import 'dart:io' show File;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/camera_viewer_controller.dart';
import '../../state/parameter_calibration_controller.dart';
import '../fluidd/panels/camera_panel.dart';
import '../fluidd/widgets/fluidd_card.dart';

enum _CalibrationStage {
  charuco,
  machineFrame,
  errorGrid,
  coordinateFit,
  mechanismFit,
}

class ParameterCalibrationPage extends StatefulWidget {
  const ParameterCalibrationPage({super.key});

  @override
  State<ParameterCalibrationPage> createState() =>
      _ParameterCalibrationPageState();
}

class _ParameterCalibrationPageState extends State<ParameterCalibrationPage> {
  late final TextEditingController _workspaceCtrl;
  late final TextEditingController _pythonCtrl;
  late final TextEditingController _moonrakerCtrl;
  late final TextEditingController _snapshotCtrl;
  late final TextEditingController _intrinsicsCtrl;
  _CalibrationStage _selectedStage = _CalibrationStage.charuco;

  @override
  void initState() {
    super.initState();
    final c = context.read<ParameterCalibrationController>();
    _workspaceCtrl = TextEditingController(text: c.workspacePath);
    _pythonCtrl = TextEditingController(text: c.pythonExecutable);
    _moonrakerCtrl = TextEditingController(text: c.moonrakerUrl);
    _snapshotCtrl = TextEditingController(text: c.snapshotUrl);
    _intrinsicsCtrl = TextEditingController(text: c.intrinsicsPath);
  }

  @override
  void dispose() {
    _workspaceCtrl.dispose();
    _pythonCtrl.dispose();
    _moonrakerCtrl.dispose();
    _snapshotCtrl.dispose();
    _intrinsicsCtrl.dispose();
    super.dispose();
  }

  void _syncTextControllers(ParameterCalibrationController c) {
    _syncController(_workspaceCtrl, c.workspacePath);
    _syncController(_pythonCtrl, c.pythonExecutable);
    _syncController(_moonrakerCtrl, c.moonrakerUrl);
    _syncController(_snapshotCtrl, c.snapshotUrl);
    _syncController(_intrinsicsCtrl, c.intrinsicsPath);
  }

  void _syncController(TextEditingController controller, String value) {
    if (controller.text == value || controller.selection.isValid) return;
    controller.text = value;
  }

  Future<void> _runAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = context.read<ParameterCalibrationController>();
    await action();
    if (!mounted) return;
    if (controller.lastError != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(controller.lastError!),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ParameterCalibrationController>(
      builder: (context, c, _) {
        _syncTextControllers(c);
        final isWide = MediaQuery.of(context).size.width > 980;
        final left = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StageCard(
              controller: c,
              selectedStage: _selectedStage,
              onSelect: (stage) => setState(() => _selectedStage = stage),
            ),
            _ConnectionCard(
              controller: c,
              workspaceCtrl: _workspaceCtrl,
              pythonCtrl: _pythonCtrl,
              moonrakerCtrl: _moonrakerCtrl,
              snapshotCtrl: _snapshotCtrl,
              intrinsicsCtrl: _intrinsicsCtrl,
            ),
            _StageActionCard(
              stage: _selectedStage,
              controller: c,
              runAction: _runAction,
            ),
            _ArtifactCard(controller: c, stage: _selectedStage),
          ],
        );
        final right = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CameraPanel(),
            _StageResultCard(stage: _selectedStage, controller: c),
            _LogCard(controller: c),
          ],
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: left),
                    const SizedBox(width: 16),
                    Expanded(flex: 6, child: right),
                  ],
                )
              : Column(children: [left, right]),
        );
      },
    );
  }
}

class _StageCard extends StatelessWidget {
  final ParameterCalibrationController controller;
  final _CalibrationStage selectedStage;
  final ValueChanged<_CalibrationStage> onSelect;

  const _StageCard({
    required this.controller,
    required this.selectedStage,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return FluiddCard(
      title: '校准流程',
      subtitle: controller.busy ? '运行中' : '就绪',
      scrollable: false,
      actions: [
        IconButton(
          tooltip: '重新读取结果',
          icon: const Icon(Icons.refresh, size: 20, color: Colors.grey),
          onPressed: controller.busy ? null : controller.loadLatestResult,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepTile(
            index: 0,
            title: '床面 ChArUco 外参',
            subtitle: '先让末端避让，再确认床面坐标系与叠加图',
            active: selectedStage == _CalibrationStage.charuco,
            done: controller.latestCharucoResult != null,
            onTap: () => onSelect(_CalibrationStage.charuco),
          ),
          _StepTile(
            index: 1,
            title: '机械坐标系对齐',
            subtitle: '以 ChArUco 中心为原点估计 yaw、tx、ty、tz',
            active: selectedStage == _CalibrationStage.machineFrame,
            done: controller.latestResult != null,
            onTap: () => onSelect(_CalibrationStage.machineFrame),
          ),
          _StepTile(
            index: 2,
            title: '误差采样网格',
            subtitle: '采集不同 XY 与 Z 高度下的视觉误差',
            active: selectedStage == _CalibrationStage.errorGrid,
            done: controller.latestStage2Result != null,
            onTap: () => onSelect(_CalibrationStage.errorGrid),
          ),
          _StepTile(
            index: 3,
            title: '坐标系与末端偏移拟合',
            subtitle: '仅拟合坐标系/TCP 等效偏移，不修改 cfg',
            active: selectedStage == _CalibrationStage.coordinateFit,
            done: controller.latestStage4Result != null,
            onTap: () => onSelect(_CalibrationStage.coordinateFit),
          ),
          _StepTile(
            index: 4,
            title: '机构参数拟合（可选）',
            subtitle: '后续再拟合半径、高度、臂长与归零角偏置',
            active: selectedStage == _CalibrationStage.mechanismFit,
            done: false,
            onTap: () => onSelect(_CalibrationStage.mechanismFit),
          ),
          if (controller.busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 3),
          ],
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  final ParameterCalibrationController controller;
  final TextEditingController workspaceCtrl;
  final TextEditingController pythonCtrl;
  final TextEditingController moonrakerCtrl;
  final TextEditingController snapshotCtrl;
  final TextEditingController intrinsicsCtrl;

  const _ConnectionCard({
    required this.controller,
    required this.workspaceCtrl,
    required this.pythonCtrl,
    required this.moonrakerCtrl,
    required this.snapshotCtrl,
    required this.intrinsicsCtrl,
  });

  Future<void> _pickIntrinsicsFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择相机内参 JSON 文件',
      type: FileType.custom,
      allowedExtensions: ['json', 'JSON'],
    );
    final path = result?.files.single.path;
    if (path == null || path.trim().isEmpty) return;
    intrinsicsCtrl.text = path;
    controller.setIntrinsicsPath(path);
  }

  @override
  Widget build(BuildContext context) {
    return FluiddCard(
      title: '连接与路径',
      scrollable: false,
      actions: [
        Tooltip(
          message: '使用相机预览中的截图地址',
          child: IconButton(
            icon: const Icon(Icons.link, size: 20, color: Colors.grey),
            onPressed: controller.busy
                ? null
                : () {
                    final camera = context.read<CameraViewerController>();
                    controller.setSnapshotUrl('${camera.baseUrl}/snapshot');
                  },
          ),
        ),
      ],
      child: Column(
        children: [
          _TextSetting(
            label: '工作区路径',
            controller: workspaceCtrl,
            onSubmit: controller.setWorkspacePath,
          ),
          const SizedBox(height: 10),
          _TextSetting(
            label: 'Python 解释器',
            controller: pythonCtrl,
            onSubmit: controller.setPythonExecutable,
          ),
          const SizedBox(height: 10),
          _TextSetting(
            label: 'Moonraker 地址',
            controller: moonrakerCtrl,
            onSubmit: controller.setMoonrakerUrl,
          ),
          const SizedBox(height: 10),
          _TextSetting(
            label: '截图地址',
            controller: snapshotCtrl,
            onSubmit: controller.setSnapshotUrl,
          ),
          const SizedBox(height: 10),
          _TextSetting(
            label: '相机内参 JSON',
            controller: intrinsicsCtrl,
            onSubmit: controller.setIntrinsicsPath,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '选择文件',
                  icon: const Icon(
                    Icons.folder_open_outlined,
                    color: Colors.grey,
                    size: 18,
                  ),
                  onPressed: controller.busy ? null : _pickIntrinsicsFile,
                ),
                IconButton(
                  tooltip: '恢复默认内参路径',
                  icon: const Icon(
                    Icons.restore_outlined,
                    color: Colors.blue,
                    size: 18,
                  ),
                  onPressed: controller.busy
                      ? null
                      : () {
                          controller.resetIntrinsicsPath();
                          intrinsicsCtrl.text =
                              controller.defaultIntrinsicsPath;
                        },
                ),
                IconButton(
                  tooltip: '应用',
                  icon: const Icon(Icons.check, color: Colors.blue, size: 18),
                  onPressed: controller.busy
                      ? null
                      : () => controller.setIntrinsicsPath(intrinsicsCtrl.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StageActionCard extends StatelessWidget {
  final _CalibrationStage stage;
  final ParameterCalibrationController controller;
  final Future<void> Function(
    BuildContext context,
    Future<void> Function() action,
  )
  runAction;

  const _StageActionCard({
    required this.stage,
    required this.controller,
    required this.runAction,
  });

  @override
  Widget build(BuildContext context) {
    return switch (stage) {
      _CalibrationStage.charuco => _CharucoStageCard(
        controller: controller,
        runAction: runAction,
      ),
      _CalibrationStage.machineFrame => _MachineFrameStageCard(
        controller: controller,
        runAction: runAction,
      ),
      _CalibrationStage.errorGrid => _ErrorGridStageCard(
        controller: controller,
        runAction: runAction,
      ),
      _CalibrationStage.coordinateFit => _CoordinateFitStageCard(
        controller: controller,
        runAction: runAction,
      ),
      _CalibrationStage.mechanismFit => const _ComingSoonCard(
        title: '机构参数拟合（可选）',
        body: '第5阶段会使用采样误差和电机角度记录，离线拟合 Klipper 机构参数。',
      ),
    };
  }
}

class _CharucoStageCard extends StatelessWidget {
  final ParameterCalibrationController controller;
  final Future<void> Function(
    BuildContext context,
    Future<void> Function() action,
  )
  runAction;

  const _CharucoStageCard({required this.controller, required this.runAction});

  @override
  Widget build(BuildContext context) {
    return FluiddCard(
      title: '床面 ChArUco 外参',
      subtitle: '坐标原点使用 ChArUco 板中心',
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _DoubleTextSetting(
                  label: '避让 X',
                  value: controller.charucoClearX,
                  suffix: 'mm',
                  onChanged: controller.setCharucoClearX,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DoubleTextSetting(
                  label: '避让 Y',
                  value: controller.charucoClearY,
                  suffix: 'mm',
                  onChanged: controller.setCharucoClearY,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DoubleTextSetting(
                  label: '避让 Z',
                  value: controller.charucoClearZ,
                  suffix: 'mm',
                  onChanged: controller.setCharucoClearZ,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: controller.busy
                    ? null
                    : () => runAction(
                        context,
                        () =>
                            controller.moveToCharucoClearPose(homeFirst: false),
                      ),
                icon: const Icon(Icons.open_with, size: 18),
                label: const Text('移动到避让位'),
              ),
              FilledButton.tonalIcon(
                onPressed: controller.busy
                    ? null
                    : () => runAction(
                        context,
                        () =>
                            controller.moveToCharucoClearPose(homeFirst: true),
                      ),
                icon: const Icon(Icons.home_outlined, size: 18),
                label: const Text('回零并避让'),
              ),
              OutlinedButton.icon(
                onPressed: controller.busy ? null : controller.loadLatestResult,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('读取外参结果'),
              ),
              OutlinedButton.icon(
                onPressed: controller.busy ? controller.stopCurrentTask : null,
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('停止'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MachineFrameStageCard extends StatelessWidget {
  final ParameterCalibrationController controller;
  final Future<void> Function(
    BuildContext context,
    Future<void> Function() action,
  )
  runAction;

  const _MachineFrameStageCard({
    required this.controller,
    required this.runAction,
  });

  @override
  Widget build(BuildContext context) {
    return FluiddCard(
      title: '机械坐标系对齐',
      subtitle: '采集平台 AprilTag，估计机器坐标到床面坐标',
      scrollable: false,
      child: Column(
        children: [
          _NumberSetting(
            label: '安全 Z',
            value: controller.zsafe,
            suffix: 'mm',
            min: 20,
            max: 160,
            onChanged: controller.setZsafe,
          ),
          _NumberSetting(
            label: 'XY 位移',
            value: controller.moveDistance,
            suffix: 'mm',
            min: 5,
            max: 80,
            onChanged: controller.setMoveDistance,
          ),
          _NumberSetting(
            label: '移动速度',
            value: controller.feedrate,
            suffix: 'mm/min',
            min: 300,
            max: 9000,
            divisions: 87,
            onChanged: controller.setFeedrate,
          ),
          _NumberSetting(
            label: '稳定等待',
            value: controller.settleSeconds,
            suffix: 's',
            min: 0,
            max: 5,
            divisions: 50,
            onChanged: controller.setSettleSeconds,
          ),
          _NumberSetting(
            label: '标签边长',
            value: controller.tagSize,
            suffix: 'mm',
            min: 5,
            max: 120,
            onChanged: controller.setTagSize,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _SmallStepper(
                  label: '重复次数',
                  value: controller.repeats,
                  onChanged: controller.setRepeats,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SmallStepper(
                  label: '标签 ID',
                  value: controller.tagId,
                  allowNegative: false,
                  onChanged: controller.setTagId,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            value: controller.homeAndClear,
            onChanged: controller.busy ? null : controller.setHomeAndClear,
            dense: true,
            contentPadding: EdgeInsets.zero,
            activeThumbColor: Colors.blue,
            title: const Text(
              '采集前执行回零并清除 EMM 角度',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: controller.busy
                    ? null
                    : () => runAction(context, controller.dryRunStage0),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('预演'),
              ),
              FilledButton.icon(
                onPressed: controller.busy
                    ? null
                    : () => runAction(context, controller.collectStage0),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('采集第0阶段'),
              ),
              FilledButton.tonalIcon(
                onPressed: controller.busy
                    ? null
                    : () => runAction(context, controller.estimateStage0),
                icon: const Icon(Icons.functions, size: 18),
                label: const Text('仅重新估计'),
              ),
              OutlinedButton.icon(
                onPressed: controller.busy ? controller.stopCurrentTask : null,
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('停止'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorGridStageCard extends StatelessWidget {
  final ParameterCalibrationController controller;
  final Future<void> Function(
    BuildContext context,
    Future<void> Function() action,
  )
  runAction;

  const _ErrorGridStageCard({
    required this.controller,
    required this.runAction,
  });

  @override
  Widget build(BuildContext context) {
    return FluiddCard(
      title: '误差采样网格',
      subtitle: '按 Z 分层采集 XY 平面视觉误差和 EMM 角度',
      scrollable: false,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _DoubleTextSetting(
                  label: 'X 最小',
                  value: controller.stage2XMin,
                  suffix: 'mm',
                  onChanged: controller.setStage2XMin,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DoubleTextSetting(
                  label: 'X 最大',
                  value: controller.stage2XMax,
                  suffix: 'mm',
                  onChanged: controller.setStage2XMax,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _DoubleTextSetting(
                  label: 'Y 最小',
                  value: controller.stage2YMin,
                  suffix: 'mm',
                  onChanged: controller.setStage2YMin,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DoubleTextSetting(
                  label: 'Y 最大',
                  value: controller.stage2YMax,
                  suffix: 'mm',
                  onChanged: controller.setStage2YMax,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SmallStepper(
                  label: 'X 点数',
                  value: controller.stage2XCount,
                  allowNegative: false,
                  onChanged: controller.setStage2XCount,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SmallStepper(
                  label: 'Y 点数',
                  value: controller.stage2YCount,
                  allowNegative: false,
                  onChanged: controller.setStage2YCount,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _StringTextSetting(
            label: 'Z 分层',
            value: controller.stage2ZLevels,
            suffix: 'mm',
            onSubmitted: controller.setStage2ZLevels,
          ),
          const SizedBox(height: 10),
          _StringTextSetting(
            label: '传动比',
            value: controller.gearRatio,
            suffix: '驱动:大臂',
            onSubmitted: controller.setGearRatio,
          ),
          _NumberSetting(
            label: '移动速度',
            value: controller.feedrate,
            suffix: 'mm/min',
            min: 300,
            max: 9000,
            divisions: 87,
            onChanged: controller.setFeedrate,
          ),
          _NumberSetting(
            label: '稳定等待',
            value: controller.settleSeconds,
            suffix: 's',
            min: 0,
            max: 5,
            divisions: 50,
            onChanged: controller.setSettleSeconds,
          ),
          _NumberSetting(
            label: '标签边长',
            value: controller.tagSize,
            suffix: 'mm',
            min: 5,
            max: 120,
            onChanged: controller.setTagSize,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _SmallStepper(
                  label: '重复次数',
                  value: controller.repeats,
                  onChanged: controller.setRepeats,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SmallStepper(
                  label: '标签 ID',
                  value: controller.tagId,
                  allowNegative: false,
                  onChanged: controller.setTagId,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            value: controller.homeAndClear,
            onChanged: controller.busy ? null : controller.setHomeAndClear,
            dense: true,
            contentPadding: EdgeInsets.zero,
            activeThumbColor: Colors.blue,
            title: const Text(
              '采集前执行回零并清除 EMM 角度',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: controller.busy
                    ? null
                    : () => runAction(context, controller.dryRunStage2),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('预演'),
              ),
              FilledButton.icon(
                onPressed: controller.busy
                    ? null
                    : () => runAction(context, controller.collectStage2),
                icon: const Icon(Icons.grid_on, size: 18),
                label: const Text('采集第2阶段'),
              ),
              FilledButton.tonalIcon(
                onPressed: controller.busy
                    ? null
                    : () => runAction(context, controller.summarizeStage2),
                icon: const Icon(Icons.analytics_outlined, size: 18),
                label: const Text('重生成结果'),
              ),
              OutlinedButton.icon(
                onPressed: controller.busy ? controller.stopCurrentTask : null,
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('停止'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoordinateFitStageCard extends StatelessWidget {
  final ParameterCalibrationController controller;
  final Future<void> Function(
    BuildContext context,
    Future<void> Function() action,
  )
  runAction;

  const _CoordinateFitStageCard({
    required this.controller,
    required this.runAction,
  });

  @override
  Widget build(BuildContext context) {
    return FluiddCard(
      title: '坐标系与末端偏移拟合',
      subtitle: '使用第2阶段采样，不修改 cfg 机械参数',
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ChoiceRow(
            label: 'XY 模型',
            options: const <String, String>{'rigid': '刚体', 'affine': '仿射'},
            value: controller.stage4XyModel,
            enabled: !controller.busy,
            onChanged: controller.setStage4XyModel,
          ),
          const SizedBox(height: 10),
          _ChoiceRow(
            label: 'Z 模型',
            options: const <String, String>{
              'offset': '偏置',
              'plane': '平面',
              'none': '不拟合',
            },
            value: controller.stage4ZModel,
            enabled: !controller.busy,
            onChanged: controller.setStage4ZModel,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SmallStepper(
                  label: '未标定 X 点数',
                  value: controller.stage4HoldoutXCount,
                  allowNegative: false,
                  onChanged: controller.setStage4HoldoutXCount,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SmallStepper(
                  label: '未标定 Y 点数',
                  value: controller.stage4HoldoutYCount,
                  allowNegative: false,
                  onChanged: controller.setStage4HoldoutYCount,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _StringTextSetting(
            label: '未标定 Z 分层',
            value: controller.stage4HoldoutZLevels,
            suffix: 'mm',
            onSubmitted: controller.setStage4HoldoutZLevels,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: controller.busy
                    ? null
                    : () => runAction(context, controller.fitStage4Coordinate),
                icon: const Icon(Icons.functions, size: 18),
                label: const Text('执行第4阶段拟合'),
              ),
              OutlinedButton.icon(
                onPressed: controller.busy
                    ? null
                    : () =>
                          runAction(context, controller.dryRunStage4Validation),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('预演验证网格'),
              ),
              FilledButton.tonalIcon(
                onPressed: controller.busy
                    ? null
                    : () => runAction(
                        context,
                        controller.collectStage4Validation,
                      ),
                icon: const Icon(Icons.grid_on, size: 18),
                label: const Text('采集验证网格'),
              ),
              OutlinedButton.icon(
                onPressed: controller.busy
                    ? null
                    : () => runAction(
                        context,
                        controller.summarizeStage4Validation,
                      ),
                icon: const Icon(Icons.analytics_outlined, size: 18),
                label: const Text('重算验证结果'),
              ),
              OutlinedButton.icon(
                onPressed: controller.busy
                    ? null
                    : () => runAction(
                        context,
                        controller.dryRunStage4HoldoutValidation,
                      ),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('预演未标定平面'),
              ),
              FilledButton.tonalIcon(
                onPressed: controller.busy
                    ? null
                    : () => runAction(
                        context,
                        controller.collectStage4HoldoutValidation,
                      ),
                icon: const Icon(Icons.layers_outlined, size: 18),
                label: const Text('采集未标定平面'),
              ),
              OutlinedButton.icon(
                onPressed: controller.busy
                    ? null
                    : () => runAction(
                        context,
                        controller.summarizeStage4HoldoutValidation,
                      ),
                icon: const Icon(Icons.analytics_outlined, size: 18),
                label: const Text('重算未标定结果'),
              ),
              OutlinedButton.icon(
                onPressed: controller.busy ? null : controller.loadLatestResult,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('读取拟合结果'),
              ),
              OutlinedButton.icon(
                onPressed: controller.busy ? controller.stopCurrentTask : null,
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('停止'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComingSoonCard extends StatelessWidget {
  final String title;
  final String body;

  const _ComingSoonCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return FluiddCard(
      title: title,
      scrollable: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(body, style: const TextStyle(color: Colors.white60)),
      ),
    );
  }
}

class _StageResultCard extends StatelessWidget {
  final _CalibrationStage stage;
  final ParameterCalibrationController controller;

  const _StageResultCard({required this.stage, required this.controller});

  @override
  Widget build(BuildContext context) {
    return switch (stage) {
      _CalibrationStage.charuco => _CharucoResultCard(controller: controller),
      _CalibrationStage.machineFrame => _MachineFrameResultCard(
        controller: controller,
      ),
      _CalibrationStage.errorGrid => _ErrorGridResultCard(
        controller: controller,
      ),
      _CalibrationStage.coordinateFit => _CoordinateFitResultCard(
        controller: controller,
      ),
      _CalibrationStage.mechanismFit => const _EmptyResultCard(
        title: '机构参数拟合结果',
      ),
    };
  }
}

class _CharucoResultCard extends StatelessWidget {
  final ParameterCalibrationController controller;

  const _CharucoResultCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final result = controller.latestCharucoResult;
    return FluiddCard(
      title: '床面 ChArUco 结果',
      subtitle: controller.latestCharucoResultPath == null ? '无结果' : '最新',
      scrollable: false,
      child: result == null
          ? const SizedBox(
              height: 96,
              child: Center(
                child: Text(
                  '尚未读取到 ChArUco 外参结果',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetricTile(
                      label: '均值重投影',
                      value: _fmt(
                        result['mean_reprojection_error_px'] ??
                            result['mean_error_px'],
                      ),
                      unit: 'px',
                      color: Colors.blueAccent,
                    ),
                    _MetricTile(
                      label: '最大重投影',
                      value: _fmt(
                        result['max_reprojection_error_px'] ??
                            result['max_error_px'],
                      ),
                      unit: 'px',
                      color: Colors.orangeAccent,
                    ),
                    _MetricTile(
                      label: '方格尺寸',
                      value: _fmt(result['square_length_mm']),
                      unit: 'mm',
                      color: Colors.greenAccent,
                    ),
                    _MetricTile(
                      label: '识别角点',
                      value: '${result['charuco_corners'] ?? '--'}',
                      unit: '个',
                      color: Colors.purpleAccent,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _PathLine(
                  label: '结果',
                  path: controller.latestCharucoResultPath,
                ),
                _PathLine(
                  label: '叠加图',
                  path: controller.latestCharucoOverlayPath,
                ),
                const SizedBox(height: 14),
                if (controller.latestCharucoOverlayPath != null)
                  _ImagePreview(
                    path: controller.latestCharucoOverlayPath!,
                    label: '实拍 ChArUco 坐标标注图',
                  ),
              ],
            ),
    );
  }
}

class _MachineFrameResultCard extends StatelessWidget {
  final ParameterCalibrationController controller;

  const _MachineFrameResultCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final result = controller.latestResult;
    final residuals = (result?['residuals'] as List?) ?? const [];
    return FluiddCard(
      title: '机械坐标系对齐结果',
      subtitle: controller.latestResultPath == null ? '无结果' : '最新',
      scrollable: false,
      child: result == null
          ? const SizedBox(
              height: 96,
              child: Center(
                child: Text(
                  '尚未读取到机械坐标系对齐结果',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetricTile(
                      label: 'yaw',
                      value: _fmt(result['yaw_deg']),
                      unit: '度',
                      color: Colors.blueAccent,
                    ),
                    _MetricTile(
                      label: 'tx',
                      value: _fmt(result['tx_mm']),
                      unit: 'mm',
                      color: Colors.greenAccent,
                    ),
                    _MetricTile(
                      label: 'ty',
                      value: _fmt(result['ty_mm']),
                      unit: 'mm',
                      color: Colors.greenAccent,
                    ),
                    _MetricTile(
                      label: 'tz',
                      value: _fmt(result['tz_mm']),
                      unit: 'mm',
                      color: Colors.orangeAccent,
                    ),
                    _MetricTile(
                      label: 'RMS',
                      value: _fmt(result['rms_error_mm']),
                      unit: 'mm',
                      color: Colors.purpleAccent,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _PathLine(label: '结果', path: controller.latestResultPath),
                _PathLine(label: '采样', path: controller.latestSamplesPath),
                _PathLine(
                  label: 'XY 类型',
                  path:
                      '${result['xy_transform'] ?? '--'} / ${result['xy_handedness'] ?? '--'}',
                ),
                _PathLine(
                  label: '轴映射',
                  path: _joinList(result['machine_to_board_axis_mapping']),
                ),
                const SizedBox(height: 14),
                if (controller.latestPhotoOverlayPath != null) ...[
                  _ImagePreview(
                    path: controller.latestPhotoOverlayPath!,
                    label: '实拍坐标标注图',
                  ),
                  const SizedBox(height: 14),
                ],
                if (controller.latestSummaryPath != null) ...[
                  _ImagePreview(
                    path: controller.latestSummaryPath!,
                    label: '平面坐标误差图',
                  ),
                  const SizedBox(height: 14),
                ],
                if (controller.latestOverlayPath != null)
                  _ImagePreview(
                    path: controller.latestOverlayPath!,
                    label: '最近抓拍识别图',
                  ),
                if (residuals.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _ResidualTable(residuals: residuals),
                ],
              ],
            ),
    );
  }
}

class _ErrorGridResultCard extends StatelessWidget {
  final ParameterCalibrationController controller;

  const _ErrorGridResultCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final result = controller.latestStage2Result;
    final layers = (result?['layer_stats'] as List?) ?? const [];
    return FluiddCard(
      title: '误差采样结果',
      subtitle: controller.latestStage2ResultPath == null ? '无结果' : '最新',
      scrollable: false,
      child: result == null
          ? const SizedBox(
              height: 96,
              child: Center(
                child: Text(
                  '尚未读取到第2阶段误差采样结果',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetricTile(
                      label: '有效样本',
                      value: '${result['valid_sample_count'] ?? '--'}',
                      unit: '/ ${result['sample_count'] ?? '--'}',
                      color: Colors.blueAccent,
                    ),
                    _MetricTile(
                      label: 'RMS XY',
                      value: _fmt(result['rms_xy_error_mm']),
                      unit: 'mm',
                      color: Colors.greenAccent,
                    ),
                    _MetricTile(
                      label: '最大 XY',
                      value: _fmt(result['max_xy_error_mm']),
                      unit: 'mm',
                      color: Colors.orangeAccent,
                    ),
                    _MetricTile(
                      label: '平均 Z 误差',
                      value: _fmt(result['mean_z_error_mm']),
                      unit: 'mm',
                      color: Colors.purpleAccent,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _PathLine(label: '结果', path: controller.latestStage2ResultPath),
                _PathLine(
                  label: '采样',
                  path: controller.latestStage2SamplesPath,
                ),
                _PathLine(
                  label: 'Z 分层',
                  path: _joinList(result['z_levels_mm']),
                ),
                const SizedBox(height: 14),
                if (controller.latestStage2SummaryPath != null) ...[
                  _ImagePreview(
                    path: controller.latestStage2SummaryPath!,
                    label: 'XY 分层误差图',
                  ),
                  const SizedBox(height: 14),
                ],
                if (controller.latestStage2ContactSheetPath != null) ...[
                  _ImagePreview(
                    path: controller.latestStage2ContactSheetPath!,
                    label: '采样照片接触表',
                  ),
                  const SizedBox(height: 14),
                ],
                if (controller.latestStage2OverlayPath != null)
                  _ImagePreview(
                    path: controller.latestStage2OverlayPath!,
                    label: '最近抓拍识别图',
                  ),
                if (layers.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _LayerStatsTable(layers: layers),
                ],
              ],
            ),
    );
  }
}

class _CoordinateFitResultCard extends StatelessWidget {
  final ParameterCalibrationController controller;

  const _CoordinateFitResultCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final result = controller.latestStage4Result;
    final initialStats =
        (result?['initial_stats'] as Map?) ?? const <String, dynamic>{};
    final fittedStats =
        (result?['fitted_stats'] as Map?) ?? const <String, dynamic>{};
    final improvement =
        (result?['improvement'] as Map?) ?? const <String, dynamic>{};
    final residuals = (result?['residuals'] as List?) ?? const [];
    final validation = controller.latestStage4ValidationResult;
    final validationLayers = (validation?['layer_stats'] as List?) ?? const [];
    final holdout = controller.latestStage4HoldoutResult;
    final holdoutLayers = (holdout?['layer_stats'] as List?) ?? const [];
    return FluiddCard(
      title: '坐标系拟合结果',
      subtitle: controller.latestStage4ResultPath == null ? '无结果' : '最新',
      scrollable: false,
      child: result == null
          ? const SizedBox(
              height: 96,
              child: Center(
                child: Text(
                  '尚未读取到第4阶段坐标系拟合结果',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetricTile(
                      label: '拟合前 RMS XY',
                      value: _fmt(initialStats['rms_xy_error_mm']),
                      unit: 'mm',
                      color: Colors.orangeAccent,
                    ),
                    _MetricTile(
                      label: '拟合后 RMS XY',
                      value: _fmt(fittedStats['rms_xy_error_mm']),
                      unit: 'mm',
                      color: Colors.greenAccent,
                    ),
                    _MetricTile(
                      label: '改善',
                      value: _fmt(improvement['rms_xy_reduction_percent']),
                      unit: '%',
                      color: Colors.blueAccent,
                    ),
                    _MetricTile(
                      label: '样本',
                      value: '${result['valid_sample_count'] ?? '--'}',
                      unit: '个',
                      color: Colors.purpleAccent,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _PathLine(label: '结果', path: controller.latestStage4ResultPath),
                _PathLine(
                  label: '采样',
                  path: controller.latestStage2SamplesPath,
                ),
                _PathLine(
                  label: '模型',
                  path:
                      '${result['xy_model'] ?? '--'} / ${result['z_model'] ?? '--'}',
                ),
                _PathLine(
                  label: 'TCP 等效偏移',
                  path: _joinList(
                    result['equivalent_tcp_offset_from_initial_mm'],
                  ),
                ),
                const SizedBox(height: 14),
                if (controller.latestStage4SummaryPath != null) ...[
                  _ImagePreview(
                    path: controller.latestStage4SummaryPath!,
                    label: '拟合前后 XY 残差图',
                  ),
                  const SizedBox(height: 14),
                ],
                if (residuals.isNotEmpty) _ResidualTable(residuals: residuals),
                if (validation != null) ...[
                  const SizedBox(height: 14),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MetricTile(
                        label: '验证有效样本',
                        value: '${validation['valid_sample_count'] ?? '--'}',
                        unit: '/ ${validation['sample_count'] ?? '--'}',
                        color: Colors.blueAccent,
                      ),
                      _MetricTile(
                        label: '验证 RMS XY',
                        value: _fmt(validation['rms_xy_error_mm']),
                        unit: 'mm',
                        color: Colors.greenAccent,
                      ),
                      _MetricTile(
                        label: '验证最大 XY',
                        value: _fmt(validation['max_xy_error_mm']),
                        unit: 'mm',
                        color: Colors.orangeAccent,
                      ),
                      _MetricTile(
                        label: '预测 RMS XY',
                        value: _fmt(fittedStats['rms_xy_error_mm']),
                        unit: 'mm',
                        color: Colors.purpleAccent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _PathLine(
                    label: '验证结果',
                    path: controller.latestStage4ValidationResultPath,
                  ),
                  _PathLine(
                    label: '验证采样',
                    path: controller.latestStage4ValidationSamplesPath,
                  ),
                  if (controller.latestStage4ValidationSummaryPath != null) ...[
                    const SizedBox(height: 14),
                    _ImagePreview(
                      path: controller.latestStage4ValidationSummaryPath!,
                      label: '仿射结果验证网格误差图',
                    ),
                  ],
                  if (controller.latestStage4ValidationContactSheetPath !=
                      null) ...[
                    const SizedBox(height: 14),
                    _ImagePreview(
                      path: controller.latestStage4ValidationContactSheetPath!,
                      label: '验证采样照片接触表',
                    ),
                  ],
                  if (validationLayers.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _LayerStatsTable(layers: validationLayers),
                  ],
                ],
                if (holdout != null) ...[
                  const SizedBox(height: 14),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MetricTile(
                        label: '未标定有效样本',
                        value: '${holdout['valid_sample_count'] ?? '--'}',
                        unit: '/ ${holdout['sample_count'] ?? '--'}',
                        color: Colors.blueAccent,
                      ),
                      _MetricTile(
                        label: '未标定 RMS XY',
                        value: _fmt(holdout['rms_xy_error_mm']),
                        unit: 'mm',
                        color: Colors.greenAccent,
                      ),
                      _MetricTile(
                        label: '未标定最大 XY',
                        value: _fmt(holdout['max_xy_error_mm']),
                        unit: 'mm',
                        color: Colors.orangeAccent,
                      ),
                      _MetricTile(
                        label: '预测 RMS XY',
                        value: _fmt(fittedStats['rms_xy_error_mm']),
                        unit: 'mm',
                        color: Colors.purpleAccent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _PathLine(
                    label: '未标定结果',
                    path: controller.latestStage4HoldoutResultPath,
                  ),
                  _PathLine(
                    label: '未标定采样',
                    path: controller.latestStage4HoldoutSamplesPath,
                  ),
                  _PathLine(
                    label: '未标定 Z 分层',
                    path: _joinList(holdout['z_levels_mm']),
                  ),
                  if (controller.latestStage4HoldoutSummaryPath != null) ...[
                    const SizedBox(height: 14),
                    _ImagePreview(
                      path: controller.latestStage4HoldoutSummaryPath!,
                      label: '未标定平面验证误差图',
                    ),
                  ],
                  if (controller.latestStage4HoldoutContactSheetPath !=
                      null) ...[
                    const SizedBox(height: 14),
                    _ImagePreview(
                      path: controller.latestStage4HoldoutContactSheetPath!,
                      label: '未标定平面采样照片接触表',
                    ),
                  ],
                  if (controller.latestStage4HoldoutOverlayPath != null) ...[
                    const SizedBox(height: 14),
                    _ImagePreview(
                      path: controller.latestStage4HoldoutOverlayPath!,
                      label: '未标定平面最近识别图',
                    ),
                  ],
                  if (holdoutLayers.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _LayerStatsTable(layers: holdoutLayers),
                  ],
                ],
              ],
            ),
    );
  }
}

class _EmptyResultCard extends StatelessWidget {
  final String title;

  const _EmptyResultCard({required this.title});

  @override
  Widget build(BuildContext context) {
    return FluiddCard(
      title: title,
      scrollable: false,
      child: const SizedBox(
        height: 96,
        child: Center(
          child: Text('该阶段尚未生成结果', style: TextStyle(color: Colors.white54)),
        ),
      ),
    );
  }
}

class _ArtifactCard extends StatelessWidget {
  final ParameterCalibrationController controller;
  final _CalibrationStage stage;

  const _ArtifactCard({required this.controller, required this.stage});

  @override
  Widget build(BuildContext context) {
    return FluiddCard(
      title: '产物文件',
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PathLine(label: 'Moonraker', path: controller.moonrakerUrl),
          _PathLine(label: '相机', path: controller.snapshotUrl),
          if (stage == _CalibrationStage.charuco) ...[
            _PathLine(label: '外参', path: controller.latestCharucoResultPath),
            _PathLine(label: '叠加图', path: controller.latestCharucoOverlayPath),
          ] else if (stage == _CalibrationStage.machineFrame) ...[
            _PathLine(label: '实拍图', path: controller.latestPhotoOverlayPath),
            _PathLine(label: '误差图', path: controller.latestSummaryPath),
            _PathLine(label: '结果', path: controller.latestResultPath),
            _PathLine(label: '采样', path: controller.latestSamplesPath),
          ] else if (stage == _CalibrationStage.errorGrid) ...[
            _PathLine(label: '误差图', path: controller.latestStage2SummaryPath),
            _PathLine(
              label: '接触表',
              path: controller.latestStage2ContactSheetPath,
            ),
            _PathLine(label: '识别图', path: controller.latestStage2OverlayPath),
            _PathLine(label: '结果', path: controller.latestStage2ResultPath),
            _PathLine(label: '采样', path: controller.latestStage2SamplesPath),
          ] else if (stage == _CalibrationStage.coordinateFit) ...[
            _PathLine(label: '拟合图', path: controller.latestStage4SummaryPath),
            _PathLine(label: '结果', path: controller.latestStage4ResultPath),
            _PathLine(label: '采样', path: controller.latestStage2SamplesPath),
            _PathLine(
              label: '验证图',
              path: controller.latestStage4ValidationSummaryPath,
            ),
            _PathLine(
              label: '验证结果',
              path: controller.latestStage4ValidationResultPath,
            ),
            _PathLine(
              label: '验证采样',
              path: controller.latestStage4ValidationSamplesPath,
            ),
            _PathLine(
              label: '验证识别',
              path: controller.latestStage4ValidationOverlayPath,
            ),
            _PathLine(
              label: '未标定验证图',
              path: controller.latestStage4HoldoutSummaryPath,
            ),
            _PathLine(
              label: '未标定结果',
              path: controller.latestStage4HoldoutResultPath,
            ),
            _PathLine(
              label: '未标定采样',
              path: controller.latestStage4HoldoutSamplesPath,
            ),
            _PathLine(
              label: '未标定识别',
              path: controller.latestStage4HoldoutOverlayPath,
            ),
          ],
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  final ParameterCalibrationController controller;

  const _LogCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final lines = controller.logLines;
    return FluiddCard(
      title: '运行日志',
      subtitle: controller.lastExitCode == null
          ? null
          : '退出码 ${controller.lastExitCode}',
      actions: [
        IconButton(
          tooltip: '清空日志',
          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
          onPressed: controller.clearLog,
        ),
      ],
      scrollable: false,
      child: Container(
        height: 260,
        decoration: BoxDecoration(
          color: const Color(0xFF101316),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white12),
        ),
        padding: const EdgeInsets.all(12),
        child: lines.isEmpty
            ? const Center(
                child: Text(
                  '运行输出会显示在这里',
                  style: TextStyle(color: Colors.white38),
                ),
              )
            : SingleChildScrollView(
                reverse: true,
                child: SelectableText(
                  lines.join('\n'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontFamily: 'monospace',
                    height: 1.35,
                  ),
                ),
              ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final int index;
  final String title;
  final String subtitle;
  final bool active;
  final bool done;
  final VoidCallback onTap;

  const _StepTile({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.done,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = done
        ? Colors.greenAccent
        : active
        ? Colors.blueAccent
        : Colors.white24;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.45)),
              color: color.withValues(alpha: active ? 0.10 : 0.05),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: color.withValues(alpha: 0.18),
                  child: done
                      ? Icon(Icons.check, color: color, size: 17)
                      : Text(
                          '$index',
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TextSetting extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final Widget? suffixIcon;

  const _TextSetting({
    required this.label,
    required this.controller,
    required this.onSubmit,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        isDense: true,
        border: const OutlineInputBorder(),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white12),
        ),
        suffixIcon:
            suffixIcon ??
            IconButton(
              tooltip: '应用',
              icon: const Icon(Icons.check, color: Colors.blue, size: 18),
              onPressed: () => onSubmit(controller.text),
            ),
      ),
      onSubmitted: onSubmit,
      onTapOutside: (_) => onSubmit(controller.text),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  final String label;
  final Map<String, String> options;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _ChoiceRow({
    required this.label,
    required this.options,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.entries.map((entry) {
              return ChoiceChip(
                label: Text(entry.value),
                selected: value == entry.key,
                onSelected: enabled ? (_) => onChanged(entry.key) : null,
                selectedColor: Colors.blue.withValues(alpha: 0.22),
                backgroundColor: const Color(0xFF171B20),
                side: BorderSide(
                  color: value == entry.key
                      ? Colors.blueAccent
                      : Colors.white12,
                ),
                labelStyle: TextStyle(
                  color: value == entry.key ? Colors.white : Colors.white60,
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _DoubleTextSetting extends StatefulWidget {
  final String label;
  final double value;
  final String suffix;
  final ValueChanged<double> onChanged;

  const _DoubleTextSetting({
    required this.label,
    required this.value,
    required this.suffix,
    required this.onChanged,
  });

  @override
  State<_DoubleTextSetting> createState() => _DoubleTextSettingState();
}

class _DoubleTextSettingState extends State<_DoubleTextSetting> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
  }

  @override
  void didUpdateWidget(covariant _DoubleTextSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_controller.selection.isValid) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_controller.text.trim());
    if (value == null) {
      _controller.text = _format(widget.value);
      return;
    }
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: widget.suffix,
        labelStyle: const TextStyle(color: Colors.white54),
        suffixStyle: const TextStyle(color: Colors.white38),
        isDense: true,
        border: const OutlineInputBorder(),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white12),
        ),
      ),
      onSubmitted: (_) => _submit(),
      onTapOutside: (_) => _submit(),
    );
  }

  static String _format(double value) => value.toStringAsFixed(3);
}

class _StringTextSetting extends StatefulWidget {
  final String label;
  final String value;
  final String suffix;
  final ValueChanged<String> onSubmitted;

  const _StringTextSetting({
    required this.label,
    required this.value,
    required this.suffix,
    required this.onSubmitted,
  });

  @override
  State<_StringTextSetting> createState() => _StringTextSettingState();
}

class _StringTextSettingState extends State<_StringTextSetting> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _StringTextSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_controller.selection.isValid) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => widget.onSubmitted(_controller.text);

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: widget.suffix,
        labelStyle: const TextStyle(color: Colors.white54),
        suffixStyle: const TextStyle(color: Colors.white38),
        isDense: true,
        border: const OutlineInputBorder(),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white12),
        ),
      ),
      onSubmitted: (_) => _submit(),
      onTapOutside: (_) => _submit(),
    );
  }
}

class _NumberSetting extends StatelessWidget {
  final String label;
  final double value;
  final String suffix;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  const _NumberSetting({
    required this.label,
    required this.value,
    required this.suffix,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions ?? (max - min).round(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 86,
          child: Text(
            '${value.toStringAsFixed(value < 10 ? 2 : 1)} $suffix',
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _SmallStepper extends StatelessWidget {
  final String label;
  final int value;
  final bool allowNegative;
  final ValueChanged<int> onChanged;

  const _SmallStepper({
    required this.label,
    required this.value,
    this.allowNegative = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white12),
        color: Colors.white.withValues(alpha: 0.04),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove, size: 16),
            onPressed: !allowNegative && value <= 0
                ? null
                : () => onChanged(value - 1),
          ),
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add, size: 16),
            onPressed: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 118,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          Text(
            unit,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _PathLine extends StatelessWidget {
  final String label;
  final String? path;

  const _PathLine({required this.label, required this.path});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
          Expanded(
            child: SelectableText(
              path ?? '--',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  final String path;
  final String label;

  const _ImagePreview({required this.path, required this.label});

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    if (!file.existsSync()) return const SizedBox.shrink();
    final stat = file.statSync();
    if (stat.size <= 0) {
      return _ImageErrorPanel(label: label, message: '图片文件为空', path: path);
    }
    late final Uint8List bytes;
    try {
      bytes = file.readAsBytesSync();
    } catch (_) {
      return _ImageErrorPanel(label: label, message: '图片暂时无法读取', path: path);
    }
    if (!_looksLikeImage(bytes)) {
      return _ImageErrorPanel(label: label, message: '图片文件头无效', path: path);
    }
    final imageKey = ValueKey(
      '$path-${stat.modified.millisecondsSinceEpoch}-${stat.size}',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF101316),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white12),
            ),
            clipBehavior: Clip.hardEdge,
            child: Image.memory(
              bytes,
              key: imageKey,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return _ImageErrorPanel(
                  label: label,
                  message: '图片解码失败，请刷新或重新生成标注图',
                  path: path,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  static bool _looksLikeImage(List<int> bytes) {
    if (bytes.length < 12) return false;
    final isPng =
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
    return isPng || isJpeg;
  }
}

class _ImageErrorPanel extends StatelessWidget {
  final String label;
  final String message;
  final String path;

  const _ImageErrorPanel({
    required this.label,
    required this.message,
    required this.path,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF101316),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined, color: Colors.orangeAccent),
            const SizedBox(height: 8),
            Text(
              '$label：$message',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 6),
            SelectableText(
              path,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResidualTable extends StatelessWidget {
  final List residuals;

  const _ResidualTable({required this.residuals});

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1),
        4: FlexColumnWidth(1),
      },
      border: TableBorder.all(color: Colors.white10),
      children: [
        _row(['点位', 'dx', 'dy', 'dz', '范数'], header: true),
        ...residuals.take(8).whereType<Map>().map((item) {
          final residual = item['residual_mm'];
          final r = residual is List ? residual : const [];
          return _row([
            '${item['name'] ?? item['sample_id'] ?? '--'}',
            _cellNum(r, 0),
            _cellNum(r, 1),
            _cellNum(r, 2),
            _num(item['residual_norm_mm']),
          ]);
        }),
      ],
    );
  }

  TableRow _row(List<String> cells, {bool header = false}) {
    return TableRow(
      decoration: BoxDecoration(
        color: header ? Colors.white.withValues(alpha: 0.06) : null,
      ),
      children: cells
          .map(
            (text) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: header ? Colors.white : Colors.white70,
                  fontSize: 11,
                  fontWeight: header ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  static String _cellNum(List values, int index) {
    if (values.length <= index) return '--';
    return _num(values[index]);
  }

  static String _num(dynamic value) {
    if (value is num) return value.toStringAsFixed(3);
    return '--';
  }
}

class _LayerStatsTable extends StatelessWidget {
  final List layers;

  const _LayerStatsTable({required this.layers});

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(1.2),
        4: FlexColumnWidth(1.2),
      },
      border: TableBorder.all(color: Colors.white10),
      children: [
        _row(['Z', '样本', 'RMS XY', '最大 XY', '平均 Z'], header: true),
        ...layers.take(8).whereType<Map>().map((item) {
          return _row([
            _num(item['z_mm']),
            '${item['valid_sample_count'] ?? '--'}',
            _num(item['rms_xy_error_mm']),
            _num(item['max_xy_error_mm']),
            _num(item['mean_z_error_mm']),
          ]);
        }),
      ],
    );
  }

  TableRow _row(List<String> cells, {bool header = false}) {
    return TableRow(
      decoration: BoxDecoration(
        color: header ? Colors.white.withValues(alpha: 0.06) : null,
      ),
      children: cells
          .map(
            (text) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: header ? Colors.white : Colors.white70,
                  fontSize: 11,
                  fontWeight: header ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  static String _num(dynamic value) {
    if (value is num) return value.toStringAsFixed(3);
    return '--';
  }
}

String _fmt(dynamic value) {
  if (value is num) return value.toStringAsFixed(4);
  return '--';
}

String _joinList(dynamic value) {
  if (value is List) return value.map((item) => '$item').join('；');
  return '--';
}
