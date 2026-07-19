/// Line jumps for SVG/PDF export (and shared with the Flutter canvas).
///
/// Where one connector crosses another, draw a small semicircle so the upper
/// connector hops over the lower one instead of forming an ambiguous "+".
/// Render-only — never mutates model geometry.
library;

import 'dart:math' as math;

import '../model/geometry.dart';

/// Default hop radius in inches (matches the canvas default closely).
const double kDefaultLineJumpRadiusInches = 0.07;

/// Whether a page's Visio `LineJumpCode` enables line jumps.
///
/// `0` (visPLOJumpNone) turns jumps off. Any other value or an unset code
/// keeps the hop-over overlay (Visio / Edraw behaviour).
bool lineJumpsEnabledForCode(int? lineJumpCode) => lineJumpCode != 0;

/// Intersection of segments `a→b` and `c→d` when they *properly* cross
/// (strictly interior to both segments), else `null`.
Offset2D? segmentIntersection(
  Offset2D a,
  Offset2D b,
  Offset2D c,
  Offset2D d,
) {
  final rdx = b.x - a.x;
  final rdy = b.y - a.y;
  final sdx = d.x - c.x;
  final sdy = d.y - c.y;
  final denom = rdx * sdy - rdy * sdx;
  if (denom.abs() < 1e-9) return null;
  final acx = c.x - a.x;
  final acy = c.y - a.y;
  final t = (acx * sdy - acy * sdx) / denom;
  final u = (acx * rdy - acy * rdx) / denom;
  const eps = 1e-6;
  if (t <= eps || t >= 1 - eps || u <= eps || u >= 1 - eps) return null;
  return Offset2D(a.x + rdx * t, a.y + rdy * t);
}

/// Every point where polyline [route] properly crosses a segment of any
/// polyline in [unders].
List<Offset2D> polylineCrossings(
  List<Offset2D> route,
  List<List<Offset2D>> unders,
) {
  final out = <Offset2D>[];
  for (var i = 0; i + 1 < route.length; i++) {
    for (final poly in unders) {
      for (var j = 0; j + 1 < poly.length; j++) {
        final p = segmentIntersection(
          route[i],
          route[i + 1],
          poly[j],
          poly[j + 1],
        );
        if (p != null) out.add(p);
      }
    }
  }
  return out;
}

/// SVG path `d` for [route] that arcs over each crossing with a segment in
/// [unders], with jump radius [r] (same units as the points).
///
/// Semicircle uses `A r r 0 0 0` (sweep=0 = counter-clockwise), matching
/// Flutter `arcToPoint(..., clockwise: false)`.
String polylineWithJumpsSvg(
  List<Offset2D> route,
  List<List<Offset2D>> unders,
  double r, {
  String Function(double) format = _defaultFormat,
}) {
  if (route.isEmpty) return '';
  final buf = StringBuffer('M ${format(route.first.x)} ${format(route.first.y)}');
  for (var i = 0; i + 1 < route.length; i++) {
    final a = route[i];
    final b = route[i + 1];
    final sdx = b.x - a.x;
    final sdy = b.y - a.y;
    final len = math.sqrt(sdx * sdx + sdy * sdy);
    if (len < 1e-9) continue;

    final ts = <double>[];
    for (final poly in unders) {
      for (var j = 0; j + 1 < poly.length; j++) {
        final p = segmentIntersection(a, b, poly[j], poly[j + 1]);
        if (p != null) {
          final dx = p.x - a.x;
          final dy = p.y - a.y;
          ts.add(math.sqrt(dx * dx + dy * dy) / len);
        }
      }
    }
    ts.sort();

    final half = r / len;
    var cursor = 0.0;
    for (final t in ts) {
      if (t - half <= cursor + 1e-6) continue;
      if (t + half >= 1 - 1e-6) break;
      final inX = a.x + sdx * (t - half);
      final inY = a.y + sdy * (t - half);
      final outX = a.x + sdx * (t + half);
      final outY = a.y + sdy * (t + half);
      buf.write(' L ${format(inX)} ${format(inY)}');
      buf.write(
        ' A ${format(r)} ${format(r)} 0 0 0 ${format(outX)} ${format(outY)}',
      );
      cursor = t + half;
    }
    buf.write(' L ${format(b.x)} ${format(b.y)}');
  }
  return buf.toString();
}

/// Plain polyline SVG `d` (no jumps).
String polylineSvg(
  List<Offset2D> route, {
  String Function(double) format = _defaultFormat,
}) {
  if (route.isEmpty) return '';
  final buf = StringBuffer('M ${format(route.first.x)} ${format(route.first.y)}');
  for (var i = 1; i < route.length; i++) {
    buf.write(' L ${format(route[i].x)} ${format(route[i].y)}');
  }
  return buf.toString();
}

String _defaultFormat(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(4);
}
