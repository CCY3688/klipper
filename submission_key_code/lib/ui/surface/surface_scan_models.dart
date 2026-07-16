import 'dart:math' as math;

import 'stl_mesh.dart';

class SurfaceScanResult {
  final String profile;
  final String sensor;
  final String createdAt;
  final double? spacing;
  final double? scanZ;
  final SurfaceScanSummary summary;
  final SurfaceScanGrid grid;
  final List<SurfaceScanPoint> points;
  final List<SurfaceScanPoint> invalidPoints;
  final String? csvPath;
  final String? jsonPath;

  const SurfaceScanResult({
    required this.profile,
    required this.sensor,
    required this.createdAt,
    required this.spacing,
    required this.scanZ,
    required this.summary,
    required this.grid,
    required this.points,
    required this.invalidPoints,
    required this.csvPath,
    required this.jsonPath,
  });

  factory SurfaceScanResult.fromJson(Map<String, dynamic> json) {
    final rawPoints = (json['points'] as List?) ?? const [];
    final points = rawPoints
        .whereType<Map>()
        .map((e) => SurfaceScanPoint.fromJson(e.cast<String, dynamic>()))
        .toList();

    final rawInvalid = (json['invalid_points'] as List?) ?? const [];
    final invalidPoints = rawInvalid
        .whereType<Map>()
        .map((e) => SurfaceScanPoint.fromJson(e.cast<String, dynamic>()))
        .toList();

    return SurfaceScanResult(
      profile: (json['profile'] ?? '').toString(),
      sensor: (json['sensor'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      spacing: _asDouble(json['spacing']),
      scanZ: _asDouble(json['scan_z']),
      summary: SurfaceScanSummary.fromJson(
        (json['summary'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      grid: SurfaceScanGrid.fromJson(
        (json['grid'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      points: points,
      invalidPoints: invalidPoints,
      csvPath: json['csv_path']?.toString(),
      jsonPath: json['json_path']?.toString(),
    );
  }

  List<SurfaceScanPoint> get validPoints =>
      points.where((point) => point.valid && point.z != null).toList();

  bool get isEmpty => points.isEmpty;

  StlBounds get bounds {
    var renderPoints = points.where((point) => point.z != null).toList();
    renderPoints = renderPoints.isEmpty ? points : renderPoints;
    if (renderPoints.isEmpty) {
      return const StlBounds(
        minX: 0,
        maxX: 1,
        minY: 0,
        maxY: 1,
        minZ: 0,
        maxZ: 1,
      );
    }

    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var maxZ = -double.infinity;

    for (final point in renderPoints) {
      final z = point.z ?? summary.zMin ?? scanZ ?? 0;
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minY = math.min(minY, point.y);
      maxY = math.max(maxY, point.y);
      minZ = math.min(minZ, z);
      maxZ = math.max(maxZ, z);
    }

    if ((maxZ - minZ).abs() < 1e-6) {
      minZ -= 0.5;
      maxZ += 0.5;
    }

    return StlBounds(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      minZ: minZ,
      maxZ: maxZ,
    );
  }
}

class SurfaceScanPoint {
  final int index;
  final double x;
  final double y;
  final double? z;
  final double? distanceMm;
  final double? rawMm;
  final int? status;
  final double? sigma;
  final bool valid;
  final String? error;

  const SurfaceScanPoint({
    required this.index,
    required this.x,
    required this.y,
    required this.z,
    required this.distanceMm,
    required this.rawMm,
    required this.status,
    required this.sigma,
    required this.valid,
    required this.error,
  });

  factory SurfaceScanPoint.fromJson(Map<String, dynamic> json) {
    final z = _asDouble(json['z']);
    return SurfaceScanPoint(
      index: _asInt(json['index']) ?? 0,
      x: _asDouble(json['x']) ?? 0,
      y: _asDouble(json['y']) ?? 0,
      z: z,
      distanceMm: _asDouble(json['distance_mm']),
      rawMm: _asDouble(json['raw_mm']),
      status: _asInt(json['status']),
      sigma: _asDouble(json['sigma']),
      valid: (json['valid'] as bool?) ?? z != null,
      error: json['error']?.toString(),
    );
  }
}

class SurfaceScanSummary {
  final int pointCount;
  final int validCount;
  final int invalidCount;
  final double? zMin;
  final double? zMax;
  final double? zRange;

  const SurfaceScanSummary({
    required this.pointCount,
    required this.validCount,
    required this.invalidCount,
    required this.zMin,
    required this.zMax,
    required this.zRange,
  });

  factory SurfaceScanSummary.fromJson(Map<String, dynamic> json) {
    return SurfaceScanSummary(
      pointCount: _asInt(json['point_count']) ?? 0,
      validCount: _asInt(json['valid_count']) ?? 0,
      invalidCount: _asInt(json['invalid_count']) ?? 0,
      zMin: _asDouble(json['z_min']),
      zMax: _asDouble(json['z_max']),
      zRange: _asDouble(json['z_range']),
    );
  }
}

class SurfaceScanGrid {
  final int xCount;
  final int yCount;
  final List<double> xPoints;
  final List<double> yPoints;

  const SurfaceScanGrid({
    required this.xCount,
    required this.yCount,
    required this.xPoints,
    required this.yPoints,
  });

  factory SurfaceScanGrid.fromJson(Map<String, dynamic> json) {
    final xPoints = _asDoubleList(json['x_points']);
    final yPoints = _asDoubleList(json['y_points']);
    return SurfaceScanGrid(
      xCount: _asInt(json['x_count']) ?? xPoints.length,
      yCount: _asInt(json['y_count']) ?? yPoints.length,
      xPoints: xPoints,
      yPoints: yPoints,
    );
  }
}

class SurfaceScanProgress {
  final bool active;
  final String? profile;
  final int current;
  final int total;
  final int remaining;
  final double percent;
  final double? updated;

  const SurfaceScanProgress({
    required this.active,
    required this.profile,
    required this.current,
    required this.total,
    required this.remaining,
    required this.percent,
    required this.updated,
  });

  factory SurfaceScanProgress.fromJson(Map<String, dynamic> json) {
    final current = _asInt(json['current']) ?? 0;
    final total = _asInt(json['total']) ?? 0;
    final percent = total <= 0 ? 0.0 : current / total;
    return SurfaceScanProgress(
      active: (json['active'] as bool?) ?? false,
      profile: json['profile']?.toString(),
      current: current,
      total: total,
      remaining: _asInt(json['remaining']) ?? math.max(0, total - current),
      percent: percent.clamp(0.0, 1.0).toDouble(),
      updated: _asDouble(json['updated']),
    );
  }

  bool get hasWork => total > 0;
  bool get complete => hasWork && current >= total && !active;
}

double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

List<double> _asDoubleList(dynamic value) {
  if (value is! List) return const [];
  return value.map(_asDouble).whereType<double>().toList(growable: false);
}
