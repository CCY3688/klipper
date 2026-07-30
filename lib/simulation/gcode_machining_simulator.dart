import 'dart:math' as math;

import '../ui/surface/stl_mesh.dart';
import 'delta_kinematics.dart';

class SimVector3 {
  final double x;
  final double y;
  final double z;

  const SimVector3(this.x, this.y, this.z);

  SimVector3 operator +(SimVector3 other) =>
      SimVector3(x + other.x, y + other.y, z + other.z);

  SimVector3 operator -(SimVector3 other) =>
      SimVector3(x - other.x, y - other.y, z - other.z);

  SimVector3 operator *(double scale) =>
      SimVector3(x * scale, y * scale, z * scale);

  double dot(SimVector3 other) => x * other.x + y * other.y + z * other.z;

  double get length => math.sqrt(dot(this));

  SimVector3 normalized() {
    final magnitude = length;
    return magnitude <= 1e-9
        ? const SimVector3(0, 0, 0)
        : this * (1 / magnitude);
  }

  static SimVector3 cross(SimVector3 a, SimVector3 b) => SimVector3(
    a.y * b.z - a.z * b.y,
    a.z * b.x - a.x * b.z,
    a.x * b.y - a.y * b.x,
  );

  StlVector3 toStl() => StlVector3(x, y, z);
}

/// The bounding-box face of the workpiece that is supported by the bed.
/// The selected outward normal is rotated to machine -Z, which is the
/// downward-facing contact direction for a workpiece resting on a horizontal bed.
enum WorkpieceBedFace { posX, negX, posY, negY, posZ, negZ, custom }

extension WorkpieceBedFaceDetails on WorkpieceBedFace {
  String get label => switch (this) {
    WorkpieceBedFace.posX => '+X',
    WorkpieceBedFace.negX => '-X',
    WorkpieceBedFace.posY => '+Y',
    WorkpieceBedFace.negY => '-Y',
    WorkpieceBedFace.posZ => '+Z',
    WorkpieceBedFace.negZ => '-Z',
    WorkpieceBedFace.custom => '自定义法线',
  };

  String get description => switch (this) {
    WorkpieceBedFace.posX => '模型 +X 包围面接触床面',
    WorkpieceBedFace.negX => '模型 -X 包围面接触床面',
    WorkpieceBedFace.posY => '模型 +Y 包围面接触床面',
    WorkpieceBedFace.negY => '模型 -Y 包围面接触床面',
    WorkpieceBedFace.posZ => '模型 +Z 包围面接触床面',
    WorkpieceBedFace.negZ => '模型 -Z 包围面接触床面',
    WorkpieceBedFace.custom => '按输入的 STL 接触面法线对齐床面',
  };
}

class WorkpiecePlacement {
  final WorkpieceBedFace bedFace;
  final double centerXmm;
  final double centerYmm;
  final double bedZmm;
  final double yawDeg;
  final SimVector3 contactNormal;

  const WorkpiecePlacement({
    this.bedFace = WorkpieceBedFace.negZ,
    this.centerXmm = 0,
    this.centerYmm = 0,
    this.bedZmm = 0,
    this.yawDeg = 0,
    this.contactNormal = const SimVector3(0, 0, -1),
  });
}

/// Rigid STL-to-machine transform derived from the selected bed face.
/// It first centres the source bounds, rotates the selected face downwards,
/// applies a bed-plane yaw, and finally places its XY bounds centre and Z
/// contact plane at the requested machine coordinates.
class WorkpieceTransform {
  final WorkpiecePlacement placement;
  final StlBounds transformedBounds;
  final SimVector3 _sourceCenter;
  final SimVector3 _translation;

  WorkpieceTransform._({
    required this.placement,
    required StlBounds sourceBounds,
    required this.transformedBounds,
    required SimVector3 translation,
  }) : _sourceCenter = SimVector3(
         sourceBounds.center.x,
         sourceBounds.center.y,
         sourceBounds.center.z,
       ),
       _translation = translation;

  factory WorkpieceTransform.fromMesh(
    StlMesh mesh,
    WorkpiecePlacement placement,
  ) {
    final source = mesh.bounds;
    final sourceCenter = source.center;
    final corners = <StlVector3>[
      StlVector3(source.minX, source.minY, source.minZ),
      StlVector3(source.maxX, source.minY, source.minZ),
      StlVector3(source.maxX, source.maxY, source.minZ),
      StlVector3(source.minX, source.maxY, source.minZ),
      StlVector3(source.minX, source.minY, source.maxZ),
      StlVector3(source.maxX, source.minY, source.maxZ),
      StlVector3(source.maxX, source.maxY, source.maxZ),
      StlVector3(source.minX, source.maxY, source.maxZ),
    ];
    final rotated = corners
        .map(
          (point) => _orient(
            SimVector3(
              point.x - sourceCenter.x,
              point.y - sourceCenter.y,
              point.z - sourceCenter.z,
            ),
            placement,
          ),
        )
        .toList(growable: false);
    final minX = rotated.map((point) => point.x).reduce(math.min);
    final maxX = rotated.map((point) => point.x).reduce(math.max);
    final minY = rotated.map((point) => point.y).reduce(math.min);
    final maxY = rotated.map((point) => point.y).reduce(math.max);
    final minZ = rotated.map((point) => point.z).reduce(math.min);
    final maxZ = rotated.map((point) => point.z).reduce(math.max);
    final translation = SimVector3(
      placement.centerXmm - (minX + maxX) / 2,
      placement.centerYmm - (minY + maxY) / 2,
      placement.bedZmm - minZ,
    );
    return WorkpieceTransform._(
      placement: placement,
      sourceBounds: source,
      transformedBounds: StlBounds(
        minX: minX + translation.x,
        maxX: maxX + translation.x,
        minY: minY + translation.y,
        maxY: maxY + translation.y,
        minZ: minZ + translation.z,
        maxZ: maxZ + translation.z,
      ),
      translation: translation,
    );
  }

  SimVector3 transform(StlVector3 source) =>
      _orient(
        SimVector3(
          source.x - _sourceCenter.x,
          source.y - _sourceCenter.y,
          source.z - _sourceCenter.z,
        ),
        placement,
      ) +
      _translation;

  static SimVector3 _orient(SimVector3 point, WorkpiecePlacement placement) {
    final faceAligned = switch (placement.bedFace) {
      WorkpieceBedFace.negZ => point,
      WorkpieceBedFace.posZ => SimVector3(point.x, -point.y, -point.z),
      WorkpieceBedFace.posX => SimVector3(point.z, point.y, -point.x),
      WorkpieceBedFace.negX => SimVector3(-point.z, point.y, point.x),
      WorkpieceBedFace.posY => SimVector3(point.x, point.z, -point.y),
      WorkpieceBedFace.negY => SimVector3(point.x, -point.z, point.y),
      WorkpieceBedFace.custom => _alignNormalToBed(
        point,
        placement.contactNormal,
      ),
    };
    final yaw = placement.yawDeg * math.pi / 180;
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    return SimVector3(
      faceAligned.x * c - faceAligned.y * s,
      faceAligned.x * s + faceAligned.y * c,
      faceAligned.z,
    );
  }

  static SimVector3 _alignNormalToBed(SimVector3 point, SimVector3 normal) {
    final from = normal.normalized();
    if (from.length <= 1e-9) {
      throw ArgumentError('Custom contact normal must not be zero.');
    }
    const target = SimVector3(0, 0, -1);
    final cosine = from.dot(target).clamp(-1.0, 1.0);
    final axis = SimVector3.cross(from, target);
    final sine = axis.length;
    if (sine <= 1e-9) {
      return cosine > 0 ? point : SimVector3(point.x, -point.y, -point.z);
    }
    final unitAxis = axis * (1 / sine);
    return point * cosine +
        SimVector3.cross(unitAxis, point) * sine +
        unitAxis * (unitAxis.dot(point) * (1 - cosine));
  }
}

class SimMove {
  final int lineNumber;
  final SimVector3 start;
  final SimVector3 end;
  final bool rapid;
  final bool processing;
  final double feedMmPerMin;
  final double yawDeg;
  final double pitchDeg;

  const SimMove({
    required this.lineNumber,
    required this.start,
    required this.end,
    required this.rapid,
    required this.processing,
    required this.feedMmPerMin,
    required this.yawDeg,
    required this.pitchDeg,
  });

  double get length => (end - start).length;
}

class GcodeSimulationProgram {
  final List<SimMove> moves;
  final List<String> warnings;

  const GcodeSimulationProgram({required this.moves, required this.warnings});

  factory GcodeSimulationProgram.parse(
    String source, {
    bool linearMovesAreProcessing = true,
  }) {
    var position = const SimVector3(0, 0, 0);
    var absolute = true;
    var feed = 1200.0;
    var toolOn = linearMovesAreProcessing;
    var yaw = 90.0;
    var pitch = 90.0;
    final moves = <SimMove>[];
    final warnings = <String>[];
    final word = RegExp(
      r'([A-Za-z])\s*([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)',
    );

    for (var index = 0; index < source.split('\n').length; index++) {
      var line = source.split('\n')[index];
      line = line.split(';').first.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
      if (line.isEmpty) continue;
      final upper = line.toUpperCase();
      if (upper.contains('G90')) {
        absolute = true;
      }
      if (upper.contains('G91')) {
        absolute = false;
      }
      if (upper.startsWith('M3') || upper.startsWith('M4')) toolOn = true;
      if (upper.startsWith('M5')) toolOn = false;
      if (upper.startsWith('SET_PIN')) {
        final value = RegExp(
          r'VALUE\s*=\s*([-+]?\d*\.?\d+)',
          caseSensitive: false,
        ).firstMatch(line);
        if (value != null) toolOn = (double.tryParse(value.group(1)!) ?? 0) > 0;
      }
      if (upper.startsWith('SET_SERVO')) {
        final angle = RegExp(
          r'ANGLE\s*=\s*([-+]?\d*\.?\d+)',
          caseSensitive: false,
        ).firstMatch(line);
        if (angle != null) {
          final value = double.tryParse(angle.group(1)!);
          if (value != null) {
            if (upper.contains('CARTRIDGE') || upper.contains('YAW')) {
              yaw = value;
            }
            if (upper.contains('PEN') || upper.contains('PITCH')) {
              pitch = value;
            }
          }
        }
      }
      final isRapid = RegExp(
        r'^G0(?:0)?(?:\s|$)',
        caseSensitive: false,
      ).hasMatch(line);
      final isLinear = RegExp(
        r'^G0?1(?:\s|$)',
        caseSensitive: false,
      ).hasMatch(line);
      if (!isRapid && !isLinear) continue;
      final words = <String, double>{
        for (final match in word.allMatches(line))
          match.group(1)!.toUpperCase(): double.parse(match.group(2)!),
      };
      feed = words['F'] ?? feed;
      final target = SimVector3(
        _coordinate(words['X'], position.x, absolute),
        _coordinate(words['Y'], position.y, absolute),
        _coordinate(words['Z'], position.z, absolute),
      );
      if ((target - position).length > 1e-8) {
        moves.add(
          SimMove(
            lineNumber: index + 1,
            start: position,
            end: target,
            rapid: isRapid,
            processing: isLinear && toolOn,
            feedMmPerMin: feed,
            yawDeg: yaw,
            pitchDeg: pitch,
          ),
        );
      }
      position = target;
    }
    if (moves.isEmpty) warnings.add('No G0/G1 Cartesian moves were found.');
    return GcodeSimulationProgram(moves: moves, warnings: warnings);
  }

  static double _coordinate(double? value, double previous, bool absolute) {
    if (value == null) return previous;
    return absolute ? value : previous + value;
  }
}

class MachiningSimulationOptions {
  final DeltaGeometry geometry;
  final double toolRadiusMm;
  final double tcpOffsetZMm;
  final double sampleStepMm;
  final bool linearMovesAreProcessing;
  final WorkpiecePlacement workpiecePlacement;

  const MachiningSimulationOptions({
    this.geometry = const DeltaGeometry(),
    this.toolRadiusMm = 1.0,
    this.tcpOffsetZMm = 0,
    this.sampleStepMm = 2.0,
    this.linearMovesAreProcessing = true,
    this.workpiecePlacement = const WorkpiecePlacement(),
  });
}

class MachiningSimulationResult {
  final GcodeSimulationProgram program;
  final List<bool> contactedFaces;
  final List<int> invalidMoveIndexes;
  final List<String> errors;
  final int sampledPoses;
  final int reachablePoses;
  final double pathLengthMm;
  final double processingLengthMm;

  const MachiningSimulationResult({
    required this.program,
    required this.contactedFaces,
    required this.invalidMoveIndexes,
    required this.errors,
    required this.sampledPoses,
    required this.reachablePoses,
    required this.pathLengthMm,
    required this.processingLengthMm,
  });

  bool get kinematicsValid => invalidMoveIndexes.isEmpty;
  bool get hasMeshContact => contactedFaces.any((value) => value);
  int get contactedFaceCount => contactedFaces.where((value) => value).length;
  double get faceCoverage =>
      contactedFaces.isEmpty ? 0 : contactedFaceCount / contactedFaces.length;
}

class GcodeMachiningSimulator {
  MachiningSimulationResult run({
    required String gcode,
    required StlMesh? mesh,
    required MachiningSimulationOptions options,
  }) {
    final program = GcodeSimulationProgram.parse(
      gcode,
      linearMovesAreProcessing: options.linearMovesAreProcessing,
    );
    final kinematics = DeltaKinematics(options.geometry);
    final transform = mesh == null
        ? null
        : WorkpieceTransform.fromMesh(mesh, options.workpiecePlacement);
    final contact = List<bool>.filled(mesh?.faceCount ?? 0, false);
    final invalid = <int>[];
    final errors = <String>[...program.warnings];
    var samples = 0;
    var reachable = 0;
    var pathLength = 0.0;
    var processingLength = 0.0;

    for (var moveIndex = 0; moveIndex < program.moves.length; moveIndex++) {
      final move = program.moves[moveIndex];
      final length = move.length;
      pathLength += length;
      if (move.processing) processingLength += length;
      final count = math.max(
        1,
        (length / options.sampleStepMm.clamp(0.1, 20)).ceil(),
      );
      var moveValid = true;
      for (var i = 0; i <= count; i++) {
        final t = i / count;
        final point = move.start + (move.end - move.start) * t;
        final tcp = SimVector3(
          point.x,
          point.y,
          point.z + options.tcpOffsetZMm,
        );
        samples++;
        if (kinematics.inverse(tcp.x, tcp.y, tcp.z).isReachable) {
          reachable++;
        } else {
          moveValid = false;
        }
      }
      if (!moveValid) {
        invalid.add(moveIndex);
        errors.add(
          'G-code line ${move.lineNumber} leaves the configured Delta workspace.',
        );
      }
      if (mesh != null && move.processing) {
        for (var face = 0; face < mesh.triangles.length; face++) {
          if (contact[face]) continue;
          final target = transform!.transform(mesh.triangles[face].center);
          if (_distanceToSegment(target, move.start, move.end) <=
              options.toolRadiusMm) {
            contact[face] = true;
          }
        }
      }
    }
    if (mesh != null && !contact.any((value) => value)) {
      errors.add(
        'No STL faces intersect the processing tool sweep. Check fixture offset, Z datum and tool radius.',
      );
    }
    return MachiningSimulationResult(
      program: program,
      contactedFaces: contact,
      invalidMoveIndexes: invalid,
      errors: errors,
      sampledPoses: samples,
      reachablePoses: reachable,
      pathLengthMm: pathLength,
      processingLengthMm: processingLength,
    );
  }

  double _distanceToSegment(
    SimVector3 point,
    SimVector3 start,
    SimVector3 end,
  ) {
    final segment = end - start;
    final denom = segment.dot(segment);
    if (denom <= 1e-12) return (point - start).length;
    final t = ((point - start).dot(segment) / denom).clamp(0.0, 1.0);
    return (point - (start + segment * t)).length;
  }
}
