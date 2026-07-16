import 'dart:math' as math;

class StlVector3 {
  final double x;
  final double y;
  final double z;

  const StlVector3(this.x, this.y, this.z);

  StlVector3 operator +(StlVector3 other) =>
      StlVector3(x + other.x, y + other.y, z + other.z);

  StlVector3 operator -(StlVector3 other) =>
      StlVector3(x - other.x, y - other.y, z - other.z);

  StlVector3 operator *(double factor) =>
      StlVector3(x * factor, y * factor, z * factor);

  double dot(StlVector3 other) => x * other.x + y * other.y + z * other.z;

  double get length => math.sqrt(dot(this));

  StlVector3 normalized() {
    final l = length;
    if (l <= 1e-9) return const StlVector3(0, 0, 1);
    return StlVector3(x / l, y / l, z / l);
  }

  static StlVector3 cross(StlVector3 a, StlVector3 b) {
    return StlVector3(
      a.y * b.z - a.z * b.y,
      a.z * b.x - a.x * b.z,
      a.x * b.y - a.y * b.x,
    );
  }
}

class StlTriangle {
  final StlVector3 a;
  final StlVector3 b;
  final StlVector3 c;
  final StlVector3 normal;

  const StlTriangle({
    required this.a,
    required this.b,
    required this.c,
    required this.normal,
  });

  StlVector3 get center => StlVector3(
    (a.x + b.x + c.x) / 3,
    (a.y + b.y + c.y) / 3,
    (a.z + b.z + c.z) / 3,
  );

  static StlVector3 computedNormal(StlVector3 a, StlVector3 b, StlVector3 c) {
    return StlVector3.cross(b - a, c - a).normalized();
  }
}

class StlBounds {
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
  final double minZ;
  final double maxZ;

  const StlBounds({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.minZ,
    required this.maxZ,
  });

  double get width => maxX - minX;
  double get depth => maxY - minY;
  double get height => maxZ - minZ;

  double get maxSpan => math.max(width, math.max(depth, height));

  double get diagonal =>
      math.sqrt(width * width + depth * depth + height * height);

  StlVector3 get center =>
      StlVector3((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2);

  static StlBounds fromTriangles(List<StlTriangle> triangles) {
    if (triangles.isEmpty) {
      return const StlBounds(
        minX: 0,
        maxX: 0,
        minY: 0,
        maxY: 0,
        minZ: 0,
        maxZ: 0,
      );
    }

    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var maxZ = -double.infinity;

    void include(StlVector3 p) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      minZ = math.min(minZ, p.z);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
      maxZ = math.max(maxZ, p.z);
    }

    for (final triangle in triangles) {
      include(triangle.a);
      include(triangle.b);
      include(triangle.c);
    }

    return StlBounds(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      minZ: minZ,
      maxZ: maxZ,
    );
  }
}

class StlMesh {
  final String name;
  final List<StlTriangle> triangles;
  final StlBounds bounds;

  const StlMesh({
    required this.name,
    required this.triangles,
    required this.bounds,
  });

  int get faceCount => triangles.length;

  int get vertexCount => triangles.length * 3;

  bool get isEmpty => triangles.isEmpty;

  List<StlTriangle> sampledTriangles(int maxFaces) {
    if (triangles.length <= maxFaces) return triangles;
    final result = <StlTriangle>[];
    final step = triangles.length / maxFaces;
    var cursor = 0.0;
    while (result.length < maxFaces && cursor < triangles.length) {
      result.add(triangles[cursor.floor()]);
      cursor += step;
    }
    return result;
  }

  /// 应用变换矩阵，返回新的 StlMesh
  /// 需要从 surface_registration.dart 导入 Transform3D
  StlMesh transformed(dynamic transform) {
    final transformedTriangles = triangles.map((triangle) {
      final newA = transform.transformPoint(triangle.a);
      final newB = transform.transformPoint(triangle.b);
      final newC = transform.transformPoint(triangle.c);
      final newNormal = StlTriangle.computedNormal(newA, newB, newC);
      return StlTriangle(
        a: newA,
        b: newB,
        c: newC,
        normal: newNormal,
      );
    }).toList();

    return StlMesh(
      name: name,
      triangles: transformedTriangles,
      bounds: StlBounds.fromTriangles(transformedTriangles),
    );
  }
}
