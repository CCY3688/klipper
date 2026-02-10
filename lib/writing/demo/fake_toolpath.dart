import '../model/essay_grid.dart';
import '../model/geometry.dart';
import '../model/toolpath.dart';

/// 生成一段用于验证渲染效果的“假轨迹”。
///
/// 坐标单位：mm
/// 坐标原点：纸张左上角 (0,0)
///
/// 轨迹特点：
/// - 若干段 penDown 实线笔迹
/// - 若干段 penUp 虚线移动
/// - 尽量落在作文格区域内，便于目测对齐
ToolPath buildFakeEssayToolPath({required EssayGridSpec grid}) {
  final polylines = <ToolPolyline>[];
  final penUpPoints = <Vec2>[];

  Vec2 centerOfCell(int col, int row) {
    final cx = grid.marginLeftMm + (col + 0.5) * grid.cellMm;
    final cy = grid.marginTopMm + (row + 0.5) * grid.cellMm;
    return Vec2(cx, cy);
  }

  // 叉的半径（mm）：控制叉的大小（落在格子内）
  final half = grid.cellMm * 0.28;

  for (int r = 0; r < grid.rows; r++) {
    for (int c = 0; c < grid.cols; c++) {
      final center = centerOfCell(c, r);
      final x = center.x;
      final y = center.y;

      final stroke1Start = Vec2(x - half, y - half);
      final stroke1End = Vec2(x + half, y + half);
      final stroke2Start = Vec2(x - half, y + half);
      final stroke2End = Vec2(x + half, y - half);

      // \ 方向
      polylines.add(
        ToolPolyline(penDown: true, points: [stroke1Start, stroke1End]),
      );

      // 抬笔：从第一笔末端移动到第二笔起点（用于验证 penUp 虚线/淡色）
      penUpPoints.add(stroke1End);
      penUpPoints.add(stroke2Start);

      // / 方向
      polylines.add(
        ToolPolyline(penDown: true, points: [stroke2Start, stroke2End]),
      );

      // 抬笔：从当前格子移动到下一格子的第一笔起点（蛇形遍历，线更连续）
      final isLastCell = r == grid.rows - 1 && c == grid.cols - 1;
      if (!isLastCell) {
        final int nextCol;
        final int nextRow;
        if (c < grid.cols - 1) {
          nextCol = c + 1;
          nextRow = r;
        } else {
          nextCol = 0;
          nextRow = r + 1;
        }

        final target = centerOfCell(nextCol, nextRow);

        // 目标格子的第一笔起点
        final targetStart = Vec2(target.x - half, target.y - half);
        penUpPoints.add(stroke2End);
        penUpPoints.add(targetStart);
      }
    }
  }

  if (penUpPoints.length >= 2) {
    polylines.add(ToolPolyline(penDown: false, points: penUpPoints));
  }

  return ToolPath(polylines: polylines);
}
