/// Orthogonal connector routing that skirts around other shapes (draw.io-style
/// obstacle avoidance).
///
/// Algorithm:
///   1. Optionally offset glued endpoints outward along their approach side
///      (jetty stubs) so the first/last segment is perpendicular to the shape
///      edge — matching draw.io OrthConnector / port-constraint behaviour.
///   2. Try the two classic elbow routes (horizontal-first / vertical-first).
///   3. If either is clear of [obstacles], return the shorter one.
///   4. Otherwise build a Hanan grid from the endpoints + obstacle edges and
///      run Dijkstra for a shortest axis-aligned path that never enters an
///      obstacle AABB. Collapse collinear vertices before returning.
///   5. If the grid search fails (degenerate / fully blocked), fall back to
///      the plain elbow so callers always get a usable route.
library;

import 'dart:math' as math;

import 'geometry.dart';

/// Cardinal side of a shape that a connector approaches / leaves from.
///
/// Page inches use Visio Y-up: [north] is +Y (top edge), [south] is −Y.
enum RouteSide {
  north,
  south,
  east,
  west;

  /// Dominant cardinal direction of the vector ([dx], [dy]).
  static RouteSide? fromVector(double dx, double dy) {
    if (dx.abs() < 1e-12 && dy.abs() < 1e-12) return null;
    if (dy.abs() >= dx.abs()) {
      return dy >= 0 ? RouteSide.north : RouteSide.south;
    }
    return dx >= 0 ? RouteSide.east : RouteSide.west;
  }

  /// Outward unit step in page inches (Y up).
  (double, double) get outward {
    switch (this) {
      case RouteSide.north:
        return (0, 1);
      case RouteSide.south:
        return (0, -1);
      case RouteSide.east:
        return (1, 0);
      case RouteSide.west:
        return (-1, 0);
    }
  }

  /// Whether the terminal segment along this side is vertical (N/S).
  bool get isVertical =>
      this == RouteSide.north || this == RouteSide.south;
}

/// Axis-aligned box in page inches (Y up). Used as an inflated obstacle.
class RouteAabb {
  const RouteAabb(this.left, this.bottom, this.right, this.top);

  final double left;
  final double bottom;
  final double right;
  final double top;

  factory RouteAabb.fromCenter({
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    double pad = 0,
  }) {
    final hw = width / 2 + pad;
    final hh = height / 2 + pad;
    return RouteAabb(pinX - hw, pinY - hh, pinX + hw, pinY + hh);
  }

  RouteAabb inflate(double pad) =>
      RouteAabb(left - pad, bottom - pad, right + pad, top + pad);

  /// Strict interior (boundary is allowed — endpoints sit on begin/end edges).
  bool containsPoint(double x, double y, {double eps = 1e-9}) =>
      x > left + eps && x < right - eps && y > bottom + eps && y < top - eps;

  /// Whether the open segment (x1,y1)→(x2,y2) properly intersects this box.
  /// Orthogonal segments only; grazing the boundary is allowed.
  bool blocksSegment(double x1, double y1, double x2, double y2,
      {double eps = 1e-9}) {
    final minX = math.min(x1, x2);
    final maxX = math.max(x1, x2);
    final minY = math.min(y1, y2);
    final maxY = math.max(y1, y2);
    // No overlap with the open box interior.
    if (maxX <= left + eps || minX >= right - eps) return false;
    if (maxY <= bottom + eps || minY >= top - eps) return false;
    // Axis-aligned: a horizontal (or vertical) segment that overlaps the
    // open interval in both axes crosses the interior.
    final horiz = (y1 - y2).abs() < eps;
    final vert = (x1 - x2).abs() < eps;
    if (horiz) {
      return y1 > bottom + eps && y1 < top - eps;
    }
    if (vert) {
      return x1 > left + eps && x1 < right - eps;
    }
    // Non-orthogonal — treat as blocked if the bbox overlaps (defensive).
    return true;
  }
}

/// Stateless obstacle-avoiding orthogonal router.
class ObstacleRouter {
  const ObstacleRouter();

  /// Default clearance around each obstacle (inches), matching a comfortable
  /// draw.io-ish gutter so the line does not hug shape edges.
  static const double defaultClearance = 0.12;

  /// Outward stub length (inches) so the first/last segment meets the shape
  /// edge perpendicularly (draw.io jetty).
  static const double defaultJetty = 0.1;

  /// Orthogonal route from ([ax],[ay]) to ([bx],[by]) that avoids [obstacles].
  ///
  /// When [beginSide] / [endSide] are set (glued ends), a short outward jetty
  /// is inserted so the terminal segment is perpendicular to that side —
  /// arrows then point into the shape instead of sliding along its edge.
  ///
  /// Always returns at least the two endpoints. Interior waypoints are the
  /// bend corners (same convention as [VsdxPage]'s elbow helper: full polyline
  /// including endpoints).
  List<Offset2D> route(
    double ax,
    double ay,
    double bx,
    double by, {
    required List<RouteAabb> obstacles,
    RouteSide? beginSide,
    RouteSide? endSide,
    double jetty = defaultJetty,
  }) {
    if ((ax - bx).abs() < 1e-9 && (ay - by).abs() < 1e-9) {
      return <Offset2D>[Offset2D(ax, ay), Offset2D(bx, by)];
    }

    final sep = math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by));
    // Shrink / drop jetties when endpoints are too close (draw.io tooShort).
    var j = jetty;
    if (sep < 2 * j) {
      j = sep * 0.25;
    }
    if (j < 1e-6) {
      beginSide = null;
      endSide = null;
    }

    final (sax, say) = beginSide != null
        ? _jettyPoint(ax, ay, beginSide, j)
        : (ax, ay);
    final (sbx, sby) = endSide != null
        ? _jettyPoint(bx, by, endSide, j)
        : (bx, by);

    final mid = _routeCore(sax, say, sbx, sby, obstacles);

    // Stitch real endpoints around the routed jetty corridor.
    final out = <Offset2D>[Offset2D(ax, ay)];
    if (beginSide != null &&
        ((sax - ax).abs() > 1e-9 || (say - ay).abs() > 1e-9)) {
      out.add(Offset2D(sax, say));
    }
    for (final p in mid) {
      final last = out.last;
      if ((p.x - last.x).abs() < 1e-9 && (p.y - last.y).abs() < 1e-9) {
        continue;
      }
      out.add(p);
    }
    if (endSide != null &&
        ((sbx - bx).abs() > 1e-9 || (sby - by).abs() > 1e-9)) {
      final last = out.last;
      if ((last.x - sbx).abs() > 1e-9 || (last.y - sby).abs() > 1e-9) {
        out.add(Offset2D(sbx, sby));
      }
      out.add(Offset2D(bx, by));
    } else {
      final last = out.last;
      if ((last.x - bx).abs() > 1e-9 || (last.y - by).abs() > 1e-9) {
        out.add(Offset2D(bx, by));
      }
    }
    return _simplifyOrthogonal(out);
  }

  static (double, double) _jettyPoint(
    double x,
    double y,
    RouteSide side,
    double jetty,
  ) {
    final (dx, dy) = side.outward;
    return (x + dx * jetty, y + dy * jetty);
  }

  /// Core elbow / Hanan route between (possibly jettied) points.
  List<Offset2D> _routeCore(
    double ax,
    double ay,
    double bx,
    double by,
    List<RouteAabb> obstacles,
  ) {
    if ((ax - bx).abs() < 1e-9 && (ay - by).abs() < 1e-9) {
      return <Offset2D>[Offset2D(ax, ay), Offset2D(bx, by)];
    }

    final elbowH = _elbowHorizontalFirst(ax, ay, bx, by);
    final elbowV = _elbowVerticalFirst(ax, ay, bx, by);
    final clearH = _polylineClear(elbowH, obstacles);
    final clearV = _polylineClear(elbowV, obstacles);
    if (clearH && clearV) {
      return _length(elbowH) <= _length(elbowV) ? elbowH : elbowV;
    }
    if (clearH) return elbowH;
    if (clearV) return elbowV;

    if (obstacles.isEmpty) {
      return _length(elbowH) <= _length(elbowV) ? elbowH : elbowV;
    }

    final found = _hananRoute(ax, ay, bx, by, obstacles);
    if (found != null && found.length >= 2) return found;

    // Last resort: classic elbow (may cross an obstacle).
    return _length(elbowH) <= _length(elbowV) ? elbowH : elbowV;
  }

  static List<Offset2D> _elbowHorizontalFirst(
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    if ((ax - bx).abs() < 1e-9 || (ay - by).abs() < 1e-9) {
      return <Offset2D>[Offset2D(ax, ay), Offset2D(bx, by)];
    }
    final mx = (ax + bx) / 2;
    return <Offset2D>[
      Offset2D(ax, ay),
      Offset2D(mx, ay),
      Offset2D(mx, by),
      Offset2D(bx, by),
    ];
  }

  static List<Offset2D> _elbowVerticalFirst(
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    if ((ax - bx).abs() < 1e-9 || (ay - by).abs() < 1e-9) {
      return <Offset2D>[Offset2D(ax, ay), Offset2D(bx, by)];
    }
    final my = (ay + by) / 2;
    return <Offset2D>[
      Offset2D(ax, ay),
      Offset2D(ax, my),
      Offset2D(bx, my),
      Offset2D(bx, by),
    ];
  }

  static bool _polylineClear(List<Offset2D> pts, List<RouteAabb> obstacles) {
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      for (final o in obstacles) {
        if (o.blocksSegment(a.x, a.y, b.x, b.y)) return false;
      }
    }
    return true;
  }

  static double _length(List<Offset2D> pts) {
    var sum = 0.0;
    for (var i = 0; i < pts.length - 1; i++) {
      sum += (pts[i].x - pts[i + 1].x).abs() + (pts[i].y - pts[i + 1].y).abs();
    }
    return sum;
  }

  /// Hanan-grid Dijkstra. Returns a simplified orthogonal polyline or null.
  static List<Offset2D>? _hananRoute(
    double ax,
    double ay,
    double bx,
    double by,
    List<RouteAabb> obstacles,
  ) {
    final xs = <double>{ax, bx};
    final ys = <double>{ay, by};
    for (final o in obstacles) {
      xs.addAll(<double>[o.left, o.right]);
      ys.addAll(<double>[o.bottom, o.top]);
    }
    // Extra escape lanes just outside the obstacle set so a path can skirt
    // around a cluster that sits between the endpoints.
    var minL = ax, maxR = ax, minB = ay, maxT = ay;
    for (final o in obstacles) {
      minL = math.min(minL, o.left);
      maxR = math.max(maxR, o.right);
      minB = math.min(minB, o.bottom);
      maxT = math.max(maxT, o.top);
    }
    xs.addAll(<double>[minL, maxR, bx, ax]);
    ys.addAll(<double>[minB, maxT, by, ay]);

    final xList = xs.toList()..sort();
    final yList = ys.toList()..sort();
    // Dedup with tolerance.
    final xsU = _uniqueSorted(xList);
    final ysU = _uniqueSorted(yList);
    if (xsU.isEmpty || ysU.isEmpty) return null;

    int ixOf(double v) {
      var best = 0;
      var bestD = (xsU[0] - v).abs();
      for (var i = 1; i < xsU.length; i++) {
        final d = (xsU[i] - v).abs();
        if (d < bestD) {
          best = i;
          bestD = d;
        }
      }
      return best;
    }

    int iyOf(double v) {
      var best = 0;
      var bestD = (ysU[0] - v).abs();
      for (var i = 1; i < ysU.length; i++) {
        final d = (ysU[i] - v).abs();
        if (d < bestD) {
          best = i;
          bestD = d;
        }
      }
      return best;
    }

    final nx = xsU.length;
    final ny = ysU.length;
    final start = ixOf(ax) * ny + iyOf(ay);
    final goal = ixOf(bx) * ny + iyOf(by);

    bool nodeOk(int ix, int iy) {
      final x = xsU[ix], y = ysU[iy];
      for (final o in obstacles) {
        if (o.containsPoint(x, y)) return false;
      }
      return true;
    }

    bool edgeOk(int ix1, int iy1, int ix2, int iy2) {
      final x1 = xsU[ix1], y1 = ysU[iy1];
      final x2 = xsU[ix2], y2 = ysU[iy2];
      for (final o in obstacles) {
        if (o.blocksSegment(x1, y1, x2, y2)) return false;
      }
      return true;
    }

    final n = nx * ny;
    final dist = List<double>.filled(n, double.infinity);
    final prev = List<int>.filled(n, -1);
    final used = List<bool>.filled(n, false);
    dist[start] = 0;

    for (var iter = 0; iter < n; iter++) {
      var u = -1;
      var best = double.infinity;
      for (var i = 0; i < n; i++) {
        if (!used[i] && dist[i] < best) {
          best = dist[i];
          u = i;
        }
      }
      if (u < 0 || best == double.infinity) break;
      if (u == goal) break;
      used[u] = true;
      final ux = u ~/ ny;
      final uy = u % ny;
      if (!nodeOk(ux, uy) && u != start && u != goal) continue;

      void relax(int vx, int vy) {
        if (vx < 0 || vy < 0 || vx >= nx || vy >= ny) return;
        final v = vx * ny + vy;
        if (used[v]) return;
        if (!nodeOk(vx, vy) && v != goal) return;
        if (!edgeOk(ux, uy, vx, vy)) return;
        final w = (xsU[ux] - xsU[vx]).abs() + (ysU[uy] - ysU[vy]).abs();
        final nd = dist[u] + w;
        if (nd < dist[v]) {
          dist[v] = nd;
          prev[v] = u;
        }
      }

      relax(ux - 1, uy);
      relax(ux + 1, uy);
      relax(ux, uy - 1);
      relax(ux, uy + 1);
    }

    if (dist[goal] == double.infinity) return null;

    final pathIdx = <int>[];
    for (var v = goal; v != -1; v = prev[v]) {
      pathIdx.add(v);
      if (v == start) break;
    }
    if (pathIdx.isEmpty || pathIdx.last != start) return null;
    final pts = <Offset2D>[
      for (final v in pathIdx.reversed)
        Offset2D(xsU[v ~/ ny], ysU[v % ny]),
    ];
    // Snap true endpoints (grid snap may have moved them by epsilon).
    if (pts.isNotEmpty) {
      pts[0] = Offset2D(ax, ay);
      pts[pts.length - 1] = Offset2D(bx, by);
    }
    return _simplifyOrthogonal(pts);
  }

  static List<double> _uniqueSorted(List<double> sorted) {
    if (sorted.isEmpty) return sorted;
    final out = <double>[sorted.first];
    for (var i = 1; i < sorted.length; i++) {
      if ((sorted[i] - out.last).abs() > 1e-9) out.add(sorted[i]);
    }
    return out;
  }

  /// Drop collinear intermediate vertices on an orthogonal polyline.
  static List<Offset2D> _simplifyOrthogonal(List<Offset2D> pts) {
    if (pts.length <= 2) return pts;
    final out = <Offset2D>[pts.first];
    for (var i = 1; i < pts.length - 1; i++) {
      final a = out.last;
      final b = pts[i];
      final c = pts[i + 1];
      final colinear = ((a.x - b.x).abs() < 1e-9 && (b.x - c.x).abs() < 1e-9) ||
          ((a.y - b.y).abs() < 1e-9 && (b.y - c.y).abs() < 1e-9);
      if (!colinear) out.add(b);
    }
    out.add(pts.last);
    return out;
  }
}
