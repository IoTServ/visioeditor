/// Rewrite shape line appearance into cells / rows libvisio still collects.
///
/// LibreOffice Draw never reads Visio XML itself — `VisioImportFilter.cxx`
/// only calls `VisioDocument::isSupported` + `parse`. The VSDX token map has
/// no `CompoundType` and no `LineGradient`, `LineColorTrans` is absent and
/// `xmlStringToColour` forces Colour.a = 0, and unknown `LinePattern` ids
/// (custom draw.io arrays, 0xFE, …) fall through `_lineProperties` to a solid
/// stroke. A save therefore has to emit parallel Geometry rails, a built-in
/// pattern 2–23, and — for an unfilled stroke with a line gradient or
/// LineColorTrans — a filled ribbon whose FillPattern 25–40 / FillForegndTrans
/// libvisio *does* collect.
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
  var fill = shape.fill;
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

  final ribbon = bakeStrokeRibbonForLibvisio(
    shape: shape,
    geometries: geometries,
    line: line,
  );
  if (ribbon != null) {
    geometries = ribbon.geometries;
    line = ribbon.line;
    fill = ribbon.fill;
    geometryRewritten = true;
  }

  return LibvisioShapeWrite(
    geometries: geometries,
    line: line,
    fill: fill,
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

bool _shapePaintsFill(VsdxShape shape, List<VsdxGeometry> geometries) {
  if (!shape.fill.hasFill) return false;
  for (final geometry in geometries) {
    if (!geometry.noShow && !geometry.noFill) return true;
  }
  return false;
}

bool _hasArrowheads(VsdxLine line) =>
    line.beginArrow != 0 || line.endArrow != 0;

/// `true` when CompoundType would otherwise vanish in Draw.
///
/// 1-D connectors with arrowheads are left alone: libvisio hangs a marker on
/// every open path, so splitting a connector into rails duplicates the arrow.
/// Arrow-less 1-D double-lines bake the same way 2-D shapes do.
bool shapeNeedsLibvisioCompoundBake(VsdxShape shape) {
  if (shape.is1D && _hasArrowheads(shape.line)) return false;
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

/// `true` when an unfilled LineGradient / LineColorTrans stroke vanishes in Draw.
///
/// `tokens.txt` has no LineGradient or LineColorTrans cell, and
/// `xmlStringToColour` always stores Colour.a = 0, so `VSDContentCollector`
/// paints every VSDX stroke opaque. Arrowheads stay shape-level markers and
/// cannot follow a filled ribbon, so connectors with arrows keep LineColor.
/// Arrow-less 1-D strokes bake the same ribbon as 2-D: XForm1D / glue cells
/// are untouched, matching CompoundType. Filled shapes already occupy
/// FillPattern, so they keep LineColor (Draw will show an opaque stroke).
bool shapeNeedsLibvisioStrokeRibbon(VsdxShape shape) {
  if (_hasArrowheads(shape.line)) return false;
  if (!shape.line.hasLine) return false;
  if (!shape.line.hasGradient && shape.line.transparency <= 1e-9) {
    return false;
  }
  if (_shapePaintsFill(shape, shape.geometries)) return false;
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points != null && points.length >= 2) return true;
  }
  return false;
}

/// Back-compat name for the LineGradient half of [shapeNeedsLibvisioStrokeRibbon].
bool shapeNeedsLibvisioLineGradientRibbon(VsdxShape shape) =>
    shape.line.hasGradient && shapeNeedsLibvisioStrokeRibbon(shape);

/// Expand an unfilled gradient or transparent stroke into a closed ribbon
/// FillPattern 25–40 / FillForegndTrans can paint. Compound rails, when
/// present, are expanded one by one.
({List<VsdxGeometry> geometries, VsdxLine line, VsdxFill fill})?
    bakeStrokeRibbonForLibvisio({
  required VsdxShape shape,
  required List<VsdxGeometry> geometries,
  required VsdxLine line,
}) {
  if (!shapeNeedsLibvisioStrokeRibbon(shape)) return null;
  if (!line.hasLine) return null;
  final fill = _fillFromLineStroke(line);
  if (fill == null) return null;

  final weight = line.weightInches > 1e-9 ? line.weightInches : 0.01;
  final half = weight / 2;
  final out = <VsdxGeometry>[];
  var added = false;
  for (final geometry in geometries) {
    if (geometry.noShow || geometry.noLine) {
      out.add(geometry);
      continue;
    }
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 2) {
      out.add(geometry);
      continue;
    }
    final closed = polylineLooksClosed(points, noFill: geometry.noFill);
    final commands = strokeRibbonCommands(
      points,
      halfWidth: half,
      closed: closed,
    );
    if (commands.length < 3) {
      out.add(geometry);
      continue;
    }
    out.add(
      VsdxGeometry(
        noFill: false,
        noLine: true,
        commands: commands,
      ),
    );
    added = true;
  }
  if (!added) return null;

  return (
    geometries: out,
    line: line.copyWith(pattern: 0, gradient: null, transparency: 0),
    fill: fill,
  );
}

VsdxFill? _fillFromLineStroke(VsdxLine line) {
  final transparency = line.transparency.clamp(0.0, 1.0);
  if (line.hasGradient) {
    final gradient = line.gradient!;
    VsdxColor? first;
    VsdxColor? last;
    for (final stop in gradient.stops) {
      if (stop.color != null) {
        first ??= stop.color;
        last = stop.color;
      }
    }
    first ??= line.color ?? const VsdxColor(0xFF000000);
    last ??= first;
    return VsdxFill(
      foreground: first,
      background: last,
      pattern: 1,
      gradient: gradient,
      foregroundTransparency: transparency,
      backgroundTransparency: transparency,
    );
  }
  if (transparency <= 1e-9) return null;
  return VsdxFill(
    foreground: line.color ?? const VsdxColor(0xFF000000),
    background: line.color ?? const VsdxColor(0xFF000000),
    pattern: 1,
    themeForegroundIndex: line.color == null ? line.themeColorIndex : null,
    foregroundTransparency: transparency,
    backgroundTransparency: transparency,
  );
}

/// Closed polygon covering a stroked polyline, used as a filled ribbon.
List<VsdxPathCommand> strokeRibbonCommands(
  List<Offset2D> points, {
  required double halfWidth,
  required bool closed,
}) {
  final left = offsetPolyline(points, halfWidth, closed: closed);
  final right = offsetPolyline(points, -halfWidth, closed: closed);
  if (left.length < 2 || right.length < 2) {
    return const <VsdxPathCommand>[];
  }
  if (closed) {
    return <VsdxPathCommand>[
      ...polylineCommands(left, closed: true),
      ...polylineCommands(List<Offset2D>.of(right.reversed), closed: true),
    ];
  }
  return polylineCommands(
    <Offset2D>[...left, ...right.reversed],
    closed: true,
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
