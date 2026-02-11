/// 风格学习模块
/// 
/// 使用方法:
/// ```dart
/// import 'package:your_app/style_learning/style_learning.dart';
/// ```

library;

// 数据模型
export 'models/stroke_trajectory.dart';
export 'models/character_data.dart';
export 'models/handwriting_sample.dart';

// 服务
export 'services/image_capture_service.dart';
export 'services/image_processor.dart';

// UI 页面
export 'ui/style_learning_test_page.dart';
export 'ui/image_capture_page.dart';

// TODO: 后续会添加更多导出
// export 'services/image_processor.dart';
// export 'services/skeleton_extractor.dart';
// export 'services/style_analyzer.dart';
// export 'services/style_transfer.dart';