import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

import '../../writing/font/stroke_font.dart';
import '../models/sample_template.dart';

/// 模板图像生成器
///
/// 根据 [SampleTemplate] 生成一张供用户打印的模板图像。
  /// 模板包含：
///   - 网格线
///   - （可选）每个格子内浅灰色的参考字形（用字库中的 medians 绘制）
///   - 格子编号
///   - 页眉标题和说明
class TemplateGenerator {
  final StrokeFont font;

  /// 图像 DPI（300 适合打印）
  final int dpi;

  TemplateGenerator(this.font, {this.dpi = 300});

  /// 毫米转像素
  int _mmToPx(double mm) => (mm / 25.4 * dpi).round();

  /// 生成模板图像（PNG）
  Future<Uint8List> generate(
    SampleTemplate template, {
    bool includeReferenceGlyphs = true,
  }) async {
    final pageW = _mmToPx(template.pageWidthMm);
    final pageH = _mmToPx(template.pageHeightMm);
    final cellSize = _mmToPx(template.cellSizeMm);
    final marginLeft = _mmToPx(template.marginLeftMm);
    final marginTop = _mmToPx(template.marginTopMm);

    final image = img.Image(width: pageW, height: pageH);

    // 白色背景
    for (int y = 0; y < pageH; y++) {
      for (int x = 0; x < pageW; x++) {
        image.setPixel(x, y, img.ColorRgb8(255, 255, 255));
      }
    }

    // 绘制标题区域
    _drawHeaderArea(image, template, marginLeft, marginTop, cellSize);

    // 绘制网格
    final gridStartY = marginTop;
    for (int row = 0; row <= template.rows; row++) {
      for (int col = 0; col <= template.columns; col++) {
        // 绘制水平线
        if (col == 0) {
          _drawLine(
            image,
            marginLeft,
            gridStartY + row * cellSize,
            marginLeft + template.columns * cellSize,
            gridStartY + row * cellSize,
            img.ColorRgb8(180, 180, 180),
            lineWidth: (row == 0 || row == template.rows) ? 3 : 1,
          );
        }
        // 绘制垂直线
        if (row == 0) {
          _drawLine(
            image,
            marginLeft + col * cellSize,
            gridStartY,
            marginLeft + col * cellSize,
            gridStartY + template.rows * cellSize,
            img.ColorRgb8(180, 180, 180),
            lineWidth:
                (col == 0 || col == template.columns) ? 3 : 1,
          );
        }
      }
    }

    // 绘制米字格辅助线（浅色虚线）
    for (int row = 0; row < template.rows; row++) {
      for (int col = 0; col < template.columns; col++) {
        final cx = marginLeft + col * cellSize + cellSize ~/ 2;
        final cy = gridStartY + row * cellSize + cellSize ~/ 2;
        final half = cellSize ~/ 2;

        final guideColor = img.ColorRgb8(230, 210, 210);

        // 十字线
        _drawDashedLine(image, cx - half, cy, cx + half, cy, guideColor, 6);
        _drawDashedLine(image, cx, cy - half, cx, cy + half, guideColor, 6);
        // 对角线
        _drawDashedLine(
            image, cx - half, cy - half, cx + half, cy + half, guideColor, 8);
        _drawDashedLine(
            image, cx + half, cy - half, cx - half, cy + half, guideColor, 8);
      }
    }

    // 绘制参考字形（可选）
    if (includeReferenceGlyphs) {
      for (int i = 0; i < template.characters.length; i++) {
        final row = i ~/ template.columns;
        final col = i % template.columns;
        final ch = template.characters[i];

        final cellX = marginLeft + col * cellSize;
        final cellY = gridStartY + row * cellSize;

        _drawReferenceGlyph(image, ch, cellX, cellY, cellSize);
      }
    }

    return Uint8List.fromList(img.encodePng(image));
  }

  /// 绘制页眉区域信息
  void _drawHeaderArea(img.Image image, SampleTemplate template,
      int marginLeft, int marginTop, int cellSize) {
    // 简单地在顶部边距区域画一些标记点作为定位参考
    // 四个角标记（用于拍照后的透视矫正）
    final gridRight = marginLeft + template.columns * cellSize;
    final gridBottom = marginTop + template.rows * cellSize;

    const markSize = 15;
    final markColor = img.ColorRgb8(0, 0, 0);

    // 左上角标记
    _drawCornerMark(image, marginLeft, marginTop, markSize, markColor, true, true);
    // 右上角标记
    _drawCornerMark(image, gridRight, marginTop, markSize, markColor, false, true);
    // 左下角标记
    _drawCornerMark(image, marginLeft, gridBottom, markSize, markColor, true, false);
    // 右下角标记
    _drawCornerMark(image, gridRight, gridBottom, markSize, markColor, false, false);
  }

  /// 绘制角标记（用于辅助定位）
  void _drawCornerMark(img.Image image, int x, int y, int size,
      img.Color color, bool isLeft, bool isTop) {
    final dx = isLeft ? 1 : -1;
    final dy = isTop ? 1 : -1;

    // L 形标记
    for (int i = 0; i < size; i++) {
      _setPixelSafe(image, x + i * dx, y, color);
      _setPixelSafe(image, x + i * dx, y + dy, color);
      _setPixelSafe(image, x, y + i * dy, color);
      _setPixelSafe(image, x + dx, y + i * dy, color);
    }
  }

  /// 绘制参考字形（浅灰色的笔画中线）
  void _drawReferenceGlyph(
      img.Image image, String ch, int cellX, int cellY, int cellSize) {
    final glyph = font.richGlyphOf(ch);
    if (glyph == null) return;

    // 字形坐标(0..1) → 像素坐标
    // 留 15% 边距
    final padding = (cellSize * 0.15).round();
    final glyphSize = cellSize - padding * 2;
    final offsetX = cellX + padding;
    final offsetY = cellY + padding;

    final color = img.ColorRgb8(210, 210, 210); // 浅灰色

    for (final stroke in glyph.strokes) {
      for (int i = 1; i < stroke.points.length; i++) {
        final p0 = stroke.points[i - 1];
        final p1 = stroke.points[i];

        final x0 = offsetX + (p0.x * glyphSize).round();
        final y0 = offsetY + (p0.y * glyphSize).round();
        final x1 = offsetX + (p1.x * glyphSize).round();
        final y1 = offsetY + (p1.y * glyphSize).round();

        _drawLine(image, x0, y0, x1, y1, color, lineWidth: 2);
      }
    }
  }

  /// Bresenham 直线绘制（带线宽）
  void _drawLine(img.Image image, int x0, int y0, int x1, int y1,
      img.Color color,
      {int lineWidth = 1}) {
    final dx = (x1 - x0).abs();
    final dy = (y1 - y0).abs();
    final sx = x0 < x1 ? 1 : -1;
    final sy = y0 < y1 ? 1 : -1;
    var err = dx - dy;

    var cx = x0, cy = y0;
    while (true) {
      // 绘制带宽度的点
      final half = lineWidth ~/ 2;
      for (int oy = -half; oy <= half; oy++) {
        for (int ox = -half; ox <= half; ox++) {
          _setPixelSafe(image, cx + ox, cy + oy, color);
        }
      }

      if (cx == x1 && cy == y1) break;
      final e2 = 2 * err;
      if (e2 > -dy) {
        err -= dy;
        cx += sx;
      }
      if (e2 < dx) {
        err += dx;
        cy += sy;
      }
    }
  }

  /// 绘制虚线
  void _drawDashedLine(img.Image image, int x0, int y0, int x1, int y1,
      img.Color color, int dashLen) {
    final dx = (x1 - x0).abs();
    final dy = (y1 - y0).abs();
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) return;

    final dirX = (x1 - x0) / length;
    final dirY = (y1 - y0) / length;

    bool draw = true;
    double pos = 0;
    while (pos < length) {
      final segEnd = math.min(pos + dashLen, length);
      if (draw) {
        _drawLine(
          image,
          (x0 + pos * dirX).round(),
          (y0 + pos * dirY).round(),
          (x0 + segEnd * dirX).round(),
          (y0 + segEnd * dirY).round(),
          color,
        );
      }
      pos = segEnd;
      draw = !draw;
    }
  }

  /// 安全设置像素（边界检查）
  void _setPixelSafe(img.Image image, int x, int y, img.Color color) {
    if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
      image.setPixel(x, y, color);
    }
  }
}
