/// Windows Metafile (WMF) → [MetafileDrawing] vector replay.
///
/// Covers the GDI records Visio / LibreOffice thumbnails and ForeignData
/// typically emit: window mapping, pens/brushes/fonts, polygon/polyline,
/// rectangle/ellipse, and ExtTextOut. `META_ESCAPE` blobs (often truncated
/// dual-mode EMF) are skipped — the native WMF drawing stream after them is
/// what actually paints.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'metafile_drawing.dart';

const int _placeableKey = 0x9AC6CDD7;

const int _metaSetWindowOrg = 0x020B;
const int _metaSetWindowExt = 0x020C;
const int _metaSetTextColor = 0x0209;
const int _metaSetTextAlign = 0x012E;
const int _metaCreatePenIndirect = 0x02FA;
const int _metaCreateBrushIndirect = 0x02FC;
const int _metaCreateFontIndirect = 0x02FB;
const int _metaSelectObject = 0x012D;
const int _metaDeleteObject = 0x01F0;
const int _metaPolygon = 0x0324;
const int _metaPolyline = 0x0325;
const int _metaPolyPolygon = 0x0538;
const int _metaRectangle = 0x041B;
const int _metaEllipse = 0x0418;
const int _metaMoveTo = 0x0214;
const int _metaLineTo = 0x0213;
const int _metaPolyBezier = 0x1008;
const int _metaExtTextOut = 0x0A32;
const int _metaTextOut = 0x0521;
const int _metaEscape = 0x0626;
const int _metaEof = 0x0000;

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
  var brushColor = 0xFFFFFFFF;
  var brushStyle = 1; // BS_NULL
  var textColor = 0xFF000000;
  var textAlign = 0;
  String? fontFace;
  var fontHeight = 12.0;
  double? winOrgX, winOrgY, winExtX, winExtY;
  double? curX, curY;
  final ops = <Object>[];

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
    } else if (func == _metaSetTextColor && params + 4 <= recEnd) {
      textColor = _rgbToArgb(bd.getUint32(params, Endian.little));
    } else if (func == _metaSetTextAlign && params + 2 <= recEnd) {
      textAlign = bd.getUint16(params, Endian.little);
    } else if (func == _metaCreatePenIndirect && params + 10 <= recEnd) {
      final style = bd.getUint16(params, Endian.little);
      final width = bd.getInt16(params + 2, Endian.little).abs().toDouble();
      final color = _rgbToArgb(bd.getUint32(params + 6, Endian.little));
      objects[allocSlot()] = _GdiPen(style, width == 0 ? 1.0 : width, color);
    } else if (func == _metaCreateBrushIndirect && params + 8 <= recEnd) {
      final style = bd.getUint16(params, Endian.little);
      final color = _rgbToArgb(bd.getUint32(params + 2, Endian.little));
      objects[allocSlot()] = _GdiBrush(style, color);
    } else if (func == _metaCreateFontIndirect && params + 18 <= recEnd) {
      final height =
          bd.getInt16(params, Endian.little).abs().toDouble().clamp(1.0, 500.0);
      String? face;
      final faceBytes = <int>[];
      for (var i = params + 18; i < recEnd && faceBytes.length < 32; i++) {
        final c = bytes[i];
        if (c == 0) break;
        faceBytes.add(c);
      }
      if (faceBytes.isNotEmpty) {
        face = latin1.decode(faceBytes, allowInvalid: true);
      }
      objects[allocSlot()] = _GdiFont(height, face);
    } else if (func == _metaSelectObject && params + 2 <= recEnd) {
      final ix = bd.getUint16(params, Endian.little);
      if (ix < objects.length) {
        final o = objects[ix];
        if (o is _GdiPen) {
          penStyle = o.style;
          penWidth = o.width;
          penColor = o.color;
        } else if (o is _GdiBrush) {
          brushStyle = o.style;
          brushColor = o.color;
        } else if (o is _GdiFont) {
          fontHeight = o.height;
          fontFace = o.face;
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
      final fromX = curX;
      final fromY = curY;
      final pts = [MetafilePoint(fromX, fromY), MetafilePoint(x, y)];
      ensureBounds(pts);
      if (penStyle != 5) {
        ops.add(MetafilePathOp(
          points: pts,
          closed: false,
          fill: false,
          stroke: true,
          fillArgb: 0,
          strokeArgb: penColor,
          strokeWidth: penWidth,
        ));
      }
      curX = x;
      curY = y;
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
          brushStyle: brushStyle,
          brushColor: brushColor,
        ));
      }
    } else if (func == _metaPolyline) {
      final pts = _readPoints(bd, params, recEnd);
      if (pts.length >= 2) {
        ensureBounds(pts);
        if (penStyle != 5) {
          ops.add(MetafilePathOp(
            points: pts,
            closed: false,
            fill: false,
            stroke: true,
            fillArgb: 0,
            strokeArgb: penColor,
            strokeWidth: penWidth,
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
        if (penStyle != 5) {
          ops.add(MetafilePathOp(
            points: dense,
            closed: false,
            fill: false,
            stroke: true,
            fillArgb: 0,
            strokeArgb: penColor,
            strokeWidth: penWidth,
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
          ops.add(_pathOp(
            pts,
            closed: true,
            penStyle: penStyle,
            penColor: penColor,
            penWidth: penWidth,
            brushStyle: brushStyle,
            brushColor: brushColor,
          ));
        }
      }
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
        brushStyle: brushStyle,
        brushColor: brushColor,
        asEllipse: func == _metaEllipse,
      ));
    } else if (func == _metaExtTextOut) {
      final textOp = _readExtTextOut(
        bd, bytes, params, recEnd, textColor, textAlign, fontHeight, fontFace,
      );
      if (textOp != null) {
        ensureBounds([MetafilePoint(textOp.x, textOp.y)]);
        ops.add(textOp);
      }
    } else if (func == _metaTextOut) {
      final textOp = _readTextOut(
        bd, bytes, params, recEnd, textColor, textAlign, fontHeight, fontFace,
      );
      if (textOp != null) {
        ensureBounds([MetafilePoint(textOp.x, textOp.y)]);
        ops.add(textOp);
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
  required int brushStyle,
  required int brushColor,
  bool asEllipse = false,
}) {
  final fill = brushStyle == 0;
  final stroke = penStyle != 5;
  return MetafilePathOp(
    points: pts,
    closed: closed,
    fill: fill,
    stroke: stroke,
    fillArgb: fill ? brushColor : 0,
    strokeArgb: stroke ? penColor : 0,
    strokeWidth: penWidth,
    isEllipse: asEllipse,
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
) {
  if (params + 8 > recEnd) return null;
  final y = bd.getInt16(params, Endian.little).toDouble();
  final x = bd.getInt16(params + 2, Endian.little).toDouble();
  final count = bd.getUint16(params + 4, Endian.little);
  final options = bd.getUint16(params + 6, Endian.little);
  var p = params + 8;
  if ((options & 0x0006) != 0) p += 8;
  if (count == 0 || p + count > recEnd) return null;
  final raw = bytes.sublist(p, p + count);
  final text = latin1.decode(raw, allowInvalid: true).replaceAll('\u0000', '');
  if (text.trim().isEmpty) return null;
  return MetafileTextOp(
    text: text,
    x: x,
    y: y,
    fontHeight: fontHeight,
    argb: textColor,
    face: fontFace,
    align: textAlign,
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
) {
  if (params + 2 > recEnd) return null;
  final count = bd.getUint16(params, Endian.little);
  var p = params + 2;
  if (count == 0 || p + count + 4 > recEnd) return null;
  final raw = bytes.sublist(p, p + count);
  p += count;
  if (count.isOdd) p++;
  if (p + 4 > recEnd) return null;
  final y = bd.getInt16(p, Endian.little).toDouble();
  final x = bd.getInt16(p + 2, Endian.little).toDouble();
  final text = latin1.decode(raw, allowInvalid: true).replaceAll('\u0000', '');
  if (text.trim().isEmpty) return null;
  return MetafileTextOp(
    text: text,
    x: x,
    y: y,
    fontHeight: fontHeight,
    argb: textColor,
    face: fontFace,
    align: textAlign,
  );
}

int _rgbToArgb(int colorRef) {
  final r = colorRef & 0xff;
  final g = (colorRef >> 8) & 0xff;
  final b = (colorRef >> 16) & 0xff;
  return 0xFF000000 | (r << 16) | (g << 8) | b;
}

sealed class _GdiObject {}

class _GdiPen extends _GdiObject {
  _GdiPen(this.style, this.width, this.color);
  final int style;
  final double width;
  final int color;
}

class _GdiBrush extends _GdiObject {
  _GdiBrush(this.style, this.color);
  final int style;
  final int color;
}

class _GdiFont extends _GdiObject {
  _GdiFont(this.height, this.face);
  final double height;
  final String? face;
}
