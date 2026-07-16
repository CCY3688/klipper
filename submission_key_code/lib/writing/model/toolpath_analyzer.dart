import 'toolpath.dart';

enum ToolPathIssueLevel { info, warning, error }

class ToolPathIssue {
  final ToolPathIssueLevel level;
  final String title;
  final String message;
  final List<int>? relatedPolylineIndices;

  ToolPathIssue({
    required this.level,
    required this.title,
    required this.message,
    this.relatedPolylineIndices,
  });
}

class ToolPathAnalyzer {
  static List<ToolPathIssue> analyze(ToolPath toolPath) {
    final issues = <ToolPathIssue>[];
    
    if (toolPath.polylines.isEmpty) {
      issues.add(ToolPathIssue(
        level: ToolPathIssueLevel.warning,
        title: '空轨迹',
        message: '没有找到任何有效的移动轨迹。',
      ));
      return issues;
    }

    final penDownPolylines = <int, ToolPolyline>{};
    for (int i = 0; i < toolPath.polylines.length; i++) {
      if (toolPath.polylines[i].penDown) {
        penDownPolylines[i] = toolPath.polylines[i];
      }
    }

    // 1. 检测重复笔画
    final checked = <int>{};
    for (final i in penDownPolylines.keys) {
      if (checked.contains(i)) continue;
      final p1 = penDownPolylines[i]!;
      
      for (final j in penDownPolylines.keys) {
        if (i == j || checked.contains(j)) continue;
        final p2 = penDownPolylines[j]!;
        
        if (_isDuplicate(p1, p2)) {
          issues.add(ToolPathIssue(
            level: ToolPathIssueLevel.warning,
            title: '检测到重复笔画',
            message: '第 $i 段和第 $j 段轨迹几乎完全重合。',
            relatedPolylineIndices: [i, j],
          ));
          checked.add(j);
        }
      }
      checked.add(i);
    }

    // 2. 检测轨迹断点 (笔尖瞬移)
    for (int i = 0; i < toolPath.polylines.length - 1; i++) {
      final p1 = toolPath.polylines[i];
      final p2 = toolPath.polylines[i + 1];
      
      if (p1.points.last != p2.points.first) {
        issues.add(ToolPathIssue(
          level: ToolPathIssueLevel.error,
          title: '检测到笔尖瞬移',
          message: '第 $i 段末尾与第 ${i + 1} 段起点不连续，笔尖发生了非法跳变。',
          relatedPolylineIndices: [i, i + 1],
        ));
      }
    }

    // 3. 检测空笔画 (落笔后无位移)
    for (final i in penDownPolylines.keys) {
      final p = penDownPolylines[i]!;
      if (_isZeroLength(p)) {
        issues.add(ToolPathIssue(
          level: ToolPathIssueLevel.info,
          title: '零长度笔画',
          message: '第 $i 段落笔后没有有效移动，仅是一个点。',
          relatedPolylineIndices: [i],
        ));
      }
    }

    return issues;
  }

  static bool _isDuplicate(ToolPolyline a, ToolPolyline b) {
    if (a.points.length != b.points.length) return false;
    
    // 检查正向重合
    bool forward = true;
    for (int k = 0; k < a.points.length; k++) {
      if (a.points[k] != b.points[k]) {
        forward = false;
        break;
      }
    }
    if (forward) return true;

    // 检查反向重合
    bool backward = true;
    final len = a.points.length;
    for (int k = 0; k < len; k++) {
      if (a.points[k] != b.points[len - 1 - k]) {
        backward = false;
        break;
      }
    }
    return backward;
  }

  static bool _isZeroLength(ToolPolyline p) {
    if (p.points.length < 2) return true;
    final first = p.points.first;
    for (final pt in p.points) {
      if (pt != first) return false;
    }
    return true;
  }
}
