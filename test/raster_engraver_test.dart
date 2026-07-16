import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:klipper/writing/engraving/raster_engraver.dart';

void main() {
  test('builds horizontal scan segments for dark pixels', () {
    final image = img.Image(width: 3, height: 2);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, 255, 255, 255);
      }
    }
    image.setPixelRgb(0, 0, 0, 0, 0);
    image.setPixelRgb(1, 0, 0, 0, 0);
    image.setPixelRgb(2, 1, 0, 0, 0);

    final path = RasterEngraver.buildToolPath(
      image,
      options: const RasterEngraveOptions(
        originXmm: 10,
        originYmm: 20,
        widthMm: 2,
        heightMm: 1,
        stepMm: 1,
        threshold: 128,
      ),
    );

    expect(path.polylines, hasLength(2));
    expect(path.polylines.first.penDown, isTrue);
    expect(path.polylines.first.points.first.x, 10);
    expect(path.polylines.first.points.first.y, 20);
    expect(path.polylines.first.points.last.x, 11);
    expect(path.polylines.last.points.first.x, 12);
    expect(path.polylines.last.points.first.y, 21);
    expect(path.polylines.last.points.last.x, 11);
  });

  test('invert engraves light pixels instead of dark pixels', () {
    final image = img.Image(width: 2, height: 1);
    image.setPixelRgb(0, 0, 0, 0, 0);
    image.setPixelRgb(1, 0, 255, 255, 255);

    final path = RasterEngraver.buildToolPath(
      image,
      options: const RasterEngraveOptions(
        originXmm: 0,
        originYmm: 0,
        widthMm: 1,
        heightMm: 1,
        stepMm: 1,
        threshold: 128,
        invert: true,
      ),
    );

    expect(path.polylines, hasLength(1));
    expect(path.polylines.single.points.last.x, 1);
  });
}
