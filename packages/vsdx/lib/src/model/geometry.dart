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
  });

  /// End point of the polyline (after the last interior vertex).
  final double x;
  final double y;

  /// Interior vertices, in (x, y) pairs (shape-local inches). Excludes the
  /// shape's current pen position (the implicit P0) and the end point
  /// [x]/[y] (the implicit Pn).
  final List<Offset2D> vertices;

  @override
  String toString() =>
      'PolylineTo($x, $y, ${vertices.length} verts)';
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
  });
  final double x;
  final double y;
  final double a;
  final double b;
  @override
  String toString() => 'InfiniteLine(p=($x,$y), q=($a,$b))';
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

  @override
  String toString() => 'SplineStart($x, $y, degree=$degree)';
}

/// `SplineKnot` — subsequent control point in a spline that began with
/// [SplineStart]. Interpreted as a polyline vertex by the path builder.
@immutable
class SplineKnot extends VsdxPathCommand {
  const SplineKnot({required this.x, required this.y, required this.knot});
  final double x;
  final double y;

  /// The knot value (`A` cell).
  final double knot;

  @override
  String toString() => 'SplineKnot($x, $y, knot=$knot)';
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

  @override
  String toString() =>
      'NurbsTo($x, $y, ${controlPoints.length} cps, deg=$degree)';
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
    case ArcTo(:final x, :final y, :final bow):
      return ArcTo(x: x * sx, y: y * sy, bow: bow * (sx + sy) / 2);
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
    case PolylineTo(:final x, :final y, :final vertices):
      return PolylineTo(
        x: x * sx,
        y: y * sy,
        vertices: <Offset2D>[
          for (final v in vertices) Offset2D(v.x * sx, v.y * sy),
        ],
      );
    case InfiniteLineCmd(:final x, :final y, :final a, :final b):
      return InfiniteLineCmd(x: x * sx, y: y * sy, a: a * sx, b: b * sy);
    case SplineStart(:final x, :final y, :final a, :final b, :final c, :final degree):
      return SplineStart(x: x * sx, y: y * sy, a: a, b: b, c: c, degree: degree);
    case SplineKnot(:final x, :final y, :final knot):
      return SplineKnot(x: x * sx, y: y * sy, knot: knot);
    case NurbsTo(
        :final x,
        :final y,
        :final controlPoints,
        :final weights,
        :final knots,
        :final degree,
      ):
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
    this.noFill = false,
    this.noLine = false,
    this.noShow = false,
  });

  /// Path commands in source order.
  final List<VsdxPathCommand> commands;

  /// `<Cell N="NoFill" V="1"/>` — suppress fill for this geometry only.
  final bool noFill;
  final bool noLine;

  /// `<Cell N="NoShow" V="1"/>` — don't draw at all (still hit-tests).
  final bool noShow;

  @override
  String toString() =>
      'VsdxGeometry(${commands.length} cmd'
      '${noFill ? ' NoFill' : ''}'
      '${noLine ? ' NoLine' : ''}'
      '${noShow ? ' NoShow' : ''})';
}
