import 'dart:math' as math;
import '../models/character_data.dart';
import '../models/stroke_trajectory.dart';
import '../models/style_vector.dart';
import '../utils/math_utils.dart';

/// 风格迁移服务
/// 
/// 将用户的书写风格应用到标准字库
class StyleTransfer {
  /// 风格强度（0-1）
  double intensity;

  /// 随机变化量
  double randomness;

  StyleTransfer({
    this.intensity = 1.0,
    this.randomness = 0.1,
  });

  /// 将风格应用到字符
  CharacterData transfer(
    CharacterData standardChar,
    StyleVector style,
  ) {
    final transformedStrokes = <StrokeTrajectory>[];

    for (int i = 0; i < standardChar.strokes.length; i++) {
      final stroke = standardChar.strokes[i];
      final strokeType = stroke.strokeType;

      // 获取对应笔画类型的风格特征
      final typeFeatures = strokeType != null
          ? style.strokeTypes[strokeType]
          : null;

      // 转换笔画
      final transformed = _transferStroke(
        stroke,
        style.global,
        typeFeatures,
      );

      transformedStrokes.add(transformed);
    }

    return CharacterData(
      character: standardChar.character,
      strokes: transformedStrokes,
    );
  }

  /// 转换单个笔画
  StrokeTrajectory _transferStroke(
    StrokeTrajectory stroke,
    GlobalStyleFeatures globalStyle,
    StrokeTypeFeatures? typeStyle,
  ) {
    // 将中线点转换为 Point2D 列表
    var points = stroke.medians
        .map((p) => Point2D(p[0].toDouble(), p[1].toDouble()))
        .toList();

    if (points.isEmpty) return stroke;

    // 1. 应用整体倾斜
    points = _applySlant(points, globalStyle.avgSlantAngle * intensity);

    // 2. 应用曲率变化
    if (typeStyle != null) {
      points = _applyCurvature(points, typeStyle.avgCurvature * intensity);
    }

    // 3. 应用起笔/收笔风格
    if (typeStyle != null) {
      points = _applyStartEndStyle(points, typeStyle);
    }

    // 4. 添加自然变化
    points = _addNaturalVariation(points, globalStyle);

    // 转换回中线格式
    final newMedians = points
        .map((p) => [p.x.round(), p.y.round()])
        .toList();

    // 重新生成 SVG 路径
    final newSvgPath = _generateSvgPath(points);

    return StrokeTrajectory(
      svgPath: newSvgPath,
      medians: newMedians,
      strokeType: stroke.strokeType,
    );
  }

  /// 应用倾斜
  List<Point2D> _applySlant(List<Point2D> points, double slantAngle) {
    if (points.isEmpty || slantAngle.abs() < 0.01) return points;

    // 找到中心点
    final center = _getCenter(points);

    // 应用剪切变换（模拟倾斜）
    return points.map((p) {
      final dy = p.y - center.y;
      final shearX = dy * math.tan(slantAngle);
      return Point2D(p.x + shearX, p.y);
    }).toList();
  }

  /// 应用曲率变化
  List<Point2D> _applyCurvature(List<Point2D> points, double targetCurvature) {
    if (points.length < 3) return points;

    // 计算当前平均曲率
    double currentCurvature = 0;
    for (int i = 1; i < points.length - 1; i++) {
      currentCurvature += MathUtils.curvature(
        points[i - 1].x, points[i - 1].y,
        points[i].x, points[i].y,
        points[i + 1].x, points[i + 1].y,
      ).abs();
    }
    currentCurvature /= (points.length - 2);

    // 如果目标曲率更大，需要增加弯曲
    final curvatureDiff = targetCurvature - currentCurvature;
    if (curvatureDiff.abs() < 0.001) return points;

    final result = <Point2D>[points.first];

    for (int i = 1; i < points.length - 1; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final next = points[i + 1];

      // 计算法向量
      final tangent = Point2D(next.x - prev.x, next.y - prev.y).normalized();
      final normal = Point2D(-tangent.y, tangent.x);

      // 根据曲率差异调整位置
      final offset = curvatureDiff * 10 * intensity;
      final t = (i / (points.length - 1)) - 0.5; // -0.5 到 0.5
      final displacement = offset * (1 - 4 * t * t); // 中间最大

      result.add(Point2D(
        curr.x + normal.x * displacement,
        curr.y + normal.y * displacement,
      ));
    }

    result.add(points.last);
    return result;
  }

  /// 应用起笔/收笔风格
  List<Point2D> _applyStartEndStyle(
    List<Point2D> points,
    StrokeTypeFeatures typeStyle,
  ) {
    if (points.length < 4) return points;

    final result = List<Point2D>.from(points);

    // 调整起笔角度
    final startAngleDiff = typeStyle.avgStartAngle * intensity * 0.3;
    if (startAngleDiff.abs() > 0.01) {
      // 旋转前几个点
      for (int i = 1; i < math.min(3, points.length); i++) {
        final rotated = result[i].rotate(
          startAngleDiff * (1 - i / 3),
          result[0],
        );
        result[i] = rotated;
      }
    }

    // 调整收笔角度
    final endAngleDiff = typeStyle.avgEndAngle * intensity * 0.3;
    if (endAngleDiff.abs() > 0.01) {
      final lastIdx = points.length - 1;
      for (int i = lastIdx - 2; i < lastIdx; i++) {
        if (i < 0) continue;
        final rotated = result[i].rotate(
          endAngleDiff * ((lastIdx - i) / 3),
          result[lastIdx],
        );
        result[i] = rotated;
      }
    }

    return result;
  }

  /// 添加自然变化
  List<Point2D> _addNaturalVariation(
    List<Point2D> points,
    GlobalStyleFeatures globalStyle,
  ) {
    if (randomness <= 0) return points;

    final random = math.Random();
    final variation = randomness * 24; // 最大偏移量（1024坐标系下更可见）

    return points.map((p) {
      final dx = (random.nextDouble() - 0.5) * variation;
      final dy = (random.nextDouble() - 0.5) * variation;
      return Point2D(p.x + dx, p.y + dy);
    }).toList();
  }

  /// 获取点集中心
  Point2D _getCenter(List<Point2D> points) {
    if (points.isEmpty) return const Point2D(0, 0);

    double sumX = 0, sumY = 0;
    for (final p in points) {
      sumX += p.x;
      sumY += p.y;
    }

    return Point2D(sumX / points.length, sumY / points.length);
  }

  /// 生成 SVG 路径
  String _generateSvgPath(List<Point2D> points) {
    if (points.isEmpty) return '';
    if (points.length == 1) {
      return 'M ${points[0].x.round()} ${points[0].y.round()} Z';
    }

    final buffer = StringBuffer();

    // 起点
    buffer.write('M ${points[0].x.round()} ${points[0].y.round()} ');

    // 使用二次贝塞尔曲线连接点
    for (int i = 1; i < points.length - 1; i++) {
      final curr = points[i];
      final next = points[i + 1];

      // 控制点为当前点
      // 终点为当前点和下一点的中点
      final endX = (curr.x + next.x) / 2;
      final endY = (curr.y + next.y) / 2;

      buffer.write(
        'Q ${curr.x.round()} ${curr.y.round()} '
        '${endX.round()} ${endY.round()} ',
      );
    }

    // 最后一段
    if (points.length >= 2) {
      final last = points.last;
      final secondLast = points[points.length - 2];
      buffer.write(
        'Q ${secondLast.x.round()} ${secondLast.y.round()} '
        '${last.x.round()} ${last.y.round()} ',
      );
    }

    buffer.write('Z');
    return buffer.toString();
  }
}

/// 批量风格迁移
class BatchStyleTransfer {
  final StyleTransfer _transfer;
  final StyleVector _style;

  BatchStyleTransfer({
    required StyleVector style,
    double intensity = 1.0,
    double randomness = 0.1,
  })  : _style = style,
        _transfer = StyleTransfer(
          intensity: intensity,
          randomness: randomness,
        );

  /// 转换多个字符
  List<CharacterData> transferAll(List<CharacterData> characters) {
    return characters.map((c) => _transfer.transfer(c, _style)).toList();
  }

  /// 异步转换（带进度回调）
  Stream<TransferProgress> transferAllAsync(
    List<CharacterData> characters,
  ) async* {
    for (int i = 0; i < characters.length; i++) {
      final transformed = _transfer.transfer(characters[i], _style);

      yield TransferProgress(
        current: i + 1,
        total: characters.length,
        character: transformed,
      );

      // 让出执行权，避免阻塞 UI
      await Future.delayed(Duration.zero);
    }
  }
}

/// 转换进度
class TransferProgress {
  final int current;
  final int total;
  final CharacterData character;

  TransferProgress({
    required this.current,
    required this.total,
    required this.character,
  });

  double get progress => current / total;
  bool get isComplete => current >= total;
}