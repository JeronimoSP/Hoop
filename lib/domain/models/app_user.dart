class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.name,
    this.alias = '',
    this.googlePhotoURL,
    this.customPhotoURL,
    this.isPlatformAdmin = false,
    this.createdAt,
  });

  final String uid;
  final String email;
  /// Google / account name (read-only in UI).
  final String name;
  /// Optional nickname shown alongside [name], not instead of it.
  final String alias;
  /// Profile image URL from Google Auth (synced on sign-in; never overwritten by uploads).
  final String? googlePhotoURL;
  /// Circle-only custom avatar in Firebase Storage (never written to Google).
  final String? customPhotoURL;
  final bool isPlatformAdmin;
  final DateTime? createdAt;

  bool get hasCustomPhoto {
    final u = customPhotoURL?.trim();
    return u != null && u.isNotEmpty;
  }

  /// Avatar to show in Circle: custom if set, otherwise Google.
  String? get avatarURL {
    if (hasCustomPhoto) return customPhotoURL!.trim();
    final g = googlePhotoURL?.trim();
    if (g != null && g.isNotEmpty) return g;
    return null;
  }

  /// Legal/Google name for initials and primary label.
  String get displayName {
    final n = name.trim();
    if (n.isNotEmpty) return n;
    return alias.trim();
  }

  /// Name with optional alias complement, e.g. `Jeronimo (Jer)`.
  String get displayLabel {
    final n = name.trim();
    final a = alias.trim();
    if (n.isEmpty) return a.isEmpty ? '' : a;
    if (a.isEmpty) return n;
    return '$n ($a)';
  }

  String get initial {
    final label = displayName;
    if (label.isEmpty) return '?';
    return String.fromCharCodes(label.runes.take(1)).toUpperCase();
  }

  factory AppUser.fromMap(String uid, Map<String, dynamic> data) {
    final legacyPhoto = data['photoURL'] as String?;
    final customFlag = data['customPhoto'] as bool? ?? false;
    final google = data['googlePhotoURL'] as String?;
    final custom = data['customPhotoURL'] as String?;

    // Migrate older docs that only had photoURL + customPhoto.
    final resolvedGoogle = (google != null && google.trim().isNotEmpty)
        ? google
        : (!customFlag ? legacyPhoto : null);
    final resolvedCustom = (custom != null && custom.trim().isNotEmpty)
        ? custom
        : (customFlag ? legacyPhoto : null);

    return AppUser(
      uid: uid,
      email: data['email'] as String? ?? '',
      name: data['name'] as String? ?? '',
      alias: data['alias'] as String? ?? '',
      googlePhotoURL: resolvedGoogle,
      customPhotoURL: resolvedCustom,
      isPlatformAdmin: data['isPlatformAdmin'] as bool? ?? false,
      createdAt: (data['createdAt'] as dynamic)?.toDate() as DateTime?,
    );
  }

  Map<String, dynamic> toMap() => {
        'email': email,
        'name': name,
        'alias': alias,
        'googlePhotoURL': googlePhotoURL,
        'customPhotoURL': customPhotoURL,
        'customPhoto': hasCustomPhoto,
        // Keep photoURL as the effective Circle avatar for older readers.
        'photoURL': avatarURL,
        'isPlatformAdmin': isPlatformAdmin,
        'createdAt': createdAt,
      };
}
