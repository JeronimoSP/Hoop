import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/circle_repository.dart';
import '../../data/repositories/library_repository.dart';
import '../../domain/models/library_item.dart';

final myLibraryItemsProvider =
    StreamProvider.autoDispose<List<LibraryItem>>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(libraryRepositoryProvider).watchMyItems(uid);
});

final libraryItemProvider =
    StreamProvider.autoDispose.family<LibraryItem?, String>((ref, itemId) {
  return ref.watch(libraryRepositoryProvider).watchItem(itemId);
});

/// Hoops where the signed-in user is admin (for publish picker).
final adminCirclesProvider =
    StreamProvider.autoDispose<List<CircleListItem>>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(circleRepositoryProvider).watchMyCircles(uid).map(
        (items) => items.where((i) => i.membership.isAdmin).toList(),
      );
});
