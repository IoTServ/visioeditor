/// Visio `SplineStart` / `SplineKnot` sampling via libvisio → NURBS.
library;

import 'dart:math' as math;

import 'geometry.dart';
import 'nurbs.dart';

/// Sample a Visio spline that begins at pen [start], with [head] =
/// `SplineStart` and following [knots] = `SplineKnot` rows.
///
/// Assembly matches libvisio `collectSplineStart` / `collectSplineKnot` /
/// `collectSplineEnd`: control polygon is pen + flushed SplineStart/Knot
/// points; knot vector is `[B, A, …knot cells…, C]` with unit weights.
List<Offset2D> sampleVisioSpline({
  required Offset2D start,
  required SplineStart head,
  required List<SplineKnot> knots,
  int samples = 32,
}) {
  // B = first knot, A = second knot, C = last knot (MS-VSDX SplineStart).
  final knotVec = <double>[head.b, head.a];
  final cps = <Offset2D>[];
  var curX = head.x;
  var curY = head.y;
  for (final k in knots) {
    cps.add(Offset2D(curX, curY));
    knotVec.add(k.knot);
    curX = k.x;
    curY = k.y;
  }
  knotVec.add(head.c);
  final end = Offset2D(curX, curY);
  if (cps.isEmpty) {
    // SplineStart with no knots — fall back to the second control point.
    return <Offset2D>[end];
  }
  return sampleNurbs(
    start: start,
    end: end,
    controlPoints: cps,
    weights: List<double>.filled(cps.length + 2, 1.0),
    knots: knotVec,
    degree: head.degree.clamp(1, 7),
    samples: samples,
  );
}

/// Consume `SplineStart` at [index] plus following `SplineKnot` rows.
///
/// Returns sampled points (excludes [pen]), the new pen position, and the
/// index of the first command *after* the spline sequence.
({List<Offset2D> samples, Offset2D end, int nextIndex}) consumeSplineSequence(
  List<VsdxPathCommand> commands,
  int index, {
  required Offset2D pen,
  required double width,
  required double height,
  int samples = 32,
}) {
  final headCmd = commands[index];
  if (headCmd is! SplineStart) {
    throw ArgumentError('commands[$index] is not SplineStart');
  }
  final headLocal = SplineStart(
    x: headCmd.relative ? headCmd.x * width : headCmd.x,
    y: headCmd.relative ? headCmd.y * height : headCmd.y,
    a: headCmd.a,
    b: headCmd.b,
    c: headCmd.c,
    degree: headCmd.degree,
  );
  final knots = <SplineKnot>[];
  var j = index + 1;
  while (j < commands.length && commands[j] is SplineKnot) {
    final k = commands[j] as SplineKnot;
    knots.add(
      SplineKnot(
        x: k.relative ? k.x * width : k.x,
        y: k.relative ? k.y * height : k.y,
        knot: k.knot,
      ),
    );
    j++;
  }
  final pts = sampleVisioSpline(
    start: pen,
    head: headLocal,
    knots: knots,
    samples: samples,
  );
  // Authored endpoint (last knot, or SplineStart when there are none) — not
  // the last dense sample, so callers can rest the pen exactly.
  final end = knots.isEmpty
      ? Offset2D(headLocal.x, headLocal.y)
      : Offset2D(knots.last.x, knots.last.y);
  return (samples: pts, end: end, nextIndex: j);
}

/// Whether a Visio ArcTo uses the major circular arc.
///
/// Matches libvisio `collectArcTo`: `abs(bow) > radius`, where
/// `r = (chord² + 4·bow²) / (8·|bow|)`.
bool visioArcByBowIsLarge(double chord, double bow) {
  final sagitta = bow.abs();
  if (!chord.isFinite || !sagitta.isFinite || sagitta < 1e-12) return false;
  final radius =
      (chord * chord + 4 * sagitta * sagitta) / (8 * sagitta);
  // Exact libvisio condition: fabs(bow) > radius. Algebraically this is
  // equivalent to 2*|bow| > chord, but retaining the source form documents
  // the renderer contract and avoids the previous factor-of-two regression.
  return sagitta > radius;
}

/// Sample a Visio ArcTo (chord + bow / sagitta) as a **circular** arc.
///
/// Returns intermediate points (excludes [start]; includes [end]).
List<Offset2D> sampleArcByBow({
  required Offset2D start,
  required Offset2D end,
  required double bow,
  int steps = 10,
}) {
  if (bow.abs() < 1e-12) return <Offset2D>[end];
  final dx = end.x - start.x;
  final dy = end.y - start.y;
  final chord = math.sqrt(dx * dx + dy * dy);
  if (chord < 1e-12) return <Offset2D>[end];
  final s = bow.abs();
  final r = (chord * chord + 4 * s * s) / (8 * s);
  final mx = (start.x + end.x) / 2;
  final my = (start.y + end.y) / 2;
  // Unit left-normal of the chord (Visio +bow lies on this side).
  final nx = -dy / chord;
  final ny = dx / chord;
  final sign = bow > 0 ? 1.0 : -1.0;
  // Apex at M + n·bow; centre is r from both ends, on the same side.
  final dist = r - s;
  final cx = mx - nx * sign * dist;
  final cy = my - ny * sign * dist;
  final apex = Offset2D(mx + nx * bow, my + ny * bow);

  final a0 = math.atan2(start.y - cy, start.x - cx);
  final a1 = math.atan2(end.y - cy, end.x - cx);
  final aA = math.atan2(apex.y - cy, apex.x - cx);

  // Pick the sweep a0→a1 that passes nearer the apex (handles major/minor).
  var dPos = a1 - a0;
  while (dPos <= 0) {
    dPos += 2 * math.pi;
  }
  var dNeg = a1 - a0;
  while (dNeg >= 0) {
    dNeg -= 2 * math.pi;
  }
  double angDist(double a, double b) {
    var d = (a - b).abs();
    if (d > math.pi) d = 2 * math.pi - d;
    return d;
  }

  final midPos = a0 + dPos / 2;
  final midNeg = a0 + dNeg / 2;
  final delta =
      angDist(midPos, aA) <= angDist(midNeg, aA) ? dPos : dNeg;

  final out = <Offset2D>[];
  for (var i = 1; i <= steps; i++) {
    final t = i / steps;
    final a = a0 + delta * t;
    out.add(Offset2D(cx + r * math.cos(a), cy + r * math.sin(a)));
  }
  // Snap the last sample to the exact endpoint.
  if (out.isNotEmpty) {
    out[out.length - 1] = end;
  }
  return out;
}
