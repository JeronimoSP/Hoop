import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/create_circle_screen.dart';
import '../features/admin/circle_info_screen.dart';
import '../features/admin/hoop_progress_screen.dart';
import '../features/auth/auth_screen.dart';
import '../features/challenges/challenge_detail_enroll_screen.dart';
import '../features/challenges/challenge_edit_screen.dart';
import '../features/challenges/challenge_session_screen.dart';
import '../features/challenges/challenges_list_screen.dart';
import '../features/challenges/enrollment_progress_screen.dart';
import '../features/coins/assignment_roster_screen.dart';
import '../features/coins/assignment_system_thread_screen.dart';
import '../features/coins/hoop_assignments_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_edit_screen.dart';
import '../features/library/library_list_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/thread/hoop_resources_screen.dart';
import '../features/thread/thread_screen.dart';
import '../data/repositories/auth_repository.dart';
import '../domain/models/library_item.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // Do NOT watch auth here — recreating GoRouter drops in-flight deep links
  // (e.g. practice alarm taps). Auth changes go through refreshListenable.
  final refresh = _AuthRefresh(ref);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
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
        path: '/library',
        builder: (context, state) => const LibraryListScreen(),
      ),
      GoRoute(
        path: '/library/new',
        builder: (context, state) {
          final kindParam = state.uri.queryParameters['kind'];
          final kind = kindParam == null
              ? LibraryItemKind.resource
              : libraryItemKindFromString(kindParam);
          return LibraryEditScreen(initialKind: kind);
        },
      ),
      GoRoute(
        path: '/library/:itemId',
        builder: (context, state) {
          final id = state.pathParameters['itemId']!;
          return LibraryEditScreen(itemId: id);
        },
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
        path: '/circles/:circleId/progress',
        builder: (context, state) {
          final id = state.pathParameters['circleId']!;
          return HoopProgressScreen(circleId: id);
        },
      ),
      GoRoute(
        path: '/circles/:circleId/assignments',
        builder: (context, state) {
          final id = state.pathParameters['circleId']!;
          return HoopAssignmentsScreen(circleId: id);
        },
      ),
      GoRoute(
        path: '/circles/:circleId/assignments/new',
        builder: (context, state) {
          final id = state.pathParameters['circleId']!;
          return AssignmentSystemThreadScreen(circleId: id);
        },
      ),
      GoRoute(
        path: '/circles/:circleId/assignments/:assignmentId',
        builder: (context, state) {
          final circleId = state.pathParameters['circleId']!;
          final assignmentId = state.pathParameters['assignmentId']!;
          return AssignmentSystemThreadScreen(
            circleId: circleId,
            assignmentId: assignmentId,
          );
        },
      ),
      GoRoute(
        path: '/circles/:circleId/assignments/:assignmentId/edit',
        builder: (context, state) {
          final circleId = state.pathParameters['circleId']!;
          final assignmentId = state.pathParameters['assignmentId']!;
          return AssignmentSystemThreadScreen(
            circleId: circleId,
            assignmentId: assignmentId,
            forceEdit: true,
          );
        },
      ),
      GoRoute(
        path: '/circles/:circleId/assignments/:assignmentId/roster',
        builder: (context, state) {
          final circleId = state.pathParameters['circleId']!;
          final assignmentId = state.pathParameters['assignmentId']!;
          return AssignmentRosterScreen(
            circleId: circleId,
            assignmentId: assignmentId,
          );
        },
      ),
      GoRoute(
        path:
            '/circles/:circleId/assignments/:assignmentId/participant/:userId',
        builder: (context, state) {
          final circleId = state.pathParameters['circleId']!;
          final assignmentId = state.pathParameters['assignmentId']!;
          final userId = state.pathParameters['userId']!;
          return AssignmentSystemThreadScreen(
            circleId: circleId,
            assignmentId: assignmentId,
            viewAsUserId: userId,
          );
        },
      ),
      GoRoute(
        path: '/circles/:circleId/resources',
        builder: (context, state) {
          final id = state.pathParameters['circleId']!;
          return HoopResourcesScreen(circleId: id);
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
