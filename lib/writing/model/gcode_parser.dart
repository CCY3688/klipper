import 'geometry.dart';
import 'toolpath.dart';

class GcodeParser {
  ToolPath parse(String gcode) {
    final List<ToolPolyline> polylines = [];
    List<Vec2> currentPoints = [];
    bool isPenDown = false;
    Vec2 currentPos = const Vec2(0, 0);

    final lines = gcode.split('\n');
    for (var line in lines) {
      line = line.split(';')[0].trim(); // Remove comments
      if (line.isEmpty) continue;

      if (line.startsWith('PEN_UP')) {
        if (currentPoints.length >= 2) {
          polylines.add(ToolPolyline(penDown: isPenDown, points: List.from(currentPoints)));
        }
        isPenDown = false;
        currentPoints = [currentPos];
      } else if (line.startsWith('PEN_DOWN')) {
        if (currentPoints.length >= 2) {
          polylines.add(ToolPolyline(penDown: isPenDown, points: List.from(currentPoints)));
        }
        isPenDown = true;
        currentPoints = [currentPos];
      } else if (line.startsWith('G0') || line.startsWith('G1')) {
        final xMatch = RegExp(r'X([-+]?[0-9]*\.?[0-9]+)').firstMatch(line);
        final yMatch = RegExp(r'Y([-+]?[0-9]*\.?[0-9]+)').firstMatch(line);
        
        if (xMatch != null || yMatch != null) {
          double newX = xMatch != null ? double.parse(xMatch.group(1)!) : currentPos.x;
          double newY = yMatch != null ? double.parse(yMatch.group(1)!) : currentPos.y;
          currentPos = Vec2(newX, newY);
          
          if (currentPoints.isEmpty) {
            currentPoints.add(currentPos);
          } else {
            currentPoints.add(currentPos);
          }
        }
      }
    }

    if (currentPoints.length >= 2) {
      polylines.add(ToolPolyline(penDown: isPenDown, points: currentPoints));
    }

    return ToolPath(polylines: polylines);
  }
}
