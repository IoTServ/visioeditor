/// Builders for brand-new shapes created in the editor.
///
/// All geometry is expressed in **shape-local inches** with the origin at the
/// shape's bottom-left (matching the parser / `lib/render/path_builder.dart`),
/// so a factory shape renders identically before and after a save round-trip.
library;

import 'dart:math' as math;

import '../utils/color.dart';
import 'fill.dart';
import 'geometry.dart';
import 'line.dart';
import 'shape.dart';

abstract final class VsdxShapeFactory {
  VsdxShapeFactory._();

  static const VsdxFill _defaultFill = VsdxFill(foreground: VsdxColor.white);
  static const VsdxLine _defaultLine = VsdxLine(color: VsdxColor.black);

  /// Rectangle spanning [width] x [height] inches, centred at ([pinX],[pinY]).
  static VsdxShape rectangle({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          commands: <VsdxPathCommand>[
            const MoveTo(0, 0),
            LineTo(w, 0),
            LineTo(w, h),
            LineTo(0, h),
            const LineTo(0, 0),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Geometry for a rounded rectangle [w] x [h] (shape-local inches, origin
  /// bottom-left) with corner radius [radius] (clamped to `min(w,h)/2`). A zero
  /// radius yields a plain rectangle. Corners are quarter-circle
  /// [EllipticalArcTo]s (control point = the 45° arc midpoint).
  static VsdxGeometry roundedRectGeometry(double w, double h, double radius) {
    final r = radius.clamp(0.0, math.min(w, h) / 2);
    if (r <= 1e-6) {
      return VsdxGeometry(
        commands: <VsdxPathCommand>[
          const MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          const LineTo(0, 0),
        ],
      );
    }
    final s = r * math.sqrt2 / 2; // arc-midpoint offset from the corner centre
    return VsdxGeometry(
      commands: <VsdxPathCommand>[
        MoveTo(r, 0),
        LineTo(w - r, 0),
        EllipticalArcTo(x: w, y: r, controlX: w - r + s, controlY: r - s),
        LineTo(w, h - r),
        EllipticalArcTo(x: w - r, y: h, controlX: w - r + s, controlY: h - r + s),
        LineTo(r, h),
        EllipticalArcTo(x: 0, y: h - r, controlX: r - s, controlY: h - r + s),
        LineTo(0, r),
        EllipticalArcTo(x: r, y: 0, controlX: r - s, controlY: r - s),
      ],
    );
  }

  /// Rounded rectangle [width] x [height] centred at the pin, corner [radius]
  /// inches (defaults to ~15% of the shorter side).
  static VsdxShape roundedRectangle({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    double? radius,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    final r = radius ?? (math.min(w, h) * 0.15);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[roundedRectGeometry(w, h, r)],
      fill: fill,
      line: line,
    );
  }

  /// Ellipse inscribed in the [width] x [height] box centred at the pin.
  static VsdxShape ellipse({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          commands: <VsdxPathCommand>[
            EllipseCmd(cx: w / 2, cy: h / 2, aX: w, aY: h / 2, bX: w / 2, bY: 0),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Closed polygon from [unit] points (each 0..1 in shape-local space,
  /// origin bottom-left / Y-up), scaled to [width] x [height].
  static VsdxShape polygon({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    required List<Offset2D> unit,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    final commands = <VsdxPathCommand>[
      MoveTo(unit.first.x * w, unit.first.y * h),
      for (final p in unit.skip(1)) LineTo(p.x * w, p.y * h),
      LineTo(unit.first.x * w, unit.first.y * h),
    ];
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[VsdxGeometry(commands: commands)],
      fill: fill,
      line: line,
    );
  }

  /// Straight 1-D line from page point ([ax],[ay]) to ([bx],[by]) (inches).
  static VsdxShape line({
    required int id,
    required double ax,
    required double ay,
    required double bx,
    required double by,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final left = math.min(ax, bx);
    final right = math.max(ax, bx);
    final bottom = math.min(ay, by);
    final top = math.max(ay, by);
    final w = right - left;
    final h = top - bottom;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: (left + right) / 2,
      pinY: (bottom + top) / 2,
      width: w,
      height: h,
      is1D: true,
      beginX: ax,
      beginY: ay,
      endX: bx,
      endY: by,
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          commands: <VsdxPathCommand>[
            MoveTo(ax - left, ay - bottom),
            LineTo(bx - left, by - bottom),
          ],
          noFill: true,
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }
}
