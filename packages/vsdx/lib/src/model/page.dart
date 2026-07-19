/// One Visio "drawing page". Page size is stored in **inches** (see
/// `lib/utils/units.dart` for the normalisation policy).
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../utils/color.dart';
import 'connect.dart';
import 'fill.dart';
import 'geometry.dart';
import 'layer.dart';
import 'line.dart';
import 'obstacle_router.dart';
import 'perimeter.dart';
import 'shape.dart';
import 'shape_kind.dart';

/// PageSheet cells beyond width/height/colour (scale, page shadow, jumps,
/// margins). Required so newly-created pages round-trip like Visio / libvisio.
@immutable
class VsdxPageSheet {
  const VsdxPageSheet({
    this.shadowOffsetXInches = 0.125,
    this.shadowOffsetYInches = -0.125,
    this.pageScale = 1,
    this.pageScaleUnit = 'PT',
    this.drawingScale = 1,
    this.drawingScaleUnit = 'PT',
    this.drawingSizeType = 0,
    this.drawingScaleType = 0,
    this.drawingResizeType = 2,
    this.inhibitSnap = false,
    this.pageLockReplace = false,
    this.pageLockDuplicate = false,
    this.uiVisibility = 0,
    this.shadowType = 0,
    this.shadowObliqueAngle = 0,
    this.shadowScaleFactor = 1,
    this.pageShapeSplit = true,
    this.lineJumpCode,
    this.lineJumpStyle,
    this.marginLeftInches = 0,
    this.marginRightInches = 0,
    this.marginTopInches = 0,
    this.marginBottomInches = 0,
    this.printPageOrientation = 2,
    this.variationColorIndex,
    this.variationStyleIndex,
  });

  /// `ShdwOffsetX` / `ShdwOffsetY` — page-level drop-shadow offsets (inches).
  final double shadowOffsetXInches;
  final double shadowOffsetYInches;

  /// `PageScale` — usually `V="1" U="PT"`.
  final double pageScale;
  final String? pageScaleUnit;

  /// `DrawingScale` — usually `V="1" U="PT"`.
  final double drawingScale;
  final String? drawingScaleUnit;

  final int drawingSizeType;
  final int drawingScaleType;
  final int drawingResizeType;
  final bool inhibitSnap;
  final bool pageLockReplace;
  final bool pageLockDuplicate;
  final int uiVisibility;
  final int shadowType;
  final double shadowObliqueAngle;
  final double shadowScaleFactor;
  final bool pageShapeSplit;

  /// `LineJumpCode` / `LineJumpStyle` — optional; absent on some blank pages.
  final int? lineJumpCode;
  final int? lineJumpStyle;

  final double marginLeftInches;
  final double marginRightInches;
  final double marginTopInches;
  final double marginBottomInches;

  /// `PrintPageOrientation` — 1 = portrait, 2 = landscape (Visio).
  final int printPageOrientation;

  /// `VariationColorIndex` / `VariationStyleIndex` — theme variation selectors
  /// libvisio reads to resolve THEMEVAL() colours. Optional (absent on many
  /// pages / older documents).
  final int? variationColorIndex;
  final int? variationStyleIndex;

  static const VsdxPageSheet defaults = VsdxPageSheet();

  VsdxPageSheet copyWith({
    double? shadowOffsetXInches,
    double? shadowOffsetYInches,
    double? pageScale,
    String? pageScaleUnit,
    double? drawingScale,
    String? drawingScaleUnit,
    int? drawingSizeType,
    int? drawingScaleType,
    int? drawingResizeType,
    bool? inhibitSnap,
    bool? pageLockReplace,
    bool? pageLockDuplicate,
    int? uiVisibility,
    int? shadowType,
    double? shadowObliqueAngle,
    double? shadowScaleFactor,
    bool? pageShapeSplit,
    int? lineJumpCode,
    int? lineJumpStyle,
    double? marginLeftInches,
    double? marginRightInches,
    double? marginTopInches,
    double? marginBottomInches,
    int? printPageOrientation,
    int? variationColorIndex,
    int? variationStyleIndex,
  }) =>
      VsdxPageSheet(
        shadowOffsetXInches:
            shadowOffsetXInches ?? this.shadowOffsetXInches,
        shadowOffsetYInches:
            shadowOffsetYInches ?? this.shadowOffsetYInches,
        pageScale: pageScale ?? this.pageScale,
        pageScaleUnit: pageScaleUnit ?? this.pageScaleUnit,
        drawingScale: drawingScale ?? this.drawingScale,
        drawingScaleUnit: drawingScaleUnit ?? this.drawingScaleUnit,
        drawingSizeType: drawingSizeType ?? this.drawingSizeType,
        drawingScaleType: drawingScaleType ?? this.drawingScaleType,
        drawingResizeType: drawingResizeType ?? this.drawingResizeType,
        inhibitSnap: inhibitSnap ?? this.inhibitSnap,
        pageLockReplace: pageLockReplace ?? this.pageLockReplace,
        pageLockDuplicate: pageLockDuplicate ?? this.pageLockDuplicate,
        uiVisibility: uiVisibility ?? this.uiVisibility,
        shadowType: shadowType ?? this.shadowType,
        shadowObliqueAngle: shadowObliqueAngle ?? this.shadowObliqueAngle,
        shadowScaleFactor: shadowScaleFactor ?? this.shadowScaleFactor,
        pageShapeSplit: pageShapeSplit ?? this.pageShapeSplit,
        lineJumpCode: lineJumpCode ?? this.lineJumpCode,
        lineJumpStyle: lineJumpStyle ?? this.lineJumpStyle,
        marginLeftInches: marginLeftInches ?? this.marginLeftInches,
        marginRightInches: marginRightInches ?? this.marginRightInches,
        marginTopInches: marginTopInches ?? this.marginTopInches,
        marginBottomInches: marginBottomInches ?? this.marginBottomInches,
        printPageOrientation:
            printPageOrientation ?? this.printPageOrientation,
        variationColorIndex: variationColorIndex ?? this.variationColorIndex,
        variationStyleIndex: variationStyleIndex ?? this.variationStyleIndex,
      );

  @override
  bool operator ==(Object other) =>
      other is VsdxPageSheet &&
      other.shadowOffsetXInches == shadowOffsetXInches &&
      other.shadowOffsetYInches == shadowOffsetYInches &&
      other.pageScale == pageScale &&
      other.pageScaleUnit == pageScaleUnit &&
      other.drawingScale == drawingScale &&
      other.drawingScaleUnit == drawingScaleUnit &&
      other.drawingSizeType == drawingSizeType &&
      other.drawingScaleType == drawingScaleType &&
      other.drawingResizeType == drawingResizeType &&
      other.inhibitSnap == inhibitSnap &&
      other.pageLockReplace == pageLockReplace &&
      other.pageLockDuplicate == pageLockDuplicate &&
      other.uiVisibility == uiVisibility &&
      other.shadowType == shadowType &&
      other.shadowObliqueAngle == shadowObliqueAngle &&
      other.shadowScaleFactor == shadowScaleFactor &&
      other.pageShapeSplit == pageShapeSplit &&
      other.lineJumpCode == lineJumpCode &&
      other.lineJumpStyle == lineJumpStyle &&
      other.marginLeftInches == marginLeftInches &&
      other.marginRightInches == marginRightInches &&
      other.marginTopInches == marginTopInches &&
      other.marginBottomInches == marginBottomInches &&
      other.printPageOrientation == printPageOrientation &&
      other.variationColorIndex == variationColorIndex &&
      other.variationStyleIndex == variationStyleIndex;

  @override
  int get hashCode => Object.hashAll([
        shadowOffsetXInches,
        shadowOffsetYInches,
        pageScale,
        pageScaleUnit,
        drawingScale,
        drawingScaleUnit,
        drawingSizeType,
        drawingScaleType,
        drawingResizeType,
        inhibitSnap,
        pageLockReplace,
        pageLockDuplicate,
        uiVisibility,
        shadowType,
        shadowObliqueAngle,
        shadowScaleFactor,
        pageShapeSplit,
        lineJumpCode,
        lineJumpStyle,
        marginLeftInches,
        marginRightInches,
        marginTopInches,
        marginBottomInches,
        printPageOrientation,
        variationColorIndex,
        variationStyleIndex,
      ]);
}

@immutable
class VsdxPage {
  const VsdxPage({
    required this.id,
    required this.name,
    required this.widthInches,
    required this.heightInches,
    required this.shapes,
    this.layers = const <VsdxLayer>[],
    this.connects = const <VsdxConnect>[],
    this.backgroundColor,
    this.isBackgroundPage = false,
    this.backgroundPageId,
    this.pageSheet = VsdxPageSheet.defaults,
    this.viewScale,
    this.viewCenterX,
    this.viewCenterY,
  });

  /// Visio internal page id; unique within the document.
  final int id;

  /// User-facing name (e.g. "Page-1", "Floor 2").
  final String name;

  final double widthInches;
  final double heightInches;

  /// Top-level shapes. Groups are nested via `VsdxShape.children`.
  final List<VsdxShape> shapes;

  /// Page-scoped layers. Empty list ⇒ no layer section on this page (every
  /// shape is drawn unconditionally).
  final List<VsdxLayer> layers;

  /// Page-level `<Connect>` rows. Mostly used by the connector router.
  final List<VsdxConnect> connects;

  /// `PageColor` cell — `null` ⇒ inherit document default (white).
  final VsdxColor? backgroundColor;

  /// `Background="1"` attribute on the Page element.
  final bool isBackgroundPage;

  /// `BackPage="N"` attribute — id of the background page rendered
  /// underneath this one (`null` when no background).
  final int? backgroundPageId;

  /// Remaining PageSheet cells (scale / shadow / jumps / margins).
  final VsdxPageSheet pageSheet;

  /// `ViewScale` / `ViewCenterX` / `ViewCenterY` attributes on `<Page>`.
  final double? viewScale;
  final double? viewCenterX;
  final double? viewCenterY;

  /// O(1) by-connector lookup. Lazily built each access — cheap because
  /// the list is usually tiny.
  ConnectIndex get connectIndex =>
      connects.isEmpty ? ConnectIndex.empty : ConnectIndex(connects);

  /// Convenience: the set of layer ids whose `visible == true`. Used by the
  /// renderer when filtering shapes.
  Set<int> get visibleLayerIds => {
        for (final l in layers)
          if (l.visible) l.id,
      };

  /// Whether [s] would be painted when layer visibility is respected
  /// (shapes with no layer membership are always visible).
  bool isShapeVisible(VsdxShape s) {
    if (s.layerMemberIds.isEmpty || layers.isEmpty) return true;
    return s.isOnAnyLayer(visibleLayerIds);
  }

  /// Whether [shapeId] is painted: [isShapeVisible] for it and every ancestor.
  /// Children of a hidden-layer group are not interactive even if they have no
  /// layer membership of their own (matches [VsdxPainter] early-out).
  bool isShapeTreeVisible(int shapeId) {
    int? id = shapeId;
    while (id != null) {
      final s = findShapeById(id);
      if (s == null || !isShapeVisible(s)) return false;
      id = findParentId(id);
    }
    return true;
  }

  /// Layer ids whose Visio `Print` flag is on — used by PDF / SVG / PNG export.
  Set<int> get printableLayerIds => {
        for (final l in layers)
          if (l.print) l.id,
      };

  /// Walk the shape tree (DFS) and return the shape with [id], or `null`.
  VsdxShape? findShapeById(int id) {
    for (final s in shapes) {
      final hit = _walk(s, id);
      if (hit != null) return hit;
    }
    return null;
  }

  static VsdxShape? _walk(VsdxShape s, int id) {
    if (s.id == id) return s;
    for (final c in s.children) {
      final hit = _walk(c, id);
      if (hit != null) return hit;
    }
    return null;
  }

  /// Sentinel for [copyWith] so callers can clear [backgroundPageId] to `null`
  /// (plain `null` would mean "leave unchanged").
  static const Object keepBackgroundPageId = Object();

  VsdxPage copyWith({
    int? id,
    String? name,
    double? widthInches,
    double? heightInches,
    List<VsdxShape>? shapes,
    List<VsdxLayer>? layers,
    List<VsdxConnect>? connects,
    VsdxColor? backgroundColor,
    bool? isBackgroundPage,
    Object? backgroundPageId = keepBackgroundPageId,
    VsdxPageSheet? pageSheet,
    double? viewScale,
    double? viewCenterX,
    double? viewCenterY,
  }) {
    return VsdxPage(
      id: id ?? this.id,
      name: name ?? this.name,
      widthInches: widthInches ?? this.widthInches,
      heightInches: heightInches ?? this.heightInches,
      shapes: shapes ?? this.shapes,
      layers: layers ?? this.layers,
      connects: connects ?? this.connects,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      isBackgroundPage: isBackgroundPage ?? this.isBackgroundPage,
      backgroundPageId: identical(backgroundPageId, keepBackgroundPageId)
          ? this.backgroundPageId
          : backgroundPageId as int?,
      pageSheet: pageSheet ?? this.pageSheet,
      viewScale: viewScale ?? this.viewScale,
      viewCenterX: viewCenterX ?? this.viewCenterX,
      viewCenterY: viewCenterY ?? this.viewCenterY,
    );
  }

  /// Returns a copy of this page with the shape identified by [id] replaced by
  /// `update(oldShape)`. Recurses into groups. Returns `this` (identical) when
  /// no shape matches, so callers can cheaply detect no-ops.
  VsdxPage updateShapeById(int id, VsdxShape Function(VsdxShape) update) {
    final (newShapes, changed) = _updateInList(shapes, id, update);
    return changed ? copyWith(shapes: newShapes) : this;
  }

  /// Re-evaluate ShapeSheet formulas across shapes on this page, resolving
  /// `Sheet.n!Cell` against sibling shapes (PinX/Y, Width/Height, Angle,
  /// LocPin*, Begin*/End*).
  ///
  /// When [changedShapeIds] is set, recalculates those shapes plus any shape
  /// whose formulas reference them. When omitted, recalculates every shape
  /// that carries formula sources. Up to four passes settle short dependency
  /// chains (A→B→C). Cycles leave unresolved cells at their prior `V`.
  VsdxPage recalculateFormulas({Set<int>? changedShapeIds}) {
    final index = <int, VsdxShape>{};
    void indexTree(VsdxShape s) {
      index[s.id] = s;
      for (final c in s.children) {
        indexTree(c);
      }
    }

    void rebuildIndex(VsdxPage page) {
      index.clear();
      for (final s in page.shapes) {
        indexTree(s);
      }
    }

    rebuildIndex(this);
    if (index.isEmpty) return this;

    final Set<int> targets;
    if (changedShapeIds == null || changedShapeIds.isEmpty) {
      targets = {
        for (final e in index.entries)
          if (e.value.formulaSources.isNotEmpty) e.key,
      };
    } else {
      targets = {...changedShapeIds};
      for (final e in index.entries) {
        if (e.value.referencesAnySheet(changedShapeIds)) {
          targets.add(e.key);
        }
      }
    }
    if (targets.isEmpty) return this;

    var page = this;
    for (var pass = 0; pass < 4; pass++) {
      rebuildIndex(page);
      double? lookup(int id, String cell) {
        final sh = index[id];
        if (sh == null) return null;
        return sh.lookupSheetCell(cell);
      }

      var any = false;
      for (final id in targets) {
        final s = index[id];
        if (s == null) continue;
        final next = s.recalculateLocalFormulas(sheetLookup: lookup);
        if (!identical(next, s)) {
          page = page.updateShapeById(id, (_) => next);
          any = true;
        }
      }
      if (!any) break;
    }
    return page;
  }

  static (List<VsdxShape>, bool) _updateInList(
    List<VsdxShape> list,
    int id,
    VsdxShape Function(VsdxShape) update,
  ) {
    var changed = false;
    final result = <VsdxShape>[];
    for (final s in list) {
      if (s.id == id) {
        final u = update(s);
        result.add(u);
        if (!identical(u, s)) changed = true;
      } else if (s.children.isNotEmpty) {
        final (newChildren, childChanged) = _updateInList(s.children, id, update);
        if (childChanged) {
          result.add(s.copyWith(children: newChildren));
          changed = true;
        } else {
          result.add(s);
        }
      } else {
        result.add(s);
      }
    }
    return (result, changed);
  }

  /// A new page with [shape] appended to the top-level shape list.
  VsdxPage addShape(VsdxShape shape) =>
      copyWith(shapes: <VsdxShape>[...shapes, shape]);

  /// A new page with the shape [id] removed (recursing into groups). Returns
  /// `this` (identical) when nothing matched.
  ///
  /// When [pruneConnects] is true (default), `<Connect>` rows that reference
  /// the removed shape or any of its descendants are dropped too. Pass
  /// `false` for temporary removals such as [reparentShape], which put the
  /// shape back on the page in the same edit.
  VsdxPage removeShapeById(int id, {bool pruneConnects = true}) {
    final victim = findShapeById(id);
    if (victim == null) return this;
    final removedIds = <int>{};
    void walk(VsdxShape s) {
      removedIds.add(s.id);
      for (final c in s.children) {
        walk(c);
      }
    }

    walk(victim);
    final (newShapes, changed) = _removeInList(shapes, id);
    if (!changed) return this;
    if (!pruneConnects || connects.isEmpty) {
      return copyWith(shapes: newShapes);
    }
    final nextConnects = <VsdxConnect>[
      for (final c in connects)
        if (!removedIds.contains(c.fromSheetId) &&
            !removedIds.contains(c.toSheetId))
          c,
    ];
    return copyWith(
      shapes: newShapes,
      connects: nextConnects.length == connects.length ? connects : nextConnects,
    );
  }

  static (List<VsdxShape>, bool) _removeInList(List<VsdxShape> list, int id) {
    var changed = false;
    final result = <VsdxShape>[];
    for (final s in list) {
      if (s.id == id) {
        changed = true;
        continue;
      }
      if (s.children.isNotEmpty) {
        final (nc, cc) = _removeInList(s.children, id);
        if (cc) {
          result.add(s.copyWith(children: nc));
          changed = true;
          continue;
        }
      }
      result.add(s);
    }
    return (result, changed);
  }

  /// Re-route glued connectors so their endpoints follow the current shapes
  /// they are connected to (via [connects]). Returns `this` unchanged when
  /// there are no connects.
  ///
  /// When [movedShapeIds] is supplied, only connectors glued to one of those
  /// shapes (or whose own id is listed) are re-routed; every other connector
  /// keeps its baked geometry untouched. This is what stops an edit to one part
  /// of an imported Visio drawing from re-routing — and thereby scrambling —
  /// hand-drawn / multi-bend connectors elsewhere on the page. Passing `null`
  /// re-routes all glued connectors (connector-level edits, tests).
  VsdxPage rerouteConnectors({Set<int>? movedShapeIds}) {
    if (connects.isEmpty) return this;
    final index = connectIndex;
    final connectorIds = <int>{for (final c in connects) c.fromSheetId};
    var next = this;
    for (final cid in connectorIds) {
      final connector = next.findShapeById(cid);
      if (connector == null) continue;
      VsdxShape? beginShape;
      VsdxShape? endShape;
      VsdxConnect? beginConnect;
      VsdxConnect? endConnect;
      for (final e in index.forConnector(cid)) {
        final target = next.findShapeById(e.toSheetId);
        if (target == null) continue;
        if (e.isBegin) {
          beginShape = target;
          beginConnect = e;
        } else if (e.isEnd) {
          endShape = target;
          endConnect = e;
        }
      }
      // Only re-route connectors affected by this edit; leave the rest (and
      // their authored geometry) alone.
      if (movedShapeIds != null &&
          !movedShapeIds.contains(cid) &&
          !(beginShape != null && movedShapeIds.contains(beginShape.id)) &&
          !(endShape != null && movedShapeIds.contains(endShape.id))) {
        continue;
      }
      // Nested connectors store Begin/End/waypoints in the *parent's* local
      // frame. Routing math is always in page inches — convert at the edges.
      final parentId = next.findParentId(cid);
      Offset2D connToPage(double x, double y) {
        final local = Offset2D(x, y);
        if (parentId == null) return local;
        return next.localToPageDeep(parentId, local);
      }

      Offset2D pageToConn(Offset2D page) {
        if (parentId == null) return page;
        return next.pageToLocalDeep(parentId, page);
      }

      // A fixed connection point (drawio blue point) pins the endpoint to a
      // specific spot on the shape; otherwise we attach on the edge aimed at
      // the opposite end.
      final beginFixed = _fixedPoint(beginShape, beginConnect);
      final endFixed = _fixedPoint(endShape, endConnect);
      final connBegin = connToPage(
        connector.beginX ?? connector.pinX,
        connector.beginY ?? connector.pinY,
      );
      final connEnd = connToPage(
        connector.endX ?? connector.pinX,
        connector.endY ?? connector.pinY,
      );
      // Reference points used to aim edge attachments at the opposite end.
      final beginPin =
          beginShape != null ? next.shapePinPage(beginShape.id) : null;
      final endPin = endShape != null ? next.shapePinPage(endShape.id) : null;
      final refBx = beginFixed?.x ?? beginPin?.x ?? connBegin.x;
      final refBy = beginFixed?.y ?? beginPin?.y ?? connBegin.y;
      final refEx = endFixed?.x ?? endPin?.x ?? connEnd.x;
      final refEy = endFixed?.y ?? endPin?.y ?? connEnd.y;
      final (ax, ay) = beginFixed != null
          ? (beginFixed.x, beginFixed.y)
          : beginShape != null
              ? _perimeterPoint(beginShape, refEx, refEy)
              : (refBx, refBy);
      final (bx, by) = endFixed != null
          ? (endFixed.x, endFixed.y)
          : endShape != null
              ? _perimeterPoint(endShape, refBx, refBy)
              : (refEx, refEy);
      final exclude = <int>{
        cid,
        if (beginShape != null) beginShape.id,
        if (endShape != null) endShape.id,
      };
      final pageWaypoints = <Offset2D>[
        for (final w in connector.waypoints) connToPage(w.x, w.y),
      ];
      final control = pageWaypoints.isNotEmpty
          ? <Offset2D>[
              Offset2D(ax, ay),
              ...pageWaypoints,
              Offset2D(bx, by),
            ]
          : connector.straightRoute
              ? <Offset2D>[Offset2D(ax, ay), Offset2D(bx, by)]
              : next._autoRoute(ax, ay, bx, by, excludeIds: exclude);
      final geometry = _bakeRoute(control,
          curved: connector.curved, rounded: connector.rounded);
      final localGeom = <Offset2D>[for (final p in geometry) pageToConn(p)];
      final localWaypoints = pageWaypoints.isEmpty
          ? null
          : <Offset2D>[
              for (final p in control.skip(1).take(control.length - 2))
                pageToConn(p),
            ];
      next = next.updateShapeById(
        cid,
        (s) => (localWaypoints != null
                ? s.copyWith(waypoints: localWaypoints)
                : s)
            .reshapeAsPolyline(localGeom),
      );
    }
    return next;
  }

  /// Page-inch polyline for a geometry-less 1-D connector as the canvas paints
  /// it: perimeter glue (when [connects] exist) + [ObstacleRouter] avoidance.
  ///
  /// Nested connectors store Begin/End in the *parent* local frame — those are
  /// lifted to page inches before routing.
  ///
  /// Used by SVG/PDF export so dynamic connectors match on-screen routing.
  List<Offset2D> autoRoutedConnectorPolyline(VsdxShape connector) {
    if (!connector.is1D) return const <Offset2D>[];
    final rawBx = connector.beginX;
    final rawBy = connector.beginY;
    final rawEx = connector.endX;
    final rawEy = connector.endY;
    if (rawBx == null || rawBy == null || rawEx == null || rawEy == null) {
      return const <Offset2D>[];
    }

    // Nested Begin/End live in the parent frame (see [rerouteConnectors]).
    final parentId = findParentId(connector.id);
    Offset2D toPage(double x, double y) {
      if (parentId == null) return Offset2D(x, y);
      return localToPageDeep(parentId, Offset2D(x, y));
    }

    final begin = toPage(rawBx, rawBy);
    final end = toPage(rawEx, rawEy);
    final bx = begin.x;
    final by = begin.y;
    final ex = end.x;
    final ey = end.y;

    if (connector.waypoints.isNotEmpty) {
      final wps = parentId == null
          ? connector.waypoints
          : <Offset2D>[
              for (final w in connector.waypoints)
                localToPageDeep(parentId, w),
            ];
      return <Offset2D>[Offset2D(bx, by), ...wps, Offset2D(ex, ey)];
    }
    if (connector.straightRoute) {
      return <Offset2D>[Offset2D(bx, by), Offset2D(ex, ey)];
    }

    var ax = bx;
    var ay = by;
    var zx = ex;
    var zy = ey;
    final exclude = <int>{connector.id};
    for (final c in connectIndex.forConnector(connector.id)) {
      final target = findShapeById(c.toSheetId);
      if (target == null) continue;
      exclude.add(target.id);
      if (c.isBegin) {
        final hit = perimeterAttach(target.id, ex, ey);
        ax = hit.x;
        ay = hit.y;
      } else if (c.isEnd) {
        final hit = perimeterAttach(target.id, bx, by);
        zx = hit.x;
        zy = hit.y;
      }
    }
    return _autoRoute(ax, ay, zx, zy, excludeIds: exclude);
  }

  /// Drawn connector polyline in **page** inches: baked MoveTo/LineTo geometry
  /// when present, otherwise [autoRoutedConnectorPolyline]. Walks nested
  /// shapes correctly for SVG line-jump collection.
  List<Offset2D> drawnConnectorPagePolyline(VsdxShape s) {
    if (!s.is1D) return const <Offset2D>[];
    if (s.hasGeometry && !s.curved && !s.rounded) {
      final local = <Offset2D>[];
      for (final g in s.geometries) {
        if (g.noShow) continue;
        local.clear();
        var ok = true;
        for (final c in g.commands) {
          if (c is MoveTo) {
            local.add(Offset2D(c.x, c.y));
          } else if (c is LineTo) {
            local.add(Offset2D(c.x, c.y));
          } else {
            ok = false;
            break;
          }
        }
        if (ok && local.length >= 2) {
          return <Offset2D>[
            for (final p in local) localToPageDeep(s.id, p),
          ];
        }
      }
    }
    return autoRoutedConnectorPolyline(s);
  }

  /// The drawn route of connector [s] in page inches: begin → waypoints → end,
  /// or the straight / elbow route when it has no explicit waypoints.
  ///
  /// Sharp auto-routes (including obstacle-avoiding polylines) are recovered
  /// from baked geometry so labels and bend handles match what is drawn.
  /// Curved / rounded connectors keep the control polyline (waypoints or
  /// elbow) because their geometry is a dense sample.
  static List<Offset2D> connectorRoute(VsdxShape s) {
    final ax = s.beginX ?? s.pinX, ay = s.beginY ?? s.pinY;
    final bx = s.endX ?? s.pinX, by = s.endY ?? s.pinY;
    if (s.waypoints.isNotEmpty) {
      return <Offset2D>[Offset2D(ax, ay), ...s.waypoints, Offset2D(bx, by)];
    }
    if (s.straightRoute) return <Offset2D>[Offset2D(ax, ay), Offset2D(bx, by)];
    if (!s.curved && !s.rounded) {
      final fromGeom = _polylineFromGeometry(s);
      if (fromGeom != null && fromGeom.length >= 2) return fromGeom;
    }
    return _elbowRoute(ax, ay, bx, by);
  }

  /// Recover a page-space polyline from a 1-D shape's first geometry section
  /// (MoveTo / LineTo only). Returns `null` when geometry is missing or not a
  /// simple polyline.
  ///
  /// Maps local → page via `pin − LocPin` (Visio Begin-origin connectors:
  /// local (0,0) is Begin). Avoids the old AABB `pin − size/2` assumption.
  static List<Offset2D>? _polylineFromGeometry(VsdxShape s) {
    if (s.geometries.isEmpty) return null;
    final cmds = s.geometries.first.commands;
    if (cmds.length < 2) return null;
    final ox = s.pinX - s.effectiveLocPinX;
    final oy = s.pinY - s.effectiveLocPinY;
    final pts = <Offset2D>[];
    for (final c in cmds) {
      if (c is MoveTo) {
        pts.add(Offset2D(c.x + ox, c.y + oy));
      } else if (c is LineTo) {
        pts.add(Offset2D(c.x + ox, c.y + oy));
      } else {
        return null;
      }
    }
    return pts.length >= 2 ? pts : null;
  }

  /// The point half-way along connector [s]'s drawn route (by arc length), in
  /// page inches. This is where a connector's text label sits (drawio-style
  /// edge labels), and where the in-place editor anchors. Falls back to the
  /// shape's pin for degenerate / zero-length routes.
  static Offset2D connectorMidpoint(VsdxShape s) {
    final route = connectorRoute(s);
    if (route.isEmpty) return Offset2D(s.pinX, s.pinY);
    if (route.length == 1) return route.first;
    var total = 0.0;
    for (var i = 0; i < route.length - 1; i++) {
      total += _segLength(route[i], route[i + 1]);
    }
    if (total <= 0) return route.first;
    var remaining = total / 2;
    for (var i = 0; i < route.length - 1; i++) {
      final len = _segLength(route[i], route[i + 1]);
      if (len >= remaining) {
        final t = len == 0 ? 0.0 : remaining / len;
        return Offset2D(
          route[i].x + (route[i + 1].x - route[i].x) * t,
          route[i].y + (route[i + 1].y - route[i].y) * t,
        );
      }
      remaining -= len;
    }
    return route.last;
  }

  static double _segLength(Offset2D a, Offset2D b) {
    final dx = a.x - b.x, dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Set the interior [waypoints] of connector [id] (page inches) and rebuild
  /// its geometry; glued endpoints are re-derived by [rerouteConnectors].
  VsdxPage setConnectorWaypoints(int id, List<Offset2D> waypoints) {
    final s = findShapeById(id);
    if (s == null || !s.is1D) return this;
    final control = connectorRoute(s.copyWith(waypoints: waypoints));
    final geometry = _bakeRoute(control, curved: s.curved, rounded: s.rounded);
    final next = updateShapeById(
      id,
      (sh) => sh.copyWith(waypoints: waypoints).reshapeAsPolyline(geometry),
    );
    return next.rerouteConnectors(movedShapeIds: <int>{id});
  }

  /// Move / reconnect one end of connector [id] (drawio endpoint editing).
  ///
  /// When [targetShapeId] is non-null the affected end is **glued** to that
  /// shape — its `<Connect>` row is added / replaced and [rerouteConnectors]
  /// then attaches the endpoint. With [connectionPointIndex] the end is pinned
  /// to that **fixed connection point** (materialising the standard point set
  /// on the target when it has none), otherwise it glues to the whole shape
  /// (edge attach). When [targetShapeId] is `null` the end is **detached** (its
  /// `<Connect>` row removed) and floats at page point ([x],[y]). Returns
  /// `this` unchanged if [id] is not a 1-D shape.
  VsdxPage setConnectorEndpoint(
    int id, {
    required bool begin,
    int? targetShapeId,
    int? connectionPointIndex,
    required double x,
    required double y,
  }) {
    final s = findShapeById(id);
    if (s == null || !s.is1D) return this;

    // Materialise the standard connection points on the target when pinning to
    // a fixed point and the shape has none yet (so the point round-trips).
    // Skip locked / locked-layer targets — glue may still reference the index
    // via [effectiveConnectionPoints], but must not mutate a locked shape.
    var base = this;
    if (targetShapeId != null && connectionPointIndex != null) {
      final target = base.findShapeById(targetShapeId);
      if (target != null &&
          target.connectionPoints.isEmpty &&
          !target.locked &&
          !base.isShapeTreeOnLockedLayer(targetShapeId)) {
        base = base.updateShapeById(
          targetShapeId,
          (t) => t.copyWith(
            connectionPoints:
                defaultConnectionPoints(t.width, t.height),
          ),
        );
      }
    }

    // Rebuild the connects list: drop this connector's row for the affected
    // end, then append a fresh glue row (whole-shape or a fixed point).
    final fixedIdx = targetShapeId != null ? connectionPointIndex : null;
    int? beginTarget;
    int? endTarget;
    for (final c in base.connects) {
      if (c.fromSheetId != id) continue;
      if (c.isBegin) beginTarget = c.toSheetId;
      if (c.isEnd) endTarget = c.toSheetId;
    }
    if (begin) {
      beginTarget = targetShapeId;
    } else {
      endTarget = targetShapeId;
    }
    final nextConnects = <VsdxConnect>[
      for (final c in base.connects)
        if (!(c.fromSheetId == id && (begin ? c.isBegin : c.isEnd))) c,
      if (targetShapeId != null)
        VsdxConnect(
          fromSheetId: id,
          fromCell: begin ? 'BeginX' : 'EndX',
          fromPart: begin ? 9 : 12,
          toSheetId: targetShapeId,
          toCell: fixedIdx != null ? 'Connections.X${fixedIdx + 1}' : 'PinX',
          toPart: fixedIdx != null ? 100 + fixedIdx : 3,
        ),
    ];

    // Seed the moved endpoint; reroute refines glued ends to the attach point.
    final ax = begin ? x : (s.beginX ?? s.pinX);
    final ay = begin ? y : (s.beginY ?? s.pinY);
    final bx = begin ? (s.endX ?? s.pinX) : x;
    final by = begin ? (s.endY ?? s.pinY) : y;
    final control = s.waypoints.isNotEmpty
        ? <Offset2D>[Offset2D(ax, ay), ...s.waypoints, Offset2D(bx, by)]
        : s.straightRoute
            ? <Offset2D>[Offset2D(ax, ay), Offset2D(bx, by)]
            : _elbowRoute(ax, ay, bx, by);
    final geometry = _bakeRoute(control, curved: s.curved, rounded: s.rounded);
    final next = base
        .updateShapeById(
          id,
          (sh) => _withGlueTriggers(
            sh.reshapeAsPolyline(geometry),
            beginTarget: beginTarget,
            endTarget: endTarget,
          ),
        )
        .copyWith(connects: nextConnects);
    return next.rerouteConnectors(movedShapeIds: <int>{id});
  }

  /// Keep BegTrigger / EndTrigger XFTRIGGER formulas aligned with Connect rows.
  static VsdxShape _withGlueTriggers(
    VsdxShape connector, {
    int? beginTarget,
    int? endTarget,
  }) {
    final formulas = Map<String, String>.from(connector.formulas);
    if (beginTarget != null) {
      formulas['BegTrigger'] = '_XFTRIGGER(Sheet.$beginTarget!EventXFMod)';
    } else {
      formulas.remove('BegTrigger');
    }
    if (endTarget != null) {
      formulas['EndTrigger'] = '_XFTRIGGER(Sheet.$endTarget!EventXFMod)';
    } else {
      formulas.remove('EndTrigger');
    }
    return connector.copyWith(formulas: formulas);
  }

  /// Remove connector [id]'s interior bend points, resetting it to the plain
  /// straight / elbow route (drawio's "Clear Waypoints").
  VsdxPage clearConnectorWaypoints(int id) =>
      setConnectorWaypoints(id, const <Offset2D>[]);

  /// The 0-based fixed connection-point index a [connect] references, or `null`
  /// for a whole-shape (`ToPart 3`) / edge glue. Visio encodes point `k` as
  /// `ToPart = 100 + k`.
  static int? fixedConnectionIndex(VsdxConnect? connect) {
    final p = connect?.toPart;
    if (p == null || p < 100) return null;
    return p - 100;
  }

  /// Map a shape-local point [local] (inches, origin bottom-left / Y-up) on [s]
  /// to parent-local (or page) inches, honouring pin, LocPin, rotation and flip.
  ///
  /// Matches the paint / bbox transform
  /// `T(pin) · R · S(±1) · T(-LocPin)`.
  static Offset2D localToPage(VsdxShape s, Offset2D local) {
    var dx = local.x - s.effectiveLocPinX;
    var dy = local.y - s.effectiveLocPinY;
    if (s.flipX) dx = -dx;
    if (s.flipY) dy = -dy;
    if (s.angleRad != 0) {
      final cosA = math.cos(s.angleRad), sinA = math.sin(s.angleRad);
      final rx = dx * cosA - dy * sinA;
      final ry = dx * sinA + dy * cosA;
      dx = rx;
      dy = ry;
    }
    return Offset2D(s.pinX + dx, s.pinY + dy);
  }

  /// Map a parent-local (or page) inch point back into [s]'s local coordinates
  /// (origin bottom-left / Y-up), honouring pin, LocPin, rotation and flip.
  /// Inverse of [localToPage].
  static Offset2D pageToLocal(VsdxShape s, Offset2D page) {
    var dx = page.x - s.pinX;
    var dy = page.y - s.pinY;
    if (s.angleRad != 0) {
      final cosA = math.cos(-s.angleRad), sinA = math.sin(-s.angleRad);
      final rx = dx * cosA - dy * sinA;
      final ry = dx * sinA + dy * cosA;
      dx = rx;
      dy = ry;
    }
    if (s.flipX) dx = -dx;
    if (s.flipY) dy = -dy;
    return Offset2D(dx + s.effectiveLocPinX, dy + s.effectiveLocPinY);
  }

  /// Page-inch position of connection point [index] on [s]. [index] is into
  /// [VsdxShape.connectionPoints] (shape-local inches, origin bottom-left).
  static Offset2D connectionPointPage(VsdxShape s, int index) =>
      localToPage(s, s.connectionPoints[index].offset);

  /// Effective connection points of [s] for display / snapping: its explicit
  /// points, or the standard default set (drawio) when it has none.
  static List<VsdxConnectionPoint> effectiveConnectionPoints(VsdxShape s) =>
      s.connectionPoints.isNotEmpty
          ? s.connectionPoints
          : defaultConnectionPoints(s.width, s.height);

  /// Page position of [connect]'s fixed connection point on [shape], or `null`
  /// when the connect isn't pinned to a valid point.
  Offset2D? _fixedPoint(VsdxShape? shape, VsdxConnect? connect) {
    if (shape == null) return null;
    final idx = fixedConnectionIndex(connect);
    if (idx == null || idx < 0 || idx >= shape.connectionPoints.length) {
      return null;
    }
    // Nested Group children need ancestor composition.
    return localToPageDeep(shape.id, shape.connectionPoints[idx].offset);
  }

  /// Standard default connection points (drawio-style) for a [width]×[height]
  /// box, shape-local inches (origin bottom-left): top-centre, right-middle,
  /// bottom-centre, left-middle, centre — indices 0..4. Directions point
  /// outward (libvisio / Visio `DirX`/`DirY`).
  ///
  /// X/Y carry `Width*` / `Height*` formulas so 万兴图示 / Visio keep the
  /// points on the edges when the shape is resized.
  static List<VsdxConnectionPoint> defaultConnectionPoints(
          double width, double height) =>
      <VsdxConnectionPoint>[
        VsdxConnectionPoint(width / 2, height,
            dirX: 0, dirY: 1, xFormula: 'Width*0.5', yFormula: 'Height*1'), // 0 top
        VsdxConnectionPoint(width, height / 2,
            dirX: 1, dirY: 0, xFormula: 'Width*1', yFormula: 'Height*0.5'), // 1 right
        VsdxConnectionPoint(width / 2, 0,
            dirX: 0, dirY: -1, xFormula: 'Width*0.5', yFormula: 'Height*0'), // 2 bottom
        VsdxConnectionPoint(0, height / 2,
            dirX: -1, dirY: 0, xFormula: 'Width*0', yFormula: 'Height*0.5'), // 3 left
        VsdxConnectionPoint(width / 2, height / 2,
            xFormula: 'Width*0.5', yFormula: 'Height*0.5'), // 4 centre
      ];

  /// Build a connection point at shape-local ([x],[y]) with `Width*`/`Height*`
  /// formulas (so resize keeps the relative position) and an outward
  /// `DirX`/`DirY` inferred from the nearest edge.
  static VsdxConnectionPoint connectionPointAt(
    double x,
    double y,
    double width,
    double height,
  ) {
    final w = width <= 0 ? 1.0 : width;
    final h = height <= 0 ? 1.0 : height;
    final fx = (x / w).clamp(0.0, 1.0);
    final fy = (y / h).clamp(0.0, 1.0);
    final dl = x, dr = w - x, db = y, dt = h - y;
    var dirX = 0.0, dirY = 0.0;
    final m = math.min(math.min(dl, dr), math.min(db, dt));
    if (m == dl) {
      dirX = -1;
    } else if (m == dr) {
      dirX = 1;
    } else if (m == db) {
      dirY = -1;
    } else {
      dirY = 1;
    }
    return VsdxConnectionPoint(
      x,
      y,
      dirX: dirX,
      dirY: dirY,
      xFormula: 'Width*${_fracFormula(fx)}',
      yFormula: 'Height*${_fracFormula(fy)}',
    );
  }

  static String _fracFormula(double f) {
    final r = (f * 10000).round() / 10000;
    if ((r - r.roundToDouble()).abs() < 1e-9) return '${r.round()}';
    var s = r.toStringAsFixed(4);
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  /// True when [s] belongs to at least one layer with `Lock=1`.
  bool isShapeOnLockedLayer(VsdxShape s) {
    if (s.layerMemberIds.isEmpty || layers.isEmpty) return false;
    for (final id in s.layerMemberIds) {
      for (final l in layers) {
        if (l.id == id && l.locked) return true;
      }
    }
    return false;
  }

  /// True when [shapeId] or any ancestor sits on a locked layer.
  /// Children of a locked-layer group are not editable even with no membership.
  bool isShapeTreeOnLockedLayer(int shapeId) {
    int? id = shapeId;
    while (id != null) {
      final s = findShapeById(id);
      if (s == null) return false;
      if (isShapeOnLockedLayer(s)) return true;
      id = findParentId(id);
    }
    return false;
  }

  /// Ensure [id] has an explicit Connection section (materialise the default
  /// 5 points when empty). No-op for missing / 1-D / locked shapes.
  VsdxPage materializeConnectionPoints(int id) {
    final s = findShapeById(id);
    if (s == null ||
        s.is1D ||
        s.locked ||
        isShapeTreeOnLockedLayer(id) ||
        s.connectionPoints.isNotEmpty) {
      return this;
    }
    return updateShapeById(
      id,
      (t) => t.copyWith(
        connectionPoints: defaultConnectionPoints(t.width, t.height),
      ),
    );
  }

  /// Append a connection point at shape-local ([localX],[localY]) on [id]
  /// (materialising defaults first when the shape has none).
  VsdxPage addConnectionPoint(int id, double localX, double localY) {
    var next = materializeConnectionPoints(id);
    final s = next.findShapeById(id);
    if (s == null || s.is1D) return this;
    final pt = connectionPointAt(localX, localY, s.width, s.height);
    return next.updateShapeById(
      id,
      (t) => t.copyWith(
        connectionPoints: <VsdxConnectionPoint>[...t.connectionPoints, pt],
      ),
    );
  }

  /// Move connection point [index] on [id] to shape-local ([localX],[localY]).
  VsdxPage moveConnectionPoint(
    int id,
    int index,
    double localX,
    double localY,
  ) {
    final s = findShapeById(id);
    if (s == null ||
        s.is1D ||
        index < 0 ||
        index >= s.connectionPoints.length) {
      return this;
    }
    final built = connectionPointAt(localX, localY, s.width, s.height);
    final old = s.connectionPoints[index];
    final pts = List<VsdxConnectionPoint>.of(s.connectionPoints);
    pts[index] = VsdxConnectionPoint(
      built.x,
      built.y,
      dirX: built.dirX,
      dirY: built.dirY,
      type: old.type,
      autoGen: false,
      prompt: old.prompt,
      xFormula: built.xFormula,
      yFormula: built.yFormula,
    );
    // Glued connectors pin to fixed ToPart indices — refresh their endpoints.
    return updateShapeById(id, (t) => t.copyWith(connectionPoints: pts))
        .rerouteConnectors(movedShapeIds: <int>{id});
  }

  /// Remove connection point [index] on [id], remapping any connectors pinned
  /// to that point (deleted → whole-shape glue; higher indices shift down).
  VsdxPage removeConnectionPoint(int id, int index) {
    final s = findShapeById(id);
    if (s == null ||
        s.is1D ||
        index < 0 ||
        index >= s.connectionPoints.length) {
      return this;
    }
    final pts = List<VsdxConnectionPoint>.of(s.connectionPoints)..removeAt(index);
    final nextConnects = <VsdxConnect>[];
    for (final c in connects) {
      if (c.toSheetId != id) {
        nextConnects.add(c);
        continue;
      }
      final idx = fixedConnectionIndex(c);
      if (idx == null) {
        nextConnects.add(c);
      } else if (idx == index) {
        nextConnects.add(VsdxConnect(
          fromSheetId: c.fromSheetId,
          fromCell: c.fromCell,
          fromPart: c.fromPart,
          toSheetId: c.toSheetId,
          toCell: 'PinX',
          toPart: 3,
        ));
      } else if (idx > index) {
        final n = idx - 1;
        nextConnects.add(VsdxConnect(
          fromSheetId: c.fromSheetId,
          fromCell: c.fromCell,
          fromPart: c.fromPart,
          toSheetId: c.toSheetId,
          toCell: 'Connections.X${n + 1}',
          toPart: 100 + n,
        ));
      } else {
        nextConnects.add(c);
      }
    }
    return updateShapeById(id, (t) => t.copyWith(connectionPoints: pts))
        .copyWith(connects: nextConnects)
        .rerouteConnectors(movedShapeIds: <int>{id});
  }

  /// Whether connector [id] currently prefers a straight route.
  bool isConnectorStraight(int id) => findShapeById(id)?.straightRoute ?? false;

  /// Whether connector [id] is drawn as a smooth (curved) spline.
  bool isConnectorCurved(int id) => findShapeById(id)?.curved ?? false;

  /// Whether connector [id] rounds its route corners (drawio "Rounded").
  bool isConnectorRounded(int id) => findShapeById(id)?.rounded ?? false;

  /// Set the routing style of the given connectors:
  ///   * `straight` = a single direct segment,
  ///   * otherwise an orthogonal elbow,
  ///   * `curved` = a smooth spline through the same control points.
  /// Recomputed from each connector's current begin/end (respecting explicit
  /// waypoints) and remembered on the shape so later re-routes keep the choice.
  VsdxPage setConnectorStyle(
    Set<int> ids, {
    required bool straight,
    bool curved = false,
  }) {
    var next = this;
    for (final id in ids) {
      final s = next.findShapeById(id);
      if (s == null || !s.is1D) continue;
      final ax = s.beginX ?? s.pinX, ay = s.beginY ?? s.pinY;
      final bx = s.endX ?? s.pinX, by = s.endY ?? s.pinY;
      // Nested connectors store Begin/End in the parent-local frame; obstacle
      // avoidance uses page AABBs — convert at the edges like [rerouteConnectors].
      final parentId = next.findParentId(id);
      Offset2D toPage(double x, double y) {
        final local = Offset2D(x, y);
        if (parentId == null) return local;
        return next.localToPageDeep(parentId, local);
      }

      Offset2D toLocal(Offset2D page) {
        if (parentId == null) return page;
        return next.pageToLocalDeep(parentId, page);
      }

      final List<Offset2D> control;
      if (s.waypoints.isNotEmpty) {
        control = <Offset2D>[Offset2D(ax, ay), ...s.waypoints, Offset2D(bx, by)];
      } else if (straight) {
        control = <Offset2D>[Offset2D(ax, ay), Offset2D(bx, by)];
      } else {
        final beginPage = toPage(ax, ay);
        final endPage = toPage(bx, by);
        control = <Offset2D>[
          for (final p in next._autoRoute(
            beginPage.x,
            beginPage.y,
            endPage.x,
            endPage.y,
            excludeIds: <int>{id},
          ))
            toLocal(p),
        ];
      }
      final geometry = _bakeRoute(control, curved: curved, rounded: s.rounded);
      next = next.updateShapeById(
        id,
        (sh) => sh
            .copyWith(straightRoute: straight, curved: curved)
            .reshapeAsPolyline(geometry),
      );
    }
    return next;
  }

  /// Toggle drawio-style **rounded corners** on the given connectors, re-baking
  /// each one's geometry from its current route (straight / elbow / waypoints).
  /// Rounding is a corner treatment on the sharp polyline, so the choice is
  /// remembered on the shape and honoured by later re-routes; it has no visible
  /// effect on a two-point straight route (no corner to round) and is
  /// superseded by a [VsdxShape.curved] connector (already smooth).
  VsdxPage setConnectorRounded(Set<int> ids, bool rounded) {
    var next = this;
    for (final id in ids) {
      final s = next.findShapeById(id);
      if (s == null || !s.is1D) continue;
      final control = connectorRoute(s);
      final geometry = _bakeRoute(control, curved: s.curved, rounded: rounded);
      next = next.updateShapeById(
        id,
        (sh) => sh.copyWith(rounded: rounded).reshapeAsPolyline(geometry),
      );
    }
    return next;
  }

  /// Point on [s]'s **drawn outline** (Geometry) along the ray from its pin
  /// toward ([towardX], [towardY]), in page inches. Falls back to the local
  /// Width×Height box when geometry is missing. Nested groups compose via
  /// [localToPageDeep] so the tip meets the body, not a parent-local AABB.
  (double, double) _perimeterPoint(
    VsdxShape s,
    double towardX,
    double towardY,
  ) {
    final hit = ShapePerimeter.attachToward(
      s,
      pinPage: shapePinPage(s.id),
      towardX: towardX,
      towardY: towardY,
      localToPage: (local) => localToPageDeep(s.id, local),
      pageToLocal: (page) => pageToLocalDeep(s.id, page),
    );
    return (hit.x, hit.y);
  }

  /// Page-inch attach point on [shapeId]'s outline aimed at ([towardX],
  /// [towardY]) — shared by the editor router and paint-time fallback.
  Offset2D perimeterAttach(int shapeId, double towardX, double towardY) {
    final s = findShapeById(shapeId);
    if (s == null) return Offset2D(towardX, towardY);
    final (x, y) = _perimeterPoint(s, towardX, towardY);
    return Offset2D(x, y);
  }

  /// Orthogonal (elbow / Z) route between two page points. Falls back to a
  /// straight line when the points already share an axis.
  ///
  /// Prefer [_autoRoute] when a page context is available so other shapes are
  /// treated as obstacles (draw.io-style avoidance).
  static List<Offset2D> _elbowRoute(
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    if (ax == bx || ay == by) {
      return <Offset2D>[Offset2D(ax, ay), Offset2D(bx, by)];
    }
    if ((bx - ax).abs() >= (by - ay).abs()) {
      final mx = (ax + bx) / 2;
      return <Offset2D>[
        Offset2D(ax, ay),
        Offset2D(mx, ay),
        Offset2D(mx, by),
        Offset2D(bx, by),
      ];
    }
    final my = (ay + by) / 2;
    return <Offset2D>[
      Offset2D(ax, ay),
      Offset2D(ax, my),
      Offset2D(bx, my),
      Offset2D(bx, by),
    ];
  }

  /// Obstacle-avoiding orthogonal route on this page. [excludeIds] are shapes
  /// that must not block the path (typically the connector and its begin/end
  /// targets). Falls back to [_elbowRoute] when avoidance finds nothing better.
  List<Offset2D> _autoRoute(
    double ax,
    double ay,
    double bx,
    double by, {
    Set<int> excludeIds = const <int>{},
  }) {
    final obstacles = _obstacleAabbs(excludeIds);
    return const ObstacleRouter().route(
      ax,
      ay,
      bx,
      by,
      obstacles: obstacles,
    );
  }

  /// Inflated AABBs of every 2-D shape on the page that should deflect
  /// auto-routed connectors. Skips 1-D shapes, excluded ids, tiny stubs, and
  /// shapes on invisible layers (including children of hidden-layer hosts).
  List<RouteAabb> _obstacleAabbs(Set<int> excludeIds) {
    final out = <RouteAabb>[];
    void walk(List<VsdxShape> list) {
      for (final s in list) {
        // Match paint: a hidden-layer host hides its whole subtree.
        if (!isShapeVisible(s)) continue;
        if (s.children.isNotEmpty && !s.collapsed) {
          walk(s.children);
          continue;
        }
        if (excludeIds.contains(s.id) || s.is1D) continue;
        if (s.width < 0.05 || s.height < 0.05) continue;
        final aabb = shapePageAabb(s.id);
        if (aabb != null) {
          out.add(RouteAabb(
            aabb.left - ObstacleRouter.defaultClearance,
            aabb.bottom - ObstacleRouter.defaultClearance,
            aabb.right + ObstacleRouter.defaultClearance,
            aabb.top + ObstacleRouter.defaultClearance,
          ));
        } else {
          out.add(RouteAabb.fromCenter(
            pinX: s.pinX,
            pinY: s.pinY,
            width: s.width,
            height: s.height,
            pad: ObstacleRouter.defaultClearance,
          ));
        }
      }
    }

    walk(shapes);
    return out;
  }

  /// Sample a smooth Catmull-Rom spline that passes through every point in
  /// [control] (page inches), returning a dense polyline that begins and ends
  /// exactly on `control.first` / `control.last`. Fewer than three points can't
  /// bend, so they are returned unchanged.
  ///
  /// drawio-style *curved* connectors bake this sampled polyline straight into
  /// their geometry, so the smooth look round-trips as ordinary `MoveTo`/
  /// `LineTo` rows with no dedicated spline cell.
  static List<Offset2D> curveThrough(
    List<Offset2D> control, {
    int segmentsPerSpan = 12,
  }) {
    if (control.length < 3 || segmentsPerSpan < 1) return control;
    final pts = <Offset2D>[control.first];
    for (var i = 0; i < control.length - 1; i++) {
      final p0 = control[i == 0 ? 0 : i - 1];
      final p1 = control[i];
      final p2 = control[i + 1];
      final p3 = control[i + 2 < control.length ? i + 2 : control.length - 1];
      for (var s = 1; s <= segmentsPerSpan; s++) {
        pts.add(_catmullRom(p0, p1, p2, p3, s / segmentsPerSpan));
      }
    }
    return pts;
  }

  /// Centripetal-ish uniform Catmull-Rom interpolation of the middle span
  /// (`p1`→`p2`) at parameter [t] ∈ [0, 1].
  static Offset2D _catmullRom(
    Offset2D p0,
    Offset2D p1,
    Offset2D p2,
    Offset2D p3,
    double t,
  ) {
    final t2 = t * t;
    final t3 = t2 * t;
    double axis(double a0, double a1, double a2, double a3) => 0.5 *
        ((2 * a1) +
            (-a0 + a2) * t +
            (2 * a0 - 5 * a1 + 4 * a2 - a3) * t2 +
            (-a0 + 3 * a1 - 3 * a2 + a3) * t3);
    return Offset2D(
      axis(p0.x, p1.x, p2.x, p3.x),
      axis(p0.y, p1.y, p2.y, p3.y),
    );
  }

  /// Round off the interior corners of a route [control] (page inches) with
  /// small fillets, returning a denser polyline that keeps `control.first` /
  /// `control.last` exact — drawio's "Rounded" edges. Each bend is replaced by
  /// a quadratic-Bezier fillet that starts / ends [radius] back along the
  /// adjacent segments (clamped to half the shorter neighbour so short legs
  /// never overshoot). Fewer than three points have no corner to round and are
  /// returned unchanged.
  ///
  /// Like [curveThrough], the fillet is plain `LineTo` sampling, so a rounded
  /// connector round-trips as ordinary `MoveTo`/`LineTo` geometry.
  static List<Offset2D> roundCorners(
    List<Offset2D> control, {
    double radius = 0.12,
    int segmentsPerCorner = 6,
  }) {
    if (control.length < 3 || radius <= 0 || segmentsPerCorner < 1) {
      return control;
    }
    final out = <Offset2D>[control.first];
    for (var i = 1; i < control.length - 1; i++) {
      final prev = control[i - 1];
      final corner = control[i];
      final next = control[i + 1];
      final len1 = _segLength(prev, corner);
      final len2 = _segLength(corner, next);
      final r = math.min(radius, math.min(len1, len2) / 2);
      if (r <= 1e-9) {
        out.add(corner);
        continue;
      }
      // Fillet endpoints: back off r from the corner toward each neighbour.
      final p1 = Offset2D(
        corner.x + (prev.x - corner.x) / len1 * r,
        corner.y + (prev.y - corner.y) / len1 * r,
      );
      final p2 = Offset2D(
        corner.x + (next.x - corner.x) / len2 * r,
        corner.y + (next.y - corner.y) / len2 * r,
      );
      out.add(p1);
      for (var s = 1; s < segmentsPerCorner; s++) {
        out.add(_quadBezier(p1, corner, p2, s / segmentsPerCorner));
      }
      out.add(p2);
    }
    out.add(control.last);
    return out;
  }

  /// Quadratic Bezier point at [t] ∈ [0, 1] with endpoints [a] / [c] and
  /// control point [b] — used to fillet a route corner.
  static Offset2D _quadBezier(Offset2D a, Offset2D b, Offset2D c, double t) {
    final u = 1 - t;
    return Offset2D(
      u * u * a.x + 2 * u * t * b.x + t * t * c.x,
      u * u * a.y + 2 * u * t * b.y + t * t * c.y,
    );
  }

  /// Bake a connector's control polyline [control] into its drawn geometry,
  /// honouring its route treatment: a smooth [curved] spline wins, else
  /// [rounded] corner fillets, else the plain sharp polyline. Single source of
  /// truth shared by every re-route / restyle path so the drawn geometry stays
  /// consistent with the chosen style.
  static List<Offset2D> _bakeRoute(
    List<Offset2D> control, {
    required bool curved,
    required bool rounded,
  }) {
    if (curved) return curveThrough(control);
    if (rounded) return roundCorners(control);
    return control;
  }

  /// Move a top-level shape to the front (drawn last). No-op for nested shapes.
  VsdxPage bringToFront(int id) {
    final siblings = _siblingList(id);
    if (siblings == null) return this;
    final i = siblings.indexWhere((s) => s.id == id);
    if (i < 0 || i == siblings.length - 1) return this;
    final next = <VsdxShape>[
      for (final s in siblings)
        if (s.id != id) s,
      siblings[i],
    ];
    return _replaceSiblingList(id, next);
  }

  /// Move a shape to the back among its siblings (drawn first).
  VsdxPage sendToBack(int id) {
    final siblings = _siblingList(id);
    if (siblings == null) return this;
    final i = siblings.indexWhere((s) => s.id == id);
    if (i <= 0) return this;
    final next = <VsdxShape>[
      siblings[i],
      for (final s in siblings)
        if (s.id != id) s,
    ];
    return _replaceSiblingList(id, next);
  }

  /// Move a shape one step forward among its siblings (later in draw order).
  /// Works for top-level shapes and nested children inside groups/containers.
  VsdxPage bringForward(int id) {
    final siblings = _siblingList(id);
    if (siblings == null) return this;
    final i = siblings.indexWhere((s) => s.id == id);
    if (i < 0 || i >= siblings.length - 1) return this;
    final next = <VsdxShape>[...siblings];
    final tmp = next[i];
    next[i] = next[i + 1];
    next[i + 1] = tmp;
    return _replaceSiblingList(id, next);
  }

  /// Move a shape one step backward among its siblings (earlier in draw order).
  /// Works for top-level shapes and nested children inside groups/containers.
  VsdxPage sendBackward(int id) {
    final siblings = _siblingList(id);
    if (siblings == null) return this;
    final i = siblings.indexWhere((s) => s.id == id);
    if (i <= 0) return this;
    final next = <VsdxShape>[...siblings];
    final tmp = next[i];
    next[i] = next[i - 1];
    next[i - 1] = tmp;
    return _replaceSiblingList(id, next);
  }

  /// Sibling list containing [id] (page [shapes] or a parent's [children]).
  List<VsdxShape>? _siblingList(int id) {
    if (shapes.any((s) => s.id == id)) return shapes;
    final parentId = findParentId(id);
    if (parentId == null) return null;
    return findShapeById(parentId)?.children;
  }

  /// Replace the sibling list that contains [id] with [next].
  VsdxPage _replaceSiblingList(int id, List<VsdxShape> next) {
    if (shapes.any((s) => s.id == id)) {
      return copyWith(shapes: next);
    }
    final parentId = findParentId(id);
    if (parentId == null) return this;
    return updateShapeById(parentId, (p) => p.copyWith(children: next));
  }

  // --- Grouping --------------------------------------------------------------

  /// Group the top-level shapes [ids] into a new (axis-aligned) group shape
  /// [groupId], which is appended to the front of the z-order. Members keep
  /// their on-page appearance: their coordinates become local to the group's
  /// bottom-left corner (Visio's group coordinate convention). Returns `this`
  /// when fewer than two of [ids] are top-level shapes.
  VsdxPage group(Set<int> ids, {required int groupId, String name = ''}) {
    final members = <VsdxShape>[
      for (final s in shapes)
        if (ids.contains(s.id)) s,
    ];
    if (members.length < 2) return this;
    double? l, b, r, t;
    for (final m in members) {
      final (ml, mb, mr, mt) = _aabb(m);
      l = l == null ? ml : math.min(l, ml);
      b = b == null ? mb : math.min(b, mb);
      r = r == null ? mr : math.max(r, mr);
      t = t == null ? mt : math.max(t, mt);
    }
    final left = l!, bottom = b!;
    final w = math.max(r! - left, 0.01);
    final h = math.max(t! - bottom, 0.01);
    // Groups are containers: no fill / no stroke. Leaving the default
    // FillPattern=1 with a null foreground made the writer invent #FFFFFF for
    // Edraw, which then drifted on save→reopen (null → opaque white).
    final group = VsdxShape(
      id: groupId,
      name: name.isEmpty ? 'Group.$groupId' : name,
      pinX: left + w / 2,
      pinY: bottom + h / 2,
      width: w,
      height: h,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      shapeKind: VsdxShapeKind.group,
      children: <VsdxShape>[
        for (final m in members) _shiftShape(m, -left, -bottom),
      ],
    );
    return copyWith(shapes: <VsdxShape>[
      for (final s in shapes)
        if (!ids.contains(s.id)) s,
      group,
    ]);
  }

  /// Ungroup [groupId], promoting its children into the group's parent frame
  /// (page when top-level, or the enclosing group/container when nested).
  /// Returns `this` when [groupId] is missing or has no children.
  VsdxPage ungroup(int groupId) {
    final g = findShapeById(groupId);
    if (g == null || g.children.isEmpty) return this;
    final parentId = findParentId(groupId);
    if (parentId == null) {
      final idx = shapes.indexWhere((s) => s.id == groupId);
      if (idx < 0) return this;
      final cosA = math.cos(g.angleRad);
      final sinA = math.sin(g.angleRad);
      final fx = g.flipX ? -1.0 : 1.0;
      final fy = g.flipY ? -1.0 : 1.0;
      final ox = g.effectiveLocPinX;
      final oy = g.effectiveLocPinY;
      (double, double) toPage(double lx, double ly) {
        final rx = (lx - ox) * fx;
        final ry = (ly - oy) * fy;
        return (
          g.pinX + rx * cosA - ry * sinA,
          g.pinY + rx * sinA + ry * cosA,
        );
      }

      return copyWith(shapes: <VsdxShape>[
        ...shapes.sublist(0, idx),
        for (final c in g.children)
          _childToPage(c, toPage, g.angleRad).copyWith(
            flipX: c.flipX ^ g.flipX,
            flipY: c.flipY ^ g.flipY,
          ),
        ...shapes.sublist(idx + 1),
      ]);
    }
    // Nested group: promote children one level into the parent’s local frame.
    final promoted = <VsdxShape>[
      for (final c in g.children) _promoteChildToPage(c, g),
    ];
    return updateShapeById(
      parentId,
      (p) => p.copyWith(
        children: <VsdxShape>[
          for (final c in p.children)
            if (c.id != groupId) c,
          ...promoted,
        ],
      ),
    );
  }

  /// Rotation-aware page-inch AABB of [s] as (left, bottom, right, top).
  /// Uses [localToPage] so non-centre LocPin / flip match paint bounds.
  static (double, double, double, double) _aabb(VsdxShape s) {
    final corners = <Offset2D>[
      localToPage(s, const Offset2D(0, 0)),
      localToPage(s, Offset2D(s.width, 0)),
      localToPage(s, Offset2D(s.width, s.height)),
      localToPage(s, Offset2D(0, s.height)),
    ];
    var minX = corners.first.x, maxX = corners.first.x;
    var minY = corners.first.y, maxY = corners.first.y;
    for (final c in corners.skip(1)) {
      if (c.x < minX) minX = c.x;
      if (c.x > maxX) maxX = c.x;
      if (c.y < minY) minY = c.y;
      if (c.y > maxY) maxY = c.y;
    }
    return (minX, minY, maxX, maxY);
  }

  /// Translate [s] by ([dx],[dy]) in page inches. When [dontMoveChildren] is
  /// set, children are rewritten so their on-page positions stay fixed.
  static VsdxShape translateShape(
    VsdxShape s,
    double dx,
    double dy, {
    bool honourDontMoveChildren = true,
  }) {
    if (dx == 0 && dy == 0) return s;
    if (!honourDontMoveChildren ||
        !s.dontMoveChildren ||
        s.children.isEmpty) {
      return _shiftShape(s, dx, dy);
    }
    final movedParent = _shiftShape(s, dx, dy);
    final kids = <VsdxShape>[
      for (final c in s.children)
        _demotePageToChild(_promoteChildToPage(c, s), movedParent),
    ];
    return movedParent.copyWith(children: kids);
  }

  /// Translate a shape's pin, 1-D begin/end, and waypoints by (dx, dy).
  static VsdxShape _shiftShape(VsdxShape s, double dx, double dy) {
    var r = s.copyWith(
      pinX: s.pinX + dx,
      pinY: s.pinY + dy,
      beginX: s.beginX == null ? null : s.beginX! + dx,
      beginY: s.beginY == null ? null : s.beginY! + dy,
      endX: s.endX == null ? null : s.endX! + dx,
      endY: s.endY == null ? null : s.endY! + dy,
    );
    if (s.waypoints.isNotEmpty) {
      r = r.copyWith(
        waypoints: <Offset2D>[
          for (final w in s.waypoints) Offset2D(w.x + dx, w.y + dy),
        ],
      );
    }
    return r;
  }

  /// Convert a group child (local coords) back to page coords via [toPage],
  /// folding the group's rotation into the child's own angle.
  static VsdxShape _childToPage(
    VsdxShape c,
    (double, double) Function(double, double) toPage,
    double groupAngle,
  ) {
    final (px, py) = toPage(c.pinX, c.pinY);
    var r = c.copyWith(pinX: px, pinY: py, angleRad: c.angleRad + groupAngle);
    if (c.beginX != null && c.beginY != null) {
      final (bx, by) = toPage(c.beginX!, c.beginY!);
      r = r.copyWith(beginX: bx, beginY: by);
    }
    if (c.endX != null && c.endY != null) {
      final (ex, ey) = toPage(c.endX!, c.endY!);
      r = r.copyWith(endX: ex, endY: ey);
    }
    if (c.waypoints.isNotEmpty) {
      final wps = <Offset2D>[];
      for (final w in c.waypoints) {
        final (x, y) = toPage(w.x, w.y);
        wps.add(Offset2D(x, y));
      }
      r = r.copyWith(waypoints: wps);
    }
    return r;
  }

  /// Promote [child] from under [parent] into page-absolute coordinates.
  static VsdxShape _promoteChildToPage(VsdxShape child, VsdxShape parent) {
    final cosA = math.cos(parent.angleRad);
    final sinA = math.sin(parent.angleRad);
    final fx = parent.flipX ? -1.0 : 1.0;
    final fy = parent.flipY ? -1.0 : 1.0;
    final ox = parent.effectiveLocPinX;
    final oy = parent.effectiveLocPinY;
    (double, double) toPage(double lx, double ly) {
      final rx = (lx - ox) * fx;
      final ry = (ly - oy) * fy;
      return (
        parent.pinX + rx * cosA - ry * sinA,
        parent.pinY + rx * sinA + ry * cosA,
      );
    }

    // Bake parent flips into the child so chirality survives ungroup / eject.
    final promoted = _childToPage(child, toPage, parent.angleRad);
    return promoted.copyWith(
      flipX: child.flipX ^ parent.flipX,
      flipY: child.flipY ^ parent.flipY,
    );
  }

  /// Convert a page-absolute shape into [parent]'s local coordinate system.
  static VsdxShape _demotePageToChild(VsdxShape pageShape, VsdxShape parent) {
    final pin = pageToLocal(parent, Offset2D(pageShape.pinX, pageShape.pinY));
    // Inverse of [_promoteChildToPage] flip bake so dontMoveChildren / reparent
    // round-trips do not toggle chirality each move.
    var r = pageShape.copyWith(
      pinX: pin.x,
      pinY: pin.y,
      angleRad: pageShape.angleRad - parent.angleRad,
      flipX: pageShape.flipX ^ parent.flipX,
      flipY: pageShape.flipY ^ parent.flipY,
    );
    if (pageShape.beginX != null && pageShape.beginY != null) {
      final b =
          pageToLocal(parent, Offset2D(pageShape.beginX!, pageShape.beginY!));
      r = r.copyWith(beginX: b.x, beginY: b.y);
    }
    if (pageShape.endX != null && pageShape.endY != null) {
      final e =
          pageToLocal(parent, Offset2D(pageShape.endX!, pageShape.endY!));
      r = r.copyWith(endX: e.x, endY: e.y);
    }
    if (pageShape.waypoints.isNotEmpty) {
      r = r.copyWith(
        waypoints: <Offset2D>[
          for (final w in pageShape.waypoints) pageToLocal(parent, w),
        ],
      );
    }
    return r;
  }

  /// Map a point in [shapeId]'s local coordinates to page inches, walking up
  /// through any parent groups / containers.
  Offset2D localToPageDeep(int shapeId, Offset2D local) {
    var p = local;
    var id = shapeId;
    while (true) {
      final s = findShapeById(id);
      if (s == null) return p;
      p = localToPage(s, p);
      final parent = findParentId(id);
      if (parent == null) return p;
      id = parent;
    }
  }

  /// Map a page-inch point into [shapeId]'s local coordinates, walking down
  /// through any parent groups / containers. Inverse of [localToPageDeep].
  Offset2D pageToLocalDeep(int shapeId, Offset2D page) {
    final chain = <int>[];
    var id = shapeId;
    while (true) {
      chain.add(id);
      final parent = findParentId(id);
      if (parent == null) break;
      id = parent;
    }
    var p = page;
    for (final sid in chain.reversed) {
      final s = findShapeById(sid);
      if (s == null) return p;
      p = pageToLocal(s, p);
    }
    return p;
  }

  /// Page-inch position of [shapeId]'s pin (LocPin mapped through ancestors).
  Offset2D shapePinPage(int shapeId) {
    final s = findShapeById(shapeId);
    if (s == null) return const Offset2D(0, 0);
    return localToPageDeep(
      shapeId,
      Offset2D(s.effectiveLocPinX, s.effectiveLocPinY),
    );
  }

  /// Exact (unpadded) axis-aligned page-inch bbox of [shapeId]'s local
  /// `[0..W]×[0..H]` box after composing ancestor XForms, or `null` if missing.
  ({double left, double bottom, double right, double top})? shapePageAabb(
    int shapeId,
  ) {
    final s = findShapeById(shapeId);
    if (s == null) return null;
    final corners = <Offset2D>[
      localToPageDeep(shapeId, const Offset2D(0, 0)),
      localToPageDeep(shapeId, Offset2D(s.width, 0)),
      localToPageDeep(shapeId, Offset2D(s.width, s.height)),
      localToPageDeep(shapeId, Offset2D(0, s.height)),
    ];
    var minX = corners.first.x, maxX = corners.first.x;
    var minY = corners.first.y, maxY = corners.first.y;
    for (final c in corners.skip(1)) {
      if (c.x < minX) minX = c.x;
      if (c.x > maxX) maxX = c.x;
      if (c.y < minY) minY = c.y;
      if (c.y > maxY) maxY = c.y;
    }
    return (left: minX, bottom: minY, right: maxX, top: maxY);
  }

  /// Parent shape id of [id], or `null` when [id] is top-level / missing.
  int? findParentId(int id) {
    if (findShapeById(id) == null) return null;
    int? search(List<VsdxShape> list, int? parentId) {
      for (final s in list) {
        if (s.id == id) return parentId;
        final found = search(s.children, s.id);
        // Non-null means a nested match reported its parent. A top-level match
        // in this list returns [parentId] above (possibly null).
        if (found != null) return found;
        // Direct child of [s] matched with parentId == s.id — already handled
        // by the recursive call returning s.id. If the match was top-level of
        // [s.children], found == s.id (!= null). Nothing more to do.
      }
      return null;
    }

    return search(shapes, null);
  }

  /// Whether [s] can accept dropped children (draw.io-style containers /
  /// swimlanes / groups). Empty structural stencils qualify via
  /// [VsdxShapeKind.isStructural]; any shape that already has children does too.
  static bool isDropContainer(VsdxShape s) =>
      !s.is1D && (s.shapeKind.isStructural || s.children.isNotEmpty);

  /// Whether page point ([x],[y]) lies inside [s]'s axis-aligned **local**
  /// bounds (pin ± size/2). Prefer [containsShapePagePoint] for nested shapes
  /// whose pins are parent-local.
  static bool containsPagePoint(VsdxShape s, double x, double y) {
    final (l, b, r, t) = _aabb(s);
    return x >= l && x <= r && y >= b && y <= t;
  }

  /// Whether page point ([x],[y]) lies inside [shapeId]'s page-space AABB
  /// (accounts for parent transforms / nested swimlanes).
  bool containsShapePagePoint(int shapeId, double x, double y) {
    final aabb = shapePageAabb(shapeId);
    if (aabb == null) return false;
    return x >= aabb.left &&
        x <= aabb.right &&
        y >= aabb.bottom &&
        y <= aabb.top;
  }

  /// Deepest drop-container under page point ([x],[y]), excluding [excludeIds]
  /// and their ancestors / descendants (so a shape cannot be dropped into
  /// itself or its own subtree). Returns `null` when nothing qualifies.
  int? findDropContainerAt(
    double x,
    double y, {
    Set<int> excludeIds = const <int>{},
  }) {
    final blocked = <int>{...excludeIds};
    for (final id in excludeIds) {
      var p = findParentId(id);
      while (p != null) {
        blocked.add(p);
        p = findParentId(p);
      }
      final s = findShapeById(id);
      if (s != null) _collectDescendantIds(s, blocked);
    }

    int? best;
    var bestDepth = -1;
    void walk(List<VsdxShape> list, int depth) {
      for (final s in list) {
        if (s.children.isNotEmpty) walk(s.children, depth + 1);
        if (blocked.contains(s.id) || !isDropContainer(s)) continue;
        // Use page-space AABB so nested lanes / containers hit-test correctly.
        if (!containsShapePagePoint(s.id, x, y)) continue;
        if (depth >= bestDepth) {
          best = s.id;
          bestDepth = depth;
        }
      }
    }

    walk(shapes, 0);
    return best;
  }

  static void _collectDescendantIds(VsdxShape s, Set<int> out) {
    for (final c in s.children) {
      out.add(c.id);
      _collectDescendantIds(c, out);
    }
  }

  /// Move [childId] under [newParentId] (draw.io drop-into-container).
  ///
  /// When [newParentId] is `null` the shape is promoted to the top level.
  /// Coordinates are converted between page and parent-local space so the
  /// on-page appearance is preserved. Returns `this` unchanged when the shape
  /// is missing, when the parent is missing, or when membership would not
  /// change.
  VsdxPage reparentShape(int childId, int? newParentId) {
    final child = findShapeById(childId);
    if (child == null) return this;
    final oldParentId = findParentId(childId);
    if (oldParentId == newParentId) return this;
    if (newParentId == childId) return this;
    if (newParentId != null) {
      final parent = findShapeById(newParentId);
      if (parent == null || parent.is1D) return this;
      final descendants = <int>{};
      _collectDescendantIds(child, descendants);
      if (descendants.contains(newParentId)) return this;
    }

    late final VsdxShape pageShape;
    late final VsdxPage without;
    if (oldParentId == null) {
      pageShape = child;
      without = removeShapeById(childId, pruneConnects: false);
    } else {
      // Walk all ancestors so nested parents (lanes / inner groups) keep the
      // on-page pin — shallow promote treats parent.pin as page inches.
      pageShape = _promoteToPageDeep(childId);
      without = removeShapeById(childId, pruneConnects: false);
    }

    if (newParentId == null) {
      return without.addShape(pageShape);
    }
    final parent = without.findShapeById(newParentId);
    if (parent == null) return without.addShape(pageShape);
    final local = without._demoteFromPageDeep(pageShape, newParentId);
    return without.updateShapeById(
      newParentId,
      (p) => p.copyWith(
        children: <VsdxShape>[...p.children, local],
        shapeKind: p.shapeKind == VsdxShapeKind.normal
            ? VsdxShapeKind.group
            : p.shapeKind,
      ),
    );
  }

  /// Materialize [shapeId] as a top-level shape (page pin / angle / flip).
  /// Children keep their coordinates in the root's local frame.
  VsdxShape shapeAsPageRoot(int shapeId) {
    final s = findShapeById(shapeId);
    if (s == null) {
      throw ArgumentError.value(shapeId, 'shapeId', 'not on page');
    }
    if (findParentId(shapeId) == null) return s;
    return _promoteToPageDeep(shapeId);
  }

  /// Promote [childId] through every ancestor into true page-absolute coords,
  /// baking ancestor reflection into [VsdxShape.flipX].
  VsdxShape _promoteToPageDeep(int childId) {
    final child = findShapeById(childId)!;
    final parentId = findParentId(childId);
    if (parentId == null) return child;

    Offset2D map(double x, double y) =>
        localToPageDeep(parentId, Offset2D(x, y));

    final pin = map(child.pinX, child.pinY);
    final baked = _pageOrientation(childId);
    var r = child.copyWith(
      pinX: pin.x,
      pinY: pin.y,
      angleRad: baked.angle,
      flipX: baked.flipX,
      flipY: false,
    );
    if (child.beginX != null && child.beginY != null) {
      final b = map(child.beginX!, child.beginY!);
      r = r.copyWith(beginX: b.x, beginY: b.y);
    }
    if (child.endX != null && child.endY != null) {
      final e = map(child.endX!, child.endY!);
      r = r.copyWith(endX: e.x, endY: e.y);
    }
    if (child.waypoints.isNotEmpty) {
      r = r.copyWith(
        waypoints: <Offset2D>[
          for (final w in child.waypoints) map(w.x, w.y),
        ],
      );
    }
    return r;
  }

  /// Page heading + whether the local→page linear map reflects (det &lt; 0).
  ({double angle, bool flipX}) _pageOrientation(int shapeId) {
    final s = findShapeById(shapeId)!;
    final lx = s.effectiveLocPinX;
    final ly = s.effectiveLocPinY;
    final origin = localToPageDeep(shapeId, Offset2D(lx, ly));
    final right = localToPageDeep(shapeId, Offset2D(lx + 1, ly));
    final up = localToPageDeep(shapeId, Offset2D(lx, ly + 1));
    final rx = right.x - origin.x;
    final ry = right.y - origin.y;
    final ux = up.x - origin.x;
    final uy = up.y - origin.y;
    final reflected = (rx * uy - ry * ux) < 0;
    final angle = math.atan2(-ux, uy);
    return (angle: angle, flipX: reflected);
  }

  /// Demote a page-absolute [pageShape] into [parentId]'s local frame (deep).
  VsdxShape _demoteFromPageDeep(VsdxShape pageShape, int parentId) {
    Offset2D map(double x, double y) =>
        pageToLocalDeep(parentId, Offset2D(x, y));

    // Normalize flipY → flipX + π so we do not drop vertical mirrors (promote
    // already bakes reflection as flipX; top-level flipVertical never promotes).
    var src = pageShape;
    if (src.flipY) {
      src = src.copyWith(
        flipX: !src.flipX,
        flipY: false,
        angleRad: src.angleRad + math.pi,
      );
    }

    final parentOri = _pageOrientation(parentId);
    final pin = map(src.pinX, src.pinY);
    var r = src.copyWith(
      pinX: pin.x,
      pinY: pin.y,
      angleRad: src.angleRad - parentOri.angle,
      // Inverse of [_promoteToPageDeep] reflection bake.
      flipX: src.flipX ^ parentOri.flipX,
      flipY: false,
    );
    if (src.beginX != null && src.beginY != null) {
      final b = map(src.beginX!, src.beginY!);
      r = r.copyWith(beginX: b.x, beginY: b.y);
    }
    if (src.endX != null && src.endY != null) {
      final e = map(src.endX!, src.endY!);
      r = r.copyWith(endX: e.x, endY: e.y);
    }
    if (src.waypoints.isNotEmpty) {
      r = r.copyWith(
        waypoints: <Offset2D>[
          for (final w in src.waypoints) map(w.x, w.y),
        ],
      );
    }
    return r;
  }

  /// Absolute page heading of [shapeId] (Visio CCW, 0 = local +Y).
  double shapePageAngle(int shapeId) => _pageOrientation(shapeId).angle;

  /// The smallest shape id greater than every id currently used on the page
  /// (including nested group children) — used when creating new shapes.
  int nextFreeShapeId() {
    var maxId = 0;
    void walk(VsdxShape s) {
      if (s.id > maxId) maxId = s.id;
      for (final c in s.children) {
        walk(c);
      }
    }

    for (final s in shapes) {
      walk(s);
    }
    return maxId + 1;
  }

  @override
  String toString() =>
      'VsdxPage(id: $id, name: $name, ${widthInches}x$heightInches in, '
      '${shapes.length} shapes, ${layers.length} layers)';
}
