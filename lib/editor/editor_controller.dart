import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:vsdx/vsdx.dart';

import '../render/shape_bounds.dart';
import 'shape_clipboard.dart';
import 'snap_guides.dart';
import 'third_party_icons.dart';

/// Editing tools the canvas can be in.
enum EditorTool {
  select,
  /// Pan / pinch-zoom the canvas without selecting or editing shapes.
  /// Intended for touch: drag moves the view; pinch changes zoom.
  pan,
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

/// Common draw.io label positions around a 2-D shape.
enum TextLabelPosition { left, top, center, bottom, right }

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
  bool _showGuides = true;
  bool _showLineJumps = true;
  bool _colorByLayer = false;
  double _lineJumpRadiusInches = 0.07;
  final double _gridInches = 0.25;
  final Set<int> _selection = <int>{};
  final List<_HistoryEntry> _undo = <_HistoryEntry>[];
  final List<_HistoryEntry> _redo = <_HistoryEntry>[];
  VsdxDocument? _txnBase;
  int? _txnPageIndex;
  Set<int>? _txnSelection;
  bool _dirty = false;
  /// Document snapshot considered "saved / pristine". Undo/redo that lands
  /// back on this instance clears the dirty flag.
  VsdxDocument? _cleanDocument;

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

  /// Last non-zero SoftEdgesSize so toggle off→on restores the user's radius.
  double _memoSoftEdgesInches = 0.05;

  // Monotonic counter for minting fresh `/visio/media/imageN.ext` part names on
  // image insert. Lives outside the document snapshot so it keeps climbing
  // across undo/redo — that way a re-inserted image never reuses a part name
  // (and so never collides with a stale entry in the render image cache).
  int _imageSeq = 0;

  bool _importedFromVsd = false;

  VsdxDocument? get document => _document;
  Uint8List? get originalBytes => _originalBytes;
  String? get filePath => _filePath;
  String? get fileName => _fileName;
  bool get isLoading => _isLoading;
  Object? get error => _error;
  bool get hasDocument => _document != null;
  bool get isDirty => _dirty;

  /// `true` when the active document was imported from a legacy `.vsd`.
  /// Cleared after the first successful Save As `.vsdx`.
  bool get importedFromVsd => _importedFromVsd;

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
    // A page switch cannot continue a canvas gesture on the old page. Revert
    // the transient frame so [_txnBase] never leaks into the new page.
    if (_txnBase != null) cancelTransaction();
    _leaveConnectionPointEdit();
    _leaveTextEditSession();
    _currentPageIndex = index;
    _selection.clear();
    // Keep Find matches across page-tab switches so Replace / Find Next still
    // work after the user briefly inspects another sheet (draw.io behaviour).
    // Page reorder ([movePage]) still clears find — those indices go stale.
    notifyListeners();
  }

  /// Rename the page at [index] (persists as `<Page NameU>` via the writer).
  void renamePageAt(int index, String name) {
    final doc = _document;
    if (doc == null || index < 0 || index >= doc.pages.length) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == doc.pages[index].name) return;
    // Disambiguate against other pages (same helper as add/duplicate).
    final taken = <String>{
      for (var i = 0; i < doc.pages.length; i++)
        if (i != index) doc.pages[i].name,
    };
    final unique = taken.contains(trimmed)
        ? _uniquePageName(doc, trimmed)
        : trimmed;
    if (unique == doc.pages[index].name) return;
    applyEdit(doc.replacePage(index, doc.pages[index].copyWith(name: unique)));
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
    final undoPage = _currentPageIndex;
    final undoSel = Set<int>.of(_selection);
    _leaveTextEditSession();
    _selection.clear();
    _currentPageIndex = at;
    // Snapshot the pre-add page index + selection so undo restores both.
    applyEdit(
      doc.insertPage(at, page),
      undoPageIndex: undoPage,
      undoSelection: undoSel,
    );
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
    final undoPage = _currentPageIndex;
    final undoSel = Set<int>.of(_selection);
    _leaveTextEditSession();
    _selection.clear();
    _currentPageIndex = at;
    applyEdit(
      doc.insertPage(at, copy),
      undoPageIndex: undoPage,
      undoSelection: undoSel,
    );
  }

  /// Delete the current page (keeps at least one page).
  void deleteCurrentPage() {
    final doc = _document;
    if (doc == null || doc.pages.length <= 1) return;
    final i = _currentPageIndex;
    final pageId = doc.pages[i].id;
    final undoSel = Set<int>.of(_selection);
    _leaveTextEditSession();
    _selection.clear();
    // Session guides are keyed by page id; drop them so a later page that
    // reuses this id does not inherit ghost ruler guides.
    _pageGuides.remove(pageId);
    var next = doc.removePageAt(i);
    // Drop dangling BackPage refs so export does not write a missing id.
    for (var pi = 0; pi < next.pages.length; pi++) {
      final p = next.pages[pi];
      if (p.backgroundPageId == pageId) {
        next = next.replacePage(pi, p.copyWith(backgroundPageId: null));
      }
    }
    _currentPageIndex = i.clamp(0, next.pages.length - 1);
    applyEdit(next, undoPageIndex: i, undoSelection: undoSel);
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
    final undoPage = _currentPageIndex;
    final undoSel = Set<int>.of(_selection);
    final next = doc.movePage(from, to);
    if (identical(next, doc)) return;
    final newIdx = next.pages.indexWhere((p) => p.id == currentId);
    _currentPageIndex = newIdx >= 0 ? newIdx : 0;
    // Same sheet content — keep the selection (only the tab order changed).
    _clearFindState();
    applyEdit(next, undoPageIndex: undoPage, undoSelection: undoSel);
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

  /// Clear the page `PageColor` so reopen inherits the default white fill.
  void clearBackgroundColor() {
    updateCurrentPage((page) {
      if (page.backgroundColor == null) return page;
      return page.withoutBackgroundColor();
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
  bool get showGuides => _showGuides;
  bool get showLineJumps => _showLineJumps;
  bool get colorByLayer => _colorByLayer;
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

  /// Toggle dynamic edge/centre/spacing/page-centre guides (draw.io Guides).
  void toggleGuides() {
    _showGuides = !_showGuides;
    notifyListeners();
  }

  /// Toggle drawio-style line jumps (arc connectors over the ones they cross).
  void toggleLineJumps() {
    _showLineJumps = !_showLineJumps;
    notifyListeners();
  }

  /// Toggle Visio Color-by-Layer view (session-only; not written to `.vsdx`).
  void toggleColorByLayer() {
    _colorByLayer = !_colorByLayer;
    notifyListeners();
  }

  void setColorByLayer(bool enabled) {
    if (_colorByLayer == enabled) return;
    _colorByLayer = enabled;
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
  void addPageGuide({
    required bool vertical,
    required double pos,
    bool snapToGrid = true,
  }) {
    final id = currentPage?.id;
    if (id == null) return;
    final g = PageGuide(
      vertical: vertical,
      pos: snapToGrid ? snap(pos) : pos,
    );
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
  void movePageGuide(int index, double pos, {bool snapToGrid = true}) {
    final id = currentPage?.id;
    final list = id == null ? null : _pageGuides[id];
    if (id == null || list == null || index < 0 || index >= list.length) {
      return;
    }
    final next = List<PageGuide>.of(list);
    next[index] =
        next[index].copyWith(pos: snapToGrid ? snap(pos) : pos);
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
    // Match hit-test / paint: hidden-layer shapes are not selectable via Cmd+A.
    setSelection(<int>[
      for (final s in page.shapes)
        if (page.isShapeVisible(s)) s.id,
    ]);
  }

  /// Select every glueable connector on the page, including nested ones
  /// (draw.io "Select Edges", Cmd+E). Freehand ink is skipped.
  void selectConnectors() {
    final page = currentPage;
    if (page == null) return;
    final ids = <int>[];
    void walk(VsdxShape s) {
      if (!page.isShapeVisible(s)) return;
      if (s.isGlueableConnector) ids.add(s.id);
      if (s.collapsed) return;
      for (final c in s.children) {
        walk(c);
      }
    }

    for (final s in page.shapes) {
      walk(s);
    }
    setSelection(ids);
  }

  /// Select every non-connector shape on the page, including nested ones and
  /// freehand ink (draw.io "Select Vertices", Cmd+Shift+I).
  void selectVertices() {
    final page = currentPage;
    if (page == null) return;
    final ids = <int>[];
    void walk(VsdxShape s) {
      if (!page.isShapeVisible(s)) return;
      if (!s.isGlueableConnector) ids.add(s.id);
      if (s.collapsed) return;
      for (final c in s.children) {
        walk(c);
      }
    }

    for (final s in page.shapes) {
      walk(s);
    }
    setSelection(ids);
  }

  /// Cycle through every visible shape in paint order (draw.io Tab/Shift+Tab).
  ///
  /// Expanded containers are followed by their children; collapsed subtrees
  /// and hidden layers are skipped.
  void selectNextShape({bool reverse = false}) {
    final page = currentPage;
    if (page == null || page.shapes.isEmpty) return;
    final ids = <int>[];
    void walk(VsdxShape s) {
      if (!page.isShapeVisible(s)) return;
      ids.add(s.id);
      if (s.collapsed) return;
      for (final child in s.children) {
        walk(child);
      }
    }

    for (final shape in page.shapes) {
      walk(shape);
    }
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

  /// Select the immediate parent/container of the single selection
  /// (draw.io Alt+Tab). Repeating the command walks toward the page root.
  void selectParentShape() {
    final page = currentPage;
    final id = singleSelectedId;
    if (page == null || id == null) return;
    final parent = page.findParentId(id);
    if (parent != null) selectOnly(parent);
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
    // Drop now-hidden shapes from the selection so delete/move/style cannot
    // silently edit invisible geometry. Also refresh Find so Replace cannot
    // target a stale hit on a just-hidden layer.
    final page = currentPage;
    if (page == null) return;
    final before = _selection.length;
    if (_selection.isNotEmpty) {
      _selection.removeWhere((id) => !page.isShapeTreeVisible(id));
    }
    if (_findQuery.trim().isNotEmpty) {
      _recomputeFindMatches();
    }
    if (_selection.length != before || _findQuery.trim().isNotEmpty) {
      notifyListeners();
    }
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
        // updateShapeById walks the tree, so nested selections are covered.
        // Skip locked / locked-layer shapes (same as assignSelectionToLayer).
        for (final shapeId in _selection) {
          final s = next.findShapeById(shapeId);
          if (s == null || s.locked || isOnLockedLayer(shapeId)) continue;
          next = next.updateShapeById(
            shapeId,
            (sh) => sh.copyWith(layerMemberIds: <int>[id]),
          );
        }
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
      VsdxShape strip(VsdxShape s) {
        var out = s.layerMemberIds.contains(layerId)
            ? s.copyWith(
                layerMemberIds: <int>[
                  for (final id in s.layerMemberIds)
                    if (id != layerId) id,
                ],
              )
            : s;
        if (out.children.isNotEmpty) {
          out = out.copyWith(
            children: <VsdxShape>[for (final c in out.children) strip(c)],
          );
        }
        return out;
      }

      return p.copyWith(
        layers: layers,
        shapes: <VsdxShape>[for (final s in p.shapes) strip(s)],
      );
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

  /// True when [shapeId] or an ancestor sits on a locked layer.
  bool isOnLockedLayer(int shapeId) {
    final page = currentPage;
    if (page == null) return false;
    return page.isShapeTreeOnLockedLayer(shapeId);
  }

  static bool _shapeOnLockedLayer(VsdxPage page, VsdxShape s) =>
      page.isShapeTreeOnLockedLayer(s.id);

  // --- Undo / redo -----------------------------------------------------------

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Apply a discrete edit that becomes a single undo step.
  ///
  /// [undoPageIndex] is the page index to restore with the pre-edit document
  /// (needed when the caller updates [_currentPageIndex] for the *new* doc
  /// before/after calling this — e.g. [addPage] / [deleteCurrentPage]).
  /// [undoSelection] is the selection to restore with that snapshot (needed
  /// when the caller clears/replaces [_selection] before calling this).
  void applyEdit(
    VsdxDocument next, {
    int? undoPageIndex,
    Set<int>? undoSelection,
  }) {
    final cur = _document;
    if (cur == null || identical(cur, next)) return;
    if (_txnBase != null) {
      // A shortcut/property edit can arrive while a pointer gesture is still
      // active. Keep it inside that transaction so subsequent transient
      // updates and the discrete edit form one coherent undo step.
      _redo.clear();
      _document = next;
      _pruneSelection();
      _dirty = !identical(next, _cleanDocument);
      notifyListeners();
      return;
    }
    _undo.add(_HistoryEntry(
      cur,
      undoPageIndex ?? _currentPageIndex,
      undoSelection ?? Set<int>.of(_selection),
    ));
    _redo.clear();
    _document = next;
    // Drop ids removed with a parent / cut root so selection never ghosts.
    _pruneSelection();
    _dirty = !identical(next, _cleanDocument);
    notifyListeners();
  }

  /// Snapshot the document at the start of a continuous gesture (e.g. a drag).
  void beginTransaction() {
    if (_txnBase == null) {
      _txnBase = _document;
      _txnPageIndex = _currentPageIndex;
      _txnSelection = Set<int>.of(_selection);
    }
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
    final basePage = _txnPageIndex ?? _currentPageIndex;
    final baseSel = _txnSelection ?? Set<int>.of(_selection);
    _txnBase = null;
    _txnPageIndex = null;
    _txnSelection = null;
    if (base != null && !identical(base, _document)) {
      _undo.add(_HistoryEntry(base, basePage, baseSel));
      _redo.clear();
      _dirty = !identical(_document, _cleanDocument);
    }
    notifyListeners();
  }

  /// Abort the current gesture, reverting the live document to the snapshot
  /// taken at [beginTransaction] (no history entry). Used by Escape-to-cancel.
  void cancelTransaction() {
    final base = _txnBase;
    final basePage = _txnPageIndex;
    final baseSel = _txnSelection;
    _txnBase = null;
    _txnPageIndex = null;
    _txnSelection = null;
    if (base == null) return;
    var changed = false;
    if (!identical(base, _document)) {
      _document = base;
      changed = true;
    }
    if (basePage != null && basePage != _currentPageIndex) {
      _currentPageIndex = basePage;
      changed = true;
    }
    if (baseSel != null &&
        (baseSel.length != _selection.length ||
            !baseSel.containsAll(_selection))) {
      _selection
        ..clear()
        ..addAll(baseSel);
      changed = true;
    }
    if (changed) {
      _clampPageIndex();
      _pruneSelection();
      notifyListeners();
    }
  }

  void undo() {
    if (_txnBase != null) {
      cancelTransaction();
      return;
    }
    if (_undo.isEmpty || _document == null) return;
    _leaveConnectionPointEdit();
    _leaveTextEditSession();
    _redo.add(_HistoryEntry(
      _document!,
      _currentPageIndex,
      Set<int>.of(_selection),
    ));
    final prev = _undo.removeLast();
    _document = prev.document;
    _currentPageIndex = prev.pageIndex;
    _selection
      ..clear()
      ..addAll(prev.selection);
    _dirty = !identical(_document, _cleanDocument);
    _clampPageIndex();
    _pruneSelection();
    notifyListeners();
  }

  void redo() {
    if (_txnBase != null) {
      cancelTransaction();
      return;
    }
    if (_redo.isEmpty || _document == null) return;
    _leaveConnectionPointEdit();
    _leaveTextEditSession();
    _undo.add(_HistoryEntry(
      _document!,
      _currentPageIndex,
      Set<int>.of(_selection),
    ));
    final next = _redo.removeLast();
    _document = next.document;
    _currentPageIndex = next.pageIndex;
    _selection
      ..clear()
      ..addAll(next.selection);
    _dirty = !identical(_document, _cleanDocument);
    _clampPageIndex();
    _pruneSelection();
    notifyListeners();
  }

  // --- Editing helpers -------------------------------------------------------

  /// Replace the current page via [update]. When [transient] the change does
  /// not create its own history entry (used mid-drag between
  /// [beginTransaction] and [commitTransaction]).
  ///
  /// [undoPageIndex] overrides the page index stored with the undo snapshot
  /// (e.g. Find/Replace jumped to another page before editing).
  void updateCurrentPage(
    VsdxPage Function(VsdxPage page) update, {
    bool transient = false,
    int? undoPageIndex,
    Set<int>? undoSelection,
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
      applyEdit(
        next,
        undoPageIndex: undoPageIndex,
        undoSelection: undoSelection,
      );
    }
  }

  /// Translate every selected shape by [dxInches] / [dyInches] (page space).
  ///
  /// When a moved shape has [VsdxShape.dontMoveChildren], its children are
  /// compensated so their on-page positions stay fixed (Visio semantics).
  /// Only selection roots move (a group + child multi-select does not double
  /// apply the delta to the child).
  void moveSelectionBy(
    double dxInches,
    double dyInches, {
    bool transient = false,
  }) {
    if (_selection.isEmpty || (dxInches == 0 && dyInches == 0)) return;
    final page0 = currentPage;
    if (page0 == null) return;
    final roots = _selectionRoots(page0, <int>[
      for (final id in _selection)
        if (page0.findShapeById(id) case final s?
            when !s.locked && !isOnLockedLayer(id))
          id,
    ]);
    if (roots.isEmpty) return;
    final movedIds = _subtreeIds(roots);
    updateCurrentPage(
      (page) {
        var next = page;
        var moved = false;
        for (final id in roots) {
          final after = _nudgeShapeOnPage(next, id, dxInches, dyInches);
          if (!identical(after, next)) {
            next = after;
            moved = true;
          }
        }
        return moved
            ? next
                .recalculateFormulas(changedShapeIds: movedIds)
                .rerouteConnectors(movedShapeIds: movedIds)
            : page;
      },
      transient: transient,
    );
  }

  /// Detach glue from connectors in the moving selection to shapes that are
  /// not moving with them.
  ///
  /// draw.io applies this when Alt+Shift-dragging a remote selection: a
  /// connector moved on its own becomes floating, while glue to any target
  /// included in the same moving selection is preserved.
  void detachSelectionConnectorsFromStationaryShapes({
    bool transient = false,
  }) {
    final page = currentPage;
    if (page == null || _selection.isEmpty || page.connects.isEmpty) return;
    final movingIds = _subtreeIds(_selection);
    final movingConnectors = <int>{
      for (final id in movingIds)
        if (page.findShapeById(id) case final shape?
            when shape.isGlueableConnector &&
                !shape.locked &&
                !isOnLockedLayer(id))
          id,
    };
    if (movingConnectors.isEmpty) return;
    updateCurrentPage(
      (current) {
        final connects = <VsdxConnect>[
          for (final connect in current.connects)
            if (!movingConnectors.contains(connect.fromSheetId) ||
                movingIds.contains(connect.toSheetId))
              connect,
        ];
        return connects.length == current.connects.length
            ? current
            : current.copyWith(connects: connects);
      },
      transient: transient,
    );
  }

  /// Move arbitrary shape roots by individual page-space deltas.
  ///
  /// Used by draw.io's area-displacement gesture, where shapes on one side of
  /// the vertical cut may move horizontally while shapes on one side of the
  /// horizontal cut move vertically. All deltas are committed as one edit (or
  /// folded into the active drag transaction when [transient]).
  void moveShapesBy(
    Map<int, Offset2D> deltas, {
    bool transient = false,
  }) {
    if (deltas.isEmpty) return;
    final page0 = currentPage;
    if (page0 == null) return;
    final movable = <int, Offset2D>{};
    for (final entry in deltas.entries) {
      if (entry.value.x == 0 && entry.value.y == 0) continue;
      final shape = page0.findShapeById(entry.key);
      if (shape == null || shape.locked || isOnLockedLayer(entry.key)) {
        continue;
      }
      movable[entry.key] = entry.value;
    }
    if (movable.isEmpty) return;
    final movedIds = _subtreeIds(movable.keys);
    updateCurrentPage(
      (page) {
        var next = page;
        var moved = false;
        for (final entry in movable.entries) {
          final after = _nudgeShapeOnPage(
            next,
            entry.key,
            entry.value.x,
            entry.value.y,
          );
          if (!identical(after, next)) {
            next = after;
            moved = true;
          }
        }
        return moved
            ? next
                .recalculateFormulas(changedShapeIds: movedIds)
                .rerouteConnectors(movedShapeIds: movedIds)
            : page;
      },
      transient: transient,
    );
  }

  /// Nudge shape [id] by a page-space delta, converting into parent-local pins
  /// when nested (so rotated ancestors do not shear the move).
  static VsdxPage _nudgeShapeOnPage(
    VsdxPage page,
    int id,
    double dx,
    double dy,
  ) {
    final s = page.findShapeById(id);
    if (s == null || (dx == 0 && dy == 0)) return page;
    final parentId = page.findParentId(id);
    if (parentId == null) {
      return page.updateShapeById(
        id,
        (sh) => VsdxPage.translateShape(sh, dx, dy),
      );
    }
    final pin = page.shapePinPage(id);
    final local = page.pageToLocalDeep(
      parentId,
      Offset2D(pin.x + dx, pin.y + dy),
    );
    return page.updateShapeById(
      id,
      (sh) => VsdxPage.translateShape(sh, local.x - sh.pinX, local.y - sh.pinY),
    );
  }

  void _reparentShapesInto(
    Iterable<int> shapeIds,
    int? containerId,
  ) {
    final movable = List<int>.of(shapeIds);
    if (movable.isEmpty) return;
    final movedIds = <int>{
      ..._subtreeIds(movable),
      if (containerId != null) ..._subtreeIds(<int>{containerId}),
    };
    updateCurrentPage((page) {
      var next = page;
      for (final id in movable) {
        next = next.reparentShape(id, containerId);
      }
      return next
          .recalculateFormulas(changedShapeIds: movedIds)
          .rerouteConnectors(movedShapeIds: movedIds);
    });
  }

  /// Reparent each selected shape into [containerId] (or out to the top level
  /// when [containerId] is `null`). Used by canvas drop-into-container.
  void reparentSelectionInto(int? containerId) {
    if (_selection.isEmpty) return;
    final page0 = currentPage;
    if (page0 == null) return;
    if (containerId != null && !_containerAcceptsDrop(page0, containerId)) {
      return;
    }
    // Roots only — co-selecting group+child must not eject the child.
    final movable = _selectionRoots(page0, <int>[
      for (final id in _selection)
        if (containerId == null || id != containerId)
          if (page0.findShapeById(id) case final s?
              when !s.locked && !isOnLockedLayer(id))
            id,
    ]);
    _reparentShapesInto(movable, containerId);
  }

  /// Toggle draw.io-style fold on a foldable container / swimlane. Children
  /// stay in the model; paint and hit-testing hide them while collapsed. The
  /// container height shrinks to the header band (top edge fixed) and restores
  /// on unfold. Plain Visio/Edraw groups are not foldable.
  ///
  /// Glue aimed at children is detached while folded (so connectors don't pin
  /// to invisible targets) and stashed on the host via
  /// [VsdxShape.userCollapsedGlue] so unfold — and undo — restore it.
  void toggleCollapsed(int id) {
    final page0 = currentPage;
    final host = page0?.findShapeById(id);
    if (host == null ||
        !host.shapeKind.isFoldable ||
        host.locked ||
        isOnLockedLayer(id)) {
      return;
    }
    updateCurrentPage((page) => page.setCollapsed(id, !host.collapsed));
    final page = currentPage;
    final s = page?.findShapeById(id);
    if (page == null || s == null || !s.collapsed) return;
    final hidden = _subtreeIds(<int>{id})..remove(id);
    if (_selection.any(hidden.contains)) {
      _selection.removeWhere(hidden.contains);
      notifyListeners();
    }
  }

  bool _canSetSelectedHostCollapsed(VsdxPage page, int id, bool value) {
    final host = page.findShapeById(id);
    return host != null &&
        host.shapeKind.isFoldable &&
        host.collapsed != value &&
        !host.locked &&
        !isOnLockedLayer(id);
  }

  bool get canCollapseSelection {
    final page = currentPage;
    if (page == null) return false;
    return _selection.any(
      (id) => _canSetSelectedHostCollapsed(page, id, true),
    );
  }

  bool get canExpandSelection {
    final page = currentPage;
    if (page == null) return false;
    return _selection.any(
      (id) => _canSetSelectedHostCollapsed(page, id, false),
    );
  }

  /// draw.io Ctrl/Cmd+Home / Ctrl/Cmd+End: fold or unfold every eligible
  /// selected container as one undoable edit.
  void setSelectionCollapsed(bool collapsed) {
    final page = currentPage;
    if (page == null || _selection.isEmpty) return;
    final ids = <int>[
      for (final id in _selection)
        if (_canSetSelectedHostCollapsed(page, id, collapsed)) id,
    ];
    if (ids.isEmpty) return;
    beginTransaction();
    for (final id in ids) {
      toggleCollapsed(id);
    }
    commitTransaction();
  }

  void collapseSelection() => setSelectionCollapsed(true);
  void expandSelection() => setSelectionCollapsed(false);

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
    // Match [reparentSelectionInto]: roots only; locked / locked-layer stay.
    final movable = _selectionRoots(page, <int>[
      for (final id in _selection)
        if (page.findShapeById(id) case final s?
            when !s.locked && !isOnLockedLayer(id))
          id,
    ]);
    if (movable.isEmpty) return null;
    final dropId = page.findDropContainerAt(
      pageX,
      pageY,
      excludeIds: Set<int>.of(_selection),
    );
    // Reject locked / hidden hosts without ejecting from the current parent.
    if (dropId != null && !_containerAcceptsDrop(page, dropId)) {
      return null;
    }
    final movedIds = <int>{
      ..._subtreeIds(movable),
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
          final droppingLane = movable.any((id) {
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
          if (targetId != null && !_containerAcceptsDrop(next, targetId)) {
            return p;
          }
        }
        for (final id in movable) {
          final oldParent = next.findParentId(id);
          if (targetId != null) {
            if (oldParent != targetId) {
              next = next.reparentShape(id, targetId);
              changed = true;
            }
          } else if (oldParent != null) {
            // Ancestors are excluded from [findDropContainerAt] so a host is
            // never offered as its own drop target. That looks like "no hit"
            // while the pointer is still inside the current parent — keep the
            // nesting in that case; eject only after leaving the host.
            final stillInside = next.containsShapePagePoint(
                  oldParent,
                  pageX,
                  pageY,
                ) &&
                _containerAcceptsDrop(next, oldParent);
            if (!stillInside) {
              next = next.reparentShape(id, null);
              changed = true;
            }
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
            ? next
                .recalculateFormulas(changedShapeIds: movedIds)
                .rerouteConnectors(movedShapeIds: movedIds)
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
  bool get canAddLane {
    final poolId = selectedPoolId;
    return poolId != null && !_isStructureLocked(poolId);
  }

  /// Whether Remove Lane is available (selected lane inside a multi-lane pool).
  bool get canRemoveLane {
    final page = currentPage;
    final id = singleSelectedId;
    if (page == null || id == null) return false;
    final s = page.findShapeById(id);
    if (s == null || !SwimlaneOps.isLane(s)) return false;
    // Locked lane (or locked layer) cannot be removed even if the pool is free.
    if (s.locked || isOnLockedLayer(id)) return false;
    final poolId = selectedPoolId;
    if (poolId == null || _isStructureLocked(poolId)) return false;
    final pool = page.findShapeById(poolId);
    return pool != null && SwimlaneOps.lanesOf(pool).length > 1;
  }

  /// True when [shapeId] (table / pool host) is locked or on a locked layer.
  bool _isStructureLocked(int shapeId) {
    final page = currentPage;
    final s = page?.findShapeById(shapeId);
    return s == null || s.locked || isOnLockedLayer(shapeId);
  }

  /// Append a lane to the selected pool (or the pool that owns the selected
  /// lane). One undo step; new lane is selected.
  void addLaneToSelectedPool() {
    if (!canAddLane) return;
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
          .recalculateFormulas(changedShapeIds: movedIds)
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
    final doomed = _subtreeIds(<int>{laneId});
    final movedIds = _subtreeIds(<int>{poolId});
    updateCurrentPage((p) {
      final host = p.findShapeById(poolId);
      if (host == null) return p;
      var next = p.updateShapeById(
        poolId,
        (_) => SwimlaneOps.removeLane(host, laneId),
      );
      next = _pruneConnectsReferencing(next, doomed);
      return next
          .recalculateFormulas(changedShapeIds: movedIds)
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

  /// Top-level or separately nested connectors whose glued endpoints all
  /// terminate inside [targetIds]. Both ends must be glued, so free/cross-row
  /// connectors are not accidentally copied with a duplicated table row.
  Set<int> _fullyGluedConnectorsWithin(Set<int> targetIds) {
    final page = currentPage;
    if (page == null || targetIds.isEmpty) return const <int>{};
    final rowsByConnector = <int, List<VsdxConnect>>{};
    for (final connect in page.connects) {
      final shape = page.findShapeById(connect.fromSheetId);
      if (shape == null || !shape.isGlueableConnector) continue;
      rowsByConnector
          .putIfAbsent(connect.fromSheetId, () => <VsdxConnect>[])
          .add(connect);
    }
    return <int>{
      for (final entry in rowsByConnector.entries)
        if (entry.value.any((row) => row.isBegin) &&
            entry.value.any((row) => row.isEnd) &&
            entry.value.every((row) => targetIds.contains(row.toSheetId)))
          entry.key,
    };
  }

  bool get canAddTableRow {
    final tableId = selectedTableId;
    return tableId != null && !_isStructureLocked(tableId);
  }

  bool get canAddTableColumn {
    final tableId = selectedTableId;
    return tableId != null && !_isStructureLocked(tableId);
  }

  int? get _selectedTableRowIndex {
    final cells = _selectedTableCells;
    if (cells.isEmpty) return null;
    final row = TableOps.cellRow(cells.first);
    if (row == null) return null;
    for (final cell in cells.skip(1)) {
      if (TableOps.cellRow(cell) != row) return null;
    }
    return row;
  }

  /// Resolve a safe draw.io-style Delete target for the selected table cells.
  ///
  /// A single cell (or multiple cells in one row) means "delete row". A
  /// column is only selected when every visible cell in that column is in the
  /// selection, avoiding accidental column deletion from a sparse selection.
  ({bool row, int index})? get _selectedTableDeleteBand {
    final page = currentPage;
    final tableId = selectedTableId;
    final cells = _selectedTableCells;
    if (page == null || tableId == null || cells.isEmpty) return null;
    if (_selection.length != cells.length) return null;
    final table = page.findShapeById(tableId);
    if (table == null) return null;
    final dim = TableOps.dimensions(table);
    if (cells.any(
      (cell) =>
          TableOps.cellRow(cell) == null || TableOps.cellCol(cell) == null,
    )) {
      return null;
    }
    final rows = <int>{for (final cell in cells) TableOps.cellRow(cell)!};
    final cols = <int>{for (final cell in cells) TableOps.cellCol(cell)!};
    if (cells.length == 1) {
      final row = rows.single;
      if (dim.rows > 1) return (row: true, index: row);
      final col = cols.single;
      if (dim.cols > 1) return (row: false, index: col);
      return null;
    }
    if (rows.length == 1) return (row: true, index: rows.single);
    if (cols.length != 1) return null;
    final col = cols.single;
    final visibleColumn = <int>{
      for (final cell in TableOps.cellsOf(table))
        if (!TableOps.isCovered(cell) && TableOps.cellCol(cell) == col) cell.id,
    };
    return visibleColumn.length == cells.length &&
            visibleColumn.containsAll(cells.map((cell) => cell.id))
        ? (row: false, index: col)
        : null;
  }

  bool get canDeleteSelectedTableBand {
    final band = _selectedTableDeleteBand;
    if (band == null) return false;
    return band.row ? canRemoveTableRow : canRemoveTableColumn;
  }

  /// Delete the selected row/column instead of removing individual cell
  /// children and leaving an invalid table grid.
  void deleteSelectedTableBand() {
    final band = _selectedTableDeleteBand;
    if (band == null) return;
    if (band.row) {
      if (canRemoveTableRow) removeRowFromSelectedTable();
    } else if (canRemoveTableColumn) {
      removeColumnFromSelectedTable();
    }
  }

  /// draw.io Enter shortcut: a selected cell (or cells from one row) can
  /// duplicate its whole row directly below itself.
  bool get canDuplicateSelectedTableRow {
    final tableId = selectedTableId;
    final row = _selectedTableRowIndex;
    if (tableId == null || row == null || _isStructureLocked(tableId)) {
      return false;
    }
    final page = currentPage;
    final table = page?.findShapeById(tableId);
    if (page == null || table == null) return false;
    return TableOps.cellsOf(table)
        .where((cell) => TableOps.cellRow(cell) == row)
        .every((cell) => !cell.locked && !isOnLockedLayer(cell.id));
  }

  /// draw.io Ctrl/Cmd+Enter shortcut: duplicate a selected table even when
  /// the current selection is one of its cells.
  bool get canDuplicateSelectedTable {
    final tableId = selectedTableId;
    return tableId != null && !_isStructureLocked(tableId);
  }

  bool get canRemoveTableRow {
    final page = currentPage;
    final tableId = selectedTableId;
    if (page == null || tableId == null || _isStructureLocked(tableId)) {
      return false;
    }
    final table = page.findShapeById(tableId);
    if (table == null) return false;
    return TableOps.dimensions(table).rows > 1;
  }

  bool get canRemoveTableColumn {
    final page = currentPage;
    final tableId = selectedTableId;
    if (page == null || tableId == null || _isStructureLocked(tableId)) {
      return false;
    }
    final table = page.findShapeById(tableId);
    if (table == null) return false;
    return TableOps.dimensions(table).cols > 1;
  }

  void addRowToSelectedTable() {
    if (!canAddTableRow) return;
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
          .recalculateFormulas(changedShapeIds: movedIds)
          .rerouteConnectors(movedShapeIds: movedIds);
    });
    _selection
      ..clear()
      ..add(tableId);
    notifyListeners();
  }

  void addColumnToSelectedTable() {
    if (!canAddTableColumn) return;
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
          .recalculateFormulas(changedShapeIds: movedIds)
          .rerouteConnectors(movedShapeIds: movedIds);
    });
    _selection
      ..clear()
      ..add(tableId);
    notifyListeners();
  }

  void duplicateSelectedTableRow() {
    if (!canDuplicateSelectedTableRow) return;
    final page = currentPage;
    final tableId = selectedTableId;
    final rowIndex = _selectedTableRowIndex;
    if (page == null || tableId == null || rowIndex == null) return;
    final table = page.findShapeById(tableId)!;
    final sourceCells = <VsdxShape>[
      for (final cell in TableOps.cellsOf(table))
        if (TableOps.cellRow(cell) == rowIndex) cell,
    ];
    final sourceIds = <int>{
      for (final cell in sourceCells) ..._subtreeIds(<int>{cell.id}),
    };
    final connectorIds = _fullyGluedConnectorsWithin(sourceIds)
      ..removeAll(sourceIds);
    final movedIds = _subtreeIds(<int>{tableId});
    final idMap = <int, int>{};
    updateCurrentPage((p) {
      final host = p.findShapeById(tableId);
      if (host == null) return p;
      var next = p.updateShapeById(
        tableId,
        (_) => TableOps.duplicateRow(
          host,
          rowIndex,
          startId: p.nextFreeShapeId(),
          idMap: idMap,
        ),
      );
      var nextId = idMap.values.isEmpty
          ? p.nextFreeShapeId()
          : idMap.values.reduce((a, b) => a > b ? a : b) + 1;
      final clonedConnectorIds = <int>[];
      for (final connectorId in connectorIds) {
        final connector = p.findShapeById(connectorId);
        if (connector == null) continue;
        final clone = _withTreeUnlocked(
          _clipboardRoot(p, connectorId).withRemappedIds(
            () => nextId++,
            idMap: idMap,
          ),
        );
        clonedConnectorIds.add(clone.id);
        next = next.addShape(clone);
      }
      // Connector formulas may refer to ids mapped by a later clone.
      for (final connectorId in clonedConnectorIds) {
        next = next.updateShapeById(
          connectorId,
          (shape) => VsdxShape.rewriteSheetRefsInTree(shape, idMap),
        );
      }
      final copiedConnects = <VsdxConnect>[
        for (final connect in p.connects)
          if (idMap.containsKey(connect.fromSheetId) &&
              idMap.containsKey(connect.toSheetId))
            VsdxConnect(
              fromSheetId: idMap[connect.fromSheetId]!,
              fromCell: connect.fromCell,
              fromPart: connect.fromPart,
              toSheetId: idMap[connect.toSheetId]!,
              toCell: connect.toCell,
              toPart: connect.toPart,
            ),
      ];
      if (copiedConnects.isNotEmpty) {
        next = next.copyWith(
          connects: <VsdxConnect>[...next.connects, ...copiedConnects],
        );
      }
      final changed = <int>{...movedIds, ...idMap.values};
      return next
          .syncGlueTriggers(connectorIds: idMap.values.toSet())
          .recalculateFormulas(changedShapeIds: changed)
          .rerouteConnectors(movedShapeIds: changed);
    });
    _selection.clear();
    for (final cell in sourceCells) {
      final clonedId = idMap[cell.id];
      if (clonedId != null) _selection.add(clonedId);
    }
    notifyListeners();
  }

  void duplicateSelectedTable() {
    if (!canDuplicateSelectedTable) return;
    final page = currentPage;
    final tableId = selectedTableId;
    if (page == null || tableId == null) return;
    final subtree = _subtreeIds(<int>{tableId});
    final connectorIds = _fullyGluedConnectorsWithin(subtree)
      ..removeAll(subtree);
    final copiedIds = <int>{
      ...subtree,
      for (final connectorId in connectorIds)
        ..._subtreeIds(<int>{connectorId}),
    };
    final connects = <VsdxConnect>[
      for (final connect in page.connects)
        if (copiedIds.contains(connect.fromSheetId) &&
            copiedIds.contains(connect.toSheetId))
          connect,
    ];
    _cloneShapesOntoPage(
      <VsdxShape>[
        _clipboardRoot(page, tableId),
        for (final connectorId in connectorIds)
          _clipboardRoot(page, connectorId),
      ],
      dx: 0.25,
      dy: -0.25,
      connects: connects,
    );
  }

  void removeRowFromSelectedTable() {
    if (!canRemoveTableRow) return;
    final page = currentPage;
    final tableId = selectedTableId;
    if (page == null || tableId == null) return;
    final table = page.findShapeById(tableId)!;
    var rowIndex = TableOps.dimensions(table).rows - 1;
    final cells = _selectedTableCells;
    if (cells.isNotEmpty) {
      rowIndex = TableOps.cellRow(cells.first) ?? rowIndex;
    } else {
      final sel = singleSelectedId;
      if (sel != null) {
        final cell = page.findShapeById(sel);
        if (cell != null && TableOps.isCell(cell)) {
          rowIndex = TableOps.cellRow(cell) ?? rowIndex;
        }
      }
    }
    final doomed = <int>{
      for (final c in TableOps.cellsOf(table))
        if (TableOps.cellRow(c) == rowIndex) ..._subtreeIds(<int>{c.id}),
    };
    final movedIds = _subtreeIds(<int>{tableId});
    updateCurrentPage((p) {
      final host = p.findShapeById(tableId);
      if (host == null) return p;
      var next = p.updateShapeById(
        tableId,
        (_) => TableOps.removeRow(host, rowIndex),
      );
      next = _pruneConnectsReferencing(next, doomed);
      return next
          .recalculateFormulas(changedShapeIds: movedIds)
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
    if (page == null || tableId == null) return;
    final table = page.findShapeById(tableId)!;
    var colIndex = TableOps.dimensions(table).cols - 1;
    final cells = _selectedTableCells;
    if (cells.isNotEmpty) {
      colIndex = TableOps.cellCol(cells.first) ?? colIndex;
    } else {
      final sel = singleSelectedId;
      if (sel != null) {
        final cell = page.findShapeById(sel);
        if (cell != null && TableOps.isCell(cell)) {
          colIndex = TableOps.cellCol(cell) ?? colIndex;
        }
      }
    }
    final doomed = <int>{
      for (final c in TableOps.cellsOf(table))
        if (TableOps.cellCol(c) == colIndex) ..._subtreeIds(<int>{c.id}),
    };
    final movedIds = _subtreeIds(<int>{tableId});
    updateCurrentPage((p) {
      final host = p.findShapeById(tableId);
      if (host == null) return p;
      var next = p.updateShapeById(
        tableId,
        (_) => TableOps.removeColumn(host, colIndex),
      );
      next = _pruneConnectsReferencing(next, doomed);
      return next
          .recalculateFormulas(changedShapeIds: movedIds)
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
    final tableId = selectedTableId;
    if (tableId == null || _isStructureLocked(tableId)) return false;
    final cells = _selectedTableCells;
    if (cells.length < 2) return false;
    var minR = 1 << 30, maxR = -1, minC = 1 << 30, maxC = -1;
    for (final c in cells) {
      if (c.locked || isOnLockedLayer(c.id)) return false;
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
    final tableId = selectedTableId;
    if (page == null || id == null || tableId == null) return false;
    if (_isStructureLocked(tableId)) return false;
    final s = page.findShapeById(id);
    if (s == null || !TableOps.isCell(s)) return false;
    if (s.locked || isOnLockedLayer(id)) return false;
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
    int? masterId;
    final coveredIds = <int>{};
    for (final c in cells) {
      final r = TableOps.cellRow(c)!;
      final col = TableOps.cellCol(c)!;
      if (r == minR && col == minC) {
        masterId = c.id;
      } else {
        coveredIds.add(c.id);
      }
    }
    updateCurrentPage((p) {
      final host = p.findShapeById(tableId);
      if (host == null) return p;
      var next = p.updateShapeById(
        tableId,
        (_) => TableOps.mergeCells(
          host,
          row: minR,
          col: minC,
          rowSpan: maxR - minR + 1,
          colSpan: maxC - minC + 1,
        ),
      );
      // Glue aimed at covered cells must follow the master (cells stay in the
      // model but are skipped by hit-test / paint). Sync XFTRIGGER formulas too.
      if (masterId != null && coveredIds.isNotEmpty && next.connects.isNotEmpty) {
        final affected = <int>{};
        final remapped = <VsdxConnect>[];
        for (final c in next.connects) {
          if (coveredIds.contains(c.toSheetId)) {
            affected.add(c.fromSheetId);
            // Fixed connection-point indices on covered cells rarely exist on
            // the merge master — fall back to whole-shape glue.
            final fixedCp = c.toPart != null && c.toPart! >= 100;
            remapped.add(VsdxConnect(
              fromSheetId: c.fromSheetId,
              fromCell: c.fromCell,
              fromPart: c.fromPart,
              toSheetId: masterId,
              toCell: fixedCp ? 'PinX' : c.toCell,
              toPart: fixedCp ? 3 : c.toPart,
            ));
          } else {
            remapped.add(c);
          }
        }
        next = next.copyWith(connects: remapped);
        if (affected.isNotEmpty) {
          next = next.syncGlueTriggers(connectorIds: affected);
        }
      }
      return next
          .recalculateFormulas(changedShapeIds: movedIds)
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
          .recalculateFormulas(changedShapeIds: movedIds)
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
    if (_isStructureLocked(tableId)) return;
    final movedIds = _subtreeIds(<int>{tableId});
    updateCurrentPage(
      (p) {
        final host = p.findShapeById(tableId);
        if (host == null || !TableOps.isTable(host)) return p;
        return p
            .updateShapeById(
              tableId,
              (_) => TableOps.resizeColumnBoundary(host, afterCol, deltaInches),
            )
            .recalculateFormulas(changedShapeIds: movedIds)
            .rerouteConnectors(movedShapeIds: movedIds);
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
    if (_isStructureLocked(tableId)) return;
    final movedIds = _subtreeIds(<int>{tableId});
    updateCurrentPage(
      (p) {
        final host = p.findShapeById(tableId);
        if (host == null || !TableOps.isTable(host)) return p;
        return p
            .updateShapeById(
              tableId,
              (_) => TableOps.resizeRowBoundary(host, afterRow, deltaPageY),
            )
            .recalculateFormulas(changedShapeIds: movedIds)
            .rerouteConnectors(movedShapeIds: movedIds);
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
    final undoSel = Set<int>.of(_selection);
    _selection
      ..clear()
      ..add(id);
    _tool = EditorTool.select;
    applyEdit(
      doc.replacePage(_currentPageIndex, page.addShape(shape)),
      undoSelection: undoSel,
    );
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
        _tool == EditorTool.pan ||
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
      // Either edge too small (click / hairline drag) → default text box.
      if (w < 0.1 || h < 0.1) {
        w = 1.5;
        h = 0.5;
        left = sx - w / 2;
        bottom = sy - h / 2;
      }
      final pinX = left + w / 2;
      final pinY = bottom + h / 2;
      var box = VsdxShapeFactory.textBox(
        id: id,
        pinX: pinX,
        pinY: pinY,
        width: w,
        height: h,
      );
      if (box.connectionPoints.isEmpty) {
        box = box.copyWith(
          connectionPoints: VsdxPage.defaultConnectionPoints(
            box.width,
            box.height,
          ),
        );
      }
      final undoSel = Set<int>.of(_selection);
      _selection
        ..clear()
        ..add(id);
      _tool = EditorTool.select;
      applyEdit(
        doc.replacePage(_currentPageIndex, page.addShape(box)),
        undoSelection: undoSel,
      );
      // Transient so insert + contain stay one undo step (palette / drag parity).
      applyDropContainmentAt(pinX, pinY, transient: true);
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
      // Either edge too small → default size (avoid 0.05 hairline strips).
      if (w < 0.1 || h < 0.1) {
        w = 1.5;
        h = 0.75;
        left = sx - w / 2;
        bottom = sy - h / 2;
      }
      final pinX = left + w / 2;
      final pinY = bottom + h / 2;
      base = _tool == EditorTool.rectangle
          ? VsdxShapeFactory.rectangle(
              id: id, pinX: pinX, pinY: pinY, width: w, height: h)
          : VsdxShapeFactory.ellipse(
              id: id, pinX: pinX, pinY: pinY, width: w, height: h);
    }

    final shape0 =
        _withMemoStyle(base, includeFill: _tool != EditorTool.line);
    // Materialise default blue points on new 2-D shapes so Edraw glue works
    // after save without the writer inventing points over an intentional clear.
    final shape = (!shape0.is1D && shape0.connectionPoints.isEmpty)
        ? shape0.copyWith(
            connectionPoints: VsdxPage.defaultConnectionPoints(
              shape0.width,
              shape0.height,
            ),
          )
        : shape0;
    final undoSel = Set<int>.of(_selection);
    _selection
      ..clear()
      ..add(id);
    _tool = EditorTool.select;
    applyEdit(
      doc.replacePage(_currentPageIndex, page.addShape(shape)),
      undoSelection: undoSel,
    );
    // Match stencil drop: reparent into a container / lane under the pin
    // (or line midpoint). Transient so insert + contain stay one undo step.
    final dropX = shape.is1D
        ? ((shape.beginX ?? shape.pinX) + (shape.endX ?? shape.pinX)) / 2
        : shape.pinX;
    final dropY = shape.is1D
        ? ((shape.beginY ?? shape.pinY) + (shape.endY ?? shape.pinY)) / 2
        : shape.pinY;
    applyDropContainmentAt(dropX, dropY, transient: true);
  }

  /// Create a connector line between two page points. When [beginTarget] /
  /// [endTarget] name a shape, that end is glued (a `<Connect>` row is added).
  /// With an explicit [beginConnectionPointIndex] / [endConnectionPointIndex]
  /// the end pins to that fixed blue point; otherwise whole-shape glue
  /// (`ToPart=3`) attaches on the geometry perimeter aimed at the opposite end
  /// (draw.io-style — any border point, not only the four mid-edge dots).
  /// [beginFixedAtPosition] / [endFixedAtPosition] first create a custom
  /// connection point at the supplied page position, matching draw.io's
  /// Alt/Option-drop gesture.
  void createConnector(
    double ax,
    double ay,
    double bx,
    double by, {
    int? beginTarget,
    int? endTarget,
    int? beginConnectionPointIndex,
    int? endConnectionPointIndex,
    bool beginFixedAtPosition = false,
    bool endFixedAtPosition = false,
  }) {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null) return;
    // Only 2-D shapes are valid glue targets (match canvas / agent guards).
    bool glueableTarget(int? id) {
      if (id == null) return false;
      final t = page.findShapeById(id);
      return t != null && !t.is1D;
    }

    final begin = glueableTarget(beginTarget) ? beginTarget : null;
    final end = glueableTarget(endTarget) ? endTarget : null;
    var workingPage = page;
    int? addFixedPoint(int? targetId, double x, double y) {
      if (targetId == null) return null;
      final target = workingPage.findShapeById(targetId);
      if (target == null ||
          target.is1D ||
          target.locked ||
          workingPage.isShapeTreeOnLockedLayer(targetId)) {
        return null;
      }
      final local =
          workingPage.pageToLocalDeep(targetId, Offset2D(x, y));
      workingPage = workingPage.addConnectionPoint(
        targetId,
        local.x,
        local.y,
      );
      final updated = workingPage.findShapeById(targetId);
      return updated == null || updated.connectionPoints.isEmpty
          ? null
          : updated.connectionPoints.length - 1;
    }

    var beginIdx = begin != null ? beginConnectionPointIndex : null;
    var endIdx = end != null ? endConnectionPointIndex : null;
    if (begin != null && beginFixedAtPosition) {
      beginIdx = addFixedPoint(begin, ax, ay);
    }
    if (end != null && endFixedAtPosition) {
      endIdx = addFixedPoint(end, bx, by);
    }
    final id = page.nextFreeShapeId();
    var sax = ax, say = ay, sbx = bx, sby = by;
    if (begin != null) {
      final pin = page.shapePinPage(begin);
      sax = pin.x;
      say = pin.y;
    }
    if (end != null) {
      final pin = page.shapePinPage(end);
      sbx = pin.x;
      sby = pin.y;
    }
    // Connectors carry a filled end arrowhead by default (drawio edges point
    // at their target); the stroke follows the last-used line style (never
    // Soft Edges — that is a 2-D effect).
    var baseLine = (_memoLine ?? const VsdxLine(color: VsdxColor.black))
        .copyWith(endArrow: 4);
    if (baseLine.softEdgesInches > 0) {
      baseLine = baseLine.copyWith(softEdgesInches: 0);
    }
    if (baseLine.pattern == 0) {
      baseLine = baseLine.copyWith(pattern: 1);
    }
    var connector = VsdxShapeFactory.line(
      id: id,
      ax: sax,
      ay: say,
      bx: sbx,
      by: sby,
      line: baseLine,
    );
    // Prefixed XFTRIGGER formulas so 万兴图示 re-glues when targets move.
    if (begin != null || end != null) {
      final formulas = Map<String, String>.from(connector.formulas);
      final props = connector.connectorProps ?? const VsdxConnectorProps();
      if (begin != null) {
        formulas['BegTrigger'] = '_XFTRIGGER(Sheet.$begin!EventXFMod)';
      }
      if (end != null) {
        formulas['EndTrigger'] = '_XFTRIGGER(Sheet.$end!EventXFMod)';
      }
      connector = connector.copyWith(
        formulas: formulas,
        connectorProps: props.copyWith(
          begTrigger: begin != null ? '2' : props.begTrigger,
          endTrigger: end != null ? '2' : props.endTrigger,
        ),
      );
    }
    // Prefer explicit CP indices (drawio blue points). Otherwise use whole-shape
    // glue (ToPart=3) so the endpoint attaches anywhere on the geometry
    // perimeter aimed at the opposite end — not only the four mid-edge points.
    final connects = <VsdxConnect>[
      ...workingPage.connects,
      if (begin != null)
        VsdxConnect(
          fromSheetId: id,
          fromCell: 'BeginX',
          fromPart: 9,
          toSheetId: begin,
          toCell: beginIdx != null ? 'Connections.X${beginIdx + 1}' : 'PinX',
          toPart: beginIdx != null ? 100 + beginIdx : 3,
        ),
      if (end != null)
        VsdxConnect(
          fromSheetId: id,
          fromCell: 'EndX',
          fromPart: 12,
          toSheetId: end,
          toCell: endIdx != null ? 'Connections.X${endIdx + 1}' : 'PinX',
          toPart: endIdx != null ? 100 + endIdx : 3,
        ),
    ];
    final undoSel = Set<int>.of(_selection);
    _selection
      ..clear()
      ..add(id);
    _tool = EditorTool.select;
    var next = workingPage.addShape(connector).copyWith(connects: connects);
    // Materialise Connection rows on targets so fixed-point glue round-trips.
    if (begin != null && beginIdx != null) {
      next = next.setConnectorEndpoint(
        id,
        begin: true,
        targetShapeId: begin,
        connectionPointIndex: beginIdx,
        x: sax,
        y: say,
      );
    }
    if (end != null && endIdx != null) {
      next = next.setConnectorEndpoint(
        id,
        begin: false,
        targetShapeId: end,
        connectionPointIndex: endIdx,
        x: sbx,
        y: sby,
      );
    }
    next = next
        .recalculateFormulas(changedShapeIds: <int>{id, ?begin, ?end})
        .rerouteConnectors(movedShapeIds: <int>{id, ?begin, ?end});
    applyEdit(
      doc.replacePage(
        _currentPageIndex,
        next,
      ),
      undoSelection: undoSel,
    );
  }

  /// Draw.io Alt+Shift+Arrow: connect the single selected shape to the visible
  /// shape one step away, or clone the selection there when that spot is empty.
  void connectSelectionInDirection(int dir) {
    final page = currentPage;
    final sourceId = singleSelectedId;
    if (page == null || sourceId == null || dir < 0 || dir > 3) return;
    final source = page.findShapeById(sourceId);
    if (source == null ||
        source.is1D ||
        source.locked ||
        isOnLockedLayer(sourceId)) {
      return;
    }

    const gap = 0.5;
    final aabb = page.shapePageAabb(sourceId);
    final pin = page.shapePinPage(sourceId);
    final width =
        aabb == null ? source.width : aabb.right - aabb.left;
    final height =
        aabb == null ? source.height : aabb.top - aabb.bottom;
    var cx = pin.x;
    var cy = pin.y;
    switch (dir) {
      case 0:
        cy += height + gap;
      case 1:
        cx += width + gap;
      case 2:
        cy -= height + gap;
      case 3:
        cx -= width + gap;
    }
    cx = snap(cx);
    cy = snap(cy);

    // Later shapes/children paint on top, so let the last matching visible 2-D
    // shape win just like canvas hit testing.
    int? existingTargetId;
    void findTarget(VsdxShape shape) {
      if (!page.isShapeVisible(shape)) return;
      final bounds = page.shapePageAabb(shape.id);
      if (shape.id != sourceId &&
          !shape.is1D &&
          bounds != null &&
          cx >= bounds.left &&
          cx <= bounds.right &&
          cy >= bounds.bottom &&
          cy <= bounds.top) {
        existingTargetId = shape.id;
      }
      if (shape.collapsed) return;
      for (final child in shape.children) {
        findTarget(child);
      }
    }

    for (final shape in page.shapes) {
      findTarget(shape);
    }
    connectDirectional(
      sourceId,
      dir,
      existingTargetId: existingTargetId,
      cloneX: cx,
      cloneY: cy,
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
    if (source == null ||
        source.is1D ||
        source.locked ||
        isOnLockedLayer(sourceId)) {
      return;
    }

    var next = page;
    final int targetId;
    var didClone = false;
    if (existingTargetId != null &&
        existingTargetId != sourceId &&
        page.findShapeById(existingTargetId)?.is1D == false) {
      targetId = existingTargetId;
    } else {
      // Nothing to connect to yet: clone the source one step over (drawio
      // copies the shape and wires it up). Remap the whole subtree so a
      // group source does not collide with its original children.
      var nextId = next.nextFreeShapeId();
      // Nested sources keep parent-local pin/angle — materialize page space
      // before cloning as a top-level neighbour (same as clipboard roots).
      final cloneSrc = _clipboardRoot(page, sourceId);
      final clone = cloneSrc.withRemappedIds(
        () => nextId++,
        pinX: cloneX,
        pinY: cloneY,
      );
      next = next.addShape(clone);
      targetId = clone.id;
      didClone = true;
    }

    _wireDirectionalConnector(
      page: next,
      sourceId: sourceId,
      targetId: targetId,
      dir: dir,
    );
    // Match quick-add: reparent a freshly cloned neighbour into a lane /
    // container under its pin (folded into the same undo step).
    if (didClone) {
      applyDropContainmentAt(snap(cloneX), snap(cloneY), transient: true);
    }
  }

  /// EdrawMax / draw.io quick-add: place a shape from [build] one step from
  /// [sourceId] in [dir] (0=N, 1=E, 2=S, 3=W) at ([cx],[cy]) and glue a
  /// connector between facing connection points. One undo step; selects the
  /// new shape. No-op for a 1-D / locked source.
  void quickAddInDirection(
    int sourceId,
    int dir, {
    required VsdxShape Function(int id, double cx, double cy) build,
    required double cx,
    required double cy,
    bool inheritStyle = true,
  }) {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null) return;
    final source = page.findShapeById(sourceId);
    if (source == null ||
        source.is1D ||
        source.locked ||
        isOnLockedLayer(sourceId)) {
      return;
    }

    final id = page.nextFreeShapeId();
    final built = build(id, snap(cx), snap(cy));
    if (built.is1D) return;
    var shape =
        inheritStyle ? _withMemoStyle(built, includeFill: true) : built;
    if (shape.connectionPoints.isEmpty) {
      shape = shape.copyWith(
        connectionPoints: VsdxPage.defaultConnectionPoints(
          shape.width,
          shape.height,
        ),
      );
    }
    final next = page.addShape(shape);
    _wireDirectionalConnector(
      page: next,
      sourceId: sourceId,
      targetId: id,
      dir: dir,
    );
    // Fold lane/container reparent into the same undo step as the insert.
    applyDropContainmentAt(snap(cx), snap(cy), transient: true);
  }

  /// Shared glue + route for [connectDirectional] / [quickAddInDirection]:
  /// connector from [sourceId] to [targetId] along [dir], ends pinned to facing
  /// fixed connection points. Applies one undo step and selects [targetId].
  void _wireDirectionalConnector({
    required VsdxPage page,
    required int sourceId,
    required int targetId,
    required int dir,
  }) {
    final doc = _document;
    if (doc == null) return;
    final source = page.findShapeById(sourceId);
    final target = page.findShapeById(targetId);
    if (source == null || target == null) return;

    var next = page;
    final connId = next.nextFreeShapeId();
    var baseLine = (_memoLine ?? const VsdxLine(color: VsdxColor.black))
        .copyWith(endArrow: 4);
    if (baseLine.softEdgesInches > 0) {
      baseLine = baseLine.copyWith(softEdgesInches: 0);
    }
    if (baseLine.pattern == 0) {
      baseLine = baseLine.copyWith(pattern: 1);
    }
    final srcPin = next.shapePinPage(sourceId);
    final tgtPin = next.shapePinPage(targetId);
    var connector = VsdxShapeFactory.line(
      id: connId,
      ax: srcPin.x,
      ay: srcPin.y,
      bx: tgtPin.x,
      by: tgtPin.y,
      line: baseLine,
    );
    // Same XFTRIGGER wiring as [createConnector] so exported diagrams re-glue.
    final formulas = Map<String, String>.from(connector.formulas);
    formulas['BegTrigger'] = '_XFTRIGGER(Sheet.$sourceId!EventXFMod)';
    formulas['EndTrigger'] = '_XFTRIGGER(Sheet.$targetId!EventXFMod)';
    final props = connector.connectorProps ?? const VsdxConnectorProps();
    connector = connector.copyWith(
      formulas: formulas,
      connectorProps: props.copyWith(begTrigger: '2', endTrigger: '2'),
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
    );

    // Glue each end to the facing fixed connection point so the edge meets the
    // sides square-on. [dir] is page-space N/E/S/W (hover arrows); map to the
    // nearest side CP after rotate/flip via [connectionIndexForPageDir].
    final srcPts = VsdxPage.effectiveConnectionPoints(source);
    final tgtPts = VsdxPage.effectiveConnectionPoints(target);
    if (srcPts.length >= 4 && dir >= 0 && dir < 4) {
      final beginIdx = next.connectionIndexForPageDir(sourceId, dir);
      next = next.setConnectorEndpoint(
        connId,
        begin: true,
        targetShapeId: sourceId,
        connectionPointIndex: beginIdx,
        x: srcPin.x,
        y: srcPin.y,
      );
    }
    final endDir = (dir + 2) % 4;
    if (tgtPts.length >= 4) {
      final endIdx = next.connectionIndexForPageDir(targetId, endDir);
      next = next.setConnectorEndpoint(
        connId,
        begin: false,
        targetShapeId: targetId,
        connectionPointIndex: endIdx,
        x: tgtPin.x,
        y: tgtPin.y,
      );
    }
    next = next
        .recalculateFormulas(
          changedShapeIds: <int>{connId, sourceId, targetId},
        )
        .rerouteConnectors(
          movedShapeIds: <int>{connId, sourceId, targetId},
        );

    final undoSel = Set<int>.of(_selection);
    _selection
      ..clear()
      ..add(targetId);
    _tool = EditorTool.select;
    applyEdit(
      doc.replacePage(_currentPageIndex, next),
      undoSelection: undoSel,
    );
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
    String? name,
    List<VsdxUserCell>? userCells,
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
    final pinX = snap(cx ?? page.widthInches / 2);
    final pinY = snap(cy ?? page.heightInches / 2);
    var shape = VsdxShapeFactory.picture(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      imagePartName: minted.partName,
      name: name,
    );
    if (userCells != null && userCells.isNotEmpty) {
      shape = shape.copyWith(userCells: userCells);
    }
    if (shape.connectionPoints.isEmpty) {
      shape = shape.copyWith(
        connectionPoints: VsdxPage.defaultConnectionPoints(
          shape.width,
          shape.height,
        ),
      );
    }
    final undoSel = Set<int>.of(_selection);
    _selection
      ..clear()
      ..add(id);
    _tool = EditorTool.select;
    applyEdit(
      doc.copyWith(images: doc.images.withImage(minted)).replacePage(
            _currentPageIndex,
            page.addShape(shape),
          ),
      undoSelection: undoSel,
    );
    // Fold lane/container reparent into the same undo step as the insert.
    applyDropContainmentAt(pinX, pinY, transient: true);
  }

  /// Replace the media on an existing picture shape (drawio drop-on-image /
  /// "Replace Image"). Keeps pin / size / angle; mints a fresh media part so
  /// undo of a prior insert can't collide. One undo step.
  void replaceImage(
    int shapeId,
    Uint8List bytes, {
    required String fileExtension,
    List<VsdxUserCell>? userCells,
    bool clearIconMeta = false,
  }) {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null || bytes.isEmpty) return;
    final shape = page.findShapeById(shapeId);
    if (shape == null ||
        !shape.hasImage ||
        shape.locked ||
        isOnLockedLayer(shapeId) ||
        !page.isShapeVisible(shape)) {
      return;
    }

    final minted = _mintImage(doc, bytes, fileExtension);
    final oldPart = shape.imagePartName;
    final next = page.updateShapeById(
      shapeId,
      (s) {
        var cells = userCells ?? s.userCells;
        if (clearIconMeta && userCells == null) {
          cells = [
            for (final c in s.userCells)
              if (c.name != IconOps.userIcon &&
                  c.name != IconOps.userProvider &&
                  c.name != IconOps.userId &&
                  c.name != IconOps.userColor)
                c,
          ];
        }
        return s.copyWith(
          imagePartName: minted.partName,
          foreignType: minted.foreignType,
          foreignCompressionType: minted.compressionType,
          userCells: cells,
        );
      },
    );
    final undoSel = Set<int>.of(_selection);
    _selection
      ..clear()
      ..add(shapeId);
    _tool = EditorTool.select;
    var images = doc.images.withImage(minted);
    // Drop the old part from the in-memory registry when nothing else uses it
    // (zip prune on save handles the package; this keeps warmUp lean).
    if (oldPart != null &&
        oldPart.isNotEmpty &&
        !_anyShapeUsesImage(doc, oldPart, exceptShapeId: shapeId)) {
      images = images.withoutImage(oldPart);
    }
    applyEdit(
      doc.copyWith(images: images).replacePage(
            _currentPageIndex,
            next,
          ),
      undoSelection: undoSel,
    );
  }

  /// True when any shape (any page / nested) still references [partName].
  bool _anyShapeUsesImage(
    VsdxDocument doc,
    String partName, {
    int? exceptShapeId,
  }) {
    String norm(String p) => p.startsWith('/') ? p.substring(1) : p;
    final want = norm(partName);
    bool walk(VsdxShape s) {
      if (exceptShapeId == null || s.id != exceptShapeId) {
        final p = s.imagePartName;
        if (p != null && p.isNotEmpty && norm(p) == want) return true;
      }
      for (final c in s.children) {
        if (walk(c)) return true;
      }
      return false;
    }

    for (final page in doc.pages) {
      for (final s in page.shapes) {
        if (walk(s)) return true;
      }
    }
    return false;
  }

  /// True when the single selection is an unlocked, visible picture shape.
  bool get canReplaceSelectedImage {
    final id = singleSelectedId;
    final page = currentPage;
    if (id == null || page == null) return false;
    final s = page.findShapeById(id);
    return s != null &&
        s.hasImage &&
        !s.locked &&
        !isOnLockedLayer(id) &&
        page.isShapeVisible(s);
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
      if (s == null ||
          !s.hasImage ||
          s.locked ||
          isOnLockedLayer(id) ||
          !page.isShapeVisible(s)) {
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
    VsdxShape Function(int id, double cx, double cy) build, {
    bool inheritStyle = true,
  }) {
    final page = currentPage;
    if (page == null) return;
    addShapeFromBuilderAt(
      build,
      page.widthInches / 2,
      page.heightInches / 2,
      inheritStyle: inheritStyle,
    );
  }

  /// Add a shape produced by [build] centred at page point ([cx],[cy])
  /// (snapped to the grid) and select it. [inheritStyle] applies the remembered
  /// creation style; [allowContainment] reparents it into a container under the
  /// drop point. Shape-library Shift and Alt modifiers disable those behaviours
  /// respectively, matching draw.io.
  void addShapeFromBuilderAt(
    VsdxShape Function(int id, double cx, double cy) build,
    double cx,
    double cy, {
    bool inheritStyle = true,
    bool allowContainment = true,
  }) {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null) return;
    final id = page.nextFreeShapeId();
    final built = build(id, snap(cx), snap(cy));
    var shape = inheritStyle
        ? _withMemoStyle(built, includeFill: !built.is1D)
        : built;
    // Materialise default blue points like [createShapeByDrag] / quick-add so
    // exported diagrams keep glue targets (writer no longer invents them).
    if (!shape.is1D && shape.connectionPoints.isEmpty) {
      shape = shape.copyWith(
        connectionPoints: VsdxPage.defaultConnectionPoints(
          shape.width,
          shape.height,
        ),
      );
    }
    final undoSel = Set<int>.of(_selection);
    _selection
      ..clear()
      ..add(id);
    _tool = EditorTool.select;
    applyEdit(
      doc.replacePage(_currentPageIndex, page.addShape(shape)),
      undoSelection: undoSel,
    );
    if (allowContainment) {
      // Fold containment into the same undo step as the insert (transient).
      applyDropContainmentAt(snap(cx), snap(cy), transient: true);
    }
  }

  /// Add a library shape beneath the lower-left of the existing drawing.
  ///
  /// This is draw.io's Alt+click palette placement: it avoids the normal
  /// centre-page stack while keeping the finite Visio page bounds usable.
  void addShapeFromBuilderBottomLeft(
    VsdxShape Function(int id, double cx, double cy) build, {
    bool inheritStyle = true,
  }) {
    final page = currentPage;
    if (page == null) return;
    final probe = build(page.nextFreeShapeId(), 0, 0);
    const margin = 0.25;
    const gap = 0.25;
    final bounds =
        <({double left, double bottom, double right, double top})>[
      for (final shape in page.shapes)
        if (page.isShapeVisible(shape))
          ?page.shapePageAabb(shape.id),
    ];
    final left = bounds.isEmpty
        ? margin
        : bounds.map((box) => box.left).reduce(math.min);
    final bottom = bounds.isEmpty
        ? margin + probe.height.abs() + gap
        : bounds.map((box) => box.bottom).reduce(math.min);
    final halfW = probe.width.abs() / 2;
    final halfH = probe.height.abs() / 2;
    final minX = margin + halfW;
    final maxX = math.max(minX, page.widthInches - margin - halfW);
    final minY = margin + halfH;
    final maxY = math.max(minY, page.heightInches - margin - halfH);
    final cx = (left + halfW).clamp(minX, maxX).toDouble();
    final cy = (bottom - gap - halfH).clamp(minY, maxY).toDouble();
    addShapeFromBuilderAt(
      build,
      cx,
      cy,
      inheritStyle: inheritStyle,
      // Alt means overlay rather than becoming a container child.
      allowContainment: false,
    );
  }

  /// Whether a palette Alt+Shift/Ctrl click can insert and connect a new shape.
  bool get canQuickAddSelection {
    final page = currentPage;
    final id = singleSelectedId;
    if (page == null || id == null) return false;
    final source = page.findShapeById(id);
    return source != null &&
        !source.is1D &&
        !source.locked &&
        !isOnLockedLayer(id) &&
        page.isShapeVisible(source);
  }

  /// Insert a chosen palette shape beside the single selected shape and glue
  /// them together. Prefers right, then below, left and above according to the
  /// available page space (draw.io Alt+Shift/Ctrl+click).
  void quickAddSelectionWithBuilder(
    VsdxShape Function(int id, double cx, double cy) build,
  ) {
    if (!canQuickAddSelection) return;
    final page = currentPage!;
    final sourceId = singleSelectedId!;
    final sourceBounds = page.shapePageAabb(sourceId);
    if (sourceBounds == null) return;
    final probe = build(page.nextFreeShapeId(), 0, 0);
    if (probe.is1D) return;
    const gap = 0.5;
    const margin = 0.1;
    final halfW = probe.width.abs() / 2;
    final halfH = probe.height.abs() / 2;
    final sourceCx = (sourceBounds.left + sourceBounds.right) / 2;
    final sourceCy = (sourceBounds.bottom + sourceBounds.top) / 2;
    final candidates = <({int dir, double x, double y})>[
      (
        dir: 1,
        x: sourceBounds.right + gap + halfW,
        y: sourceCy,
      ),
      (
        dir: 2,
        x: sourceCx,
        y: sourceBounds.bottom - gap - halfH,
      ),
      (
        dir: 3,
        x: sourceBounds.left - gap - halfW,
        y: sourceCy,
      ),
      (
        dir: 0,
        x: sourceCx,
        y: sourceBounds.top + gap + halfH,
      ),
    ];
    final chosen = candidates.firstWhere(
      (candidate) =>
          candidate.x - halfW >= margin &&
          candidate.x + halfW <= page.widthInches - margin &&
          candidate.y - halfH >= margin &&
          candidate.y + halfH <= page.heightInches - margin,
      orElse: () => candidates.first,
    );
    quickAddInDirection(
      sourceId,
      chosen.dir,
      build: build,
      cx: chosen.x,
      cy: chosen.y,
    );
  }

  /// The preferred free end of the selected connector, in page inches.
  ///
  /// draw.io attaches a palette shape to the unconnected end of a selected
  /// connector. When both ends are free, prefer the arrow/end side.
  ({int connectorId, bool begin, double x, double y})?
      get _selectedConnectorFreeEnd {
    final page = currentPage;
    final id = singleSelectedId;
    if (page == null || id == null) return null;
    final connector = page.findShapeById(id);
    if (connector == null ||
        !connector.isGlueableConnector ||
        connector.locked ||
        isOnLockedLayer(id) ||
        !page.isShapeVisible(connector)) {
      return null;
    }
    final beginGlued =
        page.connects.any((row) => row.fromSheetId == id && row.isBegin);
    final endGlued =
        page.connects.any((row) => row.fromSheetId == id && row.isEnd);
    if (beginGlued && endGlued) return null;
    final begin = endGlued;
    final route = page.drawnConnectorPagePolyline(connector);
    if (route.length < 2) return null;
    final point = begin ? route.first : route.last;
    return (
      connectorId: id,
      begin: begin,
      x: point.x,
      y: point.y,
    );
  }

  /// Whether clicking a palette shape can attach it to the selected connector.
  bool get canAttachShapeToSelectionConnector =>
      _selectedConnectorFreeEnd != null;

  /// Insert a palette shape at a specific free connector end and glue it.
  ///
  /// Used by both palette-click attachment and canvas drop-on-endpoint. The
  /// connector may be unselected, but it must be visible, editable and the
  /// requested end must still be free.
  bool attachShapeToConnectorEnd(
    int connectorId, {
    required bool begin,
    required VsdxShape Function(int id, double cx, double cy) build,
    bool inheritStyle = true,
  }) {
    final page = currentPage;
    final connector = page?.findShapeById(connectorId);
    if (page == null ||
        connector == null ||
        !connector.isGlueableConnector ||
        connector.locked ||
        isOnLockedLayer(connectorId) ||
        !page.isShapeVisible(connector)) {
      return false;
    }
    final endIsGlued = page.connects.any(
      (row) =>
          row.fromSheetId == connectorId &&
          (begin ? row.isBegin : row.isEnd),
    );
    if (endIsGlued) return false;
    final route = page.drawnConnectorPagePolyline(connector);
    if (route.length < 2) return false;
    final point = begin ? route.first : route.last;
    final probe = build(page.nextFreeShapeId(), point.x, point.y);
    if (probe.is1D) return false;

    beginTransaction();
    addShapeFromBuilderAt(
      build,
      point.x,
      point.y,
      inheritStyle: inheritStyle,
      // A connector endpoint may sit over a container; attaching a shape must
      // not silently change its parent as a side effect.
      allowContainment: false,
    );
    final shapeId = singleSelectedId;
    if (shapeId == null) {
      cancelTransaction();
      return false;
    }
    reconnectEndpoint(
      connectorId,
      begin: begin,
      targetShapeId: shapeId,
      x: point.x,
      y: point.y,
      transient: true,
    );
    commitTransaction();
    return true;
  }

  /// Insert a palette shape at the selected connector's free end and glue it.
  ///
  /// The insert and endpoint reconnect are committed as one undo step. Returns
  /// false when the selection has no free connector end or [build] is 1-D.
  bool attachShapeToSelectionConnector(
    VsdxShape Function(int id, double cx, double cy) build, {
    bool inheritStyle = true,
  }) {
    final free = _selectedConnectorFreeEnd;
    if (free == null) return false;
    return attachShapeToConnectorEnd(
      free.connectorId,
      begin: free.begin,
      build: build,
      inheritStyle: inheritStyle,
    );
  }

  /// Whether Shift-clicking a stencil can replace at least one selected shape.
  bool get canReplaceSelectionShapes {
    final page = currentPage;
    if (page == null) return false;
    return _selectionRoots(page, _selection.toList()).any((id) {
      final s = page.findShapeById(id);
      return s != null &&
          !s.is1D &&
          s.children.isEmpty &&
          !s.locked &&
          !isOnLockedLayer(id);
    });
  }

  /// Whether a palette drop may replace [shapeId].
  bool canReplaceShape(int shapeId) {
    final page = currentPage;
    final shape = page?.findShapeById(shapeId);
    return page != null &&
        shape != null &&
        !shape.is1D &&
        shape.children.isEmpty &&
        !shape.locked &&
        !isOnLockedLayer(shapeId) &&
        page.isShapeVisible(shape);
  }

  /// Replace the shape under a palette drop. Dropping on one member of a
  /// multi-selection replaces all selected compatible shapes, like draw.io.
  bool replaceShapeWithBuilder(
    int shapeId,
    VsdxShape Function(int id, double cx, double cy) build,
  ) {
    final page = currentPage;
    if (page == null || !canReplaceShape(shapeId)) return false;
    final wasSelected = _selection.contains(shapeId);
    final candidates = wasSelected
        ? _selectionRoots(page, _selection.toList())
        : <int>[shapeId];
    return _replaceShapesWithBuilder(
      candidates,
      build,
      selectionAfter: wasSelected ? null : <int>{shapeId},
    );
  }

  /// Replace selected atomic shapes with [build] while preserving their
  /// position, size, label, style, data, links and connector glue.
  ///
  /// Shape ids stay stable, so page-level `<Connect>` rows remain valid. This
  /// implements draw.io's Shift-click shape-library replacement and supports
  /// multiple selected shapes as one undoable edit.
  bool replaceSelectionWithBuilder(
    VsdxShape Function(int id, double cx, double cy) build,
  ) {
    final page0 = currentPage;
    if (page0 == null) return false;
    return _replaceShapesWithBuilder(
      _selectionRoots(page0, _selection.toList()),
      build,
    );
  }

  bool _replaceShapesWithBuilder(
    Iterable<int> candidates,
    VsdxShape Function(int id, double cx, double cy) build, {
    Set<int>? selectionAfter,
  }) {
    final page0 = currentPage;
    if (page0 == null) return false;
    final targets = <int>[
      for (final id in candidates)
        if (page0.findShapeById(id) case final s?
            when !s.is1D &&
                s.children.isEmpty &&
                !s.locked &&
                !isOnLockedLayer(id) &&
                page0.isShapeVisible(s))
          id,
    ];
    if (targets.isEmpty) return false;
    final movedIds = _subtreeIds(targets);
    var replaced = false;
    updateCurrentPage((page) {
      var next = page;
      var changed = false;
      for (final id in targets) {
        final old = next.findShapeById(id);
        if (old == null) continue;
        final template = build(id, old.pinX, old.pinY);
        if (template.is1D || template.children.isNotEmpty) continue;
        var replacement = template.resizeTo(
          pinX: old.pinX,
          pinY: old.pinY,
          width: old.width,
          height: old.height,
        );
        final geometries = syncGeometryNoLine(
          syncGeometryNoFill(
            replacement.geometries,
            hollow: old.fill.pattern == 0,
          ),
          hollow: old.line.pattern == 0,
        );
        replacement = replacement.copyWith(
          id: old.id,
          name: old.name,
          pinX: old.pinX,
          pinY: old.pinY,
          width: old.width,
          height: old.height,
          angleRad: old.angleRad,
          text: old.text,
          richText: old.richText,
          geometries: geometries,
          fill: old.fill,
          line: old.line,
          shadow: old.shadow,
          glow: old.glow,
          reflection: old.reflection,
          layerMemberIds: old.layerMemberIds,
          connectionPoints: replacement.connectionPoints.isEmpty
              ? VsdxPage.defaultConnectionPoints(old.width, old.height)
              : replacement.connectionPoints,
          flipX: old.flipX,
          flipY: old.flipY,
          locked: old.locked,
          resizeMode: old.resizeMode,
          eventDblClick: old.eventDblClick,
          noAlignBox: old.noAlignBox,
          shapeSplittable: old.shapeSplittable,
          themeIndex: old.themeIndex,
          quickStyleFillMatrix: old.quickStyleFillMatrix,
          quickStyleLineMatrix: old.quickStyleLineMatrix,
          quickStyleEffectsMatrix: old.quickStyleEffectsMatrix,
          quickStyleFontMatrix: old.quickStyleFontMatrix,
          hyperlinks: old.hyperlinks,
          userProperties: old.userProperties,
          userCells: old.userCells,
          fields: old.fields,
          actions: old.actions,
          lineStyleId: old.lineStyleId,
          fillStyleId: old.fillStyleId,
          textStyleId: old.textStyleId,
        );
        next = next.updateShapeById(id, (_) => replacement);
        changed = true;
      }
      replaced = changed;
      return changed
          ? next
              .recalculateFormulas(changedShapeIds: movedIds)
              .rerouteConnectors(movedShapeIds: movedIds)
          : page;
    });
    if (replaced && selectionAfter != null) {
      _selection
        ..clear()
        ..addAll(selectionAfter);
      _tool = EditorTool.select;
      notifyListeners();
    }
    return replaced;
  }

  static bool _isStructuralTableCell(VsdxPage page, VsdxShape shape) {
    if (!TableOps.isCell(shape)) return false;
    final parentId = page.findParentId(shape.id);
    final parent = parentId == null ? null : page.findShapeById(parentId);
    return parent != null && TableOps.isTable(parent);
  }

  /// Delete all selected shapes as a single undo step.
  ///
  /// Plain deletion preserves incident connectors as floating lines, matching
  /// draw.io's Delete / Backspace behaviour. When [includeConnected] is true,
  /// every unlocked connector glued to a removed shape (or descendant) is
  /// deleted too — draw.io's Shift+toolbar-delete gesture.
  void deleteSelection({bool includeConnected = false}) {
    if (_editingConnectionPoints) {
      removeSelectedConnectionPoint();
      return;
    }
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null || _selection.isEmpty) return;
    // draw.io tables treat Delete as a row/column operation. Never remove a
    // raw cell child: sparse/mixed cell selections are deliberately preserved.
    if (_selectedTableDeleteBand != null) {
      deleteSelectedTableBand();
      return;
    }
    var next = page;
    final removedRoots = <int>[];
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null && (s.locked || isOnLockedLayer(id))) {
        continue; // locked shapes / layers can't be deleted
      }
      if (s != null && _isStructuralTableCell(page, s)) {
        continue;
      }
      if (s != null) removedRoots.add(id);
    }
    final removedIds = _subtreeIds(removedRoots);
    final connectedIds = <int>{};
    if (includeConnected && removedIds.isNotEmpty) {
      for (final connect in page.connects) {
        if (!removedIds.contains(connect.toSheetId) ||
            removedIds.contains(connect.fromSheetId)) {
          continue;
        }
        final connector = page.findShapeById(connect.fromSheetId);
        if (connector == null ||
            !connector.isGlueableConnector ||
            connector.locked ||
            isOnLockedLayer(connector.id)) {
          continue;
        }
        connectedIds.add(connector.id);
      }
    }
    for (final id in <int>[...removedRoots, ...connectedIds]) {
      next = next.removeShapeById(id);
    }
    if (identical(next, page)) return;
    final undoSel = Set<int>.of(_selection);
    // Removing a parent also deletes descendants — clear those ids too.
    _selection
      ..removeAll(removedIds)
      ..removeAll(connectedIds);
    applyEdit(
      doc.replacePage(_currentPageIndex, next),
      undoSelection: undoSel,
    );
  }

  /// Delete a single shape by [id] (recursing into groups) as one undo step.
  void deleteShapeById(int id) {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null) return;
    final target = page.findShapeById(id);
    if (target != null &&
        (target.locked ||
            isOnLockedLayer(id) ||
            _isStructuralTableCell(page, target))) {
      return; // locked shapes/layers and structural cells can't be deleted
    }
    final doomed = _subtreeIds(<int>{id});
    final next = page.removeShapeById(id);
    if (identical(next, page)) return;
    final undoSel = Set<int>.of(_selection);
    _selection.removeAll(doomed);
    applyEdit(
      doc.replacePage(_currentPageIndex, next),
      undoSelection: undoSel,
    );
  }

  /// Remove a just-created abandoned shape (empty Text-tool box) without
  /// leaving a resurrectable undo step. Collapses history back to the
  /// snapshot before [id] existed when that is still a pure create (+ edits
  /// of that shape only); otherwise falls back to [deleteShapeById].
  void discardAbandonedShape(int id) {
    if (_collapseCreateOf(id)) return;
    deleteShapeById(id);
  }

  /// Restore the newest undo snapshot that predates top-level shape [id],
  /// when current page top-level count is exactly that snapshot + 1 (only
  /// this shape was added). Covers "create → Bold → Esc" as well as a bare
  /// create tip.
  bool _collapseCreateOf(int id) {
    if (_undo.isEmpty || _document == null) return false;
    final curPage = currentPage;
    if (curPage == null || curPage.findShapeById(id) == null) return false;
    for (var i = _undo.length - 1; i >= 0; i--) {
      final tip = _undo[i];
      if (tip.pageIndex != _currentPageIndex) continue;
      final tipPage = tip.document.pages[tip.pageIndex];
      if (tipPage.findShapeById(id) != null) continue;
      if (curPage.shapes.length != tipPage.shapes.length + 1) {
        // Other structural edits happened after create — do not collapse.
        return false;
      }
      _undo.removeRange(i, _undo.length);
      _document = tip.document;
      _currentPageIndex = tip.pageIndex;
      _selection
        ..clear()
        ..addAll(tip.selection);
      _redo.clear();
      _dirty = !identical(_document, _cleanDocument);
      _clampPageIndex();
      _pruneSelection();
      notifyListeners();
      return true;
    }
    return false;
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
      skipLocked: false,
    );
  }

  List<VsdxShape> _clipboard = const <VsdxShape>[];
  List<VsdxConnect> _clipboardConnects = const <VsdxConnect>[];
  ImageRegistry _clipboardImages = ImageRegistry.empty;
  /// Successive plain pastes offset further so copies do not stack.
  int _pasteGeneration = 0;
  /// Bumped on every copy/cut so a stale async [Clipboard.setData] cannot
  /// overwrite a newer in-app or external clipboard write.
  int _clipboardWriteSerial = 0;
  /// Last envelope we wrote to the system clipboard (trimmed). Used so
  /// [syncClipboardFromSystem] does not replace a richer in-memory clipboard
  /// (Connect rows / images) with our own stripped system encode.
  String? _lastSystemEnvelope;
  /// While true, system envelope sync is ignored so a pending write (or an
  /// image-only copy that cannot encode) cannot clobber in-memory paste data.
  bool _preferMemoryClipboard = false;
  bool get hasClipboard => _clipboard.isNotEmpty;

  /// Selection ids that are not descendants of another selected shape — used
  /// so copy/paste of a group + child does not duplicate the child.
  static List<int> _selectionRoots(VsdxPage page, Iterable<int> ids) {
    final selected = ids.toSet();
    bool hasSelectedAncestor(int id) {
      var p = page.findParentId(id);
      while (p != null) {
        if (selected.contains(p)) return true;
        p = page.findParentId(p);
      }
      return false;
    }

    return <int>[
      for (final id in ids)
        if (page.findShapeById(id) != null && !hasSelectedAncestor(id)) id,
    ];
  }

  /// Copy the current selection into the in-app clipboard **and** the system
  /// clipboard (encoded as a tiny `.vsdx` envelope for cross-instance paste).
  void copySelection() {
    final page = currentPage;
    if (page == null || _selection.isEmpty) return;
    final roots = _selectionRoots(page, _selection);
    if (roots.isEmpty) return;
    final subtree = _subtreeIds(roots);
    // Nested roots keep parent-local pins; materialize page pin/angle so paste
    // as a top-level shape lands where the original appeared on the page.
    _clipboard = <VsdxShape>[
      for (final id in roots) _clipboardRoot(page, id),
    ];
    // Keep glue rows whose both ends are in the copied subtree so paste can
    // re-wire the copies to each other (not the originals).
    _clipboardConnects = <VsdxConnect>[
      for (final c in page.connects)
        if (subtree.contains(c.fromSheetId) && subtree.contains(c.toSheetId)) c,
    ];
    _clipboardImages = _document?.images ?? ImageRegistry.empty;
    _pasteGeneration = 0;
    _preferMemoryClipboard = true;
    _lastSystemEnvelope = null;
    final writeSerial = ++_clipboardWriteSerial;
    notifyListeners();
    unawaited(_writeSystemClipboard(
      _clipboard,
      _clipboardConnects,
      images: _clipboardImages,
      writeSerial: writeSerial,
    ));
  }

  /// Shape tree ready for top-level paste: page pin / angle / flip when [id]
  /// is nested (children stay in the root's local frame).
  static VsdxShape _clipboardRoot(VsdxPage page, int id) =>
      page.shapeAsPageRoot(id);

  Future<void> _writeSystemClipboard(
    List<VsdxShape> shapes,
    List<VsdxConnect> connects, {
    ImageRegistry images = ImageRegistry.empty,
    required int writeSerial,
  }) async {
    try {
      final envelope = ShapeClipboardCodec.encode(
        shapes,
        connects: connects,
        images: images,
      );
      // A newer copy/cut superseded this write — do not touch the pasteboard.
      if (writeSerial != _clipboardWriteSerial) return;
      if (envelope.isEmpty) {
        // Empty after encode — keep preferring memory so a stale system
        // envelope cannot wipe the in-app clipboard.
        _preferMemoryClipboard = true;
        _lastSystemEnvelope = null;
        return;
      }
      await Clipboard.setData(ClipboardData(text: envelope));
      if (writeSerial != _clipboardWriteSerial) return;
      _lastSystemEnvelope = envelope.trim();
      _preferMemoryClipboard = false;
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
      final payload = ShapeClipboardCodec.decodeEnvelope(text);
      if (payload != null) {
        if (payload.shapes.isEmpty) return false;
        final trimmed = text.trim();
        // Same-app copy: keep in-memory clipboard (images + Connect rows).
        if (_preferMemoryClipboard && _clipboard.isNotEmpty) return false;
        if (_lastSystemEnvelope != null && trimmed == _lastSystemEnvelope) {
          return false;
        }
        // Invalidate any in-flight system write from a prior copy/cut.
        _clipboardWriteSerial++;
        _clipboard = payload.shapes;
        _clipboardConnects = payload.connects;
        _clipboardImages = payload.images;
        _pasteGeneration = 0;
        _preferMemoryClipboard = false;
        notifyListeners();
        return true;
      }
      // External plain text always wins over an image-only memory clipboard
      // (_preferMemory only guards our own shape envelopes, not foreign text).
      final trimmed = text.trim();
      if (trimmed.isEmpty || ShapeClipboardCodec.looksLikeEnvelope(text)) {
        return false;
      }
      _clipboardWriteSerial++;
      final plain = VsdxShapeFactory.textBox(
        id: 1,
        pinX: 0,
        pinY: 0,
        width: 1.6,
        height: 0.6,
        text: trimmed,
      );
      _clipboard = <VsdxShape>[
        plain.copyWith(
          connectionPoints: VsdxPage.defaultConnectionPoints(
            plain.width,
            plain.height,
          ),
        ),
      ];
      _clipboardConnects = const <VsdxConnect>[];
      _clipboardImages = ImageRegistry.empty;
      _pasteGeneration = 0;
      _preferMemoryClipboard = false;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Cut = copy deletable shapes to the clipboard, then delete them.
  /// Locked shapes / shapes on locked layers stay put and are not copied, so
  /// Paste cannot resurrect a shape that Cut refused to remove.
  void cut() {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null || _selection.isEmpty) return;
    final cuttable = _selectionRoots(page, <int>[
      for (final id in _selection)
        if (page.findShapeById(id) case final s?
            when !s.locked &&
                !isOnLockedLayer(id) &&
                !_isStructuralTableCell(page, s))
          id,
    ]);
    if (cuttable.isEmpty) return;
    final subtree = _subtreeIds(cuttable);
    final originalSel = Set<int>.of(_selection);
    _clipboard = <VsdxShape>[
      for (final id in cuttable) _clipboardRoot(page, id),
    ];
    _clipboardConnects = <VsdxConnect>[
      for (final c in page.connects)
        if (subtree.contains(c.fromSheetId) && subtree.contains(c.toSheetId)) c,
    ];
    _clipboardImages = doc.images;
    _pasteGeneration = 0;
    _preferMemoryClipboard = true;
    _lastSystemEnvelope = null;
    final writeSerial = ++_clipboardWriteSerial;
    unawaited(_writeSystemClipboard(
      _clipboard,
      _clipboardConnects,
      images: _clipboardImages,
      writeSerial: writeSerial,
    ));

    var next = page;
    for (final id in cuttable) {
      next = next.removeShapeById(id);
    }
    if (identical(next, page)) return;
    _selection.removeAll(subtree);
    applyEdit(
      doc.replacePage(_currentPageIndex, next),
      undoSelection: originalSel,
    );
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
    if (_clipboard.isEmpty) return;
    late final double dx;
    late final double dy;
    if (cx != null && cy != null) {
      var minX = double.infinity, minY = double.infinity;
      var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
      for (final s in _clipboard) {
        // Use rotation-aware AABB so Paste Here centres rotated shapes.
        final b = _bounds(s);
        minX = math.min(minX, b.$1);
        minY = math.min(minY, b.$2);
        maxX = math.max(maxX, b.$3);
        maxY = math.max(maxY, b.$4);
      }
      dx = snap(cx) - (minX + maxX) / 2;
      dy = snap(cy) - (minY + maxY) / 2;
      _pasteGeneration = 0;
    } else {
      _pasteGeneration += 1;
      dx = 0.25 * _pasteGeneration;
      dy = -0.25 * _pasteGeneration;
    }
    _cloneShapesOntoPage(
      _clipboard,
      dx: dx,
      dy: dy,
      connects: _clipboardConnects,
      images: _clipboardImages,
    );
  }

  /// Duplicate the current selection, offset slightly, selecting the copies.
  void duplicateSelection() {
    final page = currentPage;
    if (page == null || _selection.isEmpty) return;
    final roots = _selectionRoots(page, <int>[
      for (final id in _selection)
        if (page.findShapeById(id) case final s?
            when !s.locked && !isOnLockedLayer(id))
          id,
    ]);
    if (roots.isEmpty) return;
    final shapes = <VsdxShape>[
      for (final id in roots) _clipboardRoot(page, id),
    ];
    final subtree = _subtreeIds(roots);
    final connects = <VsdxConnect>[
      for (final c in page.connects)
        if (subtree.contains(c.fromSheetId) && subtree.contains(c.toSheetId)) c,
    ];
    _cloneShapesOntoPage(
      shapes,
      dx: 0.25,
      dy: -0.25,
      connects: connects,
    );
  }

  /// Clone [shapes] onto the current page with fresh ids, reminted image parts,
  /// rewritten `Sheet.n!` formulas, and remapped [connects]. Selects the copies.
  ///
  /// Does **not** auto-contain into nearby groups: an offset duplicate of a
  /// group still overlaps the original AABB, and drop-into would swallow the
  /// copy (draw.io keeps paste/duplicate as page-level unless the user drops).
  void _cloneShapesOntoPage(
    List<VsdxShape> shapes, {
    required double dx,
    required double dy,
    List<VsdxConnect> connects = const <VsdxConnect>[],
    ImageRegistry? images,
  }) {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null || shapes.isEmpty) return;
    var nextDoc = doc;
    // Merge clipboard / system-envelope media before reminting parts so
    // cross-instance paste can resolve ForeignData references.
    final extra = images ?? _clipboardImages;
    for (final img in extra.all) {
      if (nextDoc.images.findByPart(img.partName) == null) {
        nextDoc = nextDoc.copyWith(images: nextDoc.images.withImage(img));
      }
    }
    var next = page;
    final newIds = <int>{};
    final idMap = <int, int>{};

    VsdxShape remintImages(VsdxShape s) {
      final kids = <VsdxShape>[
        for (final c in s.children) remintImages(c),
      ];
      var out = kids.isEmpty && s.children.isEmpty
          ? s
          : s.copyWith(children: kids);
      final part = out.imagePartName;
      if (part == null || !out.hasImage) return out;
      final src = nextDoc.images.findByPart(part);
      if (src == null) return out;
      final dot = part.lastIndexOf('.');
      final ext = dot >= 0 ? part.substring(dot + 1) : 'png';
      final minted = _mintImage(nextDoc, src.bytes, ext);
      nextDoc = nextDoc.copyWith(images: nextDoc.images.withImage(minted));
      return out.copyWith(imagePartName: minted.partName);
    }

    for (final s in shapes) {
      var nextId = next.nextFreeShapeId();
      // Paste / duplicate clones are always unlocked so the user can edit them
      // (draw.io clears lock on the copy; the original stays locked).
      // Remap ids at the original pin, then translate so 1-D Begin/End /
      // waypoints move with the pin (withRemappedIds alone only shifts Pin*).
      final remapped = remintImages(s).withRemappedIds(
        () => nextId++,
        idMap: idMap,
      );
      final cloned = _withTreeUnlocked(
        VsdxPage.translateShape(
          remapped,
          dx,
          dy,
          honourDontMoveChildren: false,
        ),
      );
      next = next.addShape(cloned);
      newIds.add(cloned.id);
    }
    // Re-rewrite Sheet.n! refs now that idMap covers every pasted root
    // (connector cloned before its targets would otherwise keep old XFTRIGGERs).
    if (idMap.isNotEmpty && newIds.isNotEmpty) {
      for (final id in newIds) {
        next = next.updateShapeById(
          id,
          (sh) => VsdxShape.rewriteSheetRefsInTree(sh, idMap),
        );
      }
    }
    if (connects.isNotEmpty) {
      final remapped = <VsdxConnect>[
        for (final c in connects)
          if (idMap.containsKey(c.fromSheetId) &&
              idMap.containsKey(c.toSheetId))
            VsdxConnect(
              fromSheetId: idMap[c.fromSheetId]!,
              fromCell: c.fromCell,
              fromPart: c.fromPart,
              toSheetId: idMap[c.toSheetId]!,
              toCell: c.toCell,
              toPart: c.toPart,
            ),
      ];
      if (remapped.isNotEmpty) {
        next = next.copyWith(connects: <VsdxConnect>[
          ...next.connects,
          ...remapped,
        ]);
      }
    }
    // Align XFTRIGGER with remapped Connect rows (or clear dangling triggers
    // when a connector was pasted without its glue targets).
    final pastedIds = <int>{};
    void collectIds(VsdxShape s) {
      pastedIds.add(s.id);
      for (final c in s.children) {
        collectIds(c);
      }
    }

    for (final id in newIds) {
      final s = next.findShapeById(id);
      if (s != null) collectIds(s);
    }
    if (pastedIds.isNotEmpty) {
      next = next
          .syncGlueTriggers(connectorIds: pastedIds)
          .recalculateFormulas(changedShapeIds: pastedIds)
          .rerouteConnectors(movedShapeIds: pastedIds);
    }
    final undoSel = Set<int>.of(_selection);
    _selection
      ..clear()
      ..addAll(newIds);
    applyEdit(
      nextDoc.replacePage(_currentPageIndex, next),
      undoSelection: undoSel,
    );
  }

  // --- Align / distribute ----------------------------------------------------

  /// Axis-aligned bounding box of [s] in page inches as (left, bottom, right,
  /// top), honouring LocPin, rotation and flip. 1-D includes elbow/curve bends.
  static (double, double, double, double) _bounds(VsdxShape s) {
    final corners = <Offset2D>[];
    if (s.is1D) {
      // Align with [VsdxPage._shapeExtentPoints] / [buildShapeBounds]: expand
      // PolylineTo first, then sample NURBS/Arc/Spline strokes.
      for (final g in s.geometries) {
        if (g.noShow) continue;
        final verts = g.polylineVertices(
          widthInches: s.width,
          heightInches: s.height,
        );
        if (verts != null && verts.length >= 2) {
          for (final p in verts) {
            corners.add(VsdxPage.localToPage(s, p));
          }
          break;
        }
      }
      if (corners.isEmpty) {
        final sampled = ShapePerimeter.sampledPathVertices(s);
        if (sampled != null && sampled.length >= 2) {
          for (final p in sampled) {
            corners.add(VsdxPage.localToPage(s, p));
          }
        }
      }
      if (corners.isEmpty) {
        final ax = s.beginX ?? s.pinX, ay = s.beginY ?? s.pinY;
        final bx = s.endX ?? s.pinX, by = s.endY ?? s.pinY;
        corners.addAll(<Offset2D>[
          Offset2D(ax, ay),
          ...s.waypoints,
          Offset2D(bx, by),
        ]);
      }
    } else {
      corners.addAll(<Offset2D>[
        const Offset2D(0, 0),
        Offset2D(s.width, 0),
        Offset2D(s.width, s.height),
        Offset2D(0, s.height),
      ].map((local) => VsdxPage.localToPage(s, local)));
    }
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in corners) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
    return (minX, minY, maxX, maxY);
  }

  /// Page-space AABB (left, bottom, right, top) for [id], or `null`.
  static (double, double, double, double)? _pageBounds(VsdxPage page, int id) {
    final aabb = page.shapePageAabb(id);
    if (aabb == null) return null;
    return (aabb.left, aabb.bottom, aabb.right, aabb.top);
  }

  void _align(
    Map<int, (double, double)> Function(VsdxPage page, List<int> ids) compute,
  ) {
    final page = currentPage;
    if (page == null) return;
    // Roots only for gap/anchor math — co-selected nested children must not
    // inflate distribute spacing (group AABB already covers them).
    final ids = _selectionRoots(page, <int>[
      for (final id in _selection)
        if (page.findShapeById(id) != null) id,
    ]);
    if (ids.length < 2) return;
    final deltas = compute(page, ids);
    if (deltas.isEmpty) return;
    // Locked shapes still participate as align anchors, but do not move.
    final movable = <int, (double, double)>{
      for (final e in deltas.entries)
        if (page.findShapeById(e.key) case final s?
            when !s.locked &&
                !isOnLockedLayer(e.key) &&
                (e.value.$1 != 0 || e.value.$2 != 0))
          e.key: e.value,
    };
    if (movable.isEmpty) return;
    final movedIds = _subtreeIds(movable.keys);
    updateCurrentPage((p) {
      var next = p;
      movable.forEach((id, d) {
        next = _nudgeShapeOnPage(next, id, d.$1, d.$2);
      });
      return next
          .recalculateFormulas(changedShapeIds: movedIds)
          .rerouteConnectors(movedShapeIds: movedIds);
    });
  }

  /// Align a single selection to the page box (draw.io "to page" when one
  /// shape is selected). Multi-selection keeps relative-to-selection align.
  void _alignToPage(
    (double, double) Function(VsdxPage page, (double, double, double, double) b)
        delta,
  ) {
    final page = currentPage;
    final id = singleSelectedId;
    if (page == null || id == null) return;
    final s = page.findShapeById(id);
    if (s == null || s.locked || isOnLockedLayer(id)) return;
    final b = _pageBounds(page, id);
    if (b == null) return;
    final d = delta(page, b);
    if (d.$1 == 0 && d.$2 == 0) return;
    final movedIds = _subtreeIds(<int>{id});
    updateCurrentPage((p) {
      final next = _nudgeShapeOnPage(p, id, d.$1, d.$2);
      return identical(next, p)
          ? p
          : next
              .recalculateFormulas(changedShapeIds: movedIds)
              .rerouteConnectors(movedShapeIds: movedIds);
    });
  }

  /// Page AABBs for align/distribute, skipping glueable connector hairlines.
  /// Freehand ink keeps a real AABB and participates like 2-D shapes.
  static Map<int, (double, double, double, double)> _alignBounds2D(
    VsdxPage page,
    List<int> ids,
  ) {
    final out = <int, (double, double, double, double)>{};
    for (final id in ids) {
      if (page.findShapeById(id)?.isGlueableConnector == true) continue;
      final bounds = _pageBounds(page, id);
      if (bounds != null) out[id] = bounds;
    }
    return out;
  }

  void alignLeft() {
    if (_selection.length == 1) {
      _alignToPage((_, b) => (0.0 - b.$1, 0.0));
      return;
    }
    _align((page, ids) {
      final bounds = _alignBounds2D(page, ids);
      if (bounds.length < 2) return const {};
      final target = bounds.values.map((b) => b.$1).reduce(math.min);
      return {
        for (final e in bounds.entries) e.key: (target - e.value.$1, 0.0),
      };
    });
  }

  void alignRight() {
    if (_selection.length == 1) {
      _alignToPage((page, b) => (page.widthInches - b.$3, 0.0));
      return;
    }
    _align((page, ids) {
      final bounds = _alignBounds2D(page, ids);
      if (bounds.length < 2) return const {};
      final target = bounds.values.map((b) => b.$3).reduce(math.max);
      return {
        for (final e in bounds.entries) e.key: (target - e.value.$3, 0.0),
      };
    });
  }

  void alignCenterH() {
    if (_selection.length == 1) {
      _alignToPage((page, b) => (page.widthInches / 2 - (b.$1 + b.$3) / 2, 0.0));
      return;
    }
    _align((page, ids) {
      final bounds = _alignBounds2D(page, ids);
      if (bounds.length < 2) return const {};
      final l = bounds.values.map((b) => b.$1).reduce(math.min);
      final r = bounds.values.map((b) => b.$3).reduce(math.max);
      final target = (l + r) / 2;
      return {
        for (final e in bounds.entries)
          e.key: (target - (e.value.$1 + e.value.$3) / 2, 0.0),
      };
    });
  }

  void alignTop() {
    if (_selection.length == 1) {
      _alignToPage((page, b) => (0.0, page.heightInches - b.$4));
      return;
    }
    _align((page, ids) {
      final bounds = _alignBounds2D(page, ids);
      if (bounds.length < 2) return const {};
      final target = bounds.values.map((b) => b.$4).reduce(math.max);
      return {
        for (final e in bounds.entries) e.key: (0.0, target - e.value.$4),
      };
    });
  }

  void alignBottom() {
    if (_selection.length == 1) {
      _alignToPage((_, b) => (0.0, 0.0 - b.$2));
      return;
    }
    _align((page, ids) {
      final bounds = _alignBounds2D(page, ids);
      if (bounds.length < 2) return const {};
      final target = bounds.values.map((b) => b.$2).reduce(math.min);
      return {
        for (final e in bounds.entries) e.key: (0.0, target - e.value.$2),
      };
    });
  }

  void alignMiddle() {
    if (_selection.length == 1) {
      _alignToPage(
        (page, b) => (0.0, page.heightInches / 2 - (b.$2 + b.$4) / 2),
      );
      return;
    }
    _align((page, ids) {
      final bounds = _alignBounds2D(page, ids);
      if (bounds.length < 2) return const {};
      final bot = bounds.values.map((b) => b.$2).reduce(math.min);
      final top = bounds.values.map((b) => b.$4).reduce(math.max);
      final target = (bot + top) / 2;
      return {
        for (final e in bounds.entries)
          e.key: (0.0, target - (e.value.$2 + e.value.$4) / 2),
      };
    });
  }

  /// Equalise gaps between axis-aligned bounds (draw.io Distribute).
  void distributeHorizontally() => _align((page, ids) {
        if (ids.length < 3) return const {};
        final bounds = _alignBounds2D(page, ids);
        if (bounds.length < 3) return const {};
        final sorted = bounds.keys.toList()
          ..sort((a, b) => bounds[a]!.$1.compareTo(bounds[b]!.$1));
        final first = bounds[sorted.first]!;
        final last = bounds[sorted.last]!;
        final totalW = sorted.fold<double>(
          0,
          (sum, id) {
            final b = bounds[id]!;
            return sum + (b.$3 - b.$1);
          },
        );
        final gap = (last.$3 - first.$1 - totalW) / (sorted.length - 1);
        var cursor = first.$1;
        final out = <int, (double, double)>{};
        for (final id in sorted) {
          final b = bounds[id]!;
          final w = b.$3 - b.$1;
          out[id] = (cursor - b.$1, 0.0);
          cursor += w + gap;
        }
        return out;
      });

  /// Equalise gaps between axis-aligned bounds (draw.io Distribute).
  void distributeVertically() => _align((page, ids) {
        if (ids.length < 3) return const {};
        final bounds = _alignBounds2D(page, ids);
        if (bounds.length < 3) return const {};
        final sorted = bounds.keys.toList()
          ..sort((a, b) => bounds[a]!.$2.compareTo(bounds[b]!.$2));
        final first = bounds[sorted.first]!;
        final last = bounds[sorted.last]!;
        final totalH = sorted.fold<double>(
          0,
          (sum, id) {
            final b = bounds[id]!;
            return sum + (b.$4 - b.$2);
          },
        );
        final gap = (last.$4 - first.$2 - totalH) / (sorted.length - 1);
        var cursor = first.$2;
        final out = <int, (double, double)>{};
        for (final id in sorted) {
          final b = bounds[id]!;
          final h = b.$4 - b.$2;
          out[id] = (0.0, cursor - b.$2);
          cursor += h + gap;
        }
        return out;
      });

  /// Exactly two unlocked 2-D selection roots can trade page-space centres.
  bool get canSwapSelection {
    final page = currentPage;
    if (page == null) return false;
    final roots = _selectionRoots(page, _selection.toList());
    if (roots.length != 2) return false;
    return roots.every((id) {
      final s = page.findShapeById(id);
      return s != null &&
          !s.is1D &&
          !s.locked &&
          !isOnLockedLayer(id);
    });
  }

  /// Exchange the page-space positions of two shapes (draw.io Arrange → Swap).
  ///
  /// Page centres are used so differently-sized and nested shapes swap
  /// intuitively while preserving their own size, rotation and parent.
  void swapSelectionPositions() {
    if (!canSwapSelection) return;
    _align((page, ids) {
      if (ids.length != 2) return const {};
      final a = _pageBounds(page, ids[0]);
      final b = _pageBounds(page, ids[1]);
      if (a == null || b == null) return const {};
      final ac = ((a.$1 + a.$3) / 2, (a.$2 + a.$4) / 2);
      final bc = ((b.$1 + b.$3) / 2, (b.$2 + b.$4) / 2);
      return <int, (double, double)>{
        ids[0]: (bc.$1 - ac.$1, bc.$2 - ac.$2),
        ids[1]: (ac.$1 - bc.$1, ac.$2 - bc.$2),
      };
    });
  }

  // Session-local draw.io Copy Size / Paste Size clipboard.
  ({double width, double height})? _sizeClipboard;

  bool get canCopySize {
    final id = singleSelectedId;
    final s = id == null ? null : currentPage?.findShapeById(id);
    return s != null && !s.is1D && s.width > 0 && s.height > 0;
  }

  bool get canPasteSize {
    if (_sizeClipboard == null) return false;
    final page = currentPage;
    if (page == null) return false;
    return _selection.any((id) {
      final s = page.findShapeById(id);
      return s != null &&
          !s.is1D &&
          !s.locked &&
          !isOnLockedLayer(id);
    });
  }

  /// Capture the selected shape's dimensions without changing the document.
  void copySelectionSize() {
    if (!canCopySize) return;
    final s = currentPage!.findShapeById(singleSelectedId!)!;
    _sizeClipboard = (width: s.width, height: s.height);
    notifyListeners();
  }

  /// Resize all unlocked 2-D selection roots to the copied dimensions.
  void pasteSelectionSize() {
    final clip = _sizeClipboard;
    if (clip == null || !canPasteSize) return;
    _resizeSelectionTo(
      targetWidth: clip.width,
      targetHeight: clip.height,
      width: true,
      height: true,
    );
  }

  bool get canAutosizeSelection {
    final page = currentPage;
    if (page == null) return false;
    return _selection.any((id) {
      final s = page.findShapeById(id);
      return s != null &&
          !s.is1D &&
          s.children.isEmpty &&
          !s.locked &&
          !isOnLockedLayer(id) &&
          _shapeLabel(s).trim().isNotEmpty;
    });
  }

  /// Fit each selected atomic shape's height to its wrapped text label.
  ///
  /// This mirrors draw.io Arrange → Autosize: width stays fixed, proportion
  /// constraints are ignored, and every eligible shape is resized in one undo
  /// step while its page-space top-left remains anchored.
  void autosizeSelection() {
    final page = currentPage;
    if (page == null) return;
    final targets = <({int id, double height})>[];
    for (final id in _selectionRoots(page, _selection.toList())) {
      final s = page.findShapeById(id);
      if (s == null ||
          s.is1D ||
          s.children.isNotEmpty ||
          s.locked ||
          isOnLockedLayer(id) ||
          _shapeLabel(s).trim().isEmpty) {
        continue;
      }
      final height = _autosizeHeight(s);
      if ((height - s.height).abs() > 1e-6) {
        targets.add((id: id, height: height));
      }
    }
    if (targets.isEmpty) return;
    beginTransaction();
    for (final target in targets) {
      final s = currentPage?.findShapeById(target.id);
      if (s == null) continue;
      resizeShape(
        target.id,
        pinX: s.pinX,
        pinY: s.pinY,
        width: s.width,
        height: target.height,
        transient: true,
        preservePageTopLeft: true,
      );
    }
    commitTransaction();
  }

  /// Measure a shape label in a stable 96px-per-inch layout frame.
  static double _autosizeHeight(VsdxShape s) {
    const dpi = 96.0;
    final block = s.richText.textBlock;
    final maxWidthInches = math.max(
      0.05,
      (block.widthInches ?? s.width) -
          block.marginLeftInches -
          block.marginRightInches,
    );
    TextStyle runStyle(VsdxTextRun run) {
      final c = run.charStyle;
      final p = run.paraStyle;
      final size = math.max(c.fontSizeInches, 0.04) * dpi;
      final height = p.lineSpacingAbsoluteInches > 0
          ? p.lineSpacingAbsoluteInches * dpi / size
          : (p.lineSpacing > 0 ? p.lineSpacing : 1.0);
      return TextStyle(
        fontFamily: c.fontFamily,
        fontSize: size,
        fontWeight: c.style.bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: c.style.italic ? FontStyle.italic : FontStyle.normal,
        height: height,
        letterSpacing: c.letterSpacingInches * dpi,
        decoration: TextDecoration.combine(<TextDecoration>[
          if (c.underline || c.doubleUnderline) TextDecoration.underline,
          if (c.strikethrough || c.doubleStrikethrough)
            TextDecoration.lineThrough,
          if (c.overline) TextDecoration.overline,
        ]),
      );
    }

    final spans = s.richText.isEmpty
        ? <InlineSpan>[
            TextSpan(
              text: s.text ?? '',
              style: const TextStyle(fontSize: 12.0 / 72.0 * dpi),
            ),
          ]
        : <InlineSpan>[
            for (final run in s.richText.runs)
              TextSpan(text: run.text, style: runStyle(run)),
          ];
    final tp = TextPainter(
      text: TextSpan(children: spans),
      textDirection: TextDirection.ltr,
      maxLines: null,
    );
    if (block.textDirection == 1) {
      tp.layout();
    } else {
      tp.layout(maxWidth: maxWidthInches * dpi);
    }
    final contentHeight =
        (block.textDirection == 1 ? tp.width : tp.height) / dpi;
    return math.max(
      0.05,
      contentHeight +
          block.marginTopInches +
          block.marginBottomInches +
          0.02,
    );
  }

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
    // Prefer a 2-D reference so a leading connector does not resize boxes
    // to a hairline Begin/End span.
    final ref = _firstSelected2D ?? _firstSelected;
    final page0 = currentPage;
    if (ref == null || ref.is1D || _selection.length < 2 || page0 == null) {
      return;
    }
    final tw = ref.width;
    final th = ref.height;
    if ((width && tw <= 0) || (height && th <= 0)) return;
    _resizeSelectionTo(
      targetWidth: tw,
      targetHeight: th,
      width: width,
      height: height,
      skipId: ref.id,
    );
  }

  void _resizeSelectionTo({
    required double targetWidth,
    required double targetHeight,
    required bool width,
    required bool height,
    int? skipId,
  }) {
    final page0 = currentPage;
    if (page0 == null ||
        (width && targetWidth <= 0) ||
        (height && targetHeight <= 0)) {
      return;
    }
    // Resize selection roots only (group+child co-selection must not double-
    // apply width/height to the nested child).
    final roots = _selectionRoots(page0, <int>[
      for (final id in _selection)
        if (page0.findShapeById(id) case final s?
            when !s.locked && !isOnLockedLayer(id) && !s.is1D)
          id,
    ]);
    if (roots.isEmpty) return;
    final movedIds = _subtreeIds(roots);
    updateCurrentPage((page) {
      var next = page;
      var changed = false;
      for (final id in roots) {
        if (id == skipId) continue;
        final s = next.findShapeById(id);
        if (s == null || s.locked || isOnLockedLayer(id) || s.is1D) {
          continue;
        }
        final nw = width ? targetWidth : s.width;
        final nh = height ? targetHeight : s.height;
        if ((nw - s.width).abs() < 1e-9 && (nh - s.height).abs() < 1e-9) {
          continue;
        }
        // Keep the page-space AABB top-left stable (draw.io Same Size),
        // including under rotated ancestors (page Δ → parent-local).
        final beforeAabb = next.shapePageAabb(id);
        next = next.updateShapeById(
          id,
          (sh) {
            final sx = sh.width == 0 ? 1.0 : nw / sh.width;
            final sy = sh.height == 0 ? 1.0 : nh / sh.height;
            final resized = sh.resizeTo(
              pinX: sh.pinX,
              pinY: sh.pinY,
              width: nw,
              height: nh,
            );
            // Match [resizeShape]: groups scale all children; pools scale
            // non-lane content here (lanes reflow via layoutLanes below).
            if (SwimlaneOps.isPool(sh)) {
              if ((sx - 1).abs() < 1e-12 && (sy - 1).abs() < 1e-12) {
                return resized;
              }
              return resized.copyWith(
                children: <VsdxShape>[
                  ...SwimlaneOps.lanesOf(sh),
                  for (final c in SwimlaneOps.nonLaneChildren(sh))
                    VsdxPage.scaleChildInFrame(
                      c,
                      sx,
                      sy,
                      sh.effectiveLocPinX,
                      sh.effectiveLocPinY,
                      resized.effectiveLocPinX,
                      resized.effectiveLocPinY,
                    ),
                ],
              );
            }
            if (sh.shapeKind != VsdxShapeKind.group ||
                sh.children.isEmpty ||
                ((sx - 1).abs() < 1e-12 && (sy - 1).abs() < 1e-12)) {
              return resized;
            }
            final oldOx = sh.effectiveLocPinX;
            final oldOy = sh.effectiveLocPinY;
            final newOx = resized.effectiveLocPinX;
            final newOy = resized.effectiveLocPinY;
            return resized.copyWith(
              children: <VsdxShape>[
                for (final c in sh.children)
                  _scaleGroupChild(c, sx, sy, oldOx, oldOy, newOx, newOy),
              ],
            );
          },
        );
        if (beforeAabb != null) {
          final afterAabb = next.shapePageAabb(id);
          if (afterAabb != null) {
            final dx = beforeAabb.left - afterAabb.left;
            final dy = beforeAabb.top - afterAabb.top;
            if (dx != 0 || dy != 0) {
              next = _nudgeShapeOnPage(next, id, dx, dy);
            }
          }
        }
        final host = next.findShapeById(id);
        if (host != null) {
          if (SwimlaneOps.isPool(host)) {
            next = next.updateShapeById(id, SwimlaneOps.layoutLanes);
          } else if (TableOps.isTable(host)) {
            next = next.updateShapeById(id, TableOps.layoutCells);
          }
        }
        changed = true;
      }
      return changed
          ? next
              .recalculateFormulas(changedShapeIds: movedIds)
              .rerouteConnectors(movedShapeIds: movedIds)
          : page;
    });
  }

  void bringSelectionToFront() {
    if (_selection.isEmpty) return;
    updateCurrentPage((page) => _reorderSelectionAmongSiblings(
          page,
          toFront: true,
        ));
  }

  void sendSelectionToBack() {
    if (_selection.isEmpty) return;
    updateCurrentPage((page) => _reorderSelectionAmongSiblings(
          page,
          toFront: false,
        ));
  }

  /// Lift / sink the selection as blocks within each sibling list (page root
  /// or a group's children), preserving relative order inside the selection.
  VsdxPage _reorderSelectionAmongSiblings(
    VsdxPage page, {
    required bool toFront,
  }) {
    final byParent = <int?, List<int>>{};
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s == null || s.locked || isOnLockedLayer(id)) continue;
      final parent = page.findParentId(id);
      (byParent[parent] ??= <int>[]).add(id);
    }
    var next = page;
    for (final entry in byParent.entries) {
      final parentId = entry.key;
      final ids = entry.value.toSet();
      if (parentId == null) {
        final selected = <VsdxShape>[
          for (final s in next.shapes)
            if (ids.contains(s.id)) s,
        ];
        if (selected.isEmpty) continue;
        next = next.copyWith(
          shapes: toFront
              ? <VsdxShape>[
                  for (final s in next.shapes)
                    if (!ids.contains(s.id)) s,
                  ...selected,
                ]
              : <VsdxShape>[
                  ...selected,
                  for (final s in next.shapes)
                    if (!ids.contains(s.id)) s,
                ],
        );
      } else {
        final parent = next.findShapeById(parentId);
        if (parent == null) continue;
        final selected = <VsdxShape>[
          for (final s in parent.children)
            if (ids.contains(s.id)) s,
        ];
        if (selected.isEmpty) continue;
        next = next.updateShapeById(
          parentId,
          (p) => p.copyWith(
            children: toFront
                ? <VsdxShape>[
                    for (final s in p.children)
                      if (!ids.contains(s.id)) s,
                    ...selected,
                  ]
                : <VsdxShape>[
                    ...selected,
                    for (final s in p.children)
                      if (!ids.contains(s.id)) s,
                  ],
          ),
        );
      }
    }
    return next;
  }

  /// Move the selection one step forward in z-order (drawio "Bring Forward").
  void bringSelectionForward() {
    if (_selection.isEmpty) return;
    updateCurrentPage((page) {
      var next = page;
      // Process front-to-back within each sibling list.
      final ids = <int>[
        for (final id in _selection)
          if (page.findShapeById(id) case final s?
              when !s.locked && !isOnLockedLayer(id))
            id,
      ];
      if (ids.isEmpty) return page;
      ids.sort((a, b) {
        final pa = page.findParentId(a);
        final pb = page.findParentId(b);
        if (pa != pb) return (pa ?? -1).compareTo(pb ?? -1);
        final list = pa == null
            ? page.shapes
            : page.findShapeById(pa)?.children ?? const <VsdxShape>[];
        return list.indexWhere((s) => s.id == b).compareTo(
              list.indexWhere((s) => s.id == a),
            );
      });
      for (final id in ids) {
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
      final ids = <int>[
        for (final id in _selection)
          if (page.findShapeById(id) case final s?
              when !s.locked && !isOnLockedLayer(id))
            id,
      ];
      if (ids.isEmpty) return page;
      ids.sort((a, b) {
        final pa = page.findParentId(a);
        final pb = page.findParentId(b);
        if (pa != pb) return (pa ?? -1).compareTo(pb ?? -1);
        final list = pa == null
            ? page.shapes
            : page.findShapeById(pa)?.children ?? const <VsdxShape>[];
        return list.indexWhere((s) => s.id == a).compareTo(
              list.indexWhere((s) => s.id == b),
            );
      });
      for (final id in ids) {
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
  /// `x`/`y` are the top-left of the **page AABB** in inches from the page's
  /// top-left (Y-down); `w`/`h` remain the shape's local width/height;
  /// `angleDeg` is the **page** heading in Visio CCW degrees (matches the
  /// rotate handle under nested / rotated parents).
  ({double x, double y, double w, double h, double angleDeg})? get selectedGeometry {
    final s = singleSelected;
    final page = currentPage;
    if (s == null || page == null) return null;
    final angleDeg = page.shapePageAngle(s.id) * 180 / math.pi;
    final aabb = page.shapePageAabb(s.id);
    if (aabb == null) {
      return (
        x: s.pinX - s.width / 2,
        y: page.heightInches - (s.pinY + s.height / 2),
        w: s.width,
        h: s.height,
        angleDeg: angleDeg,
      );
    }
    return (
      x: aabb.left,
      y: page.heightInches - aabb.top,
      w: s.width,
      h: s.height,
      angleDeg: angleDeg,
    );
  }

  /// Move the single selection so its page-AABB left edge sits at [x] inches.
  void setSelectedX(double x) {
    final s = singleSelected;
    final page = currentPage;
    if (s == null || page == null) return;
    if (s.locked || isOnLockedLayer(s.id)) return;
    final aabb = page.shapePageAabb(s.id);
    if (aabb == null) return;
    final dx = x - aabb.left;
    if (dx.abs() < 1e-12) return;
    moveSelectionBy(dx, 0);
  }

  /// Move the single selection so its page-AABB top edge sits at [y] inches
  /// from the page top (Y-down).
  void setSelectedY(double y) {
    final s = singleSelected;
    final page = currentPage;
    if (s == null || page == null) return;
    if (s.locked || isOnLockedLayer(s.id)) return;
    final aabb = page.shapePageAabb(s.id);
    if (aabb == null) return;
    final targetTop = page.heightInches - y;
    final dy = targetTop - aabb.top;
    if (dy.abs() < 1e-12) return;
    moveSelectionBy(0, dy);
  }

  /// Resize the single selection to [w] inches wide, keeping its page-AABB
  /// left edge (matches [selectedGeometry] / Arrange panel).
  void setSelectedWidth(double w) {
    final s = singleSelected;
    final page = currentPage;
    if (s == null || page == null || w <= 0 || s.locked || isOnLockedLayer(s.id)) {
      return;
    }
    final before = page.shapePageAabb(s.id);
    beginTransaction();
    resizeShape(
      s.id,
      pinX: s.pinX,
      pinY: s.pinY,
      width: w,
      height: s.height,
      transient: true,
    );
    if (before != null) {
      final after = currentPage?.shapePageAabb(s.id);
      if (after != null) {
        final dx = before.left - after.left;
        final dy = before.top - after.top;
        if (dx != 0 || dy != 0) {
          moveSelectionBy(dx, dy, transient: true);
        }
      }
    }
    commitTransaction();
  }

  /// Resize the single selection to [h] inches tall, keeping its page-AABB
  /// top edge (matches [selectedGeometry] / Arrange panel).
  void setSelectedHeight(double h) {
    final s = singleSelected;
    final page = currentPage;
    if (s == null || page == null || h <= 0 || s.locked || isOnLockedLayer(s.id)) {
      return;
    }
    final before = page.shapePageAabb(s.id);
    beginTransaction();
    resizeShape(
      s.id,
      pinX: s.pinX,
      pinY: s.pinY,
      width: s.width,
      height: h,
      transient: true,
    );
    if (before != null) {
      final after = currentPage?.shapePageAabb(s.id);
      if (after != null) {
        final dx = before.left - after.left;
        final dy = before.top - after.top;
        if (dx != 0 || dy != 0) {
          moveSelectionBy(dx, dy, transient: true);
        }
      }
    }
    commitTransaction();
  }

  /// Set the single selection's **page** heading from a value in degrees
  /// (Arrange panel). Nested shapes convert page→parent-local like the canvas
  /// rotate handle. [VsdxShape.flipY] adds π to the page heading of local +Y,
  /// so the stored [VsdxShape.angleRad] is compensated accordingly.
  ///
  /// 1-D connectors rewrite Begin/End geometry (Angle stays 0).
  void setSelectedAngleDegrees(double deg) {
    final s = singleSelected;
    final page = currentPage;
    if (s == null || page == null || s.locked || isOnLockedLayer(s.id)) {
      return;
    }
    final pageAngle = deg * math.pi / 180;
    final parentId = page.findParentId(s.id);
    double localAngle;
    if (parentId == null) {
      localAngle = pageAngle;
    } else {
      final pin = page.shapePinPage(s.id);
      final tipPage = Offset2D(
        pin.x - math.sin(pageAngle),
        pin.y + math.cos(pageAngle),
      );
      final tipLocal = page.pageToLocalDeep(parentId, tipPage);
      final pinLocal = page.pageToLocalDeep(parentId, pin);
      localAngle = math.atan2(
        -(tipLocal.x - pinLocal.x),
        tipLocal.y - pinLocal.y,
      );
    }
    // flipY reflects local +Y → page −Y, which reads as +π in shapePageAngle.
    if (s.flipY) localAngle -= math.pi;
    rotateShape(s.id, localAngle);
  }

  /// Rotate every selected shape 90° about its own pin (drawio Ctrl+R). Pass
  /// `clockwise: false` to turn the other way.
  void rotateSelection90({bool clockwise = true}) {
    if (_selection.isEmpty) return;
    final page0 = currentPage;
    if (page0 == null) return;
    // Visio angles are CCW-positive, so a clockwise turn subtracts 90°.
    final delta = (clockwise ? -1 : 1) * math.pi / 2;
    final roots = _selectionRoots(page0, <int>[
      for (final id in _selection)
        if (page0.findShapeById(id) case final s?
            when !s.locked && !isOnLockedLayer(id))
          id,
    ]);
    if (roots.isEmpty) return;
    final movedIds = _subtreeIds(roots);
    // Connectors we bake geometrically must not be re-glued by reroute
    // (that would snap Begin/End back onto targets and undo the turn).
    final bakedConnectors = <int>{
      for (final id in roots)
        if (page0.findShapeById(id)?.isGlueableConnector == true) id,
    };
    updateCurrentPage((page) {
      var next = page;
      var rotated = false;
      for (final id in roots) {
        final s = next.findShapeById(id);
        if (s == null) continue;
        if (s.isGlueableConnector) {
          next = next.updateShapeById(
            id,
            (sh) => _rotate1DAboutPin(next, sh, delta),
          );
        } else {
          final parentId = next.findParentId(id);
          if (parentId == null) {
            next = next.updateShapeById(
              id,
              (sh) => _withLiteralAngle(sh, sh.angleRad + delta),
            );
          } else {
            // Page-space delta then parent-local writeback so a flipped
            // ancestor does not reverse clockwise / CCW.
            final pageAngle = next.shapePageAngle(id) + delta;
            final pin = next.shapePinPage(id);
            final tipPage = Offset2D(
              pin.x - math.sin(pageAngle),
              pin.y + math.cos(pageAngle),
            );
            final tipLocal = next.pageToLocalDeep(parentId, tipPage);
            final pinLocal = next.pageToLocalDeep(parentId, pin);
            var localAngle = math.atan2(
              -(tipLocal.x - pinLocal.x),
              tipLocal.y - pinLocal.y,
            );
            // Match [setSelectedAngleDegrees] / canvas rotate: flipY adds π
            // to the page heading of local +Y.
            if (s.flipY) localAngle -= math.pi;
            next = next.updateShapeById(
              id,
              (sh) => _withLiteralAngle(sh, localAngle),
            );
          }
        }
        rotated = true;
      }
      return rotated
          ? next
              .recalculateFormulas(changedShapeIds: movedIds)
              .rerouteConnectors(
                movedShapeIds: <int>{
                  for (final id in movedIds)
                    if (!bakedConnectors.contains(id)) id,
                },
              )
          : page;
    });
  }

  /// Mirror the selected shapes horizontally (`FlipX`). Locked shapes skip.
  /// Reroutes glued connectors so endpoints follow mirrored connection points.
  void flipHorizontal() => _flipSelection(horizontal: true);

  /// Mirror the selected shapes vertically (`FlipY`). Locked shapes skip.
  /// Reroutes glued connectors so endpoints follow mirrored connection points.
  void flipVertical() => _flipSelection(horizontal: false);

  void _flipSelection({required bool horizontal}) {
    if (_selection.isEmpty) return;
    final page0 = currentPage;
    if (page0 == null) return;
    final roots = _selectionRoots(page0, <int>[
      for (final id in _selection)
        if (page0.findShapeById(id) case final s?
            when !s.locked && !isOnLockedLayer(id))
          id,
    ]);
    if (roots.isEmpty) return;
    final movedIds = _subtreeIds(roots);
    final bakedConnectors = <int>{
      for (final id in roots)
        if (page0.findShapeById(id)?.isGlueableConnector == true) id,
    };
    updateCurrentPage((page) {
      var next = page;
      var flipped = false;
      for (final id in roots) {
        final s = next.findShapeById(id);
        if (s == null) continue;
        if (s.isGlueableConnector) {
          next = next.updateShapeById(
            id,
            (sh) => _mirror1DAboutPin(next, sh, horizontal: horizontal),
          );
        } else {
          // Boxes and freehand ink: flip flags (AABB-local geometry).
          // Ink also refreshes Begin/End so exported endpoints match paint.
          next = next.updateShapeById(
            id,
            (sh) => (horizontal
                    ? sh.copyWith(flipX: !sh.flipX)
                    : sh.copyWith(flipY: !sh.flipY))
                .syncInkEndpoints(),
          );
        }
        flipped = true;
      }
      return flipped
          ? next
              .recalculateFormulas(changedShapeIds: movedIds)
              .rerouteConnectors(
                movedShapeIds: <int>{
                  for (final id in movedIds)
                    if (!bakedConnectors.contains(id)) id,
                },
              )
          : page;
    });
  }

  /// Control polyline of [conn] in **page** inches (waypoints / elbow).
  static List<Offset2D> _connectorControlPage(VsdxPage page, VsdxShape conn) {
    final route = VsdxPage.connectorRoute(conn);
    final parentId = page.findParentId(conn.id);
    if (parentId == null) return route;
    return <Offset2D>[
      for (final p in route) page.localToPageDeep(parentId, p),
    ];
  }

  /// Page-inch pin of [s] using [s]'s own pin (not a stale page lookup).
  static Offset2D _pinPageOf(VsdxPage page, VsdxShape s) {
    final parentId = page.findParentId(s.id);
    final local = Offset2D(s.pinX, s.pinY);
    if (parentId == null) return local;
    return page.localToPageDeep(parentId, local);
  }

  /// Write a page-space control polyline back onto [s] (parent-local reshape).
  static VsdxShape _applyPageControlTo1D(
    VsdxPage page,
    VsdxShape s,
    List<Offset2D> pagePoly,
  ) {
    if (pagePoly.length < 2) return s;
    final parentId = page.findParentId(s.id);
    final local = parentId == null
        ? pagePoly
        : <Offset2D>[
            for (final p in pagePoly) page.pageToLocalDeep(parentId, p),
          ];
    final wps = local.length > 2
        ? local.sublist(1, local.length - 1)
        : const <Offset2D>[];
    final geometry = s.curved
        ? VsdxPage.curveThrough(local)
        : s.rounded
            ? VsdxPage.roundCorners(local)
            : local;
    return s.copyWith(waypoints: wps).reshapeAsPolyline(geometry);
  }

  /// Fold residual Angle/Flip into Begin/End geometry (Visio 1-D convention).
  static VsdxShape _bake1DXformIfNeeded(VsdxPage page, VsdxShape s) {
    if (!s.isGlueableConnector ||
        (s.angleRad == 0 && !s.flipX && !s.flipY)) {
      return s;
    }
    final drawn = page.drawnConnectorPagePolyline(s);
    if (drawn.length < 2) {
      return s.copyWith(angleRad: 0, flipX: false, flipY: false);
    }
    final parentId = page.findParentId(s.id);
    final local = parentId == null
        ? drawn
        : <Offset2D>[
            for (final p in drawn) page.pageToLocalDeep(parentId, p),
          ];
    // Visual path is already sampled; keep it sharp so we do not re-spline.
    return s
        .copyWith(
          angleRad: 0,
          flipX: false,
          flipY: false,
          curved: false,
          rounded: false,
          waypoints: local.length > 2
              ? local.sublist(1, local.length - 1)
              : const <Offset2D>[],
        )
        .reshapeAsPolyline(local);
  }

  /// Rotate a 1-D connector's control polyline about its page pin (CCW).
  static VsdxShape _rotate1DAboutPin(
    VsdxPage page,
    VsdxShape s,
    double deltaRad,
  ) {
    if (!s.isGlueableConnector) return s;
    final base = _bake1DXformIfNeeded(page, s);
    if (deltaRad.abs() < 1e-12) return base;
    final pin = _pinPageOf(page, base);
    final cosA = math.cos(deltaRad);
    final sinA = math.sin(deltaRad);
    final route = _connectorControlPage(page, base);
    final rotated = <Offset2D>[
      for (final p in route)
        Offset2D(
          pin.x + (p.x - pin.x) * cosA - (p.y - pin.y) * sinA,
          pin.y + (p.x - pin.x) * sinA + (p.y - pin.y) * cosA,
        ),
    ];
    return _applyPageControlTo1D(page, base, rotated);
  }

  /// Mirror a 1-D connector's control polyline about its page pin.
  static VsdxShape _mirror1DAboutPin(
    VsdxPage page,
    VsdxShape s, {
    required bool horizontal,
  }) {
    if (!s.isGlueableConnector) return s;
    final base = _bake1DXformIfNeeded(page, s);
    final pin = _pinPageOf(page, base);
    final route = _connectorControlPage(page, base);
    final mirrored = <Offset2D>[
      for (final p in route)
        horizontal
            ? Offset2D(2 * pin.x - p.x, p.y)
            : Offset2D(p.x, 2 * pin.y - p.y),
    ];
    return _applyPageControlTo1D(page, base, mirrored);
  }

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
  ///
  /// Prefers Visio `Line.Rounding` (filleted polyline). Legacy factory
  /// rounded-rects that baked corners into `EllipticalArcTo` still report the
  /// arc inset so the inspector stays truthful until the next edit.
  double? get selectedCornerRadius {
    final s = singleSelected;
    if (s == null || !_isRectangleLike(s)) return null;
    final g = s.geometries.first;
    if (g.commands.any((c) => c is EllipticalArcTo)) {
      final first = g.commands.first;
      return first is MoveTo ? first.x : 0;
    }
    return s.line.roundingInches;
  }

  /// Round the single (rectangular) selection's corners to [radiusInches]
  /// (0 = square). Writes Visio `Rounding` so Canvas/SVG/`VsdxWriter` share one
  /// semantic; flattens any prior arc-baked corners back to a sharp rect.
  void setCornerRadius(double radiusInches, {bool transient = false}) {
    final s = singleSelected;
    if (s == null || !_isRectangleLike(s)) return;
    if (s.locked || isOnLockedLayer(s.id)) return;
    final r = radiusInches.clamp(0.0, math.min(s.width, s.height) / 2);
    final movedIds = _subtreeIds(<int>{s.id});
    updateCurrentPage(
      (page) => page
          .updateShapeById(
            s.id,
            (sh) {
              var next = sh;
              final hasArcCorners =
                  sh.geometries.first.commands.any((c) => c is EllipticalArcTo);
              if (hasArcCorners) {
                // One semantic: sharp polyline + Rounding (not EllipticalArcTo).
                var geos = <VsdxGeometry>[
                  VsdxShapeFactory.roundedRectGeometry(sh.width, sh.height, 0),
                ];
                geos = syncGeometryNoFill(geos, hollow: sh.fill.pattern == 0);
                geos = syncGeometryNoLine(geos, hollow: !sh.line.hasLine);
                next = next.copyWith(geometries: geos);
              }
              return next.copyWith(
                line: next.line.copyWith(roundingInches: r),
              );
            },
          )
          .recalculateFormulas(changedShapeIds: movedIds)
          .rerouteConnectors(movedShapeIds: movedIds),
      transient: transient,
    );
  }

  void _updateSelectedShapes(
    VsdxShape Function(VsdxShape) update, {
    bool transient = false,
    bool rememberStyle = false,
    bool skipLocked = true,
  }) {
    if (_selection.isEmpty) return;
    var didChange = false;
    updateCurrentPage((page) {
      var next = page;
      var changed = false;
      for (final id in _selection) {
        final s = next.findShapeById(id) ?? page.findShapeById(id);
        if (s == null) continue;
        if (skipLocked && (s.locked || isOnLockedLayer(id))) continue;
        final updated = update(s);
        if (identical(updated, s)) continue;
        next = next.updateShapeById(id, (_) => updated);
        changed = true;
      }
      didChange = changed;
      return changed ? next : page;
    }, transient: transient);
    if (rememberStyle && didChange) _rememberStyle();
  }

  /// Remember the first selection's fill / line so new shapes inherit it
  /// (drawio's `currentVertexStyle`). Prefers a 2-D shape so Soft Edges from a
  /// box are not skipped when a connector leads the selection.
  void _rememberStyle() {
    final s = _firstSelected2D ?? _firstSelected;
    if (s == null) return;
    _memoFill = s.is1D ? null : s.fill;
    final line = s.line;
    _memoLine = s.is1D && line.softEdgesInches > 0
        ? line.copyWith(softEdgesInches: 0)
        : line;
  }

  /// Use the selected shape or connector's appearance for newly created
  /// elements (draw.io Cmd/Ctrl+Shift+D, "Set as Default Style").
  void setSelectionAsDefaultStyle() {
    if (_selection.isEmpty) return;
    _rememberStyle();
    notifyListeners();
  }

  /// Restore the built-in white-fill / black-line creation style.
  ///
  /// This is session state rather than a document edit, so it does not dirty
  /// the file or create an undo entry (draw.io Cmd/Ctrl+Shift+R with no
  /// selection).
  void clearDefaultStyle() {
    if (_memoFill == null && _memoLine == null) return;
    _memoFill = null;
    _memoLine = null;
    notifyListeners();
  }

  /// Apply the remembered style to a freshly-created shape. Lines/connectors
  /// take only the stroke (never a fill / Soft Edges).
  VsdxShape _withMemoStyle(VsdxShape s, {required bool includeFill}) {
    var r = s;
    if (includeFill && _memoFill != null) r = r.copyWith(fill: _memoFill);
    if (_memoLine != null) {
      // Arrowheads belong on 1-D connectors. A memo line remembered from a
      // connector must not stamp BeginArrow/EndArrow onto boxes/ellipses —
      // otherwise the export shows stray arrowheads in 万兴图示 on vertices.
      // Soft Edges are a 2-D fill-edge effect — never seed them onto 1-D.
      var line = _memoLine!;
      if (!s.is1D && (line.beginArrow != 0 || line.endArrow != 0)) {
        line = line.copyWith(beginArrow: 0, endArrow: 0);
      }
      if (s.is1D && line.softEdgesInches > 0) {
        line = line.copyWith(softEdgesInches: 0);
      }
      // "No line" on a box must not birth invisible connectors / freehands.
      if (s.is1D && line.pattern == 0) {
        line = line.copyWith(pattern: 1);
      }
      r = r.copyWith(line: line);
    }
    // Match pasteStyle / setNoFill: keep Geometry NoFill/NoLine in sync so
    // Edraw does not revive a fill when FillPattern=0 but NoFill=0.
    var geos = r.geometries;
    if (includeFill && _memoFill != null) {
      geos = syncGeometryNoFill(geos, hollow: r.fill.pattern == 0);
    }
    if (_memoLine != null) {
      geos = syncGeometryNoLine(geos, hollow: r.line.pattern == 0);
    }
    if (!identical(geos, r.geometries)) {
      r = r.copyWith(geometries: geos);
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

  /// First selected 2-D shape — used by fill / effect inspectors so a leading
  /// connector in a mixed selection does not hide box styles.
  VsdxShape? get _firstSelected2D {
    final page = currentPage;
    if (page == null) return null;
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null && !s.is1D) return s;
    }
    return null;
  }

  /// Clear [locked] on [s] and every descendant (paste / duplicate clones).
  static VsdxShape _withTreeUnlocked(VsdxShape s) {
    final kids = s.children;
    final unlockedKids = kids.isEmpty
        ? kids
        : <VsdxShape>[for (final c in kids) _withTreeUnlocked(c)];
    if (!s.locked && identical(unlockedKids, kids)) return s;
    return s.copyWith(locked: false, children: unlockedKids);
  }

  VsdxFill? get selectedFill => (_firstSelected2D ?? _firstSelected)?.fill;
  VsdxLine? get selectedLine => _firstSelected?.line;

  void setFillColor(VsdxColor color) => _updateSelectedShapes(
        (s) {
          if (s.is1D) return s;
          return s.copyWith(
            fill: s.fill.withSolidForeground(color),
            geometries: syncGeometryNoFill(s.geometries, hollow: false),
          );
        },
        rememberStyle: true,
      );

  /// Bind selected shapes' fill to a document theme colour slot (draw.io
  /// theme swatch). Installs the Office palette when the document has none.
  void setFillThemeSlot(int slot) {
    _applyThemeSlotToSelection(
      slot,
      (s) {
        if (s.is1D) return s;
        return s.copyWith(
          fill: s.fill.withThemeForeground(slot),
          geometries: syncGeometryNoFill(s.geometries, hollow: false),
        );
      },
    );
  }

  void setNoFill() => _updateSelectedShapes(
        (s) {
          if (s.is1D) return s;
          // Clear theme slots too — otherwise a later hatch can revive a stale
          // FillBkgnd AccentColor (same hygiene as [setFillPattern(0)]).
          return s.copyWith(
            fill: s.fill.copyWith(
              pattern: 0,
              gradient: null,
              clearThemeForegroundIndex: true,
              clearThemeBackgroundIndex: true,
            ),
            geometries: syncGeometryNoFill(s.geometries, hollow: true),
          );
        },
        rememberStyle: true,
      );

  /// Set or clear the selection's fill gradient (draw.io Format → Gradient).
  /// `null` removes the gradient and leaves the solid fill colour.
  void setFillGradient(VsdxGradient? gradient) => _updateSelectedShapes(
        (s) {
          if (s.is1D) return s;
          return s.copyWith(
            fill: s.fill.withGradient(gradient),
            geometries: gradient == null
                ? null
                : syncGeometryNoFill(s.geometries, hollow: false),
          );
        },
        rememberStyle: true,
      );

  void setLineColor(VsdxColor color) => _updateSelectedShapes(
        (s) => s.copyWith(
          line: s.line.withSolidColor(color),
          geometries: syncGeometryNoLine(s.geometries, hollow: false),
        ),
        rememberStyle: true,
      );

  /// Bind selected shapes' stroke to a document theme colour slot.
  void setLineThemeSlot(int slot) {
    _applyThemeSlotToSelection(
      slot,
      (s) => s.copyWith(
        line: s.line.withThemeColor(slot),
        geometries: syncGeometryNoLine(s.geometries, hollow: false),
      ),
    );
  }

  /// Set or clear the selection's line gradient (draw.io Format → Line).
  void setLineGradient(VsdxGradient? gradient) => _updateSelectedShapes(
        (s) => s.copyWith(
          line: s.line.withGradient(gradient),
          geometries: gradient == null
              ? null
              : syncGeometryNoLine(s.geometries, hollow: false),
        ),
        rememberStyle: true,
      );

  /// One undo step: ensure a document theme exists, then restyle selection.
  /// Skips installing an orphan theme when nothing in the selection can change
  /// (all locked, or fill-theme on 1-D-only, etc.).
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
      if (s == null || s.locked || isOnLockedLayer(id)) continue;
      final updated = update(s);
      if (identical(updated, s)) continue;
      nextPage = nextPage.updateShapeById(id, (_) => updated);
      changed = true;
    }
    if (!changed) return;
    applyEdit(nextDoc.replacePage(_currentPageIndex, nextPage));
    _rememberStyle();
  }

  void setLineWeight(double inches) => _updateSelectedShapes(
        (s) => s.copyWith(
          line: s.line.copyWith(
            weightInches: inches,
            pattern: s.line.pattern == 0 ? 1 : s.line.pattern,
          ),
          geometries: syncGeometryNoLine(s.geometries, hollow: false),
        ),
        rememberStyle: true,
      );

  void setNoLine() => _updateSelectedShapes(
        (s) => s.copyWith(
          line: s.line.copyWith(
            pattern: 0,
            gradient: null,
            clearThemeColorIndex: true,
          ),
          geometries: syncGeometryNoLine(s.geometries, hollow: true),
        ),
        rememberStyle: true,
      );

  /// Set the line dash pattern (Visio `LinePattern`: 1 = solid, 2 = dashed,
  /// 3 = dotted, 4 = dash-dot…). Re-enables the line if it was off.
  void setLinePattern(int pattern) => _updateSelectedShapes(
        (s) => s.copyWith(
          line: s.line.copyWith(
            pattern: pattern,
            // pattern=0 is NoLine — clear gradient/theme like [setNoLine].
            gradient: pattern == 0 ? null : VsdxLine.keepGradient,
            clearThemeColorIndex: pattern == 0,
          ),
          geometries: syncGeometryNoLine(s.geometries, hollow: pattern == 0),
        ),
        rememberStyle: true,
      );

  /// Toggle / set the connector arrowheads (0 = none, 1 = a basic arrow).
  /// Pass only the end(s) you want to change. 2-D shapes ignore arrowheads
  /// (same rule as [pasteStyle] / [_withMemoStyle]).
  void setLineArrows({int? begin, int? end}) => _updateSelectedShapes(
        (s) {
          if (!s.is1D) return s;
          return s.copyWith(
            line: s.line.copyWith(beginArrow: begin, endArrow: end),
          );
        },
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
  /// 2-D shapes ignore arrow sizes.
  void setLineArrowSizes({double? beginInches, double? endInches}) =>
      _updateSelectedShapes(
        (s) {
          if (!s.is1D) return s;
          return s.copyWith(
            line: s.line.copyWith(
              beginArrowSizeInches: beginInches,
              endArrowSizeInches: endInches,
            ),
          );
        },
        rememberStyle: true,
      );

  void setBeginArrowSize(double inches) =>
      setLineArrowSizes(beginInches: inches);

  void setEndArrowSize(double inches) => setLineArrowSizes(endInches: inches);

  /// Set Visio `FillPattern` (`0` none, `1` solid, `>1` hatch). Clears gradient
  /// when switching to a hatch so the pattern is visible.
  void setFillPattern(int pattern) => _updateSelectedShapes(
        (s) {
          if (s.is1D) return s;
          // pattern=0 is NoFill — clear gradient like [setNoFill] so writer
          // does not leave FillGradientEnabled=1 with an invisible solid.
          // Solid/none also drop hatch-only FillBkgnd theme so it cannot
          // revive when the user later picks a hatch again.
          return s.copyWith(
            fill: s.fill.copyWith(
              pattern: pattern,
              gradient: pattern == 0 || pattern > 1
                  ? null
                  : VsdxFill.keepGradient,
              clearThemeBackgroundIndex: pattern <= 1,
              // Match [setNoFill]: drop FG theme so it cannot revive later.
              clearThemeForegroundIndex: pattern == 0,
            ),
            geometries: syncGeometryNoFill(s.geometries, hollow: pattern == 0),
          );
        },
        rememberStyle: true,
      );

  /// Hatch background colour (`FillBkgnd`). Enables a hatch when the fill is
  /// currently solid / none so the background is visible.
  void setFillBackground(VsdxColor color) => _updateSelectedShapes(
        (s) {
          if (s.is1D) return s;
          return s.copyWith(
            fill: s.fill.withSolidBackground(color),
            geometries: syncGeometryNoFill(s.geometries, hollow: false),
          );
        },
        rememberStyle: true,
      );

  /// Bind hatch background to a document theme slot (`FillBkgnd` THEMEVAL).
  void setFillBackgroundThemeSlot(int slot) {
    _applyThemeSlotToSelection(
      slot,
      (s) {
        if (s.is1D) return s;
        return s.copyWith(
          fill: s.fill.withThemeBackground(slot),
          geometries: syncGeometryNoFill(s.geometries, hollow: false),
        );
      },
    );
  }

  /// Fill opacity in 0..1 (1 = opaque). Stored as `FillForegndTrans = 1-opacity`.
  /// For hatch fills also mirrors into `FillBkgndTrans` so the gap colour fades
  /// with the same slider (canvas already honours both).
  void setFillOpacity(double opacity, {bool transient = false}) =>
      _updateSelectedShapes(
        (s) {
          if (s.is1D) return s;
          final t = (1 - opacity).clamp(0.0, 1.0);
          return s.copyWith(
            fill: s.fill.copyWith(
              foregroundTransparency: t,
              backgroundTransparency:
                  s.fill.pattern > 1 ? t : s.fill.backgroundTransparency,
            ),
          );
        },
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

  /// Whether the selection includes at least one glueable connector.
  bool get hasConnectorSelected {
    final page = currentPage;
    if (page == null) return false;
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null && s.isGlueableConnector) return true;
    }
    return false;
  }

  /// Whether at least one selected connector can be semantically reversed.
  bool get canReverseConnector {
    final page = currentPage;
    if (page == null) return false;
    return _selection.any((id) {
      final s = page.findShapeById(id);
      return s != null &&
          s.isGlueableConnector &&
          !s.locked &&
          !isOnLockedLayer(id);
    });
  }

  /// Reverse every unlocked selected connector in one undo step.
  void reverseSelectedConnectors() {
    final page = currentPage;
    if (page == null) return;
    final targets = <int>[
      for (final id in _selection)
        if (page.findShapeById(id) case final s?
            when s.isGlueableConnector &&
                !s.locked &&
                !isOnLockedLayer(id))
          id,
    ];
    if (targets.isEmpty) return;
    updateCurrentPage((p) {
      var next = p;
      for (final id in targets) {
        next = next.reverseConnector(id);
      }
      return next;
    });
  }

  /// Whether the first selected connector is drawn as a straight segment.
  bool get selectedConnectorStraight {
    final page = currentPage;
    if (page == null) return false;
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null && s.isGlueableConnector) {
        return page.isConnectorStraight(id);
      }
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
      if (s != null && s.isGlueableConnector) {
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
    final page = currentPage;
    if (page == null) return;
    final targets = <int>{
      for (final id in _selection)
        if (page.findShapeById(id) case final s?
            when s.isGlueableConnector && !s.locked && !isOnLockedLayer(id))
          id,
    };
    if (targets.isEmpty) return;
    updateCurrentPage(
      (page) => page.setConnectorStyle(
        targets,
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
      if (s != null && s.isGlueableConnector) return s.rounded;
    }
    return false;
  }

  /// Toggle drawio-style rounded corners on the selected connectors (one undo
  /// step). Ignored for curved connectors (already smooth) and has no visible
  /// effect on a two-point straight route.
  void setConnectorRounded(bool rounded) {
    if (_selection.isEmpty) return;
    final page = currentPage;
    if (page == null) return;
    final targets = <int>{
      for (final id in _selection)
        if (page.findShapeById(id) case final s?
            when s.isGlueableConnector && !s.locked && !isOnLockedLayer(id))
          id,
    };
    if (targets.isEmpty) return;
    updateCurrentPage(
      (page) => page.setConnectorRounded(targets, rounded),
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
    final page = currentPage;
    final s = page?.findShapeById(id);
    if (s == null || s.locked || isOnLockedLayer(id)) return;
    updateCurrentPage(
      (page) => page.setConnectorWaypoints(id, waypoints),
      transient: transient,
    );
  }

  void moveWaypoint(int id, int index, Offset2D p, {bool transient = false}) {
    final page = currentPage;
    if (page == null) return;
    final wps = List<Offset2D>.of(connectorWaypoints(id));
    if (index < 0 || index >= wps.length) return;
    // Canvas passes page inches; nested connectors store parent-local.
    wps[index] = _pagePointToConnectorLocal(page, id, p);
    setConnectorWaypoints(id, wps, transient: transient);
  }

  void addWaypoint(int id, int index, Offset2D p, {bool transient = false}) {
    final page = currentPage;
    if (page == null) return;
    final wps = List<Offset2D>.of(connectorWaypoints(id));
    wps.insert(
      index.clamp(0, wps.length),
      _pagePointToConnectorLocal(page, id, p),
    );
    setConnectorWaypoints(id, wps, transient: transient);
  }

  /// Map a page-inch point into the coordinate frame used by connector [id]
  /// (page for top-level, parent-local when nested).
  static Offset2D _pagePointToConnectorLocal(
    VsdxPage page,
    int connectorId,
    Offset2D pagePoint,
  ) {
    final parentId = page.findParentId(connectorId);
    if (parentId == null) return pagePoint;
    return page.pageToLocalDeep(parentId, pagePoint);
  }

  void removeWaypoint(int id, int index) {
    final wps = List<Offset2D>.of(connectorWaypoints(id));
    if (index < 0 || index >= wps.length) return;
    wps.removeAt(index);
    setConnectorWaypoints(id, wps);
  }

  /// Move a connector's single VSDX text block to a page-space point.
  ///
  /// Draw.io exposes this as the yellow diamond label handle. A connector
  /// without an authored TextXForm starts as a compact text box centred on the
  /// requested point; existing text-block size, rotation and styling survive.
  void moveConnectorLabel(
    int id,
    double pageX,
    double pageY, {
    bool transient = false,
  }) {
    final page0 = currentPage;
    final connector = page0?.findShapeById(id);
    if (connector == null ||
        !connector.isGlueableConnector ||
        connector.locked ||
        isOnLockedLayer(id)) {
      return;
    }
    updateCurrentPage(
      (page) {
        final s = page.findShapeById(id);
        if (s == null || !s.isGlueableConnector) return page;
        final local =
            page.pageToLocalDeep(id, Offset2D(pageX, pageY));
        final old = s.richText.textBlock;
        final plain = s.richText.plainText.isNotEmpty
            ? s.richText.plainText
            : s.text ?? '';
        final lines = plain.split('\n');
        final longest = lines.fold<int>(
          0,
          (best, line) => math.max(best, line.runes.length),
        );
        final fontSize = s.richText.runs.isEmpty
            ? 0.14
            : s.richText.runs.first.charStyle.fontSizeInches;
        final width = old.widthInches ??
            math.max(
              0.35,
              longest * fontSize * 0.62 +
                  old.marginLeftInches +
                  old.marginRightInches,
            );
        final height = old.heightInches ??
            math.max(
              0.24,
              math.max(lines.length, 1) * fontSize * 1.35 +
                  old.marginTopInches +
                  old.marginBottomInches,
            );
        final formulas = Map<String, String>.of(s.formulas);
        for (final key in const <String>[
          'TxtPinX',
          'TxtPinY',
          'TxtLocPinX',
          'TxtLocPinY',
          'TxtWidth',
          'TxtHeight',
        ]) {
          formulas.remove(key);
        }
        return page.updateShapeById(
          id,
          (shape) => shape.copyWith(
            formulas: formulas,
            richText: shape.richText.copyWith(
              textBlock: old.copyWith(
                pinXInches: local.x,
                pinYInches: local.y,
                locPinXInches: old.locPinXInches ?? width / 2,
                locPinYInches: old.locPinYInches ?? height / 2,
                widthInches: width,
                heightInches: height,
              ),
            ),
          ),
        );
      },
      transient: transient,
    );
  }

  /// Arc-length midpoint of the connector's drawn route in page coordinates.
  static Offset2D _connectorLabelMidpointPage(
    VsdxPage page,
    VsdxShape connector,
  ) {
    final route = page.drawnConnectorPagePolyline(connector);
    if (route.isEmpty) return page.shapePinPage(connector.id);
    if (route.length == 1) return route.first;
    var total = 0.0;
    for (var i = 0; i < route.length - 1; i++) {
      final dx = route[i + 1].x - route[i].x;
      final dy = route[i + 1].y - route[i].y;
      total += math.sqrt(dx * dx + dy * dy);
    }
    if (total <= 1e-12) return route.first;
    var remaining = total / 2;
    for (var i = 0; i < route.length - 1; i++) {
      final dx = route[i + 1].x - route[i].x;
      final dy = route[i + 1].y - route[i].y;
      final length = math.sqrt(dx * dx + dy * dy);
      if (length >= remaining) {
        final t = length <= 1e-12 ? 0.0 : remaining / length;
        return Offset2D(route[i].x + dx * t, route[i].y + dy * t);
      }
      remaining -= length;
    }
    return route.last;
  }

  /// Rotate a connector label so its local +Y axis points from the label pin
  /// towards the page-space pointer ([pageX], [pageY]).
  ///
  /// This matches draw.io's label rotate grab handle while storing the result
  /// in the standard VSDX `TxtAngle` cell. The page→connector-local conversion
  /// keeps labels correct inside rotated or flipped groups.
  void rotateConnectorLabelToward(
    int id,
    double pageX,
    double pageY, {
    bool snapTo15Degrees = false,
    bool transient = false,
  }) {
    final page0 = currentPage;
    if (page0 == null) return;
    final connector = page0.findShapeById(id);
    if (connector == null ||
        !connector.isGlueableConnector ||
        connector.locked ||
        isOnLockedLayer(id)) {
      return;
    }
    final block = connector.richText.textBlock;
    final pinPage = block.pinXInches != null || block.pinYInches != null
        ? page0.localToPageDeep(
            id,
            Offset2D(
              block.pinXInches ?? connector.width / 2,
              block.pinYInches ?? connector.height / 2,
            ),
          )
        : _connectorLabelMidpointPage(page0, connector);
    final pinLocal = page0.pageToLocalDeep(id, pinPage);
    final pointerLocal =
        page0.pageToLocalDeep(id, Offset2D(pageX, pageY));
    final dx = pointerLocal.x - pinLocal.x;
    final dy = pointerLocal.y - pinLocal.y;
    if (dx * dx + dy * dy < 1e-12) return;
    var angle = math.atan2(-dx, dy);
    if (snapTo15Degrees) {
      const step = math.pi / 12;
      angle = (angle / step).round() * step;
    }
    updateCurrentPage(
      (page) => page.updateShapeById(
        id,
        (shape) {
          final formulas = Map<String, String>.of(shape.formulas)
            ..remove('TxtAngle');
          return shape.copyWith(
            formulas: formulas,
            richText: shape.richText.copyWith(
              textBlock: shape.richText.textBlock.copyWith(angleRad: angle),
            ),
          );
        },
      ),
      transient: transient,
    );
  }

  /// Reconnect (or detach) one end of connector [connectorId] — drawio's
  /// endpoint editing. When [targetShapeId] is non-null the end is glued to
  /// that shape; otherwise it floats at page point ([x],[y]). Pass
  /// [createFixedConnectionPoint] to append a custom point at ([x],[y]) before
  /// gluing, matching draw.io's Alt/Option-drop gesture. Pass `transient: true`
  /// while dragging and commit once on release.
  void reconnectEndpoint(
    int connectorId, {
    required bool begin,
    int? targetShapeId,
    int? connectionPointIndex,
    bool createFixedConnectionPoint = false,
    required double x,
    required double y,
    bool transient = false,
  }) {
    final page0 = currentPage;
    final s = page0?.findShapeById(connectorId);
    if (s == null || s.locked || isOnLockedLayer(connectorId)) return;
    updateCurrentPage(
      (page) {
        var next = page;
        var fixedIndex = connectionPointIndex;
        if (targetShapeId != null && createFixedConnectionPoint) {
          final target = next.findShapeById(targetShapeId);
          if (target != null &&
              !target.is1D &&
              !target.locked &&
              !next.isShapeTreeOnLockedLayer(targetShapeId)) {
            final targetLocal = next.pageToLocalDeep(
              targetShapeId,
              Offset2D(x, y),
            );
            next = next.addConnectionPoint(
              targetShapeId,
              targetLocal.x,
              targetLocal.y,
            );
            final updated = next.findShapeById(targetShapeId);
            fixedIndex =
                updated == null || updated.connectionPoints.isEmpty
                    ? null
                    : updated.connectionPoints.length - 1;
          } else {
            // Locked targets remain valid whole-shape glue targets, but must
            // not be mutated to host a new custom connection point.
            fixedIndex = null;
          }
        }
        // [x]/[y] are page inches from the canvas; nested connectors store
        // Begin/End in parent-local space.
        final local =
            _pagePointToConnectorLocal(next, connectorId, Offset2D(x, y));
        return next.setConnectorEndpoint(
          connectorId,
          begin: begin,
          targetShapeId: targetShapeId,
          connectionPointIndex: fixedIndex,
          x: local.x,
          y: local.y,
        );
      },
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

  void _leaveTextEditSession() {
    _textEditShapeId = null;
    _textEditSelection = null;
  }

  /// Whether [containerId] may receive a drop / explicit reparent.
  static bool _containerAcceptsDrop(VsdxPage page, int containerId) {
    final host = page.findShapeById(containerId);
    if (host == null || host.locked) return false;
    if (!page.isShapeTreeVisible(containerId)) return false;
    if (page.isShapeTreeOnLockedLayer(containerId)) return false;
    return true;
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
    final s = currentPage?.findShapeById(id);
    if (s == null || s.locked || isOnLockedLayer(id)) return;
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
    final s = currentPage?.findShapeById(id);
    if (s == null || s.locked || isOnLockedLayer(id)) return;
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
    final s = currentPage?.findShapeById(id);
    if (s == null || s.locked || isOnLockedLayer(id)) return;
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
      if (s != null &&
          s.isGlueableConnector &&
          s.waypoints.isNotEmpty &&
          !s.locked &&
          !isOnLockedLayer(id)) {
        return true;
      }
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
        if (page.findShapeById(id) case final s?
            when s.isGlueableConnector &&
                s.waypoints.isNotEmpty &&
                !s.locked &&
                !isOnLockedLayer(id))
          id,
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

  ({
    VsdxFill fill,
    VsdxLine line,
    VsdxCharStyle? char,
    VsdxParaStyle? para,
    VsdxShadow shadow,
    VsdxGlow glow,
    VsdxReflection reflection,
    bool includeFill,
    bool includeEffects,
  })? _styleClipboard;
  bool get hasStyleClipboard => _styleClipboard != null;

  /// Capture fill / line / text / effect styling of the first selected shape.
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
          shadow: s.shadow,
          glow: s.glow,
          reflection: s.reflection,
          // Connectors have no meaningful fill / effects to transfer onto boxes.
          includeFill: !s.is1D,
          includeEffects: !s.is1D,
        );
        notifyListeners();
        return;
      }
    }
  }

  /// Apply the copied styling to every selected shape (one undo step).
  /// 1-D shapes take only the stroke (never a fill); 2-D shapes never inherit
  /// connector arrowheads — same rules as [_withMemoStyle]. Effects
  /// (shadow / glow / reflection) are included for 2-D shapes when the
  /// clipboard came from a 2-D source.
  ///
  /// Theme-bound fill/line/text installs [VsdxTheme.office] when the document
  /// has no theme yet (same as [setFillThemeSlot]) so New Document → Paste
  /// Style still resolves accent colours.
  void pasteStyle() {
    final clip = _styleClipboard;
    final doc = _document;
    final page0 = currentPage;
    if (clip == null || doc == null || page0 == null || _selection.isEmpty) {
      return;
    }
    final needsTheme = _styleClipboardNeedsTheme(clip);
    var nextDoc =
        needsTheme && doc.theme.isEmpty ? doc.copyWith(theme: VsdxTheme.office) : doc;
    var nextPage = nextDoc.pages[_currentPageIndex];
    var changed = !identical(nextDoc, doc);
    for (final id in _selection) {
      final s = nextPage.findShapeById(id);
      if (s == null || s.locked || isOnLockedLayer(id)) continue;
      final updated = _pasteStyleOnto(s, clip);
      if (identical(updated, s)) continue;
      nextPage = nextPage.updateShapeById(id, (_) => updated);
      changed = true;
    }
    if (!changed) return;
    applyEdit(nextDoc.replacePage(_currentPageIndex, nextPage));
    _rememberStyle();
  }

  static bool _styleClipboardNeedsTheme(
    ({
      VsdxFill fill,
      VsdxLine line,
      VsdxCharStyle? char,
      VsdxParaStyle? para,
      VsdxShadow shadow,
      VsdxGlow glow,
      VsdxReflection reflection,
      bool includeFill,
      bool includeEffects,
    }) clip,
  ) {
    if (clip.includeFill &&
        (clip.fill.themeForegroundIndex != null ||
            clip.fill.themeBackgroundIndex != null)) {
      return true;
    }
    if (clip.line.themeColorIndex != null) return true;
    if (clip.char?.themeColorIndex != null) return true;
    if (clip.includeEffects &&
        (clip.shadow.themeColorIndex != null ||
            clip.glow.themeColorIndex != null)) {
      return true;
    }
    return false;
  }

  static VsdxShape _pasteStyleOnto(
    VsdxShape s,
    ({
      VsdxFill fill,
      VsdxLine line,
      VsdxCharStyle? char,
      VsdxParaStyle? para,
      VsdxShadow shadow,
      VsdxGlow glow,
      VsdxReflection reflection,
      bool includeFill,
      bool includeEffects,
    }) clip,
  ) {
    var line = clip.line;
    if (!s.is1D && (line.beginArrow != 0 || line.endArrow != 0)) {
      line = line.copyWith(beginArrow: 0, endArrow: 0);
    }
    if (s.is1D && line.softEdgesInches > 0) {
      line = line.copyWith(softEdgesInches: 0);
    }
    // 1-D sources have no Soft Edges — do not wipe Soft Edges on 2-D targets.
    if (!clip.includeEffects && !s.is1D) {
      line = line.copyWith(softEdgesInches: s.line.softEdgesInches);
    }
    // A no-line memo must not make connectors invisible.
    if (s.is1D && line.pattern == 0) {
      line = line.copyWith(pattern: 1);
    }
    var next = s.is1D
        ? s.copyWith(line: line)
        : s.copyWith(
            fill: clip.includeFill ? clip.fill : s.fill,
            line: line,
            shadow: clip.includeEffects ? clip.shadow : s.shadow,
            glow: clip.includeEffects ? clip.glow : s.glow,
            reflection: clip.includeEffects ? clip.reflection : s.reflection,
          );
    // Keep Geometry NoFill/NoLine in sync with pasted fill/line — otherwise
    // setNoFill → pasteStyle leaves geom.noFill=true and the canvas stays hollow.
    if (!s.is1D) {
      var geos = next.geometries;
      if (clip.includeFill) {
        geos = syncGeometryNoFill(geos, hollow: next.fill.pattern == 0);
      }
      geos = syncGeometryNoLine(geos, hollow: next.line.pattern == 0);
      if (!identical(geos, next.geometries)) {
        next = next.copyWith(geometries: geos);
      }
    } else if (next.line.pattern != 0) {
      final geos = syncGeometryNoLine(next.geometries, hollow: false);
      if (!identical(geos, next.geometries)) {
        next = next.copyWith(geometries: geos);
      }
    }
    if (clip.char != null || clip.para != null) {
      var runs = next.richText.runs;
      if (runs.isEmpty) {
        final t = next.text;
        if (t != null && t.isNotEmpty) {
          runs = <VsdxTextRun>[VsdxTextRun(text: t)];
        } else {
          runs = <VsdxTextRun>[
            VsdxTextRun(
              text: '',
              charStyle: clip.char ?? const VsdxCharStyle(),
              paraStyle: clip.para ?? const VsdxParaStyle(),
            ),
          ];
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
  }

  // --- Shape data (drawio "Edit Data", Cmd+M) --------------------------------

  /// The id of the single selected shape, or `null` when zero / many are
  /// selected. Used to scope shape-data editing to one shape.
  int? get singleSelectedId => _selection.length == 1 ? _selection.first : null;

  /// Chart group root for the single selection (self or ancestor), or null.
  int? get selectedChartId {
    final page = currentPage;
    final id = singleSelectedId;
    if (page == null || id == null) return null;
    var cur = id;
    while (true) {
      final s = page.findShapeById(cur);
      if (s == null) return null;
      if (ChartOps.isChart(s)) return cur;
      final p = page.findParentId(cur);
      if (p == null) return null;
      cur = p;
    }
  }

  /// The chart group for [selectedChartId], or null.
  VsdxShape? get selectedChart {
    final id = selectedChartId;
    if (id == null) return null;
    return currentPage?.findShapeById(id);
  }

  /// Rebuild the selected chart from comma/semicolon-separated [csv] values.
  void setChartValuesCsv(String csv) {
    final parsed = ChartOps.parseSeriesPaste(csv);
    _rebuildSelectedChart(
      values: parsed.values,
      labels: parsed.labels,
    );
  }

  /// Paste values (and optional `Label: value` pairs) into the selected chart.
  void pasteChartSeries(String text) => setChartValuesCsv(text);

  /// Set every series value to the same relative weight (equal bars/slices).
  void equalizeChartValues() {
    final chart = selectedChart;
    if (chart == null) return;
    final n = ChartOps.chartValues(chart).length;
    if (n < 1) return;
    _rebuildSelectedChart(values: List<double>.filled(n, 1));
  }

  /// Rebuild the selected chart with [values] (one undo step).
  void setChartValues(List<double> values) {
    _rebuildSelectedChart(values: values);
  }

  /// Change chart type while keeping values/colors (one undo step).
  void setChartKind(String kind) {
    if (!ChartOps.kindDisplayNames.containsKey(kind)) return;
    _rebuildSelectedChart(kind: kind);
  }

  /// Replace values and optional series colours (one undo step).
  void setChartData({
    List<double>? values,
    List<VsdxColor>? colors,
    String? kind,
  }) {
    _rebuildSelectedChart(values: values, colors: colors, kind: kind);
  }

  /// Append a series item (default mid value / next palette colour).
  void addChartItem({String? label}) {
    final chart = selectedChart;
    if (chart == null) return;
    final vals = List<double>.of(ChartOps.chartValues(chart));
    if (ChartOps.isSingleValueKind(ChartOps.chartKind(chart) ?? 'column')) {
      return;
    }
    if (vals.length >= ChartOps.maxSeriesItems) return;
    final cols = List<VsdxColor>.of(ChartOps.chartColors(chart));
    final labs = List<String>.of(ChartOps.chartLabels(chart, vals.length));
    final avg = vals.isEmpty
        ? 0.5
        : vals.reduce((a, b) => a + b) / vals.length;
    vals.add(avg);
    cols.add(ChartOps.seriesColors[vals.length % ChartOps.seriesColors.length]);
    labs.add(label?.trim().isNotEmpty == true
        ? label!.trim()
        : ChartOps.defaultLabel(vals.length - 1));
    _rebuildSelectedChart(values: vals, colors: cols, labels: labs);
  }

  /// Remove series item at [index].
  void removeChartItem(int index) {
    final chart = selectedChart;
    if (chart == null) return;
    final vals = List<double>.of(ChartOps.chartValues(chart));
    if (index < 0 || index >= vals.length || vals.length <= 1) return;
    final cols = List<VsdxColor>.of(ChartOps.chartColors(chart));
    final labs = List<String>.of(ChartOps.chartLabels(chart, vals.length));
    vals.removeAt(index);
    if (index < cols.length) cols.removeAt(index);
    if (index < labs.length) labs.removeAt(index);
    _rebuildSelectedChart(values: vals, colors: cols, labels: labs);
  }

  /// Move series item from [from] to [to].
  void reorderChartItem(int from, int to) {
    final chart = selectedChart;
    if (chart == null) return;
    final vals = List<double>.of(ChartOps.chartValues(chart));
    if (from < 0 ||
        to < 0 ||
        from >= vals.length ||
        to >= vals.length ||
        from == to) {
      return;
    }
    final cols = ChartOps.padColors(ChartOps.chartColors(chart), vals.length);
    final labs = ChartOps.padLabels(ChartOps.chartLabels(chart), vals.length);
    final v = vals.removeAt(from);
    final c = cols.removeAt(from);
    final l = labs.removeAt(from);
    vals.insert(to, v);
    cols.insert(to, c);
    labs.insert(to, l);
    _rebuildSelectedChart(values: vals, colors: cols, labels: labs);
  }

  /// Update one series item value, colour, and/or label.
  void updateChartItem(
    int index, {
    double? value,
    VsdxColor? color,
    String? label,
    bool transient = false,
  }) {
    final chart = selectedChart;
    if (chart == null) return;
    final vals = List<double>.of(ChartOps.chartValues(chart));
    if (index < 0 || index >= vals.length) return;
    final cols = ChartOps.padColors(ChartOps.chartColors(chart), vals.length);
    final labs = ChartOps.padLabels(ChartOps.chartLabels(chart), vals.length);
    if (value != null && value.isFinite) vals[index] = value;
    if (color != null) cols[index] = color;
    if (label != null) {
      labs[index] =
          label.trim().isEmpty ? ChartOps.defaultLabel(index) : label.trim();
    }
    _rebuildSelectedChart(
      values: vals,
      colors: cols,
      labels: labs,
      transient: transient,
    );
  }

  void _rebuildSelectedChart({
    List<double>? values,
    List<VsdxColor>? colors,
    List<String>? labels,
    String? kind,
    String? extras,
    bool transient = false,
  }) {
    final chartId = selectedChartId;
    if (chartId == null) return;
    final page0 = currentPage;
    final chart0 = page0?.findShapeById(chartId);
    if (chart0 == null || chart0.locked || isOnLockedLayer(chartId)) return;
    updateCurrentPage(
      (page) {
        final chart = page.findShapeById(chartId);
        if (chart == null || !ChartOps.isChart(chart)) return page;
        var nextId = page.nextFreeShapeId();
        final rebuilt = ChartOps.rebuild(
          chart,
          values: values,
          colors: colors,
          labels: labels,
          kind: kind,
          extras: extras,
          allocId: () => nextId++,
        );
        return page.updateShapeById(chartId, (_) => rebuilt);
      },
      transient: transient,
    );
    if (!transient) setSelection([chartId]);
  }

  /// Update kind-specific extras (heatmap grid, calendar weeks, …).
  void setChartExtras(String extras) {
    _rebuildSelectedChart(extras: extras);
  }

  /// Rebuild selected chart with packed specialty values + optional extras.
  void setChartSpecialtyData({
    List<double>? values,
    List<VsdxColor>? colors,
    List<String>? labels,
    String? extras,
  }) {
    _rebuildSelectedChart(
      values: values,
      colors: colors,
      labels: labels,
      extras: extras,
    );
  }

  /// Coloured series children of the selected chart (for swatch editing).
  List<VsdxShape> get selectedChartSeries {
    final chart = selectedChart;
    if (chart == null) return const <VsdxShape>[];
    return ChartOps.seriesChildren(chart);
  }

  /// Set fill colour on a chart series child (one undo step).
  void setChartSeriesColor(int seriesId, VsdxColor color) {
    final chart = selectedChart;
    if (chart == null) return;
    final series = ChartOps.seriesChildren(chart);
    final index = series.indexWhere((s) => s.id == seriesId);
    if (index < 0) return;
    updateChartItem(index, color: color);
  }

  // --- Third-party icons (picture + IconOps userCells) -----------------------

  int _iconRebuildSerial = 0;

  /// Caption height placed below an icon picture (inches).
  static const double iconCaptionHeightInches = 0.22;

  /// Attach [caption] under [shapeId] (TxtPin below the picture box).
  /// Does not change the picture frame size so the glyph stays full-bleed.
  /// Pass [transient] `true` to fold into the preceding undo step (e.g. insert).
  void setIconCaptionBelow(
    int shapeId,
    String caption, {
    bool transient = false,
  }) {
    final page = currentPage;
    final s = page?.findShapeById(shapeId);
    if (s == null || s.locked || isOnLockedLayer(shapeId)) return;
    final text = caption.trim();
    if (text.isEmpty) return;
    final w = s.width.abs();
    final labelH = iconCaptionHeightInches;
    final labelW = math.max(w, 0.9);
    final sizeInches = (8.0 / 72.0).clamp(4.0 / 72.0, 0.18);
    final cjk = _containsCjk(text);
    updateCurrentPage(
      (p) => p.updateShapeById(
        shapeId,
        (sh) {
          // Drop Width*/Height*/SETATREF Txt* formulas so absolute caption
          // placement is not overwritten by recalculate / resize / save.
          final nextFormulas = Map<String, String>.of(sh.formulas)
            ..remove('TxtPinX')
            ..remove('TxtPinY')
            ..remove('TxtWidth')
            ..remove('TxtHeight')
            ..remove('TxtLocPinX')
            ..remove('TxtLocPinY');
          return sh.copyWith(
            text: text,
            fields: const <VsdxFieldRow>[],
            formulas: nextFormulas,
            richText: VsdxRichText(
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
              // Pin at the shape's bottom edge (Y=0) with LocPin at the top
              // of the caption box so the label hangs fully below. Prefer this
              // over a negative TxtPinY — EdrawMax clamps / ignores negative
              // pins and would otherwise paint the caption on top of the glyph.
              textBlock: VsdxTextBlock(
                pinXInches: w / 2,
                pinYInches: 0,
                locPinXInches: labelW / 2,
                locPinYInches: labelH,
                widthInches: labelW,
                heightInches: labelH,
                verticalAlign: VsdxVertAlign.middle,
                marginLeftInches: 0.02,
                marginRightInches: 0.02,
                marginTopInches: 0.01,
                marginBottomInches: 0.01,
              ),
            ),
          );
        },
      ),
      transient: transient,
    );
  }

  /// Selected picture that carries [IconOps] metadata, or null.
  int? get selectedIconId {
    final page = currentPage;
    final id = singleSelectedId;
    if (page == null || id == null) return null;
    final s = page.findShapeById(id);
    if (s == null || !s.hasImage || !IconOps.isIcon(s)) return null;
    return id;
  }

  /// The selected icon picture shape, or null.
  VsdxShape? get selectedIcon {
    final id = selectedIconId;
    if (id == null) return null;
    return currentPage?.findShapeById(id);
  }

  /// Re-rasterise the selected icon (pack / glyph / colour). One undo step.
  Future<void> setSelectedIcon({
    String? providerId,
    String? iconId,
    int? colorArgb,
  }) async {
    final shapeId = selectedIconId;
    if (shapeId == null) return;
    final page = currentPage;
    final shape = page?.findShapeById(shapeId);
    if (shape == null || shape.locked || isOnLockedLayer(shapeId)) return;

    final p = providerId ?? IconOps.providerId(shape);
    final i = iconId ?? IconOps.iconId(shape);
    if (p == null || i == null) return;
    final entry = findThirdPartyIcon(p, i);
    if (entry == null) return;
    final argb = colorArgb ?? IconOps.colorArgb(shape);
    final color = Color(argb);

    final serial = ++_iconRebuildSerial;
    final bytes = await rasterizeThirdPartyIcon(entry.icon, color: color);
    if (serial != _iconRebuildSerial) return;
    if (bytes.isEmpty) return;
    // Selection may have changed while awaiting.
    if (selectedIconId != shapeId) return;

    replaceImage(
      shapeId,
      bytes,
      fileExtension: 'png',
      userCells: IconOps.meta(
        providerId: p,
        iconId: i,
        colorArgb: argb,
      ),
    );
  }

  /// The custom properties (`<Section N="Property">`, Visio "Shape Data") of
  /// the single selection, or an empty list.
  List<VsdxUserProperty> get selectedProperties =>
      singleSelected?.userProperties ?? const <VsdxUserProperty>[];

  /// Replace a shape's Shape Data with [props] (one undo step). Empty [props]
  /// clears the `<Section N="Property">` on save. Names should be unique;
  /// duplicates are dropped keeping the first occurrence.
  void setShapeProperties(int shapeId, List<VsdxUserProperty> props) {
    final page = currentPage;
    final shape = page?.findShapeById(shapeId);
    if (shape == null || shape.locked || isOnLockedLayer(shapeId)) return;
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
    final page = currentPage;
    final shape = page?.findShapeById(shapeId);
    if (shape == null || shape.locked || isOnLockedLayer(shapeId)) return;
    updateCurrentPage(
      (page) => page.updateShapeById(
        shapeId,
        (s) => s.copyWith(hyperlinks: links),
      ),
    );
  }

  // --- Grouping (drawio "Group" / "Ungroup") ---------------------------------

  /// Whether the selection has ≥ 2 unlocked top-level shapes that can be grouped.
  bool get canGroup {
    final page = currentPage;
    if (page == null) return false;
    var n = 0;
    for (final s in page.shapes) {
      if (_selection.contains(s.id) &&
          !s.locked &&
          !isOnLockedLayer(s.id)) {
        if (++n >= 2) return true;
      }
    }
    return false;
  }

  /// Whether the selection contains an unlocked group to ungroup (top-level or
  /// nested — matches [ungroupSelection]).
  static bool _isStructuredGroup(VsdxShape shape) =>
      TableOps.isTable(shape) ||
      SwimlaneOps.isPool(shape) ||
      ChartOps.isChart(shape);

  static bool _canUngroupShape(VsdxShape shape) =>
      shape.children.isNotEmpty && !_isStructuredGroup(shape);

  bool get canUngroup {
    final page = currentPage;
    if (page == null) return false;
    for (final id in _selection) {
      if (page.findShapeById(id) case final s?
          when _canUngroupShape(s) &&
              !s.locked &&
              !isOnLockedLayer(id)) {
        return true;
      }
    }
    return false;
  }

  bool _canRemoveShapeFromGroup(VsdxPage page, int id) {
    final shape = page.findShapeById(id);
    final parentId = page.findParentId(id);
    final parent = parentId == null ? null : page.findShapeById(parentId);
    return shape != null &&
        !shape.locked &&
        !isOnLockedLayer(id) &&
        parent != null &&
        _canUngroupShape(parent) &&
        !parent.locked &&
        !isOnLockedLayer(parent.id);
  }

  /// Whether at least one selected root can be promoted out of an ordinary
  /// group. Structured hosts (tables, swimlanes and charts) are intentionally
  /// excluded so their internal rows/cells are not dismantled.
  bool get canRemoveSelectionFromGroup {
    final page = currentPage;
    if (page == null || _selection.isEmpty) return false;
    return _selectionRoots(page, _selection)
        .any((id) => _canRemoveShapeFromGroup(page, id));
  }

  /// draw.io "Arrange > Remove from Group": promote selected direct children
  /// to the page while preserving their page-space geometry.
  void removeSelectionFromGroup() {
    final page = currentPage;
    if (page == null || _selection.isEmpty) return;
    final movable = _selectionRoots(page, _selection)
        .where((id) => _canRemoveShapeFromGroup(page, id));
    _reparentShapesInto(movable, null);
  }

  /// Group the selected top-level shapes into a new group and select it.
  /// Locked shapes / locked-layer shapes are left outside the group.
  void groupSelection() {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null) return;
    final ids = <int>{
      for (final s in page.shapes)
        if (_selection.contains(s.id) &&
            !s.locked &&
            !isOnLockedLayer(s.id))
          s.id,
    };
    if (ids.length < 2) return;
    final gid = page.nextFreeShapeId();
    final movedIds = <int>{..._subtreeIds(ids), gid};
    var next = page.group(ids, groupId: gid);
    if (identical(next, page)) return;
    next = next
        .recalculateFormulas(changedShapeIds: movedIds)
        .rerouteConnectors(movedShapeIds: movedIds);
    final undoSel = Set<int>.of(_selection);
    _selection
      ..clear()
      ..add(gid);
    applyEdit(
      doc.replacePage(_currentPageIndex, next),
      undoSelection: undoSel,
    );
  }

  /// Ungroup every selected unlocked group (top-level or nested), selecting
  /// the children.
  void ungroupSelection() {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null) return;
    final groups = <VsdxShape>[
      for (final id in _selection)
        if (page.findShapeById(id) case final s?
            when _canUngroupShape(s) &&
                !s.locked &&
                !isOnLockedLayer(id))
          s,
    ];
    if (groups.isEmpty) return;
    // Deepest first so nested groups ungroup before their parents.
    int depth(int id) {
      var d = 0;
      var p = page.findParentId(id);
      while (p != null) {
        d++;
        p = page.findParentId(p);
      }
      return d;
    }

    groups.sort((a, b) => depth(b.id).compareTo(depth(a.id)));
    final childIds = <int>{
      for (final g in groups)
        for (final c in g.children) c.id,
    };
    final movedIds = _subtreeIds(<int>[for (final g in groups) g.id]);
    var next = page;
    for (final g in groups) {
      next = next.ungroup(g.id);
    }
    if (identical(next, page)) return;
    next = next
        .recalculateFormulas(changedShapeIds: movedIds)
        .rerouteConnectors(movedShapeIds: movedIds);
    final groupIds = <int>{for (final g in groups) g.id};
    final keep = <int>{
      for (final id in _selection)
        if (!groupIds.contains(id) && next.findShapeById(id) != null) id,
    };
    final undoSel = Set<int>.of(_selection);
    _selection
      ..clear()
      ..addAll(childIds)
      ..addAll(keep);
    applyEdit(
      doc.replacePage(_currentPageIndex, next),
      undoSelection: undoSel,
    );
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
  void setShapeText(int id, String text) {
    final page = currentPage;
    final s = page?.findShapeById(id);
    if (s == null || s.locked || isOnLockedLayer(id)) return;
    updateCurrentPage(
      (p) => p.updateShapeById(id, (sh) => _withLabelText(sh, text)),
    );
  }

  /// Apply [text] to [s], preserving multi-run styles when possible.
  /// Clears Field rows when the label is rewritten (field spans are dropped
  /// by [replacePlainText] / a fresh single run).
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
        fields: const <VsdxFieldRow>[],
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
    return s.copyWith(
        text: text, richText: next, fields: const <VsdxFieldRow>[]);
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

  /// Character style for the Format → Text panel / Cmd+B/I/U.
  ///
  /// Returns Visio defaults when the shape has no Character runs yet (plain
  /// `text` fallback, empty label, or mid-inline-edit before commit) so the
  /// panel stays visible like draw.io — applying a style seeds the run.
  VsdxCharStyle? get selectedCharStyle {
    final page = currentPage;
    if (page == null) return null;
    final editId = _textEditShapeId;
    if (editId != null) {
      final s = page.findShapeById(editId);
      if (s != null) {
        if (s.richText.runs.isNotEmpty) {
          final sel = _textEditSelection;
          final collapsed = sel == null || sel.start == sel.end;
          final idx = collapsed
              ? (sel?.start ?? 0)
              : math.min(sel.start, sel.end);
          return charStyleAt(s.richText, idx) ?? s.richText.runs.first.charStyle;
        }
        return VsdxCharStyle.defaults;
      }
    }
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null) {
        if (s.richText.runs.isNotEmpty) {
          return s.richText.runs.first.charStyle;
        }
        return VsdxCharStyle.defaults;
      }
    }
    return null;
  }

  VsdxHorzAlign? get selectedAlign {
    final page = currentPage;
    if (page == null) return null;
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null) {
        if (s.richText.runs.isNotEmpty) {
          return s.richText.runs.first.paraStyle.horizontalAlign;
        }
        return VsdxParaStyle.defaults.horizontalAlign;
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
        if (s == null || s.locked || isOnLockedLayer(editId)) return page;
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
        if (t == null || t.isEmpty) {
          // Seed an empty styled run so Format tools (Bold etc.) stick for
          // the next keystroke — same as clearing text via replacePlainText.
          if (char == null && para == null) return s;
          final seeded = VsdxTextRun(
            text: '',
            charStyle: char != null
                ? char(const VsdxCharStyle())
                : const VsdxCharStyle(),
            paraStyle: para != null
                ? para(const VsdxParaStyle())
                : const VsdxParaStyle(),
          );
          return s.copyWith(
            richText: s.richText.copyWith(runs: <VsdxTextRun>[seeded]),
          );
        }
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

  /// Increase or decrease every run in the selected label by [deltaPoints].
  ///
  /// Unlike the Text panel, this deliberately ignores an inline text range:
  /// draw.io's Cmd/Ctrl+Shift+NumPad +/- shortcut always changes the entire
  /// shape or connector label. Each run keeps its relative size.
  void adjustWholeLabelTextSizePoints(double deltaPoints) {
    if (!deltaPoints.isFinite || deltaPoints == 0) return;
    final editId = _textEditShapeId;
    _updateSelectedShapes((s) {
      if (editId != null && s.id != editId) return s;
      var runs = s.richText.runs;
      if (runs.isEmpty) {
        runs = <VsdxTextRun>[VsdxTextRun(text: s.text ?? '')];
      }
      final nextRuns = <VsdxTextRun>[
        for (final run in runs)
          run.copyWith(
            charStyle: run.charStyle.copyWith(
              fontSizeInches:
                  ((run.charStyle.fontSizeInches * 72 + deltaPoints)
                              .clamp(1.0, 999.0) /
                          72)
                      .toDouble(),
            ),
          ),
      ];
      return s.copyWith(
        richText: s.richText.copyWith(runs: nextRuns),
      );
    });
  }

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
    _applyTextThemeSlot(slot);
  }

  /// Install a document theme (when missing) and restyle text in one undo step.
  void _applyTextThemeSlot(int slot) {
    final doc = _document;
    final page = currentPage;
    if (doc == null || page == null) return;
    final nextDoc =
        doc.theme.isEmpty ? doc.copyWith(theme: VsdxTheme.office) : doc;
    VsdxCharStyle char(VsdxCharStyle c) => c.withThemeColor(slot);

    final editId = _textEditShapeId;
    final sel = _textEditSelection;
    final useRange = editId != null && sel != null && sel.start != sel.end;
    var nextPage = nextDoc.pages[_currentPageIndex];

    if (useRange) {
      final s = nextPage.findShapeById(editId);
      if (s == null || s.locked || isOnLockedLayer(editId)) return;
      var rich = s.richText;
      if (rich.runs.isEmpty) {
        final t = s.text;
        if (t == null || t.isEmpty) return;
        rich = rich.copyWith(runs: <VsdxTextRun>[VsdxTextRun(text: t)]);
      }
      final a = math.min(sel.start, sel.end);
      final b = math.max(sel.start, sel.end);
      rich = applyCharStyleToRange(rich, start: a, end: b, update: char);
      nextPage = nextPage.updateShapeById(
        editId,
        (sh) => sh.copyWith(text: rich.plainText, richText: rich),
      );
    } else {
      var changed = false;
      for (final id in _selection) {
        final s = nextPage.findShapeById(id);
        if (s == null || s.locked || isOnLockedLayer(id)) continue;
        if (editId != null && s.id != editId) continue;
        var runs = s.richText.runs;
        if (runs.isEmpty) {
          final t = s.text;
          if (t == null || t.isEmpty) {
            // Seed an empty styled run so later typing inherits the theme colour.
            final seeded = VsdxTextRun(
              text: '',
              charStyle: char(const VsdxCharStyle()),
            );
            nextPage = nextPage.updateShapeById(
              id,
              (sh) => sh.copyWith(
                richText: sh.richText.copyWith(runs: <VsdxTextRun>[seeded]),
              ),
            );
            changed = true;
            continue;
          }
          runs = <VsdxTextRun>[VsdxTextRun(text: t)];
        }
        final newRuns = <VsdxTextRun>[
          for (final r in runs)
            r.copyWith(charStyle: char(r.charStyle)),
        ];
        nextPage = nextPage.updateShapeById(
          id,
          (sh) => sh.copyWith(
            richText: sh.richText.copyWith(runs: newRuns),
          ),
        );
        changed = true;
      }
      if (!changed) return;
    }
    applyEdit(nextDoc.replacePage(_currentPageIndex, nextPage));
  }

  void setTextAlign(VsdxHorzAlign align) =>
      _updateText(para: (p) => p.copyWith(horizontalAlign: align));

  /// First selected (or in-edit) paragraph style — for Format Text spacing.
  ///
  /// Falls back to Visio paragraph defaults when no Paragraph runs exist yet
  /// (same visibility contract as [selectedCharStyle]).
  VsdxParaStyle? get selectedParaStyle {
    final page = currentPage;
    if (page == null) return null;
    final editId = _textEditShapeId;
    if (editId != null) {
      final s = page.findShapeById(editId);
      if (s != null) {
        if (s.richText.runs.isNotEmpty) {
          return s.richText.runs.first.paraStyle;
        }
        return VsdxParaStyle.defaults;
      }
    }
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null) {
        if (s.richText.runs.isNotEmpty) {
          return s.richText.runs.first.paraStyle;
        }
        return VsdxParaStyle.defaults;
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

  /// Toggle Visio paragraph bullets on the selection / in-edit text.
  ///
  /// Enables `Bullet=1` with a hanging indent defaults when turning on;
  /// clears `Bullet` when turning off (glyph/`BulletStr` retained for reopen).
  void setBullet(bool enabled) => _updateText(
        para: (p) {
          if (!enabled) {
            return p.copyWith(bullet: 0);
          }
          if (p.bullet != 0) return p;
          return p.copyWith(
            bullet: 1,
            bulletStr: p.bulletStr ?? '•',
            indentLeftInches:
                p.indentLeftInches > 0 ? p.indentLeftInches : 0.2,
            indentFirstInches:
                p.indentFirstInches != 0 ? p.indentFirstInches : -0.15,
            textPosAfterBulletInches: p.textPosAfterBulletInches > 0
                ? p.textPosAfterBulletInches
                : 0.2,
          );
        },
      );

  /// Whether every selected / in-edit shape paragraph currently has bullets.
  bool get selectedHasBullet {
    final style = selectedParaStyle;
    return style != null && style.bullet != 0;
  }

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

  /// Move selected 2-D labels inside or immediately outside their shapes.
  ///
  /// Visio represents this with the text block transform (`TxtPin*`,
  /// `TxtLocPin*`, `TxtWidth/Height`). The block keeps the shape's size and is
  /// pinned by the edge nearest the shape, matching draw.io's five common
  /// Position choices while remaining stable under rotation and resize.
  void setTextLabelPosition(TextLabelPosition position) =>
      _updateSelectedShapes((s) {
        if (s.is1D) return s;
        final w = math.max(s.width.abs(), 0.05);
        final h = math.max(s.height.abs(), 0.05);
        final old = s.richText.textBlock;
        final (pinX, pinY, locX, locY, verticalAlign, horizontalAlign) =
            switch (position) {
          TextLabelPosition.left => (
              0.0,
              h / 2,
              w,
              h / 2,
              VsdxVertAlign.middle,
              VsdxHorzAlign.right,
            ),
          TextLabelPosition.top => (
              w / 2,
              h,
              w / 2,
              0.0,
              VsdxVertAlign.bottom,
              VsdxHorzAlign.center,
            ),
          TextLabelPosition.center => (
              w / 2,
              h / 2,
              w / 2,
              h / 2,
              VsdxVertAlign.middle,
              VsdxHorzAlign.center,
            ),
          TextLabelPosition.bottom => (
              w / 2,
              0.0,
              w / 2,
              h,
              VsdxVertAlign.top,
              VsdxHorzAlign.center,
            ),
          TextLabelPosition.right => (
              w,
              h / 2,
              0.0,
              h / 2,
              VsdxVertAlign.middle,
              VsdxHorzAlign.left,
            ),
        };
        final runs = s.richText.runs.isEmpty
            ? <VsdxTextRun>[
                VsdxTextRun(
                  text: s.text ?? '',
                  paraStyle: VsdxParaStyle(
                    horizontalAlign: horizontalAlign,
                  ),
                ),
              ]
            : <VsdxTextRun>[
                for (final run in s.richText.runs)
                  run.copyWith(
                    paraStyle: run.paraStyle.copyWith(
                      horizontalAlign: horizontalAlign,
                    ),
                  ),
              ];
        final formulas = Map<String, String>.of(s.formulas);
        for (final key in const <String>[
          'TxtPinX',
          'TxtPinY',
          'TxtLocPinX',
          'TxtLocPinY',
          'TxtWidth',
          'TxtHeight',
        ]) {
          formulas.remove(key);
        }
        return s.copyWith(
          formulas: formulas,
          richText: s.richText.copyWith(
            runs: runs,
            textBlock: VsdxTextBlock(
              pinXInches: pinX,
              pinYInches: pinY,
              locPinXInches: locX,
              locPinYInches: locY,
              widthInches: w,
              heightInches: h,
              angleRad: old.angleRad,
              verticalAlign: verticalAlign,
              marginLeftInches: old.marginLeftInches,
              marginRightInches: old.marginRightInches,
              marginTopInches: old.marginTopInches,
              marginBottomInches: old.marginBottomInches,
              hideText: old.hideText,
              backgroundColor: old.backgroundColor,
              backgroundTransparency: old.backgroundTransparency,
              textDirection: old.textDirection,
              defaultTabStopInches: old.defaultTabStopInches,
            ),
          ),
        );
      });

  TextLabelPosition? get selectedTextLabelPosition {
    final s = _firstSelected2D;
    if (s == null) return null;
    final b = s.richText.textBlock;
    final w = math.max(s.width.abs(), 0.05);
    final h = math.max(s.height.abs(), 0.05);
    final blockWidth = b.widthInches ?? w;
    final blockHeight = b.heightInches ?? h;
    final px = b.pinXInches ?? w / 2;
    final py = b.pinYInches ?? h / 2;
    final lx = b.locPinXInches ?? blockWidth / 2;
    final ly = b.locPinYInches ?? blockHeight / 2;
    bool near(double a, double value) => (a - value).abs() < 1e-6;
    if (near(px, 0) && near(lx, blockWidth)) {
      return TextLabelPosition.left;
    }
    if (near(py, h) && near(ly, 0)) return TextLabelPosition.top;
    if (near(py, 0) && near(ly, blockHeight)) {
      return TextLabelPosition.bottom;
    }
    if (near(px, w) && near(lx, 0)) return TextLabelPosition.right;
    return TextLabelPosition.center;
  }

  void setVerticalText(bool enabled) => _updateSelectedShapes(
        (s) => s.copyWith(
          richText: s.richText.copyWith(
            textBlock: s.richText.textBlock.copyWith(
              textDirection: enabled ? 1 : 0,
            ),
          ),
        ),
      );

  bool get selectedVerticalText {
    final page = currentPage;
    if (page == null || _selection.isEmpty) return false;
    var any = false;
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s == null) continue;
      any = true;
      if (s.richText.textBlock.textDirection != 1) return false;
    }
    return any;
  }

  /// Toggle Curved Text (label along an arc) on selected 2-D shapes.
  void setCurvedText(bool value) => _updateSelectedShapes(
        (s) {
          if (s.is1D || s.locked) return s;
          return s.curvedText == value ? s : s.withCurvedText(value);
        },
      );

  /// Whether every selected 2-D shape currently has Curved Text enabled.
  bool get selectedCurvedText {
    final page = currentPage;
    if (page == null || _selection.isEmpty) return false;
    var any = false;
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s == null || s.is1D) continue;
      any = true;
      if (!s.curvedText) return false;
    }
    return any;
  }

  VsdxVertAlign? get selectedVerticalAlign {
    final page = currentPage;
    if (page == null) return null;
    for (final id in _selection) {
      final s = page.findShapeById(id);
      if (s != null) return s.richText.textBlock.verticalAlign;
    }
    return null;
  }

  /// Toggle a drop shadow on the selected shapes (2-D only; connectors skip).
  void setShadow(bool enabled) => _updateSelectedShapes(
        (s) {
          if (s.is1D) return s;
          if (!enabled) {
            // Keep colour / offsets / blur so toggle-off restores them
            // (writer still emits ShadowPattern=0 while disabled).
            return s.copyWith(shadow: s.shadow.copyWith(enabled: false));
          }
          final prev = s.shadow;
          if (prev.enabled) return s;
          // Prefer page Sheet ShdwOffset* (Visio default 0.125/-0.125) when
          // the shape still carries the library 0.05/0.05 placeholder.
          final page = currentPage;
          final sheet = page?.pageSheet;
          final usePageOffset = sheet != null &&
              (prev.offsetXInches - 0.05).abs() < 1e-9 &&
              (prev.offsetYInches - 0.05).abs() < 1e-9;
          return s.copyWith(
            shadow: prev.copyWith(
              enabled: true,
              transparency: prev.transparency >= 1 ? 0.4 : prev.transparency,
              offsetXInches: usePageOffset
                  ? sheet.shadowOffsetXInches
                  : prev.offsetXInches,
              offsetYInches: usePageOffset
                  ? sheet.shadowOffsetYInches
                  : prev.offsetYInches,
            ),
          );
        },
      );

  bool get selectedHasShadow {
    final s = _firstSelected2D;
    return s != null && s.shadow.enabled;
  }

  /// First selected 2-D shape's shadow (may be disabled).
  VsdxShadow? get selectedShadow => _firstSelected2D?.shadow;

  /// Update shadow colour / offsets / blur / opacity on the selection.
  void updateShadow({
    VsdxColor? color,
    int? themeColorIndex,
    double? offsetXInches,
    double? offsetYInches,
    double? blurInches,
    double? transparency,
    bool transient = false,
  }) {
    _updateSelectedShapes(
      (s) {
        if (s.is1D) return s;
        // Prefer the shape's shadow (may be disabled but still hold offsets).
        final base = s.shadow;
        final VsdxShadow next;
        if (themeColorIndex != null) {
          next = base.withThemeColor(themeColorIndex).copyWith(
                offsetXInches: offsetXInches,
                offsetYInches: offsetYInches,
                blurInches: blurInches,
                transparency: transparency,
                enabled: true,
              );
        } else if (color != null) {
          next = base.withSolidColor(color).copyWith(
                offsetXInches: offsetXInches,
                offsetYInches: offsetYInches,
                blurInches: blurInches,
                transparency: transparency,
                enabled: true,
              );
        } else {
          next = base.copyWith(
            offsetXInches: offsetXInches,
            offsetYInches: offsetYInches,
            blurInches: blurInches,
            transparency: transparency,
            enabled: true,
          );
        }
        return s.copyWith(shadow: next);
      },
      transient: transient,
    );
  }

  /// Toggle an outer glow on the selected shapes (2-D only).
  void setGlow(bool enabled) => _updateSelectedShapes(
        (s) {
          if (s.is1D) return s;
          if (!enabled) {
            // Keep colour / theme / size in the model so a UI toggle-off
            // restores them; writer still emits GlowSize=0 when disabled.
            return s.copyWith(glow: s.glow.copyWith(enabled: false));
          }
          final prev = s.glow;
          if (prev.enabled) return s;
          final hasAuthored =
              prev.color != null || prev.themeColorIndex != null;
          // Persist amber only for a brand-new solid glow so SVG/canvas share
          // the same authored colour. Theme-bound / prior solid glows restore.
          return s.copyWith(
            glow: hasAuthored
                ? prev.copyWith(
                    enabled: true,
                    sizeInches:
                        prev.sizeInches <= 0 ? 0.05 : prev.sizeInches,
                  )
                : prev.copyWith(
                    enabled: true,
                    transparency: 0.6,
                    sizeInches: 0.05,
                    color: const VsdxColor(0xFFFFC107),
                  ),
          );
        },
      );

  bool get selectedHasGlow {
    final g = _firstSelected2D?.glow;
    return g != null && g.enabled;
  }

  VsdxGlow? get selectedGlow => _firstSelected2D?.glow;

  void updateGlow({
    VsdxColor? color,
    int? themeColorIndex,
    double? sizeInches,
    double? transparency,
    bool transient = false,
  }) {
    _updateSelectedShapes(
      (s) {
        if (s.is1D) return s;
        // Prefer the shape's glow (may be disabled but still hold theme/size).
        final base = s.glow;
        final VsdxGlow next;
        if (themeColorIndex != null) {
          next = base.withThemeColor(themeColorIndex).copyWith(
                sizeInches: sizeInches ??
                    (base.sizeInches <= 0 ? 0.05 : base.sizeInches),
                transparency: transparency ??
                    (base.transparency >= 1 ? 0.6 : base.transparency),
                enabled: true,
              );
        } else if (color != null) {
          next = base.withSolidColor(color).copyWith(
                sizeInches: sizeInches,
                transparency: transparency,
                enabled: true,
              );
        } else {
          next = base.copyWith(
            sizeInches: sizeInches ??
                (base.sizeInches <= 0 ? 0.05 : base.sizeInches),
            transparency: transparency ??
                (base.transparency >= 1 ? 0.6 : base.transparency),
            enabled: true,
          );
        }
        return s.copyWith(glow: next);
      },
      transient: transient,
    );
  }

  /// Toggle a mirror reflection under the selected shapes (2-D only).
  void setReflection(bool enabled) => _updateSelectedShapes(
        (s) {
          if (s.is1D) return s;
          if (!enabled) {
            // Keep size/dist/blur so toggle-off restores them (writer emits
            // ReflectionSize=0 while disabled).
            return s.copyWith(
              reflection: s.reflection.copyWith(enabled: false),
            );
          }
          final prev = s.reflection;
          if (prev.enabled) return s;
          return s.copyWith(
            reflection: prev.copyWith(
              enabled: true,
              sizeInches: prev.sizeInches <= 0 ? 0.3 : prev.sizeInches,
            ),
          );
        },
      );

  bool get selectedHasReflection {
    final r = _firstSelected2D?.reflection;
    return r != null && r.enabled;
  }

  VsdxReflection? get selectedReflection => _firstSelected2D?.reflection;

  void updateReflection({
    double? sizeInches,
    double? distanceInches,
    double? blurInches,
    double? transparency,
    bool transient = false,
  }) {
    _updateSelectedShapes(
      (s) {
        if (s.is1D) return s;
        final base = s.reflection;
        return s.copyWith(
          reflection: base.copyWith(
            sizeInches: sizeInches ??
                (base.sizeInches <= 0 ? 0.3 : base.sizeInches),
            distanceInches: distanceInches,
            blurInches: blurInches,
            transparency: transparency ??
                (base.transparency >= 1 ? 0.6 : base.transparency),
            enabled: true,
          ),
        );
      },
      transient: transient,
    );
  }

  /// Whether the selection has Soft Edges (`SoftEdgesSize` > 0).
  bool get selectedHasSoftEdges =>
      (_firstSelected2D?.line.softEdgesInches ?? 0) > 0;

  double get selectedSoftEdgesInches =>
      _firstSelected2D?.line.softEdgesInches ?? 0;

  /// Toggle Soft Edges on the selection (default size 0.05"; 2-D only).
  void setSoftEdges(bool enabled) => _updateSelectedShapes(
        (s) {
          if (s.is1D) return s;
          final cur = s.line.softEdgesInches;
          if (!enabled) {
            if (cur > 0) _memoSoftEdgesInches = cur;
            return s.copyWith(line: s.line.copyWith(softEdgesInches: 0));
          }
          final size = cur > 0
              ? cur
              : (_memoSoftEdgesInches > 0 ? _memoSoftEdgesInches : 0.05);
          return s.copyWith(line: s.line.copyWith(softEdgesInches: size));
        },
        rememberStyle: true,
      );

  /// Update Soft Edges blur radius (inches).
  void updateSoftEdges(double sizeInches, {bool transient = false}) {
    final clamped = sizeInches.clamp(0.0, 0.25);
    if (clamped > 0) _memoSoftEdgesInches = clamped;
    _updateSelectedShapes(
      (s) {
        if (s.is1D) return s;
        return s.copyWith(
          line: s.line.copyWith(softEdgesInches: clamped),
        );
      },
      transient: transient,
      rememberStyle: true,
    );
  }

  /// Rotate a single shape about its pin (radians, Visio CCW convention).
  /// 1-D connectors rotate Begin/End geometry; [angleRad] is treated as a
  /// delta from the current heading when the shape already has Angle 0.
  /// Clears stale `formulas['Angle']` (e.g. Master Inh) so group rebuild
  /// cannot resurrect inherited rotation.
  void rotateShape(int id, double angleRad, {bool transient = false}) {
    final page = currentPage;
    final s = page?.findShapeById(id);
    if (s == null || s.locked || isOnLockedLayer(id)) return;
    final movedIds = _subtreeIds(<int>{id});
    updateCurrentPage(
      (p) {
        final sh = p.findShapeById(id);
        if (sh == null) return p;
        if (sh.isGlueableConnector) {
          // Absolute local heading → delta from current (usually 0 after bake).
          // Exclude this connector from reroute so glue does not undo the turn
          // (same as [rotateSelection90]).
          final delta = angleRad - sh.angleRad;
          return p
              .updateShapeById(id, (s) => _rotate1DAboutPin(p, s, delta))
              .recalculateFormulas(changedShapeIds: movedIds)
              .rerouteConnectors(
                movedShapeIds: <int>{
                  for (final mid in movedIds)
                    if (mid != id) mid,
                },
              );
        }
        return p
            .updateShapeById(
              id,
              (s) => _withLiteralAngle(s, angleRad),
            )
            .recalculateFormulas(changedShapeIds: movedIds)
            .rerouteConnectors(movedShapeIds: movedIds);
      },
      transient: transient,
    );
  }

  /// Drop `formulas['Angle']` and set a literal angle (UI rotate / arrange).
  static VsdxShape _withLiteralAngle(VsdxShape s, double angleRad) {
    if (!s.formulas.containsKey('Angle')) {
      return s.copyWith(angleRad: angleRad).syncInkEndpoints();
    }
    final next = Map<String, String>.from(s.formulas)..remove('Angle');
    return s.copyWith(angleRad: angleRad, formulas: next).syncInkEndpoints();
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
    bool resizeChildren = true,
    bool preservePageTopLeft = false,
  }) {
    final page = currentPage;
    if (page == null) return;
    final s = page.findShapeById(id);
    if (s == null || s.locked || isOnLockedLayer(id)) return;
    final reflowPool = SwimlaneOps.isPool(s);
    final reflowLane = SwimlaneOps.isLane(s);
    final reflowTable = TableOps.isTable(s);
    final lanePoolId = reflowLane ? page.findParentId(id) : null;
    final movedRoots = <int>{id};
    if (lanePoolId != null) movedRoots.add(lanePoolId);
    final movedIds = _subtreeIds(movedRoots);
    updateCurrentPage(
      (p) {
        final beforeAabb =
            preservePageTopLeft ? p.shapePageAabb(id) : null;
        var next = p.updateShapeById(
          id,
          (sh) {
            // Glueable connectors: scale Begin→End like applyOps so Arrange /
            // handles stay in sync with Visio Width=EndX−BeginX (not AABB-only).
            if (sh.isGlueableConnector &&
                sh.beginX != null &&
                sh.beginY != null &&
                sh.endX != null &&
                sh.endY != null) {
              final ax = sh.beginX!;
              final ay = sh.beginY!;
              final bx = sh.endX!;
              final by = sh.endY!;
              final sx = sh.width.abs() < 1e-12
                  ? 1.0
                  : width.abs() / sh.width.abs();
              final sy = sh.height.abs() < 1e-12
                  ? 1.0
                  : height.abs() / sh.height.abs();
              final newEx = ax + (bx - ax) * sx;
              final newEy = ay + (by - ay) * sy;
              final newWps = <Offset2D>[
                for (final pt in sh.waypoints)
                  Offset2D(ax + (pt.x - ax) * sx, ay + (pt.y - ay) * sy),
              ];
              final poly = <Offset2D>[
                Offset2D(ax, ay),
                ...newWps,
                Offset2D(newEx, newEy),
              ];
              return sh
                  .copyWith(
                    beginX: ax,
                    beginY: ay,
                    endX: newEx,
                    endY: newEy,
                    pinX: (ax + newEx) / 2,
                    pinY: (ay + newEy) / 2,
                    width: newEx - ax,
                    height: newEy - ay,
                    waypoints: newWps,
                  )
                  .reshapeAsPolyline(poly);
            }
            final sx = sh.width == 0 ? 1.0 : width / sh.width;
            final sy = sh.height == 0 ? 1.0 : height / sh.height;
            final resized = sh.resizeTo(
              pinX: pinX,
              pinY: pinY,
              width: width,
              height: height,
            );
            // Groups: scale children with the box (draw.io). Skip pools/lanes/
            // tables (they reflow) and pure pin moves (sx≈sy≈1).
            if (!resizeChildren ||
                sh.shapeKind != VsdxShapeKind.group ||
                sh.children.isEmpty ||
                ((sx - 1).abs() < 1e-12 && (sy - 1).abs() < 1e-12)) {
              return resized;
            }
            final oldOx = sh.effectiveLocPinX;
            final oldOy = sh.effectiveLocPinY;
            final newOx = resized.effectiveLocPinX;
            final newOy = resized.effectiveLocPinY;
            return resized.copyWith(
              children: <VsdxShape>[
                for (final c in sh.children)
                  _scaleGroupChild(c, sx, sy, oldOx, oldOy, newOx, newOy),
              ],
            );
          },
        );
        // Pool resize: scale pool-level (non-lane) content with the frame,
        // then equal-tile lanes into the new bounds.
        if (reflowPool) {
          final resized = next.findShapeById(id)!;
          final sx = s.width == 0 ? 1.0 : resized.width / s.width;
          final sy = s.height == 0 ? 1.0 : resized.height / s.height;
          next = next.updateShapeById(id, (sh) {
            var host = sh;
            if ((sx - 1).abs() > 1e-12 || (sy - 1).abs() > 1e-12) {
              host = sh.copyWith(
                children: <VsdxShape>[
                  ...SwimlaneOps.lanesOf(sh),
                  for (final c in SwimlaneOps.nonLaneChildren(sh))
                    VsdxPage.scaleChildInFrame(
                      c,
                      sx,
                      sy,
                      s.effectiveLocPinX,
                      s.effectiveLocPinY,
                      sh.effectiveLocPinX,
                      sh.effectiveLocPinY,
                    ),
                ],
              );
            }
            return SwimlaneOps.layoutLanes(host);
          });
        } else if (reflowLane && lanePoolId != null) {
          // Lane resize: keep sibling sizes, grow/shrink the pool.
          final host = next.findShapeById(lanePoolId);
          if (host != null && SwimlaneOps.isPool(host)) {
            next = next.updateShapeById(
              lanePoolId,
              SwimlaneOps.layoutLanesPreservingSizes,
            );
          }
        } else if (reflowTable) {
          next = next.updateShapeById(id, TableOps.layoutCells);
        }
        if (beforeAabb != null) {
          final afterAabb = next.shapePageAabb(id);
          if (afterAabb != null) {
            final dx = beforeAabb.left - afterAabb.left;
            final dy = beforeAabb.top - afterAabb.top;
            if (dx.abs() > 1e-9 || dy.abs() > 1e-9) {
              next = _nudgeShapeOnPage(next, id, dx, dy);
            }
          }
        }
        // Direct Begin→End bake on a glueable connector must not be undone by
        // re-gluing that same connector (Arrange size / handles).
        final skipRerouteSelf =
            s.isGlueableConnector ? <int>{id} : const <int>{};
        return next
            .recalculateFormulas(changedShapeIds: movedIds)
            .rerouteConnectors(
              movedShapeIds: <int>{
                for (final mid in movedIds)
                  if (!skipRerouteSelf.contains(mid)) mid,
              },
            );
      },
      transient: transient,
    );
  }

  /// Scale a group child: map offsets from [oldOx],[oldOy] into the resized
  /// parent's LocPin frame ([newOx],[newOy]).
  static VsdxShape _scaleGroupChild(
    VsdxShape c,
    double sx,
    double sy,
    double oldOx,
    double oldOy,
    double newOx,
    double newOy,
  ) =>
      VsdxPage.scaleChildInFrame(c, sx, sy, oldOx, oldOy, newOx, newOy);

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

  /// Drop `<Connect>` rows that reference any id in [ids] and clear matching
  /// BegTrigger / EndTrigger XFTRIGGER cells.
  static VsdxPage _pruneConnectsReferencing(VsdxPage page, Set<int> ids) =>
      page.pruneConnectsReferencing(ids);

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
      final page = doc.pages[pi];
      void walk(VsdxShape s) {
        // Match paint / hit-test: skip hidden layers; do not descend into
        // folded containers (children are not visible until unfold).
        if (!page.isShapeVisible(s)) return;
        final text = _shapeLabel(s);
        final hayText = _findMatchCase ? text : text.toLowerCase();
        final hayName = _findMatchCase ? s.name : s.name.toLowerCase();
        if (_haystackMatches(hayText, needle) ||
            _haystackMatches(hayName, needle)) {
          matches.add((pageIndex: pi, shapeId: s.id));
        }
        if (s.collapsed) return;
        for (final c in s.children) {
          walk(c);
        }
      }

      for (final s in page.shapes) {
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

  /// Advance the find cursor without changing page / selection.
  void _advanceFindIndexSilently() {
    if (_findMatches.isEmpty) return;
    _findIndex = (_findIndex + 1) % _findMatches.length;
    notifyListeners();
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
    // Remember page + selection before Find may jump, so undo restores both.
    final undoPage = _currentPageIndex;
    final undoSel = Set<int>.of(_selection);
    final doc = _document;
    if (doc == null ||
        hit.pageIndex < 0 ||
        hit.pageIndex >= doc.pages.length) {
      return;
    }
    // Resolve the hit without mutating page/selection yet — name-only and
    // locked hits must not strand the user on another page with no undo.
    final hitPage = doc.pages[hit.pageIndex];
    final shape = hitPage.findShapeById(hit.shapeId);
    if (shape == null) return;
    if (shape.locked ||
        _shapeOnLockedLayer(hitPage, shape) ||
        !hitPage.isShapeTreeVisible(hit.shapeId)) {
      _advanceFindIndexSilently();
      return;
    }
    final text = _shapeLabel(shape);
    final next = replaceFirstMatch(
      text,
      q,
      replacement,
      matchCase: _findMatchCase,
      wholeWord: _findWholeWord,
    );
    if (next == text) {
      // Name-only match — advance the find cursor but do not jump page /
      // selection (findNext would call _selectAndRevealFind).
      _advanceFindIndexSilently();
      return;
    }
    if (_currentPageIndex != hit.pageIndex) {
      _leaveConnectionPointEdit();
      _currentPageIndex = hit.pageIndex;
      _selection.clear();
    }
    updateCurrentPage(
      (p) => p.updateShapeById(hit.shapeId, (s) => _withLabelText(s, next)),
      undoPageIndex: undoPage,
      undoSelection: undoSel,
    );
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
  /// (one undo step). Shape names are left alone. Locked shapes, shapes on
  /// locked layers, hidden-layer shapes, and children of folded containers are
  /// skipped (same scope as Find matches).
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
        if (!page.isShapeVisible(s)) return s;
        final text = _shapeLabel(s);
        final nextText = replaceAllMatch(
          text,
          q,
          replacement,
          matchCase: _findMatchCase,
          wholeWord: _findWholeWord,
        );
        var next = s;
        if (nextText != text &&
            !s.locked &&
            !page.isShapeTreeOnLockedLayer(s.id)) {
          next = _withLabelText(s, nextText);
          pageChanged = true;
        }
        if (next.collapsed || next.children.isEmpty) return next;
        return next.copyWith(
          children: <VsdxShape>[
            for (final c in next.children) transform(c),
          ],
        );
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
    _cleanDocument = _document;
    _importedFromVsd = false;
    notifyListeners();
  }

  /// Keep [_currentPageIndex] valid after undo/redo that add or remove pages.
  /// Without this, undoing [addPage] left the tab index pointing past the last
  /// page so the page chip strip highlighted nothing.
  void _clampPageIndex() {
    final doc = _document;
    if (doc == null || doc.pages.isEmpty) {
      _currentPageIndex = 0;
      return;
    }
    if (_currentPageIndex >= doc.pages.length) {
      _currentPageIndex = doc.pages.length - 1;
    } else if (_currentPageIndex < 0) {
      _currentPageIndex = 0;
    }
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
    _importedFromVsd = false;
    _currentPageIndex = 0;
    _error = null;
    _resetHistory();
    notifyListeners();
  }

  /// Parse [bytes] into a document and make it the active file.
  ///
  /// Accepts OPC `.vsdx` (and siblings) or legacy binary `.vsd`. Binary imports
  /// synthesise a `.vsdx` baseline; [importedFromVsd] is set and [filePath] is
  /// cleared so the next Save prompts for a `.vsdx` location.
  Future<void> openBytes(
    Uint8List bytes, {
    String? path,
    String? name,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final result = parseVisio(bytes);
      _document = result.document;
      _originalBytes = result.originalBytes;
      _importedFromVsd = result.importedFromVsd;
      if (result.importedFromVsd) {
        // Never overwrite the source `.vsd` with OPC bytes.
        _filePath = null;
        final base = name ?? _basename(path) ?? 'drawing.vsd';
        _fileName = base.toLowerCase().endsWith('.vsd')
            ? '${base.substring(0, base.length - 4)}.vsdx'
            : (base.toLowerCase().endsWith('.vsdx') ? base : '$base.vsdx');
      } else {
        _filePath = path;
        _fileName = name ?? _basename(path);
      }
      _currentPageIndex = 0;
      _resetHistory();
    } catch (e) {
      _error = e;
      _document = null;
      _originalBytes = null;
      _filePath = null;
      _fileName = null;
      _importedFromVsd = false;
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
    _importedFromVsd = false;
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
    _txnPageIndex = null;
    _txnSelection = null;
    _dirty = false;
    _cleanDocument = _document;
    _clearFindState();
    _memoFill = null;
    _memoLine = null;
    _memoSoftEdgesInches = 0.05;
    _imageSeq = 0;
    // Page guides are keyed by page id; empty docs reuse id 0, so clear on
    // every fresh document load or the previous file's guides leak through.
    _pageGuides.clear();
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

/// One undo/redo snapshot: document, page the user was viewing, and selection.
class _HistoryEntry {
  const _HistoryEntry(this.document, this.pageIndex, this.selection);

  final VsdxDocument document;
  final int pageIndex;
  final Set<int> selection;
}
