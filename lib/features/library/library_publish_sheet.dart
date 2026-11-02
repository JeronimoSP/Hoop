import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/library_repository.dart';
import '../../domain/models/library_item.dart';
import 'library_providers.dart';

Future<void> showPublishLibraryItemSheet({
  required BuildContext context,
  required WidgetRef ref,
  required LibraryItem item,
}) async {
  final circleId = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return Consumer(
        builder: (context, ref, _) {
          final adminAsync = ref.watch(adminCirclesProvider);
          return SafeArea(
            child: adminAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('$e'),
              ),
              data: (hoops) {
                if (hoops.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'You are not an admin of any Hoop yet. '
                      'Create or join a Hoop as facilitator first.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        'Publish into Hoop',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    ...hoops.map(
                      (h) => ListTile(
                        title: Text(h.circle.name),
                        trailing: const Icon(Icons.publish_outlined),
                        onTap: () => Navigator.pop(ctx, h.circle.id),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );
    },
  );

  if (circleId == null || !context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Publish to Hoop?'),
      content: Text(
        '“${item.title}” will be added to the selected Hoop as a live '
        '${libraryItemKindLabel(item.kind).toLowerCase()}.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Publish'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final uid = ref.read(authStateProvider).asData?.value?.uid;
  if (uid == null) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(libraryRepositoryProvider).publishToCircle(
          item: item,
          circleId: circleId,
          authorId: uid,
        );
    messenger.showSnackBar(
      const SnackBar(content: Text('Published to Hoop')),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          e is StateError ? e.message : 'Could not publish. Please try again.',
        ),
      ),
    );
  }
}
