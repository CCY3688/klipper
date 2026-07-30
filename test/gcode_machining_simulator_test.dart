import 'package:flutter_test/flutter_test.dart';
import 'package:klipper/simulation/delta_kinematics.dart';
import 'package:klipper/simulation/gcode_machining_simulator.dart';
import 'package:klipper/ui/surface/stl_mesh.dart';

void main() {
  test('parses absolute and relative moves with tool state', () {
    final program = GcodeSimulationProgram.parse('''
G90
G0 X0 Y0 Z20
M3
G1 X10 F600
G91
G1 Y5
M5
G1 X2
''');

    expect(program.moves, hasLength(4));
    expect(program.moves[1].processing, isTrue);
    expect(program.moves[2].end.y, 5);
    expect(program.moves[3].processing, isFalse);
  });

  test('reports an STL face contacted by a processing sweep', () {
    final mesh = StlMesh(
      name: 'test',
      triangles: [
        StlTriangle(
          a: const StlVector3(0, -1, 0),
          b: const StlVector3(10, -1, 0),
          c: const StlVector3(5, 1, 0),
          normal: const StlVector3(0, 0, 1),
        ),
      ],
      bounds: const StlBounds(
        minX: 0,
        maxX: 10,
        minY: -1,
        maxY: 1,
        minZ: 0,
        maxZ: 0,
      ),
    );
    final result = GcodeMachiningSimulator().run(
      gcode: 'G1 X10 Y0 Z0 F600',
      mesh: mesh,
      options: const MachiningSimulationOptions(toolRadiusMm: 1.1),
    );

    expect(result.hasMeshContact, isTrue);
    expect(result.faceCoverage, 1);
  });

  test('delta inverse kinematics rejects a clearly impossible point', () {
    const kinematics = DeltaKinematics(DeltaGeometry());
    expect(kinematics.inverse(2000, 0, 0).isReachable, isFalse);
  });

  test(
    'bed-face placement aligns every selected face to the requested bed',
    () {
      final mesh = StlMesh(
        name: 'asymmetric block',
        triangles: const [],
        bounds: const StlBounds(
          minX: -10,
          maxX: 20,
          minY: -4,
          maxY: 8,
          minZ: 2,
          maxZ: 9,
        ),
      );
      for (final face in WorkpieceBedFace.values) {
        final transform = WorkpieceTransform.fromMesh(
          mesh,
          WorkpiecePlacement(
            bedFace: face,
            centerXmm: 35,
            centerYmm: -12,
            bedZmm: 4.5,
            yawDeg: 23,
          ),
        );
        final bounds = transform.transformedBounds;
        expect(bounds.minZ, closeTo(4.5, 1e-9), reason: face.label);
        expect((bounds.minX + bounds.maxX) / 2, closeTo(35, 1e-9));
        expect((bounds.minY + bounds.maxY) / 2, closeTo(-12, 1e-9));
      }
    },
  );
}
