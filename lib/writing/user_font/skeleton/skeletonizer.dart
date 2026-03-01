/// Zhang-Suen 细化算法（骨架化）
///
/// 将二值填充位图细化为单像素宽骨架，用于后续提取笔画中心线。
/// 参考：Zhang, T.Y. and Suen, C.Y. (1984).
/// "A Fast Parallel Algorithm for Thinning Digital Patterns."
library;

import 'dart:typed_data';
import 'dart:math' as math;
import 'outline_rasterizer.dart';

class Skeletonizer {
  /// 对填充位图执行 Zhang-Suen 细化，原地修改 pixels
  ///
  /// 返回细化后的新 GlyphBitmap（不修改原始数据）
  static GlyphBitmap skeletonize(GlyphBitmap input) {
    final w = input.width;
    final h = input.height;
    // 工作副本
    final pixels = Uint8List.fromList(input.pixels);
    final marker = Uint8List(w * h); // 标记待删除像素

    bool changed = true;
    while (changed) {
      changed = false;
      marker.fillRange(0, marker.length, 0);

      // ── 第一子迭代 ──────────────────────────────────────────────────
      for (int y = 1; y < h - 1; y++) {
        for (int x = 1; x < w - 1; x++) {
          if (pixels[y * w + x] == 0) continue;

          final p = _getNeighbors(pixels, x, y, w);
          final b = _neighborCount(p); // 非零邻域数
          final a = _transitionCount(p); // 0→1 过渡次数

          if (b >= 2 && b <= 6 &&
              a == 1 &&
              (p[0] == 0 || p[2] == 0 || p[4] == 0) && // P2*P4*P6=0
              (p[2] == 0 || p[4] == 0 || p[6] == 0)) { // P4*P6*P8=0
            marker[y * w + x] = 1;
          }
        }
      }

      for (int i = 0; i < pixels.length; i++) {
        if (marker[i] != 0) {
          pixels[i] = 0;
          changed = true;
        }
      }
      marker.fillRange(0, marker.length, 0);

      // ── 第二子迭代 ──────────────────────────────────────────────────
      for (int y = 1; y < h - 1; y++) {
        for (int x = 1; x < w - 1; x++) {
          if (pixels[y * w + x] == 0) continue;

          final p = _getNeighbors(pixels, x, y, w);
          final b = _neighborCount(p);
          final a = _transitionCount(p);

          if (b >= 2 && b <= 6 &&
              a == 1 &&
              (p[0] == 0 || p[2] == 0 || p[6] == 0) && // P2*P4*P8=0
              (p[0] == 0 || p[4] == 0 || p[6] == 0)) { // P2*P6*P8=0
            marker[y * w + x] = 1;
          }
        }
      }

      for (int i = 0; i < pixels.length; i++) {
        if (marker[i] != 0) {
          pixels[i] = 0;
          changed = true;
        }
      }
    }

    // 细化后桥接微小断点（常见于斜线/小圆点边缘的像素裂缝）
    // 手写字体笔画较粗时，细化可能产生 4~6 像素的断裂
    _bridgeSmallEndpointGaps(pixels, w, h, maxGap: 6);

    return GlyphBitmap(pixels: pixels, width: w, height: h);
  }

  /// 连接靠近且方向连续的端点，修复细化造成的微小断裂。
  static void _bridgeSmallEndpointGaps(
    Uint8List pixels,
    int w,
    int h, {
    int maxGap = 3,
  }) {
    int idx(int x, int y) => y * w + x;

    final endpoints = <int>[];

    int neighborCount(int x, int y) {
      int cnt = 0;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
          if (pixels[idx(nx, ny)] != 0) cnt++;
        }
      }
      return cnt;
    }

    ({int x, int y})? singleNeighbor(int x, int y) {
      ({int x, int y})? found;
      int cnt = 0;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
          if (pixels[idx(nx, ny)] != 0) {
            cnt++;
            found = (x: nx, y: ny);
            if (cnt > 1) return null;
          }
        }
      }
      return cnt == 1 ? found : null;
    }

    ({double x, double y}) unitVec(double x, double y) {
      final len = math.sqrt(x * x + y * y);
      if (len < 1e-9) return (x: 0, y: 0);
      return (x: x / len, y: y / len);
    }

    // 收集端点（1 邻域）
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        if (pixels[idx(x, y)] == 0) continue;
        if (neighborCount(x, y) == 1) {
          endpoints.add(idx(x, y));
        }
      }
    }

    if (endpoints.length < 2) return;

    final used = <int>{};

    void drawLine(int x0, int y0, int x1, int y1) {
      int x = x0;
      int y = y0;
      final dx = (x1 - x0).abs();
      final sx = x0 < x1 ? 1 : -1;
      final dy = -(y1 - y0).abs();
      final sy = y0 < y1 ? 1 : -1;
      int err = dx + dy;

      while (true) {
        if (x >= 0 && x < w && y >= 0 && y < h) {
          pixels[idx(x, y)] = 1;
        }
        if (x == x1 && y == y1) break;
        final e2 = 2 * err;
        if (e2 >= dy) {
          err += dy;
          x += sx;
        }
        if (e2 <= dx) {
          err += dx;
          y += sy;
        }
      }
    }

    // 贪心配对：优先连接最近且方向最连续的端点
    for (final aKey in endpoints) {
      if (used.contains(aKey)) continue;
      final ax = aKey % w;
      final ay = aKey ~/ w;
      final aN = singleNeighbor(ax, ay);
      if (aN == null) continue;

      final aTan = unitVec((ax - aN.x).toDouble(), (ay - aN.y).toDouble());

      double bestScore = double.infinity;
      int bestB = -1;

      for (final bKey in endpoints) {
        if (bKey == aKey || used.contains(bKey)) continue;

        final bx = bKey % w;
        final by = bKey ~/ w;
        final dx = bx - ax;
        final dy = by - ay;
        final dist2 = dx * dx + dy * dy;
        if (dist2 == 0 || dist2 > maxGap * maxGap) continue;

        final bN = singleNeighbor(bx, by);
        if (bN == null) continue;

        final conn = unitVec(dx.toDouble(), dy.toDouble());
        final bTan = unitVec((bx - bN.x).toDouble(), (by - bN.y).toDouble());

        // 端点朝向需与连接方向基本一致，避免误连近邻独立笔画
        final aDot = aTan.x * conn.x + aTan.y * conn.y;
        final bDot = bTan.x * (-conn.x) + bTan.y * (-conn.y);
        if (aDot < 0.45 || bDot < 0.45) continue;

        // 以距离为主，方向连续性为辅
        final score = dist2.toDouble() + (2 - aDot - bDot) * 2.0;
        if (score < bestScore) {
          bestScore = score;
          bestB = bKey;
        }
      }

      if (bestB != -1) {
        final bx = bestB % w;
        final by = bestB ~/ w;
        drawLine(ax, ay, bx, by);
        used.add(aKey);
        used.add(bestB);
      }
    }
  }

  /// 获取 8 邻域像素（顺时针，从正上方 P2 开始）
  /// 返回 [P2, P3, P4, P5, P6, P7, P8, P9]（论文符号，索引 0-7 对应 P2-P9）
  static List<int> _getNeighbors(Uint8List pixels, int x, int y, int w) {
    return [
      pixels[(y - 1) * w + x],     // P2 (上)
      pixels[(y - 1) * w + x + 1], // P3 (右上)
      pixels[y * w + x + 1],       // P4 (右)
      pixels[(y + 1) * w + x + 1], // P5 (右下)
      pixels[(y + 1) * w + x],     // P6 (下)
      pixels[(y + 1) * w + x - 1], // P7 (左下)
      pixels[y * w + x - 1],       // P8 (左)
      pixels[(y - 1) * w + x - 1], // P9 (左上)
    ];
  }

  /// 8 邻域中非零像素数（邻域像素总数）
  static int _neighborCount(List<int> p) => p.fold(0, (sum, v) => sum + v);

  /// 邻域像素序列中 0→1 的跳变次数（连通性指标）
  static int _transitionCount(List<int> p) {
    int count = 0;
    for (int i = 0; i < 8; i++) {
      if (p[i] == 0 && p[(i + 1) % 8] == 1) count++;
    }
    return count;
  }
}
