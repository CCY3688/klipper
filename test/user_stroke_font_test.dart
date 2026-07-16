import 'package:flutter_test/flutter_test.dart';
import 'package:klipper/writing/font/stroke_font.dart';
import 'package:klipper/writing/model/geometry.dart';
import 'package:klipper/writing/model/glyph.dart';
import 'package:klipper/writing/model/stroke.dart';
import 'package:klipper/writing/user_font/user_font_profile.dart';
import 'package:klipper/writing/user_font/user_stroke_font.dart';

void main() {
  Glyph glyph(String ch, double y) {
    return Glyph(
      character: ch,
      strokes: [
        Stroke(points: [Vec2(0, y), Vec2(1, y)]),
      ],
    );
  }

  test('ASCII glyphs prefer fallback font over imported user font', () {
    final userA = glyph('A', 0);
    final fallbackA = glyph('A', 1);
    final userZh = glyph('赋', 0.25);

    final profile = UserFontProfile(
      id: 'test',
      name: 'wo de zi ti',
      source: FontSourceType.ttf,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      learnedGlyphs: {'A': userA, '赋': userZh},
    );
    final font = UserStrokeFont(
      profile: profile,
      fallback: StrokeFont.fromGlyphs({'A': fallbackA}),
    );

    expect(font.richGlyphOf('A'), same(fallbackA));
    expect(font.richGlyphOf('赋'), same(userZh));
  });
}
