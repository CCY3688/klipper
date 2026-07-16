import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the machine coordinate used as the writing origin.
class WritingStartPointConfig {
  static const _kStartPointX = 'writing_start_point_x';
  static const _kStartPointY = 'writing_start_point_y';
  static const _kStartPointZ = 'writing_start_point_z';
  static const _kStartPointEnabled = 'writing_start_point_enabled';

  final Offset offset;
  final double z;
  final bool hasCustomStartPoint;

  const WritingStartPointConfig({
    this.offset = Offset.zero,
    this.z = 0.0,
    this.hasCustomStartPoint = false,
  });

  static const defaultConfig = WritingStartPointConfig();

  static Future<WritingStartPointConfig> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final enabled = sp.getBool(_kStartPointEnabled) ?? false;
      final x = sp.getDouble(_kStartPointX) ?? 0.0;
      final y = sp.getDouble(_kStartPointY) ?? 0.0;
      final z = sp.getDouble(_kStartPointZ) ?? 0.0;

      return WritingStartPointConfig(
        offset: Offset(x, y),
        z: z,
        hasCustomStartPoint: enabled,
      );
    } catch (e) {
      return defaultConfig;
    }
  }

  Future<void> save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble(_kStartPointX, offset.dx);
      await sp.setDouble(_kStartPointY, offset.dy);
      await sp.setDouble(_kStartPointZ, z);
      await sp.setBool(_kStartPointEnabled, hasCustomStartPoint);
    } catch (e) {
      debugPrint('Failed to save writing start point config: $e');
    }
  }

  WritingStartPointConfig withCustomStartPoint(Offset newOffset, {double? z}) {
    return WritingStartPointConfig(
      offset: newOffset,
      z: z ?? this.z,
      hasCustomStartPoint: true,
    );
  }

  WritingStartPointConfig reset() {
    return defaultConfig;
  }

  String get formattedText {
    if (!hasCustomStartPoint) {
      return '(0, 0, 0) - default origin';
    }
    return 'X: ${offset.dx.toStringAsFixed(2)}, '
        'Y: ${offset.dy.toStringAsFixed(2)}, '
        'Z: ${z.toStringAsFixed(2)} mm';
  }

  String get shortText {
    if (!hasCustomStartPoint) {
      return 'default';
    }
    return '(${offset.dx.toStringAsFixed(1)}, '
        '${offset.dy.toStringAsFixed(1)}, '
        '${z.toStringAsFixed(1)})';
  }
}
