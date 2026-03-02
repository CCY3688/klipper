/// 骨架向量化器 + 笔画分割器
///
/// 将 Zhang-Suen 骨架位图转换为有序折线列表（候选笔画）。
///
/// 算法：
/// 1. 扫描骨架像素，构建像素邻接图
/// 2. 识别关键点（endpoint: 1邻域, junction: >2邻域）
/// 3. 沿路径追踪：从端点/交叉点出发，沿骨架游走直到下一个端点/交叉点
/// 4. 对短段和噪声进行过滤
library;

import 'dart:math' as math;
import 'outline_rasterizer.dart';

/// 归一化的笔画折线（坐标范围 0~1）
class SkeletonStroke {
  /// 归一化坐标点序列
  final List<({double x, double y})> points;
  const SkeletonStroke(this.points);
  int get length => points.length;
}

class SkeletonVectorizer {
  /// 从骨架位图提取候选笔画列表
  ///
  /// [skeleton] Zhang-Suen 细化后的位图
  /// [minStrokePixels] 最短笔画像素长度（过滤噪声小段）
  static List<SkeletonStroke> vectorize(
    GlyphBitmap skeleton, {
    int minStrokePixels = 5,
  }) {
    final w = skeleton.width;
    final h = skeleton.height;

    // ── 1. 收集所有骨架像素 ────────────────────────────────────────────
    final bonePixels = <int>{}; // 编码为 y*w+x
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (skeleton.isSet(x, y)) {
          bonePixels.add(y * w + x);
        }
      }
    }

    if (bonePixels.isEmpty) return [];

    // ── 2. 计算每个像素的邻域数 ────────────────────────────────────────
    int neighborCount(int x, int y) {
      int cnt = 0;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (nx >= 0 && nx < w && ny >= 0 && ny < h &&
              bonePixels.contains(ny * w + nx)) {
            cnt++;
          }
        }
      }
      return cnt;
    }

    final degreeByKey = <int, int>{};
    for (final key in bonePixels) {
      final x = key % w;
      final y = key ~/ w;
      degreeByKey[key] = neighborCount(x, y);
    }

    // 分类关键点
    final endpoints  = <int>{}; // 1 邻域
    final junctions  = <int>{}; // ≥3 邻域
    for (final key in degreeByKey.keys) {
      final cnt = degreeByKey[key] ?? 0;
      if (cnt == 1) endpoints.add(key);
      if (cnt >= 3) junctions.add(key);
      if (cnt == 0) endpoints.add(key); // 孤立点（0邻域）→ 端点
    }

    // 相邻交叉像素会形成“交叉团块”，若直接把每个像素都当作 junction，
    // 会把一笔切成大量小段。将 8 邻接的 junction 聚成簇，并以簇代表点替代。
    final junctionClusterByPixel = _buildJunctionClusters(junctions, w, h);
    final junctionRepresentatives = _pickJunctionRepresentatives(
      junctions,
      junctionClusterByPixel,
      degreeByKey,
    );

    // ── 3. 路径追踪 ────────────────────────────────────────────────────
    final visitedEdges = <int>{};
    final strokes = <List<({double x, double y})>>[];

    // 从端点出发追踪
    final startPoints = <int>[...endpoints, ...junctionRepresentatives];

    for (final startKey in startPoints) {
      final startX = startKey % w;
      final startY = startKey ~/ w;

      // 从该起点沿每个未访问方向出发
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = startX + dx;
          final ny = startY + dy;
          if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
          final neighborKey = ny * w + nx;
          if (!bonePixels.contains(neighborKey)) continue;

          // 尝试追踪这条路径
          final edgeKey = _edgeKey(startKey, neighborKey);
          if (visitedEdges.contains(edgeKey)) continue;

          final path = _tracePath(
            startKey, neighborKey,
            bonePixels, endpoints, junctions,
            junctionClusterByPixel,
            visitedEdges, w,
          );

          if (path.length >= minStrokePixels) {
            strokes.add(path.map((key) {
              final px = key % w;
              final py = key ~/ w;
              return (
                x: px / (w - 1).toDouble(),
                y: py / (h - 1).toDouble(),
              );
            }).toList());
          }
        }
      }
    }

    bool hasUnvisitedEdge(int key) {
      final x = key % w;
      final y = key ~/ w;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
          final nKey = ny * w + nx;
          if (!bonePixels.contains(nKey)) continue;
          if (!visitedEdges.contains(_edgeKey(key, nKey))) return true;
        }
      }
      return false;
    }

    // 处理未被端点覆盖的孤立环路（如"○"）
    for (final key in bonePixels) {
      if (!hasUnvisitedEdge(key)) continue;
      // 从未访问的骨架点开始追踪环路
      final path = _traceLoop(key, bonePixels, visitedEdges, w, h);
      if (path.length >= minStrokePixels) {
        strokes.add(path.map((k) {
          final px = k % w;
          final py = k ~/ w;
          return (x: px / (w - 1).toDouble(), y: py / (h - 1).toDouble());
        }).toList());
      }
    }

    // ── 4. 向量阶段去碎合并（在接链前先减小碎段规模） ───────────────────────
    final mergedStrokes = _mergeShortFragments(
      strokes,
      minStrokePixels: minStrokePixels,
      maxDimensionPx: math.max(w, h),
    );

    // ── 5. 构建结果 ────────────────────────────────────────────────────
    return mergedStrokes
        .where((s) => s.length >= minStrokePixels)
        .map(_simplify)
        .map((s) => SkeletonStroke(s))
        .toList();
  }

  /// 沿骨架追踪路径，直到到达另一个端点/交叉点或已访问边
  static List<int> _tracePath(
    int from, int next,
    Set<int> bonePixels,
    Set<int> endpoints,
    Set<int> junctions,
    Map<int, int> junctionClusterByPixel,
    Set<int> visitedEdges,
    int w,
  ) {
    final path = <int>[from, next];
    visitedEdges.add(_edgeKey(from, next));

    int prev = from;
    int cur = next;

    while (true) {
      // 到达端点则停止
      if (endpoints.contains(cur)) break;

      // 到达交叉点时，优先尝试“直行穿越”以保持同一笔画连续。
      // 若无法找到合理延续方向，再在此停止分段。
      if (junctions.contains(cur)) {
        final curCluster = junctionClusterByPixel[cur];
        final prevCluster = junctionClusterByPixel[prev];
        final isInsideSameJunctionCluster =
            curCluster != null && prevCluster != null && curCluster == prevCluster;
        if (isInsideSameJunctionCluster) {
          // 在同一个交叉团块内部游走，不在此处分段。
        } else {
        final pass = _pickPassThroughNext(
          prev,
          cur,
          bonePixels,
          junctionClusterByPixel,
          visitedEdges,
          w,
        );
        if (pass == null) break;

        visitedEdges.add(_edgeKey(cur, pass));
        path.add(pass);
        prev = cur;
        cur = pass;
        continue;
        }
      }

      final cx = cur % w;
      final cy = cur ~/ w;
      final px = prev % w;
      final py = prev ~/ w;

      // 找到下一个未访问邻居（排除来自方向）
      int? nextKey;
      double bestScore = double.infinity;

      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = cx + dx;
          final ny = cy + dy;
          // 不回头（排除 prev）
          if (nx == px && ny == py) continue;

          final nKey = ny * w + nx;
          if (!bonePixels.contains(nKey)) continue;

          final edge = _edgeKey(cur, nKey);
          if (visitedEdges.contains(edge)) continue;

          // 优先方向连续性（选方向角最接近当前行进方向的邻居）
          final ddx = nx - cx;
          final ddy = ny - cy;
          final prevDx = cx - px;
          final prevDy = cy - py;
          final dot = -(ddx * prevDx + ddy * prevDy).toDouble();
          if (dot < bestScore) {
            bestScore = dot;
            nextKey = nKey;
          }
        }
      }

      if (nextKey == null) break;

      visitedEdges.add(_edgeKey(cur, nextKey));
      path.add(nextKey);
      prev = cur;
      cur = nextKey;
    }

    return path;
  }

  /// 在交叉点选择“直行”方向的下一步。
  ///
  /// 返回 null 表示无法可靠穿越该交叉点，应在此处截断分段。
  static int? _pickPassThroughNext(
    int prev,
    int cur,
    Set<int> bonePixels,
    Map<int, int> junctionClusterByPixel,
    Set<int> visitedEdges,
    int w,
  ) {
    final cx = cur % w;
    final cy = cur ~/ w;
    final px = prev % w;
    final py = prev ~/ w;

    final inDx = cx - px;
    final inDy = cy - py;
    final inLen = math.sqrt((inDx * inDx + inDy * inDy).toDouble());
    if (inLen < 1e-9) return null;

    int? bestKey;
    double bestCos = -2.0;

    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = cx + dx;
        final ny = cy + dy;
        if (nx == px && ny == py) continue;

        final nKey = ny * w + nx;
        if (!bonePixels.contains(nKey)) continue;
        if (visitedEdges.contains(_edgeKey(cur, nKey))) continue;

        final curCluster = junctionClusterByPixel[cur];
        final nextCluster = junctionClusterByPixel[nKey];
        if (curCluster != null && nextCluster != null && curCluster == nextCluster) {
          continue;
        }

        final outDx = nx - cx;
        final outDy = ny - cy;
        final outLen = math.sqrt((outDx * outDx + outDy * outDy).toDouble());
        if (outLen < 1e-9) continue;

        final cos = (inDx * outDx + inDy * outDy) / (inLen * outLen);
        if (cos > bestCos) {
          bestCos = cos;
          bestKey = nKey;
        }
      }
    }

    // 仅在方向足够连续时穿越交叉点，避免错误跨笔画。
    const minPassThroughCos = 0.2; // 约 <= 78°，降低交叉点误分段
    if (bestKey == null || bestCos < minPassThroughCos) return null;
    return bestKey;
  }

  static List<List<({double x, double y})>> _mergeShortFragments(
    List<List<({double x, double y})>> strokes, {
    required int minStrokePixels,
    required int maxDimensionPx,
  }) {
    if (strokes.length <= 1) return strokes;

    final working = strokes
        .where((s) => s.length >= 2)
        .map((s) => List<({double x, double y})>.from(s))
        .toList();
    if (working.length <= 1) return working;

    final shortLenPx = math.max(5.0, minStrokePixels * 2.2);
    final mergeDist = math.max(2.5, minStrokePixels * 1.2) /
        (math.max(2, maxDimensionPx - 1)).toDouble();
    const maxTurnDeg = 125.0;

    bool merged = true;
    int guard = 0;
    while (merged && guard < 200) {
      guard++;
      merged = false;

      double bestScore = double.infinity;
      int bestI = -1;
      int bestJ = -1;
      bool bestFlipI = false;
      bool bestFlipJ = false;

      for (int i = 0; i < working.length; i++) {
        final li = _polylineLength(working[i]) * (maxDimensionPx - 1);

        for (int j = i + 1; j < working.length; j++) {
          final lj = _polylineLength(working[j]) * (maxDimensionPx - 1);
          if (li > shortLenPx && lj > shortLenPx) continue;

          for (final flipI in [false, true]) {
            for (final flipJ in [false, true]) {
              final tail = flipI ? working[i].first : working[i].last;
              final head = flipJ ? working[j].last : working[j].first;
              final d = _ptDist(tail, head);
              if (d > mergeDist) continue;

              final angle = _junctionAngleNorm(working[i], flipI, working[j], flipJ);
              if (angle > maxTurnDeg) continue;

              final shortBias = math.min(li, lj) / shortLenPx;
              final score =
                  angle * 1.2 + (d / mergeDist) * 25.0 + shortBias * 8.0;
              if (score < bestScore) {
                bestScore = score;
                bestI = i;
                bestJ = j;
                bestFlipI = flipI;
                bestFlipJ = flipJ;
              }
            }
          }
        }
      }

      if (bestI != -1) {
        final first = bestFlipI ? working[bestI].reversed.toList() : working[bestI];
        final second = bestFlipJ ? working[bestJ].reversed.toList() : working[bestJ];
        final mergedPts = _mergeChainPoints(first, second);

        final hi = bestI > bestJ ? bestI : bestJ;
        final lo = bestI < bestJ ? bestI : bestJ;
        working.removeAt(hi);
        working.removeAt(lo);
        working.insert(lo, mergedPts);
        merged = true;
      }
    }

    return working;
  }

  static double _junctionAngleNorm(
    List<({double x, double y})> ci,
    bool flipI,
    List<({double x, double y})> cj,
    bool flipJ,
  ) {
    if (ci.length < 2 || cj.length < 2) return 0;

    const span = 4;
    final ({double x, double y}) ti;
    if (!flipI) {
      final k = math.max(0, ci.length - span);
      ti = _unitVec(ci.last.x - ci[k].x, ci.last.y - ci[k].y);
    } else {
      final k = math.min(ci.length - 1, span - 1);
      ti = _unitVec(ci.first.x - ci[k].x, ci.first.y - ci[k].y);
    }

    final ({double x, double y}) tj;
    if (!flipJ) {
      final k = math.min(cj.length - 1, span - 1);
      tj = _unitVec(cj[k].x - cj.first.x, cj[k].y - cj.first.y);
    } else {
      final k = math.max(0, cj.length - span);
      tj = _unitVec(cj[k].x - cj.last.x, cj[k].y - cj.last.y);
    }

    final dot = (ti.x * tj.x + ti.y * tj.y).clamp(-1.0, 1.0);
    return math.acos(dot) * 180.0 / math.pi;
  }

  static double _polylineLength(List<({double x, double y})> pts) {
    if (pts.length < 2) return 0;
    double total = 0;
    for (int i = 1; i < pts.length; i++) {
      total += _ptDist(pts[i - 1], pts[i]);
    }
    return total;
  }

  static List<({double x, double y})> _mergeChainPoints(
    List<({double x, double y})> first,
    List<({double x, double y})> second,
  ) {
    if (first.isEmpty) return List<({double x, double y})>.from(second);
    if (second.isEmpty) return List<({double x, double y})>.from(first);

    final merged = <({double x, double y})>[...first];
    if (_ptDist(first.last, second.first) < 1e-9) {
      merged.addAll(second.skip(1));
    } else {
      merged.addAll(second);
    }
    return merged;
  }

  static ({double x, double y}) _unitVec(double dx, double dy) {
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-9) return (x: 1, y: 0);
    return (x: dx / len, y: dy / len);
  }

  static double _ptDist(
    ({double x, double y}) a,
    ({double x, double y}) b,
  ) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  static Map<int, int> _buildJunctionClusters(
    Set<int> junctions,
    int w,
    int h,
  ) {
    final clusterByPixel = <int, int>{};
    int clusterId = 0;

    for (final start in junctions) {
      if (clusterByPixel.containsKey(start)) continue;

      final queue = <int>[start];
      clusterByPixel[start] = clusterId;

      while (queue.isNotEmpty) {
        final cur = queue.removeLast();
        final cx = cur % w;
        final cy = cur ~/ w;

        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = cx + dx;
            final ny = cy + dy;
            if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;

            final nKey = ny * w + nx;
            if (!junctions.contains(nKey)) continue;
            if (clusterByPixel.containsKey(nKey)) continue;

            clusterByPixel[nKey] = clusterId;
            queue.add(nKey);
          }
        }
      }

      clusterId++;
    }

    return clusterByPixel;
  }

  static Set<int> _pickJunctionRepresentatives(
    Set<int> junctions,
    Map<int, int> junctionClusterByPixel,
    Map<int, int> degreeByKey,
  ) {
    final repByCluster = <int, int>{};
    final bestDegreeByCluster = <int, int>{};

    for (final key in junctions) {
      final cluster = junctionClusterByPixel[key];
      if (cluster == null) continue;

      final degree = degreeByKey[key] ?? 0;
      final bestDegree = bestDegreeByCluster[cluster] ?? -1;

      if (degree > bestDegree) {
        bestDegreeByCluster[cluster] = degree;
        repByCluster[cluster] = key;
      }
    }

    return repByCluster.values.toSet();
  }

  /// 追踪孤立环路
  static List<int> _traceLoop(
    int start,
    Set<int> bonePixels,
    Set<int> visitedEdges,
    int w, int h,
  ) {
    final path = <int>[start];
    int prev = -1;
    int cur = start;

    for (int step = 0; step < bonePixels.length; step++) {
      final cx = cur % w;
      final cy = cur ~/ w;
      int? nextKey;

      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = cx + dx;
          final ny = cy + dy;
          final nKey = ny * w + nx;
          if (nKey == prev) continue;
          if (!bonePixels.contains(nKey)) continue;
          if (visitedEdges.contains(_edgeKey(cur, nKey))) continue;

          nextKey = nKey;
          break;
        }
        if (nextKey != null) break;
      }

      if (nextKey == null) break;
      if (nextKey == start && path.length > 2) break; // 闭合

      visitedEdges.add(_edgeKey(cur, nextKey));
      path.add(nextKey);
      prev = cur;
      cur = nextKey;
    }

    return path;
  }

  /// 有序边 key（无向）
  static int _edgeKey(int a, int b) => a < b ? a * 1000000 + b : b * 1000000 + a;

  /// Douglas-Peucker 简化折线（去除冗余中间点）
  static List<({double x, double y})> _simplify(
    List<({double x, double y})> pts,
  ) {
    if (pts.length <= 2) return pts;
    return _dpSimplify(pts, 0, pts.length - 1, 0.004);
  }

  static List<({double x, double y})> _dpSimplify(
    List<({double x, double y})> pts,
    int start, int end,
    double epsilon,
  ) {
    if (end - start <= 1) return [pts[start], pts[end]];

    double maxDist = 0;
    int maxIdx = start;

    final p0 = pts[start];
    final p1 = pts[end];

    for (int i = start + 1; i < end; i++) {
      final d = _perpendicularDist(pts[i], p0, p1);
      if (d > maxDist) {
        maxDist = d;
        maxIdx = i;
      }
    }

    if (maxDist <= epsilon) {
      return [pts[start], pts[end]];
    }

    final left  = _dpSimplify(pts, start, maxIdx, epsilon);
    final right = _dpSimplify(pts, maxIdx, end, epsilon);
    return [...left.sublist(0, left.length - 1), ...right];
  }

  static double _perpendicularDist(
    ({double x, double y}) p,
    ({double x, double y}) a,
    ({double x, double y}) b,
  ) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) {
      final ex = p.x - a.x;
      final ey = p.y - a.y;
      return math.sqrt(ex * ex + ey * ey);
    }
    final cross = (p.x - a.x) * dy - (p.y - a.y) * dx;
    return cross.abs() / math.sqrt(len2);
  }
}
