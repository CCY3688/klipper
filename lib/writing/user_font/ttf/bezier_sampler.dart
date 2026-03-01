/// 二次贝塞尔曲线采样器
///
/// TTF 轮廓使用二次贝塞尔曲线（Quadratic Bezier）描述字形外框，
/// 本模块负责将曲线离散化为均匀间隔的点序列，供后续光栅化使用。
library;

import 'dart:math' as math;
import 'ttf_glyph_outline.dart';

/// 采样后的轮廓（已展开为点序列，首尾相连）
class SampledContour {
  final List<({double x, double y})> points;
  const SampledContour(this.points);
  bool get isEmpty => points.isEmpty;
}

class BezierSampler {
  /// 将 TTF 轮廓采样为点序列
  ///
  /// [contour] 原始 TTF 轮廓（含 on/off-curve 点）
  /// [maxSegmentLen] 每段折线的最大长度（字体单位），控制采样精度
  static SampledContour sample(TtfContour contour, {double maxSegmentLen = 4.0}) {
    if (contour.points.length < 2) return const SampledContour([]);

    final pts = contour.points;
    final n = pts.length;
    final result = <({double x, double y})>[];

    /// TTF 隐式中点规则：
    /// 两个相邻的 off-curve 点之间，存在一个隐式的 on-curve 中点。
    /// 我们首先展开 pts 为完整的 [on, off, on, off, on ...] 序列。
    final expanded = <TtfPoint>[];
    for (int i = 0; i < n; i++) {
      final cur = pts[i];
      final next = pts[(i + 1) % n];
      expanded.add(cur);
      // 如果当前和下一个都是 off-curve，插入隐式中点
      if (!cur.onCurve && !next.onCurve) {
        expanded.add(TtfPoint(
          (cur.x + next.x) / 2,
          (cur.y + next.y) / 2,
          onCurve: true,
        ));
      }
    }

    final m = expanded.length;
    int i = 0;

    // 找到起始 on-curve 点
    int start = 0;
    for (int k = 0; k < m; k++) {
      if (expanded[k].onCurve) {
        start = k;
        break;
      }
    }

    // 计算展开序列中 on-curve 点的数量，即封闭轮廓中的线段数量。
    // 注意：不能用 `while (i % m != start)` 作为终止条件——当 m 为奇数
    // 且所有段均为二次贝塞尔（步长 +2）时，i 会遍历所有余数后才回到
    // start，导致某些段被重复采样、产生自交多边形，进而破坏扫描线填充。
    final onCurveCount = expanded.where((p) => p.onCurve).length;
    i = start;
    for (int seg = 0; seg < onCurveCount; seg++) {
      final p0 = expanded[i % m];
      final p1 = expanded[(i + 1) % m];

      if (p1.onCurve) {
        // 直线段
        _sampleLine(result, p0.x, p0.y, p1.x, p1.y, maxSegmentLen);
        i++;
      } else {
        // 二次贝塞尔曲线：p0(on) → p1(off) → p2(on)
        final p2 = expanded[(i + 2) % m];
        _sampleQuadratic(result, p0.x, p0.y, p1.x, p1.y, p2.x, p2.y, maxSegmentLen);
        i += 2;
      }
    }

    return SampledContour(result);
  }

  /// 直线段均匀采样
  static void _sampleLine(
    List<({double x, double y})> out,
    double x0, double y0, double x1, double y1,
    double maxLen,
  ) {
    final dist = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
    final steps = math.max(1, (dist / maxLen).ceil());
    for (int k = 0; k < steps; k++) {
      final t = k / steps;
      out.add((x: x0 + t * (x1 - x0), y: y0 + t * (y1 - y0)));
    }
  }

  /// 二次贝塞尔曲线自适应采样
  static void _sampleQuadratic(
    List<({double x, double y})> out,
    double x0, double y0, // p0 on-curve
    double cx, double cy, // control point (off-curve)
    double x1, double y1, // p1 on-curve
    double maxLen,
  ) {
    // 用弦长估计步数
    final chordLen = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
    final ctrlLen1 = math.sqrt((cx - x0) * (cx - x0) + (cy - y0) * (cy - y0));
    final ctrlLen2 = math.sqrt((x1 - cx) * (x1 - cx) + (y1 - cy) * (y1 - cy));
    final approxLen = (ctrlLen1 + ctrlLen2 + chordLen) / 2;
    final steps = math.max(2, (approxLen / maxLen).ceil());

    for (int k = 0; k < steps; k++) {
      final t = k / steps;
      final mt = 1 - t;
      final bx = mt * mt * x0 + 2 * mt * t * cx + t * t * x1;
      final by = mt * mt * y0 + 2 * mt * t * cy + t * t * y1;
      out.add((x: bx, y: by));
    }
  }
}
