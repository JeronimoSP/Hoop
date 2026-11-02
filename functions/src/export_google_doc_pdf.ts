import { randomUUID } from 'crypto';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { logger } from 'firebase-functions';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';

const MAX_PDF_BYTES = 20 * 1024 * 1024;
const DOC_ID_RE = /\/document\/d\/([a-zA-Z0-9_-]+)/;

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

function parseDocFileId(url: string): string | null {
  const m = DOC_ID_RE.exec(url);
  return m?.[1] ?? null;
}

function isPdfBuffer(buf: Buffer): boolean {
  if (buf.length < 5) return false;
  return buf.subarray(0, 5).toString('utf8') === '%PDF-';
}

/** Export a publicly shared Google Doc resource to PDF and rewrite the post. */
export const exportGoogleDocPdf = onDocumentCreated(
  {
    document: 'circles/{circleId}/posts/{postId}',
    region: 'us-east1',
    memory: '1GiB',
    timeoutSeconds: 120,
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const circleId = event.params.circleId as string;
    const postId = event.params.postId as string;
    const data = snap.data();
    const type = (data.type as string) || '';
    const meta = (data.meta ?? {}) as Record<string, unknown>;
    const kind = (meta.kind as string) || '';
    const exportStatus = (meta.exportStatus as string) || '';

    if (type !== 'resource' || kind !== 'googleDoc') {
      return;
    }
    if (exportStatus === 'ready') {
      logger.info('Google Doc already exported; skip', { circleId, postId });
      return;
    }

    const sourceUrl =
      ((meta.url as string) || '').trim() ||
      ((data.body as string) || '').trim();
    const fileId = parseDocFileId(sourceUrl);
    const postRef = snap.ref;
    const authorId = (data.authorId as string) || '';

    if (!fileId) {
      logger.warn('Could not parse Google Doc file id', { sourceUrl });
      await postRef.update({
        'meta.exportStatus': 'failed',
        'meta.exportError':
          'Invalid Google Docs URL. Use docs.google.com/document/d/…',
      });
      return;
    }
    if (!authorId) {
      await postRef.update({
        'meta.exportStatus': 'failed',
        'meta.exportError': 'Post missing authorId',
      });
      return;
    }

    const exportUrl = `https://docs.google.com/document/d/${fileId}/export?format=pdf`;
    let pdfBytes: Buffer;
    try {
      const res = await fetch(exportUrl, {
        redirect: 'follow',
        headers: { Accept: 'application/pdf,*/*' },
      });
      if (!res.ok) {
        throw new Error(`Export HTTP ${res.status}`);
      }
      const ab = await res.arrayBuffer();
      pdfBytes = Buffer.from(ab);
      const contentType = (res.headers.get('content-type') || '').toLowerCase();
      if (
        !isPdfBuffer(pdfBytes) ||
        contentType.includes('text/html') ||
        contentType.includes('text/plain')
      ) {
        throw new Error(
          'Doc is not publicly shared (Anyone with the link) or export failed',
        );
      }
      if (pdfBytes.length > MAX_PDF_BYTES) {
        throw new Error('Exported PDF exceeds the 20 MB limit');
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      logger.error('Google Doc export failed', { circleId, postId, message });
      await postRef.update({
        'meta.exportStatus': 'failed',
        'meta.exportError': message,
      });
      return;
    }

    const storagePath = `circles/${circleId}/uploads/${authorId}/${postId}/document.pdf`;
    const bucket = getStorage().bucket();
    const token = randomUUID();
    await bucket.file(storagePath).save(pdfBytes, {
      metadata: {
        contentType: 'application/pdf',
        metadata: { firebaseStorageDownloadTokens: token },
      },
      resumable: false,
    });

    const downloadUrl = firebaseDownloadUrl(
      bucket.name,
      storagePath,
      token,
    );

    await postRef.update({
      'meta.kind': 'pdf',
      'meta.storagePath': storagePath,
      'meta.downloadUrl': downloadUrl,
      'meta.contentType': 'application/pdf',
      'meta.fileName': 'document.pdf',
      'meta.byteSize': pdfBytes.length,
      'meta.coverStatus': 'pending',
      'meta.exportStatus': 'ready',
      'meta.sourceUrl': sourceUrl,
      'meta.exportError': null,
      'meta.url': null,
    });

    // Keep home preview in sync when body was only the Doc URL.
    const body = ((data.body as string) || '').trim();
    if (!body || body === sourceUrl) {
      await getFirestore().doc(`circles/${circleId}`).update({
        'lastPost.body': 'PDF',
        'lastPost.kind': 'pdf',
        'lastPost.type': 'resource',
      });
    } else {
      await getFirestore().doc(`circles/${circleId}`).update({
        'lastPost.kind': 'pdf',
        'lastPost.type': 'resource',
      });
    }

    logger.info('Google Doc exported to PDF', {
      circleId,
      postId,
      storagePath,
      bytes: pdfBytes.length,
    });
  },
);
