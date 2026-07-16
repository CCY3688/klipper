// import '../model/page.dart';

class EssayGridSpec {
  final double cellMm; // 格子边长
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
  // A4: 297x210mm, long edge on X.
  // 8mm grid: 35 columns and 23 rows fit inside the default margins.
  return const EssayGridSpec(
    cellMm: 8,
    marginLeftMm: 5,
    marginTopMm: 12.5,
    cols: 35,
    rows: 23,
  );
}
