import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../media_bytes_cache.dart';

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepository(FirebaseStorage.instance);
});

class PickedFileBytes {
  const PickedFileBytes({
    required this.bytes,
    required this.contentType,
    required this.fileName,
    this.durationMs,
  });

  final Uint8List bytes;
  final String contentType;
  final String fileName;
  final int? durationMs;
}

/// Back-compat alias used by image upload paths.
typedef PickedImage = PickedFileBytes;

const int kMaxImageBytes = 5 * 1024 * 1024;
const int kMaxPdfBytes = 20 * 1024 * 1024;
const int kMaxAudioBytes = 5 * 1024 * 1024;
const int kMaxVideoBytes = 25 * 1024 * 1024;
const int kMaxVoiceNoteMs = 2 * 60 * 1000;
const int kMaxVideoSeconds = 60;

class MediaRepository {
  MediaRepository(this._storage);

  final FirebaseStorage _storage;
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();

  /// Process-lifetime L1 cache (survives widget rebuilds; cleared on app kill).
  final Map<String, Uint8List> _memoryBytes = {};

  DateTime? _voiceStartedAt;

  /// Speech on web typically lands around -20…0 dBFS; -50 crushed the meter
  /// into a near-full bar that looked static.
  static const double _minDb = -25;

  final StreamController<double> _voiceLevelCtrl =
      StreamController<double>.broadcast();
  StreamSubscription<Amplitude>? _amplitudeSub;

  /// Normalized mic level 0–1 while a voice note is recording; otherwise 0.
  Stream<double> get voiceLevelStream => _voiceLevelCtrl.stream;

  double _normalizeDb(double currentDb) {
    return ((currentDb - _minDb) / (0 - _minDb)).clamp(0.0, 1.0);
  }

  void _startAmplitudeMonitor() {
    _stopAmplitudeMonitor(emitZero: false);
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((amp) {
      if (!_voiceLevelCtrl.isClosed) {
        _voiceLevelCtrl.add(_normalizeDb(amp.current));
      }
    });
  }

  void _stopAmplitudeMonitor({bool emitZero = true}) {
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    if (emitZero && !_voiceLevelCtrl.isClosed) {
      _voiceLevelCtrl.add(0);
    }
  }

  Future<PickedImage?> pickCompressedImage({
    ImageSource source = ImageSource.gallery,
  }) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file == null) return null;

    final raw = await file.readAsBytes();
    Uint8List bytes = raw;
    var contentType =
        lookupMimeType(file.name, headerBytes: bytes) ?? 'image/jpeg';

    if (!kIsWeb) {
      try {
        final compressed = await FlutterImageCompress.compressWithList(
          raw,
          minWidth: 1600,
          minHeight: 1600,
          quality: 82,
          format: CompressFormat.jpeg,
        );
        if (compressed.isNotEmpty) {
          bytes = Uint8List.fromList(compressed);
          contentType = 'image/jpeg';
        }
      } catch (_) {
        // Keep raw bytes if compress fails.
      }
    }

    if (!contentType.startsWith('image/')) {
      contentType = 'image/jpeg';
    }

    if (bytes.length > kMaxImageBytes) {
      throw StateError('Image exceeds the 5 MB limit');
    }

    final ext = contentType.contains('png')
        ? 'png'
        : contentType.contains('webp')
            ? 'webp'
            : 'jpg';
    final name = 'image_${DateTime.now().millisecondsSinceEpoch}.$ext';
    return PickedImage(
      bytes: bytes,
      contentType: contentType,
      fileName: name,
    );
  }

  Future<PickedImage?> pickCameraPhoto() {
    return pickCompressedImage(source: ImageSource.camera);
  }

  Future<PickedFileBytes?> pickCameraVideo() async {
    final file = await _picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(seconds: kMaxVideoSeconds),
    );
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Could not read the video');
    }
    if (bytes.length > kMaxVideoBytes) {
      throw StateError('Video exceeds the 25 MB limit');
    }

    var contentType =
        lookupMimeType(file.name, headerBytes: bytes) ?? 'video/mp4';
    if (!contentType.startsWith('video/')) {
      contentType = 'video/mp4';
    }
    final ext = contentType.contains('webm')
        ? 'webm'
        : contentType.contains('quicktime')
            ? 'mov'
            : 'mp4';
    final name = 'video_${DateTime.now().millisecondsSinceEpoch}.$ext';
    return PickedFileBytes(
      bytes: bytes,
      contentType: contentType,
      fileName: name,
      durationMs: null,
    );
  }

  Future<PickedFileBytes?> pickPdf() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (files.isEmpty) return null;

    final file = files.single;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Could not read the PDF bytes');
    }
    if (bytes.length > kMaxPdfBytes) {
      throw StateError('PDF exceeds the 20 MB limit');
    }

    final rawName = file.name.trim().isEmpty ? 'documento.pdf' : file.name;
    final safeName = rawName.toLowerCase().endsWith('.pdf')
        ? rawName
        : '$rawName.pdf';
    final contentType =
        lookupMimeType(safeName, headerBytes: bytes) ?? 'application/pdf';
    if (contentType != 'application/pdf' &&
        !safeName.toLowerCase().endsWith('.pdf')) {
      throw StateError('Only PDF files are allowed');
    }

    return PickedFileBytes(
      bytes: bytes,
      contentType: 'application/pdf',
      fileName: safeName.replaceAll(RegExp(r'[^\w.\-]+'), '_'),
    );
  }

  Future<PickedFileBytes?> pickAudioFile() async {
    final files = await FilePicker.pickFiles(type: FileType.audio);
    if (files.isEmpty) return null;

    final file = files.single;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Could not read the audio bytes');
    }
    if (bytes.length > kMaxAudioBytes) {
      throw StateError('Audio exceeds the 5 MB limit');
    }

    final rawName = file.name.trim().isEmpty
        ? 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a'
        : file.name;
    final contentType =
        lookupMimeType(rawName, headerBytes: bytes) ?? 'audio/mpeg';
    final safeType =
        contentType.startsWith('audio/') ? contentType : 'audio/mpeg';

    return PickedFileBytes(
      bytes: bytes,
      contentType: safeType,
      fileName: rawName.replaceAll(RegExp(r'[^\w.\-]+'), '_'),
    );
  }

  Future<bool> hasMicPermission() => _recorder.hasPermission();

  Future<void> startVoiceNote() async {
    final ok = await _recorder.hasPermission();
    if (!ok) {
      throw StateError('Microphone permission denied');
    }
    if (await _recorder.isRecording()) {
      _stopAmplitudeMonitor();
      await _recorder.cancel();
    }

    final encoder = kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc;
    String? path;
    if (!kIsWeb) {
      final dir = await getTemporaryDirectory();
      path = p.join(
        dir.path,
        'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
    }

    await _recorder.start(
      RecordConfig(
        encoder: encoder,
        numChannels: 1,
        bitRate: 64000,
      ),
      path: path ?? '',
    );
    _voiceStartedAt = DateTime.now();
    _startAmplitudeMonitor();
  }

  /// Stops recording. Returns null if cancelled or too short (<400ms).
  Future<PickedFileBytes?> stopVoiceNote({bool cancel = false}) async {
    final started = _voiceStartedAt;
    _voiceStartedAt = null;
    _stopAmplitudeMonitor();

    if (cancel) {
      await _recorder.cancel();
      return null;
    }

    final path = await _recorder.stop();
    if (path == null || path.isEmpty) return null;

    final durationMs = started == null
        ? 0
        : DateTime.now().difference(started).inMilliseconds;
    if (durationMs < 400) {
      return null;
    }
    if (durationMs > kMaxVoiceNoteMs + 1500) {
      throw StateError('Voice note exceeds the 2 minute limit');
    }

    late final Uint8List bytes;
    if (kIsWeb) {
      bytes = await XFile(path).readAsBytes();
    } else {
      bytes = await XFile(path).readAsBytes();
    }
    if (bytes.isEmpty) return null;
    if (bytes.length > kMaxAudioBytes) {
      throw StateError('Audio exceeds the 5 MB limit');
    }

    final contentType = kIsWeb ? 'audio/webm' : 'audio/mp4';
    final ext = kIsWeb ? 'webm' : 'm4a';
    return PickedFileBytes(
      bytes: bytes,
      contentType: contentType,
      fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.$ext',
      durationMs: durationMs.clamp(0, kMaxVoiceNoteMs),
    );
  }

  Future<bool> get isRecording async => _recorder.isRecording();

  Future<({String storagePath, String downloadUrl})> uploadCircleFile({
    required String circleId,
    required String userId,
    required String postId,
    required PickedFileBytes file,
  }) async {
    final storagePath =
        'circles/$circleId/uploads/$userId/$postId/${file.fileName}';
    final ref = _storage.ref(storagePath);
    await ref.putData(
      file.bytes,
      SettableMetadata(contentType: file.contentType),
    );
    final downloadUrl = await ref.getDownloadURL();
    return (storagePath: storagePath, downloadUrl: downloadUrl);
  }

  Future<({String storagePath, String downloadUrl})> uploadCircleImage({
    required String circleId,
    required String userId,
    required String postId,
    required PickedImage image,
  }) {
    return uploadCircleFile(
      circleId: circleId,
      userId: userId,
      postId: postId,
      file: image,
    );
  }

  Future<Uint8List> downloadBytes({
    String? storagePath,
    String? downloadUrl,
    int maxSize = 25 * 1024 * 1024,
  }) async {
    final cacheKey = MediaBytesCache.keyFor(
      storagePath: storagePath,
      downloadUrl: downloadUrl,
    );

    final mem = _memoryBytes[cacheKey];
    if (mem != null && mem.isNotEmpty) return mem;

    final disk = await MediaBytesCache.get(cacheKey);
    if (disk != null && disk.isNotEmpty) {
      _memoryBytes[cacheKey] = disk;
      return disk;
    }

    final Reference ref;
    if (storagePath != null && storagePath.isNotEmpty) {
      ref = _storage.ref(storagePath);
    } else if (downloadUrl != null && downloadUrl.isNotEmpty) {
      ref = _storage.refFromURL(downloadUrl);
    } else {
      throw ArgumentError('Need storagePath or downloadUrl');
    }
    final data = await ref.getData(maxSize);
    if (data == null || data.isEmpty) {
      throw StateError('Empty data from Storage');
    }
    _memoryBytes[cacheKey] = data;
    await MediaBytesCache.put(cacheKey, data);
    return data;
  }

  Future<Uint8List> downloadImageBytes({
    String? storagePath,
    String? downloadUrl,
  }) {
    return downloadBytes(
      storagePath: storagePath,
      downloadUrl: downloadUrl,
      maxSize: 15 * 1024 * 1024,
    );
  }

  void dispose() {
    _recorder.dispose();
  }
}
