import 'dart:typed_data';

import 'download_helper_stub.dart'
    if (dart.library.html) 'download_helper_web.dart';

Future<void> downloadBytes({
  required Uint8List bytes,
  required String filename,
  String mimeType = 'application/octet-stream',
}) {
  return downloadBytesImpl(bytes: bytes, filename: filename, mimeType: mimeType);
}
