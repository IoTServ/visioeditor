/// Dash a Flutter [Path] by walking [PathMetric] segments.
///
/// Flutter's `Paint` doesn't support stroke dash patterns natively, so we
/// resample the path: every other run of [dashPattern] length becomes a
/// sub-path, the gaps are skipped.
///
/// The pattern is an alternating list of `[dash, gap, dash, gap, ...]`,
/// expressed in the **same units** as the source path (currently inches at
/// the painter level). An empty pattern returns the source unchanged.
library;

import 'dart:ui';

/// Resample [source] using [dashPattern].
Path dashedPath(Path source, List<double> dashPattern) {
  if (dashPattern.isEmpty) return source;
  if (dashPattern.length.isOdd) {
    // Pattern must have an even number of entries (dash + gap pairs).
    // Repeat once to make it even.
    dashPattern = [...dashPattern, ...dashPattern];
  }
  final out = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    var draw = true;
    var patternIdx = 0;
    while (distance < metric.length) {
      final span = dashPattern[patternIdx % dashPattern.length];
      final next = (distance + span).clamp(0.0, metric.length);
      if (draw && next > distance) {
        out.addPath(metric.extractPath(distance, next), Offset.zero);
      }
      distance = next;
      draw = !draw;
      patternIdx++;
    }
  }
  return out;
}

/// Look-up table mapping Visio `LinePattern` integers to a dash pattern in
/// **inches**. Pattern 1 is solid (no dashing). Patterns 2–23 are Visio's
/// built-ins; we approximate the most common ones, falling back to a long
/// dash for unrecognised values.
List<double>? dashPatternFor(int linePattern) {
  switch (linePattern) {
    case 0:
    case 1:
      return null; // solid (or no line — caller checks `hasLine` separately)
    case 2: // dashed
      return const [0.10, 0.05];
    case 3: // dotted
      return const [0.02, 0.04];
    case 4: // dash-dot
      return const [0.12, 0.05, 0.02, 0.05];
    case 5: // dash-dot-dot
      return const [0.12, 0.05, 0.02, 0.05, 0.02, 0.05];
    case 6: // short dash
      return const [0.06, 0.04];
    case 7: // dash long-gap
      return const [0.10, 0.10];
    case 8: // sparse dash
      return const [0.08, 0.12];
    case 9: // long-dash
      return const [0.20, 0.05];
    case 10: // long-dash-dot
      return const [0.20, 0.05, 0.02, 0.05];
    case 11: // long-dash-dot-dot
      return const [0.20, 0.05, 0.02, 0.05, 0.02, 0.05];
    case 12: // medium dash
      return const [0.14, 0.06];
    case 13: // medium dash-dot
      return const [0.14, 0.05, 0.02, 0.05];
    case 14: // medium dash-dot-dot
      return const [0.14, 0.05, 0.02, 0.05, 0.02, 0.05];
    case 15: // fine dots
      return const [0.015, 0.03];
    case 16: // dash-gap-dash
      return const [0.10, 0.04, 0.04, 0.04];
    case 17:
    case 18:
      return const [0.16, 0.06];
    case 19:
    case 20:
      return const [0.10, 0.05, 0.03, 0.05];
    case 21:
    case 22:
    case 23:
      return const [0.08, 0.04, 0.02, 0.04];
    default:
      return const [0.08, 0.04];
  }
}
