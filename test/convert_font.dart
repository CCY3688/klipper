import 'dart:convert';
import 'dart:io';

import 'package:klipper/writing/font/makemeahanzi_converter.dart';
import 'package:klipper/writing/model/stroke_analyzer.dart';

void main() async {
  // 1. 配置路径
  // 输入：MakeMeAHanzi 的 graphics.txt
  final inputPath = r'd:\ccy\Desktop\makemeahanzi\graphics.txt';
  // 输出：你的工程 assets/fonts 目录下的新字库文件
  final outputPath = r'd:\ccy\Desktop\flutter\1.0\klipper\assets\fonts\makemeahanzi_standard.json';

  // 2. 准备工作
  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    print('错误：找不到输入文件 $inputPath');
    return;
  }

  print('开始转换字库...');
  print('输入: $inputPath');
  print('输出: $outputPath');

  final outputMap = <String, dynamic>{
    'units': 'normalized_0_1',
    'source': 'MakeMeAHanzi',
    'license': 'Arphic Technology (Public License)',
    'glyphs': <String, dynamic>{},
  };

  final glyphsMap = outputMap['glyphs'] as Map<String, dynamic>;
  final analyzer = StrokeAnalyzer(); // 用于自动推断笔画类型
  int count = 0;

  // 3. 逐行读取并转换
  // graphics.txt 很大，使用 Stream 逐行处理避免内存溢出
  final lines = inputFile.openRead()
      .transform(utf8.decoder)
      .transform(LineSplitter());

  await for (final line in lines) {
    if (line.trim().isEmpty) continue;

    try {
      final jsonEntry = jsonDecode(line) as Map<String, dynamic>;
      // 使用转换器解析 (useOutline: false 表示使用骨架线，适合写字机)
      final rawGlyph = MakeMeAHanziConverter.parseEntry(jsonEntry, useOutline: false);
      
      if (rawGlyph.isEmpty) continue;

      // 自动分析笔画类型 (横、竖、撇、捺...)
      final analyzedGlyph = analyzer.analyzeGlyph(rawGlyph);

      // 转换为你的 JSON 存储格式
      // {
      //   "strokes": [
      //     {"points": [[x,y],...], "type": "horizontal"}
      //   ]
      // }
      final glyphJson = {
        'strokes': analyzedGlyph.strokes.map((s) {
          return {
            'points': s.points.map((p) => [
              double.parse(p.x.toStringAsFixed(4)), // 保留4位小数减小体积
              double.parse(p.y.toStringAsFixed(4))
            ]).toList(),
            'type': s.type?.name // 保存推断出的类型
          };
        }).toList(),
      };

      glyphsMap[rawGlyph.character] = glyphJson;
      count++;

      if (count % 1000 == 0) {
        print('已处理 $count 个字符...');
      }
    } catch (e) {
      print('处理行时出错: $e');
      // 继续处理下一行
    }
  }

  print('转换完成！共生成 $count 个字形。');
  
  // 3.5 注入手动定义的标点符号
  print('正在注入标点符号...');
  _injectPunctuation(glyphsMap);
  print('标点符号注入完成。');

  print('正在写入文件...');

  // 4. 写入结果
  final outputFile = File(outputPath);
  // 使用缩进格式化以便人类可读（可选，正式包建议去掉缩进以减小体积）
  // 这里为了方便你查看，暂时不压缩
  await outputFile.writeAsString(jsonEncode(outputMap));
  
  print('写入成功！文件大小: ${(outputFile.lengthSync() / 1024 / 1024).toStringAsFixed(2)} MB');
}

/// 注入手动定义的标点符号 (0-1 坐标系)
void _injectPunctuation(Map<String, dynamic> glyphsMap) {
  // 简易笔画定义：List<List<double>> representing points [x, y]
  final punctuations = <String, List<List<List<double>>>>{
    // 逗号 ， (左下角一撇)
    '，': [
      [[0.2, 0.8], [0.25, 0.85], [0.15, 0.95]]
    ],
    // 句号 。 (左下角圆圈，用多边形模拟)
    '。': [
      [[0.15, 0.8], [0.25, 0.8], [0.25, 0.9], [0.15, 0.9], [0.15, 0.8]]
    ],
    // 顿号 、 (左下角斜点)
    '、': [
      [[0.2, 0.8], [0.3, 0.9]]
    ],
    // 冒号 ： (居中偏左两个点)
    '：': [
      [[0.2, 0.4], [0.3, 0.4], [0.3, 0.48], [0.2, 0.48], [0.2, 0.4]], // 上点
      [[0.2, 0.75], [0.3, 0.75], [0.3, 0.83], [0.2, 0.83], [0.2, 0.75]], // 下点
    ],
    // 分号 ； (上点下撇)
    '；': [
      [[0.2, 0.4], [0.3, 0.4], [0.3, 0.48], [0.2, 0.48], [0.2, 0.4]], // 上点
      [[0.2, 0.75], [0.25, 0.83], [0.15, 0.93]], // 下撇
    ],
    // 感叹号 ！ (竖+点)
    '！': [
      [[0.5, 0.15], [0.5, 0.65]], // 竖
      [[0.45, 0.78], [0.55, 0.78], [0.55, 0.88], [0.45, 0.88], [0.45, 0.78]], // 点
    ],
    // 问号 ？ (曲线+点)
    '？': [
      [[0.3, 0.25], [0.7, 0.25], [0.7, 0.45], [0.5, 0.55], [0.5, 0.65]], // 问号弯
      [[0.45, 0.78], [0.55, 0.78], [0.55, 0.88], [0.45, 0.88], [0.45, 0.78]], // 点
    ],
    // 双引号 “ (左上两点)
    '“': [
      [[0.2, 0.2], [0.25, 0.3], [0.15, 0.35]], 
      [[0.35, 0.2], [0.4, 0.3], [0.3, 0.35]],
    ],
    // 双引号 ” (右上两点)
    '”': [
      [[0.6, 0.2], [0.65, 0.3], [0.55, 0.35]], 
      [[0.75, 0.2], [0.8, 0.3], [0.7, 0.35]],
    ],
    // 左括号 （ 
    '（': [
      [[0.6, 0.2], [0.4, 0.35], [0.4, 0.65], [0.6, 0.8]]
    ],
    // 右括号 ）
    '）': [
      [[0.4, 0.2], [0.6, 0.35], [0.6, 0.65], [0.4, 0.8]]
    ],
  };

  final analyzer = StrokeAnalyzer();

  punctuations.forEach((char, strokes) {
    // 构造 stroke 数据
    // 标点符号通常比较简单，直接存入即可，也可以跑一下 analyze 获取 geometry info
    final glyphStrokes = strokes.map((pts) {
      return MarkerStroke(pts);
    }).toList();

    // 转换为 Json
    final glyphJson = {
      'strokes': glyphStrokes.map((s) {
        // 这里只是为了复用 analyze 逻辑，实际标点符号不需要太复杂的分析，
        // 但为了格式统一，我们还是生成 type
        return {
          'points': s.points,
          'type': 'other' // 标点符号默认 other
        };
      }).toList(),
    };
    
    // 如果字库里已经有了（虽然不太可能），覆盖它
    glyphsMap[char] = glyphJson;
  });
}

class MarkerStroke {
  final List<List<double>> points;
  MarkerStroke(this.points);
}
