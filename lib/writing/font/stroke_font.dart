import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

import '../model/geometry.dart';
import '../model/glyph.dart';
import '../model/stroke.dart';

// ============================================================================
// StrokeGlyph - 旧版数据结构（保留用于向后兼容）
// ============================================================================
/// 
/// 【功能】简单的字形表示，只包含笔画的坐标点序列
/// 【使用场景】旧代码兼容、简单渲染场景
/// 【限制】不包含笔画类型等语义信息
class StrokeGlyph {
  /// 每个 stroke 是一条折线（点序列，坐标归一化 0..1）
  final List<List<Vec2>> strokes;
  const StrokeGlyph(this.strokes);
  
  /// 从新版 Glyph 转换（适配器模式的核心）
  factory StrokeGlyph.fromGlyph(Glyph glyph) {
    return StrokeGlyph(glyph.toRawStrokes());
  }
}

// ============================================================================
// StrokeFont - 笔画字体（支持新旧两种数据格式）
// ============================================================================
/// 
/// 【功能】管理一套笔画字体的字形数据
/// 【JSON格式支持】
///   - 旧格式：{"strokes": [[[x,y], [x,y]]]} - 纯坐标点
///   - 新格式：{"strokes": [{"points": [...], "type": "horizontal"}]} - 带类型信息
/// 【对外接口】
///   - glyphOf(ch): 获取旧格式字形（兼容现有代码）
///   - richGlyphOf(ch): 获取新格式字形（带类型信息）
class StrokeFont {
  /// 内部使用新版 Glyph 存储（保留完整信息）
  final Map<String, Glyph> _glyphs;
  
  /// 缓存的旧版格式（按需转换，提升性能）
  final Map<String, StrokeGlyph> _legacyCache = {};
  
  StrokeFont._(this._glyphs);
  
  /// 旧版构造函数（兼容现有代码）
  factory StrokeFont(Map<String, StrokeGlyph> legacyGlyphs) {
    final map = <String, Glyph>{};
    for (final entry in legacyGlyphs.entries) {
      map[entry.key] = Glyph.fromRawStrokes(entry.key, entry.value.strokes);
    }
    return StrokeFont._(map);
  }
  
  // -------------- 对外接口 --------------
  
  /// 【旧接口】获取字形（返回 StrokeGlyph，兼容现有布局代码）
  StrokeGlyph? glyphOf(String ch) {
    if (!_glyphs.containsKey(ch)) return null;
    
    // 使用缓存避免重复转换
    return _legacyCache.putIfAbsent(
      ch, 
      () => StrokeGlyph.fromGlyph(_glyphs[ch]!)
    );
  }
  
  /// 【新接口】获取富字形（返回 Glyph，包含笔画类型等信息）
  Glyph? richGlyphOf(String ch) => _glyphs[ch];
  
  /// 获取所有字符
  Iterable<String> get characters => _glyphs.keys;
  
  /// 字形总数
  int get length => _glyphs.length;
  
  // -------------- 加载方法 --------------
  
  /// 从 Asset 加载字体（自动识别新旧格式）
  static Future<StrokeFont> loadFromAsset(String assetPath) async {
    final text = await rootBundle.loadString(assetPath);
    return loadFromJson(text);
  }
  
  /// 从 JSON 字符串加载（核心解析逻辑）
  static StrokeFont loadFromJson(String jsonText) {
    final jsonObj = jsonDecode(jsonText) as Map<String, dynamic>;
    final glyphsObj = (jsonObj['glyphs'] as Map).cast<String, dynamic>();
    
    final map = <String, Glyph>{};
    
    for (final entry in glyphsObj.entries) {
      final ch = entry.key;
      final glyphData = (entry.value as Map).cast<String, dynamic>();
      
      // 使用 Glyph.fromJson，它会自动处理新旧格式
      try {
        final glyph = Glyph.fromJson(ch, glyphData);
        if (!glyph.isEmpty) {
          map[ch] = glyph;
        }
      } catch (e) {
        // 解析失败时跳过该字形，可以在这里添加日志
        continue;
      }
    }
    
    return StrokeFont._(map);
  }
}