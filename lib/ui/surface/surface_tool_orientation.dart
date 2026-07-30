import 'dart:math' as math;

import '../coating/coating_motion.dart';
import 'stl_mesh.dart';

enum SurfaceToolPoseMode { xyzOnly, fixed, normalFollow }

enum SurfaceBedZToolheadKind { xyzOnly, dualServo }

extension SurfaceToolPoseModeDetails on SurfaceToolPoseMode {
  String get label => switch (this) {
    SurfaceToolPoseMode.xyzOnly => '仅 XYZ（兼容模式）',
    SurfaceToolPoseMode.fixed => '固定工具姿态',
    SurfaceToolPoseMode.normalFollow => '跟随曲面外法线',
  };

  SurfaceBedZToolheadKind get bedZToolheadKind => switch (this) {
    SurfaceToolPoseMode.xyzOnly => SurfaceBedZToolheadKind.xyzOnly,
    SurfaceToolPoseMode.fixed ||
    SurfaceToolPoseMode.normalFollow => SurfaceBedZToolheadKind.dualServo,
  };
}

extension SurfaceBedZToolheadKindDetails on SurfaceBedZToolheadKind {
  String get storageKey => switch (this) {
    SurfaceBedZToolheadKind.xyzOnly => 'xyz_only',
    SurfaceBedZToolheadKind.dualServo => 'dual_servo',
  };

  String get label => switch (this) {
    SurfaceBedZToolheadKind.xyzOnly => '单针头（仅 XYZ）',
    SurfaceBedZToolheadKind.dualServo => '双自由度舵机工具头',
  };
}

bool surfaceBedZNeedsRecalibration(
  double xyzOnlyBedZ,
  double dualServoBedZ, {
  double toleranceMm = 0.01,
}) {
  return xyzOnlyBedZ.isFinite &&
      dualServoBedZ.isFinite &&
      (xyzOnlyBedZ - dualServoBedZ).abs() <= toleranceMm;
}

class SurfaceToolOrientationConfig {
  static const double defaultYawServoDeg = 30.0;
  static const double defaultPitchServoDeg = 80.0;

  final SurfaceToolPoseMode mode;
  final double fixedYawServoDeg;
  final double fixedPitchServoDeg;
  final double yawOffsetDeg;
  final double pitchOffsetDeg;
  final double tipLengthMm;
  final double tipLateralOffsetMm;
  final bool reverseYaw;
  final bool reversePitch;
  final double deadbandDeg;
  final double maxStepDeg;
  final int settleMs;

  const SurfaceToolOrientationConfig({
    this.mode = SurfaceToolPoseMode.xyzOnly,
    this.fixedYawServoDeg = defaultYawServoDeg,
    this.fixedPitchServoDeg = defaultPitchServoDeg,
    this.yawOffsetDeg = 0,
    this.pitchOffsetDeg = 0,
    this.tipLengthMm = 0,
    this.tipLateralOffsetMm = 0,
    this.reverseYaw = false,
    this.reversePitch = false,
    this.deadbandDeg = 1,
    this.maxStepDeg = 25,
    this.settleMs = 250,
  });

  SurfaceToolOrientationConfig copyWith({
    SurfaceToolPoseMode? mode,
    double? fixedYawServoDeg,
    double? fixedPitchServoDeg,
    double? yawOffsetDeg,
    double? pitchOffsetDeg,
    double? tipLengthMm,
    double? tipLateralOffsetMm,
    bool? reverseYaw,
    bool? reversePitch,
    double? deadbandDeg,
    double? maxStepDeg,
    int? settleMs,
  }) => SurfaceToolOrientationConfig(
    mode: mode ?? this.mode,
    fixedYawServoDeg: fixedYawServoDeg ?? this.fixedYawServoDeg,
    fixedPitchServoDeg: fixedPitchServoDeg ?? this.fixedPitchServoDeg,
    yawOffsetDeg: yawOffsetDeg ?? this.yawOffsetDeg,
    pitchOffsetDeg: pitchOffsetDeg ?? this.pitchOffsetDeg,
    tipLengthMm: tipLengthMm ?? this.tipLengthMm,
    tipLateralOffsetMm: tipLateralOffsetMm ?? this.tipLateralOffsetMm,
    reverseYaw: reverseYaw ?? this.reverseYaw,
    reversePitch: reversePitch ?? this.reversePitch,
    deadbandDeg: deadbandDeg ?? this.deadbandDeg,
    maxStepDeg: maxStepDeg ?? this.maxStepDeg,
    settleMs: settleMs ?? this.settleMs,
  );
}

/// Returns the machine-pivot offset that keeps the needle tip at its target.
/// The zero pose is vertical down with yaw toward world +X.
StlVector3 surfaceToolTipCompensationOffset(
  SurfaceToolPose pose,
  SurfaceToolOrientationConfig config,
) {
  final length = config.tipLengthMm;
  final lateral = config.tipLateralOffsetMm;
  if (length == 0 && lateral == 0) return const StlVector3(0, 0, 0);

  final yawDeg = pose.worldYawDeg;
  final pitchDeg = pose.worldPitchDeg;
  if (yawDeg == null || pitchDeg == null) {
    throw ArgumentError('针尖补偿需要有效的世界姿态。');
  }
  final yaw = yawDeg * math.pi / 180;
  final pitch = pitchDeg * math.pi / 180;
  final cosPitch = math.cos(pitch);
  final sinPitch = math.sin(pitch);
  final cosYaw = math.cos(yaw);
  final sinYaw = math.sin(yaw);

  final tipOffsetX = length * cosPitch * cosYaw - lateral * sinPitch * cosYaw;
  final tipOffsetY = length * cosPitch * sinYaw - lateral * sinPitch * sinYaw;
  final tipOffsetZ = length * sinPitch + lateral * cosPitch;

  // At the declared zero pose rRef = (e, 0, -L); command the pivot opposite
  // to the change in the tip offset.
  return StlVector3(lateral - tipOffsetX, -tipOffsetY, -length - tipOffsetZ);
}

class SurfaceToolPose {
  final double? worldYawDeg;
  final double? worldPitchDeg;
  final double yawServoDeg;
  final double pitchServoDeg;
  final String? error;

  const SurfaceToolPose({
    this.worldYawDeg,
    this.worldPitchDeg,
    required this.yawServoDeg,
    required this.pitchServoDeg,
    this.error,
  });

  bool get isValid => error == null;

  static SurfaceToolPose fixed(SurfaceToolOrientationConfig config) =>
      _validatedPose(
        yawServoDeg: config.fixedYawServoDeg,
        pitchServoDeg: config.fixedPitchServoDeg,
      );

  static SurfaceToolPose fromOutwardNormal(
    StlVector3 normal,
    SurfaceToolOrientationConfig config, {
    double fallbackWorldYawDeg = 0,
  }) => fromToolAxis(
    toolAxisFromOutwardNormal(normal),
    config,
    fallbackWorldYawDeg: fallbackWorldYawDeg,
  );

  /// Maps the projected surface normal into the calibrated toolhead frame.
  /// The horizontal component selects the nozzle's yaw direction; the tool
  /// must still point down toward the workpiece, so its vertical component is
  /// inverted.
  static StlVector3 toolAxisFromOutwardNormal(StlVector3 normal) =>
      StlVector3(normal.x, normal.y, -normal.z);

  /// Converts the direction from the gimbal pivot to the tool tip into servo
  /// commands. [fromOutwardNormal] is the preferred surface-planning entry
  /// point so preview and G-code use the calibrated frame convention.
  ///
  /// At vertical down/up the yaw axis is physically singular.  Keeping the
  /// previous yaw avoids a meaningless rotation at the cone apex or a flat
  /// surface.
  static SurfaceToolPose fromToolAxis(
    StlVector3 toolAxis,
    SurfaceToolOrientationConfig config, {
    double fallbackWorldYawDeg = 0,
  }) {
    final length = toolAxis.length;
    if (!length.isFinite || length <= 1e-9) {
      return const SurfaceToolPose(
        yawServoDeg: double.nan,
        pitchServoDeg: double.nan,
        error: '曲面法线无效。',
      );
    }
    final unit = toolAxis.normalized();
    final horizontal = math.sqrt(unit.x * unit.x + unit.y * unit.y);
    final worldYawDeg = horizontal <= 1e-7
        ? fallbackWorldYawDeg
        : math.atan2(unit.y, unit.x) * 180 / math.pi;
    final worldPitchDeg = math.atan2(unit.z, horizontal) * 180 / math.pi;
    final yawFactor = config.reverseYaw ? -1.0 : 1.0;
    final pitchFactor = config.reversePitch ? 1.0 : -1.0;
    // 80° is horizontal and 180° is vertically down: 100 servo degrees / 90°.
    return _validatedPose(
      worldYawDeg: worldYawDeg,
      worldPitchDeg: worldPitchDeg,
      yawServoDeg:
          SurfaceToolOrientationConfig.defaultYawServoDeg +
          config.yawOffsetDeg +
          yawFactor * worldYawDeg,
      pitchServoDeg:
          SurfaceToolOrientationConfig.defaultPitchServoDeg +
          config.pitchOffsetDeg +
          pitchFactor * worldPitchDeg * (100 / 90),
    );
  }

  static SurfaceToolPose _validatedPose({
    double? worldYawDeg,
    double? worldPitchDeg,
    required double yawServoDeg,
    required double pitchServoDeg,
  }) {
    if (!yawServoDeg.isFinite || !pitchServoDeg.isFinite) {
      return SurfaceToolPose(
        worldYawDeg: worldYawDeg,
        worldPitchDeg: worldPitchDeg,
        yawServoDeg: yawServoDeg,
        pitchServoDeg: pitchServoDeg,
        error: '舵机姿态不是有效数字。',
      );
    }
    if (yawServoDeg < CoatingServo.cartridge.minAngleDeg ||
        yawServoDeg > CoatingServo.cartridge.maxAngleDeg) {
      return SurfaceToolPose(
        worldYawDeg: worldYawDeg,
        worldPitchDeg: worldPitchDeg,
        yawServoDeg: yawServoDeg,
        pitchServoDeg: pitchServoDeg,
        error: 'Yaw 指令 ${yawServoDeg.toStringAsFixed(1)}° 超出 0°–180° 限位。',
      );
    }
    if (pitchServoDeg < CoatingServo.pen.minAngleDeg ||
        pitchServoDeg > CoatingServo.pen.maxAngleDeg) {
      return SurfaceToolPose(
        worldYawDeg: worldYawDeg,
        worldPitchDeg: worldPitchDeg,
        yawServoDeg: yawServoDeg,
        pitchServoDeg: pitchServoDeg,
        error: 'Pitch 指令 ${pitchServoDeg.toStringAsFixed(1)}° 超出 50°–180° 限位。',
      );
    }
    return SurfaceToolPose(
      worldYawDeg: worldYawDeg,
      worldPitchDeg: worldPitchDeg,
      yawServoDeg: yawServoDeg,
      pitchServoDeg: pitchServoDeg,
    );
  }
}

class SurfaceToolOrientationSummary {
  final int total;
  final int valid;
  final int invalid;
  final int updates;
  final double? minYawServoDeg;
  final double? maxYawServoDeg;
  final double? minPitchServoDeg;
  final double? maxPitchServoDeg;
  final List<String> errors;

  const SurfaceToolOrientationSummary({
    required this.total,
    required this.valid,
    required this.invalid,
    required this.updates,
    required this.minYawServoDeg,
    required this.maxYawServoDeg,
    required this.minPitchServoDeg,
    required this.maxPitchServoDeg,
    required this.errors,
  });

  bool get canExport => invalid == 0 && errors.isEmpty;
}

SurfaceToolOrientationSummary summarizeSurfaceToolPoses(
  Iterable<SurfaceToolPose?> poses,
  SurfaceToolOrientationConfig config,
) {
  final list = poses.whereType<SurfaceToolPose>().toList(growable: false);
  final valid = list.where((pose) => pose.isValid).toList(growable: false);
  final errors = <String>{
    ...list.where((pose) => !pose.isValid).map((pose) => pose.error!),
  };
  SurfaceToolPose? previous;
  var updates = 0;
  for (final pose in valid) {
    if (previous != null) {
      final yawDelta = (pose.yawServoDeg - previous.yawServoDeg).abs();
      final pitchDelta = (pose.pitchServoDeg - previous.pitchServoDeg).abs();
      if (math.max(yawDelta, pitchDelta) > config.maxStepDeg) {
        errors.add('相邻姿态变化超过 ${config.maxStepDeg.toStringAsFixed(1)}°。');
      }
      if (math.max(yawDelta, pitchDelta) > config.deadbandDeg) updates++;
    } else {
      updates++;
    }
    previous = pose;
  }
  double? minimum(Iterable<double> values) =>
      values.isEmpty ? null : values.reduce(math.min);
  double? maximum(Iterable<double> values) =>
      values.isEmpty ? null : values.reduce(math.max);
  return SurfaceToolOrientationSummary(
    total: list.length,
    valid: valid.length,
    invalid: list.length - valid.length,
    updates: updates,
    minYawServoDeg: minimum(valid.map((pose) => pose.yawServoDeg)),
    maxYawServoDeg: maximum(valid.map((pose) => pose.yawServoDeg)),
    minPitchServoDeg: minimum(valid.map((pose) => pose.pitchServoDeg)),
    maxPitchServoDeg: maximum(valid.map((pose) => pose.pitchServoDeg)),
    errors: errors.toList(growable: false),
  );
}
