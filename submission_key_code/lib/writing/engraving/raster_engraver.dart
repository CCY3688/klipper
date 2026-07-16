import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../model/geometry.dart';
import '../model/toolpath.dart';

class RasterEngraveOptions {
  final double originXmm;
  final double originYmm;
  final double widthMm;
  final double heightMm;
  final double stepMm;
  final double threshold;
  final bool invert;

  const RasterEngraveOptions({
    required this.originXmm,
    required this.originYmm,
    required this.widthMm,
    required this.heightMm,
    required this.stepMm,
    required this.threshold,
    this.invert = false,
  });
}

class RasterEngraver {
  const RasterEngraver._();

  static ToolPath buildToolPath(
    img.Image image, {
    required RasterEngraveOptions options,
  }) {
    if (image.width <= 0 ||
        image.height <= 0 ||
        options.widthMm <= 0 ||
        options.heightMm <= 0 ||
        options.stepMm <= 0) {
      return ToolPath.empty;
    }

    final rows = image.height == 1
        ? 1
        : math.max(1, (options.heightMm / options.stepMm).floor() + 1);
    final cols = math.max(2, (options.widthMm / options.stepMm).ceil() + 1);
    final threshold = options.threshold.clamp(0.0, 255.0);
    final polylines = <ToolPolyline>[];

    for (var row = 0; row < rows; row++) {
      final yRatio = rows == 1 ? 0.0 : row / (rows - 1);
      final sourceY = (yRatio * (image.height - 1)).round();
      final y = options.originYmm + yRatio * options.heightMm;
      int? runStart;

      for (var col = 0; col < cols; col++) {
        final xRatio = col / (cols - 1);
        final sourceX = (xRatio * (image.width - 1)).round();
        final dark = _isEngravedPixel(
          image,
          sourceX,
          sourceY,
          threshold,
          options.invert,
        );

        if (dark && runStart == null) {
          runStart = col;
        }

        final isLast = col == cols - 1;
        if ((!dark || isLast) && runStart != null) {
          final runEnd = dark && isLast ? col : col - 1;
          var startColumn = runStart;
          var endColumn = runEnd;
          if (runEnd == runStart) {
            if (runEnd < cols - 1) {
              endColumn = runEnd + 1;
            } else {
              startColumn = math.max(0, runStart - 1);
            }
          }
          final startX = _xAtColumn(options, cols, startColumn);
          final endX = _xAtColumn(options, cols, endColumn);

          final left = math.min(startX, endX);
          final right = math.max(startX, endX);
          final points = row.isEven
              ? [Vec2(left, y), Vec2(right, y)]
              : [Vec2(right, y), Vec2(left, y)];
          polylines.add(ToolPolyline(penDown: true, points: points));
          runStart = null;
        }
      }
    }

    return ToolPath(polylines: polylines);
  }

  static double _xAtColumn(RasterEngraveOptions options, int cols, int col) {
    final ratio = cols == 1 ? 0.0 : col / (cols - 1);
    return options.originXmm + ratio * options.widthMm;
  }

  static bool _isEngravedPixel(
    img.Image image,
    int x,
    int y,
    double threshold,
    bool invert,
  ) {
    final pixel = image.getPixel(x, y);
    final alpha = pixel.a.toDouble();
    if (alpha <= 0) return false;

    final luminance =
        0.299 * pixel.r.toDouble() +
        0.587 * pixel.g.toDouble() +
        0.114 * pixel.b.toDouble();
    return invert ? luminance >= threshold : luminance <= threshold;
  }
}
