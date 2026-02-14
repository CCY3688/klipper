// 样本模板模型
//
// 定义用户需要书写的字符集和纸张布局。
// 系统会生成一张带有参考字和网格的模板，用户在模板上
// 书写对应的字符，然后拍照上传。由于字符和位置已知，
// 可以直接按格子分割并与参考字体进行风格比对。

/// 单个模板字符的元信息
class TemplateCharacter {
  /// 字符
  final String character;

  /// 在模板中的行索引（0-based）
  final int row;

  /// 在模板中的列索引（0-based）
  final int col;

  /// 该字符包含的笔画类型列表
  final List<String> strokeTypes;

  const TemplateCharacter({
    required this.character,
    required this.row,
    required this.col,
    this.strokeTypes = const [],
  });
}

/// 样本模板
class SampleTemplate {
  /// 模板名称
  final String name;

  /// 模板描述
  final String description;

  /// 模板中的字符（按顺序排列，从左到右、从上到下）
  final List<String> characters;

  /// 网格列数
  final int columns;

  /// 网格行数
  int get rows => (characters.length / columns).ceil();

  /// 单元格大小（毫米）
  final double cellSizeMm;

  /// 页面宽度（毫米）
  final double pageWidthMm;

  /// 页面高度（毫米）
  final double pageHeightMm;

  /// 左边距（毫米）
  final double marginLeftMm;

  /// 上边距（毫米）
  final double marginTopMm;

  const SampleTemplate({
    required this.name,
    this.description = '',
    required this.characters,
    this.columns = 5,
    this.cellSizeMm = 25.0,
    this.pageWidthMm = 210.0,
    this.pageHeightMm = 297.0,
    this.marginLeftMm = 30.0,
    this.marginTopMm = 40.0,
  });

  /// 获取指定位置的字符
  String? characterAt(int row, int col) {
    final index = row * columns + col;
    if (index >= 0 && index < characters.length) {
      return characters[index];
    }
    return null;
  }

  /// 获取字符在模板中的行列位置
  (int row, int col)? positionOf(String char) {
    final index = characters.indexOf(char);
    if (index < 0) return null;
    return (index ~/ columns, index % columns);
  }

  /// 总字符数
  int get characterCount => characters.length;

  /// 可用的格子总数（包含可能的空格子）
  int get totalCells => rows * columns;

  // ================================================================
  //  预置模板
  // ================================================================

  /// 默认基础模板 —— 20 字，覆盖全部基础笔画类型
  ///
  /// 选字策略：
  ///   1. 永字八法核心字「永」涵盖横竖撇捺点折钩7种基础笔画。
  ///   2. 补充常见高频汉字，使每种笔画至少出现5次以上，
  ///      提高风格统计的鲁棒性。
  ///   3. 包含独体字和合体字，覆盖不同结构。
  ///   4. 字形简单易写，减轻用户负担。
  static const SampleTemplate basic = SampleTemplate(
    name: '基础笔画模板',
    description: '20个常用汉字，覆盖横竖撇捺点折钩全部基础笔画，每种笔画至少出现5次',
    characters: [
      // 第1行：永字八法 + 基础结构
      '永', '大', '人', '十', '口',
      // 第2行：带钩和点的字
      '心', '我', '中', '小', '天',
      // 第3行：多种结构
      '之', '上', '月', '日', '木',
      // 第4行：补充笔画
      '水', '火', '土', '山', '女',
    ],
    columns: 5,
    cellSizeMm: 25.0,
  );

  /// 精简模板 —— 10 字，快速采集
  static const SampleTemplate quick = SampleTemplate(
    name: '快速采集模板',
    description: '10个精选汉字，快速完成基础风格采集',
    characters: [
      '永', '大', '口', '心', '我',
      '天', '月', '木', '水', '女',
    ],
    columns: 5,
    cellSizeMm: 30.0,
  );

  /// 进阶模板 —— 35 字，更精确的风格学习
  static const SampleTemplate advanced = SampleTemplate(
    name: '进阶笔画模板',
    description: '35个汉字，涵盖更丰富的笔画组合与字形结构',
    characters: [
      '永', '大', '人', '十', '口',
      '心', '我', '中', '小', '天',
      '之', '上', '月', '日', '木',
      '水', '火', '土', '山', '女',
      '风', '雨', '花', '鸟', '龙',
      '书', '学', '写', '手', '字',
      '长', '门', '走', '飞', '马',
    ],
    columns: 5,
    cellSizeMm: 20.0,
    marginTopMm: 30.0,
  );

  /// 所有预置模板
  static const List<SampleTemplate> presets = [basic, quick, advanced];
}
