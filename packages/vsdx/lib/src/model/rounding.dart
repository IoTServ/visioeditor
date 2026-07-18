import 'dart:math' as math;

import 'geometry.dart';

/// Fillet sharp corners of a polyline to approximate Visio `Rounding`
/// (libvisio-style corner radius on stroked / filled geometry).
///
/// Returns [points] unchanged when [radius] ≤ 0 or there are fewer than
/// three vertices. Arc fillets are sampled into line segments so callers can
/// stay on a pure polyline representation (Flutter [Path] / SVG `d`).
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

  final midX = (p1.x + p2.x) / 2;
  final midY = (p1.y + p2.y) / 2;
  final chord = math.sqrt(
    (p2.x - p1.x) * (p2.x - p1.x) + (p2.y - p1.y) * (p2.y - p1.y),
  );
  final h = math.sqrt(
    math.max(0.0, radius * radius - (chord * 0.5) * (chord * 0.5)),
  );
  final toCornerX = cur.x - midX;
  final toCornerY = cur.y - midY;
  final toCornerLen =
      math.sqrt(toCornerX * toCornerX + toCornerY * toCornerY);
  final double cx;
  final double cy;
  if (toCornerLen < 1e-12) {
    final sign = turn > 0 ? 1.0 : -1.0;
    cx = midX + (-inUy * sign) * h;
    cy = midY + (inUx * sign) * h;
  } else {
    cx = midX - (toCornerX / toCornerLen) * h;
    cy = midY - (toCornerY / toCornerLen) * h;
  }

  final a0 = math.atan2(p1.y - cy, p1.x - cx);
  final a1 = math.atan2(p2.y - cy, p2.x - cx);
  var sweep = a1 - a0;
  if (turn > 0 && sweep < 0) sweep += 2 * math.pi;
  if (turn < 0 && sweep > 0) sweep -= 2 * math.pi;

  final effectiveRadius = math.sqrt(
    (p1.x - cx) * (p1.x - cx) + (p1.y - cy) * (p1.y - cy),
  );
  final samples = <Offset2D>[p1];
  final segs = math.max(2, arcSegments);
  for (var s = 1; s < segs; s++) {
    final t = s / segs;
    final a = a0 + sweep * t;
    samples.add(Offset2D(
      cx + effectiveRadius * math.cos(a),
      cy + effectiveRadius * math.sin(a),
    ));
  }
  samples.add(p2);
  return samples;
}
