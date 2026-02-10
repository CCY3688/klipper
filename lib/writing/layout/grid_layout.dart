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
import '../model/toolpath.dart';
import 'stroke_optimizer.dart';

/// 书写模式
enum WritingMode {
  /// 标准模式：严格遵循汉字笔顺
  standard,
  
  /// 快速模式：优化笔画顺序以减少抬笔移动距离
  fast,
}

class GridLayoutOptions {
  final double cellPaddingMm; // 字在格子内四周留白
  final WritingMode mode; // 书写模式
  final bool allowStrokeReverse; // 快速模式下是否允许反向笔画
  
  const GridLayoutOptions({
    this.cellPaddingMm = 0.8,
    this.mode = WritingMode.standard,
    this.allowStrokeReverse = true,
  });
  
  GridLayoutOptions copyWith({
    double? cellPaddingMm,
    WritingMode? mode,
    bool? allowStrokeReverse,
  }) {
    return GridLayoutOptions(
      cellPaddingMm: cellPaddingMm ?? this.cellPaddingMm,
      mode: mode ?? this.mode,
      allowStrokeReverse: allowStrokeReverse ?? this.allowStrokeReverse,
    );
  }
}

class EssayGridLayout {
  final EssayGridSpec grid;
  final StrokeFont font;
  final GridLayoutOptions options;

  EssayGridLayout({
    required this.grid,
    required this.font,
    this.options = const GridLayoutOptions(),
  });

  ToolPath layoutText(String text) {
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
      final bool isReversed = r % 2 == 1; // 奇数行(第二、四...)反向书写

      // 根据方向决定列的处理顺序
      final Iterable<int> columns = isReversed
          ? Iterable<int>.generate(lineChars.length, (i) => lineChars.length - 1 - i)
          : Iterable<int>.generate(lineChars.length, (i) => i);

      for (final c in columns) {
        final ch = lineChars[c];

        // 空格：占格但不画
        if (ch.trim().isEmpty) {
          continue;
        }

        final glyph = font.glyphOf(ch) ?? _placeholderGlyph();

        // 计算当前格子位置 (mm)
        final cellLeft = grid.marginLeftMm + c * grid.cellMm;
        final cellTop = grid.marginTopMm + r * grid.cellMm;

        final pad = options.cellPaddingMm;
        final inner = (grid.cellMm - 2 * pad).clamp(0.1, grid.cellMm);

        // 映射坐标
        Vec2 mapPt(Vec2 p) {
          final x = cellLeft + pad + p.x * inner;
          final y = cellTop + pad + p.y * inner;
          return Vec2(x, y);
        }

        // 处理笔画
        // 快速模式：优化笔画顺序以减少抬笔移动
        // 标准模式：保持原始笔顺
        List<List<Vec2>> strokes = glyph.strokes;
        
        if (options.mode == WritingMode.fast && strokes.length > 1) {
          // 传入当前光标位置（已映射到格子内坐标系）
          final cursorInCell = cursor != null 
              ? Vec2(
                  (cursor.x - cellLeft - pad) / inner,
                  (cursor.y - cellTop - pad) / inner,
                )
              : null;
          strokes = StrokeOptimizer.optimizeGlyph(
            strokes,
            startFrom: cursorInCell,
            allowReverse: options.allowStrokeReverse,
          );
        }
        
        for (final stroke in strokes) {
          if (stroke.length < 2) continue;

          final pts = stroke.map(mapPt).toList();
          final start = pts.first;

          // 生成 pen-up 移动
          if (cursor != null && (cursor.x != start.x || cursor.y != start.y)) {
            polylines.add(ToolPolyline(penDown: false, points: [cursor, start]));
          }

          // 生成 pen-down 笔迹
          polylines.add(ToolPolyline(penDown: true, points: pts));
          cursor = pts.last;
        }
      }
    }

    return ToolPath(polylines: polylines);
  }

  StrokeGlyph _placeholderGlyph() {
    // 方框 + 斜线（归一化坐标）
    return const StrokeGlyph([
      [Vec2(0.2, 0.2), Vec2(0.8, 0.2), Vec2(0.8, 0.8), Vec2(0.2, 0.8), Vec2(0.2, 0.2)],
      [Vec2(0.2, 0.2), Vec2(0.8, 0.8)],
    ]);
  }
}