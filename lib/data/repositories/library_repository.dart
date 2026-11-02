import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';

import '../../domain/models/challenge.dart';
import '../../domain/models/library_item.dart';
import '../../domain/models/post.dart';
import 'assignment_repository.dart';
import 'auth_repository.dart';
import 'challenge_repository.dart';
import 'media_repository.dart';
import 'post_repository.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository(
    db: ref.watch(firestoreProvider),
    storage: FirebaseStorage.instance,
    posts: ref.watch(postRepositoryProvider),
    challenges: ref.watch(challengeRepositoryProvider),
    assignments: ref.watch(assignmentRepositoryProvider),
  );
});

class LibraryRepository {
  LibraryRepository({
    required FirebaseFirestore db,
    required FirebaseStorage storage,
    required PostRepository posts,
    required ChallengeRepository challenges,
    required AssignmentRepository assignments,
  })  : _db = db,
        _storage = storage,
        _posts = posts,
        _challenges = challenges,
        _assignments = assignments;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final PostRepository _posts;
  final ChallengeRepository _challenges;
  final AssignmentRepository _assignments;

  CollectionReference<Map<String, dynamic>> get _items =>
      _db.collection('libraryItems');

  Stream<List<LibraryItem>> watchMyItems(String ownerId) {
    return _items
        .where('ownerId', isEqualTo: ownerId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => LibraryItem.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  Stream<LibraryItem?> watchItem(String itemId) {
    return _items.doc(itemId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return LibraryItem.fromMap(snap.id, snap.data()!);
    });
  }

  Future<String> createItem({
    required String ownerId,
    required LibraryItemKind kind,
    required String title,
    String body = '',
    Map<String, dynamic> meta = const {},
  }) async {
    final ref = _items.doc();
    final now = FieldValue.serverTimestamp();
    await ref.set({
      'ownerId': ownerId,
      'kind': libraryItemKindToString(kind),
      'title': title.trim(),
      'body': body.trim(),
      'meta': meta,
      'createdAt': now,
      'updatedAt': now,
    });
    return ref.id;
  }

  Future<void> updateItem({
    required String itemId,
    String? title,
    String? body,
    Map<String, dynamic>? meta,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (title != null) data['title'] = title.trim();
    if (body != null) data['body'] = body.trim();
    if (meta != null) data['meta'] = meta;
    await _items.doc(itemId).update(data);
  }

  /// Mirror a Hoop-created artifact into the facilitator's library catalog.
  Future<String> mirrorFromHoop({
    required String ownerId,
    required LibraryItemKind kind,
    required String title,
    String body = '',
    Map<String, dynamic> meta = const {},
  }) {
    return createItem(
      ownerId: ownerId,
      kind: kind,
      title: title,
      body: body,
      meta: {
        ...meta,
        'source': meta['source'] ?? 'hoop',
      },
    );
  }

  /// Merge instance link fields into an existing library item meta.
  Future<void> linkInstance({
    required String itemId,
    required Map<String, dynamic> instanceMeta,
  }) async {
    final snap = await _items.doc(itemId).get();
    final existing = Map<String, dynamic>.from(snap.data()?['meta'] as Map? ?? {});
    existing.addAll(instanceMeta);
    await updateItem(itemId: itemId, meta: existing);
  }

  Future<void> deleteItem(LibraryItem item) async {
    final storagePath = item.meta['storagePath'] as String?;
    if (storagePath != null && storagePath.isNotEmpty) {
      try {
        await _storage.ref(storagePath).delete();
      } catch (_) {
        // Best-effort; Firestore doc still removed.
      }
    }
    await _items.doc(item.id).delete();
  }

  /// Upload media under `library/{ownerId}/{itemId}/...` and return path + meta.
  Future<Map<String, dynamic>> uploadLibraryFile({
    required String ownerId,
    required String itemId,
    required Uint8List bytes,
    required String fileName,
    String? contentType,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final path = 'library/$ownerId/$itemId/$safeName';
    final ct = contentType ??
        lookupMimeType(safeName, headerBytes: bytes) ??
        'application/octet-stream';
    await _storage.ref(path).putData(
          bytes,
          SettableMetadata(contentType: ct),
        );
    return {
      'storagePath': path,
      'contentType': ct,
      'fileName': safeName,
      'byteSize': bytes.length,
    };
  }

  Future<Uint8List?> _downloadBytes(String storagePath) async {
    return _storage.ref(storagePath).getData(100 * 1024 * 1024);
  }

  /// Clone a library item into an admin Hoop.
  Future<void> publishToCircle({
    required LibraryItem item,
    required String circleId,
    required String authorId,
  }) async {
    switch (item.kind) {
      case LibraryItemKind.resource:
        await _publishResource(
          item: item,
          circleId: circleId,
          authorId: authorId,
        );
      case LibraryItemKind.challenge:
        await _publishChallenge(
          item: item,
          circleId: circleId,
          authorId: authorId,
        );
      case LibraryItemKind.assignment:
        await _publishAssignment(
          item: item,
          circleId: circleId,
          authorId: authorId,
        );
    }
  }

  Future<void> _publishResource({
    required LibraryItem item,
    required String circleId,
    required String authorId,
  }) async {
    final kind = item.meta['kind'] as String? ?? 'link';
    final caption = item.body.trim().isNotEmpty ? item.body : item.title;
    late final String postId;

    if (kind == 'link' || kind == 'googleDoc') {
      final url = item.meta['url'] as String? ?? '';
      if (url.isEmpty) throw StateError('Resource is missing a URL');
      final meta = <String, dynamic>{
        'kind': kind,
        'url': url,
        if (kind == 'googleDoc') 'exportStatus': 'pending',
      };
      postId = await _posts.sendPost(
        circleId: circleId,
        authorId: authorId,
        type: PostType.resource,
        body: item.title.isNotEmpty ? item.title : url,
        meta: meta,
      );
    } else {
      final storagePath = item.meta['storagePath'] as String?;
      if (storagePath == null || storagePath.isEmpty) {
        throw StateError('Resource file is missing');
      }
      final bytes = await _downloadBytes(storagePath);
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Could not download library file');
      }
      final fileName =
          item.meta['fileName'] as String? ?? 'resource.bin';
      final contentType = item.meta['contentType'] as String? ??
          lookupMimeType(fileName, headerBytes: bytes) ??
          'application/octet-stream';
      final file = PickedFileBytes(
        bytes: bytes,
        contentType: contentType,
        fileName: fileName,
      );

      switch (kind) {
        case 'pdf':
          final created = await _posts.sendPdfPost(
            circleId: circleId,
            authorId: authorId,
            pdf: file,
            caption: caption,
            type: PostType.resource,
          );
          postId = created.postId;
        case 'audio':
          final created = await _posts.sendAudioPost(
            circleId: circleId,
            authorId: authorId,
            audio: file,
            caption: caption,
            type: PostType.resource,
          );
          postId = created.postId;
        case 'video':
          final created = await _posts.sendVideoPost(
            circleId: circleId,
            authorId: authorId,
            video: file,
            caption: caption,
            type: PostType.resource,
          );
          postId = created.postId;
        default:
          throw StateError('Unsupported resource kind: $kind');
      }
    }

    await linkInstance(
      itemId: item.id,
      instanceMeta: {
        'circleId': circleId,
        'postId': postId,
      },
    );
  }

  Future<void> _publishChallenge({
    required LibraryItem item,
    required String circleId,
    required String authorId,
  }) async {
    final kind = challengeKindFromString(
      item.meta['kind'] as String? ?? 'quest',
    );
    final durationDays = (item.meta['durationDays'] as num?)?.toInt() ?? 21;
    final preAlarm = (item.meta['preAlarmMinutes'] as num?)?.toInt() ?? 10;
    final instructions = item.meta['instructions'] as String?;
    ChallengeMediaKind? mediaKind;
    Uint8List? mediaBytes;
    String? mediaFileName;
    String? mediaContentType;

    if (kind == ChallengeKind.media) {
      mediaKind = challengeMediaKindFromString(
        item.meta['mediaKind'] as String? ?? 'audio',
      );
      final storagePath = item.meta['storagePath'] as String?;
      if (storagePath == null || storagePath.isEmpty) {
        throw StateError('Challenge media is missing');
      }
      mediaBytes = await _downloadBytes(storagePath);
      if (mediaBytes == null || mediaBytes.isEmpty) {
        throw StateError('Could not download challenge media');
      }
      mediaFileName = item.meta['fileName'] as String? ?? 'practice.bin';
      mediaContentType = item.meta['contentType'] as String?;
    }

    final challengeId = await _challenges.createChallenge(
      circleId: circleId,
      createdBy: authorId,
      title: item.title,
      description: item.body,
      kind: kind,
      durationDays: durationDays,
      preAlarmMinutes: preAlarm.clamp(0, 180),
      mediaKind: mediaKind,
      instructions: instructions,
      mediaBytes: mediaBytes,
      mediaFileName: mediaFileName,
      mediaContentType: mediaContentType,
      skipLibraryMirror: true,
    );
    await linkInstance(
      itemId: item.id,
      instanceMeta: {
        'circleId': circleId,
        'challengeId': challengeId,
      },
    );
  }

  Future<void> _publishAssignment({
    required LibraryItem item,
    required String circleId,
    required String authorId,
  }) async {
    final blocksRaw = item.meta['blocks'];
    final String assignmentId;
    if (blocksRaw is List && blocksRaw.isNotEmpty) {
      assignmentId = await _assignments.createPublishedFromBlockSnapshot(
        circleId: circleId,
        createdBy: authorId,
        title: item.title,
        blocks: blocksRaw,
        fromLibraryItemId: item.id,
      );
    } else {
      final prompt = () {
        final raw = item.meta['objectives'];
        if (raw is List && raw.isNotEmpty) {
          final first = raw.first;
          if (first is Map) {
            final label = first['label'] as String?;
            if (label != null && label.trim().isNotEmpty) return label.trim();
          }
        }
        return 'Your response';
      }();

      assignmentId = await _assignments.createPublishedWithMinimalBlocks(
        circleId: circleId,
        createdBy: authorId,
        title: item.title,
        body: item.body,
        questionPrompt: prompt,
        fromLibraryItemId: item.id,
      );
    }
    await linkInstance(
      itemId: item.id,
      instanceMeta: {
        'circleId': circleId,
        'assignmentId': assignmentId,
      },
    );
  }
}
