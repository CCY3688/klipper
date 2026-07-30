import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../state/camera_viewer_controller.dart';
import '../../state/printer_controller.dart';
import '../fluidd/widgets/fluidd_card.dart';
import 'dxf_toolpath.dart';
import 'stl_mesh.dart';
import 'stl_parser.dart';
import 'surface_motion_preflight.dart';
import 'surface_orientation_gcode.dart';
import 'surface_preview.dart';
import 'surface_tool_orientation.dart';

class _SurfaceBedZCalibrationRecord {
  const _SurfaceBedZCalibrationRecord({
    required this.touchZ,
    required this.bedZ,
    required this.calibratedAt,
    required this.source,
  });

  final double? touchZ;
  final double bedZ;
  final DateTime? calibratedAt;
  final String? source;

  Map<String, Object?> toJson() => {
    'source': source,
    'created_at': calibratedAt?.toIso8601String(),
    'touch_machine_z_mm': touchZ,
    'reference_surface_height_mm': 0.0,
    'bed_z_mm': bedZ,
  };

  static _SurfaceBedZCalibrationRecord? fromJson(Object? value) {
    if (value is! Map) return null;
    final bedZ = (value['bed_z_mm'] as num?)?.toDouble();
    if (bedZ == null || !bedZ.isFinite) return null;
    final touchZ = (value['touch_machine_z_mm'] as num?)?.toDouble();
    final createdAtText = value['created_at'] as String?;
    return _SurfaceBedZCalibrationRecord(
      touchZ: touchZ != null && touchZ.isFinite ? touchZ : null,
      bedZ: bedZ,
      calibratedAt: createdAtText == null
          ? null
          : DateTime.tryParse(createdAtText),
      source: value['source'] as String?,
    );
  }
}

class SurfacePage extends StatefulWidget {
  const SurfacePage({super.key});

  @override
  State<SurfacePage> createState() => _SurfacePageState();
}

class _SurfacePageState extends State<SurfacePage> {
  static const double _pasteSyringeInnerDiameterMm = 15.6;
  static const double _pasteSyringeAreaMm2 =
      math.pi *
      _pasteSyringeInnerDiameterMm *
      _pasteSyringeInnerDiameterMm /
      4.0;
  static const double _pasteStepperAccelMmPerS2 = 30.0;
  static const double _defaultSurfaceBedZ = -30.0;
  static const double _surfacePastePrimeRetractMaxUl = 500.0;
  static const String _kSurfacePasteUlPerMm = 'surface.paste_test.ul_per_mm';
  static const String _kSurfacePasteStartPrimeUl =
      'surface.paste_test.start_prime_ul';
  static const String _kSurfacePasteStartPrimeRateUlPerS =
      'surface.paste_test.start_prime_rate_ul_per_s';
  static const String _kSurfacePasteStartBoostUl =
      'surface.paste_test.start_boost_ul';
  static const String _kSurfacePasteStartBoostDistanceMm =
      'surface.paste_test.start_boost_distance_mm';
  static const String _kSurfacePasteCoastDistanceMm =
      'surface.paste_test.coast_distance_mm';
  static const String _kSurfacePasteStopRetractUl =
      'surface.paste_test.stop_retract_ul';
  static const String _kSurfacePasteStopRetractRateUlPerS =
      'surface.paste_test.stop_retract_rate_ul_per_s';
  static const String _kSurfacePasteStopDwellMs =
      'surface.paste_test.stop_dwell_ms';
  static const String _kSurfacePasteStartDwellMs =
      'surface.paste_test.start_dwell_ms';
  static const String _kSurfacePasteReturnDwellMs =
      'surface.paste_test.return_dwell_ms';

  StlMesh? _mesh;
  String? _meshName;
  String? _meshPath;
  bool _loading = false;
  String? _error;
  bool _platformClearedForPhoto = false;
  bool _capturingWorkpiece = false;
  Uint8List? _workpiecePhotoBytes;
  String? _workpiecePhotoPath;
  DateTime? _workpiecePhotoAt;
  String? _workpiecePhotoError;
  Size? _workpieceImageSize;
  bool _showActualVerificationTrajectory = true;
  _ContactFace _contactFace = _ContactFace.zMin;
  bool _showLocalizationHeightMap = true;
  bool _showLocalizationMesh = true;
  bool _showLocalizationAxes = true;
  bool _showLocalizationBounds = true;
  bool _showLocalizationHandles = true;
  _AlignmentHandleId? _lockedAlignmentHandle;
  Offset _localizationOffsetPx = Offset.zero;
  double _localizationYawDeg = 0.0;
  double _localizationScalePxPerMm = 2.0;
  double _localizationOpacity = 0.86;
  String? _localizationResultPath;
  String? _localizationError;
  Timer? _localizationAutosaveTimer;
  _SurfacePattern _surfacePattern = _SurfacePattern.line;
  _SurfaceTrajectorySource _surfaceTrajectorySource =
      _SurfaceTrajectorySource.pattern;
  DxfToolpath? _dxfToolpath;
  String? _dxfPath;
  String? _dxfWarning;
  String? _dxfError;
  bool _dxfLoading = false;
  bool _dxfKeepAspectRatio = true;
  double _surfacePatternWidthMm = 40.0;
  double _surfacePatternHeightMm = 20.0;
  Offset _surfacePatternCenterLocal = Offset.zero;
  double _surfacePatternRotationDeg = 0.0;
  double _surfaceClearanceMm = 3.0;
  double _surfaceSampleStepMm = 2.0;
  static const double _surfaceBedZSameToolheadToleranceMm = 0.01;
  final Map<SurfaceBedZToolheadKind, _SurfaceBedZCalibrationRecord>
  _surfaceBedZCalibrations = {};
  double _surfaceBedZ = _defaultSurfaceBedZ;
  double? _surfaceBedZCalibrationTouchZ;
  DateTime? _surfaceBedZCalibrationAt;
  String? _surfaceBedZCalibrationPath;
  String? _surfaceBedZCalibrationMessage;
  String? _surfaceBedZCalibrationError;
  bool _surfaceBedZCalibrationBusy = false;
  double _surfaceTravelSpeedMmPerS = 40.0;
  double _surfaceWorkSpeedMmPerS = 20.0;
  double _surfaceSmoothStepMm = 0.8;
  double _surfaceSmoothMaxZStepMm = 0.20;
  SurfaceToolOrientationConfig _surfaceToolOrientation =
      const SurfaceToolOrientationConfig();
  SurfaceToolOrientationSummary? _surfaceToolOrientationSummary;
  List<_SurfaceToolPoint> _surfaceTrajectory = const [];
  List<_SurfaceToolPoint> _surfaceMotionTrajectory = const [];
  String? _surfaceTrajectoryError;
  String? _surfaceMotionError;
  bool _surfaceOneClickStarting = false;
  bool _surfaceHomingStatusRefreshing = false;
  String? _surfaceOneClickStatus;
  bool _surfacePasteTestStarting = false;
  String? _surfacePasteTestStatus;
  double _surfacePasteUlPerMm = 1.0;
  double _surfacePasteStartPrimeUl = 35.0;
  double _surfacePasteStartPrimeRateUlPerS = 80.0;
  double _surfacePasteStartBoostUl = 8.0;
  double _surfacePasteStartBoostDistanceMm = 10.0;
  double _surfacePasteCoastDistanceMm = 6.0;
  double _surfacePasteStopRetractUl = 40.0;
  double _surfacePasteStopRetractRateUlPerS = 120.0;
  double _surfacePasteStopDwellMs = 300.0;
  double _surfacePasteStartDwellMs = 0.0;
  double _surfacePasteReturnDwellMs = 0.0;
  String? _surfaceTrajectoryPath;
  String? _surfaceGcodePath;
  double _verificationSettleSeconds = 1.0;
  double _verificationSpacingMm = 10.0;
  int _verificationMaxCaptures = 30;
  bool _verificationRunning = false;
  int _verificationProgress = 0;
  String? _verificationError;
  String? _verificationResultPath;
  Map<String, dynamic>? _verificationResult;
  bool _applySurfaceCommandCorrection = false;
  bool _showGcodeTrajectory = true;
  bool _showGcodeZMap = true;
  bool _interpolateGcodeZMapVertices = true;
  bool _showToolReachabilityOverlay = false;
  _SurfaceReachabilityOverlay? _surfaceReachabilityOverlay;
  _SurfaceReachabilityOverlayKey? _surfaceReachabilityOverlayKey;
  _SurfaceCommandCorrection? _surfaceCommandCorrection;
  bool _surfaceFilesLoading = false;
  String? _surfaceFilesError;
  List<_SurfaceFileGroup> _surfaceFileGroups = const [];

  int _workspaceView = 0;
  SurfacePreviewMode _previewMode = SurfacePreviewMode.combined;
  bool _showBounds = true;
  bool _showAxes = true;
  late final TransformationController _photoTransformController;
  late final TransformationController _localizationTransformController;
  TransformationController? _trajectoryTransformController;

  double _rotationX = -0.72;
  double _rotationY = 0.0;
  double _rotationZ = -0.72;
  double _zoom = 1.0;
  Offset _pan = Offset.zero;

  double _gestureStartZoom = 1.0;
  Offset _gestureStartPan = Offset.zero;
  Offset _gestureStartFocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    _photoTransformController = TransformationController();
    _localizationTransformController = TransformationController();
    unawaited(_loadSurfaceBedZCalibration());
    unawaited(_loadSurfacePasteSettings());
    unawaited(_refreshSurfaceFiles());
  }

  @override
  void dispose() {
    _localizationAutosaveTimer?.cancel();
    _photoTransformController.dispose();
    _localizationTransformController.dispose();
    _trajectoryTransformController?.dispose();
    super.dispose();
  }

  TransformationController get _trajectoryController =>
      _trajectoryTransformController ??= TransformationController();

  Future<void> _loadSurfacePasteSettings() async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _surfacePasteUlPerMm =
          sp.getDouble(_kSurfacePasteUlPerMm) ?? _surfacePasteUlPerMm;
      _surfacePasteStartPrimeUl =
          sp.getDouble(_kSurfacePasteStartPrimeUl) ?? _surfacePasteStartPrimeUl;
      _surfacePasteStartPrimeRateUlPerS =
          sp.getDouble(_kSurfacePasteStartPrimeRateUlPerS) ??
          _surfacePasteStartPrimeRateUlPerS;
      _surfacePasteStartBoostUl =
          sp.getDouble(_kSurfacePasteStartBoostUl) ?? _surfacePasteStartBoostUl;
      _surfacePasteStartBoostDistanceMm =
          sp.getDouble(_kSurfacePasteStartBoostDistanceMm) ??
          _surfacePasteStartBoostDistanceMm;
      _surfacePasteCoastDistanceMm =
          sp.getDouble(_kSurfacePasteCoastDistanceMm) ??
          _surfacePasteCoastDistanceMm;
      _surfacePasteStopRetractUl =
          sp.getDouble(_kSurfacePasteStopRetractUl) ??
          _surfacePasteStopRetractUl;
      _surfacePasteStopRetractRateUlPerS =
          sp.getDouble(_kSurfacePasteStopRetractRateUlPerS) ??
          _surfacePasteStopRetractRateUlPerS;
      _surfacePasteStopDwellMs =
          sp.getDouble(_kSurfacePasteStopDwellMs) ?? _surfacePasteStopDwellMs;
      _surfacePasteStartDwellMs =
          sp.getDouble(_kSurfacePasteStartDwellMs) ?? _surfacePasteStartDwellMs;
      _surfacePasteReturnDwellMs =
          sp.getDouble(_kSurfacePasteReturnDwellMs) ??
          _surfacePasteReturnDwellMs;
    });
  }

  Future<void> _saveSurfacePasteSettings() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(_kSurfacePasteUlPerMm, _surfacePasteUlPerMm);
    await sp.setDouble(_kSurfacePasteStartPrimeUl, _surfacePasteStartPrimeUl);
    await sp.setDouble(
      _kSurfacePasteStartPrimeRateUlPerS,
      _surfacePasteStartPrimeRateUlPerS,
    );
    await sp.setDouble(_kSurfacePasteStartBoostUl, _surfacePasteStartBoostUl);
    await sp.setDouble(
      _kSurfacePasteStartBoostDistanceMm,
      _surfacePasteStartBoostDistanceMm,
    );
    await sp.setDouble(
      _kSurfacePasteCoastDistanceMm,
      _surfacePasteCoastDistanceMm,
    );
    await sp.setDouble(_kSurfacePasteStopRetractUl, _surfacePasteStopRetractUl);
    await sp.setDouble(
      _kSurfacePasteStopRetractRateUlPerS,
      _surfacePasteStopRetractRateUlPerS,
    );
    await sp.setDouble(_kSurfacePasteStopDwellMs, _surfacePasteStopDwellMs);
    await sp.setDouble(_kSurfacePasteStartDwellMs, _surfacePasteStartDwellMs);
    await sp.setDouble(_kSurfacePasteReturnDwellMs, _surfacePasteReturnDwellMs);
  }

  void _setSurfacePasteSetting(void Function() update) {
    setState(() {
      update();
      _surfacePasteTestStatus = null;
    });
    unawaited(_saveSurfacePasteSettings());
  }

  Future<void> _pickStl() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'STL', extensions: ['stl']),
      ],
    );
    if (file == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final bytes = await file.readAsBytes();
      final mesh = StlParser.parse(bytes, name: file.name);
      setState(() {
        _mesh = mesh;
        _meshName = file.name;
        _meshPath = file.path;
        _loading = false;
        _error = null;
        _resetLocalizationFit(mesh: mesh);
      });
      _resetView();
    } catch (err) {
      setState(() {
        _loading = false;
        _error = err.toString();
      });
    }
  }

  Future<void> _pickDxf() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'DXF', extensions: ['dxf']),
      ],
    );
    if (file == null) return;

    setState(() {
      _dxfLoading = true;
      _dxfError = null;
      _dxfWarning = null;
    });

    try {
      final bytes = await file.readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true);
      final toolpath = DxfParser.parse(text, name: file.name);
      _applyDxfToolpath(toolpath, path: file.path);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _dxfLoading = false;
        _dxfError = error.toString();
      });
    }
  }

  Future<void> _loadDxfFile(File file) async {
    setState(() {
      _dxfLoading = true;
      _dxfError = null;
      _dxfWarning = null;
    });

    try {
      final bytes = await file.readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true);
      final toolpath = DxfParser.parse(
        text,
        name: _fileNameFromPath(file.path),
      );
      _applyDxfToolpath(toolpath, path: file.path);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _dxfLoading = false;
        _dxfError = error.toString();
      });
    }
  }

  void _applyDxfToolpath(DxfToolpath toolpath, {required String path}) {
    if (toolpath.isEmpty) {
      throw const FormatException(
        'DXF has no supported geometry. Supported: LINE, LWPOLYLINE, POLYLINE, ARC, CIRCLE.',
      );
    }
    final width = math.max(1.0, toolpath.widthMm.abs());
    final height = math.max(1.0, toolpath.heightMm.abs());
    final unsupported = toolpath.unsupportedEntities.toList()..sort();
    setState(() {
      _dxfToolpath = toolpath;
      _dxfPath = path;
      _dxfLoading = false;
      _dxfError = null;
      _dxfWarning = unsupported.isEmpty
          ? null
          : 'Unsupported DXF entities skipped: ${unsupported.take(8).join(', ')}'
                '${unsupported.length > 8 ? '...' : ''}';
      _surfaceTrajectorySource = _SurfaceTrajectorySource.dxf;
      _surfacePatternWidthMm = width;
      _surfacePatternHeightMm = height;
      _surfacePatternCenterLocal = Offset.zero;
      _clearGeneratedSurfaceTrajectory();
    });
  }

  void _resetView() {
    setState(() {
      _rotationX = -0.72;
      _rotationY = 0.0;
      _rotationZ = -0.72;
      _zoom = 1.0;
      _pan = Offset.zero;
    });
  }

  Future<void> _captureWorkpiecePhoto() async {
    setState(() {
      _capturingWorkpiece = true;
      _workpiecePhotoError = null;
    });

    try {
      final camera = context.read<CameraViewerController>();
      final bytes = await camera.captureStill();
      final path = await _saveWorkpiecePhoto(bytes);
      final imageSize = await _decodeImageSize(bytes);
      setState(() {
        _workpiecePhotoBytes = bytes;
        _workpiecePhotoPath = path;
        _workpiecePhotoAt = DateTime.now();
        _workpieceImageSize = imageSize;
        _capturingWorkpiece = false;
        _workspaceView = 2;
        _resetLocalizationFit(imageSize: imageSize);
      });
      _resetPhotoView();
      unawaited(_refreshSurfaceFiles());
    } catch (error) {
      setState(() {
        _capturingWorkpiece = false;
        _workpiecePhotoError = error.toString();
      });
    }
  }

  Future<String> _saveWorkpiecePhoto(Uint8List bytes) async {
    final dir = Directory(
      '${Directory.current.path}${Platform.pathSeparator}02_visual'
      '${Platform.pathSeparator}surface_workpiece_photos',
    );
    await dir.create(recursive: true);
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final file = File(
      '${dir.path}${Platform.pathSeparator}workpiece_$stamp.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  void _resetPhotoView() {
    _photoTransformController.value = Matrix4.identity();
  }

  void _zoomPhoto(double factor) {
    final current = _photoTransformController.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(0.25, 8.0).toDouble();
    if ((next - current).abs() < 0.001) return;
    final scale = next / current;
    _photoTransformController.value = _photoTransformController.value.clone()
      ..scaleByDouble(scale, scale, scale, 1);
  }

  Future<Size> _decodeImageSize(Uint8List bytes) {
    final completer = Completer<Size>();
    ui.decodeImageFromList(bytes, (image) {
      completer.complete(Size(image.width.toDouble(), image.height.toDouble()));
      image.dispose();
    });
    return completer.future;
  }

  bool get _localizationReady =>
      _mesh != null &&
      !_mesh!.isEmpty &&
      _workpiecePhotoBytes != null &&
      _workpieceImageSize != null;

  _ProjectionBasis get _projectionBasis =>
      _ProjectionBasis.fromContactFace(_contactFace);

  void _resetLocalizationFit({StlMesh? mesh, Size? imageSize}) {
    final targetMesh = mesh ?? _mesh;
    final targetSize = imageSize ?? _workpieceImageSize;
    if (targetMesh == null || targetMesh.isEmpty || targetSize == null) {
      return;
    }

    final projectedSize = _projectionBasis.projectedSize(targetMesh.bounds);
    final modelSpan = math.max(projectedSize.width, projectedSize.height);
    final imageSpan = math.min(targetSize.width, targetSize.height);
    if (modelSpan > 1e-6 && imageSpan > 1e-6) {
      _localizationScalePxPerMm = imageSpan / (modelSpan * 1.25);
    }
    _localizationOffsetPx = Offset.zero;
    _localizationYawDeg = 0.0;
    _lockedAlignmentHandle = null;
    _localizationResultPath = null;
    _localizationError = null;
    _localizationTransformController.value = Matrix4.identity();
  }

  void _nudgeLocalization(double dx, double dy) {
    setState(() {
      _localizationOffsetPx += Offset(dx, dy);
      _localizationResultPath = null;
    });
    _scheduleLocalizationAutosave();
  }

  void _scheduleLocalizationAutosave() {
    _localizationAutosaveTimer?.cancel();
    _localizationAutosaveTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted && _localizationReady) {
        unawaited(_saveLocalizationResult());
      }
    });
  }

  void _toggleAlignmentHandleLock(_AlignmentHandleId handle) {
    setState(() {
      _lockedAlignmentHandle = _lockedAlignmentHandle == handle ? null : handle;
    });
  }

  void _clearAlignmentHandleLock() {
    setState(() => _lockedAlignmentHandle = null);
  }

  void _dragAlignmentHandle({
    required _AlignmentHandleId handle,
    required Offset targetImagePx,
  }) {
    final mesh = _mesh;
    final imageSize = _workpieceImageSize;
    if (mesh == null || imageSize == null || mesh.isEmpty) return;
    if (_lockedAlignmentHandle == handle) return;

    final deltas = _alignmentHandleDeltas(mesh);
    final draggedDelta = deltas[handle];
    if (draggedDelta == null || draggedDelta.distance < 1e-6) return;

    final imageCenter = Offset(imageSize.width / 2, imageSize.height / 2);
    final locked = _lockedAlignmentHandle;
    final lockedDelta = locked == null ? null : deltas[locked];

    setState(() {
      if (locked != null &&
          locked != handle &&
          lockedDelta != null &&
          (draggedDelta - lockedDelta).distance > 1e-6) {
        final anchorImagePx =
            imageCenter +
            _localizationOffsetPx +
            lockedDelta * _localizationScalePxPerMm;
        final targetVector = targetImagePx - anchorImagePx;
        final modelVector = draggedDelta - lockedDelta;
        final nextScale =
            targetVector.distance / math.max(modelVector.distance, 1e-6);
        final clampedScale = nextScale.clamp(0.02, 2000.0).toDouble();
        _localizationScalePxPerMm = clampedScale;
        _localizationOffsetPx =
            anchorImagePx - imageCenter - lockedDelta * clampedScale;
      } else {
        _localizationOffsetPx =
            targetImagePx -
            imageCenter -
            draggedDelta * _localizationScalePxPerMm;
      }
      _localizationResultPath = null;
    });
    _scheduleLocalizationAutosave();
  }

  Map<_AlignmentHandleId, Offset> _alignmentHandleDeltas(StlMesh mesh) {
    final basis = _projectionBasis;
    final bounds = mesh.bounds;
    final center = basis.project(bounds.center);
    final u0 = basis.minU(bounds);
    final u1 = basis.maxU(bounds);
    final v0 = basis.minV(bounds);
    final v1 = basis.maxV(bounds);
    final um = (u0 + u1) / 2;
    final vm = (v0 + v1) / 2;

    Offset delta(double u, double v) {
      final projected = Offset(u, v);
      final local = Offset(
        projected.dx - center.dx,
        -(projected.dy - center.dy),
      );
      final yaw = _localizationYawDeg * math.pi / 180.0;
      final cosYaw = math.cos(yaw);
      final sinYaw = math.sin(yaw);
      return Offset(
        local.dx * cosYaw - local.dy * sinYaw,
        local.dx * sinYaw + local.dy * cosYaw,
      );
    }

    return {
      _AlignmentHandleId.topLeft: delta(u0, v1),
      _AlignmentHandleId.topCenter: delta(um, v1),
      _AlignmentHandleId.topRight: delta(u1, v1),
      _AlignmentHandleId.centerRight: delta(u1, vm),
      _AlignmentHandleId.bottomRight: delta(u1, v0),
      _AlignmentHandleId.bottomCenter: delta(um, v0),
      _AlignmentHandleId.bottomLeft: delta(u0, v0),
      _AlignmentHandleId.centerLeft: delta(u0, vm),
    };
  }

  void _zoomLocalizationView(double factor) {
    final current = _localizationTransformController.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(0.35, 8.0).toDouble();
    if ((next - current).abs() < 0.001) return;
    final scale = next / current;
    _localizationTransformController.value =
        _localizationTransformController.value.clone()
          ..scaleByDouble(scale, scale, scale, 1);
  }

  void _zoomTrajectoryView(double factor) {
    final current = _trajectoryController.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(0.35, 8.0).toDouble();
    if ((next - current).abs() < 0.001) return;
    final scale = next / current;
    _trajectoryController.value = _trajectoryController.value.clone()
      ..scaleByDouble(scale, scale, scale, 1);
  }

  Future<void> _saveLocalizationResult() async {
    final mesh = _mesh;
    final imageSize = _workpieceImageSize;
    if (mesh == null || mesh.isEmpty || imageSize == null) return;

    setState(() {
      _localizationError = null;
    });

    try {
      final dir = Directory(
        '${Directory.current.path}${Platform.pathSeparator}02_visual'
        '${Platform.pathSeparator}surface_workpiece_photos',
      );
      await dir.create(recursive: true);
      final now = DateTime.now();
      final stamp =
          '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}';
      final bounds = mesh.bounds;
      final centerPx = Offset(
        imageSize.width / 2 + _localizationOffsetPx.dx,
        imageSize.height / 2 + _localizationOffsetPx.dy,
      );
      final result = {
        'created_at': now.toIso8601String(),
        'mesh_name': _meshName ?? mesh.name,
        'mesh_path': _meshPath,
        'photo_path': _workpiecePhotoPath,
        'image_size_px': {'width': imageSize.width, 'height': imageSize.height},
        'manual_alignment': {
          'contact_face': _contactFace.id,
          'contact_face_label': _contactFace.label,
          'bed_u_axis': _projectionBasis.uAxis.label,
          'bed_v_axis': _projectionBasis.vAxis.label,
          'height_axis': _projectionBasis.heightAxis.label,
          'center_px': {'x': centerPx.dx, 'y': centerPx.dy},
          'center_offset_px': {
            'x': _localizationOffsetPx.dx,
            'y': _localizationOffsetPx.dy,
          },
          'yaw_deg': _localizationYawDeg,
          'scale_px_per_mm': _localizationScalePxPerMm,
          'locked_handle': _lockedAlignmentHandle?.id,
        },
        'model_bounds_mm': {
          'min_x': bounds.minX,
          'max_x': bounds.maxX,
          'min_y': bounds.minY,
          'max_y': bounds.maxY,
          'min_z': bounds.minZ,
          'max_z': bounds.maxZ,
        },
        'note':
            'Manual image-space STL top projection alignment. Apply camera-to-motion calibration before using this as a machine-coordinate pose.',
      };
      final text = const JsonEncoder.withIndent('  ').convert(result);
      final file = File(
        '${dir.path}${Platform.pathSeparator}'
        'workpiece_localization_$stamp.json',
      );
      await file.writeAsString(text, flush: true);
      final latest = File(
        '${dir.path}${Platform.pathSeparator}workpiece_localization_latest.json',
      );
      await latest.writeAsString(text, flush: true);

      setState(() {
        _localizationResultPath = file.path;
      });
      unawaited(_refreshSurfaceFiles());
    } catch (error) {
      setState(() {
        _localizationError = error.toString();
      });
    }
  }

  Future<void> _importLocalizationResult() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (file == null) return;
    await _loadLocalizationResultFile(File(file.path));
  }

  Future<void> _loadLatestLocalizationResult() async {
    final dir = Directory(
      '${Directory.current.path}${Platform.pathSeparator}02_visual'
      '${Platform.pathSeparator}surface_workpiece_photos',
    );
    final file = File(
      '${dir.path}${Platform.pathSeparator}workpiece_localization_latest.json',
    );
    if (!await file.exists()) {
      setState(() {
        _localizationError = 'No latest localization JSON found.';
      });
      return;
    }
    await _loadLocalizationResultFile(file);
  }

  Future<void> _loadLocalizationResultFile(File file) async {
    setState(() {
      _localizationError = null;
    });

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        throw const FormatException('Invalid localization JSON.');
      }
      await _applyLocalizationResult(
        Map<String, dynamic>.from(decoded),
        path: file.path,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _localizationError = 'Failed to import localization: $error';
      });
    }
  }

  Future<void> _applyLocalizationResult(
    Map<String, dynamic> result, {
    required String path,
  }) async {
    final warnings = <String>[];
    final alignment = _jsonMap(result['manual_alignment']);
    if (alignment == null) {
      throw const FormatException('Missing manual_alignment.');
    }

    StlMesh? importedMesh;
    String? importedMeshPath;
    String? importedMeshName;
    final savedMeshPath = _jsonString(result['mesh_path']);
    final hasCurrentMesh = _mesh != null && !_mesh!.isEmpty;
    if (!hasCurrentMesh && savedMeshPath != null && savedMeshPath.isNotEmpty) {
      final meshFile = File(savedMeshPath);
      if (await meshFile.exists()) {
        final bytes = await meshFile.readAsBytes();
        importedMeshName = _fileNameFromPath(meshFile.path);
        importedMesh = StlParser.parse(bytes, name: importedMeshName);
        importedMeshPath = meshFile.path;
      } else {
        warnings.add('定位结果记录的 STL 文件不存在：$savedMeshPath');
      }
    } else if (hasCurrentMesh &&
        savedMeshPath != null &&
        savedMeshPath.isNotEmpty &&
        _meshPath != null &&
        _meshPath != savedMeshPath) {
      warnings.add('Current STL path differs from localization JSON.');
    }

    Uint8List? importedPhotoBytes;
    Size? importedPhotoSize;
    String? importedPhotoPath;
    DateTime? importedPhotoAt;
    final savedPhotoPath = _jsonString(result['photo_path']);
    if (savedPhotoPath != null && savedPhotoPath.isNotEmpty) {
      final photoFile = File(savedPhotoPath);
      if (await photoFile.exists()) {
        importedPhotoBytes = await photoFile.readAsBytes();
        importedPhotoSize = await _decodeImageSize(importedPhotoBytes);
        importedPhotoPath = photoFile.path;
        importedPhotoAt =
            DateTime.tryParse(_jsonString(result['created_at']) ?? '') ??
            await photoFile.lastModified();
      } else if (_workpiecePhotoBytes == null) {
        warnings.add('定位结果记录的工件照片不存在：$savedPhotoPath');
      }
    }

    final savedImageSize = _jsonSize(result['image_size_px']);
    final nextImageSize =
        importedPhotoSize ?? _workpieceImageSize ?? savedImageSize;
    final offsetMap = _jsonMap(alignment['center_offset_px']);
    final centerMap = _jsonMap(alignment['center_px']);
    var nextOffset = _localizationOffsetPx;
    if (offsetMap != null) {
      nextOffset = Offset(
        _jsonDouble(offsetMap['x'], _localizationOffsetPx.dx),
        _jsonDouble(offsetMap['y'], _localizationOffsetPx.dy),
      );
    } else if (centerMap != null && nextImageSize != null) {
      nextOffset = Offset(
        _jsonDouble(centerMap['x'], nextImageSize.width / 2) -
            nextImageSize.width / 2,
        _jsonDouble(centerMap['y'], nextImageSize.height / 2) -
            nextImageSize.height / 2,
      );
    }

    final nextFace =
        _contactFaceFromId(_jsonString(alignment['contact_face'])) ??
        _contactFace;
    final nextLockedHandle = _alignmentHandleFromId(
      _jsonString(alignment['locked_handle']),
    );

    if (!mounted) return;
    setState(() {
      if (importedMesh != null) {
        _mesh = importedMesh;
        _meshName = importedMeshName;
        _meshPath = importedMeshPath;
      }
      if (importedPhotoBytes != null) {
        _workpiecePhotoBytes = importedPhotoBytes;
        _workpiecePhotoPath = importedPhotoPath;
        _workpiecePhotoAt = importedPhotoAt;
      }
      _workpieceImageSize = nextImageSize;
      _contactFace = nextFace;
      _localizationOffsetPx = nextOffset;
      _localizationYawDeg = _jsonDouble(
        alignment['yaw_deg'],
        _localizationYawDeg,
      ).clamp(-180.0, 180.0).toDouble();
      _localizationScalePxPerMm = _jsonDouble(
        alignment['scale_px_per_mm'],
        _localizationScalePxPerMm,
      ).clamp(0.02, 2000.0).toDouble();
      _lockedAlignmentHandle = nextLockedHandle;
      _localizationResultPath = path;
      _localizationError = warnings.isEmpty ? null : warnings.join('\n');
      _clearGeneratedSurfaceTrajectory();
      _surfaceTrajectoryError = null;
      _surfaceMotionError = null;
      _surfaceTrajectoryPath = null;
      _surfaceGcodePath = null;
      _verificationError = null;
      _verificationResultPath = null;
      _verificationResult = null;
      _verificationProgress = 0;
      _workspaceView = 2;
      _localizationTransformController.value = Matrix4.identity();
      _trajectoryTransformController?.value = Matrix4.identity();
    });
  }

  String? _jsonString(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  Map<String, dynamic>? _jsonMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  double _jsonDouble(Object? value, double fallback) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  Size? _jsonSize(Object? value) {
    final map = _jsonMap(value);
    if (map == null) return null;
    final width = _jsonDouble(map['width'], 0);
    final height = _jsonDouble(map['height'], 0);
    if (width <= 0 || height <= 0) return null;
    return Size(width, height);
  }

  String _fileNameFromPath(String path) {
    final parts = path.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? path : parts.last;
  }

  String _joinPath(List<String> parts) => parts.join(Platform.pathSeparator);

  String get _visualRootPath =>
      _joinPath([Directory.current.path, '02_visual']);

  List<_SurfaceFileLocation> get _surfaceFileLocations => [
    _SurfaceFileLocation(
      label: '工件照片',
      path: _joinPath([_visualRootPath, 'surface_workpiece_photos']),
      importKind: _SurfaceFileImportKind.auto,
    ),
    _SurfaceFileLocation(
      label: '定位文件',
      path: _joinPath([_visualRootPath, 'surface_workpiece_photos']),
      importKind: _SurfaceFileImportKind.localization,
      extensions: {'json'},
      namePrefixes: {'workpiece_localization'},
    ),
    _SurfaceFileLocation(
      label: '轨迹文件',
      path: _joinPath([_visualRootPath, 'surface_trajectories']),
      importKind: _SurfaceFileImportKind.trajectory,
    ),
    _SurfaceFileLocation(
      label: 'DXF trajectory',
      path: _joinPath([_visualRootPath, 'surface_trajectories']),
      importKind: _SurfaceFileImportKind.dxf,
      extensions: {'dxf'},
    ),
    _SurfaceFileLocation(
      label: '验证文件',
      path: _joinPath([_visualRootPath, 'surface_trajectory_verification']),
      importKind: _SurfaceFileImportKind.verification,
      recursive: true,
    ),
    _SurfaceFileLocation(
      label: '补偿文件',
      path: _visualRootPath,
      importKind: _SurfaceFileImportKind.correction,
      extensions: {'json'},
      namePrefixes: {'surface_trajectory_correction'},
    ),
  ];

  Future<void> _refreshSurfaceFiles() async {
    if (mounted) {
      setState(() {
        _surfaceFilesLoading = true;
        _surfaceFilesError = null;
      });
    }

    try {
      final groups = <_SurfaceFileGroup>[];
      final seen = <String>{};
      for (final location in _surfaceFileLocations) {
        final dir = Directory(location.path);
        final entries = <_SurfaceManagedFile>[];
        if (await dir.exists()) {
          final entities = await dir
              .list(recursive: location.recursive)
              .toList();
          for (final entity in entities) {
            final item = await _surfaceManagedFileFromEntity(entity, location);
            if (item == null) continue;
            final key = item.path.toLowerCase();
            if (!seen.add('${location.label}:$key')) continue;
            entries.add(item);
          }
        }
        entries.sort((a, b) {
          if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
          return b.modified.compareTo(a.modified);
        });
        groups.add(_SurfaceFileGroup(location: location, items: entries));
      }
      if (!mounted) return;
      setState(() {
        _surfaceFileGroups = groups;
        _surfaceFilesLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _surfaceFilesError = error.toString();
        _surfaceFilesLoading = false;
      });
    }
  }

  Future<_SurfaceManagedFile?> _surfaceManagedFileFromEntity(
    FileSystemEntity entity,
    _SurfaceFileLocation location,
  ) async {
    final stat = await entity.stat();
    final type = stat.type;
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.directory) {
      return null;
    }
    final name = _fileNameFromPath(entity.path);
    if (name.startsWith('.')) return null;
    final isDirectory = type == FileSystemEntityType.directory;
    final extension = _extensionOf(name);
    if (!isDirectory && location.extensions != null) {
      if (!location.extensions!.contains(extension)) return null;
    }
    if (!isDirectory && location.namePrefixes != null) {
      final lower = name.toLowerCase();
      final matched = location.namePrefixes!.any(
        (prefix) => lower.startsWith(prefix.toLowerCase()),
      );
      if (!matched) return null;
    }
    return _SurfaceManagedFile(
      name: name,
      path: entity.path,
      relativePath: _relativePath(entity.path, location.path),
      isDirectory: isDirectory,
      sizeBytes: isDirectory ? 0 : stat.size,
      modified: stat.modified,
      importKind: location.importKind,
    );
  }

  String _relativePath(String path, String root) {
    final normalizedRoot = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    if (path.toLowerCase().startsWith(normalizedRoot.toLowerCase())) {
      return path.substring(normalizedRoot.length);
    }
    return _fileNameFromPath(path);
  }

  String _extensionOf(String name) {
    final index = name.lastIndexOf('.');
    if (index < 0 || index == name.length - 1) return '';
    return name.substring(index + 1).toLowerCase();
  }

  bool _isInsideVisualRoot(String path) {
    final root = Directory(_visualRootPath).absolute.path.toLowerCase();
    final target = FileSystemEntity.isDirectorySync(path)
        ? Directory(path).absolute.path.toLowerCase()
        : File(path).absolute.path.toLowerCase();
    return target == root ||
        target.startsWith('$root${Platform.pathSeparator}');
  }

  Future<void> _importSurfaceManagedFile(_SurfaceManagedFile item) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (item.isDirectory) {
        final manifest = File(
          '${item.path}${Platform.pathSeparator}manifest.json',
        );
        if (await manifest.exists()) {
          await _loadVerificationManifestFile(manifest);
          messenger.showSnackBar(const SnackBar(content: Text('已导入验证文件')));
          return;
        }
        throw StateError('该文件夹中未找到 manifest.json');
      }

      final extension = _extensionOf(item.name);
      if (extension == 'stl') {
        await _loadStlFile(File(item.path));
        messenger.showSnackBar(const SnackBar(content: Text('已导入 STL')));
      } else if (_looksLikeLocalizationFile(item)) {
        await _loadLocalizationResultFile(File(item.path));
        messenger.showSnackBar(const SnackBar(content: Text('已导入定位文件')));
      } else if (_looksLikeVerificationFile(item)) {
        await _loadVerificationManifestFile(File(item.path));
        messenger.showSnackBar(const SnackBar(content: Text('已导入验证文件')));
      } else if (_isImageExtension(extension)) {
        await _loadWorkpiecePhotoFile(File(item.path));
        messenger.showSnackBar(const SnackBar(content: Text('已导入工件照片')));
      } else if (extension == 'dxf') {
        await _loadDxfFile(File(item.path));
        messenger.showSnackBar(const SnackBar(content: Text('DXF imported')));
      } else if (extension == 'csv') {
        setState(() {
          _surfaceTrajectoryPath = item.path;
          _surfaceTrajectoryError = null;
        });
        messenger.showSnackBar(const SnackBar(content: Text('已选择 CSV')));
      } else if (extension == 'gcode' || extension == 'g') {
        setState(() {
          _surfaceGcodePath = item.path;
          _surfaceTrajectoryError = null;
        });
        messenger.showSnackBar(const SnackBar(content: Text('已选择 G-code')));
      } else if (item.importKind == _SurfaceFileImportKind.correction) {
        await _loadSurfaceCommandCorrection();
        messenger.showSnackBar(const SnackBar(content: Text('已选择补偿文件')));
      } else {
        throw StateError('暂不支持导入该文件类型');
      }
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('导入失败: $error')));
    }
  }

  bool _looksLikeLocalizationFile(_SurfaceManagedFile item) =>
      _extensionOf(item.name) == 'json' &&
      (item.importKind == _SurfaceFileImportKind.localization ||
          item.name.startsWith('workpiece_localization'));

  bool _looksLikeVerificationFile(_SurfaceManagedFile item) =>
      _extensionOf(item.name) == 'json' &&
      (item.importKind == _SurfaceFileImportKind.verification ||
          item.name == 'manifest.json');

  bool _isImageExtension(String extension) =>
      extension == 'jpg' ||
      extension == 'jpeg' ||
      extension == 'png' ||
      extension == 'bmp';

  Future<void> _loadStlFile(File file) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final name = _fileNameFromPath(file.path);
      final mesh = StlParser.parse(bytes, name: name);
      if (!mounted) return;
      setState(() {
        _mesh = mesh;
        _meshName = name;
        _meshPath = file.path;
        _loading = false;
        _error = null;
        _resetLocalizationFit(mesh: mesh);
      });
      _resetView();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadWorkpiecePhotoFile(File file) async {
    final bytes = await file.readAsBytes();
    final imageSize = await _decodeImageSize(bytes);
    final modified = await file.lastModified();
    if (!mounted) return;
    setState(() {
      _workpiecePhotoBytes = bytes;
      _workpiecePhotoPath = file.path;
      _workpiecePhotoAt = modified;
      _workpieceImageSize = imageSize;
      _workpiecePhotoError = null;
      _workspaceView = 1;
      _resetLocalizationFit(imageSize: imageSize);
    });
    _resetPhotoView();
  }

  Future<void> _loadVerificationManifestFile(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Invalid verification manifest JSON.');
    }
    if (!mounted) return;
    setState(() {
      _verificationResult = Map<String, dynamic>.from(decoded);
      _verificationResultPath = file.path;
      _verificationError = null;
      _showActualVerificationTrajectory = true;
      _workspaceView = 3;
    });
  }

  Future<void> _deleteSurfaceManagedFile(_SurfaceManagedFile item) async {
    if (!_isInsideVisualRoot(item.path)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('只能删除 02_visual 下的曲面相关文件')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定删除 ${item.relativePath} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (item.isDirectory) {
        await Directory(item.path).delete(recursive: true);
      } else {
        await File(item.path).delete();
      }
      _clearSurfaceReferencesToPath(item.path);
      await _refreshSurfaceFiles();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败: $error')));
    }
  }

  Future<void> _renameSurfaceManagedFile(_SurfaceManagedFile item) async {
    if (!_isInsideVisualRoot(item.path)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('只能重命名 02_visual 下的曲面相关文件')));
      return;
    }
    final controller = TextEditingController(text: item.name);
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '新名称',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (nextName == null) return;
    final trimmed = nextName.trim();
    if (trimmed.isEmpty || trimmed == item.name) return;
    if (trimmed.contains('/') || trimmed.contains('\\')) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('名称不能包含路径分隔符')));
      return;
    }
    final parent = File(item.path).parent.path;
    final target = '$parent${Platform.pathSeparator}$trimmed';
    if (await FileSystemEntity.type(target) != FileSystemEntityType.notFound) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('同名文件已存在')));
      return;
    }
    try {
      if (item.isDirectory) {
        await Directory(item.path).rename(target);
      } else {
        await File(item.path).rename(target);
      }
      _replaceSurfaceReferencePath(item.path, target);
      await _refreshSurfaceFiles();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('重命名失败: $error')));
    }
  }

  void _clearSurfaceReferencesToPath(String path) {
    setState(() {
      if (_meshPath == path) {
        _mesh = null;
        _meshName = null;
        _meshPath = null;
      }
      if (_workpiecePhotoPath == path) {
        _workpiecePhotoBytes = null;
        _workpiecePhotoPath = null;
        _workpiecePhotoAt = null;
        _workpieceImageSize = null;
      }
      if (_localizationResultPath == path) _localizationResultPath = null;
      if (_surfaceTrajectoryPath == path) _surfaceTrajectoryPath = null;
      if (_surfaceGcodePath == path) _surfaceGcodePath = null;
      if (_dxfPath == path) {
        _dxfPath = null;
        _dxfToolpath = null;
        _dxfWarning = null;
        _dxfError = null;
        _clearGeneratedSurfaceTrajectory();
      }
      if (_verificationResultPath == path) {
        _verificationResultPath = null;
        _verificationResult = null;
      }
    });
  }

  void _replaceSurfaceReferencePath(String oldPath, String newPath) {
    setState(() {
      if (_meshPath == oldPath) {
        _meshPath = newPath;
        _meshName = _fileNameFromPath(newPath);
      }
      if (_workpiecePhotoPath == oldPath) _workpiecePhotoPath = newPath;
      if (_localizationResultPath == oldPath) _localizationResultPath = newPath;
      if (_surfaceTrajectoryPath == oldPath) _surfaceTrajectoryPath = newPath;
      if (_surfaceGcodePath == oldPath) _surfaceGcodePath = newPath;
      if (_dxfPath == oldPath) _dxfPath = newPath;
      if (_verificationResultPath == oldPath) _verificationResultPath = newPath;
    });
  }

  void _clearGeneratedSurfaceTrajectory() {
    _surfaceTrajectory = const [];
    _surfaceMotionTrajectory = const [];
    _surfaceTrajectoryPath = null;
    _surfaceGcodePath = null;
    _verificationResult = null;
    _verificationResultPath = null;
    _verificationError = null;
    _verificationProgress = 0;
    _surfaceCommandCorrection = null;
    _surfaceMotionError = null;
    _surfaceOneClickStatus = null;
    _surfacePasteTestStatus = null;
  }

  bool get _surfaceTrajectorySourceReady =>
      _surfaceTrajectorySource == _SurfaceTrajectorySource.pattern ||
      _dxfToolpath != null;

  String get _surfaceTrajectorySourceLabel {
    if (_surfaceTrajectorySource == _SurfaceTrajectorySource.dxf) {
      final dxf = _dxfToolpath;
      return dxf == null ? 'DXF file' : 'DXF: ${dxf.name}';
    }
    return _surfacePattern.label;
  }

  List<List<Offset>> _currentSurfacePolylines({
    required double width,
    required double height,
  }) {
    final dxf = _dxfToolpath;
    if (_surfaceTrajectorySource == _SurfaceTrajectorySource.dxf) {
      if (dxf == null) return const [];
      return dxf.transformedPolylines(
        widthMm: width,
        heightMm: height,
        center: _surfacePatternCenterLocal,
        rotationDeg: _surfacePatternRotationDeg,
        keepAspectRatio: _dxfKeepAspectRatio,
      );
    }
    return _surfacePattern
        .polylines(width, height)
        .map(
          (polyline) => polyline
              .map(
                (point) =>
                    _rotateOffset(point, _surfacePatternRotationDeg) +
                    _surfacePatternCenterLocal,
              )
              .toList(growable: false),
        )
        .toList(growable: false);
  }

  Rect _containRect(Size outer, Size inner) {
    final scale = math.min(
      outer.width / inner.width,
      outer.height / inner.height,
    );
    final width = inner.width * scale;
    final height = inner.height * scale;
    return Rect.fromLTWH(
      (outer.width - width) / 2,
      (outer.height - height) / 2,
      width,
      height,
    );
  }

  void _moveSurfacePatternBySceneDelta({
    required Offset sceneDelta,
    required Size sceneSize,
    required Size imageSize,
  }) {
    final imageRect = _containRect(sceneSize, imageSize);
    if (imageRect.width <= 0 || imageRect.height <= 0) return;
    final imageDelta = Offset(
      sceneDelta.dx * imageSize.width / imageRect.width,
      sceneDelta.dy * imageSize.height / imageRect.height,
    );
    final yaw = -_localizationYawDeg * math.pi / 180.0;
    final cosYaw = math.cos(yaw);
    final sinYaw = math.sin(yaw);
    final localPxDelta = Offset(
      imageDelta.dx * cosYaw - imageDelta.dy * sinYaw,
      imageDelta.dx * sinYaw + imageDelta.dy * cosYaw,
    );
    final localDelta = Offset(
      localPxDelta.dx / _localizationScalePxPerMm,
      -localPxDelta.dy / _localizationScalePxPerMm,
    );
    if (!localDelta.dx.isFinite || !localDelta.dy.isFinite) return;
    setState(() {
      _surfacePatternCenterLocal += localDelta;
      _clearGeneratedSurfaceTrajectory();
    });
  }

  Offset _imagePixelToLocalMm(
    Offset imagePx,
    Size imageSize,
    Offset offsetPx,
    double yawDeg,
    double scalePxPerMm,
  ) {
    final centerPx = Offset(imageSize.width / 2, imageSize.height / 2);
    final relativeToCenter = imagePx - centerPx - offsetPx;
    final yaw = -yawDeg * math.pi / 180.0;
    final cosYaw = math.cos(yaw);
    final sinYaw = math.sin(yaw);
    final localPx = Offset(
      relativeToCenter.dx * cosYaw - relativeToCenter.dy * sinYaw,
      relativeToCenter.dx * sinYaw + relativeToCenter.dy * cosYaw,
    );
    return Offset(localPx.dx / scalePxPerMm, -localPx.dy / scalePxPerMm);
  }

  _ContactFace? _contactFaceFromId(String? id) {
    if (id == null) return null;
    for (final face in _ContactFace.values) {
      if (face.id == id) return face;
    }
    return null;
  }

  _AlignmentHandleId? _alignmentHandleFromId(String? id) {
    if (id == null) return null;
    for (final handle in _AlignmentHandleId.values) {
      if (handle.id == id) return handle;
    }
    return null;
  }

  Future<void> _generateSurfaceTrajectory() async {
    final mesh = _mesh;
    if (mesh == null || mesh.isEmpty) {
      setState(() {
        _surfaceTrajectoryError = '请先加载 STL 模型。';
      });
      return;
    }
    if (_workpieceImageSize == null) {
      setState(() {
        _surfaceTrajectoryError = '请先完成照片定位，轨迹需要用照片标定换算到机器坐标。';
      });
      return;
    }
    if (!_surfaceTrajectorySourceReady) {
      setState(() {
        _surfaceTrajectoryError =
            'Please import a DXF file or switch back to the built-in patterns.';
      });
      return;
    }

    final basis = _projectionBasis;
    final bounds = mesh.bounds;
    final projectedSize = basis.projectedSize(bounds);
    final widthLimit = math.max(1.0, projectedSize.width * 0.92);
    final heightLimit = math.max(1.0, projectedSize.height * 0.92);
    final width = _surfacePatternWidthMm.clamp(1.0, widthLimit).toDouble();
    final height = _surfacePatternHeightMm.clamp(1.0, heightLimit).toDouble();
    final step = _surfaceSampleStepMm.clamp(0.2, 20.0).toDouble();
    final polylines = _currentSurfacePolylines(width: width, height: height);
    final center = basis.project(bounds.center);
    final minHeight = basis.minHeight(bounds);
    final points = <_SurfaceToolPoint>[];
    var missingSamples = 0;

    for (
      var polylineIndex = 0;
      polylineIndex < polylines.length;
      polylineIndex++
    ) {
      final polyline = polylines[polylineIndex];
      final sampled = _samplePolyline(polyline, step);
      for (var i = 0; i < sampled.length; i++) {
        final sample = sampled[i];
        final local = sample.point;
        final u = center.dx + local.dx;
        final v = center.dy + local.dy;
        final sampledSurface = _sampleSurface(mesh, basis, u, v);
        if (sampledSurface == null) {
          missingSamples++;
          continue;
        }
        final surfaceHeight = sampledSurface.height;

        points.add(
          _SurfaceToolPoint(
            localX: local.dx,
            localY: local.dy,
            surfaceHeight: surfaceHeight - minHeight,
            surfaceNormal: sampledSurface.normal,
            machineX: double.nan,
            machineY: double.nan,
            machineZ:
                _surfaceBedZ + surfaceHeight - minHeight + _surfaceClearanceMm,
            travel: i == 0,
            polylineIndex: polylineIndex,
            segmentIndex: sample.segmentIndex,
            sampleIndexInPolyline: i,
            isControlPoint: sample.isControlPoint,
          ),
        );
      }
    }

    if (points.isEmpty) {
      setState(() {
        _surfaceTrajectory = const [];
        _surfaceMotionTrajectory = const [];
        _surfaceTrajectoryError = '没有轨迹点落在 STL 投影内部。';
      });
      return;
    }

    List<_SurfaceToolPoint> calibratedPoints;
    try {
      calibratedPoints = await _calibrateSurfaceTrajectoryMachinePoints(points);
      calibratedPoints = _attachSurfaceToolPoses(calibratedPoints);
      _surfaceToolOrientationSummary = _summarizeSurfaceToolOrientation(
        calibratedPoints,
      );
    } catch (error) {
      setState(() {
        _surfaceTrajectory = const [];
        _surfaceMotionTrajectory = const [];
        _surfaceTrajectoryPath = null;
        _surfaceGcodePath = null;
        _surfaceTrajectoryError =
            '轨迹坐标标定失败：$error\n请检查照片定位、相机内参、ChArUco 外参和 machine-board 标定文件。';
      });
      return;
    }

    setState(() {
      _surfacePatternWidthMm = width;
      _surfacePatternHeightMm = height;
      _surfaceSampleStepMm = step;
      _surfaceTrajectory = calibratedPoints;
      _surfaceMotionTrajectory = const [];
      _surfaceTrajectoryPath = null;
      _surfaceGcodePath = null;
      _surfaceMotionError = null;
      _verificationError = null;
      _verificationResultPath = null;
      _verificationResult = null;
      _verificationProgress = 0;
      _surfaceTrajectoryError = missingSamples > 0
          ? '已生成 ${calibratedPoints.length} 个点；跳过 $missingSamples 个 STL 外部采样点。'
          : null;
      _workspaceView = 3;
    });
  }

  StlVector3 _surfaceNormalInTrajectoryFrame(StlVector3 normal) {
    final radians = _localizationYawDeg * math.pi / 180.0;
    final cosine = math.cos(radians);
    final sine = math.sin(radians);
    return StlVector3(
      normal.x * cosine - normal.y * sine,
      normal.x * sine + normal.y * cosine,
      normal.z,
    ).normalized();
  }

  _SurfaceReachabilityOverlay? _reachabilityOverlayForPreview(StlMesh mesh) {
    if (!_showToolReachabilityOverlay ||
        _surfaceToolOrientation.mode != SurfaceToolPoseMode.normalFollow) {
      return null;
    }
    final key = _SurfaceReachabilityOverlayKey(
      mesh: mesh,
      contactFace: _contactFace,
      localizationYawDeg: _localizationYawDeg,
      config: _surfaceToolOrientation,
    );
    if (_surfaceReachabilityOverlayKey?.matches(key) == true) {
      return _surfaceReachabilityOverlay;
    }

    final basis = _projectionBasis;
    final center = basis.project(mesh.bounds.center);
    final triangles = <_SurfaceReachabilityTriangle>[];
    for (final triangle in mesh.sampledTriangles(4000)) {
      if (!_isVisibleHeightTriangle(mesh, basis, triangle)) continue;
      final normal = _surfaceNormalInTrajectoryFrame(
        basis.projectNormal(triangle.normal),
      );
      final toolAxis = SurfaceToolPose.toolAxisFromOutwardNormal(normal);
      final pose = SurfaceToolPose.fromOutwardNormal(
        normal,
        _surfaceToolOrientation,
      );
      final horizontal = math.sqrt(
        toolAxis.x * toolAxis.x + toolAxis.y * toolAxis.y,
      );
      final status = !pose.isValid
          ? _SurfaceReachabilityStatus.unreachable
          : horizontal <= 1e-7
          ? _SurfaceReachabilityStatus.yawSingular
          : _SurfaceReachabilityStatus.reachable;
      Offset local(StlVector3 point) {
        final projected = basis.project(point);
        return Offset(projected.dx - center.dx, projected.dy - center.dy);
      }

      triangles.add(
        _SurfaceReachabilityTriangle(
          a: local(triangle.a),
          b: local(triangle.b),
          c: local(triangle.c),
          status: status,
        ),
      );
    }
    final overlay = _SurfaceReachabilityOverlay(triangles);
    _surfaceReachabilityOverlayKey = key;
    _surfaceReachabilityOverlay = overlay;
    return overlay;
  }

  List<_SurfaceToolPoint> _attachSurfaceToolPoses(
    List<_SurfaceToolPoint> points,
  ) {
    final config = _surfaceToolOrientation;
    if (config.mode == SurfaceToolPoseMode.xyzOnly) {
      return points
          .map(
            (point) => point.copyWith(
              machineX: point.referenceMachineX ?? point.machineX,
              machineY: point.referenceMachineY ?? point.machineY,
              machineZ: point.referenceMachineZ ?? point.machineZ,
            ),
          )
          .toList(growable: false);
    }
    var previousWorldYawDeg = 0.0;
    return points
        .map((point) {
          final pose = switch (config.mode) {
            SurfaceToolPoseMode.xyzOnly => null,
            SurfaceToolPoseMode.fixed => SurfaceToolPose.fixed(config),
            SurfaceToolPoseMode.normalFollow =>
              point.surfaceNormal == null
                  ? const SurfaceToolPose(
                      yawServoDeg: double.nan,
                      pitchServoDeg: double.nan,
                      error: '轨迹点缺少曲面法线。',
                    )
                  : SurfaceToolPose.fromOutwardNormal(
                      _surfaceNormalInTrajectoryFrame(point.surfaceNormal!),
                      config,
                      fallbackWorldYawDeg: previousWorldYawDeg,
                    ),
          };
          if (pose?.isValid == true && pose!.worldYawDeg != null) {
            previousWorldYawDeg = pose.worldYawDeg!;
          }
          final offset =
              config.mode == SurfaceToolPoseMode.normalFollow &&
                  pose?.isValid == true &&
                  (config.tipLengthMm != 0 || config.tipLateralOffsetMm != 0)
              ? surfaceToolTipCompensationOffset(pose!, config)
              : const StlVector3(0, 0, 0);
          final referenceX = point.referenceMachineX ?? point.machineX;
          final referenceY = point.referenceMachineY ?? point.machineY;
          final referenceZ = point.referenceMachineZ ?? point.machineZ;
          final machineX = referenceX + offset.x;
          final machineY = referenceY + offset.y;
          final machineZ = referenceZ + offset.z;
          if (!machineX.isFinite || !machineY.isFinite || !machineZ.isFinite) {
            throw StateError('针尖几何补偿生成了无效的机器坐标。');
          }
          return point.copyWith(
            toolPose: pose,
            machineX: machineX,
            machineY: machineY,
            machineZ: machineZ,
          );
        })
        .toList(growable: false);
  }

  SurfaceToolOrientationSummary _summarizeSurfaceToolOrientation(
    List<_SurfaceToolPoint> points,
  ) => summarizeSurfaceToolPoses(
    points.where((point) => !point.travel).map((point) => point.toolPose),
    _surfaceToolOrientation,
  );

  void _showSurfaceToolPoseDiagnostics() {
    final trajectory = _exportTrajectory;
    const maximumRows = 250;
    final visiblePoints = trajectory.take(maximumRows).toList(growable: false);
    String number(double? value) =>
        value == null ? '-' : value.toStringAsFixed(2);
    String vector(StlVector3? value) => value == null
        ? '-'
        : '(${number(value.x)}, ${number(value.y)}, ${number(value.z)})';

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('姿态计算明细'),
        content: SizedBox(
          width: 1120,
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('工具轴 = 投影/定位后的曲面外法线；竖直工具轴沿用上一点 Yaw。'),
              const SizedBox(height: 8),
              if (trajectory.length > maximumRows)
                Text(
                  '窗口显示前 $maximumRows/${trajectory.length} 点；导出 CSV 可查看完整明细。',
                ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 18,
                      headingTextStyle: const TextStyle(fontSize: 12),
                      dataTextStyle: const TextStyle(fontSize: 11),
                      columns: const [
                        DataColumn(label: Text('#')),
                        DataColumn(label: Text('移动')),
                        DataColumn(label: Text('STL 外法线')),
                        DataColumn(label: Text('轨迹坐标法线')),
                        DataColumn(label: Text('工具轴')),
                        DataColumn(label: Text('世界 Y/P')),
                        DataColumn(label: Text('舵机 Y/P')),
                        DataColumn(label: Text('状态')),
                      ],
                      rows: List<DataRow>.generate(visiblePoints.length, (
                        index,
                      ) {
                        final point = visiblePoints[index];
                        final frameNormal = point.surfaceNormal == null
                            ? null
                            : _surfaceNormalInTrajectoryFrame(
                                point.surfaceNormal!,
                              );
                        final toolAxis = frameNormal == null
                            ? null
                            : SurfaceToolPose.toolAxisFromOutwardNormal(
                                frameNormal,
                              );
                        final pose = point.toolPose;
                        return DataRow(
                          cells: [
                            DataCell(Text('$index')),
                            DataCell(Text(point.travel ? '空移' : '工作')),
                            DataCell(Text(vector(point.surfaceNormal))),
                            DataCell(Text(vector(frameNormal))),
                            DataCell(Text(vector(toolAxis))),
                            DataCell(
                              Text(
                                '${number(pose?.worldYawDeg)} / ${number(pose?.worldPitchDeg)}',
                              ),
                            ),
                            DataCell(
                              Text(
                                '${number(pose?.yawServoDeg)} / ${number(pose?.pitchServoDeg)}',
                              ),
                            ),
                            DataCell(
                              Text(pose?.error ?? (pose == null ? '-' : 'ok')),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<List<_SurfaceToolPoint>> _calibrateSurfaceTrajectoryMachinePoints(
    List<_SurfaceToolPoint> points,
  ) async {
    final imageSize = _workpieceImageSize;
    if (imageSize == null) {
      throw StateError('缺少照片尺寸。');
    }

    final dir = Directory(
      '${Directory.current.path}${Platform.pathSeparator}02_visual'
      '${Platform.pathSeparator}surface_trajectories',
    );
    await dir.create(recursive: true);
    final inputPath =
        '${dir.path}${Platform.pathSeparator}surface_map_input.json';
    final outputPath =
        '${dir.path}${Platform.pathSeparator}surface_map_output.json';
    final payload = {
      'image_size_px': {'width': imageSize.width, 'height': imageSize.height},
      'manual_alignment': {
        'center_px': {'x': imageSize.width / 2, 'y': imageSize.height / 2},
        'center_offset_px': {
          'x': _localizationOffsetPx.dx,
          'y': _localizationOffsetPx.dy,
        },
        'yaw_deg': _localizationYawDeg,
        'scale_px_per_mm': _localizationScalePxPerMm,
      },
      'points': [
        for (var i = 0; i < points.length; i++)
          {
            'index': i,
            'local_x_mm': points[i].localX,
            'local_y_mm': points[i].localY,
            'surface_height_mm': points[i].surfaceHeight,
          },
      ],
    };
    await File(inputPath).writeAsString(jsonEncode(payload), flush: true);

    final scriptPath =
        '${Directory.current.path}${Platform.pathSeparator}02_visual'
        '${Platform.pathSeparator}surface_local_to_machine.py';
    final result = await Process.run(
      'python',
      [scriptPath, '--input', inputPath, '--output', outputPath],
      workingDirectory: Directory.current.path,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      final stdout = result.stdout.toString().trim();
      throw StateError(
        [
          if (stderr.isNotEmpty) stderr,
          if (stdout.isNotEmpty) stdout,
          if (stderr.isEmpty && stdout.isEmpty)
            'Python 进程退出码 ${result.exitCode}',
        ].join('\n'),
      );
    }

    final decoded = jsonDecode(await File(outputPath).readAsString());
    final mapped = decoded is Map ? decoded['points'] : null;
    if (mapped is! List || mapped.length != points.length) {
      throw StateError('标定脚本返回的点数量不一致。');
    }

    final next = <_SurfaceToolPoint>[];
    final correction = _applySurfaceCommandCorrection
        ? await _loadSurfaceCommandCorrection()
        : _SurfaceCommandCorrection.none();
    _surfaceCommandCorrection = correction;

    // Re-sample STL height at the actual projected image positions
    // to ensure height matches the spatial location
    final mesh = _mesh;
    final basis = _projectionBasis;
    final bounds = mesh?.bounds;
    final center = bounds == null ? Offset.zero : basis.project(bounds.center);
    final minHeight = bounds == null ? 0.0 : basis.minHeight(bounds);

    for (final item in mapped) {
      if (item is! Map) continue;
      final index = _jsonInt(item['index'], -1);
      if (index < 0 || index >= points.length) {
        throw StateError('标定脚本返回了无效点序号：$index');
      }
      final point = points[index];
      final targetMachineX = _jsonDouble(item['machine_x_mm'], double.nan);
      final targetMachineY = _jsonDouble(item['machine_y_mm'], double.nan);
      final targetMachineZFromBoard = _jsonDouble(
        item['machine_z_from_board_mm'],
        double.nan,
      );

      // Convert the Python-calculated image position back to STL projection coordinates
      final imagePx = Offset(
        _jsonDouble(item['image_x_px'], double.nan),
        _jsonDouble(item['image_y_px'], double.nan),
      );

      // Sample STL height at the correct projected position
      double correctedSurfaceHeight = point.surfaceHeight;
      StlVector3? correctedSurfaceNormal = point.surfaceNormal;
      if (mesh != null && imagePx.dx.isFinite && imagePx.dy.isFinite) {
        // Convert image px back to local mm using the inverse transformation
        final localFromImage = _imagePixelToLocalMm(
          imagePx,
          imageSize,
          _localizationOffsetPx,
          _localizationYawDeg,
          _localizationScalePxPerMm,
        );
        final u = center.dx + localFromImage.dx;
        final v = center.dy + localFromImage.dy;
        final sampledSurface = _sampleSurface(mesh, basis, u, v);
        if (sampledSurface != null) {
          correctedSurfaceHeight = sampledSurface.height - minHeight;
          correctedSurfaceNormal = sampledSurface.normal;
        }
      }

      final targetMachineZ =
          _surfaceBedZ + _surfaceClearanceMm + correctedSurfaceHeight;
      final correctedMachineX = targetMachineX + correction.dx;
      final correctedMachineY = targetMachineY + correction.dy;
      final correctedMachineZ = correction.correctedZ(
        x: targetMachineX,
        y: targetMachineY,
        z: targetMachineZ,
      );

      next.add(
        point.copyWith(
          machineX: correctedMachineX,
          machineY: correctedMachineY,
          machineZ: correctedMachineZ,
          referenceMachineX: correctedMachineX,
          referenceMachineY: correctedMachineY,
          referenceMachineZ: correctedMachineZ,
          targetMachineX: targetMachineX,
          targetMachineY: targetMachineY,
          targetMachineZ: targetMachineZ,
          targetMachineZFromBoard: targetMachineZFromBoard,
          targetImagePx: imagePx,
          targetBoardX: _jsonDouble(item['board_x_mm'], double.nan),
          targetBoardY: _jsonDouble(item['board_y_mm'], double.nan),
          targetBoardZ: _jsonDouble(item['board_z_mm'], double.nan),
          surfaceNormal: correctedSurfaceNormal,
        ),
      );
    }
    if (next.any(
      (point) =>
          !point.machineX.isFinite ||
          !point.machineY.isFinite ||
          !point.machineZ.isFinite,
    )) {
      throw StateError('标定脚本返回了非数值机器坐标。');
    }
    return next;
  }

  void _generateSmoothSurfaceMotionTrajectory() {
    if (_surfaceTrajectory.isEmpty) return;
    final step = _surfaceSmoothStepMm.clamp(0.1, 5.0).toDouble();
    final maxZStep = _surfaceSmoothMaxZStepMm.clamp(0.02, 2.0).toDouble();
    final smoothed = <_SurfaceToolPoint>[];

    for (var i = 0; i < _surfaceTrajectory.length; i++) {
      final current = _surfaceTrajectory[i];
      if (i == 0 || current.travel) {
        smoothed.add(current.copyWithMotionMetadata(isControlPoint: true));
        continue;
      }

      final previous = _surfaceTrajectory[i - 1];
      if (previous.safePolylineIndex != current.safePolylineIndex ||
          previous.travel) {
        smoothed.add(current.copyWithMotionMetadata(isControlPoint: true));
        continue;
      }

      final distance = math.sqrt(
        math.pow(current.localX - previous.localX, 2) +
            math.pow(current.localY - previous.localY, 2),
      );
      final zDelta = (current.machineZ - previous.machineZ).abs();
      final xyCount = math.max(1, (distance / step).ceil());
      final zCount = math.max(1, (zDelta / maxZStep).ceil());
      final count = math.max(xyCount, zCount);

      for (var j = 1; j <= count; j++) {
        final t = j / count;
        smoothed.add(
          _interpolateSurfaceToolPoint(
            previous,
            current,
            t,
            travel: false,
            sampleIndexInPolyline: smoothed.length,
            isControlPoint: j == count && current.safeIsControlPoint,
          ),
        );
      }
    }

    final motionTrajectory = _attachSurfaceToolPoses(smoothed);
    setState(() {
      _surfaceSmoothStepMm = step;
      _surfaceSmoothMaxZStepMm = maxZStep;
      _surfaceMotionTrajectory = motionTrajectory;
      _surfaceGcodePath = null;
      _surfaceMotionError = smoothed.length < _surfaceTrajectory.length
          ? '平滑轨迹生成异常，请重新生成基础轨迹。'
          : null;
    });
  }

  _SurfaceToolPoint _interpolateSurfaceToolPoint(
    _SurfaceToolPoint a,
    _SurfaceToolPoint b,
    double t, {
    required bool travel,
    required int sampleIndexInPolyline,
    required bool isControlPoint,
  }) {
    double lerp(double x, double y) => x + (y - x) * t;
    double? lerpNullable(double? x, double? y) {
      if (x == null || y == null) return null;
      return lerp(x, y);
    }

    Offset? lerpOffset(Offset? x, Offset? y) {
      if (x == null || y == null) return null;
      return Offset(lerp(x.dx, y.dx), lerp(x.dy, y.dy));
    }

    return _SurfaceToolPoint(
      localX: lerp(a.localX, b.localX),
      localY: lerp(a.localY, b.localY),
      surfaceHeight: lerp(a.surfaceHeight, b.surfaceHeight),
      surfaceNormal: _lerpNormal(a.surfaceNormal, b.surfaceNormal, t),
      toolPose: _interpolateToolPose(a.toolPose, b.toolPose, t),
      machineX: lerp(a.machineX, b.machineX),
      machineY: lerp(a.machineY, b.machineY),
      machineZ: lerp(a.machineZ, b.machineZ),
      referenceMachineX: lerpNullable(a.referenceMachineX, b.referenceMachineX),
      referenceMachineY: lerpNullable(a.referenceMachineY, b.referenceMachineY),
      referenceMachineZ: lerpNullable(a.referenceMachineZ, b.referenceMachineZ),
      targetMachineX: lerpNullable(a.targetMachineX, b.targetMachineX),
      targetMachineY: lerpNullable(a.targetMachineY, b.targetMachineY),
      targetMachineZ: lerpNullable(a.targetMachineZ, b.targetMachineZ),
      targetMachineZFromBoard: lerpNullable(
        a.targetMachineZFromBoard,
        b.targetMachineZFromBoard,
      ),
      targetImagePx: lerpOffset(a.targetImagePx, b.targetImagePx),
      targetBoardX: lerpNullable(a.targetBoardX, b.targetBoardX),
      targetBoardY: lerpNullable(a.targetBoardY, b.targetBoardY),
      targetBoardZ: lerpNullable(a.targetBoardZ, b.targetBoardZ),
      travel: travel,
      polylineIndex: b.polylineIndex,
      segmentIndex: b.segmentIndex,
      sampleIndexInPolyline: sampleIndexInPolyline,
      isControlPoint: isControlPoint,
    );
  }

  StlVector3? _lerpNormal(StlVector3? a, StlVector3? b, double t) {
    if (a == null || b == null) return null;
    return StlVector3(
      a.x + (b.x - a.x) * t,
      a.y + (b.y - a.y) * t,
      a.z + (b.z - a.z) * t,
    ).normalized();
  }

  SurfaceToolPose? _interpolateToolPose(
    SurfaceToolPose? a,
    SurfaceToolPose? b,
    double t,
  ) {
    if (a == null || b == null || !a.isValid || !b.isValid) return null;
    double lerp(double x, double y) => x + (y - x) * t;
    return SurfaceToolPose(
      worldYawDeg: a.worldYawDeg != null && b.worldYawDeg != null
          ? lerp(a.worldYawDeg!, b.worldYawDeg!)
          : null,
      worldPitchDeg: a.worldPitchDeg != null && b.worldPitchDeg != null
          ? lerp(a.worldPitchDeg!, b.worldPitchDeg!)
          : null,
      yawServoDeg: lerp(a.yawServoDeg, b.yawServoDeg),
      pitchServoDeg: lerp(a.pitchServoDeg, b.pitchServoDeg),
    );
  }

  Future<_SurfaceCommandCorrection> _loadSurfaceCommandCorrection() async {
    final path =
        '${Directory.current.path}${Platform.pathSeparator}02_visual'
        '${Platform.pathSeparator}surface_trajectory_correction_latest.json';
    final file = File(path);
    if (!await file.exists()) {
      _surfaceCommandCorrection = _SurfaceCommandCorrection.none();
      return _surfaceCommandCorrection!;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      final values = decoded is Map
          ? decoded['command_precompensation_mm']
          : null;
      if (values is! List || values.length < 3) {
        _surfaceCommandCorrection = _SurfaceCommandCorrection.none();
        return _surfaceCommandCorrection!;
      }
      final correction = _SurfaceCommandCorrection(
        dx: _jsonDouble(values[0], 0),
        dy: _jsonDouble(values[1], 0),
        dz: _jsonDouble(values[2], 0),
        zErrorModelCoefficients: _readZErrorModelCoefficients(
          decoded is Map ? decoded : null,
        ),
        zErrorSamples: _readZErrorSamples(decoded is Map ? decoded : null),
        sourcePath: path,
      );
      _surfaceCommandCorrection = correction;
      return correction;
    } catch (_) {
      _surfaceCommandCorrection = _SurfaceCommandCorrection.none();
      return _surfaceCommandCorrection!;
    }
  }

  List<double>? _readZErrorModelCoefficients(Map<dynamic, dynamic>? decoded) {
    final model = decoded?['z_error_model'];
    if (model is! Map) return null;
    final type = model['type'];
    final coefficients = model['coefficients'];
    if (type != 'linear_machine_xyz' ||
        coefficients is! List ||
        coefficients.length < 4) {
      return null;
    }
    final values = [
      _jsonDouble(coefficients[0], double.nan),
      _jsonDouble(coefficients[1], double.nan),
      _jsonDouble(coefficients[2], double.nan),
      _jsonDouble(coefficients[3], double.nan),
    ];
    return values.every((value) => value.isFinite) ? values : null;
  }

  List<_SurfaceZErrorSample> _readZErrorSamples(
    Map<dynamic, dynamic>? decoded,
  ) {
    final samples = decoded?['z_error_samples'];
    if (samples is! List) return const [];
    final result = <_SurfaceZErrorSample>[];
    for (final sample in samples) {
      if (sample is! Map) continue;
      final x = _jsonDouble(sample['machine_x_mm'], double.nan);
      final y = _jsonDouble(sample['machine_y_mm'], double.nan);
      final z = _jsonDouble(sample['machine_z_mm'], double.nan);
      final errorZ = _jsonDouble(sample['error_z_mm'], double.nan);
      if (!x.isFinite || !y.isFinite || !z.isFinite || !errorZ.isFinite) {
        continue;
      }
      result.add(_SurfaceZErrorSample(x: x, y: y, z: z, errorZ: errorZ));
    }
    return List.unmodifiable(result);
  }

  Future<void> _exportSurfaceTrajectoryCsv() async {
    if (_surfaceTrajectory.isEmpty) return;
    try {
      final path = await _writeSurfaceTrajectoryFile(extension: 'csv');
      setState(() {
        _surfaceTrajectoryPath = path;
        _surfaceTrajectoryError = null;
      });
      unawaited(_refreshSurfaceFiles());
    } catch (error) {
      setState(() => _surfaceTrajectoryError = error.toString());
    }
  }

  Future<void> _exportSurfaceTrajectoryGcode() async {
    if (_surfaceTrajectory.isEmpty) return;
    try {
      final path = await _writeSurfaceTrajectoryFile(extension: 'gcode');
      setState(() {
        _surfaceGcodePath = path;
        _surfaceTrajectoryError = null;
      });
      unawaited(_refreshSurfaceFiles());
    } catch (error) {
      setState(() => _surfaceTrajectoryError = error.toString());
    }
  }

  SurfaceMotionPreflight _surfaceMotionPreflight(PrinterController printer) {
    final trajectory = _exportTrajectory;
    final hasFiniteCoordinates =
        trajectory.isNotEmpty &&
        trajectory.every(
          (point) =>
              point.machineX.isFinite &&
              point.machineY.isFinite &&
              point.machineZ.isFinite,
        );
    final orientationSummary = _summarizeSurfaceToolOrientation(trajectory);
    return SurfaceMotionPreflight(
      moonrakerConnected: printer.repo != null,
      klippyReady: printer.klippyReady,
      klippyStateMessage: printer.klippyStateMessage,
      printState: printer.printState.toLowerCase(),
      sdIsActive: printer.sdIsActive,
      isHomed: printer.isHomed,
      hasTrajectory: hasFiniteCoordinates,
      hasActiveBedZCalibration: _activeSurfaceBedZCalibration != null,
      bedZToolheadWarning: _surfaceBedZToolheadWarning,
      orientationSummary: orientationSummary,
    );
  }

  bool _canOneClickStart({
    required PrinterController printer,
    required bool ready,
    required bool localized,
    required bool sourceReady,
  }) {
    if (_surfaceOneClickStarting) return false;
    if (_surfaceTrajectory.isEmpty) return ready && localized && sourceReady;
    return _surfaceMotionPreflight(printer).canStart;
  }

  /// Reads homed_axes from Moonraker so homing done on the controller screen
  /// is reflected before enabling one-click motion.
  Future<void> _refreshSurfaceHomingStatus() async {
    if (_surfaceHomingStatusRefreshing) return;
    final printer = context.read<PrinterController>();
    final messenger = ScaffoldMessenger.of(context);

    if (printer.repo == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Moonraker 未连接，无法查询归零状态')),
      );
      return;
    }

    setState(() => _surfaceHomingStatusRefreshing = true);
    try {
      final refreshed = await printer.refreshStatusSnapshot();
      if (!mounted) return;
      if (!refreshed) {
        messenger.showSnackBar(
          const SnackBar(content: Text('归零状态查询失败，请检查 Moonraker 连接')),
        );
        return;
      }
      final axes = printer.homedAxes ?? '';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            printer.isHomed
                ? '已从下位机同步归零状态（homed_axes: $axes）'
                : '下位机当前未完成 XYZ 归零（homed_axes: ${axes.isEmpty ? '无' : axes}）',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _surfaceHomingStatusRefreshing = false);
      }
    }
  }

  Future<void> _startSurfaceMotionOneClick() async {
    if (_surfaceOneClickStarting) return;
    final printer = context.read<PrinterController>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _surfaceOneClickStarting = true;
      _surfaceOneClickStatus = '正在准备平滑 G-code...';
      _surfaceTrajectoryError = null;
      _surfaceMotionError = null;
    });

    try {
      if (printer.repo == null) {
        throw StateError('Moonraker 未连接，请先连接打印机。');
      }

      await printer.refreshAllStatus();
      if (!mounted) return;

      if (_surfaceTrajectory.isEmpty) {
        await _generateSurfaceTrajectory();
        if (!mounted) return;
      }
      if (_surfaceTrajectory.isEmpty) {
        throw StateError(_surfaceTrajectoryError ?? '基础轨迹生成失败。');
      }

      if (_surfaceMotionTrajectory.isEmpty) {
        _generateSmoothSurfaceMotionTrajectory();
      }
      if (_surfaceMotionTrajectory.isEmpty) {
        throw StateError(_surfaceMotionError ?? '平滑运动轨迹生成失败。');
      }

      final preflight = _surfaceMotionPreflight(printer);
      if (!preflight.canStart) {
        throw StateError(preflight.blockingReason!);
      }

      final path = await _writeSurfaceTrajectoryFile(extension: 'gcode');
      final gcode = await _surfaceTrajectoryToGcode();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'surface_motion_$stamp.gcode';

      if (!mounted) return;
      setState(() {
        _surfaceGcodePath = path;
        _surfaceOneClickStatus = '正在上传并启动：$filename';
      });

      final result = await printer.uploadAndStartGcode(
        filename: filename,
        gcode: gcode,
      );
      if (!result.uploaded) {
        throw StateError(result.error ?? '上传失败。');
      }
      if (!result.started) {
        throw StateError(
          'G-code 已上传至 ${result.remotePath}，但启动失败：${result.error ?? '未知错误'}',
        );
      }

      await printer.refreshAllStatus();
      if (!mounted) return;
      final started = printer.printState.toLowerCase() == 'printing';
      setState(() {
        _surfaceOneClickStatus = started
            ? '已启动：${result.remotePath}'
            : '启动命令已发送：${result.remotePath}；等待打印机状态更新。';
        _surfaceTrajectoryError = null;
      });
      unawaited(_refreshSurfaceFiles());
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            started ? '已启动曲面运动：${result.remotePath}' : '启动命令已发送，等待打印机状态更新。',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _surfaceOneClickStatus = null;
        _surfaceTrajectoryError = '一键启动失败：$error';
      });
      messenger.showSnackBar(SnackBar(content: Text('一键启动失败：$error')));
    } finally {
      if (mounted) {
        setState(() => _surfaceOneClickStarting = false);
      }
    }
  }

  Future<void> _startSurfacePasteTestOneClick() async {
    if (_surfacePasteTestStarting) return;
    final printer = context.read<PrinterController>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _surfacePasteTestStarting = true;
      _surfacePasteTestStatus = '正在准备锡膏测试 G-code...';
      _surfaceTrajectoryError = null;
      _surfaceMotionError = null;
    });

    try {
      if (_surfaceToolOrientation.mode != SurfaceToolPoseMode.xyzOnly) {
        throw StateError('工具姿态 G-code 仅支持预览与导出；请保持“仅 XYZ（兼容模式）”后再一键启动。');
      }
      if (printer.repo == null) {
        throw StateError('Moonraker 未连接，请先连接打印机。');
      }

      await printer.refreshAllStatus();
      if (!mounted) return;

      final klippyState = printer.klippyState.toLowerCase();
      final hasKnownKlippyError =
          klippyState == 'error' || klippyState == 'shutdown';
      if (hasKnownKlippyError ||
          (printer.serverInfo != null && !printer.klippyReady)) {
        throw StateError('Klipper 当前未就绪：${printer.klippyStateMessage}');
      }

      final printState = printer.printState.toLowerCase();
      if (printer.sdIsActive ||
          printState == 'printing' ||
          printState == 'paused') {
        throw StateError('打印机当前正在执行任务：${printer.printState}');
      }

      if (_surfaceTrajectory.isEmpty) {
        await _generateSurfaceTrajectory();
        if (!mounted) return;
      }
      if (_surfaceTrajectory.isEmpty) {
        throw StateError(_surfaceTrajectoryError ?? '基础轨迹生成失败。');
      }

      if (_surfaceMotionTrajectory.isEmpty) {
        _generateSmoothSurfaceMotionTrajectory();
      }
      if (_surfaceMotionTrajectory.isEmpty) {
        throw StateError(_surfaceMotionError ?? '平滑运动轨迹生成失败。');
      }

      final gcode = await _surfaceTrajectoryToPasteTestGcode();
      final path = await _writeSurfacePasteTestGcodeFile(gcode);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'surface_paste_test_$stamp.gcode';

      if (!mounted) return;
      setState(() {
        _surfaceGcodePath = path;
        _surfacePasteTestStatus = '正在上传并启动：$filename';
      });

      final remotePath = await printer.uploadGcode(
        filename: filename,
        gcode: gcode,
        startAfterUpload: true,
      );
      if (remotePath == null) {
        throw StateError(printer.lastError ?? '上传或启动失败。');
      }

      if (!mounted) return;
      setState(() {
        _surfacePasteTestStatus = '已启动锡膏测试：$remotePath';
        _surfaceTrajectoryError = null;
      });
      unawaited(_refreshSurfaceFiles());
      messenger.showSnackBar(SnackBar(content: Text('已启动曲面锡膏测试：$remotePath')));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _surfacePasteTestStatus = null;
        _surfaceTrajectoryError = '锡膏测试启动失败：$error';
      });
      messenger.showSnackBar(SnackBar(content: Text('锡膏测试启动失败：$error')));
    } finally {
      if (mounted) {
        setState(() => _surfacePasteTestStarting = false);
      }
    }
  }

  Future<void> _runTrajectoryCaptureVerification() async {
    if (_surfaceTrajectory.isEmpty || _verificationRunning) return;
    final printer = context.read<PrinterController>();
    final camera = context.read<CameraViewerController>();
    final samples = _verificationSamplePoints();
    if (samples.isEmpty) return;

    setState(() {
      _verificationRunning = true;
      _verificationProgress = 0;
      _verificationError = null;
      _verificationResultPath = null;
      _verificationResult = null;
    });

    try {
      final dir = await _createTrajectoryVerificationDir();
      final records = <Map<String, dynamic>>[];
      for (var i = 0; i < samples.length; i++) {
        final sample = samples[i];
        final point = sample.point;
        final script = _verificationMoveScript(point);
        final error = await printer.sendGcode(
          script,
          receiveTimeout: const Duration(seconds: 30),
        );
        if (error != null) throw StateError(error);
        await Future<void>.delayed(
          Duration(milliseconds: (_verificationSettleSeconds * 1000).round()),
        );
        final bytes = await camera.captureStill();
        final imagePath = await _writeVerificationImage(
          dir: dir,
          bytes: bytes,
          index: i + 1,
        );
        records.add({
          'index': i + 1,
          'verification_point_id': sample.id,
          'key_point_id': sample.id,
          'label': sample.label,
          'point_type': sample.pointType,
          'polyline_index': sample.polylineIndex,
          'segment_index': sample.segmentIndex,
          'endpoint': sample.endpoint,
          'trajectory_index': sample.trajectoryIndex,
          'nearest_trajectory_distance_mm': sample.nearestDistanceMm,
          'matches_generated_trajectory': sample.matchesGeneratedTrajectory,
          'image_path': imagePath,
          'target': point.toJson(),
          'command': point.commandJson(),
          'gcode': script,
        });
        if (!mounted) return;
        setState(() => _verificationProgress = i + 1);
      }
      final manifest = _buildVerificationManifest(records: records);
      final resultPath = await _writeVerificationManifest(
        dir: dir,
        manifest: manifest,
      );
      var detectedManifest = manifest;
      String? detectionError;
      try {
        detectedManifest = await _detectVerificationImages(resultPath);
      } catch (error) {
        detectionError = '抽检图片识别失败：$error';
      }
      if (!mounted) return;
      setState(() {
        _verificationResult = detectedManifest;
        _verificationResultPath = resultPath;
        _verificationError = detectionError;
        _showActualVerificationTrajectory = true;
        _workspaceView = 3;
        _verificationRunning = false;
      });
      unawaited(_refreshSurfaceFiles());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _verificationError = error.toString();
        _verificationRunning = false;
      });
    }
  }

  List<_TrajectoryVerificationPoint> _verificationSamplePoints() {
    final points = _surfaceTrajectory;
    if (points.isEmpty) return const [];

    final candidates = <_TrajectoryVerificationPoint>[];
    final seen = <String>{};
    final spacing = _verificationSpacingMm.clamp(1.0, 100.0).toDouble();

    void addCandidate({
      required int index,
      required String pointType,
      required String endpoint,
      required int priority,
    }) {
      if (index < 0 || index >= points.length) return;
      final point = points[index];
      final key =
          '${point.localX.toStringAsFixed(3)},'
          '${point.localY.toStringAsFixed(3)},$pointType';
      if (!seen.add(key)) return;
      candidates.add(
        _TrajectoryVerificationPoint(
          id: 'V${candidates.length + 1}',
          label: _verificationPointLabel(point, pointType),
          point: point,
          polylineIndex: point.safePolylineIndex,
          segmentIndex: point.safeSegmentIndex,
          endpoint: endpoint,
          pointType: pointType,
          priority: priority,
          trajectoryIndex: index,
          nearestDistanceMm: 0,
          matchesGeneratedTrajectory: true,
        ),
      );
    }

    final segmentIndices = <String, List<int>>{};
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final key = '${point.safePolylineIndex}:${point.safeSegmentIndex}';
      segmentIndices.putIfAbsent(key, () => <int>[]).add(i);
    }

    for (final indices in segmentIndices.values) {
      if (indices.isEmpty) continue;
      addCandidate(
        index: indices.first,
        pointType: 'start',
        endpoint: 'start',
        priority: 0,
      );
      addCandidate(
        index: indices.last,
        pointType: 'end',
        endpoint: 'end',
        priority: 0,
      );
      addCandidate(
        index: indices[indices.length ~/ 2],
        pointType: 'midpoint',
        endpoint: 'middle',
        priority: 1,
      );

      var distanceFromLastCapture = 0.0;
      for (var j = 1; j < indices.length; j++) {
        final previous = points[indices[j - 1]];
        final current = points[indices[j]];
        distanceFromLastCapture += math.sqrt(
          math.pow(current.localX - previous.localX, 2) +
              math.pow(current.localY - previous.localY, 2),
        );
        if (distanceFromLastCapture + 1e-6 < spacing) continue;
        addCandidate(
          index: indices[j],
          pointType: 'sample',
          endpoint: 'sample',
          priority: 2,
        );
        distanceFromLastCapture = 0.0;
      }
    }

    candidates.sort((a, b) {
      final byIndex = a.trajectoryIndex.compareTo(b.trajectoryIndex);
      if (byIndex != 0) return byIndex;
      return a.priority.compareTo(b.priority);
    });

    final maxCaptures = _verificationMaxCaptures.clamp(3, 200);
    final selected = candidates.length <= maxCaptures
        ? candidates
        : _thinVerificationCandidates(candidates, maxCaptures);
    return [
      for (var i = 0; i < selected.length; i++)
        selected[i].copyWith(id: 'V${i + 1}'),
    ];
  }

  List<_TrajectoryVerificationPoint> _thinVerificationCandidates(
    List<_TrajectoryVerificationPoint> candidates,
    int maxCaptures,
  ) {
    final required = candidates.where((point) => point.priority == 0).toList();
    final optional = candidates.where((point) => point.priority > 0).toList();
    if (required.length >= maxCaptures) {
      return _evenlyPick(required, maxCaptures)
        ..sort((a, b) => a.trajectoryIndex.compareTo(b.trajectoryIndex));
    }
    final picked = <_TrajectoryVerificationPoint>[...required];
    picked.addAll(_evenlyPick(optional, maxCaptures - picked.length));
    picked.sort((a, b) => a.trajectoryIndex.compareTo(b.trajectoryIndex));
    return picked;
  }

  List<T> _evenlyPick<T>(List<T> values, int count) {
    if (count <= 0 || values.isEmpty) return const [];
    if (values.length <= count) return [...values];
    if (count == 1) return [values[values.length ~/ 2]];
    return [
      for (var i = 0; i < count; i++)
        values[((values.length - 1) * i / (count - 1)).round()],
    ];
  }

  String _verificationPointLabel(_SurfaceToolPoint point, String pointType) {
    if (_surfaceTrajectorySource == _SurfaceTrajectorySource.dxf) {
      final prefix = 'DXF polyline ${point.safePolylineIndex + 1}';
      return switch (pointType) {
        'start' => '$prefix start',
        'end' => '$prefix end',
        'midpoint' => '$prefix midpoint',
        _ => '$prefix sample',
      };
    }
    if (_surfacePattern == _SurfacePattern.rectangle && pointType != 'sample') {
      final horizontal = point.localX < 0 ? 'Left' : 'Right';
      final vertical = point.localY < 0 ? 'Bottom' : 'Top';
      if (pointType == 'midpoint') {
        if (point.localX.abs() > point.localY.abs()) {
          return '$horizontal side midpoint';
        }
        return '$vertical side midpoint';
      }
      return '$horizontal $vertical corner';
    }
    final prefix = 'Line ${point.safePolylineIndex + 1}';
    return switch (pointType) {
      'start' => '$prefix 起点',
      'end' => '$prefix 终点',
      'midpoint' => '$prefix 中点',
      _ => '$prefix sample',
    };
  }

  Map<String, dynamic> _buildVerificationManifest({
    required List<Map<String, dynamic>> records,
  }) {
    final expectedCount = _verificationSamplePoints().length;
    final allTrajectoryMatches = records.every(
      (record) => record['matches_generated_trajectory'] == true,
    );
    final enoughKeyPoints = records.length == expectedCount;
    final status = records.isEmpty
        ? 'fail'
        : enoughKeyPoints && allTrajectoryMatches
        ? 'ready'
        : 'warn';
    final summary = records.isEmpty
        ? 'No verification points captured.'
        : status == 'ready'
        ? 'Captured verification images; detected actual points are shown when available.'
        : 'Verification count or trajectory matching is abnormal.';

    return {
      'created_at': DateTime.now().toIso8601String(),
      'status': status,
      'summary': summary,
      'pattern': _surfaceTrajectorySourceLabel,
      'trajectory_source': _surfaceTrajectorySource.name,
      'dxf_name': _dxfToolpath?.name,
      'dxf_path': _dxfPath,
      'expected_verification_point_count': expectedCount,
      'captured_verification_point_count': records.length,
      'expected_key_point_count': expectedCount,
      'captured_key_point_count': records.length,
      'verification_spacing_mm': _verificationSpacingMm,
      'verification_max_captures': _verificationMaxCaptures,
      'mesh_name': _meshName ?? _mesh?.name,
      'mesh_path': _meshPath,
      'localization_result_path': _localizationResultPath,
      'trajectory_csv_path': _surfaceTrajectoryPath,
      'trajectory_gcode_path': _surfaceGcodePath,
      'surface_command_correction_enabled': _applySurfaceCommandCorrection,
      'surface_command_correction': _surfaceCommandCorrection?.toJson(),
      'settle_seconds': _verificationSettleSeconds,
      'note':
          'Each capture stores the commanded target and image_path. Green actual trajectory is rendered only when actual/observed/detected local coordinates are present.',
      'checks': {
        'expected_verification_points_found': enoughKeyPoints,
        'expected_key_points_found': enoughKeyPoints,
        'all_targets_match_generated_trajectory': allTrajectoryMatches,
      },
      'captures': records,
    };
  }

  int _expectedVerificationKeyPointCount() {
    if (_surfaceTrajectorySource == _SurfaceTrajectorySource.dxf) {
      final polylineCount = _dxfToolpath?.polylines.length ?? 1;
      return math.max(2, math.min(_verificationMaxCaptures, polylineCount * 2));
    }
    return switch (_surfacePattern) {
      _SurfacePattern.line => 2,
      _SurfacePattern.semicircle => 3,
      _SurfacePattern.rectangle => 4,
      _SurfacePattern.cross => 4,
    };
  }

  String _verificationMoveScript(_SurfaceToolPoint point) {
    final feed = (_surfaceTravelSpeedMmPerS * 60).round();
    return 'G90\n'
        'G21\n'
        'G1 X${point.machineX.toStringAsFixed(3)} '
        'Y${point.machineY.toStringAsFixed(3)} '
        'Z${point.machineZ.toStringAsFixed(3)} '
        'F$feed\n'
        'M400';
  }

  Future<Directory> _createTrajectoryVerificationDir() async {
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final dir = Directory(
      '${Directory.current.path}${Platform.pathSeparator}02_visual'
      '${Platform.pathSeparator}surface_trajectory_verification'
      '${Platform.pathSeparator}capture_$stamp',
    );
    await dir.create(recursive: true);
    return dir;
  }

  Future<String> _writeVerificationImage({
    required Directory dir,
    required Uint8List bytes,
    required int index,
  }) async {
    final file = File(
      '${dir.path}${Platform.pathSeparator}'
      'verification_${index.toString().padLeft(2, '0')}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<String> _writeVerificationManifest({
    required Directory dir,
    required Map<String, dynamic> manifest,
  }) async {
    final file = File('${dir.path}${Platform.pathSeparator}manifest.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
      flush: true,
    );
    return file.path;
  }

  Future<Map<String, dynamic>> _detectVerificationImages(
    String manifestPath,
  ) async {
    final visualDir =
        '${Directory.current.path}${Platform.pathSeparator}02_visual';
    final scriptPath =
        '$visualDir${Platform.pathSeparator}surface_trajectory_verify_detect.py';
    final script = File(scriptPath);
    if (!script.existsSync()) {
      throw FileSystemException('未找到抽检图片识别脚本', scriptPath);
    }

    final frame = _surfaceVerificationFrame();
    final args = <String>[
      scriptPath,
      '--manifest',
      manifestPath,
      '--surface-center-x',
      frame.center.dx.toStringAsFixed(6),
      '--surface-center-y',
      frame.center.dy.toStringAsFixed(6),
      '--surface-yaw-deg',
      frame.yawDeg.toStringAsFixed(6),
    ];
    final result = await Process.run(
      'python',
      args,
      workingDirectory: Directory.current.path,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      final stdout = result.stdout.toString().trim();
      throw StateError(
        [
          if (stderr.isNotEmpty) stderr,
          if (stdout.isNotEmpty) stdout,
          if (stderr.isEmpty && stdout.isEmpty)
            'Python 进程退出码 ${result.exitCode}',
        ].join('\n'),
      );
    }

    final text = await File(manifestPath).readAsString();
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw StateError('抽检图片识别结果不是 JSON 对象');
  }

  ({Offset center, double yawDeg}) _surfaceVerificationFrame() {
    if (_surfaceTrajectory.isEmpty) {
      return (
        center: Offset.zero,
        yawDeg: _localizationYawDeg + _surfacePatternRotationDeg,
      );
    }
    var sumX = 0.0;
    var sumY = 0.0;
    var count = 0;
    for (final point in _surfaceTrajectory) {
      if (!point.machineX.isFinite || !point.machineY.isFinite) continue;
      sumX += point.machineX;
      sumY += point.machineY;
      count++;
    }
    final center = count == 0
        ? Offset.zero
        : Offset(sumX / count.toDouble(), sumY / count.toDouble());
    return (
      center: center,
      yawDeg: _localizationYawDeg + _surfacePatternRotationDeg,
    );
  }

  Future<String> _writeSurfaceTrajectoryFile({
    required String extension,
  }) async {
    final dir = Directory(
      '${Directory.current.path}${Platform.pathSeparator}02_visual'
      '${Platform.pathSeparator}surface_trajectories',
    );
    await dir.create(recursive: true);
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final file = File(
      '${dir.path}${Platform.pathSeparator}surface_path_$stamp.$extension',
    );
    final text = extension == 'gcode'
        ? await _surfaceTrajectoryToGcode()
        : _surfaceTrajectoryToCsv();
    await file.writeAsString(text, flush: true);
    final latest = File(
      '${dir.path}${Platform.pathSeparator}surface_path_latest.$extension',
    );
    await latest.writeAsString(text, flush: true);
    return file.path;
  }

  Future<String> _writeSurfacePasteTestGcodeFile(String gcode) async {
    final dir = Directory(
      '${Directory.current.path}${Platform.pathSeparator}02_visual'
      '${Platform.pathSeparator}surface_trajectories',
    );
    await dir.create(recursive: true);
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final file = File(
      '${dir.path}${Platform.pathSeparator}surface_paste_test_$stamp.gcode',
    );
    await file.writeAsString(gcode, flush: true);
    final latest = File(
      '${dir.path}${Platform.pathSeparator}surface_paste_test_latest.gcode',
    );
    await latest.writeAsString(gcode, flush: true);
    return file.path;
  }

  List<_SurfaceToolPoint> get _exportTrajectory =>
      _surfaceMotionTrajectory.isNotEmpty
      ? _surfaceMotionTrajectory
      : _surfaceTrajectory;

  String _surfaceTrajectoryToCsv() {
    final trajectory = _exportTrajectory;
    String poseValue(double? value) => value?.toStringAsFixed(3) ?? '';
    final buffer = StringBuffer()
      ..writeln(
        'index,source,polyline_index,segment_index,control_point,travel,local_x_mm,local_y_mm,surface_height_mm,normal_x,normal_y,normal_z,trajectory_normal_x,trajectory_normal_y,trajectory_normal_z,tool_axis_x,tool_axis_y,tool_axis_z,world_yaw_deg,world_pitch_deg,yaw_servo_deg,pitch_servo_deg,pose_status,machine_x_mm,machine_y_mm,machine_z_mm,image_x_px,image_y_px,board_x_mm,board_y_mm,board_z_mm,clearance_mm',
      );
    final source = _surfaceMotionTrajectory.isNotEmpty ? 'smoothed' : 'base';
    for (var i = 0; i < trajectory.length; i++) {
      final point = trajectory[i];
      final trajectoryNormal = point.surfaceNormal == null
          ? null
          : _surfaceNormalInTrajectoryFrame(point.surfaceNormal!);
      final toolAxis = trajectoryNormal == null
          ? null
          : SurfaceToolPose.toolAxisFromOutwardNormal(trajectoryNormal);
      buffer.writeln(
        [
          i,
          source,
          point.safePolylineIndex,
          point.safeSegmentIndex,
          point.safeIsControlPoint ? 1 : 0,
          point.travel ? 1 : 0,
          point.localX.toStringAsFixed(4),
          point.localY.toStringAsFixed(4),
          point.surfaceHeight.toStringAsFixed(4),
          poseValue(point.surfaceNormal?.x),
          poseValue(point.surfaceNormal?.y),
          poseValue(point.surfaceNormal?.z),
          poseValue(trajectoryNormal?.x),
          poseValue(trajectoryNormal?.y),
          poseValue(trajectoryNormal?.z),
          poseValue(toolAxis?.x),
          poseValue(toolAxis?.y),
          poseValue(toolAxis?.z),
          poseValue(point.toolPose?.worldYawDeg),
          poseValue(point.toolPose?.worldPitchDeg),
          poseValue(point.toolPose?.yawServoDeg),
          poseValue(point.toolPose?.pitchServoDeg),
          point.toolPose?.error ?? (point.toolPose == null ? '' : 'ok'),
          point.machineX.toStringAsFixed(4),
          point.machineY.toStringAsFixed(4),
          point.machineZ.toStringAsFixed(4),
          point.targetImagePx?.dx.toStringAsFixed(3) ?? '',
          point.targetImagePx?.dy.toStringAsFixed(3) ?? '',
          point.targetBoardX?.toStringAsFixed(4) ?? '',
          point.targetBoardY?.toStringAsFixed(4) ?? '',
          point.targetBoardZ?.toStringAsFixed(4) ?? '',
          _surfaceClearanceMm.toStringAsFixed(4),
        ].join(','),
      );
    }
    return buffer.toString();
  }

  Future<String> _surfaceTrajectoryToGcode() async {
    final trajectory = _exportTrajectory;
    final thumbnails = await _surfaceTrajectoryThumbnailGcode(trajectory);
    final generatedAt = DateTime.now();
    final slicerTimestamp =
        '${generatedAt.year.toString().padLeft(4, '0')}-'
        '${generatedAt.month.toString().padLeft(2, '0')}-'
        '${generatedAt.day.toString().padLeft(2, '0')} at '
        '${generatedAt.hour.toString().padLeft(2, '0')}:'
        '${generatedAt.minute.toString().padLeft(2, '0')}:'
        '${generatedAt.second.toString().padLeft(2, '0')}';
    final orientation = _surfaceToolOrientation;
    final orientationSummary = _summarizeSurfaceToolOrientation(trajectory);
    if (orientation.mode != SurfaceToolPoseMode.xyzOnly &&
        !orientationSummary.canExport) {
      throw StateError('工具姿态校验未通过：${orientationSummary.errors.join('；')}');
    }
    final header = StringBuffer()
      ..writeln('; generated by PrusaSlicer 2.7.0 on $slicerTimestamp')
      ..writeln('; Surface constant-distance motion path')
      ..writeln(
        '; Generated from STL height sampling. Dry-run before printing.',
      )
      ..write(thumbnails)
      ..writeln('; Source: $_surfaceTrajectorySourceLabel')
      ..writeln('; DXF: ${_dxfPath ?? '-'}')
      ..writeln('; Clearance: ${_surfaceClearanceMm.toStringAsFixed(3)} mm')
      ..writeln(
        '; Motion: ${_surfaceMotionTrajectory.isNotEmpty ? 'smoothed' : 'base'}',
      )
      ..writeln('; Points: ${trajectory.length}')
      ..writeln('; Tool pose: ${orientation.mode.label}')
      ..writeln(
        '; Tool axis points opposite the STL outward normal when enabled.',
      )
      ..writeln('; Verify Klipper [servo] configuration before execution.')
      ..writeln('G21')
      ..writeln('G90');
    final result = buildSurfaceOrientationGcode(
      points: trajectory
          .map(
            (point) => SurfaceOrientationGcodePoint(
              x: point.machineX,
              y: point.machineY,
              z: point.machineZ,
              speedMmPerS: point.travel
                  ? _surfaceTravelSpeedMmPerS
                  : _surfaceWorkSpeedMmPerS,
              travel: point.travel,
              pose: point.toolPose,
            ),
          )
          .toList(growable: false),
      config: orientation,
      header: header.toString(),
    );
    final defaultPoseGcode = orientation.mode == SurfaceToolPoseMode.xyzOnly
        ? ''
        : buildDefaultSurfaceToolPoseGcode(settleMs: orientation.settleMs);
    return '${result.gcode}M400\n'
        'G28 ; auto home after print\n'
        'M400\n'
        'G28 ; repeat home after print\n'
        'M400\n'
        '$defaultPoseGcode';
  }

  Future<String> _surfaceTrajectoryToPasteTestGcode() async {
    final trajectory = _exportTrajectory;
    final thumbnails = await _surfaceTrajectoryThumbnailGcode(trajectory);
    final generatedAt = DateTime.now();
    final slicerTimestamp =
        '${generatedAt.year.toString().padLeft(4, '0')}-'
        '${generatedAt.month.toString().padLeft(2, '0')}-'
        '${generatedAt.day.toString().padLeft(2, '0')} at '
        '${generatedAt.hour.toString().padLeft(2, '0')}:'
        '${generatedAt.minute.toString().padLeft(2, '0')}:'
        '${generatedAt.second.toString().padLeft(2, '0')}';
    final travelFeed = (_surfaceTravelSpeedMmPerS * 60).toStringAsFixed(0);
    final workFeed = (_surfaceWorkSpeedMmPerS * 60).toStringAsFixed(0);
    final workSpeedMmPerS = _surfaceWorkSpeedMmPerS
        .clamp(0.1, 120.0)
        .toDouble();
    final ulPerMm = _surfacePasteUlPerMm.clamp(0.01, 5.0).toDouble();
    final primeUl = _surfacePasteStartPrimeUl
        .clamp(0.0, _surfacePastePrimeRetractMaxUl)
        .toDouble();
    final startBoostUl = _surfacePasteStartBoostUl.clamp(0.0, 100.0).toDouble();
    final startBoostDistanceMm = _surfacePasteStartBoostDistanceMm
        .clamp(0.0, 100.0)
        .toDouble();
    final coastDistanceMm = _surfacePasteCoastDistanceMm
        .clamp(0.0, 100.0)
        .toDouble();
    final retractUl = _surfacePasteStopRetractUl
        .clamp(0.0, _surfacePastePrimeRetractMaxUl)
        .toDouble();
    final stopDwellMs = _surfacePasteStopDwellMs.clamp(0.0, 3000.0).toDouble();
    final startDwellMs = _surfacePasteStartDwellMs
        .clamp(0.0, 10000.0)
        .toDouble();
    final returnDwellMs = _surfacePasteReturnDwellMs
        .clamp(0.0, 10000.0)
        .toDouble();
    final segmentPasteRateUlPerS = ulPerMm * workSpeedMmPerS;
    final primeRateUlPerS = _surfacePasteStartPrimeRateUlPerS
        .clamp(0.5, 300.0)
        .toDouble();
    final retractRateUlPerS = _surfacePasteStopRetractRateUlPerS
        .clamp(0.5, 300.0)
        .toDouble();
    final compensationByIndex = _pasteSegmentCompensations(trajectory);
    var workLengthMm = 0.0;
    var pasteVolumeUl = 0.0;
    var boostVolumeUl = 0.0;
    var coastLengthMm = 0.0;
    var travelCount = 0;
    var workCount = 0;

    final buffer = StringBuffer()
      ..writeln('; generated by PrusaSlicer 2.7.0 on $slicerTimestamp')
      ..writeln('; Surface solder paste test path')
      ..writeln(
        '; Travel points move without paste; work segments move with paste_pump SYNC=0.',
      )
      ..write(thumbnails)
      ..writeln('; Source: $_surfaceTrajectorySourceLabel')
      ..writeln('; DXF: ${_dxfPath ?? '-'}')
      ..writeln('; Clearance: ${_surfaceClearanceMm.toStringAsFixed(3)} mm')
      ..writeln(
        '; Motion: ${_surfaceMotionTrajectory.isNotEmpty ? 'smoothed' : 'base'}',
      )
      ..writeln('; Points: ${trajectory.length}')
      ..writeln('; Syringe ID: $_pasteSyringeInnerDiameterMm mm')
      ..writeln(
        '; Syringe area: ${_pasteSyringeAreaMm2.toStringAsFixed(3)} mm^2',
      )
      ..writeln('; Paste amount: ${ulPerMm.toStringAsFixed(3)} uL/mm')
      ..writeln(
        '; Work paste rate: ${segmentPasteRateUlPerS.toStringAsFixed(3)} uL/s',
      )
      ..writeln('; Start prime: ${primeUl.toStringAsFixed(3)} uL')
      ..writeln(
        '; Start prime rate: ${primeRateUlPerS.toStringAsFixed(3)} uL/s',
      )
      ..writeln(
        '; Start boost: ${startBoostUl.toStringAsFixed(3)} uL over '
        '${startBoostDistanceMm.toStringAsFixed(3)} mm',
      )
      ..writeln('; Coast distance: ${coastDistanceMm.toStringAsFixed(3)} mm')
      ..writeln('; Stop retract: ${retractUl.toStringAsFixed(3)} uL')
      ..writeln(
        '; Stop retract rate: ${retractRateUlPerS.toStringAsFixed(3)} uL/s',
      )
      ..writeln('; Start dwell: ${startDwellMs.toStringAsFixed(0)} ms')
      ..writeln('; Return dwell: ${returnDwellMs.toStringAsFixed(0)} ms')
      ..writeln('G21')
      ..writeln('G90')
      ..writeln('M400')
      ..writeln('MANUAL_STEPPER STEPPER=paste_pump ENABLE=1')
      ..writeln('MANUAL_STEPPER STEPPER=paste_pump SYNC=1')
      ..writeln('PASTE_STATUS');

    _SurfaceToolPoint? previous;
    var pasteActive = false;

    void writePasteStart() {
      if (pasteActive) return;
      buffer
        ..writeln(
          'PASTE_START UL=${primeUl.toStringAsFixed(3)} '
          'RATE=${primeRateUlPerS.toStringAsFixed(3)}',
        )
        ..writeln('M400');
      if (startDwellMs > 0.0) {
        buffer.writeln('G4 P${startDwellMs.round()} ; start dwell delay');
      }
      pasteActive = true;
    }

    void writePasteStop(String reason) {
      if (!pasteActive) return;
      buffer
        ..writeln('; paste retract: $reason')
        ..writeln(
          'PASTE_STOP UL=${retractUl.toStringAsFixed(3)} '
          'RATE=${retractRateUlPerS.toStringAsFixed(3)}',
        )
        ..writeln('M400');
      if (stopDwellMs > 0.0) {
        buffer.writeln('G4 P${stopDwellMs.round()}');
      }
      pasteActive = false;
    }

    void writeWorkMove({
      required _SurfaceToolPoint from,
      required _SurfaceToolPoint to,
      required double commandedPasteUl,
      required String comment,
    }) {
      final dx = to.machineX - from.machineX;
      final dy = to.machineY - from.machineY;
      final dz = to.machineZ - from.machineZ;
      final xyDistanceMm = math.sqrt(dx * dx + dy * dy);
      final moveDistanceMm = math.sqrt(dx * dx + dy * dy + dz * dz);
      final pasteTravelMm = commandedPasteUl / _pasteSyringeAreaMm2;
      final moveSeconds = moveDistanceMm / workSpeedMmPerS;
      final pasteSpeedMmPerS = moveSeconds > 0
          ? pasteTravelMm / moveSeconds
          : 0.0;

      if (commandedPasteUl > 0.0001 &&
          pasteTravelMm > 0.0001 &&
          pasteSpeedMmPerS > 0.0001) {
        writePasteStart();
        buffer
          ..writeln('MANUAL_STEPPER STEPPER=paste_pump SYNC=1')
          ..writeln('MANUAL_STEPPER STEPPER=paste_pump SET_POSITION=0')
          ..writeln(
            'MANUAL_STEPPER STEPPER=paste_pump '
            'MOVE=${pasteTravelMm.toStringAsFixed(5)} '
            'SPEED=${pasteSpeedMmPerS.toStringAsFixed(5)} '
            'ACCEL=${_pasteStepperAccelMmPerS2.toStringAsFixed(1)} '
            'SYNC=0',
          );
      }
      buffer.writeln(
        'G1 X${to.machineX.toStringAsFixed(3)} '
        'Y${to.machineY.toStringAsFixed(3)} '
        'Z${to.machineZ.toStringAsFixed(3)} '
        'F$workFeed ; $comment',
      );
      buffer.writeln('M400');
      if (commandedPasteUl > 0.0001 &&
          pasteTravelMm > 0.0001 &&
          pasteSpeedMmPerS > 0.0001) {
        buffer.writeln('MANUAL_STEPPER STEPPER=paste_pump SYNC=1');
      }
      workLengthMm += xyDistanceMm;
      pasteVolumeUl += commandedPasteUl;
      workCount++;
      previous = to;
    }

    for (var index = 0; index < trajectory.length; index++) {
      final point = trajectory[index];
      if (!point.machineX.isFinite ||
          !point.machineY.isFinite ||
          !point.machineZ.isFinite) {
        continue;
      }

      if (previous == null || point.travel) {
        writePasteStop(
          previous == null ? 'initial travel' : 'work to travel before move',
        );
        buffer.writeln(
          'G1 X${point.machineX.toStringAsFixed(3)} '
          'Y${point.machineY.toStringAsFixed(3)} '
          'Z${point.machineZ.toStringAsFixed(3)} '
          'F$travelFeed ; travel/no paste',
        );
        buffer.writeln('M400');
        travelCount++;
        previous = point;
        continue;
      }

      final prev = previous!;
      final xyDistanceMm = _surfaceXyDistance(prev, point);
      if (xyDistanceMm <= 0.0001) {
        writeWorkMove(
          from: prev,
          to: point,
          commandedPasteUl: 0.0,
          comment: 'work/no paste',
        );
        continue;
      }

      final compensation =
          compensationByIndex[index] ??
          const _PasteSegmentCompensation(
            startDistanceBeforeMm: 0.0,
            remainingDistanceAfterMm: 0.0,
          );
      final segmentStartMm = compensation.startDistanceBeforeMm;
      final segmentEndMm = segmentStartMm + xyDistanceMm;
      final lineLengthMm = segmentEndMm + compensation.remainingDistanceAfterMm;
      final coastStartMm = coastDistanceMm <= 0
          ? lineLengthMm
          : math.max(0.0, lineLengthMm - coastDistanceMm);
      final stopInsideSegment =
          coastStartMm > segmentStartMm && coastStartMm < segmentEndMm;

      double commandedPasteFor(double fromMm, double toMm) {
        final effectiveEndMm = math.min(toMm, coastStartMm);
        final baseLengthMm = math.max(0.0, effectiveEndMm - fromMm);
        final boostLengthMm = startBoostDistanceMm > 0.0 && startBoostUl > 0.0
            ? _overlapLength(fromMm, toMm, 0.0, startBoostDistanceMm)
            : 0.0;
        final boostUl = startBoostDistanceMm > 0.0
            ? startBoostUl * boostLengthMm / startBoostDistanceMm
            : 0.0;
        boostVolumeUl += boostUl;
        return baseLengthMm * ulPerMm + boostUl;
      }

      if (stopInsideSegment) {
        final t = (coastStartMm - segmentStartMm) / xyDistanceMm;
        final stopPoint = _interpolateSurfaceToolPoint(
          prev,
          point,
          t,
          travel: false,
          sampleIndexInPolyline: point.safeSampleIndexInPolyline,
          isControlPoint: false,
        );
        final pasteUl = commandedPasteFor(segmentStartMm, coastStartMm);
        writeWorkMove(
          from: prev,
          to: stopPoint,
          commandedPasteUl: pasteUl,
          comment: 'work/paste before coast',
        );
        writePasteStop('coast before line end');
        coastLengthMm += segmentEndMm - coastStartMm;
        writeWorkMove(
          from: stopPoint,
          to: point,
          commandedPasteUl: 0.0,
          comment: 'work/coast no active paste',
        );
      } else {
        final inCoast = segmentStartMm >= coastStartMm;
        final pasteUl = inCoast
            ? 0.0
            : commandedPasteFor(segmentStartMm, segmentEndMm);
        if (inCoast) {
          writePasteStop('coast before line end');
          coastLengthMm += xyDistanceMm;
        }
        writeWorkMove(
          from: prev,
          to: point,
          commandedPasteUl: pasteUl,
          comment: pasteUl > 0.0 ? 'work/paste' : 'work/coast no active paste',
        );
      }
    }

    writePasteStop('end of paste test');
    buffer
      ..writeln('; Travel moves: $travelCount')
      ..writeln('; Work moves: $workCount')
      ..writeln('; Work length: ${workLengthMm.toStringAsFixed(3)} mm')
      ..writeln('; Estimated paste: ${pasteVolumeUl.toStringAsFixed(3)} uL')
      ..writeln('; Start boost volume: ${boostVolumeUl.toStringAsFixed(3)} uL')
      ..writeln('; Coast length: ${coastLengthMm.toStringAsFixed(3)} mm')
      ..writeln('PASTE_STATUS')
      ..writeln('M400');
    if (returnDwellMs > 0.0) {
      buffer.writeln('G4 P${returnDwellMs.round()} ; return dwell delay');
    }
    buffer
      ..writeln('G28 ; auto home after print')
      ..writeln('M400')
      ..writeln('G28 ; repeat home after print');
    return buffer.toString();
  }

  Map<int, _PasteSegmentCompensation> _pasteSegmentCompensations(
    List<_SurfaceToolPoint> trajectory,
  ) {
    final startBefore = <int, double>{};
    var distanceFromLineStart = 0.0;
    for (var i = 0; i < trajectory.length; i++) {
      final point = trajectory[i];
      if (i == 0 || point.travel) {
        distanceFromLineStart = 0.0;
        continue;
      }
      final previous = trajectory[i - 1];
      final distance = _surfaceXyDistance(previous, point);
      startBefore[i] = distanceFromLineStart;
      distanceFromLineStart += distance;
    }

    final remainingAfter = <int, double>{};
    var remaining = 0.0;
    for (var i = trajectory.length - 1; i >= 0; i--) {
      final point = trajectory[i];
      if (i == 0 || point.travel) {
        remaining = 0.0;
        continue;
      }
      final previous = trajectory[i - 1];
      final distance = _surfaceXyDistance(previous, point);
      remainingAfter[i] = remaining;
      remaining += distance;
    }

    return {
      for (final entry in startBefore.entries)
        entry.key: _PasteSegmentCompensation(
          startDistanceBeforeMm: entry.value,
          remainingDistanceAfterMm: remainingAfter[entry.key] ?? 0.0,
        ),
    };
  }

  double _surfaceXyDistance(_SurfaceToolPoint a, _SurfaceToolPoint b) {
    final dx = b.machineX - a.machineX;
    final dy = b.machineY - a.machineY;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _overlapLength(
    double aStart,
    double aEnd,
    double bStart,
    double bEnd,
  ) {
    return math.max(0.0, math.min(aEnd, bEnd) - math.max(aStart, bStart));
  }

  Future<String> _surfaceTrajectoryThumbnailGcode(
    List<_SurfaceToolPoint> trajectory,
  ) async {
    if (trajectory.length < 2) return '';
    final large = await _surfaceTrajectoryThumbnailBlock(trajectory, 300);
    final small = await _surfaceTrajectoryThumbnailBlock(trajectory, 32);
    if (large == null && small == null) return '';
    return [?large, ?small].join();
  }

  Future<String?> _surfaceTrajectoryThumbnailBlock(
    List<_SurfaceToolPoint> trajectory,
    int size,
  ) async {
    final png = await _renderSurfaceTrajectoryThumbnail(trajectory, size);
    if (png == null) return null;
    final encoded = base64Encode(png);
    final buffer = StringBuffer()
      ..writeln(';')
      ..writeln('; thumbnail begin ${size}x$size ${encoded.length}');
    for (var i = 0; i < encoded.length; i += 78) {
      buffer.writeln(
        '; ${encoded.substring(i, math.min(i + 78, encoded.length))}',
      );
    }
    buffer
      ..writeln('; thumbnail end')
      ..writeln(';');
    return buffer.toString();
  }

  Future<Uint8List?> _renderSurfaceTrajectoryThumbnail(
    List<_SurfaceToolPoint> trajectory,
    int size,
  ) async {
    final finite = trajectory
        .where(
          (point) =>
              point.machineX.isFinite &&
              point.machineY.isFinite &&
              point.machineZ.isFinite,
        )
        .toList(growable: false);
    if (finite.length < 2) return null;

    var minX = finite.first.machineX;
    var maxX = finite.first.machineX;
    var minY = finite.first.machineY;
    var maxY = finite.first.machineY;
    var minZ = finite.first.machineZ;
    var maxZ = finite.first.machineZ;
    for (final point in finite) {
      minX = math.min(minX, point.machineX);
      maxX = math.max(maxX, point.machineX);
      minY = math.min(minY, point.machineY);
      maxY = math.max(maxY, point.machineY);
      minZ = math.min(minZ, point.machineZ);
      maxZ = math.max(maxZ, point.machineZ);
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final imageSize = Size(size.toDouble(), size.toDouble());
    final bounds = Offset.zero & imageSize;
    final background = Paint()..color = const Color(0xFF15191F);
    canvas.drawRect(bounds, background);

    final rangeX = math.max(maxX - minX, 0.001);
    final rangeY = math.max(maxY - minY, 0.001);
    final margin = size * 0.10;
    final scale = math.min(
      (size - margin * 2) / rangeX,
      (size - margin * 2) / rangeY,
    );
    final contentWidth = rangeX * scale;
    final contentHeight = rangeY * scale;
    final offsetX = (size - contentWidth) / 2;
    final offsetY = (size - contentHeight) / 2;

    Offset mapPoint(_SurfaceToolPoint point) {
      return Offset(
        offsetX + (point.machineX - minX) * scale,
        size - offsetY - (point.machineY - minY) * scale,
      );
    }

    final gridPaint = Paint()
      ..color = const Color(0xFF2B333D)
      ..strokeWidth = math.max(1, size / 160);
    for (var i = 1; i < 4; i++) {
      final p = size * i / 4;
      canvas.drawLine(Offset(p, margin), Offset(p, size - margin), gridPaint);
      canvas.drawLine(Offset(margin, p), Offset(size - margin, p), gridPaint);
    }

    final travelPaint = Paint()
      ..color = const Color(0xFF64748B)
      ..strokeWidth = math.max(1, size / 95)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final workPaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = math.max(2, size / 55)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (var i = 1; i < finite.length; i++) {
      final previous = finite[i - 1];
      final current = finite[i];
      canvas.drawLine(
        mapPoint(previous),
        mapPoint(current),
        current.travel ? travelPaint : workPaint,
      );
    }

    final zSpan = math.max(maxZ - minZ, 0.001);
    final pointRadius = math.max(1.1, size / 95);
    final pointPaint = Paint()..style = PaintingStyle.fill;
    for (final point in finite) {
      final t = ((point.machineZ - minZ) / zSpan).clamp(0.0, 1.0);
      pointPaint.color = Color.lerp(
        const Color(0xFF22C55E),
        const Color(0xFFF59E0B),
        t,
      )!;
      canvas.drawCircle(mapPoint(point), pointRadius, pointPaint);
    }

    final startPaint = Paint()..color = const Color(0xFFFFFFFF);
    final endPaint = Paint()..color = const Color(0xFFEF4444);
    canvas.drawCircle(
      mapPoint(finite.first),
      math.max(2, size / 42),
      startPaint,
    );
    canvas.drawCircle(mapPoint(finite.last), math.max(2, size / 42), endPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    return byteData?.buffer.asUint8List();
  }

  List<_GcodeTrajectoryPoint> _gcodeTrajectoryPoints() {
    final trajectory = _exportTrajectory;
    if (trajectory.length < 2) return const [];
    final transform = _fitMachineXyToLocal(trajectory);
    if (transform == null) return const [];

    final points = <_GcodeTrajectoryPoint>[];
    for (final point in trajectory) {
      final x = point.machineX;
      final y = point.machineY;
      final z = point.machineZ;
      if (!x.isFinite || !y.isFinite || !z.isFinite) continue;
      final local = transform.localFromMachine(x, y);
      final nearest = _nearestSurfaceTrajectoryPoint(local, trajectory);
      if (nearest == null) continue;
      final height = z - (nearest.machineZ - nearest.surfaceHeight);
      points.add(
        _GcodeTrajectoryPoint(
          localX: local.dx,
          localY: local.dy,
          machineX: x,
          machineY: y,
          machineZ: z,
          height: height.isFinite ? height : nearest.surfaceHeight,
        ),
      );
    }
    return points;
  }

  _MachineToLocalTransform? _fitMachineXyToLocal(
    List<_SurfaceToolPoint> trajectory,
  ) {
    final samples = <_MachineLocalSample>[];
    for (final point in trajectory) {
      if (!point.machineX.isFinite ||
          !point.machineY.isFinite ||
          !point.localX.isFinite ||
          !point.localY.isFinite) {
        continue;
      }
      samples.add(
        _MachineLocalSample(
          machineX: point.machineX,
          machineY: point.machineY,
          localX: point.localX,
          localY: point.localY,
        ),
      );
    }
    if (samples.length < 3) return null;
    final xCoeffs = _fitAffineCoefficients(samples, (sample) => sample.localX);
    final yCoeffs = _fitAffineCoefficients(samples, (sample) => sample.localY);
    if (xCoeffs == null || yCoeffs == null) return null;
    return _MachineToLocalTransform(xCoeffs: xCoeffs, yCoeffs: yCoeffs);
  }

  _LocalToMachineTransform? _fitLocalToMachine(
    List<_SurfaceToolPoint> trajectory,
  ) {
    final samples = <_MachineLocalSample>[];
    for (final point in trajectory) {
      final machineX = point.targetMachineX ?? point.machineX;
      final machineY = point.targetMachineY ?? point.machineY;
      if (!machineX.isFinite ||
          !machineY.isFinite ||
          !point.localX.isFinite ||
          !point.localY.isFinite) {
        continue;
      }
      samples.add(
        _MachineLocalSample(
          machineX: machineX,
          machineY: machineY,
          localX: point.localX,
          localY: point.localY,
        ),
      );
    }
    if (samples.length < 3) return null;
    final xCoeffs = _fitLocalAffineCoefficients(
      samples,
      (sample) => sample.machineX,
    );
    final yCoeffs = _fitLocalAffineCoefficients(
      samples,
      (sample) => sample.machineY,
    );
    if (xCoeffs == null || yCoeffs == null) return null;
    return _LocalToMachineTransform(xCoeffs: xCoeffs, yCoeffs: yCoeffs);
  }

  List<double>? _fitLocalAffineCoefficients(
    List<_MachineLocalSample> samples,
    double Function(_MachineLocalSample sample) valueOf,
  ) {
    var s1 = 0.0;
    var sx = 0.0;
    var sy = 0.0;
    var sxx = 0.0;
    var sxy = 0.0;
    var syy = 0.0;
    var sv = 0.0;
    var sxv = 0.0;
    var syv = 0.0;
    for (final sample in samples) {
      final x = sample.localX;
      final y = sample.localY;
      final v = valueOf(sample);
      s1 += 1.0;
      sx += x;
      sy += y;
      sxx += x * x;
      sxy += x * y;
      syy += y * y;
      sv += v;
      sxv += x * v;
      syv += y * v;
    }
    return _solve3x3(
      [
        [s1, sx, sy],
        [sx, sxx, sxy],
        [sy, sxy, syy],
      ],
      [sv, sxv, syv],
    );
  }

  List<double>? _fitAffineCoefficients(
    List<_MachineLocalSample> samples,
    double Function(_MachineLocalSample sample) valueOf,
  ) {
    var s1 = 0.0;
    var sx = 0.0;
    var sy = 0.0;
    var sxx = 0.0;
    var sxy = 0.0;
    var syy = 0.0;
    var sv = 0.0;
    var sxv = 0.0;
    var syv = 0.0;
    for (final sample in samples) {
      final x = sample.machineX;
      final y = sample.machineY;
      final v = valueOf(sample);
      s1 += 1.0;
      sx += x;
      sy += y;
      sxx += x * x;
      sxy += x * y;
      syy += y * y;
      sv += v;
      sxv += x * v;
      syv += y * v;
    }
    return _solve3x3(
      [
        [s1, sx, sy],
        [sx, sxx, sxy],
        [sy, sxy, syy],
      ],
      [sv, sxv, syv],
    );
  }

  List<double>? _solve3x3(List<List<double>> matrix, List<double> rhs) {
    final a = [
      [...matrix[0], rhs[0]],
      [...matrix[1], rhs[1]],
      [...matrix[2], rhs[2]],
    ];
    for (var col = 0; col < 3; col++) {
      var pivot = col;
      var pivotAbs = a[col][col].abs();
      for (var row = col + 1; row < 3; row++) {
        final value = a[row][col].abs();
        if (value > pivotAbs) {
          pivot = row;
          pivotAbs = value;
        }
      }
      if (pivotAbs < 1e-12) return null;
      if (pivot != col) {
        final temp = a[col];
        a[col] = a[pivot];
        a[pivot] = temp;
      }
      final divisor = a[col][col];
      for (var item = col; item < 4; item++) {
        a[col][item] /= divisor;
      }
      for (var row = 0; row < 3; row++) {
        if (row == col) continue;
        final factor = a[row][col];
        if (factor.abs() < 1e-15) continue;
        for (var item = col; item < 4; item++) {
          a[row][item] -= factor * a[col][item];
        }
      }
    }
    return [a[0][3], a[1][3], a[2][3]];
  }

  _SurfaceToolPoint? _nearestSurfaceTrajectoryPoint(
    Offset local, [
    List<_SurfaceToolPoint>? source,
  ]) {
    final points = source ?? _surfaceTrajectory;
    if (points.isEmpty) return null;
    _SurfaceToolPoint? nearest;
    var bestDistance = double.infinity;
    for (final point in points) {
      final distance =
          math.pow(point.localX - local.dx, 2) +
          math.pow(point.localY - local.dy, 2);
      if (distance < bestDistance) {
        bestDistance = distance.toDouble();
        nearest = point;
      }
    }
    return nearest;
  }

  List<_ActualTrajectoryPoint> _actualVerificationTrajectoryPoints() {
    final result = _verificationResult;
    final captures = result?['captures'];
    if (captures is! List) return const [];

    final rows = <Map<String, dynamic>>[];
    for (final capture in captures) {
      if (capture is Map) {
        rows.add(Map<String, dynamic>.from(capture));
      }
    }
    rows.sort((a, b) {
      final aTrajectory = _jsonInt(a['trajectory_index'], 0);
      final bTrajectory = _jsonInt(b['trajectory_index'], 0);
      final byTrajectory = aTrajectory.compareTo(bTrajectory);
      if (byTrajectory != 0) return byTrajectory;
      return _jsonInt(a['index'], 0).compareTo(_jsonInt(b['index'], 0));
    });

    final points = <_ActualTrajectoryPoint>[];
    for (final row in rows) {
      final point = _actualPointFromCapture(row);
      if (point == null) continue;
      if (points.isNotEmpty &&
          (points.last.localOffset - point.localOffset).distance < 1e-6) {
        continue;
      }
      points.add(point);
    }
    return points;
  }

  List<_PlannedImageTrajectoryPoint> _plannedVerificationImagePoints() {
    if (_surfaceTrajectory.isNotEmpty) {
      final imageSize = _workpieceImageSize;
      if (imageSize == null) return const [];
      final points = <_PlannedImageTrajectoryPoint>[];
      for (final point in _surfaceTrajectory) {
        final imagePx = _stlProjectionLocalToImagePx(
          Offset(point.localX, point.localY),
          imageSize,
          _localizationOffsetPx,
          _localizationYawDeg,
          _localizationScalePxPerMm,
        );
        if (!imagePx.dx.isFinite || !imagePx.dy.isFinite) continue;
        final next = _PlannedImageTrajectoryPoint(imagePx: imagePx);
        if (points.isNotEmpty &&
            (points.last.imagePx - next.imagePx).distance < 1e-6) {
          continue;
        }
        points.add(next);
      }
      if (points.length >= 2) return points;
    }

    final result = _verificationResult;
    final captures = result?['captures'];
    if (captures is! List) return const [];

    final rows = <Map<String, dynamic>>[];
    for (final capture in captures) {
      if (capture is Map) {
        rows.add(Map<String, dynamic>.from(capture));
      }
    }
    rows.sort((a, b) {
      final aTrajectory = _jsonInt(a['trajectory_index'], 0);
      final bTrajectory = _jsonInt(b['trajectory_index'], 0);
      final byTrajectory = aTrajectory.compareTo(bTrajectory);
      if (byTrajectory != 0) return byTrajectory;
      return _jsonInt(a['index'], 0).compareTo(_jsonInt(b['index'], 0));
    });

    final points = <_PlannedImageTrajectoryPoint>[];
    for (final row in rows) {
      final target = _jsonMap(row['target']);
      if (target == null) continue;
      final imageX = _jsonDouble(target['image_x_px'], double.nan);
      final imageY = _jsonDouble(target['image_y_px'], double.nan);
      if (!imageX.isFinite || !imageY.isFinite) continue;
      final next = _PlannedImageTrajectoryPoint(
        imagePx: Offset(imageX, imageY),
      );
      if (points.isNotEmpty &&
          (points.last.imagePx - next.imagePx).distance < 1e-6) {
        continue;
      }
      points.add(next);
    }
    return points;
  }

  Offset _stlProjectionLocalToImagePx(
    Offset localMm,
    Size imageSize,
    Offset offsetPx,
    double yawDeg,
    double scalePxPerMm,
  ) {
    final localPx = Offset(
      localMm.dx * scalePxPerMm,
      -localMm.dy * scalePxPerMm,
    );
    final yaw = yawDeg * math.pi / 180.0;
    final cosYaw = math.cos(yaw);
    final sinYaw = math.sin(yaw);
    final rotated = Offset(
      localPx.dx * cosYaw - localPx.dy * sinYaw,
      localPx.dx * sinYaw + localPx.dy * cosYaw,
    );
    return Offset(
      imageSize.width / 2 + offsetPx.dx + rotated.dx,
      imageSize.height / 2 + offsetPx.dy + rotated.dy,
    );
  }

  _ActualTrajectoryPoint? _actualPointFromCapture(
    Map<String, dynamic> capture,
  ) {
    final actual =
        _jsonMap(capture['actual']) ??
        _jsonMap(capture['observed']) ??
        _jsonMap(capture['detected']);
    if (actual == null) return null;
    final target = _jsonMap(capture['target']);

    final x = _jsonDouble(
      actual['local_x_mm'] ?? actual['x_mm'] ?? actual['x'],
      double.nan,
    );
    final y = _jsonDouble(
      actual['local_y_mm'] ?? actual['y_mm'] ?? actual['y'],
      double.nan,
    );
    if (!x.isFinite || !y.isFinite) return null;
    final actualMachineZ = _jsonDouble(actual['machine_z_mm'], double.nan);
    final targetSurfaceHeight = _jsonDouble(
      target?['surface_height_mm'],
      double.nan,
    );
    final targetMachineZ = _jsonDouble(target?['machine_z_mm'], double.nan);
    final targetSurfaceOffset =
        targetMachineZ.isFinite && targetSurfaceHeight.isFinite
        ? targetMachineZ - targetSurfaceHeight
        : double.nan;
    final height = actualMachineZ.isFinite && targetSurfaceOffset.isFinite
        ? actualMachineZ - targetSurfaceOffset
        : _jsonDouble(
            actual['surface_height_mm'] ??
                actual['target_surface_height_mm'] ??
                actual['board_surface_z_mm'] ??
                target?['surface_height_mm'] ??
                actual['z_mm'] ??
                actual['z'],
            double.nan,
          );
    final imageX = _jsonDouble(
      actual['image_center_x_px'] ?? actual['image_x_px'] ?? actual['px_x'],
      double.nan,
    );
    final imageY = _jsonDouble(
      actual['image_center_y_px'] ?? actual['image_y_px'] ?? actual['px_y'],
      double.nan,
    );
    return _ActualTrajectoryPoint(
      localX: x,
      localY: y,
      height: height.isFinite ? height : null,
      imagePx: imageX.isFinite && imageY.isFinite
          ? Offset(imageX, imageY)
          : null,
    );
  }

  int _jsonInt(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  List<_PolylineSample> _samplePolyline(
    List<Offset> controlPoints,
    double stepMm,
  ) {
    if (controlPoints.length < 2) {
      return [
        for (final point in controlPoints)
          _PolylineSample(point: point, segmentIndex: 0, isControlPoint: true),
      ];
    }
    final result = <_PolylineSample>[];
    for (var i = 0; i < controlPoints.length - 1; i++) {
      final a = controlPoints[i];
      final b = controlPoints[i + 1];
      final segment = b - a;
      final length = segment.distance;
      final count = math.max(1, (length / stepMm).ceil());
      for (var j = 0; j <= count; j++) {
        if (i > 0 && j == 0) continue;
        final t = j / count;
        result.add(
          _PolylineSample(
            point: Offset(a.dx + segment.dx * t, a.dy + segment.dy * t),
            segmentIndex: i,
            isControlPoint: j == 0 || j == count,
          ),
        );
      }
    }
    return result;
  }

  _SurfaceSample? _sampleSurface(
    StlMesh mesh,
    _ProjectionBasis basis,
    double u,
    double v,
  ) {
    _SurfaceSample? top;
    for (final triangle in mesh.triangles) {
      final a = basis.project(triangle.a);
      final b = basis.project(triangle.b);
      final c = basis.project(triangle.c);
      final weights = _barycentricWeights(Offset(u, v), a, b, c);
      if (weights == null) continue;
      final height =
          weights[0] * basis.heightValue(triangle.a) +
          weights[1] * basis.heightValue(triangle.b) +
          weights[2] * basis.heightValue(triangle.c);
      if (top == null || height > top.height) {
        top = _SurfaceSample(
          height: height,
          normal: basis.projectNormal(triangle.normal),
        );
      }
    }
    return top;
  }

  List<double>? _barycentricWeights(
    Offset point,
    Offset a,
    Offset b,
    Offset c,
  ) {
    final v0 = b - a;
    final v1 = c - a;
    final v2 = point - a;
    final denom = v0.dx * v1.dy - v1.dx * v0.dy;
    if (denom.abs() < 1e-9) return null;
    final w1 = (v2.dx * v1.dy - v1.dx * v2.dy) / denom;
    final w2 = (v0.dx * v2.dy - v2.dx * v0.dy) / denom;
    final w0 = 1.0 - w1 - w2;
    const tolerance = 1e-6;
    if (w0 < -tolerance || w1 < -tolerance || w2 < -tolerance) return null;
    return [w0, w1, w2];
  }

  void _setView(_PresetView view) {
    setState(() {
      switch (view) {
        case _PresetView.top:
          _rotationX = 0;
          _rotationY = 0;
          _rotationZ = 0;
        case _PresetView.front:
          _rotationX = -math.pi / 2;
          _rotationY = 0;
          _rotationZ = 0;
        case _PresetView.side:
          _rotationX = -math.pi / 2;
          _rotationY = 0;
          _rotationZ = -math.pi / 2;
        case _PresetView.iso:
          _rotationX = -0.72;
          _rotationY = 0;
          _rotationZ = -0.72;
      }
      _zoom = 1.0;
      _pan = Offset.zero;
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartZoom = _zoom;
    _gestureStartPan = _pan;
    _gestureStartFocal = details.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_mesh == null) return;

    setState(() {
      if (details.pointerCount > 1) {
        _zoom = (_gestureStartZoom * details.scale).clamp(0.25, 8.0);
        _pan = _gestureStartPan + details.focalPoint - _gestureStartFocal;
      } else {
        _rotationZ += details.focalPointDelta.dx * 0.01;
        _rotationX = (_rotationX + details.focalPointDelta.dy * 0.01).clamp(
          -math.pi,
          math.pi,
        );
      }
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (_mesh == null || event is! PointerScrollEvent) return;
    final factor = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
    setState(() {
      _zoom = (_zoom * factor).clamp(0.25, 8.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 980;
        final sidePanel = _buildSidePanel(context);
        final preview = _buildPreviewCard(context);

        return Padding(
          padding: const EdgeInsets.all(16),
          child: compact
              ? SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      sidePanel,
                      const SizedBox(height: 12),
                      SizedBox(height: 560, child: preview),
                    ],
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 360,
                      child: SingleChildScrollView(child: sidePanel),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: preview),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildSidePanel(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildModelCard(context),
        _buildPhotoCaptureCard(context),
        _buildLocalizationCard(context),
        _buildSurfaceTrajectoryCard(context),
        _buildSurfaceFilesCard(context),
        _buildStlCheckCard(context),
        _buildNextStageCard(context),
      ],
    );
  }

  Widget _buildSurfaceFilesCard(BuildContext context) {
    final total = _surfaceFileGroups.fold<int>(
      0,
      (sum, group) => sum + group.items.length,
    );
    return FluiddCard(
      title: '曲面文件',
      collapsible: true,
      scrollable: false,
      actions: [
        IconButton(
          tooltip: '刷新文件',
          onPressed: _surfaceFilesLoading ? null : _refreshSurfaceFiles,
          icon: _surfaceFilesLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.folder_outlined,
                size: 18,
                color: Colors.grey.shade300,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _visualRootPath,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
              ),
              Text(
                '$total 项',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            ],
          ),
          if (_surfaceFilesError != null) ...[
            const SizedBox(height: 10),
            _MessageBox(message: _surfaceFilesError!, isError: true),
          ],
          const SizedBox(height: 8),
          if (_surfaceFileGroups.isEmpty && !_surfaceFilesLoading)
            Text('暂无曲面生成文件', style: TextStyle(color: Colors.grey.shade500))
          else
            ..._surfaceFileGroups.map(_buildSurfaceFileFolder),
        ],
      ),
    );
  }

  Widget _buildSurfaceFileFolder(_SurfaceFileGroup group) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: false,
        leading: const Icon(Icons.folder, size: 20),
        title: Text(group.location.label),
        subtitle: Text(
          group.location.path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
        ),
        trailing: Text(
          '${group.items.length}',
          style: TextStyle(color: Colors.grey.shade400),
        ),
        children: group.items.isEmpty
            ? [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 28, bottom: 8),
                    child: Text(
                      '空文件夹',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                ),
              ]
            : group.items.map(_buildSurfaceFileRow).toList(),
      ),
    );
  }

  Widget _buildSurfaceFileRow(_SurfaceManagedFile item) {
    final extension = _extensionOf(item.name);
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white10),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 8, right: 4, top: 6, bottom: 6),
          child: Row(
            children: [
              Icon(
                _surfaceFileIcon(item, extension),
                size: 18,
                color: item.isDirectory ? Colors.amber.shade300 : Colors.blue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.relativePath,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade100),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatBytes(item.sizeBytes)} · ${_formatDateTime(item.modified)}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '选择导入',
                onPressed: () => _importSurfaceManagedFile(item),
                icon: const Icon(Icons.file_open_outlined, size: 18),
              ),
              IconButton(
                tooltip: '重命名',
                onPressed: () => _renameSurfaceManagedFile(item),
                icon: const Icon(Icons.drive_file_rename_outline, size: 18),
              ),
              IconButton(
                tooltip: '删除',
                onPressed: () => _deleteSurfaceManagedFile(item),
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _surfaceFileIcon(_SurfaceManagedFile item, String extension) {
    if (item.isDirectory) return Icons.folder;
    if (_isImageExtension(extension)) return Icons.image_outlined;
    if (extension == 'json') return Icons.data_object;
    if (extension == 'dxf') return Icons.polyline_outlined;
    if (extension == 'csv') return Icons.table_chart_outlined;
    if (extension == 'gcode' || extension == 'g') {
      return Icons.precision_manufacturing_outlined;
    }
    if (extension == 'stl') return Icons.view_in_ar_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '-';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final decimals = unitIndex == 0 || value >= 10 ? 0 : 1;
    return '${value.toStringAsFixed(decimals)} ${units[unitIndex]}';
  }

  String _formatDateTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  Widget _buildModelCard(BuildContext context) {
    final mesh = _mesh;
    final bounds = mesh?.bounds;
    final theme = Theme.of(context);

    return FluiddCard(
      title: 'STL 模型',
      collapsible: true,
      scrollable: false,
      actions: [
        IconButton(
          tooltip: '加载 STL',
          onPressed: _loading ? null : _pickStl,
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.upload_file),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _pickStl,
              icon: const Icon(Icons.folder_open),
              label: Text(_mesh == null ? '选择 STL 文件' : '重新选择 STL'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _MessageBox(message: _error!, isError: true),
          ],
          const SizedBox(height: 14),
          if (mesh == null)
            Text(
              '等待加载 STL',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade400,
              ),
            )
          else ...[
            _InfoRow(label: '文件', value: _meshName ?? mesh.name),
            if (_meshPath != null && _meshPath!.isNotEmpty)
              _InfoRow(label: '路径', value: _meshPath!),
            const Divider(height: 24),
            _InfoRow(label: '面片', value: _formatInt(mesh.faceCount)),
            _InfoRow(label: '顶点', value: _formatInt(mesh.vertexCount)),
            if (bounds != null) ...[
              _InfoRow(label: '尺寸 X', value: '${_fmt(bounds.width)} mm'),
              _InfoRow(label: '尺寸 Y', value: '${_fmt(bounds.depth)} mm'),
              _InfoRow(label: '尺寸 Z', value: '${_fmt(bounds.height)} mm'),
              _InfoRow(label: '中心', value: _formatVector(bounds.center)),
              const Divider(height: 24),
              Text(
                '选择与床面接触的模型面',
                style: TextStyle(color: Colors.grey.shade300),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<_ContactFace>(
                initialValue: _contactFace,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: _ContactFace.values
                    .map(
                      (face) => DropdownMenuItem(
                        value: face,
                        child: Text(face.label),
                      ),
                    )
                    .toList(),
                onChanged: (face) {
                  if (face == null) return;
                  setState(() {
                    _contactFace = face;
                    _resetLocalizationFit();
                  });
                },
              ),
              const SizedBox(height: 8),
              _InfoRow(label: '床面 U', value: _projectionBasis.uAxis.label),
              _InfoRow(label: '床面 V', value: _projectionBasis.vAxis.label),
              _InfoRow(label: '高度方向', value: _projectionBasis.heightAxis.label),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildStlCheckCard(BuildContext context) {
    final mesh = _mesh;
    final bounds = mesh?.bounds;
    final hasMesh = mesh != null && !mesh.isEmpty;
    final hasSize = bounds != null && bounds.maxSpan > 0;
    final hasHeight = bounds != null && bounds.height > 0;

    return FluiddCard(
      title: '加载检查',
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusLine(
            label: 'STL 解析',
            value: hasMesh ? 'OK' : 'Not loaded',
            ok: hasMesh,
          ),
          _StatusLine(
            label: 'Bounds',
            value: hasSize ? '有效' : '等待数据',
            ok: hasSize,
          ),
          _StatusLine(
            label: '高度信息',
            value: hasHeight ? 'OK' : 'Pending',
            ok: hasHeight,
          ),
          if (bounds != null) ...[
            const SizedBox(height: 12),
            _BoundsTable(bounds: bounds),
          ],
          const SizedBox(height: 12),
          _MessageBox(
            message: hasMesh
                ? 'STL loaded. Confirm units, orientation, and pose before motion.'
                : 'Load an STL to inspect size, center, bounds, and height.',
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoCaptureCard(BuildContext context) {
    final camera = context.watch<CameraViewerController>();
    final hasPhoto = _workpiecePhotoBytes != null;

    return FluiddCard(
      title: '工件拍照',
      collapsible: true,
      subtitle: hasPhoto ? 'Photo captured' : 'Move platform away first',
      scrollable: false,
      actions: [
        IconButton(
          tooltip: 'Probe camera service',
          onPressed: camera.probeService,
          icon: Icon(
            Icons.health_and_safety_outlined,
            color: camera.serviceRunning ? Colors.greenAccent : Colors.grey,
          ),
        ),
        IconButton(
          tooltip: camera.serviceRunning ? '停止相机服务' : '启动相机服务',
          onPressed: camera.serviceStarting
              ? null
              : camera.serviceRunning
              ? camera.stopCameraService
              : camera.startCameraService,
          icon: Icon(
            camera.serviceRunning
                ? Icons.power_settings_new
                : Icons.video_call_outlined,
            color: camera.serviceRunning ? Colors.orangeAccent : Colors.blue,
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            value: _platformClearedForPhoto,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('末端平台已手动移到不遮挡的位置'),
            onChanged: (value) {
              setState(() => _platformClearedForPhoto = value ?? false);
            },
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: !_platformClearedForPhoto || _capturingWorkpiece
                ? null
                : _captureWorkpiecePhoto,
            icon: _capturingWorkpiece
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_camera_outlined),
            label: Text(
              _capturingWorkpiece ? 'Capturing...' : 'Capture workpiece photo',
            ),
          ),
          if (_workpiecePhotoError != null) ...[
            const SizedBox(height: 12),
            _MessageBox(message: _workpiecePhotoError!, isError: true),
          ],
          if (hasPhoto) ...[
            const SizedBox(height: 12),
            _InfoRow(label: '时间', value: _formatTime(_workpiecePhotoAt)),
            if (_workpiecePhotoPath != null)
              _InfoRow(label: '照片', value: _workpiecePhotoPath!),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() => _workspaceView = 1),
              icon: const Icon(Icons.image_search_outlined),
              label: const Text('查看工件照片'),
            ),
          ],
          if (!camera.serviceRunning && camera.serviceError != null) ...[
            const SizedBox(height: 12),
            _MessageBox(message: camera.serviceError!, isError: true),
          ],
        ],
      ),
    );
  }

  Widget _buildLocalizationCard(BuildContext context) {
    final ready = _localizationReady;
    final imageSize = _workpieceImageSize;
    final shiftLimit = math.max(
      200.0,
      ((imageSize?.longestSide ?? 1200.0) * 0.75).toDouble(),
    );
    final scaleMax = math.max(8.0, _localizationScalePxPerMm * 2.5);
    final centerPx = imageSize == null
        ? null
        : Offset(
            imageSize.width / 2 + _localizationOffsetPx.dx,
            imageSize.height / 2 + _localizationOffsetPx.dy,
          );

    return FluiddCard(
      title: '人工辅助定位',
      collapsible: true,
      subtitle: ready ? '可以开始对齐' : '等待 STL 和照片',
      scrollable: false,
      actions: [
        IconButton(
          tooltip: '导入定位结果',
          onPressed: _importLocalizationResult,
          icon: const Icon(Icons.file_open_outlined),
        ),
        IconButton(
          tooltip: 'Load latest localization',
          onPressed: _loadLatestLocalizationResult,
          icon: const Icon(Icons.history),
        ),
        IconButton(
          tooltip: '进入定位视图',
          onPressed: ready ? () => setState(() => _workspaceView = 2) : null,
          icon: const Icon(Icons.control_camera_outlined),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusLine(
            label: 'STL 模型',
            value: _mesh == null ? 'Not loaded' : 'Available',
            ok: _mesh != null && !_mesh!.isEmpty,
          ),
          _StatusLine(
            label: '工件照片',
            value: _workpiecePhotoBytes == null ? 'No photo' : 'Available',
            ok: _workpiecePhotoBytes != null,
          ),
          _InfoRow(label: '接触面', value: _contactFace.label),
          _InfoRow(
            label: '投影坐标轴',
            value:
                '${_projectionBasis.uAxis.label} / ${_projectionBasis.vAxis.label}',
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: ready ? () => setState(() => _workspaceView = 2) : null,
            icon: const Icon(Icons.my_location),
            label: const Text('进入人工定位'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: ready
                      ? () => setState(() => _resetLocalizationFit())
                      : null,
                  icon: const Icon(Icons.center_focus_strong),
                  label: const Text('居中适配'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: ready
                    ? () {
                        setState(() {
                          _localizationYawDeg =
                              (_localizationYawDeg + 180.0) % 360.0;
                          if (_localizationYawDeg > 180.0) {
                            _localizationYawDeg -= 360.0;
                          }
                          _localizationResultPath = null;
                        });
                        _scheduleLocalizationAutosave();
                      }
                    : null,
                icon: const Icon(Icons.rotate_90_degrees_ccw),
                label: const Text('180度'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('位置微调', style: TextStyle(color: Colors.grey.shade300)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '左移',
                onPressed: ready ? () => _nudgeLocalization(-5, 0) : null,
                icon: const Icon(Icons.keyboard_arrow_left),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '上移',
                    onPressed: ready ? () => _nudgeLocalization(0, -5) : null,
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                  IconButton(
                    tooltip: '下移',
                    onPressed: ready ? () => _nudgeLocalization(0, 5) : null,
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                ],
              ),
              IconButton(
                tooltip: '右移',
                onPressed: ready ? () => _nudgeLocalization(5, 0) : null,
                icon: const Icon(Icons.keyboard_arrow_right),
              ),
            ],
          ),
          _buildLabeledSlider(
            label: 'X 偏移',
            value: _localizationOffsetPx.dx.clamp(-shiftLimit, shiftLimit),
            min: -shiftLimit,
            max: shiftLimit,
            unit: 'px',
            enabled: ready,
            onChanged: (value) {
              setState(() {
                _localizationOffsetPx = Offset(value, _localizationOffsetPx.dy);
                _localizationResultPath = null;
              });
              _scheduleLocalizationAutosave();
            },
          ),
          _buildLabeledSlider(
            label: 'Y 偏移',
            value: _localizationOffsetPx.dy.clamp(-shiftLimit, shiftLimit),
            min: -shiftLimit,
            max: shiftLimit,
            unit: 'px',
            enabled: ready,
            onChanged: (value) {
              setState(() {
                _localizationOffsetPx = Offset(_localizationOffsetPx.dx, value);
                _localizationResultPath = null;
              });
              _scheduleLocalizationAutosave();
            },
          ),
          _buildLabeledSlider(
            label: 'Yaw',
            value: _localizationYawDeg.clamp(-180.0, 180.0),
            min: -180,
            max: 180,
            unit: 'deg',
            enabled: ready,
            onChanged: (value) {
              setState(() {
                _localizationYawDeg = value;
                _localizationResultPath = null;
              });
              _scheduleLocalizationAutosave();
            },
          ),
          _buildLabeledSlider(
            label: '缩放比例',
            value: _localizationScalePxPerMm.clamp(0.05, scaleMax),
            min: 0.05,
            max: scaleMax,
            unit: 'px/mm',
            enabled: ready,
            onChanged: (value) {
              setState(() {
                _localizationScalePxPerMm = value;
                _localizationResultPath = null;
              });
              _scheduleLocalizationAutosave();
            },
          ),
          _buildLabeledSlider(
            label: 'Overlay opacity',
            value: _localizationOpacity,
            min: 0.15,
            max: 1.0,
            unit: '',
            enabled: ready,
            onChanged: (value) {
              setState(() => _localizationOpacity = value);
            },
          ),
          SwitchListTile(
            value: _showLocalizationHeightMap,
            contentPadding: EdgeInsets.zero,
            title: const Text('显示 STL 高度云图'),
            onChanged: ready
                ? (value) => setState(() => _showLocalizationHeightMap = value)
                : null,
          ),
          SwitchListTile(
            value: _showLocalizationMesh,
            contentPadding: EdgeInsets.zero,
            title: const Text('显示 STL 投影网格'),
            onChanged: ready
                ? (value) => setState(() => _showLocalizationMesh = value)
                : null,
          ),
          SwitchListTile(
            value: _showLocalizationAxes,
            contentPadding: EdgeInsets.zero,
            title: const Text('显示模型坐标轴'),
            onChanged: ready
                ? (value) => setState(() => _showLocalizationAxes = value)
                : null,
          ),
          SwitchListTile(
            value: _showLocalizationBounds,
            contentPadding: EdgeInsets.zero,
            title: const Text('显示模型包围框'),
            onChanged: ready
                ? (value) => setState(() => _showLocalizationBounds = value)
                : null,
          ),
          SwitchListTile(
            value: _showLocalizationHandles,
            contentPadding: EdgeInsets.zero,
            title: const Text('显示对齐控制点'),
            onChanged: ready
                ? (value) => setState(() => _showLocalizationHandles = value)
                : null,
          ),
          if (_showLocalizationHandles)
            _MessageBox(
              message: _lockedAlignmentHandle == null
                  ? '拖动控制点对齐模型；双击控制点可锁定。'
                  : '已锁定 ${_lockedAlignmentHandle!.label}；拖动其他点可调整缩放和偏移。',
            ),
          if (centerPx != null) ...[
            const SizedBox(height: 8),
            _InfoRow(
              label: '中心像素',
              value: '(${_fmt(centerPx.dx)}, ${_fmt(centerPx.dy)})',
            ),
            _InfoRow(label: '角度', value: '${_fmt(_localizationYawDeg)}度'),
            _InfoRow(
              label: '比例',
              value: '${_fmt(_localizationScalePxPerMm)} px/mm',
            ),
            _InfoRow(
              label: '锁定点',
              value: _lockedAlignmentHandle?.label ?? '未锁定',
            ),
            if (_lockedAlignmentHandle != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _clearAlignmentHandleLock,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('解除锁定'),
                ),
              ),
          ],
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: ready ? _saveLocalizationResult : null,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存定位结果'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _importLocalizationResult,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('导入定位结果'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loadLatestLocalizationResult,
                  icon: const Icon(Icons.history),
                  label: const Text('读取最近结果'),
                ),
              ),
            ],
          ),
          if (_localizationResultPath != null) ...[
            const SizedBox(height: 10),
            _InfoRow(label: '结果', value: _localizationResultPath!),
          ],
          if (_localizationError != null) ...[
            const SizedBox(height: 10),
            _MessageBox(message: _localizationError!, isError: true),
          ],
        ],
      ),
    );
  }

  Widget _buildSurfaceTrajectoryCard(BuildContext context) {
    final mesh = _mesh;
    final ready = mesh != null && !mesh.isEmpty;
    final localized = _localizationResultPath != null;
    final basis = _projectionBasis;
    final projectedSize = mesh == null || mesh.isEmpty
        ? Size.zero
        : basis.projectedSize(mesh.bounds);
    final widthMax = math.max(5.0, projectedSize.width * 0.95);
    final heightMax = math.max(5.0, projectedSize.height * 0.95);
    final centerXLimit = math.max(1.0, projectedSize.width);
    final centerYLimit = math.max(1.0, projectedSize.height);
    final stats = _SurfaceTrajectoryStats.fromPoints(_surfaceTrajectory);
    final motionStats = _SurfaceTrajectoryStats.fromPoints(_exportTrajectory);
    final hasSmoothMotion = _surfaceMotionTrajectory.isNotEmpty;
    final exportModeLabel = hasSmoothMotion ? '平滑' : '基础';
    final dxf = _dxfToolpath;
    final usingDxfSource =
        _surfaceTrajectorySource == _SurfaceTrajectorySource.dxf;
    final sourceReady = _surfaceTrajectorySourceReady;
    final canGenerateTrajectory = ready && sourceReady;
    final widthLabel = usingDxfSource ? 'DXF宽度' : '图案宽度';
    final heightLabel = usingDxfSource ? 'DXF高度' : '图案高度';
    final angleLabel = usingDxfSource ? 'DXF角度' : '图案角度';
    final centerXLabel = usingDxfSource ? 'DXF中心 X' : '图案中心 X';
    final centerYLabel = usingDxfSource ? 'DXF中心 Y' : '图案中心 Y';
    final printer = context.watch<PrinterController>();
    final canOneClickStart = _canOneClickStart(
      printer: printer,
      ready: ready,
      localized: localized,
      sourceReady: sourceReady,
    );
    final canPasteTestStart =
        !_surfacePasteTestStarting &&
        !_surfaceOneClickStarting &&
        (_surfaceTrajectory.isNotEmpty || (ready && localized && sourceReady));
    final pastePreviewRate =
        _surfacePasteUlPerMm * _surfaceWorkSpeedMmPerS.clamp(0.1, 120.0);
    final verificationKeyPointCount = _surfaceTrajectory.isEmpty
        ? _expectedVerificationKeyPointCount()
        : _verificationSamplePoints().length;

    return FluiddCard(
      title: '曲面恒距轨迹',
      collapsible: true,
      subtitle: _surfaceTrajectory.isEmpty ? '生成验证路径' : '轨迹已生成',
      scrollable: false,
      actions: [
        IconButton(
          tooltip: '查看轨迹预览',
          onPressed: ready ? () => setState(() => _workspaceView = 3) : null,
          icon: const Icon(Icons.timeline),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusLine(label: 'STL 高度', value: ready ? '可采样' : '未加载', ok: ready),
          _StatusLine(
            label: '工件定位',
            value: localized ? '已保存' : '建议先保存',
            ok: localized,
          ),
          _InfoRow(label: '接触面', value: _contactFace.label),
          _InfoRow(
            label: '投影尺寸',
            value:
                '${_fmt(projectedSize.width)} x ${_fmt(projectedSize.height)} mm',
          ),
          const SizedBox(height: 10),
          SegmentedButton<_SurfaceTrajectorySource>(
            segments: _SurfaceTrajectorySource.values
                .map(
                  (source) => ButtonSegment<_SurfaceTrajectorySource>(
                    value: source,
                    icon: Icon(source.icon),
                    label: Text(source.label),
                  ),
                )
                .toList(growable: false),
            selected: {_surfaceTrajectorySource},
            onSelectionChanged: ready
                ? (values) {
                    final source = values.first;
                    setState(() {
                      _surfaceTrajectorySource = source;
                      _clearGeneratedSurfaceTrajectory();
                    });
                  }
                : null,
          ),
          const SizedBox(height: 10),
          if (!usingDxfSource)
            DropdownButtonFormField<_SurfacePattern>(
              initialValue: _surfacePattern,
              decoration: const InputDecoration(
                labelText: '测试图案',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: _SurfacePattern.values
                  .map(
                    (pattern) => DropdownMenuItem(
                      value: pattern,
                      child: Text(pattern.label),
                    ),
                  )
                  .toList(),
              onChanged: ready
                  ? (pattern) {
                      if (pattern == null) return;
                      setState(() {
                        _surfacePattern = pattern;
                        _clearGeneratedSurfaceTrajectory();
                      });
                    }
                  : null,
            ),
          if (usingDxfSource) ...[
            FilledButton.icon(
              onPressed: _dxfLoading ? null : _pickDxf,
              icon: _dxfLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(dxf == null ? '导入 DXF 文件' : '重新导入 DXF'),
            ),
            const SizedBox(height: 8),
            if (dxf == null)
              const _MessageBox(
                message:
                    '支持 DXF: LINE, LWPOLYLINE, POLYLINE, ARC, CIRCLE。SPLINE 和 Block/INSERT 暂不解析。',
              )
            else ...[
              _InfoRow(label: 'DXF', value: dxf.name),
              _InfoRow(
                label: '几何',
                value:
                    '${dxf.polylines.length} 条 | ${dxf.pointCount} 点 | ${_fmt(dxf.totalLengthMm)} mm',
              ),
              _InfoRow(
                label: '原尺寸',
                value: '${_fmt(dxf.widthMm)} x ${_fmt(dxf.heightMm)} mm',
              ),
              if (dxf.layers.isNotEmpty)
                _InfoRow(label: '图层', value: dxf.layers.take(8).join(', ')),
              if (_dxfPath != null) _InfoRow(label: '路径', value: _dxfPath!),
            ],
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('保持 DXF 宽高比例'),
              value: _dxfKeepAspectRatio,
              onChanged: ready
                  ? (value) => setState(() {
                      _dxfKeepAspectRatio = value ?? true;
                      _clearGeneratedSurfaceTrajectory();
                    })
                  : null,
            ),
            if (_dxfWarning != null)
              _MessageBox(message: _dxfWarning!, isError: false),
            if (_dxfError != null)
              _MessageBox(message: _dxfError!, isError: true),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: _buildTrajectoryNumberInput(
                  label: widthLabel,
                  value: _surfacePatternWidthMm.clamp(1.0, widthMax).toDouble(),
                  min: 1.0,
                  max: widthMax,
                  unit: 'mm',
                  enabled: ready,
                  onChanged: (value) => setState(() {
                    _surfacePatternWidthMm = value;
                    _clearGeneratedSurfaceTrajectory();
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTrajectoryNumberInput(
                  label: heightLabel,
                  value: _surfacePatternHeightMm
                      .clamp(1.0, heightMax)
                      .toDouble(),
                  min: 1.0,
                  max: heightMax,
                  unit: 'mm',
                  enabled:
                      ready && (usingDxfSource || _surfacePattern.usesHeight),
                  onChanged: (value) => setState(() {
                    _surfacePatternHeightMm = value;
                    _clearGeneratedSurfaceTrajectory();
                  }),
                ),
              ),
            ],
          ),
          _buildTrajectoryNumberInput(
            label: angleLabel,
            value: _surfacePatternRotationDeg.clamp(-180.0, 180.0).toDouble(),
            min: -180.0,
            max: 180.0,
            unit: 'deg',
            enabled: ready,
            onChanged: (value) => setState(() {
              _surfacePatternRotationDeg = value;
              _clearGeneratedSurfaceTrajectory();
            }),
          ),
          Row(
            children: [
              Expanded(
                child: _buildTrajectoryNumberInput(
                  label: centerXLabel,
                  value: _surfacePatternCenterLocal.dx
                      .clamp(-centerXLimit, centerXLimit)
                      .toDouble(),
                  min: -centerXLimit,
                  max: centerXLimit,
                  unit: 'mm',
                  enabled: ready,
                  onChanged: (value) => setState(() {
                    _surfacePatternCenterLocal = Offset(
                      value,
                      _surfacePatternCenterLocal.dy,
                    );
                    _clearGeneratedSurfaceTrajectory();
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTrajectoryNumberInput(
                  label: centerYLabel,
                  value: _surfacePatternCenterLocal.dy
                      .clamp(-centerYLimit, centerYLimit)
                      .toDouble(),
                  min: -centerYLimit,
                  max: centerYLimit,
                  unit: 'mm',
                  enabled: ready,
                  onChanged: (value) => setState(() {
                    _surfacePatternCenterLocal = Offset(
                      _surfacePatternCenterLocal.dx,
                      value,
                    );
                    _clearGeneratedSurfaceTrajectory();
                  }),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _buildTrajectoryNumberInput(
                  label: '恒定间距',
                  value: _surfaceClearanceMm.clamp(0.5, 30.0).toDouble(),
                  min: 0.5,
                  max: 30.0,
                  unit: 'mm',
                  enabled: ready,
                  onChanged: (value) => setState(() {
                    _surfaceClearanceMm = value;
                    _clearGeneratedSurfaceTrajectory();
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTrajectoryNumberInput(
                  label: '采样步距',
                  value: _surfaceSampleStepMm.clamp(0.2, 10.0).toDouble(),
                  min: 0.2,
                  max: 10.0,
                  unit: 'mm',
                  enabled: ready,
                  onChanged: (value) => setState(() {
                    _surfaceSampleStepMm = value;
                    _clearGeneratedSurfaceTrajectory();
                  }),
                ),
              ),
            ],
          ),
          _buildSurfaceToolOrientationPanel(ready: ready),
          const SizedBox(height: 8),
          _buildSurfaceBedZCalibrationPanel(ready: ready),
          Row(
            children: [
              Expanded(
                child: _buildTrajectoryNumberInput(
                  label: '空移速度',
                  value: _surfaceTravelSpeedMmPerS.clamp(1.0, 120.0).toDouble(),
                  min: 1.0,
                  max: 120.0,
                  unit: 'mm/s',
                  enabled: ready,
                  onChanged: (value) => setState(() {
                    _surfaceTravelSpeedMmPerS = value;
                    _clearGeneratedSurfaceTrajectory();
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTrajectoryNumberInput(
                  label: '工作速度',
                  value: _surfaceWorkSpeedMmPerS.clamp(1.0, 80.0).toDouble(),
                  min: 1.0,
                  max: 80.0,
                  unit: 'mm/s',
                  enabled: ready,
                  onChanged: (value) => setState(() {
                    _surfaceWorkSpeedMmPerS = value;
                    _clearGeneratedSurfaceTrajectory();
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              '应用曲面局部补偿',
              style: TextStyle(color: Colors.grey.shade200, fontSize: 13),
            ),
            subtitle: Text(
              '使用上一次曲面验证的均值残差，重新生成轨迹后生效',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
            value: _applySurfaceCommandCorrection,
            onChanged: _verificationRunning
                ? null
                : (value) => setState(() {
                    _applySurfaceCommandCorrection = value;
                    _clearGeneratedSurfaceTrajectory();
                  }),
          ),
          FilledButton.icon(
            onPressed: canGenerateTrajectory
                ? _generateSurfaceTrajectory
                : null,
            icon: const Icon(Icons.route_outlined),
            label: const Text('生成恒距基础轨迹'),
          ),
          if (_surfaceTrajectory.isNotEmpty) ...[
            const SizedBox(height: 10),
            _InfoRow(label: '轨迹点', value: '${_surfaceTrajectory.length}'),
            _InfoRow(
              label: 'Z 范围',
              value: '${_fmt(stats.minZ)} .. ${_fmt(stats.maxZ)} mm',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildTrajectoryNumberInput(
                    label: '平滑 XY 步距',
                    value: _surfaceSmoothStepMm.clamp(0.1, 5.0).toDouble(),
                    min: 0.1,
                    max: 5.0,
                    unit: 'mm',
                    enabled: !_verificationRunning,
                    onChanged: (value) => setState(() {
                      _surfaceSmoothStepMm = value;
                      _surfaceMotionTrajectory = const [];
                      _surfaceGcodePath = null;
                      _surfaceMotionError = null;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTrajectoryNumberInput(
                    label: '单段最大 Z',
                    value: _surfaceSmoothMaxZStepMm.clamp(0.02, 2.0).toDouble(),
                    min: 0.02,
                    max: 2.0,
                    unit: 'mm',
                    enabled: !_verificationRunning,
                    onChanged: (value) => setState(() {
                      _surfaceSmoothMaxZStepMm = value;
                      _surfaceMotionTrajectory = const [];
                      _surfaceGcodePath = null;
                      _surfaceMotionError = null;
                    }),
                  ),
                ),
              ],
            ),
            FilledButton.icon(
              onPressed: _verificationRunning
                  ? null
                  : _generateSmoothSurfaceMotionTrajectory,
              icon: const Icon(Icons.ssid_chart),
              label: const Text('生成平滑运动轨迹'),
            ),
            if (_surfaceTrajectory.isNotEmpty && !canOneClickStart) ...[
              const SizedBox(height: 8),
              _MessageBox(
                message:
                    _surfaceMotionPreflight(printer).blockingReason ??
                    '当前条件不满足一键启动。',
                isError: true,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: canOneClickStart
                        ? _startSurfaceMotionOneClick
                        : null,
                    icon: _surfaceOneClickStarting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(
                      _surfaceOneClickStarting ? '正在启动...' : '一键启动平滑运动',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: '查询下位机归零状态',
                  onPressed: _surfaceHomingStatusRefreshing
                      ? null
                      : _refreshSurfaceHomingStatus,
                  icon: _surfaceHomingStatusRefreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('锡膏同步测试'),
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildTrajectoryNumberInput(
                        label: '锡膏量',
                        value: _surfacePasteUlPerMm.clamp(0.01, 5.0).toDouble(),
                        min: 0.01,
                        max: 5.0,
                        unit: 'uL/mm',
                        enabled: !_surfacePasteTestStarting,
                        onChanged: (value) => _setSurfacePasteSetting(
                          () => _surfacePasteUlPerMm = value,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTrajectoryNumberInput(
                        label: '起始预压',
                        value: _surfacePasteStartPrimeUl
                            .clamp(0.0, _surfacePastePrimeRetractMaxUl)
                            .toDouble(),
                        min: 0.0,
                        max: _surfacePastePrimeRetractMaxUl,
                        unit: 'uL',
                        enabled: !_surfacePasteTestStarting,
                        onChanged: (value) => _setSurfacePasteSetting(
                          () => _surfacePasteStartPrimeUl = value,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTrajectoryNumberInput(
                        label: '停胶回抽',
                        value: _surfacePasteStopRetractUl
                            .clamp(0.0, _surfacePastePrimeRetractMaxUl)
                            .toDouble(),
                        min: 0.0,
                        max: _surfacePastePrimeRetractMaxUl,
                        unit: 'uL',
                        enabled: !_surfacePasteTestStarting,
                        onChanged: (value) => _setSurfacePasteSetting(
                          () => _surfacePasteStopRetractUl = value,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildTrajectoryNumberInput(
                        label: '预压速度',
                        value: _surfacePasteStartPrimeRateUlPerS
                            .clamp(0.5, 300.0)
                            .toDouble(),
                        min: 0.5,
                        max: 300.0,
                        unit: 'uL/s',
                        enabled: !_surfacePasteTestStarting,
                        onChanged: (value) => _setSurfacePasteSetting(
                          () => _surfacePasteStartPrimeRateUlPerS = value,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTrajectoryNumberInput(
                        label: '回抽速度',
                        value: _surfacePasteStopRetractRateUlPerS
                            .clamp(0.5, 300.0)
                            .toDouble(),
                        min: 0.5,
                        max: 300.0,
                        unit: 'uL/s',
                        enabled: !_surfacePasteTestStarting,
                        onChanged: (value) => _setSurfacePasteSetting(
                          () => _surfacePasteStopRetractRateUlPerS = value,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildTrajectoryNumberInput(
                        label: '前段补偿',
                        value: _surfacePasteStartBoostUl
                            .clamp(0.0, 100.0)
                            .toDouble(),
                        min: 0.0,
                        max: 100.0,
                        unit: 'uL',
                        enabled: !_surfacePasteTestStarting,
                        onChanged: (value) => _setSurfacePasteSetting(
                          () => _surfacePasteStartBoostUl = value,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTrajectoryNumberInput(
                        label: '补偿长度',
                        value: _surfacePasteStartBoostDistanceMm
                            .clamp(0.0, 100.0)
                            .toDouble(),
                        min: 0.0,
                        max: 100.0,
                        unit: 'mm',
                        enabled: !_surfacePasteTestStarting,
                        onChanged: (value) => _setSurfacePasteSetting(
                          () => _surfacePasteStartBoostDistanceMm = value,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _buildTrajectoryNumberInput(
                        label: '提前停胶',
                        value: _surfacePasteCoastDistanceMm
                            .clamp(0.0, 100.0)
                            .toDouble(),
                        min: 0.0,
                        max: 100.0,
                        unit: 'mm',
                        enabled: !_surfacePasteTestStarting,
                        onChanged: (value) => _setSurfacePasteSetting(
                          () => _surfacePasteCoastDistanceMm = value,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTrajectoryNumberInput(
                        label: '停胶等待',
                        value: _surfacePasteStopDwellMs
                            .clamp(0.0, 3000.0)
                            .toDouble(),
                        min: 0.0,
                        max: 3000.0,
                        unit: 'ms',
                        enabled: !_surfacePasteTestStarting,
                        onChanged: (value) => _setSurfacePasteSetting(
                          () => _surfacePasteStopDwellMs = value,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildTrajectoryNumberInput(
                        label: '起始等待',
                        value: _surfacePasteStartDwellMs
                            .clamp(0.0, 10000.0)
                            .toDouble(),
                        min: 0.0,
                        max: 10000.0,
                        unit: 'ms',
                        enabled: !_surfacePasteTestStarting,
                        onChanged: (value) => _setSurfacePasteSetting(
                          () => _surfacePasteStartDwellMs = value,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTrajectoryNumberInput(
                        label: '归程等待时间',
                        value: _surfacePasteReturnDwellMs
                            .clamp(0.0, 10000.0)
                            .toDouble(),
                        min: 0.0,
                        max: 10000.0,
                        unit: 'ms',
                        enabled: !_surfacePasteTestStarting,
                        onChanged: (value) => _setSurfacePasteSetting(
                          () => _surfacePasteReturnDwellMs = value,
                        ),
                      ),
                    ),
                  ],
                ),
                _InfoRow(
                  label: '工作段估算速率',
                  value: '${_fmt(pastePreviewRate.toDouble())} uL/s',
                ),
                FilledButton.icon(
                  onPressed: canPasteTestStart
                      ? _startSurfacePasteTestOneClick
                      : null,
                  icon: _surfacePasteTestStarting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.science_outlined),
                  label: Text(
                    _surfacePasteTestStarting ? '正在启动测试...' : '测试轨迹 + 锡膏',
                  ),
                ),
                if (hasSmoothMotion) ...[
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: '平滑点',
                    value: '${_surfaceMotionTrajectory.length}',
                  ),
                  _InfoRow(
                    label: '平滑 Z 范围',
                    value:
                        '${_fmt(motionStats.minZ)} .. ${_fmt(motionStats.maxZ)} mm',
                  ),
                ],
                if (_surfaceMotionError != null) ...[
                  const SizedBox(height: 8),
                  _MessageBox(message: _surfaceMotionError!, isError: true),
                ],
                if (_surfaceOneClickStatus != null) ...[
                  const SizedBox(height: 8),
                  _MessageBox(message: _surfaceOneClickStatus!),
                ],
                if (_surfacePasteTestStatus != null) ...[
                  const SizedBox(height: 8),
                  _MessageBox(message: _surfacePasteTestStatus!),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _exportSurfaceTrajectoryCsv,
                    icon: const Icon(Icons.table_chart_outlined),
                    label: Text('导出 CSV（$exportModeLabel）'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _exportSurfaceTrajectoryGcode,
                    icon: const Icon(Icons.data_object),
                    label: Text('导出 G-code（$exportModeLabel）'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('可选点位抽检抓拍'),
              children: [
                _InfoRow(
                  label: '抓拍点',
                  value:
                      '$verificationKeyPointCount 个验证点 ($_surfaceTrajectorySourceLabel)',
                ),
                Row(
                  children: [
                    Expanded(
                      child: _buildTrajectoryNumberInput(
                        label: '验证间距',
                        value: _verificationSpacingMm
                            .clamp(1.0, 100.0)
                            .toDouble(),
                        min: 1,
                        max: 100,
                        unit: 'mm',
                        enabled: !_verificationRunning,
                        onChanged: (value) =>
                            setState(() => _verificationSpacingMm = value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTrajectoryNumberInput(
                        label: '最大抓拍数',
                        value: _verificationMaxCaptures
                            .clamp(3, 200)
                            .toDouble(),
                        min: 3,
                        max: 200,
                        unit: '',
                        enabled: !_verificationRunning,
                        onChanged: (value) => setState(
                          () => _verificationMaxCaptures = value.round().clamp(
                            3,
                            200,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTrajectoryNumberInput(
                        label: '稳定等待',
                        value: _verificationSettleSeconds
                            .clamp(0.0, 5.0)
                            .toDouble(),
                        min: 0,
                        max: 5,
                        unit: 's',
                        enabled: !_verificationRunning,
                        onChanged: (value) =>
                            setState(() => _verificationSettleSeconds = value),
                      ),
                    ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: _verificationRunning || _surfaceTrajectory.isEmpty
                      ? null
                      : _runTrajectoryCaptureVerification,
                  icon: _verificationRunning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_enhance_outlined),
                  label: Text(
                    _verificationRunning
                        ? '抓拍中 $_verificationProgress/$verificationKeyPointCount'
                        : '移动抽检并识别照片轨迹',
                  ),
                ),
                if (_actualVerificationTrajectoryPoints().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => setState(
                      () => _showActualVerificationTrajectory =
                          !_showActualVerificationTrajectory,
                    ),
                    icon: Icon(
                      _showActualVerificationTrajectory
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    label: Text(
                      _showActualVerificationTrajectory
                          ? '隐藏照片识别轨迹'
                          : '显示照片识别轨迹',
                    ),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: '照片识别轨迹',
                    value:
                        '${_actualVerificationTrajectoryPoints().length} 个识别点',
                  ),
                ],
                if (_verificationResult != null &&
                    _actualVerificationTrajectoryPoints().isEmpty) ...[
                  const SizedBox(height: 8),
                  const _MessageBox(
                    message:
                        'Captured photos were saved, but this manifest has no detected actual points, so the green actual trajectory is not drawn.',
                  ),
                ],
              ],
            ),
          ],
          if (_surfaceTrajectoryPath != null) ...[
            const SizedBox(height: 8),
            _InfoRow(label: 'CSV', value: _surfaceTrajectoryPath!),
          ],
          if (_surfaceGcodePath != null) ...[
            const SizedBox(height: 8),
            _InfoRow(label: 'G-code', value: _surfaceGcodePath!),
          ],
          if (_verificationResultPath != null) ...[
            const SizedBox(height: 8),
            _InfoRow(label: '验证', value: _verificationResultPath!),
          ],
          if (_verificationResult != null) ...[
            const SizedBox(height: 10),
            _buildSurfaceVerificationMetricsPanel(),
            const SizedBox(height: 10),
            _MessageBox(
              message:
                  'Capture verification result saved. The green actual trajectory is drawn only when manifest contains actual/observed/detected coordinates.',
            ),
          ],
          if (_verificationError != null) ...[
            const SizedBox(height: 10),
            _MessageBox(message: _verificationError!, isError: true),
          ],
          if (_surfaceTrajectoryError != null) ...[
            const SizedBox(height: 10),
            _MessageBox(
              message: _surfaceTrajectoryError!,
              isError: _surfaceTrajectory.isEmpty,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLabeledSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String unit,
    required bool enabled,
    required ValueChanged<double> onChanged,
  }) {
    final display = unit.isEmpty ? _fmt(value) : '${_fmt(value)} $unit';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
                ),
              ),
              Text(
                display,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSurfaceVerificationMetricsPanel() {
    final detection = _jsonMap(_verificationResult?['detection']);
    final metrics = _jsonMap(detection?['metrics']);
    if (metrics == null) return const SizedBox.shrink();

    final corrected = _jsonMap(detection?['offset_corrected_metrics']);
    final sampleCount = _jsonInt(metrics['sample_count'], 0);
    final correctionOutput = _jsonString(
      detection?['surface_correction_output'],
    );
    final meanError = metrics['mean_error_mm'];
    final activeCorrection = _surfaceCommandCorrection;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '曲面验证误差',
              style: TextStyle(
                color: Colors.grey.shade100,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            _InfoRow(label: '样本', value: '$sampleCount 个点'),
            _InfoRow(
              label: '原始',
              value:
                  'XY RMS ${_metricMm(metrics, 'rms_xy_error_mm')} | '
                  'Z RMS ${_metricMm(metrics, 'rms_z_error_mm')} | '
                  'XYZ RMS ${_metricMm(metrics, 'rms_xyz_error_mm')} | '
                  'Max XY ${_metricMm(metrics, 'max_xy_error_mm')}',
            ),
            if (corrected != null)
              _InfoRow(
                label: '去均值',
                value:
                    'XY RMS ${_metricMm(corrected, 'rms_xy_error_mm')} | '
                    'Z RMS ${_metricMm(corrected, 'rms_z_error_mm')} | '
                    'XYZ RMS ${_metricMm(corrected, 'rms_xyz_error_mm')} | '
                    'Max XY ${_metricMm(corrected, 'max_xy_error_mm')}',
              ),
            _InfoRow(label: '均值误差', value: _formatMetricVector(meanError)),
            _InfoRow(
              label: '建议补偿',
              value: _formatMetricVector(meanError, negate: true),
            ),
            _InfoRow(
              label: '补偿状态',
              value: _applySurfaceCommandCorrection
                  ? '已启用 ${activeCorrection == null ? '' : _formatCorrection(activeCorrection)}'
                  : '未启用，仅显示诊断数据',
            ),
            if (correctionOutput != null)
              _InfoRow(label: '补偿JSON', value: correctionOutput),
            const SizedBox(height: 6),
            Text(
              '该补偿来自本次曲面验证轨迹的均值残差，只适用于相同装夹、相同图像配准和相近轨迹；全局坐标系拟合仍是基础标定。',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  String _metricMm(Map<String, dynamic> map, String key) {
    final value = _jsonDouble(map[key], double.nan);
    return value.isFinite ? '${_fmt(value)} mm' : '-';
  }

  String _formatMetricVector(Object? value, {bool negate = false}) {
    if (value is! List || value.length < 3) return '-';
    final x = _jsonDouble(value[0], double.nan);
    final y = _jsonDouble(value[1], double.nan);
    final z = _jsonDouble(value[2], double.nan);
    if (!x.isFinite || !y.isFinite || !z.isFinite) return '-';
    final sign = negate ? -1.0 : 1.0;
    return '(${_fmt(sign * x)}, ${_fmt(sign * y)}, ${_fmt(sign * z)}) mm';
  }

  String _formatCorrection(_SurfaceCommandCorrection correction) {
    final suffix = correction.hasZErrorModel ? ' + Z model' : '';
    return '(${_fmt(correction.dx)}, ${_fmt(correction.dy)}, ${_fmt(correction.dz)}) mm$suffix';
  }

  SurfaceBedZToolheadKind get _surfaceBedZToolheadKind =>
      _surfaceToolOrientation.mode.bedZToolheadKind;

  _SurfaceBedZCalibrationRecord? get _activeSurfaceBedZCalibration =>
      _surfaceBedZCalibrations[_surfaceBedZToolheadKind];

  String? get _surfaceBedZToolheadWarning {
    final active = _activeSurfaceBedZCalibration;
    if (_surfaceBedZToolheadKind == SurfaceBedZToolheadKind.dualServo) {
      if (active == null) {
        return '当前为双自由度舵机工具头，必须重新标定第一层 Z 基准；不能沿用单针头“仅 XYZ”标定。';
      }
      final xyzOnly = _surfaceBedZCalibrations[SurfaceBedZToolheadKind.xyzOnly];
      if (xyzOnly != null &&
          surfaceBedZNeedsRecalibration(
            xyzOnly.bedZ,
            active.bedZ,
            toleranceMm: _surfaceBedZSameToolheadToleranceMm,
          )) {
        return '双自由度舵机工具头的床面 Z 与单针头“仅 XYZ”标定相同（误差不超过 ${_fmt(_surfaceBedZSameToolheadToleranceMm)} mm）。请确认已安装舵机工具头并重新标定。';
      }
    }
    return null;
  }

  void _activateSurfaceBedZCalibrationForCurrentToolhead() {
    final calibration = _activeSurfaceBedZCalibration;
    _surfaceBedZ = calibration?.bedZ ?? _defaultSurfaceBedZ;
    _surfaceBedZCalibrationTouchZ = calibration?.touchZ;
    _surfaceBedZCalibrationAt = calibration?.calibratedAt;
  }

  Future<void> _recordSurfaceBedZFromCurrentPosition() async {
    if (_surfaceBedZCalibrationBusy) {
      return;
    }
    setState(() {
      _surfaceBedZCalibrationBusy = true;
      _surfaceBedZCalibrationError = null;
      _surfaceBedZCalibrationMessage = null;
    });

    try {
      final printer = context.read<PrinterController>();
      if (printer.repo == null) {
        throw StateError('Moonraker 未连接，无法读取当前机器 Z。');
      }
      await printer.refreshAllStatus();
      final position = printer.currentPosition;
      if (position == null || position.length < 3 || !position[2].isFinite) {
        throw StateError('没有读到有效的当前 Z 坐标，请先刷新打印机状态。');
      }
      await _applySurfaceBedZCalibrationFromTouch(
        touchZ: position[2],
        source: 'moonraker_current_position',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _surfaceBedZCalibrationError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _surfaceBedZCalibrationBusy = false;
        });
      }
    }
  }

  Future<void> _applySurfaceBedZCalibrationFromTouch({
    double? touchZ,
    String source = 'manual_recalculate',
  }) async {
    final measuredTouchZ = touchZ ?? _surfaceBedZCalibrationTouchZ;
    if (measuredTouchZ == null || !measuredTouchZ.isFinite) {
      setState(() {
        _surfaceBedZCalibrationError = '还没有可用的触碰机器 Z。';
      });
      return;
    }

    final calibratedBedZ = measuredTouchZ;
    if (!calibratedBedZ.isFinite) {
      setState(() {
        _surfaceBedZCalibrationError = '标定结果不是有效数值。';
      });
      return;
    }

    final calibratedAt = DateTime.now();
    final toolheadKind = _surfaceBedZToolheadKind;
    final calibration = _SurfaceBedZCalibrationRecord(
      touchZ: measuredTouchZ,
      bedZ: calibratedBedZ,
      calibratedAt: calibratedAt,
      source: source,
    );
    setState(() {
      _surfaceBedZCalibrations[toolheadKind] = calibration;
      _activateSurfaceBedZCalibrationForCurrentToolhead();
      _surfaceBedZCalibrationError = null;
      _surfaceBedZCalibrationMessage =
          '已应用 ${toolheadKind.label}：床面 Z = ${_fmt(calibratedBedZ)} mm';
      _clearGeneratedSurfaceTrajectory();
    });

    try {
      final path = await _writeSurfaceBedZCalibrationFile(
        activeToolheadKind: toolheadKind,
        calibration: calibration,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _surfaceBedZCalibrationPath = path;
        _surfaceBedZCalibrationMessage =
            '已应用并保存 ${toolheadKind.label}：床面 Z = ${_fmt(calibratedBedZ)} mm';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _surfaceBedZCalibrationError = '标定已应用，但保存失败：$error';
      });
    }
  }

  File _surfaceBedZCalibrationFile() {
    return File(
      [
        Directory.current.path,
        '02_visual',
        'surface_bed_z_calibration_latest.json',
      ].join(Platform.pathSeparator),
    );
  }

  Future<void> _loadSurfaceBedZCalibration() async {
    final file = _surfaceBedZCalibrationFile();
    if (!await file.exists()) {
      return;
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('标定文件格式不是 JSON 对象。');
      }

      final calibrations =
          <SurfaceBedZToolheadKind, _SurfaceBedZCalibrationRecord>{};
      final savedCalibrations = decoded['calibrations'];
      if (savedCalibrations is Map) {
        for (final toolheadKind in SurfaceBedZToolheadKind.values) {
          final calibration = _SurfaceBedZCalibrationRecord.fromJson(
            savedCalibrations[toolheadKind.storageKey],
          );
          if (calibration != null) {
            calibrations[toolheadKind] = calibration;
          }
        }
      }

      if (calibrations.isEmpty) {
        final legacyCalibration = _SurfaceBedZCalibrationRecord.fromJson(
          decoded,
        );
        if (legacyCalibration == null) {
          throw const FormatException('标定文件缺少有效的 bed_z_mm。');
        }
        calibrations[SurfaceBedZToolheadKind.xyzOnly] = legacyCalibration;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _surfaceBedZCalibrations
          ..clear()
          ..addAll(calibrations);
        _activateSurfaceBedZCalibrationForCurrentToolhead();
        _surfaceBedZCalibrationPath = file.path;
        _surfaceBedZCalibrationError = null;
        final active = _activeSurfaceBedZCalibration;
        _surfaceBedZCalibrationMessage = active == null
            ? '已加载单针头“仅 XYZ”标定；双自由度舵机工具头需要重新标定。'
            : '已加载 ${_surfaceBedZToolheadKind.label}：床面 Z = ${_fmt(active.bedZ)} mm';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _surfaceBedZCalibrationPath = file.path;
        _surfaceBedZCalibrationError =
            '读取保存的床面 Z 失败，已使用默认值 ${_fmt(_defaultSurfaceBedZ)} mm：$error';
      });
    }
  }

  Future<String> _writeSurfaceBedZCalibrationFile({
    required SurfaceBedZToolheadKind activeToolheadKind,
    required _SurfaceBedZCalibrationRecord calibration,
  }) async {
    final file = _surfaceBedZCalibrationFile();
    await file.parent.create(recursive: true);
    final calibrations =
        Map<SurfaceBedZToolheadKind, _SurfaceBedZCalibrationRecord>.from(
          _surfaceBedZCalibrations,
        )..[activeToolheadKind] = calibration;
    final payload = <String, Object?>{
      'type': 'surface_bed_z_first_layer_calibration',
      'version': 2,
      ...calibration.toJson(),
      'toolhead_kind': activeToolheadKind.storageKey,
      'formula': 'bed_z_mm = touch_machine_z_mm for model bed plane z=0',
      'calibrations': {
        for (final entry in calibrations.entries)
          entry.key.storageKey: entry.value.toJson(),
      },
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    return file.path;
  }

  Widget _buildSurfaceToolOrientationPanel({required bool ready}) {
    final config = _surfaceToolOrientation;
    final summary =
        _surfaceToolOrientationSummary ??
        (_surfaceTrajectory.isEmpty
            ? null
            : _summarizeSurfaceToolOrientation(_exportTrajectory));
    void update(SurfaceToolOrientationConfig next) {
      final toolheadChanged =
          next.mode.bedZToolheadKind !=
          _surfaceToolOrientation.mode.bedZToolheadKind;
      setState(() {
        _surfaceToolOrientation = next;
        if (toolheadChanged) {
          _activateSurfaceBedZCalibrationForCurrentToolhead();
          _surfaceBedZCalibrationError = null;
          _surfaceBedZCalibrationMessage = null;
        }
        if (_surfaceTrajectory.isNotEmpty) {
          _surfaceTrajectory = _attachSurfaceToolPoses(_surfaceTrajectory);
          _surfaceMotionTrajectory = const [];
          _surfaceToolOrientationSummary = _summarizeSurfaceToolOrientation(
            _surfaceTrajectory,
          );
        }
        _surfaceGcodePath = null;
      });
    }

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('工具姿态'),
      subtitle: Text(config.mode.label),
      children: [
        DropdownButtonFormField<SurfaceToolPoseMode>(
          initialValue: config.mode,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '姿态模式',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: SurfaceToolPoseMode.values
              .map(
                (mode) => DropdownMenuItem<SurfaceToolPoseMode>(
                  value: mode,
                  child: Text(mode.label, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(growable: false),
          onChanged: ready
              ? (mode) {
                  if (mode != null) update(config.copyWith(mode: mode));
                }
              : null,
        ),
        const SizedBox(height: 8),
        const _MessageBox(
          message:
              'Pitch：80° 工具水平，50° 上抬限位，180° 竖直向下；Yaw：30° 工具朝 +X（上臂 A）。姿态导出仅供审阅，勿在未校准舵机前执行。',
        ),
        if (config.mode == SurfaceToolPoseMode.fixed) ...[
          Row(
            children: [
              Expanded(
                child: _buildTrajectoryNumberInput(
                  label: '固定 Yaw',
                  value: config.fixedYawServoDeg,
                  min: 0,
                  max: 180,
                  unit: 'deg',
                  enabled: ready,
                  onChanged: (value) =>
                      update(config.copyWith(fixedYawServoDeg: value)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTrajectoryNumberInput(
                  label: '固定 Pitch',
                  value: config.fixedPitchServoDeg,
                  min: 50,
                  max: 180,
                  unit: 'deg',
                  enabled: ready,
                  onChanged: (value) =>
                      update(config.copyWith(fixedPitchServoDeg: value)),
                ),
              ),
            ],
          ),
        ],
        if (config.mode == SurfaceToolPoseMode.normalFollow) ...[
          Row(
            children: [
              Expanded(
                child: _buildTrajectoryNumberInput(
                  label: 'Yaw 偏置',
                  value: config.yawOffsetDeg,
                  min: -180,
                  max: 180,
                  unit: 'deg',
                  enabled: ready,
                  onChanged: (value) =>
                      update(config.copyWith(yawOffsetDeg: value)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTrajectoryNumberInput(
                  label: 'Pitch 偏置',
                  value: config.pitchOffsetDeg,
                  min: -90,
                  max: 90,
                  unit: 'deg',
                  enabled: ready,
                  onChanged: (value) =>
                      update(config.copyWith(pitchOffsetDeg: value)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildTrajectoryNumberInput(
                  label: 'L：俯仰轴至针尖',
                  value: config.tipLengthMm,
                  min: 0,
                  max: 100,
                  unit: 'mm',
                  enabled: ready,
                  onChanged: (value) =>
                      update(config.copyWith(tipLengthMm: value)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTrajectoryNumberInput(
                  label: 'e：针尖横向偏心',
                  value: config.tipLateralOffsetMm,
                  min: -30,
                  max: 30,
                  unit: 'mm',
                  enabled: ready,
                  onChanged: (value) =>
                      update(config.copyWith(tipLateralOffsetMm: value)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const _MessageBox(
            message:
                '针尖补偿零位：针尖竖直向下、Yaw 朝 +X（Yaw 30° / Pitch 180°）。双舵机床面 Z 标定须在该姿态完成；e 的正负用于选择俯仰摆动平面两侧。',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('反向 Yaw'),
            value: config.reverseYaw,
            onChanged: ready
                ? (value) => update(config.copyWith(reverseYaw: value))
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('反向 Pitch'),
            value: config.reversePitch,
            onChanged: ready
                ? (value) => update(config.copyWith(reversePitch: value))
                : null,
          ),
        ],
        if (config.mode != SurfaceToolPoseMode.xyzOnly) ...[
          Row(
            children: [
              Expanded(
                child: _buildTrajectoryNumberInput(
                  label: '姿态死区',
                  value: config.deadbandDeg,
                  min: 0,
                  max: 20,
                  unit: 'deg',
                  enabled: ready,
                  onChanged: (value) =>
                      update(config.copyWith(deadbandDeg: value)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTrajectoryNumberInput(
                  label: '最大变化',
                  value: config.maxStepDeg,
                  min: 1,
                  max: 90,
                  unit: 'deg',
                  enabled: ready,
                  onChanged: (value) =>
                      update(config.copyWith(maxStepDeg: value)),
                ),
              ),
            ],
          ),
          _buildTrajectoryNumberInput(
            label: '舵机稳定时间',
            value: config.settleMs.toDouble(),
            min: 0,
            max: 5000,
            unit: 'ms',
            enabled: ready,
            onChanged: (value) =>
                update(config.copyWith(settleMs: value.round())),
          ),
          if (summary != null) ...[
            _InfoRow(
              label: '姿态工作点',
              value:
                  '${summary.valid}/${summary.total} 有效；${summary.updates} 次调整',
            ),
            _InfoRow(
              label: 'Yaw 范围',
              value:
                  '${_fmt(summary.minYawServoDeg ?? 0)}° – ${_fmt(summary.maxYawServoDeg ?? 0)}°',
            ),
            _InfoRow(
              label: 'Pitch 范围',
              value:
                  '${_fmt(summary.minPitchServoDeg ?? 0)}° – ${_fmt(summary.maxPitchServoDeg ?? 0)}°',
            ),
            OutlinedButton.icon(
              onPressed: _showSurfaceToolPoseDiagnostics,
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('查看姿态计算'),
            ),
            if (!summary.canExport)
              _MessageBox(
                message: '姿态 G-code 已阻止导出：${summary.errors.join('；')}',
                isError: true,
              ),
          ],
        ],
      ],
    );
  }

  Widget _buildSurfaceBedZCalibrationPanel({required bool ready}) {
    final printer = context.watch<PrinterController>();
    final position = printer.currentPosition;
    final currentZ =
        position != null && position.length >= 3 && position[2].isFinite
        ? position[2]
        : null;
    final connected = printer.repo != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF151A20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.vertical_align_bottom_outlined,
                color: Colors.blueGrey.shade200,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '第一层 Z 基准标定',
                  style: TextStyle(
                    color: Colors.grey.shade100,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_surfaceBedZCalibrationBusy)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.blueGrey.shade100,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _InfoRow(
            label: '机器Z',
            value: currentZ == null ? '未读取' : '${_fmt(currentZ)} mm',
          ),
          _InfoRow(label: '工具头', value: _surfaceBedZToolheadKind.label),
          _InfoRow(
            label: '标定状态',
            value: _activeSurfaceBedZCalibration == null ? '未标定' : '已标定',
          ),
          _InfoRow(
            label: '触碰Z',
            value: _surfaceBedZCalibrationTouchZ == null
                ? '未记录'
                : '${_fmt(_surfaceBedZCalibrationTouchZ!)} mm',
          ),
          _InfoRow(label: '当前床Z', value: '${_fmt(_surfaceBedZ)} mm'),
          if (_surfaceBedZCalibrationAt != null)
            _InfoRow(
              label: '时间',
              value: _surfaceBedZCalibrationAt!.toLocal().toString(),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: ready && connected && !_surfaceBedZCalibrationBusy
                    ? () => unawaited(_recordSurfaceBedZFromCurrentPosition())
                    : null,
                icon: const Icon(Icons.my_location_outlined, size: 18),
                label: Text(_surfaceBedZCalibrationBusy ? '读取中' : '读取当前Z并应用'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '床面Z = 当前工具头的针尖刚好触碰床面时的机器Z。单针头“仅 XYZ”和双自由度舵机工具头必须分别标定；STL曲面高度仍由模型和视觉定位决定。',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
          if (_surfaceBedZToolheadWarning case final warning?) ...[
            const SizedBox(height: 8),
            _MessageBox(message: warning, isError: true),
          ],
          if (!connected) ...[
            const SizedBox(height: 8),
            _MessageBox(message: 'Moonraker 未连接，暂不能读取当前 Z。', isError: true),
          ],
          if (_surfaceBedZCalibrationMessage != null) ...[
            const SizedBox(height: 8),
            _MessageBox(message: _surfaceBedZCalibrationMessage!),
          ],
          if (_surfaceBedZCalibrationError != null) ...[
            const SizedBox(height: 8),
            _MessageBox(message: _surfaceBedZCalibrationError!, isError: true),
          ],
          if (_surfaceBedZCalibrationPath != null) ...[
            const SizedBox(height: 4),
            _InfoRow(label: '文件', value: _surfaceBedZCalibrationPath!),
          ],
        ],
      ),
    );
  }

  Widget _buildTrajectoryNumberInput({
    required String label,
    required double value,
    required double min,
    required double max,
    required String unit,
    required bool enabled,
    required ValueChanged<double> onChanged,
    bool integer = false,
  }) {
    return _TrajectoryNumberInput(
      label: label,
      value: value,
      min: min,
      max: max,
      unit: unit,
      enabled: enabled,
      integer: integer,
      onChanged: onChanged,
    );
  }

  Widget _buildNextStageCard(BuildContext context) {
    final ready = _mesh != null && !_mesh!.isEmpty;
    final hasPhoto = _workpiecePhotoBytes != null;
    final localized = _localizationResultPath != null;
    final trajectoryReady = _surfaceTrajectory.isNotEmpty;
    final motionReady = _surfaceMotionTrajectory.isNotEmpty;
    final gcodeReady = _surfaceGcodePath != null;
    final started = _surfaceOneClickStatus?.startsWith('已启动') ?? false;

    return FluiddCard(
      title: '后续流程',
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PipelineStep(
            index: 1,
            label: '加载 STL',
            state: ready ? '已完成' : '当前',
            active: true,
            done: ready,
          ),
          _PipelineStep(
            index: 2,
            label: '拍摄工件照片',
            state: hasPhoto ? '已完成' : '当前',
            active: ready,
            done: hasPhoto,
          ),
          _PipelineStep(
            index: 3,
            label: '人工/视觉辅助定位',
            state: localized ? '已完成' : '当前',
            active: ready && hasPhoto,
            done: localized,
          ),
          _PipelineStep(
            index: 4,
            label: '曲面恒距基础轨迹',
            state: trajectoryReady ? '已生成' : '当前',
            active: localized,
            done: trajectoryReady,
          ),
          _PipelineStep(
            index: 5,
            label: '平滑运动轨迹',
            state: motionReady
                ? '已生成'
                : trajectoryReady
                ? '当前'
                : '等待',
            active: trajectoryReady,
            done: motionReady,
          ),
          _PipelineStep(
            index: 6,
            label: '一键启动运动',
            state: started
                ? '已启动'
                : _surfaceOneClickStarting
                ? '启动中'
                : gcodeReady
                ? '已导出'
                : motionReady
                ? '当前'
                : '等待',
            active: motionReady,
            done: started,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: localized
                ? () => setState(() => _workspaceView = 3)
                : ready && hasPhoto
                ? () => setState(() => _workspaceView = 2)
                : null,
            icon: Icon(localized ? Icons.timeline : Icons.my_location),
            label: Text(localized ? '进入曲面运动流程' : '进入人工定位'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard(BuildContext context) {
    if (_workspaceView == 0) return _buildStlPreviewCard(context);
    if (_workspaceView == 1) return _buildPhotoPreviewCard(context);
    if (_workspaceView == 2) return _buildLocalizationPreviewCard(context);
    return _buildTrajectoryPreviewCard(context);
  }

  Widget _buildWorkspaceSwitcher() {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(
          value: 0,
          icon: Icon(Icons.view_in_ar),
          label: Text('STL'),
        ),
        ButtonSegment(value: 1, icon: Icon(Icons.photo), label: Text('照片')),
        ButtonSegment(
          value: 2,
          icon: Icon(Icons.my_location),
          label: Text('定位'),
        ),
        ButtonSegment(value: 3, icon: Icon(Icons.timeline), label: Text('轨迹')),
      ],
      selected: {_workspaceView},
      onSelectionChanged: (selection) {
        setState(() => _workspaceView = selection.first);
      },
    );
  }

  Widget _buildStlPreviewCard(BuildContext context) {
    final theme = Theme.of(context);
    final actions = [
      _buildWorkspaceSwitcher(),
      const SizedBox(width: 8),
      _PreviewModeButton(
        tooltip: '线框',
        icon: Icons.grid_4x4,
        selected: _previewMode == SurfacePreviewMode.wireframe,
        onPressed: () =>
            setState(() => _previewMode = SurfacePreviewMode.wireframe),
      ),
      _PreviewModeButton(
        tooltip: '实体',
        icon: Icons.view_in_ar,
        selected: _previewMode == SurfacePreviewMode.shaded,
        onPressed: () =>
            setState(() => _previewMode = SurfacePreviewMode.shaded),
      ),
      _PreviewModeButton(
        tooltip: '组合',
        icon: Icons.layers,
        selected: _previewMode == SurfacePreviewMode.combined,
        onPressed: () =>
            setState(() => _previewMode = SurfacePreviewMode.combined),
      ),
      const SizedBox(width: 6),
      _PreviewModeButton(
        tooltip: '包围框',
        icon: Icons.crop_free,
        selected: _showBounds,
        onPressed: () => setState(() => _showBounds = !_showBounds),
      ),
      _PreviewModeButton(
        tooltip: '坐标轴',
        icon: Icons.threed_rotation,
        selected: _showAxes,
        onPressed: () => setState(() => _showAxes = !_showAxes),
      ),
      PopupMenuButton<_PresetView>(
        tooltip: '预设视角',
        icon: const Icon(Icons.visibility),
        onSelected: _setView,
        itemBuilder: (context) => const [
          PopupMenuItem(value: _PresetView.iso, child: Text('等轴测')),
          PopupMenuItem(value: _PresetView.top, child: Text('俯视')),
          PopupMenuItem(value: _PresetView.front, child: Text('正视')),
          PopupMenuItem(value: _PresetView.side, child: Text('侧视')),
        ],
      ),
      IconButton(
        tooltip: '重置视角',
        onPressed: _mesh == null ? null : _resetView,
        icon: const Icon(Icons.refresh),
      ),
    ];

    return Card(
      color: const Color(0xFF2C3034),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        '曲面预览',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_meshName != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _meshName!,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Listener(
                      onPointerSignal: _onPointerSignal,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: _onScaleStart,
                        onScaleUpdate: _onScaleUpdate,
                        child: SurfacePreview(
                          mesh: _mesh,
                          mode: _previewMode,
                          showBounds: _showBounds,
                          showAxes: _showAxes,
                          rotationX: _rotationX,
                          rotationY: _rotationY,
                          rotationZ: _rotationZ,
                          zoom: _zoom,
                          pan: _pan,
                        ),
                      ),
                    ),
                  ),
                  if (_mesh == null)
                    Center(
                      child: FilledButton.icon(
                        onPressed: _loading ? null : _pickStl,
                        icon: const Icon(Icons.upload_file),
                        label: Text(_loading ? '加载中...' : '加载 STL'),
                      ),
                    ),
                  if (_mesh != null)
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: _PreviewStats(mesh: _mesh!, zoom: _zoom),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoPreviewCard(BuildContext context) {
    final theme = Theme.of(context);
    final camera = context.watch<CameraViewerController>();
    final capturedBytes = _workpiecePhotoBytes;
    final bytes = capturedBytes ?? camera.frameBytes;
    final showingLivePreview = capturedBytes == null;

    return Card(
      color: const Color(0xFF2C3034),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    showingLivePreview ? '相机预览' : '工件照片',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildWorkspaceSwitcher(),
                const SizedBox(width: 8),
                if (showingLivePreview) ...[
                  IconButton(
                    tooltip: camera.running ? 'Stop preview' : 'Start preview',
                    onPressed: camera.running ? camera.stop : camera.start,
                    icon: Icon(
                      camera.running
                          ? Icons.stop_circle_outlined
                          : Icons.play_circle_outline,
                      color: camera.running ? Colors.orangeAccent : Colors.blue,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh frame',
                    onPressed: camera.loading ? null : camera.refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Capture workpiece photo',
                    onPressed: !_platformClearedForPhoto || _capturingWorkpiece
                        ? null
                        : _captureWorkpiecePhoto,
                    icon: _capturingWorkpiece
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_camera_outlined),
                  ),
                ],
                IconButton(
                  tooltip: '缂╁皬',
                  onPressed: bytes == null ? null : () => _zoomPhoto(0.8),
                  icon: const Icon(Icons.zoom_out),
                ),
                IconButton(
                  tooltip: '鏀惧ぇ',
                  onPressed: bytes == null ? null : () => _zoomPhoto(1.25),
                  icon: const Icon(Icons.zoom_in),
                ),
                IconButton(
                  tooltip: '閲嶇疆瑙嗗浘',
                  onPressed: bytes == null ? null : _resetPhotoView,
                  icon: const Icon(Icons.center_focus_strong),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF101316),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white10),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (bytes == null)
                        _EmptyCameraPreview(
                          loading: camera.loading || _capturingWorkpiece,
                          error: camera.lastError,
                          platformCleared: _platformClearedForPhoto,
                          onStartPreview: camera.start,
                          onCapture: _platformClearedForPhoto
                              ? _captureWorkpiecePhoto
                              : null,
                        )
                      else
                        InteractiveViewer(
                          transformationController: _photoTransformController,
                          minScale: 0.25,
                          maxScale: 8,
                          boundaryMargin: const EdgeInsets.all(240),
                          child: Center(
                            child: Image.memory(
                              bytes,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                      if (showingLivePreview && bytes != null)
                        Positioned(
                          left: 12,
                          top: 12,
                          child: _PreviewBadge(
                            label: camera.running ? '实时预览' : '单帧预览',
                            color: camera.running
                                ? Colors.greenAccent
                                : Colors.blueAccent,
                          ),
                        ),
                      if (showingLivePreview && camera.loading)
                        const Center(
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalizationPreviewCard(BuildContext context) {
    final theme = Theme.of(context);
    final mesh = _mesh;
    final photoBytes = _workpiecePhotoBytes;
    final imageSize = _workpieceImageSize;
    final ready =
        mesh != null &&
        !mesh.isEmpty &&
        photoBytes != null &&
        imageSize != null;

    return Card(
      color: const Color(0xFF2C3034),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '人工辅助工件定位',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildWorkspaceSwitcher(),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '缩小视图',
                  onPressed: ready ? () => _zoomLocalizationView(0.8) : null,
                  icon: const Icon(Icons.zoom_out),
                ),
                IconButton(
                  tooltip: _interpolateGcodeZMapVertices
                      ? 'Height rendering: vertex gradient (cone)'
                      : 'Height rendering: face height (wing)',
                  onPressed: ready
                      ? () => setState(
                          () => _interpolateGcodeZMapVertices =
                              !_interpolateGcodeZMapVertices,
                        )
                      : null,
                  icon: Icon(
                    Icons.gradient,
                    color: _interpolateGcodeZMapVertices
                        ? const Color(0xFFFFD54F)
                        : Colors.grey.shade400,
                  ),
                ),
                IconButton(
                  tooltip: '放大视图',
                  onPressed: ready ? () => _zoomLocalizationView(1.25) : null,
                  icon: const Icon(Icons.zoom_in),
                ),
                IconButton(
                  tooltip: '重置视图',
                  onPressed: ready
                      ? () => _localizationTransformController.value =
                            Matrix4.identity()
                      : null,
                  icon: const Icon(Icons.center_focus_strong),
                ),
                IconButton(
                  tooltip: '保存定位结果',
                  onPressed: ready ? _saveLocalizationResult : null,
                  icon: const Icon(Icons.save_outlined),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF101316),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white10),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (!ready)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: _MessageBox(
                              message: '请先加载 STL，并拍摄一张工件照片，然后在这里进行人工定位。',
                            ),
                          ),
                        )
                      else
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final sceneSize = Size(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            );
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                InteractiveViewer(
                                  transformationController:
                                      _localizationTransformController,
                                  minScale: 0.35,
                                  maxScale: 8,
                                  boundaryMargin: const EdgeInsets.all(260),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.memory(
                                        photoBytes,
                                        fit: BoxFit.contain,
                                        gaplessPlayback: true,
                                      ),
                                      Positioned.fill(
                                        child: CustomPaint(
                                          painter: _StlTopProjectionPainter(
                                            mesh: mesh,
                                            imageSize: imageSize,
                                            contactFace: _contactFace,
                                            offsetPx: _localizationOffsetPx,
                                            yawDeg: _localizationYawDeg,
                                            scalePxPerMm:
                                                _localizationScalePxPerMm,
                                            opacity: _localizationOpacity,
                                            showHeightMap:
                                                _showLocalizationHeightMap,
                                            interpolateHeightVertices:
                                                _interpolateGcodeZMapVertices,
                                            showMesh: _showLocalizationMesh,
                                            showAxes: _showLocalizationAxes,
                                            showBounds: _showLocalizationBounds,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_showLocalizationHandles)
                                  Positioned.fill(
                                    child: _AlignmentHandlesLayer(
                                      mesh: mesh,
                                      imageSize: imageSize,
                                      sceneSize: sceneSize,
                                      transformController:
                                          _localizationTransformController,
                                      contactFace: _contactFace,
                                      offsetPx: _localizationOffsetPx,
                                      yawDeg: _localizationYawDeg,
                                      scalePxPerMm: _localizationScalePxPerMm,
                                      lockedHandle: _lockedAlignmentHandle,
                                      onDragHandle: _dragAlignmentHandle,
                                      onToggleLock: _toggleAlignmentHandleLock,
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      if (ready)
                        Positioned(
                          left: 12,
                          top: 12,
                          child: _PreviewBadge(
                            label:
                                '${_contactFace.label} | ${_projectionBasis.uAxis.label} 红色, ${_projectionBasis.vAxis.label} 绿色 | ${_fmt(_localizationYawDeg)} 度',
                            color: Colors.amberAccent,
                          ),
                        ),
                      if (_localizationResultPath != null)
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: _PreviewBadge(
                            label: '定位结果已保存',
                            color: const Color(0xFF45C486),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrajectoryPreviewCard(BuildContext context) {
    final theme = Theme.of(context);
    final printer = context.watch<PrinterController>();
    final mesh = _mesh;
    final ready = mesh != null && !mesh.isEmpty;
    final sourceReady = _surfaceTrajectorySourceReady;
    final canOneClickStart = _canOneClickStart(
      printer: printer,
      ready: ready,
      localized: _localizationResultPath != null,
      sourceReady: sourceReady,
    );
    final exportTrajectory = _exportTrajectory;
    final stats = _SurfaceTrajectoryStats.fromPoints(exportTrajectory);
    final trajectoryModeLabel = _surfaceMotionTrajectory.isNotEmpty
        ? '平滑轨迹'
        : '基础轨迹';
    final detectedVerificationPoints = _actualVerificationTrajectoryPoints();
    final plannedImageTrajectory = _plannedVerificationImagePoints();
    final generatedGcodeTrajectory = _showGcodeTrajectory
        ? _gcodeTrajectoryPoints()
        : const <_GcodeTrajectoryPoint>[];
    final showGcodeZMap = _showGcodeZMap && exportTrajectory.isNotEmpty;
    final guidePolylines = _currentSurfacePolylines(
      width: _surfacePatternWidthMm,
      height: _surfacePatternHeightMm,
    );
    final gcodeZMapTransform = showGcodeZMap
        ? _fitLocalToMachine(exportTrajectory)
        : null;
    final gcodeZMapCorrection = _applySurfaceCommandCorrection
        ? _surfaceCommandCorrection
        : null;
    final actualTrajectory = _showActualVerificationTrajectory
        ? detectedVerificationPoints
        : const <_ActualTrajectoryPoint>[];
    final photoBytes = _workpiecePhotoBytes;
    final imageSize = _workpieceImageSize;
    final photoReady = photoBytes != null && imageSize != null;
    final reachabilityOverlay = ready
        ? _reachabilityOverlayForPreview(mesh)
        : null;
    final reachabilityOverlayEnabled =
        ready &&
        _surfaceToolOrientation.mode == SurfaceToolPoseMode.normalFollow;
    final trajectoryLegendLabel = actualTrajectory.isNotEmpty
        ? photoReady
              ? '黄色：规划轨迹 | 绿色：照片识别像素轨迹'
              : '黄色：规划轨迹 | 绿色：照片识别坐标轨迹'
        : detectedVerificationPoints.isEmpty
        ? '黄色：规划轨迹；抽检照片暂无识别坐标'
        : '黄色：规划轨迹；可显示绿色照片识别轨迹';

    final gcodeBadgeTop = actualTrajectory.isNotEmpty ? 120.0 : 84.0;
    final zMapBadgeTop =
        gcodeBadgeTop + (generatedGcodeTrajectory.isNotEmpty ? 36.0 : 0.0);

    return Card(
      color: const Color(0xFF2C3034),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    '曲面恒距轨迹预览',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 16),
                  _buildWorkspaceSwitcher(),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '生成轨迹',
                    onPressed: ready && sourceReady
                        ? _generateSurfaceTrajectory
                        : null,
                    icon: const Icon(Icons.route_outlined),
                  ),
                  IconButton(
                    tooltip: '导出 CSV',
                    onPressed: _surfaceTrajectory.isEmpty
                        ? null
                        : _exportSurfaceTrajectoryCsv,
                    icon: const Icon(Icons.table_chart_outlined),
                  ),
                  IconButton(
                    tooltip: '导出 G-code',
                    onPressed: _surfaceTrajectory.isEmpty
                        ? null
                        : _exportSurfaceTrajectoryGcode,
                    icon: const Icon(Icons.data_object),
                  ),
                  IconButton(
                    tooltip: '一键启动平滑运动',
                    onPressed: canOneClickStart
                        ? _startSurfaceMotionOneClick
                        : null,
                    icon: _surfaceOneClickStarting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                  ),
                  IconButton(
                    tooltip: '查询下位机归零状态',
                    onPressed: _surfaceHomingStatusRefreshing
                        ? null
                        : _refreshSurfaceHomingStatus,
                    icon: _surfaceHomingStatusRefreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: _showGcodeTrajectory
                        ? '隐藏 G-code 轨迹'
                        : '显示 G-code 轨迹',
                    onPressed: _surfaceTrajectory.isEmpty
                        ? null
                        : () => setState(
                            () => _showGcodeTrajectory = !_showGcodeTrajectory,
                          ),
                    icon: Icon(
                      Icons.code,
                      color: generatedGcodeTrajectory.isNotEmpty
                          ? const Color(0xFF26C6DA)
                          : null,
                    ),
                  ),
                  IconButton(
                    tooltip: _showGcodeZMap
                        ? '隐藏 G-code Z 云图'
                        : '显示 G-code Z 云图',
                    onPressed: _surfaceTrajectory.isEmpty
                        ? null
                        : () =>
                              setState(() => _showGcodeZMap = !_showGcodeZMap),
                    icon: Icon(
                      Icons.terrain_outlined,
                      color: showGcodeZMap ? const Color(0xFFFFD54F) : null,
                    ),
                  ),
                  IconButton(
                    tooltip: _showActualVerificationTrajectory
                        ? '隐藏照片识别轨迹'
                        : '显示照片识别轨迹',
                    onPressed: detectedVerificationPoints.isEmpty
                        ? null
                        : () => setState(
                            () => _showActualVerificationTrajectory =
                                !_showActualVerificationTrajectory,
                          ),
                    icon: Icon(
                      _showActualVerificationTrajectory
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: actualTrajectory.isNotEmpty
                          ? const Color(0xFF45C486)
                          : null,
                    ),
                  ),
                  IconButton(
                    tooltip: _showToolReachabilityOverlay
                        ? '隐藏工具姿态可达区域'
                        : '显示工具姿态可达区域',
                    onPressed: !reachabilityOverlayEnabled
                        ? null
                        : () => setState(
                            () => _showToolReachabilityOverlay =
                                !_showToolReachabilityOverlay,
                          ),
                    icon: Icon(
                      Icons.layers_outlined,
                      color: _showToolReachabilityOverlay
                          ? const Color(0xFF66BB6A)
                          : null,
                    ),
                  ),
                  IconButton(
                    tooltip: '缩小视图',
                    onPressed: photoReady
                        ? () => _zoomTrajectoryView(0.8)
                        : null,
                    icon: const Icon(Icons.zoom_out),
                  ),
                  IconButton(
                    tooltip: _interpolateGcodeZMapVertices
                        ? 'Height rendering: vertex gradient (cone)'
                        : 'Height rendering: face height (wing)',
                    onPressed: _surfaceTrajectory.isEmpty
                        ? null
                        : () => setState(
                            () => _interpolateGcodeZMapVertices =
                                !_interpolateGcodeZMapVertices,
                          ),
                    icon: Icon(
                      Icons.gradient,
                      color: _interpolateGcodeZMapVertices
                          ? const Color(0xFFFFD54F)
                          : Colors.grey.shade400,
                    ),
                  ),
                  IconButton(
                    tooltip: '放大视图',
                    onPressed: photoReady
                        ? () => _zoomTrajectoryView(1.25)
                        : null,
                    icon: const Icon(Icons.zoom_in),
                  ),
                  IconButton(
                    tooltip: '重置视图',
                    onPressed: photoReady
                        ? () => _trajectoryController.value = Matrix4.identity()
                        : null,
                    icon: const Icon(Icons.center_focus_strong),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF101316),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white10),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (!ready)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: _MessageBox(message: '请先加载 STL 模型。'),
                        ),
                      )
                    else if (photoReady)
                      _buildTrajectoryPhotoOverlay(
                        mesh: mesh,
                        photoBytes: photoBytes,
                        imageSize: imageSize,
                        actualTrajectory: actualTrajectory,
                        plannedImageTrajectory: plannedImageTrajectory,
                        gcodeTrajectory: generatedGcodeTrajectory,
                        showGcodeZMap: showGcodeZMap,
                        interpolateGcodeZMapVertices:
                            _interpolateGcodeZMapVertices,
                        gcodeZMapCorrection: gcodeZMapCorrection,
                        gcodeZMapTransform: gcodeZMapTransform,
                        guidePolylines: guidePolylines,
                        reachabilityOverlay: reachabilityOverlay,
                      )
                    else
                      CustomPaint(
                        painter: _SurfaceTrajectoryPainter(
                          mesh: mesh,
                          contactFace: _contactFace,
                          trajectory: _surfaceTrajectory,
                          gcodeTrajectory: generatedGcodeTrajectory,
                          actualTrajectory: actualTrajectory,
                          showGcodeZMap: showGcodeZMap,
                          interpolateGcodeZMapVertices:
                              _interpolateGcodeZMapVertices,
                          bedZ: _surfaceBedZ,
                          clearanceMm: _surfaceClearanceMm,
                          gcodeZMapCorrection: gcodeZMapCorrection,
                          gcodeZMapTransform: gcodeZMapTransform,
                          patternWidth: _surfacePatternWidthMm,
                          patternHeight: _surfacePatternHeightMm,
                          patternCenterLocal: _surfacePatternCenterLocal,
                          patternRotationDeg: _surfacePatternRotationDeg,
                          guidePolylines: guidePolylines,
                          reachabilityOverlay: reachabilityOverlay,
                        ),
                      ),
                    if (ready && _surfaceTrajectory.isEmpty)
                      Center(
                        child: FilledButton.icon(
                          onPressed: sourceReady
                              ? _generateSurfaceTrajectory
                              : null,
                          icon: const Icon(Icons.route_outlined),
                          label: const Text('生成恒距基础轨迹'),
                        ),
                      ),
                    if (_surfaceTrajectory.isNotEmpty)
                      Positioned(
                        left: 12,
                        top: 12,
                        child: _PreviewBadge(
                          label:
                              '$trajectoryModeLabel ${exportTrajectory.length} points | Z ${_fmt(stats.minZ)}..${_fmt(stats.maxZ)} mm | clearance ${_fmt(_surfaceClearanceMm)} mm',
                          color: const Color(0xFF45C486),
                        ),
                      ),
                    if (ready && photoReady)
                      Positioned(
                        right: 12,
                        top: 12,
                        child: _PreviewBadge(
                          label:
                              '拖动黄色预设图案 | 中心 (${_fmt(_surfacePatternCenterLocal.dx)}, ${_fmt(_surfacePatternCenterLocal.dy)}) mm',
                          color: Colors.lightBlueAccent,
                        ),
                      ),
                    if (_surfaceTrajectory.isNotEmpty)
                      Positioned(
                        left: 12,
                        top: 48,
                        child: _PreviewBadge(
                          label: trajectoryLegendLabel,
                          color: Colors.amberAccent,
                        ),
                      ),
                    if (actualTrajectory.isNotEmpty)
                      Positioned(
                        left: 12,
                        top: 84,
                        child: _PreviewBadge(
                          label: '照片识别轨迹 ${actualTrajectory.length} 个点',
                          color: const Color(0xFF45C486),
                        ),
                      ),
                    if (generatedGcodeTrajectory.isNotEmpty)
                      Positioned(
                        left: 12,
                        top: gcodeBadgeTop,
                        child: _PreviewBadge(
                          label:
                              'G-code 轨迹 ${generatedGcodeTrajectory.length} 个点',
                          color: const Color(0xFF26C6DA),
                        ),
                      ),
                    if (showGcodeZMap)
                      Positioned(
                        left: 12,
                        top: zMapBadgeTop,
                        child: const _PreviewBadge(
                          label: 'G-code Z 云图：整 STL 区域',
                          color: Color(0xFFFFD54F),
                        ),
                      ),
                    if (reachabilityOverlay != null)
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: const _PreviewBadge(
                          label: '姿态可达区：绿=可达，橙=超限，灰=Yaw 奇异',
                          color: Color(0xFF66BB6A),
                        ),
                      ),
                    if (_surfaceTrajectoryError != null)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: _MessageBox(
                            message: _surfaceTrajectoryError!,
                            isError: _surfaceTrajectory.isEmpty,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrajectoryPhotoOverlay({
    required StlMesh mesh,
    required Uint8List photoBytes,
    required Size imageSize,
    required List<_ActualTrajectoryPoint> actualTrajectory,
    required List<_PlannedImageTrajectoryPoint> plannedImageTrajectory,
    required List<_GcodeTrajectoryPoint> gcodeTrajectory,
    required bool showGcodeZMap,
    required bool interpolateGcodeZMapVertices,
    required _SurfaceCommandCorrection? gcodeZMapCorrection,
    required _LocalToMachineTransform? gcodeZMapTransform,
    required List<List<Offset>> guidePolylines,
    required _SurfaceReachabilityOverlay? reachabilityOverlay,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sceneSize = Size(constraints.maxWidth, constraints.maxHeight);
        return InteractiveViewer(
          transformationController: _trajectoryController,
          minScale: 0.35,
          maxScale: 8,
          panEnabled: false,
          boundaryMargin: const EdgeInsets.all(260),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) {
              _moveSurfacePatternBySceneDelta(
                sceneDelta: details.delta,
                sceneSize: sceneSize,
                imageSize: imageSize,
              );
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  photoBytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _StlTopProjectionPainter(
                      mesh: mesh,
                      imageSize: imageSize,
                      contactFace: _contactFace,
                      offsetPx: _localizationOffsetPx,
                      yawDeg: _localizationYawDeg,
                      scalePxPerMm: _localizationScalePxPerMm,
                      opacity: 0.38,
                      showHeightMap: _showLocalizationHeightMap,
                      interpolateHeightVertices: interpolateGcodeZMapVertices,
                      showMesh: _showLocalizationMesh,
                      showAxes: _showLocalizationAxes,
                      showBounds: _showLocalizationBounds,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SurfaceTrajectoryPhotoPainter(
                      mesh: mesh,
                      imageSize: imageSize,
                      contactFace: _contactFace,
                      offsetPx: _localizationOffsetPx,
                      yawDeg: _localizationYawDeg,
                      scalePxPerMm: _localizationScalePxPerMm,
                      trajectory: _surfaceTrajectory,
                      gcodeTrajectory: gcodeTrajectory,
                      actualTrajectory: actualTrajectory,
                      plannedImageTrajectory: plannedImageTrajectory,
                      showGcodeZMap: showGcodeZMap,
                      interpolateGcodeZMapVertices:
                          interpolateGcodeZMapVertices,
                      bedZ: _surfaceBedZ,
                      clearanceMm: _surfaceClearanceMm,
                      gcodeZMapCorrection: gcodeZMapCorrection,
                      gcodeZMapTransform: gcodeZMapTransform,
                      patternWidth: _surfacePatternWidthMm,
                      patternHeight: _surfacePatternHeightMm,
                      patternCenterLocal: _surfacePatternCenterLocal,
                      patternRotationDeg: _surfacePatternRotationDeg,
                      guidePolylines: guidePolylines,
                      reachabilityOverlay: reachabilityOverlay,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatVector(StlVector3 value) {
    return '(${_fmt(value.x)}, ${_fmt(value.y)}, ${_fmt(value.z)})';
  }

  String _formatTime(DateTime? value) {
    if (value == null) return '-';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  String _fmt(double value) {
    if (!value.isFinite) return '-';
    final absValue = value.abs();
    if (absValue >= 1000) return value.toStringAsFixed(0);
    if (absValue >= 100) return value.toStringAsFixed(1);
    return value.toStringAsFixed(2);
  }

  String _formatInt(int value) {
    final text = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final remaining = text.length - i;
      buffer.write(text[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(label, style: TextStyle(color: Colors.grey.shade500)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(color: Colors.grey.shade200),
            ),
          ),
        ],
      ),
    );
  }
}

enum _SurfaceFileImportKind {
  auto,
  localization,
  trajectory,
  dxf,
  verification,
  correction,
}

enum _SurfaceTrajectorySource {
  pattern('基础图案', Icons.gesture),
  dxf('DXF文件', Icons.polyline_outlined);

  final String label;
  final IconData icon;

  const _SurfaceTrajectorySource(this.label, this.icon);
}

class _SurfaceFileLocation {
  final String label;
  final String path;
  final _SurfaceFileImportKind importKind;
  final bool recursive;
  final Set<String>? extensions;
  final Set<String>? namePrefixes;

  const _SurfaceFileLocation({
    required this.label,
    required this.path,
    required this.importKind,
    this.recursive = false,
    this.extensions,
    this.namePrefixes,
  });
}

class _SurfaceFileGroup {
  final _SurfaceFileLocation location;
  final List<_SurfaceManagedFile> items;

  const _SurfaceFileGroup({required this.location, required this.items});
}

class _SurfaceManagedFile {
  final String name;
  final String path;
  final String relativePath;
  final bool isDirectory;
  final int sizeBytes;
  final DateTime modified;
  final _SurfaceFileImportKind importKind;

  const _SurfaceManagedFile({
    required this.name,
    required this.path,
    required this.relativePath,
    required this.isDirectory,
    required this.sizeBytes,
    required this.modified,
    required this.importKind,
  });
}

class _TrajectoryNumberInput extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String unit;
  final bool enabled;
  final bool integer;
  final ValueChanged<double> onChanged;

  const _TrajectoryNumberInput({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.enabled,
    required this.integer,
    required this.onChanged,
  });

  @override
  State<_TrajectoryNumberInput> createState() => _TrajectoryNumberInputState();
}

class _TrajectoryNumberInputState extends State<_TrajectoryNumberInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _TrajectoryNumberInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        (oldWidget.value != widget.value ||
            oldWidget.integer != widget.integer)) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) _commit();
  }

  String _format(double value) {
    if (widget.integer) return value.round().toString();
    final text = value.toStringAsFixed(3);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  void _commit() {
    final raw = _controller.text.trim();
    final parsed = double.tryParse(raw);
    if (parsed == null) {
      _controller.text = _format(widget.value);
      return;
    }

    final clamped = parsed.clamp(widget.min, widget.max).toDouble();
    final next = widget.integer ? clamped.roundToDouble() : clamped;
    _controller.text = _format(next);
    if ((next - widget.value).abs() > 1e-9) {
      widget.onChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final suffix = widget.unit.isEmpty ? null : Text(widget.unit);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _commit(),
        decoration: InputDecoration(
          labelText: widget.label,
          suffix: suffix,
          helperText: '${_format(widget.min)}..${_format(widget.max)}',
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final String label;
  final String value;
  final bool ok;

  const _StatusLine({
    required this.label,
    required this.value,
    required this.ok,
  });

  @override
  Widget build(BuildContext context) {
    final color = ok ? const Color(0xFF45C486) : Colors.grey.shade500;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: TextStyle(color: Colors.grey.shade200)),
          ),
          Text(value, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}

class _BoundsTable extends StatelessWidget {
  final StlBounds bounds;

  const _BoundsTable({required this.bounds});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            _BoundsRow(axis: 'X', min: bounds.minX, max: bounds.maxX),
            _BoundsRow(axis: 'Y', min: bounds.minY, max: bounds.maxY),
            _BoundsRow(axis: 'Z', min: bounds.minZ, max: bounds.maxZ),
          ],
        ),
      ),
    );
  }
}

class _BoundsRow extends StatelessWidget {
  final String axis;
  final double min;
  final double max;

  const _BoundsRow({required this.axis, required this.min, required this.max});

  @override
  Widget build(BuildContext context) {
    String fmt(double value) => value.toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(axis, style: TextStyle(color: Colors.grey.shade400)),
          ),
          Expanded(
            child: Text(
              '${fmt(min)} .. ${fmt(max)} mm',
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.grey.shade200),
            ),
          ),
        ],
      ),
    );
  }
}

class _PipelineStep extends StatelessWidget {
  final int index;
  final String label;
  final String state;
  final bool active;
  final bool done;

  const _PipelineStep({
    required this.index,
    required this.label,
    required this.state,
    required this.active,
    this.done = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = done
        ? const Color(0xFF45C486)
        : active
        ? Colors.blue
        : Colors.grey.shade600;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              border: Border.all(color: color),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: TextStyle(color: Colors.grey.shade200)),
          ),
          Text(state, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _MessageBox extends StatelessWidget {
  final String message;
  final bool isError;

  const _MessageBox({required this.message, this.isError = false});

  @override
  Widget build(BuildContext context) {
    final color = isError ? Colors.redAccent : Colors.blueAccent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          message,
          style: TextStyle(color: isError ? Colors.red.shade100 : Colors.white),
        ),
      ),
    );
  }
}

class _EmptyCameraPreview extends StatelessWidget {
  final bool loading;
  final String? error;
  final bool platformCleared;
  final VoidCallback onStartPreview;
  final VoidCallback? onCapture;

  const _EmptyCameraPreview({
    required this.loading,
    required this.error,
    required this.platformCleared,
    required this.onStartPreview,
    required this.onCapture,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            error == null ? Icons.videocam_outlined : Icons.videocam_off,
            color: Colors.white24,
            size: 58,
          ),
          const SizedBox(height: 14),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
            )
          else
            Text(
              loading ? '等待相机画面' : '尚未获取相机画面',
              style: TextStyle(color: Colors.grey.shade400),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: loading ? null : onStartPreview,
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Start preview'),
              ),
              FilledButton.icon(
                onPressed: loading || !platformCleared ? null : onCapture,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Capture photo'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _PreviewBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(label, style: TextStyle(color: color, fontSize: 12)),
      ),
    );
  }
}

({double min, double max})? _actualTrajectoryHeightRange(
  List<_ActualTrajectoryPoint> points, [
  ({double min, double max})? preferredRange,
]) {
  if (preferredRange != null &&
      preferredRange.min.isFinite &&
      preferredRange.max.isFinite &&
      (preferredRange.max - preferredRange.min).abs() >= 1e-6) {
    return preferredRange;
  }
  final heights = points
      .map((point) => point.height)
      .whereType<double>()
      .where((height) => height.isFinite)
      .toList(growable: false);
  if (heights.isEmpty) return null;
  var minHeight = heights.first;
  var maxHeight = heights.first;
  for (final height in heights.skip(1)) {
    minHeight = math.min(minHeight, height);
    maxHeight = math.max(maxHeight, height);
  }
  if ((maxHeight - minHeight).abs() < 1e-6) return null;
  return (min: minHeight, max: maxHeight);
}

({double min, double max})? _gcodeTrajectoryHeightRange(
  List<_GcodeTrajectoryPoint> points, [
  ({double min, double max})? preferredRange,
]) {
  if (preferredRange != null &&
      preferredRange.min.isFinite &&
      preferredRange.max.isFinite &&
      (preferredRange.max - preferredRange.min).abs() >= 1e-6) {
    return preferredRange;
  }
  final heights = points
      .map((point) => point.height)
      .where((height) => height.isFinite)
      .toList(growable: false);
  if (heights.isEmpty) return null;
  var minHeight = heights.first;
  var maxHeight = heights.first;
  for (final height in heights.skip(1)) {
    minHeight = math.min(minHeight, height);
    maxHeight = math.max(maxHeight, height);
  }
  if ((maxHeight - minHeight).abs() < 1e-6) return null;
  return (min: minHeight, max: maxHeight);
}

({double min, double max})? _surfaceTrajectoryHeightRange(
  List<_SurfaceToolPoint> points,
) {
  final heights = points
      .map((point) => point.surfaceHeight)
      .where((height) => height.isFinite)
      .toList(growable: false);
  if (heights.isEmpty) return null;
  var minHeight = heights.first;
  var maxHeight = heights.first;
  for (final height in heights.skip(1)) {
    minHeight = math.min(minHeight, height);
    maxHeight = math.max(maxHeight, height);
  }
  if ((maxHeight - minHeight).abs() < 1e-6) return null;
  return (min: minHeight, max: maxHeight);
}

Color _trajectoryHeightColor(double t) {
  final stops = <({double stop, Color color})>[
    (stop: 0.0, color: const Color(0xFF1E88E5)),
    (stop: 0.34, color: const Color(0xFF00ACC1)),
    (stop: 0.62, color: const Color(0xFFFFD54F)),
    (stop: 1.0, color: const Color(0xFFE53935)),
  ];
  final clamped = t.clamp(0.0, 1.0);
  for (var i = 1; i < stops.length; i++) {
    final previous = stops[i - 1];
    final current = stops[i];
    if (clamped <= current.stop) {
      final localT =
          ((clamped - previous.stop) / (current.stop - previous.stop)).clamp(
            0.0,
            1.0,
          );
      return Color.lerp(previous.color, current.color, localT)!;
    }
  }
  return stops.last.color;
}

bool _isVisibleHeightTriangle(
  StlMesh mesh,
  _ProjectionBasis basis,
  StlTriangle triangle,
) {
  final radial = triangle.center - mesh.bounds.center;
  final outwardNormal = triangle.normal.dot(radial) < 0
      ? triangle.normal * -1
      : triangle.normal;
  return basis.heightValue(outwardNormal) > 1e-5;
}

Color _actualPointColor(
  _ActualTrajectoryPoint point,
  ({double min, double max})? range,
) {
  final height = point.height;
  if (height == null || range == null) return const Color(0xFF45C486);
  final t = (height - range.min) / (range.max - range.min);
  return _trajectoryHeightColor(t);
}

Color _gcodePointColor(
  _GcodeTrajectoryPoint point,
  ({double min, double max})? range,
) {
  if (range == null) return const Color(0xFF26C6DA);
  final t = (point.height - range.min) / (range.max - range.min);
  return _trajectoryHeightColor(t);
}

Color _actualSegmentColor(
  _ActualTrajectoryPoint previous,
  _ActualTrajectoryPoint current,
  ({double min, double max})? range,
) {
  if (range == null) return const Color(0xFF45C486);
  final previousHeight = previous.height;
  final currentHeight = current.height;
  if (previousHeight == null && currentHeight == null) {
    return const Color(0xFF45C486);
  }
  final height = previousHeight == null
      ? currentHeight!
      : currentHeight == null
      ? previousHeight
      : (previousHeight + currentHeight) / 2;
  final t = (height - range.min) / (range.max - range.min);
  return _trajectoryHeightColor(t);
}

void _drawActualTrajectoryHeightScale(
  Canvas canvas,
  Rect bounds,
  List<_ActualTrajectoryPoint> points, [
  ({double min, double max})? preferredRange,
]) {
  final range = _actualTrajectoryHeightRange(points, preferredRange);
  if (range == null) return;

  const barWidth = 16.0;
  const barHeight = 96.0;
  const padding = 12.0;
  const panelWidth = 124.0;
  const panelHeight = 128.0;
  final left = (bounds.right - padding - panelWidth).clamp(
    bounds.left + padding,
    bounds.right - panelWidth,
  );
  final top = (bounds.bottom - padding - panelHeight).clamp(
    bounds.top + padding,
    bounds.bottom - panelHeight,
  );
  final panelRect = Rect.fromLTWH(left, top, panelWidth, panelHeight);
  final barRect = Rect.fromLTWH(left + 10, top + 22, barWidth, barHeight);

  canvas.drawRRect(
    BorderRadius.circular(4).toRRect(panelRect),
    Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.black.withValues(alpha: 0.60),
  );
  canvas.drawRRect(
    BorderRadius.circular(4).toRRect(panelRect),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.22),
  );

  final gradient = ui.Gradient.linear(
    barRect.bottomLeft,
    barRect.topLeft,
    [
      _trajectoryHeightColor(0),
      _trajectoryHeightColor(0.34),
      _trajectoryHeightColor(0.62),
      _trajectoryHeightColor(1),
    ],
    const [0.0, 0.34, 0.62, 1.0],
  );
  canvas.drawRRect(
    BorderRadius.circular(3).toRRect(barRect),
    Paint()..shader = gradient,
  );
  canvas.drawRRect(
    BorderRadius.circular(3).toRRect(barRect),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.45),
  );

  final tickPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.78)
    ..strokeWidth = 1;
  for (final t in const [0.0, 0.5, 1.0]) {
    final y = barRect.bottom - barRect.height * t;
    canvas.drawLine(
      Offset(barRect.right, y),
      Offset(barRect.right + 5, y),
      tickPaint,
    );
  }

  _drawOverlayText(
    canvas,
    'Surface Z',
    Offset(left + 10, top + 4),
    Colors.white.withValues(alpha: 0.94),
    fontWeight: FontWeight.w700,
  );
  _drawOverlayText(
    canvas,
    '${range.max.toStringAsFixed(1)} mm',
    Offset(barRect.right + 8, barRect.top - 7),
    Colors.white,
  );
  _drawOverlayText(
    canvas,
    '${((range.min + range.max) / 2).toStringAsFixed(1)} mm',
    Offset(barRect.right + 8, barRect.center.dy - 7),
    Colors.white.withValues(alpha: 0.88),
  );
  _drawOverlayText(
    canvas,
    '${range.min.toStringAsFixed(1)} mm',
    Offset(barRect.right + 8, barRect.bottom - 12),
    Colors.white,
  );
}

void _drawOverlayText(
  Canvas canvas,
  String text,
  Offset offset,
  Color color, {
  FontWeight fontWeight = FontWeight.w500,
}) {
  final textPainter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: fontWeight),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  textPainter.paint(canvas, offset);
}

void _drawGcodeZMapProjection({
  required Canvas canvas,
  required StlMesh mesh,
  required _ProjectionBasis basis,
  required Offset Function(Offset localMm) localToCanvas,
  required Rect legendBounds,
  required double bedZ,
  required double clearanceMm,
  required _SurfaceCommandCorrection? correction,
  required _LocalToMachineTransform? transform,
  required bool interpolateVertices,
  double opacity = 0.52,
}) {
  final bounds = mesh.bounds;
  final centerUv = basis.project(bounds.center);
  final minHeight = basis.minHeight(bounds);
  final triangles = mesh.sampledTriangles(5200);
  if (triangles.isEmpty) return;

  final cells = <StlTriangle>[];
  var minZ = double.infinity;
  var maxZ = -double.infinity;

  double commandZFor(StlVector3 point) {
    final projected = basis.project(point);
    final local = Offset(
      projected.dx - centerUv.dx,
      projected.dy - centerUv.dy,
    );
    final surfaceHeight = basis.heightValue(point) - minHeight;
    final targetZ = bedZ + clearanceMm + surfaceHeight;
    final activeCorrection = correction;
    if (activeCorrection == null) return targetZ;
    final localToMachine = transform;
    if (localToMachine == null) {
      return activeCorrection.hasZErrorModel
          ? targetZ
          : targetZ + activeCorrection.dz;
    }
    final machine = localToMachine.machineFromLocal(local.dx, local.dy);
    return activeCorrection.correctedZ(
      x: machine.dx,
      y: machine.dy,
      z: targetZ,
    );
  }

  for (final triangle in triangles) {
    if (interpolateVertices &&
        !_isVisibleHeightTriangle(mesh, basis, triangle)) {
      continue;
    }
    final zValues = interpolateVertices
        ? [
            commandZFor(triangle.a),
            commandZFor(triangle.b),
            commandZFor(triangle.c),
          ]
        : [commandZFor(triangle.center)];
    if (zValues.any((z) => !z.isFinite)) continue;
    cells.add(triangle);
    for (final z in zValues) {
      minZ = math.min(minZ, z);
      maxZ = math.max(maxZ, z);
    }
  }
  if (cells.isEmpty || !minZ.isFinite || !maxZ.isFinite) return;

  Offset vertexToCanvas(StlVector3 point) {
    final projected = basis.project(point);
    return localToCanvas(
      Offset(projected.dx - centerUv.dx, projected.dy - centerUv.dy),
    );
  }

  final range = math.max(maxZ - minZ, 1e-6);
  final paint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = false;
  for (final triangle in cells) {
    final a = vertexToCanvas(triangle.a);
    final b = vertexToCanvas(triangle.b);
    final c = vertexToCanvas(triangle.c);
    final colors = interpolateVertices
        ? [triangle.a, triangle.b, triangle.c]
              .map(
                (point) => _trajectoryHeightColor(
                  (commandZFor(point) - minZ) / range,
                ).withValues(alpha: opacity),
              )
              .toList(growable: false)
        : List<Color>.filled(
            3,
            _trajectoryHeightColor(
              (commandZFor(triangle.center) - minZ) / range,
            ).withValues(alpha: opacity),
          );
    canvas.drawVertices(
      ui.Vertices(ui.VertexMode.triangles, [a, b, c], colors: colors),
      BlendMode.srcOver,
      paint,
    );
  }

  _drawGcodeZMapScale(canvas, legendBounds, (min: minZ, max: maxZ));
}

void _drawGcodeZMapScale(
  Canvas canvas,
  Rect bounds,
  ({double min, double max}) range,
) {
  const barWidth = 16.0;
  const barHeight = 96.0;
  const padding = 12.0;
  const panelWidth = 124.0;
  const panelHeight = 128.0;
  const stackedPanelGap = 138.0;
  final left = (bounds.right - padding - panelWidth).clamp(
    bounds.left + padding,
    bounds.right - panelWidth,
  );
  final top = (bounds.bottom - padding - panelHeight - stackedPanelGap).clamp(
    bounds.top + padding,
    bounds.bottom - panelHeight,
  );
  final panelRect = Rect.fromLTWH(left, top, panelWidth, panelHeight);
  final barRect = Rect.fromLTWH(left + 10, top + 22, barWidth, barHeight);

  canvas.drawRRect(
    BorderRadius.circular(4).toRRect(panelRect),
    Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.black.withValues(alpha: 0.60),
  );
  canvas.drawRRect(
    BorderRadius.circular(4).toRRect(panelRect),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFFFFD54F).withValues(alpha: 0.36),
  );

  final gradient = ui.Gradient.linear(
    barRect.bottomLeft,
    barRect.topLeft,
    [
      _trajectoryHeightColor(0),
      _trajectoryHeightColor(0.34),
      _trajectoryHeightColor(0.62),
      _trajectoryHeightColor(1),
    ],
    const [0.0, 0.34, 0.62, 1.0],
  );
  canvas.drawRRect(
    BorderRadius.circular(3).toRRect(barRect),
    Paint()..shader = gradient,
  );
  canvas.drawRRect(
    BorderRadius.circular(3).toRRect(barRect),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.45),
  );

  final tickPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.78)
    ..strokeWidth = 1;
  for (final t in const [0.0, 0.5, 1.0]) {
    final y = barRect.bottom - barRect.height * t;
    canvas.drawLine(
      Offset(barRect.right, y),
      Offset(barRect.right + 5, y),
      tickPaint,
    );
  }

  _drawOverlayText(
    canvas,
    'G-code Z',
    Offset(left + 10, top + 4),
    Colors.white.withValues(alpha: 0.94),
    fontWeight: FontWeight.w700,
  );
  _drawOverlayText(
    canvas,
    '${range.max.toStringAsFixed(1)} mm',
    Offset(barRect.right + 8, barRect.top - 7),
    Colors.white,
  );
  _drawOverlayText(
    canvas,
    '${((range.min + range.max) / 2).toStringAsFixed(1)} mm',
    Offset(barRect.right + 8, barRect.center.dy - 7),
    Colors.white.withValues(alpha: 0.88),
  );
  _drawOverlayText(
    canvas,
    '${range.min.toStringAsFixed(1)} mm',
    Offset(barRect.right + 8, barRect.bottom - 12),
    Colors.white,
  );
}

Offset _rotateOffset(Offset point, double degrees) {
  final radians = degrees * math.pi / 180.0;
  final cosValue = math.cos(radians);
  final sinValue = math.sin(radians);
  return Offset(
    point.dx * cosValue - point.dy * sinValue,
    point.dx * sinValue + point.dy * cosValue,
  );
}

Rect? _polylineBounds(List<List<Offset>> polylines) {
  var hasPoint = false;
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final polyline in polylines) {
    for (final point in polyline) {
      if (!point.dx.isFinite || !point.dy.isFinite) continue;
      hasPoint = true;
      minX = math.min(minX, point.dx);
      minY = math.min(minY, point.dy);
      maxX = math.max(maxX, point.dx);
      maxY = math.max(maxY, point.dy);
    }
  }
  if (!hasPoint) return null;
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

void _drawSurfaceGuide(
  Canvas canvas,
  Offset Function(Offset point) localToCanvas,
  List<List<Offset>> polylines,
  Offset centerLocal,
) {
  if (polylines.isEmpty) return;
  final guidePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = Colors.white.withValues(alpha: 0.42);
  for (final polyline in polylines) {
    if (polyline.length < 2) continue;
    final first = localToCanvas(polyline.first);
    final path = Path()..moveTo(first.dx, first.dy);
    for (final point in polyline.skip(1)) {
      final canvasPoint = localToCanvas(point);
      path.lineTo(canvasPoint.dx, canvasPoint.dy);
    }
    canvas.drawPath(path, guidePaint);
  }

  final center = localToCanvas(centerLocal);
  canvas.drawCircle(
    center,
    4,
    Paint()..color = Colors.white.withValues(alpha: 0.72),
  );
  canvas.drawCircle(
    center,
    4,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.black.withValues(alpha: 0.72),
  );
}

void _drawImageTrajectoryGuide(Canvas canvas, List<Offset> points) {
  if (points.isEmpty) return;
  final guidePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = Colors.white.withValues(alpha: 0.46);
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (final point in points.skip(1)) {
    path.lineTo(point.dx, point.dy);
  }
  canvas.drawPath(path, guidePaint);

  final center =
      points.fold<Offset>(Offset.zero, (sum, point) => sum + point) /
      points.length.toDouble();
  canvas.drawCircle(
    center,
    4,
    Paint()..color = Colors.white.withValues(alpha: 0.72),
  );
  canvas.drawCircle(
    center,
    4,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.black.withValues(alpha: 0.72),
  );
}

void _drawSurfaceReachabilityOverlay(
  Canvas canvas,
  _SurfaceReachabilityOverlay? overlay,
  Offset Function(Offset point) localToCanvas,
) {
  if (overlay == null) return;
  final paints = <_SurfaceReachabilityStatus, Paint>{
    _SurfaceReachabilityStatus.reachable: Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF66BB6A).withValues(alpha: 0.28),
    _SurfaceReachabilityStatus.unreachable: Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.deepOrangeAccent.withValues(alpha: 0.30),
    _SurfaceReachabilityStatus.yawSingular: Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.blueGrey.withValues(alpha: 0.24),
  };
  for (final triangle in overlay.triangles) {
    final path = Path()
      ..moveTo(localToCanvas(triangle.a).dx, localToCanvas(triangle.a).dy)
      ..lineTo(localToCanvas(triangle.b).dx, localToCanvas(triangle.b).dy)
      ..lineTo(localToCanvas(triangle.c).dx, localToCanvas(triangle.c).dy)
      ..close();
    canvas.drawPath(path, paints[triangle.status]!);
  }
}

class _SurfaceTrajectoryPainter extends CustomPainter {
  final StlMesh mesh;
  final _ContactFace contactFace;
  final _SurfaceReachabilityOverlay? reachabilityOverlay;
  final List<_SurfaceToolPoint> trajectory;
  final List<_GcodeTrajectoryPoint> gcodeTrajectory;
  final List<_ActualTrajectoryPoint> actualTrajectory;
  final bool showGcodeZMap;
  final bool interpolateGcodeZMapVertices;
  final double bedZ;
  final double clearanceMm;
  final _SurfaceCommandCorrection? gcodeZMapCorrection;
  final _LocalToMachineTransform? gcodeZMapTransform;
  final double patternWidth;
  final double patternHeight;
  final Offset patternCenterLocal;
  final double patternRotationDeg;
  final List<List<Offset>> guidePolylines;

  const _SurfaceTrajectoryPainter({
    required this.mesh,
    required this.contactFace,
    required this.reachabilityOverlay,
    required this.trajectory,
    required this.gcodeTrajectory,
    required this.actualTrajectory,
    required this.showGcodeZMap,
    required this.interpolateGcodeZMapVertices,
    required this.bedZ,
    required this.clearanceMm,
    required this.gcodeZMapCorrection,
    required this.gcodeZMapTransform,
    required this.patternWidth,
    required this.patternHeight,
    required this.patternCenterLocal,
    required this.patternRotationDeg,
    required this.guidePolylines,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (mesh.isEmpty || size.width <= 0 || size.height <= 0) return;
    final basis = _ProjectionBasis.fromContactFace(contactFace);
    final bounds = mesh.bounds;
    final projectedSize = basis.projectedSize(bounds);
    final guideBounds = _polylineBounds(guidePolylines);
    final spanX = math.max(
      projectedSize.width,
      guideBounds?.width ?? patternWidth,
    );
    final spanY = math.max(
      projectedSize.height,
      guideBounds?.height ?? patternHeight,
    );
    final scale = math
        .min(
          (size.width - 64) / math.max(1.0, spanX),
          (size.height - 64) / math.max(1.0, spanY),
        )
        .clamp(0.05, 1000.0);
    final center = Offset(size.width / 2, size.height / 2);

    Offset localToCanvas(double x, double y) {
      return Offset(center.dx + x * scale, center.dy - y * scale);
    }

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.07);
    for (var x = -spanX / 2; x <= spanX / 2; x += 10) {
      canvas.drawLine(
        localToCanvas(x, -spanY / 2),
        localToCanvas(x, spanY / 2),
        gridPaint,
      );
    }
    for (var y = -spanY / 2; y <= spanY / 2; y += 10) {
      canvas.drawLine(
        localToCanvas(-spanX / 2, y),
        localToCanvas(spanX / 2, y),
        gridPaint,
      );
    }

    final modelPath = Path();
    final centerUv = basis.project(bounds.center);
    final u0 = basis.minU(bounds) - centerUv.dx;
    final u1 = basis.maxU(bounds) - centerUv.dx;
    final v0 = basis.minV(bounds) - centerUv.dy;
    final v1 = basis.maxV(bounds) - centerUv.dy;
    final corners = [
      localToCanvas(u0, v0),
      localToCanvas(u1, v0),
      localToCanvas(u1, v1),
      localToCanvas(u0, v1),
    ];
    modelPath.moveTo(corners.first.dx, corners.first.dy);
    for (final corner in corners.skip(1)) {
      modelPath.lineTo(corner.dx, corner.dy);
    }
    modelPath.close();
    canvas.drawPath(
      modelPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.lightBlueAccent.withValues(alpha: 0.06),
    );
    canvas.drawPath(
      modelPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.lightBlueAccent.withValues(alpha: 0.62),
    );

    if (showGcodeZMap) {
      _drawGcodeZMapProjection(
        canvas: canvas,
        mesh: mesh,
        basis: basis,
        localToCanvas: (point) => localToCanvas(point.dx, point.dy),
        legendBounds: Rect.fromLTWH(0, 0, size.width, size.height),
        bedZ: bedZ,
        clearanceMm: clearanceMm,
        correction: gcodeZMapCorrection,
        transform: gcodeZMapTransform,
        interpolateVertices: interpolateGcodeZMapVertices,
        opacity: 0.74,
      );
      canvas.drawPath(
        modelPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.lightBlueAccent.withValues(alpha: 0.72),
      );
    }

    _drawSurfaceReachabilityOverlay(
      canvas,
      reachabilityOverlay,
      (point) => localToCanvas(point.dx, point.dy),
    );

    final axisPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    axisPaint.color = Colors.redAccent.withValues(alpha: 0.72);
    canvas.drawLine(
      center,
      localToCanvas(math.min(spanX / 3, 35), 0),
      axisPaint,
    );
    axisPaint.color = const Color(0xFF45C486).withValues(alpha: 0.72);
    canvas.drawLine(
      center,
      localToCanvas(0, math.min(spanY / 3, 35)),
      axisPaint,
    );

    _drawSurfaceGuide(
      canvas,
      (point) => localToCanvas(point.dx, point.dy),
      guidePolylines,
      patternCenterLocal,
    );

    if (trajectory.isEmpty) return;
    final travelPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.35);
    final workPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = Colors.amberAccent.withValues(alpha: 0.9);
    for (var i = 1; i < trajectory.length; i++) {
      final previous = trajectory[i - 1];
      final current = trajectory[i];
      canvas.drawLine(
        localToCanvas(previous.localX, previous.localY),
        localToCanvas(current.localX, current.localY),
        current.travel ? travelPaint : workPaint,
      );
    }

    if (gcodeTrajectory.isNotEmpty) {
      final targetHeightRange = _surfaceTrajectoryHeightRange(trajectory);
      final heightRange = _gcodeTrajectoryHeightRange(
        gcodeTrajectory,
        targetHeightRange,
      );
      final gcodeLinePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF26C6DA).withValues(alpha: 0.76);
      for (var i = 1; i < gcodeTrajectory.length; i++) {
        final previous = gcodeTrajectory[i - 1];
        final current = gcodeTrajectory[i];
        canvas.drawLine(
          localToCanvas(previous.localX, previous.localY),
          localToCanvas(current.localX, current.localY),
          gcodeLinePaint,
        );
      }
      final pointFill = Paint();
      final pointStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = Colors.black.withValues(alpha: 0.68);
      for (final point in gcodeTrajectory) {
        final canvasPoint = localToCanvas(point.localX, point.localY);
        pointFill.color = _gcodePointColor(point, heightRange);
        canvas.drawCircle(canvasPoint, 2.8, pointFill);
        canvas.drawCircle(canvasPoint, 2.8, pointStroke);
      }
    }

    if (actualTrajectory.isNotEmpty) {
      final targetHeightRange = _surfaceTrajectoryHeightRange(trajectory);
      final heightRange = _actualTrajectoryHeightRange(
        actualTrajectory,
        targetHeightRange,
      );
      final actualPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (var i = 1; i < actualTrajectory.length; i++) {
        final previous = actualTrajectory[i - 1];
        final current = actualTrajectory[i];
        actualPaint.color = _actualSegmentColor(
          previous,
          current,
          heightRange,
        ).withValues(alpha: 0.96);
        canvas.drawLine(
          localToCanvas(previous.localX, previous.localY),
          localToCanvas(current.localX, current.localY),
          actualPaint,
        );
      }

      final pointFill = Paint();
      final pointStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.black.withValues(alpha: 0.72);
      for (final point in actualTrajectory) {
        final canvasPoint = localToCanvas(point.localX, point.localY);
        pointFill.color = _actualPointColor(point, heightRange);
        canvas.drawCircle(canvasPoint, 3.8, pointFill);
        canvas.drawCircle(canvasPoint, 3.8, pointStroke);
      }
      _drawActualTrajectoryHeightScale(
        canvas,
        Rect.fromLTWH(0, 0, size.width, size.height),
        actualTrajectory,
        targetHeightRange,
      );
    }

    final start = localToCanvas(
      trajectory.first.localX,
      trajectory.first.localY,
    );
    final end = localToCanvas(trajectory.last.localX, trajectory.last.localY);
    canvas.drawCircle(start, 5, Paint()..color = const Color(0xFF45C486));
    canvas.drawCircle(end, 5, Paint()..color = Colors.redAccent);
  }

  @override
  bool shouldRepaint(covariant _SurfaceTrajectoryPainter oldDelegate) {
    return oldDelegate.mesh != mesh ||
        oldDelegate.contactFace != contactFace ||
        oldDelegate.reachabilityOverlay != reachabilityOverlay ||
        oldDelegate.trajectory != trajectory ||
        oldDelegate.gcodeTrajectory != gcodeTrajectory ||
        oldDelegate.actualTrajectory != actualTrajectory ||
        oldDelegate.showGcodeZMap != showGcodeZMap ||
        oldDelegate.interpolateGcodeZMapVertices !=
            interpolateGcodeZMapVertices ||
        oldDelegate.bedZ != bedZ ||
        oldDelegate.clearanceMm != clearanceMm ||
        oldDelegate.gcodeZMapCorrection != gcodeZMapCorrection ||
        oldDelegate.gcodeZMapTransform != gcodeZMapTransform ||
        oldDelegate.patternWidth != patternWidth ||
        oldDelegate.patternHeight != patternHeight ||
        oldDelegate.patternCenterLocal != patternCenterLocal ||
        oldDelegate.patternRotationDeg != patternRotationDeg ||
        oldDelegate.guidePolylines != guidePolylines;
  }
}

class _SurfaceTrajectoryPhotoPainter extends CustomPainter {
  final StlMesh mesh;
  final Size imageSize;
  final _ContactFace contactFace;
  final _SurfaceReachabilityOverlay? reachabilityOverlay;
  final Offset offsetPx;
  final double yawDeg;
  final double scalePxPerMm;
  final List<_SurfaceToolPoint> trajectory;
  final List<_GcodeTrajectoryPoint> gcodeTrajectory;
  final List<_ActualTrajectoryPoint> actualTrajectory;
  final List<_PlannedImageTrajectoryPoint> plannedImageTrajectory;
  final bool showGcodeZMap;
  final bool interpolateGcodeZMapVertices;
  final double bedZ;
  final double clearanceMm;
  final _SurfaceCommandCorrection? gcodeZMapCorrection;
  final _LocalToMachineTransform? gcodeZMapTransform;
  final double patternWidth;
  final double patternHeight;
  final Offset patternCenterLocal;
  final double patternRotationDeg;
  final List<List<Offset>> guidePolylines;

  const _SurfaceTrajectoryPhotoPainter({
    required this.mesh,
    required this.imageSize,
    required this.contactFace,
    required this.reachabilityOverlay,
    required this.offsetPx,
    required this.yawDeg,
    required this.scalePxPerMm,
    required this.trajectory,
    required this.gcodeTrajectory,
    required this.actualTrajectory,
    required this.plannedImageTrajectory,
    required this.showGcodeZMap,
    required this.interpolateGcodeZMapVertices,
    required this.bedZ,
    required this.clearanceMm,
    required this.gcodeZMapCorrection,
    required this.gcodeZMapTransform,
    required this.patternWidth,
    required this.patternHeight,
    required this.patternCenterLocal,
    required this.patternRotationDeg,
    required this.guidePolylines,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (mesh.isEmpty || imageSize.width <= 0 || imageSize.height <= 0) return;
    final imageRect = _containRect(size, imageSize);
    canvas.save();
    canvas.clipRect(imageRect);

    if (showGcodeZMap) {
      _drawGcodeZMapProjection(
        canvas: canvas,
        mesh: mesh,
        basis: _ProjectionBasis.fromContactFace(contactFace),
        localToCanvas: (point) => _stlProjectionLocalToCanvas(point, imageRect),
        legendBounds: imageRect,
        bedZ: bedZ,
        clearanceMm: clearanceMm,
        correction: gcodeZMapCorrection,
        transform: gcodeZMapTransform,
        interpolateVertices: interpolateGcodeZMapVertices,
        opacity: 0.80,
      );
    }

    _drawSurfaceReachabilityOverlay(
      canvas,
      reachabilityOverlay,
      (point) => _stlProjectionLocalToCanvas(point, imageRect),
    );

    if (plannedImageTrajectory.length >= 2) {
      _drawImageTrajectoryGuide(
        canvas,
        plannedImageTrajectory
            .map((point) {
              return _imagePxToCanvas(point.imagePx, imageRect);
            })
            .toList(growable: false),
      );
    } else {
      _drawSurfaceGuide(
        canvas,
        (point) => _stlProjectionLocalToCanvas(point, imageRect),
        guidePolylines,
        patternCenterLocal,
      );
    }

    if (trajectory.isEmpty) {
      canvas.restore();
      return;
    }

    final travelPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.45);
    final workPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = Colors.amberAccent.withValues(alpha: 0.96);

    if (plannedImageTrajectory.length >= 2) {
      for (var i = 1; i < plannedImageTrajectory.length; i++) {
        final previous = plannedImageTrajectory[i - 1].imagePx;
        final current = plannedImageTrajectory[i].imagePx;
        canvas.drawLine(
          _imagePxToCanvas(previous, imageRect),
          _imagePxToCanvas(current, imageRect),
          workPaint,
        );
      }
    } else {
      for (var i = 1; i < trajectory.length; i++) {
        final previous = trajectory[i - 1];
        final current = trajectory[i];
        canvas.drawLine(
          _stlProjectionLocalToCanvas(
            Offset(previous.localX, previous.localY),
            imageRect,
          ),
          _stlProjectionLocalToCanvas(
            Offset(current.localX, current.localY),
            imageRect,
          ),
          current.travel ? travelPaint : workPaint,
        );
      }
    }

    if (gcodeTrajectory.isNotEmpty) {
      final targetHeightRange = _surfaceTrajectoryHeightRange(trajectory);
      final heightRange = _gcodeTrajectoryHeightRange(
        gcodeTrajectory,
        targetHeightRange,
      );
      final gcodeLinePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF26C6DA).withValues(alpha: 0.78);
      for (var i = 1; i < gcodeTrajectory.length; i++) {
        final previous = gcodeTrajectory[i - 1];
        final current = gcodeTrajectory[i];
        canvas.drawLine(
          _stlProjectionLocalToCanvas(previous.localOffset, imageRect),
          _stlProjectionLocalToCanvas(current.localOffset, imageRect),
          gcodeLinePaint,
        );
      }
      final pointFill = Paint();
      final pointStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = Colors.black.withValues(alpha: 0.72);
      for (final point in gcodeTrajectory) {
        final canvasPoint = _stlProjectionLocalToCanvas(
          point.localOffset,
          imageRect,
        );
        pointFill.color = _gcodePointColor(point, heightRange);
        canvas.drawCircle(canvasPoint, 3.0, pointFill);
        canvas.drawCircle(canvasPoint, 3.0, pointStroke);
      }
    }

    if (actualTrajectory.isNotEmpty) {
      final targetHeightRange = _surfaceTrajectoryHeightRange(trajectory);
      final heightRange = _actualTrajectoryHeightRange(
        actualTrajectory,
        targetHeightRange,
      );
      final actualPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (var i = 1; i < actualTrajectory.length; i++) {
        final previous = actualTrajectory[i - 1];
        final current = actualTrajectory[i];
        final previousCanvas = _actualPointToCanvas(previous, imageRect);
        final currentCanvas = _actualPointToCanvas(current, imageRect);
        if (previousCanvas == null || currentCanvas == null) continue;
        actualPaint.color = _actualSegmentColor(
          previous,
          current,
          heightRange,
        ).withValues(alpha: 0.98);
        canvas.drawLine(previousCanvas, currentCanvas, actualPaint);
      }

      final pointFill = Paint();
      final pointStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.black.withValues(alpha: 0.75);
      for (final point in actualTrajectory) {
        final canvasPoint = _actualPointToCanvas(point, imageRect);
        if (canvasPoint == null) continue;
        pointFill.color = _actualPointColor(point, heightRange);
        canvas.drawCircle(canvasPoint, 4.2, pointFill);
        canvas.drawCircle(canvasPoint, 4.2, pointStroke);
      }
      _drawActualTrajectoryHeightScale(
        canvas,
        imageRect,
        actualTrajectory,
        targetHeightRange,
      );
    }

    final start = plannedImageTrajectory.isNotEmpty
        ? _imagePxToCanvas(plannedImageTrajectory.first.imagePx, imageRect)
        : _stlProjectionLocalToCanvas(
            Offset(trajectory.first.localX, trajectory.first.localY),
            imageRect,
          );
    final end = plannedImageTrajectory.isNotEmpty
        ? _imagePxToCanvas(plannedImageTrajectory.last.imagePx, imageRect)
        : _stlProjectionLocalToCanvas(
            Offset(trajectory.last.localX, trajectory.last.localY),
            imageRect,
          );
    canvas.drawCircle(start, 5.5, Paint()..color = const Color(0xFF45C486));
    canvas.drawCircle(end, 5.5, Paint()..color = Colors.redAccent);
    canvas.restore();
  }

  Rect _containRect(Size outer, Size inner) {
    final scale = math.min(
      outer.width / inner.width,
      outer.height / inner.height,
    );
    final width = inner.width * scale;
    final height = inner.height * scale;
    return Rect.fromLTWH(
      (outer.width - width) / 2,
      (outer.height - height) / 2,
      width,
      height,
    );
  }

  Offset _stlProjectionLocalToCanvas(Offset localMm, Rect imageRect) {
    final localPx = Offset(
      localMm.dx * scalePxPerMm,
      -localMm.dy * scalePxPerMm,
    );
    final yaw = yawDeg * math.pi / 180.0;
    final cosYaw = math.cos(yaw);
    final sinYaw = math.sin(yaw);
    final rotated = Offset(
      localPx.dx * cosYaw - localPx.dy * sinYaw,
      localPx.dx * sinYaw + localPx.dy * cosYaw,
    );
    final imagePx = Offset(
      imageSize.width / 2 + offsetPx.dx + rotated.dx,
      imageSize.height / 2 + offsetPx.dy + rotated.dy,
    );
    return Offset(
      imageRect.left + imagePx.dx * imageRect.width / imageSize.width,
      imageRect.top + imagePx.dy * imageRect.height / imageSize.height,
    );
  }

  Offset _imagePxToCanvas(Offset imagePx, Rect imageRect) {
    return Offset(
      imageRect.left + imagePx.dx * imageRect.width / imageSize.width,
      imageRect.top + imagePx.dy * imageRect.height / imageSize.height,
    );
  }

  Offset? _actualPointToCanvas(_ActualTrajectoryPoint point, Rect imageRect) {
    final imagePx = point.imagePx;
    if (imagePx != null) {
      return _imagePxToCanvas(imagePx, imageRect);
    }
    return _stlProjectionLocalToCanvas(point.localOffset, imageRect);
  }

  @override
  bool shouldRepaint(covariant _SurfaceTrajectoryPhotoPainter oldDelegate) {
    return oldDelegate.mesh != mesh ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.contactFace != contactFace ||
        oldDelegate.reachabilityOverlay != reachabilityOverlay ||
        oldDelegate.offsetPx != offsetPx ||
        oldDelegate.yawDeg != yawDeg ||
        oldDelegate.scalePxPerMm != scalePxPerMm ||
        oldDelegate.trajectory != trajectory ||
        oldDelegate.gcodeTrajectory != gcodeTrajectory ||
        oldDelegate.actualTrajectory != actualTrajectory ||
        oldDelegate.plannedImageTrajectory != plannedImageTrajectory ||
        oldDelegate.showGcodeZMap != showGcodeZMap ||
        oldDelegate.interpolateGcodeZMapVertices !=
            interpolateGcodeZMapVertices ||
        oldDelegate.bedZ != bedZ ||
        oldDelegate.clearanceMm != clearanceMm ||
        oldDelegate.gcodeZMapCorrection != gcodeZMapCorrection ||
        oldDelegate.gcodeZMapTransform != gcodeZMapTransform ||
        oldDelegate.patternWidth != patternWidth ||
        oldDelegate.patternHeight != patternHeight ||
        oldDelegate.patternCenterLocal != patternCenterLocal ||
        oldDelegate.patternRotationDeg != patternRotationDeg ||
        oldDelegate.guidePolylines != guidePolylines;
  }
}

class _StlTopProjectionPainter extends CustomPainter {
  final StlMesh mesh;
  final Size imageSize;
  final _ContactFace contactFace;
  final Offset offsetPx;
  final double yawDeg;
  final double scalePxPerMm;
  final double opacity;
  final bool showHeightMap;
  final bool interpolateHeightVertices;
  final bool showMesh;
  final bool showAxes;
  final bool showBounds;

  const _StlTopProjectionPainter({
    required this.mesh,
    required this.imageSize,
    required this.contactFace,
    required this.offsetPx,
    required this.yawDeg,
    required this.scalePxPerMm,
    required this.opacity,
    required this.showHeightMap,
    required this.interpolateHeightVertices,
    required this.showMesh,
    required this.showAxes,
    required this.showBounds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (mesh.isEmpty || imageSize.width <= 0 || imageSize.height <= 0) return;

    final imageRect = _containRect(size, imageSize);
    final clip = Rect.fromLTRB(
      imageRect.left - 1,
      imageRect.top - 1,
      imageRect.right + 1,
      imageRect.bottom + 1,
    );
    canvas.save();
    canvas.clipRect(clip);

    if (showHeightMap) {
      _drawHeightMapProjection(canvas, imageRect);
      _drawHeightMapScale(canvas, imageRect);
    }
    if (showMesh) _drawWireProjection(canvas, imageRect);
    if (showBounds) _drawBounds(canvas, imageRect);
    if (showAxes) _drawAxes(canvas, imageRect);

    canvas.restore();
  }

  Rect _containRect(Size outer, Size inner) {
    final scale = math.min(
      outer.width / inner.width,
      outer.height / inner.height,
    );
    final width = inner.width * scale;
    final height = inner.height * scale;
    return Rect.fromLTWH(
      (outer.width - width) / 2,
      (outer.height - height) / 2,
      width,
      height,
    );
  }

  Offset _modelToCanvas(StlVector3 point, Rect imageRect) {
    final basis = _ProjectionBasis.fromContactFace(contactFace);
    final projected = basis.project(point);
    final center = basis.project(mesh.bounds.center);
    final local = Offset(
      (projected.dx - center.dx) * scalePxPerMm,
      -(projected.dy - center.dy) * scalePxPerMm,
    );
    final yaw = yawDeg * math.pi / 180.0;
    final cosYaw = math.cos(yaw);
    final sinYaw = math.sin(yaw);
    final rotated = Offset(
      local.dx * cosYaw - local.dy * sinYaw,
      local.dx * sinYaw + local.dy * cosYaw,
    );
    final imagePx = Offset(
      imageSize.width / 2 + offsetPx.dx + rotated.dx,
      imageSize.height / 2 + offsetPx.dy + rotated.dy,
    );
    return Offset(
      imageRect.left + imagePx.dx * imageRect.width / imageSize.width,
      imageRect.top + imagePx.dy * imageRect.height / imageSize.height,
    );
  }

  void _drawWireProjection(Canvas canvas, Rect imageRect) {
    final path = Path();
    for (final triangle in mesh.sampledTriangles(3200)) {
      final a = _modelToCanvas(triangle.a, imageRect);
      final b = _modelToCanvas(triangle.b, imageRect);
      final c = _modelToCanvas(triangle.c, imageRect);
      path
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(c.dx, c.dy)
        ..close();
    }
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.amberAccent.withValues(alpha: opacity * 0.08);
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.amberAccent.withValues(alpha: opacity * 0.62);
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  void _drawHeightMapProjection(Canvas canvas, Rect imageRect) {
    final basis = _ProjectionBasis.fromContactFace(contactFace);
    final minHeight = basis.minHeight(mesh.bounds);
    final heightRange = math.max(
      basis.maxHeight(mesh.bounds) - minHeight,
      1e-6,
    );
    final paint = Paint()..style = PaintingStyle.fill;

    for (final triangle in mesh.sampledTriangles(4200)) {
      if (interpolateHeightVertices &&
          !_isVisibleHeightTriangle(mesh, basis, triangle)) {
        continue;
      }
      final a = _modelToCanvas(triangle.a, imageRect);
      final b = _modelToCanvas(triangle.b, imageRect);
      final c = _modelToCanvas(triangle.c, imageRect);
      final colors = interpolateHeightVertices
          ? [triangle.a, triangle.b, triangle.c]
                .map(
                  (point) => _heightMapColor(
                    (basis.heightValue(point) - minHeight) / heightRange,
                  ).withValues(alpha: opacity * 0.90),
                )
                .toList(growable: false)
          : List<Color>.filled(
              3,
              _heightMapColor(
                (basis.heightValue(triangle.center) - minHeight) / heightRange,
              ).withValues(alpha: opacity * 0.48),
            );
      canvas.drawVertices(
        ui.Vertices(ui.VertexMode.triangles, [a, b, c], colors: colors),
        BlendMode.srcOver,
        paint,
      );
    }
  }

  Color _heightMapColor(double t) {
    final stops = <({double stop, Color color})>[
      (stop: 0.0, color: const Color(0xFF1E88E5)),
      (stop: 0.34, color: const Color(0xFF00ACC1)),
      (stop: 0.62, color: const Color(0xFFFFD54F)),
      (stop: 1.0, color: const Color(0xFFE53935)),
    ];
    for (var i = 1; i < stops.length; i++) {
      final previous = stops[i - 1];
      final current = stops[i];
      if (t <= current.stop) {
        final localT = ((t - previous.stop) / (current.stop - previous.stop))
            .clamp(0.0, 1.0);
        return Color.lerp(previous.color, current.color, localT)!;
      }
    }
    return stops.last.color;
  }

  void _drawHeightMapScale(Canvas canvas, Rect imageRect) {
    final basis = _ProjectionBasis.fromContactFace(contactFace);
    final minHeight = basis.minHeight(mesh.bounds);
    final maxHeight = basis.maxHeight(mesh.bounds);
    const barWidth = 18.0;
    const barHeight = 118.0;
    const padding = 12.0;
    const labelGap = 8.0;
    final left = imageRect.left + padding;
    final top = imageRect.bottom - padding - barHeight;
    final barRect = Rect.fromLTWH(left, top, barWidth, barHeight);
    final panelRect = Rect.fromLTWH(left - 9, top - 28, 138, barHeight + 46);

    final panelPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.58)
      ..style = PaintingStyle.fill;
    final panelBorder = Paint()
      ..color = Colors.white.withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final radius = BorderRadius.circular(4).toRRect(panelRect);
    canvas.drawRRect(radius, panelPaint);
    canvas.drawRRect(radius, panelBorder);

    final gradient = ui.Gradient.linear(
      barRect.bottomLeft,
      barRect.topLeft,
      [
        _heightMapColor(0),
        _heightMapColor(0.34),
        _heightMapColor(0.62),
        _heightMapColor(1),
      ],
      const [0.0, 0.34, 0.62, 1.0],
    );
    final barPaint = Paint()..shader = gradient;
    canvas.drawRRect(BorderRadius.circular(3).toRRect(barRect), barPaint);
    canvas.drawRRect(
      BorderRadius.circular(3).toRRect(barRect),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.45),
    );

    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.78)
      ..strokeWidth = 1;
    for (final t in const [0.0, 0.5, 1.0]) {
      final y = barRect.bottom - barRect.height * t;
      canvas.drawLine(
        Offset(barRect.right, y),
        Offset(barRect.right + 5, y),
        tickPaint,
      );
    }

    _drawLegendText(
      canvas,
      'Height ${basis.heightAxis.label}',
      Offset(left, top - 22),
      Colors.white.withValues(alpha: 0.92),
      fontWeight: FontWeight.w700,
    );
    _drawLegendText(
      canvas,
      '${maxHeight.toStringAsFixed(1)} mm',
      Offset(barRect.right + labelGap, barRect.top - 7),
      Colors.white,
    );
    _drawLegendText(
      canvas,
      '${((minHeight + maxHeight) / 2).toStringAsFixed(1)} mm',
      Offset(barRect.right + labelGap, barRect.center.dy - 7),
      Colors.white.withValues(alpha: 0.88),
    );
    _drawLegendText(
      canvas,
      '${minHeight.toStringAsFixed(1)} mm',
      Offset(barRect.right + labelGap, barRect.bottom - 12),
      Colors.white,
    );
  }

  void _drawLegendText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color, {
    FontWeight fontWeight = FontWeight.w500,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: fontWeight),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 110);
    textPainter.paint(canvas, offset);
  }

  void _drawBounds(Canvas canvas, Rect imageRect) {
    final bounds = mesh.bounds;
    final basis = _ProjectionBasis.fromContactFace(contactFace);
    final u0 = basis.minU(bounds);
    final u1 = basis.maxU(bounds);
    final v0 = basis.minV(bounds);
    final v1 = basis.maxV(bounds);
    final corners = [
      basis.pointOnProjectionPlane(bounds, u0, v0),
      basis.pointOnProjectionPlane(bounds, u1, v0),
      basis.pointOnProjectionPlane(bounds, u1, v1),
      basis.pointOnProjectionPlane(bounds, u0, v1),
    ].map((point) => _modelToCanvas(point, imageRect)).toList();
    final path = Path()..moveTo(corners.first.dx, corners.first.dy);
    for (final corner in corners.skip(1)) {
      path.lineTo(corner.dx, corner.dy);
    }
    path.close();
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.lightBlueAccent.withValues(alpha: opacity * 0.9);
    canvas.drawPath(path, paint);
  }

  void _drawAxes(Canvas canvas, Rect imageRect) {
    final bounds = mesh.bounds;
    final basis = _ProjectionBasis.fromContactFace(contactFace);
    final origin = bounds.center;
    final projectedSize = basis.projectedSize(bounds);
    final axisSpan = math.max(projectedSize.width, projectedSize.height);
    final axisLength = axisSpan.isFinite && axisSpan > 1e-6
        ? math.max(10.0, axisSpan * 0.32)
        : 20.0;
    final start = _modelToCanvas(origin, imageRect);
    final uEnd = _modelToCanvas(
      basis.offsetAlong(origin, basis.uAxis, axisLength),
      imageRect,
    );
    final vEnd = _modelToCanvas(
      basis.offsetAlong(origin, basis.vAxis, axisLength),
      imageRect,
    );

    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: opacity);
    canvas.drawCircle(start, 4.5, dotPaint);
    _drawArrow(canvas, start, uEnd, Colors.redAccent, basis.uAxis.label);
    _drawArrow(canvas, start, vEnd, const Color(0xFF45C486), basis.vAxis.label);
  }

  void _drawArrow(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color,
    String label,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: opacity);
    canvas.drawLine(start, end, paint);

    final vector = end - start;
    final angle = math.atan2(vector.dy, vector.dx);
    const headLength = 12.0;
    const headAngle = math.pi / 7;
    final p1 =
        end -
        Offset(
          math.cos(angle - headAngle) * headLength,
          math.sin(angle - headAngle) * headLength,
        );
    final p2 =
        end -
        Offset(
          math.cos(angle + headAngle) * headLength,
          math.sin(angle + headAngle) * headLength,
        );
    final headPath = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(p1.dx, p1.dy)
      ..moveTo(end.dx, end.dy)
      ..lineTo(p2.dx, p2.dy);
    canvas.drawPath(headPath, paint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color.withValues(alpha: opacity),
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, end + const Offset(6, -22));
  }

  @override
  bool shouldRepaint(covariant _StlTopProjectionPainter oldDelegate) {
    return oldDelegate.mesh != mesh ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.contactFace != contactFace ||
        oldDelegate.offsetPx != offsetPx ||
        oldDelegate.yawDeg != yawDeg ||
        oldDelegate.scalePxPerMm != scalePxPerMm ||
        oldDelegate.opacity != opacity ||
        oldDelegate.showHeightMap != showHeightMap ||
        oldDelegate.interpolateHeightVertices != interpolateHeightVertices ||
        oldDelegate.showMesh != showMesh ||
        oldDelegate.showAxes != showAxes ||
        oldDelegate.showBounds != showBounds;
  }
}

class _AlignmentHandlesLayer extends StatelessWidget {
  final StlMesh mesh;
  final Size imageSize;
  final Size sceneSize;
  final TransformationController transformController;
  final _ContactFace contactFace;
  final Offset offsetPx;
  final double yawDeg;
  final double scalePxPerMm;
  final _AlignmentHandleId? lockedHandle;
  final void Function({
    required _AlignmentHandleId handle,
    required Offset targetImagePx,
  })
  onDragHandle;
  final ValueChanged<_AlignmentHandleId> onToggleLock;

  const _AlignmentHandlesLayer({
    required this.mesh,
    required this.imageSize,
    required this.sceneSize,
    required this.transformController,
    required this.contactFace,
    required this.offsetPx,
    required this.yawDeg,
    required this.scalePxPerMm,
    required this.lockedHandle,
    required this.onDragHandle,
    required this.onToggleLock,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: transformController,
      builder: (context, _) {
        final geometry = _AlignmentHandleGeometry(
          mesh: mesh,
          imageSize: imageSize,
          sceneSize: sceneSize,
          contactFace: contactFace,
          offsetPx: offsetPx,
          yawDeg: yawDeg,
          scalePxPerMm: scalePxPerMm,
        );
        final handles = geometry.handleScenePoints();

        return Stack(
          children: [
            for (final entry in handles.entries)
              _buildHandle(
                context: context,
                handle: entry.key,
                scenePoint: entry.value,
                geometry: geometry,
              ),
          ],
        );
      },
    );
  }

  Widget _buildHandle({
    required BuildContext context,
    required _AlignmentHandleId handle,
    required Offset scenePoint,
    required _AlignmentHandleGeometry geometry,
  }) {
    final viewportPoint = MatrixUtils.transformPoint(
      transformController.value,
      scenePoint,
    );
    final locked = lockedHandle == handle;
    final color = locked ? const Color(0xFF45C486) : Colors.amberAccent;

    return Positioned(
      left: viewportPoint.dx - 13,
      top: viewportPoint.dy - 13,
      width: 26,
      height: 26,
      child: Tooltip(
        message: locked
            ? '${handle.label} locked'
            : 'Drag ${handle.label}; double-click to lock',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: () => onToggleLock(handle),
          onPanStart: (details) =>
              _dragToPointer(context, handle, geometry, details.globalPosition),
          onPanUpdate: (details) =>
              _dragToPointer(context, handle, geometry, details.globalPosition),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: locked ? 3 : 2),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.28),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(
              locked ? Icons.lock : Icons.drag_indicator,
              size: 14,
              color: color,
            ),
          ),
        ),
      ),
    );
  }

  void _dragToPointer(
    BuildContext context,
    _AlignmentHandleId handle,
    _AlignmentHandleGeometry geometry,
    Offset globalPosition,
  ) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final viewportPoint = box.globalToLocal(globalPosition);
    final scenePoint = transformController.toScene(viewportPoint);
    final imagePx = geometry.sceneToImagePx(scenePoint);
    if (imagePx == null) return;
    onDragHandle(handle: handle, targetImagePx: imagePx);
  }
}

class _AlignmentHandleGeometry {
  final StlMesh mesh;
  final Size imageSize;
  final Size sceneSize;
  final _ContactFace contactFace;
  final Offset offsetPx;
  final double yawDeg;
  final double scalePxPerMm;

  const _AlignmentHandleGeometry({
    required this.mesh,
    required this.imageSize,
    required this.sceneSize,
    required this.contactFace,
    required this.offsetPx,
    required this.yawDeg,
    required this.scalePxPerMm,
  });

  Map<_AlignmentHandleId, Offset> handleScenePoints() {
    final imageRect = _containRect(sceneSize, imageSize);
    final imageCenter = Offset(imageSize.width / 2, imageSize.height / 2);
    final deltas = _handleDeltas();
    return {
      for (final entry in deltas.entries)
        entry.key: _imagePxToScene(
          imageCenter + offsetPx + entry.value * scalePxPerMm,
          imageRect,
        ),
    };
  }

  Offset? sceneToImagePx(Offset scenePoint) {
    final imageRect = _containRect(sceneSize, imageSize);
    if (!imageRect.inflate(48).contains(scenePoint)) return null;
    return Offset(
      (scenePoint.dx - imageRect.left) * imageSize.width / imageRect.width,
      (scenePoint.dy - imageRect.top) * imageSize.height / imageRect.height,
    );
  }

  Map<_AlignmentHandleId, Offset> _handleDeltas() {
    final basis = _ProjectionBasis.fromContactFace(contactFace);
    final bounds = mesh.bounds;
    final center = basis.project(bounds.center);
    final u0 = basis.minU(bounds);
    final u1 = basis.maxU(bounds);
    final v0 = basis.minV(bounds);
    final v1 = basis.maxV(bounds);
    final um = (u0 + u1) / 2;
    final vm = (v0 + v1) / 2;

    Offset delta(double u, double v) {
      final local = Offset(u - center.dx, -(v - center.dy));
      final yaw = yawDeg * math.pi / 180.0;
      final cosYaw = math.cos(yaw);
      final sinYaw = math.sin(yaw);
      return Offset(
        local.dx * cosYaw - local.dy * sinYaw,
        local.dx * sinYaw + local.dy * cosYaw,
      );
    }

    return {
      _AlignmentHandleId.topLeft: delta(u0, v1),
      _AlignmentHandleId.topCenter: delta(um, v1),
      _AlignmentHandleId.topRight: delta(u1, v1),
      _AlignmentHandleId.centerRight: delta(u1, vm),
      _AlignmentHandleId.bottomRight: delta(u1, v0),
      _AlignmentHandleId.bottomCenter: delta(um, v0),
      _AlignmentHandleId.bottomLeft: delta(u0, v0),
      _AlignmentHandleId.centerLeft: delta(u0, vm),
    };
  }

  Rect _containRect(Size outer, Size inner) {
    final scale = math.min(
      outer.width / inner.width,
      outer.height / inner.height,
    );
    final width = inner.width * scale;
    final height = inner.height * scale;
    return Rect.fromLTWH(
      (outer.width - width) / 2,
      (outer.height - height) / 2,
      width,
      height,
    );
  }

  Offset _imagePxToScene(Offset imagePx, Rect imageRect) {
    return Offset(
      imageRect.left + imagePx.dx * imageRect.width / imageSize.width,
      imageRect.top + imagePx.dy * imageRect.height / imageSize.height,
    );
  }
}

class _PreviewModeButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback? onPressed;

  const _PreviewModeButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: selected
            ? Colors.blue.withValues(alpha: 0.18)
            : Colors.transparent,
        foregroundColor: selected ? Colors.blue : Colors.grey.shade400,
      ),
      icon: Icon(icon),
    );
  }
}

class _PreviewStats extends StatelessWidget {
  final StlMesh mesh;
  final double zoom;

  const _PreviewStats({required this.mesh, required this.zoom});

  @override
  Widget build(BuildContext context) {
    final bounds = mesh.bounds;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1D2227).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: DefaultTextStyle(
          style: TextStyle(color: Colors.grey.shade200, fontSize: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('面片 ${mesh.faceCount}'),
              Text(
                '尺寸 ${bounds.width.toStringAsFixed(1)} x '
                '${bounds.depth.toStringAsFixed(1)} x '
                '${bounds.height.toStringAsFixed(1)} mm',
              ),
              Text('缩放 ${zoom.toStringAsFixed(2)}x'),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SurfacePattern {
  line('直线', false),
  semicircle('半圆', true),
  rectangle('矩形', true),
  cross('十字', true);

  final String label;
  final bool usesHeight;

  const _SurfacePattern(this.label, this.usesHeight);

  List<List<Offset>> polylines(double width, double height) {
    final halfW = width / 2;
    final halfH = height / 2;
    return switch (this) {
      _SurfacePattern.line => [
        [Offset(-halfW, 0), Offset(halfW, 0)],
      ],
      _SurfacePattern.semicircle => [
        [
          for (var i = 0; i <= 32; i++)
            Offset(
              halfW * math.cos(math.pi - math.pi * i / 32),
              halfH * math.sin(math.pi - math.pi * i / 32),
            ),
        ],
      ],
      _SurfacePattern.rectangle => [
        [
          Offset(-halfW, -halfH),
          Offset(halfW, -halfH),
          Offset(halfW, halfH),
          Offset(-halfW, halfH),
          Offset(-halfW, -halfH),
        ],
      ],
      _SurfacePattern.cross => [
        [Offset(-halfW, 0), Offset(halfW, 0)],
        [Offset(0, -halfH), Offset(0, halfH)],
      ],
    };
  }
}

class _SurfaceSample {
  final double height;
  final StlVector3 normal;

  const _SurfaceSample({required this.height, required this.normal});
}

enum _SurfaceReachabilityStatus { reachable, unreachable, yawSingular }

class _SurfaceReachabilityTriangle {
  final Offset a;
  final Offset b;
  final Offset c;
  final _SurfaceReachabilityStatus status;

  const _SurfaceReachabilityTriangle({
    required this.a,
    required this.b,
    required this.c,
    required this.status,
  });
}

class _SurfaceReachabilityOverlay {
  final List<_SurfaceReachabilityTriangle> triangles;

  const _SurfaceReachabilityOverlay(this.triangles);
}

class _SurfaceReachabilityOverlayKey {
  final StlMesh mesh;
  final _ContactFace contactFace;
  final double localizationYawDeg;
  final SurfaceToolOrientationConfig config;

  const _SurfaceReachabilityOverlayKey({
    required this.mesh,
    required this.contactFace,
    required this.localizationYawDeg,
    required this.config,
  });

  bool matches(_SurfaceReachabilityOverlayKey other) =>
      identical(mesh, other.mesh) &&
      contactFace == other.contactFace &&
      localizationYawDeg == other.localizationYawDeg &&
      config.mode == other.config.mode &&
      config.yawOffsetDeg == other.config.yawOffsetDeg &&
      config.pitchOffsetDeg == other.config.pitchOffsetDeg &&
      config.reverseYaw == other.config.reverseYaw &&
      config.reversePitch == other.config.reversePitch;
}

class _SurfaceToolPoint {
  final double localX;
  final double localY;
  final double surfaceHeight;
  final StlVector3? surfaceNormal;
  final SurfaceToolPose? toolPose;
  final double machineX;
  final double machineY;
  final double machineZ;
  final double? referenceMachineX;
  final double? referenceMachineY;
  final double? referenceMachineZ;
  final double? targetMachineX;
  final double? targetMachineY;
  final double? targetMachineZ;
  final double? targetMachineZFromBoard;
  final Offset? targetImagePx;
  final double? targetBoardX;
  final double? targetBoardY;
  final double? targetBoardZ;
  final bool travel;
  final int? polylineIndex;
  final int? segmentIndex;
  final int? sampleIndexInPolyline;
  final bool? isControlPoint;

  const _SurfaceToolPoint({
    required this.localX,
    required this.localY,
    required this.surfaceHeight,
    this.surfaceNormal,
    this.toolPose,
    required this.machineX,
    required this.machineY,
    required this.machineZ,
    this.referenceMachineX,
    this.referenceMachineY,
    this.referenceMachineZ,
    this.targetMachineX,
    this.targetMachineY,
    this.targetMachineZ,
    this.targetMachineZFromBoard,
    this.targetImagePx,
    this.targetBoardX,
    this.targetBoardY,
    this.targetBoardZ,
    required this.travel,
    this.polylineIndex,
    this.segmentIndex,
    this.sampleIndexInPolyline,
    this.isControlPoint,
  });

  int get safePolylineIndex => polylineIndex ?? 0;
  int get safeSegmentIndex => segmentIndex ?? 0;
  int get safeSampleIndexInPolyline => sampleIndexInPolyline ?? 0;
  bool get safeIsControlPoint => isControlPoint ?? travel;

  _SurfaceToolPoint copyWith({
    StlVector3? surfaceNormal,
    SurfaceToolPose? toolPose,
    double? machineX,
    double? machineY,
    double? machineZ,
    double? referenceMachineX,
    double? referenceMachineY,
    double? referenceMachineZ,
    double? targetMachineX,
    double? targetMachineY,
    double? targetMachineZ,
    double? targetMachineZFromBoard,
    Offset? targetImagePx,
    double? targetBoardX,
    double? targetBoardY,
    double? targetBoardZ,
  }) {
    return _SurfaceToolPoint(
      localX: localX,
      localY: localY,
      surfaceHeight: surfaceHeight,
      surfaceNormal: surfaceNormal ?? this.surfaceNormal,
      toolPose: toolPose ?? this.toolPose,
      machineX: machineX ?? this.machineX,
      machineY: machineY ?? this.machineY,
      machineZ: machineZ ?? this.machineZ,
      referenceMachineX: referenceMachineX ?? this.referenceMachineX,
      referenceMachineY: referenceMachineY ?? this.referenceMachineY,
      referenceMachineZ: referenceMachineZ ?? this.referenceMachineZ,
      targetMachineX: targetMachineX ?? this.targetMachineX,
      targetMachineY: targetMachineY ?? this.targetMachineY,
      targetMachineZ: targetMachineZ ?? this.targetMachineZ,
      targetMachineZFromBoard:
          targetMachineZFromBoard ?? this.targetMachineZFromBoard,
      targetImagePx: targetImagePx ?? this.targetImagePx,
      targetBoardX: targetBoardX ?? this.targetBoardX,
      targetBoardY: targetBoardY ?? this.targetBoardY,
      targetBoardZ: targetBoardZ ?? this.targetBoardZ,
      travel: travel,
      polylineIndex: polylineIndex,
      segmentIndex: segmentIndex,
      sampleIndexInPolyline: sampleIndexInPolyline,
      isControlPoint: isControlPoint,
    );
  }

  _SurfaceToolPoint copyWithMotionMetadata({
    int? sampleIndexInPolyline,
    bool? isControlPoint,
  }) {
    return _SurfaceToolPoint(
      localX: localX,
      localY: localY,
      surfaceHeight: surfaceHeight,
      surfaceNormal: surfaceNormal,
      toolPose: toolPose,
      machineX: machineX,
      machineY: machineY,
      machineZ: machineZ,
      referenceMachineX: referenceMachineX,
      referenceMachineY: referenceMachineY,
      referenceMachineZ: referenceMachineZ,
      targetMachineX: targetMachineX,
      targetMachineY: targetMachineY,
      targetMachineZ: targetMachineZ,
      targetMachineZFromBoard: targetMachineZFromBoard,
      targetImagePx: targetImagePx,
      targetBoardX: targetBoardX,
      targetBoardY: targetBoardY,
      targetBoardZ: targetBoardZ,
      travel: travel,
      polylineIndex: polylineIndex,
      segmentIndex: segmentIndex,
      sampleIndexInPolyline:
          sampleIndexInPolyline ?? this.sampleIndexInPolyline,
      isControlPoint: isControlPoint ?? this.isControlPoint,
    );
  }

  Map<String, dynamic> toJson() {
    final imagePx = targetImagePx;
    return {
      'polyline_index': safePolylineIndex,
      'segment_index': safeSegmentIndex,
      'sample_index_in_polyline': safeSampleIndexInPolyline,
      'is_control_point': safeIsControlPoint,
      'local_x_mm': localX,
      'local_y_mm': localY,
      'surface_height_mm': surfaceHeight,
      'machine_x_mm': targetMachineX ?? machineX,
      'machine_y_mm': targetMachineY ?? machineY,
      'machine_z_mm': targetMachineZ ?? machineZ,
      if (targetMachineZFromBoard != null)
        'machine_z_from_board_mm': targetMachineZFromBoard,
      if (imagePx != null) ...{
        'image_x_px': imagePx.dx,
        'image_y_px': imagePx.dy,
      },
      if (targetBoardX != null) 'board_x_mm': targetBoardX,
      if (targetBoardY != null) 'board_y_mm': targetBoardY,
      if (targetBoardZ != null) 'board_z_mm': targetBoardZ,
      'travel': travel,
    };
  }

  Map<String, dynamic> commandJson() {
    return {
      'machine_x_mm': machineX,
      'machine_y_mm': machineY,
      'machine_z_mm': machineZ,
    };
  }
}

class _SurfaceCommandCorrection {
  final double dx;
  final double dy;
  final double dz;
  final List<double>? zErrorModelCoefficients;
  final List<_SurfaceZErrorSample> zErrorSamples;
  final String? sourcePath;

  const _SurfaceCommandCorrection({
    required this.dx,
    required this.dy,
    required this.dz,
    this.zErrorModelCoefficients,
    this.zErrorSamples = const [],
    this.sourcePath,
  });

  factory _SurfaceCommandCorrection.none() {
    return const _SurfaceCommandCorrection(dx: 0, dy: 0, dz: 0);
  }

  bool get hasZErrorModel =>
      zErrorModelCoefficients != null || zErrorSamples.isNotEmpty;

  double correctedZ({required double x, required double y, required double z}) {
    final sampledError = _sampleZError(x: x, y: y, z: z);
    if (sampledError != null) return z - sampledError;
    final coeffs = zErrorModelCoefficients;
    if (coeffs == null || coeffs.length < 4) return z + dz;
    final predictedError =
        coeffs[0] + coeffs[1] * x + coeffs[2] * y + coeffs[3] * z;
    return z - predictedError;
  }

  double? _sampleZError({
    required double x,
    required double y,
    required double z,
  }) {
    if (zErrorSamples.length < 3) return null;
    const xyScaleMm = 20.0;
    const zScaleMm = 5.0;
    final distances = <({double distance, double errorZ})>[];
    for (final sample in zErrorSamples) {
      final dx = (x - sample.x) / xyScaleMm;
      final dy = (y - sample.y) / xyScaleMm;
      final dz = (z - sample.z) / zScaleMm;
      final distance = math.sqrt(dx * dx + dy * dy + dz * dz);
      distances.add((distance: distance, errorZ: sample.errorZ));
    }
    distances.sort((a, b) => a.distance.compareTo(b.distance));
    final nearest = distances.take(math.min(6, distances.length)).toList();
    if (nearest.isEmpty || nearest.first.distance > 3.0) return null;
    final exactSamples = nearest.where((item) => item.distance < 1e-6).toList();
    if (exactSamples.isNotEmpty) {
      return exactSamples.map((item) => item.errorZ).reduce((a, b) => a + b) /
          exactSamples.length;
    }
    var weighted = 0.0;
    var weightSum = 0.0;
    for (final item in nearest) {
      final weight = 1.0 / math.pow(math.max(item.distance, 1e-6), 2.0);
      weighted += weight * item.errorZ;
      weightSum += weight;
    }
    return weightSum > 0 ? weighted / weightSum : null;
  }

  Map<String, dynamic> toJson() {
    return {
      'command_precompensation_mm': [dx, dy, dz],
      if (zErrorModelCoefficients != null)
        'z_error_model': {
          'type': 'linear_machine_xyz',
          'coefficients': zErrorModelCoefficients,
        },
      if (zErrorSamples.isNotEmpty)
        'z_error_samples': [
          for (final sample in zErrorSamples) sample.toJson(),
        ],
      if (sourcePath != null) 'source_path': sourcePath,
    };
  }
}

class _SurfaceZErrorSample {
  final double x;
  final double y;
  final double z;
  final double errorZ;

  const _SurfaceZErrorSample({
    required this.x,
    required this.y,
    required this.z,
    required this.errorZ,
  });

  Map<String, dynamic> toJson() {
    return {
      'machine_x_mm': x,
      'machine_y_mm': y,
      'machine_z_mm': z,
      'error_z_mm': errorZ,
    };
  }
}

class _ActualTrajectoryPoint {
  final double localX;
  final double localY;
  final double? height;
  final Offset? imagePx;

  const _ActualTrajectoryPoint({
    required this.localX,
    required this.localY,
    this.height,
    this.imagePx,
  });

  Offset get localOffset => Offset(localX, localY);
}

class _GcodeTrajectoryPoint {
  final double localX;
  final double localY;
  final double machineX;
  final double machineY;
  final double machineZ;
  final double height;

  const _GcodeTrajectoryPoint({
    required this.localX,
    required this.localY,
    required this.machineX,
    required this.machineY,
    required this.machineZ,
    required this.height,
  });

  Offset get localOffset => Offset(localX, localY);
}

class _PlannedImageTrajectoryPoint {
  final Offset imagePx;

  const _PlannedImageTrajectoryPoint({required this.imagePx});
}

class _MachineLocalSample {
  final double machineX;
  final double machineY;
  final double localX;
  final double localY;

  const _MachineLocalSample({
    required this.machineX,
    required this.machineY,
    required this.localX,
    required this.localY,
  });
}

class _PasteSegmentCompensation {
  final double startDistanceBeforeMm;
  final double remainingDistanceAfterMm;

  const _PasteSegmentCompensation({
    required this.startDistanceBeforeMm,
    required this.remainingDistanceAfterMm,
  });
}

class _MachineToLocalTransform {
  final List<double> xCoeffs;
  final List<double> yCoeffs;

  const _MachineToLocalTransform({
    required this.xCoeffs,
    required this.yCoeffs,
  });

  Offset localFromMachine(double x, double y) {
    return Offset(
      xCoeffs[0] + xCoeffs[1] * x + xCoeffs[2] * y,
      yCoeffs[0] + yCoeffs[1] * x + yCoeffs[2] * y,
    );
  }
}

class _LocalToMachineTransform {
  final List<double> xCoeffs;
  final List<double> yCoeffs;

  const _LocalToMachineTransform({
    required this.xCoeffs,
    required this.yCoeffs,
  });

  Offset machineFromLocal(double x, double y) {
    return Offset(
      xCoeffs[0] + xCoeffs[1] * x + xCoeffs[2] * y,
      yCoeffs[0] + yCoeffs[1] * x + yCoeffs[2] * y,
    );
  }
}

class _PolylineSample {
  final Offset point;
  final int segmentIndex;
  final bool isControlPoint;

  const _PolylineSample({
    required this.point,
    required this.segmentIndex,
    required this.isControlPoint,
  });
}

class _TrajectoryVerificationPoint {
  final String id;
  final String label;
  final _SurfaceToolPoint point;
  final int polylineIndex;
  final int segmentIndex;
  final String endpoint;
  final String pointType;
  final int priority;
  final int trajectoryIndex;
  final double nearestDistanceMm;
  final bool matchesGeneratedTrajectory;

  const _TrajectoryVerificationPoint({
    required this.id,
    required this.label,
    required this.point,
    required this.polylineIndex,
    required this.segmentIndex,
    required this.endpoint,
    required this.pointType,
    required this.priority,
    required this.trajectoryIndex,
    required this.nearestDistanceMm,
    required this.matchesGeneratedTrajectory,
  });

  _TrajectoryVerificationPoint copyWith({String? id}) {
    return _TrajectoryVerificationPoint(
      id: id ?? this.id,
      label: label,
      point: point,
      polylineIndex: polylineIndex,
      segmentIndex: segmentIndex,
      endpoint: endpoint,
      pointType: pointType,
      priority: priority,
      trajectoryIndex: trajectoryIndex,
      nearestDistanceMm: nearestDistanceMm,
      matchesGeneratedTrajectory: matchesGeneratedTrajectory,
    );
  }
}

class _SurfaceTrajectoryStats {
  final double minZ;
  final double maxZ;

  const _SurfaceTrajectoryStats({required this.minZ, required this.maxZ});

  factory _SurfaceTrajectoryStats.fromPoints(List<_SurfaceToolPoint> points) {
    if (points.isEmpty) {
      return const _SurfaceTrajectoryStats(minZ: 0, maxZ: 0);
    }
    var minZ = double.infinity;
    var maxZ = -double.infinity;
    for (final point in points) {
      minZ = math.min(minZ, point.machineZ);
      maxZ = math.max(maxZ, point.machineZ);
    }
    return _SurfaceTrajectoryStats(minZ: minZ, maxZ: maxZ);
  }
}

enum _PresetView { iso, top, front, side }

enum _AlignmentHandleId {
  topLeft('top_left', '左上角'),
  topCenter('top_center', '上边中点'),
  topRight('top_right', '右上角'),
  centerRight('center_right', '右边中点'),
  bottomRight('bottom_right', '右下角'),
  bottomCenter('bottom_center', '下边中点'),
  bottomLeft('bottom_left', '左下角'),
  centerLeft('center_left', '左边中点');

  final String id;
  final String label;

  const _AlignmentHandleId(this.id, this.label);
}

enum _ContactFace {
  xMin('x_min', 'X- bed face'),
  xMax('x_max', 'X+ bed face'),
  yMin('y_min', 'Y- bed face'),
  yMax('y_max', 'Y+ bed face'),
  zMin('z_min', 'Z- bed face'),
  zMax('z_max', 'Z+ bed face');

  final String id;
  final String label;

  const _ContactFace(this.id, this.label);
}

enum _ModelAxis {
  x('X'),
  negX('-X'),
  y('Y'),
  negY('-Y'),
  z('Z'),
  negZ('-Z');

  final String label;

  const _ModelAxis(this.label);
}

class _ProjectionBasis {
  final _ModelAxis uAxis;
  final _ModelAxis vAxis;
  final _ModelAxis heightAxis;

  const _ProjectionBasis({
    required this.uAxis,
    required this.vAxis,
    required this.heightAxis,
  });

  factory _ProjectionBasis.fromContactFace(_ContactFace face) {
    return switch (face) {
      _ContactFace.zMin => const _ProjectionBasis(
        uAxis: _ModelAxis.x,
        vAxis: _ModelAxis.y,
        heightAxis: _ModelAxis.z,
      ),
      _ContactFace.zMax => const _ProjectionBasis(
        uAxis: _ModelAxis.x,
        vAxis: _ModelAxis.negY,
        heightAxis: _ModelAxis.negZ,
      ),
      _ContactFace.xMin => const _ProjectionBasis(
        uAxis: _ModelAxis.y,
        vAxis: _ModelAxis.z,
        heightAxis: _ModelAxis.x,
      ),
      _ContactFace.xMax => const _ProjectionBasis(
        uAxis: _ModelAxis.y,
        vAxis: _ModelAxis.negZ,
        heightAxis: _ModelAxis.negX,
      ),
      _ContactFace.yMin => const _ProjectionBasis(
        uAxis: _ModelAxis.z,
        vAxis: _ModelAxis.x,
        heightAxis: _ModelAxis.y,
      ),
      _ContactFace.yMax => const _ProjectionBasis(
        uAxis: _ModelAxis.x,
        vAxis: _ModelAxis.z,
        heightAxis: _ModelAxis.negY,
      ),
    };
  }

  Offset project(StlVector3 point) {
    return Offset(_axisValue(point, uAxis), _axisValue(point, vAxis));
  }

  StlVector3 projectNormal(StlVector3 normal) => StlVector3(
    _axisValue(normal, uAxis),
    _axisValue(normal, vAxis),
    _axisValue(normal, heightAxis),
  ).normalized();

  Size projectedSize(StlBounds bounds) {
    return Size(maxU(bounds) - minU(bounds), maxV(bounds) - minV(bounds));
  }

  double minU(StlBounds bounds) => _axisMin(bounds, uAxis);

  double maxU(StlBounds bounds) => _axisMax(bounds, uAxis);

  double minV(StlBounds bounds) => _axisMin(bounds, vAxis);

  double maxV(StlBounds bounds) => _axisMax(bounds, vAxis);

  double heightValue(StlVector3 point) => _axisValue(point, heightAxis);

  double minHeight(StlBounds bounds) => _axisMin(bounds, heightAxis);

  double maxHeight(StlBounds bounds) => _axisMax(bounds, heightAxis);

  StlVector3 offsetAlong(StlVector3 origin, _ModelAxis axis, double distance) {
    return switch (axis) {
      _ModelAxis.x => StlVector3(origin.x + distance, origin.y, origin.z),
      _ModelAxis.negX => StlVector3(origin.x - distance, origin.y, origin.z),
      _ModelAxis.y => StlVector3(origin.x, origin.y + distance, origin.z),
      _ModelAxis.negY => StlVector3(origin.x, origin.y - distance, origin.z),
      _ModelAxis.z => StlVector3(origin.x, origin.y, origin.z + distance),
      _ModelAxis.negZ => StlVector3(origin.x, origin.y, origin.z - distance),
    };
  }

  StlVector3 pointOnProjectionPlane(StlBounds bounds, double u, double v) {
    var point = bounds.center;
    point = _withAxisValue(point, uAxis, u);
    point = _withAxisValue(point, vAxis, v);
    return point;
  }

  double _axisValue(StlVector3 point, _ModelAxis axis) {
    return switch (axis) {
      _ModelAxis.x => point.x,
      _ModelAxis.negX => -point.x,
      _ModelAxis.y => point.y,
      _ModelAxis.negY => -point.y,
      _ModelAxis.z => point.z,
      _ModelAxis.negZ => -point.z,
    };
  }

  double _axisMin(StlBounds bounds, _ModelAxis axis) {
    return switch (axis) {
      _ModelAxis.x => bounds.minX,
      _ModelAxis.negX => -bounds.maxX,
      _ModelAxis.y => bounds.minY,
      _ModelAxis.negY => -bounds.maxY,
      _ModelAxis.z => bounds.minZ,
      _ModelAxis.negZ => -bounds.maxZ,
    };
  }

  double _axisMax(StlBounds bounds, _ModelAxis axis) {
    return switch (axis) {
      _ModelAxis.x => bounds.maxX,
      _ModelAxis.negX => -bounds.minX,
      _ModelAxis.y => bounds.maxY,
      _ModelAxis.negY => -bounds.minY,
      _ModelAxis.z => bounds.maxZ,
      _ModelAxis.negZ => -bounds.minZ,
    };
  }

  StlVector3 _withAxisValue(StlVector3 point, _ModelAxis axis, double value) {
    return switch (axis) {
      _ModelAxis.x => StlVector3(value, point.y, point.z),
      _ModelAxis.negX => StlVector3(-value, point.y, point.z),
      _ModelAxis.y => StlVector3(point.x, value, point.z),
      _ModelAxis.negY => StlVector3(point.x, -value, point.z),
      _ModelAxis.z => StlVector3(point.x, point.y, value),
      _ModelAxis.negZ => StlVector3(point.x, point.y, -value),
    };
  }
}
