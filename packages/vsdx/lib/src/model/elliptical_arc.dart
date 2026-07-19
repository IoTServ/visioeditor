/// Visio `EllipticalArcTo` / `RelEllipticalArcTo` sampling.
///
/// MS-VSDX: endpoint (X,Y), on-arc control (A,B), major-axis angle (C),
/// major/minor ratio (D). Map the ellipse to a circle via rotate(−C) then
/// scale Y by D, fit a circle through the three transformed points, sample
/// the arc that passes through the control, then inverse-transform.
library;

import 'dart:math' as math;

import 'geometry.dart';

/// Sample an elliptical arc from [start] through [control] to [end].
///
/// Returns intermediate points (excludes [start]; includes [end]). When the
/// geometry is degenerate, falls back to `[end]` (chord).
List<Offset2D> sampleEllipticalArc({
  required Offset2D start,
  required Offset2D end,
  required Offset2D control,
  required double angle,
  required double eccentricity,
  int steps = 16,
}) {
  final ecc = eccentricity <= 0 ? 1.0 : eccentricity;
  Offset2D toCircle(Offset2D p) {
    final cosA = math.cos(-angle);
    final sinA = math.sin(-angle);
    final rx = p.x * cosA - p.y * sinA;
    final ry = p.x * sinA + p.y * cosA;
    return Offset2D(rx, ry * ecc);
  }

  Offset2D fromCircle(Offset2D p) {
    final y = p.y / ecc;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    return Offset2D(p.x * cosA - y * sinA, p.x * sinA + y * cosA);
  }

  final p0 = toCircle(start);
  final p1 = toCircle(control);
  final p2 = toCircle(end);
  final circle = _circleThrough(p0, p1, p2);
  if (circle == null) return <Offset2D>[end];

  final (cx, cy, r) = circle;
  if (r < 1e-12) return <Offset2D>[end];

  double ang(Offset2D p) => math.atan2(p.y - cy, p.x - cx);
  var a0 = ang(p0);
  var a1 = ang(p1);
  var a2 = ang(p2);

  // Sweep from a0 → a2 that contains a1 (control on the arc).
  double norm(double a) {
    while (a <= -math.pi) {
      a += 2 * math.pi;
    }
    while (a > math.pi) {
      a -= 2 * math.pi;
    }
    return a;
  }

  var sweep = norm(a2 - a0);
  if (sweep.abs() < 1e-12) {
    // Nearly full circle or zero — pick the longer path through control.
    sweep = math.pi * 2 * (norm(a1 - a0) >= 0 ? 1 : -1);
  }
  final ctrlOfs = norm(a1 - a0);
  // Control must lie on the chosen sweep (same sign, |ctrl| ≤ |sweep|).
  final onSweep = sweep > 0
      ? (ctrlOfs >= -1e-9 && ctrlOfs <= sweep + 1e-9)
      : (ctrlOfs <= 1e-9 && ctrlOfs >= sweep - 1e-9);
  if (!onSweep) {
    // Flip to the other way around the circle.
    sweep = sweep > 0
        ? sweep - 2 * math.pi
        : sweep + 2 * math.pi;
  }

  final n = steps < 2 ? 2 : steps;
  final out = <Offset2D>[];
  for (var i = 1; i <= n; i++) {
    final t = i / n;
    final a = a0 + sweep * t;
    out.add(fromCircle(Offset2D(cx + r * math.cos(a), cy + r * math.sin(a))));
  }
  // Snap the last sample to the exact end point.
  if (out.isNotEmpty) out[out.length - 1] = end;
  return out;
}

/// Circle through three non-collinear points, or `null`.
(double, double, double)? _circleThrough(Offset2D a, Offset2D b, Offset2D c) {
  final d = 2 *
      (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y));
  if (d.abs() < 1e-18) return null;
  final a2 = a.x * a.x + a.y * a.y;
  final b2 = b.x * b.x + b.y * b.y;
  final c2 = c.x * c.x + c.y * c.y;
  final ux = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d;
  final uy = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d;
  final r = math.sqrt((a.x - ux) * (a.x - ux) + (a.y - uy) * (a.y - uy));
  return (ux, uy, r);
}
