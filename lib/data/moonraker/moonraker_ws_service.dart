//目标：建立 WS 连接、发 JSON-RPC 请求、接收消息流。
//例如：connect / disconnect / sendRequest / onMessageStream
//核心：JSON-RPC 请求 id ↔ 响应匹配 + 持续接收 notify消息。

import 'dart:async';//异步库（async）
import 'dart:convert';//JSON编解码（convert）

//import 'package:web_socket_channel/io.dart';//dart:io 只能在 iOS、Android、Windows、macOS 和 Linux 上运行，不支持 web;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/moonraker_config.dart';

enum WsConnState { connected, disconnected, error }

class MoonrakerWsService {
  final MoonrakerConfig config;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  final _incoming = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _incoming.stream;

  final _connEvents = StreamController<WsConnState>.broadcast();
  Stream<WsConnState> get connEvents => _connEvents.stream;

  int _nextId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};

  bool get isConnected => _channel != null;

  MoonrakerWsService(this.config);

  Future<void> connect() async {
    if (_channel != null) return;

    final uri = Uri.parse(config.wsUrl);
    _channel = WebSocketChannel.connect(uri);

    _connEvents.add(WsConnState.connected);

    _sub = _channel!.stream.listen((event) {
      final text = event as String;
      final msg = (jsonDecode(text) as Map).cast<String, dynamic>();

      _incoming.add(msg);

      final id = msg['id'];
      if (id is int) {
        final c = _pending.remove(id);
        if (c != null && !c.isCompleted) c.complete(msg);
      }
    }, onError: (e) {
      _connEvents.add(WsConnState.error);
    }, onDone: () {
      _connEvents.add(WsConnState.disconnected);
    });
  }

  Future<void> disconnect() async {
    // 不关闭 _incoming / _connEvents，便于重连复用
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('WebSocket disconnected'));
    }
    _pending.clear();

    await _sub?.cancel();
    _sub = null;

    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _incoming.close();
    await _connEvents.close();
  }

  Future<Map<String, dynamic>> sendRequest(String method, Map<String, dynamic> params) async {
    if (_channel == null) throw StateError('WebSocket not connected');

    final id = _nextId++;
    final req = <String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
      'id': id,
    };

    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;

    _channel!.sink.add(jsonEncode(req));
    return c.future.timeout(const Duration(seconds: 5));
  }

  Future<Map<String, dynamic>> subscribe(Map<String, dynamic> objects) {
    return sendRequest('printer.objects.subscribe', {'objects': objects});
  }
}