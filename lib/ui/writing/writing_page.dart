import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:provider/provider.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as img;

import '../../core/download_helper.dart';
import '../../state/printer_controller.dart';
import '../../ui/surface/dxf_toolpath.dart';
import '../../writing/engraving/dxf_engraver.dart';
import '../../writing/engraving/raster_engraver.dart';
import '../../writing/font/stroke_font.dart';
import '../../writing/layout/grid_layout.dart';
import '../../writing/model/essay_grid.dart';
import '../../writing/model/geometry.dart';
import '../../writing/model/glyph.dart';
import '../../writing/model/page.dart';
import '../../writing/model/paper_type.dart';
import '../../writing/model/animated_toolpath_painter.dart';
import '../../writing/model/toolpath.dart';
import '../../writing/model/toolpath_painter.dart';
import '../../writing/model/start_point_config.dart';
import '../../writing/render/viewport.dart' as kp;
import '../../writing/render/paper_type_painter.dart';
import '../../writing/export/gcode_exporter.dart';
import '../../writing/export/visual_compensation.dart';
import '../../state/paper_config_controller.dart';
import '../../state/user_font_controller.dart';
import '../fluidd/widgets/fluidd_card.dart';
import '../paper/paper_settings_page.dart';
import 'widgets/glyph_widgets.dart';

/// 字体书写页面
/// 主界面：文本编辑 + 路径预览
/// 二级界面：纸张设置（通过按钮进入）
class WritingPage extends StatefulWidget {
  const WritingPage({super.key});

  @override
  State<WritingPage> createState() => _WritingPageState();
}

enum WritingLayoutDirection { longEdge, shortEdge }

enum LaserWorkMode { writing, engraving }

class _WritingPageState extends State<WritingPage>
    with SingleTickerProviderStateMixin {
  final _textController = TextEditingController(text: 'AI赋能设计，设计点亮AI！');
  final _laserPowerController = TextEditingController(text: '30');
  final _writingSpeedController = TextEditingController(text: '25');
  final _traceBorderPowerController = TextEditingController(text: '1');
  final _engravingWidthController = TextEditingController(text: '80');
  final _engravingHeightController = TextEditingController(text: '60');
  final _engravingStepController = TextEditingController(text: '0.5');
  final _engravingSpeedController = TextEditingController(text: '20');
  final _engravingFocusZController = TextEditingController(text: '50');
  final _dxfOffsetXController = TextEditingController(text: '0');
  final _dxfOffsetYController = TextEditingController(text: '0');
  final _dxfRotationController = TextEditingController(text: '0');
  final _laserPowerFocus = FocusNode();
  final _leftScrollController = ScrollController();
  final _rightScrollController = ScrollController();
  final GlobalKey _gestureKey = GlobalKey();
  late final AnimationController _animationController;
  bool _isDynamicPreview = false;
  double _playbackSpeed = 1.0;

  StrokeFont? _font;

  ToolPath _toolPath = ToolPath.empty;
  bool _showPenUp = true;
  bool _showStartPointMarker = true; // 是否显示起点标记
  WritingMode _writingMode = WritingMode.standard;
  WritingLayoutDirection _layoutDirection = WritingLayoutDirection.longEdge;
  LaserWorkMode _laserWorkMode = LaserWorkMode.writing;
  double _laserPowerPercent = 30;
  double _writingSpeedMmPerS = 25;
  double _traceBorderPowerPercent = 1;
  bool _laserSending = false;
  Uint8List? _engravingImageBytes;
  img.Image? _engravingImage;
  String? _engravingFileName;
  DxfToolpath? _engravingDxf;
  String? _engravingDxfPath;
  String? _engravingDxfWarning;
  double _engravingWidthMm = 80;
  double _engravingHeightMm = 60;
  double _engravingStepMm = 0.5;
  double _engravingSpeedMmPerS = 20;
  double _engravingFocusZMm = 50;
  double _dxfOffsetXmm = 0;
  double _dxfOffsetYmm = 0;
  double _dxfRotationDeg = 0;
  bool _dxfMirrorX = false;
  double _engravingThreshold = 128;
  bool _engravingInvert = false;
  bool _engravingKeepAspect = true;
  VisualCompensationTransform? _visualCompensation;
  PaperConfig? _lastPaperConfig; // 追踪纸张配置变化

  // 起点配置
  WritingStartPointConfig _startPointConfig =
      WritingStartPointConfig.defaultConfig;

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
  static const double _laserMinPercent = 0.0;
  static const double _laserMaxPercent = 100.0;
  static const double _writingLaserZMm = 50.0;

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

  bool get _isShortEdgeLayout =>
      _layoutDirection == WritingLayoutDirection.shortEdge;

  PaperConfig get _previewPaperConfig {
    final config = _paperConfig;
    if (!_isShortEdgeLayout) return config;
    return _shortEdgeViewConfig(config);
  }

  PageMm get _previewPage => PageMm(
    widthMm: _previewPaperConfig.pageWidthMm,
    heightMm: _previewPaperConfig.pageHeightMm,
  );

  ToolPath get _previewToolPath =>
      _isShortEdgeLayout ? _transposeToolPath(_toolPath) : _toolPath;

  UserFontController? _userFontCtrl;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    _animationController.addListener(() {
      setState(() {});
    });
    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _isDynamicPreview = false;
        });
      }
    });
    _loadFont();
    _refreshVisualCompensation();
    _textController.addListener(_onTextChanged);
    _loadStartPointConfig();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 监听用户字体切换，自动重新渲染
    final newCtrl = context.read<UserFontController>();
    if (!identical(newCtrl, _userFontCtrl)) {
      _userFontCtrl?.removeListener(_onFontChanged);
      _userFontCtrl = newCtrl;
      _userFontCtrl!.addListener(_onFontChanged);
    }
  }

  void _onFontChanged() {
    if (_laserWorkMode == LaserWorkMode.writing) _generateToolPath();
  }

  @override
  void dispose() {
    _userFontCtrl?.removeListener(_onFontChanged);
    _textController.dispose();
    _laserPowerController.dispose();
    _writingSpeedController.dispose();
    _traceBorderPowerController.dispose();
    _engravingWidthController.dispose();
    _engravingHeightController.dispose();
    _engravingStepController.dispose();
    _engravingSpeedController.dispose();
    _engravingFocusZController.dispose();
    _dxfOffsetXController.dispose();
    _dxfOffsetYController.dispose();
    _dxfRotationController.dispose();
    _laserPowerFocus.dispose();
    _leftScrollController.dispose();
    _rightScrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadFont() async {
    try {
      // 优先尝试加载完整字库，如果文件太大或加载慢，可以考虑切分或异步流式加载
      final zhFont = await StrokeFont.loadFromAsset(
        'assets/fonts/makemeahanzi_standard.json',
      );
      final latinFont = await _loadLatinFallbackFont();
      final font = StrokeFont.merge([zhFont, latinFont]);
      if (!mounted) return;
      setState(() {
        _font = font;
      });
      // 注入标准字库到 UserFontController，供用户字体回退使用
      if (mounted) context.read<UserFontController>().setStandardFont(font);
      _generateToolPath();
    } catch (e) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(SnackBar(content: Text('字库加载失败: $e')));
    }
  }

  Future<StrokeFont> _loadLatinFallbackFont() async {
    return StrokeFont.loadFromAsset('assets/fonts/hershey_simplex_latin.json');
  }

  void _onTextChanged() {
    if (_laserWorkMode == LaserWorkMode.writing) _generateToolPath();
  }

  // 起点配置相关方法
  void _setLaserPowerPercent(double value, {bool updateText = true}) {
    final next = value
        .clamp(_laserMinPercent, _laserMaxPercent)
        .roundToDouble();
    setState(() => _laserPowerPercent = next);
    if (updateText) {
      _laserPowerController.text = next.round().toString();
      _laserPowerController.selection = TextSelection.collapsed(
        offset: _laserPowerController.text.length,
      );
    }
  }

  void _commitLaserPowerInput() {
    final parsed = double.tryParse(_laserPowerController.text.trim());
    if (parsed == null) {
      _setLaserPowerPercent(_laserPowerPercent);
      return;
    }
    _setLaserPowerPercent(parsed);
  }

  void _setWritingSpeedMmPerS(double value, {bool updateText = true}) {
    final next = value.clamp(1.0, 100.0).toDouble();
    setState(() => _writingSpeedMmPerS = next);
    if (updateText) {
      _writingSpeedController.text = _formatMm(next);
      _writingSpeedController.selection = TextSelection.collapsed(
        offset: _writingSpeedController.text.length,
      );
    }
  }

  void _commitWritingSpeedInput() {
    final parsed = double.tryParse(_writingSpeedController.text.trim());
    if (parsed == null || !parsed.isFinite) {
      _setWritingSpeedMmPerS(_writingSpeedMmPerS);
      return;
    }
    _setWritingSpeedMmPerS(parsed);
  }

  void _setTraceBorderPowerPercent(double value, {bool updateText = true}) {
    final next = value
        .clamp(_laserMinPercent, _laserMaxPercent)
        .roundToDouble();
    setState(() => _traceBorderPowerPercent = next);
    if (updateText) {
      _traceBorderPowerController.text = next.round().toString();
      _traceBorderPowerController.selection = TextSelection.collapsed(
        offset: _traceBorderPowerController.text.length,
      );
    }
  }

  void _commitTraceBorderPowerInput() {
    final parsed = double.tryParse(_traceBorderPowerController.text.trim());
    if (parsed == null) {
      _setTraceBorderPowerPercent(_traceBorderPowerPercent);
      return;
    }
    _setTraceBorderPowerPercent(parsed);
  }

  String _laserSetPinCommand(double percent) {
    final value =
        percent.clamp(_laserMinPercent, _laserMaxPercent) / _laserMaxPercent;
    return 'SET_PIN PIN=laser VALUE=${value.toStringAsFixed(3)}';
  }

  Future<void> _applyLaserPower() async {
    if (_laserSending) return;
    _commitLaserPowerInput();
    setState(() => _laserSending = true);
    final messenger = ScaffoldMessenger.of(context);
    final error = await context.read<PrinterController>().setLaserPower(
      _laserPowerPercent,
      maxPower: _laserMaxPercent,
    );
    if (!mounted) return;
    setState(() => _laserSending = false);
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _loadStartPointConfig() async {
    final config = await WritingStartPointConfig.load();
    if (mounted) {
      setState(() => _startPointConfig = config);
    }
  }

  Future<void> _setStartPoint() async {
    final printer = context.read<PrinterController>();

    // 检查连接状态
    if (printer.phase != AppConnPhase.connected) {
      _showMessage('未连接到打印机', isError: true);
      return;
    }

    // 检查工具头位置
    await printer.refreshAllStatus();
    final pos = printer.currentPosition;
    if (pos == null || pos.length < 3) {
      _showMessage('无法获取工具头位置', isError: true);
      return;
    }

    final newOffset = Offset(pos[0], pos[1]);
    final newConfig = _startPointConfig.withCustomStartPoint(
      newOffset,
      z: pos[2],
    );

    await newConfig.save();
    if (mounted) {
      setState(() => _startPointConfig = newConfig);
      _showMessage(
        '起点已设置: X: ${pos[0].toStringAsFixed(2)}, Y: ${pos[1].toStringAsFixed(2)}, Z: ${pos[2].toStringAsFixed(2)} mm',
      );
    }
  }

  Future<void> _resetStartPoint() async {
    final defaultConfig = WritingStartPointConfig.defaultConfig;
    await defaultConfig.save();
    if (mounted) {
      setState(() => _startPointConfig = defaultConfig);
      _showMessage('起点已重置为默认原点');
    }
  }

  /// 刷新打印机状态（急停重启后使用）
  Future<void> _refreshPrinterStatus() async {
    final printer = context.read<PrinterController>();

    if (printer.phase != AppConnPhase.connected) {
      _showMessage('未连接到打印机', isError: true);
      return;
    }

    try {
      await printer.refreshAllStatus();
      _showMessage('状态已刷新');
    } catch (e) {
      _showMessage('刷新失败: $e', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
      ),
    );
  }

  void _generateToolPath() {
    if (_laserWorkMode == LaserWorkMode.engraving) {
      _generateEngravingToolPath();
      return;
    }
    _generateWritingToolPath();
  }

  void _generateWritingToolPath() {
    // 优先使用用户字体（若已激活），否则使用标准字库
    final userFont = context.read<UserFontController>().activeUserFont;
    final font = userFont ?? _font;
    if (font == null) return;

    final paperCtrl = context.read<PaperConfigController>();
    final config = paperCtrl.activePaper;
    final layoutConfig = _isShortEdgeLayout
        ? _shortEdgeViewConfig(config)
        : config;
    final grid = EssayGridSpec(
      cellMm: layoutConfig.cellSizeMm,
      marginLeftMm: layoutConfig.marginLeftMm,
      marginTopMm: layoutConfig.marginTopMm,
      cols: layoutConfig.cols,
      rows: layoutConfig.rows,
    );

    final options = GridLayoutOptions(
      mode: _writingMode,
      cellPaddingMm: layoutConfig.cellPaddingMm,
      cellHeightMm: layoutConfig.effectiveCellHeight,
      gridRowSpacingMm: layoutConfig.gridRowSpacingMm,
      verticalFirst: false,
    );
    final layout = GridLayout(grid: grid, font: font, options: options);
    final viewPath = layout.layoutText(_textController.text);
    final newPath = _isShortEdgeLayout
        ? _transposeToolPath(viewPath)
        : viewPath;

    setState(() {
      _toolPath = newPath;
      if (_isDynamicPreview) {
        _animationController.stop();
        _animationController.reset();
      }
      _isDynamicPreview = false;
    });
  }

  void _generateEngravingToolPath() {
    _commitEngravingInputs(updateText: false);
    final image = _engravingImage;
    final dxf = _engravingDxf;
    if (dxf != null) {
      _commitDxfTransformInputs(updateText: false);
    }
    if (image == null && dxf == null) {
      setState(() {
        _toolPath = ToolPath.empty;
        _isDynamicPreview = false;
      });
      return;
    }

    final config = context.read<PaperConfigController>().activePaper;
    final maxWidth = (config.pageWidthMm - config.marginLeftMm).clamp(
      1.0,
      config.pageWidthMm,
    );
    final maxHeight = (config.pageHeightMm - config.marginTopMm).clamp(
      1.0,
      config.pageHeightMm,
    );
    final width = _engravingWidthMm.clamp(1.0, maxWidth).toDouble();
    final height = _engravingHeightMm.clamp(1.0, maxHeight).toDouble();
    final path = dxf != null
        ? DxfEngraver.buildToolPath(
            dxf,
            options: DxfEngraveOptions(
              originXmm: config.marginLeftMm,
              originYmm: config.marginTopMm,
              widthMm: width,
              heightMm: height,
              keepAspectRatio: _engravingKeepAspect,
              mirrorX: _dxfMirrorX,
              rotationDeg: _dxfRotationDeg,
              translateXmm: _dxfOffsetXmm,
              translateYmm: _dxfOffsetYmm,
            ),
          )
        : RasterEngraver.buildToolPath(
            image!,
            options: RasterEngraveOptions(
              originXmm: config.marginLeftMm,
              originYmm: config.marginTopMm,
              widthMm: width,
              heightMm: height,
              stepMm: _engravingStepMm,
              threshold: _engravingThreshold,
              invert: _engravingInvert,
            ),
          );

    setState(() {
      _toolPath = path;
      if (_isDynamicPreview) {
        _animationController.stop();
        _animationController.reset();
      }
      _isDynamicPreview = false;
    });
  }

  void _commitEngravingInputs({bool updateText = true}) {
    final width = double.tryParse(_engravingWidthController.text.trim());
    final height = double.tryParse(_engravingHeightController.text.trim());
    final step = double.tryParse(_engravingStepController.text.trim());
    final speed = double.tryParse(_engravingSpeedController.text.trim());
    final focusZ = double.tryParse(_engravingFocusZController.text.trim());

    var nextWidth = (width ?? _engravingWidthMm).clamp(1.0, _page.widthMm);
    var nextHeight = (height ?? _engravingHeightMm).clamp(1.0, _page.heightMm);
    if (_engravingKeepAspect && width != null) {
      final image = _engravingImage;
      final dxf = _engravingDxf;
      if (image != null) {
        nextHeight = (nextWidth * image.height / image.width).clamp(
          1.0,
          _page.heightMm,
        );
      } else if (dxf != null && dxf.widthMm > 0) {
        nextHeight = (nextWidth * dxf.heightMm / dxf.widthMm).clamp(
          1.0,
          _page.heightMm,
        );
      }
    }

    _engravingWidthMm = nextWidth.toDouble();
    _engravingHeightMm = nextHeight.toDouble();
    _engravingStepMm = (step ?? _engravingStepMm).clamp(0.1, 5.0).toDouble();
    _engravingSpeedMmPerS = (speed ?? _engravingSpeedMmPerS)
        .clamp(1.0, 100.0)
        .toDouble();
    _engravingFocusZMm = (focusZ ?? _engravingFocusZMm)
        .clamp(0.0, 300.0)
        .toDouble();

    if (updateText) {
      _engravingWidthController.text = _formatMm(_engravingWidthMm);
      _engravingHeightController.text = _formatMm(_engravingHeightMm);
      _engravingStepController.text = _formatMm(_engravingStepMm);
      _engravingSpeedController.text = _formatMm(_engravingSpeedMmPerS);
      _engravingFocusZController.text = _formatMm(_engravingFocusZMm);
    }
  }

  void _commitDxfTransformInputs({bool updateText = true}) {
    final offsetX = double.tryParse(_dxfOffsetXController.text.trim());
    final offsetY = double.tryParse(_dxfOffsetYController.text.trim());
    final rotation = double.tryParse(_dxfRotationController.text.trim());

    final nextOffsetX = offsetX?.isFinite == true ? offsetX! : _dxfOffsetXmm;
    final nextOffsetY = offsetY?.isFinite == true ? offsetY! : _dxfOffsetYmm;
    final nextRotation = rotation?.isFinite == true
        ? rotation!
        : _dxfRotationDeg;

    _dxfOffsetXmm = nextOffsetX.clamp(-_page.widthMm, _page.widthMm).toDouble();
    _dxfOffsetYmm = nextOffsetY
        .clamp(-_page.heightMm, _page.heightMm)
        .toDouble();
    _dxfRotationDeg = nextRotation.clamp(-360.0, 360.0).toDouble();

    if (updateText) {
      _dxfOffsetXController.text = _formatMm(_dxfOffsetXmm);
      _dxfOffsetYController.text = _formatMm(_dxfOffsetYmm);
      _dxfRotationController.text = _formatMm(_dxfRotationDeg);
    }
  }

  String _formatMm(double value) {
    final fixed = value.toStringAsFixed(2);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  Future<void> _pickEngravingImage() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Image',
          extensions: ['png', 'jpg', 'jpeg', 'bmp'],
        ),
      ],
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      _showMessage('图片解析失败', isError: true);
      return;
    }

    _commitEngravingInputs();
    var nextHeight = _engravingHeightMm;
    if (_engravingKeepAspect) {
      nextHeight = (_engravingWidthMm * decoded.height / decoded.width)
          .clamp(1.0, _page.heightMm)
          .toDouble();
    }

    setState(() {
      _engravingImageBytes = bytes;
      _engravingImage = decoded;
      _engravingFileName = file.name;
      _engravingDxf = null;
      _engravingDxfPath = null;
      _engravingDxfWarning = null;
      _engravingHeightMm = nextHeight;
      _engravingHeightController.text = _formatMm(nextHeight);
    });
    _generateToolPath();
  }

  Future<void> _pickEngravingDxf() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'DXF', extensions: ['dxf']),
      ],
    );
    if (file == null) return;

    try {
      final text = await file.readAsString();
      final dxf = DxfParser.parse(text, name: file.name);
      if (dxf.isEmpty) {
        _showMessage('DXF 没有可用几何', isError: true);
        return;
      }

      _commitEngravingInputs();
      var nextHeight = _engravingHeightMm;
      if (_engravingKeepAspect && dxf.widthMm > 0) {
        nextHeight = (_engravingWidthMm * dxf.heightMm / dxf.widthMm)
            .clamp(1.0, _page.heightMm)
            .toDouble();
      }
      final unsupported = dxf.unsupportedEntities.toList()..sort();

      setState(() {
        _engravingImageBytes = null;
        _engravingImage = null;
        _engravingFileName = null;
        _engravingDxf = dxf;
        _engravingDxfPath = file.path;
        _engravingDxfWarning = unsupported.isEmpty
            ? null
            : '已跳过: ${unsupported.take(8).join(', ')}';
        _engravingHeightMm = nextHeight;
        _dxfOffsetXmm = 0;
        _dxfOffsetYmm = 0;
        _dxfRotationDeg = 0;
        _dxfMirrorX = false;
        _engravingHeightController.text = _formatMm(nextHeight);
        _dxfOffsetXController.text = '0';
        _dxfOffsetYController.text = '0';
        _dxfRotationController.text = '0';
      });
      _generateToolPath();
    } catch (error) {
      _showMessage('DXF 导入失败: $error', isError: true);
    }
  }

  void _clearEngravingSource() {
    setState(() {
      _engravingImageBytes = null;
      _engravingImage = null;
      _engravingFileName = null;
      _engravingDxf = null;
      _engravingDxfPath = null;
      _engravingDxfWarning = null;
      _dxfMirrorX = false;
      _toolPath = ToolPath.empty;
      _isDynamicPreview = false;
    });
  }

  PaperConfig _shortEdgeViewConfig(PaperConfig config) {
    return config.copyWith(
      pageWidthMm: config.pageHeightMm,
      pageHeightMm: config.pageWidthMm,
      marginLeftMm: config.marginTopMm,
      marginTopMm: config.marginLeftMm,
      marginRightMm: config.marginBottomMm,
      marginBottomMm: config.marginRightMm,
      customCols: null,
      customRows: null,
    );
  }

  ToolPath _transposeToolPath(ToolPath source) {
    return ToolPath(
      polylines: [
        for (final polyline in source.polylines)
          ToolPolyline(
            penDown: polyline.penDown,
            points: [for (final p in polyline.points) Vec2(p.y, p.x)],
          ),
      ],
    );
  }

  void _toggleDynamicPreview() {
    if (_toolPath.polylines.isEmpty) return;

    setState(() {
      _isDynamicPreview = !_isDynamicPreview;
      if (_isDynamicPreview) {
        final totalPoints = _toolPath.polylines.fold(
          0,
          (sum, pl) => sum + pl.points.length,
        );
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
        final totalPoints = _toolPath.polylines.fold(
          0,
          (sum, pl) => sum + pl.points.length,
        );
        final baseSeconds = (totalPoints / 100).clamp(5, 120).toDouble();
        _animationController.duration = Duration(
          milliseconds: (baseSeconds * 1000 / _playbackSpeed).toInt(),
        );
        _animationController.forward(from: currentProgress);
      }
    });
  }

  kp.Viewport _fitViewport(Size size) {
    final availW = (size.width - _fitPaddingPx * 2).clamp(1.0, double.infinity);
    final availH = (size.height - _fitPaddingPx * 2).clamp(
      1.0,
      double.infinity,
    );

    double scale = availW / _previewPage.widthMm;
    if (_previewPage.heightMm * scale > availH) {
      scale = availH / _previewPage.heightMm;
    }
    scale = scale.clamp(_minScalePxPerMm, _maxScalePxPerMm);

    final contentW = _previewPage.widthMm * scale;
    final contentH = _previewPage.heightMm * scale;
    final pan = Offset(
      (size.width - contentW) / 2,
      (size.height - contentH) / 2,
    );

    return kp.Viewport(scale: scale, pan: pan);
  }

  double get _activeLaserZMm => _laserWorkMode == LaserWorkMode.engraving
      ? _engravingFocusZMm
      : _writingLaserZMm;

  GcodeExportOptions _machineExportOptions(
    VisualCompensationTransform? visualCompensation, {
    double? laserPowerPercent,
    double? writeSpeedMmPerS,
  }) => GcodeExportOptions(
    penUpCmd: _laserSetPinCommand(0),
    penDownCmd: _laserSetPinCommand(laserPowerPercent ?? _laserPowerPercent),
    writeSpeedMmPerS:
        writeSpeedMmPerS ??
        (_laserWorkMode == LaserWorkMode.engraving
            ? _engravingSpeedMmPerS
            : _writingSpeedMmPerS),
    pageWidthMm: _page.widthMm,
    pageHeightMm: _page.heightMm,
    defaultZMm: _activeLaserZMm,
    visualCompensation: visualCompensation,
  );

  String get _gcodeFilePrefix =>
      _laserWorkMode == LaserWorkMode.engraving ? 'engraving' : 'writing';

  Future<VisualCompensationTransform?> _refreshVisualCompensation() async {
    if (kIsWeb) return null;
    final visualCompensation = await VisualCompensationTransform.tryLoad();
    if (mounted) {
      setState(() => _visualCompensation = visualCompensation);
    }
    return visualCompensation;
  }

  Future<String> _buildMachineGcodeFor(
    ToolPath toolPath, {
    double? laserPowerPercent,
    double? writeSpeedMmPerS,
  }) async {
    if (_laserWorkMode == LaserWorkMode.writing && writeSpeedMmPerS == null) {
      _commitWritingSpeedInput();
    }
    final visualCompensation =
        await _refreshVisualCompensation() ?? _visualCompensation;
    final useManualStartOffset = _startPointConfig.hasCustomStartPoint;
    final z = _startPointConfig.hasCustomStartPoint
        ? _startPointConfig.z
        : _activeLaserZMm;

    return GcodeExporter().export(
      toolPath,
      opt: _machineExportOptions(
        visualCompensation,
        laserPowerPercent: laserPowerPercent,
        writeSpeedMmPerS: writeSpeedMmPerS,
      ),
      startPointOffset: useManualStartOffset ? _startPointConfig.offset : null,
      startPointZ: z,
    );
  }

  Future<String> _buildMachineGcode() => _buildMachineGcodeFor(_toolPath);

  ToolPath? _buildTraceBorderToolPath() {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;

    for (final polyline in _toolPath.polylines) {
      for (final point in polyline.points) {
        if (!point.x.isFinite || !point.y.isFinite) continue;
        if (point.x < minX) minX = point.x;
        if (point.y < minY) minY = point.y;
        if (point.x > maxX) maxX = point.x;
        if (point.y > maxY) maxY = point.y;
      }
    }

    if (!minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite) {
      return null;
    }
    if ((maxX - minX).abs() < 0.01 || (maxY - minY).abs() < 0.01) {
      return null;
    }

    return ToolPath(
      polylines: [
        ToolPolyline(
          penDown: true,
          points: [
            Vec2(minX, minY),
            Vec2(maxX, minY),
            Vec2(maxX, maxY),
            Vec2(minX, maxY),
            Vec2(minX, minY),
          ],
        ),
      ],
    );
  }

  Future<void> _handleSave() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final gcode = await _buildMachineGcode();
      final fileName =
          '${_gcodeFilePrefix}_${DateTime.now().millisecondsSinceEpoch}.gcode';

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
      messenger.showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
  }

  Future<void> _handleUpload() async {
    final messenger = ScaffoldMessenger.of(context);
    final printer = context.read<PrinterController>();
    try {
      final gcode = await _buildMachineGcode();
      final filename =
          '${_gcodeFilePrefix}_${DateTime.now().millisecondsSinceEpoch}.gcode';

      final remotePath = await printer.uploadGcode(
        filename: filename,
        gcode: gcode,
      );

      if (!mounted) return;
      if (remotePath != null) {
        messenger.showSnackBar(SnackBar(content: Text('已上传到: $remotePath')));
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text('上传失败: ${printer.lastError}')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('错误: $e')));
    }
  }

  Future<void> _handleTraceBorder() async {
    final messenger = ScaffoldMessenger.of(context);
    final printer = context.read<PrinterController>();
    try {
      _commitTraceBorderPowerInput();
      final borderPath = _buildTraceBorderToolPath();
      if (borderPath == null) {
        messenger.showSnackBar(const SnackBar(content: Text('当前图案无法生成边框')));
        return;
      }

      final gcode = await _buildMachineGcodeFor(
        borderPath,
        laserPowerPercent: _traceBorderPowerPercent,
      );
      final filename =
          '${_gcodeFilePrefix}_border_${DateTime.now().millisecondsSinceEpoch}.gcode';

      final remotePath = await printer.uploadGcode(
        filename: filename,
        gcode: gcode,
        startAfterUpload: true,
      );

      if (!mounted) return;
      if (remotePath != null) {
        messenger.showSnackBar(SnackBar(content: Text('正在走边框: $remotePath')));
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text('走边框失败: ${printer.lastError}')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('走边框错误: $e')));
    }
  }

  kp.Viewport _ensureViewport(Size size) {
    if (_viewport == null ||
        (!_hasUserTransform && _lastViewportSize != size)) {
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

  RenderBox? _gestureBox() {
    final ctx = _gestureKey.currentContext;
    final obj = ctx?.findRenderObject();
    if (obj is RenderBox) return obj;
    return null;
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
    final newScale = (startScale * details.scale).clamp(
      _minScalePxPerMm,
      _maxScalePxPerMm,
    );

    final startWorldX =
        (_gestureStartFocal.dx - _gestureStartPan.dx) / startScale;
    final startWorldY =
        (_gestureStartFocal.dy - _gestureStartPan.dy) / startScale;

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
      if ((_laserWorkMode == LaserWorkMode.writing && _font != null) ||
          (_laserWorkMode == LaserWorkMode.engraving &&
              (_engravingImage != null || _engravingDxf != null))) {
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
                    _buildLaserModeCard(),
                    const SizedBox(height: 8),
                    if (_laserWorkMode == LaserWorkMode.writing)
                      _buildInputCard()
                    else
                      _buildEngravingCard(),
                    const SizedBox(height: 8),
                    _buildPaperSettingsButton(),
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

  void _setLaserWorkMode(LaserWorkMode mode) {
    if (mode == _laserWorkMode) return;
    setState(() {
      _laserWorkMode = mode;
      _viewport = null;
      _lastViewportSize = null;
      _hasUserTransform = false;
    });
    _generateToolPath();
  }

  Widget _buildLaserModeCard() {
    return FluiddCard(
      title: '激光',
      scrollable: false,
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<LaserWorkMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment<LaserWorkMode>(
              value: LaserWorkMode.writing,
              icon: Icon(Icons.edit_note, size: 16),
              label: Text('写字'),
            ),
            ButtonSegment<LaserWorkMode>(
              value: LaserWorkMode.engraving,
              icon: Icon(Icons.grid_on, size: 16),
              label: Text('雕刻'),
            ),
          ],
          selected: {_laserWorkMode},
          onSelectionChanged: (selection) => _setLaserWorkMode(selection.first),
        ),
      ),
    );
  }

  Widget _buildEngravingCard() {
    final image = _engravingImage;
    final imageBytes = _engravingImageBytes;
    final dxf = _engravingDxf;
    final hasSource = image != null || dxf != null;

    return FluiddCard(
      title: '雕刻',
      scrollable: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
          tooltip: '导入图片',
          onPressed: _pickEngravingImage,
        ),
        IconButton(
          icon: const Icon(Icons.polyline_outlined, size: 20),
          tooltip: '导入 DXF',
          onPressed: _pickEngravingDxf,
        ),
        IconButton(
          icon: const Icon(Icons.clear, size: 20),
          tooltip: '清空文件',
          onPressed: hasSource ? _clearEngravingSource : null,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (imageBytes != null && image != null)
            Container(
              height: 160,
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade700),
              ),
              child: Image.memory(imageBytes, fit: BoxFit.contain),
            )
          else if (dxf != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade700),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.polyline_outlined,
                        color: Colors.lightBlueAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          dxf.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${dxf.polylines.length} 条 | ${dxf.pointCount} 点 | ${_formatMm(dxf.widthMm)} x ${_formatMm(dxf.heightMm)} mm',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
                  if (dxf.layers.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '图层: ${dxf.layers.take(8).join(', ')}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (_engravingDxfPath != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _engravingDxfPath!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  if (_engravingDxfWarning != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _engravingDxfWarning!,
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('导入图片'),
                    onPressed: _pickEngravingImage,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.polyline_outlined),
                    label: const Text('导入 DXF'),
                    onPressed: _pickEngravingDxf,
                  ),
                ),
              ],
            ),
          if (image != null) ...[
            const SizedBox(height: 8),
            Text(
              '${_engravingFileName ?? 'Image'}  ${image.width} x ${image.height}px',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildEngravingNumberField(
                  label: '宽度 mm',
                  controller: _engravingWidthController,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildEngravingNumberField(
                  label: '高度 mm',
                  controller: _engravingHeightController,
                ),
              ),
            ],
          ),
          if (dxf != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildEngravingNumberField(
                    label: 'X 平移 mm',
                    controller: _dxfOffsetXController,
                    onCommit: _commitDxfTransformInputs,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildEngravingNumberField(
                    label: 'Y 平移 mm',
                    controller: _dxfOffsetYController,
                    onCommit: _commitDxfTransformInputs,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildEngravingNumberField(
              label: '旋转 °',
              controller: _dxfRotationController,
              onCommit: _commitDxfTransformInputs,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.flip),
                label: Text(_dxfMirrorX ? '已水平镜像' : '水平镜像 DXF'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _dxfMirrorX
                      ? Colors.lightBlueAccent
                      : Colors.white70,
                  side: BorderSide(
                    color: _dxfMirrorX
                        ? Colors.lightBlueAccent
                        : Colors.grey.shade700,
                  ),
                ),
                onPressed: () {
                  setState(() => _dxfMirrorX = !_dxfMirrorX);
                  _generateToolPath();
                },
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (dxf == null) ...[
                Expanded(
                  child: _buildEngravingNumberField(
                    label: '行距 mm',
                    controller: _engravingStepController,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: _buildEngravingNumberField(
                  label: '速度 mm/s',
                  controller: _engravingSpeedController,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildEngravingNumberField(
            label: 'Focus Z mm',
            controller: _engravingFocusZController,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('保持比例', style: TextStyle(fontSize: 13)),
            value: _engravingKeepAspect,
            onChanged: (value) {
              setState(() => _engravingKeepAspect = value);
              _generateToolPath();
            },
          ),
          if (dxf == null) ...[
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('反相', style: TextStyle(fontSize: 13)),
              value: _engravingInvert,
              onChanged: (value) {
                setState(() => _engravingInvert = value);
                _generateToolPath();
              },
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.tonality, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                const Text(
                  '阈值',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  _engravingThreshold.round().toString(),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
            Slider(
              value: _engravingThreshold,
              min: 0,
              max: 255,
              divisions: 255,
              label: _engravingThreshold.round().toString(),
              onChanged: (value) {
                setState(() => _engravingThreshold = value.roundToDouble());
                _generateToolPath();
              },
            ),
          ],
          const SizedBox(height: 12),
          _buildLaserPowerControl(),
        ],
      ),
    );
  }

  Widget _buildEngravingNumberField({
    required String label,
    required TextEditingController controller,
    VoidCallback? onCommit,
  }) {
    void commit() {
      _commitEngravingInputs();
      onCommit?.call();
      _generateToolPath();
    }

    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))],
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      onSubmitted: (_) => commit(),
      onEditingComplete: commit,
    );
  }

  Widget _buildInputCard() {
    final userCtrl = context.watch<UserFontController>();
    final activeUserFont = userCtrl.activeUserFont;

    return FluiddCard(
      title: '写字',
      scrollable: false,
      actions: [
        if (activeUserFont != null)
          IconButton(
            icon: const Icon(
              Icons.grid_view_rounded,
              color: Colors.grey,
              size: 20,
            ),
            onPressed: () => _openGlyphPicker(userCtrl),
            tooltip: '字形选择库',
          ),
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
            style: const TextStyle(fontSize: 16, height: 1.5),
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
          _buildLayoutDirectionControl(),
          const SizedBox(height: 12),
          _buildLaserPowerControl(),
          const SizedBox(height: 12),
          _buildWritingSpeedControl(),
          const SizedBox(height: 8),

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

  Widget _buildWritingSpeedControl() {
    return Row(
      children: [
        const Icon(Icons.speed, size: 16, color: Colors.lightBlueAccent),
        const SizedBox(width: 8),
        const Text(
          '\u4e66\u5199\u901f\u5ea6',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const Spacer(),
        SizedBox(
          width: 118,
          child: TextField(
            controller: _writingSpeedController,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              suffixText: 'mm/s',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            ),
            onSubmitted: (_) => _commitWritingSpeedInput(),
            onEditingComplete: _commitWritingSpeedInput,
          ),
        ),
      ],
    );
  }

  Widget _buildLaserPowerControl() {
    final connected = context.select<PrinterController, bool>(
      (controller) => controller.phase == AppConnPhase.connected,
    );
    final canApply = connected && !_laserSending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.light_mode, size: 16, color: Colors.amber),
            const SizedBox(width: 8),
            const Text(
              '激光强度',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const Spacer(),
            Text(
              '${_laserPowerPercent.round()}%',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _laserPowerPercent,
                min: _laserMinPercent,
                max: _laserMaxPercent,
                divisions: _laserMaxPercent.toInt(),
                label: '${_laserPowerPercent.round()}%',
                onChanged: (value) => _setLaserPowerPercent(value),
              ),
            ),
            SizedBox(
              width: 76,
              child: TextField(
                controller: _laserPowerController,
                focusNode: _laserPowerFocus,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  suffixText: '%',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                ),
                onChanged: (text) {
                  final parsed = double.tryParse(text);
                  if (parsed != null) {
                    _setLaserPowerPercent(parsed, updateText: false);
                  }
                },
                onSubmitted: (_) => _commitLaserPowerInput(),
                onEditingComplete: _commitLaserPowerInput,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: '应用激光强度',
              icon: _laserSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt, size: 18),
              onPressed: canApply ? _applyLaserPower : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(
              Icons.crop_free,
              size: 16,
              color: Colors.lightBlueAccent,
            ),
            const SizedBox(width: 8),
            const Text(
              '走边框强度',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const Spacer(),
            SizedBox(
              width: 76,
              child: TextField(
                controller: _traceBorderPowerController,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  suffixText: '%',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                ),
                onChanged: (text) {
                  final parsed = double.tryParse(text);
                  if (parsed != null) {
                    _setTraceBorderPowerPercent(parsed, updateText: false);
                  }
                },
                onSubmitted: (_) => _commitTraceBorderPowerInput(),
                onEditingComplete: _commitTraceBorderPowerInput,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLayoutDirectionControl() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.text_rotation_none, size: 16, color: Colors.grey),
            SizedBox(width: 8),
            Text('排布方向：', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<WritingLayoutDirection>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment<WritingLayoutDirection>(
                value: WritingLayoutDirection.longEdge,
                icon: Icon(Icons.swap_horiz, size: 16),
                label: Text('沿长边'),
              ),
              ButtonSegment<WritingLayoutDirection>(
                value: WritingLayoutDirection.shortEdge,
                icon: Icon(Icons.swap_vert, size: 16),
                label: Text('沿短边'),
              ),
            ],
            selected: {_layoutDirection},
            onSelectionChanged: (selection) {
              final next = selection.first;
              if (next == _layoutDirection) return;
              setState(() {
                _layoutDirection = next;
                _viewport = null;
                _lastViewportSize = null;
                _hasUserTransform = false;
              });
              _generateToolPath();
            },
          ),
        ),
      ],
    );
  }

  // 以前的 _buildFontInfoCard 相关代码已移除

  // ────────────────────────────────────────────────────────────────────────
  // 纸张设置入口
  // ────────────────────────────────────────────────────────────────────────

  /// 打开纸张设置页面（全屏对话框）
  void _openPaperSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xFF181A1B),
          appBar: AppBar(
            backgroundColor: const Color(0xFF212529),
            title: const Text('纸张设置', style: TextStyle(color: Colors.white)),
            iconTheme: const IconThemeData(color: Colors.grey),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: const PaperSettingsPage(),
        ),
      ),
    );
  }

  Widget _buildPaperSettingsButton() {
    final paperCtrl = context.watch<PaperConfigController>();
    final config = paperCtrl.activePaper;

    return FluiddCard(
      title: '当前纸张',
      scrollable: false,
      actions: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${config.cols}列×${config.rows}行',
            style: const TextStyle(color: Colors.blue, fontSize: 11),
          ),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _paperInfoRow('纸张类型', _kindLabel(config.kind)),
          _paperInfoRow(
            '纸张尺寸',
            '${config.pageWidthMm.toStringAsFixed(0)} × ${config.pageHeightMm.toStringAsFixed(0)} mm',
          ),
          _paperInfoRow('格子', '${config.cellSizeMm.toStringAsFixed(1)} mm'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('修改纸张设置'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _openPaperSettings,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paperInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Text(
            value,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _kindLabel(PaperTypeKind kind) {
    switch (kind) {
      case PaperTypeKind.grid:
        return '格子纸';
      case PaperTypeKind.horizontal:
        return '横线格';
      case PaperTypeKind.letter:
        return '信纸笺';
      case PaperTypeKind.blank:
        return '空白纸';
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // 字形辅助方法
  // ────────────────────────────────────────────────────────────────────────

  /// 在光标处插入字符
  void _insertChar(String ch) {
    final text = _textController.text;
    final sel = _textController.selection;
    final pos = sel.isValid
        ? sel.extentOffset.clamp(0, text.length)
        : text.length;
    final newText = text.substring(0, pos) + ch + text.substring(pos);
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: pos + ch.length),
    );
  }

  /// 打开字形选择底部面板
  void _openGlyphPicker(UserFontController ctrl) {
    final profile = ctrl.activeProfile;
    if (profile == null || profile.learnedGlyphs.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _GlyphPickerSheet(
        glyphs: Map.unmodifiable(profile.learnedGlyphs),
        fontName: profile.name,
        onInsert: _insertChar,
      ),
    );
  }

  Widget _buildPreviewCard() {
    return FluiddCard(
      title: '路径预览',
      scrollable: false,
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
          icon: const Icon(
            Icons.cloud_upload_outlined,
            color: Colors.grey,
            size: 20,
          ),
          onPressed: _toolPath.polylines.isEmpty ? null : _handleUpload,
        ),
        IconButton(
          tooltip: '走边框（上传并开始）',
          icon: const Icon(
            Icons.crop_free,
            color: Colors.lightBlueAccent,
            size: 20,
          ),
          onPressed: _toolPath.polylines.isEmpty ? null : _handleTraceBorder,
        ),
        IconButton(
          tooltip: '刷新打印机状态（急停重启后使用）',
          icon: const Icon(Icons.refresh, color: Colors.orange, size: 20),
          onPressed: _refreshPrinterStatus,
        ),
        IconButton(
          tooltip: _startPointConfig.hasCustomStartPoint
              ? '起点: ${_startPointConfig.shortText} (点击重置)'
              : '设置起点（当前工具头位置）',
          icon: Icon(
            Icons.my_location,
            color: _startPointConfig.hasCustomStartPoint
                ? Colors.green
                : Colors.grey,
            size: 20,
          ),
          onPressed: _startPointConfig.hasCustomStartPoint
              ? _resetStartPoint
              : _setStartPoint,
        ),
        IconButton(
          tooltip: _isDynamicPreview ? '停止动态预览' : '动态预览',
          icon: Icon(
            _isDynamicPreview
                ? Icons.stop_circle_outlined
                : Icons.play_circle_outlined,
            color: _isDynamicPreview
                ? Colors.orange
                : (_toolPath.polylines.isEmpty
                      ? Colors.grey.shade600
                      : Colors.grey),
            size: 20,
          ),
          onPressed: _toolPath.polylines.isEmpty ? null : _toggleDynamicPreview,
        ),
        if (_isDynamicPreview)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<double>(
                value: _playbackSpeed,
                dropdownColor: const Color(0xFF2C3034),
                icon: const SizedBox.shrink(),
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                items: [0.1, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
                    .map(
                      (s) => DropdownMenuItem(value: s, child: Text('${s}x')),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) _updatePlaybackSpeed(v);
                },
              ),
            ),
          ),
        IconButton(
          tooltip: _showPenUp ? '隐藏抬笔轨迹' : '显示抬笔轨迹',
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
          tooltip: _showStartPointMarker ? '隐藏起点标记' : '显示起点标记',
          icon: Icon(
            Icons.location_on_outlined,
            color: _showStartPointMarker ? Colors.red : Colors.grey,
            size: 20,
          ),
          onPressed: () {
            setState(() => _showStartPointMarker = !_showStartPointMarker);
          },
        ),
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.grey, size: 20),
          onPressed: _resetView,
          tooltip: '重置视图',
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: _previewPage.widthMm / _previewPage.heightMm,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF333333),
                borderRadius: BorderRadius.circular(4),
              ),
              clipBehavior: Clip.hardEdge,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final viewport = _ensureViewport(size);
                  final currentViewport = _viewport ?? viewport;

                  return Listener(
                    key: _gestureKey,
                    onPointerSignal: (event) {
                      if (event is! PointerScrollEvent) return;
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
                          final rawFactor =
                              1.0 - (event.scrollDelta.dy * 0.001);
                          final zoomFactor = rawFactor
                              .clamp(0.8, 1.25)
                              .toDouble();
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
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      child: CustomPaint(
                        size: size,
                        painter: PaperTypePainter(
                          config: _previewPaperConfig,
                          viewport: currentViewport,
                        ),
                        foregroundPainter: _isDynamicPreview
                            ? AnimatedToolPathPainter(
                                toolPath: _previewToolPath,
                                viewport: currentViewport,
                                progress: _animationController.value,
                                penWidthMm: 0.6,
                                showPenUp: _showPenUp,
                                showStartPointMarker: _showStartPointMarker,
                                cellSizeMm: _previewPaperConfig.cellSizeMm,
                              )
                            : ToolPathPainter(
                                toolPath: _previewToolPath,
                                viewport: currentViewport,
                                penWidthMm: 0.6,
                                showPenUp: _showPenUp,
                                showStartPointMarker: _showStartPointMarker,
                                cellSizeMm: _previewPaperConfig.cellSizeMm,
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // 起点信息显示
          if (_startPointConfig.hasCustomStartPoint)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  const Icon(Icons.my_location, color: Colors.green, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '起点: ${_startPointConfig.formattedText}',
                    style: const TextStyle(color: Colors.green, fontSize: 11),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 字形选择底部面板
class _GlyphPickerSheet extends StatefulWidget {
  final Map<String, Glyph> glyphs;
  final String fontName;
  final void Function(String) onInsert;

  const _GlyphPickerSheet({
    required this.glyphs,
    required this.fontName,
    required this.onInsert,
  });

  @override
  State<_GlyphPickerSheet> createState() => _GlyphPickerSheetState();
}

class _GlyphPickerSheetState extends State<_GlyphPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allChars =
        widget.glyphs.keys
            .where((c) => _query.isEmpty || c.contains(_query))
            .toList()
          ..sort();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          // ▶ 拖拽把手
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // ▶ 标题
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '从「${widget.fontName}」选择字形',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Chip(
                  label: Text('${allChars.length} 字'),
                  labelStyle: theme.textTheme.labelSmall,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          const Divider(height: 16),
          // ▶ 搜索框
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: '搜索字符…',
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _query = ''),
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Icon(
                  Icons.touch_app_outlined,
                  size: 13,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 4),
                Text(
                  '点击字形即可插入到文本',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          // ▶ 字形网格
          Expanded(
            child: allChars.isEmpty
                ? Center(
                    child: Text(
                      '无匹配字形',
                      style: TextStyle(color: theme.colorScheme.outline),
                    ),
                  )
                : GridView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 72,
                          mainAxisExtent: 84,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                        ),
                    itemCount: allChars.length,
                    itemBuilder: (ctx, i) {
                      final ch = allChars[i];
                      return GlyphTile(
                        character: ch,
                        glyph: widget.glyphs[ch],
                        isUserFont: true,
                        onTap: () {
                          widget.onInsert(ch);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
