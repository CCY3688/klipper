import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' as picker;
import 'package:permission_handler/permission_handler.dart';
import '../models/handwriting_sample.dart';

/// 图像采集服务
/// 
/// 提供跨平台的图像获取功能
class ImageCaptureService {
  final picker.ImagePicker _picker = picker.ImagePicker();
  
  /// 从相机拍照
  Future<HandwritingSample?> captureFromCamera() async {
    // Windows 平台兼容性处理：image_picker 在 Windows 上不支持 ImageSource.camera
    if (!kIsWeb && Platform.isWindows) {
      throw UnsupportedError('Windows 平台暂不支持直接通过摄像头拍摄。请使用“相册选择”功能来导入手写样本文件。');
    }

    // 检查相机权限
    if (!kIsWeb && Platform.isAndroid) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        throw PermissionException('需要相机权限才能拍照');
      }
    }
    
    final image = await _picker.pickImage(
      source: picker.ImageSource.camera,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
    
    if (image == null) return null;
    
    final bytes = await image.readAsBytes();
    
    return HandwritingSample(
      id: HandwritingSample.generateId(),
      originalImage: bytes,
      capturedAt: DateTime.now(),
      source: ImageSource.camera,
    );
  }
  
  /// 从相册选择
  Future<HandwritingSample?> pickFromGallery() async {
    // 检查存储权限（Android 13以下需要）
    if (!kIsWeb && Platform.isAndroid) {
      final status = await Permission.photos.request();
      // 即使权限被拒绝，有些设备也可能允许选择
    }
    
    final image = await _picker.pickImage(
      source: picker.ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
    
    if (image == null) return null;
    
    final bytes = await image.readAsBytes();
    
    return HandwritingSample(
      id: HandwritingSample.generateId(),
      originalImage: bytes,
      capturedAt: DateTime.now(),
      source: ImageSource.gallery,
    );
  }
  
  /// 选择多张图片
  Future<List<HandwritingSample>> pickMultipleFromGallery({int limit = 10}) async {
    final images = await _picker.pickMultiImage(
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
      limit: limit,
    );
    
    final samples = <HandwritingSample>[];
    
    for (final image in images) {
      final bytes = await image.readAsBytes();
      samples.add(HandwritingSample(
        id: HandwritingSample.generateId(),
        originalImage: bytes,
        capturedAt: DateTime.now(),
        source: ImageSource.gallery,
      ));
    }
    
    return samples;
  }
  
  /// 从文件路径加载
  Future<HandwritingSample?> loadFromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileNotFoundException('文件不存在: $path');
    }
    
    final bytes = await file.readAsBytes();
    
    return HandwritingSample(
      id: HandwritingSample.generateId(),
      originalImage: bytes,
      capturedAt: DateTime.now(),
      source: ImageSource.file,
    );
  }
  
  /// 从字节数据创建
  HandwritingSample createFromBytes(Uint8List bytes, {ImageSource source = ImageSource.file}) {
    return HandwritingSample(
      id: HandwritingSample.generateId(),
      originalImage: bytes,
      capturedAt: DateTime.now(),
      source: source,
    );
  }
}

/// 权限异常
class PermissionException implements Exception {
  final String message;
  PermissionException(this.message);
  
  @override
  String toString() => message;
}

/// 文件不存在异常
class FileNotFoundException implements Exception {
  final String message;
  FileNotFoundException(this.message);
  
  @override
  String toString() => message;
}