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
/// libvisio *does* collect. Unfilled CompoundType 2–4 keep thick/thin contrast
/// the same way: each rail becomes a filled ribbon of that rail's width,
/// because LineWeight is shape-level and stroked rails would share the
/// thinnest width. Arrowed 1-D connectors that also need those
/// rewrites bake Begin/EndArrow as filled Geometry so Draw does not hang a
/// marker on every open rail (and so BeginArrowSize, which is not a token,
/// still has a size). Character Highlight is skipped by `readCharIX` but
/// `TextBkgnd` is collected and painted as `fo:background-color`, so a
/// uniform highlight with no authored text-block fill is written there.
/// `AsianFont` / `ComplexScriptFont` / `ComplexScriptSize` are not tokens —
/// `readCharIX` only stores `Font` and `Size` — so an Asian-only (or
/// complex-script-only) run whose Latin `Font` would tofu in Draw is
/// rewritten to the Asian / complex face, and a complex-only run writes
/// `ComplexScriptSize` into `Size`. `_lineProperties` derives `stroke-linejoin`
/// from `LineCap` only (round cap → round join, otherwise miter), so an
/// explicit round / arcs join on a square/flat cap is baked with the same
/// RelQuadBezTo fillets as shape-level Rounding, and a bevel join becomes a
/// LineTo chamfer. The Rounding cell stays 0 so Visio does not restroke.
library;

import 'dart:math' as math;

import '../export/compound_stroke.dart';
import '../utils/color.dart';
import 'dash_pattern.dart';
import 'fill.dart';
import 'geometry.dart';
import 'line.dart';
import 'perimeter.dart';
import 'rich_text.dart';
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

  var working = shape;
  List<VsdxGeometry> arrowGeoms = const <VsdxGeometry>[];
  if (shapeNeedsLibvisioArrowedStrokeBake(shape)) {
    arrowGeoms = bakeArrowGeometriesForLibvisio(shape);
    working = shape.copyWith(
      line: shape.line.copyWith(beginArrow: 0, endArrow: 0),
    );
    geometries = working.geometries;
    line = working.line;
    if (arrowGeoms.isNotEmpty) geometryRewritten = true;
  }

  final baked = bakeCompoundTypeForLibvisio(working);
  if (baked != null) {
    geometries = baked.geometries;
    line = baked.line;
    if (baked.fill != null) fill = baked.fill!;
    geometryRewritten = true;
    working = working.copyWith(
      geometries: geometries,
      line: line,
      fill: fill,
    );
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
    shape: working,
    geometries: geometries,
    line: line,
  );
  if (ribbon != null) {
    geometries = ribbon.geometries;
    line = ribbon.line;
    fill = ribbon.fill;
    geometryRewritten = true;
  }

  if (arrowGeoms.isNotEmpty) {
    geometries = <VsdxGeometry>[...geometries, ...arrowGeoms];
    if (!fill.hasFill) {
      fill = VsdxFill(
        foreground: line.color ?? const VsdxColor(0xFF000000),
        pattern: 1,
        themeForegroundIndex: line.color == null ? line.themeColorIndex : null,
        foregroundTransparency: line.transparency.clamp(0.0, 1.0),
      );
    }
    line = line.copyWith(beginArrow: 0, endArrow: 0);
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

VsdxShape _withoutArrowheads(VsdxShape shape) => shape.copyWith(
      line: shape.line.copyWith(beginArrow: 0, endArrow: 0),
    );

/// Arrowed 1-D that also needs rails / a ribbon: bake markers as Geometry.
///
/// libvisio hangs `draw:marker-*` on every open path, so CompoundType rails
/// would duplicate arrowheads, and a closed LineGradient / LineColorTrans
/// ribbon cannot carry shape-level markers. `tokens.txt` also has no
/// BeginArrowSize cell — marker width follows line weight — so baking the
/// polygon at [VsdxLine.beginArrowSizeInches] is the size Draw will paint.
bool shapeNeedsLibvisioArrowedStrokeBake(VsdxShape shape) {
  if (!_hasArrowheads(shape.line)) return false;
  if (_shapePaintsFill(shape, shape.geometries)) return false;
  if (_strokeTips(shape) == null) return false;
  final stripped = _withoutArrowheads(shape);
  return shapeNeedsLibvisioCompoundBake(stripped) ||
      shapeNeedsLibvisioStrokeRibbon(stripped);
}

/// `true` when CompoundType would otherwise vanish in Draw.
///
/// 1-D connectors with arrowheads are left alone unless
/// [shapeNeedsLibvisioArrowedStrokeBake] will turn the markers into Geometry
/// first: libvisio hangs a marker on every open path, so splitting a
/// connector into rails would otherwise duplicate the arrow.
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

/// Whether an unfilled CompoundType 2–4 can keep thick/thin contrast in Draw.
///
/// LineWeight is shape-level, so stroked rails must share one width (the
/// thinnest, or they blob). Unfilled solid / gradient / transparent strokes
/// can instead become filled ribbons of each rail's own width — FillPattern
/// and FillForegndTrans are tokens. Dashes 2–23 stay stroked so
/// `_lineProperties` still paints them. Filled 2-D keeps stroked rails
/// because the shape's Fill is already the body colour.
bool _useVariableWidthCompoundRibbons(VsdxShape shape) {
  if (shape.line.compoundType < 2) return false;
  if (_shapePaintsFill(shape, shape.geometries)) return false;
  final pattern = linePatternForLibvisioWrite(shape.line);
  if (pattern >= 2 &&
      pattern <= 23 &&
      !shape.line.hasGradient &&
      shape.line.transparency <= 1e-9) {
    return false;
  }
  return true;
}

/// Offset each stroked polyline into rails libvisio can stroke (or fill).
///
/// CompoundType 1 (equal double) stays two strokes. Unfilled 2–4 become
/// per-rail ribbons so Draw keeps thick-thin / triple contrast; filled 2-D
/// and dashed unfilled strokes keep parallel strokes at the thinnest rail
/// width so they do not blob into one fat line.
({List<VsdxGeometry> geometries, VsdxLine line, VsdxFill? fill})?
    bakeCompoundTypeForLibvisio(
  VsdxShape shape,
) {
  if (!shapeNeedsLibvisioCompoundBake(shape)) return null;
  final weight =
      shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
  final rails = compoundRails(shape.line.compoundType, weight);
  if (rails.isEmpty) return null;
  final useRibbons = _useVariableWidthCompoundRibbons(shape);

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
      if (useRibbons) {
        final commands = strokeRibbonCommands(
          offset,
          halfWidth: rail.width / 2,
          closed: closed,
        );
        if (commands.length < 3) continue;
        out.add(
          VsdxGeometry(
            noFill: false,
            noLine: true,
            commands: commands,
          ),
        );
      } else {
        out.add(
          VsdxGeometry(
            noFill: true,
            noLine: false,
            commands: polylineCommands(offset, closed: closed),
          ),
        );
      }
      addedRails = true;
    }
  }
  if (!addedRails) return null;

  if (useRibbons) {
    final fill = _fillFromLineStroke(shape.line) ??
        VsdxFill(
          foreground: shape.line.color ?? const VsdxColor(0xFF000000),
          background: shape.line.color ?? const VsdxColor(0xFF000000),
          pattern: 1,
          themeForegroundIndex:
              shape.line.color == null ? shape.line.themeColorIndex : null,
        );
    return (
      geometries: out,
      line: shape.line.copyWith(
        compoundType: 0,
        pattern: 0,
        gradient: null,
        transparency: 0,
      ),
      fill: fill,
    );
  }

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
    fill: null,
  );
}

/// `true` when an unfilled LineGradient / LineColorTrans stroke vanishes in Draw.
///
/// `tokens.txt` has no LineGradient or LineColorTrans cell, and
/// `xmlStringToColour` always stores Colour.a = 0, so `VSDContentCollector`
/// paints every VSDX stroke opaque. Arrowheads stay shape-level markers and
/// cannot follow a filled ribbon, so connectors with arrows keep LineColor
/// unless [shapeNeedsLibvisioArrowedStrokeBake] turns the markers into
/// Geometry first. Arrow-less 1-D strokes bake the same ribbon as 2-D:
/// XForm1D / glue cells are untouched, matching CompoundType. Filled
/// shapes already occupy FillPattern, so they keep LineColor (Draw will
/// show an opaque stroke).
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

({Offset2D begin, Offset2D beginFrom, Offset2D end, Offset2D endFrom})?
    _strokeTips(VsdxShape shape) {
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 2) continue;
    var beginFrom = points[1];
    var endFrom = points[points.length - 2];
    if ((beginFrom.x - points.first.x).abs() < 1e-12 &&
        (beginFrom.y - points.first.y).abs() < 1e-12 &&
        points.length > 2) {
      beginFrom = points[2];
    }
    if ((endFrom.x - points.last.x).abs() < 1e-12 &&
        (endFrom.y - points.last.y).abs() < 1e-12 &&
        points.length > 2) {
      endFrom = points[points.length - 3];
    }
    return (
      begin: points.first,
      beginFrom: beginFrom,
      end: points.last,
      endFrom: endFrom,
    );
  }
  return null;
}

/// Filled arrow polygons in the 0–10 marker viewBox used by
/// `VSDContentCollector::_linePropertiesMarkerPath` / SVG `_arrowMarkerBody`
/// (tip at x=10, y=5). Extra ids beyond 2/5/8/11/13/39/40 are the filled
/// cousins Draw would otherwise flatten to the default triangle.
List<List<Offset2D>> _markerPolygons(int arrowId) {
  switch (arrowId) {
    case 2:
    case 15:
      return const [
        [Offset2D(0, 2.5), Offset2D(10, 5), Offset2D(0, 7.5)],
      ];
    case 5:
    case 17:
      return const [
        [Offset2D(0, 1), Offset2D(10, 5), Offset2D(0, 9), Offset2D(3, 5)],
      ];
    case 6:
      return const [
        [Offset2D(0, 1), Offset2D(10, 5), Offset2D(0, 9), Offset2D(7, 5)],
      ];
    case 8:
    case 12:
    case 18:
      return const [
        [
          Offset2D(0, 0.5),
          Offset2D(10, 5),
          Offset2D(0, 9.5),
          Offset2D(2.5, 5),
        ],
      ];
    case 10:
    case 20:
    case 38:
    case 42:
      return const [
        [
          Offset2D(5, 0),
          Offset2D(8.5, 1.5),
          Offset2D(10, 5),
          Offset2D(8.5, 8.5),
          Offset2D(5, 10),
          Offset2D(1.5, 8.5),
          Offset2D(0, 5),
          Offset2D(1.5, 1.5),
        ],
      ];
    case 11:
    case 21:
      return const [
        [Offset2D(0, 1), Offset2D(10, 1), Offset2D(10, 9), Offset2D(0, 9)],
      ];
    case 13:
      return const [
        [Offset2D(0, 1.667), Offset2D(10, 5), Offset2D(0, 8.333)],
      ];
    case 39:
    case 40:
      return const [
        [Offset2D(4, 1), Offset2D(10, 5), Offset2D(4, 9)],
        [Offset2D(0, 1), Offset2D(6, 5), Offset2D(0, 9)],
      ];
    default:
      return const [
        [Offset2D(0, 1), Offset2D(10, 5), Offset2D(0, 9)],
      ];
  }
}

bool _centeredMarker(int arrowId) =>
    arrowId == 9 ||
    arrowId == 10 ||
    arrowId == 11 ||
    arrowId == 20 ||
    arrowId == 21;

Offset2D _markerWorld(
  Offset2D local, {
  required Offset2D tip,
  required double ux,
  required double uy,
  required double scale,
  required double refX,
}) {
  final x = (local.x - refX) * scale;
  final y = (local.y - 5) * scale;
  return Offset2D(
    tip.x + x * ux - y * uy,
    tip.y + x * uy + y * ux,
  );
}

/// Shape-local filled polygons for BeginArrow / EndArrow.
List<VsdxGeometry> bakeArrowGeometriesForLibvisio(VsdxShape shape) {
  final tips = _strokeTips(shape);
  if (tips == null) return const <VsdxGeometry>[];
  final out = <VsdxGeometry>[];
  void add(int id, double size, Offset2D tip, Offset2D from) {
    if (id == 0) return;
    final dx = tip.x - from.x;
    final dy = tip.y - from.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-12) return;
    final ux = dx / len;
    final uy = dy / len;
    final mw = size <= 0 ? 0.125 : size;
    final scale = mw / 10;
    final refX = _centeredMarker(id) ? 5.0 : 10.0;
    for (final poly in _markerPolygons(id)) {
      final world = <Offset2D>[
        for (final p in poly)
          _markerWorld(
            p,
            tip: tip,
            ux: ux,
            uy: uy,
            scale: scale,
            refX: refX,
          ),
      ];
      if (world.length < 3) continue;
      out.add(
        VsdxGeometry(
          noFill: false,
          noLine: true,
          commands: polylineCommands(world, closed: true),
        ),
      );
    }
  }

  add(
    shape.line.beginArrow,
    shape.line.beginArrowSizeInches,
    tips.begin,
    tips.beginFrom,
  );
  add(
    shape.line.endArrow,
    shape.line.endArrowSizeInches,
    tips.end,
    tips.endFrom,
  );
  return out;
}

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

/// Fillet / chamfer radius Draw will actually paint.
///
/// Shape-level `Rounding` is not in `readShapeProperties` (only stylesheet
/// `readLine`). Explicit draw.io joins are also dropped: `_lineProperties`
/// maps join from `LineCap`, so a square/flat cap becomes a miter. Bake
/// round / arcs as RelQuadBezTo and bevel as a LineTo chamfer, at half the
/// line weight, without writing a Rounding cell Visio would apply a second
/// time on top of the geometry. An already-authored Rounding cell wins over
/// a bevel chamfer so Visio's round corners stay round.
double roundingForLibvisioWrite(VsdxLine line) {
  var radius = line.roundingInches;
  if (line.cap == LineCap.round) return radius;
  final joinRadius = (line.weightInches > 1e-9 ? line.weightInches : 0.01) / 2;
  switch (line.join) {
    case VsdxLineJoin.round:
    case VsdxLineJoin.arcs:
      if (joinRadius > radius) radius = joinRadius;
    case VsdxLineJoin.bevel:
      if (radius <= 1e-12) radius = joinRadius;
    case VsdxLineJoin.miter:
    case VsdxLineJoin.miterClip:
    case null:
      break;
  }
  return radius;
}

/// `true` when the baked corner must be a LineTo chamfer, not RelQuadBezTo.
///
/// Only bevel, and only when there is no shape-level Rounding (that cell
/// still means a Visio fillet). Round / arcs keep the quadratic.
bool chamferForLibvisioWrite(VsdxLine line) =>
    line.roundingInches <= 1e-12 &&
    line.cap != LineCap.round &&
    line.join == VsdxLineJoin.bevel;

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

/// Shared Character Highlight of every non-empty run, or `null` if mixed / absent.
VsdxColor? uniformCharacterHighlight(VsdxShape shape) {
  VsdxColor? highlight;
  var sawText = false;
  for (final run in shape.richText.runs) {
    if (run.text.trim().isEmpty) continue;
    sawText = true;
    final color = run.charStyle.highlight;
    if (color == null) return null;
    if (highlight == null) {
      highlight = color;
    } else if (highlight.value != color.value) {
      return null;
    }
  }
  if (sawText) return highlight;
  final plain = shape.text?.trim() ?? '';
  if (plain.isEmpty || shape.richText.runs.isEmpty) return null;
  return shape.richText.runs.first.charStyle.highlight;
}

/// `true` when Character Highlight must be written as TextBkgnd for Draw.
///
/// `readCharIX` has `case XML_HIGHLIGHT: break;`. `TextBkgnd` is a token
/// `VSDContentCollector` paints as span `fo:background-color`. Skip when the
/// block already has a fill — that cell is the user's text-block colour.
bool shapeNeedsLibvisioTextBkgndBake(VsdxShape shape) {
  final block = shape.richText.textBlock;
  if (block.hideText) return false;
  if (block.backgroundColor != null) return false;
  return uniformCharacterHighlight(shape) != null;
}

/// Text block cells the writer should emit so Draw paints Highlight.
VsdxTextBlock textBlockForLibvisioWrite(VsdxShape shape) {
  final block = shape.richText.textBlock;
  if (!shapeNeedsLibvisioTextBkgndBake(shape)) return block;
  return block.copyWith(backgroundColor: uniformCharacterHighlight(shape));
}

/// TextBkgnd to paint here. `null` when it is only the LibreOffice stand-in
/// for Character Highlight, so canvas / SVG keep the tighter highlight halo.
VsdxColor? textBlockBackgroundForPaint(VsdxShape shape) {
  final background = shape.richText.textBlock.backgroundColor;
  if (background == null) return null;
  final highlight = uniformCharacterHighlight(shape);
  if (highlight != null && highlight.value == background.value) return null;
  return background;
}

/// [VsdxShape.richText] text block with a Highlight-stand-in TextBkgnd cleared.
VsdxTextBlock textBlockForPaint(VsdxShape shape) {
  final block = shape.richText.textBlock;
  if (textBlockBackgroundForPaint(shape) != null ||
      block.backgroundColor == null) {
    return block;
  }
  return block.withoutBackgroundColor();
}

/// Face libvisio's `readCharIX` will actually load (`tokens.txt` has `Font`,
/// not `AsianFont` / `ComplexScriptFont`).
const kLibvisioDefaultAsianFont = 'Microsoft YaHei';

bool _isLatinLetterRune(int rune) =>
    (rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A);

/// Han / Kana / Hangul / Bopomofo with no Latin or complex-script letters.
bool _isAsianOnly(String text) {
  var hasAsian = false;
  for (final rune in text.runes) {
    if (isVisioAsianScriptRune(rune)) {
      hasAsian = true;
      continue;
    }
    if (isVisioComplexScriptRune(rune) || _isLatinLetterRune(rune)) {
      return false;
    }
  }
  return hasAsian;
}

/// Arabic / Hebrew / Indic / … with no Latin or East-Asian letters.
bool _isComplexScriptOnly(String text) {
  var hasComplex = false;
  for (final rune in text.runes) {
    if (isVisioComplexScriptRune(rune)) {
      hasComplex = true;
      continue;
    }
    if (isVisioAsianScriptRune(rune) || _isLatinLetterRune(rune)) {
      return false;
    }
  }
  return hasComplex;
}

bool _isLatinUiFace(String? face) {
  if (face == null || face.isEmpty) return true;
  switch (face.toLowerCase()) {
    case 'arial':
    case 'calibri':
    case 'cambria':
    case 'candara':
    case 'consolas':
    case 'constantia':
    case 'corbel':
    case 'courier new':
    case 'georgia':
    case 'helvetica':
    case 'segoe ui':
    case 'tahoma':
    case 'times':
    case 'times new roman':
    case 'trebuchet ms':
    case 'verdana':
      return true;
    default:
      return false;
  }
}

/// `Font` cell Draw will collect. Asian-only runs whose Visio `Font` is a
/// Latin UI face are rewritten to `AsianFont` (or YaHei); complex-script-only
/// runs use `ComplexScriptFont`. Mixed Latin+CJK / Latin+Arabic keep `Font`
/// so Visio's Latin glyphs do not change face.
String? fontFamilyForLibvisioWrite(VsdxCharStyle style, String text) {
  final current = style.fontFamily;
  if (_isAsianOnly(text)) {
    final asian = style.asianFont?.trim();
    if (asian != null && asian.isNotEmpty) return asian;
    if (_isLatinUiFace(current)) return kLibvisioDefaultAsianFont;
    return current;
  }
  if (_isComplexScriptOnly(text)) {
    final complex = style.complexScriptFont?.trim();
    if (complex != null && complex.isNotEmpty) return complex;
  }
  return current;
}

/// `Size` cell Draw will collect. `ComplexScriptSize` is not a token, so a
/// complex-script-only run writes that size into `Size`. Mixed runs keep
/// `Size` so Latin glyphs do not jump.
double fontSizeForLibvisioWrite(VsdxCharStyle style, String text) {
  final complex = style.complexScriptSizeInches;
  if (complex != null &&
      _isComplexScriptOnly(text) &&
      (complex - style.fontSizeInches).abs() > 1e-12) {
    return complex;
  }
  return style.fontSizeInches;
}

bool shapeNeedsLibvisioFontBake(VsdxShape shape) {
  if (shape.richText.textBlock.hideText) return false;
  for (final run in shape.richText.runs) {
    if (run.text.trim().isEmpty) continue;
    final baked = fontFamilyForLibvisioWrite(run.charStyle, run.text);
    final current = run.charStyle.fontFamily;
    if ((baked ?? '') != (current ?? '')) return true;
    if ((fontSizeForLibvisioWrite(run.charStyle, run.text) -
                run.charStyle.fontSizeInches)
            .abs() >
        1e-12) {
      return true;
    }
  }
  return false;
}
