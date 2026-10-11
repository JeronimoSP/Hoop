import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';

import '../../domain/models/app_user.dart';
import 'auth_google_io.dart'
    if (dart.library.html) 'auth_google_web.dart' as google_auth;

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

final currentAppUserProvider = StreamProvider<AppUser?>((ref) {
  final auth = ref.watch(authStateProvider);
  return auth.when(
    data: (user) {
      if (user == null) return Stream.value(null);
      return ref.watch(userRepositoryProvider).watchUser(user.uid);
    },
    loading: () => Stream.value(null),
    error: (_, _) => Stream.value(null),
  );
});

final appUserProvider =
    StreamProvider.autoDispose.family<AppUser?, String>((ref, uid) {
  if (uid.isEmpty) return Stream.value(null);
  return ref.watch(userRepositoryProvider).watchUser(uid);
});

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(
    db: ref.watch(firestoreProvider),
    storage: FirebaseStorage.instance,
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    auth: ref.watch(firebaseAuthProvider),
    users: ref.watch(userRepositoryProvider),
  );
});

class UserRepository {
  UserRepository({
    required FirebaseFirestore db,
    required FirebaseStorage storage,
  })  : _db = db,
        _storage = storage;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('users').doc(uid);

  String profilePhotoPath(String uid) => 'users/$uid/profile/avatar.jpg';

  Stream<AppUser?> watchUser(String uid) {
    return _doc(uid).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return AppUser.fromMap(snap.id, snap.data()!);
    });
  }

  Future<AppUser?> getByEmail(String email) async {
    final q = await _db
        .collection('users')
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    final doc = q.docs.first;
    return AppUser.fromMap(doc.id, doc.data());
  }

  /// Sync Google account fields into Firestore. Never clears Circle custom photo.
  /// Does not write anything to the user's Google account.
  Future<void> upsertFromFirebaseUser(User user) async {
    final ref = _doc(user.uid);
    final existing = await ref.get();
    final authPhoto = user.photoURL;

    if (existing.exists) {
      final data = existing.data() ?? {};
      final priorCustom = data['customPhotoURL'] as String?;
      final legacyCustom = (data['customPhoto'] as bool? ?? false)
          ? data['photoURL'] as String?
          : null;
      final customKept = (priorCustom != null && priorCustom.trim().isNotEmpty)
          ? priorCustom
          : legacyCustom;

      final merge = <String, dynamic>{
        'email': user.email ?? '',
        'name': user.displayName ?? data['name'] ?? '',
        // Always refresh Google photo independently of Circle custom avatar.
        'googlePhotoURL': authPhoto,
        'customPhoto':
            customKept != null && customKept.trim().isNotEmpty,
        // Effective avatar for any legacy readers.
        'photoURL': (customKept != null && customKept.trim().isNotEmpty)
            ? customKept
            : authPhoto,
      };
      await ref.set(merge, SetOptions(merge: true));
      return;
    }

    await ref.set({
      'email': user.email ?? '',
      'name': user.displayName ?? '',
      'alias': '',
      'googlePhotoURL': authPhoto,
      'customPhotoURL': null,
      'customPhoto': false,
      'photoURL': authPhoto,
      'isPlatformAdmin': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateAlias(String uid, String alias) async {
    await _doc(uid).set({
      'alias': alias.trim(),
    }, SetOptions(merge: true));
  }

  /// Upload Circle-only avatar. Does not modify the Google account photo.
  Future<String> uploadProfilePhoto({
    required String uid,
    required Uint8List bytes,
    String? contentType,
    String? fileName,
  }) async {
    if (bytes.isEmpty) {
      throw StateError('Photo is empty');
    }
    if (bytes.length > 5 * 1024 * 1024) {
      throw StateError('Photo must be 5 MB or less');
    }
    final type = contentType ??
        lookupMimeType(fileName ?? 'avatar.jpg', headerBytes: bytes) ??
        'image/jpeg';
    if (!type.startsWith('image/')) {
      throw StateError('File must be an image');
    }
    final path = profilePhotoPath(uid);
    final storageRef = _storage.ref(path);
    await storageRef.putData(bytes, SettableMetadata(contentType: type));
    final downloadUrl = await storageRef.getDownloadURL();
    await _doc(uid).set({
      'customPhotoURL': downloadUrl,
      'customPhoto': true,
      'photoURL': downloadUrl,
    }, SetOptions(merge: true));
    return downloadUrl;
  }

  Future<void> promoteToPlatformAdmin(String uid) async {
    await _doc(uid).set({
      'isPlatformAdmin': true,
    }, SetOptions(merge: true));
  }
}

class AuthRepository {
  AuthRepository({required this.auth, required this.users});

  final FirebaseAuth auth;
  final UserRepository users;

  Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      final result = await auth.signInWithPopup(provider);
      final user = result.user;
      if (user != null) {
        await users.upsertFromFirebaseUser(user);
      }
      return result;
    }

    return google_auth.signInWithGoogleNative(
      auth: auth,
      upsertUser: users.upsertFromFirebaseUser,
    );
  }

  Future<void> signOut() async {
    await auth.signOut();
    if (!kIsWeb) {
      await google_auth.signOutGoogleNative();
    }
  }
}
