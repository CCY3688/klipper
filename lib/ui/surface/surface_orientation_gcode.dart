import '../coating/coating_motion.dart';
import 'surface_tool_orientation.dart';

class SurfaceOrientationGcodePoint {
  final double x;
  final double y;
  final double z;
  final double speedMmPerS;
  final bool travel;
  final SurfaceToolPose? pose;

  const SurfaceOrientationGcodePoint({
    required this.x,
    required this.y,
    required this.z,
    required this.speedMmPerS,
    required this.travel,
    this.pose,
  });
}

class SurfaceOrientationGcodeResult {
  final String gcode;
  final SurfaceToolOrientationSummary summary;

  const SurfaceOrientationGcodeResult({
    required this.gcode,
    required this.summary,
  });
}

String buildDefaultSurfaceToolPoseGcode({int settleMs = 0}) {
  final buffer = StringBuffer()
    ..writeln('; Return gimbal to default pose')
    ..writeln('SET_SERVO SERVO=${CoatingServo.pen.klipperName} ANGLE=80.0')
    ..writeln(
      'SET_SERVO SERVO=${CoatingServo.cartridge.klipperName} ANGLE=30.0',
    )
    ..writeln('M400');
  if (settleMs > 0) buffer.writeln('G4 P$settleMs');
  return buffer.toString();
}

SurfaceOrientationGcodeResult buildSurfaceOrientationGcode({
  required Iterable<SurfaceOrientationGcodePoint> points,
  required SurfaceToolOrientationConfig config,
  required String header,
}) {
  final pointList = points.toList(growable: false);
  final workPoses = pointList
      .where((point) => !point.travel)
      .map((point) => point.pose);
  final summary = summarizeSurfaceToolPoses(workPoses, config);
  if (config.mode != SurfaceToolPoseMode.xyzOnly && !summary.canExport) {
    throw ArgumentError(summary.errors.join('\n'));
  }

  final buffer = StringBuffer(header);
  SurfaceToolPose? lastPose;
  for (final point in pointList) {
    final pose = point.pose;
    if (config.mode != SurfaceToolPoseMode.xyzOnly && !point.travel) {
      if (pose == null || !pose.isValid) {
        throw ArgumentError(pose?.error ?? '工作点缺少工具姿态。');
      }
      final hasChanged =
          lastPose == null ||
          (pose.yawServoDeg - lastPose.yawServoDeg).abs() >
              config.deadbandDeg ||
          (pose.pitchServoDeg - lastPose.pitchServoDeg).abs() >
              config.deadbandDeg;
      if (hasChanged) {
        buffer
          ..writeln(
            'SET_SERVO SERVO=${CoatingServo.pen.klipperName} '
            'ANGLE=${pose.pitchServoDeg.toStringAsFixed(1)}',
          )
          ..writeln(
            'SET_SERVO SERVO=${CoatingServo.cartridge.klipperName} '
            'ANGLE=${pose.yawServoDeg.toStringAsFixed(1)}',
          )
          ..writeln('M400');
        if (config.settleMs > 0) buffer.writeln('G4 P${config.settleMs}');
        lastPose = pose;
      }
    }
    buffer.writeln(
      'G1 X${point.x.toStringAsFixed(3)} '
      'Y${point.y.toStringAsFixed(3)} '
      'Z${point.z.toStringAsFixed(3)} '
      'F${(point.speedMmPerS * 60).toStringAsFixed(0)}',
    );
  }
  return SurfaceOrientationGcodeResult(
    gcode: buffer.toString(),
    summary: summary,
  );
}
