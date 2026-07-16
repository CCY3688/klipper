import 'package:flutter_test/flutter_test.dart';
import 'package:klipper/writing/model/paper_type.dart';

void main() {
  test('default A4 grid uses long edge as X axis', () {
    final paper = defaultGridPaper();

    expect(paper.pageWidthMm, 297);
    expect(paper.pageHeightMm, 210);
    expect(paper.cols, 35);
    expect(paper.rows, 23);
  });

  test('legacy portrait A4 config migrates to long-X coordinate system', () {
    final paper = PaperConfig.fromJson({
      'name': 'legacy A4',
      'kind': 'grid',
      'pageWidthMm': 210,
      'pageHeightMm': 297,
      'marginLeftMm': 5,
      'marginTopMm': 12.5,
      'marginRightMm': 5,
      'marginBottomMm': 12.5,
      'cellSizeMm': 8,
      'customCols': 25,
      'customRows': 34,
    });

    expect(paper.pageWidthMm, 297);
    expect(paper.pageHeightMm, 210);
    expect(paper.customCols, isNull);
    expect(paper.customRows, isNull);
    expect(paper.cols, 35);
    expect(paper.rows, 23);
  });
}
