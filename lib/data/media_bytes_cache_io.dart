import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const int _kMaxCacheBytes = 150 * 1024 * 1024;

Directory? _root;
Future<Directory>? _rootFuture;

Future<Directory> _cacheDir() async {
  if (_root != null) return _root!;
  _rootFuture ??= () async {
    final base = await getApplicationCacheDirectory();
    final dir = Directory(p.join(base.path, 'media_bytes'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _root = dir;
    return dir;
  }();
  return _rootFuture!;
}

File _fileFor(Directory dir, String key) =>
    File(p.join(dir.path, '$key.bin'));

Future<Uint8List?> readBytes(String key) async {
  try {
    final dir = await _cacheDir();
    final file = _fileFor(dir, key);
    if (!await file.exists()) return null;
    // Touch mtime so LRU prune keeps recently used files.
    try {
      await file.setLastModified(DateTime.now());
    } catch (_) {}
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

Future<void> writeBytes(String key, Uint8List bytes) async {
  try {
    final dir = await _cacheDir();
    final file = _fileFor(dir, key);
    await file.writeAsBytes(bytes, flush: true);
    await _pruneIfNeeded(dir);
  } catch (_) {
    // Disk failures must not break media loading.
  }
}

Future<void> _pruneIfNeeded(Directory dir) async {
  try {
    final entries = <File>[];
    var total = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.bin')) continue;
      entries.add(entity);
      total += await entity.length();
    }
    if (total <= _kMaxCacheBytes) return;

    entries.sort((a, b) {
      final am = a.statSync().modified;
      final bm = b.statSync().modified;
      return am.compareTo(bm);
    });

    for (final file in entries) {
      if (total <= _kMaxCacheBytes) break;
      final len = await file.length();
      try {
        await file.delete();
        total -= len;
      } catch (_) {}
    }
  } catch (_) {}
}
