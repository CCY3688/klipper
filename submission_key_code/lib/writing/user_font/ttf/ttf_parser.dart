/// TTF/OTF 二进制字体文件解析器（纯 Dart 实现）
///
/// 支持表：head, cmap (Format 4), maxp, loca, glyf, hhea, hmtx
/// 支持简单字形（Simple Glyph）和空字形（Space Glyph）。
/// 不支持：复合字形（Composite, numberOfContours < 0）、CFF/PostScript 轮廓。
/// 
/// 参考规范：https://docs.microsoft.com/en-us/typography/opentype/spec/
library;

import 'dart:typed_data';
import 'ttf_glyph_outline.dart';

/// TTF 解析异常
class TtfParseException implements Exception {
  final String message;
  TtfParseException(this.message);
  @override
  String toString() => 'TtfParseException: $message';
}

/// TTF 二进制解析器
class TtfParser {
  final ByteData _data;
  int _pos = 0;

  // 表偏移量缓存
  int _cmapOffset = 0;
  int _locaOffset = 0;
  int _glyfOffset = 0;
  int _headOffset = 0;
  int _maxpOffset = 0;
  int _hheaOffset = 0;
  int _hmtxOffset = 0;

  // head 表数据
  int _indexToLocFormat = 0; // 0 = short, 1 = long
  int _unitsPerEm = 1000;

  // maxp 表数据
  int _numGlyphs = 0;

  // hhea 表数据
  int _numberOfHMetrics = 0;

  // cmap: unicode → glyphId
  final Map<int, int> _unicodeToGlyphId = {};

  TtfParser._(this._data);

  // ─────────────────────────────────────────────────────────────────────
  // 公开工厂：解析字节数据
  // ─────────────────────────────────────────────────────────────────────

  static TtfParser parse(Uint8List bytes) {
    final parser = TtfParser._(ByteData.sublistView(bytes));
    parser._parse();
    return parser;
  }

  // ─────────────────────────────────────────────────────────────────────
  // 公开查询接口
  // ─────────────────────────────────────────────────────────────────────

  /// 每 em 字体单位数（通常 1000 或 2048）
  int get unitsPerEm => _unitsPerEm;

  /// 总字形数量
  int get numGlyphs => _numGlyphs;

  /// 通过 Unicode 码点获取字形 ID（不存在返回 null）
  int? glyphIdForCodePoint(int codePoint) => _unicodeToGlyphId[codePoint];

  /// 通过字形 ID 获取轮廓数据
  TtfGlyphOutline? glyphOutlineById(int glyphId) {
    if (glyphId < 0 || glyphId >= _numGlyphs) return null;
    return _readGlyph(glyphId);
  }

  /// 通过 Unicode 字符获取轮廓
  TtfGlyphOutline? glyphOutlineForChar(String char) {
    final cp = char.runes.first;
    final id = _unicodeToGlyphId[cp];
    if (id == null) return null;
    return glyphOutlineById(id);
  }

  /// 获取字形前进宽度（字体单位）
  int advanceWidthForGlyph(int glyphId) {
    if (glyphId < 0 || glyphId >= _numGlyphs) return _unitsPerEm;
    final idx = glyphId < _numberOfHMetrics ? glyphId : _numberOfHMetrics - 1;
    final offset = _hmtxOffset + idx * 4;
    return _readUint16(offset);
  }

  /// 支持的 Unicode 码点集合
  Set<int> get supportedCodePoints => _unicodeToGlyphId.keys.toSet();

  // ─────────────────────────────────────────────────────────────────────
  // 核心解析流程
  // ─────────────────────────────────────────────────────────────────────

  void _parse() {
    _readOffsetTable();
    _readTableDirectory();
    _readHeadTable();
    _readMaxpTable();
    _readHheaTable();
    _readCmapTable();
  }

  void _readOffsetTable() {
    _pos = 0;
    final sfVersion = _readUint32(0);
    // 0x00010000 = TrueType, 0x4F54544F = 'OTTO' (CFF)
    if (sfVersion != 0x00010000 && sfVersion != 0x4F54544F && sfVersion != 0x74727565) {
      throw TtfParseException('不支持的字体格式: 0x${sfVersion.toRadixString(16)}');
    }
    _pos = 12; // skip numTables, searchRange, entrySelector, rangeShift
  }

  void _readTableDirectory() {
    _pos = 4;
    final numTables = _readUint16(_pos);
    _pos = 12; // 跳过 offset table

    for (int i = 0; i < numTables; i++) {
      final tag = _readTag(_pos);
      // skip checkSum (4bytes)
      final offset = _readUint32(_pos + 8);
      // skip length (4bytes)
      _pos += 16;

      switch (tag) {
        case 'cmap': _cmapOffset = offset;
        case 'loca': _locaOffset = offset;
        case 'glyf': _glyfOffset = offset;
        case 'head': _headOffset = offset;
        case 'maxp': _maxpOffset = offset;
        case 'hhea': _hheaOffset = offset;
        case 'hmtx': _hmtxOffset = offset;
      }
    }

    if (_cmapOffset == 0) throw TtfParseException('缺少 cmap 表');
    if (_headOffset == 0) throw TtfParseException('缺少 head 表');
    if (_maxpOffset == 0) throw TtfParseException('缺少 maxp 表');
  }

  void _readHeadTable() {
    // head 表 offset 0: version (fixed), 4: fontRevision (fixed), ...
    // offset 50: indexToLocFormat (int16), 0=short loca, 1=long loca
    _unitsPerEm = _readUint16(_headOffset + 18);
    _indexToLocFormat = _readInt16(_headOffset + 50);
  }

  void _readMaxpTable() {
    _numGlyphs = _readUint16(_maxpOffset + 4);
  }

  void _readHheaTable() {
    // numberOfHMetrics is at offset 34 in hhea table
    _numberOfHMetrics = _readUint16(_hheaOffset + 34);
  }

  void _readCmapTable() {
    final version = _readUint16(_cmapOffset);
    if (version != 0) {
      // 仍尝试继续，某些字体 version 字段不为 0 但格式正常
    }

    final numSubtables = _readUint16(_cmapOffset + 2);
    int format4Offset = 0;
    // 优先找 platformID=3 (Windows), encodingID=1 (BMP Unicode)
    // 次选 platformID=0 (Unicode), encodingID=3 (BMP)
    // 次选 platformID=0, encodingID=4 (Full Unicode via format 12)
    int bestScore = -1;

    for (int i = 0; i < numSubtables; i++) {
      final base = _cmapOffset + 4 + i * 8;
      final platformId = _readUint16(base);
      final encodingId = _readUint16(base + 2);
      final subtableOffset = _cmapOffset + _readUint32(base + 4);
      final format = _readUint16(subtableOffset);

      int score = -1;
      if (platformId == 3 && encodingId == 1 && format == 4) {
        score = 10;
      } else if (platformId == 0 && encodingId == 3 && format == 4) {
        score = 8;
      } else if (platformId == 0 && format == 4) {
        score = 5;
      }

      if (score > bestScore) {
        bestScore = score;
        format4Offset = subtableOffset;
      }
    }

    if (format4Offset == 0 || bestScore < 0) {
      throw TtfParseException('找不到支持 BMP Unicode 的 cmap Format 4 子表');
    }

    _parseCmapFormat4(format4Offset);
  }

  void _parseCmapFormat4(int base) {
    // Format 4 结构：
    // 0: format=4, 2: length, 4: language
    // 6: segCountX2, 8: searchRange, 10: entrySelector, 12: rangeShift
    // 14: endCode[segCount], 14+segCountX2: reservedPad=0
    // 14+segCountX2+2: startCode[segCount]
    // 14+segCountX2+2+segCountX2: idDelta[segCount]
    // 14+segCountX2+2+segCountX2*2: idRangeOffset[segCount]
    // 14+segCountX2+2+segCountX2*3: glyphIdArray[...]

    final segCountX2 = _readUint16(base + 6);
    final segCount = segCountX2 ~/ 2;

    final endCodesBase   = base + 14;
    final startCodesBase = endCodesBase + segCountX2 + 2;
    final deltaBase      = startCodesBase + segCountX2;
    final rangeOffBase   = deltaBase + segCountX2;
    // glyphIdArray starts at: rangeOffBase + segCountX2 (used via idRangeOffset)

    for (int i = 0; i < segCount; i++) {
      final endCode   = _readUint16(endCodesBase + i * 2);
      final startCode = _readUint16(startCodesBase + i * 2);
      final delta     = _readInt16(deltaBase + i * 2);
      final rangeOff  = _readUint16(rangeOffBase + i * 2);

      if (startCode == 0xFFFF) break; // 终止 segment

      for (int cp = startCode; cp <= endCode; cp++) {
        int glyphId;
        if (rangeOff == 0) {
          glyphId = (cp + delta) & 0xFFFF;
        } else {
          // rangeOffset 是相对于其自身地址的偏移
          final rangeOffAddr = rangeOffBase + i * 2;
          final glyphIdAddr = rangeOffAddr + rangeOff + (cp - startCode) * 2;
          if (glyphIdAddr + 2 > _data.lengthInBytes) continue;
          glyphId = _readUint16(glyphIdAddr);
          if (glyphId != 0) {
            glyphId = (glyphId + delta) & 0xFFFF;
          }
        }
        if (glyphId > 0 && glyphId < _numGlyphs) {
          _unicodeToGlyphId[cp] = glyphId;
        }
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // 字形读取
  // ─────────────────────────────────────────────────────────────────────

  TtfGlyphOutline? _readGlyph(int glyphId) {
    final glyfOffset = _getGlyfOffset(glyphId);
    if (glyfOffset < 0) return null; // 空字形（如空格）

    final nextOffset = _getGlyfOffset(glyphId + 1);
    if (nextOffset >= 0 && nextOffset == glyfOffset) {
      // 此字形无轮廓数据
      return TtfGlyphOutline(
        advanceWidth: advanceWidthForGlyph(glyphId),
        leftSideBearing: 0,
        contours: const [],
        xMin: 0, yMin: 0, xMax: 0, yMax: 0,
      );
    }

    final numberOfContours = _readInt16(glyfOffset);
    final xMin = _readInt16(glyfOffset + 2);
    final yMin = _readInt16(glyfOffset + 4);
    final xMax = _readInt16(glyfOffset + 6);
    final yMax = _readInt16(glyfOffset + 8);
    final aw = advanceWidthForGlyph(glyphId);

    if (numberOfContours < 0) {
      // 复合字形（Composite Glyph）：暂不支持，返回空轮廓
      // 未来可递归展开 component glyphs
      return TtfGlyphOutline(
        advanceWidth: aw,
        leftSideBearing: xMin,
        contours: const [],
        xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax,
      );
    }

    if (numberOfContours == 0) {
      return TtfGlyphOutline(
        advanceWidth: aw,
        leftSideBearing: xMin,
        contours: const [],
        xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax,
      );
    }

    // 读取 end points of contours
    final endPts = List<int>.generate(
      numberOfContours,
      (i) => _readUint16(glyfOffset + 10 + i * 2),
    );
    final totalPoints = endPts.last + 1;

    // 跳过 instructionLength + instructions
    final instrLenOffset = glyfOffset + 10 + numberOfContours * 2;
    final instrLen = _readUint16(instrLenOffset);
    int ptr = instrLenOffset + 2 + instrLen;

    // 读取 flags（含 REPEAT_FLAG 展开）
    final flags = <int>[];
    while (flags.length < totalPoints) {
      final flag = _data.getUint8(ptr++);
      flags.add(flag);
      if ((flag & 0x08) != 0) {
        // REPEAT_FLAG: 下一字节是重复次数
        final repeat = _data.getUint8(ptr++);
        for (int r = 0; r < repeat; r++) {
          flags.add(flag);
        }
      }
    }

    // 读取 x 坐标（相对坐标，累加）
    final xCoords = <int>[];
    int xCur = 0;
    for (int i = 0; i < totalPoints; i++) {
      final f = flags[i];
      if ((f & 0x02) != 0) {
        // X_SHORT_VECTOR: 1 byte
        final val = _data.getUint8(ptr++);
        xCur += (f & 0x10) != 0 ? val : -val;
      } else if ((f & 0x10) != 0) {
        // X_IS_SAME: same as previous
      } else {
        // 2 bytes signed
        xCur += _readInt16(ptr);
        ptr += 2;
      }
      xCoords.add(xCur);
    }

    // 读取 y 坐标
    final yCoords = <int>[];
    int yCur = 0;
    for (int i = 0; i < totalPoints; i++) {
      final f = flags[i];
      if ((f & 0x04) != 0) {
        // Y_SHORT_VECTOR: 1 byte
        final val = _data.getUint8(ptr++);
        yCur += (f & 0x20) != 0 ? val : -val;
      } else if ((f & 0x20) != 0) {
        // Y_IS_SAME
      } else {
        yCur += _readInt16(ptr);
        ptr += 2;
      }
      yCoords.add(yCur);
    }

    // 组装轮廓
    final contours = <TtfContour>[];
    int start = 0;
    for (final endPt in endPts) {
      final pts = <TtfPoint>[];
      for (int i = start; i <= endPt; i++) {
        pts.add(TtfPoint(
          xCoords[i].toDouble(),
          yCoords[i].toDouble(),
          onCurve: (flags[i] & 0x01) != 0,
        ));
      }
      if (pts.length >= 2) {
        contours.add(TtfContour(pts));
      }
      start = endPt + 1;
    }

    // 读取 lsb（从 hmtx 表）
    final lsb = _readLsb(glyphId);

    return TtfGlyphOutline(
      advanceWidth: aw,
      leftSideBearing: lsb,
      contours: contours,
      xMin: xMin,
      yMin: yMin,
      xMax: xMax,
      yMax: yMax,
    );
  }

  int _getGlyfOffset(int glyphId) {
    if (glyphId >= _numGlyphs + 1) return -1;
    if (_locaOffset == 0 || _glyfOffset == 0) return -1;

    if (_indexToLocFormat == 0) {
      // short format: offset = loca[i] * 2
      final raw = _readUint16(_locaOffset + glyphId * 2);
      final next = glyphId < _numGlyphs
          ? _readUint16(_locaOffset + (glyphId + 1) * 2)
          : raw;
      if (raw == next) return -1; // 空字形
      return _glyfOffset + raw * 2;
    } else {
      // long format
      final raw = _readUint32(_locaOffset + glyphId * 4);
      final next = glyphId < _numGlyphs
          ? _readUint32(_locaOffset + (glyphId + 1) * 4)
          : raw;
      if (raw == next) return -1;
      return _glyfOffset + raw;
    }
  }

  int _readLsb(int glyphId) {
    if (_hmtxOffset == 0) return 0;
    if (glyphId < _numberOfHMetrics) {
      return _readInt16(_hmtxOffset + glyphId * 4 + 2);
    } else {
      // lsb-only array after the hMetrics
      final lsbBase = _hmtxOffset + _numberOfHMetrics * 4;
      final idx = glyphId - _numberOfHMetrics;
      return _readInt16(lsbBase + idx * 2);
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // 低级读取工具
  // ─────────────────────────────────────────────────────────────────────

  String _readTag(int offset) {
    return String.fromCharCodes([
      _data.getUint8(offset),
      _data.getUint8(offset + 1),
      _data.getUint8(offset + 2),
      _data.getUint8(offset + 3),
    ]);
  }

  int _readUint16(int offset) => _data.getUint16(offset, Endian.big);
  int _readInt16(int offset) => _data.getInt16(offset, Endian.big);
  int _readUint32(int offset) => _data.getUint32(offset, Endian.big);
}
