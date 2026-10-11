import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';

import '../../domain/models/challenge.dart';
import 'auth_repository.dart';

final challengeRepositoryProvider = Provider<ChallengeRepository>((ref) {
  return ChallengeRepository(
    db: ref.watch(firestoreProvider),
    storage: FirebaseStorage.instance,
  );
});

class ChallengeRepository {
  ChallengeRepository({
    required FirebaseFirestore db,
    required FirebaseStorage storage,
  })  : _db = db,
        _storage = storage;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> _challenges(String circleId) =>
      _db.collection('circles').doc(circleId).collection('challenges');

  Stream<List<Challenge>> watchChallenges(String circleId) {
    return _challenges(circleId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => Challenge.fromMap(d.id, {...d.data(), 'circleId': circleId}))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Stream<Challenge?> watchChallenge(String circleId, String challengeId) {
    return _challenges(circleId).doc(challengeId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return Challenge.fromMap(
        snap.id,
        {...snap.data()!, 'circleId': circleId},
      );
    });
  }

  Future<String> createChallenge({
    required String circleId,
    required String createdBy,
    required String title,
    String? description,
    required ChallengeKind kind,
    required int durationDays,
    int preAlarmMinutes = 10,
    ChallengeMediaKind? mediaKind,
    String? instructions,
    Uint8List? mediaBytes,
    String? mediaFileName,
    String? mediaContentType,
  }) async {
    final ref = _challenges(circleId).doc();
    String? storagePath;
    String? contentType = mediaContentType;

    if (kind == ChallengeKind.media) {
      if (mediaBytes == null || mediaFileName == null || mediaKind == null) {
        throw StateError('Media challenge requires a file');
      }
      contentType ??=
          lookupMimeType(mediaFileName, headerBytes: mediaBytes) ??
              (mediaKind == ChallengeMediaKind.video ? 'video/mp4' : 'audio/mpeg');
      storagePath =
          'circles/$circleId/challenges/${ref.id}/master/$mediaFileName';
      await _storage.ref(storagePath).putData(
            mediaBytes,
            SettableMetadata(contentType: contentType),
          );
    } else {
      if ((instructions ?? '').trim().isEmpty) {
        throw StateError('Quest challenge requires instructions');
      }
    }

    await ref.set({
      'circleId': circleId,
      'title': title.trim(),
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      'kind': challengeKindToString(kind),
      if (mediaKind != null) 'mediaKind': challengeMediaKindToString(mediaKind),
      if (storagePath != null) 'storagePath': storagePath,
      if (contentType != null) 'contentType': contentType,
      if (instructions != null) 'instructions': instructions.trim(),
      'durationDays': durationDays,
      'preAlarmMinutes': preAlarmMinutes,
      'status': 'active',
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Stream<ChallengeEnrollment?> watchMyEnrollment({
    required String challengeId,
    required String userId,
  }) {
    final id = '${challengeId}_$userId';
    return _db.collection('challengeEnrollments').doc(id).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return ChallengeEnrollment.fromMap(snap.id, snap.data()!);
    });
  }

  Stream<List<ChallengeEnrollment>> watchMyEnrollmentsInCircle({
    required String circleId,
    required String userId,
  }) {
    return _db
        .collection('challengeEnrollments')
        .where('userId', isEqualTo: userId)
        .where('circleId', isEqualTo: circleId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => ChallengeEnrollment.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  Future<String> enroll({
    required Challenge challenge,
    required String userId,
    required String startDate,
    required String dailyTime,
    required String timezone,
  }) async {
    final enrollmentId = '${challenge.id}_$userId';
    final existing =
        await _db.collection('challengeEnrollments').doc(enrollmentId).get();
    if (existing.exists &&
        (existing.data()?['status'] as String? ?? '') == 'active') {
      throw StateError(
        'You already have an active enrollment for this challenge',
      );
    }

    final batch = _db.batch();
    final enrollRef = _db.collection('challengeEnrollments').doc(enrollmentId);
    batch.set(enrollRef, {
      'circleId': challenge.circleId,
      'challengeId': challenge.id,
      'userId': userId,
      'startDate': startDate,
      'dailyTime': dailyTime,
      'timezone': timezone,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    });

    for (var day = 1; day <= challenge.durationDays; day++) {
      final sessionId = '${enrollmentId}_$day';
      final scheduled = scheduledAtForDay(
        startDate: startDate,
        dailyTime: dailyTime,
        dayIndex: day,
      );
      final sessionRef = _db.collection('challengeSessions').doc(sessionId);
      batch.set(sessionRef, {
        'circleId': challenge.circleId,
        'challengeId': challenge.id,
        'enrollmentId': enrollmentId,
        'userId': userId,
        'dayIndex': day,
        'scheduledAt': Timestamp.fromDate(scheduled),
        'state': 'scheduled',
        'evidence': <String, dynamic>{},
      });
    }

    await batch.commit();
    return enrollmentId;
  }

  /// List rules require `userId == uid()`; queries must include that equality.
  Stream<List<ChallengeSession>> watchSessions(
    String enrollmentId, {
    required String userId,
  }) {
    return _db
        .collection('challengeSessions')
        .where('enrollmentId', isEqualTo: enrollmentId)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => ChallengeSession.fromMap(d.id, d.data()))
          .toList();
      list.sort((a, b) => a.dayIndex.compareTo(b.dayIndex));
      return list;
    });
  }

  Future<List<ChallengeSession>> fetchSessions(
    String enrollmentId, {
    required String userId,
  }) async {
    final snap = await _db
        .collection('challengeSessions')
        .where('enrollmentId', isEqualTo: enrollmentId)
        .where('userId', isEqualTo: userId)
        .get();
    final list = snap.docs
        .map((d) => ChallengeSession.fromMap(d.id, d.data()))
        .toList();
    list.sort((a, b) => a.dayIndex.compareTo(b.dayIndex));
    return list;
  }

  Stream<ChallengeSession?> watchSession(String sessionId) {
    return _db.collection('challengeSessions').doc(sessionId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return ChallengeSession.fromMap(snap.id, snap.data()!);
    });
  }

  Future<void> markSessionInProgress(String sessionId) async {
    await _db.collection('challengeSessions').doc(sessionId).update({
      'state': 'in_progress',
      'startedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> completeMediaSession(String sessionId) async {
    await _db.collection('challengeSessions').doc(sessionId).update({
      'state': 'completed',
      'playbackEnded': true,
      'completedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> skipSession(String sessionId) async {
    await _db.collection('challengeSessions').doc(sessionId).update({
      'state': 'skipped',
      'completedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> completeQuestSession({
    required ChallengeSession session,
    String? text,
    Uint8List? imageBytes,
    String? imageFileName,
    Uint8List? audioBytes,
    String? audioFileName,
  }) async {
    final hasText = text != null && text.trim().isNotEmpty;
    final hasImage = imageBytes != null && imageBytes.isNotEmpty;
    final hasAudio = audioBytes != null && audioBytes.isNotEmpty;
    if (!hasText && !hasImage && !hasAudio) {
      throw StateError('Add text, an image, or audio feedback');
    }

    final evidence = <String, dynamic>{};
    if (hasText) evidence['text'] = text.trim();

    final base =
        'circles/${session.circleId}/challenges/${session.challengeId}/enrollments/${session.enrollmentId}/sessions/${session.id}';

    if (hasImage) {
      final name = imageFileName ?? 'feedback.jpg';
      final path = '$base/image/$name';
      final ct = lookupMimeType(name, headerBytes: imageBytes) ?? 'image/jpeg';
      await _storage.ref(path).putData(
            imageBytes,
            SettableMetadata(contentType: ct),
          );
      evidence['imageStoragePath'] = path;
    }
    if (hasAudio) {
      final name = audioFileName ?? 'feedback.m4a';
      final path = '$base/audio/$name';
      final ct = lookupMimeType(name, headerBytes: audioBytes) ?? 'audio/mp4';
      await _storage.ref(path).putData(
            audioBytes,
            SettableMetadata(contentType: ct),
          );
      evidence['audioStoragePath'] = path;
    }

    await _db.collection('challengeSessions').doc(session.id).update({
      'state': 'completed',
      'evidence': evidence,
      'completedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> getDownloadUrl(String storagePath) {
    return _storage.ref(storagePath).getDownloadURL();
  }

  Future<Uint8List?> getData(String storagePath) async {
    return _storage.ref(storagePath).getData(100 * 1024 * 1024);
  }

  /// Mark overdue scheduled sessions as missed (best-effort on open).
  /// Returns session ids that were newly marked missed.
  Future<List<String>> refreshMissedSessions(String enrollmentId) async {
    final snap = await _db
        .collection('challengeSessions')
        .where('enrollmentId', isEqualTo: enrollmentId)
        .get();
    final now = DateTime.now();
    final batch = _db.batch();
    final missedIds = <String>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final state = data['state'] as String? ?? 'scheduled';
      if (state != 'scheduled') continue;
      final scheduled = (data['scheduledAt'] as Timestamp?)?.toDate();
      if (scheduled == null) continue;
      // Missed if the calendar day after the session day has begun.
      final endOfDay = DateTime(
        scheduled.year,
        scheduled.month,
        scheduled.day,
        23,
        59,
        59,
      );
      if (now.isAfter(endOfDay)) {
        batch.update(doc.reference, {'state': 'missed'});
        missedIds.add(doc.id);
      }
    }
    if (missedIds.isNotEmpty) await batch.commit();
    return missedIds;
  }
}
