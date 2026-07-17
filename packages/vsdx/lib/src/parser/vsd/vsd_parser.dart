/// Visio binary (VSD5 / VSD6 / VSD11) parser → [VsdxDocument].
///
/// Stream / chunk layout follows the publicly documented Visio binary structure
/// (algorithm reference: LibreOffice libvisio `VSDParser` / `VSD5Parser`).
/// Independent Dart implementation — no C++ source is copied.
library;

import 'dart:typed_data';

import '../../core/exceptions.dart';
import '../../model/document.dart';
import '../../model/fill.dart';
import '../../model/geometry.dart';
import '../../model/image.dart';
import '../../model/layer.dart';
import '../../model/line.dart';
import '../../model/page.dart';
import '../../model/rich_text.dart';
import '../../model/shape.dart';
import '../../utils/color.dart';
import 'vsd_byte_reader.dart';
import 'vsd_internal_stream.dart';
import 'vsd_record_ids.dart';

const int _minusOne = 0xFFFFFFFF;

class _GeomBuilder {
  _GeomBuilder();
  bool noFill = false;
  bool noLine = false;
  bool noShow = false;
  final commands = <VsdxPathCommand>[];
  final order = <int>[];
  final byId = <int, VsdxPathCommand>{};
  int? geometryFlagsId;
}

class _ShapeDraft {
  _ShapeDraft();

  int id = 0;
  int parent = 0;
  int masterPage = _minusOne;
  int masterShape = _minusOne;
  int lineStyleId = _minusOne;
  int fillStyleId = _minusOne;
  int textStyleId = _minusOne;
  double pinX = 0;
  double pinY = 0;
  double width = 1;
  double height = 1;
  double locPinX = 0.5;
  double locPinY = 0.5;
  double angle = 0;
  bool flipX = false;
  bool flipY = false;
  bool is1D = false;
  double? beginX;
  double? beginY;
  double? endX;
  double? endY;
  VsdxLine? line;
  VsdxFill? fill;
  String? text;
  double? fontSizeInches;
  VsdxColor? textColor;
  bool bold = false;
  bool italic = false;
  bool hideText = false;
  String? fontFamily;
  String? shapeName;
  double? txtPinX;
  double? txtPinY;
  double? txtWidth;
  double? txtHeight;
  double? txtLocPinX;
  double? txtLocPinY;
  double? txtAngle;
  double? marginLeft;
  double? marginRight;
  double? marginTop;
  double? marginBottom;
  VsdxVertAlign? verticalAlign;
  VsdxColor? textBgColor;
  double? defaultTabStop;
  int? textDirection;
  bool underline = false;
  bool smallCaps = false;
  VsdxTextCase textCase = VsdxTextCase.normal;
  VsdxTextPosition textPosition = VsdxTextPosition.normal;
  bool strikethrough = false;
  bool doubleUnderline = false;
  bool doubleStrikethrough = false;
  double fontScale = 1.0;
  VsdxHorzAlign? paraAlign;
  double? indFirst;
  double? indLeft;
  double? indRight;
  double? spLine;
  double? spBefore;
  double? spAfter;
  int? bullet;
  String? bulletStr;
  String? bulletFont;
  double? bulletFontSize;
  double? textPosAfterBullet;
  int? paraFlags;
  List<int> layerMemberIds = [];
  /// Child shape ids from ShapeList trailer (libvisio `m_shapeList` order).
  final childOrder = <int>[];
  final geometries = <_GeomBuilder>[];
  _GeomBuilder? currentGeom;
  Uint8List? foreignBytes;
  int foreignType = 0;
  int foreignFormat = 0;
  /// ShapeData polyline blobs keyed by chunk id (libvisio `m_polylineData`).
  final polylineData = <int, List<Offset2D>>{};
  /// ShapeData NURBS blobs keyed by chunk id.
  final nurbsData = <int, ({List<Offset2D> cps, List<double> knots, List<double> weights, int degree})>{};
  /// Pending PolylineTo that references ShapeData by id.
  final pendingPolylineDataIds = <int, ({double x, double y, int dataId})>{};
  /// Pending NURBSTo that references ShapeData by id.
  final pendingNurbsDataIds = <int, ({double x, double y, int dataId})>{};
  /// Text field display values in document order (for ￼ / 0x1E substitution).
  final fieldDisplays = <String>[];
  /// CharIX rows in encounter order (libvisio `m_charList`) for multi-run text.
  final charRuns = <_CharRunDraft>[];
  /// ParaIX rows in encounter order (libvisio `m_paraList`).
  final paraRuns = <_ParaRunDraft>[];
  /// TabsData rows (libvisio `m_tabSets`).
  final tabRuns = <_TabSetDraft>[];
}

class _CharRunDraft {
  int charCount = 0;
  String? fontFamily;
  double? fontSizeInches;
  VsdxColor? textColor;
  bool bold = false;
  bool italic = false;
  bool underline = false;
  bool smallCaps = false;
  VsdxTextCase textCase = VsdxTextCase.normal;
  VsdxTextPosition textPosition = VsdxTextPosition.normal;
  bool strikethrough = false;
  bool doubleUnderline = false;
  bool doubleStrikethrough = false;
  double fontScale = 1.0;
}

class _ParaRunDraft {
  int charCount = 0;
  VsdxHorzAlign? paraAlign;
  double? indFirst;
  double? indLeft;
  double? indRight;
  double? spLine;
  double? spBefore;
  double? spAfter;
  int? bullet;
  String? bulletStr;
  String? bulletFont;
  double? bulletFontSize;
  double? textPosAfterBullet;
  int? paraFlags;
}

class _TabSetDraft {
  int id = 0;
  int numChars = 0;
  final stops = <VsdxTabStop>[];
}

class _StyleDraft {
  VsdxLine? line;
  VsdxFill? fill;
  int lineParent = _minusOne;
  int fillParent = _minusOne;
  int textParent = _minusOne;
  // Text style cells collected while `_isInStyles` (libvisio style sheet Char/Para/TextBlock).
  String? fontFamily;
  double? fontSizeInches;
  VsdxColor? textColor;
  bool bold = false;
  bool italic = false;
  bool underline = false;
  bool smallCaps = false;
  VsdxTextCase textCase = VsdxTextCase.normal;
  VsdxTextPosition textPosition = VsdxTextPosition.normal;
  bool strikethrough = false;
  bool doubleUnderline = false;
  bool doubleStrikethrough = false;
  double fontScale = 1.0;
  bool hideText = false;
  double? marginLeft;
  double? marginRight;
  double? marginTop;
  double? marginBottom;
  VsdxVertAlign? verticalAlign;
  VsdxColor? textBgColor;
  double? defaultTabStop;
  int? textDirection;
  VsdxHorzAlign? paraAlign;
  double? indFirst;
  double? indLeft;
  double? indRight;
  double? spLine;
  double? spBefore;
  double? spAfter;
  int? bullet;
  String? bulletStr;
  String? bulletFont;
  double? bulletFontSize;
  double? textPosAfterBullet;
  int? paraFlags;
  bool hasCharStyle = false;
  bool hasParaStyle = false;
  bool hasTextBlock = false;
}

class _PageDraft {
  _PageDraft(this.id);
  final int id;
  String name = 'Page-1';
  double width = 8.5;
  double height = 11.0;
  /// `pageScale / drawingScale` from PageProps (libvisio `m_scale`).
  double scale = 1.0;
  final shapes = <_ShapeDraft>[];
  final shapeOrder = <int>[];
  final layers = <VsdxLayer>[];
}

/// Parses a VisioDocument stream (VSD5 / VSD6 / VSD11) into an editable model.
class VsdBinaryParser {
  VsdBinaryParser(this._docStream);

  final Uint8List _docStream;
  late VsdByteReader _input;
  int _version = 11;

  final _colours = <VsdxColor>[];
  final _styles = <int, _StyleDraft>{};
  final _pages = <_PageDraft>[];
  /// Name2 table: nameId → decoded string (libvisio `m_names`).
  final _names = <int, String>{};
  /// NameIDX: level → (elementId → name) (libvisio `m_namesMapMap`).
  final _namesByLevel = <int, Map<int, String>>{};
  /// FontFace id → family name (libvisio `m_fonts`).
  final _fonts = <int, String>{};
  /// stencilPageId → (shapeId → draft)
  final _stencils = <int, Map<int, _ShapeDraft>>{};
  Map<int, _ShapeDraft>? _currentStencilShapes;
  _PageDraft? _currentPage;
  _ShapeDraft? _shape;
  bool _isShapeStarted = false;
  bool _isInStyles = false;
  bool _isStencilStarted = false;
  int _currentLevel = 0;
  int _currentShapeLevel = 0;
  int _currentShapeId = _minusOne;
  VsdChunkHeader _header = VsdChunkHeader();
  int _currentStyleId = _minusOne;
  bool _isBackgroundPage = false;

  VsdxDocument parse() {
    _input = VsdByteReader(_docStream);
    _verifyMagic();
    _input.seek(0x1A);
    _version = _input.readU8();
    if (_version != 5 && _version != 6 && _version != 11) {
      throw VsdxFormatException(
        'Unsupported Visio binary version $_version '
        '(supported: 5 = Visio 5, 6 = Visio 2000, 11 = Visio 2002–2010)',
      );
    }

    _input.seek(0x24);
    final trailerPtr = _readPointer(_input);
    final compressed = trailerPtr.compressed;
    final shift = compressed ? 4 : 0;
    _input.seek(trailerPtr.offset);
    final trailerRaw = _input.readBytes(trailerPtr.length);
    final trailerBytes = vsdInflate(trailerRaw, compressed: compressed);
    final trailer = VsdByteReader(trailerBytes);

    // Two passes: styles first, then content (mirrors libvisio).
    _parseDocument(trailer, shift, collectStylesOnly: true);
    _handleLevelChange(0);
    _resetPassState();
    trailer.seek(0);
    _parseDocument(trailer, shift, collectStylesOnly: false);
    _handleLevelChange(0);

    return _buildDocument();
  }

  void _verifyMagic() {
    const magic = 'Visio (TM) Drawing\r\n\x00';
    _input.seek(0);
    final bytes = _input.readBytes(magic.length);
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic.codeUnitAt(i)) {
        throw const VsdxFormatException('Missing VisioDocument magic');
      }
    }
  }

  void _resetPassState() {
    _pages.clear();
    _currentPage = null;
    _currentStencilShapes = null;
    // Keep _stencils across? No — styles pass skips them; content rebuilds.
    _stencils.clear();
    // Preserve name/font tables collected in the styles pass.
    _foreignPartByShapeId.clear();
    _foreignTypeByShapeId.clear();
    _shape = null;
    _isShapeStarted = false;
    _isInStyles = false;
    _isStencilStarted = false;
    _currentLevel = 0;
    _currentShapeLevel = 0;
    _currentShapeId = _minusOne;
    _isBackgroundPage = false;
  }

  void _parseDocument(
    VsdByteReader input,
    int shift, {
    required bool collectStylesOnly,
  }) {
    final visited = <int>{};
    _handleStreams(
      input,
      VsdRecordId.trailerStream,
      shift,
      0,
      visited,
      collectStylesOnly: collectStylesOnly,
    );
  }

  void _handleStreams(
    VsdByteReader input,
    int ptrType,
    int shift,
    int level,
    Set<int> visited, {
    required bool collectStylesOnly,
  }) {
    final ptrList = <int, VsdPointer>{};
    final fontFaces = <int, VsdPointer>{};
    final nameList = <int, VsdPointer>{};
    final nameIdx = <int, VsdPointer>{};
    final pointerOrder = <int>[];

    try {
      final info = _readPointerInfo(input, ptrType, shift);
      var listSize = info.listSize;
      for (var i = 0; i < info.pointerCount; i++) {
        final ptr = _readPointer(input);
        if (ptr.type == 0) continue;
        if (ptr.type == VsdRecordId.fontFaces ||
            ptr.type == VsdRecordId.fontList) {
          fontFaces[i] = ptr;
        } else if (ptr.type == VsdRecordId.nameList2) {
          nameList[i] = ptr;
        } else if (ptr.type == VsdRecordId.nameIdx ||
            ptr.type == VsdRecordId.nameIdx123) {
          nameIdx[i] = ptr;
        } else {
          ptrList[i] = ptr;
        }
      }
      if (listSize <= 1) listSize = 0;
      while (listSize-- > 0) {
        pointerOrder.add(input.readU32());
      }
    } catch (_) {
      ptrList.clear();
      pointerOrder.clear();
    }

    for (final e in nameList.entries) {
      _handleStream(e.value, e.key, level + 1, visited,
          collectStylesOnly: collectStylesOnly);
    }
    for (final e in nameIdx.entries) {
      _handleStream(e.value, e.key, level + 1, visited,
          collectStylesOnly: collectStylesOnly);
    }
    for (final e in fontFaces.entries) {
      _handleStream(e.value, e.key, level + 1, visited,
          collectStylesOnly: collectStylesOnly);
    }
    // Prefer stencils before pages so master shapes exist when pages instantiate.
    final stencilPtrs = <MapEntry<int, VsdPointer>>[];
    final pagePtrs = <MapEntry<int, VsdPointer>>[];
    final otherPtrs = <MapEntry<int, VsdPointer>>[];
    for (final e in ptrList.entries) {
      if (e.value.type == VsdRecordId.stencils) {
        stencilPtrs.add(e);
      } else if (e.value.type == VsdRecordId.pages) {
        pagePtrs.add(e);
      } else {
        otherPtrs.add(e);
      }
    }
    if (pointerOrder.isNotEmpty) {
      for (final j in pointerOrder) {
        final ptr = ptrList.remove(j);
        if (ptr != null) {
          _handleStream(ptr, j, level + 1, visited,
              collectStylesOnly: collectStylesOnly);
        }
      }
    }
    for (final e in [...stencilPtrs, ...otherPtrs, ...pagePtrs]) {
      if (!ptrList.containsKey(e.key)) continue;
      ptrList.remove(e.key);
      _handleStream(e.value, e.key, level + 1, visited,
          collectStylesOnly: collectStylesOnly);
    }
  }

  void _handleStream(
    VsdPointer ptr,
    int idx,
    int level,
    Set<int> visited, {
    required bool collectStylesOnly,
  }) {
    _header = VsdChunkHeader()
      ..level = level
      ..id = idx
      ..chunkType = ptr.type;
    _handleLevelChange(level);

    // Skip background pages; styles-only pass skips page/stencil content.
    if (ptr.type == VsdRecordId.page) {
      if (collectStylesOnly) return;
      _isBackgroundPage = (ptr.format & 0x1) == 0;
      if (_isBackgroundPage) return;
      final resolved = _nameFromId(idx, level + 1);
      // Reject pure-numeric "names" (often mis-mapped NameIDX entries).
      final pageName =
          (resolved != null && !RegExp(r'^\d+$').hasMatch(resolved))
              ? resolved
              : 'Page-${_pages.length + 1}';
      _currentPage = _PageDraft(idx)..name = pageName;
      _pages.add(_currentPage!);
    }
    if (ptr.type == VsdRecordId.styles) {
      _isInStyles = true;
    }
    if (ptr.type == VsdRecordId.stencils) {
      if (collectStylesOnly) return;
      if (_stencils.isNotEmpty) return;
      _isStencilStarted = true;
    }
    if (ptr.type == VsdRecordId.stencilPage) {
      if (collectStylesOnly || !_isStencilStarted) return;
      _currentStencilShapes = <int, _ShapeDraft>{};
      _stencils[idx] = _currentStencilShapes!;
    }
    if (ptr.type == VsdRecordId.shapeGroup ||
        ptr.type == VsdRecordId.shapeShape ||
        ptr.type == VsdRecordId.shapeForeign) {
      if (!collectStylesOnly) _currentShapeId = idx;
    }

    _input.seek(ptr.offset);
    final raw = _input.readBytes(ptr.length);
    final streamBytes = vsdInflate(raw, compressed: ptr.compressed);
    final stream = VsdByteReader(streamBytes);
    _header.dataLength = streamBytes.length;
    final shift = ptr.compressed ? 4 : 0;
    final fmtHi = ptr.format >> 4;

    if (fmtHi == 0x4 || fmtHi == 0x5 || fmtHi == 0x0) {
      _handleBlob(stream, shift, level + 1, collectStylesOnly: collectStylesOnly);
      if (fmtHi == 0x5 && ptr.type != VsdRecordId.colors) {
        if (visited.add(ptr.offset)) {
          try {
            _handleStreams(
              stream,
              ptr.type,
              shift,
              level + 1,
              visited,
              collectStylesOnly: collectStylesOnly,
            );
          } finally {
            visited.remove(ptr.offset);
          }
        }
      }
    } else if (fmtHi == 0xd || fmtHi == 0xc || fmtHi == 0x8) {
      _handleChunks(stream, level + 1, collectStylesOnly: collectStylesOnly);
    }

    if (ptr.type == VsdRecordId.styles) {
      _handleLevelChange(0);
      _isInStyles = false;
    }
    if (ptr.type == VsdRecordId.page) {
      _handleLevelChange(0);
      _currentPage = null;
    }
    if (ptr.type == VsdRecordId.stencilPage) {
      _handleLevelChange(0);
      _currentStencilShapes = null;
    }
    if (ptr.type == VsdRecordId.stencils) {
      _handleLevelChange(0);
      _isStencilStarted = false;
    }
    if ((ptr.type == VsdRecordId.shapeGroup ||
            ptr.type == VsdRecordId.shapeShape ||
            ptr.type == VsdRecordId.shapeForeign) &&
        _isStencilStarted) {
      _handleLevelChange(0);
    }
  }

  void _handleBlob(
    VsdByteReader input,
    int shift,
    int level, {
    required bool collectStylesOnly,
  }) {
    try {
      _header.level = level;
      input.seek(shift);
      _header.dataLength -= shift;
      _handleLevelChange(_header.level);
      _handleChunk(input, collectStylesOnly: collectStylesOnly);
    } catch (_) {}
  }

  void _handleChunks(
    VsdByteReader input,
    int level, {
    required bool collectStylesOnly,
  }) {
    while (!input.isEnd) {
      if (!_readChunkHeader(input)) return;
      _header.level += level;
      final endPos = _header.dataLength + _header.trailer + input.offset;
      _handleLevelChange(_header.level);
      _handleChunk(input, collectStylesOnly: collectStylesOnly);
      if (endPos > input.length) return;
      input.seek(endPos);
    }
  }

  bool _readChunkHeader(VsdByteReader input) {
    var tmp = 0;
    while (!input.isEnd && tmp == 0) {
      tmp = input.readU8();
    }
    if (input.isEnd) return false;
    input.seek(input.offset - 1);

    if (_version == 5) {
      // Visio 5: typed ints are int16; trailer always 0 (libvisio VSD5Parser).
      _header.chunkType = _getUInt(input);
      _header.id = _getUInt(input);
      _header.level = input.readU8();
      _header.unknown = input.readU8();
      _header.trailer = 0;
      _header.list = _getUInt(input);
      _header.dataLength = input.readU32();
      return true;
    }

    _header.chunkType = input.readU32();
    _header.id = input.readU32();
    _header.list = input.readU32();
    _header.trailer = 0;

    if (_version == 6) {
      // VSD6 trailer rules (algorithm reference: libvisio VSD6Parser).
      if (_header.list != 0 ||
          (_header.chunkType >= 0x64 && _header.chunkType <= 0x76) ||
          _header.chunkType == 0x2c ||
          _header.chunkType == 0xd) {
        _header.trailer += 8;
      }
      _header.dataLength = input.readU32();
      _header.level = input.readU16();
      _header.unknown = input.readU8();
      if (_header.chunkType == 0x1f || _header.chunkType == 0xc9) {
        _header.trailer = 0;
      }
      return true;
    }

    // VSD11
    if (_header.list != 0 ||
        _header.chunkType == 0x71 ||
        _header.chunkType == 0x70 ||
        _header.chunkType == 0x6b ||
        _header.chunkType == 0x6a ||
        _header.chunkType == 0x69 ||
        _header.chunkType == 0x66 ||
        _header.chunkType == 0x65 ||
        _header.chunkType == 0x2c) {
      _header.trailer += 8;
    }
    _header.dataLength = input.readU32();
    _header.level = input.readU16();
    _header.unknown = input.readU8();

    if (_header.list != 0 ||
        (_header.level == 2 && _header.unknown == 0x55) ||
        (_header.level == 2 &&
            _header.unknown == 0x54 &&
            _header.chunkType == 0xaa) ||
        (_header.level == 3 &&
            _header.unknown != 0x50 &&
            _header.unknown != 0x54)) {
      _header.trailer += 4;
    }
    const trailerChunks = <int>[
      0x64, 0x65, 0x66, 0x69, 0x6a, 0x6b, 0x6f, 0x71,
      0x92, 0xa9, 0xb4, 0xb6, 0xb9, 0xc7,
    ];
    for (final t in trailerChunks) {
      if (_header.chunkType == t &&
          _header.trailer != 12 &&
          _header.trailer != 4) {
        _header.trailer += 4;
        break;
      }
    }
    if (_header.chunkType == 0x1f ||
        _header.chunkType == 0xc9 ||
        _header.chunkType == 0x2d ||
        _header.chunkType == 0xd1) {
      _header.trailer = 0;
    }
    return true;
  }

  VsdPointer _readPointer(VsdByteReader input) =>
      _version == 5 ? input.readPointerVsd5() : input.readPointer();

  /// Positions [input] at the first pointer and returns list/pointer counts.
  ({int listSize, int pointerCount}) _readPointerInfo(
    VsdByteReader input,
    int ptrType,
    int shift,
  ) {
    if (_version == 5) {
      // Algorithm reference: libvisio VSD5Parser::readPointerInfo.
      switch (ptrType) {
        case VsdRecordId.trailerStream:
          input.seek(shift + 0x82);
        case VsdRecordId.page:
          input.seek(shift + 0x42);
        case VsdRecordId.fontList:
          input.seek(shift + 0x2e);
        case VsdRecordId.styles:
          input.seek(shift + 0x12);
        case VsdRecordId.stencils:
        case VsdRecordId.shapeForeign:
          input.seek(shift + 0x1e);
        case VsdRecordId.stencilPage:
          input.seek(shift + 0x36);
        default:
          if (ptrType > 0x45) {
            input.seek(shift + 0x1e);
          } else {
            input.seek(shift + 0xa);
          }
      }
      return (listSize: 0, pointerCount: input.readS16());
    }

    input.seek(shift);
    final offset = input.readU32();
    input.seek(offset + shift - 4);
    final listSize = input.readU32();
    final pointerCount = input.readS32();
    input.skip(4);
    return (listSize: listSize, pointerCount: pointerCount);
  }

  /// Visio 5 typed integers are signed 16-bit (libvisio `VSD5Parser::getUInt`).
  int _getUInt(VsdByteReader input) {
    if (_version == 5) {
      final v = input.readS16();
      return v < 0 ? _minusOne : v;
    }
    return input.readU32();
  }

  /// VSD5 packs child cells at the end of list chunks (libvisio handleChunkRecords).
  void _handleChunkRecords(
    VsdByteReader input, {
    required bool collectStylesOnly,
  }) {
    final startPosition = input.offset;
    final endPosition = input.offset + _header.dataLength;
    if (endPosition > input.length || endPosition - 4 < startPosition) return;
    input.seek(endPosition - 4);
    final numRecords = input.readU16();
    final headerPosition = endPosition - 4 * (numRecords + 1);
    if (headerPosition <= startPosition) return;
    var endOffset = input.readU16();
    if (endOffset > headerPosition - startPosition) {
      endOffset = headerPosition - startPosition;
    }
    final records = <int, VsdChunkHeader>{};
    input.seek(headerPosition);
    for (var i = 0; i < numRecords; i++) {
      final chunkType = input.readU16();
      final offset = input.readU16();
      var tmpStart = offset;
      while (tmpStart % 4 != 0) {
        tmpStart++;
      }
      if (tmpStart < endOffset) {
        records[tmpStart] = VsdChunkHeader(
          chunkType: chunkType,
          dataLength: endOffset - tmpStart,
          level: _header.level + 1,
        );
        endOffset = offset;
      }
    }
    var seq = 0;
    final sorted = records.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final e in sorted) {
      _header = e.value..id = seq++;
      input.seek(startPosition + e.key);
      _handleChunk(input, collectStylesOnly: collectStylesOnly);
    }
  }

  void _handleChunk(VsdByteReader input, {required bool collectStylesOnly}) {
    // In styles-only pass, keep style + name/font tables needed for content.
    if (collectStylesOnly) {
      switch (_header.chunkType) {
        case VsdRecordId.colors:
          _readColours(input);
          return;
        case VsdRecordId.styleSheet:
          _readStyleSheet(input);
          return;
        case VsdRecordId.line:
          _readLine(input);
          return;
        case VsdRecordId.fillAndShadow:
          _readFillAndShadow(input);
          return;
        case VsdRecordId.name2:
          _readName2(input);
          return;
        case VsdRecordId.nameIdx:
          _readNameIdx(input);
          return;
        case VsdRecordId.nameIdx123:
          _readNameIdx123(input);
          return;
        case VsdRecordId.fontFace:
          _readFontFace(input);
          return;
        case VsdRecordId.fontIx:
          _readFontIx(input);
          return;
        case VsdRecordId.charIx:
          _readCharIx(input);
          return;
        case VsdRecordId.paraIx:
          _readParaIx(input);
          return;
        case VsdRecordId.textBlock:
          _readTextBlock(input);
          return;
        default:
          return;
      }
    }

    switch (_header.chunkType) {
      case VsdRecordId.shapeGroup:
      case VsdRecordId.shapeShape:
      case VsdRecordId.shapeForeign:
        _readShape(input);
      case VsdRecordId.xformData:
        _readXFormData(input);
      case VsdRecordId.xform1d:
        _readXForm1D(input);
      case VsdRecordId.textXform:
        _readTextXForm(input);
      case VsdRecordId.line:
        _readLine(input);
      case VsdRecordId.fillAndShadow:
        _readFillAndShadow(input);
      case VsdRecordId.geomList:
        _readGeomList(input);
      case VsdRecordId.geometry:
        _readGeometry(input);
      case VsdRecordId.moveTo:
        _readMoveTo(input);
      case VsdRecordId.lineTo:
        _readLineTo(input);
      case VsdRecordId.arcTo:
        _readArcTo(input);
      case VsdRecordId.ellipse:
        _readEllipse(input);
      case VsdRecordId.ellipticalArcTo:
        _readEllipticalArcTo(input);
      case VsdRecordId.polylineTo:
        _readPolylineTo(input);
      case VsdRecordId.nurbsTo:
        _readNurbsTo(input);
      case VsdRecordId.infiniteLine:
        _readInfiniteLine(input);
      case VsdRecordId.splineStart:
        _readSplineStart(input);
      case VsdRecordId.splineKnot:
        _readSplineKnot(input);
      case VsdRecordId.shapeData:
        _readShapeData(input);
      case VsdRecordId.textField:
        _readTextField(input);
      case VsdRecordId.misc:
        _readMisc(input);
      case VsdRecordId.layer:
        _readLayer(input);
      case VsdRecordId.layerMembership:
        _readLayerMem(input);
      case VsdRecordId.name2:
        _readName2(input);
      case VsdRecordId.name:
        _readName(input);
      case VsdRecordId.nameIdx:
        _readNameIdx(input);
      case VsdRecordId.nameIdx123:
        _readNameIdx123(input);
      case VsdRecordId.fontFace:
        _readFontFace(input);
      case VsdRecordId.fontIx:
        _readFontIx(input);
      case VsdRecordId.textBlock:
        _readTextBlock(input);
      case VsdRecordId.pageProps:
        _readPageProps(input);
      case VsdRecordId.text:
        _readText(input);
      case VsdRecordId.charIx:
        _readCharIx(input);
      case VsdRecordId.paraIx:
        _readParaIx(input);
      case VsdRecordId.colors:
        _readColours(input);
      case VsdRecordId.styleSheet:
        _readStyleSheet(input);
      case VsdRecordId.shapeList:
        _readShapeList(input);
      case VsdRecordId.charList:
      case VsdRecordId.paraList:
      case VsdRecordId.fieldList:
      case VsdRecordId.propList:
      case VsdRecordId.tabsDataList:
        if (_version == 5) {
          _handleChunkRecords(input, collectStylesOnly: collectStylesOnly);
        }
      case VsdRecordId.tabsData1:
      case VsdRecordId.tabsData2:
      case VsdRecordId.tabsData3:
      case VsdRecordId.tabsData4:
        if (!collectStylesOnly) _readTabsData(input);
      case VsdRecordId.shapeId:
        _readShapeId(input);
      case VsdRecordId.foreignDataType:
        _readForeignDataType(input);
      case VsdRecordId.foreignData:
        _readForeignData(input);
      case VsdRecordId.pageSheet:
        _currentShapeLevel = _header.level;
      default:
        break;
    }
  }

  void _handleLevelChange(int level) {
    if (level == _currentLevel) return;
    if (level <= _currentShapeLevel) {
      _flushShape();
      _shape = null;
      _isShapeStarted = false;
    }
    _currentLevel = level;
  }

  void _flushShape() {
    if (!_isShapeStarted || _shape == null) return;
    final d = _shape!;

    if (_isStencilStarted) {
      final bucket = _currentStencilShapes;
      if (bucket != null) {
        bucket[d.id] = d;
      }
      return;
    }

    if (_currentPage == null) return;
    _applyMasterInheritance(d);
    if (d.line == null && d.lineStyleId != _minusOne) {
      d.line = _styles[d.lineStyleId]?.line;
    }
    if (d.fill == null && d.fillStyleId != _minusOne) {
      d.fill = _styles[d.fillStyleId]?.fill;
    }
    _applyTextStyle(d);
    _resolvePendingShapeData(d);
    // Drop GeomList shells that never received path commands (common on
    // ForeignData picture frames — trailer may list child ids with no rows).
    d.geometries.removeWhere((g) => g.byId.isEmpty);
    // Line fallback for 1D connectors without geometry.
    if (d.geometries.isEmpty && d.is1D) {
      final x0 = 0.0;
      final y0 = d.height / 2;
      final x1 = d.width;
      final y1 = d.height / 2;
      final g = _GeomBuilder()
        ..byId[0] = MoveTo(x0, y0)
        ..byId[1] = LineTo(x1, y1)
        ..order.addAll([0, 1]);
      d.geometries.add(g);
    }
    // Rectangle fallback: text-only, picture frame, or unresolved master.
    if (d.geometries.isEmpty && !d.is1D) {
      final g = _GeomBuilder()
        ..byId[0] = const MoveTo(0, 0)
        ..byId[1] = LineTo(d.width, 0)
        ..byId[2] = LineTo(d.width, d.height)
        ..byId[3] = LineTo(0, d.height)
        ..byId[4] = const LineTo(0, 0)
        ..order.addAll([0, 1, 2, 3, 4]);
      // Picture frames: no stroke fill from geometry — painter draws the image.
      if (d.foreignBytes != null) {
        g.noLine = true;
        g.noFill = true;
      }
      d.geometries.add(g);
    }
    _currentPage!.shapes.add(d);
  }

  void _resolvePendingShapeData(_ShapeDraft d) {
    for (final e in d.pendingPolylineDataIds.entries) {
      final pts = d.polylineData[e.value.dataId];
      for (final g in d.geometries) {
        if (!g.byId.containsKey(e.key)) continue;
        if (pts != null && pts.isNotEmpty) {
          g.byId[e.key] = PolylineTo(
            x: e.value.x,
            y: e.value.y,
            vertices: pts,
          );
        }
        break;
      }
    }
    d.pendingPolylineDataIds.clear();
    for (final e in d.pendingNurbsDataIds.entries) {
      final n = d.nurbsData[e.value.dataId];
      for (final g in d.geometries) {
        if (!g.byId.containsKey(e.key)) continue;
        if (n != null && n.cps.isNotEmpty) {
          g.byId[e.key] = NurbsTo(
            x: e.value.x,
            y: e.value.y,
            controlPoints: n.cps,
            knots: n.knots,
            weights: n.weights,
            degree: n.degree,
          );
        }
        break;
      }
    }
    d.pendingNurbsDataIds.clear();
  }

  /// Replace Visio field placeholders (`U+FFFC` / `0x1E`) with field values.
  String _expandFieldMarkers(String text, List<String> fields) {
    if (fields.isEmpty) return text;
    final out = StringBuffer();
    var fi = 0;
    for (var i = 0; i < text.length; i++) {
      final cu = text.codeUnitAt(i);
      if ((cu == 0xFFFC || cu == 0x1E) && fi < fields.length) {
        out.write(fields[fi++]);
      } else if (cu == 0xFFFC || cu == 0x1E) {
        // No matching field — drop the marker.
      } else {
        out.writeCharCode(cu);
      }
    }
    return out.toString();
  }

  void _applyMasterInheritance(_ShapeDraft d) {
    if (d.masterPage == _minusOne) return;
    final page = _stencils[d.masterPage];
    if (page == null || page.isEmpty) return;
    _ShapeDraft? master;
    if (d.masterShape != _minusOne) {
      master = page[d.masterShape];
    }
    master ??= page.values.first;
    if (d.geometries.isEmpty && master.geometries.isNotEmpty) {
      for (final g in master.geometries) {
        final ng = _GeomBuilder()
          ..noFill = g.noFill
          ..noLine = g.noLine
          ..noShow = g.noShow
          ..order.addAll(g.order)
          ..byId.addAll(g.byId);
        d.geometries.add(ng);
      }
    }
    d.line ??= master.line;
    d.fill ??= master.fill;
    d.text ??= master.text;
    d.fontSizeInches ??= master.fontSizeInches;
    d.fontFamily ??= master.fontFamily;
    d.textColor ??= master.textColor;
    d.shapeName ??= master.shapeName;
    d.txtPinX ??= master.txtPinX;
    d.txtPinY ??= master.txtPinY;
    d.txtWidth ??= master.txtWidth;
    d.txtHeight ??= master.txtHeight;
    d.txtLocPinX ??= master.txtLocPinX;
    d.txtLocPinY ??= master.txtLocPinY;
    d.txtAngle ??= master.txtAngle;
    d.marginLeft ??= master.marginLeft;
    d.marginRight ??= master.marginRight;
    d.marginTop ??= master.marginTop;
    d.marginBottom ??= master.marginBottom;
    d.verticalAlign ??= master.verticalAlign;
    d.textBgColor ??= master.textBgColor;
    d.defaultTabStop ??= master.defaultTabStop;
    d.textDirection ??= master.textDirection;
    d.paraAlign ??= master.paraAlign;
    d.indFirst ??= master.indFirst;
    d.indLeft ??= master.indLeft;
    d.indRight ??= master.indRight;
    d.spLine ??= master.spLine;
    d.spBefore ??= master.spBefore;
    d.spAfter ??= master.spAfter;
    d.bullet ??= master.bullet;
    d.bulletStr ??= master.bulletStr;
    d.bulletFont ??= master.bulletFont;
    d.bulletFontSize ??= master.bulletFontSize;
    d.textPosAfterBullet ??= master.textPosAfterBullet;
    d.paraFlags ??= master.paraFlags;
    if (!d.bold) d.bold = master.bold;
    if (!d.italic) d.italic = master.italic;
    if (!d.underline) d.underline = master.underline;
    if (!d.smallCaps) d.smallCaps = master.smallCaps;
    if (d.textCase == VsdxTextCase.normal) d.textCase = master.textCase;
    if (d.textPosition == VsdxTextPosition.normal) {
      d.textPosition = master.textPosition;
    }
    if (!d.strikethrough) d.strikethrough = master.strikethrough;
    if (!d.doubleUnderline) d.doubleUnderline = master.doubleUnderline;
    if (!d.doubleStrikethrough) {
      d.doubleStrikethrough = master.doubleStrikethrough;
    }
    if (d.fontScale == 1.0 && master.fontScale != 1.0) {
      d.fontScale = master.fontScale;
    }
    if (!d.hideText) d.hideText = master.hideText;
    if (d.charRuns.isEmpty && master.charRuns.isNotEmpty) {
      d.charRuns.addAll(master.charRuns);
    }
    if (d.paraRuns.isEmpty && master.paraRuns.isNotEmpty) {
      d.paraRuns.addAll(master.paraRuns);
    }
    // Only inherit tab sets that actually define stops (empty TabsData is
    // common on masters and would otherwise inflate every instance).
    if (d.tabRuns.isEmpty &&
        master.tabRuns.any((t) => t.stops.isNotEmpty)) {
      d.tabRuns.addAll(master.tabRuns);
    }
    if (d.layerMemberIds.isEmpty && master.layerMemberIds.isNotEmpty) {
      d.layerMemberIds = List<int>.from(master.layerMemberIds);
    }
  }

  /// Apply StyleSheet text cells referenced by [textStyleId] (libvisio).
  /// Walks the text-style parent chain so sheets without local CharIX still
  /// inherit fonts from their ancestors.
  void _applyTextStyle(_ShapeDraft d) {
    if (d.textStyleId == _minusOne) return;
    var id = d.textStyleId;
    final seen = <int>{};
    while (id != _minusOne && seen.add(id)) {
      final st = _styles[id];
      if (st == null) break;
      if (st.hasCharStyle) {
        d.fontFamily ??= st.fontFamily;
        d.fontSizeInches ??= st.fontSizeInches;
        d.textColor ??= st.textColor;
        if (!d.bold) d.bold = st.bold;
        if (!d.italic) d.italic = st.italic;
        if (!d.underline) d.underline = st.underline;
        if (!d.smallCaps) d.smallCaps = st.smallCaps;
        if (d.textCase == VsdxTextCase.normal) d.textCase = st.textCase;
        if (d.textPosition == VsdxTextPosition.normal) {
          d.textPosition = st.textPosition;
        }
        if (!d.strikethrough) d.strikethrough = st.strikethrough;
        if (!d.doubleUnderline) d.doubleUnderline = st.doubleUnderline;
        if (!d.doubleStrikethrough) {
          d.doubleStrikethrough = st.doubleStrikethrough;
        }
        if (d.fontScale == 1.0 && st.fontScale != 1.0) {
          d.fontScale = st.fontScale;
        }
      }
      if (st.hasTextBlock) {
        d.marginLeft ??= st.marginLeft;
        d.marginRight ??= st.marginRight;
        d.marginTop ??= st.marginTop;
        d.marginBottom ??= st.marginBottom;
        d.verticalAlign ??= st.verticalAlign;
        d.textBgColor ??= st.textBgColor;
        d.defaultTabStop ??= st.defaultTabStop;
        d.textDirection ??= st.textDirection;
        if (!d.hideText) d.hideText = st.hideText;
      }
      if (st.hasParaStyle) {
        d.paraAlign ??= st.paraAlign;
        d.indFirst ??= st.indFirst;
        d.indLeft ??= st.indLeft;
        d.indRight ??= st.indRight;
        d.spLine ??= st.spLine;
        d.spBefore ??= st.spBefore;
        d.spAfter ??= st.spAfter;
        d.bullet ??= st.bullet;
        d.bulletStr ??= st.bulletStr;
        d.bulletFont ??= st.bulletFont;
        d.bulletFontSize ??= st.bulletFontSize;
        d.textPosAfterBullet ??= st.textPosAfterBullet;
        d.paraFlags ??= st.paraFlags;
      }
      id = st.textParent;
    }
  }

  void _readShape(VsdByteReader input) {
    _isShapeStarted = true;
    if (_header.id != _minusOne) _currentShapeId = _header.id;
    _currentShapeLevel = _header.level;
    var parent = 0;
    var masterPage = _minusOne;
    var masterShape = _minusOne;
    var lineStyle = _minusOne;
    var fillStyle = _minusOne;
    var textStyle = _minusOne;
    try {
      if (_version == 5) {
        // Algorithm reference: libvisio VSD5Parser::readShape.
        input.skip(2);
        parent = _getUInt(input);
        input.skip(2);
        masterPage = _getUInt(input);
        masterShape = _getUInt(input);
        lineStyle = _getUInt(input);
        fillStyle = _getUInt(input);
        textStyle = _getUInt(input);
      } else {
        input.skip(10);
        parent = input.readU32();
        input.skip(4);
        masterPage = input.readU32();
        input.skip(4);
        masterShape = input.readU32();
        input.skip(4);
        fillStyle = input.readU32();
        input.skip(4);
        lineStyle = input.readU32();
        input.skip(4);
        textStyle = input.readU32();
      }
    } catch (_) {}

    // Instance cells override; geometry is inherited at flush if still empty.
    final d = _ShapeDraft()
      ..id = _currentShapeId
      ..parent = parent
      ..masterPage = masterPage
      ..masterShape = masterShape
      ..lineStyleId = lineStyle
      ..fillStyleId = fillStyle
      ..textStyleId = textStyle;
    if (!_isStencilStarted && masterPage != _minusOne) {
      final page = _stencils[masterPage];
      if (page != null && page.isNotEmpty) {
        final master = (masterShape != _minusOne ? page[masterShape] : null) ??
            page.values.first;
        d
          ..line = master.line
          ..fill = master.fill
          ..text = master.text
          ..fontSizeInches = master.fontSizeInches
          ..textColor = master.textColor
          ..bold = master.bold
          ..italic = master.italic;
      }
    }
    _shape = d;
    _currentShapeId = _minusOne;
  }

  void _readXFormData(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    input.skip(1);
    s.pinX = input.readF64();
    input.skip(1);
    s.pinY = input.readF64();
    input.skip(1);
    s.width = input.readF64();
    input.skip(1);
    s.height = input.readF64();
    input.skip(1);
    s.locPinX = input.readF64();
    input.skip(1);
    s.locPinY = input.readF64();
    input.skip(1);
    s.angle = input.readF64();
    s.flipX = input.readU8() != 0;
    s.flipY = input.readU8() != 0;
  }

  void _readXForm1D(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    s.is1D = true;
    input.skip(1);
    s.beginX = input.readF64();
    input.skip(1);
    s.beginY = input.readF64();
    input.skip(1);
    s.endX = input.readF64();
    input.skip(1);
    s.endY = input.readF64();
  }

  void _readTextXForm(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readTxtXForm.
    final s = _shape;
    if (s == null) return;
    try {
      input.skip(1);
      s.txtPinX = input.readF64();
      input.skip(1);
      s.txtPinY = input.readF64();
      input.skip(1);
      s.txtWidth = input.readF64();
      input.skip(1);
      s.txtHeight = input.readF64();
      input.skip(1);
      s.txtLocPinX = input.readF64();
      input.skip(1);
      s.txtLocPinY = input.readF64();
      input.skip(1);
      s.txtAngle = input.readF64();
    } catch (_) {}
  }

  void _readLine(VsdByteReader input) {
    late final VsdxLine line;
    if (_version == 5) {
      // Algorithm reference: libvisio VSD5Parser::readLine.
      input.skip(1);
      final strokeWidth = input.readF64();
      final colourIndex = input.readU8();
      final colour = _colourFromIndex(colourIndex);
      final pattern = input.readU8();
      input.skip(1);
      final rounding = input.readF64();
      input.skip(1);
      final startMarker = input.readU8();
      final endMarker = input.readU8();
      final lineCap = input.readU8();
      line = VsdxLine(
        color: colour,
        weightInches: strokeWidth,
        pattern: pattern,
        beginArrow: startMarker,
        endArrow: endMarker,
        roundingInches: rounding,
        cap: lineCap == 0
            ? LineCap.round
            : (lineCap == 2 ? LineCap.square : LineCap.extended),
      );
    } else {
      input.skip(1);
      final strokeWidth = input.readF64();
      input.skip(1);
      final r = input.readU8();
      final g = input.readU8();
      final b = input.readU8();
      final a = input.readU8();
      final pattern = input.readU8();
      input.skip(1);
      final rounding = input.readF64();
      input.skip(1);
      final startMarker = input.readU8();
      final endMarker = input.readU8();
      final lineCap = input.readU8();
      final colour = VsdxColor.argb(a == 0 ? 255 : a, r, g, b);
      line = VsdxLine(
        color: colour,
        weightInches: strokeWidth,
        pattern: pattern,
        beginArrow: startMarker,
        endArrow: endMarker,
        roundingInches: rounding,
        cap: lineCap == 0
            ? LineCap.round
            : (lineCap == 2 ? LineCap.square : LineCap.extended),
      );
    }
    if (_isInStyles) {
      final sid = _currentStyleId != _minusOne ? _currentStyleId : _header.id;
      final st = _styles.putIfAbsent(sid, _StyleDraft.new);
      st.line = line;
    } else {
      _shape?.line = line;
    }
  }

  void _readFillAndShadow(VsdByteReader input) {
    late final VsdxFill fill;
    if (_version == 5) {
      // Algorithm reference: libvisio VSD5Parser::readFillAndShadow.
      final colourFG = _colourFromIndex(input.readU8());
      final colourBG = _colourFromIndex(input.readU8());
      final fillPattern = input.readU8();
      input.readU8(); // shadow FG index
      input.skip(1); // shadow BG
      input.readU8(); // shadow pattern
      fill = VsdxFill(
        foreground: colourFG,
        background: colourBG,
        pattern: fillPattern,
        foregroundTransparency: 1.0 - (colourFG.alpha / 255.0),
        backgroundTransparency: 1.0 - (colourBG.alpha / 255.0),
      );
    } else {
      final fgIdx = input.readU8();
      var fgR = input.readU8();
      var fgG = input.readU8();
      var fgB = input.readU8();
      var fgA = input.readU8();
      final bgIdx = input.readU8();
      var bgR = input.readU8();
      var bgG = input.readU8();
      var bgB = input.readU8();
      var bgA = input.readU8();
      var colourFG = VsdxColor.argb(fgA == 0 ? 255 : fgA, fgR, fgG, fgB);
      var colourBG = VsdxColor.argb(bgA == 0 ? 255 : bgA, bgR, bgG, bgB);
      if (fgR == 0 && fgG == 0 && fgB == 0 && fgA == 0 &&
          bgR == 0 && bgG == 0 && bgB == 0 && bgA == 0) {
        colourFG = _colourFromIndex(fgIdx);
        colourBG = _colourFromIndex(bgIdx);
      }
      final fillPattern = input.readU8();
      // VSD11 appends shadow offsets; VSD6 stops here (algorithm reference:
      // libvisio VSD6Parser::readFillAndShadow).
      if (_version == 11) {
        try {
          input.readU8(); // shadow FG index
          input.skip(4); // shadow FG rgba
          input.readU8(); // shadow BG index
          input.skip(4); // shadow BG rgba
          input.readU8(); // shadow pattern
          input.skip(2); // shadow type + format
          input.readF64(); // shadowOffsetX
          input.skip(1);
          input.readF64(); // shadowOffsetY
        } catch (_) {}
      }
      fill = VsdxFill(
        foreground: colourFG,
        background: colourBG,
        pattern: fillPattern,
        foregroundTransparency: 1.0 - (colourFG.alpha / 255.0),
        backgroundTransparency: 1.0 - (colourBG.alpha / 255.0),
      );
    }
    if (_isInStyles) {
      final sid = _currentStyleId != _minusOne ? _currentStyleId : _header.id;
      final st = _styles.putIfAbsent(sid, _StyleDraft.new);
      st.fill = fill;
    } else {
      _shape?.fill = fill;
    }
  }

  void _readGeomList(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    if (s.geometries.isNotEmpty &&
        s.currentGeom != null &&
        s.currentGeom!.commands.isEmpty &&
        s.currentGeom!.byId.isEmpty) {
      s.geometries.removeLast();
    }
    final g = _GeomBuilder();
    s.geometries.add(g);
    s.currentGeom = g;
    if (_version == 5) {
      _handleChunkRecords(input, collectStylesOnly: false);
      return;
    }
    if (_header.trailer != 0) {
      try {
        final subHeaderLength = input.readU32();
        var childrenListLength = input.readU32();
        input.skip(subHeaderLength);
        if (childrenListLength > input.remaining) {
          childrenListLength = input.remaining;
        }
        final count = childrenListLength ~/ 4;
        for (var i = 0; i < count; i++) {
          g.order.add(input.readU32());
        }
      } catch (_) {}
    }
  }

  void _readGeometry(VsdByteReader input) {
    final g = _shape?.currentGeom;
    if (g == null) return;
    final flags = input.readU8();
    g.noFill = (flags & 1) != 0;
    g.noLine = (flags & 2) != 0;
    g.noShow = (flags & 4) != 0;
    g.geometryFlagsId = _header.id;
  }

  void _addGeomCmd(int id, VsdxPathCommand cmd) {
    final g = _shape?.currentGeom;
    if (g == null) return;
    g.byId[id] = cmd;
  }

  void _readMoveTo(VsdByteReader input) {
    input.skip(1);
    final x = input.readF64();
    input.skip(1);
    final y = input.readF64();
    _addGeomCmd(_header.id, MoveTo(x, y));
  }

  void _readLineTo(VsdByteReader input) {
    input.skip(1);
    final x = input.readF64();
    input.skip(1);
    final y = input.readF64();
    _addGeomCmd(_header.id, LineTo(x, y));
  }

  void _readArcTo(VsdByteReader input) {
    input.skip(1);
    final x2 = input.readF64();
    input.skip(1);
    final y2 = input.readF64();
    input.skip(1);
    final bow = input.readF64();
    _addGeomCmd(_header.id, ArcTo(x: x2, y: y2, bow: bow));
  }

  void _readEllipse(VsdByteReader input) {
    input.skip(1);
    final cx = input.readF64();
    input.skip(1);
    final cy = input.readF64();
    input.skip(1);
    final xleft = input.readF64();
    input.skip(1);
    final yleft = input.readF64();
    input.skip(1);
    final xtop = input.readF64();
    input.skip(1);
    final ytop = input.readF64();
    _addGeomCmd(
      _header.id,
      EllipseCmd(
        cx: cx,
        cy: cy,
        aX: xleft,
        aY: yleft,
        bX: xtop,
        bY: ytop,
      ),
    );
  }

  void _readEllipticalArcTo(VsdByteReader input) {
    input.skip(1);
    final x3 = input.readF64();
    input.skip(1);
    final y3 = input.readF64();
    input.skip(1);
    final x2 = input.readF64();
    input.skip(1);
    final y2 = input.readF64();
    input.skip(1);
    final angle = input.readF64();
    input.skip(1);
    final ecc = input.readF64();
    _addGeomCmd(
      _header.id,
      EllipticalArcTo(
        x: x3,
        y: y3,
        controlX: x2,
        controlY: y2,
        angle: angle,
        eccentricity: ecc,
      ),
    );
  }

  void _readPageProps(VsdByteReader input) {
    input.skip(1);
    final pageWidth = input.readF64();
    input.skip(1);
    final pageHeight = input.readF64();
    input.skip(1);
    input.readF64(); // shadowOffsetX
    input.skip(1);
    input.readF64(); // shadowOffsetY
    input.skip(1);
    final pageScale = input.readF64();
    input.readU8(); // drawingScaleUnit
    var drawingScale = input.readF64();
    if (drawingScale.abs() < 1e-12) drawingScale = 1.0;
    final scale = (pageScale / drawingScale).abs();
    if (_currentPage != null) {
      _currentPage!.width = pageWidth > 0 ? pageWidth : 8.5;
      _currentPage!.height = pageHeight > 0 ? pageHeight : 11.0;
      if (scale > 0 && scale.isFinite) _currentPage!.scale = scale;
    }
  }

  void _readForeignDataType(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    try {
      input.skip(1);
      input.readF64(); // offsetX
      input.skip(1);
      input.readF64(); // offsetY
      input.skip(1);
      input.readF64(); // width
      input.skip(1);
      input.readF64(); // height
      var foreignType = input.readU16();
      final mapMode = input.readU16();
      if (mapMode == 0x8) foreignType = 0x4;
      input.skip(0x9);
      final foreignFormat = input.readU32();
      s.foreignType = foreignType;
      s.foreignFormat = foreignFormat;
    } catch (_) {}
  }

  void _readForeignData(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    if (_header.dataLength <= 0 || input.remaining < _header.dataLength) return;
    s.foreignBytes = input.readBytes(_header.dataLength);
  }

  void _readPolylineTo(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readPolylineTo.
    input.skip(1);
    final x = input.readF64();
    input.skip(1);
    final y = input.readF64();
    try {
      input.skip(1);
      final useData = input.readU8();
      if (useData == 0x8b) {
        input.skip(3);
        final dataId = input.readU32();
        final s = _shape;
        if (s == null) return;
        final pts = s.polylineData[dataId];
        if (pts != null && pts.isNotEmpty) {
          _addGeomCmd(_header.id, PolylineTo(x: x, y: y, vertices: pts));
        } else {
          s.pendingPolylineDataIds[_header.id] = (x: x, y: y, dataId: dataId);
          _addGeomCmd(_header.id, LineTo(x, y)); // placeholder until flush
        }
        return;
      }
      // Formula blocks start at offset 0x30 from chunk data start.
      input.skip(0x9);
      var chunkBytesRead = 0x30;
      var cellRef = 0;
      var length = 0;
      var inputPos = input.offset;
      while (cellRef != 2 &&
          !input.isEnd &&
          _header.dataLength - chunkBytesRead > 4) {
        length = input.readU32();
        if (length == 0) break;
        input.skip(1);
        cellRef = input.readU8();
        if (cellRef < 2) {
          input.skip(length - 6);
        }
        chunkBytesRead += input.offset - inputPos;
        inputPos = input.offset;
      }
      final points = <Offset2D>[];
      if (cellRef == 2) {
        input.skip(1);
        input.readU16(); // xType
        input.skip(1);
        input.readU16(); // yType
        var flag = input.readU8();
        var blockBytesRead = 6 + (input.offset - inputPos);
        inputPos = input.offset;
        while (flag != 0x81 && blockBytesRead < length && !input.isEnd) {
          final x2 = flag == 0x20 ? input.readF64() : input.readU16().toDouble();
          final yFlag = input.readU8();
          final y2 =
              yFlag == 0x20 ? input.readF64() : input.readU16().toDouble();
          points.add(Offset2D(x2, y2));
          flag = input.readU8();
          blockBytesRead += input.offset - inputPos;
          inputPos = input.offset;
        }
      }
      if (points.isEmpty) {
        _addGeomCmd(_header.id, LineTo(x, y));
      } else {
        _addGeomCmd(
          _header.id,
          PolylineTo(x: x, y: y, vertices: points),
        );
      }
    } catch (_) {
      _addGeomCmd(_header.id, LineTo(x, y));
    }
  }

  void _readNurbsTo(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readNURBSTo (simplified).
    input.skip(1);
    final x = input.readF64();
    input.skip(1);
    final y = input.readF64();
    try {
      final knot = input.readF64();
      final weight = input.readF64();
      final knotPrev = input.readF64();
      final weightPrev = input.readF64();
      input.skip(1);
      final useData = input.readU8();
      if (useData == 0x8a) {
        input.skip(3);
        final dataId = input.readU32();
        final s = _shape;
        if (s == null) return;
        final n = s.nurbsData[dataId];
        if (n != null && n.cps.isNotEmpty) {
          _addGeomCmd(
            _header.id,
            NurbsTo(
              x: x,
              y: y,
              controlPoints: n.cps,
              knots: n.knots,
              weights: n.weights,
              degree: n.degree,
            ),
          );
        } else {
          s.pendingNurbsDataIds[_header.id] = (x: x, y: y, dataId: dataId);
          _addGeomCmd(_header.id, LineTo(x, y));
        }
        return;
      }
      // Inline formula — best-effort static block; else endpoint only.
      input.skip(9);
      final knotVector = <double>[knotPrev];
      final controlPoints = <Offset2D>[];
      final weights = <double>[weightPrev];
      var degree = 3;
      try {
        // Seek formula cell 6 similarly to libvisio (best-effort).
        var cellRef = 0;
        var length = 0;
        var chunkBytesRead = 0x50;
        var inputPos = input.offset;
        while (cellRef != 6 &&
            !input.isEnd &&
            _header.dataLength - chunkBytesRead > 4) {
          length = input.readU32();
          input.skip(1);
          cellRef = input.readU8();
          if (cellRef < 6) input.skip(length - 6);
          chunkBytesRead += input.offset - inputPos;
          inputPos = input.offset;
        }
        if (cellRef == 6) {
          final paramType = input.readU8();
          if (paramType == 0x8a) {
            final lastKnot = input.readF64();
            degree = input.readU16();
            input.readU8(); // xType
            input.readU8(); // yType
            var repetitions = input.readU32();
            while (repetitions > 0 && input.remaining >= 32) {
              final cx = input.readF64();
              final cy = input.readF64();
              final k = input.readF64();
              final w = input.readF64();
              controlPoints.add(Offset2D(cx, cy));
              knotVector.add(k);
              weights.add(w);
              repetitions--;
            }
            knotVector.add(knot);
            knotVector.add(lastKnot);
            weights.add(weight);
          }
        }
      } catch (_) {}
      if (controlPoints.isEmpty) {
        _addGeomCmd(_header.id, LineTo(x, y));
      } else {
        _addGeomCmd(
          _header.id,
          NurbsTo(
            x: x,
            y: y,
            controlPoints: controlPoints,
            knots: knotVector,
            weights: weights,
            degree: degree,
          ),
        );
      }
    } catch (_) {
      _addGeomCmd(_header.id, LineTo(x, y));
    }
  }

  void _readInfiniteLine(VsdByteReader input) {
    input.skip(1);
    final x1 = input.readF64();
    input.skip(1);
    final y1 = input.readF64();
    input.skip(1);
    final x2 = input.readF64();
    input.skip(1);
    final y2 = input.readF64();
    _addGeomCmd(
      _header.id,
      InfiniteLineCmd(x: x1, y: y1, a: x2, b: y2),
    );
  }

  void _readSplineStart(VsdByteReader input) {
    // libvisio: x,y, secondKnot, firstKnot, lastKnot, degree
    input.skip(1);
    final x = input.readF64();
    input.skip(1);
    final y = input.readF64();
    final secondKnot = input.readF64();
    final firstKnot = input.readF64();
    final lastKnot = input.readF64();
    final degree = input.readU8();
    _addGeomCmd(
      _header.id,
      SplineStart(
        x: x,
        y: y,
        a: secondKnot,
        b: firstKnot,
        c: lastKnot,
        degree: degree,
      ),
    );
  }

  void _readSplineKnot(VsdByteReader input) {
    input.skip(1);
    final x = input.readF64();
    input.skip(1);
    final y = input.readF64();
    final knot = input.readF64();
    _addGeomCmd(_header.id, SplineKnot(x: x, y: y, knot: knot));
  }

  void _readShapeData(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    try {
      final dataType = input.readU8();
      input.skip(15);
      if (dataType == 0x80) {
        input.readU8(); // xType
        input.readU8(); // yType
        var pointCount = input.readU32();
        final maxPts = input.remaining ~/ 16;
        if (pointCount > maxPts) pointCount = maxPts;
        final points = <Offset2D>[];
        for (var i = 0; i < pointCount; i++) {
          points.add(Offset2D(input.readF64(), input.readF64()));
        }
        s.polylineData[_header.id] = points;
      } else if (dataType == 0x82) {
        final lastKnot = input.readF64();
        final degree = input.readU16();
        input.readU8(); // xType
        input.readU8(); // yType
        var pointCount = input.readU32();
        final maxPts = input.remaining ~/ 32;
        if (pointCount > maxPts) pointCount = maxPts;
        final cps = <Offset2D>[];
        final knots = <double>[];
        final weights = <double>[];
        for (var i = 0; i < pointCount; i++) {
          cps.add(Offset2D(input.readF64(), input.readF64()));
          knots.add(input.readF64());
          weights.add(input.readF64());
        }
        knots.add(lastKnot);
        s.nurbsData[_header.id] = (
          cps: cps,
          knots: knots,
          weights: weights,
          degree: degree,
        );
      }
    } catch (_) {}
  }

  void _readTextField(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    // CELL_TYPE_* / format blocks — libvisio VSDParser::readTextField /
    // VSD6Parser::readTextField / VSDFieldList::getString.
    const stringWithoutUnit = 232;
    const cellTypeDate = 40;
    const formatUnknown = 0xffff;
    try {
      if (_version == 5) {
        // VSD5Parser::readTextField — no format block.
        input.skip(3);
        final cellType = input.readU8();
        if (cellType == stringWithoutUnit) {
          input.readS16();
          s.fieldDisplays.add('');
        } else {
          final numeric = input.readF64();
          final fmt = cellType == cellTypeDate ? 200 : formatUnknown;
          s.fieldDisplays
              .add(_formatNumericField(numeric, cellType, fmt, null));
        }
        return;
      }
      final initial = input.offset;
      input.skip(7);
      final cellType = input.readU8();
      if (cellType == stringWithoutUnit) {
        final nameId = input.readS32();
        input.skip(6);
        final formatStringId = input.readS32();
        var text = nameId >= 0 ? (_names[nameId] ?? '') : '';
        // Format block may request StrUpper / StrLower (libvisio TODO; we apply).
        final formatNumber = _readFieldFormatBlock(
          input,
          initial: initial,
          blockBase: _version == 6 ? initial + 0x24 : initial + 0x36,
        );
        var fmt = formatNumber;
        if (fmt == formatUnknown && formatStringId >= 0) {
          fmt = _parseFormatId(_names[formatStringId]) ?? formatUnknown;
        }
        text = _applyStringFieldFormat(text, fmt);
        s.fieldDisplays.add(text);
        final end = initial + _header.dataLength;
        if (end <= input.length && end >= input.offset) input.seek(end);
        return;
      }
      final numeric = input.readF64();
      input.skip(2);
      final formatStringId = input.readS32();

      // Trailing format block (VSD11 @0x36, VSD6 @0x24 from chunk data start).
      var formatNumber = formatUnknown;
      String? customFormat;
      final blockBase = _version == 6 ? initial + 0x24 : initial + 0x36;
      if (blockBase < input.length) {
        input.seek(blockBase);
        var blockIdx = 0;
        final limit = initial + _header.dataLength;
        while (blockIdx != 2 && !input.isEnd && input.offset < limit) {
          final inputPos = input.offset;
          final length = input.readU32();
          if (length == 0) break;
          input.skip(1);
          blockIdx = input.readU8();
          if (blockIdx != 2) {
            final next = inputPos + length;
            if (next > input.length) break;
            input.seek(next);
            continue;
          }
          final typeByte = input.readU8();
          if (typeByte == 0x62) {
            // Numeric format id + 0x80 0xc2 marker (libvisio).
            formatNumber = input.readU16();
            if (input.readU8() != 0x80 || input.readU8() != 0xc2) {
              formatNumber = formatUnknown;
              final next = inputPos + length;
              if (next > input.length) break;
              input.seek(next);
              blockIdx = 0;
              continue;
            }
            break;
          }
          if (typeByte == 0x60) {
            // Custom UTF-16 format string: u8 charCount + UTF-16LE chars
            // (e.g. `<,$>U #,##0.00`). libvisio only handles 0x62+0x80/0xc2.
            final charCount = input.readU8();
            if (charCount > 0 && input.remaining >= charCount * 2) {
              customFormat =
                  _decodeUtf16Le(input.readBytes(charCount * 2));
            }
            break;
          }
          if (typeByte == 0x70) {
            // Alternate numeric/date format payload seen in Gantt samples
            // (tdf76829): u32 + u32(formatId) + trailer. libvisio ignores this.
            if (input.remaining >= 8) {
              input.readU32();
              final fmt = input.readU32();
              if (fmt <= 221) formatNumber = fmt;
            }
            break;
          }
          // Unknown type — skip block.
          final next = inputPos + length;
          if (next > input.length) break;
          input.seek(next);
          blockIdx = 0;
        }
      }
      if (formatNumber == formatUnknown && customFormat == null) {
        if (cellType == cellTypeDate) {
          formatNumber = 200; // VSD_FIELD_FORMAT_MsoDateShort
        } else if (formatStringId >= 0) {
          final parsed = _parseFormatId(_names[formatStringId]);
          if (parsed != null) formatNumber = parsed;
        }
      }
      s.fieldDisplays.add(
          _formatNumericField(numeric, cellType, formatNumber, customFormat));
      final end = initial + _header.dataLength;
      if (end <= input.length && end >= input.offset) input.seek(end);
    } catch (_) {}
  }

  /// Parse `{<N>}` / `esc(N)` format-string ids (libvisio `parseFormatId`).
  int? _parseFormatId(String? s) {
    if (s == null || s.isEmpty) return null;
    final m = RegExp(r'^\s*(?:\{<(\d+)>\}|esc\((\d+)\))\s*$').firstMatch(s);
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? m.group(2)!);
  }

  /// Read a TextField trailing format block; returns format id or `0xffff`.
  int _readFieldFormatBlock(
    VsdByteReader input, {
    required int initial,
    required int blockBase,
  }) {
    const formatUnknown = 0xffff;
    if (blockBase >= input.length) return formatUnknown;
    try {
      input.seek(blockBase);
      var blockIdx = 0;
      final limit = initial + _header.dataLength;
      while (blockIdx != 2 && !input.isEnd && input.offset < limit) {
        final inputPos = input.offset;
        final length = input.readU32();
        if (length == 0) break;
        input.skip(1);
        blockIdx = input.readU8();
        if (blockIdx != 2) {
          final next = inputPos + length;
          if (next > input.length) break;
          input.seek(next);
          continue;
        }
        final typeByte = input.readU8();
        if (typeByte == 0x62) {
          final formatNumber = input.readU16();
          if (input.readU8() != 0x80 || input.readU8() != 0xc2) {
            final next = inputPos + length;
            if (next > input.length) break;
            input.seek(next);
            blockIdx = 0;
            continue;
          }
          return formatNumber;
        }
        // Non-numeric blocks ignored for string fields.
        break;
      }
    } catch (_) {}
    return formatUnknown;
  }

  /// Apply StrNormal / StrLower / StrUpper (formats 37–39).
  String _applyStringFieldFormat(String text, int format) {
    switch (format) {
      case 38: // StrLower
        return text.toLowerCase();
      case 39: // StrUpper
        return text.toUpperCase();
      case 37: // StrNormal
      default:
        return text;
    }
  }

  /// Format a numeric/date field (subset of libvisio `VSDNumericField::getString`).
  String _formatNumericField(
    double value,
    int cellType,
    int format, [
    String? customFormat,
  ]) {
    const formatUnknown = 0xffff;

    // Custom Visio format string from type-0x60 block (e.g. `<,$>U #,##0.00`).
    if (customFormat != null && customFormat.isNotEmpty) {
      final custom = _applyCustomFormat(value, customFormat);
      if (custom != null) return custom;
    }

    if (format == formatUnknown) {
      // Gantt / property cells often store calendar values as CELL_TYPE_Number
      // (32) with no format block (libvisio returns empty). Treat Visio serial
      // days in a sane year range as dates.
      if (cellType == 32 && _looksLikeVisioDateSerial(value)) {
        final frac = (value - value.truncateToDouble()).abs();
        final fmt = frac > 1e-4 ? 211 : 200; // datetime vs MsoDateShort
        final formatted = _formatVisioDate(value, fmt);
        if (formatted != null) return formatted;
      }
      return _formatFieldNumber(value);
    }

    // Date / time formats (Visio serial day → UTC).
    if (_isDateFormat(format) || cellType == 40) {
      final formatted = _formatVisioDate(value, format);
      if (formatted != null) return formatted;
    }

    // Resolve AngleUnits → concrete angle cell type (libvisio getString).
    var effectiveType = cellType;
    var effectiveFormat = format;
    if (cellType == 80) {
      // CELL_TYPE_AngleUnits
      if (format == 11) {
        effectiveType = 83; // Radians
      } else if (format == 12) {
        effectiveType = 81; // Degrees
      } else {
        effectiveType = 82; // DegreeMinuteSecond
      }
    }
    if (effectiveType == 82 && format == 1) {
      effectiveFormat = 12; // NumGenDefUnits on DMS → Degrees
    }

    final converted = _convertNumber(effectiveType, value);
    final suffix = _unitSuffix(effectiveType);

    // Common numeric precision formats.
    switch (effectiveFormat) {
      case 0: // NumGenNoUnits
        return _formatFieldNumber(converted);
      case 1: // NumGenDefUnits
        return '${_formatFieldNumber(converted)}$suffix';
      case 2: // 0PlNoUnits
        return converted.round().toString();
      case 3: // 0PlDefUnits
        return '${converted.round()}$suffix';
      case 4: // 1PlNoUnits
        return converted.toStringAsFixed(1);
      case 5:
        return '${converted.toStringAsFixed(1)}$suffix';
      case 6: // 2PlNoUnits
        return converted.toStringAsFixed(2);
      case 7:
        return '${converted.toStringAsFixed(2)}$suffix';
      case 8: // 3PlNoUnits
        return converted.toStringAsFixed(3);
      case 9:
        return '${converted.toStringAsFixed(3)}$suffix';
      case 11: // Radians
        return '${_convertNumber(83, value).toStringAsFixed(4)} rad';
      case 12: // Degrees (or DMS when cell is DegreeMinuteSecond)
        if (effectiveType == 82) {
          final deg = value * 57.2957795;
          final degInt = deg.truncateToDouble();
          final minTotal = (deg - degInt).abs() * 60.0;
          final minInt = minTotal.truncateToDouble();
          final sec = (minTotal - minInt) * 60.0;
          return '${degInt.round()} deg ${minInt.round()} min ${sec.round()} sec';
        }
        return '${_convertNumber(81, value).round()} deg';
      default:
        return _formatFieldNumber(converted);
    }
  }

  /// Inches/radians/days → display units (libvisio `convertNumber`).
  double _convertNumber(int cellType, double number) {
    switch (cellType) {
      case 33: // Percent
        return number * 100.0;
      case 44: // ElapsedDay
        return number;
      case 43: // ElapsedWeek
        return number / 7.0;
      case 45: // ElapsedHour
        return number * 24.0;
      case 46: // ElapsedMin
        return number * 24.0 * 60.0;
      case 47: // ElapsedSec
        return number * 24.0 * 60.0 * 60.0;
      case 65: // Inches
        return number;
      case 50: // Points
        return number * 72.0;
      case 51: // Picas
        return number * 6.0;
      case 53: // Didots
        return number * 67.75;
      case 54: // Ciceros
        return number * 5.644444444444;
      case 66: // Feet
        return number * 0.0833333333;
      case 69: // Centimeters
        return number * 2.54;
      case 68: // Miles
        return number / 63360.0;
      case 70: // Millimeters
        return number * 25.4;
      case 71: // Meters
        return number * 0.0254;
      case 72: // Kilometers
        return number * 0.0000254;
      case 75: // Yards
        return number * 0.0277777778;
      case 76: // NauticalMiles
        return number / 72913.386;
      case 83: // Radians
        return number;
      case 81: // Degrees
      case 82: // DegreeMinuteSecond
        return number * 57.2957795;
      default:
        return number;
    }
  }

  /// Best-effort Visio custom format (`<,$>U #,##0.00`, `0.00%`, …).
  String? _applyCustomFormat(double value, String format) {
    var f = format.trim();
    // Locale/currency bracket `<,$>` / `<,€>` — extract symbol before strip.
    String? currency;
    final bracket = RegExp(r'^<([^>]*)>').firstMatch(f);
    if (bracket != null) {
      final inner = bracket.group(1)!;
      if (inner.contains(r'$')) {
        currency = r'$';
      } else if (inner.contains('€')) {
        currency = '€';
      } else {
        final sym = RegExp(r'[^,\s0-9.]').firstMatch(inner);
        if (sym != null) currency = sym.group(0);
      }
      f = f.substring(bracket.end).trim();
    }
    // `U` is the currency placeholder (prefix or suffix position).
    final uPos = f.indexOf('U');
    final currencyPrefix = currency != null &&
        uPos >= 0 &&
        (f.indexOf('#') < 0 || uPos < f.indexOf('#'));
    f = f.replaceAll('U', '').trim();
    if (f.isEmpty && currency == null) return null;

    if (currency == null) {
      if (f.contains(r'$')) {
        currency = r'$';
        f = f.replaceAll(r'$', '');
      } else if (f.contains('€')) {
        currency = '€';
        f = f.replaceAll('€', '');
      }
    }
    f = f.trim();

    final isPercent = f.contains('%');
    if (isPercent) {
      f = f.replaceAll('%', '');
      value = value * 100.0;
    }

    final dot = f.lastIndexOf('.');
    var decimals = 0;
    if (dot >= 0) {
      decimals = f.substring(dot + 1).replaceAll(RegExp(r'[^0#]'), '').length;
    }
    final useGrouping = f.contains(',');
    var body = value.toStringAsFixed(decimals);
    if (useGrouping) {
      final parts = body.split('.');
      final neg = parts[0].startsWith('-');
      var intPart = neg ? parts[0].substring(1) : parts[0];
      final buf = StringBuffer();
      for (var i = 0; i < intPart.length; i++) {
        final fromEnd = intPart.length - i;
        if (i > 0 && fromEnd % 3 == 0) buf.write(',');
        buf.write(intPart[i]);
      }
      body = '${neg ? '-' : ''}${buf.toString()}'
          '${parts.length > 1 ? '.${parts[1]}' : ''}';
    }
    if (isPercent) body = '$body%';
    if (currency != null) {
      body = currencyPrefix ? '$currency$body' : '$body $currency';
    }
    return body;
  }

  bool _isDateFormat(int format) {
    if (format >= 20 && format <= 36) return true;
    if (format >= 44 && format <= 81) return true;
    if (format >= 200 && format <= 221) return true;
    return false;
  }

  String? _formatVisioDate(double serial, int format) {
    // libvisio: time_t = 86400 * serial - 2209161600.0
    final unixSec = 86400.0 * serial - 2209161600.0;
    if (!unixSec.isFinite) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(
      (unixSec * 1000.0).round(),
      isUtc: true,
    );
    String two(int n) => n.toString().padLeft(2, '0');
    String y2() => two(dt.year % 100);
    switch (format) {
      case 20: // DateShort weekday abbr
        return _weekdayAbbr(dt.weekday);
      case 21:
        return _weekdayName(dt.weekday);
      case 22:
      case 23:
      case 203: // M/d/yy
        return '${dt.month}/${dt.day}/$y2()';
      case 24: // MMM d, yyyy
        return '${_monthAbbr(dt.month)} ${dt.day}, ${dt.year}';
      case 25:
      case 202: // MMMM d, yyyy
        return '${_monthName(dt.month)} ${dt.day}, ${dt.year}';
      case 26: // d/M/yy
        return '${dt.day}/${dt.month}/$y2()';
      case 27: // dd/MM/yy
        return '${two(dt.day)}/${two(dt.month)}/$y2()';
      case 28:
        return '${dt.day} ${_monthAbbr(dt.month)}, ${dt.year}';
      case 29:
      case 208: // d MMMM yyyy
        return '${dt.day} ${_monthName(dt.month)} ${dt.year}';
      case 30:
      case 213:
        return '${dt.hour % 12 == 0 ? 12 : dt.hour % 12}:${two(dt.minute)} '
            '${dt.hour >= 12 ? 'PM' : 'AM'}';
      case 31:
      case 32:
      case 33:
      case 34:
      case 215:
        return '${two(dt.hour)}:${two(dt.minute)}';
      case 35:
      case 36:
        return '${dt.hour % 12 == 0 ? 12 : dt.hour % 12}:${two(dt.minute)} '
            '${dt.hour >= 12 ? 'PM' : 'AM'}';
      case 201: // dddd, MMMM dd, yyyy
        return '${_weekdayName(dt.weekday)}, ${_monthName(dt.month)} '
            '${two(dt.day)}, ${dt.year}';
      case 204: // yyyy-MM-dd
        return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
      case 205: // d-MMM-yy
        return '${dt.day}-${_monthAbbr(dt.month)}-$y2()';
      case 206: // M.d.yyyy
        return '${dt.month}.${dt.day}.${dt.year}';
      case 207:
        return '${_monthAbbr(dt.month)}.${dt.day}, $y2()';
      case 209:
        return '${_monthName(dt.month)} $y2()';
      case 210:
        return '${_monthAbbr(dt.month)}-$y2()';
      case 211: // M/d/yyyy h:mm am/pm
      case 212: // M/d/yyyy h:mm:ss am/pm
        {
          final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
          final ampm = dt.hour >= 12 ? 'PM' : 'AM';
          if (format == 212) {
            return '${dt.month}/${dt.day}/${dt.year} '
                '$h12:${two(dt.minute)}:${two(dt.second)} $ampm';
          }
          return '${dt.month}/${dt.day}/${dt.year} '
              '$h12:${two(dt.minute)} $ampm';
        }
      case 214:
      case 216:
        return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
      case 200: // MsoDateShort M/d/yyyy
      default:
        // Most remaining date codes map to M/d/yyyy (libvisio).
        return '${dt.month}/${dt.day}/${dt.year}';
    }
  }

  /// Visio serial day roughly covering 1954–2064 (Gantt bars, prop dates).
  bool _looksLikeVisioDateSerial(double value) {
    if (!value.isFinite) return false;
    return value >= 20000 && value <= 60000;
  }

  String _unitSuffix(int cellType) {
    // Match libvisio `getUnitString`.
    return switch (cellType) {
      33 => '%',
      36 => ' acres',
      37 => ' ha',
      43 => ' ew.',
      44 => ' ed.',
      45 => ' eh.',
      46 => ' em.',
      47 => ' es.',
      50 => ' pt',
      51 => ' p',
      53 => ' d',
      54 => ' c',
      65 => ' in',
      66 => ' ft',
      68 => ' mi',
      69 => ' cm',
      70 => ' mm',
      71 => ' m',
      72 => ' km',
      75 => ' yd',
      76 => ' nm.',
      81 => ' deg',
      83 => ' rad',
      84 => ' min',
      85 => ' sec',
      _ => '',
    };
  }

  String _monthAbbr(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][m - 1];

  String _monthName(int m) => const [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ][m - 1];

  String _weekdayAbbr(int w) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][w - 1];

  String _weekdayName(int w) => const [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday',
        'Friday', 'Saturday', 'Sunday',
      ][w - 1];

  String _formatFieldNumber(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e12) {
      return v.round().toString();
    }
    var s = v.toStringAsFixed(4);
    s = s.replaceFirst(RegExp(r'\.?0+$'), '');
    return s;
  }

  void _readMisc(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readMisc (HideText bit 0x20).
    final s = _shape;
    if (s == null) return;
    try {
      final flags = input.readU8();
      s.hideText = (flags & 0x20) != 0;
    } catch (_) {}
  }

  void _readLayer(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readLayer.
    final page = _currentPage;
    if (page == null || _isStencilStarted) return;
    try {
      input.skip(8);
      final colourId = input.readU8();
      VsdxColor? color;
      if (colourId == 0xff) {
        input.skip(4);
      } else {
        final r = input.readU8();
        final g = input.readU8();
        final b = input.readU8();
        final a = input.readU8();
        color = VsdxColor.argb(a == 0 ? 255 : a, r, g, b);
      }
      input.skip(1);
      final visible = input.readU8() != 0;
      final printable = input.readU8() != 0;
      page.layers.add(
        VsdxLayer(
          id: _header.id,
          name: 'Layer ${_header.id}',
          visible: visible,
          print: printable,
          color: color,
        ),
      );
    } catch (_) {}
  }

  void _readLayerMem(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readLayerMem /
    // VSD6Parser::readLayerMem (ANSI byte count, not UTF-16).
    final s = _shape;
    if (s == null) return;
    try {
      input.skip(13);
      final textLength = input.readU8();
      if (textLength == 0) return;
      final String text;
      if (_version < 11) {
        if (input.remaining < textLength) return;
        text = _decodeAnsi(input.readBytes(textLength));
      } else {
        final n = textLength * 2;
        if (input.remaining < n) return;
        text = _decodeUtf16Le(input.readBytes(n));
      }
      final ids = <int>[];
      for (final part in text.split(RegExp(r'[;,\s]+'))) {
        final v = int.tryParse(part.trim());
        if (v != null) ids.add(v);
      }
      if (ids.isNotEmpty) s.layerMemberIds = ids;
    } catch (_) {}
  }

  void _readName2(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readName2 (VSD11 UTF-16) /
    // VSD6Parser::readName2 (VSD5/6 ANSI).
    try {
      if (_version < 11) {
        // getInt: s32 (VSD6) / s16 (VSD5)
        if (_version == 5) {
          input.readS16();
        } else {
          input.readS32();
        }
        final chars = <int>[];
        while (!input.isEnd) {
          final c = input.readU8();
          if (c == 0) break;
          chars.add(c);
        }
        final text = String.fromCharCodes(chars).trim();
        if (text.isNotEmpty) _names[_header.id] = text;
      } else {
        input.skip(4);
        final units = <int>[];
        while (!input.isEnd) {
          final cu = input.readU16();
          units.add(cu & 0xff);
          units.add((cu >> 8) & 0xff);
          if (cu == 0) break;
        }
        final text = _decodeUtf16Le(Uint8List.fromList(units));
        if (text.isNotEmpty) _names[_header.id] = text;
      }
    } catch (_) {}
  }

  void _readName(VsdByteReader input) {
    // Shape-local name: UTF-16 on VSD11, ANSI on VSD5/6 (libvisio VSD6Parser::readName).
    final s = _shape;
    if (s == null) return;
    if (_header.dataLength <= 0 || input.remaining < _header.dataLength) return;
    try {
      final raw = input.readBytes(_header.dataLength);
      final text = _version < 11 ? _decodeAnsi(raw) : _decodeUtf16Le(raw);
      if (text.isNotEmpty) s.shapeName = text;
    } catch (_) {}
  }

  void _readNameIdx(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readNameIDX /
    // VSD5Parser::readNameIDX (U16 records).
    try {
      final names = <int, String>{};
      if (_version == 5) {
        var recordCount = input.readU16();
        final max = input.remaining ~/ 4;
        if (recordCount > max) recordCount = max;
        for (var i = 0; i < recordCount; i++) {
          final nameId = input.readU16();
          final elementId = input.readU16();
          final n = _names[nameId];
          if (n != null) names[elementId] = n;
        }
      } else {
        var recordCount = input.readU32();
        final max = input.remaining ~/ 13;
        if (recordCount > max) recordCount = max;
        for (var i = 0; i < recordCount; i++) {
          final nameId = input.readU32();
          input.readU32(); // duplicate nameId
          final elementId = input.readU32();
          input.skip(1);
          final n = _names[nameId];
          if (n != null) names[elementId] = n;
        }
      }
      _namesByLevel[_header.level] = names;
    } catch (_) {}
  }

  void _readNameIdx123(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readNameIDX123.
    try {
      final end = input.offset + _header.dataLength;
      final names = <int, String>{};
      while (!input.isEnd && input.offset < end) {
        final nameId = _getUInt(input);
        final elementId = _getUInt(input);
        final n = _names[nameId];
        if (n != null) names[elementId] = n;
      }
      _namesByLevel[_header.level] = names;
    } catch (_) {}
  }

  String? _nameFromId(int id, int level) {
    final map = _namesByLevel[level];
    if (map == null) return null;
    return map[id];
  }

  void _readFontFace(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readFont.
    try {
      input.skip(4);
      final units = <int>[];
      for (var i = 0; i < 32 && !input.isEnd; i++) {
        final lo = input.readU8();
        final hi = input.readU8();
        if (lo == 0 && hi == 0) break;
        units.add(lo);
        units.add(hi);
      }
      final name = _decodeUtf16Le(Uint8List.fromList(units));
      if (name.isNotEmpty) _fonts[_header.id] = name;
    } catch (_) {}
  }

  void _readFontIx(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readFontIX.
    // Layout: skip(2) + getUInt(codePage) + ANSI name bytes (nul-terminated).
    try {
      final start = input.offset;
      input.skip(2);
      final codePage = _getUInt(input) & 0xff;
      final remaining = _header.dataLength - (input.offset - start);
      if (remaining <= 0) return;
      final chars = <int>[];
      for (var i = 0; i < remaining && !input.isEnd; i++) {
        final c = input.readU8();
        if (c == 0) break;
        chars.add(c);
      }
      if (chars.isEmpty) return;
      var name = String.fromCharCodes(chars);
      // When codePage==0, libvisio derives it from name suffixes and strips them.
      if (codePage == 0) {
        for (final suffix in const [
          ' CE',
          ' Cyrillic',
          ' Cyr',
          ' CYR',
          ' Baltic',
          ' Greek',
          ' Tur',
          ' TUR',
          ' Hebrew',
          ' Arabic',
          ' Thai',
        ]) {
          if (name.endsWith(suffix)) {
            name = name.substring(0, name.length - suffix.length);
            break;
          }
        }
      }
      name = name.trim();
      if (name.isNotEmpty) _fonts[_header.id] = name;
    } catch (_) {}
  }

  void _readTextBlock(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readTextBlock.
    final shape = (!_isInStyles) ? _shape : null;
    final style = (_isInStyles && _currentStyleId != _minusOne)
        ? _styles.putIfAbsent(_currentStyleId, _StyleDraft.new)
        : null;
    if (shape == null && style == null) return;
    try {
      input.skip(1);
      final marginLeft = input.readF64();
      input.skip(1);
      final marginRight = input.readF64();
      input.skip(1);
      final marginTop = input.readF64();
      input.skip(1);
      final marginBottom = input.readF64();
      final valign = input.readU8();
      final verticalAlign = switch (valign) {
        0 => VsdxVertAlign.top,
        2 => VsdxVertAlign.bottom,
        _ => VsdxVertAlign.middle,
      };
      final bgIdx = input.readU8();
      input.skip(4);
      final isBgFilled = bgIdx != 0 && bgIdx != 0xff;
      final textBgColor =
          isBgFilled ? _colourFromIndex(bgIdx - 1) : null;
      input.skip(1);
      final defaultTabStop = input.readF64();
      input.skip(12);
      final textDirection = input.readU8();
      void apply(dynamic t) {
        t.marginLeft = marginLeft;
        t.marginRight = marginRight;
        t.marginTop = marginTop;
        t.marginBottom = marginBottom;
        t.verticalAlign = verticalAlign;
        if (textBgColor != null) t.textBgColor = textBgColor;
        t.defaultTabStop = defaultTabStop;
        t.textDirection = textDirection;
        if (t is _StyleDraft) t.hasTextBlock = true;
      }
      if (shape != null) apply(shape);
      if (style != null) apply(style);
    } catch (_) {}
  }

  void _readText(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    if (_header.dataLength < 8) return;
    input.skip(8);
    final n = _header.dataLength - 8;
    if (n <= 0 || input.remaining < n) return;
    final raw = input.readBytes(n);
    s.text = _version == 11 ? _decodeUtf16Le(raw) : _decodeAnsi(raw);
  }

  void _readCharIx(VsdByteReader input) {
    final shape = (!_isInStyles) ? _shape : null;
    final style = (_isInStyles && _currentStyleId != _minusOne)
        ? _styles.putIfAbsent(_currentStyleId, _StyleDraft.new)
        : null;
    if (shape == null && style == null) return;
    try {
      late final int charCount;
      late final int fontID;
      VsdxColor? textColor;
      var bold = false;
      var italic = false;
      var underline = false;
      var smallCaps = false;
      var allCaps = false;
      var initCaps = false;
      var superscript = false;
      var subscript = false;
      var doubleUnderline = false;
      var strikethrough = false;
      var doubleStrikethrough = false;
      var fontScale = 1.0;
      double? fontSizeInches;
      if (_version == 5) {
        // Algorithm reference: libvisio VSD5Parser::readCharIX.
        charCount = input.readU16();
        fontID = input.readU16();
        textColor = _colourFromIndex(input.readU8());
        var fontMod = input.readU8();
        bold = (fontMod & 1) != 0;
        italic = (fontMod & 2) != 0;
        underline = (fontMod & 4) != 0;
        smallCaps = (fontMod & 8) != 0;
        fontMod = input.readU8();
        allCaps = (fontMod & 1) != 0;
        initCaps = (fontMod & 2) != 0;
        fontMod = input.readU8();
        superscript = (fontMod & 1) != 0;
        subscript = (fontMod & 2) != 0;
        fontScale = input.readU16() / 10000.0;
        input.skip(2);
        fontSizeInches = input.readF64();
        // VSD5: trailing strike flags are present in the stream but unused
        // by libvisio (`#if 0`); skip when available.
      } else {
        // Algorithm reference: libvisio VSDParser::readCharIX.
        charCount = input.readU32();
        fontID = input.readU16();
        input.skip(1);
        final r = input.readU8();
        final g = input.readU8();
        final b = input.readU8();
        final a = input.readU8();
        textColor = VsdxColor.argb(a == 0 ? 255 : a, r, g, b);
        var fontMod = input.readU8();
        bold = (fontMod & 1) != 0;
        italic = (fontMod & 2) != 0;
        underline = (fontMod & 4) != 0;
        smallCaps = (fontMod & 8) != 0;
        fontMod = input.readU8();
        allCaps = (fontMod & 1) != 0;
        initCaps = (fontMod & 2) != 0;
        fontMod = input.readU8();
        superscript = (fontMod & 1) != 0;
        subscript = (fontMod & 2) != 0;
        fontScale = input.readU16() / 10000.0;
        input.skip(2);
        fontSizeInches = input.readF64();
        fontMod = input.readU8();
        doubleUnderline = (fontMod & 1) != 0;
        strikethrough = (fontMod & 4) != 0;
        doubleStrikethrough = (fontMod & 0x20) != 0;
      }
      final textCase = allCaps
          ? VsdxTextCase.allCaps
          : (initCaps ? VsdxTextCase.initialCaps : VsdxTextCase.normal);
      final textPosition = superscript
          ? VsdxTextPosition.superscript
          : (subscript
              ? VsdxTextPosition.subscript
              : VsdxTextPosition.normal);
      final family = _fonts[fontID];
      void apply(dynamic t) {
        if (family != null) t.fontFamily ??= family;
        if (textColor != null) t.textColor = textColor;
        t.bold = bold;
        t.italic = italic;
        t.underline = underline;
        t.smallCaps = smallCaps;
        t.textCase = textCase;
        t.textPosition = textPosition;
        t.strikethrough = strikethrough;
        t.doubleUnderline = doubleUnderline;
        t.doubleStrikethrough = doubleStrikethrough;
        t.fontScale = fontScale;
        t.fontSizeInches = fontSizeInches;
        if (t is _StyleDraft) t.hasCharStyle = true;
      }
      if (shape != null) {
        apply(shape);
        shape.charRuns.add(_CharRunDraft()
          ..charCount = charCount
          ..fontFamily = family
          ..fontSizeInches = fontSizeInches
          ..textColor = textColor
          ..bold = bold
          ..italic = italic
          ..underline = underline
          ..smallCaps = smallCaps
          ..textCase = textCase
          ..textPosition = textPosition
          ..strikethrough = strikethrough
          ..doubleUnderline = doubleUnderline
          ..doubleStrikethrough = doubleStrikethrough
          ..fontScale = fontScale);
      }
      if (style != null) apply(style);
    } catch (_) {}
  }

  void _readParaIx(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readParaIX / VSD5Parser::readParaIX.
    final shape = (!_isInStyles) ? _shape : null;
    final style = (_isInStyles && _currentStyleId != _minusOne)
        ? _styles.putIfAbsent(_currentStyleId, _StyleDraft.new)
        : null;
    if (shape == null && style == null) return;
    try {
      final start = input.offset;
      final charCount =
          _version == 5 ? input.readU16() : input.readU32();
      input.skip(1);
      final indFirst = input.readF64();
      input.skip(1);
      final indLeft = input.readF64();
      input.skip(1);
      final indRight = input.readF64();
      input.skip(1);
      final spLine = input.readF64();
      input.skip(1);
      final spBefore = input.readF64();
      input.skip(1);
      final spAfter = input.readF64();
      final align = input.readU8();
      final paraAlign = switch (align) {
        1 => VsdxHorzAlign.center,
        2 => VsdxHorzAlign.right,
        3 => VsdxHorzAlign.justify,
        _ => VsdxHorzAlign.left,
      };
      int? bullet;
      String? bulletFont;
      double? bulletFontSize;
      double? textPosAfterBullet;
      int? paraFlags;
      String? bulletStr;
      if (_version != 5) {
        bullet = input.readU8();
        input.skip(4);
        final fontID = input.readU16();
        if (fontID != 0) bulletFont = _fonts[fontID];
        input.skip(2);
        bulletFontSize = input.readF64();
        input.skip(1);
        textPosAfterBullet = input.readF64();
        paraFlags = input.readU32();
        input.skip(34);
        var remaining = _header.dataLength - (input.offset - start);
        while (remaining >= 4 && !input.isEnd) {
          final blockLength = input.readU32();
          if (blockLength == 0 || blockLength > remaining) break;
          final blockEnd = input.offset + blockLength - 4;
          final blockType = input.readU8();
          final blockIdx = input.readU8();
          if (blockType == 2 && blockIdx == 8 && input.remaining >= 2) {
            input.skip(1);
            final numBytes = 2 * input.readU8();
            if (numBytes > 0 && input.remaining >= numBytes) {
              bulletStr = _decodeUtf16Le(input.readBytes(numBytes));
            }
          }
          if (blockEnd > input.length) break;
          input.seek(blockEnd);
          remaining -= blockLength;
        }
      }
      void apply(dynamic t) {
        t.indFirst = indFirst;
        t.indLeft = indLeft;
        t.indRight = indRight;
        t.spLine = spLine;
        t.spBefore = spBefore;
        t.spAfter = spAfter;
        t.paraAlign = paraAlign;
        if (bullet != null) t.bullet = bullet;
        if (bulletFont != null) t.bulletFont = bulletFont;
        if (bulletFontSize != null) t.bulletFontSize = bulletFontSize;
        if (textPosAfterBullet != null) {
          t.textPosAfterBullet = textPosAfterBullet;
        }
        if (paraFlags != null) t.paraFlags = paraFlags;
        if (bulletStr != null) t.bulletStr = bulletStr;
        if (t is _StyleDraft) t.hasParaStyle = true;
      }
      if (shape != null) {
        apply(shape);
        shape.paraRuns.add(_ParaRunDraft()
          ..charCount = charCount
          ..paraAlign = paraAlign
          ..indFirst = indFirst
          ..indLeft = indLeft
          ..indRight = indRight
          ..spLine = spLine
          ..spBefore = spBefore
          ..spAfter = spAfter
          ..bullet = bullet
          ..bulletStr = bulletStr
          ..bulletFont = bulletFont
          ..bulletFontSize = bulletFontSize
          ..textPosAfterBullet = textPosAfterBullet
          ..paraFlags = paraFlags);
      }
      if (style != null) apply(style);
    } catch (_) {}
  }

  /// TabsData (libvisio `VSDParser::readTabsData`) — 0x88 / 0x96 / 0x97 / 0xb5.
  void _readTabsData(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    try {
      final numChars = _getUInt(input);
      final numStops = input.readU8();
      final draft = _TabSetDraft()
        ..id = _header.id
        ..numChars = numChars;
      for (var i = 0; i < numStops; i++) {
        input.skip(1);
        final position = input.readF64();
        final alignment = input.readU8();
        input.readU8(); // leader (not modelled)
        draft.stops.add(VsdxTabStop(
          positionInches: position,
          alignment: alignment,
        ));
      }
      s.tabRuns.add(draft);
    } catch (_) {}
  }

  void _readColours(VsdByteReader input) {
    input.skip(2);
    final numColours = input.readU8();
    input.skip(1);
    _colours.clear();
    for (var i = 0; i < numColours; i++) {
      final r = input.readU8();
      final g = input.readU8();
      final b = input.readU8();
      final a = input.readU8();
      _colours.add(VsdxColor.argb(a == 0 ? 255 : a, r, g, b));
    }
  }

  void _readStyleSheet(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readStyleSheet /
    // VSD5Parser::readStyleSheet (parent line/fill/text style ids).
    _currentStyleId = _header.id;
    final st = _styles.putIfAbsent(_header.id, _StyleDraft.new);
    try {
      if (_version == 5) {
        input.skip(10);
        st.lineParent = _getUInt(input);
        st.fillParent = _getUInt(input);
        st.textParent = _getUInt(input);
      } else {
        input.skip(0x22);
        st.lineParent = input.readU32();
        input.skip(4);
        st.fillParent = input.readU32();
        input.skip(4);
        st.textParent = input.readU32();
      }
    } catch (_) {}
  }

  void _readShapeList(VsdByteReader input) {
    if (_version == 5) {
      _handleChunkRecords(input, collectStylesOnly: false);
      return;
    }
    if (_header.trailer == 0) return;
    try {
      final subHeaderLength = input.readU32();
      var childrenListLength = input.readU32();
      input.skip(subHeaderLength);
      if (childrenListLength > input.remaining) {
        childrenListLength = input.remaining;
      }
      final count = childrenListLength ~/ 4;
      final order = <int>[];
      for (var i = 0; i < count; i++) {
        order.add(input.readU32());
      }
      if (!_isShapeStarted && _currentPage != null) {
        _currentPage!.shapeOrder.addAll(order);
      } else if (_isShapeStarted && _shape != null) {
        _shape!.childOrder.addAll(order);
      }
    } catch (_) {}
  }

  void _readShapeId(VsdByteReader input) {
    try {
      _getUInt(input);
    } catch (_) {}
  }

  VsdxColor _colourFromIndex(int idx) {
    if (idx < 0 || idx >= _colours.length) return VsdxColor.black;
    return _colours[idx];
  }

  String _decodeAnsi(Uint8List raw) {
    if (raw.isEmpty) return '';
    final out = StringBuffer();
    for (final b in raw) {
      if (b == 0) break;
      if (b == 0x0d || b == 0x0e) {
        out.writeCharCode(0x0a);
      } else {
        out.writeCharCode(b);
      }
    }
    return out.toString();
  }

  String _decodeUtf16Le(Uint8List raw) {
    if (raw.isEmpty) return '';
    final units = <int>[];
    for (var i = 0; i + 1 < raw.length; i += 2) {
      final cu = raw[i] | (raw[i + 1] << 8);
      if (cu == 0) break;
      if (cu == 0x0d || cu == 0x0e) {
        units.add(0x0a);
      } else {
        units.add(cu);
      }
    }
    return String.fromCharCodes(units);
  }

  VsdxDocument _buildDocument() {
    if (_pages.isEmpty) {
      return VsdxDocument(
        pages: [
          VsdxPage(
            id: 0,
            name: 'Page-1',
            widthInches: 8.5,
            heightInches: 11.0,
            shapes: const [],
          ),
        ],
        applicationName: 'Editor for Visio Diagrams',
      );
    }
    final images = <String, VsdxImage>{};
    var imageSeq = 0;
    final pages = <VsdxPage>[];
    for (var i = 0; i < _pages.length; i++) {
      final p = _pages[i];
      final scale = (p.scale > 0 && p.scale.isFinite) ? p.scale : 1.0;
      // Apply drawing scale (libvisio: page size and coords *= m_scale).
      for (final s in p.shapes) {
        _applyScale(s, scale);
        _registerForeignImage(s, images, () => ++imageSeq);
      }
      pages.add(
        VsdxPage(
          id: i == 0 ? 0 : p.id,
          name: p.name,
          widthInches: p.width * scale,
          heightInches: p.height * scale,
          shapes: _assembleShapes(p.shapes, p.shapeOrder),
          layers: List<VsdxLayer>.from(p.layers),
        ),
      );
    }
    return VsdxDocument(
      pages: pages,
      images: images.isEmpty ? ImageRegistry.empty : ImageRegistry(images),
      applicationName: 'Editor for Visio Diagrams',
    );
  }

  void _applyScale(_ShapeDraft d, double s) {
    if (s == 1.0) return;
    d.pinX *= s;
    d.pinY *= s;
    d.width *= s;
    d.height *= s;
    d.locPinX *= s;
    d.locPinY *= s;
    if (d.beginX != null) d.beginX = d.beginX! * s;
    if (d.beginY != null) d.beginY = d.beginY! * s;
    if (d.endX != null) d.endX = d.endX! * s;
    if (d.endY != null) d.endY = d.endY! * s;
    if (d.fontSizeInches != null) d.fontSizeInches = d.fontSizeInches! * s;
    if (d.txtPinX != null) d.txtPinX = d.txtPinX! * s;
    if (d.txtPinY != null) d.txtPinY = d.txtPinY! * s;
    if (d.txtWidth != null) d.txtWidth = d.txtWidth! * s;
    if (d.txtHeight != null) d.txtHeight = d.txtHeight! * s;
    if (d.txtLocPinX != null) d.txtLocPinX = d.txtLocPinX! * s;
    if (d.txtLocPinY != null) d.txtLocPinY = d.txtLocPinY! * s;
    for (final g in d.geometries) {
      final scaled = <int, VsdxPathCommand>{};
      for (final e in g.byId.entries) {
        scaled[e.key] = _scaleCommand(e.value, s);
      }
      g.byId
        ..clear()
        ..addAll(scaled);
    }
  }

  VsdxPathCommand _scaleCommand(VsdxPathCommand c, double s) {
    return switch (c) {
      MoveTo(:final x, :final y) => MoveTo(x * s, y * s),
      LineTo(:final x, :final y) => LineTo(x * s, y * s),
      ArcTo(:final x, :final y, :final bow) =>
        ArcTo(x: x * s, y: y * s, bow: bow * s),
      EllipticalArcTo(
        :final x,
        :final y,
        :final controlX,
        :final controlY,
        :final angle,
        :final eccentricity
      ) =>
        EllipticalArcTo(
          x: x * s,
          y: y * s,
          controlX: controlX * s,
          controlY: controlY * s,
          angle: angle,
          eccentricity: eccentricity,
        ),
      EllipseCmd(:final cx, :final cy, :final aX, :final aY, :final bX, :final bY) =>
        EllipseCmd(
          cx: cx * s,
          cy: cy * s,
          aX: aX * s,
          aY: aY * s,
          bX: bX * s,
          bY: bY * s,
        ),
      PolylineTo(:final x, :final y, :final vertices, :final relative) =>
        relative
            ? c
            : PolylineTo(
                x: x * s,
                y: y * s,
                vertices: [
                  for (final v in vertices) Offset2D(v.x * s, v.y * s),
                ],
              ),
      InfiniteLineCmd(:final x, :final y, :final a, :final b, :final relative) =>
        relative
            ? c
            : InfiniteLineCmd(x: x * s, y: y * s, a: a * s, b: b * s),
      SplineStart(
        :final x,
        :final y,
        :final a,
        :final b,
        :final c,
        :final degree,
        :final relative,
      ) =>
        relative
            ? SplineStart(
                x: x,
                y: y,
                a: a,
                b: b,
                c: c,
                degree: degree,
                relative: true,
              )
            : SplineStart(
                x: x * s,
                y: y * s,
                a: a,
                b: b,
                c: c,
                degree: degree,
              ),
      SplineKnot(:final x, :final y, :final knot, :final relative) =>
        relative
            ? c
            : SplineKnot(x: x * s, y: y * s, knot: knot),
      NurbsTo(
        :final x,
        :final y,
        :final controlPoints,
        :final weights,
        :final knots,
        :final degree,
        :final relative
      ) =>
        relative
            ? c
            : NurbsTo(
                x: x * s,
                y: y * s,
                controlPoints: [
                  for (final p in controlPoints) Offset2D(p.x * s, p.y * s),
                ],
                weights: weights,
                knots: knots,
                degree: degree,
              ),
      _ => c,
    };
  }

  void _registerForeignImage(
    _ShapeDraft d,
    Map<String, VsdxImage> images,
    int Function() nextSeq,
  ) {
    final raw = d.foreignBytes;
    if (raw == null || raw.isEmpty) return;
    final decoded = _decodeForeignImage(raw, d.foreignType, d.foreignFormat);
    if (decoded == null) return;
    final seq = nextSeq();
    final part = '/visio/media/image$seq.${decoded.ext}';
    images[part] = VsdxImage(
      partName: part,
      bytes: decoded.bytes,
      mimeType: decoded.mime,
    );
    _foreignPartByShapeId[d.id] = part;
    _foreignTypeByShapeId[d.id] = decoded.foreignType;
  }

  final _foreignPartByShapeId = <int, String>{};
  final _foreignTypeByShapeId = <int, String>{};

  /// Convert Visio ForeignData payload using type/format (libvisio
  /// `VSDContentCollector::_handleForeignData`). OLE still skipped.
  ({Uint8List bytes, String ext, String mime, String foreignType})?
      _decodeForeignImage(Uint8List raw, int foreignType, int foreignFormat) {
    if (foreignType == 1) {
      switch (foreignFormat) {
        case 0:
        case 255:
          final bmp = _dibToBmp(raw);
          return (
            bytes: bmp,
            ext: 'bmp',
            mime: 'image/bmp',
            foreignType: 'Bitmap',
          );
        case 1:
          return (
            bytes: raw,
            ext: 'jpg',
            mime: 'image/jpeg',
            foreignType: 'Bitmap',
          );
        case 2:
          return (
            bytes: raw,
            ext: 'gif',
            mime: 'image/gif',
            foreignType: 'Bitmap',
          );
        case 3:
          return (
            bytes: raw,
            ext: 'tif',
            mime: 'image/tiff',
            foreignType: 'Bitmap',
          );
        case 4:
          return (
            bytes: raw,
            ext: 'png',
            mime: 'image/png',
            foreignType: 'Bitmap',
          );
      }
    }
    // EMF / WMF (libvisio foreignType 0 or 4) — keep bytes for vsdx round-trip;
    // Flutter cannot paint them natively (renderer shows a placeholder).
    if (foreignType == 0 || foreignType == 4) {
      final isEmf = raw.length > 0x2B &&
          raw[0x28] == 0x20 &&
          raw[0x29] == 0x45 &&
          raw[0x2A] == 0x4D &&
          raw[0x2B] == 0x46;
      if (isEmf) {
        return (
          bytes: raw,
          ext: 'emf',
          mime: 'image/x-emf',
          foreignType: 'EnhMetaFile',
        );
      }
      return (
        bytes: raw,
        ext: 'wmf',
        mime: 'image/x-wmf',
        foreignType: 'MetaFile',
      );
    }
    // Already a self-describing raster (or type unset) — sniff magic.
    final sniff = _sniffImage(raw);
    if (sniff != null) return sniff;
    // Sniff EMF/WMF even when type cell is missing.
    if (raw.length > 0x2B &&
        raw[0x28] == 0x20 &&
        raw[0x29] == 0x45 &&
        raw[0x2A] == 0x4D &&
        raw[0x2B] == 0x46) {
      return (
        bytes: raw,
        ext: 'emf',
        mime: 'image/x-emf',
        foreignType: 'EnhMetaFile',
      );
    }
    if (raw.length >= 4 && raw[0] == 0xd7 && raw[1] == 0xcd) {
      return (
        bytes: raw,
        ext: 'wmf',
        mime: 'image/x-wmf',
        foreignType: 'MetaFile',
      );
    }
    // DIB without BM header (common when format cell missing).
    if (raw.length >= 40) {
      final headerSize = raw[0] |
          (raw[1] << 8) |
          (raw[2] << 16) |
          (raw[3] << 24);
      if (headerSize == 40 || headerSize == 108 || headerSize == 124) {
        final bmp = _dibToBmp(raw);
        return (
          bytes: bmp,
          ext: 'bmp',
          mime: 'image/bmp',
          foreignType: 'Bitmap',
        );
      }
    }
    return null; // OLE / unknown
  }

  /// Prepend BITMAPFILEHEADER to a DIB (BITMAPINFOHEADER + pixels).
  /// Algorithm reference: libvisio `computeBMPDataOffset` + `_handleForeignData`.
  Uint8List _dibToBmp(Uint8List dib) {
    final dataOff = _bmpDataOffset(dib);
    final total = dib.length + 14;
    final out = Uint8List(total);
    out[0] = 0x42; // 'B'
    out[1] = 0x4D; // 'M'
    out[2] = total & 0xff;
    out[3] = (total >> 8) & 0xff;
    out[4] = (total >> 16) & 0xff;
    out[5] = (total >> 24) & 0xff;
    // reserved 6..9 = 0
    out[10] = dataOff & 0xff;
    out[11] = (dataOff >> 8) & 0xff;
    out[12] = (dataOff >> 16) & 0xff;
    out[13] = (dataOff >> 24) & 0xff;
    out.setRange(14, total, dib);
    return out;
  }

  int _bmpDataOffset(Uint8List dib) {
    if (dib.length < 4) return 14 + 40;
    var headerSize = dib[0] | (dib[1] << 8) | (dib[2] << 16) | (dib[3] << 24);
    if (headerSize > dib.length) headerSize = 40;
    var off = headerSize;
    var bpp = 0;
    if (dib.length >= 16) {
      bpp = dib[14] | (dib[15] << 8);
    }
    if (bpp > 32) bpp = 32;
    const allowed = [1, 4, 8, 16, 24, 32];
    for (final a in allowed) {
      if (bpp <= a) {
        bpp = a;
        break;
      }
    }
    var paletteColors = 0;
    if (dib.length >= 36) {
      paletteColors =
          dib[32] | (dib[33] << 8) | (dib[34] << 16) | (dib[35] << 24);
    }
    if (bpp < 16 && paletteColors == 0) {
      paletteColors = 1 << bpp;
    }
    if (paletteColors > 0 && paletteColors < (dib.length - off) / 4) {
      off += 4 * paletteColors;
    }
    return off + 14; // include BITMAPFILEHEADER
  }

  ({Uint8List bytes, String ext, String mime, String foreignType})?
      _sniffImage(Uint8List b) {
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return (
        bytes: b,
        ext: 'png',
        mime: 'image/png',
        foreignType: 'Bitmap',
      );
    }
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return (
        bytes: b,
        ext: 'jpg',
        mime: 'image/jpeg',
        foreignType: 'Bitmap',
      );
    }
    if (b.length >= 6 &&
        b[0] == 0x47 &&
        b[1] == 0x49 &&
        b[2] == 0x46) {
      return (
        bytes: b,
        ext: 'gif',
        mime: 'image/gif',
        foreignType: 'Bitmap',
      );
    }
    if (b.length >= 2 && b[0] == 0x42 && b[1] == 0x4D) {
      return (
        bytes: b,
        ext: 'bmp',
        mime: 'image/bmp',
        foreignType: 'Bitmap',
      );
    }
    return null;
  }

  List<VsdxShape> _assembleShapes(
    List<_ShapeDraft> drafts, [
    List<int> shapeOrder = const [],
  ]) {
    final byId = <int, _ShapeDraft>{for (final d in drafts) d.id: d};
    final childrenOf = <int, List<int>>{};
    final roots = <int>[];
    for (final d in drafts) {
      final parent = d.parent;
      if (parent == 0 || parent == _minusOne || !byId.containsKey(parent)) {
        roots.add(d.id);
      } else {
        childrenOf.putIfAbsent(parent, () => <int>[]).add(d.id);
      }
    }

    List<int> orderIds(List<int> ids, List<int> preferred) {
      if (preferred.isEmpty || ids.length <= 1) return ids;
      final remaining = ids.toSet();
      final out = <int>[];
      for (final id in preferred) {
        if (remaining.remove(id)) out.add(id);
      }
      // Append any shapes missing from the order trailer (stable).
      for (final id in ids) {
        if (remaining.remove(id)) out.add(id);
      }
      return out;
    }

    final orderedRoots = orderIds(roots, shapeOrder);

    VsdxShape build(int id) {
      final d = byId[id]!;
      final kids = orderIds(childrenOf[id] ?? const <int>[], d.childOrder);
      return _toShape(d, kids.map(build).toList());
    }

    return orderedRoots.map(build).toList();
  }

  VsdxShape _toShape(_ShapeDraft d, List<VsdxShape> children) {
    final geoms = <VsdxGeometry>[];
    for (var i = 0; i < d.geometries.length; i++) {
      final g = d.geometries[i];
      final cmds = <VsdxPathCommand>[];
      if (g.order.isNotEmpty) {
        for (final id in g.order) {
          final c = g.byId[id];
          if (c != null) cmds.add(c);
        }
      } else {
        // Insertion order by ascending id for stability.
        final ids = g.byId.keys.toList()..sort();
        for (final id in ids) {
          cmds.add(g.byId[id]!);
        }
      }
      if (cmds.isEmpty) continue;
      geoms.add(
        VsdxGeometry(
          commands: cmds,
          noFill: g.noFill,
          noLine: g.noLine,
          noShow: g.noShow,
          ix: i,
        ),
      );
    }

    VsdxRichText rich = VsdxRichText.empty;
    final rawText = d.text;
    final textBlock = VsdxTextBlock.defaults.copyWith(
      hideText: d.hideText,
      pinXInches: d.txtPinX,
      pinYInches: d.txtPinY,
      widthInches: d.txtWidth,
      heightInches: d.txtHeight,
      locPinXInches: d.txtLocPinX,
      locPinYInches: d.txtLocPinY,
      angleRad: d.txtAngle,
      marginLeftInches: d.marginLeft,
      marginRightInches: d.marginRight,
      marginTopInches: d.marginTop,
      marginBottomInches: d.marginBottom,
      verticalAlign: d.verticalAlign,
      backgroundColor: d.textBgColor,
      defaultTabStopInches: d.defaultTabStop,
      textDirection: d.textDirection,
    );
    final tabSets = [
      for (final t in d.tabRuns)
        VsdxTabSet(ix: t.id, stops: List<VsdxTabStop>.from(t.stops)),
    ];
    String? text;
    if (rawText != null && rawText.trim().isNotEmpty) {
      final built = _buildRichText(d, rawText, textBlock, tabSets);
      rich = built.rich;
      text = built.plain;
    } else if (d.hideText ||
        d.txtPinX != null ||
        d.txtWidth != null ||
        tabSets.isNotEmpty) {
      rich = VsdxRichText(
        runs: const [],
        textBlock: textBlock,
        tabSets: tabSets,
      );
    }

    return VsdxShape(
      id: d.id,
      name: d.shapeName ?? 'Sheet.${d.id}',
      pinX: d.pinX,
      pinY: d.pinY,
      width: d.width <= 0 ? 1.0 : d.width,
      height: d.height <= 0 ? 1.0 : d.height,
      locPinXInches: d.locPinX,
      locPinYInches: d.locPinY,
      angleRad: d.angle,
      flipX: d.flipX,
      flipY: d.flipY,
      text: text,
      richText: rich,
      geometries: geoms,
      fill: d.fill ?? VsdxFill.defaultFill,
      line: d.line ?? VsdxLine.defaultLine,
      is1D: d.is1D,
      beginX: d.beginX,
      beginY: d.beginY,
      endX: d.endX,
      endY: d.endY,
      imagePartName: _foreignPartByShapeId[d.id],
      foreignType: _foreignTypeByShapeId[d.id],
      layerMemberIds: List<int>.from(d.layerMemberIds),
      children: children,
    );
  }

  /// Split shape text into runs by CharIX/ParaIX charCounts (libvisio
  /// `VSDContentCollector` text walk). Field markers expand after the split
  /// so counts stay aligned with the binary stream.
  ({VsdxRichText rich, String plain}) _buildRichText(
    _ShapeDraft d,
    String rawText,
    VsdxTextBlock textBlock,
    List<VsdxTabSet> tabSets,
  ) {
    final chars = d.charRuns;
    final paras = d.paraRuns;
    final tabs = d.tabRuns;

    VsdxCharStyle charStyleOf(_CharRunDraft? c) {
      final bold = c?.bold ?? d.bold;
      final italic = c?.italic ?? d.italic;
      final smallCaps = c?.smallCaps ?? d.smallCaps;
      return VsdxCharStyle(
        fontFamily: c?.fontFamily ?? d.fontFamily,
        fontSizeInches: c?.fontSizeInches ?? d.fontSizeInches ?? (12.0 / 72.0),
        color: c?.textColor ?? d.textColor,
        style: VsdxFontStyle(
          bold: bold,
          italic: italic,
          smallCaps: smallCaps,
        ),
        underline: c?.underline ?? d.underline,
        textCase: c?.textCase ?? d.textCase,
        position: c?.textPosition ?? d.textPosition,
        strikethrough: c?.strikethrough ?? d.strikethrough,
        doubleUnderline: c?.doubleUnderline ?? d.doubleUnderline,
        doubleStrikethrough: c?.doubleStrikethrough ?? d.doubleStrikethrough,
        fontScale: c?.fontScale ?? d.fontScale,
      );
    }

    VsdxParaStyle paraStyleOf(_ParaRunDraft? p) {
      var lineSpacing = 1.0;
      var lineSpacingAbs = 0.0;
      var lineSpacingSolid = false;
      final sp = p?.spLine ?? d.spLine;
      if (sp != null) {
        if (sp < 0) {
          lineSpacing = -sp;
        } else if (sp == 0) {
          lineSpacingSolid = true;
        } else {
          lineSpacingAbs = sp;
        }
      }
      return VsdxParaStyle(
        horizontalAlign: p?.paraAlign ?? d.paraAlign ?? VsdxHorzAlign.left,
        indentFirstInches: p?.indFirst ?? d.indFirst ?? 0.0,
        indentLeftInches: p?.indLeft ?? d.indLeft ?? 0.0,
        indentRightInches: p?.indRight ?? d.indRight ?? 0.0,
        spaceBeforeInches: p?.spBefore ?? d.spBefore ?? 0.0,
        spaceAfterInches: p?.spAfter ?? d.spAfter ?? 0.0,
        lineSpacing: lineSpacing,
        lineSpacingAbsoluteInches: lineSpacingAbs,
        lineSpacingSolid: lineSpacingSolid,
        bullet: p?.bullet ?? d.bullet ?? 0,
        bulletStr: p?.bulletStr ?? d.bulletStr,
        bulletFont: p?.bulletFont ?? d.bulletFont,
        bulletFontSizeInches: p?.bulletFontSize ?? d.bulletFontSize,
        textPosAfterBulletInches:
            p?.textPosAfterBullet ?? d.textPosAfterBullet ?? 0.0,
        flags: p?.paraFlags ?? d.paraFlags ?? 0,
      );
    }

    // Single-run fast path when there is at most one CharIX/ParaIX.
    final multi = chars.length > 1 || paras.length > 1;
    if (!multi) {
      final expanded = d.fieldDisplays.isEmpty
          ? rawText
          : _expandFieldMarkers(rawText, d.fieldDisplays);
      final plain = expanded.trim();
      return (
        rich: VsdxRichText(
          runs: [
            VsdxTextRun(
              text: plain,
              charStyle: charStyleOf(chars.isEmpty ? null : chars.first),
              paraStyle: paraStyleOf(paras.isEmpty ? null : paras.first),
            ),
          ],
          textBlock: textBlock,
          tabSets: tabSets,
        ),
        plain: plain,
      );
    }

    var ci = 0;
    var pi = 0;
    var ti = 0;
    var charLeft = chars.isEmpty ? rawText.length : chars.first.charCount;
    var paraLeft = paras.isEmpty ? rawText.length : paras.first.charCount;
    var tabLeft = tabs.isEmpty ? rawText.length : tabs.first.numChars;
    if (charLeft == 0 && chars.isNotEmpty) charLeft = rawText.length;
    if (paraLeft == 0 && paras.isNotEmpty) paraLeft = rawText.length;
    if (tabLeft == 0 && tabs.isNotEmpty) tabLeft = rawText.length;

    final runs = <VsdxTextRun>[];
    final buf = StringBuffer();
    final tabIndices = <int>[];
    var fieldIdx = 0;
    var prevCi = -1;
    var prevPi = -1;
    VsdxCharStyle curChar = charStyleOf(null);
    VsdxParaStyle curPara = paraStyleOf(null);

    void flush() {
      if (buf.isEmpty) return;
      runs.add(VsdxTextRun(
        text: buf.toString(),
        charStyle: curChar,
        paraStyle: curPara,
        tabIndices: List<int>.from(tabIndices),
      ));
      buf.clear();
      tabIndices.clear();
    }

    for (var i = 0; i < rawText.length; i++) {
      if (ci != prevCi || pi != prevPi) {
        flush();
        curChar = charStyleOf(chars.isEmpty ? null : chars[ci]);
        curPara = paraStyleOf(paras.isEmpty ? null : paras[pi]);
        prevCi = ci;
        prevPi = pi;
      }

      final cu = rawText.codeUnitAt(i);
      if (cu == 0xFFFC || cu == 0x1E) {
        if (fieldIdx < d.fieldDisplays.length) {
          buf.write(d.fieldDisplays[fieldIdx++]);
        }
      } else {
        buf.writeCharCode(cu);
        if (cu == 0x09 && tabs.isNotEmpty) {
          tabIndices.add(tabs[ti].id);
        }
      }

      if (charLeft > 0) charLeft--;
      if (charLeft == 0 && ci + 1 < chars.length) {
        ci++;
        charLeft = chars[ci].charCount;
        if (charLeft == 0) charLeft = rawText.length - i;
      }
      if (paraLeft > 0) paraLeft--;
      if (paraLeft == 0 && pi + 1 < paras.length) {
        pi++;
        paraLeft = paras[pi].charCount;
        if (paraLeft == 0) paraLeft = rawText.length - i;
      }
      if (tabLeft > 0) tabLeft--;
      if (tabLeft == 0 && ti + 1 < tabs.length) {
        ti++;
        tabLeft = tabs[ti].numChars;
        if (tabLeft == 0) tabLeft = rawText.length - i;
      }
    }
    flush();

    if (runs.isEmpty) {
      final plain = rawText.trim();
      return (
        rich: VsdxRichText(
          runs: [
            VsdxTextRun(
              text: plain,
              charStyle: charStyleOf(null),
              paraStyle: paraStyleOf(null),
            ),
          ],
          textBlock: textBlock,
          tabSets: tabSets,
        ),
        plain: plain,
      );
    }

    final plain = runs.map((r) => r.text).join().trim();
    return (
      rich: VsdxRichText(
        runs: runs,
        textBlock: textBlock,
        tabSets: tabSets,
      ),
      plain: plain,
    );
  }
}
