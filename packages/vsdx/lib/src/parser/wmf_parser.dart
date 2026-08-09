/// Windows Metafile (WMF) → [MetafileDrawing] vector replay.
///
/// Covers the GDI records Visio / LibreOffice thumbnails and ForeignData
/// typically emit: window mapping, pens/brushes/fonts, polygon/polyline,
/// rectangle/ellipse, and ExtTextOut. LibreOffice-style `META_ESCAPE` `WMFC`
/// chunks are reassembled by [extractWmfEmbeddedEmf]; other private escapes
/// are skipped so the native WMF drawing stream after them can paint.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'emf_vector_parser.dart';
import 'metafile_drawing.dart';
import 'vsd/vsd_text_codec.dart';

const int _placeableKey = 0x9AC6CDD7;

const int _metaSetWindowOrg = 0x020B;
const int _metaSetWindowExt = 0x020C;
const int _metaSetBkMode = 0x0102;
const int _metaSetMapMode = 0x0103;
const int _metaSetPolyFillMode = 0x0106;
const int _metaSetBkColor = 0x0201;
const int _metaSetTextColor = 0x0209;
const int _metaSetTextJustification = 0x020A;
const int _metaSetTextAlign = 0x012E;
const int _metaSaveDc = 0x001E;
const int _metaRestoreDc = 0x0127;
const int _metaExcludeClipRect = 0x0415;
const int _metaIntersectClipRect = 0x0416;
const int _metaCreatePenIndirect = 0x02FA;
const int _metaCreateBrushIndirect = 0x02FC;
const int _metaCreateFontIndirect = 0x02FB;
const int _metaSelectObject = 0x012D;
const int _metaDeleteObject = 0x01F0;
const int _metaPolygon = 0x0324;
const int _metaPolyline = 0x0325;
const int _metaPolyPolygon = 0x0538;
const int _metaArc = 0x0817;
const int _metaRectangle = 0x041B;
const int _metaRoundRect = 0x061C;
const int _metaEllipse = 0x0418;
const int _metaPie = 0x081A;
const int _metaChord = 0x0830;
const int _metaMoveTo = 0x0214;
const int _metaLineTo = 0x0213;
const int _metaPolyBezier = 0x1008;
const int _metaExtTextOut = 0x0A32;
const int _metaTextOut = 0x0521;
const int _metaEscape = 0x0626;
const int _metaEof = 0x0000;
const int _mfCommentEscape = 15;
const int _wmfcCommentIdentifier = 0x43464D57;

/// Whether [bytes] start with a valid placeable or standard WMF header.
bool looksLikeWmf(Uint8List bytes) {
  if (bytes.length < 18) return false;
  final bd = ByteData.sublistView(bytes);
  var pos = 0;
  if (bytes.length >= 22 && bd.getUint32(0, Endian.little) == _placeableKey) {
    pos = 22;
  }
  if (pos + 18 > bytes.length) return false;
  final type = bd.getUint16(pos, Endian.little);
  final headerWords = bd.getUint16(pos + 2, Endian.little);
  final version = bd.getUint16(pos + 4, Endian.little);
  return (type == 1 || type == 2) &&
      headerWords >= 9 &&
      pos + headerWords * 2 <= bytes.length &&
      (version == 0x0100 || version == 0x0300);
}

/// Reassemble an EMF embedded in WMF `META_ESCAPE/MFCOMMENT` records.
///
/// Microsoft Office can split a complete enhanced metafile across several
/// `WMFC` comments. LibreOffice validates the chunk count and declared total,
/// concatenates the payloads, and prefers that EMF over the fallback WMF
/// records. MathType and other private escapes intentionally return `null`.
Uint8List? extractWmfEmbeddedEmf(Uint8List bytes) {
  if (!looksLikeWmf(bytes)) return null;
  final bd = ByteData.sublistView(bytes);
  var pos = 0;
  if (bytes.length >= 22 && bd.getUint32(0, Endian.little) == _placeableKey) {
    pos = 22;
  }
  final headerWords = bd.getUint16(pos + 2, Endian.little);
  pos += headerWords * 2;

  int? expectedChunks;
  int? expectedSize;
  var chunksRead = 0;
  var payload = BytesBuilder(copy: false);

  void reset() {
    expectedChunks = null;
    expectedSize = null;
    chunksRead = 0;
    payload = BytesBuilder(copy: false);
  }

  while (pos + 6 <= bytes.length) {
    final sizeWords = bd.getUint32(pos, Endian.little);
    final function = bd.getUint16(pos + 4, Endian.little);
    if (sizeWords < 3) break;
    final recordSize = sizeWords * 2;
    final recordEnd = pos + recordSize;
    if (recordEnd > bytes.length) break;
    if (function == _metaEof) break;
    if (function == _metaEscape && pos + 10 <= recordEnd) {
      final mode = bd.getUint16(pos + 6, Endian.little);
      final dataLength = bd.getUint16(pos + 8, Endian.little);
      final dataStart = pos + 10;
      if (mode == _mfCommentEscape &&
          dataLength >= 34 &&
          dataStart + dataLength <= recordEnd &&
          sizeWords == ((dataLength + 1) >> 1) + 5 &&
          bd.getUint32(dataStart, Endian.little) == _wmfcCommentIdentifier) {
        final commentType = bd.getUint32(dataStart + 4, Endian.little);
        final commentVersion = bd.getUint32(dataStart + 8, Endian.little);
        final chunkCount = bd.getUint32(dataStart + 18, Endian.little);
        final chunkSize = bd.getUint32(dataStart + 22, Endian.little);
        final totalSize = bd.getUint32(dataStart + 30, Endian.little);
        if (commentType != 1 ||
            commentVersion != 0x00010000 ||
            chunkCount == 0 ||
            chunkSize > dataLength - 34 ||
            totalSize == 0 ||
            totalSize > bytes.length) {
          reset();
        } else if (expectedChunks != null &&
            (expectedChunks != chunkCount || expectedSize != totalSize)) {
          reset();
        } else {
          expectedChunks ??= chunkCount;
          expectedSize ??= totalSize;
          payload.add(bytes.sublist(
            dataStart + 34,
            dataStart + 34 + chunkSize,
          ));
          chunksRead++;
          if (chunksRead == expectedChunks) {
            final emf = Uint8List.fromList(payload.takeBytes());
            if (emf.length == expectedSize && looksLikeEmf(emf)) return emf;
            reset();
          }
        }
      }
    }
    pos = recordEnd;
  }
  return null;
}

/// Parse placeable or standard WMF bytes into a paint list, or `null`.
MetafileDrawing? parseWmfDrawing(Uint8List bytes) {
  if (bytes.length < 18) return null;
  final bd = ByteData.sublistView(bytes);
  var pos = 0;
  double minX = 0, minY = 0, maxX = 0, maxY = 0;
  var haveBounds = false;

  if (bd.getUint32(0, Endian.little) == _placeableKey) {
    if (bytes.length < 40) return null;
    final left = bd.getInt16(6, Endian.little).toDouble();
    final top = bd.getInt16(8, Endian.little).toDouble();
    final right = bd.getInt16(10, Endian.little).toDouble();
    final bottom = bd.getInt16(12, Endian.little).toDouble();
    minX = math.min(left, right);
    maxX = math.max(left, right);
    minY = math.min(top, bottom);
    maxY = math.max(top, bottom);
    haveBounds = maxX > minX && maxY > minY;
    pos = 22;
  }

  if (pos + 18 > bytes.length) return null;
  final mtType = bd.getUint16(pos, Endian.little);
  final mtHeaderSize = bd.getUint16(pos + 2, Endian.little);
  if (mtType != 1 && mtType != 2) return null;
  if (mtHeaderSize < 9) return null;
  pos += mtHeaderSize * 2;

  final objects = <_GdiObject?>[];
  var penColor = 0xFF000000;
  var penWidth = 1.0;
  var penStyle = 0;
  List<double>? penDashPattern;
  var brushColor = 0xFFFFFFFF;
  var brushStyle = 1; // BS_NULL
  var brushHatch = 0;
  var textColor = 0xFF000000;
  var backgroundMode = 1; // TRANSPARENT
  var backgroundColor = 0xFFFFFFFF;
  var textAlign = 0;
  var mapMode = 1; // MM_TEXT
  var polyFillMode = 1; // ALTERNATE
  var textBreakExtra = 0;
  var textBreakCount = 0;
  String? fontFace;
  var fontHeight = 12.0;
  var fontWeight = 400;
  var fontItalic = false;
  var fontUnderline = false;
  var fontStrikeThrough = false;
  var fontEscapementDegrees = 0.0;
  var fontEncoding = VsdLegacyTextEncoding.ansi;
  double? winOrgX, winOrgY, winExtX, winExtY;
  double? curX, curY;
  final ops = <Object>[];
  final savedStates = <_WmfDcState>[];

  _WmfDcState captureState() => _WmfDcState(
        penColor: penColor,
        penWidth: penWidth,
        penStyle: penStyle,
        penDashPattern: penDashPattern,
        brushColor: brushColor,
        brushStyle: brushStyle,
        brushHatch: brushHatch,
        textColor: textColor,
        backgroundMode: backgroundMode,
        backgroundColor: backgroundColor,
        textAlign: textAlign,
        mapMode: mapMode,
        polyFillMode: polyFillMode,
        textBreakExtra: textBreakExtra,
        textBreakCount: textBreakCount,
        fontFace: fontFace,
        fontHeight: fontHeight,
        fontWeight: fontWeight,
        fontItalic: fontItalic,
        fontUnderline: fontUnderline,
        fontStrikeThrough: fontStrikeThrough,
        fontEscapementDegrees: fontEscapementDegrees,
        fontEncoding: fontEncoding,
        winOrgX: winOrgX,
        winOrgY: winOrgY,
        winExtX: winExtX,
        winExtY: winExtY,
        curX: curX,
        curY: curY,
      );

  int restoreState(int savedDc) {
    if (savedDc == 0) return 0;
    // SaveDC identifiers are one-based; negative values are relative to the
    // current stack (-1 is the most recently saved context).
    final index = savedDc < 0 ? savedStates.length + savedDc : savedDc - 1;
    if (index < 0 || index >= savedStates.length) return 0;
    final state = savedStates[index];
    final restoredCount = savedStates.length - index;
    savedStates.removeRange(index, savedStates.length);
    penColor = state.penColor;
    penWidth = state.penWidth;
    penStyle = state.penStyle;
    penDashPattern = state.penDashPattern;
    brushColor = state.brushColor;
    brushStyle = state.brushStyle;
    brushHatch = state.brushHatch;
    textColor = state.textColor;
    backgroundMode = state.backgroundMode;
    backgroundColor = state.backgroundColor;
    textAlign = state.textAlign;
    mapMode = state.mapMode;
    polyFillMode = state.polyFillMode;
    textBreakExtra = state.textBreakExtra;
    textBreakCount = state.textBreakCount;
    fontFace = state.fontFace;
    fontHeight = state.fontHeight;
    fontWeight = state.fontWeight;
    fontItalic = state.fontItalic;
    fontUnderline = state.fontUnderline;
    fontStrikeThrough = state.fontStrikeThrough;
    fontEscapementDegrees = state.fontEscapementDegrees;
    fontEncoding = state.fontEncoding;
    winOrgX = state.winOrgX;
    winOrgY = state.winOrgY;
    winExtX = state.winExtX;
    winExtY = state.winExtY;
    curX = state.curX;
    curY = state.curY;
    return restoredCount;
  }

  void ensureBounds(Iterable<MetafilePoint> pts) {
    for (final p in pts) {
      if (!haveBounds) {
        minX = maxX = p.x;
        minY = maxY = p.y;
        haveBounds = true;
      } else {
        minX = math.min(minX, p.x);
        maxX = math.max(maxX, p.x);
        minY = math.min(minY, p.y);
        maxY = math.max(maxY, p.y);
      }
    }
  }

  int allocSlot() {
    for (var i = 0; i < objects.length; i++) {
      if (objects[i] == null) return i;
    }
    objects.add(null);
    return objects.length - 1;
  }

  while (pos + 6 <= bytes.length) {
    // MS-WMF METARECORD: RecordSize (DWORD, in WORDS) + RecordFunction (WORD).
    final size = bd.getUint32(pos, Endian.little);
    final func = bd.getUint16(pos + 4, Endian.little);
    if (size < 3) break;
    final recEnd = pos + size * 2;
    if (recEnd > bytes.length) break;
    final params = pos + 6;

    if (func == _metaEof) {
      break;
    } else if (func == _metaEscape) {
      // Skip dual-mode EMF comments.
    } else if (func == _metaSaveDc) {
      savedStates.add(captureState());
      ops.add(const MetafileSaveDcOp());
    } else if (func == _metaRestoreDc && params + 2 <= recEnd) {
      final restored = restoreState(bd.getInt16(params, Endian.little));
      if (restored > 0) ops.add(MetafileRestoreDcOp(count: restored));
    } else if (func == _metaSetMapMode && params + 2 <= recEnd) {
      mapMode = bd.getUint16(params, Endian.little);
    } else if (func == _metaSetPolyFillMode && params + 2 <= recEnd) {
      polyFillMode = bd.getUint16(params, Endian.little);
    } else if (func == _metaSetTextJustification && params + 4 <= recEnd) {
      // WMF stores API parameters in reverse order: break count, then the
      // signed total extra width distributed across break characters.
      textBreakCount = bd.getInt16(params, Endian.little);
      textBreakExtra = bd.getInt16(params + 2, Endian.little);
    } else if ((func == _metaIntersectClipRect ||
            func == _metaExcludeClipRect) &&
        params + 8 <= recEnd) {
      final rect = MetafileRect(
        bd.getInt16(params + 6, Endian.little).toDouble(),
        bd.getInt16(params + 4, Endian.little).toDouble(),
        bd.getInt16(params + 2, Endian.little).toDouble(),
        bd.getInt16(params, Endian.little).toDouble(),
      );
      ops.add(MetafileClipRectOp(
        rect: rect,
        mode: func == _metaIntersectClipRect
            ? MetafileClipCombineMode.intersect
            : MetafileClipCombineMode.exclude,
      ));
    } else if (func == _metaSetWindowOrg && params + 4 <= recEnd) {
      winOrgY = bd.getInt16(params, Endian.little).toDouble();
      winOrgX = bd.getInt16(params + 2, Endian.little).toDouble();
    } else if (func == _metaSetWindowExt && params + 4 <= recEnd) {
      winExtY = bd.getInt16(params, Endian.little).toDouble();
      winExtX = bd.getInt16(params + 2, Endian.little).toDouble();
      final ox = winOrgX;
      final oy = winOrgY;
      final ex = winExtX;
      final ey = winExtY;
      if (!haveBounds && ox != null && oy != null && ex != null && ey != null) {
        minX = math.min(ox, ox + ex);
        maxX = math.max(ox, ox + ex);
        minY = math.min(oy, oy + ey);
        maxY = math.max(oy, oy + ey);
        haveBounds = true;
      }
    } else if (func == _metaSetBkMode && params + 2 <= recEnd) {
      backgroundMode = bd.getUint16(params, Endian.little);
    } else if (func == _metaSetBkColor && params + 4 <= recEnd) {
      backgroundColor = _rgbToArgb(bd.getUint32(params, Endian.little));
    } else if (func == _metaSetTextColor && params + 4 <= recEnd) {
      textColor = _rgbToArgb(bd.getUint32(params, Endian.little));
    } else if (func == _metaSetTextAlign && params + 2 <= recEnd) {
      textAlign = bd.getUint16(params, Endian.little);
    } else if (func == _metaCreatePenIndirect && params + 10 <= recEnd) {
      final style = bd.getUint16(params, Endian.little);
      final width = bd.getInt16(params + 2, Endian.little).abs().toDouble();
      final color = _rgbToArgb(bd.getUint32(params + 6, Endian.little));
      objects[allocSlot()] = _GdiPen(
        style,
        width == 0 ? 1.0 : width,
        color,
        metafileGdiDashPattern(style, width),
      );
    } else if (func == _metaCreateBrushIndirect && params + 8 <= recEnd) {
      final style = bd.getUint16(params, Endian.little);
      final color = _rgbToArgb(bd.getUint32(params + 2, Endian.little));
      final hatch = bd.getUint16(params + 6, Endian.little);
      objects[allocSlot()] = _GdiBrush(style, color, hatch);
    } else if (func == _metaCreateFontIndirect && params + 18 <= recEnd) {
      final height =
          bd.getInt16(params, Endian.little).abs().toDouble().clamp(1.0, 500.0);
      final escapement = bd.getInt16(params + 4, Endian.little) / 10.0;
      final weight = bd.getInt16(params + 8, Endian.little);
      final italic = bd.getUint8(params + 10) != 0;
      final underline = bd.getUint8(params + 11) != 0;
      final strikeThrough = bd.getUint8(params + 12) != 0;
      final charset = bd.getUint8(params + 13);
      String? face;
      final faceBytes = <int>[];
      for (var i = params + 18; i < recEnd && faceBytes.length < 32; i++) {
        final c = bytes[i];
        if (c == 0) break;
        faceBytes.add(c);
      }
      if (faceBytes.isNotEmpty) {
        face = decodeWindowsLegacyText(
          faceBytes,
          VsdLegacyTextEncoding.ansi,
        );
      }
      final encoding = face == 'Symbol' || face == 'MT Extra'
          ? VsdLegacyTextEncoding.symbol
          : vsdLegacyEncodingForCodePage(charset);
      objects[allocSlot()] = _GdiFont(
        height,
        face,
        weight,
        italic,
        underline,
        strikeThrough,
        escapement,
        encoding,
      );
    } else if (func == _metaSelectObject && params + 2 <= recEnd) {
      final ix = bd.getUint16(params, Endian.little);
      if (ix < objects.length) {
        final o = objects[ix];
        if (o is _GdiPen) {
          penStyle = o.style;
          penWidth = o.width;
          penColor = o.color;
          penDashPattern = o.dashPattern;
        } else if (o is _GdiBrush) {
          brushStyle = o.style;
          brushColor = o.color;
          brushHatch = o.hatch;
        } else if (o is _GdiFont) {
          fontHeight = o.height;
          fontFace = o.face;
          fontWeight = o.weight;
          fontItalic = o.italic;
          fontUnderline = o.underline;
          fontStrikeThrough = o.strikeThrough;
          fontEscapementDegrees = o.escapementDegrees;
          fontEncoding = o.encoding;
        }
      }
    } else if (func == _metaDeleteObject && params + 2 <= recEnd) {
      final ix = bd.getUint16(params, Endian.little);
      if (ix < objects.length) objects[ix] = null;
    } else if (func == _metaMoveTo && params + 4 <= recEnd) {
      curY = bd.getInt16(params, Endian.little).toDouble();
      curX = bd.getInt16(params + 2, Endian.little).toDouble();
    } else if (func == _metaLineTo &&
        params + 4 <= recEnd &&
        curX != null &&
        curY != null) {
      final y = bd.getInt16(params, Endian.little).toDouble();
      final x = bd.getInt16(params + 2, Endian.little).toDouble();
      final fromX = curX!;
      final fromY = curY!;
      final pts = [MetafilePoint(fromX, fromY), MetafilePoint(x, y)];
      ensureBounds(pts);
      if ((penStyle & 0x0f) != 5) {
        ops.add(MetafilePathOp(
          points: pts,
          closed: false,
          fill: false,
          stroke: true,
          fillArgb: 0,
          strokeArgb: penColor,
          strokeWidth: penWidth,
          strokeDashPattern: penDashPattern,
        ));
      }
      curX = x;
      curY = y;
    } else if ((func == _metaArc || func == _metaPie || func == _metaChord) &&
        params + 16 <= recEnd) {
      final end = MetafilePoint(
        bd.getInt16(params + 2, Endian.little).toDouble(),
        bd.getInt16(params, Endian.little).toDouble(),
      );
      final start = MetafilePoint(
        bd.getInt16(params + 6, Endian.little).toDouble(),
        bd.getInt16(params + 4, Endian.little).toDouble(),
      );
      final bounds = MetafileRect(
        bd.getInt16(params + 14, Endian.little).toDouble(),
        bd.getInt16(params + 12, Endian.little).toDouble(),
        bd.getInt16(params + 10, Endian.little).toDouble(),
        bd.getInt16(params + 8, Endian.little).toDouble(),
      );
      if (func == _metaPie && start.x == end.x && start.y == end.y) {
        final points = bounds.corners;
        ensureBounds(points);
        ops.add(_pathOp(
          points,
          closed: true,
          penStyle: penStyle,
          penColor: penColor,
          penWidth: penWidth,
          penDashPattern: penDashPattern,
          brushStyle: brushStyle,
          brushColor: brushColor,
          brushHatch: brushHatch,
          backgroundMode: backgroundMode,
          backgroundColor: backgroundColor,
          evenOddFill: polyFillMode != 2,
          asEllipse: true,
        ));
      } else {
        final arc = densifyMetafileEllipticalArc(bounds, start, end);
        final points = func == _metaPie
            ? <MetafilePoint>[
                MetafilePoint(
                  (bounds.minX + bounds.maxX) / 2,
                  (bounds.minY + bounds.maxY) / 2,
                ),
                ...arc,
              ]
            : arc;
        if (points.length >= 2) {
          ensureBounds(points);
          if (func == _metaArc) {
            if ((penStyle & 0x0f) != 5) {
              ops.add(MetafilePathOp(
                points: points,
                closed: false,
                fill: false,
                stroke: true,
                fillArgb: 0,
                strokeArgb: penColor,
                strokeWidth: penWidth,
                strokeDashPattern: penDashPattern,
              ));
            }
          } else {
            ops.add(_pathOp(
              points,
              closed: true,
              penStyle: penStyle,
              penColor: penColor,
              penWidth: penWidth,
              penDashPattern: penDashPattern,
              brushStyle: brushStyle,
              brushColor: brushColor,
              brushHatch: brushHatch,
              backgroundMode: backgroundMode,
              backgroundColor: backgroundColor,
              evenOddFill: polyFillMode != 2,
            ));
          }
        }
      }
    } else if (func == _metaPolygon) {
      final pts = _readPoints(bd, params, recEnd);
      if (pts.length >= 2) {
        ensureBounds(pts);
        ops.add(_pathOp(
          pts,
          closed: true,
          penStyle: penStyle,
          penColor: penColor,
          penWidth: penWidth,
          penDashPattern: penDashPattern,
          brushStyle: brushStyle,
          brushColor: brushColor,
          brushHatch: brushHatch,
          backgroundMode: backgroundMode,
          backgroundColor: backgroundColor,
          evenOddFill: polyFillMode != 2,
        ));
      }
    } else if (func == _metaPolyline) {
      final pts = _readPoints(bd, params, recEnd);
      if (pts.length >= 2) {
        ensureBounds(pts);
        if ((penStyle & 0x0f) != 5) {
          ops.add(MetafilePathOp(
            points: pts,
            closed: false,
            fill: false,
            stroke: true,
            fillArgb: 0,
            strokeArgb: penColor,
            strokeWidth: penWidth,
            strokeDashPattern: penDashPattern,
          ));
        }
      }
    } else if (func == _metaPolyBezier && params + 2 <= recEnd) {
      // Count (WORD) + POINTS: start + n×(c1,c2,end).
      final count = bd.getUint16(params, Endian.little);
      final pts = <MetafilePoint>[];
      var p = params + 2;
      for (var i = 0; i < count && p + 4 <= recEnd; i++) {
        final x = bd.getInt16(p, Endian.little).toDouble();
        final y = bd.getInt16(p + 2, Endian.little).toDouble();
        pts.add(MetafilePoint(x, y));
        p += 4;
      }
      if (pts.length >= 4) {
        final dense = densifyPolyBezier(pts);
        ensureBounds(dense);
        if ((penStyle & 0x0f) != 5) {
          ops.add(MetafilePathOp(
            points: dense,
            closed: false,
            fill: false,
            stroke: true,
            fillArgb: 0,
            strokeArgb: penColor,
            strokeWidth: penWidth,
            strokeDashPattern: penDashPattern,
          ));
        }
        if (dense.isNotEmpty) {
          curX = dense.last.x;
          curY = dense.last.y;
        }
      }
    } else if (func == _metaPolyPolygon && params + 2 <= recEnd) {
      final nPolys = bd.getUint16(params, Endian.little);
      var p = params + 2;
      final counts = <int>[];
      for (var i = 0; i < nPolys && p + 2 <= recEnd; i++) {
        counts.add(bd.getUint16(p, Endian.little));
        p += 2;
      }
      final contours = <List<MetafilePoint>>[];
      for (final c in counts) {
        final pts = <MetafilePoint>[];
        for (var i = 0; i < c && p + 4 <= recEnd; i++) {
          final x = bd.getInt16(p, Endian.little).toDouble();
          final y = bd.getInt16(p + 2, Endian.little).toDouble();
          pts.add(MetafilePoint(x, y));
          p += 4;
        }
        if (pts.length >= 2) {
          ensureBounds(pts);
          contours.add(pts);
        }
      }
      if (contours.isNotEmpty) {
        ops.add(_pathOp(
          contours.first,
          closed: true,
          penStyle: penStyle,
          penColor: penColor,
          penWidth: penWidth,
          penDashPattern: penDashPattern,
          brushStyle: brushStyle,
          brushColor: brushColor,
          brushHatch: brushHatch,
          backgroundMode: backgroundMode,
          backgroundColor: backgroundColor,
          additionalContours: <MetafilePathContour>[
            for (final points in contours.skip(1))
              MetafilePathContour(points: points, closed: true),
          ],
          evenOddFill: polyFillMode != 2,
        ));
      }
    } else if (func == _metaRoundRect && params + 12 <= recEnd) {
      final cornerHeight = bd.getInt16(params, Endian.little).abs() / 2.0;
      final cornerWidth = bd.getInt16(params + 2, Endian.little).abs() / 2.0;
      final bot = bd.getInt16(params + 4, Endian.little).toDouble();
      final right = bd.getInt16(params + 6, Endian.little).toDouble();
      final top = bd.getInt16(params + 8, Endian.little).toDouble();
      final left = bd.getInt16(params + 10, Endian.little).toDouble();
      final pts = [
        MetafilePoint(left, top),
        MetafilePoint(right, top),
        MetafilePoint(right, bot),
        MetafilePoint(left, bot),
      ];
      ensureBounds(pts);
      ops.add(_pathOp(
        pts,
        closed: true,
        penStyle: penStyle,
        penColor: penColor,
        penWidth: penWidth,
        penDashPattern: penDashPattern,
        brushStyle: brushStyle,
        brushColor: brushColor,
        brushHatch: brushHatch,
        backgroundMode: backgroundMode,
        backgroundColor: backgroundColor,
        evenOddFill: polyFillMode != 2,
        cornerRadiusX: cornerWidth,
        cornerRadiusY: cornerHeight,
      ));
    } else if ((func == _metaRectangle || func == _metaEllipse) &&
        params + 8 <= recEnd) {
      final bot = bd.getInt16(params, Endian.little).toDouble();
      final right = bd.getInt16(params + 2, Endian.little).toDouble();
      final top = bd.getInt16(params + 4, Endian.little).toDouble();
      final left = bd.getInt16(params + 6, Endian.little).toDouble();
      final pts = [
        MetafilePoint(left, top),
        MetafilePoint(right, top),
        MetafilePoint(right, bot),
        MetafilePoint(left, bot),
      ];
      ensureBounds(pts);
      ops.add(_pathOp(
        pts,
        closed: true,
        penStyle: penStyle,
        penColor: penColor,
        penWidth: penWidth,
        penDashPattern: penDashPattern,
        brushStyle: brushStyle,
        brushColor: brushColor,
        brushHatch: brushHatch,
        backgroundMode: backgroundMode,
        backgroundColor: backgroundColor,
        evenOddFill: polyFillMode != 2,
        asEllipse: func == _metaEllipse,
      ));
    } else if (func == _metaExtTextOut) {
      final textOp = _readExtTextOut(
        bd,
        bytes,
        params,
        recEnd,
        textColor,
        textAlign,
        fontHeight,
        fontFace,
        backgroundColor,
        backgroundMode == 2,
        fontWeight,
        fontItalic,
        fontUnderline,
        fontStrikeThrough,
        fontEscapementDegrees,
        fontEncoding,
        textBreakExtra,
        textBreakCount,
        currentX: (textAlign & 0x01) != 0 ? curX : null,
        currentY: (textAlign & 0x01) != 0 ? curY : null,
      );
      if (textOp != null) {
        ensureBounds([MetafilePoint(textOp.x, textOp.y)]);
        final opaqueRect = textOp.opaqueRect;
        if (opaqueRect != null) ensureBounds(opaqueRect.corners);
        ops.add(textOp);
        if ((textAlign & 0x01) != 0) {
          final next = metafileTextUpdatedCurrentPoint(textOp);
          curX = next.x;
          curY = next.y;
          ensureBounds([next]);
        }
      }
    } else if (func == _metaTextOut) {
      final textOp = _readTextOut(
        bd,
        bytes,
        params,
        recEnd,
        textColor,
        textAlign,
        fontHeight,
        fontFace,
        backgroundMode == 2 ? backgroundColor : null,
        fontWeight,
        fontItalic,
        fontUnderline,
        fontStrikeThrough,
        fontEscapementDegrees,
        fontEncoding,
        textBreakExtra,
        textBreakCount,
        currentX: (textAlign & 0x01) != 0 ? curX : null,
        currentY: (textAlign & 0x01) != 0 ? curY : null,
      );
      if (textOp != null) {
        ensureBounds([MetafilePoint(textOp.x, textOp.y)]);
        ops.add(textOp);
        if ((textAlign & 0x01) != 0) {
          final next = metafileTextUpdatedCurrentPoint(textOp);
          curX = next.x;
          curY = next.y;
          ensureBounds([next]);
        }
      }
    }

    pos = recEnd;
  }

  if (ops.isEmpty || !haveBounds) return null;
  if ((maxX - minX).abs() < 1) maxX = minX + 1;
  if ((maxY - minY).abs() < 1) maxY = minY + 1;
  return MetafileDrawing(
    minX: minX,
    minY: minY,
    maxX: maxX,
    maxY: maxY,
    ops: ops,
  );
}

MetafilePathOp _pathOp(
  List<MetafilePoint> pts, {
  required bool closed,
  required int penStyle,
  required int penColor,
  required double penWidth,
  required List<double>? penDashPattern,
  required int brushStyle,
  required int brushColor,
  required int brushHatch,
  required int backgroundMode,
  required int backgroundColor,
  List<MetafilePathContour> additionalContours = const <MetafilePathContour>[],
  bool evenOddFill = false,
  bool asEllipse = false,
  double? cornerRadiusX,
  double? cornerRadiusY,
}) {
  final fill = brushStyle == 0 || brushStyle == 2;
  final stroke = (penStyle & 0x0f) != 5;
  return MetafilePathOp(
    points: pts,
    closed: closed,
    fill: fill,
    stroke: stroke,
    fillArgb: fill ? brushColor : 0,
    strokeArgb: stroke ? penColor : 0,
    strokeWidth: penWidth,
    strokeDashPattern: penDashPattern,
    isEllipse: asEllipse,
    cornerRadiusX: cornerRadiusX,
    cornerRadiusY: cornerRadiusY,
    fillHatch: brushStyle == 2 ? brushHatch : null,
    fillBackgroundArgb:
        brushStyle == 2 && backgroundMode == 2 ? backgroundColor : null,
    additionalContours: additionalContours,
    evenOddFill: evenOddFill,
  );
}

List<MetafilePoint> _readPoints(ByteData bd, int params, int recEnd) {
  if (params + 2 > recEnd) return const [];
  final count = bd.getUint16(params, Endian.little);
  var p = params + 2;
  final pts = <MetafilePoint>[];
  for (var i = 0; i < count && p + 4 <= recEnd; i++) {
    final x = bd.getInt16(p, Endian.little).toDouble();
    final y = bd.getInt16(p + 2, Endian.little).toDouble();
    pts.add(MetafilePoint(x, y));
    p += 4;
  }
  return pts;
}

MetafileTextOp? _readExtTextOut(
    ByteData bd,
    Uint8List bytes,
    int params,
    int recEnd,
    int textColor,
    int textAlign,
    double fontHeight,
    String? fontFace,
    int backgroundColor,
    bool backgroundModeOpaque,
    int fontWeight,
    bool italic,
    bool underline,
    bool strikeThrough,
    double escapementDegrees,
    VsdLegacyTextEncoding encoding,
    int textBreakExtra,
    int textBreakCount,
    {double? currentX,
    double? currentY}) {
  if (params + 8 > recEnd) return null;
  final recordY = bd.getInt16(params, Endian.little).toDouble();
  final recordX = bd.getInt16(params + 2, Endian.little).toDouble();
  final x = currentX ?? recordX;
  final y = currentY ?? recordY;
  final count = bd.getUint16(params + 4, Endian.little);
  final options = bd.getUint16(params + 6, Endian.little);
  var p = params + 8;
  MetafileRect? recordRect;
  if ((options & 0x0006) != 0) {
    if (p + 8 > recEnd) return null;
    recordRect = MetafileRect(
      bd.getInt16(p, Endian.little).toDouble(),
      bd.getInt16(p + 2, Endian.little).toDouble(),
      bd.getInt16(p + 4, Endian.little).toDouble(),
      bd.getInt16(p + 6, Endian.little).toDouble(),
    );
    p += 8;
  }
  if (p + count > recEnd) return null;
  final raw = bytes.sublist(p, p + count);
  final text = decodeWindowsLegacyText(raw, encoding).replaceAll('\u0000', '');
  if (text.trim().isEmpty && !((options & 0x0002) != 0 && recordRect != null)) {
    return null;
  }
  List<double>? advancesX;
  List<double>? advancesY;
  var advancePos = p + count;
  if (count.isOdd) advancePos++;
  final hasVerticalAdvances = (options & 0x2000) != 0; // ETO_PDY
  final advanceWords = (recEnd - advancePos) ~/ 2;
  final wordsPerGlyph = hasVerticalAdvances ? 2 : 1;
  if (advanceWords >= count * wordsPerGlyph) {
    final byteX = <double>[];
    final byteY = hasVerticalAdvances ? <double>[] : null;
    for (var i = 0; i < count; i++) {
      byteX.add(bd.getInt16(advancePos, Endian.little).toDouble());
      advancePos += 2;
      if (byteY != null) {
        byteY.add(bd.getInt16(advancePos, Endian.little).toDouble());
        advancePos += 2;
      }
    }
    final byteLengths = windowsLegacyCharacterByteLengths(raw, encoding);
    if (byteLengths.length == text.runes.length) {
      var byteIndex = 0;
      final x = <double>[];
      final y = byteY == null ? null : <double>[];
      for (final byteLength in byteLengths) {
        var dx = 0.0;
        var dy = 0.0;
        for (var i = 0; i < byteLength; i++) {
          dx += byteX[byteIndex + i];
          if (byteY != null) dy += byteY[byteIndex + i];
        }
        x.add(dx);
        y?.add(dy);
        byteIndex += byteLength;
      }
      advancesX = List<double>.unmodifiable(x);
      advancesY = y == null ? null : List<double>.unmodifiable(y);
    }
  }
  advancesX ??= _justifiedTextAdvances(
    text,
    fontHeight,
    textBreakExtra,
    textBreakCount,
  );
  return MetafileTextOp(
    text: text,
    x: x,
    y: y,
    fontHeight: fontHeight,
    argb: textColor,
    face: fontFace,
    align: textAlign,
    backgroundArgb: backgroundModeOpaque || (options & 0x0002) != 0
        ? backgroundColor
        : null,
    opaqueRect: (options & 0x0002) != 0 ? recordRect : null,
    clipRect: (options & 0x0004) != 0 ? recordRect : null,
    advancesX: advancesX,
    advancesY: advancesY,
    fontWeight: fontWeight,
    italic: italic,
    underline: underline,
    strikeThrough: strikeThrough,
    escapementDegrees: escapementDegrees,
  );
}

MetafileTextOp? _readTextOut(
    ByteData bd,
    Uint8List bytes,
    int params,
    int recEnd,
    int textColor,
    int textAlign,
    double fontHeight,
    String? fontFace,
    int? backgroundArgb,
    int fontWeight,
    bool italic,
    bool underline,
    bool strikeThrough,
    double escapementDegrees,
    VsdLegacyTextEncoding encoding,
    int textBreakExtra,
    int textBreakCount,
    {double? currentX,
    double? currentY}) {
  if (params + 2 > recEnd) return null;
  final count = bd.getUint16(params, Endian.little);
  var p = params + 2;
  if (count == 0 || p + count + 4 > recEnd) return null;
  final raw = bytes.sublist(p, p + count);
  p += count;
  if (count.isOdd) p++;
  if (p + 4 > recEnd) return null;
  final recordY = bd.getInt16(p, Endian.little).toDouble();
  final recordX = bd.getInt16(p + 2, Endian.little).toDouble();
  final x = currentX ?? recordX;
  final y = currentY ?? recordY;
  final text = decodeWindowsLegacyText(raw, encoding).replaceAll('\u0000', '');
  if (text.trim().isEmpty) return null;
  final advancesX = _justifiedTextAdvances(
    text,
    fontHeight,
    textBreakExtra,
    textBreakCount,
  );
  return MetafileTextOp(
    text: text,
    x: x,
    y: y,
    fontHeight: fontHeight,
    argb: textColor,
    face: fontFace,
    align: textAlign,
    backgroundArgb: backgroundArgb,
    advancesX: advancesX,
    fontWeight: fontWeight,
    italic: italic,
    underline: underline,
    strikeThrough: strikeThrough,
    escapementDegrees: escapementDegrees,
  );
}

List<double>? _justifiedTextAdvances(
  String text,
  double fontHeight,
  int breakExtra,
  int breakCount,
) {
  if (breakExtra == 0 || breakCount <= 0) return null;
  final glyphs = text.runes.toList(growable: false);
  final breakIndices = <int>[
    for (var i = 0; i < glyphs.length; i++)
      if (glyphs[i] == 0x20) i,
  ];
  if (breakIndices.isEmpty) return null;
  final usedBreaks = math.min(breakCount, breakIndices.length);
  final base = math.max(fontHeight.abs(), 1.0) * 0.55;
  final advances = List<double>.filled(glyphs.length, base);
  var remaining = breakExtra;
  for (var i = 0; i < usedBreaks; i++) {
    final left = usedBreaks - i;
    final adjustment = remaining ~/ left;
    advances[breakIndices[i]] += adjustment;
    remaining -= adjustment;
  }
  return List<double>.unmodifiable(advances);
}

int _rgbToArgb(int colorRef) {
  final r = colorRef & 0xff;
  final g = (colorRef >> 8) & 0xff;
  final b = (colorRef >> 16) & 0xff;
  return 0xFF000000 | (r << 16) | (g << 8) | b;
}

sealed class _GdiObject {}

class _GdiPen extends _GdiObject {
  _GdiPen(this.style, this.width, this.color, this.dashPattern);
  final int style;
  final double width;
  final int color;
  final List<double>? dashPattern;
}

class _GdiBrush extends _GdiObject {
  _GdiBrush(this.style, this.color, this.hatch);
  final int style;
  final int color;
  final int hatch;
}

class _GdiFont extends _GdiObject {
  _GdiFont(
    this.height,
    this.face,
    this.weight,
    this.italic,
    this.underline,
    this.strikeThrough,
    this.escapementDegrees,
    this.encoding,
  );
  final double height;
  final String? face;
  final int weight;
  final bool italic;
  final bool underline;
  final bool strikeThrough;
  final double escapementDegrees;
  final VsdLegacyTextEncoding encoding;
}

class _WmfDcState {
  const _WmfDcState({
    required this.penColor,
    required this.penWidth,
    required this.penStyle,
    required this.penDashPattern,
    required this.brushColor,
    required this.brushStyle,
    required this.brushHatch,
    required this.textColor,
    required this.backgroundMode,
    required this.backgroundColor,
    required this.textAlign,
    required this.mapMode,
    required this.polyFillMode,
    required this.textBreakExtra,
    required this.textBreakCount,
    required this.fontFace,
    required this.fontHeight,
    required this.fontWeight,
    required this.fontItalic,
    required this.fontUnderline,
    required this.fontStrikeThrough,
    required this.fontEscapementDegrees,
    required this.fontEncoding,
    required this.winOrgX,
    required this.winOrgY,
    required this.winExtX,
    required this.winExtY,
    required this.curX,
    required this.curY,
  });

  final int penColor;
  final double penWidth;
  final int penStyle;
  final List<double>? penDashPattern;
  final int brushColor;
  final int brushStyle;
  final int brushHatch;
  final int textColor;
  final int backgroundMode;
  final int backgroundColor;
  final int textAlign;
  final int mapMode;
  final int polyFillMode;
  final int textBreakExtra;
  final int textBreakCount;
  final String? fontFace;
  final double fontHeight;
  final int fontWeight;
  final bool fontItalic;
  final bool fontUnderline;
  final bool fontStrikeThrough;
  final double fontEscapementDegrees;
  final VsdLegacyTextEncoding fontEncoding;
  final double? winOrgX;
  final double? winOrgY;
  final double? winExtX;
  final double? winExtY;
  final double? curX;
  final double? curY;
}
