/// Replay a [MetafileDrawing] into a PNG Draw can paint as Foreign Bitmap.
///
/// The PNG is opaque (GDI paper white) so LibreOffice cannot show its
/// default Blue 2 graphic style through unpainted pixels. Polygon fill
/// is a scanline rasteriser — `package:image` 4.3 `fillPolygon` drops a
/// vertex whose `x` is slightly past `vertex.xi`, then pairs the leftover
/// hit with 0 and paints only a left-edge strip. ExtTextOut glyphs are
/// scaled from the bundled Arial bitmap so dimension labels survive the
/// bake; canvas / SVG still paint through `dart:ui`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as raster;

import 'metafile.dart';

/// Rasterise a parsed WMF/EMF display list. Logical Y grows downward (GDI).
Uint8List? rasterizeMetafileDrawingToPng(
  MetafileDrawing drawing, {
  int maxEdge = 2048,
}) {
  if (drawing.isEmpty) return null;
  final logicalW = drawing.width;
  final logicalH = drawing.height;
  if (!logicalW.isFinite || !logicalH.isFinite || logicalW <= 0 || logicalH <= 0) {
    return null;
  }
  final scale = math.min(maxEdge / logicalW, maxEdge / logicalH);
  final pxW = math.max(1, (logicalW * scale).round());
  final pxH = math.max(1, (logicalH * scale).round());
  final image = raster.Image(width: pxW, height: pxH, numChannels: 4);
  raster.fill(
    image,
    color: raster.ColorRgba8(255, 255, 255, 255),
  );

  var xf = _Affine.identity;
  final saved = <_Affine>[];

  raster.Point map(MetafilePoint p) {
    final t = xf.apply(p);
    return raster.Point(
      (t.x - drawing.minX) * scale,
      (t.y - drawing.minY) * scale,
    );
  }

  for (final op in drawing.ops) {
    if (op is MetafileSaveDcOp) {
      saved.add(xf);
    } else if (op is MetafileRestoreDcOp) {
      var count = math.min(op.count, saved.length);
      while (count-- > 0) {
        xf = saved.removeLast();
      }
    } else if (op is MetafileTransformOp) {
      xf = xf.then(_Affine(
        op.m11,
        op.m12,
        op.m21,
        op.m22,
        op.dx,
        op.dy,
      ));
    } else if (op is MetafilePixelOp) {
      final p = map(MetafilePoint(op.x, op.y));
      _put(image, p.x.round(), p.y.round(), op.argb);
    } else if (op is MetafilePathOp) {
      _paintPath(image, op, map, scale);
    } else if (op is MetafileBitmapOp) {
      _paintBitmap(image, op, map);
    } else if (op is MetafileGradientRectOp) {
      _paintGradientRect(image, op, map);
    } else if (op is MetafileGradientTriangleOp) {
      _fillContours(
        image,
        <List<raster.Point>>[
          <raster.Point>[
            map(op.first.point),
            map(op.second.point),
            map(op.third.point),
          ],
        ],
        op.first.argb,
        evenOdd: false,
      );
    } else if (op is MetafileTextOp) {
      _paintText(image, op, map, scale);
    }
  }

  return Uint8List.fromList(raster.encodePng(image));
}

/// Parse [bytes] as WMF/EMF/OLE and rasterise when there is no wrapped DIB.
Uint8List? rasterizeVectorMetafileToPng(
  Uint8List bytes, {
  String mimeType = '',
  String partName = '',
  int maxEdge = 2048,
}) {
  final drawing = parseMetafileDrawing(
    bytes,
    mimeType: mimeType,
    partName: partName,
  );
  if (drawing == null || drawing.isEmpty) return null;
  return rasterizeMetafileDrawingToPng(drawing, maxEdge: maxEdge);
}

class _Affine {
  const _Affine(this.a, this.b, this.c, this.d, this.e, this.f);

  static const identity = _Affine(1, 0, 0, 1, 0, 0);

  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;

  /// Apply [delta] first (same order as `Canvas.transform`).
  _Affine then(_Affine delta) => _Affine(
        a * delta.a + c * delta.b,
        b * delta.a + d * delta.b,
        a * delta.c + c * delta.d,
        b * delta.c + d * delta.d,
        a * delta.e + c * delta.f + e,
        b * delta.e + d * delta.f + f,
      );

  MetafilePoint apply(MetafilePoint p) => MetafilePoint(
        a * p.x + c * p.y + e,
        b * p.x + d * p.y + f,
      );
}

void _paintPath(
  raster.Image image,
  MetafilePathOp op,
  raster.Point Function(MetafilePoint) map,
  double scale,
) {
  if (op.points.isEmpty) return;
  if (op.rasterOperation == MetafileRasterOperation.nop) return;
  final mapped = <raster.Point>[for (final p in op.points) map(p)];
  final extra = <List<raster.Point>>[
    for (final contour in op.additionalContours)
      [for (final p in contour.points) map(p)],
  ];
  final rx = op.cornerRadiusX;
  final ry = op.cornerRadiusY ?? rx;
  final fillContour = !op.isEllipse &&
          rx != null &&
          rx.abs() > 0 &&
          extra.isEmpty
      ? _densifyRRect(
          mapped,
          rx.abs() * scale,
          (ry ?? rx).abs() * scale,
        )
      : mapped;
  final contours = <List<raster.Point>>[fillContour, ...extra];
  if (op.fill) {
    final color = op.fillHatch != null && op.fillBackgroundArgb != null
        ? op.fillBackgroundArgb!
        : op.fillArgb;
    if (op.isEllipse && mapped.length >= 2) {
      _fillEllipse(image, mapped, color);
    } else if (extra.isEmpty && _isAxisAlignedRect(fillContour)) {
      _fillBounds(image, fillContour, color);
    } else {
      _fillContours(image, contours, color, evenOdd: op.evenOddFill);
    }
  }
  if (op.stroke) {
    final thickness = math.max(1, (op.strokeWidth.abs() * scale).round());
    final color = _color(op.strokeArgb);
    for (final contour in contours) {
      if (contour.length < 2) continue;
      for (var i = 1; i < contour.length; i++) {
        raster.drawLine(
          image,
          x1: contour[i - 1].x.round(),
          y1: contour[i - 1].y.round(),
          x2: contour[i].x.round(),
          y2: contour[i].y.round(),
          color: color,
          thickness: thickness,
        );
      }
      if (op.closed || (op.isEllipse && contour.length >= 3)) {
        raster.drawLine(
          image,
          x1: contour.last.x.round(),
          y1: contour.last.y.round(),
          x2: contour.first.x.round(),
          y2: contour.first.y.round(),
          color: color,
          thickness: thickness,
        );
      }
    }
  }
}

bool _isAxisAlignedRect(List<raster.Point> pts) {
  if (pts.length != 4) return false;
  final xs = <int>{
    for (final p in pts) p.x.round(),
  };
  final ys = <int>{
    for (final p in pts) p.y.round(),
  };
  return xs.length == 2 && ys.length == 2;
}

void _fillBounds(raster.Image image, List<raster.Point> pts, int argb) {
  var minX = pts.first.x;
  var maxX = pts.first.x;
  var minY = pts.first.y;
  var maxY = pts.first.y;
  for (final p in pts) {
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
  }
  _fillRect(
    image,
    raster.Point(minX, minY),
    raster.Point(maxX, maxY),
    argb,
  );
}

List<raster.Point> _densifyRRect(
  List<raster.Point> corners,
  double radiusX,
  double radiusY,
) {
  if (corners.length < 2) return corners;
  var minX = corners.first.x;
  var maxX = corners.first.x;
  var minY = corners.first.y;
  var maxY = corners.first.y;
  for (final p in corners) {
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
  }
  final rx = math.min(radiusX, (maxX - minX) / 2);
  final ry = math.min(radiusY, (maxY - minY) / 2);
  if (rx <= 0 || ry <= 0) {
    return <raster.Point>[
      raster.Point(minX, minY),
      raster.Point(maxX, minY),
      raster.Point(maxX, maxY),
      raster.Point(minX, maxY),
    ];
  }
  final points = <raster.Point>[];
  void addCorner(double cx, double cy, double startAngle) {
    for (var i = 0; i <= 8; i++) {
      final angle = startAngle + math.pi * i / 16;
      points.add(raster.Point(
        cx + rx * math.cos(angle),
        cy + ry * math.sin(angle),
      ));
    }
  }

  addCorner(maxX - rx, minY + ry, -math.pi / 2);
  addCorner(maxX - rx, maxY - ry, 0);
  addCorner(minX + rx, maxY - ry, math.pi / 2);
  addCorner(minX + rx, minY + ry, math.pi);
  return points;
}

class _ScanHit {
  const _ScanHit(this.x, this.delta);
  final double x;
  final int delta;
}

void _fillContours(
  raster.Image image,
  List<List<raster.Point>> contours,
  int argb, {
  required bool evenOdd,
}) {
  final color = _color(argb);
  if (color.a.toInt() == 0) return;
  final edges = <(double, double, double, double)>[];
  for (final contour in contours) {
    if (contour.length < 3) continue;
    for (var i = 0; i < contour.length; i++) {
      final a = contour[i];
      final b = contour[(i + 1) % contour.length];
      if (a.y == b.y) continue;
      edges.add((a.x.toDouble(), a.y.toDouble(), b.x.toDouble(), b.y.toDouble()));
    }
  }
  if (edges.isEmpty) return;
  var yMin = edges.first.$2;
  var yMax = edges.first.$2;
  for (final e in edges) {
    yMin = math.min(yMin, math.min(e.$2, e.$4));
    yMax = math.max(yMax, math.max(e.$2, e.$4));
  }
  final y0 = yMin.floor().clamp(0, image.height - 1);
  final y1 = yMax.ceil().clamp(0, image.height - 1);
  for (var yi = y0; yi <= y1; yi++) {
    final y = yi + 0.5;
    final hits = <_ScanHit>[];
    for (final e in edges) {
      final x1 = e.$1;
      final y1e = e.$2;
      final x2 = e.$3;
      final y2e = e.$4;
      if ((y1e <= y && y2e > y) || (y2e <= y && y1e > y)) {
        final t = (y - y1e) / (y2e - y1e);
        hits.add(_ScanHit(x1 + t * (x2 - x1), y2e > y1e ? 1 : -1));
      }
    }
    if (hits.isEmpty) continue;
    hits.sort((a, b) => a.x.compareTo(b.x));
    if (evenOdd) {
      for (var i = 0; i + 1 < hits.length; i += 2) {
        _fillSpan(image, yi, hits[i].x, hits[i + 1].x, color);
      }
    } else {
      var winding = 0;
      double? prev;
      for (final hit in hits) {
        if (winding != 0 && prev != null) {
          _fillSpan(image, yi, prev, hit.x, color);
        }
        winding += hit.delta;
        prev = hit.x;
      }
    }
  }
}

void _fillSpan(
  raster.Image image,
  int y,
  double x0,
  double x1,
  raster.ColorRgba8 color,
) {
  if (y < 0 || y >= image.height) return;
  var a = math.min(x0, x1).round();
  var b = math.max(x0, x1).round();
  if (a > image.width - 1 || b < 0) return;
  a = a.clamp(0, image.width - 1);
  b = b.clamp(0, image.width - 1);
  final r = color.r.toInt();
  final g = color.g.toInt();
  final bl = color.b.toInt();
  final al = color.a.toInt();
  if (al >= 255) {
    for (var x = a; x <= b; x++) {
      image.setPixelRgba(x, y, r, g, bl, 255);
    }
    return;
  }
  for (var x = a; x <= b; x++) {
    raster.drawPixel(image, x, y, color);
  }
}

void _paintBitmap(
  raster.Image image,
  MetafileBitmapOp op,
  raster.Point Function(MetafilePoint) map,
) {
  final decoded = raster.decodeBmp(op.bmpBytes) ?? raster.decodeImage(op.bmpBytes);
  if (decoded == null || decoded.width <= 0 || decoded.height <= 0) return;
  final dest = op.destination;
  final p0 = map(MetafilePoint(dest.minX, dest.minY));
  final p1 = map(MetafilePoint(dest.maxX, dest.maxY));
  final x = math.min(p0.x, p1.x).round();
  final y = math.min(p0.y, p1.y).round();
  final w = math.max(1, (p0.x - p1.x).abs().round());
  final h = math.max(1, (p0.y - p1.y).abs().round());
  raster.compositeImage(
    image,
    decoded,
    dstX: x,
    dstY: y,
    dstW: w,
    dstH: h,
  );
}

void _paintGradientRect(
  raster.Image image,
  MetafileGradientRectOp op,
  raster.Point Function(MetafilePoint) map,
) {
  _fillRect(
    image,
    map(op.upperLeft.point),
    map(op.lowerRight.point),
    op.upperLeft.argb,
  );
}

void _fillRect(
  raster.Image image,
  raster.Point a,
  raster.Point b,
  int argb,
) {
  raster.fillRect(
    image,
    x1: math.min(a.x, b.x).round(),
    y1: math.min(a.y, b.y).round(),
    x2: math.max(a.x, b.x).round(),
    y2: math.max(a.y, b.y).round(),
    color: _color(argb),
  );
}

void _fillEllipse(raster.Image image, List<raster.Point> pts, int argb) {
  if (pts.length < 2) return;
  var minX = pts.first.x;
  var maxX = pts.first.x;
  var minY = pts.first.y;
  var maxY = pts.first.y;
  for (final p in pts) {
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
  }
  final cx = (minX + maxX) / 2;
  final cy = (minY + maxY) / 2;
  final rx = math.max((maxX - minX) / 2, 0.5);
  final ry = math.max((maxY - minY) / 2, 0.5);
  final color = _color(argb);
  final x0 = minX.floor().clamp(0, image.width - 1);
  final x1 = maxX.ceil().clamp(0, image.width - 1);
  final y0 = minY.floor().clamp(0, image.height - 1);
  final y1 = maxY.ceil().clamp(0, image.height - 1);
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final nx = (x + 0.5 - cx) / rx;
      final ny = (y + 0.5 - cy) / ry;
      if (nx * nx + ny * ny <= 1) {
        image.setPixelRgba(
          x,
          y,
          color.r.toInt(),
          color.g.toInt(),
          color.b.toInt(),
          color.a.toInt(),
        );
      }
    }
  }
}

void _put(raster.Image image, int x, int y, int argb) {
  if (x < 0 || y < 0 || x >= image.width || y >= image.height) return;
  final color = _color(argb);
  image.setPixelRgba(
    x,
    y,
    color.r.toInt(),
    color.g.toInt(),
    color.b.toInt(),
    color.a.toInt(),
  );
}

void _paintText(
  raster.Image image,
  MetafileTextOp op,
  raster.Point Function(MetafilePoint) map,
  double scale,
) {
  final opaque = op.opaqueRect;
  if (opaque != null) {
    _fillRect(
      image,
      map(MetafilePoint(opaque.minX, opaque.minY)),
      map(MetafilePoint(opaque.maxX, opaque.maxY)),
      op.backgroundArgb ?? op.argb,
    );
  }
  if (op.text.isEmpty) return;
  final origin = map(MetafilePoint(op.x, op.y));
  final pxHeight = math.max(6, (op.fontHeight.abs() * scale).round());
  final layer = _glyphLayer(op, pxHeight);
  if (layer == null) return;
  var sprite = layer;
  final angle = op.escapementDegrees % 360;
  if (angle.abs() > 0.5) {
    sprite = raster.copyRotate(
      sprite,
      angle: -angle,
      interpolation: raster.Interpolation.linear,
    );
  }
  final destW = sprite.width;
  var dx = origin.x;
  final align = op.align & 0x06;
  if (align == 6) {
    dx -= destW / 2;
  } else if (align == 2) {
    dx -= destW;
  }
  var dy = origin.y;
  switch (op.align & 0x18) {
    case 0x00:
      break;
    case 0x08:
      dy -= sprite.height;
    default:
      dy -= sprite.height * 0.85;
  }
  raster.compositeImage(
    image,
    sprite,
    dstX: dx.round(),
    dstY: dy.round(),
  );
  if (op.underline || op.strikeThrough) {
    final y = op.underline
        ? dy + sprite.height * 0.9
        : dy + sprite.height * 0.45;
    raster.drawLine(
      image,
      x1: dx.round(),
      y1: y.round(),
      x2: (dx + destW).round(),
      y2: y.round(),
      color: _color(op.argb),
      thickness: math.max(1, pxHeight ~/ 12),
    );
  }
}

raster.Image? _glyphLayer(MetafileTextOp op, int pxHeight) {
  final font = raster.arial48;
  final color = _color(op.argb);
  if (color.a.toInt() == 0) return null;
  final runes = op.text.runes.toList(growable: false);
  if (runes.isEmpty) return null;
  final advances = op.advancesX;
  final useAdvances = advances != null &&
      advances.length == runes.length &&
      advances.every((a) => a.isFinite && a.abs() < 1e6);
  var widthPx = 2;
  if (useAdvances) {
    widthPx += advances
        .fold<double>(0, (sum, a) => sum + a.abs())
        .round()
        .clamp(1, 4096);
    widthPx = math.max(
      8,
      (widthPx * font.lineHeight / math.max(op.fontHeight.abs(), 1)).round(),
    );
  } else {
    for (final r in runes) {
      final ch = font.characters[r];
      widthPx += ch?.xAdvance ?? font.base ~/ 2;
    }
  }
  widthPx = widthPx.clamp(8, 4096);
  final heightPx = (font.lineHeight + 4).clamp(8, 512);
  final layer = raster.Image(width: widthPx, height: heightPx, numChannels: 4);
  var x = 1.0;
  for (var i = 0; i < runes.length; i++) {
    final r = runes[i];
    final ch = font.characters[r];
    if (ch != null) {
      raster.drawChar(
        layer,
        String.fromCharCode(r),
        font: font,
        x: x.round(),
        y: 1,
        color: color,
      );
    } else {
      final tofu = math.max(4, font.base ~/ 2);
      raster.fillRect(
        layer,
        x1: x.round(),
        y1: 1 + font.lineHeight ~/ 5,
        x2: x.round() + tofu,
        y2: 1 + font.lineHeight * 4 ~/ 5,
        color: color,
      );
    }
    if (useAdvances) {
      x += advances[i].abs() * font.lineHeight / math.max(op.fontHeight.abs(), 1);
    } else {
      x += (ch?.xAdvance ?? font.base ~/ 2).toDouble();
    }
  }
  final destH = pxHeight.clamp(6, 512);
  final destW =
      math.max(6, (layer.width * destH / heightPx).round().clamp(6, 2048));
  return raster.copyResize(
    layer,
    width: destW,
    height: destH,
    interpolation: raster.Interpolation.linear,
  );
}

raster.ColorRgba8 _color(int argb) {
  var a = (argb >> 24) & 0xff;
  final r = (argb >> 16) & 0xff;
  final g = (argb >> 8) & 0xff;
  final b = argb & 0xff;
  if (a == 0 && (r | g | b) != 0) a = 255;
  return raster.ColorRgba8(r, g, b, a);
}
