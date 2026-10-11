import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/challenge_repository.dart';
import '../../data/repositories/circle_repository.dart';
import '../../domain/models/challenge.dart';
import '../../domain/models/circle.dart';

final challengesProvider =
    StreamProvider.autoDispose.family<List<Challenge>, String>((ref, circleId) {
  return ref.watch(challengeRepositoryProvider).watchChallenges(circleId);
});

final challengeProvider = StreamProvider.autoDispose
    .family<Challenge?, ({String circleId, String challengeId})>((ref, key) {
  return ref
      .watch(challengeRepositoryProvider)
      .watchChallenge(key.circleId, key.challengeId);
});

final myChallengeEnrollmentProvider = StreamProvider.autoDispose
    .family<ChallengeEnrollment?, ({String challengeId, String userId})>(
        (ref, key) {
  return ref.watch(challengeRepositoryProvider).watchMyEnrollment(
        challengeId: key.challengeId,
        userId: key.userId,
      );
});

final myCircleEnrollmentsProvider = StreamProvider.autoDispose
    .family<List<ChallengeEnrollment>, String>((ref, circleId) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(challengeRepositoryProvider).watchMyEnrollmentsInCircle(
        circleId: circleId,
        userId: uid,
      );
});

final challengeSessionsProvider = StreamProvider.autoDispose
    .family<List<ChallengeSession>, String>((ref, enrollmentId) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(challengeRepositoryProvider).watchSessions(
        enrollmentId,
        userId: uid,
      );
});

final challengeSessionProvider =
    StreamProvider.autoDispose.family<ChallengeSession?, String>((ref, sessionId) {
  return ref.watch(challengeRepositoryProvider).watchSession(sessionId);
});

final circleMembershipProvider = StreamProvider.autoDispose
    .family<Membership?, ({String circleId, String userId})>((ref, key) {
  return ref.watch(circleRepositoryProvider).watchMembership(
        circleId: key.circleId,
        userId: key.userId,
      );
});

ChallengeSession? sessionForToday(List<ChallengeSession> sessions) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  for (final s in sessions) {
    final d = DateTime(
      s.scheduledAt.year,
      s.scheduledAt.month,
      s.scheduledAt.day,
    );
    if (d == today) return s;
  }
  return null;
}

String localTimezoneLabel() {
  final name = DateTime.now().timeZoneName;
  if (name.isNotEmpty) return name;
  final offset = DateTime.now().timeZoneOffset;
  final hours = offset.inHours;
  final mins = offset.inMinutes.remainder(60).abs();
  final sign = hours >= 0 ? '+' : '-';
  return 'UTC$sign${hours.abs().toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
}
