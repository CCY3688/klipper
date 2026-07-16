/// 用户字体加载管线
///
/// 完整的 TTF → Glyph 处理链：
///   解析 TTF → 光栅化 → 骨架化 → 向量化 → 笔顺对齐 → UserFontProfile
///
/// 进度通过 [onProgress] 回调报告，支持提前取消（[cancel] 标志）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';

import '../font/makemeahanzi_converter.dart';
import '../model/geometry.dart';
import '../model/glyph.dart';
import '../model/stroke.dart';
import '../model/stroke_analyzer.dart';
import 'alignment/stroke_order_aligner.dart';
import 'skeleton/outline_rasterizer.dart';
import 'skeleton/skeleton_vectorizer.dart';
import 'skeleton/skeletonizer.dart';
import 'target_charset.dart';
import 'ttf/ttf_parser.dart';
import 'user_font_profile.dart';

/// 单字处理结果
class GlyphProcessResult {
  final String character;
  final Glyph? glyph;
  final double matchScore;
  final String? errorMessage;

  const GlyphProcessResult({
    required this.character,
    this.glyph,
    this.matchScore = 0,
    this.errorMessage,
  });

  bool get success => glyph != null;
}

/// 加载进度信息
class FontLoadProgress {
  final int current;
  final int total;
  final String currentChar;
  final bool done;
  final String? error;

  const FontLoadProgress({
    required this.current,
    required this.total,
    required this.currentChar,
    this.done = false,
    this.error,
  });

  double get ratio => total > 0 ? current / total : 0;
}

/// TTF 用户字体加载器（主入口）
class UserFontLoader {
  bool _cancelled = false;

  /// 取消正在进行的处理
  void cancel() => _cancelled = true;

  // ── 公开调试接口（供 GlyphDebugProcessor 调用） ────────────────────
  /// 公开版接链（代理到私有 _chainStrokes）
  static List<SkeletonStroke> chainStrokesPublic(
    List<SkeletonStroke> strokes, {
    double mergeThreshold = 0.06,
    double maxTurnDeg = 90.0,
    int? targetCount,
  }) =>
      _chainStrokes(strokes,
          mergeThreshold: mergeThreshold,
          maxTurnDeg: maxTurnDeg,
          targetCount: targetCount);

  /// 公开版碎段吸附（代理到私有 _absorbTinyFragments）
  static List<SkeletonStroke> absorbTinyFragmentsPublic(
    List<SkeletonStroke> strokes, {
    int? targetCount,
  }) =>
      _absorbTinyFragments(strokes, targetCount: targetCount);

  /// 公开版同类合并（代理到私有 _mergeByStrokeType）
  static List<Stroke> mergeByStrokeTypePublic(
    List<Stroke> strokes, {
    int? targetCount,
  }) =>
      _mergeByStrokeType(strokes, targetCount: targetCount);

  /// 公开版重复笔画去重（代理到私有 _removeRedundantOverlaps）
  static List<Stroke> removeRedundantOverlapsPublic(
    List<Stroke> strokes, {
    int? targetCount,
  }) =>
      _removeRedundantOverlaps(strokes, targetCount: targetCount);

  /// 从 TTF 文件构建 UserFontProfile
  ///
  /// [ttfFile]     TTF/OTF 字体文件
  /// [profileName] 档案显示名称
  /// [onProgress]  进度回调
  Future<UserFontProfile> loadFromTtf({
    required File ttfFile,
    required String profileName,
    void Function(FontLoadProgress)? onProgress,
  }) async {
    _cancelled = false;

    // ── 1. 解析 TTF ───────────────────────────────────────────────────
    final bytes = await ttfFile.readAsBytes();
    final ttf = TtfParser.parse(bytes);

    // ── 2. 加载 makemeahanzi 模板数据（medians）────────────────────────
    final templates = await _loadMakemeahanziTemplates();

    // ── 3. 确定要处理的字符列表 ─────────────────────────────────────────
    final targetChars = TargetCharset.all
        .where((ch) {
          final cp = ch.runes.first;
          return ttf.glyphIdForCodePoint(cp) != null;
        })
        .toList();

    final profile = UserFontProfile.createNew(
      name: profileName,
      source: FontSourceType.ttf,
      sourceFontFileName: ttfFile.uri.pathSegments.last,
    );
    profile.processingProgress = 0;

    final total = targetChars.length;

    onProgress?.call(FontLoadProgress(
      current: 0,
      total: total,
      currentChar: '',
    ));

    // ── 4. 逐字处理 ───────────────────────────────────────────────────
    for (int i = 0; i < targetChars.length; i++) {
      if (_cancelled) break;

      final ch = targetChars[i];

      onProgress?.call(FontLoadProgress(
        current: i,
        total: total,
        currentChar: ch,
      ));

      final result = _processChar(ch, ttf, templates);
      if (result.success) {
        profile.learnedGlyphs[ch] = result.glyph!;
      }

      // 每处理 50 字保存一次（断点续传）
      if (i % 50 == 0) {
        profile.processingProgress = i / total;
        await profile.save();
      }

      // 让出 UI 线程（避免卡顿）
      if (i % 10 == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    // ── 5. 最终保存 ───────────────────────────────────────────────────
    profile.processingProgress = 1.0;
    await profile.save();

    onProgress?.call(FontLoadProgress(
      current: total,
      total: total,
      currentChar: '',
      done: true,
    ));

    return profile;
  }

  // ─────────────────────────────────────────────────────────────────────
  // 单字处理
  // ─────────────────────────────────────────────────────────────────────

  GlyphProcessResult _processChar(
    String ch,
    TtfParser ttf,
    Map<String, List<List<({double x, double y})>>> templates,
  ) {
    try {
      // 获取 TTF 轮廓
      final outline = ttf.glyphOutlineForChar(ch);
      if (outline == null || outline.isEmpty) {
        return GlyphProcessResult(character: ch, errorMessage: 'no outline');
      }

      // 光栅化
      final bitmap = OutlineRasterizer.rasterize(outline, resolution: 256, padding: 8);

      // 骨架化（Zhang-Suen）
      final skeleton = Skeletonizer.skeletonize(bitmap);

      // 向量化
      final vectorStrokes = SkeletonVectorizer.vectorize(
        skeleton,
        minStrokePixels: 4,
      );

      // 获取模板（直接使用 Dict 中的采样点）
      final templateStrokePts = templates[ch] ?? [];

      // 将端点相邻的碎段接链，修复交叉点分割导致的笔画断裂问题
      final skeletonStrokes = _chainStrokes(
        vectorStrokes,
        targetCount: templateStrokePts.isNotEmpty ? templateStrokePts.length : null,
      );

      if (skeletonStrokes.isEmpty) {
        return GlyphProcessResult(character: ch, errorMessage: 'no skeleton strokes');
      }

      // 笔顺对齐
      final aligned = StrokeOrderAligner.align(
        candidateStrokes: skeletonStrokes,
        templateStrokes: templateStrokePts,
      );

      // 对齐后再做一轮补链，处理对齐保留的残余短碎段。
      final repairedStrokes = _chainStrokes(
        aligned.orderedStrokes,
        mergeThreshold: 0.04,
        maxTurnDeg: 95.0,
        targetCount: templateStrokePts.isNotEmpty ? templateStrokePts.length : null,
      );

      // 最终微碎段吸附：把极短残段并入邻近主笔画，减少末端点状断链。
      final finalizedStrokes = _absorbTinyFragments(
        repairedStrokes,
        targetCount: templateStrokePts.isNotEmpty ? templateStrokePts.length : null,
      );

      // 转换为 Glyph（骨架坐标 → Vec2，坐标系 Y 轴已在光栅化时翻转）
      final rawStrokeModels = finalizedStrokes.map((sStroke) {
        final pts = sStroke.points.map((p) => Vec2(p.x, p.y)).toList();
        return Stroke(points: pts);
      }).toList();

      // 基于笔画类型进行同类合并，减少一次笔画被切成多段导致的多次抬笔。
      final mergedByType = _mergeByStrokeType(
        rawStrokeModels,
        targetCount: templateStrokePts.isNotEmpty ? templateStrokePts.length : null,
      );

      // 去重：删除被主笔画覆盖的重复短段（例如同一撇上重复生成的子段）。
      final strokes = _removeRedundantOverlaps(
        mergedByType,
        targetCount: templateStrokePts.isNotEmpty ? templateStrokePts.length : null,
      );

      if (strokes.isEmpty) {
        return GlyphProcessResult(character: ch, errorMessage: 'empty strokes after align');
      }

      final glyph = Glyph(character: ch, strokes: strokes);

      return GlyphProcessResult(
        character: ch,
        glyph: glyph,
        matchScore: aligned.matchScore,
      );
    } catch (e) {
      return GlyphProcessResult(character: ch, errorMessage: e.toString());
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // 笔画接链工具
  // ─────────────────────────────────────────────────────────────────────

  /// 将端点相邻的碎段接链成自然笔画。
  ///
  /// 升级策略：方向感知选优
  /// - 每轮遍历所有 (i, j, flipI, flipJ) 组合，计算接合后的转角
  /// - 优先选择转角最小（方向最连续）的接合，跳过转角 > maxTurnDeg 的组合
  /// - 这样可避免在三叉路口把两段不同笔画错误拼接
  static List<SkeletonStroke> _chainStrokes(
    List<SkeletonStroke> strokes, {
    double mergeThreshold = 0.06, // ≈ 11 px @ 192×192，覆盖交叉点附近像素
    double maxTurnDeg = 90.0,     // 超过此转角认为是不同笔画，拒绝接链
    int? targetCount,
  }) {
    if (strokes.length <= 1) return strokes;

    final chains = strokes
        .map((s) => List<({double x, double y})>.from(s.points))
        .toList();

    bool anyMerge = true;
    while (anyMerge) {
      anyMerge = false;

      double bestScore = double.infinity;
      int bestI = -1, bestJ = -1;
      bool bestFlipI = false, bestFlipJ = false;

      for (int i = 0; i < chains.length; i++) {
        for (int j = 0; j < chains.length; j++) {
          if (i == j) continue;

          // flipI=false → tail = chains[i].last
          // flipI=true  → tail = chains[i].first (chain i will be reversed)
          for (final flipI in [false, true]) {
            for (final flipJ in [false, true]) {
              final tail = flipI ? chains[i].first : chains[i].last;
              final head = flipJ ? chains[j].last  : chains[j].first;

              final d = _ptDist(tail, head);
              if (d > mergeThreshold) continue;

              final angle = _junctionAngle(chains[i], flipI, chains[j], flipJ);
              if (angle > maxTurnDeg) continue;

              // Score: weight angle heavily (主因) + distance (次因)
              final score = angle + d / mergeThreshold * 20.0;
              if (score < bestScore) {
                bestScore = score;
                bestI = i; bestJ = j;
                bestFlipI = flipI; bestFlipJ = flipJ;
              }
            }
          }
        }
      }

      if (bestI != -1) {
        final ci = bestFlipI ? chains[bestI].reversed.toList() : chains[bestI];
        final cj = bestFlipJ ? chains[bestJ].reversed.toList() : chains[bestJ];
        final merged = _mergeChainPoints(ci, cj);

        // Remove higher index first to keep lower index valid
        final hi = bestI > bestJ ? bestI : bestJ;
        final lo = bestI < bestJ ? bestI : bestJ;
        chains.removeAt(hi);
        chains.removeAt(lo);
        chains.insert(lo, merged);

        anyMerge = true;
      } else {
        // 普通阈值无法继续合并。
        // 先尝试"交叉点接链"：端点几乎重合（同一交叉像素）的片段，
        // 使用更宽松的转角阈值合并。这解决了 chains.length == targetCount
        // 但仍有交叉点分裂残留的情况（如"大"的捺被分成两段）。
        const junctionDist = 0.025; // ≈ 6 px @ 256，交叉点共享像素范围
        const junctionMaxTurnDeg = 120.0; // 交叉点处允许更大转角

        double bestJuncScore = double.infinity;
        int juncI = -1, juncJ = -1;
        bool juncFlipI = false, juncFlipJ = false;

        for (int i = 0; i < chains.length; i++) {
          for (int j = 0; j < chains.length; j++) {
            if (i == j) continue;

            for (final flipI in [false, true]) {
              for (final flipJ in [false, true]) {
                final tail = flipI ? chains[i].first : chains[i].last;
                final head = flipJ ? chains[j].last : chains[j].first;

                final d = _ptDist(tail, head);
                if (d > junctionDist) continue;

                final angle = _junctionAngle(chains[i], flipI, chains[j], flipJ);
                if (angle > junctionMaxTurnDeg) continue;

                final score = angle + d / junctionDist * 15.0;
                if (score < bestJuncScore) {
                  bestJuncScore = score;
                  juncI = i; juncJ = j;
                  juncFlipI = flipI; juncFlipJ = flipJ;
                }
              }
            }
          }
        }

        if (juncI != -1) {
          final ci = juncFlipI ? chains[juncI].reversed.toList() : chains[juncI];
          final cj = juncFlipJ ? chains[juncJ].reversed.toList() : chains[juncJ];
          final merged = _mergeChainPoints(ci, cj);

          final hi = juncI > juncJ ? juncI : juncJ;
          final lo = juncI < juncJ ? juncI : juncJ;
          chains.removeAt(hi);
          chains.removeAt(lo);
          chains.insert(lo, merged);

          anyMerge = true;
        } else if (targetCount != null && chains.length > targetCount) {
          // 交叉点接链也无法继续，但片段数仍多于模板笔画数：
          // 启用"受控强制合并"以减少断续碎段。
          const forceMergeMaxDist = 0.25; // 归一化坐标，约 64 px @ 256

          double bestForceScore = double.infinity;
          int forceI = -1, forceJ = -1;
          bool forceFlipI = false, forceFlipJ = false;

          for (int i = 0; i < chains.length; i++) {
            for (int j = 0; j < chains.length; j++) {
              if (i == j) continue;

              for (final flipI in [false, true]) {
                for (final flipJ in [false, true]) {
                  final tail = flipI ? chains[i].first : chains[i].last;
                  final head = flipJ ? chains[j].last : chains[j].first;

                  final d = _ptDist(tail, head);
                  if (d > forceMergeMaxDist) continue;

                  final angle = _junctionAngle(chains[i], flipI, chains[j], flipJ);
                  final score = angle * 1.5 + d / forceMergeMaxDist * 25.0;

                  if (score < bestForceScore) {
                    bestForceScore = score;
                    forceI = i;
                    forceJ = j;
                    forceFlipI = flipI;
                    forceFlipJ = flipJ;
                  }
                }
              }
            }
          }

          if (forceI != -1) {
            final ci = forceFlipI ? chains[forceI].reversed.toList() : chains[forceI];
            final cj = forceFlipJ ? chains[forceJ].reversed.toList() : chains[forceJ];
            final merged = _mergeChainPoints(ci, cj);

            final hi = forceI > forceJ ? forceI : forceJ;
            final lo = forceI < forceJ ? forceI : forceJ;
            chains.removeAt(hi);
            chains.removeAt(lo);
            chains.insert(lo, merged);

            anyMerge = true;
          }
        }
      }
    }

    return chains.map((c) => SkeletonStroke(c)).toList();
  }

  /// 计算接链处的转角（度）——使用多点窗口估计切线方向
  ///
  /// 在骨架交叉点附近，像素位置有量化噪声，仅用最近 2 个点计算切线
  /// 会产生严重偏差。使用 [span] 个点的跨度方向可显著降低噪声，
  /// 避免把同一笔画的两段误判为不同笔画而拒绝接链。
  static double _junctionAngle(
    List<({double x, double y})> ci, bool flipI,
    List<({double x, double y})> cj, bool flipJ,
  ) {
    if (ci.length < 2 || cj.length < 2) return 0;

    const span = 5;

    // Tangent leaving i's tail (pointing away from i)
    final ({double x, double y}) ti;
    if (!flipI) {
      final k = math.max(0, ci.length - span);
      ti = _unitVec(ci.last.x - ci[k].x, ci.last.y - ci[k].y);
    } else {
      final k = math.min(ci.length - 1, span - 1);
      ti = _unitVec(ci.first.x - ci[k].x, ci.first.y - ci[k].y);
    }

    // Tangent entering j's head (pointing into j)
    final ({double x, double y}) tj;
    if (!flipJ) {
      final k = math.min(cj.length - 1, span - 1);
      tj = _unitVec(cj[k].x - cj.first.x, cj[k].y - cj.first.y);
    } else {
      final k = math.max(0, cj.length - span);
      tj = _unitVec(cj[k].x - cj.last.x, cj[k].y - cj.last.y);
    }

    final dot = (ti.x * tj.x + ti.y * tj.y).clamp(-1.0, 1.0);
    return math.acos(dot) * 180.0 / math.pi;
  }

  static ({double x, double y}) _unitVec(double dx, double dy) {
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-9) return (x: 1, y: 0);
    return (x: dx / len, y: dy / len);
  }

  static double _ptDist(
    ({double x, double y}) a,
    ({double x, double y}) b,
  ) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  static List<({double x, double y})> _mergeChainPoints(
    List<({double x, double y})> first,
    List<({double x, double y})> second,
  ) {
    if (first.isEmpty) return List<({double x, double y})>.from(second);
    if (second.isEmpty) return List<({double x, double y})>.from(first);

    final out = <({double x, double y})>[...first];
    if (_ptDist(first.last, second.first) > 1e-9) {
      out.add(second.first);
    }
    out.addAll(second.skip(1));
    return out;
  }

  static List<Stroke> _mergeByStrokeType(
    List<Stroke> strokes, {
    int? targetCount,
  }) {
    if (strokes.length <= 1) {
      return strokes
          .map((s) => Stroke(points: s.points, type: s.type ?? _strokeAnalyzer.inferType(s)))
          .toList();
    }

    final working = strokes
        .map((s) => Stroke(points: s.points, type: s.type ?? _strokeAnalyzer.inferType(s)))
        .toList();

    bool merged = true;
    while (merged) {
      merged = false;

      double bestScore = double.infinity;
      int bestI = -1;
      int bestJ = -1;
      bool bestFlipI = false;
      bool bestFlipJ = false;

      final relax = targetCount != null && working.length > targetCount;

      for (int i = 0; i < working.length; i++) {
        for (int j = i + 1; j < working.length; j++) {
          final ti = working[i].type ?? _strokeAnalyzer.inferType(working[i]);
          final tj = working[j].type ?? _strokeAnalyzer.inferType(working[j]);
          if (ti != tj) continue;
          if (!_isMergeFriendlyType(ti)) continue;

          final maxGap = _maxGapForType(ti, relax: relax);
          final maxTurnDeg = relax ? 95.0 : 70.0;

          for (final flipI in [false, true]) {
            for (final flipJ in [false, true]) {
              final tail = flipI ? working[i].points.first : working[i].points.last;
              final head = flipJ ? working[j].points.last : working[j].points.first;

              final d = _vecDist(tail, head);
              if (d > maxGap) continue;

              final angle = _strokeJunctionAngle(working[i], flipI, working[j], flipJ);
              if (angle > maxTurnDeg) continue;

              final orderPenalty = (j - i) * 0.8;
              final score = angle + (d / maxGap) * 25.0 + orderPenalty;
              if (score < bestScore) {
                bestScore = score;
                bestI = i;
                bestJ = j;
                bestFlipI = flipI;
                bestFlipJ = flipJ;
              }
            }
          }
        }
      }

      if (bestI == -1) break;

      final first = bestFlipI
          ? working[bestI].points.reversed.toList()
          : List<Vec2>.from(working[bestI].points);
      final second = bestFlipJ
          ? working[bestJ].points.reversed.toList()
          : List<Vec2>.from(working[bestJ].points);

      final mergedStroke = Stroke(
        points: _mergeStrokePoints(first, second),
        type: working[bestI].type,
      );

      working[bestI] = mergedStroke;
      working.removeAt(bestJ);
      merged = true;
    }

    return working
        .map((s) => Stroke(points: s.points, type: s.type ?? _strokeAnalyzer.inferType(s)))
        .toList();
  }

  static bool _isMergeFriendlyType(StrokeType type) {
    return type == StrokeType.horizontal ||
        type == StrokeType.vertical ||
        type == StrokeType.leftFalling ||
        type == StrokeType.rightFalling ||
        type == StrokeType.turning;
  }

  static double _maxGapForType(StrokeType type, {required bool relax}) {
    final base = switch (type) {
      StrokeType.leftFalling => 0.14,
      StrokeType.rightFalling => 0.14,
      StrokeType.horizontal => 0.09,
      StrokeType.vertical => 0.09,
      StrokeType.turning => 0.08,
      StrokeType.hook => 0.06,
      StrokeType.dot => 0.04,
      StrokeType.other => 0.06,
    };
    return relax ? base * 1.2 : base;
  }

  static double _strokeJunctionAngle(
    Stroke first,
    bool flipFirst,
    Stroke second,
    bool flipSecond,
  ) {
    if (first.points.length < 2 || second.points.length < 2) return 180.0;

    const span = 4;

    ({double x, double y}) outVec() {
      if (!flipFirst) {
        final k = math.max(0, first.points.length - span);
        return _unitVec2(
          first.points.last.x - first.points[k].x,
          first.points.last.y - first.points[k].y,
        );
      }
      final k = math.min(first.points.length - 1, span - 1);
      return _unitVec2(
        first.points.first.x - first.points[k].x,
        first.points.first.y - first.points[k].y,
      );
    }

    ({double x, double y}) inVec() {
      if (!flipSecond) {
        final k = math.min(second.points.length - 1, span - 1);
        return _unitVec2(
          second.points[k].x - second.points.first.x,
          second.points[k].y - second.points.first.y,
        );
      }
      final k = math.max(0, second.points.length - span);
      return _unitVec2(
        second.points[k].x - second.points.last.x,
        second.points[k].y - second.points.last.y,
      );
    }

    final ov = outVec();
    final iv = inVec();
    final dot = (ov.x * iv.x + ov.y * iv.y).clamp(-1.0, 1.0);
    return math.acos(dot) * 180.0 / math.pi;
  }

  static ({double x, double y}) _unitVec2(double dx, double dy) {
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-9) return (x: 1.0, y: 0.0);
    return (x: dx / len, y: dy / len);
  }

  static double _vecDist(Vec2 a, Vec2 b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  static List<Vec2> _mergeStrokePoints(List<Vec2> first, List<Vec2> second) {
    if (first.isEmpty) return List<Vec2>.from(second);
    if (second.isEmpty) return List<Vec2>.from(first);

    final out = <Vec2>[...first];
    if (_vecDist(first.last, second.first) > 1e-9) {
      out.add(second.first);
    }
    out.addAll(second.skip(1));
    return out;
  }

  static List<Stroke> _removeRedundantOverlaps(
    List<Stroke> strokes, {
    int? targetCount,
  }) {
    if (strokes.length <= 1) return strokes;

    final keep = List<bool>.filled(strokes.length, true);
    final sortedByLength = List<int>.generate(strokes.length, (i) => i)
      ..sort((a, b) => strokes[b].pathLength.compareTo(strokes[a].pathLength));

    final relax = targetCount != null && strokes.length > targetCount;
    final distThreshold = relax ? 0.026 : 0.020;
    final coverageThreshold = relax ? 0.70 : 0.80;
    final maxLenRatio = relax ? 0.98 : 0.94;

    for (final majorIdx in sortedByLength) {
      if (!keep[majorIdx]) continue;
      final major = strokes[majorIdx];

      for (final minorIdx in sortedByLength.reversed) {
        if (!keep[minorIdx] || minorIdx == majorIdx) continue;
        final minor = strokes[minorIdx];

        if (minor.pathLength >= major.pathLength * maxLenRatio) continue;
        if (_isRedundantStroke(
          minor,
          major,
          distThreshold: distThreshold,
          coverageThreshold: coverageThreshold,
        )) {
          keep[minorIdx] = false;
        }
      }
    }

    return [
      for (int i = 0; i < strokes.length; i++)
        if (keep[i]) strokes[i],
    ];
  }

  static bool _isRedundantStroke(
    Stroke minor,
    Stroke major, {
    required double distThreshold,
    required double coverageThreshold,
  }) {
    if (minor.points.length < 2 || major.points.length < 2) return false;

    int covered = 0;
    double maxDist = 0;
    double sumDist = 0;

    for (final p in minor.points) {
      final d = _pointToPolylineDistance(p, major.points);
      sumDist += d;
      if (d <= distThreshold) covered++;
      if (d > maxDist) maxDist = d;
    }

    final coverage = covered / minor.points.length;
    final meanDist = sumDist / minor.points.length;
    if (coverage < coverageThreshold) return false;
    if (meanDist > distThreshold * 0.85) return false;
    if (maxDist > distThreshold * 1.8) return false;

    final dirCos = _strokeDirectionCos(minor, major).abs();
    if (dirCos < 0.78) return false;

    final endA = _pointToPolylineDistance(minor.points.first, major.points);
    final endB = _pointToPolylineDistance(minor.points.last, major.points);
    if (math.min(endA, endB) > distThreshold * 1.35) return false;

    return true;
  }

  static double _strokeDirectionCos(Stroke a, Stroke b) {
    final adx = a.endPoint.x - a.startPoint.x;
    final ady = a.endPoint.y - a.startPoint.y;
    final bdx = b.endPoint.x - b.startPoint.x;
    final bdy = b.endPoint.y - b.startPoint.y;
    final al = math.sqrt(adx * adx + ady * ady);
    final bl = math.sqrt(bdx * bdx + bdy * bdy);
    if (al < 1e-9 || bl < 1e-9) return 0;
    return (adx * bdx + ady * bdy) / (al * bl);
  }

  static double _pointToPolylineDistance(Vec2 p, List<Vec2> polyline) {
    if (polyline.length == 1) return _vecDist(p, polyline.first);

    double best = double.infinity;
    for (int i = 1; i < polyline.length; i++) {
      final d = _pointToSegmentDistance(p, polyline[i - 1], polyline[i]);
      if (d < best) best = d;
    }
    return best;
  }

  static double _pointToSegmentDistance(Vec2 p, Vec2 a, Vec2 b) {
    final abx = b.x - a.x;
    final aby = b.y - a.y;
    final apx = p.x - a.x;
    final apy = p.y - a.y;

    final len2 = abx * abx + aby * aby;
    if (len2 <= 1e-12) return _vecDist(p, a);

    var t = (apx * abx + apy * aby) / len2;
    t = t.clamp(0.0, 1.0);

    final proj = Vec2(a.x + abx * t, a.y + aby * t);
    return _vecDist(p, proj);
  }

  static const StrokeAnalyzer _strokeAnalyzer = StrokeAnalyzer();

  /// 将极短碎段吸附到邻近主笔画。
  static List<SkeletonStroke> _absorbTinyFragments(
    List<SkeletonStroke> strokes, {
    int? targetCount,
  }) {
    if (strokes.length <= 1) return strokes;

    final tiny = <List<({double x, double y})>>[];
    final normal = <List<({double x, double y})>>[];

    bool isTiny(List<({double x, double y})> pts) {
      if (pts.length <= 3) return true;
      double len = 0;
      for (int i = 1; i < pts.length; i++) {
        len += _ptDist(pts[i - 1], pts[i]);
      }
      return len < 0.10;
    }

    for (final s in strokes) {
      final pts = List<({double x, double y})>.from(s.points);
      if (isTiny(pts)) {
        tiny.add(pts);
      } else {
        normal.add(pts);
      }
    }

    if (tiny.isEmpty || normal.isEmpty) return strokes;

    const maxAttachDist = 0.06;

    for (final frag in tiny) {
      double bestDist = double.infinity;
      int bestHost = -1;
      bool bestFlipHost = false;
      bool bestFlipFrag = false;

      for (int i = 0; i < normal.length; i++) {
        for (final flipHost in [false, true]) {
          for (final flipFrag in [false, true]) {
            final hostTail = flipHost ? normal[i].first : normal[i].last;
            final fragHead = flipFrag ? frag.last : frag.first;
            final d = _ptDist(hostTail, fragHead);
            if (d < bestDist) {
              bestDist = d;
              bestHost = i;
              bestFlipHost = flipHost;
              bestFlipFrag = flipFrag;
            }
          }
        }
      }

      if (bestHost != -1 && bestDist <= maxAttachDist) {
        final host = bestFlipHost ? normal[bestHost].reversed.toList() : normal[bestHost];
        final append = bestFlipFrag ? frag.reversed.toList() : frag;
        normal[bestHost] = _mergeChainPoints(host, append);
      } else {
        normal.add(frag);
      }
    }

    var merged = normal.map((p) => SkeletonStroke(p)).toList();
    if (targetCount != null && merged.length > targetCount) {
      merged = _chainStrokes(
        merged,
        mergeThreshold: 0.05,
        maxTurnDeg: 110.0,
        targetCount: targetCount,
      );
    }
    return merged;
  }

  // ─────────────────────────────────────────────────────────────────────
  // 模板数据加载
  // ─────────────────────────────────────────────────────────────────────

  static Map<String, List<List<({double x, double y})>>>? _cachedTemplates;

  static Future<Map<String, List<List<({double x, double y})>>>> _loadMakemeahanziTemplates() async {
    if (_cachedTemplates != null) return _cachedTemplates!;

    final result = <String, List<List<({double x, double y})>>>{};

    try {
      final jsonText = await rootBundle.loadString(
        'assets/fonts/makemeahanzi_standard.json',
      );
      final jsonObj = jsonDecode(jsonText) as Map<String, dynamic>;

      // makemeahanzi 格式：
      // { "characters": { "一": { "medians": [[[x,y],...]], ... } } }
      // 或 NDJSON（每行一个 JSON）
      if (jsonObj.containsKey('characters')) {
        _parseCharacterMap(jsonObj['characters'] as Map<String, dynamic>, result);
      } else if (jsonObj.containsKey('glyphs')) {
        // 已转换格式中，strokes 就是中心线点列表
        _parseGlyphsMap(jsonObj['glyphs'] as Map<String, dynamic>, result);
      }
    } catch (_) {
      // 模板加载失败：回退到无模板模式（仅启发式排序）
    }

    _cachedTemplates = result;
    return result;
  }

  static void _parseCharacterMap(
    Map<String, dynamic> chars,
    Map<String, List<List<({double x, double y})>>> out,
  ) {
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
      if (strokePts.isNotEmpty) out[ch] = strokePts;
    }
  }

  static void _parseGlyphsMap(
    Map<String, dynamic> glyphs,
    Map<String, List<List<({double x, double y})>>> out,
  ) {
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
      if (strokePts.isNotEmpty) out[ch] = strokePts;
    }
  }
}
