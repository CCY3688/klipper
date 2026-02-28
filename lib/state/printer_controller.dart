import 'dart:async';
import 'package:flutter/foundation.dart';

import '../core/app_logger.dart';
import '../core/moonraker_config.dart';
import '../data/moonraker/moonraker_repository.dart';
import '../data/moonraker/moonraker_ws_service.dart';
import '../data/moonraker/moonraker_models.dart';

enum AppConnPhase { idle, connecting, connected, reconnecting, disconnected, error }

class PrinterController extends ChangeNotifier {
  MoonrakerRepository? _repo;

  /// 暴露给 UI 层直接调用文件 API（只读引用）
  MoonrakerRepository? get repo => _repo;

  StreamSubscription? _wsMsgSub;
  StreamSubscription? _wsConnSub;

  Timer? _reconnectTimer;
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
  List<double>? get gcodePosition => status.gcodeMove?.gcodePosition;

  void _log(LogLevel level, String tag, String msg) {
    logger.log(level, tag, msg);
  }

  Future<void> connect(MoonrakerConfig config, {StatusProfile profile = StatusProfile.basic}) async {
    await disconnect();

    this.profile = profile;

    _shouldStayConnected = true;
    phase = AppConnPhase.connecting;
    lastError = null;
    notifyListeners();

    _repo = MoonrakerRepository(config);

    try {
      _log(LogLevel.info, 'CTRL', 'Connect start ${config.httpBaseUrl} profile=${profile.name}');
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
      final objects = await _repo!.buildSubscriptionObjects(profile);
      final subResp = await _repo!.ws.subscribe(objects);
      _applySubscribeResult(subResp);
      final snap = await _repo!.queryStatusSnapshot(objects);
      status = PrinterStatus.fromSnapshot(snap);
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
    await repo.sendTestGcode();
    _log(LogLevel.info, 'HTTP', 'sent M115');
    notifyListeners();
  }

  Future<void> sendGcode(String script) async {
    final repo = _repo;
    if (repo == null) return;
    try {
      await repo.http.gcodeScript(script);
      _log(LogLevel.info, 'GCODE', '> $script');
    } catch (e) {
      _log(LogLevel.error, 'GCODE', 'Failed: $e');
    }
    // No notify needed for log update since log() does it? 
    // Wait, log() doesn't call notifyListeners() in AppLogger, 
    // but _log() in this file calls logger.log.
    // The previous implementation of _log just called logger.log.
    // We might need to notifyListeners() if the UI depends on 'notifyListeners' to redraw logs.
    // StatusPage listens to PrinterController. 
    // AppLogger is just a data holder. 
    // We need to trigger a rebuild when logs change.
    notifyListeners(); 
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
      final remotePath = await repo.uploadGcodeString(filename: filename, gcode: gcode);
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

      final objects = await repo.buildSubscriptionObjects(profile);
      final subResp = await repo.ws.subscribe(objects);
      _applySubscribeResult(subResp);
      final snap = await repo.queryStatusSnapshot(objects);
      status = PrinterStatus.fromSnapshot(snap);
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
      if (procStatNotifyCount % 50 == 0) {
        _log(LogLevel.debug, 'WS', 'notify_proc_stat_update x$procStatNotifyCount');
        notifyListeners();
      }
      return;
    }

    if (method is String) {
      _log(LogLevel.debug, 'WS', 'notify: $method');
    } else if (msg.containsKey('id')) {
      _log(LogLevel.debug, 'WS', 'response id=${msg['id']}');
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
      _refreshServerAndPrinterInfo();
    }

    if (method == 'notify_klippy_disconnected' && serverInfo != null) {
      serverInfo = MoonrakerServerInfo(
        klippyConnected: false,
        klippyState: 'disconnected',
        moonrakerVersion: serverInfo!.moonrakerVersion,
        apiVersionString: serverInfo!.apiVersionString,
      );
      printerInfo = null;
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
      _log(LogLevel.warn, 'WS', 'Klippy shutdown');
      notifyListeners();
      // 刷新服务器信息以获取最新状态（包括 state_message）
      _refreshServerAndPrinterInfo();
    }
  }

  /// 刷新 serverInfo 和 printerInfo
  Future<void> _refreshServerAndPrinterInfo() async {
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
}