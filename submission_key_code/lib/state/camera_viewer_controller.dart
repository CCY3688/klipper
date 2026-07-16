import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CameraViewerController extends ChangeNotifier {
  static const defaultBaseUrl = 'http://127.0.0.1:8765';
  static const _kBaseUrl = 'camera_viewer_base_url';
  static const _kRefreshMs = 'camera_viewer_refresh_ms';
  static const _kAutoStart = 'camera_viewer_auto_start';
  static const _kPythonExecutable = 'camera_viewer_python_executable';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 2),
      receiveTimeout: const Duration(seconds: 10),
      responseType: ResponseType.bytes,
    ),
  );

  String _baseUrl = defaultBaseUrl;
  String _pythonExecutable = 'python';
  int _refreshMs = 500;
  bool _autoStart = false;
  bool _running = false;
  bool _serviceRunning = false;
  bool _serviceStarting = false;
  bool _loading = false;
  int _nonce = DateTime.now().microsecondsSinceEpoch;
  int _pendingNonce = 0;
  int _renderedNonce = 0;
  Uint8List? _frameBytes;
  DateTime? _lastFrameAt;
  String? _lastError;
  String? _serviceError;
  Process? _serviceProcess;
  Timer? _timer;
  Timer? _serviceProbeTimer;
  StreamSubscription<String>? _serviceStdoutSub;
  StreamSubscription<String>? _serviceStderrSub;

  CameraViewerController() {
    _load();
  }

  String get baseUrl => _baseUrl;
  String get pythonExecutable => _pythonExecutable;
  int get refreshMs => _refreshMs;
  bool get autoStart => _autoStart;
  bool get running => _running;
  bool get serviceRunning => _serviceRunning;
  bool get serviceStarting => _serviceStarting;
  bool get loading => _loading;
  int get nonce => _nonce;
  Uint8List? get frameBytes => _frameBytes;
  DateTime? get lastFrameAt => _lastFrameAt;
  String? get lastError => _lastError;
  String? get serviceError => _serviceError;
  String get normalizedBaseUrl => _normalizeBaseUrl();
  String get cameraServiceScript =>
      '${Directory.current.path}${Platform.pathSeparator}host${Platform.pathSeparator}camera_viewer.py';

  String get snapshotUrl => '${_normalizeBaseUrl()}/snapshot?t=$_nonce';
  String get streamUrl => '${_normalizeBaseUrl()}/stream';

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    _baseUrl = sp.getString(_kBaseUrl) ?? _baseUrl;
    _pythonExecutable = sp.getString(_kPythonExecutable) ?? _pythonExecutable;
    _refreshMs = sp.getInt(_kRefreshMs) ?? _refreshMs;
    _autoStart = sp.getBool(_kAutoStart) ?? _autoStart;
    notifyListeners();
    unawaited(probeService());
    if (_autoStart) {
      start();
    }
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kBaseUrl, _baseUrl);
    await sp.setString(_kPythonExecutable, _pythonExecutable);
    await sp.setInt(_kRefreshMs, _refreshMs);
    await sp.setBool(_kAutoStart, _autoStart);
  }

  String _normalizeBaseUrl() {
    final raw = _baseUrl.trim();
    if (raw.isEmpty) return defaultBaseUrl;
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw.replaceAll(RegExp(r'/*$'), '');
    }
    return 'http://$raw'.replaceAll(RegExp(r'/*$'), '');
  }

  void setBaseUrl(String value) {
    final normalized = value.trim().isEmpty ? defaultBaseUrl : value.trim();
    if (_baseUrl == normalized) return;
    _baseUrl = normalized;
    _lastError = null;
    notifyListeners();
    _save();
    if (_running) {
      _loading = false;
      refresh();
    }
  }

  void resetBaseUrl() {
    setBaseUrl(defaultBaseUrl);
  }

  void setPythonExecutable(String value) {
    final next = value.trim().isEmpty ? 'python' : value.trim();
    if (_pythonExecutable == next) return;
    _pythonExecutable = next;
    _serviceError = null;
    notifyListeners();
    _save();
  }

  void setRefreshMs(int value) {
    final next = value.clamp(100, 2000);
    if (_refreshMs == next) return;
    _refreshMs = next;
    notifyListeners();
    _save();
    if (_running) {
      _restartTimer();
    }
  }

  void setAutoStart(bool value) {
    if (_autoStart == value) return;
    _autoStart = value;
    notifyListeners();
    _save();
  }

  Future<void> startCameraService() async {
    if (_serviceStarting || _serviceProcess != null) return;
    await probeService();
    if (_serviceRunning) {
      return;
    }

    final script = File(cameraServiceScript);
    if (!script.existsSync()) {
      _serviceError = '未找到相机服务脚本：${script.path}';
      notifyListeners();
      return;
    }

    _serviceStarting = true;
    _serviceError = null;
    notifyListeners();

    try {
      final process = await Process.start(
        _pythonExecutable,
        <String>[script.path],
        workingDirectory: Directory.current.path,
        runInShell: true,
        mode: ProcessStartMode.normal,
      );
      _serviceProcess = process;
      _serviceStdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleServiceLog);
      _serviceStderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleServiceLog);
      unawaited(_watchServiceExit(process));
      _startServiceProbeTimer();

      final ok = await _waitForServiceReady();
      if (ok) {
        _serviceRunning = true;
        _serviceStarting = false;
        _serviceError = null;
      } else {
        _serviceStarting = false;
        _serviceError ??= '相机服务启动后仍未就绪，请查看 Python 输出';
      }
    } catch (error) {
      _serviceStarting = false;
      _serviceRunning = false;
      _serviceError = '启动相机服务失败：$error';
    }
    notifyListeners();
  }

  Future<void> stopCameraService() async {
    stop();
    _serviceProbeTimer?.cancel();
    _serviceProbeTimer = null;
    final process = _serviceProcess;
    if (process != null) {
      process.kill(ProcessSignal.sigterm);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (_serviceProcess == process) {
        process.kill(ProcessSignal.sigkill);
      }
    }
    await _serviceStdoutSub?.cancel();
    await _serviceStderrSub?.cancel();
    _serviceStdoutSub = null;
    _serviceStderrSub = null;
    _serviceProcess = null;
    _serviceRunning = false;
    _serviceStarting = false;
    notifyListeners();
  }

  Future<void> probeService() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_normalizeBaseUrl()}/health',
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (status) => status != null && status < 600,
        ),
      );
      final payload = response.data;
      final online = payload != null && payload.containsKey('camera_name');
      final hasLiveFrame = response.statusCode == 200 && payload?['ok'] == true;
      _serviceRunning = online;
      if (hasLiveFrame) {
        _serviceError = null;
      } else {
        final remoteError = payload?['last_error']?.toString();
        _serviceError = remoteError == null || remoteError.isEmpty
            ? '相机服务在线，但没有新图像帧'
            : '相机流异常：$remoteError';
      }
    } catch (error) {
      _serviceRunning = false;
      if (!_serviceStarting) {
        _serviceError = _formatFetchError(error);
      }
    }
    notifyListeners();
  }

  void _startServiceProbeTimer() {
    _serviceProbeTimer?.cancel();
    _serviceProbeTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(probeService());
    });
  }

  Future<bool> _waitForServiceReady() async {
    for (var i = 0; i < 20; i += 1) {
      try {
        final response = await _dio.get<Map<String, dynamic>>(
          '${_normalizeBaseUrl()}/health',
          options: Options(
            responseType: ResponseType.json,
            validateStatus: (status) => status != null && status < 600,
          ),
        );
        if (response.data?.containsKey('camera_name') == true) {
          return true;
        }
      } catch (_) {
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    return false;
  }

  Future<void> _watchServiceExit(Process process) async {
    final exitCode = await process.exitCode;
    if (_serviceProcess != process) return;
    await _serviceStdoutSub?.cancel();
    await _serviceStderrSub?.cancel();
    _serviceStdoutSub = null;
    _serviceStderrSub = null;
    _serviceProcess = null;
    _serviceRunning = false;
    _serviceStarting = false;
    _serviceError ??= '相机服务已退出，退出码 $exitCode';
    notifyListeners();
  }

  void _handleServiceLog(String line) {
    if (line.trim().isEmpty) return;
    if (line.toLowerCase().contains('error') ||
        line.toLowerCase().contains('exception') ||
        line.contains('错误')) {
      _serviceError = line;
      notifyListeners();
    }
  }

  void start() {
    if (_running) return;
    _running = true;
    _lastError = null;
    refresh();
    _restartTimer();
    notifyListeners();
    _save();
  }

  void stop() {
    if (!_running) return;
    _timer?.cancel();
    _timer = null;
    _running = false;
    _loading = false;
    _pendingNonce = 0;
    notifyListeners();
    _save();
  }

  void refresh() {
    if (_loading) return;
    _nonce = DateTime.now().microsecondsSinceEpoch;
    _pendingNonce = _nonce;
    _loading = true;
    _lastError = null;
    notifyListeners();
    unawaited(_fetchSnapshot(_nonce));
  }

  Future<Uint8List> captureStill() async {
    final nonce = DateTime.now().microsecondsSinceEpoch;
    _nonce = nonce;
    _pendingNonce = nonce;
    _loading = true;
    _lastError = null;
    notifyListeners();

    try {
      final response = await _dio.get<List<int>>(
        '${_normalizeBaseUrl()}/snapshot',
        queryParameters: {'t': nonce, 'fresh': 1, 'timeout': 8.0},
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw StateError('相机服务返回了空图像');
      }

      final bytes = Uint8List.fromList(data);
      _frameBytes = bytes;
      _renderedNonce = nonce;
      _loading = false;
      _lastFrameAt = DateTime.now();
      _lastError = null;
      notifyListeners();
      return bytes;
    } catch (error) {
      _loading = false;
      _lastError = _formatFetchError(error);
      notifyListeners();
      throw StateError(_lastError ?? '取图失败');
    }
  }

  Future<void> _fetchSnapshot(int nonce) async {
    try {
      final response = await _dio.get<List<int>>(
        '${_normalizeBaseUrl()}/snapshot',
        queryParameters: {'t': nonce, 'fresh': 1, 'timeout': 8.0},
        options: Options(responseType: ResponseType.bytes),
      );
      if (nonce != _pendingNonce) return;

      final data = response.data;
      if (data == null || data.isEmpty) {
        throw StateError('相机服务返回了空图像');
      }

      _frameBytes = Uint8List.fromList(data);
      _renderedNonce = nonce;
      _loading = false;
      _lastFrameAt = DateTime.now();
      _lastError = null;
      notifyListeners();
    } catch (error) {
      if (nonce != _pendingNonce) return;
      _loading = false;
      _lastError = _formatFetchError(error);
      notifyListeners();
    }
  }

  void markFrameRendered(int nonce) {
    if (nonce != _pendingNonce || _renderedNonce == nonce) return;
    _renderedNonce = nonce;
    _loading = false;
    _lastFrameAt = DateTime.now();
    _lastError = null;
    notifyListeners();
  }

  void markFrameError(int nonce, String error) {
    if (nonce != _pendingNonce) return;
    _loading = false;
    _lastError = error;
    notifyListeners();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(milliseconds: _refreshMs), (_) {
      if (_running && !_loading) {
        refresh();
      }
    });
  }

  String _formatFetchError(Object error) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      if (statusCode != null) {
        return '预览服务返回 HTTP $statusCode';
      }

      switch (error.type) {
        case DioExceptionType.connectionTimeout:
          return '连接预览服务超时，请确认 ${_normalizeBaseUrl()} 可访问';
        case DioExceptionType.receiveTimeout:
          return '等待相机图像超时，请检查远程摄像头或桥接服务';
        case DioExceptionType.connectionError:
          return '无法连接预览服务，请先启动 host/camera_viewer.py，并确认地址为 ${_normalizeBaseUrl()}';
        default:
          final message = error.message ?? error.error?.toString();
          return message == null || message.isEmpty ? '取图失败' : message;
      }
    }
    return error.toString();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _serviceProbeTimer?.cancel();
    _serviceStdoutSub?.cancel();
    _serviceStderrSub?.cancel();
    _serviceProcess?.kill();
    super.dispose();
  }
}
