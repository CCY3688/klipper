/// 动态时间规整（DTW）算法
///
/// 用于计算两条笔画折线之间的形状相似度，
/// 不受长度差异或速度不均匀影响。
library;

import 'dart:math' as math;

class Dtw {
  /// 计算两条折线的 DTW 距离
  ///
  /// [a], [b] 归一化坐标点列表
  /// 返回 DTW 距离（越小越相似）
  static double distance(
    List<({double x, double y})> a,
    List<({double x, double y})> b,
  ) {
    if (a.isEmpty || b.isEmpty) return double.infinity;

    final n = a.length;
    final m = b.length;

    // 使用滚动数组节省内存：O(m) 空间
    var prev = List<double>.filled(m, double.infinity);
    var curr = List<double>.filled(m, double.infinity);

    prev[0] = _dist(a[0], b[0]);
    for (int j = 1; j < m; j++) {
      prev[j] = prev[j - 1] + _dist(a[0], b[j]);
    }

    for (int i = 1; i < n; i++) {
      curr[0] = prev[0] + _dist(a[i], b[0]);
      for (int j = 1; j < m; j++) {
        final cost = _dist(a[i], b[j]);
        curr[j] = cost + _min3(prev[j - 1], prev[j], curr[j - 1]);
      }
      // swap
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }

    return prev[m - 1] / (n + m); // 归一化到路径长度
  }

  /// 考虑方向翻转的 DTW 距离（取正向与反向中的较小值）
  static double distanceWithReverse(
    List<({double x, double y})> a,
    List<({double x, double y})> b,
  ) {
    final d1 = distance(a, b);
    final bRev = b.reversed.toList();
    final d2 = distance(a, bRev);
    return math.min(d1, d2);
  }

  static double _dist(({double x, double y}) p, ({double x, double y}) q) {
    final dx = p.x - q.x;
    final dy = p.y - q.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _min3(double a, double b, double c) {
    if (a <= b && a <= c) return a;
    if (b <= c) return b;
    return c;
  }
}
