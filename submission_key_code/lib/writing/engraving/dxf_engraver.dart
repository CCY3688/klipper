import 'package:flutter/material.dart' show Offset;

import '../../ui/surface/dxf_toolpath.dart';
import '../model/geometry.dart';
import '../model/toolpath.dart';

class DxfEngraveOptions {
  final double originXmm;
  final double originYmm;
  final double widthMm;
  final double heightMm;
  final bool keepAspectRatio;
  final bool mirrorX;
  final bool mirrorY;
  final double rotationDeg;
  final double translateXmm;
  final double translateYmm;

  const DxfEngraveOptions({
    required this.originXmm,
    required this.originYmm,
    required this.widthMm,
    required this.heightMm,
    this.keepAspectRatio = true,
    this.mirrorX = false,
    this.mirrorY = false,
    this.rotationDeg = 0,
    this.translateXmm = 0,
    this.translateYmm = 0,
  });
}

class DxfEngraver {
  const DxfEngraver._();

  static ToolPath buildToolPath(
    DxfToolpath dxf, {
    required DxfEngraveOptions options,
  }) {
    if (dxf.isEmpty || options.widthMm <= 0 || options.heightMm <= 0) {
      return ToolPath.empty;
    }

    final center = Offset(
      options.originXmm + options.widthMm / 2 + options.translateXmm,
      options.originYmm + options.heightMm / 2 + options.translateYmm,
    );
    final polylines = dxf.transformedPolylines(
      widthMm: options.widthMm,
      heightMm: options.heightMm,
      center: center,
      rotationDeg: options.rotationDeg,
      keepAspectRatio: options.keepAspectRatio,
      mirrorX: options.mirrorX,
      mirrorY: options.mirrorY,
    );

    return ToolPath(
      polylines: [
        for (final polyline in polylines)
          ToolPolyline(
            penDown: true,
            points: [for (final point in polyline) Vec2(point.dx, point.dy)],
          ),
      ],
    );
  }
}
