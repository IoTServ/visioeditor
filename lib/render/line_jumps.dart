/// Line jumps (drawio's "Line jumps"): where one connector crosses another,
/// draw a small hop so the upper connector visibly jumps over the lower one
/// instead of forming an ambiguous "+". This is a pure, render-only overlay —
/// it never touches the model or the round-trip geometry.
///
/// Geometry lives in `package:vsdx` ([Offset2D]); this file adapts to Flutter
/// [Offset] / [Path] for the canvas painter.
library;

import 'dart:math' as math;
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

/// A stroke [Path] for polyline [route] that hops over each crossing with a
/// segment in [unders], with jump radius [r] (same units as the points).
///
/// [style] / [pageStyle] follow Visio `ConLineJumpStyle` / `LineJumpStyle`
/// (Arc / Gap / Square). When nothing crosses, the result is the plain polyline.
Path polylineWithJumps(
  List<Offset> route,
  List<List<Offset>> unders,
  double r, {
  int? style,
  int? pageStyle,
}) {
  final path = Path();
  if (route.isEmpty) return path;
  final mode = vsdx.LineJumpRenderStyle.resolve(
    conStyle: style,
    pageStyle: pageStyle,
  );
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

    // Dense curved polylines bake short LineTo segments (often < 2r). Shrink
    // the hop so it still fits. Segments shorter than ~half the intended
    // radius cannot host a meaningful Gap — skip (neighbours cover crossings).
    if (len < r * 0.5) {
      path.lineTo(b.dx, b.dy);
      continue;
    }
    final hopR = math.min(r, len * 0.45);
    if (hopR < 1e-6) {
      path.lineTo(b.dx, b.dy);
      continue;
    }
    final half = hopR / len;
    var cursor = 0.0;
    final ux = seg.dx / len;
    final uy = seg.dy / len;
    final perp = Offset(-uy * hopR, ux * hopR);
    for (final t in ts) {
      if (t - half <= cursor + 1e-6) continue;
      if (t + half >= 1 - 1e-6) break;
      final inP = a + seg * (t - half);
      final outP = a + seg * (t + half);
      path.lineTo(inP.dx, inP.dy);
      switch (mode) {
        case vsdx.LineJumpRenderStyle.gap:
          path.moveTo(outP.dx, outP.dy);
        case vsdx.LineJumpRenderStyle.square:
          path
            ..lineTo(inP.dx + perp.dx, inP.dy + perp.dy)
            ..lineTo(outP.dx + perp.dx, outP.dy + perp.dy)
            ..lineTo(outP.dx, outP.dy);
        case vsdx.LineJumpRenderStyle.arc:
          path.arcToPoint(
            outP,
            radius: Radius.circular(hopR),
            clockwise: false,
          );
      }
      cursor = t + half;
    }
    path.lineTo(b.dx, b.dy);
  }
  return path;
}
