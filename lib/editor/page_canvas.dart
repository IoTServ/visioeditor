import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vsdx/vsdx.dart';

import '../io/document_io.dart';
import '../render/image_cache.dart';
import '../render/pattern_fill.dart';
import '../render/shape_bounds.dart';
import '../render/vsdx_painter.dart';
import 'canvas_camera.dart';
import 'edit_data_dialog.dart';
import 'edit_link_dialog.dart';
import 'editor_controller.dart';
import 'image_materials.dart';
import '../l10n/editor_l10n.dart';
import 'quick_add_picker.dart';
import 'snap_guides.dart';
import 'stencils.dart';
import 'third_party_icons.dart';
import 'touch_ui.dart';

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
    this.presentationMode = false,
    this.onExitPresentation,
    this.onImageMaterialDropped,
    this.onThirdPartyIconDropped,
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

  /// When true, chrome such as zoom controls is hidden and Escape exits
  /// presentation instead of clearing the selection.
  final bool presentationMode;

  /// Called when the user presses Escape in [presentationMode] (after any
  /// in-progress drag / connection-point edit is cancelled).
  final VoidCallback? onExitPresentation;

  /// Insert a built-in image material at the drop point (page inches).
  final Future<void> Function(ImageMaterial material, {Offset? pagePt})?
      onImageMaterialDropped;

  /// Insert a third-party icon at the drop point (page inches).
  final Future<void> Function(ThirdPartyIcon icon, {Offset? pagePt})?
      onThirdPartyIconDropped;

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
  moveArea,
  moveWaypoint,
  moveEndpoint,
  moveConnectorLabel,
  rotateConnectorLabel,
  connect,
  tableColResize,
  tableRowResize,
  moveConnectionPoint,
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

  // draw.io temporary hand tool: right- or middle-button drag pans even while
  // the select/edit tool is active. A stationary right click still belongs to
  // the secondary-tap recognizer and opens the context menu.
  int? _auxPanPointer;
  Offset _auxPanLast = Offset.zero;

  /// View-only (pan tool / presentation) pinch-zoom baseline.
  double _viewScaleStart = 1;
  Offset _viewScaleContentFocal = Offset.zero;
  double _viewPinchStartDistance = 0;
  final Map<int, Offset> _viewPointers = <int, Offset>{};

  /// True while a two-finger pinch is driving zoom in view-only mode.
  bool _pinchActive = false;

  /// Touch empty-canvas pan that may still become a marquee if held still.
  DateTime? _emptyTouchPanAt;
  Offset? _emptyTouchPanOrigin;
  Offset _emptyTouchPanAccum = Offset.zero;

  // Reveal ("scroll into view") — tracks the controller's revealSerial.
  int _lastRevealSerial = 0;
  // App-level Enter requests — the inline editor itself belongs to this state.
  int _lastTextEditRequestSerial = 0;
  // Fit-to-window requests (toolbar / zoom controls) — tracks fitSerial.
  int _lastFitSerial = 0;
  // Reset-to-100% requests (draw.io Home) — tracks resetViewSerial.
  int _lastResetViewSerial = 0;
  Offset _doubleTapPos = Offset.zero;
  _Handle? _activeHandle;
  int? _resizeShapeId;
  // Shape state captured when a resize begins, so aspect-lock / resize-from-
  // centre stay stable across the whole drag.
  VsdxShape? _resizeStartShape;

  /// Table column/row divider drag (draw.io table resize).
  int? _tableResizeId;
  int? _tableDividerIndex; // boundary after this col/row
  Offset _tableResizeLastPage = Offset.zero; // last pointer in page inches

  // In-place text editing: the shape whose label is being edited (if any),
  // plus the field's controller / focus node.
  int? _editingShapeId;
  // Id of a text box just created by the Text tool (drawio): if it is
  // committed / cancelled while still empty it is removed again.
  int? _newTextBoxId;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocus = FocusNode(debugLabel: 'inlineTextEditor');

  /// Owns canvas keyboard handling (Delete, arrows, Escape, zoom). Re-focused
  /// on pointer interaction so keys keep working after toolbar / sidebar focus.
  final FocusNode _canvasFocus = FocusNode(debugLabel: 'pageCanvas');

  // Smart alignment guides (drawio-style) shown while moving a selection.
  ({double l, double b, double r, double t})? _moveStartBounds; // inches, y-up
  Offset _moveAccumInches = Offset.zero; // raw accumulated delta from start
  Offset _moveAppliedInches = Offset.zero; // snapped delta applied so far
  bool _remoteMove = false; // Alt+Shift blank-canvas drag owns Shift itself
  List<SnapGuide> _guides = const <SnapGuide>[];

  // Connector waypoint drag (drawio bend points).
  int? _waypointConnId;
  int? _waypointIndex;

  // Connector endpoint drag (drawio endpoint editing): the connector whose
  // begin / end handle is being dragged to reconnect or detach.
  int? _endpointConnId;
  bool _endpointIsBegin = false;

  // Connector label drag (draw.io yellow diamond handle).
  int? _connectorLabelId;

  // Hover-to-connect (drawio HoverIcons / EdrawMax quick-add): the top-level
  // shape currently under the cursor in idle select mode (shows directional
  // arrows), the source while dragging a connector from a blue connection
  // point / perimeter / arrow, and the glue target while wiring.
  int? _hoverShapeId;
  int? _connectSourceId;
  int? _connectTargetId;

  /// Dismisses an open quick-add shape picker, if any.
  VoidCallback? _dismissQuickAdd;

  /// Arrow press that became a pan (slop) — open quick-add on release if the
  /// pointer barely moved, so jittery clicks still work when Tap loses the arena.
  ({int id, int dir, Offset start})? _pendingQuickAdd;

  /// Container under the pointer while dragging shapes (drop-into highlight).
  int? _dropContainerId;

  /// Atomic shape under a stencil drag that will be replaced on drop.
  int? _stencilReplaceTargetId;

  /// Free connector endpoint under a stencil drag (draw.io blue drop circle).
  ({int connectorId, bool begin, double x, double y})?
      _stencilConnectorEndTarget;

  /// Shape and optional directional arrow under a stencil drag. Hovering a
  /// shape keeps its quick-connect arrows visible; dropping on one inserts the
  /// stencil in that direction and wires it in the same undo step (draw.io).
  ({int sourceId, int? dir})? _stencilShapeConnectionTarget;

  // Whether the pointer sits on a shape connection point / perimeter (crosshair)
  // or a directional quick-add arrow (click cursor).
  bool _hoverOnConnectPoint = false;
  bool _hoverOnQuickAddArrow = false;

  // Fixed connection-point index the new connector's begin end glues to (the
  // arrow / blue point it was dragged out of), or null for a whole-shape glue.
  int? _connectSourceConnIndex;

  // Alt/Option connector drops create a custom fixed point at the exact
  // pointer position. Keep the source and live target intent independently so
  // connector-tool drags can fix either end in one creation edit.
  bool _connectSourceFixedAtPosition = false;
  bool _connectTargetFixedAtPosition = false;

  // Direction of a connector drag that started on a quick-connect arrow.
  // Holding Ctrl/Cmd on release clones the source at the drop point and wires
  // the clone instead of leaving a floating connector (draw.io).
  int? _connectArrowDirection;

  // Fixed connection point (drawio blue point) the pointer is snapping to on
  // the current target while wiring / dragging an endpoint (index into the
  // target's effective connection points), or null for a whole-shape glue.
  int? _snapConnIndex;

  /// Index of the connection point being dragged in edit-connection-points mode.
  int? _connPointDragIndex;

  /// Screen-px gap from a shape's box to its hover-connect arrows.
  static const double _connectArrowGapPx = 22;
  static const double _connectArrowHitPx = 15;

  /// Touch: push arrows farther out so they clear larger resize handles.
  static const double _connectArrowGapTouchPx = 38;
  static const double _connectArrowHitTouchPx = 26;

  /// Screen-px radius within which an endpoint snaps to a connection point.
  static const double _connSnapPx = 13;

  /// Touch / phone chrome: selection quick-add arrows, larger hit targets, and
  /// empty-canvas pan.
  ///
  /// Native Android/iOS use [isNativeMobileOs] (not [defaultTargetPlatform]) so
  /// `flutter test` on a desktop host keeps mouse chrome. Compact width covers
  /// phone browsers and the responsive layout breakpoint.
  bool get _isTouchUi {
    if (isNativeMobileOs) return true;
    final size = MediaQuery.maybeSizeOf(context);
    return size != null && size.width < 720;
  }

  /// draw.io modifier semantics: Alt/Option bypasses all snapping for precise
  /// placement; Ctrl/Cmd-drag clones the selection.
  bool get _bypassSnapping => HardwareKeyboard.instance.isAltPressed;
  bool get _customFixedConnectorDrop =>
      HardwareKeyboard.instance.isAltPressed;
  bool get _forceFloatingConnectorDrop =>
      !_customFixedConnectorDrop &&
      HardwareKeyboard.instance.isShiftPressed;
  bool get _cloneDrag =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  double get _connectArrowGapPxEffective =>
      _isTouchUi ? _connectArrowGapTouchPx : _connectArrowGapPx;

  double get _connectArrowHitPxEffective =>
      _isTouchUi ? _connectArrowHitTouchPx : _connectArrowHitPx;

  /// Screen-px hit radius for resize / rotate / endpoint knobs.
  double get _handleHitPx => _isTouchUi ? 22 : 12;

  /// Shape that should show directional quick-add arrows right now.
  ///
  /// Touch layouts prefer the single selection (no reliable hover). Mouse
  /// hover still wins on desktop so unselected shapes keep draw.io parity.
  int? get _connectAffordanceShapeId {
    if (!_connectAffordanceActive) return null;
    if (_isTouchUi) {
      final selected = _singleSelectedShape();
      if (selected != null && _canConnectFrom(selected)) return selected.id;
    }
    if (_hoverShapeId != null) return _hoverShapeId;
    return null;
  }

  // Creation preview, in content-px space.
  Offset? _previewStart;
  Offset? _previewEnd;

  /// Freehand stroke samples in content-px (drawio Freehand live ink).
  final List<Offset> _freehandPoints = <Offset>[];

  // Marquee selection rectangle, in content-px space.
  Offset? _marqueeStart;
  Offset? _marqueeEnd;

  // draw.io Alt+Ctrl/Cmd+Shift blank-canvas drag ("move area").
  Offset? _areaOriginPage;
  Offset? _areaStartContent;
  Offset? _areaEndContent;
  Offset _areaAppliedPage = Offset.zero;
  Set<int>? _areaHorizontalIds;
  Set<int>? _areaVerticalIds;

  /// Async decode cache for embedded pictures, keyed by media part name. The
  /// painter repaints when a decode lands (`super(repaint: imageCache)`).
  /// Rebuilt whenever a fresh document loads (see [_imageCacheEpoch]).
  final VsdxImageCache _imageCache = VsdxImageCache();
  int _imageCacheEpoch = 0;

  @override
  void initState() {
    super.initState();
    _textFocus.addListener(_onEditorFocusChange);
    _textController.addListener(_onTextControllerChanged);
    _imageCacheEpoch = widget.controller.documentEpoch;
  }

  @override
  void dispose() {
    _dismissQuickAdd?.call();
    _dismissQuickAdd = null;
    _pendingQuickAdd = null;
    _textFocus
      ..removeListener(_onEditorFocusChange)
      ..dispose();
    _textController
      ..removeListener(_onTextControllerChanged)
      ..dispose();
    _canvasFocus.dispose();
    _imageCache.dispose();
    super.dispose();
  }

  /// Ensure diagram keys reach [_onKey] after the user clicks / drags the page.
  void _ensureCanvasFocus() {
    if (_editingShapeId != null) return;
    if (!_canvasFocus.hasFocus) _canvasFocus.requestFocus();
  }

  /// Commit the in-place edit when the field loses focus (e.g. the user clicks
  /// another window or tabs away). Deferred one frame so a toolbar Bold/Color
  /// press can still see [EditorController.textEditSelection] and apply a
  /// range format before the session is cleared (draw.io behaviour).
  void _onEditorFocusChange() {
    if (!_textFocus.hasFocus && _editingShapeId != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_textFocus.hasFocus && _editingShapeId != null && mounted) {
          _commitTextEdit();
        }
      });
    }
  }

  /// Keep the controller's text-edit session in sync so toolbar formatting can
  /// target the current UTF-16 selection (draw.io-style per-run edits).
  void _onTextControllerChanged() {
    final id = _editingShapeId;
    if (id == null) return;
    final sel = _textController.selection;
    _c.setTextEditSession(
      shapeId: id,
      start: sel.start,
      end: sel.end,
    );
    // Rebuild so the mixed-style preview tracks typing.
    if (mounted) setState(() {});
  }

  void _syncTextEditSession() {
    final id = _editingShapeId;
    if (id == null) {
      _c.setTextEditSession();
      return;
    }
    final sel = _textController.selection;
    _c.setTextEditSession(
      shapeId: id,
      start: sel.start,
      end: sel.end,
    );
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
    final scale =
        (sx < sy ? sx : sy).clamp(widget.minScale, widget.maxScale).toDouble();
    final offset = Offset(
      (viewport.width - content.width * scale) / 2,
      (viewport.height - content.height * scale) / 2,
    );
    if (_scale == scale && _offset == offset) return;
    setState(() {
      _scale = scale;
      _offset = offset;
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

  List<int> _hitTests(Offset viewportPos) {
    final page = _page;
    if (page == null) return const <int>[];
    final pt = _contentToPageInches(_viewportToContent(viewportPos));
    final bounds = buildShapeBounds(page);
    // Prefer the top-most shape in draw order (parents before children,
    // siblings in list order). Keep every hit in bottom-to-top order so
    // Alt-click can cycle through overlapping shapes like draw.io.
    // 1-D strokes: AABB is only a coarse filter — require proximity to the
    // polyline so diagonal connectors do not steal hits from shapes below.
    final hits = <int>[];
    for (final id in _drawOrder(page)) {
      final s = page.findShapeById(id);
      if (s == null || !page.isShapeVisible(s)) continue;
      final r = bounds[id];
      if (r == null || !r.contains(pt)) continue;
      if (s.is1D && !_hit1DStroke(page, s, pt)) continue;
      hits.add(id);
    }
    return hits;
  }

  int? _hitTest(Offset viewportPos) {
    final hits = _hitTests(viewportPos);
    return hits.isEmpty ? null : hits.last;
  }

  /// draw.io Alt-click: select the next object below the top-most selected hit.
  ///
  /// If the current selection is a group/chart root while a nested child is the
  /// raw top hit, the first Alt-click drills into that child. Repeated clicks
  /// then cycle down the local z-order and wrap.
  int? _hitBelow(Offset viewportPos) {
    final hits = _hitTests(viewportPos);
    if (hits.isEmpty) return null;
    final page = _page;
    final top = hits.last;
    for (var i = hits.length - 1; i >= 0; i--) {
      final selected = hits[i];
      if (!_c.isSelected(selected)) continue;
      // A normal click may have selected a chart/group root while the raw hit
      // is one of its children. Drill into that child before cycling below.
      var parent = page?.findParentId(top);
      while (parent != null) {
        if (parent == selected) return top;
        parent = page?.findParentId(parent);
      }
      return hits[(i - 1 + hits.length) % hits.length];
    }
    return top;
  }

  /// Resolve a raw deepest hit using draw.io's group drill-down semantics.
  ///
  /// The first click selects the outer plain group. Clicking the same point
  /// again descends one level, while a selected sibling lets another sibling
  /// be selected directly. Alt bypasses groups and keeps the deepest raw hit.
  /// Charts retain their existing root-first behaviour.
  int _selectionAwareHit(int hit) {
    if (HardwareKeyboard.instance.isAltPressed) return hit;
    final page = _page;
    if (page == null) return hit;

    // Charts are edited as one semantic object unless Alt explicitly drills
    // into their generated series children.
    var cur = hit;
    while (true) {
      final s = page.findShapeById(cur);
      if (s != null && ChartOps.isChart(s)) return cur;
      final p = page.findParentId(cur);
      if (p == null) break;
      cur = p;
    }

    // Inner→outer path, including the raw hit.
    final path = <int>[hit];
    var parent = page.findParentId(hit);
    while (parent != null) {
      path.add(parent);
      parent = page.findParentId(parent);
    }

    final selected = _c.singleSelectedId;
    if (selected != null) {
      // Once inside a group, clicking another child of that same group should
      // switch siblings instead of jumping back out to the group.
      final selectedParent = page.findParentId(selected);
      if (selectedParent != null &&
          page.findShapeById(selectedParent)?.shapeKind ==
              VsdxShapeKind.group) {
        final commonParentIndex = path.indexOf(selectedParent);
        if (commonParentIndex > 0) return path[commonParentIndex - 1];
      }

      // A selected ancestor drills exactly one level towards the raw hit.
      final selectedIndex = path.indexOf(selected);
      if (selectedIndex > 0) return path[selectedIndex - 1];
      if (selectedIndex == 0) return hit;
    }

    // With no active ancestor, select the outermost plain group first.
    for (final id in path.reversed) {
      if (id != hit &&
          page.findShapeById(id)?.shapeKind == VsdxShapeKind.group) {
        return id;
      }
    }
    return hit;
  }

  /// True when [pt] (page inches) is within stroke hit distance of [s]'s path.
  bool _hit1DStroke(VsdxPage page, VsdxShape s, Offset pt) {
    final segs = _strokePageSegments(page, s);
    if (segs.isEmpty) return true;
    final half = math.max(s.line.weightInches.abs() / 2, 0.01);
    final screenPad = 5.0 / math.max(widget.pxPerInch * _scale, 1e-6);
    final tol = half + screenPad;
    final tol2 = tol * tol;
    for (final (a, b) in segs) {
      if (_dist2PointToSeg(pt.dx, pt.dy, a.x, a.y, b.x, b.y) <= tol2) {
        return true;
      }
    }
    return false;
  }

  /// Page-inch stroke segments for hit-testing / marquee (glueable route,
  /// sampled outline for arcs/beziers, else Begin→End).
  List<(Offset2D, Offset2D)> _strokePageSegments(VsdxPage page, VsdxShape s) {
    if (s.isGlueableConnector) {
      final drawn = page.drawnConnectorPagePolyline(s);
      if (drawn.length >= 2) {
        return <(Offset2D, Offset2D)>[
          for (var i = 0; i < drawn.length - 1; i++) (drawn[i], drawn[i + 1]),
        ];
      }
    }
    final localSegs = ShapePerimeter.outlineSegments(s);
    if (localSegs.isNotEmpty) {
      return <(Offset2D, Offset2D)>[
        for (final (a, b) in localSegs)
          (page.localToPageDeep(s.id, a), page.localToPageDeep(s.id, b)),
      ];
    }
    // Begin/End live in the parent (or page) frame for 1-D shapes.
    final ax = s.beginX ?? s.pinX, ay = s.beginY ?? s.pinY;
    final bx = s.endX ?? s.pinX, by = s.endY ?? s.pinY;
    final parentId = page.findParentId(s.id);
    Offset2D toPage(double x, double y) {
      if (parentId == null) return Offset2D(x, y);
      return page.localToPageDeep(parentId, Offset2D(x, y));
    }

    return <(Offset2D, Offset2D)>[(toPage(ax, ay), toPage(bx, by))];
  }

  static double _dist2PointToSeg(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 < 1e-24) {
      final ex = px - ax, ey = py - ay;
      return ex * ex + ey * ey;
    }
    var t = ((px - ax) * dx + (py - ay) * dy) / len2;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    final qx = ax + t * dx, qy = ay + t * dy;
    final ex = px - qx, ey = py - qy;
    return ex * ex + ey * ey;
  }

  static List<int> _drawOrder(VsdxPage page) {
    final out = <int>[];
    void walk(VsdxShape s) {
      // Match paint: hidden-layer hosts skip their whole subtree.
      if (!page.isShapeVisible(s)) return;
      out.add(s.id);
      if (s.collapsed) return; // hide children while folded (draw.io)
      for (final c in s.children) {
        walk(c);
      }
    }

    for (final s in page.shapes) {
      walk(s);
    }
    return out;
  }

  /// Click the fold chevron on a container / swimlane header (draw.io).
  bool _tryToggleCollapse(Offset viewportPos) {
    final page = _page;
    if (page == null) return false;
    final pt = _contentToPageInches(_viewportToContent(viewportPos));
    for (final id in _drawOrder(page).reversed) {
      final s = page.findShapeById(id);
      if (s == null ||
          !s.shapeKind.isFoldable ||
          !page.isShapeVisible(s)) {
        continue;
      }
      final local = VsdxPainter.collapseChevronLocalCenter(s);
      final pagePt =
          page.localToPageDeep(s.id, Offset2D(local.dx, local.dy));
      final r = VsdxPainter.collapseChevronHitRadius(s);
      final dx = pt.dx - pagePt.x;
      final dy = pt.dy - pagePt.y;
      if (dx * dx + dy * dy <= r * r) {
        _c.toggleCollapsed(id);
        return true;
      }
    }
    return false;
  }

  // --- Gestures --------------------------------------------------------------

  Offset _pageInchesAt(Offset viewportPos) =>
      _contentToPageInches(_viewportToContent(viewportPos));

  /// Spans the viewport (see the keyed `ClipRect` in `build`); used to convert
  /// a stencil drag-drop's global position into canvas-local coordinates.
  final GlobalKey _canvasBoxKey = GlobalKey();

  int? _stencilReplaceTargetAt(Offset viewportPos) {
    final keyboard = HardwareKeyboard.instance;
    // Alt or Shift explicitly means overlap: do not replace or contain.
    if (keyboard.isAltPressed || keyboard.isShiftPressed) return null;
    for (final id in _hitTests(viewportPos).reversed) {
      if (_c.canReplaceShape(id)) return id;
    }
    return null;
  }

  ({int connectorId, bool begin, double x, double y})?
      _stencilConnectorEndTargetAt(Offset viewportPos) {
    if (HardwareKeyboard.instance.isAltPressed) return null;
    final page = _page;
    if (page == null) return null;
    final threshold = _connSnapPx * 1.4;
    var bestDistance = threshold * threshold;
    ({int connectorId, bool begin, double x, double y})? best;
    final gluedBegins = <int>{
      for (final row in page.connects)
        if (row.isBegin) row.fromSheetId,
    };
    final gluedEnds = <int>{
      for (final row in page.connects)
        if (row.isEnd) row.fromSheetId,
    };
    for (final id in _drawOrder(page)) {
      final connector = page.findShapeById(id);
      if (connector == null ||
          !connector.isGlueableConnector ||
          connector.locked ||
          _c.isOnLockedLayer(id) ||
          !page.isShapeVisible(connector)) {
        continue;
      }
      final route = _connectorRoutePage(connector);
      if (route.length < 2) continue;
      for (final candidate in <({bool begin, Offset2D point})>[
        if (!gluedBegins.contains(id)) (begin: true, point: route.first),
        if (!gluedEnds.contains(id)) (begin: false, point: route.last),
      ]) {
        final point = candidate.point;
        final distance =
            (_pageToScreen(point.x, point.y) - viewportPos).distanceSquared;
        if (distance <= bestDistance) {
          bestDistance = distance;
          best = (
            connectorId: id,
            begin: candidate.begin,
            x: point.x,
            y: point.y,
          );
        }
      }
    }
    return best;
  }

  ({int sourceId, int? dir})?
      _stencilShapeConnectionTargetAt(Offset viewportPos) {
    if (HardwareKeyboard.instance.isAltPressed) return null;
    final page = _page;
    if (page == null) return null;

    // Arrows sit outside the shape hit area. Check every eligible shape first
    // so a library drag can land directly on an arrow even if it did not pass
    // over the shape body slowly enough to establish hover.
    for (final id in _drawOrder(page).reversed) {
      final shape = page.findShapeById(id);
      if (shape == null ||
          !_canConnectFrom(shape) ||
          !page.isShapeVisible(shape)) {
        continue;
      }
      final dir = _connectArrowHitDir(shape, viewportPos);
      if (dir != null) return (sourceId: id, dir: dir);
    }

    // Preserve the source while crossing the small gap from its edge to an
    // arrow, matching the stable hover affordance used for pointer wiring.
    final previous = _stencilShapeConnectionTarget;
    if (previous != null) {
      final shape = page.findShapeById(previous.sourceId);
      if (shape != null &&
          _canConnectFrom(shape) &&
          page.isShapeVisible(shape) &&
          _withinConnectAffordance(shape, viewportPos)) {
        return (sourceId: shape.id, dir: null);
      }
    }

    for (final id in _hitTests(viewportPos).reversed) {
      final shape = page.findShapeById(id);
      if (shape != null &&
          _canConnectFrom(shape) &&
          page.isShapeVisible(shape)) {
        return (sourceId: id, dir: null);
      }
    }
    return null;
  }

  void _onStencilMoved(DragTargetDetails<Stencil> details) {
    final box = _canvasBoxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.offset);
    final connectorTarget = _stencilConnectorEndTargetAt(local);
    final shapeConnectionTarget = connectorTarget == null
        ? _stencilShapeConnectionTargetAt(local)
        : null;
    final replaceTarget = connectorTarget == null &&
            shapeConnectionTarget?.dir == null
        ? _stencilReplaceTargetAt(local)
        : null;
    if (replaceTarget != _stencilReplaceTargetId ||
        connectorTarget != _stencilConnectorEndTarget ||
        shapeConnectionTarget != _stencilShapeConnectionTarget) {
      setState(() {
        _stencilReplaceTargetId = replaceTarget;
        _stencilConnectorEndTarget = connectorTarget;
        _stencilShapeConnectionTarget = shapeConnectionTarget;
      });
    }
  }

  void _onStencilLeft(Stencil? _) {
    if (_stencilReplaceTargetId != null ||
        _stencilConnectorEndTarget != null ||
        _stencilShapeConnectionTarget != null) {
      setState(() {
        _stencilReplaceTargetId = null;
        _stencilConnectorEndTarget = null;
        _stencilShapeConnectionTarget = null;
      });
    }
  }

  /// A stencil dropped from the shapes palette (drawio drag-and-drop): replace
  /// an atomic shape under a plain drop, insert and connect on a directional
  /// arrow, or otherwise create at the drop point. Alt disables automatic
  /// connections; Alt/Shift force overlap and disable replacement/containment.
  void _onStencilDropped(DragTargetDetails<Stencil> details) {
    final box = _canvasBoxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.offset);
    final connectorTarget = _stencilConnectorEndTargetAt(local);
    final shapeConnectionTarget = connectorTarget == null
        ? _stencilShapeConnectionTargetAt(local)
        : null;
    final replaceTarget = connectorTarget == null &&
            shapeConnectionTarget?.dir == null
        ? _stencilReplaceTargetAt(local)
        : null;
    if (_stencilReplaceTargetId != null ||
        _stencilConnectorEndTarget != null ||
        _stencilShapeConnectionTarget != null) {
      setState(() {
        _stencilReplaceTargetId = null;
        _stencilConnectorEndTarget = null;
        _stencilShapeConnectionTarget = null;
      });
    }
    final keyboard = HardwareKeyboard.instance;
    if (connectorTarget != null &&
        _c.attachShapeToConnectorEnd(
          connectorTarget.connectorId,
          begin: connectorTarget.begin,
          build: details.data.build,
          inheritStyle: !keyboard.isShiftPressed,
        )) {
      return;
    }
    final direction = shapeConnectionTarget?.dir;
    if (direction != null) {
      final source =
          _page?.findShapeById(shapeConnectionTarget!.sourceId);
      if (source != null && _canConnectFrom(source)) {
        final (cx, cy) = _neighbourCentre(source, direction);
        _c.quickAddInDirection(
          source.id,
          direction,
          build: details.data.build,
          cx: cx,
          cy: cy,
          inheritStyle: !keyboard.isShiftPressed,
        );
        return;
      }
    }
    if (replaceTarget != null &&
        _c.replaceShapeWithBuilder(replaceTarget, details.data.build)) {
      return;
    }
    final p = _pageInchesAt(local);
    final overlay = keyboard.isAltPressed || keyboard.isShiftPressed;
    _c.addShapeFromBuilderAt(
      details.data.build,
      p.dx,
      p.dy,
      // Shift-drag also ignores a custom palette style.
      inheritStyle: !keyboard.isShiftPressed,
      allowContainment: !overlay,
    );
  }

  /// A clipart tile dropped from the image-materials palette.
  void _onImageMaterialDropped(DragTargetDetails<ImageMaterial> details) {
    final handler = widget.onImageMaterialDropped;
    if (handler == null) return;
    final box = _canvasBoxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final p = _pageInchesAt(box.globalToLocal(details.offset));
    unawaited(handler(details.data, pagePt: p));
  }

  /// An icon tile dropped from the third-party icons palette.
  void _onThirdPartyIconDropped(DragTargetDetails<ThirdPartyIcon> details) {
    final handler = widget.onThirdPartyIconDropped;
    if (handler == null) return;
    final box = _canvasBoxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final p = _pageInchesAt(box.globalToLocal(details.offset));
    unawaited(handler(details.data, pagePt: p));
  }

  VsdxShape? _singleSelectedShape() {
    final page = _page;
    if (page == null || _c.selection.length != 1) return null;
    return page.findShapeById(_c.selection.first);
  }

  /// The single selected shape if it is a non-rotated 2-D shape that supports
  /// box resize. Locked shapes never expose resize handles (drawio parity).
  /// Nested shapes under a rotated ancestor are excluded — page-AABB handles
  /// would not align with the local resize axes.
  VsdxShape? _resizableSelection() {
    if (_c.editingConnectionPoints) return null;
    final s = _singleSelectedShape();
    // Glueable connectors use endpoint handles; freehand ink uses box resize
    // (AABB geometry) like 2-D shapes.
    if (s == null ||
        s.isGlueableConnector ||
        s.angleRad != 0 ||
        s.locked ||
        _c.isOnLockedLayer(s.id)) {
      return null;
    }
    if (_ancestorRotated(s.id)) return null;
    return s;
  }

  /// Whether any ancestor of [id] has a non-zero rotation.
  bool _ancestorRotated(int id) {
    final page = _page;
    if (page == null) return false;
    var parent = page.findParentId(id);
    while (parent != null) {
      final s = page.findShapeById(parent);
      if (s == null) return false;
      if (s.angleRad != 0) return true;
      parent = page.findParentId(parent);
    }
    return false;
  }

  /// The single selected shape if it is a 2-D shape that supports rotation.
  /// Locked shapes never expose the rotation handle (drawio parity).
  VsdxShape? _rotatableSelection() {
    if (_c.editingConnectionPoints) return null;
    final s = _singleSelectedShape();
    if (s == null ||
        s.isGlueableConnector ||
        s.locked ||
        _c.isOnLockedLayer(s.id)) {
      return null;
    }
    return s;
  }

  /// 2-D shape eligible for hover-connect / connection-point affordances.
  bool _canConnectFrom(VsdxShape s) =>
      !s.is1D && !s.locked && !_c.isOnLockedLayer(s.id);

  /// Connector eligible for endpoint / waypoint editing (not freehand ink).
  bool _canEditConnector(VsdxShape s) =>
      s.isGlueableConnector && !s.locked && !_c.isOnLockedLayer(s.id);

  Offset _pageToContent(double x, double y) => Offset(
        x * widget.pxPerInch,
        (_page!.heightInches - y) * widget.pxPerInch,
      );

  Offset _pageToScreen(double x, double y) =>
      _offset + _pageToContent(x, y) * _scale;

  /// The single selected glueable connector, or null (excludes freehand ink).
  VsdxShape? _selectedConnector() {
    final s = _singleSelectedShape();
    return (s != null && s.isGlueableConnector) ? s : null;
  }

  bool _connectorHasLabel(VsdxShape connector) =>
      connector.richText.plainText.isNotEmpty ||
      (connector.text?.isNotEmpty ?? false);

  /// Page-space anchor of the connector's single VSDX label.
  Offset2D _connectorLabelPage(VsdxShape connector) {
    final page = _page!;
    final block = connector.richText.textBlock;
    if (block.pinXInches != null || block.pinYInches != null) {
      return page.localToPageDeep(
        connector.id,
        Offset2D(
          block.pinXInches ?? connector.width / 2,
          block.pinYInches ?? connector.height / 2,
        ),
      );
    }
    return _connectorMidpointPage(connector);
  }

  /// Content-space label pin and rotate knob. The knob follows the text
  /// block's rotated local +Y axis and keeps a constant on-screen distance.
  (Offset anchor, Offset knob) _connectorLabelRotateAnchors(
    VsdxShape connector,
  ) {
    final page = _page!;
    final block = connector.richText.textBlock;
    final pinPage = _connectorLabelPage(connector);
    final pinLocal = page.pageToLocalDeep(connector.id, pinPage);
    final tipLocal = Offset2D(
      pinLocal.x - math.sin(block.angleRad),
      pinLocal.y + math.cos(block.angleRad),
    );
    final tipPage = page.localToPageDeep(connector.id, tipLocal);
    final anchor = _pageToContent(pinPage.x, pinPage.y);
    final tip = _pageToContent(tipPage.x, tipPage.y);
    final delta = tip - anchor;
    final length = delta.distance;
    final direction = length > 1e-9 ? delta / length : const Offset(0, -1);
    final gap = (_isTouchUi ? 48.0 : 26.0) / _scale;
    return (anchor, anchor + direction * gap);
  }

  /// Content-px positions of (rotate-line anchor at the shape's oriented top
  /// centre, rotate-handle knob just beyond it).
  (Offset anchor, Offset knob) _rotateAnchors(VsdxShape s) {
    final page = _page!;
    // Top-centre of the local box, mapped through any parent groups.
    final top = page.localToPageDeep(s.id, Offset2D(s.width / 2, s.height));
    final pin = page.shapePinPage(s.id);
    final dx = top.x - pin.x;
    final dy = top.y - pin.y;
    final len = math.sqrt(dx * dx + dy * dy);
    final offIn = (_isTouchUi ? 52.0 : 22.0) / (_scale * widget.pxPerInch);
    final ux = len > 1e-9 ? dx / len : 0.0;
    final uy = len > 1e-9 ? dy / len : 1.0;
    final knobX = top.x + ux * offIn;
    final knobY = top.y + uy * offIn;
    return (_pageToContent(top.x, top.y), _pageToContent(knobX, knobY));
  }

  /// Axis-aligned selection box of [s] in content-px space.
  ///
  /// Uses page-space AABB with ancestor XForms composed — nested Group
  /// children store Pin in parent-local inches, not page inches.
  Rect _exactContentBox(VsdxShape s) {
    final page = _page!;
    final aabb = page.shapePageAabb(s.id);
    if (aabb == null) {
      return Rect.zero;
    }
    return _normaliseRect(
      _boundsInchesToContent(
        Rect.fromLTRB(aabb.left, aabb.bottom, aabb.right, aabb.top),
      ),
    );
  }

  /// Page-inch position of a connection point on [s] (ancestor-aware).
  Offset2D _connPointPage(VsdxShape s, Offset2D local) =>
      _page!.localToPageDeep(s.id, local);

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

  /// Whether hover-connect affordances should be offered right now.
  bool get _connectAffordanceActive =>
      !widget.presentationMode &&
      _mode == _DragMode.none &&
      _c.tool == EditorTool.select &&
      _editingShapeId == null &&
      !_c.editingConnectionPoints;

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

  static Rect _normaliseRect(Rect r) => Rect.fromLTRB(
        math.min(r.left, r.right),
        math.min(r.top, r.bottom),
        math.max(r.left, r.right),
        math.max(r.top, r.bottom),
      );

  /// If [viewportPos] is on one of [s]'s connect arrows, return its direction.
  int? _connectArrowHitDir(VsdxShape s, Offset viewportPos) {
    final gap = _connectArrowGapPxEffective / _scale;
    final anchors = _connectArrows(_exactContentBox(s), gap);
    final hit = _connectArrowHitPxEffective * _connectArrowHitPxEffective;
    for (final (c, dir) in anchors) {
      if ((_offset + c * _scale - viewportPos).distanceSquared <= hit) {
        return dir;
      }
    }
    return null;
  }

  /// Whether [viewportPos] is within the hover-connect "halo" of [s] — its box
  /// plus enough margin to cover the connect arrows. Keeping the hover alive
  /// across this whole zone means the arrows don't vanish in the gap between
  /// the shape's edge and the arrow hit-circles as the pointer travels out to
  /// them (drawio keeps the icons visible around the shape).
  bool _withinConnectAffordance(VsdxShape s, Offset viewportPos) {
    final box = _normaliseRect(_exactContentBox(s));
    final screen = Rect.fromLTRB(
      _offset.dx + box.left * _scale,
      _offset.dy + box.top * _scale,
      _offset.dx + box.right * _scale,
      _offset.dy + box.bottom * _scale,
    );
    // Reach a little past the arrow hit-circles (gap + hit) so there's no dead
    // zone against the shape and a bit of slack beyond the triangles.
    final margin =
        _connectArrowGapPxEffective + _connectArrowHitPxEffective + 8;
    return screen.inflate(margin).contains(viewportPos);
  }

  void _onHover(PointerHoverEvent e) {
    if (!_connectAffordanceActive) {
      if (_hoverShapeId != null) setState(() => _hoverShapeId = null);
      return;
    }
    final pos = e.localPosition;
    // Deepest 2-D shape so nested children get hover-connect arrows too.
    var next = _glueTargetAt(pos);
    // Keep the current hover while the pointer is anywhere in its arrow halo
    // (the arrows sit outside the shape, so a plain hit-test there clears it —
    // and there's a gap between the edge and the arrow hit-circles).
    if (next == null && _hoverShapeId != null) {
      final s = _page?.findShapeById(_hoverShapeId!);
      if (s != null &&
          _canConnectFrom(s) &&
          _withinConnectAffordance(s, pos)) {
        next = _hoverShapeId;
      }
    }
    // Don't offer arrows on 1-D shapes (connectors) or locked / locked-layer.
    if (next != null) {
      final s = _page?.findShapeById(next);
      if (s == null || !_canConnectFrom(s)) next = null;
    }
    // Cursor affordances: arrows → click/drag (quick-add/connector); blue CPs
    // and perimeter → crosshair (draw a connector glued to the shape).
    var onConnect = false;
    var onArrow = false;
    if (next != null) {
      final s = _page?.findShapeById(next);
      if (s != null && _canConnectFrom(s)) {
        onArrow = _connectArrowHitDir(s, pos) != null;
        onConnect = !onArrow &&
            _resizableSelection()?.id != s.id &&
            (_connDragSourceIndex(s, pos) != null ||
                _nearShapePerimeter(s, pos));
      }
    }
    if (next != _hoverShapeId ||
        onConnect != _hoverOnConnectPoint ||
        onArrow != _hoverOnQuickAddArrow) {
      setState(() {
        _hoverShapeId = next;
        _hoverOnConnectPoint = onConnect;
        _hoverOnQuickAddArrow = onArrow;
      });
    }
  }

  void _clearHover() {
    if (_hoverShapeId != null ||
        _hoverOnConnectPoint ||
        _hoverOnQuickAddArrow) {
      setState(() {
        _hoverShapeId = null;
        _hoverOnConnectPoint = false;
        _hoverOnQuickAddArrow = false;
      });
    }
  }

  /// Pan tool or presentation: drag/pinch the viewport, no shape editing.
  bool get _viewOnlyGestures =>
      widget.presentationMode || _c.tool == EditorTool.pan;

  void _onTapUp(TapUpDetails d) {
    if (_editingShapeId != null) {
      _commitTextEdit(); // a click outside the editor applies the edit
      return;
    }
    _ensureCanvasFocus();
    if (widget.presentationMode) {
      // Slideshow: click advances; Shift+click goes back.
      if (HardwareKeyboard.instance.isShiftPressed) {
        if (_c.currentPageIndex > 0) {
          _c.selectPage(_c.currentPageIndex - 1);
        }
      } else if (_c.currentPageIndex < _c.pageCount - 1) {
        _c.selectPage(_c.currentPageIndex + 1);
      }
      return;
    }
    if (_c.tool == EditorTool.pan) return;
    // Click a directional arrow → EdrawMax / draw.io quick-add picker (choose
    // the next shape and auto-connect). Shift+click still clones the source.
    if (_connectAffordanceActive) {
      final affordanceId = _connectAffordanceShapeId;
      if (affordanceId != null) {
        final s = _page?.findShapeById(affordanceId);
        if (s != null && _canConnectFrom(s)) {
          final dir = _connectArrowHitDir(s, d.localPosition);
          if (dir != null) {
            // Tap won the arena — don't also fire from a pending pan release.
            _pendingQuickAdd = null;
            if (HardwareKeyboard.instance.isShiftPressed) {
              _connectInDirection(s, dir);
            } else {
              _showQuickAddFor(s, dir, d.localPosition);
            }
            return;
          }
        }
      }
    }
    if (_c.tool == EditorTool.connector || _c.tool == EditorTool.freehand) {
      return; // connectors / freehand need a drag
    }
    if (_c.tool != EditorTool.select) {
      final wasText = _c.tool == EditorTool.text;
      final p = _pageInchesAt(d.localPosition);
      _c.createShapeByDrag(p.dx, p.dy, p.dx, p.dy); // click ⇒ default size
      if (wasText) _startEditingNewTextBox();
      return;
    }
    final keyboard = HardwareKeyboard.instance;
    final alt = keyboard.isAltPressed;
    final shift = keyboard.isShiftPressed;
    final subtract = alt && shift;
    final hit0 = alt && !subtract
        ? _hitBelow(d.localPosition)
        : _hitTest(d.localPosition);
    final hit = hit0 == null ? null : _selectionAwareHit(hit0);
    final toggle =
        shift || keyboard.isControlPressed || keyboard.isMetaPressed;
    if (hit != null) {
      if (subtract) {
        if (_c.isSelected(hit)) _c.toggleSelection(hit);
      } else if (alt) {
        _c.selectOnly(hit);
      } else if (toggle) {
        _c.toggleSelection(hit);
      } else {
        _c.selectOnly(hit);
      }
    } else if (!toggle) {
      _c.clearSelection();
    }
  }

  void _onDoubleTap() {
    if (widget.presentationMode || _c.tool == EditorTool.pan) return;
    // Double-clicking a connector's bend point removes it.
    final conn = _selectedConnector();
    if (conn != null &&
        _canEditConnector(conn) &&
        conn.waypoints.isNotEmpty) {
      final route = _connectorControlRoutePage(conn);
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
    if (hit != null) {
      _beginTextEdit(hit);
    } else if (_c.tool == EditorTool.select) {
      _showQuickInsertAt(_doubleTapPos);
    }
  }

  // --- Context menu (right-click) --------------------------------------------

  void _onSecondaryTapUp(TapUpDetails d) {
    if (widget.presentationMode || _c.tool == EditorTool.pan) return;
    if (_editingShapeId != null) _commitTextEdit();
    _ensureCanvasFocus();
    final rawHit = _hitTest(d.localPosition);
    final hit = rawHit == null ? null : _selectionAwareHit(rawHit);
    if (hit != null && !_c.isSelected(hit)) _c.selectOnly(hit);
    _showContextMenu(d.globalPosition, hit, _pageInchesAt(d.localPosition));
  }

  Future<void> _showContextMenu(
      Offset globalPos, int? hit, Offset pagePos) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final el = EditorL10n.of(context);
    final items = <PopupMenuEntry<String>>[];
    int? contextConnectorId;
    int? contextAddWaypointIndex;
    int? contextRemoveWaypointIndex;
    final hitShape = hit == null ? null : _page?.findShapeById(hit);
    if (hitShape != null &&
        hitShape.isGlueableConnector &&
        _canEditConnector(hitShape)) {
      final route = _connectorControlRoutePage(hitShape);
      if (route.length >= 2) {
        contextConnectorId = hitShape.id;
        // Only explicit interior points are removable. Automatically routed
        // bends are promoted when an adjacent segment gets a new waypoint.
        if (hitShape.waypoints.isNotEmpty) {
          final hitInches =
              _handleHitPx / (_scale * widget.pxPerInch);
          final hitSquared = hitInches * hitInches;
          for (var r = 1; r < route.length - 1; r++) {
            final dx = route[r].x - pagePos.dx;
            final dy = route[r].y - pagePos.dy;
            if (dx * dx + dy * dy <= hitSquared) {
              contextRemoveWaypointIndex = r - 1;
              break;
            }
          }
        }
        if (contextRemoveWaypointIndex == null) {
          contextAddWaypointIndex =
              _nearestConnectorSegmentIndex(route, pagePos);
        }
      }
    }
    if (hit != null && _c.hasSelection) {
      items.add(PopupMenuItem(value: 'cut', child: Text(el.cut)));
      items.add(PopupMenuItem(value: 'copy', child: Text(el.copy)));
      items.add(PopupMenuItem(value: 'duplicate', child: Text(el.duplicate)));
      items.add(PopupMenuItem(value: 'paste', child: Text(el.paste)));
      items.add(PopupMenuItem(value: 'delete', child: Text(el.delete)));
      items.add(PopupMenuItem(
          value: 'lock',
          child: Text(_c.selectionLocked ? el.unlock : el.lock)));
      if (contextRemoveWaypointIndex != null) {
        items.add(PopupMenuItem(
            value: 'removeWaypoint', child: Text(el.removeWaypoint)));
      } else if (contextAddWaypointIndex != null) {
        items.add(PopupMenuItem(
            value: 'addWaypoint', child: Text(el.addWaypoint)));
      }
      if (_c.canClearWaypoints) {
        items.add(PopupMenuItem(
            value: 'clearWaypoints', child: Text(el.clearWaypoints)));
      }
      items.add(const PopupMenuDivider());
      items.add(PopupMenuItem(value: 'front', child: Text(el.bringToFront)));
      items.add(PopupMenuItem(value: 'back', child: Text(el.sendToBack)));
      items.add(PopupMenuItem(value: 'forward', child: Text(el.bringForward)));
      items.add(PopupMenuItem(value: 'backward', child: Text(el.sendBackward)));
      if (_c.canGroup ||
          _c.canUngroup ||
          _c.canRemoveSelectionFromGroup ||
          _c.canCollapseSelection ||
          _c.canExpandSelection) {
        items.add(const PopupMenuDivider());
        if (_c.canGroup) {
          items.add(PopupMenuItem(value: 'group', child: Text(el.group)));
        }
        if (_c.canUngroup) {
          items.add(PopupMenuItem(value: 'ungroup', child: Text(el.ungroup)));
        }
        if (_c.canRemoveSelectionFromGroup) {
          items.add(PopupMenuItem(
            value: 'removeFromGroup',
            child: Text(el.removeFromGroup),
          ));
        }
        if (_c.canCollapseSelection) {
          items.add(PopupMenuItem(
            value: 'collapseSelection',
            child: Text(el.collapseSelection),
          ));
        }
        if (_c.canExpandSelection) {
          items.add(PopupMenuItem(
            value: 'expandSelection',
            child: Text(el.expandSelection),
          ));
        }
      }
      items.add(const PopupMenuDivider());
      items.add(PopupMenuItem(value: 'copyStyle', child: Text(el.copyStyle)));
      if (_c.hasStyleClipboard) {
        items.add(PopupMenuItem(
            value: 'pasteStyle', child: Text(el.pasteStyle)));
      }
      items.add(const PopupMenuDivider());
      items.add(PopupMenuItem(value: 'edit', child: Text(el.editText)));
      if (_c.singleSelectedId != null) {
        items.add(PopupMenuItem(value: 'editData', child: Text(el.editData)));
        items.add(PopupMenuItem(value: 'editLink', child: Text(el.editLink)));
      }
      if (_c.canReplaceSelectedImage) {
        items.add(PopupMenuItem(
            value: 'replaceImage', child: Text(el.replaceImage)));
      }
      if (_c.editingConnectionPoints) {
        items.add(PopupMenuItem(
            value: 'doneConnPts',
            child: Text(el.doneEditingConnectionPoints)));
      } else if (_c.canEditConnectionPoints) {
        items.add(PopupMenuItem(
            value: 'editConnPts',
            child: Text(el.editConnectionPoints)));
      }
      if (_c.canAddLane || _c.canRemoveLane) {
        items.add(const PopupMenuDivider());
        if (_c.canAddLane) {
          items.add(PopupMenuItem(value: 'addLane', child: Text(el.addLane)));
        }
        if (_c.canRemoveLane) {
          items.add(PopupMenuItem(
              value: 'removeLane', child: Text(el.removeLane)));
        }
      }
      if (_c.canAddTableRow ||
          _c.canAddTableColumn ||
          _c.canRemoveTableRow ||
          _c.canRemoveTableColumn ||
          _c.canMergeCells ||
          _c.canUnmergeCell) {
        items.add(const PopupMenuDivider());
        if (_c.canAddTableRow) {
          items.add(PopupMenuItem(value: 'addRow', child: Text(el.addRow)));
        }
        if (_c.canAddTableColumn) {
          items.add(PopupMenuItem(
              value: 'addColumn', child: Text(el.addColumn)));
        }
        if (_c.canRemoveTableRow) {
          items.add(PopupMenuItem(
              value: 'removeRow', child: Text(el.deleteRow)));
        }
        if (_c.canRemoveTableColumn) {
          items.add(PopupMenuItem(
              value: 'removeColumn', child: Text(el.deleteColumn)));
        }
        if (_c.canMergeCells) {
          items.add(PopupMenuItem(
              value: 'mergeCells', child: Text(el.mergeCells)));
        }
        if (_c.canUnmergeCell) {
          items.add(PopupMenuItem(
              value: 'unmergeCells', child: Text(el.unmergeCells)));
        }
      }
    } else {
      items.add(PopupMenuItem(value: 'paste', child: Text(el.paste)));
      items.add(PopupMenuItem(value: 'pasteHere', child: Text(el.pasteHere)));
      items.add(PopupMenuItem(value: 'selectAll', child: Text(el.selectAll)));
      items.add(PopupMenuItem(
          value: 'selectEdges', child: Text(el.selectEdges)));
      items.add(PopupMenuItem(
          value: 'selectVertices', child: Text(el.selectVertices)));
      items.add(PopupMenuItem(value: 'fit', child: Text(el.fitToWindow)));
      if (_c.hasPageGuides) {
        items.add(PopupMenuItem(
            value: 'clearGuides', child: Text(el.clearGuides)));
      }
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
        unawaited(_c.pasteFromSystem());
      case 'pasteHere':
        unawaited(_c.pasteFromSystem(cx: pagePos.dx, cy: pagePos.dy));
      case 'delete':
        _c.deleteSelection();
      case 'lock':
        _c.toggleLock();
      case 'addWaypoint':
        final connectorId = contextConnectorId;
        final index = contextAddWaypointIndex;
        if (connectorId != null && index != null) {
          _addContextWaypoint(connectorId, index, pagePos);
        }
      case 'removeWaypoint':
        final connectorId = contextConnectorId;
        final index = contextRemoveWaypointIndex;
        if (connectorId != null && index != null) {
          _c.removeWaypoint(connectorId, index);
        }
      case 'clearWaypoints':
        _c.clearSelectedConnectorWaypoints();
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
      case 'removeFromGroup':
        _c.removeSelectionFromGroup();
      case 'collapseSelection':
        _c.collapseSelection();
      case 'expandSelection':
        _c.expandSelection();
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
      case 'replaceImage':
        final id = _c.singleSelectedId;
        if (id == null) break;
        final picked = await pickImageFile();
        if (picked == null || !mounted) break;
        _c.replaceImage(id, picked.bytes, fileExtension: picked.extension);
      case 'editConnPts':
        _c.beginEditConnectionPoints();
      case 'doneConnPts':
        _c.endEditConnectionPoints();
      case 'addLane':
        _c.addLaneToSelectedPool();
      case 'removeLane':
        _c.removeSelectedLane();
      case 'addRow':
        _c.addRowToSelectedTable();
      case 'addColumn':
        _c.addColumnToSelectedTable();
      case 'removeRow':
        _c.removeRowFromSelectedTable();
      case 'removeColumn':
        _c.removeColumnFromSelectedTable();
      case 'mergeCells':
        _c.mergeSelectedCells();
      case 'unmergeCells':
        _c.unmergeSelectedCell();
      case 'selectAll':
        _c.selectAll();
      case 'selectEdges':
        _c.selectConnectors();
      case 'selectVertices':
        _c.selectVertices();
      case 'fit':
        fitToScreen();
      case 'clearGuides':
        _c.clearPageGuides();
    }
  }

  static int _nearestConnectorSegmentIndex(
    List<Offset2D> route,
    Offset point,
  ) {
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < route.length - 1; i++) {
      final a = route[i];
      final b = route[i + 1];
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final lengthSquared = dx * dx + dy * dy;
      final projection = lengthSquared <= 1e-12
          ? 0.0
          : (((point.dx - a.x) * dx + (point.dy - a.y) * dy) /
                  lengthSquared)
              .clamp(0.0, 1.0);
      final px = a.x + dx * projection;
      final py = a.y + dy * projection;
      final ex = point.dx - px;
      final ey = point.dy - py;
      final distance = ex * ex + ey * ey;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  /// Add a waypoint at a connector context-menu position. If the connector is
  /// using an automatically generated elbow, promote those bends first so the
  /// new point edits the visible route. Everything is one undo step.
  void _addContextWaypoint(int connectorId, int segmentIndex, Offset pagePos) {
    final page = _page;
    final connector = page?.findShapeById(connectorId);
    if (page == null ||
        connector == null ||
        !_canEditConnector(connector)) {
      return;
    }
    final route = _connectorControlRoutePage(connector);
    if (route.length < 2) return;
    _c.beginTransaction();
    if (connector.waypoints.isEmpty && route.length > 2) {
      final parentId = page.findParentId(connectorId);
      final promoted = <Offset2D>[
        for (final point in route.sublist(1, route.length - 1))
          parentId == null
              ? point
              : page.pageToLocalDeep(parentId, point),
      ];
      _c.setConnectorWaypoints(
        connectorId,
        promoted,
        transient: true,
      );
    }
    _c.addWaypoint(
      connectorId,
      segmentIndex,
      Offset2D(pagePos.dx, pagePos.dy),
      transient: true,
    );
    _c.commitTransaction();
  }

  // --- In-place text editing -------------------------------------------------

  /// Enter inline edit mode for shape [id]: select it, seed the field with its
  /// current label (all selected) and focus the overlaid editor.
  void _beginTextEdit(int id, {String? replacement}) {
    final s = _page?.findShapeById(id);
    if (s == null || s.locked || _c.isOnLockedLayer(id)) {
      return; // locked shapes / layers can't be text-edited
    }
    _newTextBoxId = null; // editing an existing shape, not a fresh text box
    _c.selectOnly(id);
    final initial =
        replacement ??
        (s.richText.runs.isNotEmpty ? s.richText.plainText : (s.text ?? ''));
    _textController.value = TextEditingValue(
      text: initial,
      selection: replacement == null
          ? TextSelection(baseOffset: 0, extentOffset: initial.length)
          : TextSelection.collapsed(offset: initial.length),
    );
    setState(() => _editingShapeId = id);
    _syncTextEditSession();
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
    _c.setTextEditSession();
    if (_textFocus.hasFocus) _textFocus.unfocus();
    // An untyped Text-tool box is discarded rather than left invisible.
    if (wasNewBox && text.trim().isEmpty) {
      _c.discardAbandonedShape(id);
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
    _c.setTextEditSession();
    if (_textFocus.hasFocus) _textFocus.unfocus();
    if (wasNewBox) _c.discardAbandonedShape(id);
  }

  void _insertTextEditLineBreak() {
    final value = _textController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final a = math.min(start, end).clamp(0, value.text.length);
    final b = math.max(start, end).clamp(0, value.text.length);
    final text = value.text.replaceRange(a, b, '\n');
    _textController.value = value.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: a + 1),
      composing: TextRange.empty,
    );
  }

  /// The overlaid text editor for the shape being edited, positioned over its
  /// box in screen space (`null` when not editing). Enter applies,
  /// Shift/Alt+Enter inserts a newline, and Esc cancels.
  ///
  /// When the shape has rich-text runs, a [Text.rich] preview mirrors bold /
  /// colour / size per run under a near-transparent [TextField] so typing and
  /// selection still work (draw.io-style mixed-style editing feedback).
  Widget? _buildInlineEditor(BuildContext context) {
    final id = _editingShapeId;
    final s = id == null ? null : _page?.findShapeById(id);
    if (s == null) return null;
    final run = s.richText.runs.isNotEmpty ? s.richText.runs.first : null;
    final cs = run?.charStyle ?? VsdxCharStyle.defaults;
    final fontPx = math.max(cs.fontSizeInches * widget.pxPerInch * _scale, 8.0);
    final align = run?.paraStyle.horizontalAlign ?? VsdxHorzAlign.center;
    final vAlign = s.richText.textBlock.verticalAlign;
    final previewAlign = switch (vAlign) {
      VsdxVertAlign.top => Alignment.topCenter,
      VsdxVertAlign.bottom => Alignment.bottomCenter,
      VsdxVertAlign.middle => Alignment.center,
    };
    final textAlignVertical = switch (vAlign) {
      VsdxVertAlign.top => TextAlignVertical.top,
      VsdxVertAlign.bottom => TextAlignVertical.bottom,
      VsdxVertAlign.middle => TextAlignVertical.center,
    };
    final scheme = Theme.of(context).colorScheme;
    final docTheme = _c.documentTheme.isEmpty
        ? VsdxTheme.office
        : _c.documentTheme;
    final preview = s.richText.runs.isEmpty
        ? null
        : replacePlainText(s.richText, _textController.text);

    final double left, top, width, height;
    var pageAngle = 0.0;
    var locAlignX = 0.0;
    var locAlignY = 0.0;
    // When the editor is placed via localToPageDeep(TxtPin), flip is already
    // in the page pin — applying Transform flip again would double-flip.
    var applyShapeFlip = true;
    if (s.isGlueableConnector) {
      // Edge label: a compact editor centred on its yellow-diamond anchor
      // (route midpoint until the label has been moved).
      final label = _connectorLabelPage(s);
      final screen = _pageToScreen(label.x, label.y);
      width = 140.0;
      height = math.max(fontPx + 14, 30.0);
      left = screen.dx - width / 2;
      top = screen.dy - height / 2;
    } else {
      // Prefer the text-block box (TxtPin/TxtWidth) so captions below icons
      // edit where they paint — not the picture Width×Height frame.
      final ppi = widget.pxPerInch;
      final block = s.richText.textBlock;
      final useTextBlock = block.pinXInches != null ||
          block.pinYInches != null ||
          block.widthInches != null ||
          block.heightInches != null;
      final boxW = useTextBlock ? (block.widthInches ?? s.width) : s.width;
      final boxH = useTextBlock ? (block.heightInches ?? s.height) : s.height;
      final pinLocalX =
          useTextBlock ? (block.pinXInches ?? s.width / 2) : s.effectiveLocPinX;
      final pinLocalY = useTextBlock
          ? (block.pinYInches ?? s.height / 2)
          : s.effectiveLocPinY;
      final locPinXIn = useTextBlock
          ? (block.locPinXInches ?? boxW / 2)
          : s.effectiveLocPinX;
      final locPinYIn = useTextBlock
          ? (block.locPinYInches ?? boxH / 2)
          : s.effectiveLocPinY;
      width = math.max(boxW * ppi * _scale, 44.0);
      height = math.max(boxH * ppi * _scale, 26.0);
      final pinPage = useTextBlock
          ? _page!.localToPageDeep(s.id, Offset2D(pinLocalX, pinLocalY))
          : _page!.shapePinPage(s.id);
      final pinScr = _pageToScreen(pinPage.x, pinPage.y);
      pageAngle = _page!.shapePageAngle(s.id) +
          (useTextBlock ? block.angleRad : 0.0);
      final locPinX = locPinXIn * ppi * _scale;
      final locPinYFromTop = (boxH - locPinYIn) * ppi * _scale;
      left = pinScr.dx - locPinX;
      top = pinScr.dy - locPinYFromTop;
      locAlignX = width <= 0 ? 0.0 : (locPinX / width) * 2 - 1;
      locAlignY = height <= 0 ? 0.0 : (locPinYFromTop / height) * 2 - 1;
      applyShapeFlip = !useTextBlock;
    }
    Widget editor = CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _cancelTextEdit,
        // draw.io: Enter saves; Shift+Enter / Alt+Enter inserts a line break.
        const SingleActivator(LogicalKeyboardKey.enter): _commitTextEdit,
        const SingleActivator(LogicalKeyboardKey.enter, shift: true):
            _insertTextEditLineBreak,
        const SingleActivator(LogicalKeyboardKey.enter, alt: true):
            _insertTextEditLineBreak,
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (preview != null)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: IgnorePointer(
                    // Match [TextField] layout: full-width box + same
                    // textAlign so the invisible field's caret/selection
                    // land on the visible glyphs (not left-side empty
                    // space while a centred preview is shown).
                    child: SizedBox(
                      width: math.max(width - 8, 1),
                      height: math.max(height - 4, 1),
                      child: Align(
                        alignment: previewAlign,
                        child: SizedBox(
                          width: math.max(width - 8, 1),
                          child: Text.rich(
                            TextSpan(
                              children: <InlineSpan>[
                                for (final r in preview.runs)
                                  _inlineRunSpan(
                                    r,
                                    widget.pxPerInch * _scale,
                                    docTheme,
                                    scheme.onSurface,
                                  ),
                              ],
                            ),
                            textAlign: _textAlign(align),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              TextField(
                controller: _textController,
                focusNode: _textFocus,
                maxLines: null,
                expands: true,
                textAlign: _textAlign(align),
                textAlignVertical: textAlignVertical,
                cursorColor: scheme.primary,
                style: TextStyle(
                  fontSize: fontPx,
                  height: 1.15,
                  // Hide glyphs when a rich preview is shown; keep a tiny
                  // alpha so caret / selection metrics stay stable.
                  color: preview != null
                      ? const Color(0x01FFFFFF)
                      : scheme.onSurface,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Boxes and freehand ink: match paint flip/rotate about LocPin.
    // Glueable connectors keep an axis-aligned edge-label editor.
    // Text-block placement already includes Flip via localToPageDeep — skip
    // a second Transform flip (would misplace icon captions under FlipY).
    if (!s.isGlueableConnector) {
      final sx = applyShapeFlip && s.flipX ? -1.0 : 1.0;
      final sy = applyShapeFlip && s.flipY ? -1.0 : 1.0;
      final align = Alignment(locAlignX, locAlignY);
      if (sx != 1.0 || sy != 1.0) {
        editor = Transform(
          alignment: align,
          transform: Matrix4.diagonal3Values(sx, sy, 1),
          child: editor,
        );
      }
      if (pageAngle.abs() > 1e-9) {
        // Visio CCW / Y-up → Flutter CW / Y-down.
        editor = Transform.rotate(
          angle: -pageAngle,
          alignment: align,
          child: editor,
        );
      }
    }
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: editor,
    );
  }

  /// One styled span for the inline rich-text preview (mirrors painter rules
  /// for bold / italic / underline / colour / size).
  static TextSpan _inlineRunSpan(
    VsdxTextRun run,
    double pxPerInch,
    VsdxTheme theme,
    Color fallback,
  ) {
    final cs = run.charStyle;
    final themeColor = cs.themeColorIndex == null
        ? null
        : theme.resolve(cs.themeColorIndex!);
    final color = cs.color != null
        ? Color(cs.color!.value)
        : (themeColor != null ? Color(themeColor.value) : fallback);
    final size = math.max(cs.fontSizeInches * pxPerInch, 8.0);
    return TextSpan(
      text: run.text,
      style: TextStyle(
        color: color,
        fontSize: size,
        height: 1.15,
        fontWeight: cs.style.bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: cs.style.italic ? FontStyle.italic : FontStyle.normal,
        decoration: TextDecoration.combine([
          if (cs.underline) TextDecoration.underline,
          if (cs.strikethrough) TextDecoration.lineThrough,
        ]),
        fontFamily: cs.fontFamily,
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
    // Two-finger pinch (view-only) owns the gesture.
    if (_pinchActive) {
      _mode = _DragMode.none;
      return;
    }
    _ensureCanvasFocus();
    if (_viewOnlyGestures) {
      // View-only: drag pans the canvas; editing gestures are disabled.
      // (Pinch-zoom uses [_onCanvasPointer*] when those handlers are wired.)
      _lastPointer = d.localPosition;
      _mode = _DragMode.panCanvas;
      return;
    }
    _lastPointer = d.localPosition;
    // Space always owns the drag, even when it starts over a selected shape,
    // resize handle or non-select tool (draw.io temporary hand tool).
    if (HardwareKeyboard.instance.logicalKeysPressed
        .contains(LogicalKeyboardKey.space)) {
      _mode = _DragMode.panCanvas;
      return;
    }
    if (_c.editingConnectionPoints) {
      _onConnPointEditPanStart(d.localPosition);
      return;
    }
    if (_c.tool == EditorTool.freehand) {
      _mode = _DragMode.createShape;
      final p = _viewportToContent(d.localPosition);
      setState(() {
        _freehandPoints
          ..clear()
          ..add(p);
        _previewStart = p;
        _previewEnd = p;
      });
      return;
    }
    if (_c.tool != EditorTool.select) {
      _mode = _DragMode.createShape;
      if (_c.tool == EditorTool.connector) {
        // Capture the begin glue point at press (deepest 2-D, matches drop).
        final beginId = _connectorTargetAt(d.localPosition);
        final beginShape =
            beginId == null ? null : _page?.findShapeById(beginId);
        _connectSourceConnIndex =
            (beginShape != null && _canConnectFrom(beginShape))
                ? _connectorSnapIndex(beginShape, d.localPosition)
                : null;
        _connectSourceFixedAtPosition =
            beginId != null && _customFixedConnectorDrop;
        _connectTargetFixedAtPosition = false;
        setState(() {
          _previewStart = _previewEndForSnap(
            beginShape,
            _connectSourceConnIndex,
            _viewportToContent(d.localPosition),
          );
          _previewEnd = _previewStart;
          _connectTargetId = beginId;
          _snapConnIndex = _connectSourceConnIndex;
        });
      } else {
        _connectSourceConnIndex = null;
        _connectSourceFixedAtPosition = false;
        _connectTargetFixedAtPosition = false;
        setState(() {
          _previewStart = _viewportToContent(d.localPosition);
          _previewEnd = _previewStart;
        });
      }
      return;
    }
    // Alt forces a selection box even when the drag starts over a shape.
    // Together with Shift this is draw.io's subtract-from-selection gesture.
    // Blank-canvas Alt+Shift remains the remote-move gesture below.
    final altShiftMarquee = HardwareKeyboard.instance.isAltPressed &&
        HardwareKeyboard.instance.isShiftPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed;
    if (altShiftMarquee && _hitTest(d.localPosition) != null) {
      _mode = _DragMode.marquee;
      setState(() {
        _marqueeStart = _viewportToContent(d.localPosition);
        _marqueeEnd = _marqueeStart;
      });
      return;
    }
    // Rotate handle before quick-add arrows: on touch both sit above the
    // selected shape and the north arrow would otherwise steal the knob.
    final rotatable = _rotatableSelection();
    if (rotatable != null) {
      final (_, knob) = _rotateAnchors(rotatable);
      final hit = _handleHitPx * _handleHitPx;
      if ((_offset + knob * _scale - d.localPosition).distanceSquared <= hit) {
        _resizeShapeId = rotatable.id;
        _mode = _DragMode.rotate;
        _c.beginTransaction();
        return;
      }
    }
    // Connect affordances: arrows → quick-add (click) or connector drag; blue
    // CPs / perimeter → drag out a connector glued to the shape. On touch the
    // arrows sit on the selected shape (no hover), so hit-test that too.
    final affordanceId = _connectAffordanceShapeId;
    if (affordanceId != null) {
      final s = _page?.findShapeById(affordanceId);
      if (s != null && _canConnectFrom(s)) {
        // Remember the press so a click opens the picker, while movement can
        // transition into a fixed directional connector drag.
        final arrowDir = _connectArrowHitDir(s, d.localPosition);
        if (arrowDir != null) {
          _pendingQuickAdd =
              (id: s.id, dir: arrowDir, start: d.localPosition);
          return;
        }
        if (_resizableSelection()?.id != s.id) {
          final cpIndex = _connDragSourceIndex(s, d.localPosition);
          if (cpIndex != null) {
            final pts = VsdxPage.effectiveConnectionPoints(s);
            final pg = _connPointPage(s, pts[cpIndex].offset);
            _connectSourceId = affordanceId;
            _connectSourceConnIndex = cpIndex;
            _connectSourceFixedAtPosition = false;
            _connectTargetFixedAtPosition = false;
            _connectArrowDirection = null;
            _connectTargetId = null;
            _mode = _DragMode.connect;
            setState(() {
              _previewStart = _pageToContent(pg.x, pg.y);
              _previewEnd = _viewportToContent(d.localPosition);
            });
            return;
          }
          final peri = _nearestPerimeterPage(s, d.localPosition);
          if (peri != null) {
            _connectSourceId = affordanceId;
            _connectSourceConnIndex = null;
            _connectSourceFixedAtPosition = false;
            _connectTargetFixedAtPosition = false;
            _connectArrowDirection = null;
            _connectTargetId = null;
            _mode = _DragMode.connect;
            setState(() {
              _previewStart = _pageToContent(peri.x, peri.y);
              _previewEnd = _viewportToContent(d.localPosition);
            });
            return;
          }
        }
      }
    }

    // Resize handles take priority over move/pan when one shape is selected,
    // but only near the edge — on touch the larger hit radius would otherwise
    // swallow drags that start in the middle of a small on-screen shape.
    final resizable = _resizableSelection();
    if (resizable != null && !_pointerInsideShapeBody(resizable, d.localPosition)) {
      final handles = _handleScreens(_exactContentBox(resizable));
      final hit = _handleHitPx * _handleHitPx;
      for (final entry in handles.entries) {
        if ((entry.value - d.localPosition).distanceSquared <= hit) {
          _activeHandle = entry.key;
          _resizeShapeId = resizable.id;
          _resizeStartShape = resizable;
          _mode = _DragMode.resize;
          _c.beginTransaction();
          return;
        }
      }
    }

    // Table column / row dividers (when a table or cell is selected).
    if (_tryStartTableDividerDrag(d.localPosition)) return;

    // Connector endpoint handles (reconnect / detach) then bend points take
    // priority over hit-testing (they sit on top of the connector).
    if (_tryToggleCollapse(d.localPosition)) return;
    if (_tryStartConnectorLabelRotate(d.localPosition)) return;
    if (_tryStartConnectorLabelDrag(d.localPosition)) return;
    if (_tryStartEndpointDrag(d.localPosition)) return;
    if (_tryStartWaypointDrag(d.localPosition)) return;

    final hit0 = _hitTest(d.localPosition);
    final hit = hit0 == null ? null : _selectionAwareHit(hit0);
    if (hit != null) {
      if (!_c.isSelected(hit)) _c.selectOnly(hit);
      // Ctrl/Cmd-drag leaves the originals behind and drags a copy (draw.io).
      if (_cloneDrag) _c.duplicateSelection();
      _mode = _DragMode.moveShapes;
      _c.beginTransaction();
      _moveAccumInches = Offset.zero;
      _moveAppliedInches = Offset.zero;
      _remoteMove = false;
      _moveStartBounds = _selectionUnionInches();
    } else if (_isTouchUi) {
      // Touch: empty-canvas drag pans. Holding still ~400ms converts to
      // marquee (see [_onPanUpdate]) so multi-select stays available.
      _mode = _DragMode.panCanvas;
      _emptyTouchPanAt = DateTime.now();
      _emptyTouchPanOrigin = d.localPosition;
      _emptyTouchPanAccum = Offset.zero;
    } else {
      final alt = HardwareKeyboard.instance.isAltPressed;
      final shift = HardwareKeyboard.instance.isShiftPressed;
      final command = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      if (alt && shift && command) {
        _mode = _DragMode.moveArea;
        _areaOriginPage = _pageInchesAt(d.localPosition);
        _areaAppliedPage = Offset.zero;
        _areaHorizontalIds = null;
        _areaVerticalIds = null;
        _c.beginTransaction();
        setState(() {
          _areaStartContent = _viewportToContent(d.localPosition);
          _areaEndContent = _areaStartContent;
        });
      } else if (alt && shift && _c.hasSelection) {
        // Move a selected shape from anywhere on blank canvas (draw.io remote
        // move). Alt also gives the expected smooth, unsnapped movement.
        _mode = _DragMode.moveShapes;
        _c.beginTransaction();
        _c.detachSelectionConnectorsFromStationaryShapes(transient: true);
        _moveAccumInches = Offset.zero;
        _moveAppliedInches = Offset.zero;
        _remoteMove = true;
        _moveStartBounds = _selectionUnionInches();
      } else {
        _mode = _DragMode.marquee;
        setState(() {
          _marqueeStart = _viewportToContent(d.localPosition);
          _marqueeEnd = _marqueeStart;
        });
      }
    }
  }

  /// Whether [viewportPos] sits inside [s]'s box, inset by the handle hit
  /// radius — used so touch-sized resize targets don't steal body drags.
  bool _pointerInsideShapeBody(VsdxShape s, Offset viewportPos) {
    final box = _normaliseRect(_exactContentBox(s));
    final screen = Rect.fromLTRB(
      _offset.dx + box.left * _scale,
      _offset.dy + box.top * _scale,
      _offset.dx + box.right * _scale,
      _offset.dy + box.bottom * _scale,
    );
    final inset = screen.deflate(_handleHitPx);
    if (inset.width <= 0 || inset.height <= 0) {
      // Tiny on-screen shape: treat the centre third as the body.
      return screen.deflate(screen.shortestSide / 3).contains(viewportPos);
    }
    return inset.contains(viewportPos);
  }

  /// Connection-point edit mode: drag existing points, or click the shape to
  /// add a new one (draw.io Edit Connection Points).
  void _onConnPointEditPanStart(Offset localPos) {
    final id = _c.singleSelectedId;
    final s = id == null ? null : _page?.findShapeById(id);
    if (s == null || s.is1D) {
      _mode = _DragMode.none;
      return;
    }
    final hit = _connPointHitIndex(s, localPos);
    if (hit != null) {
      _connPointDragIndex = hit;
      _c.selectConnectionPoint(hit);
      _mode = _DragMode.moveConnectionPoint;
      _c.beginTransaction();
      return;
    }
    if (_hitTest(localPos) == id) {
      final pagePos = _pageInchesAt(localPos);
      final local =
          _page!.pageToLocalDeep(s.id, Offset2D(pagePos.dx, pagePos.dy));
      _c.addConnectionPointAtLocal(local.x, local.y);
    }
    _mode = _DragMode.none;
  }

  /// Index of the connection point under [localPos], or `null`.
  int? _connPointHitIndex(VsdxShape s, Offset localPos) {
    final pts = VsdxPage.effectiveConnectionPoints(s);
    final hit = _handleHitPx * _handleHitPx;
    for (var i = 0; i < pts.length; i++) {
      final pg = _connPointPage(s, pts[i].offset);
      final screen = _offset + _pageToContent(pg.x, pg.y) * _scale;
      if ((screen - localPos).distanceSquared <= hit) return i;
    }
    return null;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_pinchActive) return;
    final pos = d.localPosition;
    // A directional-arrow click opens quick-add; once the pointer clearly
    // moves, turn it into a connector drag. Ctrl/Cmd at release clones the
    // source at the free drop point and connects it (draw.io).
    final pending = _pendingQuickAdd;
    if (pending != null &&
        (pos - pending.start).distance > (_isTouchUi ? 16 : 8)) {
      _pendingQuickAdd = null;
      _beginDirectionalArrowDrag(pending, pos);
    }
    switch (_mode) {
      case _DragMode.moveConnectionPoint:
        final id = _c.singleSelectedId;
        final idx = _connPointDragIndex;
        final s = id == null ? null : _page?.findShapeById(id);
        if (id != null && idx != null && s != null) {
          final pagePos = _pageInchesAt(pos);
          final local =
              _page!.pageToLocalDeep(s.id, Offset2D(pagePos.dx, pagePos.dy));
          _c.moveConnectionPointAtLocal(idx, local.x, local.y,
              transient: true);
        }
      case _DragMode.moveShapes:
        _applyMove((pos - _lastPointer) / _scale);
        final pagePt = _contentToPageInches(_viewportToContent(pos));
        final drop = _bypassSnapping
            ? null
            : _page?.findDropContainerAt(
                pagePt.dx,
                pagePt.dy,
                excludeIds: Set<int>.of(_c.selection),
              );
        if (drop != _dropContainerId) {
          setState(() => _dropContainerId = drop);
        }
      case _DragMode.panCanvas:
        final delta = pos - _lastPointer;
        // Touch empty-canvas: hold still briefly → marquee multi-select.
        if (_emptyTouchPanAt != null && _emptyTouchPanOrigin != null) {
          _emptyTouchPanAccum += delta;
          final held = DateTime.now().difference(_emptyTouchPanAt!);
          if (_emptyTouchPanAccum.distance >= 14) {
            // Confirmed pan — stop watching for marquee conversion.
            _emptyTouchPanAt = null;
            _emptyTouchPanOrigin = null;
          } else if (held >= const Duration(milliseconds: 400)) {
            final origin = _emptyTouchPanOrigin!;
            final undo = _emptyTouchPanAccum;
            _emptyTouchPanAt = null;
            _emptyTouchPanOrigin = null;
            _emptyTouchPanAccum = Offset.zero;
            setState(() {
              _offset -= undo;
              _mode = _DragMode.marquee;
              _marqueeStart = _viewportToContent(origin);
              _marqueeEnd = _viewportToContent(pos);
            });
            _lastPointer = pos;
            return;
          }
        }
        setState(() => _offset += delta);
      case _DragMode.createShape:
        if (_c.tool == EditorTool.freehand) {
          final p = _viewportToContent(pos);
          // Sample in content-px (~3 device px at current zoom) for smooth ink.
          final minPx = 3.0 / _scale;
          final last = _freehandPoints.isEmpty ? null : _freehandPoints.last;
          if (last == null || (p - last).distance >= minPx) {
            setState(() {
              _freehandPoints.add(p);
              _previewEnd = p;
            });
          } else {
            setState(() => _previewEnd = p);
          }
          break;
        }
        final connTarget = _c.tool == EditorTool.connector
            ? _connectorTargetAt(pos)
            : null;
        final connTs =
            connTarget == null ? null : _page?.findShapeById(connTarget);
        final snap =
            connTs != null ? _connectorSnapIndex(connTs, pos) : null;
        setState(() {
          _previewEnd = _previewEndForSnap(
            connTs,
            snap,
            _viewportToContent(pos),
          );
          // Highlight the shape the connector would glue to on drop, snapping
          // its end to a fixed connection point when the pointer is near one.
          _connectTargetId = connTarget;
          _snapConnIndex = snap;
          _connectTargetFixedAtPosition =
              connTarget != null && _customFixedConnectorDrop;
        });
      case _DragMode.connect:
        final src = _connectSourceId;
        final target = _connectorTargetAt(pos, excludeId: src);
        final ts = target == null ? null : _page?.findShapeById(target);
        final snap = ts != null ? _connectorSnapIndex(ts, pos) : null;
        setState(() {
          _previewEnd = _previewEndForSnap(
            ts,
            snap,
            _viewportToContent(pos),
          );
          _connectTargetId = target;
          _snapConnIndex = snap;
          _connectTargetFixedAtPosition =
              target != null && _customFixedConnectorDrop;
        });
      case _DragMode.resize:
        _applyResize(pos);
      case _DragMode.tableColResize:
        _applyTableColResize(pos);
      case _DragMode.tableRowResize:
        _applyTableRowResize(pos);
      case _DragMode.marquee:
        setState(() => _marqueeEnd = _viewportToContent(pos));
      case _DragMode.moveArea:
        _applyAreaMove(pos);
      case _DragMode.moveWaypoint:
        final id = _waypointConnId;
        final idx = _waypointIndex;
        if (id != null && idx != null) {
          final p = _pageInchesAt(pos);
          final point = _bypassSnapping
              ? Offset2D(p.dx, p.dy)
              : Offset2D(_c.snap(p.dx), _c.snap(p.dy));
          _c.moveWaypoint(
            id,
            idx,
            point,
            transient: true,
          );
        }
      case _DragMode.moveConnectorLabel:
        final id = _connectorLabelId;
        if (id != null) {
          final p = _pageInchesAt(pos);
          _c.moveConnectorLabel(
            id,
            p.dx,
            p.dy,
            transient: true,
          );
        }
      case _DragMode.rotateConnectorLabel:
        final id = _connectorLabelId;
        if (id != null) {
          final p = _pageInchesAt(pos);
          _c.rotateConnectorLabelToward(
            id,
            p.dx,
            p.dy,
            snapTo15Degrees: HardwareKeyboard.instance.isShiftPressed,
            transient: true,
          );
        }
      case _DragMode.moveEndpoint:
        final id = _endpointConnId;
        if (id != null) {
          final p = _pageInchesAt(pos);
          final target = _connectorTargetAt(pos, excludeId: id);
          final ts = target == null ? null : _page?.findShapeById(target);
          final snap =
              ts == null ? null : _connectorSnapIndex(ts, pos);
          var x = _bypassSnapping ? p.dx : _c.snap(p.dx);
          var y = _bypassSnapping ? p.dy : _c.snap(p.dy);
          if (ts != null && snap != null) {
            final pts = VsdxPage.effectiveConnectionPoints(ts);
            if (snap >= 0 && snap < pts.length) {
              final pg = _connPointPage(ts, pts[snap].offset);
              x = pg.x;
              y = pg.y;
            }
          }
          setState(() {
            _connectTargetId = target;
            _snapConnIndex = snap;
            _connectTargetFixedAtPosition =
                target != null && _customFixedConnectorDrop;
          });
          _c.reconnectEndpoint(
            id,
            begin: _endpointIsBegin,
            // Keep an Alt/Option drag visually under the pointer; the custom
            // point and fixed glue are created once on release.
            targetShapeId:
                _customFixedConnectorDrop ? null : target,
            connectionPointIndex: snap,
            x: x,
            y: y,
            transient: true,
          );
        }
      case _DragMode.rotate:
        final id = _resizeShapeId;
        final page = _page;
        final s = id == null ? null : page?.findShapeById(id);
        if (s != null && page != null) {
          final p = _pageInchesAt(pos);
          final pin = page.shapePinPage(s.id);
          // Pointer gives a page-space heading; angleRad is parent-relative.
          final pageAngle = math.atan2(-(p.dx - pin.x), p.dy - pin.y);
          final tipPage = Offset2D(
            pin.x - math.sin(pageAngle),
            pin.y + math.cos(pageAngle),
          );
          final parentId = page.findParentId(s.id);
          double localAngle;
          if (parentId == null) {
            localAngle = pageAngle;
          } else {
            final tipLocal = page.pageToLocalDeep(parentId, tipPage);
            final pinLocal = page.pageToLocalDeep(parentId, pin);
            localAngle = math.atan2(
              -(tipLocal.x - pinLocal.x),
              tipLocal.y - pinLocal.y,
            );
          }
          // Match [EditorController.setSelectedAngleDegrees]: flipY adds π.
          if (s.flipY) localAngle -= math.pi;
          _c.rotateShape(id!, localAngle, transient: true);
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
    final page = _page;
    if (id == null || handle == null || s0 == null || page == null) return;
    final p = _pageInchesAt(pos);
    final px = _bypassSnapping ? p.dx : _c.snap(p.dx);
    final py = _bypassSnapping ? p.dy : _c.snap(p.dy);
    // Start from the page-space AABB so nested Group children resize correctly.
    final aabb0 = page.shapePageAabb(s0.id);
    final cx = aabb0 != null
        ? (aabb0.left + aabb0.right) / 2
        : s0.pinX;
    final cy = aabb0 != null
        ? (aabb0.bottom + aabb0.top) / 2
        : s0.pinY;
    var l = aabb0?.left ?? (s0.pinX - s0.width / 2);
    var r = aabb0?.right ?? (s0.pinX + s0.width / 2);
    var b = aabb0?.bottom ?? (s0.pinY - s0.height / 2);
    var t = aabb0?.top ?? (s0.pinY + s0.height / 2);

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

    // Alt / Option resizes symmetrically and bypasses grid snapping.
    final centered = _bypassSnapping;
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
        // Anchor the corner opposite the one being dragged (page space).
        final fixedX = movesL ? (aabb0?.right ?? (s0.pinX + s0.width / 2))
            : (aabb0?.left ?? (s0.pinX - s0.width / 2));
        final fixedY = movesB ? (aabb0?.top ?? (s0.pinY + s0.height / 2))
            : (aabb0?.bottom ?? (s0.pinY - s0.height / 2));
        nl = movesL ? fixedX - w : fixedX;
        nr = movesL ? fixedX : fixedX + w;
        nb = movesB ? fixedY - h : fixedY;
        nt = movesB ? fixedY : fixedY + h;
      }
    }

    // Keep LocPin-relative Pin (not AABB centre) — non-centre LocPin shapes
    // would jump if we wrote the box midpoint as Pin. Match Arrange
    // [setSelectedWidth]: resize about current Pin, then nudge AABB.
    final newW = math.max(nr - nl, 0.05);
    final newH = math.max(nt - nb, 0.05);
    _c.resizeShape(
      id,
      pinX: s0.pinX,
      pinY: s0.pinY,
      width: newW,
      height: newH,
      transient: true,
      // draw.io Ctrl/Cmd-resize changes only a normal group's outer boundary;
      // structured containers keep their lane/table reflow semantics.
      resizeChildren: !(_cloneDrag &&
          s0.shapeKind == VsdxShapeKind.group &&
          !SwimlaneOps.isPool(s0) &&
          !TableOps.isTable(s0)),
    );
    final after = _c.currentPage?.shapePageAabb(id);
    if (after != null) {
      final dx = nl - after.left;
      final dy = nb - after.bottom;
      if (dx.abs() > 1e-9 || dy.abs() > 1e-9) {
        _c.moveSelectionBy(dx, dy, transient: true);
      }
    }
  }

  // --- Smart alignment guides (drawio-style) ---------------------------------

  /// Union AABB of the current selection in page inches (Y-up), or null.
  ({double l, double b, double r, double t})? _selectionUnionInches() {
    final page = _page;
    if (page == null) return null;
    double? l, b, r, t;
    for (final id in _c.selection) {
      final aabb = page.shapePageAabb(id);
      if (aabb == null) continue;
      l = l == null ? aabb.left : math.min(l, aabb.left);
      r = r == null ? aabb.right : math.max(r, aabb.right);
      b = b == null ? aabb.bottom : math.min(b, aabb.bottom);
      t = t == null ? aabb.top : math.max(t, aabb.top);
    }
    if (l == null) return null;
    return (l: l, b: b!, r: r!, t: t!);
  }

  /// Selection ids plus every descendant — excluded from snap targets so a
  /// moved group does not magnetize to its own children.
  Set<int> _snapBlockedIds() {
    final page = _page;
    if (page == null) return Set<int>.of(_c.selection);
    final blocked = <int>{};
    void walk(VsdxShape s) {
      blocked.add(s.id);
      for (final c in s.children) {
        walk(c);
      }
    }

    for (final id in _c.selection) {
      final s = page.findShapeById(id);
      if (s != null) walk(s);
    }
    return blocked;
  }

  /// AABBs (page inches) of non-selected visible 2-D shapes (nested included).
  List<SnapBox> _otherShapeBoxes() {
    final page = _page;
    if (page == null) return const <SnapBox>[];
    final blocked = _snapBlockedIds();
    final out = <SnapBox>[];
    void walk(VsdxShape s) {
      // Match paint / hit-test: skip hidden-layer hosts and folded children.
      if (!page.isShapeVisible(s)) return;
      if (!blocked.contains(s.id) && !s.is1D) {
        final aabb = page.shapePageAabb(s.id);
        if (aabb != null) {
          out.add(SnapBox(aabb.left, aabb.bottom, aabb.right, aabb.top));
        }
      }
      if (s.collapsed) return;
      for (final c in s.children) {
        walk(c);
      }
    }

    for (final s in page.shapes) {
      walk(s);
    }
    return out;
  }

  /// Connection-point magnets on non-selected shapes (page inches).
  ///
  /// 2-D shapes contribute their effective (blue) connection points; glueable
  /// connectors contribute begin/end so moving boxes can H/V-align to a line.
  List<SnapMagnet> _otherConnectionMagnets() {
    final page = _page;
    if (page == null) return const <SnapMagnet>[];
    final blocked = _snapBlockedIds();
    final out = <SnapMagnet>[];
    void walk(VsdxShape s) {
      if (!page.isShapeVisible(s)) return;
      if (!blocked.contains(s.id)) {
        if (s.isGlueableConnector) {
          final route = _connectorRoutePage(s);
          if (route.isNotEmpty) {
            out.add(SnapMagnet(route.first.x, route.first.y));
            if (route.length > 1) {
              out.add(SnapMagnet(route.last.x, route.last.y));
            }
          }
        } else if (!s.is1D) {
          final pts = VsdxPage.effectiveConnectionPoints(s);
          for (final p in pts) {
            final pg = page.localToPageDeep(s.id, p.offset);
            out.add(SnapMagnet(pg.x, pg.y));
          }
        }
      }
      if (s.collapsed) return;
      for (final c in s.children) {
        walk(c);
      }
    }

    for (final s in page.shapes) {
      walk(s);
    }
    return out;
  }

  /// Apply a raw pointer delta (content px) to the moving selection, snapping to
  /// neighbour edges/centres / connection points and updating guide lines.
  void _applyMove(Offset deltaContentPx) {
    final ppi = widget.pxPerInch;
    _moveAccumInches += Offset(deltaContentPx.dx / ppi, -deltaContentPx.dy / ppi);

    // Holding Shift constrains movement to the dominant axis (drawio parity).
    var eff = _moveAccumInches;
    if (HardwareKeyboard.instance.isShiftPressed && !_remoteMove) {
      eff = eff.dx.abs() >= eff.dy.abs()
          ? Offset(eff.dx, 0)
          : Offset(0, eff.dy);
    }

    var snapDx = 0.0, snapDy = 0.0;
    var guides = const <SnapGuide>[];
    final start = _moveStartBounds;
    if (start != null && !_bypassSnapping) {
      final moving = SnapBox(
        start.l + eff.dx,
        start.b + eff.dy,
        start.r + eff.dx,
        start.t + eff.dy,
      );
      final page = _page;
      final res = _c.showGuides
          ? computeSnap(
              moving: moving,
              others: _otherShapeBoxes(),
              threshold: 6 / (_scale * ppi),
              pageGuides: _c.pageGuides,
              magnets: _otherConnectionMagnets(),
              pageBounds: page == null
                  ? null
                  : SnapBox(0, 0, page.widthInches, page.heightInches),
            )
          : SnapResult.none;
      snapDx = res.dx;
      snapDy = res.dy;
      guides = res.guides;
      // Fall back to grid snapping on any axis a neighbour / magnet / page
      // guide did not claim. Do not use `snapDx == 0` alone — once a box sits
      // on a guide the nudge is 0, and grid must not yank it off the align.
      if (_c.snapToGrid) {
        final g = _c.gridInches;
        if (!res.snappedX) {
          snapDx = (moving.l / g).roundToDouble() * g - moving.l;
        }
        if (!res.snappedY) {
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
    _remoteMove = false;
    if (_guides.isNotEmpty) setState(() => _guides = const <SnapGuide>[]);
  }

  static bool _sameGuides(List<SnapGuide> a, List<SnapGuide> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Connector target under [pos]. Alt/Option custom points are only valid
  /// inside a shape; ordinary and Shift-floating glue may also acquire a
  /// nearby blue point just outside its bounds.
  int? _connectorTargetAt(Offset pos, {int? excludeId}) => _glueTargetAt(
        pos,
        excludeId: excludeId,
        insideOnly: _customFixedConnectorDrop,
      );

  /// Deepest visible 2-D shape under [pos] (nested children included), or the
  /// shape owning the nearest connection point within [_connSnapPx].
  ///
  /// Skips 1-D strokes entirely so a connector's AABB cannot block glue to a
  /// shape underneath (create-by-drag / endpoint attach / hover-connect).
  /// Connection-point proximity is checked even when the pointer is *outside*
  /// the AABB so edge blue points stay sticky (draw.io parity).
  int? _glueTargetAt(
    Offset pos, {
    int? excludeId,
    bool insideOnly = false,
  }) {
    final page = _page;
    if (page == null) return null;
    final pt = _contentToPageInches(_viewportToContent(pos));
    final bounds = buildShapeBounds(page);
    int? bestInside;
    int? bestCp;
    var bestCpD = _connSnapPx * _connSnapPx;
    for (final id in _drawOrder(page)) {
      if (id == excludeId) continue;
      final s = page.findShapeById(id);
      if (s == null || !page.isShapeVisible(s) || s.is1D) continue;
      final r = bounds[id];
      if (r != null && r.contains(pt)) bestInside = id;
      final pts = VsdxPage.effectiveConnectionPoints(s);
      for (final p in pts) {
        final pg = _connPointPage(s, p.offset);
        final d = (_pageToScreen(pg.x, pg.y) - pos).distanceSquared;
        if (d <= bestCpD) {
          bestCpD = d;
          bestCp = id;
        }
      }
    }
    // Prefer a nearby connection point over a deep AABB hit so an outer blue
    // point is not stolen by an overlapping neighbour's interior.
    return insideOnly ? bestInside : bestCp ?? bestInside;
  }

  /// Content-px end for a live connector preview: sticks to a snapped blue
  /// connection point when one is active, otherwise follows the pointer.
  Offset _previewEndForSnap(VsdxShape? target, int? snapIndex, Offset pointerContent) {
    if (target == null || snapIndex == null) return pointerContent;
    final pts = VsdxPage.effectiveConnectionPoints(target);
    if (snapIndex < 0 || snapIndex >= pts.length) return pointerContent;
    final pg = _connPointPage(target, pts[snapIndex].offset);
    return _pageToContent(pg.x, pg.y);
  }

  /// Draw.io connector modifiers: Shift forces whole-shape (floating)
  /// attachment, while Alt/Option reserves the exact pointer position for a
  /// custom fixed point created on drop. Neither should snap to a nearby
  /// existing blue point during the preview.
  int? _connectorSnapIndex(VsdxShape target, Offset pos) {
    if (_customFixedConnectorDrop || _forceFloatingConnectorDrop) return null;
    return _connSnapIndex(target, pos);
  }

  /// Drawn / obstacle-aware connector polyline in **page** inches (matches
  /// canvas paint and SVG export via [VsdxPage.drawnConnectorPagePolyline]).
  List<Offset2D> _connectorRoutePage(VsdxShape conn) {
    final page = _page;
    if (page != null) {
      final drawn = page.drawnConnectorPagePolyline(conn);
      if (drawn.length >= 2) return drawn;
    }
    return _connectorControlRoutePage(conn);
  }

  /// Control polyline (waypoints / elbow) in **page** inches for bend handles.
  /// Curved / rounded connectors keep the sparse control path — not the dense
  /// baked sample — so drag indices match [setConnectorWaypoints].
  List<Offset2D> _connectorControlRoutePage(VsdxShape conn) {
    final route = VsdxPage.connectorRoute(conn);
    final page = _page;
    if (page == null || route.isEmpty) return route;
    final parentId = page.findParentId(conn.id);
    if (parentId == null) return route;
    return <Offset2D>[
      for (final p in route) page.localToPageDeep(parentId, p),
    ];
  }

  /// Arc-length midpoint of [conn]'s drawn route in **page** inches.
  Offset2D _connectorMidpointPage(VsdxShape conn) {
    final route = _connectorRoutePage(conn);
    if (route.isEmpty) {
      final page = _page;
      if (page != null) return page.shapePinPage(conn.id);
      return Offset2D(conn.pinX, conn.pinY);
    }
    if (route.length == 1) return route.first;
    var total = 0.0;
    for (var i = 0; i < route.length - 1; i++) {
      final dx = route[i].x - route[i + 1].x;
      final dy = route[i].y - route[i + 1].y;
      total += math.sqrt(dx * dx + dy * dy);
    }
    if (total <= 0) return route.first;
    var remaining = total / 2;
    for (var i = 0; i < route.length - 1; i++) {
      final dx = route[i + 1].x - route[i].x;
      final dy = route[i + 1].y - route[i].y;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len >= remaining) {
        final t = len == 0 ? 0.0 : remaining / len;
        return Offset2D(route[i].x + dx * t, route[i].y + dy * t);
      }
      remaining -= len;
    }
    return route.last;
  }

  /// Index of [s]'s effective connection point nearest [viewportPos] within the
  /// snap radius (drawio blue point), or null for a whole-shape glue.
  int? _connSnapIndex(VsdxShape s, Offset viewportPos) {
    final pts = VsdxPage.effectiveConnectionPoints(s);
    var best = -1;
    var bestD = _connSnapPx * _connSnapPx;
    for (var i = 0; i < pts.length; i++) {
      final page = _connPointPage(s, pts[i].offset);
      final d = (_pageToScreen(page.x, page.y) - viewportPos).distanceSquared;
      if (d <= bestD) {
        bestD = d;
        best = i;
      }
    }
    return best < 0 ? null : best;
  }

  /// Whether [viewportPos] is within the snap radius of [s]'s geometry outline
  /// (draw.io: start a connector from anywhere on the body, not only blue dots).
  bool _nearShapePerimeter(VsdxShape s, Offset viewportPos) =>
      _nearestPerimeterPage(s, viewportPos) != null;

  /// Nearest page-inch point on [s]'s outline to [viewportPos], or `null` when
  /// farther than [_connSnapPx] from every segment.
  Offset2D? _nearestPerimeterPage(VsdxShape s, Offset viewportPos) {
    final page = _page;
    if (page == null) return null;
    final inch = _pageInchesAt(viewportPos);
    final local = page.pageToLocalDeep(s.id, Offset2D(inch.dx, inch.dy));
    final nearest = ShapePerimeter.nearestLocal(s, local);
    if (nearest == null) return null;
    final pg = page.localToPageDeep(s.id, nearest);
    final d = (_pageToScreen(pg.x, pg.y) - viewportPos).distanceSquared;
    if (d > _connSnapPx * _connSnapPx) return null;
    return pg;
  }

  /// Index of a connection point on [s] under [viewportPos] to start a *new*
  /// connector from (drawio's edge connection points), or null. Excludes the
  /// shape's centre point so pressing the middle still moves the shape.
  int? _connDragSourceIndex(VsdxShape s, Offset viewportPos) {
    final pts = VsdxPage.effectiveConnectionPoints(s);
    final cx = s.width / 2, cy = s.height / 2;
    var best = -1;
    var bestD = _connSnapPx * _connSnapPx;
    for (var i = 0; i < pts.length; i++) {
      if ((pts[i].x - cx).abs() < 1e-6 && (pts[i].y - cy).abs() < 1e-6) {
        continue; // centre point overlaps the move-grab region
      }
      final page = _connPointPage(s, pts[i].offset);
      final d = (_pageToScreen(page.x, page.y) - viewportPos).distanceSquared;
      if (d <= bestD) {
        bestD = d;
        best = i;
      }
    }
    return best < 0 ? null : best;
  }

  /// Page-inch centre one step from [s] in [dir] (0=N, 1=E, 2=S, 3=W).
  (double, double) _neighbourCentre(VsdxShape s, int dir) {
    // Gap between the two boxes' facing edges (snapped so neighbours tile).
    const gap = 0.5;
    final aabb = _page!.shapePageAabb(s.id);
    final pin = _page!.shapePinPage(s.id);
    final w = aabb != null ? (aabb.right - aabb.left) : s.width;
    final h = aabb != null ? (aabb.top - aabb.bottom) : s.height;
    var cx = pin.x, cy = pin.y;
    switch (dir) {
      case 0: // north (page space is Y-up)
        cy = pin.y + h + gap;
      case 1: // east
        cx = pin.x + w + gap;
      case 2: // south
        cy = pin.y - h - gap;
      default: // west
        cx = pin.x - w - gap;
    }
    return (_c.snap(cx), _c.snap(cy));
  }

  /// drawio directional-arrow Shift+click: connect [s] to the shape one step
  /// over in [dir] — or clone [s] there and connect to it — then select it.
  void _connectInDirection(VsdxShape s, int dir) {
    final (cx, cy) = _neighbourCentre(s, dir);
    // Connect to a shape already sitting where the clone would land, else clone.
    final existing = _glueTargetAt(_pageToScreen(cx, cy), excludeId: s.id);
    _c.connectDirectional(
      s.id,
      dir,
      existingTargetId: existing,
      cloneX: cx,
      cloneY: cy,
    );
  }

  /// EdrawMax-style click on a hover arrow: open the quick-add shape picker.
  void _showQuickAddFor(VsdxShape s, int dir, Offset localPos) {
    _dismissQuickAdd?.call();
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    // Anchor at the arrow centre (more stable than the raw pointer).
    final gap = _connectArrowGapPxEffective / _scale;
    Offset content = localPos;
    for (final (c, d) in _connectArrows(_exactContentBox(s), gap)) {
      if (d == dir) {
        content = c;
        break;
      }
    }
    final global = box.localToGlobal(_offset + content * _scale);
    final sourceId = s.id;
    _dismissQuickAdd = showQuickAddPicker(
      context: context,
      anchorGlobal: global,
      onClosed: () => _dismissQuickAdd = null,
      onSelect: (stencil) {
        final src = _page?.findShapeById(sourceId);
        if (src == null || !_canConnectFrom(src)) return;
        final (cx, cy) = _neighbourCentre(src, dir);
        _c.quickAddInDirection(
          sourceId,
          dir,
          build: stencil.build,
          cx: cx,
          cy: cy,
        );
      },
      onDuplicate: () {
        final src = _page?.findShapeById(sourceId);
        if (src == null || !_canConnectFrom(src)) return;
        _connectInDirection(src, dir);
      },
    );
  }

  /// draw.io blank-canvas double-click: choose a common shape and insert it at
  /// the clicked page point using the current default style.
  void _showQuickInsertAt(Offset localPos) {
    _dismissQuickAdd?.call();
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final pagePoint = _pageInchesAt(localPos);
    _dismissQuickAdd = showQuickAddPicker(
      context: context,
      anchorGlobal: box.localToGlobal(localPos),
      onClosed: () => _dismissQuickAdd = null,
      onSelect: (stencil) {
        _c.addShapeFromBuilderAt(
          stencil.build,
          pagePoint.dx,
          pagePoint.dy,
        );
      },
    );
  }

  /// Start dragging a selected connector's label anchor (draw.io yellow
  /// diamond). Returns whether the drag was started.
  bool _tryStartConnectorLabelDrag(Offset localPos) {
    final conn = _selectedConnector();
    if (conn == null ||
        !_canEditConnector(conn) ||
        !_connectorHasLabel(conn)) {
      return false;
    }
    final label = _connectorLabelPage(conn);
    final hit = _handleHitPx * _handleHitPx;
    if ((_pageToScreen(label.x, label.y) - localPos).distanceSquared > hit) {
      return false;
    }
    _c.beginTransaction();
    _connectorLabelId = conn.id;
    _mode = _DragMode.moveConnectorLabel;
    return true;
  }

  /// Start rotating a selected connector label from its circular grab handle.
  bool _tryStartConnectorLabelRotate(Offset localPos) {
    final conn = _selectedConnector();
    if (conn == null ||
        !_canEditConnector(conn) ||
        !_connectorHasLabel(conn)) {
      return false;
    }
    final (_, knob) = _connectorLabelRotateAnchors(conn);
    final knobScreen = _offset + knob * _scale;
    final hit = _handleHitPx * _handleHitPx;
    if ((knobScreen - localPos).distanceSquared > hit) return false;
    _c.beginTransaction();
    _connectorLabelId = conn.id;
    _mode = _DragMode.rotateConnectorLabel;
    return true;
  }

  /// Start dragging a selected connector's begin / end handle (drawio endpoint
  /// editing). Returns whether the drag was started.
  bool _tryStartEndpointDrag(Offset localPos) {
    final conn = _selectedConnector();
    if (conn == null || !_canEditConnector(conn)) return false;
    final route = _connectorRoutePage(conn);
    if (route.length < 2) return false;
    final hit = _handleHitPx * _handleHitPx;
    final ends = <bool>[true, false]; // begin, end
    for (final begin in ends) {
      final p = begin ? route.first : route.last;
      if ((_pageToScreen(p.x, p.y) - localPos).distanceSquared <= hit) {
        _c.beginTransaction();
        _endpointConnId = conn.id;
        _endpointIsBegin = begin;
        _connectTargetId = null;
        _snapConnIndex = null;
        _connectTargetFixedAtPosition = false;
        _mode = _DragMode.moveEndpoint;
        return true;
      }
    }
    return false;
  }

  bool _tryStartWaypointDrag(Offset localPos) {
    final conn = _selectedConnector();
    if (conn == null || !_canEditConnector(conn)) return false;
    // Hit-test control polyline (not dense curved samples); promote stores
    // parent-local waypoints from the same control path.
    final pageRoute = _connectorControlRoutePage(conn);
    final page = _page;
    void promote() {
      if (conn.waypoints.isNotEmpty || pageRoute.length <= 2) return;
      final parentId = page?.findParentId(conn.id);
      final localInterior = <Offset2D>[
        for (final p in pageRoute.sublist(1, pageRoute.length - 1))
          parentId == null || page == null
              ? p
              : page.pageToLocalDeep(parentId, p),
      ];
      _c.setConnectorWaypoints(conn.id, localInterior, transient: true);
    }

    // Existing interior vertices → move that bend point.
    final hit = _handleHitPx * _handleHitPx;
    for (var r = 1; r < pageRoute.length - 1; r++) {
      if ((_pageToScreen(pageRoute[r].x, pageRoute[r].y) - localPos)
              .distanceSquared <=
          hit) {
        _c.beginTransaction();
        promote();
        _waypointConnId = conn.id;
        _waypointIndex = r - 1;
        _mode = _DragMode.moveWaypoint;
        return true;
      }
    }
    // Segment midpoints → insert a new bend point there and drag it.
    for (var r = 0; r < pageRoute.length - 1; r++) {
      final mx = (pageRoute[r].x + pageRoute[r + 1].x) / 2;
      final my = (pageRoute[r].y + pageRoute[r + 1].y) / 2;
      if ((_pageToScreen(mx, my) - localPos).distanceSquared <= hit) {
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

  /// Start dragging a table column/row divider near [viewportPos].
  bool _tryStartTableDividerDrag(Offset viewportPos) {
    final tableId = _c.selectedTableId;
    final page = _page;
    if (tableId == null || page == null) return false;
    final table = page.findShapeById(tableId);
    if (table == null ||
        !TableOps.isTable(table) ||
        table.locked ||
        _c.isOnLockedLayer(tableId)) {
      return false;
    }
    const hitPxMouse = 6.0;
    final hitPx = _isTouchUi ? 14.0 : hitPxMouse;
    final hit2 = hitPx * hitPx;

    final colDivs = TableOps.colDividerLocals(table);
    for (var i = 0; i < colDivs.length; i++) {
      final lx = colDivs[i];
      final a = page.localToPageDeep(tableId, Offset2D(lx, 0));
      final b = page.localToPageDeep(tableId, Offset2D(lx, table.height));
      final sa = _pageToScreen(a.x, a.y);
      final sb = _pageToScreen(b.x, b.y);
      if (_distToSegmentSq(viewportPos, sa, sb) <= hit2) {
        _tableResizeId = tableId;
        _tableDividerIndex = i;
        _tableResizeLastPage = _pageInchesAt(viewportPos);
        _mode = _DragMode.tableColResize;
        _c.beginTransaction();
        return true;
      }
    }
    final rowDivs = TableOps.rowDividerLocalsFromBottom(table);
    for (var i = 0; i < rowDivs.length; i++) {
      final ly = rowDivs[i];
      final a = page.localToPageDeep(tableId, Offset2D(0, ly));
      final b = page.localToPageDeep(tableId, Offset2D(table.width, ly));
      final sa = _pageToScreen(a.x, a.y);
      final sb = _pageToScreen(b.x, b.y);
      if (_distToSegmentSq(viewportPos, sa, sb) <= hit2) {
        _tableResizeId = tableId;
        _tableDividerIndex = i;
        _tableResizeLastPage = _pageInchesAt(viewportPos);
        _mode = _DragMode.tableRowResize;
        _c.beginTransaction();
        return true;
      }
    }
    return false;
  }

  void _applyTableColResize(Offset pos) {
    final id = _tableResizeId;
    final idx = _tableDividerIndex;
    final page = _page;
    if (id == null || idx == null || page == null) return;
    final cur = _pageInchesAt(pos);
    // Column width is table-local X; project page delta through ancestors.
    final prevLocal = page.pageToLocalDeep(
      id,
      Offset2D(_tableResizeLastPage.dx, _tableResizeLastPage.dy),
    );
    final curLocal = page.pageToLocalDeep(id, Offset2D(cur.dx, cur.dy));
    final delta = curLocal.x - prevLocal.x;
    _tableResizeLastPage = cur;
    if (delta.abs() < 1e-9) return;
    _c.resizeTableColumn(id, idx, delta, transient: true);
  }

  void _applyTableRowResize(Offset pos) {
    final id = _tableResizeId;
    final idx = _tableDividerIndex;
    final page = _page;
    if (id == null || idx == null || page == null) return;
    final cur = _pageInchesAt(pos);
    final prevLocal = page.pageToLocalDeep(
      id,
      Offset2D(_tableResizeLastPage.dx, _tableResizeLastPage.dy),
    );
    final curLocal = page.pageToLocalDeep(id, Offset2D(cur.dx, cur.dy));
    final delta = curLocal.y - prevLocal.y;
    _tableResizeLastPage = cur;
    if (delta.abs() < 1e-9) return;
    _c.resizeTableRow(id, idx, delta, transient: true);
  }

  static double _distToSegmentSq(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 < 1e-12) return (p - a).distanceSquared;
    var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
    t = t.clamp(0.0, 1.0);
    final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - proj).distanceSquared;
  }

  /// Table divider guides in content-px for the selection overlay.
  List<(Offset, Offset)> _tableDividerSegments(VsdxPage page) {
    final tableId = _c.selectedTableId;
    if (tableId == null) return const <(Offset, Offset)>[];
    final table = page.findShapeById(tableId);
    if (table == null || !TableOps.isTable(table)) {
      return const <(Offset, Offset)>[];
    }
    final out = <(Offset, Offset)>[];
    for (final lx in TableOps.colDividerLocals(table)) {
      final a = page.localToPageDeep(tableId, Offset2D(lx, 0));
      final b = page.localToPageDeep(tableId, Offset2D(lx, table.height));
      out.add((_pageToContent(a.x, a.y), _pageToContent(b.x, b.y)));
    }
    for (final ly in TableOps.rowDividerLocalsFromBottom(table)) {
      final a = page.localToPageDeep(tableId, Offset2D(0, ly));
      final b = page.localToPageDeep(tableId, Offset2D(table.width, ly));
      out.add((_pageToContent(a.x, a.y), _pageToContent(b.x, b.y)));
    }
    return out;
  }

  void _onPanEnd(DragEndDetails d) {
    switch (_mode) {
      case _DragMode.moveConnectionPoint:
        _c.commitTransaction();
        _connPointDragIndex = null;
      case _DragMode.moveWaypoint:
        _c.commitTransaction();
        _waypointConnId = null;
        _waypointIndex = null;
      case _DragMode.moveConnectorLabel:
      case _DragMode.rotateConnectorLabel:
        _c.commitTransaction();
        _connectorLabelId = null;
      case _DragMode.moveEndpoint:
        final endpointId = _endpointConnId;
        final fixedTarget = _connectTargetId;
        if (endpointId != null &&
            fixedTarget != null &&
            _connectTargetFixedAtPosition) {
          final p = _pageInchesAt(_lastPointer);
          _c.reconnectEndpoint(
            endpointId,
            begin: _endpointIsBegin,
            targetShapeId: fixedTarget,
            createFixedConnectionPoint: true,
            x: p.dx,
            y: p.dy,
            transient: true,
          );
        }
        _c.commitTransaction();
        _endpointConnId = null;
        setState(() {
          _connectTargetId = null;
          _snapConnIndex = null;
          _connectTargetFixedAtPosition = false;
        });
      case _DragMode.moveShapes:
      case _DragMode.resize:
      case _DragMode.rotate:
      case _DragMode.tableColResize:
      case _DragMode.tableRowResize:
        if (_mode == _DragMode.moveShapes) {
          final end = _lastPointer;
          final pagePt = _contentToPageInches(_viewportToContent(end));
          if (!_bypassSnapping) {
            _c.applyDropContainmentAt(pagePt.dx, pagePt.dy, transient: true);
          }
        }
        _c.commitTransaction();
        _activeHandle = null;
        _resizeShapeId = null;
        _resizeStartShape = null;
        _tableResizeId = null;
        _tableDividerIndex = null;
        _clearMoveGuides();
        setState(() => _dropContainerId = null);
      case _DragMode.moveArea:
        _c.commitTransaction();
        _clearAreaMove();
      case _DragMode.createShape:
        if (_c.tool == EditorTool.freehand) {
          final end = _previewEnd;
          if (end != null &&
              _freehandPoints.isNotEmpty &&
              _freehandPoints.last != end) {
            _freehandPoints.add(end);
          }
          if (_freehandPoints.length >= 2) {
            final pts = <Offset2D>[];
            for (final p in _freehandPoints) {
              final inch = _contentToPageInches(p);
              pts.add(Offset2D(inch.dx, inch.dy));
            }
            _c.createFreehand(pts);
          }
          setState(() {
            _freehandPoints.clear();
            _previewStart = null;
            _previewEnd = null;
          });
          break;
        }
        final start = _previewStart;
        final end = _previewEnd;
        if (start != null && end != null) {
          final a = _contentToPageInches(start);
          final b = _contentToPageInches(end);
          if (_c.tool == EditorTool.connector) {
            final beginTarget =
                _connectorTargetAt(_offset + start * _scale);
            final endTarget = _connectTargetId ??
                _connectorTargetAt(_offset + end * _scale);
            _c.createConnector(
              a.dx,
              a.dy,
              b.dx,
              b.dy,
              beginTarget: beginTarget,
              endTarget: endTarget,
              beginConnectionPointIndex:
                  beginTarget != null ? _connectSourceConnIndex : null,
              endConnectionPointIndex: endTarget != null ? _snapConnIndex : null,
              beginFixedAtPosition:
                  beginTarget != null && _connectSourceFixedAtPosition,
              endFixedAtPosition:
                  endTarget != null && _connectTargetFixedAtPosition,
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
          _snapConnIndex = null;
          _connectSourceConnIndex = null;
          _connectSourceFixedAtPosition = false;
          _connectTargetFixedAtPosition = false;
        });
      case _DragMode.connect:
        final start = _previewStart;
        final end = _previewEnd;
        final src = _connectSourceId;
        if (start != null && end != null && src != null) {
          final a = _contentToPageInches(start);
          final b = _contentToPageInches(end);
          final target =
              _connectTargetId == src ? null : _connectTargetId;
          final arrowDirection = _connectArrowDirection;
          if (arrowDirection != null && _cloneDrag) {
            _c.connectDirectional(
              src,
              arrowDirection,
              existingTargetId: target,
              cloneX: _bypassSnapping ? b.dx : _c.snap(b.dx),
              cloneY: _bypassSnapping ? b.dy : _c.snap(b.dy),
            );
          } else {
            _c.createConnector(
              a.dx,
              a.dy,
              b.dx,
              b.dy,
              beginTarget: src,
              endTarget: target,
              beginConnectionPointIndex: _connectSourceConnIndex,
              endConnectionPointIndex:
                  target != null ? _snapConnIndex : null,
              endFixedAtPosition:
                  target != null && _connectTargetFixedAtPosition,
            );
          }
        }
        setState(() {
          _previewStart = null;
          _previewEnd = null;
          _connectSourceId = null;
          _connectSourceConnIndex = null;
          _connectArrowDirection = null;
          _connectTargetId = null;
          _snapConnIndex = null;
          _connectSourceFixedAtPosition = false;
          _connectTargetFixedAtPosition = false;
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
    _emptyTouchPanAt = null;
    _emptyTouchPanOrigin = null;
    _emptyTouchPanAccum = Offset.zero;
    _finishPendingQuickAdd();
  }

  /// If a directional-arrow press was claimed by the pan recognizer but barely
  /// moved, treat the release as a click (open picker / Shift-clone).
  void _finishPendingQuickAdd() {
    final pending = _pendingQuickAdd;
    _pendingQuickAdd = null;
    if (pending == null || !_connectAffordanceActive) return;
    final s = _page?.findShapeById(pending.id);
    if (s == null || !_canConnectFrom(s)) return;
    if (HardwareKeyboard.instance.isShiftPressed) {
      _connectInDirection(s, pending.dir);
    } else {
      _showQuickAddFor(s, pending.dir, pending.start);
    }
  }

  /// Promote a directional-arrow press into a connector drag, fixing its begin
  /// to the source's page-facing connection point.
  void _beginDirectionalArrowDrag(
    ({int id, int dir, Offset start}) pending,
    Offset current,
  ) {
    final page = _page;
    final source = page?.findShapeById(pending.id);
    if (page == null || source == null || !_canConnectFrom(source)) return;
    final points = VsdxPage.effectiveConnectionPoints(source);
    if (points.isEmpty) return;
    final index = page.connectionIndexForPageDir(source.id, pending.dir);
    if (index < 0 || index >= points.length) return;
    final begin = _connPointPage(source, points[index].offset);
    _connectSourceId = source.id;
    _connectSourceConnIndex = index;
    _connectSourceFixedAtPosition = false;
    _connectTargetFixedAtPosition = false;
    _connectArrowDirection = pending.dir;
    _connectTargetId = null;
    _snapConnIndex = null;
    _previewStart = _pageToContent(begin.x, begin.y);
    _previewEnd = _viewportToContent(current);
    _mode = _DragMode.connect;
  }

  /// Abort whatever drag is in progress and revert transient model changes
  /// (Escape). Further pan updates are ignored because the mode is reset.
  void _cancelActiveDrag() {
    _pendingQuickAdd = null;
    switch (_mode) {
      case _DragMode.moveShapes:
      case _DragMode.resize:
      case _DragMode.rotate:
      case _DragMode.moveWaypoint:
      case _DragMode.moveEndpoint:
      case _DragMode.moveConnectorLabel:
      case _DragMode.rotateConnectorLabel:
      case _DragMode.moveConnectionPoint:
      case _DragMode.tableColResize:
      case _DragMode.tableRowResize:
      case _DragMode.moveArea:
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
      _connectSourceFixedAtPosition = false;
      _connectTargetFixedAtPosition = false;
      _freehandPoints.clear();
      _marqueeStart = null;
      _marqueeEnd = null;
      _areaOriginPage = null;
      _areaStartContent = null;
      _areaEndContent = null;
      _areaAppliedPage = Offset.zero;
      _areaHorizontalIds = null;
      _areaVerticalIds = null;
      _connectSourceId = null;
      _connectSourceConnIndex = null;
      _connectArrowDirection = null;
      _connectTargetId = null;
      _tableResizeId = null;
      _tableDividerIndex = null;
      _dropContainerId = null;
      _activeHandle = null;
      _resizeShapeId = null;
      _resizeStartShape = null;
      _waypointConnId = null;
      _waypointIndex = null;
      _endpointConnId = null;
      _connectorLabelId = null;
      _connPointDragIndex = null;
      _snapConnIndex = null;
      _guides = const <SnapGuide>[];
      _moveStartBounds = null;
      _remoteMove = false;
      _emptyTouchPanAt = null;
      _emptyTouchPanOrigin = null;
      _emptyTouchPanAccum = Offset.zero;
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
    final marquee = Rect.fromLTRB(l, bottom, r, top);
    final bounds = buildShapeBounds(page);
    final topLevel = <int>{
      for (final sh in page.shapes)
        if (page.isShapeVisible(sh)) sh.id,
    };
    final intersecting = HardwareKeyboard.instance.isAltPressed;
    final candidates =
        intersecting ? _drawOrder(page).toSet() : topLevel;
    final ids = <int>[];
    for (final entry in bounds.entries) {
      if (!candidates.contains(entry.key)) continue;
      final box = entry.value;
      // Default draw.io marquee selects only fully enclosed top-level shapes.
      // Alt expands this to every visible shape/connector that intersects.
      final misses = box.left > r ||
          box.right < l ||
          box.top > top ||
          box.bottom < bottom;
      final contained = box.left >= l &&
          box.right <= r &&
          box.top >= bottom &&
          box.bottom <= top;
      if (intersecting ? misses : !contained) continue;
      final sh = page.findShapeById(entry.key);
      if (sh == null) continue;
      // For Alt-intersection, require the actual 1-D stroke (not its diagonal
      // AABB) to meet the marquee. Default containment already checked the
      // connector's complete routed bounds above.
      if (intersecting && sh.is1D) {
        final segs = _strokePageSegments(page, sh);
        var hit = false;
        for (final (p0, p1) in segs) {
          if (_segIntersectsRect(p0, p1, marquee)) {
            hit = true;
            break;
          }
        }
        if (!hit) continue;
      }
      ids.add(entry.key);
    }
    final subtract = HardwareKeyboard.instance.isAltPressed &&
        HardwareKeyboard.instance.isShiftPressed;
    final toggle = HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (subtract) {
      _c.setSelection(Set<int>.of(_c.selection)..removeAll(ids));
    } else if (toggle) {
      final next = Set<int>.of(_c.selection);
      for (final id in ids) {
        if (!next.remove(id)) next.add(id);
      }
      _c.setSelection(next);
    } else {
      _c.setSelection(ids);
    }
  }

  void _applyAreaMove(Offset viewportPos) {
    final page = _page;
    final origin = _areaOriginPage;
    if (page == null || origin == null) return;
    final current = _pageInchesAt(viewportPos);
    final total = current - origin;
    setState(() => _areaEndContent = _viewportToContent(viewportPos));
    if (_areaHorizontalIds == null || _areaVerticalIds == null) {
      if (total.distance < 2 / (_scale * widget.pxPerInch)) return;
      final bounds = buildShapeBounds(page);
      final horizontal = <int>{};
      final vertical = <int>{};
      for (final shape in page.shapes) {
        if (!page.isShapeVisible(shape) ||
            shape.locked ||
            _c.isOnLockedLayer(shape.id)) {
          continue;
        }
        final box = bounds[shape.id];
        if (box == null) continue;
        if ((total.dx > 0 && box.left >= origin.dx) ||
            (total.dx < 0 && box.right <= origin.dx)) {
          horizontal.add(shape.id);
        }
        if ((total.dy > 0 && box.bottom >= origin.dy) ||
            (total.dy < 0 && box.top <= origin.dy)) {
          vertical.add(shape.id);
        }
      }
      _areaHorizontalIds = horizontal;
      _areaVerticalIds = vertical;
    }
    final dx = total.dx - _areaAppliedPage.dx;
    final dy = total.dy - _areaAppliedPage.dy;
    final horizontal = _areaHorizontalIds!;
    final vertical = _areaVerticalIds!;
    final ids = <int>{...horizontal, ...vertical};
    _c.moveShapesBy(
      <int, Offset2D>{
        for (final id in ids)
          id: Offset2D(
            horizontal.contains(id) ? dx : 0,
            vertical.contains(id) ? dy : 0,
          ),
      },
      transient: true,
    );
    _areaAppliedPage = total;
  }

  void _clearAreaMove() {
    setState(() {
      _areaOriginPage = null;
      _areaStartContent = null;
      _areaEndContent = null;
      _areaAppliedPage = Offset.zero;
      _areaHorizontalIds = null;
      _areaVerticalIds = null;
    });
  }

  /// True when segment [a]→[b] intersects or lies inside axis-aligned [r].
  static bool _segIntersectsRect(Offset2D a, Offset2D b, Rect r) {
    bool inside(Offset2D p) =>
        p.x >= r.left && p.x <= r.right && p.y >= r.top && p.y <= r.bottom;
    if (inside(a) || inside(b)) return true;
    // Cohen-style: clip against each edge of the rect.
    bool crosses(
      double x1,
      double y1,
      double x2,
      double y2,
      double x3,
      double y3,
      double x4,
      double y4,
    ) {
      final d = (x2 - x1) * (y4 - y3) - (y2 - y1) * (x4 - x3);
      if (d.abs() < 1e-18) return false;
      final t = ((x3 - x1) * (y4 - y3) - (y3 - y1) * (x4 - x3)) / d;
      final u = ((x3 - x1) * (y2 - y1) - (y3 - y1) * (x2 - x1)) / d;
      return t >= 0 && t <= 1 && u >= 0 && u <= 1;
    }

    final x1 = a.x, y1 = a.y, x2 = b.x, y2 = b.y;
    return crosses(x1, y1, x2, y2, r.left, r.top, r.right, r.top) ||
        crosses(x1, y1, x2, y2, r.right, r.top, r.right, r.bottom) ||
        crosses(x1, y1, x2, y2, r.right, r.bottom, r.left, r.bottom) ||
        crosses(x1, y1, x2, y2, r.left, r.bottom, r.left, r.top);
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
      // Modified Delete/Backspace is also handled locally when the canvas owns
      // focus; every other Cmd/Ctrl chord bubbles to the app-level shortcuts.
      if (key != LogicalKeyboardKey.delete &&
          key != LogicalKeyboardKey.backspace) {
        return KeyEventResult.ignored;
      }
    }
    if (widget.presentationMode) {
      if (key == LogicalKeyboardKey.escape) {
        if (_mode != _DragMode.none) {
          _cancelActiveDrag();
          return KeyEventResult.handled;
        }
        widget.onExitPresentation?.call();
        return KeyEventResult.handled;
      }
      // Slideshow-style page navigation (editing keys are ignored).
      if (key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.pageDown ||
          key == LogicalKeyboardKey.space) {
        if (_c.currentPageIndex < _c.pageCount - 1) {
          _c.selectPage(_c.currentPageIndex + 1);
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.pageUp ||
          key == LogicalKeyboardKey.backspace) {
        if (_c.currentPageIndex > 0) {
          _c.selectPage(_c.currentPageIndex - 1);
        }
        return KeyEventResult.handled;
      }
      // Swallow delete / typing so presentation never mutates the document.
      if (key == LogicalKeyboardKey.delete ||
          key == LogicalKeyboardKey.backspace) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      if (_c.editingConnectionPoints) {
        if (_c.selectedConnectionPointIndex != null) {
          _c.removeSelectedConnectionPoint();
          return KeyEventResult.handled;
        }
        return KeyEventResult.handled; // don't delete the shape while editing
      }
      if (_c.hasSelection) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          _c.clearSelectionLabels();
        } else {
          _c.deleteSelection(
            includeConnected: HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed,
          );
        }
        return KeyEventResult.handled;
      }
    } else if (key == LogicalKeyboardKey.escape) {
      // Dismiss quick-add picker before other Escape actions.
      if (_dismissQuickAdd != null) {
        _dismissQuickAdd!.call();
        return KeyEventResult.handled;
      }
      // Cancel a pending arrow click (pan claimed, not yet released).
      if (_pendingQuickAdd != null) {
        _pendingQuickAdd = null;
        return KeyEventResult.handled;
      }
      // Cancel an in-progress drag first (revert to the pre-drag state).
      if (_mode != _DragMode.none) {
        _cancelActiveDrag();
        return KeyEventResult.handled;
      }
      if (_c.editingConnectionPoints) {
        _c.endEditConnectionPoints();
        return KeyEventResult.handled;
      }
      if (_c.tool != EditorTool.select) {
        _c.setTool(EditorTool.select);
      } else {
        _c.clearSelection();
      }
      return KeyEventResult.handled;
    } else if (_c.hasSelection && !_c.editingConnectionPoints) {
      // draw.io: selecting a shape and typing replaces its entire label.
      // Shift is allowed for capital letters; command/option modifiers remain
      // available to app and platform shortcuts.
      final character = event.character;
      final id = _c.singleSelectedId;
      if (id != null &&
          character != null &&
          character.trim().isNotEmpty &&
          !HardwareKeyboard.instance.isMetaPressed &&
          !HardwareKeyboard.instance.isControlPressed &&
          !HardwareKeyboard.instance.isAltPressed) {
        _beginTextEdit(id, replacement: character);
        return KeyEventResult.handled;
      }
      if (HardwareKeyboard.instance.isAltPressed &&
          HardwareKeyboard.instance.isShiftPressed) {
        final dir = switch (key) {
          LogicalKeyboardKey.arrowUp => 0,
          LogicalKeyboardKey.arrowRight => 1,
          LogicalKeyboardKey.arrowDown => 2,
          LogicalKeyboardKey.arrowLeft => 3,
          _ => null,
        };
        if (dir != null) {
          _c.connectSelectionInDirection(dir);
          return KeyEventResult.handled;
        }
      }
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
    final zoomModifier = HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (zoomModifier) {
      final factor = e.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1;
      _zoomBy(factor, e.localPosition);
    } else if (HardwareKeyboard.instance.isShiftPressed) {
      final dx =
          e.scrollDelta.dy != 0 ? e.scrollDelta.dy : e.scrollDelta.dx;
      setState(() => _offset -= Offset(dx, 0));
    } else {
      setState(() => _offset -= e.scrollDelta);
    }
  }

  /// View-only pan / pinch via raw pointers (no gesture-arena slop), so a
  /// one-finger drag tracks 1:1 and a two-finger pinch zooms around the focal.
  ///
  /// Edit-mode gestures stay on [GestureDetector] — tracking pointers here
  /// while editing prevented pan/tap recognition on touch layouts.
  void _onCanvasPointerDown(PointerDownEvent e) {
    final auxiliaryPan =
        e.buttons & (kSecondaryMouseButton | kMiddleMouseButton) != 0;
    if (auxiliaryPan && _auxPanPointer == null) {
      if (_mode != _DragMode.none && !_viewOnlyGestures) return;
      if (_editingShapeId != null) _commitTextEdit();
      _ensureCanvasFocus();
      setState(() {
        _auxPanPointer = e.pointer;
        _auxPanLast = e.localPosition;
        _mode = _DragMode.panCanvas;
      });
      return;
    }
    if (!_viewOnlyGestures) return;
    if (_editingShapeId != null) {
      _commitTextEdit();
      _mode = _DragMode.none;
    }
    _ensureCanvasFocus();
    _viewPointers[e.pointer] = e.localPosition;
    if (_viewPointers.length == 1) {
      _lastPointer = e.localPosition;
      _mode = _DragMode.panCanvas;
      _pinchActive = false;
    } else if (_viewPointers.length == 2) {
      final pts = _viewPointers.values.toList(growable: false);
      final focal = Offset(
        (pts[0].dx + pts[1].dx) / 2,
        (pts[0].dy + pts[1].dy) / 2,
      );
      _viewScaleStart = _scale;
      _viewScaleContentFocal = _viewportToContent(focal);
      _viewPinchStartDistance = (pts[0] - pts[1]).distance;
      _mode = _DragMode.panCanvas;
      _pinchActive = true;
    }
  }

  void _onCanvasPointerMove(PointerMoveEvent e) {
    if (e.pointer == _auxPanPointer) {
      final pos = e.localPosition;
      setState(() => _offset += pos - _auxPanLast);
      _auxPanLast = pos;
      return;
    }
    if (!_viewOnlyGestures || !_viewPointers.containsKey(e.pointer)) return;
    _viewPointers[e.pointer] = e.localPosition;
    if (_viewPointers.length == 1 && _mode == _DragMode.panCanvas) {
      final pos = e.localPosition;
      setState(() => _offset += pos - _lastPointer);
      _lastPointer = pos;
      return;
    }
    if (_viewPointers.length >= 2 && _mode == _DragMode.panCanvas) {
      final pts = _viewPointers.values.toList(growable: false);
      final focal = Offset(
        (pts[0].dx + pts[1].dx) / 2,
        (pts[0].dy + pts[1].dy) / 2,
      );
      final dist = (pts[0] - pts[1]).distance;
      final factor = _viewPinchStartDistance > 1e-6
          ? dist / _viewPinchStartDistance
          : 1.0;
      final target =
          (_viewScaleStart * factor).clamp(widget.minScale, widget.maxScale);
      setState(() {
        _scale = target.toDouble();
        _offset = focal - _viewScaleContentFocal * _scale;
      });
    }
  }

  void _onCanvasPointerUp(PointerEvent e) {
    if (e.pointer == _auxPanPointer) {
      setState(() {
        _auxPanPointer = null;
        _mode = _DragMode.none;
      });
      return;
    }
    if (!_viewPointers.containsKey(e.pointer)) return;
    _viewPointers.remove(e.pointer);
    if (_viewPointers.isEmpty) {
      if (_mode == _DragMode.panCanvas) _mode = _DragMode.none;
      _pinchActive = false;
      return;
    }
    if (_viewPointers.length == 1) {
      _lastPointer = _viewPointers.values.first;
      _mode = _DragMode.panCanvas;
      _pinchActive = false;
    }
  }

  /// Resolve [page]'s Visio `BackPage` underlay from [doc], or `null`.
  VsdxPage? _resolvedUnderlay(VsdxDocument doc, VsdxPage page) {
    final id = page.backgroundPageId;
    if (id == null) return null;
    for (final p in doc.pages) {
      if (p.id == id) return p;
    }
    return null;
  }

  // --- Build -----------------------------------------------------------------

  MouseCursor get _canvasCursor {
    if (_mode == _DragMode.panCanvas) return SystemMouseCursors.grabbing;
    if (_c.tool == EditorTool.pan) return SystemMouseCursors.grab;
    if (_c.tool == EditorTool.text) return SystemMouseCursors.text;
    if (_hoverOnQuickAddArrow) return SystemMouseCursors.click;
    if (_c.tool == EditorTool.freehand ||
        _c.tool == EditorTool.connector ||
        _mode == _DragMode.connect ||
        _hoverOnConnectPoint) {
      return SystemMouseCursors.precise;
    }
    return MouseCursor.defer;
  }

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
            if (resized) {
              _viewport = viewport;
            }
            // Fit only on first layout / page change / explicit toolbar request.
            // Re-fitting on every resize frame makes maximize/restore janky.
            if (_fitPending || pageChanged) {
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
            if (_c.textEditRequestSerial != _lastTextEditRequestSerial) {
              _lastTextEditRequestSerial = _c.textEditRequestSerial;
              final id = _c.textEditRequestShapeId;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && id != null && _editingShapeId == null) {
                  _beginTextEdit(id);
                }
              });
            }
            if (_c.fitSerial != _lastFitSerial) {
              _lastFitSerial = _c.fitSerial;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) fitToScreen();
              });
            }
            if (_c.resetViewSerial != _lastResetViewSerial) {
              _lastResetViewSerial = _c.resetViewSerial;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _resetZoom();
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
            // highlight shown while wiring a connector. On touch there is no
            // hover — arrows sit on the single selected 2-D shape instead.
            Rect? hoverBox;
            final affordanceId =
                _stencilShapeConnectionTarget?.sourceId ??
                    _connectAffordanceShapeId;
            if (affordanceId != null) {
              final s = page.findShapeById(affordanceId);
              if (s != null && !s.is1D) hoverBox = _exactContentBox(s);
            }
            final targetId =
                _stencilReplaceTargetId ?? _connectTargetId ?? _dropContainerId;
            final Rect? connectTargetRect = (targetId != null &&
                    bounds[targetId] != null)
                ? _boundsInchesToContent(bounds[targetId]!)
                : null;
            // Fixed connection points (drawio blue points) on the shape a
            // connector is being wired / dragged onto, plus the snapped one.
            // Also always shown while editing connection points on the selection.
            var connectionPointDots = const <Offset>[];
            Offset? snappedConnectionPoint;
            VsdxShape? cpShape;
            if (_c.editingConnectionPoints && _c.singleSelectedId != null) {
              cpShape = page.findShapeById(_c.singleSelectedId!);
            } else if (targetId != null &&
                (_mode == _DragMode.connect ||
                    _mode == _DragMode.moveEndpoint ||
                    (_mode == _DragMode.createShape &&
                        _c.tool == EditorTool.connector))) {
              cpShape = page.findShapeById(targetId);
            } else if (_connectAffordanceActive && _hoverShapeId != null) {
              // Blue CPs only for true hover (unselected source). Selection-
              // based touch arrows stay triangle-only so they don't fight
              // resize handles.
              cpShape = page.findShapeById(_hoverShapeId!);
            }
            if (cpShape != null && _canConnectFrom(cpShape)) {
              final t = cpShape;
              final pts = VsdxPage.effectiveConnectionPoints(t);
              connectionPointDots = <Offset>[
                for (final p in pts.map((p) => _connPointPage(t, p.offset)))
                  _pageToContent(p.x, p.y),
              ];
              final selIdx = _c.editingConnectionPoints
                  ? _c.selectedConnectionPointIndex
                  : _snapConnIndex;
              if (selIdx != null && selIdx < pts.length) {
                final pg = _connPointPage(t, pts[selIdx].offset);
                snappedConnectionPoint = _pageToContent(pg.x, pg.y);
              }
            }
            final stencilEnd = _stencilConnectorEndTarget;
            if (stencilEnd != null) {
              final point = _pageToContent(stencilEnd.x, stencilEnd.y);
              connectionPointDots = <Offset>[point];
              snappedConnectionPoint = point;
            }
            final inlineEditor = _buildInlineEditor(context);
            final guideSegments = <(Offset, Offset, SnapGuideKind)>[
              for (final g in _guides)
                g.vertical
                    ? (
                        _pageToContent(g.pos, g.start),
                        _pageToContent(g.pos, g.end),
                        g.kind,
                      )
                    : (
                        _pageToContent(g.start, g.pos),
                        _pageToContent(g.end, g.pos),
                        g.kind,
                      ),
              for (final segment in _tableDividerSegments(page))
                (
                  segment.$1,
                  segment.$2,
                  SnapGuideKind.alignment,
                ),
            ];
            final connector = _selectedConnector();
            var waypointHandles = const <Offset>[];
            var midpointHandles = const <Offset>[];
            var endpointHandles = const <Offset>[];
            Offset? connectorLabelHandle;
            Offset? connectorLabelRotateKnob;
            if (connector != null && _canEditConnector(connector)) {
              final route = _connectorControlRoutePage(connector);
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
              // Begin / end handles (drawio endpoint editing): drag to
              // reconnect to another shape or detach to a floating point.
              if (route.length >= 2) {
                endpointHandles = <Offset>[
                  _pageToContent(route.first.x, route.first.y),
                  _pageToContent(route.last.x, route.last.y),
                ];
              }
              if (_connectorHasLabel(connector)) {
                final anchors = _connectorLabelRotateAnchors(connector);
                connectorLabelHandle = anchors.$1;
                connectorLabelRotateKnob = anchors.$2;
              }
            }
            return DragTarget<ThirdPartyIcon>(
              onAcceptWithDetails: _onThirdPartyIconDropped,
              builder: (context, iconCandidate, iconRejected) =>
                  DragTarget<ImageMaterial>(
              onAcceptWithDetails: _onImageMaterialDropped,
              builder: (context, imageCandidate, imageRejected) =>
                  DragTarget<Stencil>(
              onAcceptWithDetails: _onStencilDropped,
              onMove: _onStencilMoved,
              onLeave: _onStencilLeft,
              builder: (context, candidate, rejected) => Focus(
              focusNode: _canvasFocus,
              autofocus: true,
              onKeyEvent: _onKey,
              child: Listener(
              onPointerSignal: _onPointerSignal,
              onPointerDown: _onCanvasPointerDown,
              onPointerMove: _onCanvasPointerMove,
              onPointerUp: _onCanvasPointerUp,
              onPointerCancel: _onCanvasPointerUp,
              child: MouseRegion(
              onHover: _onHover,
              onExit: (_) => _clearHover(),
              cursor: _canvasCursor,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Hit-test handles and measure movement from the pointer-down
                // position. With the default `start` behaviour, Flutter
                // reports onPanStart only after touch slop, so shapes lag the
                // pointer and a 12 px resize/rotate handle is already missed.
                dragStartBehavior: DragStartBehavior.down,
                onTapUp: _onTapUp,
                onSecondaryTapUp: _onSecondaryTapUp,
                onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
                onDoubleTap: _onDoubleTap,
                // View-only pan/pinch is handled by the outer Listener so
                // single-finger pans track 1:1 (no scale-gesture slop).
                onPanStart: _viewOnlyGestures ? null : _onPanStart,
                onPanUpdate: _viewOnlyGestures ? null : _onPanUpdate,
                onPanEnd: _viewOnlyGestures ? null : _onPanEnd,
                child: ClipRect(
                  key: _canvasBoxKey,
                  child: Stack(
                    children: [
                      Positioned.fill(child: ColoredBox(color: widget.canvasColor)),
                      Transform(
                        transform: Matrix4.identity()
                          ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
                          ..scaleByDouble(_scale, _scale, 1, 1),
                        // Let the sheet lay out at its true content size: as a
                        // non-positioned Stack child it would otherwise inherit
                        // the Stack's loose (viewport-capped) constraints and be
                        // clamped before the transform scales it — shrinking the
                        // page whenever it is larger than the canvas area (i.e.
                        // most non-maximized windows).
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: 0,
                          maxWidth: double.infinity,
                          minHeight: 0,
                          maxHeight: double.infinity,
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
                                      underlayPage: _resolvedUnderlay(doc, page),
                                      theme: doc.theme,
                                      images: doc.images,
                                      imageCache: _imageCache,
                                      patternBuilder: PatternFillBuilder.shared,
                                      pxPerInch: widget.pxPerInch,
                                      drawLineJumps: _c.showLineJumps,
                                      colorByLayer: _c.colorByLayer,
                                      lineJumpRadiusInches:
                                          _c.lineJumpRadiusInches,
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
                                      handleSize: (_isTouchUi ? 11.0 : 7.0) /
                                          _scale,
                                      previewStart: _previewStart,
                                      previewEnd: _previewEnd,
                                      previewTool: previewTool,
                                      freehandPoints: _c.tool ==
                                                  EditorTool.freehand &&
                                              _mode == _DragMode.createShape
                                          ? List<Offset>.of(_freehandPoints)
                                          : const <Offset>[],
                                      marquee: marquee,
                                      areaStart: _areaStartContent,
                                      areaEnd: _areaEndContent,
                                      guides: guideSegments,
                                      waypointHandles: waypointHandles,
                                      midpointHandles: midpointHandles,
                                      endpointHandles: endpointHandles,
                                      connectorLabelHandle:
                                          connectorLabelHandle,
                                      connectorLabelRotateKnob:
                                          connectorLabelRotateKnob,
                                      hoverBox: hoverBox,
                                      hoverArrowGap:
                                          _connectArrowGapPxEffective / _scale,
                                      connectTargetRect: connectTargetRect,
                                      connectionPoints: connectionPointDots,
                                      snappedConnectionPoint:
                                          snappedConnectionPoint,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        ),
                      ),
                      ?inlineEditor,
                      if (!widget.presentationMode)
                        Positioned(
                          right: 12,
                          // Leave room for the compact-layout format FAB
                          // (same corner) so zoom stays tappable on phones.
                          bottom: MediaQuery.sizeOf(context).width < 720
                              ? 64
                              : 12,
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
    this.freehandPoints = const <Offset>[],
    this.marquee,
    this.areaStart,
    this.areaEnd,
    this.guides = const <(Offset, Offset, SnapGuideKind)>[],
    this.waypointHandles = const <Offset>[],
    this.midpointHandles = const <Offset>[],
    this.endpointHandles = const <Offset>[],
    this.connectorLabelHandle,
    this.connectorLabelRotateKnob,
    this.hoverBox,
    this.hoverArrowGap = 0,
    this.connectTargetRect,
    this.connectionPoints = const <Offset>[],
    this.snappedConnectionPoint,
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

  /// Live freehand ink samples (content-px).
  final List<Offset> freehandPoints;

  /// Hover-connect arrow ring around the hovered shape (content-px) and the
  /// gap from its box; plus the glue-target highlight while wiring.
  final Rect? hoverBox;
  final double hoverArrowGap;
  final Rect? connectTargetRect;

  /// Fixed connection points (content-px) of the shape being wired onto, and
  /// the one the endpoint is snapping to (drawio blue points).
  final List<Offset> connectionPoints;
  final Offset? snappedConnectionPoint;

  final Rect? marquee;
  final Offset? areaStart;
  final Offset? areaEnd;

  /// Alignment guide lines (content-px), drawn while dragging a selection.
  final List<(Offset, Offset, SnapGuideKind)> guides;

  /// Connector bend points (filled) and segment midpoints (hollow), content-px.
  final List<Offset> waypointHandles;
  final List<Offset> midpointHandles;

  /// Connector begin / end handles (drawio endpoint editing), content-px.
  final List<Offset> endpointHandles;

  /// Connector label anchor (draw.io yellow diamond), content-px.
  final Offset? connectorLabelHandle;

  /// Circular connector-label rotation handle, content-px.
  final Offset? connectorLabelRotateKnob;

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
    final areaA = areaStart;
    final areaB = areaEnd;
    if (areaA != null && areaB != null) {
      final areaPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = const Color(0xFFFF9800);
      canvas
        ..drawLine(Offset(areaA.dx, 0), Offset(areaA.dx, size.height), areaPaint)
        ..drawLine(Offset(0, areaA.dy), Offset(size.width, areaA.dy), areaPaint)
        ..drawLine(Offset(areaB.dx, 0), Offset(areaB.dx, size.height), areaPaint)
        ..drawLine(Offset(0, areaB.dy), Offset(size.width, areaB.dy), areaPaint);
    }
    if (guides.isNotEmpty) {
      final guidePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      for (final (a, b, kind) in guides) {
        guidePaint.color = switch (kind) {
          SnapGuideKind.alignment => const Color(0xFF29B6F6),
          SnapGuideKind.spacing => const Color(0xFF8E5CFF),
          SnapGuideKind.pageCenter => const Color(0xFFFF9800),
        };
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
    // Connector begin / end handles (drawio green endpoints) — drag to
    // reconnect to another shape or detach to a floating point.
    if (endpointHandles.isNotEmpty) {
      final fill = Paint()..color = const Color(0xFF12B886);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = Colors.white;
      for (final c in endpointHandles) {
        canvas
          ..drawCircle(c, handleSize * 0.85, fill)
          ..drawCircle(c, handleSize * 0.85, ring);
      }
    }
    final labelHandle = connectorLabelHandle;
    final labelRotateKnob = connectorLabelRotateKnob;
    if (labelHandle != null && labelRotateKnob != null) {
      canvas
        ..drawLine(labelHandle, labelRotateKnob, outline)
        ..drawCircle(
          labelRotateKnob,
          handleSize * 0.72,
          Paint()..color = Colors.white,
        )
        ..drawCircle(labelRotateKnob, handleSize * 0.72, outline);
    }
    if (labelHandle != null) {
      final radius = handleSize * 0.9;
      final path = Path()
        ..moveTo(labelHandle.dx, labelHandle.dy - radius)
        ..lineTo(labelHandle.dx + radius, labelHandle.dy)
        ..lineTo(labelHandle.dx, labelHandle.dy + radius)
        ..lineTo(labelHandle.dx - radius, labelHandle.dy)
        ..close();
      canvas
        ..drawPath(path, Paint()..color = const Color(0xFFFFC107))
        ..drawPath(path, outline);
    }
    _paintConnectTarget(canvas);
    _paintConnectionPoints(canvas);
    _paintHoverArrows(canvas);
    _paintPreview(canvas, outline);
  }

  /// Fixed connection points on the shape a connector is being wired onto —
  /// drawio-style blue crosses, with a filled halo on the snapped one.
  void _paintConnectionPoints(Canvas canvas) {
    if (connectionPoints.isEmpty) return;
    const blue = Color(0xFF1565C0);
    final arm = handleSize * 0.6;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 1.2
      ..color = blue;
    for (final c in connectionPoints) {
      canvas
        ..drawLine(Offset(c.dx - arm, c.dy - arm), Offset(c.dx + arm, c.dy + arm),
            stroke)
        ..drawLine(Offset(c.dx - arm, c.dy + arm), Offset(c.dx + arm, c.dy - arm),
            stroke);
    }
    final snapped = snappedConnectionPoint;
    if (snapped != null) {
      canvas
        ..drawCircle(snapped, handleSize * 0.9, Paint()..color = blue)
        ..drawCircle(
            snapped,
            handleSize * 0.9,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..color = Colors.white);
    }
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

  /// Directional quick-add arrows around the hovered shape (EdrawMax / draw.io).
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
    final tool = previewTool;
    if (tool == EditorTool.freehand) {
      if (freehandPoints.length < 2) return;
      final path = Path()..moveTo(freehandPoints.first.dx, freehandPoints.first.dy);
      for (var i = 1; i < freehandPoints.length; i++) {
        path.lineTo(freehandPoints[i].dx, freehandPoints[i].dy);
      }
      final end = previewEnd;
      if (end != null && end != freehandPoints.last) {
        path.lineTo(end.dx, end.dy);
      }
      canvas.drawPath(path, outline);
      return;
    }
    final a = previewStart;
    final b = previewEnd;
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
      case EditorTool.pan:
      case EditorTool.freehand:
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
      old.areaStart != areaStart ||
      old.areaEnd != areaEnd ||
      old.hoverBox != hoverBox ||
      old.hoverArrowGap != hoverArrowGap ||
      old.connectTargetRect != connectTargetRect ||
      old.snappedConnectionPoint != snappedConnectionPoint ||
      !listEquals(old.guides, guides) ||
      !listEquals(old.waypointHandles, waypointHandles) ||
      !listEquals(old.midpointHandles, midpointHandles) ||
      !listEquals(old.endpointHandles, endpointHandles) ||
      old.connectorLabelHandle != connectorLabelHandle ||
      old.connectorLabelRotateKnob != connectorLabelRotateKnob ||
      !listEquals(old.connectionPoints, connectionPoints) ||
      !listEquals(old.freehandPoints, freehandPoints);
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
            onPressed: onFit,
            icon: const Icon(Icons.fit_screen_outlined),
            tooltip: EditorL10n.of(context).fitToWindowShortcut,
          ),
          const VerticalDivider(width: 1, indent: 8, endIndent: 8),
          IconButton(
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove),
            tooltip: EditorL10n.of(context).zoomOut,
          ),
          Tooltip(
            message: EditorL10n.of(context).fitToWindow,
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
            tooltip: EditorL10n.of(context).zoomIn,
          ),
        ],
      ),
    );
  }
}
