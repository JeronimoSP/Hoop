import {
  FieldValue,
  getFirestore,
  type DocumentData,
  type DocumentReference,
} from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';

function postPreview(data: DocumentData): string {
  const type = (data.type as string) || 'free';
  const body = ((data.body as string) || '').trim();
  const kind = (data.meta as { kind?: string } | undefined)?.kind;
  if (body) {
    return body.length > 80 ? `${body.slice(0, 77)}…` : body;
  }
  if (type === 'media') {
    switch (kind) {
      case 'pdf':
        return 'PDF';
      case 'audio':
        return 'Audio';
      case 'video':
        return 'Video';
      default:
        return 'Image';
    }
  }
  if (type === 'instruction') return 'Instruction';
  if (type === 'resource') return 'Resource';
  return 'New message';
}

/** Notify circle members (except author) when a post is created. */
export const notifyOnNewPost = onDocumentCreated(
  {
    document: 'circles/{circleId}/posts/{postId}',
    region: 'us-east1',
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const circleId = event.params.circleId as string;
    const postId = event.params.postId as string;
    const data = snap.data();
    const authorId = (data.authorId as string) || '';
    if (!authorId) {
      logger.warn('Post missing authorId; skip notify', { circleId, postId });
      return;
    }

    const db = getFirestore();
    const circleSnap = await db.doc(`circles/${circleId}`).get();
    const circleName =
      (circleSnap.data()?.name as string | undefined)?.trim() || 'Hoop';
    const bodyText = postPreview(data);

    const memberships = await db
      .collection('memberships')
      .where('circleId', '==', circleId)
      .get();

    const recipientIds = memberships.docs
      .map((d) => d.data().userId as string)
      .filter((id) => id && id !== authorId);

    if (recipientIds.length === 0) {
      logger.info('No recipients for post notify', { circleId, postId });
      return;
    }

    // Denormalized unread badges on Hoops home (exclude author).
    const unreadBatch = db.batch();
    for (const uid of recipientIds) {
      const mid = `${circleId}_${uid}`;
      unreadBatch.set(
        db.collection('memberships').doc(mid),
        { unreadCount: FieldValue.increment(1) },
        { merge: true },
      );
    }
    await unreadBatch.commit();
    logger.info('Unread counts incremented', {
      circleId,
      postId,
      recipients: recipientIds.length,
    });

    const tokens: string[] = [];
    const tokenRefs: DocumentReference[] = [];

    await Promise.all(
      recipientIds.map(async (uid) => {
        const tokenSnap = await db
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .get();
        for (const doc of tokenSnap.docs) {
          const token = doc.data().token as string | undefined;
          if (token) {
            tokens.push(token);
            tokenRefs.push(doc.ref);
          }
        }
      }),
    );

    if (tokens.length === 0) {
      logger.info('No FCM tokens for recipients', { circleId, postId });
      return;
    }

    const messaging = getMessaging();
    const chunkSize = 500;
    for (let i = 0; i < tokens.length; i += chunkSize) {
      const chunk = tokens.slice(i, i + chunkSize);
      const refs = tokenRefs.slice(i, i + chunkSize);
      const response = await messaging.sendEachForMulticast({
        tokens: chunk,
        notification: {
          title: circleName,
          body: bodyText,
        },
        data: {
          circleId,
          postId,
        },
        webpush: {
          fcmOptions: {
            link: `https://circulo-mvp.web.app/circles/${circleId}`,
          },
        },
      });

      const deletes: Promise<unknown>[] = [];
      response.responses.forEach((res, idx) => {
        if (res.success) return;
        const code = res.error?.code || '';
        logger.warn('FCM send failed', {
          code,
          message: res.error?.message,
        });
        if (
          code === 'messaging/registration-token-not-registered' ||
          code === 'messaging/invalid-registration-token'
        ) {
          deletes.push(refs[idx].delete());
        }
      });
      await Promise.all(deletes);
      logger.info('FCM multicast done', {
        circleId,
        postId,
        sent: response.successCount,
        failed: response.failureCount,
      });
    }
  },
);
