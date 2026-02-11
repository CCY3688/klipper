/// 笔画轨迹 - 与你现有字库兼容的数据结构
/// 
/// 对应字库中的格式：
/// {"character":"丕","strokes":[...],"medians":[...]}
library;

class StrokeTrajectory {
  /// SVG 路径字符串 (如 "M 585 690 Q 604 696...")
  final String svgPath;
  
  /// 中线点列 (如 [[228,686],[258,676],...])
  final List<List<int>> medians;
  
  /// 笔画类型 (横、竖、撇、捺等)
  final String? strokeType;

  StrokeTrajectory({
    required this.svgPath,
    required this.medians,
    this.strokeType,
  });

  /// 从 JSON 创建
  factory StrokeTrajectory.fromJson(Map<String, dynamic> json) {
    return StrokeTrajectory(
      svgPath: json['path'] as String,
      medians: (json['median'] as List)
          .map((p) => (p as List).cast<int>().toList())
          .toList(),
      strokeType: json['type'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'path': svgPath,
      'median': medians,
      if (strokeType != null) 'type': strokeType,
    };
  }

  /// 获取所有点的 X 坐标
  List<int> get xCoordinates => medians.map((p) => p[0]).toList();

  /// 获取所有点的 Y 坐标
  List<int> get yCoordinates => medians.map((p) => p[1]).toList();

  /// 计算边界框
  Map<String, int> get boundingBox {
    final xs = xCoordinates;
    final ys = yCoordinates;
    return {
      'minX': xs.reduce((a, b) => a < b ? a : b),
      'maxX': xs.reduce((a, b) => a > b ? a : b),
      'minY': ys.reduce((a, b) => a < b ? a : b),
      'maxY': ys.reduce((a, b) => a > b ? a : b),
    };
  }

  @override
  String toString() {
    return 'StrokeTrajectory(points: ${medians.length}, type: $strokeType)';
  }
}