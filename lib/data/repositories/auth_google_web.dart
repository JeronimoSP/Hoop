import 'package:firebase_auth/firebase_auth.dart';

/// Web must not load google_sign_in_web (requires OAuth ClientID meta tag).
Future<UserCredential> signInWithGoogleNative({
  required FirebaseAuth auth,
  required Future<void> Function(User user) upsertUser,
}) {
  throw UnsupportedError(
    'Native Google Sign-In is not used on web; use Firebase popup.',
  );
}

Future<void> signOutGoogleNative() async {}
