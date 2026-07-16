import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:klipper/ui/surface/stl_mesh.dart';
import 'package:klipper/ui/surface/surface_registration.dart';
import 'package:klipper/ui/surface/surface_scan_models.dart';

void main() {
  test('registers STL model points to scan points with a known transform', () {
    final mesh = _testMesh();
    const trueTranslation = StlVector3(12.5, -7.25, 3.2);
    const yaw = math.pi / 8;
    final trueTransform = Transform3D.centeredYaw(
      sourceCenter: const StlVector3(0, 0, 0),
      targetCenter: trueTranslation,
      yaw: yaw,
    );
    final scan = _scanFromMesh(mesh, trueTransform);

    final result = const SurfaceRegistrationService().register(
      mesh: mesh,
      scan: scan,
      options: SurfaceRegistrationOptions(
        rmseThresholdMm: 0.05,
        yawSearchSteps: 32,
        maxPairDistanceMm: 6,
      ),
    );

    expect(result.passed, isTrue);
    expect(result.rmse, lessThan(0.05));
    for (final triangle in mesh.triangles) {
      final actual = result.transform.transformPoint(triangle.center);
      final expected = trueTransform.transformPoint(triangle.center);
      expect((actual - expected).length, lessThan(0.08));
    }
  });

  test('locked registration only applies yaw and translation', () {
    final mesh = _slopedSurfaceMesh();
    final trueTransform = Transform3D.fromRotationAndTranslation([
      1,
      0,
      0,
      0,
      0,
      -1,
      0,
      1,
      0,
    ], const StlVector3(18, -6, 12));
    final scan = _scanFromMesh(mesh, trueTransform);

    final result = const SurfaceRegistrationService().register(
      mesh: mesh,
      scan: scan,
      options: SurfaceRegistrationOptions(
        lockModelOrientation: true,
        maxPairDistanceMm: 80,
      ),
    );

    expect(result.transform.values[2], closeTo(0, 1e-9));
    expect(result.transform.values[6], closeTo(0, 1e-9));
    expect(result.transform.values[8], closeTo(0, 1e-9));
    expect(result.transform.values[9], closeTo(0, 1e-9));
    expect(result.transform.values[10], closeTo(1, 1e-9));
  });
}

StlMesh _testMesh() {
  const z = 0.0;
  final triangles = <StlTriangle>[];
  for (var x = 0; x < 5; x++) {
    for (var y = 0; y < 3; y++) {
      if (x == 4 && y == 2) continue;
      final x0 = (x * 8).toDouble();
      final y0 = (y * 7).toDouble();
      final x1 = x0 + 8;
      final y1 = y0 + 7;
      triangles.add(
        _triangle(
          StlVector3(x0, y0, z),
          StlVector3(x1, y0, z),
          StlVector3(x0, y1, z),
        ),
      );
      triangles.add(
        _triangle(
          StlVector3(x1, y0, z),
          StlVector3(x1, y1, z),
          StlVector3(x0, y1, z),
        ),
      );
    }
  }
  return StlMesh(
    name: 'test.stl',
    triangles: triangles,
    bounds: StlBounds.fromTriangles(triangles),
  );
}

StlMesh _slopedSurfaceMesh() {
  final triangles = <StlTriangle>[];
  for (var x = 0; x < 5; x++) {
    for (var y = 0; y < 4; y++) {
      final x0 = (x * 6).toDouble();
      final y0 = (y * 5).toDouble();
      final x1 = x0 + 6;
      final y1 = y0 + 5;
      final p00 = StlVector3(x0, y0, _surfaceZ(x0, y0));
      final p10 = StlVector3(x1, y0, _surfaceZ(x1, y0));
      final p01 = StlVector3(x0, y1, _surfaceZ(x0, y1));
      final p11 = StlVector3(x1, y1, _surfaceZ(x1, y1));
      triangles.add(_triangle(p00, p10, p01));
      triangles.add(_triangle(p10, p11, p01));
    }
  }
  return StlMesh(
    name: 'sloped.stl',
    triangles: triangles,
    bounds: StlBounds.fromTriangles(triangles),
  );
}

double _surfaceZ(double x, double y) {
  return 0.2 * x + 0.05 * y + math.sin(x * 0.3) * 0.4;
}

StlTriangle _triangle(StlVector3 a, StlVector3 b, StlVector3 c) {
  return StlTriangle(
    a: a,
    b: b,
    c: c,
    normal: StlTriangle.computedNormal(a, b, c),
  );
}

SurfaceScanResult _scanFromMesh(StlMesh mesh, Transform3D transform) {
  final points = <SurfaceScanPoint>[];
  for (final triangle in mesh.triangles) {
    final point = transform.transformPoint(triangle.center);
    points.add(
      SurfaceScanPoint(
        index: points.length,
        x: point.x,
        y: point.y,
        z: point.z,
        distanceMm: null,
        rawMm: null,
        status: null,
        sigma: null,
        valid: true,
        error: null,
      ),
    );
  }

  final zValues = points.map((p) => p.z!).toList(growable: false);
  final zMin = zValues.reduce(math.min);
  final zMax = zValues.reduce(math.max);
  return SurfaceScanResult(
    profile: 'known-transform',
    sensor: 'test',
    createdAt: '',
    spacing: null,
    scanZ: null,
    summary: SurfaceScanSummary(
      pointCount: points.length,
      validCount: points.length,
      invalidCount: 0,
      zMin: zMin,
      zMax: zMax,
      zRange: zMax - zMin,
    ),
    grid: const SurfaceScanGrid(xCount: 0, yCount: 0, xPoints: [], yPoints: []),
    points: points,
    invalidPoints: const [],
    csvPath: null,
    jsonPath: null,
  );
}
