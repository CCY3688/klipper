/// 共享字形渲染组件
///
/// [GlyphPainter]  — 将 Glyph 的归一化笔画 (0~1) 绘制到 Canvas
/// [GlyphTile]     — 单个字形预览方块：笔画 + 字符标签，可带点击回调
library;

import 'package:flutter/material.dart';

import '../../../writing/model/glyph.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GlyphPainter
// ─────────────────────────────────────────────────────────────────────────────

/// 直接将 [Glyph] 的归一化坐标 (0→1) 绘制到 Flutter Canvas。
class GlyphPainter extends CustomPainter {
  final Glyph glyph;
  final Color strokeColor;
  final double strokeWidth;

  const GlyphPainter({
    required this.glyph,
    required this.strokeColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    const padding = 0.06; // 留 6% 内边距
    final w = size.width * (1 - padding * 2);
    final h = size.height * (1 - padding * 2);
    final ox = size.width * padding;
    final oy = size.height * padding;

    for (final stroke in glyph.strokes) {
      final points = stroke.points;
      if (points.length < 2) continue;
      final path = Path();
      final first = points.first;
      path.moveTo(ox + first.x * w, oy + first.y * h);
      for (final pt in points.skip(1)) {
        path.lineTo(ox + pt.x * w, oy + pt.y * h);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(GlyphPainter old) =>
      old.glyph != glyph ||
      old.strokeColor != strokeColor ||
      old.strokeWidth != strokeWidth;
}

// ─────────────────────────────────────────────────────────────────────────────
// GlyphTile
// ─────────────────────────────────────────────────────────────────────────────

/// 单字形预览方块：显示 [glyph] 笔画，若 [glyph] 为 null 则显示灰色占位。
///
/// * [character] 始终显示在底部作标签。
/// * [onTap] 不为 null 时整块可点击（高亮效果）。
/// * [highlight] 是否显示选中高亮边框。
class GlyphTile extends StatelessWidget {
  final String character;
  final Glyph? glyph;
  final double size;
  final VoidCallback? onTap;
  final bool highlight;

  /// 是使用用户字体（true）还是标准字体（false/null）
  final bool? isUserFont;

  const GlyphTile({
    super.key,
    required this.character,
    required this.glyph,
    this.size = 56,
    this.onTap,
    this.highlight = false,
    this.isUserFont,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasGlyph = glyph != null && glyph!.strokes.isNotEmpty;

    final borderColor = highlight
        ? theme.colorScheme.primary
        : (hasGlyph
              ? theme.colorScheme.outlineVariant.withValues(alpha: 0.5)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.3));

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              border: Border.all(color: borderColor, width: highlight ? 2 : 1),
              borderRadius: BorderRadius.circular(6),
              color: highlight
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
                  : (hasGlyph
                        ? theme.colorScheme.surface
                        : theme.colorScheme.surfaceContainerHighest),
            ),
            child: hasGlyph
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: CustomPaint(
                          painter: GlyphPainter(
                            glyph: glyph!,
                            strokeColor: highlight
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface.withValues(
                                    alpha: 0.85,
                                  ),
                            strokeWidth: (size / 28.0).clamp(1.0, 3.5),
                          ),
                        ),
                      ),
                      // 用户字体徽章
                      if (isUserFont == true)
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  )
                : Center(
                    child: Text(
                      character,
                      style: TextStyle(
                        color: theme.colorScheme.outlineVariant,
                        fontSize: size * 0.45,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 2),
          Text(
            character,
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
