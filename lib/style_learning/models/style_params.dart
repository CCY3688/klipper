import 'dart:math' as math;

/// 风格参数
///
/// 从用户手写样本中提取的风格特征，可用于将标准字库字形
/// 变换为接近用户手写风格的形态。
///
/// 包含三层变换：
///   1. 全局仿射变换：缩放、偏移、拉伸、倾斜
///   2. 按笔画类型变换：角度偏移、长度缩放
///   3. 自然手写模拟：位置抖动、笔画噪声、大小变化
class StyleParams {
  // ==================== 全局变换参数 ====================

  /// 整体缩放比（相对于参考字形，1.0 = 与参考同大小）
  final double sizeRatio;

  /// 水平偏移（归一化，相对于参考字形重心的偏差）
  final double xOffsetRatio;

  /// 垂直偏移（归一化，相对于参考字形重心的偏差）
  final double yOffsetRatio;

  /// 水平拉伸系数（1.0 = 无拉伸）
  final double xStretch;

  /// 垂直拉伸系数（1.0 = 无拉伸）
  final double yStretch;

  /// 整体倾斜角度（弧度，正值 = 右倾）
  final double slantAngle;

  /// 笔画相对粗细（1.0 = 标准粗细）
  final double strokeWeight;

  // ==================== 按笔画类型的变换参数 ====================

  /// 每种笔画类型的角度偏移（弧度）
  /// key = StrokeType name, value = angle offset
  final Map<String, double> strokeAngleOffsets;

  /// 每种笔画类型的长度缩放
  final Map<String, double> strokeLengthScales;

  // ==================== 自然手写模拟参数 ====================

  /// 字符位置抖动量（归一化格内坐标，0=无抖动，0.03=典型手写）
  /// 每个字符会有一个确定性的随机偏移，模拟手写时位置不完全一致
  final double positionJitter;

  /// 笔画点噪声振幅（归一化，0=无噪声，0.008=典型手写）
  /// 给笔画路径点添加平滑的正弦波动，模拟手抖
  final double pointNoise;

  /// 字符大小随机变化量（0=统一大小，0.05=典型手写）
  /// 每个字会在 sizeRatio 基础上随机浮动 ±sizeVariation
  final double sizeVariation;

  const StyleParams({
    this.sizeRatio = 1.0,
    this.xOffsetRatio = 0.0,
    this.yOffsetRatio = 0.0,
    this.xStretch = 1.0,
    this.yStretch = 1.0,
    this.slantAngle = 0.0,
    this.strokeWeight = 1.0,
    this.strokeAngleOffsets = const {},
    this.strokeLengthScales = const {},
    this.positionJitter = 0.0,
    this.pointNoise = 0.0,
    this.sizeVariation = 0.0,
  });

  /// 默认参数（无变换）
  static const StyleParams identity = StyleParams();

  /// 合并多个样本的风格参数（取平均值）
  static StyleParams average(List<StyleParams> samples) {
    if (samples.isEmpty) return identity;
    if (samples.length == 1) return samples.first;

    final n = samples.length;

    double sumSize = 0, sumXOff = 0, sumYOff = 0;
    double sumXStr = 0, sumYStr = 0;
    double sumSlant = 0, sumWeight = 0;

    final angleOffsetSums = <String, double>{};
    final angleOffsetCounts = <String, int>{};
    final lengthScaleSums = <String, double>{};
    final lengthScaleCounts = <String, int>{};

    for (final s in samples) {
      sumSize += s.sizeRatio;
      sumXOff += s.xOffsetRatio;
      sumYOff += s.yOffsetRatio;
      sumXStr += s.xStretch;
      sumYStr += s.yStretch;
      sumSlant += s.slantAngle;
      sumWeight += s.strokeWeight;

      for (final entry in s.strokeAngleOffsets.entries) {
        angleOffsetSums[entry.key] =
            (angleOffsetSums[entry.key] ?? 0) + entry.value;
        angleOffsetCounts[entry.key] =
            (angleOffsetCounts[entry.key] ?? 0) + 1;
      }
      for (final entry in s.strokeLengthScales.entries) {
        lengthScaleSums[entry.key] =
            (lengthScaleSums[entry.key] ?? 0) + entry.value;
        lengthScaleCounts[entry.key] =
            (lengthScaleCounts[entry.key] ?? 0) + 1;
      }
    }

    return StyleParams(
      sizeRatio: sumSize / n,
      xOffsetRatio: sumXOff / n,
      yOffsetRatio: sumYOff / n,
      xStretch: sumXStr / n,
      yStretch: sumYStr / n,
      slantAngle: sumSlant / n,
      strokeWeight: sumWeight / n,
      strokeAngleOffsets: angleOffsetSums.map(
        (k, v) => MapEntry(k, v / angleOffsetCounts[k]!),
      ),
      strokeLengthScales: lengthScaleSums.map(
        (k, v) => MapEntry(k, v / lengthScaleCounts[k]!),
      ),
      // 自然手写参数不做平均——由 extract() 从跨字符统计量计算
    );
  }

  /// 从多个样本的参数中计算跨字符统计量（标准差），
  /// 用于推断 positionJitter / sizeVariation / pointNoise
  static ({double posJitter, double sizeVar, double ptNoise})
      characterVariation(List<StyleParams> samples) {
    if (samples.length < 3) {
      return (posJitter: 0.015, sizeVar: 0.03, ptNoise: 0.005);
    }

    final xOffs = samples.map((s) => s.xOffsetRatio).toList();
    final yOffs = samples.map((s) => s.yOffsetRatio).toList();
    final sizes = samples.map((s) => s.sizeRatio).toList();
    final weights = samples.map((s) => s.strokeWeight).toList();

    final posJitter = ((_stddev(xOffs) + _stddev(yOffs)) / 2)
        .clamp(0.005, 0.06);
    final sizeVar = _stddev(sizes).clamp(0.01, 0.12);
    // 从笔画粗细变异推断点噪声
    final ptNoise = (_stddev(weights) * 0.015).clamp(0.003, 0.02);

    return (posJitter: posJitter, sizeVar: sizeVar, ptNoise: ptNoise);
  }

  /// 转 JSON
  Map<String, dynamic> toJson() => {
        'sizeRatio': sizeRatio,
        'xOffsetRatio': xOffsetRatio,
        'yOffsetRatio': yOffsetRatio,
        'xStretch': xStretch,
        'yStretch': yStretch,
        'slantAngle': slantAngle,
        'strokeWeight': strokeWeight,
        'strokeAngleOffsets': strokeAngleOffsets,
        'strokeLengthScales': strokeLengthScales,
        'positionJitter': positionJitter,
        'pointNoise': pointNoise,
        'sizeVariation': sizeVariation,
      };

  /// 从 JSON 恢复
  factory StyleParams.fromJson(Map<String, dynamic> json) {
    return StyleParams(
      sizeRatio: (json['sizeRatio'] as num?)?.toDouble() ?? 1.0,
      xOffsetRatio: (json['xOffsetRatio'] as num?)?.toDouble() ?? 0.0,
      yOffsetRatio: (json['yOffsetRatio'] as num?)?.toDouble() ?? 0.0,
      xStretch: (json['xStretch'] as num?)?.toDouble() ?? 1.0,
      yStretch: (json['yStretch'] as num?)?.toDouble() ?? 1.0,
      slantAngle: (json['slantAngle'] as num?)?.toDouble() ?? 0.0,
      strokeWeight: (json['strokeWeight'] as num?)?.toDouble() ?? 1.0,
      strokeAngleOffsets:
          (json['strokeAngleOffsets'] as Map<String, dynamic>?)
                  ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
              {},
      strokeLengthScales:
          (json['strokeLengthScales'] as Map<String, dynamic>?)
                  ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
              {},
      positionJitter: (json['positionJitter'] as num?)?.toDouble() ?? 0.0,
      pointNoise: (json['pointNoise'] as num?)?.toDouble() ?? 0.0,
      sizeVariation: (json['sizeVariation'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// 全局仿射变换：将归一化坐标点 (x, y ∈ 0..1) 变换为风格化坐标
  ///
  /// 变换顺序：中心化 → 拉伸 → 倾斜 → 缩放 → 偏移
  (double, double) transformPoint(double x, double y) {
    // 1. 中心化
    double cx = x - 0.5;
    double cy = y - 0.5;

    // 2. 拉伸
    cx *= xStretch;
    cy *= yStretch;

    // 3. 倾斜（剪切变换）
    if (slantAngle != 0) {
      final s = math.sin(slantAngle);
      cx += cy * s;
    }

    // 4. 缩放
    cx *= sizeRatio;
    cy *= sizeRatio;

    // 5. 偏移：直接使用提取的偏移值
    //    xOffsetRatio 是用户重心与参考重心的差值，直接反映位置偏好
    cx += xOffsetRatio;
    cy += yOffsetRatio;

    return (cx + 0.5, cy + 0.5);
  }

  /// 辅助：计算标准差
  static double _stddev(List<double> values) {
    if (values.length < 2) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values
            .map((v) => (v - mean) * (v - mean))
            .reduce((a, b) => a + b) /
        values.length;
    return math.sqrt(variance);
  }

  @override
  String toString() => '''StyleParams(
  size=$sizeRatio, offset=($xOffsetRatio, $yOffsetRatio),
  stretch=($xStretch, $yStretch), slant=${(slantAngle * 180 / math.pi).toStringAsFixed(1)}°,
  weight=$strokeWeight, strokeTypes=${strokeAngleOffsets.length},
  jitter=$positionJitter, noise=$pointNoise, sizeVar=$sizeVariation
)''';
}
