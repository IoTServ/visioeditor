/// Rasterise a [MetafileDrawing] to a [ui.Image] for the canvas image cache.
library;

import 'dart:math' as math;
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

  for (final op in drawing.ops) {
    if (op is MetafilePixelOp) {
      canvas.drawRect(
        Rect.fromLTWH(op.x, op.y, 1, 1),
        Paint()
          ..color = Color(op.argb)
          ..isAntiAlias = false,
      );
    } else if (op is MetafilePathOp) {
      _paintPath(canvas, op, deviceScale: scale);
    } else if (op is MetafileTextOp) {
      _paintText(canvas, op);
    }
  }

  final picture = recorder.endRecording();
  try {
    return await picture.toImage(pxW, pxH);
  } finally {
    picture.dispose();
  }
}

void _paintPath(
  Canvas canvas,
  MetafilePathOp op, {
  required double deviceScale,
}) {
  if (op.points.isEmpty) return;
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
    if (op.fillHatch == null) {
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
