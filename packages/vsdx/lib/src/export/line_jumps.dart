/// Line jumps for SVG/PDF export (and shared with the Flutter canvas).
///
/// Where one connector crosses another, draw a small hop so the upper
/// connector jumps over the lower one instead of forming an ambiguous "+".
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

/// Visio `LineJumpStyle` / `ConLineJumpStyle` → render mode.
///
/// Page: 0/1 = Arc, 2 = Gap, 3 = Square (higher values ≈ Arc).
/// Shape `ConLineJumpStyle`: 0 = page default, 1 = Arc, 2 = Gap, 3 = Square.
enum LineJumpRenderStyle {
  arc,
  gap,
  square;

  /// Resolve [conStyle] (shape) over [pageStyle] (page layout).
  static LineJumpRenderStyle resolve({int? conStyle, int? pageStyle}) {
    final raw = (conStyle != null && conStyle != 0) ? conStyle : pageStyle;
    return switch (raw) {
      2 => LineJumpRenderStyle.gap,
      3 => LineJumpRenderStyle.square,
      _ => LineJumpRenderStyle.arc,
    };
  }
}

/// Resolve shape `ConLineJumpDir*` over page `PageLineJumpDir*` (0 = inherit).
int? effectiveLineJumpDir(int? conDir, int? pageDir) {
  if (conDir != null && conDir != 0) return conDir;
  if (pageDir != null && pageDir != 0) return pageDir;
  return null;
}

/// Sign for the left-hand hop normal given Visio JumpDir cells.
///
/// `ConLineJumpDirX` / `PageLineJumpDirX`: 0 default, 1 Up (+Y), 2 Down (−Y)
/// on horizontal spans. `*DirY`: 0 default, 1 Left (−X), 2 Right (+X) on
/// vertical spans. Default keeps the CCW (left-hand) hop used historically.
double lineJumpHopSign({
  required double sdx,
  required double sdy,
  int? dirX,
  int? dirY,
}) {
  final horiz = sdx.abs() >= sdy.abs();
  if (horiz) {
    final d = dirX ?? 0;
    if (d == 1) return sdx >= 0 ? 1.0 : -1.0;
    if (d == 2) return sdx >= 0 ? -1.0 : 1.0;
  } else {
    final d = dirY ?? 0;
    if (d == 1) return sdy >= 0 ? 1.0 : -1.0;
    if (d == 2) return sdy >= 0 ? -1.0 : 1.0;
  }
  return 1.0;
}

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

/// SVG path `d` for [route] that hops over each crossing with a segment in
/// [unders], with jump radius [r] (same units as the points).
///
/// [style] is Visio `ConLineJumpStyle` or page `LineJumpStyle` (null → Arc).
/// Arc uses `A r r 0 0 0` (sweep=0 = counter-clockwise), matching Flutter
/// `arcToPoint(..., clockwise: false)`.
String polylineWithJumpsSvg(
  List<Offset2D> route,
  List<List<Offset2D>> unders,
  double r, {
  int? style,
  int? pageStyle,
  int? dirX,
  int? dirY,
  String Function(double) format = _defaultFormat,
}) {
  if (route.isEmpty) return '';
  final mode = LineJumpRenderStyle.resolve(conStyle: style, pageStyle: pageStyle);
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

    // Dense curved polylines bake short LineTo segments (often < 2r). Shrink
    // the hop so it still fits. Segments shorter than ~half the intended
    // radius cannot host a meaningful Gap — skip (neighbours cover crossings).
    if (len < r * 0.5) {
      buf.write(' L ${format(b.x)} ${format(b.y)}');
      continue;
    }
    final hopR = math.min(r, len * 0.45);
    if (hopR < 1e-6) {
      buf.write(' L ${format(b.x)} ${format(b.y)}');
      continue;
    }
    final half = hopR / len;
    var cursor = 0.0;
    final ux = sdx / len;
    final uy = sdy / len;
    final hopSign = lineJumpHopSign(
      sdx: sdx,
      sdy: sdy,
      dirX: dirX,
      dirY: dirY,
    );
    // Left-hand perpendicular (CCW), optionally flipped by JumpDir.
    final px = -uy * hopR * hopSign;
    final py = ux * hopR * hopSign;
    final sweep = hopSign < 0 ? 1 : 0;
    for (final t in ts) {
      if (t - half <= cursor + 1e-6) continue;
      if (t + half >= 1 - 1e-6) break;
      final inX = a.x + sdx * (t - half);
      final inY = a.y + sdy * (t - half);
      final outX = a.x + sdx * (t + half);
      final outY = a.y + sdy * (t + half);
      buf.write(' L ${format(inX)} ${format(inY)}');
      switch (mode) {
        case LineJumpRenderStyle.gap:
          buf.write(' M ${format(outX)} ${format(outY)}');
        case LineJumpRenderStyle.square:
          buf.write(
            ' L ${format(inX + px)} ${format(inY + py)}'
            ' L ${format(outX + px)} ${format(outY + py)}'
            ' L ${format(outX)} ${format(outY)}',
          );
        case LineJumpRenderStyle.arc:
          buf.write(
            ' A ${format(hopR)} ${format(hopR)} 0 0 $sweep '
            '${format(outX)} ${format(outY)}',
          );
      }
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
