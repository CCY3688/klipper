/// 字形处理流水线调试页面
///
/// 可视化展示 TTF 字形处理各阶段的中间结果：
///   轮廓 → 光栅 → 骨架 → 向量化 → 接链 → 对齐 → 补链 → 吸附 → 最终
///
/// 用于排查笔画断裂等问题。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../writing/user_font/debug/glyph_debug_data.dart';
import '../../writing/user_font/debug/glyph_debug_processor.dart';
import '../../writing/user_font/skeleton/outline_rasterizer.dart';
import '../../writing/user_font/skeleton/skeleton_vectorizer.dart';

/// 字形调试页面
class GlyphDebugPage extends StatefulWidget {
  /// TTF 文件路径
  final File ttfFile;

  /// 初始要调试的字符
  final String initialChar;

  const GlyphDebugPage({
    super.key,
    required this.ttfFile,
    this.initialChar = '大',
  });

  @override
  State<GlyphDebugPage> createState() => _GlyphDebugPageState();
}

class _GlyphDebugPageState extends State<GlyphDebugPage> {
  final _charController = TextEditingController();
  GlyphDebugData? _debugData;
  bool _loading = false;
  int _selectedStage = 0;
  int _preSpurPruneLen = 6;
  int _tinyComponentSize = 4;
  int _bridgeGap = 6;
  int _postSpurPruneLen = 4;

  @override
  void initState() {
    super.initState();
    _charController.text = widget.initialChar;
    _runDebug(widget.initialChar);
  }

  @override
  void dispose() {
    _charController.dispose();
    super.dispose();
  }

  Future<void> _runDebug(String ch) async {
    if (ch.isEmpty) return;
    setState(() {
      _loading = true;
      _selectedStage = 0;
    });

    final data = await GlyphDebugProcessor.processChar(
      ttfFile: widget.ttfFile,
      character: ch,
      preSpurPruneLen: _preSpurPruneLen,
      tinyComponentSize: _tinyComponentSize,
      bridgeGap: _bridgeGap,
      postSpurPruneLen: _postSpurPruneLen,
    );

    if (mounted) {
      setState(() {
        _debugData = data;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('笔画处理调试'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _charController,
                    decoration: const InputDecoration(
                      labelText: '输入字符',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                    onSubmitted: (v) {
                      if (v.isNotEmpty) _runDebug(v.characters.first);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final t = _charController.text;
                    if (t.isNotEmpty) _runDebug(t.characters.first);
                  },
                  child: const Text('调试'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _openSkeletonParamsSheet,
                  icon: const Icon(Icons.tune, size: 16),
                  label: const Text('骨架参数'),
                ),
                const SizedBox(width: 16),
                // 快捷按钮
                for (final ch in ['大', '人', '木', '水', '永', '我'])
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ActionChip(
                      label: Text(ch),
                      onPressed: () {
                        _charController.text = ch;
                        _runDebug(ch);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _debugData == null
              ? const Center(child: Text('输入字符后点击"调试"'))
              : _buildDebugView(theme),
    );
  }

  Widget _buildDebugView(ThemeData theme) {
    final data = _debugData!;

    if (data.error != null && data.rasterBitmap == null) {
      return Center(
        child: Text('错误：${data.error}', style: TextStyle(color: theme.colorScheme.error)),
      );
    }

    return Row(
      children: [
        // ── 左侧：阶段选择器 ──
        SizedBox(
          width: 140,
          child: ListView.builder(
            itemCount: GlyphDebugData.stageLabels.length,
            itemBuilder: (ctx, i) {
              final hasData = _stageHasData(i);
              final selected = i == _selectedStage;
              return ListTile(
                dense: true,
                selected: selected,
                selectedTileColor: theme.colorScheme.primaryContainer,
                leading: Text(
                  '$i',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: hasData
                        ? (selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface)
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                title: Text(
                  GlyphDebugData.stageLabels[i],
                  style: TextStyle(
                    fontSize: 13,
                    color: hasData ? null : theme.colorScheme.outlineVariant,
                  ),
                ),
                trailing: hasData
                    ? Icon(Icons.check_circle, size: 16, color: Colors.green.shade600)
                    : Icon(Icons.circle_outlined,
                        size: 16, color: theme.colorScheme.outlineVariant),
                onTap: hasData ? () => setState(() => _selectedStage = i) : null,
              );
            },
          ),
        ),
        VerticalDivider(width: 1, color: theme.colorScheme.outlineVariant),
        // ── 右侧：可视化区域 ──
        Expanded(
          child: Column(
            children: [
              // 信息栏
              _buildInfoBar(theme, data),
              const Divider(height: 1),
              // 可视化
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: CustomPaint(
                          painter: _StageVisualizationPainter(
                            data: data,
                            stage: _selectedStage,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 图例
              _buildLegend(theme),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBar(ThemeData theme, GlyphDebugData data) {
    final infoParts = <String>['字符: "${data.character}"'];

    switch (_selectedStage) {
      case 0:
        final n = data.sampledContours?.length ?? 0;
        infoParts.add('轮廓数: $n');
      case 1:
        final bm = data.rasterBitmap;
        if (bm != null) {
          final filled = bm.pixels.where((p) => p != 0).length;
          infoParts.add('像素: ${bm.width}×${bm.height}  前景: $filled px');
        }
      case 2:
        final sk = data.skeletonBitmap;
        if (sk != null) {
          final bone = sk.pixels.where((p) => p != 0).length;
          infoParts.add('骨架像素: $bone px');
        }
        infoParts.add(
          '参数 pre=$_preSpurPruneLen tiny=$_tinyComponentSize bridge=$_bridgeGap post=$_postSpurPruneLen',
        );
      case 3:
        final n = data.rawVectorStrokes?.length ?? 0;
        infoParts.add('原始段数: $n');
      case 4:
        final n = data.chainedStrokes?.length ?? 0;
        final tn = data.templateStrokes?.length;
        infoParts.add('接链后: $n 段');
        if (tn != null) infoParts.add('模板: $tn 笔画');
      case 5:
        final n = data.alignedStrokes?.length ?? 0;
        final score = data.matchScore;
        infoParts.add('对齐后: $n 段');
        if (score != null) infoParts.add('匹配分: ${score.toStringAsFixed(3)}');
      case 6:
        final n = data.repairedStrokes?.length ?? 0;
        infoParts.add('补链后: $n 段');
      case 7:
        final n = data.finalizedStrokes?.length ?? 0;
        infoParts.add('吸附后: $n 段');
      case 8:
        final n = data.finalGlyph?.strokeCount ?? 0;
        infoParts.add('最终笔画: $n');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Text(
            '阶段 $_selectedStage: ${GlyphDebugData.stageLabels[_selectedStage]}',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 24),
          Text(infoParts.skip(1).join('  |  '), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Future<void> _openSkeletonParamsSheet() async {
    int preSpurPruneLen = _preSpurPruneLen;
    int tinyComponentSize = _tinyComponentSize;
    int bridgeGap = _bridgeGap;
    int postSpurPruneLen = _postSpurPruneLen;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Widget sliderRow({
              required String label,
              required int value,
              required int min,
              required int max,
              required ValueChanged<int> onChanged,
            }) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$label: $value'),
                  Slider(
                    value: value.toDouble(),
                    min: min.toDouble(),
                    max: max.toDouble(),
                    divisions: max - min,
                    label: '$value',
                    onChanged: (v) => onChanged(v.round()),
                  ),
                ],
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('骨架化参数', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    sliderRow(
                      label: '预清刺长度(pre)',
                      value: preSpurPruneLen,
                      min: 0,
                      max: 12,
                      onChanged: (v) => setSheetState(() => preSpurPruneLen = v),
                    ),
                    sliderRow(
                      label: '微小连通域阈值(tiny)',
                      value: tinyComponentSize,
                      min: 0,
                      max: 12,
                      onChanged: (v) => setSheetState(() => tinyComponentSize = v),
                    ),
                    sliderRow(
                      label: '端点桥接距离(bridge)',
                      value: bridgeGap,
                      min: 0,
                      max: 12,
                      onChanged: (v) => setSheetState(() => bridgeGap = v),
                    ),
                    sliderRow(
                      label: '后清刺长度(post)',
                      value: postSpurPruneLen,
                      min: 0,
                      max: 12,
                      onChanged: (v) => setSheetState(() => postSpurPruneLen = v),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            setSheetState(() {
                              preSpurPruneLen = 6;
                              tinyComponentSize = 4;
                              bridgeGap = 6;
                              postSpurPruneLen = 4;
                            });
                          },
                          child: const Text('恢复默认'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('应用并重跑'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (applied == true && mounted) {
      setState(() {
        _preSpurPruneLen = preSpurPruneLen;
        _tinyComponentSize = tinyComponentSize;
        _bridgeGap = bridgeGap;
        _postSpurPruneLen = postSpurPruneLen;
      });

      final t = _charController.text;
      if (t.isNotEmpty) {
        _runDebug(t.characters.first);
      }
    }
  }

  Widget _buildLegend(ThemeData theme) {
    final legends = <({Color color, String label})>[];

    switch (_selectedStage) {
      case 0:
        legends.addAll([
          (color: Colors.blue, label: '轮廓点'),
        ]);
      case 1:
        legends.addAll([
          (color: Colors.black, label: '前景像素'),
        ]);
      case 2:
        legends.addAll([
          (color: Colors.grey.shade300, label: '原始填充'),
          (color: Colors.red, label: '骨架像素'),
        ]);
      case 3 || 4 || 5 || 6 || 7:
        legends.addAll([
          (color: Colors.grey.shade300, label: '骨架'),
          (color: Colors.red, label: '笔画 1'),
          (color: Colors.blue, label: '笔画 2'),
          (color: Colors.green, label: '笔画 3'),
          (color: Colors.orange, label: '更多…'),
          (color: Colors.purple.shade300, label: '模板笔画'),
        ]);
      case 8:
        legends.addAll([
          (color: Colors.red, label: '笔画 1'),
          (color: Colors.blue, label: '笔画 2'),
          (color: Colors.green, label: '笔画 3'),
        ]);
    }

    if (legends.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: legends
            .map(
              (l) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: l.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(l.label, style: theme.textTheme.bodySmall),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  bool _stageHasData(int stage) {
    final d = _debugData;
    if (d == null) return false;
    return switch (stage) {
      0 => d.sampledContours != null,
      1 => d.rasterBitmap != null,
      2 => d.skeletonBitmap != null,
      3 => d.rawVectorStrokes != null,
      4 => d.chainedStrokes != null,
      5 => d.alignedStrokes != null,
      6 => d.repairedStrokes != null,
      7 => d.finalizedStrokes != null,
      8 => d.finalGlyph != null,
      _ => false,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 可视化 Painter
// ─────────────────────────────────────────────────────────────────────────────

/// 每个阶段的颜色列表（用于区分不同笔画）
const _strokeColors = [
  Colors.red,
  Colors.blue,
  Colors.green,
  Colors.orange,
  Colors.teal,
  Colors.purple,
  Colors.pink,
  Colors.indigo,
  Colors.brown,
  Colors.cyan,
  Colors.amber,
  Colors.lime,
  Colors.deepOrange,
  Colors.lightBlue,
  Colors.deepPurple,
];

class _StageVisualizationPainter extends CustomPainter {
  final GlyphDebugData data;
  final int stage;

  _StageVisualizationPainter({required this.data, required this.stage});

  @override
  void paint(Canvas canvas, Size size) {
    switch (stage) {
      case 0:
        _paintContours(canvas, size);
      case 1:
        _paintBitmap(canvas, size, data.rasterBitmap, Colors.black);
      case 2:
        _paintSkeleton(canvas, size);
      case 3:
        _paintStrokes(canvas, size, data.rawVectorStrokes, showSkeleton: true);
      case 4:
        _paintStrokes(canvas, size, data.chainedStrokes,
            showSkeleton: true, showTemplate: true);
      case 5:
        _paintStrokes(canvas, size, data.alignedStrokes,
            showSkeleton: true, showTemplate: true);
      case 6:
        _paintStrokes(canvas, size, data.repairedStrokes,
            showSkeleton: true, showTemplate: true);
      case 7:
        _paintStrokes(canvas, size, data.finalizedStrokes,
            showSkeleton: true, showTemplate: true);
      case 8:
        _paintFinalGlyph(canvas, size);
    }
  }

  void _paintContours(Canvas canvas, Size size) {
    final contours = data.sampledContours;
    if (contours == null) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.blue;

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.blue.withValues(alpha: 0.08);

    for (int ci = 0; ci < contours.length; ci++) {
      final contour = contours[ci];
      if (contour.length < 2) continue;

      final path = Path();
      path.moveTo(contour.first.x * size.width, contour.first.y * size.height);
      for (final p in contour.skip(1)) {
        path.lineTo(p.x * size.width, p.y * size.height);
      }
      path.close();
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, paint);
    }

    // 标记起点
    final dotPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    for (final contour in contours) {
      if (contour.isEmpty) continue;
      canvas.drawCircle(
        Offset(contour.first.x * size.width, contour.first.y * size.height),
        3,
        dotPaint,
      );
    }
  }

  void _paintBitmap(Canvas canvas, Size size, GlyphBitmap? bm, Color color) {
    if (bm == null) return;
    final pw = size.width / bm.width;
    final ph = size.height / bm.height;

    final paint = Paint()..color = color;

    for (int y = 0; y < bm.height; y++) {
      for (int x = 0; x < bm.width; x++) {
        if (bm.isSet(x, y)) {
          canvas.drawRect(
            Rect.fromLTWH(x * pw, y * ph, pw.ceilToDouble(), ph.ceilToDouble()),
            paint,
          );
        }
      }
    }
  }

  void _paintSkeleton(Canvas canvas, Size size) {
    // 先画原始填充（淡灰色）
    final bm = data.rasterBitmap;
    if (bm != null) {
      final pw = size.width / bm.width;
      final ph = size.height / bm.height;
      final paint = Paint()..color = Colors.grey.shade200;
      for (int y = 0; y < bm.height; y++) {
        for (int x = 0; x < bm.width; x++) {
          if (bm.isSet(x, y)) {
            canvas.drawRect(
              Rect.fromLTWH(x * pw, y * ph, pw.ceilToDouble(), ph.ceilToDouble()),
              paint,
            );
          }
        }
      }
    }

    // 再画骨架（红色）
    final sk = data.skeletonBitmap;
    if (sk != null) {
      final pw = size.width / sk.width;
      final ph = size.height / sk.height;
      final paint = Paint()..color = Colors.red;
      for (int y = 0; y < sk.height; y++) {
        for (int x = 0; x < sk.width; x++) {
          if (sk.isSet(x, y)) {
            canvas.drawRect(
              Rect.fromLTWH(x * pw, y * ph, pw.ceilToDouble(), ph.ceilToDouble()),
              paint,
            );
          }
        }
      }
    }
  }

  void _paintStrokes(Canvas canvas, Size size, List<SkeletonStroke>? strokes,
      {bool showSkeleton = false, bool showTemplate = false}) {
    // 背景：淡灰骨架
    if (showSkeleton) {
      final sk = data.skeletonBitmap;
      if (sk != null) {
        final pw = size.width / sk.width;
        final ph = size.height / sk.height;
        final paint = Paint()..color = Colors.grey.shade200;
        for (int y = 0; y < sk.height; y++) {
          for (int x = 0; x < sk.width; x++) {
            if (sk.isSet(x, y)) {
              canvas.drawRect(
                Rect.fromLTWH(x * pw, y * ph, pw.ceilToDouble(), ph.ceilToDouble()),
                paint,
              );
            }
          }
        }
      }
    }

    // 画模板笔画（紫色虚线）
    if (showTemplate && data.templateStrokes != null) {
      for (final tStroke in data.templateStrokes!) {
        if (tStroke.length < 2) continue;
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.purple.shade300;

        final path = Path();
        path.moveTo(tStroke.first.x * size.width, tStroke.first.y * size.height);
        for (final p in tStroke.skip(1)) {
          path.lineTo(p.x * size.width, p.y * size.height);
        }
        canvas.drawPath(path, paint);
      }
    }

    if (strokes == null) return;

    // 画每个笔画（不同颜色）
    for (int si = 0; si < strokes.length; si++) {
      final stroke = strokes[si];
      if (stroke.points.length < 2) continue;

      final color = _strokeColors[si % _strokeColors.length];
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color;

      final path = Path();
      final pts = stroke.points;
      path.moveTo(pts.first.x * size.width, pts.first.y * size.height);
      for (final p in pts.skip(1)) {
        path.lineTo(p.x * size.width, p.y * size.height);
      }
      canvas.drawPath(path, paint);

      // 起点：实心圆
      canvas.drawCircle(
        Offset(pts.first.x * size.width, pts.first.y * size.height),
        4,
        Paint()..color = color,
      );

      // 终点：空心圆
      canvas.drawCircle(
        Offset(pts.last.x * size.width, pts.last.y * size.height),
        4,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // 笔画编号
      final tp = TextPainter(
        text: TextSpan(
          text: '${si + 1}',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          pts.first.x * size.width + 6,
          pts.first.y * size.height - 6,
        ),
      );
    }
  }

  void _paintFinalGlyph(Canvas canvas, Size size) {
    final glyph = data.finalGlyph;
    if (glyph == null) return;

    for (int si = 0; si < glyph.strokes.length; si++) {
      final stroke = glyph.strokes[si];
      if (stroke.points.length < 2) continue;

      final color = _strokeColors[si % _strokeColors.length];
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color;

      final path = Path();
      path.moveTo(
        stroke.points.first.x * size.width,
        stroke.points.first.y * size.height,
      );
      for (final p in stroke.points.skip(1)) {
        path.lineTo(p.x * size.width, p.y * size.height);
      }
      canvas.drawPath(path, paint);

      // 起点实心圆
      canvas.drawCircle(
        Offset(
          stroke.points.first.x * size.width,
          stroke.points.first.y * size.height,
        ),
        5,
        Paint()..color = color,
      );

      // 终点空心圆
      canvas.drawCircle(
        Offset(
          stroke.points.last.x * size.width,
          stroke.points.last.y * size.height,
        ),
        5,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      // 笔画编号
      final tp = TextPainter(
        text: TextSpan(
          text: '${si + 1}',
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          stroke.points.first.x * size.width + 7,
          stroke.points.first.y * size.height - 7,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_StageVisualizationPainter old) =>
      old.stage != stage || old.data != data;
}
