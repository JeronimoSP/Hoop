import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_chrome.dart';
import '../../domain/models/library_item.dart';
import 'library_providers.dart';
import 'library_publish_sheet.dart';

class LibraryListScreen extends ConsumerWidget {
  const LibraryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(myLibraryItemsProvider);

    return Scaffold(
      appBar: brandAppBar(
        title: Text(
          'Library',
          style: brandDisplay(fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateKindSheet(context),
        child: const Icon(Icons.add),
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Your content library',
                      style: brandDisplay(fontSize: 20),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Save resources, challenges, and assignment templates, '
                      'then publish them into Hoops you facilitate.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => _showCreateKindSheet(context),
                      child: const Text('Create first item'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                leading: Icon(
                  _kindIcon(item.kind),
                  color: AppColors.accent,
                ),
                title: Text(item.title),
                subtitle: Text(
                  libraryItemKindLabel(item.kind),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) =>
                      _onOverflow(context, ref, item, value),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'publish', child: Text('Publish')),
                  ],
                ),
                onTap: () => _openItem(context, item),
                onLongPress: () => _showItemActions(context, ref, item),
              );
            },
          );
        },
      ),
    );
  }

  IconData _kindIcon(LibraryItemKind kind) {
    switch (kind) {
      case LibraryItemKind.resource:
        return Icons.menu_book_outlined;
      case LibraryItemKind.challenge:
        return Icons.spa_outlined;
      case LibraryItemKind.assignment:
        return Icons.workspace_premium_outlined;
    }
  }

  void _openItem(BuildContext context, LibraryItem item) {
    final circleId = item.meta['circleId'] as String?;
    final assignmentId = item.meta['assignmentId'] as String?;
    final challengeId = item.meta['challengeId'] as String?;

    if (circleId != null &&
        circleId.isNotEmpty &&
        assignmentId != null &&
        assignmentId.isNotEmpty) {
      context.push('/circles/$circleId/assignments/$assignmentId');
      return;
    }
    if (circleId != null &&
        circleId.isNotEmpty &&
        challengeId != null &&
        challengeId.isNotEmpty) {
      context.push('/circles/$circleId/challenges/$challengeId');
      return;
    }
    context.push('/library/${item.id}');
  }

  Future<void> _onOverflow(
    BuildContext context,
    WidgetRef ref,
    LibraryItem item,
    String value,
  ) async {
    switch (value) {
      case 'edit':
        context.push('/library/${item.id}');
      case 'publish':
        await showPublishLibraryItemSheet(
          context: context,
          ref: ref,
          item: item,
        );
    }
  }

  Future<void> _showItemActions(
    BuildContext context,
    WidgetRef ref,
    LibraryItem item,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.publish_outlined),
                title: const Text('Publish to Hoop'),
                onTap: () => Navigator.pop(ctx, 'publish'),
              ),
            ],
          ),
        );
      },
    );
    if (action == null || !context.mounted) return;
    await _onOverflow(context, ref, item, action);
  }

  Future<void> _showCreateKindSheet(BuildContext context) async {
    final kind = await showModalBottomSheet<LibraryItemKind>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Resource'),
                subtitle: const Text('Link, Doc, PDF, audio, or video'),
                onTap: () => Navigator.pop(ctx, LibraryItemKind.resource),
              ),
              ListTile(
                leading: const Icon(Icons.spa_outlined),
                title: const Text('Challenge'),
                subtitle: const Text('Media practice or quest template'),
                onTap: () => Navigator.pop(ctx, LibraryItemKind.challenge),
              ),
              ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: const Text('Assignment'),
                subtitle: const Text('Reusable assignment template'),
                onTap: () => Navigator.pop(ctx, LibraryItemKind.assignment),
              ),
            ],
          ),
        );
      },
    );
    if (kind == null || !context.mounted) return;
    context.push('/library/new?kind=${libraryItemKindToString(kind)}');
  }
}
