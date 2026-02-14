import 'package:flutter/material.dart';
import '../models/style_vector.dart';
import '../services/style_analyzer.dart';
import '../services/style_model_manager.dart';
import '../services/skeleton_extractor.dart';
import 'dart:math' as math;

/// 风格分析页面
class StyleAnalysisPage extends StatefulWidget {
  /// 已提取骨架的字符列表
  final List<SkeletonResult> skeletons;

  /// 字符列表（可选，用于标注）
  final List<String>? characters;

  const StyleAnalysisPage({
    super.key,
    required this.skeletons,
    this.characters,
  });

  @override
  State<StyleAnalysisPage> createState() => _StyleAnalysisPageState();
}

class _StyleAnalysisPageState extends State<StyleAnalysisPage> {
  final StyleAnalyzer _analyzer = StyleAnalyzer();
  final StyleModelManager _modelManager = StyleModelManager();

  StyleVector? _styleVector;
  bool _isAnalyzing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _analyzeStyle();
  }

  Future<void> _analyzeStyle() async {
    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    try {
      // 构建分析输入
      final inputs = <CharacterAnalysisInput>[];
      for (int i = 0; i < widget.skeletons.length; i++) {
        inputs.add(CharacterAnalysisInput(
          character: widget.characters != null && i < widget.characters!.length
              ? widget.characters![i]
              : null,
          skeleton: widget.skeletons[i],
        ));
      }

      // 执行分析
      final style = await _analyzer.analyze(inputs);

      setState(() {
        _styleVector = style;
        _isAnalyzing = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '分析失败: $e';
        _isAnalyzing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('风格分析'),
        actions: [
          if (_styleVector != null)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _showSaveDialog,
              tooltip: '保存风格',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isAnalyzing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在分析书写风格...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _analyzeStyle,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_styleVector == null) {
      return const Center(child: Text('暂无数据'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 概览卡片
          _buildOverviewCard(),
          const SizedBox(height: 16),

          // 全局特征
          _buildGlobalFeaturesCard(),
          const SizedBox(height: 16),

          // 笔画类型特征
          _buildStrokeTypesCard(),
          const SizedBox(height: 16),

          // 可视化
          _buildVisualizationCard(),
        ],
      ),
    );
  }

  Widget _buildOverviewCard() {
    final style = _styleVector!;
    final slantDegrees = style.global.avgSlantAngle * 180 / math.pi;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  '风格概览',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            _InfoTile(
              icon: Icons.format_list_numbered,
              label: '样本数量',
              value: '${style.sampleCount} 个字符',
            ),
            _InfoTile(
              icon: Icons.rotate_right,
              label: '整体倾斜',
              value: '${slantDegrees.toStringAsFixed(1)}°',
              valueColor: slantDegrees.abs() > 5 ? Colors.orange : Colors.green,
            ),
            _InfoTile(
              icon: Icons.aspect_ratio,
              label: '平均高宽比',
              value: style.global.avgAspectRatio.toStringAsFixed(2),
            ),
            _InfoTile(
              icon: Icons.density_small,
              label: '笔画密度',
              value: style.global.avgStrokeDensity.toStringAsFixed(4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalFeaturesCard() {
    final global = _styleVector!.global;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.public, color: Colors.green),
                const SizedBox(width: 8),
                const Text(
                  '全局特征',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            _FeatureBar(
              label: '重心位置 X',
              value: global.centerOfGravityX,
              min: 0,
              max: 1,
            ),
            _FeatureBar(
              label: '重心位置 Y',
              value: global.centerOfGravityY,
              min: 0,
              max: 1,
            ),
            _FeatureBar(
              label: '笔画间距一致性',
              value: 1 - global.strokeSpacingStd.clamp(0, 1),
              min: 0,
              max: 1,
              color: Colors.purple,
            ),
            _FeatureBar(
              label: '倾斜一致性',
              value: 1 - global.slantAngleStd.clamp(0, 1),
              min: 0,
              max: 1,
              color: Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStrokeTypesCard() {
    final strokeTypes = _styleVector!.strokeTypes;

    if (strokeTypes.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.edit, color: Colors.grey),
              const SizedBox(height: 8),
              const Text('未检测到笔画类型信息'),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.edit, color: Colors.indigo),
                const SizedBox(width: 8),
                const Text(
                  '笔画类型特征',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            ...strokeTypes.entries.map((entry) {
              return _StrokeTypeItem(
                typeName: entry.key,
                features: entry.value,
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildVisualizationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pie_chart, color: Colors.teal),
                const SizedBox(width: 8),
                const Text(
                  '风格可视化',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            SizedBox(
              height: 200,
              child: CustomPaint(
                painter: _StyleRadarPainter(_styleVector!),
                size: Size.infinite,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSaveDialog() async {
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
        await _modelManager.saveStyle(_styleVector!, name);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('风格 "$name" 已保存')),
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
}

// ==================== 辅助组件 ====================

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Text(label),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureBar extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final Color? color;

  const _FeatureBar({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
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
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation(color ?? Colors.blue),
          ),
        ],
      ),
    );
  }
}

class _StrokeTypeItem extends StatelessWidget {
  final String typeName;
  final StrokeTypeFeatures features;

  const _StrokeTypeItem({
    required this.typeName,
    required this.features,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(typeName),
      subtitle: Text('${features.sampleCount} 个样本'),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _InfoRow('平均长度', features.avgLength.toStringAsFixed(1)),
              _InfoRow('平均曲率', features.avgCurvature.toStringAsFixed(4)),
              _InfoRow(
                '起笔角度',
                '${(features.avgStartAngle * 180 / math.pi).toStringAsFixed(1)}°',
              ),
              _InfoRow(
                '收笔角度',
                '${(features.avgEndAngle * 180 / math.pi).toStringAsFixed(1)}°',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
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
}

/// 雷达图绘制器
class _StyleRadarPainter extends CustomPainter {
  final StyleVector style;

  _StyleRadarPainter(this.style);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 30;

    // 绘制背景网格
    _drawGrid(canvas, center, radius);

    // 绘制数据
    _drawData(canvas, center, radius);

    // 绘制标签
    _drawLabels(canvas, center, radius);
  }

  void _drawGrid(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..color = Colors.grey[300]!
      ..style = PaintingStyle.stroke;

    // 绘制同心圆
    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, radius * i / 4, paint);
    }

    // 绘制辐射线
    const labels = ['倾斜', '曲率', '密度', '一致性', '重心X', '重心Y'];
    for (int i = 0; i < labels.length; i++) {
      final angle = -math.pi / 2 + 2 * math.pi * i / labels.length;
      final end = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawLine(center, end, paint);
    }
  }

  void _drawData(Canvas canvas, Offset center, double radius) {
    final global = style.global;

    // 归一化特征值到 0-1
    final values = [
      (global.avgSlantAngle.abs() / 0.5).clamp(0.0, 1.0), // 倾斜
      global.avgStrokeDensity.clamp(0.0, 1.0), // 曲率（用密度代替）
      global.avgStrokeDensity.clamp(0.0, 1.0), // 密度
      (1 - global.slantAngleStd).clamp(0.0, 1.0), // 一致性
      global.centerOfGravityX, // 重心X
      global.centerOfGravityY, // 重心Y
    ];

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final angle = -math.pi / 2 + 2 * math.pi * i / values.length;
      final r = radius * values[i];
      final point = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );

      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();

    // 填充
    final fillPaint = Paint()
      ..color = Colors.blue.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // 边框
    final strokePaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, strokePaint);

    // 绘制数据点
    final pointPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    for (int i = 0; i < values.length; i++) {
      final angle = -math.pi / 2 + 2 * math.pi * i / values.length;
      final r = radius * values[i];
      final point = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      canvas.drawCircle(point, 4, pointPaint);
    }
  }

  void _drawLabels(Canvas canvas, Offset center, double radius) {
    const labels = ['倾斜', '曲率', '密度', '一致性', '重心X', '重心Y'];

    for (int i = 0; i < labels.length; i++) {
      final angle = -math.pi / 2 + 2 * math.pi * i / labels.length;
      final labelRadius = radius + 20;
      final point = Offset(
        center.dx + labelRadius * math.cos(angle),
        center.dy + labelRadius * math.sin(angle),
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: const TextStyle(color: Colors.black87, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        point - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}