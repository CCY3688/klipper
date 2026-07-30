import 'package:flutter_test/flutter_test.dart';
import 'package:klipper/ui/surface/surface_motion_preflight.dart';
import 'package:klipper/ui/surface/surface_tool_orientation.dart';

SurfaceMotionPreflight preflight({
  bool moonrakerConnected = true,
  bool klippyReady = true,
  String printState = 'idle',
  bool sdIsActive = false,
  bool isHomed = true,
  bool hasTrajectory = true,
  bool hasActiveBedZCalibration = true,
  String? bedZToolheadWarning,
  SurfaceToolOrientationSummary? orientationSummary,
}) => SurfaceMotionPreflight(
  moonrakerConnected: moonrakerConnected,
  klippyReady: klippyReady,
  klippyStateMessage: 'Printer is ready',
  printState: printState,
  sdIsActive: sdIsActive,
  isHomed: isHomed,
  hasTrajectory: hasTrajectory,
  hasActiveBedZCalibration: hasActiveBedZCalibration,
  bedZToolheadWarning: bedZToolheadWarning,
  orientationSummary:
      orientationSummary ??
      const SurfaceToolOrientationSummary(
        total: 0,
        valid: 0,
        invalid: 0,
        updates: 0,
        minYawServoDeg: null,
        maxYawServoDeg: null,
        minPitchServoDeg: null,
        maxPitchServoDeg: null,
        errors: [],
      ),
);

void main() {
  test('allows execution only when all preflight checks pass', () {
    expect(preflight().canStart, isTrue);
  });

  test('blocks disconnected, unhomed, and active printers', () {
    expect(
      preflight(moonrakerConnected: false).blockingReason,
      contains('未连接'),
    );
    expect(preflight(isHomed: false).blockingReason, contains('XYZ 回零'));
    expect(preflight(printState: 'printing').blockingReason, contains('执行任务'));
  });

  test('blocks missing calibration and invalid trajectory', () {
    expect(
      preflight(hasActiveBedZCalibration: false).blockingReason,
      contains('床面 Z 标定'),
    );
    expect(preflight(hasTrajectory: false).blockingReason, contains('平滑运动轨迹'));
  });

  test('blocks toolhead calibration and pose validation warnings', () {
    expect(
      preflight(bedZToolheadWarning: '双自由度工具头需要重新标定').blockingReason,
      contains('重新标定'),
    );
    expect(
      preflight(
        orientationSummary: const SurfaceToolOrientationSummary(
          total: 2,
          valid: 1,
          invalid: 1,
          updates: 1,
          minYawServoDeg: 30,
          maxYawServoDeg: 30,
          minPitchServoDeg: 80,
          maxPitchServoDeg: 80,
          errors: ['相邻姿态变化超过 25.0°。'],
        ),
      ).blockingReason,
      contains('姿态校验未通过'),
    );
  });
}
