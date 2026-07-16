// 这个 painter 会把 ToolPath 画到你现有的 Page 上：
// - penDown：实线（深色）
// - penUp：虚线（浅色）
// 线宽用 mm 表示，并随 viewport 缩放映射到 px（更接近真实“笔宽”）
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../model/toolpath.dart';
import '../render/viewport.dart' as kp;

class ToolPathPainter extends CustomPainter {
  final ToolPath toolPath;
  final kp.Viewport viewport;

  /// 是否渲染 penUp(抬笔) 路径（虚线/淡色）
  final bool showPenUp;

  /// 笔迹宽度（mm）
  final double penWidthMm;

  /// 虚线参数（mm）
  final double dashMm;
  final double gapMm;

  /// 是否显示起点标记
  final bool showStartPointMarker;

  /// 纸张格子大小（mm），用于计算标记大小
  final double cellSizeMm;

  ToolPathPainter({
    required this.toolPath,
    required this.viewport,
    this.showPenUp = true,
    this.penWidthMm = 0.35,
    this.dashMm = 1.2,
    this.gapMm = 0.8,
    this.showStartPointMarker = true,
    this.cellSizeMm = 8.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 将 mm 转 px
    final strokePx = (penWidthMm * viewport.scale).clamp(1.0, 6.0);
    final dashPx = (dashMm * viewport.scale).clamp(2.0, 30.0);
    final gapPx = (gapMm * viewport.scale).clamp(2.0, 30.0);

    final downPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokePx
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.indigo.shade700;

    final upPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (strokePx * 0.8).clamp(1.0, 5.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.indigo.withValues(alpha: 0.35);

    for (final pl in toolPath.polylines) {
      if (pl.points.length < 2) continue;
      if (!showPenUp && !pl.penDown) continue;
      final ptsPx = pl.points.map((p) => viewport.mmToPx(p.x, p.y)).toList();

      if (pl.penDown) {
        // 实线：逐段画即可
        for (int i = 0; i < ptsPx.length - 1; i++) {
          canvas.drawLine(ptsPx[i], ptsPx[i + 1], downPaint);
        }
      } else {
        // 虚线：逐段“切割画短线”
        for (int i = 0; i < ptsPx.length - 1; i++) {
          _drawDashedLine(
            canvas,
            ptsPx[i],
            ptsPx[i + 1],
            upPaint,
            dashPx,
            gapPx,
          );
        }
      }
    }

    // 绘制起点标记（在最上层）
    if (showStartPointMarker) {
      _drawStartPointMarker(canvas, viewport);
    }
  }

  void _drawStartPointMarker(Canvas canvas, kp.Viewport viewport) {
    if (toolPath.polylines.isEmpty) return;
    if (toolPath.polylines.first.points.isEmpty) return;

    final startPointMm = toolPath.polylines.first.points.first;
    final startPointPx = viewport.mmToPx(startPointMm.x, startPointMm.y);

    // 计算标记半径：基于格子大小的 15%，限制在 6-20px 之间
    final baseRadiusMm = cellSizeMm * 0.15;
    final radiusPx = (baseRadiusMm * viewport.scale).clamp(6.0, 20.0);

    // 外圆：红色描边
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.red;
    canvas.drawCircle(startPointPx, radiusPx, outlinePaint);

    // 内十字：白色线条
    final crossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.white
      ..strokeCap = StrokeCap.round;

    final crossSize = radiusPx * 0.6;
    // 横线
    canvas.drawLine(
      Offset(startPointPx.dx - crossSize, startPointPx.dy),
      Offset(startPointPx.dx + crossSize, startPointPx.dy),
      crossPaint,
    );
    // 竖线
    canvas.drawLine(
      Offset(startPointPx.dx, startPointPx.dy - crossSize),
      Offset(startPointPx.dx, startPointPx.dy + crossSize),
      crossPaint,
    );

    // 中心点：白色填充圆
    final centerPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;
    canvas.drawCircle(startPointPx, radiusPx * 0.3, centerPaint);
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint,
    double dashPx,
    double gapPx,
  ) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len <= 0.0001) return;

    final ux = dx / len;
    final uy = dy / len;

    double dist = 0.0;
    while (dist < len) {
      final start = dist;
      final end = math.min(dist + dashPx, len);

      final p1 = Offset(a.dx + ux * start, a.dy + uy * start);
      final p2 = Offset(a.dx + ux * end, a.dy + uy * end);
      canvas.drawLine(p1, p2, paint);

      dist += dashPx + gapPx;
    }
  }

  @override
  bool shouldRepaint(covariant ToolPathPainter oldDelegate) {
    return oldDelegate.toolPath != toolPath ||
        oldDelegate.showPenUp != showPenUp ||
        oldDelegate.viewport.scale != viewport.scale ||
        oldDelegate.viewport.pan != viewport.pan ||
        oldDelegate.showStartPointMarker != showStartPointMarker ||
        oldDelegate.cellSizeMm != cellSizeMm;
  }
}
