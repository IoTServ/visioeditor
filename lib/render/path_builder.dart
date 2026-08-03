/// Convert a [VsdxGeometry] (shape-local coords, inches) into a Flutter
/// [Path] expressed in the **same units** the painter uses (also inches,
/// because the painter is operating after `canvas.scale(pxPerInch, …)`).
///
/// The math here is the M3 minimum viable subset — straight segments,
/// `Rel*To` fractions, ArcTo (chord+bow) and full Ellipse. More exotic
/// curves (EllipticalArcTo, NURBS, Splines) follow in subsequent M3
/// iterations.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:vsdx/vsdx.dart';

typedef InfiniteLineResolver = List<Offset2D>? Function(
  Offset2D p,
  Offset2D q,
);

/// Combine every Geometry section with `NoFill=0` into one even-odd path.
///
/// Visio / libvisio fill all non-NoFill sections of a shape as a single
/// compound path (`svg:fill-rule=evenodd`). That punches holes for frames /
/// donuts (e.g. sample.vsd's page border). Returns `null` when fewer than two
/// fillable sections exist — callers then paint each Geometry separately.
Path? buildCompoundFillPath(
  List<VsdxGeometry> geometries, {
  required double widthInches,
  required double heightInches,
  double roundingInches = 0,
  InfiniteLineResolver? infiniteLineResolver,
}) {
  final fillable = <VsdxGeometry>[
    for (final g in geometries)
      if (!g.noShow && !g.noFill) g,
  ];
  if (fillable.length < 2) return null;
  final path = Path()..fillType = PathFillType.evenOdd;
  for (final g in fillable) {
    path.addPath(
      buildPath(
        g,
        widthInches: widthInches,
        heightInches: heightInches,
        roundingInches: roundingInches,
        infiniteLineResolver: infiniteLineResolver,
      ),
      Offset.zero,
    );
  }
  return path;
}

/// Build a single Flutter [Path] from one [VsdxGeometry], given the shape's
/// width and height (used by the `Rel*` commands).
///
/// When [roundingInches] > 0 and the geometry is a Move/Line polyline,
/// corners are filleted to match Visio `Rounding` (libvisio-style).
Path buildPath(
  VsdxGeometry geometry, {
  required double widthInches,
  required double heightInches,
  double roundingInches = 0,
  InfiniteLineResolver? infiniteLineResolver,
}) {
  if (roundingInches > 1e-12) {
    final poly = _polylineVertices(
      geometry,
      widthInches: widthInches,
      heightInches: heightInches,
    );
    if (poly != null && poly.points.length >= 3) {
      final filleted = filletPolyline(
        poly.points,
        roundingInches,
        closed: poly.closed,
      );
      final path = Path();
      if (filleted.isEmpty) return path;
      path.moveTo(filleted.first.x, filleted.first.y);
      for (var i = 1; i < filleted.length; i++) {
        path.lineTo(filleted[i].x, filleted[i].y);
      }
      if (poly.closed) path.close();
      return path;
    }
  }

  final path = Path();
  double cursorX = 0;
  double cursorY = 0;
  var hasStart = false;

  void start(double x, double y) {
    path.moveTo(x, y);
    cursorX = x;
    cursorY = y;
    hasStart = true;
  }

  final cmds = geometry.commands;
  for (var i = 0; i < cmds.length; i++) {
    final cmd = cmds[i];
    switch (cmd) {
      case MoveTo(:final x, :final y):
        start(x, y);
      case RelMoveTo(:final fx, :final fy):
        start(fx * widthInches, fy * heightInches);
      case LineTo(:final x, :final y):
        if (!hasStart) start(0, 0);
        path.lineTo(x, y);
        cursorX = x;
        cursorY = y;
      case RelLineTo(:final fx, :final fy):
        final x = fx * widthInches;
        final y = fy * heightInches;
        if (!hasStart) start(0, 0);
        path.lineTo(x, y);
        cursorX = x;
        cursorY = y;
      case CubBezTo(
          :final x,
          :final y,
          :final x1,
          :final y1,
          :final x2,
          :final y2,
        ):
        if (!hasStart) start(0, 0);
        path.cubicTo(x1, y1, x2, y2, x, y);
        cursorX = x;
        cursorY = y;
      case RelCubBezTo(
          :final fx,
          :final fy,
          :final fx1,
          :final fy1,
          :final fx2,
          :final fy2,
        ):
        if (!hasStart) start(0, 0);
        final ex = fx * widthInches;
        final ey = fy * heightInches;
        path.cubicTo(
          fx1 * widthInches,
          fy1 * heightInches,
          fx2 * widthInches,
          fy2 * heightInches,
          ex,
          ey,
        );
        cursorX = ex;
        cursorY = ey;
      case QuadBezTo(:final x, :final y, :final x1, :final y1):
        if (!hasStart) start(0, 0);
        path.quadraticBezierTo(x1, y1, x, y);
        cursorX = x;
        cursorY = y;
      case RelQuadBezTo(:final fx, :final fy, :final fx1, :final fy1):
        if (!hasStart) start(0, 0);
        final ex = fx * widthInches;
        final ey = fy * heightInches;
        path.quadraticBezierTo(fx1 * widthInches, fy1 * heightInches, ex, ey);
        cursorX = ex;
        cursorY = ey;
      case ArcTo(:final x, :final y, :final bow):
        if (!hasStart) start(0, 0);
        _arcByBow(path, cursorX, cursorY, x, y, bow);
        cursorX = x;
        cursorY = y;
      case RelArcTo(:final fx, :final fy, :final fbow):
        if (!hasStart) start(0, 0);
        final x = fx * widthInches;
        final y = fy * heightInches;
        final bow = fbow * (widthInches + heightInches) / 2;
        _arcByBow(path, cursorX, cursorY, x, y, bow);
        cursorX = x;
        cursorY = y;
      case EllipticalArcTo(
          :final x,
          :final y,
          :final controlX,
          :final controlY,
          :final angle,
          :final eccentricity,
        ):
        if (!hasStart) start(0, 0);
        final samples = sampleEllipticalArc(
          start: Offset2D(cursorX, cursorY),
          end: Offset2D(x, y),
          control: Offset2D(controlX, controlY),
          angle: angle,
          eccentricity: eccentricity,
        );
        for (final p in samples) {
          path.lineTo(p.x, p.y);
        }
        cursorX = x;
        cursorY = y;
      case RelEllipticalArcTo(
          :final fx,
          :final fy,
          :final fcx,
          :final fcy,
          :final angle,
          :final eccentricity,
        ):
        if (!hasStart) start(0, 0);
        final ex = fx * widthInches;
        final ey = fy * heightInches;
        final samples = sampleEllipticalArc(
          start: Offset2D(cursorX, cursorY),
          end: Offset2D(ex, ey),
          control: Offset2D(fcx * widthInches, fcy * heightInches),
          angle: angle,
          eccentricity: eccentricity,
        );
        for (final p in samples) {
          path.lineTo(p.x, p.y);
        }
        cursorX = ex;
        cursorY = ey;
      case EllipseCmd(
          :final cx,
          :final cy,
          :final aX,
          :final aY,
          :final bX,
          :final bY,
        ):
        _ellipseFromPoints(path, cx, cy, aX, aY, bX, bY);
      // Ellipse closes its own sub-path; cursor stays where it was.
      case PolylineTo(
          :final x,
          :final y,
          :final vertices,
          :final relative,
          :final vertsRelative,
          :final vertsYRelative,
        ):
        if (!hasStart) start(0, 0);
        final vsx = vertsRelative ? widthInches : 1.0;
        final vsy = vertsYRelative ? heightInches : 1.0;
        final esx = relative ? widthInches : 1.0;
        final esy = relative ? heightInches : 1.0;
        for (final v in vertices) {
          path.lineTo(v.x * vsx, v.y * vsy);
        }
        path.lineTo(x * esx, y * esy);
        cursorX = x * esx;
        cursorY = y * esy;
      case InfiniteLineCmd(:final x, :final y, :final a, :final b, :final relative):
        final sx = relative ? widthInches : 1.0;
        final sy = relative ? heightInches : 1.0;
        final px = x * sx, py = y * sy, qx = a * sx, qy = b * sy;
        final clipped = infiniteLineResolver?.call(
          Offset2D(px, py),
          Offset2D(qx, qy),
        );
        if (clipped != null && clipped.length >= 2) {
          start(clipped.first.x, clipped.first.y);
          path.lineTo(clipped.last.x, clipped.last.y);
          cursorX = clipped.last.x;
          cursorY = clipped.last.y;
          break;
        }
        final dx = qx - px;
        final dy = qy - py;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len == 0) break;
        final ux = dx / len;
        final uy = dy / len;
        final reach = 100 * math.sqrt(
              widthInches * widthInches + heightInches * heightInches,
            );
        start(px - ux * reach, py - uy * reach);
        path.lineTo(px + ux * reach, py + uy * reach);
        cursorX = px + ux * reach;
        cursorY = py + uy * reach;
      case SplineStart():
        if (!hasStart) start(0, 0);
        final spline = consumeSplineSequence(
          cmds,
          i,
          pen: Offset2D(cursorX, cursorY),
          width: widthInches,
          height: heightInches,
        );
        for (final p in spline.samples) {
          path.lineTo(p.x, p.y);
        }
        cursorX = spline.end.x;
        cursorY = spline.end.y;
        i = spline.nextIndex - 1;
      case SplineKnot():
        // Consumed with the preceding SplineStart.
        break;
      case NurbsTo(
          :final x,
          :final y,
          :final controlPoints,
          :final weights,
          :final knots,
          :final degree,
          :final relative,
          :final cpRelative,
          :final cpYRelative,
        ):
        if (!hasStart) start(0, 0);
        final csx = cpRelative ? widthInches : 1.0;
        final csy = cpYRelative ? heightInches : 1.0;
        final esx = relative ? widthInches : 1.0;
        final esy = relative ? heightInches : 1.0;
        final samples = sampleNurbs(
          start: Offset2D(cursorX, cursorY),
          end: Offset2D(x * esx, y * esy),
          controlPoints: <Offset2D>[
            for (final p in controlPoints) Offset2D(p.x * csx, p.y * csy),
          ],
          weights: weights,
          knots: knots,
          degree: degree,
        );
        for (final p in samples) {
          path.lineTo(p.x, p.y);
        }
        cursorX = x * esx;
        cursorY = y * esy;
    }
  }
  return path;
}

/// Extract absolute polyline vertices when [geometry] is Move/Line(/Rel/Poly)
/// only. Returns `null` when curves or ellipses are present (Rounding then
/// falls back to the sharp path + strokeJoin).
({List<Offset2D> points, bool closed})? _polylineVertices(
  VsdxGeometry geometry, {
  required double widthInches,
  required double heightInches,
}) {
  final pts = <Offset2D>[];
  double cx = 0, cy = 0;
  var started = false;
  for (final cmd in geometry.commands) {
    switch (cmd) {
      case MoveTo(:final x, :final y):
        if (started && pts.isNotEmpty) return null; // multi-contour
        pts
          ..clear()
          ..add(Offset2D(x, y));
        cx = x;
        cy = y;
        started = true;
      case RelMoveTo(:final fx, :final fy):
        if (started && pts.isNotEmpty) return null;
        final x = fx * widthInches, y = fy * heightInches;
        pts
          ..clear()
          ..add(Offset2D(x, y));
        cx = x;
        cy = y;
        started = true;
      case LineTo(:final x, :final y):
        if (!started) {
          pts.add(const Offset2D(0, 0));
          started = true;
        }
        pts.add(Offset2D(x, y));
        cx = x;
        cy = y;
      case RelLineTo(:final fx, :final fy):
        final x = fx * widthInches, y = fy * heightInches;
        if (!started) {
          pts.add(const Offset2D(0, 0));
          started = true;
        }
        pts.add(Offset2D(x, y));
        cx = x;
        cy = y;
      case PolylineTo(
          :final x,
          :final y,
          :final vertices,
          :final relative,
          :final vertsRelative,
          :final vertsYRelative,
        ):
        final vsx = vertsRelative ? widthInches : 1.0;
        final vsy = vertsYRelative ? heightInches : 1.0;
        final esx = relative ? widthInches : 1.0;
        final esy = relative ? heightInches : 1.0;
        if (!started) {
          pts.add(const Offset2D(0, 0));
          started = true;
        }
        for (final v in vertices) {
          pts.add(Offset2D(v.x * vsx, v.y * vsy));
        }
        final ex = x * esx, ey = y * esy;
        pts.add(Offset2D(ex, ey));
        cx = ex;
        cy = ey;
      default:
        return null;
    }
  }
  if (pts.length < 2) return null;
  var closed = false;
  if (pts.length >= 3) {
    final a = pts.first, b = pts.last;
    if ((a.x - b.x).abs() < 1e-9 && (a.y - b.y).abs() < 1e-9) {
      closed = true;
      pts.removeLast();
    } else if (polylineLooksClosed(pts, noFill: geometry.noFill)) {
      // Filled outline without an explicit closing vertex.
      closed = true;
    }
  }
  // Ignore unused cursor warning.
  assert(cx.isFinite && cy.isFinite);
  return (points: pts, closed: closed);
}

/// Visio ArcTo: arc from `(x0,y0)` to `(x1,y1)` whose **apex** lies `bow`
/// inches perpendicular to the chord midpoint. `bow == 0` ⇒ straight line.
///
/// We approximate the circular arc via Flutter's `arcToPoint`, mapping the
/// bow to a `Radius` and the correct sweep / large-arc booleans. Derivation:
///   r = (chord² + 4·bow²) / (8·|bow|)
void _arcByBow(
  Path path,
  double x0,
  double y0,
  double x1,
  double y1,
  double bow,
) {
  if (bow == 0) {
    path.lineTo(x1, y1);
    return;
  }
  final dx = x1 - x0;
  final dy = y1 - y0;
  final chord = math.sqrt(dx * dx + dy * dy);
  if (chord == 0) {
    // Degenerate: full circle would require a closed-arc approach; just emit
    // a tiny line so the path stays well-formed.
    path.lineTo(x1, y1);
    return;
  }
  final r = (chord * chord + 4 * bow * bow) / (8 * bow.abs());
  // `bow > 0` is "left of the chord direction" in Visio's convention.
  // Flutter's `arcToPoint` clockwise=true sweeps clockwise. We map:
  //   bow > 0 → CCW sweep (clockwise=false)
  //   bow < 0 → CW  sweep (clockwise=true)
  path.arcToPoint(
    Offset(x1, y1),
    radius: Radius.circular(r),
    largeArc: visioArcByBowIsLarge(chord, bow),
    clockwise: bow < 0,
  );
}

/// Visio Ellipse row: centre `(cx,cy)`, axis end-point A and conjugate B.
/// Samples a rotated ellipse when A/B are not axis-aligned.
void _ellipseFromPoints(
  Path path,
  double cx,
  double cy,
  double aX,
  double aY,
  double bX,
  double bY,
) {
  final ellipse = EllipseCmd(
    cx: cx,
    cy: cy,
    aX: aX,
    aY: aY,
    bX: bX,
    bY: bY,
  );
  final degenerate = visioDegenerateEllipsePath(ellipse);
  if (degenerate != null) {
    if (degenerate.isEmpty) return;
    path.moveTo(degenerate.first.x, degenerate.first.y);
    for (final point in degenerate.skip(1)) {
      path.lineTo(point.x, point.y);
    }
    path.close();
    return;
  }
  final ax = aX - cx, ay = aY - cy;
  final bx = bX - cx, by = bY - cy;
  final rx = math.sqrt(ax * ax + ay * ay);
  final ry = math.sqrt(bx * bx + by * by);
  // Axis-aligned fast path.
  if (ay.abs() < 1e-9 && bx.abs() < 1e-9) {
    path.addOval(Rect.fromCenter(
      center: Offset(cx, cy),
      width: 2 * rx,
      height: 2 * ry,
    ));
    return;
  }
  const steps = 64;
  for (var i = 0; i <= steps; i++) {
    final t = 2 * math.pi * i / steps;
    final cosT = math.cos(t), sinT = math.sin(t);
    final x = cx + ax * cosT + bx * sinT;
    final y = cy + ay * cosT + by * sinT;
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
}
