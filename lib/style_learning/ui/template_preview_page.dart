import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/download_helper.dart';
import '../../writing/font/stroke_font.dart';
import '../models/sample_template.dart';
import '../services/template_generator.dart';

/// 模板预览与导出页面
///
/// 显示生成的模板图像，并提供保存/打印功能。
class TemplatePreviewPage extends StatefulWidget {
  final SampleTemplate template;
  final StrokeFont font;

  const TemplatePreviewPage({
    super.key,
    required this.template,
    required this.font,
  });

  @override
  State<TemplatePreviewPage> createState() => _TemplatePreviewPageState();
}

class _TemplatePreviewPageState extends State<TemplatePreviewPage> {
  Uint8List? _templateImage;
  bool _isGenerating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generateTemplate();
  }

  Future<void> _generateTemplate() async {
    setState(() {
      _isGenerating = true;
      _error = null;
    });

    try {
      final generator = TemplateGenerator(widget.font, dpi: 150); // 预览用150dpi
      final imageBytes = await generator.generate(widget.template);
      setState(() {
        _templateImage = imageBytes;
        _isGenerating = false;
      });
    } catch (e) {
      setState(() {
        _error = '生成模板失败: $e';
        _isGenerating = false;
      });
    }
  }

  Future<void> _exportHighRes() async {
    setState(() => _isGenerating = true);

    try {
      final generator = TemplateGenerator(widget.font, dpi: 300);
      final imageBytes = await generator.generate(
        widget.template,
        includeReferenceGlyphs: false,
      );

      if (!mounted) return;
      setState(() => _isGenerating = false);

      final messenger = ScaffoldMessenger.of(context);
      final fileName =
          'style_template_${DateTime.now().millisecondsSinceEpoch}.png';

      if (kIsWeb) {
        await downloadBytes(
          bytes: imageBytes,
          filename: fileName,
          mimeType: 'image/png',
        );
        if (!mounted) return;
        messenger.showSnackBar(const SnackBar(content: Text('已开始下载高清模板 PNG')));
        return;
      }

      final FileSaveLocation? location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: [
          const XTypeGroup(label: 'PNG 图片', extensions: ['png']),
        ],
      );

      if (!mounted) return;
      if (location == null) {
        messenger.showSnackBar(const SnackBar(content: Text('已取消导出')));
        return;
      }

      final file = File(location.path);
      await file.writeAsBytes(imageBytes, flush: true);

      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('已保存到: ${location.path}')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '导出失败: $e';
        _isGenerating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('模板预览'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_templateImage != null)
            TextButton.icon(
              onPressed: _isGenerating ? null : _exportHighRes,
              icon: const Icon(Icons.save_alt),
              label: const Text('导出高清'),
            ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isGenerating) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在生成模板...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _generateTemplate,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_templateImage == null) {
      return const Center(child: Text('暂无模板'));
    }

    return Column(
      children: [
        // 模板信息
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.template.name,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                widget.template.description,
                style: TextStyle(
                    fontSize: 13, color: Colors.grey[400]),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _InfoChip(
                      label: '${widget.template.characterCount} 字'),
                  _InfoChip(
                      label:
                          '${widget.template.columns}×${widget.template.rows} 网格'),
                  _InfoChip(
                      label:
                          '${widget.template.cellSizeMm.toStringAsFixed(0)}mm 格子'),
                ],
              ),
            ],
          ),
        ),

        // 字符列表
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: widget.template.characters
                .map((ch) => Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(ch,
                          style: const TextStyle(fontSize: 16)),
                    ))
                .toList(),
          ),
        ),

        const SizedBox(height: 16),

        // 模板图像预览
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.memory(
                  _templateImage!,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),

        // 说明文字
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '请打印此模板，在每个格子内按照参考（浅灰色）书写对应的汉字，然后拍照上传',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500]),
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 12, color: Colors.blue)),
    );
  }
}
