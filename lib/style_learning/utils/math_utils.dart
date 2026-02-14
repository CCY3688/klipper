import 'dart:math' as math;

/// 数学工具类
class MathUtils {
  /// 计算两点之间的距离
  static double distance(double x1, double y1, double x2, double y2) {
    return math.sqrt(math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2));
  }

  /// 计算两点之间的角度（弧度）
  static double angle(double x1, double y1, double x2, double y2) {
    return math.atan2(y2 - y1, x2 - x1);
  }

  /// 弧度转角度
  static double radToDeg(double rad) {
    return rad * 180 / math.pi;
  }

  /// 角度转弧度
  static double degToRad(double deg) {
    return deg * math.pi / 180;
  }

  /// 计算向量叉积
  static double crossProduct(
    double x1, double y1,
    double x2, double y2,
  ) {
    return x1 * y2 - y1 * x2;
  }

  /// 计算向量点积
  static double dotProduct(
    double x1, double y1,
    double x2, double y2,
  ) {
    return x1 * x2 + y1 * y2;
  }

  /// 计算三点形成的角度（弧度）
  static double angleAtPoint(
    double x1, double y1,  // 前一点
    double x2, double y2,  // 中心点
    double x3, double y3,  // 后一点
  ) {
    final v1x = x1 - x2;
    final v1y = y1 - y2;
    final v2x = x3 - x2;
    final v2y = y3 - y2;

    final dot = dotProduct(v1x, v1y, v2x, v2y);
    final mag1 = math.sqrt(v1x * v1x + v1y * v1y);
    final mag2 = math.sqrt(v2x * v2x + v2y * v2y);

    if (mag1 == 0 || mag2 == 0) return math.pi;

    final cosAngle = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
    return math.acos(cosAngle);
  }

  /// 计算点到线段的垂直距离
  static double pointToLineDistance(
    double px, double py,
    double x1, double y1,
    double x2, double y2,
  ) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final lengthSq = dx * dx + dy * dy;

    if (lengthSq == 0) {
      return distance(px, py, x1, y1);
    }

    final t = ((px - x1) * dx + (py - y1) * dy) / lengthSq;
    final clampedT = t.clamp(0.0, 1.0);

    final projX = x1 + clampedT * dx;
    final projY = y1 + clampedT * dy;

    return distance(px, py, projX, projY);
  }

  /// 计算曲率（使用三点）
  /// 返回曲率半径的倒数，正值表示左转，负值表示右转
  static double curvature(
    double x1, double y1,
    double x2, double y2,
    double x3, double y3,
  ) {
    final ax = x2 - x1;
    final ay = y2 - y1;
    final bx = x3 - x2;
    final by = y3 - y2;

    final cross = crossProduct(ax, ay, bx, by);
    final aMag = math.sqrt(ax * ax + ay * ay);
    final bMag = math.sqrt(bx * bx + by * by);

    if (aMag == 0 || bMag == 0) return 0;

    // 曲率 = 2 * sin(theta) / |chord|
    final chordLength = distance(x1, y1, x3, y3);
    if (chordLength == 0) return 0;

    return 2 * cross / (aMag * bMag * chordLength);
  }

  /// 计算列表的均值
  static double mean(List<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// 计算列表的标准差
  static double standardDeviation(List<double> values) {
    if (values.length < 2) return 0;
    final avg = mean(values);
    final squaredDiffs = values.map((v) => math.pow(v - avg, 2));
    return math.sqrt(squaredDiffs.reduce((a, b) => a + b) / values.length);
  }

  /// 计算列表的中位数
  static double median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[mid];
    }
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  /// 计算百分位数
  static double percentile(List<double> values, double p) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.from(values)..sort();
    final index = (p / 100 * (sorted.length - 1)).round();
    return sorted[index.clamp(0, sorted.length - 1)];
  }

  /// 线性插值
  static double lerp(double a, double b, double t) {
    return a + (b - a) * t;
  }

  /// 平滑数据（移动平均）
  static List<double> smooth(List<double> values, int windowSize) {
    if (values.length <= windowSize) return values;

    final result = <double>[];
    final halfWindow = windowSize ~/ 2;

    for (int i = 0; i < values.length; i++) {
      double sum = 0;
      int count = 0;

      for (int j = i - halfWindow; j <= i + halfWindow; j++) {
        if (j >= 0 && j < values.length) {
          sum += values[j];
          count++;
        }
      }

      result.add(sum / count);
    }

    return result;
  }
}

/// 2D 点
class Point2D {
  final double x;
  final double y;

  const Point2D(this.x, this.y);

  Point2D operator +(Point2D other) => Point2D(x + other.x, y + other.y);
  Point2D operator -(Point2D other) => Point2D(x - other.x, y - other.y);
  Point2D operator *(double scale) => Point2D(x * scale, y * scale);

  double get magnitude => math.sqrt(x * x + y * y);

  Point2D normalized() {
    final mag = magnitude;
    if (mag == 0) return const Point2D(0, 0);
    return Point2D(x / mag, y / mag);
  }

  double distanceTo(Point2D other) {
    return MathUtils.distance(x, y, other.x, other.y);
  }

  double angleTo(Point2D other) {
    return MathUtils.angle(x, y, other.x, other.y);
  }

  /// 旋转点
  Point2D rotate(double angleRad, [Point2D? center]) {
    final c = center ?? const Point2D(0, 0);
    final cos = math.cos(angleRad);
    final sin = math.sin(angleRad);

    final dx = x - c.x;
    final dy = y - c.y;

    return Point2D(
      c.x + dx * cos - dy * sin,
      c.y + dx * sin + dy * cos,
    );
  }

  @override
  String toString() => 'Point2D($x, $y)';
}