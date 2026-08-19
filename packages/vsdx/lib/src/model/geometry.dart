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

import 'dart:math' as math;

import 'package:meta/meta.dart';

@immutable
sealed class VsdxPathCommand {
  const VsdxPathCommand();
}

bool _sameOffsets(List<Offset2D> a, List<Offset2D> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameDoubles(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Structural equality for geometry commands. Prefer this over [Object.toString]
/// — some commands (e.g. [PolylineTo]) omit vertex data from their debug string.
bool pathCommandsEqual(VsdxPathCommand a, VsdxPathCommand b) {
  if (identical(a, b)) return true;
  return switch ((a, b)) {
    (MoveTo(:final x, :final y), MoveTo(x: final ox, y: final oy)) =>
      x == ox && y == oy,
    (LineTo(:final x, :final y), LineTo(x: final ox, y: final oy)) =>
      x == ox && y == oy,
    (RelMoveTo(:final fx, :final fy), RelMoveTo(fx: final ox, fy: final oy)) =>
      fx == ox && fy == oy,
    (RelLineTo(:final fx, :final fy), RelLineTo(fx: final ox, fy: final oy)) =>
      fx == ox && fy == oy,
    (
      CubBezTo(
        :final x,
        :final y,
        :final x1,
        :final y1,
        :final x2,
        :final y2,
      ),
      CubBezTo(
        x: final ox,
        y: final oy,
        x1: final ox1,
        y1: final oy1,
        x2: final ox2,
        y2: final oy2,
      ),
    ) =>
      x == ox &&
          y == oy &&
          x1 == ox1 &&
          y1 == oy1 &&
          x2 == ox2 &&
          y2 == oy2,
    (
      RelCubBezTo(
        :final fx,
        :final fy,
        :final fx1,
        :final fy1,
        :final fx2,
        :final fy2,
      ),
      RelCubBezTo(
        fx: final ox,
        fy: final oy,
        fx1: final ox1,
        fy1: final oy1,
        fx2: final ox2,
        fy2: final oy2,
      ),
    ) =>
      fx == ox &&
          fy == oy &&
          fx1 == ox1 &&
          fy1 == oy1 &&
          fx2 == ox2 &&
          fy2 == oy2,
    (
      QuadBezTo(:final x, :final y, :final x1, :final y1),
      QuadBezTo(x: final ox, y: final oy, x1: final ox1, y1: final oy1),
    ) =>
      x == ox && y == oy && x1 == ox1 && y1 == oy1,
    (
      RelQuadBezTo(:final fx, :final fy, :final fx1, :final fy1),
      RelQuadBezTo(fx: final ox, fy: final oy, fx1: final ox1, fy1: final oy1),
    ) =>
      fx == ox && fy == oy && fx1 == ox1 && fy1 == oy1,
    (
      ArcTo(:final x, :final y, :final bow),
      ArcTo(x: final ox, y: final oy, bow: final ob),
    ) =>
      x == ox && y == oy && bow == ob,
    (
      RelArcTo(:final fx, :final fy, :final fbow),
      RelArcTo(fx: final ox, fy: final oy, fbow: final ob),
    ) =>
      fx == ox && fy == oy && fbow == ob,
    (
      EllipticalArcTo(
        :final x,
        :final y,
        :final controlX,
        :final controlY,
        :final angle,
        :final eccentricity,
      ),
      EllipticalArcTo(
        x: final ox,
        y: final oy,
        controlX: final ocx,
        controlY: final ocy,
        angle: final oa,
        eccentricity: final oe,
      ),
    ) =>
      x == ox &&
          y == oy &&
          controlX == ocx &&
          controlY == ocy &&
          angle == oa &&
          eccentricity == oe,
    (
      RelEllipticalArcTo(
        :final fx,
        :final fy,
        :final fcx,
        :final fcy,
        :final angle,
        :final eccentricity,
      ),
      RelEllipticalArcTo(
        fx: final ox,
        fy: final oy,
        fcx: final ocx,
        fcy: final ocy,
        angle: final oa,
        eccentricity: final oe,
      ),
    ) =>
      fx == ox &&
          fy == oy &&
          fcx == ocx &&
          fcy == ocy &&
          angle == oa &&
          eccentricity == oe,
    (
      EllipseCmd(
        :final cx,
        :final cy,
        :final aX,
        :final aY,
        :final bX,
        :final bY,
      ),
      EllipseCmd(
        cx: final ocx,
        cy: final ocy,
        aX: final oax,
        aY: final oay,
        bX: final obx,
        bY: final oby,
      ),
    ) =>
      cx == ocx &&
          cy == ocy &&
          aX == oax &&
          aY == oay &&
          bX == obx &&
          bY == oby,
    (
      PolylineTo(
        :final x,
        :final y,
        :final vertices,
        :final relative,
        :final vertsRelative,
        :final vertsYRelative,
      ),
      PolylineTo(
        x: final ox,
        y: final oy,
        vertices: final ov,
        relative: final or,
        vertsRelative: final ovr,
        vertsYRelative: final ovyr,
      ),
    ) =>
      x == ox &&
          y == oy &&
          relative == or &&
          vertsRelative == ovr &&
          vertsYRelative == ovyr &&
          _sameOffsets(vertices, ov),
    (
      InfiniteLineCmd(
        :final x,
        :final y,
        :final a,
        :final b,
        :final relative,
      ),
      InfiniteLineCmd(
        x: final ox,
        y: final oy,
        a: final oa,
        b: final ob,
        relative: final or,
      ),
    ) =>
      x == ox && y == oy && a == oa && b == ob && relative == or,
    (
      SplineStart(
        :final x,
        :final y,
        :final a,
        :final b,
        :final c,
        :final degree,
        :final relative,
      ),
      SplineStart(
        x: final ox,
        y: final oy,
        a: final oa,
        b: final ob,
        c: final oc,
        degree: final od,
        relative: final or,
      ),
    ) =>
      x == ox &&
          y == oy &&
          a == oa &&
          b == ob &&
          c == oc &&
          degree == od &&
          relative == or,
    (
      SplineKnot(:final x, :final y, :final knot, :final relative),
      SplineKnot(x: final ox, y: final oy, knot: final ok, relative: final or),
    ) =>
      x == ox && y == oy && knot == ok && relative == or,
    (
      NurbsTo(
        :final x,
        :final y,
        :final controlPoints,
        :final weights,
        :final knots,
        :final degree,
        :final relative,
        :final cpRelative,
        :final cpYRelative,
      ),
      NurbsTo(
        x: final ox,
        y: final oy,
        controlPoints: final ocp,
        weights: final ow,
        knots: final ok,
        degree: final od,
        relative: final or,
        cpRelative: final ocr,
        cpYRelative: final ocyr,
      ),
    ) =>
      x == ox &&
          y == oy &&
          degree == od &&
          relative == or &&
          cpRelative == ocr &&
          cpYRelative == ocyr &&
          _sameOffsets(controlPoints, ocp) &&
          _sameDoubles(weights, ow) &&
          _sameDoubles(knots, ok),
    _ => false,
  };
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
/// from the chord, MS-VSDX §"ArcTo Row"). In native Y-up shape coordinates,
/// positive bow lies on the chord's right side, matching libvisio's
/// `sweep = (bow < 0)` conversion.
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
/// Render / SVG / perimeter sample a true ellipse from [angle] and
/// [eccentricity] (see `elliptical_arc.dart`), not a quadratic Bézier.
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

/// The path emitted by libvisio when an [EllipseCmd] has a zero-length axis.
///
/// `VSDContentCollector::collectEllipse` always emits `M A`, an arc to B,
/// an arc back to A, and `Z`. SVG defines an arc with either radius equal to
/// zero as a straight line, so the visible fallback is `A → B → A`. Returns
/// `null` for a non-degenerate ellipse and an empty list for non-finite data.
List<Offset2D>? visioDegenerateEllipsePath(EllipseCmd ellipse) {
  final ax = ellipse.aX - ellipse.cx;
  final ay = ellipse.aY - ellipse.cy;
  final bx = ellipse.bX - ellipse.cx;
  final by = ellipse.bY - ellipse.cy;
  final aLength2 = ax * ax + ay * ay;
  final bLength2 = bx * bx + by * by;
  if (!aLength2.isFinite || !bLength2.isFinite) return const <Offset2D>[];
  if (aLength2 != 0 && bLength2 != 0) return null;
  final a = Offset2D(ellipse.aX, ellipse.aY);
  final b = Offset2D(ellipse.bX, ellipse.bY);
  return <Offset2D>[a, b, a];
}

/// `PolylineTo` — Visio packs the polyline data inside a `POLYLINE(...)`
/// formula on the `A` cell:
///   `POLYLINE(xType, yType, x0,y0, x1,y1, …, xN,yN)`
/// [xType]/[yType] are 0 = % of Width/Height or 1 = local inches. The
/// `X`/`Y` cells give the polyline's end point (cursor advance).
///
/// MS-VSDX §"PolylineTo Row".
@immutable
class PolylineTo extends VsdxPathCommand {
  const PolylineTo({
    required this.x,
    required this.y,
    required this.vertices,
    this.relative = false,
    this.vertsRelative = false,
    bool? vertsYRelative,
  }) : vertsYRelative = vertsYRelative ?? vertsRelative;

  /// End point of the polyline (after the last interior vertex).
  final double x;
  final double y;

  /// Interior vertices from `POLYLINE(...)`. Excludes pen start and [x]/[y].
  /// X is a fraction of Width when [vertsRelative]; Y is a fraction of Height
  /// when [vertsYRelative]. Independent of [relative] (Rel* only affects X/Y).
  final List<Offset2D> vertices;

  /// `true` when the row was `RelPolylineTo` (endpoint X/Y are fractions).
  final bool relative;

  /// `true` when `POLYLINE` xType is 0 (X verts are % of Width).
  final bool vertsRelative;

  /// `true` when `POLYLINE` yType is 0 (Y verts are % of Height).
  /// Defaults to [vertsRelative] when omitted (symmetric formulas).
  final bool vertsYRelative;

  @override
  String toString() =>
      '${relative ? 'Rel' : ''}PolylineTo($x, $y, '
      'verts=$vertices, xRel=$vertsRelative, yRel=$vertsYRelative)';
}

/// Clip the infinite line through [p] and [q] to a Visio page rectangle.
///
/// This mirrors libvisio `VSDContentCollector::collectInfiniteLine`: vertical
/// and horizontal lines span the corresponding page dimension; other lines
/// use their first and last intersections with the four page borders. A line
/// that misses the page, is degenerate, or contains non-finite coordinates
/// returns `null`.
List<Offset2D>? clipInfiniteLineToPage(
  Offset2D p,
  Offset2D q, {
  required double pageWidth,
  required double pageHeight,
}) {
  if (!p.x.isFinite ||
      !p.y.isFinite ||
      !q.x.isFinite ||
      !q.y.isFinite ||
      !pageWidth.isFinite ||
      !pageHeight.isFinite ||
      pageWidth < 0 ||
      pageHeight < 0) {
    return null;
  }
  const epsilon = 1e-10;
  final dx = q.x - p.x;
  final dy = q.y - p.y;
  if (dx.abs() <= epsilon && dy.abs() <= epsilon) return null;
  if (dx.abs() <= epsilon) {
    return <Offset2D>[
      Offset2D(p.x, 0),
      Offset2D(p.x, pageHeight),
    ];
  }
  if (dy.abs() <= epsilon) {
    return <Offset2D>[
      Offset2D(0, p.y),
      Offset2D(pageWidth, p.y),
    ];
  }

  final slope = dy / dx;
  final intercept = p.y - slope * p.x;
  final intersections = <Offset2D>[];

  void add(double x, double y) {
    if (!x.isFinite || !y.isFinite) return;
    if (x < -epsilon ||
        x > pageWidth + epsilon ||
        y < -epsilon ||
        y > pageHeight + epsilon) {
      return;
    }
    final point = Offset2D(
      x.clamp(0.0, pageWidth),
      y.clamp(0.0, pageHeight),
    );
    if (intersections.any(
      (other) =>
          (other.x - point.x).abs() <= epsilon &&
          (other.y - point.y).abs() <= epsilon,
    )) {
      return;
    }
    intersections.add(point);
  }

  add(0, intercept);
  add(pageWidth, slope * pageWidth + intercept);
  add(-intercept / slope, 0);
  add((pageHeight - intercept) / slope, pageHeight);
  if (intersections.length < 2) return null;
  intersections.sort((a, b) {
    final byX = a.x.compareTo(b.x);
    return byX != 0 ? byX : a.y.compareTo(b.y);
  });
  return <Offset2D>[intersections.first, intersections.last];
}

/// `InfiniteLine` — a straight line passing through (`x`, `y`) with the
/// direction implied by (`a`, `b`). Rendering clips it to the Visio page.
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

/// `SplineStart` — second control point of a B-spline that continues via
/// [SplineKnot] rows. MS-VSDX §"SplineStart Row".
///
/// The preceding geometry row supplies the first control point (pen).
/// Sampling assembles a NURBS like libvisio (`sampleVisioSpline`).
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

  /// Second knot (`A` cell).
  final double a;

  /// First knot (`B` cell).
  final double b;

  /// Last knot (`C` cell).
  final double c;

  /// Spline degree (`D` cell, typically 3).
  final int degree;

  final bool relative;

  @override
  String toString() =>
      '${relative ? 'Rel' : ''}SplineStart($x, $y, a=$a, b=$b, c=$c, '
      'degree=$degree)';
}

/// `SplineKnot` — subsequent control point / knot in a spline that began
/// with [SplineStart].
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
    this.cpRelative = false,
    bool? cpYRelative,
  }) : cpYRelative = cpYRelative ?? cpRelative;

  /// Final endpoint of the NURBS arc (X/Y cells).
  final double x;
  final double y;

  /// Interior control points from the `NURBS(...)` formula (excludes pen
  /// start and the X/Y endpoint).
  final List<Offset2D> controlPoints;

  /// Weights assembled like libvisio: `[D, …E weights…, B]` when A/B/C/D
  /// were present, otherwise interior-only from E. Empty ⇒ all 1.0.
  final List<double> weights;

  /// Knots assembled like libvisio: `[C, …E knots…, A, knotLast]` when
  /// A/B/C/D were present. Empty ⇒ uniform clamped.
  final List<double> knots;

  final int degree;

  /// `true` when the row was `RelNURBSTo` (endpoint X/Y are fractions).
  final bool relative;

  /// `true` when the NURBS formula has xType == 0 (CP X is % of Width).
  /// Independent of [relative] (Rel* only affects the endpoint).
  final bool cpRelative;

  /// `true` when the NURBS formula has yType == 0 (CP Y is % of Height).
  /// Defaults to [cpRelative] when omitted (symmetric formulas).
  final bool cpYRelative;

  @override
  String toString() =>
      '${relative ? 'Rel' : ''}NurbsTo($x, $y, cps=$controlPoints, '
      'w=$weights, k=$knots, deg=$degree, '
      'xRel=$cpRelative, yRel=$cpYRelative)';
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
    case PolylineTo(
        :final x,
        :final y,
        :final vertices,
        :final relative,
        :final vertsRelative,
        :final vertsYRelative,
      ):
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
        vertsRelative: vertsRelative,
        vertsYRelative: vertsYRelative,
      );
    case RelEllipticalArcTo(
        :final fx,
        :final fy,
        :final fcx,
        :final fcy,
        :final angle,
        :final eccentricity,
      ):
      // Fractional X/Y/A/B stay as-is; C (angle) / D (ecc) often carry F=.
      final nc = cell('C');
      final nd = cell('D');
      if (nc == null && nd == null) return cmd;
      return RelEllipticalArcTo(
        fx: fx,
        fy: fy,
        fcx: fcx,
        fcy: fcy,
        angle: nc ?? angle,
        eccentricity: nd ?? eccentricity,
      );
    case RelMoveTo():
    case RelLineTo():
    case RelCubBezTo():
    case RelQuadBezTo():
    case RelArcTo():
      return cmd;
    case SplineStart(
        :final x,
        :final y,
        :final a,
        :final b,
        :final c,
        :final degree,
        :final relative,
      ):
      if (relative) return cmd;
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
      return SplineStart(
        x: nx ?? x,
        y: ny ?? y,
        a: na ?? a,
        b: nb ?? b,
        c: nc ?? c,
        degree: nd?.toInt() ?? degree,
      );
    case SplineKnot(:final x, :final y, :final knot, :final relative):
      if (relative) return cmd;
      final nx = cell('X');
      final ny = cell('Y');
      final na = cell('A');
      if (nx == null && ny == null && na == null) return cmd;
      return SplineKnot(
        x: nx ?? x,
        y: ny ?? y,
        knot: na ?? knot,
      );
    case NurbsTo(
        :final x,
        :final y,
        :final controlPoints,
        :final weights,
        :final knots,
        :final degree,
        :final relative,
        :final cpRelative,
        :final cpYRelative,
      ):
      if (relative) return cmd;
      final nx = cell('X');
      final ny = cell('Y');
      if (nx == null && ny == null) return cmd;
      return NurbsTo(
        x: nx ?? x,
        y: ny ?? y,
        controlPoints: controlPoints,
        weights: weights,
        knots: knots,
        degree: degree,
        relative: relative,
        cpRelative: cpRelative,
        cpYRelative: cpYRelative,
      );
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
    case RelEllipticalArcTo(
        :final fx,
        :final fy,
        :final fcx,
        :final fcy,
        :final angle,
        :final eccentricity,
      ):
      // Fractions stay; angle/ecc are absolute and must track non-uniform scale.
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      final majorScale =
          math.sqrt(sx * sx * cosA * cosA + sy * sy * sinA * sinA);
      final minorScale =
          math.sqrt(sx * sx * sinA * sinA + sy * sy * cosA * cosA);
      final eccScale = minorScale < 1e-12 ? 1.0 : majorScale / minorScale;
      return RelEllipticalArcTo(
        fx: fx,
        fy: fy,
        fcx: fcx,
        fcy: fcy,
        angle: math.atan2(sy * sinA, sx * cosA),
        eccentricity: eccentricity * eccScale,
      );
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
      // Non-uniform scale stretches the ellipse axes: update major-axis
      // angle and a/b eccentricity so Visio/Edraw match the new box.
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      final majorScale =
          math.sqrt(sx * sx * cosA * cosA + sy * sy * sinA * sinA);
      final minorScale =
          math.sqrt(sx * sx * sinA * sinA + sy * sy * cosA * cosA);
      final eccScale = minorScale < 1e-12 ? 1.0 : majorScale / minorScale;
      return EllipticalArcTo(
        x: x * sx,
        y: y * sy,
        controlX: controlX * sx,
        controlY: controlY * sy,
        angle: math.atan2(sy * sinA, sx * cosA),
        eccentricity: eccentricity * eccScale,
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
    case PolylineTo(
        :final x,
        :final y,
        :final vertices,
        :final relative,
        :final vertsRelative,
        :final vertsYRelative,
      ):
      // Rel* endpoint stays fractional; formula-% axes stay fractional;
      // scale only local-inch components.
      final scaledVerts = (vertsRelative && vertsYRelative)
          ? vertices
          : <Offset2D>[
              for (final v in vertices)
                Offset2D(
                  vertsRelative ? v.x : v.x * sx,
                  vertsYRelative ? v.y : v.y * sy,
                ),
            ];
      return PolylineTo(
        x: relative ? x : x * sx,
        y: relative ? y : y * sy,
        vertices: scaledVerts,
        relative: relative,
        vertsRelative: vertsRelative,
        vertsYRelative: vertsYRelative,
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
        :final cpRelative,
        :final cpYRelative,
      ):
      // Rel* endpoint stays fractional; formula-% CPs stay fractional.
      final scaledCps = (cpRelative && cpYRelative)
          ? controlPoints
          : <Offset2D>[
              for (final p in controlPoints)
                Offset2D(
                  cpRelative ? p.x : p.x * sx,
                  cpYRelative ? p.y : p.y * sy,
                ),
            ];
      return NurbsTo(
        x: relative ? x : x * sx,
        y: relative ? y : y * sy,
        controlPoints: scaledCps,
        weights: weights,
        knots: knots,
        degree: degree,
        relative: relative,
        cpRelative: cpRelative,
        cpYRelative: cpYRelative,
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
    this.hitBox = false,
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

  /// Invisible selection frame (annotation / parallel-mode). Not a VSDX cell —
  /// in-memory only so [syncGeometryNoLine] can restore strokes without
  /// painting a box around hollow hit-test geometry.
  final bool hitBox;

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
    bool? hitBox,
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
        hitBox: hitBox ?? this.hitBox,
        ix: ix ?? this.ix,
        rowIndices: rowIndices ?? this.rowIndices,
        deletedRowIndices: deletedRowIndices ?? this.deletedRowIndices,
        definedFlagCells: definedFlagCells ?? this.definedFlagCells,
        deleted: deleted ?? this.deleted,
      );

  /// Flatten MoveTo / LineTo / PolylineTo (and Rel* variants) into shape-local
  /// vertices. Returns `null` when any other command is present (arcs, beziers).
  List<Offset2D>? polylineVertices({
    required double widthInches,
    required double heightInches,
  }) {
    final w = widthInches;
    final h = heightInches;
    final pts = <Offset2D>[];
    for (final c in commands) {
      switch (c) {
        case MoveTo(:final x, :final y):
          pts.add(Offset2D(x, y));
        case LineTo(:final x, :final y):
          pts.add(Offset2D(x, y));
        case RelMoveTo(:final fx, :final fy):
          pts.add(Offset2D(fx * w, fy * h));
        case RelLineTo(:final fx, :final fy):
          pts.add(Offset2D(fx * w, fy * h));
        case PolylineTo(
            :final x,
            :final y,
            :final vertices,
            :final relative,
            :final vertsRelative,
            :final vertsYRelative,
          ):
          final vsx = vertsRelative ? w : 1.0;
          final vsy = vertsYRelative ? h : 1.0;
          final esx = relative ? w : 1.0;
          final esy = relative ? h : 1.0;
          for (final v in vertices) {
            pts.add(Offset2D(v.x * vsx, v.y * vsy));
          }
          pts.add(Offset2D(x * esx, y * esy));
        default:
          return null;
      }
    }
    return pts.length >= 2 ? pts : null;
  }

  @override
  String toString() =>
      'VsdxGeometry(${commands.length} cmd'
      '${noFill ? ' NoFill' : ''}'
      '${noLine ? ' NoLine' : ''}'
      '${noShow ? ' NoShow' : ''}'
      '${noSnap ? ' NoSnap' : ''}'
      '${noQuickDrag ? ' NoQuickDrag' : ''})';
}

/// Sync Geometry NoFill without wiping decorative hollow segments on
/// multi-geometry shapes (e.g. doubleRectangle inner ring stays NoFill).
///
/// - [hollow] true → all geoms NoFill.
/// - [hollow] false → only restore when fully hollowed; re-enable the first
///   non-hit-box fill path and keep later NoFill decorations. When a hit-box
///   frame precedes stroke-only geoms (annotation / parallel mode), keep
///   every geom NoFill so restoring fill cannot paint the selection rectangle.
List<VsdxGeometry> syncGeometryNoFill(
  List<VsdxGeometry> geos, {
  required bool hollow,
}) {
  if (geos.isEmpty) return geos;
  if (hollow) {
    final tagged = tagStructuralHitBoxes(geos);
    return [for (final g in tagged) g.copyWith(noFill: true)];
  }
  if (!geos.every((g) => g.noFill)) return geos;
  final primary = geos.indexWhere((g) => !g.hitBox);
  // Only hit-boxes, or hit-box + stroke decorations: never paint the invisible
  // selection frame (annotation / parallel / picture silhouette).
  if (primary != 0) {
    return [for (final g in geos) g.copyWith(noFill: true)];
  }
  return [
    for (var i = 0; i < geos.length; i++)
      geos[i].copyWith(noFill: i == 0 ? false : true),
  ];
}

/// Mark structural hit-boxes: geoms that already have NoLine while siblings
/// still stroke. Used after parse and before [syncGeometryNoLine] hollows all.
List<VsdxGeometry> tagStructuralHitBoxes(List<VsdxGeometry> geos) {
  if (geos.length < 2) return geos;
  final mixed = geos.any((g) => g.noLine) && geos.any((g) => !g.noLine);
  if (!mixed) return geos;
  return [
    for (final g in geos) g.noLine ? g.copyWith(hitBox: true) : g,
  ];
}

/// Sync Geometry NoLine without painting hit-box frames (annotation brackets).
///
/// - [hollow] true → all geoms NoLine (preserving [VsdxGeometry.hitBox]).
/// - [hollow] false → only restore when fully NoLine'd; re-enable strokes on
///   non-hit-box geoms so invisible selection frames stay NoLine.
List<VsdxGeometry> syncGeometryNoLine(
  List<VsdxGeometry> geos, {
  required bool hollow,
}) {
  if (geos.isEmpty) return geos;
  if (hollow) {
    final tagged = tagStructuralHitBoxes(geos);
    return [for (final g in tagged) g.copyWith(noLine: true)];
  }
  if (!geos.every((g) => g.noLine)) return geos;
  return [for (final g in geos) g.copyWith(noLine: g.hitBox)];
}

/// Copy section flags from [prior] onto freshly rebuilt [fresh] paths so
/// layout/resize regenerations do not drop NoFill/NoLine (Edraw export).
List<VsdxGeometry> preserveGeometryFlags(
  List<VsdxGeometry> fresh,
  List<VsdxGeometry> prior,
) {
  if (fresh.isEmpty || prior.isEmpty) return fresh;
  return <VsdxGeometry>[
    for (var i = 0; i < fresh.length; i++)
      fresh[i].copyWith(
        noFill: i < prior.length ? prior[i].noFill : fresh[i].noFill,
        noLine: i < prior.length ? prior[i].noLine : fresh[i].noLine,
        noShow: i < prior.length ? prior[i].noShow : fresh[i].noShow,
        noSnap: i < prior.length ? prior[i].noSnap : fresh[i].noSnap,
        noQuickDrag:
            i < prior.length ? prior[i].noQuickDrag : fresh[i].noQuickDrag,
        hitBox: i < prior.length ? prior[i].hitBox : fresh[i].hitBox,
      ),
  ];
}

double _axisFraction(double value, double span) =>
    span.abs() < 1e-12 ? 0.0 : value / span;

/// Whether [cmd] is a VSDX row type LibreOffice's libvisio importer drops.
///
/// `VSDXParser::getElementToken` maps `Row T=` through `tokens.txt`. That
/// table has RelCubBezTo / RelQuadBezTo / ArcTo / PolylineTo / InfiniteLine /
/// SplineStart / SplineKnot / NURBSTo, but not CubBezTo, QuadBezTo, RelArcTo,
/// RelPolylineTo, RelInfiniteLine, RelSpline* or RelNURBSTo. Those rows are
/// skipped in `readGeometry`'s default branch, so a save that keeps the
/// original `T=` looks empty in Draw.
bool commandNeedsLibvisioRewrite(VsdxPathCommand cmd) => switch (cmd) {
      CubBezTo() || QuadBezTo() || RelArcTo() => true,
      PolylineTo(:final relative) => relative,
      InfiniteLineCmd(:final relative) => relative,
      SplineStart(:final relative) => relative,
      SplineKnot(:final relative) => relative,
      NurbsTo(:final relative) => relative,
      _ => false,
    };

/// Map [cmd] onto a row type libvisio collects, baking Rel* endpoints into
/// local inches (or CubBezTo/QuadBezTo into Rel*) at the current [width] /
/// [height]. Appearance at this size is preserved; LibreOffice can then
/// draw the path.
VsdxPathCommand forLibvisioWrite(
  VsdxPathCommand cmd, {
  required double width,
  required double height,
}) {
  final w = width;
  final h = height;
  switch (cmd) {
    case CubBezTo(
        :final x,
        :final y,
        :final x1,
        :final y1,
        :final x2,
        :final y2,
      ):
      return RelCubBezTo(
        fx: _axisFraction(x, w),
        fy: _axisFraction(y, h),
        fx1: _axisFraction(x1, w),
        fy1: _axisFraction(y1, h),
        fx2: _axisFraction(x2, w),
        fy2: _axisFraction(y2, h),
      );
    case QuadBezTo(:final x, :final y, :final x1, :final y1):
      return RelQuadBezTo(
        fx: _axisFraction(x, w),
        fy: _axisFraction(y, h),
        fx1: _axisFraction(x1, w),
        fy1: _axisFraction(y1, h),
      );
    case RelArcTo(:final fx, :final fy, :final fbow):
      // Same bow scaling the SVG / canvas path builders use.
      return ArcTo(x: fx * w, y: fy * h, bow: fbow * (w + h) / 2);
    case PolylineTo(
        :final x,
        :final y,
        :final vertices,
        :final relative,
        :final vertsRelative,
        :final vertsYRelative,
      ) when relative:
      return PolylineTo(
        x: x * w,
        y: y * h,
        vertices: vertices,
        vertsRelative: vertsRelative,
        vertsYRelative: vertsYRelative,
      );
    case InfiniteLineCmd(
        :final x,
        :final y,
        :final a,
        :final b,
        :final relative,
      ) when relative:
      return InfiniteLineCmd(x: x * w, y: y * h, a: a * w, b: b * h);
    case SplineStart(
        :final x,
        :final y,
        :final a,
        :final b,
        :final c,
        :final degree,
        :final relative,
      ) when relative:
      return SplineStart(
        x: x * w,
        y: y * h,
        a: a,
        b: b,
        c: c,
        degree: degree,
      );
    case SplineKnot(:final x, :final y, :final knot, :final relative)
        when relative:
      return SplineKnot(x: x * w, y: y * h, knot: knot);
    case NurbsTo(
        :final x,
        :final y,
        :final controlPoints,
        :final weights,
        :final knots,
        :final degree,
        :final relative,
        :final cpRelative,
        :final cpYRelative,
      ) when relative:
      return NurbsTo(
        x: x * w,
        y: y * h,
        controlPoints: controlPoints,
        weights: weights,
        knots: knots,
        degree: degree,
        cpRelative: cpRelative,
        cpYRelative: cpYRelative,
      );
    default:
      return cmd;
  }
}
