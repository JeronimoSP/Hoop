import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum UserAvatarSize {
  sm(24),
  md(40),
  lg(72);

  const UserAvatarSize(this.diameter);
  final double diameter;

  double get radius => diameter / 2;
  double get fontSize => switch (this) {
        UserAvatarSize.sm => 11,
        UserAvatarSize.md => 16,
        UserAvatarSize.lg => 28,
      };
}

/// Circular profile image with initials fallback.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.photoURL,
    required this.label,
    this.size = UserAvatarSize.md,
  });

  final String? photoURL;
  final String label;
  final UserAvatarSize size;

  @override
  Widget build(BuildContext context) {
    final url = photoURL?.trim();
    final hasPhoto = url != null && url.isNotEmpty;
    final initial = () {
      final t = label.trim();
      if (t.isEmpty) return '?';
      return String.fromCharCodes(t.runes.take(1)).toUpperCase();
    }();

    return CircleAvatar(
      radius: size.radius,
      backgroundColor: AppColors.accentSoft,
      foregroundColor: AppColors.accent,
      backgroundImage: hasPhoto ? NetworkImage(url) : null,
      child: hasPhoto
          ? null
          : Text(
              initial,
              style: TextStyle(
                fontSize: size.fontSize,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
    );
  }
}
