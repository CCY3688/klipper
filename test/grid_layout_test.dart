import 'package:flutter_test/flutter_test.dart';
import 'package:klipper/writing/font/stroke_font.dart';
import 'package:klipper/writing/layout/grid_layout.dart';
import 'package:klipper/writing/model/essay_grid.dart';
import 'package:klipper/writing/model/geometry.dart';

void main() {
  final font = StrokeFont({
    for (final ch in ['A', 'B', 'C', 'D'])
      ch: const StrokeGlyph([
        [Vec2(0, 0), Vec2(1, 0)],
      ]),
  });

  const grid = EssayGridSpec(
    cellMm: 10,
    marginLeftMm: 0,
    marginTopMm: 0,
    cols: 2,
    rows: 2,
  );

  test('horizontal layout advances along X before wrapping to Y', () {
    final path = GridLayout(
      grid: grid,
      font: font,
      options: const GridLayoutOptions(cellPaddingMm: 0),
    ).layoutText('ABCD');

    final drawn = path.polylines.where((p) => p.penDown).toList();

    expect(drawn[0].points.first, const Vec2(0, 0));
    expect(drawn[1].points.first, const Vec2(10, 0));
  });

  test('verticalFirst layout advances along Y before wrapping to X', () {
    final path = GridLayout(
      grid: grid,
      font: font,
      options: const GridLayoutOptions(cellPaddingMm: 0, verticalFirst: true),
    ).layoutText('ABCD');

    final drawn = path.polylines.where((p) => p.penDown).toList();

    expect(drawn[0].points.first, const Vec2(0, 0));
    expect(drawn[1].points.first, const Vec2(0, 10));
  });
}
