import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'stl_mesh.dart';
import 'surface_scan_models.dart';

class PointCloudPreview extends StatelessWidget {
  final SurfaceScanResult? result;
  final bool showBounds;
  final bool showAxes;
  final bool showInvalid;
  final bool showLines;
  final double rotationX;
  final double rotationY;
  final double rotationZ;
  final double zoom;
  final double zScale;
  final Offset pan;

  const PointCloudPreview({
    super.key,
    required this.result,
    required this.showBounds,
    required this.showAxes,
    required this.showInvalid,
    required this.showLines,
    required this.rotationX,
    required this.rotationY,
    required this.rotationZ,
    required this.zoom,
    required this.zScale,
    required this.pan,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: PointCloudPreviewPainter(
        result: result,
        showBounds: showBounds,
        showAxes: showAxes,
        showInvalid: showInvalid,
        showLines: showLines,
        rotationX: rotationX,
        rotationY: rotationY,
        rotationZ: rotationZ,
        zoom: zoom,
        zScale: zScale,
        pan: pan,
      ),
    );
  }
}

class PointCloudPreviewPainter extends CustomPainter {
  final SurfaceScanResult? result;
  final bool showBounds;
  final bool showAxes;
  final bool showInvalid;
  final bool showLines;
  final double rotationX;
  final double rotationY;
  final double rotationZ;
  final double zoom;
  final double zScale;
  final Offset pan;

  const PointCloudPreviewPainter({
    required this.result,
    required this.showBounds,
    required this.showAxes,
    required this.showInvalid,
    required this.showLines,
    required this.rotationX,
    required this.rotationY,
    required this.rotationZ,
    required this.zoom,
    required this.zScale,
    required this.pan,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);

    final scan = result;
    if (scan == null || scan.isEmpty) return;

    final projector = _PointProjector(
      bounds: scan.bounds,
      size: size,
      rotationX: rotationX,
      rotationY: rotationY,
      rotationZ: rotationZ,
      zoom: zoom,
      zScale: zScale,
      pan: pan,
    );

    if (showBounds) {
      _drawBounds(canvas, projector, scan.bounds);
    }

    if (showLines) {
      _drawScanLines(canvas, projector, scan);
    }

    _drawPoints(canvas, projector, scan);

    if (showAxes) {
      _drawAxes(canvas, projector, scan.bounds);
    }

    _drawHeightRuler(canvas, size, scan);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF8FBFE), Color(0xFFE7F1FB)],
      ).createShader(rect);
    canvas.drawRect(rect, bgPaint);

    final gridPaint = Paint()
      ..color = const Color(0xFFD4E0EB)
      ..strokeWidth = 0.7;
    const gap = 40.0;
    for (var x = 0.0; x <= size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y <= size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  void _drawScanLines(
    Canvas canvas,
    _PointProjector projector,
    SurfaceScanResult scan,
  ) {
    final linePaint = Paint()
      ..color = const Color(0xFF516170).withValues(alpha: 0.36)
      ..strokeWidth = 0.75
      ..strokeCap = StrokeCap.round;

    SurfaceScanPoint? previous;
    for (final point in scan.points) {
      if (point.valid && point.z != null) {
        if (previous != null && previous.valid && previous.z != null) {
          final rowBreak =
              scan.grid.xCount > 0 &&
              point.index ~/ scan.grid.xCount !=
                  previous.index ~/ scan.grid.xCount;
          if (!rowBreak) {
            canvas.drawLine(
              projector.project(_toVector(previous, scan)).point,
              projector.project(_toVector(point, scan)).point,
              linePaint,
            );
          }
        }
        previous = point;
      } else {
        previous = null;
      }
    }

    final byGrid = <String, SurfaceScanPoint>{};
    for (final point in scan.points) {
      if (point.valid && point.z != null) {
        byGrid[_gridKey(point.x, point.y)] = point;
      }
    }

    for (var xi = 0; xi < scan.grid.xPoints.length; xi++) {
      SurfaceScanPoint? last;
      for (var yi = 0; yi < scan.grid.yPoints.length; yi++) {
        final point =
            byGrid[_gridKey(scan.grid.xPoints[xi], scan.grid.yPoints[yi])];
        if (point != null && last != null) {
          canvas.drawLine(
            projector.project(_toVector(last, scan)).point,
            projector.project(_toVector(point, scan)).point,
            linePaint,
          );
        }
        last = point;
      }
    }
  }

  void _drawPoints(
    Canvas canvas,
    _PointProjector projector,
    SurfaceScanResult scan,
  ) {
    final projected = <_ProjectedScanPoint>[];
    for (final point in scan.points) {
      if (point.z == null && !showInvalid) continue;
      final projectedPoint = projector.project(_toVector(point, scan));
      projected.add(
        _ProjectedScanPoint(point, projectedPoint.point, projectedPoint.depth),
      );
    }

    projected.sort((a, b) => a.depth.compareTo(b.depth));
    final zMin = scan.summary.zMin ?? scan.bounds.minZ;
    final zMax = scan.summary.zMax ?? scan.bounds.maxZ;
    final zRange = math.max(zMax - zMin, 1e-6);

    for (final item in projected) {
      final point = item.source;
      if (!point.valid || point.z == null) {
        final markerPaint = Paint()
          ..color = const Color(0xFFC94D47).withValues(alpha: 0.82)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round;
        const r = 3.5;
        canvas.drawLine(
          item.screen + const Offset(-r, -r),
          item.screen + const Offset(r, r),
          markerPaint,
        );
        canvas.drawLine(
          item.screen + const Offset(r, -r),
          item.screen + const Offset(-r, r),
          markerPaint,
        );
        continue;
      }

      final t = ((point.z! - zMin) / zRange).clamp(0.0, 1.0).toDouble();
      final color = _heightColor(t);
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.10)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(item.screen + const Offset(0.6, 0.8), 3.4, shadowPaint);
      canvas.drawCircle(
        item.screen,
        3.1,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        item.screen,
        3.1,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.65,
      );
    }
  }

  void _drawHeightRuler(Canvas canvas, Size size, SurfaceScanResult scan) {
    final zMin = scan.summary.zMin;
    final zMax = scan.summary.zMax;
    if (zMin == null || zMax == null) return;

    const panelWidth = 94.0;
    const barWidth = 10.0;
    final rulerHeight = math.min(190.0, size.height - 112).clamp(86.0, 190.0);
    final left = size.width - panelWidth - 14;
    final top = 54.0;
    if (left < 14 || size.height < 170) return;

    final panelRect = Rect.fromLTWH(
      left,
      top - 28,
      panelWidth,
      rulerHeight + 56,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(panelRect, const Radius.circular(6)),
      Paint()..color = Colors.white.withValues(alpha: 0.76),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(panelRect, const Radius.circular(6)),
      Paint()
        ..color = const Color(0xFF8BA0B4).withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    final barLeft = left + 12;
    final rect = Rect.fromLTWH(barLeft, top, barWidth, rulerHeight);
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFD9503F),
          Color(0xFFF0B342),
          Color(0xFF2BAE9F),
          Color(0xFF2D6CDF),
        ],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      paint,
    );

    const titleStyle = TextStyle(
      color: Color(0xFF2F3C4C),
      fontSize: 10,
      fontWeight: FontWeight.w700,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    _paintText(canvas, 'Z mm', Offset(left + 10, top - 19), titleStyle);
    _paintRightText(
      canvas,
      '${zScale.toStringAsFixed(1)}x',
      Offset(left + panelWidth - 10, top - 19),
      titleStyle,
    );

    const labelStyle = TextStyle(
      color: Color(0xFF2F3C4C),
      fontSize: 10,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final tickPaint = Paint()
      ..color = const Color(0xFF425466).withValues(alpha: 0.86)
      ..strokeWidth = 0.9;
    const tickCount = 5;
    for (var i = 0; i < tickCount; i++) {
      final t = i / (tickCount - 1);
      final y = top + rulerHeight * t;
      final value = zMax - (zMax - zMin) * t;
      canvas.drawLine(
        Offset(barLeft + barWidth + 3, y),
        Offset(barLeft + barWidth + 10, y),
        tickPaint,
      );
      _paintText(
        canvas,
        value.toStringAsFixed(2),
        Offset(barLeft + barWidth + 14, y - 6),
        labelStyle,
      );
    }
  }

  void _drawBounds(Canvas canvas, _PointProjector projector, StlBounds bounds) {
    final corners = [
      StlVector3(bounds.minX, bounds.minY, bounds.minZ),
      StlVector3(bounds.maxX, bounds.minY, bounds.minZ),
      StlVector3(bounds.maxX, bounds.maxY, bounds.minZ),
      StlVector3(bounds.minX, bounds.maxY, bounds.minZ),
      StlVector3(bounds.minX, bounds.minY, bounds.maxZ),
      StlVector3(bounds.maxX, bounds.minY, bounds.maxZ),
      StlVector3(bounds.maxX, bounds.maxY, bounds.maxZ),
      StlVector3(bounds.minX, bounds.maxY, bounds.maxZ),
    ];
    const edges = [
      [0, 1],
      [1, 2],
      [2, 3],
      [3, 0],
      [4, 5],
      [5, 6],
      [6, 7],
      [7, 4],
      [0, 4],
      [1, 5],
      [2, 6],
      [3, 7],
    ];
    final projected = corners.map((p) => projector.project(p).point).toList();
    final paint = Paint()
      ..color = const Color(0xFF2F80C1).withValues(alpha: 0.55)
      ..strokeWidth = 1.1;
    for (final edge in edges) {
      canvas.drawLine(projected[edge[0]], projected[edge[1]], paint);
    }
  }

  void _drawAxes(Canvas canvas, _PointProjector projector, StlBounds bounds) {
    final span = math.max(bounds.maxSpan * 0.32, 1.0);
    final origin = StlVector3(bounds.minX, bounds.minY, bounds.minZ);
    _drawAxis(
      canvas,
      projector,
      origin,
      StlVector3(origin.x + span, origin.y, origin.z),
      'X',
      const Color(0xFFD84A3A),
    );
    _drawAxis(
      canvas,
      projector,
      origin,
      StlVector3(origin.x, origin.y + span, origin.z),
      'Y',
      const Color(0xFF2E9D57),
    );
    _drawAxis(
      canvas,
      projector,
      origin,
      StlVector3(origin.x, origin.y, origin.z + span),
      'Z',
      const Color(0xFF2E72D2),
    );
  }

  void _drawAxis(
    Canvas canvas,
    _PointProjector projector,
    StlVector3 from,
    StlVector3 to,
    String label,
    Color color,
  ) {
    final start = projector.project(from).point;
    final end = projector.project(to).point;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, end, paint);
    canvas.drawCircle(end, 3.2, Paint()..color = color);
    _paintText(
      canvas,
      label,
      end + const Offset(5, -6),
      TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    );
  }

  Color _heightColor(double t) {
    if (t < 0.34) {
      return Color.lerp(
        const Color(0xFF2D6CDF),
        const Color(0xFF2BAE9F),
        t / 0.34,
      )!;
    }
    if (t < 0.68) {
      return Color.lerp(
        const Color(0xFF2BAE9F),
        const Color(0xFFF0B342),
        (t - 0.34) / 0.34,
      )!;
    }
    return Color.lerp(
      const Color(0xFFF0B342),
      const Color(0xFFD9503F),
      (t - 0.68) / 0.32,
    )!;
  }

  StlVector3 _toVector(SurfaceScanPoint point, SurfaceScanResult scan) {
    return StlVector3(
      point.x,
      point.y,
      point.z ?? scan.summary.zMin ?? scan.scanZ ?? 0,
    );
  }

  String _gridKey(double x, double y) {
    return '${x.toStringAsFixed(4)},${y.toStringAsFixed(4)}';
  }

  void _paintText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  void _paintRightText(
    Canvas canvas,
    String text,
    Offset rightTop,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, rightTop - Offset(painter.width, 0));
  }

  @override
  bool shouldRepaint(covariant PointCloudPreviewPainter oldDelegate) {
    return oldDelegate.result != result ||
        oldDelegate.showBounds != showBounds ||
        oldDelegate.showAxes != showAxes ||
        oldDelegate.showInvalid != showInvalid ||
        oldDelegate.showLines != showLines ||
        oldDelegate.rotationX != rotationX ||
        oldDelegate.rotationY != rotationY ||
        oldDelegate.rotationZ != rotationZ ||
        oldDelegate.zoom != zoom ||
        oldDelegate.zScale != zScale ||
        oldDelegate.pan != pan;
  }
}

class _PointProjector {
  final StlBounds bounds;
  final Size size;
  final double rotationX;
  final double rotationY;
  final double rotationZ;
  final double zoom;
  final double zScale;
  final Offset pan;

  late final StlVector3 _center = bounds.center;
  late final double _scale = _fitScale();
  late final Offset _projectedCenter = _fitCenter();

  _PointProjector({
    required this.bounds,
    required this.size,
    required this.rotationX,
    required this.rotationY,
    required this.rotationZ,
    required this.zoom,
    required this.zScale,
    required this.pan,
  });

  _ProjectedPoint project(StlVector3 point) {
    final rotated = rotate(_scaleZ(point) - _center);
    final projected = Offset(rotated.x, -rotated.y);
    final screen =
        Offset(size.width / 2, size.height / 2) +
        (projected - _projectedCenter) * _scale +
        pan;
    return _ProjectedPoint(screen, rotated.z);
  }

  StlVector3 _scaleZ(StlVector3 point) {
    return StlVector3(
      point.x,
      point.y,
      _center.z + (point.z - _center.z) * zScale.clamp(0.2, 8.0),
    );
  }

  StlVector3 rotate(StlVector3 point) {
    final cx = math.cos(rotationX);
    final sx = math.sin(rotationX);
    final cy = math.cos(rotationY);
    final sy = math.sin(rotationY);
    final cz = math.cos(rotationZ);
    final sz = math.sin(rotationZ);

    var x = point.x;
    var y = point.y * cx - point.z * sx;
    var z = point.y * sx + point.z * cx;

    final x2 = x * cy + z * sy;
    final z2 = -x * sy + z * cy;
    x = x2;
    z = z2;

    final x3 = x * cz - y * sz;
    final y3 = x * sz + y * cz;
    return StlVector3(x3, y3, z);
  }

  double _fitScale() {
    final points = _projectedBoundsCorners();
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final p in points) {
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }

    final width = math.max(maxX - minX, 1e-6);
    final height = math.max(maxY - minY, 1e-6);
    final fit = math.min(size.width / width, size.height / height) * 0.72;
    return fit * zoom.clamp(0.2, 8.0);
  }

  Offset _fitCenter() {
    final points = _projectedBoundsCorners();
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final p in points) {
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
    return Offset((minX + maxX) / 2, (minY + maxY) / 2);
  }

  List<Offset> _projectedBoundsCorners() {
    final corners = [
      StlVector3(bounds.minX, bounds.minY, bounds.minZ),
      StlVector3(bounds.maxX, bounds.minY, bounds.minZ),
      StlVector3(bounds.maxX, bounds.maxY, bounds.minZ),
      StlVector3(bounds.minX, bounds.maxY, bounds.minZ),
      StlVector3(bounds.minX, bounds.minY, bounds.maxZ),
      StlVector3(bounds.maxX, bounds.minY, bounds.maxZ),
      StlVector3(bounds.maxX, bounds.maxY, bounds.maxZ),
      StlVector3(bounds.minX, bounds.maxY, bounds.maxZ),
    ];
    return corners.map((p) {
      final rotated = rotate(_scaleZ(p) - _center);
      return Offset(rotated.x, -rotated.y);
    }).toList();
  }
}

class _ProjectedPoint {
  final Offset point;
  final double depth;

  const _ProjectedPoint(this.point, this.depth);
}

class _ProjectedScanPoint {
  final SurfaceScanPoint source;
  final Offset screen;
  final double depth;

  const _ProjectedScanPoint(this.source, this.screen, this.depth);
}
