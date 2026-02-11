import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// 图像编辑服务
/// 
/// 提供裁剪、旋转、调节等功能
class ImageEditorService {
  
  /// 裁剪图像
  /// 
  /// [imageBytes] 原始图像
  /// [rect] 裁剪区域 (相对坐标 0-1)
  Future<Uint8List> crop(
    Uint8List imageBytes, 
    CropRect rect,
  ) async {
    final image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('无法解码图像');
    
    final x = (rect.left * image.width).round();
    final y = (rect.top * image.height).round();
    final w = (rect.width * image.width).round();
    final h = (rect.height * image.height).round();
    
    final cropped = img.copyCrop(image, x: x, y: y, width: w, height: h);
    return img.encodeJpg(cropped, quality: 95);
  }
  
  /// 旋转图像
  /// 
  /// [angle] 旋转角度（度）
  Future<Uint8List> rotate(Uint8List imageBytes, double angle) async {
    final image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('无法解码图像');
    
    final rotated = img.copyRotate(image, angle: angle);
    return img.encodeJpg(rotated, quality: 95);
  }
  
  /// 顺时针旋转90度
  Future<Uint8List> rotate90CW(Uint8List imageBytes) async {
    return rotate(imageBytes, 90);
  }
  
  /// 逆时针旋转90度
  Future<Uint8List> rotate90CCW(Uint8List imageBytes) async {
    return rotate(imageBytes, -90);
  }
  
  /// 调整亮度和对比度
  /// 
  /// [brightness] 亮度调整 (-100 到 100)
  /// [contrast] 对比度调整 (0.5 到 2.0)
  Future<Uint8List> adjustBrightnessContrast(
    Uint8List imageBytes, {
    int brightness = 0,
    double contrast = 1.0,
  }) async {
    final image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('无法解码图像');
    
    var adjusted = image;
    
    // 调整亮度
    if (brightness != 0) {
      adjusted = img.adjustColor(adjusted, brightness: brightness);
    }
    
    // 调整对比度
    if (contrast != 1.0) {
      adjusted = img.adjustColor(adjusted, contrast: contrast);
    }
    
    return img.encodeJpg(adjusted, quality: 95);
  }
  
  /// 自动增强（简单的自动调整）
  Future<Uint8List> autoEnhance(Uint8List imageBytes) async {
    final image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('无法解码图像');
    
    // 自动对比度拉伸
    final enhanced = img.normalize(image, min: 0, max: 255);
    
    return img.encodeJpg(enhanced, quality: 95);
  }
  
  /// 获取图像信息
  ImageInfo getImageInfo(Uint8List imageBytes) {
    final image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('无法解码图像');
    
    return ImageInfo(
      width: image.width,
      height: image.height,
      sizeBytes: imageBytes.length,
    );
  }
}

/// 裁剪区域
class CropRect {
  final double left;
  final double top;
  final double width;
  final double height;
  
  const CropRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
  
  double get right => left + width;
  double get bottom => top + height;
  
  /// 全图
  static const CropRect full = CropRect(left: 0, top: 0, width: 1, height: 1);
}

/// 图像信息
class ImageInfo {
  final int width;
  final int height;
  final int sizeBytes;
  
  ImageInfo({
    required this.width,
    required this.height,
    required this.sizeBytes,
  });
  
  String get sizeDisplay {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  
  String get dimensionDisplay => '${width}x$height';
}