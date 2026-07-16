// 目标：创建一个配置类，方便将来切换不同的Moonraker服务器地址（host/port等），并提供计算属性（如URL和headers）
// 需要一个配置类：
// - host / port / useHttps / apiKey
// - baseUrl / wsUrl 计算属性
//HTTP：http://host:port (http://172.31.204.78:7125)
//WS：ws://host:port/websocket (ws://172.31.204.78:7125/websocket)

class MoonrakerConfig {
  final String host;    //final：关键词表示这个变量是只读的，一旦赋值后不能修改
  final int port;
  final String? apiKey; //?表示这个类型是可空的
  final bool useHttps;

  const MoonrakerConfig({
    required this.host, //关键词，表示这个命名参数是必须提供的
    required this.port, //this是指向当前对象的指针，表示将传入的参数赋值给对象的字段
    this.apiKey,
    this.useHttps = false,
  });

  //getter方法（getter），用于获取计算属性
  String get httpBaseUrl => '${useHttps ? "https" : "http"}://$host:$port';
  String get wsUrl => '${useHttps ? "wss" : "ws"}://$host:$port/websocket';
  //=>：箭头函数语法，简写形式，相当于{ return ...; }。类似于C中的单行函数。
  //${}用于插入变量或表达式

  //Map是映射类型（类似C中的哈希表或字典），键和值都是字符串。用于存储HTTP头信息
  Map<String, String> get headers { //返回一个Map对象，表示HTTP请求的头信息
    final key = apiKey?.trim();     //?. 安全访问操作符，只有当apiKey不为null时才调用trim()方法（移除字符串前后空格），否则返回null
    if (key == null || key.isEmpty) return {};
    return {'X-Api-Key': key};
  }
}