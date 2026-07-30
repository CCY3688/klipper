import 'dart:async';
import 'package:flutter/foundation.dart';

import '../core/app_logger.dart';
import '../core/moonraker_config.dart';
import '../data/moonraker/moonraker_exception.dart';
import '../data/moonraker/moonraker_repository.dart';
import '../data/moonraker/moonraker_ws_service.dart';
import '../data/moonraker/moonraker_models.dart';

enum AppConnPhase {
  idle,
  connecting,
  connected,
  reconnecting,
  disconnected,
  error,
}

class GcodeUploadStartResult {
  const GcodeUploadStartResult({
    required this.remotePath,
    required this.uploaded,
    required this.started,
    this.error,
  });

  final String? remotePath;
  final bool uploaded;
  final bool started;
  final String? error;
}

class PrinterController extends ChangeNotifier {
  MoonrakerRepository? _repo;

  /// 暴露给 UI 层直接调用文件 API（只读引用）
  MoonrakerRepository? get repo => _repo;

  StreamSubscription? _wsMsgSub;
  StreamSubscription? _wsConnSub;

  Timer? _reconnectTimer;
  int _statusRefreshToken = 0;
  int _reconnectAttempt = 0;
  bool _shouldStayConnected = false;

  AppConnPhase phase = AppConnPhase.idle;
  String? lastError;

  // ====== 模型化后的状态 ======
  MoonrakerServerInfo? serverInfo;
  MoonrakerPrinterInfo? printerInfo;
  PrinterStatus status = PrinterStatus.empty;

  // ====== 订阅档位（Profile） ======
  StatusProfile profile = StatusProfile.basic;

  // logs (结构化)
  final AppLogger logger = AppLogger();
  int procStatNotifyCount = 0;
  bool klipperScreenRestarting = false;

  // ====== Tasks / Files (gcodes) ======
  bool gcodeFilesLoading = false;
  String? gcodeFilesError;
  List<MoonrakerFileItem> gcodeFiles = const [];

  // ====== 为了尽量不改 UI，保留一些 getter ======
  String get moonrakerVersion => serverInfo?.moonrakerVersion ?? '';
  String get klippyStateFromServerInfo => serverInfo?.klippyState ?? '';
  String get printerState => printerInfo?.state ?? '';

  // ====== Klippy 状态相关 getter（参考 Fluidd） ======
  /// Klippy 是否已就绪（klippy_connected 且 klippy_state == 'ready'）
  bool get klippyReady {
    final info = serverInfo;
    if (info == null) return false;
    return info.klippyConnected && info.klippyState == 'ready';
  }

  /// Klippy 是否已连接
  bool get klippyConnected => serverInfo?.klippyConnected ?? false;

  /// Klippy 状态（ready, startup, shutdown, error, disconnected）
  String get klippyState => serverInfo?.klippyState ?? 'disconnected';

  /// Klippy 状态消息（用于显示错误详情）
  String get klippyStateMessage {
    final info = serverInfo;
    if (info == null) return 'Not connected to Moonraker';

    // 如果 klippy 未连接
    if (!info.klippyConnected) {
      return 'Klippy not connected';
    }

    // 从 printerInfo 获取状态消息
    final msg = printerInfo?.stateMessage ?? '';
    if (msg.isNotEmpty) {
      return msg;
    }

    // 根据状态返回默认消息
    switch (info.klippyState) {
      case 'ready':
        return 'Printer is ready';
      case 'startup':
        return 'Klipper is starting up...';
      case 'shutdown':
        return 'Klipper has shutdown';
      case 'error':
        return 'Klipper error';
      default:
        return 'Unknown state: ${info.klippyState}';
    }
  }

  String get printState => status.printStats?.state ?? 'unknown';
  String get filename => status.printStats?.filename ?? '';
  double get progress => status.virtualSdcard?.progress ?? 0.0;
  bool get sdIsActive => status.virtualSdcard?.isActive ?? false;
  List<double>? get toolheadPosition => status.toolhead?.position;
  String? get homedAxes => status.toolhead?.homedAxes;

  /// Whether the printer has been homed (at least X, Y, Z axes)
  bool get isHomed {
    final axes = homedAxisSet;
    return axes.contains('x') && axes.contains('y') && axes.contains('z');
  }

  Set<String> get homedAxisSet => (homedAxes ?? '')
      .toLowerCase()
      .split('')
      .where((ch) => ch == 'x' || ch == 'y' || ch == 'z')
      .toSet();

  List<double>? get gcodePosition => status.gcodeMove?.gcodePosition;

  /// Best available current tool position for live display and origin setting.
  List<double>? get livePosition {
    final motion = status.motionReport?.livePosition;
    if (_hasUsablePosition(motion)) return motion;

    final toolhead = status.toolhead?.position;
    if (_hasUsablePosition(toolhead)) return toolhead;

    final gcode = status.gcodeMove?.gcodePosition;
    if (_hasUsablePosition(gcode)) return gcode;

    return motion ?? toolhead ?? gcode;
  }

  List<double>? get currentPosition => livePosition;

  bool _hasUsablePosition(List<double>? position) {
    if (position == null || position.length < 3) return false;
    return position.take(3).any((v) => v.abs() > 1e-9);
  }

  void _log(LogLevel level, String tag, String msg) {
    logger.log(level, tag, msg);
  }

  bool isConsoleLog(LogEntry entry) {
    if (entry.level == LogLevel.error || entry.level == LogLevel.warn) {
      return true;
    }
    return const {'GCODE', 'KLIPPER', 'CTRL', 'STATUS'}.contains(entry.tag);
  }

  List<LogEntry> get consoleEntries => logger.where(isConsoleLog);

  void clearConsole() {
    logger.clear();
    notifyListeners();
  }

  String exportConsoleText() => logger.exportWhere(isConsoleLog);

  Future<void> connect(
    MoonrakerConfig config, {
    StatusProfile profile = StatusProfile.basic,
  }) async {
    await disconnect();

    this.profile = profile;

    _shouldStayConnected = true;
    phase = AppConnPhase.connecting;
    lastError = null;
    notifyListeners();

    _repo = MoonrakerRepository(config);

    try {
      _log(
        LogLevel.info,
        'CTRL',
        'Connect start ${config.httpBaseUrl} profile=${profile.name}',
      );
      // HTTP -> 模型
      final si = await _repo!.fetchServerInfo();
      serverInfo = MoonrakerServerInfo.fromServerInfoResponse(si);

      final pi = await _repo!.fetchPrinterInfo();
      printerInfo = MoonrakerPrinterInfo.fromPrinterInfoResponse(pi);

      // WS connect + listen
      await _repo!.connectWs();
      _wsMsgSub = _repo!.wsMessages.listen(_handleWsMessage);
      _wsConnSub = _repo!.wsConnEvents.listen(_handleWsConnEvent);

      // subscribe -> 初始 status
      await _refreshSubscriptionAndStatus(_repo!, resubscribe: true);
      notifyListeners();

      phase = AppConnPhase.connected;
      _reconnectAttempt = 0;
      _log(LogLevel.info, 'CTRL', 'Connect ok');
      notifyListeners();
    } catch (e) {
      lastError = e.toString();
      phase = AppConnPhase.error;
      _log(LogLevel.error, 'CTRL', 'Connect failed: $lastError');
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _shouldStayConnected = false;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;

    await _wsMsgSub?.cancel();
    await _wsConnSub?.cancel();
    _wsMsgSub = null;
    _wsConnSub = null;

    final repo = _repo;
    _repo = null;
    if (repo != null) await repo.close();

    phase = AppConnPhase.disconnected;
    _log(LogLevel.info, 'CTRL', 'Disconnected');
    notifyListeners();
  }

  Future<void> sendTestGcode() async {
    final repo = _repo;
    if (repo == null) return;
    _log(LogLevel.info, 'GCODE', '> M115');
    notifyListeners();
    await repo.sendTestGcode();
    notifyListeners();
  }

  Future<String?> sendGcode(String script, {Duration? receiveTimeout}) async {
    final repo = _repo;
    if (repo == null) {
      lastError = 'Not connected to Moonraker';
      _log(LogLevel.error, 'CTRL', lastError!);
      notifyListeners();
      return lastError;
    }
    _log(LogLevel.info, 'GCODE', '> $script');
    notifyListeners();
    try {
      await repo.runGcodeScript(script, receiveTimeout: receiveTimeout);
    } catch (e) {
      final message = _friendlyGcodeError(e);
      lastError = message;
      _log(LogLevel.error, 'GCODE', message);
      notifyListeners();
      return message;
    }
    notifyListeners();
    return null;
  }

  Future<String?> restartKlipperScreen() async {
    final repo = _repo;
    if (repo == null) {
      lastError = 'Not connected to Moonraker';
      _log(LogLevel.error, 'CTRL', lastError!);
      notifyListeners();
      return lastError;
    }

    if (klipperScreenRestarting) return null;

    klipperScreenRestarting = true;
    lastError = null;
    _log(LogLevel.info, 'CTRL', 'Restart KlipperScreen service');
    notifyListeners();

    try {
      await repo.restartKlipperScreen();
      _log(LogLevel.info, 'CTRL', 'KlipperScreen restart command sent');
      return null;
    } catch (e) {
      final message = _friendlyMoonrakerError(e);
      lastError = message;
      _log(LogLevel.error, 'CTRL', message);
      return message;
    } finally {
      klipperScreenRestarting = false;
      notifyListeners();
    }
  }

  Future<String?> setLaserPower(double power, {double maxPower = 100}) {
    final range = maxPower <= 0 ? 100.0 : maxPower;
    final value = (power.clamp(0, range) / range).toDouble();
    final script = 'SET_PIN PIN=laser VALUE=${_fmtGcodeNumber(value)}';
    return sendGcode(script);
  }

  Future<String?> startSurfaceScan({
    required double xMin,
    required double xMax,
    required double yMin,
    required double yMax,
    required double spacing,
    required int samples,
    required double scanZ,
    String? profile,
    String result = 'median',
    String? sensor,
  }) async {
    final repo = _repo;
    if (repo == null) {
      lastError = 'Not connected to Moonraker';
      _log(LogLevel.error, 'CTRL', lastError!);
      notifyListeners();
      return lastError;
    }

    final parts = <String>[
      'SURFACE_SCAN',
      'AREA_MIN=${_fmtGcodeNumber(xMin)},${_fmtGcodeNumber(yMin)}',
      'AREA_MAX=${_fmtGcodeNumber(xMax)},${_fmtGcodeNumber(yMax)}',
      'SPACING=${_fmtGcodeNumber(spacing)}',
      'SAMPLES=$samples',
      'Z=${_fmtGcodeNumber(scanZ)}',
      'RESULT=${_sanitizeGcodeToken(result, fallback: 'median')}',
    ];

    final scanProfile = profile?.trim();
    if (scanProfile != null && scanProfile.isNotEmpty) {
      parts.add('PROFILE=${_sanitizeGcodeToken(scanProfile)}');
    }

    final scanSensor = sensor?.trim();
    if (scanSensor != null && scanSensor.isNotEmpty) {
      parts.add('SENSOR=${_sanitizeGcodeToken(scanSensor)}');
    }

    final script = parts.join(' ');
    _log(LogLevel.info, 'GCODE', '> $script');
    notifyListeners();
    try {
      await repo.runGcodeScript(
        script,
        receiveTimeout: const Duration(minutes: 30),
      );
    } catch (e) {
      final message = _friendlyGcodeError(e);
      lastError = message;
      _log(LogLevel.error, 'SURFACE', message);
      notifyListeners();
      return message;
    }

    notifyListeners();
    return null;
  }

  Future<Map<String, dynamic>?> fetchSurfaceScanList() async {
    final repo = _repo;
    if (repo == null) {
      lastError = '未连接到 Moonraker';
      notifyListeners();
      return null;
    }
    try {
      return await repo.fetchSurfaceScanList();
    } catch (e) {
      lastError = e.toString();
      _log(LogLevel.error, 'SURFACE', 'Scan list failed: $e');
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchSurfaceScan({String? profile}) async {
    final repo = _repo;
    if (repo == null) {
      lastError = '未连接到 Moonraker';
      notifyListeners();
      return null;
    }
    try {
      return await repo.fetchSurfaceScan(profile: profile);
    } catch (e) {
      lastError = e.toString();
      _log(LogLevel.error, 'SURFACE', 'Scan get failed: $e');
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchSurfaceScanProgress() async {
    final repo = _repo;
    if (repo == null) {
      lastError = '未连接到 Moonraker';
      notifyListeners();
      return null;
    }
    try {
      return await repo.fetchSurfaceScanProgress();
    } catch (e) {
      lastError = e.toString();
      _log(LogLevel.error, 'SURFACE', 'Scan progress failed: $e');
      notifyListeners();
      return null;
    }
  }

  String _fmtGcodeNumber(double value) {
    final text = value.toStringAsFixed(4);
    return text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _sanitizeGcodeToken(String value, {String fallback = 'surface'}) {
    final sanitized = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_');
    return sanitized.isEmpty ? fallback : sanitized;
  }

  String _friendlyGcodeError(Object error) {
    final raw = error is MoonrakerApiException
        ? error.message
        : error.toString();
    final firstLine = raw.split('\n').first.trim();
    if (firstLine.isEmpty) return '!! G-code command failed';
    if (firstLine.startsWith('!!')) return firstLine;
    return '!! $firstLine';
  }

  String _friendlyMoonrakerError(Object error) {
    final raw = error is MoonrakerApiException
        ? error.message
        : error.toString();
    final firstLine = raw.split('\n').first.trim();
    return firstLine.isEmpty ? 'Moonraker request failed' : firstLine;
  }

  Future<void> home([String? axis]) async {
    final script = axis == null ? 'G28' : 'G28 ${axis.toUpperCase()}';
    await sendGcode(script);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await refreshStatusSnapshot();
  }

  /// Queries the current status snapshot. Returns false when the query fails.
  Future<bool> refreshStatusSnapshot() async {
    final repo = _repo;
    if (repo == null) return false;

    try {
      final objects = await repo.buildSubscriptionObjects(profile);
      final snap = await repo.queryStatusSnapshot(objects);
      status = PrinterStatus.fromSnapshot(snap);
      _log(LogLevel.debug, 'STATUS', 'refreshed homed_axes=${homedAxes ?? ''}');
      notifyListeners();
      return true;
    } catch (e) {
      _log(LogLevel.error, 'STATUS', 'Refresh failed: $e');
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshGcodeFiles() async {
    final repo = _repo;
    if (repo == null) {
      gcodeFilesError = 'Not connected to Moonraker';
      notifyListeners();
      return;
    }

    gcodeFilesLoading = true;
    gcodeFilesError = null;
    notifyListeners();

    try {
      final files = await repo.listGcodeFiles(root: 'gcodes');
      // simple sort: newest first
      files.sort((a, b) => b.modified.compareTo(a.modified));
      gcodeFiles = files;
    } catch (e) {
      gcodeFilesError = e.toString();
    } finally {
      gcodeFilesLoading = false;
      notifyListeners();
    }
  }

  Future<bool> startPrintUploaded(String filenameOrPath) async {
    final repo = _repo;
    if (repo == null) {
      lastError = 'Not connected to Moonraker';
      notifyListeners();
      return false;
    }

    try {
      await repo.startPrintUploaded(filenameOrPath);
      return true;
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<GcodeUploadStartResult> uploadAndStartGcode({
    required String filename,
    required String gcode,
  }) async {
    final repo = _repo;
    if (repo == null) {
      lastError = 'Not connected to Moonraker';
      notifyListeners();
      return GcodeUploadStartResult(
        remotePath: null,
        uploaded: false,
        started: false,
        error: lastError,
      );
    }

    String remotePath;
    try {
      remotePath = await repo.uploadGcodeString(
        filename: filename,
        gcode: gcode,
      );
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
      return GcodeUploadStartResult(
        remotePath: null,
        uploaded: false,
        started: false,
        error: lastError,
      );
    }

    try {
      await repo.startPrintUploaded(remotePath);
      return GcodeUploadStartResult(
        remotePath: remotePath,
        uploaded: true,
        started: true,
      );
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
      return GcodeUploadStartResult(
        remotePath: remotePath,
        uploaded: true,
        started: false,
        error: lastError,
      );
    }
  }

  Future<String?> uploadGcode({
    required String filename,
    required String gcode,
    bool startAfterUpload = false,
  }) async {
    final repo = _repo;
    if (repo == null) {
      lastError = 'Not connected to Moonraker';
      notifyListeners();
      return null;
    }

    try {
      final remotePath = await repo.uploadGcodeString(
        filename: filename,
        gcode: gcode,
      );
      if (startAfterUpload) {
        await repo.startPrintUploaded(remotePath);
      }
      return remotePath;
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<bool> deleteGcodeFile(String filename) async {
    final repo = _repo;
    if (repo == null) {
      lastError = 'Not connected to Moonraker';
      notifyListeners();
      return false;
    }

    try {
      await repo.deleteGcodeFile(filename);
      // 成功后刷本地列表
      await refreshGcodeFiles();
      return true;
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ===== WS 事件处理 =====
  void _handleWsConnEvent(WsConnState ev) {
    if (!_shouldStayConnected) return;
    if (ev == WsConnState.disconnected || ev == WsConnState.error) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) return;

    phase = AppConnPhase.reconnecting;
    notifyListeners();

    final delaySec = _calcBackoffSeconds(_reconnectAttempt++);
    _log(LogLevel.warn, 'WS', 'disconnected, reconnect in ${delaySec}s...');
    notifyListeners();

    _reconnectTimer = Timer(Duration(seconds: delaySec), () async {
      _reconnectTimer = null;
      await _tryReconnect();
    });
  }

  int _calcBackoffSeconds(int attempt) {
    final v = 1 << attempt;
    return v > 30 ? 30 : v;
  }

  Future<void> _tryReconnect() async {
    if (!_shouldStayConnected) return;
    final repo = _repo;
    if (repo == null) return;

    try {
      await repo.connectWs();
      _wsMsgSub ??= repo.wsMessages.listen(_handleWsMessage);
      _wsConnSub ??= repo.wsConnEvents.listen(_handleWsConnEvent);

      await _refreshSubscriptionAndStatus(repo, resubscribe: true);
      notifyListeners();

      phase = AppConnPhase.connected;
      _reconnectAttempt = 0;
      _log(LogLevel.info, 'WS', 'Reconnected');
      notifyListeners();
    } catch (e) {
      lastError = e.toString();
      _log(LogLevel.error, 'WS', 'Reconnect failed: $lastError');
      _scheduleReconnect();
    }
  }

  void _handleWsMessage(Map<String, dynamic> msg) {
    final method = msg['method'];

    if (method == 'notify_proc_stat_update') {
      procStatNotifyCount++;
      return;
    }

    if (method == 'notify_gcode_response') {
      final params = msg['params'];
      final response = params is List && params.isNotEmpty
          ? params.first?.toString().trim()
          : null;
      if (response != null && response.isNotEmpty) {
        final level = response.startsWith('!!')
            ? LogLevel.error
            : LogLevel.info;
        _log(level, 'KLIPPER', response);
        notifyListeners();
      }
      return;
    }

    if (method == 'notify_status_update') {
      final params = msg['params'];
      if (params is List && params.isNotEmpty) {
        final delta = (params[0] as Map).cast<String, dynamic>();
        status = status.applyDelta(delta);
        notifyListeners();
      }
    }

    if (method == 'notify_klippy_ready' && serverInfo != null) {
      serverInfo = MoonrakerServerInfo(
        klippyConnected: true,
        klippyState: 'ready',
        moonrakerVersion: serverInfo!.moonrakerVersion,
        apiVersionString: serverInfo!.apiVersionString,
      );
      _log(LogLevel.info, 'WS', 'Klippy ready');
      notifyListeners();
      // 刷新 printerInfo 以获取最新状态
      refreshAllStatus();
    }

    if (method == 'notify_klippy_disconnected' && serverInfo != null) {
      serverInfo = MoonrakerServerInfo(
        klippyConnected: false,
        klippyState: 'disconnected',
        moonrakerVersion: serverInfo!.moonrakerVersion,
        apiVersionString: serverInfo!.apiVersionString,
      );
      printerInfo = null;
      status = PrinterStatus.empty;
      _log(LogLevel.warn, 'WS', 'Klippy disconnected');
      notifyListeners();
    }

    if (method == 'notify_klippy_shutdown' && serverInfo != null) {
      serverInfo = MoonrakerServerInfo(
        klippyConnected: serverInfo!.klippyConnected,
        klippyState: 'shutdown',
        moonrakerVersion: serverInfo!.moonrakerVersion,
        apiVersionString: serverInfo!.apiVersionString,
      );
      status = PrinterStatus.empty;
      _log(LogLevel.warn, 'WS', 'Klippy shutdown');
      notifyListeners();
      // 刷新服务器信息以获取最新状态（包括 state_message）
      refreshAllStatus();
    }
  }

  /// 刷新所有打印机状态（serverInfo, printerInfo, status）
  ///
  /// 在 klippy 重启后调用此方法强制刷新所有状态
  Future<void> refreshAllStatus() async {
    final repo = _repo;
    if (repo == null) {
      _log(LogLevel.warn, 'STATUS', 'Cannot refresh: not connected');
      return;
    }

    try {
      // 刷新 serverInfo 和 printerInfo
      final token = ++_statusRefreshToken;
      final si = await repo.fetchServerInfo();
      if (token != _statusRefreshToken) return;
      serverInfo = MoonrakerServerInfo.fromServerInfoResponse(si);

      if (serverInfo!.klippyConnected) {
        final pi = await repo.fetchPrinterInfo();
        if (token != _statusRefreshToken) return;
        printerInfo = MoonrakerPrinterInfo.fromPrinterInfoResponse(pi);

        // 刷新 status snapshot（包含 toolhead 位置）
        await _refreshSubscriptionAndStatus(repo, resubscribe: true);
      } else {
        printerInfo = null;
        status = PrinterStatus.empty;
      }

      _log(LogLevel.info, 'STATUS', 'All status refreshed successfully');
      notifyListeners();
    } catch (e) {
      _log(LogLevel.error, 'STATUS', 'Failed to refresh all status: $e');
      notifyListeners();
    }
  }

  /// 刷新 serverInfo 和 printerInfo
  Future<void> refreshServerAndPrinterInfo() async {
    final repo = _repo;
    if (repo == null) return;

    try {
      final si = await repo.fetchServerInfo();
      serverInfo = MoonrakerServerInfo.fromServerInfoResponse(si);

      // 只有在 klippy 连接时才获取 printerInfo
      if (serverInfo!.klippyConnected) {
        final pi = await repo.fetchPrinterInfo();
        printerInfo = MoonrakerPrinterInfo.fromPrinterInfoResponse(pi);
      }
      notifyListeners();
    } catch (e) {
      _log(LogLevel.error, 'CTRL', 'Failed to refresh info: $e');
    }
  }

  void _applySubscribeResult(Map<String, dynamic> subResp) {
    final result = (subResp['result'] as Map?)?.cast<String, dynamic>();
    final st = (result?['status'] as Map?)?.cast<String, dynamic>();
    if (st != null) {
      status = status.applyDelta(st);
    }
  }

  Future<void> _refreshSubscriptionAndStatus(
    MoonrakerRepository repo, {
    required bool resubscribe,
  }) async {
    final objects = await repo.buildSubscriptionObjects(profile);

    if (resubscribe && repo.ws.isConnected) {
      try {
        final subResp = await repo.ws.subscribe(objects);
        status = PrinterStatus.empty;
        _applySubscribeResult(subResp);
      } catch (e) {
        _log(LogLevel.warn, 'WS', 'Subscribe refresh failed: $e');
      }
    }

    final snap = await repo.queryStatusSnapshot(objects);
    status = PrinterStatus.fromSnapshot(snap);
  }
}
