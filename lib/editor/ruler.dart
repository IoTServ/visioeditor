import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../render/shape_bounds.dart';
import 'canvas_camera.dart';
import 'editor_controller.dart';

/// "Nice" tick spacing (inches) ladder for the rulers. The smallest entry
/// whose on-screen size is at least `minLabelPx` wins, so labels never crowd.
const List<double> _rulerLadder = <double>[
  0.0625, 0.125, 0.25, 0.5, 1, 2, 5, 10, 20, 50, 100, 200,
];

/// Pick a tick spacing in inches so that one step is at least [minLabelPx]
/// wide on screen. [pxPerInchOnScreen] = `canvas scale × pxPerInch`.
double niceRulerStepInches(double pxPerInchOnScreen, {double minLabelPx = 56}) {
  if (pxPerInchOnScreen <= 0) return 1;
  for (final s in _rulerLadder) {
    if (s * pxPerInchOnScreen >= minLabelPx) return s;
  }
  return _rulerLadder.last;
}

/// Every multiple of [step] inches within the inclusive `[minInch, maxInch]`
/// range (aligned to the origin), capped to keep pathological zoom-outs cheap.
List<double> rulerTicksInches(double minInch, double maxInch, double step) {
  if (step <= 0 || maxInch <= minInch) return const <double>[];
  final first = (minInch / step).floorToDouble() * step;
  final count = ((maxInch - first) / step).floor() + 1;
  if (count <= 0) return const <double>[];
  final n = math.min(count, 100000);
  return <double>[for (var i = 0; i < n; i++) first + i * step];
}

String _fmtInch(double v) {
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
  return s == '-0' ? '0' : s;
}

/// drawio-style rulers drawn along the top and left edges of the canvas. Reads
/// the live view transform from [camera] (so it tracks pan / zoom) and marks
/// the current selection's extent. Non-interactive — it never intercepts
/// canvas gestures.
class RulerOverlay extends StatelessWidget {
  const RulerOverlay({
    required this.controller,
    required this.camera,
    this.pxPerInch = 96.0,
    this.thickness = 22.0,
    super.key,
  });

  final EditorController controller;
  final CanvasCamera camera;
  final double pxPerInch;
  final double thickness;

  Rect? _selectionContentRect(EditorController c) {
    final page = c.currentPage;
    if (page == null || c.selection.isEmpty) return null;
    final bounds = buildShapeBounds(page);
    final ph = page.heightInches;
    double? xMin, xMax, yMin, yMax;
    for (final id in c.selection) {
      final b = bounds[id];
      if (b == null) continue;
      final l = b.left * pxPerInch;
      final r = b.right * pxPerInch;
      final y0 = (ph - b.bottom) * pxPerInch;
      final y1 = (ph - b.top) * pxPerInch;
      final yTop = math.min(y0, y1);
      final yBot = math.max(y0, y1);
      xMin = xMin == null ? l : math.min(xMin, l);
      xMax = xMax == null ? r : math.max(xMax, r);
      yMin = yMin == null ? yTop : math.min(yMin, yTop);
      yMax = yMax == null ? yBot : math.max(yMax, yBot);
    }
    if (xMin == null) return null;
    return Rect.fromLTRB(xMin, yMin!, xMax!, yMax!);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[controller, camera]),
        builder: (context, _) {
          if (controller.currentPage == null) return const SizedBox.shrink();
          return CustomPaint(
            painter: _RulerPainter(
              camera: camera,
              pxPerInch: pxPerInch,
              thickness: thickness,
              selection: _selectionContentRect(controller),
              bandColor: scheme.surfaceContainerHighest,
              borderColor: scheme.outlineVariant,
              tickColor: scheme.onSurfaceVariant,
              labelColor: scheme.onSurfaceVariant,
              highlightColor: scheme.primary,
            ),
          );
        },
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.camera,
    required this.pxPerInch,
    required this.thickness,
    required this.selection,
    required this.bandColor,
    required this.borderColor,
    required this.tickColor,
    required this.labelColor,
    required this.highlightColor,
  }) : super(repaint: camera);

  final CanvasCamera camera;
  final double pxPerInch;
  final double thickness;
  final Rect? selection;
  final Color bandColor;
  final Color borderColor;
  final Color tickColor;
  final Color labelColor;
  final Color highlightColor;

  @override
  void paint(Canvas canvas, Size size) {
    final t = thickness;
    final scale = camera.scale;
    final ppi = pxPerInch * scale; // on-screen px per inch
    if (ppi <= 0) return;
    final ox = camera.offset.dx; // screen x of inch 0
    final oy = camera.offset.dy; // screen y of inch 0

    final bandPaint = Paint()..color = bandColor;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = borderColor;
    final tickPaint = Paint()
      ..strokeWidth = 1
      ..color = tickColor;
    final highlightPaint = Paint()
      ..color = highlightColor.withValues(alpha: 0.18);

    // Bands.
    final topBand = Rect.fromLTWH(0, 0, size.width, t);
    final leftBand = Rect.fromLTWH(0, 0, t, size.height);
    canvas.drawRect(topBand, bandPaint);
    canvas.drawRect(leftBand, bandPaint);

    // Selection extent highlight (drawn under the ticks).
    final sel = selection;
    if (sel != null) {
      final sx0 = sel.left * ppi + ox;
      final sx1 = sel.right * ppi + ox;
      final sy0 = sel.top * ppi + oy;
      final sy1 = sel.bottom * ppi + oy;
      canvas.drawRect(
        Rect.fromLTRB(math.max(sx0, t), 0, math.max(sx1, t), t),
        highlightPaint,
      );
      canvas.drawRect(
        Rect.fromLTRB(0, math.max(sy0, t), t, math.max(sy1, t)),
        highlightPaint,
      );
    }

    final step = niceRulerStepInches(ppi);

    // Horizontal ruler (top band).
    final hMin = (t - ox) / ppi;
    final hMax = (size.width - ox) / ppi;
    for (final v in rulerTicksInches(hMin, hMax, step / 2)) {
      final x = v * ppi + ox;
      canvas.drawLine(Offset(x, t - 4), Offset(x, t), tickPaint);
    }
    for (final v in rulerTicksInches(hMin, hMax, step)) {
      final x = v * ppi + ox;
      canvas.drawLine(Offset(x, t - 9), Offset(x, t), tickPaint);
      _label(canvas, _fmtInch(v), Offset(x + 2, 2), rotate: false);
    }

    // Vertical ruler (left band).
    final vMin = (t - oy) / ppi;
    final vMax = (size.height - oy) / ppi;
    for (final v in rulerTicksInches(vMin, vMax, step / 2)) {
      final y = v * ppi + oy;
      canvas.drawLine(Offset(t - 4, y), Offset(t, y), tickPaint);
    }
    for (final v in rulerTicksInches(vMin, vMax, step)) {
      final y = v * ppi + oy;
      canvas.drawLine(Offset(t - 9, y), Offset(t, y), tickPaint);
      _label(canvas, _fmtInch(v), Offset(2, y - 2), rotate: true);
    }

    // Corner + band borders (drawn last, above ticks that reach the edge).
    canvas.drawRect(Rect.fromLTWH(0, 0, t, t), bandPaint);
    canvas.drawLine(Offset(0, t), Offset(size.width, t), borderPaint);
    canvas.drawLine(Offset(t, 0), Offset(t, size.height), borderPaint);
  }

  void _label(Canvas canvas, String text, Offset at, {required bool rotate}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: labelColor, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    if (!rotate) {
      tp.paint(canvas, at);
      return;
    }
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(-math.pi / 2);
    // After rotating, the text reads bottom-to-top; offset so it sits just
    // below the tick's y (now along the negative-x axis).
    tp.paint(canvas, Offset(-tp.width, 0));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.selection != selection ||
      old.pxPerInch != pxPerInch ||
      old.thickness != thickness ||
      old.bandColor != bandColor ||
      old.tickColor != tickColor ||
      old.highlightColor != highlightColor;
}
