import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/style_vector.dart';

/// 风格模型管理器
/// 
/// 负责保存、加载、管理用户的风格模型
class StyleModelManager {
  static const String _styleDir = 'style_models';
  static const String _modelExtension = '.style';

  /// 获取存储目录
  Future<Directory> _getStyleDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final styleDir = Directory('${appDir.path}/$_styleDir');

    if (!await styleDir.exists()) {
      await styleDir.create(recursive: true);
    }

    return styleDir;
  }

  /// 保存风格模型
  Future<String> saveStyle(StyleVector style, String name) async {
    final dir = await _getStyleDirectory();
    final fileName = _sanitizeFileName(name);
    final file = File('${dir.path}/$fileName$_modelExtension');

    final metadata = StyleModelMetadata(
      name: name,
      createdAt: style.createdAt,
      sampleCount: style.sampleCount,
      version: style.version,
    );

    final data = {
      'metadata': metadata.toJson(),
      'style': style.toJson(),
    };

    await file.writeAsString(jsonEncode(data));
    return file.path;
  }

  /// 加载风格模型
  Future<StyleVector> loadStyle(String name) async {
    final dir = await _getStyleDirectory();
    final fileName = _sanitizeFileName(name);
    final file = File('${dir.path}/$fileName$_modelExtension');

    if (!await file.exists()) {
      throw StyleModelNotFoundException('找不到风格模型: $name');
    }

    final content = await file.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;

    return StyleVector.fromJson(data['style'] as Map<String, dynamic>);
  }

  /// 列出所有风格模型
  Future<List<StyleModelMetadata>> listStyles() async {
    final dir = await _getStyleDirectory();
    final files = await dir
        .list()
        .where((f) => f.path.endsWith(_modelExtension))
        .toList();

    final models = <StyleModelMetadata>[];

    for (final file in files) {
      try {
        final content = await File(file.path).readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final metadata = StyleModelMetadata.fromJson(
          data['metadata'] as Map<String, dynamic>,
        );
        models.add(metadata);
      } catch (e) {
        // 跳过无效文件
        continue;
      }
    }

    // 按创建时间排序
    models.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return models;
  }

  /// 删除风格模型
  Future<void> deleteStyle(String name) async {
    final dir = await _getStyleDirectory();
    final fileName = _sanitizeFileName(name);
    final file = File('${dir.path}/$fileName$_modelExtension');

    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 重命名风格模型
  Future<void> renameStyle(String oldName, String newName) async {
    final style = await loadStyle(oldName);
    await saveStyle(style, newName);
    await deleteStyle(oldName);
  }

  /// 导出风格模型（用于分享）
  Future<String> exportStyle(String name) async {
    final style = await loadStyle(name);
    return jsonEncode(style.toJson());
  }

  /// 导入风格模型
  Future<void> importStyle(String jsonData, String name) async {
    final data = jsonDecode(jsonData) as Map<String, dynamic>;
    final style = StyleVector.fromJson(data);
    await saveStyle(style, name);
  }

  /// 清理文件名
  String _sanitizeFileName(String name) {
    return name
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
  }
}

/// 风格模型元数据
class StyleModelMetadata {
  final String name;
  final DateTime createdAt;
  final int sampleCount;
  final int version;

  StyleModelMetadata({
    required this.name,
    required this.createdAt,
    required this.sampleCount,
    required this.version,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'sampleCount': sampleCount,
      'version': version,
    };
  }

  factory StyleModelMetadata.fromJson(Map<String, dynamic> json) {
    return StyleModelMetadata(
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      sampleCount: json['sampleCount'] as int,
      version: json['version'] as int? ?? 1,
    );
  }
}

/// 风格模型未找到异常
class StyleModelNotFoundException implements Exception {
  final String message;
  StyleModelNotFoundException(this.message);

  @override
  String toString() => message;
}