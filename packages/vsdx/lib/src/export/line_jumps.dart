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

/// Whether a page's Visio `LineJumpCode` enables line jumps at all.
///
/// `0` (visPLOJumpNone) turns jumps off. Any other value or an unset code
/// keeps the hop-over overlay (Visio / Edraw behaviour). Per-segment
/// horizontal/vertical filtering is [lineJumpAppliesToSegment].
bool lineJumpsEnabledForCode(int? lineJumpCode) => lineJumpCode != 0;

/// Whether this connector should render hops.
///
/// Visio `ConLineJumpCode`:
/// * `0` — follow page [pageLineJumpCode]
/// * `1` — Never
/// * `2` — Always (even when page is None)
/// * `3` — Other connector jumps (this shape does not hop)
/// * `4` — Neither connector jumps
bool connectorLineJumpsEnabled(
  int? conLineJumpCode, {
  int? pageLineJumpCode,
}) {
  final c = conLineJumpCode ?? 0;
  if (c == 1 || c == 3 || c == 4) return false;
  if (c == 2) return true;
  return lineJumpsEnabledForCode(pageLineJumpCode);
}

/// Whether a route segment should host hops for the page's `LineJumpCode`.
///
/// `1` = horizontal only, `2` = vertical only; other non-zero codes accept all.
bool lineJumpAppliesToSegment(int? pageJumpCode, double sdx, double sdy) {
  final horiz = sdx.abs() >= sdy.abs();
  return switch (pageJumpCode) {
    1 => horiz,
    2 => !horiz,
    _ => true,
  };
}

/// `LineJumpCode` 5 = first displayed (bottom of z-order) hops over later ones.
bool lineJumpsReverseDisplayOrder(int? pageJumpCode) => pageJumpCode == 5;

/// Whether connector at z-index [k] has any peers to hop over.
///
/// Prefer this over a bare z-order gate — `ConLineJumpCode` Other/Always can
/// force hops even when [k] is first (or last) in paint order.
bool lineJumpShapeMayHop({
  required int k,
  required int routeCount,
  required int? pageJumpCode,
  int? selfConCode,
  List<int?>? peerConCodes,
}) {
  if (!connectorLineJumpsEnabled(
    selfConCode,
    pageLineJumpCode: pageJumpCode,
  )) {
    return false;
  }
  return lineJumpPeerIndices(
    k: k,
    routeCount: routeCount,
    pageJumpCode: pageJumpCode,
    selfConCode: selfConCode,
    peerConCodes: peerConCodes,
  ).isNotEmpty;
}

/// Peer route indices that [k] should hop over.
///
/// Normal (`4` / unset): hop over lower z (`i < k`).
/// Reverse (`5`): hop over higher z (`i > k`).
///
/// [peerConCodes] (parallel to routes) applies Visio ConLineJumpCode peers:
/// * peer `4` (Neither) — never hop that crossing
/// * peer `3` (Other) — force hop even when z-order would not (they refuse)
/// * self `2` (Always) — hop over every other non-Neither peer
/// * self + peer both `3` — no hop (symmetric Other)
List<int> lineJumpPeerIndices({
  required int k,
  required int routeCount,
  required int? pageJumpCode,
  int? selfConCode,
  List<int?>? peerConCodes,
}) {
  final peers = <int>[];
  final self = selfConCode ?? 0;
  if (self == 2) {
    // Always — ignore page z-order; hop every other non-Neither connector.
    for (var i = 0; i < routeCount; i++) {
      if (i == k) continue;
      final peer = (peerConCodes != null && i < peerConCodes.length)
          ? (peerConCodes[i] ?? 0)
          : 0;
      if (peer != 4) peers.add(i);
    }
    return peers;
  }
  if (lineJumpsReverseDisplayOrder(pageJumpCode)) {
    for (var i = k + 1; i < routeCount; i++) {
      peers.add(i);
    }
  } else {
    for (var i = 0; i < k; i++) {
      peers.add(i);
    }
  }
  if (peerConCodes != null) {
    for (var i = 0; i < routeCount && i < peerConCodes.length; i++) {
      if (i == k) continue;
      final peer = peerConCodes[i] ?? 0;
      if (peer == 3 && self != 3 && !peers.contains(i)) {
        peers.add(i);
      }
    }
    peers.removeWhere((i) {
      if (i < 0 || i >= peerConCodes.length) return false;
      return (peerConCodes[i] ?? 0) == 4;
    });
  }
  return peers;
}

/// Resolve hop radius from page `LineToLine*` × `LineJumpFactor*` (or default).
double pageLineJumpRadius({
  double? lineToLineInches,
  double? jumpFactor,
}) {
  if (lineToLineInches != null &&
      jumpFactor != null &&
      lineToLineInches > 0 &&
      jumpFactor > 0) {
    return lineToLineInches * jumpFactor;
  }
  return kDefaultLineJumpRadiusInches;
}

/// Prefer page-derived radius when the UI still uses the engine default.
double resolveLineJumpRadius({
  required double uiRadius,
  double? lineToLineInches,
  double? jumpFactor,
}) {
  if ((uiRadius - kDefaultLineJumpRadiusInches).abs() < 1e-9) {
    return pageLineJumpRadius(
      lineToLineInches: lineToLineInches,
      jumpFactor: jumpFactor,
    );
  }
  return uiRadius;
}

/// Visio `LineJumpStyle` / `ConLineJumpStyle` → render mode.
///
/// Page: 0/1 = Arc, 2 = Gap, 3 = Square (higher values ≈ Arc).
/// Shape `ConLineJumpStyle`: 0 = page default, 1 = Arc, 2 = Gap, 3 = Square.
enum LineJumpRenderStyle {
  arc,
  gap,
  square,
  line;

  /// Resolve [conStyle] (shape) over [pageStyle] (page layout).
  static LineJumpRenderStyle resolve({
    int? conStyle,
    int? pageStyle,
    String? customStyle,
  }) {
    if (customStyle == 'line') return LineJumpRenderStyle.line;
    if (customStyle == 'gap') return LineJumpRenderStyle.gap;
    if (customStyle == 'sharp') return LineJumpRenderStyle.square;
    if (customStyle == 'arc') return LineJumpRenderStyle.arc;
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
/// When [radiusY] is set, vertical segments use it instead of [r].
/// [pageJumpCode] filters hops to horizontal (`1`) or vertical (`2`) only.
///
/// [style] is Visio `ConLineJumpStyle` or page `LineJumpStyle` (null → Arc).
/// Arc uses `A r r 0 0 0` (sweep=0 = counter-clockwise), matching Flutter
/// `arcToPoint(..., clockwise: false)`.
String polylineWithJumpsSvg(
  List<Offset2D> route,
  List<List<Offset2D>> unders,
  double r, {
  double? radiusY,
  int? pageJumpCode,
  int? style,
  int? pageStyle,
  String? customStyle,
  int? dirX,
  int? dirY,
  String Function(double) format = _defaultFormat,
}) {
  if (route.isEmpty) return '';
  final mode = LineJumpRenderStyle.resolve(
    conStyle: style,
    pageStyle: pageStyle,
    customStyle: customStyle,
  );
  final buf = StringBuffer('M ${format(route.first.x)} ${format(route.first.y)}');
  for (var i = 0; i + 1 < route.length; i++) {
    final a = route[i];
    final b = route[i + 1];
    final sdx = b.x - a.x;
    final sdy = b.y - a.y;
    final len = math.sqrt(sdx * sdx + sdy * sdy);
    if (len < 1e-9) continue;

    final horiz = sdx.abs() >= sdy.abs();
    final segR = (!horiz && radiusY != null) ? radiusY : r;
    if (!lineJumpAppliesToSegment(pageJumpCode, sdx, sdy)) {
      buf.write(' L ${format(b.x)} ${format(b.y)}');
      continue;
    }

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
    if (len < segR * 0.5) {
      buf.write(' L ${format(b.x)} ${format(b.y)}');
      continue;
    }
    final hopR = math.min(segR, len * 0.45);
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
        case LineJumpRenderStyle.line:
          buf.write(
            ' M ${format(inX + px)} ${format(inY + py)}'
            ' L ${format(inX - px)} ${format(inY - py)}'
            ' M ${format(outX - px)} ${format(outY - py)}'
            ' L ${format(outX + px)} ${format(outY + py)}'
            ' M ${format(outX)} ${format(outY)}',
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
