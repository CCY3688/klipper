import 'package:flutter_test/flutter_test.dart';
import 'package:klipper/ui/surface/stl_mesh.dart';
import 'package:klipper/ui/surface/surface_tool_orientation.dart';

void main() {
  test(
    'keeps normal yaw while turning the tool axis down toward the workpiece',
    () {
      final pose = SurfaceToolPose.fromOutwardNormal(
        const StlVector3(1, 0, 0),
        const SurfaceToolOrientationConfig(
          mode: SurfaceToolPoseMode.normalFollow,
        ),
      );

      expect(pose.isValid, isTrue);
      expect(pose.worldYawDeg, closeTo(0, 0.001));
      expect(pose.worldPitchDeg, closeTo(0, 0.001));
      expect(pose.yawServoDeg, closeTo(30, 0.001));
      expect(pose.pitchServoDeg, closeTo(80, 0.001));
    },
  );

  test('maps a raised surface normal to a valid downward tool pose', () {
    final pose = SurfaceToolPose.fromOutwardNormal(
      const StlVector3(1, 0, 1),
      const SurfaceToolOrientationConfig(
        mode: SurfaceToolPoseMode.normalFollow,
      ),
    );

    expect(pose.isValid, isTrue);
    expect(pose.worldYawDeg, closeTo(0, 0.001));
    expect(pose.worldPitchDeg, closeTo(-45, 0.001));
    expect(pose.yawServoDeg, closeTo(30, 0.001));
    expect(pose.pitchServoDeg, closeTo(130, 0.001));
  });

  test('applies configurable offsets and direction reversals', () {
    final pose = SurfaceToolPose.fromOutwardNormal(
      const StlVector3(0, -1, 0),
      const SurfaceToolOrientationConfig(
        mode: SurfaceToolPoseMode.normalFollow,
        yawOffsetDeg: 10,
        reverseYaw: true,
        pitchOffsetDeg: 5,
      ),
    );

    expect(pose.isValid, isTrue);
    expect(pose.yawServoDeg, closeTo(130, 0.001));
    expect(pose.pitchServoDeg, closeTo(85, 0.001));
  });

  test('keeps fallback yaw for a vertical tool axis', () {
    final pose = SurfaceToolPose.fromOutwardNormal(
      const StlVector3(0, 0, 1),
      const SurfaceToolOrientationConfig(
        mode: SurfaceToolPoseMode.normalFollow,
      ),
    );

    expect(pose.worldYawDeg, closeTo(0, 0.001));
    expect(pose.worldPitchDeg, closeTo(-90, 0.001));
    expect(pose.yawServoDeg, closeTo(30, 0.001));
    expect(pose.pitchServoDeg, closeTo(180, 0.001));
    expect(pose.isValid, isTrue);
  });

  test('rejects servo poses beyond mechanical limits', () {
    final pose = SurfaceToolPose.fixed(
      const SurfaceToolOrientationConfig(
        mode: SurfaceToolPoseMode.fixed,
        fixedYawServoDeg: 181,
      ),
    );

    expect(pose.isValid, isFalse);
    expect(pose.error, contains('0°–180°'));
  });

  test('accepts inclusive yaw and pitch mechanical limits', () {
    final yawMin = SurfaceToolPose.fixed(
      const SurfaceToolOrientationConfig(
        mode: SurfaceToolPoseMode.fixed,
        fixedYawServoDeg: 0,
        fixedPitchServoDeg: 50,
      ),
    );
    final yawMax = SurfaceToolPose.fixed(
      const SurfaceToolOrientationConfig(
        mode: SurfaceToolPoseMode.fixed,
        fixedYawServoDeg: 180,
        fixedPitchServoDeg: 180,
      ),
    );

    expect(yawMin.isValid, isTrue);
    expect(yawMax.isValid, isTrue);
  });

  test('rejects pitch commands outside the 50 to 180 degree range', () {
    final belowMin = SurfaceToolPose.fixed(
      const SurfaceToolOrientationConfig(
        mode: SurfaceToolPoseMode.fixed,
        fixedPitchServoDeg: 49.9,
      ),
    );
    final aboveMax = SurfaceToolPose.fixed(
      const SurfaceToolOrientationConfig(
        mode: SurfaceToolPoseMode.fixed,
        fixedPitchServoDeg: 180.1,
      ),
    );

    expect(belowMin.isValid, isFalse);
    expect(belowMin.error, contains('50°–180°'));
    expect(aboveMax.isValid, isFalse);
    expect(aboveMax.error, contains('50°–180°'));
  });

  test('maps XYZ-only and servo modes to separate Z calibration toolheads', () {
    expect(
      SurfaceToolPoseMode.xyzOnly.bedZToolheadKind,
      SurfaceBedZToolheadKind.xyzOnly,
    );
    expect(
      SurfaceToolPoseMode.fixed.bedZToolheadKind,
      SurfaceBedZToolheadKind.dualServo,
    );
    expect(
      SurfaceToolPoseMode.normalFollow.bedZToolheadKind,
      SurfaceBedZToolheadKind.dualServo,
    );
  });

  test('requires servo Z recalibration when it matches XYZ-only Z', () {
    expect(surfaceBedZNeedsRecalibration(-30.0, -30.005), isTrue);
    expect(surfaceBedZNeedsRecalibration(-30.0, -30.011), isFalse);
  });

  test('keeps zero compensation for zero geometry', () {
    final pose = SurfaceToolPose.fromOutwardNormal(
      const StlVector3(1, 1, 1),
      const SurfaceToolOrientationConfig(
        mode: SurfaceToolPoseMode.normalFollow,
      ),
    );

    final offset = surfaceToolTipCompensationOffset(
      pose,
      const SurfaceToolOrientationConfig(),
    );

    expect(offset.x, closeTo(0, 0.001));
    expect(offset.y, closeTo(0, 0.001));
    expect(offset.z, closeTo(0, 0.001));
  });

  test('uses vertical-down plus X as the needle compensation zero pose', () {
    final pose = SurfaceToolPose.fromOutwardNormal(
      const StlVector3(0, 0, 1),
      const SurfaceToolOrientationConfig(
        mode: SurfaceToolPoseMode.normalFollow,
      ),
    );
    const config = SurfaceToolOrientationConfig(
      tipLengthMm: 20,
      tipLateralOffsetMm: 3,
    );

    final offset = surfaceToolTipCompensationOffset(pose, config);

    expect(offset.x, closeTo(0, 0.001));
    expect(offset.y, closeTo(0, 0.001));
    expect(offset.z, closeTo(0, 0.001));
  });

  test('compensates pivot opposite to a length-only tip tilt', () {
    final pose = SurfaceToolPose.fromOutwardNormal(
      const StlVector3(1, 0, 1),
      const SurfaceToolOrientationConfig(
        mode: SurfaceToolPoseMode.normalFollow,
      ),
    );

    final offset = surfaceToolTipCompensationOffset(
      pose,
      const SurfaceToolOrientationConfig(tipLengthMm: 20),
    );

    expect(offset.x, closeTo(-14.142, 0.001));
    expect(offset.y, closeTo(0, 0.001));
    expect(offset.z, closeTo(-5.858, 0.001));
  });

  test('rotates lateral compensation with yaw and honors its sign', () {
    final positiveYaw = SurfaceToolPose.fromOutwardNormal(
      const StlVector3(0, 1, 1),
      const SurfaceToolOrientationConfig(
        mode: SurfaceToolPoseMode.normalFollow,
      ),
    );
    const positiveConfig = SurfaceToolOrientationConfig(tipLateralOffsetMm: 5);
    const negativeConfig = SurfaceToolOrientationConfig(tipLateralOffsetMm: -5);

    final positive = surfaceToolTipCompensationOffset(
      positiveYaw,
      positiveConfig,
    );
    final negative = surfaceToolTipCompensationOffset(
      positiveYaw,
      negativeConfig,
    );

    expect(positive.x, closeTo(5, 0.001));
    expect(positive.y, closeTo(-3.536, 0.001));
    expect(negative.x, closeTo(-5, 0.001));
    expect(negative.y, closeTo(3.536, 0.001));
  });

  test('summaries flag unsafe adjacent pose changes', () {
    const config = SurfaceToolOrientationConfig(maxStepDeg: 10);
    final summary = summarizeSurfaceToolPoses([
      const SurfaceToolPose(yawServoDeg: 30, pitchServoDeg: 80),
      const SurfaceToolPose(yawServoDeg: 60, pitchServoDeg: 80),
    ], config);

    expect(summary.canExport, isFalse);
    expect(summary.errors.single, contains('超过 10.0°'));
  });
}
