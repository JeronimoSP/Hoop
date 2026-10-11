import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_chrome.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/circle_repository.dart';
import '../../domain/models/circle.dart';
import '../../domain/models/post.dart';

final homeCirclesProvider =
    StreamProvider.autoDispose<List<CircleListItem>>((ref) {
  final user = ref.watch(authStateProvider).asData?.value;
  if (user == null) return Stream.value(const []);
  return ref.watch(circleRepositoryProvider).watchMyCircles(user.uid);
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final circlesAsync = ref.watch(homeCirclesProvider);
    final appUser = ref.watch(currentAppUserProvider).asData?.value;
    final canCreate = appUser?.isPlatformAdmin == true;
    final myUid = ref.watch(authStateProvider).asData?.value?.uid;

    return Scaffold(
      appBar: brandAppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'Circles',
          style: brandDisplay(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton(
              onPressed: () => context.push('/circles/new'),
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Search circles',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: circlesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (items) {
                final filtered = _query.isEmpty
                    ? items
                    : items
                        .where(
                          (i) =>
                              i.circle.name.toLowerCase().contains(_query),
                        )
                        .toList();

                if (filtered.isEmpty) {
                  return _EmptyHome(canCreate: canCreate);
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(
                    height: 1,
                    color: AppColors.hairline,
                    indent: 72,
                  ),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return _CircleRow(
                      item: item,
                      myUid: myUid,
                      onTap: () =>
                          context.push('/circles/${item.circle.id}'),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// WhatsApp-style row: name + time on top; "Sender: message" + unread pill below.
class _CircleRow extends ConsumerWidget {
  const _CircleRow({
    required this.item,
    required this.onTap,
    this.myUid,
  });

  final CircleListItem item;
  final String? myUid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circle = item.circle;
    final preview = circle.lastPost;
    final unread = item.membership.unreadCount;

    String? senderLabel;
    if (preview != null) {
      final author = preview.authorId.isEmpty
          ? null
          : ref.watch(appUserProvider(preview.authorId)).asData?.value;
      final isMe = myUid != null && preview.authorId == myUid;
      if (isMe) {
        senderLabel = 'You';
      } else {
        final name = author?.displayName.trim() ?? '';
        final alias = author?.alias.trim() ?? '';
        // Prefer short alias for list density; else first name / display name.
        if (alias.isNotEmpty) {
          senderLabel = alias;
        } else if (name.isNotEmpty) {
          senderLabel = name.split(RegExp(r'\s+')).first;
        } else {
          senderLabel = 'Member';
        }
      }
    }

    final timeLabel =
        preview == null ? null : _formatListTime(preview.createdAt);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: AppColors.accentSoft,
              foregroundColor: AppColors.accent,
              child: Text(
                circle.name.isNotEmpty
                    ? circle.name.characters.first.toUpperCase()
                    : '?',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          circle.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (timeLabel != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          timeLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: unread > 0
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: unread > 0
                                ? AppColors.unreadBadge
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: preview == null
                            ? const Text(
                                'No messages yet',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                              )
                            : _LastMessagePreview(
                                senderLabel: senderLabel!,
                                preview: preview,
                              ),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(width: 8),
                        _UnreadBadge(count: unread),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Icon key for structured previews; null means plain text message body.
  static String? _previewIconKey(LastPostPreview preview) {
    final kind = (preview.kind ?? '').toLowerCase();
    final type = preview.type;
    if (type == PostType.media.name ||
        kind == 'image' ||
        kind == 'video' ||
        kind == 'audio' ||
        kind == 'pdf') {
      switch (kind) {
        case 'video':
          return 'video';
        case 'audio':
          return 'audio';
        case 'pdf':
          return 'pdf';
        default:
          return 'image';
      }
    }
    if (type == PostType.resource.name || kind == 'resource') {
      return 'resource';
    }
    if (type == PostType.instruction.name ||
        kind == 'challenge' ||
        kind == 'instruction') {
      return 'challenge';
    }
    if (kind == 'assignment') {
      return 'assignment';
    }
    return null;
  }

  static String _formatListTime(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    if (day == today) {
      final h = local.hour.toString().padLeft(2, '0');
      final m = local.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == yesterday) return 'Yesterday';
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    if (local.year == now.year) return '$dd/$mm';
    return '$dd/$mm/${local.year}';
  }
}

class _LastMessagePreview extends StatelessWidget {
  const _LastMessagePreview({
    required this.senderLabel,
    required this.preview,
  });

  final String senderLabel;
  final LastPostPreview preview;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: AppColors.textSecondary,
      fontSize: 14,
    );
    final icon = _iconForPreview(preview);
    final body = preview.body.trim();
    // Plain chat text: keep "Sender: message".
    if (icon == null) {
      final text = body.isNotEmpty ? body : 'Message';
      return Text(
        '$senderLabel: $text',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    // Media / special: sender + icon only (no text label beside the icon).
    return Row(
      children: [
        Text('$senderLabel: ', style: style),
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const Spacer(),
      ],
    );
  }

  static IconData? _iconForPreview(LastPostPreview preview) {
    final key = _CircleRow._previewIconKey(preview);
    return switch (key) {
      'image' => Icons.image_outlined,
      'video' => Icons.videocam_outlined,
      'audio' => Icons.mic_none_outlined,
      'pdf' => Icons.picture_as_pdf_outlined,
      'resource' => Icons.folder_outlined,
      'challenge' => Icons.emoji_events_outlined,
      'assignment' => Icons.assignment_outlined,
      _ => null,
    };
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.unreadBadge,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.canCreate});

  final bool canCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              canCreate
                  ? 'Open your first Circle'
                  : 'You are not in a Circle yet',
              textAlign: TextAlign.center,
              style: brandDisplay(fontSize: 22),
            ),
            const SizedBox(height: 8),
            Text(
              canCreate
                  ? 'Gather your community and learn together.'
                  : 'Ask a facilitator to invite you into their circle.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (canCreate) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.push('/circles/new'),
                child: const Text('New Circle'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
