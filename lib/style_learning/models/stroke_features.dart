import 'dart:math' as math;
import '../utils/math_utils.dart';

/// 单个笔画的特征
class StrokeFeatures {
  /// 笔画长度（像素）
  final double length;

  /// 笔画方向（起点到终点的角度，弧度）
  final double direction;

  /// 起笔角度（前几个点的方向）
  final double startAngle;

  /// 收笔角度（最后几个点的方向）
  final double endAngle;

  /// 平均曲率
  final double avgCurvature;

  /// 最大曲率
  final double maxCurvature;

  /// 曲率变化（标准差）
  final double curvatureVariation;

  /// 笔画高度
  final double height;

  /// 笔画宽度
  final double width;

  /// 高宽比
  final double aspectRatio;

  /// 起点位置（相对于字符边界框，0-1）
  final Point2D relativeStart;

  /// 终点位置（相对于字符边界框，0-1）
  final Point2D relativeEnd;

  /// 点数
  final int pointCount;

  /// 笔画类型（如果已识别）
  final String? strokeType;

  StrokeFeatures({
    required this.length,
    required this.direction,
    required this.startAngle,
    required this.endAngle,
    required this.avgCurvature,
    required this.maxCurvature,
    required this.curvatureVariation,
    required this.height,
    required this.width,
    required this.aspectRatio,
    required this.relativeStart,
    required this.relativeEnd,
    required this.pointCount,
    this.strokeType,
  });

  /// 从点列表提取特征
  factory StrokeFeatures.fromPoints(
    List<Point2D> points, {
    double charWidth = 1,
    double charHeight = 1,
    double charMinX = 0,
    double charMinY = 0,
    String? strokeType,
  }) {
    if (points.length < 2) {
      return StrokeFeatures(
        length: 0,
        direction: 0,
        startAngle: 0,
        endAngle: 0,
        avgCurvature: 0,
        maxCurvature: 0,
        curvatureVariation: 0,
        height: 0,
        width: 0,
        aspectRatio: 1,
        relativeStart: const Point2D(0.5, 0.5),
        relativeEnd: const Point2D(0.5, 0.5),
        pointCount: points.length,
        strokeType: strokeType,
      );
    }

    // 计算长度
    double totalLength = 0;
    for (int i = 1; i < points.length; i++) {
      totalLength += points[i].distanceTo(points[i - 1]);
    }

    // 计算方向
    final direction = points.first.angleTo(points.last);

    // 计算起笔角度（前3个点）
    double startAngle = 0;
    if (points.length >= 2) {
      final endIdx = math.min(3, points.length);
      startAngle = points[0].angleTo(points[endIdx - 1]);
    }

    // 计算收笔角度（后3个点）
    double endAngle = 0;
    if (points.length >= 2) {
      final startIdx = math.max(0, points.length - 3);
      endAngle = points[startIdx].angleTo(points.last);
    }

    // 计算曲率
    final curvatures = <double>[];
    for (int i = 1; i < points.length - 1; i++) {
      final c = MathUtils.curvature(
        points[i - 1].x, points[i - 1].y,
        points[i].x, points[i].y,
        points[i + 1].x, points[i + 1].y,
      );
      curvatures.add(c.abs());
    }

    final avgCurvature = curvatures.isEmpty ? 0.0 : MathUtils.mean(curvatures);
    final maxCurvature = curvatures.isEmpty ? 0.0 : curvatures.reduce(math.max);
    final curvatureVariation = curvatures.isEmpty ? 0.0 : MathUtils.standardDeviation(curvatures);

    // 计算边界框
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;

    for (final p in points) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }

    final width = maxX - minX;
    final height = maxY - minY;
    final aspectRatio = height > 0 ? width / height : 1.0;

    // 计算相对位置
    final relativeStart = Point2D(
      charWidth > 0 ? (points.first.x - charMinX) / charWidth : 0.5,
      charHeight > 0 ? (points.first.y - charMinY) / charHeight : 0.5,
    );

    final relativeEnd = Point2D(
      charWidth > 0 ? (points.last.x - charMinX) / charWidth : 0.5,
      charHeight > 0 ? (points.last.y - charMinY) / charHeight : 0.5,
    );

    return StrokeFeatures(
      length: totalLength,
      direction: direction,
      startAngle: startAngle,
      endAngle: endAngle,
      avgCurvature: avgCurvature,
      maxCurvature: maxCurvature,
      curvatureVariation: curvatureVariation,
      height: height,
      width: width,
      aspectRatio: aspectRatio,
      relativeStart: relativeStart,
      relativeEnd: relativeEnd,
      pointCount: points.length,
      strokeType: strokeType,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'length': length,
      'direction': direction,
      'startAngle': startAngle,
      'endAngle': endAngle,
      'avgCurvature': avgCurvature,
      'maxCurvature': maxCurvature,
      'curvatureVariation': curvatureVariation,
      'height': height,
      'width': width,
      'aspectRatio': aspectRatio,
      'relativeStart': [relativeStart.x, relativeStart.y],
      'relativeEnd': [relativeEnd.x, relativeEnd.y],
      'pointCount': pointCount,
      'strokeType': strokeType,
    };
  }
}

/// 字符整体特征
class CharacterFeatures {
  /// 字符宽度
  final double width;

  /// 字符高度
  final double height;

  /// 高宽比
  final double aspectRatio;

  /// 整体倾斜角度（弧度）
  final double slantAngle;

  /// 重心位置（相对坐标 0-1）
  final Point2D centerOfGravity;

  /// 笔画数量
  final int strokeCount;

  /// 笔画总长度
  final double totalStrokeLength;

  /// 笔画密度（总长度/面积）
  final double strokeDensity;

  /// 各笔画特征
  final List<StrokeFeatures> strokeFeatures;

  /// 笔画间平均间距
  final double avgStrokeSpacing;

  CharacterFeatures({
    required this.width,
    required this.height,
    required this.aspectRatio,
    required this.slantAngle,
    required this.centerOfGravity,
    required this.strokeCount,
    required this.totalStrokeLength,
    required this.strokeDensity,
    required this.strokeFeatures,
    required this.avgStrokeSpacing,
  });

  Map<String, dynamic> toJson() {
    return {
      'width': width,
      'height': height,
      'aspectRatio': aspectRatio,
      'slantAngle': slantAngle,
      'centerOfGravity': [centerOfGravity.x, centerOfGravity.y],
      'strokeCount': strokeCount,
      'totalStrokeLength': totalStrokeLength,
      'strokeDensity': strokeDensity,
      'strokeFeatures': strokeFeatures.map((s) => s.toJson()).toList(),
      'avgStrokeSpacing': avgStrokeSpacing,
    };
  }
}