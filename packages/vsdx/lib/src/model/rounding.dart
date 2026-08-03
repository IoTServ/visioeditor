import 'dart:math' as math;

import 'geometry.dart';

/// Whether a Move/Line polyline should be treated as a closed ring for Rounding.
///
/// Explicit first≈last is always closed. Filled outlines (`!noFill`) that omit
/// the closing LineTo (common Visio rectangles) are also treated as closed so
/// all corners fillet; open 1-D / NoFill elbows stay open.
bool polylineLooksClosed(
  List<Offset2D> pts, {
  required bool noFill,
}) {
  if (pts.length < 3) return false;
  final a = pts.first, b = pts.last;
  if ((a.x - b.x).abs() < 1e-9 && (a.y - b.y).abs() < 1e-9) return true;
  return !noFill;
}

/// Fillet sharp corners of a polyline using Visio/libvisio `Rounding`.
///
/// libvisio trims each adjacent segment and inserts a quadratic Bézier whose
/// control point is the original sharp corner. The Bézier is sampled into line
/// segments here so Flutter and SVG callers share the same geometry.
/// Returns [points] unchanged when [radius] ≤ 0 or fewer than three vertices.
List<Offset2D> filletPolyline(
  List<Offset2D> points,
  double radius, {
  bool closed = false,
  int arcSegments = 6,
}) {
  if (radius <= 1e-12 || points.length < 3) return points;

  final n = points.length;
  final out = <Offset2D>[];
  if (!closed) out.add(points.first);

  for (var i = 0; i < n; i++) {
    if (!closed && (i == 0 || i == n - 1)) continue;
    final prev = points[(i - 1 + n) % n];
    final cur = points[i];
    final next = points[(i + 1) % n];
    final fillet = _filletCorner(
      prev,
      cur,
      next,
      radius,
      arcSegments: arcSegments,
    );
    if (fillet == null) {
      out.add(cur);
      continue;
    }
    out.addAll(fillet);
  }

  if (!closed) out.add(points.last);
  return out;
}

List<Offset2D>? _filletCorner(
  Offset2D prev,
  Offset2D cur,
  Offset2D next,
  double radius, {
  required int arcSegments,
}) {
  final inDx = cur.x - prev.x;
  final inDy = cur.y - prev.y;
  final outDx = next.x - cur.x;
  final outDy = next.y - cur.y;
  final inLen = math.sqrt(inDx * inDx + inDy * inDy);
  final outLen = math.sqrt(outDx * outDx + outDy * outDy);
  if (inLen < 1e-12 || outLen < 1e-12) return null;

  final inUx = inDx / inLen;
  final inUy = inDy / inLen;
  final outUx = outDx / outLen;
  final outUy = outDy / outLen;

  final cross = inUx * outUy - inUy * outUx;
  final dot = (inUx * outUx + inUy * outUy).clamp(-1.0, 1.0);
  final turn = math.atan2(cross, dot);
  if (turn.abs() < 1e-6 || (turn.abs() - math.pi).abs() < 1e-6) {
    return <Offset2D>[cur];
  }

  final half = turn.abs() / 2;
  var trim = radius * math.tan(half);
  final maxTrim = math.min(inLen, outLen) * 0.5;
  if (trim > maxTrim) trim = maxTrim;
  if (trim < 1e-12) return <Offset2D>[cur];

  final p1 = Offset2D(cur.x - inUx * trim, cur.y - inUy * trim);
  final p2 = Offset2D(cur.x + outUx * trim, cur.y + outUy * trim);

  final samples = <Offset2D>[p1];
  final segs = math.max(2, arcSegments);
  for (var s = 1; s < segs; s++) {
    final t = s / segs;
    final u = 1.0 - t;
    samples.add(Offset2D(
      u * u * p1.x + 2.0 * u * t * cur.x + t * t * p2.x,
      u * u * p1.y + 2.0 * u * t * cur.y + t * t * p2.y,
    ));
  }
  samples.add(p2);
  return samples;
}
