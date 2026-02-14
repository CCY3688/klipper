import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// 图像处理服务
/// 
/// 提供手写图像的预处理功能：
/// - 灰度化
/// - 二值化
/// - 降噪
class ImageProcessor {
  
  /// 完整的预处理流程
  /// 
  /// 返回处理后的图像数据和各阶段结果
  Future<ImageProcessResult> process(Uint8List imageBytes) async {
    return processWithOptions(imageBytes, options: const ImageProcessOptions());
  }

  /// 使用可配置参数执行预处理流程
  Future<ImageProcessResult> processWithOptions(
    Uint8List imageBytes, {
    required ImageProcessOptions options,
  }) async {
    final stopwatch = Stopwatch()..start();
    final stages = <ProcessingStage>[];
    
    // 1. 解码图像
    final original = img.decodeImage(imageBytes);
    if (original == null) {
      throw Exception('无法解码图像');
    }
    stages.add(ProcessingStage(
      name: '原始图像',
      image: img.encodeJpg(original),
      duration: stopwatch.elapsedMilliseconds,
    ));
    
    // 2. 调整大小（如果图像太大）
    img.Image resized = original;
    if (options.maxSide > 0 &&
        (original.width > options.maxSide || original.height > options.maxSide)) {
      final scale = options.maxSide / (original.width > original.height 
          ? original.width 
          : original.height);
      resized = img.copyResize(
        original,
        width: (original.width * scale).round(),
        height: (original.height * scale).round(),
        interpolation: img.Interpolation.linear,
      );
      stages.add(ProcessingStage(
        name: '调整大小',
        image: img.encodeJpg(resized),
        duration: stopwatch.elapsedMilliseconds,
        info: '${resized.width}x${resized.height}',
      ));
    }
    
    // 3. 灰度化
    final grayscale = img.grayscale(resized);
    stages.add(ProcessingStage(
      name: '灰度化',
      image: img.encodeJpg(grayscale),
      duration: stopwatch.elapsedMilliseconds,
      info: '将彩色图像转换为8位灰度空间',
    ));
    
    // 4. 对比度增强
    final enhanced = img.adjustColor(
      grayscale,
      contrast: options.contrast,
    );
    stages.add(ProcessingStage(
      name: '对比度增强',
      image: img.encodeJpg(enhanced),
      duration: stopwatch.elapsedMilliseconds,
      info: '增强笔画与背景的视觉反差',
    ));
    
    // 5. 自适应二值化
    final binary = _adaptiveThreshold(
      enhanced,
      blockSize: options.blockSize,
      c: options.thresholdOffset,
    );
    stages.add(ProcessingStage(
      name: '二值化',
      image: img.encodePng(binary),
      duration: stopwatch.elapsedMilliseconds,
      info: '提取手写骨架，转换为纯黑白像素',
    ));
    
    // 6. 降噪（连通域小噪点过滤）
    // 说明：手写细笔画在开运算中容易被腐蚀掉，因此改为仅移除微小孤立连通域。
    final denoised = _removeSmallConnectedComponents(
      binary,
      minArea: options.minComponentArea,
    );
    stages.add(ProcessingStage(
      name: '降噪',
      image: img.encodePng(denoised),
      duration: stopwatch.elapsedMilliseconds,
      info: '移除离散噪点并尽量保留细笔画',
    ));
    
    stopwatch.stop();
    
    return ImageProcessResult(
      originalImage: imageBytes,
      processedImage: img.encodePng(denoised),
      binaryImage: denoised,
      stages: stages,
      totalDuration: stopwatch.elapsedMilliseconds,
      options: options,
    );
  }
  
  /// 自适应阈值二值化
  /// 
  /// 使用局部均值作为阈值，适合处理光照不均的图像
  img.Image _adaptiveThreshold(img.Image src, {
    int blockSize = 11,
    int c = 5,
  }) {
    final result = img.Image(width: src.width, height: src.height);
    final halfBlock = blockSize ~/ 2;
    
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        // 计算局部均值
        int sum = 0;
        int count = 0;
        
        for (int dy = -halfBlock; dy <= halfBlock; dy++) {
          for (int dx = -halfBlock; dx <= halfBlock; dx++) {
            final nx = x + dx;
            final ny = y + dy;
            if (nx >= 0 && nx < src.width && ny >= 0 && ny < src.height) {
              final pixel = src.getPixel(nx, ny);
              sum += pixel.r.toInt();
              count++;
            }
          }
        }
        
        final mean = sum / count;
        final pixel = src.getPixel(x, y);
        final value = pixel.r.toInt();
        
        // 如果像素值小于局部均值减去常数c，则为黑色（墨迹）
        if (value < mean - c) {
          result.setPixel(x, y, img.ColorRgb8(0, 0, 0));
        } else {
          result.setPixel(x, y, img.ColorRgb8(255, 255, 255));
        }
      }
    }
    
    return result;
  }
  
  /// 连通域降噪：仅删除面积过小的黑色孤立区域，避免细笔画被整体腐蚀
  img.Image _removeSmallConnectedComponents(
    img.Image src, {
    int minArea = 6,
  }) {
    final width = src.width;
    final height = src.height;
    final visited = Uint8List(width * height);
    final result = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        result.setPixel(x, y, img.ColorRgb8(255, 255, 255));
      }
    }

    int index(int x, int y) => y * width + x;
    bool isBlack(int x, int y) => src.getPixel(x, y).r < 128;

    const neighborOffsets = <List<int>>[
      [-1, -1], [0, -1], [1, -1],
      [-1, 0],           [1, 0],
      [-1, 1],  [0, 1],  [1, 1],
    ];

    final queueX = <int>[];
    final queueY = <int>[];

    for (int startY = 0; startY < height; startY++) {
      for (int startX = 0; startX < width; startX++) {
        final startIdx = index(startX, startY);
        if (visited[startIdx] == 1 || !isBlack(startX, startY)) {
          continue;
        }

        queueX.clear();
        queueY.clear();
        final componentX = <int>[];
        final componentY = <int>[];

        queueX.add(startX);
        queueY.add(startY);
        visited[startIdx] = 1;

        int head = 0;
        while (head < queueX.length) {
          final x = queueX[head];
          final y = queueY[head];
          head++;

          componentX.add(x);
          componentY.add(y);

          for (final offset in neighborOffsets) {
            final nx = x + offset[0];
            final ny = y + offset[1];
            if (nx < 0 || nx >= width || ny < 0 || ny >= height) {
              continue;
            }
            final nextIdx = index(nx, ny);
            if (visited[nextIdx] == 1 || !isBlack(nx, ny)) {
              continue;
            }
            visited[nextIdx] = 1;
            queueX.add(nx);
            queueY.add(ny);
          }
        }

        if (componentX.length >= minArea) {
          for (int i = 0; i < componentX.length; i++) {
            result.setPixel(componentX[i], componentY[i], img.ColorRgb8(0, 0, 0));
          }
        }
      }
    }

    return result;
  }
}

/// 处理阶段信息
class ProcessingStage {
  final String name;
  final Uint8List image;
  final int duration;
  final String? info;
  
  ProcessingStage({
    required this.name,
    required this.image,
    required this.duration,
    this.info,
  });
}

/// 图像处理结果
class ImageProcessResult {
  final Uint8List originalImage;
  final Uint8List processedImage;
  final img.Image binaryImage;
  final List<ProcessingStage> stages;
  final int totalDuration;
  final ImageProcessOptions options;
  
  ImageProcessResult({
    required this.originalImage,
    required this.processedImage,
    required this.binaryImage,
    required this.stages,
    required this.totalDuration,
    required this.options,
  });
}

/// 图像预处理高级参数
class ImageProcessOptions {
  /// 最大边长，<=0 表示不缩放
  final int maxSide;

  /// 对比度增强系数
  final double contrast;

  /// 自适应阈值窗口大小（奇数）
  final int blockSize;

  /// 自适应阈值偏移量（值越大越严格）
  final int thresholdOffset;

  /// 连通域去噪最小面积（像素）
  final int minComponentArea;

  const ImageProcessOptions({
    this.maxSide = 1024,
    this.contrast = 1.3,
    this.blockSize = 15,
    this.thresholdOffset = 4,
    this.minComponentArea = 6,
  });

  ImageProcessOptions copyWith({
    int? maxSide,
    double? contrast,
    int? blockSize,
    int? thresholdOffset,
    int? minComponentArea,
  }) {
    return ImageProcessOptions(
      maxSide: maxSide ?? this.maxSide,
      contrast: contrast ?? this.contrast,
      blockSize: blockSize ?? this.blockSize,
      thresholdOffset: thresholdOffset ?? this.thresholdOffset,
      minComponentArea: minComponentArea ?? this.minComponentArea,
    );
  }
}