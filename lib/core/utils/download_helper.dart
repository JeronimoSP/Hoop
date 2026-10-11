import 'dart:typed_data';

import 'download_helper_stub.dart'
    if (dart.library.html) 'download_helper_web.dart'
    if (dart.library.io) 'download_helper_io.dart' as impl;

/// Saves or shares [bytes] as a downloadable file named [fileName].
Future<void> saveOrShareFile({
  required Uint8List bytes,
  required String fileName,
  String mimeType = 'application/octet-stream',
}) {
  return impl.saveOrShareFile(
    bytes: bytes,
    fileName: fileName,
    mimeType: mimeType,
  );
}
