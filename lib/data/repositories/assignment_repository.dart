import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/assignment.dart';
import 'auth_repository.dart';

final assignmentRepositoryProvider = Provider<AssignmentRepository>((ref) {
  return AssignmentRepository(ref.watch(firestoreProvider));
});

class AssignmentRepository {
  AssignmentRepository(this._db);

  final FirebaseFirestore _db;

  Stream<List<Assignment>> watchAssignments(String circleId) {
    return _db
        .collection('assignments')
        .where('circleId', isEqualTo: circleId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => Assignment.fromMap(d.id, d.data()))
              .toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
        );
  }

  Stream<List<Objective>> watchObjectivesForAssignments(
    List<String> assignmentIds,
  ) {
    if (assignmentIds.isEmpty) return Stream.value(const []);
    // Firestore whereIn limit 10 — MVP circles stay small.
    final ids = assignmentIds.take(10).toList();
    return _db
        .collection('objectives')
        .where('assignmentId', whereIn: ids)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => Objective.fromMap(d.id, d.data()))
          .toList();
      list.sort((a, b) => a.order.compareTo(b.order));
      return list;
    });
  }

  Stream<List<ProgressLog>> watchMyProgress({
    required String userId,
    required String circleId,
  }) {
    return _db
        .collection('progressLogs')
        .where('userId', isEqualTo: userId)
        .where('circleId', isEqualTo: circleId)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => ProgressLog.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  Future<String> createAssignmentWithObjectives({
    required String circleId,
    required String createdBy,
    required String title,
    String? description,
    required List<({ObjectiveType type, String label})> objectives,
  }) async {
    final batch = _db.batch();
    final assignmentRef = _db.collection('assignments').doc();
    final now = FieldValue.serverTimestamp();

    batch.set(assignmentRef, {
      'circleId': circleId,
      'createdBy': createdBy,
      'title': title.trim(),
      'description': description?.trim(),
      'createdAt': now,
      'status': 'active',
    });

    for (var i = 0; i < objectives.length; i++) {
      final o = objectives[i];
      final objRef = _db.collection('objectives').doc();
      batch.set(objRef, {
        'assignmentId': assignmentRef.id,
        'type': objectiveTypeToString(o.type),
        'criteria': {'label': o.label},
        'evidenceSpec': {'kind': 'check'},
        'order': i,
        'weight': 1,
      });
    }

    await batch.commit();
    return assignmentRef.id;
  }

  Future<void> markObjectiveCompleted({
    required String circleId,
    required String assignmentId,
    required String objectiveId,
    required String userId,
    Map<String, dynamic> evidence = const {},
  }) async {
    final existing = await _db
        .collection('progressLogs')
        .where('userId', isEqualTo: userId)
        .where('objectiveId', isEqualTo: objectiveId)
        .limit(1)
        .get();

    final now = FieldValue.serverTimestamp();
    final data = {
      'circleId': circleId,
      'assignmentId': assignmentId,
      'objectiveId': objectiveId,
      'userId': userId,
      'status': 'completed',
      'evidence': evidence,
      'completedAt': now,
      'updatedAt': now,
    };

    if (existing.docs.isNotEmpty) {
      await existing.docs.first.reference.set(data, SetOptions(merge: true));
    } else {
      await _db.collection('progressLogs').add(data);
    }
  }
}

List<CoinView> buildCoinViews({
  required List<Assignment> assignments,
  required List<Objective> objectives,
  required List<ProgressLog> logs,
}) {
  return assignments.map((a) {
    final objs = objectives.where((o) => o.assignmentId == a.id).toList();
    final aLogs = logs.where((l) => l.assignmentId == a.id);
    final completed = aLogs
        .where((l) => l.status == ProgressStatus.completed)
        .map((l) => l.objectiveId)
        .toSet();
    final done = objs.where((o) => completed.contains(o.id)).length;
    return CoinView(
      assignment: a,
      objectives: objs,
      state: deriveCoinState(objectives: objs, logs: aLogs),
      completedCount: done,
      completedObjectiveIds: completed,
    );
  }).toList();
}
