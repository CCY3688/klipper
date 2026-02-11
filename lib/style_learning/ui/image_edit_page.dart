//图像编辑页面
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/image_editor_service.dart';

/// 图像编辑页面
/// 
/// 提供裁剪、旋转、调节等功能
class ImageEditPage extends StatefulWidget {
  final Uint8List imageBytes;
  
  const ImageEditPage({Key? key, required this.imageBytes}) : super(key: key);

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
  
  // 裁剪相关
  bool _isCropping = false;
  Rect _cropRect = Rect.zero;
  Size _imageSize = Size.zero;
  
  @override
  void initState() {
    super.initState();
    _currentImage = widget.imageBytes;
    _addToHistory(_currentImage);
    _updateImageInfo();
  }
  
  void _updateImageInfo() {
    final info = _editorService.getImageInfo(_currentImage);
    _imageSize = Size(info.width.toDouble(), info.height.toDouble());
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
        _updateImageInfo();
      });
    }
  }
  
  void _redo() {
    if (_canRedo) {
      setState(() {
        _historyIndex++;
        _currentImage = _history[_historyIndex];
        _updateImageInfo();
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑图像'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: _canUndo ? _undo : null,
            tooltip: '撤销',
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            onPressed: _canRedo ? _redo : null,
            tooltip: '重做',
          ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _isProcessing ? null : _confirmEdit,
            tooltip: '完成',
          ),
        ],
      ),
      body: Column(
        children: [
          // 图像预览区域
          Expanded(
            child: _buildImagePreview(),
          ),
          
          // 工具栏
          _buildToolbar(),
          
          // 调节滑块
          if (!_isCropping) _buildAdjustmentSliders(),
        ],
      ),
    );
  }
  
  Widget _buildImagePreview() {
    if (_isProcessing) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _isCropping 
            ? _buildCropView()
            : InteractiveViewer(
                child: Image.memory(
                  _currentImage,
                  fit: BoxFit.contain,
                ),
              ),
      ),
    );
  }
  
  Widget _buildCropView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onPanStart: (details) {
            setState(() {
              _cropRect = Rect.fromLTWH(
                details.localPosition.dx,
                details.localPosition.dy,
                0,
                0,
              );
            });
          },
          onPanUpdate: (details) {
            setState(() {
              _cropRect = Rect.fromPoints(
                _cropRect.topLeft,
                details.localPosition,
              );
            });
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(
                _currentImage,
                fit: BoxFit.contain,
              ),
              // 半透明遮罩
              CustomPaint(
                painter: _CropOverlayPainter(_cropRect),
              ),
              // 裁剪区域边框
              if (_cropRect.width > 10 && _cropRect.height > 10)
                Positioned(
                  left: _cropRect.left,
                  top: _cropRect.top,
                  child: Container(
                    width: _cropRect.width,
                    height: _cropRect.height,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildToolbar() {
    if (_isCropping) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.close),
              label: const Text('取消'),
              onPressed: () {
                setState(() {
                  _isCropping = false;
                  _cropRect = Rect.zero;
                });
              },
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.crop),
              label: const Text('确认裁剪'),
              onPressed: _cropRect.width > 10 && _cropRect.height > 10
                  ? _applyCrop
                  : null,
            ),
          ],
        ),
      );
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _ToolButton(
              icon: Icons.crop,
              label: '裁剪',
              onPressed: () {
                setState(() {
                  _isCropping = true;
                });
              },
            ),
            _ToolButton(
              icon: Icons.rotate_left,
              label: '左旋',
              onPressed: () => _rotate(-90),
            ),
            _ToolButton(
              icon: Icons.rotate_right,
              label: '右旋',
              onPressed: () => _rotate(90),
            ),
            _ToolButton(
              icon: Icons.auto_fix_high,
              label: '自动',
              onPressed: _autoEnhance,
            ),
            _ToolButton(
              icon: Icons.refresh,
              label: '重置',
              onPressed: _reset,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAdjustmentSliders() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 亮度
          Row(
            children: [
              const SizedBox(width: 60, child: Text('亮度')),
              Expanded(
                child: Slider(
                  value: _brightness,
                  min: -100,
                  max: 100,
                  divisions: 200,
                  label: _brightness.round().toString(),
                  onChanged: (value) {
                    setState(() {
                      _brightness = value;
                    });
                  },
                  onChangeEnd: (value) => _applyAdjustments(),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(_brightness.round().toString()),
              ),
            ],
          ),
          // 对比度
          Row(
            children: [
              const SizedBox(width: 60, child: Text('对比度')),
              Expanded(
                child: Slider(
                  value: _contrast,
                  min: 0.5,
                  max: 2.0,
                  divisions: 30,
                  label: _contrast.toStringAsFixed(1),
                  onChanged: (value) {
                    setState(() {
                      _contrast = value;
                    });
                  },
                  onChangeEnd: (value) => _applyAdjustments(),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(_contrast.toStringAsFixed(1)),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  // ==================== 操作方法 ====================
  
  Future<void> _applyCrop() async {
    if (_cropRect.width < 10 || _cropRect.height < 10) return;
    
    setState(() {
      _isProcessing = true;
    });
    
    try {
      // 需要将屏幕坐标转换为图像坐标
      // 这里简化处理，实际需要考虑图像在容器中的缩放和位置
      final cropRectNormalized = CropRect(
        left: (_cropRect.left / 300).clamp(0.0, 1.0),
        top: (_cropRect.top / 300).clamp(0.0, 1.0),
        width: (_cropRect.width / 300).clamp(0.0, 1.0),
        height: (_cropRect.height / 300).clamp(0.0, 1.0),
      );
      
      final result = await _editorService.crop(_currentImage, cropRectNormalized);
      
      setState(() {
        _currentImage = result;
        _isCropping = false;
        _cropRect = Rect.zero;
        _updateImageInfo();
        _addToHistory(_currentImage);
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      _showError('裁剪失败: $e');
    }
  }
  
  Future<void> _rotate(double angle) async {
    setState(() {
      _isProcessing = true;
    });
    
    try {
      final result = await _editorService.rotate(_currentImage, angle);
      
      setState(() {
        _currentImage = result;
        _updateImageInfo();
        _addToHistory(_currentImage);
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      _showError('旋转失败: $e');
    }
  }
  
  Future<void> _autoEnhance() async {
    setState(() {
      _isProcessing = true;
    });
    
    try {
      final result = await _editorService.autoEnhance(_currentImage);
      
      setState(() {
        _currentImage = result;
        _addToHistory(_currentImage);
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      _showError('自动增强失败: $e');
    }
  }
  
  Future<void> _applyAdjustments() async {
    if (_brightness == 0 && _contrast == 1.0) return;
    
    setState(() {
      _isProcessing = true;
    });
    
    try {
      final result = await _editorService.adjustBrightnessContrast(
        _history[0], // 从原图开始调整
        brightness: _brightness.round(),
        contrast: _contrast,
      );
      
      setState(() {
        _currentImage = result;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
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
      _updateImageInfo();
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