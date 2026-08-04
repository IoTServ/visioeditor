/// Enhanced Metafile (EMF) vector records → [MetafileDrawing].
///
/// Prefer [extractEmfEmbeddedBitmap] when the file is a thin wrapper around a
/// DIB. This parser covers the GDI path used by OLE `\x02OlePres000` previews
/// and pure-vector ForeignData: pens/brushes, MOVETOEX / LINETO,
/// POLYBEZIER* / POLYLINE* / POLYGON* (32-bit and 16-bit, incl. *TO),
/// POLYPOLYGON16, rectangle/ellipse, and ExtTextOutW.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'metafile_drawing.dart';

const int _emrHeader = 1;
const int _emrPolyBezier = 2;
const int _emrPolygon = 3;
const int _emrPolyline = 4;
const int _emrPolyBezierTo = 5;
const int _emrPolyPolyline = 7;
const int _emrPolyPolygon = 8;
const int _emrEof = 14;
const int _emrSetWindowExtEx = 9;
const int _emrSetWindowOrgEx = 10;
const int _emrSetBkMode = 18;
const int _emrSetTextAlign = 22;
const int _emrSetTextColor = 24;
const int _emrSetBkColor = 25;
const int _emrMoveToEx = 27;
const int _emrSelectObject = 37;
const int _emrCreatePen = 38;
const int _emrCreateBrushIndirect = 39;
const int _emrDeleteObject = 40;
const int _emrEllipse = 42;
const int _emrRectangle = 43;
const int _emrLineTo = 54;
const int _emrPolylineTo = 59;
const int _emrExtCreateFontIndirectW = 82;
const int _emrExtTextOutW = 84;
const int _emrPolyBezier16 = 85;
const int _emrPolygon16 = 86;
const int _emrPolyline16 = 87;
const int _emrPolyBezierTo16 = 88;
const int _emrPolylineTo16 = 89;
const int _emrPolyPolygon16 = 91;

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
  var brushColor = 0xFFFFFFFF;
  var brushStyle = 1;
  var brushHatch = 0;
  var textColor = 0xFF000000;
  var backgroundMode = 1; // TRANSPARENT
  var backgroundColor = 0xFFFFFFFF;
  var textAlign = 0;
  String? fontFace;
  var fontHeight = 12.0;
  var fontWeight = 400;
  var fontItalic = false;
  var fontUnderline = false;
  var fontStrikeThrough = false;
  var fontEscapementDegrees = 0.0;
  final ops = <Object>[];
  MetafilePoint? curPt;

  void ensurePts(Iterable<MetafilePoint> pts) {
    for (final p in pts) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
      haveBounds = true;
    }
  }

  void emitBezier(List<MetafilePoint> ctrl) {
    if (ctrl.length < 4) return;
    final dense = densifyPolyBezier(ctrl);
    ensurePts(dense);
    curPt = dense.last;
    final stroke = penStyle != 5;
    final fill = brushStyle == 0 || brushStyle == 2;
    if (fill || stroke) {
      ops.add(MetafilePathOp(
        points: dense,
        closed: fill,
        fill: fill,
        stroke: stroke,
        fillArgb: fill ? brushColor : 0,
        strokeArgb: stroke ? penColor : 0,
        strokeWidth: penWidth,
        fillHatch: brushStyle == 2 ? brushHatch : null,
        fillBackgroundArgb:
            brushStyle == 2 && backgroundMode == 2 ? backgroundColor : null,
      ));
    }
  }

  void emitPolyline(List<MetafilePoint> pts, {required bool closed}) {
    if (pts.length < 2) return;
    ensurePts(pts);
    curPt = pts.last;
    final fill = closed && (brushStyle == 0 || brushStyle == 2);
    final stroke = penStyle != 5;
    if (fill || stroke) {
      ops.add(MetafilePathOp(
        points: pts,
        closed: closed,
        fill: fill,
        stroke: stroke,
        fillArgb: fill ? brushColor : 0,
        strokeArgb: stroke ? penColor : 0,
        strokeWidth: penWidth,
        fillHatch: brushStyle == 2 ? brushHatch : null,
        fillBackgroundArgb:
            brushStyle == 2 && backgroundMode == 2 ? backgroundColor : null,
      ));
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

    if (t == _emrSetWindowOrgEx && params + 8 <= recEnd) {
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
    } else if (t == _emrSetBkColor && params + 4 <= recEnd) {
      backgroundColor = _rgbToArgb(bd.getUint32(params, Endian.little));
    } else if (t == _emrSetTextColor && params + 4 <= recEnd) {
      textColor = _rgbToArgb(bd.getUint32(params, Endian.little));
    } else if (t == _emrSetTextAlign && params + 4 <= recEnd) {
      textAlign = bd.getUint32(params, Endian.little);
    } else if (t == _emrCreatePen && params + 20 <= recEnd) {
      final ih = bd.getInt32(params, Endian.little);
      final style = bd.getUint32(params + 4, Endian.little);
      final width = bd.getInt32(params + 8, Endian.little).abs().toDouble();
      final color = _rgbToArgb(bd.getUint32(params + 16, Endian.little));
      _store(objects, ih, _EmfPen(style, width == 0 ? 1.0 : width, color));
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
          ),
        );
      }
    } else if (t == _emrSelectObject && params + 4 <= recEnd) {
      final ih = bd.getUint32(params, Endian.little);
      if (ih & 0x80000000 != 0) {
        // Stock object — NULL_PEN / NULL_BRUSH etc.
        final stock = ih & 0x7fffffff;
        if (stock == 8) penStyle = 5; // NULL_PEN
        if (stock == 5) brushStyle = 1; // NULL_BRUSH
      } else if (ih < objects.length) {
        final o = objects[ih];
        if (o is _EmfPen) {
          penStyle = o.style;
          penWidth = o.width;
          penColor = o.color;
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
        }
      }
    } else if (t == _emrDeleteObject && params + 4 <= recEnd) {
      final ih = bd.getUint32(params, Endian.little);
      if (ih < objects.length) objects[ih] = null;
    } else if (t == _emrMoveToEx && params + 8 <= recEnd) {
      curPt = MetafilePoint(
        bd.getInt32(params, Endian.little).toDouble(),
        bd.getInt32(params + 4, Endian.little).toDouble(),
      );
      ensurePts([curPt!]);
    } else if (t == _emrLineTo && params + 8 <= recEnd) {
      final end = MetafilePoint(
        bd.getInt32(params, Endian.little).toDouble(),
        bd.getInt32(params + 4, Endian.little).toDouble(),
      );
      if (curPt != null) {
        ensurePts([curPt!, end]);
        final stroke = penStyle != 5;
        if (stroke) {
          ops.add(MetafilePathOp(
            points: <MetafilePoint>[curPt!, end],
            closed: false,
            fill: false,
            stroke: true,
            fillArgb: 0,
            strokeArgb: penColor,
            strokeWidth: penWidth,
          ));
        }
      }
      curPt = end;
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
        emitBezier(<MetafilePoint>[curPt!, ...ctrl]);
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
        emitBezier(<MetafilePoint>[curPt!, ...ctrl]);
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
        emitPolyline(<MetafilePoint>[curPt!, ...pts], closed: false);
      }
    } else if (t == _emrPolylineTo16 && params + 20 <= recEnd) {
      final count = bd.getUint32(params + 16, Endian.little);
      final pts = _readPoints16(bd, params + 20, recEnd, count);
      if (curPt != null && pts.isNotEmpty) {
        emitPolyline(<MetafilePoint>[curPt!, ...pts], closed: false);
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
        final pts = _readPoints32(bd, p, recEnd, c);
        p += c * 8;
        emitPolyline(pts, closed: closed);
      }
    } else if (t == _emrPolyPolygon16 && params + 20 <= recEnd) {
      final nPolys = bd.getUint32(params + 16, Endian.little);
      var p = params + 20;
      final counts = <int>[];
      for (var i = 0; i < nPolys && p + 4 <= recEnd; i++) {
        counts.add(bd.getUint32(p, Endian.little));
        p += 4;
      }
      for (final c in counts) {
        final pts = _readPoints16(bd, p, recEnd, c);
        p += c * 4;
        emitPolyline(pts, closed: true);
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
      ensurePts(pts);
      curPt = MetafilePoint(right, bottom);
      final fill = brushStyle == 0 || brushStyle == 2;
      final stroke = penStyle != 5;
      if (fill || stroke) {
        ops.add(MetafilePathOp(
          points: pts,
          closed: true,
          fill: fill,
          stroke: stroke,
          fillArgb: fill ? brushColor : 0,
          strokeArgb: stroke ? penColor : 0,
          strokeWidth: penWidth,
          isEllipse: t == _emrEllipse,
          fillHatch: brushStyle == 2 ? brushHatch : null,
          fillBackgroundArgb:
              brushStyle == 2 && backgroundMode == 2 ? backgroundColor : null,
        ));
      }
    } else if (t == _emrExtTextOutW && params + 32 <= recEnd) {
      // Bounds(16) + iGraphicsMode(4) + exScale(4) + eyScale(4) + EMRTEXT
      // EMRTEXT at params+28: ptlReference(8), nChars(4), offString(4), …
      final textOff = params + 28;
      if (textOff + 16 <= recEnd) {
        final recordX = bd.getInt32(textOff, Endian.little).toDouble();
        final recordY = bd.getInt32(textOff + 4, Endian.little).toDouble();
        final useCurrentPoint = (textAlign & 0x01) != 0 && curPt != null;
        final x = useCurrentPoint ? curPt!.x : recordX;
        final y = useCurrentPoint ? curPt!.y : recordY;
        final nChars = bd.getUint32(textOff + 8, Endian.little);
        final offString = bd.getUint32(textOff + 12, Endian.little);
        final options = textOff + 20 <= recEnd
            ? bd.getUint32(textOff + 16, Endian.little)
            : 0;
        final recordRect = textOff + 36 <= recEnd && (options & 0x0006) != 0
            ? MetafileRect(
                bd.getInt32(textOff + 20, Endian.little).toDouble(),
                bd.getInt32(textOff + 24, Endian.little).toDouble(),
                bd.getInt32(textOff + 28, Endian.little).toDouble(),
                bd.getInt32(textOff + 32, Endian.little).toDouble(),
              )
            : null;
        final offDx = textOff + 40 <= recEnd
            ? bd.getUint32(textOff + 36, Endian.little)
            : 0;
        // offString is from start of record
        final strAt = offset + offString;
        if (nChars < 4096 && strAt + nChars * 2 <= recEnd) {
          final codes = <int>[];
          for (var i = 0; i < nChars; i++) {
            codes.add(bd.getUint16(strAt + i * 2, Endian.little));
          }
          final text = String.fromCharCodes(codes).replaceAll('\u0000', '');
          if (text.trim().isNotEmpty ||
              ((options & 0x0002) != 0 && recordRect != null)) {
            List<double>? advancesX;
            List<double>? advancesY;
            final hasVerticalAdvances = (options & 0x2000) != 0; // ETO_PDY
            final wordsPerGlyph = hasVerticalAdvances ? 2 : 1;
            final advanceAt = offset + offDx;
            if (offDx > 0 &&
                text.runes.length == nChars &&
                advanceAt >= offset &&
                advanceAt + nChars * wordsPerGlyph * 4 <= recEnd) {
              final xAdvances = <double>[];
              final yAdvances = hasVerticalAdvances ? <double>[] : null;
              var p = advanceAt;
              for (var i = 0; i < nChars; i++) {
                xAdvances.add(bd.getInt32(p, Endian.little).toDouble());
                p += 4;
                if (yAdvances != null) {
                  yAdvances.add(bd.getInt32(p, Endian.little).toDouble());
                  p += 4;
                }
              }
              advancesX = List<double>.unmodifiable(xAdvances);
              advancesY = yAdvances == null
                  ? null
                  : List<double>.unmodifiable(yAdvances);
            }
            final pt = MetafilePoint(x, y);
            ensurePts([pt]);
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
  _EmfPen(this.style, this.width, this.color);
  final int style;
  final double width;
  final int color;
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
  );
  final double height;
  final String? face;
  final int weight;
  final bool italic;
  final bool underline;
  final bool strikeThrough;
  final double escapementDegrees;
}
