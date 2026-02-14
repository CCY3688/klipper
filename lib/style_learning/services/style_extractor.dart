import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

import '../../writing/font/stroke_font.dart';
import '../../writing/model/glyph.dart';
import '../../writing/model/stroke.dart';
import '../models/sample_template.dart';
import '../models/style_params.dart';

/// 风格提取器（重构版）
///
/// 核心改进：
///   1. 重心偏移改为**相对参考字形重心**的差值，避免非对称字符的系统误差
///   2. 尺寸比例放宽范围，允许更明显的大小差异
///   3. 按笔画类型的角度偏移和长度缩放实际参与渲染
///   4. 新增跨字符统计量 → positionJitter / pointNoise / sizeVariation
///      用于模拟自然手写的不规则性
class StyleExtractor {
  final StrokeFont font;

  StyleExtractor(this.font);

  /// 从模板照片中提取风格参数
  Future<StyleExtractionResult> extract({
    required List<Uint8List> cellImages,
    required SampleTemplate template,
  }) async {
    final perCharParams = <CharacterStyleResult>[];

    for (int i = 0; i < cellImages.length && i < template.characters.length; i++) {
      final ch = template.characters[i];
      final glyph = font.richGlyphOf(ch);
      if (glyph == null) continue;

      try {
        final params = _analyzeCharacter(cellImages[i], glyph);
        perCharParams.add(CharacterStyleResult(
          character: ch,
          params: params,
          success: true,
        ));
      } catch (e) {
        perCharParams.add(CharacterStyleResult(
          character: ch,
          params: StyleParams.identity,
          success: false,
          error: e.toString(),
        ));
      }
    }

    // 汇总：取所有成功分析的字符参数的平均值
    final successParams = perCharParams
        .where((r) => r.success)
        .map((r) => r.params)
        .toList();

    if (successParams.isEmpty) {
      return StyleExtractionResult(
        globalParams: StyleParams.identity,
        perCharacter: perCharParams,
        successCount: 0,
        totalCount: cellImages.length,
      );
    }

    // 1. 先对全局仿射参数取平均
    final averaged = StyleParams.average(successParams);

    // 2. 从跨字符变异中计算自然手写模拟参数
    final variation = StyleParams.characterVariation(successParams);

    // 3. 合成最终参数
    final globalParams = StyleParams(
      sizeRatio: averaged.sizeRatio,
      xOffsetRatio: averaged.xOffsetRatio,
      yOffsetRatio: averaged.yOffsetRatio,
      xStretch: averaged.xStretch,
      yStretch: averaged.yStretch,
      slantAngle: averaged.slantAngle,
      strokeWeight: averaged.strokeWeight,
      strokeAngleOffsets: averaged.strokeAngleOffsets,
      strokeLengthScales: averaged.strokeLengthScales,
      positionJitter: variation.posJitter,
      pointNoise: variation.ptNoise,
      sizeVariation: variation.sizeVar,
    );

    return StyleExtractionResult(
      globalParams: globalParams,
      perCharacter: perCharParams,
      successCount: successParams.length,
      totalCount: cellImages.length,
    );
  }

  /// 分析单个字符的风格参数
  StyleParams _analyzeCharacter(Uint8List imageBytes, Glyph refGlyph) {
    final image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('无法解码单元格图像');

    final w = image.width;
    final h = image.height;

    // 构建二值矩阵：true = 墨迹
    final ink = List.generate(h, (y) {
      return List.generate(w, (x) {
        final p = image.getPixel(x, y);
        final gray = (p.r.toInt() + p.g.toInt() + p.b.toInt()) ~/ 3;
        return gray < 128;
      });
    });

    // ---------- 1. 整体包围盒 & 重心 ----------
    int minX = w, maxX = 0, minY = h, maxY = 0;
    int inkCount = 0;
    double sumX = 0, sumY = 0;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (ink[y][x]) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
          sumX += x;
          sumY += y;
          inkCount++;
        }
      }
    }

    if (inkCount < 10) {
      return StyleParams.identity;
    }

    // ---------- 2. 尺寸比例 ----------
    final bboxW = (maxX - minX + 1).toDouble();
    final bboxH = (maxY - minY + 1).toDouble();
    // 用户字符占格比
    final userFillW = bboxW / w;
    final userFillH = bboxH / h;

    final refBox = refGlyph.boundingBox;
    final refW = refBox.maxX - refBox.minX;
    final refH = refBox.maxY - refBox.minY;

    // 分别比较宽、高方向的占格比，取平均
    final scaleW = refW > 0.05 ? userFillW / refW : 1.0;
    final scaleH = refH > 0.05 ? userFillH / refH : 1.0;
    final sizeRatio = ((scaleW + scaleH) / 2).clamp(0.5, 1.6);

    // ---------- 3. 重心偏移（相对于参考字形重心） ----------
    final userCentroidX = sumX / inkCount / w; // 0..1
    final userCentroidY = sumY / inkCount / h; // 0..1

    // 参考字形重心（从笔画点计算，归一化 0..1）
    final refCentroid = _computeGlyphCentroid(refGlyph);

    // 偏移 = 用户重心 - 参考重心（直接在归一化空间中）
    final xOffset = userCentroidX - refCentroid.$1;
    final yOffset = userCentroidY - refCentroid.$2;

    // ---------- 4. 拉伸比 ----------
    final refAspect = refW > 0.05 && refH > 0.05 ? refW / refH : 1.0;
    final userAspect = bboxH > 0 ? bboxW / bboxH : 1.0;
    final aspectRatio = refAspect > 0 ? userAspect / refAspect : 1.0;

    final xStretch = math.sqrt(aspectRatio).clamp(0.7, 1.5);
    final yStretch = (1.0 / math.sqrt(aspectRatio)).clamp(0.7, 1.5);

    // ---------- 5. 倾斜角度 ----------
    final centroidX = sumX / inkCount;
    final centroidY = sumY / inkCount;
    final slant = _estimateSlant(ink, w, h, centroidX, centroidY);

    // ---------- 6. 笔画粗细 ----------
    // 使用墨迹面积/(字符面积 × 参考路径长度) 来估算相对笔画粗细
    final charArea = bboxW * bboxH;
    final refTotalLength = _referencePathLength(refGlyph);
    double strokeWeight = 1.0;
    if (refTotalLength > 0.01 && charArea > 0) {
      // 标准墨迹面积 ≈ refTotalLength * w * 0.03 * w (粗细 × 长度 × 像素)
      final expectedInk = refTotalLength * w * 0.03 * w;
      strokeWeight = expectedInk > 0 ? (inkCount / expectedInk).clamp(0.4, 2.5) : 1.0;
    }

    // ---------- 7. 按笔画类型统计 ----------
    final (angleOffsets, lengthScales) =
        _analyzePerStrokeType(ink, w, h, refGlyph);

    return StyleParams(
      sizeRatio: sizeRatio,
      xOffsetRatio: xOffset.clamp(-0.15, 0.15),
      yOffsetRatio: yOffset.clamp(-0.15, 0.15),
      xStretch: xStretch,
      yStretch: yStretch,
      slantAngle: slant.clamp(-0.25, 0.25), // ±14°
      strokeWeight: strokeWeight,
      strokeAngleOffsets: angleOffsets,
      strokeLengthScales: lengthScales,
    );
  }

  /// 计算参考字形的加权重心（归一化 0..1）
  (double, double) _computeGlyphCentroid(Glyph glyph) {
    double sumX = 0, sumY = 0;
    int count = 0;
    for (final stroke in glyph.strokes) {
      for (final p in stroke.points) {
        sumX += p.x;
        sumY += p.y;
        count++;
      }
    }
    if (count == 0) return (0.5, 0.5);
    return (sumX / count, sumY / count);
  }

  /// 通过图像二阶矩估计整体倾斜角度
  double _estimateSlant(
      List<List<bool>> ink, int w, int h, double cx, double cy) {
    double myy = 0, mxy = 0;
    int count = 0;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (ink[y][x]) {
          final dx = x - cx;
          final dy = y - cy;
          myy += dy * dy;
          mxy += dx * dy;
          count++;
        }
      }
    }

    if (count < 20) return 0;

    // 提取倾斜分量：只取 mxy 对应的剪切角
    // 完整的主轴方向 atan2(2*mxy, mxx-myy)/2 对扁平或高瘦字符会产生
    // 与"倾斜"无关的大角度。改用纯剪切估计更符合书写倾斜直觉。
    if (myy < 1) return 0;
    final shear = mxy / myy;
    return math.atan(shear);
  }

  /// 计算参考字形的总路径长度（归一化单位）
  double _referencePathLength(Glyph glyph) {
    double total = 0;
    for (final stroke in glyph.strokes) {
      total += stroke.pathLength;
    }
    return total;
  }

  /// 按笔画类型分析角度偏移和长度缩放
  (Map<String, double>, Map<String, double>) _analyzePerStrokeType(
      List<List<bool>> ink, int w, int h, Glyph refGlyph) {
    final angleOffsets = <String, List<double>>{};
    final lengthScales = <String, List<double>>{};

    for (final stroke in refGlyph.strokes) {
      final type = stroke.type ?? StrokeType.other;
      final typeName = type.name;
      final refAngle = stroke.directionAngle;

      // 获取笔画经过区域（稍微扩大边界以容纳手写偏差）
      final box = stroke.boundingBox;
      final margin = 0.05; // 5% 的额外边距
      final startX = ((box.minX - margin) * w).round().clamp(0, w - 1);
      final endX = ((box.maxX + margin) * w).round().clamp(0, w - 1);
      final startY = ((box.minY - margin) * h).round().clamp(0, h - 1);
      final endY = ((box.maxY + margin) * h).round().clamp(0, h - 1);

      if (endX <= startX + 2 || endY <= startY + 2) continue;

      // 在此区域统计墨迹重心
      double rSumX = 0, rSumY = 0;
      int regionInk = 0;

      for (int y = startY; y <= endY; y++) {
        for (int x = startX; x <= endX; x++) {
          if (ink[y][x]) {
            rSumX += x;
            rSumY += y;
            regionInk++;
          }
        }
      }

      if (regionInk < 5) continue;

      final regionCX = rSumX / regionInk;
      final regionCY = rSumY / regionInk;

      // 二阶矩主方向
      double mxx = 0, myy = 0, mxy = 0;
      for (int y = startY; y <= endY; y++) {
        for (int x = startX; x <= endX; x++) {
          if (ink[y][x]) {
            final dx = x - regionCX;
            final dy = y - regionCY;
            mxx += dx * dx;
            myy += dy * dy;
            mxy += dx * dy;
          }
        }
      }

      final userAngle = 0.5 * math.atan2(2 * mxy, mxx - myy);
      final angleDiff = _normalizeAngle(userAngle - refAngle);

      angleOffsets.putIfAbsent(typeName, () => []).add(angleDiff);

      // 长度缩放
      final refLen = stroke.pathLength;
      if (refLen > 0.01) {
        final userRegionDiag = math.sqrt(
            math.pow(endX - startX, 2) + math.pow(endY - startY, 2));
        final refRegionDiag = math.sqrt(
                math.pow(box.maxX - box.minX, 2) +
                    math.pow(box.maxY - box.minY, 2)) *
            w;
        if (refRegionDiag > 1) {
          lengthScales
              .putIfAbsent(typeName, () => [])
              .add((userRegionDiag / refRegionDiag).clamp(0.6, 1.6));
        }
      }
    }

    // 求中位数（比均值更抗离群值）
    final avgAngles = angleOffsets.map((k, vals) {
      vals.sort();
      return MapEntry(k, vals[vals.length ~/ 2]);
    });
    final avgScales = lengthScales.map((k, vals) {
      vals.sort();
      return MapEntry(k, vals[vals.length ~/ 2]);
    });

    return (avgAngles, avgScales);
  }

  /// 将角度归一化到 [-π, π]
  double _normalizeAngle(double a) {
    while (a > math.pi) { a -= 2 * math.pi; }
    while (a < -math.pi) { a += 2 * math.pi; }
    return a;
  }
}

/// 单字符风格分析结果
class CharacterStyleResult {
  final String character;
  final StyleParams params;
  final bool success;
  final String? error;

  const CharacterStyleResult({
    required this.character,
    required this.params,
    required this.success,
    this.error,
  });
}

/// 完整风格提取结果
class StyleExtractionResult {
  /// 全局平均风格参数
  final StyleParams globalParams;

  /// 每个字符的风格结果
  final List<CharacterStyleResult> perCharacter;

  /// 成功分析的字符数
  final int successCount;

  /// 总字符数
  final int totalCount;

  const StyleExtractionResult({
    required this.globalParams,
    required this.perCharacter,
    required this.successCount,
    required this.totalCount,
  });

  /// 成功率
  double get successRate => totalCount > 0 ? successCount / totalCount : 0;
}
