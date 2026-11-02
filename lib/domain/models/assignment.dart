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

enum AssignmentStatus { draft, published, archived }

enum BlockKind { content, input }

enum SubmissionStatus { notStarted, inProgress, submitted, late }

class Assignment {
  const Assignment({
    required this.id,
    required this.circleId,
    required this.createdBy,
    required this.title,
    required this.createdAt,
    this.description,
    this.status = AssignmentStatus.draft,
    this.opensAt,
    this.dueAt,
    this.allowLate = false,
    this.publishedAt,
  });

  final String id;
  final String circleId;
  final String createdBy;
  final String title;
  final String? description;
  final DateTime createdAt;
  final AssignmentStatus status;
  final DateTime? opensAt;
  final DateTime? dueAt;
  final bool allowLate;
  final DateTime? publishedAt;

  bool get isDraft => status == AssignmentStatus.draft;
  bool get isPublished => status == AssignmentStatus.published;

  factory Assignment.fromMap(String id, Map<String, dynamic> data) {
    return Assignment(
      id: id,
      circleId: data['circleId'] as String? ?? '',
      createdBy: data['createdBy'] as String? ?? '',
      title: data['title'] as String? ?? '',
      description: data['description'] as String?,
      createdAt:
          (data['createdAt'] as dynamic)?.toDate() as DateTime? ?? DateTime.now(),
      status: assignmentStatusFromString(data['status'] as String?),
      opensAt: (data['opensAt'] as dynamic)?.toDate() as DateTime?,
      dueAt: (data['dueAt'] as dynamic)?.toDate() as DateTime?,
      allowLate: data['allowLate'] as bool? ?? false,
      publishedAt: (data['publishedAt'] as dynamic)?.toDate() as DateTime?,
    );
  }
}

AssignmentStatus assignmentStatusFromString(String? value) {
  switch (value) {
    case 'published':
    case 'active':
      return AssignmentStatus.published;
    case 'archived':
      return AssignmentStatus.archived;
    case 'draft':
    default:
      return AssignmentStatus.draft;
  }
}

String assignmentStatusToString(AssignmentStatus status) {
  switch (status) {
    case AssignmentStatus.draft:
      return 'draft';
    case AssignmentStatus.published:
      return 'published';
    case AssignmentStatus.archived:
      return 'archived';
  }
}

class AssignmentBlock {
  const AssignmentBlock({
    required this.id,
    required this.circleId,
    required this.assignmentId,
    required this.order,
    required this.kind,
    required this.type,
    this.required = false,
    this.payload = const {},
  });

  final String id;
  final String circleId;
  final String assignmentId;
  final int order;
  final BlockKind kind;
  final String type;
  final bool required;
  final Map<String, dynamic> payload;

  bool get isContent => kind == BlockKind.content;
  bool get isInput => kind == BlockKind.input;

  factory AssignmentBlock.fromMap(String id, Map<String, dynamic> data) {
    return AssignmentBlock(
      id: id,
      circleId: data['circleId'] as String? ?? '',
      assignmentId: data['assignmentId'] as String? ?? '',
      order: (data['order'] as num?)?.toInt() ?? 0,
      kind: (data['kind'] as String?) == 'input'
          ? BlockKind.input
          : BlockKind.content,
      type: data['type'] as String? ?? 'text',
      required: data['required'] as bool? ?? false,
      payload: Map<String, dynamic>.from(data['payload'] as Map? ?? {}),
    );
  }
}

class BlockAnswer {
  const BlockAnswer({
    required this.id,
    required this.circleId,
    required this.assignmentId,
    required this.blockId,
    required this.userId,
    required this.updatedAt,
    this.value = const {},
  });

  final String id;
  final String circleId;
  final String assignmentId;
  final String blockId;
  final String userId;
  final Map<String, dynamic> value;
  final DateTime updatedAt;

  factory BlockAnswer.fromMap(String id, Map<String, dynamic> data) {
    return BlockAnswer(
      id: id,
      circleId: data['circleId'] as String? ?? '',
      assignmentId: data['assignmentId'] as String? ?? '',
      blockId: data['blockId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      value: Map<String, dynamic>.from(data['value'] as Map? ?? {}),
      updatedAt:
          (data['updatedAt'] as dynamic)?.toDate() as DateTime? ?? DateTime.now(),
    );
  }

  bool get hasValue {
    if (value.isEmpty) return false;
    final text = value['text'] as String?;
    if (text != null && text.trim().isNotEmpty) return true;
    final ids = value['selectedOptionIds'];
    if (ids is List && ids.isNotEmpty) return true;
    final files = value['files'];
    if (files is List && files.isNotEmpty) return true;
    return false;
  }
}

class AssignmentSubmission {
  const AssignmentSubmission({
    required this.id,
    required this.circleId,
    required this.assignmentId,
    required this.userId,
    required this.status,
    required this.answeredRequiredCount,
    required this.requiredCount,
    required this.updatedAt,
    this.submittedAt,
    this.facilitatorFeedback,
  });

  final String id;
  final String circleId;
  final String assignmentId;
  final String userId;
  final SubmissionStatus status;
  final int answeredRequiredCount;
  final int requiredCount;
  final DateTime? submittedAt;
  final DateTime updatedAt;
  final String? facilitatorFeedback;

  factory AssignmentSubmission.fromMap(String id, Map<String, dynamic> data) {
    return AssignmentSubmission(
      id: id,
      circleId: data['circleId'] as String? ?? '',
      assignmentId: data['assignmentId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      status: submissionStatusFromString(data['status'] as String?),
      answeredRequiredCount:
          (data['answeredRequiredCount'] as num?)?.toInt() ?? 0,
      requiredCount: (data['requiredCount'] as num?)?.toInt() ?? 0,
      submittedAt: (data['submittedAt'] as dynamic)?.toDate() as DateTime?,
      updatedAt:
          (data['updatedAt'] as dynamic)?.toDate() as DateTime? ?? DateTime.now(),
      facilitatorFeedback: data['facilitatorFeedback'] as String?,
    );
  }
}

SubmissionStatus submissionStatusFromString(String? value) {
  switch (value) {
    case 'inProgress':
      return SubmissionStatus.inProgress;
    case 'submitted':
      return SubmissionStatus.submitted;
    case 'late':
      return SubmissionStatus.late;
    case 'notStarted':
    default:
      return SubmissionStatus.notStarted;
  }
}

String submissionStatusToString(SubmissionStatus status) {
  switch (status) {
    case SubmissionStatus.notStarted:
      return 'notStarted';
    case SubmissionStatus.inProgress:
      return 'inProgress';
    case SubmissionStatus.submitted:
      return 'submitted';
    case SubmissionStatus.late:
      return 'late';
  }
}

class AssignmentProgressView {
  const AssignmentProgressView({
    required this.assignment,
    required this.state,
    required this.answeredRequiredCount,
    required this.requiredCount,
  });

  final Assignment assignment;
  final CoinState state;
  final int answeredRequiredCount;
  final int requiredCount;

  int get totalCount => requiredCount;
  int get completedCount => answeredRequiredCount;
}

// --- Legacy ---

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

CoinState deriveProgressState({
  required int requiredCount,
  required int answeredRequiredCount,
  required SubmissionStatus? submissionStatus,
}) {
  if (submissionStatus == SubmissionStatus.submitted ||
      submissionStatus == SubmissionStatus.late) {
    return CoinState.completed;
  }
  if (requiredCount <= 0) {
    return submissionStatus == SubmissionStatus.inProgress
        ? CoinState.inProgress
        : CoinState.pending;
  }
  if (answeredRequiredCount <= 0) return CoinState.pending;
  return CoinState.inProgress;
}
