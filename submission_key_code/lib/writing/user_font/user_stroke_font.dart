/// 用户笔画字体适配器
///
/// 将 UserFontProfile 包装为 StrokeFont 子类，使其可无缝替换标准字库。
/// 对于 Profile 中未学习的字符，自动回退到标准字体。
library;

import 'dart:math' as math;

import '../font/stroke_font.dart';
import '../model/geometry.dart';
import '../model/glyph.dart';
import '../model/stroke.dart';
import '../model/stroke_analyzer.dart';
import 'user_font_profile.dart';

/// 用户自定义字体（支持回退到标准字体）
class UserStrokeFont extends StrokeFont {
  final UserFontProfile profile;
  final StrokeFont? fallback;
  final Map<String, Glyph> _repairedCache = {};
  final Map<String, Glyph> _repairedSourceCache = {};

  UserStrokeFont({required this.profile, this.fallback})
    : super.fromGlyphs(profile.learnedGlyphs);

  /// 字体显示名称
  String get displayName => profile.name;

  /// 已学习字符数
  int get learnedCount => profile.learnedCount;

  @override
  Glyph? richGlyphOf(String ch) {
    if (_preferFallbackGlyph(ch)) {
      final fallbackGlyph = fallback?.richGlyphOf(ch);
      if (fallbackGlyph != null) return fallbackGlyph;
    }

    // 优先返回用户字体
    final userGlyph = profile.learnedGlyphs[ch];
    if (userGlyph != null) {
      final cached = _repairedCache[ch];
      final cachedSource = _repairedSourceCache[ch];
      if (cached != null && identical(cachedSource, userGlyph)) {
        return cached;
      }

      final repaired = _repairGlyph(userGlyph);
      _repairedCache[ch] = repaired;
      _repairedSourceCache[ch] = userGlyph;
      return repaired;
    }

    _repairedCache.remove(ch);
    _repairedSourceCache.remove(ch);

    // 回退到标准字体
    return fallback?.richGlyphOf(ch);
  }

  bool _preferFallbackGlyph(String ch) {
    if (ch.length != 1) return false;
    final code = ch.codeUnitAt(0);
    return code >= 0x21 && code <= 0x7E;
  }

  @override
  StrokeGlyph? glyphOf(String ch) {
    final glyph = richGlyphOf(ch);
    if (glyph == null) return null;
    return StrokeGlyph.fromGlyph(glyph);
  }

  @override
  Iterable<String> get characters {
    final chars = <String>{};
    chars.addAll(profile.learnedGlyphs.keys);
    if (fallback != null) chars.addAll(fallback!.characters);
    return chars;
  }

  @override
  int get length => characters.length;

  Glyph _repairGlyph(Glyph glyph) {
    if (glyph.strokes.length <= 1) return glyph;

    final chains = <List<Vec2>>[];
    final chainTypes = <StrokeType>[];

    for (final stroke in glyph.strokes) {
      if (stroke.points.length < 2) continue;
      chains.add(List<Vec2>.from(stroke.points));
      chainTypes.add(stroke.type ?? _strokeAnalyzer.inferType(stroke));
    }

    if (chains.length <= 1) return glyph;

    const maxGap = 0.065;
    const maxTurnDeg = 115.0;

    bool merged = true;
    while (merged) {
      merged = false;

      double bestScore = double.infinity;
      int bestI = -1;
      int bestJ = -1;
      bool bestFlipI = false;
      bool bestFlipJ = false;

      for (int i = 0; i < chains.length; i++) {
        for (int j = 0; j < chains.length; j++) {
          if (i == j) continue;
          if (chainTypes[i] != chainTypes[j]) continue;
          if (!_isMergeFriendlyType(chainTypes[i])) continue;

          for (final flipI in [false, true]) {
            for (final flipJ in [false, true]) {
              final tail = flipI ? chains[i].first : chains[i].last;
              final head = flipJ ? chains[j].last : chains[j].first;

              final dist = _distance(tail, head);
              if (dist > maxGap) continue;

              final angle = _junctionAngle(chains[i], flipI, chains[j], flipJ);
              if (angle > maxTurnDeg) continue;

              final score = angle + dist / maxGap * 20.0;
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

      final first = bestFlipI ? chains[bestI].reversed.toList() : chains[bestI];
      final second = bestFlipJ
          ? chains[bestJ].reversed.toList()
          : chains[bestJ];

      final bridged = <Vec2>[...first];
      if (_distance(first.last, second.first) > 1e-6) {
        bridged.add(second.first);
      }
      bridged.addAll(second.skip(1));

      final hi = bestI > bestJ ? bestI : bestJ;
      final lo = bestI < bestJ ? bestI : bestJ;
      final mergedType = chainTypes[lo];

      chains.removeAt(hi);
      chains.removeAt(lo);
      chains.insert(lo, bridged);

      chainTypes.removeAt(hi);
      chainTypes.removeAt(lo);
      chainTypes.insert(lo, mergedType);

      merged = true;
    }

    final repairedStrokes = <Stroke>[];
    for (int i = 0; i < chains.length; i++) {
      final pts = chains[i];
      if (pts.length < 2 || _polylineLength(pts) < 0.015) continue;
      repairedStrokes.add(Stroke(points: pts, type: chainTypes[i]));
    }

    if (repairedStrokes.isEmpty) return glyph;

    final dedupedStrokes = _removeRedundantOverlaps(repairedStrokes);
    if (dedupedStrokes.isEmpty) return glyph;

    return Glyph(
      character: glyph.character,
      strokes: dedupedStrokes,
      aspectRatio: glyph.aspectRatio,
    );
  }

  /// 计算接链处的转角——使用多点窗口估计切线方向，减少骨架噪声
  double _junctionAngle(
    List<Vec2> first,
    bool flipFirst,
    List<Vec2> second,
    bool flipSecond,
  ) {
    if (first.length < 2 || second.length < 2) return 0;

    const span = 5;

    final outVec = !flipFirst
        ? () {
            final k = math.max(0, first.length - span);
            return _unit(first.last.x - first[k].x, first.last.y - first[k].y);
          }()
        : () {
            final k = math.min(first.length - 1, span - 1);
            return _unit(
              first.first.x - first[k].x,
              first.first.y - first[k].y,
            );
          }();

    final inVec = !flipSecond
        ? () {
            final k = math.min(second.length - 1, span - 1);
            return _unit(
              second[k].x - second.first.x,
              second[k].y - second.first.y,
            );
          }()
        : () {
            final k = math.max(0, second.length - span);
            return _unit(
              second[k].x - second.last.x,
              second[k].y - second.last.y,
            );
          }();

    final dot = (outVec.x * inVec.x + outVec.y * inVec.y).clamp(-1.0, 1.0);
    return math.acos(dot) * 180 / math.pi;
  }

  ({double x, double y}) _unit(double dx, double dy) {
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-9) return (x: 1, y: 0);
    return (x: dx / len, y: dy / len);
  }

  double _distance(Vec2 a, Vec2 b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _polylineLength(List<Vec2> pts) {
    double length = 0;
    for (int i = 1; i < pts.length; i++) {
      length += _distance(pts[i - 1], pts[i]);
    }
    return length;
  }

  bool _isMergeFriendlyType(StrokeType type) {
    return type == StrokeType.horizontal ||
        type == StrokeType.vertical ||
        type == StrokeType.leftFalling ||
        type == StrokeType.rightFalling ||
        type == StrokeType.turning;
  }

  List<Stroke> _removeRedundantOverlaps(List<Stroke> strokes) {
    if (strokes.length <= 1) return strokes;

    const distThreshold = 0.020;
    const coverageThreshold = 0.80;
    const maxLenRatio = 0.94;

    final keep = List<bool>.filled(strokes.length, true);
    final sortedByLength = List<int>.generate(strokes.length, (i) => i)
      ..sort((a, b) => strokes[b].pathLength.compareTo(strokes[a].pathLength));

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

  bool _isRedundantStroke(
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

  double _strokeDirectionCos(Stroke a, Stroke b) {
    final adx = a.endPoint.x - a.startPoint.x;
    final ady = a.endPoint.y - a.startPoint.y;
    final bdx = b.endPoint.x - b.startPoint.x;
    final bdy = b.endPoint.y - b.startPoint.y;
    final al = math.sqrt(adx * adx + ady * ady);
    final bl = math.sqrt(bdx * bdx + bdy * bdy);
    if (al < 1e-9 || bl < 1e-9) return 0;
    return (adx * bdx + ady * bdy) / (al * bl);
  }

  double _pointToPolylineDistance(Vec2 p, List<Vec2> polyline) {
    if (polyline.length == 1) return _distance(p, polyline.first);

    double best = double.infinity;
    for (int i = 1; i < polyline.length; i++) {
      final d = _pointToSegmentDistance(p, polyline[i - 1], polyline[i]);
      if (d < best) best = d;
    }
    return best;
  }

  double _pointToSegmentDistance(Vec2 p, Vec2 a, Vec2 b) {
    final abx = b.x - a.x;
    final aby = b.y - a.y;
    final apx = p.x - a.x;
    final apy = p.y - a.y;

    final len2 = abx * abx + aby * aby;
    if (len2 <= 1e-12) return _distance(p, a);

    var t = (apx * abx + apy * aby) / len2;
    t = t.clamp(0.0, 1.0);

    final proj = Vec2(a.x + abx * t, a.y + aby * t);
    return _distance(p, proj);
  }

  static const StrokeAnalyzer _strokeAnalyzer = StrokeAnalyzer();
}
