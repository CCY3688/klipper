enum CoatingMotionMode { joint, platformOnly, servoOnly }

enum CoatingJointSequence { overlap, servoThenPlatform }

enum CoatingServo { pen, cartridge }

extension CoatingServoDetails on CoatingServo {
  String get klipperName => switch (this) {
    CoatingServo.pen => 'pen_servo',
    CoatingServo.cartridge => 'cartridge_servo',
  };

  String get label => switch (this) {
    CoatingServo.pen => '俯仰 Pitch 舵机',
    CoatingServo.cartridge => '偏航 Yaw 舵机',
  };

  double get minAngleDeg => switch (this) {
    CoatingServo.pen => 50.0,
    CoatingServo.cartridge => 0.0,
  };

  double get maxAngleDeg => 180.0;
}

class CoatingMotionRequest {
  static const double minServoAngleDeg = 0.0;
  static const double maxServoAngleDeg = 180.0;
  static const double minFeedMmPerS = 0.1;
  static const double maxAcceptanceFeedMmPerS = 120.0;
  static const int maxServoSettleMs = 5000;

  final double x;
  final double y;
  final double z;
  final double feedMmPerS;
  final double penServoAngleDeg;
  final double cartridgeServoAngleDeg;
  final int servoSettleMs;

  const CoatingMotionRequest({
    required this.x,
    required this.y,
    required this.z,
    required this.feedMmPerS,
    required this.penServoAngleDeg,
    required this.cartridgeServoAngleDeg,
    required this.servoSettleMs,
  });

  double angleFor(CoatingServo servo) => switch (servo) {
    CoatingServo.pen => penServoAngleDeg,
    CoatingServo.cartridge => cartridgeServoAngleDeg,
  };

  String? validate(CoatingMotionMode mode) {
    if (mode != CoatingMotionMode.platformOnly) {
      for (final servo in CoatingServo.values) {
        final angle = angleFor(servo);
        if (!angle.isFinite ||
            angle < servo.minAngleDeg ||
            angle > servo.maxAngleDeg) {
          return '${servo.label}角度必须在 ${servo.minAngleDeg.toStringAsFixed(0)}° 到 ${servo.maxAngleDeg.toStringAsFixed(0)}° 之间';
        }
      }
    }

    if (mode != CoatingMotionMode.servoOnly) {
      if (![x, y, z].every((value) => value.isFinite)) {
        return 'XYZ 目标必须是有效数字';
      }
      if (!feedMmPerS.isFinite ||
          feedMmPerS < minFeedMmPerS ||
          feedMmPerS > maxAcceptanceFeedMmPerS) {
        return '验收速度必须在 0.1 mm/s 到 120 mm/s 之间';
      }
    }

    if (servoSettleMs < 0 || servoSettleMs > maxServoSettleMs) {
      return '舵机稳定时间必须在 0 ms 到 5000 ms 之间';
    }
    return null;
  }

  String buildServoGcode(CoatingServo servo) =>
      'SET_SERVO SERVO=${servo.klipperName} ANGLE=${_format(angleFor(servo), 1)}';

  String buildGcode(
    CoatingMotionMode mode, {
    CoatingJointSequence sequence = CoatingJointSequence.servoThenPlatform,
  }) {
    final validationError = validate(mode);
    if (validationError != null) {
      throw ArgumentError(validationError);
    }

    final moveCommand =
        'G1 X${_format(x, 3)} Y${_format(y, 3)} Z${_format(z, 3)} '
        'F${_format(feedMmPerS * 60.0, 0)}';

    switch (mode) {
      case CoatingMotionMode.servoOnly:
        return CoatingServo.values.map(buildServoGcode).join('\n');
      case CoatingMotionMode.platformOnly:
        return ['G21', 'G90', moveCommand, 'M400'].join('\n');
      case CoatingMotionMode.joint:
        return [
          'G21',
          'G90',
          ...CoatingServo.values.map(buildServoGcode),
          if (sequence == CoatingJointSequence.servoThenPlatform &&
              servoSettleMs > 0)
            'G4 P$servoSettleMs',
          moveCommand,
          'M400',
        ].join('\n');
    }
  }

  static String buildServoReleaseGcode(Iterable<CoatingServo> servos) => servos
      .map((servo) => 'SET_SERVO SERVO=${servo.klipperName} WIDTH=0')
      .join('\n');

  static String _format(double value, int fractionDigits) {
    final normalized = value.abs() < 0.0000001 ? 0.0 : value;
    return normalized.toStringAsFixed(fractionDigits);
  }
}
