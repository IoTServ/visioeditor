/// Rasterise a [MetafileDrawing] to a [ui.Image] for the canvas image cache.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:vsdx/vsdx.dart';

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
    if (op is MetafilePathOp) {
      _paintPath(canvas, op);
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

void _paintPath(Canvas canvas, MetafilePathOp op) {
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

  if (op.isEllipse && op.points.length >= 2) {
    double minX = op.points.first.x, maxX = op.points.first.x;
    double minY = op.points.first.y, maxY = op.points.first.y;
    for (final p in op.points) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
    final rect = Rect.fromLTRB(minX, minY, maxX, maxY);
    if (op.fill) canvas.drawOval(rect, paintFill);
    if (op.stroke) canvas.drawOval(rect, paintStroke);
    return;
  }

  final path = Path()..moveTo(op.points.first.x, op.points.first.y);
  for (var i = 1; i < op.points.length; i++) {
    path.lineTo(op.points[i].x, op.points[i].y);
  }
  if (op.closed) path.close();
  if (op.fill) canvas.drawPath(path, paintFill);
  if (op.stroke) canvas.drawPath(path, paintStroke);
}

void _paintText(Canvas canvas, MetafileTextOp op) {
  final fontSize = math.max(op.fontHeight.abs(), 1.0);
  // GDI text baseline is near (x,y); Flutter paints from top-left of glyphs.
  final tp = TextPainter(
    text: TextSpan(
      text: op.text,
      style: TextStyle(
        color: Color(op.argb),
        fontSize: fontSize,
        fontFamily: op.face,
        height: 1.0,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.left,
  )..layout();
  var dx = op.x;
  var dy = op.y - fontSize * 0.85;
  // TA_CENTER = 6, TA_RIGHT = 2 (low bits).
  final align = op.align & 0x07;
  if (align == 6) {
    dx -= tp.width / 2;
  } else if (align == 2) {
    dx -= tp.width;
  }
  tp.paint(canvas, Offset(dx, dy));
}
