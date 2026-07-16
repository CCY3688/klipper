/// 笔画排序优化器
/// 
/// 用于"快速模式"：通过优化字内笔画顺序来减少抬笔移动距离。
/// 核心算法：贪心最近邻 (Greedy Nearest Neighbor)
/// - 从当前笔尖位置出发，选择起点或终点距离最近的下一笔
/// - 如果终点更近，则反向该笔画
library;

import '../model/geometry.dart';

/// 单个笔画的表示（用于优化计算）
class _Stroke {
  final List<Vec2> points;
  bool reversed;
  
  _Stroke(this.points) : reversed = false;
  
  Vec2 get start => reversed ? points.last : points.first;
  Vec2 get end => reversed ? points.first : points.last;
  
  List<Vec2> get orderedPoints => reversed ? points.reversed.toList() : points;
}

/// 笔画排序优化器
class StrokeOptimizer {
  /// 优化单个字符内的笔画顺序
  /// 
  /// [strokes] 原始笔画列表（每个笔画是点的列表）
  /// [startFrom] 笔尖起始位置（可选，默认为第一笔的起点）
  /// [allowReverse] 是否允许反向笔画（某些笔画反向书写效果可能不同）
  /// 
  /// 返回：优化后的笔画列表
  static List<List<Vec2>> optimizeGlyph(
    List<List<Vec2>> strokes, {
    Vec2? startFrom,
    bool allowReverse = true,
  }) {
    if (strokes.isEmpty) return strokes;
    if (strokes.length == 1) return strokes;
    
    // 转换为可变结构
    final remaining = strokes
        .where((s) => s.length >= 2)
        .map((s) => _Stroke(s))
        .toList();
    
    if (remaining.isEmpty) return strokes;
    
    final result = <_Stroke>[];
    Vec2 cursor = startFrom ?? remaining.first.start;
    
    // 贪心选择：每次选距离当前位置最近的笔画
    while (remaining.isNotEmpty) {
      int bestIdx = 0;
      double bestDist = double.infinity;
      bool shouldReverse = false;
      
      for (int i = 0; i < remaining.length; i++) {
        final stroke = remaining[i];
        
        // 检查起点距离
        final distStart = cursor.distanceTo(stroke.points.first);
        if (distStart < bestDist) {
          bestDist = distStart;
          bestIdx = i;
          shouldReverse = false;
        }
        
        // 检查终点距离（如果允许反向）
        if (allowReverse) {
          final distEnd = cursor.distanceTo(stroke.points.last);
          if (distEnd < bestDist) {
            bestDist = distEnd;
            bestIdx = i;
            shouldReverse = true;
          }
        }
      }
      
      final chosen = remaining.removeAt(bestIdx);
      chosen.reversed = shouldReverse;
      result.add(chosen);
      cursor = chosen.end;
    }
    
    return result.map((s) => s.orderedPoints).toList();
  }
  
  /// 计算一组笔画的总抬笔移动距离（用于评估优化效果）
  static double calculatePenUpDistance(List<List<Vec2>> strokes, {Vec2? startFrom}) {
    if (strokes.isEmpty) return 0;
    
    double total = 0;
    Vec2 cursor = startFrom ?? strokes.first.first;
    
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      
      // 移动到笔画起点的距离
      total += _sqrt(cursor.distanceTo(stroke.first));
      cursor = stroke.last;
    }
    
    return total;
  }
  
  static double _sqrt(double x) => x > 0 ? x * 0.5 + 0.5 : 0; // 简化sqrt近似，足够比较大小
}
