/// 用户字体风格档案（UserFontProfile）
///
/// 存储从用户 TTF 字体文件学习到的字形数据，以及配置参数。
/// 采用 JSON 格式持久化到 app 文档目录。
library;

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../model/geometry.dart';
import '../model/glyph.dart';
import '../model/stroke.dart';

/// 字体风格来源
enum FontSourceType {
  ttf,        // 从 TTF/OTF 文件学习
  parameterized, // 参数化风格（未来扩展）
  ml,         // 机器学习（未来扩展）
}

/// 用户字体档案
class UserFontProfile {
  /// 档案唯一 ID（UUID 或时间戳字符串）
  final String id;

  /// 显示名称（用户命名，如"我的手写体"）
  String name;

  /// 风格来源
  final FontSourceType source;

  /// 原始 TTF 文件名（仅用于显示，不重新加载）
  final String? sourceFontFileName;

  /// 创建时间
  final DateTime createdAt;

  /// 最后更新时间
  DateTime updatedAt;

  /// 从 TTF 学习到的字形（char → Glyph）
  final Map<String, Glyph> learnedGlyphs;

  /// 处理进度（0.0 ~ 1.0）
  /// 持久化时存储，用于断点续传场景
  double processingProgress;

  UserFontProfile({
    required this.id,
    required this.name,
    required this.source,
    this.sourceFontFileName,
    required this.createdAt,
    required this.updatedAt,
    required this.learnedGlyphs,
    this.processingProgress = 1.0,
  });

  /// 已学习的字形数量
  int get learnedCount => learnedGlyphs.length;

  /// 判断是否包含某字符
  bool hasGlyph(String ch) => learnedGlyphs.containsKey(ch);

  // ─────────────────────────────────────────────────────────────────────
  // JSON 序列化
  // ─────────────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'source': source.name,
      'sourceFontFileName': sourceFontFileName,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'processingProgress': processingProgress,
      'glyphs': _encodeGlyphs(),
    };
  }

  Map<String, dynamic> _encodeGlyphs() {
    final result = <String, dynamic>{};
    for (final entry in learnedGlyphs.entries) {
      result[entry.key] = _encodeGlyph(entry.value);
    }
    return result;
  }

  static Map<String, dynamic> _encodeGlyph(Glyph g) {
    return {
      'strokes': g.strokes.map(_encodeStroke).toList(),
      if (g.aspectRatio != null) 'aspectRatio': g.aspectRatio,
    };
  }

  static Map<String, dynamic> _encodeStroke(Stroke s) {
    return {
      'points': s.points.map((p) => [p.x, p.y]).toList(),
      if (s.type != null) 'type': s.type!.name,
    };
  }

  factory UserFontProfile.fromJson(Map<String, dynamic> json) {
    final glyphsJson = (json['glyphs'] as Map<String, dynamic>?) ?? {};
    final glyphs = <String, Glyph>{};

    for (final entry in glyphsJson.entries) {
      final g = _decodeGlyph(entry.key, entry.value as Map<String, dynamic>);
      if (g != null) glyphs[entry.key] = g;
    }

    return UserFontProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      source: FontSourceType.values.firstWhere(
        (e) => e.name == json['source'],
        orElse: () => FontSourceType.ttf,
      ),
      sourceFontFileName: json['sourceFontFileName'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      learnedGlyphs: glyphs,
      processingProgress: (json['processingProgress'] as num?)?.toDouble() ?? 1.0,
    );
  }

  static Glyph? _decodeGlyph(String char, Map<String, dynamic> json) {
    final strokesJson = json['strokes'] as List<dynamic>?;
    if (strokesJson == null) return null;

    final strokes = <Stroke>[];
    for (final sJson in strokesJson) {
      final s = _decodeStroke(sJson);
      if (s != null) strokes.add(s);
    }
    if (strokes.isEmpty) return null;

    return Glyph(
      character: char,
      strokes: strokes,
      aspectRatio: (json['aspectRatio'] as num?)?.toDouble(),
    );
  }

  static Stroke? _decodeStroke(dynamic json) {
    List<dynamic> pointsJson;
    StrokeType? type;

    if (json is List) {
      pointsJson = json;
    } else if (json is Map) {
      pointsJson = json['points'] as List<dynamic>;
      final typeStr = json['type'] as String?;
      if (typeStr != null) {
        type = StrokeType.values.firstWhere(
          (t) => t.name == typeStr,
          orElse: () => StrokeType.other,
        );
      }
    } else {
      return null;
    }

    final points = <Vec2>[];
    for (final p in pointsJson) {
      if (p is List && p.length >= 2) {
        points.add(Vec2((p[0] as num).toDouble(), (p[1] as num).toDouble()));
      }
    }

    if (points.length < 2) return null;
    return Stroke(points: points, type: type);
  }

  // ─────────────────────────────────────────────────────────────────────
  // 文件系统持久化
  // ─────────────────────────────────────────────────────────────────────

  static const _profilesDirName = 'user_fonts';

  /// 加载所有已保存档案
  static Future<List<UserFontProfile>> loadAll() async {
    final dir = await _profilesDir();
    if (!await dir.exists()) return [];

    final profiles = <UserFontProfile>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final content = await entity.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          profiles.add(UserFontProfile.fromJson(json));
        } catch (_) {
          // 跳过损坏文件
        }
      }
    }

    profiles.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return profiles;
  }

  /// 保存档案到磁盘
  Future<void> save() async {
    updatedAt = DateTime.now();
    final dir = await _profilesDir();
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/$id.json');
    await file.writeAsString(jsonEncode(toJson()));
  }

  /// 删除档案
  Future<void> delete() async {
    final dir = await _profilesDir();
    final file = File('${dir.path}/$id.json');
    if (await file.exists()) await file.delete();
  }

  static Future<Directory> _profilesDir() async {
    final appDoc = await getApplicationDocumentsDirectory();
    return Directory('${appDoc.path}/$_profilesDirName');
  }

  /// 创建新档案（工厂）
  static UserFontProfile createNew({
    required String name,
    FontSourceType source = FontSourceType.ttf,
    String? sourceFontFileName,
  }) {
    final now = DateTime.now();
    return UserFontProfile(
      id: now.millisecondsSinceEpoch.toString(),
      name: name,
      source: source,
      sourceFontFileName: sourceFontFileName,
      createdAt: now,
      updatedAt: now,
      learnedGlyphs: {},
      processingProgress: 0,
    );
  }
}
