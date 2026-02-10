import 'package:flutter/material.dart';

import '../demo/fake_toolpath.dart';
import '../model/essay_grid.dart';
import '../model/page.dart';
import '../model/toolpath_painter.dart';
import '../render/page_painter.dart';
import '../render/viewport.dart' as kp;

class WritingDemoPage extends StatelessWidget {
  const WritingDemoPage({super.key});

  static const PageMm _a4 = PageMm(widthMm: 210, heightMm: 297);

  @override
  Widget build(BuildContext context) {
    final grid = defaultA4EssayGrid();
    final toolPath = buildFakeEssayToolPath(grid: grid);

    return Scaffold(
      appBar: AppBar(title: const Text('Writing Demo')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = _fitA4Viewport(
            available: Size(constraints.maxWidth, constraints.maxHeight),
            page: _a4,
          );

          return CustomPaint(
            size: Size.infinite,
            painter: PagePainter(page: _a4, grid: grid, viewport: viewport),
            foregroundPainter: ToolPathPainter(
              toolPath: toolPath,
              viewport: viewport,
              penWidthMm: 0.6,
            ),
          );
        },
      ),
    );
  }

  kp.Viewport _fitA4Viewport({required Size available, required PageMm page}) {
    const outerPaddingPx = 16.0;
    final usableW = (available.width - outerPaddingPx * 2).clamp(
      1.0,
      double.infinity,
    );
    final usableH = (available.height - outerPaddingPx * 2).clamp(
      1.0,
      double.infinity,
    );

    final scale =
        (usableW / page.widthMm).clamp(0.1, double.infinity) <
            (usableH / page.heightMm)
        ? (usableW / page.widthMm)
        : (usableH / page.heightMm);

    final pageWpx = page.widthMm * scale;
    final pageHpx = page.heightMm * scale;

    final pan = Offset(
      (available.width - pageWpx) / 2,
      (available.height - pageHpx) / 2,
    );

    return kp.Viewport(scale: scale, pan: pan);
  }
}
