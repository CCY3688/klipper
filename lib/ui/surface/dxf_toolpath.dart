import 'dart:math' as math;

import 'package:flutter/material.dart' show Offset, Rect;

class DxfToolpath {
  final String name;
  final List<DxfPolyline> polylines;
  final Set<String> unsupportedEntities;
  final int parsedEntityCount;

  DxfToolpath({
    required this.name,
    required Iterable<DxfPolyline> polylines,
    required Iterable<String> unsupportedEntities,
    required this.parsedEntityCount,
  }) : polylines = List.unmodifiable(
         polylines.where((polyline) => polyline.points.length >= 2),
       ),
       unsupportedEntities = Set.unmodifiable(unsupportedEntities);

  bool get isEmpty => polylines.isEmpty;

  int get pointCount =>
      polylines.fold<int>(0, (sum, polyline) => sum + polyline.points.length);

  double get totalLengthMm =>
      polylines.fold<double>(0, (sum, polyline) => sum + polyline.lengthMm);

  Rect get bounds {
    var hasPoint = false;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final polyline in polylines) {
      for (final point in polyline.points) {
        hasPoint = true;
        minX = math.min(minX, point.dx);
        minY = math.min(minY, point.dy);
        maxX = math.max(maxX, point.dx);
        maxY = math.max(maxY, point.dy);
      }
    }
    if (!hasPoint) return Rect.zero;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  double get widthMm => bounds.width;
  double get heightMm => bounds.height;

  List<String> get layers {
    final values = <String>{};
    for (final polyline in polylines) {
      if (polyline.layer.isNotEmpty) values.add(polyline.layer);
    }
    final sorted = values.toList()..sort();
    return List.unmodifiable(sorted);
  }

  List<List<Offset>> transformedPolylines({
    required double widthMm,
    required double heightMm,
    required Offset center,
    required double rotationDeg,
    required bool keepAspectRatio,
    bool mirrorX = false,
    bool mirrorY = false,
  }) {
    if (polylines.isEmpty) return const [];
    final sourceBounds = bounds;
    final sourceCenter = sourceBounds.center;
    final sourceWidth = math.max(sourceBounds.width.abs(), 1e-6);
    final sourceHeight = math.max(sourceBounds.height.abs(), 1e-6);
    var scaleX = widthMm / sourceWidth;
    var scaleY = heightMm / sourceHeight;
    if (!scaleX.isFinite || scaleX <= 0) scaleX = 1;
    if (!scaleY.isFinite || scaleY <= 0) scaleY = scaleX;
    if (keepAspectRatio) {
      final scale = math.min(scaleX, scaleY);
      scaleX = scale;
      scaleY = scale;
    }

    return polylines
        .map(
          (polyline) => polyline.points
              .map((point) {
                final scaled = Offset(
                  (point.dx - sourceCenter.dx) * scaleX * (mirrorX ? -1 : 1),
                  (point.dy - sourceCenter.dy) * scaleY * (mirrorY ? -1 : 1),
                );
                return _rotateOffsetForDxf(scaled, rotationDeg) + center;
              })
              .toList(growable: false),
        )
        .where((polyline) => polyline.length >= 2)
        .toList(growable: false);
  }
}

class DxfPolyline {
  final List<Offset> points;
  final bool closed;
  final String layer;
  final String entityType;

  DxfPolyline({
    required Iterable<Offset> points,
    required this.closed,
    required this.layer,
    required this.entityType,
  }) : points = List.unmodifiable(_removeDuplicatePoints(points));

  double get lengthMm {
    var length = 0.0;
    for (var i = 1; i < points.length; i++) {
      length += (points[i] - points[i - 1]).distance;
    }
    return length;
  }
}

class DxfParser {
  static DxfToolpath parse(
    String text, {
    String name = 'DXF',
    double arcSegmentMm = 0.5,
  }) {
    final pairs = _readPairs(text);
    final records = _entityRecords(pairs);
    final polylines = <DxfPolyline>[];
    final unsupported = <String>{};
    var parsedEntityCount = 0;

    for (var index = 0; index < records.length; index++) {
      final record = records[index];
      switch (record.type) {
        case 'LINE':
          final polyline = _parseLine(record);
          if (polyline == null) {
            unsupported.add('LINE(incomplete)');
          } else {
            polylines.add(polyline);
            parsedEntityCount++;
          }
          break;
        case 'LWPOLYLINE':
          final polyline = _parseLwPolyline(record, arcSegmentMm);
          if (polyline == null) {
            unsupported.add('LWPOLYLINE(incomplete)');
          } else {
            polylines.add(polyline);
            parsedEntityCount++;
          }
          break;
        case 'POLYLINE':
          final result = _parsePolyline(records, index, arcSegmentMm);
          if (result.polyline == null) {
            unsupported.add('POLYLINE(incomplete)');
          } else {
            polylines.add(result.polyline!);
            parsedEntityCount++;
          }
          index = result.nextIndex;
          break;
        case 'ARC':
          final polyline = _parseArc(record, arcSegmentMm);
          if (polyline == null) {
            unsupported.add('ARC(incomplete)');
          } else {
            polylines.add(polyline);
            parsedEntityCount++;
          }
          break;
        case 'CIRCLE':
          final polyline = _parseCircle(record, arcSegmentMm);
          if (polyline == null) {
            unsupported.add('CIRCLE(incomplete)');
          } else {
            polylines.add(polyline);
            parsedEntityCount++;
          }
          break;
        case 'VERTEX':
        case 'SEQEND':
          break;
        default:
          unsupported.add(record.type);
      }
    }

    return DxfToolpath(
      name: name,
      polylines: polylines,
      unsupportedEntities: unsupported,
      parsedEntityCount: parsedEntityCount,
    );
  }

  static List<_DxfPair> _readPairs(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    final pairs = <_DxfPair>[];
    for (var index = 0; index + 1 < lines.length; index += 2) {
      final code = int.tryParse(lines[index].trim());
      if (code == null) continue;
      pairs.add(_DxfPair(code, lines[index + 1].trim()));
    }
    return pairs;
  }

  static List<_DxfRecord> _entityRecords(List<_DxfPair> pairs) {
    final records = <_DxfRecord>[];
    var inEntities = false;
    String? currentType;
    var currentPairs = <_DxfPair>[];

    void flush() {
      final type = currentType;
      if (type == null) return;
      records.add(_DxfRecord(type, currentPairs));
      currentType = null;
      currentPairs = <_DxfPair>[];
    }

    for (var index = 0; index < pairs.length; index++) {
      final pair = pairs[index];
      final value = pair.value.toUpperCase();
      if (pair.code == 0 &&
          value == 'SECTION' &&
          index + 1 < pairs.length &&
          pairs[index + 1].code == 2 &&
          pairs[index + 1].value.toUpperCase() == 'ENTITIES') {
        inEntities = true;
        currentType = null;
        currentPairs = <_DxfPair>[];
        index++;
        continue;
      }
      if (!inEntities) continue;

      if (pair.code == 0) {
        if (value == 'ENDSEC' || value == 'EOF') {
          flush();
          inEntities = false;
          continue;
        }
        flush();
        currentType = value;
        currentPairs = <_DxfPair>[];
      } else if (currentType != null) {
        currentPairs.add(pair);
      }
    }
    flush();
    return records;
  }

  static DxfPolyline? _parseLine(_DxfRecord record) {
    final x0 = _firstDouble(record, 10);
    final y0 = _firstDouble(record, 20);
    final x1 = _firstDouble(record, 11);
    final y1 = _firstDouble(record, 21);
    if (x0 == null || y0 == null || x1 == null || y1 == null) return null;
    return DxfPolyline(
      points: [Offset(x0, y0), Offset(x1, y1)],
      closed: false,
      layer: _layer(record),
      entityType: record.type,
    );
  }

  static DxfPolyline? _parseLwPolyline(_DxfRecord record, double arcSegmentMm) {
    final vertices = <_DxfVertex>[];
    double? x;
    double? y;
    var bulge = 0.0;

    void flushVertex() {
      if (x == null || y == null) return;
      vertices.add(_DxfVertex(Offset(x!, y!), bulge));
      x = null;
      y = null;
      bulge = 0.0;
    }

    for (final pair in record.pairs) {
      switch (pair.code) {
        case 10:
          flushVertex();
          x = double.tryParse(pair.value);
          break;
        case 20:
          y = double.tryParse(pair.value);
          break;
        case 42:
          bulge = double.tryParse(pair.value) ?? 0.0;
          break;
      }
    }
    flushVertex();
    if (vertices.length < 2) return null;
    return _buildPolyline(
      vertices: vertices,
      closed: (_firstInt(record, 70) ?? 0) & 1 == 1,
      layer: _layer(record),
      entityType: record.type,
      arcSegmentMm: arcSegmentMm,
    );
  }

  static _PolylineParseResult _parsePolyline(
    List<_DxfRecord> records,
    int startIndex,
    double arcSegmentMm,
  ) {
    final record = records[startIndex];
    final vertices = <_DxfVertex>[];
    var nextIndex = startIndex;
    for (var index = startIndex + 1; index < records.length; index++) {
      final child = records[index];
      nextIndex = index;
      if (child.type == 'SEQEND') break;
      if (child.type != 'VERTEX') continue;
      final x = _firstDouble(child, 10);
      final y = _firstDouble(child, 20);
      if (x == null || y == null) continue;
      vertices.add(_DxfVertex(Offset(x, y), _firstDouble(child, 42) ?? 0.0));
    }
    if (vertices.length < 2) {
      return _PolylineParseResult(polyline: null, nextIndex: nextIndex);
    }
    return _PolylineParseResult(
      polyline: _buildPolyline(
        vertices: vertices,
        closed: (_firstInt(record, 70) ?? 0) & 1 == 1,
        layer: _layer(record),
        entityType: record.type,
        arcSegmentMm: arcSegmentMm,
      ),
      nextIndex: nextIndex,
    );
  }

  static DxfPolyline? _parseArc(_DxfRecord record, double arcSegmentMm) {
    final cx = _firstDouble(record, 10);
    final cy = _firstDouble(record, 20);
    final radius = _firstDouble(record, 40);
    final startDeg = _firstDouble(record, 50);
    final endDeg = _firstDouble(record, 51);
    if (cx == null ||
        cy == null ||
        radius == null ||
        startDeg == null ||
        endDeg == null ||
        radius <= 0) {
      return null;
    }
    final points = _sampleArc(
      center: Offset(cx, cy),
      radius: radius,
      startRadians: _degreesToRadians(startDeg),
      endRadians: _degreesToRadians(endDeg),
      arcSegmentMm: arcSegmentMm,
    );
    return DxfPolyline(
      points: points,
      closed: false,
      layer: _layer(record),
      entityType: record.type,
    );
  }

  static DxfPolyline? _parseCircle(_DxfRecord record, double arcSegmentMm) {
    final cx = _firstDouble(record, 10);
    final cy = _firstDouble(record, 20);
    final radius = _firstDouble(record, 40);
    if (cx == null || cy == null || radius == null || radius <= 0) {
      return null;
    }
    final points = _sampleArc(
      center: Offset(cx, cy),
      radius: radius,
      startRadians: 0,
      endRadians: math.pi * 2,
      arcSegmentMm: arcSegmentMm,
    );
    return DxfPolyline(
      points: [...points, points.first],
      closed: true,
      layer: _layer(record),
      entityType: record.type,
    );
  }

  static DxfPolyline _buildPolyline({
    required List<_DxfVertex> vertices,
    required bool closed,
    required String layer,
    required String entityType,
    required double arcSegmentMm,
  }) {
    final points = <Offset>[vertices.first.point];
    final segmentCount = closed ? vertices.length : vertices.length - 1;
    for (var index = 0; index < segmentCount; index++) {
      final current = vertices[index];
      final next = vertices[(index + 1) % vertices.length];
      _appendSegment(
        points,
        current.point,
        next.point,
        current.bulge,
        arcSegmentMm,
      );
    }
    if (closed && (points.last - points.first).distance > 1e-6) {
      points.add(points.first);
    }
    return DxfPolyline(
      points: points,
      closed: closed,
      layer: layer,
      entityType: entityType,
    );
  }

  static void _appendSegment(
    List<Offset> output,
    Offset start,
    Offset end,
    double bulge,
    double arcSegmentMm,
  ) {
    final chord = end - start;
    final chordLength = chord.distance;
    if (chordLength <= 1e-9) return;
    if (bulge.abs() <= 1e-9) {
      _appendPoint(output, end);
      return;
    }

    final normal = Offset(-chord.dy / chordLength, chord.dx / chordLength);
    final sagitta = bulge * chordLength / 2;
    final count = math.max(
      2,
      (chordLength * (1 + bulge.abs() * 2) / math.max(0.05, arcSegmentMm))
          .ceil(),
    );
    for (var step = 1; step <= count; step++) {
      final t = step / count;
      final base = start + chord * t;
      final arcOffset = normal * (4 * sagitta * t * (1 - t));
      _appendPoint(output, base + arcOffset);
    }
  }

  static void _appendPoint(List<Offset> output, Offset point) {
    if (output.isNotEmpty && (output.last - point).distance <= 1e-6) return;
    output.add(point);
  }

  static List<Offset> _sampleArc({
    required Offset center,
    required double radius,
    required double startRadians,
    required double endRadians,
    required double arcSegmentMm,
  }) {
    var sweep = endRadians - startRadians;
    while (sweep <= 0) {
      sweep += math.pi * 2;
    }
    final count = math.max(
      1,
      (sweep.abs() * radius / math.max(0.05, arcSegmentMm)).ceil(),
    );
    return List.generate(count + 1, (index) {
      final t = index / count;
      final angle = startRadians + sweep * t;
      return center + Offset(math.cos(angle), math.sin(angle)) * radius;
    }, growable: false);
  }

  static double? _firstDouble(_DxfRecord record, int code) {
    for (final pair in record.pairs) {
      if (pair.code == code) return double.tryParse(pair.value);
    }
    return null;
  }

  static int? _firstInt(_DxfRecord record, int code) {
    for (final pair in record.pairs) {
      if (pair.code == code) return int.tryParse(pair.value);
    }
    return null;
  }

  static String _layer(_DxfRecord record) {
    for (final pair in record.pairs) {
      if (pair.code == 8) return pair.value;
    }
    return '';
  }
}

class _DxfPair {
  final int code;
  final String value;

  const _DxfPair(this.code, this.value);
}

class _DxfRecord {
  final String type;
  final List<_DxfPair> pairs;

  const _DxfRecord(this.type, this.pairs);
}

class _DxfVertex {
  final Offset point;
  final double bulge;

  const _DxfVertex(this.point, this.bulge);
}

class _PolylineParseResult {
  final DxfPolyline? polyline;
  final int nextIndex;

  const _PolylineParseResult({required this.polyline, required this.nextIndex});
}

List<Offset> _removeDuplicatePoints(Iterable<Offset> points) {
  final result = <Offset>[];
  for (final point in points) {
    if (!point.dx.isFinite || !point.dy.isFinite) continue;
    if (result.isNotEmpty && (result.last - point).distance <= 1e-6) continue;
    result.add(point);
  }
  return result;
}

Offset _rotateOffsetForDxf(Offset point, double degrees) {
  final radians = degrees * math.pi / 180.0;
  final cosValue = math.cos(radians);
  final sinValue = math.sin(radians);
  return Offset(
    point.dx * cosValue - point.dy * sinValue,
    point.dx * sinValue + point.dy * cosValue,
  );
}

double _degreesToRadians(double degrees) => degrees * math.pi / 180.0;
