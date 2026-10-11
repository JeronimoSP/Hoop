import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_chrome.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/challenge_alarm_scheduler.dart';
import '../../data/repositories/challenge_repository.dart';
import '../../domain/models/challenge.dart';
import 'challenges_providers.dart';

class ChallengeDetailEnrollScreen extends ConsumerStatefulWidget {
  const ChallengeDetailEnrollScreen({
    super.key,
    required this.circleId,
    required this.challengeId,
  });

  final String circleId;
  final String challengeId;

  @override
  ConsumerState<ChallengeDetailEnrollScreen> createState() =>
      _ChallengeDetailEnrollScreenState();
}

class _ChallengeDetailEnrollScreenState
    extends ConsumerState<ChallengeDetailEnrollScreen> {
  DateTime _startDate = DateTime.now();
  TimeOfDay _dailyTime = const TimeOfDay(hour: 7, minute: 0);
  bool _enrolling = false;
  String? _error;

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickDailyTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _dailyTime,
    );
    if (picked != null) setState(() => _dailyTime = picked);
  }

  Future<void> _enroll(Challenge challenge) async {
    final uid = ref.read(authStateProvider).asData?.value?.uid;
    if (uid == null) return;
    setState(() {
      _enrolling = true;
      _error = null;
    });
    final startDate = formatDateYmd(_startDate);
    final dailyTime =
        '${_dailyTime.hour.toString().padLeft(2, '0')}:${_dailyTime.minute.toString().padLeft(2, '0')}';
    final timezone = localTimezoneLabel();
    try {
      final enrollmentId =
          await ref.read(challengeRepositoryProvider).enroll(
                challenge: challenge,
                userId: uid,
                startDate: startDate,
                dailyTime: dailyTime,
                timezone: timezone,
              );
      final sessions = await ref
          .read(challengeRepositoryProvider)
          .fetchSessions(enrollmentId, userId: uid);
      try {
        await ref.read(challengeAlarmSchedulerProvider).scheduleEnrollment(
              challenge: challenge,
              sessions: sessions,
            );
      } catch (_) {
        // Alarms are best-effort; enrollment already succeeded.
      }
      if (!mounted) return;
      context.push(
        '/circles/${widget.circleId}/challenges/${widget.challengeId}/progress/$enrollmentId',
      );
    } catch (e) {
      setState(() {
        _error = e is StateError
            ? e.message
            : 'Could not enroll. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _enrolling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authStateProvider).asData?.value?.uid;
    final challengeAsync = ref.watch(
      challengeProvider((
        circleId: widget.circleId,
        challengeId: widget.challengeId,
      )),
    );
    final enrollmentAsync = uid == null
        ? const AsyncValue.data(null)
        : ref.watch(
            myChallengeEnrollmentProvider((
              challengeId: widget.challengeId,
              userId: uid,
            )),
          );

    return Scaffold(
      appBar: brandAppBar(
        title: Text(
          'Challenge',
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
          final enrollment = enrollmentAsync.asData?.value;
          final active = enrollment?.status == EnrollmentStatus.active;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(challenge.title, style: brandDisplay(fontSize: 24)),
              const SizedBox(height: 8),
              Text(
                '${challenge.isMedia ? 'Media practice' : 'Quest'} · ${challenge.durationDays} days',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (challenge.description != null &&
                  challenge.description!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(challenge.description!),
              ],
              if (challenge.isQuest &&
                  challenge.instructions != null &&
                  challenge.instructions!.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Instructions', style: brandDisplay(fontSize: 18)),
                const SizedBox(height: 8),
                Text(
                  challenge.instructions!,
                  style: const TextStyle(height: 1.4),
                ),
              ],
              if (challenge.isMedia) ...[
                const SizedBox(height: 20),
                const Text(
                  'Each day you will play the practice file. Duration and cues are part of the recording.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
              const SizedBox(height: 28),
              if (active && enrollment != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'You are enrolled',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Starts ${enrollment.startDate} · daily at ${enrollment.dailyTime}',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => context.push(
                          '/circles/${widget.circleId}/challenges/${widget.challengeId}/progress/${enrollment.id}',
                        ),
                        child: const Text('View progress'),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Text('Enroll', style: brandDisplay(fontSize: 18)),
                const SizedBox(height: 8),
                const Text(
                  'Choose when your daily practice starts and at what local time.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start date'),
                  subtitle: Text(formatDateYmd(_startDate)),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: _pickStartDate,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Daily time'),
                  subtitle: Text(
                    '${_dailyTime.hour.toString().padLeft(2, '0')}:${_dailyTime.minute.toString().padLeft(2, '0')}',
                  ),
                  trailing: const Icon(Icons.schedule_outlined),
                  onTap: _pickDailyTime,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _enrolling ? null : () => _enroll(challenge),
                  child: _enrolling
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Confirm enrollment'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
