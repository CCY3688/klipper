import 'geometry.dart';

/// 笔画类型枚举
/// 
/// 目前是简化版，覆盖汉字最基本的笔画类型。
/// 设为可选是因为：旧字库数据没有类型信息，仍然需要能正常使用。
enum StrokeType {
  horizontal,   // 横 ━
  vertical,     // 竖 ┃
  leftFalling,  // 撇 ╲
  rightFalling, // 捺 ╱
  dot,          // 点 、
  turning,      // 折（横折、竖折等）
  hook,         // 钩
  other,        // 其他/复合笔画
}

/// 核心职责：表示一个独立的笔画
/// 包含信息点：
/// - ponits 坐标点
/// - type (可选)笔画类型
/// - 计算属性（起点、终点、边界框等）
/// 
/// 一个笔画 = 一次落笔到抬笔之间的连续轨迹。
/// 例如"十"字有2个笔画（横、竖），"田"字有3个笔画（框、中竖、中横）。
class Stroke {
  /// 笔画的坐标点序列（归一化坐标 0~1）
  final List<Vec2> points;
  
  /// 笔画类型（可选）
  /// 为 null 时表示未分类，不影响基本功能
  final StrokeType? type;

  const Stroke({
    required this.points,
    this.type,
  });

  /// 从纯坐标列表创建（兼容旧数据格式）
  factory Stroke.fromPoints(List<Vec2> points) {
    return Stroke(points: points);
  }

  // ===== 便捷访问器 =====

  /// 笔画起点
  Vec2 get startPoint => points.first;

  /// 笔画终点
  Vec2 get endPoint => points.last;

  /// 点的数量
  int get pointCount => points.length;

  /// 是否是有效笔画（至少2个点才能形成轨迹）
  bool get isValid => points.length >= 2;

  /// 笔画的边界框 (minX, minY, maxX, maxY)
  /// 用于快速判断笔画的大致位置和大小
  ({double minX, double minY, double maxX, double maxY}) get boundingBox {
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }

    return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  /// 笔画的大致方向角度（起点到终点的角度，弧度）
  /// 用于后续判断笔画类型
  double get directionAngle {
    final dx = endPoint.x - startPoint.x;
    final dy = endPoint.y - startPoint.y;
    return _atan2(dy, dx);
  }

  /// 笔画的直线距离（起点到终点）
  double get directDistance {
    final dx = endPoint.x - startPoint.x;
    final dy = endPoint.y - startPoint.y;
    return _sqrt(dx * dx + dy * dy);
  }

  /// 笔画的实际路径长度（沿着所有点的折线长度）
  double get pathLength {
    double length = 0;
    for (int i = 1; i < points.length; i++) {
      final dx = points[i].x - points[i - 1].x;
      final dy = points[i].y - points[i - 1].y;
      length += _sqrt(dx * dx + dy * dy);
    }
    return length;
  }

  // 简单的数学函数（避免导入 dart:math 的复杂性）
  static double _sqrt(double x) => x <= 0 ? 0 : _newtonSqrt(x);
  static double _newtonSqrt(double x) {
    double guess = x / 2;
    for (int i = 0; i < 10; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }
  
  static double _atan2(double y, double x) {
    // 简化版，实际项目中用 dart:math
    if (x == 0) return y >= 0 ? 1.5708 : -1.5708;
    final angle = _atan(y / x);
    if (x < 0) return y >= 0 ? angle + 3.1416 : angle - 3.1416;
    return angle;
  }
  
  static double _atan(double x) {
    // 泰勒级数近似
    if (x.abs() > 1) {
      return (x > 0 ? 1.5708 : -1.5708) - _atan(1 / x);
    }
    double result = x;
    double term = x;
    for (int i = 1; i < 10; i++) {
      term *= -x * x * (2 * i - 1) / (2 * i + 1);
      result += term / (2 * i + 1);
    }
    return result;
  }
}