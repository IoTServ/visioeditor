/// One Visio "drawing page". Page size is stored in **inches** (see
/// `lib/utils/units.dart` for the normalisation policy).
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../utils/color.dart';
import 'connect.dart';
import 'geometry.dart';
import 'layer.dart';
import 'shape.dart';

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
    int? backgroundPageId,
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
      backgroundPageId: backgroundPageId ?? this.backgroundPageId,
    );
  }

  /// Returns a copy of this page with the shape identified by [id] replaced by
  /// `update(oldShape)`. Recurses into groups. Returns `this` (identical) when
  /// no shape matches, so callers can cheaply detect no-ops.
  VsdxPage updateShapeById(int id, VsdxShape Function(VsdxShape) update) {
    final (newShapes, changed) = _updateInList(shapes, id, update);
    return changed ? copyWith(shapes: newShapes) : this;
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
        result.add(update(s));
        changed = true;
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
  VsdxPage removeShapeById(int id) {
    final (newShapes, changed) = _removeInList(shapes, id);
    return changed ? copyWith(shapes: newShapes) : this;
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

  /// Re-route every glued connector so its endpoints follow the current
  /// centres of the shapes they are connected to (via [connects]). Returns
  /// `this` unchanged when there are no connects.
  VsdxPage rerouteConnectors() {
    if (connects.isEmpty) return this;
    final index = connectIndex;
    final connectorIds = <int>{for (final c in connects) c.fromSheetId};
    var next = this;
    for (final cid in connectorIds) {
      final connector = next.findShapeById(cid);
      if (connector == null) continue;
      VsdxShape? beginShape;
      VsdxShape? endShape;
      for (final e in index.forConnector(cid)) {
        final target = next.findShapeById(e.toSheetId);
        if (target == null) continue;
        if (e.isBegin) {
          beginShape = target;
        } else if (e.isEnd) {
          endShape = target;
        }
      }
      // Reference centres (fall back to the connector's own endpoints).
      final beginCx = beginShape?.pinX ?? connector.beginX ?? connector.pinX;
      final beginCy = beginShape?.pinY ?? connector.beginY ?? connector.pinY;
      final endCx = endShape?.pinX ?? connector.endX ?? connector.pinX;
      final endCy = endShape?.pinY ?? connector.endY ?? connector.pinY;
      // Attach on each shape's edge, aimed at the opposite end's centre.
      final (ax, ay) = beginShape != null
          ? _edgePoint(beginShape, endCx, endCy)
          : (beginCx, beginCy);
      final (bx, by) = endShape != null
          ? _edgePoint(endShape, beginCx, beginCy)
          : (endCx, endCy);
      final control = connector.waypoints.isNotEmpty
          ? <Offset2D>[
              Offset2D(ax, ay),
              ...connector.waypoints,
              Offset2D(bx, by),
            ]
          : connector.straightRoute
              ? <Offset2D>[Offset2D(ax, ay), Offset2D(bx, by)]
              : _elbowRoute(ax, ay, bx, by);
      final geometry = connector.curved ? curveThrough(control) : control;
      next = next.updateShapeById(cid, (s) => s.reshapeAsPolyline(geometry));
    }
    return next;
  }

  /// The drawn route of connector [s] in page inches: begin → waypoints → end,
  /// or the straight / elbow route when it has no explicit waypoints.
  static List<Offset2D> connectorRoute(VsdxShape s) {
    final ax = s.beginX ?? s.pinX, ay = s.beginY ?? s.pinY;
    final bx = s.endX ?? s.pinX, by = s.endY ?? s.pinY;
    if (s.waypoints.isNotEmpty) {
      return <Offset2D>[Offset2D(ax, ay), ...s.waypoints, Offset2D(bx, by)];
    }
    if (s.straightRoute) return <Offset2D>[Offset2D(ax, ay), Offset2D(bx, by)];
    return _elbowRoute(ax, ay, bx, by);
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
    final geometry = s.curved ? curveThrough(control) : control;
    final next = updateShapeById(
      id,
      (sh) => sh.copyWith(waypoints: waypoints).reshapeAsPolyline(geometry),
    );
    return next.rerouteConnectors();
  }

  /// Whether connector [id] currently prefers a straight route.
  bool isConnectorStraight(int id) => findShapeById(id)?.straightRoute ?? false;

  /// Whether connector [id] is drawn as a smooth (curved) spline.
  bool isConnectorCurved(int id) => findShapeById(id)?.curved ?? false;

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
      final control = s.waypoints.isNotEmpty
          ? <Offset2D>[Offset2D(ax, ay), ...s.waypoints, Offset2D(bx, by)]
          : straight
              ? <Offset2D>[Offset2D(ax, ay), Offset2D(bx, by)]
              : _elbowRoute(ax, ay, bx, by);
      final geometry = curved ? curveThrough(control) : control;
      next = next.updateShapeById(
        id,
        (sh) => sh
            .copyWith(straightRoute: straight, curved: curved)
            .reshapeAsPolyline(geometry),
      );
    }
    return next;
  }

  /// Point on [s]'s axis-aligned bounding box boundary along the ray from its
  /// centre toward ([towardX], [towardY]).
  static (double, double) _edgePoint(
    VsdxShape s,
    double towardX,
    double towardY,
  ) {
    final cx = s.pinX;
    final cy = s.pinY;
    final dx = towardX - cx;
    final dy = towardY - cy;
    if (dx == 0 && dy == 0) return (cx, cy);
    final hw = s.width / 2;
    final hh = s.height / 2;
    final sx = dx == 0 ? double.infinity : hw / dx.abs();
    final sy = dy == 0 ? double.infinity : hh / dy.abs();
    final t = math.min(sx, sy);
    return (cx + dx * t, cy + dy * t);
  }

  /// Orthogonal (elbow / Z) route between two page points. Falls back to a
  /// straight line when the points already share an axis.
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

  /// Move a top-level shape to the front (drawn last). No-op for nested shapes.
  VsdxPage bringToFront(int id) {
    if (!shapes.any((s) => s.id == id)) return this;
    return copyWith(shapes: <VsdxShape>[
      for (final s in shapes)
        if (s.id != id) s,
      shapes.firstWhere((s) => s.id == id),
    ]);
  }

  /// Move a top-level shape to the back (drawn first).
  VsdxPage sendToBack(int id) {
    if (!shapes.any((s) => s.id == id)) return this;
    return copyWith(shapes: <VsdxShape>[
      shapes.firstWhere((s) => s.id == id),
      for (final s in shapes)
        if (s.id != id) s,
    ]);
  }

  /// Move a top-level shape one step forward (later in draw order). No-op when
  /// it is already frontmost or is not a top-level shape.
  VsdxPage bringForward(int id) {
    final i = shapes.indexWhere((s) => s.id == id);
    if (i < 0 || i >= shapes.length - 1) return this;
    final next = <VsdxShape>[...shapes];
    final tmp = next[i];
    next[i] = next[i + 1];
    next[i + 1] = tmp;
    return copyWith(shapes: next);
  }

  /// Move a top-level shape one step backward (earlier in draw order). No-op
  /// when it is already backmost or is not a top-level shape.
  VsdxPage sendBackward(int id) {
    final i = shapes.indexWhere((s) => s.id == id);
    if (i <= 0) return this;
    final next = <VsdxShape>[...shapes];
    final tmp = next[i];
    next[i] = next[i - 1];
    next[i - 1] = tmp;
    return copyWith(shapes: next);
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
    final group = VsdxShape(
      id: groupId,
      name: name.isEmpty ? 'Group.$groupId' : name,
      pinX: left + w / 2,
      pinY: bottom + h / 2,
      width: w,
      height: h,
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

  /// Ungroup the top-level group [groupId], promoting its children back to the
  /// page with page-absolute coordinates. Returns `this` when [groupId] is not
  /// a top-level shape with children.
  VsdxPage ungroup(int groupId) {
    final idx = shapes.indexWhere((s) => s.id == groupId);
    if (idx < 0 || shapes[idx].children.isEmpty) return this;
    final g = shapes[idx];
    final cosA = math.cos(g.angleRad);
    final sinA = math.sin(g.angleRad);
    final fx = g.flipX ? -1.0 : 1.0;
    final fy = g.flipY ? -1.0 : 1.0;
    (double, double) toPage(double lx, double ly) {
      final rx = (lx - g.width / 2) * fx;
      final ry = (ly - g.height / 2) * fy;
      return (
        g.pinX + rx * cosA - ry * sinA,
        g.pinY + rx * sinA + ry * cosA,
      );
    }

    return copyWith(shapes: <VsdxShape>[
      ...shapes.sublist(0, idx),
      for (final c in g.children) _childToPage(c, toPage, g.angleRad),
      ...shapes.sublist(idx + 1),
    ]);
  }

  /// Rotation-aware page-inch AABB of [s] as (left, bottom, right, top).
  static (double, double, double, double) _aabb(VsdxShape s) {
    final hw = s.width / 2, hh = s.height / 2;
    if (s.angleRad == 0) {
      return (s.pinX - hw, s.pinY - hh, s.pinX + hw, s.pinY + hh);
    }
    final c = math.cos(s.angleRad), sn = math.sin(s.angleRad);
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

  /// Translate a shape's pin and (for 1-D shapes) its begin/end by (dx, dy).
  static VsdxShape _shiftShape(VsdxShape s, double dx, double dy) => s.copyWith(
        pinX: s.pinX + dx,
        pinY: s.pinY + dy,
        beginX: s.beginX == null ? null : s.beginX! + dx,
        beginY: s.beginY == null ? null : s.beginY! + dy,
        endX: s.endX == null ? null : s.endX! + dx,
        endY: s.endY == null ? null : s.endY! + dy,
      );

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
    return r;
  }

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
