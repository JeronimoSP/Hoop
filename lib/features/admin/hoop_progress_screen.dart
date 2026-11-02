import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_chrome.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/repositories/assignment_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/challenge_repository.dart';
import '../../data/repositories/circle_repository.dart';
import '../../domain/models/assignment.dart';
import '../../domain/models/challenge.dart';
import '../../domain/models/circle.dart';
import '../challenges/challenges_providers.dart';

final _membersProvider =
    StreamProvider.autoDispose.family<List<Membership>, String>((ref, circleId) {
  return ref.watch(circleRepositoryProvider).watchMembers(circleId);
});

final _circleProgressLogsProvider =
    StreamProvider.autoDispose.family<List<ProgressLog>, String>((ref, circleId) {
  return ref.watch(assignmentRepositoryProvider).watchCircleProgress(circleId);
});

final _circleAssignmentsProvider =
    StreamProvider.autoDispose.family<List<Assignment>, String>((ref, circleId) {
  return ref.watch(assignmentRepositoryProvider).watchAssignments(circleId);
});

final _circleObjectivesProvider = StreamProvider.autoDispose
    .family<List<Objective>, String>((ref, circleId) {
  final repo = ref.watch(assignmentRepositoryProvider);
  return repo.watchAssignments(circleId).asyncExpand((assignments) {
    final ids = assignments.map((a) => a.id).toList();
    return repo.watchObjectivesForAssignments(ids);
  });
});

final _circleEnrollmentsProvider = StreamProvider.autoDispose
    .family<List<ChallengeEnrollment>, String>((ref, circleId) {
  return ref
      .watch(challengeRepositoryProvider)
      .watchEnrollmentsForCircle(circleId);
});

class HoopProgressScreen extends ConsumerWidget {
  const HoopProgressScreen({super.key, required this.circleId});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authStateProvider).asData?.value?.uid;
    final membership = uid == null
        ? null
        : ref
            .watch(circleMembershipProvider((circleId: circleId, userId: uid)))
            .asData
            ?.value;

    if (uid != null && membership != null && membership.isAdmin != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/circles/$circleId');
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final membersAsync = ref.watch(_membersProvider(circleId));
    final logsAsync = ref.watch(_circleProgressLogsProvider(circleId));
    final assignmentsAsync = ref.watch(_circleAssignmentsProvider(circleId));
    final objectivesAsync = ref.watch(_circleObjectivesProvider(circleId));
    final enrollmentsAsync = ref.watch(_circleEnrollmentsProvider(circleId));
    final challengesAsync = ref.watch(challengesProvider(circleId));

    return Scaffold(
      appBar: brandAppBar(
        title: Text(
          'Progress',
          style: brandDisplay(fontWeight: FontWeight.w600),
        ),
      ),
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (members) {
          if (members.isEmpty) {
            return const Center(child: Text('No members yet'));
          }
          final logs = logsAsync.asData?.value ?? const <ProgressLog>[];
          final assignments =
              assignmentsAsync.asData?.value ?? const <Assignment>[];
          final objectives =
              objectivesAsync.asData?.value ?? const <Objective>[];
          final enrollments =
              enrollmentsAsync.asData?.value ?? const <ChallengeEnrollment>[];
          final challenges =
              challengesAsync.asData?.value ?? const <Challenge>[];
          final challengeById = {
            for (final c in challenges) c.id: c,
          };
          final memberCoins = buildMemberCoinViews(
            assignments: assignments,
            objectives: objectives,
            logs: logs,
            userIds: members.map((m) => m.userId),
          );

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: members.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final m = members[index];
              final coins = memberCoins[m.userId] ?? const <CoinView>[];
              final totals = coinTotals(coins);
              final userEnrollments =
                  enrollments.where((e) => e.userId == m.userId).toList();
              return _MemberProgressTile(
                circleId: circleId,
                membership: m,
                coinCompleted: totals.completed,
                coinTotal: totals.total,
                coins: coins,
                enrollments: userEnrollments,
                challengeById: challengeById,
              );
            },
          );
        },
      ),
    );
  }
}

class _MemberProgressTile extends ConsumerWidget {
  const _MemberProgressTile({
    required this.circleId,
    required this.membership,
    required this.coinCompleted,
    required this.coinTotal,
    required this.coins,
    required this.enrollments,
    required this.challengeById,
  });

  final String circleId;
  final Membership membership;
  final int coinCompleted;
  final int coinTotal;
  final List<CoinView> coins;
  final List<ChallengeEnrollment> enrollments;
  final Map<String, Challenge> challengeById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appUserProvider(membership.userId)).asData?.value;
    final label = user?.displayLabel.trim().isNotEmpty == true
        ? user!.displayLabel
        : 'Member';
    final enrollLabel = enrollments.isEmpty
        ? 'No challenges'
        : '${enrollments.length} challenge${enrollments.length == 1 ? '' : 's'}';

    return ListTile(
      leading: UserAvatar(
        photoURL: user?.avatarURL,
        label: user?.displayName.isNotEmpty == true
            ? user!.displayName
            : label,
        size: UserAvatarSize.md,
      ),
      title: Text(label),
      subtitle: Text(
        coinTotal == 0
            ? 'No assignments · $enrollLabel'
            : '$coinCompleted/$coinTotal coins · $enrollLabel',
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showMemberDetail(
        context: context,
        ref: ref,
        label: label,
      ),
    );
  }

  Future<void> _showMemberDetail({
    required BuildContext context,
    required WidgetRef ref,
    required String label,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return _MemberDetailSheet(
              circleId: circleId,
              userId: membership.userId,
              label: label,
              coins: coins,
              enrollments: enrollments,
              challengeById: challengeById,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }
}

class _MemberDetailSheet extends ConsumerWidget {
  const _MemberDetailSheet({
    required this.circleId,
    required this.userId,
    required this.label,
    required this.coins,
    required this.enrollments,
    required this.challengeById,
    required this.scrollController,
  });

  final String circleId;
  final String userId;
  final String label;
  final List<CoinView> coins;
  final List<ChallengeEnrollment> enrollments;
  final Map<String, Challenge> challengeById;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(label, style: brandDisplay(fontSize: 20)),
        const SizedBox(height: 16),
        Text('Assignments', style: brandDisplay(fontSize: 16)),
        const SizedBox(height: 8),
        if (coins.isEmpty)
          const Text(
            'No assignments',
            style: TextStyle(color: AppColors.textSecondary),
          )
        else
          ...coins.map((coin) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${coin.assignment.title} · ${coin.completedCount}/${coin.totalCount}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  ...coin.objectives.map((o) {
                    final done = coin.isObjectiveCompleted(o.id);
                    return Row(
                      children: [
                        Icon(
                          done
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: done
                              ? AppColors.accent
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(o.label)),
                      ],
                    );
                  }),
                ],
              ),
            );
          }),
        const SizedBox(height: 16),
        Text('Challenges', style: brandDisplay(fontSize: 16)),
        const SizedBox(height: 8),
        if (enrollments.isEmpty)
          const Text(
            'Not enrolled in any challenges',
            style: TextStyle(color: AppColors.textSecondary),
          )
        else
          ...enrollments.map((e) {
            final challenge = challengeById[e.challengeId];
            final title = challenge?.title ?? 'Challenge';
            return _EnrollmentProgressRow(
              circleId: circleId,
              enrollment: e,
              title: title,
              durationDays: challenge?.durationDays ?? 0,
            );
          }),
      ],
    );
  }
}

class _EnrollmentProgressRow extends ConsumerWidget {
  const _EnrollmentProgressRow({
    required this.circleId,
    required this.enrollment,
    required this.title,
    required this.durationDays,
  });

  final String circleId;
  final ChallengeEnrollment enrollment;
  final String title;
  final int durationDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(
      _adminSessionsProvider(
        (circleId: circleId, enrollmentId: enrollment.id),
      ),
    );
    final sessions = sessionsAsync.asData?.value;
    final rollup = sessions == null
        ? null
        : sessionRollup(sessions);
    final status = enrollmentStatusToString(enrollment.status);
    final progressText = rollup == null
        ? '…'
        : '${rollup.completed}/${rollup.total == 0 ? durationDays : rollup.total} days';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text('$status · $progressText'),
      dense: true,
    );
  }
}

final _adminSessionsProvider = StreamProvider.autoDispose
    .family<List<ChallengeSession>, ({String circleId, String enrollmentId})>(
  (ref, args) {
    return ref.watch(challengeRepositoryProvider).watchSessionsForEnrollmentAdmin(
          circleId: args.circleId,
          enrollmentId: args.enrollmentId,
        );
  },
);
