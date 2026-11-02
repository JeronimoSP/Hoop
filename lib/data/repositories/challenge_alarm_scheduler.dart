import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/models/challenge.dart';
import '../../router/app_router.dart';
import 'auth_repository.dart';
import 'challenge_repository.dart';

const String kPracticeActionId = 'play_practice';
const String kPracticeCategoryId = 'circulo_practice';
/// New id so Android recreates the channel with max + alarm audio attributes.
const String kPracticeChannelId = 'circulo_practice_alarm_v2';

/// Shared plugin so FCM foreground alerts and practice alarms share one init.
final FlutterLocalNotificationsPlugin kLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

bool _localNotificationsInitialized = false;
bool get localNotificationsInitialized => _localNotificationsInitialized;

void markLocalNotificationsInitialized() {
  _localNotificationsInitialized = true;
}

ChallengeAlarmPayload? _pendingAlarmPayload;

@pragma('vm:entry-point')
void challengeAlarmBackgroundResponse(NotificationResponse response) {
  final parsed = ChallengeAlarmPayload.tryParse(response.payload);
  if (parsed != null) {
    _pendingAlarmPayload = parsed;
  }
}

class ChallengeAlarmPayload {
  const ChallengeAlarmPayload({
    required this.circleId,
    required this.challengeId,
    required this.sessionId,
    this.autoplay = true,
  });

  final String circleId;
  final String challengeId;
  final String sessionId;
  final bool autoplay;

  String toJson() => jsonEncode({
        'circleId': circleId,
        'challengeId': challengeId,
        'sessionId': sessionId,
        'autoplay': autoplay,
      });

  static ChallengeAlarmPayload? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final circleId = map['circleId']?.toString() ?? '';
      final challengeId = map['challengeId']?.toString() ?? '';
      final sessionId = map['sessionId']?.toString() ?? '';
      if (circleId.isEmpty || challengeId.isEmpty || sessionId.isEmpty) {
        return null;
      }
      return ChallengeAlarmPayload(
        circleId: circleId,
        challengeId: challengeId,
        sessionId: sessionId,
        autoplay: map['autoplay'] != false,
      );
    } catch (_) {
      return null;
    }
  }

  String get route =>
      '/circles/$circleId/challenges/$challengeId/session/$sessionId'
      '${autoplay ? '?autoplay=1' : ''}';
}

final challengeAlarmSchedulerProvider = Provider<ChallengeAlarmScheduler>((ref) {
  // Stable instance so notification callbacks keep the open-handler.
  return ChallengeAlarmScheduler(
    db: ref.read(firestoreProvider),
    challenges: ref.read(challengeRepositoryProvider),
  );
});

class ChallengeAlarmScheduler {
  ChallengeAlarmScheduler({
    required FirebaseFirestore db,
    required ChallengeRepository challenges,
  })  : _db = db,
        _sessions = challenges;

  final FirebaseFirestore _db;
  final ChallengeRepository _sessions;

  void Function(ChallengeAlarmPayload payload)? _onOpen;
  void Function(String circleId)? _onOpenCircle;

  static const _practiceChannel = AndroidNotificationChannel(
    kPracticeChannelId,
    'Practice alarms',
    description: 'Alarm-style alerts that open your daily practice',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    audioAttributesUsage: AudioAttributesUsage.alarm,
  );

  void setOpenHandler(void Function(ChallengeAlarmPayload payload) handler) {
    _onOpen = handler;
    final pending = _pendingAlarmPayload;
    if (pending != null) {
      _pendingAlarmPayload = null;
      handler(pending);
    }
  }

  /// Secondary handler for plain FCM post payloads (circle id string).
  void setOpenCircleHandler(void Function(String circleId) handler) {
    _onOpenCircle = handler;
  }

  Future<void> ensureInitialized() async {
    if (kIsWeb) return;
    if (_localNotificationsInitialized) return;

    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.local);
    } catch (_) {}

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosInit = DarwinInitializationSettings(
      notificationCategories: [
        DarwinNotificationCategory(
          kPracticeCategoryId,
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.plain(
              kPracticeActionId,
              'Start practice',
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.foreground,
              },
            ),
          ],
        ),
      ],
    );

    await kLocalNotificationsPlugin.initialize(
      InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          challengeAlarmBackgroundResponse,
    );

    final android = kLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_practiceChannel);
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    await android?.requestFullScreenIntentPermission();

    _localNotificationsInitialized = true;

    final launch = await kLocalNotificationsPlugin
        .getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final parsed =
          ChallengeAlarmPayload.tryParse(launch!.notificationResponse?.payload);
      if (parsed != null) {
        _pendingAlarmPayload = parsed;
      }
    }
  }

  void _onNotificationResponse(NotificationResponse response) {
    final parsed = ChallengeAlarmPayload.tryParse(response.payload);
    if (parsed != null) {
      _onOpen?.call(parsed);
      return;
    }
    final raw = response.payload;
    if (raw != null && raw.isNotEmpty && !raw.trimLeft().startsWith('{')) {
      _onOpenCircle?.call(raw);
    }
  }

  int notificationIdForSession(String sessionId) =>
      sessionId.hashCode & 0x7fffffff;

  NotificationDetails _details({required bool isTest}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _practiceChannel.id,
        _practiceChannel.name,
        channelDescription: _practiceChannel.description,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        visibility: NotificationVisibility.public,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        ongoing: true,
        autoCancel: false,
        actions: <AndroidNotificationAction>[
          const AndroidNotificationAction(
            kPracticeActionId,
            'Start practice',
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        categoryIdentifier: kPracticeCategoryId,
        presentAlert: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
  }

  Future<void> scheduleEnrollment({
    required Challenge challenge,
    required List<ChallengeSession> sessions,
  }) async {
    if (kIsWeb) return;
    await ensureInitialized();
    final pre = challenge.preAlarmMinutes.clamp(0, 180);
    final now = DateTime.now();

    for (final session in sessions) {
      if (session.state != SessionState.scheduled) {
        await cancelSession(session.id);
        continue;
      }
      final fireAt =
          session.scheduledAt.subtract(Duration(minutes: pre));
      if (!fireAt.isAfter(now)) {
        await cancelSession(session.id);
        continue;
      }
      final payload = ChallengeAlarmPayload(
        circleId: session.circleId.isNotEmpty
            ? session.circleId
            : challenge.circleId,
        challengeId: challenge.id,
        sessionId: session.id,
        autoplay: challenge.isMedia,
      );
      final when = tz.TZDateTime.from(fireAt, tz.local);
      await kLocalNotificationsPlugin.zonedSchedule(
        notificationIdForSession(session.id),
        challenge.title,
        pre == 0
            ? 'Practice starts now'
            : 'Practice starts in $pre minutes',
        when,
        _details(isTest: false),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload.toJson(),
      );
    }
  }

  Future<void> cancelSession(String sessionId) async {
    if (kIsWeb) return;
    await ensureInitialized();
    await kLocalNotificationsPlugin
        .cancel(notificationIdForSession(sessionId));
  }

  Future<void> cancelEnrollment(Iterable<String> sessionIds) async {
    for (final id in sessionIds) {
      await cancelSession(id);
    }
  }

  Future<void> showTestNotification({
    required String title,
    required ChallengeAlarmPayload payload,
    int preAlarmMinutes = 10,
  }) async {
    if (kIsWeb) return;
    await ensureInitialized();
    await kLocalNotificationsPlugin.show(
      notificationIdForSession('test_${payload.sessionId}'),
      title,
      'TEMP test · Practice starts in $preAlarmMinutes minutes',
      _details(isTest: true),
      payload: payload.toJson(),
    );
  }

  /// Schedules a practice alarm ~1 minute from now (for device testing).
  /// Tapping / opening it navigates to the session with [payload] (autoplay).
  Future<DateTime> scheduleTestInOneMinute({
    required String title,
    required ChallengeAlarmPayload payload,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Practice alarms are not supported on web');
    }
    await ensureInitialized();

    final android = kLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final notifOk = await android?.areNotificationsEnabled();
    var exactAllowed = await android?.canScheduleExactNotifications();
    if (notifOk == false) {
      await android?.requestNotificationsPermission();
    }
    if (exactAllowed == false) {
      await android?.requestExactAlarmsPermission();
      exactAllowed = await android?.canScheduleExactNotifications();
    }

    final id = notificationIdForSession('test_${payload.sessionId}');
    await kLocalNotificationsPlugin.cancel(id);

    final when = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 1));
    // alarmClock surfaces like a clock alarm and is more reliable when idle.
    final mode = exactAllowed == false
        ? AndroidScheduleMode.inexactAllowWhileIdle
        : AndroidScheduleMode.alarmClock;
    await kLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      'Test alarm · Practice starts now',
      when,
      _details(isTest: true),
      androidScheduleMode: mode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload.toJson(),
    );
    return when;
  }

  /// Reschedule alarms for every active enrollment of [userId].
  Future<void> rescheduleForUser(String userId) async {
    if (kIsWeb) return;
    await ensureInitialized();
    final enrollSnap = await _db
        .collection('challengeEnrollments')
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'active')
        .get();

    for (final doc in enrollSnap.docs) {
      final enrollment = ChallengeEnrollment.fromMap(doc.id, doc.data());
      final challengeSnap = await _db
          .collection('circles')
          .doc(enrollment.circleId)
          .collection('challenges')
          .doc(enrollment.challengeId)
          .get();
      if (!challengeSnap.exists || challengeSnap.data() == null) continue;
      final challenge = Challenge.fromMap(challengeSnap.id, {
        ...challengeSnap.data()!,
        'circleId': enrollment.circleId,
      });
      final sessions = await _sessions.fetchSessions(
        enrollment.id,
        userId: enrollment.userId,
      );
      await scheduleEnrollment(challenge: challenge, sessions: sessions);
    }
  }
}

/// Wires challenge alarm taps into [GoRouter].
void attachChallengeAlarmNavigation(WidgetRef ref, GoRouter router) {
  final scheduler = ref.read(challengeAlarmSchedulerProvider);
  scheduler.setOpenHandler((payload) {
    // Read current router at tap-time (avoid stale instance from first frame).
    final current = ref.read(appRouterProvider);
    // Cancel sticky alarm notification once user opens it.
    unawaited(
      kLocalNotificationsPlugin.cancel(
        scheduler.notificationIdForSession('test_${payload.sessionId}'),
      ),
    );
    unawaited(
      kLocalNotificationsPlugin
          .cancel(scheduler.notificationIdForSession(payload.sessionId)),
    );
    current.go(payload.route);
  });
}
