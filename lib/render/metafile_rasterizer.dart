/// Rasterise a [MetafileDrawing] to a [ui.Image] for the canvas image cache.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:vsdx/vsdx.dart';

import 'dash_path.dart';

/// Paint [drawing] into an image. Logical metafile Y grows downward (GDI);
/// the result is a top-left origin bitmap suitable for [Canvas.drawImageRect]
/// after the painter's usual Y flip.
Future<ui.Image?> rasterizeMetafileDrawing(
  MetafileDrawing drawing, {
  int maxEdge = 2048,
}) async {
  if (drawing.isEmpty) return null;
  final bitmapImages = <MetafileBitmapOp, ui.Image>{};
  for (final op in drawing.ops.whereType<MetafileBitmapOp>()) {
    try {
      final codec = await ui.instantiateImageCodec(op.bmpBytes);
      try {
        final frame = await codec.getNextFrame();
        bitmapImages[op] = frame.image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      // Keep replaying later operations when one malformed embedded DIB fails.
    }
  }
  final patternImages = <MetafilePathOp, ui.Image>{};
  for (final op in drawing.ops.whereType<MetafilePathOp>()) {
    final bytes = op.fillPatternBmpBytes;
    if (bytes == null) continue;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        patternImages[op] = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      // A malformed pattern brush must not suppress later metafile records.
    }
  }
  final logicalW = drawing.width;
  final logicalH = drawing.height;
  final scale = math.min(maxEdge / logicalW, maxEdge / logicalH);
  final pxW = math.max(1, (logicalW * scale).round());
  final pxH = math.max(1, (logicalH * scale).round());

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, pxW.toDouble(), pxH.toDouble()),
    Paint()..color = const Color(0x00000000),
  );
  canvas.scale(scale, scale);
  canvas.translate(-drawing.minX, -drawing.minY);

  var savedDcCount = 0;
  for (final op in drawing.ops) {
    if (op is MetafileSaveDcOp) {
      canvas.save();
      savedDcCount++;
    } else if (op is MetafileRestoreDcOp) {
      var count = math.min(op.count, savedDcCount);
      while (count-- > 0) {
        canvas.restore();
        savedDcCount--;
      }
    } else if (op is MetafileTransformOp) {
      canvas.transform(Float64List.fromList(<double>[
        op.m11, op.m12, 0, 0,
        op.m21, op.m22, 0, 0,
        0, 0, 1, 0,
        op.dx, op.dy, 0, 1,
      ]));
    } else if (op is MetafileClipRectOp) {
      final rect = op.rect;
      canvas.clipRect(
        Rect.fromLTRB(rect.minX, rect.minY, rect.maxX, rect.maxY),
        clipOp: op.mode == MetafileClipCombineMode.intersect
            ? ui.ClipOp.intersect
            : ui.ClipOp.difference,
      );
    } else if (op is MetafileClipPathOp) {
      canvas.clipPath(
        _metafileClipPath(
          op,
          excludeBounds: op.mode == MetafileClipCombineMode.exclude
              ? Rect.fromLTRB(
                  drawing.minX,
                  drawing.minY,
                  drawing.maxX,
                  drawing.maxY,
                )
              : null,
        ),
      );
    } else if (op is MetafilePixelOp) {
      canvas.drawRect(
        Rect.fromLTWH(op.x, op.y, 1, 1),
        Paint()
          ..color = Color(op.argb)
          ..isAntiAlias = false,
      );
    } else if (op is MetafileBitmapOp) {
      final image = bitmapImages[op];
      if (image == null) continue;
      final source = op.source;
      final sourceRect = source == null
          ? Rect.fromLTWH(
              0,
              0,
              op.pixelWidth.toDouble(),
              op.pixelHeight.toDouble(),
            )
          : Rect.fromLTRB(source.minX, source.minY, source.maxX, source.maxY);
      final destination = op.destination;
      final flipX = (destination.right < destination.left) !=
          (source != null && source.right < source.left);
      final flipY = (destination.bottom < destination.top) !=
          (source != null && source.bottom < source.top);
      canvas.save();
      final parallelogram = op.destinationParallelogram;
      if (parallelogram != null && parallelogram.length == 3) {
        final p0 = parallelogram[0];
        var ax = parallelogram[1].x - p0.x;
        var ay = parallelogram[1].y - p0.y;
        var bx = parallelogram[2].x - p0.x;
        var by = parallelogram[2].y - p0.y;
        var tx = p0.x;
        var ty = p0.y;
        if (source != null && source.right < source.left) {
          tx += ax;
          ty += ay;
          ax = -ax;
          ay = -ay;
        }
        if (source != null && source.bottom < source.top) {
          tx += bx;
          ty += by;
          bx = -bx;
          by = -by;
        }
        canvas.transform(Float64List.fromList(<double>[
          ax, ay, 0, 0,
          bx, by, 0, 0,
          0, 0, 1, 0,
          tx, ty, 0, 1,
        ]));
      } else if (flipX || flipY) {
        canvas.translate(
          flipX ? destination.left + destination.right : 0,
          flipY ? destination.top + destination.bottom : 0,
        );
        canvas.scale(flipX ? -1 : 1, flipY ? -1 : 1);
      }
      canvas.drawImageRect(
        image,
        sourceRect,
        parallelogram != null && parallelogram.length == 3
            ? const Rect.fromLTWH(0, 0, 1, 1)
            : Rect.fromLTRB(
                destination.minX,
                destination.minY,
                destination.maxX,
                destination.maxY,
              ),
        Paint()
          ..filterQuality = FilterQuality.low
          ..color = Color.fromARGB(
            (op.opacity.clamp(0.0, 1.0) * 255).round(),
            255,
            255,
            255,
          ),
      );
      canvas.restore();
    } else if (op is MetafileGradientRectOp) {
      final upperLeft = op.upperLeft;
      final lowerRight = op.lowerRight;
      final rect = Rect.fromLTRB(
        math.min(upperLeft.point.x, lowerRight.point.x),
        math.min(upperLeft.point.y, lowerRight.point.y),
        math.max(upperLeft.point.x, lowerRight.point.x),
        math.max(upperLeft.point.y, lowerRight.point.y),
      );
      if (rect.width == 0 || rect.height == 0) continue;
      final start = upperLeft.point;
      final end = lowerRight.point;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(start.x, start.y),
            op.horizontal
                ? Offset(end.x, start.y)
                : Offset(start.x, end.y),
            <Color>[Color(upperLeft.argb), Color(lowerRight.argb)],
          ),
      );
    } else if (op is MetafileGradientTriangleOp) {
      final vertices = ui.Vertices(
        ui.VertexMode.triangles,
        <Offset>[
          Offset(op.first.point.x, op.first.point.y),
          Offset(op.second.point.x, op.second.point.y),
          Offset(op.third.point.x, op.third.point.y),
        ],
        colors: <Color>[
          Color(op.first.argb),
          Color(op.second.argb),
          Color(op.third.argb),
        ],
      );
      canvas.drawVertices(vertices, BlendMode.dst, Paint());
      vertices.dispose();
    } else if (op is MetafilePathOp) {
      _paintPath(
        canvas,
        op,
        deviceScale: scale,
        patternImage: patternImages[op],
      );
    } else if (op is MetafileTextOp) {
      _paintText(canvas, op);
    }
  }
  while (savedDcCount > 0) {
    canvas.restore();
    savedDcCount--;
  }

  final picture = recorder.endRecording();
  try {
    return await picture.toImage(pxW, pxH);
  } finally {
    picture.dispose();
    for (final image in bitmapImages.values) {
      image.dispose();
    }
    for (final image in patternImages.values) {
      image.dispose();
    }
  }
}

Path _metafileClipPath(MetafileClipPathOp op, {Rect? excludeBounds}) {
  final path = Path()
    ..fillType = excludeBounds != null || op.evenOddFill
        ? PathFillType.evenOdd
        : PathFillType.nonZero;
  if (excludeBounds != null) path.addRect(excludeBounds);

  void addContour(List<MetafilePoint> points) {
    if (points.isEmpty) return;
    path.moveTo(points.first.x, points.first.y);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].x, points[i].y);
    }
    path.close();
  }

  addContour(op.points);
  for (final contour in op.additionalContours) {
    addContour(contour.points);
  }
  return path;
}

void _paintPath(
  Canvas canvas,
  MetafilePathOp op, {
  required double deviceScale,
  ui.Image? patternImage,
}) {
  if (op.points.isEmpty) return;
  if (op.rasterOperation == MetafileRasterOperation.nop) return;
  void applyRaster(Paint paint) {
    switch (op.rasterOperation) {
      case MetafileRasterOperation.invert:
        paint
          ..color = const Color(0xffffffff)
          ..blendMode = BlendMode.difference;
      case MetafileRasterOperation.xor:
        // Flutter has no bitwise XOR blend; difference is the closest
        // premultiplied replay and matches LibreOffice's Xor raster action
        // for the opaque pen/brush colors emitted by Visio.
        paint.blendMode = BlendMode.difference;
      case MetafileRasterOperation.overpaint:
      case MetafileRasterOperation.nop:
        break;
    }
  }
  final paintFill = Paint()
    ..style = PaintingStyle.fill
    ..color = Color(op.fillArgb)
    ..isAntiAlias = true;
  final paintStroke = Paint()
    ..style = PaintingStyle.stroke
    ..color = Color(op.strokeArgb)
    ..strokeWidth = math.max(op.strokeWidth, 0.5)
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  applyRaster(paintFill);
  applyRaster(paintStroke);

  final path = Path()
    ..fillType = op.evenOddFill ? PathFillType.evenOdd : PathFillType.nonZero;
  if ((op.isEllipse || op.cornerRadiusX != null) && op.points.length >= 2) {
    double minX = op.points.first.x, maxX = op.points.first.x;
    double minY = op.points.first.y, maxY = op.points.first.y;
    for (final p in op.points) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
    final rect = Rect.fromLTRB(minX, minY, maxX, maxY);
    if (op.isEllipse) {
      path.addOval(rect);
    } else {
      final radiusX = math.min(op.cornerRadiusX!.abs(), rect.width / 2);
      final radiusY = math.min(
        (op.cornerRadiusY ?? op.cornerRadiusX!).abs(),
        rect.height / 2,
      );
      path.addRRect(RRect.fromRectAndCorners(
        rect,
        topLeft: Radius.elliptical(radiusX, radiusY),
        topRight: Radius.elliptical(radiusX, radiusY),
        bottomRight: Radius.elliptical(radiusX, radiusY),
        bottomLeft: Radius.elliptical(radiusX, radiusY),
      ));
    }
  } else {
    void addContour(List<MetafilePoint> points, {required bool closed}) {
      if (points.isEmpty) return;
      path.moveTo(points.first.x, points.first.y);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i].x, points[i].y);
      }
      if (closed) path.close();
    }

    addContour(op.points, closed: op.closed);
    for (final contour in op.additionalContours) {
      addContour(contour.points, closed: contour.closed);
    }
  }
  if (op.fill) {
    if (patternImage != null &&
        op.rasterOperation != MetafileRasterOperation.invert) {
      paintFill
        ..color = const Color(0xffffffff)
        ..shader = ui.ImageShader(
          patternImage,
          TileMode.repeated,
          TileMode.repeated,
          Float64List.fromList(<double>[
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
          ]),
          filterQuality: FilterQuality.none,
        );
      canvas.drawPath(path, paintFill);
    } else if (op.fillHatch == null) {
      canvas.drawPath(path, paintFill);
    } else {
      final background = op.fillBackgroundArgb;
      if (background != null) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.fill
            ..color = Color(background)
            ..isAntiAlias = true,
        );
      }
      canvas.save();
      canvas.clipPath(path);
      _paintHatch(
        canvas,
        path.getBounds(),
        op.fillHatch!,
        op.fillArgb,
        spacing: 8 / deviceScale,
        strokeWidth: 1 / deviceScale,
      );
      canvas.restore();
    }
  }
  if (op.stroke) {
    final dash = op.strokeDashPattern;
    canvas.drawPath(
      dash == null || dash.isEmpty ? path : dashedPath(path, dash),
      paintStroke,
    );
  }
}

void _paintHatch(
  Canvas canvas,
  Rect bounds,
  int style,
  int argb, {
  required double spacing,
  required double strokeWidth,
}) {
  if (bounds.isEmpty || !spacing.isFinite || spacing <= 0) return;
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..color = Color(argb)
    ..strokeWidth = strokeWidth
    ..isAntiAlias = true;

  void horizontal() {
    for (var y = bounds.top; y <= bounds.bottom; y += spacing) {
      canvas.drawLine(Offset(bounds.left, y), Offset(bounds.right, y), paint);
    }
  }

  void vertical() {
    for (var x = bounds.left; x <= bounds.right; x += spacing) {
      canvas.drawLine(Offset(x, bounds.top), Offset(x, bounds.bottom), paint);
    }
  }

  void diagonal(bool descending) {
    final h = bounds.height;
    for (var x = bounds.left - h; x <= bounds.right; x += spacing) {
      final from = descending
          ? Offset(x, bounds.top)
          : Offset(x, bounds.bottom);
      final to = descending
          ? Offset(x + h, bounds.bottom)
          : Offset(x + h, bounds.top);
      canvas.drawLine(from, to, paint);
    }
  }

  switch (style) {
    case 0: // HS_HORIZONTAL
      horizontal();
      break;
    case 1: // HS_VERTICAL
      vertical();
      break;
    case 2: // HS_FDIAGONAL
      diagonal(false);
      break;
    case 3: // HS_BDIAGONAL
      diagonal(true);
      break;
    case 4: // HS_CROSS
      horizontal();
      vertical();
      break;
    case 5: // HS_DIAGCROSS
      diagonal(false);
      diagonal(true);
      break;
    default:
      horizontal();
      break;
  }
}

void _paintText(Canvas canvas, MetafileTextOp op) {
  final background = op.backgroundArgb;
  final opaqueRect = op.opaqueRect;
  if (background != null && opaqueRect != null) {
    canvas.drawRect(
      Rect.fromLTRB(
        opaqueRect.minX,
        opaqueRect.minY,
        opaqueRect.maxX,
        opaqueRect.maxY,
      ),
      Paint()..color = Color(background),
    );
  }
  if (op.text.isEmpty) return;

  final fontSize = math.max(op.fontHeight.abs(), 1.0);
  final style = TextStyle(
    color: Color(op.argb),
    fontSize: fontSize,
    fontFamily: op.face,
    fontWeight: _gdiFontWeight(op.fontWeight),
    fontStyle: op.italic ? FontStyle.italic : FontStyle.normal,
    decoration: TextDecoration.combine(<TextDecoration>[
      if (op.underline) TextDecoration.underline,
      if (op.strikeThrough) TextDecoration.lineThrough,
    ]),
    height: 1.0,
  );
  // GDI text baseline is near (x,y); Flutter paints from top-left of glyphs.
  final tp = TextPainter(
    text: TextSpan(text: op.text, style: style),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.left,
  )..layout();
  final glyphs = op.text.runes.toList(growable: false);
  final xAdvances = op.advancesX;
  final yAdvances = op.advancesY;
  final hasAdvances = xAdvances != null &&
      xAdvances.length == glyphs.length &&
      xAdvances.every((advance) => advance.isFinite) &&
      (yAdvances == null ||
          (yAdvances.length == glyphs.length &&
              yAdvances.every((advance) => advance.isFinite)));
  final textWidth = hasAdvances
      ? xAdvances.fold<double>(0, (sum, advance) => sum + advance).abs()
      : tp.width;
  var dx = 0.0;
  // GDI vertical alignment is encoded in bits 3-4. Flutter paints from the
  // glyph box's top edge, so convert the reference point before rotation.
  final dy = switch (op.align & 0x18) {
    0x00 => 0.0, // TA_TOP
    0x08 => -tp.height, // TA_BOTTOM
    _ => -fontSize * 0.85, // TA_BASELINE
  };
  // TA_UPDATECP is bit 0 and must not affect left/right/centre alignment.
  final align = op.align & 0x06;
  if (align == 6) {
    dx -= textWidth / 2;
  } else if (align == 2) {
    dx -= textWidth;
  }
  canvas.save();
  final clipRect = op.clipRect;
  if (clipRect != null) {
    canvas.clipRect(
      Rect.fromLTRB(
        clipRect.minX,
        clipRect.minY,
        clipRect.maxX,
        clipRect.maxY,
      ),
    );
  }
  canvas.translate(op.x, op.y);
  final angle = op.escapementDegrees % 360;
  if (angle.abs() > 1e-9) {
    // GDI logical coordinates grow down, so positive LOGFONT escapement is
    // the negative Canvas angle around the text reference point.
    canvas.rotate(-angle * math.pi / 180);
  }
  if (background != null && opaqueRect == null) {
    canvas.drawRect(
      Rect.fromLTWH(dx, dy, textWidth, tp.height),
      Paint()..color = Color(background),
    );
  }
  if (!hasAdvances) {
    tp.paint(canvas, Offset(dx, dy));
  } else {
    var glyphX = 0.0;
    var glyphY = 0.0;
    for (var i = 0; i < glyphs.length; i++) {
      final glyphPainter = TextPainter(
        text: TextSpan(text: String.fromCharCode(glyphs[i]), style: style),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
      )..layout();
      glyphPainter.paint(canvas, Offset(dx + glyphX, dy + glyphY));
      glyphX += xAdvances[i];
      if (yAdvances != null) glyphY += yAdvances[i];
    }
  }
  canvas.restore();
}

FontWeight _gdiFontWeight(int weight) {
  if (weight <= 0) return FontWeight.normal;
  final rounded = ((weight.clamp(100, 900) + 50) ~/ 100).clamp(1, 9);
  return FontWeight.values[rounded - 1];
}
