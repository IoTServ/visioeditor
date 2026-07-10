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
