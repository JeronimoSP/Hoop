enum PostType { instruction, resource, discussion, free, system, media }

enum PostStatus { pending, sent, failed }

/// Quote target when replying to another post (WhatsApp-style).
class PostReplyTo {
  const PostReplyTo({
    required this.postId,
    required this.authorId,
    required this.preview,
    this.kind = 'text',
  });

  final String postId;
  final String authorId;
  final String preview;
  final String kind;

  Map<String, dynamic> toMap() => {
        'postId': postId,
        'authorId': authorId,
        'preview': preview,
        'kind': kind,
      };

  factory PostReplyTo.fromMap(Map<String, dynamic> data) {
    return PostReplyTo(
      postId: data['postId'] as String? ?? '',
      authorId: data['authorId'] as String? ?? '',
      preview: data['preview'] as String? ?? '',
      kind: data['kind'] as String? ?? 'text',
    );
  }

  static PostReplyTo? fromPost(CirclePost post) {
    final preview = post.isEmojiMedia
        ? post.body
        : post.body.trim().isNotEmpty
            ? (post.body.length > 80
                ? '${post.body.substring(0, 80)}…'
                : post.body)
            : postTypeLabel(post.type, kind: post.kind);
    return PostReplyTo(
      postId: post.id,
      authorId: post.authorId,
      preview: preview,
      kind: post.isEmojiMedia
          ? 'emoji'
          : post.isImageMedia
              ? 'image'
              : post.isAudioMedia
                  ? 'audio'
                  : post.isVideoMedia
                      ? 'video'
                      : post.isPdfMedia
                          ? 'pdf'
                          : 'text',
    );
  }
}

class PostReaction {
  const PostReaction({
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });

  final String userId;
  final String emoji;
  final DateTime createdAt;

  factory PostReaction.fromMap(String id, Map<String, dynamic> data) {
    return PostReaction(
      userId: data['userId'] as String? ?? id,
      emoji: data['emoji'] as String? ?? '',
      createdAt:
          (data['createdAt'] as dynamic)?.toDate() as DateTime? ?? DateTime.now(),
    );
  }
}

class ReactionSummary {
  const ReactionSummary({
    required this.counts,
    this.myEmoji,
  });

  final Map<String, int> counts;
  final String? myEmoji;

  bool get isEmpty => counts.isEmpty;

  factory ReactionSummary.fromReactions(
    List<PostReaction> reactions, {
    String? myUserId,
  }) {
    final counts = <String, int>{};
    String? mine;
    for (final r in reactions) {
      if (r.emoji.isEmpty) continue;
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
      if (myUserId != null && r.userId == myUserId) {
        mine = r.emoji;
      }
    }
    return ReactionSummary(counts: counts, myEmoji: mine);
  }
}

class CirclePost {
  const CirclePost({
    required this.id,
    required this.authorId,
    required this.type,
    required this.body,
    required this.createdAt,
    this.meta = const {},
    this.status = PostStatus.sent,
    this.replyTo,
  });

  final String id;
  final String authorId;
  final PostType type;
  final String body;
  final Map<String, dynamic> meta;
  final DateTime createdAt;
  final PostStatus status;
  final PostReplyTo? replyTo;

  bool get isSticky => type == PostType.instruction;

  String? get mediaUrl {
    final v = meta['downloadUrl'];
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  String? get storagePath {
    final v = meta['storagePath'];
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  bool get hasMediaRef => mediaUrl != null || storagePath != null;

  String get kind => meta['kind']?.toString() ?? '';

  bool get isPdfMedia =>
      kind == 'pdf' ||
      (type == PostType.media &&
          (meta['contentType']?.toString() == 'application/pdf'));

  bool get isAudioMedia =>
      kind == 'audio' ||
      (type == PostType.media &&
          (meta['contentType']?.toString().startsWith('audio/') ?? false));

  bool get isVideoMedia =>
      kind == 'video' ||
      (type == PostType.media &&
          (meta['contentType']?.toString().startsWith('video/') ?? false));

  bool get isEmojiMedia => kind == 'emoji' || looksLikeEmojiOnly(body);

  bool get isImageMedia {
    if (isPdfMedia || isAudioMedia || isVideoMedia || kind == 'emoji') {
      return false;
    }
    return type == PostType.media || kind == 'image';
  }

  String? get fileName {
    final v = meta['fileName'];
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  int? get durationMs {
    final v = meta['durationMs'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  String? get coverStoragePath {
    final v = meta['coverStoragePath'];
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  String? get coverDownloadUrl {
    final v = meta['coverDownloadUrl'];
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  String get coverStatus => meta['coverStatus']?.toString() ?? '';

  bool get hasCoverRef =>
      coverStoragePath != null || coverDownloadUrl != null;

  /// Server-generated stream thumbnail (≤320×320).
  String? get previewStoragePath {
    final v = meta['previewStoragePath'];
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  String? get previewDownloadUrl {
    final v = meta['previewDownloadUrl'];
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  String get previewStatus => meta['previewStatus']?.toString() ?? '';

  bool get hasPreviewRef =>
      previewStoragePath != null || previewDownloadUrl != null;

  /// Server-generated detail image (≤690×690).
  String? get largeStoragePath {
    final v = meta['largeStoragePath'];
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  String? get largeDownloadUrl {
    final v = meta['largeDownloadUrl'];
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  String get largeStatus => meta['largeStatus']?.toString() ?? '';

  bool get hasLargeRef =>
      largeStoragePath != null || largeDownloadUrl != null;

  /// Cursor Cloud agent reply metadata (`meta.agent` / `meta.agentActions`).
  bool get hasAgentMeta {
    if (meta['agent'] is Map) return true;
    final actions = meta['agentActions'];
    return actions is List && actions.isNotEmpty;
  }

  String? get agentJobId {
    final agent = meta['agent'];
    if (agent is Map) {
      final id = agent['jobId']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  String? get agentPrUrl {
    final agent = meta['agent'];
    if (agent is Map) {
      final url = agent['prUrl']?.toString();
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  List<({String id, String label})> get agentActions {
    final fromAgent = meta['agent'] is Map
        ? (meta['agent'] as Map)['actions']
        : null;
    final raw = fromAgent is List ? fromAgent : meta['agentActions'];
    if (raw is! List) {
      if (!hasAgentMeta) return const [];
      return const [
        (id: 'continue', label: 'Continue'),
        (id: 'open_pr', label: 'Open PR'),
        (id: 'retry', label: 'Retry'),
      ];
    }
    final out = <({String id, String label})>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final id = item['id']?.toString() ?? '';
      final label = item['label']?.toString() ?? id;
      if (id.isEmpty) continue;
      out.add((id: id, label: label));
    }
    return out;
  }

  factory CirclePost.fromMap(String id, Map<String, dynamic> data) {
    final replyRaw = data['replyTo'];
    return CirclePost(
      id: id,
      authorId: data['authorId'] as String? ?? '',
      type: postTypeFromString(data['type'] as String? ?? 'free'),
      body: data['body'] as String? ?? '',
      meta: Map<String, dynamic>.from(data['meta'] as Map? ?? {}),
      createdAt:
          (data['createdAt'] as dynamic)?.toDate() as DateTime? ?? DateTime.now(),
      status: postStatusFromString(data['status'] as String? ?? 'sent'),
      replyTo: replyRaw is Map
          ? PostReplyTo.fromMap(Map<String, dynamic>.from(replyRaw))
          : null,
    );
  }

  CirclePost copyWith({PostStatus? status}) {
    return CirclePost(
      id: id,
      authorId: authorId,
      type: type,
      body: body,
      meta: meta,
      createdAt: createdAt,
      status: status ?? this.status,
      replyTo: replyTo,
    );
  }
}

/// True when [text] is short and has no letters/digits (emoji / emoticon post).
bool looksLikeEmojiOnly(String text) {
  final t = text.trim();
  if (t.isEmpty || t.length > 24) return false;
  if (RegExp(r'[A-Za-z0-9]').hasMatch(t)) return false;
  return t.runes.any((r) => r > 0x00A0);
}

PostType postTypeFromString(String value) {
  return PostType.values.firstWhere(
    (e) => e.name == value,
    orElse: () => PostType.free,
  );
}

PostStatus postStatusFromString(String value) {
  return PostStatus.values.firstWhere(
    (e) => e.name == value,
    orElse: () => PostStatus.sent,
  );
}

String postTypeLabel(PostType type, {String? kind}) {
  if (kind == 'emoji') return 'Emoji';
  if (type == PostType.media) {
    switch (kind) {
      case 'pdf':
        return 'PDF';
      case 'audio':
        return 'Audio';
      case 'video':
        return 'Video';
      case 'emoji':
        return 'Emoji';
      default:
        return 'Image';
    }
  }
  switch (type) {
    case PostType.instruction:
      return 'Instruction';
    case PostType.resource:
      return 'Resource';
    case PostType.discussion:
      return 'Discussion';
    case PostType.free:
      return 'Message';
    case PostType.system:
      return 'System';
    case PostType.media:
      return 'Image';
  }
}

/// Bubble chrome: hide labels for ordinary messages/media (self-explanatory).
/// Keep labels for structured / special posts (resource, instruction, etc.).
bool showBubbleTypeLabel(PostType type, {String? kind}) {
  switch (type) {
    case PostType.resource:
    case PostType.instruction:
    case PostType.discussion:
    case PostType.system:
      return true;
    case PostType.free:
    case PostType.media:
      return false;
  }
}

String lastPostPreviewBody({
  required String type,
  required String body,
  String? kind,
}) {
  if (kind == 'emoji' || looksLikeEmojiOnly(body)) {
    final t = body.trim();
    return t.isEmpty ? 'Emoji' : t;
  }
  if (type == PostType.media.name) {
    final trimmed = body.trim();
    if (trimmed.isNotEmpty) return trimmed;
    switch (kind) {
      case 'pdf':
        return 'PDF';
      case 'audio':
        return 'Audio';
      case 'video':
        return 'Video';
      default:
        return 'Image';
    }
  }
  return body;
}

String formatDurationMs(int? ms) {
  if (ms == null || ms < 0) return '0:00';
  final totalSec = (ms / 1000).round();
  final m = totalSec ~/ 60;
  final s = totalSec % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
