/// 字形处理流水线调试器
///
/// 对单个字符执行完整处理链，记录每个阶段的中间结果。
/// 用于诊断笔画断裂等问题。
library;

import 'dart:io';

import 'package:flutter/services.dart';

import '../../model/geometry.dart';
import '../../model/stroke.dart';
import '../alignment/stroke_order_aligner.dart';
import '../skeleton/outline_rasterizer.dart';
import '../skeleton/skeleton_vectorizer.dart';
import '../skeleton/skeletonizer.dart';
import '../ttf/bezier_sampler.dart';
import '../ttf/ttf_parser.dart';
import '../user_font_loader.dart';
import 'glyph_debug_data.dart';
import '../../model/glyph.dart';
import '../../font/makemeahanzi_converter.dart';
import 'dart:convert';

/// 对单个字符执行完整处理并返回调试数据
class GlyphDebugProcessor {
  /// 从 TTF 文件对一个字符生成调试数据
  static Future<GlyphDebugData> processChar({
    required File ttfFile,
    required String character,
    int preSpurPruneLen = 0,
    int tinyComponentSize = 0,
    int bridgeGap = 6,
    int postSpurPruneLen = 7,
  }) async {
    final bytes = await ttfFile.readAsBytes();
    final ttf = TtfParser.parse(bytes);
    final templates = await _loadTemplates();
    return _processCharDebug(
      character,
      ttf,
      templates,
      preSpurPruneLen: preSpurPruneLen,
      tinyComponentSize: tinyComponentSize,
      bridgeGap: bridgeGap,
      postSpurPruneLen: postSpurPruneLen,
    );
  }

  /// 直接从已解析的数据处理（避免重复解析）
  static Future<GlyphDebugData> processCharFromParsed({
    required TtfParser ttf,
    required String character,
    required Map<String, List<List<({double x, double y})>>> templates,
    int preSpurPruneLen = 0,
    int tinyComponentSize = 0,
    int bridgeGap = 6,
    int postSpurPruneLen = 7,
  }) async {
    return _processCharDebug(
      character,
      ttf,
      templates,
      preSpurPruneLen: preSpurPruneLen,
      tinyComponentSize: tinyComponentSize,
      bridgeGap: bridgeGap,
      postSpurPruneLen: postSpurPruneLen,
    );
  }

  static GlyphDebugData _processCharDebug(
    String ch,
    TtfParser ttf,
    Map<String, List<List<({double x, double y})>>> templates,
    {
    int preSpurPruneLen = 0,
    int tinyComponentSize = 0,
    int bridgeGap = 6,
    int postSpurPruneLen = 7,
    }
  ) {
    try {
      // ── 阶段 0: 获取 TTF 轮廓 ──
      final outline = ttf.glyphOutlineForChar(ch);
      if (outline == null || outline.isEmpty) {
        return GlyphDebugData(character: ch, error: 'no outline');
      }

      // 采样轮廓点（归一化到 0~1 用于预览）
      final resolution = 256;
      final padding = 8;
      final drawSize = resolution - padding * 2;
      final xMin = outline.xMin.toDouble();
      final yMin = outline.yMin.toDouble();
      final xRange = (outline.xMax - outline.xMin).toDouble();
      final yRange = (outline.yMax - outline.yMin).toDouble();

      List<List<({double x, double y})>>? sampledContours;
      if (xRange > 0 && yRange > 0) {
        final scale = drawSize / (xRange > yRange ? xRange : yRange);
        final xOffset = padding + (drawSize - xRange * scale) / 2;
        final yOffset = padding + (drawSize - yRange * scale) / 2;

        sampledContours = outline.contours.map((c) {
          final sc = BezierSampler.sample(c, maxSegmentLen: 1.0 / scale);
          return sc.points.map((p) {
            final bx = (p.x - xMin) * scale + xOffset;
            final by = (resolution - 1) - ((p.y - yMin) * scale + yOffset);
            return (x: bx / (resolution - 1), y: by / (resolution - 1));
          }).toList();
        }).where((c) => c.length >= 2).toList();
      }

      // ── 阶段 1: 光栅化 ──
      final bitmap = OutlineRasterizer.rasterize(outline, resolution: 256, padding: 8);

      // ── 阶段 2: 骨架化 ──
      final skeleton = Skeletonizer.skeletonize(
        bitmap,
        preSpurPruneLen: preSpurPruneLen,
        tinyComponentSize: tinyComponentSize,
        bridgeGap: bridgeGap,
        postSpurPruneLen: postSpurPruneLen,
      );

      // ── 阶段 3: 向量化 ──
      final rawStrokes = SkeletonVectorizer.vectorize(skeleton, minStrokePixels: 4);

      // ── 阶段 4: 获取模板 ──
      final templateStrokePts = templates[ch] ?? [];

      // ── 阶段 5: 第一轮接链 ──
      final chainedStrokes = UserFontLoader.chainStrokesPublic(
        rawStrokes,
        targetCount: templateStrokePts.isNotEmpty ? templateStrokePts.length : null,
      );

      if (chainedStrokes.isEmpty) {
        return GlyphDebugData(
          character: ch,
          sampledContours: sampledContours,
          rasterBitmap: bitmap,
          skeletonBitmap: skeleton,
          rawVectorStrokes: rawStrokes,
          chainedStrokes: chainedStrokes,
          templateStrokes: templateStrokePts.isNotEmpty ? templateStrokePts : null,
          error: 'no skeleton strokes after chaining',
        );
      }

      // ── 阶段 6: 笔顺对齐 ──
      final aligned = StrokeOrderAligner.align(
        candidateStrokes: chainedStrokes,
        templateStrokes: templateStrokePts,
      );

      // ── 阶段 7: 第二轮补链 ──
      final repairedStrokes = UserFontLoader.chainStrokesPublic(
        aligned.orderedStrokes,
        mergeThreshold: 0.04,
        maxTurnDeg: 95.0,
        targetCount: templateStrokePts.isNotEmpty ? templateStrokePts.length : null,
      );

      // ── 阶段 8: 微碎段吸附 ──
      final finalizedStrokes = UserFontLoader.absorbTinyFragmentsPublic(
        repairedStrokes,
        targetCount: templateStrokePts.isNotEmpty ? templateStrokePts.length : null,
      );

      // ── 阶段 9: 最终 Glyph ──
      final rawStrokeModels = finalizedStrokes.map((sStroke) {
        final pts = sStroke.points.map((p) => Vec2(p.x, p.y)).toList();
        return Stroke(points: pts);
      }).toList();

      final mergedByType = UserFontLoader.mergeByStrokeTypePublic(
        rawStrokeModels,
        targetCount: templateStrokePts.isNotEmpty ? templateStrokePts.length : null,
      );

      final strokes = UserFontLoader.removeRedundantOverlapsPublic(
        mergedByType,
        targetCount: templateStrokePts.isNotEmpty ? templateStrokePts.length : null,
      );

      final glyph = strokes.isNotEmpty ? Glyph(character: ch, strokes: strokes) : null;

      return GlyphDebugData(
        character: ch,
        sampledContours: sampledContours,
        rasterBitmap: bitmap,
        skeletonBitmap: skeleton,
        rawVectorStrokes: rawStrokes,
        chainedStrokes: chainedStrokes,
        alignedStrokes: aligned.orderedStrokes,
        matchScore: aligned.matchScore,
        repairedStrokes: repairedStrokes,
        finalizedStrokes: finalizedStrokes,
        finalGlyph: glyph,
        templateStrokes: templateStrokePts.isNotEmpty ? templateStrokePts : null,
      );
    } catch (e) {
      return GlyphDebugData(character: ch, error: e.toString());
    }
  }

  // ── 模板数据加载 ──

  static Map<String, List<List<({double x, double y})>>>? _cachedTemplates;

  static Future<Map<String, List<List<({double x, double y})>>>> _loadTemplates() async {
    if (_cachedTemplates != null) return _cachedTemplates!;

    final result = <String, List<List<({double x, double y})>>>{};
    try {
      final jsonText = await rootBundle.loadString(
        'assets/fonts/makemeahanzi_standard.json',
      );
      final jsonObj = jsonDecode(jsonText) as Map<String, dynamic>;

      if (jsonObj.containsKey('characters')) {
        final chars = jsonObj['characters'] as Map<String, dynamic>;
        for (final entry in chars.entries) {
          final ch = entry.key;
          final data = entry.value as Map<String, dynamic>;
          final medians = data['medians'] as List<dynamic>?;
          if (medians == null) continue;

          final strokePts = <List<({double x, double y})>>[];
          for (final median in medians) {
            final pts = MakeMeAHanziConverter.parseMedians(median as List)
                .map((v) => (x: v.x, y: v.y))
                .toList();
            if (pts.length >= 2) strokePts.add(pts);
          }
          if (strokePts.isNotEmpty) result[ch] = strokePts;
        }
      } else if (jsonObj.containsKey('glyphs')) {
        final glyphs = jsonObj['glyphs'] as Map<String, dynamic>;
        for (final entry in glyphs.entries) {
          final ch = entry.key;
          final data = entry.value as Map<String, dynamic>;
          final strokes = data['strokes'] as List<dynamic>?;
          if (strokes == null) continue;

          final strokePts = <List<({double x, double y})>>[];
          for (final s in strokes) {
            if (s is List) {
              final pts = s.map((p) {
                final pair = p as List;
                return (x: (pair[0] as num).toDouble(), y: (pair[1] as num).toDouble());
              }).toList();
              if (pts.length >= 2) strokePts.add(pts);
            }
          }
          if (strokePts.isNotEmpty) result[ch] = strokePts;
        }
      }
    } catch (_) {}

    _cachedTemplates = result;
    return result;
  }
}
