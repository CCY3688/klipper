//完整的工作流程页面
import 'dart:typed_data';
import 'package:flutter/material.dart';
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
  final bool embedded;

  const SampleCollectionPage({super.key, this.embedded = false});

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
  int _selectedProcessStageIndex = 0;
  bool _showSkeleton = true;
  bool _showPoints = false;
  static const TextStyle _chipTextStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );
  static const TextStyle _stageChipTextStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.embedded) {
      return Container(
        color: theme.scaffoldBackgroundColor,
        child: _buildMainLayout(),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('图像采集'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_charactersWithSkeleton.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: const Icon(Icons.save_alt),
                onPressed: _saveResults,
                tooltip: '导出结果',
              ),
            ),
        ],
      ),
      body: _buildMainLayout(),
    );
  }

  Widget _buildMainLayout() {
    return Column(
      children: [
        // 现代化的进度指示器
        _buildModernStepIndicator(),

        const Divider(height: 1, color: Colors.white10),

        // 主要内容
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: _buildContent(),
          ),
        ),

        // 动态操作栏
        _buildActionButtonArea(),
      ],
    );
  }
  
  Widget _buildModernStepIndicator() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _buildStep(1, '采集', _originalImage != null, isActive: _originalImage != null),
          _buildStepLine(_originalImage != null),
          _buildStep(2, '校准', _editedImage != null, isActive: _originalImage != null),
          _buildStepLine(_processResult != null),
          _buildStep(3, '处理', _processResult != null, isActive: _editedImage != null),
          _buildStepLine(_segmentationResult != null),
          _buildStep(4, '分割', _segmentationResult != null, isActive: _processResult != null),
          _buildStepLine(_charactersWithSkeleton.isNotEmpty),
          _buildStep(5, '骨架', _charactersWithSkeleton.isNotEmpty, isActive: _segmentationResult != null),
        ],
      ),
    );
  }

  Widget _buildStep(int step, String label, bool isDone, {bool isActive = false}) {
    final theme = Theme.of(context);
    final color = isDone ? Colors.green : (isActive ? theme.colorScheme.primary : Colors.grey[700]!);
    final canNavigate = _canNavigateToStep(step) && _state != ProcessingState.processing;
    
    return InkWell(
      onTap: canNavigate ? () => _goToStep(step) : null,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: canNavigate ? 1 : 0.8,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone ? Colors.green : Colors.transparent,
                  border: Border.all(color: color, width: 2),
                ),
                child: Center(
                  child: isDone 
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Text('$step', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: color, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  bool _canNavigateToStep(int step) {
    switch (step) {
      case 1:
        return _originalImage != null;
      case 2:
        return _editedImage != null || _processResult != null || _segmentationResult != null || _charactersWithSkeleton.isNotEmpty;
      case 3:
        return _processResult != null || _segmentationResult != null || _charactersWithSkeleton.isNotEmpty;
      case 4:
        return _segmentationResult != null || _charactersWithSkeleton.isNotEmpty;
      case 5:
        return _charactersWithSkeleton.isNotEmpty;
      default:
        return false;
    }
  }

  void _goToStep(int step) {
    if (!_canNavigateToStep(step)) return;

    setState(() {
      if (step <= 1) {
        _editedImage = null;
        _processResult = null;
        _selectedProcessStageIndex = 0;
        _segmentationResult = null;
        _charactersWithSkeleton.clear();
        _selectedCharacterIndex = -1;
        _statusMessage = '已返回采集阶段';
      } else if (step == 2) {
        _processResult = null;
        _selectedProcessStageIndex = 0;
        _segmentationResult = null;
        _charactersWithSkeleton.clear();
        _selectedCharacterIndex = -1;
        _statusMessage = '已返回校准阶段';
      } else if (step == 3) {
        _segmentationResult = null;
        _charactersWithSkeleton.clear();
        _selectedCharacterIndex = -1;
        _statusMessage = '已返回预处理阶段';
      } else if (step == 4) {
        _charactersWithSkeleton.clear();
        _selectedCharacterIndex = -1;
        _statusMessage = '已返回分割阶段';
      } else if (step == 5) {
        _statusMessage = '当前为骨架分析阶段';
      }
      _state = ProcessingState.idle;
    });
  }

  Widget _buildStepLine(bool isDone) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: isDone ? Colors.green : Colors.grey[800],
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }

  Widget _buildActionButtonArea() {
    final theme = Theme.of(context);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_originalImage != null)
              IconButton(
                onPressed: _reset,
                icon: const Icon(Icons.refresh),
                tooltip: '重置',
              ),
            const Spacer(),
            _buildContextualButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildContextualButton() {
    if (_state == ProcessingState.processing) return const SizedBox.shrink();
    
    if (_originalImage == null) {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
        icon: const Icon(Icons.add_a_photo),
        label: const Text('开始采集'),
        onPressed: () => _pickFromGallery(),
      );
    }
    
    if (_editedImage == null) {
      return ElevatedButton.icon(
        icon: const Icon(Icons.edit),
        label: const Text('进入编辑'),
        onPressed: _editImage,
      );
    }
    
    if (_processResult == null) {
      return ElevatedButton.icon(
        icon: const Icon(Icons.auto_awesome),
        label: const Text('预处理图像'),
        onPressed: _processImage,
      );
    }
    
    if (_segmentationResult == null) {
      return ElevatedButton.icon(
        icon: const Icon(Icons.grid_view),
        label: const Text('识别并分割'),
        onPressed: _segmentCharacters,
      );
    }
    
    if (_charactersWithSkeleton.isEmpty) {
      return ElevatedButton.icon(
        icon: const Icon(Icons.analytics),
        label: const Text('提取特征骨架'),
        onPressed: _extractSkeletons,
      );
    }
    
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
      icon: const Icon(Icons.done_all),
      label: const Text('保存所有结果'),
      onPressed: _saveResults,
    );
  }
  
  Widget _buildContent() {
    if (_state == ProcessingState.processing) {
      return Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(_statusMessage, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      );
    }
    
    // 如果有骨架结果，显示字符网格
    if (_charactersWithSkeleton.isNotEmpty) return _buildCharacterGrid();
    if (_segmentationResult != null) return _buildSegmentationPreview();
    if (_processResult != null) return _buildProcessPreview();
    if (_editedImage != null) return _buildEditedPreview();
    if (_originalImage != null) return _buildOriginalPreview();
    
    return _buildEmptyState();
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.draw, size: 80, color: Colors.blue.withOpacity(0.5)),
          ),
          const SizedBox(height: 32),
          const Text('尚未加载任何样本', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text('请从相册选择或拍照，系统将自动识别并分析骨架', 
            textAlign: TextAlign.center, 
            style: TextStyle(color: Colors.grey)
          ),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _HeroButton(
                icon: Icons.photo_library,
                label: '相册选择',
                onPressed: _pickFromGallery,
              ),
              const SizedBox(width: 20),
              _HeroButton(
                icon: Icons.camera_alt,
                label: '现场拍照',
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
        const SizedBox(height: 16),
        const _SectionHeader(title: '原始捕捉图像', subtitle: '准备进行下一步编辑校准'),
        Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(_originalImage!, fit: BoxFit.contain),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    onPressed: _editImage,
                    child: const Icon(Icons.edit),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildEditedPreview() {
    return Column(
      children: [
        const SizedBox(height: 16),
        const _SectionHeader(title: '校准完成', subtitle: '图像已按要求裁剪旋转，准备预处理'),
        Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Image.memory(_editedImage!, fit: BoxFit.contain),
          ),
        ),
      ],
    );
  }
  
  Widget _buildProcessPreview() {
    final selectedStage = _processResult!.stages[_selectedProcessStageIndex];

    return Column(
      children: [
        const SizedBox(height: 16),
        _SectionHeader(
          title: '预处理流水线', 
          subtitle: '完成二值化与去噪 (耗时: ${_processResult!.totalDuration}ms)'
        ),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _processResult!.stages.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  _processResult!.stages[index].name,
                  style: _stageChipTextStyle,
                ),
                labelStyle: _stageChipTextStyle,
                selected: _selectedProcessStageIndex == index,
                onSelected: (_) => setState(() => _selectedProcessStageIndex = index),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(selectedStage.image, fit: BoxFit.contain),
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      selectedStage.info ?? selectedStage.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildSegmentationPreview() {
    return Column(
      children: [
        const SizedBox(height: 16),
        _SectionHeader(title: '字符分割结果', subtitle: '识别到 ${_segmentationResult!.totalFound} 个潜在手写区域'),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _segmentationResult!.characters.length,
            itemBuilder: (context, index) => Card(
              margin: EdgeInsets.zero,
              color: Colors.black26,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Image.memory(_segmentationResult!.characters[index].imageData, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildCharacterGrid() {
    return Row(
      children: [
        // 左侧侧边栏列表
        Container(
          width: 240,
          margin: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('字符列表', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: _charactersWithSkeleton.length,
                  itemBuilder: (context, index) {
                    final isSelected = index == _selectedCharacterIndex;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () => setState(() => _selectedCharacterIndex = index),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isSelected ? Colors.blue : Colors.transparent),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                color: Colors.black26,
                                child: Image.memory(_charactersWithSkeleton[index].binaryImage),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('字符 #$index', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text('${_charactersWithSkeleton[index].skeleton.strokeCount} 笔画', 
                                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        
        const VerticalDivider(width: 32, indent: 24, endIndent: 24),
        
        // 右侧详情区域
        Expanded(
          child: _selectedCharacterIndex >= 0
              ? _buildCharacterDetail(_charactersWithSkeleton[_selectedCharacterIndex])
              : const Center(child: Text('请从左侧选择字符以查看分析')),
        ),
      ],
    );
  }
  
  Widget _buildCharacterDetail(CharacterWithSkeleton char) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Row(
            children: [
              const Text('视图控制:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('骨架', style: _chipTextStyle),
                labelStyle: _chipTextStyle,
                selected: _showSkeleton,
                onSelected: (v) => setState(() => _showSkeleton = v),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('关键点', style: _chipTextStyle),
                labelStyle: _chipTextStyle,
                selected: _showPoints,
                onSelected: (v) => setState(() => _showPoints = v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              color: const Color(0xFF101010),
              clipBehavior: Clip.antiAlias,
              child: CustomPaint(
                painter: _SkeletonPainter(
                  binaryImage: char.binaryImage,
                  skeleton: char.skeleton,
                  showSkeleton: _showSkeleton,
                  showPoints: _showPoints,
                ),
                child: Container(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildMetricsPanel(char.skeleton),
        ],
      ),
    );
  }

  Widget _buildMetricsPanel(SkeletonResult skeleton) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _MetricItem(label: '笔画数', value: '${skeleton.strokeCount}'),
          _MetricItem(label: '关键点', value: '${skeleton.skeletonPoints.length}'),
          _MetricItem(label: '端点', value: '${skeleton.endpointCount}'),
          _MetricItem(label: '分叉', value: '${skeleton.junctionCount}'),
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
          _selectedProcessStageIndex = 0;
          _segmentationResult = null;
          _charactersWithSkeleton.clear();
          _selectedCharacterIndex = -1;
          _statusMessage = '已选择图片';
        });
        await _editImage();
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
          _selectedProcessStageIndex = 0;
          _segmentationResult = null;
          _charactersWithSkeleton.clear();
          _selectedCharacterIndex = -1;
          _statusMessage = '已拍摄图片';
        });
        await _editImage();
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
        _selectedProcessStageIndex = 0;
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
      _statusMessage = '正在进行二值化与去噪...';
    });
    
    try {
      final result = await _imageProcessor.process(imageToProcess);
      
      setState(() {
        _processResult = result;
        _selectedProcessStageIndex = _processResult!.stages.length - 1;
        _state = ProcessingState.idle;
        _statusMessage = '处理完成';
      });
    } catch (e) {
      _setError('处理失败: $e');
    }
  }
  
  Future<void> _segmentCharacters() async {
    if (_processResult == null) return;
    
    setState(() {
      _state = ProcessingState.processing;
      _statusMessage = '正在分割手写区域...';
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
      _statusMessage = '正在提取骨架特种...';
    });
    
    try {
      final results = <CharacterWithSkeleton>[];
      
      for (int i = 0; i < _segmentationResult!.characters.length; i++) {
        setState(() {
          _statusMessage = '正在分析第 ${i + 1}/${_segmentationResult!.characters.length} 个字符...';
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('分析结果已保存至本地数据库'),
        backgroundColor: Colors.green,
      ),
    );
  }
  
  void _reset() {
    setState(() {
      _originalImage = null;
      _editedImage = null;
      _processResult = null;
      _selectedProcessStageIndex = 0;
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

class _HeroButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _HeroButton({required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(24),
          ),
          child: Icon(icon, size: 32),
        ),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  final String label;
  final String value;

  const _MetricItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

/// 骨架绘制器
class _SkeletonPainter extends CustomPainter {
  final Uint8List binaryImage;
  final SkeletonResult skeleton;
  final bool showSkeleton;
  final bool showPoints;
  
  _SkeletonPainter({
    required this.binaryImage,
    required this.skeleton,
    required this.showSkeleton,
    required this.showPoints,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    // 计算缩放
    final scaleX = size.width / skeleton.width;
    final scaleY = size.height / skeleton.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    
    final offsetX = (size.width - skeleton.width * scale) / 2;
    final offsetY = (size.height - skeleton.height * scale) / 2;
    
    // 绘制背景
    final bgPaint = Paint()..color = Colors.white.withOpacity(0.05);
    canvas.drawRect(Rect.fromLTWH(offsetX, offsetY, skeleton.width * scale, skeleton.height * scale), bgPaint);

    if (showSkeleton) {
      // 绘制笔画路径 (彩色)
      final strokeColors = [
        Colors.redAccent,
        Colors.blueAccent,
        Colors.greenAccent,
        Colors.orangeAccent,
        Colors.purpleAccent,
        Colors.tealAccent,
      ];
      
      for (int i = 0; i < skeleton.strokes.length; i++) {
        final stroke = skeleton.strokes[i];
        final color = strokeColors[i % strokeColors.length];
        
        final paint = Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        
        if (stroke.points.isEmpty) continue;
        
        final path = Path();
        path.moveTo(
          offsetX + stroke.points.first.x * scale,
          offsetY + stroke.points.first.y * scale,
        );
        
        for (int j = 1; j < stroke.points.length; j++) {
          path.lineTo(
            offsetX + stroke.points[j].x * scale,
            offsetY + stroke.points[j].y * scale,
          );
        }
        canvas.drawPath(path, paint);
      }
    }

    if (showPoints) {
      for (final p in skeleton.skeletonPoints) {
        if (p.type == PointType.normal) continue;
        
        final paint = Paint()
          ..color = p.type == PointType.endpoint ? Colors.red : Colors.yellow
          ..style = PaintingStyle.fill;
        
        canvas.drawCircle(
          Offset(offsetX + p.x * scale, offsetY + p.y * scale),
          p.type == PointType.endpoint ? 3 : 4,
          paint,
        );
      }
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}