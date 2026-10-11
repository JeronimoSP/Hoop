import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/create_circle_screen.dart';
import '../features/admin/circle_info_screen.dart';
import '../features/auth/auth_screen.dart';
import '../features/challenges/challenge_detail_enroll_screen.dart';
import '../features/challenges/challenge_edit_screen.dart';
import '../features/challenges/challenge_session_screen.dart';
import '../features/challenges/challenges_list_screen.dart';
import '../features/challenges/enrollment_progress_screen.dart';
import '../features/home/home_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/thread/thread_screen.dart';
import '../data/repositories/auth_repository.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthRefresh(ref),
    redirect: (context, state) {
      final loggingIn = state.matchedLocation == '/auth';
      final user = auth.asData?.value;
      final loading = auth.isLoading;

      if (loading) return null;
      if (user == null) return loggingIn ? null : '/auth';
      if (loggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/circles/new',
        builder: (context, state) => const CreateCircleScreen(),
      ),
      GoRoute(
        path: '/circles/:circleId',
        builder: (context, state) {
          final id = state.pathParameters['circleId']!;
          return ThreadScreen(circleId: id);
        },
      ),
      GoRoute(
        path: '/circles/:circleId/info',
        builder: (context, state) {
          final id = state.pathParameters['circleId']!;
          return CircleInfoScreen(circleId: id);
        },
      ),
      GoRoute(
        path: '/circles/:circleId/challenges',
        builder: (context, state) {
          final id = state.pathParameters['circleId']!;
          return ChallengesListScreen(circleId: id);
        },
      ),
      GoRoute(
        path: '/circles/:circleId/challenges/new',
        builder: (context, state) {
          final id = state.pathParameters['circleId']!;
          return ChallengeEditScreen(circleId: id);
        },
      ),
      GoRoute(
        path: '/circles/:circleId/challenges/:challengeId',
        builder: (context, state) {
          final circleId = state.pathParameters['circleId']!;
          final challengeId = state.pathParameters['challengeId']!;
          return ChallengeDetailEnrollScreen(
            circleId: circleId,
            challengeId: challengeId,
          );
        },
      ),
      GoRoute(
        path:
            '/circles/:circleId/challenges/:challengeId/progress/:enrollmentId',
        builder: (context, state) {
          final circleId = state.pathParameters['circleId']!;
          final challengeId = state.pathParameters['challengeId']!;
          final enrollmentId = state.pathParameters['enrollmentId']!;
          return EnrollmentProgressScreen(
            circleId: circleId,
            challengeId: challengeId,
            enrollmentId: enrollmentId,
          );
        },
      ),
      GoRoute(
        path:
            '/circles/:circleId/challenges/:challengeId/session/:sessionId',
        builder: (context, state) {
          final circleId = state.pathParameters['circleId']!;
          final challengeId = state.pathParameters['challengeId']!;
          final sessionId = state.pathParameters['sessionId']!;
          final autoplay = state.uri.queryParameters['autoplay'] == '1';
          return ChallengeSessionScreen(
            circleId: circleId,
            challengeId: challengeId,
            sessionId: sessionId,
            autoplay: autoplay,
          );
        },
      ),
    ],
  );
});

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(this._ref) {
    _ref.listen(authStateProvider, (_, _) => notifyListeners());
  }

  final Ref _ref;
}
