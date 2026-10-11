import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository.dart';
import '../theme/app_colors.dart';
import 'user_avatar.dart';

/// Avatar + name (with optional alias) resolved from Firestore `users/{uid}`.
class UserIdentityChip extends ConsumerWidget {
  const UserIdentityChip({
    super.key,
    required this.userId,
    this.myUid,
    this.size = UserAvatarSize.sm,
    this.dense = true,
  });

  final String userId;
  final String? myUid;
  final UserAvatarSize size;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appUserProvider(userId)).asData?.value;
    final isMe = myUid != null && userId == myUid;
    final label = user?.displayLabel.trim() ?? '';
    final isAgent = user?.isAgent == true;
    final text = isAgent
        ? (label.isNotEmpty ? '$label · Agent' : 'Agent')
        : isMe
            ? (label.isNotEmpty ? '$label · You' : 'You')
            : (label.isNotEmpty ? label : 'Member');
    final avatarLabel =
        user?.displayName.isNotEmpty == true ? user!.displayName : text;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        UserAvatar(
          photoURL: user?.avatarURL,
          label: avatarLabel,
          size: size,
        ),
        SizedBox(width: dense ? 6 : 10),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: dense ? 12 : 15,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
        ),
      ],
    );
  }
}
