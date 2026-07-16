/// 字形处理流水线调试数据
///
/// 记录 TTF → Glyph 各阶段中间结果，供可视化调试页面使用。
library;

import '../../model/glyph.dart';
import '../skeleton/outline_rasterizer.dart';
import '../skeleton/skeleton_vectorizer.dart';

/// 单个字符的全流水线中间结果
class GlyphDebugData {
  final String character;

  /// 阶段 1: 轮廓采样点（归一化 0~1）
  /// 每条轮廓是一组闭合多边形点序列
  final List<List<({double x, double y})>>? sampledContours;

  /// 阶段 2: 光栅化位图
  final GlyphBitmap? rasterBitmap;

  /// 阶段 3: 骨架位图（Zhang-Suen 细化后）
  final GlyphBitmap? skeletonBitmap;

  /// 阶段 4: 向量化原始笔画段（交叉点分割后）
  final List<SkeletonStroke>? rawVectorStrokes;

  /// 阶段 5: 第一轮接链后的笔画
  final List<SkeletonStroke>? chainedStrokes;

  /// 阶段 6: 笔顺对齐后的笔画
  final List<SkeletonStroke>? alignedStrokes;
  final double? matchScore;

  /// 阶段 7: 第二轮补链后的笔画
  final List<SkeletonStroke>? repairedStrokes;

  /// 阶段 8: 微碎段吸附后的笔画
  final List<SkeletonStroke>? finalizedStrokes;

  /// 阶段 9: 最终 Glyph
  final Glyph? finalGlyph;

  /// 模板笔画（来自 makemeahanzi）
  final List<List<({double x, double y})>>? templateStrokes;

  /// 错误信息
  final String? error;

  const GlyphDebugData({
    required this.character,
    this.sampledContours,
    this.rasterBitmap,
    this.skeletonBitmap,
    this.rawVectorStrokes,
    this.chainedStrokes,
    this.alignedStrokes,
    this.matchScore,
    this.repairedStrokes,
    this.finalizedStrokes,
    this.finalGlyph,
    this.templateStrokes,
    this.error,
  });

  /// 各阶段标签（用于 UI 显示）
  static const stageLabels = [
    '轮廓采样',    // 0
    '光栅化',      // 1
    '骨架化',      // 2
    '向量化(去碎后)', // 3
    '接链',        // 4
    '笔顺对齐',    // 5
    '补链',        // 6
    '碎段吸附',    // 7
    '最终结果',    // 8
  ];
}
