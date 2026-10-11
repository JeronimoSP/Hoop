import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

Future<UserCredential> signInWithGoogleNative({
  required FirebaseAuth auth,
  required Future<void> Function(User user) upsertUser,
}) async {
  await GoogleSignIn.instance.initialize();
  final account = await GoogleSignIn.instance.authenticate();
  final idToken = account.authentication.idToken;
  if (idToken == null) {
    throw StateError('Google Sign-In no devolvió idToken');
  }
  final credential = GoogleAuthProvider.credential(idToken: idToken);
  final result = await auth.signInWithCredential(credential);
  final user = result.user;
  if (user != null) {
    await upsertUser(user);
  }
  return result;
}

Future<void> signOutGoogleNative() async {
  await GoogleSignIn.instance.initialize();
  await GoogleSignIn.instance.signOut();
}
