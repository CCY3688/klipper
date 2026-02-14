import 'dart:math' as math;
import '../models/stroke_features.dart';
import '../models/style_vector.dart';
import '../utils/math_utils.dart';
import 'skeleton_extractor.dart';

/// 风格分析服务
/// 
/// 从用户手写样本中提取风格特征
class StyleAnalyzer {
  
  /// 从多个字符的骨架结果中分析风格
  Future<StyleVector> analyze(List<CharacterAnalysisInput> inputs) async {
    if (inputs.isEmpty) {
      throw ArgumentError('至少需要一个字符样本');
    }

    // 1. 提取每个字符的特征
    final characterFeatures = <CharacterFeatures>[];
    for (final input in inputs) {
      final features = _extractCharacterFeatures(input);
      characterFeatures.add(features);
    }

    // 2. 计算全局特征统计
    final globalFeatures = _computeGlobalFeatures(characterFeatures);

    // 3. 按笔画类型统计特征
    final strokeTypeFeatures = _computeStrokeTypeFeatures(characterFeatures);

    return StyleVector(
      global: globalFeatures,
      strokeTypes: strokeTypeFeatures,
      createdAt: DateTime.now(),
      sampleCount: inputs.length,
    );
  }

  /// 提取单个字符的特征
  CharacterFeatures _extractCharacterFeatures(CharacterAnalysisInput input) {
    final skeleton = input.skeleton;
    final strokes = skeleton.strokes;

    // 计算字符边界框
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    double sumX = 0, sumY = 0;
    int totalPoints = 0;

    for (final stroke in strokes) {
      for (final point in stroke.points) {
        minX = math.min(minX, point.x.toDouble());
        maxX = math.max(maxX, point.x.toDouble());
        minY = math.min(minY, point.y.toDouble());
        maxY = math.max(maxY, point.y.toDouble());
        sumX += point.x;
        sumY += point.y;
        totalPoints++;
      }
    }

    final width = maxX - minX;
    final height = maxY - minY;
    final aspectRatio = height > 0 ? width / height : 1.0;

    // 计算重心
    final centerX = totalPoints > 0 ? sumX / totalPoints : 0;
    final centerY = totalPoints > 0 ? sumY / totalPoints : 0;
    final relativeCenterX = width > 0 ? (centerX - minX) / width : 0.5;
    final relativeCenterY = height > 0 ? (centerY - minY) / height : 0.5;

    // 计算倾斜角度
    final slantAngle = _computeSlantAngle(strokes);

    // 提取每个笔画的特征
    final strokeFeatures = <StrokeFeatures>[];
    double totalLength = 0;

    for (int i = 0; i < strokes.length; i++) {
      final stroke = strokes[i];
      final points = stroke.points
          .map((p) => Point2D(p.x.toDouble(), p.y.toDouble()))
          .toList();

      final features = StrokeFeatures.fromPoints(
        points,
        charWidth: width,
        charHeight: height,
        charMinX: minX,
        charMinY: minY,
        strokeType: input.strokeTypes?[i],
      );

      strokeFeatures.add(features);
      totalLength += features.length;
    }

    // 计算笔画密度
    final area = width * height;
    final strokeDensity = area > 0 ? totalLength / area : 0.0;

    // 计算笔画间距
    final avgSpacing = _computeAvgStrokeSpacing(strokes);

    return CharacterFeatures(
      width: width,
      height: height,
      aspectRatio: aspectRatio,
      slantAngle: slantAngle,
      centerOfGravity: Point2D(relativeCenterX, relativeCenterY),
      strokeCount: strokes.length,
      totalStrokeLength: totalLength,
      strokeDensity: strokeDensity,
      strokeFeatures: strokeFeatures,
      avgStrokeSpacing: avgSpacing,
    );
  }

  /// 计算倾斜角度
  double _computeSlantAngle(List<StrokePath> strokes) {
    // 找竖直方向的笔画，计算它们的平均倾斜
    final verticalAngles = <double>[];

    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;

      final start = stroke.start;
      final end = stroke.end;

      // 检查是否大致是竖直的（方向在 60-120 度或 240-300 度）
      final angle = MathUtils.angle(
        start.x.toDouble(), start.y.toDouble(),
        end.x.toDouble(), end.y.toDouble(),
      );

      final absAngle = angle.abs();
      if (absAngle > math.pi / 3 && absAngle < 2 * math.pi / 3) {
        // 这是一个竖直笔画
        // 计算相对于垂直方向的偏移
        final deviation = angle - (angle > 0 ? math.pi / 2 : -math.pi / 2);
        verticalAngles.add(deviation);
      }
    }

    if (verticalAngles.isEmpty) return 0;
    return MathUtils.mean(verticalAngles);
  }

  /// 计算笔画间平均间距
  double _computeAvgStrokeSpacing(List<StrokePath> strokes) {
    if (strokes.length < 2) return 0;

    final distances = <double>[];

    for (int i = 0; i < strokes.length; i++) {
      for (int j = i + 1; j < strokes.length; j++) {
        // 计算两个笔画中心点之间的距离
        final center1 = _getStrokeCenter(strokes[i]);
        final center2 = _getStrokeCenter(strokes[j]);

        final dist = MathUtils.distance(
          center1.x, center1.y,
          center2.x, center2.y,
        );
        distances.add(dist);
      }
    }

    return distances.isEmpty ? 0 : MathUtils.mean(distances);
  }

  Point2D _getStrokeCenter(StrokePath stroke) {
    if (stroke.points.isEmpty) return const Point2D(0, 0);

    double sumX = 0, sumY = 0;
    for (final p in stroke.points) {
      sumX += p.x;
      sumY += p.y;
    }

    return Point2D(
      sumX / stroke.points.length,
      sumY / stroke.points.length,
    );
  }

  /// 计算全局风格特征
  GlobalStyleFeatures _computeGlobalFeatures(List<CharacterFeatures> chars) {
    final slantAngles = chars.map((c) => c.slantAngle).toList();
    final aspectRatios = chars.map((c) => c.aspectRatio).toList();
    final densities = chars.map((c) => c.strokeDensity).toList();
    final cogXs = chars.map((c) => c.centerOfGravity.x).toList();
    final cogYs = chars.map((c) => c.centerOfGravity.y).toList();
    final spacings = chars.map((c) => c.avgStrokeSpacing).toList();

    return GlobalStyleFeatures(
      avgSlantAngle: MathUtils.mean(slantAngles),
      slantAngleStd: MathUtils.standardDeviation(slantAngles),
      avgAspectRatio: MathUtils.mean(aspectRatios),
      aspectRatioStd: MathUtils.standardDeviation(aspectRatios),
      avgStrokeDensity: MathUtils.mean(densities),
      centerOfGravityX: MathUtils.mean(cogXs),
      centerOfGravityY: MathUtils.mean(cogYs),
      avgStrokeSpacing: MathUtils.mean(spacings),
      strokeSpacingStd: MathUtils.standardDeviation(spacings),
    );
  }

  /// 按笔画类型计算特征
  Map<String, StrokeTypeFeatures> _computeStrokeTypeFeatures(
    List<CharacterFeatures> chars,
  ) {
    // 收集所有笔画特征，按类型分组
    final strokesByType = <String, List<StrokeFeatures>>{};

    for (final char in chars) {
      for (final stroke in char.strokeFeatures) {
        final type = stroke.strokeType ?? '未知';
        strokesByType.putIfAbsent(type, () => []);
        strokesByType[type]!.add(stroke);
      }
    }

    // 计算每种类型的统计特征
    final result = <String, StrokeTypeFeatures>{};

    for (final entry in strokesByType.entries) {
      final typeName = entry.key;
      final strokes = entry.value;

      if (strokes.isEmpty) continue;

      final lengths = strokes.map((s) => s.length).toList();
      final curvatures = strokes.map((s) => s.avgCurvature).toList();
      final startAngles = strokes.map((s) => s.startAngle).toList();
      final endAngles = strokes.map((s) => s.endAngle).toList();
      final directions = strokes.map((s) => s.direction).toList();

      result[typeName] = StrokeTypeFeatures(
        typeName: typeName,
        sampleCount: strokes.length,
        avgLength: MathUtils.mean(lengths),
        lengthStd: MathUtils.standardDeviation(lengths),
        avgCurvature: MathUtils.mean(curvatures),
        curvatureStd: MathUtils.standardDeviation(curvatures),
        avgStartAngle: MathUtils.mean(startAngles),
        startAngleStd: MathUtils.standardDeviation(startAngles),
        avgEndAngle: MathUtils.mean(endAngles),
        endAngleStd: MathUtils.standardDeviation(endAngles),
        avgDirection: MathUtils.mean(directions),
        directionStd: MathUtils.standardDeviation(directions),
      );
    }

    return result;
  }
}

/// 字符分析输入
class CharacterAnalysisInput {
  /// 字符（如果已知）
  final String? character;

  /// 骨架提取结果
  final SkeletonResult skeleton;

  /// 各笔画的类型（如果已知）
  final List<String>? strokeTypes;

  CharacterAnalysisInput({
    this.character,
    required this.skeleton,
    this.strokeTypes,
  });
}