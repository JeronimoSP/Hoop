import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_chrome.dart';
import '../../data/repositories/post_repository.dart';
import '../../domain/models/post.dart';
import 'resource_open.dart';

final hoopResourcePostsProvider =
    StreamProvider.autoDispose.family<List<CirclePost>, String>((ref, circleId) {
  return ref.watch(postRepositoryProvider).watchPosts(circleId).map((posts) {
    final resources =
        posts.where((p) => p.type == PostType.resource).toList();
    resources.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return resources;
  });
});

class HoopResourcesScreen extends ConsumerWidget {
  const HoopResourcesScreen({super.key, required this.circleId});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resourcesAsync = ref.watch(hoopResourcePostsProvider(circleId));

    return Scaffold(
      appBar: brandAppBar(
        title: Text(
          'Resources',
          style: brandDisplay(fontWeight: FontWeight.w600),
        ),
      ),
      body: resourcesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (resources) {
          if (resources.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No resources yet',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: resources.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final r = resources[index];
              final exportPending = r.kind == 'googleDoc' &&
                  (r.meta['exportStatus']?.toString() ?? '') == 'pending';
              final exportFailed = r.kind == 'googleDoc' &&
                  (r.meta['exportStatus']?.toString() ?? '') == 'failed';
              return ListTile(
                leading: exportPending
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        resourceKindIcon(r),
                        color: exportFailed
                            ? AppColors.danger
                            : AppColors.accent,
                      ),
                title: Text(
                  resourceTitle(r),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  resourceKindLabel(r),
                  style: TextStyle(
                    fontSize: 13,
                    color: exportFailed
                        ? AppColors.danger
                        : AppColors.textSecondary,
                  ),
                ),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => openResourcePost(ref, r),
              );
            },
          );
        },
      ),
    );
  }
}
