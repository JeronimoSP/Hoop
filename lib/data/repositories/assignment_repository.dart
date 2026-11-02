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

  CollectionReference<Map<String, dynamic>> get _assignments =>
      _db.collection('assignments');
  CollectionReference<Map<String, dynamic>> get _blocks =>
      _db.collection('assignmentBlocks');
  CollectionReference<Map<String, dynamic>> get _answers =>
      _db.collection('blockAnswers');
  CollectionReference<Map<String, dynamic>> get _submissions =>
      _db.collection('assignmentSubmissions');

  Stream<List<Assignment>> watchPublishedAssignments(String circleId) {
    return _assignments
        .where('circleId', isEqualTo: circleId)
        .where('status', whereIn: ['published', 'active'])
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => Assignment.fromMap(d.id, d.data()))
              .toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
        );
  }

  Stream<List<Assignment>> watchAssignmentsForAdmin(String circleId) {
    return _assignments
        .where('circleId', isEqualTo: circleId)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => Assignment.fromMap(d.id, d.data()))
              .where((a) => a.status != AssignmentStatus.archived)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        );
  }

  Stream<List<Assignment>> watchAssignments(String circleId) =>
      watchPublishedAssignments(circleId);

  Stream<Assignment?> watchAssignment(String assignmentId) {
    return _assignments.doc(assignmentId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return Assignment.fromMap(doc.id, doc.data()!);
    });
  }

  Stream<List<AssignmentBlock>> watchBlocks({
    required String circleId,
    required String assignmentId,
  }) {
    return _blocks
        .where('circleId', isEqualTo: circleId)
        .where('assignmentId', isEqualTo: assignmentId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => AssignmentBlock.fromMap(d.id, d.data()))
          .toList();
      list.sort((a, b) => a.order.compareTo(b.order));
      return list;
    });
  }

  Stream<List<BlockAnswer>> watchMyAnswers({
    required String circleId,
    required String assignmentId,
    required String userId,
  }) {
    return _answers
        .where('circleId', isEqualTo: circleId)
        .where('assignmentId', isEqualTo: assignmentId)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => BlockAnswer.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  Stream<AssignmentSubmission?> watchMySubmission({
    required String assignmentId,
    required String userId,
  }) {
    final id = '${assignmentId}_$userId';
    return _submissions.doc(id).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return AssignmentSubmission.fromMap(doc.id, doc.data()!);
    });
  }

  Stream<List<AssignmentSubmission>> watchSubmissionsForAssignment({
    required String circleId,
    required String assignmentId,
  }) {
    return _submissions
        .where('circleId', isEqualTo: circleId)
        .where('assignmentId', isEqualTo: assignmentId)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => AssignmentSubmission.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  Stream<List<AssignmentSubmission>> watchMySubmissionsInCircle({
    required String circleId,
    required String userId,
  }) {
    return _submissions
        .where('circleId', isEqualTo: circleId)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => AssignmentSubmission.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  Future<bool> hasAnyAnswers({
    required String circleId,
    required String assignmentId,
  }) async {
    final snap = await _answers
        .where('circleId', isEqualTo: circleId)
        .where('assignmentId', isEqualTo: assignmentId)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future<String> createDraftAssignment({
    required String circleId,
    required String createdBy,
    String title = 'Untitled assignment',
    String? fromLibraryItemId,
    bool skipLibraryMirror = false,
  }) async {
    final ref = _assignments.doc();
    final trimmed =
        title.trim().isEmpty ? 'Untitled assignment' : title.trim();
    final data = <String, dynamic>{
      'circleId': circleId,
      'createdBy': createdBy,
      'title': trimmed,
      'description': null,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'draft',
      'allowLate': false,
    };
    if (fromLibraryItemId != null) {
      data['libraryItemId'] = fromLibraryItemId;
    }
    await ref.set(data);

    if (!skipLibraryMirror && fromLibraryItemId == null) {
      final libRef = _db.collection('libraryItems').doc();
      await libRef.set({
        'ownerId': createdBy,
        'kind': 'assignment',
        'title': trimmed,
        'body': '',
        'meta': {
          'source': 'hoop',
          'circleId': circleId,
          'assignmentId': ref.id,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await ref.update({'libraryItemId': libRef.id});
    }
    return ref.id;
  }

  Future<void> updateAssignmentMeta({
    required String assignmentId,
    String? title,
    String? description,
    DateTime? opensAt,
    DateTime? dueAt,
    bool? allowLate,
    bool clearOpensAt = false,
    bool clearDueAt = false,
  }) async {
    final data = <String, dynamic>{};
    if (title != null) data['title'] = title.trim();
    if (description != null) data['description'] = description.trim();
    if (allowLate != null) data['allowLate'] = allowLate;
    if (clearOpensAt) {
      data['opensAt'] = null;
    } else if (opensAt != null) {
      data['opensAt'] = Timestamp.fromDate(opensAt);
    }
    if (clearDueAt) {
      data['dueAt'] = null;
    } else if (dueAt != null) {
      data['dueAt'] = Timestamp.fromDate(dueAt);
    }
    if (data.isEmpty) return;
    await _assignments.doc(assignmentId).update(data);
  }

  Future<void> publishAssignment({
    required String assignmentId,
    required String title,
    DateTime? opensAt,
    DateTime? dueAt,
    bool allowLate = false,
  }) async {
    await _assignments.doc(assignmentId).update({
      'title': title.trim(),
      'status': 'published',
      'publishedAt': FieldValue.serverTimestamp(),
      'allowLate': allowLate,
      'opensAt': opensAt != null ? Timestamp.fromDate(opensAt) : null,
      'dueAt': dueAt != null ? Timestamp.fromDate(dueAt) : null,
    });
    await _syncAssignmentToLibrary(
      assignmentId: assignmentId,
      title: title.trim(),
    );
  }

  Future<void> _syncAssignmentToLibrary({
    required String assignmentId,
    required String title,
  }) async {
    final snap = await _assignments.doc(assignmentId).get();
    final data = snap.data();
    if (data == null) return;
    final libraryItemId = data['libraryItemId'] as String?;
    final circleId = data['circleId'] as String? ?? '';
    final blocksSnap = await _blocks
        .where('circleId', isEqualTo: circleId)
        .where('assignmentId', isEqualTo: assignmentId)
        .get();
    final blocks = blocksSnap.docs.map((d) {
      final m = d.data();
      return {
        'kind': m['kind'],
        'type': m['type'],
        'required': m['required'] ?? false,
        'order': m['order'] ?? 0,
        'payload': m['payload'] ?? {},
      };
    }).toList()
      ..sort(
        (a, b) => ((a['order'] as num?)?.toInt() ?? 0)
            .compareTo((b['order'] as num?)?.toInt() ?? 0),
      );

    if (libraryItemId == null || libraryItemId.isEmpty) return;
    final libSnap = await _db.collection('libraryItems').doc(libraryItemId).get();
    final meta = Map<String, dynamic>.from(libSnap.data()?['meta'] as Map? ?? {});
    meta['circleId'] = circleId;
    meta['assignmentId'] = assignmentId;
    meta['blocks'] = blocks;
    await _db.collection('libraryItems').doc(libraryItemId).update({
      'title': title,
      'meta': meta,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> addBlock({
    required String circleId,
    required String assignmentId,
    required BlockKind kind,
    required String type,
    required int order,
    bool required = false,
    Map<String, dynamic> payload = const {},
  }) async {
    final ref = _blocks.doc();
    await ref.set({
      'circleId': circleId,
      'assignmentId': assignmentId,
      'order': order,
      'kind': kind == BlockKind.input ? 'input' : 'content',
      'type': type,
      'required': required,
      'payload': payload,
    });
    return ref.id;
  }

  Future<void> updateBlock({
    required String blockId,
    int? order,
    bool? required,
    Map<String, dynamic>? payload,
    String? type,
  }) async {
    final data = <String, dynamic>{};
    if (order != null) data['order'] = order;
    if (required != null) data['required'] = required;
    if (payload != null) data['payload'] = payload;
    if (type != null) data['type'] = type;
    if (data.isEmpty) return;
    await _blocks.doc(blockId).update(data);
  }

  Future<void> deleteBlock(String blockId) async {
    await _blocks.doc(blockId).delete();
  }

  Future<void> reorderBlocks(List<AssignmentBlock> ordered) async {
    final batch = _db.batch();
    for (var i = 0; i < ordered.length; i++) {
      batch.update(_blocks.doc(ordered[i].id), {'order': i});
    }
    await batch.commit();
  }

  Future<void> upsertAnswer({
    required String circleId,
    required String assignmentId,
    required String blockId,
    required String userId,
    required Map<String, dynamic> value,
    required List<AssignmentBlock> blocks,
  }) async {
    final id = '${assignmentId}_${blockId}_$userId';
    await _answers.doc(id).set({
      'circleId': circleId,
      'assignmentId': assignmentId,
      'blockId': blockId,
      'userId': userId,
      'value': value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _refreshSubmissionProgress(
      circleId: circleId,
      assignmentId: assignmentId,
      userId: userId,
      blocks: blocks,
    );
  }

  Future<void> submitAssignment({
    required String circleId,
    required String assignmentId,
    required String userId,
    required List<AssignmentBlock> blocks,
    required Assignment assignment,
  }) async {
    final answersSnap = await _answers
        .where('circleId', isEqualTo: circleId)
        .where('assignmentId', isEqualTo: assignmentId)
        .where('userId', isEqualTo: userId)
        .get();
    final answers = {
      for (final d in answersSnap.docs)
        BlockAnswer.fromMap(d.id, d.data()).blockId:
            BlockAnswer.fromMap(d.id, d.data()),
    };

    final requiredBlocks =
        blocks.where((b) => b.isInput && b.required).toList();
    for (final b in requiredBlocks) {
      final a = answers[b.id];
      if (a == null || !a.hasValue) {
        throw StateError('Required block ${b.id} is incomplete');
      }
    }

    final now = DateTime.now();
    final pastDue =
        assignment.dueAt != null && now.isAfter(assignment.dueAt!);
    if (pastDue && !assignment.allowLate) {
      throw StateError('Past due date');
    }

    final answered = requiredBlocks
        .where((b) => answers[b.id]?.hasValue == true)
        .length;

    await _submissions.doc('${assignmentId}_$userId').set({
      'circleId': circleId,
      'assignmentId': assignmentId,
      'userId': userId,
      'status': submissionStatusToString(
        pastDue ? SubmissionStatus.late : SubmissionStatus.submitted,
      ),
      'answeredRequiredCount': answered,
      'requiredCount': requiredBlocks.length,
      'submittedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _refreshSubmissionProgress({
    required String circleId,
    required String assignmentId,
    required String userId,
    required List<AssignmentBlock> blocks,
  }) async {
    final answersSnap = await _answers
        .where('circleId', isEqualTo: circleId)
        .where('assignmentId', isEqualTo: assignmentId)
        .where('userId', isEqualTo: userId)
        .get();
    final byBlock = {
      for (final d in answersSnap.docs)
        BlockAnswer.fromMap(d.id, d.data()).blockId:
            BlockAnswer.fromMap(d.id, d.data()),
    };

    final requiredBlocks =
        blocks.where((b) => b.isInput && b.required).toList();
    final answered =
        requiredBlocks.where((b) => byBlock[b.id]?.hasValue == true).length;

    final id = '${assignmentId}_$userId';
    final existing = await _submissions.doc(id).get();
    final existingStatus = existing.data()?['status'] as String?;
    if (existingStatus == 'submitted' || existingStatus == 'late') {
      await _submissions.doc(id).set({
        'answeredRequiredCount': answered,
        'requiredCount': requiredBlocks.length,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final status = answered > 0
        ? SubmissionStatus.inProgress
        : SubmissionStatus.notStarted;

    await _submissions.doc(id).set({
      'circleId': circleId,
      'assignmentId': assignmentId,
      'userId': userId,
      'status': submissionStatusToString(status),
      'answeredRequiredCount': answered,
      'requiredCount': requiredBlocks.length,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> createPublishedWithMinimalBlocks({
    required String circleId,
    required String createdBy,
    required String title,
    String? body,
    String? questionPrompt,
    String? fromLibraryItemId,
  }) async {
    final assignmentId = await createDraftAssignment(
      circleId: circleId,
      createdBy: createdBy,
      title: title,
      fromLibraryItemId: fromLibraryItemId,
      skipLibraryMirror: fromLibraryItemId != null,
    );
    var order = 0;
    final textBody = (body ?? '').trim();
    if (textBody.isNotEmpty) {
      await addBlock(
        circleId: circleId,
        assignmentId: assignmentId,
        kind: BlockKind.content,
        type: 'text',
        order: order++,
        payload: {'body': textBody},
      );
    }
    await addBlock(
      circleId: circleId,
      assignmentId: assignmentId,
      kind: BlockKind.input,
      type: 'question',
      order: order,
      required: true,
      payload: {
        'prompt': (questionPrompt ?? 'Your response').trim(),
        'longAnswer': true,
      },
    );
    await publishAssignment(assignmentId: assignmentId, title: title);
    return assignmentId;
  }

  /// Rebuild a published assignment from a library `meta.blocks` snapshot.
  Future<String> createPublishedFromBlockSnapshot({
    required String circleId,
    required String createdBy,
    required String title,
    required List<dynamic> blocks,
    String? fromLibraryItemId,
  }) async {
    final assignmentId = await createDraftAssignment(
      circleId: circleId,
      createdBy: createdBy,
      title: title,
      fromLibraryItemId: fromLibraryItemId,
      skipLibraryMirror: fromLibraryItemId != null,
    );
    var order = 0;
    for (final raw in blocks) {
      if (raw is! Map) continue;
      final kind = (raw['kind'] as String?) == 'input'
          ? BlockKind.input
          : BlockKind.content;
      await addBlock(
        circleId: circleId,
        assignmentId: assignmentId,
        kind: kind,
        type: raw['type'] as String? ?? 'text',
        order: order++,
        required: raw['required'] as bool? ?? false,
        payload: Map<String, dynamic>.from(raw['payload'] as Map? ?? {}),
      );
    }
    await publishAssignment(assignmentId: assignmentId, title: title);
    return assignmentId;
  }

  // --- Legacy read ---

  Stream<List<Objective>> watchObjectivesForAssignments(
    List<String> assignmentIds, {
    String? circleId,
  }) {
    if (assignmentIds.isEmpty) return Stream.value(const []);
    if (circleId != null && circleId.isNotEmpty) {
      return _db
          .collection('objectives')
          .where('circleId', isEqualTo: circleId)
          .snapshots()
          .map((snap) {
        final idSet = assignmentIds.toSet();
        final list = snap.docs
            .map((d) => Objective.fromMap(d.id, d.data()))
            .where((o) => idSet.contains(o.assignmentId))
            .toList();
        list.sort((a, b) => a.order.compareTo(b.order));
        return list;
      });
    }
    final ids = assignmentIds.take(10).toList();
    return _db
        .collection('objectives')
        .where('assignmentId', whereIn: ids)
        .snapshots()
        .map((snap) {
      final list =
          snap.docs.map((d) => Objective.fromMap(d.id, d.data())).toList();
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

  Stream<List<ProgressLog>> watchCircleProgress(String circleId) {
    return _db
        .collection('progressLogs')
        .where('circleId', isEqualTo: circleId)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => ProgressLog.fromMap(d.id, d.data()))
              .toList(),
        );
  }
}

List<AssignmentProgressView> buildProgressViews({
  required List<Assignment> assignments,
  required List<AssignmentSubmission> submissions,
}) {
  final byAssignment = {for (final s in submissions) s.assignmentId: s};
  return assignments.map((a) {
    final s = byAssignment[a.id];
    return AssignmentProgressView(
      assignment: a,
      state: deriveProgressState(
        requiredCount: s?.requiredCount ?? 0,
        answeredRequiredCount: s?.answeredRequiredCount ?? 0,
        submissionStatus: s?.status,
      ),
      answeredRequiredCount: s?.answeredRequiredCount ?? 0,
      requiredCount: s?.requiredCount ?? 0,
    );
  }).toList();
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

Map<String, List<CoinView>> buildMemberCoinViews({
  required List<Assignment> assignments,
  required List<Objective> objectives,
  required List<ProgressLog> logs,
  required Iterable<String> userIds,
}) {
  final map = <String, List<CoinView>>{};
  for (final uid in userIds) {
    map[uid] = buildCoinViews(
      assignments: assignments,
      objectives: objectives,
      logs: logs.where((l) => l.userId == uid).toList(),
    );
  }
  return map;
}

({int completed, int total}) coinTotals(List<CoinView> coins) {
  var completed = 0;
  var total = 0;
  for (final c in coins) {
    completed += c.completedCount;
    total += c.totalCount;
  }
  return (completed: completed, total: total);
}
