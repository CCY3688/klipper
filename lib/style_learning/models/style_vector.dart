import 'dart:convert';
import 'dart:typed_data';

/// 风格向量
/// 
/// 包含用户书写风格的所有统计特征
class StyleVector {
  /// 全局特征
  final GlobalStyleFeatures global;

  /// 笔画类型特定特征
  final Map<String, StrokeTypeFeatures> strokeTypes;

  /// 创建时间
  final DateTime createdAt;

  /// 样本数量
  final int sampleCount;

  /// 版本号
  final int version;

  StyleVector({
    required this.global,
    required this.strokeTypes,
    required this.createdAt,
    required this.sampleCount,
    this.version = 1,
  });

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'createdAt': createdAt.toIso8601String(),
      'sampleCount': sampleCount,
      'global': global.toJson(),
      'strokeTypes': strokeTypes.map((k, v) => MapEntry(k, v.toJson())),
    };
  }

  /// 从 JSON 创建
  factory StyleVector.fromJson(Map<String, dynamic> json) {
    return StyleVector(
      version: json['version'] as int? ?? 1,
      createdAt: DateTime.parse(json['createdAt'] as String),
      sampleCount: json['sampleCount'] as int,
      global: GlobalStyleFeatures.fromJson(json['global'] as Map<String, dynamic>),
      strokeTypes: (json['strokeTypes'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, StrokeTypeFeatures.fromJson(v as Map<String, dynamic>)),
      ),
    );
  }

  /// 序列化为字节
  Uint8List toBytes() {
    final jsonStr = jsonEncode(toJson());
    return Uint8List.fromList(utf8.encode(jsonStr));
  }

  /// 从字节反序列化
  factory StyleVector.fromBytes(Uint8List bytes) {
    final jsonStr = utf8.decode(bytes);
    return StyleVector.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  /// 获取风格向量的数值表示（用于机器学习）
  List<double> toNumericVector() {
    final vector = <double>[];

    // 全局特征
    vector.addAll([
      global.avgSlantAngle,
      global.slantAngleStd,
      global.avgAspectRatio,
      global.aspectRatioStd,
      global.avgStrokeDensity,
      global.centerOfGravityX,
      global.centerOfGravityY,
    ]);

    // 笔画类型特征（按固定顺序）
    for (final type in ['横', '竖', '撇', '捺', '点', '折', '钩', '提']) {
      final features = strokeTypes[type];
      if (features != null) {
        vector.addAll([
          features.avgLength,
          features.avgCurvature,
          features.avgStartAngle,
          features.avgEndAngle,
          features.lengthStd,
          features.curvatureStd,
        ]);
      } else {
        vector.addAll([0, 0, 0, 0, 0, 0]); // 填充默认值
      }
    }

    return vector;
  }

  @override
  String toString() {
    return 'StyleVector(samples: $sampleCount, slant: ${(global.avgSlantAngle * 180 / 3.14159).toStringAsFixed(1)}°)';
  }
}

/// 全局风格特征
class GlobalStyleFeatures {
  /// 平均倾斜角度
  final double avgSlantAngle;

  /// 倾斜角度标准差
  final double slantAngleStd;

  /// 平均高宽比
  final double avgAspectRatio;

  /// 高宽比标准差
  final double aspectRatioStd;

  /// 平均笔画密度
  final double avgStrokeDensity;

  /// 平均重心X（0-1）
  final double centerOfGravityX;

  /// 平均重心Y（0-1）
  final double centerOfGravityY;

  /// 平均笔画间距
  final double avgStrokeSpacing;

  /// 笔画间距标准差
  final double strokeSpacingStd;

  GlobalStyleFeatures({
    required this.avgSlantAngle,
    required this.slantAngleStd,
    required this.avgAspectRatio,
    required this.aspectRatioStd,
    required this.avgStrokeDensity,
    required this.centerOfGravityX,
    required this.centerOfGravityY,
    required this.avgStrokeSpacing,
    required this.strokeSpacingStd,
  });

  Map<String, dynamic> toJson() {
    return {
      'avgSlantAngle': avgSlantAngle,
      'slantAngleStd': slantAngleStd,
      'avgAspectRatio': avgAspectRatio,
      'aspectRatioStd': aspectRatioStd,
      'avgStrokeDensity': avgStrokeDensity,
      'centerOfGravityX': centerOfGravityX,
      'centerOfGravityY': centerOfGravityY,
      'avgStrokeSpacing': avgStrokeSpacing,
      'strokeSpacingStd': strokeSpacingStd,
    };
  }

  factory GlobalStyleFeatures.fromJson(Map<String, dynamic> json) {
    return GlobalStyleFeatures(
      avgSlantAngle: (json['avgSlantAngle'] as num).toDouble(),
      slantAngleStd: (json['slantAngleStd'] as num).toDouble(),
      avgAspectRatio: (json['avgAspectRatio'] as num).toDouble(),
      aspectRatioStd: (json['aspectRatioStd'] as num).toDouble(),
      avgStrokeDensity: (json['avgStrokeDensity'] as num).toDouble(),
      centerOfGravityX: (json['centerOfGravityX'] as num).toDouble(),
      centerOfGravityY: (json['centerOfGravityY'] as num).toDouble(),
      avgStrokeSpacing: (json['avgStrokeSpacing'] as num).toDouble(),
      strokeSpacingStd: (json['strokeSpacingStd'] as num).toDouble(),
    );
  }
}

/// 笔画类型特定特征
class StrokeTypeFeatures {
  /// 笔画类型名称
  final String typeName;

  /// 样本数量
  final int sampleCount;

  /// 平均长度
  final double avgLength;

  /// 长度标准差
  final double lengthStd;

  /// 平均曲率
  final double avgCurvature;

  /// 曲率标准差
  final double curvatureStd;

  /// 平均起笔角度
  final double avgStartAngle;

  /// 起笔角度标准差
  final double startAngleStd;

  /// 平均收笔角度
  final double avgEndAngle;

  /// 收笔角度标准差
  final double endAngleStd;

  /// 平均方向
  final double avgDirection;

  /// 方向标准差
  final double directionStd;

  StrokeTypeFeatures({
    required this.typeName,
    required this.sampleCount,
    required this.avgLength,
    required this.lengthStd,
    required this.avgCurvature,
    required this.curvatureStd,
    required this.avgStartAngle,
    required this.startAngleStd,
    required this.avgEndAngle,
    required this.endAngleStd,
    required this.avgDirection,
    required this.directionStd,
  });

  Map<String, dynamic> toJson() {
    return {
      'typeName': typeName,
      'sampleCount': sampleCount,
      'avgLength': avgLength,
      'lengthStd': lengthStd,
      'avgCurvature': avgCurvature,
      'curvatureStd': curvatureStd,
      'avgStartAngle': avgStartAngle,
      'startAngleStd': startAngleStd,
      'avgEndAngle': avgEndAngle,
      'endAngleStd': endAngleStd,
      'avgDirection': avgDirection,
      'directionStd': directionStd,
    };
  }

  factory StrokeTypeFeatures.fromJson(Map<String, dynamic> json) {
    return StrokeTypeFeatures(
      typeName: json['typeName'] as String,
      sampleCount: json['sampleCount'] as int,
      avgLength: (json['avgLength'] as num).toDouble(),
      lengthStd: (json['lengthStd'] as num).toDouble(),
      avgCurvature: (json['avgCurvature'] as num).toDouble(),
      curvatureStd: (json['curvatureStd'] as num).toDouble(),
      avgStartAngle: (json['avgStartAngle'] as num).toDouble(),
      startAngleStd: (json['startAngleStd'] as num).toDouble(),
      avgEndAngle: (json['avgEndAngle'] as num).toDouble(),
      endAngleStd: (json['endAngleStd'] as num).toDouble(),
      avgDirection: (json['avgDirection'] as num).toDouble(),
      directionStd: (json['directionStd'] as num).toDouble(),
    );
  }
}