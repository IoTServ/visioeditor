/// Rewrite shape line appearance into cells / rows libvisio still collects.
///
/// LibreOffice Draw never reads Visio XML itself — `VisioImportFilter.cxx`
/// only calls `VisioDocument::isSupported` + `parse`. The VSDX token map has
/// no `CompoundType`, and unknown `LinePattern` ids (custom draw.io arrays,
/// 0xFE, …) fall through `_lineProperties` to a solid stroke. A save therefore
/// has to emit parallel Geometry rails and a built-in pattern 2–23.
library;

import '../export/compound_stroke.dart';
import '../utils/color.dart';
import 'dash_pattern.dart';
import 'fill.dart';
import 'geometry.dart';
import 'line.dart';
import 'perimeter.dart';
import 'rounding.dart';
import 'shape.dart';

/// Cells and Geometry the writer should emit so Draw paints this shape.
class LibvisioShapeWrite {
  const LibvisioShapeWrite({
    required this.geometries,
    required this.line,
    required this.fill,
    required this.geometryRewritten,
  });

  final List<VsdxGeometry> geometries;
  final VsdxLine line;
  final VsdxFill fill;
  final bool geometryRewritten;
}

/// Map [shape] onto the Fill / Line / Geometry libvisio will actually draw.
LibvisioShapeWrite libvisioShapeWrite(VsdxShape shape) {
  var geometries = shape.geometries;
  var line = shape.line;
  var geometryRewritten = false;

  final baked = bakeCompoundTypeForLibvisio(shape);
  if (baked != null) {
    geometries = baked.geometries;
    line = baked.line;
    geometryRewritten = true;
  }

  final pattern = linePatternForLibvisioWrite(line);
  if (pattern != line.pattern) {
    line = line.copyWith(pattern: pattern);
  }

  final color = lineColorForLibvisioWrite(line);
  if (color != null && line.color == null && line.themeColorIndex == null) {
    line = line.copyWith(color: color);
  }

  return LibvisioShapeWrite(
    geometries: geometries,
    line: line,
    fill: shape.fill,
    geometryRewritten: geometryRewritten,
  );
}

List<Offset2D>? _strokedVertices(VsdxGeometry geometry, VsdxShape shape) {
  return geometry.polylineVertices(
        widthInches: shape.width,
        heightInches: shape.height,
      ) ??
      ShapePerimeter.sampledGeometryVertices(
        geometry,
        width: shape.width,
        height: shape.height,
      );
}

/// `true` when a 2-D shape's CompoundType would otherwise vanish in Draw.
bool shapeNeedsLibvisioCompoundBake(VsdxShape shape) {
  if (shape.is1D) return false;
  if (shape.line.compoundType <= 0 || !shape.line.hasLine) return false;
  final weight =
      shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
  if (compoundRails(shape.line.compoundType, weight).isEmpty) return false;
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points != null && points.length >= 2) return true;
  }
  return false;
}

/// Offset each stroked polyline into rails libvisio can stroke.
///
/// LineWeight is shape-level, so every rail shares the same width (exact for
/// CompoundType 1; thick-thin / triple keep the offsets and use the thinnest
/// rail width so they do not blob into one fat stroke).
({List<VsdxGeometry> geometries, VsdxLine line})? bakeCompoundTypeForLibvisio(
  VsdxShape shape,
) {
  if (!shapeNeedsLibvisioCompoundBake(shape)) return null;
  final weight =
      shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
  final rails = compoundRails(shape.line.compoundType, weight);
  if (rails.isEmpty) return null;

  final out = <VsdxGeometry>[];
  var addedRails = false;
  for (final geometry in shape.geometries) {
    if (geometry.noShow) {
      out.add(geometry);
      continue;
    }
    if (geometry.noLine) {
      out.add(geometry);
      continue;
    }
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 2) {
      out.add(geometry);
      continue;
    }
    final closed = polylineLooksClosed(points, noFill: geometry.noFill);
    if (!geometry.noFill) {
      out.add(geometry.copyWith(noLine: true));
    }
    for (final rail in rails) {
      final offset = offsetPolyline(points, rail.offset, closed: closed);
      if (offset.length < 2) continue;
      out.add(
        VsdxGeometry(
          noFill: true,
          noLine: false,
          commands: polylineCommands(offset, closed: closed),
        ),
      );
      addedRails = true;
    }
  }
  if (!addedRails) return null;

  var railWeight = rails.first.width;
  for (final rail in rails) {
    if (rail.width < railWeight) railWeight = rail.width;
  }
  return (
    geometries: out,
    line: shape.line.copyWith(
      compoundType: 0,
      weightInches: railWeight,
    ),
  );
}

/// Built-in `LinePattern` 0–23 that libvisio's `_lineProperties` switch
/// actually dashes. Custom draw.io arrays and unknown ids become solid in
/// Draw unless they snap to this table.
int linePatternForLibvisioWrite(VsdxLine line) {
  if (line.pattern == 0) return 0;
  final custom = line.customDashPattern;
  if (custom != null && custom.isNotEmpty) {
    return nearestLibvisioLinePattern(custom);
  }
  if (line.pattern >= 1 && line.pattern <= 23) return line.pattern;
  return 1;
}

/// Closest of libvisio's dash ids 2–23 for a draw.io / custom array.
int nearestLibvisioLinePattern(List<double> custom) {
  var best = 2;
  var bestScore = double.infinity;
  for (var id = 2; id <= 23; id++) {
    final built = dashPatternFor(id, weightInches: 1);
    if (built == null) continue;
    final score = _dashDistance(custom, built);
    if (score < bestScore) {
      bestScore = score;
      best = id;
    }
  }
  return best;
}

/// First authored stop colour, used when Draw cannot collect LineGradient.
VsdxColor? lineColorForLibvisioWrite(VsdxLine line) {
  if (line.color != null) return line.color;
  if (line.themeColorIndex != null) return null;
  final gradient = line.gradient;
  if (gradient == null) return null;
  for (final stop in gradient.stops) {
    if (stop.color != null) return stop.color;
  }
  return null;
}

List<VsdxPathCommand> polylineCommands(
  List<Offset2D> points, {
  required bool closed,
}) {
  if (points.isEmpty) return const <VsdxPathCommand>[];
  var ring = List<Offset2D>.of(points);
  if (closed && ring.length >= 2) {
    final a = ring.first;
    final b = ring.last;
    if ((a.x - b.x).abs() < 1e-9 && (a.y - b.y).abs() < 1e-9) {
      ring = ring.sublist(0, ring.length - 1);
    }
  }
  if (ring.isEmpty) return const <VsdxPathCommand>[];
  final commands = <VsdxPathCommand>[
    MoveTo(ring.first.x, ring.first.y),
    for (var i = 1; i < ring.length; i++) LineTo(ring[i].x, ring[i].y),
  ];
  if (closed) {
    commands.add(LineTo(ring.first.x, ring.first.y));
  }
  return commands;
}

double _dashDistance(List<double> a, List<double> b) {
  if (a.length == b.length) {
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      final d = a[i] - b[i];
      sum += d * d;
    }
    return sum;
  }
  final na = _normalizedDash(a);
  final nb = _normalizedDash(b);
  final n = na.length < nb.length ? na.length : nb.length;
  var sum = (na.length - nb.length).abs() * 4.0;
  for (var i = 0; i < n; i++) {
    final d = na[i] - nb[i];
    sum += d * d;
  }
  return sum;
}

List<double> _normalizedDash(List<double> values) {
  var max = 0.0;
  for (final value in values) {
    if (value > max) max = value;
  }
  if (max < 1e-12) return values;
  return <double>[for (final value in values) value / max];
}
