// lib/data/moonraker/moonraker_models.dart
typedef JsonMap = Map<String, dynamic>;

List<double>? _toDoubleList(dynamic v) {
  if (v is! List) return null;
  return v.map((e) => (e as num).toDouble()).toList();
}

class MoonrakerServerInfo {
  final bool klippyConnected;
  final String klippyState;
  final String moonrakerVersion;
  final String apiVersionString;

  const MoonrakerServerInfo({
    required this.klippyConnected,
    required this.klippyState,
    required this.moonrakerVersion,
    required this.apiVersionString,
  });

  factory MoonrakerServerInfo.fromServerInfoResponse(JsonMap resp) {
    final result = (resp['result'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    return MoonrakerServerInfo(
      klippyConnected: (result['klippy_connected'] as bool?) ?? false,
      klippyState: (result['klippy_state'] ?? '').toString(),
      moonrakerVersion: (result['moonraker_version'] ?? '').toString(),
      apiVersionString: (result['api_version_string'] ?? '').toString(),
    );
  }
}

class MoonrakerPrinterInfo {
  final String state;
  final String stateMessage;
  final String hostname;

  const MoonrakerPrinterInfo({
    required this.state,
    required this.stateMessage,
    required this.hostname,
  });

  factory MoonrakerPrinterInfo.fromPrinterInfoResponse(JsonMap resp) {
    final result = (resp['result'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    return MoonrakerPrinterInfo(
      state: (result['state'] ?? '').toString(),
      stateMessage: (result['state_message'] ?? '').toString(),
      hostname: (result['hostname'] ?? '').toString(),
    );
  }
}

class PrintStats {
  final String? state;
  final String? filename;

  const PrintStats({this.state, this.filename});

  PrintStats applyDelta(JsonMap d) => PrintStats(
        state: d.containsKey('state') ? (d['state']?.toString()) : state,
        filename: d.containsKey('filename') ? (d['filename']?.toString()) : filename,
      );
}

class VirtualSdCard {
  final double? progress; // 0..1
  final bool? isActive;

  const VirtualSdCard({this.progress, this.isActive});

  VirtualSdCard applyDelta(JsonMap d) => VirtualSdCard(
        progress: d.containsKey('progress') ? (d['progress'] as num?)?.toDouble() : progress,
        isActive: d.containsKey('is_active') ? (d['is_active'] as bool?) : isActive,
      );
}

class Toolhead {
  final List<double>? position;

  const Toolhead({this.position});

  Toolhead applyDelta(JsonMap d) => Toolhead(
        position: d.containsKey('position') ? _toDoubleList(d['position']) : position,
      );
}

class GcodeMove {
  final List<double>? gcodePosition;

  const GcodeMove({this.gcodePosition});

  GcodeMove applyDelta(JsonMap d) => GcodeMove(
        gcodePosition: d.containsKey('gcode_position') ? _toDoubleList(d['gcode_position']) : gcodePosition,
      );
}

/// WS 订阅的综合状态（可增量更新）
class PrinterStatus {
  final PrintStats? printStats;
  final VirtualSdCard? virtualSdcard;
  final Toolhead? toolhead;
  final GcodeMove? gcodeMove;

  const PrinterStatus({
    this.printStats,
    this.virtualSdcard,
    this.toolhead,
    this.gcodeMove,
  });

  static const empty = PrinterStatus();

  static PrinterStatus fromSnapshot(JsonMap statusMap) {
    return PrinterStatus.empty.applyDelta(statusMap);
  }

  PrinterStatus applyDelta(JsonMap delta) {
    PrintStats? ps = printStats;
    VirtualSdCard? vsd = virtualSdcard;
    Toolhead? th = toolhead;
    GcodeMove? gm = gcodeMove;

    final d1 = delta['print_stats'];
    if (d1 is Map) ps = (ps ?? const PrintStats()).applyDelta(d1.cast<String, dynamic>());

    final d2 = delta['virtual_sdcard'];
    if (d2 is Map) vsd = (vsd ?? const VirtualSdCard()).applyDelta(d2.cast<String, dynamic>());

    final d3 = delta['toolhead'];
    if (d3 is Map) th = (th ?? const Toolhead()).applyDelta(d3.cast<String, dynamic>());

    final d4 = delta['gcode_move'];
    if (d4 is Map) gm = (gm ?? const GcodeMove()).applyDelta(d4.cast<String, dynamic>());

    return PrinterStatus(
      printStats: ps,
      virtualSdcard: vsd,
      toolhead: th,
      gcodeMove: gm,
    );
  }
}