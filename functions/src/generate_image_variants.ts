import { createCanvas, loadImage } from '@napi-rs/canvas';
import { randomUUID } from 'crypto';
import * as path from 'path';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { logger } from 'firebase-functions';
import { onObjectFinalized } from 'firebase-functions/v2/storage';

const PATH_RE =
  /^circles\/([^/]+)\/uploads\/([^/]+)\/([^/]+)\/([^/]+)$/;

const PREVIEW_NAME = 'preview.jpg';
const LARGE_NAME = 'large.jpg';
const PREVIEW_MAX = 320;
const LARGE_MAX = 690;

/** Server-written derivatives — never reprocess these. */
const SKIP_BASENAMES = new Set([
  'cover.jpg',
  PREVIEW_NAME,
  LARGE_NAME,
]);

function firebaseDownloadUrl(
  bucket: string,
  objectPath: string,
  token: string,
): string {
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

/** Scale down only; preserve aspect ratio within maxW × maxH. */
async function resizeToJpeg(
  bytes: Buffer,
  maxW: number,
  maxH: number,
  quality = 82,
): Promise<Buffer> {
  const img = await loadImage(bytes);
  const scale = Math.min(1, maxW / img.width, maxH / img.height);
  const w = Math.max(1, Math.round(img.width * scale));
  const h = Math.max(1, Math.round(img.height * scale));
  const canvas = createCanvas(w, h);
  const ctx = canvas.getContext('2d');
  ctx.drawImage(img, 0, 0, w, h);
  return canvas.toBuffer('image/jpeg', quality);
}

async function saveVariant(opts: {
  bucket: ReturnType<ReturnType<typeof getStorage>['bucket']>;
  bucketName: string;
  objectPath: string;
  jpeg: Buffer;
}): Promise<{ storagePath: string; downloadUrl: string }> {
  const token = randomUUID();
  await opts.bucket.file(opts.objectPath).save(opts.jpeg, {
    metadata: {
      contentType: 'image/jpeg',
      metadata: { firebaseStorageDownloadTokens: token },
    },
    resumable: false,
  });
  return {
    storagePath: opts.objectPath,
    downloadUrl: firebaseDownloadUrl(
      opts.bucketName,
      opts.objectPath,
      token,
    ),
  };
}

/**
 * On image upload, write preview.jpg (≤320) and large.jpg (≤690).
 * Stream clients load preview; detail/lightbox loads large.
 */
export const generateImageVariants = onObjectFinalized(
  {
    bucket: process.env.STORAGE_BUCKET || 'circulo-mvp.firebasestorage.app',
    memory: '1GiB',
    timeoutSeconds: 120,
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
    if (SKIP_BASENAMES.has(baseName)) {
      logger.info('Derivative object; skipping', { filePath });
      return;
    }

    if (!contentType.startsWith('image/')) {
      logger.info('Not an image; skipping', { contentType, filePath });
      return;
    }

    const match = PATH_RE.exec(filePath);
    if (!match) {
      logger.info('Path does not match uploads layout; skipping', { filePath });
      return;
    }

    const [, circleId, , postId] = match;
    const folder = path.posix.dirname(filePath);
    const previewPath = `${folder}/${PREVIEW_NAME}`;
    const largePath = `${folder}/${LARGE_NAME}`;
    const bucket = getStorage().bucket(object.bucket);
    const db = getFirestore();
    const postRef = db.doc(`circles/${circleId}/posts/${postId}`);

    try {
      const postSnap = await waitForPost(postRef);
      if (postSnap) {
        const meta = (postSnap.data()?.meta ?? {}) as Record<string, unknown>;
        if (
          meta['previewStatus'] === 'ready' &&
          meta['largeStatus'] === 'ready'
        ) {
          logger.info('Variants already ready; skipping', { postId });
          return;
        }
      }

      const [previewExists] = await bucket.file(previewPath).exists();
      const [largeExists] = await bucket.file(largePath).exists();
      if (previewExists && largeExists && postSnap) {
        logger.info('Variant files exist; refreshing meta only', { postId });
        const [pMeta] = await bucket.file(previewPath).getMetadata();
        const [lMeta] = await bucket.file(largePath).getMetadata();
        const pToken =
          (typeof pMeta.metadata?.firebaseStorageDownloadTokens === 'string' &&
            pMeta.metadata.firebaseStorageDownloadTokens) ||
          randomUUID();
        const lToken =
          (typeof lMeta.metadata?.firebaseStorageDownloadTokens === 'string' &&
            lMeta.metadata.firebaseStorageDownloadTokens) ||
          randomUUID();
        await postRef.update({
          'meta.previewStatus': 'ready',
          'meta.previewStoragePath': previewPath,
          'meta.previewDownloadUrl': firebaseDownloadUrl(
            object.bucket,
            previewPath,
            pToken,
          ),
          'meta.largeStatus': 'ready',
          'meta.largeStoragePath': largePath,
          'meta.largeDownloadUrl': firebaseDownloadUrl(
            object.bucket,
            largePath,
            lToken,
          ),
          'meta.variantsError': null,
        });
        return;
      }

      logger.info('Generating image variants', {
        filePath,
        previewPath,
        largePath,
        contentType,
      });
      const [bytes] = await bucket.file(filePath).download();

      const previewJpeg = await resizeToJpeg(bytes, PREVIEW_MAX, PREVIEW_MAX, 80);
      const largeJpeg = await resizeToJpeg(bytes, LARGE_MAX, LARGE_MAX, 85);

      const preview = await saveVariant({
        bucket,
        bucketName: object.bucket,
        objectPath: previewPath,
        jpeg: previewJpeg,
      });
      const large = await saveVariant({
        bucket,
        bucketName: object.bucket,
        objectPath: largePath,
        jpeg: largeJpeg,
      });

      const snap = await waitForPost(postRef, 5);
      if (!snap) {
        throw new Error('Post document missing; cannot update variant meta');
      }

      await postRef.update({
        'meta.previewStatus': 'ready',
        'meta.previewStoragePath': preview.storagePath,
        'meta.previewDownloadUrl': preview.downloadUrl,
        'meta.largeStatus': 'ready',
        'meta.largeStoragePath': large.storagePath,
        'meta.largeDownloadUrl': large.downloadUrl,
        'meta.variantsError': null,
      });

      logger.info('Image variants ready', {
        postId,
        previewBytes: previewJpeg.length,
        largeBytes: largeJpeg.length,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      logger.error('Image variant generation failed', {
        filePath,
        message,
        err,
      });
      try {
        const snap = await waitForPost(postRef, 3);
        if (snap) {
          await postRef.update({
            'meta.previewStatus': 'failed',
            'meta.largeStatus': 'failed',
            'meta.variantsError': message.slice(0, 200),
          });
        }
      } catch (updateErr) {
        logger.error('Failed to mark variant status failed', { updateErr });
      }
    }
  },
);
