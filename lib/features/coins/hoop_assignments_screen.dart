import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_chrome.dart';
import '../../data/repositories/assignment_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/models/assignment.dart';
import '../challenges/challenges_providers.dart';
import 'coin_rail.dart';

final hoopAssignmentsProvider =
    StreamProvider.autoDispose.family<List<Assignment>, String>((ref, circleId) {
  return ref.watch(assignmentRepositoryProvider).watchPublishedAssignments(circleId);
});

final hoopAdminAssignmentsProvider =
    StreamProvider.autoDispose.family<List<Assignment>, String>((ref, circleId) {
  return ref.watch(assignmentRepositoryProvider).watchAssignmentsForAdmin(circleId);
});

class HoopAssignmentsScreen extends ConsumerWidget {
  const HoopAssignmentsScreen({super.key, required this.circleId});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authStateProvider).asData?.value?.uid;
    final membershipAsync = uid == null
        ? const AsyncValue.data(null)
        : ref.watch(
            circleMembershipProvider((circleId: circleId, userId: uid)),
          );
    final isAdmin = membershipAsync.asData?.value?.isAdmin == true;
    final assignmentsAsync = isAdmin
        ? ref.watch(hoopAdminAssignmentsProvider(circleId))
        : ref.watch(hoopAssignmentsProvider(circleId));
    final progressAsync = ref.watch(assignmentProgressProvider(circleId));

    return Scaffold(
      appBar: brandAppBar(
        title: Text(
          'Assignments',
          style: brandDisplay(fontWeight: FontWeight.w600),
        ),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'New assignment',
              icon: const Icon(Icons.add),
              onPressed: () =>
                  context.push('/circles/$circleId/assignments/new'),
            ),
        ],
      ),
      body: assignmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (assignments) {
          if (assignments.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'No assignments yet',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isAdmin
                          ? 'Open a system chat and compose content + questions.'
                          : 'Your facilitator has not published any assignments.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => context
                            .push('/circles/$circleId/assignments/new'),
                        child: const Text('Create assignment'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          final progressById = <String, AssignmentProgressView>{
            for (final v
                in progressAsync.asData?.value ??
                    const <AssignmentProgressView>[])
              v.assignment.id: v,
          };

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: assignments.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final assignment = assignments[index];
              final progress = progressById[assignment.id];
              final statusLabel = assignment.isDraft
                  ? 'Draft'
                  : progress == null
                      ? 'Published'
                      : '${progress.completedCount}/${progress.totalCount} required';
              return ListTile(
                leading: _StatusDot(
                  state: progress?.state ?? CoinState.pending,
                  draft: assignment.isDraft,
                ),
                title: Text(assignment.title),
                subtitle: Text(
                  statusLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                trailing: isAdmin && assignment.isPublished
                    ? IconButton(
                        tooltip: 'Roster',
                        icon: const Icon(Icons.people_outline),
                        onPressed: () => context.push(
                          '/circles/$circleId/assignments/${assignment.id}/roster',
                        ),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: () {
                  if (isAdmin && assignment.isDraft) {
                    context.push(
                      '/circles/$circleId/assignments/${assignment.id}/edit',
                    );
                  } else {
                    context.push(
                      '/circles/$circleId/assignments/${assignment.id}',
                    );
                  }
                },
                onLongPress: isAdmin
                    ? () => context.push(
                          '/circles/$circleId/assignments/${assignment.id}/edit',
                        )
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.state, this.draft = false});

  final CoinState state;
  final bool draft;

  @override
  Widget build(BuildContext context) {
    final color = draft
        ? Colors.grey
        : switch (state) {
            CoinState.pending => AppColors.coinPending,
            CoinState.inProgress => AppColors.coinInProgress,
            CoinState.completed => AppColors.coinCompleted,
          };
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: draft
          ? const Icon(Icons.edit, size: 16, color: Colors.white)
          : state == CoinState.completed
              ? const Icon(Icons.check, size: 18, color: AppColors.gold)
              : null,
    );
  }
}
