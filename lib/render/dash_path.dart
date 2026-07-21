/// Dash a Flutter [Path] by walking [PathMetric] segments.
///
/// Flutter's `Paint` doesn't support stroke dash patterns natively, so we
/// resample the path: every other run of [dashPattern] length becomes a
/// sub-path, the gaps are skipped.
///
/// The pattern is an alternating list of `[dash, gap, dash, gap, ...]`,
/// expressed in the **same units** as the source path (currently inches at
/// the painter level). An empty pattern returns the source unchanged.
///
/// Visio `LinePattern` → inch tables live in `package:vsdx` ([dashPatternFor])
/// and scale with line weight.
library;

import 'dart:ui';

import 'package:vsdx/vsdx.dart' show dashPatternFor;

export 'package:vsdx/vsdx.dart' show dashPatternFor, dashArrayAttr;

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

/// Convenience: Visio [linePattern] + [weightInches] → dash list (or null).
List<double>? dashPatternForLine(int linePattern, double weightInches) =>
    dashPatternFor(linePattern, weightInches: weightInches);
