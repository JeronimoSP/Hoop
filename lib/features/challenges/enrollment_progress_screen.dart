import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_chrome.dart';
import '../../data/repositories/challenge_alarm_scheduler.dart';
import '../../data/repositories/challenge_repository.dart';
import '../../domain/models/challenge.dart';
import 'challenges_providers.dart';

class EnrollmentProgressScreen extends ConsumerStatefulWidget {
  const EnrollmentProgressScreen({
    super.key,
    required this.circleId,
    required this.challengeId,
    required this.enrollmentId,
  });

  final String circleId;
  final String challengeId;
  final String enrollmentId;

  @override
  ConsumerState<EnrollmentProgressScreen> createState() =>
      _EnrollmentProgressScreenState();
}

class _EnrollmentProgressScreenState
    extends ConsumerState<EnrollmentProgressScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final missed = await ref
          .read(challengeRepositoryProvider)
          .refreshMissedSessions(widget.enrollmentId);
      if (missed.isEmpty) return;
      final alarms = ref.read(challengeAlarmSchedulerProvider);
      for (final id in missed) {
        await alarms.cancelSession(id);
      }
    });
  }

  Future<void> _testPracticeAlarm(
    Challenge challenge,
    List<ChallengeSession> sessions,
  ) async {
    ChallengeSession? target = sessionForToday(sessions);
    if (target == null || !_canOpen(target)) {
      for (final s in sessions) {
        if (_canOpen(s)) {
          target = s;
          break;
        }
      }
    }
    target ??= sessions.isNotEmpty ? sessions.first : null;
    if (target == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No session available to test')),
      );
      return;
    }
    try {
      final when =
          await ref.read(challengeAlarmSchedulerProvider).scheduleTestInOneMinute(
                title: challenge.title,
                payload: ChallengeAlarmPayload(
                  circleId: widget.circleId,
                  challengeId: widget.challengeId,
                  sessionId: target.id,
                  autoplay: challenge.isMedia,
                ),
              );
      if (!mounted) return;
      final local = when.toLocal();
      final hh = local.hour.toString().padLeft(2, '0');
      final mm = local.minute.toString().padLeft(2, '0');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Test alarm set for $hh:$mm — lock the phone, then open the '
            'notification to play the challenge',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg.contains('web')
                ? 'Practice alarms need iOS/Android — not Chrome/web.'
                : 'Could not schedule alarm: $msg',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  String _stateLabel(SessionState state) {
    switch (state) {
      case SessionState.scheduled:
        return 'Scheduled';
      case SessionState.inProgress:
        return 'In progress';
      case SessionState.completed:
        return 'Completed';
      case SessionState.skipped:
        return 'Skipped';
      case SessionState.missed:
        return 'Missed';
    }
  }

  Color _stateColor(SessionState state) {
    switch (state) {
      case SessionState.completed:
        return AppColors.accent;
      case SessionState.skipped:
      case SessionState.missed:
        return AppColors.textSecondary;
      case SessionState.inProgress:
        return AppColors.gold;
      case SessionState.scheduled:
        return AppColors.coinPending;
    }
  }

  bool _canOpen(ChallengeSession session) {
    if (session.state == SessionState.completed ||
        session.state == SessionState.skipped ||
        session.state == SessionState.missed) {
      return false;
    }
    final now = DateTime.now();
    final day = DateTime(
      session.scheduledAt.year,
      session.scheduledAt.month,
      session.scheduledAt.day,
    );
    final today = DateTime(now.year, now.month, now.day);
    return !day.isAfter(today);
  }

  @override
  Widget build(BuildContext context) {
    final challengeAsync = ref.watch(
      challengeProvider((
        circleId: widget.circleId,
        challengeId: widget.challengeId,
      )),
    );
    final sessionsAsync =
        ref.watch(challengeSessionsProvider(widget.enrollmentId));

    return Scaffold(
      appBar: brandAppBar(
        title: Text(
          'Progress',
          style: brandDisplay(fontWeight: FontWeight.w600),
        ),
      ),
      body: challengeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (challenge) {
          if (challenge == null) {
            return const Center(child: Text('Challenge not found'));
          }
          return sessionsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (sessions) {
              final completed = sessions
                  .where((s) => s.state == SessionState.completed)
                  .length;
              final today = sessionForToday(sessions);

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(challenge.title, style: brandDisplay(fontSize: 22)),
                  const SizedBox(height: 6),
                  Text(
                    'Day $completed of ${challenge.durationDays} completed',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  if (today != null && _canOpen(today)) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context.push(
                        '/circles/${widget.circleId}/challenges/${widget.challengeId}/session/${today.id}',
                      ),
                      icon: const Icon(Icons.play_arrow),
                      label: Text('Open today · Day ${today.dayIndex}'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (kIsWeb)
                    const Text(
                      'Practice alarms need the iOS/Android app. '
                      'They cannot run from the Firebase web build in a phone browser.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () =>
                          _testPracticeAlarm(challenge, sessions),
                      icon: const Icon(Icons.alarm_add_outlined),
                      label: const Text('Test alarm in 1 minute'),
                    ),
                  const SizedBox(height: 20),
                  Text('Sessions', style: brandDisplay(fontSize: 18)),
                  const SizedBox(height: 8),
                  ...sessions.map((session) {
                    final openable = _canOpen(session);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: _stateColor(session.state).withValues(
                          alpha: 0.2,
                        ),
                        child: Text(
                          '${session.dayIndex}',
                          style: TextStyle(
                            color: _stateColor(session.state),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      title: Text('Day ${session.dayIndex}'),
                      subtitle: Text(
                        '${formatDateYmd(session.scheduledAt)} · ${_stateLabel(session.state)}',
                      ),
                      trailing: openable
                          ? const Icon(Icons.chevron_right)
                          : null,
                      onTap: openable
                          ? () => context.push(
                                '/circles/${widget.circleId}/challenges/${widget.challengeId}/session/${session.id}',
                              )
                          : null,
                    );
                  }),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
