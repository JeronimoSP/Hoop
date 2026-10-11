import { createCanvas } from '@napi-rs/canvas';
import { randomUUID } from 'crypto';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { logger } from 'firebase-functions';
import { onObjectFinalized } from 'firebase-functions/v2/storage';
import ffmpeg from 'fluent-ffmpeg';
// eslint-disable-next-line @typescript-eslint/no-require-imports
const ffmpegPath = require('ffmpeg-static') as string | null;

if (ffmpegPath) {
  ffmpeg.setFfmpegPath(ffmpegPath);
}

initializeApp();

export { notifyOnNewPost } from './notify_on_new_post.js';
export { generateImageVariants } from './generate_image_variants.js';
export {
  bootstrapCircleAgent,
  onCircleAgentPost,
  agentAction,
} from './circle_agent.js';

const PATH_RE =
  /^circles\/([^/]+)\/uploads\/([^/]+)\/([^/]+)\/([^/]+)$/;

const COVER_NAME = 'cover.jpg';
const TARGET_WIDTH = 1200;

type NodeCanvas = {
  width: number;
  height: number;
  getContext: (type: '2d') => unknown;
  toBuffer: (mime: 'image/jpeg', quality?: number) => Buffer;
};

type CanvasAndContext = {
  canvas: NodeCanvas;
  context: unknown;
};

/** Minimal CanvasFactory so pdf.js can render in Node. */
class NodeCanvasFactory {
  create(width: number, height: number): CanvasAndContext {
    const canvas = createCanvas(width, height) as unknown as NodeCanvas;
    const context = canvas.getContext('2d');
    return { canvas, context };
  }

  reset(canvasAndContext: CanvasAndContext, width: number, height: number): void {
    canvasAndContext.canvas.width = width;
    canvasAndContext.canvas.height = height;
  }

  destroy(canvasAndContext: CanvasAndContext): void {
    canvasAndContext.canvas.width = 0;
    canvasAndContext.canvas.height = 0;
  }
}

async function renderPdfCover(pdfBytes: Buffer): Promise<Buffer> {
  const mod = await import('pdfjs-dist/legacy/build/pdf.mjs');
  const pdfjs = mod as {
    getDocument?: unknown;
    default?: { getDocument: unknown };
  };
  const getDocument = (pdfjs.getDocument ?? pdfjs.default?.getDocument) as (
    src: unknown,
  ) => {
    promise: Promise<{
      getPage: (n: number) => Promise<{
        getViewport: (p: { scale: number }) => { width: number; height: number };
        render: (p: Record<string, unknown>) => { promise: Promise<void> };
      }>;
      destroy: () => Promise<void>;
    }>;
  };

  const canvasFactory = new NodeCanvasFactory();
  const loadingTask = getDocument({
    data: new Uint8Array(pdfBytes),
    canvasFactory,
    disableFontFace: true,
    useSystemFonts: true,
  });
  const pdf = await loadingTask.promise;
  try {
    const page = await pdf.getPage(1);
    const base = page.getViewport({ scale: 1 });
    const scale = Math.min(TARGET_WIDTH / base.width, 2);
    const viewport = page.getViewport({ scale });
    const canvasAndContext = canvasFactory.create(
      Math.ceil(viewport.width),
      Math.ceil(viewport.height),
    );
    await page
      .render({
        canvasContext: canvasAndContext.context,
        viewport,
        canvasFactory,
      })
      .promise;
    const jpeg = canvasAndContext.canvas.toBuffer('image/jpeg', 85);
    canvasFactory.destroy(canvasAndContext);
    return jpeg;
  } finally {
    await pdf.destroy();
  }
}

async function renderVideoCover(videoBytes: Buffer, ext: string): Promise<Buffer> {
  const tmpDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'circulo-vid-'));
  const inPath = path.join(tmpDir, `input${ext || '.mp4'}`);
  const outPath = path.join(tmpDir, 'cover.jpg');
  try {
    await fs.promises.writeFile(inPath, videoBytes);
    await new Promise<void>((resolve, reject) => {
      ffmpeg(inPath)
        .on('end', () => resolve())
        .on('error', (err: Error) => reject(err))
        .screenshots({
          count: 1,
          timemarks: ['0.1'],
          filename: 'cover.jpg',
          folder: tmpDir,
          size: `${TARGET_WIDTH}x?`,
        });
    });
    return await fs.promises.readFile(outPath);
  } finally {
    await fs.promises.rm(tmpDir, { recursive: true, force: true });
  }
}

function firebaseDownloadUrl(bucket: string, objectPath: string, token: string): string {
  const encoded = encodeURIComponent(objectPath);
  return (
    `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encoded}` +
    `?alt=media&token=${token}`
  );
}

async function waitForPost(
  postRef: ReturnType<ReturnType<typeof getFirestore>['doc']>,
  attempts = 10,
) {
  for (let i = 0; i < attempts; i++) {
    const snap = await postRef.get();
    if (snap.exists) return snap;
    await new Promise((r) => setTimeout(r, 400 * (i + 1)));
  }
  return null;
}

async function updateCoverMeta(
  postRef: ReturnType<ReturnType<typeof getFirestore>['doc']>,
  fields: Record<string, unknown>,
): Promise<void> {
  const snap = await waitForPost(postRef, 5);
  if (!snap) {
    throw new Error('Post document missing; cannot update cover meta');
  }
  await postRef.update(fields);
}

async function saveCoverAndUpdateMeta(opts: {
  bucketName: string;
  coverPath: string;
  jpeg: Buffer;
  postRef: ReturnType<ReturnType<typeof getFirestore>['doc']>;
  bucket: ReturnType<ReturnType<typeof getStorage>['bucket']>;
}): Promise<void> {
  const token = randomUUID();
  await opts.bucket.file(opts.coverPath).save(opts.jpeg, {
    metadata: {
      contentType: 'image/jpeg',
      metadata: { firebaseStorageDownloadTokens: token },
    },
    resumable: false,
  });
  await updateCoverMeta(opts.postRef, {
    'meta.coverStatus': 'ready',
    'meta.coverStoragePath': opts.coverPath,
    'meta.coverDownloadUrl': firebaseDownloadUrl(
      opts.bucketName,
      opts.coverPath,
      token,
    ),
    'meta.coverError': null,
  });
}

/** PDF page-1 and video first-frame covers. */
export const generatePdfCover = onObjectFinalized(
  {
    bucket: process.env.STORAGE_BUCKET || 'circulo-mvp.firebasestorage.app',
    memory: '2GiB',
    timeoutSeconds: 180,
    cpu: 1,
  },
  async (event) => {
    const object = event.data;
    const filePath = object.name;
    const contentType = object.contentType ?? '';

    if (!filePath) {
      logger.info('No object name; skipping');
      return;
    }

    const baseName = path.posix.basename(filePath).toLowerCase();
    if (
      baseName.startsWith('cover.') ||
      baseName === 'preview.jpg' ||
      baseName === 'large.jpg'
    ) {
      logger.info('Derivative object; skipping', { filePath });
      return;
    }

    const isPdf = contentType === 'application/pdf';
    const isVideo = contentType.startsWith('video/');
    if (!isPdf && !isVideo) {
      logger.info('Not PDF/video; skipping', { contentType, filePath });
      return;
    }

    const match = PATH_RE.exec(filePath);
    if (!match) {
      logger.info('Path does not match uploads layout; skipping', { filePath });
      return;
    }

    const [, circleId, , postId] = match;
    const folder = path.posix.dirname(filePath);
    const coverPath = `${folder}/${COVER_NAME}`;
    const bucket = getStorage().bucket(object.bucket);
    const db = getFirestore();
    const postRef = db.doc(`circles/${circleId}/posts/${postId}`);

    try {
      const postSnap = await waitForPost(postRef);
      if (postSnap) {
        const meta = (postSnap.data()?.meta ?? {}) as Record<string, unknown>;
        if (meta['coverStatus'] === 'ready') {
          logger.info('Cover already ready; skipping', { postId });
          return;
        }
      } else {
        logger.warn('Post still missing after retries; generating cover file', {
          circleId,
          postId,
        });
      }

      const [coverExists] = await bucket.file(coverPath).exists();
      if (coverExists) {
        logger.info('Cover file already exists; refreshing meta', { coverPath });
        const [meta] = await bucket.file(coverPath).getMetadata();
        const existing = meta.metadata?.firebaseStorageDownloadTokens;
        const token =
          typeof existing === 'string' && existing.length > 0
            ? existing
            : randomUUID();
        if (token !== existing) {
          await bucket.file(coverPath).setMetadata({
            metadata: { firebaseStorageDownloadTokens: token },
          });
        }
        await updateCoverMeta(postRef, {
          'meta.coverStatus': 'ready',
          'meta.coverStoragePath': coverPath,
          'meta.coverDownloadUrl': firebaseDownloadUrl(
            object.bucket,
            coverPath,
            token,
          ),
          'meta.coverError': null,
        });
        return;
      }

      logger.info('Generating cover', { filePath, coverPath, contentType });
      const [bytes] = await bucket.file(filePath).download();
      let jpeg: Buffer;
      if (isPdf) {
        jpeg = await renderPdfCover(bytes);
      } else {
        const ext = path.posix.extname(filePath) || '.mp4';
        jpeg = await renderVideoCover(bytes, ext);
      }

      await saveCoverAndUpdateMeta({
        bucketName: object.bucket,
        coverPath,
        jpeg,
        postRef,
        bucket,
      });

      logger.info('Cover ready', { postId, coverPath });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      logger.error('Cover generation failed', { filePath, message, err });
      try {
        await updateCoverMeta(postRef, {
          'meta.coverStatus': 'failed',
          'meta.coverError': message.slice(0, 200),
        });
      } catch (updateErr) {
        logger.error('Failed to mark coverStatus failed', { updateErr });
      }
    }
  },
);
