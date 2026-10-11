enum ChallengeKind { media, quest }

enum ChallengeMediaKind { audio, video }

enum ChallengeStatus { active, archived }

enum EnrollmentStatus { active, completed, cancelled }

enum SessionState { scheduled, inProgress, completed, skipped, missed }

class Challenge {
  const Challenge({
    required this.id,
    required this.circleId,
    required this.title,
    required this.kind,
    required this.durationDays,
    required this.createdBy,
    required this.createdAt,
    this.description,
    this.mediaKind,
    this.storagePath,
    this.contentType,
    this.instructions,
    this.preAlarmMinutes = 10,
    this.status = ChallengeStatus.active,
  });

  final String id;
  final String circleId;
  final String title;
  final String? description;
  final ChallengeKind kind;
  final ChallengeMediaKind? mediaKind;
  final String? storagePath;
  final String? contentType;
  final String? instructions;
  final int durationDays;
  final int preAlarmMinutes;
  final ChallengeStatus status;
  final String createdBy;
  final DateTime createdAt;

  bool get isMedia => kind == ChallengeKind.media;
  bool get isQuest => kind == ChallengeKind.quest;

  factory Challenge.fromMap(String id, Map<String, dynamic> data) {
    return Challenge(
      id: id,
      circleId: data['circleId'] as String? ?? '',
      title: data['title'] as String? ?? '',
      description: data['description'] as String?,
      kind: challengeKindFromString(data['kind'] as String? ?? 'quest'),
      mediaKind: data['mediaKind'] != null
          ? challengeMediaKindFromString(data['mediaKind'] as String)
          : null,
      storagePath: data['storagePath'] as String?,
      contentType: data['contentType'] as String?,
      instructions: data['instructions'] as String?,
      durationDays: (data['durationDays'] as num?)?.toInt() ?? 1,
      preAlarmMinutes: (data['preAlarmMinutes'] as num?)?.toInt() ?? 10,
      status: challengeStatusFromString(data['status'] as String? ?? 'active'),
      createdBy: data['createdBy'] as String? ?? '',
      createdAt:
          (data['createdAt'] as dynamic)?.toDate() as DateTime? ?? DateTime.now(),
    );
  }
}

class ChallengeEnrollment {
  const ChallengeEnrollment({
    required this.id,
    required this.circleId,
    required this.challengeId,
    required this.userId,
    required this.startDate,
    required this.dailyTime,
    required this.timezone,
    required this.status,
    required this.createdAt,
    this.completedAt,
  });

  final String id;
  final String circleId;
  final String challengeId;
  final String userId;
  final String startDate;
  final String dailyTime;
  final String timezone;
  final EnrollmentStatus status;
  final DateTime createdAt;
  final DateTime? completedAt;

  factory ChallengeEnrollment.fromMap(String id, Map<String, dynamic> data) {
    return ChallengeEnrollment(
      id: id,
      circleId: data['circleId'] as String? ?? '',
      challengeId: data['challengeId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      startDate: data['startDate'] as String? ?? '',
      dailyTime: data['dailyTime'] as String? ?? '07:00',
      timezone: data['timezone'] as String? ?? 'UTC',
      status: enrollmentStatusFromString(data['status'] as String? ?? 'active'),
      createdAt:
          (data['createdAt'] as dynamic)?.toDate() as DateTime? ?? DateTime.now(),
      completedAt: (data['completedAt'] as dynamic)?.toDate() as DateTime?,
    );
  }
}

class ChallengeSession {
  const ChallengeSession({
    required this.id,
    required this.circleId,
    required this.challengeId,
    required this.enrollmentId,
    required this.userId,
    required this.dayIndex,
    required this.scheduledAt,
    required this.state,
    this.startedAt,
    this.completedAt,
    this.evidence = const {},
    this.playbackEnded,
  });

  final String id;
  final String circleId;
  final String challengeId;
  final String enrollmentId;
  final String userId;
  final int dayIndex;
  final DateTime scheduledAt;
  final SessionState state;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final Map<String, dynamic> evidence;
  final bool? playbackEnded;

  factory ChallengeSession.fromMap(String id, Map<String, dynamic> data) {
    return ChallengeSession(
      id: id,
      circleId: data['circleId'] as String? ?? '',
      challengeId: data['challengeId'] as String? ?? '',
      enrollmentId: data['enrollmentId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      dayIndex: (data['dayIndex'] as num?)?.toInt() ?? 1,
      scheduledAt:
          (data['scheduledAt'] as dynamic)?.toDate() as DateTime? ?? DateTime.now(),
      state: sessionStateFromString(data['state'] as String? ?? 'scheduled'),
      startedAt: (data['startedAt'] as dynamic)?.toDate() as DateTime?,
      completedAt: (data['completedAt'] as dynamic)?.toDate() as DateTime?,
      evidence: Map<String, dynamic>.from(data['evidence'] as Map? ?? {}),
      playbackEnded: data['playbackEnded'] as bool?,
    );
  }
}

ChallengeKind challengeKindFromString(String value) {
  switch (value) {
    case 'media':
      return ChallengeKind.media;
    default:
      return ChallengeKind.quest;
  }
}

String challengeKindToString(ChallengeKind kind) {
  switch (kind) {
    case ChallengeKind.media:
      return 'media';
    case ChallengeKind.quest:
      return 'quest';
  }
}

ChallengeMediaKind challengeMediaKindFromString(String value) {
  switch (value) {
    case 'video':
      return ChallengeMediaKind.video;
    default:
      return ChallengeMediaKind.audio;
  }
}

String challengeMediaKindToString(ChallengeMediaKind kind) {
  switch (kind) {
    case ChallengeMediaKind.audio:
      return 'audio';
    case ChallengeMediaKind.video:
      return 'video';
  }
}

ChallengeStatus challengeStatusFromString(String value) {
  switch (value) {
    case 'archived':
      return ChallengeStatus.archived;
    default:
      return ChallengeStatus.active;
  }
}

EnrollmentStatus enrollmentStatusFromString(String value) {
  switch (value) {
    case 'completed':
      return EnrollmentStatus.completed;
    case 'cancelled':
      return EnrollmentStatus.cancelled;
    default:
      return EnrollmentStatus.active;
  }
}

SessionState sessionStateFromString(String value) {
  switch (value) {
    case 'in_progress':
      return SessionState.inProgress;
    case 'completed':
      return SessionState.completed;
    case 'skipped':
      return SessionState.skipped;
    case 'missed':
      return SessionState.missed;
    default:
      return SessionState.scheduled;
  }
}

String sessionStateToString(SessionState state) {
  switch (state) {
    case SessionState.scheduled:
      return 'scheduled';
    case SessionState.inProgress:
      return 'in_progress';
    case SessionState.completed:
      return 'completed';
    case SessionState.skipped:
      return 'skipped';
    case SessionState.missed:
      return 'missed';
  }
}

/// Local calendar day + HH:mm → DateTime for dayIndex (1-based from startDate).
DateTime scheduledAtForDay({
  required String startDate,
  required String dailyTime,
  required int dayIndex,
}) {
  final d = startDate.split('-');
  final t = dailyTime.split(':');
  final base = DateTime(
    int.parse(d[0]),
    int.parse(d[1]),
    int.parse(d[2]),
    int.parse(t[0]),
    int.parse(t[1]),
  );
  return base.add(Duration(days: dayIndex - 1));
}

String formatDateYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String formatTimeHm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';
