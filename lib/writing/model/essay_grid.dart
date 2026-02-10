// import '../model/page.dart';

class EssayGridSpec {
  final double cellMm;         // 格子边长
  final double marginLeftMm;
  final double marginTopMm;
  final int cols;
  final int rows;

  const EssayGridSpec({
    required this.cellMm,
    required this.marginLeftMm,
    required this.marginTopMm,
    required this.cols,
    required this.rows,
  });

  double get gridWidthMm => cols * cellMm;
  double get gridHeightMm => rows * cellMm;
}

EssayGridSpec defaultA4EssayGrid() {
  // A4: 210x297mm
  // 改为 8mm 格子
  // 宽度：25列 * 8 = 200mm (左右边距各5mm)
  // 高度：34行 * 8 = 272mm (上下边距分摊，如顶部12.5mm)
  return const EssayGridSpec(
    cellMm: 8,
    marginLeftMm: 5,
    marginTopMm: 12.5,
    cols: 25,
    rows: 34,
  );
}