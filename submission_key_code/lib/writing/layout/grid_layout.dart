// 核心点：
// - 输入：text + gridSpec + font
// - 输出：ToolPath
// 规则：
// - 遇到 \n 换行
// - 每个字符占一个格子（空格也占格）
// - 不存在 glyph 的字符用占位符（方框 + 斜线）保证可预览
// 坐标变换：
// - glyph 点 (0..1) 映射到 cell 内部：cellLeft + padding + x*(cellSize-2padding)

import 'package:characters/characters.dart';

import '../font/stroke_font.dart';
import '../model/essay_grid.dart';
import '../model/geometry.dart';
import '../model/stroke.dart';
import '../model/toolpath.dart';
import 'stroke_optimizer.dart';

/// 书写模式
enum WritingMode {
  /// 标准模式：严格遵循汉字笔顺
  standard,
  
  /// 快速模式：优化笔画顺序以减少抬笔移动距离
  fast,
}

typedef GridStrokeTransformer = List<List<Vec2>> Function(
  String character,
  List<List<Vec2>> strokes,
  List<StrokeType?> strokeTypes,
);

class GridLayoutOptions {
  final double cellPaddingMm; // 字在格子内四周留白
  final WritingMode mode; // 书写模式
  final bool allowStrokeReverse; // 快速模式下是否允许反向笔画
  final double? cellHeightMm; // 格子高度（与宽度不同时使用），null 则取 grid.cellMm
  final double gridRowSpacingMm; // 格子行间距
  
  final bool verticalFirst;
  final GridStrokeTransformer? strokeTransformer;

  const GridLayoutOptions({
    this.cellPaddingMm = 0.8,
    this.mode = WritingMode.standard,
    this.allowStrokeReverse = true,
    this.cellHeightMm,
    this.gridRowSpacingMm = 0,
    this.verticalFirst = false,
    this.strokeTransformer,
  });

  GridLayoutOptions copyWith({
    double? cellPaddingMm,
    WritingMode? mode,
    bool? allowStrokeReverse,
    double? cellHeightMm,
    double? gridRowSpacingMm,
    bool? verticalFirst,
    GridStrokeTransformer? strokeTransformer,
  }) {
    return GridLayoutOptions(
      cellPaddingMm: cellPaddingMm ?? this.cellPaddingMm,
      mode: mode ?? this.mode,
      allowStrokeReverse: allowStrokeReverse ?? this.allowStrokeReverse,
      cellHeightMm: cellHeightMm ?? this.cellHeightMm,
      gridRowSpacingMm: gridRowSpacingMm ?? this.gridRowSpacingMm,
      verticalFirst: verticalFirst ?? this.verticalFirst,
      strokeTransformer: strokeTransformer ?? this.strokeTransformer,
    );
  }
}

class GridLayout {
  final EssayGridSpec grid;
  final StrokeFont font;
  final GridLayoutOptions options;

  GridLayout({
    required this.grid,
    required this.font,
    this.options = const GridLayoutOptions(),
  });

  ToolPath layoutText(String text) {
    if (options.verticalFirst) {
      return _layoutVerticalFirst(text);
    }

    // 1. 将文本拆分为行和列的布局矩阵
    final List<List<String>> lines = [];
    List<String> currentRow = [];

    for (final ch in text.characters) {
      if (ch == '\n') {
        lines.add(currentRow);
        currentRow = [];
        if (lines.length >= grid.rows) break;
        continue;
      }

      currentRow.add(ch);
      if (currentRow.length >= grid.cols) {
        lines.add(currentRow);
        currentRow = [];
        if (lines.length >= grid.rows) break;
      }
    }
    if (currentRow.isNotEmpty && lines.length < grid.rows) {
      lines.add(currentRow);
    }

    final polylines = <ToolPolyline>[];
    Vec2? cursor;

    // 2. 遍历每一行执行布局
    for (int r = 0; r < lines.length; r++) {
      final lineChars = lines[r];
      // 这里的 S 型书写逻辑
      final bool isReversed = r % 2 == 1; // 奇数行(第二、四...)反向书写

      // 根据方向决定列的处理顺序
      final Iterable<int> columnsOrder = isReversed
          ? Iterable<int>.generate(lineChars.length, (i) => lineChars.length - 1 - i)
          : Iterable<int>.generate(lineChars.length, (i) => i);

      for (final c in columnsOrder) {
        final ch = lineChars[c];
        _processChar(ch, r, c, polylines, (newCursor) => cursor = newCursor, () => cursor);
      }
    }

    return ToolPath(polylines: polylines);
  }

  ToolPath _layoutVerticalFirst(String text) {
    // 纵向书写：一列一列来，从左往右
    final List<List<String>> cols = [];
    List<String> currentCol = [];

    for (final ch in text.characters) {
      if (ch == '\n') {
        cols.add(currentCol);
        currentCol = [];
        if (cols.length >= grid.cols) break;
        continue;
      }

      currentCol.add(ch);
      if (currentCol.length >= grid.rows) {
        cols.add(currentCol);
        currentCol = [];
        if (cols.length >= grid.cols) break;
      }
    }
    if (currentCol.isNotEmpty && cols.length < grid.cols) {
      cols.add(currentCol);
    }

    final polylines = <ToolPolyline>[];
    Vec2? cursor;

    for (int c = 0; c < cols.length; c++) {
      final colChars = cols[c];
      
      // S 型书写：如果是奇数列，则从下往上
      final bool isReversed = c % 2 == 1;
      final Iterable<int> rowsOrder = isReversed
          ? Iterable<int>.generate(colChars.length, (i) => colChars.length - 1 - i)
          : Iterable<int>.generate(colChars.length, (i) => i);

      for (final r in rowsOrder) {
        final ch = colChars[r];
        _processChar(ch, r, c, polylines, (newCursor) => cursor = newCursor, () => cursor);
      }
    }

    return ToolPath(polylines: polylines);
  }

  void _processChar(
    String ch, 
    int r, 
    int c, 
    List<ToolPolyline> polylines,
    void Function(Vec2?) setCursor,
    Vec2? Function() getCursor,
  ) {
    // 空格：占格但不画
    if (ch.trim().isEmpty) {
      return;
    }

    final legacyGlyph = font.glyphOf(ch) ?? _placeholderGlyph();
    final richGlyph = font.richGlyphOf(ch); // 可选，用于获取笔画类型

    // 计算当前格子位置 (mm)
    final cellW = grid.cellMm;
    final boxH = options.cellHeightMm ?? grid.cellMm;
    final rowGap = options.gridRowSpacingMm;
    
    final cellLeft = grid.marginLeftMm + c * cellW;
    final cellTop = grid.marginTopMm + r * (boxH + rowGap);

    final pad = options.cellPaddingMm;
    final innerSquare = ([cellW - 2 * pad, boxH - 2 * pad].reduce((a, b) => a < b ? a : b)).clamp(0.1, double.infinity);
    final offsetX = cellLeft + (cellW - innerSquare) / 2;
    final offsetY = cellTop + (boxH - innerSquare) / 2;

    // ---------- 坐标映射 ----------
    Vec2 mapPt(Vec2 p) {
      return Vec2(offsetX + p.x * innerSquare, offsetY + p.y * innerSquare);
    }

    List<List<Vec2>> strokes = legacyGlyph.strokes;
    final strokeTypes = richGlyph?.strokes.map((s) => s.type).toList() ??
        List<StrokeType?>.filled(strokes.length, null);

    final transformer = options.strokeTransformer;
    if (transformer != null) {
      final transformed = transformer(ch, strokes, strokeTypes);
      if (transformed.isNotEmpty && transformed.length == strokes.length) {
        strokes = transformed;
      }
    }
    Vec2? cursor = getCursor();

    // 优化笔画顺序（快速模式下会打乱原始顺序）
    if (options.mode == WritingMode.fast && strokes.length > 1) {
      final cursorInCell = cursor != null 
          ? Vec2((cursor.x - offsetX) / innerSquare, (cursor.y - offsetY) / innerSquare)
          : null;
      strokes = StrokeOptimizer.optimizeGlyph(
        strokes,
        startFrom: cursorInCell,
        allowReverse: options.allowStrokeReverse,
      );
    }
    
    for (int si = 0; si < strokes.length; si++) {
      final stroke = strokes[si];
      if (stroke.length < 2) continue;

      // ---------- 坐标映射 ----------
      final transformedPts = [for (final p in stroke) mapPt(p)];

      final start = transformedPts.first;
      if (cursor != null && (cursor.x != start.x || cursor.y != start.y)) {
        polylines.add(ToolPolyline(penDown: false, points: [cursor, start]));
      }

      polylines.add(ToolPolyline(penDown: true, points: transformedPts));
      cursor = transformedPts.last;
    }
    setCursor(cursor);
  }

  StrokeGlyph _placeholderGlyph() {
    // 方框 + 斜线（归一化坐标）
    return const StrokeGlyph([
      [Vec2(0.2, 0.2), Vec2(0.8, 0.2), Vec2(0.8, 0.8), Vec2(0.2, 0.8), Vec2(0.2, 0.2)],
      [Vec2(0.2, 0.2), Vec2(0.8, 0.8)],
    ]);
  }
}