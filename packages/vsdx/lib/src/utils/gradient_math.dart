/// Shared Visio gradient helpers (SVG export + Flutter canvas).
library;

import 'dart:math' as math;

/// Visio `FillGradientDir` / `LineGradientDir` 1–7 → radial origin within
/// an axis-aligned box. `4` / `null` / unknown → centre.
({double x, double y}) radialGradientOrigin({
  int? dir,
  required double minX,
  required double minY,
  required double width,
  required double height,
}) {
  final left = minX;
  final right = minX + width;
  final top = minY;
  final bottom = minY + height;
  final cx = left + width / 2;
  final cy = top + height / 2;
  return switch (dir) {
    1 => (x: left, y: top),
    2 => (x: cx, y: top),
    3 => (x: right, y: top),
    5 => (x: left, y: bottom),
    6 => (x: cx, y: bottom),
    7 => (x: right, y: bottom),
    _ => (x: cx, y: cy), // 4 / null / legacy
  };
}

/// Sample canvas / SVG `_buildGradientShader` at a point in the same
/// user-space inches (Y-up). Linear uses the box centre ± 0.6×longest side
/// along [angleRad]; radial / rectangular / path use [radialGradientOrigin]
/// and the same radius.
({int r, int g, int b, int a}) sampleVisioGradientRgba({
  required double x,
  required double y,
  required double minX,
  required double minY,
  required double width,
  required double height,
  required bool linear,
  required double angleRad,
  int? dir,
  required List<({double position, int r, int g, int b, int a})> stops,
}) {
  final t = linear
      ? _linearGradientT(
          x,
          y,
          minX: minX,
          minY: minY,
          width: width,
          height: height,
          angleRad: angleRad,
        )
      : _radialGradientT(
          x,
          y,
          minX: minX,
          minY: minY,
          width: width,
          height: height,
          dir: dir,
        );
  return _lerpGradientStops(stops, t);
}

double _linearGradientT(
  double x,
  double y, {
  required double minX,
  required double minY,
  required double width,
  required double height,
  required double angleRad,
}) {
  final cx = minX + width / 2;
  final cy = minY + height / 2;
  final reach = math.max(width.abs(), height.abs()) * 0.6;
  final dx = math.cos(angleRad) * reach;
  final dy = math.sin(angleRad) * reach;
  final x1 = cx - dx;
  final y1 = cy - dy;
  final vx = dx * 2;
  final vy = dy * 2;
  final denom = vx * vx + vy * vy;
  if (denom <= 1e-18) return 0.5;
  return ((x - x1) * vx + (y - y1) * vy) / denom;
}

double _radialGradientT(
  double x,
  double y, {
  required double minX,
  required double minY,
  required double width,
  required double height,
  int? dir,
}) {
  final origin = radialGradientOrigin(
    dir: dir,
    minX: minX,
    minY: minY,
    width: width,
    height: height,
  );
  final reach = math.max(width.abs(), height.abs()) * 0.6;
  if (reach <= 1e-18) return 0;
  final dx = x - origin.x;
  final dy = y - origin.y;
  return math.sqrt(dx * dx + dy * dy) / reach;
}

({int r, int g, int b, int a}) _lerpGradientStops(
  List<({double position, int r, int g, int b, int a})> stops,
  double t,
) {
  if (stops.isEmpty) return (r: 0, g: 0, b: 0, a: 0);
  final sorted = List<({double position, int r, int g, int b, int a})>.of(stops)
    ..sort((a, b) => a.position.compareTo(b.position));
  final u = t.clamp(0.0, 1.0);
  if (u <= sorted.first.position) {
    final s = sorted.first;
    return (r: s.r, g: s.g, b: s.b, a: s.a);
  }
  if (u >= sorted.last.position) {
    final s = sorted.last;
    return (r: s.r, g: s.g, b: s.b, a: s.a);
  }
  for (var i = 1; i < sorted.length; i++) {
    final next = sorted[i];
    if (u > next.position) continue;
    final prev = sorted[i - 1];
    final span = next.position - prev.position;
    final f = span.abs() < 1e-12 ? 0.0 : (u - prev.position) / span;
    return (
      r: (prev.r + (next.r - prev.r) * f).round().clamp(0, 255),
      g: (prev.g + (next.g - prev.g) * f).round().clamp(0, 255),
      b: (prev.b + (next.b - prev.b) * f).round().clamp(0, 255),
      a: (prev.a + (next.a - prev.a) * f).round().clamp(0, 255),
    );
  }
  final s = sorted.last;
  return (r: s.r, g: s.g, b: s.b, a: s.a);
}
