import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_selector/file_selector.dart';

import '../../core/download_helper.dart';
import '../../style_learning/models/style_params.dart';
import '../../style_learning/services/style_profile_store.dart';
import '../../writing/font/stroke_font.dart';
import '../../writing/layout/grid_layout.dart';
import '../../writing/model/essay_grid.dart';
import '../../writing/model/page.dart';
import '../../writing/model/paper_type.dart';
import '../../writing/model/toolpath.dart';
import '../../writing/model/toolpath_painter.dart';
import '../../writing/render/viewport.dart' as kp;
import '../../writing/render/paper_type_painter.dart';
import '../../writing/export/gcode_exporter.dart';
import '../../state/printer_controller.dart';
import '../../state/paper_config_controller.dart';
import '../fluidd/widgets/fluidd_card.dart';

/// 文本编辑与预览页面
/// 用户输入文本 -> 生成 ToolPath -> 预览
class WritingPage extends StatefulWidget {
  const WritingPage({super.key});

  @override
  State<WritingPage> createState() => _WritingPageState();
}

class _WritingPageState extends State<WritingPage> {
  final _textController = TextEditingController(text: '你好世界\n欢迎使用手写路径生成器');
  final _leftScrollController = ScrollController();
  final _rightScrollController = ScrollController();
  
  StrokeFont? _font;
  
  ToolPath _toolPath = ToolPath.empty;
  bool _showPenUp = true;
  WritingMode _writingMode = WritingMode.standard;
  final StyleProfileStore _styleProfileStore = StyleProfileStore();
  SavedStyleProfile? _learnedStyleProfile;
  bool _applyLearnedStyle = false;
  double _fontSizeScale = 1.0;
  PaperConfig? _lastPaperConfig; // 追踪纸张配置变化
  
  // Viewport 管理
  kp.Viewport? _viewport;
  Size? _lastViewportSize;
  bool _hasUserTransform = false;
  double _gestureStartScale = 1.0;
  Offset _gestureStartPan = Offset.zero;
  Offset _gestureStartFocal = Offset.zero;
  
  static const double _fitPaddingPx = 10.0;
  static const double _minScalePxPerMm = 0.2;
  static const double _maxScalePxPerMm = 30.0;

  // 从 PaperConfigController 获取当前纸张配置
  PaperConfig get _paperConfig {
    try {
      return context.read<PaperConfigController>().activePaper;
    } catch (_) {
      return defaultGridPaper();
    }
  }

  PageMm get _page => PageMm(
    widthMm: _paperConfig.pageWidthMm,
    heightMm: _paperConfig.pageHeightMm,
  );

  @override
  void initState() {
    super.initState();
    _loadLearnedStyle();
    _loadFont();
    _textController.addListener(_onTextChanged);
  }
  Future<void> _loadLearnedStyle() async {
    final profile = await _styleProfileStore.loadLatest();
    if (!mounted) return;
    setState(() {
      _learnedStyleProfile = profile;
      _applyLearnedStyle = profile != null;
    });
    _generateToolPath();
  }


  @override
  void dispose() {
    _textController.dispose();
    _leftScrollController.dispose();
    _rightScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFont() async {
    try {
      // 优先尝试加载完整字库，如果文件太大或加载慢，可以考虑切分或异步流式加载
      final font = await StrokeFont.loadFromAsset('assets/fonts/makemeahanzi_standard.json');
      if (!mounted) return;
      setState(() {
        _font = font;
      });
      _generateToolPath();
    } catch (e) {
      if (!mounted) return;
      // 如果完整字库加载失败（例如尚未生成），回退到 Demo 字库
      try {
        final demoFont = await StrokeFont.loadFromAsset('assets/fonts/demo_stroke_font_zh.json');
        if (!mounted) return;
        setState(() {
          _font = demoFont;
        });
        _generateToolPath();
      } catch (e2) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(content: Text('字库加载失败: $e2')),
        );
      }
    }
  }

  StyleParams? get _effectiveStyleParams {
    final base = (_applyLearnedStyle ? _learnedStyleProfile?.params : null) ??
        StyleParams.identity;

    // 将用户字号缩放叠加到风格参数的 sizeRatio 上
    final scaledSize = (base.sizeRatio * _fontSizeScale).clamp(0.5, 2.0);

    if (!_applyLearnedStyle && (_fontSizeScale - 1.0).abs() < 0.001) {
      return null;
    }

    return StyleParams(
      sizeRatio: scaledSize,
      xOffsetRatio: base.xOffsetRatio,
      yOffsetRatio: base.yOffsetRatio,
      xStretch: base.xStretch,
      yStretch: base.yStretch,
      slantAngle: base.slantAngle,
      strokeWeight: base.strokeWeight,
      strokeAngleOffsets: base.strokeAngleOffsets,
      strokeLengthScales: base.strokeLengthScales,
      positionJitter: base.positionJitter,
      pointNoise: base.pointNoise,
      sizeVariation: base.sizeVariation,
    );
  }

  void _onTextChanged() {
    _generateToolPath();
  }

  void _generateToolPath() {
    final font = _font;
    if (font == null) return;
    
    final paperCtrl = context.read<PaperConfigController>();
    final config = paperCtrl.activePaper;
    final grid = EssayGridSpec(
      cellMm: config.cellSizeMm,
      marginLeftMm: config.marginLeftMm,
      marginTopMm: config.marginTopMm,
      cols: config.cols,
      rows: config.rows,
    );
    
    final options = GridLayoutOptions(
      mode: _writingMode,
      cellPaddingMm: config.cellPaddingMm,
      cellHeightMm: config.effectiveCellHeight,
      gridRowSpacingMm: config.gridRowSpacingMm,
      verticalFirst: config.kind == PaperTypeKind.letter,
      styleParams: _effectiveStyleParams,
    );
    final layout = GridLayout(grid: grid, font: font, options: options);
    final newPath = layout.layoutText(_textController.text);
    
    setState(() {
      _toolPath = newPath;
    });
  }

  kp.Viewport _fitViewport(Size size) {
    final availW = (size.width - _fitPaddingPx * 2).clamp(1.0, double.infinity);
    final availH = (size.height - _fitPaddingPx * 2).clamp(1.0, double.infinity);

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

  Future<void> _handleSave() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final exporter = GcodeExporter();
      final gcode = exporter.export(_toolPath);
      final fileName = 'writing_${DateTime.now().millisecondsSinceEpoch}.gcode';

      if (kIsWeb) {
        final bytes = Uint8List.fromList(utf8.encode(gcode));
        await downloadBytes(
          bytes: bytes,
          filename: fileName,
          mimeType: 'text/plain',
        );
        messenger.showSnackBar(
          const SnackBar(content: Text('正在下载 GCode 文件...')),
        );
      } else {
        // 桌面端处理
        final FileSaveLocation? result = await getSaveLocation(
          suggestedName: fileName,
          acceptedTypeGroups: [
            const XTypeGroup(label: 'GCode', extensions: ['gcode']),
          ],
        );

        if (result != null) {
          final File file = File(result.path);
          await file.writeAsString(gcode);
          messenger.showSnackBar(
            SnackBar(content: Text('文件已保存到: ${result.path}')),
          );
        }
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    }
  }

  Future<void> _handleUpload() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final exporter = GcodeExporter();
      final gcode = exporter.export(_toolPath);
      final filename = "writing_${DateTime.now().millisecondsSinceEpoch}.gcode";
      
      final printer = context.read<PrinterController>();
      final remotePath = await printer.uploadGcode(
        filename: filename,
        gcode: gcode,
      );

      if (remotePath != null) {
        messenger.showSnackBar(
          SnackBar(content: Text('已上传到: $remotePath')),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text('上传失败: ${printer.lastError}')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('错误: $e')),
      );
    }
  }

  kp.Viewport _ensureViewport(Size size) {
    if (_viewport == null || (!_hasUserTransform && _lastViewportSize != size)) {
      _viewport = _fitViewport(size);
    }
    _lastViewportSize = size;
    return _viewport!;
  }

  void _resetView() {
    final size = _lastViewportSize;
    if (size == null) return;
    setState(() {
      _viewport = _fitViewport(size);
      _hasUserTransform = false;
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    final viewport = _viewport;
    if (viewport == null) return;
    _gestureStartScale = viewport.scale;
    _gestureStartPan = viewport.pan;
    _gestureStartFocal = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final startScale = _gestureStartScale;
    final newScale = (startScale * details.scale).clamp(_minScalePxPerMm, _maxScalePxPerMm);

    final startWorldX = (_gestureStartFocal.dx - _gestureStartPan.dx) / startScale;
    final startWorldY = (_gestureStartFocal.dy - _gestureStartPan.dy) / startScale;

    final focal = details.localFocalPoint;
    final newPan = Offset(
      focal.dx - startWorldX * newScale,
      focal.dy - startWorldY * newScale,
    );

    setState(() {
      _viewport = kp.Viewport(scale: newScale, pan: newPan);
      _hasUserTransform = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 监听纸张配置变化，自动重新生成路径
    final paperCtrl = context.watch<PaperConfigController>();
    final currentConfig = paperCtrl.activePaper;
    
    // 当纸张配置变化时重新生成路径
    if (_lastPaperConfig != currentConfig) {
      _lastPaperConfig = currentConfig;
      if (_font != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _generateToolPath();
        });
      }
    }
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：文本输入区域
          Expanded(
            flex: 4,
            child: Scrollbar(
              controller: _leftScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _leftScrollController,
                child: Column(
                  children: [
                    _buildInputCard(),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // 右侧：预览区域
          Expanded(
            flex: 6,
            child: Scrollbar(
              controller: _rightScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _rightScrollController,
                padding: const EdgeInsets.only(right: 12), // 留出滚动条空间
                child: _buildPreviewCard(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputCard() {
    return FluiddCard(
      title: '文本输入',
      actions: [
        IconButton(
          icon: const Icon(Icons.clear, color: Colors.grey, size: 20),
          onPressed: () {
            _textController.clear();
          },
          tooltip: '清空文本',
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _textController,
            maxLines: 8,
            style: const TextStyle(
              fontSize: 16,
              height: 1.5,
            ),
            decoration: InputDecoration(
              hintText: '请输入要写的文字...\n支持中文字符',
              hintStyle: TextStyle(color: Colors.grey.shade600),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade700),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade700),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.blue),
              ),
              filled: true,
              fillColor: Colors.black26,
            ),
          ),
          const SizedBox(height: 12),
          // 书写模式选择
          Row(
            children: [
              const Icon(Icons.speed, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              const Text(
                '书写模式：',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('标准'),
                selected: _writingMode == WritingMode.standard,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _writingMode = WritingMode.standard);
                    _generateToolPath();
                  }
                },
                selectedColor: Colors.blue.shade700,
                backgroundColor: Colors.grey.shade800,
                labelStyle: TextStyle(
                  color: _writingMode == WritingMode.standard 
                      ? Colors.white 
                      : Colors.grey.shade400,
                  fontSize: 11,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('快速'),
                selected: _writingMode == WritingMode.fast,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _writingMode = WritingMode.fast);
                    _generateToolPath();
                  }
                },
                selectedColor: Colors.orange.shade700,
                backgroundColor: Colors.grey.shade800,
                labelStyle: TextStyle(
                  color: _writingMode == WritingMode.fast 
                      ? Colors.white 
                      : Colors.grey.shade400,
                  fontSize: 11,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.auto_fix_high, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _learnedStyleProfile == null
                      ? '未检测到已保存风格参数'
                      : '应用学习风格（${_learnedStyleProfile!.templateName}，${_learnedStyleProfile!.sampleCount}样本）',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
              ),
              Switch(
                value: _applyLearnedStyle && _learnedStyleProfile != null,
                onChanged: _learnedStyleProfile == null
                    ? null
                    : (v) {
                        setState(() => _applyLearnedStyle = v);
                        _generateToolPath();
                      },
              ),
            ],
          ),
          if (_learnedStyleProfile != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.text_fields, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                SizedBox(
                  width: 74,
                  child: Text('字体大小',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                ),
                Expanded(
                  child: Slider(
                    value: _fontSizeScale,
                    min: 0.6,
                    max: 1.6,
                    divisions: 20,
                    onChanged: (v) {
                      setState(() => _fontSizeScale = v);
                      _generateToolPath();
                    },
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    _fontSizeScale.toStringAsFixed(2),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _writingMode == WritingMode.fast
                      ? '快速模式：优化笔画顺序，减少抬笔移动'
                      : '标准模式：遵循汉字标准笔顺',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '当前输入 ${_textController.text.replaceAll('\n', '').length} 个字符',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

// 以前的 _buildFontInfoCard 相关代码已移除

  Widget _buildPreviewCard() {
    return FluiddCard(
      title: '路径预览',
      subtitle: '(提示: 使用触摸板进行缩放)',
      actions: [
        // 笔画统计
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${_toolPath.polylines.where((p) => p.penDown).length} 笔画',
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '保存 GCode 到本地',
          icon: const Icon(Icons.save_outlined, color: Colors.grey, size: 20),
          onPressed: _toolPath.polylines.isEmpty ? null : _handleSave,
        ),
        IconButton(
          tooltip: '上传 GCode 到打印机',
          icon: const Icon(Icons.cloud_upload_outlined, color: Colors.grey, size: 20),
          onPressed: _toolPath.polylines.isEmpty ? null : _handleUpload,
        ),
        IconButton(
          tooltip: _showPenUp ? '隐藏抬笔轨迹' : '显示抬笔轨迹',
          icon: Icon(
            _showPenUp ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: Colors.grey,
            size: 20,
          ),
          onPressed: () {
            setState(() => _showPenUp = !_showPenUp);
          },
        ),
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.grey, size: 20),
          onPressed: _resetView,
          tooltip: '重置视图',
        ),
      ],
      child: AspectRatio(
        aspectRatio: _page.widthMm / _page.heightMm,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF333333),
            borderRadius: BorderRadius.circular(4),
          ),
          clipBehavior: Clip.hardEdge,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              final viewport = _ensureViewport(size);

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                child: CustomPaint(
                  size: size,
                  painter: _CombinedPainter(
                    paperConfig: _paperConfig,
                    toolPath: _toolPath,
                    viewport: viewport,
                    showPenUp: _showPenUp,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 组合绘制器：绘制纸张网格和工具路径
class _CombinedPainter extends CustomPainter {
  final PaperConfig paperConfig;
  final ToolPath toolPath;
  final kp.Viewport viewport;
  final bool showPenUp;

  _CombinedPainter({
    required this.paperConfig,
    required this.toolPath,
    required this.viewport,
    required this.showPenUp,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 绘制纸张和网格（使用 PaperTypePainter）
    final paperPainter = PaperTypePainter(
      config: paperConfig,
      viewport: viewport,
    );
    paperPainter.paint(canvas, size);

    // 2. 绘制工具路径
    final pathPainter = ToolPathPainter(
      toolPath: toolPath,
      viewport: viewport,
      showPenUp: showPenUp,
    );
    pathPainter.paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _CombinedPainter oldDelegate) {
    return oldDelegate.toolPath != toolPath ||
        oldDelegate.viewport != viewport ||
        oldDelegate.showPenUp != showPenUp ||
        oldDelegate.paperConfig != paperConfig;
  }
}
