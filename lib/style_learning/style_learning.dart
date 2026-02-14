/// 风格学习模块
///
/// 完整的风格学习工作流：
///   1. 图像采集与校准
///   2. 预处理 → 字符分割 → 骨架提取
///   3. 基于骨架的风格分析（提取风格向量）
///   4. 风格迁移与应用
///
/// ```dart
/// import 'package:your_app/style_learning/style_learning.dart';
/// ```

library;

// 数据模型
export 'models/stroke_trajectory.dart';
export 'models/character_data.dart';
export 'models/handwriting_sample.dart';
export 'models/stroke_features.dart';
export 'models/style_vector.dart';

// 工具类
export 'utils/math_utils.dart';

// 服务
export 'services/image_capture_service.dart';
export 'services/image_processor.dart';
export 'services/image_editor_service.dart';
export 'services/character_segmenter.dart';
export 'services/skeleton_extractor.dart' hide Point;
export 'services/style_analyzer.dart';
export 'services/style_transfer.dart';
export 'services/style_model_manager.dart';

// UI 页面
export 'ui/style_learning_test_page.dart';
export 'ui/image_capture_page.dart';
export 'ui/image_edit_page.dart';
export 'ui/sample_collection_page.dart';
export 'ui/style_analysis_page.dart';
export 'ui/style_transfer_page.dart';
export 'ui/style_learning_main_page.dart';
export 'ui/style_learning_workspace_page.dart';