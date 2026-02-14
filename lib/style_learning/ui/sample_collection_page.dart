//完整的工作流程页面
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/sample_template.dart';
import '../models/style_vector.dart';
import '../services/image_capture_service.dart';
import '../services/image_processor.dart';
import '../services/grid_segmenter.dart';
import '../services/skeleton_extractor.dart';
import '../services/style_analyzer.dart';
import '../services/style_model_manager.dart';
import 'grid_outer_border_select_page.dart';
import 'image_edit_page.dart';
import 'style_analysis_page.dart';

/// 样本采集主页面
/// 
/// 完整的工作流程：
/// 1. 拍照/选择图片
/// 2. 编辑图片（裁剪、旋转等）
/// 3. 预处理（二值化）
/// 4. 框选外边框 → 网格分割
/// 5. 骨架提取
/// 6. 风格分析（基于骨架提取结果）
class SampleCollectionPage extends StatefulWidget {
  final bool embedded;

  const SampleCollectionPage({super.key, this.embedded = false});

  @override
  State<SampleCollectionPage> createState() => _SampleCollectionPageState();
}

class _SampleCollectionPageState extends State<SampleCollectionPage> {
  final ImageCaptureService _captureService = ImageCaptureService();
  final ImageProcessor _imageProcessor = ImageProcessor();
  final GridSegmenter _gridSegmenter = GridSegmenter();
  final SkeletonExtractor _skeletonExtractor = SkeletonExtractor();
  final StyleAnalyzer _styleAnalyzer = StyleAnalyzer();
  final StyleModelManager _styleModelManager = StyleModelManager();
  
  // 处理状态
  ProcessingState _state = ProcessingState.idle;
  String _statusMessage = '';
  
  // 数据
  Uint8List? _originalImage;
  Uint8List? _editedImage;
  ImageProcessResult? _processResult;
  GridSegmentResult? _gridSegmentResult;
  GridOuterBorder? _outerBorder;
  List<CharacterWithSkeleton> _charactersWithSkeleton = [];
  StyleVector? _styleVector;
  
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
          if (_styleVector != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: const Icon(Icons.save_alt),
                onPressed: _showSaveDialog,
                tooltip: '保存风格模型',
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
          _buildStepLine(_gridSegmentResult != null),
          _buildStep(4, '分割', _gridSegmentResult != null, isActive: _processResult != null),
          _buildStepLine(_charactersWithSkeleton.isNotEmpty),
          _buildStep(5, '骨架', _charactersWithSkeleton.isNotEmpty, isActive: _gridSegmentResult != null),
          _buildStepLine(_styleVector != null),
          _buildStep(6, '风格', _styleVector != null, isActive: _charactersWithSkeleton.isNotEmpty),
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
        return _editedImage != null || _processResult != null || _gridSegmentResult != null || _charactersWithSkeleton.isNotEmpty;
      case 3:
        return _processResult != null || _gridSegmentResult != null || _charactersWithSkeleton.isNotEmpty;
      case 4:
        return _gridSegmentResult != null || _charactersWithSkeleton.isNotEmpty;
      case 5:
        return _charactersWithSkeleton.isNotEmpty;
      case 6:
        return _styleVector != null;
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
        _gridSegmentResult = null;
        _outerBorder = null;
        _charactersWithSkeleton.clear();
        _selectedCharacterIndex = -1;
        _styleVector = null;
        _statusMessage = '已返回采集阶段';
      } else if (step == 2) {
        _processResult = null;
        _selectedProcessStageIndex = 0;
        _gridSegmentResult = null;
        _outerBorder = null;
        _charactersWithSkeleton.clear();
        _selectedCharacterIndex = -1;
        _styleVector = null;
        _statusMessage = '已返回校准阶段';
      } else if (step == 3) {
        _gridSegmentResult = null;
        _outerBorder = null;
        _charactersWithSkeleton.clear();
        _selectedCharacterIndex = -1;
        _styleVector = null;
        _statusMessage = '已返回预处理阶段';
      } else if (step == 4) {
        _charactersWithSkeleton.clear();
        _selectedCharacterIndex = -1;
        _styleVector = null;
        _statusMessage = '已返回分割阶段';
      } else if (step == 5) {
        _styleVector = null;
        _statusMessage = '当前为骨架分析阶段';
      } else if (step == 6) {
        _statusMessage = '当前为风格分析阶段';
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
    
    if (_gridSegmentResult == null) {
      return ElevatedButton.icon(
        icon: const Icon(Icons.grid_view),
        label: const Text('框选外边框并分割'),
        onPressed: _selectBorderAndSegment,
      );
    }
    
    if (_charactersWithSkeleton.isEmpty) {
      return ElevatedButton.icon(
        icon: const Icon(Icons.analytics),
        label: const Text('提取特征骨架'),
        onPressed: _extractSkeletons,
      );
    }

    if (_styleVector == null) {
      return Row(
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重新提取'),
            onPressed: _extractSkeletons,
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.style),
            label: const Text('分析风格'),
            onPressed: _analyzeStyle,
          ),
        ],
      );
    }
    
    return Row(
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.visibility, size: 18),
          label: const Text('详细分析'),
          onPressed: _viewDetailedAnalysis,
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          icon: const Icon(Icons.save),
          label: const Text('保存风格模型'),
          onPressed: _showSaveDialog,
        ),
      ],
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
    
    // 如果有风格分析结果，显示风格结果
    if (_styleVector != null) return _buildStyleResultView();
    // 如果有骨架结果，显示字符网格
    if (_charactersWithSkeleton.isNotEmpty) return _buildCharacterGrid();
    if (_gridSegmentResult != null) return _buildSegmentationPreview();
    if (_processResult != null) return _buildProcessPreview();
    if (_editedImage != null) return _buildEditedPreview();
    if (_originalImage != null) return _buildOriginalPreview();
    
    return _buildEmptyState();
  }
  
  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.draw, size: 64, color: Colors.blue.withValues(alpha: 0.5)),
                    ),
                    const SizedBox(height: 24),
                    const Text('尚未加载任何样本', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('请按照模板书写后拍照上传，系统将自动识别并分析', 
                      textAlign: TextAlign.center, 
                      style: TextStyle(color: Colors.grey)
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _HeroButton(
                          icon: Icons.photo_library,
                          label: '相册选择',
                          onPressed: _pickFromGallery,
                        ),
                        _HeroButton(
                          icon: Icons.camera_alt,
                          label: '现场拍照',
                          onPressed: _captureFromCamera,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
    final result = _gridSegmentResult!;
    final validCount = result.validCells.length;
    return Column(
      children: [
        const SizedBox(height: 16),
        _SectionHeader(
          title: '网格分割结果',
          subtitle: '模板「${result.template.name}」共 ${result.cells.length} 格，检测到 $validCount 个有效字符',
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: result.columns,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemCount: result.cells.length,
            itemBuilder: (context, index) {
              final cell = result.cells[index];
              return Card(
                margin: EdgeInsets.zero,
                color: cell.hasInk ? Colors.black26 : Colors.grey[900],
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Opacity(
                        opacity: cell.hasInk ? 1.0 : 0.3,
                        child: Image.memory(cell.imageData, fit: BoxFit.contain),
                      ),
                    ),
                    Positioned(
                      left: 4,
                      top: 2,
                      child: Text(
                        cell.character,
                        style: TextStyle(
                          fontSize: 10,
                          color: cell.hasInk ? Colors.blue : Colors.grey[600],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (!cell.hasInk)
                      Positioned(
                        right: 4,
                        bottom: 2,
                        child: Icon(Icons.warning_amber, size: 12, color: Colors.orange[700]),
                      ),
                  ],
                ),
              );
            },
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
                                  Text(
                                    _charactersWithSkeleton[index].character.isNotEmpty
                                      ? '「${_charactersWithSkeleton[index].character}」'
                                      : '字符 #$index',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
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
          _gridSegmentResult = null;
          _outerBorder = null;
          _charactersWithSkeleton.clear();
          _selectedCharacterIndex = -1;
          _styleVector = null;
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
          _gridSegmentResult = null;
          _outerBorder = null;
          _charactersWithSkeleton.clear();
          _selectedCharacterIndex = -1;
          _styleVector = null;
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
        _gridSegmentResult = null;
        _outerBorder = null;
        _charactersWithSkeleton.clear();
        _styleVector = null;
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
  
  Future<void> _selectBorderAndSegment() async {
    final processResult = _processResult;
    if (processResult == null) return;
    final processedImage = processResult.processedImage;

    // 先让用户选择模板
    final template = await _showTemplateSelector();
    if (template == null || !mounted) return;
    final selectedTemplate = template;

    // 进入外边框选择页面
    final border = await Navigator.push<GridOuterBorder>(
      context,
      MaterialPageRoute(
        builder: (context) => GridOuterBorderSelectPage(
          imageBytes: processedImage,
          initialBorder: _outerBorder,
        ),
      ),
    );

    if (border == null || !mounted) return;

    setState(() {
      _outerBorder = border;
      _state = ProcessingState.processing;
      _statusMessage = '正在按模板网格分割...';
    });

    try {
      final result = await _gridSegmenter.segment(
        processedImage,
        template: selectedTemplate,
        outerBorder: border,
      );

      setState(() {
        _gridSegmentResult = result;
        _state = ProcessingState.idle;
        _statusMessage = '分割完成，共 ${result.cells.length} 格，${result.validCells.length} 个有效字符';
      });
    } catch (e) {
      _setError('网格分割失败: $e');
    }
  }

  Future<SampleTemplate?> _showTemplateSelector() async {
    return showDialog<SampleTemplate>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('选择书写模板'),
          children: SampleTemplate.presets.map((t) {
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(context, t),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(t.description, style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                    const SizedBox(height: 4),
                    Text('${t.characterCount} 字 · ${t.columns} 列 × ${t.rows} 行',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
  
  Future<void> _extractSkeletons() async {
    if (_gridSegmentResult == null) return;

    final validCells = _gridSegmentResult!.validCells;
    if (validCells.isEmpty) {
      _setError('没有检测到有效的手写字符');
      return;
    }
    
    setState(() {
      _state = ProcessingState.processing;
      _statusMessage = '正在提取骨架特征...';
    });
    
    try {
      final results = <CharacterWithSkeleton>[];
      
      for (int i = 0; i < validCells.length; i++) {
        setState(() {
          _statusMessage = '正在分析第 ${i + 1}/${validCells.length} 个字符 (${validCells[i].character})...';
        });
        
        final cell = validCells[i];
        final skeleton = await _skeletonExtractor.extract(cell.imageData);
        
        results.add(CharacterWithSkeleton(
          index: i,
          binaryImage: cell.imageData,
          skeleton: skeleton,
          character: cell.character,
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
  
  Future<void> _analyzeStyle() async {
    if (_charactersWithSkeleton.isEmpty) return;

    setState(() {
      _state = ProcessingState.processing;
      _statusMessage = '正在基于骨架分析书写风格...';
    });

    try {
      // 构建分析输入
      final inputs = <CharacterAnalysisInput>[];
      for (final char in _charactersWithSkeleton) {
        inputs.add(CharacterAnalysisInput(
          skeleton: char.skeleton,
        ));
      }

      // 执行风格分析
      final style = await _styleAnalyzer.analyze(inputs);

      setState(() {
        _styleVector = style;
        _state = ProcessingState.idle;
        _statusMessage = '风格分析完成，已提取 ${style.strokeTypes.length} 种笔画类型特征';
      });
    } catch (e) {
      _setError('风格分析失败: $e');
    }
  }

  void _viewDetailedAnalysis() {
    if (_styleVector == null || _charactersWithSkeleton.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StyleAnalysisPage(
          skeletons: _charactersWithSkeleton.map((c) => c.skeleton).toList(),
        ),
      ),
    );
  }

  Future<void> _showSaveDialog() async {
    if (_styleVector == null) return;

    final controller = TextEditingController(
      text: '我的书写风格_${DateTime.now().millisecondsSinceEpoch}',
    );

    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('保存风格模型'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: '风格名称',
              hintText: '请输入风格名称',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (name != null && name.isNotEmpty && _styleVector != null) {
      try {
        await _styleModelManager.saveStyle(_styleVector!, name);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('风格模型 "$name" 已保存'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('保存失败: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // ---------- 风格分析结果视图 ----------

  Widget _buildStyleResultView() {
    final style = _styleVector!;
    final global = style.global;
    final slantDegrees = global.avgSlantAngle * 180 / math.pi;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: '风格分析完成',
            subtitle: '基于 ${style.sampleCount} 个字符的骨架提取结果',
          ),

          // 概览卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.analytics, color: Colors.blue),
                      const SizedBox(width: 8),
                      const Text('风格概览', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const Divider(),
                  _buildStyleInfoRow(Icons.format_list_numbered, '样本数量', '${style.sampleCount} 个字符'),
                  _buildStyleInfoRow(
                    Icons.rotate_right, '整体倾斜',
                    '${slantDegrees.toStringAsFixed(1)}°',
                    valueColor: slantDegrees.abs() > 5 ? Colors.orange : Colors.green,
                  ),
                  _buildStyleInfoRow(Icons.aspect_ratio, '平均高宽比', global.avgAspectRatio.toStringAsFixed(2)),
                  _buildStyleInfoRow(Icons.density_small, '笔画密度', global.avgStrokeDensity.toStringAsFixed(4)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 全局特征
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.public, color: Colors.green),
                      const SizedBox(width: 8),
                      const Text('全局特征', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const Divider(),
                  _buildFeatureBar('重心位置 X', global.centerOfGravityX, 0, 1),
                  _buildFeatureBar('重心位置 Y', global.centerOfGravityY, 0, 1),
                  _buildFeatureBar('笔画间距一致性', 1 - global.strokeSpacingStd.clamp(0.0, 1.0), 0, 1, color: Colors.purple),
                  _buildFeatureBar('倾斜一致性', 1 - global.slantAngleStd.clamp(0.0, 1.0), 0, 1, color: Colors.orange),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 笔画类型特征
          if (style.strokeTypes.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.edit, color: Colors.indigo),
                        const SizedBox(width: 8),
                        const Text('笔画类型特征', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const Divider(),
                    ...style.strokeTypes.entries.map((entry) {
                      final features = entry.value;
                      return ExpansionTile(
                        title: Text(entry.key),
                        subtitle: Text('${features.sampleCount} 个样本'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                _buildStyleDetailRow('平均长度', features.avgLength.toStringAsFixed(1)),
                                _buildStyleDetailRow('平均曲率', features.avgCurvature.toStringAsFixed(4)),
                                _buildStyleDetailRow('起笔角度', '${(features.avgStartAngle * 180 / math.pi).toStringAsFixed(1)}°'),
                                _buildStyleDetailRow('收笔角度', '${(features.avgEndAngle * 180 / math.pi).toStringAsFixed(1)}°'),
                              ],
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStyleInfoRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Text(label),
          const Spacer(),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: valueColor)),
        ],
      ),
    );
  }

  Widget _buildFeatureBar(String label, double value, double min, double max, {Color? color}) {
    final percentage = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text(value.toStringAsFixed(2)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: percentage,
            backgroundColor: Colors.grey[800],
            valueColor: AlwaysStoppedAnimation(color ?? Colors.blue),
          ),
        ],
      ),
    );
  }

  Widget _buildStyleDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
  
  void _reset() {
    setState(() {
      _originalImage = null;
      _editedImage = null;
      _processResult = null;
      _selectedProcessStageIndex = 0;
      _gridSegmentResult = null;
      _outerBorder = null;
      _charactersWithSkeleton.clear();
      _selectedCharacterIndex = -1;
      _styleVector = null;
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
  final String character;
  
  CharacterWithSkeleton({
    required this.index,
    required this.binaryImage,
    required this.skeleton,
    this.character = '',
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