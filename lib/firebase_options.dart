// File generated from Firebase config for project circulo-mvp.
// Prefer regenerating with: flutterfire configure

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        // Reuse iOS app config for local macOS desktop runs.
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDOmcjbdw5avragU8YHX-3KpLJvZekkWLk',
    appId: '1:302212210419:web:e92ad1c262d7ac6cb1e186',
    messagingSenderId: '302212210419',
    projectId: 'circulo-mvp',
    authDomain: 'circulo-mvp.firebaseapp.com',
    storageBucket: 'circulo-mvp.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBxICi9VYmAjDEh-ggYD804lj_jATlSBVc',
    appId: '1:302212210419:android:5010324d1152ceefb1e186',
    messagingSenderId: '302212210419',
    projectId: 'circulo-mvp',
    storageBucket: 'circulo-mvp.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBP3g3JKxjaQW14wYp1EHs1vpDfjfwPiyg',
    appId: '1:302212210419:ios:e264eb4564d63d2db1e186',
    messagingSenderId: '302212210419',
    projectId: 'circulo-mvp',
    storageBucket: 'circulo-mvp.firebasestorage.app',
    iosBundleId: 'com.circulo.circulo',
  );
}
