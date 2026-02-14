import 'dart:typed_data';
import 'package:image/image.dart' as img;

import '../models/sample_template.dart';

/// 网格分割器
///
/// 与 [CharacterSegmenter] 不同，此分割器利用模板的已知网格布局，
/// 直接按固定位置将图像切割为单元格，不需要做连通域分析。
///
/// 前提条件：用户的照片已经过裁剪/透视校正，使得网格区域与图像边缘对齐。
class GridSegmenter {
  /// 按网格分割图像
  ///
  /// [imageBytes]  预处理后的二值图像
  /// [template]    模板定义（列数、行数即可）
  /// [outerBorder] 人工选中的外边框区域（归一化坐标 0~1），为空时默认整图
  /// [normalize]   是否将每个单元格归一化为正方形并标准化大小
  /// [outputSize]  归一化后的输出尺寸
  Future<GridSegmentResult> segment(
    Uint8List imageBytes, {
    required SampleTemplate template,
    GridOuterBorder? outerBorder,
    bool normalize = true,
    int outputSize = 128,
  }) async {
    final image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('无法解码图像');

    final gridRect = _resolveGridRect(image, outerBorder);
    final cellW = gridRect.width / template.columns;
    final cellH = gridRect.height / template.rows;

    final cells = <GridCell>[];

    for (int row = 0; row < template.rows; row++) {
      for (int col = 0; col < template.columns; col++) {
        final index = row * template.columns + col;
        if (index >= template.characters.length) break;

        final character = template.characters[index];

        // 裁剪单元格（留 5% 内边距避免裁到格线）
        final padX = (cellW * 0.05).round();
        final padY = (cellH * 0.05).round();

        final cropX =
          (gridRect.left + col * cellW + padX).round().clamp(0, image.width - 1);
        final cropY =
          (gridRect.top + row * cellH + padY).round().clamp(0, image.height - 1);
        final cropW =
            (cellW - padX * 2).round().clamp(1, image.width - cropX);
        final cropH =
            (cellH - padY * 2).round().clamp(1, image.height - cropY);

        var cellImage = img.copyCrop(image,
            x: cropX, y: cropY, width: cropW, height: cropH);

        // 抑制模板格线，避免把横/竖边框当作笔画参与后续骨架分析
        cellImage = _suppressGridLines(cellImage);

        if (normalize) {
          cellImage = _normalizeCell(cellImage, outputSize);
        }

        cells.add(GridCell(
          row: row,
          col: col,
          index: index,
          character: character,
          imageData: Uint8List.fromList(img.encodePng(cellImage)),
          image: cellImage,
          hasInk: _hasSignificantInk(cellImage),
        ));
      }
    }

    return GridSegmentResult(
      cells: cells,
      rows: template.rows,
      columns: template.columns,
      template: template,
    );
  }

  _PixelRect _resolveGridRect(img.Image image, GridOuterBorder? outerBorder) {
    if (outerBorder == null) {
      return _PixelRect(left: 0, top: 0, width: image.width, height: image.height);
    }

    final left = (outerBorder.left * image.width)
        .round()
        .clamp(0, image.width - 1);
    final top = (outerBorder.top * image.height)
        .round()
        .clamp(0, image.height - 1);
    final width = (outerBorder.width * image.width)
        .round()
        .clamp(1, image.width - left);
    final height = (outerBorder.height * image.height)
        .round()
        .clamp(1, image.height - top);

    return _PixelRect(left: left, top: top, width: width, height: height);
  }

  /// 将单元格归一化为 outputSize × outputSize 的正方形
  img.Image _normalizeCell(img.Image source, int size) {
    // 先做正方形填充
    final maxDim = source.width > source.height ? source.width : source.height;
    final squared = img.Image(width: maxDim, height: maxDim);

    // 白色背景
    for (int y = 0; y < maxDim; y++) {
      for (int x = 0; x < maxDim; x++) {
        squared.setPixel(x, y, img.ColorRgb8(255, 255, 255));
      }
    }

    // 居中放置
    final ox = (maxDim - source.width) ~/ 2;
    final oy = (maxDim - source.height) ~/ 2;
    for (int y = 0; y < source.height; y++) {
      for (int x = 0; x < source.width; x++) {
        squared.setPixel(ox + x, oy + y, source.getPixel(x, y));
      }
    }

    return img.copyResize(squared, width: size, height: size);
  }

  /// 抑制网格线：
  /// 1) 清除单元格四周窄边带
  /// 2) 删除与边缘相连、且明显呈横/竖长线的连通域
  img.Image _suppressGridLines(img.Image source) {
    final cleaned = img.Image.from(source);
    final width = cleaned.width;
    final height = cleaned.height;

    // 先把四周 2%（至少1像素）的边带置白，去除大部分格线残留
    final bandX = (width * 0.02).round().clamp(1, 4);
    final bandY = (height * 0.02).round().clamp(1, 4);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < bandX; x++) {
        cleaned.setPixel(x, y, img.ColorRgb8(255, 255, 255));
      }
      for (int x = width - bandX; x < width; x++) {
        if (x >= 0 && x < width) {
          cleaned.setPixel(x, y, img.ColorRgb8(255, 255, 255));
        }
      }
    }

    for (int y = 0; y < bandY; y++) {
      for (int x = 0; x < width; x++) {
        cleaned.setPixel(x, y, img.ColorRgb8(255, 255, 255));
      }
    }
    for (int y = height - bandY; y < height; y++) {
      if (y >= 0 && y < height) {
        for (int x = 0; x < width; x++) {
          cleaned.setPixel(x, y, img.ColorRgb8(255, 255, 255));
        }
      }
    }

    // 再对“触边连通域”做长线过滤
    final visited = List.generate(height, (_) => List<bool>.filled(width, false));

    bool isInk(int x, int y) => cleaned.getPixel(x, y).r.toInt() < 128;

    for (int sy = 0; sy < height; sy++) {
      for (int sx = 0; sx < width; sx++) {
        if (visited[sy][sx] || !isInk(sx, sy)) continue;

        final queue = <(int x, int y)>[(sx, sy)];
        visited[sy][sx] = true;
        final points = <(int x, int y)>[];

        int minX = sx, maxX = sx, minY = sy, maxY = sy;
        bool touchesBorder = false;

        while (queue.isNotEmpty) {
          final p = queue.removeLast();
          final x = p.$1;
          final y = p.$2;
          points.add((x, y));

          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;

          if (x == 0 || y == 0 || x == width - 1 || y == height - 1) {
            touchesBorder = true;
          }

          for (int ny = y - 1; ny <= y + 1; ny++) {
            for (int nx = x - 1; nx <= x + 1; nx++) {
              if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
              if (visited[ny][nx]) continue;
              if (!isInk(nx, ny)) continue;

              visited[ny][nx] = true;
              queue.add((nx, ny));
            }
          }
        }

        if (!touchesBorder) continue;

        final boxW = maxX - minX + 1;
        final boxH = maxY - minY + 1;

        final isHorizontalBorderLine =
            boxW >= width * 0.70 && boxH <= height * 0.18;
        final isVerticalBorderLine =
            boxH >= height * 0.70 && boxW <= width * 0.18;

        if (isHorizontalBorderLine || isVerticalBorderLine) {
          for (final p in points) {
            cleaned.setPixel(p.$1, p.$2, img.ColorRgb8(255, 255, 255));
          }
        }
      }
    }

    return cleaned;
  }

  /// 检测单元格中是否有足够的墨迹
  bool _hasSignificantInk(img.Image cell) {
    int inkPixels = 0;
    final total = cell.width * cell.height;

    for (int y = 0; y < cell.height; y++) {
      for (int x = 0; x < cell.width; x++) {
        final p = cell.getPixel(x, y);
        if (p.r.toInt() < 128) inkPixels++;
      }
    }

    // 至少 1% 的像素为墨迹
    return inkPixels > total * 0.01;
  }
}

/// 人工框选的模板外边框（归一化坐标）
class GridOuterBorder {
  final double left;
  final double top;
  final double width;
  final double height;

  const GridOuterBorder({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  double get right => left + width;
  double get bottom => top + height;
}

class _PixelRect {
  final int left;
  final int top;
  final int width;
  final int height;

  const _PixelRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

/// 单个网格单元格
class GridCell {
  /// 行索引
  final int row;

  /// 列索引
  final int col;

  /// 在模板字符列表中的索引
  final int index;

  /// 对应的模板字符
  final String character;

  /// 单元格图像数据 (PNG)
  final Uint8List imageData;

  /// 单元格图像对象
  final img.Image image;

  /// 是否包含有效墨迹
  final bool hasInk;

  const GridCell({
    required this.row,
    required this.col,
    required this.index,
    required this.character,
    required this.imageData,
    required this.image,
    required this.hasInk,
  });
}

/// 网格分割结果
class GridSegmentResult {
  final List<GridCell> cells;
  final int rows;
  final int columns;
  final SampleTemplate template;

  const GridSegmentResult({
    required this.cells,
    required this.rows,
    required this.columns,
    required this.template,
  });

  /// 有效单元格（包含墨迹的）
  List<GridCell> get validCells => cells.where((c) => c.hasInk).toList();

  /// 有效率
  double get validRate =>
      cells.isNotEmpty ? validCells.length / cells.length : 0;

  /// 获取指定位置的单元格
  GridCell? cellAt(int row, int col) {
    final idx = row * columns + col;
    if (idx >= 0 && idx < cells.length) return cells[idx];
    return null;
  }
}
