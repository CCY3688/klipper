import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// 骨架提取服务
/// 
/// 使用 Zhang-Suen 细化算法提取笔画骨架
class SkeletonExtractor {
  
  /// 提取骨架
  /// 
  /// 输入：二值图像（黑色为笔画）
  /// 输出：骨架点列表和骨架图像
  Future<SkeletonResult> extract(Uint8List binaryImageBytes) async {
    final image = img.decodeImage(binaryImageBytes);
    if (image == null) throw Exception('无法解码图像');
    
    // 1. 转换为二值矩阵
    final binary = _toBinaryMatrix(image);
    
    // 2. Zhang-Suen 细化
    final skeleton = _zhangSuenThinning(binary);
    
    // 3. 提取骨架点
    final points = _extractSkeletonPoints(skeleton);
    
    // 4. 追踪笔画路径
    final strokes = _traceStrokes(skeleton, points);
    
    // 5. 生成骨架图像
    final skeletonImage = _toImage(skeleton, image.width, image.height);
    
    return SkeletonResult(
      skeletonImage: img.encodePng(skeletonImage),
      skeletonPoints: points,
      strokes: strokes,
      width: image.width,
      height: image.height,
    );
  }
  
  /// 转换为二值矩阵（1=黑色/笔画，0=白色/背景）
  List<List<int>> _toBinaryMatrix(img.Image image) {
    final matrix = List.generate(
      image.height,
      (y) => List.generate(image.width, (x) {
        final pixel = image.getPixel(x, y);
        return pixel.r < 128 ? 1 : 0;
      }),
    );
    return matrix;
  }
  
  /// Zhang-Suen 细化算法
  /// 
  /// 迭代删除边界像素，直到得到单像素宽的骨架
  List<List<int>> _zhangSuenThinning(List<List<int>> input) {
    final height = input.length;
    final width = input[0].length;
    
    // 复制输入
    var image = List.generate(height, (y) => List<int>.from(input[y]));
    
    bool changed = true;
    while (changed) {
      changed = false;
      
      // 第一次子迭代
      final toRemove1 = <Point>[];
      for (int y = 1; y < height - 1; y++) {
        for (int x = 1; x < width - 1; x++) {
          if (image[y][x] == 1 && _shouldRemoveStep1(image, x, y)) {
            toRemove1.add(Point(x, y));
          }
        }
      }
      for (final p in toRemove1) {
        image[p.y][p.x] = 0;
        changed = true;
      }
      
      // 第二次子迭代
      final toRemove2 = <Point>[];
      for (int y = 1; y < height - 1; y++) {
        for (int x = 1; x < width - 1; x++) {
          if (image[y][x] == 1 && _shouldRemoveStep2(image, x, y)) {
            toRemove2.add(Point(x, y));
          }
        }
      }
      for (final p in toRemove2) {
        image[p.y][p.x] = 0;
        changed = true;
      }
    }
    
    return image;
  }
  
  /// 获取 8 邻域像素值 (P2-P9，顺时针)
  ///  P9 P2 P3
  ///  P8 P1 P4
  ///  P7 P6 P5
  List<int> _getNeighbors(List<List<int>> image, int x, int y) {
    return [
      image[y - 1][x],     // P2
      image[y - 1][x + 1], // P3
      image[y][x + 1],     // P4
      image[y + 1][x + 1], // P5
      image[y + 1][x],     // P6
      image[y + 1][x - 1], // P7
      image[y][x - 1],     // P8
      image[y - 1][x - 1], // P9
    ];
  }
  
  /// 计算 B(P1) - 非零邻域数
  int _countNonZeroNeighbors(List<int> neighbors) {
    return neighbors.where((n) => n == 1).length;
  }
  
  /// 计算 A(P1) - 0到1的跳变次数（顺时针）
  int _countTransitions(List<int> neighbors) {
    int count = 0;
    for (int i = 0; i < 8; i++) {
      if (neighbors[i] == 0 && neighbors[(i + 1) % 8] == 1) {
        count++;
      }
    }
    return count;
  }
  
  /// 第一步删除条件
  bool _shouldRemoveStep1(List<List<int>> image, int x, int y) {
    final neighbors = _getNeighbors(image, x, y);
    final b = _countNonZeroNeighbors(neighbors);
    final a = _countTransitions(neighbors);
    
    // 条件：
    // (a) 2 <= B(P1) <= 6
    // (b) A(P1) = 1
    // (c) P2 * P4 * P6 = 0
    // (d) P4 * P6 * P8 = 0
    
    if (b < 2 || b > 6) return false;
    if (a != 1) return false;
    if (neighbors[0] * neighbors[2] * neighbors[4] != 0) return false;
    if (neighbors[2] * neighbors[4] * neighbors[6] != 0) return false;
    
    return true;
  }
  
  /// 第二步删除条件
  bool _shouldRemoveStep2(List<List<int>> image, int x, int y) {
    final neighbors = _getNeighbors(image, x, y);
    final b = _countNonZeroNeighbors(neighbors);
    final a = _countTransitions(neighbors);
    
    // 条件：
    // (a) 2 <= B(P1) <= 6
    // (b) A(P1) = 1
    // (c) P2 * P4 * P8 = 0
    // (d) P2 * P6 * P8 = 0
    
    if (b < 2 || b > 6) return false;
    if (a != 1) return false;
    if (neighbors[0] * neighbors[2] * neighbors[6] != 0) return false;
    if (neighbors[0] * neighbors[4] * neighbors[6] != 0) return false;
    
    return true;
  }
  
  /// 提取骨架点
  List<SkeletonPoint> _extractSkeletonPoints(List<List<int>> skeleton) {
    final points = <SkeletonPoint>[];
    final height = skeleton.length;
    final width = skeleton[0].length;
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (skeleton[y][x] == 1) {
          final neighbors = _countNeighbors8(skeleton, x, y);
          final type = _classifyPoint(neighbors);
          points.add(SkeletonPoint(
            x: x,
            y: y,
            type: type,
            neighborCount: neighbors,
          ));
        }
      }
    }
    
    return points;
  }
  
  /// 计算 8 邻域非零点数
  int _countNeighbors8(List<List<int>> image, int x, int y) {
    int count = 0;
    final height = image.length;
    final width = image[0].length;
    
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
          if (image[ny][nx] == 1) count++;
        }
      }
    }
    
    return count;
  }
  
  /// 分类骨架点
  PointType _classifyPoint(int neighborCount) {
    if (neighborCount == 1) return PointType.endpoint;
    if (neighborCount == 2) return PointType.normal;
    if (neighborCount >= 3) return PointType.junction;
    return PointType.isolated;
  }
  
  /// 追踪笔画路径
  List<StrokePath> _traceStrokes(List<List<int>> skeleton, List<SkeletonPoint> points) {
    final height = skeleton.length;
    final width = skeleton[0].length;
    
    // 创建访问标记
    final visited = List.generate(height, (_) => List.filled(width, false));
    
    // 找到所有端点和交叉点
    final endpoints = points.where((p) => p.type == PointType.endpoint).toList();
    final junctions = points.where((p) => p.type == PointType.junction).toList();
    
    final strokes = <StrokePath>[];
    
    // 从每个端点开始追踪
    for (final start in endpoints) {
      if (visited[start.y][start.x]) continue;
      
      final path = _tracePath(skeleton, start.x, start.y, visited);
      if (path.length >= 3) { // 至少3个点才算有效笔画
        strokes.add(StrokePath(points: path));
      }
    }
    
    // 处理可能遗漏的闭合曲线
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (skeleton[y][x] == 1 && !visited[y][x]) {
          final path = _tracePath(skeleton, x, y, visited);
          if (path.length >= 3) {
            strokes.add(StrokePath(points: path));
          }
        }
      }
    }
    
    return strokes;
  }
  
  /// 从指定点开始追踪路径
  List<Point> _tracePath(
    List<List<int>> skeleton,
    int startX,
    int startY,
    List<List<bool>> visited,
  ) {
    final path = <Point>[];
    final height = skeleton.length;
    final width = skeleton[0].length;
    
    int x = startX;
    int y = startY;
    
    while (true) {
      if (x < 0 || x >= width || y < 0 || y >= height) break;
      if (skeleton[y][x] != 1) break;
      if (visited[y][x]) break;
      
      visited[y][x] = true;
      path.add(Point(x, y));
      
      // 找下一个未访问的邻居
      bool found = false;
      for (final dir in _directions) {
        final nx = x + dir.x;
        final ny = y + dir.y;
        
        if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
          if (skeleton[ny][nx] == 1 && !visited[ny][nx]) {
            x = nx;
            y = ny;
            found = true;
            break;
          }
        }
      }
      
      if (!found) break;
    }
    
    return path;
  }
  
  // 8个方向，优先直线方向
  static final _directions = [
    Point(1, 0), Point(-1, 0), Point(0, 1), Point(0, -1),
    Point(1, 1), Point(1, -1), Point(-1, 1), Point(-1, -1),
  ];
  
  /// 将骨架矩阵转换为图像
  img.Image _toImage(List<List<int>> skeleton, int width, int height) {
    final image = img.Image(width: width, height: height);
    
    // 白色背景
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        image.setPixel(x, y, img.ColorRgb8(255, 255, 255));
      }
    }
    
    // 绘制骨架（红色）
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (skeleton[y][x] == 1) {
          image.setPixel(x, y, img.ColorRgb8(255, 0, 0));
        }
      }
    }
    
    return image;
  }
}

/// 点
class Point {
  final int x;
  final int y;
  Point(this.x, this.y);
  
  @override
  String toString() => '($x, $y)';
}

/// 骨架点类型
enum PointType {
  isolated,  // 孤立点
  endpoint,  // 端点（1个邻居）
  normal,    // 普通点（2个邻居）
  junction,  // 交叉点（3+个邻居）
}

/// 骨架点
class SkeletonPoint {
  final int x;
  final int y;
  final PointType type;
  final int neighborCount;
  
  SkeletonPoint({
    required this.x,
    required this.y,
    required this.type,
    required this.neighborCount,
  });
}

/// 笔画路径
class StrokePath {
  final List<Point> points;
  
  StrokePath({required this.points});
  
  int get length => points.length;
  
  Point get start => points.first;
  Point get end => points.last;
  
  /// 转换为中线格式（兼容字库格式）
  List<List<int>> toMedian() {
    return points.map((p) => [p.x, p.y]).toList();
  }
  
  /// 简化路径（减少点数）
  StrokePath simplify({double tolerance = 2.0}) {
    if (points.length <= 2) return this;
    
    final simplified = _douglasPeucker(points, tolerance);
    return StrokePath(points: simplified);
  }
  
  /// Douglas-Peucker 简化算法
  List<Point> _douglasPeucker(List<Point> points, double tolerance) {
    if (points.length <= 2) return points;
    
    // 找到距离首尾连线最远的点
    double maxDist = 0;
    int maxIndex = 0;
    
    final first = points.first;
    final last = points.last;
    
    for (int i = 1; i < points.length - 1; i++) {
      final dist = _perpendicularDistance(points[i], first, last);
      if (dist > maxDist) {
        maxDist = dist;
        maxIndex = i;
      }
    }
    
    if (maxDist > tolerance) {
      // 递归简化
      final left = _douglasPeucker(points.sublist(0, maxIndex + 1), tolerance);
      final right = _douglasPeucker(points.sublist(maxIndex), tolerance);
      
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [first, last];
    }
  }
  
  /// 点到线段的垂直距离
  double _perpendicularDistance(Point p, Point lineStart, Point lineEnd) {
    final dx = lineEnd.x - lineStart.x;
    final dy = lineEnd.y - lineStart.y;
    
    if (dx == 0 && dy == 0) {
      return math.sqrt(
        math.pow(p.x - lineStart.x, 2) + math.pow(p.y - lineStart.y, 2)
      );
    }
    
    final t = ((p.x - lineStart.x) * dx + (p.y - lineStart.y) * dy) / 
              (dx * dx + dy * dy);
    
    final projX = lineStart.x + t * dx;
    final projY = lineStart.y + t * dy;
    
    return math.sqrt(math.pow(p.x - projX, 2) + math.pow(p.y - projY, 2));
  }
}

/// 骨架提取结果
class SkeletonResult {
  final Uint8List skeletonImage;
  final List<SkeletonPoint> skeletonPoints;
  final List<StrokePath> strokes;
  final int width;
  final int height;
  
  SkeletonResult({
    required this.skeletonImage,
    required this.skeletonPoints,
    required this.strokes,
    required this.width,
    required this.height,
  });
  
  /// 端点数量
  int get endpointCount => 
      skeletonPoints.where((p) => p.type == PointType.endpoint).length;
  
  /// 交叉点数量
  int get junctionCount => 
      skeletonPoints.where((p) => p.type == PointType.junction).length;
  
  /// 总笔画数
  int get strokeCount => strokes.length;
}