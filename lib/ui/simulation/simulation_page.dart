import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../simulation/delta_kinematics.dart';
import '../../simulation/gcode_machining_simulator.dart';
import '../fluidd/widgets/fluidd_card.dart';
import '../surface/stl_mesh.dart';
import '../surface/stl_parser.dart';

enum _PlaybackMode { staticView, dynamicView }

class SimulationPage extends StatefulWidget {
  const SimulationPage({super.key});

  @override
  State<SimulationPage> createState() => _SimulationPageState();
}

class _SimulationPageState extends State<SimulationPage> {
  final _gcodeController = TextEditingController(text: _demoGcode);
  final _shoulderRadius = TextEditingController(text: '65.5');
  final _shoulderHeight = TextEditingController(text: '347');
  final _upperArm = TextEditingController(text: '173');
  final _lowerArm = TextEditingController(text: '289.9');
  final _platformRadius = TextEditingController(text: '28');
  final _toolRadius = TextEditingController(text: '1.0');
  final _sampleStep = TextEditingController(text: '2.0');
  final _fixtureX = TextEditingController(text: '0');
  final _fixtureY = TextEditingController(text: '0');
  final _fixtureZ = TextEditingController(text: '0');
  final _fixtureYaw = TextEditingController(text: '0');
  final _contactNormalX = TextEditingController(text: '0');
  final _contactNormalY = TextEditingController(text: '0');
  final _contactNormalZ = TextEditingController(text: '-1');

  StlMesh? _mesh;
  String? _meshName;
  String? _loadError;
  MachiningSimulationResult? _result;
  MachiningSimulationOptions _options = const MachiningSimulationOptions();
  _PlaybackMode _playbackMode = _PlaybackMode.staticView;
  Timer? _timer;
  bool _playing = false;
  double _progress = 0;
  bool _linearMovesAreProcessing = true;
  WorkpieceBedFace _bedFace = WorkpieceBedFace.negZ;

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in [
      _gcodeController,
      _shoulderRadius,
      _shoulderHeight,
      _upperArm,
      _lowerArm,
      _platformRadius,
      _toolRadius,
      _sampleStep,
      _fixtureX,
      _fixtureY,
      _fixtureZ,
      _fixtureYaw,
      _contactNormalX,
      _contactNormalY,
      _contactNormalZ,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickStl() async {
    setState(() => _loadError = null);
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['stl', 'STL'],
      withData: true,
      dialogTitle: '选择待加工 STL 模型',
    );
    final file = selection?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    try {
      final mesh = StlParser.parse(bytes, name: file.name);
      setState(() {
        _mesh = mesh;
        _meshName = file.name;
        _result = null;
      });
    } on StlParseException catch (error) {
      setState(() => _loadError = error.message);
    } catch (error) {
      setState(() => _loadError = 'STL load failed: $error');
    }
  }

  Future<void> _pickGcode() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gcode', 'gc', 'nc', 'tap', 'txt'],
      withData: true,
      dialogTitle: '选择 G-code 文件',
    );
    final file = selection?.files.single;
    final bytes = file?.bytes;
    if (bytes == null) return;
    setState(() {
      _gcodeController.text = utf8.decode(bytes, allowMalformed: true);
      _result = null;
    });
  }

  void _runSimulation() {
    final values = [
      _number(_shoulderRadius),
      _number(_shoulderHeight),
      _number(_upperArm),
      _number(_lowerArm),
      _number(_platformRadius),
      _number(_toolRadius),
      _number(_sampleStep),
      _number(_fixtureX),
      _number(_fixtureY),
      _number(_fixtureZ),
      _number(_fixtureYaw),
      _number(_contactNormalX),
      _number(_contactNormalY),
      _number(_contactNormalZ),
    ];
    if (values.any((value) => value == null)) {
      setState(() => _loadError = '机构、刀具和装夹参数必须是有效数字。');
      return;
    }
    final normal = SimVector3(values[11]!, values[12]!, values[13]!);
    if (_bedFace == WorkpieceBedFace.custom && normal.length <= 1e-9) {
      setState(() => _loadError = '自定义接触法线不能为零向量。');
      return;
    }
    final geometry = DeltaGeometry(
      shoulderRadiusMm: values[0]!,
      shoulderHeightMm: values[1]!,
      upperArmMm: values[2]!,
      lowerArmMm: values[3]!,
      platformRadiusMm: values[4]!,
    );
    final options = MachiningSimulationOptions(
      geometry: geometry,
      toolRadiusMm: values[5]!.abs(),
      sampleStepMm: values[6]!.abs(),
      linearMovesAreProcessing: _linearMovesAreProcessing,
      workpiecePlacement: WorkpiecePlacement(
        bedFace: _bedFace,
        centerXmm: values[7]!,
        centerYmm: values[8]!,
        bedZmm: values[9]!,
        yawDeg: values[10]!,
        contactNormal: normal,
      ),
    );
    final result = GcodeMachiningSimulator().run(
      gcode: _gcodeController.text,
      mesh: _mesh,
      options: options,
    );
    setState(() {
      _options = options;
      _result = result;
      _loadError = null;
      _progress = 0;
      _playing = false;
    });
    _timer?.cancel();
  }

  double? _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim());

  void _togglePlayback() {
    if (_result == null) return;
    if (_playing) {
      _timer?.cancel();
      setState(() => _playing = false);
      return;
    }
    if (_progress >= 1) _progress = 0;
    setState(() => _playing = true);
    _timer = Timer.periodic(const Duration(milliseconds: 32), (_) {
      if (!mounted) return;
      setState(() {
        _progress += 0.004;
        if (_progress >= 1) {
          _progress = 1;
          _playing = false;
          _timer?.cancel();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_inputCard(), _machineCard(), _fixtureCard(), _resultCard()],
    );
    final view = _viewportCard();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 390, child: left),
                const SizedBox(width: 16),
                Expanded(child: view),
              ],
            )
          : Column(children: [view, left]),
    );
  }

  Widget _inputCard() => FluiddCard(
    title: '输入程序',
    subtitle: _meshName ?? '未加载 STL',
    scrollable: false,
    actions: [
      IconButton(
        tooltip: '加载 STL',
        icon: const Icon(Icons.view_in_ar_outlined),
        onPressed: _pickStl,
      ),
      IconButton(
        tooltip: '加载 G-code',
        icon: const Icon(Icons.folder_open_outlined),
        onPressed: _pickGcode,
      ),
    ],
    child: Column(
      children: [
        TextField(
          controller: _gcodeController,
          minLines: 8,
          maxLines: 12,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: const InputDecoration(
            labelText: 'G-code',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() => _result = null),
        ),
        const SizedBox(height: 10),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _linearMovesAreProcessing,
          onChanged: (value) => setState(() {
            _linearMovesAreProcessing = value ?? true;
            _result = null;
          }),
          title: const Text('将 G1 视为加工运动'),
          subtitle: const Text('M3/M4/M5 和 SET_PIN 会覆盖此初始状态。'),
        ),
        if (_loadError != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _loadError!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
      ],
    ),
  );

  Widget _machineCard() => FluiddCard(
    title: 'Delta 数学模型',
    subtitle: '单位 mm，来自当前 printer.cfg 的默认值',
    scrollable: false,
    child: Column(
      children: [
        _numberRow('肩部半径', _shoulderRadius, '肩部高度', _shoulderHeight),
        const SizedBox(height: 10),
        _numberRow('上臂长度', _upperArm, '下臂长度', _lowerArm),
        const SizedBox(height: 10),
        _numberRow('动平台半径', _platformRadius, '刀具半径', _toolRadius),
        const SizedBox(height: 10),
        _numberField('轨迹采样间距', _sampleStep),
      ],
    ),
  );

  Widget _fixtureCard() => FluiddCard(
    title: '工件接触面与放置',
    subtitle: '选定面旋转到床面，位置为机床坐标',
    scrollable: false,
    child: Column(
      children: [
        DropdownButtonFormField<WorkpieceBedFace>(
          initialValue: _bedFace,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '接触床面的 STL 包围面',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: WorkpieceBedFace.values
              .map(
                (face) => DropdownMenuItem(
                  value: face,
                  child: Text('${face.label}  ${face.description}'),
                ),
              )
              .toList(),
          onChanged: (face) => setState(() {
            _bedFace = face ?? _bedFace;
            _result = null;
          }),
        ),
        const SizedBox(height: 10),
        if (_bedFace == WorkpieceBedFace.custom) ...[
          _numberRow('接触法线 Nx', _contactNormalX, '接触法线 Ny', _contactNormalY),
          const SizedBox(height: 10),
          _numberField('接触法线 Nz', _contactNormalZ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '填写 STL 中接触面的外法线；长度任意，仿真会自动归一化。',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
        ],
        _numberRow('放置中心 X', _fixtureX, '放置中心 Y', _fixtureY),
        const SizedBox(height: 10),
        _numberRow('床面 Z', _fixtureZ, '床面内旋转', _fixtureYaw),
        const SizedBox(height: 8),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '放置中心为工件落在床面后的包围盒中心；床面 Z 是接触面高度。',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _runSimulation,
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('运行验证'),
          ),
        ),
      ],
    ),
  );

  Widget _resultCard() {
    final result = _result;
    if (result == null) {
      return const FluiddCard(
        title: '验证结果',
        subtitle: '等待运行',
        scrollable: false,
        child: Text('加载 STL 和 G-code 后运行验证。'),
      );
    }
    final success =
        result.kinematicsValid && (_mesh == null || result.hasMeshContact);
    return FluiddCard(
      title: '验证结果',
      subtitle: success ? '通过基础检查' : '需要处理',
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _metric(
            '运动学采样',
            '${result.reachablePoses}/${result.sampledPoses} 可达',
          ),
          _metric('总轨迹', '${result.pathLengthMm.toStringAsFixed(1)} mm'),
          _metric('加工轨迹', '${result.processingLengthMm.toStringAsFixed(1)} mm'),
          if (_mesh != null)
            _metric(
              'STL 面覆盖',
              '${(result.faceCoverage * 100).toStringAsFixed(1)}% (${result.contactedFaceCount}/${_mesh!.faceCount})',
            ),
          if (_mesh != null)
            _metric(
              '装夹状态',
              '${_bedFace.label} 接触，中心 (${_fixtureX.text}, ${_fixtureY.text})',
            ),
          if (result.errors.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final error in result.errors.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  error,
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _metric(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        const Spacer(),
        Text(value),
      ],
    ),
  );

  Widget _viewportCard() => FluiddCard(
    title: '机构与加工回放',
    subtitle: _result == null
        ? '加载后显示'
        : '${_result!.program.moves.length} 段运动',
    scrollable: false,
    actions: [
      SegmentedButton<_PlaybackMode>(
        segments: const [
          ButtonSegment(
            value: _PlaybackMode.staticView,
            icon: Icon(Icons.photo_outlined),
            tooltip: '静态预览',
          ),
          ButtonSegment(
            value: _PlaybackMode.dynamicView,
            icon: Icon(Icons.movie_outlined),
            tooltip: '动态演示',
          ),
        ],
        selected: {_playbackMode},
        showSelectedIcon: false,
        onSelectionChanged: (value) =>
            setState(() => _playbackMode = value.first),
      ),
      const SizedBox(width: 8),
      IconButton(
        tooltip: _playing ? '暂停' : '播放',
        onPressed: _result == null || _playbackMode == _PlaybackMode.staticView
            ? null
            : _togglePlayback,
        icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
      ),
    ],
    child: Column(
      children: [
        AspectRatio(
          aspectRatio: 1.35,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white12),
            ),
            child: CustomPaint(
              painter: _SimulationPainter(
                mesh: _mesh,
                result: _result,
                options: _options,
                progress: _playbackMode == _PlaybackMode.staticView
                    ? 1
                    : _progress,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        if (_playbackMode == _PlaybackMode.dynamicView) ...[
          Slider(
            value: _progress,
            onChanged: _result == null
                ? null
                : (value) => setState(() => _progress = value),
          ),
          Row(
            children: [
              Text(
                '${(_progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '回到起点',
                onPressed: _result == null
                    ? null
                    : () => setState(() => _progress = 0),
                icon: const Icon(Icons.restart_alt),
              ),
            ],
          ),
        ],
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            '蓝色：STL 目标面；青色：加工扫掠；红色：不可达运动。面覆盖按三角面中心与刀具扫掠体的距离计算。',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ),
      ],
    ),
  );

  Widget _numberRow(
    String leftLabel,
    TextEditingController left,
    String rightLabel,
    TextEditingController right,
  ) => Row(
    children: [
      Expanded(child: _numberField(leftLabel, left)),
      const SizedBox(width: 10),
      Expanded(child: _numberField(rightLabel, right)),
    ],
  );

  Widget _numberField(String label, TextEditingController controller) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() => _result = null),
      );
}

class _SimulationPainter extends CustomPainter {
  final StlMesh? mesh;
  final MachiningSimulationResult? result;
  final MachiningSimulationOptions options;
  final double progress;

  const _SimulationPainter({
    required this.mesh,
    required this.result,
    required this.options,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF161B20),
    );
    final bounds = _sceneBounds();
    final projector = _Projector(bounds, size);
    _drawBed(canvas, projector, bounds);
    _drawMesh(canvas, projector);
    _drawPath(canvas, projector);
    _drawRobot(canvas, projector);
    _drawAxes(canvas, projector);
  }

  _Bounds _sceneBounds() {
    final geometry = options.geometry;
    final span = math.max(geometry.shoulderRadiusMm * 2.8, 180.0);
    var minX = -span / 2;
    var maxX = span / 2;
    var minY = -span / 2;
    var maxY = span / 2;
    var minZ = -20.0;
    var maxZ = geometry.shoulderHeightMm + 20;
    if (mesh != null) {
      final b = WorkpieceTransform.fromMesh(
        mesh!,
        options.workpiecePlacement,
      ).transformedBounds;
      minX = math.min(minX, b.minX);
      maxX = math.max(maxX, b.maxX);
      minY = math.min(minY, b.minY);
      maxY = math.max(maxY, b.maxY);
      minZ = math.min(minZ, b.minZ);
      maxZ = math.max(maxZ, b.maxZ);
    }
    return _Bounds(minX, maxX, minY, maxY, minZ, maxZ);
  }

  void _drawBed(Canvas canvas, _Projector p, _Bounds b) {
    final points = [
      p.project(SimVector3(b.minX, b.minY, 0)),
      p.project(SimVector3(b.maxX, b.minY, 0)),
      p.project(SimVector3(b.maxX, b.maxY, 0)),
      p.project(SimVector3(b.minX, b.maxY, 0)),
    ];
    canvas.drawPath(
      Path()..addPolygon(points, true),
      Paint()..color = const Color(0xFF24313A),
    );
    canvas.drawPath(
      Path()..addPolygon(points, true),
      Paint()
        ..color = Colors.white12
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawMesh(Canvas canvas, _Projector p) {
    if (mesh == null) return;
    final contact = result?.contactedFaces;
    final transform = WorkpieceTransform.fromMesh(
      mesh!,
      options.workpiecePlacement,
    );
    final faces = mesh!.sampledTriangles(1800);
    final sampleStep = math.max(1, mesh!.faceCount ~/ faces.length);
    for (var i = 0; i < faces.length; i++) {
      final face = faces[i];
      final sourceIndex = math.min(i * sampleStep, mesh!.faceCount - 1);
      final covered = contact != null && contact[sourceIndex];
      final shade = (0.35 + 0.65 * face.normal.normalized().z.abs()).clamp(
        0.2,
        1.0,
      );
      final color = covered
          ? Color.lerp(const Color(0xFF006D77), const Color(0xFF33D6CC), shade)!
          : Color.lerp(
              const Color(0xFF123D72),
              const Color(0xFF55A8FF),
              shade,
            )!;
      final path = Path()
        ..moveTo(
          p.project(transform.transform(face.a)).dx,
          p.project(transform.transform(face.a)).dy,
        )
        ..lineTo(
          p.project(transform.transform(face.b)).dx,
          p.project(transform.transform(face.b)).dy,
        )
        ..lineTo(
          p.project(transform.transform(face.c)).dx,
          p.project(transform.transform(face.c)).dy,
        )
        ..close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.72));
    }
  }

  void _drawPath(Canvas canvas, _Projector p) {
    final moves = result?.program.moves;
    if (moves == null || moves.isEmpty) return;
    final count = math.max(1, (moves.length * progress).ceil());
    final invalid = result!.invalidMoveIndexes.toSet();
    for (var i = 0; i < count; i++) {
      final move = moves[i];
      final color = invalid.contains(i)
          ? Colors.redAccent
          : move.processing
          ? const Color(0xFF26D9C5)
          : const Color(0xFFB3C0C8);
      canvas.drawLine(
        p.project(move.start),
        p.project(move.end),
        Paint()
          ..color = color
          ..strokeWidth = move.processing ? 2.5 : 1.0,
      );
    }
  }

  void _drawRobot(Canvas canvas, _Projector p) {
    final moves = result?.program.moves;
    if (moves == null || moves.isEmpty) return;
    final index = math.min(
      moves.length - 1,
      math.max(0, (moves.length * progress).ceil() - 1),
    );
    final move = moves[index];
    final center =
        move.start +
        (move.end - move.start) *
            ((progress * moves.length - index).clamp(0.0, 1.0));
    final geometry = options.geometry;
    final joints = DeltaKinematics(
      geometry,
    ).inverse(center.x, center.y, center.z).jointDeg;
    for (var arm = 0; arm < 3; arm++) {
      final a = arm * 2 * math.pi / 3;
      final shoulder = SimVector3(
        geometry.shoulderRadiusMm * math.cos(a),
        geometry.shoulderRadiusMm * math.sin(a),
        geometry.shoulderHeightMm,
      );
      final joint = joints.length == 3
          ? joints[arm] * math.pi / 180
          : 90 * math.pi / 180;
      final elbow =
          shoulder +
          SimVector3(
            -math.cos(a) * geometry.upperArmMm * math.cos(joint),
            -math.sin(a) * geometry.upperArmMm * math.cos(joint),
            -geometry.upperArmMm * math.sin(joint),
          );
      final paint = Paint()
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        p.project(shoulder),
        p.project(elbow),
        paint..color = const Color(0xFFEF9B3A),
      );
      canvas.drawLine(
        p.project(elbow),
        p.project(center),
        paint..color = const Color(0xFF8EA4B3),
      );
      canvas.drawCircle(
        p.project(shoulder),
        5,
        Paint()..color = const Color(0xFFF0B342),
      );
      canvas.drawCircle(
        p.project(elbow),
        4,
        Paint()..color = const Color(0xFFE6EEF2),
      );
    }
    final platform = <Offset>[];
    for (var i = 0; i < 3; i++) {
      final a = i * 2 * math.pi / 3;
      platform.add(
        p.project(
          center +
              SimVector3(
                geometry.platformRadiusMm * math.cos(a),
                geometry.platformRadiusMm * math.sin(a),
                0,
              ),
        ),
      );
    }
    canvas.drawPath(
      Path()..addPolygon(platform, true),
      Paint()..color = const Color(0xFFCED9DE),
    );
    final yaw = move.yawDeg * math.pi / 180;
    final servoAxis =
        center + SimVector3(math.cos(yaw) * 18, math.sin(yaw) * 18, -8);
    canvas.drawLine(
      p.project(center),
      p.project(servoAxis),
      Paint()
        ..color = const Color(0xFFF06C59)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    final pitch = move.pitchDeg * math.pi / 180;
    final tool =
        servoAxis +
        SimVector3(
          math.cos(yaw) * math.cos(pitch) * 15,
          math.sin(yaw) * math.cos(pitch) * 15,
          -math.sin(pitch) * 15 - 16,
        );
    canvas.drawLine(
      p.project(servoAxis),
      p.project(tool),
      Paint()
        ..color = const Color(0xFFF4F7F8)
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      p.project(tool),
      4,
      Paint()..color = const Color(0xFFFF5E5B),
    );
  }

  void _drawAxes(Canvas canvas, _Projector p) {
    const origin = SimVector3(0, 0, 0);
    final axes = [
      (const SimVector3(35, 0, 0), Colors.redAccent, 'X'),
      (const SimVector3(0, 35, 0), Colors.greenAccent, 'Y'),
      (const SimVector3(0, 0, 35), Colors.lightBlueAccent, 'Z'),
    ];
    for (final axis in axes) {
      canvas.drawLine(
        p.project(origin),
        p.project(axis.$1),
        Paint()
          ..color = axis.$2
          ..strokeWidth = 2,
      );
      final text = TextPainter(
        text: TextSpan(
          text: axis.$3,
          style: TextStyle(color: axis.$2, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, p.project(axis.$1) + const Offset(3, -12));
    }
  }

  @override
  bool shouldRepaint(covariant _SimulationPainter oldDelegate) =>
      oldDelegate.mesh != mesh ||
      oldDelegate.result != result ||
      oldDelegate.options != options ||
      oldDelegate.progress != progress;
}

class _Bounds {
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
  final double minZ;
  final double maxZ;
  const _Bounds(
    this.minX,
    this.maxX,
    this.minY,
    this.maxY,
    this.minZ,
    this.maxZ,
  );
}

class _Projector {
  final _Bounds bounds;
  final Size size;
  late final double _scale =
      math.min(
        size.width / math.max(bounds.maxX - bounds.minX, 1),
        size.height /
            math.max(
              (bounds.maxY - bounds.minY) * .55 +
                  (bounds.maxZ - bounds.minZ) * .9,
              1,
            ),
      ) *
      .72;
  _Projector(this.bounds, this.size);

  Offset project(SimVector3 value) {
    const cos = 0.8660254;
    const sin = 0.5;
    final x = (value.x - value.y) * cos;
    final y = (value.x + value.y) * sin - value.z;
    final centerX = (bounds.minX + bounds.maxX) / 2;
    final centerY = (bounds.minY + bounds.maxY) / 2;
    final centerZ = (bounds.minZ + bounds.maxZ) / 2;
    final cx = (centerX - centerY) * cos;
    final cy = (centerX + centerY) * sin - centerZ;
    return Offset(
      size.width / 2 + (x - cx) * _scale,
      size.height / 2 + (y - cy) * _scale,
    );
  }
}

const _demoGcode = '''; Replace this with the generated machining program
G90
G0 X-30 Y-20 Z40 F2400
M3
G1 X30 Y-20 Z40 F900
G1 X30 Y-10 Z40 F900
G1 X-30 Y-10 Z40 F900
G1 X-30 Y0 Z40 F900
G1 X30 Y0 Z40 F900
G1 X30 Y10 Z40 F900
G1 X-30 Y10 Z40 F900
G1 X-30 Y20 Z40 F900
G1 X30 Y20 Z40 F900
M5
''';
