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
  final end =
      pts.isNotEmpty ? pts.last : Offset2D(headLocal.x, headLocal.y);
  return (samples: pts, end: end, nextIndex: j);
}

/// Sample an ArcTo chord+bow into polyline points (excludes [start], includes
/// [end]). Used by perimeter glue and arrow-tangent extraction.
List<Offset2D> sampleArcByBow({
  required Offset2D start,
  required Offset2D end,
  required double bow,
  int steps = 10,
}) {
  if (bow.abs() < 1e-12) return <Offset2D>[end];
  final mx = (start.x + end.x) / 2;
  final my = (start.y + end.y) / 2;
  final dx = end.x - start.x;
  final dy = end.y - start.y;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length < 1e-12) return <Offset2D>[end];
  final nx = -dy / length;
  final ny = dx / length;
  final ctrl = Offset2D(mx + nx * bow, my + ny * bow);
  final out = <Offset2D>[];
  for (var i = 1; i <= steps; i++) {
    final t = i / steps;
    final u = 1 - t;
    out.add(
      Offset2D(
        u * u * start.x + 2 * u * t * ctrl.x + t * t * end.x,
        u * u * start.y + 2 * u * t * ctrl.y + t * t * end.y,
      ),
    );
  }
  return out;
}
