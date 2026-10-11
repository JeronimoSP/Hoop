import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_chrome.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/models/challenge.dart';
import 'challenges_providers.dart';

class ChallengesListScreen extends ConsumerWidget {
  const ChallengesListScreen({super.key, required this.circleId});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authStateProvider).asData?.value?.uid;
    final challengesAsync = ref.watch(challengesProvider(circleId));
    final enrollmentsAsync = ref.watch(myCircleEnrollmentsProvider(circleId));
    final membershipAsync = uid == null
        ? const AsyncValue.data(null)
        : ref.watch(
            circleMembershipProvider((circleId: circleId, userId: uid)),
          );
    final isAdmin = membershipAsync.asData?.value?.isAdmin == true;

    final enrollmentByChallenge = <String, ChallengeEnrollment>{};
    for (final e in enrollmentsAsync.asData?.value ?? const <ChallengeEnrollment>[]) {
      enrollmentByChallenge[e.challengeId] = e;
    }

    return Scaffold(
      appBar: brandAppBar(
        title: Text(
          'Challenges',
          style: brandDisplay(fontWeight: FontWeight.w600),
        ),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'New challenge',
              icon: const Icon(Icons.add),
              onPressed: () =>
                  context.push('/circles/$circleId/challenges/new'),
            ),
        ],
      ),
      body: challengesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (challenges) {
          if (challenges.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'No challenges yet',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isAdmin
                          ? 'Create a media or quest challenge for this circle.'
                          : 'Your facilitator has not published any challenges.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () =>
                            context.push('/circles/$circleId/challenges/new'),
                        child: const Text('Create challenge'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: challenges.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final c = challenges[index];
              final enrollment = enrollmentByChallenge[c.id];
              return Material(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => context.push(
                    '/circles/$circleId/challenges/${c.id}',
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.accentSoft,
                          child: Icon(
                            c.isMedia
                                ? (c.mediaKind == ChallengeMediaKind.video
                                    ? Icons.videocam_outlined
                                    : Icons.headphones_outlined)
                                : Icons.edit_note_outlined,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${c.isMedia ? 'Media' : 'Quest'} · ${c.durationDays} days',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              if (enrollment != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Enrolled · starts ${enrollment.startDate} at ${enrollment.dailyTime}',
                                  style: const TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
