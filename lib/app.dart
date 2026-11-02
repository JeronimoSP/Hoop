import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/challenge_alarm_scheduler.dart';
import 'data/repositories/messaging_repository.dart';
import 'router/app_router.dart';

class CirculoApp extends ConsumerStatefulWidget {
  const CirculoApp({super.key});

  @override
  ConsumerState<CirculoApp> createState() => _CirculoAppState();
}

class _CirculoAppState extends ConsumerState<CirculoApp> {
  var _navAttached = false;
  String? _messagingUid;
  String? _profileSyncedUid;

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    if (!_navAttached) {
      _navAttached = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        attachMessagingNavigation(ref, router);
        // Handler reads appRouterProvider at tap-time so deep links survive.
        attachChallengeAlarmNavigation(ref, router);
      });
    }

    ref.listen<AsyncValue<User?>>(authStateProvider, (prev, next) {
      next.whenData((user) {
        _syncMessaging(user);
        _syncGoogleProfile(user);
      });
    });

    final user = ref.watch(authStateProvider).asData?.value;
    if (user?.uid != _messagingUid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncMessaging(user);
        _syncGoogleProfile(user);
      });
    }

    return MaterialApp.router(
      title: 'Hoop',
      theme: buildCirculoTheme(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }

  void _syncMessaging(User? user) {
    final messaging = ref.read(messagingRepositoryProvider);
    final uid = user?.uid;
    if (uid == _messagingUid) return;
    _messagingUid = uid;
    if (uid != null) {
      unawaited(() async {
        try {
          if (!kIsWeb) {
            final alarms = ref.read(challengeAlarmSchedulerProvider);
            // Init practice categories before FCM local-notification setup.
            await alarms.ensureInitialized();
            await messaging.start(uid);
            await alarms.rescheduleForUser(uid);
          } else {
            await messaging.start(uid);
          }
        } catch (e) {
          debugPrint('Messaging / challenge alarms sync failed: $e');
        }
      }());
    } else {
      messaging.stop();
    }
  }

  /// Refresh Google name/photo into Firestore (Circle custom photo stays).
  void _syncGoogleProfile(User? user) {
    if (user == null) {
      _profileSyncedUid = null;
      return;
    }
    final uid = user.uid;
    if (uid == _profileSyncedUid) return;
    _profileSyncedUid = uid;
    unawaited(() async {
      try {
        await ref.read(userRepositoryProvider).upsertFromFirebaseUser(user);
      } catch (e) {
        debugPrint('Google profile sync failed: $e');
      }
    }());
  }
}
