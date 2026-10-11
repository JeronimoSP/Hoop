import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/repositories/messaging_repository.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ErrorWidget is built outside the app's Directionality; Text alone
  // causes cascading "No Directionality widget found" exceptions.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0x22B42318),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Something went wrong displaying this content.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
      ),
    );
  };
  FlutterError.onError = FlutterError.presentError;

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Web: allow multiple Circle tabs to share IndexedDB persistence.
  FirebaseFirestore.instance.settings = Settings(
    persistenceEnabled: true,
    webPersistentTabManager:
        kIsWeb ? const WebPersistentMultipleTabManager() : null,
  );
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
  runApp(const ProviderScope(child: CirculoApp()));
}
