import 'package:flutter_test/flutter_test.dart';
import 'package:klipper/writing/font/stroke_font.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Hershey latin fallback contains letters and exclamation mark',
    () async {
      final font = await StrokeFont.loadFromAsset(
        'assets/fonts/hershey_simplex_latin.json',
      );

      expect(font.richGlyphOf('A'), isNotNull);
      expect(font.richGlyphOf('I'), isNotNull);
      expect(font.richGlyphOf('!'), isNotNull);
      expect(font.richGlyphOf('!')!.isEmpty, isFalse);
    },
  );
}
