import 'dart:math' as math;

import 'stroke.dart';
import 'glyph.dart';

// ============================================================================
// StrokeAnalyzer - 笔画几何分析工具
// ============================================================================
/// 
/// 【核心功能】基于几何特征自动推断笔画类型
/// 
/// 【分析依据】
///   - 方向角度：起点到终点的角度
///   - 路径弯曲度：实际路径长度 / 直线距离
///   - 笔画尺寸：相对于字形的大小比例
///   - 拐点检测：折笔、钩等复合笔画的识别
/// 
/// 【使用方式】
///   ```dart
///   final analyzer = StrokeAnalyzer();
///   final type = analyzer.inferType(stroke);
///   final enrichedGlyph = analyzer.analyzeGlyph(glyph);
///   ```
class StrokeAnalyzer {
  
  // ========== 配置参数（可调优）==========
  
  /// 角度容差（弧度），用于判断"接近水平/垂直"
  final double angleTolerance;
  
  /// 弯曲度阈值，超过此值认为是折笔或钩
  final double bendingThreshold;
  
  /// 短笔画阈值（归一化长度），小于此值可能是"点"
  final double dotThreshold;
  
  const StrokeAnalyzer({
    this.angleTolerance = 0.35,       // 约 20 度
    this.bendingThreshold = 1.3,      // 路径长度超过直线30%认为有弯折
    this.dotThreshold = 0.15,         // 长度小于 0.15 认为是点
  });
  
  // ========== 主要分析方法 ==========
  
  /// 【核心】推断单个笔画的类型
  /// 
  /// 分析流程：
  /// 1. 检查是否是"点"（长度太短）
  /// 2. 检查是否有拐点（折笔、钩）
  /// 3. 根据方向角度分类（横、竖、撇、捺）
  StrokeType inferType(Stroke stroke) {
    if (!stroke.isValid) return StrokeType.other;
    
    final directDist = stroke.directDistance;
    final pathLen = stroke.pathLength;
    final angle = stroke.directionAngle;
    
    // 1. 短笔画 → 点
    if (directDist < dotThreshold) {
      return StrokeType.dot;
    }
    
    // 2. 弯曲笔画 → 折或钩
    final bendingRatio = pathLen / directDist;
    if (bendingRatio > bendingThreshold) {
      // 进一步区分折和钩
      return _classifyBentStroke(stroke);
    }
    
    // 3. 直线型笔画 → 根据角度分类
    return _classifyByAngle(angle);
  }
  
  /// 分析整个字形，为所有笔画添加类型信息
  Glyph analyzeGlyph(Glyph glyph) {
    final analyzedStrokes = glyph.strokes.map((stroke) {
      if (stroke.type != null) {
        // 已有类型，保留原值
        return stroke;
      }
      // 推断类型
      final inferredType = inferType(stroke);
      return Stroke(points: stroke.points, type: inferredType);
    }).toList();
    
    return Glyph(
      character: glyph.character,
      strokes: analyzedStrokes,
      aspectRatio: glyph.aspectRatio,
    );
  }
  
  /// 批量分析多个字形
  Map<String, Glyph> analyzeGlyphs(Map<String, Glyph> glyphs) {
    return glyphs.map((char, glyph) => MapEntry(char, analyzeGlyph(glyph)));
  }
  
  // ========== 统计与诊断 ==========
  
  /// 获取笔画的详细几何信息（用于调试和可视化）
  StrokeGeometryInfo getGeometryInfo(Stroke stroke) {
    return StrokeGeometryInfo(
      directDistance: stroke.directDistance,
      pathLength: stroke.pathLength,
      bendingRatio: stroke.pathLength / stroke.directDistance,
      directionAngle: stroke.directionAngle,
      directionDegrees: stroke.directionAngle * 180 / math.pi,
      turningPoints: _findTurningPoints(stroke),
      inferredType: inferType(stroke),
    );
  }
  
  // ========== 私有辅助方法 ==========
  
  /// 根据角度分类直线型笔画
  StrokeType _classifyByAngle(double angle) {
    // 归一化角度到 -π ~ π
    while (angle > math.pi) {
      angle -= 2 * math.pi;
    }
    while (angle < -math.pi) {
      angle += 2 * math.pi;
    }
    
    final absAngle = angle.abs();
    
    // 接近水平（0° 或 180°）
    if (absAngle < angleTolerance || absAngle > math.pi - angleTolerance) {
      return StrokeType.horizontal;
    }
    
    // 接近垂直（90°）
    if ((absAngle - math.pi / 2).abs() < angleTolerance) {
      return StrokeType.vertical;
    }
    
    // 斜向：根据起点到终点的方向判断撇/捺
    // 撇：从右上到左下（dx < 0, dy > 0）→ 角度在 90°~180°
    // 捺：从左上到右下（dx > 0, dy > 0）→ 角度在 0°~90°
    if (angle > 0) {
      // 向下
      return angle < math.pi / 2 ? StrokeType.rightFalling : StrokeType.leftFalling;
    } else {
      // 向上（较少见，可能是某些特殊笔画）
      return StrokeType.other;
    }
  }
  
  /// 分类弯曲笔画（折 vs 钩）
  StrokeType _classifyBentStroke(Stroke stroke) {
    final turningPoints = _findTurningPoints(stroke);
    
    if (turningPoints.isEmpty) {
      // 没有明显拐点但路径弯曲，可能是弧形笔画
      return StrokeType.other;
    }
    
    // 分析拐点后的走向
    // 钩：通常在末端有一个小的回转
    // 折：方向变化较大但继续前进
    
    final lastTurn = turningPoints.last;
    final remainingLength = _lengthAfterIndex(stroke, lastTurn);
    final totalLength = stroke.pathLength;
    
    // 如果拐点在末端附近（最后 20% 路径），更可能是钩
    if (remainingLength < totalLength * 0.25) {
      return StrokeType.hook;
    }
    
    return StrokeType.turning;
  }
  
  /// 找到笔画中的拐点（方向突变的位置）
  List<int> _findTurningPoints(Stroke stroke) {
    if (stroke.pointCount < 3) return [];
    
    final turns = <int>[];
    const turnAngleThreshold = 0.5; // 约 30 度变化算拐点
    
    for (int i = 1; i < stroke.pointCount - 1; i++) {
      final prev = stroke.points[i - 1];
      final curr = stroke.points[i];
      final next = stroke.points[i + 1];
      
      final angle1 = math.atan2(curr.y - prev.y, curr.x - prev.x);
      final angle2 = math.atan2(next.y - curr.y, next.x - curr.x);
      
      var angleDiff = (angle2 - angle1).abs();
      if (angleDiff > math.pi) angleDiff = 2 * math.pi - angleDiff;
      
      if (angleDiff > turnAngleThreshold) {
        turns.add(i);
      }
    }
    
    return turns;
  }
  
  /// 计算从某个点之后的路径长度
  double _lengthAfterIndex(Stroke stroke, int index) {
    double length = 0;
    for (int i = index + 1; i < stroke.pointCount; i++) {
      final dx = stroke.points[i].x - stroke.points[i - 1].x;
      final dy = stroke.points[i].y - stroke.points[i - 1].y;
      length += math.sqrt(dx * dx + dy * dy);
    }
    return length;
  }
}

// ============================================================================
// StrokeGeometryInfo - 笔画几何信息（调试/可视化用）
// ============================================================================
/// 
/// 【功能】记录笔画的详细几何特征，用于分析和调试
class StrokeGeometryInfo {
  /// 起点到终点的直线距离
  final double directDistance;
  
  /// 沿路径的实际长度
  final double pathLength;
  
  /// 弯曲度 = pathLength / directDistance
  final double bendingRatio;
  
  /// 方向角度（弧度）
  final double directionAngle;
  
  /// 方向角度（度数，便于阅读）
  final double directionDegrees;
  
  /// 拐点索引列表
  final List<int> turningPoints;
  
  /// 推断的笔画类型
  final StrokeType inferredType;
  
  const StrokeGeometryInfo({
    required this.directDistance,
    required this.pathLength,
    required this.bendingRatio,
    required this.directionAngle,
    required this.directionDegrees,
    required this.turningPoints,
    required this.inferredType,
  });
  
  @override
  String toString() => '''
StrokeGeometryInfo {
  directDistance: ${directDistance.toStringAsFixed(4)},
  pathLength: ${pathLength.toStringAsFixed(4)},
  bendingRatio: ${bendingRatio.toStringAsFixed(2)},
  direction: ${directionDegrees.toStringAsFixed(1)}°,
  turningPoints: $turningPoints,
  inferredType: $inferredType
}''';
}
