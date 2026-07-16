import 'dart:typed_data';

Future<void> downloadBytesImpl({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  throw UnsupportedError('downloadBytes is only supported on Web');
}
