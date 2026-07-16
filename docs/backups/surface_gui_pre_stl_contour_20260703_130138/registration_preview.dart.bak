import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'stl_mesh.dart';
import 'surface_preview.dart';
import 'surface_registration.dart';
import 'surface_scan_models.dart';

/// 配准结果预览组件 - 显示打印床、配准后的模型和点云
class RegistrationPreview extends StatelessWidget {
  final StlMesh? mesh;
  final SurfaceScanResult? scan;
  final SurfaceRegistrationResult? registration;
  final bool showBed;
  final bool showMesh;
  final bool showScan;
  final bool showAxes;
  final SurfacePreviewMode meshMode;
  final double rotationX;
  final double rotationY;
  final double rotationZ;
  final double zoom;
  final Offset pan;

  const RegistrationPreview({
    super.key,
    required this.mesh,
    required this.scan,
    required this.registration,
    this.showBed = true,
    this.showMesh = true,
    this.showScan = true,
    this.showAxes = true,
    this.meshMode = SurfacePreviewMode.combined,
    required this.rotationX,
    required this.rotationY,
    required this.rotationZ,
    required this.zoom,
    required this.pan,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: RegistrationPreviewPainter(
        mesh: mesh,
        scan: scan,
        registration: registration,
        showBed: showBed,
        showMesh: showMesh,
        showScan: showScan,
        showAxes: showAxes,
        meshMode: meshMode,
        rotationX: rotationX,
        rotationY: rotationY,
        rotationZ: rotationZ,
        zoom: zoom,
        pan: pan,
      ),
    );
  }
}

class RegistrationPreviewPainter extends CustomPainter {
  static const int _maxMeshFaces = 4000;
  static const double _bedSize = 150.0; // 打印床尺寸 (mm)
  static const double _bedGridSpacing = 10.0; // 打印床网格间距 (mm)

  final StlMesh? mesh;
  final SurfaceScanResult? scan;
  final SurfaceRegistrationResult? registration;
  final bool showBed;
  final bool showMesh;
  final bool showScan;
  final bool showAxes;
  final SurfacePreviewMode meshMode;
  final double rotationX;
  final double rotationY;
  final double rotationZ;
  final double zoom;
  final Offset pan;

  const RegistrationPreviewPainter({
    required this.mesh,
    required this.scan,
    required this.registration,
    required this.showBed,
    required this.showMesh,
    required this.showScan,
    required this.showAxes,
    required this.meshMode,
    required this.rotationX,
    required this.rotationY,
    required this.rotationZ,
    required this.zoom,
    required this.pan,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);

    if (mesh == null || scan == null || registration == null) {
      _drawPlaceholder(canvas, size);
      return;
    }

    // 使用机械坐标系原点作为视图中心
    final bounds = _calculateCombinedBounds();
    final projector = _Projector(
      center: bounds.center,
      bounds: bounds,
      size: size,
      rotationX: rotationX,
      rotationY: rotationY,
      rotationZ: rotationZ,
      zoom: zoom,
      pan: pan,
    );

    // 绘制顺序：从后到前（根据 Z 深度）
    if (showBed) {
      _drawBed(canvas, projector);
    }

    if (showAxes) {
      _drawAxes(canvas, projector);
    }

    if (showScan) {
      _drawScanPoints(canvas, projector);
    }

    if (showMesh) {
      _drawTransformedMesh(canvas, projector);
    }

    _drawInfo(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1E2228), Color(0xFF2A2F36)],
      ).createShader(rect);
    canvas.drawRect(rect, bgPaint);
  }

  void _drawPlaceholder(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '完成配准后显示结果',
        style: TextStyle(
          color: Color(0xFF6B7280),
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
  }

  StlBounds _calculateCombinedBounds() {
    final scanBounds = scan!.bounds;

    // 扩展边界以包含打印床
    final minX = math.min(scanBounds.minX, -_bedSize / 2);
    final minY = math.min(scanBounds.minY, -_bedSize / 2);
    final minZ = 0.0;
    final maxX = math.max(scanBounds.maxX, _bedSize / 2);
    final maxY = math.max(scanBounds.maxY, _bedSize / 2);
    final maxZ = math.max(scanBounds.maxZ, 20.0);

    return StlBounds(
      minX: minX,
      minY: minY,
      minZ: minZ,
      maxX: maxX,
      maxY: maxY,
      maxZ: maxZ,
    );
  }

  void _drawBed(Canvas canvas, _Projector projector) {
    final halfSize = _bedSize / 2;

    // 绘制打印床平面 (Z=0)
    final bedCorners = [
      StlVector3(-halfSize, -halfSize, 0),
      StlVector3(halfSize, -halfSize, 0),
      StlVector3(halfSize, halfSize, 0),
      StlVector3(-halfSize, halfSize, 0),
    ];

    final projectedCorners = bedCorners.map((p) => projector.project(p)).toList();

    // 填充床面
    final bedPath = Path()
      ..moveTo(projectedCorners[0].point.dx, projectedCorners[0].point.dy)
      ..lineTo(projectedCorners[1].point.dx, projectedCorners[1].point.dy)
      ..lineTo(projectedCorners[2].point.dx, projectedCorners[2].point.dy)
      ..lineTo(projectedCorners[3].point.dx, projectedCorners[3].point.dy)
      ..close();

    final bedFill = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF3A3F48).withValues(alpha: 0.6);
    canvas.drawPath(bedPath, bedFill);

    // 绘制网格线
    final gridPaint = Paint()
      ..color = const Color(0xFF4A5160).withValues(alpha: 0.8)
      ..strokeWidth = 0.8;

    for (var x = -halfSize; x <= halfSize; x += _bedGridSpacing) {
      final start = projector.project(StlVector3(x, -halfSize, 0));
      final end = projector.project(StlVector3(x, halfSize, 0));
      canvas.drawLine(start.point, end.point, gridPaint);
    }

    for (var y = -halfSize; y <= halfSize; y += _bedGridSpacing) {
      final start = projector.project(StlVector3(-halfSize, y, 0));
      final end = projector.project(StlVector3(halfSize, y, 0));
      canvas.drawLine(start.point, end.point, gridPaint);
    }

    // 绘制床边框（加粗）
    final borderPaint = Paint()
      ..color = const Color(0xFF5A6170)
      ..strokeWidth = 2.0;
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(
        projectedCorners[i].point,
        projectedCorners[(i + 1) % 4].point,
        borderPaint,
      );
    }
  }

  void _drawAxes(Canvas canvas, _Projector projector) {
    const axisLength = 40.0;
    final origin = const StlVector3(0, 0, 0);

    // X 轴（红色）
    _drawAxis(
      canvas,
      projector,
      origin,
      StlVector3(axisLength, 0, 0),
      'X',
      const Color(0xFFE74C3C),
    );

    // Y 轴（绿色）
    _drawAxis(
      canvas,
      projector,
      origin,
      StlVector3(0, axisLength, 0),
      'Y',
      const Color(0xFF2ECC71),
    );

    // Z 轴（蓝色）
    _drawAxis(
      canvas,
      projector,
      origin,
      StlVector3(0, 0, axisLength),
      'Z',
      const Color(0xFF3498DB),
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
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, end, paint);

    // 绘制箭头
    canvas.drawCircle(end, 4.0, Paint()..color = color);

    // 绘制标签
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 2,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, end + const Offset(8, -8));
  }

  void _drawScanPoints(Canvas canvas, _Projector projector) {
    final validPoints = scan!.validPoints;

    for (final point in validPoints) {
      final pos = StlVector3(point.x, point.y, point.z ?? 0);
      final projected = projector.project(pos);

      // 根据高度着色
      final z = point.z ?? 0;
      final zRange = scan!.summary.zRange ?? 1.0;
      final zMin = scan!.summary.zMin ?? 0.0;
      final normalizedZ = zRange > 0 ? ((z - zMin) / zRange).clamp(0.0, 1.0) : 0.5;

      final color = Color.lerp(
        const Color(0xFF3498DB), // 低点：蓝色
        const Color(0xFFE74C3C), // 高点：红色
        normalizedZ,
      )!;

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(projected.point, 2.5, paint);

      // 外圈描边
      final borderPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      canvas.drawCircle(projected.point, 2.5, borderPaint);
    }
  }

  void _drawTransformedMesh(Canvas canvas, _Projector projector) {
    final currentMesh = mesh!;
    final transform = registration!.transform;

    final triangles = currentMesh.sampledTriangles(_maxMeshFaces);
    final projected = <_ProjectedTriangle>[];

    for (final triangle in triangles) {
      // 应用配准变换
      final a = transform.transformPoint(triangle.a);
      final b = transform.transformPoint(triangle.b);
      final c = transform.transformPoint(triangle.c);

      final projA = projector.project(a);
      final projB = projector.project(b);
      final projC = projector.project(c);

      // 跳过退化三角形
      if ((projA.point - projB.point).distance < 0.15 &&
          (projB.point - projC.point).distance < 0.15) {
        continue;
      }

      // 计算变换后的法向量
      final transformedNormal = transform.transformPoint(
        triangle.center + triangle.normal,
      ) - transform.transformPoint(triangle.center);
      final rotatedNormal = projector.rotate(transformedNormal.normalized());

      // 光照计算
      final light = const StlVector3(-0.3, -0.5, 0.9).normalized();
      final shade = ((rotatedNormal.dot(light) + 1.0) / 2.0).clamp(0.0, 1.0);

      projected.add(
        _ProjectedTriangle(
          points: [projA.point, projB.point, projC.point],
          depth: (projA.depth + projB.depth + projC.depth) / 3.0,
          shade: shade.toDouble(),
        ),
      );
    }

    // 按深度排序（画家算法）
    projected.sort((a, b) => a.depth.compareTo(b.depth));

    // 根据显示模式设置画笔
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = meshMode == SurfacePreviewMode.wireframe ? 0.72 : 0.48
      ..strokeJoin = StrokeJoin.round
      ..color = meshMode == SurfacePreviewMode.wireframe
          ? const Color(0xFF6D7D8B).withValues(alpha: 0.88)
          : const Color(0xFF6A7480).withValues(alpha: 0.48);

    // 绘制三角形
    for (final triangle in projected) {
      final path = Path()
        ..moveTo(triangle.points[0].dx, triangle.points[0].dy)
        ..lineTo(triangle.points[1].dx, triangle.points[1].dy)
        ..lineTo(triangle.points[2].dx, triangle.points[2].dy)
        ..close();

      // 填充（实体或网格实体模式）
      if (meshMode != SurfacePreviewMode.wireframe) {
        final fillColor = Color.lerp(
          const Color(0xFFFFFFFF),
          const Color(0xFFB7C9DA),
          1.0 - triangle.shade,
        )!;
        final fill = Paint()
          ..style = PaintingStyle.fill
          ..color = fillColor.withValues(alpha: 0.74);
        canvas.drawPath(path, fill);
      }

      // 边缘（网格或网格实体模式）
      if (meshMode != SurfacePreviewMode.shaded) {
        canvas.drawPath(path, edgePaint);
      }
    }
  }

  void _drawInfo(Canvas canvas, Size size) {
    if (registration == null) return;

    final status = registration!.passed ? '通过' : '超限';
    final statusColor = registration!.passed
        ? const Color(0xFF2ECC71)
        : const Color(0xFFE74C3C);

    final info = [
      '状态: $status',
      'RMSE: ${registration!.rmse.toStringAsFixed(3)} mm',
      '匹配点: ${registration!.matchedPairs}',
      '迭代: ${registration!.iterations}',
    ];

    final textPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '${info[0]}\n',
            style: TextStyle(
              color: statusColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text: info.skip(1).join('\n'),
            style: const TextStyle(
              color: Color(0xFFD1D5DB),
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final padding = 12.0;
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        padding,
        padding,
        textPainter.width + 16,
        textPainter.height + 12,
      ),
      const Radius.circular(6),
    );

    final bgPaint = Paint()
      ..color = const Color(0xFF1F2937).withValues(alpha: 0.85);
    canvas.drawRRect(bgRect, bgPaint);

    textPainter.paint(canvas, Offset(padding + 8, padding + 6));
  }

  @override
  bool shouldRepaint(covariant RegistrationPreviewPainter oldDelegate) {
    return oldDelegate.mesh != mesh ||
        oldDelegate.scan != scan ||
        oldDelegate.registration != registration ||
        oldDelegate.showBed != showBed ||
        oldDelegate.showMesh != showMesh ||
        oldDelegate.showScan != showScan ||
        oldDelegate.showAxes != showAxes ||
        oldDelegate.meshMode != meshMode ||
        oldDelegate.rotationX != rotationX ||
        oldDelegate.rotationY != rotationY ||
        oldDelegate.rotationZ != rotationZ ||
        oldDelegate.zoom != zoom ||
        oldDelegate.pan != pan;
  }
}

class _Projector {
  final StlVector3 center;
  final StlBounds bounds;
  final Size size;
  final double rotationX;
  final double rotationY;
  final double rotationZ;
  final double zoom;
  final Offset pan;

  late final double _scale = _fitScale();
  late final Offset _projectedCenter = _fitCenter();

  _Projector({
    required this.center,
    required this.bounds,
    required this.size,
    required this.rotationX,
    required this.rotationY,
    required this.rotationZ,
    required this.zoom,
    required this.pan,
  });

  _ProjectedPoint project(StlVector3 point) {
    final rotated = rotate(point - center);
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
    final fit = math.min(size.width / width, size.height / height) * 0.65;
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
      final rotated = rotate(p - center);
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
