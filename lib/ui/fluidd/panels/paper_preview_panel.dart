import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'dart:io' show File;
import 'dart:convert';

import '../../../writing/model/page.dart';
import '../../../writing/model/essay_grid.dart';
import '../../../writing/model/toolpath.dart';
import '../../../writing/model/toolpath_painter.dart';
import '../../../writing/model/animated_toolpath_painter.dart';
import '../../../writing/render/page_painter.dart';
import '../../../writing/render/viewport.dart' as kp;
import '../../../writing/model/gcode_parser.dart';
import '../../../writing/model/toolpath_analyzer.dart';
import '../widgets/fluidd_card.dart';

class PaperPreviewPanel extends StatefulWidget {
  const PaperPreviewPanel({super.key});

  @override
  State<PaperPreviewPanel> createState() => _PaperPreviewPanelState();
}

class _PaperPreviewPanelState extends State<PaperPreviewPanel>
    with SingleTickerProviderStateMixin {
  // 默认 A4 纸张
  final PageMm _page = const PageMm(widthMm: 210, heightMm: 297);
  // 默认作文格
  final EssayGridSpec _grid = defaultA4EssayGrid();

  bool _showPenUp = true;

  ToolPath _uploadedToolPath = ToolPath.empty;
  List<ToolPathIssue> _issues = [];
  final GlobalKey _gestureKey = GlobalKey();

  // 动态预览相关
  bool _isDynamicPreview = false;
  late AnimationController _animationController;
  double _playbackSpeed = 1.0;

  kp.Viewport? _viewport;
  Size? _lastViewportSize;
  bool _hasUserTransform = false;

  kp.Viewport? _gestureStartViewport;
  Offset? _gestureWorldMm;

  static const double _fitPaddingPx = 10.0;
  static const double _minScalePxPerMm = 0.2;
  static const double _maxScalePxPerMm = 30.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10), // 默认10秒完成动画
    );
    _animationController.addListener(() {
      setState(() {});
    });
    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // 动画完成后自动停止动态预览模式
        setState(() {
          _isDynamicPreview = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  kp.Viewport _fitViewport(Size size) {
    final availW = (size.width - _fitPaddingPx * 2).clamp(1.0, double.infinity);
    final availH = (size.height - _fitPaddingPx * 2).clamp(
      1.0,
      double.infinity,
    );

    double scale = availW / _page.widthMm;
    if (_page.heightMm * scale > availH) {
      scale = availH / _page.heightMm;
    }
    scale = scale.clamp(_minScalePxPerMm, _maxScalePxPerMm);

    final contentW = _page.widthMm * scale;
    final contentH = _page.heightMm * scale;
    final pan = Offset(
      (size.width - contentW) / 2,
      (size.height - contentH) / 2,
    );

    return kp.Viewport(scale: scale, pan: pan);
  }

  kp.Viewport _ensureViewport(Size size) {
    if (_viewport == null ||
        (!_hasUserTransform && _lastViewportSize != size)) {
      _viewport = _fitViewport(size);
    }
    _lastViewportSize = size;
    return _viewport!;
  }

  RenderBox? _gestureBox() {
    final ctx = _gestureKey.currentContext;
    final obj = ctx?.findRenderObject();
    if (obj is RenderBox) return obj;
    return null;
  }

  void _resetView() {
    final size = _lastViewportSize;
    if (size == null) return;
    setState(() {
      _viewport = _fitViewport(size);
      _hasUserTransform = false;
    });
  }

  void _showIssuesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C3034),
        title: const Text('轨迹分析报告', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _issues.length,
            itemBuilder: (context, index) {
              final issue = _issues[index];
              final color = switch (issue.level) {
                ToolPathIssueLevel.error => Colors.redAccent,
                ToolPathIssueLevel.warning => Colors.orangeAccent,
                ToolPathIssueLevel.info => Colors.blueAccent,
              };
              return ListTile(
                leading: Icon(
                  issue.level == ToolPathIssueLevel.error
                      ? Icons.error_outline
                      : (issue.level == ToolPathIssueLevel.warning
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline),
                  color: color,
                ),
                title: Text(issue.title, style: TextStyle(color: color, fontSize: 14)),
                subtitle: Text(
                  issue.message,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePickAndPreview() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gcode'],
      withData: true, // Web 平台必须设置 true 才能获取字节数据
    );

    if (result != null && result.files.isNotEmpty) {
      String gcode;
      if (kIsWeb) {
        // Web 端从 bytes 读取，不使用 path
        final bytes = result.files.single.bytes;
        if (bytes == null) return;
        gcode = utf8.decode(bytes);
      } else {
        // 桌面端从文件读取
        final path = result.files.single.path;
        if (path == null) return;
        final file = File(path);
        gcode = await file.readAsString();
      }

      final parser = GcodeParser();
      final newPath = parser.parse(gcode);
      setState(() {
        _uploadedToolPath = newPath;
        _issues = ToolPathAnalyzer.analyze(newPath);
        // 重置动画状态
        _isDynamicPreview = false;
        _animationController.reset();
      });
    }
  }

  void _toggleDynamicPreview() {
    if (_uploadedToolPath.polylines.isEmpty) return;
    
    setState(() {
      _isDynamicPreview = !_isDynamicPreview;
      if (_isDynamicPreview) {
        // 计算动画时长：基于轨迹复杂度，约每100个点1秒，并应用速率系数
        final totalPoints = _uploadedToolPath.polylines
            .fold(0, (sum, pl) => sum + pl.points.length);
        final baseSeconds = (totalPoints / 100).clamp(5, 120).toDouble();
        _animationController.duration = Duration(
          milliseconds: (baseSeconds * 1000 / _playbackSpeed).toInt(),
        );
        _animationController.forward(from: 0.0);
      } else {
        _animationController.stop();
        _animationController.reset();
      }
    });
  }

  void _updatePlaybackSpeed(double speed) {
    if (_playbackSpeed == speed) return;
    
    setState(() {
      _playbackSpeed = speed;
      
      if (_isDynamicPreview && _animationController.isAnimating) {
        final currentProgress = _animationController.value;
        final totalPoints = _uploadedToolPath.polylines
            .fold(0, (sum, pl) => sum + pl.points.length);
        final baseSeconds = (totalPoints / 100).clamp(5, 120).toDouble();
        
        _animationController.duration = Duration(
          milliseconds: (baseSeconds * 1000 / _playbackSpeed).toInt(),
        );
        // 从当前进度继续播放
        _animationController.forward(from: currentProgress);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ToolPath toolPath = _uploadedToolPath;

    return FluiddCard(
      title: 'Paper Preview',
      actions: [
        IconButton(
          tooltip: _showPenUp ? 'Hide pen-up moves' : 'Show pen-up moves',
          icon: Icon(
            _showPenUp
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: Colors.grey,
            size: 20,
          ),
          onPressed: () {
            setState(() => _showPenUp = !_showPenUp);
          },
        ),
        IconButton(
          tooltip: '上传并预览 GCode',
          icon: const Icon(Icons.upload_file_outlined, color: Colors.grey, size: 20),
          onPressed: _handlePickAndPreview,
        ),
        IconButton(
          tooltip: _isDynamicPreview ? '停止动态预览' : '动态预览',
          icon: Icon(
            _isDynamicPreview ? Icons.stop_circle_outlined : Icons.play_circle_outlined,
            color: _isDynamicPreview ? Colors.orange : (_uploadedToolPath.polylines.isEmpty ? Colors.grey.shade600 : Colors.grey),
            size: 20,
          ),
          onPressed: _uploadedToolPath.polylines.isEmpty ? null : _toggleDynamicPreview,
        ),
        if (_isDynamicPreview)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<double>(
                value: _playbackSpeed,
                dropdownColor: const Color(0xFF2C3034),
                icon: const SizedBox.shrink(), // 隐藏箭头以节省空间
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                items: [0.1, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0].map((s) => DropdownMenuItem(
                  value: s,
                  child: Text('${s}x'),
                )).toList(),
                onChanged: (v) {
                  if (v != null) _updatePlaybackSpeed(v);
                },
              ),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.grey, size: 20),
          onPressed: () {
            _resetView();
          },
          tooltip: 'Reset View',
        ),
        if (_issues.isNotEmpty)
          IconButton(
            icon: Icon(
              Icons.warning_amber_rounded,
              color: _issues.any((i) => i.level == ToolPathIssueLevel.error)
                  ? Colors.red
                  : Colors.orange,
              size: 20,
            ),
            onPressed: () => _showIssuesDialog(context),
            tooltip: '查看轨迹检测结果',
          ),
      ],
      child: AspectRatio(
        aspectRatio: _page.widthMm / _page.heightMm, // 保持纸张比例
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF333333), // 背景色，深色衬托白纸
            borderRadius: BorderRadius.circular(4),
          ),
          clipBehavior: Clip.hardEdge,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              final viewport = _ensureViewport(size);

              return Stack(
                fit: StackFit.expand,
                children: [
                  Listener(
                    key: _gestureKey,
                    onPointerSignal: (event) {
                      if (event is! PointerScrollEvent) return;

                      // 使用 pointerSignalResolver 注册当前事件，防止事件冒泡导致父级 SingleChildScrollView 同步滚动
                      GestureBinding.instance.pointerSignalResolver.register(
                        event,
                        (event) {
                          if (event is! PointerScrollEvent) return;
                          final box = _gestureBox();
                          if (box == null) return;

                          final local = box.globalToLocal(event.position);
                          final current = _viewport ?? viewport;
                          final worldMm = Offset(
                            (local.dx - current.pan.dx) / current.scale,
                            (local.dy - current.pan.dy) / current.scale,
                          );

                          final rawFactor = 1.0 - (event.scrollDelta.dy * 0.001);
                          final zoomFactor =
                              (rawFactor).clamp(0.8, 1.25).toDouble();
                          final newScale = (current.scale * zoomFactor).clamp(
                            _minScalePxPerMm,
                            _maxScalePxPerMm,
                          );
                          final newPan = Offset(
                            local.dx - worldMm.dx * newScale,
                            local.dy - worldMm.dy * newScale,
                          );

                          setState(() {
                            _viewport = kp.Viewport(
                              scale: newScale,
                              pan: newPan,
                            );
                            _hasUserTransform = true;
                          });
                        },
                      );
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: (details) {
                        final box = _gestureBox();
                        if (box == null) return;
                        final localFocal = box.globalToLocal(
                          details.focalPoint,
                        );

                        final current = _viewport ?? viewport;
                        _gestureStartViewport = current;
                        _gestureWorldMm = Offset(
                          (localFocal.dx - current.pan.dx) / current.scale,
                          (localFocal.dy - current.pan.dy) / current.scale,
                        );
                      },
                      onScaleUpdate: (details) {
                        final box = _gestureBox();
                        final start = _gestureStartViewport;
                        final world = _gestureWorldMm;
                        if (box == null || start == null || world == null) {
                          return;
                        }

                        final localFocal = box.globalToLocal(
                          details.focalPoint,
                        );
                        final newScale = (start.scale * details.scale).clamp(
                          _minScalePxPerMm,
                          _maxScalePxPerMm,
                        );
                        final newPan = Offset(
                          localFocal.dx - world.dx * newScale,
                          localFocal.dy - world.dy * newScale,
                        );

                        setState(() {
                          _viewport = kp.Viewport(scale: newScale, pan: newPan);
                          _hasUserTransform = true;
                        });
                      },
                      child: CustomPaint(
                        painter: PagePainter(
                          page: _page,
                          grid: _grid,
                          viewport: _viewport ?? viewport,
                        ),
                        foregroundPainter: _isDynamicPreview
                            ? AnimatedToolPathPainter(
                                toolPath: toolPath,
                                viewport: _viewport ?? viewport,
                                progress: _animationController.value,
                                penWidthMm: 0.6,
                                showPenUp: _showPenUp,
                              )
                            : ToolPathPainter(
                                toolPath: toolPath,
                                viewport: _viewport ?? viewport,
                                penWidthMm: 0.6,
                                showPenUp: _showPenUp,
                              ),
                        size: size,
                      ),
                    ),
                  ),
                  if (toolPath.polylines.isEmpty)
                    const Center(
                      child: Text(
                        '请上传 GCode 文件预览',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
