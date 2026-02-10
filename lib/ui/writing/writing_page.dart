import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_selector/file_selector.dart';

import '../../core/download_helper.dart';
import '../../writing/font/stroke_font.dart';
import '../../writing/layout/grid_layout.dart';
import '../../writing/layout/stroke_optimizer.dart';
import '../../writing/model/essay_grid.dart';
import '../../writing/model/page.dart';
import '../../writing/model/toolpath.dart';
import '../../writing/model/toolpath_painter.dart';
import '../../writing/render/viewport.dart' as kp;
import '../../writing/export/gcode_exporter.dart';
import '../../state/printer_controller.dart';
import '../fluidd/widgets/fluidd_card.dart';

/// 文本编辑与预览页面
/// 用户输入文本 -> 生成 ToolPath -> 预览
class WritingPage extends StatefulWidget {
  const WritingPage({super.key});

  @override
  State<WritingPage> createState() => _WritingPageState();
}

class _WritingPageState extends State<WritingPage> {
  final _textController = TextEditingController(text: '一二十口人中');
  final _leftScrollController = ScrollController();
  final _rightScrollController = ScrollController();
  
  StrokeFont? _font;
  bool _fontLoading = true;
  String? _fontError;
  
  ToolPath _toolPath = ToolPath.empty;
  bool _showPenUp = true;
  WritingMode _writingMode = WritingMode.standard;
  
  // 页面和网格配置
  final PageMm _page = const PageMm(widthMm: 210, heightMm: 297);
  final EssayGridSpec _grid = defaultA4EssayGrid();
  
  // Viewport 管理
  kp.Viewport? _viewport;
  Size? _lastViewportSize;
  bool _hasUserTransform = false;
  
  static const double _fitPaddingPx = 10.0;
  static const double _minScalePxPerMm = 0.2;
  static const double _maxScalePxPerMm = 30.0;

  @override
  void initState() {
    super.initState();
    _loadFont();
    _textController.addListener(_onTextChanged);
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
        _fontLoading = false;
      });
      _generateToolPath();
    } catch (e) {
      if (!mounted) return;
      // 如果完整字库加载失败（例如尚未生成），回退到 Demo 字库
      print('加载完整字库失败: $e，尝试加载 Demo 字库');
      try {
        final demoFont = await StrokeFont.loadFromAsset('assets/fonts/demo_stroke_font_zh.json');
        if (!mounted) return;
        setState(() {
          _font = demoFont;
          _fontLoading = false;
        });
        _generateToolPath();
      } catch (e2) {
        if (!mounted) return;
        setState(() {
          _fontError = e.toString();
          _fontLoading = false;
        });
      }
    }
  }

  void _onTextChanged() {
    _generateToolPath();
  }

  void _generateToolPath() {
    final font = _font;
    if (font == null) return;
    
    final options = GridLayoutOptions(mode: _writingMode);
    final layout = EssayGridLayout(grid: _grid, font: font, options: options);
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

  @override
  Widget build(BuildContext context) {
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

              return CustomPaint(
                size: size,
                painter: _CombinedPainter(
                  page: _page,
                  grid: _grid,
                  toolPath: _toolPath,
                  viewport: viewport,
                  showPenUp: _showPenUp,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 组合绘制器：绘制页面、网格和工具路径
class _CombinedPainter extends CustomPainter {
  final PageMm page;
  final EssayGridSpec grid;
  final ToolPath toolPath;
  final kp.Viewport viewport;
  final bool showPenUp;

  _CombinedPainter({
    required this.page,
    required this.grid,
    required this.toolPath,
    required this.viewport,
    required this.showPenUp,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 绘制白色纸张背景
    final paperRect = viewport.mmRectToPx(
      Rect.fromLTWH(0, 0, page.widthMm, page.heightMm),
    );
    canvas.drawRect(
      paperRect,
      Paint()..color = Colors.white,
    );

    // 2. 绘制作文格
    _drawGrid(canvas);

    // 3. 绘制工具路径
    final pathPainter = ToolPathPainter(
      toolPath: toolPath,
      viewport: viewport,
      showPenUp: showPenUp,
    );
    pathPainter.paint(canvas, size);
  }

  void _drawGrid(Canvas canvas) {
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.pink.shade200;

    for (int r = 0; r < grid.rows; r++) {
      for (int c = 0; c < grid.cols; c++) {
        final left = grid.marginLeftMm + c * grid.cellMm;
        final top = grid.marginTopMm + r * grid.cellMm;
        final rect = Rect.fromLTWH(left, top, grid.cellMm, grid.cellMm);
        final pxRect = viewport.mmRectToPx(rect);
        canvas.drawRect(pxRect, gridPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CombinedPainter oldDelegate) {
    return oldDelegate.toolPath != toolPath ||
        oldDelegate.viewport != viewport ||
        oldDelegate.showPenUp != showPenUp;
  }
}
