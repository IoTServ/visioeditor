/// Line jumps (drawio's "Line jumps"): where one connector crosses another,
/// draw a small arc so the upper connector visibly hops over the lower one
/// instead of forming an ambiguous "+". This is a pure, render-only overlay —
/// it never touches the model or the round-trip geometry.
///
/// Geometry lives in `package:vsdx` ([Offset2D]); this file adapts to Flutter
/// [Offset] / [Path] for the canvas painter.
library;

import 'dart:ui';

import 'package:vsdx/vsdx.dart' as vsdx;

/// Whether a page's Visio `LineJumpCode` (Page Layout section) enables line
/// jumps at all. `0` (visPLOJumpNone) means the file explicitly turns jumps
/// off, so crossing connectors must draw straight through — matching how
/// Visio and 万兴图示/Edraw render such pages. Any other value (1 horizontal,
/// 2 vertical, 3 last-routed, 4/5 by z-order) or an unset code keeps the
/// hop-over overlay.
bool lineJumpsEnabledForCode(int? lineJumpCode) =>
    vsdx.lineJumpsEnabledForCode(lineJumpCode);

/// Intersection of segments `a→b` and `c→d` when they *properly* cross
/// (strictly interior to both segments), else `null`.
Offset? segmentIntersection(Offset a, Offset b, Offset c, Offset d) {
  final p = vsdx.segmentIntersection(
    vsdx.Offset2D(a.dx, a.dy),
    vsdx.Offset2D(b.dx, b.dy),
    vsdx.Offset2D(c.dx, c.dy),
    vsdx.Offset2D(d.dx, d.dy),
  );
  if (p == null) return null;
  return Offset(p.x, p.y);
}

/// Every point where polyline [route] properly crosses a segment of any
/// polyline in [unders]. Exposed for testing.
List<Offset> polylineCrossings(List<Offset> route, List<List<Offset>> unders) {
  final pts = vsdx.polylineCrossings(
    <vsdx.Offset2D>[for (final o in route) vsdx.Offset2D(o.dx, o.dy)],
    <List<vsdx.Offset2D>>[
      for (final poly in unders)
        <vsdx.Offset2D>[for (final o in poly) vsdx.Offset2D(o.dx, o.dy)],
    ],
  );
  return <Offset>[for (final p in pts) Offset(p.x, p.y)];
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

    final ts = <double>[];
    for (final poly in unders) {
      for (var j = 0; j + 1 < poly.length; j++) {
        final p = segmentIntersection(a, b, poly[j], poly[j + 1]);
        if (p != null) ts.add((p - a).distance / len);
      }
    }
    ts.sort();

    final half = r / len;
    var cursor = 0.0;
    for (final t in ts) {
      if (t - half <= cursor + 1e-6) continue;
      if (t + half >= 1 - 1e-6) break;
      final inP = a + seg * (t - half);
      final outP = a + seg * (t + half);
      path.lineTo(inP.dx, inP.dy);
      path.arcToPoint(outP, radius: Radius.circular(r), clockwise: false);
      cursor = t + half;
    }
    path.lineTo(b.dx, b.dy);
  }
  return path;
}
