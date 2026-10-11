class LastPostPreview {
  const LastPostPreview({
    required this.type,
    required this.body,
    required this.authorId,
    required this.createdAt,
    this.kind,
  });

  final String type;
  final String body;
  final String authorId;
  final DateTime createdAt;
  final String? kind;

  factory LastPostPreview.fromMap(Map<String, dynamic> data) {
    return LastPostPreview(
      type: data['type'] as String? ?? 'free',
      body: data['body'] as String? ?? '',
      authorId: data['authorId'] as String? ?? '',
      createdAt:
          (data['createdAt'] as dynamic)?.toDate() as DateTime? ?? DateTime.now(),
      kind: data['kind'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type,
        'body': body,
        'authorId': authorId,
        'createdAt': createdAt,
        if (kind != null) 'kind': kind,
      };
}

class Circle {
  const Circle({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.updatedAt,
    this.description = '',
    this.photoURL,
    this.pointerId,
    this.timeKeeperId,
    this.nextMeetingAt,
    this.lastPost,
  });

  final String id;
  final String name;
  final String description;
  final String? photoURL;
  final String createdBy;
  final String? pointerId;
  final String? timeKeeperId;
  final DateTime? nextMeetingAt;
  final LastPostPreview? lastPost;
  final DateTime updatedAt;

  factory Circle.fromMap(String id, Map<String, dynamic> data) {
    final last = data['lastPost'];
    return Circle(
      id: id,
      name: data['name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      photoURL: data['photoURL'] as String?,
      createdBy: data['createdBy'] as String? ?? '',
      pointerId: data['pointerId'] as String?,
      timeKeeperId: data['timeKeeperId'] as String?,
      nextMeetingAt: (data['nextMeetingAt'] as dynamic)?.toDate() as DateTime?,
      lastPost: last is Map<String, dynamic>
          ? LastPostPreview.fromMap(last)
          : null,
      updatedAt:
          (data['updatedAt'] as dynamic)?.toDate() as DateTime? ?? DateTime.now(),
    );
  }
}

class Membership {
  const Membership({
    required this.id,
    required this.circleId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.lastOpenedAt,
    this.unreadCount = 0,
  });

  final String id;
  final String circleId;
  final String userId;
  final String role; // admin | member
  final DateTime joinedAt;
  final DateTime? lastOpenedAt;
  final int unreadCount;

  bool get isAdmin => role == 'admin';

  factory Membership.fromMap(String id, Map<String, dynamic> data) {
    final unreadRaw = data['unreadCount'];
    final unread = unreadRaw is int
        ? unreadRaw
        : unreadRaw is num
            ? unreadRaw.toInt()
            : 0;
    return Membership(
      id: id,
      circleId: data['circleId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      role: data['role'] as String? ?? 'member',
      joinedAt:
          (data['joinedAt'] as dynamic)?.toDate() as DateTime? ?? DateTime.now(),
      lastOpenedAt: (data['lastOpenedAt'] as dynamic)?.toDate() as DateTime?,
      unreadCount: unread < 0 ? 0 : unread,
    );
  }
}
