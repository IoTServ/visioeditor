/// Enhanced Metafile (EMF) vector records → [MetafileDrawing].
///
/// Prefer [extractEmfEmbeddedBitmap] when the file is a thin wrapper around a
/// DIB. This parser covers the GDI path used by OLE `\x02OlePres000` previews
/// and pure-vector ForeignData: pens/brushes, POLYGON16 / POLYLINE16 /
/// POLYPOLYGON16, rectangle/ellipse, and ExtTextOutW.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'metafile_drawing.dart';

const int _emrHeader = 1;
const int _emrEof = 14;
const int _emrSetWindowExtEx = 9;
const int _emrSetWindowOrgEx = 10;
const int _emrSetTextAlign = 22;
const int _emrSetTextColor = 24;
const int _emrSelectObject = 37;
const int _emrCreatePen = 38;
const int _emrCreateBrushIndirect = 39;
const int _emrDeleteObject = 40;
const int _emrEllipse = 42;
const int _emrRectangle = 43;
const int _emrExtCreateFontIndirectW = 82;
const int _emrExtTextOutW = 84;
const int _emrPolyBezier16 = 85;
const int _emrPolygon16 = 86;
const int _emrPolyline16 = 87;
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
  var textColor = 0xFF000000;
  var textAlign = 0;
  String? fontFace;
  var fontHeight = 12.0;
  final ops = <Object>[];

  void ensurePts(Iterable<MetafilePoint> pts) {
    for (final p in pts) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
      haveBounds = true;
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
      _store(objects, ih, _EmfBrush(style, color));
    } else if (t == _emrExtCreateFontIndirectW && params + 8 <= recEnd) {
      final ih = bd.getInt32(params, Endian.little);
      // EXTLOGFONTW starts at params+4; elfLogFont.lfHeight at +0 of that.
      if (params + 4 + 4 <= recEnd) {
        final height =
            bd.getInt32(params + 4, Endian.little).abs().toDouble().clamp(1.0, 2000.0);
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
        _store(objects, ih, _EmfFont(height, face));
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
        } else if (o is _EmfFont) {
          fontHeight = o.height;
          fontFace = o.face;
        }
      }
    } else if (t == _emrDeleteObject && params + 4 <= recEnd) {
      final ih = bd.getUint32(params, Endian.little);
      if (ih < objects.length) objects[ih] = null;
    } else if (t == _emrPolyBezier16 && params + 20 <= recEnd) {
      // Bounds(16) + count(4) + POINTS: start + n×(c1,c2,end).
      final count = bd.getUint32(params + 16, Endian.little);
      final pts = _readPoints16(bd, params + 20, recEnd, count);
      if (pts.length >= 4) {
        final dense = _densifyPolyBezier16(pts);
        ensurePts(dense);
        final stroke = penStyle != 5;
        final fill = brushStyle == 0;
        if (fill || stroke) {
          ops.add(MetafilePathOp(
            points: dense,
            closed: fill,
            fill: fill,
            stroke: stroke,
            fillArgb: fill ? brushColor : 0,
            strokeArgb: stroke ? penColor : 0,
            strokeWidth: penWidth,
          ));
        }
      }
    } else if ((t == _emrPolygon16 || t == _emrPolyline16) &&
        params + 20 <= recEnd) {
      // Bounds(16) + count(4) + points
      final count = bd.getInt32(params + 16, Endian.little);
      final pts = _readPoints16(bd, params + 20, recEnd, count);
      if (pts.length >= 2) {
        ensurePts(pts);
        final closed = t == _emrPolygon16;
        final fill = closed && brushStyle == 0;
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
          ));
        }
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
        if (pts.length >= 2) {
          ensurePts(pts);
          final fill = brushStyle == 0;
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
            ));
          }
        }
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
      final fill = brushStyle == 0;
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
        ));
      }
    } else if (t == _emrExtTextOutW && params + 32 <= recEnd) {
      // Bounds(16) + iGraphicsMode(4) + exScale(4) + eyScale(4) + EMRTEXT
      // EMRTEXT at params+28: ptlReference(8), nChars(4), offString(4), …
      final textOff = params + 28;
      if (textOff + 16 <= recEnd) {
        final x = bd.getInt32(textOff, Endian.little).toDouble();
        final y = bd.getInt32(textOff + 4, Endian.little).toDouble();
        final nChars = bd.getUint32(textOff + 8, Endian.little);
        final offString = bd.getUint32(textOff + 12, Endian.little);
        // offString is from start of record
        final strAt = offset + offString;
        if (nChars > 0 &&
            nChars < 4096 &&
            strAt + nChars * 2 <= emf.length) {
          final codes = <int>[];
          for (var i = 0; i < nChars; i++) {
            codes.add(bd.getUint16(strAt + i * 2, Endian.little));
          }
          final text = String.fromCharCodes(codes).replaceAll('\u0000', '');
          if (text.trim().isNotEmpty) {
            ensurePts([MetafilePoint(x, y)]);
            ops.add(MetafileTextOp(
              text: text,
              x: x,
              y: y,
              fontHeight: fontHeight,
              argb: textColor,
              face: fontFace,
              align: textAlign,
            ));
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

/// Densify EMR_POLYBEZIER16 control points into a polyline (cubic samples).
List<MetafilePoint> _densifyPolyBezier16(
  List<MetafilePoint> pts, {
  int steps = 8,
}) {
  if (pts.length < 4) return pts;
  final out = <MetafilePoint>[pts.first];
  for (var i = 1; i + 2 < pts.length; i += 3) {
    final p0 = out.last;
    final p1 = pts[i];
    final p2 = pts[i + 1];
    final p3 = pts[i + 2];
    for (var s = 1; s <= steps; s++) {
      final t = s / steps;
      final u = 1 - t;
      final x = u * u * u * p0.x +
          3 * u * u * t * p1.x +
          3 * u * t * t * p2.x +
          t * t * t * p3.x;
      final y = u * u * u * p0.y +
          3 * u * u * t * p1.y +
          3 * u * t * t * p2.y +
          t * t * t * p3.y;
      out.add(MetafilePoint(x, y));
    }
  }
  return out;
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
  _EmfBrush(this.style, this.color);
  final int style;
  final int color;
}

class _EmfFont extends _EmfObject {
  _EmfFont(this.height, this.face);
  final double height;
  final String? face;
}
