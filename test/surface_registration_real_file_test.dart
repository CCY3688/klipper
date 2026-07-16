import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klipper/ui/surface/stl_parser.dart';
import 'package:klipper/ui/surface/surface_registration.dart';
import 'package:klipper/ui/surface/surface_scan_models.dart';

void main() {
  test('diagnoses bundled wing STL and plane scan registration', () {
    final stlFile = Directory.current
        .listSync()
        .whereType<File>()
        .firstWhere((file) => file.path.toLowerCase().endsWith('.stl'));
    final scanFile = File('plane_test.json');
    if (!scanFile.existsSync()) {
      return;
    }

    final mesh = StlParser.parse(
      stlFile.readAsBytesSync(),
      name: stlFile.uri.pathSegments.last,
    );
    final scan = SurfaceScanResult.fromJson(
      jsonDecode(scanFile.readAsStringSync()) as Map<String, dynamic>,
    );
    final result = const SurfaceRegistrationService().register(
      mesh: mesh,
      scan: scan,
    );

    expect(result.diagnostics.modelSampleCount, greaterThanOrEqualTo(3));
    expect(result.diagnostics.scanSampleCount, greaterThanOrEqualTo(3));
    expect(result.diagnostics.ungatedNearestMinMm.isFinite, isTrue);
    expect(result.matchedPairs, greaterThanOrEqualTo(3));
  });
}
