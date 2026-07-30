import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

class PrintcartPortInfo {
  final String name;
  final String? description;
  final int? vendorId;
  final int? productId;

  const PrintcartPortInfo({
    required this.name,
    this.description,
    this.vendorId,
    this.productId,
  });

  bool get isEspressifUsbJtag => vendorId == 0x303a && productId == 0x1001;
}

abstract class PrintcartTransport {
  bool get isConnected;
  Stream<String> get events;
  Future<List<PrintcartPortInfo>> listPorts();
  Future<void> connect(String portName);
  Future<String> command(
    String command, {
    Duration timeout = const Duration(seconds: 2),
  });
  Future<void> disconnect();
}

class PrintcartSerialService implements PrintcartTransport {
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _readerSubscription;
  final _events = StreamController<String>.broadcast();
  Completer<String>? _pendingReply;
  String _lineBuffer = '';

  @override
  bool get isConnected => _port?.isOpen ?? false;

  @override
  Stream<String> get events => _events.stream;

  @override
  Future<List<PrintcartPortInfo>> listPorts() async {
    return SerialPort.availablePorts.map((name) {
      final port = SerialPort(name);
      try {
        return PrintcartPortInfo(
          name: name,
          description: port.description ?? port.productName,
          vendorId: port.vendorId,
          productId: port.productId,
        );
      } finally {
        port.dispose();
      }
    }).toList();
  }

  @override
  Future<void> connect(String portName) async {
    await disconnect();
    final port = SerialPort(portName);
    if (!port.openReadWrite()) {
      final error = SerialPort.lastError?.message ?? '无法打开串口';
      port.dispose();
      throw StateError(error);
    }

    try {
      final config = SerialPortConfig()
        ..baudRate = 115200
        ..bits = 8
        ..stopBits = 1
        ..parity = SerialPortParity.none
        ..setFlowControl(SerialPortFlowControl.none);
      port.config = config;
      port.flush(SerialPortBuffer.both);
      _port = port;
      _reader = SerialPortReader(port, timeout: 100);
      _readerSubscription = _reader!.stream.listen(
        _onBytes,
        onError: (Object error) {
          _pendingReply?.completeError(error);
          _pendingReply = null;
          _events.add('ERR SERIAL $error');
        },
      );
    } catch (_) {
      port.close();
      port.dispose();
      rethrow;
    }
  }

  void _onBytes(Uint8List bytes) {
    _lineBuffer += ascii.decode(bytes, allowInvalid: true);
    while (true) {
      final newline = _lineBuffer.indexOf('\n');
      if (newline < 0) return;
      final line = _lineBuffer.substring(0, newline).trim();
      _lineBuffer = _lineBuffer.substring(newline + 1);
      if (line.isEmpty) continue;
      if ((line.startsWith('OK ') || line.startsWith('ERR ')) &&
          _pendingReply != null) {
        _pendingReply!.complete(line);
        _pendingReply = null;
      } else {
        _events.add(line);
      }
    }
  }

  @override
  Future<String> command(
    String command, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final port = _port;
    if (port == null || !port.isOpen) throw StateError('喷头控制器未连接');
    if (_pendingReply != null) throw StateError('上一条喷头命令尚未完成');

    final completer = Completer<String>();
    _pendingReply = completer;
    final bytes = Uint8List.fromList(ascii.encode('$command\n'));
    try {
      final written = port.write(bytes, timeout: 500);
      if (written != bytes.length) throw StateError('串口命令未完整写入');
      final reply = await completer.future.timeout(timeout);
      if (reply.startsWith('ERR ')) throw StateError(reply.substring(4));
      return reply;
    } finally {
      if (identical(_pendingReply, completer)) _pendingReply = null;
    }
  }

  @override
  Future<void> disconnect() async {
    _pendingReply?.completeError(StateError('串口已断开'));
    _pendingReply = null;
    await _readerSubscription?.cancel();
    _readerSubscription = null;
    _reader?.close();
    _reader = null;
    final port = _port;
    _port = null;
    if (port != null) {
      if (port.isOpen) port.close();
      port.dispose();
    }
    _lineBuffer = '';
  }
}
