//目标：把 HTTP/WS 两套能力组合成“更好用的业务接口”。
//Repository 类比“中间件/适配层”：把 HTTP + WS 组合成“连接/订阅/发 gcode”等可用能力。
//例如：getFullPrinterStatus / executePrintJob / monitorPrintProgress

import '../../core/moonraker_config.dart';
import 'moonraker_http_service.dart';
import 'moonraker_ws_service.dart';

enum StatusProfile { basic, full }

class MoonrakerRepository {
  final MoonrakerHttpService http;
  final MoonrakerWsService ws;

  MoonrakerRepository._(this.http, this.ws);
  //工厂构造函数：根据配置创建 HTTP 和 WS 服务实例，并返回一个 Repository 实例。
  //这样外部只需要关心 Repository，而不需要直接使用 HTTP/WS 服务。

  factory MoonrakerRepository(MoonrakerConfig config) {
    return MoonrakerRepository._(
      MoonrakerHttpService(config),
      MoonrakerWsService(config),
    );
  }
  //factory 关键词表示这是一个工厂构造函数，允许你在创建实例时执行一些额外的逻辑（如创建其他对象）。
  //这里我们根据传入的配置创建 HTTP 和 WS 服务，并将它们传递给私有构造函数。

    Future<void> close() async {
    await ws.dispose();
  }

  Future<Map<String, dynamic>> fetchServerInfo() => http.serverInfo();
  Future<Map<String, dynamic>> fetchPrinterInfo() => http.printerInfo();
  Future<Map<String, dynamic>> fetchObjectsList() => http.objectsList();

  Future<void> connectWs() => ws.connect();

  Stream<Map<String, dynamic>> get wsMessages => ws.messages;
  Stream<WsConnState> get wsConnEvents => ws.connEvents;

  Map<String, dynamic> _wantedObjectsByProfile(StatusProfile profile) {
    switch (profile) {
      case StatusProfile.basic:
        return <String, dynamic>{
          'print_stats': ['state', 'filename'],
          'virtual_sdcard': ['progress', 'is_active'],
          'toolhead': ['position'],
          'gcode_move': ['gcode_position'],
        };
      case StatusProfile.full:
        return <String, dynamic>{
          // 基础
          'print_stats': null,       // full 档可以直接订阅全部字段（方便调试）
          'virtual_sdcard': null,
          'toolhead': null,
          'gcode_move': null,

          // 扩展：常见对象（若 printer.cfg 不包含，会被过滤掉）
          'pause_resume': null,
          'display_status': null,
          'idle_timeout': null,
          'system_stats': null,
        };
    }
  }

  /// 智能订阅：先 objects/list，再过滤不存在对象
  Future<Map<String, dynamic>> subscribe(StatusProfile profile) async {
    final filtered = await buildSubscriptionObjects(profile);
    return ws.subscribe(filtered);
  }

  Future<Map<String, dynamic>> buildSubscriptionObjects(StatusProfile profile) async {
    final objectsList = await fetchObjectsList();
    final list = (objectsList['result']?['objects'] as List?)?.cast<String>() ?? const [];
    final available = list.toSet();

    final wanted = _wantedObjectsByProfile(profile);
    final filtered = <String, dynamic>{};
    wanted.forEach((k, v) {
      if (available.contains(k)) filtered[k] = v;
    });

    return filtered;
  }

  Future<Map<String, dynamic>> queryStatusSnapshot(Map<String, dynamic> objects) async {
    final resp = await http.objectsQuery(objects);
    final result = (resp['result'] as Map?)?.cast<String, dynamic>() ?? {};
    final status = (result['status'] as Map?)?.cast<String, dynamic>() ?? {};
    return status;
  }

  Future<void> sendTestGcode() async {
    await http.gcodeScript('M115\n');
  }
}