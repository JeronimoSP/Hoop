import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'media_bytes_cache_stub.dart'
    if (dart.library.io) 'media_bytes_cache_io.dart' as impl;

/// Durable on-disk cache for Firebase Storage byte payloads (images, covers, PDFs).
/// On web, disk ops are no-ops; [MediaRepository] still keeps an in-memory L1.
abstract final class MediaBytesCache {
  /// Stable key from Storage path (preferred) or download URL.
  static String keyFor({String? storagePath, String? downloadUrl}) {
    final raw = (storagePath != null && storagePath.isNotEmpty)
        ? storagePath
        : (downloadUrl ?? '');
    if (raw.isEmpty) {
      throw ArgumentError('Need storagePath or downloadUrl for cache key');
    }
    return sha256.convert(utf8.encode(raw)).toString();
  }

  static Future<Uint8List?> get(String key) => impl.readBytes(key);

  static Future<void> put(String key, Uint8List bytes) =>
      impl.writeBytes(key, bytes);
}
