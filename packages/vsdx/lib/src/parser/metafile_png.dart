/// Replay a [MetafileDrawing] into a PNG Draw can paint as Foreign Bitmap.
///
/// The PNG is opaque (GDI paper white) so LibreOffice cannot show its
/// default Blue 2 graphic style through unpainted pixels. Polygon fill
/// is a scanline rasteriser — `package:image` 4.3 `fillPolygon` drops a
/// vertex whose `x` is slightly past `vertex.xi`, then pairs the leftover
/// hit with 0 and paints only a left-edge strip. Hatch brushes, tiled
/// DIB patterns and GDI clips match the canvas / SVG replay; ExtTextOut
/// glyphs are scaled from the bundled Arial bitmap so dimension labels
/// survive the bake. Canvas / SVG still paint through `dart:ui`.
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
  var clip = _Mask.unrestricted(pxW, pxH);
  final savedClips = <_Mask>[];

  raster.Point map(MetafilePoint p) {
    final t = xf.apply(p);
    return raster.Point(
      (t.x - drawing.minX) * scale,
      (t.y - drawing.minY) * scale,
    );
  }

  List<raster.Point> mapPoints(List<MetafilePoint> points) =>
      <raster.Point>[for (final p in points) map(p)];

  void combineClip(
    List<List<raster.Point>> contours, {
    required MetafileClipCombineMode mode,
    required bool evenOdd,
  }) {
    if (mode == MetafileClipCombineMode.intersect) {
      clip.intersectContours(contours, evenOdd: evenOdd);
    } else {
      clip.excludeContours(contours, evenOdd: evenOdd);
    }
  }

  for (final op in drawing.ops) {
    if (op is MetafileSaveDcOp) {
      saved.add(xf);
      savedClips.add(clip.clone());
    } else if (op is MetafileRestoreDcOp) {
      var count = math.min(op.count, saved.length);
      while (count-- > 0) {
        xf = saved.removeLast();
        clip = savedClips.removeLast();
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
    } else if (op is MetafileClipRectOp) {
      combineClip(
        <List<raster.Point>>[mapPoints(op.rect.corners)],
        mode: op.mode,
        evenOdd: false,
      );
    } else if (op is MetafileClipPathOp) {
      combineClip(
        <List<raster.Point>>[
          mapPoints(op.points),
          for (final contour in op.additionalContours) mapPoints(contour.points),
        ],
        mode: op.mode,
        evenOdd: op.evenOddFill,
      );
    } else if (op is MetafileOffsetClipOp) {
      final origin = map(const MetafilePoint(0, 0));
      final moved = map(MetafilePoint(op.dx, op.dy));
      clip.offset(
        (moved.x - origin.x).round(),
        (moved.y - origin.y).round(),
      );
    } else if (op is MetafilePixelOp) {
      final p = map(MetafilePoint(op.x, op.y));
      _put(image, p.x.round(), p.y.round(), op.argb, clip);
    } else if (op is MetafilePathOp) {
      _paintPath(image, op, map, scale, clip);
    } else if (op is MetafileBitmapOp) {
      _paintBitmap(image, op, map, clip);
    } else if (op is MetafileGradientRectOp) {
      _paintGradientRect(image, op, map, clip);
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
        clip: clip,
      );
    } else if (op is MetafileTextOp) {
      _paintText(image, op, map, scale, clip);
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
  _Mask clip,
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
    if (op.fillPatternBmpBytes != null) {
      _paintPatternFill(
        image,
        contours,
        op.fillPatternBmpBytes!,
        origin: map(MetafilePoint(op.fillOriginX, op.fillOriginY)),
        evenOdd: op.evenOddFill,
        ellipse: op.isEllipse && mapped.length >= 2,
        clip: clip,
      );
    } else if (op.fillHatch != null) {
      final background = op.fillBackgroundArgb;
      if (background != null) {
        _fillPath(
          image,
          mapped,
          extra,
          fillContour,
          background,
          evenOdd: op.evenOddFill,
          ellipse: op.isEllipse && mapped.length >= 2,
          clip: clip,
        );
      }
      _paintHatch(
        image,
        contours,
        op.fillHatch!,
        op.fillArgb,
        origin: map(MetafilePoint(op.fillOriginX, op.fillOriginY)),
        evenOdd: op.evenOddFill,
        ellipse: op.isEllipse && mapped.length >= 2,
        clip: clip,
      );
    } else {
      _fillPath(
        image,
        mapped,
        extra,
        fillContour,
        op.fillArgb,
        evenOdd: op.evenOddFill,
        ellipse: op.isEllipse && mapped.length >= 2,
        clip: clip,
      );
    }
  }
  if (op.stroke) {
    final thickness = math.max(1, (op.strokeWidth.abs() * scale).round());
    final dashes = op.strokeDashPattern;
    for (final contour in contours) {
      if (contour.length < 2) continue;
      for (var i = 1; i < contour.length; i++) {
        _strokeSegment(
          image,
          contour[i - 1],
          contour[i],
          op.strokeArgb,
          thickness,
          dashes,
          scale,
          clip,
        );
      }
      if (op.closed || (op.isEllipse && contour.length >= 3)) {
        _strokeSegment(
          image,
          contour.last,
          contour.first,
          op.strokeArgb,
          thickness,
          dashes,
          scale,
          clip,
        );
      }
    }
  }
}

void _fillPath(
  raster.Image image,
  List<raster.Point> mapped,
  List<List<raster.Point>> extra,
  List<raster.Point> fillContour,
  int argb, {
  required bool evenOdd,
  required bool ellipse,
  required _Mask clip,
}) {
  if (ellipse) {
    _fillEllipse(image, mapped, argb, clip);
  } else if (extra.isEmpty && _isAxisAlignedRect(fillContour)) {
    _fillBounds(image, fillContour, argb, clip);
  } else {
    _fillContours(
      image,
      <List<raster.Point>>[fillContour, ...extra],
      argb,
      evenOdd: evenOdd,
      clip: clip,
    );
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

void _fillBounds(
  raster.Image image,
  List<raster.Point> pts,
  int argb,
  _Mask clip,
) {
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
    clip,
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
  required _Mask clip,
}) {
  final color = _color(argb);
  if (color.a.toInt() == 0) return;
  _scanFill(
    image.width,
    image.height,
    contours,
    evenOdd: evenOdd,
    plot: (x, y) {
      if (!clip.contains(x, y)) return;
      image.setPixelRgba(
        x,
        y,
        color.r.toInt(),
        color.g.toInt(),
        color.b.toInt(),
        color.a.toInt(),
      );
    },
  );
}

void _paintBitmap(
  raster.Image image,
  MetafileBitmapOp op,
  raster.Point Function(MetafilePoint) map,
  _Mask clip,
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
  if (!clip.restricted) {
    raster.compositeImage(
      image,
      decoded,
      dstX: x,
      dstY: y,
      dstW: w,
      dstH: h,
    );
    return;
  }
  final scaled = raster.copyResize(
    decoded,
    width: w,
    height: h,
    interpolation: raster.Interpolation.linear,
  );
  for (var dy = 0; dy < h; dy++) {
    final py = y + dy;
    if (py < 0 || py >= image.height) continue;
    for (var dx = 0; dx < w; dx++) {
      final px = x + dx;
      if (!clip.contains(px, py)) continue;
      final pixel = scaled.getPixel(dx, dy);
      image.setPixelRgba(
        px,
        py,
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
        pixel.a.toInt(),
      );
    }
  }
}

void _paintGradientRect(
  raster.Image image,
  MetafileGradientRectOp op,
  raster.Point Function(MetafilePoint) map,
  _Mask clip,
) {
  _fillRect(
    image,
    map(op.upperLeft.point),
    map(op.lowerRight.point),
    op.upperLeft.argb,
    clip,
  );
}

void _fillRect(
  raster.Image image,
  raster.Point a,
  raster.Point b,
  int argb,
  _Mask clip,
) {
  final color = _color(argb);
  if (color.a.toInt() == 0) return;
  var x0 = math.min(a.x, b.x).round();
  var y0 = math.min(a.y, b.y).round();
  var x1 = math.max(a.x, b.x).round();
  var y1 = math.max(a.y, b.y).round();
  if (x1 < 0 || y1 < 0 || x0 >= image.width || y0 >= image.height) return;
  x0 = x0.clamp(0, image.width - 1);
  y0 = y0.clamp(0, image.height - 1);
  x1 = x1.clamp(0, image.width - 1);
  y1 = y1.clamp(0, image.height - 1);
  final r = color.r.toInt();
  final g = color.g.toInt();
  final bl = color.b.toInt();
  final al = color.a.toInt();
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      if (!clip.contains(x, y)) continue;
      image.setPixelRgba(x, y, r, g, bl, al);
    }
  }
}

void _fillEllipse(
  raster.Image image,
  List<raster.Point> pts,
  int argb,
  _Mask clip,
) {
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
      if (!clip.contains(x, y)) continue;
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

void _put(raster.Image image, int x, int y, int argb, _Mask clip) {
  if (!clip.contains(x, y)) return;
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
  _Mask clip,
) {
  var localClip = clip;
  final opaque = op.opaqueRect;
  if (op.clipRect != null) {
    localClip = clip.clone()
      ..intersectContours(
        <List<raster.Point>>[ <raster.Point>[
          for (final p in op.clipRect!.corners) map(p),
        ]],
        evenOdd: false,
      );
  }
  if (opaque != null) {
    _fillRect(
      image,
      map(MetafilePoint(opaque.minX, opaque.minY)),
      map(MetafilePoint(opaque.maxX, opaque.maxY)),
      op.backgroundArgb ?? op.argb,
      localClip,
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
  final destX = dx.round();
  final destY = dy.round();
  if (!localClip.restricted) {
    raster.compositeImage(
      image,
      sprite,
      dstX: destX,
      dstY: destY,
    );
  } else {
    for (var sy = 0; sy < sprite.height; sy++) {
      final py = destY + sy;
      if (py < 0 || py >= image.height) continue;
      for (var sx = 0; sx < sprite.width; sx++) {
        final px = destX + sx;
        if (!localClip.contains(px, py)) continue;
        final pixel = sprite.getPixel(sx, sy);
        if (pixel.a.toInt() < 8) continue;
        image.setPixelRgba(
          px,
          py,
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
          pixel.a.toInt(),
        );
      }
    }
  }
  if (op.underline || op.strikeThrough) {
    final y = op.underline
        ? dy + sprite.height * 0.9
        : dy + sprite.height * 0.45;
    _strokeSegment(
      image,
      raster.Point(dx, y),
      raster.Point(dx + destW, y),
      op.argb,
      math.max(1, pxHeight ~/ 12),
      null,
      scale,
      localClip,
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

void _scanFill(
  int width,
  int height,
  List<List<raster.Point>> contours, {
  required bool evenOdd,
  required void Function(int x, int y) plot,
}) {
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
  final y0 = yMin.floor().clamp(0, height - 1);
  final y1 = yMax.ceil().clamp(0, height - 1);
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
    void span(double x0, double x1) {
      var a = math.min(x0, x1).round();
      var b = math.max(x0, x1).round();
      if (a > width - 1 || b < 0) return;
      a = a.clamp(0, width - 1);
      b = b.clamp(0, width - 1);
      for (var x = a; x <= b; x++) {
        plot(x, yi);
      }
    }

    if (evenOdd) {
      for (var i = 0; i + 1 < hits.length; i += 2) {
        span(hits[i].x, hits[i + 1].x);
      }
    } else {
      var winding = 0;
      double? prev;
      for (final hit in hits) {
        if (winding != 0 && prev != null) span(prev, hit.x);
        winding += hit.delta;
        prev = hit.x;
      }
    }
  }
}

void _coverEllipse(
  Uint8List bits,
  int width,
  int height,
  List<raster.Point> pts,
  int value,
) {
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
  final x0 = minX.floor().clamp(0, width - 1);
  final x1 = maxX.ceil().clamp(0, width - 1);
  final y0 = minY.floor().clamp(0, height - 1);
  final y1 = maxY.ceil().clamp(0, height - 1);
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final nx = (x + 0.5 - cx) / rx;
      final ny = (y + 0.5 - cy) / ry;
      if (nx * nx + ny * ny <= 1) bits[y * width + x] = value;
    }
  }
}

_Mask _pathMask(
  int width,
  int height,
  List<List<raster.Point>> contours, {
  required bool evenOdd,
  required bool ellipse,
}) {
  final mask = _Mask.empty(width, height);
  if (ellipse && contours.isNotEmpty) {
    _coverEllipse(mask.bits!, width, height, contours.first, 1);
    return mask;
  }
  _scanFill(
    width,
    height,
    contours,
    evenOdd: evenOdd,
    plot: (x, y) => mask.bits![y * width + x] = 1,
  );
  return mask;
}

void _paintHatch(
  raster.Image image,
  List<List<raster.Point>> contours,
  int style,
  int argb, {
  required raster.Point origin,
  required bool evenOdd,
  required bool ellipse,
  required _Mask clip,
}) {
  final color = _color(argb);
  if (color.a.toInt() == 0) return;
  final cover = _pathMask(
    image.width,
    image.height,
    contours,
    evenOdd: evenOdd,
    ellipse: ellipse,
  );
  const spacing = 8.0;
  final originX = origin.x;
  final originY = origin.y;
  var minX = image.width;
  var maxX = 0;
  var minY = image.height;
  var maxY = 0;
  final coverBits = cover.bits!;
  for (var y = 0; y < image.height; y++) {
    final row = y * image.width;
    for (var x = 0; x < image.width; x++) {
      if (coverBits[row + x] == 0) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < minX) return;

  void plot(int x, int y) {
    if (x < minX || x > maxX || y < minY || y > maxY) return;
    if (coverBits[y * image.width + x] == 0) return;
    if (!clip.contains(x, y)) return;
    image.setPixelRgba(
      x,
      y,
      color.r.toInt(),
      color.g.toInt(),
      color.b.toInt(),
      color.a.toInt(),
    );
  }

  void horizontal() {
    final first =
        originY + ((minY - originY) / spacing).floor() * spacing;
    for (var y = first; y <= maxY; y += spacing) {
      final yi = y.round();
      for (var x = minX; x <= maxX; x++) {
        plot(x, yi);
      }
    }
  }

  void vertical() {
    final first =
        originX + ((minX - originX) / spacing).floor() * spacing;
    for (var x = first; x <= maxX; x += spacing) {
      final xi = x.round();
      for (var y = minY; y <= maxY; y++) {
        plot(xi, y);
      }
    }
  }

  void diagonal(bool descending) {
    final h = (maxY - minY).toDouble();
    final phase = descending ? originX - originY : originX + originY;
    final minimum = descending
        ? minX - maxY
        : minX + minY;
    final maximum = descending
        ? maxX - minY
        : maxX + maxY;
    final first = phase + ((minimum - phase) / spacing).floor() * spacing;
    for (var value = first; value <= maximum; value += spacing) {
      final x = descending ? value + minY : value - maxY;
      final from = descending
          ? raster.Point(x, minY.toDouble())
          : raster.Point(x, maxY.toDouble());
      final to = descending
          ? raster.Point(x + h, maxY.toDouble())
          : raster.Point(x + h, minY.toDouble());
      _bresenham(from, to, plot);
    }
  }

  switch (style) {
    case 0:
      horizontal();
    case 1:
      vertical();
    case 2:
      diagonal(false);
    case 3:
      diagonal(true);
    case 4:
      horizontal();
      vertical();
    case 5:
      diagonal(false);
      diagonal(true);
    default:
      horizontal();
  }
}

void _paintPatternFill(
  raster.Image image,
  List<List<raster.Point>> contours,
  Uint8List bmpBytes, {
  required raster.Point origin,
  required bool evenOdd,
  required bool ellipse,
  required _Mask clip,
}) {
  final decoded =
      raster.decodeBmp(bmpBytes) ?? raster.decodeImage(bmpBytes);
  if (decoded == null || decoded.width <= 0 || decoded.height <= 0) return;
  final tileW = decoded.width;
  final tileH = decoded.height;
  final cover = _pathMask(
    image.width,
    image.height,
    contours,
    evenOdd: evenOdd,
    ellipse: ellipse,
  );
  final originX = origin.x.round();
  final originY = origin.y.round();
  final bits = cover.bits!;
  for (var y = 0; y < image.height; y++) {
    final row = y * image.width;
    for (var x = 0; x < image.width; x++) {
      if (bits[row + x] == 0) continue;
      if (!clip.contains(x, y)) continue;
      final tx = _mod(x - originX, tileW);
      final ty = _mod(y - originY, tileH);
      final pixel = decoded.getPixel(tx, ty);
      image.setPixelRgba(
        x,
        y,
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
        pixel.a.toInt() == 0 ? 255 : pixel.a.toInt(),
      );
    }
  }
}

void _strokeSegment(
  raster.Image image,
  raster.Point a,
  raster.Point b,
  int argb,
  int thickness,
  List<double>? dashes,
  double scale,
  _Mask clip,
) {
  final color = _color(argb);
  if (color.a.toInt() == 0) return;
  final t = math.max(1, thickness);
  if ((dashes == null || dashes.isEmpty) && !clip.restricted && t == 1) {
    raster.drawLine(
      image,
      x1: a.x.round(),
      y1: a.y.round(),
      x2: b.x.round(),
      y2: b.y.round(),
      color: color,
      thickness: t,
    );
    return;
  }
  final points = <raster.Point>[];
  if (dashes == null || dashes.isEmpty) {
    points.add(a);
    points.add(b);
  } else {
    points.addAll(_dashPoints(a, b, dashes, scale));
  }
  void plot(int x, int y) {
    final r = t ~/ 2;
    for (var dy = -r; dy <= r; dy++) {
      for (var dx = -r; dx <= r; dx++) {
        final px = x + dx;
        final py = y + dy;
        if (!clip.contains(px, py)) continue;
        image.setPixelRgba(
          px,
          py,
          color.r.toInt(),
          color.g.toInt(),
          color.b.toInt(),
          color.a.toInt(),
        );
      }
    }
  }

  for (var i = 0; i + 1 < points.length; i += 2) {
    _bresenham(points[i], points[i + 1], plot);
  }
}

List<raster.Point> _dashPoints(
  raster.Point a,
  raster.Point b,
  List<double> dashes,
  double scale,
) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 1) return <raster.Point>[a, b];
  final ux = dx / len;
  final uy = dy / len;
  final pattern = <double>[
    for (final d in dashes) math.max(1, d.abs() * scale),
  ];
  if (pattern.length == 1) pattern.add(pattern.first);
  final out = <raster.Point>[];
  var dist = 0.0;
  var on = true;
  var pi = 0;
  var remaining = pattern[0];
  while (dist < len) {
    final step = math.min(remaining, len - dist);
    if (on) {
      out.add(raster.Point(a.x + ux * dist, a.y + uy * dist));
      out.add(raster.Point(a.x + ux * (dist + step), a.y + uy * (dist + step)));
    }
    dist += step;
    remaining -= step;
    if (remaining <= 0) {
      pi = (pi + 1) % pattern.length;
      remaining = pattern[pi];
      on = !on;
    }
  }
  return out;
}

void _bresenham(
  raster.Point a,
  raster.Point b,
  void Function(int x, int y) plot,
) {
  var x0 = a.x.round();
  var y0 = a.y.round();
  final x1 = b.x.round();
  final y1 = b.y.round();
  final dx = (x1 - x0).abs();
  final sx = x0 < x1 ? 1 : -1;
  final dy = -(y1 - y0).abs();
  final sy = y0 < y1 ? 1 : -1;
  var err = dx + dy;
  while (true) {
    plot(x0, y0);
    if (x0 == x1 && y0 == y1) break;
    final e2 = 2 * err;
    if (e2 >= dy) {
      err += dy;
      x0 += sx;
    }
    if (e2 <= dx) {
      err += dx;
      y0 += sy;
    }
  }
}

int _mod(int value, int modulus) {
  if (modulus <= 0) return 0;
  final r = value % modulus;
  return r < 0 ? r + modulus : r;
}

class _Mask {
  _Mask.unrestricted(this.width, this.height);

  _Mask.empty(this.width, this.height)
      : bits = Uint8List(width * height);

  _Mask._(this.width, this.height, this.bits);

  final int width;
  final int height;
  Uint8List? bits;

  bool get restricted => bits != null;

  bool contains(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return false;
    final data = bits;
    if (data == null) return true;
    return data[y * width + x] != 0;
  }

  _Mask clone() {
    final data = bits;
    if (data == null) return _Mask.unrestricted(width, height);
    return _Mask._(width, height, Uint8List.fromList(data));
  }

  void intersectContours(
    List<List<raster.Point>> contours, {
    required bool evenOdd,
  }) {
    final operand = Uint8List(width * height);
    _scanFill(
      width,
      height,
      contours,
      evenOdd: evenOdd,
      plot: (x, y) => operand[y * width + x] = 1,
    );
    final current = bits;
    if (current == null) {
      bits = operand;
      return;
    }
    for (var i = 0; i < current.length; i++) {
      if (operand[i] == 0) current[i] = 0;
    }
  }

  void excludeContours(
    List<List<raster.Point>> contours, {
    required bool evenOdd,
  }) {
    bits ??= Uint8List(width * height)..fillRange(0, width * height, 1);
    _scanFill(
      width,
      height,
      contours,
      evenOdd: evenOdd,
      plot: (x, y) => bits![y * width + x] = 0,
    );
  }

  void offset(int dx, int dy) {
    if (dx == 0 && dy == 0) return;
    final current = bits;
    if (current == null) return;
    final next = Uint8List(current.length);
    for (var y = 0; y < height; y++) {
      final ny = y + dy;
      if (ny < 0 || ny >= height) continue;
      for (var x = 0; x < width; x++) {
        final nx = x + dx;
        if (nx < 0 || nx >= width) continue;
        next[ny * width + nx] = current[y * width + x];
      }
    }
    bits = next;
  }
}
