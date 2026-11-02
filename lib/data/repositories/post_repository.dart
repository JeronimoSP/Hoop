import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/post.dart';
import 'auth_repository.dart';
import 'media_repository.dart';

final postRepositoryProvider = Provider<PostRepository>((ref) {
  return PostRepository(
    ref.watch(firestoreProvider),
    ref.watch(mediaRepositoryProvider),
  );
});

final postReactionsProvider = StreamProvider.autoDispose
    .family<ReactionSummary, ({String circleId, String postId, String? uid})>(
        (ref, key) {
  return ref.watch(postRepositoryProvider).watchReactionSummary(
        circleId: key.circleId,
        postId: key.postId,
        myUserId: key.uid,
      );
});

class PostRepository {
  PostRepository(this._db, this._media);

  final FirebaseFirestore _db;
  final MediaRepository _media;

  CollectionReference<Map<String, dynamic>> _posts(String circleId) =>
      _db.collection('circles').doc(circleId).collection('posts');

  CollectionReference<Map<String, dynamic>> _reactions(
    String circleId,
    String postId,
  ) =>
      _posts(circleId).doc(postId).collection('reactions');

  Stream<List<CirclePost>> watchPosts(String circleId) {
    return _posts(circleId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => CirclePost.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  Stream<ReactionSummary> watchReactionSummary({
    required String circleId,
    required String postId,
    String? myUserId,
  }) {
    // Local / pending posts have no Firestore reactions.
    if (postId.startsWith('local-')) {
      return Stream.value(const ReactionSummary(counts: {}));
    }
    return _reactions(circleId, postId).snapshots().map((snap) {
      final list = snap.docs
          .map((d) => PostReaction.fromMap(d.id, d.data()))
          .toList();
      return ReactionSummary.fromReactions(list, myUserId: myUserId);
    });
  }

  /// Deletes a post and its reactions (circle admin only; enforced by rules).
  Future<void> deletePost({
    required String circleId,
    required String postId,
  }) async {
    if (postId.startsWith('local-')) return;
    final postRef = _posts(circleId).doc(postId);
    final reactions = await _reactions(circleId, postId).get();
    var batch = _db.batch();
    var ops = 0;
    for (final doc in reactions.docs) {
      batch.delete(doc.reference);
      ops++;
      if (ops >= 450) {
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }
    }
    batch.delete(postRef);
    await batch.commit();
  }

  /// Sets or clears the caller's reaction (one emoji per user).
  Future<void> toggleReaction({
    required String circleId,
    required String postId,
    required String userId,
    required String emoji,
  }) async {
    final ref = _reactions(circleId, postId).doc(userId);
    final existing = await ref.get();
    if (existing.exists &&
        (existing.data()?['emoji'] as String? ?? '') == emoji) {
      await ref.delete();
      return;
    }
    await ref.set({
      'userId': userId,
      'emoji': emoji,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> sendPost({
    required String circleId,
    required String authorId,
    required PostType type,
    required String body,
    Map<String, dynamic> meta = const {},
    PostReplyTo? replyTo,
  }) async {
    final trimmed = body.trim();
    final effectiveMeta = Map<String, dynamic>.from(meta);
    if (looksLikeEmojiOnly(trimmed) &&
        type != PostType.instruction &&
        type != PostType.resource) {
      effectiveMeta['kind'] = 'emoji';
    }

    final batch = _db.batch();
    final postRef = _posts(circleId).doc();
    final now = FieldValue.serverTimestamp();
    final typeName = type.name;
    final previewBody = lastPostPreviewBody(
      type: typeName,
      body: trimmed,
      kind: effectiveMeta['kind']?.toString(),
    );

    batch.set(postRef, {
      'authorId': authorId,
      'type': typeName,
      'body': trimmed,
      'meta': effectiveMeta,
      if (replyTo != null) 'replyTo': replyTo.toMap(),
      'createdAt': now,
      'status': 'sent',
    });

    batch.update(_db.collection('circles').doc(circleId), {
      'lastPost': {
        'type': typeName,
        'body': previewBody,
        if (effectiveMeta['kind'] != null) 'kind': effectiveMeta['kind'],
        'authorId': authorId,
        'createdAt': now,
      },
      'updatedAt': now,
    });

    await batch.commit();
    return postRef.id;
  }

  Future<void> sendEmojiPost({
    required String circleId,
    required String authorId,
    required String emoji,
    PostReplyTo? replyTo,
  }) {
    return sendPost(
      circleId: circleId,
      authorId: authorId,
      type: PostType.free,
      body: emoji.trim(),
      meta: const {'kind': 'emoji'},
      replyTo: replyTo,
    );
  }

  Future<void> sendMediaPost({
    required String circleId,
    required String authorId,
    required PickedImage image,
    String caption = '',
    PostReplyTo? replyTo,
  }) async {
    final postRef = _posts(circleId).doc();
    final postId = postRef.id;

    final uploaded = await _media.uploadCircleImage(
      circleId: circleId,
      userId: authorId,
      postId: postId,
      image: image,
    );

    final now = FieldValue.serverTimestamp();
    final body = caption.trim();
    final meta = <String, dynamic>{
      'kind': 'image',
      'storagePath': uploaded.storagePath,
      'downloadUrl': uploaded.downloadUrl,
      'contentType': image.contentType,
      'fileName': image.fileName,
      'byteSize': image.bytes.length,
      'previewStatus': 'pending',
      'largeStatus': 'pending',
    };

    final batch = _db.batch();
    batch.set(postRef, {
      'authorId': authorId,
      'type': PostType.media.name,
      'body': body,
      'meta': meta,
      if (replyTo != null) 'replyTo': replyTo.toMap(),
      'createdAt': now,
      'status': 'sent',
    });

    batch.update(_db.collection('circles').doc(circleId), {
      'lastPost': {
        'type': PostType.media.name,
        'body': lastPostPreviewBody(
          type: PostType.media.name,
          body: body,
          kind: 'image',
        ),
        'kind': 'image',
        'authorId': authorId,
        'createdAt': now,
      },
      'updatedAt': now,
    });

    await batch.commit();
  }

  /// Returns post id and the written [meta] (for library mirror / linking).
  Future<({String postId, Map<String, dynamic> meta})> sendPdfPost({
    required String circleId,
    required String authorId,
    required PickedFileBytes pdf,
    String caption = '',
    PostReplyTo? replyTo,
    PostType type = PostType.media,
  }) async {
    final postRef = _posts(circleId).doc();
    final postId = postRef.id;

    final uploaded = await _media.uploadCircleFile(
      circleId: circleId,
      userId: authorId,
      postId: postId,
      file: pdf,
    );

    final now = FieldValue.serverTimestamp();
    final body = caption.trim();
    final typeName = type.name;
    final meta = <String, dynamic>{
      'kind': 'pdf',
      'storagePath': uploaded.storagePath,
      'downloadUrl': uploaded.downloadUrl,
      'contentType': pdf.contentType,
      'fileName': pdf.fileName,
      'byteSize': pdf.bytes.length,
      'coverStatus': 'pending',
    };

    final batch = _db.batch();
    batch.set(postRef, {
      'authorId': authorId,
      'type': typeName,
      'body': body,
      'meta': meta,
      if (replyTo != null) 'replyTo': replyTo.toMap(),
      'createdAt': now,
      'status': 'sent',
    });

    batch.update(_db.collection('circles').doc(circleId), {
      'lastPost': {
        'type': typeName,
        'body': lastPostPreviewBody(
          type: typeName,
          body: body,
          kind: 'pdf',
        ),
        'kind': 'pdf',
        'authorId': authorId,
        'createdAt': now,
      },
      'updatedAt': now,
    });

    await batch.commit();
    return (postId: postId, meta: meta);
  }

  /// Returns post id and the written [meta] (for library mirror / linking).
  Future<({String postId, Map<String, dynamic> meta})> sendAudioPost({
    required String circleId,
    required String authorId,
    required PickedFileBytes audio,
    String caption = '',
    PostReplyTo? replyTo,
    PostType type = PostType.media,
  }) async {
    final postRef = _posts(circleId).doc();
    final postId = postRef.id;

    final uploaded = await _media.uploadCircleFile(
      circleId: circleId,
      userId: authorId,
      postId: postId,
      file: audio,
    );

    final now = FieldValue.serverTimestamp();
    final body = caption.trim();
    final typeName = type.name;
    final meta = <String, dynamic>{
      'kind': 'audio',
      'storagePath': uploaded.storagePath,
      'downloadUrl': uploaded.downloadUrl,
      'contentType': audio.contentType,
      'fileName': audio.fileName,
      'byteSize': audio.bytes.length,
      if (audio.durationMs != null) 'durationMs': audio.durationMs,
    };

    final batch = _db.batch();
    batch.set(postRef, {
      'authorId': authorId,
      'type': typeName,
      'body': body,
      'meta': meta,
      if (replyTo != null) 'replyTo': replyTo.toMap(),
      'createdAt': now,
      'status': 'sent',
    });

    batch.update(_db.collection('circles').doc(circleId), {
      'lastPost': {
        'type': typeName,
        'body': lastPostPreviewBody(
          type: typeName,
          body: body,
          kind: 'audio',
        ),
        'kind': 'audio',
        'authorId': authorId,
        'createdAt': now,
      },
      'updatedAt': now,
    });

    await batch.commit();
    return (postId: postId, meta: meta);
  }

  /// Returns post id and the written [meta] (for library mirror / linking).
  Future<({String postId, Map<String, dynamic> meta})> sendVideoPost({
    required String circleId,
    required String authorId,
    required PickedFileBytes video,
    String caption = '',
    PostReplyTo? replyTo,
    PostType type = PostType.media,
  }) async {
    final postRef = _posts(circleId).doc();
    final postId = postRef.id;

    final uploaded = await _media.uploadCircleFile(
      circleId: circleId,
      userId: authorId,
      postId: postId,
      file: video,
    );

    final now = FieldValue.serverTimestamp();
    final body = caption.trim();
    final typeName = type.name;
    final meta = <String, dynamic>{
      'kind': 'video',
      'storagePath': uploaded.storagePath,
      'downloadUrl': uploaded.downloadUrl,
      'contentType': video.contentType,
      'fileName': video.fileName,
      'byteSize': video.bytes.length,
      'coverStatus': 'pending',
      if (video.durationMs != null) 'durationMs': video.durationMs,
    };

    final batch = _db.batch();
    batch.set(postRef, {
      'authorId': authorId,
      'type': typeName,
      'body': body,
      'meta': meta,
      if (replyTo != null) 'replyTo': replyTo.toMap(),
      'createdAt': now,
      'status': 'sent',
    });

    batch.update(_db.collection('circles').doc(circleId), {
      'lastPost': {
        'type': typeName,
        'body': lastPostPreviewBody(
          type: typeName,
          body: body,
          kind: 'video',
        ),
        'kind': 'video',
        'authorId': authorId,
        'createdAt': now,
      },
      'updatedAt': now,
    });

    await batch.commit();
    return (postId: postId, meta: meta);
  }
}
