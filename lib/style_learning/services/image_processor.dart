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
    if (original.width > 1024 || original.height > 1024) {
      final scale = 1024 / (original.width > original.height 
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
      contrast: 1.3,
    );
    stages.add(ProcessingStage(
      name: '对比度增强',
      image: img.encodeJpg(enhanced),
      duration: stopwatch.elapsedMilliseconds,
      info: '增强笔画与背景的视觉反差',
    ));
    
    // 5. 自适应二值化
    final binary = _adaptiveThreshold(enhanced, blockSize: 15, c: 10);
    stages.add(ProcessingStage(
      name: '二值化',
      image: img.encodePng(binary),
      duration: stopwatch.elapsedMilliseconds,
      info: '提取手写骨架，转换为纯黑白像素',
    ));
    
    // 6. 降噪（形态学开运算）
    final denoised = _morphologicalOpen(binary, kernelSize: 2);
    stages.add(ProcessingStage(
      name: '降噪',
      image: img.encodePng(denoised),
      duration: stopwatch.elapsedMilliseconds,
      info: '消除离散噪点，平滑笔画边缘',
    ));
    
    stopwatch.stop();
    
    return ImageProcessResult(
      originalImage: imageBytes,
      processedImage: img.encodePng(denoised),
      binaryImage: denoised,
      stages: stages,
      totalDuration: stopwatch.elapsedMilliseconds,
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
  
  /// 形态学开运算（腐蚀后膨胀）
  /// 
  /// 用于去除小噪点
  img.Image _morphologicalOpen(img.Image src, {int kernelSize = 2}) {
    // 先腐蚀
    final eroded = _erode(src, kernelSize);
    // 再膨胀
    final dilated = _dilate(eroded, kernelSize);
    return dilated;
  }
  
  /// 腐蚀操作
  img.Image _erode(img.Image src, int kernelSize) {
    final result = img.Image(width: src.width, height: src.height);
    final half = kernelSize ~/ 2;
    
    // 初始化为白色
    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        result.setPixel(x, y, img.ColorRgb8(255, 255, 255));
      }
    }
    
    for (int y = half; y < src.height - half; y++) {
      for (int x = half; x < src.width - half; x++) {
        bool allBlack = true;
        
        // 检查邻域是否全为黑色
        outer:
        for (int dy = -half; dy <= half; dy++) {
          for (int dx = -half; dx <= half; dx++) {
            final pixel = src.getPixel(x + dx, y + dy);
            if (pixel.r > 128) {
              allBlack = false;
              break outer;
            }
          }
        }
        
        if (allBlack) {
          result.setPixel(x, y, img.ColorRgb8(0, 0, 0));
        }
      }
    }
    
    return result;
  }
  
  /// 膨胀操作
  img.Image _dilate(img.Image src, int kernelSize) {
    final result = img.Image(width: src.width, height: src.height);
    final half = kernelSize ~/ 2;
    
    // 初始化为白色
    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        result.setPixel(x, y, img.ColorRgb8(255, 255, 255));
      }
    }
    
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final pixel = src.getPixel(x, y);
        
        // 如果当前像素是黑色，则扩展到邻域
        if (pixel.r < 128) {
          for (int dy = -half; dy <= half; dy++) {
            for (int dx = -half; dx <= half; dx++) {
              final nx = x + dx;
              final ny = y + dy;
              if (nx >= 0 && nx < result.width && 
                  ny >= 0 && ny < result.height) {
                result.setPixel(nx, ny, img.ColorRgb8(0, 0, 0));
              }
            }
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
  
  ImageProcessResult({
    required this.originalImage,
    required this.processedImage,
    required this.binaryImage,
    required this.stages,
    required this.totalDuration,
  });
}