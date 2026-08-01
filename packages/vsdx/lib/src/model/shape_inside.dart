/// draw.io `shapeInside` text-flow support for simple Visio outlines.
library;

import 'dart:math' as math;

import 'geometry.dart';
import 'shape.dart';
import 'user_property.dart';

typedef VsdxShapeInsideBand = ({double left, double right});

sealed class _ShapeInsideOutline {
  const _ShapeInsideOutline();
  VsdxShapeInsideBand? at(double tau);
}

final class _EllipseOutline extends _ShapeInsideOutline {
  const _EllipseOutline();

  @override
  VsdxShapeInsideBand at(double tau) {
    final y = (2 * tau.clamp(0.0, 1.0)) - 1;
    final inset = 0.5 * (1 - math.sqrt(math.max(0, 1 - y * y)));
    return (left: inset, right: 1 - inset);
  }
}

final class _PolygonOutline extends _ShapeInsideOutline {
  const _PolygonOutline(this.points);

  final List<Offset2D> points;

  @override
  VsdxShapeInsideBand? at(double tau) {
    // Geometry uses Y-up; text layout and draw.io bands use Y-down.
    final y = 1 - tau.clamp(0.0, 1.0);
    final xs = <double>[];
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      if ((a.y <= y && b.y > y) || (b.y <= y && a.y > y)) {
        xs.add(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y));
      }
    }
    if (xs.length < 2) return null;
    xs.sort();
    return (left: xs.first, right: xs.last);
  }
}

extension VsdxShapeInside on VsdxShape {
  /// Persisted draw.io-style text flow toggle.
  bool get shapeInside {
    for (final cell in userCells) {
      if (cell.name == VsdxShape.userShapeInside) return cell.value == '1';
    }
    return false;
  }

  /// Gap between the outline and each text line, in draw.io screen pixels.
  double get shapeInsidePaddingPx {
    for (final cell in userCells) {
      if (cell.name == VsdxShape.userShapeInsidePadding) {
        final value = double.tryParse(cell.value ?? '');
        if (value != null && value.isFinite && value >= 0) return value;
      }
    }
    return 2;
  }

  VsdxShape withShapeInside(bool value) {
    final others = <VsdxUserCell>[
      for (final cell in userCells)
        if (cell.name != VsdxShape.userShapeInside) cell,
    ];
    return copyWith(
      userCells: value
          ? <VsdxUserCell>[
              ...others,
              const VsdxUserCell(name: VsdxShape.userShapeInside, value: '1'),
            ]
          : others,
    );
  }

  VsdxShape withShapeInsidePadding(double pixels) {
    final value = pixels.isFinite ? pixels.clamp(0.0, 100.0).toDouble() : 2.0;
    final others = <VsdxUserCell>[
      for (final cell in userCells)
        if (cell.name != VsdxShape.userShapeInsidePadding) cell,
    ];
    return copyWith(
      userCells: <VsdxUserCell>[
        ...others,
        VsdxUserCell(
          name: VsdxShape.userShapeInsidePadding,
          value: value.toStringAsFixed(4).replaceFirst(RegExp(r'\.?0+$'), ''),
        ),
      ],
    );
  }

  /// True for the same core outline families draw.io exposes in its Format
  /// panel: ellipses and non-rectangular simple convex polygons.
  bool get supportsShapeInside => _shapeInsideOutline != null;

  /// Narrowest relative horizontal interval across a text line's vertical
  /// band. Sampling top/middle/bottom mirrors draw.io's SVG text-flow logic.
  VsdxShapeInsideBand? shapeInsideBand(double topTau, double bottomTau) {
    final outline = _shapeInsideOutline;
    if (outline == null) return null;
    final top = topTau;
    final bottom = bottomTau;
    final sampleTop = flipY ? 1 - bottom : top;
    final sampleBottom = flipY ? 1 - top : bottom;
    VsdxShapeInsideBand? sample(double tau) {
      // Like draw.io, overflowing lines outside the shape regain full width.
      if (tau < 0 || tau > 1) return (left: 0, right: 1);
      // Polygon scanlines use half-open edges; nudge exact extrema inward so
      // an apex yields a very narrow band instead of appearing unsupported.
      return outline.at(tau.clamp(1e-9, 1 - 1e-9).toDouble());
    }

    final a = sample(sampleTop);
    final b = sample((sampleTop + sampleBottom) / 2);
    final c = sample(sampleBottom);
    if (a == null || b == null || c == null) return null;
    var left = math.max(a.left, math.max(b.left, c.left));
    var right = math.min(a.right, math.min(b.right, c.right));
    if (flipX) {
      final oldLeft = left;
      left = 1 - right;
      right = 1 - oldLeft;
    }
    return (left: left, right: math.max(left, right));
  }

  _ShapeInsideOutline? get _shapeInsideOutline {
    if (is1D || width.abs() < 1e-9 || height.abs() < 1e-9) return null;
    for (final geometry in geometries) {
      if (geometry.noShow || geometry.noFill) continue;
      if (geometry.commands.length == 1 &&
          geometry.commands.first is EllipseCmd) {
        final ellipse = geometry.commands.first as EllipseCmd;
        final horizontal = (ellipse.aY - ellipse.cy).abs() < 1e-6;
        final vertical = (ellipse.bX - ellipse.cx).abs() < 1e-6;
        final inscribed = (ellipse.cx - width.abs() / 2).abs() < 1e-6 &&
            (ellipse.cy - height.abs() / 2).abs() < 1e-6 &&
            ((ellipse.aX - ellipse.cx).abs() - width.abs() / 2).abs() < 1e-6 &&
            ((ellipse.bY - ellipse.cy).abs() - height.abs() / 2).abs() < 1e-6;
        if (horizontal && vertical && inscribed) {
          return const _EllipseOutline();
        }
      }
      final points = <Offset2D>[];
      var valid = true;
      for (final command in geometry.commands) {
        switch (command) {
          case MoveTo(:final x, :final y):
            if (points.isNotEmpty) valid = false;
            points.add(Offset2D(x / width.abs(), y / height.abs()));
          case RelMoveTo(:final fx, :final fy):
            if (points.isNotEmpty) valid = false;
            points.add(Offset2D(fx, fy));
          case LineTo(:final x, :final y):
            points.add(Offset2D(x / width.abs(), y / height.abs()));
          case RelLineTo(:final fx, :final fy):
            points.add(Offset2D(fx, fy));
          default:
            valid = false;
        }
        if (!valid) break;
      }
      if (!valid || points.length < 4) continue;
      if (_near(points.first, points.last)) points.removeLast();
      if (points.length < 3 || !_isConvex(points)) continue;
      final outline = _PolygonOutline(points);
      final top = outline.at(0.1);
      final middle = outline.at(0.5);
      final bottom = outline.at(0.9);
      if (top == null || middle == null || bottom == null) continue;
      // A plain rectangle already uses the complete text block and is not an
      // option in draw.io's supported-outline registry.
      final fullRectangle = <VsdxShapeInsideBand>[top, middle, bottom].every(
        (band) => band.left.abs() < 1e-6 && (band.right - 1).abs() < 1e-6,
      );
      if (!fullRectangle) return outline;
    }
    return null;
  }
}

bool _near(Offset2D a, Offset2D b) =>
    (a.x - b.x).abs() < 1e-7 && (a.y - b.y).abs() < 1e-7;

bool _isConvex(List<Offset2D> points) {
  var sign = 0;
  for (var i = 0; i < points.length; i++) {
    final a = points[i];
    final b = points[(i + 1) % points.length];
    final c = points[(i + 2) % points.length];
    final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
    if (cross.abs() < 1e-9) continue;
    final nextSign = cross < 0 ? -1 : 1;
    if (sign != 0 && sign != nextSign) return false;
    sign = nextSign;
  }
  return sign != 0;
}
