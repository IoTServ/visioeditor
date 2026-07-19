/// Shared NURBS sampling (rational de Boor) for perimeter, SVG, and paint.
library;

import 'geometry.dart';

/// Sample a NURBS from [start] through [controlPoints] to [end].
///
/// Returns intermediate points (excludes [start]; includes [end]-ish last
/// sample). Falls back to the control polygon when there are too few points
/// for [degree].
List<Offset2D> sampleNurbs({
  required Offset2D start,
  required Offset2D end,
  required List<Offset2D> controlPoints,
  List<double> weights = const <double>[],
  List<double> knots = const <double>[],
  int degree = 3,
  int samples = 32,
}) {
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
    return <Offset2D>[for (var i = 1; i <= n; i++) cps[i]];
  }
  final fullKnots =
      knots.length == n + degree + 2 ? knots : clampedNurbsKnots(n, degree);
  final tMin = fullKnots[degree];
  final tMax = fullKnots[n + 1];
  final out = <Offset2D>[];
  for (var s = 1; s <= samples; s++) {
    final t = tMin + (tMax - tMin) * s / samples;
    out.add(deBoorNurbs(cps, wts, fullKnots, degree, t));
  }
  return out;
}

/// Clamped uniform knot vector with `n + degree + 2` entries.
List<double> clampedNurbsKnots(int n, int degree) {
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
Offset2D deBoorNurbs(
  List<Offset2D> cps,
  List<double> wts,
  List<double> knots,
  int degree,
  double t,
) {
  final n = cps.length - 1;
  var k = degree;
  while (k < n && t >= knots[k + 1]) {
    k++;
  }
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
