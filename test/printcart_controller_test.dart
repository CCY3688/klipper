import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:klipper/data/printcart/printcart_protocol.dart';
import 'package:klipper/data/printcart/printcart_serial_service.dart';
import 'package:klipper/state/printcart_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTransport implements PrintcartTransport {
  final int protocolVersion;
  final int initReplies;
  final commands = <String>[];
  final eventController = StreamController<String>.broadcast();
  bool connected = false;
  bool failFire = false;
  int _pingCount = 0;

  _FakeTransport({this.protocolVersion = 2, this.initReplies = 0});

  @override
  bool get isConnected => connected;

  @override
  Stream<String> get events => eventController.stream;

  @override
  Future<List<PrintcartPortInfo>> listPorts() async => const [
    PrintcartPortInfo(name: 'COM23', vendorId: 0x303a, productId: 0x1001),
  ];

  @override
  Future<void> connect(String portName) async => connected = true;

  @override
  Future<String> command(
    String command, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    commands.add(command);
    if (command == 'PING') {
      _pingCount++;
      if (_pingCount <= initReplies) {
        return 'OK ESP32S3-PRINTERCART 1 COLOR INIT';
      }
      return 'OK ESP32S3-PRINTERCART $protocolVersion COLOR';
    }
    if (command == 'STATUS') {
      return 'OK STATUS HV=OFF CART=COLOR FRAME_BYTES=42 AUTO_OFF_MS=5000';
    }
    if (command.startsWith('FIRE ') && failFire) {
      throw StateError('WAVEFORM');
    }
    if (command == 'HV ON') {
      return 'OK HV ON AUTO_OFF_MS=5000';
    }
    if (command == 'OFF') {
      return 'OK OFF';
    }
    return 'OK FIRE';
  }

  @override
  Future<void> disconnect() async => connected = false;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('auto detects the ESP32-S3 and accepts protocol v2', () async {
    final transport = _FakeTransport();
    final controller = PrintcartController(transport: transport);

    await controller.connect();

    expect(controller.selectedPort, 'COM23');
    expect(controller.isConnected, isTrue);
    expect(controller.hasSafeFirmware, isTrue);
    expect(transport.commands, ['PING', 'STATUS']);
    controller.dispose();
  });

  test(
    'waits for firmware initialization before rejecting the connection',
    () async {
      final transport = _FakeTransport(initReplies: 2);
      final controller = PrintcartController(transport: transport);

      await controller.connect();

      expect(controller.hasSafeFirmware, isTrue);
      expect(transport.commands, ['PING', 'PING', 'PING', 'STATUS']);
      controller.dispose();
    },
  );

  test('protocol v1 is connected but firing remains locked', () async {
    final controller = PrintcartController(
      transport: _FakeTransport(protocolVersion: 1),
    );

    await controller.connect();

    expect(controller.isConnected, isTrue);
    expect(controller.canFire, isFalse);
    expect(controller.errorMessage, contains('协议低于 v2'));
    controller.dispose();
  });

  test('always sends OFF when FIRE fails', () async {
    final transport = _FakeTransport()..failFire = true;
    final controller = PrintcartController(transport: transport);
    await controller.connect();

    await expectLater(
      controller.fireSingleNozzle(
        color: PrintcartColor.cyan,
        nozzle: 0,
        repeats: 1,
        intervalMs: 50,
      ),
      throwsStateError,
    );

    expect(transport.commands, contains('HV ON'));
    expect(transport.commands.last, 'OFF');
    expect(controller.status?.highVoltageEnabled, isFalse);
    controller.dispose();
  });
}
