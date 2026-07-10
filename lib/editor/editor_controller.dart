import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vsdx/vsdx.dart';

/// Editing tools the canvas can be in.
enum EditorTool { select, rectangle, ellipse, line, connector }

/// Central editor state: the parsed [VsdxDocument], current page, selection,
/// and an undo/redo history built on immutable document snapshots.
///
/// Snapshots are cheap because the model is immutable with structural sharing
/// ([VsdxDocument.replacePage] / [VsdxShape.copyWith] only allocate the nodes
/// that actually change), so each history entry shares the untouched subtree
/// with its neighbours.
class EditorController extends ChangeNotifier {
  VsdxDocument? _document;
  Uint8List? _originalBytes;
  String? _filePath;
  String? _fileName;
  int _currentPageIndex = 0;
  bool _isLoading = false;
  Object? _error;

  EditorTool _tool = EditorTool.select;
  bool _showGrid = true;
  bool _snapToGrid = true;
  final double _gridInches = 0.25;
  final Set<int> _selection = <int>{};
  final List<VsdxDocument> _undo = <VsdxDocument>[];
  final List<VsdxDocument> _redo = <VsdxDocument>[];
  VsdxDocument? _txnBase;
  bool _dirty = false;

  VsdxDocument? get document => _document;
  Uint8List? get originalBytes => _originalBytes;
  String? get filePath => _filePath;
  String? get fileName => _fileName;
  bool get isLoading => _isLoading;
  Object? get error => _error;
  bool get hasDocument => _document != null;
  bool get isDirty => _dirty;

  int get pageCount => _document?.pages.length ?? 0;
  int get currentPageIndex => _currentPageIndex;

  VsdxPage? get currentPage {
    final doc = _document;
    if (doc == null || doc.pages.isEmpty) return null;
    final i = _currentPageIndex.clamp(0, doc.pages.length - 1);
    return doc.pages[i];
  }

  void selectPage(int index) {
    if (index < 0 || index >= pageCount || index == _currentPageIndex) return;
    _currentPageIndex = index;
    _selection.clear();
    notifyListeners();
  }

  /// Rename the page at [index] (persists as `<Page NameU>` via the writer).
  void renamePageAt(int index, String name) {
    final doc = _document;
    if (doc == null || index < 0 || index >= doc.pages.length) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == doc.pages[index].name) return;
    applyEdit(doc.replacePage(index, doc.pages[index].copyWith(name: trimmed)));
  }

  /// Add a new blank page after the current one and switch to it.
  void addPage() {
    final doc = _document;
    if (doc == null) return;
    final base = currentPage;
    final page = VsdxPage(
      id: doc.nextPageId(),
      name: _uniquePageName(doc, 'Page-${doc.pages.length + 1}'),
      widthInches: base?.widthInches ?? 8.5,
      heightInches: base?.heightInches ?? 11.0,
      shapes: const <VsdxShape>[],
    );
    final at = _currentPageIndex + 1;
    _selection.clear();
    _currentPageIndex = at;
    applyEdit(doc.insertPage(at, page));
  }

  /// Duplicate the current page (new id, copied shapes) after it, and switch.
  void duplicateCurrentPage() {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null) return;
    final copy = page.copyWith(
      id: doc.nextPageId(),
      name: _uniquePageName(doc, '${page.name} copy'),
    );
    final at = _currentPageIndex + 1;
    _selection.clear();
    _currentPageIndex = at;
    applyEdit(doc.insertPage(at, copy));
  }

  /// Delete the current page (keeps at least one page).
  void deleteCurrentPage() {
    final doc = _document;
    if (doc == null || doc.pages.length <= 1) return;
    final i = _currentPageIndex;
    _selection.clear();
    final next = doc.removePageAt(i);
    _currentPageIndex = i.clamp(0, next.pages.length - 1);
    applyEdit(next);
  }

  static String _uniquePageName(VsdxDocument doc, String base) {
    final names = <String>{for (final p in doc.pages) p.name};
    if (!names.contains(base)) return base;
    var n = 2;
    while (names.contains('$base $n')) {
      n++;
    }
    return '$base $n';
  }

  // --- Tool ------------------------------------------------------------------

  EditorTool get tool => _tool;

  void setTool(EditorTool tool) {
    if (_tool == tool) return;
    _tool = tool;
    notifyListeners();
  }

  // --- Grid / snapping -------------------------------------------------------

  bool get showGrid => _showGrid;
  bool get snapToGrid => _snapToGrid;
  double get gridInches => _gridInches;

  void toggleGrid() {
    _showGrid = !_showGrid;
    notifyListeners();
  }

  void toggleSnap() {
    _snapToGrid = !_snapToGrid;
    notifyListeners();
  }

  /// Snap an inch coordinate to the grid when snapping is enabled.
  double snap(double v) =>
      _snapToGrid ? (v / _gridInches).roundToDouble() * _gridInches : v;

  // --- Selection -------------------------------------------------------------

  Set<int> get selection => Set<int>.unmodifiable(_selection);
  bool get hasSelection => _selection.isNotEmpty;
  bool isSelected(int shapeId) => _selection.contains(shapeId);

  void selectOnly(int shapeId) {
    if (_selection.length == 1 && _selection.contains(shapeId)) return;
    _selection
      ..clear()
      ..add(shapeId);
    notifyListeners();
  }

  void toggleSelection(int shapeId) {
    if (!_selection.remove(shapeId)) _selection.add(shapeId);
    notifyListeners();
  }

  void clearSelection() {
    if (_selection.isEmpty) return;
    _selection.clear();
    notifyListeners();
  }

  void setSelection(Iterable<int> ids) {
    _selection
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  // --- Layers ----------------------------------------------------------------

  bool get hasLayers => currentPage?.layers.isNotEmpty ?? false;

  /// Toggle a layer's visibility on the current page (persists via the writer).
  void toggleLayerVisibility(int layerId) {
    updateCurrentPage(
      (page) => page.copyWith(
        layers: <VsdxLayer>[
          for (final l in page.layers)
            if (l.id == layerId) l.copyWith(visible: !l.visible) else l,
        ],
      ),
    );
  }

  // --- Undo / redo -----------------------------------------------------------

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Apply a discrete edit that becomes a single undo step.
  void applyEdit(VsdxDocument next) {
    final cur = _document;
    if (cur == null || identical(cur, next)) return;
    _undo.add(cur);
    _redo.clear();
    _document = next;
    _dirty = true;
    notifyListeners();
  }

  /// Snapshot the document at the start of a continuous gesture (e.g. a drag).
  void beginTransaction() {
    _txnBase ??= _document;
  }

  /// Update the live document during a gesture without pushing history.
  void updateTransient(VsdxDocument next) {
    if (_document == null || identical(_document, next)) return;
    _document = next;
    notifyListeners();
  }

  /// Close a gesture, recording one undo step if anything actually changed.
  void commitTransaction() {
    final base = _txnBase;
    _txnBase = null;
    if (base != null && !identical(base, _document)) {
      _undo.add(base);
      _redo.clear();
      _dirty = true;
    }
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty || _document == null) return;
    _redo.add(_document!);
    _document = _undo.removeLast();
    _dirty = true;
    _pruneSelection();
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty || _document == null) return;
    _undo.add(_document!);
    _document = _redo.removeLast();
    _dirty = true;
    _pruneSelection();
    notifyListeners();
  }

  // --- Editing helpers -------------------------------------------------------

  /// Replace the current page via [update]. When [transient] the change does
  /// not create its own history entry (used mid-drag between
  /// [beginTransaction] and [commitTransaction]).
  void updateCurrentPage(
    VsdxPage Function(VsdxPage page) update, {
    bool transient = false,
  }) {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null) return;
    final newPage = update(page);
    if (identical(newPage, page)) return;
    final next = doc.replacePage(_currentPageIndex, newPage);
    if (transient) {
      updateTransient(next);
    } else {
      applyEdit(next);
    }
  }

  /// Translate every selected shape by [dxInches] / [dyInches] (page space).
  void moveSelectionBy(
    double dxInches,
    double dyInches, {
    bool transient = false,
  }) {
    if (_selection.isEmpty || (dxInches == 0 && dyInches == 0)) return;
    updateCurrentPage(
      (page) {
        var next = page;
        for (final id in _selection) {
          next = next.updateShapeById(
            id,
            (s) => _translated(s, dxInches, dyInches),
          );
        }
        return next.rerouteConnectors();
      },
      transient: transient,
    );
  }

  /// Create a shape for the current [tool] from a drag in page inches. A tiny
  /// drag (a click) yields a sensibly-sized default. Resets to the select tool
  /// and selects the new shape.
  void createShapeByDrag(double sx, double sy, double ex, double ey) {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null || _tool == EditorTool.select) return;
    sx = snap(sx);
    sy = snap(sy);
    ex = snap(ex);
    ey = snap(ey);
    final id = page.nextFreeShapeId();

    final VsdxShape shape;
    if (_tool == EditorTool.line) {
      var bx = ex;
      var by = ey;
      if ((bx - sx).abs() < 0.1 && (by - sy).abs() < 0.1) {
        bx = sx + 1.5;
        by = sy;
      }
      shape = VsdxShapeFactory.line(id: id, ax: sx, ay: sy, bx: bx, by: by);
    } else {
      var left = math.min(sx, ex);
      var bottom = math.min(sy, ey);
      var w = (math.max(sx, ex) - left).abs();
      var h = (math.max(sy, ey) - bottom).abs();
      if (w < 0.1 && h < 0.1) {
        w = 1.5;
        h = 0.75;
        left = sx - w / 2;
        bottom = sy - h / 2;
      } else {
        w = math.max(w, 0.05);
        h = math.max(h, 0.05);
      }
      final pinX = left + w / 2;
      final pinY = bottom + h / 2;
      shape = _tool == EditorTool.rectangle
          ? VsdxShapeFactory.rectangle(
              id: id, pinX: pinX, pinY: pinY, width: w, height: h)
          : VsdxShapeFactory.ellipse(
              id: id, pinX: pinX, pinY: pinY, width: w, height: h);
    }

    _selection
      ..clear()
      ..add(id);
    _tool = EditorTool.select;
    applyEdit(doc.replacePage(_currentPageIndex, page.addShape(shape)));
  }

  /// Create a connector line between two page points. When [beginTarget] /
  /// [endTarget] name a shape, that end is glued (a `<Connect>` row is added
  /// and the endpoint snaps to the shape's centre; it follows on later moves).
  void createConnector(
    double ax,
    double ay,
    double bx,
    double by, {
    int? beginTarget,
    int? endTarget,
  }) {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null) return;
    final id = page.nextFreeShapeId();
    var sax = ax, say = ay, sbx = bx, sby = by;
    if (beginTarget != null) {
      final t = page.findShapeById(beginTarget);
      if (t != null) {
        sax = t.pinX;
        say = t.pinY;
      }
    }
    if (endTarget != null) {
      final t = page.findShapeById(endTarget);
      if (t != null) {
        sbx = t.pinX;
        sby = t.pinY;
      }
    }
    final connector =
        VsdxShapeFactory.line(id: id, ax: sax, ay: say, bx: sbx, by: sby);
    final connects = <VsdxConnect>[
      ...page.connects,
      if (beginTarget != null)
        VsdxConnect(
          fromSheetId: id,
          fromCell: 'BeginX',
          fromPart: 9,
          toSheetId: beginTarget,
          toCell: 'PinX',
          toPart: 3,
        ),
      if (endTarget != null)
        VsdxConnect(
          fromSheetId: id,
          fromCell: 'EndX',
          fromPart: 12,
          toSheetId: endTarget,
          toCell: 'PinX',
          toPart: 3,
        ),
    ];
    _selection
      ..clear()
      ..add(id);
    _tool = EditorTool.select;
    applyEdit(
      doc.replacePage(
        _currentPageIndex,
        page.addShape(connector).copyWith(connects: connects).rerouteConnectors(),
      ),
    );
  }

  /// Add a shape produced by [build] at the current page's centre, select it.
  void addShapeFromBuilder(
    VsdxShape Function(int id, double cx, double cy) build,
  ) {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null) return;
    final id = page.nextFreeShapeId();
    final shape = build(id, page.widthInches / 2, page.heightInches / 2);
    _selection
      ..clear()
      ..add(id);
    _tool = EditorTool.select;
    applyEdit(doc.replacePage(_currentPageIndex, page.addShape(shape)));
  }

  /// Delete all selected shapes as a single undo step.
  void deleteSelection() {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null || _selection.isEmpty) return;
    var next = page;
    for (final id in _selection) {
      next = next.removeShapeById(id);
    }
    if (identical(next, page)) return;
    _selection.clear();
    applyEdit(doc.replacePage(_currentPageIndex, next));
  }

  List<VsdxShape> _clipboard = const <VsdxShape>[];
  bool get hasClipboard => _clipboard.isNotEmpty;

  /// Copy the current selection into the in-app clipboard.
  void copySelection() {
    final page = currentPage;
    if (page == null || _selection.isEmpty) return;
    _clipboard = <VsdxShape>[
      for (final id in _selection)
        if (page.findShapeById(id) != null) page.findShapeById(id)!,
    ];
  }

  /// Paste clipboard shapes onto the current page (offset, freshly id'd).
  void paste() {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null || _clipboard.isEmpty) return;
    var next = page;
    final newIds = <int>{};
    for (final s in _clipboard) {
      final newId = next.nextFreeShapeId();
      next = next.addShape(
        s.copyWith(id: newId, pinX: s.pinX + 0.25, pinY: s.pinY - 0.25),
      );
      newIds.add(newId);
    }
    _selection
      ..clear()
      ..addAll(newIds);
    applyEdit(doc.replacePage(_currentPageIndex, next));
  }

  /// Duplicate the current selection, offset slightly, selecting the copies.
  void duplicateSelection() {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null || _selection.isEmpty) return;
    var next = page;
    final newIds = <int>{};
    for (final id in _selection.toList()) {
      final s = page.findShapeById(id);
      if (s == null) continue;
      final newId = next.nextFreeShapeId();
      next = next.addShape(
        s.copyWith(id: newId, pinX: s.pinX + 0.25, pinY: s.pinY - 0.25),
      );
      newIds.add(newId);
    }
    if (identical(next, page)) return;
    _selection
      ..clear()
      ..addAll(newIds);
    applyEdit(doc.replacePage(_currentPageIndex, next));
  }

  // --- Align / distribute ----------------------------------------------------

  /// Axis-aligned bounding box of [s] in page inches as (left, bottom, right,
  /// top), accounting for rotation.
  static (double, double, double, double) _bounds(VsdxShape s) {
    if (s.angleRad == 0) {
      return (
        s.pinX - s.width / 2,
        s.pinY - s.height / 2,
        s.pinX + s.width / 2,
        s.pinY + s.height / 2,
      );
    }
    final c = math.cos(s.angleRad);
    final sn = math.sin(s.angleRad);
    final hw = s.width / 2;
    final hh = s.height / 2;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final ox in <double>[-hw, hw]) {
      for (final oy in <double>[-hh, hh]) {
        final x = s.pinX + ox * c - oy * sn;
        final y = s.pinY + ox * sn + oy * c;
        minX = math.min(minX, x);
        maxX = math.max(maxX, x);
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
      }
    }
    return (minX, minY, maxX, maxY);
  }

  void _align(Map<int, (double, double)> Function(List<VsdxShape>) compute) {
    final page = currentPage;
    if (page == null) return;
    final shapes = <VsdxShape>[
      for (final id in _selection)
        if (page.findShapeById(id) != null) page.findShapeById(id)!,
    ];
    if (shapes.length < 2) return;
    final deltas = compute(shapes);
    if (deltas.isEmpty) return;
    updateCurrentPage((p) {
      var next = p;
      deltas.forEach((id, d) {
        next = next.updateShapeById(
          id,
          (s) => s.copyWith(pinX: s.pinX + d.$1, pinY: s.pinY + d.$2),
        );
      });
      return next.rerouteConnectors();
    });
  }

  void alignLeft() => _align((shapes) {
        final target = shapes.map((s) => _bounds(s).$1).reduce(math.min);
        return {for (final s in shapes) s.id: (target - _bounds(s).$1, 0.0)};
      });

  void alignRight() => _align((shapes) {
        final target = shapes.map((s) => _bounds(s).$3).reduce(math.max);
        return {for (final s in shapes) s.id: (target - _bounds(s).$3, 0.0)};
      });

  void alignCenterH() => _align((shapes) {
        final l = shapes.map((s) => _bounds(s).$1).reduce(math.min);
        final r = shapes.map((s) => _bounds(s).$3).reduce(math.max);
        final target = (l + r) / 2;
        return {for (final s in shapes) s.id: (target - s.pinX, 0.0)};
      });

  void alignTop() => _align((shapes) {
        final target = shapes.map((s) => _bounds(s).$4).reduce(math.max);
        return {for (final s in shapes) s.id: (0.0, target - _bounds(s).$4)};
      });

  void alignBottom() => _align((shapes) {
        final target = shapes.map((s) => _bounds(s).$2).reduce(math.min);
        return {for (final s in shapes) s.id: (0.0, target - _bounds(s).$2)};
      });

  void alignMiddle() => _align((shapes) {
        final b = shapes.map((s) => _bounds(s).$2).reduce(math.min);
        final t = shapes.map((s) => _bounds(s).$4).reduce(math.max);
        final target = (b + t) / 2;
        return {for (final s in shapes) s.id: (0.0, target - s.pinY)};
      });

  void distributeHorizontally() => _align((shapes) {
        if (shapes.length < 3) return const {};
        final sorted = [...shapes]..sort((a, b) => a.pinX.compareTo(b.pinX));
        final first = sorted.first.pinX;
        final step = (sorted.last.pinX - first) / (sorted.length - 1);
        return {
          for (var i = 0; i < sorted.length; i++)
            sorted[i].id: (first + i * step - sorted[i].pinX, 0.0),
        };
      });

  void distributeVertically() => _align((shapes) {
        if (shapes.length < 3) return const {};
        final sorted = [...shapes]..sort((a, b) => a.pinY.compareTo(b.pinY));
        final first = sorted.first.pinY;
        final step = (sorted.last.pinY - first) / (sorted.length - 1);
        return {
          for (var i = 0; i < sorted.length; i++)
            sorted[i].id: (0.0, first + i * step - sorted[i].pinY),
        };
      });

  void bringSelectionToFront() {
    if (_selection.isEmpty) return;
    updateCurrentPage((page) {
      var next = page;
      for (final id in _selection) {
        next = next.bringToFront(id);
      }
      return next;
    });
  }

  void sendSelectionToBack() {
    if (_selection.isEmpty) return;
    updateCurrentPage((page) {
      var next = page;
      for (final id in _selection) {
        next = next.sendToBack(id);
      }
      return next;
    });
  }

  void _updateSelectedShapes(VsdxShape Function(VsdxShape) update) {
    if (_selection.isEmpty) return;
    updateCurrentPage((page) {
      var next = page;
      for (final id in _selection) {
        next = next.updateShapeById(id, update);
      }
      return next;
    });
  }

  void setFillColor(VsdxColor color) => _updateSelectedShapes(
        (s) => s.copyWith(
          fill: s.fill.copyWith(
            foreground: color,
            pattern: s.fill.pattern == 0 ? 1 : s.fill.pattern,
          ),
        ),
      );

  void setNoFill() =>
      _updateSelectedShapes((s) => s.copyWith(fill: s.fill.copyWith(pattern: 0)));

  void setLineColor(VsdxColor color) => _updateSelectedShapes(
        (s) => s.copyWith(
          line: s.line.copyWith(
            color: color,
            pattern: s.line.pattern == 0 ? 1 : s.line.pattern,
          ),
        ),
      );

  void setLineWeight(double inches) => _updateSelectedShapes(
        (s) => s.copyWith(
          line: s.line.copyWith(
            weightInches: inches,
            pattern: s.line.pattern == 0 ? 1 : s.line.pattern,
          ),
        ),
      );

  void setNoLine() =>
      _updateSelectedShapes((s) => s.copyWith(line: s.line.copyWith(pattern: 0)));

  void setShapeText(int id, String text) => updateCurrentPage(
        (page) => page.updateShapeById(id, (s) => s.copyWith(text: text)),
      );

  // --- Text formatting (applies to the whole text of selected shapes) --------

  VsdxCharStyle? get selectedCharStyle {
    final page = currentPage;
    if (page == null) return null;
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null && s.richText.runs.isNotEmpty) {
        return s.richText.runs.first.charStyle;
      }
    }
    return null;
  }

  VsdxHorzAlign? get selectedAlign {
    final page = currentPage;
    if (page == null) return null;
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null && s.richText.runs.isNotEmpty) {
        return s.richText.runs.first.paraStyle.horizontalAlign;
      }
    }
    return null;
  }

  void _updateText({
    VsdxCharStyle Function(VsdxCharStyle)? char,
    VsdxParaStyle Function(VsdxParaStyle)? para,
  }) {
    _updateSelectedShapes((s) {
      var runs = s.richText.runs;
      if (runs.isEmpty) {
        final t = s.text;
        if (t == null || t.isEmpty) return s;
        runs = <VsdxTextRun>[VsdxTextRun(text: t)];
      }
      final newRuns = <VsdxTextRun>[
        for (final r in runs)
          r.copyWith(
            charStyle: char != null ? char(r.charStyle) : null,
            paraStyle: para != null ? para(r.paraStyle) : null,
          ),
      ];
      return s.copyWith(richText: s.richText.copyWith(runs: newRuns));
    });
  }

  void setTextSizeInches(double inches) =>
      _updateText(char: (c) => c.copyWith(fontSizeInches: inches));

  void setBold(bool value) =>
      _updateText(char: (c) => c.copyWith(style: c.style.copyWith(bold: value)));

  void setItalic(bool value) => _updateText(
      char: (c) => c.copyWith(style: c.style.copyWith(italic: value)));

  void setTextColor(VsdxColor color) =>
      _updateText(char: (c) => c.copyWith(color: color));

  void setTextAlign(VsdxHorzAlign align) =>
      _updateText(para: (p) => p.copyWith(horizontalAlign: align));

  /// Rotate a single shape about its pin (radians, Visio CCW convention).
  void rotateShape(int id, double angleRad, {bool transient = false}) {
    updateCurrentPage(
      (page) => page
          .updateShapeById(id, (s) => s.copyWith(angleRad: angleRad))
          .rerouteConnectors(),
      transient: transient,
    );
  }

  /// Resize a single shape (used by the canvas resize handles); geometry is
  /// scaled to fill the new box.
  void resizeShape(
    int id, {
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    bool transient = false,
  }) {
    updateCurrentPage(
      (page) => page
          .updateShapeById(
            id,
            (s) => s.resizeTo(
              pinX: pinX,
              pinY: pinY,
              width: width,
              height: height,
            ),
          )
          .rerouteConnectors(),
      transient: transient,
    );
  }

  static VsdxShape _translated(VsdxShape s, double dx, double dy) {
    return s.copyWith(
      pinX: s.pinX + dx,
      pinY: s.pinY + dy,
      beginX: s.beginX == null ? null : s.beginX! + dx,
      beginY: s.beginY == null ? null : s.beginY! + dy,
      endX: s.endX == null ? null : s.endX! + dx,
      endY: s.endY == null ? null : s.endY! + dy,
    );
  }

  // --- Save / export ---------------------------------------------------------

  /// Serialise the current document back to `.vsdx` bytes (round-trip writer).
  /// Throws [StateError] when there is nothing to export.
  Uint8List exportToBytes() {
    final doc = _document;
    final orig = _originalBytes;
    if (doc == null || orig == null) {
      throw StateError('No document to export');
    }
    return const VsdxWriter().write(originalBytes: orig, edited: doc);
  }

  /// Record that [savedBytes] were persisted: they become the new baseline for
  /// subsequent saves and the dirty flag is cleared.
  void markSaved(Uint8List savedBytes, {String? path, String? name}) {
    _originalBytes = savedBytes;
    if (path != null) _filePath = path;
    _fileName = name ?? _basename(_filePath) ?? _fileName;
    _dirty = false;
    notifyListeners();
  }

  void _pruneSelection() {
    final page = currentPage;
    if (page == null) {
      _selection.clear();
      return;
    }
    _selection.removeWhere((id) => page.findShapeById(id) == null);
  }

  // --- File lifecycle --------------------------------------------------------

  /// Start a new, empty in-memory drawing. Saving later prompts for a path
  /// (Save As) and writes a valid `.vsdx`.
  void newDocument({double widthInches = 8.5, double heightInches = 11.0}) {
    final bytes = const VsdxWriter()
        .emptyDocument(widthInches: widthInches, heightInches: heightInches);
    _document = const DocumentParser().parse(bytes);
    _originalBytes = bytes;
    _filePath = null;
    _fileName = 'Untitled.vsdx';
    _currentPageIndex = 0;
    _error = null;
    _resetHistory();
    notifyListeners();
  }

  /// Parse [bytes] into a document and make it the active file.
  Future<void> openBytes(
    Uint8List bytes, {
    String? path,
    String? name,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final doc = const DocumentParser().parse(bytes);
      _document = doc;
      _originalBytes = bytes;
      _filePath = path;
      _fileName = name ?? _basename(path);
      _currentPageIndex = 0;
      _resetHistory();
    } catch (e) {
      _error = e;
      _document = null;
      _originalBytes = null;
      _filePath = null;
      _fileName = null;
      _resetHistory();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void closeDocument() {
    _document = null;
    _originalBytes = null;
    _filePath = null;
    _fileName = null;
    _currentPageIndex = 0;
    _error = null;
    _resetHistory();
    notifyListeners();
  }

  void _resetHistory() {
    _selection.clear();
    _undo.clear();
    _redo.clear();
    _txnBase = null;
    _dirty = false;
  }

  static String? _basename(String? path) {
    if (path == null) return null;
    final i = path.lastIndexOf(RegExp(r'[/\\]'));
    return i < 0 ? path : path.substring(i + 1);
  }
}
