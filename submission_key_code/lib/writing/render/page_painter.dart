//（画纸张边界 + 作文格）
import 'package:flutter/material.dart';
import '../model/page.dart';
import '../model/essay_grid.dart';
import '../render/viewport.dart'as kp;

class PagePainter extends CustomPainter {
  final PageMm page;
  final EssayGridSpec grid;
  final kp.Viewport viewport;

  PagePainter({required this.page, required this.grid, required this.viewport});

  @override
  void paint(Canvas canvas, Size size) {
    // 背景
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF7F7F7));

    // 纸张矩形（以 mm 世界坐标定义：左上角 (0,0)）
    final pageRectMm = Rect.fromLTWH(0, 0, page.widthMm, page.heightMm);
    final pageRectPx = viewport.mmRectToPx(pageRectMm);

    // 纸张边界
    canvas.drawRect(
      pageRectPx,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black54,
    );

    // 作文格网格线
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black26;

    final left = grid.marginLeftMm;
    final top = grid.marginTopMm;

    // 竖线
    for (int c = 0; c <= grid.cols; c++) {
      final x = left + c * grid.cellMm;
      final p1 = viewport.mmToPx(x, top);
      final p2 = viewport.mmToPx(x, top + grid.gridHeightMm);
      canvas.drawLine(p1, p2, gridPaint);
    }

    // 横线
    for (int r = 0; r <= grid.rows; r++) {
      final y = top + r * grid.cellMm;
      final p1 = viewport.mmToPx(left, y);
      final p2 = viewport.mmToPx(left + grid.gridWidthMm, y);
      canvas.drawLine(p1, p2, gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PagePainter oldDelegate) {
    return oldDelegate.viewport.scale != viewport.scale ||
        oldDelegate.viewport.pan != viewport.pan ||
        oldDelegate.page != page ||
        oldDelegate.grid != grid;
  }
}