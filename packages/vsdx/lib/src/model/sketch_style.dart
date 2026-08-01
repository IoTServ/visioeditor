/// Deterministic helpers for draw.io's hand-drawn Sketch style.
library;

import 'geometry.dart';

/// Returns the two small, stable stroke translations used for a sketch.
///
/// draw.io's rough.js `jiggle` is expressed in screen pixels. Renderers pass
/// their pixel density so the authored value has the same apparent size in
/// Canvas, SVG and PDF. A shape-id seed prevents every outline from sharing
/// exactly the same double-stroke displacement while remaining export-stable.
List<Offset2D> drawioSketchStrokeOffsets(
  int shapeId,
  double jiggle, {
  double pxPerInch = 96.0,
}) {
  final amplitude = jiggle.clamp(0.25, 10.0) / pxPerInch;
  var hash = (shapeId * 1103515245 + 12345) & 0x7fffffff;
  double unit() {
    hash = (hash * 1103515245 + 12345) & 0x7fffffff;
    return hash / 0x7fffffff * 2 - 1;
  }

  final dx = (0.55 + unit().abs() * 0.35) * amplitude;
  final dy = (0.45 + unit().abs() * 0.4) * amplitude;
  final skew = unit() * amplitude * 0.18;
  return <Offset2D>[
    Offset2D(-dx, dy + skew),
    Offset2D(dx + skew, -dy),
  ];
}
