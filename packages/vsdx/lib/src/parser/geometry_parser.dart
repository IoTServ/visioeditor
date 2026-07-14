/// Parses every `<Section N="Geometry">` block of a shape into one
/// [VsdxGeometry] per section.
///
/// M3-01 scope (the row types overwhelmingly used by real-world VSDX):
///
///  | Row `T=`            | Command          |
///  |---------------------|------------------|
///  | `MoveTo`            | [MoveTo]         |
///  | `LineTo`            | [LineTo]         |
///  | `RelMoveTo`         | [RelMoveTo]      |
///  | `RelLineTo`         | [RelLineTo]      |
///  | `ArcTo` / `RelArcTo`| [ArcTo]          |
///  | `Ellipse`           | [EllipseCmd]     |
///
/// More exotic rows (`EllipticalArcTo`, `NURBSTo`, `SplineKnot`,
/// `PolylineTo`, `InfiniteLine`) are intentionally **dropped with a log
/// warning** for now — they show up in M3-02 next.
library;

import 'package:logging/logging.dart';
import 'package:xml/xml.dart';

import '../model/geometry.dart';
import 'cell_helpers.dart';

final _log = Logger('vsdx.parser.geometry');

class GeometryParser {
  const GeometryParser();

  /// Returns one [VsdxGeometry] per `Geometry` section found directly under
  /// [shape] (no recursion into sub-shapes).
  List<VsdxGeometry> parse(XmlElement shape) {
    final out = <VsdxGeometry>[];
    for (final el in shape.childElements) {
      if (el.name.local != 'Section') continue;
      if (el.getAttribute('N') != 'Geometry') continue;
      out.add(_readSection(el));
    }
    return out;
  }

  VsdxGeometry _readSection(XmlElement section) {
    final commands = <VsdxPathCommand>[];
    var noFill = false;
    var noLine = false;
    var noShow = false;

    for (final child in section.childElements) {
      switch (child.name.local) {
        case 'Cell':
          final n = child.getAttribute('N');
          final v = child.getAttribute('V');
          switch (n) {
            case 'NoFill':
              noFill = v == '1';
            case 'NoLine':
              noLine = v == '1';
            case 'NoShow':
              noShow = v == '1';
          }
        case 'Row':
          final cmd = _readRow(child);
          if (cmd != null) commands.add(cmd);
      }
    }
    return VsdxGeometry(
      commands: List.unmodifiable(commands),
      noFill: noFill,
      noLine: noLine,
      noShow: noShow,
    );
  }

  VsdxPathCommand? _readRow(XmlElement row) {
    final t = row.getAttribute('T');
    switch (t) {
      case 'MoveTo':
        return MoveTo(
          readLengthInches(row, 'X') ?? 0,
          readLengthInches(row, 'Y') ?? 0,
        );
      case 'LineTo':
        return LineTo(
          readLengthInches(row, 'X') ?? 0,
          readLengthInches(row, 'Y') ?? 0,
        );
      case 'RelMoveTo':
        return RelMoveTo(
          _rawDouble(row, 'X') ?? 0,
          _rawDouble(row, 'Y') ?? 0,
        );
      case 'RelLineTo':
        return RelLineTo(
          _rawDouble(row, 'X') ?? 0,
          _rawDouble(row, 'Y') ?? 0,
        );
      case 'CubBezTo':
        // Absolute cubic Bézier: A/B = control 1, C/D = control 2, X/Y = end,
        // all in shape-local inches.
        return CubBezTo(
          x: readLengthInches(row, 'X') ?? 0,
          y: readLengthInches(row, 'Y') ?? 0,
          x1: readLengthInches(row, 'A') ?? 0,
          y1: readLengthInches(row, 'B') ?? 0,
          x2: readLengthInches(row, 'C') ?? 0,
          y2: readLengthInches(row, 'D') ?? 0,
        );
      case 'RelCubBezTo':
        // Relative cubic Bézier: every coordinate is a fraction of the shape's
        // width (X/A/C) or height (Y/B/D), so read the raw V without unit
        // normalisation (like RelMoveTo / RelLineTo).
        return RelCubBezTo(
          fx: _rawDouble(row, 'X') ?? 0,
          fy: _rawDouble(row, 'Y') ?? 0,
          fx1: _rawDouble(row, 'A') ?? 0,
          fy1: _rawDouble(row, 'B') ?? 0,
          fx2: _rawDouble(row, 'C') ?? 0,
          fy2: _rawDouble(row, 'D') ?? 0,
        );
      case 'ArcTo':
      case 'RelArcTo':
        return ArcTo(
          x: readLengthInches(row, 'X') ?? 0,
          y: readLengthInches(row, 'Y') ?? 0,
          bow: readLengthInches(row, 'A') ?? 0,
        );
      case 'EllipticalArcTo':
      case 'RelEllipticalArcTo':
        return EllipticalArcTo(
          x: readLengthInches(row, 'X') ?? 0,
          y: readLengthInches(row, 'Y') ?? 0,
          controlX: readLengthInches(row, 'A') ?? 0,
          controlY: readLengthInches(row, 'B') ?? 0,
          angle: readAngleRadians(row, 'C') ?? 0,
          eccentricity: _rawDouble(row, 'D') ?? 1,
        );
      case 'Ellipse':
        return EllipseCmd(
          cx: readLengthInches(row, 'X') ?? 0,
          cy: readLengthInches(row, 'Y') ?? 0,
          aX: readLengthInches(row, 'A') ?? 0,
          aY: readLengthInches(row, 'B') ?? 0,
          bX: readLengthInches(row, 'C') ?? 0,
          bY: readLengthInches(row, 'D') ?? 0,
        );
      case 'PolylineTo':
      case 'RelPolylineTo':
        return PolylineTo(
          x: readLengthInches(row, 'X') ?? 0,
          y: readLengthInches(row, 'Y') ?? 0,
          vertices: _parsePolylineFormula(_cellValue(row, 'A')),
        );
      case 'InfiniteLine':
      case 'RelInfiniteLine':
        return InfiniteLineCmd(
          x: readLengthInches(row, 'X') ?? 0,
          y: readLengthInches(row, 'Y') ?? 0,
          a: readLengthInches(row, 'A') ?? 0,
          b: readLengthInches(row, 'B') ?? 0,
        );
      case 'SplineStart':
      case 'RelSplineStart':
        return SplineStart(
          x: readLengthInches(row, 'X') ?? 0,
          y: readLengthInches(row, 'Y') ?? 0,
          a: _rawDouble(row, 'A') ?? 0,
          b: _rawDouble(row, 'B') ?? 4,
          c: _rawDouble(row, 'C') ?? 1,
          degree: (_rawDouble(row, 'D') ?? 3).toInt(),
        );
      case 'SplineKnot':
      case 'RelSplineKnot':
        return SplineKnot(
          x: readLengthInches(row, 'X') ?? 0,
          y: readLengthInches(row, 'Y') ?? 0,
          knot: _rawDouble(row, 'A') ?? 0,
        );
      case 'NURBSTo':
      case 'RelNURBSTo':
        final nurbs = _parseNurbsFull(_cellValue(row, 'E'));
        return NurbsTo(
          x: readLengthInches(row, 'X') ?? 0,
          y: readLengthInches(row, 'Y') ?? 0,
          controlPoints: nurbs.controlPoints,
          weights: nurbs.weights,
          knots: nurbs.knots,
          degree: nurbs.degree,
        );
      default:
        // Drop silently-but-noisily for now; the path will fall back to its
        // bounding box.
        _log.fine(() => 'Unsupported Geometry row type: $t');
        return null;
    }
  }

  /// Parse a `POLYLINE(flag, flag, x0, y0, x1, y1, ...)` formula into the
  /// inner vertex list. Returns an empty list if the formula is missing or
  /// malformed.
  List<Offset2D> _parsePolylineFormula(String? raw) {
    final nums = _extractFormulaArgs(raw, 'POLYLINE');
    if (nums.length < 4) return const <Offset2D>[];
    // First two numbers are flags; treat the rest as (x, y) pairs.
    final out = <Offset2D>[];
    for (var i = 2; i + 1 < nums.length; i += 2) {
      out.add(Offset2D(nums[i], nums[i + 1]));
    }
    return List.unmodifiable(out);
  }

  /// Parse an `NURBS(knotLast, degree, xLast, yLast, x1, y1, knot1, weight1,
  /// ...)` formula. Extracts control points, weights, knots and degree —
  /// adequate for a full de Boor evaluation in the path builder.
  _NurbsArgs _parseNurbsFull(String? raw) {
    final nums = _extractFormulaArgs(raw, 'NURBS');
    if (nums.length < 4) return _NurbsArgs.empty;
    final knotLast = nums[0];
    final degree = nums[1].toInt().clamp(1, 7);
    final points = <Offset2D>[];
    final weights = <double>[];
    final knots = <double>[];
    for (var i = 4; i + 3 < nums.length; i += 4) {
      points.add(Offset2D(nums[i], nums[i + 1]));
      knots.add(nums[i + 2]);
      weights.add(nums[i + 3]);
    }
    if (knots.isNotEmpty) knots.add(knotLast);
    return _NurbsArgs(
      controlPoints: List.unmodifiable(points),
      weights: List.unmodifiable(weights),
      knots: List.unmodifiable(knots),
      degree: degree,
    );
  }

  /// Generic `FN(arg1, arg2, ...)` numeric argument extractor. Whitespace
  /// inside the parens is ignored; non-numeric tokens contribute `0`.
  List<double> _extractFormulaArgs(String? raw, String fn) {
    if (raw == null) return const <double>[];
    final s = raw.trim();
    final upper = s.toUpperCase();
    if (!upper.startsWith(fn.toUpperCase())) {
      // Fallback: comma-separated bare numbers (some files omit the
      // `NURBS(`/`POLYLINE(` wrapper after Visio's auto-rewrite).
      return _parseCsvNumbers(s);
    }
    final open = s.indexOf('(');
    final close = s.lastIndexOf(')');
    if (open < 0 || close <= open) return const <double>[];
    return _parseCsvNumbers(s.substring(open + 1, close));
  }

  List<double> _parseCsvNumbers(String s) {
    final out = <double>[];
    for (final tok in s.split(',')) {
      final v = double.tryParse(tok.trim());
      if (v != null) out.add(v);
    }
    return out;
  }

  String? _cellValue(XmlElement row, String name) {
    for (final el in row.childElements) {
      if (el.name.local == 'Cell' && el.getAttribute('N') == name) {
        return el.getAttribute('F') ?? el.getAttribute('V');
      }
    }
    return null;
  }

  /// Read the literal numeric `V=` without any unit normalisation — useful
  /// for `RelXxxTo` where the value is a pure fraction (0..1).
  double? _rawDouble(XmlElement row, String name) {
    for (final el in row.childElements) {
      if (el.name.local == 'Cell' && el.getAttribute('N') == name) {
        return double.tryParse(el.getAttribute('V') ?? '');
      }
    }
    return null;
  }
}

class _NurbsArgs {
  const _NurbsArgs({
    required this.controlPoints,
    required this.weights,
    required this.knots,
    required this.degree,
  });

  static const _NurbsArgs empty = _NurbsArgs(
    controlPoints: <Offset2D>[],
    weights: <double>[],
    knots: <double>[],
    degree: 3,
  );

  final List<Offset2D> controlPoints;
  final List<double> weights;
  final List<double> knots;
  final int degree;
}
