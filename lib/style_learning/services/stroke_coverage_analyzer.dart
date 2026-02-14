import '../../writing/font/stroke_font.dart';
import '../../writing/model/stroke.dart';
import '../models/sample_template.dart';

/// 笔画覆盖率分析器
///
/// 分析模板字符集对各种笔画类型的覆盖程度，
/// 帮助选择能最大化笔画覆盖的字符集合。
class StrokeCoverageAnalyzer {
  final StrokeFont font;

  StrokeCoverageAnalyzer(this.font);

  /// 分析一组字符的笔画覆盖情况
  CoverageReport analyze(List<String> characters) {
    final typeCounts = <StrokeType, int>{};
    final charDetails = <String, List<StrokeType>>{};

    for (final ch in characters) {
      final glyph = font.richGlyphOf(ch);
      if (glyph == null) continue;

      final types = <StrokeType>[];
      for (final stroke in glyph.strokes) {
        final type = stroke.type ?? StrokeType.other;
        types.add(type);
        typeCounts[type] = (typeCounts[type] ?? 0) + 1;
      }
      charDetails[ch] = types;
    }

    // 检查缺失的笔画类型
    final allTypes = StrokeType.values.toSet();
    final coveredTypes = typeCounts.keys.toSet();
    final missingTypes = allTypes.difference(coveredTypes);

    return CoverageReport(
      characters: characters,
      strokeTypeCounts: typeCounts,
      characterStrokeTypes: charDetails,
      missingTypes: missingTypes.toList(),
      totalStrokes: typeCounts.values.fold(0, (a, b) => a + b),
    );
  }

  /// 分析现有模板的覆盖情况
  CoverageReport analyzeTemplate(SampleTemplate template) {
    return analyze(template.characters);
  }

  /// 从字库中选择覆盖率最好的 n 个字符
  ///
  /// 使用贪心集合覆盖算法：
  /// 每轮选择能覆盖最多「尚未充分覆盖」的笔画类型的字符。
  /// [minPerType] 每种笔画至少出现的次数。
  List<String> selectOptimalCharacters({
    int maxCount = 20,
    int minPerType = 3,
    List<String>? candidateChars,
  }) {
    // 准备候选字符
    final candidates = candidateChars ?? font.characters.toList();
    final selected = <String>[];
    final typeCounts = <StrokeType, int>{};

    // 初始化：所有类型的计数为 0
    for (final type in StrokeType.values) {
      typeCounts[type] = 0;
    }

    // 预计算每个候选字符的笔画类型
    final charTypes = <String, List<StrokeType>>{};
    for (final ch in candidates) {
      final glyph = font.richGlyphOf(ch);
      if (glyph == null || glyph.isEmpty) continue;

      final types = glyph.strokes
          .map((s) => s.type ?? StrokeType.other)
          .toList();
      if (types.isNotEmpty) {
        charTypes[ch] = types;
      }
    }

    // 贪心选择
    while (selected.length < maxCount && charTypes.isNotEmpty) {
      // 找出覆盖得分最高的字符
      String? bestChar;
      double bestScore = -1;

      for (final entry in charTypes.entries) {
        double score = 0;
        for (final type in entry.value) {
          final currentCount = typeCounts[type] ?? 0;
          if (currentCount < minPerType) {
            // 尚未充分覆盖的类型得分更高
            score += (minPerType - currentCount).toDouble();
          } else {
            // 已充分覆盖的类型仍有微小贡献
            score += 0.1;
          }
        }
        // 稍微偏好笔画较多的字（信息量更大）
        score += entry.value.length * 0.05;

        if (score > bestScore) {
          bestScore = score;
          bestChar = entry.key;
        }
      }

      if (bestChar == null) break;

      selected.add(bestChar);
      // 更新覆盖计数
      for (final type in charTypes[bestChar]!) {
        typeCounts[type] = (typeCounts[type] ?? 0) + 1;
      }
      charTypes.remove(bestChar);

      // 如果所有类型都已充分覆盖，检查是否继续
      final allCovered = StrokeType.values.every(
        (t) => (typeCounts[t] ?? 0) >= minPerType,
      );
      if (allCovered && selected.length >= 10) break;
    }

    return selected;
  }

  /// 获取字库中某个字符的笔画类型信息
  List<StrokeType> getStrokeTypes(String character) {
    final glyph = font.richGlyphOf(character);
    if (glyph == null) return [];
    return glyph.strokes
        .map((s) => s.type ?? StrokeType.other)
        .toList();
  }

  /// 获取字库中某个字符的笔画数
  int getStrokeCount(String character) {
    final glyph = font.richGlyphOf(character);
    return glyph?.strokeCount ?? 0;
  }
}

/// 覆盖率报告
class CoverageReport {
  /// 被分析的字符列表
  final List<String> characters;

  /// 每种笔画类型的出现次数
  final Map<StrokeType, int> strokeTypeCounts;

  /// 每个字符包含的笔画类型
  final Map<String, List<StrokeType>> characterStrokeTypes;

  /// 缺失的笔画类型
  final List<StrokeType> missingTypes;

  /// 总笔画数
  final int totalStrokes;

  const CoverageReport({
    required this.characters,
    required this.strokeTypeCounts,
    required this.characterStrokeTypes,
    required this.missingTypes,
    required this.totalStrokes,
  });

  /// 覆盖的笔画类型数
  int get coveredTypeCount => strokeTypeCounts.length;

  /// 总共可能的笔画类型数
  int get totalTypeCount => StrokeType.values.length;

  /// 覆盖率（0..1）
  double get coverageRatio =>
      totalTypeCount > 0 ? coveredTypeCount / totalTypeCount : 0;

  /// 是否完全覆盖
  bool get isFullyCovered => missingTypes.isEmpty;

  /// 获取某种笔画类型的出现次数
  int countOf(StrokeType type) => strokeTypeCounts[type] ?? 0;

  @override
  String toString() {
    final buffer = StringBuffer('CoverageReport:\n');
    buffer.writeln('  字符数: ${characters.length}');
    buffer.writeln('  总笔画: $totalStrokes');
    buffer.writeln(
        '  类型覆盖: $coveredTypeCount/$totalTypeCount (${(coverageRatio * 100).toStringAsFixed(0)}%)');
    if (missingTypes.isNotEmpty) {
      buffer.writeln('  缺失类型: ${missingTypes.map((t) => t.name).join(', ')}');
    }
    buffer.writeln('  各类型统计:');
    for (final type in StrokeType.values) {
      buffer.writeln(
          '    ${type.name}: ${strokeTypeCounts[type] ?? 0} 次');
    }
    return buffer.toString();
  }
}
