import 'package:flutter_test/flutter_test.dart';
import 'package:klipper/data/printcart/printcart_protocol.dart';

void main() {
  test('single nozzle frame uses the physical +14 offset', () {
    final frame = PrintcartFrame.singleNozzle(PrintcartColor.cyan, 0);

    expect(frame.length, PrintcartFrame.frameBytes);
    expect(frame.where((value) => value != 0), hasLength(1));
    expect(frame[8], 0x02);
    expect(PrintcartFrame.toHex(frame), hasLength(84));
  });

  test('last logical nozzle remains inside the six active bits', () {
    final frame = PrintcartFrame.singleNozzle(PrintcartColor.yellow, 83);

    expect(frame.where((value) => value != 0), hasLength(1));
    expect(frame[37], 0x40);
  });

  test('color rows use separate 14 byte regions', () {
    final cyan = PrintcartFrame.singleNozzle(PrintcartColor.cyan, 20);
    final magenta = PrintcartFrame.singleNozzle(PrintcartColor.magenta, 20);
    final yellow = PrintcartFrame.singleNozzle(PrintcartColor.yellow, 20);

    expect(cyan.sublist(14).every((value) => value == 0), isTrue);
    expect(magenta.sublist(0, 14).every((value) => value == 0), isTrue);
    expect(magenta.sublist(28).every((value) => value == 0), isTrue);
    expect(yellow.sublist(0, 28).every((value) => value == 0), isTrue);
  });

  test('status response is parsed', () {
    final status = PrintcartStatus.tryParse(
      'OK STATUS HV=OFF CART=COLOR FRAME_BYTES=42 AUTO_OFF_MS=5000',
    );

    expect(status, isNotNull);
    expect(status!.highVoltageEnabled, isFalse);
    expect(status.frameBytes, 42);
    expect(status.autoOffMs, 5000);
  });
}
