import 'dart:convert';
import 'dart:typed_data';

import 'stl_mesh.dart';

class StlParseException implements Exception {
  final String message;

  const StlParseException(this.message);

  @override
  String toString() => message;
}

class StlParser {
  static StlMesh parse(Uint8List bytes, {String name = 'model.stl'}) {
    if (bytes.isEmpty) {
      throw const StlParseException('STL 文件为空');
    }

    final triangles = _looksLikeBinary(bytes)
        ? _parseBinary(bytes)
        : _parseAscii(bytes);

    if (triangles.isEmpty) {
      throw const StlParseException('未解析到有效三角面');
    }

    return StlMesh(
      name: name,
      triangles: triangles,
      bounds: StlBounds.fromTriangles(triangles),
    );
  }

  static bool _looksLikeBinary(Uint8List bytes) {
    if (bytes.length < 84) return false;
    final data = ByteData.sublistView(bytes);
    final faceCount = data.getUint32(80, Endian.little);
    final expectedLength = 84 + faceCount * 50;
    if (expectedLength == bytes.length) return true;

    final headerLength = bytes.length < 256 ? bytes.length : 256;
    final header = ascii.decode(
      bytes.sublist(0, headerLength),
      allowInvalid: true,
    );
    final startsWithSolid = header.trimLeft().startsWith('solid');
    return !startsWithSolid;
  }

  static List<StlTriangle> _parseBinary(Uint8List bytes) {
    if (bytes.length < 84) {
      throw const StlParseException('二进制 STL 文件长度不足');
    }

    final data = ByteData.sublistView(bytes);
    final faceCount = data.getUint32(80, Endian.little);
    final expectedLength = 84 + faceCount * 50;
    if (expectedLength > bytes.length) {
      throw const StlParseException('二进制 STL 面片数据不完整');
    }

    final triangles = <StlTriangle>[];
    var offset = 84;
    for (var i = 0; i < faceCount; i++) {
      final normal = _readVector(data, offset);
      final a = _readVector(data, offset + 12);
      final b = _readVector(data, offset + 24);
      final c = _readVector(data, offset + 36);
      final computed = StlTriangle.computedNormal(a, b, c);
      triangles.add(
        StlTriangle(
          a: a,
          b: b,
          c: c,
          normal: normal.length <= 1e-9 ? computed : normal.normalized(),
        ),
      );
      offset += 50;
    }
    return triangles;
  }

  static StlVector3 _readVector(ByteData data, int offset) {
    return StlVector3(
      data.getFloat32(offset, Endian.little).toDouble(),
      data.getFloat32(offset + 4, Endian.little).toDouble(),
      data.getFloat32(offset + 8, Endian.little).toDouble(),
    );
  }

  static List<StlTriangle> _parseAscii(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final vertexPattern = RegExp(
      r'vertex\s+([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)\s+'
      r'([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)\s+'
      r'([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)',
      caseSensitive: false,
    );
    final vertices = <StlVector3>[];

    for (final match in vertexPattern.allMatches(text)) {
      vertices.add(
        StlVector3(
          double.parse(match.group(1)!),
          double.parse(match.group(2)!),
          double.parse(match.group(3)!),
        ),
      );
    }

    final triangles = <StlTriangle>[];
    for (var i = 0; i + 2 < vertices.length; i += 3) {
      final a = vertices[i];
      final b = vertices[i + 1];
      final c = vertices[i + 2];
      triangles.add(
        StlTriangle(
          a: a,
          b: b,
          c: c,
          normal: StlTriangle.computedNormal(a, b, c),
        ),
      );
    }
    return triangles;
  }
}
