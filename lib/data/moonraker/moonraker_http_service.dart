//目标：封装 dio，提供最基本的 get/post 与常用接口。
//例如：getServerInfo / getPrinterStatus / sendGcodeCommand

import 'package:dio/dio.dart';
import '../../core/moonraker_config.dart';

class MoonrakerHttpService {
  final Dio _dio;

  MoonrakerHttpService(MoonrakerConfig config)
      : _dio = Dio(BaseOptions( //Dio实例初始化，BaseOptions是Dio的配置类，设置基本选项
          baseUrl: config.httpBaseUrl,
          headers: config.headers,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 8),
        ));

  //getJson和postJson是两个通用方法，分别用于发送GET和POST请求，并将响应数据转换为Map<String, dynamic>类型（类似于JSON对象）
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final resp = await _dio.get(path, queryParameters: queryParameters);
    return (resp.data as Map).cast<String, dynamic>();
  }
    //Future表示异步操作的结果；async：关键词，表示这个方法是异步的（asynchronous），允许使用await

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async {
    final resp = await _dio.post(path, data: body);
    return (resp.data as Map).cast<String, dynamic>();
      //as Map：类型断言（cast），将响应数据转换为Map。cast<String, dynamic>()：强制转换为指定类型的Map。
  }

  Future<Map<String, dynamic>> deleteJson(String path) async {
    final resp = await _dio.delete(path);
    return (resp.data as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> serverInfo() => getJson('/server/info');

  Future<Map<String, dynamic>> printerInfo() => getJson('/printer/info');

  Future<Map<String, dynamic>> objectsList() => getJson('/printer/objects/list');

  Future<Map<String, dynamic>> objectsQuery(Map<String, dynamic> objects) {
    return postJson('/printer/objects/query', {'objects': objects});
  }

  Future<Map<String, dynamic>> gcodeScript(String script) {
    return postJson('/printer/gcode/script', {'script': script});
  }

    Future<Map<String, dynamic>> uploadGcodeBytes({
    required String filename,
    required List<int> bytes,
    String root = 'gcodes',
    String? path, // 子目录，可选
  }) async {
    final form = FormData.fromMap({
      'root': root,
      if (path != null && path.trim().isNotEmpty) 'path': path.trim(),
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });

    final resp = await _dio.post(
      '/server/files/upload',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    return (resp.data as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> startPrint(String filename) async {
    // filename 通常是相对于 gcodes root 的路径，如 "demo.gcode" 或 "subdir/demo.gcode"
    return postJson('/printer/print/start', {'filename': filename});
  }

  Future<Map<String, dynamic>> filesList({
    String root = 'gcodes',
    String? path,
  }) {
    return getJson(
      '/server/files/list',
      queryParameters: {
        'root': root,
        if (path != null && path.trim().isNotEmpty) 'path': path.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> deleteFile({
    required String filename,
    String root = 'gcodes',
  }) {
    // 编码文件名以处理路径分隔符等
    final encoded = Uri.encodeComponent(filename);
    return deleteJson('/server/files/$root/$encoded');
  }
}

