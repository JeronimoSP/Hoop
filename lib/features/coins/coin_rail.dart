import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/models/assignment.dart';
import '../../domain/models/challenge.dart';
import '../../data/repositories/assignment_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../challenges/challenges_providers.dart';

final assignmentProgressProvider = StreamProvider.autoDispose
    .family<List<AssignmentProgressView>, String>((ref, circleId) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) return Stream.value(const []);

  final repo = ref.watch(assignmentRepositoryProvider);
  return repo.watchPublishedAssignments(circleId).asyncExpand((assignments) {
    return repo
        .watchMySubmissionsInCircle(circleId: circleId, userId: uid)
        .map(
          (subs) => buildProgressViews(
            assignments: assignments,
            submissions: subs,
          ),
        );
  });
});

/// Legacy objectives path (admin progress screen).
final coinViewsProvider =
    StreamProvider.autoDispose.family<List<CoinView>, String>((ref, circleId) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) return Stream.value(const []);

  final repo = ref.watch(assignmentRepositoryProvider);
  return repo.watchPublishedAssignments(circleId).asyncExpand((assignments) {
    final ids = assignments.map((a) => a.id).toList();
    return repo
        .watchObjectivesForAssignments(ids, circleId: circleId)
        .asyncExpand((objectives) {
      return repo.watchMyProgress(userId: uid, circleId: circleId).map(
            (logs) => buildCoinViews(
              assignments: assignments,
              objectives: objectives,
              logs: logs,
            ),
          );
    });
  });
});

class ChallengeOfDay {
  const ChallengeOfDay({
    required this.enrollment,
    required this.session,
    required this.challengeTitle,
  });

  final ChallengeEnrollment enrollment;
  final ChallengeSession session;
  final String challengeTitle;
}

final challengeOfDayProvider =
    Provider.autoDispose.family<ChallengeOfDay?, String>((ref, circleId) {
  final enrollments =
      ref.watch(myCircleEnrollmentsProvider(circleId)).asData?.value;
  if (enrollments == null || enrollments.isEmpty) return null;

  final sorted = [...enrollments]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  for (final enrollment in sorted) {
    final sessions =
        ref.watch(challengeSessionsProvider(enrollment.id)).asData?.value;
    if (sessions == null) continue;
    final today = sessionForToday(sessions);
    if (today == null) continue;
    final challenge = ref
        .watch(
          challengeProvider((
            circleId: circleId,
            challengeId: enrollment.challengeId,
          )),
        )
        .asData
        ?.value;
    final title = challenge?.title.trim().isNotEmpty == true
        ? challenge!.title
        : 'Challenge';
    return ChallengeOfDay(
      enrollment: enrollment,
      session: today,
      challengeTitle: title,
    );
  }
  return null;
});

class CoinRail extends ConsumerWidget {
  const CoinRail({super.key, required this.circleId});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressAsync = ref.watch(assignmentProgressProvider(circleId));
    final challengeDay = ref.watch(challengeOfDayProvider(circleId));

    return Container(
      width: double.infinity,
      color: AppColors.accentSoft,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: progressAsync.when(
        loading: () => const SizedBox(
          height: 40,
          child: Center(child: LinearProgressIndicator()),
        ),
        error: (e, _) => Text('$e'),
        data: (views) {
          if (views.isEmpty && challengeDay == null) {
            return const Text(
              'No assignments yet',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            );
          }

          final itemCount = views.length + (challengeDay != null ? 1 : 0);
          return SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: itemCount,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                if (challengeDay != null && index == 0) {
                  return _ChallengeDayChip(
                    challengeDay: challengeDay,
                    onTap: () {
                      context.push(
                        '/circles/$circleId/challenges/'
                        '${challengeDay.enrollment.challengeId}/session/'
                        '${challengeDay.session.id}',
                      );
                    },
                  );
                }
                final viewIndex = challengeDay != null ? index - 1 : index;
                final view = views[viewIndex];
                return _ProgressChip(
                  view: view,
                  onTap: () => context.push(
                    '/circles/$circleId/assignments/${view.assignment.id}',
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ChallengeDayChip extends StatelessWidget {
  const _ChallengeDayChip({
    required this.challengeDay,
    required this.onTap,
  });

  final ChallengeOfDay challengeDay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = challengeDay.session.state == SessionState.completed;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? AppColors.accent : AppColors.bgElevated,
              border: Border.all(color: AppColors.accent, width: 1.5),
            ),
            child: done
                ? const Icon(Icons.check, size: 18, color: AppColors.textOnDark)
                : Center(
                    child: Text(
                      '${challengeDay.session.dayIndex}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: 72,
            child: Text(
              challengeDay.challengeTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressChip extends StatelessWidget {
  const _ProgressChip({required this.view, required this.onTap});

  final AssignmentProgressView view;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (view.state) {
      CoinState.pending => AppColors.coinPending,
      CoinState.inProgress => AppColors.coinInProgress,
      CoinState.completed => AppColors.coinCompleted,
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: view.state == CoinState.completed
                ? const Icon(Icons.check, size: 18, color: AppColors.gold)
                : Center(
                    child: Text(
                      view.totalCount == 0
                          ? '—'
                          : '${view.completedCount}/${view.totalCount}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: 64,
            child: Text(
              view.assignment.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}
