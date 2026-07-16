//把世界坐标(mm)映射到屏幕(px)。先做最小：缩放+平移（不做旋转）。
import 'dart:ui';

class Viewport {
  double scale;    // px per mm
  Offset pan;      // px

  Viewport({required this.scale, required this.pan});

  Offset mmToPx(double xMm, double yMm) => Offset(xMm * scale, yMm * scale) + pan;

  Rect mmRectToPx(Rect mmRect) {
    final tl = mmToPx(mmRect.left, mmRect.top);
    final br = mmToPx(mmRect.right, mmRect.bottom);
    return Rect.fromPoints(tl, br);
  }
}