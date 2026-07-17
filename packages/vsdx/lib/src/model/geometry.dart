/// Intermediate geometry representation.
///
/// One [VsdxGeometry] mirrors a single `<Section N="Geometry" IX="...">`
/// block. We deliberately keep coordinates in **local shape inches**
/// (i.e. `0..Width` × `0..Height`) — the render layer applies the shape's
/// XForm and the page→viewport transform.
///
/// `Rel*` row types are kept as their own command variants — the conversion
/// from "fraction of width/height" to absolute local inches happens in
/// `lib/render/path_builder.dart`, where the parent's width and height are
/// known. This keeps the parser pure (no shape context required).
library;

import 'package:meta/meta.dart';

@immutable
sealed class VsdxPathCommand {
  const VsdxPathCommand();
}

@immutable
class MoveTo extends VsdxPathCommand {
  const MoveTo(this.x, this.y);
  final double x;
  final double y;
  @override
  String toString() => 'MoveTo($x, $y)';
}

@immutable
class LineTo extends VsdxPathCommand {
  const LineTo(this.x, this.y);
  final double x;
  final double y;
  @override
  String toString() => 'LineTo($x, $y)';
}

/// `RelMoveTo` — X and Y are fractions of the shape's width / height
/// respectively (Visio docs §"Geometry Section").
@immutable
class RelMoveTo extends VsdxPathCommand {
  const RelMoveTo(this.fx, this.fy);
  final double fx;
  final double fy;
  @override
  String toString() => 'RelMoveTo($fx, $fy)';
}

@immutable
class RelLineTo extends VsdxPathCommand {
  const RelLineTo(this.fx, this.fy);
  final double fx;
  final double fy;
  @override
  String toString() => 'RelLineTo($fx, $fy)';
}

/// `CubBezTo` — cubic Bézier curve to (`x`,`y`) with control points
/// (`x1`,`y1`) and (`x2`,`y2`), all in shape-local inches. MS-VSDX
/// §"CubBezTo Row" (`A`/`B` = first control point, `C`/`D` = second,
/// `X`/`Y` = end point).
@immutable
class CubBezTo extends VsdxPathCommand {
  const CubBezTo({
    required this.x,
    required this.y,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });
  final double x;
  final double y;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  @override
  String toString() => 'CubBezTo(c1=($x1,$y1) c2=($x2,$y2) -> ($x,$y))';
}

/// `RelCubBezTo` — like [CubBezTo] but every coordinate is a fraction of the
/// shape's width/height (X/A/C scale by width, Y/B/D by height). The
/// fraction→inches conversion happens in the render layer, mirroring
/// [RelMoveTo] / [RelLineTo].
@immutable
class RelCubBezTo extends VsdxPathCommand {
  const RelCubBezTo({
    required this.fx,
    required this.fy,
    required this.fx1,
    required this.fy1,
    required this.fx2,
    required this.fy2,
  });
  final double fx;
  final double fy;
  final double fx1;
  final double fy1;
  final double fx2;
  final double fy2;
  @override
  String toString() => 'RelCubBezTo(c1=($fx1,$fy1) c2=($fx2,$fy2) -> ($fx,$fy))';
}

/// `QuadBezTo` — quadratic Bézier curve to (`x`,`y`) with a single control
/// point (`x1`,`y1`), in shape-local inches (`A`/`B` = control, `X`/`Y` = end).
@immutable
class QuadBezTo extends VsdxPathCommand {
  const QuadBezTo({
    required this.x,
    required this.y,
    required this.x1,
    required this.y1,
  });
  final double x;
  final double y;
  final double x1;
  final double y1;
  @override
  String toString() => 'QuadBezTo(c=($x1,$y1) -> ($x,$y))';
}

/// `RelQuadBezTo` — like [QuadBezTo] but every coordinate is a fraction of the
/// shape's width/height (X/A scale by width, Y/B by height). MS-VSDX
/// §"RelQuadBezTo Row".
@immutable
class RelQuadBezTo extends VsdxPathCommand {
  const RelQuadBezTo({
    required this.fx,
    required this.fy,
    required this.fx1,
    required this.fy1,
  });
  final double fx;
  final double fy;
  final double fx1;
  final double fy1;
  @override
  String toString() => 'RelQuadBezTo(c=($fx1,$fy1) -> ($fx,$fy))';
}

/// `ArcTo` — end point + `bow` (the perpendicular offset of the arc's apex
/// from the chord, MS-VSDX §"ArcTo Row").
@immutable
class ArcTo extends VsdxPathCommand {
  const ArcTo({required this.x, required this.y, required this.bow});
  final double x;
  final double y;
  final double bow;
  @override
  String toString() => 'ArcTo($x, $y, bow=$bow)';
}

/// `RelArcTo` — like [ArcTo] but X/Y/A are fractions of the shape's
/// width/height (bow scales with the average of width and height at render
/// time, matching how absolute ArcTo bow is scaled on resize).
@immutable
class RelArcTo extends VsdxPathCommand {
  const RelArcTo({required this.fx, required this.fy, required this.fbow});
  final double fx;
  final double fy;
  final double fbow;
  @override
  String toString() => 'RelArcTo($fx, $fy, bow=$fbow)';
}

/// `EllipticalArcTo` — Visio's general elliptical arc.
///
/// MS-VSDX §"EllipticalArcTo Row":
///   * (`x`,`y`) = arc end point (shape-local inches)
///   * (`controlX`,`controlY`) = a point that lies **on** the arc (typically
///     near its midpoint). Together with the start point this is enough to
///     identify the unique ellipse.
///   * `angle` = ellipse major-axis rotation (radians, CCW from page X)
///   * `eccentricity` = major/minor axis ratio (≥ 1)
///
/// The render pipeline approximates this with a quadratic Bezier through the
/// control point — good enough for the vast majority of stencil shapes
/// (rounded rectangles, callouts, end-caps). A true elliptical arc plotter
/// arrives with the NURBS work in a follow-up M3 iteration.
@immutable
class EllipticalArcTo extends VsdxPathCommand {
  const EllipticalArcTo({
    required this.x,
    required this.y,
    required this.controlX,
    required this.controlY,
    this.angle = 0,
    this.eccentricity = 1,
  });
  final double x;
  final double y;
  final double controlX;
  final double controlY;
  final double angle;
  final double eccentricity;
  @override
  String toString() =>
      'EllipticalArcTo($x,$y ctrl=($controlX,$controlY) '
      'angle=$angle ecc=$eccentricity)';
}

/// `RelEllipticalArcTo` — like [EllipticalArcTo] but the end point (`fx`,`fy`)
/// and the on-arc control point (`fcx`,`fcy`) are fractions of the shape's
/// width/height. [angle] (radians) and [eccentricity] (ratio) are absolute,
/// exactly as in the non-relative row. MS-VSDX §"RelEllipticalArcTo Row".
@immutable
class RelEllipticalArcTo extends VsdxPathCommand {
  const RelEllipticalArcTo({
    required this.fx,
    required this.fy,
    required this.fcx,
    required this.fcy,
    this.angle = 0,
    this.eccentricity = 1,
  });
  final double fx;
  final double fy;
  final double fcx;
  final double fcy;
  final double angle;
  final double eccentricity;
  @override
  String toString() => 'RelEllipticalArcTo($fx,$fy ctrl=($fcx,$fcy) '
      'angle=$angle ecc=$eccentricity)';
}

/// `Ellipse` — fully specified by three reference points (centre + two axis
/// endpoints), in shape-local inches.
@immutable
class EllipseCmd extends VsdxPathCommand {
  const EllipseCmd({
    required this.cx,
    required this.cy,
    required this.aX,
    required this.aY,
    required this.bX,
    required this.bY,
  });
  final double cx;
  final double cy;
  final double aX;
  final double aY;
  final double bX;
  final double bY;
  @override
  String toString() =>
      'Ellipse(c=($cx,$cy), a=($aX,$aY), b=($bX,$bY))';
}

/// `PolylineTo` — Visio packs the polyline data inside a `POLYLINE(...)`
/// formula on the `A` cell:
///   `POLYLINE(0, 2, x0,y0, x1,y1, …, xN,yN)`
/// The first two integers are flags (`degree`, `useRelative`); the rest are
/// vertex coordinates in shape-local inches (already pre-resolved by Visio,
/// so we read them as-is). The `X`/`Y` cells give the polyline's end
/// point, used as the cursor advance after the last vertex.
///
/// MS-VSDX §"PolylineTo Row".
@immutable
class PolylineTo extends VsdxPathCommand {
  const PolylineTo({
    required this.x,
    required this.y,
    required this.vertices,
    this.relative = false,
  });

  /// End point of the polyline (after the last interior vertex).
  final double x;
  final double y;

  /// Interior vertices, in (x, y) pairs (shape-local inches). Excludes the
  /// shape's current pen position (the implicit P0) and the end point
  /// [x]/[y] (the implicit Pn). When [relative] is true these are fractions
  /// of width/height (from `RelPolylineTo`).
  final List<Offset2D> vertices;

  /// `true` when the row was `RelPolylineTo` (or POLYLINE useRelative).
  final bool relative;

  @override
  String toString() =>
      '${relative ? 'Rel' : ''}PolylineTo($x, $y, ${vertices.length} verts)';
}

/// `InfiniteLine` — a straight line passing through (`x`, `y`) with the
/// direction implied by (`a`, `b`). Render-time clips to a large bound
/// inside the shape's local box.
@immutable
class InfiniteLineCmd extends VsdxPathCommand {
  const InfiniteLineCmd({
    required this.x,
    required this.y,
    required this.a,
    required this.b,
    this.relative = false,
  });
  final double x;
  final double y;
  final double a;
  final double b;
  final bool relative;
  @override
  String toString() =>
      '${relative ? 'Rel' : ''}InfiniteLine(p=($x,$y), q=($a,$b))';
}

/// `SplineStart` — anchor point for a B-spline that follows via
/// [SplineKnot] rows. MS-VSDX §"SplineStart Row".
///
/// Visio stores spline control points and knots inline; for the first cut
/// we approximate the curve as a chord polyline (the same fallback all
/// minor open-source readers use). Real cubic-spline reconstruction lives
/// behind a feature flag in the path builder.
@immutable
class SplineStart extends VsdxPathCommand {
  const SplineStart({
    required this.x,
    required this.y,
    required this.a,
    required this.b,
    required this.c,
    this.degree = 3,
    this.relative = false,
  });
  final double x;
  final double y;

  /// Second knot value (`A` cell — the first interior knot).
  final double a;

  /// Initial knot count (`B` cell — usually `degree + 1`).
  final double b;

  /// Spline weight (`C` cell — left at 1 for unit-weight splines).
  final double c;

  /// Spline degree (typically 3 for cubic). Defaults to 3.
  final int degree;

  final bool relative;

  @override
  String toString() =>
      '${relative ? 'Rel' : ''}SplineStart($x, $y, degree=$degree)';
}

/// `SplineKnot` — subsequent control point in a spline that began with
/// [SplineStart]. Interpreted as a polyline vertex by the path builder.
@immutable
class SplineKnot extends VsdxPathCommand {
  const SplineKnot({
    required this.x,
    required this.y,
    required this.knot,
    this.relative = false,
  });
  final double x;
  final double y;

  /// The knot value (`A` cell).
  final double knot;

  final bool relative;

  @override
  String toString() =>
      '${relative ? 'Rel' : ''}SplineKnot($x, $y, knot=$knot)';
}

/// `NURBSTo` — non-uniform rational B-spline arc. Visio packs the control
/// points / knots / weights inside an `NURBS(...)` formula on the `E` cell.
///
/// Knots and per-point weights are now decoded too so the path builder can
/// run a real de Boor evaluation; when they are absent the builder falls
/// back to the chord polyline through the control points.
@immutable
class NurbsTo extends VsdxPathCommand {
  const NurbsTo({
    required this.x,
    required this.y,
    required this.controlPoints,
    this.weights = const <double>[],
    this.knots = const <double>[],
    this.degree = 3,
    this.relative = false,
  });

  /// Final endpoint of the NURBS arc.
  final double x;
  final double y;

  /// Control points (knots stripped) decoded from the `NURBS(...)` formula.
  final List<Offset2D> controlPoints;

  /// Per-control-point weights. Empty ⇒ all 1.0.
  final List<double> weights;

  /// Knot vector. Empty ⇒ uniform clamped (so the builder synthesises
  /// `[0,0,…,0, k, k+1, …, 1,1,…,1]`).
  final List<double> knots;

  final int degree;

  /// `true` when the row was `RelNURBSTo`.
  final bool relative;

  @override
  String toString() =>
      '${relative ? 'Rel' : ''}NurbsTo($x, $y, ${controlPoints.length} cps, deg=$degree)';
}

/// A tiny 2D point value object, kept local to the geometry layer so the
/// model has zero `dart:ui` dependency.
@immutable
class Offset2D {
  const Offset2D(this.x, this.y);
  final double x;
  final double y;
  @override
  bool operator ==(Object other) =>
      other is Offset2D && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
  @override
  String toString() => '($x, $y)';
}

/// A Visio `<Section N="Connection">` row — glue point with optional direction
/// and type metadata (libvisio / MS-VSDX Connection Row).
@immutable
class VsdxConnectionPoint {
  const VsdxConnectionPoint(
    this.x,
    this.y, {
    this.dirX = 0.0,
    this.dirY = 0.0,
    this.type = 0,
    this.autoGen = false,
    this.prompt,
    this.xFormula,
    this.yFormula,
  });

  /// Shape-local inches (origin bottom-left, Y-up).
  final double x;
  final double y;

  /// Outward direction of the connection (`DirX` / `DirY`).
  final double dirX;
  final double dirY;

  /// Visio `Type` cell (0 = inward, …).
  final int type;

  /// `AutoGen` — Visio may regenerate this point.
  final bool autoGen;

  /// Optional `Prompt` string.
  final String? prompt;

  /// Optional `F=` on X/Y (`Width*0.5`, …) — required for group rebuild.
  final String? xFormula;
  final String? yFormula;

  Offset2D get offset => Offset2D(x, y);

  VsdxConnectionPoint copyWith({
    double? x,
    double? y,
    double? dirX,
    double? dirY,
    int? type,
    bool? autoGen,
    String? prompt,
    String? xFormula,
    String? yFormula,
  }) =>
      VsdxConnectionPoint(
        x ?? this.x,
        y ?? this.y,
        dirX: dirX ?? this.dirX,
        dirY: dirY ?? this.dirY,
        type: type ?? this.type,
        autoGen: autoGen ?? this.autoGen,
        prompt: prompt ?? this.prompt,
        xFormula: xFormula ?? this.xFormula,
        yFormula: yFormula ?? this.yFormula,
      );

  @override
  bool operator ==(Object other) =>
      other is VsdxConnectionPoint &&
      other.x == x &&
      other.y == y &&
      other.dirX == dirX &&
      other.dirY == dirY &&
      other.type == type &&
      other.autoGen == autoGen &&
      other.prompt == prompt &&
      other.xFormula == xFormula &&
      other.yFormula == yFormula;

  @override
  int get hashCode =>
      Object.hash(x, y, dirX, dirY, type, autoGen, prompt, xFormula, yFormula);

  @override
  String toString() => 'ConnectionPoint($x, $y, dir=($dirX,$dirY))';
}

/// Re-apply ShapeSheet cell formulas onto an absolute path command.
///
/// [eval] resolves `F=` strings (may return `null` when the formula needs
/// context we don't have). Relative (`Rel*`) commands are returned unchanged
/// — they already scale with Width/Height at paint time. `PolylineTo` /
/// NURBS / spline rows are left alone when their packed formulas cannot be
/// re-evaluated locally.
VsdxPathCommand applyPathCommandFormulas(
  VsdxPathCommand cmd,
  Map<String, String> formulas,
  double? Function(String? formula) eval,
) {
  if (formulas.isEmpty) return cmd;
  double? cell(String name) {
    final f = formulas[name];
    if (f == null || f.isEmpty) return null;
    return eval(f);
  }

  switch (cmd) {
    case MoveTo(:final x, :final y):
      final nx = cell('X');
      final ny = cell('Y');
      if (nx == null && ny == null) return cmd;
      return MoveTo(nx ?? x, ny ?? y);
    case LineTo(:final x, :final y):
      final nx = cell('X');
      final ny = cell('Y');
      if (nx == null && ny == null) return cmd;
      return LineTo(nx ?? x, ny ?? y);
    case ArcTo(:final x, :final y, :final bow):
      final nx = cell('X');
      final ny = cell('Y');
      final na = cell('A');
      if (nx == null && ny == null && na == null) return cmd;
      return ArcTo(x: nx ?? x, y: ny ?? y, bow: na ?? bow);
    case EllipticalArcTo(
        :final x,
        :final y,
        :final controlX,
        :final controlY,
        :final angle,
        :final eccentricity,
      ):
      final nx = cell('X');
      final ny = cell('Y');
      final na = cell('A');
      final nb = cell('B');
      final nc = cell('C');
      final nd = cell('D');
      if (nx == null &&
          ny == null &&
          na == null &&
          nb == null &&
          nc == null &&
          nd == null) {
        return cmd;
      }
      return EllipticalArcTo(
        x: nx ?? x,
        y: ny ?? y,
        controlX: na ?? controlX,
        controlY: nb ?? controlY,
        angle: nc ?? angle,
        eccentricity: nd ?? eccentricity,
      );
    case CubBezTo(
        :final x,
        :final y,
        :final x1,
        :final y1,
        :final x2,
        :final y2,
      ):
      final nx = cell('X');
      final ny = cell('Y');
      final na = cell('A');
      final nb = cell('B');
      final nc = cell('C');
      final nd = cell('D');
      if (nx == null &&
          ny == null &&
          na == null &&
          nb == null &&
          nc == null &&
          nd == null) {
        return cmd;
      }
      return CubBezTo(
        x: nx ?? x,
        y: ny ?? y,
        x1: na ?? x1,
        y1: nb ?? y1,
        x2: nc ?? x2,
        y2: nd ?? y2,
      );
    case QuadBezTo(:final x, :final y, :final x1, :final y1):
      final nx = cell('X');
      final ny = cell('Y');
      final na = cell('A');
      final nb = cell('B');
      if (nx == null && ny == null && na == null && nb == null) return cmd;
      return QuadBezTo(
        x: nx ?? x,
        y: ny ?? y,
        x1: na ?? x1,
        y1: nb ?? y1,
      );
    case EllipseCmd(
        :final cx,
        :final cy,
        :final aX,
        :final aY,
        :final bX,
        :final bY,
      ):
      final nx = cell('X');
      final ny = cell('Y');
      final na = cell('A');
      final nb = cell('B');
      final nc = cell('C');
      final nd = cell('D');
      if (nx == null &&
          ny == null &&
          na == null &&
          nb == null &&
          nc == null &&
          nd == null) {
        return cmd;
      }
      return EllipseCmd(
        cx: nx ?? cx,
        cy: ny ?? cy,
        aX: na ?? aX,
        aY: nb ?? aY,
        bX: nc ?? bX,
        bY: nd ?? bY,
      );
    case InfiniteLineCmd(:final x, :final y, :final a, :final b, :final relative):
      if (relative) return cmd;
      final nx = cell('X');
      final ny = cell('Y');
      final na = cell('A');
      final nb = cell('B');
      if (nx == null && ny == null && na == null && nb == null) return cmd;
      return InfiniteLineCmd(
        x: nx ?? x,
        y: ny ?? y,
        a: na ?? a,
        b: nb ?? b,
      );
    case PolylineTo(:final x, :final y, :final vertices, :final relative):
      if (relative) return cmd;
      final nx = cell('X');
      final ny = cell('Y');
      if (nx == null && ny == null) return cmd;
      // Interior POLYLINE(...) vertices stay as cached; only the end point
      // X/Y cells are locally re-evaluated.
      return PolylineTo(
        x: nx ?? x,
        y: ny ?? y,
        vertices: vertices,
        relative: relative,
      );
    case RelMoveTo():
    case RelLineTo():
    case RelCubBezTo():
    case RelQuadBezTo():
    case RelArcTo():
    case RelEllipticalArcTo():
    case SplineStart():
    case SplineKnot():
    case NurbsTo():
      return cmd;
  }
}

/// Scale a path command's coordinates by ([sx], [sy]) about the shape-local
/// origin. Fractional `Rel*` commands are returned unchanged because they
/// already scale with the shape's width/height at render time.
VsdxPathCommand scalePathCommand(VsdxPathCommand c, double sx, double sy) {
  switch (c) {
    case MoveTo(:final x, :final y):
      return MoveTo(x * sx, y * sy);
    case LineTo(:final x, :final y):
      return LineTo(x * sx, y * sy);
    case RelMoveTo():
      return c;
    case RelLineTo():
      return c;
    case CubBezTo(
        :final x,
        :final y,
        :final x1,
        :final y1,
        :final x2,
        :final y2,
      ):
      return CubBezTo(
        x: x * sx,
        y: y * sy,
        x1: x1 * sx,
        y1: y1 * sy,
        x2: x2 * sx,
        y2: y2 * sy,
      );
    case RelCubBezTo():
      return c;
    case QuadBezTo(:final x, :final y, :final x1, :final y1):
      return QuadBezTo(x: x * sx, y: y * sy, x1: x1 * sx, y1: y1 * sy);
    case RelQuadBezTo():
      return c;
    case RelEllipticalArcTo():
      return c;
    case ArcTo(:final x, :final y, :final bow):
      return ArcTo(x: x * sx, y: y * sy, bow: bow * (sx + sy) / 2);
    case RelArcTo():
      return c;
    case EllipticalArcTo(
        :final x,
        :final y,
        :final controlX,
        :final controlY,
        :final angle,
        :final eccentricity,
      ):
      return EllipticalArcTo(
        x: x * sx,
        y: y * sy,
        controlX: controlX * sx,
        controlY: controlY * sy,
        angle: angle,
        eccentricity: eccentricity,
      );
    case EllipseCmd(
        :final cx,
        :final cy,
        :final aX,
        :final aY,
        :final bX,
        :final bY,
      ):
      return EllipseCmd(
        cx: cx * sx,
        cy: cy * sy,
        aX: aX * sx,
        aY: aY * sy,
        bX: bX * sx,
        bY: bY * sy,
      );
    case PolylineTo(:final x, :final y, :final vertices, :final relative):
      if (relative) return c;
      return PolylineTo(
        x: x * sx,
        y: y * sy,
        vertices: <Offset2D>[
          for (final v in vertices) Offset2D(v.x * sx, v.y * sy),
        ],
      );
    case InfiniteLineCmd(:final x, :final y, :final a, :final b, :final relative):
      if (relative) return c;
      return InfiniteLineCmd(x: x * sx, y: y * sy, a: a * sx, b: b * sy);
    case SplineStart(
        :final x,
        :final y,
        a: final knotA,
        b: final knotB,
        c: final weight,
        :final degree,
        :final relative,
      ):
      if (relative) return c;
      return SplineStart(
          x: x * sx,
          y: y * sy,
          a: knotA,
          b: knotB,
          c: weight,
          degree: degree);
    case SplineKnot(:final x, :final y, :final knot, :final relative):
      if (relative) return c;
      return SplineKnot(x: x * sx, y: y * sy, knot: knot);
    case NurbsTo(
        :final x,
        :final y,
        :final controlPoints,
        :final weights,
        :final knots,
        :final degree,
        :final relative,
      ):
      if (relative) return c;
      return NurbsTo(
        x: x * sx,
        y: y * sy,
        controlPoints: <Offset2D>[
          for (final p in controlPoints) Offset2D(p.x * sx, p.y * sy),
        ],
        weights: weights,
        knots: knots,
        degree: degree,
      );
  }
}

/// A single Geometry section.
@immutable
class VsdxGeometry {
  const VsdxGeometry({
    required this.commands,
    this.commandFormulas = const <Map<String, String>>[],
    this.noFill = false,
    this.noLine = false,
    this.noShow = false,
    this.noSnap = false,
    this.noQuickDrag = false,
    this.ix = 0,
    this.rowIndices = const <int>[],
    this.deletedRowIndices = const <int>{},
    this.definedFlagCells = const <String>{},
    this.deleted = false,
  });

  /// Path commands in source order.
  final List<VsdxPathCommand> commands;

  /// Per-command Cell `N` → `F=` maps (aligned with [commands]). Empty when
  /// the row has no parametric formulas. Required so group rebuild keeps
  /// `Scratch.X1` / `Width*` / `Height*` on Geometry rows.
  final List<Map<String, String>> commandFormulas;

  /// `<Cell N="NoFill" V="1"/>` — suppress fill for this geometry only.
  final bool noFill;
  final bool noLine;

  /// `<Cell N="NoShow" V="1"/>` — don't draw at all (still hit-tests).
  final bool noShow;

  /// `<Cell N="NoSnap" V="1"/>` — exclude from snap targets.
  final bool noSnap;

  /// `<Cell N="NoQuickDrag" V="1"/>` — disable quick-drag handles.
  final bool noQuickDrag;

  /// Section index (`<Section N="Geometry" IX="N">`). Used to merge a shape's
  /// geometry with the geometry it inherits from its master by matching IX
  /// (mirrors libvisio's per-IX geometry inheritance). Default 0.
  final int ix;

  /// Source `IX` of each command row (parallel to [commands]). Empty for
  /// programmatically-built geometry that never participates in master merge.
  final List<int> rowIndices;

  /// Row `IX`es explicitly deleted on this (instance) section via `Del="1"`;
  /// they remove the same-IX row inherited from the master.
  final Set<int> deletedRowIndices;

  /// Which of the section flag cells (NoFill/NoLine/NoShow/NoSnap/NoQuickDrag)
  /// were explicitly present, so a master merge only overrides flags the
  /// instance actually declared (others inherit from the master).
  final Set<String> definedFlagCells;

  /// `<Section N="Geometry" IX="N" Del="1"/>` — the instance deletes the whole
  /// inherited geometry section.
  final bool deleted;

  /// Formulas for command index [i], or an empty map.
  Map<String, String> formulasAt(int i) =>
      i >= 0 && i < commandFormulas.length
          ? commandFormulas[i]
          : const <String, String>{};

  VsdxGeometry copyWith({
    List<VsdxPathCommand>? commands,
    List<Map<String, String>>? commandFormulas,
    bool? noFill,
    bool? noLine,
    bool? noShow,
    bool? noSnap,
    bool? noQuickDrag,
    int? ix,
    List<int>? rowIndices,
    Set<int>? deletedRowIndices,
    Set<String>? definedFlagCells,
    bool? deleted,
  }) =>
      VsdxGeometry(
        commands: commands ?? this.commands,
        commandFormulas: commandFormulas ?? this.commandFormulas,
        noFill: noFill ?? this.noFill,
        noLine: noLine ?? this.noLine,
        noShow: noShow ?? this.noShow,
        noSnap: noSnap ?? this.noSnap,
        noQuickDrag: noQuickDrag ?? this.noQuickDrag,
        ix: ix ?? this.ix,
        rowIndices: rowIndices ?? this.rowIndices,
        deletedRowIndices: deletedRowIndices ?? this.deletedRowIndices,
        definedFlagCells: definedFlagCells ?? this.definedFlagCells,
        deleted: deleted ?? this.deleted,
      );

  @override
  String toString() =>
      'VsdxGeometry(${commands.length} cmd'
      '${noFill ? ' NoFill' : ''}'
      '${noLine ? ' NoLine' : ''}'
      '${noShow ? ' NoShow' : ''}'
      '${noSnap ? ' NoSnap' : ''}'
      '${noQuickDrag ? ' NoQuickDrag' : ''})';
}
