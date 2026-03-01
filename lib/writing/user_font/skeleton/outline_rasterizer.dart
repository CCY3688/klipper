/// 字形轮廓光栅化器
///
/// 将 TTF 轮廓（采样后的点序列）光栅化为二值位图（Uint8List）。
/// 使用扫描线填充算法 + 奇偶规则（Even-Odd rule）。
/// 奇偶规则对汉字"内孔"（如"日"的内框）处理正确。
library;

import 'dart:typed_data';
import 'dart:math' as math;
import '../ttf/ttf_glyph_outline.dart';
import '../ttf/bezier_sampler.dart';

/// 扫描线填充后的二值位图
/// - 1 = 前景（笔迹区域）
/// - 0 = 背景
class GlyphBitmap {
  final Uint8List pixels; // row-major, pixels[y*width + x]
  final int width;
  final int height;

  const GlyphBitmap({
    required this.pixels,
    required this.width,
    required this.height,
  });

  bool isSet(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return false;
    return pixels[y * width + x] != 0;
  }

  void set(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return;
    pixels[y * width + x] = 1;
  }

  void clear(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return;
    pixels[y * width + x] = 0;
  }
}

class OutlineRasterizer {
  /// 将字形轮廓光栅化为二值位图
  ///
  /// [outline] TTF 字形轮廓
  /// [resolution] 输出位图尺寸（正方形），建议 256
  /// [padding] 四边留白像素数
  static GlyphBitmap rasterize(
    TtfGlyphOutline outline, {
    int resolution = 256,
    int padding = 8,
  }) {
    final pixels = Uint8List(resolution * resolution);
    final bitmap = GlyphBitmap(pixels: pixels, width: resolution, height: resolution);

    if (outline.isEmpty) return bitmap;

    final drawSize = resolution - padding * 2;
    if (drawSize <= 0) return bitmap;

    // 字形坐标范围（字体单位）
    final xMin = outline.xMin.toDouble();
    final yMin = outline.yMin.toDouble();
    final xRange = (outline.xMax - outline.xMin).toDouble();
    final yRange = (outline.yMax - outline.yMin).toDouble();

    if (xRange <= 0 || yRange <= 0) return bitmap;

    // 保持宽高比，取较大轴填满 drawSize
    final scale = drawSize / math.max(xRange, yRange).toDouble();
    final xOffset = padding + (drawSize - xRange * scale) / 2;
    final yOffset = padding + (drawSize - yRange * scale) / 2;

    // 采样所有轮廓
    final sampledContours = outline.contours.map((c) {
      final sc = BezierSampler.sample(c, maxSegmentLen: 1.0 / scale);
      // 转换到位图坐标（Y轴翻转：字体Y向上，位图Y向下）
      return sc.points.map((p) => (
        x: (p.x - xMin) * scale + xOffset,
        y: (resolution - 1) - ((p.y - yMin) * scale + yOffset),
      )).toList();
    }).where((c) => c.length >= 2).toList();

    // 扫描线填充（奇偶规则）
    _scanlineFill(bitmap, sampledContours);

    return bitmap;
  }

  static void _scanlineFill(
    GlyphBitmap bitmap,
    List<List<({double x, double y})>> contours,
  ) {
    final h = bitmap.height;
    final w = bitmap.width;

    for (int scanY = 0; scanY < h; scanY++) {
      final intersections = <double>[];

      for (final contour in contours) {
        final n = contour.length;
        for (int i = 0; i < n; i++) {
          final p0 = contour[i];
          final p1 = contour[(i + 1) % n];

          final y0 = p0.y;
          final y1 = p1.y;
          final sy = scanY + 0.5; // 扫描线在像素中心

          // 检查扫描线是否穿过这条边
          if ((y0 <= sy && y1 > sy) || (y1 <= sy && y0 > sy)) {
            // 计算交点 x
            final t = (sy - y0) / (y1 - y0);
            intersections.add(p0.x + t * (p1.x - p0.x));
          }
        }
      }

      if (intersections.isEmpty) continue;
      intersections.sort();

      // 奇偶填充：成对填充区间
      for (int i = 0; i + 1 < intersections.length; i += 2) {
        final x0 = intersections[i].ceil();
        final x1 = intersections[i + 1].floor();
        for (int x = x0; x <= x1 && x < w; x++) {
          if (x >= 0) bitmap.set(x, scanY);
        }
      }
    }
  }
}
