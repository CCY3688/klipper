import 'geometry.dart';
import 'stroke.dart';

/// 表示一个字形（Glyph）
/// 
/// 一个字形包含该字符的所有笔画数据，以及可选的元信息。
/// 坐标使用归一化坐标系(0~1)，实际渲染时再映射到具体尺寸。
class Glyph {
  /// 对应的字符
  final String character;

  /// 笔画列表（按书写顺序排列）
  final List<Stroke> strokes;

  /// 建议的宽高比（可选）
  /// 有些字偏扁（如"一"），有些字偏长（如"中"）
  /// 为 null 时使用默认的 1:1
  final double? aspectRatio;

  const Glyph({
    required this.character,
    required this.strokes,
    this.aspectRatio,
  });

  /// 从原始坐标数据创建（兼容旧 JSON 格式）
  /// 
  /// 旧格式：{"strokes": [[[x,y], [x,y]], [[x,y], [x,y]]]}
  /// 每个内层数组是一个笔画的点列表
  factory Glyph.fromRawStrokes(String char, List<List<Vec2>> rawStrokes) {
    final strokes = rawStrokes
        .map((points) => Stroke.fromPoints(points))
        .where((stroke) => stroke.isValid)  // 过滤掉无效笔画
        .toList();
    
    return Glyph(
      character: char,
      strokes: strokes,
    );
  }

  /// 从 JSON Map 创建
  /// 
  /// 支持两种格式：
  /// 1. 旧格式：{"strokes": [[[x,y], ...]]}
  /// 2. 新格式（预留）：{"strokes": [{"points": [...], "type": "horizontal"}]}
  factory Glyph.fromJson(String char, Map<String, dynamic> json) {
    final rawStrokes = json['strokes'] as List<dynamic>;
    
    final strokes = <Stroke>[];
    
    for (final strokeData in rawStrokes) {
      if (strokeData is List) {
        // 旧格式：直接是点数组
        final points = _parsePointList(strokeData);
        if (points.length >= 2) {
          strokes.add(Stroke.fromPoints(points));
        }
      } else if (strokeData is Map) {
        // 新格式：包含 points 和可选的 type
        final points = _parsePointList(strokeData['points'] as List);
        final typeStr = strokeData['type'] as String?;
        final type = typeStr != null ? _parseStrokeType(typeStr) : null;
        
        if (points.length >= 2) {
          strokes.add(Stroke(points: points, type: type));
        }
      }
    }

    return Glyph(
      character: char,
      strokes: strokes,
      aspectRatio: (json['aspectRatio'] as num?)?.toDouble(),
    );
  }

  // ===== 便捷访问器 =====

  /// 笔画总数
  int get strokeCount => strokes.length;

  /// 所有笔画的总点数
  int get totalPointCount => strokes.fold(0, (sum, s) => sum + s.pointCount);

  /// 是否是空字形（没有可用笔画）
  bool get isEmpty => strokes.isEmpty;

  /// 整个字形的边界框
  ({double minX, double minY, double maxX, double maxY}) get boundingBox {
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final stroke in strokes) {
      final box = stroke.boundingBox;
      if (box.minX < minX) minX = box.minX;
      if (box.minY < minY) minY = box.minY;
      if (box.maxX > maxX) maxX = box.maxX;
      if (box.maxY > maxY) maxY = box.maxY;
    }

    return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  /// 转换为旧格式（用于兼容旧代码或导出）
  List<List<Vec2>> toRawStrokes() {
    return strokes.map((s) => s.points).toList();
  }

  // ===== 私有辅助方法 =====

  static List<Vec2> _parsePointList(List<dynamic> data) {
    return data.map((p) {
      if (p is List && p.length >= 2) {
        return Vec2(
          (p[0] as num).toDouble(),
          (p[1] as num).toDouble(),
        );
      }
      throw FormatException('Invalid point format: $p');
    }).toList();
  }

  static StrokeType? _parseStrokeType(String type) {
    return switch (type) {
      'horizontal' => StrokeType.horizontal,
      'vertical' => StrokeType.vertical,
      'leftFalling' => StrokeType.leftFalling,
      'rightFalling' => StrokeType.rightFalling,
      'dot' => StrokeType.dot,
      'turning' => StrokeType.turning,
      'hook' => StrokeType.hook,
      _ => StrokeType.other,
    };
  }
}