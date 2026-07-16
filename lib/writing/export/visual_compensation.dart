import 'dart:convert';
import 'dart:io';

import '../model/geometry.dart';

class VisualCompensationTransform {
  const VisualCompensationTransform({
    required this.visualDirPath,
    required this.sourcePath,
    required this.dxMm,
    required this.dyMm,
    required this.dzMm,
  });

  final String visualDirPath;
  final String sourcePath;
  final double dxMm;
  final double dyMm;
  final double dzMm;

  String get summary =>
      'source=$sourcePath commandXY=(${dxMm.toStringAsFixed(3)}, '
      '${dyMm.toStringAsFixed(3)})';

  static Future<VisualCompensationTransform?> tryLoad({
    String? visualDirPath,
  }) async {
    try {
      return await load(visualDirPath: visualDirPath);
    } catch (_) {
      return null;
    }
  }

  static Future<VisualCompensationTransform> load({
    String? visualDirPath,
  }) async {
    final visualDir = await _findVisualDir(visualDirPath: visualDirPath);
    if (visualDir == null) {
      throw const FileSystemException('02_visual folder was not found.');
    }

    final correctionFile = File(
      _join(visualDir.path, 'surface_trajectory_correction_latest.json'),
    );
    final decoded = jsonDecode(await correctionFile.readAsString());
    final correction = decoded is Map
        ? decoded['command_precompensation_mm']
        : null;
    if (correction is! List || correction.length < 3) {
      throw const FormatException(
        'command_precompensation_mm must contain dx, dy and dz.',
      );
    }

    return VisualCompensationTransform(
      visualDirPath: visualDir.path,
      sourcePath: correctionFile.path,
      dxMm: _jsonDouble(correction[0], 0.0),
      dyMm: _jsonDouble(correction[1], 0.0),
      dzMm: _jsonDouble(correction[2], 0.0),
    );
  }

  Vec2 correctMachinePoint(Vec2 machinePoint) {
    return Vec2(machinePoint.x + dxMm, machinePoint.y + dyMm);
  }

  static Future<Directory?> _findVisualDir({String? visualDirPath}) async {
    if (visualDirPath != null) {
      final dir = Directory(visualDirPath);
      if (await dir.exists()) return dir;
    }

    var dir = Directory.current;
    for (var i = 0; i < 10; i++) {
      final candidate = Directory(_join(dir.path, '02_visual'));
      if (await candidate.exists()) return candidate;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  static String _join(String first, String second) =>
      '$first${Platform.pathSeparator}$second';

  static double _jsonDouble(Object? value, double fallback) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }
}
