import 'dart:math' as math;

import 'stl_mesh.dart';
import 'surface_scan_models.dart';

class SurfaceRegistrationOptions {
  final int maxIterations;
  final double toleranceMm;
  final double rmseThresholdMm;
  final int maxModelSamples;
  final int maxScanSamples;
  final int yawSearchSteps;
  final double? maxPairDistanceMm;
  final bool skipInitialSearch;
  final bool lockModelOrientation;

  const SurfaceRegistrationOptions({
    this.maxIterations = 35,
    this.toleranceMm = 0.002,
    this.rmseThresholdMm = 0.5,
    this.maxModelSamples = 1800,
    this.maxScanSamples = 2600,
    this.yawSearchSteps = 24,
    this.maxPairDistanceMm,
    this.skipInitialSearch = false,
    this.lockModelOrientation = false,
  });
}

class SurfaceRegistrationResult {
  final Transform3D initialTransform;
  final Transform3D transform;
  final double initialRmse;
  final double rmse;
  final int iterations;
  final int matchedPairs;
  final bool converged;
  final double thresholdMm;
  final SurfaceRegistrationDiagnostics diagnostics;

  const SurfaceRegistrationResult({
    required this.initialTransform,
    required this.transform,
    required this.initialRmse,
    required this.rmse,
    required this.iterations,
    required this.matchedPairs,
    required this.converged,
    required this.thresholdMm,
    required this.diagnostics,
  });

  bool get passed => rmse <= thresholdMm;

  bool get hasFiniteRmse => rmse.isFinite;

  String get statusMessage {
    if (passed) {
      return 'Registration passed, RMSE ${rmse.toStringAsFixed(3)} mm';
    }
    if (!hasFiniteRmse || matchedPairs < 3) {
      return 'Registration failed: not enough nearest-neighbor pairs within '
          '${diagnostics.pairGateMm.toStringAsFixed(2)} mm';
    }
    return 'Registration RMSE ${rmse.toStringAsFixed(3)} mm exceeds threshold';
  }
}

class SurfaceRegistrationDiagnostics {
  final StlBounds modelBounds;
  final StlBounds scanBounds;
  final int modelSampleCount;
  final int scanSampleCount;
  final int topFacingTriangleCount;
  final int totalTriangleCount;
  final double pairGateMm;
  final double bestInitialAngleDeg;
  final String bestInitialAxes;
  final double ungatedNearestMinMm;
  final double ungatedNearestMeanMm;
  final double ungatedNearestMaxMm;
  final bool usedAllFaces;
  final int scanFilteredCount;
  final double scanZThreshold;

  const SurfaceRegistrationDiagnostics({
    required this.modelBounds,
    required this.scanBounds,
    required this.modelSampleCount,
    required this.scanSampleCount,
    required this.topFacingTriangleCount,
    required this.totalTriangleCount,
    required this.pairGateMm,
    required this.bestInitialAngleDeg,
    required this.bestInitialAxes,
    required this.ungatedNearestMinMm,
    required this.ungatedNearestMeanMm,
    required this.ungatedNearestMaxMm,
    required this.usedAllFaces,
    required this.scanFilteredCount,
    required this.scanZThreshold,
  });

  String get likelyCause {
    if (modelSampleCount < 3 || scanSampleCount < 3) {
      return 'Not enough valid sampled points.';
    }
    if (!ungatedNearestMinMm.isFinite) {
      return 'No nearest-neighbor distances could be measured.';
    }
    if (ungatedNearestMinMm > pairGateMm) {
      return 'Closest model/scan distance is outside the pair gate; check '
          'coordinate axes, origin, unit scale, or whether STL and scan are '
          'from the same physical part.';
    }
    if (topFacingTriangleCount < 3 && !usedAllFaces) {
      return 'STL has few upward-facing facets; model orientation may differ '
          'from the scanner coordinate frame.';
    }
    if (scanFilteredCount > 0) {
      return 'Filtered $scanFilteredCount bed surface points (Z < ${scanZThreshold.toStringAsFixed(1)}mm). '
          'Pairs were found but residual error is too large; check scan quality and STL/physical-part consistency.';
    }
    return 'Pairs were found but residual error is too large; check scan '
        'quality and STL/physical-part consistency.';
  }
}

class Transform3D {
  final List<double> values;

  const Transform3D(this.values);

  factory Transform3D.identity() {
    return const Transform3D([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
  }

  factory Transform3D.translation(StlVector3 offset) {
    return Transform3D([
      1,
      0,
      0,
      offset.x,
      0,
      1,
      0,
      offset.y,
      0,
      0,
      1,
      offset.z,
      0,
      0,
      0,
      1,
    ]);
  }

  factory Transform3D.fromRotationAndTranslation(
    List<double> rotation,
    StlVector3 translation,
  ) {
    return Transform3D([
      rotation[0],
      rotation[1],
      rotation[2],
      translation.x,
      rotation[3],
      rotation[4],
      rotation[5],
      translation.y,
      rotation[6],
      rotation[7],
      rotation[8],
      translation.z,
      0,
      0,
      0,
      1,
    ]);
  }

  factory Transform3D.centeredYaw({
    required StlVector3 sourceCenter,
    required StlVector3 targetCenter,
    required double yaw,
  }) {
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    final rotatedCenter = StlVector3(
      c * sourceCenter.x - s * sourceCenter.y,
      s * sourceCenter.x + c * sourceCenter.y,
      sourceCenter.z,
    );
    final offset = targetCenter - rotatedCenter;
    return Transform3D([
      c,
      -s,
      0,
      offset.x,
      s,
      c,
      0,
      offset.y,
      0,
      0,
      1,
      offset.z,
      0,
      0,
      0,
      1,
    ]);
  }

  factory Transform3D.centeredRotation({
    required StlVector3 sourceCenter,
    required StlVector3 targetCenter,
    required List<double> rotation,
  }) {
    final rotatedCenter = _rotateWithMatrix(rotation, sourceCenter);
    return Transform3D.fromRotationAndTranslation(
      rotation,
      targetCenter - rotatedCenter,
    );
  }

  StlVector3 transformPoint(StlVector3 point) {
    return StlVector3(
      values[0] * point.x +
          values[1] * point.y +
          values[2] * point.z +
          values[3],
      values[4] * point.x +
          values[5] * point.y +
          values[6] * point.z +
          values[7],
      values[8] * point.x +
          values[9] * point.y +
          values[10] * point.z +
          values[11],
    );
  }

  Transform3D multiplied(Transform3D other) {
    final a = values;
    final b = other.values;
    final out = List<double>.filled(16, 0);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 4; col++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += a[row * 4 + k] * b[k * 4 + col];
        }
        out[row * 4 + col] = sum;
      }
    }
    return Transform3D(out);
  }

  List<String> formattedRows({int digits = 4}) {
    return [
      _formatRow(0, digits),
      _formatRow(4, digits),
      _formatRow(8, digits),
      _formatRow(12, digits),
    ];
  }

  String _formatRow(int start, int digits) {
    return values
        .skip(start)
        .take(4)
        .map((v) => v.toStringAsFixed(digits).padLeft(10))
        .join(' ');
  }

  static StlVector3 _rotateWithMatrix(List<double> rotation, StlVector3 point) {
    return StlVector3(
      rotation[0] * point.x + rotation[1] * point.y + rotation[2] * point.z,
      rotation[3] * point.x + rotation[4] * point.y + rotation[5] * point.z,
      rotation[6] * point.x + rotation[7] * point.y + rotation[8] * point.z,
    );
  }
}

class SurfaceRegistrationService {
  const SurfaceRegistrationService();

  SurfaceRegistrationResult register({
    required StlMesh mesh,
    required SurfaceScanResult scan,
    SurfaceRegistrationOptions options = const SurfaceRegistrationOptions(),
  }) {
    final modelSample = _sampleModelPoints(mesh, options.maxModelSamples);
    final modelPoints = modelSample.points;
    final scanSample = _sampleScanPoints(scan, options.maxScanSamples);
    final scanPoints = scanSample.points;
    if (modelPoints.length < 3 || scanPoints.length < 3) {
      throw const SurfaceRegistrationException('Need at least 3 valid points');
    }

    final gate =
        options.maxPairDistanceMm ??
        math.max(mesh.bounds.diagonal, scan.bounds.diagonal) * 0.18;

    // 如果启用skipInitialSearch，跳过初始姿态搜索，直接使用Identity变换
    final _InitialRegistration initial;
    if (options.skipInitialSearch) {
      final identityTransform = Transform3D.identity();
      final error = _registrationError(
        moving: modelPoints,
        fixed: scanPoints,
        transform: identityTransform,
        maxDistance: gate,
      );
      initial = _InitialRegistration(
        transform: identityTransform,
        rmse: error.rmse,
        matchedPairs: error.matchedPairs,
        angleDeg: 0.0,
        axesLabel: 'manual',
      );
    } else if (options.lockModelOrientation) {
      initial = _bestYawOnlyInitialTransform(
        mesh: mesh,
        scan: scan,
        modelPoints: modelPoints,
        scanPoints: scanPoints,
        yawSearchSteps: options.yawSearchSteps,
        gate: gate,
      );
    } else {
      initial = _bestInitialTransform(
        mesh: mesh,
        scan: scan,
        modelPoints: modelPoints,
        scanPoints: scanPoints,
        yawSearchSteps: options.yawSearchSteps,
        gate: gate,
      );
    }

    final initialDistances = _nearestDistanceStats(
      moving: modelPoints,
      fixed: scanPoints,
      transform: initial.transform,
    );
    var transform = initial.transform;
    var previousRmse = initial.rmse;
    var rmse = previousRmse;
    var matchedPairs = initial.matchedPairs;
    var converged = false;
    var iterations = 0;

    for (var i = 0; i < options.maxIterations; i++) {
      final pairs = _matchPairs(
        moving: modelPoints,
        fixed: scanPoints,
        transform: transform,
        maxDistance: gate,
      );
      if (pairs.length < 3) break;

      final delta = options.lockModelOrientation
          ? _estimateYawTranslationTransform(
              pairs.map((p) => p.moving).toList(growable: false),
              pairs.map((p) => p.fixed).toList(growable: false),
            )
          : _estimateRigidTransform(
              pairs.map((p) => p.moving).toList(growable: false),
              pairs.map((p) => p.fixed).toList(growable: false),
            );
      transform = delta.multiplied(transform);

      final updated = _registrationError(
        moving: modelPoints,
        fixed: scanPoints,
        transform: transform,
        maxDistance: gate,
      );
      iterations = i + 1;
      rmse = updated.rmse;
      matchedPairs = updated.matchedPairs;

      if ((previousRmse - rmse).abs() <= options.toleranceMm) {
        converged = true;
        break;
      }
      previousRmse = rmse;
    }

    return SurfaceRegistrationResult(
      initialTransform: initial.transform,
      transform: transform,
      initialRmse: initial.rmse,
      rmse: rmse,
      iterations: iterations,
      matchedPairs: matchedPairs,
      converged: converged,
      thresholdMm: options.rmseThresholdMm,
      diagnostics: SurfaceRegistrationDiagnostics(
        modelBounds: mesh.bounds,
        scanBounds: scan.bounds,
        modelSampleCount: modelPoints.length,
        scanSampleCount: scanPoints.length,
        topFacingTriangleCount: modelSample.topFacingTriangleCount,
        totalTriangleCount: mesh.triangles.length,
        pairGateMm: gate,
        bestInitialAngleDeg: initial.angleDeg,
        bestInitialAxes: initial.axesLabel,
        ungatedNearestMinMm: initialDistances.min,
        ungatedNearestMeanMm: initialDistances.mean,
        ungatedNearestMaxMm: initialDistances.max,
        usedAllFaces: modelSample.usedAllFaces,
        scanFilteredCount: scanSample.filteredCount,
        scanZThreshold: scanSample.zThreshold,
      ),
    );
  }

  _InitialRegistration _bestYawOnlyInitialTransform({
    required StlMesh mesh,
    required SurfaceScanResult scan,
    required List<StlVector3> modelPoints,
    required List<StlVector3> scanPoints,
    required int yawSearchSteps,
    required double gate,
  }) {
    final steps = math.max(1, yawSearchSteps);
    _InitialRegistration? best;
    for (var i = 0; i < steps; i++) {
      final yaw = math.pi * 2.0 * i / steps;
      final transform = Transform3D.centeredRotation(
        sourceCenter: mesh.bounds.center,
        targetCenter: scan.bounds.center,
        rotation: _yawRotation(yaw),
      );
      final error = _registrationError(
        moving: modelPoints,
        fixed: scanPoints,
        transform: transform,
        maxDistance: gate,
      );
      final candidate = _InitialRegistration(
        transform: transform,
        rmse: error.rmse,
        matchedPairs: error.matchedPairs,
        angleDeg: yaw * 180.0 / math.pi,
        axesLabel: 'locked-yaw',
      );
      if (best == null ||
          candidate.matchedPairs > best.matchedPairs ||
          (candidate.matchedPairs == best.matchedPairs &&
              candidate.rmse < best.rmse)) {
        best = candidate;
      }
    }
    return best!;
  }

  _InitialRegistration _bestInitialTransform({
    required StlMesh mesh,
    required SurfaceScanResult scan,
    required List<StlVector3> modelPoints,
    required List<StlVector3> scanPoints,
    required int yawSearchSteps,
    required double gate,
  }) {
    final steps = math.max(1, yawSearchSteps);
    _InitialRegistration? best;
    for (final base in _axisAlignedRotations()) {
      for (var i = 0; i < steps; i++) {
        final yaw = math.pi * 2.0 * i / steps;
        final rotation = _multiplyRotation(_yawRotation(yaw), base.rotation);
        final transform = Transform3D.centeredRotation(
          sourceCenter: mesh.bounds.center,
          targetCenter: scan.bounds.center,
          rotation: rotation,
        );
        final error = _registrationError(
          moving: modelPoints,
          fixed: scanPoints,
          transform: transform,
          maxDistance: gate,
        );
        final candidate = _InitialRegistration(
          transform: transform,
          rmse: error.rmse,
          matchedPairs: error.matchedPairs,
          angleDeg: yaw * 180.0 / math.pi,
          axesLabel: base.label,
        );
        if (best == null ||
            candidate.matchedPairs > best.matchedPairs ||
            (candidate.matchedPairs == best.matchedPairs &&
                candidate.rmse < best.rmse)) {
          best = candidate;
        }
      }
    }
    return best!;
  }

  _ModelSample _sampleModelPoints(StlMesh mesh, int maxSamples) {
    final topFacing = mesh.triangles
        .where((triangle) => triangle.normal.z > 0.2)
        .toList(growable: false);

    // 如果朝上面数量 < 总面数的20%，则使用所有面
    final minRequired = (mesh.triangles.length * 0.2).ceil();
    final useAllFaces = topFacing.length < math.max(3, minRequired);
    final source = useAllFaces ? mesh.triangles : topFacing;

    final triangles = _sampleTriangles(source, math.max(3, maxSamples));
    return _ModelSample(
      points: triangles
          .map((triangle) => triangle.center)
          .toList(growable: false),
      topFacingTriangleCount: topFacing.length,
      usedAllFaces: useAllFaces,
    );
  }

  List<StlTriangle> _sampleTriangles(
    List<StlTriangle> triangles,
    int maxSamples,
  ) {
    if (triangles.length <= maxSamples) return triangles;
    final result = <StlTriangle>[];
    final step = triangles.length / maxSamples;
    var cursor = 0.0;
    while (result.length < maxSamples && cursor < triangles.length) {
      result.add(triangles[cursor.floor()]);
      cursor += step;
    }
    return result;
  }

  _ScanSample _sampleScanPoints(SurfaceScanResult scan, int maxSamples) {
    final valid = scan.validPoints;

    // 计算Z值的中位数和第75百分位数，用于识别零件表面
    final zValues = valid.map((p) => p.z ?? 0.0).toList()..sort();
    final median = zValues.isNotEmpty ? zValues[zValues.length ~/ 2] : 0.0;
    final p75 = zValues.isNotEmpty ? zValues[(zValues.length * 3) ~/ 4] : 0.0;

    // 动态阈值：中位数 + (75分位 - 中位数) / 2
    // 这样可以过滤掉明显的床面点，保留零件表面点
    final zThreshold = median + (p75 - median) * 0.3;

    // 过滤低于阈值的点（床面点）
    final filtered = valid
        .where((p) => (p.z ?? 0.0) > zThreshold)
        .toList(growable: false);

    final filteredCount = valid.length - filtered.length;

    // 如果过滤后点数太少，使用所有点
    final source = filtered.length >= 10 ? filtered : valid;

    if (source.length <= maxSamples) {
      return _ScanSample(
        points: source.map(_scanPointToVector).toList(growable: false),
        filteredCount: filteredCount,
        zThreshold: zThreshold,
      );
    }

    final out = <StlVector3>[];
    final step = source.length / maxSamples;
    var cursor = 0.0;
    while (out.length < maxSamples && cursor < source.length) {
      out.add(_scanPointToVector(source[cursor.floor()]));
      cursor += step;
    }

    return _ScanSample(
      points: out,
      filteredCount: filteredCount,
      zThreshold: zThreshold,
    );
  }

  StlVector3 _scanPointToVector(SurfaceScanPoint point) {
    return StlVector3(point.x, point.y, point.z ?? 0);
  }

  _RegistrationError _registrationError({
    required List<StlVector3> moving,
    required List<StlVector3> fixed,
    required Transform3D transform,
    required double maxDistance,
  }) {
    var sum = 0.0;
    var count = 0;
    final maxDistanceSq = maxDistance * maxDistance;
    for (final point in moving) {
      final moved = transform.transformPoint(point);
      final nearest = _nearest(moved, fixed);
      if (nearest.distanceSq > maxDistanceSq) continue;
      sum += nearest.distanceSq;
      count++;
    }
    if (count == 0) {
      return const _RegistrationError(rmse: double.infinity, matchedPairs: 0);
    }
    return _RegistrationError(
      rmse: math.sqrt(sum / count),
      matchedPairs: count,
    );
  }

  _DistanceStats _nearestDistanceStats({
    required List<StlVector3> moving,
    required List<StlVector3> fixed,
    required Transform3D transform,
  }) {
    if (moving.isEmpty || fixed.isEmpty) {
      return const _DistanceStats(
        min: double.infinity,
        mean: double.infinity,
        max: double.infinity,
      );
    }
    var minDistance = double.infinity;
    var maxDistance = 0.0;
    var sum = 0.0;
    for (final point in moving) {
      final nearest = _nearest(transform.transformPoint(point), fixed);
      final distance = math.sqrt(nearest.distanceSq);
      minDistance = math.min(minDistance, distance);
      maxDistance = math.max(maxDistance, distance);
      sum += distance;
    }
    return _DistanceStats(
      min: minDistance,
      mean: sum / moving.length,
      max: maxDistance,
    );
  }

  List<_PointPair> _matchPairs({
    required List<StlVector3> moving,
    required List<StlVector3> fixed,
    required Transform3D transform,
    required double maxDistance,
  }) {
    final pairs = <_PointPair>[];
    final maxDistanceSq = maxDistance * maxDistance;
    for (final point in moving) {
      final moved = transform.transformPoint(point);
      final nearest = _nearest(moved, fixed);
      if (nearest.distanceSq <= maxDistanceSq) {
        pairs.add(_PointPair(moved, nearest.point));
      }
    }
    return pairs;
  }

  _NearestPoint _nearest(StlVector3 point, List<StlVector3> candidates) {
    var best = candidates.first;
    var bestDistance = _distanceSq(point, best);
    for (var i = 1; i < candidates.length; i++) {
      final candidate = candidates[i];
      final distance = _distanceSq(point, candidate);
      if (distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return _NearestPoint(best, bestDistance);
  }

  double _distanceSq(StlVector3 a, StlVector3 b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    final dz = a.z - b.z;
    return dx * dx + dy * dy + dz * dz;
  }

  Transform3D _estimateRigidTransform(
    List<StlVector3> moving,
    List<StlVector3> fixed,
  ) {
    final movingCenter = _centroid(moving);
    final fixedCenter = _centroid(fixed);
    var sxx = 0.0;
    var sxy = 0.0;
    var sxz = 0.0;
    var syx = 0.0;
    var syy = 0.0;
    var syz = 0.0;
    var szx = 0.0;
    var szy = 0.0;
    var szz = 0.0;

    for (var i = 0; i < moving.length; i++) {
      final a = moving[i] - movingCenter;
      final b = fixed[i] - fixedCenter;
      sxx += a.x * b.x;
      sxy += a.x * b.y;
      sxz += a.x * b.z;
      syx += a.y * b.x;
      syy += a.y * b.y;
      syz += a.y * b.z;
      szx += a.z * b.x;
      szy += a.z * b.y;
      szz += a.z * b.z;
    }

    final q = _largestEigenQuaternion([
      [sxx + syy + szz, syz - szy, szx - sxz, sxy - syx],
      [syz - szy, sxx - syy - szz, sxy + syx, szx + sxz],
      [szx - sxz, sxy + syx, -sxx + syy - szz, syz + szy],
      [sxy - syx, szx + sxz, syz + szy, -sxx - syy + szz],
    ]);
    final rotation = _quaternionToMatrix(q);
    final rotatedCenter = _applyRotation(rotation, movingCenter);
    final t = fixedCenter - rotatedCenter;

    return Transform3D([
      rotation[0],
      rotation[1],
      rotation[2],
      t.x,
      rotation[3],
      rotation[4],
      rotation[5],
      t.y,
      rotation[6],
      rotation[7],
      rotation[8],
      t.z,
      0,
      0,
      0,
      1,
    ]);
  }

  Transform3D _estimateYawTranslationTransform(
    List<StlVector3> moving,
    List<StlVector3> fixed,
  ) {
    final movingCenter = _centroid(moving);
    final fixedCenter = _centroid(fixed);
    var cosTerm = 0.0;
    var sinTerm = 0.0;

    for (var i = 0; i < moving.length; i++) {
      final a = moving[i] - movingCenter;
      final b = fixed[i] - fixedCenter;
      cosTerm += a.x * b.x + a.y * b.y;
      sinTerm += a.x * b.y - a.y * b.x;
    }

    final yaw = math.atan2(sinTerm, cosTerm);
    final rotation = _yawRotation(yaw);
    final rotatedCenter = _applyRotation(rotation, movingCenter);
    final translation = fixedCenter - rotatedCenter;
    return Transform3D.fromRotationAndTranslation(rotation, translation);
  }

  StlVector3 _centroid(List<StlVector3> points) {
    var sum = const StlVector3(0, 0, 0);
    for (final point in points) {
      sum = sum + point;
    }
    final inv = 1.0 / points.length;
    return sum * inv;
  }

  List<double> _largestEigenQuaternion(List<List<double>> matrix) {
    var q = [1.0, 0.0, 0.0, 0.0];
    for (var iter = 0; iter < 64; iter++) {
      final next = List<double>.filled(4, 0);
      for (var row = 0; row < 4; row++) {
        for (var col = 0; col < 4; col++) {
          next[row] += matrix[row][col] * q[col];
        }
      }
      final length = math.sqrt(next.fold(0.0, (sum, v) => sum + v * v));
      if (length <= 1e-12) return q;
      q = next.map((v) => v / length).toList(growable: false);
    }
    return q;
  }

  List<double> _quaternionToMatrix(List<double> q) {
    final w = q[0];
    final x = q[1];
    final y = q[2];
    final z = q[3];
    return [
      1 - 2 * (y * y + z * z),
      2 * (x * y - z * w),
      2 * (x * z + y * w),
      2 * (x * y + z * w),
      1 - 2 * (x * x + z * z),
      2 * (y * z - x * w),
      2 * (x * z - y * w),
      2 * (y * z + x * w),
      1 - 2 * (x * x + y * y),
    ];
  }

  StlVector3 _applyRotation(List<double> rotation, StlVector3 point) {
    return StlVector3(
      rotation[0] * point.x + rotation[1] * point.y + rotation[2] * point.z,
      rotation[3] * point.x + rotation[4] * point.y + rotation[5] * point.z,
      rotation[6] * point.x + rotation[7] * point.y + rotation[8] * point.z,
    );
  }

  List<double> _yawRotation(double yaw) {
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    return [c, -s, 0, s, c, 0, 0, 0, 1];
  }

  List<double> _multiplyRotation(List<double> a, List<double> b) {
    final out = List<double>.filled(9, 0);
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        out[row * 3 + col] =
            a[row * 3] * b[col] +
            a[row * 3 + 1] * b[3 + col] +
            a[row * 3 + 2] * b[6 + col];
      }
    }
    return out;
  }

  List<_AxisRotation> _axisAlignedRotations() {
    const axes = [
      StlVector3(1, 0, 0),
      StlVector3(-1, 0, 0),
      StlVector3(0, 1, 0),
      StlVector3(0, -1, 0),
      StlVector3(0, 0, 1),
      StlVector3(0, 0, -1),
    ];
    final result = <_AxisRotation>[];
    for (final xAxis in axes) {
      for (final yAxis in axes) {
        if (xAxis.dot(yAxis).abs() > 1e-9) continue;
        final zAxis = StlVector3.cross(xAxis, yAxis);
        if (zAxis.length <= 1e-9) continue;
        result.add(
          _AxisRotation(
            rotation: [
              xAxis.x,
              xAxis.y,
              xAxis.z,
              yAxis.x,
              yAxis.y,
              yAxis.z,
              zAxis.x,
              zAxis.y,
              zAxis.z,
            ],
            label:
                'X${_axisLabel(xAxis)} Y${_axisLabel(yAxis)} '
                'Z${_axisLabel(zAxis)}',
          ),
        );
      }
    }
    return result;
  }

  String _axisLabel(StlVector3 axis) {
    if (axis.x > 0.5) return '+X';
    if (axis.x < -0.5) return '-X';
    if (axis.y > 0.5) return '+Y';
    if (axis.y < -0.5) return '-Y';
    if (axis.z > 0.5) return '+Z';
    return '-Z';
  }
}

class SurfaceRegistrationException implements Exception {
  final String message;

  const SurfaceRegistrationException(this.message);

  @override
  String toString() => message;
}

class _InitialRegistration {
  final Transform3D transform;
  final double rmse;
  final int matchedPairs;
  final double angleDeg;
  final String axesLabel;

  const _InitialRegistration({
    required this.transform,
    required this.rmse,
    required this.matchedPairs,
    required this.angleDeg,
    required this.axesLabel,
  });
}

class _ModelSample {
  final List<StlVector3> points;
  final int topFacingTriangleCount;
  final bool usedAllFaces;

  const _ModelSample({
    required this.points,
    required this.topFacingTriangleCount,
    required this.usedAllFaces,
  });
}

class _ScanSample {
  final List<StlVector3> points;
  final int filteredCount;
  final double zThreshold;

  const _ScanSample({
    required this.points,
    required this.filteredCount,
    required this.zThreshold,
  });
}

class _RegistrationError {
  final double rmse;
  final int matchedPairs;

  const _RegistrationError({required this.rmse, required this.matchedPairs});
}

class _PointPair {
  final StlVector3 moving;
  final StlVector3 fixed;

  const _PointPair(this.moving, this.fixed);
}

class _NearestPoint {
  final StlVector3 point;
  final double distanceSq;

  const _NearestPoint(this.point, this.distanceSq);
}

class _DistanceStats {
  final double min;
  final double mean;
  final double max;

  const _DistanceStats({
    required this.min,
    required this.mean,
    required this.max,
  });
}

class _AxisRotation {
  final List<double> rotation;
  final String label;

  const _AxisRotation({required this.rotation, required this.label});
}
