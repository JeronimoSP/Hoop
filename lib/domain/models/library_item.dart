enum LibraryItemKind { resource, challenge, assignment }

class LibraryItem {
  const LibraryItem({
    required this.id,
    required this.ownerId,
    required this.kind,
    required this.title,
    required this.body,
    required this.meta,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String ownerId;
  final LibraryItemKind kind;
  final String title;
  final String body;
  final Map<String, dynamic> meta;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory LibraryItem.fromMap(String id, Map<String, dynamic> data) {
    return LibraryItem(
      id: id,
      ownerId: data['ownerId'] as String? ?? '',
      kind: libraryItemKindFromString(data['kind'] as String? ?? 'resource'),
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      meta: Map<String, dynamic>.from(data['meta'] as Map? ?? {}),
      createdAt:
          (data['createdAt'] as dynamic)?.toDate() as DateTime? ?? DateTime.now(),
      updatedAt:
          (data['updatedAt'] as dynamic)?.toDate() as DateTime? ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'ownerId': ownerId,
        'kind': libraryItemKindToString(kind),
        'title': title,
        'body': body,
        'meta': meta,
      };
}

LibraryItemKind libraryItemKindFromString(String value) {
  switch (value) {
    case 'challenge':
      return LibraryItemKind.challenge;
    case 'assignment':
      return LibraryItemKind.assignment;
    case 'resource':
    default:
      return LibraryItemKind.resource;
  }
}

String libraryItemKindToString(LibraryItemKind kind) {
  switch (kind) {
    case LibraryItemKind.resource:
      return 'resource';
    case LibraryItemKind.challenge:
      return 'challenge';
    case LibraryItemKind.assignment:
      return 'assignment';
  }
}

String libraryItemKindLabel(LibraryItemKind kind) {
  switch (kind) {
    case LibraryItemKind.resource:
      return 'Resource';
    case LibraryItemKind.challenge:
      return 'Challenge';
    case LibraryItemKind.assignment:
      return 'Assignment';
  }
}
