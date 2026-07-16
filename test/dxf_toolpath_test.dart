import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klipper/ui/surface/dxf_toolpath.dart';

void main() {
  test('parses repository DXF sample into toolpath polylines', () {
    final file = File(
      'host/AprilTag-tag36h11-ID0_closed_white_regions_20mm.dxf',
    );
    final toolpath = DxfParser.parse(file.readAsStringSync(), name: file.path);

    expect(toolpath.isEmpty, isFalse);
    expect(toolpath.polylines.length, greaterThan(1));
    expect(toolpath.pointCount, greaterThan(10));
    expect(toolpath.widthMm, greaterThan(0));
    expect(toolpath.heightMm, greaterThan(0));
  });

  test('parses common DXF entities used for drawing trajectories', () {
    const dxf = '''
0
SECTION
2
ENTITIES
0
LINE
8
LINES
10
0
20
0
11
10
21
0
0
ARC
8
ARCS
10
20
20
20
40
5
50
0
51
90
0
CIRCLE
8
CIRCLES
10
40
20
40
40
2
0
LWPOLYLINE
8
POLYS
70
1
10
0
20
0
10
5
20
0
42
0.4
10
5
20
5
0
ENDSEC
0
EOF
''';

    final toolpath = DxfParser.parse(dxf, name: 'inline.dxf');

    expect(toolpath.polylines.length, 4);
    expect(toolpath.layers, containsAll(['LINES', 'ARCS', 'CIRCLES', 'POLYS']));
    expect(toolpath.pointCount, greaterThan(12));
    expect(toolpath.unsupportedEntities, isEmpty);
  });
}
