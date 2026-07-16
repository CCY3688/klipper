// 支持多种纸张类型的绘制器
// 根据 PaperConfig 绘制格子纸/横线格/信纸笺(竖线格)/空白纸
import 'package:flutter/material.dart';
import '../model/paper_type.dart';
import '../render/viewport.dart' as kp;

class PaperTypePainter extends CustomPainter {
  final PaperConfig config;
  final kp.Viewport viewport;

  PaperTypePainter({required this.config, required this.viewport});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 绘制浅灰背景（画布区域）
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF7F7F7),
    );

    // 2. 绘制白色纸张
    final pageRectMm = Rect.fromLTWH(0, 0, config.pageWidthMm, config.pageHeightMm);
    final pageRectPx = viewport.mmRectToPx(pageRectMm);
    canvas.drawRect(pageRectPx, Paint()..color = Colors.white);
    
    // 纸张边界
    canvas.drawRect(
      pageRectPx,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.black38,
    );

    // 3. 根据纸张类型绘制网格/线条
    final lineColor = Color(config.lineColorValue);
    final lineWidth = (config.lineWidthMm * viewport.scale).clamp(0.3, 4.0);
    
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..color = lineColor;

    switch (config.kind) {
      case PaperTypeKind.grid:
        _drawGrid(canvas, linePaint);
        break;
      case PaperTypeKind.horizontal:
        _drawHorizontalLines(canvas, linePaint);
        break;
      case PaperTypeKind.letter:
        _drawVerticalLines(canvas, linePaint);
        break;
      case PaperTypeKind.blank:
        // 空白纸不画线
        break;
    }
  }

  /// 格子纸：画完整的行列网格
  void _drawGrid(Canvas canvas, Paint paint) {
    final left = config.marginLeftMm;
    final top = config.marginTopMm;
    final cols = config.cols;
    final rows = config.rows;
    final cell = config.cellSizeMm;
    final rowGap = config.gridRowSpacingMm;

    for (int r = 0; r < rows; r++) {
      final yTop = top + r * (cell + rowGap);
      
      for (int c = 0; c < cols; c++) {
        final xLeft = left + c * cell;
        
        final rectMm = Rect.fromLTWH(xLeft, yTop, cell, cell);
        final rectPx = viewport.mmRectToPx(rectMm);
        canvas.drawRect(rectPx, paint);
      }
    }
  }

  /// 横线格：只画横线
  void _drawHorizontalLines(Canvas canvas, Paint paint) {
    final left = config.marginLeftMm;
    final right = config.pageWidthMm - config.marginRightMm;
    final top = config.marginTopMm;
    final rows = config.rows;
    final spacing = config.lineSpacingMm;

    for (int r = 0; r <= rows; r++) {
      final y = top + r * spacing;
      final p1 = viewport.mmToPx(left, y);
      final p2 = viewport.mmToPx(right, y);
      canvas.drawLine(p1, p2, paint);
    }
  }

  /// 信纸笺（竖线格）：画竖线 + 顶底横线框
  void _drawVerticalLines(Canvas canvas, Paint paint) {
    final left = config.marginLeftMm;
    final top = config.marginTopMm;
    final bottom = config.pageHeightMm - config.marginBottomMm;
    final cols = config.cols;
    final cell = config.cellSizeMm;

    // 顶部横线
    final pTopLeft = viewport.mmToPx(left, top);
    final pTopRight = viewport.mmToPx(left + cols * cell, top);
    canvas.drawLine(pTopLeft, pTopRight, paint);

    // 底部横线
    final pBotLeft = viewport.mmToPx(left, bottom);
    final pBotRight = viewport.mmToPx(left + cols * cell, bottom);
    canvas.drawLine(pBotLeft, pBotRight, paint);

    // 竖线
    for (int c = 0; c <= cols; c++) {
      final x = left + c * cell;
      final p1 = viewport.mmToPx(x, top);
      final p2 = viewport.mmToPx(x, bottom);
      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant PaperTypePainter oldDelegate) {
    return oldDelegate.config != config ||
        oldDelegate.viewport.scale != viewport.scale ||
        oldDelegate.viewport.pan != viewport.pan;
  }
}
