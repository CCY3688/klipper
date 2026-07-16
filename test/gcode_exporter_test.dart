import 'package:flutter_test/flutter_test.dart';
import 'package:klipper/writing/export/gcode_exporter.dart';
import 'package:klipper/writing/export/visual_compensation.dart';
import 'package:klipper/writing/model/geometry.dart';
import 'package:klipper/writing/model/toolpath.dart';

void main() {
  test('emits explicit start point and fixed Z for macro pen mode', () {
    final toolPath = ToolPath(
      polylines: [
        ToolPolyline(penDown: true, points: [Vec2(0, 0), Vec2(10, 0)]),
      ],
    );

    final gcode = GcodeExporter().export(
      toolPath,
      startPointOffset: const Offset(-20, -20),
      startPointZ: 50,
    );

    expect(gcode, contains('G0 X-20.000 Y-20.000 Z50.000 F4800'));
    expect(gcode, contains('G1 X-10.000 Y-20.000 Z50.000 F1500'));
  });

  test('emits configured writing feedrate', () {
    final toolPath = ToolPath(
      polylines: [
        ToolPolyline(penDown: true, points: [Vec2(0, 0), Vec2(10, 0)]),
      ],
    );

    final gcode = GcodeExporter().export(
      toolPath,
      opt: const GcodeExportOptions(writeSpeedMmPerS: 12.5),
    );

    expect(gcode, contains('; WriteSpeed: 12.5 mm/s'));
    expect(gcode, contains('G1 X10.000 Y0.000 Z0.000 F750'));
  });

  test('anchors mirrored path at custom start point', () {
    final toolPath = ToolPath(
      polylines: [
        ToolPolyline(penDown: true, points: [Vec2(0, 10), Vec2(10, 20)]),
      ],
    );

    final gcode = GcodeExporter().export(
      toolPath,
      opt: const GcodeExportOptions(mirrorY: true, pageHeightMm: 100),
      startPointOffset: const Offset(-20, -20),
      startPointZ: 50,
    );

    expect(gcode, contains('G0 X-20.000 Y-20.000 Z50.000 F4800'));
    expect(gcode, contains('G1 X-10.000 Y-30.000 Z50.000 F1500'));
    expect(gcode, isNot(contains('Y70.000')));
  });

  test('custom start point prevents full-page Y jump after mirroring', () {
    final toolPath = ToolPath(
      polylines: [
        ToolPolyline(
          penDown: true,
          points: [Vec2(6.793, 17.5), Vec2(13.528, 14.934)],
        ),
      ],
    );

    final gcode = GcodeExporter().export(
      toolPath,
      opt: const GcodeExportOptions(mirrorY: true, pageHeightMm: 210),
      startPointOffset: const Offset(-100, -60),
      startPointZ: 50,
    );

    expect(gcode, contains('G0 X-100.000 Y-60.000 Z50.000 F4800'));
    expect(gcode, contains('G1 X-93.265 Y-57.434 Z50.000 F1500'));
    expect(gcode, isNot(contains('Y132.500')));
  });

  test('custom start point preserves positive paper Y direction', () {
    final toolPath = ToolPath(
      polylines: [
        ToolPolyline(penDown: true, points: [Vec2(0, 0), Vec2(0, 10)]),
      ],
    );

    final gcode = GcodeExporter().export(
      toolPath,
      opt: const GcodeExportOptions(pageHeightMm: 210),
      startPointOffset: const Offset(-100, -60),
      startPointZ: 50,
    );

    expect(gcode, contains('G0 X-100.000 Y-60.000 Z50.000 F4800'));
    expect(gcode, contains('G1 X-100.000 Y-50.000 Z50.000 F1500'));
    expect(gcode, isNot(contains('Y-70.000')));
  });

  test('emits Klipper output pin commands for laser intensity', () {
    final toolPath = ToolPath(
      polylines: [
        ToolPolyline(penDown: true, points: [Vec2(0, 0), Vec2(10, 0)]),
      ],
    );

    final gcode = GcodeExporter().export(
      toolPath,
      opt: const GcodeExportOptions(
        penUpCmd: 'SET_PIN PIN=laser VALUE=0.000',
        penDownCmd: 'SET_PIN PIN=laser VALUE=0.300',
      ),
    );

    expect(gcode, contains('SET_PIN PIN=laser VALUE=0.000'));
    expect(gcode, contains('SET_PIN PIN=laser VALUE=0.300'));
    expect(gcode, isNot(contains('M3')));
    expect(gcode, isNot(contains('M5')));
  });

  test('uses default Z without emitting an origin start move', () {
    final toolPath = ToolPath(
      polylines: [
        ToolPolyline(penDown: true, points: [Vec2(2, 3), Vec2(4, 5)]),
      ],
    );

    final gcode = GcodeExporter().export(
      toolPath,
      opt: const GcodeExportOptions(defaultZMm: 50),
    );

    expect(gcode, contains('G0 X2.000 Y3.000 Z50.000 F4800'));
    expect(gcode, contains('G1 X4.000 Y5.000 Z50.000 F1500'));
    expect(gcode, isNot(contains('G0 X0.000 Y0.000 Z50.000')));
  });

  test('applies visual compensation to anchored machine commands', () async {
    final visualCompensation = await VisualCompensationTransform.tryLoad();
    expect(visualCompensation, isNotNull);
    final compensation = visualCompensation!;

    final toolPath = ToolPath(
      polylines: [
        ToolPolyline(penDown: true, points: [Vec2(0, 0), Vec2(10, 0)]),
      ],
    );

    final gcode = GcodeExporter().export(
      toolPath,
      opt: GcodeExportOptions(defaultZMm: 50, visualCompensation: compensation),
      startPointOffset: const Offset(-100, -60),
      startPointZ: 50,
    );

    final startX = (-100 + compensation.dxMm).toStringAsFixed(3);
    final startY = (-60 + compensation.dyMm).toStringAsFixed(3);
    final nextX = (-90 + compensation.dxMm).toStringAsFixed(3);

    expect(gcode, contains('; VisualCompensation: enabled'));
    expect(gcode, contains('G0 X$startX Y$startY Z50.000 F4800'));
    expect(gcode, contains('G1 X$nextX Y$startY Z50.000 F1500'));
    expect(gcode, isNot(contains('X128.026 Y-99.365')));
  });

  test('requires page height when Y mirroring is enabled', () {
    final toolPath = ToolPath(
      polylines: [
        ToolPolyline(penDown: true, points: [Vec2(0, 0), Vec2(10, 0)]),
      ],
    );

    expect(
      () => GcodeExporter().export(
        toolPath,
        opt: const GcodeExportOptions(mirrorY: true),
      ),
      throwsArgumentError,
    );
  });
}
