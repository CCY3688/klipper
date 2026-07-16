/// TTF 字形轮廓数据结构
///
/// 表示从 TTF 二进制文件中解析出的原始字形轮廓（填充路径），
/// 由多条封闭轮廓（contour）组成，每条轮廓由二次贝塞尔曲线描述。
library;

/// TTF 轮廓图中一个点
class TtfPoint {
  final double x;
  final double y;
  /// true = 在曲线上；false = 二次贝塞尔控制点（不在曲线上）
  final bool onCurve;

  const TtfPoint(this.x, this.y, {required this.onCurve});

  @override
  String toString() => 'TtfPoint($x, $y, onCurve: $onCurve)';
}

/// 一条封闭轮廓（由若干 TtfPoint 首尾相连构成闭合路径）
class TtfContour {
  final List<TtfPoint> points;
  const TtfContour(this.points);

  bool get isEmpty => points.isEmpty;
  int get length => points.length;
}

/// 单个字形的完整轮廓数据（从 glyf 表解析）
class TtfGlyphOutline {
  /// 字形前进宽度（字体单位）
  final int advanceWidth;

  /// 左侧轴承（字体单位）
  final int leftSideBearing;

  /// 所有封闭轮廓列表（空格等空字形时为空）
  final List<TtfContour> contours;

  /// 边界框（字体单位，Y轴向上为正）
  final int xMin;
  final int yMin;
  final int xMax;
  final int yMax;

  const TtfGlyphOutline({
    required this.advanceWidth,
    required this.leftSideBearing,
    required this.contours,
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
  });

  /// 是否是空字形（无法渲染，如空格）
  bool get isEmpty => contours.isEmpty;

  /// 字形在字体单位中的宽度
  int get width => xMax - xMin;

  /// 字形在字体单位中的高度
  int get height => yMax - yMin;
}
