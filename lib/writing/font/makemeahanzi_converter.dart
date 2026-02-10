import 'dart:ui';
import '../model/geometry.dart';
import '../model/stroke.dart';
import '../model/glyph.dart';

/// MakeMeAHanzi 数据转换工具
/// 
/// 负责将 SVG Path 数据解析并转换为我们系统可用的笔画数据
class MakeMeAHanziConverter {
  
  // MakeMeAHanzi 的坐标系通常是 1024x1024
  static const double _sourceScale = 1024.0;
  
  /// 解析 MakeMeAHanzi 的 SVG Path 字符串为点序列
  /// 
  /// 格式示例: "M 323 706 Q 325 699 328 694 ... Z"
  /// 注意：这里我们需要简化处理，将曲线离散化为折线点序列
  static List<Vec2> parseSvgPath(String pathData) {
    // 由于 Dart 标准库没有直接解析 SVG Path 数据的 API
    // 且 flutter_svg 等库主要用于渲染而非提取点
    // 这里我们使用一个简单的正则解析策略，提取关键点
    // 
    // 实际生产中，更好的做法是使用 path_parsing 库或在 python 侧预处理
    // 但为了纯 Dart 解决方案，我们做简单的关键点提取：
    // M (Move to) -> 起点
    // L (Line to) -> 直线点
    // Q (Quadratic Bezier) -> 二次贝塞尔曲线控制点和终点
    // 
    // 更精确的做法：对 Bezier 曲线进行采样
    
    final points = <Vec2>[];
    
    // 简单正则提取所有数字对
    final regExp = RegExp(r'([MLQ])\s*(-?\d+)\s*(-?\d+)(?:\s*(-?\d+)\s*(-?\d+))?');
    final matches = regExp.allMatches(pathData);
    
    // 上一个点，用于贝塞尔插值
    // Vec2? lastPoint; 
    
    for (final match in matches) {
      final cmd = match.group(1);
      final x1 = double.parse(match.group(2)!);
      final y1 = double.parse(match.group(3)!);
      
      // 坐标变换 v3：
      // 这里的原始数据在 1024x1024 空间
      // 现在的需求是：在之前“旋转180度”的基础上，再做一次“左右镜像”
      // 
      // 之前的变换（旋转180）:
      // x' = 1.0 - x/1024
      // y' = 1.0 - y/1024
      //
      // 现在的变换（在旋转180的基础上，左右镜像）：
      // x'' = 1.0 - x' = 1.0 - (1.0 - x/1024) = x/1024
      // y'' = y' = 1.0 - y/1024
      //
      // 结论：
      // M/L cmd:
      // x_final = x1 / _sourceScale
      // y_final = 1.0 - y1 / _sourceScale
      
      if (cmd == 'M' || cmd == 'L') {
        points.add(Vec2(
          x1 / _sourceScale, 
          1.0 - (y1 / _sourceScale)
        ));
        // lastPoint = points.last;
      } else if (cmd == 'Q') {
        // Q x1 y1 x y
        // 控制点 (x1, y1), 终点 (x2, y2)
        if (match.group(4) != null) {
          final cx = x1; 
          final cy = y1;
          final x2 = double.parse(match.group(4)!);
          final y2 = double.parse(match.group(5)!);
          
          if (points.isNotEmpty) {
             final p0 = points.last;
             // Sample t=0.5
             final t = 0.5;
             final mt = 1-t;
             
             // 坐标变换同上：
             // cx_final = cx / 1024
             // cy_final = 1.0 - cy / 1024
             
             final cvtCx = cx / _sourceScale;
             final cvtCy = 1.0 - cy / _sourceScale;
             final cvtX2 = x2 / _sourceScale;
             final cvtY2 = 1.0 - y2 / _sourceScale;
             
             final midX = mt*mt*p0.x + 2*mt*t*cvtCx + t*t*cvtX2;
             final midY = mt*mt*p0.y + 2*mt*t*cvtCy + t*t*cvtY2;
             
             points.add(Vec2(midX, midY));
          }

          points.add(Vec2(
            x2 / _sourceScale, 
            1.0 - (y2 / _sourceScale)
          ));
        }
      }
    }
    
    return points;
  }
  
  /// 从 medians (骨架线) 解析
  /// 如果我们只需要单线字体（写字机模式），使用 medians 可能比 strokes 轮廓更合适！
  static List<Vec2> parseMedians(List<dynamic> mediansData) {
     return mediansData.map((ptPair) {
        final pair = (ptPair as List).cast<num>();
        // 应用坐标变换 v3 (旋转180 + 左右镜像) -> 相当于只在 Y 轴翻转
        // x_final = x / 1024
        // y_final = 1.0 - y / 1024
        return Vec2(
          pair[0].toDouble() / _sourceScale, 
          1.0 - pair[1].toDouble() / _sourceScale
        );
     }).toList();
  }

  // 工厂方法：从 MakeMeAHanzi 的 JSON Entry 创建 Glyph
  // 输入格式: {"character":"一", "strokes":["M..."], "medians":[[[x,y],...]]}
  static Glyph parseEntry(Map<String, dynamic> json, {bool useOutline = false}) {
     final char = json['character'] as String;
     final strokes = <Stroke>[];
     
     if (useOutline) {
       // 解析轮廓 (SVG Path)
       // 注意：SVG Path 通常是闭合的轮廓，但这对于写字机来说是"空心字"
       // 如果用户想要画轮廓，用 pending 处理
       final paths = json['strokes'] as List;
       for (final pathStr in paths) {
         final points = parseSvgPath(pathStr as String);
         if (points.length > 1) {
           strokes.add(Stroke(points: points));
         }
       }
     } else {
       // 解析骨架 (Medians) - 更适合写字机/单线字体
       final medians = json['medians'] as List;
       for (final medianStroke in medians) {
         final points = parseMedians(medianStroke as List);
         if (points.length > 1) {
           strokes.add(Stroke(points: points));
         }
       }
     }
     
     return Glyph(character: char, strokes: strokes);
  }
}
