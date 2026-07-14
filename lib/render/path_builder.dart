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

/// Build a single Flutter [Path] from one [VsdxGeometry], given the shape's
/// width and height (used by the `Rel*` commands).
Path buildPath(
  VsdxGeometry geometry, {
  required double widthInches,
  required double heightInches,
}) {
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

  for (final cmd in geometry.commands) {
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
      case EllipticalArcTo(
          :final x,
          :final y,
          :final controlX,
          :final controlY,
        ):
        // Approximate by a quadratic Bezier that *passes through* the
        // control point at parameter t = 0.5. Solving B(0.5) gives:
        //   P_ctrl = 2·M − 0.5·P0 − 0.5·P2
        // where M is the on-curve midpoint Visio gives us as (A,B).
        if (!hasStart) start(0, 0);
        final bezX = 2 * controlX - 0.5 * cursorX - 0.5 * x;
        final bezY = 2 * controlY - 0.5 * cursorY - 0.5 * y;
        path.quadraticBezierTo(bezX, bezY, x, y);
        cursorX = x;
        cursorY = y;
      case RelEllipticalArcTo(
          :final fx,
          :final fy,
          :final fcx,
          :final fcy,
        ):
        if (!hasStart) start(0, 0);
        final ex = fx * widthInches;
        final ey = fy * heightInches;
        final cX = fcx * widthInches;
        final cY = fcy * heightInches;
        final bezX = 2 * cX - 0.5 * cursorX - 0.5 * ex;
        final bezY = 2 * cY - 0.5 * cursorY - 0.5 * ey;
        path.quadraticBezierTo(bezX, bezY, ex, ey);
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
      case PolylineTo(:final x, :final y, :final vertices):
        if (!hasStart) start(0, 0);
        for (final v in vertices) {
          path.lineTo(v.x, v.y);
        }
        path.lineTo(x, y);
        cursorX = x;
        cursorY = y;
      case InfiniteLineCmd(:final x, :final y, :final a, :final b):
        // Project the line through (x,y)→(a,b) onto a long chord inside
        // the shape's local box; render-time clipping handles the rest.
        final dx = a - x;
        final dy = b - y;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len == 0) break;
        final ux = dx / len;
        final uy = dy / len;
        // 100× the shape diagonal — well beyond any plausible viewport.
        final reach = 100 * math.sqrt(
              widthInches * widthInches + heightInches * heightInches,
            );
        start(x - ux * reach, y - uy * reach);
        path.lineTo(x + ux * reach, y + uy * reach);
        cursorX = x + ux * reach;
        cursorY = y + uy * reach;
      case SplineStart(:final x, :final y):
        // Chord-polyline fallback: treat the anchor as a MoveTo (or LineTo
        // if a sub-path is already open). True cubic-spline evaluation
        // arrives with the NURBS pass.
        if (!hasStart) {
          start(x, y);
        } else {
          path.lineTo(x, y);
          cursorX = x;
          cursorY = y;
        }
      case SplineKnot(:final x, :final y):
        if (!hasStart) start(x, y);
        path.lineTo(x, y);
        cursorX = x;
        cursorY = y;
      case NurbsTo(
          :final x,
          :final y,
          :final controlPoints,
          :final weights,
          :final knots,
          :final degree,
        ):
        if (!hasStart) start(0, 0);
        _emitNurbs(
          path,
          start: Offset2D(cursorX, cursorY),
          end: Offset2D(x, y),
          controlPoints: controlPoints,
          weights: weights,
          knots: knots,
          degree: degree,
        );
        cursorX = x;
        cursorY = y;
    }
  }
  return path;
}

/// Sample a NURBS curve into ~32 line segments using the de Boor algorithm.
/// When the knot vector is empty we synthesise a clamped uniform one so
/// the curve still passes through its endpoints.
void _emitNurbs(
  Path path, {
  required Offset2D start,
  required Offset2D end,
  required List<Offset2D> controlPoints,
  required List<double> weights,
  required List<double> knots,
  required int degree,
}) {
  // Construct the full control polygon: start + interior + end.
  final cps = <Offset2D>[start, ...controlPoints, end];
  final wts = <double>[
    1.0,
    ...List<double>.generate(
      controlPoints.length,
      (i) => i < weights.length ? weights[i] : 1.0,
    ),
    1.0,
  ];
  final n = cps.length - 1;
  if (n < degree) {
    // Not enough control points — fall back to chord polyline.
    for (var i = 1; i <= n; i++) {
      path.lineTo(cps[i].x, cps[i].y);
    }
    return;
  }
  // Build a clamped uniform knot vector if not supplied.
  final fullKnots = knots.length == n + degree + 2
      ? knots
      : _clampedKnots(n, degree);

  const samples = 32;
  final tMin = fullKnots[degree];
  final tMax = fullKnots[n + 1];
  for (var s = 1; s <= samples; s++) {
    final t = tMin + (tMax - tMin) * s / samples;
    final pt = _deBoor(cps, wts, fullKnots, degree, t);
    path.lineTo(pt.x, pt.y);
  }
}

/// Build a clamped uniform knot vector with `n + degree + 2` entries:
/// `[0, …, 0, t1, t2, …, tn-degree, 1, …, 1]`.
List<double> _clampedKnots(int n, int degree) {
  final size = n + degree + 2;
  final out = List<double>.filled(size, 0);
  final interior = n - degree;
  for (var i = 0; i <= degree; i++) {
    out[i] = 0;
    out[size - 1 - i] = 1;
  }
  for (var i = 1; i <= interior; i++) {
    out[degree + i] = i / (interior + 1);
  }
  return out;
}

/// Evaluate the NURBS at parameter [t] via rational de Boor recursion.
Offset2D _deBoor(
  List<Offset2D> cps,
  List<double> wts,
  List<double> knots,
  int degree,
  double t,
) {
  final n = cps.length - 1;
  // Find knot span k such that knots[k] <= t < knots[k+1].
  var k = degree;
  while (k < n && t >= knots[k + 1]) {
    k++;
  }
  // Rational de Boor: build (w*x, w*y, w) and iterate.
  final wx = <double>[];
  final wy = <double>[];
  final w = <double>[];
  for (var j = 0; j <= degree; j++) {
    final idx = k - degree + j;
    final wj = wts[idx];
    wx.add(cps[idx].x * wj);
    wy.add(cps[idx].y * wj);
    w.add(wj);
  }
  for (var r = 1; r <= degree; r++) {
    for (var j = degree; j >= r; j--) {
      final idx = k - degree + j;
      final denom = knots[idx + degree - r + 1] - knots[idx];
      final alpha = denom == 0 ? 0.0 : (t - knots[idx]) / denom;
      wx[j] = (1 - alpha) * wx[j - 1] + alpha * wx[j];
      wy[j] = (1 - alpha) * wy[j - 1] + alpha * wy[j];
      w[j] = (1 - alpha) * w[j - 1] + alpha * w[j];
    }
  }
  final ww = w[degree];
  if (ww == 0) return Offset2D(wx[degree], wy[degree]);
  return Offset2D(wx[degree] / ww, wy[degree] / ww);
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
    largeArc: 4 * bow.abs() > chord, // apex on far side of chord midpoint
    clockwise: bow < 0,
  );
}

/// Visio Ellipse row: centre `(cx,cy)`, axis end-point A and conjugate
/// end-point B. For the M3 minimum we assume **axis-aligned** ellipses
/// (the by-far common case): semi-axes derived from |A - centre| and
/// |B - centre|. Rotated ellipses get an approximation; full rotation
/// support arrives with EllipticalArcTo in the next M3 pass.
void _ellipseFromPoints(
  Path path,
  double cx,
  double cy,
  double aX,
  double aY,
  double bX,
  double bY,
) {
  final rx = math.sqrt(math.pow(aX - cx, 2) + math.pow(aY - cy, 2));
  final ry = math.sqrt(math.pow(bX - cx, 2) + math.pow(bY - cy, 2));
  if (rx == 0 || ry == 0) return;
  path.addOval(Rect.fromCenter(
    center: Offset(cx, cy),
    width: 2 * rx,
    height: 2 * ry,
  ));
}
