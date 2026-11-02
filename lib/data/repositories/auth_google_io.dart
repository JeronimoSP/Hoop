import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

Future<UserCredential> signInWithGoogleNative({
  required FirebaseAuth auth,
  required Future<void> Function(User user) upsertUser,
}) async {
  // Web OAuth client (client_type 3) — required as serverClientId on Android
  // when google-services.json lacks default_web_client_id / oauth entries.
  const serverClientId =
      '302212210419-5gmt7smk1ddgvhrkicql4rkrpnbebmp0.apps.googleusercontent.com';
  await GoogleSignIn.instance.initialize(serverClientId: serverClientId);
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
