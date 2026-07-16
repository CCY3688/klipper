import 'package:flutter_test/flutter_test.dart';
import 'package:klipper/ui/surface/dxf_toolpath.dart';
import 'package:klipper/writing/engraving/dxf_engraver.dart';

void main() {
  test('scales dxf polylines into engraving toolpath area', () {
    final dxf = DxfToolpath(
      name: 'inline.dxf',
      polylines: [
        DxfPolyline(
          points: const [Offset(0, 0), Offset(10, 0), Offset(10, 5)],
          closed: false,
          layer: 'CUT',
          entityType: 'LWPOLYLINE',
        ),
      ],
      unsupportedEntities: const [],
      parsedEntityCount: 1,
    );

    final path = DxfEngraver.buildToolPath(
      dxf,
      options: const DxfEngraveOptions(
        originXmm: 20,
        originYmm: 30,
        widthMm: 100,
        heightMm: 50,
      ),
    );

    expect(path.polylines, hasLength(1));
    expect(path.polylines.single.penDown, isTrue);
    expect(path.polylines.single.points.first.x, 20);
    expect(path.polylines.single.points.first.y, 30);
    expect(path.polylines.single.points.last.x, 120);
    expect(path.polylines.single.points.last.y, 80);
  });

  test('applies dxf rotation and translation to toolpath', () {
    final dxf = DxfToolpath(
      name: 'line.dxf',
      polylines: [
        DxfPolyline(
          points: const [Offset(0, 0), Offset(10, 0)],
          closed: false,
          layer: 'CUT',
          entityType: 'LINE',
        ),
      ],
      unsupportedEntities: const [],
      parsedEntityCount: 1,
    );

    final path = DxfEngraver.buildToolPath(
      dxf,
      options: const DxfEngraveOptions(
        originXmm: 0,
        originYmm: 0,
        widthMm: 10,
        heightMm: 10,
        rotationDeg: 90,
        translateXmm: 5,
        translateYmm: -2,
      ),
    );

    expect(path.polylines, hasLength(1));
    expect(path.polylines.single.points.first.x, closeTo(10, 0.001));
    expect(path.polylines.single.points.first.y, closeTo(-2, 0.001));
    expect(path.polylines.single.points.last.x, closeTo(10, 0.001));
    expect(path.polylines.single.points.last.y, closeTo(8, 0.001));
  });

  test('mirrors dxf horizontally around its engraving center', () {
    final dxf = DxfToolpath(
      name: 'mirror.dxf',
      polylines: [
        DxfPolyline(
          points: const [Offset(0, 0), Offset(10, 0), Offset(10, 5)],
          closed: false,
          layer: 'CUT',
          entityType: 'LWPOLYLINE',
        ),
      ],
      unsupportedEntities: const [],
      parsedEntityCount: 1,
    );

    final path = DxfEngraver.buildToolPath(
      dxf,
      options: const DxfEngraveOptions(
        originXmm: 20,
        originYmm: 30,
        widthMm: 100,
        heightMm: 50,
        mirrorX: true,
      ),
    );

    final points = path.polylines.single.points;
    expect(points[0].x, closeTo(120, 0.001));
    expect(points[0].y, closeTo(30, 0.001));
    expect(points[1].x, closeTo(20, 0.001));
    expect(points[1].y, closeTo(30, 0.001));
    expect(points[2].x, closeTo(20, 0.001));
    expect(points[2].y, closeTo(80, 0.001));
  });
}
