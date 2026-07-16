import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/printer_controller.dart';
import '../fluidd/widgets/fluidd_card.dart';

class EmmReplayPage extends StatefulWidget {
  const EmmReplayPage({super.key});

  @override
  State<EmmReplayPage> createState() => _EmmReplayPageState();
}

class _EmmReplayPageState extends State<EmmReplayPage> {
  final _pointNameCtrl = TextEditingController();
  final _pointCommandsCtrl = TextEditingController();
  final _startCtrl = TextEditingController(text: '0');
  final _endCtrl = TextEditingController();
  final _segmentsCtrl = TextEditingController(text: '10');
  final _speedCtrl = TextEditingController(text: '2');
  final _paceScaleCtrl = TextEditingController(text: '1.10');
  final _minSegmentTimeMsCtrl = TextEditingController(text: '0');
  final _interPacketDelayMsCtrl = TextEditingController(text: '10');

  bool _loadingPoints = false;
  bool _busy = false;
  bool _autoEnable = true;
  final bool _showLegacyLimitSwitch = false;
  int? _selectedIndex;
  String? _error;
  List<EmmRecordedPoint> _points = const [];
  _RotaryDeltaGeometry _geometry = _RotaryDeltaGeometry.fallback;
  Timer? _playbackPollTimer;
  EmmPlaybackStatus? _playbackStatus;
  double _trajectoryYaw = -0.72;
  double _trajectoryZoom = 1.0;
  double _gestureStartYaw = -0.72;
  double _gestureStartZoom = 1.0;
  double _lastGestureFocalX = 0.0;

  static const _magnetOnCommand = 'SET_PIN PIN=laser VALUE=0.99';
  static const _magnetOffCommand = 'SET_PIN PIN=laser VALUE=0.0';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPoints());
  }

  @override
  void dispose() {
    _playbackPollTimer?.cancel();
    _pointNameCtrl.dispose();
    _pointCommandsCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    _segmentsCtrl.dispose();
    _speedCtrl.dispose();
    _paceScaleCtrl.dispose();
    _minSegmentTimeMsCtrl.dispose();
    _interPacketDelayMsCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshPoints() async {
    final repo = context.read<PrinterController>().repo;
    if (repo == null) {
      setState(() {
        _points = const [];
        _error = '未连接 Moonraker';
      });
      return;
    }

    setState(() {
      _loadingPoints = true;
      _error = null;
    });

    try {
      var geometry = _geometry;
      try {
        final cfgText = await repo.readFileText(
          root: 'config',
          path: 'printer.cfg',
        );
        geometry = _RotaryDeltaGeometry.fromConfig(cfgText, fallback: geometry);
      } catch (_) {
        geometry = _RotaryDeltaGeometry.fallback;
      }

      final text = await repo.readFileText(
        root: 'config',
        path: 'emm_points.json',
      );
      final raw = jsonDecode(text);
      final next = raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (e) => EmmRecordedPoint.fromJson(e.cast<String, dynamic>()),
                )
                .toList()
          : <EmmRecordedPoint>[];
      if (!mounted) return;
      setState(() {
        _points = next;
        _geometry = geometry;
        _loadingPoints = false;
        if (_selectedIndex != null && _selectedIndex! >= next.length) {
          _selectedIndex = next.isEmpty ? null : next.length - 1;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _points = const [];
        _loadingPoints = false;
        _error = '记录文件为空或无法读取';
      });
    }
  }

  Future<void> _runCommand(
    String script, {
    bool refreshPoints = false,
    String? successMessage,
    Duration refreshDelay = const Duration(milliseconds: 350),
    Duration? receiveTimeout,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final printer = context.read<PrinterController>();
    final error = await printer.sendGcode(
      script,
      receiveTimeout: receiveTimeout,
    );
    if (!mounted) return;

    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      _showMessage(error, isError: true);
      return;
    }

    if (refreshPoints) {
      await Future<void>.delayed(refreshDelay);
      if (mounted) await _refreshPoints();
    }

    if (!mounted) return;
    setState(() => _busy = false);
    if (successMessage != null) _showMessage(successMessage);
  }

  Future<void> _recordPoint() async {
    final name = _sanitizedPointName();
    final commandsParam = _encodedPointCommandsParam();
    await _runCommand(
      'EMM_RECORD_POINT NAME=$name$commandsParam',
      refreshPoints: true,
      successMessage: '已记录 $name',
    );
    if (!mounted) return;
    _pointNameCtrl.clear();
  }

  Future<void> _updateSelectedPointCommands() async {
    final index = _selectedIndex;
    if (index == null || index < 0 || index >= _points.length) {
      _showMessage('请先选中一个记录点', isError: true);
      return;
    }
    await _runCommand(
      'EMM_SET_POINT_COMMANDS INDEX=$index${_encodedPointCommandsParam()}',
      refreshPoints: true,
      successMessage: '已更新 #$index 的附加指令',
    );
  }

  Future<void> _clearPoints() async {
    final ok = await _confirm('清空记录点', '确认清空当前所有 EMM 记录点？');
    if (ok != true) return;
    await _runCommand(
      'EMM_CLEAR_POINTS',
      refreshPoints: true,
      successMessage: '记录点已清空',
    );
  }

  Future<void> _homeAndClear() async {
    final ok = await _confirm('G28 后清角度', '确认执行 G28，并在归零完成后清除驱动器角度？');
    if (ok != true) return;
    await _runCommand('EMM_HOME_AND_CLEAR', successMessage: '已发送 G28 清角度');
  }

  Future<void> _play({required bool confirm}) async {
    final command = _buildPlayCommand(confirm: confirm);
    if (command == null) return;
    if (confirm) {
      final ok = await _confirm('绝对轨迹重现', '确认执行当前记录点的绝对角度回放？');
      if (ok != true) return;
      _startPlaybackPolling();
    }
    await _runCommand(
      command,
      successMessage: confirm ? '绝对回放已完成' : '预览命令已发送',
      receiveTimeout: confirm ? const Duration(minutes: 30) : null,
    );
    if (confirm) {
      await _refreshPlaybackStatus();
      _stopPlaybackPollingAfterIdle();
    }
  }

  String? _buildPlayCommand({required bool confirm}) {
    if (_points.isEmpty) {
      _showMessage('需要至少 1 个记录点', isError: true);
      return null;
    }
    final start = int.tryParse(
      _startCtrl.text.trim().isEmpty ? '0' : _startCtrl.text.trim(),
    );
    final end = _endCtrl.text.trim().isEmpty
        ? _points.length - 1
        : int.tryParse(_endCtrl.text.trim());
    final segments = int.tryParse(_segmentsCtrl.text.trim());
    final speed = int.tryParse(_speedCtrl.text.trim());
    final paceScale = double.tryParse(_paceScaleCtrl.text.trim());
    final minSegmentTimeMs = double.tryParse(
      _minSegmentTimeMsCtrl.text.trim().isEmpty
          ? '0'
          : _minSegmentTimeMsCtrl.text.trim(),
    );
    final interPacketDelayMs = double.tryParse(
      _interPacketDelayMsCtrl.text.trim().isEmpty
          ? '10'
          : _interPacketDelayMsCtrl.text.trim(),
    );

    if (start == null ||
        end == null ||
        start < 0 ||
        end < start ||
        end >= _points.length) {
      _showMessage('起点/终点范围无效', isError: true);
      return null;
    }
    if (segments == null || segments < 1 || segments > 200) {
      _showMessage('插值段数需要在 1-200 之间', isError: true);
      return null;
    }
    if (speed == null || speed < 1) {
      _showMessage('速度需要大于 0 RPM', isError: true);
      return null;
    }

    if (paceScale == null || paceScale < 0.1 || paceScale > 5.0) {
      _showMessage('节拍倍率需要在 0.1-5.0 之间', isError: true);
      return null;
    }
    if (minSegmentTimeMs == null ||
        minSegmentTimeMs < 0 ||
        minSegmentTimeMs > 10000) {
      _showMessage('最小段时间需要在 0-10000ms 之间', isError: true);
      return null;
    }
    if (interPacketDelayMs == null ||
        interPacketDelayMs < 10 ||
        interPacketDelayMs > 1000) {
      _showMessage('命令间隔不能小于 10ms', isError: true);
      return null;
    }

    return [
      'EMM_PLAY_POINTS',
      'START=$start',
      'END=$end',
      'SEGMENTS=$segments',
      'SPEED=$speed',
      'PACE_SCALE=${_fmtGcodeFloat(paceScale)}',
      'MIN_SEGMENT_TIME=${_fmtGcodeFloat(minSegmentTimeMs / 1000.0)}',
      'INTER_PACKET_DELAY=${_fmtGcodeFloat(interPacketDelayMs / 1000.0)}',
      'AUTO_ENABLE=${_autoEnable ? 1 : 0}',
      'CONFIRM=${confirm ? 1 : 0}',
    ].join(' ');
  }

  String _fmtGcodeFloat(double value) {
    return value.toStringAsFixed(4).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String _encodedPointCommandsParam() {
    final text = _pointCommandsCtrl.text.trim();
    if (text.isEmpty) return '';
    final encoded = base64Url
        .encode(utf8.encode(text))
        .replaceAll(RegExp(r'=+$'), '');
    return ' COMMANDS_B64=$encoded';
  }

  String _sanitizedPointName() {
    final raw = _pointNameCtrl.text.trim().isEmpty
        ? 'P${_points.length}'
        : _pointNameCtrl.text.trim();
    final name = raw.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_');
    return name.isEmpty ? 'P${_points.length}' : name;
  }

  void _appendPointCommandPreset(String command) {
    final current = _pointCommandsCtrl.text;
    final needsNewline = current.trim().isNotEmpty && !current.endsWith('\n');
    final next = [current, if (needsNewline) '\n', command].join();
    _pointCommandsCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  Future<bool?> _confirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C3034),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.blueGrey,
      ),
    );
  }

  void _startPlaybackPolling() {
    _playbackPollTimer?.cancel();
    setState(() {
      _playbackStatus = const EmmPlaybackStatus(
        active: true,
        current: 0,
        total: 0,
        progress: 0,
        message: 'starting',
      );
    });
    unawaited(_refreshPlaybackStatus());
    _playbackPollTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_refreshPlaybackStatus()),
    );
  }

  void _stopPlaybackPollingAfterIdle() {
    Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (_playbackStatus?.active == true) return;
      _playbackPollTimer?.cancel();
      _playbackPollTimer = null;
    });
  }

  Future<void> _refreshPlaybackStatus() async {
    final repo = context.read<PrinterController>().repo;
    if (repo == null) return;
    try {
      final status = await repo.queryStatusSnapshot({
        'emm_uart': ['playback'],
      });
      final emm = status['emm_uart'];
      final playback = emm is Map ? emm['playback'] : null;
      if (playback is! Map || !mounted) return;
      setState(() {
        _playbackStatus = EmmPlaybackStatus.fromJson(
          playback.cast<String, dynamic>(),
        );
      });
    } catch (_) {
      // Older Klipper extras do not expose playback yet; keep the busy bar.
    }
  }

  void _resetTrajectoryView() {
    setState(() {
      _trajectoryYaw = -0.72;
      _trajectoryZoom = 1.0;
    });
  }

  void _zoomTrajectory(double factor) {
    setState(() {
      _trajectoryZoom = (_trajectoryZoom * factor).clamp(0.45, 4.0);
    });
  }

  void _selectPoint(int index) {
    setState(() {
      _selectedIndex = index;
      _pointCommandsCtrl.text = _points[index].commandsText;
    });
  }

  @override
  Widget build(BuildContext context) {
    final printer = context.watch<PrinterController>();
    final connected =
        printer.phase == AppConnPhase.connected && printer.repo != null;
    final countText = _loadingPoints ? '读取中' : '${_points.length} 点';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 980;
          final controls = Column(
            children: [
              _buildControlCard(connected),
              _buildReplayCard(connected),
            ],
          );
          final trajectory = Column(
            children: [_buildTrajectoryCard(countText), _buildPointsCard()],
          );

          if (!isWide) {
            return Column(children: [controls, trajectory]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 380, child: controls),
              const SizedBox(width: 16),
              Expanded(child: trajectory),
            ],
          );
        },
      ),
    );
  }

  Widget _buildControlCard(bool connected) {
    return FluiddCard(
      title: 'EMM 运动记录',
      subtitle: connected ? null : 'Moonraker 未连接',
      scrollable: false,
      actions: [
        IconButton(
          tooltip: '刷新记录点',
          onPressed: connected && !_busy ? _refreshPoints : null,
          icon: const Icon(Icons.refresh, size: 20),
          color: Colors.grey,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionButton(
                icon: Icons.power,
                label: '使能',
                onPressed: connected && !_busy
                    ? () => _runCommand('EMM_ENABLE', successMessage: '电机已使能')
                    : null,
              ),
              _ActionButton(
                icon: Icons.power_off,
                label: '失能',
                onPressed: connected && !_busy
                    ? () => _runCommand('EMM_DISABLE', successMessage: '电机已失能')
                    : null,
              ),
              _ActionButton(
                icon: Icons.adjust,
                label: '清角度',
                onPressed: connected && !_busy
                    ? () => _runCommand(
                        'EMM_CLEAR_ANGLES',
                        successMessage: '驱动器角度已清零',
                      )
                    : null,
              ),
              _ActionButton(
                icon: Icons.home,
                label: 'G28清角',
                onPressed: connected && !_busy ? _homeAndClear : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _TextField(label: '点名', controller: _pointNameCtrl),
              ),
              const SizedBox(width: 8),
              _IconCommandButton(
                icon: Icons.radio_button_checked,
                tooltip: '记录当前点',
                onPressed: connected && !_busy ? _recordPoint : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _CommandTextField(
            label: '点位附加指令（每行一条）',
            controller: _pointCommandsCtrl,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionButton(
                icon: Icons.electrical_services,
                label: '插入电磁铁开',
                onPressed: () => _appendPointCommandPreset(_magnetOnCommand),
              ),
              _ActionButton(
                icon: Icons.power_settings_new,
                label: '插入电磁铁关',
                onPressed: () => _appendPointCommandPreset(_magnetOffCommand),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: connected && !_busy && _selectedIndex != null
                  ? _updateSelectedPointCommands
                  : null,
              icon: const Icon(Icons.save, size: 17),
              label: const Text('更新选中点指令'),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionButton(
                icon: Icons.edit_location_alt,
                label: '开始记录',
                onPressed: connected && !_busy
                    ? () => _runCommand(
                        'EMM_RECORD_BEGIN CLEAR=0',
                        successMessage: '已进入手动记录状态',
                      )
                    : null,
              ),
              _ActionButton(
                icon: Icons.delete_sweep,
                label: '清空点',
                tone: _ButtonTone.danger,
                onPressed: connected && !_busy && _points.isNotEmpty
                    ? _clearPoints
                    : null,
              ),
              _ActionButton(
                icon: Icons.my_location,
                label: '读角度',
                onPressed: connected && !_busy
                    ? () => _runCommand(
                        'EMM_READ_POSITIONS',
                        successMessage: '已读取实时角度',
                      )
                    : null,
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReplayCard(bool connected) {
    return FluiddCard(
      title: '绝对轨迹重现',
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _NumberField(label: '起点', controller: _startCtrl),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(label: '终点', controller: _endCtrl),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _NumberField(label: '插值段数', controller: _segmentsCtrl),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(label: '速度 RPM', controller: _speedCtrl),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: '命令间隔 ms',
                  controller: _interPacketDelayMsCtrl,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(label: '节拍倍率', controller: _paceScaleCtrl),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _NumberField(label: '最小段时间 ms', controller: _minSegmentTimeMsCtrl),
          const SizedBox(height: 10),
          if (_showLegacyLimitSwitch)
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '限位保护',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              value: false,
              onChanged: null,
            ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '回放前自动使能',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            value: _autoEnable,
            onChanged: (v) => setState(() => _autoEnable = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: connected && !_busy && _points.isNotEmpty
                      ? () => _play(confirm: false)
                      : null,
                  icon: const Icon(Icons.visibility, size: 18),
                  label: const Text('预览'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: connected && !_busy && _points.isNotEmpty
                      ? () => _play(confirm: true)
                      : null,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('绝对回放'),
                ),
              ),
            ],
          ),
          if (_busy || _playbackStatus != null) ...[
            const SizedBox(height: 12),
            _buildPlaybackProgress(),
          ],
        ],
      ),
    );
  }

  Widget _buildPlaybackProgress() {
    final status = _playbackStatus;
    final progress = status == null || status.total <= 0
        ? null
        : status.progress.clamp(0.0, 1.0);
    final text = status == null ? '正在执行，等待回放状态...' : status.description;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: progress, minHeight: 3),
        const SizedBox(height: 8),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _buildTrajectoryCard(String countText) {
    return FluiddCard(
      title: '末端空间轨迹',
      subtitle: '$countText · ${_geometry.summary}',
      scrollable: false,
      actions: [
        IconButton(
          tooltip: '放大',
          onPressed: () => _zoomTrajectory(1.18),
          icon: const Icon(Icons.zoom_in, size: 18),
          color: Colors.grey,
        ),
        IconButton(
          tooltip: '缩小',
          onPressed: () => _zoomTrajectory(1 / 1.18),
          icon: const Icon(Icons.zoom_out, size: 18),
          color: Colors.grey,
        ),
        IconButton(
          tooltip: '重置视角',
          onPressed: _resetTrajectoryView,
          icon: const Icon(Icons.center_focus_strong, size: 18),
          color: Colors.grey,
        ),
        if (_selectedIndex != null)
          IconButton(
            tooltip: '取消选中',
            onPressed: () => setState(() => _selectedIndex = null),
            icon: const Icon(Icons.close, size: 18),
            color: Colors.grey,
          ),
      ],
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF181A1B),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white10),
          ),
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                _zoomTrajectory(event.scrollDelta.dy < 0 ? 1.12 : 1 / 1.12);
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: _resetTrajectoryView,
              onScaleStart: (details) {
                _gestureStartYaw = _trajectoryYaw;
                _gestureStartZoom = _trajectoryZoom;
                _lastGestureFocalX = details.focalPoint.dx;
              },
              onScaleUpdate: (details) {
                final totalDeltaX = details.focalPoint.dx - _lastGestureFocalX;
                setState(() {
                  _trajectoryYaw = _gestureStartYaw + totalDeltaX * 0.014;
                  _trajectoryZoom = (_gestureStartZoom * details.scale).clamp(
                    0.45,
                    4.0,
                  );
                });
              },
              child: CustomPaint(
                painter: _AngleTrajectoryPainter(
                  points: _points,
                  geometry: _geometry,
                  selectedIndex: _selectedIndex,
                  yaw: _trajectoryYaw,
                  zoom: _trajectoryZoom,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPointsCard() {
    return FluiddCard(
      title: '记录点',
      subtitle: _points.isEmpty ? '空' : '${_points.length}',
      scrollable: false,
      child: _points.isEmpty
          ? const SizedBox(
              height: 120,
              child: Center(
                child: Text('暂无记录点', style: TextStyle(color: Colors.white38)),
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 34,
                dataRowMinHeight: 34,
                dataRowMaxHeight: 42,
                showCheckboxColumn: false,
                columnSpacing: 22,
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('名称')),
                  DataColumn(label: Text('ID1')),
                  DataColumn(label: Text('ID2')),
                  DataColumn(label: Text('ID3')),
                  DataColumn(label: Text('附加指令')),
                  DataColumn(label: Text('时间')),
                ],
                rows: [
                  for (var i = 0; i < _points.length; i++)
                    DataRow(
                      selected: _selectedIndex == i,
                      onSelectChanged: (_) => _selectPoint(i),
                      cells: [
                        DataCell(Text('$i')),
                        DataCell(
                          Text(
                            _points[i].name.isEmpty ? 'P$i' : _points[i].name,
                          ),
                        ),
                        DataCell(Text(_points[i].angleText(1))),
                        DataCell(Text(_points[i].angleText(2))),
                        DataCell(Text(_points[i].angleText(3))),
                        DataCell(Text(_points[i].commandsSummary)),
                        DataCell(Text(_points[i].timeText)),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}

class EmmRecordedPoint {
  final String name;
  final DateTime? time;
  final List<int> ids;
  final List<double> angles;
  final List<String> commands;

  const EmmRecordedPoint({
    required this.name,
    required this.time,
    required this.ids,
    required this.angles,
    required this.commands,
  });

  factory EmmRecordedPoint.fromJson(Map<String, dynamic> json) {
    return EmmRecordedPoint(
      name: json['name']?.toString() ?? '',
      time: _timeFromUnixSeconds(json['time']),
      ids: (json['ids'] as List? ?? const [])
          .map((e) => int.tryParse(e.toString()) ?? 0)
          .where((e) => e > 0)
          .toList(),
      angles: (json['angles'] as List? ?? const [])
          .map((e) => double.tryParse(e.toString()) ?? 0.0)
          .toList(),
      commands: _commandsFromJson(json['commands']),
    );
  }

  double? angleForId(int id) {
    final index = ids.indexOf(id);
    if (index < 0 || index >= angles.length) return null;
    return angles[index];
  }

  String angleText(int id) {
    final value = angleForId(id);
    return value == null ? '--' : value.toStringAsFixed(2);
  }

  String get commandsText => commands.join('\n');

  String get commandsSummary {
    if (commands.isEmpty) return '--';
    if (commands.length == 1) return commands.first;
    return '${commands.length} 条';
  }

  String get timeText {
    final t = time;
    if (t == null) return '--';
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
  }
}

class EmmPlaybackStatus {
  final bool active;
  final int current;
  final int total;
  final double progress;
  final String message;

  const EmmPlaybackStatus({
    required this.active,
    required this.current,
    required this.total,
    required this.progress,
    required this.message,
  });

  factory EmmPlaybackStatus.fromJson(Map<String, dynamic> json) {
    final total = int.tryParse(json['total']?.toString() ?? '') ?? 0;
    final current = int.tryParse(json['current']?.toString() ?? '') ?? 0;
    final rawProgress = (json['progress'] is num)
        ? (json['progress'] as num).toDouble()
        : double.tryParse(json['progress']?.toString() ?? '');
    final progress = rawProgress ?? (total > 0 ? current / total : 0.0);
    return EmmPlaybackStatus(
      active: json['active'] == true || json['active']?.toString() == 'true',
      current: current,
      total: total,
      progress: progress.clamp(0.0, 1.0),
      message: json['message']?.toString() ?? 'idle',
    );
  }

  String get description {
    final percent = (progress.clamp(0.0, 1.0) * 100).round();
    final state = active
        ? '回放中'
        : message == 'complete'
        ? '回放完成'
        : message == 'aborted'
        ? '回放中止'
        : '空闲';
    if (total <= 0) return '$state  $percent%';
    return '$state  $current/$total  $percent%';
  }
}

class _RotaryDeltaGeometry {
  final double shoulderRadius;
  final double shoulderHeight;
  final List<double> upperArms;
  final List<double> lowerArms;
  final List<double> towerAnglesDeg;
  final List<double> endstopAnglesDeg;

  static const fallback = _RotaryDeltaGeometry(
    shoulderRadius: 30.36,
    shoulderHeight: 230.0,
    upperArms: [125.0, 125.0, 125.0],
    lowerArms: [217.0, 217.0, 217.0],
    towerAnglesDeg: [0.0, 120.0, 240.0],
    endstopAnglesDeg: [126.0, 126.0, 126.0],
  );

  const _RotaryDeltaGeometry({
    required this.shoulderRadius,
    required this.shoulderHeight,
    required this.upperArms,
    required this.lowerArms,
    required this.towerAnglesDeg,
    required this.endstopAnglesDeg,
  });

  factory _RotaryDeltaGeometry.fromConfig(
    String text, {
    required _RotaryDeltaGeometry fallback,
  }) {
    final sections = <String, Map<String, String>>{};
    var section = '';

    for (final rawLine in const LineSplitter().convert(text)) {
      var line = rawLine;
      final hashIndex = line.indexOf('#');
      if (hashIndex >= 0) line = line.substring(0, hashIndex);
      final semicolonIndex = line.indexOf(';');
      if (semicolonIndex >= 0) line = line.substring(0, semicolonIndex);
      line = line.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1).trim().toLowerCase();
        sections.putIfAbsent(section, () => <String, String>{});
        continue;
      }

      final colon = line.indexOf(':');
      final equals = line.indexOf('=');
      final split = colon < 0
          ? equals
          : equals < 0
          ? colon
          : math.min(colon, equals);
      if (split <= 0 || section.isEmpty) continue;
      final key = line.substring(0, split).trim().toLowerCase();
      final value = line.substring(split + 1).trim();
      sections.putIfAbsent(section, () => <String, String>{})[key] = value;
    }

    double read(String section, String key, double fallbackValue) {
      final raw = sections[section]?[key];
      return double.tryParse(raw ?? '') ?? fallbackValue;
    }

    final shoulderRadius = read(
      'printer',
      'shoulder_radius',
      fallback.shoulderRadius,
    );
    final shoulderHeight = read(
      'printer',
      'shoulder_height',
      fallback.shoulderHeight,
    );
    final upperA = read('stepper_a', 'upper_arm_length', fallback.upperArms[0]);
    final lowerA = read('stepper_a', 'lower_arm_length', fallback.lowerArms[0]);
    final endstopA = read(
      'stepper_a',
      'position_endstop',
      fallback.endstopAnglesDeg[0],
    );

    final steppers = const ['stepper_a', 'stepper_b', 'stepper_c'];
    final upperArms = <double>[];
    final lowerArms = <double>[];
    final towerAngles = <double>[];
    final endstops = <double>[];
    for (var i = 0; i < steppers.length; i++) {
      final stepper = steppers[i];
      upperArms.add(read(stepper, 'upper_arm_length', upperA));
      lowerArms.add(read(stepper, 'lower_arm_length', lowerA));
      towerAngles.add(read(stepper, 'angle', fallback.towerAnglesDeg[i]));
      endstops.add(read(stepper, 'position_endstop', endstopA));
    }

    return _RotaryDeltaGeometry(
      shoulderRadius: shoulderRadius,
      shoulderHeight: shoulderHeight,
      upperArms: List<double>.unmodifiable(upperArms),
      lowerArms: List<double>.unmodifiable(lowerArms),
      towerAnglesDeg: List<double>.unmodifiable(towerAngles),
      endstopAnglesDeg: List<double>.unmodifiable(endstops),
    );
  }

  String get summary =>
      'FK XYZ  R=${shoulderRadius.toStringAsFixed(1)}  H=${shoulderHeight.toStringAsFixed(0)}';

  _AnglePoint3? cartesianFromPoint(EmmRecordedPoint point) {
    final relativeAngles = <double>[];
    for (var id = 1; id <= 3; id++) {
      final fallbackIndex = id - 1;
      final angle =
          point.angleForId(id) ??
          (point.angles.length > fallbackIndex
              ? point.angles[fallbackIndex]
              : null);
      if (angle == null) return null;
      relativeAngles.add(angle);
    }

    final spos = List<double>.generate(
      3,
      (i) => _degToRad(endstopAnglesDeg[i] + relativeAngles[i]),
    );
    return _actuatorToCartesian(spos);
  }

  _AnglePoint3? _actuatorToCartesian(List<double> spos) {
    final sphereCoords = List<_AnglePoint3>.generate(
      3,
      (i) => _elbowCoord(i, spos[i]),
    );
    return _trilateration(sphereCoords);
  }

  _AnglePoint3 _elbowCoord(int index, double spos) {
    final sjElbowX = upperArms[index] * math.cos(spos);
    final sjElbowY = upperArms[index] * math.sin(spos);
    final angle = _degToRad(towerAnglesDeg[index]);
    return _AnglePoint3(
      (sjElbowX + shoulderRadius) * math.cos(angle),
      (sjElbowX + shoulderRadius) * math.sin(angle),
      sjElbowY + shoulderHeight,
    );
  }

  _AnglePoint3? _trilateration(List<_AnglePoint3> spheres) {
    final s1 = spheres[0];
    final s2 = spheres[1];
    final s3 = spheres[2];
    final s21 = _sub(s2, s1);
    final s31 = _sub(s3, s1);
    final d = math.sqrt(_mag2(s21));
    if (d <= 1e-9) return null;

    final ex = _scale(s21, 1.0 / d);
    final i = _dot(ex, s31);
    final vectEy = _sub(s31, _scale(ex, i));
    final eyNorm = math.sqrt(_mag2(vectEy));
    if (eyNorm <= 1e-9) return null;

    final ey = _scale(vectEy, 1.0 / eyNorm);
    final ez = _cross(ex, ey);
    final j = _dot(ey, s31);
    if (j.abs() <= 1e-9) return null;

    final r0 = lowerArms[0];
    final r1 = lowerArms[1];
    final r2 = lowerArms[2];
    final x = (r0 * r0 - r1 * r1 + d * d) / (2.0 * d);
    final y =
        (r0 * r0 - r2 * r2 - x * x + (x - i) * (x - i) + j * j) / (2.0 * j);
    final z2 = r0 * r0 - x * x - y * y;
    if (z2 < -1e-6) return null;
    final z = -math.sqrt(math.max(0.0, z2));

    return _add(s1, _add(_scale(ex, x), _add(_scale(ey, y), _scale(ez, z))));
  }

  static double _degToRad(double degrees) => degrees * math.pi / 180.0;
  static double _dot(_AnglePoint3 a, _AnglePoint3 b) =>
      a.a * b.a + a.b * b.b + a.c * b.c;
  static double _mag2(_AnglePoint3 p) => _dot(p, p);
  static _AnglePoint3 _add(_AnglePoint3 a, _AnglePoint3 b) =>
      _AnglePoint3(a.a + b.a, a.b + b.b, a.c + b.c);
  static _AnglePoint3 _sub(_AnglePoint3 a, _AnglePoint3 b) =>
      _AnglePoint3(a.a - b.a, a.b - b.b, a.c - b.c);
  static _AnglePoint3 _scale(_AnglePoint3 p, double scale) =>
      _AnglePoint3(p.a * scale, p.b * scale, p.c * scale);
  static _AnglePoint3 _cross(_AnglePoint3 a, _AnglePoint3 b) => _AnglePoint3(
    a.b * b.c - a.c * b.b,
    a.c * b.a - a.a * b.c,
    a.a * b.b - a.b * b.a,
  );
}

DateTime? _timeFromUnixSeconds(dynamic value) {
  final seconds = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  if (seconds == null || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
}

List<String> _commandsFromJson(dynamic value) {
  if (value is List) {
    return value
        .map((e) => e.toString().trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }
  if (value is String) {
    return const LineSplitter()
        .convert(value)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }
  return const [];
}

class _AngleTrajectoryPainter extends CustomPainter {
  final List<EmmRecordedPoint> points;
  final _RotaryDeltaGeometry geometry;
  final int? selectedIndex;
  final double yaw;
  final double zoom;

  const _AngleTrajectoryPainter({
    required this.points,
    required this.geometry,
    required this.selectedIndex,
    required this.yaw,
    required this.zoom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gridPaint = Paint()
      ..color = Colors.white10
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1.2;
    final pathPaint = Paint()
      ..color = Colors.lightBlueAccent
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    final pointPaint = Paint()..color = Colors.white;
    final selectedPaint = Paint()..color = Colors.orangeAccent;

    canvas.drawRect(rect, Paint()..color = const Color(0xFF181A1B));

    final samples = <_AnglePoint3>[];
    for (final point in points) {
      final xyz = geometry.cartesianFromPoint(point);
      if (xyz != null) samples.add(xyz);
    }

    final bounds = _AngleBounds.from(samples);
    final projector = _AngleProjector(
      size: size,
      bounds: bounds,
      yaw: yaw,
      zoom: zoom,
    );

    void drawText(
      String text,
      Offset offset,
      Color color, {
      double fontSize = 11,
    }) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, offset);
    }

    final min = bounds.min;
    final max = bounds.max;
    for (var i = 0; i <= 4; i++) {
      final t = i / 4.0;
      final a = min.a + (max.a - min.a) * t;
      final b = min.b + (max.b - min.b) * t;
      canvas.drawLine(
        projector.project(_AnglePoint3(a, min.b, min.c)),
        projector.project(_AnglePoint3(a, max.b, min.c)),
        gridPaint,
      );
      canvas.drawLine(
        projector.project(_AnglePoint3(min.a, b, min.c)),
        projector.project(_AnglePoint3(max.a, b, min.c)),
        gridPaint,
      );
    }

    final origin = projector.project(min);
    final aEnd = projector.project(_AnglePoint3(max.a, min.b, min.c));
    final bEnd = projector.project(_AnglePoint3(min.a, max.b, min.c));
    final cEnd = projector.project(_AnglePoint3(min.a, min.b, max.c));
    canvas.drawLine(origin, aEnd, axisPaint);
    canvas.drawLine(origin, bEnd, axisPaint);
    canvas.drawLine(origin, cEnd, axisPaint);
    drawText('X', aEnd + const Offset(6, -10), Colors.white60);
    drawText('Y', bEnd + const Offset(6, 0), Colors.white60);
    drawText('Z', cEnd + const Offset(6, -8), Colors.white60);

    if (samples.isEmpty) {
      drawText(
        'No FK points',
        Offset(size.width / 2 - 40, size.height / 2 - 8),
        Colors.white38,
        fontSize: 13,
      );
      return;
    }

    final path = Path()
      ..moveTo(
        projector.project(samples.first).dx,
        projector.project(samples.first).dy,
      );
    for (final sample in samples.skip(1)) {
      final p = projector.project(sample);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, pathPaint);

    for (var i = 0; i < samples.length; i++) {
      final p = projector.project(samples[i]);
      final selected = i == selectedIndex;
      canvas.drawCircle(
        p,
        selected ? 5.5 : 3.8,
        selected ? selectedPaint : pointPaint,
      );
      if (selected) {
        drawText(
          '#$i',
          p + const Offset(7, -17),
          Colors.orangeAccent,
          fontSize: 12,
        );
      }
    }

    final rangeText =
        'X ${bounds.min.a.toStringAsFixed(1)}..${bounds.max.a.toStringAsFixed(1)}  '
        'Y ${bounds.min.b.toStringAsFixed(1)}..${bounds.max.b.toStringAsFixed(1)}  '
        'Z ${bounds.min.c.toStringAsFixed(1)}..${bounds.max.c.toStringAsFixed(1)} mm  '
        'zoom ${zoom.toStringAsFixed(2)}x';
    drawText(rangeText, const Offset(12, 10), Colors.white54);
  }

  @override
  bool shouldRepaint(covariant _AngleTrajectoryPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.geometry != geometry ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.yaw != yaw ||
        oldDelegate.zoom != zoom;
  }
}

class _AnglePoint3 {
  final double a;
  final double b;
  final double c;

  const _AnglePoint3(this.a, this.b, this.c);
}

class _AngleBounds {
  final _AnglePoint3 min;
  final _AnglePoint3 max;

  const _AngleBounds(this.min, this.max);

  factory _AngleBounds.from(List<_AnglePoint3> points) {
    if (points.isEmpty) {
      return const _AngleBounds(
        _AnglePoint3(-10, -10, -10),
        _AnglePoint3(10, 10, 10),
      );
    }
    var minA = points.first.a;
    var maxA = points.first.a;
    var minB = points.first.b;
    var maxB = points.first.b;
    var minC = points.first.c;
    var maxC = points.first.c;
    for (final p in points) {
      minA = math.min(minA, p.a);
      maxA = math.max(maxA, p.a);
      minB = math.min(minB, p.b);
      maxB = math.max(maxB, p.b);
      minC = math.min(minC, p.c);
      maxC = math.max(maxC, p.c);
    }
    padRange(double min, double max) {
      final span = math.max((max - min).abs(), 1.0);
      return (min - span * 0.12, max + span * 0.12);
    }

    final a = padRange(minA, maxA);
    final b = padRange(minB, maxB);
    final c = padRange(minC, maxC);
    return _AngleBounds(
      _AnglePoint3(a.$1, b.$1, c.$1),
      _AnglePoint3(a.$2, b.$2, c.$2),
    );
  }
}

class _AngleProjector {
  final Size size;
  final _AngleBounds bounds;
  final double yaw;
  final double zoom;

  const _AngleProjector({
    required this.size,
    required this.bounds,
    required this.yaw,
    required this.zoom,
  });

  Offset project(_AnglePoint3 p) {
    final center = _AnglePoint3(
      (bounds.min.a + bounds.max.a) * 0.5,
      (bounds.min.b + bounds.max.b) * 0.5,
      (bounds.min.c + bounds.max.c) * 0.5,
    );
    final span = math.max(
      math.max(
        (bounds.max.a - bounds.min.a).abs(),
        (bounds.max.b - bounds.min.b).abs(),
      ),
      math.max((bounds.max.c - bounds.min.c).abs(), 1.0),
    );
    final a = (p.a - center.a) / span;
    final b = (p.b - center.b) / span;
    final c = (p.c - center.c) / span;
    final cy = math.cos(yaw);
    final sy = math.sin(yaw);

    final xYaw = a * cy - b * sy;
    final yYaw = a * sy + b * cy;
    final scale = math.min(size.width, size.height) * 0.78 * zoom;
    final x = xYaw;
    final y = -yYaw * 0.42 - c * 0.82;
    return Offset(size.width * 0.5 + x * scale, size.height * 0.56 + y * scale);
  }
}

enum _ButtonTone { normal, danger }

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final _ButtonTone tone;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tone = _ButtonTone.normal,
  });

  @override
  Widget build(BuildContext context) {
    final color = tone == _ButtonTone.danger ? Colors.redAccent : Colors.blue;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: onPressed == null ? Colors.white24 : color,
        side: BorderSide(
          color: onPressed == null
              ? Colors.white12
              : color.withValues(alpha: 0.55),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}

class _IconCommandButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _IconCommandButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 46,
        height: 46,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const _TextField({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: _inputDecoration(label),
    );
  }
}

class _CommandTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const _CommandTextField({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: 3,
      maxLines: 6,
      textInputAction: TextInputAction.newline,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      decoration: _inputDecoration(label).copyWith(
        alignLabelWithHint: true,
        hintText: '例如：M3 S600\nG4 P500\nM5',
        hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const _NumberField({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
        signed: true,
        decimal: true,
      ),
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: _inputDecoration(label),
    );
  }
}

InputDecoration _inputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
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
