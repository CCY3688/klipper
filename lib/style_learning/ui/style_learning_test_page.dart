import 'package:flutter/material.dart';
import 'dart:math';
import '../models/character_data.dart';

/// 测试页面 - 验证基础数据结构
class StyleLearningTestPage extends StatefulWidget {
  const StyleLearningTestPage({super.key});

  @override
  State<StyleLearningTestPage> createState() => _StyleLearningTestPageState();
}

class _StyleLearningTestPageState extends State<StyleLearningTestPage> {
  CharacterData? _testChar;
  String _log = '';

  @override
  void initState() {
    super.initState();
    _runTest();
  }

  void _runTest() {
    _log = '开始测试...\n';

    // 使用你提供的示例数据
    final testJson = {
      "character": "丕",
      "strokes": [
        "M 585 690 Q 604 696 788 710 Q 800 709 811 722 Q 812 735 788 748 Q 746 773 687 757 Q 488 718 235 696 Q 201 695 226 673 Q 265 643 292 647 Q 406 666 547 686 L 585 690 Z",
        "M 547 686 Q 547 685 548 683 Q 549 641 500 567 L 464 517 Q 454 507 443 493 Q 349 382 111 236 Q 101 232 112 227 Q 185 227 349 341 Q 391 377 467 447 L 520 504 Q 601 603 624 622 Q 633 626 633 637 Q 633 647 621 662 Q 599 689 585 690 C 558 704 548 709 547 686 Z",
        "M 500 567 Q 470 597 457 603 Q 447 604 443 598 Q 436 580 451 554 Q 461 535 464 517 L 467 447 Q 467 369 450 287 Q 446 268 454 234 Q 466 200 477 188 Q 495 172 507 199 Q 522 239 521 286 Q 517 458 520 504 C 521 534 521 546 500 567 Z",
        "M 610 431 Q 700 376 810 291 Q 829 273 846 271 Q 855 271 861 283 Q 871 299 851 340 Q 824 398 606 463 Q 596 467 596 454 Q 597 441 610 431 Z",
        "M 176 104 Q 151 103 168 83 Q 204 47 246 56 Q 468 105 840 82 Q 862 81 869 90 Q 876 103 858 120 Q 795 171 730 156 Q 567 135 176 104 Z"
      ],
      "medians": [
        [[228, 686], [258, 676], [294, 674], [715, 733], [761, 733], [800, 724]],
        [[553, 686], [584, 642], [508, 530], [430, 443], [309, 340], [188, 264], [116, 232]],
        [[454, 589], [479, 553], [492, 502], [492, 364], [485, 277], [490, 200]],
        [[608, 451], [788, 353], [827, 318], [844, 288]],
        [[172, 94], [227, 81], [428, 105], [743, 123], [785, 121], [857, 98]]
      ]
    };

    try {
      // 测试解析
      _testChar = CharacterData.fromLibraryJson(testJson);
      _log += '✅ 解析成功: $_testChar\n';

      // 测试笔画数据
      for (int i = 0; i < _testChar!.strokes.length; i++) {
        final stroke = _testChar!.strokes[i];
        _log += '  笔画${i + 1}: ${stroke.medians.length}个点\n';
        _log += '    边界框: ${stroke.boundingBox}\n';
      }

      // 测试转换回JSON
      final backToJson = _testChar!.toLibraryJson();
      _log += '✅ 转回JSON成功\n';
      _log += '  字符: ${backToJson['character']}\n';
      _log += '  笔画数: ${(backToJson['strokes'] as List).length}\n';

      _log += '\n🎉 所有测试通过！\n';
    } catch (e) {
      _log += '❌ 错误: $e\n';
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('风格学习 - MVP-0 测试'),
      ),
      body: Column(
        children: [
          // 日志输出
          Expanded(
            flex: 1,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.black87,
              child: SingleChildScrollView(
                child: Text(
                  _log,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Colors.greenAccent,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),

          // 可视化预览
          Expanded(
            flex: 2,
            child: _testChar != null
                ? _CharacterPreview(character: _testChar!)
                : const Center(child: Text('加载中...')),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _runTest,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

/// 字符预览组件 - 绘制笔画中线
class _CharacterPreview extends StatelessWidget {
  final CharacterData character;

  const _CharacterPreview({required this.character});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: InteractiveViewer(
          boundaryMargin: const EdgeInsets.all(100),
          minScale: 0.5,
          maxScale: 4.0,
          child: CustomPaint(
            painter: _StrokePainter(character),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

/// 笔画绘制器
class _StrokePainter extends CustomPainter {
  final CharacterData character;

  // 不同笔画的颜色
  final List<Color> strokeColors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
  ];

  _StrokePainter(this.character);

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 外框
    canvas.drawRect(Offset.zero & size, paint);

    // 计算字符区域的中心和缩放（与 paint 方法一致）
    final availableSize = min(size.width, size.height) * 0.8;
    final scale = availableSize / 1024;
    final offsetX = (size.width - 1024 * scale) / 2;
    final offsetY = (size.height - 1024 * scale) / 2;
    final rect = Rect.fromLTWH(offsetX, offsetY, 1024 * scale, 1024 * scale);

    final gridPaint = Paint()
      ..color = Colors.red.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 绘制米字格
    canvas.drawRect(rect, gridPaint);
    canvas.drawLine(rect.topLeft, rect.bottomRight, gridPaint);
    canvas.drawLine(rect.topRight, rect.bottomLeft, gridPaint);
    canvas.drawLine(
      Offset(rect.left + rect.width / 2, rect.top),
      Offset(rect.left + rect.width / 2, rect.bottom),
      gridPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.top + rect.height / 2),
      Offset(rect.right, rect.top + rect.height / 2),
      gridPaint,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 绘制米字格背景
    _drawGrid(canvas, size);

    // 2. 计算缩放和偏移，使字符居中且完整显示
    // 字库坐标系：1024x1024，原点在左下角
    // Flutter坐标系：原点在左上角
    
    // 留出 10% 的边距
    final availableSize = min(size.width, size.height) * 0.8;
    final scale = availableSize / 1024;
    
    // 居中偏移
    final offsetX = (size.width - 1024 * scale) / 2;
    final offsetY = (size.height - 1024 * scale) / 2;

    // 3. 绘制每个笔画
    for (int i = 0; i < character.strokes.length; i++) {
      final stroke = character.strokes[i];
      final color = strokeColors[i % strokeColors.length];

      final paint = Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final pointPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      if (stroke.medians.isEmpty) continue;

      final path = Path();
      
      for (int j = 0; j < stroke.medians.length; j++) {
        final point = stroke.medians[j];
        // 坐标转换：Y轴翻转
        final x = point[0] * scale + offsetX;
        final y = (1024 - point[1]) * scale + offsetY;

        if (j == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }

        // 绘制关键点
        canvas.drawCircle(Offset(x, y), 4, pointPaint);
      }

      canvas.drawPath(path, paint);

      // 标注笔画序号
      final firstPoint = stroke.medians.first;
      final textX = firstPoint[0] * scale + offsetX;
      final textY = (1024 - firstPoint[1]) * scale + offsetY - 15;

      final textPainter = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(textX - 5, textY));
    }

    // 绘制字符信息
    final infoPainter = TextPainter(
      text: TextSpan(
        text: '"${character.character}" - ${character.strokeCount}笔',
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 20,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    infoPainter.layout();
    infoPainter.paint(canvas, Offset(10, size.height - 30));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}