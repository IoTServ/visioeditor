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

  /// Borderless, fill-less text box (drawio's "Text"): a rectangle-bounded
  /// shape that draws only its label. [text] may be empty (the editor fills it
  /// in). Fill / line default to *none* (pattern 0) — but the underlying
  /// geometry is a plain rectangle, so a user can still give the box a
  /// background or border later from the inspector.
  static VsdxShape textBox({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    String text = '',
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
      text: text.isEmpty ? null : text,
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
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
    );
  }

  /// Embedded-picture shape (drawio's "Insert > Image"): a borderless,
  /// fill-less box whose content is the media part [imagePartName]
  /// (e.g. `/visio/media/image7.png`). Carries no geometry — the renderer
  /// paints the decoded image to fill the shape's box, and the writer emits it
  /// as a Visio `Type="Foreign"` shape with a `<ForeignData>` relationship.
  static VsdxShape picture({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    required String imagePartName,
    String? name,
  }) {
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: width.abs(),
      height: height.abs(),
      imagePartName: imagePartName,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
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

  /// Cylinder / database (drawio "Cylinder"): a barrel with an elliptical top
  /// cap. The body (fill + stroke) and the cap's back rim (stroke only) are two
  /// geometries built from MoveTo/LineTo/EllipticalArcTo, so the shape
  /// round-trips through the writer without loss.
  static VsdxShape cylinder({
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
    final ey = (h * 0.15).clamp(0.0, h / 2);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        // Barrel body: left wall, bottom arc, right wall, front rim arc (close).
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, h - ey),
          LineTo(0, ey),
          EllipticalArcTo(x: w, y: ey, controlX: w / 2, controlY: 0),
          LineTo(w, h - ey),
          EllipticalArcTo(x: 0, y: h - ey, controlX: w / 2, controlY: h - 2 * ey),
        ]),
        // Top cap back rim — with the front rim it reads as a full lid ellipse.
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, h - ey),
            EllipticalArcTo(x: w, y: h - ey, controlX: w / 2, controlY: h),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Document (drawio / flowchart "Document"): a rectangle whose bottom edge is
  /// a single S-wave (two elliptical arcs). Round-trips losslessly.
  static VsdxShape document({
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
    final wy = (h * 0.16).clamp(0.0, h / 2);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, wy),
          LineTo(0, h),
          LineTo(w, h),
          LineTo(w, wy),
          // Right half bulges up, left half bulges down → a shallow ~ wave.
          EllipticalArcTo(
              x: w / 2, y: wy, controlX: 3 * w / 4, controlY: wy + wy * 0.9),
          EllipticalArcTo(
              x: 0, y: wy, controlX: w / 4, controlY: wy - wy * 0.9),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Isometric cube (drawio "Cube"): a hexagonal outline (fill + stroke) plus
  /// three inner edges (stroke only). [depth] defaults to 20% of the shorter
  /// side. Round-trips via MoveTo/LineTo across two geometries.
  static VsdxShape cube({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    double? depth,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    final d = (depth ?? math.min(w, h) * 0.2).clamp(0.0, math.min(w, h) / 2);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          const MoveTo(0, 0),
          LineTo(w - d, 0),
          LineTo(w, d),
          LineTo(w, h),
          LineTo(d, h),
          LineTo(0, h - d),
          const LineTo(0, 0),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, h - d),
            LineTo(w - d, h - d),
            LineTo(w - d, 0),
            MoveTo(w - d, h - d),
            LineTo(w, h),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Predefined process (flowchart): a rectangle with two vertical bars near
  /// the left/right edges. Round-trips via two geometries.
  static VsdxShape predefinedProcess({
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
    final bar = (w * 0.1).clamp(0.0, w / 4);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          const MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          const LineTo(0, 0),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(bar, 0),
            LineTo(bar, h),
            MoveTo(w - bar, 0),
            LineTo(w - bar, h),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Internal storage (flowchart): a rectangle with a left vertical rule and a
  /// top horizontal rule. Round-trips via two geometries.
  static VsdxShape internalStorage({
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
    final ix = (w * 0.12).clamp(0.0, w / 3);
    final iy = (h * 0.12).clamp(0.0, h / 3);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          const MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          const LineTo(0, 0),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(ix, 0),
            LineTo(ix, h),
            MoveTo(0, h - iy),
            LineTo(w, h - iy),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Delay (flowchart): a rectangle whose right edge is a semicircle. The
  /// radius is `min(h/2, w)`. Round-trips via MoveTo/LineTo/EllipticalArcTo.
  static VsdxShape delay({
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
    final r = math.min(h / 2, w);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          const MoveTo(0, 0),
          LineTo(w - r, 0),
          EllipticalArcTo(x: w - r, y: h, controlX: w, controlY: h / 2),
          LineTo(0, h),
          const LineTo(0, 0),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Cloud (drawio "Cloud"): a bumpy closed outline made of outward-bulging
  /// elliptical arcs around the box. Round-trips via MoveTo/EllipticalArcTo.
  static VsdxShape cloud({
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
    // Boundary anchors (unit, origin bottom-left, Y-up) around the box.
    const unit = <List<double>>[
      [0.22, 0.30],
      [0.40, 0.14],
      [0.66, 0.15],
      [0.85, 0.33],
      [0.96, 0.55],
      [0.80, 0.82],
      [0.53, 0.92],
      [0.27, 0.83],
      [0.07, 0.62],
      [0.06, 0.40],
    ];
    final pts = <Offset2D>[
      for (final u in unit) Offset2D(u[0] * w, u[1] * h),
    ];
    final cx = w / 2, cy = h / 2;
    final bulge = math.min(w, h) * 0.16;
    final cmds = <VsdxPathCommand>[MoveTo(pts.first.x, pts.first.y)];
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      final mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
      var nx = mx - cx, ny = my - cy;
      final len = math.sqrt(nx * nx + ny * ny);
      if (len > 1e-6) {
        nx /= len;
        ny /= len;
      }
      cmds.add(EllipticalArcTo(
        x: b.x,
        y: b.y,
        controlX: mx + nx * bulge,
        controlY: my + ny * bulge,
      ));
    }
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[VsdxGeometry(commands: cmds)],
      fill: fill,
      line: line,
    );
  }

  /// UML actor (drawio's stick figure): a head ellipse plus a body / arms /
  /// legs stroke geometry. Round-trips via EllipseCmd + MoveTo/LineTo.
  static VsdxShape umlActor({
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
    final headRx = w * 0.22, headRy = h * 0.12;
    final headCy = h * 0.84;
    final headBottom = headCy - headRy;
    final hipY = h * 0.30;
    final armY = h * 0.60;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: w / 2,
              cy: headCy,
              aX: w / 2 + headRx,
              aY: headCy,
              bX: w / 2,
              bY: headCy - headRy),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(w / 2, headBottom),
            LineTo(w / 2, hipY),
            MoveTo(w * 0.12, armY),
            LineTo(w * 0.88, armY),
            MoveTo(w / 2, hipY),
            LineTo(w * 0.15, 0),
            MoveTo(w / 2, hipY),
            LineTo(w * 0.85, 0),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// UML class (drawio): a rectangle split into three compartments by two
  /// horizontal dividers (title / attributes / methods). Round-trips via
  /// two geometries (rect + NoFill divider lines).
  static VsdxShape umlClass({
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
        VsdxGeometry(commands: <VsdxPathCommand>[
          const MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          const LineTo(0, 0),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, h * 0.72),
            LineTo(w, h * 0.72),
            MoveTo(0, h * 0.40),
            LineTo(w, h * 0.40),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// UML package (drawio): a folder outline — a small tab on the top-left over
  /// a body rectangle. Single-polygon geometry (round-trips via MoveTo/LineTo).
  static VsdxShape umlPackage({
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
    final tabW = w * 0.42, tabH = h * 0.16;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, h),
          LineTo(tabW, h),
          LineTo(tabW, h - tabH),
          LineTo(w, h - tabH),
          LineTo(w, 0),
          const LineTo(0, 0),
          LineTo(0, h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Note / annotation (drawio "Note"): a rectangle with a folded top-right
  /// dog-ear. Round-trips via two geometries (cut-corner outline + fold lines).
  static VsdxShape note({
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
    final f = math.min(w, h) * 0.24;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          const MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h - f),
          LineTo(w - f, h),
          LineTo(0, h),
          const LineTo(0, 0),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(w - f, h),
            LineTo(w - f, h - f),
            LineTo(w, h - f),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Display (flowchart): a left point, straight top/bottom, and a right
  /// semicircle. Round-trips via MoveTo/LineTo/EllipticalArcTo.
  static VsdxShape display({
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
    final r = math.min(h / 2, w * 0.6);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, h / 2),
          LineTo(w * 0.22, h),
          LineTo(w - r, h),
          EllipticalArcTo(x: w - r, y: 0, controlX: w, controlY: h / 2),
          LineTo(w * 0.22, 0),
          LineTo(0, h / 2),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Flowchart "Or": a circle crossed by a full-width plus sign. Round-trips
  /// via EllipseCmd + NoFill cross lines.
  static VsdxShape orGate({
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
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(cx: w / 2, cy: h / 2, aX: w, aY: h / 2, bX: w / 2, bY: 0),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, h / 2),
            LineTo(w, h / 2),
            MoveTo(w / 2, 0),
            LineTo(w / 2, h),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Flowchart "Summing Junction": a circle crossed by a diagonal X (corners on
  /// the circle at 45°). Round-trips via EllipseCmd + NoFill cross lines.
  static VsdxShape summingJunction({
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
    const k = 0.1465; // 0.5 - 0.5·cos45° → 45° point on the inscribed circle
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(cx: w / 2, cy: h / 2, aX: w, aY: h / 2, bX: w / 2, bY: 0),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(w * k, h * k),
            LineTo(w * (1 - k), h * (1 - k)),
            MoveTo(w * k, h * (1 - k)),
            LineTo(w * (1 - k), h * k),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Flowchart "Sort": a diamond split by a horizontal mid-line. Round-trips
  /// via two geometries (diamond outline + NoFill divider).
  static VsdxShape sort({
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
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(w / 2, h),
          LineTo(w, h / 2),
          LineTo(w / 2, 0),
          LineTo(0, h / 2),
          LineTo(w / 2, h),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, h / 2),
            LineTo(w, h / 2),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Heart (drawio "Heart"): two top lobes meeting at a centre dip and tapering
  /// to a bottom point, built from four elliptical arcs. Round-trips losslessly.
  static VsdxShape heart({
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
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(w / 2, 0),
          EllipticalArcTo(x: 0, y: h * 0.72, controlX: w * 0.02, controlY: h * 0.34),
          EllipticalArcTo(
              x: w / 2, y: h * 0.72, controlX: w * 0.25, controlY: h * 0.98),
          EllipticalArcTo(
              x: w, y: h * 0.72, controlX: w * 0.75, controlY: h * 0.98),
          EllipticalArcTo(x: w / 2, y: 0, controlX: w * 0.98, controlY: h * 0.34),
        ]),
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
      // Visio connector object type — required for glue / routing in other apps.
      objType: 2,
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
