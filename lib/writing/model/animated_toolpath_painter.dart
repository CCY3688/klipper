import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'toolpath.dart';
import '../render/viewport.dart' as kp;

/// 动态预览的轨迹绘制器
/// 
/// 根据 progress (0.0 ~ 1.0) 渐进式绘制轨迹，并在当前位置显示"笔尖"
/// - 落笔时笔尖填充黑色
/// - 抬笔时笔尖填充灰白色
class AnimatedToolPathPainter extends CustomPainter {
  final ToolPath toolPath;
  final kp.Viewport viewport;
  
  /// 动画进度 0.0 ~ 1.0
  final double progress;
  
  /// 是否渲染 penUp(抬笔) 路径
  final bool showPenUp;
  
  /// 笔迹宽度（mm）
  final double penWidthMm;
  
  /// 笔尖半径（mm）
  final double penTipRadiusMm;
  
  /// 虚线参数（mm）
  final double dashMm;
  final double gapMm;

  AnimatedToolPathPainter({
    required this.toolPath,
    required this.viewport,
    required this.progress,
    this.showPenUp = true,
    this.penWidthMm = 0.35,
    this.penTipRadiusMm = 1.5,
    this.dashMm = 1.2,
    this.gapMm = 0.8,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (toolPath.polylines.isEmpty) return;
    
    // 计算总路径长度
    final totalLength = _calculateTotalLength();
    if (totalLength <= 0) return;
    
    final targetLength = totalLength * progress;
    
    // 将 mm 转 px
    final strokePx = (penWidthMm * viewport.scale).clamp(1.0, 6.0);
    final dashPx = (dashMm * viewport.scale).clamp(2.0, 30.0);
    final gapPx = (gapMm * viewport.scale).clamp(2.0, 30.0);
    final penTipRadiusPx = (penTipRadiusMm * viewport.scale).clamp(3.0, 15.0);

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

    double accumulatedLength = 0.0;
    Offset? penTipPosition;
    bool penTipDown = true;

    for (final pl in toolPath.polylines) {
      if (pl.points.length < 2) continue;
      if (!showPenUp && !pl.penDown) continue;
      
      final ptsMm = pl.points;
      
      for (int i = 0; i < ptsMm.length - 1; i++) {
        final segmentStartMm = ptsMm[i];
        final segmentEndMm = ptsMm[i + 1];
        
        final dx = segmentEndMm.x - segmentStartMm.x;
        final dy = segmentEndMm.y - segmentStartMm.y;
        final segmentLength = math.sqrt(dx * dx + dy * dy);
        
        if (accumulatedLength + segmentLength <= targetLength) {
          // 这一段完全在进度范围内，完整绘制
          final startPx = viewport.mmToPx(segmentStartMm.x, segmentStartMm.y);
          final endPx = viewport.mmToPx(segmentEndMm.x, segmentEndMm.y);
          
          if (pl.penDown) {
            canvas.drawLine(startPx, endPx, downPaint);
          } else {
            _drawDashedLine(canvas, startPx, endPx, upPaint, dashPx, gapPx);
          }
          
          accumulatedLength += segmentLength;
          penTipPosition = endPx;
          penTipDown = pl.penDown;
        } else if (accumulatedLength < targetLength) {
          // 这一段部分在进度范围内，绘制部分
          final remainingLength = targetLength - accumulatedLength;
          final ratio = remainingLength / segmentLength;
          
          final partialEndMmX = segmentStartMm.x + dx * ratio;
          final partialEndMmY = segmentStartMm.y + dy * ratio;
          
          final startPx = viewport.mmToPx(segmentStartMm.x, segmentStartMm.y);
          final endPx = viewport.mmToPx(partialEndMmX, partialEndMmY);
          
          if (pl.penDown) {
            canvas.drawLine(startPx, endPx, downPaint);
          } else {
            _drawDashedLine(canvas, startPx, endPx, upPaint, dashPx, gapPx);
          }
          
          penTipPosition = endPx;
          penTipDown = pl.penDown;
          accumulatedLength = targetLength; // 停止继续绘制
          break;
        } else {
          // 这一段完全在进度范围外，不绘制
          break;
        }
      }
      
      if (accumulatedLength >= targetLength) break;
    }

    // 绘制笔尖
    if (penTipPosition != null && progress > 0 && progress < 1) {
      _drawPenTip(canvas, penTipPosition, penTipRadiusPx, penTipDown);
    }
  }
  
  double _calculateTotalLength() {
    double total = 0.0;
    for (final pl in toolPath.polylines) {
      if (pl.points.length < 2) continue;
      if (!showPenUp && !pl.penDown) continue;
      
      for (int i = 0; i < pl.points.length - 1; i++) {
        final dx = pl.points[i + 1].x - pl.points[i].x;
        final dy = pl.points[i + 1].y - pl.points[i].y;
        total += math.sqrt(dx * dx + dy * dy);
      }
    }
    return total;
  }
  
  void _drawPenTip(Canvas canvas, Offset position, double radius, bool penDown) {
    // 笔尖外圈
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.black87;
    
    // 笔尖填充：落笔黑色，抬笔灰白色
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = penDown ? Colors.black : Colors.grey.shade300;
    
    canvas.drawCircle(position, radius, fillPaint);
    canvas.drawCircle(position, radius, outlinePaint);
    
    // 绘制一个小三角形表示笔尖方向（可选）
    if (penDown) {
      final indicatorPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white;
      canvas.drawCircle(position, radius * 0.3, indicatorPaint);
    }
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
  bool shouldRepaint(covariant AnimatedToolPathPainter oldDelegate) {
    return oldDelegate.toolPath != toolPath ||
        oldDelegate.progress != progress ||
        oldDelegate.showPenUp != showPenUp ||
        oldDelegate.viewport.scale != viewport.scale ||
        oldDelegate.viewport.pan != viewport.pan;
  }
}
