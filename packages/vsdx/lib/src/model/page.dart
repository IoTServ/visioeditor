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
      // A fixed connection point (drawio blue point) pins the endpoint to a
      // specific spot on the shape; otherwise we attach on the edge aimed at
      // the opposite end.
      final beginFixed = _fixedPoint(beginShape, beginConnect);
      final endFixed = _fixedPoint(endShape, endConnect);
      // Reference points used to aim edge attachments at the opposite end.
      final refBx =
          beginFixed?.x ?? beginShape?.pinX ?? connector.beginX ?? connector.pinX;
      final refBy =
          beginFixed?.y ?? beginShape?.pinY ?? connector.beginY ?? connector.pinY;
      final refEx =
          endFixed?.x ?? endShape?.pinX ?? connector.endX ?? connector.pinX;
      final refEy =
          endFixed?.y ?? endShape?.pinY ?? connector.endY ?? connector.pinY;
      final (ax, ay) = beginFixed != null
          ? (beginFixed.x, beginFixed.y)
          : beginShape != null
              ? _edgePoint(beginShape, refEx, refEy)
              : (refBx, refBy);
      final (bx, by) = endFixed != null
          ? (endFixed.x, endFixed.y)
          : endShape != null
              ? _edgePoint(endShape, refBx, refBy)
              : (refEx, refEy);
      final control = connector.waypoints.isNotEmpty
          ? <Offset2D>[
              Offset2D(ax, ay),
              ...connector.waypoints,
              Offset2D(bx, by),
            ]
          : connector.straightRoute
              ? <Offset2D>[Offset2D(ax, ay), Offset2D(bx, by)]
              : _elbowRoute(ax, ay, bx, by);
      final geometry = _bakeRoute(control,
          curved: connector.curved, rounded: connector.rounded);
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
    final geometry = _bakeRoute(control, curved: s.curved, rounded: s.rounded);
    final next = updateShapeById(
      id,
      (sh) => sh.copyWith(waypoints: waypoints).reshapeAsPolyline(geometry),
    );
    return next.rerouteConnectors();
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
    var base = this;
    if (targetShapeId != null && connectionPointIndex != null) {
      final target = base.findShapeById(targetShapeId);
      if (target != null && target.connectionPoints.isEmpty) {
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
        .updateShapeById(id, (sh) => sh.reshapeAsPolyline(geometry))
        .copyWith(connects: nextConnects);
    return next.rerouteConnectors();
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
  /// to page inches, honouring its pin, size, rotation and flip.
  static Offset2D localToPage(VsdxShape s, Offset2D local) {
    var dx = local.x - s.width / 2;
    var dy = local.y - s.height / 2;
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

  /// Page-inch position of connection point [index] on [s]. [index] is into
  /// [VsdxShape.connectionPoints] (shape-local inches, origin bottom-left).
  static Offset2D connectionPointPage(VsdxShape s, int index) =>
      localToPage(s, s.connectionPoints[index]);

  /// Effective connection points of [s] for display / snapping: its explicit
  /// points, or the standard default set (drawio) when it has none.
  static List<Offset2D> effectiveConnectionPoints(VsdxShape s) =>
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
    return connectionPointPage(shape, idx);
  }

  /// Standard default connection points (drawio-style) for a [width]×[height]
  /// box, shape-local inches (origin bottom-left): top-centre, right-middle,
  /// bottom-centre, left-middle, centre — indices 0..4.
  static List<Offset2D> defaultConnectionPoints(double width, double height) =>
      <Offset2D>[
        Offset2D(width / 2, height), // 0 top
        Offset2D(width, height / 2), // 1 right
        Offset2D(width / 2, 0), // 2 bottom
        Offset2D(0, height / 2), // 3 left
        Offset2D(width / 2, height / 2), // 4 centre
      ];

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
      final control = s.waypoints.isNotEmpty
          ? <Offset2D>[Offset2D(ax, ay), ...s.waypoints, Offset2D(bx, by)]
          : straight
              ? <Offset2D>[Offset2D(ax, ay), Offset2D(bx, by)]
              : _elbowRoute(ax, ay, bx, by);
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
      final ax = s.beginX ?? s.pinX, ay = s.beginY ?? s.pinY;
      final bx = s.endX ?? s.pinX, by = s.endY ?? s.pinY;
      final control = s.waypoints.isNotEmpty
          ? <Offset2D>[Offset2D(ax, ay), ...s.waypoints, Offset2D(bx, by)]
          : s.straightRoute
              ? <Offset2D>[Offset2D(ax, ay), Offset2D(bx, by)]
              : _elbowRoute(ax, ay, bx, by);
      final geometry = _bakeRoute(control, curved: s.curved, rounded: rounded);
      next = next.updateShapeById(
        id,
        (sh) => sh.copyWith(rounded: rounded).reshapeAsPolyline(geometry),
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
