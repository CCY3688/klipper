//完整的工作流程页面
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/handwriting_sample.dart';
import '../services/image_capture_service.dart';
import '../services/image_processor.dart';
import '../services/character_segmenter.dart';
import '../services/skeleton_extractor.dart';
import 'image_edit_page.dart';

/// 样本采集主页面
/// 
/// 完整的工作流程：
/// 1. 拍照/选择图片
/// 2. 编辑图片（裁剪、旋转等）
/// 3. 预处理（二值化）
/// 4. 字符分割
/// 5. 骨架提取
class SampleCollectionPage extends StatefulWidget {
  const SampleCollectionPage({Key? key}) : super(key: key);

  @override
  State<SampleCollectionPage> createState() => _SampleCollectionPageState();
}

class _SampleCollectionPageState extends State<SampleCollectionPage> {
  final ImageCaptureService _captureService = ImageCaptureService();
  final ImageProcessor _imageProcessor = ImageProcessor();
  final CharacterSegmenter _segmenter = CharacterSegmenter();
  final SkeletonExtractor _skeletonExtractor = SkeletonExtractor();
  
  // 处理状态
  ProcessingState _state = ProcessingState.idle;
  String _statusMessage = '';
  
  // 数据
  Uint8List? _originalImage;
  Uint8List? _editedImage;
  ImageProcessResult? _processResult;
  SegmentationResult? _segmentationResult;
  List<CharacterWithSkeleton> _charactersWithSkeleton = [];
  
  // UI 状态
  int _selectedCharacterIndex = -1;
  bool _showSkeleton = true;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('手写样本采集'),
        actions: [
          if (_charactersWithSkeleton.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveResults,
              tooltip: '保存结果',
            ),
        ],
      ),
      body: Column(
        children: [
          // 进度指示器
          _buildProgressIndicator(),
          
          // 主要内容
          Expanded(
            child: _buildContent(),
          ),
          
          // 底部操作栏
          _buildBottomBar(),
        ],
      ),
    );
  }
  
  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              _StepIndicator(
                step: 1,
                label: '选择',
                isActive: _state.index >= ProcessingState.idle.index,
                isComplete: _originalImage != null,
              ),
              _StepConnector(isComplete: _originalImage != null),
              _StepIndicator(
                step: 2,
                label: '编辑',
                isActive: _originalImage != null,
                isComplete: _editedImage != null,
              ),
              _StepConnector(isComplete: _processResult != null),
              _StepIndicator(
                step: 3,
                label: '处理',
                isActive: _editedImage != null,
                isComplete: _processResult != null,
              ),
              _StepConnector(isComplete: _segmentationResult != null),
              _StepIndicator(
                step: 4,
                label: '分割',
                isActive: _processResult != null,
                isComplete: _segmentationResult != null,
              ),
              _StepConnector(isComplete: _charactersWithSkeleton.isNotEmpty),
              _StepIndicator(
                step: 5,
                label: '骨架',
                isActive: _segmentationResult != null,
                isComplete: _charactersWithSkeleton.isNotEmpty,
              ),
            ],
          ),
          if (_statusMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _statusMessage,
                style: TextStyle(
                  color: _state == ProcessingState.error 
                      ? Colors.red 
                      : Colors.grey[600],
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildContent() {
    if (_state == ProcessingState.processing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('处理中...'),
          ],
        ),
      );
    }
    
    // 如果有骨架结果，显示字符网格
    if (_charactersWithSkeleton.isNotEmpty) {
      return _buildCharacterGrid();
    }
    
    // 如果有分割结果，显示分割预览
    if (_segmentationResult != null) {
      return _buildSegmentationPreview();
    }
    
    // 如果有处理结果，显示处理预览
    if (_processResult != null) {
      return _buildProcessPreview();
    }
    
    // 如果有编辑后的图片，显示编辑预览
    if (_editedImage != null) {
      return _buildEditedPreview();
    }
    
    // 如果有原始图片，显示原始预览
    if (_originalImage != null) {
      return _buildOriginalPreview();
    }
    
    // 空状态
    return _buildEmptyState();
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '请选择或拍摄手写样本图片',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            '可以一次拍摄多个字，系统会自动分割',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.photo_library),
                label: const Text('从相册选择'),
                onPressed: _pickFromGallery,
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt),
                label: const Text('拍照'),
                onPressed: _captureFromCamera,
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildOriginalPreview() {
    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            child: Image.memory(_originalImage!, fit: BoxFit.contain),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.edit),
            label: const Text('编辑图片'),
            onPressed: _editImage,
          ),
        ),
      ],
    );
  }
  
  Widget _buildEditedPreview() {
    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            child: Image.memory(_editedImage!, fit: BoxFit.contain),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.edit),
                label: const Text('重新编辑'),
                onPressed: _editImage,
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('开始处理'),
                onPressed: _processImage,
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildProcessPreview() {
    return Column(
      children: [
        // 阶段选择
        SizedBox(
          height: 50,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _processResult!.stages.length,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemBuilder: (context, index) {
              final stage = _processResult!.stages[index];
              return Padding(
                padding: const EdgeInsets.all(4),
                child: ActionChip(
                  label: Text(stage.name),
                  onPressed: () {},
                ),
              );
            },
          ),
        ),
        // 处理后的图像
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            child: Image.memory(
              _processResult!.stages.last.image,
              fit: BoxFit.contain,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.grid_view),
            label: const Text('分割字符'),
            onPressed: _segmentCharacters,
          ),
        ),
      ],
    );
  }
  
  Widget _buildSegmentationPreview() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '检测到 ${_segmentationResult!.totalFound} 个字符',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _segmentationResult!.characters.length,
            itemBuilder: (context, index) {
              final char = _segmentationResult!.characters[index];
              return Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Image.memory(
                  char.imageData,
                  fit: BoxFit.contain,
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.auto_awesome),
            label: const Text('提取骨架'),
            onPressed: _extractSkeletons,
          ),
        ),
      ],
    );
  }
  
  Widget _buildCharacterGrid() {
    return Column(
      children: [
        // 工具栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '共 ${_charactersWithSkeleton.length} 个字符',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Row(
                children: [
                  const Text('显示骨架'),
                  Switch(
                    value: _showSkeleton,
                    onChanged: (value) {
                      setState(() {
                        _showSkeleton = value;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        // 字符网格
        Expanded(
          child: Row(
            children: [
              // 左侧：字符列表
              SizedBox(
                width: 200,
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _charactersWithSkeleton.length,
                  itemBuilder: (context, index) {
                    final char = _charactersWithSkeleton[index];
                    final isSelected = index == _selectedCharacterIndex;
                    
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCharacterIndex = index;
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isSelected ? Colors.blue : Colors.grey[300]!,
                            width: isSelected ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(4),
                          color: isSelected ? Colors.blue.withOpacity(0.1) : null,
                        ),
                        child: Row(
                          children: [
                            Image.memory(
                              char.binaryImage,
                              width: 48,
                              height: 48,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('字符 ${index + 1}'),
                                  Text(
                                    '${char.skeleton.strokeCount} 笔画',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // 右侧：详细视图
              Expanded(
                child: _selectedCharacterIndex >= 0
                    ? _buildCharacterDetail(_charactersWithSkeleton[_selectedCharacterIndex])
                    : const Center(child: Text('选择一个字符查看详情')),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildCharacterDetail(CharacterWithSkeleton char) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 图像预览
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CustomPaint(
                  painter: _SkeletonPainter(
                    binaryImage: char.binaryImage,
                    skeleton: char.skeleton,
                    showSkeleton: _showSkeleton,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
          // 信息面板
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _InfoRow(label: '笔画数量', value: '${char.skeleton.strokeCount}'),
                _InfoRow(label: '端点数量', value: '${char.skeleton.endpointCount}'),
                _InfoRow(label: '交叉点数量', value: '${char.skeleton.junctionCount}'),
                _InfoRow(label: '骨架点总数', value: '${char.skeleton.skeletonPoints.length}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('重新开始'),
            onPressed: _reset,
          ),
          const Spacer(),
          if (_originalImage == null) ...[
            ElevatedButton.icon(
              icon: const Icon(Icons.photo_library),
              label: const Text('选择图片'),
              onPressed: _pickFromGallery,
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.camera_alt),
              label: const Text('拍照'),
              onPressed: _captureFromCamera,
            ),
          ],
        ],
      ),
    );
  }
  
  // ==================== 操作方法 ====================
  
  Future<void> _pickFromGallery() async {
    try {
      final sample = await _captureService.pickFromGallery();
      if (sample != null) {
        setState(() {
          _originalImage = sample.originalImage;
          _editedImage = null;
          _processResult = null;
          _segmentationResult = null;
          _charactersWithSkeleton.clear();
          _selectedCharacterIndex = -1;
          _statusMessage = '已选择图片';
        });
      }
    } catch (e) {
      _setError('选择图片失败: $e');
    }
  }
  
  Future<void> _captureFromCamera() async {
    try {
      final sample = await _captureService.captureFromCamera();
      if (sample != null) {
        setState(() {
          _originalImage = sample.originalImage;
          _editedImage = null;
          _processResult = null;
          _segmentationResult = null;
          _charactersWithSkeleton.clear();
          _selectedCharacterIndex = -1;
          _statusMessage = '已拍摄图片';
        });
      }
    } catch (e) {
      _setError('拍照失败: $e');
    }
  }
  
  Future<void> _editImage() async {
    if (_originalImage == null) return;
    
    final result = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        builder: (context) => ImageEditPage(
          imageBytes: _editedImage ?? _originalImage!,
        ),
      ),
    );
    
    if (result != null) {
      setState(() {
        _editedImage = result;
        _processResult = null;
        _segmentationResult = null;
        _charactersWithSkeleton.clear();
        _statusMessage = '图片编辑完成';
      });
    }
  }
  
  Future<void> _processImage() async {
    final imageToProcess = _editedImage ?? _originalImage;
    if (imageToProcess == null) return;
    
    setState(() {
      _state = ProcessingState.processing;
      _statusMessage = '正在处理图像...';
    });
    
    try {
      final result = await _imageProcessor.process(imageToProcess);
      
      setState(() {
        _processResult = result;
        _state = ProcessingState.idle;
        _statusMessage = '处理完成，耗时 ${result.totalDuration}ms';
      });
    } catch (e) {
      _setError('处理失败: $e');
    }
  }
  
  Future<void> _segmentCharacters() async {
    if (_processResult == null) return;
    
    setState(() {
      _state = ProcessingState.processing;
      _statusMessage = '正在分割字符...';
    });
    
    try {
      final result = await _segmenter.segment(_processResult!.processedImage);
      
      setState(() {
        _segmentationResult = result;
        _state = ProcessingState.idle;
        _statusMessage = '检测到 ${result.totalFound} 个字符';
      });
    } catch (e) {
      _setError('分割失败: $e');
    }
  }
  
  Future<void> _extractSkeletons() async {
    if (_segmentationResult == null) return;
    
    setState(() {
      _state = ProcessingState.processing;
      _statusMessage = '正在提取骨架...';
    });
    
    try {
      final results = <CharacterWithSkeleton>[];
      
      for (int i = 0; i < _segmentationResult!.characters.length; i++) {
        setState(() {
          _statusMessage = '正在处理第 ${i + 1}/${_segmentationResult!.characters.length} 个字符...';
        });
        
        final char = _segmentationResult!.characters[i];
        final skeleton = await _skeletonExtractor.extract(char.imageData);
        
        results.add(CharacterWithSkeleton(
          index: i,
          binaryImage: char.imageData,
          skeleton: skeleton,
        ));
      }
      
      setState(() {
        _charactersWithSkeleton = results;
        _selectedCharacterIndex = results.isNotEmpty ? 0 : -1;
        _state = ProcessingState.idle;
        _statusMessage = '骨架提取完成';
      });
    } catch (e) {
      _setError('骨架提取失败: $e');
    }
  }
  
  void _saveResults() {
    // TODO: 实现保存逻辑
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已保存 ${_charactersWithSkeleton.length} 个字符'),
      ),
    );
  }
  
  void _reset() {
    setState(() {
      _originalImage = null;
      _editedImage = null;
      _processResult = null;
      _segmentationResult = null;
      _charactersWithSkeleton.clear();
      _selectedCharacterIndex = -1;
      _state = ProcessingState.idle;
      _statusMessage = '';
    });
  }
  
  void _setError(String message) {
    setState(() {
      _state = ProcessingState.error;
      _statusMessage = message;
    });
  }
}

// ==================== 辅助类和组件 ====================

enum ProcessingState {
  idle,
  processing,
  error,
}

class CharacterWithSkeleton {
  final int index;
  final Uint8List binaryImage;
  final SkeletonResult skeleton;
  
  CharacterWithSkeleton({
    required this.index,
    required this.binaryImage,
    required this.skeleton,
  });
}

class _StepIndicator extends StatelessWidget {
  final int step;
  final String label;
  final bool isActive;
  final bool isComplete;
  
  const _StepIndicator({
    required this.step,
    required this.label,
    required this.isActive,
    required this.isComplete,
  });
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isComplete
                ? Colors.green
                : isActive
                    ? Colors.blue
                    : Colors.grey[300],
          ),
          child: Center(
            child: isComplete
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : Text(
                    '$step',
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.grey[600],
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive ? Colors.blue : Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

class _StepConnector extends StatelessWidget {
  final bool isComplete;
  
  const _StepConnector({required this.isComplete});
  
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: isComplete ? Colors.green : Colors.grey[300],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  
  const _InfoRow({required this.label, required this.value});
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// 骨架绘制器
class _SkeletonPainter extends CustomPainter {
  final Uint8List binaryImage;
  final SkeletonResult skeleton;
  final bool showSkeleton;
  
  _SkeletonPainter({
    required this.binaryImage,
    required this.skeleton,
    required this.showSkeleton,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    // 计算缩放
    final scaleX = size.width / skeleton.width;
    final scaleY = size.height / skeleton.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    
    final offsetX = (size.width - skeleton.width * scale) / 2;
    final offsetY = (size.height - skeleton.height * scale) / 2;
    
    // 绘制背景网格
    final gridPaint = Paint()
      ..color = Colors.grey[200]!
      ..strokeWidth = 1;
    
    for (int i = 0; i <= 4; i++) {
      final x = offsetX + skeleton.width * scale * i / 4;
      canvas.drawLine(
        Offset(x, offsetY),
        Offset(x, offsetY + skeleton.height * scale),
        gridPaint,
      );
      
      final y = offsetY + skeleton.height * scale * i / 4;
      canvas.drawLine(
        Offset(offsetX, y),
        Offset(offsetX + skeleton.width * scale, y),
        gridPaint,
      );
    }
    
    if (showSkeleton) {
      // 绘制笔画路径
      final strokeColors = [
        Colors.red,
        Colors.blue,
        Colors.green,
        Colors.orange,
        Colors.purple,
        Colors.teal,
        Colors.pink,
        Colors.indigo,
      ];
      
      for (int i = 0; i < skeleton.strokes.length; i++) {
        final stroke = skeleton.strokes[i];
        final color = strokeColors[i % strokeColors.length];
        
        final paint = Paint()
          ..color = color
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        
        if (stroke.points.isEmpty) continue;
        
        final path = Path();
        final firstPoint = stroke.points.first;
        path.moveTo(
          offsetX + firstPoint.x * scale,
          offsetY + firstPoint.y * scale,
        );
        
        for (int j = 1; j < stroke.points.length; j++) {
          final point = stroke.points[j];
          path.lineTo(
            offsetX + point.x * scale,
            offsetY + point.y * scale,
          );
        }
        
        canvas.drawPath(path, paint);
        
        // 绘制起点和终点
        final startPaint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        
        canvas.drawCircle(
          Offset(offsetX + firstPoint.x * scale, offsetY + firstPoint.y * scale),
          5,
          startPaint,
        );
        
        final lastPoint = stroke.points.last;
        final endPaint = Paint()
          ..color = color.withOpacity(0.5)
          ..style = PaintingStyle.fill;
        
        canvas.drawCircle(
          Offset(offsetX + lastPoint.x * scale, offsetY + lastPoint.y * scale),
          4,
          endPaint,
        );
      }
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}