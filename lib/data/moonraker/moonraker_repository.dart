//目标：把 HTTP/WS 两套能力组合成“更好用的业务接口”。
//Repository 类比“中间件/适配层”：把 HTTP + WS 组合成“连接/订阅/发 gcode”等可用能力。
//例如：getFullPrinterStatus / executePrintJob / monitorPrintProgress

import '../../core/moonraker_config.dart';
import 'moonraker_http_service.dart';
import 'moonraker_ws_service.dart';
import 'moonraker_models.dart';

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

    Future<String> uploadGcodeString({
    required String filename,
    required String gcode,
    String root = 'gcodes',
    String? path,
  }) async {
    final resp = await http.uploadGcodeBytes(
      filename: filename,
      bytes: gcode.codeUnits, // ASCII 基本够用；更严谨可用 utf8.encode(gcode)
      root: root,
      path: path,
    );

    // Moonraker 返回结构通常是 result.item.path / result.item.filename 等
    final result = (resp['result'] as Map?)?.cast<String, dynamic>() ?? {};
    final item = (result['item'] as Map?)?.cast<String, dynamic>() ?? {};
    final uploadedPath = (item['path'] ?? item['filename'] ?? filename).toString();
    return uploadedPath;
  }

  Future<void> startPrintUploaded(String filenameOrPath) async {
    await http.startPrint(filenameOrPath);
  }

  Future<void> deleteGcodeFile(String filename) async {
    await http.deleteFile(filename: filename);
  }

  Future<List<MoonrakerFileItem>> listGcodeFiles({String root = 'gcodes'}) async {
    final resp = await http.filesList(root: root);
    final result = resp['result'];
    
    List filesList = [];
    if (result is List) {
      filesList = result;
    } else if (result is Map && result['files'] is List) {
      filesList = result['files'];
    }

    return filesList
        .whereType<Map>()
        .map((e) => MoonrakerFileItem.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  // ── 配置文件 API ────────────────────────────────────────────────────────

  /// 列出某个 root 下的所有文件（扁平列表）
  Future<List<MoonrakerFileItem>> listFiles({required String root}) async {
    final resp = await http.filesList(root: root);
    final result = resp['result'];

    List raw = [];
    if (result is List) {
      raw = result;
    } else if (result is Map && result['files'] is List) {
      raw = result['files'] as List;
    }

    return raw
        .whereType<Map>()
        .map((e) => MoonrakerFileItem.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// 读取文件文本内容
  Future<String> readFileText({required String root, required String path}) {
    return http.readFileRaw(root: root, path: path);
  }

  /// 写入/保存文件文本内容
  Future<void> writeFileText({
    required String root,
    required String path,
    required String content,
  }) async {
    await http.uploadTextFile(root: root, path: path, content: content);
  }

  /// 删除配置文件
  Future<void> deleteConfigFile({required String root, required String path}) async {
    await http.deleteFile(filename: path, root: root);
  }
}