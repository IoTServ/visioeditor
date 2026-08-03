/// Shared NURBS sampling (rational de Boor) for perimeter, SVG, and paint.
///
/// Knot/weight assembly follows libvisio `collectNURBSTo`: full control
/// polygon is pen-start + interior CPs + endpoint; weights may be the full
/// `[D, …, B]` vector; knots `[C, …, A, knotLast]` are padded to
/// `cps.length + degree + 1` and normalized to `[0,1]`.
library;

import 'geometry.dart';

/// Sample a NURBS from [start] through [controlPoints] to [end].
///
/// Returns intermediate points (excludes [start]; last sample ≈ [end]).
/// Falls back to the control polygon when there are too few points for
/// [degree].
List<Offset2D> sampleNurbs({
  required Offset2D start,
  required Offset2D end,
  required List<Offset2D> controlPoints,
  List<double> weights = const <double>[],
  List<double> knots = const <double>[],
  int degree = 3,
  int samples = 32,
}) {
  final effectiveDegree = visioNurbsDegree(degree);
  // A zero degree reaches libvisio's endpoint LineTo after its curve
  // generator rejects the spline. Negative degrees are foreign/corrupt input
  // (the binary value is unsigned) and use the same safe fallback.
  if (effectiveDegree == 0) return <Offset2D>[end];
  final cps = <Offset2D>[start, ...controlPoints, end];
  final wts = _resolveWeights(cps.length, controlPoints.length, weights);
  final n = cps.length - 1;
  if (n < effectiveDegree) {
    return <Offset2D>[for (var i = 1; i <= n; i++) cps[i]];
  }
  final fullKnots = _resolveKnots(cps.length, effectiveDegree, knots);
  final tMin = fullKnots[effectiveDegree];
  final tMax = fullKnots[n + 1];
  final out = <Offset2D>[];
  for (var s = 1; s <= samples; s++) {
    final t = tMin + (tMax - tMin) * s / samples;
    out.add(deBoorNurbs(cps, wts, fullKnots, effectiveDegree, t));
  }
  // de Boor at tMax is numerically ≈ end; snap so pen / arrows / glue land
  // on the authored endpoint rather than a float residual.
  if (out.isNotEmpty) out[out.length - 1] = end;
  return out;
}

/// Normalize a Visio NURBS degree like libvisio `collectNURBSTo`.
///
/// Valid VSD/VSDX values are unsigned. libvisio caps them at
/// `MAX_ALLOWED_NURBS_DEGREE` (8); non-positive model values use the
/// endpoint-only fallback in [sampleNurbs].
int visioNurbsDegree(int degree) {
  if (degree <= 0) return 0;
  return degree > 8 ? 8 : degree;
}

List<double> _resolveWeights(
  int cpsLength,
  int interiorLength,
  List<double> weights,
) {
  if (weights.length == cpsLength) {
    return weights;
  }
  if (weights.length == interiorLength + 2 && interiorLength + 2 == cpsLength) {
    return weights;
  }
  if (weights.length == interiorLength) {
    return <double>[
      1.0,
      ...weights,
      1.0,
    ];
  }
  return List<double>.filled(cpsLength, 1.0);
}

/// Pad / normalize a Visio knot vector to `cpsLength + degree + 1` entries
/// in `[0, 1]`, matching libvisio.
List<double> _resolveKnots(int cpsLength, int degree, List<double> knots) {
  final need = cpsLength + degree + 1;
  if (knots.isEmpty) {
    return clampedNurbsKnots(cpsLength - 1, degree);
  }
  final out = List<double>.of(knots);
  // Ensure non-decreasing.
  for (var i = 1; i < out.length; i++) {
    if (out[i] < out[i - 1]) out[i] = out[i - 1];
  }
  while (out.length < need) {
    out.add(out.last);
  }
  if (out.length > need) {
    out.removeRange(need, out.length);
  }
  final first = out.first;
  final span = out.last - first;
  if (span.abs() < 1e-18) {
    return clampedNurbsKnots(cpsLength - 1, degree);
  }
  for (var i = 0; i < out.length; i++) {
    out[i] = (out[i] - first) / span;
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
