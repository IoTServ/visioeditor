import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../render/shape_bounds.dart';
import 'canvas_camera.dart';
import 'editor_controller.dart';
import 'snap_guides.dart';

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

/// drawio-style rulers + permanent page guides.
///
/// - Drag from the **top** ruler → vertical guide; from the **left** → horizontal.
/// - Drag a guide marker back onto its ruler band to delete it.
/// - Guide lines paint across the page with [IgnorePointer] so the canvas keeps
///   receiving shape gestures.
class RulerOverlay extends StatefulWidget {
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

  @override
  State<RulerOverlay> createState() => _RulerOverlayState();
}

class _RulerOverlayState extends State<RulerOverlay> {
  _GuideDrag? _drag;

  EditorController get _c => widget.controller;
  CanvasCamera get _cam => widget.camera;
  double get _t => widget.thickness;
  double get _ppi => widget.pxPerInch;

  Rect? _selectionContentRect() {
    final page = _c.currentPage;
    if (page == null || _c.selection.isEmpty) return null;
    final bounds = buildShapeBounds(page);
    final ph = page.heightInches;
    double? xMin, xMax, yMin, yMax;
    for (final id in _c.selection) {
      final b = bounds[id];
      if (b == null) continue;
      final l = b.left * _ppi;
      final r = b.right * _ppi;
      final y0 = (ph - b.bottom) * _ppi;
      final y1 = (ph - b.top) * _ppi;
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

  double _pageXFromLocal(double localX) {
    final scale = _cam.scale;
    if (scale <= 0) return 0;
    return (localX - _cam.offset.dx) / (_ppi * scale);
  }

  double _pageYFromLocal(double localY) {
    final page = _c.currentPage;
    final scale = _cam.scale;
    if (page == null || scale <= 0) return 0;
    final contentY = (localY - _cam.offset.dy) / (_ppi * scale);
    return page.heightInches - contentY;
  }

  int? _hitVerticalGuide(double overlayX) {
    final guides = _c.pageGuides;
    final scale = _cam.scale;
    if (scale <= 0) return null;
    const hitPx = 6.0;
    for (var i = 0; i < guides.length; i++) {
      final g = guides[i];
      if (!g.vertical) continue;
      final sx = g.pos * _ppi * scale + _cam.offset.dx;
      if ((sx - overlayX).abs() <= hitPx) return i;
    }
    return null;
  }

  int? _hitHorizontalGuide(double overlayY) {
    final page = _c.currentPage;
    final guides = _c.pageGuides;
    final scale = _cam.scale;
    if (page == null || scale <= 0) return null;
    const hitPx = 6.0;
    for (var i = 0; i < guides.length; i++) {
      final g = guides[i];
      if (g.vertical) continue;
      final contentY = (page.heightInches - g.pos) * _ppi;
      final sy = contentY * scale + _cam.offset.dy;
      if ((sy - overlayY).abs() <= hitPx) return i;
    }
    return null;
  }

  void _commitDrag() {
    final drag = _drag;
    if (drag == null) return;
    // Clear synchronously so a paired onPanEnd + onPointerUp can't double-commit.
    _drag = null;
    final local = drag.overlayLocal;
    final delete = local != null &&
        (drag.vertical ? local.dy < _t : local.dx < _t);
    if (delete) {
      if (drag.index != null) _c.removePageGuide(drag.index!);
    } else if (drag.index != null) {
      _c.movePageGuide(
        drag.index!,
        drag.pos,
        snapToGrid: !HardwareKeyboard.instance.isAltPressed,
      );
    } else {
      _c.addPageGuide(
        vertical: drag.vertical,
        pos: drag.pos,
        snapToGrid: !HardwareKeyboard.instance.isAltPressed,
      );
    }
    if (mounted) setState(() {});
  }

  void _onTopPanStart(DragStartDetails d) {
    final overlayX = d.localPosition.dx + _t;
    final hit = _hitVerticalGuide(overlayX);
    setState(() {
      _drag = _GuideDrag(
        vertical: true,
        index: hit,
        pos: _pageXFromLocal(overlayX),
        overlayLocal: Offset(overlayX, d.localPosition.dy),
      );
    });
  }

  void _onLeftPanStart(DragStartDetails d) {
    final overlayY = d.localPosition.dy + _t;
    final hit = _hitHorizontalGuide(overlayY);
    setState(() {
      _drag = _GuideDrag(
        vertical: false,
        index: hit,
        pos: _pageYFromLocal(overlayY),
        overlayLocal: Offset(d.localPosition.dx, overlayY),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = _t;
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_c, _cam]),
      builder: (context, _) {
        final page = _c.currentPage;
        if (page == null) return const SizedBox.shrink();
        final guides = _c.pageGuides;
        final preview = _drag;
        return Stack(
          children: [
            IgnorePointer(
              child: CustomPaint(
                painter: _GuideLinesPainter(
                  camera: _cam,
                  pxPerInch: _ppi,
                  pageHeight: page.heightInches,
                  guides: guides,
                  preview: preview,
                  color: const Color(0xFF29B6F6),
                ),
              ),
            ),
            IgnorePointer(
              child: CustomPaint(
                painter: _RulerPainter(
                  camera: _cam,
                  pxPerInch: _ppi,
                  thickness: t,
                  selection: _selectionContentRect(),
                  guides: guides,
                  preview: preview,
                  pageHeight: page.heightInches,
                  bandColor: scheme.surfaceContainerHighest,
                  borderColor: scheme.outlineVariant,
                  tickColor: scheme.onSurfaceVariant,
                  labelColor: scheme.onSurfaceVariant,
                  highlightColor: scheme.primary,
                  guideColor: const Color(0xFF29B6F6),
                ),
              ),
            ),
            Positioned(
              left: t,
              top: 0,
              right: 0,
              height: t,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: _onTopPanStart,
                onPanUpdate: (d) {
                  final drag = _drag;
                  if (drag == null || !drag.vertical) return;
                  final overlayX = d.localPosition.dx + t;
                  setState(() {
                    _drag = drag.copyWith(
                      pos: _pageXFromLocal(overlayX),
                      overlayLocal: Offset(overlayX, d.localPosition.dy),
                    );
                  });
                },
                onPanEnd: (_) => _commitDrag(),
                onPanCancel: () => setState(() => _drag = null),
              ),
            ),
            Positioned(
              left: 0,
              top: t,
              bottom: 0,
              width: t,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: _onLeftPanStart,
                onPanUpdate: (d) {
                  final drag = _drag;
                  if (drag == null || drag.vertical) return;
                  final overlayY = d.localPosition.dy + t;
                  setState(() {
                    _drag = drag.copyWith(
                      pos: _pageYFromLocal(overlayY),
                      overlayLocal: Offset(d.localPosition.dx, overlayY),
                    );
                  });
                },
                onPanEnd: (_) => _commitDrag(),
                onPanCancel: () => setState(() => _drag = null),
              ),
            ),
            // Track the pointer across the page while a guide drag is active
            // so the line follows past the thin ruler band (drawio).
            if (preview != null)
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerMove: (e) {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null || _drag == null) return;
                    final local = box.globalToLocal(e.position);
                    setState(() {
                      final drag = _drag!;
                      _drag = drag.vertical
                          ? drag.copyWith(
                              pos: _pageXFromLocal(local.dx),
                              overlayLocal: local,
                            )
                          : drag.copyWith(
                              pos: _pageYFromLocal(local.dy),
                              overlayLocal: local,
                            );
                    });
                  },
                  onPointerUp: (_) => _commitDrag(),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GuideDrag {
  const _GuideDrag({
    required this.vertical,
    required this.pos,
    this.index,
    this.overlayLocal,
  });

  final bool vertical;
  final double pos;
  final int? index;
  final Offset? overlayLocal;

  _GuideDrag copyWith({double? pos, Offset? overlayLocal}) => _GuideDrag(
        vertical: vertical,
        pos: pos ?? this.pos,
        index: index,
        overlayLocal: overlayLocal ?? this.overlayLocal,
      );
}

class _GuideLinesPainter extends CustomPainter {
  _GuideLinesPainter({
    required this.camera,
    required this.pxPerInch,
    required this.pageHeight,
    required this.guides,
    required this.preview,
    required this.color,
  }) : super(repaint: camera);

  final CanvasCamera camera;
  final double pxPerInch;
  final double pageHeight;
  final List<PageGuide> guides;
  final _GuideDrag? preview;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = camera.scale;
    if (scale <= 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.85);

    void drawVertical(double pageX) {
      final x = pageX * pxPerInch * scale + camera.offset.dx;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    void drawHorizontal(double pageY) {
      final contentY = (pageHeight - pageY) * pxPerInch;
      final y = contentY * scale + camera.offset.dy;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    final skip = preview?.index;
    for (var i = 0; i < guides.length; i++) {
      if (skip != null && i == skip) continue;
      final g = guides[i];
      if (g.vertical) {
        drawVertical(g.pos);
      } else {
        drawHorizontal(g.pos);
      }
    }
    final prev = preview;
    if (prev != null) {
      if (prev.vertical) {
        drawVertical(prev.pos);
      } else {
        drawHorizontal(prev.pos);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GuideLinesPainter old) =>
      old.pageHeight != pageHeight ||
      old.pxPerInch != pxPerInch ||
      old.color != color ||
      old.preview?.pos != preview?.pos ||
      old.preview?.index != preview?.index ||
      old.preview?.vertical != preview?.vertical ||
      !_listEq(old.guides, guides);

  static bool _listEq(List<PageGuide> a, List<PageGuide> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.camera,
    required this.pxPerInch,
    required this.thickness,
    required this.selection,
    required this.guides,
    required this.preview,
    required this.pageHeight,
    required this.bandColor,
    required this.borderColor,
    required this.tickColor,
    required this.labelColor,
    required this.highlightColor,
    required this.guideColor,
  }) : super(repaint: camera);

  final CanvasCamera camera;
  final double pxPerInch;
  final double thickness;
  final Rect? selection;
  final List<PageGuide> guides;
  final _GuideDrag? preview;
  final double pageHeight;
  final Color bandColor;
  final Color borderColor;
  final Color tickColor;
  final Color labelColor;
  final Color highlightColor;
  final Color guideColor;

  @override
  void paint(Canvas canvas, Size size) {
    final t = thickness;
    final scale = camera.scale;
    final ppi = pxPerInch * scale;
    if (ppi <= 0) return;
    final ox = camera.offset.dx;
    final oy = camera.offset.dy;

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
    final markerPaint = Paint()..color = guideColor;

    final topBand = Rect.fromLTWH(0, 0, size.width, t);
    final leftBand = Rect.fromLTWH(0, 0, t, size.height);
    canvas.drawRect(topBand, bandPaint);
    canvas.drawRect(leftBand, bandPaint);

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

    // Guide markers on the ruler bands (triangles pointing into the page).
    void vMarker(double pageX) {
      final x = pageX * ppi + ox;
      final path = Path()
        ..moveTo(x, t)
        ..lineTo(x - 4, t - 7)
        ..lineTo(x + 4, t - 7)
        ..close();
      canvas.drawPath(path, markerPaint);
    }

    void hMarker(double pageY) {
      final contentY = (pageHeight - pageY) * pxPerInch;
      final y = contentY * scale + oy;
      final path = Path()
        ..moveTo(t, y)
        ..lineTo(t - 7, y - 4)
        ..lineTo(t - 7, y + 4)
        ..close();
      canvas.drawPath(path, markerPaint);
    }

    final skip = preview?.index;
    for (var i = 0; i < guides.length; i++) {
      if (skip != null && i == skip) continue;
      final g = guides[i];
      if (g.vertical) {
        vMarker(g.pos);
      } else {
        hMarker(g.pos);
      }
    }
    final prev = preview;
    if (prev != null) {
      if (prev.vertical) {
        vMarker(prev.pos);
      } else {
        hMarker(prev.pos);
      }
    }

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
    tp.paint(canvas, Offset(-tp.width, 0));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.selection != selection ||
      old.pxPerInch != pxPerInch ||
      old.thickness != thickness ||
      old.pageHeight != pageHeight ||
      old.bandColor != bandColor ||
      old.tickColor != tickColor ||
      old.highlightColor != highlightColor ||
      old.guideColor != guideColor ||
      old.preview?.pos != preview?.pos ||
      old.preview?.index != preview?.index ||
      !_GuideLinesPainter._listEq(old.guides, guides);
}
