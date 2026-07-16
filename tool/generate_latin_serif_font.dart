import 'dart:convert';
import 'dart:io';

import 'package:klipper/writing/user_font/skeleton/outline_rasterizer.dart';
import 'package:klipper/writing/user_font/skeleton/skeleton_vectorizer.dart';
import 'package:klipper/writing/user_font/skeleton/skeletonizer.dart';
import 'package:klipper/writing/user_font/ttf/ttf_parser.dart';

const _chars =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    'abcdefghijklmnopqrstuvwxyz'
    '0123456789'
    ',.!?;:()[]<>/\\@#\$%^&*-+=_|`\'"~';

Future<void> main(List<String> args) async {
  final sourcePath = args.isNotEmpty ? args[0] : r'C:\Windows\Fonts\times.ttf';
  final outputPath = args.length > 1
      ? args[1]
      : 'assets/fonts/times_new_roman_latin.json';

  final sourceFile = File(sourcePath);
  if (!sourceFile.existsSync()) {
    stderr.writeln('Font file not found: $sourcePath');
    exitCode = 1;
    return;
  }

  final parser = TtfParser.parse(await sourceFile.readAsBytes());
  final glyphs = <String, Object?>{};
  final skipped = <String>[];

  for (final ch in _chars.split('')) {
    final glyphId = parser.glyphIdForCodePoint(ch.runes.single);
    final outline = parser.glyphOutlineForChar(ch);
    if (glyphId == null || outline == null || outline.isEmpty) {
      skipped.add(ch);
      continue;
    }

    final bitmap = OutlineRasterizer.rasterize(
      outline,
      resolution: 256,
      padding: 10,
    );
    final skeleton = Skeletonizer.skeletonize(bitmap);
    final strokes = SkeletonVectorizer.vectorize(skeleton, minStrokePixels: 2);

    final rawStrokes = <List<List<double>>>[];
    for (final stroke in strokes) {
      final points = <List<double>>[];
      for (final point in stroke.points) {
        points.add([_round(point.x), _round(point.y)]);
      }
      if (points.length >= 2) rawStrokes.add(points);
    }

    if (rawStrokes.isEmpty) {
      skipped.add(ch);
      continue;
    }

    final advance = parser.advanceWidthForGlyph(glyphId).toDouble();
    final aspectRatio = (advance / parser.unitsPerEm).clamp(0.2, 1.4);
    glyphs[ch] = {'strokes': rawStrokes, 'aspectRatio': _round(aspectRatio)};
  }

  final output = {
    'units': 'normalized_0_1',
    'source': {
      'name': 'Times New Roman Regular Latin stroke fallback',
      'sourceFile': sourceFile.uri.pathSegments.last,
      'generator': 'tool/generate_latin_serif_font.dart',
      'note':
          'Generated from a local system font using outline skeletonization.',
    },
    'glyphs': glyphs,
  };

  final encoder = const JsonEncoder.withIndent('  ');
  final outFile = File(outputPath);
  await outFile.parent.create(recursive: true);
  await outFile.writeAsString('${encoder.convert(output)}\n');

  stdout.writeln(
    'Wrote ${glyphs.length} glyphs to ${outFile.path}'
    '${skipped.isEmpty ? '' : '; skipped: ${skipped.join()}'}',
  );
}

double _round(double value) => double.parse(value.toStringAsFixed(4));
