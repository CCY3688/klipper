// lib/writing/export/gcode_file_store.dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class GcodeFileStore {
  Future<String> saveToAppDocuments({
    required String filename,
    required String gcodeText,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/gcode_exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    final safeName = _sanitize(filename);
    final file = File('${exportDir.path}/$safeName');
    await file.writeAsString(gcodeText);
    return file.path;
  }

  String _sanitize(String name) {
    // 简单处理，避免 Windows/Android 路径非法字符
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }
}