import 'dart:typed_data';

Future<void> saveOrShareFile({
  required Uint8List bytes,
  required String fileName,
  String mimeType = 'application/octet-stream',
}) {
  throw UnsupportedError('File download is not supported on this platform');
}
