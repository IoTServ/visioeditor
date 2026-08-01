/// Deterministic helpers for draw.io's hand-drawn Sketch style.
library;

import 'dart:math' as math;

import 'geometry.dart';

/// draw.io rough.js fill styles exposed while Sketch is active.
enum VsdxSketchFillStyle {
  auto('auto'),
  solid('solid'),
  hachure('hachure'),
  crossHatch('cross-hatch'),
  dots('dots');

  const VsdxSketchFillStyle(this.drawioValue);
  final String drawioValue;

  static VsdxSketchFillStyle parse(String? value) {
    for (final style in values) {
      if (style.drawioValue == value?.trim().toLowerCase()) return style;
    }
    return VsdxSketchFillStyle.auto;
  }
}

typedef VsdxSketchFillSegment = ({Offset2D start, Offset2D end});

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

/// Generates clipped-at-render-time hachure lines over an axis-aligned box.
/// Coordinates remain in the shape's local inch space so Canvas and SVG/PDF
/// consume exactly the same pattern geometry.
List<VsdxSketchFillSegment> drawioSketchHachureSegments({
  required double minX,
  required double minY,
  required double width,
  required double height,
  required double gap,
  required double angleDegrees,
  bool crossHatch = false,
}) {
  List<VsdxSketchFillSegment> atAngle(double degrees) {
    final angle = degrees * 3.141592653589793 / 180;
    final dx = math.cos(angle), dy = math.sin(angle);
    final nx = -dy, ny = dx;
    final corners = <Offset2D>[
      Offset2D(minX, minY),
      Offset2D(minX + width, minY),
      Offset2D(minX + width, minY + height),
      Offset2D(minX, minY + height),
    ];
    var dMin = double.infinity, dMax = double.negativeInfinity;
    var nMin = double.infinity, nMax = double.negativeInfinity;
    for (final p in corners) {
      final d = p.x * dx + p.y * dy;
      final n = p.x * nx + p.y * ny;
      if (d < dMin) dMin = d;
      if (d > dMax) dMax = d;
      if (n < nMin) nMin = n;
      if (n > nMax) nMax = n;
    }
    final spacing = gap.clamp(0.005, 1.0).toDouble();
    final pad = spacing * 2;
    dMin -= pad;
    dMax += pad;
    final first = (nMin / spacing).floor() * spacing - spacing;
    final out = <VsdxSketchFillSegment>[];
    for (var n = first; n <= nMax + spacing; n += spacing) {
      out.add((
        start: Offset2D(dx * dMin + nx * n, dy * dMin + ny * n),
        end: Offset2D(dx * dMax + nx * n, dy * dMax + ny * n),
      ));
    }
    return out;
  }

  final result = atAngle(angleDegrees);
  if (crossHatch) result.addAll(atAngle(angleDegrees + 90));
  return result;
}

/// Grid of dots covering the same box; the caller clips against the actual
/// silhouette. The phase is stable for deterministic repeated exports.
List<Offset2D> drawioSketchFillDots({
  required double minX,
  required double minY,
  required double width,
  required double height,
  required double gap,
}) {
  final spacing = gap.clamp(0.005, 1.0).toDouble();
  final result = <Offset2D>[];
  final left = (minX / spacing).floor() * spacing;
  final bottom = (minY / spacing).floor() * spacing;
  for (var y = bottom; y <= minY + height + spacing; y += spacing) {
    for (var x = left; x <= minX + width + spacing; x += spacing) {
      result.add(Offset2D(x, y));
    }
  }
  return result;
}
