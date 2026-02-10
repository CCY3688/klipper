import 'geometry.dart';

/// 一段折线（polyline）
/// - penDown=true：这段折线会在纸上留下笔迹
/// - penDown=false：这段折线只是“抬笔移动轨迹”（预览用虚线显示）
class ToolPolyline {
  final bool penDown;
  final List<Vec2> points; // >=2 更有意义

  const ToolPolyline({
    required this.penDown,
    required this.points,
  }) : assert(points.length >= 2, 'ToolPolyline.points should have at least 2 points');
}

/// 一页/一段要执行的完整路径（保持顺序）
class ToolPath {
  final List<ToolPolyline> polylines;

  const ToolPath({required this.polylines});

  static const empty = ToolPath(polylines: []);
}