import 'dart:typed_data';

enum PrintcartColor { cyan, magenta, yellow }

extension PrintcartColorLabel on PrintcartColor {
  String get shortLabel => switch (this) {
    PrintcartColor.cyan => 'C',
    PrintcartColor.magenta => 'M',
    PrintcartColor.yellow => 'Y',
  };

  String get displayName => switch (this) {
    PrintcartColor.cyan => '青色',
    PrintcartColor.magenta => '品红',
    PrintcartColor.yellow => '黄色',
  };
}

enum NozzleHealth { unknown, normal, blocked }

class PrintcartFrame {
  static const frameBytes = 42;
  static const nozzlesPerColor = 84;
  static const physicalNozzleOffset = 14;

  static const _byteOrder = <List<int>>[
    [8, 13, 4, 9, 0, 5, 10, 1, 6, 11, 2, 7, 12, 3],
    [11, 2, 7, 12, 3, 8, 13, 4, 9, 0, 5, 10, 1, 6],
    [0, 5, 10, 1, 6, 11, 2, 7, 12, 3, 8, 13, 4, 9],
  ];

  static Uint8List singleNozzle(PrintcartColor color, int logicalNozzle) {
    if (logicalNozzle < 0 || logicalNozzle >= nozzlesPerColor) {
      throw RangeError.range(
        logicalNozzle,
        0,
        nozzlesPerColor - 1,
        'logicalNozzle',
      );
    }

    final physicalNozzle = logicalNozzle + physicalNozzleOffset;
    final colorIndex = color.index;
    final byteIndex =
        colorIndex * 14 + _byteOrder[colorIndex][physicalNozzle % 14];
    final bitIndex = physicalNozzle ~/ 14;
    final frame = Uint8List(frameBytes);
    frame[byteIndex] = 1 << bitIndex;
    return frame;
  }

  static String toHex(Uint8List frame) {
    if (frame.length != frameBytes) {
      throw ArgumentError.value(frame.length, 'frame.length', 'must be 42');
    }
    return frame.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  static String singleNozzleFireCommand(
    PrintcartColor color,
    int logicalNozzle,
  ) => 'FIRE ${toHex(singleNozzle(color, logicalNozzle))}';
}

class PrintcartStatus {
  final bool highVoltageEnabled;
  final String cartridge;
  final int frameBytes;
  final int autoOffMs;

  const PrintcartStatus({
    required this.highVoltageEnabled,
    required this.cartridge,
    required this.frameBytes,
    required this.autoOffMs,
  });

  static PrintcartStatus? tryParse(String line) {
    final match = RegExp(
      r'^OK STATUS HV=(ON|OFF) CART=([^ ]+) FRAME_BYTES=(\d+) AUTO_OFF_MS=(\d+)$',
    ).firstMatch(line.trim());
    if (match == null) return null;
    return PrintcartStatus(
      highVoltageEnabled: match.group(1) == 'ON',
      cartridge: match.group(2)!,
      frameBytes: int.parse(match.group(3)!),
      autoOffMs: int.parse(match.group(4)!),
    );
  }
}
