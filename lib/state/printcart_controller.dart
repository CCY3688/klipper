import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/printcart/printcart_protocol.dart';
import '../data/printcart/printcart_serial_service.dart';

enum PrintcartConnectionPhase { disconnected, connecting, connected, error }

class PrintcartController extends ChangeNotifier {
  static const _healthStorageKey = 'printcart_nozzle_health_v1';
  static const _firmwareInitRetryInterval = Duration(milliseconds: 100);
  static const _firmwareInitTimeout = Duration(seconds: 3);

  final PrintcartTransport transport;
  StreamSubscription<String>? _eventSubscription;
  List<PrintcartPortInfo> ports = const [];
  String? selectedPort;
  String? firmwareIdentity;
  PrintcartStatus? status;
  PrintcartConnectionPhase phase = PrintcartConnectionPhase.disconnected;
  bool busy = false;
  String? errorMessage;
  final List<String> log = [];
  final Map<String, NozzleHealth> _health = {};

  PrintcartController({PrintcartTransport? transport})
    : transport = transport ?? PrintcartSerialService() {
    _eventSubscription = this.transport.events.listen(_handleEvent);
    _loadHealth();
  }

  bool get isConnected =>
      phase == PrintcartConnectionPhase.connected && transport.isConnected;

  bool get hasSafeFirmware {
    final identity = firmwareIdentity;
    if (identity == null) return false;
    final match = RegExp(r'ESP32S3-PRINTERCART\s+(\d+)').firstMatch(identity);
    return match != null && int.parse(match.group(1)!) >= 2;
  }

  bool get canFire => isConnected && hasSafeFirmware && !busy;

  NozzleHealth healthFor(PrintcartColor color, int nozzle) =>
      _health['${color.name}:$nozzle'] ?? NozzleHealth.unknown;

  int healthCount(PrintcartColor color, NozzleHealth health) =>
      Iterable<int>.generate(
        PrintcartFrame.nozzlesPerColor,
      ).where((nozzle) => healthFor(color, nozzle) == health).length;

  Future<void> refreshPorts() async {
    try {
      ports = await transport.listPorts();
      final detected = ports.where((port) => port.isEspressifUsbJtag);
      selectedPort = detected.isNotEmpty
          ? detected.first.name
          : (ports.any((port) => port.name == selectedPort)
                ? selectedPort
                : ports.firstOrNull?.name);
      errorMessage = null;
    } catch (error) {
      errorMessage = '串口枚举失败：$error';
    }
    notifyListeners();
  }

  void selectPort(String? value) {
    selectedPort = value;
    notifyListeners();
  }

  Future<void> connect() async {
    if (busy) return;
    if (ports.isEmpty) await refreshPorts();
    final port = selectedPort;
    if (port == null) {
      errorMessage = '未发现可用串口';
      phase = PrintcartConnectionPhase.error;
      notifyListeners();
      return;
    }

    busy = true;
    phase = PrintcartConnectionPhase.connecting;
    errorMessage = null;
    notifyListeners();
    try {
      await transport.connect(port);
      final reply = await _waitForReadyFirmware();
      firmwareIdentity = reply.startsWith('OK ') ? reply.substring(3) : reply;
      phase = PrintcartConnectionPhase.connected;
      _appendLog('RX $reply');
      if (hasSafeFirmware) {
        await refreshStatus();
      } else {
        errorMessage = '固件协议低于 v2，已锁定喷射；请刷写新版镜像';
      }
    } catch (error) {
      await transport.disconnect();
      phase = PrintcartConnectionPhase.error;
      errorMessage = '喷头连接失败：$error';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String> _waitForReadyFirmware() async {
    final deadline = DateTime.now().add(_firmwareInitTimeout);
    var reply = await transport.command('PING');

    while (_isFirmwareInitializing(reply) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_firmwareInitRetryInterval);
      reply = await transport.command('PING');
    }
    return reply;
  }

  bool _isFirmwareInitializing(String reply) =>
      reply.contains('ESP32S3-PRINTERCART 1 COLOR INIT');

  Future<void> refreshStatus() async {
    if (!isConnected) return;
    try {
      final reply = await transport.command('STATUS');
      status = PrintcartStatus.tryParse(reply);
      if (status == null) throw const FormatException('状态响应格式不匹配');
      _appendLog('RX $reply');
      errorMessage = null;
    } catch (error) {
      errorMessage = '读取喷头状态失败：$error';
    }
    notifyListeners();
  }

  Future<void> fireSingleNozzle({
    required PrintcartColor color,
    required int nozzle,
    required int repeats,
    required int intervalMs,
  }) async {
    if (!canFire) throw StateError('喷头未就绪或固件不满足安全要求');
    if (repeats < 1 || repeats > 10) {
      throw RangeError.range(repeats, 1, 10, 'repeats');
    }
    if (intervalMs < 50 || intervalMs > 2000) {
      throw RangeError.range(intervalMs, 50, 2000, 'intervalMs');
    }

    busy = true;
    errorMessage = null;
    notifyListeners();
    var hvArmed = false;
    try {
      final hvReply = await transport.command('HV ON');
      hvArmed = true;
      status = PrintcartStatus(
        highVoltageEnabled: true,
        cartridge: status?.cartridge ?? 'COLOR',
        frameBytes: PrintcartFrame.frameBytes,
        autoOffMs: status?.autoOffMs ?? 5000,
      );
      _appendLog('RX $hvReply');
      final command = PrintcartFrame.singleNozzleFireCommand(color, nozzle);
      for (var i = 0; i < repeats; i++) {
        final reply = await transport.command(command);
        _appendLog(
          'RX $reply ${color.shortLabel}#${nozzle + 1} (${i + 1}/$repeats)',
        );
        if (i + 1 < repeats) {
          await Future<void>.delayed(Duration(milliseconds: intervalMs));
        }
      }
    } catch (error) {
      errorMessage = '单喷嘴测试失败：$error';
      rethrow;
    } finally {
      if (hvArmed || transport.isConnected) {
        try {
          final reply = await transport.command(
            'OFF',
            timeout: const Duration(seconds: 1),
          );
          _appendLog('RX $reply');
        } catch (error) {
          _appendLog('WARN OFF $error');
        }
      }
      if (status != null) {
        status = PrintcartStatus(
          highVoltageEnabled: false,
          cartridge: status!.cartridge,
          frameBytes: status!.frameBytes,
          autoOffMs: status!.autoOffMs,
        );
      }
      busy = false;
      notifyListeners();
    }
  }

  Future<void> setHealth(
    PrintcartColor color,
    int nozzle,
    NozzleHealth health,
  ) async {
    _health['${color.name}:$nozzle'] = health;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _healthStorageKey,
      jsonEncode(_health.map((key, value) => MapEntry(key, value.name))),
    );
  }

  Future<void> clearHealth(PrintcartColor color) async {
    for (var nozzle = 0; nozzle < PrintcartFrame.nozzlesPerColor; nozzle++) {
      _health.remove('${color.name}:$nozzle');
    }
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _healthStorageKey,
      jsonEncode(_health.map((key, value) => MapEntry(key, value.name))),
    );
  }

  Future<void> _loadHealth() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_healthStorageKey);
    if (encoded == null) return;
    try {
      final values = (jsonDecode(encoded) as Map<String, dynamic>);
      for (final entry in values.entries) {
        _health[entry.key] = NozzleHealth.values.byName(entry.value as String);
      }
      notifyListeners();
    } catch (_) {
      // Ignore incompatible historical data.
    }
  }

  void _handleEvent(String line) {
    _appendLog('EVENT $line');
    if (line == 'EVENT HV AUTO_OFF' && status != null) {
      status = PrintcartStatus(
        highVoltageEnabled: false,
        cartridge: status!.cartridge,
        frameBytes: status!.frameBytes,
        autoOffMs: status!.autoOffMs,
      );
    }
    notifyListeners();
  }

  void _appendLog(String line) {
    log.insert(0, line);
    if (log.length > 40) log.removeLast();
  }

  Future<void> disconnect() async {
    await _shutdownTransport();
    phase = PrintcartConnectionPhase.disconnected;
    firmwareIdentity = null;
    status = null;
    errorMessage = null;
    busy = false;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_shutdownTransport());
    unawaited(_eventSubscription?.cancel());
    super.dispose();
  }

  Future<void> _shutdownTransport() async {
    if (transport.isConnected) {
      try {
        await transport.command('OFF', timeout: const Duration(seconds: 1));
      } catch (_) {}
    }
    await transport.disconnect();
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
