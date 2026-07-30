import 'surface_tool_orientation.dart';

class SurfaceMotionPreflight {
  const SurfaceMotionPreflight({
    required this.moonrakerConnected,
    required this.klippyReady,
    required this.klippyStateMessage,
    required this.printState,
    required this.sdIsActive,
    required this.isHomed,
    required this.hasTrajectory,
    required this.hasActiveBedZCalibration,
    required this.bedZToolheadWarning,
    required this.orientationSummary,
  });

  final bool moonrakerConnected;
  final bool klippyReady;
  final String klippyStateMessage;
  final String printState;
  final bool sdIsActive;
  final bool isHomed;
  final bool hasTrajectory;
  final bool hasActiveBedZCalibration;
  final String? bedZToolheadWarning;
  final SurfaceToolOrientationSummary orientationSummary;

  String? get blockingReason {
    if (!moonrakerConnected) return 'Moonraker 未连接，请先连接打印机。';
    if (!klippyReady) return 'Klipper 当前未就绪：$klippyStateMessage';
    if (sdIsActive || printState == 'printing' || printState == 'paused') {
      return '打印机当前正在执行任务：$printState';
    }
    if (!isHomed) return '打印机尚未完成 XYZ 回零；请先回零后再启动。';
    if (!hasTrajectory) return '尚未生成可执行的平滑运动轨迹。';
    if (!hasActiveBedZCalibration) return '当前工具头尚未完成床面 Z 标定。';
    if (bedZToolheadWarning != null) return bedZToolheadWarning;
    if (!orientationSummary.canExport) {
      return '工具姿态校验未通过：${orientationSummary.errors.join('；')}';
    }
    return null;
  }

  bool get canStart => blockingReason == null;
}
