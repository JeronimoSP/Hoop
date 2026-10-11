import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';

class AppConfig {
  const AppConfig({
    required this.exists,
    required this.selfPromoteEnabled,
  });

  final bool exists;
  final bool selfPromoteEnabled;

  factory AppConfig.missing() =>
      const AppConfig(exists: false, selfPromoteEnabled: false);

  factory AppConfig.fromMap(Map<String, dynamic> data) {
    return AppConfig(
      exists: true,
      selfPromoteEnabled: data['selfPromoteEnabled'] as bool? ?? false,
    );
  }
}

final appConfigRepositoryProvider = Provider<AppConfigRepository>((ref) {
  return AppConfigRepository(ref.watch(firestoreProvider));
});

final appConfigProvider = StreamProvider<AppConfig>((ref) {
  return ref.watch(appConfigRepositoryProvider).watchSettings();
});

class AppConfigRepository {
  AppConfigRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> get _settings =>
      _db.collection('appConfig').doc('settings');

  Stream<AppConfig> watchSettings() {
    return _settings.snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) {
        return AppConfig.missing();
      }
      return AppConfig.fromMap(snap.data()!);
    });
  }

  /// Ensures bootstrap doc exists with self-promote open (first run).
  Future<void> ensureBootstrapSettings() async {
    final snap = await _settings.get();
    if (snap.exists) return;
    await _settings.set({'selfPromoteEnabled': true});
  }

  Future<void> setSelfPromoteEnabled(bool enabled) async {
    await _settings.set({'selfPromoteEnabled': enabled}, SetOptions(merge: true));
  }
}
