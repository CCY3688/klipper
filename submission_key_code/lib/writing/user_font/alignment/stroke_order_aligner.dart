/// 笔顺对齐器
///
/// 将从 TTF 轮廓骨架提取的无序候选笔画，与 makemeahanzi 标准数据中的
/// 笔顺模板对齐，输出按照标准笔顺排列的笔画列表。
///
/// 算法：
/// 1. 将模板笔画（SVG Path 采样点）与候选骨架笔画建立代价矩阵（DTW 距离）
/// 2. 使用匈牙利算法（Hungarian Algorithm）求最优 1-对-1 匹配
/// 3. 按模板顺序重排候选笔画 → 输出有序骨架笔画
library;

import 'dart:math' as math;
import 'dtw.dart';
import '../skeleton/skeleton_vectorizer.dart';

/// 对齐结果
class AlignedStrokes {
  /// 按模板笔顺排列的骨架笔画
  final List<SkeletonStroke> orderedStrokes;

  /// 匹配质量分 (0~1, 1=完美)
  final double matchScore;

  /// 是否成功找到合理匹配（false = 候选/模板笔画数差异过大，降级处理）
  final bool reliable;

  const AlignedStrokes({
    required this.orderedStrokes,
    required this.matchScore,
    required this.reliable,
  });
}

class StrokeOrderAligner {
  /// 对齐骨架笔画到模板笔顺
  ///
  /// [candidateStrokes] 从骨架提取的无序笔画列表
  /// [templateStrokes]  从 makemeahanzi 数据加载的标准笔画点序列
  static AlignedStrokes align({
    required List<SkeletonStroke> candidateStrokes,
    required List<List<({double x, double y})>> templateStrokes,
  }) {
    if (candidateStrokes.isEmpty) {
      return const AlignedStrokes(
        orderedStrokes: [],
        matchScore: 0,
        reliable: false,
      );
    }

    if (templateStrokes.isEmpty) {
      // 无模板：按从上到下、从左到右排序（启发式）
      final sorted = _heuristicOrder(candidateStrokes);
      return AlignedStrokes(
        orderedStrokes: sorted,
        matchScore: 0.5,
        reliable: false,
      );
    }

    final n = templateStrokes.length; // 模板笔画数
    final m = candidateStrokes.length; // 候选笔画数

    // ── 1. 构建代价矩阵 ─────────────────────────────────────────────────
    // cost[i][j] = 模板笔画 i 与候选笔画 j 的 DTW 距离
    final cost = List.generate(n, (i) {
      return List.generate(m, (j) {
        return Dtw.distanceWithReverse(
          templateStrokes[i],
          candidateStrokes[j].points,
        );
      });
    });

    // ── 2. 匈牙利算法求最优匹配 ─────────────────────────────────────────
    final assignment = _hungarian(cost, n, m);

    // ── 3. 重排笔画 ──────────────────────────────────────────────────────
    final orderedStrokes = <SkeletonStroke>[];
    final usedCandidateIndexes = <int>{};
    double totalCost = 0;
    int matched = 0;

    for (int i = 0; i < n; i++) {
      final j = assignment[i];
      if (j >= 0 && j < m) {
        orderedStrokes.add(candidateStrokes[j]);
        usedCandidateIndexes.add(j);
        totalCost += cost[i][j];
        matched++;
      }
    }

    // 保留未匹配候选片段，避免在 n!=m 时被直接丢弃造成断续。
    if (usedCandidateIndexes.length < m) {
      final leftovers = <SkeletonStroke>[];
      for (int j = 0; j < m; j++) {
        if (!usedCandidateIndexes.contains(j)) {
          leftovers.add(candidateStrokes[j]);
        }
      }
      orderedStrokes.addAll(_heuristicOrder(leftovers));
    }

    // 数量差异过大时认为不可靠
    final reliable = (n - m).abs() <= math.max(n, m) ~/ 3;

    // 匹配分（归一化到 0~1）
    final avgCost = matched > 0 ? totalCost / matched : 1.0;
    final matchScore = math.max(0.0, 1.0 - avgCost * 5).clamp(0.0, 1.0);

    return AlignedStrokes(
      orderedStrokes: orderedStrokes.isEmpty ? candidateStrokes : orderedStrokes,
      matchScore: matchScore,
      reliable: reliable,
    );
  }

  static List<SkeletonStroke> _heuristicOrder(List<SkeletonStroke> strokes) {
    final sorted = List<SkeletonStroke>.from(strokes)
      ..sort((a, b) {
        final ay = a.points.first.y;
        final by_ = b.points.first.y;
        if ((ay - by_).abs() > 0.1) return ay.compareTo(by_);
        return a.points.first.x.compareTo(b.points.first.x);
      });
    return sorted;
  }

  // ─────────────────────────────────────────────────────────────────────
  // 匈牙利算法（Munkres / Hungarian）
  // 针对矩形代价矩阵（n×m, n 可 ≠ m），求最小代价完美匹配
  // 返回 assignment[i] = j（模板 i → 候选 j），-1 表示未匹配
  // ─────────────────────────────────────────────────────────────────────
  static List<int> _hungarian(List<List<double>> cost, int n, int m) {
    // 扩展为方阵（用大值填充）
    final size = math.max(n, m);
    const bigVal = 1e9;

    // 工作矩阵
    final c = List.generate(size, (i) {
      return List.generate(size, (j) {
        if (i < n && j < m) return cost[i][j];
        return bigVal;
      });
    });

    final rowCover = List<bool>.filled(size, false);
    final colCover = List<bool>.filled(size, false);
    final starred = List.generate(size, (_) => List<int>.filled(size, 0));
    // starred[i][j]: 1=starred, 2=primed

    final rowAssign = List<int>.filled(size, -1);
    final colAssign = List<int>.filled(size, -1);

    // Step 1: 行归约
    for (int i = 0; i < size; i++) {
      double minVal = c[i].reduce(math.min);
      for (int j = 0; j < size; j++) {
        c[i][j] -= minVal;
      }
    }

    // Step 2: 列归约
    for (int j = 0; j < size; j++) {
      double minVal = double.infinity;
      for (int i = 0; i < size; i++) {
        minVal = math.min(minVal, c[i][j]);
      }
      for (int i = 0; i < size; i++) {
        c[i][j] -= minVal;
      }
    }

    // Step 3: 星化零元素（每行每列最多一个）
    for (int i = 0; i < size; i++) {
      for (int j = 0; j < size; j++) {
        if (c[i][j] == 0 && rowAssign[i] < 0 && colAssign[j] < 0) {
          starred[i][j] = 1;
          rowAssign[i] = j;
          colAssign[j] = i;
        }
      }
    }

    // 主循环
    for (int iter = 0; iter < size * size; iter++) {
      // 检查是否完成（每列都有 starred 零）
      int coveredCols = 0;
      rowCover.fillRange(0, size, false);
      colCover.fillRange(0, size, false);

      for (int j = 0; j < size; j++) {
        if (colAssign[j] >= 0) {
          colCover[j] = true;
          coveredCols++;
        }
      }
      if (coveredCols >= size) break;

      // 找未覆盖零
      bool found = false;
      outer:
      for (int i = 0; i < size; i++) {
        if (rowCover[i]) continue;
        for (int j = 0; j < size; j++) {
          if (colCover[j]) continue;
          if (c[i][j] == 0) {
            // Prime it
            starred[i][j] = 2;
            // 找同行的 starred 零
            int starCol = -1;
            for (int jj = 0; jj < size; jj++) {
              if (starred[i][jj] == 1) { starCol = jj; break; }
            }
            if (starCol < 0) {
              // 增广路径：将这个 primed 零 starred
              _augment(i, j, starred, size, rowAssign, colAssign);
              // 清除所有 prime
              for (int ii = 0; ii < size; ii++) {
                for (int jj = 0; jj < size; jj++) {
                  if (starred[ii][jj] == 2) starred[ii][jj] = 0;
                }
              }
              found = true;
              break outer;
            } else {
              rowCover[i] = true;
              colCover[starCol] = false;
            }
          }
        }
      }

      if (!found) {
        // 找未覆盖最小值，调整代价矩阵
        double minVal = double.infinity;
        for (int i = 0; i < size; i++) {
          if (rowCover[i]) continue;
          for (int j = 0; j < size; j++) {
            if (colCover[j]) continue;
            if (c[i][j] < minVal) minVal = c[i][j];
          }
        }
        if (minVal == double.infinity) break;
        for (int i = 0; i < size; i++) {
          for (int j = 0; j < size; j++) {
            if (!rowCover[i] && !colCover[j]) c[i][j] -= minVal;
            if (rowCover[i] && colCover[j]) c[i][j] += minVal;
          }
        }
      }
    }

    // 提取结果（仅前 n 行）
    return List.generate(n, (i) {
      final j = rowAssign[i];
      return (j >= 0 && j < m) ? j : -1;
    });
  }

  static void _augment(
    int row, int col,
    List<List<int>> starred,
    int size,
    List<int> rowAssign,
    List<int> colAssign,
  ) {
    // 沿增广路径交替翻转 star/unstar
    int r = row, c = col;
    while (true) {
      starred[r][c] = 1;
      rowAssign[r] = c;
      colAssign[c] = r;

      // 找同列的 starred 零（之前的）
      int prevRow = -1;
      for (int i = 0; i < size; i++) {
        if (i != r && starred[i][c] == 1) { prevRow = i; break; }
      }
      if (prevRow < 0) break;

      // 该行取消 star
      starred[prevRow][c] = 0;
      colAssign[c] = -1;
      rowAssign[prevRow] = -1;

      // 找同行的 primed 零
      int primeCol = -1;
      for (int j = 0; j < size; j++) {
        if (starred[prevRow][j] == 2) { primeCol = j; break; }
      }
      if (primeCol < 0) break;
      r = prevRow;
      c = primeCol;
    }
  }
}
