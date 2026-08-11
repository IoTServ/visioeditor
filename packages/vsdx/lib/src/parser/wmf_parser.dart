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

import 'emf_embedded_bitmap.dart';
import 'emf_vector_parser.dart';
import 'metafile_drawing.dart';
import 'vsd/vsd_text_codec.dart';

const int _placeableKey = 0x9AC6CDD7;

const int _metaSetWindowOrg = 0x020B;
const int _metaSetWindowExt = 0x020C;
const int _metaSetViewportOrg = 0x020D;
const int _metaSetViewportExt = 0x020E;
const int _metaOffsetWindowOrg = 0x020F;
const int _metaScaleWindowExt = 0x0410;
const int _metaOffsetViewportOrg = 0x0211;
const int _metaScaleViewportExt = 0x0412;
const int _metaSetBkMode = 0x0102;
const int _metaSetMapMode = 0x0103;
const int _metaSetRop2 = 0x0104;
const int _metaSetPolyFillMode = 0x0106;
const int _metaSetStretchBltMode = 0x0107;
const int _metaSetTextCharExtra = 0x0108;
const int _metaSetBkColor = 0x0201;
const int _metaSetTextColor = 0x0209;
const int _metaSetTextJustification = 0x020A;
const int _metaSetTextAlign = 0x012E;
const int _metaRealizePalette = 0x0035;
const int _metaSetPalEntries = 0x0037;
const int _metaSaveDc = 0x001E;
const int _metaRestoreDc = 0x0127;
const int _metaResizePalette = 0x0139;
const int _metaExcludeClipRect = 0x0415;
const int _metaIntersectClipRect = 0x0416;
const int _metaCreatePenIndirect = 0x02FA;
const int _metaCreateBrushIndirect = 0x02FC;
const int _metaCreatePatternBrush = 0x01F9;
const int _metaDibCreatePatternBrush = 0x0142;
const int _metaCreateFontIndirect = 0x02FB;
const int _metaSelectObject = 0x012D;
const int _metaDeleteObject = 0x01F0;
const int _metaCreateRegion = 0x06FF;
const int _metaCreatePalette = 0x00F7;
const int _metaSelectPalette = 0x0234;
const int _metaAnimatePalette = 0x0436;
const int _metaFillRegion = 0x0228;
const int _metaFrameRegion = 0x0429;
const int _metaInvertRegion = 0x012A;
const int _metaPaintRegion = 0x012B;
const int _metaSelectClipRegion = 0x012C;
const int _metaPolygon = 0x0324;
const int _metaPolyline = 0x0325;
const int _metaPolyPolygon = 0x0538;
const int _metaArc = 0x0817;
const int _metaRectangle = 0x041B;
const int _metaRoundRect = 0x061C;
const int _metaEllipse = 0x0418;
const int _metaSetPixel = 0x041F;
const int _metaPie = 0x081A;
const int _metaChord = 0x0830;
const int _metaPatBlt = 0x061D;
const int _metaBitBlt = 0x0922;
const int _metaStretchBlt = 0x0B23;
const int _metaDibBitBlt = 0x0940;
const int _metaDibStretchBlt = 0x0B41;
const int _metaSetDibToDev = 0x0D33;
const int _metaStretchDib = 0x0F43;
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
  MetafileRect? logicalFrame;

  if (bd.getUint32(0, Endian.little) == _placeableKey) {
    if (bytes.length < 40) return null;
    final left = bd.getInt16(6, Endian.little).toDouble();
    final top = bd.getInt16(8, Endian.little).toDouble();
    final right = bd.getInt16(10, Endian.little).toDouble();
    final bottom = bd.getInt16(12, Endian.little).toDouble();
    logicalFrame = MetafileRect(left, top, right, bottom);
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
  var penIsCosmetic = true;
  var penStyle = 0;
  List<double>? penDashPattern;
  var brushColor = 0xFFFFFFFF;
  var brushStyle = 1; // BS_NULL
  var brushHatch = 0;
  Uint8List? brushPatternBmpBytes;
  var textColor = 0xFF000000;
  var backgroundMode = 1; // TRANSPARENT
  var backgroundColor = 0xFFFFFFFF;
  var textAlign = 0;
  var mapMode = 1; // MM_TEXT
  var polyFillMode = 1; // ALTERNATE
  var rasterOperation = MetafileRasterOperation.overpaint;
  var bitmapFilter = MetafileBitmapFilter.linear;
  var textBreakExtra = 0;
  var textBreakCount = 0;
  var textCharExtra = 0;
  String? fontFace;
  var fontHeight = 12.0;
  var fontWeight = 400;
  var fontItalic = false;
  var fontUnderline = false;
  var fontStrikeThrough = false;
  var fontEscapementDegrees = 0.0;
  var fontEncoding = VsdLegacyTextEncoding.ansi;
  _GdiPalette? selectedPalette;
  var winOrgX = 0.0, winOrgY = 0.0;
  double? winExtX, winExtY;
  var viewportOrgX = 0.0, viewportOrgY = 0.0;
  double? viewportExtX, viewportExtY;
  double? curX, curY;
  final ops = <Object>[];
  final savedStates = <_WmfDcState>[];

  _WmfDcState captureState() => _WmfDcState(
        penColor: penColor,
        penWidth: penWidth,
        penIsCosmetic: penIsCosmetic,
        penStyle: penStyle,
        penDashPattern: penDashPattern,
        brushColor: brushColor,
        brushStyle: brushStyle,
        brushHatch: brushHatch,
        brushPatternBmpBytes: brushPatternBmpBytes,
        textColor: textColor,
        backgroundMode: backgroundMode,
        backgroundColor: backgroundColor,
        textAlign: textAlign,
        mapMode: mapMode,
        polyFillMode: polyFillMode,
        rasterOperation: rasterOperation,
        bitmapFilter: bitmapFilter,
        textBreakExtra: textBreakExtra,
        textBreakCount: textBreakCount,
        textCharExtra: textCharExtra,
        fontFace: fontFace,
        fontHeight: fontHeight,
        fontWeight: fontWeight,
        fontItalic: fontItalic,
        fontUnderline: fontUnderline,
        fontStrikeThrough: fontStrikeThrough,
        fontEscapementDegrees: fontEscapementDegrees,
        fontEncoding: fontEncoding,
        selectedPalette: selectedPalette,
        winOrgX: winOrgX,
        winOrgY: winOrgY,
        winExtX: winExtX,
        winExtY: winExtY,
        viewportOrgX: viewportOrgX,
        viewportOrgY: viewportOrgY,
        viewportExtX: viewportExtX,
        viewportExtY: viewportExtY,
        logicalFrame: logicalFrame,
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
    penIsCosmetic = state.penIsCosmetic;
    penStyle = state.penStyle;
    penDashPattern = state.penDashPattern;
    brushColor = state.brushColor;
    brushStyle = state.brushStyle;
    brushHatch = state.brushHatch;
    brushPatternBmpBytes = state.brushPatternBmpBytes;
    textColor = state.textColor;
    backgroundMode = state.backgroundMode;
    backgroundColor = state.backgroundColor;
    textAlign = state.textAlign;
    mapMode = state.mapMode;
    polyFillMode = state.polyFillMode;
    rasterOperation = state.rasterOperation;
    bitmapFilter = state.bitmapFilter;
    textBreakExtra = state.textBreakExtra;
    textBreakCount = state.textBreakCount;
    textCharExtra = state.textCharExtra;
    fontFace = state.fontFace;
    fontHeight = state.fontHeight;
    fontWeight = state.fontWeight;
    fontItalic = state.fontItalic;
    fontUnderline = state.fontUnderline;
    fontStrikeThrough = state.fontStrikeThrough;
    fontEscapementDegrees = state.fontEscapementDegrees;
    fontEncoding = state.fontEncoding;
    selectedPalette = state.selectedPalette;
    winOrgX = state.winOrgX;
    winOrgY = state.winOrgY;
    winExtX = state.winExtX;
    winExtY = state.winExtY;
    viewportOrgX = state.viewportOrgX;
    viewportOrgY = state.viewportOrgY;
    viewportExtX = state.viewportExtX;
    viewportExtY = state.viewportExtY;
    logicalFrame = state.logicalFrame;
    curX = state.curX;
    curY = state.curY;
    return restoredCount;
  }

  double mappingScaleX() {
    final window = winExtX;
    final viewport = viewportExtX;
    return window != null && viewport != null && window != 0
        ? viewport / window
        : 1;
  }

  double mappingScaleY() {
    final window = winExtY;
    final viewport = viewportExtY;
    return window != null && viewport != null && window != 0
        ? viewport / window
        // The five fixed physical mapping modes use a bottom-up logical Y
        // axis. Their absolute unit size cancels when the metafile is fitted
        // into its Visio image frame, but the axis direction must be retained.
        : mapMode >= 2 && mapMode <= 6
            ? -1
            : 1;
  }

  MetafilePoint mapPoint(MetafilePoint point) => MetafilePoint(
        viewportOrgX + (point.x - winOrgX) * mappingScaleX(),
        viewportOrgY + (point.y - winOrgY) * mappingScaleY(),
      );

  List<MetafilePoint> mapPoints(Iterable<MetafilePoint> points) =>
      <MetafilePoint>[for (final point in points) mapPoint(point)];

  MetafileRect mapRect(MetafileRect rect) {
    final points = mapPoints(rect.corners);
    return MetafileRect(
      points.map((point) => point.x).reduce(math.min),
      points.map((point) => point.y).reduce(math.min),
      points.map((point) => point.x).reduce(math.max),
      points.map((point) => point.y).reduce(math.max),
    );
  }

  MetafileRect mapDirectedRect(
    double x,
    double y,
    double width,
    double height,
  ) {
    final start = mapPoint(MetafilePoint(x, y));
    final end = mapPoint(MetafilePoint(x + width, y + height));
    return MetafileRect(start.x, start.y, end.x, end.y);
  }

  MetafileTextOp mapTextOp(MetafileTextOp op) {
    final point = mapPoint(MetafilePoint(op.x, op.y));
    final sx = mappingScaleX();
    final sy = mappingScaleY();
    return MetafileTextOp(
      text: op.text,
      x: point.x,
      y: point.y,
      fontHeight: op.fontHeight * sy.abs(),
      argb: op.argb,
      face: op.face,
      align: op.align,
      backgroundArgb: op.backgroundArgb,
      opaqueRect: op.opaqueRect == null ? null : mapRect(op.opaqueRect!),
      clipRect: op.clipRect == null ? null : mapRect(op.clipRect!),
      advancesX: op.advancesX == null
          ? null
          : List<double>.unmodifiable(
              <double>[for (final advance in op.advancesX!) advance * sx],
            ),
      advancesY: op.advancesY == null
          ? null
          : List<double>.unmodifiable(
              <double>[for (final advance in op.advancesY!) advance * sy],
            ),
      fontWeight: op.fontWeight,
      italic: op.italic,
      underline: op.underline,
      strikeThrough: op.strikeThrough,
      escapementDegrees:
          sx * sy < 0 ? -op.escapementDegrees : op.escapementDegrees,
    );
  }

  double mappedPenWidth() =>
      penIsCosmetic ? penWidth : penWidth * mappingScaleX().abs();

  List<double>? mappedPenDashPattern() {
    final pattern = penDashPattern;
    if (pattern == null) return null;
    final scale = penIsCosmetic ? 1.0 : mappingScaleX().abs();
    return List<double>.unmodifiable(
      <double>[for (final length in pattern) length * scale],
    );
  }

  void ensureBounds(Iterable<MetafilePoint> pts) {
    final frame = logicalFrame;
    if (!haveBounds && frame != null) {
      for (final p in mapRect(frame).corners) {
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

  void emitRasterFill(
    double x,
    double y,
    double width,
    double height, {
    required int color,
    int? hatch,
    int? hatchBackground,
    Uint8List? patternBmpBytes,
  }) {
    final points = mapPoints(<MetafilePoint>[
      MetafilePoint(x, y),
      MetafilePoint(x + width, y),
      MetafilePoint(x + width, y + height),
      MetafilePoint(x, y + height),
    ]);
    ensureBounds(points);
    ops.add(MetafilePathOp(
      points: points,
      closed: true,
      fill: true,
      stroke: false,
      fillArgb: color,
      strokeArgb: 0,
      strokeWidth: 0,
      fillHatch: hatch,
      fillBackgroundArgb: hatchBackground,
      fillPatternBmpBytes: patternBmpBytes,
      rasterOperation: rasterOperation,
    ));
  }

  void emitRasterOperationFill(
    int rasterOperation,
    double x,
    double y,
    double width,
    double height,
  ) {
    if (rasterOperation == 0x00f00021 &&
        (brushStyle == 0 || brushStyle == 2 || brushPatternBmpBytes != null)) {
      emitRasterFill(
        x,
        y,
        width,
        height,
        color: brushColor,
        hatch: brushStyle == 2 ? brushHatch : null,
        hatchBackground:
            brushStyle == 2 && backgroundMode == 2 ? backgroundColor : null,
        patternBmpBytes: brushPatternBmpBytes,
      );
    } else if (rasterOperation == 0x00000042) {
      emitRasterFill(
        x,
        y,
        width,
        height,
        color: 0xff000000,
        patternBmpBytes: null,
      );
    } else if (rasterOperation == 0x00ff0062) {
      emitRasterFill(
        x,
        y,
        width,
        height,
        color: 0xffffffff,
        patternBmpBytes: null,
      );
    }
  }

  _GdiBrush? regionBrush(int? index) {
    if (index == null) {
      return _GdiBrush(
        brushStyle,
        brushColor,
        brushHatch,
        brushPatternBmpBytes,
      );
    }
    if (index >= objects.length) return null;
    final object = objects[index];
    return object is _GdiBrush ? object : null;
  }

  void emitRegion(
    _GdiRegion region,
    _GdiBrush brush, {
    MetafileRasterOperation? operation,
  }) {
    if (!brush.canFill || region.rectangles.isEmpty) return;
    final contours = <List<MetafilePoint>>[
      for (final rectangle in region.rectangles) mapPoints(rectangle),
    ];
    for (final contour in contours) {
      ensureBounds(contour);
    }
    ops.add(MetafilePathOp(
      points: contours.first,
      closed: true,
      fill: true,
      stroke: false,
      fillArgb: brush.color,
      strokeArgb: 0,
      strokeWidth: 0,
      fillHatch: brush.style == 2 ? brush.hatch : null,
      fillBackgroundArgb:
          brush.style == 2 && backgroundMode == 2 ? backgroundColor : null,
      fillPatternBmpBytes: brush.patternBmpBytes,
      additionalContours: <MetafilePathContour>[
        for (final contour in contours.skip(1))
          MetafilePathContour(points: contour, closed: true),
      ],
      // Scan rectangles describe their union; non-zero filling prevents
      // adjacent bands from punching even-odd holes into the region.
      evenOddFill: false,
      rasterOperation: operation ?? rasterOperation,
    ));
  }

  void emitFramedRegion(
    _GdiRegion region,
    _GdiBrush brush,
    double frameWidth,
    double frameHeight,
  ) {
    if (!brush.canFill || frameWidth <= 0 || frameHeight <= 0) return;
    emitRegion(
      _GdiRegion(_frameRegionRectangles(
        region.rectangles,
        frameWidth,
        frameHeight,
      )),
      brush,
    );
  }

  void selectClipRegion(_GdiRegion region) {
    if (region.rectangles.isEmpty) return;
    final contours = <List<MetafilePoint>>[
      for (final rectangle in region.rectangles) mapPoints(rectangle),
    ];
    ops.add(MetafileClipPathOp(
      points: contours.first,
      mode: MetafileClipCombineMode.intersect,
      additionalContours: <MetafilePathContour>[
        for (final contour in contours.skip(1))
          MetafilePathContour(points: contour, closed: true),
      ],
      evenOddFill: false,
    ));
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
    } else if (func == _metaSetRop2 && params + 2 <= recEnd) {
      rasterOperation = switch (bd.getUint16(params, Endian.little)) {
        6 => MetafileRasterOperation.invert, // R2_NOT
        7 => MetafileRasterOperation.xor, // R2_XORPEN
        11 => MetafileRasterOperation.nop, // R2_NOP
        _ => MetafileRasterOperation.overpaint,
      };
    } else if (func == _metaSetPolyFillMode && params + 2 <= recEnd) {
      polyFillMode = bd.getUint16(params, Endian.little);
    } else if (func == _metaSetStretchBltMode && params + 2 <= recEnd) {
      bitmapFilter = switch (bd.getUint16(params, Endian.little)) {
        1 || 2 || 3 => MetafileBitmapFilter.nearest,
        4 => MetafileBitmapFilter.linear,
        _ => bitmapFilter,
      };
    } else if (func == _metaSetTextJustification && params + 4 <= recEnd) {
      // WMF stores API parameters in reverse order: break count, then the
      // signed total extra width distributed across break characters.
      textBreakCount = bd.getInt16(params, Endian.little);
      textBreakExtra = bd.getInt16(params + 2, Endian.little);
    } else if (func == _metaSetTextCharExtra && params + 2 <= recEnd) {
      textCharExtra = bd.getInt16(params, Endian.little);
    } else if ((func == _metaIntersectClipRect ||
            func == _metaExcludeClipRect) &&
        params + 8 <= recEnd) {
      final rect = mapRect(MetafileRect(
        bd.getInt16(params + 6, Endian.little).toDouble(),
        bd.getInt16(params + 4, Endian.little).toDouble(),
        bd.getInt16(params + 2, Endian.little).toDouble(),
        bd.getInt16(params, Endian.little).toDouble(),
      ));
      ops.add(MetafileClipRectOp(
        rect: rect,
        mode: func == _metaIntersectClipRect
            ? MetafileClipCombineMode.intersect
            : MetafileClipCombineMode.exclude,
      ));
    } else if (func == _metaSetWindowOrg && params + 4 <= recEnd) {
      winOrgY = bd.getInt16(params, Endian.little).toDouble();
      winOrgX = bd.getInt16(params + 2, Endian.little).toDouble();
      final ex = winExtX;
      final ey = winExtY;
      if (ex != null && ey != null) {
        logicalFrame = MetafileRect(
          winOrgX,
          winOrgY,
          winOrgX + ex,
          winOrgY + ey,
        );
      }
    } else if (func == _metaSetWindowExt && params + 4 <= recEnd) {
      winExtY = bd.getInt16(params, Endian.little).toDouble();
      winExtX = bd.getInt16(params + 2, Endian.little).toDouble();
      final ex = winExtX;
      final ey = winExtY;
      if (ex != null && ey != null) {
        logicalFrame = MetafileRect(
          winOrgX,
          winOrgY,
          winOrgX + ex,
          winOrgY + ey,
        );
      }
    } else if (func == _metaSetViewportOrg && params + 4 <= recEnd) {
      viewportOrgY = bd.getInt16(params, Endian.little).toDouble();
      viewportOrgX = bd.getInt16(params + 2, Endian.little).toDouble();
    } else if (func == _metaSetViewportExt && params + 4 <= recEnd) {
      viewportExtY = bd.getInt16(params, Endian.little).toDouble();
      viewportExtX = bd.getInt16(params + 2, Endian.little).toDouble();
    } else if (func == _metaOffsetWindowOrg && params + 4 <= recEnd) {
      winOrgY += bd.getInt16(params, Endian.little);
      winOrgX += bd.getInt16(params + 2, Endian.little);
      final ex = winExtX;
      final ey = winExtY;
      if (ex != null && ey != null) {
        logicalFrame = MetafileRect(
          winOrgX,
          winOrgY,
          winOrgX + ex,
          winOrgY + ey,
        );
      }
    } else if (func == _metaOffsetViewportOrg && params + 4 <= recEnd) {
      viewportOrgY += bd.getInt16(params, Endian.little);
      viewportOrgX += bd.getInt16(params + 2, Endian.little);
    } else if ((func == _metaScaleWindowExt || func == _metaScaleViewportExt) &&
        params + 8 <= recEnd) {
      final yDenom = bd.getInt16(params, Endian.little);
      final yNum = bd.getInt16(params + 2, Endian.little);
      final xDenom = bd.getInt16(params + 4, Endian.little);
      final xNum = bd.getInt16(params + 6, Endian.little);
      if (xDenom != 0 && yDenom != 0) {
        if (func == _metaScaleWindowExt) {
          final oldWinExtX = winExtX;
          final oldWinExtY = winExtY;
          if (oldWinExtX != null) winExtX = oldWinExtX * xNum / xDenom;
          if (oldWinExtY != null) winExtY = oldWinExtY * yNum / yDenom;
          final ex = winExtX;
          final ey = winExtY;
          if (ex != null && ey != null) {
            logicalFrame = MetafileRect(
              winOrgX,
              winOrgY,
              winOrgX + ex,
              winOrgY + ey,
            );
          }
        } else {
          final oldViewportExtX = viewportExtX;
          final oldViewportExtY = viewportExtY;
          if (oldViewportExtX != null) {
            viewportExtX = oldViewportExtX * xNum / xDenom;
          }
          if (oldViewportExtY != null) {
            viewportExtY = oldViewportExtY * yNum / yDenom;
          }
        }
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
      final rawWidth = bd.getInt16(params + 2, Endian.little).abs().toDouble();
      final color = _rgbToArgb(bd.getUint32(params + 6, Endian.little));
      objects[allocSlot()] = _GdiPen(
        style,
        rawWidth == 0 ? 1.0 : rawWidth,
        rawWidth == 0,
        color,
        metafileGdiDashPattern(style, rawWidth),
      );
    } else if (func == _metaCreateBrushIndirect && params + 8 <= recEnd) {
      final style = bd.getUint16(params, Endian.little);
      final color = _rgbToArgb(bd.getUint32(params + 2, Endian.little));
      final hatch = bd.getUint16(params + 6, Endian.little);
      objects[allocSlot()] = _GdiBrush(style, color, hatch, null);
    } else if (func == _metaDibCreatePatternBrush && params + 4 <= recEnd) {
      final style = bd.getUint16(params, Endian.little);
      final colorUsage = bd.getUint16(params + 2, Endian.little);
      final target = params + 4;
      Uint8List? pattern;
      if (style == 3 && !_isDibHeaderAt(bd, target, recEnd)) {
        pattern = _wrapBitmap16Pattern(bytes, target, recEnd, 10);
      } else if (target + 12 <= recEnd) {
        final dib = _resolvePaletteDib(
          Uint8List.sublistView(bytes, target, recEnd),
          colorUsage,
          selectedPalette,
        );
        if (dib != null) pattern = wrapDibAsBmp(dib);
      }
      objects[allocSlot()] = _GdiBrush(style, 0xffffffff, 0, pattern);
    } else if (func == _metaCreatePatternBrush && params + 32 <= recEnd) {
      final pattern = _wrapBitmap16Pattern(bytes, params, recEnd, 32);
      objects[allocSlot()] = _GdiBrush(3, 0xffffffff, 0, pattern);
    } else if (func == _metaCreateRegion) {
      objects[allocSlot()] =
          _readWmfRegion(bd, params, recEnd) ?? _GdiRegion(const []);
    } else if (func == _metaCreatePalette && params + 4 <= recEnd) {
      final count = bd.getUint16(params + 2, Endian.little);
      final entries = _readPaletteEntries(bd, params + 4, recEnd, count);
      objects[allocSlot()] = _GdiPalette(entries ?? <int>[]);
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
          penIsCosmetic = o.isCosmetic;
          penColor = o.color;
          penDashPattern = o.dashPattern;
        } else if (o is _GdiBrush) {
          brushStyle = o.style;
          brushColor = o.color;
          brushHatch = o.hatch;
          brushPatternBmpBytes = o.patternBmpBytes;
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
    } else if (func == _metaSelectPalette && params + 2 <= recEnd) {
      final ix = bd.getUint16(params, Endian.little);
      if (ix < objects.length && objects[ix] is _GdiPalette) {
        selectedPalette = objects[ix]! as _GdiPalette;
      }
    } else if ((func == _metaSetPalEntries || func == _metaAnimatePalette) &&
        selectedPalette != null &&
        params + 4 <= recEnd) {
      final start = bd.getUint16(params, Endian.little);
      final count = bd.getUint16(params + 2, Endian.little);
      final entries = _readPaletteEntries(bd, params + 4, recEnd, count);
      if (entries != null) selectedPalette!.replace(start, entries);
    } else if (func == _metaResizePalette &&
        selectedPalette != null &&
        params + 2 <= recEnd) {
      selectedPalette!.resize(bd.getUint16(params, Endian.little));
    } else if (func == _metaRealizePalette) {
      // Vector replay has no device system palette to realize. Resolve the
      // selected logical palette directly when emitting a standalone bitmap.
    } else if (func == _metaDeleteObject && params + 2 <= recEnd) {
      final ix = bd.getUint16(params, Endian.little);
      if (ix < objects.length) objects[ix] = null;
    } else if (func == _metaFillRegion && params + 4 <= recEnd) {
      final regionIndex = bd.getUint16(params, Endian.little);
      final brushIndex = bd.getUint16(params + 2, Endian.little);
      if (regionIndex < objects.length && objects[regionIndex] is _GdiRegion) {
        final brush = regionBrush(brushIndex);
        if (brush != null) {
          emitRegion(objects[regionIndex]! as _GdiRegion, brush);
        }
      }
    } else if (func == _metaFrameRegion && params + 8 <= recEnd) {
      final regionIndex = bd.getUint16(params, Endian.little);
      final brushIndex = bd.getUint16(params + 2, Endian.little);
      final frameHeight =
          bd.getInt16(params + 4, Endian.little).abs().toDouble();
      final frameWidth =
          bd.getInt16(params + 6, Endian.little).abs().toDouble();
      if (regionIndex < objects.length && objects[regionIndex] is _GdiRegion) {
        final brush = regionBrush(brushIndex);
        if (brush != null) {
          emitFramedRegion(
            objects[regionIndex]! as _GdiRegion,
            brush,
            frameWidth,
            frameHeight,
          );
        }
      }
    } else if ((func == _metaInvertRegion ||
            func == _metaPaintRegion ||
            func == _metaSelectClipRegion) &&
        params + 2 <= recEnd) {
      final regionIndex = bd.getUint16(params, Endian.little);
      if (regionIndex < objects.length && objects[regionIndex] is _GdiRegion) {
        final region = objects[regionIndex]! as _GdiRegion;
        if (func == _metaInvertRegion) {
          emitRegion(
            region,
            _GdiBrush(0, 0xffffffff, 0, null),
            operation: MetafileRasterOperation.invert,
          );
        } else if (func == _metaPaintRegion) {
          final brush = regionBrush(null);
          if (brush != null) emitRegion(region, brush);
        } else {
          selectClipRegion(region);
        }
      }
    } else if (func == _metaSetPixel && params + 8 <= recEnd) {
      final point = mapPoint(MetafilePoint(
        bd.getInt16(params + 6, Endian.little).toDouble(),
        bd.getInt16(params + 4, Endian.little).toDouble(),
      ));
      ops.add(MetafilePixelOp(
        x: point.x,
        y: point.y,
        argb: _rgbToArgb(bd.getUint32(params, Endian.little)),
      ));
      ensureBounds(<MetafilePoint>[
        point,
        MetafilePoint(point.x + 1, point.y + 1),
      ]);
    } else if (func == _metaPatBlt && params + 12 <= recEnd) {
      final rasterOperation = bd.getUint32(params, Endian.little);
      final height = bd.getInt16(params + 4, Endian.little).toDouble();
      final width = bd.getInt16(params + 6, Endian.little).toDouble();
      final y = bd.getInt16(params + 8, Endian.little).toDouble();
      final x = bd.getInt16(params + 10, Endian.little).toDouble();
      emitRasterOperationFill(rasterOperation, x, y, width, height);
    } else if (func == _metaSetDibToDev && params + 30 <= recEnd) {
      // Match LibreOffice's SetDIBitsToDevice replay: StartScan selects the
      // first source row and ScanCount is the height actually transferred.
      // Unlike the BLT records, this record always uses a straight source
      // copy and gives the destination the same size as that scan subset.
      final colorUsage = bd.getUint16(params, Endian.little);
      final scanCount = bd.getUint16(params + 2, Endian.little);
      final startScan = bd.getUint16(params + 4, Endian.little);
      final sourceY = bd.getUint16(params + 6, Endian.little);
      final sourceX = bd.getUint16(params + 8, Endian.little);
      final sourceWidth = bd.getUint16(params + 12, Endian.little);
      final destinationY = bd.getUint16(params + 14, Endian.little).toDouble();
      final destinationX = bd.getUint16(params + 16, Endian.little).toDouble();
      if (sourceWidth > 0 && scanCount > 0) {
        final dib = _resolvePaletteDib(
          Uint8List.sublistView(bytes, params + 18, recEnd),
          colorUsage,
          selectedPalette,
        );
        if (dib == null) {
          pos = recEnd;
          continue;
        }
        final dimensions = dibDimensions(dib);
        final bmp = wrapDibAsBmp(dib);
        if (dimensions != null && bmp != null) {
          final pixelWidth = dimensions.$1;
          final pixelHeight = dimensions.$2;
          final firstSourceY = sourceY + startScan;
          if (sourceX + sourceWidth <= pixelWidth &&
              firstSourceY + scanCount <= pixelHeight) {
            final destination = mapDirectedRect(
              destinationX,
              destinationY,
              sourceWidth.toDouble(),
              scanCount.toDouble(),
            );
            ensureBounds(destination.corners);
            ops.add(MetafileBitmapOp(
              bmpBytes: bmp,
              pixelWidth: pixelWidth,
              pixelHeight: pixelHeight,
              destination: destination,
              source: MetafileRect(
                sourceX.toDouble(),
                firstSourceY.toDouble(),
                (sourceX + sourceWidth).toDouble(),
                (firstSourceY + scanCount).toDouble(),
              ),
              filter: bitmapFilter,
            ));
          }
        }
      }
    } else if ((func == _metaDibBitBlt ||
            func == _metaDibStretchBlt ||
            func == _metaStretchDib) &&
        !(func != _metaStretchDib && size == (func >> 8) + 3)) {
      // Match LibreOffice's WMF reader: retain a source DIB in the display
      // list at the point where the record occurs. Extracting it after parsing
      // loses both the destination rectangle and surrounding vector content.
      final stretched = func == _metaDibStretchBlt || func == _metaStretchDib;
      final fixedBytes = func == _metaStretchDib
          ? 22
          : stretched
              ? 20
              : 16;
      if (params + fixedBytes + 12 <= recEnd) {
        final rasterOperation = bd.getUint32(params, Endian.little);
        var p = params + 4;
        final colorUsage =
            func == _metaStretchDib ? bd.getUint16(p, Endian.little) : 0;
        if (func == _metaStretchDib) p += 2;
        var sourceHeight = 0;
        var sourceWidth = 0;
        if (stretched) {
          sourceHeight = bd.getInt16(p, Endian.little);
          sourceWidth = bd.getInt16(p + 2, Endian.little);
          p += 4;
        }
        final sourceY = bd.getInt16(p, Endian.little);
        final sourceX = bd.getInt16(p + 2, Endian.little);
        p += 4;
        final destinationHeight = bd.getInt16(p, Endian.little).toDouble();
        final destinationWidth = bd.getInt16(p + 2, Endian.little).toDouble();
        final destinationY = bd.getInt16(p + 4, Endian.little).toDouble();
        final destinationX = bd.getInt16(p + 6, Endian.little).toDouble();
        p += 8;

        if (destinationWidth != 0 &&
            destinationHeight != 0 &&
            (rasterOperation == 0x00f00021 ||
                rasterOperation == 0x00000042 ||
                rasterOperation == 0x00ff0062)) {
          // These ROP3 values ignore the source even when a DIB is present.
          emitRasterOperationFill(
            rasterOperation,
            destinationX,
            destinationY,
            destinationWidth,
            destinationHeight,
          );
        } else if (destinationWidth != 0 && destinationHeight != 0) {
          final dib = _resolvePaletteDib(
            Uint8List.sublistView(bytes, p, recEnd),
            colorUsage,
            selectedPalette,
          );
          if (dib == null) {
            pos = recEnd;
            continue;
          }
          final dimensions = dibDimensions(dib);
          final bmp = wrapDibAsBmp(dib);
          if (dimensions != null && bmp != null) {
            final pixelWidth = dimensions.$1;
            final pixelHeight = dimensions.$2;
            MetafileRect? source;
            if (sourceWidth > 0 &&
                sourceHeight > 0 &&
                sourceX >= 0 &&
                sourceY >= 0 &&
                sourceX + sourceWidth <= pixelWidth &&
                sourceY + sourceHeight <= pixelHeight) {
              source = MetafileRect(
                sourceX.toDouble(),
                sourceY.toDouble(),
                (sourceX + sourceWidth).toDouble(),
                (sourceY + sourceHeight).toDouble(),
              );
            }
            final destination = mapDirectedRect(
              destinationX,
              destinationY,
              destinationWidth,
              destinationHeight,
            );
            ensureBounds(destination.corners);
            ops.add(MetafileBitmapOp(
              bmpBytes: bmp,
              pixelWidth: pixelWidth,
              pixelHeight: pixelHeight,
              destination: destination,
              source: source,
              rasterOperation: rasterOperation,
              filter: bitmapFilter,
            ));
          }
        }
      }
    } else if ((func == _metaBitBlt ||
            func == _metaStretchBlt ||
            func == _metaDibBitBlt ||
            func == _metaDibStretchBlt) &&
        size == (func >> 8) + 3) {
      // The short form has no embedded bitmap. PATCOPY, BLACKNESS and
      // WHITENESS still produce output because their ROP3 ignores the source.
      final stretched = func == _metaStretchBlt || func == _metaDibStretchBlt;
      final requiredBytes = stretched ? 22 : 18;
      if (params + requiredBytes <= recEnd) {
        final rasterOperation = bd.getUint32(params, Endian.little);
        var p = params + 4;
        if (stretched) p += 4; // SrcHeight, SrcWidth.
        p += 4; // YSrc, XSrc.
        p += 2; // Reserved in the no-source form.
        final height = bd.getInt16(p, Endian.little).toDouble();
        final width = bd.getInt16(p + 2, Endian.little).toDouble();
        final y = bd.getInt16(p + 4, Endian.little).toDouble();
        final x = bd.getInt16(p + 6, Endian.little).toDouble();
        emitRasterOperationFill(rasterOperation, x, y, width, height);
      }
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
      final pts = mapPoints(<MetafilePoint>[
        MetafilePoint(fromX, fromY),
        MetafilePoint(x, y),
      ]);
      ensureBounds(pts);
      if ((penStyle & 0x0f) != 5) {
        ops.add(MetafilePathOp(
          points: pts,
          closed: false,
          fill: false,
          stroke: true,
          fillArgb: 0,
          strokeArgb: penColor,
          strokeWidth: mappedPenWidth(),
          strokeDashPattern: mappedPenDashPattern(),
          rasterOperation: rasterOperation,
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
        final points = mapPoints(bounds.corners);
        ensureBounds(points);
        ops.add(_pathOp(
          points,
          closed: true,
          penStyle: penStyle,
          penColor: penColor,
          penWidth: mappedPenWidth(),
          penDashPattern: mappedPenDashPattern(),
          brushStyle: brushStyle,
          brushColor: brushColor,
          brushHatch: brushHatch,
          brushPatternBmpBytes: brushPatternBmpBytes,
          backgroundMode: backgroundMode,
          backgroundColor: backgroundColor,
          rasterOperation: rasterOperation,
          evenOddFill: polyFillMode != 2,
          asEllipse: true,
        ));
      } else {
        final arc = densifyMetafileEllipticalArc(bounds, start, end);
        final rawPoints = func == _metaPie
            ? <MetafilePoint>[
                MetafilePoint(
                  (bounds.minX + bounds.maxX) / 2,
                  (bounds.minY + bounds.maxY) / 2,
                ),
                ...arc,
              ]
            : arc;
        final points = mapPoints(rawPoints);
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
                strokeWidth: mappedPenWidth(),
                strokeDashPattern: mappedPenDashPattern(),
                rasterOperation: rasterOperation,
              ));
            }
          } else {
            ops.add(_pathOp(
              points,
              closed: true,
              penStyle: penStyle,
              penColor: penColor,
              penWidth: mappedPenWidth(),
              penDashPattern: mappedPenDashPattern(),
              brushStyle: brushStyle,
              brushColor: brushColor,
              brushHatch: brushHatch,
              brushPatternBmpBytes: brushPatternBmpBytes,
              backgroundMode: backgroundMode,
              backgroundColor: backgroundColor,
              rasterOperation: rasterOperation,
              evenOddFill: polyFillMode != 2,
            ));
          }
        }
      }
    } else if (func == _metaPolygon) {
      final pts = mapPoints(_readPoints(bd, params, recEnd));
      if (pts.length >= 2) {
        ensureBounds(pts);
        ops.add(_pathOp(
          pts,
          closed: true,
          penStyle: penStyle,
          penColor: penColor,
          penWidth: mappedPenWidth(),
          penDashPattern: mappedPenDashPattern(),
          brushStyle: brushStyle,
          brushColor: brushColor,
          brushHatch: brushHatch,
          brushPatternBmpBytes: brushPatternBmpBytes,
          backgroundMode: backgroundMode,
          backgroundColor: backgroundColor,
          rasterOperation: rasterOperation,
          evenOddFill: polyFillMode != 2,
        ));
      }
    } else if (func == _metaPolyline) {
      final pts = mapPoints(_readPoints(bd, params, recEnd));
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
            strokeWidth: mappedPenWidth(),
            strokeDashPattern: mappedPenDashPattern(),
            rasterOperation: rasterOperation,
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
        final dense = mapPoints(densifyPolyBezier(pts));
        ensureBounds(dense);
        if ((penStyle & 0x0f) != 5) {
          ops.add(MetafilePathOp(
            points: dense,
            closed: false,
            fill: false,
            stroke: true,
            fillArgb: 0,
            strokeArgb: penColor,
            strokeWidth: mappedPenWidth(),
            strokeDashPattern: mappedPenDashPattern(),
            rasterOperation: rasterOperation,
          ));
        }
        if (pts.isNotEmpty) {
          curX = pts.last.x;
          curY = pts.last.y;
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
          final mapped = mapPoints(pts);
          ensureBounds(mapped);
          contours.add(mapped);
        }
      }
      if (contours.isNotEmpty) {
        ops.add(_pathOp(
          contours.first,
          closed: true,
          penStyle: penStyle,
          penColor: penColor,
          penWidth: mappedPenWidth(),
          penDashPattern: mappedPenDashPattern(),
          brushStyle: brushStyle,
          brushColor: brushColor,
          brushHatch: brushHatch,
          brushPatternBmpBytes: brushPatternBmpBytes,
          backgroundMode: backgroundMode,
          backgroundColor: backgroundColor,
          rasterOperation: rasterOperation,
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
      final pts = mapPoints(<MetafilePoint>[
        MetafilePoint(left, top),
        MetafilePoint(right, top),
        MetafilePoint(right, bot),
        MetafilePoint(left, bot),
      ]);
      ensureBounds(pts);
      ops.add(_pathOp(
        pts,
        closed: true,
        penStyle: penStyle,
        penColor: penColor,
        penWidth: mappedPenWidth(),
        penDashPattern: mappedPenDashPattern(),
        brushStyle: brushStyle,
        brushColor: brushColor,
        brushHatch: brushHatch,
        brushPatternBmpBytes: brushPatternBmpBytes,
        backgroundMode: backgroundMode,
        backgroundColor: backgroundColor,
        rasterOperation: rasterOperation,
        evenOddFill: polyFillMode != 2,
        cornerRadiusX: cornerWidth * mappingScaleX().abs(),
        cornerRadiusY: cornerHeight * mappingScaleY().abs(),
      ));
    } else if ((func == _metaRectangle || func == _metaEllipse) &&
        params + 8 <= recEnd) {
      final bot = bd.getInt16(params, Endian.little).toDouble();
      final right = bd.getInt16(params + 2, Endian.little).toDouble();
      final top = bd.getInt16(params + 4, Endian.little).toDouble();
      final left = bd.getInt16(params + 6, Endian.little).toDouble();
      final pts = mapPoints(<MetafilePoint>[
        MetafilePoint(left, top),
        MetafilePoint(right, top),
        MetafilePoint(right, bot),
        MetafilePoint(left, bot),
      ]);
      ensureBounds(pts);
      ops.add(_pathOp(
        pts,
        closed: true,
        penStyle: penStyle,
        penColor: penColor,
        penWidth: mappedPenWidth(),
        penDashPattern: mappedPenDashPattern(),
        brushStyle: brushStyle,
        brushColor: brushColor,
        brushHatch: brushHatch,
        brushPatternBmpBytes: brushPatternBmpBytes,
        backgroundMode: backgroundMode,
        backgroundColor: backgroundColor,
        rasterOperation: rasterOperation,
        evenOddFill: polyFillMode != 2,
        asEllipse: func == _metaEllipse,
      ));
    } else if (func == _metaExtTextOut) {
      final rawTextOp = _readExtTextOut(
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
        textCharExtra,
        currentX: (textAlign & 0x01) != 0 ? curX : null,
        currentY: (textAlign & 0x01) != 0 ? curY : null,
      );
      if (rawTextOp != null) {
        final textOp = mapTextOp(rawTextOp);
        ensureBounds([MetafilePoint(textOp.x, textOp.y)]);
        final opaqueRect = textOp.opaqueRect;
        if (opaqueRect != null) ensureBounds(opaqueRect.corners);
        ops.add(textOp);
        if ((textAlign & 0x01) != 0) {
          final logicalNext = metafileTextUpdatedCurrentPoint(rawTextOp);
          curX = logicalNext.x;
          curY = logicalNext.y;
          ensureBounds([mapPoint(logicalNext)]);
        }
      }
    } else if (func == _metaTextOut) {
      final rawTextOp = _readTextOut(
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
        textCharExtra,
        currentX: (textAlign & 0x01) != 0 ? curX : null,
        currentY: (textAlign & 0x01) != 0 ? curY : null,
      );
      if (rawTextOp != null) {
        final textOp = mapTextOp(rawTextOp);
        ensureBounds([MetafilePoint(textOp.x, textOp.y)]);
        ops.add(textOp);
        if ((textAlign & 0x01) != 0) {
          final logicalNext = metafileTextUpdatedCurrentPoint(rawTextOp);
          curX = logicalNext.x;
          curY = logicalNext.y;
          ensureBounds([mapPoint(logicalNext)]);
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
  required Uint8List? brushPatternBmpBytes,
  required int backgroundMode,
  required int backgroundColor,
  required MetafileRasterOperation rasterOperation,
  List<MetafilePathContour> additionalContours = const <MetafilePathContour>[],
  bool evenOddFill = false,
  bool asEllipse = false,
  double? cornerRadiusX,
  double? cornerRadiusY,
}) {
  final fill =
      brushStyle == 0 || brushStyle == 2 || brushPatternBmpBytes != null;
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
    fillPatternBmpBytes: fill ? brushPatternBmpBytes : null,
    additionalContours: additionalContours,
    evenOddFill: evenOddFill,
    rasterOperation: rasterOperation,
  );
}

bool _isDibHeaderAt(ByteData data, int offset, int end) {
  if (offset + 4 > end) return false;
  return switch (data.getUint32(offset, Endian.little)) {
    12 || 40 || 52 || 56 || 64 || 108 || 124 => true,
    _ => false,
  };
}

/// Convert the legacy monochrome Bitmap16 payload used by WMF pattern-brush
/// records into a top-down 1-bpp BMP. LibreOffice accepts this representation
/// only for Type=0, one plane and one bit per pixel, with white/black palette
/// entries and the high bit of each source byte as the leftmost pixel.
Uint8List? _wrapBitmap16Pattern(
  Uint8List bytes,
  int offset,
  int end,
  int headerSize,
) {
  if (headerSize < 10 || offset + headerSize > end) return null;
  final data = ByteData.sublistView(bytes);
  final type = data.getInt16(offset, Endian.little);
  final width = data.getInt16(offset + 2, Endian.little);
  final height = data.getInt16(offset + 4, Endian.little);
  final sourceStride = data.getInt16(offset + 6, Endian.little);
  final planes = data.getUint8(offset + 8);
  final bitsPerPixel = data.getUint8(offset + 9);
  final minimumStride = (width + 7) ~/ 8;
  final bitsStart = offset + headerSize;
  if (type != 0 ||
      width <= 0 ||
      height <= 0 ||
      width > 100000 ||
      height > 100000 ||
      width * height > 100000000 ||
      sourceStride < minimumStride ||
      planes != 1 ||
      bitsPerPixel != 1 ||
      sourceStride > end - bitsStart ||
      height > (end - bitsStart) ~/ sourceStride) {
    return null;
  }

  final targetStride = ((width + 31) ~/ 32) * 4;
  final dib = Uint8List(48 + targetStride * height);
  ByteData.sublistView(dib)
    ..setUint32(0, 40, Endian.little)
    ..setInt32(4, width, Endian.little)
    ..setInt32(8, -height, Endian.little)
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, 1, Endian.little)
    ..setUint32(20, targetStride * height, Endian.little)
    ..setUint32(32, 2, Endian.little);
  // RGBQUAD palette: zero bit is white, one bit is black.
  dib.setRange(40, 48, const <int>[255, 255, 255, 0, 0, 0, 0, 0]);
  for (var y = 0; y < height; y++) {
    final sourceRow = bitsStart + y * sourceStride;
    final targetRow = 48 + y * targetStride;
    dib.setRange(targetRow, targetRow + minimumStride, bytes, sourceRow);
  }
  return wrapDibAsBmp(dib);
}

_GdiRegion? _readWmfRegion(ByteData data, int offset, int end) {
  // Region header: next/type (4), object count (4), size/count/maxScan (6),
  // bounding RECT (8), followed by Scan objects.
  if (offset + 22 > end || data.getInt16(offset + 2, Endian.little) != 6) {
    return null;
  }
  final scanCount = data.getInt16(offset + 10, Endian.little);
  final maxScan = data.getInt16(offset + 12, Endian.little);
  if (scanCount < 0 || maxScan < 0 || scanCount > (end - offset - 22) ~/ 8) {
    return null;
  }
  var position = offset + 22;
  final rectangles = <List<MetafilePoint>>[];
  for (var scan = 0; scan < scanCount; scan++) {
    if (position + 8 > end) return null;
    final count = data.getUint16(position, Endian.little);
    final top = data.getUint16(position + 2, Endian.little).toDouble();
    final bottom = data.getUint16(position + 4, Endian.little).toDouble();
    if (count.isOdd || count > maxScan || count > (end - position - 8) ~/ 2) {
      return null;
    }
    var pointOffset = position + 6;
    for (var point = 0; point < count; point += 2) {
      final left = data.getUint16(pointOffset, Endian.little).toDouble();
      final right = data.getUint16(pointOffset + 2, Endian.little).toDouble();
      pointOffset += 4;
      if (left < right && top < bottom) {
        rectangles.add(<MetafilePoint>[
          MetafilePoint(left, top),
          MetafilePoint(right, top),
          MetafilePoint(right, bottom),
          MetafilePoint(left, bottom),
        ]);
      }
    }
    if (data.getUint16(pointOffset, Endian.little) != count) return null;
    position = pointOffset + 2;
  }
  return _GdiRegion(List<List<MetafilePoint>>.unmodifiable(rectangles));
}

List<List<MetafilePoint>> _frameRegionRectangles(
  List<List<MetafilePoint>> rectangles,
  double frameWidth,
  double frameHeight,
) {
  final bands = <List<MetafilePoint>>[];

  List<(double, double)> exposedSegments(
    double start,
    double end,
    Iterable<(double, double)> covered,
  ) {
    var segments = <(double, double)>[(start, end)];
    for (final interval in covered) {
      final next = <(double, double)>[];
      for (final segment in segments) {
        final cutStart = math.max(segment.$1, interval.$1);
        final cutEnd = math.min(segment.$2, interval.$2);
        if (cutStart >= cutEnd) {
          next.add(segment);
        } else {
          if (segment.$1 < cutStart) next.add((segment.$1, cutStart));
          if (cutEnd < segment.$2) next.add((cutEnd, segment.$2));
        }
      }
      segments = next;
    }
    return segments;
  }

  void addBand(double left, double top, double right, double bottom) {
    if (left >= right || top >= bottom) return;
    bands.add(<MetafilePoint>[
      MetafilePoint(left, top),
      MetafilePoint(right, top),
      MetafilePoint(right, bottom),
      MetafilePoint(left, bottom),
    ]);
  }

  for (final rectangle in rectangles) {
    if (rectangle.length < 4) continue;
    final left = rectangle[0].x;
    final top = rectangle[0].y;
    final right = rectangle[2].x;
    final bottom = rectangle[2].y;
    final horizontalFrame = math.min(frameHeight, bottom - top);
    final verticalFrame = math.min(frameWidth, right - left);
    final topCoverage = rectangles
        .where((other) => other.length >= 4 && other[2].y == top)
        .map((other) => (other[0].x, other[2].x));
    final bottomCoverage = rectangles
        .where((other) => other.length >= 4 && other[0].y == bottom)
        .map((other) => (other[0].x, other[2].x));
    final leftCoverage = rectangles
        .where((other) => other.length >= 4 && other[2].x == left)
        .map((other) => (other[0].y, other[2].y));
    final rightCoverage = rectangles
        .where((other) => other.length >= 4 && other[0].x == right)
        .map((other) => (other[0].y, other[2].y));
    for (final segment in exposedSegments(left, right, topCoverage)) {
      addBand(segment.$1, top, segment.$2, top + horizontalFrame);
    }
    for (final segment in exposedSegments(left, right, bottomCoverage)) {
      addBand(segment.$1, bottom - horizontalFrame, segment.$2, bottom);
    }
    for (final segment in exposedSegments(top, bottom, leftCoverage)) {
      addBand(left, segment.$1, left + verticalFrame, segment.$2);
    }
    for (final segment in exposedSegments(top, bottom, rightCoverage)) {
      addBand(right - verticalFrame, segment.$1, right, segment.$2);
    }
  }
  return bands;
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
    int textCharExtra,
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
  advancesX ??= _textSpacingAdvances(
    text,
    fontHeight,
    textCharExtra,
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
    int textCharExtra,
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
  final advancesX = _textSpacingAdvances(
    text,
    fontHeight,
    textCharExtra,
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

List<double>? _textSpacingAdvances(
  String text,
  double fontHeight,
  int charExtra,
  int breakExtra,
  int breakCount,
) {
  if (charExtra == 0 && (breakExtra == 0 || breakCount <= 0)) return null;
  final glyphs = text.runes.toList(growable: false);
  final breakIndices = <int>[
    for (var i = 0; i < glyphs.length; i++)
      if (glyphs[i] == 0x20) i,
  ];
  final usedBreaks = math.min(math.max(breakCount, 0), breakIndices.length);
  if (charExtra == 0 && usedBreaks == 0) return null;
  final base = math.max(fontHeight.abs(), 1.0) * 0.55 + charExtra;
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

List<int>? _readPaletteEntries(
  ByteData data,
  int offset,
  int end,
  int count,
) {
  if (count > (end - offset) ~/ 4) return null;
  return <int>[
    for (var i = 0; i < count; i++)
      0xff000000 |
          (data.getUint8(offset + i * 4) << 16) |
          (data.getUint8(offset + i * 4 + 1) << 8) |
          data.getUint8(offset + i * 4 + 2),
  ];
}

/// Resolve WMF ColorUsage into the RGB table expected by a standalone BMP.
///
/// DIB_PAL_COLORS stores WORD indexes in place of RGBQUAD/RGBTRIPLE entries;
/// DIB_PAL_INDICES omits the table and uses the pixel values as palette
/// indexes. Both forms depend on the logical palette selected in the DC.
Uint8List? _resolvePaletteDib(
  Uint8List dib,
  int colorUsage,
  _GdiPalette? palette,
) {
  if (colorUsage == 0) return dib; // DIB_RGB_COLORS
  if ((colorUsage != 1 && colorUsage != 2) ||
      palette == null ||
      dib.length < 12) {
    return null;
  }
  final data = ByteData.sublistView(dib);
  final headerSize = data.getUint32(0, Endian.little);
  final isCore = headerSize == 12;
  if (!isCore &&
      headerSize != 40 &&
      headerSize != 52 &&
      headerSize != 56 &&
      headerSize != 64 &&
      headerSize != 108 &&
      headerSize != 124) {
    return null;
  }
  if (headerSize > dib.length) return null;
  final bpp = data.getUint16(isCore ? 10 : 14, Endian.little);
  if (bpp <= 0 || bpp > 8) return null;
  var count = 1 << bpp;
  if (!isCore && dib.length >= 36) {
    final used = data.getUint32(32, Endian.little);
    if (used != 0) count = used;
  }
  if (count <= 0 || count > 256) return null;

  final sourceEntrySize = colorUsage == 1 ? 2 : 0;
  final sourceBitsOffset = headerSize + count * sourceEntrySize;
  if (sourceBitsOffset > dib.length) return null;
  final resolved = <int>[];
  if (colorUsage == 1) {
    for (var i = 0; i < count; i++) {
      final index = data.getUint16(headerSize + i * 2, Endian.little);
      if (index >= palette.entries.length) return null;
      resolved.add(palette.entries[index]);
    }
  } else {
    if (count > palette.entries.length) return null;
    resolved.addAll(palette.entries.take(count));
  }

  final targetEntrySize = isCore ? 3 : 4;
  final targetBitsOffset = headerSize + count * targetEntrySize;
  final out = Uint8List(
    targetBitsOffset + dib.length - sourceBitsOffset,
  );
  out.setRange(0, headerSize, dib);
  var target = headerSize;
  for (final argb in resolved) {
    out[target] = argb & 0xff;
    out[target + 1] = (argb >> 8) & 0xff;
    out[target + 2] = (argb >> 16) & 0xff;
    target += targetEntrySize;
  }
  out.setRange(targetBitsOffset, out.length, dib, sourceBitsOffset);
  return out;
}

int _rgbToArgb(int colorRef) {
  final r = colorRef & 0xff;
  final g = (colorRef >> 8) & 0xff;
  final b = (colorRef >> 16) & 0xff;
  return 0xFF000000 | (r << 16) | (g << 8) | b;
}

sealed class _GdiObject {}

class _GdiPen extends _GdiObject {
  _GdiPen(
    this.style,
    this.width,
    this.isCosmetic,
    this.color,
    this.dashPattern,
  );
  final int style;
  final double width;
  final bool isCosmetic;
  final int color;
  final List<double>? dashPattern;
}

class _GdiBrush extends _GdiObject {
  _GdiBrush(this.style, this.color, this.hatch, this.patternBmpBytes);
  final int style;
  final int color;
  final int hatch;
  final Uint8List? patternBmpBytes;

  bool get canFill => style == 0 || style == 2 || patternBmpBytes != null;
}

class _GdiRegion extends _GdiObject {
  _GdiRegion(this.rectangles);
  final List<List<MetafilePoint>> rectangles;
}

class _GdiPalette extends _GdiObject {
  _GdiPalette(List<int> entries) : entries = List<int>.of(entries);

  final List<int> entries;

  void replace(int start, List<int> replacements) {
    if (start < 0 || start >= entries.length) return;
    final count = math.min(replacements.length, entries.length - start);
    entries.setRange(start, start + count, replacements);
  }

  void resize(int length) {
    if (length < entries.length) {
      entries.removeRange(length, entries.length);
    } else if (length > entries.length) {
      entries.addAll(List<int>.filled(length - entries.length, 0xff000000));
    }
  }
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
    required this.penIsCosmetic,
    required this.penStyle,
    required this.penDashPattern,
    required this.brushColor,
    required this.brushStyle,
    required this.brushHatch,
    required this.brushPatternBmpBytes,
    required this.textColor,
    required this.backgroundMode,
    required this.backgroundColor,
    required this.textAlign,
    required this.mapMode,
    required this.polyFillMode,
    required this.rasterOperation,
    required this.bitmapFilter,
    required this.textBreakExtra,
    required this.textBreakCount,
    required this.textCharExtra,
    required this.fontFace,
    required this.fontHeight,
    required this.fontWeight,
    required this.fontItalic,
    required this.fontUnderline,
    required this.fontStrikeThrough,
    required this.fontEscapementDegrees,
    required this.fontEncoding,
    required this.selectedPalette,
    required this.winOrgX,
    required this.winOrgY,
    required this.winExtX,
    required this.winExtY,
    required this.viewportOrgX,
    required this.viewportOrgY,
    required this.viewportExtX,
    required this.viewportExtY,
    required this.logicalFrame,
    required this.curX,
    required this.curY,
  });

  final int penColor;
  final double penWidth;
  final bool penIsCosmetic;
  final int penStyle;
  final List<double>? penDashPattern;
  final int brushColor;
  final int brushStyle;
  final int brushHatch;
  final Uint8List? brushPatternBmpBytes;
  final int textColor;
  final int backgroundMode;
  final int backgroundColor;
  final int textAlign;
  final int mapMode;
  final int polyFillMode;
  final MetafileRasterOperation rasterOperation;
  final MetafileBitmapFilter bitmapFilter;
  final int textBreakExtra;
  final int textBreakCount;
  final int textCharExtra;
  final String? fontFace;
  final double fontHeight;
  final int fontWeight;
  final bool fontItalic;
  final bool fontUnderline;
  final bool fontStrikeThrough;
  final double fontEscapementDegrees;
  final VsdLegacyTextEncoding fontEncoding;
  final _GdiPalette? selectedPalette;
  final double winOrgX;
  final double winOrgY;
  final double? winExtX;
  final double? winExtY;
  final double viewportOrgX;
  final double viewportOrgY;
  final double? viewportExtX;
  final double? viewportExtY;
  final MetafileRect? logicalFrame;
  final double? curX;
  final double? curY;
}
