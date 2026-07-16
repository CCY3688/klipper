import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ParameterCalibrationController extends ChangeNotifier {
  static const _kWorkspacePath = 'parameter_calibration_workspace_path';
  static const _kPythonExecutable = 'parameter_calibration_python_executable';
  static const _kMoonrakerUrl = 'parameter_calibration_moonraker_url';
  static const _kSnapshotUrl = 'parameter_calibration_snapshot_url';
  static const _kIntrinsicsPath = 'parameter_calibration_intrinsics_path';
  static const _kZsafe = 'parameter_calibration_zsafe';
  static const _kMoveDistance = 'parameter_calibration_move_distance';
  static const _kRepeats = 'parameter_calibration_repeats';
  static const _kFeedrate = 'parameter_calibration_feedrate';
  static const _kSettleSeconds = 'parameter_calibration_settle_seconds';
  static const _kTagId = 'parameter_calibration_tag_id';
  static const _kTagSize = 'parameter_calibration_tag_size';
  static const _kHomeAndClear = 'parameter_calibration_home_and_clear';
  static const _kCharucoClearX = 'parameter_calibration_charuco_clear_x';
  static const _kCharucoClearY = 'parameter_calibration_charuco_clear_y';
  static const _kCharucoClearZ = 'parameter_calibration_charuco_clear_z';
  static const _kStage2XMin = 'parameter_calibration_stage2_x_min';
  static const _kStage2XMax = 'parameter_calibration_stage2_x_max';
  static const _kStage2YMin = 'parameter_calibration_stage2_y_min';
  static const _kStage2YMax = 'parameter_calibration_stage2_y_max';
  static const _kStage2XCount = 'parameter_calibration_stage2_x_count';
  static const _kStage2YCount = 'parameter_calibration_stage2_y_count';
  static const _kStage2ZLevels = 'parameter_calibration_stage2_z_levels';
  static const _kGearRatio = 'parameter_calibration_gear_ratio';
  static const _kStage4XyModel = 'parameter_calibration_stage4_xy_model';
  static const _kStage4ZModel = 'parameter_calibration_stage4_z_model';
  static const _kStage4HoldoutXCount =
      'parameter_calibration_stage4_holdout_x_count';
  static const _kStage4HoldoutYCount =
      'parameter_calibration_stage4_holdout_y_count';
  static const _kStage4HoldoutZLevels =
      'parameter_calibration_stage4_holdout_z_levels';

  String _workspacePath = Directory.current.path;
  String _pythonExecutable = 'python';
  String _moonrakerUrl = 'http://192.168.67.182';
  String _snapshotUrl = 'http://127.0.0.1:8765/snapshot';
  String _intrinsicsPath = '';
  double _zsafe = 75.0;
  double _moveDistance = 40.0;
  int _repeats = 1;
  double _feedrate = 3000.0;
  double _settleSeconds = 1.0;
  int _tagId = 0;
  double _tagSize = 20.0;
  bool _homeAndClear = true;
  double _charucoClearX = -60.0;
  double _charucoClearY = -120.0;
  double _charucoClearZ = 76.0;
  double _stage2XMin = -40.0;
  double _stage2XMax = 40.0;
  double _stage2YMin = -40.0;
  double _stage2YMax = 40.0;
  int _stage2XCount = 3;
  int _stage2YCount = 3;
  String _stage2ZLevels = '55,65,75';
  String _gearRatio = '50:20';
  String _stage4XyModel = 'affine';
  String _stage4ZModel = 'offset';
  int _stage4HoldoutXCount = 5;
  int _stage4HoldoutYCount = 5;
  String _stage4HoldoutZLevels = '60,70';

  bool _busy = false;
  Process? _process;
  int? _lastExitCode;
  String? _lastError;
  Map<String, dynamic>? _latestCharucoResult;
  String? _latestCharucoResultPath;
  String? _latestCharucoOverlayPath;
  Map<String, dynamic>? _latestResult;
  String? _latestResultPath;
  String? _latestSamplesPath;
  String? _latestOverlayPath;
  String? _latestPhotoOverlayPath;
  String? _latestSummaryPath;
  Map<String, dynamic>? _latestStage2Result;
  String? _latestStage2ResultPath;
  String? _latestStage2SamplesPath;
  String? _latestStage2SummaryPath;
  String? _latestStage2ContactSheetPath;
  String? _latestStage2OverlayPath;
  Map<String, dynamic>? _latestStage4Result;
  String? _latestStage4ResultPath;
  String? _latestStage4SummaryPath;
  Map<String, dynamic>? _latestStage4ValidationResult;
  String? _latestStage4ValidationResultPath;
  String? _latestStage4ValidationSamplesPath;
  String? _latestStage4ValidationSummaryPath;
  String? _latestStage4ValidationContactSheetPath;
  String? _latestStage4ValidationOverlayPath;
  Map<String, dynamic>? _latestStage4HoldoutResult;
  String? _latestStage4HoldoutResultPath;
  String? _latestStage4HoldoutSamplesPath;
  String? _latestStage4HoldoutSummaryPath;
  String? _latestStage4HoldoutContactSheetPath;
  String? _latestStage4HoldoutOverlayPath;
  final List<String> _logLines = <String>[];

  ParameterCalibrationController() {
    _load();
  }

  String get workspacePath => _workspacePath;
  String get pythonExecutable => _pythonExecutable;
  String get moonrakerUrl => _moonrakerUrl;
  String get snapshotUrl => _snapshotUrl;
  String get intrinsicsPath =>
      _intrinsicsPath.trim().isEmpty ? defaultIntrinsicsPath : _intrinsicsPath;
  double get zsafe => _zsafe;
  double get moveDistance => _moveDistance;
  int get repeats => _repeats;
  double get feedrate => _feedrate;
  double get settleSeconds => _settleSeconds;
  int get tagId => _tagId;
  double get tagSize => _tagSize;
  bool get homeAndClear => _homeAndClear;
  double get charucoClearX => _charucoClearX;
  double get charucoClearY => _charucoClearY;
  double get charucoClearZ => _charucoClearZ;
  double get stage2XMin => _stage2XMin;
  double get stage2XMax => _stage2XMax;
  double get stage2YMin => _stage2YMin;
  double get stage2YMax => _stage2YMax;
  int get stage2XCount => _stage2XCount;
  int get stage2YCount => _stage2YCount;
  String get stage2ZLevels => _stage2ZLevels;
  String get gearRatio => _gearRatio;
  String get stage4XyModel => _stage4XyModel;
  String get stage4ZModel => _stage4ZModel;
  int get stage4HoldoutXCount => _stage4HoldoutXCount;
  int get stage4HoldoutYCount => _stage4HoldoutYCount;
  String get stage4HoldoutZLevels => _stage4HoldoutZLevels;
  bool get busy => _busy;
  int? get lastExitCode => _lastExitCode;
  String? get lastError => _lastError;
  Map<String, dynamic>? get latestCharucoResult => _latestCharucoResult;
  String? get latestCharucoResultPath => _latestCharucoResultPath;
  String? get latestCharucoOverlayPath => _latestCharucoOverlayPath;
  Map<String, dynamic>? get latestResult => _latestResult;
  String? get latestResultPath => _latestResultPath;
  String? get latestSamplesPath => _latestSamplesPath;
  String? get latestOverlayPath => _latestOverlayPath;
  String? get latestPhotoOverlayPath => _latestPhotoOverlayPath;
  String? get latestSummaryPath => _latestSummaryPath;
  Map<String, dynamic>? get latestStage2Result => _latestStage2Result;
  String? get latestStage2ResultPath => _latestStage2ResultPath;
  String? get latestStage2SamplesPath => _latestStage2SamplesPath;
  String? get latestStage2SummaryPath => _latestStage2SummaryPath;
  String? get latestStage2ContactSheetPath => _latestStage2ContactSheetPath;
  String? get latestStage2OverlayPath => _latestStage2OverlayPath;
  Map<String, dynamic>? get latestStage4Result => _latestStage4Result;
  String? get latestStage4ResultPath => _latestStage4ResultPath;
  String? get latestStage4SummaryPath => _latestStage4SummaryPath;
  Map<String, dynamic>? get latestStage4ValidationResult =>
      _latestStage4ValidationResult;
  String? get latestStage4ValidationResultPath =>
      _latestStage4ValidationResultPath;
  String? get latestStage4ValidationSamplesPath =>
      _latestStage4ValidationSamplesPath;
  String? get latestStage4ValidationSummaryPath =>
      _latestStage4ValidationSummaryPath;
  String? get latestStage4ValidationContactSheetPath =>
      _latestStage4ValidationContactSheetPath;
  String? get latestStage4ValidationOverlayPath =>
      _latestStage4ValidationOverlayPath;
  Map<String, dynamic>? get latestStage4HoldoutResult =>
      _latestStage4HoldoutResult;
  String? get latestStage4HoldoutResultPath => _latestStage4HoldoutResultPath;
  String? get latestStage4HoldoutSamplesPath => _latestStage4HoldoutSamplesPath;
  String? get latestStage4HoldoutSummaryPath => _latestStage4HoldoutSummaryPath;
  String? get latestStage4HoldoutContactSheetPath =>
      _latestStage4HoldoutContactSheetPath;
  String? get latestStage4HoldoutOverlayPath => _latestStage4HoldoutOverlayPath;
  List<String> get logLines => List.unmodifiable(_logLines);

  String get _visualDir => '$_workspacePath${Platform.pathSeparator}02_visual';
  String get _stage0Dir =>
      '$_visualDir${Platform.pathSeparator}stage0_machine_frame';
  String get _stage0Script =>
      '$_visualDir${Platform.pathSeparator}stage0_machine_frame.py';
  String get _stage2Dir =>
      '$_visualDir${Platform.pathSeparator}stage2_error_grid';
  String get _stage2Script =>
      '$_visualDir${Platform.pathSeparator}stage2_error_grid.py';
  String get _stage4Dir =>
      '$_visualDir${Platform.pathSeparator}stage4_coordinate_fit';
  String get _stage4ValidationDir =>
      '$_visualDir${Platform.pathSeparator}stage4_coordinate_fit_validation';
  String get _stage4HoldoutDir =>
      '$_visualDir${Platform.pathSeparator}stage4_coordinate_fit_holdout_validation';
  String get _stage4Script =>
      '$_visualDir${Platform.pathSeparator}stage4_coordinate_fit.py';
  String get _latestTransform =>
      '$_visualDir${Platform.pathSeparator}T_machine_from_board_initial.json';
  String get _latestStage2 =>
      '$_visualDir${Platform.pathSeparator}stage2_error_grid_latest.json';
  String get _latestStage4 =>
      '$_visualDir${Platform.pathSeparator}stage4_coordinate_fit_latest.json';
  String get _latestStage4Validation =>
      '$_visualDir${Platform.pathSeparator}stage4_coordinate_fit_validation_latest.json';
  String get _latestStage4Holdout =>
      '$_visualDir${Platform.pathSeparator}stage4_coordinate_fit_holdout_validation_latest.json';
  String get _charucoExtrinsic =>
      '$_visualDir${Platform.pathSeparator}charuco_manual_extrinsic_latest.json';
  String get _stage0Transform =>
      '$_stage0Dir${Platform.pathSeparator}T_machine_from_board_initial.json';
  String get _samplesCsv =>
      '$_stage0Dir${Platform.pathSeparator}machine_frame_samples.csv';
  String get _stage2SamplesCsv =>
      '$_stage2Dir${Platform.pathSeparator}stage2_error_grid_samples.csv';
  String get _stage4ResultJson =>
      '$_stage4Dir${Platform.pathSeparator}stage4_coordinate_fit_result.json';
  String get _stage4ValidationSamplesCsv =>
      '$_stage4ValidationDir${Platform.pathSeparator}stage2_error_grid_samples.csv';
  String get _stage4ValidationResultJson =>
      '$_stage4ValidationDir${Platform.pathSeparator}stage2_error_grid_result.json';
  String get _stage4HoldoutSamplesCsv =>
      '$_stage4HoldoutDir${Platform.pathSeparator}stage2_error_grid_samples.csv';
  String get _stage4HoldoutResultJson =>
      '$_stage4HoldoutDir${Platform.pathSeparator}stage2_error_grid_result.json';
  String get defaultIntrinsicsPath =>
      '$_workspacePath${Platform.pathSeparator}02_visual${Platform.pathSeparator}摄像头内参${Platform.pathSeparator}camera_calibration_results.json';

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    _workspacePath = sp.getString(_kWorkspacePath) ?? _workspacePath;
    _pythonExecutable = sp.getString(_kPythonExecutable) ?? _pythonExecutable;
    _moonrakerUrl = sp.getString(_kMoonrakerUrl) ?? _moonrakerUrl;
    _snapshotUrl = sp.getString(_kSnapshotUrl) ?? _snapshotUrl;
    _intrinsicsPath = sp.getString(_kIntrinsicsPath) ?? _intrinsicsPath;
    _zsafe = sp.getDouble(_kZsafe) ?? _zsafe;
    _moveDistance = sp.getDouble(_kMoveDistance) ?? _moveDistance;
    _repeats = sp.getInt(_kRepeats) ?? _repeats;
    _feedrate = sp.getDouble(_kFeedrate) ?? _feedrate;
    _settleSeconds = sp.getDouble(_kSettleSeconds) ?? _settleSeconds;
    _tagId = sp.getInt(_kTagId) ?? _tagId;
    _tagSize = sp.getDouble(_kTagSize) ?? _tagSize;
    _homeAndClear = sp.getBool(_kHomeAndClear) ?? _homeAndClear;
    _charucoClearX = sp.getDouble(_kCharucoClearX) ?? _charucoClearX;
    _charucoClearY = sp.getDouble(_kCharucoClearY) ?? _charucoClearY;
    _charucoClearZ = sp.getDouble(_kCharucoClearZ) ?? _charucoClearZ;
    _stage2XMin = sp.getDouble(_kStage2XMin) ?? _stage2XMin;
    _stage2XMax = sp.getDouble(_kStage2XMax) ?? _stage2XMax;
    _stage2YMin = sp.getDouble(_kStage2YMin) ?? _stage2YMin;
    _stage2YMax = sp.getDouble(_kStage2YMax) ?? _stage2YMax;
    _stage2XCount = sp.getInt(_kStage2XCount) ?? _stage2XCount;
    _stage2YCount = sp.getInt(_kStage2YCount) ?? _stage2YCount;
    _stage2ZLevels = sp.getString(_kStage2ZLevels) ?? _stage2ZLevels;
    _gearRatio = sp.getString(_kGearRatio) ?? _gearRatio;
    _stage4XyModel = sp.getString(_kStage4XyModel) ?? _stage4XyModel;
    _stage4ZModel = sp.getString(_kStage4ZModel) ?? _stage4ZModel;
    _stage4HoldoutXCount =
        sp.getInt(_kStage4HoldoutXCount) ?? _stage4HoldoutXCount;
    _stage4HoldoutYCount =
        sp.getInt(_kStage4HoldoutYCount) ?? _stage4HoldoutYCount;
    _stage4HoldoutZLevels =
        sp.getString(_kStage4HoldoutZLevels) ?? _stage4HoldoutZLevels;
    await loadLatestResult();
    notifyListeners();
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kWorkspacePath, _workspacePath);
    await sp.setString(_kPythonExecutable, _pythonExecutable);
    await sp.setString(_kMoonrakerUrl, _moonrakerUrl);
    await sp.setString(_kSnapshotUrl, _snapshotUrl);
    await sp.setString(_kIntrinsicsPath, _intrinsicsPath);
    await sp.setDouble(_kZsafe, _zsafe);
    await sp.setDouble(_kMoveDistance, _moveDistance);
    await sp.setInt(_kRepeats, _repeats);
    await sp.setDouble(_kFeedrate, _feedrate);
    await sp.setDouble(_kSettleSeconds, _settleSeconds);
    await sp.setInt(_kTagId, _tagId);
    await sp.setDouble(_kTagSize, _tagSize);
    await sp.setBool(_kHomeAndClear, _homeAndClear);
    await sp.setDouble(_kCharucoClearX, _charucoClearX);
    await sp.setDouble(_kCharucoClearY, _charucoClearY);
    await sp.setDouble(_kCharucoClearZ, _charucoClearZ);
    await sp.setDouble(_kStage2XMin, _stage2XMin);
    await sp.setDouble(_kStage2XMax, _stage2XMax);
    await sp.setDouble(_kStage2YMin, _stage2YMin);
    await sp.setDouble(_kStage2YMax, _stage2YMax);
    await sp.setInt(_kStage2XCount, _stage2XCount);
    await sp.setInt(_kStage2YCount, _stage2YCount);
    await sp.setString(_kStage2ZLevels, _stage2ZLevels);
    await sp.setString(_kGearRatio, _gearRatio);
    await sp.setString(_kStage4XyModel, _stage4XyModel);
    await sp.setString(_kStage4ZModel, _stage4ZModel);
    await sp.setInt(_kStage4HoldoutXCount, _stage4HoldoutXCount);
    await sp.setInt(_kStage4HoldoutYCount, _stage4HoldoutYCount);
    await sp.setString(_kStage4HoldoutZLevels, _stage4HoldoutZLevels);
  }

  void setWorkspacePath(String value) {
    final next = value.trim();
    if (next.isEmpty || next == _workspacePath) return;
    _workspacePath = next;
    _save();
    loadLatestResult();
    notifyListeners();
  }

  void setPythonExecutable(String value) {
    final next = value.trim().isEmpty ? 'python' : value.trim();
    if (next == _pythonExecutable) return;
    _pythonExecutable = next;
    _save();
    notifyListeners();
  }

  void setMoonrakerUrl(String value) {
    final next = value.trim().isEmpty ? 'http://192.168.67.182' : value.trim();
    if (next == _moonrakerUrl) return;
    _moonrakerUrl = next;
    _save();
    notifyListeners();
  }

  void setSnapshotUrl(String value) {
    final next = value.trim().isEmpty
        ? 'http://127.0.0.1:8765/snapshot'
        : value.trim();
    if (next == _snapshotUrl) return;
    _snapshotUrl = next;
    _save();
    notifyListeners();
  }

  void setIntrinsicsPath(String value) {
    final next = value.trim();
    if (next == _intrinsicsPath) return;
    _intrinsicsPath = next;
    _save();
    notifyListeners();
  }

  void resetIntrinsicsPath() {
    if (_intrinsicsPath.isEmpty) return;
    _intrinsicsPath = '';
    _save();
    notifyListeners();
  }

  void setZsafe(double value) => _setDouble((v) => _zsafe = v, value, 1, 300);
  void setMoveDistance(double value) =>
      _setDouble((v) => _moveDistance = v, value, 1, 120);
  void setFeedrate(double value) =>
      _setDouble((v) => _feedrate = v, value, 100, 12000);
  void setSettleSeconds(double value) =>
      _setDouble((v) => _settleSeconds = v, value, 0, 10);
  void setTagSize(double value) =>
      _setDouble((v) => _tagSize = v, value, 1, 200);

  void setRepeats(int value) {
    final next = value.clamp(1, 20);
    if (next == _repeats) return;
    _repeats = next;
    _save();
    notifyListeners();
  }

  void setTagId(int value) {
    if (value == _tagId) return;
    _tagId = value;
    _save();
    notifyListeners();
  }

  void setHomeAndClear(bool value) {
    if (value == _homeAndClear) return;
    _homeAndClear = value;
    _save();
    notifyListeners();
  }

  void setCharucoClearX(double value) =>
      _setDouble((v) => _charucoClearX = v, value, -300, 300);
  void setCharucoClearY(double value) =>
      _setDouble((v) => _charucoClearY = v, value, -300, 300);
  void setCharucoClearZ(double value) =>
      _setDouble((v) => _charucoClearZ = v, value, 0, 300);
  void setStage2XMin(double value) =>
      _setDouble((v) => _stage2XMin = v, value, -300, 300);
  void setStage2XMax(double value) =>
      _setDouble((v) => _stage2XMax = v, value, -300, 300);
  void setStage2YMin(double value) =>
      _setDouble((v) => _stage2YMin = v, value, -300, 300);
  void setStage2YMax(double value) =>
      _setDouble((v) => _stage2YMax = v, value, -300, 300);

  void setStage2XCount(int value) {
    final next = value.clamp(1, 15);
    if (next == _stage2XCount) return;
    _stage2XCount = next;
    _save();
    notifyListeners();
  }

  void setStage2YCount(int value) {
    final next = value.clamp(1, 15);
    if (next == _stage2YCount) return;
    _stage2YCount = next;
    _save();
    notifyListeners();
  }

  void setStage2ZLevels(String value) {
    final next = value.trim().isEmpty ? '55,65,75' : value.trim();
    if (next == _stage2ZLevels) return;
    _stage2ZLevels = next;
    _save();
    notifyListeners();
  }

  void setGearRatio(String value) {
    final next = value.trim().isEmpty ? '50:20' : value.trim();
    if (next == _gearRatio) return;
    _gearRatio = next;
    _save();
    notifyListeners();
  }

  void setStage4XyModel(String value) {
    final next = value == 'affine' ? 'affine' : 'rigid';
    if (next == _stage4XyModel) return;
    _stage4XyModel = next;
    _save();
    notifyListeners();
  }

  void setStage4ZModel(String value) {
    final next = switch (value) {
      'plane' => 'plane',
      'none' => 'none',
      _ => 'offset',
    };
    if (next == _stage4ZModel) return;
    _stage4ZModel = next;
    _save();
    notifyListeners();
  }

  void setStage4HoldoutXCount(int value) {
    final next = value.clamp(1, 40).toInt();
    if (next == _stage4HoldoutXCount) return;
    _stage4HoldoutXCount = next;
    _save();
    notifyListeners();
  }

  void setStage4HoldoutYCount(int value) {
    final next = value.clamp(1, 40).toInt();
    if (next == _stage4HoldoutYCount) return;
    _stage4HoldoutYCount = next;
    _save();
    notifyListeners();
  }

  void setStage4HoldoutZLevels(String value) {
    final next = value.trim().isEmpty ? '60,70' : value.trim();
    if (next == _stage4HoldoutZLevels) return;
    _stage4HoldoutZLevels = next;
    _save();
    notifyListeners();
  }

  void _setDouble(
    void Function(double value) assign,
    double value,
    double min,
    double max,
  ) {
    final next = value.clamp(min, max).toDouble();
    assign(next);
    _save();
    notifyListeners();
  }

  Future<void> dryRunStage0() {
    return _runStage0(<String>['collect', ..._collectArgs(execute: false)]);
  }

  Future<void> collectStage0() {
    return _runStage0(<String>['collect', ..._collectArgs(execute: true)]);
  }

  Future<void> estimateStage0() {
    return _runStage0(<String>[
      'estimate',
      '--samples',
      _samplesCsv,
      '--output',
      _stage0Transform,
      '--intrinsics',
      intrinsicsPath,
      '--board-origin',
      'center',
    ]);
  }

  Future<void> dryRunStage2() {
    return _runStage2(<String>['collect', ..._stage2Args(execute: false)]);
  }

  Future<void> collectStage2() {
    return _runStage2(<String>['collect', ..._stage2Args(execute: true)]);
  }

  Future<void> summarizeStage2() {
    return _runStage2(<String>[
      'summarize',
      '--samples',
      _stage2SamplesCsv,
      '--output',
      '$_stage2Dir${Platform.pathSeparator}stage2_error_grid_result.json',
    ]);
  }

  Future<void> fitStage4Coordinate() {
    return _runStage4(<String>[
      '--samples',
      _stage2SamplesCsv,
      '--initial-transform',
      _latestTransform,
      '--output',
      _stage4ResultJson,
      '--xy-model',
      _stage4XyModel,
      '--xy-handedness',
      'initial',
      '--z-model',
      _stage4ZModel,
    ]);
  }

  Future<void> dryRunStage4Validation() async {
    if (!await _ensureLatestStage4AffineResult()) return;
    return _runStage2(<String>[
      'collect',
      ..._stage2Args(
        execute: false,
        machineTransform: _latestStage4,
        outputDir: _stage4ValidationDir,
        latestOutput: _latestStage4Validation,
      ),
    ]);
  }

  Future<void> collectStage4Validation() async {
    if (!await _ensureLatestStage4AffineResult()) return;
    return _runStage2(<String>[
      'collect',
      ..._stage2Args(
        execute: true,
        machineTransform: _latestStage4,
        outputDir: _stage4ValidationDir,
        latestOutput: _latestStage4Validation,
      ),
    ]);
  }

  Future<void> summarizeStage4Validation() {
    return _runStage2(<String>[
      'summarize',
      '--samples',
      _stage4ValidationSamplesCsv,
      '--output',
      _stage4ValidationResultJson,
      '--latest-output',
      _latestStage4Validation,
    ]);
  }

  Future<void> dryRunStage4HoldoutValidation() async {
    if (!await _ensureLatestStage4AffineResult()) return;
    return _runStage2(<String>[
      'collect',
      ..._stage2Args(
        execute: false,
        xCount: _stage4HoldoutXCount,
        yCount: _stage4HoldoutYCount,
        zLevels: _stage4HoldoutZLevels,
        machineTransform: _latestStage4,
        outputDir: _stage4HoldoutDir,
        latestOutput: _latestStage4Holdout,
      ),
    ]);
  }

  Future<void> collectStage4HoldoutValidation() async {
    if (!await _ensureLatestStage4AffineResult()) return;
    return _runStage2(<String>[
      'collect',
      ..._stage2Args(
        execute: true,
        xCount: _stage4HoldoutXCount,
        yCount: _stage4HoldoutYCount,
        zLevels: _stage4HoldoutZLevels,
        machineTransform: _latestStage4,
        outputDir: _stage4HoldoutDir,
        latestOutput: _latestStage4Holdout,
      ),
    ]);
  }

  Future<void> summarizeStage4HoldoutValidation() {
    return _runStage2(<String>[
      'summarize',
      '--samples',
      _stage4HoldoutSamplesCsv,
      '--output',
      _stage4HoldoutResultJson,
      '--latest-output',
      _latestStage4Holdout,
    ]);
  }

  Future<bool> _ensureLatestStage4AffineResult() async {
    final file = File(_latestStage4);
    if (!file.existsSync()) {
      _lastError = '请先用仿射模型执行第4阶段拟合';
      _appendLogLine('ERROR: $_lastError');
      notifyListeners();
      return false;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['xy_model'] != 'affine') {
        _lastError = '当前第4阶段结果不是仿射模型，请先选择“仿射”并重新拟合';
        _appendLogLine('ERROR: $_lastError');
        notifyListeners();
        return false;
      }
      if (decoded['T_machine_from_board_up'] == null) {
        _lastError = '当前第4阶段结果缺少验证扫描所需矩阵，请重新执行仿射拟合';
        _appendLogLine('ERROR: $_lastError');
        notifyListeners();
        return false;
      }
      return true;
    } catch (e) {
      _lastError = '读取第4阶段仿射结果失败: $e';
      _appendLogLine('ERROR: $_lastError');
      notifyListeners();
      return false;
    }
  }

  Future<void> moveToCharucoClearPose({required bool homeFirst}) async {
    final script = <String>[
      if (homeFirst) 'EMM_HOME_AND_CLEAR',
      'G90',
      'G1 X${_charucoClearX.toStringAsFixed(3)} '
          'Y${_charucoClearY.toStringAsFixed(3)} '
          'Z${_charucoClearZ.toStringAsFixed(3)} '
          'F${_feedrate.toStringAsFixed(1)}',
      'M400',
    ].join('\n');
    return _runMoonrakerAction(
      label: homeFirst ? '回零并移动到 ChArUco 避让位' : '移动到 ChArUco 避让位',
      script: script,
      timeout: const Duration(seconds: 90),
    );
  }

  List<String> _collectArgs({required bool execute}) {
    return <String>[
      if (execute) '--execute',
      if (execute && _homeAndClear) '--home-and-clear',
      '--zsafe',
      _zsafe.toStringAsFixed(3),
      '--distance',
      _moveDistance.toStringAsFixed(3),
      '--repeats',
      '$_repeats',
      '--feedrate',
      _feedrate.toStringAsFixed(1),
      '--settle-s',
      _settleSeconds.toStringAsFixed(2),
      '--moonraker-url',
      _moonrakerUrl,
      '--snapshot-url',
      _snapshotUrl,
      '--intrinsics',
      intrinsicsPath,
      '--board-origin',
      'center',
      '--output-dir',
      _stage0Dir,
      '--tag-id',
      '$_tagId',
      '--tag-size',
      _tagSize.toStringAsFixed(3),
    ];
  }

  List<String> _stage2Args({
    required bool execute,
    int? xCount,
    int? yCount,
    String? zLevels,
    String? machineTransform,
    String? outputDir,
    String? latestOutput,
  }) {
    return <String>[
      if (execute) '--execute',
      if (execute && _homeAndClear) '--home-and-clear',
      '--x-min',
      _stage2XMin.toStringAsFixed(3),
      '--x-max',
      _stage2XMax.toStringAsFixed(3),
      '--y-min',
      _stage2YMin.toStringAsFixed(3),
      '--y-max',
      _stage2YMax.toStringAsFixed(3),
      '--x-count',
      '${xCount ?? _stage2XCount}',
      '--y-count',
      '${yCount ?? _stage2YCount}',
      '--z-levels',
      zLevels ?? _stage2ZLevels,
      '--repeats',
      '$_repeats',
      '--feedrate',
      _feedrate.toStringAsFixed(1),
      '--settle-s',
      _settleSeconds.toStringAsFixed(2),
      '--moonraker-url',
      _moonrakerUrl,
      '--snapshot-url',
      _snapshotUrl,
      '--intrinsics',
      intrinsicsPath,
      '--charuco-extrinsic',
      _charucoExtrinsic,
      '--machine-transform',
      machineTransform ?? _latestTransform,
      '--board-origin',
      'center',
      '--output-dir',
      outputDir ?? _stage2Dir,
      '--latest-output',
      latestOutput ?? _latestStage2,
      '--tag-id',
      '$_tagId',
      '--tag-size',
      _tagSize.toStringAsFixed(3),
      '--gear-ratio',
      _gearRatio,
    ];
  }

  Future<void> _runStage0(List<String> scriptArgs) async {
    if (_busy) return;
    await _save();

    _busy = true;
    _lastExitCode = null;
    _lastError = null;
    _logLines
      ..clear()
      ..add('> $_pythonExecutable $_stage0Script ${scriptArgs.join(' ')}');
    notifyListeners();

    try {
      final script = File(_stage0Script);
      if (!script.existsSync()) {
        throw FileSystemException('未找到第0阶段脚本', _stage0Script);
      }
      if (scriptArgs.contains('collect') &&
          !File(intrinsicsPath).existsSync()) {
        throw FileSystemException('未找到相机内参文件', intrinsicsPath);
      }

      final process = await Process.start(
        _pythonExecutable,
        <String>[_stage0Script, ...scriptArgs],
        workingDirectory: _workspacePath,
        runInShell: true,
      );
      _process = process;
      final stdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_appendLogLine);
      final stderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _appendLogLine('ERR: $line'));

      final exitCode = await process.exitCode;
      await stdoutSub.cancel();
      await stderrSub.cancel();
      _lastExitCode = exitCode;
      _appendLogLine('进程已退出，退出码 $exitCode');
      if (exitCode != 0) {
        _lastError = 'Python 进程异常退出，退出码 $exitCode';
      }
      await loadLatestResult();
    } catch (e) {
      _lastError = e.toString();
      _appendLogLine('ERROR: $_lastError');
    } finally {
      _process = null;
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _runStage2(List<String> scriptArgs) async {
    if (_busy) return;
    await _save();

    _busy = true;
    _lastExitCode = null;
    _lastError = null;
    _logLines
      ..clear()
      ..add('> $_pythonExecutable $_stage2Script ${scriptArgs.join(' ')}');
    notifyListeners();

    try {
      final script = File(_stage2Script);
      if (!script.existsSync()) {
        throw FileSystemException('未找到第2阶段脚本', _stage2Script);
      }
      if (scriptArgs.contains('collect')) {
        if (!File(intrinsicsPath).existsSync()) {
          throw FileSystemException('未找到相机内参文件', intrinsicsPath);
        }
        if (!File(_charucoExtrinsic).existsSync()) {
          throw FileSystemException('未找到 ChArUco 外参文件', _charucoExtrinsic);
        }
        final transformPath =
            _argValue(scriptArgs, '--machine-transform') ?? _latestTransform;
        if (!File(transformPath).existsSync()) {
          throw FileSystemException('未找到坐标系结果', transformPath);
        }
      }

      final process = await Process.start(
        _pythonExecutable,
        <String>[_stage2Script, ...scriptArgs],
        workingDirectory: _workspacePath,
        runInShell: true,
      );
      _process = process;
      final stdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_appendLogLine);
      final stderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _appendLogLine('ERR: $line'));

      final exitCode = await process.exitCode;
      await stdoutSub.cancel();
      await stderrSub.cancel();
      _lastExitCode = exitCode;
      _appendLogLine('进程已退出，退出码 $exitCode');
      if (exitCode != 0) {
        _lastError = 'Python 进程异常退出，退出码 $exitCode';
      }
      await loadLatestResult();
    } catch (e) {
      _lastError = e.toString();
      _appendLogLine('ERROR: $_lastError');
    } finally {
      _process = null;
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _runStage4(List<String> scriptArgs) async {
    if (_busy) return;
    await _save();

    _busy = true;
    _lastExitCode = null;
    _lastError = null;
    _logLines
      ..clear()
      ..add('> $_pythonExecutable $_stage4Script ${scriptArgs.join(' ')}');
    notifyListeners();

    try {
      final script = File(_stage4Script);
      if (!script.existsSync()) {
        throw FileSystemException('未找到第4阶段脚本', _stage4Script);
      }
      if (!File(_stage2SamplesCsv).existsSync()) {
        throw FileSystemException('未找到第2阶段采样 CSV', _stage2SamplesCsv);
      }
      if (!File(_latestTransform).existsSync()) {
        throw FileSystemException('未找到初始坐标系结果', _latestTransform);
      }

      final process = await Process.start(
        _pythonExecutable,
        <String>[_stage4Script, ...scriptArgs],
        workingDirectory: _workspacePath,
        runInShell: true,
      );
      _process = process;
      final stdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_appendLogLine);
      final stderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _appendLogLine('ERR: $line'));

      final exitCode = await process.exitCode;
      await stdoutSub.cancel();
      await stderrSub.cancel();
      _lastExitCode = exitCode;
      _appendLogLine('进程已退出，退出码 $exitCode');
      if (exitCode != 0) {
        _lastError = 'Python 进程异常退出，退出码 $exitCode';
      }
      await loadLatestResult();
    } catch (e) {
      _lastError = e.toString();
      _appendLogLine('ERROR: $_lastError');
    } finally {
      _process = null;
      _busy = false;
      notifyListeners();
    }
  }

  String? _argValue(List<String> args, String key) {
    final index = args.indexOf(key);
    if (index < 0 || index + 1 >= args.length) return null;
    return args[index + 1];
  }

  Future<void> _runMoonrakerAction({
    required String label,
    required String script,
    required Duration timeout,
  }) async {
    if (_busy) return;
    await _save();

    _busy = true;
    _lastExitCode = null;
    _lastError = null;
    _logLines
      ..clear()
      ..add('> Moonraker: $label')
      ..add(script);
    notifyListeners();

    try {
      await _postMoonrakerGcode(script, timeout: timeout);
      _lastExitCode = 0;
      _appendLogLine('Moonraker 指令执行完成');
    } catch (e) {
      _lastExitCode = 1;
      _lastError = e.toString();
      _appendLogLine('ERROR: $_lastError');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _postMoonrakerGcode(
    String script, {
    required Duration timeout,
  }) async {
    final base = Uri.parse(_moonrakerUrl);
    final uri = base.replace(path: '/printer/gcode/script', query: null);
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(<String, String>{'script': script}));
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        var message = text;
        try {
          final decoded = jsonDecode(text);
          if (decoded is Map && decoded['error'] is Map) {
            final error = decoded['error'] as Map;
            message = error['message']?.toString() ?? message;
          }
        } catch (_) {
          // Keep the raw response text when Moonraker returns non-JSON errors.
        }
        throw HttpException(
          'Moonraker 返回 ${response.statusCode}: $message',
          uri: uri,
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  void stopCurrentTask() {
    final process = _process;
    if (process == null) return;
    final killed = process.kill(ProcessSignal.sigterm);
    _appendLogLine(killed ? '已请求停止。' : '停止请求失败。');
  }

  Future<void> loadLatestResult() async {
    _latestCharucoResultPath = null;
    _latestCharucoResult = null;
    _latestCharucoOverlayPath = null;
    _latestResultPath = null;
    _latestResult = null;
    _latestSummaryPath = null;
    _latestPhotoOverlayPath = null;
    _latestStage2ResultPath = null;
    _latestStage2Result = null;
    _latestStage2SamplesPath = null;
    _latestStage2SummaryPath = null;
    _latestStage2ContactSheetPath = null;
    _latestStage2OverlayPath = null;
    _latestStage4ResultPath = null;
    _latestStage4Result = null;
    _latestStage4SummaryPath = null;
    _latestStage4ValidationResultPath = null;
    _latestStage4ValidationResult = null;
    _latestStage4ValidationSamplesPath = null;
    _latestStage4ValidationSummaryPath = null;
    _latestStage4ValidationContactSheetPath = null;
    _latestStage4ValidationOverlayPath = null;
    _latestStage4HoldoutResultPath = null;
    _latestStage4HoldoutResult = null;
    _latestStage4HoldoutSamplesPath = null;
    _latestStage4HoldoutSummaryPath = null;
    _latestStage4HoldoutContactSheetPath = null;
    _latestStage4HoldoutOverlayPath = null;

    final charuco = File(_charucoExtrinsic);
    if (charuco.existsSync()) {
      try {
        final decoded = jsonDecode(await charuco.readAsString());
        if (decoded is Map) {
          _latestCharucoResult = decoded.cast<String, dynamic>();
          _latestCharucoResultPath = charuco.path;
          final overlay =
              _latestCharucoResult?['overlay']?.toString() ??
              _latestCharucoResult?['overlay_image']?.toString();
          _latestCharucoOverlayPath = _resolveVisualArtifact(overlay);
        }
      } catch (e) {
        _lastError = '读取 ChArUco 外参结果失败: $e';
      }
    }

    final latest = File(_latestTransform);
    final stage0 = File(_stage0Transform);
    final source = latest.existsSync() ? latest : stage0;
    if (source.existsSync()) {
      try {
        final decoded = jsonDecode(await source.readAsString());
        if (decoded is Map) {
          _latestResult = decoded.cast<String, dynamic>();
          _latestResultPath = source.path;
          final summaryImage = _latestResult?['summary_image']?.toString();
          if (summaryImage != null && File(summaryImage).existsSync()) {
            _latestSummaryPath = summaryImage;
          }
          final photoOverlayImage = _latestResult?['photo_overlay_image']
              ?.toString();
          if (photoOverlayImage != null &&
              File(photoOverlayImage).existsSync()) {
            _latestPhotoOverlayPath = photoOverlayImage;
          }
        }
      } catch (e) {
        _lastError = '读取最新校准结果失败: $e';
      }
    }

    final samples = File(_samplesCsv);
    _latestSamplesPath = samples.existsSync() ? samples.path : null;
    _latestCharucoOverlayPath ??= _findCharucoOverlay();
    _latestPhotoOverlayPath ??= _findStage0PhotoOverlay();
    _latestSummaryPath ??= _findStage0Summary();
    _latestOverlayPath = _findNewestOverlay();

    final stage2Latest = File(_latestStage2);
    final stage2Result = File(
      '$_stage2Dir${Platform.pathSeparator}stage2_error_grid_result.json',
    );
    final stage2Source = stage2Latest.existsSync()
        ? stage2Latest
        : stage2Result;
    if (stage2Source.existsSync()) {
      try {
        final decoded = jsonDecode(await stage2Source.readAsString());
        if (decoded is Map) {
          _latestStage2Result = decoded.cast<String, dynamic>();
          _latestStage2ResultPath = stage2Source.path;
          _latestStage2SummaryPath = _resolveExistingPath(
            _latestStage2Result?['summary_image']?.toString(),
          );
          _latestStage2ContactSheetPath = _resolveExistingPath(
            _latestStage2Result?['capture_contact_sheet']?.toString(),
          );
        }
      } catch (e) {
        _lastError = '读取第2阶段结果失败: $e';
      }
    }
    final stage2Samples = File(_stage2SamplesCsv);
    _latestStage2SamplesPath = stage2Samples.existsSync()
        ? stage2Samples.path
        : null;
    _latestStage2SummaryPath ??= _findStage2Summary();
    _latestStage2ContactSheetPath ??= _findStage2ContactSheet();
    _latestStage2OverlayPath = _findNewestStage2Overlay();

    final stage4Latest = File(_latestStage4);
    final stage4Result = File(_stage4ResultJson);
    final stage4Source = stage4Latest.existsSync()
        ? stage4Latest
        : stage4Result;
    if (stage4Source.existsSync()) {
      try {
        final decoded = jsonDecode(await stage4Source.readAsString());
        if (decoded is Map) {
          _latestStage4Result = decoded.cast<String, dynamic>();
          _latestStage4ResultPath = stage4Source.path;
          _latestStage4SummaryPath = _resolveExistingPath(
            _latestStage4Result?['summary_image']?.toString(),
          );
        }
      } catch (e) {
        _lastError = '读取第4阶段结果失败: $e';
      }
    }
    _latestStage4SummaryPath ??= _findStage4Summary();

    final stage4ValidationLatest = File(_latestStage4Validation);
    final stage4ValidationResult = File(_stage4ValidationResultJson);
    final stage4ValidationSource = stage4ValidationLatest.existsSync()
        ? stage4ValidationLatest
        : stage4ValidationResult;
    if (stage4ValidationSource.existsSync()) {
      try {
        final decoded = jsonDecode(await stage4ValidationSource.readAsString());
        if (decoded is Map) {
          _latestStage4ValidationResult = decoded.cast<String, dynamic>();
          _latestStage4ValidationResultPath = stage4ValidationSource.path;
          _latestStage4ValidationSummaryPath = _resolveExistingPath(
            _latestStage4ValidationResult?['summary_image']?.toString(),
          );
          _latestStage4ValidationContactSheetPath = _resolveExistingPath(
            _latestStage4ValidationResult?['capture_contact_sheet']?.toString(),
          );
        }
      } catch (e) {
        _lastError = '读取第4阶段验证结果失败: $e';
      }
    }
    final stage4ValidationSamples = File(_stage4ValidationSamplesCsv);
    _latestStage4ValidationSamplesPath = stage4ValidationSamples.existsSync()
        ? stage4ValidationSamples.path
        : null;
    _latestStage4ValidationSummaryPath ??= _findStage4ValidationSummary();
    _latestStage4ValidationContactSheetPath ??=
        _findStage4ValidationContactSheet();
    _latestStage4ValidationOverlayPath = _findNewestStage4ValidationOverlay();

    final stage4HoldoutLatest = File(_latestStage4Holdout);
    final stage4HoldoutResult = File(_stage4HoldoutResultJson);
    final stage4HoldoutSource = stage4HoldoutLatest.existsSync()
        ? stage4HoldoutLatest
        : stage4HoldoutResult;
    if (stage4HoldoutSource.existsSync()) {
      try {
        final decoded = jsonDecode(await stage4HoldoutSource.readAsString());
        if (decoded is Map) {
          _latestStage4HoldoutResult = decoded.cast<String, dynamic>();
          _latestStage4HoldoutResultPath = stage4HoldoutSource.path;
          _latestStage4HoldoutSummaryPath = _resolveExistingPath(
            _latestStage4HoldoutResult?['summary_image']?.toString(),
          );
          _latestStage4HoldoutContactSheetPath = _resolveExistingPath(
            _latestStage4HoldoutResult?['capture_contact_sheet']?.toString(),
          );
        }
      } catch (e) {
        _lastError = '读取未标定平面验证结果失败: $e';
      }
    }
    final stage4HoldoutSamples = File(_stage4HoldoutSamplesCsv);
    _latestStage4HoldoutSamplesPath = stage4HoldoutSamples.existsSync()
        ? stage4HoldoutSamples.path
        : null;
    _latestStage4HoldoutSummaryPath ??= _findStage4HoldoutSummary();
    _latestStage4HoldoutContactSheetPath ??= _findStage4HoldoutContactSheet();
    _latestStage4HoldoutOverlayPath = _findNewestStage4HoldoutOverlay();
    notifyListeners();
  }

  String? _resolveExistingPath(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final direct = File(path);
    if (direct.existsSync()) return direct.path;
    return null;
  }

  String? _resolveVisualArtifact(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final direct = File(path);
    if (direct.isAbsolute && direct.existsSync()) return direct.path;
    if (direct.existsSync()) return direct.path;
    final relativeToVisual = File('$_visualDir${Platform.pathSeparator}$path');
    return relativeToVisual.existsSync() ? relativeToVisual.path : null;
  }

  String? _findCharucoOverlay() {
    final candidates = <String>[
      'charuco_manual_extrinsic_latest_overlay.jpg',
      'charuco_manual_extrinsic_overlay.jpg',
      'charuco_extrinsic_overlay.jpg',
    ];
    for (final name in candidates) {
      final file = File('$_visualDir${Platform.pathSeparator}$name');
      if (file.existsSync()) return file.path;
    }
    return null;
  }

  String? _findStage0PhotoOverlay() {
    final file = File(
      '$_stage0Dir${Platform.pathSeparator}stage0_photo_overlay.png',
    );
    return file.existsSync() ? file.path : null;
  }

  String? _findStage0Summary() {
    final file = File(
      '$_stage0Dir${Platform.pathSeparator}stage0_coordinate_summary.png',
    );
    return file.existsSync() ? file.path : null;
  }

  String? _findNewestOverlay() {
    final dir = Directory('$_stage0Dir${Platform.pathSeparator}overlays');
    if (!dir.existsSync()) return null;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.jpg'))
        .toList();
    if (files.isEmpty) return null;
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files.first.path;
  }

  String? _findStage2Summary() {
    final file = File(
      '$_stage2Dir${Platform.pathSeparator}stage2_error_grid_summary.png',
    );
    return file.existsSync() ? file.path : null;
  }

  String? _findStage2ContactSheet() {
    final file = File(
      '$_stage2Dir${Platform.pathSeparator}stage2_error_grid_contact_sheet.jpg',
    );
    return file.existsSync() ? file.path : null;
  }

  String? _findStage4Summary() {
    final file = File(
      '$_stage4Dir${Platform.pathSeparator}stage4_coordinate_fit_summary.png',
    );
    return file.existsSync() ? file.path : null;
  }

  String? _findStage4ValidationSummary() {
    final file = File(
      '$_stage4ValidationDir${Platform.pathSeparator}stage2_error_grid_summary.png',
    );
    return file.existsSync() ? file.path : null;
  }

  String? _findStage4ValidationContactSheet() {
    final file = File(
      '$_stage4ValidationDir${Platform.pathSeparator}stage2_error_grid_contact_sheet.jpg',
    );
    return file.existsSync() ? file.path : null;
  }

  String? _findStage4HoldoutSummary() {
    final file = File(
      '$_stage4HoldoutDir${Platform.pathSeparator}stage2_error_grid_summary.png',
    );
    return file.existsSync() ? file.path : null;
  }

  String? _findStage4HoldoutContactSheet() {
    final file = File(
      '$_stage4HoldoutDir${Platform.pathSeparator}stage2_error_grid_contact_sheet.jpg',
    );
    return file.existsSync() ? file.path : null;
  }

  String? _findNewestStage2Overlay() {
    final dir = Directory('$_stage2Dir${Platform.pathSeparator}overlays');
    if (!dir.existsSync()) return null;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.jpg'))
        .toList();
    if (files.isEmpty) return null;
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files.first.path;
  }

  String? _findNewestStage4ValidationOverlay() {
    final dir = Directory(
      '$_stage4ValidationDir${Platform.pathSeparator}overlays',
    );
    if (!dir.existsSync()) return null;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.jpg'))
        .toList();
    if (files.isEmpty) return null;
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files.first.path;
  }

  String? _findNewestStage4HoldoutOverlay() {
    final dir = Directory(
      '$_stage4HoldoutDir${Platform.pathSeparator}overlays',
    );
    if (!dir.existsSync()) return null;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.jpg'))
        .toList();
    if (files.isEmpty) return null;
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files.first.path;
  }

  void _appendLogLine(String line) {
    _logLines.add(line);
    if (_logLines.length > 500) {
      _logLines.removeRange(0, _logLines.length - 500);
    }
    notifyListeners();
  }

  void clearLog() {
    _logLines.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _process?.kill();
    super.dispose();
  }
}
