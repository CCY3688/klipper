import 'dart:typed_data';

/// 手写样本
/// 
/// 存储用户上传的单个手写字符样本
class HandwritingSample {
  /// 唯一标识
  final String id;
  
  /// 字符内容（如果已识别）
  final String? character;
  
  /// 原始图像数据
  final Uint8List originalImage;
  
  /// 处理后的图像数据
  final Uint8List? processedImage;
  
  /// 采集时间
  final DateTime capturedAt;
  
  /// 图像来源
  final ImageSource source;
  
  /// 是否已处理
  bool get isProcessed => processedImage != null;
  
  HandwritingSample({
    required this.id,
    this.character,
    required this.originalImage,
    this.processedImage,
    required this.capturedAt,
    required this.source,
  });
  
  /// 创建一个带处理结果的副本
  HandwritingSample copyWithProcessed(Uint8List processed, {String? character}) {
    return HandwritingSample(
      id: id,
      character: character ?? this.character,
      originalImage: originalImage,
      processedImage: processed,
      capturedAt: capturedAt,
      source: source,
    );
  }
  
  /// 生成唯一ID
  static String generateId() {
    return 'sample_${DateTime.now().millisecondsSinceEpoch}';
  }
}

/// 图像来源
enum ImageSource {
  camera,   // 相机拍摄
  gallery,  // 相册选择
  file,     // 文件导入
}

extension ImageSourceExtension on ImageSource {
  String get displayName {
    switch (this) {
      case ImageSource.camera:
        return '相机拍摄';
      case ImageSource.gallery:
        return '相册选择';
      case ImageSource.file:
        return '文件导入';
    }
  }
  
  String get icon {
    switch (this) {
      case ImageSource.camera:
        return '📷';
      case ImageSource.gallery:
        return '🖼️';
      case ImageSource.file:
        return '📁';
    }
  }
}