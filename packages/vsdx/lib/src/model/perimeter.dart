/// Geometry-aware shape perimeter helpers (draw.io-style edge attach).
///
/// Whole-shape glue (`ToPart=3`) should land on the **drawn outline**, not the
/// Width×Height selection AABB — otherwise diamonds / ellipses / polygons
/// leave a visible gap between the connector tip and the filled body.
library;

import 'dart:math' as math;

import 'elliptical_arc.dart';
import 'geometry.dart';
import 'nurbs.dart';
import 'shape.dart';

/// Ray / nearest-point queries against a shape's Geometry outline.
abstract final class ShapePerimeter {
  /// Page-space point where a ray from [pinPage] toward ([towardX],[towardY])
  /// first meets [shape]'s outline. Falls back to the local Width×Height box
  /// when geometry is missing or the ray misses every segment.
  ///
  /// [localToPage] / [pageToLocal] compose ancestor XForms (see
  /// [VsdxPage.localToPageDeep]).
  static Offset2D attachToward(
    VsdxShape shape, {
    required Offset2D pinPage,
    required double towardX,
    required double towardY,
    required Offset2D Function(Offset2D local) localToPage,
    required Offset2D Function(Offset2D page) pageToLocal,
  }) {
    final dx = towardX - pinPage.x;
    final dy = towardY - pinPage.y;
    if (dx.abs() < 1e-12 && dy.abs() < 1e-12) return pinPage;

    final localFrom = Offset2D(
      shape.effectiveLocPinX,
      shape.effectiveLocPinY,
    );
    final localToward = pageToLocal(Offset2D(towardX, towardY));
    final localHit = rayIntersectLocal(shape, localFrom, localToward) ??
        _aabbEdgeLocal(shape, localFrom, localToward);
    return localToPage(localHit);
  }

  /// Nearest point on [shape]'s outline (local inches) to [local], or `null`
  /// when the outline is empty.
  static Offset2D? nearestLocal(VsdxShape shape, Offset2D local) {
    final segs = outlineSegments(shape);
    if (segs.isEmpty) return null;
    Offset2D? best;
    var bestD = double.infinity;
    for (final (a, b) in segs) {
      final p = _closestOnSegment(local, a, b);
      final d = _dist2(local, p);
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
    return best;
  }

  /// Local-inch intersection of the ray [from] → [toward] with [shape]'s
  /// outline, preferring the **farthest** hit with t ≥ 0 (exit point from an
  /// interior origin). Returns `null` when nothing is hit.
  static Offset2D? rayIntersectLocal(
    VsdxShape shape,
    Offset2D from,
    Offset2D toward,
  ) {
    final rdx = toward.x - from.x;
    final rdy = toward.y - from.y;
    if (rdx.abs() < 1e-12 && rdy.abs() < 1e-12) return null;

    var bestT = -1.0;
    Offset2D? best;

    void consider(double t, Offset2D p) {
      if (t < 0) return;
      if (t > bestT) {
        bestT = t;
        best = p;
      }
    }

    for (final (a, b) in outlineSegments(shape)) {
      final t = _raySegmentT(from, rdx, rdy, a, b);
      if (t != null) {
        consider(t, Offset2D(from.x + rdx * t, from.y + rdy * t));
      }
    }

    // Analytical axis-aligned ellipses (common stencil) for sharper tips.
    for (final g in shape.geometries) {
      if (g.noShow || g.noSnap) continue;
      for (final c in g.commands) {
        if (c is! EllipseCmd) continue;
        final hit = _rayEllipse(from, rdx, rdy, c);
        if (hit != null) consider(hit.$1, hit.$2);
      }
    }

    return best;
  }

  /// Flatten visible Geometry into line segments in shape-local inches.
  /// Curves are sampled; axis-aligned `EllipseCmd` also has an analytical
  /// ray path in [rayIntersectLocal].
  static List<(Offset2D, Offset2D)> outlineSegments(VsdxShape shape) {
    final w = shape.width;
    final h = shape.height;
    final out = <(Offset2D, Offset2D)>[];
    for (final g in shape.geometries) {
      if (g.noShow || g.noSnap || g.noLine && g.noFill) continue;
      var cx = 0.0, cy = 0.0;
      var has = false;
      Offset2D? subStart;

      void emit(double x, double y) {
        final p = Offset2D(x, y);
        if (has) {
          out.add((Offset2D(cx, cy), p));
        } else {
          subStart = p;
        }
        cx = x;
        cy = y;
        has = true;
      }

      void move(double x, double y) {
        cx = x;
        cy = y;
        has = true;
        subStart = Offset2D(x, y);
      }

      for (final cmd in g.commands) {
        switch (cmd) {
          case MoveTo(:final x, :final y):
            move(x, y);
          case RelMoveTo(:final fx, :final fy):
            move(fx * w, fy * h);
          case LineTo(:final x, :final y):
            if (!has) move(0, 0);
            emit(x, y);
          case RelLineTo(:final fx, :final fy):
            if (!has) move(0, 0);
            emit(fx * w, fy * h);
          case CubBezTo(
              :final x,
              :final y,
              :final x1,
              :final y1,
              :final x2,
              :final y2,
            ):
            if (!has) move(0, 0);
            _sampleCubic(
              out,
              Offset2D(cx, cy),
              Offset2D(x1, y1),
              Offset2D(x2, y2),
              Offset2D(x, y),
            );
            cx = x;
            cy = y;
          case RelCubBezTo(
              :final fx,
              :final fy,
              :final fx1,
              :final fy1,
              :final fx2,
              :final fy2,
            ):
            if (!has) move(0, 0);
            final ex = fx * w, ey = fy * h;
            _sampleCubic(
              out,
              Offset2D(cx, cy),
              Offset2D(fx1 * w, fy1 * h),
              Offset2D(fx2 * w, fy2 * h),
              Offset2D(ex, ey),
            );
            cx = ex;
            cy = ey;
          case QuadBezTo(:final x, :final y, :final x1, :final y1):
            if (!has) move(0, 0);
            _sampleQuad(
              out,
              Offset2D(cx, cy),
              Offset2D(x1, y1),
              Offset2D(x, y),
            );
            cx = x;
            cy = y;
          case RelQuadBezTo(:final fx, :final fy, :final fx1, :final fy1):
            if (!has) move(0, 0);
            final ex = fx * w, ey = fy * h;
            _sampleQuad(
              out,
              Offset2D(cx, cy),
              Offset2D(fx1 * w, fy1 * h),
              Offset2D(ex, ey),
            );
            cx = ex;
            cy = ey;
          case ArcTo(:final x, :final y, :final bow):
            if (!has) move(0, 0);
            _sampleArcByBow(out, Offset2D(cx, cy), Offset2D(x, y), bow);
            cx = x;
            cy = y;
          case RelArcTo(:final fx, :final fy, :final fbow):
            if (!has) move(0, 0);
            final ex = fx * w, ey = fy * h;
            final bow = fbow * (w + h) / 2;
            _sampleArcByBow(out, Offset2D(cx, cy), Offset2D(ex, ey), bow);
            cx = ex;
            cy = ey;
          case EllipticalArcTo(
              :final x,
              :final y,
              :final controlX,
              :final controlY,
              :final angle,
              :final eccentricity,
            ):
            if (!has) move(0, 0);
            final samples = sampleEllipticalArc(
              start: Offset2D(cx, cy),
              end: Offset2D(x, y),
              control: Offset2D(controlX, controlY),
              angle: angle,
              eccentricity: eccentricity,
            );
            for (final p in samples) {
              emit(p.x, p.y);
            }
            cx = x;
            cy = y;
          case RelEllipticalArcTo(
              :final fx,
              :final fy,
              :final fcx,
              :final fcy,
              :final angle,
              :final eccentricity,
            ):
            if (!has) move(0, 0);
            final ex = fx * w, ey = fy * h;
            final samples = sampleEllipticalArc(
              start: Offset2D(cx, cy),
              end: Offset2D(ex, ey),
              control: Offset2D(fcx * w, fcy * h),
              angle: angle,
              eccentricity: eccentricity,
            );
            for (final p in samples) {
              emit(p.x, p.y);
            }
            cx = ex;
            cy = ey;
          case final EllipseCmd ell:
            // Analytical path in [rayIntersectLocal]; still sample for nearest.
            _sampleEllipse(out, ell, close: true);
            has = false;
            subStart = null;
          case PolylineTo(:final x, :final y, :final vertices, :final relative):
            if (!has) move(0, 0);
            final sx = relative ? w : 1.0;
            final sy = relative ? h : 1.0;
            for (final v in vertices) {
              emit(v.x * sx, v.y * sy);
            }
            emit(x * sx, y * sy);
          case SplineStart(:final x, :final y, :final relative):
            final px = relative ? x * w : x;
            final py = relative ? y * h : y;
            if (!has) {
              move(px, py);
            } else {
              emit(px, py);
            }
          case SplineKnot(:final x, :final y, :final relative):
            final px = relative ? x * w : x;
            final py = relative ? y * h : y;
            if (!has) move(px, py);
            emit(px, py);
          case NurbsTo(
              :final x,
              :final y,
              :final controlPoints,
              :final weights,
              :final knots,
              :final degree,
              :final relative,
            ):
            if (!has) move(0, 0);
            final sx = relative ? w : 1.0;
            final sy = relative ? h : 1.0;
            final samples = sampleNurbs(
              start: Offset2D(cx, cy),
              end: Offset2D(x * sx, y * sy),
              controlPoints: <Offset2D>[
                for (final p in controlPoints) Offset2D(p.x * sx, p.y * sy),
              ],
              weights: weights,
              knots: knots,
              degree: degree,
            );
            for (final p in samples) {
              emit(p.x, p.y);
            }
          case InfiniteLineCmd():
            break;
        }
      }
      // Close open subpaths that look closed (common for polygons).
      if (has && subStart != null) {
        final dx = cx - subStart!.x;
        final dy = cy - subStart!.y;
        if (dx * dx + dy * dy > 1e-12) {
          // leave open — Visio closed paths usually repeat the start vertex
        }
      }
    }

    // No geometry → local AABB edges so callers still get a perimeter.
    if (out.isEmpty && w > 0 && h > 0) {
      final bl = const Offset2D(0, 0);
      final br = Offset2D(w, 0);
      final tr = Offset2D(w, h);
      final tl = Offset2D(0, h);
      out
        ..add((bl, br))
        ..add((br, tr))
        ..add((tr, tl))
        ..add((tl, bl));
    }
    return out;
  }

  static Offset2D _aabbEdgeLocal(
    VsdxShape s,
    Offset2D from,
    Offset2D toward,
  ) {
    final dx = toward.x - from.x;
    final dy = toward.y - from.y;
    if (dx == 0 && dy == 0) return from;
    final hw = s.width / 2;
    final hh = s.height / 2;
    // from is typically LocPin ≈ (w/2,h/2); express ray in centre-relative form
    final ox = from.x;
    final oy = from.y;
    final cx = s.width / 2;
    final cy = s.height / 2;
    final rdx = toward.x - cx;
    final rdy = toward.y - cy;
    if (rdx == 0 && rdy == 0) return Offset2D(ox, oy);
    final sx = rdx == 0 ? double.infinity : hw / rdx.abs();
    final sy = rdy == 0 ? double.infinity : hh / rdy.abs();
    final t = math.min(sx, sy);
    return Offset2D(cx + rdx * t, cy + rdy * t);
  }
}

double _dist2(Offset2D a, Offset2D b) {
  final dx = a.x - b.x, dy = a.y - b.y;
  return dx * dx + dy * dy;
}

Offset2D _closestOnSegment(Offset2D p, Offset2D a, Offset2D b) {
  final abx = b.x - a.x, aby = b.y - a.y;
  final len2 = abx * abx + aby * aby;
  if (len2 < 1e-18) return a;
  var t = ((p.x - a.x) * abx + (p.y - a.y) * aby) / len2;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  return Offset2D(a.x + abx * t, a.y + aby * t);
}

/// Parametric t ≥ 0 for ray P + t·D intersecting segment AB, or `null`.
double? _raySegmentT(
  Offset2D p,
  double dx,
  double dy,
  Offset2D a,
  Offset2D b,
) {
  final ex = b.x - a.x, ey = b.y - a.y;
  final denom = dx * ey - dy * ex;
  if (denom.abs() < 1e-14) return null; // parallel
  final ax = a.x - p.x, ay = a.y - p.y;
  final t = (ax * ey - ay * ex) / denom;
  final u = (ax * dy - ay * dx) / denom;
  if (t < -1e-9 || u < -1e-9 || u > 1 + 1e-9) return null;
  return t < 0 ? 0.0 : t;
}

(double, Offset2D)? _rayEllipse(
  Offset2D from,
  double dx,
  double dy,
  EllipseCmd e,
) {
  // Conjugate-diameter form: P(θ) = C + A·cosθ + B·sinθ.
  // Solve (from − C + t·D) against the quadratic form of that ellipse.
  final ax = e.aX - e.cx, ay = e.aY - e.cy;
  final bx = e.bX - e.cx, by = e.bY - e.cy;
  // Inverse of [A B]: map local offset → (u,v) on unit circle u²+v²=1.
  final det = ax * by - ay * bx;
  if (det.abs() < 1e-18) return null;
  final inv = 1.0 / det;
  // M maps page-local offset → unit-circle coords:
  //   u =  ( by·ox - bx·oy) / det
  //   v =  (-ay·ox + ax·oy) / det
  double mapU(double ox, double oy) => (by * ox - bx * oy) * inv;
  double mapV(double ox, double oy) => (-ay * ox + ax * oy) * inv;

  final ox = from.x - e.cx;
  final oy = from.y - e.cy;
  final fu = mapU(ox, oy);
  final fv = mapV(ox, oy);
  final du = mapU(dx, dy);
  final dv = mapV(dx, dy);
  final a = du * du + dv * dv;
  final b = 2 * (fu * du + fv * dv);
  final c = fu * fu + fv * fv - 1;
  final disc = b * b - 4 * a * c;
  if (disc < 0 || a.abs() < 1e-18) return null;
  final sq = math.sqrt(disc);
  final t1 = (-b - sq) / (2 * a);
  final t2 = (-b + sq) / (2 * a);
  // Farthest non-negative t (exit from interior LocPin).
  double? t;
  if (t1 >= -1e-9) t = t1;
  if (t2 >= -1e-9 && (t == null || t2 > t)) t = t2;
  if (t == null) return null;
  if (t < 0) t = 0;
  return (
    t,
    Offset2D(from.x + dx * t, from.y + dy * t),
  );
}

void _sampleCubic(
  List<(Offset2D, Offset2D)> out,
  Offset2D p0,
  Offset2D p1,
  Offset2D p2,
  Offset2D p3, {
  int steps = 8,
}) {
  var prev = p0;
  for (var i = 1; i <= steps; i++) {
    final t = i / steps;
    final u = 1 - t;
    final p = Offset2D(
      u * u * u * p0.x +
          3 * u * u * t * p1.x +
          3 * u * t * t * p2.x +
          t * t * t * p3.x,
      u * u * u * p0.y +
          3 * u * u * t * p1.y +
          3 * u * t * t * p2.y +
          t * t * t * p3.y,
    );
    out.add((prev, p));
    prev = p;
  }
}

void _sampleQuad(
  List<(Offset2D, Offset2D)> out,
  Offset2D p0,
  Offset2D p1,
  Offset2D p2, {
  int steps = 8,
}) {
  var prev = p0;
  for (var i = 1; i <= steps; i++) {
    final t = i / steps;
    final u = 1 - t;
    final p = Offset2D(
      u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
      u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y,
    );
    out.add((prev, p));
    prev = p;
  }
}

void _sampleArcByBow(
  List<(Offset2D, Offset2D)> out,
  Offset2D p0,
  Offset2D p1,
  double bow, {
  int steps = 10,
}) {
  if (bow.abs() < 1e-12) {
    out.add((p0, p1));
    return;
  }
  final mx = (p0.x + p1.x) / 2;
  final my = (p0.y + p1.y) / 2;
  final dx = p1.x - p0.x;
  final dy = p1.y - p0.y;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 1e-12) return;
  final nx = -dy / len;
  final ny = dx / len;
  final ctrl = Offset2D(mx + nx * bow, my + ny * bow);
  _sampleQuad(out, p0, ctrl, p1, steps: steps);
}

void _sampleEllipse(
  List<(Offset2D, Offset2D)> out,
  EllipseCmd e, {
  bool close = true,
  int steps = 32,
}) {
  // Match path_builder / SVG: conjugate diameters (handles non-orthogonal A/B
  // after non-uniform scale of a rotated ellipse).
  final ax = e.aX - e.cx, ay = e.aY - e.cy;
  final bx = e.bX - e.cx, by = e.bY - e.cy;
  if (ax * ax + ay * ay < 1e-24 || bx * bx + by * by < 1e-24) return;
  Offset2D pt(double th) {
    final cosT = math.cos(th), sinT = math.sin(th);
    return Offset2D(
      e.cx + ax * cosT + bx * sinT,
      e.cy + ay * cosT + by * sinT,
    );
  }

  var prev = pt(0);
  for (var i = 1; i <= steps; i++) {
    final p = pt(2 * math.pi * i / steps);
    out.add((prev, p));
    prev = p;
  }
  if (close) {
    // last sample already returns to start when i==steps
  }
}
