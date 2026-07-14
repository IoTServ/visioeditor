/// Line jumps (drawio's "Line jumps"): where one connector crosses another,
/// draw a small arc so the upper connector visibly hops over the lower one
/// instead of forming an ambiguous "+". This is a pure, render-only overlay —
/// it never touches the model or the round-trip geometry.
///
/// All coordinates are plain [Offset]s; the caller just has to express [route]
/// and [unders] in the *same* coordinate space (the painter uses the current
/// connector's shape-local inches).
library;

import 'dart:ui';

/// Intersection of segments `a→b` and `c→d` when they *properly* cross
/// (strictly interior to both segments), else `null`.
Offset? segmentIntersection(Offset a, Offset b, Offset c, Offset d) {
  final r = b - a;
  final s = d - c;
  final denom = r.dx * s.dy - r.dy * s.dx;
  if (denom.abs() < 1e-9) return null; // parallel or collinear
  final ac = c - a;
  final t = (ac.dx * s.dy - ac.dy * s.dx) / denom;
  final u = (ac.dx * r.dy - ac.dy * r.dx) / denom;
  const eps = 1e-6;
  if (t <= eps || t >= 1 - eps || u <= eps || u >= 1 - eps) return null;
  return a + r * t;
}

/// Every point where polyline [route] properly crosses a segment of any
/// polyline in [unders]. Exposed for testing.
List<Offset> polylineCrossings(List<Offset> route, List<List<Offset>> unders) {
  final out = <Offset>[];
  for (var i = 0; i + 1 < route.length; i++) {
    for (final poly in unders) {
      for (var j = 0; j + 1 < poly.length; j++) {
        final p = segmentIntersection(route[i], route[i + 1], poly[j], poly[j + 1]);
        if (p != null) out.add(p);
      }
    }
  }
  return out;
}

/// A stroke [Path] for polyline [route] that arcs over each crossing with a
/// segment in [unders], with jump radius [r] (same units as the points). When
/// nothing crosses, the result is just the plain polyline.
Path polylineWithJumps(List<Offset> route, List<List<Offset>> unders, double r) {
  final path = Path();
  if (route.isEmpty) return path;
  path.moveTo(route.first.dx, route.first.dy);
  for (var i = 0; i + 1 < route.length; i++) {
    final a = route[i];
    final b = route[i + 1];
    final seg = b - a;
    final len = seg.distance;
    if (len < 1e-9) continue;

    // Crossing positions along this segment (param 0..1), sorted along a→b.
    final ts = <double>[];
    for (final poly in unders) {
      for (var j = 0; j + 1 < poly.length; j++) {
        final p = segmentIntersection(a, b, poly[j], poly[j + 1]);
        if (p != null) ts.add((p - a).distance / len);
      }
    }
    ts.sort();

    final half = r / len; // half the jump's chord, in segment-param units
    var cursor = 0.0;
    for (final t in ts) {
      // Skip jumps that would overlap the previous one or spill past an end.
      if (t - half <= cursor + 1e-6) continue;
      if (t + half >= 1 - 1e-6) break;
      final inP = a + seg * (t - half);
      final outP = a + seg * (t + half);
      path.lineTo(inP.dx, inP.dy);
      // Semicircle (chord = 2r, radius = r) bulging to one consistent side.
      path.arcToPoint(outP, radius: Radius.circular(r), clockwise: false);
      cursor = t + half;
    }
    path.lineTo(b.dx, b.dy);
  }
  return path;
}
