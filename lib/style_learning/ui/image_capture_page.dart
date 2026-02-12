import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/handwriting_sample.dart';
import '../services/character_segmenter.dart';
import '../services/image_capture_service.dart';
import '../services/image_processor.dart';
import '../services/skeleton_extractor.dart';
import 'image_edit_page.dart';

/// 图像采集页面 - 重构为 Fluidd 风格
class ImageCapturePage extends StatefulWidget {
  const ImageCapturePage({super.key});

  @override
  State<ImageCapturePage> createState() => _ImageCapturePageState();
}

class _ImageCapturePageState extends State<ImageCapturePage> {
  final ImageCaptureService _captureService = ImageCaptureService();
  final ImageProcessor _imageProcessor = ImageProcessor();
  final CharacterSegmenter _segmenter = CharacterSegmenter();
  final SkeletonExtractor _skeletonExtractor = SkeletonExtractor();
  
  HandwritingSample? _currentSample;
  ImageProcessResult? _processResult;
  SegmentationResult? _segmentationResult;
  List<SkeletonResult> _skeletonResults = [];
  bool _isProcessing = false;
  String? _errorMessage;
  String _processingMessage = '正在执行二值化与噪声抑制';
  int _selectedStageIndex = 0;

  // 颜色定义
  final Color _panelBg = const Color(0xFF212529);
  final Color _mainBg = const Color(0xFF181A1B);
  final Color _accentColor = Colors.blue;
  final Color _textColor = Colors.white;
  final Color _subTextColor = Colors.grey[400]!;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _mainBg,
      child: Column(
        children: [
          // 图像选择按钮区域 (Top Panel)
          _buildCaptureButtons(),
          
          const SizedBox(height: 8),
          
          // 主要内容区域 (Fluid Layout)
          Expanded(
            child: _buildMainContent(),
          ),
        ],
      ),
    );
  }
  
  /// 构建采集按钮
  Widget _buildCaptureButtons() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panelBg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: _FluiddButton(
              icon: Icons.photo_library,
              label: '相册选择',
              onPressed: _pickFromGallery,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _FluiddButton(
              icon: Icons.camera_alt,
              label: (kIsWeb || Platform.isWindows) ? '相机不可用' : '拍照采集',
              onPressed: (kIsWeb || Platform.isWindows) 
                ? () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('当前平台暂不支持通过摄像头直接采集，请使用“相册选择”导入。')))
                : _captureFromCamera,
              disabled: (kIsWeb || Platform.isWindows),
            ),
          ),
          if (_currentSample != null) ...[
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.orange),
              onPressed: _clearSample,
              tooltip: '清除样本',
            ),
          ]
        ],
      ),
    );
  }
  
  /// 构建主要内容
  Widget _buildMainContent() {
    if (_errorMessage != null) return _buildErrorView();
    if (_currentSample == null) return _buildEmptyState();
    if (_isProcessing) return _buildProcessingView();
    if (_processResult != null) return _buildResultView();
    
    return _buildPreviewView();
  }
  
  /// 空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_search, size: 64, color: _panelBg),
          const SizedBox(height: 16),
          Text(
            '尚未采集手写样本',
            style: TextStyle(fontSize: 18, color: _subTextColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('使用上方按钮从相册或相机导入手写汉字图片', style: TextStyle(color: _subTextColor.withOpacity(0.6))),
        ],
      ),
    );
  }
  
  /// 错误视图
  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.redAccent),
          const SizedBox(height: 16),
          Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 24),
          _FluiddButton(label: '重新采集', onPressed: _clearError, isPrimary: true),
        ],
      ),
    );
  }
  
  /// 处理中视图
  Widget _buildProcessingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(height: 24),
          Text('深度学习处理中...', style: TextStyle(color: _textColor, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Text(_processingMessage, style: TextStyle(color: _subTextColor, fontSize: 12)),
        ],
      ),
    );
  }
  
  /// 预览视图（处理前）
  Widget _buildPreviewView() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _panelBg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            width: double.infinity,
            color: Colors.black26,
            child: const Text('样本预览', style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black54),
              ),
              child: Image.memory(_currentSample!.originalImage, fit: BoxFit.contain),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                onPressed: _processImage,
                child: const Text('开始 AI 分析', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  /// 结果视图（处理后）
  Widget _buildResultView() {
    final stages = _processResult!.stages;
    final currentStage = stages[_selectedStageIndex];
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Processed Image
        Expanded(
          flex: 2,
          child: Container(
            margin: const EdgeInsets.only(left: 12, bottom: 12, right: 6),
            decoration: BoxDecoration(color: _panelBg, borderRadius: BorderRadius.circular(4)),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  width: double.infinity,
                  color: Colors.black26,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('处理序列: ${currentStage.name}', style: const TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
                      Text('${_selectedStageIndex + 1} / ${stages.length}', style: TextStyle(color: _subTextColor, fontSize: 10)),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: InteractiveViewer(
                       child: Image.memory(currentStage.image, fit: BoxFit.contain),
                    ),
                  ),
                ),
                // Stage selector (Bottom strip)
                Container(
                  height: 40,
                  color: Colors.black12,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: stages.length,
                    itemBuilder: (context, index) {
                      final isSelected = index == _selectedStageIndex;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedStageIndex = index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: isSelected ? _accentColor : Colors.transparent, width: 2)),
                          ),
                          child: Text(stages[index].name, style: TextStyle(color: isSelected ? _textColor : _subTextColor, fontSize: 12)),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // Right Column: Info & Actions
        Expanded(
          flex: 1,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(right: 12, bottom: 12, left: 6),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: _panelBg, borderRadius: BorderRadius.circular(4)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('性能统计', style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _InfoRow(label: '当前步骤耗时', value: '${currentStage.duration}ms'),
                    _InfoRow(label: 'AI 总耗时', value: '${_processResult!.totalDuration}ms'),
                    const Divider(color: Colors.white10, height: 24),
                    const Text('算法详情', style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(currentStage.info ?? '执行标准边缘检测与特征提取', style: TextStyle(color: _subTextColor, fontSize: 12)),
                  ],
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.only(right: 12, left: 6),
                child: Column(
                  children: [
                    _FluiddButton(label: '提取笔画骨架', icon: Icons.auto_awesome, onPressed: _extractSkeletons, isPrimary: true),
                    const SizedBox(height: 8),
                    _FluiddButton(label: '重新编辑图片', icon: Icons.edit, onPressed: _editCurrentImage),
                    if (_skeletonResults.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _FluiddButton(label: '查看骨架结果', icon: Icons.visibility, onPressed: _showSkeletonResultSheet),
                    ],
                    const SizedBox(height: 8),
                    _FluiddButton(label: '重新选择样本', icon: Icons.arrow_back, onPressed: _clearSample),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  // ==================== 操作方法 ====================
  
  Future<void> _pickFromGallery() async {
    try {
      setState(() => _errorMessage = null);
      final sample = await _captureService.pickFromGallery();
      if (sample != null) {
        await _openImageEditor(sample);
      }
    } catch (e) { setState(() => _errorMessage = e.toString()); }
  }
  
  Future<void> _captureFromCamera() async {
    try {
      setState(() => _errorMessage = null);
      final sample = await _captureService.captureFromCamera();
      if (sample != null) {
        await _openImageEditor(sample);
      }
    } catch (e) { setState(() => _errorMessage = e.toString()); }
  }

  Future<void> _openImageEditor(HandwritingSample sample) async {
    if (!mounted) return;

    final edited = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        builder: (context) => ImageEditPage(imageBytes: sample.originalImage),
      ),
    );

    if (!mounted) return;

    final nextSample = edited == null
        ? sample
        : HandwritingSample(
            id: sample.id,
            character: sample.character,
            originalImage: edited,
            capturedAt: sample.capturedAt,
            source: sample.source,
          );

    setState(() {
      _currentSample = nextSample;
      _processResult = null;
      _segmentationResult = null;
      _skeletonResults = [];
      _selectedStageIndex = 0;
    });
  }

  Future<void> _editCurrentImage() async {
    final sample = _currentSample;
    if (sample == null) return;
    await _openImageEditor(sample);
  }
  
  Future<void> _processImage() async {
    if (_currentSample == null) return;
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _processingMessage = '正在执行二值化与噪声抑制';
    });
    try {
      final result = await _imageProcessor.process(_currentSample!.originalImage);
      setState(() {
        _processResult = result;
        _segmentationResult = null;
        _skeletonResults = [];
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '处理失败: $e';
        _isProcessing = false;
      });
    }
  }

  Future<void> _extractSkeletons() async {
    if (_processResult == null) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _processingMessage = '正在分割字符区域...';
    });

    try {
      final segmentation = await _segmenter.segment(_processResult!.processedImage);
      final skeletons = <SkeletonResult>[];

      for (int i = 0; i < segmentation.characters.length; i++) {
        if (!mounted) return;
        setState(() {
          _processingMessage = '正在提取第 ${i + 1}/${segmentation.characters.length} 个字符骨架...';
        });
        final result = await _skeletonExtractor.extract(segmentation.characters[i].imageData);
        skeletons.add(result);
      }

      if (!mounted) return;
      setState(() {
        _segmentationResult = segmentation;
        _skeletonResults = skeletons;
        _isProcessing = false;
      });

      if (skeletons.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未检测到有效字符，无法提取骨架')),
        );
        return;
      }

      _showSkeletonResultSheet();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '骨架提取失败: $e';
        _isProcessing = false;
      });
    }
  }

  void _showSkeletonResultSheet() {
    if (_segmentationResult == null || _skeletonResults.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panelBg,
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white10)),
                ),
                child: Text(
                  '骨架提取结果（${_skeletonResults.length} 个字符）',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _skeletonResults.length,
                  itemBuilder: (context, index) {
                    final skeleton = _skeletonResults[index];
                    final segmented = _segmentationResult!.characters[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C3136),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('字符 #${index + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 140,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    children: [
                                      const Text('分割图', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                      const SizedBox(height: 6),
                                      Expanded(child: Image.memory(segmented.imageData, fit: BoxFit.contain)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    children: [
                                      const Text('骨架图', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                      const SizedBox(height: 6),
                                      Expanded(child: Image.memory(skeleton.skeletonImage, fit: BoxFit.contain)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            children: [
                              _MetricChip(label: '笔画', value: '${skeleton.strokeCount}'),
                              _MetricChip(label: '端点', value: '${skeleton.endpointCount}'),
                              _MetricChip(label: '交叉点', value: '${skeleton.junctionCount}'),
                              _MetricChip(label: '骨架点', value: '${skeleton.skeletonPoints.length}'),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  void _clearSample() => setState(() {
    _currentSample = null;
    _processResult = null;
    _segmentationResult = null;
    _skeletonResults = [];
    _errorMessage = null;
    _selectedStageIndex = 0;
  });
  void _clearError() => setState(() => _errorMessage = null);
}

/// Fluidd 风格按钮
class _FluiddButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback onPressed;
  final bool isPrimary;
  final bool disabled;
  
  const _FluiddButton({
    required this.label, 
    required this.onPressed, 
    this.icon, 
    this.isPrimary = false,
    this.disabled = false,
  });
  
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        icon: icon != null ? Icon(icon, size: 18, color: disabled ? Colors.grey : Colors.white) : const SizedBox.shrink(),
        label: Text(label, style: TextStyle(
          fontWeight: FontWeight.bold, 
          fontSize: 13,
          color: disabled ? Colors.grey : Colors.white,
        )),
        style: TextButton.styleFrom(
          backgroundColor: disabled ? const Color(0xFF1E1E1E) : (isPrimary ? Colors.blue : const Color(0xFF2C3136)),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        onPressed: disabled ? null : onPressed,
      ),
    );
  }
}

/// 信息行
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
          Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}