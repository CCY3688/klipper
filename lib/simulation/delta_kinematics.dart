import 'dart:math' as math;

/// Rotary-delta geometry, expressed in the same millimetre machine frame as G-code.
/// Z=0 is the configured bed plane and positive Z points towards the shoulders.
class DeltaGeometry {
  final double shoulderRadiusMm;
  final double shoulderHeightMm;
  final double upperArmMm;
  final double lowerArmMm;
  final double platformRadiusMm;
  final double minJointDeg;
  final double maxJointDeg;

  const DeltaGeometry({
    this.shoulderRadiusMm = 65.5,
    this.shoulderHeightMm = 347,
    this.upperArmMm = 173,
    this.lowerArmMm = 289.9,
    this.platformRadiusMm = 28,
    this.minJointDeg = -20,
    this.maxJointDeg = 250,
  });
}

class DeltaJointSolution {
  final List<double> jointDeg;
  final String? error;

  const DeltaJointSolution._(this.jointDeg, this.error);

  const DeltaJointSolution.ok(List<double> jointDeg) : this._(jointDeg, null);

  const DeltaJointSolution.invalid(String error) : this._(const [], error);

  bool get isReachable => error == null;
}

/// Inverse kinematics for a three-arm rotary delta.
///
/// The planar solve is the standard circle-intersection derivation. It is
/// evaluated in each arm's local Y-Z plane after rotating the TCP by 0/120/240
/// degrees. The platform radius is subtracted from the shoulder radius so the
/// result describes the moving platform centre, not merely an arm endpoint.
class DeltaKinematics {
  final DeltaGeometry geometry;

  const DeltaKinematics(this.geometry);

  DeltaJointSolution inverse(double x, double y, double z) {
    if (![x, y, z].every((value) => value.isFinite)) {
      return const DeltaJointSolution.invalid('TCP coordinate is not finite.');
    }
    final relativeZ = z - geometry.shoulderHeightMm;
    final values = <double>[];
    for (var arm = 0; arm < 3; arm++) {
      final angle = arm * 2 * math.pi / 3;
      final localX = x * math.cos(angle) + y * math.sin(angle);
      final localY = -x * math.sin(angle) + y * math.cos(angle);
      final solved = _solveArm(localX, localY, relativeZ);
      if (solved == null) {
        return DeltaJointSolution.invalid(
          'Arm ${arm + 1} cannot reach this TCP.',
        );
      }
      if (solved < geometry.minJointDeg || solved > geometry.maxJointDeg) {
        return DeltaJointSolution.invalid(
          'Arm ${arm + 1} angle ${solved.toStringAsFixed(1)} deg exceeds configured joint limits.',
        );
      }
      values.add(solved);
    }
    return DeltaJointSolution.ok(values);
  }

  double? _solveArm(double x, double y, double z) {
    if (z.abs() < 1e-8) return null;
    final baseRadius = geometry.shoulderRadiusMm - geometry.platformRadiusMm;
    final yShoulder = -baseRadius / 2;
    final yPlatform = y - geometry.platformRadiusMm / 2;
    final upper = geometry.upperArmMm;
    final lower = geometry.lowerArmMm;
    final a =
        (x * x +
            yPlatform * yPlatform +
            z * z +
            upper * upper -
            lower * lower -
            yShoulder * yShoulder) /
        (2 * z);
    final b = (yShoulder - yPlatform) / z;
    final discriminant =
        -(a + b * yShoulder) * (a + b * yShoulder) +
        upper * upper * (b * b + 1);
    if (discriminant < -1e-7) return null;
    final elbowY =
        (yShoulder - a * b - math.sqrt(math.max(0, discriminant))) /
        (b * b + 1);
    final elbowZ = a + b * elbowY;
    var deg = math.atan2(-elbowZ, yShoulder - elbowY) * 180 / math.pi;
    if (elbowY > yShoulder) deg += 180;
    return deg;
  }
}
