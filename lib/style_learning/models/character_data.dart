import 'stroke_trajectory.dart';

/// 字符数据 - 对应字库中的一个字
/// 
/// 示例数据：
/// {
///   "character": "丕",
///   "strokes": ["M 585 690 Q...", ...],
///   "medians": [[[228,686],[258,676],...], ...]
/// }

class CharacterData {
  /// 字符
  final String character;
  
  /// 所有笔画
  final List<StrokeTrajectory> strokes;

  CharacterData({
    required this.character,
    required this.strokes,
  });

  /// 从字库 JSON 格式创建
  factory CharacterData.fromLibraryJson(Map<String, dynamic> json) {
    final character = json['character'] as String;
    final strokePaths = (json['strokes'] as List).cast<String>();
    final medians = json['medians'] as List;

    final strokes = <StrokeTrajectory>[];
    for (int i = 0; i < strokePaths.length; i++) {
      strokes.add(StrokeTrajectory(
        svgPath: strokePaths[i],
        medians: (medians[i] as List)
            .map((p) => (p as List).cast<int>().toList())
            .toList(),
      ));
    }

    return CharacterData(
      character: character,
      strokes: strokes,
    );
  }

  /// 转换为字库 JSON 格式（兼容现有格式）
  Map<String, dynamic> toLibraryJson() {
    return {
      'character': character,
      'strokes': strokes.map((s) => s.svgPath).toList(),
      'medians': strokes.map((s) => s.medians).toList(),
    };
  }

  /// 笔画数量
  int get strokeCount => strokes.length;

  @override
  String toString() {
    return 'CharacterData($character, $strokeCount strokes)';
  }
}