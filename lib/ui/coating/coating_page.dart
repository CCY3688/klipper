import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/printer_controller.dart';
import '../fluidd/widgets/fluidd_card.dart';
import 'coating_motion.dart';
import 'printcart_panel.dart';

class CoatingPage extends StatefulWidget {
  const CoatingPage({super.key});

  @override
  State<CoatingPage> createState() => _CoatingPageState();
}

class _CoatingPageState extends State<CoatingPage> {
  final _xController = TextEditingController(text: '0.000');
  final _yController = TextEditingController(text: '0.000');
  final _zController = TextEditingController(text: '0.000');
  final _feedController = TextEditingController(text: '20.0');
  final _penAngleController = TextEditingController(text: '80.0');
  final _cartridgeAngleController = TextEditingController(text: '30.0');
  final _settleController = TextEditingController(text: '500');

  CoatingJointSequence _sequence = CoatingJointSequence.servoThenPlatform;
  final _servoAngles = <CoatingServo, double>{
    CoatingServo.pen: 80.0,
    CoatingServo.cartridge: 30.0,
  };
  final _lastCommandedServoAngles = <CoatingServo, double>{
    CoatingServo.pen: 80.0,
    CoatingServo.cartridge: 30.0,
  };
  bool _busy = false;
  String? _statusMessage;
  bool _statusIsError = false;
  String? _lastScript;
  DateTime? _lastExecutedAt;

  @override
  void dispose() {
    _xController.dispose();
    _yController.dispose();
    _zController.dispose();
    _feedController.dispose();
    _penAngleController.dispose();
    _cartridgeAngleController.dispose();
    _settleController.dispose();
    super.dispose();
  }

  bool _isConnected(PrinterController printer) =>
      printer.phase == AppConnPhase.connected &&
      printer.repo != null &&
      printer.klippyReady;

  CoatingMotionRequest? _readRequest(CoatingMotionMode mode) {
    final x = double.tryParse(_xController.text.trim());
    final y = double.tryParse(_yController.text.trim());
    final z = double.tryParse(_zController.text.trim());
    final feed = double.tryParse(_feedController.text.trim());
    final penAngle = double.tryParse(_penAngleController.text.trim());
    final cartridgeAngle = double.tryParse(
      _cartridgeAngleController.text.trim(),
    );
    final settle = int.tryParse(_settleController.text.trim());

    if (mode != CoatingMotionMode.servoOnly &&
        (x == null || y == null || z == null || feed == null)) {
      _setStatus('请检查 XYZ 和速度输入', isError: true);
      return null;
    }
    if (mode != CoatingMotionMode.platformOnly &&
        (penAngle == null || cartridgeAngle == null)) {
      _setStatus('请检查两个舵机角度输入', isError: true);
      return null;
    }
    if (settle == null) {
      _setStatus('请检查舵机稳定时间', isError: true);
      return null;
    }

    final request = CoatingMotionRequest(
      x: x ?? 0,
      y: y ?? 0,
      z: z ?? 0,
      feedMmPerS: feed ?? 1,
      penServoAngleDeg: penAngle ?? _servoAngles[CoatingServo.pen]!,
      cartridgeServoAngleDeg:
          cartridgeAngle ?? _servoAngles[CoatingServo.cartridge]!,
      servoSettleMs: settle,
    );
    final validationError = request.validate(mode);
    if (validationError != null) {
      _setStatus(validationError, isError: true);
      return null;
    }
    return request;
  }

  Future<void> _execute(CoatingMotionMode mode) async {
    if (_busy) return;
    final printer = context.read<PrinterController>();
    if (!_isConnected(printer)) {
      _setStatus('Moonraker 或 Klipper 未就绪', isError: true);
      return;
    }
    if (mode != CoatingMotionMode.servoOnly && !printer.isHomed) {
      _setStatus('平台尚未完成 XYZ 回零', isError: true);
      return;
    }

    final request = _readRequest(mode);
    if (request == null) return;
    final script = request.buildGcode(mode, sequence: _sequence);
    final label = switch (mode) {
      CoatingMotionMode.joint => '联合运动',
      CoatingMotionMode.platformOnly => '平台运动',
      CoatingMotionMode.servoOnly => '舵机运动',
    };
    await _runScript(
      script,
      successMessage: '$label已完成',
      commandedServos: mode == CoatingMotionMode.platformOnly
          ? null
          : CoatingServo.values.toSet(),
      refreshPosition: mode != CoatingMotionMode.servoOnly,
    );
  }

  Future<void> _runScript(
    String script, {
    required String successMessage,
    Set<CoatingServo>? commandedServos,
    bool refreshPosition = false,
  }) async {
    if (_busy) return;
    final printer = context.read<PrinterController>();
    setState(() {
      _busy = true;
      _statusMessage = '正在执行...';
      _statusIsError = false;
      _lastScript = script;
    });

    final error = await printer.sendGcode(
      script,
      receiveTimeout: const Duration(seconds: 120),
    );
    if (!mounted) return;

    if (error == null && refreshPosition) {
      await printer.refreshStatusSnapshot();
    }
    if (!mounted) return;

    setState(() {
      _busy = false;
      _lastExecutedAt = DateTime.now();
      if (error == null) {
        if (commandedServos != null) {
          for (final servo in commandedServos) {
            _lastCommandedServoAngles[servo] = _servoAngles[servo]!;
          }
        }
        _statusMessage = successMessage;
        _statusIsError = false;
      } else {
        _statusMessage = error;
        _statusIsError = true;
      }
    });
  }

  Future<void> _home() async {
    final printer = context.read<PrinterController>();
    if (!_isConnected(printer)) {
      _setStatus('Moonraker 或 Klipper 未就绪', isError: true);
      return;
    }
    await _runScript(
      'G28\nM400',
      successMessage: 'XYZ 回零完成',
      refreshPosition: true,
    );
  }

  Future<void> _refreshPosition() async {
    if (_busy) return;
    final printer = context.read<PrinterController>();
    if (!_isConnected(printer)) {
      _setStatus('Moonraker 或 Klipper 未就绪', isError: true);
      return;
    }
    setState(() => _busy = true);
    await printer.refreshStatusSnapshot();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _statusMessage = '状态已刷新';
      _statusIsError = false;
    });
  }

  void _useCurrentPosition(PrinterController printer) {
    final position = printer.currentPosition;
    if (position == null || position.length < 3) {
      _setStatus('尚未收到有效的 XYZ 位置', isError: true);
      return;
    }
    setState(() {
      _xController.text = position[0].toStringAsFixed(3);
      _yController.text = position[1].toStringAsFixed(3);
      _zController.text = position[2].toStringAsFixed(3);
      _statusMessage = '已载入当前位置';
      _statusIsError = false;
    });
  }

  TextEditingController _angleControllerFor(CoatingServo servo) =>
      switch (servo) {
        CoatingServo.pen => _penAngleController,
        CoatingServo.cartridge => _cartridgeAngleController,
      };

  void _setServoAngle(CoatingServo servo, double value) {
    final next = value.clamp(servo.minAngleDeg, servo.maxAngleDeg);
    setState(() {
      _servoAngles[servo] = next;
      _angleControllerFor(servo).text = next.toStringAsFixed(1);
    });
  }

  void _applyTypedServoAngle(CoatingServo servo, String value) {
    final parsed = double.tryParse(value.trim());
    if (parsed == null ||
        parsed < servo.minAngleDeg ||
        parsed > servo.maxAngleDeg) {
      return;
    }
    setState(() => _servoAngles[servo] = parsed);
  }

  Future<void> _executeServo(CoatingServo servo) async {
    if (_busy) return;
    final printer = context.read<PrinterController>();
    if (!_isConnected(printer)) {
      _setStatus('Moonraker 或 Klipper 未就绪', isError: true);
      return;
    }
    final request = _readRequest(CoatingMotionMode.servoOnly);
    if (request == null) return;
    await _runScript(
      request.buildServoGcode(servo),
      successMessage: '${servo.label}已转到目标角',
      commandedServos: {servo},
    );
  }

  Future<void> _releaseServos(Iterable<CoatingServo> servos) async {
    if (_busy) return;
    final printer = context.read<PrinterController>();
    if (!_isConnected(printer)) {
      _setStatus('Moonraker 或 Klipper 未就绪', isError: true);
      return;
    }
    await _runScript(
      CoatingMotionRequest.buildServoReleaseGcode(servos),
      successMessage: servos.length == 1
          ? '${servos.first.label} PWM 已释放'
          : '全部舵机 PWM 已释放',
    );
  }

  Future<void> _emergencyStop() async {
    final printer = context.read<PrinterController>();
    if (printer.repo == null) {
      _setStatus('Moonraker 未连接', isError: true);
      return;
    }
    setState(() {
      _lastScript = 'M112';
      _statusMessage = '正在发送急停...';
      _statusIsError = false;
    });
    final error = await printer.sendGcode(
      'M112',
      receiveTimeout: const Duration(seconds: 5),
    );
    if (!mounted) return;
    setState(() {
      _lastExecutedAt = DateTime.now();
      _statusMessage = error == null ? '急停命令已发送' : '急停后连接已中断';
      _statusIsError = false;
    });
  }

  void _setStatus(String message, {required bool isError}) {
    if (!mounted) return;
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
  }

  String _previewScript() {
    final x = double.tryParse(_xController.text.trim());
    final y = double.tryParse(_yController.text.trim());
    final z = double.tryParse(_zController.text.trim());
    final feed = double.tryParse(_feedController.text.trim());
    final penAngle = double.tryParse(_penAngleController.text.trim());
    final cartridgeAngle = double.tryParse(
      _cartridgeAngleController.text.trim(),
    );
    final settle = int.tryParse(_settleController.text.trim());
    if (x == null ||
        y == null ||
        z == null ||
        feed == null ||
        penAngle == null ||
        cartridgeAngle == null ||
        settle == null) {
      return '输入参数尚未完整';
    }
    final request = CoatingMotionRequest(
      x: x,
      y: y,
      z: z,
      feedMmPerS: feed,
      penServoAngleDeg: penAngle,
      cartridgeServoAngleDeg: cartridgeAngle,
      servoSettleMs: settle,
    );
    final error = request.validate(CoatingMotionMode.joint);
    if (error != null) return error;
    return request.buildGcode(CoatingMotionMode.joint, sequence: _sequence);
  }

  @override
  Widget build(BuildContext context) {
    final printer = context.watch<PrinterController>();
    final connected = _isConnected(printer);
    final platformReady = connected && printer.isHomed && !_busy;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1040;
          final statusAndServo = Column(
            children: [
              _buildStatusCard(printer, connected),
              _buildServoCard(connected),
            ],
          );
          final motionAndCommand = Column(
            children: [
              _buildJointMotionCard(platformReady, connected),
              _buildCommandCard(),
            ],
          );

          final motionPanel = !isWide
              ? Column(children: [statusAndServo, motionAndCommand])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 390, child: statusAndServo),
                    const SizedBox(width: 16),
                    Expanded(child: motionAndCommand),
                  ],
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [motionPanel, const PrintcartPanel()],
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(PrinterController printer, bool connected) {
    final position = printer.currentPosition;
    final x = position != null && position.isNotEmpty ? position[0] : null;
    final y = position != null && position.length > 1 ? position[1] : null;
    final z = position != null && position.length > 2 ? position[2] : null;

    return FluiddCard(
      title: '联合运动状态',
      subtitle: connected ? 'Klipper ready' : '未就绪',
      scrollable: false,
      actions: [
        IconButton(
          tooltip: '刷新状态',
          onPressed: connected && !_busy ? _refreshPosition : null,
          icon: const Icon(Icons.refresh, size: 20),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(
                icon: connected ? Icons.link : Icons.link_off,
                label: connected ? '已连接' : '未连接',
                color: connected ? Colors.green : Colors.grey,
              ),
              _StatusChip(
                icon: printer.isHomed ? Icons.home : Icons.home_outlined,
                label: printer.isHomed ? 'XYZ 已回零' : 'XYZ 未回零',
                color: printer.isHomed ? Colors.lightBlue : Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _PositionStrip(x: x, y: y, z: z),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: connected && !_busy ? _home : null,
                  icon: const Icon(Icons.home, size: 18),
                  label: const Text('XYZ 回零'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: position != null && !_busy
                      ? () => _useCurrentPosition(printer)
                      : null,
                  icon: const Icon(Icons.my_location, size: 18),
                  label: const Text('载入当前位置'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServoCard(bool connected) {
    return FluiddCard(
      title: '双舵机姿态',
      subtitle: '指令角度，无位置反馈',
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final servo in CoatingServo.values) ...[
            _buildServoControl(servo, connected),
            if (servo != CoatingServo.values.last)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(color: Colors.white12),
              ),
          ],
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: connected && !_busy
                ? () => _execute(CoatingMotionMode.servoOnly)
                : null,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('应用全部姿态'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade800,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Tooltip(
            message: '停止两个舵机的 PWM 输出并移除保持力矩',
            child: OutlinedButton.icon(
              onPressed: connected && !_busy
                  ? () => _releaseServos(CoatingServo.values)
                  : null,
              icon: const Icon(Icons.power_off, size: 18),
              label: const Text('释放全部 PWM'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServoControl(CoatingServo servo, bool connected) {
    final presets = switch (servo) {
      CoatingServo.pen => const [
        _ServoPreset(angle: 50, label: '上抬 50°'),
        _ServoPreset(angle: 80, label: '水平 80°'),
        _ServoPreset(angle: 180, label: '下垂 180°'),
      ],
      CoatingServo.cartridge => const [
        _ServoPreset(angle: 30, label: '+X / A 臂 30°'),
        _ServoPreset(angle: 90, label: '90°'),
        _ServoPreset(angle: 150, label: '150°'),
      ],
    };
    final angle = _servoAngles[servo]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(servo.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _AngleStepButton(
              icon: Icons.remove,
              tooltip: '减少 1°',
              onPressed: () => _setServoAngle(servo, angle - 1),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _angleControllerFor(servo),
                onChanged: (value) => _applyTypedServoAngle(servo, value),
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d{0,3}(\.\d?)?$'),
                  ),
                ],
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
                decoration: _fieldDecoration('目标角度', suffixText: '°'),
              ),
            ),
            const SizedBox(width: 8),
            _AngleStepButton(
              icon: Icons.add,
              tooltip: '增加 1°',
              onPressed: () => _setServoAngle(servo, angle + 1),
            ),
          ],
        ),
        Slider(
          value: angle,
          min: servo.minAngleDeg,
          max: servo.maxAngleDeg,
          divisions: (servo.maxAngleDeg - servo.minAngleDeg).round(),
          activeColor: Colors.amber,
          label: '${angle.toStringAsFixed(0)}°',
          onChanged: (value) => _setServoAngle(servo, value),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets
              .map(
                (preset) => ChoiceChip(
                  label: Text(preset.label),
                  selected: (angle - preset.angle).abs() < 0.05,
                  onSelected: (_) => _setServoAngle(servo, preset.angle),
                  selectedColor: Colors.amber.shade800,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: connected && !_busy
                    ? () => _executeServo(servo)
                    : null,
                icon: const Icon(Icons.rotate_right, size: 18),
                label: const Text('应用此姿态'),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: '停止此舵机 PWM 输出并移除保持力矩',
              child: OutlinedButton(
                onPressed: connected && !_busy
                    ? () => _releaseServos([servo])
                    : null,
                child: const Icon(Icons.power_off, size: 18),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '最近指令角 ${_lastCommandedServoAngles[servo]!.toStringAsFixed(1)}°',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildJointMotionCard(bool platformReady, bool connected) {
    return FluiddCard(
      title: 'XYZ + 舵机联合运动',
      subtitle: platformReady ? '可执行' : '需要连接并完成 XYZ 回零',
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 680 ? 4 : 2;
              final gap = 10.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: 10,
                children: [
                  _SizedNumberField(
                    width: width,
                    label: 'X 目标',
                    suffix: 'mm',
                    controller: _xController,
                    onChanged: (_) => setState(() {}),
                  ),
                  _SizedNumberField(
                    width: width,
                    label: 'Y 目标',
                    suffix: 'mm',
                    controller: _yController,
                    onChanged: (_) => setState(() {}),
                  ),
                  _SizedNumberField(
                    width: width,
                    label: 'Z 目标',
                    suffix: 'mm',
                    controller: _zController,
                    onChanged: (_) => setState(() {}),
                  ),
                  _SizedNumberField(
                    width: width,
                    label: '平台速度',
                    suffix: 'mm/s',
                    controller: _feedController,
                    onChanged: (_) => setState(() {}),
                    signed: false,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          SegmentedButton<CoatingJointSequence>(
            segments: const [
              ButtonSegment(
                value: CoatingJointSequence.overlap,
                icon: Icon(Icons.sync, size: 18),
                label: Text('连续下发'),
              ),
              ButtonSegment(
                value: CoatingJointSequence.servoThenPlatform,
                icon: Icon(Icons.timelapse, size: 18),
                label: Text('舵机先到位'),
              ),
            ],
            selected: {_sequence},
            showSelectedIcon: false,
            onSelectionChanged: _busy
                ? null
                : (selection) => setState(() => _sequence = selection.first),
          ),
          if (_sequence == CoatingJointSequence.servoThenPlatform) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: 220,
              child: _SizedNumberField(
                width: 220,
                label: '舵机稳定时间',
                suffix: 'ms',
                controller: _settleController,
                onChanged: (_) => setState(() {}),
                signed: false,
                decimal: false,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: platformReady
                    ? () => _execute(CoatingMotionMode.platformOnly)
                    : null,
                icon: const Icon(Icons.open_with, size: 18),
                label: const Text('只移动平台'),
              ),
              OutlinedButton.icon(
                onPressed: connected && !_busy
                    ? () => _execute(CoatingMotionMode.servoOnly)
                    : null,
                icon: const Icon(Icons.rotate_right, size: 18),
                label: const Text('只转舵机'),
              ),
              ElevatedButton.icon(
                onPressed: platformReady
                    ? () => _execute(CoatingMotionMode.joint)
                    : null,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow, size: 18),
                label: const Text('联合执行'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommandCard() {
    final preview = _previewScript();
    return FluiddCard(
      title: '命令与结果',
      subtitle: _lastExecutedAt == null
          ? '尚未执行'
          : _formatTimestamp(_lastExecutedAt!),
      scrollable: false,
      actions: [
        Tooltip(
          message: '紧急停止并使 Klipper 进入 shutdown',
          child: TextButton.icon(
            onPressed: _emergencyStop,
            icon: const Icon(Icons.stop_circle, size: 19),
            label: const Text('急停'),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _lastScript == null ? '联合命令预览' : '最近下发命令',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 116),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF16181A),
              border: Border.all(color: Colors.white12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: SelectableText(
              _lastScript ?? preview,
              style: const TextStyle(
                color: Colors.lightGreenAccent,
                fontSize: 12,
                height: 1.55,
                fontFamily: 'monospace',
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: (_statusIsError ? Colors.red : Colors.green).withValues(
                  alpha: 0.12,
                ),
                border: Border.all(
                  color: (_statusIsError ? Colors.redAccent : Colors.green)
                      .withValues(alpha: 0.45),
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(
                    _statusIsError ? Icons.error_outline : Icons.check_circle,
                    color: _statusIsError
                        ? Colors.redAccent
                        : Colors.greenAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}

class _ServoPreset {
  final double angle;
  final String label;

  const _ServoPreset({required this.angle, required this.label});
}

class _PositionStrip extends StatelessWidget {
  final double? x;
  final double? y;
  final double? z;

  const _PositionStrip({required this.x, required this.y, required this.z});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _AxisValue(axis: 'X', value: x, color: Colors.redAccent),
        ),
        const VerticalDivider(width: 1, color: Colors.white12),
        Expanded(
          child: _AxisValue(axis: 'Y', value: y, color: Colors.greenAccent),
        ),
        const VerticalDivider(width: 1, color: Colors.white12),
        Expanded(
          child: _AxisValue(axis: 'Z', value: z, color: Colors.lightBlueAccent),
        ),
      ],
    );
  }
}

class _AxisValue extends StatelessWidget {
  final String axis;
  final double? value;
  final Color color;

  const _AxisValue({
    required this.axis,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          axis,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value == null ? '--' : value!.toStringAsFixed(3),
            maxLines: 1,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const Text('mm', style: TextStyle(color: Colors.white38, fontSize: 10)),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _AngleStepButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _AngleStepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 42,
        height: 42,
        child: IconButton.filledTonal(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

class _SizedNumberField extends StatelessWidget {
  final double width;
  final String label;
  final String suffix;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool signed;
  final bool decimal;

  const _SizedNumberField({
    required this.width,
    required this.label,
    required this.suffix,
    required this.controller,
    required this.onChanged,
    this.signed = true,
    this.decimal = true,
  });

  @override
  Widget build(BuildContext context) {
    final pattern = signed
        ? (decimal ? r'^-?\d*(\.\d*)?$' : r'^-?\d*$')
        : (decimal ? r'^\d*(\.\d*)?$' : r'^\d*$');
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: TextInputType.numberWithOptions(
          signed: signed,
          decimal: decimal,
        ),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(pattern))],
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        decoration: _fieldDecoration(label, suffixText: suffix),
      ),
    );
  }
}

InputDecoration _fieldDecoration(String label, {String? suffixText}) {
  return InputDecoration(
    labelText: label,
    suffixText: suffixText,
    filled: true,
    fillColor: Colors.black26,
    isDense: true,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: Colors.white24),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: Colors.blue),
    ),
  );
}
