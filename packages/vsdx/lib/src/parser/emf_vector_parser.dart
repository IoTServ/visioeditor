/// Enhanced Metafile (EMF) vector records → [MetafileDrawing].
///
/// Prefer [extractEmfEmbeddedBitmap] when the file is a thin wrapper around a
/// DIB. This parser covers the GDI path used by OLE `\x02OlePres000` previews
/// and pure-vector ForeignData: pens/brushes, MOVETOEX / LINETO,
/// POLYBEZIER* / POLYDRAW* / POLYLINE* / POLYGON* (32/16-bit, incl. *TO),
/// POLYPOLYLINE* / POLYPOLYGON*, rectangle/ellipse, and EMF text records.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'emf_embedded_bitmap.dart';
import 'metafile_drawing.dart';
import 'vsd/vsd_text_codec.dart';

const int _emrHeader = 1;
const int _emrPolyBezier = 2;
const int _emrPolygon = 3;
const int _emrPolyline = 4;
const int _emrPolyBezierTo = 5;
const int _emrPolylineTo = 6;
const int _emrPolyPolyline = 7;
const int _emrPolyPolygon = 8;
const int _emrEof = 14;
const int _emrSetWindowExtEx = 9;
const int _emrSetWindowOrgEx = 10;
const int _emrSetViewportExtEx = 11;
const int _emrSetViewportOrgEx = 12;
const int _emrSetPixelV = 15;
const int _emrSetMapMode = 17;
const int _emrSetBkMode = 18;
const int _emrSetPolyFillMode = 19;
const int _emrSetRop2 = 20;
const int _emrSetTextAlign = 22;
const int _emrSetTextColor = 24;
const int _emrSetBkColor = 25;
const int _emrMoveToEx = 27;
const int _emrExcludeClipRect = 29;
const int _emrIntersectClipRect = 30;
const int _emrScaleViewportExtEx = 31;
const int _emrScaleWindowExtEx = 32;
const int _emrSaveDc = 33;
const int _emrRestoreDc = 34;
const int _emrSetWorldTransform = 35;
const int _emrModifyWorldTransform = 36;
const int _emrSelectObject = 37;
const int _emrCreatePen = 38;
const int _emrCreateBrushIndirect = 39;
const int _emrDeleteObject = 40;
const int _emrAngleArc = 41;
const int _emrEllipse = 42;
const int _emrRectangle = 43;
const int _emrRoundRect = 44;
const int _emrArc = 45;
const int _emrChord = 46;
const int _emrPie = 47;
const int _emrLineTo = 54;
const int _emrArcTo = 55;
const int _emrPolyDraw = 56;
const int _emrSetArcDirection = 57;
const int _emrBeginPath = 59;
const int _emrEndPath = 60;
const int _emrCloseFigure = 61;
const int _emrFillPath = 62;
const int _emrStrokeAndFillPath = 63;
const int _emrStrokePath = 64;
const int _emrAbortPath = 68;
const int _emrFillRgn = 71;
const int _emrPaintRgn = 74;
const int _emrBitBlt = 76;
const int _emrStretchBlt = 77;
const int _emrMaskBlt = 78;
const int _emrPlgBlt = 79;
const int _emrSetDibitsToDevice = 80;
const int _emrStretchDibits = 81;
const int _emrExtCreateFontIndirectW = 82;
const int _emrExtTextOutA = 83;
const int _emrExtTextOutW = 84;
const int _emrPolyBezier16 = 85;
const int _emrPolygon16 = 86;
const int _emrPolyline16 = 87;
const int _emrPolyBezierTo16 = 88;
const int _emrPolylineTo16 = 89;
const int _emrPolyPolyline16 = 90;
const int _emrPolyPolygon16 = 91;
const int _emrPolyDraw16 = 92;
const int _emrExtCreatePen = 95;
const int _emrPolyTextOutA = 96;
const int _emrPolyTextOutW = 97;
const int _emrSmallTextOut = 108;
const int _emrAlphaBlend = 114;
const int _emrTransparentBlt = 116;
const int _emrGradientFill = 118;

bool looksLikeEmf(Uint8List b) =>
    b.length > 0x2B &&
    b[0x28] == 0x20 &&
    b[0x29] == 0x45 &&
    b[0x2A] == 0x4D &&
    b[0x2B] == 0x46;

/// Locate an EMF header (type=1 + " EMF" signature) inside [bytes].
int? findEmfOffset(Uint8List bytes) {
  for (var o = 0; o + 0x2C <= bytes.length; o++) {
    if (bytes[o] != 1) continue;
    if (bytes[o + 0x28] == 0x20 &&
        bytes[o + 0x29] == 0x45 &&
        bytes[o + 0x2A] == 0x4D &&
        bytes[o + 0x2B] == 0x46) {
      return o;
    }
  }
  return null;
}

/// Parse EMF (or a buffer that embeds one) into a paint list.
MetafileDrawing? parseEmfDrawing(Uint8List bytes) {
  final start = looksLikeEmf(bytes) ? 0 : findEmfOffset(bytes);
  if (start == null) return null;
  final emf = start == 0 ? bytes : bytes.sublist(start);
  if (emf.length < 88) return null;
  final bd = ByteData.sublistView(emf);
  final type = bd.getUint32(0, Endian.little);
  final hdrSize = bd.getUint32(4, Endian.little);
  if (type != _emrHeader || hdrSize < 88) return null;

  var minX = bd.getInt32(8, Endian.little).toDouble();
  var minY = bd.getInt32(12, Endian.little).toDouble();
  var maxX = bd.getInt32(16, Endian.little).toDouble();
  var maxY = bd.getInt32(20, Endian.little).toDouble();
  if (maxX <= minX || maxY <= minY) {
    // Fall back to frame (himetric) if bounds empty — still need window ext.
    minX = 0;
    minY = 0;
    maxX = 1;
    maxY = 1;
  }
  var haveBounds = maxX > minX && maxY > minY;

  final deviceWidth = bd.getInt32(72, Endian.little).abs();
  final deviceHeight = bd.getInt32(76, Endian.little).abs();
  final millimeterWidth = bd.getInt32(80, Endian.little).abs();
  final millimeterHeight = bd.getInt32(84, Endian.little).abs();
  final pixelsPerMillimeterX = deviceWidth > 0 && millimeterWidth > 0
      ? deviceWidth / millimeterWidth
      : 96 / 25.4;
  final pixelsPerMillimeterY = deviceHeight > 0 && millimeterHeight > 0
      ? deviceHeight / millimeterHeight
      : 96 / 25.4;

  final objects = <_EmfObject?>[];
  // Stock object indices in EMF are 0x80000000 | stock; we only track created.
  var penColor = 0xFF000000;
  var penWidth = 1.0;
  var penStyle = 0;
  List<double>? penDashPattern;
  var brushColor = 0xFFFFFFFF;
  var brushStyle = 1;
  var brushHatch = 0;
  var textColor = 0xFF000000;
  var backgroundMode = 1; // TRANSPARENT
  var backgroundColor = 0xFFFFFFFF;
  var polyFillMode = 1; // ALTERNATE (even-odd)
  var rasterOperation = MetafileRasterOperation.overpaint;
  var textAlign = 0;
  String? fontFace;
  var fontHeight = 12.0;
  var fontWeight = 400;
  var fontItalic = false;
  var fontUnderline = false;
  var fontStrikeThrough = false;
  var fontEscapementDegrees = 0.0;
  var fontEncoding = VsdLegacyTextEncoding.ansi;
  var arcClockwise = false;
  var mapMode = 1; // MM_TEXT
  var windowOrgX = 0.0;
  var windowOrgY = 0.0;
  var windowExtX = 1.0;
  var windowExtY = 1.0;
  var viewportOrgX = 0.0;
  var viewportOrgY = 0.0;
  var viewportExtX = 1.0;
  var viewportExtY = 1.0;
  var worldTransform = const _EmfTransform.identity();
  final ops = <Object>[];
  MetafilePoint? curPt;
  var recordPath = false;
  final pathFigures = <_EmfPathFigure>[];
  final savedStates = <_EmfDcState>[];

  _EmfTransform pageTransform() {
    var sx = 1.0;
    var sy = 1.0;
    switch (mapMode) {
      case 2: // MM_LOMETRIC: 0.1 mm, Y-up
        sx = pixelsPerMillimeterX / 10;
        sy = -pixelsPerMillimeterY / 10;
        break;
      case 3: // MM_HIMETRIC: 0.01 mm, Y-up
        sx = pixelsPerMillimeterX / 100;
        sy = -pixelsPerMillimeterY / 100;
        break;
      case 4: // MM_LOENGLISH: 0.01 inch, Y-up
        sx = pixelsPerMillimeterX * 25.4 / 100;
        sy = -pixelsPerMillimeterY * 25.4 / 100;
        break;
      case 5: // MM_HIENGLISH: 0.001 inch, Y-up
        sx = pixelsPerMillimeterX * 25.4 / 1000;
        sy = -pixelsPerMillimeterY * 25.4 / 1000;
        break;
      case 6: // MM_TWIPS: 1/1440 inch, Y-up
        sx = pixelsPerMillimeterX * 25.4 / 1440;
        sy = -pixelsPerMillimeterY * 25.4 / 1440;
        break;
      case 7: // MM_ISOTROPIC
      case 8: // MM_ANISOTROPIC
        if (windowExtX != 0 && windowExtY != 0) {
          sx = viewportExtX / windowExtX;
          sy = viewportExtY / windowExtY;
          if (mapMode == 7) {
            final magnitude = math.min(sx.abs(), sy.abs());
            sx = sx.isNegative ? -magnitude : magnitude;
            sy = sy.isNegative ? -magnitude : magnitude;
          }
        }
        break;
    }
    final mapping = _EmfTransform(
      sx,
      0,
      0,
      sy,
      viewportOrgX - windowOrgX * sx,
      viewportOrgY - windowOrgY * sy,
    );
    return mapping.multipliedBy(worldTransform);
  }

  void changeTransform(void Function() update) {
    final before = pageTransform();
    update();
    final after = pageTransform();
    final inverse = before.inverse();
    if (inverse == null) return;
    final delta = inverse.multipliedBy(after);
    if (!delta.isIdentity) {
      ops.add(MetafileTransformOp(
        m11: delta.m11,
        m12: delta.m12,
        m21: delta.m21,
        m22: delta.m22,
        dx: delta.dx,
        dy: delta.dy,
      ));
    }
  }

  _EmfDcState captureState() => _EmfDcState(
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
        polyFillMode: polyFillMode,
        rasterOperation: rasterOperation,
        textAlign: textAlign,
        fontFace: fontFace,
        fontHeight: fontHeight,
        fontWeight: fontWeight,
        fontItalic: fontItalic,
        fontUnderline: fontUnderline,
        fontStrikeThrough: fontStrikeThrough,
        fontEscapementDegrees: fontEscapementDegrees,
        fontEncoding: fontEncoding,
        arcClockwise: arcClockwise,
        mapMode: mapMode,
        windowOrgX: windowOrgX,
        windowOrgY: windowOrgY,
        windowExtX: windowExtX,
        windowExtY: windowExtY,
        viewportOrgX: viewportOrgX,
        viewportOrgY: viewportOrgY,
        viewportExtX: viewportExtX,
        viewportExtY: viewportExtY,
        worldTransform: worldTransform,
        curPt: curPt,
        pathFigures: pathFigures
            .map((figure) => _EmfPathFigure.copy(figure))
            .toList(growable: false),
      );

  int restoreState(int savedDc) {
    if (savedDc == 0 || savedStates.isEmpty) return 0;
    final relative = savedDc < 0 ? savedDc : -1;
    final index = savedStates.length + relative;
    if (index < 0) {
      return 0;
    }
    final restoredCount = savedStates.length - index;
    final state = savedStates[index];
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
    polyFillMode = state.polyFillMode;
    rasterOperation = state.rasterOperation;
    textAlign = state.textAlign;
    fontFace = state.fontFace;
    fontHeight = state.fontHeight;
    fontWeight = state.fontWeight;
    fontItalic = state.fontItalic;
    fontUnderline = state.fontUnderline;
    fontStrikeThrough = state.fontStrikeThrough;
    fontEscapementDegrees = state.fontEscapementDegrees;
    fontEncoding = state.fontEncoding;
    arcClockwise = state.arcClockwise;
    mapMode = state.mapMode;
    windowOrgX = state.windowOrgX;
    windowOrgY = state.windowOrgY;
    windowExtX = state.windowExtX;
    windowExtY = state.windowExtY;
    viewportOrgX = state.viewportOrgX;
    viewportOrgY = state.viewportOrgY;
    viewportExtX = state.viewportExtX;
    viewportExtY = state.viewportExtY;
    worldTransform = state.worldTransform;
    curPt = state.curPt;
    pathFigures
      ..clear()
      ..addAll(state.pathFigures.map(_EmfPathFigure.copy));
    return restoredCount;
  }

  void ensurePts(Iterable<MetafilePoint> pts) {
    for (final p in pts) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
      haveBounds = true;
    }
  }

  void recordMoveTo(MetafilePoint point) {
    if (pathFigures.isEmpty || pathFigures.last.points.isNotEmpty) {
      pathFigures.add(_EmfPathFigure());
    }
    pathFigures.last.points.add(point);
  }

  void recordPathPoints(List<MetafilePoint> points, {required bool closed}) {
    if (points.isEmpty) return;
    if (closed) {
      pathFigures.add(_EmfPathFigure(points: points, closed: true));
      return;
    }
    if (pathFigures.isEmpty || pathFigures.last.closed) {
      pathFigures.add(_EmfPathFigure());
    }
    final target = pathFigures.last.points;
    var start = 0;
    if (target.isNotEmpty &&
        target.last.x == points.first.x &&
        target.last.y == points.first.y) {
      start = 1;
    }
    target.addAll(points.skip(start));
  }

  List<MetafilePoint> ellipsePoints(
    double left,
    double top,
    double right,
    double bottom,
  ) {
    final cx = (left + right) / 2;
    final cy = (top + bottom) / 2;
    final rx = (right - left).abs() / 2;
    final ry = (bottom - top).abs() / 2;
    return <MetafilePoint>[
      for (var i = 0; i < 48; i++)
        MetafilePoint(
          cx + rx * math.cos(2 * math.pi * i / 48),
          cy + ry * math.sin(2 * math.pi * i / 48),
        ),
    ];
  }

  List<MetafilePoint> roundedRectPoints(
    double left,
    double top,
    double right,
    double bottom,
    double radiusX,
    double radiusY,
  ) {
    final minRectX = math.min(left, right);
    final maxRectX = math.max(left, right);
    final minRectY = math.min(top, bottom);
    final maxRectY = math.max(top, bottom);
    final rx = math.min(radiusX.abs(), (maxRectX - minRectX) / 2);
    final ry = math.min(radiusY.abs(), (maxRectY - minRectY) / 2);
    if (rx == 0 || ry == 0) {
      return <MetafilePoint>[
        MetafilePoint(minRectX, minRectY),
        MetafilePoint(maxRectX, minRectY),
        MetafilePoint(maxRectX, maxRectY),
        MetafilePoint(minRectX, maxRectY),
      ];
    }

    final points = <MetafilePoint>[];
    void addCorner(double cx, double cy, double startAngle) {
      for (var i = 0; i <= 8; i++) {
        final angle = startAngle + math.pi * i / 16;
        points.add(MetafilePoint(
          cx + rx * math.cos(angle),
          cy + ry * math.sin(angle),
        ));
      }
    }

    addCorner(maxRectX - rx, minRectY + ry, -math.pi / 2);
    addCorner(maxRectX - rx, maxRectY - ry, 0);
    addCorner(minRectX + rx, maxRectY - ry, math.pi / 2);
    addCorner(minRectX + rx, minRectY + ry, math.pi);
    return points;
  }

  void paintRecordedPath({required bool stroke, required bool fill}) {
    final figures = pathFigures
        .where((figure) => figure.points.length >= 2)
        .toList(growable: false);
    pathFigures.clear();
    if (figures.isEmpty) return;
    for (final figure in figures) {
      ensurePts(figure.points);
    }
    final useStroke = stroke && (penStyle & 0x0f) != 5;
    final useFill = fill && (brushStyle == 0 || brushStyle == 2);
    if (!useStroke && !useFill) return;
    final first = figures.first;
    ops.add(MetafilePathOp(
      points: List<MetafilePoint>.of(first.points),
      closed: first.closed && first.points.length > 2,
      fill: useFill,
      stroke: useStroke,
      fillArgb: useFill ? brushColor : 0,
      strokeArgb: useStroke ? penColor : 0,
      strokeWidth: penWidth,
      strokeDashPattern: penDashPattern,
      fillHatch: useFill && brushStyle == 2 ? brushHatch : null,
      fillBackgroundArgb: useFill && brushStyle == 2 && backgroundMode == 2
          ? backgroundColor
          : null,
      additionalContours: <MetafilePathContour>[
        for (final figure in figures.skip(1))
          MetafilePathContour(
            points: List<MetafilePoint>.of(figure.points),
            closed: figure.closed && figure.points.length > 2,
          ),
      ],
      evenOddFill: polyFillMode != 2,
      rasterOperation: rasterOperation,
    ));
  }

  void emitBezier(
    List<MetafilePoint> ctrl, {
    bool updateCurrent = false,
  }) {
    if (ctrl.length < 4) return;
    final dense = densifyPolyBezier(ctrl);
    ensurePts(dense);
    if (updateCurrent) curPt = dense.last;
    if (recordPath) {
      recordPathPoints(dense, closed: false);
      return;
    }
    final stroke = (penStyle & 0x0f) != 5;
    if (stroke) {
      ops.add(MetafilePathOp(
        points: dense,
        closed: false,
        fill: false,
        stroke: true,
        fillArgb: 0,
        strokeArgb: penColor,
        strokeWidth: penWidth,
        strokeDashPattern: penDashPattern,
        evenOddFill: polyFillMode != 2,
        rasterOperation: rasterOperation,
      ));
    }
  }

  void emitPolyline(
    List<MetafilePoint> pts, {
    required bool closed,
    bool allowFill = true,
    bool recordIfActive = true,
    bool updateCurrent = false,
  }) {
    if (pts.length < 2) return;
    ensurePts(pts);
    if (updateCurrent) curPt = pts.last;
    if (recordPath && recordIfActive) {
      recordPathPoints(pts, closed: closed);
      return;
    }
    final fill = allowFill && closed && (brushStyle == 0 || brushStyle == 2);
    final stroke = (penStyle & 0x0f) != 5;
    if (fill || stroke) {
      ops.add(MetafilePathOp(
        points: pts,
        closed: closed,
        fill: fill,
        stroke: stroke,
        fillArgb: fill ? brushColor : 0,
        strokeArgb: stroke ? penColor : 0,
        strokeWidth: penWidth,
        strokeDashPattern: penDashPattern,
        fillHatch: brushStyle == 2 ? brushHatch : null,
        fillBackgroundArgb:
            brushStyle == 2 && backgroundMode == 2 ? backgroundColor : null,
        evenOddFill: polyFillMode != 2,
        rasterOperation: rasterOperation,
      ));
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
  }) {
    if (width == 0 || height == 0) return;
    final points = <MetafilePoint>[
      MetafilePoint(x, y),
      MetafilePoint(x + width, y),
      MetafilePoint(x + width, y + height),
      MetafilePoint(x, y + height),
    ];
    ensurePts(points);
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
      evenOddFill: polyFillMode != 2,
      rasterOperation: rasterOperation,
    ));
  }

  bool emitRasterOperationFill(
    int rasterOperation,
    double x,
    double y,
    double width,
    double height,
  ) {
    if (rasterOperation == 0x00f00021 && (brushStyle == 0 || brushStyle == 2)) {
      emitRasterFill(
        x,
        y,
        width,
        height,
        color: brushColor,
        hatch: brushStyle == 2 ? brushHatch : null,
        hatchBackground:
            brushStyle == 2 && backgroundMode == 2 ? backgroundColor : null,
      );
      return true;
    }
    if (rasterOperation == 0x00000042 || rasterOperation == 0x00ff0062) {
      emitRasterFill(
        x,
        y,
        width,
        height,
        color: rasterOperation == 0x00000042 ? 0xff000000 : 0xffffffff,
      );
      return true;
    }
    return false;
  }

  void emitEmbeddedBitmap({
    required int recordStart,
    required int recordEnd,
    required double destinationX,
    required double destinationY,
    required double destinationWidth,
    required double destinationHeight,
    required int sourceX,
    required int sourceY,
    required int sourceWidth,
    required int sourceHeight,
    required int usage,
    required int offBmi,
    required int cbBmi,
    required int offBits,
    required int cbBits,
    required int rasterOperation,
    double opacity = 1,
    bool preserveAlpha = false,
    int? transparentArgb,
    List<MetafilePoint>? destinationParallelogram,
    Uint8List? maskBmi,
    Uint8List? maskBits,
    int maskX = 0,
    int maskY = 0,
  }) {
    if (destinationWidth == 0 || destinationHeight == 0) return;
    if (emitRasterOperationFill(
      rasterOperation,
      destinationX,
      destinationY,
      destinationWidth,
      destinationHeight,
    )) {
      return;
    }
    if (usage != 0 || cbBmi < 12 || cbBits == 0) return;
    final recordSize = recordEnd - recordStart;
    bool validRange(int offset, int length) =>
        offset >= 8 &&
        length > 0 &&
        offset <= recordSize &&
        length <= recordSize - offset;
    if (!validRange(offBmi, cbBmi) || !validRange(offBits, cbBits)) return;
    final bmi = Uint8List.sublistView(
      emf,
      recordStart + offBmi,
      recordStart + offBmi + cbBmi,
    );
    final bits = Uint8List.sublistView(
      emf,
      recordStart + offBits,
      recordStart + offBits + cbBits,
    );
    final dimensions = dibDimensions(bmi);
    if (dimensions == null) return;
    final pixelWidth = dimensions.$1;
    final pixelHeight = dimensions.$2;
    MetafileRect? source;
    if (sourceWidth != 0 && sourceHeight != 0) {
      final directed = MetafileRect(
        sourceX.toDouble(),
        sourceY.toDouble(),
        (sourceX + sourceWidth).toDouble(),
        (sourceY + sourceHeight).toDouble(),
      );
      if (directed.minX >= 0 &&
          directed.minY >= 0 &&
          directed.maxX <= pixelWidth &&
          directed.maxY <= pixelHeight) {
        source = directed;
      }
    }
    final bmp = packDibAsBmp(
      bmi,
      bits,
      preserveAlpha: preserveAlpha,
      transparentArgb: transparentArgb,
      maskBmi: maskBmi,
      maskBits: maskBits,
      sourceX: sourceX,
      sourceY: sourceY,
      maskX: maskX,
      maskY: maskY,
    );
    if (bmp == null) return;
    final destination = MetafileRect(
      destinationX,
      destinationY,
      destinationX + destinationWidth,
      destinationY + destinationHeight,
    );
    final parallelogram = destinationParallelogram == null
        ? null
        : List<MetafilePoint>.unmodifiable(destinationParallelogram);
    if (parallelogram != null && parallelogram.length == 3) {
      final a = parallelogram[0];
      final b = parallelogram[1];
      final c = parallelogram[2];
      ensurePts(<MetafilePoint>[
        a,
        b,
        c,
        MetafilePoint(b.x + c.x - a.x, b.y + c.y - a.y),
      ]);
    } else {
      ensurePts(destination.corners);
    }
    ops.add(MetafileBitmapOp(
      bmpBytes: bmp,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      destination: destination,
      source: source,
      destinationParallelogram:
          parallelogram != null && parallelogram.length == 3
              ? parallelogram
              : null,
      rasterOperation: rasterOperation,
      opacity: opacity,
    ));
  }

  void emitPolyDraw(List<MetafilePoint> points, List<int> pointTypes) {
    if (points.length != pointTypes.length || points.isEmpty) return;
    const moveTo = 0x06;
    const lineTo = 0x02;
    const bezierTo = 0x04;
    const closeFigure = 0x01;

    // Like LibreOffice, reject the whole record before changing the current
    // point when a Bezier run is not made of complete (control, control, end)
    // triples. A damaged preview must not abort parsing later EMF records.
    var bezierCount = 0;
    for (final pointType in pointTypes) {
      if (pointType != moveTo && (pointType & bezierTo) != 0) {
        bezierCount++;
      } else if (bezierCount % 3 == 0) {
        bezierCount = 0;
      } else {
        return;
      }
    }
    if (bezierCount % 3 != 0) return;

    var figure = <MetafilePoint>[];
    void flushFigure({required bool closed}) {
      if (figure.length >= 2) {
        emitPolyline(
          List<MetafilePoint>.of(figure),
          closed: closed && figure.length > 2,
          allowFill: false,
          recordIfActive: false,
        );
      }
      figure = <MetafilePoint>[];
    }

    var i = 0;
    while (i < points.length) {
      final point = points[i];
      final pointType = pointTypes[i];
      if (pointType == moveTo) {
        flushFigure(closed: false);
        figure.add(point);
        curPt = point;
        i++;
        continue;
      }
      if ((pointType & lineTo) != 0) {
        if (figure.isEmpty) {
          figure.add(curPt ?? const MetafilePoint(0, 0));
        }
        figure.add(point);
        curPt = point;
        if ((pointType & closeFigure) != 0) {
          flushFigure(closed: true);
        }
        i++;
        continue;
      }
      if ((pointType & bezierTo) != 0 && i + 2 < points.length) {
        if (figure.isEmpty) {
          figure.add(curPt ?? const MetafilePoint(0, 0));
        }
        final dense = densifyPolyBezier(<MetafilePoint>[
          figure.last,
          points[i],
          points[i + 1],
          points[i + 2],
        ]);
        figure.addAll(dense.skip(1));
        curPt = points[i + 2];
        final close = (pointTypes[i + 2] & closeFigure) != 0;
        i += 3;
        if (close) flushFigure(closed: true);
        continue;
      }
      i++;
    }
    flushFigure(closed: false);
  }

  void emitArc(
    List<MetafilePoint> arc, {
    required bool closed,
    required bool fill,
    bool connectCurrent = false,
    bool updateCurrent = false,
  }) {
    if (arc.length < 2) return;
    final points = connectCurrent
        ? <MetafilePoint>[curPt ?? const MetafilePoint(0, 0), ...arc]
        : arc;
    ensurePts(points);
    if (recordPath) {
      recordPathPoints(points, closed: closed);
      if (updateCurrent) curPt = arc.last;
      return;
    }
    final stroke = (penStyle & 0x0f) != 5;
    final useFill = fill && (brushStyle == 0 || brushStyle == 2);
    if (stroke || useFill) {
      ops.add(MetafilePathOp(
        points: points,
        closed: closed,
        fill: useFill,
        stroke: stroke,
        fillArgb: useFill ? brushColor : 0,
        strokeArgb: stroke ? penColor : 0,
        strokeWidth: penWidth,
        strokeDashPattern: penDashPattern,
        fillHatch: useFill && brushStyle == 2 ? brushHatch : null,
        fillBackgroundArgb: useFill && brushStyle == 2 && backgroundMode == 2
            ? backgroundColor
            : null,
        evenOddFill: polyFillMode != 2,
        rasterOperation: rasterOperation,
      ));
    }
    if (updateCurrent) curPt = arc.last;
  }

  void emitText(
    int recordOffset,
    int textOff,
    int recEnd, {
    required bool ansi,
  }) {
    // EMRTEXT: reference(8), count(4), string offset(4), options(4),
    // optional rectangle(16), and output-Dx offset(4).
    if (textOff + 40 > recEnd) return;
    final recordX = bd.getInt32(textOff, Endian.little).toDouble();
    final recordY = bd.getInt32(textOff + 4, Endian.little).toDouble();
    final useCurrentPoint = (textAlign & 0x01) != 0 && curPt != null;
    final x = useCurrentPoint ? curPt!.x : recordX;
    final y = useCurrentPoint ? curPt!.y : recordY;
    final sourceLength = bd.getUint32(textOff + 8, Endian.little);
    if (sourceLength >= 4096) return;
    final offString = bd.getUint32(textOff + 12, Endian.little);
    final options = bd.getUint32(textOff + 16, Endian.little);
    final recordRect = (options & 0x0006) != 0
        ? MetafileRect(
            bd.getInt32(textOff + 20, Endian.little).toDouble(),
            bd.getInt32(textOff + 24, Endian.little).toDouble(),
            bd.getInt32(textOff + 28, Endian.little).toDouble(),
            bd.getInt32(textOff + 32, Endian.little).toDouble(),
          )
        : null;
    final offDx = bd.getUint32(textOff + 36, Endian.little);
    if (offString > recEnd - recordOffset) return;
    final strAt = recordOffset + offString;

    late final String text;
    late final List<int> sourceUnitsPerRune;
    if (ansi) {
      if (sourceLength > recEnd - strAt) return;
      final raw = emf.sublist(strAt, strAt + sourceLength);
      text =
          decodeWindowsLegacyText(raw, fontEncoding).replaceAll('\u0000', '');
      sourceUnitsPerRune = windowsLegacyCharacterByteLengths(
        raw,
        fontEncoding,
      );
    } else {
      if (sourceLength > (recEnd - strAt) ~/ 2) return;
      final codes = <int>[
        for (var i = 0; i < sourceLength; i++)
          bd.getUint16(strAt + i * 2, Endian.little),
      ];
      text = String.fromCharCodes(codes).replaceAll('\u0000', '');
      sourceUnitsPerRune = <int>[
        for (final rune in text.runes) rune > 0xffff ? 2 : 1,
      ];
    }
    if (text.trim().isEmpty &&
        !((options & 0x0002) != 0 && recordRect != null)) {
      return;
    }

    List<double>? advancesX;
    List<double>? advancesY;
    final hasVerticalAdvances = (options & 0x2000) != 0; // ETO_PDY
    final valuesPerUnit = hasVerticalAdvances ? 2 : 1;
    final advanceAt = recordOffset + offDx;
    final mappedSourceLength = sourceUnitsPerRune.fold<int>(0, (a, b) => a + b);
    if (offDx > 0 &&
        mappedSourceLength == sourceLength &&
        sourceUnitsPerRune.length == text.runes.length &&
        offDx <= recEnd - recordOffset &&
        sourceLength <= (recEnd - advanceAt) ~/ (valuesPerUnit * 4)) {
      final unitX = <double>[];
      final unitY = hasVerticalAdvances ? <double>[] : null;
      var p = advanceAt;
      for (var i = 0; i < sourceLength; i++) {
        unitX.add(bd.getInt32(p, Endian.little).toDouble());
        p += 4;
        if (unitY != null) {
          unitY.add(bd.getInt32(p, Endian.little).toDouble());
          p += 4;
        }
      }
      var sourceIndex = 0;
      final runeX = <double>[];
      final runeY = unitY == null ? null : <double>[];
      for (final unitCount in sourceUnitsPerRune) {
        var dx = 0.0;
        var dy = 0.0;
        for (var i = 0; i < unitCount; i++) {
          dx += unitX[sourceIndex + i];
          if (unitY != null) dy += unitY[sourceIndex + i];
        }
        runeX.add(dx);
        runeY?.add(dy);
        sourceIndex += unitCount;
      }
      advancesX = List<double>.unmodifiable(runeX);
      advancesY = runeY == null ? null : List<double>.unmodifiable(runeY);
    }

    final point = MetafilePoint(x, y);
    ensurePts([point]);
    final textOp = MetafileTextOp(
      text: text,
      x: x,
      y: y,
      fontHeight: fontHeight,
      argb: textColor,
      face: fontFace,
      align: textAlign,
      backgroundArgb: backgroundMode == 2 || (options & 0x0002) != 0
          ? backgroundColor
          : null,
      opaqueRect: (options & 0x0002) != 0 ? recordRect : null,
      clipRect: (options & 0x0004) != 0 ? recordRect : null,
      advancesX: advancesX,
      advancesY: advancesY,
      fontWeight: fontWeight,
      italic: fontItalic,
      underline: fontUnderline,
      strikeThrough: fontStrikeThrough,
      escapementDegrees: fontEscapementDegrees,
    );
    final opaqueRect = textOp.opaqueRect;
    if (opaqueRect != null) ensurePts(opaqueRect.corners);
    ops.add(textOp);
    if ((textAlign & 0x01) != 0) {
      curPt = metafileTextUpdatedCurrentPoint(textOp);
      ensurePts([curPt!]);
    }
  }

  void emitSmallText(int params, int recEnd) {
    // EMR_SMALLTEXTOUT stores the string inline after its fixed fields and an
    // optional rectangle. Unlike EMRTEXT, ETO_NO_RECT removes the rectangle
    // from the binary layout and ETO_SMALL_CHARS selects the active ANSI
    // charset instead of UTF-16LE.
    if (params + 28 > recEnd) return;
    final recordX = bd.getInt32(params, Endian.little).toDouble();
    final recordY = bd.getInt32(params + 4, Endian.little).toDouble();
    final sourceLength = bd.getUint32(params + 8, Endian.little);
    if (sourceLength >= 4096) return;
    final options = bd.getUint32(params + 12, Endian.little);
    final noRect = (options & 0x0100) != 0; // ETO_NO_RECT
    final smallChars = (options & 0x0200) != 0; // ETO_SMALL_CHARS
    var stringAt = params + 28;
    MetafileRect? recordRect;
    if (!noRect) {
      if (stringAt + 16 > recEnd) return;
      recordRect = MetafileRect(
        bd.getInt32(stringAt, Endian.little).toDouble(),
        bd.getInt32(stringAt + 4, Endian.little).toDouble(),
        bd.getInt32(stringAt + 8, Endian.little).toDouble(),
        bd.getInt32(stringAt + 12, Endian.little).toDouble(),
      );
      stringAt += 16;
    }

    late final String text;
    if (smallChars) {
      if (sourceLength > recEnd - stringAt) return;
      text = decodeWindowsLegacyText(
        emf.sublist(stringAt, stringAt + sourceLength),
        fontEncoding,
      ).replaceAll('\u0000', '');
    } else {
      if (sourceLength > (recEnd - stringAt) ~/ 2) return;
      text = String.fromCharCodes(<int>[
        for (var i = 0; i < sourceLength; i++)
          bd.getUint16(stringAt + i * 2, Endian.little),
      ]).replaceAll('\u0000', '');
    }
    if (text.trim().isEmpty &&
        !((options & 0x0002) != 0 && recordRect != null)) {
      return;
    }

    final useCurrentPoint = (textAlign & 0x01) != 0 && curPt != null;
    final x = useCurrentPoint ? curPt!.x : recordX;
    final y = useCurrentPoint ? curPt!.y : recordY;
    final textOp = MetafileTextOp(
      text: text,
      x: x,
      y: y,
      fontHeight: fontHeight,
      argb: textColor,
      face: fontFace,
      align: textAlign,
      // LibreOffice temporarily forces transparent text background when
      // ETO_NO_RECT is set, even if the DC background mode is OPAQUE.
      backgroundArgb: noRect
          ? null
          : backgroundMode == 2 || (options & 0x0002) != 0
              ? backgroundColor
              : null,
      opaqueRect: (options & 0x0002) != 0 ? recordRect : null,
      clipRect: (options & 0x0004) != 0 ? recordRect : null,
      fontWeight: fontWeight,
      italic: fontItalic,
      underline: fontUnderline,
      strikeThrough: fontStrikeThrough,
      escapementDegrees: fontEscapementDegrees,
    );
    ensurePts(<MetafilePoint>[MetafilePoint(x, y)]);
    final opaqueRect = textOp.opaqueRect;
    if (opaqueRect != null) ensurePts(opaqueRect.corners);
    ops.add(textOp);
    if ((textAlign & 0x01) != 0) {
      curPt = metafileTextUpdatedCurrentPoint(textOp);
      ensurePts(<MetafilePoint>[curPt!]);
    }
  }

  _EmfBrush? regionBrush(int? handle) {
    if (handle == null) {
      return _EmfBrush(brushStyle, brushColor, brushHatch);
    }
    if (handle & 0x80000000 != 0) {
      final stock = handle & 0x7fffffff;
      const colors = <int>[
        0xFFFFFFFF,
        0xFFC0C0C0,
        0xFF808080,
        0xFF666666,
        0xFF000000,
      ];
      if (stock < colors.length) return _EmfBrush(0, colors[stock], 0);
      return null; // NULL_BRUSH and non-brush stock objects do not paint.
    }
    if (handle >= objects.length) return null;
    final object = objects[handle];
    return object is _EmfBrush ? object : null;
  }

  void emitRegion(int regionStart, int regionLength, int? brushHandle) {
    final brush = regionBrush(brushHandle);
    if (brush == null || (brush.style != 0 && brush.style != 2)) return;
    final contours = _readEmfRegionContours(
      bd,
      regionStart,
      regionLength,
      emf.length,
    );
    if (contours.isEmpty) return;
    for (final contour in contours) {
      ensurePts(contour);
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
      additionalContours: <MetafilePathContour>[
        for (final contour in contours.skip(1))
          MetafilePathContour(points: contour, closed: true),
      ],
      // RGNDATA rectangles describe their union. A non-zero fill prevents
      // overlapping bands from punching accidental even-odd holes.
      evenOddFill: false,
      rasterOperation: rasterOperation,
    ));
  }

  var offset = hdrSize;
  while (offset + 8 <= emf.length) {
    final t = bd.getUint32(offset, Endian.little);
    final size = bd.getUint32(offset + 4, Endian.little);
    if (size < 8 || offset + size > emf.length) break;
    final params = offset + 8;
    final recEnd = offset + size;

    if (t == _emrEof) break;

    if (t == _emrSaveDc) {
      savedStates.add(captureState());
      ops.add(const MetafileSaveDcOp());
    } else if (t == _emrRestoreDc && params + 4 <= recEnd) {
      final restoredCount = restoreState(bd.getInt32(params, Endian.little));
      if (restoredCount > 0) {
        ops.add(MetafileRestoreDcOp(count: restoredCount));
      }
    } else if (t == _emrSetWindowOrgEx && params + 8 <= recEnd) {
      changeTransform(() {
        windowOrgX = bd.getInt32(params, Endian.little).toDouble();
        windowOrgY = bd.getInt32(params + 4, Endian.little).toDouble();
      });
    } else if (t == _emrSetWindowExtEx && params + 8 <= recEnd) {
      final cx = bd.getInt32(params, Endian.little).toDouble();
      final cy = bd.getInt32(params + 4, Endian.little).toDouble();
      if (cx != 0 && cy != 0) {
        changeTransform(() {
          windowExtX = cx;
          windowExtY = cy;
        });
      }
      if (!haveBounds && cx.abs() > 1 && cy.abs() > 1) {
        minX = 0;
        minY = 0;
        maxX = cx.abs();
        maxY = cy.abs();
        haveBounds = true;
      }
    } else if (t == _emrSetViewportOrgEx && params + 8 <= recEnd) {
      changeTransform(() {
        viewportOrgX = bd.getInt32(params, Endian.little).toDouble();
        viewportOrgY = bd.getInt32(params + 4, Endian.little).toDouble();
      });
    } else if (t == _emrSetViewportExtEx && params + 8 <= recEnd) {
      final cx = bd.getInt32(params, Endian.little).toDouble();
      final cy = bd.getInt32(params + 4, Endian.little).toDouble();
      if (cx != 0 && cy != 0) {
        changeTransform(() {
          viewportExtX = cx;
          viewportExtY = cy;
        });
      }
    } else if ((t == _emrScaleWindowExtEx || t == _emrScaleViewportExtEx) &&
        params + 16 <= recEnd) {
      final xDenominator = bd.getInt32(params + 4, Endian.little);
      final yDenominator = bd.getInt32(params + 12, Endian.little);
      if (xDenominator != 0 && yDenominator != 0) {
        final xScale = bd.getInt32(params, Endian.little) / xDenominator;
        final yScale = bd.getInt32(params + 8, Endian.little) / yDenominator;
        changeTransform(() {
          if (t == _emrScaleWindowExtEx) {
            windowExtX *= xScale;
            windowExtY *= yScale;
          } else {
            viewportExtX *= xScale;
            viewportExtY *= yScale;
          }
        });
      }
    } else if (t == _emrSetMapMode && params + 4 <= recEnd) {
      final mode = bd.getInt32(params, Endian.little);
      if (mode >= 1 && mode <= 8) {
        changeTransform(() => mapMode = mode);
      }
    } else if (t == _emrSetWorldTransform && params + 24 <= recEnd) {
      final transform = _EmfTransform.read(bd, params);
      if (transform != null) {
        changeTransform(() => worldTransform = transform);
      }
    } else if (t == _emrModifyWorldTransform && params + 28 <= recEnd) {
      final transform = _EmfTransform.read(bd, params);
      final mode = bd.getUint32(params + 24, Endian.little);
      if (transform != null && mode >= 1 && mode <= 4) {
        changeTransform(() {
          worldTransform = switch (mode) {
            1 => const _EmfTransform.identity(),
            2 => transform.multipliedBy(worldTransform),
            3 => worldTransform.multipliedBy(transform),
            4 => transform,
            _ => worldTransform,
          };
        });
      }
    } else if (t == _emrSetPixelV && params + 12 <= recEnd) {
      final x = bd.getInt32(params, Endian.little).toDouble();
      final y = bd.getInt32(params + 4, Endian.little).toDouble();
      ops.add(MetafilePixelOp(
        x: x,
        y: y,
        argb: _rgbToArgb(bd.getUint32(params + 8, Endian.little)),
      ));
      // A GDI pixel occupies the half-open device cell [x,x+1)×[y,y+1).
      ensurePts(<MetafilePoint>[
        MetafilePoint(x, y),
        MetafilePoint(x + 1, y + 1),
      ]);
    } else if (t == _emrSetBkMode && params + 4 <= recEnd) {
      backgroundMode = bd.getUint32(params, Endian.little);
    } else if (t == _emrSetPolyFillMode && params + 4 <= recEnd) {
      final mode = bd.getUint32(params, Endian.little);
      if (mode == 1 || mode == 2) polyFillMode = mode;
    } else if (t == _emrSetRop2 && params + 4 <= recEnd) {
      rasterOperation = switch (bd.getUint32(params, Endian.little)) {
        6 => MetafileRasterOperation.invert, // R2_NOT
        7 => MetafileRasterOperation.xor, // R2_XORPEN
        11 => MetafileRasterOperation.nop, // R2_NOP
        _ => MetafileRasterOperation.overpaint,
      };
    } else if (t == _emrSetBkColor && params + 4 <= recEnd) {
      backgroundColor = _rgbToArgb(bd.getUint32(params, Endian.little));
    } else if ((t == _emrExcludeClipRect || t == _emrIntersectClipRect) &&
        params + 16 <= recEnd) {
      ops.add(MetafileClipRectOp(
        rect: MetafileRect(
          bd.getInt32(params, Endian.little).toDouble(),
          bd.getInt32(params + 4, Endian.little).toDouble(),
          bd.getInt32(params + 8, Endian.little).toDouble(),
          bd.getInt32(params + 12, Endian.little).toDouble(),
        ),
        mode: t == _emrIntersectClipRect
            ? MetafileClipCombineMode.intersect
            : MetafileClipCombineMode.exclude,
      ));
    } else if (t == _emrSetArcDirection && params + 4 <= recEnd) {
      arcClockwise = bd.getUint32(params, Endian.little) == 2;
    } else if (t == _emrSetTextColor && params + 4 <= recEnd) {
      textColor = _rgbToArgb(bd.getUint32(params, Endian.little));
    } else if (t == _emrSetTextAlign && params + 4 <= recEnd) {
      textAlign = bd.getUint32(params, Endian.little);
    } else if (t == _emrFillRgn && params + 24 <= recEnd) {
      // Bounds (16), cbRgnData (4), ihBrush (4), RGNDATA. LibreOffice uses
      // the referenced brush temporarily without changing the selected DC
      // brush, then paints the complete rectangle region as one poly-polygon.
      final regionLength = bd.getUint32(params + 16, Endian.little);
      final brushHandle = bd.getUint32(params + 20, Endian.little);
      if (regionLength <= recEnd - (params + 24)) {
        emitRegion(params + 24, regionLength, brushHandle);
      }
    } else if (t == _emrPaintRgn && params + 20 <= recEnd) {
      // PAINTRGN has no brush handle; it uses the brush selected in the DC.
      final regionLength = bd.getUint32(params + 16, Endian.little);
      if (regionLength <= recEnd - (params + 20)) {
        emitRegion(params + 20, regionLength, null);
      }
    } else if (t == _emrCreatePen && params + 20 <= recEnd) {
      final ih = bd.getInt32(params, Endian.little);
      final style = bd.getUint32(params + 4, Endian.little);
      final width = bd.getInt32(params + 8, Endian.little).abs().toDouble();
      final color = _rgbToArgb(bd.getUint32(params + 16, Endian.little));
      _store(
        objects,
        ih,
        _EmfPen(
          style,
          width == 0 ? 1.0 : width,
          color,
          metafileGdiDashPattern(style, width),
        ),
      );
    } else if (t == _emrExtCreatePen && params + 44 <= recEnd) {
      final ih = bd.getInt32(params, Endian.little);
      final style = bd.getUint32(params + 20, Endian.little);
      final width = bd.getUint32(params + 24, Endian.little).toDouble();
      final brushStyle = bd.getUint32(params + 28, Endian.little);
      var color = _rgbToArgb(bd.getUint32(params + 32, Endian.little));
      final hatch = bd.getInt32(params + 36, Endian.little);
      if (brushStyle == 2) {
        if (hatch == 8 || hatch == 9) color = textColor;
        if (hatch == 10 || hatch == 11) color = backgroundColor;
      }
      _store(
        objects,
        ih,
        _EmfPen(
          style,
          width == 0 ? 1.0 : width,
          color,
          metafileGdiDashPattern(style, width),
        ),
      );
    } else if (t == _emrCreateBrushIndirect && params + 16 <= recEnd) {
      final ih = bd.getInt32(params, Endian.little);
      final style = bd.getUint32(params + 4, Endian.little);
      final color = _rgbToArgb(bd.getUint32(params + 8, Endian.little));
      final hatch = bd.getUint32(params + 12, Endian.little);
      _store(objects, ih, _EmfBrush(style, color, hatch));
    } else if (t == _emrExtCreateFontIndirectW && params + 8 <= recEnd) {
      final ih = bd.getInt32(params, Endian.little);
      // EXTLOGFONTW starts at params+4; elfLogFont.lfHeight at +0 of that.
      if (params + 4 + 4 <= recEnd) {
        final height = bd
            .getInt32(params + 4, Endian.little)
            .abs()
            .toDouble()
            .clamp(1.0, 2000.0);
        final escapement = params + 16 <= recEnd
            ? bd.getInt32(params + 12, Endian.little) / 10.0
            : 0.0;
        final weight = params + 24 <= recEnd
            ? bd.getInt32(params + 20, Endian.little)
            : 400;
        final italic = params + 25 <= recEnd && bd.getUint8(params + 24) != 0;
        final underline =
            params + 26 <= recEnd && bd.getUint8(params + 25) != 0;
        final strikeThrough =
            params + 27 <= recEnd && bd.getUint8(params + 26) != 0;
        final charset = params + 28 <= recEnd ? bd.getUint8(params + 27) : 0;
        String? face;
        // lfFaceName is WCHAR[32] at offset 28 within LOGFONTW (= params+4+28).
        final faceOff = params + 4 + 28;
        if (faceOff + 2 <= recEnd) {
          final codes = <int>[];
          for (var i = 0; i < 32 && faceOff + i * 2 + 1 < recEnd; i++) {
            final c = bd.getUint16(faceOff + i * 2, Endian.little);
            if (c == 0) break;
            codes.add(c);
          }
          if (codes.isNotEmpty) face = String.fromCharCodes(codes);
        }
        final encoding = face == 'Symbol' || face == 'MT Extra'
            ? VsdLegacyTextEncoding.symbol
            : vsdLegacyEncodingForCodePage(charset);
        _store(
          objects,
          ih,
          _EmfFont(
            height,
            face,
            weight,
            italic,
            underline,
            strikeThrough,
            escapement,
            encoding,
          ),
        );
      }
    } else if (t == _emrSelectObject && params + 4 <= recEnd) {
      final ih = bd.getUint32(params, Endian.little);
      if (ih & 0x80000000 != 0) {
        // Stock object colours follow LibreOffice MtfTools::SelectObject.
        final stock = ih & 0x7fffffff;
        const stockBrushColors = <int>[
          0xFFFFFFFF, // WHITE_BRUSH
          0xFFC0C0C0, // LTGRAY_BRUSH
          0xFF808080, // GRAY_BRUSH
          0xFF666666, // DKGRAY_BRUSH / LibreOffice COL_GRAY7
          0xFF000000, // BLACK_BRUSH
        ];
        if (stock < stockBrushColors.length) {
          brushStyle = 0;
          brushColor = stockBrushColors[stock];
          brushHatch = 0;
        } else if (stock == 5) {
          brushStyle = 1; // NULL_BRUSH
          brushHatch = 0;
        } else if (stock == 8) {
          penStyle = 5; // NULL_PEN
          penDashPattern = null;
        } else if (stock == 6 || stock == 7) {
          penStyle = 0; // WHITE_PEN / BLACK_PEN
          penWidth = 1;
          penColor = stock == 6 ? 0xFFFFFFFF : 0xFF000000;
          penDashPattern = null;
        }
      } else if (ih < objects.length) {
        final o = objects[ih];
        if (o is _EmfPen) {
          penStyle = o.style;
          penWidth = o.width;
          penColor = o.color;
          penDashPattern = o.dashPattern;
        } else if (o is _EmfBrush) {
          brushStyle = o.style;
          brushColor = o.color;
          brushHatch = o.hatch;
        } else if (o is _EmfFont) {
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
    } else if (t == _emrDeleteObject && params + 4 <= recEnd) {
      final ih = bd.getUint32(params, Endian.little);
      if (ih < objects.length) objects[ih] = null;
    } else if (t == _emrBeginPath) {
      pathFigures.clear();
      recordPath = true;
    } else if (t == _emrEndPath) {
      recordPath = false;
    } else if (t == _emrAbortPath) {
      pathFigures.clear();
      recordPath = false;
    } else if (t == _emrCloseFigure) {
      if (pathFigures.isNotEmpty) pathFigures.last.closed = true;
    } else if (t == _emrFillPath) {
      paintRecordedPath(stroke: false, fill: true);
    } else if (t == _emrStrokeAndFillPath) {
      paintRecordedPath(stroke: true, fill: true);
    } else if (t == _emrStrokePath) {
      paintRecordedPath(stroke: true, fill: false);
    } else if (t == _emrMoveToEx && params + 8 <= recEnd) {
      curPt = MetafilePoint(
        bd.getInt32(params, Endian.little).toDouble(),
        bd.getInt32(params + 4, Endian.little).toDouble(),
      );
      ensurePts([curPt!]);
      if (recordPath) recordMoveTo(curPt!);
    } else if (t == _emrLineTo && params + 8 <= recEnd) {
      final end = MetafilePoint(
        bd.getInt32(params, Endian.little).toDouble(),
        bd.getInt32(params + 4, Endian.little).toDouble(),
      );
      if (curPt != null) {
        emitPolyline(
          <MetafilePoint>[curPt!, end],
          closed: false,
          updateCurrent: true,
        );
      }
      curPt = end;
    } else if (t == _emrAngleArc && params + 20 <= recEnd) {
      final center = MetafilePoint(
        bd.getInt32(params, Endian.little).toDouble(),
        bd.getInt32(params + 4, Endian.little).toDouble(),
      );
      final radius = bd.getUint32(params + 8, Endian.little).toDouble();
      final arc = densifyMetafileAngleArc(
        center,
        radius,
        bd.getFloat32(params + 12, Endian.little).toDouble(),
        bd.getFloat32(params + 16, Endian.little).toDouble(),
        clockwise: arcClockwise,
      );
      emitArc(arc,
          closed: false,
          fill: false,
          connectCurrent: true,
          updateCurrent: true);
    } else if ((t == _emrArc ||
            t == _emrArcTo ||
            t == _emrChord ||
            t == _emrPie) &&
        params + 32 <= recEnd) {
      final bounds = MetafileRect(
        bd.getInt32(params, Endian.little).toDouble(),
        bd.getInt32(params + 4, Endian.little).toDouble(),
        bd.getInt32(params + 8, Endian.little).toDouble(),
        bd.getInt32(params + 12, Endian.little).toDouble(),
      );
      final arc = densifyMetafileEllipticalArc(
        bounds,
        MetafilePoint(
          bd.getInt32(params + 16, Endian.little).toDouble(),
          bd.getInt32(params + 20, Endian.little).toDouble(),
        ),
        MetafilePoint(
          bd.getInt32(params + 24, Endian.little).toDouble(),
          bd.getInt32(params + 28, Endian.little).toDouble(),
        ),
        clockwise: arcClockwise,
      );
      if (t == _emrPie) {
        emitArc(
          <MetafilePoint>[
            MetafilePoint(
              (bounds.minX + bounds.maxX) / 2,
              (bounds.minY + bounds.maxY) / 2,
            ),
            ...arc,
          ],
          closed: true,
          fill: true,
        );
      } else {
        emitArc(
          arc,
          closed: t == _emrChord,
          fill: t == _emrChord,
          connectCurrent: t == _emrArcTo,
          updateCurrent: t == _emrArcTo,
        );
      }
    } else if (t == _emrPolyBezier && params + 20 <= recEnd) {
      // Bounds(16) + count(4) + POINTL: start + n×(c1,c2,end).
      final count = bd.getUint32(params + 16, Endian.little);
      final pts = _readPoints32(bd, params + 20, recEnd, count);
      emitBezier(pts);
    } else if (t == _emrPolyBezierTo && params + 20 <= recEnd) {
      // Bounds(16) + count(4) + POINTL: n×(c1,c2,end); starts at current pt.
      final count = bd.getUint32(params + 16, Endian.little);
      final ctrl = _readPoints32(bd, params + 20, recEnd, count);
      if (curPt != null && ctrl.length >= 3) {
        emitBezier(<MetafilePoint>[curPt!, ...ctrl], updateCurrent: true);
      }
    } else if (t == _emrPolyBezier16 && params + 20 <= recEnd) {
      // Bounds(16) + count(4) + POINTS: start + n×(c1,c2,end).
      final count = bd.getUint32(params + 16, Endian.little);
      final pts = _readPoints16(bd, params + 20, recEnd, count);
      emitBezier(pts);
    } else if (t == _emrPolyBezierTo16 && params + 20 <= recEnd) {
      // Bounds(16) + count(4) + POINTS: n×(c1,c2,end); starts at current pt.
      final count = bd.getUint32(params + 16, Endian.little);
      final ctrl = _readPoints16(bd, params + 20, recEnd, count);
      if (curPt != null && ctrl.length >= 3) {
        emitBezier(<MetafilePoint>[curPt!, ...ctrl], updateCurrent: true);
      }
    } else if ((t == _emrPolyDraw || t == _emrPolyDraw16) &&
        params + 20 <= recEnd) {
      // Bounds(16) + count(4) + POINTL/POINTS[count] + type bytes[count].
      final count = bd.getUint32(params + 16, Endian.little);
      final pointSize = t == _emrPolyDraw ? 8 : 4;
      final pointsOffset = params + 20;
      if (count <= (recEnd - pointsOffset) ~/ pointSize) {
        final typesOffset = pointsOffset + count * pointSize;
        if (count <= recEnd - typesOffset) {
          final points = t == _emrPolyDraw
              ? _readPoints32(bd, pointsOffset, recEnd, count)
              : _readPoints16(bd, pointsOffset, recEnd, count);
          final pointTypes = <int>[
            for (var i = 0; i < count; i++) bd.getUint8(typesOffset + i),
          ];
          emitPolyDraw(points, pointTypes);
        }
      }
    } else if ((t == _emrPolygon || t == _emrPolyline) &&
        params + 20 <= recEnd) {
      // Bounds(16) + count(4) + POINTL
      final count = bd.getUint32(params + 16, Endian.little);
      final pts = _readPoints32(bd, params + 20, recEnd, count);
      emitPolyline(pts, closed: t == _emrPolygon);
    } else if ((t == _emrPolygon16 || t == _emrPolyline16) &&
        params + 20 <= recEnd) {
      // Bounds(16) + count(4) + POINTS
      final count = bd.getInt32(params + 16, Endian.little);
      final pts = _readPoints16(bd, params + 20, recEnd, count);
      emitPolyline(pts, closed: t == _emrPolygon16);
    } else if (t == _emrPolylineTo && params + 20 <= recEnd) {
      final count = bd.getUint32(params + 16, Endian.little);
      final pts = _readPoints32(bd, params + 20, recEnd, count);
      if (curPt != null && pts.isNotEmpty) {
        emitPolyline(
          <MetafilePoint>[curPt!, ...pts],
          closed: false,
          updateCurrent: true,
        );
      }
    } else if (t == _emrPolylineTo16 && params + 20 <= recEnd) {
      final count = bd.getUint32(params + 16, Endian.little);
      final pts = _readPoints16(bd, params + 20, recEnd, count);
      if (curPt != null && pts.isNotEmpty) {
        emitPolyline(
          <MetafilePoint>[curPt!, ...pts],
          closed: false,
          updateCurrent: true,
        );
      }
    } else if ((t == _emrPolyPolygon || t == _emrPolyPolyline) &&
        params + 24 <= recEnd) {
      // Bounds(16) + nPolys(4) + nPts(4) + counts[nPolys] + POINTL…
      final nPolys = bd.getUint32(params + 16, Endian.little);
      var p = params + 24;
      final counts = <int>[];
      for (var i = 0; i < nPolys && p + 4 <= recEnd; i++) {
        counts.add(bd.getUint32(p, Endian.little));
        p += 4;
      }
      final closed = t == _emrPolyPolygon;
      for (final c in counts) {
        if (c > (recEnd - p) ~/ 8) break;
        final pts = _readPoints32(bd, p, recEnd, c);
        p += c * 8;
        emitPolyline(pts, closed: closed);
      }
    } else if ((t == _emrPolyPolyline16 || t == _emrPolyPolygon16) &&
        params + 24 <= recEnd) {
      // Bounds(16) + nPolys(4) + nPts(4) + counts[nPolys] + POINTS…
      final nPolys = bd.getUint32(params + 16, Endian.little);
      var p = params + 24;
      final counts = <int>[];
      for (var i = 0; i < nPolys && p + 4 <= recEnd; i++) {
        counts.add(bd.getUint32(p, Endian.little));
        p += 4;
      }
      final closed = t == _emrPolyPolygon16;
      for (final c in counts) {
        if (c > (recEnd - p) ~/ 4) break;
        final pts = _readPoints16(bd, p, recEnd, c);
        p += c * 4;
        emitPolyline(pts, closed: closed);
      }
    } else if (t == _emrRoundRect && params + 24 <= recEnd) {
      final left = bd.getInt32(params, Endian.little).toDouble();
      final top = bd.getInt32(params + 4, Endian.little).toDouble();
      final right = bd.getInt32(params + 8, Endian.little).toDouble();
      final bottom = bd.getInt32(params + 12, Endian.little).toDouble();
      final cornerWidth = bd.getUint32(params + 16, Endian.little) / 2.0;
      final cornerHeight = bd.getUint32(params + 20, Endian.little) / 2.0;
      final pts = [
        MetafilePoint(left, top),
        MetafilePoint(right, top),
        MetafilePoint(right, bottom),
        MetafilePoint(left, bottom),
      ];
      final pathPoints = roundedRectPoints(
        left,
        top,
        right,
        bottom,
        cornerWidth,
        cornerHeight,
      );
      ensurePts(pathPoints);
      if (recordPath) {
        recordPathPoints(pathPoints, closed: true);
        offset = recEnd;
        continue;
      }
      final fill = brushStyle == 0 || brushStyle == 2;
      final stroke = (penStyle & 0x0f) != 5;
      if (fill || stroke) {
        ops.add(MetafilePathOp(
          points: pts,
          closed: true,
          fill: fill,
          stroke: stroke,
          fillArgb: fill ? brushColor : 0,
          strokeArgb: stroke ? penColor : 0,
          strokeWidth: penWidth,
          strokeDashPattern: penDashPattern,
          cornerRadiusX: cornerWidth,
          cornerRadiusY: cornerHeight,
          fillHatch: brushStyle == 2 ? brushHatch : null,
          fillBackgroundArgb:
              brushStyle == 2 && backgroundMode == 2 ? backgroundColor : null,
          evenOddFill: polyFillMode != 2,
          rasterOperation: rasterOperation,
        ));
      }
    } else if ((t == _emrRectangle || t == _emrEllipse) &&
        params + 16 <= recEnd) {
      final left = bd.getInt32(params, Endian.little).toDouble();
      final top = bd.getInt32(params + 4, Endian.little).toDouble();
      final right = bd.getInt32(params + 8, Endian.little).toDouble();
      final bottom = bd.getInt32(params + 12, Endian.little).toDouble();
      final pts = [
        MetafilePoint(left, top),
        MetafilePoint(right, top),
        MetafilePoint(right, bottom),
        MetafilePoint(left, bottom),
      ];
      final pathPoints =
          t == _emrEllipse ? ellipsePoints(left, top, right, bottom) : pts;
      ensurePts(pathPoints);
      if (recordPath) {
        recordPathPoints(pathPoints, closed: true);
        offset = recEnd;
        continue;
      }
      final fill = brushStyle == 0 || brushStyle == 2;
      final stroke = (penStyle & 0x0f) != 5;
      if (fill || stroke) {
        ops.add(MetafilePathOp(
          points: pts,
          closed: true,
          fill: fill,
          stroke: stroke,
          fillArgb: fill ? brushColor : 0,
          strokeArgb: stroke ? penColor : 0,
          strokeWidth: penWidth,
          strokeDashPattern: penDashPattern,
          isEllipse: t == _emrEllipse,
          fillHatch: brushStyle == 2 ? brushHatch : null,
          fillBackgroundArgb:
              brushStyle == 2 && backgroundMode == 2 ? backgroundColor : null,
          evenOddFill: polyFillMode != 2,
          rasterOperation: rasterOperation,
        ));
      }
    } else if ((t == _emrBitBlt ||
            t == _emrStretchBlt ||
            t == _emrAlphaBlend ||
            t == _emrTransparentBlt) &&
        params + (t == _emrBitBlt ? 92 : 100) <= recEnd) {
      // The four records share the same destination/source/XForm/BMI layout.
      // LibreOffice queues their reconstructed bitmaps in record order; doing
      // the same keeps vector operations before and after the bitmap intact.
      final destinationX = bd.getInt32(params + 16, Endian.little).toDouble();
      final destinationY = bd.getInt32(params + 20, Endian.little).toDouble();
      final destinationWidth =
          bd.getInt32(params + 24, Endian.little).toDouble();
      final destinationHeight =
          bd.getInt32(params + 28, Endian.little).toDouble();
      final control = bd.getUint32(params + 32, Endian.little);
      final sourceX = bd.getInt32(params + 36, Endian.little);
      final sourceY = bd.getInt32(params + 40, Endian.little);
      final usage = bd.getUint32(params + 72, Endian.little);
      final offBmi = bd.getUint32(params + 76, Endian.little);
      final cbBmi = bd.getUint32(params + 80, Endian.little);
      final offBits = bd.getUint32(params + 84, Endian.little);
      final cbBits = bd.getUint32(params + 88, Endian.little);
      final stretched = t != _emrBitBlt;
      final sourceWidth =
          stretched ? bd.getInt32(params + 92, Endian.little) : 0;
      final sourceHeight =
          stretched ? bd.getInt32(params + 96, Endian.little) : 0;
      final alphaBlend = t == _emrAlphaBlend;
      final transparent = t == _emrTransparentBlt;
      final blendOperation = control & 0xff;
      if (!alphaBlend || blendOperation == 0) {
        emitEmbeddedBitmap(
          recordStart: offset,
          recordEnd: recEnd,
          destinationX: destinationX,
          destinationY: destinationY,
          destinationWidth: destinationWidth,
          destinationHeight: destinationHeight,
          sourceX: sourceX,
          sourceY: sourceY,
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
          usage: usage,
          offBmi: offBmi,
          cbBmi: cbBmi,
          offBits: offBits,
          cbBits: cbBits,
          rasterOperation: alphaBlend || transparent ? 0x00cc0020 : control,
          opacity: alphaBlend ? ((control >> 16) & 0xff) / 255.0 : 1,
          preserveAlpha: alphaBlend && ((control >> 24) & 0x01) != 0,
          transparentArgb: transparent ? _rgbToArgb(control) : null,
        );
      }
    } else if (t == _emrMaskBlt && params + 120 <= recEnd) {
      // MASKBLT extends BITBLT with a monochrome mask. A set mask bit copies
      // the source pixel; a clear bit leaves the destination untouched.
      final recordSize = recEnd - offset;
      Uint8List? recordBytes(int fieldOffset, int length) {
        if (fieldOffset < 8 ||
            length <= 0 ||
            fieldOffset > recordSize ||
            length > recordSize - fieldOffset) {
          return null;
        }
        return Uint8List.sublistView(
          emf,
          offset + fieldOffset,
          offset + fieldOffset + length,
        );
      }

      final maskUsage = bd.getUint32(params + 100, Endian.little);
      final maskBmi = maskUsage == 0
          ? recordBytes(
              bd.getUint32(params + 104, Endian.little),
              bd.getUint32(params + 108, Endian.little),
            )
          : null;
      final maskBits = maskUsage == 0
          ? recordBytes(
              bd.getUint32(params + 112, Endian.little),
              bd.getUint32(params + 116, Endian.little),
            )
          : null;
      emitEmbeddedBitmap(
        recordStart: offset,
        recordEnd: recEnd,
        destinationX: bd.getInt32(params + 16, Endian.little).toDouble(),
        destinationY: bd.getInt32(params + 20, Endian.little).toDouble(),
        destinationWidth: bd.getInt32(params + 24, Endian.little).toDouble(),
        destinationHeight: bd.getInt32(params + 28, Endian.little).toDouble(),
        sourceX: bd.getInt32(params + 36, Endian.little),
        sourceY: bd.getInt32(params + 40, Endian.little),
        sourceWidth: bd.getInt32(params + 24, Endian.little),
        sourceHeight: bd.getInt32(params + 28, Endian.little),
        usage: bd.getUint32(params + 72, Endian.little),
        offBmi: bd.getUint32(params + 76, Endian.little),
        cbBmi: bd.getUint32(params + 80, Endian.little),
        offBits: bd.getUint32(params + 84, Endian.little),
        cbBits: bd.getUint32(params + 88, Endian.little),
        rasterOperation: bd.getUint32(params + 32, Endian.little),
        maskBmi: maskBmi,
        maskBits: maskBits,
        maskX: bd.getInt32(params + 92, Endian.little),
        maskY: bd.getInt32(params + 96, Endian.little),
      );
    } else if (t == _emrPlgBlt && params + 132 <= recEnd) {
      final destinationPoints = <MetafilePoint>[
        for (var i = 0; i < 3; i++)
          MetafilePoint(
            bd.getInt32(params + 16 + i * 8, Endian.little).toDouble(),
            bd.getInt32(params + 20 + i * 8, Endian.little).toDouble(),
          ),
      ];
      final a = destinationPoints[0];
      final b = destinationPoints[1];
      final c = destinationPoints[2];
      final allDestinationPoints = <MetafilePoint>[
        ...destinationPoints,
        MetafilePoint(b.x + c.x - a.x, b.y + c.y - a.y),
      ];
      final xs = allDestinationPoints.map((point) => point.x);
      final ys = allDestinationPoints.map((point) => point.y);
      final minDestinationX = xs.reduce(math.min);
      final minDestinationY = ys.reduce(math.min);
      final recordSize = recEnd - offset;
      Uint8List? recordBytes(int fieldOffset, int length) {
        if (fieldOffset < 8 ||
            length <= 0 ||
            fieldOffset > recordSize ||
            length > recordSize - fieldOffset) {
          return null;
        }
        return Uint8List.sublistView(
          emf,
          offset + fieldOffset,
          offset + fieldOffset + length,
        );
      }

      final maskUsage = bd.getUint32(params + 112, Endian.little);
      final maskBmi = maskUsage == 0
          ? recordBytes(
              bd.getUint32(params + 116, Endian.little),
              bd.getUint32(params + 120, Endian.little),
            )
          : null;
      final maskBits = maskUsage == 0
          ? recordBytes(
              bd.getUint32(params + 124, Endian.little),
              bd.getUint32(params + 128, Endian.little),
            )
          : null;
      emitEmbeddedBitmap(
        recordStart: offset,
        recordEnd: recEnd,
        destinationX: minDestinationX,
        destinationY: minDestinationY,
        destinationWidth: xs.reduce(math.max) - minDestinationX,
        destinationHeight: ys.reduce(math.max) - minDestinationY,
        sourceX: bd.getInt32(params + 40, Endian.little),
        sourceY: bd.getInt32(params + 44, Endian.little),
        sourceWidth: bd.getInt32(params + 48, Endian.little),
        sourceHeight: bd.getInt32(params + 52, Endian.little),
        usage: bd.getUint32(params + 84, Endian.little),
        offBmi: bd.getUint32(params + 88, Endian.little),
        cbBmi: bd.getUint32(params + 92, Endian.little),
        offBits: bd.getUint32(params + 96, Endian.little),
        cbBits: bd.getUint32(params + 100, Endian.little),
        rasterOperation: 0x00cc0020,
        destinationParallelogram: destinationPoints,
        maskBmi: maskBmi,
        maskBits: maskBits,
        maskX: bd.getInt32(params + 104, Endian.little),
        maskY: bd.getInt32(params + 108, Endian.little),
      );
    } else if (t == _emrStretchDibits && params + 72 <= recEnd) {
      emitEmbeddedBitmap(
        recordStart: offset,
        recordEnd: recEnd,
        destinationX: bd.getInt32(params + 16, Endian.little).toDouble(),
        destinationY: bd.getInt32(params + 20, Endian.little).toDouble(),
        destinationWidth: bd.getInt32(params + 64, Endian.little).toDouble(),
        destinationHeight: bd.getInt32(params + 68, Endian.little).toDouble(),
        sourceX: bd.getInt32(params + 24, Endian.little),
        sourceY: bd.getInt32(params + 28, Endian.little),
        sourceWidth: bd.getInt32(params + 32, Endian.little),
        sourceHeight: bd.getInt32(params + 36, Endian.little),
        offBmi: bd.getUint32(params + 40, Endian.little),
        cbBmi: bd.getUint32(params + 44, Endian.little),
        offBits: bd.getUint32(params + 48, Endian.little),
        cbBits: bd.getUint32(params + 52, Endian.little),
        usage: bd.getUint32(params + 56, Endian.little),
        rasterOperation: bd.getUint32(params + 60, Endian.little),
      );
    } else if (t == _emrSetDibitsToDevice && params + 68 <= recEnd) {
      final sourceWidth = bd.getInt32(params + 32, Endian.little);
      final scanCount = bd.getUint32(params + 64, Endian.little);
      final sourceY = bd.getInt32(params + 28, Endian.little) +
          bd.getUint32(params + 60, Endian.little);
      emitEmbeddedBitmap(
        recordStart: offset,
        recordEnd: recEnd,
        destinationX: bd.getInt32(params + 16, Endian.little).toDouble(),
        destinationY: bd.getInt32(params + 20, Endian.little).toDouble(),
        destinationWidth: sourceWidth.toDouble(),
        destinationHeight: scanCount.toDouble(),
        sourceX: bd.getInt32(params + 24, Endian.little),
        sourceY: sourceY,
        sourceWidth: sourceWidth,
        sourceHeight: scanCount,
        offBmi: bd.getUint32(params + 40, Endian.little),
        cbBmi: bd.getUint32(params + 44, Endian.little),
        offBits: bd.getUint32(params + 48, Endian.little),
        cbBits: bd.getUint32(params + 52, Endian.little),
        usage: bd.getUint32(params + 56, Endian.little),
        rasterOperation: 0x00cc0020,
      );
    } else if (t == _emrGradientFill && params + 28 <= recEnd) {
      final vertexCount = bd.getUint32(params + 16, Endian.little);
      final meshCount = bd.getUint32(params + 20, Endian.little);
      final mode = bd.getUint32(params + 24, Endian.little);
      final vertexStart = params + 28;
      final indexStride = mode == 2 ? 12 : 8;
      if (vertexCount <= 256 * 1024 &&
          meshCount <= 256 * 1024 &&
          (mode == 0 || mode == 1 || mode == 2) &&
          vertexCount * 16 + meshCount * indexStride <= recEnd - vertexStart) {
        final vertices = <MetafileGradientVertex>[
          for (var i = 0; i < vertexCount; i++)
            MetafileGradientVertex(
              point: MetafilePoint(
                bd.getInt32(vertexStart + i * 16, Endian.little).toDouble(),
                bd.getInt32(vertexStart + i * 16 + 4, Endian.little).toDouble(),
              ),
              // MS-EMF requires GRADIENTFILL to ignore TriVertex.Alpha.
              argb: 0xff000000 |
                  ((bd.getUint16(vertexStart + i * 16 + 8, Endian.little) >>
                          8) <<
                      16) |
                  ((bd.getUint16(vertexStart + i * 16 + 10, Endian.little) >>
                          8) <<
                      8) |
                  (bd.getUint16(vertexStart + i * 16 + 12, Endian.little) >> 8),
            ),
        ];
        final indexStart = vertexStart + vertexCount * 16;
        for (var i = 0; i < meshCount; i++) {
          final meshStart = indexStart + i * indexStride;
          final first = bd.getUint32(meshStart, Endian.little);
          final second = bd.getUint32(meshStart + 4, Endian.little);
          if (first >= vertexCount || second >= vertexCount) continue;
          if (mode == 0 || mode == 1) {
            final upperLeft = vertices[first];
            final lowerRight = vertices[second];
            ensurePts(<MetafilePoint>[
              upperLeft.point,
              lowerRight.point,
            ]);
            ops.add(MetafileGradientRectOp(
              upperLeft: upperLeft,
              lowerRight: lowerRight,
              horizontal: mode == 0,
            ));
            continue;
          }
          // Triangle indexes are three DWORDs, packed at 12-byte strides.
          final third = bd.getUint32(meshStart + 8, Endian.little);
          if (third >= vertexCount) continue;
          final a = vertices[first];
          final b = vertices[second];
          final c = vertices[third];
          ensurePts(<MetafilePoint>[a.point, b.point, c.point]);
          ops.add(MetafileGradientTriangleOp(
            first: a,
            second: b,
            third: c,
          ));
        }
      }
    } else if ((t == _emrExtTextOutA ||
            t == _emrExtTextOutW ||
            t == _emrPolyTextOutA ||
            t == _emrPolyTextOutW) &&
        params + 32 <= recEnd) {
      // Bounds(16) + graphics mode(4) + scales(8), then either one EMRTEXT
      // or a count followed by an array of EMRTEXT structures.
      final ansi = t == _emrExtTextOutA || t == _emrPolyTextOutA;
      final poly = t == _emrPolyTextOutA || t == _emrPolyTextOutW;
      final count = poly ? bd.getUint32(params + 28, Endian.little) : 1;
      var textOff = params + (poly ? 32 : 28);
      if (count <= 1024 && count <= (recEnd - textOff) ~/ 40) {
        for (var i = 0; i < count; i++) {
          emitText(offset, textOff, recEnd, ansi: ansi);
          textOff += 40;
        }
      }
    } else if (t == _emrSmallTextOut) {
      emitSmallText(params, recEnd);
    }

    offset = recEnd;
  }

  if (ops.isEmpty) return null;
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

/// Read an EMF RGNDATA rectangle union.
///
/// This follows LibreOffice `ImplReadRegion`: require the 32-byte
/// RGNDATAHEADER, accept only RDH_RECTANGLES, and reject a short rectangle
/// array as a whole so a damaged record cannot consume the next EMF record.
List<List<MetafilePoint>> _readEmfRegionContours(
  ByteData data,
  int start,
  int length,
  int streamLength,
) {
  if (length < 32 || start < 0 || start > streamLength - 32) {
    return const <List<MetafilePoint>>[];
  }
  final end = start + length;
  if (end < start || end > streamLength) {
    return const <List<MetafilePoint>>[];
  }
  final headerSize = data.getUint32(start, Endian.little);
  final regionType = data.getUint32(start + 4, Endian.little);
  final rectangleCount = data.getUint32(start + 8, Endian.little);
  final regionSize = data.getUint32(start + 12, Endian.little);
  if (headerSize != 32 ||
      regionType != 1 ||
      rectangleCount == 0 ||
      rectangleCount > (length - headerSize) ~/ 16 ||
      rectangleCount > regionSize ~/ 16 ||
      regionSize > length - headerSize) {
    return const <List<MetafilePoint>>[];
  }

  final contours = <List<MetafilePoint>>[];
  var position = start + headerSize;
  for (var i = 0; i < rectangleCount; i++) {
    final left = data.getInt32(position, Endian.little).toDouble();
    final top = data.getInt32(position + 4, Endian.little).toDouble();
    final right = data.getInt32(position + 8, Endian.little).toDouble();
    final bottom = data.getInt32(position + 12, Endian.little).toDouble();
    position += 16;
    if (left == right || top == bottom) continue;
    contours.add(<MetafilePoint>[
      MetafilePoint(left, top),
      MetafilePoint(right, top),
      MetafilePoint(right, bottom),
      MetafilePoint(left, bottom),
    ]);
  }
  return contours;
}

void _store(List<_EmfObject?> objects, int ih, _EmfObject obj) {
  if (ih < 0) return;
  while (objects.length <= ih) {
    objects.add(null);
  }
  objects[ih] = obj;
}

List<MetafilePoint> _readPoints16(
  ByteData bd,
  int start,
  int recEnd,
  int count,
) {
  final pts = <MetafilePoint>[];
  var p = start;
  for (var i = 0; i < count && p + 4 <= recEnd; i++) {
    final x = bd.getInt16(p, Endian.little).toDouble();
    final y = bd.getInt16(p + 2, Endian.little).toDouble();
    pts.add(MetafilePoint(x, y));
    p += 4;
  }
  return pts;
}

List<MetafilePoint> _readPoints32(
  ByteData bd,
  int start,
  int recEnd,
  int count,
) {
  final pts = <MetafilePoint>[];
  var p = start;
  for (var i = 0; i < count && p + 8 <= recEnd; i++) {
    final x = bd.getInt32(p, Endian.little).toDouble();
    final y = bd.getInt32(p + 4, Endian.little).toDouble();
    pts.add(MetafilePoint(x, y));
    p += 8;
  }
  return pts;
}

int _rgbToArgb(int colorRef) {
  final r = colorRef & 0xff;
  final g = (colorRef >> 8) & 0xff;
  final b = (colorRef >> 16) & 0xff;
  return 0xFF000000 | (r << 16) | (g << 8) | b;
}

sealed class _EmfObject {}

class _EmfPen extends _EmfObject {
  _EmfPen(this.style, this.width, this.color, this.dashPattern);
  final int style;
  final double width;
  final int color;
  final List<double>? dashPattern;
}

class _EmfBrush extends _EmfObject {
  _EmfBrush(this.style, this.color, this.hatch);
  final int style;
  final int color;
  final int hatch;
}

class _EmfFont extends _EmfObject {
  _EmfFont(
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

class _EmfPathFigure {
  _EmfPathFigure({List<MetafilePoint>? points, this.closed = false})
      : points =
            points == null ? <MetafilePoint>[] : List<MetafilePoint>.of(points);

  _EmfPathFigure.copy(_EmfPathFigure other)
      : points = List<MetafilePoint>.of(other.points),
        closed = other.closed;

  final List<MetafilePoint> points;
  bool closed;
}

class _EmfTransform {
  const _EmfTransform(
    this.m11,
    this.m12,
    this.m21,
    this.m22,
    this.dx,
    this.dy,
  );

  const _EmfTransform.identity() : this(1, 0, 0, 1, 0, 0);

  final double m11;
  final double m12;
  final double m21;
  final double m22;
  final double dx;
  final double dy;

  static _EmfTransform? read(ByteData data, int offset) {
    final values = <double>[
      for (var i = 0; i < 6; i++)
        data.getFloat32(offset + i * 4, Endian.little).toDouble(),
    ];
    if (values.any((value) => !value.isFinite)) return null;
    return _EmfTransform(
      values[0],
      values[1],
      values[2],
      values[3],
      values[4],
      values[5],
    );
  }

  /// Matrix product `this × other` for column-vector affine coordinates.
  _EmfTransform multipliedBy(_EmfTransform other) => _EmfTransform(
        m11 * other.m11 + m21 * other.m12,
        m12 * other.m11 + m22 * other.m12,
        m11 * other.m21 + m21 * other.m22,
        m12 * other.m21 + m22 * other.m22,
        m11 * other.dx + m21 * other.dy + dx,
        m12 * other.dx + m22 * other.dy + dy,
      );

  _EmfTransform? inverse() {
    final determinant = m11 * m22 - m12 * m21;
    if (!determinant.isFinite || determinant.abs() < 1e-12) return null;
    final a = m22 / determinant;
    final b = -m12 / determinant;
    final c = -m21 / determinant;
    final d = m11 / determinant;
    return _EmfTransform(
      a,
      b,
      c,
      d,
      -(a * dx + c * dy),
      -(b * dx + d * dy),
    );
  }

  bool get isIdentity =>
      (m11 - 1).abs() < 1e-12 &&
      m12.abs() < 1e-12 &&
      m21.abs() < 1e-12 &&
      (m22 - 1).abs() < 1e-12 &&
      dx.abs() < 1e-9 &&
      dy.abs() < 1e-9;
}

class _EmfDcState {
  const _EmfDcState({
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
    required this.polyFillMode,
    required this.rasterOperation,
    required this.textAlign,
    required this.fontFace,
    required this.fontHeight,
    required this.fontWeight,
    required this.fontItalic,
    required this.fontUnderline,
    required this.fontStrikeThrough,
    required this.fontEscapementDegrees,
    required this.fontEncoding,
    required this.arcClockwise,
    required this.mapMode,
    required this.windowOrgX,
    required this.windowOrgY,
    required this.windowExtX,
    required this.windowExtY,
    required this.viewportOrgX,
    required this.viewportOrgY,
    required this.viewportExtX,
    required this.viewportExtY,
    required this.worldTransform,
    required this.curPt,
    required this.pathFigures,
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
  final int polyFillMode;
  final MetafileRasterOperation rasterOperation;
  final int textAlign;
  final String? fontFace;
  final double fontHeight;
  final int fontWeight;
  final bool fontItalic;
  final bool fontUnderline;
  final bool fontStrikeThrough;
  final double fontEscapementDegrees;
  final VsdLegacyTextEncoding fontEncoding;
  final bool arcClockwise;
  final int mapMode;
  final double windowOrgX;
  final double windowOrgY;
  final double windowExtX;
  final double windowExtY;
  final double viewportOrgX;
  final double viewportOrgY;
  final double viewportExtX;
  final double viewportExtY;
  final _EmfTransform worldTransform;
  final MetafilePoint? curPt;
  final List<_EmfPathFigure> pathFigures;
}
