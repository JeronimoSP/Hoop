import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/fcm_config.dart';
import '../../firebase_options.dart';
import 'auth_repository.dart';
import 'challenge_alarm_scheduler.dart';

/// Top-level handler for background FCM (mobile). Must be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

final messagingRepositoryProvider = Provider<MessagingRepository>((ref) {
  return MessagingRepository(
    messaging: FirebaseMessaging.instance,
    auth: ref.watch(firebaseAuthProvider),
    db: ref.watch(firestoreProvider),
  );
});

class MessagingRepository {
  MessagingRepository({
    required FirebaseMessaging messaging,
    required FirebaseAuth auth,
    required FirebaseFirestore db,
  })  : _messaging = messaging,
        _auth = auth,
        _db = db;

  final FirebaseMessaging _messaging;
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  FlutterLocalNotificationsPlugin get _local => kLocalNotificationsPlugin;

  String? _uid;
  String? _currentToken;
  bool _started = false;
  bool _handlersWired = false;
  void Function(String circleId)? _onOpenCircle;

  static const _androidChannel = AndroidNotificationChannel(
    'circulo_posts',
    'New messages',
    description: 'Alerts when there are new posts in your circles',
    importance: Importance.high,
  );

  void setOpenCircleHandler(void Function(String circleId) handler) {
    _onOpenCircle = handler;
  }

  Future<void> start(String uid) async {
    if (_started && _uid == uid) return;
    if (_started && _uid != uid) {
      await stop();
    }
    _uid = uid;
    _started = true;

    await _ensureLocalNotifications();
    await _wireHandlers();

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('FCM permission denied');
      return;
    }

    if (!kIsWeb) {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    await _registerToken();
    _messaging.onTokenRefresh.listen((token) async {
      if (_uid == null) return;
      await _upsertToken(token);
    });
  }

  Future<void> stop() async {
    final uid = _uid;
    final token = _currentToken;
    _started = false;
    _uid = null;
    _currentToken = null;
    if (uid != null && token != null) {
      try {
        await _tokenDoc(uid, token).delete();
      } catch (e) {
        debugPrint('FCM token delete on logout: $e');
      }
    }
    try {
      await _messaging.deleteToken();
    } catch (_) {}
  }

  Future<void> _ensureLocalNotifications() async {
    if (kIsWeb) return;

    // Practice alarms own full plugin init (categories + routing). If that
    // already ran, only ensure the posts channel exists.
    if (!localNotificationsInitialized) {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _local.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            final alarm = ChallengeAlarmPayload.tryParse(payload);
            if (alarm != null) return;
            if (!payload.trimLeft().startsWith('{')) {
              _onOpenCircle?.call(payload);
            }
          }
        },
      );
      markLocalNotificationsInitialized();
    }

    final androidPlugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_androidChannel);
  }

  Future<void> _wireHandlers() async {
    if (_handlersWired) return;
    _handlersWired = true;

    FirebaseMessaging.onMessage.listen((message) async {
      await _showForeground(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _openFromMessage(message);
    });

    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      _openFromMessage(initial);
    }
  }

  Future<void> _registerToken() async {
    try {
      final String? token;
      if (kIsWeb) {
        if (FcmConfig.vapidKey.isEmpty) {
          debugPrint(
            'FCM web: set --dart-define=FCM_VAPID_KEY=... to register tokens',
          );
          return;
        }
        token = await _messaging.getToken(vapidKey: FcmConfig.vapidKey);
      } else {
        token = await _messaging.getToken();
      }
      if (token == null || token.isEmpty) {
        debugPrint('FCM getToken returned null');
        return;
      }
      await _upsertToken(token);
    } catch (e) {
      debugPrint('FCM registerToken failed: $e');
    }
  }

  Future<void> _upsertToken(String token) async {
    final uid = _uid ?? _auth.currentUser?.uid;
    if (uid == null) return;
    _currentToken = token;
    await _tokenDoc(uid, token).set({
      'token': token,
      'platform': _platformName(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  DocumentReference<Map<String, dynamic>> _tokenDoc(String uid, String token) {
    final id = sha256.convert(utf8.encode(token)).toString();
    return _db.collection('users').doc(uid).collection('fcmTokens').doc(id);
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'other';
    }
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final title =
        message.notification?.title ?? message.data['circleId'] ?? 'Hoop';
    final body = message.notification?.body ?? 'New message';
    final circleId = message.data['circleId'] as String? ?? '';

    if (kIsWeb) {
      return;
    }

    await _local.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: circleId,
    );
  }

  void _openFromMessage(RemoteMessage message) {
    final circleId = message.data['circleId'] as String?;
    if (circleId == null || circleId.isEmpty) return;
    _onOpenCircle?.call(circleId);
  }
}

/// Wires [MessagingRepository] open-circle callbacks into [GoRouter].
void attachMessagingNavigation(WidgetRef ref, GoRouter router) {
  final repo = ref.read(messagingRepositoryProvider);
  void openCircle(String circleId) {
    router.go('/circles/$circleId');
  }

  repo.setOpenCircleHandler(openCircle);
  // Practice scheduler may own notification callbacks — keep circle deep links.
  ref.read(challengeAlarmSchedulerProvider).setOpenCircleHandler(openCircle);
}
