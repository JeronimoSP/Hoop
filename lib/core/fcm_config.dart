/// Web Push (VAPID) key for FCM on Flutter web.
///
/// Generate in Firebase Console → Project settings → Cloud Messaging →
/// Web Push certificates → Generate key pair. Pass at build/run time:
///
/// ```bash
/// flutter run -d chrome --dart-define=FCM_VAPID_KEY=YOUR_KEY
/// flutter build web --dart-define=FCM_VAPID_KEY=YOUR_KEY
/// ```
class FcmConfig {
  static const String vapidKey = String.fromEnvironment(
    'FCM_VAPID_KEY',
    defaultValue: '',
  );
}
