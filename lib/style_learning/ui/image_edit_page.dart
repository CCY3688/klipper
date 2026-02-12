//图像编辑页面
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/image_editor_service.dart';

/// 图像编辑页面
/// 
/// 提供裁剪、旋转、调节等功能
class ImageEditPage extends StatefulWidget {
  final Uint8List imageBytes;
  
  const ImageEditPage({super.key, required this.imageBytes});

  @override
  State<ImageEditPage> createState() => _ImageEditPageState();
}

class _ImageEditPageState extends State<ImageEditPage> {
  final ImageEditorService _editorService = ImageEditorService();
  
  late Uint8List _currentImage;
  final List<Uint8List> _history = [];
  int _historyIndex = -1;
  
  bool _isProcessing = false;
  double _brightness = 0;
  double _contrast = 1.0;
  
  // 工具管理
  int _currentToolIndex = 0; // 0: 调节, 1: 裁剪, 2: 旋转
  
  // 裁剪相关
  Rect _cropRect = Rect.zero;
  Size _imageDisplaySize = Size.zero;
  Offset _imageDisplayOffset = Offset.zero;
  _CropDragMode _cropDragMode = _CropDragMode.none;
  Offset _panStart = Offset.zero;
  Rect _cropRectAtPanStart = Rect.zero;
  static const double _cropMinSize = 40;
  static const double _handleTouchRadius = 26;
  
  @override
  void initState() {
    super.initState();
    _currentImage = widget.imageBytes;
    _addToHistory(_currentImage);
  }
  
  void _addToHistory(Uint8List image) {
    // 移除当前位置之后的历史
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(image);
    _historyIndex = _history.length - 1;
    
    // 限制历史记录数量
    if (_history.length > 20) {
      _history.removeAt(0);
      _historyIndex--;
    }
  }
  
  bool get _canUndo => _historyIndex > 0;
  bool get _canRedo => _historyIndex < _history.length - 1;
  
  void _undo() {
    if (_canUndo) {
      setState(() {
        _historyIndex--;
        _currentImage = _history[_historyIndex];
      });
    }
  }
  
  void _redo() {
    if (_canRedo) {
      setState(() {
        _historyIndex++;
        _currentImage = _history[_historyIndex];
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('图像编辑'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: _canUndo ? _undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            onPressed: _canRedo ? _redo : null,
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _isProcessing ? null : _confirmEdit,
            child: Text(
              '保存',
              style: TextStyle(
                color: _isProcessing ? Colors.grey : theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 图像预览区域
          Expanded(
            child: Container(
              width: double.infinity,
              color: Colors.black,
              child: _buildImageArea(),
            ),
          ),
          
          // 控制面板
          Container(
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 工具内容区
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: _buildToolContent(),
                ),
                
                // 工具切换栏
                Divider(height: 1, color: Colors.white12),
                BottomNavigationBar(
                  currentIndex: _currentToolIndex,
                  onTap: (index) {
                    setState(() {
                      _currentToolIndex = index;
                    });
                  },
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  selectedItemColor: theme.colorScheme.primary,
                  unselectedItemColor: Colors.grey,
                  type: BottomNavigationBarType.fixed,
                  items: const [
                    BottomNavigationBarItem(icon: Icon(Icons.tune), label: '调节'),
                    BottomNavigationBarItem(icon: Icon(Icons.crop), label: '裁剪'),
                    BottomNavigationBarItem(icon: Icon(Icons.rotate_right), label: '旋转'),
                    BottomNavigationBarItem(icon: Icon(Icons.auto_fix_high), label: '智能'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildImageArea() {
    if (_isProcessing) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // 在这里我们不实际渲染 Image.memory 两次
        // 而是计算一次布局信息供裁剪使用
        return _currentToolIndex == 1 // 裁剪工具
            ? _buildCropView(constraints)
            : InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: Image.memory(
                    _currentImage,
                    fit: BoxFit.contain,
                  ),
                ),
              );
      },
    );
  }
  
  Widget _buildToolContent() {
    switch (_currentToolIndex) {
      case 0: // 调节
        return _buildAdjustmentSliders();
      case 1: // 裁剪
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OutlinedButton.icon(
                onPressed: () => setState(() => _cropRect = Rect.zero),
                icon: const Icon(Icons.refresh),
                label: const Text('重置区域'),
              ),
              ElevatedButton.icon(
                onPressed: _cropRect.width > 20 ? _applyCrop : null,
                icon: const Icon(Icons.check),
                label: const Text('执行裁剪'),
              ),
            ],
          ),
        );
      case 2: // 旋转
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ToolButton(
              icon: Icons.rotate_left,
              label: '左旋90°',
              onPressed: () => _rotate(-90),
            ),
            _ToolButton(
              icon: Icons.rotate_right,
              label: '右旋90°',
              onPressed: () => _rotate(90),
            ),
            _ToolButton(
              icon: Icons.flip,
              label: '水平翻转',
              onPressed: () {/* 简单旋转代替翻转示例 */ _rotate(180); },
            ),
          ],
        );
      case 3: // 智能
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ActionChip(
              icon: Icons.auto_fix_high,
              label: '一键增强',
              onPressed: _autoEnhance,
            ),
            _ActionChip(
              icon: Icons.refresh,
              label: '恢复原图',
              onPressed: _reset,
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }
  
  Widget _buildCropView(BoxConstraints constraints) {
    // 异步获取图像尺寸并计算布局，这里简化为同步计算
    // 实际生产中可能需要先把 Image 加载到内存获取 Size
    final info = _editorService.getImageInfo(_currentImage);
    final imageWidth = info.width.toDouble();
    final imageHeight = info.height.toDouble();
    
    final double imageAspect = imageWidth / imageHeight;
    final double containerAspect = constraints.maxWidth / constraints.maxHeight;
    
    double drawWidth, drawHeight;
    if (containerAspect > imageAspect) {
      drawHeight = constraints.maxHeight;
      drawWidth = drawHeight * imageAspect;
    } else {
      drawWidth = constraints.maxWidth;
      drawHeight = drawWidth / imageAspect;
    }
    
    final double left = (constraints.maxWidth - drawWidth) / 2;
    final double top = (constraints.maxHeight - drawHeight) / 2;
    
    _imageDisplaySize = Size(drawWidth, drawHeight);
    _imageDisplayOffset = Offset(left, top);
    
    // 初始化裁剪框
    if (_cropRect == Rect.zero) {
      _cropRect = Rect.fromLTWH(left + 20, top + 20, drawWidth - 40, drawHeight - 40);
    }

    return GestureDetector(
      onPanStart: (details) {
        _cropDragMode = _resolveCropDragMode(details.localPosition);
        _panStart = details.localPosition;
        _cropRectAtPanStart = _cropRect;
      },
      onPanUpdate: (details) {
        setState(() {
          final dx = details.localPosition.dx - _panStart.dx;
          final dy = details.localPosition.dy - _panStart.dy;
          _cropRect = _computeDraggedCropRect(
            startRect: _cropRectAtPanStart,
            mode: _cropDragMode,
            dx: dx,
            dy: dy,
          );
          _cropRect = _constrainCropRect(_cropRect, left, top, drawWidth, drawHeight);
        });
      },
      onPanEnd: (_) {
        _cropDragMode = _CropDragMode.none;
      },
      child: Stack(
        children: [
          Center(
            child: Image.memory(
              _currentImage,
              fit: BoxFit.contain,
            ),
          ),
          // 遮罩
          CustomPaint(
            size: Size.infinite,
            painter: _CropOverlayPainter(_cropRect),
          ),
          // 裁剪框
          Positioned.fromRect(
            rect: _cropRect,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue, width: 2),
              ),
              child: Stack(
                children: [
                  // 九宫格辅助线
                  Column(
                    children: [
                      const Spacer(),
                      Container(height: 1, color: Colors.white38),
                      const Spacer(),
                      Container(height: 1, color: Colors.white38),
                      const Spacer(),
                    ],
                  ),
                  Row(
                    children: [
                      const Spacer(),
                      Container(width: 1, color: Colors.white38),
                      const Spacer(),
                      Container(width: 1, color: Colors.white38),
                      const Spacer(),
                    ],
                  ),
                  // 四角手柄
                  _buildHandle(Alignment.topLeft),
                  _buildHandle(Alignment.topRight),
                  _buildHandle(Alignment.bottomLeft),
                  _buildHandle(Alignment.bottomRight),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHandle(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 18,
        height: 18,
        decoration: const BoxDecoration(
          color: Colors.blue,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  _CropDragMode _resolveCropDragMode(Offset pos) {
    final corners = <_CropDragMode, Offset>{
      _CropDragMode.resizeTopLeft: _cropRect.topLeft,
      _CropDragMode.resizeTopRight: _cropRect.topRight,
      _CropDragMode.resizeBottomLeft: _cropRect.bottomLeft,
      _CropDragMode.resizeBottomRight: _cropRect.bottomRight,
    };

    for (final entry in corners.entries) {
      if ((pos - entry.value).distance <= _handleTouchRadius) {
        return entry.key;
      }
    }

    if (_cropRect.contains(pos)) return _CropDragMode.move;
    return _CropDragMode.none;
  }

  Rect _computeDraggedCropRect({
    required Rect startRect,
    required _CropDragMode mode,
    required double dx,
    required double dy,
  }) {
    switch (mode) {
      case _CropDragMode.resizeTopLeft:
        return Rect.fromLTRB(startRect.left + dx, startRect.top + dy, startRect.right, startRect.bottom);
      case _CropDragMode.resizeTopRight:
        return Rect.fromLTRB(startRect.left, startRect.top + dy, startRect.right + dx, startRect.bottom);
      case _CropDragMode.resizeBottomLeft:
        return Rect.fromLTRB(startRect.left + dx, startRect.top, startRect.right, startRect.bottom + dy);
      case _CropDragMode.resizeBottomRight:
        return Rect.fromLTRB(startRect.left, startRect.top, startRect.right + dx, startRect.bottom + dy);
      case _CropDragMode.move:
        return startRect.shift(Offset(dx, dy));
      case _CropDragMode.none:
        return startRect;
    }
  }

  Rect _constrainCropRect(Rect rect, double left, double top, double drawWidth, double drawHeight) {
    final rightBound = left + drawWidth;
    final bottomBound = top + drawHeight;

    double l = rect.left;
    double t = rect.top;
    double r = rect.right;
    double b = rect.bottom;

    if (r - l < _cropMinSize) {
      if (_cropDragMode == _CropDragMode.resizeTopLeft || _cropDragMode == _CropDragMode.resizeBottomLeft) {
        l = r - _cropMinSize;
      } else {
        r = l + _cropMinSize;
      }
    }
    if (b - t < _cropMinSize) {
      if (_cropDragMode == _CropDragMode.resizeTopLeft || _cropDragMode == _CropDragMode.resizeTopRight) {
        t = b - _cropMinSize;
      } else {
        b = t + _cropMinSize;
      }
    }

    if (_cropDragMode == _CropDragMode.move) {
      final width = r - l;
      final height = b - t;
      l = l.clamp(left, rightBound - width);
      t = t.clamp(top, bottomBound - height);
      r = l + width;
      b = t + height;
    } else {
      l = l.clamp(left, rightBound - _cropMinSize);
      t = t.clamp(top, bottomBound - _cropMinSize);
      r = r.clamp(left + _cropMinSize, rightBound);
      b = b.clamp(top + _cropMinSize, bottomBound);
    }

    if (r - l < _cropMinSize) r = (l + _cropMinSize).clamp(left + _cropMinSize, rightBound);
    if (b - t < _cropMinSize) b = (t + _cropMinSize).clamp(top + _cropMinSize, bottomBound);

    return Rect.fromLTRB(l, t, r, b);
  }
  
  Widget _buildAdjustmentSliders() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        children: [
          _SliderRow(
            icon: Icons.brightness_6,
            label: '亮度',
            value: _brightness,
            min: -100,
            max: 100,
            onChanged: (v) => setState(() => _brightness = v),
            onChangeEnd: (v) => _applyAdjustments(),
          ),
          const SizedBox(height: 8),
          _SliderRow(
            icon: Icons.contrast,
            label: '对比度',
            value: _contrast,
            min: 0.5,
            max: 2.0,
            onChanged: (v) => setState(() => _contrast = v),
            onChangeEnd: (v) => _applyAdjustments(),
          ),
        ],
      ),
    );
  }
  
  // ==================== 操作方法 ====================
  
  Future<void> _applyCrop() async {
    setState(() => _isProcessing = true);
    
    try {
      // 计算归一化坐标
      final double normLeft = (_cropRect.left - _imageDisplayOffset.dx) / _imageDisplaySize.width;
      final double normTop = (_cropRect.top - _imageDisplayOffset.dy) / _imageDisplaySize.height;
      final double normWidth = _cropRect.width / _imageDisplaySize.width;
      final double normHeight = _cropRect.height / _imageDisplaySize.height;
      
      final cropRectNormalized = CropRect(
        left: normLeft.clamp(0.0, 1.0),
        top: normTop.clamp(0.0, 1.0),
        width: normWidth.clamp(0.0, 1.0),
        height: normHeight.clamp(0.0, 1.0),
      );
      
      final result = await _editorService.crop(_currentImage, cropRectNormalized);
      
      setState(() {
        _currentImage = result;
        _cropRect = Rect.zero;
        _addToHistory(_currentImage);
        _isProcessing = false;
        _currentToolIndex = 0; // 切回调节工具
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      _showError('裁剪失败: $e');
    }
  }
  
  Future<void> _rotate(double angle) async {
    setState(() => _isProcessing = true);
    try {
      final result = await _editorService.rotate(_currentImage, angle);
      setState(() {
        _currentImage = result;
        _addToHistory(_currentImage);
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      _showError('旋转失败: $e');
    }
  }
  
  Future<void> _autoEnhance() async {
    setState(() => _isProcessing = true);
    try {
      final result = await _editorService.autoEnhance(_currentImage);
      setState(() {
        _currentImage = result;
        _addToHistory(_currentImage);
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      _showError('自动增强失败: $e');
    }
  }
  
  Future<void> _applyAdjustments() async {
    setState(() => _isProcessing = true);
    try {
      // 总是从最近的一次“确认”操作后的图像开始调整，或者简单点从历史中最后一张开始
      // 为了性能，如果连续滑动，这里可以做 debounce
      final result = await _editorService.adjustBrightnessContrast(
        _history[_historyIndex], 
        brightness: _brightness.round(),
        contrast: _contrast,
      );
      
      setState(() {
        _currentImage = result;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
    }
  }
  
  void _reset() {
    setState(() {
      _currentImage = widget.imageBytes;
      _brightness = 0;
      _contrast = 1.0;
      _history.clear();
      _historyIndex = -1;
      _addToHistory(_currentImage);
      _currentToolIndex = 0;
    });
  }
  
  void _confirmEdit() {
    Navigator.pop(context, _currentImage);
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}

/// 内部小组件
class _SliderRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _SliderRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 10),
        SizedBox(width: 50, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(
          width: 35,
          child: Text(
            min < 0 ? value.round().toString() : value.toStringAsFixed(1),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ActionChip({required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onPressed,
      backgroundColor: Colors.white10,
    );
  }
}


/// 工具按钮
class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(icon),
            onPressed: onPressed,
          ),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

/// 裁剪遮罩绘制器
class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect;
  
  _CropOverlayPainter(this.cropRect);
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;
    
    // 绘制四个遮罩区域
    // 上
    canvas.drawRect(
      Rect.fromLTRB(0, 0, size.width, cropRect.top),
      paint,
    );
    // 下
    canvas.drawRect(
      Rect.fromLTRB(0, cropRect.bottom, size.width, size.height),
      paint,
    );
    // 左
    canvas.drawRect(
      Rect.fromLTRB(0, cropRect.top, cropRect.left, cropRect.bottom),
      paint,
    );
    // 右
    canvas.drawRect(
      Rect.fromLTRB(cropRect.right, cropRect.top, size.width, cropRect.bottom),
      paint,
    );
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

enum _CropDragMode {
  none,
  move,
  resizeTopLeft,
  resizeTopRight,
  resizeBottomLeft,
  resizeBottomRight,
}