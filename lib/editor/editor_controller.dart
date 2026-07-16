import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vsdx/vsdx.dart';

import '../render/shape_bounds.dart';
import 'shape_clipboard.dart';
import 'snap_guides.dart';

/// Editing tools the canvas can be in.
enum EditorTool {
  select,
  rectangle,
  ellipse,
  line,
  connector,
  text,
  /// Draw.io Freehand / scribble — drag to paint a 1-D polyline stroke.
  freehand,
}

/// Connector routing style — mirrors drawio's Straight / Orthogonal / Curved
/// edge styles. [curved] smooths the orthogonal control points into a spline.
enum ConnectorRouteStyle { straight, orthogonal, curved }

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
  bool _showLineJumps = true;
  double _lineJumpRadiusInches = 0.07;
  final double _gridInches = 0.25;
  final Set<int> _selection = <int>{};
  final List<VsdxDocument> _undo = <VsdxDocument>[];
  final List<VsdxDocument> _redo = <VsdxDocument>[];
  VsdxDocument? _txnBase;
  bool _dirty = false;

  // Reveal ("scroll into view") requests: the canvas watches [revealSerial]
  // and, when it changes, centres on [revealShapeId] (or the selection when
  // that is null). Used by Find and "Zoom to selection".
  int _revealSerial = 0;
  int? _revealShapeId;
  Offset2D? _revealPoint; // page-inch point to centre on (Outline navigation)

  // Find state (draw.io Ctrl+F): query, match-case / whole-word flags, and hits
  // across every page as (pageIndex, shapeId) pairs plus the current index.
  String _findQuery = '';
  bool _findMatchCase = false;
  bool _findWholeWord = false;
  List<({int pageIndex, int shapeId})> _findMatches =
      const <({int pageIndex, int shapeId})>[];
  int _findIndex = -1;

  // Style memory (drawio currentVertexStyle): the fill / line last applied to a
  // shape, inherited by newly-created shapes. Reset per document.
  VsdxFill? _memoFill;
  VsdxLine? _memoLine;

  // Monotonic counter for minting fresh `/visio/media/imageN.ext` part names on
  // image insert. Lives outside the document snapshot so it keeps climbing
  // across undo/redo — that way a re-inserted image never reuses a part name
  // (and so never collides with a stale entry in the render image cache).
  int _imageSeq = 0;

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
    _leaveConnectionPointEdit();
    _currentPageIndex = index;
    _selection.clear();
    _clearFindState();
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

  /// Reorder pages (draw.io page-tab drag). Keeps the active page selected by
  /// id so the canvas does not jump to a different sheet.
  void movePage(int from, int to) {
    final doc = _document;
    if (doc == null) return;
    if (from < 0 ||
        from >= doc.pages.length ||
        to < 0 ||
        to >= doc.pages.length ||
        from == to) {
      return;
    }
    final currentId = doc.pages[_currentPageIndex].id;
    final next = doc.movePage(from, to);
    if (identical(next, doc)) return;
    final newIdx = next.pages.indexWhere((p) => p.id == currentId);
    _currentPageIndex = newIdx >= 0 ? newIdx : 0;
    _selection.clear();
    _clearFindState();
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

  // --- Page setup (drawio "Diagram" tab: paper size / orientation / bg) ------

  /// Size of the current page in inches, or `null` when no document is open.
  ({double width, double height})? get pageSize {
    final p = currentPage;
    return p == null ? null : (width: p.widthInches, height: p.heightInches);
  }

  /// Whether the current page is wider than it is tall (drawio Landscape).
  bool get pageIsLandscape {
    final p = currentPage;
    return p != null && p.widthInches > p.heightInches;
  }

  /// The current page's background colour, or `null` when it inherits the
  /// document default (white).
  VsdxColor? get pageBackgroundColor => currentPage?.backgroundColor;

  /// Resize the current page to [widthInches] × [heightInches] (drawio Paper
  /// Size). Persists via the PageSheet's `PageWidth` / `PageHeight` cells.
  void setPageSize(double widthInches, double heightInches) {
    final w = widthInches.clamp(1.0, 400.0);
    final h = heightInches.clamp(1.0, 400.0);
    updateCurrentPage((page) {
      if ((page.widthInches - w).abs() < _epsilon &&
          (page.heightInches - h).abs() < _epsilon) {
        return page;
      }
      return page.copyWith(widthInches: w, heightInches: h);
    });
  }

  /// Set the current page's orientation, swapping its width/height so the
  /// paper size is preserved (drawio Portrait / Landscape).
  void setPageLandscape(bool landscape) {
    final p = currentPage;
    if (p == null || (p.widthInches > p.heightInches) == landscape) return;
    setPageSize(p.heightInches, p.widthInches);
  }

  /// Set the current page's background fill (drawio Background). Persists via
  /// the PageSheet's `PageColor` cell.
  void setBackgroundColor(VsdxColor color) {
    updateCurrentPage((page) {
      if (page.backgroundColor?.value == color.value) return page;
      return page.copyWith(backgroundColor: color);
    });
  }

  /// Mark / unmark the current page as a Visio background page (`Background="1"`).
  /// When marking, clears any BackPage reference on this page (a page cannot be
  /// both a background and a consumer of another).
  void setPageIsBackground(bool value) {
    updateCurrentPage((page) {
      if (page.isBackgroundPage == value) return page;
      if (value) {
        return page.copyWith(
          isBackgroundPage: true,
          backgroundPageId: null,
        );
      }
      return page.copyWith(isBackgroundPage: false);
    });
  }

  /// Assign [pageId] as this page's Visio `BackPage` (drawio background page),
  /// or `null` to clear. Rejects self-reference and unknown ids. When assigning,
  /// the target page is marked `Background="1"` (and its own BackPage cleared)
  /// in the same undo step — matching Visio's background-page contract.
  void setBackgroundPage(int? pageId) {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null) return;
    if (pageId == page.id) return;
    if (pageId != null && !doc.pages.any((p) => p.id == pageId)) return;
    if (page.backgroundPageId == pageId) return;

    var next = doc.replacePage(
      _currentPageIndex,
      page.copyWith(
        backgroundPageId: pageId,
        // A foreground page that uses a BackPage is not itself a background.
        isBackgroundPage: pageId != null ? false : page.isBackgroundPage,
      ),
    );
    if (pageId != null) {
      final bi = next.pages.indexWhere((p) => p.id == pageId);
      if (bi >= 0) {
        final bp = next.pages[bi];
        if (!bp.isBackgroundPage || bp.backgroundPageId != null) {
          next = next.replacePage(
            bi,
            bp.copyWith(isBackgroundPage: true, backgroundPageId: null),
          );
        }
      }
    }
    applyEdit(next);
  }

  /// Other pages that can be chosen as this page's Visio BackPage.
  List<VsdxPage> get backgroundPageOptions {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null) return const <VsdxPage>[];
    return <VsdxPage>[
      for (final p in doc.pages)
        if (p.id != page.id) p,
    ];
  }

  /// Resolved background page for the current page, or `null`.
  VsdxPage? get resolvedBackgroundPage {
    final doc = _document;
    final page = currentPage;
    final id = page?.backgroundPageId;
    if (doc == null || id == null) return null;
    for (final p in doc.pages) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Document theme palette currently in use (may be empty).
  VsdxTheme get documentTheme => _document?.theme ?? VsdxTheme.empty;

  /// Install a document theme palette (draw.io theme gallery). Theme-slot
  /// fills / lines / text on shapes resolve against this map at paint time.
  void setDocumentTheme(VsdxTheme theme) {
    final doc = _document;
    if (doc == null) return;
    if (identical(doc.theme, theme) ||
        (doc.theme.colors.length == theme.colors.length &&
            doc.theme.colors.entries
                .every((e) => theme.colors[e.key]?.value == e.value.value))) {
      return;
    }
    applyEdit(doc.copyWith(theme: theme));
  }

  static const double _epsilon = 1e-9;

  // --- Tool ------------------------------------------------------------------

  EditorTool get tool => _tool;

  void setTool(EditorTool tool) {
    if (_tool == tool) return;
    _leaveConnectionPointEdit();
    _tool = tool;
    notifyListeners();
  }

  // --- Grid / snapping -------------------------------------------------------

  bool get showGrid => _showGrid;
  bool get snapToGrid => _snapToGrid;
  bool get showLineJumps => _showLineJumps;
  double get lineJumpRadiusInches => _lineJumpRadiusInches;
  double get gridInches => _gridInches;

  void toggleGrid() {
    _showGrid = !_showGrid;
    notifyListeners();
  }

  void toggleSnap() {
    _snapToGrid = !_snapToGrid;
    notifyListeners();
  }

  /// Toggle drawio-style line jumps (arc connectors over the ones they cross).
  void toggleLineJumps() {
    _showLineJumps = !_showLineJumps;
    notifyListeners();
  }

  /// Session-level line-jump arc radius (inches). Not written to `.vsdx`.
  void setLineJumpRadius(double inches) {
    final next = inches.clamp(0.02, 0.25);
    if ((next - _lineJumpRadiusInches).abs() < 1e-9) return;
    _lineJumpRadiusInches = next;
    notifyListeners();
  }

  /// Snap an inch coordinate to the grid when snapping is enabled.
  double snap(double v) =>
      _snapToGrid ? (v / _gridInches).roundToDouble() * _gridInches : v;

  // --- Page guides (drawio ruler guides; session-level) -----------------------

  /// Permanent guides keyed by page id (not written to `.vsdx`).
  final Map<int, List<PageGuide>> _pageGuides = <int, List<PageGuide>>{};

  /// Guides on the current page (unmodifiable view).
  List<PageGuide> get pageGuides {
    final id = currentPage?.id;
    if (id == null) return const <PageGuide>[];
    return List<PageGuide>.unmodifiable(
        _pageGuides[id] ?? const <PageGuide>[]);
  }

  bool get hasPageGuides => pageGuides.isNotEmpty;

  /// Add a guide at [pos] page-inches. Snaps to the grid when enabled.
  void addPageGuide({required bool vertical, required double pos}) {
    final id = currentPage?.id;
    if (id == null) return;
    final g = PageGuide(vertical: vertical, pos: snap(pos));
    final list = List<PageGuide>.of(_pageGuides[id] ?? const <PageGuide>[]);
    // Ignore near-duplicates (within half a grid step).
    final eps = _gridInches * 0.25;
    if (list.any((e) => e.vertical == g.vertical && (e.pos - g.pos).abs() < eps)) {
      return;
    }
    list.add(g);
    _pageGuides[id] = list;
    notifyListeners();
  }

  /// Move the guide at [index] to [pos] (snapped). No-op when out of range.
  void movePageGuide(int index, double pos) {
    final id = currentPage?.id;
    final list = id == null ? null : _pageGuides[id];
    if (id == null || list == null || index < 0 || index >= list.length) {
      return;
    }
    final next = List<PageGuide>.of(list);
    next[index] = next[index].copyWith(pos: snap(pos));
    _pageGuides[id] = next;
    notifyListeners();
  }

  /// Remove the guide at [index] on the current page.
  void removePageGuide(int index) {
    final id = currentPage?.id;
    final list = id == null ? null : _pageGuides[id];
    if (id == null || list == null || index < 0 || index >= list.length) {
      return;
    }
    final next = List<PageGuide>.of(list)..removeAt(index);
    if (next.isEmpty) {
      _pageGuides.remove(id);
    } else {
      _pageGuides[id] = next;
    }
    notifyListeners();
  }

  /// Clear every guide on the current page.
  void clearPageGuides() {
    final id = currentPage?.id;
    if (id == null || (_pageGuides[id]?.isEmpty ?? true)) return;
    _pageGuides.remove(id);
    notifyListeners();
  }

  // --- Selection -------------------------------------------------------------

  Set<int> get selection => Set<int>.unmodifiable(_selection);
  bool get hasSelection => _selection.isNotEmpty;
  bool isSelected(int shapeId) => _selection.contains(shapeId);

  void selectOnly(int shapeId) {
    if (_selection.length == 1 && _selection.contains(shapeId)) return;
    _leaveConnectionPointEdit();
    _selection
      ..clear()
      ..add(shapeId);
    notifyListeners();
  }

  void toggleSelection(int shapeId) {
    _leaveConnectionPointEdit();
    if (!_selection.remove(shapeId)) _selection.add(shapeId);
    notifyListeners();
  }

  void clearSelection() {
    if (_selection.isEmpty && !_editingConnectionPoints) return;
    _leaveConnectionPointEdit();
    _selection.clear();
    notifyListeners();
  }

  void setSelection(Iterable<int> ids) {
    _leaveConnectionPointEdit();
    _selection
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  /// Select every top-level shape on the current page.
  void selectAll() {
    final page = currentPage;
    if (page == null) return;
    setSelection(<int>[for (final s in page.shapes) s.id]);
  }

  /// Select every top-level 1-D shape (draw.io "Select Edges", Cmd+E).
  void selectConnectors() {
    final page = currentPage;
    if (page == null) return;
    setSelection(<int>[
      for (final s in page.shapes)
        if (s.is1D) s.id,
    ]);
  }

  /// Select every top-level 2-D shape (draw.io "Select Vertices", Cmd+Shift+I).
  void selectVertices() {
    final page = currentPage;
    if (page == null) return;
    setSelection(<int>[
      for (final s in page.shapes)
        if (!s.is1D) s.id,
    ]);
  }

  /// Cycle the selection to the next top-level shape (Tab).
  void selectNextShape({bool reverse = false}) {
    final page = currentPage;
    if (page == null || page.shapes.isEmpty) return;
    final ids = <int>[for (final s in page.shapes) s.id];
    if (ids.isEmpty) return;
    final cur = singleSelectedId;
    var idx = cur == null ? -1 : ids.indexOf(cur);
    if (idx < 0) {
      selectOnly(reverse ? ids.last : ids.first);
      return;
    }
    idx = reverse
        ? (idx - 1 + ids.length) % ids.length
        : (idx + 1) % ids.length;
    selectOnly(ids[idx]);
  }

  // --- Layers ----------------------------------------------------------------

  bool get hasLayers => currentPage?.layers.isNotEmpty ?? false;

  /// Next free layer row IX on the current page (0 if none yet).
  int nextFreeLayerId() {
    final layers = currentPage?.layers ?? const <VsdxLayer>[];
    var maxId = -1;
    for (final l in layers) {
      if (l.id > maxId) maxId = l.id;
    }
    return maxId + 1;
  }

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

  /// Toggle a layer's lock flag (draw.io: locked layers can't be edited).
  void toggleLayerLocked(int layerId) {
    updateCurrentPage(
      (page) => page.copyWith(
        layers: <VsdxLayer>[
          for (final l in page.layers)
            if (l.id == layerId) l.copyWith(locked: !l.locked) else l,
        ],
      ),
    );
  }

  /// Toggle whether shapes on this layer are printed / exported.
  void toggleLayerPrint(int layerId) {
    updateCurrentPage(
      (page) => page.copyWith(
        layers: <VsdxLayer>[
          for (final l in page.layers)
            if (l.id == layerId) l.copyWith(print: !l.print) else l,
        ],
      ),
    );
  }

  /// Rename a layer (one undo step).
  void renameLayer(int layerId, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    updateCurrentPage(
      (page) => page.copyWith(
        layers: <VsdxLayer>[
          for (final l in page.layers)
            if (l.id == layerId) l.copyWith(name: trimmed) else l,
        ],
      ),
    );
  }

  /// Create a new layer on the current page (draw.io "+"). Optionally assign
  /// the current selection to it. One undo step.
  void addLayer({String? name, bool assignSelection = false}) {
    final page = currentPage;
    if (page == null) return;
    final id = nextFreeLayerId();
    final layer = VsdxLayer(
      id: id,
      name: (name == null || name.trim().isEmpty) ? 'Layer $id' : name.trim(),
    );
    updateCurrentPage((p) {
      var next = p.copyWith(layers: <VsdxLayer>[...p.layers, layer]);
      if (assignSelection && _selection.isNotEmpty) {
        next = next.copyWith(
          shapes: [
            for (final s in next.shapes)
              _selection.contains(s.id)
                  ? s.copyWith(layerMemberIds: <int>[id])
                  : s,
          ],
        );
      }
      return next;
    });
  }

  /// Delete a layer row. Shapes that only belonged to it become unassigned
  /// (visible on every layer). One undo step.
  void deleteLayer(int layerId) {
    final page = currentPage;
    if (page == null) return;
    if (page.layers.every((l) => l.id != layerId)) return;
    updateCurrentPage((p) {
      final layers = <VsdxLayer>[
        for (final l in p.layers)
          if (l.id != layerId) l,
      ];
      final shapes = <VsdxShape>[
        for (final s in p.shapes)
          s.layerMemberIds.contains(layerId)
              ? s.copyWith(
                  layerMemberIds: <int>[
                    for (final id in s.layerMemberIds)
                      if (id != layerId) id,
                  ],
                )
              : s,
      ];
      return p.copyWith(layers: layers, shapes: shapes);
    });
  }

  /// Assign every selected shape to [layerId] (replaces membership). One undo.
  void assignSelectionToLayer(int layerId) {
    if (_selection.isEmpty) return;
    final page = currentPage;
    if (page == null) return;
    if (page.layers.every((l) => l.id != layerId)) return;
    _updateSelectedShapes(
      (s) => s.copyWith(layerMemberIds: <int>[layerId]),
    );
  }

  /// True when [shapeId] sits on a locked layer (and has membership).
  bool isOnLockedLayer(int shapeId) {
    final page = currentPage;
    if (page == null) return false;
    final s = page.findShapeById(shapeId);
    if (s == null || s.layerMemberIds.isEmpty) return false;
    for (final id in s.layerMemberIds) {
      for (final l in page.layers) {
        if (l.id == id && l.locked) return true;
      }
    }
    return false;
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

  /// Abort the current gesture, reverting the live document to the snapshot
  /// taken at [beginTransaction] (no history entry). Used by Escape-to-cancel.
  void cancelTransaction() {
    final base = _txnBase;
    _txnBase = null;
    if (base != null && !identical(base, _document)) {
      _document = base;
      notifyListeners();
    }
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
  ///
  /// When a moved shape has [VsdxShape.dontMoveChildren], its children are
  /// compensated so their on-page positions stay fixed (Visio semantics).
  void moveSelectionBy(
    double dxInches,
    double dyInches, {
    bool transient = false,
  }) {
    if (_selection.isEmpty || (dxInches == 0 && dyInches == 0)) return;
    final movedIds = _subtreeIds(_selection);
    updateCurrentPage(
      (page) {
        var next = page;
        var moved = false;
        for (final id in _selection) {
          final s = page.findShapeById(id);
          if (s == null || s.locked || isOnLockedLayer(id)) continue;
          next = next.updateShapeById(
            id,
            (sh) => _translatedHonouringDontMoveChildren(sh, dxInches, dyInches),
          );
          moved = true;
        }
        return moved
            ? next.rerouteConnectors(movedShapeIds: movedIds)
            : page;
      },
      transient: transient,
    );
  }

  /// Reparent each selected shape into [containerId] (or out to the top level
  /// when [containerId] is `null`). Used by canvas drop-into-container.
  void reparentSelectionInto(int? containerId) {
    if (_selection.isEmpty) return;
    final movedIds = <int>{
      ..._subtreeIds(_selection),
      if (containerId != null) ..._subtreeIds(<int>{containerId}),
    };
    updateCurrentPage((page) {
      var next = page;
      for (final id in List<int>.of(_selection)) {
        // Skip the container itself if it is somehow selected.
        if (containerId != null && id == containerId) continue;
        next = next.reparentShape(id, containerId);
      }
      return next.rerouteConnectors(movedShapeIds: movedIds);
    });
  }

  /// Toggle draw.io-style fold on a structural container / swimlane. Children
  /// stay in the model; paint and hit-testing hide them while collapsed. The
  /// container height shrinks to the header band (top edge fixed) and restores
  /// on unfold.
  void toggleCollapsed(int id) {
    final movedIds = _subtreeIds(<int>{id});
    updateCurrentPage((page) {
      final s = page.findShapeById(id);
      if (s == null || !s.shapeKind.isStructural) return page;
      final next = s.collapsed ? s.unfold() : s.fold();
      return page
          .updateShapeById(id, (_) => next)
          .rerouteConnectors(movedShapeIds: movedIds);
    });
    final page = currentPage;
    final s = page?.findShapeById(id);
    if (page == null || s == null || !s.collapsed) return;
    final hidden = <int>{};
    void walk(VsdxShape n) {
      for (final c in n.children) {
        hidden.add(c.id);
        walk(c);
      }
    }

    walk(s);
    if (_selection.any(hidden.contains)) {
      _selection.removeWhere(hidden.contains);
      notifyListeners();
    }
  }

  /// Whether [id] is a foldable container currently collapsed.
  bool isCollapsed(int id) =>
      currentPage?.findShapeById(id)?.collapsed ?? false;

  /// After a drag, adopt or eject selected shapes based on [pageX]/[pageY]
  /// (pointer in page inches). Returns the drop-container id that was used
  /// (for UI feedback), or `null` when shapes were ejected / left alone.
  ///
  /// Call with [transient] `true` while a move gesture is open so the reparent
  /// folds into the same undo step as the drag.
  int? applyDropContainmentAt(
    double pageX,
    double pageY, {
    bool transient = true,
  }) {
    final page = currentPage;
    if (page == null || _selection.isEmpty) return null;
    final dropId = page.findDropContainerAt(
      pageX,
      pageY,
      excludeIds: Set<int>.of(_selection),
    );
    final movedIds = <int>{
      ..._subtreeIds(_selection),
      if (dropId != null) ..._subtreeIds(<int>{dropId}),
    };
    var changed = false;
    updateCurrentPage(
      (p) {
        var next = p;
        // If dropping a lane onto another lane inside a pool, target the pool.
        var targetId = dropId;
        if (targetId != null) {
          final host = next.findShapeById(targetId);
          final droppingLane = _selection.any((id) {
            final s = next.findShapeById(id);
            return s != null && SwimlaneOps.isLane(s);
          });
          if (droppingLane && host != null && SwimlaneOps.isLane(host)) {
            final parentId = next.findParentId(targetId);
            final parent =
                parentId == null ? null : next.findShapeById(parentId);
            if (parent != null && SwimlaneOps.isPool(parent)) {
              targetId = parentId;
            }
          }
        }
        for (final id in List<int>.of(_selection)) {
          final oldParent = next.findParentId(id);
          if (targetId != null) {
            if (oldParent != targetId) {
              next = next.reparentShape(id, targetId);
              changed = true;
            }
          } else if (oldParent != null) {
            next = next.reparentShape(id, null);
            changed = true;
          }
        }
        // When lanes land in a pool, reflow them to tile the pool.
        if (targetId != null) {
          final host = next.findShapeById(targetId);
          if (host != null && SwimlaneOps.isPool(host)) {
            final laid = SwimlaneOps.layoutLanes(host);
            if (!identical(laid, host)) {
              next = next.updateShapeById(targetId, (_) => laid);
              changed = true;
            }
          }
        }
        return changed
            ? next.rerouteConnectors(movedShapeIds: movedIds)
            : p;
      },
      transient: transient,
    );
    return dropId;
  }

  /// Pool id for the current selection (selected pool, or parent of a lane).
  int? get selectedPoolId {
    final page = currentPage;
    final id = singleSelectedId;
    if (page == null || id == null) return null;
    final s = page.findShapeById(id);
    if (s == null) return null;
    if (SwimlaneOps.isPool(s)) return id;
    final parentId = page.findParentId(id);
    if (parentId == null) return null;
    final parent = page.findShapeById(parentId);
    if (parent != null && SwimlaneOps.isPool(parent)) return parentId;
    return null;
  }

  /// Whether Add Lane is available for the current selection.
  bool get canAddLane => selectedPoolId != null;

  /// Whether Remove Lane is available (selected lane inside a multi-lane pool).
  bool get canRemoveLane {
    final page = currentPage;
    final id = singleSelectedId;
    if (page == null || id == null) return false;
    final s = page.findShapeById(id);
    if (s == null || !SwimlaneOps.isLane(s)) return false;
    final poolId = selectedPoolId;
    if (poolId == null) return false;
    final pool = page.findShapeById(poolId);
    return pool != null && SwimlaneOps.lanesOf(pool).length > 1;
  }

  /// Append a lane to the selected pool (or the pool that owns the selected
  /// lane). One undo step; new lane is selected.
  void addLaneToSelectedPool() {
    final page = currentPage;
    final poolId = selectedPoolId;
    if (page == null || poolId == null) return;
    final pool = page.findShapeById(poolId);
    if (pool == null) return;
    final horizontal = SwimlaneOps.lanesOf(pool).isEmpty
        ? true
        : SwimlaneOps.isHorizontal(SwimlaneOps.lanesOf(pool).first);
    final laneId = page.nextFreeShapeId();
    final n = SwimlaneOps.lanesOf(pool).length + 1;
    final newLane = SwimlaneOps.lane(
      id: laneId,
      pinX: pool.width / 2,
      pinY: pool.height / 2,
      width: pool.width,
      height: pool.height / n,
      horizontal: horizontal,
      name: 'Lane $n',
      text: 'Lane $n',
    );
    final movedIds = _subtreeIds(<int>{poolId});
    updateCurrentPage((p) {
      final host = p.findShapeById(poolId);
      if (host == null) return p;
      return p
          .updateShapeById(poolId, (_) => SwimlaneOps.addLane(host, newLane))
          .rerouteConnectors(movedShapeIds: movedIds);
    });
    _selection
      ..clear()
      ..add(laneId);
    notifyListeners();
  }

  /// Remove the selected lane from its pool (keeps at least one lane).
  void removeSelectedLane() {
    if (!canRemoveLane) return;
    final page = currentPage;
    final laneId = singleSelectedId;
    final poolId = selectedPoolId;
    if (page == null || laneId == null || poolId == null) return;
    final movedIds = _subtreeIds(<int>{poolId});
    updateCurrentPage((p) {
      final host = p.findShapeById(poolId);
      if (host == null) return p;
      return p
          .updateShapeById(poolId, (_) => SwimlaneOps.removeLane(host, laneId))
          .rerouteConnectors(movedShapeIds: movedIds);
    });
    _selection
      ..clear()
      ..add(poolId);
    notifyListeners();
  }

  // --- Tables (draw.io HTML table) -------------------------------------------

  /// Table id for the current selection (selected table, or parent of a cell).
  /// Works with multi-select when every selected shape belongs to one table.
  int? get selectedTableId {
    final page = currentPage;
    if (page == null || _selection.isEmpty) return null;
    int? tableId;
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s == null) return null;
      int? tid;
      if (TableOps.isTable(s)) {
        tid = id;
      } else if (TableOps.isCell(s)) {
        final parentId = page.findParentId(id);
        final parent =
            parentId == null ? null : page.findShapeById(parentId);
        if (parent != null && TableOps.isTable(parent)) tid = parentId;
      }
      if (tid == null) return null;
      tableId ??= tid;
      if (tableId != tid) return null;
    }
    return tableId;
  }

  bool get canAddTableRow => selectedTableId != null;
  bool get canAddTableColumn => selectedTableId != null;

  bool get canRemoveTableRow {
    final page = currentPage;
    final tableId = selectedTableId;
    if (page == null || tableId == null) return false;
    final table = page.findShapeById(tableId);
    if (table == null) return false;
    return TableOps.dimensions(table).rows > 1;
  }

  bool get canRemoveTableColumn {
    final page = currentPage;
    final tableId = selectedTableId;
    if (page == null || tableId == null) return false;
    final table = page.findShapeById(tableId);
    if (table == null) return false;
    return TableOps.dimensions(table).cols > 1;
  }

  void addRowToSelectedTable() {
    final page = currentPage;
    final tableId = selectedTableId;
    if (page == null || tableId == null) return;
    final startId = page.nextFreeShapeId();
    final movedIds = _subtreeIds(<int>{tableId});
    updateCurrentPage((p) {
      final host = p.findShapeById(tableId);
      if (host == null) return p;
      return p
          .updateShapeById(
              tableId, (_) => TableOps.addRow(host, startId: startId))
          .rerouteConnectors(movedShapeIds: movedIds);
    });
    _selection
      ..clear()
      ..add(tableId);
    notifyListeners();
  }

  void addColumnToSelectedTable() {
    final page = currentPage;
    final tableId = selectedTableId;
    if (page == null || tableId == null) return;
    final startId = page.nextFreeShapeId();
    final movedIds = _subtreeIds(<int>{tableId});
    updateCurrentPage((p) {
      final host = p.findShapeById(tableId);
      if (host == null) return p;
      return p
          .updateShapeById(
              tableId, (_) => TableOps.addColumn(host, startId: startId))
          .rerouteConnectors(movedShapeIds: movedIds);
    });
    _selection
      ..clear()
      ..add(tableId);
    notifyListeners();
  }

  void removeRowFromSelectedTable() {
    if (!canRemoveTableRow) return;
    final page = currentPage;
    final tableId = selectedTableId;
    final sel = singleSelectedId;
    if (page == null || tableId == null) return;
    final table = page.findShapeById(tableId)!;
    var rowIndex = TableOps.dimensions(table).rows - 1;
    if (sel != null) {
      final cell = page.findShapeById(sel);
      if (cell != null && TableOps.isCell(cell)) {
        rowIndex = TableOps.cellRow(cell) ?? rowIndex;
      }
    }
    final movedIds = _subtreeIds(<int>{tableId});
    updateCurrentPage((p) {
      final host = p.findShapeById(tableId);
      if (host == null) return p;
      return p
          .updateShapeById(tableId, (_) => TableOps.removeRow(host, rowIndex))
          .rerouteConnectors(movedShapeIds: movedIds);
    });
    _selection
      ..clear()
      ..add(tableId);
    notifyListeners();
  }

  void removeColumnFromSelectedTable() {
    if (!canRemoveTableColumn) return;
    final page = currentPage;
    final tableId = selectedTableId;
    final sel = singleSelectedId;
    if (page == null || tableId == null) return;
    final table = page.findShapeById(tableId)!;
    var colIndex = TableOps.dimensions(table).cols - 1;
    if (sel != null) {
      final cell = page.findShapeById(sel);
      if (cell != null && TableOps.isCell(cell)) {
        colIndex = TableOps.cellCol(cell) ?? colIndex;
      }
    }
    final movedIds = _subtreeIds(<int>{tableId});
    updateCurrentPage((p) {
      final host = p.findShapeById(tableId);
      if (host == null) return p;
      return p
          .updateShapeById(
              tableId, (_) => TableOps.removeColumn(host, colIndex))
          .rerouteConnectors(movedShapeIds: movedIds);
    });
    _selection
      ..clear()
      ..add(tableId);
    notifyListeners();
  }

  /// Selected cells that belong to the same table (for merge).
  List<VsdxShape> get _selectedTableCells {
    final page = currentPage;
    final tableId = selectedTableId;
    if (page == null || tableId == null || _selection.isEmpty) {
      return const <VsdxShape>[];
    }
    final out = <VsdxShape>[];
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s == null || !TableOps.isCell(s) || TableOps.isCovered(s)) continue;
      if (page.findParentId(id) != tableId) continue;
      out.add(s);
    }
    return out;
  }

  /// Whether the current multi-selection of cells can be merged into one block.
  bool get canMergeCells {
    final cells = _selectedTableCells;
    if (cells.length < 2) return false;
    var minR = 1 << 30, maxR = -1, minC = 1 << 30, maxC = -1;
    for (final c in cells) {
      if (TableOps.rowSpan(c) != 1 || TableOps.colSpan(c) != 1) return false;
      final r = TableOps.cellRow(c)!;
      final col = TableOps.cellCol(c)!;
      if (r < minR) minR = r;
      if (r > maxR) maxR = r;
      if (col < minC) minC = col;
      if (col > maxC) maxC = col;
    }
    final expect = (maxR - minR + 1) * (maxC - minC + 1);
    if (cells.length != expect) return false;
    final keys = <String>{
      for (final c in cells) '${TableOps.cellRow(c)}_${TableOps.cellCol(c)}',
    };
    for (var r = minR; r <= maxR; r++) {
      for (var c = minC; c <= maxC; c++) {
        if (!keys.contains('${r}_$c')) return false;
      }
    }
    return true;
  }

  bool get canUnmergeCell {
    final page = currentPage;
    final id = singleSelectedId;
    if (page == null || id == null) return false;
    final s = page.findShapeById(id);
    if (s == null || !TableOps.isCell(s)) return false;
    if (TableOps.isMerged(s)) return true;
    if (!TableOps.isCovered(s)) return false;
    return _masterForCovered(page, s) != null;
  }

  VsdxShape? _masterForCovered(VsdxPage page, VsdxShape covered) {
    final tableId = page.findParentId(covered.id);
    final table = tableId == null ? null : page.findShapeById(tableId);
    if (table == null) return null;
    final r = TableOps.cellRow(covered)!;
    final c = TableOps.cellCol(covered)!;
    for (final cell in TableOps.cellsOf(table)) {
      if (TableOps.isCovered(cell) || !TableOps.isMerged(cell)) continue;
      final mr = TableOps.cellRow(cell)!;
      final mc = TableOps.cellCol(cell)!;
      final rs = TableOps.rowSpan(cell);
      final cs = TableOps.colSpan(cell);
      if (r >= mr && r < mr + rs && c >= mc && c < mc + cs) return cell;
    }
    return null;
  }

  void mergeSelectedCells() {
    if (!canMergeCells) return;
    final tableId = selectedTableId;
    final page = currentPage;
    if (tableId == null || page == null) return;
    final cells = _selectedTableCells;
    var minR = 1 << 30, maxR = -1, minC = 1 << 30, maxC = -1;
    for (final c in cells) {
      final r = TableOps.cellRow(c)!;
      final col = TableOps.cellCol(c)!;
      if (r < minR) minR = r;
      if (r > maxR) maxR = r;
      if (col < minC) minC = col;
      if (col > maxC) maxC = col;
    }
    final movedIds = _subtreeIds(<int>{tableId});
    updateCurrentPage((p) {
      final host = p.findShapeById(tableId);
      if (host == null) return p;
      return p
          .updateShapeById(
            tableId,
            (_) => TableOps.mergeCells(
              host,
              row: minR,
              col: minC,
              rowSpan: maxR - minR + 1,
              colSpan: maxC - minC + 1,
            ),
          )
          .rerouteConnectors(movedShapeIds: movedIds);
    });
    // Select the master cell after merge.
    final table = currentPage?.findShapeById(tableId);
    if (table != null) {
      for (final c in TableOps.cellsOf(table)) {
        if (TableOps.cellRow(c) == minR && TableOps.cellCol(c) == minC) {
          _selection
            ..clear()
            ..add(c.id);
          break;
        }
      }
    }
    notifyListeners();
  }

  void unmergeSelectedCell() {
    if (!canUnmergeCell) return;
    final page = currentPage;
    final tableId = selectedTableId;
    final id = singleSelectedId;
    if (page == null || tableId == null || id == null) return;
    var s = page.findShapeById(id)!;
    if (TableOps.isCovered(s)) {
      s = _masterForCovered(page, s)!;
    }
    final row = TableOps.cellRow(s)!;
    final col = TableOps.cellCol(s)!;
    final movedIds = _subtreeIds(<int>{tableId});
    updateCurrentPage((p) {
      final host = p.findShapeById(tableId);
      if (host == null) return p;
      return p
          .updateShapeById(
            tableId,
            (_) => TableOps.unmergeCells(host, row: row, col: col),
          )
          .rerouteConnectors(movedShapeIds: movedIds);
    });
    _selection
      ..clear()
      ..add(s.id);
    notifyListeners();
  }

  /// Resize column divider after [afterCol] (transient during drag).
  void resizeTableColumn(
    int tableId,
    int afterCol,
    double deltaInches, {
    bool transient = false,
  }) {
    updateCurrentPage(
      (p) {
        final host = p.findShapeById(tableId);
        if (host == null || !TableOps.isTable(host)) return p;
        return p.updateShapeById(
          tableId,
          (_) => TableOps.resizeColumnBoundary(host, afterCol, deltaInches),
        );
      },
      transient: transient,
    );
  }

  /// Resize row divider below [afterRow] (transient during drag).
  void resizeTableRow(
    int tableId,
    int afterRow,
    double deltaPageY, {
    bool transient = false,
  }) {
    updateCurrentPage(
      (p) {
        final host = p.findShapeById(tableId);
        if (host == null || !TableOps.isTable(host)) return p;
        return p.updateShapeById(
          tableId,
          (_) => TableOps.resizeRowBoundary(host, afterRow, deltaPageY),
        );
      },
      transient: transient,
    );
  }

  /// Create a freehand / scribble stroke through page-space [points] (drawio
  /// Freehand). Points are lightly simplified (min spacing); fewer than 2
  /// survivors is a no-op. One undo step; selects the stroke and returns to
  /// the select tool. Inherits the remembered line style (no fill).
  void createFreehand(List<Offset2D> points) {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null) return;
    final simplified = _simplifyFreehand(points);
    if (simplified.length < 2) return;
    final id = page.nextFreeShapeId();
    final base = VsdxShapeFactory.freehand(id: id, points: simplified);
    final shape = _withMemoStyle(base, includeFill: false);
    _selection
      ..clear()
      ..add(id);
    _tool = EditorTool.select;
    applyEdit(doc.replacePage(_currentPageIndex, page.addShape(shape)));
  }

  /// Drop consecutive samples closer than ~2 pt (~0.03") so scribble paths
  /// stay compact without losing the stroke's silhouette.
  static List<Offset2D> _simplifyFreehand(List<Offset2D> points) {
    if (points.isEmpty) return const <Offset2D>[];
    const minDist = 0.03; // inches ≈ 2–3 CSS px at 96 dpi
    final out = <Offset2D>[points.first];
    for (var i = 1; i < points.length; i++) {
      final p = points[i];
      final prev = out.last;
      final dx = p.x - prev.x;
      final dy = p.y - prev.y;
      if (dx * dx + dy * dy >= minDist * minDist) out.add(p);
    }
    // Always keep the final sample so the stroke ends where the pointer did.
    if (out.last != points.last) out.add(points.last);
    return out;
  }

  /// Create a shape for the current [tool] from a drag in page inches. A tiny
  /// drag (a click) yields a sensibly-sized default. Resets to the select tool
  /// and selects the new shape. Freehand strokes use [createFreehand] instead.
  void createShapeByDrag(double sx, double sy, double ex, double ey) {
    final doc = _document;
    final page = currentPage;
    if (doc == null ||
        page == null ||
        _tool == EditorTool.select ||
        _tool == EditorTool.freehand) {
      return;
    }
    sx = snap(sx);
    sy = snap(sy);
    ex = snap(ex);
    ey = snap(ey);
    final id = page.nextFreeShapeId();

    // A borderless text box (drawio's Text tool) — no inherited fill / line,
    // enters edit mode on the canvas immediately after creation.
    if (_tool == EditorTool.text) {
      var left = math.min(sx, ex);
      var bottom = math.min(sy, ey);
      var w = (math.max(sx, ex) - left).abs();
      var h = (math.max(sy, ey) - bottom).abs();
      if (w < 0.1 && h < 0.1) {
        w = 1.5;
        h = 0.5;
        left = sx - w / 2;
        bottom = sy - h / 2;
      } else {
        w = math.max(w, 0.05);
        h = math.max(h, 0.05);
      }
      final box = VsdxShapeFactory.textBox(
        id: id,
        pinX: left + w / 2,
        pinY: bottom + h / 2,
        width: w,
        height: h,
      );
      _selection
        ..clear()
        ..add(id);
      _tool = EditorTool.select;
      applyEdit(doc.replacePage(_currentPageIndex, page.addShape(box)));
      return;
    }

    final VsdxShape base;
    if (_tool == EditorTool.line) {
      var bx = ex;
      var by = ey;
      if ((bx - sx).abs() < 0.1 && (by - sy).abs() < 0.1) {
        bx = sx + 1.5;
        by = sy;
      }
      base = VsdxShapeFactory.line(id: id, ax: sx, ay: sy, bx: bx, by: by);
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
      base = _tool == EditorTool.rectangle
          ? VsdxShapeFactory.rectangle(
              id: id, pinX: pinX, pinY: pinY, width: w, height: h)
          : VsdxShapeFactory.ellipse(
              id: id, pinX: pinX, pinY: pinY, width: w, height: h);
    }

    final shape =
        _withMemoStyle(base, includeFill: _tool != EditorTool.line);
    _selection
      ..clear()
      ..add(id);
    _tool = EditorTool.select;
    applyEdit(doc.replacePage(_currentPageIndex, page.addShape(shape)));
  }

  /// Create a connector line between two page points. When [beginTarget] /
  /// [endTarget] name a shape, that end is glued (a `<Connect>` row is added).
  /// With an explicit [beginConnectionPointIndex] / [endConnectionPointIndex]
  /// the end pins to that fixed blue point; otherwise whole-shape glue
  /// (`ToPart=3`) attaches on the geometry perimeter aimed at the opposite end
  /// (draw.io-style — any border point, not only the four mid-edge dots).
  void createConnector(
    double ax,
    double ay,
    double bx,
    double by, {
    int? beginTarget,
    int? endTarget,
    int? beginConnectionPointIndex,
    int? endConnectionPointIndex,
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
    // Connectors carry a filled end arrowhead by default (drawio edges point
    // at their target); the stroke follows the last-used line style.
    final baseLine = (_memoLine ?? const VsdxLine(color: VsdxColor.black))
        .copyWith(endArrow: 4);
    var connector = VsdxShapeFactory.line(
      id: id,
      ax: sax,
      ay: say,
      bx: sbx,
      by: sby,
      line: baseLine,
    );
    // Prefixed XFTRIGGER formulas so 万兴图示 re-glues when targets move.
    if (beginTarget != null || endTarget != null) {
      final formulas = Map<String, String>.from(connector.formulas);
      final props = connector.connectorProps ?? const VsdxConnectorProps();
      if (beginTarget != null) {
        formulas['BegTrigger'] = '_XFTRIGGER(Sheet.$beginTarget!EventXFMod)';
      }
      if (endTarget != null) {
        formulas['EndTrigger'] = '_XFTRIGGER(Sheet.$endTarget!EventXFMod)';
      }
      connector = connector.copyWith(
        formulas: formulas,
        connectorProps: props.copyWith(
          begTrigger: beginTarget != null ? '2' : props.begTrigger,
          endTrigger: endTarget != null ? '2' : props.endTrigger,
        ),
      );
    }
    // Prefer explicit CP indices (drawio blue points). Otherwise use whole-shape
    // glue (ToPart=3) so the endpoint attaches anywhere on the geometry
    // perimeter aimed at the opposite end — not only the four mid-edge points.
    final beginIdx = beginConnectionPointIndex;
    final endIdx = endConnectionPointIndex;
    final connects = <VsdxConnect>[
      ...page.connects,
      if (beginTarget != null)
        VsdxConnect(
          fromSheetId: id,
          fromCell: 'BeginX',
          fromPart: 9,
          toSheetId: beginTarget,
          toCell: beginIdx != null ? 'Connections.X${beginIdx + 1}' : 'PinX',
          toPart: beginIdx != null ? 100 + beginIdx : 3,
        ),
      if (endTarget != null)
        VsdxConnect(
          fromSheetId: id,
          fromCell: 'EndX',
          fromPart: 12,
          toSheetId: endTarget,
          toCell: endIdx != null ? 'Connections.X${endIdx + 1}' : 'PinX',
          toPart: endIdx != null ? 100 + endIdx : 3,
        ),
    ];
    _selection
      ..clear()
      ..add(id);
    _tool = EditorTool.select;
    var next = page.addShape(connector).copyWith(connects: connects);
    // Materialise Connection rows on targets so fixed-point glue round-trips.
    if (beginTarget != null && beginIdx != null) {
      next = next.setConnectorEndpoint(
        id,
        begin: true,
        targetShapeId: beginTarget,
        connectionPointIndex: beginIdx,
        x: sax,
        y: say,
      );
    }
    if (endTarget != null && endIdx != null) {
      next = next.setConnectorEndpoint(
        id,
        begin: false,
        targetShapeId: endTarget,
        connectionPointIndex: endIdx,
        x: sbx,
        y: sby,
      );
    }
    if (beginIdx == null || endIdx == null) {
      next = next.rerouteConnectors(movedShapeIds: <int>{
        id,
        ?beginTarget,
        ?endTarget,
      });
    }
    applyEdit(
      doc.replacePage(
        _currentPageIndex,
        next,
      ),
    );
  }

  /// drawio directional-arrow click ("connect / clone in a direction").
  ///
  /// Creates a connector from [sourceId] toward [dir] (0=N, 1=E, 2=S, 3=W).
  /// When [existingTargetId] names a shape already sitting where the arrow
  /// points, the connector glues to it; otherwise the source is cloned at
  /// ([cloneX],[cloneY]) and the connector glues to the clone. Either way the
  /// connected shape is selected. One undo step; no-op for a 1-D source.
  void connectDirectional(
    int sourceId,
    int dir, {
    int? existingTargetId,
    required double cloneX,
    required double cloneY,
  }) {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null) return;
    final source = page.findShapeById(sourceId);
    if (source == null || source.is1D) return;

    var next = page;
    final int targetId;
    if (existingTargetId != null &&
        existingTargetId != sourceId &&
        page.findShapeById(existingTargetId)?.is1D == false) {
      targetId = existingTargetId;
    } else {
      // Nothing to connect to yet: clone the source one step over (drawio
      // copies the shape and wires it up).
      final newId = next.nextFreeShapeId();
      next = next.addShape(
        source.copyWith(id: newId, pinX: cloneX, pinY: cloneY),
      );
      targetId = newId;
    }

    final target = next.findShapeById(targetId)!;
    final connId = next.nextFreeShapeId();
    final baseLine = (_memoLine ?? const VsdxLine(color: VsdxColor.black))
        .copyWith(endArrow: 4);
    final connector = VsdxShapeFactory.line(
      id: connId,
      ax: source.pinX,
      ay: source.pinY,
      bx: target.pinX,
      by: target.pinY,
      line: baseLine,
    );
    next = next.addShape(connector).copyWith(
      connects: <VsdxConnect>[
        ...next.connects,
        VsdxConnect(
          fromSheetId: connId,
          fromCell: 'BeginX',
          fromPart: 9,
          toSheetId: sourceId,
          toCell: 'PinX',
          toPart: 3,
        ),
        VsdxConnect(
          fromSheetId: connId,
          fromCell: 'EndX',
          fromPart: 12,
          toSheetId: targetId,
          toCell: 'PinX',
          toPart: 3,
        ),
      ],
    ).rerouteConnectors(movedShapeIds: <int>{connId, sourceId, targetId});

    // Glue each end to the facing fixed connection point so the edge meets the
    // sides square-on (only meaningful for the default point set).
    if (source.connectionPoints.isEmpty) {
      next = next.setConnectorEndpoint(
        connId,
        begin: true,
        targetShapeId: sourceId,
        connectionPointIndex: dir,
        x: source.pinX,
        y: source.pinY,
      );
    }
    if (target.connectionPoints.isEmpty) {
      next = next.setConnectorEndpoint(
        connId,
        begin: false,
        targetShapeId: targetId,
        connectionPointIndex: (dir + 2) % 4,
        x: target.pinX,
        y: target.pinY,
      );
    }

    _selection
      ..clear()
      ..add(targetId);
    _tool = EditorTool.select;
    applyEdit(doc.replacePage(_currentPageIndex, next));
  }

  /// Insert an embedded raster image as a new picture shape (drawio's
  /// "Insert > Image" / drag-drop). [bytes] are the file's contents,
  /// [fileExtension] its extension (png / jpg / gif / …).
  ///
  /// When [cx]/[cy] are set the picture is centred on that page point
  /// (snapped); otherwise it lands at the page centre. [widthInches]/
  /// [heightInches] size the box (defaulting to a square that fits the page);
  /// the picture is scaled down to stay within the page. The media bytes are
  /// embedded on the document so the canvas renders them immediately and the
  /// writer round-trips them as a new `visio/media` part. One undo step;
  /// selects the new picture and returns to the select tool.
  void insertImage(
    Uint8List bytes, {
    required String fileExtension,
    double? widthInches,
    double? heightInches,
    double? cx,
    double? cy,
  }) {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null || bytes.isEmpty) return;

    final minted = _mintImage(doc, bytes, fileExtension);
    // Fit the picture within the page (preserve the requested aspect ratio).
    final maxW = page.widthInches * 0.9;
    final maxH = page.heightInches * 0.9;
    var w = (widthInches ?? 2.0);
    var h = (heightInches ?? 2.0);
    if (w <= 0) w = 2.0;
    if (h <= 0) h = 2.0;
    final scale = math.min(1.0, math.min(maxW / w, maxH / h));
    w *= scale;
    h *= scale;

    final id = page.nextFreeShapeId();
    final shape = VsdxShapeFactory.picture(
      id: id,
      pinX: snap(cx ?? page.widthInches / 2),
      pinY: snap(cy ?? page.heightInches / 2),
      width: w,
      height: h,
      imagePartName: minted.partName,
    );
    _selection
      ..clear()
      ..add(id);
    _tool = EditorTool.select;
    applyEdit(
      doc.copyWith(images: doc.images.withImage(minted)).replacePage(
            _currentPageIndex,
            page.addShape(shape),
          ),
    );
  }

  /// Replace the media on an existing picture shape (drawio drop-on-image /
  /// "Replace Image"). Keeps pin / size / angle; mints a fresh media part so
  /// undo of a prior insert can't collide. One undo step.
  void replaceImage(
    int shapeId,
    Uint8List bytes, {
    required String fileExtension,
  }) {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null || bytes.isEmpty) return;
    final shape = page.findShapeById(shapeId);
    if (shape == null || !shape.hasImage || shape.locked) return;
    if (isOnLockedLayer(shapeId)) return;

    final minted = _mintImage(doc, bytes, fileExtension);
    final next = page.updateShapeById(
      shapeId,
      (s) => s.copyWith(
        imagePartName: minted.partName,
        foreignType: minted.foreignType,
        foreignCompressionType: minted.compressionType,
      ),
    );
    _selection
      ..clear()
      ..add(shapeId);
    _tool = EditorTool.select;
    applyEdit(
      doc.copyWith(images: doc.images.withImage(minted)).replacePage(
            _currentPageIndex,
            next,
          ),
    );
  }

  /// True when the single selection is an unlocked picture shape.
  bool get canReplaceSelectedImage {
    final id = singleSelectedId;
    if (id == null) return false;
    final s = currentPage?.findShapeById(id);
    return s != null && s.hasImage && !s.locked && !isOnLockedLayer(id);
  }

  /// Top-most picture shape whose bounds contain page point ([x],[y]), or
  /// `null`. Used when dropping an image file onto the canvas (drawio replaces
  /// the picture under the cursor).
  int? pictureShapeAt(double x, double y) {
    final page = currentPage;
    if (page == null) return null;
    final bounds = buildShapeBounds(page);
    final order = <int>[];
    void walk(VsdxShape s) {
      order.add(s.id);
      if (s.collapsed) return;
      for (final c in s.children) {
        walk(c);
      }
    }

    for (final s in page.shapes) {
      walk(s);
    }
    final pt = Offset(x, y);
    int? best;
    for (final id in order) {
      final s = page.findShapeById(id);
      if (s == null || !s.hasImage || s.locked || isOnLockedLayer(id)) {
        continue;
      }
      final b = bounds[id];
      if (b != null && b.contains(pt)) best = id;
    }
    return best;
  }

  /// Mint a unique `/visio/media/imageN.ext` entry for [bytes].
  VsdxImage _mintImage(
    VsdxDocument doc,
    Uint8List bytes,
    String fileExtension,
  ) {
    final ext = fileExtension.replaceAll('.', '').trim().toLowerCase();
    _imageSeq = math.max(
          _imageSeq,
          _maxMediaIndex(doc.images.all.map((e) => e.partName)),
        ) +
        1;
    final partName = '/visio/media/image$_imageSeq.${ext.isEmpty ? 'png' : ext}';
    return VsdxImage(
      partName: partName,
      bytes: bytes,
      mimeType: VsdxImage.mimeForExtension(ext),
    );
  }

  /// Largest `N` across `imageN.ext`-style media part names (0 when none).
  static int _maxMediaIndex(Iterable<String> partNames) {
    final re = RegExp(r'image(\d+)\.', caseSensitive: false);
    var maxN = 0;
    for (final p in partNames) {
      final m = re.firstMatch(p);
      if (m != null) {
        final n = int.tryParse(m.group(1)!);
        if (n != null && n > maxN) maxN = n;
      }
    }
    return maxN;
  }

  /// Add a shape produced by [build] at the current page's centre, select it.
  void addShapeFromBuilder(
    VsdxShape Function(int id, double cx, double cy) build,
  ) {
    final page = currentPage;
    if (page == null) return;
    addShapeFromBuilderAt(build, page.widthInches / 2, page.heightInches / 2);
  }

  /// Add a shape produced by [build] centred at page point ([cx],[cy])
  /// (snapped to the grid), inheriting the remembered style and selecting it.
  /// Used by drag-and-drop from the shapes palette (drawio drops at the cursor).
  void addShapeFromBuilderAt(
    VsdxShape Function(int id, double cx, double cy) build,
    double cx,
    double cy,
  ) {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null) return;
    final id = page.nextFreeShapeId();
    final built = build(id, snap(cx), snap(cy));
    final shape = _withMemoStyle(built, includeFill: !built.is1D);
    _selection
      ..clear()
      ..add(id);
    _tool = EditorTool.select;
    applyEdit(doc.replacePage(_currentPageIndex, page.addShape(shape)));
  }

  /// Delete all selected shapes as a single undo step.
  void deleteSelection() {
    if (_editingConnectionPoints) {
      removeSelectedConnectionPoint();
      return;
    }
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null || _selection.isEmpty) return;
    var next = page;
    final removed = <int>[];
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null && (s.locked || isOnLockedLayer(id))) {
        continue; // locked shapes / layers can't be deleted
      }
      next = next.removeShapeById(id);
      removed.add(id);
    }
    if (identical(next, page)) return;
    _selection.removeAll(removed);
    applyEdit(doc.replacePage(_currentPageIndex, next));
  }

  /// Delete a single shape by [id] (recursing into groups) as one undo step.
  void deleteShapeById(int id) {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null) return;
    final target = page.findShapeById(id);
    if (target != null &&
        (target.locked || isOnLockedLayer(id))) {
      return; // locked shapes / layers can't be deleted
    }
    final next = page.removeShapeById(id);
    if (identical(next, page)) return;
    _selection.remove(id);
    applyEdit(doc.replacePage(_currentPageIndex, next));
  }

  /// Whether [id] is an empty, borderless text box (no text, no fill, no line,
  /// no children) — the drawio "abandoned Text tool" case the canvas removes
  /// when the user commits or cancels without typing anything.
  bool isBlankTextBox(int id) {
    final s = currentPage?.findShapeById(id);
    if (s == null || s.is1D || s.children.isNotEmpty) return false;
    final hasText = s.richText.runs.isNotEmpty
        ? s.richText.plainText.trim().isNotEmpty
        : (s.text?.trim().isNotEmpty ?? false);
    return !hasText && s.fill.pattern == 0 && s.line.pattern == 0;
  }

  // --- Lock / unlock (drawio "Lock/Unlock", Cmd+L) ---------------------------

  /// Whether every shape in the selection is locked. Drives the toggle
  /// direction and the panel / menu state. `false` for an empty selection.
  bool get selectionLocked {
    final page = currentPage;
    if (page == null || _selection.isEmpty) return false;
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s == null || !s.locked) return false;
    }
    return true;
  }

  /// drawio "Lock/Unlock": lock the whole selection when any shape is still
  /// unlocked, otherwise unlock it. One undo step.
  void toggleLock() => setSelectionLocked(!selectionLocked);

  /// Set the locked flag on every selected shape (one undo step). Locked
  /// shapes can be selected but not moved, resized, rotated, deleted or
  /// text-edited.
  void setSelectionLocked(bool locked) {
    if (_selection.isEmpty) return;
    _updateSelectedShapes(
      (s) => s.locked == locked ? s : s.copyWith(locked: locked),
    );
  }

  List<VsdxShape> _clipboard = const <VsdxShape>[];
  bool get hasClipboard => _clipboard.isNotEmpty;

  /// Copy the current selection into the in-app clipboard **and** the system
  /// clipboard (encoded as a tiny `.vsdx` envelope for cross-instance paste).
  void copySelection() {
    final page = currentPage;
    if (page == null || _selection.isEmpty) return;
    _clipboard = <VsdxShape>[
      for (final id in _selection)
        if (page.findShapeById(id) != null) page.findShapeById(id)!,
    ];
    notifyListeners();
    unawaited(_writeSystemClipboard(_clipboard));
  }

  Future<void> _writeSystemClipboard(List<VsdxShape> shapes) async {
    try {
      final envelope = ShapeClipboardCodec.encode(shapes);
      if (envelope.isEmpty) {
        // Fall back to joined labels so external apps still get something.
        final labels = <String>[
          for (final s in shapes)
            if ((s.text ?? '').trim().isNotEmpty) s.text!.trim(),
        ];
        if (labels.isEmpty) return;
        await Clipboard.setData(ClipboardData(text: labels.join('\n')));
        return;
      }
      await Clipboard.setData(ClipboardData(text: envelope));
    } catch (_) {
      // Clipboard can fail in headless tests / locked pasteboards — ignore.
    }
  }

  /// Pull shapes (or plain text) from the system clipboard into [_clipboard].
  /// Returns `true` when [_clipboard] was updated.
  Future<bool> syncClipboardFromSystem() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.isEmpty) return false;
      final shapes = ShapeClipboardCodec.decode(text);
      if (shapes != null) {
        if (shapes.isEmpty) return false;
        _clipboard = shapes;
        notifyListeners();
        return true;
      }
      // External plain text → a single text box ready to paste.
      final trimmed = text.trim();
      if (trimmed.isEmpty || ShapeClipboardCodec.looksLikeEnvelope(text)) {
        return false;
      }
      _clipboard = <VsdxShape>[
        VsdxShapeFactory.textBox(
          id: 1,
          pinX: 0,
          pinY: 0,
          width: 1.6,
          height: 0.6,
          text: trimmed,
        ),
      ];
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Cut = copy the selection to the clipboard, then delete it.
  void cut() {
    if (_selection.isEmpty) return;
    copySelection();
    deleteSelection();
  }

  /// Paste clipboard shapes onto the current page (offset, freshly id'd).
  void paste() => pasteAt();

  /// Like [pasteAt], but first refreshes from the system clipboard so paste
  /// works across app instances / after external copy.
  Future<void> pasteFromSystem({double? cx, double? cy}) async {
    await syncClipboardFromSystem();
    pasteAt(cx: cx, cy: cy);
  }

  /// Paste the clipboard. With ([cx],[cy]) the shapes are positioned so their
  /// bounding-box centre lands on that page point (drawio's "Paste Here");
  /// otherwise they are offset slightly from the originals. Freshly id'd and
  /// selected; one undo step.
  void pasteAt({double? cx, double? cy}) {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null || _clipboard.isEmpty) return;
    var dx = 0.25, dy = -0.25;
    if (cx != null && cy != null) {
      var minX = double.infinity, minY = double.infinity;
      var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
      for (final s in _clipboard) {
        minX = math.min(minX, s.pinX - s.width / 2);
        minY = math.min(minY, s.pinY - s.height / 2);
        maxX = math.max(maxX, s.pinX + s.width / 2);
        maxY = math.max(maxY, s.pinY + s.height / 2);
      }
      dx = snap(cx) - (minX + maxX) / 2;
      dy = snap(cy) - (minY + maxY) / 2;
    }
    var next = page;
    final newIds = <int>{};
    for (final s in _clipboard) {
      final newId = next.nextFreeShapeId();
      next = next.addShape(
        s.copyWith(id: newId, pinX: s.pinX + dx, pinY: s.pinY + dy),
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
    final movedIds = _subtreeIds(deltas.keys);
    updateCurrentPage((p) {
      var next = p;
      deltas.forEach((id, d) {
        next = next.updateShapeById(
          id,
          (s) => s.copyWith(pinX: s.pinX + d.$1, pinY: s.pinY + d.$2),
        );
      });
      return next.rerouteConnectors(movedShapeIds: movedIds);
    });
  }

  /// Align a single selection to the page box (draw.io "to page" when one
  /// shape is selected). Multi-selection keeps relative-to-selection align.
  void _alignToPage((double, double) Function(VsdxPage page, VsdxShape s) delta) {
    final page = currentPage;
    final id = singleSelectedId;
    if (page == null || id == null) return;
    final s = page.findShapeById(id);
    if (s == null) return;
    final d = delta(page, s);
    if (d.$1 == 0 && d.$2 == 0) return;
    final movedIds = _subtreeIds(<int>{id});
    updateCurrentPage((p) => p
        .updateShapeById(
          id,
          (sh) => sh.copyWith(pinX: sh.pinX + d.$1, pinY: sh.pinY + d.$2),
        )
        .rerouteConnectors(movedShapeIds: movedIds));
  }

  void alignLeft() {
    if (_selection.length == 1) {
      _alignToPage((_, s) => (0.0 - _bounds(s).$1, 0.0));
      return;
    }
    _align((shapes) {
      final target = shapes.map((s) => _bounds(s).$1).reduce(math.min);
      return {for (final s in shapes) s.id: (target - _bounds(s).$1, 0.0)};
    });
  }

  void alignRight() {
    if (_selection.length == 1) {
      _alignToPage((page, s) => (page.widthInches - _bounds(s).$3, 0.0));
      return;
    }
    _align((shapes) {
      final target = shapes.map((s) => _bounds(s).$3).reduce(math.max);
      return {for (final s in shapes) s.id: (target - _bounds(s).$3, 0.0)};
    });
  }

  void alignCenterH() {
    if (_selection.length == 1) {
      _alignToPage((page, s) => (page.widthInches / 2 - s.pinX, 0.0));
      return;
    }
    _align((shapes) {
      final l = shapes.map((s) => _bounds(s).$1).reduce(math.min);
      final r = shapes.map((s) => _bounds(s).$3).reduce(math.max);
      final target = (l + r) / 2;
      return {for (final s in shapes) s.id: (target - s.pinX, 0.0)};
    });
  }

  void alignTop() {
    if (_selection.length == 1) {
      _alignToPage((page, s) => (0.0, page.heightInches - _bounds(s).$4));
      return;
    }
    _align((shapes) {
      final target = shapes.map((s) => _bounds(s).$4).reduce(math.max);
      return {for (final s in shapes) s.id: (0.0, target - _bounds(s).$4)};
    });
  }

  void alignBottom() {
    if (_selection.length == 1) {
      _alignToPage((_, s) => (0.0, 0.0 - _bounds(s).$2));
      return;
    }
    _align((shapes) {
      final target = shapes.map((s) => _bounds(s).$2).reduce(math.min);
      return {for (final s in shapes) s.id: (0.0, target - _bounds(s).$2)};
    });
  }

  void alignMiddle() {
    if (_selection.length == 1) {
      _alignToPage((page, s) => (0.0, page.heightInches / 2 - s.pinY));
      return;
    }
    _align((shapes) {
      final b = shapes.map((s) => _bounds(s).$2).reduce(math.min);
      final t = shapes.map((s) => _bounds(s).$4).reduce(math.max);
      final target = (b + t) / 2;
      return {for (final s in shapes) s.id: (0.0, target - s.pinY)};
    });
  }

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

  /// Make every other selected shape match the first selection's width
  /// (draw.io Arrange → Same width). Keeps each shape's left edge.
  void matchSelectionWidth() => _matchSelectionSize(width: true, height: false);

  /// Make every other selected shape match the first selection's height
  /// (draw.io Arrange → Same height). Keeps each shape's top edge.
  void matchSelectionHeight() =>
      _matchSelectionSize(width: false, height: true);

  /// Make every other selected shape match the first selection's width and
  /// height (draw.io Arrange → Same size).
  void matchSelectionSize() => _matchSelectionSize(width: true, height: true);

  void _matchSelectionSize({required bool width, required bool height}) {
    final ref = _firstSelected;
    if (ref == null || _selection.length < 2) return;
    final tw = ref.width;
    final th = ref.height;
    if ((width && tw <= 0) || (height && th <= 0)) return;
    final movedIds = _subtreeIds(_selection);
    updateCurrentPage((page) {
      var next = page;
      var changed = false;
      for (final id in _selection) {
        if (id == ref.id) continue;
        final s = next.findShapeById(id);
        if (s == null || s.locked || s.is1D) continue;
        final nw = width ? tw : s.width;
        final nh = height ? th : s.height;
        if ((nw - s.width).abs() < 1e-9 && (nh - s.height).abs() < 1e-9) {
          continue;
        }
        final left = s.pinX - s.width / 2;
        final top = s.pinY + s.height / 2;
        next = next.updateShapeById(
          id,
          (sh) => sh.resizeTo(
            pinX: left + nw / 2,
            pinY: top - nh / 2,
            width: nw,
            height: nh,
          ),
        );
        changed = true;
      }
      return changed
          ? next.rerouteConnectors(movedShapeIds: movedIds)
          : page;
    });
  }

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

  /// Move the selection one step forward in z-order (drawio "Bring Forward").
  void bringSelectionForward() {
    if (_selection.isEmpty) return;
    updateCurrentPage((page) {
      var next = page;
      for (final id in _selection) {
        next = next.bringForward(id);
      }
      return next;
    });
  }

  /// Move the selection one step backward in z-order (drawio "Send Backward").
  void sendSelectionBackward() {
    if (_selection.isEmpty) return;
    updateCurrentPage((page) {
      var next = page;
      for (final id in _selection) {
        next = next.sendBackward(id);
      }
      return next;
    });
  }

  // --- Arrange (numeric geometry, flip, rotate) ------------------------------

  /// The single selected shape, or `null` when zero / many are selected.
  VsdxShape? get singleSelected {
    if (_selection.length != 1) return null;
    return currentPage?.findShapeById(_selection.first);
  }

  /// Position / size / rotation of the single selection for the Arrange panel.
  /// `x`/`y` are the top-left of the axis-aligned box in inches measured from
  /// the page's top-left (Y-down, matching the on-screen canvas); `angleDeg`
  /// is the rotation in degrees (Visio CCW convention).
  ({double x, double y, double w, double h, double angleDeg})? get selectedGeometry {
    final s = singleSelected;
    final page = currentPage;
    if (s == null || page == null) return null;
    return (
      x: s.pinX - s.width / 2,
      y: page.heightInches - (s.pinY + s.height / 2),
      w: s.width,
      h: s.height,
      angleDeg: s.angleRad * 180 / math.pi,
    );
  }

  /// Move the single selection so its left edge sits at [x] inches.
  void setSelectedX(double x) {
    final s = singleSelected;
    if (s == null) return;
    _moveSingle(s, x + s.width / 2, s.pinY);
  }

  /// Move the single selection so its top edge sits at [y] inches from the
  /// page top (Y-down).
  void setSelectedY(double y) {
    final s = singleSelected;
    final page = currentPage;
    if (s == null || page == null) return;
    _moveSingle(s, s.pinX, page.heightInches - y - s.height / 2);
  }

  void _moveSingle(VsdxShape s, double pinX, double pinY) {
    final movedIds = _subtreeIds(<int>{s.id});
    updateCurrentPage(
      (page) => page
          .updateShapeById(s.id, (sh) => _translated(sh, pinX - sh.pinX, pinY - sh.pinY))
          .rerouteConnectors(movedShapeIds: movedIds),
    );
  }

  /// Resize the single selection to [w] inches wide, keeping its left edge.
  void setSelectedWidth(double w) {
    final s = singleSelected;
    if (s == null || w <= 0) return;
    final left = s.pinX - s.width / 2;
    resizeShape(s.id, pinX: left + w / 2, pinY: s.pinY, width: w, height: s.height);
  }

  /// Resize the single selection to [h] inches tall, keeping its top edge.
  void setSelectedHeight(double h) {
    final s = singleSelected;
    if (s == null || h <= 0) return;
    final top = s.pinY + s.height / 2;
    resizeShape(s.id, pinX: s.pinX, pinY: top - h / 2, width: s.width, height: h);
  }

  /// Set the single selection's rotation from a value in degrees.
  void setSelectedAngleDegrees(double deg) {
    final s = singleSelected;
    if (s == null) return;
    rotateShape(s.id, deg * math.pi / 180);
  }

  /// Rotate every selected shape 90° about its own pin (drawio Ctrl+R). Pass
  /// `clockwise: false` to turn the other way.
  void rotateSelection90({bool clockwise = true}) {
    if (_selection.isEmpty) return;
    // Visio angles are CCW-positive, so a clockwise turn subtracts 90°.
    final delta = (clockwise ? -1 : 1) * math.pi / 2;
    final movedIds = _subtreeIds(_selection);
    updateCurrentPage((page) {
      var next = page;
      var rotated = false;
      for (final id in _selection) {
        final s = page.findShapeById(id);
        if (s == null || s.locked) continue; // locked shapes don't rotate
        next = next.updateShapeById(
            id, (s) => s.copyWith(angleRad: s.angleRad + delta));
        rotated = true;
      }
      return rotated
          ? next.rerouteConnectors(movedShapeIds: movedIds)
          : page;
    });
  }

  /// Mirror the selected shapes horizontally (`FlipX`). Locked shapes skip.
  void flipHorizontal() =>
      _updateSelectedShapes((s) => s.locked ? s : s.copyWith(flipX: !s.flipX));

  /// Mirror the selected shapes vertically (`FlipY`). Locked shapes skip.
  void flipVertical() =>
      _updateSelectedShapes((s) => s.locked ? s : s.copyWith(flipY: !s.flipY));

  // --- Rounded corners (drawio "Rounded" + arc size) -------------------------

  /// Whether [s] is a plain or rounded rectangle (axis-aligned edges, only
  /// straight segments + corner arcs) — the shapes corner-rounding applies to.
  static bool _isRectangleLike(VsdxShape s) {
    if (s.is1D || s.geometries.length != 1) return false;
    final g = s.geometries.first;
    if (g.noShow || g.commands.isEmpty) return false;
    double? px, py;
    for (final c in g.commands) {
      switch (c) {
        case MoveTo(:final x, :final y):
          px = x;
          py = y;
        case LineTo(:final x, :final y):
          if (px != null && py != null) {
            if ((x - px).abs() > 1e-6 && (y - py).abs() > 1e-6) return false;
          }
          px = x;
          py = y;
        case EllipticalArcTo(:final x, :final y):
          px = x;
          py = y;
        default:
          return false;
      }
    }
    return true;
  }

  /// Current corner radius (inches) of the single selection when it is a
  /// rectangle, or `null` when corner-rounding doesn't apply.
  double? get selectedCornerRadius {
    final s = singleSelected;
    if (s == null || !_isRectangleLike(s)) return null;
    final g = s.geometries.first;
    if (!g.commands.any((c) => c is EllipticalArcTo)) return 0;
    final first = g.commands.first;
    return first is MoveTo ? first.x : 0;
  }

  /// Round the single (rectangular) selection's corners to [radiusInches]
  /// (0 = square), regenerating its geometry. Round-trips as `EllipticalArcTo`.
  void setCornerRadius(double radiusInches, {bool transient = false}) {
    final s = singleSelected;
    if (s == null || !_isRectangleLike(s)) return;
    final geom =
        VsdxShapeFactory.roundedRectGeometry(s.width, s.height, radiusInches);
    updateCurrentPage(
      (page) => page.updateShapeById(
        s.id,
        (sh) => sh.copyWith(geometries: <VsdxGeometry>[geom]),
      ),
      transient: transient,
    );
  }

  void _updateSelectedShapes(
    VsdxShape Function(VsdxShape) update, {
    bool transient = false,
    bool rememberStyle = false,
  }) {
    if (_selection.isEmpty) return;
    updateCurrentPage((page) {
      var next = page;
      for (final id in _selection) {
        next = next.updateShapeById(id, update);
      }
      return next;
    }, transient: transient);
    if (rememberStyle) _rememberStyle();
  }

  /// Remember the first selection's fill / line so new shapes inherit it
  /// (drawio's `currentVertexStyle`).
  void _rememberStyle() {
    final s = _firstSelected;
    if (s == null) return;
    _memoFill = s.fill;
    _memoLine = s.line;
  }

  /// Apply the remembered style to a freshly-created shape. Lines/connectors
  /// take only the stroke (never a fill).
  VsdxShape _withMemoStyle(VsdxShape s, {required bool includeFill}) {
    var r = s;
    if (includeFill && _memoFill != null) r = r.copyWith(fill: _memoFill);
    if (_memoLine != null) {
      // Arrowheads belong on 1-D connectors. A memo line remembered from a
      // connector must not stamp BeginArrow/EndArrow onto boxes/ellipses —
      // otherwise the export shows stray arrowheads in 万兴图示 on vertices.
      final memo = _memoLine!;
      final line = (!s.is1D && (memo.beginArrow != 0 || memo.endArrow != 0))
          ? memo.copyWith(beginArrow: 0, endArrow: 0)
          : memo;
      r = r.copyWith(line: line);
    }
    return r;
  }

  /// The first selected shape, or null — used by the inspector to reflect the
  /// current fill / line / text style.
  VsdxShape? get _firstSelected {
    final page = currentPage;
    if (page == null) return null;
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null) return s;
    }
    return null;
  }

  VsdxFill? get selectedFill => _firstSelected?.fill;
  VsdxLine? get selectedLine => _firstSelected?.line;

  void setFillColor(VsdxColor color) => _updateSelectedShapes(
        (s) => s.copyWith(fill: s.fill.withSolidForeground(color)),
        rememberStyle: true,
      );

  /// Bind selected shapes' fill to a document theme colour slot (draw.io
  /// theme swatch). Installs the Office palette when the document has none.
  void setFillThemeSlot(int slot) {
    _applyThemeSlotToSelection(
      slot,
      (s) => s.copyWith(fill: s.fill.withThemeForeground(slot)),
    );
  }

  void setNoFill() => _updateSelectedShapes(
        (s) => s.copyWith(fill: s.fill.copyWith(pattern: 0, gradient: null)),
        rememberStyle: true,
      );

  /// Set or clear the selection's fill gradient (draw.io Format → Gradient).
  /// `null` removes the gradient and leaves the solid fill colour.
  void setFillGradient(VsdxGradient? gradient) => _updateSelectedShapes(
        (s) => s.copyWith(fill: s.fill.withGradient(gradient)),
        rememberStyle: true,
      );

  void setLineColor(VsdxColor color) => _updateSelectedShapes(
        (s) => s.copyWith(line: s.line.withSolidColor(color)),
        rememberStyle: true,
      );

  /// Bind selected shapes' stroke to a document theme colour slot.
  void setLineThemeSlot(int slot) {
    _applyThemeSlotToSelection(
      slot,
      (s) => s.copyWith(line: s.line.withThemeColor(slot)),
    );
  }

  /// Set or clear the selection's line gradient (draw.io Format → Line).
  void setLineGradient(VsdxGradient? gradient) => _updateSelectedShapes(
        (s) => s.copyWith(line: s.line.withGradient(gradient)),
        rememberStyle: true,
      );

  /// One undo step: ensure a document theme exists, then restyle selection.
  void _applyThemeSlotToSelection(
    int slot,
    VsdxShape Function(VsdxShape) update,
  ) {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null || _selection.isEmpty) return;
    var nextDoc = doc.theme.isEmpty ? doc.copyWith(theme: VsdxTheme.office) : doc;
    var nextPage = nextDoc.pages[_currentPageIndex];
    var changed = false;
    for (final id in _selection) {
      final s = nextPage.findShapeById(id);
      if (s == null || s.locked) continue;
      nextPage = nextPage.updateShapeById(id, update);
      changed = true;
    }
    if (!changed && identical(nextDoc, doc)) return;
    applyEdit(nextDoc.replacePage(_currentPageIndex, nextPage));
    _rememberStyle();
  }

  void setLineWeight(double inches) => _updateSelectedShapes(
        (s) => s.copyWith(
          line: s.line.copyWith(
            weightInches: inches,
            pattern: s.line.pattern == 0 ? 1 : s.line.pattern,
          ),
        ),
        rememberStyle: true,
      );

  void setNoLine() => _updateSelectedShapes(
        (s) => s.copyWith(line: s.line.copyWith(pattern: 0, gradient: null)),
        rememberStyle: true,
      );

  /// Set the line dash pattern (Visio `LinePattern`: 1 = solid, 2 = dashed,
  /// 3 = dotted, 4 = dash-dot…). Re-enables the line if it was off.
  void setLinePattern(int pattern) => _updateSelectedShapes(
        (s) => s.copyWith(line: s.line.copyWith(pattern: pattern)),
        rememberStyle: true,
      );

  /// Toggle / set the connector arrowheads (0 = none, 1 = a basic arrow).
  /// Pass only the end(s) you want to change.
  void setLineArrows({int? begin, int? end}) => _updateSelectedShapes(
        (s) =>
            s.copyWith(line: s.line.copyWith(beginArrow: begin, endArrow: end)),
        rememberStyle: true,
      );

  /// Set the start arrowhead type (`BeginArrow` id; 0 = none). See
  /// `lib/render/arrow_library.dart` for the id → shape mapping.
  void setBeginArrow(int id) => setLineArrows(begin: id);

  /// Set the end arrowhead type (`EndArrow` id; 0 = none).
  void setEndArrow(int id) => setLineArrows(end: id);

  /// Visio `BeginArrowSize` / `EndArrowSize` buckets (inches).
  static const List<double> arrowSizeBuckets = <double>[
    0.0625,
    0.0875,
    0.125,
    0.175,
    0.225,
    0.30,
    0.375,
  ];

  /// Set start / end arrowhead sizes (inches; nearest Visio bucket on write).
  void setLineArrowSizes({double? beginInches, double? endInches}) =>
      _updateSelectedShapes(
        (s) => s.copyWith(
          line: s.line.copyWith(
            beginArrowSizeInches: beginInches,
            endArrowSizeInches: endInches,
          ),
        ),
        rememberStyle: true,
      );

  void setBeginArrowSize(double inches) =>
      setLineArrowSizes(beginInches: inches);

  void setEndArrowSize(double inches) => setLineArrowSizes(endInches: inches);

  /// Set Visio `FillPattern` (`0` none, `1` solid, `>1` hatch). Clears gradient
  /// when switching to a hatch so the pattern is visible.
  void setFillPattern(int pattern) => _updateSelectedShapes(
        (s) => s.copyWith(
          fill: s.fill.copyWith(
            pattern: pattern,
            gradient: pattern > 1 ? null : VsdxFill.keepGradient,
          ),
        ),
        rememberStyle: true,
      );

  /// Fill opacity in 0..1 (1 = opaque). Stored as `FillForegndTrans = 1-opacity`.
  void setFillOpacity(double opacity, {bool transient = false}) =>
      _updateSelectedShapes(
        (s) => s.copyWith(
          fill: s.fill.copyWith(
            foregroundTransparency: (1 - opacity).clamp(0.0, 1.0),
          ),
        ),
        transient: transient,
        rememberStyle: true,
      );

  /// Line opacity in 0..1 (1 = opaque). Stored as `LineColorTrans = 1-opacity`.
  void setLineOpacity(double opacity, {bool transient = false}) =>
      _updateSelectedShapes(
        (s) => s.copyWith(
          line: s.line.copyWith(transparency: (1 - opacity).clamp(0.0, 1.0)),
        ),
        transient: transient,
        rememberStyle: true,
      );

  // --- Connector routing style (drawio straight / orthogonal edges) ----------

  /// Whether the selection includes at least one connector (1-D shape).
  bool get hasConnectorSelected {
    final page = currentPage;
    if (page == null) return false;
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null && s.is1D) return true;
    }
    return false;
  }

  /// Whether the first selected connector is drawn as a straight segment.
  bool get selectedConnectorStraight {
    final page = currentPage;
    if (page == null) return false;
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null && s.is1D) return page.isConnectorStraight(id);
    }
    return false;
  }

  /// The routing style of the first selected connector (drawio Straight /
  /// Orthogonal / Curved). Falls back to [ConnectorRouteStyle.orthogonal].
  ConnectorRouteStyle get selectedConnectorRouteStyle {
    final page = currentPage;
    if (page == null) return ConnectorRouteStyle.orthogonal;
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null && s.is1D) {
        if (s.curved) return ConnectorRouteStyle.curved;
        return s.straightRoute
            ? ConnectorRouteStyle.straight
            : ConnectorRouteStyle.orthogonal;
      }
    }
    return ConnectorRouteStyle.orthogonal;
  }

  /// Route the selected connectors straight or orthogonally (binary form kept
  /// for callers that don't need the curved option).
  void setConnectorStyle({required bool straight}) =>
      setConnectorRouteStyle(straight
          ? ConnectorRouteStyle.straight
          : ConnectorRouteStyle.orthogonal);

  /// Apply a three-way routing [style] to the selected connectors.
  void setConnectorRouteStyle(ConnectorRouteStyle style) {
    if (_selection.isEmpty) return;
    updateCurrentPage(
      (page) => page.setConnectorStyle(
        _selection.toSet(),
        straight: style == ConnectorRouteStyle.straight,
        curved: style == ConnectorRouteStyle.curved,
      ),
    );
  }

  /// Whether the first selected connector rounds its route corners (drawio's
  /// "Rounded" edge option).
  bool get selectedConnectorRounded {
    final page = currentPage;
    if (page == null) return false;
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null && s.is1D) return s.rounded;
    }
    return false;
  }

  /// Toggle drawio-style rounded corners on the selected connectors (one undo
  /// step). Ignored for curved connectors (already smooth) and has no visible
  /// effect on a two-point straight route.
  void setConnectorRounded(bool rounded) {
    if (_selection.isEmpty) return;
    updateCurrentPage(
      (page) => page.setConnectorRounded(_selection.toSet(), rounded),
    );
  }

  // --- Connector waypoints (drawio bend points) ------------------------------

  List<Offset2D> connectorWaypoints(int id) =>
      currentPage?.findShapeById(id)?.waypoints ?? const <Offset2D>[];

  void setConnectorWaypoints(
    int id,
    List<Offset2D> waypoints, {
    bool transient = false,
  }) {
    updateCurrentPage(
      (page) => page.setConnectorWaypoints(id, waypoints),
      transient: transient,
    );
  }

  void moveWaypoint(int id, int index, Offset2D p, {bool transient = false}) {
    final wps = List<Offset2D>.of(connectorWaypoints(id));
    if (index < 0 || index >= wps.length) return;
    wps[index] = p;
    setConnectorWaypoints(id, wps, transient: transient);
  }

  void addWaypoint(int id, int index, Offset2D p, {bool transient = false}) {
    final wps = List<Offset2D>.of(connectorWaypoints(id));
    wps.insert(index.clamp(0, wps.length), p);
    setConnectorWaypoints(id, wps, transient: transient);
  }

  void removeWaypoint(int id, int index) {
    final wps = List<Offset2D>.of(connectorWaypoints(id));
    if (index < 0 || index >= wps.length) return;
    wps.removeAt(index);
    setConnectorWaypoints(id, wps);
  }

  /// Reconnect (or detach) one end of connector [connectorId] — drawio's
  /// endpoint editing. When [targetShapeId] is non-null the end is glued to
  /// that shape; otherwise it floats at page point ([x],[y]). Pass
  /// `transient: true` while dragging and commit once on release.
  void reconnectEndpoint(
    int connectorId, {
    required bool begin,
    int? targetShapeId,
    int? connectionPointIndex,
    required double x,
    required double y,
    bool transient = false,
  }) {
    updateCurrentPage(
      (page) => page.setConnectorEndpoint(
        connectorId,
        begin: begin,
        targetShapeId: targetShapeId,
        connectionPointIndex: connectionPointIndex,
        x: x,
        y: y,
      ),
      transient: transient,
    );
  }

  // --- Edit connection points (drawio "Edit Connection Points") --------------

  bool _editingConnectionPoints = false;
  int? _selectedConnectionPointIndex;

  /// Whether the canvas is in connection-point edit mode for the selection.
  bool get editingConnectionPoints => _editingConnectionPoints;

  /// Index of the connection point currently selected for delete / highlight.
  int? get selectedConnectionPointIndex => _selectedConnectionPointIndex;

  /// A single unlocked 2-D shape is selected (eligible for connection editing).
  bool get canEditConnectionPoints {
    final id = singleSelectedId;
    if (id == null) return false;
    final s = currentPage?.findShapeById(id);
    return s != null && !s.is1D && !s.locked && !isOnLockedLayer(id);
  }

  void _leaveConnectionPointEdit() {
    _editingConnectionPoints = false;
    _selectedConnectionPointIndex = null;
  }

  /// Enter draw.io-style connection-point edit mode. Materialises the default
  /// 5 points when the shape has none yet (one undo step).
  void beginEditConnectionPoints() {
    if (!canEditConnectionPoints) return;
    final id = singleSelectedId!;
    final s = currentPage!.findShapeById(id)!;
    _editingConnectionPoints = true;
    _selectedConnectionPointIndex = null;
    _tool = EditorTool.select;
    if (s.connectionPoints.isEmpty) {
      updateCurrentPage((p) => p.materializeConnectionPoints(id));
    } else {
      notifyListeners();
    }
  }

  /// Leave connection-point edit mode (keeps the shape selected).
  void endEditConnectionPoints() {
    if (!_editingConnectionPoints) return;
    _leaveConnectionPointEdit();
    notifyListeners();
  }

  void selectConnectionPoint(int? index) {
    if (!_editingConnectionPoints) return;
    if (_selectedConnectionPointIndex == index) return;
    _selectedConnectionPointIndex = index;
    notifyListeners();
  }

  /// Add a connection point at shape-local inches (one undo step).
  void addConnectionPointAtLocal(double localX, double localY) {
    final id = singleSelectedId;
    if (!_editingConnectionPoints || id == null) return;
    updateCurrentPage((p) => p.addConnectionPoint(id, localX, localY));
    final len =
        currentPage?.findShapeById(id)?.connectionPoints.length ?? 0;
    if (len > 0) {
      _selectedConnectionPointIndex = len - 1;
      notifyListeners();
    }
  }

  /// Move connection point [index] to shape-local inches.
  void moveConnectionPointAtLocal(
    int index,
    double localX,
    double localY, {
    bool transient = false,
  }) {
    final id = singleSelectedId;
    if (!_editingConnectionPoints || id == null) return;
    _selectedConnectionPointIndex = index;
    updateCurrentPage(
      (p) => p.moveConnectionPoint(id, index, localX, localY),
      transient: transient,
    );
  }

  /// Delete the selected connection point (or [index] when given).
  void removeSelectedConnectionPoint([int? index]) {
    final id = singleSelectedId;
    final i = index ?? _selectedConnectionPointIndex;
    if (!_editingConnectionPoints || id == null || i == null) return;
    updateCurrentPage((p) => p.removeConnectionPoint(id, i));
    final len =
        currentPage?.findShapeById(id)?.connectionPoints.length ?? 0;
    _selectedConnectionPointIndex =
        len == 0 ? null : i.clamp(0, len - 1);
    notifyListeners();
  }

  /// Whether any selected connector has interior bend points to clear.
  bool get canClearWaypoints {
    final page = currentPage;
    if (page == null) return false;
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null && s.is1D && s.waypoints.isNotEmpty) return true;
    }
    return false;
  }

  /// Reset the selected connectors to their plain straight / elbow route
  /// (drawio "Clear Waypoints"). One undo step; no-op when there's nothing to
  /// clear.
  void clearSelectedConnectorWaypoints() {
    final page = currentPage;
    if (page == null) return;
    final targets = <int>[
      for (final id in _selection)
        if (page.findShapeById(id)?.waypoints.isNotEmpty ?? false) id,
    ];
    if (targets.isEmpty) return;
    updateCurrentPage((p) {
      var next = p;
      for (final id in targets) {
        next = next.clearConnectorWaypoints(id);
      }
      return next;
    });
  }

  // --- Copy / paste style (drawio "Copy Style" / "Paste Style") --------------

  ({VsdxFill fill, VsdxLine line, VsdxCharStyle? char, VsdxParaStyle? para})?
      _styleClipboard;
  bool get hasStyleClipboard => _styleClipboard != null;

  /// Capture the fill / line / text styling of the first selected shape.
  void copyStyle() {
    final page = currentPage;
    if (page == null) return;
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null) {
        final run = s.richText.runs.isNotEmpty ? s.richText.runs.first : null;
        _styleClipboard = (
          fill: s.fill,
          line: s.line,
          char: run?.charStyle,
          para: run?.paraStyle,
        );
        notifyListeners();
        return;
      }
    }
  }

  /// Apply the copied styling to every selected shape (one undo step).
  void pasteStyle() {
    final clip = _styleClipboard;
    if (clip == null) return;
    _updateSelectedShapes((s) {
      var next = s.copyWith(fill: clip.fill, line: clip.line);
      if (clip.char != null || clip.para != null) {
        var runs = next.richText.runs;
        if (runs.isEmpty) {
          final t = next.text;
          if (t != null && t.isNotEmpty) {
            runs = <VsdxTextRun>[VsdxTextRun(text: t)];
          }
        }
        if (runs.isNotEmpty) {
          next = next.copyWith(
            richText: next.richText.copyWith(
              runs: <VsdxTextRun>[
                for (final r in runs)
                  r.copyWith(
                    charStyle: clip.char ?? r.charStyle,
                    paraStyle: clip.para ?? r.paraStyle,
                  ),
              ],
            ),
          );
        }
      }
      return next;
    }, rememberStyle: true);
  }

  // --- Shape data (drawio "Edit Data", Cmd+M) --------------------------------

  /// The id of the single selected shape, or `null` when zero / many are
  /// selected. Used to scope shape-data editing to one shape.
  int? get singleSelectedId => _selection.length == 1 ? _selection.first : null;

  /// The custom properties (`<Section N="Property">`, Visio "Shape Data") of
  /// the single selection, or an empty list.
  List<VsdxUserProperty> get selectedProperties =>
      singleSelected?.userProperties ?? const <VsdxUserProperty>[];

  /// Replace a shape's Shape Data with [props] (one undo step). Empty [props]
  /// clears the `<Section N="Property">` on save. Names should be unique;
  /// duplicates are dropped keeping the first occurrence.
  void setShapeProperties(int shapeId, List<VsdxUserProperty> props) {
    final seen = <String>{};
    final unique = <VsdxUserProperty>[
      for (final p in props)
        if (p.name.trim().isNotEmpty && seen.add(p.name)) p,
    ];
    updateCurrentPage(
      (page) => page.updateShapeById(
        shapeId,
        (s) => s.copyWith(userProperties: unique),
      ),
    );
  }

  // --- Hyperlinks (drawio "Edit Link" / Cmd+K) -------------------------------

  /// The single selection's hyperlink rows (`<Section N="Hyperlink">`), or an
  /// empty list.
  List<VsdxHyperlink> get selectedHyperlinks =>
      singleSelected?.hyperlinks ?? const <VsdxHyperlink>[];

  /// The primary hyperlink of the single selection (the one invoked on click),
  /// or `null` when there's no single selection / no link.
  VsdxHyperlink? get selectedLink => singleSelected?.primaryHyperlink;

  /// Replace a shape's hyperlinks with [links] (one undo step). An empty list
  /// clears the `<Section N="Hyperlink">` on save.
  void setShapeHyperlinks(int shapeId, List<VsdxHyperlink> links) {
    updateCurrentPage(
      (page) => page.updateShapeById(
        shapeId,
        (s) => s.copyWith(hyperlinks: links),
      ),
    );
  }

  // --- Grouping (drawio "Group" / "Ungroup") ---------------------------------

  /// Whether the selection has ≥ 2 top-level shapes that can be grouped.
  bool get canGroup {
    final page = currentPage;
    if (page == null) return false;
    var n = 0;
    for (final s in page.shapes) {
      if (_selection.contains(s.id)) {
        if (++n >= 2) return true;
      }
    }
    return false;
  }

  /// Whether the selection contains a top-level group that can be ungrouped.
  bool get canUngroup {
    final page = currentPage;
    if (page == null) return false;
    for (final s in page.shapes) {
      if (_selection.contains(s.id) && s.children.isNotEmpty) return true;
    }
    return false;
  }

  /// Group the selected top-level shapes into a new group and select it.
  void groupSelection() {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null) return;
    final ids = <int>{
      for (final s in page.shapes)
        if (_selection.contains(s.id)) s.id,
    };
    if (ids.length < 2) return;
    final gid = page.nextFreeShapeId();
    final next = page.group(ids, groupId: gid);
    if (identical(next, page)) return;
    _selection
      ..clear()
      ..add(gid);
    applyEdit(doc.replacePage(_currentPageIndex, next));
  }

  /// Ungroup every selected top-level group, selecting the promoted children.
  void ungroupSelection() {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null) return;
    final groups = <VsdxShape>[
      for (final s in page.shapes)
        if (_selection.contains(s.id) && s.children.isNotEmpty) s,
    ];
    if (groups.isEmpty) return;
    final childIds = <int>{
      for (final g in groups)
        for (final c in g.children) c.id,
    };
    var next = page;
    for (final g in groups) {
      next = next.ungroup(g.id);
    }
    if (identical(next, page)) return;
    _selection
      ..clear()
      ..addAll(childIds);
    applyEdit(doc.replacePage(_currentPageIndex, next));
  }

  static bool _containsCjk(String s) {
    for (final r in s.runes) {
      if (r >= 0x4E00 && r <= 0x9FFF) return true;
      if (r >= 0x3400 && r <= 0x4DBF) return true;
      if (r >= 0xF900 && r <= 0xFAFF) return true;
    }
    return false;
  }

  /// Replace a shape's label text. Preserves per-character styles across the
  /// common prefix/suffix so mixed-style labels are not flattened to the first
  /// run (draw.io-compatible editing).
  void setShapeText(int id, String text) => updateCurrentPage(
        (page) => page.updateShapeById(id, (s) => _withLabelText(s, text)),
      );

  /// Apply [text] to [s], preserving multi-run styles when possible.
  static VsdxShape _withLabelText(VsdxShape s, String text) {
    final runs = s.richText.runs;
    final current =
        runs.isNotEmpty ? s.richText.plainText : (s.text ?? '');
    if (current == text) return s;
    if (runs.isEmpty) {
      final box = math.min(s.width.abs(), s.height.abs());
      final sizeInches =
          (s.is1D ? 0.14 : box * 0.18).clamp(4.0 / 72.0, 1.0);
      final cjk = _containsCjk(text);
      return s.copyWith(
        text: text,
        richText: s.richText.copyWith(
          runs: <VsdxTextRun>[
            VsdxTextRun(
              text: text,
              charStyle: VsdxCharStyle(
                fontSizeInches: sizeInches,
                fontFamily: cjk ? 'Microsoft YaHei' : null,
                asianFont: 'Microsoft YaHei',
                langId: cjk ? 'zh-CN' : null,
              ),
              paraStyle: const VsdxParaStyle(
                horizontalAlign: VsdxHorzAlign.center,
              ),
            ),
          ],
        ),
      );
    }
    final next = replacePlainText(s.richText, text);
    return s.copyWith(text: text, richText: next);
  }

  static String _shapeLabel(VsdxShape s) =>
      s.richText.runs.isNotEmpty ? s.richText.plainText : (s.text ?? '');

  /// Case-insensitive replace of the first [query] in [source].
  static String replaceFirstIgnoreCase(
    String source,
    String query,
    String replacement,
  ) =>
      replaceFirstMatch(source, query, replacement, matchCase: false);

  /// Case-insensitive replace of every [query] in [source].
  static String replaceAllIgnoreCase(
    String source,
    String query,
    String replacement,
  ) =>
      replaceAllMatch(source, query, replacement, matchCase: false);

  /// Replace the first [query] in [source], honouring [matchCase] / [wholeWord].
  static String replaceFirstMatch(
    String source,
    String query,
    String replacement, {
    required bool matchCase,
    bool wholeWord = false,
  }) {
    if (query.isEmpty) return source;
    final hay = matchCase ? source : source.toLowerCase();
    final needle = matchCase ? query : query.toLowerCase();
    var i = 0;
    while (i <= hay.length - needle.length) {
      final at = hay.indexOf(needle, i);
      if (at < 0) return source;
      if (!wholeWord || _isWholeWordAt(hay, at, needle.length)) {
        return source.replaceRange(at, at + query.length, replacement);
      }
      i = at + 1;
    }
    return source;
  }

  /// Replace every [query] in [source], honouring [matchCase] / [wholeWord].
  static String replaceAllMatch(
    String source,
    String query,
    String replacement, {
    required bool matchCase,
    bool wholeWord = false,
  }) {
    if (query.isEmpty) return source;
    final hay = matchCase ? source : source.toLowerCase();
    final needle = matchCase ? query : query.toLowerCase();
    final buf = StringBuffer();
    var i = 0;
    while (i < source.length) {
      if (i + needle.length <= source.length &&
          hay.startsWith(needle, i) &&
          (!wholeWord || _isWholeWordAt(hay, i, needle.length))) {
        buf.write(replacement);
        i += query.length;
      } else {
        buf.writeCharCode(source.codeUnitAt(i));
        i++;
      }
    }
    return buf.toString();
  }

  static bool _isWholeWordAt(String hay, int at, int len) {
    final beforeOk = at == 0 || !_isWordChar(hay.codeUnitAt(at - 1));
    final after = at + len;
    final afterOk = after >= hay.length || !_isWordChar(hay.codeUnitAt(after));
    return beforeOk && afterOk;
  }

  // --- Text formatting (whole shape, or UTF-16 range while inline-editing) ---

  /// Shape currently being inline-edited (`null` when not editing).
  int? get textEditShapeId => _textEditShapeId;
  int? _textEditShapeId;

  /// UTF-16 selection inside the inline editor (`null` / collapsed ⇒ whole
  /// shape formatting when a toolbar action fires).
  ({int start, int end})? get textEditSelection => _textEditSelection;
  ({int start, int end})? _textEditSelection;

  /// Called by the canvas when entering / leaving / selecting inside the
  /// inline text editor so toolbar bold/color/size can target the range.
  void setTextEditSession({int? shapeId, int? start, int? end}) {
    final sel = (start != null && end != null) ? (start: start, end: end) : null;
    final changed = shapeId != _textEditShapeId ||
        sel?.start != _textEditSelection?.start ||
        sel?.end != _textEditSelection?.end;
    _textEditShapeId = shapeId;
    _textEditSelection = sel;
    if (changed) notifyListeners();
  }

  VsdxCharStyle? get selectedCharStyle {
    final page = currentPage;
    if (page == null) return null;
    final editId = _textEditShapeId;
    if (editId != null) {
      final s = page.findShapeById(editId);
      if (s != null && s.richText.runs.isNotEmpty) {
        final sel = _textEditSelection;
        final collapsed = sel == null || sel.start == sel.end;
        final idx = collapsed
            ? (sel?.start ?? 0)
            : math.min(sel.start, sel.end);
        return charStyleAt(s.richText, idx) ?? s.richText.runs.first.charStyle;
      }
    }
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
    final editId = _textEditShapeId;
    final sel = _textEditSelection;
    final useRange = editId != null &&
        sel != null &&
        sel.start != sel.end;

    if (useRange) {
      updateCurrentPage((page) {
        final s = page.findShapeById(editId);
        if (s == null) return page;
        var rich = s.richText;
        if (rich.runs.isEmpty) {
          final t = s.text;
          if (t == null || t.isEmpty) return page;
          rich = rich.copyWith(runs: <VsdxTextRun>[VsdxTextRun(text: t)]);
        }
        final a = math.min(sel.start, sel.end);
        final b = math.max(sel.start, sel.end);
        if (char != null) {
          rich = applyCharStyleToRange(rich, start: a, end: b, update: char);
        }
        if (para != null) {
          rich = applyParaStyleToRange(rich, start: a, end: b, update: para);
        }
        return page.updateShapeById(
          editId,
          (sh) => sh.copyWith(text: rich.plainText, richText: rich),
        );
      });
      return;
    }

    _updateSelectedShapes((s) {
      // Prefer the shape being edited when the caret is collapsed.
      if (editId != null && s.id != editId) return s;
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

  /// Toggle bold / italic / underline on the selection (draw.io Cmd+B/I/U).
  void toggleBold() => setBold(!(selectedCharStyle?.style.bold ?? false));

  void toggleItalic() =>
      setItalic(!(selectedCharStyle?.style.italic ?? false));

  void toggleUnderline() =>
      setUnderline(!(selectedCharStyle?.underline ?? false));

  void setTextColor(VsdxColor color) =>
      _updateText(char: (c) => c.withSolidColor(color));

  /// Bind selected / in-edit text colour to a document theme slot.
  void setTextThemeSlot(int slot) {
    final doc = _document;
    if (doc == null) return;
    if (doc.theme.isEmpty) {
      applyEdit(doc.copyWith(theme: VsdxTheme.office));
    }
    _updateText(char: (c) => c.withThemeColor(slot));
  }

  void setTextAlign(VsdxHorzAlign align) =>
      _updateText(para: (p) => p.copyWith(horizontalAlign: align));

  /// First selected (or in-edit) paragraph style — for Format Text spacing.
  VsdxParaStyle? get selectedParaStyle {
    final page = currentPage;
    if (page == null) return null;
    final editId = _textEditShapeId;
    if (editId != null) {
      final s = page.findShapeById(editId);
      if (s != null && s.richText.runs.isNotEmpty) {
        return s.richText.runs.first.paraStyle;
      }
    }
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null && s.richText.runs.isNotEmpty) {
        return s.richText.runs.first.paraStyle;
      }
    }
    return null;
  }

  /// Line height as a multiple of font size (Visio `SpLine` negative).
  void setLineSpacing(double multiple) => _updateText(
        para: (p) => p.copyWith(
          lineSpacing: multiple.clamp(0.5, 3.0),
          lineSpacingAbsoluteInches: 0,
          lineSpacingSolid: false,
        ),
      );

  /// Paragraph space before (inches, Visio `SpBefore`).
  void setSpaceBeforeInches(double inches) => _updateText(
        para: (p) => p.copyWith(spaceBeforeInches: inches.clamp(0.0, 1.0)),
      );

  /// Paragraph space after (inches, Visio `SpAfter`).
  void setSpaceAfterInches(double inches) => _updateText(
        para: (p) => p.copyWith(spaceAfterInches: inches.clamp(0.0, 1.0)),
      );

  void setStrikethrough(bool value) => _updateText(
        char: (c) => c.copyWith(strikethrough: value),
      );

  void toggleStrikethrough() =>
      setStrikethrough(!(selectedCharStyle?.strikethrough ?? false));

  /// Visio `CompoundType` (0=single, 1=double, 2=thick-thin, 3=thin-thick).
  void setCompoundType(int type) => _updateSelectedShapes(
        (s) => s.copyWith(
          line: s.line.copyWith(compoundType: type.clamp(0, 3)),
        ),
        rememberStyle: true,
      );

  void setUnderline(bool value) =>
      _updateText(char: (c) => c.copyWith(underline: value));

  void setFontFamily(String family) =>
      _updateText(char: (c) => c.copyWith(fontFamily: family));

  /// Vertical text alignment (applies to the shape's text block).
  void setTextVerticalAlign(VsdxVertAlign align) => _updateSelectedShapes(
        (s) => s.copyWith(
          richText: s.richText.copyWith(
            textBlock: s.richText.textBlock.copyWith(verticalAlign: align),
          ),
        ),
      );

  VsdxVertAlign? get selectedVerticalAlign {
    final page = currentPage;
    if (page == null) return null;
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null) return s.richText.textBlock.verticalAlign;
    }
    return null;
  }

  /// Toggle a drop shadow on the selected shapes.
  void setShadow(bool enabled) => _updateSelectedShapes(
        (s) {
          if (!enabled) {
            return s.copyWith(shadow: VsdxShadow.disabled);
          }
          // Re-enable keeping prior colour / offsets when already configured.
          final prev = s.shadow;
          return s.copyWith(
            shadow: prev.enabled
                ? prev
                : prev.copyWith(enabled: true, transparency: 0.4),
          );
        },
      );

  bool get selectedHasShadow {
    final page = currentPage;
    if (page == null) return false;
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null) return s.shadow.enabled;
    }
    return false;
  }

  /// First selected shape's shadow (may be disabled).
  VsdxShadow? get selectedShadow => _firstSelected?.shadow;

  /// Update shadow colour / offsets / blur / opacity on the selection.
  void updateShadow({
    VsdxColor? color,
    double? offsetXInches,
    double? offsetYInches,
    double? blurInches,
    double? transparency,
    bool transient = false,
  }) {
    _updateSelectedShapes(
      (s) {
        final base = s.shadow.enabled ? s.shadow : const VsdxShadow();
        return s.copyWith(
          shadow: base.copyWith(
            color: color ?? base.color,
            offsetXInches: offsetXInches,
            offsetYInches: offsetYInches,
            blurInches: blurInches,
            transparency: transparency,
            enabled: true,
          ),
        );
      },
      transient: transient,
    );
  }

  /// Toggle an outer glow on the selected shapes.
  void setGlow(bool enabled) => _updateSelectedShapes(
        (s) {
          if (!enabled) {
            return s.copyWith(glow: VsdxGlow.disabled);
          }
          final prev = s.glow;
          return s.copyWith(
            glow: prev.enabled
                ? prev
                : prev.copyWith(enabled: true, transparency: 0.6),
          );
        },
      );

  bool get selectedHasGlow {
    final g = _firstSelected?.glow;
    return g != null && g.enabled;
  }

  VsdxGlow? get selectedGlow => _firstSelected?.glow;

  void updateGlow({
    VsdxColor? color,
    double? sizeInches,
    double? transparency,
    bool transient = false,
  }) {
    _updateSelectedShapes(
      (s) {
        final base = s.glow.enabled ? s.glow : const VsdxGlow();
        return s.copyWith(
          glow: base.copyWith(
            color: color ?? base.color,
            sizeInches: sizeInches,
            transparency: transparency,
            enabled: true,
          ),
        );
      },
      transient: transient,
    );
  }

  /// Toggle a mirror reflection under the selected shapes.
  void setReflection(bool enabled) => _updateSelectedShapes(
        (s) {
          if (!enabled) {
            return s.copyWith(reflection: VsdxReflection.disabled);
          }
          final prev = s.reflection;
          return s.copyWith(
            reflection: prev.enabled
                ? prev
                : prev.copyWith(enabled: true, transparency: 0.6),
          );
        },
      );

  bool get selectedHasReflection {
    final r = _firstSelected?.reflection;
    return r != null && r.enabled;
  }

  VsdxReflection? get selectedReflection => _firstSelected?.reflection;

  void updateReflection({
    double? sizeInches,
    double? distanceInches,
    double? blurInches,
    double? transparency,
    bool transient = false,
  }) {
    _updateSelectedShapes(
      (s) {
        final base =
            s.reflection.enabled ? s.reflection : const VsdxReflection();
        return s.copyWith(
          reflection: base.copyWith(
            sizeInches: sizeInches,
            distanceInches: distanceInches,
            blurInches: blurInches,
            transparency: transparency,
            enabled: true,
          ),
        );
      },
      transient: transient,
    );
  }

  /// Whether the selection has Soft Edges (`SoftEdgesSize` > 0).
  bool get selectedHasSoftEdges =>
      (selectedLine?.softEdgesInches ?? 0) > 0;

  double get selectedSoftEdgesInches =>
      selectedLine?.softEdgesInches ?? 0;

  /// Toggle Soft Edges on the selection (default size 0.05").
  void setSoftEdges(bool enabled) => _updateSelectedShapes(
        (s) {
          final cur = s.line.softEdgesInches;
          return s.copyWith(
            line: s.line.copyWith(
              softEdgesInches: enabled
                  ? (cur > 0 ? cur : 0.05)
                  : 0.0,
            ),
          );
        },
        rememberStyle: true,
      );

  /// Update Soft Edges blur radius (inches).
  void updateSoftEdges(double sizeInches, {bool transient = false}) =>
      _updateSelectedShapes(
        (s) => s.copyWith(
          line: s.line.copyWith(
            softEdgesInches: sizeInches.clamp(0.0, 0.25),
          ),
        ),
        transient: transient,
        rememberStyle: true,
      );

  /// Rotate a single shape about its pin (radians, Visio CCW convention).
  void rotateShape(int id, double angleRad, {bool transient = false}) {
    final movedIds = _subtreeIds(<int>{id});
    updateCurrentPage(
      (page) => page
          .updateShapeById(id, (s) => s.copyWith(angleRad: angleRad))
          .rerouteConnectors(movedShapeIds: movedIds),
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
    final movedIds = _subtreeIds(<int>{id});
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
          .rerouteConnectors(movedShapeIds: movedIds),
      transient: transient,
    );
  }

  /// Every id in the subtrees rooted at [rootIds] — a moved/edited shape plus
  /// any descendants. Connectors glue to leaf shapes, so scoping
  /// [VsdxPage.rerouteConnectors] to a transform must cover the whole subtree
  /// of what actually changed.
  Set<int> _subtreeIds(Iterable<int> rootIds) {
    final page = currentPage;
    final out = <int>{};
    if (page == null) {
      out.addAll(rootIds);
      return out;
    }
    void walk(VsdxShape s) {
      out.add(s.id);
      for (final c in s.children) {
        walk(c);
      }
    }

    for (final r in rootIds) {
      final s = page.findShapeById(r);
      if (s != null) {
        walk(s);
      } else {
        out.add(r);
      }
    }
    return out;
  }

  static VsdxShape _translated(VsdxShape s, double dx, double dy) =>
      VsdxPage.translateShape(s, dx, dy);

  static VsdxShape _translatedHonouringDontMoveChildren(
    VsdxShape s,
    double dx,
    double dy,
  ) =>
      VsdxPage.translateShape(s, dx, dy);

  // --- Reveal / find (drawio Ctrl+F, "Zoom to selection") --------------------

  /// Monotonic counter the canvas watches to know a reveal was requested.
  int get revealSerial => _revealSerial;

  /// Target of the pending reveal: a shape id, or `null` to reveal the whole
  /// current selection.
  int? get revealShapeId => _revealShapeId;

  /// A page-inch point to centre on for the pending reveal (Outline
  /// navigation), or `null` when the reveal targets a shape / the selection.
  Offset2D? get revealPoint => _revealPoint;

  /// Ask the canvas to scroll/centre so shape [id] is in view.
  void revealShape(int id) {
    _revealShapeId = id;
    _revealPoint = null;
    _revealSerial++;
    notifyListeners();
  }

  /// Ask the canvas to zoom to the current selection.
  void revealSelection() {
    if (_selection.isEmpty) return;
    _revealShapeId = null;
    _revealPoint = null;
    _revealSerial++;
    notifyListeners();
  }

  /// Ask the canvas to centre on an arbitrary page-inch point ([xInches],
  /// [yInches]) — used by the Outline minimap to navigate without changing the
  /// selection.
  void revealPagePoint(double xInches, double yInches) {
    _revealShapeId = null;
    _revealPoint = Offset2D(xInches, yInches);
    _revealSerial++;
    notifyListeners();
  }

  // --- Fit to window (drawio "Fit Page") -------------------------------------

  /// Monotonic counter the canvas watches to know a fit-to-window was
  /// requested (from the toolbar / zoom controls), so the whole page is scaled
  /// to fit and re-centred in the viewport.
  int get fitSerial => _fitSerial;
  int _fitSerial = 0;

  /// Ask the canvas to zoom so the whole page fits, centred in the viewport.
  void requestFitToWindow() {
    _fitSerial++;
    notifyListeners();
  }

  String get findQuery => _findQuery;
  bool get findMatchCase => _findMatchCase;
  bool get findWholeWord => _findWholeWord;
  int get findMatchCount => _findMatches.length;

  /// 1-based index of the current match (0 when there are none).
  int get findCurrentOrdinal => _findIndex < 0 ? 0 : _findIndex + 1;

  /// Page index of the current match, or `null` when there are none.
  int? get findCurrentPageIndex =>
      _findIndex < 0 || _findIndex >= _findMatches.length
          ? null
          : _findMatches[_findIndex].pageIndex;

  /// Recompute matches for [query] across every page (text or name) and jump
  /// to the first hit.
  void updateFind(String query) {
    _findQuery = query;
    _recomputeFindMatches();
    if (_findIndex >= 0) {
      _selectAndRevealFind(_findMatches[_findIndex]);
    } else {
      notifyListeners();
    }
  }

  /// Toggle case-sensitive matching (draw.io "Match Case").
  void setFindMatchCase(bool value) {
    if (_findMatchCase == value) return;
    final prefer = _findIndex >= 0 && _findIndex < _findMatches.length
        ? _findMatches[_findIndex]
        : null;
    _findMatchCase = value;
    _recomputeFindMatches(prefer: prefer);
    if (_findIndex >= 0) {
      _selectAndRevealFind(_findMatches[_findIndex]);
    } else {
      notifyListeners();
    }
  }

  /// Toggle whole-word matching (draw.io "Whole Word").
  void setFindWholeWord(bool value) {
    if (_findWholeWord == value) return;
    final prefer = _findIndex >= 0 && _findIndex < _findMatches.length
        ? _findMatches[_findIndex]
        : null;
    _findWholeWord = value;
    _recomputeFindMatches(prefer: prefer);
    if (_findIndex >= 0) {
      _selectAndRevealFind(_findMatches[_findIndex]);
    } else {
      notifyListeners();
    }
  }

  void _recomputeFindMatches({({int pageIndex, int shapeId})? prefer}) {
    final doc = _document;
    final q = _findQuery.trim();
    if (doc == null || q.isEmpty) {
      _findMatches = const <({int pageIndex, int shapeId})>[];
      _findIndex = -1;
      return;
    }
    final needle = _findMatchCase ? q : q.toLowerCase();
    final matches = <({int pageIndex, int shapeId})>[];
    for (var pi = 0; pi < doc.pages.length; pi++) {
      void walk(VsdxShape s) {
        final text = _shapeLabel(s);
        final hayText = _findMatchCase ? text : text.toLowerCase();
        final hayName = _findMatchCase ? s.name : s.name.toLowerCase();
        if (_haystackMatches(hayText, needle) ||
            _haystackMatches(hayName, needle)) {
          matches.add((pageIndex: pi, shapeId: s.id));
        }
        for (final c in s.children) {
          walk(c);
        }
      }

      for (final s in doc.pages[pi].shapes) {
        walk(s);
      }
    }
    _findMatches = matches;
    if (matches.isEmpty) {
      _findIndex = -1;
      return;
    }
    if (prefer != null) {
      final i = matches.indexWhere(
        (m) => m.pageIndex == prefer.pageIndex && m.shapeId == prefer.shapeId,
      );
      _findIndex = i >= 0 ? i : 0;
    } else {
      _findIndex = 0;
    }
  }

  /// Whether [hay] contains [needle], honouring [findWholeWord].
  bool _haystackMatches(String hay, String needle) {
    if (!_findWholeWord) return hay.contains(needle);
    return _containsWholeWord(hay, needle);
  }

  static bool _containsWholeWord(String hay, String needle) {
    if (needle.isEmpty) return false;
    var i = 0;
    while (i <= hay.length - needle.length) {
      final at = hay.indexOf(needle, i);
      if (at < 0) return false;
      final beforeOk = at == 0 || !_isWordChar(hay.codeUnitAt(at - 1));
      final after = at + needle.length;
      final afterOk =
          after >= hay.length || !_isWordChar(hay.codeUnitAt(after));
      if (beforeOk && afterOk) return true;
      i = at + 1;
    }
    return false;
  }

  static bool _isWordChar(int unit) {
    final c = String.fromCharCode(unit);
    return RegExp(r'[A-Za-z0-9_\u4e00-\u9fff]').hasMatch(c);
  }

  /// Advance to the next match (wrapping), selecting and revealing it.
  void findNext() {
    if (_findMatches.isEmpty) return;
    _findIndex = (_findIndex + 1) % _findMatches.length;
    _selectAndRevealFind(_findMatches[_findIndex]);
  }

  /// Go to the previous match (wrapping), selecting and revealing it.
  void findPrevious() {
    if (_findMatches.isEmpty) return;
    _findIndex = (_findIndex - 1 + _findMatches.length) % _findMatches.length;
    _selectAndRevealFind(_findMatches[_findIndex]);
  }

  /// Replace the first occurrence of the find query in the current match's
  /// label (draw.io Replace), then advance to the next remaining match.
  /// Name-only hits are skipped (names are not rewritten).
  void replaceFind(String replacement) {
    if (_findMatches.isEmpty || _findIndex < 0) return;
    final q = _findQuery.trim();
    if (q.isEmpty) return;
    final hit = _findMatches[_findIndex];
    // Ensure we're on the hit's page before editing.
    if (_currentPageIndex != hit.pageIndex) {
      _leaveConnectionPointEdit();
      _currentPageIndex = hit.pageIndex;
      _selection.clear();
    }
    final page = currentPage;
    final shape = page?.findShapeById(hit.shapeId);
    if (shape == null) return;
    final text = _shapeLabel(shape);
    final next = replaceFirstMatch(
      text,
      q,
      replacement,
      matchCase: _findMatchCase,
      wholeWord: _findWholeWord,
    );
    if (next == text) {
      // Name-only match — skip without editing.
      findNext();
      return;
    }
    setShapeText(hit.shapeId, next);
    _recomputeFindMatches();
    if (_findMatches.isEmpty) {
      notifyListeners();
      return;
    }
    // Prefer the next match after the one we just edited.
    final after = _findMatches.indexWhere(
      (m) => m.pageIndex == hit.pageIndex && m.shapeId == hit.shapeId,
    );
    if (after >= 0 && after + 1 < _findMatches.length) {
      _findIndex = after + 1;
    } else if (after >= 0) {
      _findIndex = after; // still matches (partial replace)
    } else {
      _findIndex = 0;
    }
    _selectAndRevealFind(_findMatches[_findIndex]);
  }

  /// Replace every occurrence of the find query in labels across **all pages**
  /// (one undo step). Shape names are left alone.
  void replaceAllFind(String replacement) {
    final doc = _document;
    final q = _findQuery.trim();
    if (doc == null || q.isEmpty) return;
    var nextDoc = doc;
    var changed = false;
    for (var pi = 0; pi < nextDoc.pages.length; pi++) {
      final page = nextDoc.pages[pi];
      var pageChanged = false;
      VsdxShape transform(VsdxShape s) {
        final text = _shapeLabel(s);
        final nextText = replaceAllMatch(
          text,
          q,
          replacement,
          matchCase: _findMatchCase,
          wholeWord: _findWholeWord,
        );
        var next = s;
        if (nextText != text) {
          next = _withLabelText(s, nextText);
          pageChanged = true;
        }
        if (next.children.isNotEmpty) {
          next = next.copyWith(
            children: <VsdxShape>[
              for (final c in next.children) transform(c),
            ],
          );
        }
        return next;
      }

      final shapes = <VsdxShape>[
        for (final s in page.shapes) transform(s),
      ];
      if (pageChanged) {
        nextDoc = nextDoc.replacePage(pi, page.copyWith(shapes: shapes));
        changed = true;
      }
    }
    if (!changed) return;
    applyEdit(nextDoc);
    _recomputeFindMatches();
    if (_findIndex >= 0) {
      _selectAndRevealFind(_findMatches[_findIndex]);
    } else {
      notifyListeners();
    }
  }

  void clearFind() {
    _clearFindState();
    notifyListeners();
  }

  /// Select [hit]'s shape, switching pages without clearing the find session.
  void _selectAndRevealFind(({int pageIndex, int shapeId}) hit) {
    if (_currentPageIndex != hit.pageIndex) {
      _leaveConnectionPointEdit();
      _currentPageIndex = hit.pageIndex;
    }
    _selection
      ..clear()
      ..add(hit.shapeId);
    revealShape(hit.shapeId); // notifies
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

  /// Bumped whenever a *fresh* document is loaded (open / new / close), but
  /// never on edits. The canvas watches it to drop its per-document image
  /// decode cache so a reused part name from a different file can't render a
  /// stale picture.
  int get documentEpoch => _docEpoch;
  int _docEpoch = 0;

  void _resetHistory() {
    _selection.clear();
    _undo.clear();
    _redo.clear();
    _txnBase = null;
    _dirty = false;
    _clearFindState();
    _memoFill = null;
    _memoLine = null;
    _imageSeq = 0;
    _docEpoch++;
  }

  void _clearFindState() {
    _findQuery = '';
    _findMatchCase = false;
    _findWholeWord = false;
    _findMatches = const <({int pageIndex, int shapeId})>[];
    _findIndex = -1;
  }

  static String? _basename(String? path) {
    if (path == null) return null;
    final i = path.lastIndexOf(RegExp(r'[/\\]'));
    return i < 0 ? path : path.substring(i + 1);
  }
}
