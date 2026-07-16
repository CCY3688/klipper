import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'stl_mesh.dart';

enum SurfacePreviewMode { wireframe, shaded, combined }

class SurfacePreview extends StatelessWidget {
  final StlMesh? mesh;
  final SurfacePreviewMode mode;
  final bool showBounds;
  final bool showAxes;
  final double rotationX;
  final double rotationY;
  final double rotationZ;
  final double zoom;
  final Offset pan;

  const SurfacePreview({
    super.key,
    required this.mesh,
    required this.mode,
    required this.showBounds,
    required this.showAxes,
    required this.rotationX,
    required this.rotationY,
    required this.rotationZ,
    required this.zoom,
    required this.pan,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: SurfacePreviewPainter(
        mesh: mesh,
        mode: mode,
        showBounds: showBounds,
        showAxes: showAxes,
        rotationX: rotationX,
        rotationY: rotationY,
        rotationZ: rotationZ,
        zoom: zoom,
        pan: pan,
      ),
    );
  }
}

class SurfacePreviewPainter extends CustomPainter {
  static const int _maxWireFaces = 12000;
  static const int _maxShadedFaces = 6000;

  final StlMesh? mesh;
  final SurfacePreviewMode mode;
  final bool showBounds;
  final bool showAxes;
  final double rotationX;
  final double rotationY;
  final double rotationZ;
  final double zoom;
  final Offset pan;

  const SurfacePreviewPainter({
    required this.mesh,
    required this.mode,
    required this.showBounds,
    required this.showAxes,
    required this.rotationX,
    required this.rotationY,
    required this.rotationZ,
    required this.zoom,
    required this.pan,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);

    final currentMesh = mesh;
    if (currentMesh == null || currentMesh.isEmpty) {
      return;
    }

    final projector = _Projector(
      mesh: currentMesh,
      size: size,
      rotationX: rotationX,
      rotationY: rotationY,
      rotationZ: rotationZ,
      zoom: zoom,
      pan: pan,
    );

    if (showBounds) {
      _drawBounds(canvas, projector, currentMesh.bounds);
    }

    _drawMesh(canvas, projector, currentMesh);

    if (showAxes) {
      _drawAxes(canvas, projector, currentMesh.bounds);
    }
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

    final centerPaint = Paint()
      ..color = const Color(0xFFE6EEF6)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      centerPaint,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      centerPaint,
    );
  }

  void _drawMesh(Canvas canvas, _Projector projector, StlMesh mesh) {
    final maxFaces = mode == SurfacePreviewMode.wireframe
        ? _maxWireFaces
        : _maxShadedFaces;
    final triangles = mesh.sampledTriangles(maxFaces);
    final projected = <_ProjectedTriangle>[];

    for (final triangle in triangles) {
      final a = projector.project(triangle.a);
      final b = projector.project(triangle.b);
      final c = projector.project(triangle.c);
      if ((a.point - b.point).distance < 0.15 &&
          (b.point - c.point).distance < 0.15) {
        continue;
      }

      final normal = projector.rotate(triangle.normal).normalized();
      final light = const StlVector3(-0.35, -0.55, 0.95).normalized();
      final shade = ((normal.dot(light) + 1.0) / 2.0).clamp(0.0, 1.0);
      projected.add(
        _ProjectedTriangle(
          points: [a.point, b.point, c.point],
          depth: (a.depth + b.depth + c.depth) / 3.0,
          shade: shade.toDouble(),
        ),
      );
    }

    projected.sort((a, b) => a.depth.compareTo(b.depth));

    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = mode == SurfacePreviewMode.wireframe ? 0.72 : 0.48
      ..strokeJoin = StrokeJoin.round
      ..color = mode == SurfacePreviewMode.wireframe
          ? const Color(0xFF6D7D8B).withValues(alpha: 0.88)
          : const Color(0xFF6A7480).withValues(alpha: 0.48);

    for (final triangle in projected) {
      final path = Path()
        ..moveTo(triangle.points[0].dx, triangle.points[0].dy)
        ..lineTo(triangle.points[1].dx, triangle.points[1].dy)
        ..lineTo(triangle.points[2].dx, triangle.points[2].dy)
        ..close();

      if (mode != SurfacePreviewMode.wireframe) {
        final fill = Paint()
          ..style = PaintingStyle.fill
          ..color = Color.lerp(
            const Color(0xFFFFFFFF),
            const Color(0xFFB7C9DA),
            1.0 - triangle.shade,
          )!.withValues(alpha: 0.74);
        canvas.drawPath(path, fill);
      }

      if (mode != SurfacePreviewMode.shaded) {
        canvas.drawPath(path, edgePaint);
      }
    }
  }

  void _drawBounds(Canvas canvas, _Projector projector, StlBounds bounds) {
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

  void _drawAxes(Canvas canvas, _Projector projector, StlBounds bounds) {
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
    _Projector projector,
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

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, end + const Offset(5, -6));
  }

  @override
  bool shouldRepaint(covariant SurfacePreviewPainter oldDelegate) {
    return oldDelegate.mesh != mesh ||
        oldDelegate.mode != mode ||
        oldDelegate.showBounds != showBounds ||
        oldDelegate.showAxes != showAxes ||
        oldDelegate.rotationX != rotationX ||
        oldDelegate.rotationY != rotationY ||
        oldDelegate.rotationZ != rotationZ ||
        oldDelegate.zoom != zoom ||
        oldDelegate.pan != pan;
  }
}

class _Projector {
  final StlMesh mesh;
  final Size size;
  final double rotationX;
  final double rotationY;
  final double rotationZ;
  final double zoom;
  final Offset pan;

  late final StlVector3 _center = mesh.bounds.center;
  late final double _scale = _fitScale();
  late final Offset _projectedCenter = _fitCenter();

  _Projector({
    required this.mesh,
    required this.size,
    required this.rotationX,
    required this.rotationY,
    required this.rotationZ,
    required this.zoom,
    required this.pan,
  });

  _ProjectedPoint project(StlVector3 point) {
    final rotated = rotate(point - _center);
    final projected = Offset(rotated.x, -rotated.y);
    final screen =
        Offset(size.width / 2, size.height / 2) +
        (projected - _projectedCenter) * _scale +
        pan;
    return _ProjectedPoint(screen, rotated.z);
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
    final b = mesh.bounds;
    final corners = [
      StlVector3(b.minX, b.minY, b.minZ),
      StlVector3(b.maxX, b.minY, b.minZ),
      StlVector3(b.maxX, b.maxY, b.minZ),
      StlVector3(b.minX, b.maxY, b.minZ),
      StlVector3(b.minX, b.minY, b.maxZ),
      StlVector3(b.maxX, b.minY, b.maxZ),
      StlVector3(b.maxX, b.maxY, b.maxZ),
      StlVector3(b.minX, b.maxY, b.maxZ),
    ];
    return corners.map((p) {
      final rotated = rotate(p - _center);
      return Offset(rotated.x, -rotated.y);
    }).toList();
  }
}

class _ProjectedPoint {
  final Offset point;
  final double depth;

  const _ProjectedPoint(this.point, this.depth);
}

class _ProjectedTriangle {
  final List<Offset> points;
  final double depth;
  final double shade;

  const _ProjectedTriangle({
    required this.points,
    required this.depth,
    required this.shade,
  });
}
