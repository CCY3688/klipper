import 'dart:convert';

/// 纸张类型枚举
enum PaperTypeKind {
  grid,       // 格子纸（方格）
  horizontal, // 横线格
  letter,     // 信纸笺（竖线格）
  blank,      // 空白纸
}

/// 统一纸张配置模型
/// 通过最小参数集实现对各种纸张类型的全面控制
class PaperConfig {
  final String name;            // 配置名称
  final PaperTypeKind kind;     // 纸张类型
  
  // --- 纸张尺寸 (mm) ---
  final double pageWidthMm;     // 纸张宽度
  final double pageHeightMm;    // 纸张高度
  
  // --- 边距 (mm) ---
  final double marginLeftMm;
  final double marginTopMm;
  final double marginRightMm;
  final double marginBottomMm;
  
  // --- 格子/行 参数 (mm) ---
  final double cellSizeMm;      // 格子宽度 (grid/horizontal/letter/blank)
  final double lineSpacingMm;   // 行高/行间距 (仅 horizontal/letter 使用)
  final double gridRowSpacingMm; // 格子行与行之间的额外间距 (仅 grid 使用)
  
  // --- 线条样式 ---
  final double lineWidthMm;     // 线条宽度
  final int lineColorValue;     // 线条颜色 (ARGB int)
  
  // --- 字体对齐 ---
  final double cellPaddingMm;   // 字在格子/行内的内边距

  // --- 边界参数 ---
  final int? customCols;        // 固定列数（若指定则忽略 pageWidth/Margin 计算）
  final int? customRows;        // 固定行数（若指定则忽略 pageHeight/Margin 计算）

  const PaperConfig({
    required this.name,
    required this.kind,
    this.pageWidthMm = 210,
    this.pageHeightMm = 297,
    this.marginLeftMm = 5,
    this.marginTopMm = 12.5,
    this.marginRightMm = 5,
    this.marginBottomMm = 12.5,
    this.cellSizeMm = 8,
    this.lineSpacingMm = 8,
    this.gridRowSpacingMm = 0,
    this.lineWidthMm = 0.3,
    this.lineColorValue = 0xFFF48FB1, // Colors.pink.shade200
    this.cellPaddingMm = 0.8,
    this.customCols,
    this.customRows,
  });

  /// 计算列数
  int get cols {
    if (customCols != null && customCols! > 0) return customCols!;
    
    final usableWidth = pageWidthMm - marginLeftMm - marginRightMm;
    switch (kind) {
      case PaperTypeKind.grid:
        return (usableWidth / cellSizeMm).floor().clamp(1, 100);
      case PaperTypeKind.horizontal:
        // 横线不限制列数，用 cellSizeMm 作为字格宽度来计算每行字数
        return (usableWidth / cellSizeMm).floor().clamp(1, 100);
      case PaperTypeKind.letter:
        // 竖线格，列宽由 cellSizeMm 决定
        return (usableWidth / cellSizeMm).floor().clamp(1, 100);
      case PaperTypeKind.blank:
        return (usableWidth / cellSizeMm).floor().clamp(1, 100);
    }
  }

  /// 计算行数
  int get rows {
    if (customRows != null && customRows! > 0) return customRows!;

    final usableHeight = pageHeightMm - marginTopMm - marginBottomMm;
    switch (kind) {
      case PaperTypeKind.grid:
        // 第一行占用 cellSizeMm，后续每行占用 cellSizeMm + gridRowSpacingMm
        if (usableHeight < cellSizeMm) return 0;
        return (1 + (usableHeight - cellSizeMm) / (cellSizeMm + gridRowSpacingMm)).floor().clamp(0, 500);
      case PaperTypeKind.horizontal:
        return (usableHeight / lineSpacingMm).floor().clamp(1, 500);
      case PaperTypeKind.letter:
        return (usableHeight / lineSpacingMm).floor().clamp(1, 500);
      case PaperTypeKind.blank:
        return (usableHeight / cellSizeMm).floor().clamp(1, 500);
    }
  }

  /// 获取写字用的「单元格宽度」(mm)
  double get effectiveCellWidth {
    switch (kind) {
      case PaperTypeKind.grid:
        return cellSizeMm;
      case PaperTypeKind.horizontal:
        return cellSizeMm; // 横向格子里，每个格子其实就是宽 cellSizeMm
      case PaperTypeKind.letter:
        return cellSizeMm;
      case PaperTypeKind.blank:
        return cellSizeMm;
    }
  }

  /// 获取写字用的「单元格高度」(mm)，用于布局
  double get effectiveCellHeight {
    switch (kind) {
      case PaperTypeKind.grid:
        return cellSizeMm; // 字本身还是cellSizeMm高，但布局时需要考虑间隔
      case PaperTypeKind.horizontal:
        return lineSpacingMm;
      case PaperTypeKind.letter:
        return lineSpacingMm;
      case PaperTypeKind.blank:
        return cellSizeMm;
    }
  }

  PaperConfig copyWith({
    String? name,
    PaperTypeKind? kind,
    double? pageWidthMm,
    double? pageHeightMm,
    double? marginLeftMm,
    double? marginTopMm,
    double? marginRightMm,
    double? marginBottomMm,
    double? cellSizeMm,
    double? lineSpacingMm,
    double? gridRowSpacingMm,
    double? lineWidthMm,
    int? lineColorValue,
    double? cellPaddingMm,
    int? customCols,
    int? customRows,
  }) {
    return PaperConfig(
      name: name ?? this.name,
      kind: kind ?? this.kind,
      pageWidthMm: pageWidthMm ?? this.pageWidthMm,
      pageHeightMm: pageHeightMm ?? this.pageHeightMm,
      marginLeftMm: marginLeftMm ?? this.marginLeftMm,
      marginTopMm: marginTopMm ?? this.marginTopMm,
      marginRightMm: marginRightMm ?? this.marginRightMm,
      marginBottomMm: marginBottomMm ?? this.marginBottomMm,
      cellSizeMm: cellSizeMm ?? this.cellSizeMm,
      lineSpacingMm: lineSpacingMm ?? this.lineSpacingMm,
      gridRowSpacingMm: gridRowSpacingMm ?? this.gridRowSpacingMm,
      lineWidthMm: lineWidthMm ?? this.lineWidthMm,
      lineColorValue: lineColorValue ?? this.lineColorValue,
      cellPaddingMm: cellPaddingMm ?? this.cellPaddingMm,
      customCols: customCols ?? this.customCols,
      customRows: customRows ?? this.customRows,
    );
  }

  /// 序列化为 JSON Map
  Map<String, dynamic> toJson() => {
    'name': name,
    'kind': kind.name,
    'pageWidthMm': pageWidthMm,
    'pageHeightMm': pageHeightMm,
    'marginLeftMm': marginLeftMm,
    'marginTopMm': marginTopMm,
    'marginRightMm': marginRightMm,
    'marginBottomMm': marginBottomMm,
    'cellSizeMm': cellSizeMm,
    'lineSpacingMm': lineSpacingMm,
    'gridRowSpacingMm': gridRowSpacingMm,
    'lineWidthMm': lineWidthMm,
    'lineColorValue': lineColorValue,
    'cellPaddingMm': cellPaddingMm,
    'customCols': customCols,
    'customRows': customRows,
  };

  /// 从 JSON Map 反序列化
  factory PaperConfig.fromJson(Map<String, dynamic> json) {
    return PaperConfig(
      name: json['name'] as String? ?? '未命名',
      kind: PaperTypeKind.values.firstWhere(
        (e) => e.name == json['kind'],
        orElse: () => PaperTypeKind.grid,
      ),
      pageWidthMm: (json['pageWidthMm'] as num?)?.toDouble() ?? 210,
      pageHeightMm: (json['pageHeightMm'] as num?)?.toDouble() ?? 297,
      marginLeftMm: (json['marginLeftMm'] as num?)?.toDouble() ?? 5,
      marginTopMm: (json['marginTopMm'] as num?)?.toDouble() ?? 12.5,
      marginRightMm: (json['marginRightMm'] as num?)?.toDouble() ?? 5,
      marginBottomMm: (json['marginBottomMm'] as num?)?.toDouble() ?? 12.5,
      cellSizeMm: (json['cellSizeMm'] as num?)?.toDouble() ?? 8,
      lineSpacingMm: (json['lineSpacingMm'] as num?)?.toDouble() ?? 8,
      gridRowSpacingMm: (json['gridRowSpacingMm'] as num?)?.toDouble() ?? 0,
      lineWidthMm: (json['lineWidthMm'] as num?)?.toDouble() ?? 0.3,
      lineColorValue: (json['lineColorValue'] as num?)?.toInt() ?? 0xFFF48FB1,
      cellPaddingMm: (json['cellPaddingMm'] as num?)?.toDouble() ?? 0.8,
      customCols: (json['customCols'] as num?)?.toInt(),
      customRows: (json['customRows'] as num?)?.toInt(),
    );
  }

  /// 序列化为 JSON 字符串
  String toJsonString() => jsonEncode(toJson());

  /// 从 JSON 字符串反序列化
  factory PaperConfig.fromJsonString(String s) =>
      PaperConfig.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaperConfig &&
          name == other.name &&
          kind == other.kind &&
          pageWidthMm == other.pageWidthMm &&
          pageHeightMm == other.pageHeightMm &&
          marginLeftMm == other.marginLeftMm &&
          marginTopMm == other.marginTopMm &&
          marginRightMm == other.marginRightMm &&
          marginBottomMm == other.marginBottomMm &&
          cellSizeMm == other.cellSizeMm &&
          lineSpacingMm == other.lineSpacingMm &&
          lineWidthMm == other.lineWidthMm &&
          lineColorValue == other.lineColorValue &&
          cellPaddingMm == other.cellPaddingMm;

  @override
  int get hashCode => Object.hash(
        name, kind, pageWidthMm, pageHeightMm,
        marginLeftMm, marginTopMm, marginRightMm, marginBottomMm,
        cellSizeMm, lineSpacingMm, lineWidthMm, lineColorValue,
        cellPaddingMm,
      );
}

// ===== 预置默认纸张类型 =====

/// 默认格子纸 (当前 A4 作文格)
PaperConfig defaultGridPaper() => const PaperConfig(
  name: '默认格子纸 (A4)',
  kind: PaperTypeKind.grid,
  pageWidthMm: 210,
  pageHeightMm: 297,
  marginLeftMm: 5,
  marginTopMm: 12.5,
  marginRightMm: 5,
  marginBottomMm: 12.5,
  cellSizeMm: 8,
  lineSpacingMm: 8,
  lineWidthMm: 0.3,
  lineColorValue: 0xFFF48FB1,
  cellPaddingMm: 0.8,
);

/// 横线格纸
PaperConfig defaultHorizontalPaper() => const PaperConfig(
  name: '默认横线格 (A4)',
  kind: PaperTypeKind.horizontal,
  pageWidthMm: 210,
  pageHeightMm: 297,
  marginLeftMm: 15,
  marginTopMm: 20,
  marginRightMm: 15,
  marginBottomMm: 20,
  cellSizeMm: 7,
  lineSpacingMm: 10,
  lineWidthMm: 0.2,
  lineColorValue: 0xFF90CAF9, // 淡蓝色
  cellPaddingMm: 0.5,
);

/// 信纸笺（竖线格）
PaperConfig defaultLetterPaper() => const PaperConfig(
  name: '默认信纸笺 (A4)',
  kind: PaperTypeKind.letter,
  pageWidthMm: 210,
  pageHeightMm: 297,
  marginLeftMm: 20,
  marginTopMm: 25,
  marginRightMm: 20,
  marginBottomMm: 25,
  cellSizeMm: 10,
  lineSpacingMm: 12,
  lineWidthMm: 0.2,
  lineColorValue: 0xFFA5D6A7, // 淡绿色
  cellPaddingMm: 0.8,
);

/// 空白纸
PaperConfig defaultBlankPaper() => const PaperConfig(
  name: '默认空白纸 (A4)',
  kind: PaperTypeKind.blank,
  pageWidthMm: 210,
  pageHeightMm: 297,
  marginLeftMm: 15,
  marginTopMm: 20,
  marginRightMm: 15,
  marginBottomMm: 20,
  cellSizeMm: 8,
  lineSpacingMm: 8,
  lineWidthMm: 0.3,
  lineColorValue: 0x00000000, // 透明（不画线）
  cellPaddingMm: 0.8,
);

/// 所有默认纸张类型
List<PaperConfig> allDefaultPapers() => [
  defaultGridPaper(),
  defaultHorizontalPaper(),
  defaultLetterPaper(),
  defaultBlankPaper(),
];
