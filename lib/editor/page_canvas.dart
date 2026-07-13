import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vsdx/vsdx.dart';

import '../render/image_cache.dart';
import '../render/shape_bounds.dart';
import '../render/vsdx_painter.dart';
import 'canvas_camera.dart';
import 'edit_data_dialog.dart';
import 'edit_link_dialog.dart';
import 'editor_controller.dart';
import 'snap_guides.dart';

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
    this.camera,
    this.pxPerInch = 96.0,
    this.minScale = 0.05,
    this.maxScale = 32.0,
    this.canvasColor = const Color(0xFFECEFF3),
    this.pageColor = Colors.white,
  });

  final EditorController controller;

  /// Optional camera the canvas publishes its view transform to, so a peer
  /// widget (the Outline minimap) can show the current viewport and navigate.
  final CanvasCamera? camera;

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
  moveWaypoint,
  connect,
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

  // Reveal ("scroll into view") — tracks the controller's revealSerial.
  int _lastRevealSerial = 0;
  Offset _doubleTapPos = Offset.zero;
  _Handle? _activeHandle;
  int? _resizeShapeId;
  // Shape state captured when a resize begins, so aspect-lock / resize-from-
  // centre stay stable across the whole drag.
  VsdxShape? _resizeStartShape;

  // In-place text editing: the shape whose label is being edited (if any),
  // plus the field's controller / focus node.
  int? _editingShapeId;
  // Id of a text box just created by the Text tool (drawio): if it is
  // committed / cancelled while still empty it is removed again.
  int? _newTextBoxId;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocus = FocusNode(debugLabel: 'inlineTextEditor');

  // Smart alignment guides (drawio-style) shown while moving a selection.
  ({double l, double b, double r, double t})? _moveStartBounds; // inches, y-up
  Offset _moveAccumInches = Offset.zero; // raw accumulated delta from start
  Offset _moveAppliedInches = Offset.zero; // snapped delta applied so far
  List<SnapGuide> _guides = const <SnapGuide>[];

  // Connector waypoint drag (drawio bend points).
  int? _waypointConnId;
  int? _waypointIndex;

  // Hover-to-connect (drawio HoverIcons): the top-level shape currently under
  // the cursor in idle select mode (shows directional connect arrows), the
  // source shape while dragging out a new connector from one of those arrows,
  // and the shape currently under the cursor while wiring (highlighted).
  int? _hoverShapeId;
  int? _connectSourceId;
  int? _connectTargetId;

  /// Screen-px gap from a shape's box to its hover-connect arrows.
  static const double _connectArrowGapPx = 22;
  static const double _connectArrowHitPx = 15;

  // Creation preview, in content-px space.
  Offset? _previewStart;
  Offset? _previewEnd;

  // Marquee selection rectangle, in content-px space.
  Offset? _marqueeStart;
  Offset? _marqueeEnd;

  /// Async decode cache for embedded pictures, keyed by media part name. The
  /// painter repaints when a decode lands (`super(repaint: imageCache)`).
  /// Rebuilt whenever a fresh document loads (see [_imageCacheEpoch]).
  final VsdxImageCache _imageCache = VsdxImageCache();
  int _imageCacheEpoch = 0;

  @override
  void initState() {
    super.initState();
    _textFocus.addListener(_onEditorFocusChange);
    _imageCacheEpoch = widget.controller.documentEpoch;
  }

  @override
  void dispose() {
    _textFocus
      ..removeListener(_onEditorFocusChange)
      ..dispose();
    _textController.dispose();
    _imageCache.dispose();
    super.dispose();
  }

  /// Commit the in-place edit when the field loses focus (e.g. the user clicks
  /// another window or tabs away).
  void _onEditorFocusChange() {
    if (!_textFocus.hasFocus && _editingShapeId != null && mounted) {
      _commitTextEdit();
    }
  }

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

  /// Centre (and optionally zoom-to-fit) the given content-px [rect] in the
  /// viewport. Used by Find (centre only) and Zoom-to-selection (fit).
  void _revealContent(Rect rect, {required bool fit}) {
    final v = _viewport;
    if (v == null) return;
    final r = Rect.fromLTRB(
      math.min(rect.left, rect.right),
      math.min(rect.top, rect.bottom),
      math.max(rect.left, rect.right),
      math.max(rect.top, rect.bottom),
    );
    var scale = _scale;
    // Only re-fit when the target has a meaningful extent (skip for points /
    // thin 1-D shapes so we don't slam to max zoom).
    if (fit && r.shortestSide > 4) {
      const margin = 60.0;
      final sx = (v.width - margin * 2) / r.width;
      final sy = (v.height - margin * 2) / r.height;
      scale =
          (sx < sy ? sx : sy).clamp(widget.minScale, widget.maxScale).toDouble();
    }
    setState(() {
      _scale = scale;
      _offset = Offset(v.width / 2, v.height / 2) - r.center * scale;
    });
  }

  /// Respond to a controller reveal request: centre on the target shape, or
  /// fit the whole selection when no specific shape was named.
  void _handleReveal() {
    final page = _page;
    if (page == null) return;
    // Outline navigation: centre on an arbitrary page point.
    final point = _c.revealPoint;
    if (point != null) {
      final c = _pageToContent(point.x, point.y);
      _revealContent(Rect.fromCenter(center: c, width: 0, height: 0), fit: false);
      return;
    }
    final bounds = buildShapeBounds(page);
    final targetId = _c.revealShapeId;
    Rect? rect;
    if (targetId != null) {
      final b = bounds[targetId];
      if (b != null) rect = _boundsInchesToContent(b);
    } else {
      Rect? union;
      for (final id in _c.selection) {
        final b = bounds[id];
        if (b == null) continue;
        final r = _boundsInchesToContent(b);
        union = union == null ? r : union.expandToInclude(r);
      }
      rect = union;
    }
    if (rect != null) _revealContent(rect, fit: targetId == null);
  }

  /// Reset zoom to 100% (1 content-px per device px), centred in the viewport.
  void _resetZoom() {
    final v = _viewport;
    if (v == null) return;
    final content = _contentSize;
    setState(() {
      _scale = 1.0;
      _offset = Offset(
        (v.width - content.width) / 2,
        (v.height - content.height) / 2,
      );
    });
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
  /// box resize. Locked shapes never expose resize handles (drawio parity).
  VsdxShape? _resizableSelection() {
    final s = _singleSelectedShape();
    return (s == null || s.is1D || s.angleRad != 0 || s.locked) ? null : s;
  }

  /// The single selected shape if it is a 2-D shape that supports rotation.
  /// Locked shapes never expose the rotation handle (drawio parity).
  VsdxShape? _rotatableSelection() {
    final s = _singleSelectedShape();
    return (s == null || s.is1D || s.locked) ? null : s;
  }

  Offset _pageToContent(double x, double y) => Offset(
        x * widget.pxPerInch,
        (_page!.heightInches - y) * widget.pxPerInch,
      );

  Offset _pageToScreen(double x, double y) =>
      _offset + _pageToContent(x, y) * _scale;

  /// The single selected connector (1-D shape), or null.
  VsdxShape? _selectedConnector() {
    final s = _singleSelectedShape();
    return (s != null && s.is1D) ? s : null;
  }

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

  // --- Hover-to-connect (drawio HoverIcons) ----------------------------------

  /// The top-most *top-level* shape whose bounds contain [viewportPos], or null.
  int? _topLevelAt(Offset viewportPos) {
    final page = _page;
    if (page == null) return null;
    final pt = _contentToPageInches(_viewportToContent(viewportPos));
    final bounds = buildShapeBounds(page);
    int? best;
    for (final s in page.shapes) {
      final r = bounds[s.id];
      if (r != null && r.contains(pt)) best = s.id;
    }
    return best;
  }

  /// Whether hover-connect affordances should be offered right now.
  bool get _connectAffordanceActive =>
      _mode == _DragMode.none &&
      _c.tool == EditorTool.select &&
      _editingShapeId == null;

  /// Content-px anchor + direction (0=N,1=E,2=S,3=W) of each connect arrow
  /// around [box] (content-px, Y-down), sitting [gap] content-px outside it.
  static List<(Offset, int)> _connectArrows(Rect box, double gap) {
    final b = _normaliseRect(box);
    return <(Offset, int)>[
      (Offset(b.center.dx, b.top - gap), 0),
      (Offset(b.right + gap, b.center.dy), 1),
      (Offset(b.center.dx, b.bottom + gap), 2),
      (Offset(b.left - gap, b.center.dy), 3),
    ];
  }

  /// Midpoint of the [box] edge a connect arrow with [dir] points out of
  /// (content-px) — the visual start of the connector preview.
  static Offset _connectEdge(Rect box, int dir) {
    final b = _normaliseRect(box);
    return switch (dir) {
      0 => b.topCenter,
      1 => b.centerRight,
      2 => b.bottomCenter,
      _ => b.centerLeft,
    };
  }

  static Rect _normaliseRect(Rect r) => Rect.fromLTRB(
        math.min(r.left, r.right),
        math.min(r.top, r.bottom),
        math.max(r.left, r.right),
        math.max(r.top, r.bottom),
      );

  /// If [viewportPos] is on one of [s]'s connect arrows, return its direction.
  int? _connectArrowHitDir(VsdxShape s, Offset viewportPos) {
    final gap = _connectArrowGapPx / _scale;
    final anchors = _connectArrows(_exactContentBox(s), gap);
    final hit = _connectArrowHitPx * _connectArrowHitPx;
    for (final (c, dir) in anchors) {
      if ((_offset + c * _scale - viewportPos).distanceSquared <= hit) {
        return dir;
      }
    }
    return null;
  }

  void _onHover(PointerHoverEvent e) {
    if (!_connectAffordanceActive) {
      if (_hoverShapeId != null) setState(() => _hoverShapeId = null);
      return;
    }
    final pos = e.localPosition;
    var next = _topLevelAt(pos);
    // Keep the current hover while the pointer is over one of its arrows (which
    // sit outside the shape, so a plain hit-test there would clear it).
    if (next == null && _hoverShapeId != null) {
      final s = _page?.findShapeById(_hoverShapeId!);
      if (s != null && !s.is1D && !s.locked && _connectArrowHitDir(s, pos) != null) {
        next = _hoverShapeId;
      }
    }
    // Don't offer arrows on 1-D shapes (connectors) or locked shapes.
    if (next != null) {
      final s = _page?.findShapeById(next);
      if (s == null || s.is1D || s.locked) next = null;
    }
    if (next != _hoverShapeId) setState(() => _hoverShapeId = next);
  }

  void _clearHover() {
    if (_hoverShapeId != null) setState(() => _hoverShapeId = null);
  }

  void _onTapUp(TapUpDetails d) {
    if (_editingShapeId != null) {
      _commitTextEdit(); // a click outside the editor applies the edit
      return;
    }
    // A click on a hover-connect arrow shouldn't clear the selection.
    if (_connectAffordanceActive && _hoverShapeId != null) {
      final s = _page?.findShapeById(_hoverShapeId!);
      if (s != null && _connectArrowHitDir(s, d.localPosition) != null) return;
    }
    if (_c.tool == EditorTool.connector) {
      return; // connectors need a drag between two points
    }
    if (_c.tool != EditorTool.select) {
      final wasText = _c.tool == EditorTool.text;
      final p = _pageInchesAt(d.localPosition);
      _c.createShapeByDrag(p.dx, p.dy, p.dx, p.dy); // click ⇒ default size
      if (wasText) _startEditingNewTextBox();
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
    // Double-clicking a connector's bend point removes it.
    final conn = _selectedConnector();
    if (conn != null && conn.waypoints.isNotEmpty) {
      final route = VsdxPage.connectorRoute(conn);
      for (var r = 1; r < route.length - 1; r++) {
        if ((_pageToScreen(route[r].x, route[r].y) - _doubleTapPos)
                .distanceSquared <=
            100) {
          _c.removeWaypoint(conn.id, r - 1);
          return;
        }
      }
    }
    final hit = _hitTest(_doubleTapPos);
    if (hit != null) _beginTextEdit(hit);
  }

  // --- Context menu (right-click) --------------------------------------------

  void _onSecondaryTapUp(TapUpDetails d) {
    if (_editingShapeId != null) _commitTextEdit();
    final hit = _hitTest(d.localPosition);
    if (hit != null && !_c.isSelected(hit)) _c.selectOnly(hit);
    _showContextMenu(d.globalPosition, hit);
  }

  Future<void> _showContextMenu(Offset globalPos, int? hit) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final items = <PopupMenuEntry<String>>[];
    if (_c.hasSelection) {
      items.add(const PopupMenuItem(value: 'cut', child: Text('Cut')));
      items.add(const PopupMenuItem(value: 'copy', child: Text('Copy')));
      items.add(
          const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')));
      if (_c.hasClipboard) {
        items.add(const PopupMenuItem(value: 'paste', child: Text('Paste')));
      }
      items.add(const PopupMenuItem(value: 'delete', child: Text('Delete')));
      items.add(PopupMenuItem(
          value: 'lock',
          child: Text(_c.selectionLocked ? 'Unlock' : 'Lock')));
      items.add(const PopupMenuDivider());
      items.add(
          const PopupMenuItem(value: 'front', child: Text('Bring to Front')));
      items.add(
          const PopupMenuItem(value: 'back', child: Text('Send to Back')));
      items.add(const PopupMenuItem(
          value: 'forward', child: Text('Bring Forward')));
      items.add(const PopupMenuItem(
          value: 'backward', child: Text('Send Backward')));
      if (_c.canGroup || _c.canUngroup) {
        items.add(const PopupMenuDivider());
        if (_c.canGroup) {
          items.add(const PopupMenuItem(value: 'group', child: Text('Group')));
        }
        if (_c.canUngroup) {
          items.add(
              const PopupMenuItem(value: 'ungroup', child: Text('Ungroup')));
        }
      }
      items.add(const PopupMenuDivider());
      items.add(
          const PopupMenuItem(value: 'copyStyle', child: Text('Copy Style')));
      if (_c.hasStyleClipboard) {
        items.add(const PopupMenuItem(
            value: 'pasteStyle', child: Text('Paste Style')));
      }
      items.add(const PopupMenuDivider());
      items
          .add(const PopupMenuItem(value: 'edit', child: Text('Edit Text…')));
      if (_c.singleSelectedId != null) {
        items.add(const PopupMenuItem(
            value: 'editData', child: Text('Edit Data…')));
        items.add(const PopupMenuItem(
            value: 'editLink', child: Text('Edit Link…')));
      }
    } else {
      if (_c.hasClipboard) {
        items.add(const PopupMenuItem(value: 'paste', child: Text('Paste')));
      }
      items.add(
          const PopupMenuItem(value: 'selectAll', child: Text('Select All')));
      items.add(
          const PopupMenuItem(value: 'fit', child: Text('Fit to Window')));
    }
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPos & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: items,
    );
    if (value == null || !mounted) return;
    switch (value) {
      case 'cut':
        _c.cut();
      case 'copy':
        _c.copySelection();
      case 'duplicate':
        _c.duplicateSelection();
      case 'paste':
        _c.paste();
      case 'delete':
        _c.deleteSelection();
      case 'lock':
        _c.toggleLock();
      case 'front':
        _c.bringSelectionToFront();
      case 'back':
        _c.sendSelectionToBack();
      case 'forward':
        _c.bringSelectionForward();
      case 'backward':
        _c.sendSelectionBackward();
      case 'group':
        _c.groupSelection();
      case 'ungroup':
        _c.ungroupSelection();
      case 'copyStyle':
        _c.copyStyle();
      case 'pasteStyle':
        _c.pasteStyle();
      case 'edit':
        final id = hit ?? (_c.selection.isEmpty ? null : _c.selection.first);
        if (id != null) _beginTextEdit(id);
      case 'editData':
        final id = _c.singleSelectedId;
        if (id != null) await showEditDataDialog(context, _c, id);
      case 'editLink':
        final id = _c.singleSelectedId;
        if (id != null) await showEditLinkDialog(context, _c, id);
      case 'selectAll':
        _c.selectAll();
      case 'fit':
        fitToScreen();
    }
  }

  // --- In-place text editing -------------------------------------------------

  /// Enter inline edit mode for shape [id]: select it, seed the field with its
  /// current label (all selected) and focus the overlaid editor.
  void _beginTextEdit(int id) {
    final s = _page?.findShapeById(id);
    if (s == null || s.locked) return; // locked shapes can't be text-edited
    _newTextBoxId = null; // editing an existing shape, not a fresh text box
    _c.selectOnly(id);
    final initial =
        s.richText.runs.isNotEmpty ? s.richText.plainText : (s.text ?? '');
    _textController.value = TextEditingValue(
      text: initial,
      selection: TextSelection(baseOffset: 0, extentOffset: initial.length),
    );
    setState(() => _editingShapeId = id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editingShapeId == id) _textFocus.requestFocus();
    });
  }

  /// Begin editing the shape the Text tool just created, remembering it so an
  /// empty commit / cancel removes it again (drawio behaviour).
  void _startEditingNewTextBox() {
    if (_c.selection.isEmpty) return;
    final id = _c.selection.first;
    _beginTextEdit(id);
    _newTextBoxId = id;
  }

  /// Apply the edited text to the model and leave edit mode.
  void _commitTextEdit() {
    final id = _editingShapeId;
    if (id == null) return;
    final text = _textController.text;
    final wasNewBox = id == _newTextBoxId;
    _newTextBoxId = null;
    setState(() => _editingShapeId = null);
    if (_textFocus.hasFocus) _textFocus.unfocus();
    // An untyped Text-tool box is discarded rather than left invisible.
    if (wasNewBox && text.trim().isEmpty) {
      _c.deleteShapeById(id);
    } else {
      _c.setShapeText(id, text);
    }
  }

  /// Leave edit mode, discarding the edit. A freshly-created (uncommitted)
  /// text box is removed entirely.
  void _cancelTextEdit() {
    final id = _editingShapeId;
    if (id == null) return;
    final wasNewBox = id == _newTextBoxId;
    _newTextBoxId = null;
    setState(() => _editingShapeId = null);
    if (_textFocus.hasFocus) _textFocus.unfocus();
    if (wasNewBox) _c.deleteShapeById(id);
  }

  /// The overlaid text editor for the shape being edited, positioned over its
  /// box in screen space (`null` when not editing). Enter inserts a newline;
  /// Cmd/Ctrl+Enter or clicking away applies; Esc cancels.
  Widget? _buildInlineEditor(BuildContext context) {
    final id = _editingShapeId;
    final s = id == null ? null : _page?.findShapeById(id);
    if (s == null) return null;
    final run = s.richText.runs.isNotEmpty ? s.richText.runs.first : null;
    final cs = run?.charStyle ?? VsdxCharStyle.defaults;
    final fontPx = math.max(cs.fontSizeInches * widget.pxPerInch * _scale, 8.0);
    final align = run?.paraStyle.horizontalAlign ?? VsdxHorzAlign.center;
    final scheme = Theme.of(context).colorScheme;

    final double left, top, width, height;
    if (s.is1D) {
      // Edge label: a compact editor centred on the connector's route midpoint.
      final mid = VsdxPage.connectorMidpoint(s);
      final screen = _pageToScreen(mid.x, mid.y);
      width = 140.0;
      height = math.max(fontPx + 14, 30.0);
      left = screen.dx - width / 2;
      top = screen.dy - height / 2;
    } else {
      final box = _exactContentBox(s); // content-px, axis-aligned
      left = _offset.dx + box.left * _scale;
      top = _offset.dy + box.top * _scale;
      width = math.max(box.width * _scale, 44.0);
      height = math.max(box.height * _scale, 26.0);
    }
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): _cancelTextEdit,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true):
              _commitTextEdit,
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _commitTextEdit,
        },
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border.all(color: scheme.primary, width: 1.5),
              borderRadius: BorderRadius.circular(3),
              boxShadow: const [
                BoxShadow(color: Color(0x33000000), blurRadius: 6),
              ],
            ),
            child: TextField(
              controller: _textController,
              focusNode: _textFocus,
              maxLines: null,
              expands: true,
              textAlign: _textAlign(align),
              textAlignVertical: TextAlignVertical.center,
              cursorColor: scheme.primary,
              style: TextStyle(
                fontSize: fontPx,
                height: 1.15,
                color: scheme.onSurface,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static TextAlign _textAlign(VsdxHorzAlign a) => switch (a) {
        VsdxHorzAlign.left => TextAlign.left,
        VsdxHorzAlign.center => TextAlign.center,
        VsdxHorzAlign.right => TextAlign.right,
        VsdxHorzAlign.justify => TextAlign.justify,
      };

  void _onPanStart(DragStartDetails d) {
    if (_editingShapeId != null) {
      _commitTextEdit(); // dragging elsewhere applies the edit first
      _mode = _DragMode.none;
      return;
    }
    _lastPointer = d.localPosition;
    if (_c.tool != EditorTool.select) {
      _mode = _DragMode.createShape;
      setState(() {
        _previewStart = _viewportToContent(d.localPosition);
        _previewEnd = _previewStart;
      });
      return;
    }
    // Hover-connect: dragging out of one of a hovered shape's arrows starts a
    // new connector glued to that shape (drawio's HoverIcons).
    final hover = _hoverShapeId;
    if (hover != null) {
      final s = _page?.findShapeById(hover);
      if (s != null && !s.is1D && !s.locked) {
        final dir = _connectArrowHitDir(s, d.localPosition);
        if (dir != null) {
          _connectSourceId = hover;
          _connectTargetId = null;
          _mode = _DragMode.connect;
          setState(() {
            _previewStart = _connectEdge(_exactContentBox(s), dir);
            _previewEnd = _viewportToContent(d.localPosition);
          });
          return;
        }
      }
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
          _resizeStartShape = resizable;
          _mode = _DragMode.resize;
          _c.beginTransaction();
          return;
        }
      }
    }

    // Connector waypoint handles (drawio bend points) take priority.
    if (_tryStartWaypointDrag(d.localPosition)) return;

    final hit = _hitTest(d.localPosition);
    if (hit != null) {
      if (!_c.isSelected(hit)) _c.selectOnly(hit);
      // Alt/Option-drag leaves the originals behind and drags a copy (drawio).
      if (HardwareKeyboard.instance.isAltPressed) _c.duplicateSelection();
      _mode = _DragMode.moveShapes;
      _c.beginTransaction();
      _moveAccumInches = Offset.zero;
      _moveAppliedInches = Offset.zero;
      _moveStartBounds = _selectionUnionInches();
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
        _applyMove((pos - _lastPointer) / _scale);
      case _DragMode.panCanvas:
        setState(() => _offset += pos - _lastPointer);
      case _DragMode.createShape:
        setState(() {
          _previewEnd = _viewportToContent(pos);
          // Highlight the shape the connector would glue to on drop.
          _connectTargetId =
              _c.tool == EditorTool.connector ? _topLevelAt(pos) : null;
        });
      case _DragMode.connect:
        final src = _connectSourceId;
        final t = _topLevelAt(pos);
        setState(() {
          _previewEnd = _viewportToContent(pos);
          _connectTargetId = (t == src) ? null : t;
        });
      case _DragMode.resize:
        _applyResize(pos);
      case _DragMode.marquee:
        setState(() => _marqueeEnd = _viewportToContent(pos));
      case _DragMode.moveWaypoint:
        final id = _waypointConnId;
        final idx = _waypointIndex;
        if (id != null && idx != null) {
          final p = _pageInchesAt(pos);
          _c.moveWaypoint(
            id,
            idx,
            Offset2D(_c.snap(p.dx), _c.snap(p.dy)),
            transient: true,
          );
        }
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
    final s0 = _resizeStartShape;
    if (id == null || handle == null || s0 == null) return;
    final p = _pageInchesAt(pos);
    final px = _c.snap(p.dx);
    final py = _c.snap(p.dy);
    final cx = s0.pinX, cy = s0.pinY;
    var l = s0.pinX - s0.width / 2;
    var r = s0.pinX + s0.width / 2;
    var b = s0.pinY - s0.height / 2;
    var t = s0.pinY + s0.height / 2;

    final movesL =
        handle == _Handle.tl || handle == _Handle.bl || handle == _Handle.l;
    final movesR =
        handle == _Handle.tr || handle == _Handle.br || handle == _Handle.r;
    final movesT =
        handle == _Handle.tl || handle == _Handle.tr || handle == _Handle.t;
    final movesB =
        handle == _Handle.bl || handle == _Handle.br || handle == _Handle.b;
    if (movesL) l = px;
    if (movesR) r = px;
    if (movesT) t = py;
    if (movesB) b = py;

    // Alt / Option resizes symmetrically about the original centre.
    final centered = HardwareKeyboard.instance.isAltPressed;
    if (centered) {
      if (movesL) r = 2 * cx - l;
      if (movesR) l = 2 * cx - r;
      if (movesT) b = 2 * cy - t;
      if (movesB) t = 2 * cy - b;
    }

    var nl = math.min(l, r), nr = math.max(l, r);
    var nb = math.min(b, t), nt = math.max(b, t);
    var w = math.max(nr - nl, 0.05);
    var h = math.max(nt - nb, 0.05);

    // Shift on a corner handle keeps the original aspect ratio.
    final corner = handle == _Handle.tl ||
        handle == _Handle.tr ||
        handle == _Handle.br ||
        handle == _Handle.bl;
    if (HardwareKeyboard.instance.isShiftPressed && corner && s0.height > 0) {
      final aspect = s0.width / s0.height;
      if (w / h > aspect) {
        h = w / aspect;
      } else {
        w = h * aspect;
      }
      if (centered) {
        nl = cx - w / 2;
        nr = cx + w / 2;
        nb = cy - h / 2;
        nt = cy + h / 2;
      } else {
        // Anchor the corner opposite the one being dragged.
        final fixedX = movesL ? s0.pinX + s0.width / 2 : s0.pinX - s0.width / 2;
        final fixedY = movesB ? s0.pinY + s0.height / 2 : s0.pinY - s0.height / 2;
        nl = movesL ? fixedX - w : fixedX;
        nr = movesL ? fixedX : fixedX + w;
        nb = movesB ? fixedY - h : fixedY;
        nt = movesB ? fixedY : fixedY + h;
      }
    }

    _c.resizeShape(
      id,
      pinX: (nl + nr) / 2,
      pinY: (nb + nt) / 2,
      width: math.max(nr - nl, 0.05),
      height: math.max(nt - nb, 0.05),
      transient: true,
    );
  }

  // --- Smart alignment guides (drawio-style) ---------------------------------

  /// Union AABB of the current selection in page inches (Y-up), or null.
  ({double l, double b, double r, double t})? _selectionUnionInches() {
    final page = _page;
    if (page == null) return null;
    double? l, b, r, t;
    for (final id in _c.selection) {
      final s = page.findShapeById(id);
      if (s == null) continue;
      final sl = s.pinX - s.width / 2, sr = s.pinX + s.width / 2;
      final sb = s.pinY - s.height / 2, st = s.pinY + s.height / 2;
      l = l == null ? sl : math.min(l, sl);
      r = r == null ? sr : math.max(r, sr);
      b = b == null ? sb : math.min(b, sb);
      t = t == null ? st : math.max(t, st);
    }
    if (l == null) return null;
    return (l: l, b: b!, r: r!, t: t!);
  }

  /// AABBs (page inches) of the top-level shapes not in the selection.
  List<SnapBox> _otherShapeBoxes() {
    final page = _page;
    if (page == null) return const <SnapBox>[];
    final sel = _c.selection;
    return <SnapBox>[
      for (final s in page.shapes)
        if (!sel.contains(s.id))
          SnapBox(
            s.pinX - s.width / 2,
            s.pinY - s.height / 2,
            s.pinX + s.width / 2,
            s.pinY + s.height / 2,
          ),
    ];
  }

  /// Apply a raw pointer delta (content px) to the moving selection, snapping to
  /// neighbour edges/centres and updating the visible guide lines.
  void _applyMove(Offset deltaContentPx) {
    final ppi = widget.pxPerInch;
    _moveAccumInches += Offset(deltaContentPx.dx / ppi, -deltaContentPx.dy / ppi);

    // Holding Shift constrains movement to the dominant axis (drawio parity).
    var eff = _moveAccumInches;
    if (HardwareKeyboard.instance.isShiftPressed) {
      eff = eff.dx.abs() >= eff.dy.abs()
          ? Offset(eff.dx, 0)
          : Offset(0, eff.dy);
    }

    var snapDx = 0.0, snapDy = 0.0;
    var guides = const <SnapGuide>[];
    final start = _moveStartBounds;
    if (start != null) {
      final moving = SnapBox(
        start.l + eff.dx,
        start.b + eff.dy,
        start.r + eff.dx,
        start.t + eff.dy,
      );
      final res = computeSnap(
        moving: moving,
        others: _otherShapeBoxes(),
        threshold: 6 / (_scale * ppi),
      );
      snapDx = res.dx;
      snapDy = res.dy;
      guides = res.guides;
      // Fall back to grid snapping on any axis a neighbour didn't already
      // align (drawio snaps to the grid while dragging).
      if (_c.snapToGrid) {
        final g = _c.gridInches;
        if (snapDx == 0) {
          snapDx = (moving.l / g).roundToDouble() * g - moving.l;
        }
        if (snapDy == 0) {
          snapDy = (moving.b / g).roundToDouble() * g - moving.b;
        }
      }
    }
    final snapped = eff + Offset(snapDx, snapDy);
    final inc = snapped - _moveAppliedInches;
    _moveAppliedInches = snapped;
    if (inc.dx != 0 || inc.dy != 0) {
      _c.moveSelectionBy(inc.dx, inc.dy, transient: true);
    }
    if (!_sameGuides(guides, _guides)) {
      setState(() => _guides = guides);
    }
  }

  void _clearMoveGuides() {
    _moveStartBounds = null;
    if (_guides.isNotEmpty) setState(() => _guides = const <SnapGuide>[]);
  }

  static bool _sameGuides(List<SnapGuide> a, List<SnapGuide> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// If [localPos] is over a selected connector's bend-point or segment-midpoint
  /// handle, start a waypoint drag (promoting an auto route to explicit
  /// waypoints, inserting one at a midpoint). Returns true when a drag started.
  bool _tryStartWaypointDrag(Offset localPos) {
    final conn = _selectedConnector();
    if (conn == null) return false;
    final route = VsdxPage.connectorRoute(conn);
    void promote() {
      if (conn.waypoints.isEmpty && route.length > 2) {
        _c.setConnectorWaypoints(conn.id, route.sublist(1, route.length - 1),
            transient: true);
      }
    }

    // Existing interior vertices → move that bend point.
    for (var r = 1; r < route.length - 1; r++) {
      if ((_pageToScreen(route[r].x, route[r].y) - localPos).distanceSquared <=
          100) {
        _c.beginTransaction();
        promote();
        _waypointConnId = conn.id;
        _waypointIndex = r - 1;
        _mode = _DragMode.moveWaypoint;
        return true;
      }
    }
    // Segment midpoints → insert a new bend point there and drag it.
    for (var r = 0; r < route.length - 1; r++) {
      final mx = (route[r].x + route[r + 1].x) / 2;
      final my = (route[r].y + route[r + 1].y) / 2;
      if ((_pageToScreen(mx, my) - localPos).distanceSquared <= 100) {
        _c.beginTransaction();
        promote();
        _c.addWaypoint(conn.id, r, Offset2D(mx, my), transient: true);
        _waypointConnId = conn.id;
        _waypointIndex = r;
        _mode = _DragMode.moveWaypoint;
        return true;
      }
    }
    return false;
  }

  void _onPanEnd(DragEndDetails d) {
    switch (_mode) {
      case _DragMode.moveWaypoint:
        _c.commitTransaction();
        _waypointConnId = null;
        _waypointIndex = null;
      case _DragMode.moveShapes:
      case _DragMode.resize:
      case _DragMode.rotate:
        _c.commitTransaction();
        _activeHandle = null;
        _resizeShapeId = null;
        _resizeStartShape = null;
        _clearMoveGuides();
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
            final wasText = _c.tool == EditorTool.text;
            _c.createShapeByDrag(a.dx, a.dy, b.dx, b.dy);
            if (wasText) _startEditingNewTextBox();
          }
        }
        setState(() {
          _previewStart = null;
          _previewEnd = null;
          _connectTargetId = null;
        });
      case _DragMode.connect:
        final start = _previewStart;
        final end = _previewEnd;
        final src = _connectSourceId;
        if (start != null && end != null && src != null) {
          final a = _contentToPageInches(start);
          final b = _contentToPageInches(end);
          final target = _connectTargetId == src ? null : _connectTargetId;
          _c.createConnector(a.dx, a.dy, b.dx, b.dy,
              beginTarget: src, endTarget: target);
        }
        setState(() {
          _previewStart = null;
          _previewEnd = null;
          _connectSourceId = null;
          _connectTargetId = null;
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

  /// Abort whatever drag is in progress and revert transient model changes
  /// (Escape). Further pan updates are ignored because the mode is reset.
  void _cancelActiveDrag() {
    switch (_mode) {
      case _DragMode.moveShapes:
      case _DragMode.resize:
      case _DragMode.rotate:
      case _DragMode.moveWaypoint:
        _c.cancelTransaction();
      case _DragMode.none:
      case _DragMode.panCanvas:
      case _DragMode.createShape:
      case _DragMode.marquee:
      case _DragMode.connect:
        break;
    }
    setState(() {
      _mode = _DragMode.none;
      _previewStart = null;
      _previewEnd = null;
      _marqueeStart = null;
      _marqueeEnd = null;
      _connectSourceId = null;
      _connectTargetId = null;
      _activeHandle = null;
      _resizeShapeId = null;
      _resizeStartShape = null;
      _waypointConnId = null;
      _waypointIndex = null;
      _guides = const <SnapGuide>[];
      _moveStartBounds = null;
    });
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
    // While editing text the field owns the keyboard; never mutate shapes.
    if (_editingShapeId != null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    // Keyboard zoom (Cmd/Ctrl +/- , Cmd/Ctrl+0 = 100%, Cmd/Ctrl+Shift+H = fit).
    final zoomMod = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (zoomMod) {
      if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.add) {
        _zoomBy(1.2);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.minus) {
        _zoomBy(1 / 1.2);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit0) {
        _resetZoom();
        return KeyEventResult.handled;
      } else if (HardwareKeyboard.instance.isShiftPressed &&
          key == LogicalKeyboardKey.keyH) {
        fitToScreen();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored; // let app-level Cmd shortcuts run
    }
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      if (_c.hasSelection) {
        _c.deleteSelection();
        return KeyEventResult.handled;
      }
    } else if (key == LogicalKeyboardKey.escape) {
      // Cancel an in-progress drag first (revert to the pre-drag state).
      if (_mode != _DragMode.none) {
        _cancelActiveDrag();
        return KeyEventResult.handled;
      }
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
    if (_editingShapeId != null) _commitTextEdit();
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
        // Drop decoded pictures when a different document loaded into this
        // controller, so a reused `imageN` part name can't show a stale image.
        if (_c.documentEpoch != _imageCacheEpoch) {
          _imageCache.clear();
          _imageCacheEpoch = _c.documentEpoch;
        }
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
            if (_c.revealSerial != _lastRevealSerial) {
              _lastRevealSerial = _c.revealSerial;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _handleReveal();
              });
            }
            // Publish the current view transform to the Outline minimap.
            if (widget.camera != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  widget.camera!.publish(
                    scale: _scale,
                    offset: _offset,
                    viewport: viewport,
                    content: content,
                  );
                }
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
            final previewTool = _mode == _DragMode.createShape
                ? _c.tool
                : (_mode == _DragMode.connect ? EditorTool.connector : null);
            final marquee = (_marqueeStart != null && _marqueeEnd != null)
                ? Rect.fromPoints(_marqueeStart!, _marqueeEnd!)
                : null;
            // Hover-connect arrows (idle select mode) and the glue-target
            // highlight shown while wiring a connector.
            Rect? hoverBox;
            if (_connectAffordanceActive && _hoverShapeId != null) {
              final s = page.findShapeById(_hoverShapeId!);
              if (s != null && !s.is1D) hoverBox = _exactContentBox(s);
            }
            final targetId = _connectTargetId;
            final Rect? connectTargetRect = (targetId != null &&
                    bounds[targetId] != null)
                ? _boundsInchesToContent(bounds[targetId]!)
                : null;
            final inlineEditor = _buildInlineEditor(context);
            final guideSegments = <(Offset, Offset)>[
              for (final g in _guides)
                g.vertical
                    ? (_pageToContent(g.pos, g.start), _pageToContent(g.pos, g.end))
                    : (_pageToContent(g.start, g.pos), _pageToContent(g.end, g.pos)),
            ];
            final connector = _selectedConnector();
            var waypointHandles = const <Offset>[];
            var midpointHandles = const <Offset>[];
            if (connector != null) {
              final route = VsdxPage.connectorRoute(connector);
              waypointHandles = <Offset>[
                for (var r = 1; r < route.length - 1; r++)
                  _pageToContent(route[r].x, route[r].y),
              ];
              midpointHandles = <Offset>[
                for (var r = 0; r < route.length - 1; r++)
                  _pageToContent(
                    (route[r].x + route[r + 1].x) / 2,
                    (route[r].y + route[r + 1].y) / 2,
                  ),
              ];
            }
            return Focus(
              autofocus: true,
              onKeyEvent: _onKey,
              child: Listener(
              onPointerSignal: _onPointerSignal,
              child: MouseRegion(
              onHover: _onHover,
              onExit: (_) => _clearHover(),
              cursor: _c.tool == EditorTool.text
                  ? SystemMouseCursors.text
                  : (_c.tool == EditorTool.connector ||
                          _mode == _DragMode.connect)
                      ? SystemMouseCursors.precise
                      : MouseCursor.defer,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _onTapUp,
                onSecondaryTapUp: _onSecondaryTapUp,
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
                                      imageCache: _imageCache,
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
                                      color: _c.selectionLocked
                                          ? const Color(0xFFE53935) // drawio locked = red
                                          : Theme.of(context).colorScheme.primary,
                                      strokeWidth: 1.5 / _scale,
                                      handleSize: 7 / _scale,
                                      previewStart: _previewStart,
                                      previewEnd: _previewEnd,
                                      previewTool: previewTool,
                                      marquee: marquee,
                                      guides: guideSegments,
                                      waypointHandles: waypointHandles,
                                      midpointHandles: midpointHandles,
                                      hoverBox: hoverBox,
                                      hoverArrowGap:
                                          _connectArrowGapPx / _scale,
                                      connectTargetRect: connectTargetRect,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      ?inlineEditor,
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: _ZoomControls(
                          zoom: _scale,
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
    this.guides = const <(Offset, Offset)>[],
    this.waypointHandles = const <Offset>[],
    this.midpointHandles = const <Offset>[],
    this.hoverBox,
    this.hoverArrowGap = 0,
    this.connectTargetRect,
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

  /// Hover-connect arrow ring around the hovered shape (content-px) and the
  /// gap from its box; plus the glue-target highlight while wiring.
  final Rect? hoverBox;
  final double hoverArrowGap;
  final Rect? connectTargetRect;
  final Rect? marquee;

  /// Alignment guide lines (content-px), drawn while dragging a selection.
  final List<(Offset, Offset)> guides;

  /// Connector bend points (filled) and segment midpoints (hollow), content-px.
  final List<Offset> waypointHandles;
  final List<Offset> midpointHandles;

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
    if (guides.isNotEmpty) {
      final guidePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = const Color(0xFFFF3B9E); // drawio-style magenta guide
      for (final (a, b) in guides) {
        canvas.drawLine(a, b, guidePaint);
      }
    }
    // Connector segment midpoints (hollow) — drag to add a bend point.
    if (midpointHandles.isNotEmpty) {
      final fill = Paint()..color = Colors.white;
      for (final c in midpointHandles) {
        canvas
          ..drawCircle(c, handleSize * 0.5, fill)
          ..drawCircle(c, handleSize * 0.5, outline);
      }
    }
    // Connector bend points (filled) — drag to move, double-click to remove.
    if (waypointHandles.isNotEmpty) {
      final fill = Paint()..color = color;
      for (final c in waypointHandles) {
        canvas.drawCircle(c, handleSize * 0.7, fill);
      }
    }
    _paintConnectTarget(canvas);
    _paintHoverArrows(canvas);
    _paintPreview(canvas, outline);
  }

  /// Highlight the shape a connector would glue to on drop.
  void _paintConnectTarget(Canvas canvas) {
    final r = connectTargetRect;
    if (r == null) return;
    final rect = _normalise(r);
    canvas
      ..drawRect(rect, Paint()..color = color.withValues(alpha: 0.12))
      ..drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth * 1.6
          ..color = color,
      );
  }

  /// Directional connect arrows around the hovered shape (drawio HoverIcons).
  void _paintHoverArrows(Canvas canvas) {
    final box = hoverBox;
    if (box == null) return;
    final r = handleSize * 1.3;
    final disc = Paint()..color = color;
    final glyph = Paint()..color = Colors.white;
    for (final (c, dir) in _PageCanvasState._connectArrows(box, hoverArrowGap)) {
      canvas.drawCircle(c, r, disc);
      // A small white triangle pointing outward.
      final t = r * 0.55;
      final path = switch (dir) {
        0 => (Path()
          ..moveTo(c.dx, c.dy - t)
          ..lineTo(c.dx - t, c.dy + t * 0.6)
          ..lineTo(c.dx + t, c.dy + t * 0.6)
          ..close()),
        1 => (Path()
          ..moveTo(c.dx + t, c.dy)
          ..lineTo(c.dx - t * 0.6, c.dy - t)
          ..lineTo(c.dx - t * 0.6, c.dy + t)
          ..close()),
        2 => (Path()
          ..moveTo(c.dx, c.dy + t)
          ..lineTo(c.dx - t, c.dy - t * 0.6)
          ..lineTo(c.dx + t, c.dy - t * 0.6)
          ..close()),
        _ => (Path()
          ..moveTo(c.dx - t, c.dy)
          ..lineTo(c.dx + t * 0.6, c.dy - t)
          ..lineTo(c.dx + t * 0.6, c.dy + t)
          ..close()),
      };
      canvas.drawPath(path, glyph);
    }
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
      case EditorTool.text:
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
      old.marquee != marquee ||
      old.hoverBox != hoverBox ||
      old.hoverArrowGap != hoverArrowGap ||
      old.connectTargetRect != connectTargetRect ||
      !listEquals(old.guides, guides) ||
      !listEquals(old.waypointHandles, waypointHandles) ||
      !listEquals(old.midpointHandles, midpointHandles);
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
    required this.zoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  final double zoom;
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
          Tooltip(
            message: 'Fit to screen',
            child: InkWell(
              onTap: onFit,
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 52,
                child: Text(
                  '${(zoom * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
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
