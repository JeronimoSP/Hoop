import { randomUUID } from 'crypto';
import { Agent, CursorAgentError } from '@cursor/sdk';
import {
  FieldValue,
  getFirestore,
  type DocumentData,
  type Firestore,
} from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { defineSecret, defineString } from 'firebase-functions/params';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

const cursorApiKey = defineSecret('CURSOR_API_KEY');
const githubRepo = defineString('GITHUB_REPO', { default: '' });
const agentUserIdParam = defineString('AGENT_USER_ID', { default: '' });
const agentEmailParam = defineString('AGENT_EMAIL', {
  default: 'agent@circulo.app',
});
const agentModelId = defineString('AGENT_MODEL_ID', {
  default: 'composer-2.5',
});

const REGION = 'us-east1';
const RECENT_POSTS = 12;

type AgentAction = { id: string; label: string };

const DEFAULT_ACTIONS: AgentAction[] = [
  { id: 'continue', label: 'Continue' },
  { id: 'open_pr', label: 'Open PR' },
  { id: 'retry', label: 'Retry' },
];

async function resolveAgentUid(db: Firestore): Promise<string> {
  const configured = agentUserIdParam.value().trim();
  if (configured) return configured;

  const email = agentEmailParam.value().trim().toLowerCase();
  const q = await db
    .collection('users')
    .where('email', '==', email)
    .where('isAgent', '==', true)
    .limit(1)
    .get();
  if (!q.empty) return q.docs[0].id;

  throw new Error(
    `Agent user not found for ${email}. Run bootstrapCircleAgent first.`,
  );
}

function githubRepoUrl(): string {
  const raw = githubRepo.value().trim();
  if (!raw) {
    throw new Error('GITHUB_REPO param is not set (owner/repo or full URL).');
  }
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  return `https://github.com/${raw}`;
}

function postTextPreview(data: DocumentData): string {
  const body = ((data.body as string) || '').trim();
  if (body) return body.length > 200 ? `${body.slice(0, 197)}…` : body;
  const type = (data.type as string) || 'free';
  const kind = (data.meta as { kind?: string } | undefined)?.kind;
  if (type === 'media') return `[media:${kind || 'file'}]`;
  return `[${type}]`;
}

function buildPrompt(opts: {
  circleId: string;
  triggerBody: string;
  recent: Array<{ authorId: string; text: string }>;
  mode: 'new' | 'continue' | 'retry';
}): string {
  const recentBlock = opts.recent
    .map((p, i) => `${i + 1}. (${p.authorId}) ${p.text}`)
    .join('\n');
  const modeLine =
    opts.mode === 'continue'
      ? 'Continue from your last result on this repo. Apply the next reasonable steps.'
      : opts.mode === 'retry'
        ? 'Retry the previous request; previous run failed or was incomplete.'
        : 'Handle the triggering circle message as a coding task on this repository.';

  return [
    'You are the Hoop Agent for the Hoop Flutter/Firebase app.',
    modeLine,
    `Hoop id: ${opts.circleId}`,
    '',
    'Recent circle posts (oldest → newest, text only):',
    recentBlock || '(none)',
    '',
    'Triggering message:',
    opts.triggerBody || '(empty)',
    '',
    'When done, summarize what you changed and include any PR URL in your final reply.',
    'Keep the summary concise and suitable to post back into a chat thread.',
  ].join('\n');
}

async function loadRecentPosts(
  db: Firestore,
  circleId: string,
): Promise<Array<{ authorId: string; text: string }>> {
  const snap = await db
    .collection('circles')
    .doc(circleId)
    .collection('posts')
    .orderBy('createdAt', 'desc')
    .limit(RECENT_POSTS)
    .get();
  return snap.docs
    .slice()
    .reverse()
    .map((d) => {
      const data = d.data();
      return {
        authorId: (data.authorId as string) || '',
        text: postTextPreview(data),
      };
    });
}

async function writeAgentPost(opts: {
  db: Firestore;
  circleId: string;
  agentUid: string;
  body: string;
  jobId: string;
  prUrl?: string | null;
  actions?: AgentAction[];
}): Promise<string> {
  const postRef = opts.db
    .collection('circles')
    .doc(opts.circleId)
    .collection('posts')
    .doc();
  const now = FieldValue.serverTimestamp();
  const preview =
    opts.body.length > 80 ? `${opts.body.slice(0, 77)}…` : opts.body;
  const actions = opts.actions ?? DEFAULT_ACTIONS;
  await postRef.set({
    authorId: opts.agentUid,
    type: 'free',
    body: opts.body,
    meta: {
      agent: {
        jobId: opts.jobId,
        prUrl: opts.prUrl ?? null,
        actions,
      },
      agentActions: actions,
    },
    createdAt: now,
  });
  await opts.db.doc(`circles/${opts.circleId}`).set(
    {
      lastPost: {
        body: preview,
        type: 'free',
        authorId: opts.agentUid,
        createdAt: now,
      },
      updatedAt: now,
    },
    { merge: true },
  );
  return postRef.id;
}

function prUrlFromResult(result: {
  git?: { branches?: Array<{ prUrl?: string }> };
}): string | null {
  const branches = result.git?.branches ?? [];
  for (const b of branches) {
    if (b.prUrl) return b.prUrl;
  }
  return null;
}

async function runCursorJob(opts: {
  db: Firestore;
  circleId: string;
  agentUid: string;
  jobId: string;
  prompt: string;
  resumeAgentId?: string | null;
  apiKey: string;
}): Promise<void> {
  const jobRef = opts.db
    .collection('circles')
    .doc(opts.circleId)
    .collection('agentJobs')
    .doc(opts.jobId);

  await jobRef.set(
    {
      status: 'running',
      updatedAt: FieldValue.serverTimestamp(),
      prompt: opts.prompt,
      error: null,
    },
    { merge: true },
  );

  let agent: Awaited<ReturnType<typeof Agent.create>> | null = null;
  try {
    if (opts.resumeAgentId) {
      agent = await Agent.resume(opts.resumeAgentId, { apiKey: opts.apiKey });
    } else {
      agent = await Agent.create({
        apiKey: opts.apiKey,
        model: { id: agentModelId.value() },
        cloud: {
          repos: [{ url: githubRepoUrl() }],
          autoCreatePR: true,
          skipReviewerRequest: true,
        },
      });
    }

    const agentId = agent.agentId;
    await jobRef.set(
      {
        cursorAgentId: agentId,
        status: 'running',
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    const run = await agent.send(opts.prompt);
    await jobRef.set(
      {
        runId: run.id,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    const result = await run.wait();
    const prUrl = prUrlFromResult(result);

    if (result.status === 'error') {
      const errMsg =
        result.error?.message || `Cursor run failed (${result.id})`;
      await jobRef.set(
        {
          status: 'failed',
          error: errMsg.slice(0, 500),
          prUrl: prUrl ?? null,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      await writeAgentPost({
        db: opts.db,
        circleId: opts.circleId,
        agentUid: opts.agentUid,
        body: `I hit an error on that run. You can Retry or Continue.\n\n${errMsg}`,
        jobId: opts.jobId,
        prUrl,
      });
      return;
    }

    let summary = (result.result || '').trim();
    if (!summary) {
      summary = prUrl
        ? `Done. Open PR: ${prUrl}`
        : 'Done. Review the cloud agent run for details.';
    }
    if (prUrl && !summary.includes(prUrl)) {
      summary = `${summary.trim()}\n\nPR: ${prUrl}`;
    }

    await jobRef.set(
      {
        status: 'completed',
        prUrl: prUrl ?? null,
        error: null,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await writeAgentPost({
      db: opts.db,
      circleId: opts.circleId,
      agentUid: opts.agentUid,
      body: summary.slice(0, 4000),
      jobId: opts.jobId,
      prUrl,
    });
  } catch (err) {
    const message =
      err instanceof CursorAgentError
        ? err.message
        : err instanceof Error
          ? err.message
          : String(err);
    logger.error('Hoop agent job failed', { err: message, jobId: opts.jobId });
    await jobRef.set(
      {
        status: 'failed',
        error: message.slice(0, 500),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await writeAgentPost({
      db: opts.db,
      circleId: opts.circleId,
      agentUid: opts.agentUid,
      body: `Agent run failed: ${message.slice(0, 400)}\n\nUse Retry to try again.`,
      jobId: opts.jobId,
    });
  } finally {
    if (agent) {
      try {
        await agent[Symbol.asyncDispose]();
      } catch {
        // ignore dispose errors
      }
    }
  }
}

/** Ensure the synthetic Hoop Agent user exists (callable, platform admin). */
export const bootstrapCircleAgent = onCall(
  {
    region: REGION,
    secrets: [cursorApiKey],
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'Sign in required.');
    }
    const db = getFirestore();
    const caller = await db.doc(`users/${request.auth.uid}`).get();
    if (caller.data()?.isPlatformAdmin !== true) {
      throw new HttpsError('permission-denied', 'Platform admin required.');
    }

    const email = agentEmailParam.value().trim().toLowerCase();
    const existing = await db
      .collection('users')
      .where('email', '==', email)
      .limit(1)
      .get();

    if (!existing.empty) {
      const doc = existing.docs[0];
      await doc.ref.set(
        {
          isAgent: true,
          isPlatformAdmin: false,
          name: 'Hoop Agent',
          alias: 'Agent',
          email,
        },
        { merge: true },
      );
      return { uid: doc.id, email, created: false };
    }

    const uid = `agent_${randomUUID().replace(/-/g, '').slice(0, 20)}`;
    await db.doc(`users/${uid}`).set({
      email,
      name: 'Hoop Agent',
      alias: 'Agent',
      isAgent: true,
      isPlatformAdmin: false,
      googlePhotoURL: null,
      customPhotoURL: null,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { uid, email, created: true };
  },
);

/** When a member posts in a circle that includes the agent, run Cursor cloud. */
export const onCircleAgentPost = onDocumentCreated(
  {
    document: 'circles/{circleId}/posts/{postId}',
    region: REGION,
    secrets: [cursorApiKey],
    timeoutSeconds: 540,
    memory: '1GiB',
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const circleId = event.params.circleId as string;
    const postId = event.params.postId as string;
    const data = snap.data();
    const authorId = (data.authorId as string) || '';
    if (!authorId) return;

    // Skip agent action meta-only echoes / system noise later if needed.
    if ((data.meta as { agentActionEcho?: boolean } | undefined)?.agentActionEcho) {
      return;
    }

    const db = getFirestore();
    let agentUid: string;
    try {
      agentUid = await resolveAgentUid(db);
    } catch (err) {
      logger.info('Agent user missing; skip', { err });
      return;
    }

    if (authorId === agentUid) {
      return;
    }

    const membershipId = `${circleId}_${agentUid}`;
    const membership = await db.doc(`memberships/${membershipId}`).get();
    if (!membership.exists) {
      logger.info('Agent not a member; skip', { circleId });
      return;
    }

    const recent = await loadRecentPosts(db, circleId);
    const prompt = buildPrompt({
      circleId,
      triggerBody: postTextPreview(data),
      recent,
      mode: 'new',
    });

    const jobId = randomUUID();
    await db
      .collection('circles')
      .doc(circleId)
      .collection('agentJobs')
      .doc(jobId)
      .set({
        status: 'queued',
        triggerPostId: postId,
        authorId,
        cursorAgentId: null,
        runId: null,
        prUrl: null,
        error: null,
        prompt,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

    await runCursorJob({
      db,
      circleId,
      agentUid,
      jobId,
      prompt,
      apiKey: cursorApiKey.value(),
    });
  },
);

/** Continue / Retry from agent reply buttons. Open PR is client-side. */
export const agentAction = onCall(
  {
    region: REGION,
    secrets: [cursorApiKey],
    timeoutSeconds: 540,
    memory: '1GiB',
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'Sign in required.');
    }

    const circleId = String(request.data?.circleId || '').trim();
    const postId = String(request.data?.postId || '').trim();
    const actionId = String(request.data?.actionId || '').trim();
    const followUp = String(request.data?.followUp || '').trim();

    if (!circleId || !postId || !actionId) {
      throw new HttpsError(
        'invalid-argument',
        'circleId, postId, and actionId are required.',
      );
    }

    const db = getFirestore();
    const membership = await db
      .doc(`memberships/${circleId}_${request.auth.uid}`)
      .get();
    if (!membership.exists) {
      throw new HttpsError('permission-denied', 'Not a circle member.');
    }

    if (actionId === 'open_pr') {
      const post = await db.doc(`circles/${circleId}/posts/${postId}`).get();
      const meta = (post.data()?.meta || {}) as {
        agent?: { prUrl?: string; jobId?: string };
      };
      let prUrl = meta.agent?.prUrl || null;
      if (!prUrl && meta.agent?.jobId) {
        const job = await db
          .doc(`circles/${circleId}/agentJobs/${meta.agent.jobId}`)
          .get();
        prUrl = (job.data()?.prUrl as string) || null;
      }
      return { ok: true, actionId, prUrl };
    }

    if (actionId !== 'continue' && actionId !== 'retry') {
      throw new HttpsError('invalid-argument', `Unknown action: ${actionId}`);
    }

    const agentUid = await resolveAgentUid(db);
    const agentMembership = await db
      .doc(`memberships/${circleId}_${agentUid}`)
      .get();
    if (!agentMembership.exists) {
      throw new HttpsError('failed-precondition', 'Agent is not in this circle.');
    }

    const post = await db.doc(`circles/${circleId}/posts/${postId}`).get();
    if (!post.exists) {
      throw new HttpsError('not-found', 'Post not found.');
    }
    const meta = (post.data()?.meta || {}) as {
      agent?: { jobId?: string; prUrl?: string };
    };
    const priorJobId = meta.agent?.jobId;
    let resumeAgentId: string | null = null;
    let priorPrompt = '';
    if (priorJobId) {
      const prior = await db
        .doc(`circles/${circleId}/agentJobs/${priorJobId}`)
        .get();
      resumeAgentId = (prior.data()?.cursorAgentId as string) || null;
      priorPrompt = (prior.data()?.prompt as string) || '';
    }

    const recent = await loadRecentPosts(db, circleId);
    const mode = actionId === 'continue' ? 'continue' : 'retry';
    const triggerBody =
      followUp ||
      (actionId === 'continue'
        ? 'Continue from last result'
        : priorPrompt || 'Retry last agent task');
    const prompt = buildPrompt({
      circleId,
      triggerBody,
      recent,
      mode,
    });

    const jobId = randomUUID();
    await db
      .collection('circles')
      .doc(circleId)
      .collection('agentJobs')
      .doc(jobId)
      .set({
        status: 'queued',
        triggerPostId: postId,
        authorId: request.auth.uid,
        actionId,
        parentJobId: priorJobId || null,
        cursorAgentId: resumeAgentId,
        runId: null,
        prUrl: null,
        error: null,
        prompt,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

    // Resume on continue when we have an agent id; retry starts fresh on failure.
    const useResume =
      actionId === 'continue' && !!resumeAgentId
        ? resumeAgentId
        : actionId === 'retry'
          ? null
          : resumeAgentId;

    await runCursorJob({
      db,
      circleId,
      agentUid,
      jobId,
      prompt,
      resumeAgentId: useResume,
      apiKey: cursorApiKey.value(),
    });

    return { ok: true, actionId, jobId };
  },
);
