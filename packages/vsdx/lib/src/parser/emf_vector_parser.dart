/// Enhanced Metafile (EMF) vector records → [MetafileDrawing].
///
/// Prefer [extractEmfEmbeddedBitmap] when the file is a thin wrapper around a
/// DIB. This parser covers the GDI path used by OLE `\x02OlePres000` previews
/// and pure-vector ForeignData: pens/brushes, MOVETOEX / LINETO,
/// POLYBEZIER* / POLYDRAW* / POLYLINE* / POLYGON* (32/16-bit, incl. *TO),
/// POLYPOLYLINE* / POLYPOLYGON*, rectangle/ellipse, and ExtTextOutW.
library;

import 'dart:math' as math;
import 'dart:typed_data';

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
const int _emrSetBkMode = 18;
const int _emrSetPolyFillMode = 19;
const int _emrSetTextAlign = 22;
const int _emrSetTextColor = 24;
const int _emrSetBkColor = 25;
const int _emrMoveToEx = 27;
const int _emrSaveDc = 33;
const int _emrRestoreDc = 34;
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
  final ops = <Object>[];
  MetafilePoint? curPt;
  var recordPath = false;
  final pathFigures = <_EmfPathFigure>[];
  final savedStates = <_EmfDcState>[];

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
        curPt: curPt,
        pathFigures: pathFigures
            .map((figure) => _EmfPathFigure.copy(figure))
            .toList(growable: false),
      );

  void restoreState(int savedDc) {
    if (savedDc == 0 || savedStates.isEmpty) return;
    final relative = savedDc < 0 ? savedDc : -1;
    final index = savedStates.length + relative;
    if (index < 0) {
      savedStates.clear();
      return;
    }
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
    curPt = state.curPt;
    pathFigures
      ..clear()
      ..addAll(state.pathFigures.map(_EmfPathFigure.copy));
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
      ));
    }
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
    } else if (t == _emrRestoreDc && params + 4 <= recEnd) {
      restoreState(bd.getInt32(params, Endian.little));
    } else if (t == _emrSetWindowOrgEx && params + 8 <= recEnd) {
      // ignored for drawing; bounds already from header
    } else if (t == _emrSetWindowExtEx && params + 8 <= recEnd) {
      final cx = bd.getInt32(params, Endian.little).toDouble();
      final cy = bd.getInt32(params + 4, Endian.little).toDouble();
      if (!haveBounds && cx.abs() > 1 && cy.abs() > 1) {
        minX = 0;
        minY = 0;
        maxX = cx.abs();
        maxY = cy.abs();
        haveBounds = true;
      }
    } else if (t == _emrSetBkMode && params + 4 <= recEnd) {
      backgroundMode = bd.getUint32(params, Endian.little);
    } else if (t == _emrSetPolyFillMode && params + 4 <= recEnd) {
      final mode = bd.getUint32(params, Endian.little);
      if (mode == 1 || mode == 2) polyFillMode = mode;
    } else if (t == _emrSetBkColor && params + 4 <= recEnd) {
      backgroundColor = _rgbToArgb(bd.getUint32(params, Endian.little));
    } else if (t == _emrSetArcDirection && params + 4 <= recEnd) {
      arcClockwise = bd.getUint32(params, Endian.little) == 2;
    } else if (t == _emrSetTextColor && params + 4 <= recEnd) {
      textColor = _rgbToArgb(bd.getUint32(params, Endian.little));
    } else if (t == _emrSetTextAlign && params + 4 <= recEnd) {
      textAlign = bd.getUint32(params, Endian.little);
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
        ));
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
  final MetafilePoint? curPt;
  final List<_EmfPathFigure> pathFigures;
}
