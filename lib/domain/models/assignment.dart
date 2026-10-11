enum ObjectiveType {
  purpose,
  morningPractice,
  readDoc,
  practiceMinutes,
  listenAudio,
  curriculum,
}

enum ProgressStatus { pending, completed }

enum CoinState { pending, inProgress, completed }

class Assignment {
  const Assignment({
    required this.id,
    required this.circleId,
    required this.createdBy,
    required this.title,
    required this.createdAt,
    this.description,
    this.status = 'active',
  });

  final String id;
  final String circleId;
  final String createdBy;
  final String title;
  final String? description;
  final DateTime createdAt;
  final String status;

  factory Assignment.fromMap(String id, Map<String, dynamic> data) {
    return Assignment(
      id: id,
      circleId: data['circleId'] as String? ?? '',
      createdBy: data['createdBy'] as String? ?? '',
      title: data['title'] as String? ?? '',
      description: data['description'] as String?,
      createdAt:
          (data['createdAt'] as dynamic)?.toDate() as DateTime? ?? DateTime.now(),
      status: data['status'] as String? ?? 'active',
    );
  }
}

class Objective {
  const Objective({
    required this.id,
    required this.assignmentId,
    required this.type,
    required this.order,
    this.criteria = const {},
    this.evidenceSpec = const {},
    this.weight,
  });

  final String id;
  final String assignmentId;
  final ObjectiveType type;
  final Map<String, dynamic> criteria;
  final Map<String, dynamic> evidenceSpec;
  final int order;
  final double? weight;

  factory Objective.fromMap(String id, Map<String, dynamic> data) {
    return Objective(
      id: id,
      assignmentId: data['assignmentId'] as String? ?? '',
      type: objectiveTypeFromString(data['type'] as String? ?? 'purpose'),
      criteria: Map<String, dynamic>.from(data['criteria'] as Map? ?? {}),
      evidenceSpec:
          Map<String, dynamic>.from(data['evidenceSpec'] as Map? ?? {}),
      order: (data['order'] as num?)?.toInt() ?? 0,
      weight: (data['weight'] as num?)?.toDouble(),
    );
  }

  String get label {
    switch (type) {
      case ObjectiveType.purpose:
        return 'Purpose';
      case ObjectiveType.morningPractice:
        return 'Morning practice';
      case ObjectiveType.readDoc:
        return 'Read document';
      case ObjectiveType.practiceMinutes:
        return 'Practice (minutes)';
      case ObjectiveType.listenAudio:
        return 'Listen to audio';
      case ObjectiveType.curriculum:
        return 'Curriculum';
    }
  }
}

class ProgressLog {
  const ProgressLog({
    required this.id,
    required this.assignmentId,
    required this.objectiveId,
    required this.userId,
    required this.status,
    required this.updatedAt,
    this.circleId,
    this.evidence = const {},
    this.completedAt,
  });

  final String id;
  final String? circleId;
  final String assignmentId;
  final String objectiveId;
  final String userId;
  final ProgressStatus status;
  final Map<String, dynamic> evidence;
  final DateTime? completedAt;
  final DateTime updatedAt;

  factory ProgressLog.fromMap(String id, Map<String, dynamic> data) {
    return ProgressLog(
      id: id,
      circleId: data['circleId'] as String?,
      assignmentId: data['assignmentId'] as String? ?? '',
      objectiveId: data['objectiveId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      status: (data['status'] as String?) == 'completed'
          ? ProgressStatus.completed
          : ProgressStatus.pending,
      evidence: Map<String, dynamic>.from(data['evidence'] as Map? ?? {}),
      completedAt: (data['completedAt'] as dynamic)?.toDate() as DateTime?,
      updatedAt:
          (data['updatedAt'] as dynamic)?.toDate() as DateTime? ?? DateTime.now(),
    );
  }
}

class CoinView {
  const CoinView({
    required this.assignment,
    required this.objectives,
    required this.state,
    required this.completedCount,
    this.completedObjectiveIds = const {},
  });

  final Assignment assignment;
  final List<Objective> objectives;
  final CoinState state;
  final int completedCount;
  final Set<String> completedObjectiveIds;

  int get totalCount => objectives.length;

  bool isObjectiveCompleted(String objectiveId) =>
      completedObjectiveIds.contains(objectiveId);
}

ObjectiveType objectiveTypeFromString(String value) {
  switch (value) {
    case 'morning_practice':
      return ObjectiveType.morningPractice;
    case 'read_doc':
      return ObjectiveType.readDoc;
    case 'practice_minutes':
      return ObjectiveType.practiceMinutes;
    case 'listen_audio':
      return ObjectiveType.listenAudio;
    case 'curriculum':
      return ObjectiveType.curriculum;
    case 'purpose':
    default:
      return ObjectiveType.purpose;
  }
}

String objectiveTypeToString(ObjectiveType type) {
  switch (type) {
    case ObjectiveType.purpose:
      return 'purpose';
    case ObjectiveType.morningPractice:
      return 'morning_practice';
    case ObjectiveType.readDoc:
      return 'read_doc';
    case ObjectiveType.practiceMinutes:
      return 'practice_minutes';
    case ObjectiveType.listenAudio:
      return 'listen_audio';
    case ObjectiveType.curriculum:
      return 'curriculum';
  }
}

CoinState deriveCoinState({
  required List<Objective> objectives,
  required Iterable<ProgressLog> logs,
}) {
  if (objectives.isEmpty) return CoinState.pending;
  final completedIds = logs
      .where((l) => l.status == ProgressStatus.completed)
      .map((l) => l.objectiveId)
      .toSet();
  final done = objectives.where((o) => completedIds.contains(o.id)).length;
  if (done == 0) return CoinState.pending;
  if (done >= objectives.length) return CoinState.completed;
  return CoinState.inProgress;
}
