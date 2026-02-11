import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// 字符分割服务
/// 
/// 从图像中自动检测并分割出单个汉字
class CharacterSegmenter {
  
  /// 分割图像中的所有字符
  /// 
  /// 返回每个字符的图像数据和位置信息
  Future<SegmentationResult> segment(Uint8List binaryImageBytes) async {
    final image = img.decodeImage(binaryImageBytes);
    if (image == null) throw Exception('无法解码图像');
    
    // 1. 确保是二值图像
    final binary = _ensureBinary(image);
    
    // 2. 连通域分析
    final components = _findConnectedComponents(binary);
    
    // 3. 过滤和合并组件（去除太小的噪点，合并太近的组件）
    final filtered = _filterAndMergeComponents(components, binary.width, binary.height);
    
    // 4. 排序（从左到右，从上到下）
    final sorted = _sortComponents(filtered);
    
    // 5. 提取每个字符图像
    final characters = <SegmentedCharacter>[];
    for (int i = 0; i < sorted.length; i++) {
      final bbox = sorted[i];
      final charImage = _extractCharacter(binary, bbox);
      characters.add(SegmentedCharacter(
        index: i,
        boundingBox: bbox,
        imageData: img.encodePng(charImage),
        image: charImage,
      ));
    }
    
    return SegmentationResult(
      originalImage: binaryImageBytes,
      characters: characters,
      totalFound: characters.length,
    );
  }
  
  /// 确保图像是二值的
  img.Image _ensureBinary(img.Image src) {
    final result = img.Image(width: src.width, height: src.height);
    
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final pixel = src.getPixel(x, y);
        final gray = (pixel.r + pixel.g + pixel.b) ~/ 3;
        if (gray < 128) {
          result.setPixel(x, y, img.ColorRgb8(0, 0, 0));
        } else {
          result.setPixel(x, y, img.ColorRgb8(255, 255, 255));
        }
      }
    }
    
    return result;
  }
  
  /// 连通域分析（使用泛洪填充）
  List<BoundingBox> _findConnectedComponents(img.Image binary) {
    final width = binary.width;
    final height = binary.height;
    final visited = List.generate(height, (_) => List.filled(width, false));
    final components = <BoundingBox>[];
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (visited[y][x]) continue;
        
        final pixel = binary.getPixel(x, y);
        if (pixel.r > 128) {
          visited[y][x] = true;
          continue; // 白色背景，跳过
        }
        
        // 找到一个黑色像素，开始泛洪填充
        final bbox = _floodFill(binary, x, y, visited);
        if (bbox != null) {
          components.add(bbox);
        }
      }
    }
    
    return components;
  }
  
  /// 泛洪填充，返回边界框
  BoundingBox? _floodFill(
    img.Image binary, 
    int startX, 
    int startY, 
    List<List<bool>> visited,
  ) {
    final width = binary.width;
    final height = binary.height;
    
    int minX = startX, maxX = startX;
    int minY = startY, maxY = startY;
    int pixelCount = 0;
    
    final queue = <Point>[Point(startX, startY)];
    visited[startY][startX] = true;
    
    while (queue.isNotEmpty) {
      final p = queue.removeAt(0);
      pixelCount++;
      
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
      
      // 检查4邻域
      for (final dir in [Point(-1, 0), Point(1, 0), Point(0, -1), Point(0, 1)]) {
        final nx = p.x + dir.x;
        final ny = p.y + dir.y;
        
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
        if (visited[ny][nx]) continue;
        
        final pixel = binary.getPixel(nx, ny);
        if (pixel.r < 128) { // 黑色像素
          visited[ny][nx] = true;
          queue.add(Point(nx, ny));
        }
      }
    }
    
    // 忽略太小的组件（噪点）
    if (pixelCount < 20) return null;
    
    return BoundingBox(
      x: minX,
      y: minY,
      width: maxX - minX + 1,
      height: maxY - minY + 1,
      pixelCount: pixelCount,
    );
  }
  
  /// 过滤和合并组件
  List<BoundingBox> _filterAndMergeComponents(
    List<BoundingBox> components,
    int imageWidth,
    int imageHeight,
  ) {
    if (components.isEmpty) return [];
    
    // 估算平均字符大小
    final areas = components.map((c) => c.width * c.height).toList()..sort();
    final medianArea = areas[areas.length ~/ 2];
    final expectedSize = math.sqrt(medianArea);
    
    // 过滤太小或太大的组件
    final filtered = components.where((c) {
      final area = c.width * c.height;
      // 太小（小于中位数的1/10）可能是噪点
      if (area < medianArea / 10) return false;
      // 太大（大于中位数的10倍）可能是多个字连在一起
      // 暂时保留，后续可以尝试分割
      return true;
    }).toList();
    
    // 合并太近的组件（可能是同一个字的断开部分）
    final merged = <BoundingBox>[];
    final used = List.filled(filtered.length, false);
    
    for (int i = 0; i < filtered.length; i++) {
      if (used[i]) continue;
      
      var current = filtered[i];
      used[i] = true;
      
      // 查找可以合并的组件
      bool changed = true;
      while (changed) {
        changed = false;
        for (int j = 0; j < filtered.length; j++) {
          if (used[j]) continue;
          
          final other = filtered[j];
          // 如果两个组件很近，合并它们
          if (_shouldMerge(current, other, expectedSize)) {
            current = _mergeBoxes(current, other);
            used[j] = true;
            changed = true;
          }
        }
      }
      
      merged.add(current);
    }
    
    return merged;
  }
  
  /// 判断两个组件是否应该合并
  bool _shouldMerge(BoundingBox a, BoundingBox b, double expectedSize) {
    // 计算两个框之间的距离
    final dx = _boxDistance(a.x, a.x + a.width, b.x, b.x + b.width);
    final dy = _boxDistance(a.y, a.y + a.height, b.y, b.y + b.height);
    
    // 如果距离小于预期字符大小的1/4，合并
    final threshold = expectedSize / 4;
    return dx < threshold && dy < threshold;
  }
  
  /// 计算一维区间距离
  double _boxDistance(int aMin, int aMax, int bMin, int bMax) {
    if (aMax < bMin) return (bMin - aMax).toDouble();
    if (bMax < aMin) return (aMin - bMax).toDouble();
    return 0; // 重叠
  }
  
  /// 合并两个边界框
  BoundingBox _mergeBoxes(BoundingBox a, BoundingBox b) {
    final minX = math.min(a.x, b.x);
    final minY = math.min(a.y, b.y);
    final maxX = math.max(a.x + a.width, b.x + b.width);
    final maxY = math.max(a.y + a.height, b.y + b.height);
    
    return BoundingBox(
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY,
      pixelCount: a.pixelCount + b.pixelCount,
    );
  }
  
  /// 排序组件（从上到下，从左到右）
  List<BoundingBox> _sortComponents(List<BoundingBox> components) {
    if (components.isEmpty) return [];
    
    // 估算行高
    final heights = components.map((c) => c.height).toList()..sort();
    final medianHeight = heights[heights.length ~/ 2];
    final rowThreshold = medianHeight * 0.5;
    
    // 按行分组
    final rows = <List<BoundingBox>>[];
    final sorted = List<BoundingBox>.from(components)
      ..sort((a, b) => a.y.compareTo(b.y));
    
    for (final comp in sorted) {
      bool addedToRow = false;
      for (final row in rows) {
        // 如果和这一行的中心Y坐标接近，加入这一行
        final rowCenterY = row.map((c) => c.y + c.height / 2).reduce((a, b) => a + b) / row.length;
        final compCenterY = comp.y + comp.height / 2;
        if ((compCenterY - rowCenterY).abs() < rowThreshold) {
          row.add(comp);
          addedToRow = true;
          break;
        }
      }
      if (!addedToRow) {
        rows.add([comp]);
      }
    }
    
    // 每行内按X排序，然后合并
    final result = <BoundingBox>[];
    for (final row in rows) {
      row.sort((a, b) => a.x.compareTo(b.x));
      result.addAll(row);
    }
    
    return result;
  }
  
  /// 提取单个字符图像
  img.Image _extractCharacter(img.Image binary, BoundingBox bbox) {
    // 添加一些边距
    final margin = (math.min(bbox.width, bbox.height) * 0.1).round();
    
    final x = math.max(0, bbox.x - margin);
    final y = math.max(0, bbox.y - margin);
    final w = math.min(binary.width - x, bbox.width + margin * 2);
    final h = math.min(binary.height - y, bbox.height + margin * 2);
    
    final extracted = img.copyCrop(binary, x: x, y: y, width: w, height: h);
    
    // 调整为正方形（汉字通常是方形的）
    final size = math.max(extracted.width, extracted.height);
    final squared = img.Image(width: size, height: size);
    
    // 填充白色背景
    for (int py = 0; py < size; py++) {
      for (int px = 0; px < size; px++) {
        squared.setPixel(px, py, img.ColorRgb8(255, 255, 255));
      }
    }
    
    // 居中放置
    final offsetX = (size - extracted.width) ~/ 2;
    final offsetY = (size - extracted.height) ~/ 2;
    
    for (int py = 0; py < extracted.height; py++) {
      for (int px = 0; px < extracted.width; px++) {
        squared.setPixel(offsetX + px, offsetY + py, extracted.getPixel(px, py));
      }
    }
    
    // 统一缩放到标准尺寸
    return img.copyResize(squared, width: 128, height: 128);
  }
}

/// 点
class Point {
  final int x;
  final int y;
  Point(this.x, this.y);
}

/// 边界框
class BoundingBox {
  final int x;
  final int y;
  final int width;
  final int height;
  final int pixelCount;
  
  BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.pixelCount,
  });
  
  int get centerX => x + width ~/ 2;
  int get centerY => y + height ~/ 2;
  int get area => width * height;
  
  @override
  String toString() => 'Box($x, $y, ${width}x$height)';
}

/// 分割后的单个字符
class SegmentedCharacter {
  final int index;
  final BoundingBox boundingBox;
  final Uint8List imageData;
  final img.Image image;
  
  SegmentedCharacter({
    required this.index,
    required this.boundingBox,
    required this.imageData,
    required this.image,
  });
}

/// 分割结果
class SegmentationResult {
  final Uint8List originalImage;
  final List<SegmentedCharacter> characters;
  final int totalFound;
  
  SegmentationResult({
    required this.originalImage,
    required this.characters,
    required this.totalFound,
  });
}