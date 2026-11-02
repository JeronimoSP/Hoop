import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/circle.dart';
import 'auth_repository.dart';

final circleRepositoryProvider = Provider<CircleRepository>((ref) {
  return CircleRepository(ref.watch(firestoreProvider));
});

class CircleListItem {
  const CircleListItem({
    required this.circle,
    required this.membership,
  });

  final Circle circle;
  final Membership membership;
}

class CircleRepository {
  CircleRepository(this._db);

  final FirebaseFirestore _db;

  Stream<List<CircleListItem>> watchMyCircles(String userId) {
    return _db
        .collection('memberships')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .asyncMap((snap) async {
      final items = <CircleListItem>[];
      for (final doc in snap.docs) {
        final membership = Membership.fromMap(doc.id, doc.data());
        final circleSnap =
            await _db.collection('circles').doc(membership.circleId).get();
        if (!circleSnap.exists || circleSnap.data() == null) continue;
        items.add(
          CircleListItem(
            circle: Circle.fromMap(circleSnap.id, circleSnap.data()!),
            membership: membership,
          ),
        );
      }
      items.sort((a, b) => b.circle.updatedAt.compareTo(a.circle.updatedAt));
      return items;
    });
  }

  Stream<Circle?> watchCircle(String circleId) {
    return _db.collection('circles').doc(circleId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return Circle.fromMap(snap.id, snap.data()!);
    });
  }

  Stream<Membership?> watchMembership({
    required String circleId,
    required String userId,
  }) {
    final id = '${circleId}_$userId';
    return _db.collection('memberships').doc(id).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return Membership.fromMap(snap.id, snap.data()!);
    });
  }

  Stream<List<Membership>> watchMembers(String circleId) {
    return _db
        .collection('memberships')
        .where('circleId', isEqualTo: circleId)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => Membership.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  Future<String> createCircle({
    required String name,
    required String description,
    required String createdBy,
    List<String> memberUserIds = const [],
  }) async {
    final circleRef = _db.collection('circles').doc();
    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();

    batch.set(circleRef, {
      'name': name.trim(),
      'description': description.trim(),
      'createdBy': createdBy,
      'pointerId': null,
      'timeKeeperId': null,
      'nextMeetingAt': null,
      'lastPost': null,
      'updatedAt': now,
    });

    final adminMembershipId = '${circleRef.id}_$createdBy';
    batch.set(_db.collection('memberships').doc(adminMembershipId), {
      'circleId': circleRef.id,
      'userId': createdBy,
      'role': 'admin',
      'joinedAt': now,
      'unreadCount': 0,
      'lastOpenedAt': now,
    });

    for (final uid in memberUserIds.toSet()) {
      if (uid == createdBy) continue;
      final mid = '${circleRef.id}_$uid';
      batch.set(_db.collection('memberships').doc(mid), {
        'circleId': circleRef.id,
        'userId': uid,
        'role': 'member',
        'joinedAt': now,
        'unreadCount': 0,
        'lastOpenedAt': now,
      });
    }

    await batch.commit();
    return circleRef.id;
  }

  Future<void> addMember({
    required String circleId,
    required String userId,
    String role = 'member',
  }) async {
    final mid = '${circleId}_$userId';
    await _db.collection('memberships').doc(mid).set({
      'circleId': circleId,
      'userId': userId,
      'role': role,
      'joinedAt': FieldValue.serverTimestamp(),
      'unreadCount': 0,
      'lastOpenedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Clears unread badge for this member when they open the circle thread.
  Future<void> markCircleOpened({
    required String circleId,
    required String userId,
  }) async {
    final mid = '${circleId}_$userId';
    await _db.collection('memberships').doc(mid).set({
      'unreadCount': 0,
      'lastOpenedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateCircleMeta({
    required String circleId,
    String? pointerId,
    String? timeKeeperId,
    DateTime? nextMeetingAt,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (pointerId != null) data['pointerId'] = pointerId;
    if (timeKeeperId != null) data['timeKeeperId'] = timeKeeperId;
    if (nextMeetingAt != null) {
      data['nextMeetingAt'] = Timestamp.fromDate(nextMeetingAt);
    }
    await _db.collection('circles').doc(circleId).update(data);
  }

  /// Deletes a Hoop and related docs (admin only; enforced by rules).
  /// Memberships are removed last so the admin keeps `isCircleAdmin` until the end.
  Future<void> deleteCircle(String circleId) async {
    void log(String step, [Object? err]) {
      if (err == null) {
        debugPrint('[HoopDelete] $circleId $step ok');
      } else {
        debugPrint('[HoopDelete] $circleId $step FAILED: $err');
      }
    }

    Future<void> deleteQuery(Query<Map<String, dynamic>> query) async {
      while (true) {
        final snap = await query.limit(200).get();
        if (snap.docs.isEmpty) break;
        var batch = _db.batch();
        var ops = 0;
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
          ops++;
          if (ops >= 450) {
            await batch.commit();
            batch = _db.batch();
            ops = 0;
          }
        }
        if (ops > 0) await batch.commit();
        if (snap.docs.length < 200) break;
      }
    }

    Future<void> step(String name, Future<void> Function() run) async {
      try {
        await run();
        log(name);
      } catch (e) {
        log(name, e);
        rethrow;
      }
    }

    await step('posts', () async {
      while (true) {
        final posts = await _db
            .collection('circles')
            .doc(circleId)
            .collection('posts')
            .limit(50)
            .get();
        if (posts.docs.isEmpty) break;
        for (final post in posts.docs) {
          final reactions =
              await post.reference.collection('reactions').get();
          var batch = _db.batch();
          var ops = 0;
          for (final r in reactions.docs) {
            batch.delete(r.reference);
            ops++;
            if (ops >= 450) {
              await batch.commit();
              batch = _db.batch();
              ops = 0;
            }
          }
          batch.delete(post.reference);
          await batch.commit();
        }
      }
    });

    await step(
      'challenges',
      () => deleteQuery(
        _db.collection('circles').doc(circleId).collection('challenges'),
      ),
    );
    await step(
      'challengeEnrollments',
      () => deleteQuery(
        _db
            .collection('challengeEnrollments')
            .where('circleId', isEqualTo: circleId),
      ),
    );
    await step(
      'challengeSessions',
      () => deleteQuery(
        _db
            .collection('challengeSessions')
            .where('circleId', isEqualTo: circleId),
      ),
    );
    await step('assignments', () async {
      final assignments = await _db
          .collection('assignments')
          .where('circleId', isEqualTo: circleId)
          .get();
      for (final a in assignments.docs) {
        await deleteQuery(
          _db.collection('objectives').where('assignmentId', isEqualTo: a.id),
        );
        await a.reference.delete();
      }
    });
    await step(
      'progressLogs',
      () => deleteQuery(
        _db.collection('progressLogs').where('circleId', isEqualTo: circleId),
      ),
    );
    await step(
      'circle',
      () => _db.collection('circles').doc(circleId).delete(),
    );
    // Memberships last — admin must remain a member for prior admin deletes.
    await step(
      'memberships',
      () => deleteQuery(
        _db.collection('memberships').where('circleId', isEqualTo: circleId),
      ),
    );
    log('done');
  }
}
