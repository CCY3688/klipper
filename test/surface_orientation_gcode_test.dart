import 'package:flutter_test/flutter_test.dart';
import 'package:klipper/ui/surface/surface_orientation_gcode.dart';
import 'package:klipper/ui/surface/surface_tool_orientation.dart';

void main() {
  const xyzPoint = SurfaceOrientationGcodePoint(
    x: 1,
    y: 2,
    z: 3,
    speedMmPerS: 20,
    travel: false,
  );

  test('XYZ-only export preserves motion-only output', () {
    final result = buildSurfaceOrientationGcode(
      points: [xyzPoint],
      config: const SurfaceToolOrientationConfig(),
      header: 'G21\nG90\n',
    );

    expect(result.gcode, 'G21\nG90\nG1 X1.000 Y2.000 Z3.000 F1200\n');
    expect(result.gcode, isNot(contains('SET_SERVO')));
  });

  test('fixed poses are emitted before work moves and honor settle time', () {
    const pose = SurfaceToolPose(yawServoDeg: 30, pitchServoDeg: 80);
    final result = buildSurfaceOrientationGcode(
      points: [
        const SurfaceOrientationGcodePoint(
          x: 0,
          y: 0,
          z: 5,
          speedMmPerS: 40,
          travel: true,
          pose: pose,
        ),
        const SurfaceOrientationGcodePoint(
          x: 1,
          y: 2,
          z: 3,
          speedMmPerS: 20,
          travel: false,
          pose: pose,
        ),
      ],
      config: const SurfaceToolOrientationConfig(
        mode: SurfaceToolPoseMode.fixed,
        settleMs: 250,
      ),
      header: '',
    );

    expect(
      result.gcode,
      contains(
        'G1 X0.000 Y0.000 Z5.000 F2400\n'
        'SET_SERVO SERVO=pen_servo ANGLE=80.0\n'
        'SET_SERVO SERVO=cartridge_servo ANGLE=30.0\n'
        'M400\nG4 P250\nG1 X1.000 Y2.000 Z3.000 F1200',
      ),
    );
  });

  test('deadband avoids duplicate servo commands', () {
    const pose = SurfaceToolPose(yawServoDeg: 30, pitchServoDeg: 80);
    final result = buildSurfaceOrientationGcode(
      points: [
        const SurfaceOrientationGcodePoint(
          x: 0,
          y: 0,
          z: 0,
          speedMmPerS: 20,
          travel: false,
          pose: pose,
        ),
        const SurfaceOrientationGcodePoint(
          x: 1,
          y: 0,
          z: 0,
          speedMmPerS: 20,
          travel: false,
          pose: pose,
        ),
      ],
      config: const SurfaceToolOrientationConfig(
        mode: SurfaceToolPoseMode.fixed,
      ),
      header: '',
    );

    expect(RegExp('SET_SERVO').allMatches(result.gcode), hasLength(2));
  });

  test('default gimbal pose returns pitch to 80 and yaw to 30', () {
    expect(
      buildDefaultSurfaceToolPoseGcode(settleMs: 250),
      '; Return gimbal to default pose\n'
      'SET_SERVO SERVO=pen_servo ANGLE=80.0\n'
      'SET_SERVO SERVO=cartridge_servo ANGLE=30.0\n'
      'M400\n'
      'G4 P250\n',
    );
  });

  test('invalid enabled pose prevents G-code generation', () {
    expect(
      () => buildSurfaceOrientationGcode(
        points: [xyzPoint],
        config: const SurfaceToolOrientationConfig(
          mode: SurfaceToolPoseMode.normalFollow,
        ),
        header: '',
      ),
      throwsArgumentError,
    );
  });
}
