import 'package:flutter_test/flutter_test.dart';
import 'package:klipper/state/navigation_controller.dart';
import 'package:klipper/ui/coating/coating_motion.dart';

void main() {
  const request = CoatingMotionRequest(
    x: 12.5,
    y: -8,
    z: 36.25,
    feedMmPerS: 20,
    penServoAngleDeg: 75,
    cartridgeServoAngleDeg: 120,
    servoSettleMs: 500,
  );

  test('builds overlap joint movement without a dwell', () {
    expect(
      request.buildGcode(
        CoatingMotionMode.joint,
        sequence: CoatingJointSequence.overlap,
      ),
      'G21\n'
      'G90\n'
      'SET_SERVO SERVO=pen_servo ANGLE=75.0\n'
      'SET_SERVO SERVO=cartridge_servo ANGLE=120.0\n'
      'G1 X12.500 Y-8.000 Z36.250 F1200\n'
      'M400',
    );
  });

  test('builds servo-first joint movement with a dwell', () {
    expect(
      request.buildGcode(CoatingMotionMode.joint),
      contains('SET_SERVO SERVO=cartridge_servo ANGLE=120.0\nG4 P500\nG1'),
    );
  });

  test('builds isolated platform and double-servo commands', () {
    expect(
      request.buildGcode(CoatingMotionMode.platformOnly),
      isNot(contains('SET_SERVO')),
    );
    expect(
      request.buildGcode(CoatingMotionMode.servoOnly),
      'SET_SERVO SERVO=pen_servo ANGLE=75.0\n'
      'SET_SERVO SERVO=cartridge_servo ANGLE=120.0',
    );
    expect(
      request.buildServoGcode(CoatingServo.cartridge),
      'SET_SERVO SERVO=cartridge_servo ANGLE=120.0',
    );
    expect(
      CoatingMotionRequest.buildServoReleaseGcode(CoatingServo.values),
      'SET_SERVO SERVO=pen_servo WIDTH=0\n'
      'SET_SERVO SERVO=cartridge_servo WIDTH=0',
    );
  });

  test('validates the acceptance limits used by the page', () {
    const invalidAngle = CoatingMotionRequest(
      x: 0,
      y: 0,
      z: 0,
      feedMmPerS: 20,
      penServoAngleDeg: 181,
      cartridgeServoAngleDeg: 60,
      servoSettleMs: 0,
    );
    expect(
      invalidAngle.validate(CoatingMotionMode.joint),
      contains('俯仰 Pitch 舵机角度必须在 50° 到 180°'),
    );

    const invalidPitch = CoatingMotionRequest(
      x: 0,
      y: 0,
      z: 0,
      feedMmPerS: 20,
      penServoAngleDeg: 49,
      cartridgeServoAngleDeg: 30,
      servoSettleMs: 0,
    );
    expect(
      invalidPitch.validate(CoatingMotionMode.servoOnly),
      contains('50° 到 180°'),
    );

    const invalidFeed = CoatingMotionRequest(
      x: 0,
      y: 0,
      z: 0,
      feedMmPerS: 0,
      penServoAngleDeg: 60,
      cartridgeServoAngleDeg: 60,
      servoSettleMs: 0,
    );
    expect(
      invalidFeed.validate(CoatingMotionMode.platformOnly),
      contains('0.1 mm/s'),
    );
  });

  test('keeps coating between surface and motion replay navigation', () {
    final tabs = SidebarTab.values;
    expect(
      tabs.indexOf(SidebarTab.coating),
      tabs.indexOf(SidebarTab.surface) + 1,
    );
    expect(
      tabs.indexOf(SidebarTab.motionReplay),
      tabs.indexOf(SidebarTab.coating) + 1,
    );
  });
}
