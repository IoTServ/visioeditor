import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vsdx/vsdx.dart';

import '../render/shape_bounds.dart';
import '../render/vsdx_painter.dart';
import 'editor_controller.dart';

/// Interactive editing canvas for the controller's current page.
///
/// Manages its own view transform (`content px -> viewport px = content *
/// scale + offset`) so pan / zoom and shape dragging never fight a shared
/// gesture recognizer. Content-px space is top-left / Y-down and equals
/// `page inches * pxPerInch`; the painter applies the Visio Y-flip internally.
class PageCanvas extends StatefulWidget {
  const PageCanvas({
    required this.controller,
    super.key,
    this.onRequestTextEdit,
    this.pxPerInch = 96.0,
    this.minScale = 0.05,
    this.maxScale = 32.0,
    this.canvasColor = const Color(0xFFECEFF3),
    this.pageColor = Colors.white,
  });

  final EditorController controller;

  /// Invoked when the user double-clicks a shape and wants to edit its text.
  final void Function(int shapeId)? onRequestTextEdit;

  final double pxPerInch;
  final double minScale;
  final double maxScale;
  final Color canvasColor;
  final Color pageColor;

  @override
  State<PageCanvas> createState() => _PageCanvasState();
}

enum _DragMode {
  none,
  moveShapes,
  panCanvas,
  createShape,
  resize,
  rotate,
  marquee,
}

/// The eight resize handles around a selection box.
enum _Handle { tl, tr, br, bl, t, r, b, l }

class _PageCanvasState extends State<PageCanvas> {
  double _scale = 1;
  Offset _offset = Offset.zero;
  Size? _viewport;
  bool _fitPending = true;
  int? _fittedPageId;

  _DragMode _mode = _DragMode.none;
  Offset _lastPointer = Offset.zero;
  Offset _doubleTapPos = Offset.zero;
  _Handle? _activeHandle;
  int? _resizeShapeId;

  // Creation preview, in content-px space.
  Offset? _previewStart;
  Offset? _previewEnd;

  // Marquee selection rectangle, in content-px space.
  Offset? _marqueeStart;
  Offset? _marqueeEnd;

  EditorController get _c => widget.controller;

  VsdxPage? get _page => _c.currentPage;

  Size get _contentSize {
    final p = _page;
    final w = (p == null || p.widthInches <= 0 ? 8.5 : p.widthInches);
    final h = (p == null || p.heightInches <= 0 ? 11.0 : p.heightInches);
    return Size(w * widget.pxPerInch, h * widget.pxPerInch);
  }

  // --- Coordinate mapping ----------------------------------------------------

  Offset _viewportToContent(Offset v) => (v - _offset) / _scale;

  Offset _contentToPageInches(Offset c) {
    final p = _page!;
    return Offset(c.dx / widget.pxPerInch, p.heightInches - c.dy / widget.pxPerInch);
  }

  Rect _boundsInchesToContent(Rect b) {
    final p = _page!;
    final ppi = widget.pxPerInch;
    return Rect.fromLTRB(
      b.left * ppi,
      (p.heightInches - b.top) * ppi,
      b.right * ppi,
      (p.heightInches - b.bottom) * ppi,
    );
  }

  // --- View transform --------------------------------------------------------

  void _applyFit(Size viewport) {
    final content = _contentSize;
    if (content.width <= 0 || content.height <= 0) return;
    const margin = 40.0;
    final sx = (viewport.width - margin * 2) / content.width;
    final sy = (viewport.height - margin * 2) / content.height;
    final scale = (sx < sy ? sx : sy).clamp(widget.minScale, widget.maxScale).toDouble();
    setState(() {
      _scale = scale;
      _offset = Offset(
        (viewport.width - content.width * scale) / 2,
        (viewport.height - content.height * scale) / 2,
      );
    });
  }

  void _zoomBy(double factor, [Offset? focus]) {
    final viewport = _viewport;
    if (viewport == null) return;
    final f = focus ?? Offset(viewport.width / 2, viewport.height / 2);
    final target = (_scale * factor).clamp(widget.minScale, widget.maxScale).toDouble();
    if (target == _scale) return;
    final contentPt = (f - _offset) / _scale;
    setState(() {
      _scale = target;
      _offset = f - contentPt * target;
    });
  }

  void fitToScreen() {
    final v = _viewport;
    if (v != null) _applyFit(v);
  }

  // --- Hit testing -----------------------------------------------------------

  int? _hitTest(Offset viewportPos) {
    final page = _page;
    if (page == null) return null;
    final pt = _contentToPageInches(_viewportToContent(viewportPos));
    final bounds = buildShapeBounds(page);
    // Prefer the top-most shape in draw order (parents before children,
    // siblings in list order), so we walk the flattened order and keep the
    // last hit.
    int? best;
    for (final id in _drawOrder(page)) {
      final r = bounds[id];
      if (r != null && r.contains(pt)) best = id;
    }
    return best;
  }

  static List<int> _drawOrder(VsdxPage page) {
    final out = <int>[];
    void walk(VsdxShape s) {
      out.add(s.id);
      for (final c in s.children) {
        walk(c);
      }
    }

    for (final s in page.shapes) {
      walk(s);
    }
    return out;
  }

  // --- Gestures --------------------------------------------------------------

  Offset _pageInchesAt(Offset viewportPos) =>
      _contentToPageInches(_viewportToContent(viewportPos));

  VsdxShape? _singleSelectedShape() {
    final page = _page;
    if (page == null || _c.selection.length != 1) return null;
    return page.findShapeById(_c.selection.first);
  }

  /// The single selected shape if it is a non-rotated 2-D shape that supports
  /// box resize.
  VsdxShape? _resizableSelection() {
    final s = _singleSelectedShape();
    return (s == null || s.is1D || s.angleRad != 0) ? null : s;
  }

  /// The single selected shape if it is a 2-D shape that supports rotation.
  VsdxShape? _rotatableSelection() {
    final s = _singleSelectedShape();
    return (s == null || s.is1D) ? null : s;
  }

  Offset _pageToContent(double x, double y) => Offset(
        x * widget.pxPerInch,
        (_page!.heightInches - y) * widget.pxPerInch,
      );

  /// Content-px positions of (rotate-line anchor at the shape's oriented top
  /// centre, rotate-handle knob just beyond it).
  (Offset anchor, Offset knob) _rotateAnchors(VsdxShape s) {
    final sin = math.sin(s.angleRad);
    final cos = math.cos(s.angleRad);
    // Local up vector (0, h/2) rotated into page space (CCW).
    final topX = s.pinX - sin * (s.height / 2);
    final topY = s.pinY + cos * (s.height / 2);
    final offIn = 22 / (_scale * widget.pxPerInch);
    final knobX = topX - sin * offIn;
    final knobY = topY + cos * offIn;
    return (_pageToContent(topX, topY), _pageToContent(knobX, knobY));
  }

  /// Axis-aligned selection box of [s] in content-px space.
  Rect _exactContentBox(VsdxShape s) {
    final ppi = widget.pxPerInch;
    final ph = _page!.heightInches;
    final l = (s.pinX - s.width / 2) * ppi;
    final r = (s.pinX + s.width / 2) * ppi;
    final top = (ph - (s.pinY + s.height / 2)) * ppi;
    final bottom = (ph - (s.pinY - s.height / 2)) * ppi;
    return Rect.fromLTRB(l, top, r, bottom);
  }

  Map<_Handle, Offset> _handleScreens(Rect contentBox) {
    Offset scr(Offset c) => _offset + c * _scale;
    return <_Handle, Offset>{
      _Handle.tl: scr(contentBox.topLeft),
      _Handle.tr: scr(contentBox.topRight),
      _Handle.br: scr(contentBox.bottomRight),
      _Handle.bl: scr(contentBox.bottomLeft),
      _Handle.t: scr(contentBox.topCenter),
      _Handle.b: scr(contentBox.bottomCenter),
      _Handle.l: scr(contentBox.centerLeft),
      _Handle.r: scr(contentBox.centerRight),
    };
  }

  void _onTapUp(TapUpDetails d) {
    if (_c.tool == EditorTool.connector) {
      return; // connectors need a drag between two points
    }
    if (_c.tool != EditorTool.select) {
      final p = _pageInchesAt(d.localPosition);
      _c.createShapeByDrag(p.dx, p.dy, p.dx, p.dy); // click ⇒ default size
      return;
    }
    final hit = _hitTest(d.localPosition);
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (hit != null) {
      if (shift) {
        _c.toggleSelection(hit);
      } else {
        _c.selectOnly(hit);
      }
    } else if (!shift) {
      _c.clearSelection();
    }
  }

  void _onDoubleTap() {
    final hit = _hitTest(_doubleTapPos);
    if (hit != null) widget.onRequestTextEdit?.call(hit);
  }

  void _onPanStart(DragStartDetails d) {
    _lastPointer = d.localPosition;
    if (_c.tool != EditorTool.select) {
      _mode = _DragMode.createShape;
      setState(() {
        _previewStart = _viewportToContent(d.localPosition);
        _previewEnd = _previewStart;
      });
      return;
    }
    // Rotate handle takes top priority for a single 2-D selection.
    final rotatable = _rotatableSelection();
    if (rotatable != null) {
      final (_, knob) = _rotateAnchors(rotatable);
      if ((_offset + knob * _scale - d.localPosition).distanceSquared <= 144) {
        _resizeShapeId = rotatable.id;
        _mode = _DragMode.rotate;
        _c.beginTransaction();
        return;
      }
    }

    // Resize handles take priority over move/pan when one shape is selected.
    final resizable = _resizableSelection();
    if (resizable != null) {
      final handles = _handleScreens(_exactContentBox(resizable));
      for (final entry in handles.entries) {
        if ((entry.value - d.localPosition).distanceSquared <= 144) {
          _activeHandle = entry.key;
          _resizeShapeId = resizable.id;
          _mode = _DragMode.resize;
          _c.beginTransaction();
          return;
        }
      }
    }

    final hit = _hitTest(d.localPosition);
    if (hit != null) {
      if (!_c.isSelected(hit)) _c.selectOnly(hit);
      _mode = _DragMode.moveShapes;
      _c.beginTransaction();
    } else if (HardwareKeyboard.instance.logicalKeysPressed
        .contains(LogicalKeyboardKey.space)) {
      _mode = _DragMode.panCanvas;
    } else {
      _mode = _DragMode.marquee;
      setState(() {
        _marqueeStart = _viewportToContent(d.localPosition);
        _marqueeEnd = _marqueeStart;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final pos = d.localPosition;
    switch (_mode) {
      case _DragMode.moveShapes:
        final deltaContent = (pos - _lastPointer) / _scale;
        _c.moveSelectionBy(
          deltaContent.dx / widget.pxPerInch,
          -deltaContent.dy / widget.pxPerInch,
          transient: true,
        );
      case _DragMode.panCanvas:
        setState(() => _offset += pos - _lastPointer);
      case _DragMode.createShape:
        setState(() => _previewEnd = _viewportToContent(pos));
      case _DragMode.resize:
        _applyResize(pos);
      case _DragMode.marquee:
        setState(() => _marqueeEnd = _viewportToContent(pos));
      case _DragMode.rotate:
        final id = _resizeShapeId;
        final s = id == null ? null : _c.currentPage?.findShapeById(id);
        if (s != null) {
          final p = _pageInchesAt(pos);
          final angle = math.atan2(-(p.dx - s.pinX), p.dy - s.pinY);
          _c.rotateShape(id!, angle, transient: true);
        }
      case _DragMode.none:
        break;
    }
    _lastPointer = pos;
  }

  void _applyResize(Offset pos) {
    final id = _resizeShapeId;
    final handle = _activeHandle;
    if (id == null || handle == null) return;
    final s = _c.currentPage?.findShapeById(id);
    if (s == null) return;
    final p = _pageInchesAt(pos);
    final px = _c.snap(p.dx);
    final py = _c.snap(p.dy);
    var l = s.pinX - s.width / 2;
    var r = s.pinX + s.width / 2;
    var b = s.pinY - s.height / 2;
    var t = s.pinY + s.height / 2;
    switch (handle) {
      case _Handle.tl:
        l = px;
        t = py;
      case _Handle.tr:
        r = px;
        t = py;
      case _Handle.br:
        r = px;
        b = py;
      case _Handle.bl:
        l = px;
        b = py;
      case _Handle.t:
        t = py;
      case _Handle.b:
        b = py;
      case _Handle.l:
        l = px;
      case _Handle.r:
        r = px;
    }
    final nl = math.min(l, r);
    final nr = math.max(l, r);
    final nb = math.min(b, t);
    final nt = math.max(b, t);
    _c.resizeShape(
      id,
      pinX: (nl + nr) / 2,
      pinY: (nb + nt) / 2,
      width: math.max(nr - nl, 0.05),
      height: math.max(nt - nb, 0.05),
      transient: true,
    );
  }

  void _onPanEnd(DragEndDetails d) {
    switch (_mode) {
      case _DragMode.moveShapes:
      case _DragMode.resize:
      case _DragMode.rotate:
        _c.commitTransaction();
        _activeHandle = null;
        _resizeShapeId = null;
      case _DragMode.createShape:
        final start = _previewStart;
        final end = _previewEnd;
        if (start != null && end != null) {
          final a = _contentToPageInches(start);
          final b = _contentToPageInches(end);
          if (_c.tool == EditorTool.connector) {
            _c.createConnector(
              a.dx,
              a.dy,
              b.dx,
              b.dy,
              beginTarget: _hitTest(_offset + start * _scale),
              endTarget: _hitTest(_offset + end * _scale),
            );
          } else {
            _c.createShapeByDrag(a.dx, a.dy, b.dx, b.dy);
          }
        }
        setState(() {
          _previewStart = null;
          _previewEnd = null;
        });
      case _DragMode.marquee:
        _commitMarquee();
        setState(() {
          _marqueeStart = null;
          _marqueeEnd = null;
        });
      case _DragMode.panCanvas:
      case _DragMode.none:
        break;
    }
    _mode = _DragMode.none;
  }

  void _commitMarquee() {
    final page = _page;
    final s = _marqueeStart;
    final e = _marqueeEnd;
    if (page == null || s == null || e == null) return;
    final a = _contentToPageInches(s);
    final b = _contentToPageInches(e);
    final l = math.min(a.dx, b.dx);
    final r = math.max(a.dx, b.dx);
    final bottom = math.min(a.dy, b.dy);
    final top = math.max(a.dy, b.dy);
    // Ignore accidental micro-drags (treat as a click that cleared already).
    if ((r - l) < 0.02 && (top - bottom) < 0.02) return;
    final bounds = buildShapeBounds(page);
    final topLevel = <int>{for (final sh in page.shapes) sh.id};
    final ids = <int>[
      for (final entry in bounds.entries)
        if (topLevel.contains(entry.key) &&
            entry.value.left <= r &&
            entry.value.right >= l &&
            entry.value.top <= top &&
            entry.value.bottom >= bottom)
          entry.key,
    ];
    _c.setSelection(ids);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      if (_c.hasSelection) {
        _c.deleteSelection();
        return KeyEventResult.handled;
      }
    } else if (key == LogicalKeyboardKey.escape) {
      if (_c.tool != EditorTool.select) {
        _c.setTool(EditorTool.select);
      } else {
        _c.clearSelection();
      }
      return KeyEventResult.handled;
    } else if (_c.hasSelection) {
      final step = _c.snapToGrid ? _c.gridInches : 0.1;
      if (key == LogicalKeyboardKey.arrowLeft) {
        _c.moveSelectionBy(-step, 0);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowRight) {
        _c.moveSelectionBy(step, 0);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowUp) {
        _c.moveSelectionBy(0, step);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowDown) {
        _c.moveSelectionBy(0, -step);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final zoomModifier = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (zoomModifier) {
      final factor = e.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1;
      _zoomBy(factor, e.localPosition);
    } else {
      setState(() => _offset -= e.scrollDelta);
    }
  }

  // --- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final page = _page;
        if (page == null) {
          return ColoredBox(color: widget.canvasColor);
        }
        final content = _contentSize;
        final doc = _c.document!;
        final bounds = buildShapeBounds(page);
        return LayoutBuilder(
          builder: (context, constraints) {
            final viewport = Size(
              constraints.maxWidth.isFinite ? constraints.maxWidth : 800,
              constraints.maxHeight.isFinite ? constraints.maxHeight : 600,
            );
            final resized = _viewport == null ||
                _viewport!.width != viewport.width ||
                _viewport!.height != viewport.height;
            final pageChanged = _fittedPageId != page.id;
            if (_fitPending || resized || pageChanged) {
              _viewport = viewport;
              _fitPending = false;
              _fittedPageId = page.id;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _applyFit(viewport);
              });
            }
            final selectionRects = <Rect>[
              for (final id in _c.selection)
                if (bounds[id] != null) _boundsInchesToContent(bounds[id]!),
            ];
            final resizable = _resizableSelection();
            final Rect? handleBox =
                resizable != null ? _exactContentBox(resizable) : null;
            final outlines =
                handleBox != null ? <Rect>[handleBox] : selectionRects;
            final rotatable = _rotatableSelection();
            Offset? rotateAnchor;
            Offset? rotateKnob;
            if (rotatable != null) {
              final anchors = _rotateAnchors(rotatable);
              rotateAnchor = anchors.$1;
              rotateKnob = anchors.$2;
            }
            final previewTool = _mode == _DragMode.createShape ? _c.tool : null;
            final marquee = (_marqueeStart != null && _marqueeEnd != null)
                ? Rect.fromPoints(_marqueeStart!, _marqueeEnd!)
                : null;
            return Focus(
              autofocus: true,
              onKeyEvent: _onKey,
              child: Listener(
              onPointerSignal: _onPointerSignal,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _onTapUp,
                onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
                onDoubleTap: _onDoubleTap,
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: ClipRect(
                  child: Stack(
                    children: [
                      Positioned.fill(child: ColoredBox(color: widget.canvasColor)),
                      Transform(
                        transform: Matrix4.identity()
                          ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
                          ..scaleByDouble(_scale, _scale, 1, 1),
                        child: SizedBox(
                          width: content.width,
                          height: content.height,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: widget.pageColor,
                              boxShadow: const [
                                BoxShadow(color: Color(0x22000000), blurRadius: 12),
                              ],
                            ),
                            child: Stack(
                              children: [
                                if (_c.showGrid)
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _GridPainter(
                                        stepPx: _c.gridInches * widget.pxPerInch,
                                        color: const Color(0x11000000),
                                        strokeWidth: 1 / _scale,
                                      ),
                                    ),
                                  ),
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: VsdxPainter(
                                      page: page,
                                      theme: doc.theme,
                                      images: doc.images,
                                      pxPerInch: widget.pxPerInch,
                                      backgroundColor: _c.showGrid
                                          ? const Color(0x00000000)
                                          : widget.pageColor,
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _SelectionPainter(
                                      rects: outlines,
                                      handleBox: handleBox,
                                      rotateAnchor: rotateAnchor,
                                      rotateKnob: rotateKnob,
                                      color: Theme.of(context).colorScheme.primary,
                                      strokeWidth: 1.5 / _scale,
                                      handleSize: 7 / _scale,
                                      previewStart: _previewStart,
                                      previewEnd: _previewEnd,
                                      previewTool: previewTool,
                                      marquee: marquee,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: _ZoomControls(
                          onZoomIn: () => _zoomBy(1.25),
                          onZoomOut: () => _zoomBy(0.8),
                          onFit: fitToScreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            );
          },
        );
      },
    );
  }
}

/// Paints selection outlines / handles and the in-progress creation preview.
class _SelectionPainter extends CustomPainter {
  _SelectionPainter({
    required this.rects,
    required this.color,
    required this.strokeWidth,
    required this.handleSize,
    this.handleBox,
    this.rotateAnchor,
    this.rotateKnob,
    this.previewStart,
    this.previewEnd,
    this.previewTool,
    this.marquee,
  });

  final List<Rect> rects;
  final Rect? handleBox;
  final Offset? rotateAnchor;
  final Offset? rotateKnob;
  final Color color;
  final double strokeWidth;
  final double handleSize;
  final Offset? previewStart;
  final Offset? previewEnd;
  final EditorTool? previewTool;
  final Rect? marquee;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;
    for (final r in rects) {
      canvas.drawRect(_normalise(r), outline);
    }
    final box = handleBox;
    if (box != null) {
      final rect = _normalise(box);
      canvas.drawRect(rect, outline);
      final handleFill = Paint()..color = Colors.white;
      for (final c in <Offset>[
        rect.topLeft,
        rect.topCenter,
        rect.topRight,
        rect.centerLeft,
        rect.centerRight,
        rect.bottomLeft,
        rect.bottomCenter,
        rect.bottomRight,
      ]) {
        final h = Rect.fromCenter(center: c, width: handleSize, height: handleSize);
        canvas
          ..drawRect(h, handleFill)
          ..drawRect(h, outline);
      }
    }
    final anchor = rotateAnchor;
    final knob = rotateKnob;
    if (anchor != null && knob != null) {
      canvas
        ..drawLine(anchor, knob, outline)
        ..drawCircle(knob, handleSize * 0.7, Paint()..color = Colors.white)
        ..drawCircle(knob, handleSize * 0.7, outline);
    }
    final m = marquee;
    if (m != null) {
      final rect = _normalise(m);
      canvas
        ..drawRect(rect, Paint()..color = color.withValues(alpha: 0.12))
        ..drawRect(rect, outline);
    }
    _paintPreview(canvas, outline);
  }

  static Rect _normalise(Rect r) => Rect.fromLTRB(
        math.min(r.left, r.right),
        math.min(r.top, r.bottom),
        math.max(r.left, r.right),
        math.max(r.top, r.bottom),
      );

  void _paintPreview(Canvas canvas, Paint outline) {
    final a = previewStart;
    final b = previewEnd;
    final tool = previewTool;
    if (a == null || b == null || tool == null) return;
    switch (tool) {
      case EditorTool.line:
      case EditorTool.connector:
        canvas.drawLine(a, b, outline);
      case EditorTool.ellipse:
        canvas.drawOval(Rect.fromPoints(a, b), outline);
      case EditorTool.rectangle:
      case EditorTool.select:
        canvas.drawRect(Rect.fromPoints(a, b), outline);
    }
  }

  @override
  bool shouldRepaint(covariant _SelectionPainter old) =>
      old.rects != rects ||
      old.handleBox != handleBox ||
      old.rotateAnchor != rotateAnchor ||
      old.rotateKnob != rotateKnob ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.handleSize != handleSize ||
      old.previewStart != previewStart ||
      old.previewEnd != previewEnd ||
      old.previewTool != previewTool ||
      old.marquee != marquee;
}

/// Light grid drawn behind the page content (content-px space).
class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.stepPx,
    required this.color,
    required this.strokeWidth,
  });

  final double stepPx;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (stepPx <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth;
    for (var x = 0.0; x <= size.width; x += stepPx) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += stepPx) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.stepPx != stepPx ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

/// Floating zoom / fit controls overlaid on the canvas.
class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove),
            tooltip: 'Zoom out',
          ),
          IconButton(
            onPressed: onFit,
            icon: const Icon(Icons.fit_screen),
            tooltip: 'Fit to screen',
          ),
          IconButton(
            onPressed: onZoomIn,
            icon: const Icon(Icons.add),
            tooltip: 'Zoom in',
          ),
        ],
      ),
    );
  }
}
