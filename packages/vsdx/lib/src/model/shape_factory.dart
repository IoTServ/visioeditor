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
import 'shape_kind.dart';
import 'sheet_sections.dart';

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

  /// Paper tape / flowchart "Tape": a rectangle whose top and bottom edges are
  /// shallow S-waves (two elliptical arcs each). Round-trips via arcs.
  static VsdxShape tape({
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
    final wy = (h * 0.14).clamp(0.0, h / 4);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, h - wy),
          EllipticalArcTo(
              x: w / 2, y: h - wy, controlX: w / 4, controlY: h),
          EllipticalArcTo(
              x: w, y: h - wy, controlX: 3 * w / 4, controlY: h - 2 * wy),
          LineTo(w, wy),
          EllipticalArcTo(
              x: w / 2, y: wy, controlX: 3 * w / 4, controlY: 0),
          EllipticalArcTo(
              x: 0, y: wy, controlX: w / 4, controlY: 2 * wy),
          LineTo(0, h - wy),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Stored data / data storage (flowchart): a vertical open cylinder — left
  /// edge is a semicircle notch. Round-trips via MoveTo/LineTo/EllipticalArcTo.
  static VsdxShape storedData({
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
    final r = math.min(w * 0.2, h / 2);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(r, 0),
          LineTo(w, 0),
          EllipticalArcTo(x: w, y: h, controlX: w - r, controlY: h / 2),
          LineTo(r, h),
          EllipticalArcTo(x: r, y: 0, controlX: 0, controlY: h / 2),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Flowchart annotation: a left square-bracket (three NoFill strokes). The
  /// label sits in the open box to the right.
  static VsdxShape annotation({
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
    final arm = w * 0.28;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        // Invisible hit box so the shape is selectable.
        VsdxGeometry(
          noLine: true,
          commands: <VsdxPathCommand>[
            const MoveTo(0, 0),
            LineTo(w, 0),
            LineTo(w, h),
            LineTo(0, h),
            const LineTo(0, 0),
          ],
        ),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(arm, h),
            LineTo(0, h),
            const LineTo(0, 0),
            LineTo(arm, 0),
          ],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// Parallel mode (flowchart): two vertical bars. Round-trips via NoFill lines
  /// over a transparent box.
  static VsdxShape parallelMode({
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
    final inset = w * 0.28;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          noLine: true,
          commands: <VsdxPathCommand>[
            const MoveTo(0, 0),
            LineTo(w, 0),
            LineTo(w, h),
            LineTo(0, h),
            const LineTo(0, 0),
          ],
        ),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(inset, 0),
            LineTo(inset, h),
            MoveTo(w - inset, 0),
            LineTo(w - inset, h),
          ],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// Multi-document: a document outline with a second offset copy behind it.
  static VsdxShape multiDocument({
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
    final ox = w * 0.08, oy = h * 0.1;
    final wy = (h * 0.14).clamp(0.0, h / 4);
    VsdxGeometry doc(double dx, double dy, {required bool noFill}) {
      final ww = w - ox, hh = h - oy;
      return VsdxGeometry(
        noFill: noFill,
        commands: <VsdxPathCommand>[
          MoveTo(dx, dy + wy),
          LineTo(dx, dy + hh),
          LineTo(dx + ww, dy + hh),
          LineTo(dx + ww, dy + wy),
          EllipticalArcTo(
              x: dx + ww / 2,
              y: dy + wy,
              controlX: dx + 3 * ww / 4,
              controlY: dy + wy + wy * 0.9),
          EllipticalArcTo(
              x: dx,
              y: dy + wy,
              controlX: dx + ww / 4,
              controlY: dy + wy - wy * 0.9),
        ],
      );
    }

    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        doc(ox, oy, noFill: true),
        doc(0, 0, noFill: false),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Double rectangle (advanced): outer filled rect + inner NoFill inset.
  static VsdxShape doubleRectangle({
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
    final ix = (w * 0.1).clamp(0.0, w / 4);
    final iy = (h * 0.1).clamp(0.0, h / 4);
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
            MoveTo(ix, iy),
            LineTo(w - ix, iy),
            LineTo(w - ix, h - iy),
            LineTo(ix, h - iy),
            LineTo(ix, iy),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Double ellipse / concentric ring outline. Round-trips via two EllipseCmds
  /// (outer filled, inner NoFill).
  static VsdxShape doubleEllipse({
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
    final sx = w * 0.18, sy = h * 0.18;
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
            EllipseCmd(
                cx: w / 2,
                cy: h / 2,
                aX: w - sx,
                aY: h / 2,
                bX: w / 2,
                bY: sy),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Flowchart "And" (bow-tie / hourglass X across a circle). Distinct from
  /// [orGate] (+). Round-trips via EllipseCmd + NoFill diagonals.
  static VsdxShape andGate({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    // Same geometry as summingJunction — Visio/drawio "And" is the X-in-circle.
    return summingJunction(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      fill: fill,
      line: line,
      name: name,
    );
  }

  /// Half circle (basic): lower semicircle closed by a diameter.
  static VsdxShape halfCircle({
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
          EllipticalArcTo(x: 0, y: 0, controlX: w / 2, controlY: h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Wave (basic): a single horizontal S-wave band.
  static VsdxShape wave({
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
    final mid = h * 0.5;
    final amp = h * 0.35;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, mid),
          EllipticalArcTo(
              x: w / 2, y: mid, controlX: w / 4, controlY: mid + amp),
          EllipticalArcTo(
              x: w, y: mid, controlX: 3 * w / 4, controlY: mid - amp),
          LineTo(w, mid - amp * 0.4),
          EllipticalArcTo(
              x: w / 2,
              y: mid - amp * 0.4,
              controlX: 3 * w / 4,
              controlY: mid - amp * 0.4 - amp),
          EllipticalArcTo(
              x: 0,
              y: mid - amp * 0.4,
              controlX: w / 4,
              controlY: mid - amp * 0.4 + amp),
          LineTo(0, mid),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Frame (basic): a rectangular picture frame (outer + inner hole as NoFill
  /// outline — filled ring via even-odd is approximated as outer fill + inner
  /// stroke only; still reads as a frame at stencil size).
  static VsdxShape frame({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    return doubleRectangle(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      fill: fill,
      line: line,
      name: name,
    );
  }

  /// Donut / ring (basic): outer ellipse with a smaller concentric NoFill
  /// ellipse (reads as a ring when stroked).
  static VsdxShape donut({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) =>
      doubleEllipse(
        id: id,
        pinX: pinX,
        pinY: pinY,
        width: width,
        height: height,
        fill: fill,
        line: line,
        name: name,
      );

  /// No-entry / prohibition symbol: circle + diagonal NoFill bar.
  static VsdxShape noSymbol({
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
    const k = 0.1465;
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
            MoveTo(w * k, h * (1 - k)),
            LineTo(w * (1 - k), h * k),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// UML component: rectangle with two small stacked "lollipop" rectangles on
  /// the left edge (IEEE / UML 2 component stereotype).
  static VsdxShape umlComponent({
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
    final tw = w * 0.18, th = h * 0.14;
    final y1 = h * 0.62, y2 = h * 0.32;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(tw / 2, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(tw / 2, h),
          LineTo(tw / 2, 0),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, y1),
            LineTo(tw, y1),
            LineTo(tw, y1 - th),
            LineTo(0, y1 - th),
            LineTo(0, y1),
            MoveTo(0, y2),
            LineTo(tw, y2),
            LineTo(tw, y2 - th),
            LineTo(0, y2 - th),
            LineTo(0, y2),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// BPMN start/intermediate/end event: concentric double ellipse (end events
  /// use a heavier outer stroke in drawio — we emit the double ring).
  static VsdxShape bpmnEvent({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) =>
      doubleEllipse(
        id: id,
        pinX: pinX,
        pinY: pinY,
        width: width,
        height: height,
        fill: fill,
        line: line,
        name: name,
      );

  /// BPMN exclusive gateway: diamond with an X (reuses summing-junction mark).
  static VsdxShape bpmnGateway({
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
    const k = 0.28;
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

  /// BPMN task: rounded rectangle (drawio's default task shape).
  static VsdxShape bpmnTask({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) =>
      roundedRectangle(
        id: id,
        pinX: pinX,
        pinY: pinY,
        width: width,
        height: height,
        radius: math.min(width.abs(), height.abs()) * 0.12,
        fill: fill,
        line: line,
        name: name,
      );

  /// Stacked cylinders (basic "Cylinder Stack" / multi-database).
  static VsdxShape cylinderStack({
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
    final ey = (h * 0.08).clamp(0.0, h / 6);
    final mid = h * 0.55;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, h - ey),
          LineTo(0, ey),
          EllipticalArcTo(x: w, y: ey, controlX: w / 2, controlY: 0),
          LineTo(w, h - ey),
          EllipticalArcTo(
              x: 0, y: h - ey, controlX: w / 2, controlY: h - 2 * ey),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, h - ey),
            EllipticalArcTo(x: w, y: h - ey, controlX: w / 2, controlY: h),
            MoveTo(0, mid),
            EllipticalArcTo(x: w, y: mid, controlX: w / 2, controlY: mid + ey),
            MoveTo(0, mid),
            EllipticalArcTo(x: w, y: mid, controlX: w / 2, controlY: mid - ey),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Cone (basic): triangle with an elliptical base.
  static VsdxShape cone({
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
    final ey = h * 0.18;
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
          LineTo(w, ey),
          EllipticalArcTo(x: 0, y: ey, controlX: w / 2, controlY: 0),
          LineTo(w / 2, h),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, ey),
            EllipticalArcTo(x: w, y: ey, controlX: w / 2, controlY: 2 * ey),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Teardrop / drop (basic).
  static VsdxShape drop({
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
          EllipticalArcTo(x: 0, y: h * 0.35, controlX: w * 0.05, controlY: h * 0.75),
          EllipticalArcTo(x: w / 2, y: 0, controlX: 0, controlY: h * 0.05),
          EllipticalArcTo(x: w, y: h * 0.35, controlX: w, controlY: h * 0.05),
          EllipticalArcTo(x: w / 2, y: h, controlX: w * 0.95, controlY: h * 0.75),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Pointed oval / stadium with pointed ends (basic).
  static VsdxShape pointedOval({
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
          EllipticalArcTo(x: 0, y: h / 2, controlX: w * 0.15, controlY: h),
          EllipticalArcTo(x: w / 2, y: 0, controlX: w * 0.15, controlY: 0),
          EllipticalArcTo(x: w, y: h / 2, controlX: w * 0.85, controlY: 0),
          EllipticalArcTo(x: w / 2, y: h, controlX: w * 0.85, controlY: h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Pie slice (basic): a sector from centre to an arc.
  static VsdxShape pie({
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
          MoveTo(w / 2, h / 2),
          LineTo(w, h / 2),
          EllipticalArcTo(x: w / 2, y: h, controlX: w * 0.85, controlY: h * 0.85),
          LineTo(w / 2, h / 2),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Smiley face (basic): circle + two eyes + smile arc.
  static VsdxShape smiley({
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
    final er = math.min(w, h) * 0.06;
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
            EllipseCmd(
                cx: w * 0.35,
                cy: h * 0.62,
                aX: w * 0.35 + er,
                aY: h * 0.62,
                bX: w * 0.35,
                bY: h * 0.62 - er),
            EllipseCmd(
                cx: w * 0.65,
                cy: h * 0.62,
                aX: w * 0.65 + er,
                aY: h * 0.62,
                bX: w * 0.65,
                bY: h * 0.62 - er),
            MoveTo(w * 0.28, h * 0.38),
            EllipticalArcTo(
                x: w * 0.72, y: h * 0.38, controlX: w / 2, controlY: h * 0.18),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// UML boundary: circle with a vertical bar on the left (lollipop interface).
  static VsdxShape umlBoundary({
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
    final cx = w * 0.62, cy = h / 2, r = math.min(w, h) * 0.38;
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
              cx: cx, cy: cy, aX: cx + r, aY: cy, bX: cx, bY: cy - r),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(w * 0.12, h * 0.2),
            LineTo(w * 0.12, h * 0.8),
            MoveTo(w * 0.12, h / 2),
            LineTo(cx - r, h / 2),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// UML control: circle with an arrow-ish arc on top.
  static VsdxShape umlControl({
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
    final r = math.min(w, h) * 0.38;
    final cx = w / 2, cy = h * 0.42;
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
              cx: cx, cy: cy, aX: cx + r, aY: cy, bX: cx, bY: cy - r),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(cx + r * 0.5, cy + r),
            EllipticalArcTo(
                x: cx + r * 0.2,
                y: h * 0.92,
                controlX: w * 0.85,
                controlY: h * 0.85),
            LineTo(w * 0.72, h * 0.78),
            MoveTo(cx + r * 0.2, h * 0.92),
            LineTo(w * 0.88, h * 0.88),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// ER / Chen associative entity: rectangle with an inscribed diamond.
  static VsdxShape associativeEntity({
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
            MoveTo(w / 2, h * 0.12),
            LineTo(w * 0.88, h / 2),
            LineTo(w / 2, h * 0.88),
            LineTo(w * 0.12, h / 2),
            LineTo(w / 2, h * 0.12),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Weak / double rectangle (ER Chen weak entity) — alias of [doubleRectangle].
  static VsdxShape weakEntity({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) =>
      doubleRectangle(
        id: id,
        pinX: pinX,
        pinY: pinY,
        width: width,
        height: height,
        fill: fill,
        line: line,
        name: name,
      );

  /// Identifying relationship: double diamond (ER Chen).
  static VsdxShape identifyingRelationship({
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
    const k = 0.18;
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
            MoveTo(w / 2, h * (1 - k)),
            LineTo(w * (1 - k), h / 2),
            LineTo(w / 2, h * k),
            LineTo(w * k, h / 2),
            LineTo(w / 2, h * (1 - k)),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// BPMN parallel gateway: diamond with a plus.
  static VsdxShape bpmnParallelGateway({
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
    const k = 0.28;
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
            MoveTo(w * k, h / 2),
            LineTo(w * (1 - k), h / 2),
            MoveTo(w / 2, h * k),
            LineTo(w / 2, h * (1 - k)),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// BPMN inclusive gateway: diamond with an inscribed circle.
  static VsdxShape bpmnInclusiveGateway({
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
    final r = math.min(w, h) * 0.22;
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
            EllipseCmd(
                cx: w / 2,
                cy: h / 2,
                aX: w / 2 + r,
                aY: h / 2,
                bX: w / 2,
                bY: h / 2 - r),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// BPMN pool / lane: wide rectangle with a left title strip.
  ///
  /// Prefer [SwimlaneOps.assemblePool] for multi-lane pools and
  /// [SwimlaneOps.lane] for oriented single lanes.
  static VsdxShape bpmnPool({
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
    final strip = w * 0.12;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      shapeKind: VsdxShapeKind.swimlane,
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
            MoveTo(strip, 0),
            LineTo(strip, h),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// BPMN conversation: hexagon.
  static VsdxShape bpmnConversation({
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
          MoveTo(w * 0.25, h),
          LineTo(w * 0.75, h),
          LineTo(w, h / 2),
          LineTo(w * 0.75, 0),
          LineTo(w * 0.25, 0),
          LineTo(0, h / 2),
          LineTo(w * 0.25, h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Ellipse with a horizontal divider (Advanced).
  static VsdxShape ellipseDividerH({
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
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Ellipse with a vertical divider (Advanced).
  static VsdxShape ellipseDividerV({
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
            MoveTo(w / 2, 0),
            LineTo(w / 2, h),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Layered rectangle (basic): three offset stacked rect outlines.
  static VsdxShape layeredRectangle({
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
    final ox = w * 0.08, oy = h * 0.12;
    VsdxGeometry rect(double dx, double dy, {required bool noFill}) {
      final ww = w - 2 * ox, hh = h - 2 * oy;
      return VsdxGeometry(
        noFill: noFill,
        commands: <VsdxPathCommand>[
          MoveTo(dx, dy),
          LineTo(dx + ww, dy),
          LineTo(dx + ww, dy + hh),
          LineTo(dx, dy + hh),
          LineTo(dx, dy),
        ],
      );
    }

    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        rect(2 * ox, 2 * oy, noFill: true),
        rect(ox, oy, noFill: true),
        rect(0, 0, noFill: false),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Partial rectangle (basic): three sides (open top), like a U.
  static VsdxShape partialRectangle({
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
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, h),
            LineTo(0, 0),
            LineTo(w, 0),
            LineTo(w, h),
          ],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// Diagonal-snip rectangle (basic): top-right corner cut off.
  static VsdxShape diagonalSnipRectangle({
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
    final s = math.min(w, h) * 0.28;
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
          LineTo(w - s, h),
          LineTo(w, h - s),
          LineTo(w, 0),
          LineTo(0, 0),
          LineTo(0, h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Envelope / message (basic + BPMN message marker).
  static VsdxShape message({
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
          MoveTo(0, h),
          LineTo(w, h),
          LineTo(w, 0),
          LineTo(0, 0),
          LineTo(0, h),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, h),
            LineTo(w / 2, h * 0.45),
            LineTo(w, h),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Push-button (basic): rounded rect with an inset ellipse.
  static VsdxShape button({
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
    final r = math.min(w, h) * 0.2;
    final inset = math.min(w, h) * 0.12;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(r, h),
          LineTo(w - r, h),
          EllipticalArcTo(x: w, y: h - r, controlX: w, controlY: h),
          LineTo(w, r),
          EllipticalArcTo(x: w - r, y: 0, controlX: w, controlY: 0),
          LineTo(r, 0),
          EllipticalArcTo(x: 0, y: r, controlX: 0, controlY: 0),
          LineTo(0, h - r),
          EllipticalArcTo(x: r, y: h, controlX: 0, controlY: h),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            EllipseCmd(
              cx: w / 2,
              cy: h / 2,
              aX: w - inset,
              aY: h / 2,
              bX: w / 2,
              bY: inset,
            ),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Open elliptical arc (basic).
  static VsdxShape arc({
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
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, h * 0.15),
            EllipticalArcTo(x: w, y: h * 0.15, controlX: w / 2, controlY: h),
          ],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// Partial concentric ellipse / crescent ring segment (basic).
  static VsdxShape partialConcentricEllipse({
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
          MoveTo(0, h / 2),
          EllipticalArcTo(x: w, y: h / 2, controlX: w / 2, controlY: h),
          EllipticalArcTo(x: 0, y: h / 2, controlX: w / 2, controlY: h * 0.65),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(w * 0.18, h / 2),
            EllipticalArcTo(
                x: w * 0.82, y: h / 2, controlX: w / 2, controlY: h * 0.88),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Price-tag / label (basic).
  static VsdxShape tag({
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
    final hole = math.min(w, h) * 0.08;
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
          LineTo(w, h),
          LineTo(w, 0),
          LineTo(w * 0.22, 0),
          LineTo(0, h / 2),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            EllipseCmd(
              cx: w * 0.28,
              cy: h / 2,
              aX: w * 0.28 + hole,
              aY: h / 2,
              bX: w * 0.28,
              bY: h / 2 - hole,
            ),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Explosion / bang burst (basic).
  static VsdxShape bang({
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
    // Star-like irregular burst in unit space.
    const pts = <(double, double)>[
      (0.50, 1.00),
      (0.58, 0.78),
      (0.78, 0.90),
      (0.70, 0.68),
      (0.95, 0.70),
      (0.76, 0.55),
      (1.00, 0.42),
      (0.74, 0.40),
      (0.88, 0.18),
      (0.62, 0.28),
      (0.55, 0.00),
      (0.45, 0.22),
      (0.22, 0.08),
      (0.30, 0.32),
      (0.00, 0.35),
      (0.24, 0.48),
      (0.05, 0.68),
      (0.32, 0.65),
      (0.20, 0.90),
      (0.42, 0.78),
    ];
    final cmds = <VsdxPathCommand>[
      MoveTo(pts.first.$1 * w, pts.first.$2 * h),
      for (var i = 1; i < pts.length; i++)
        LineTo(pts[i].$1 * w, pts[i].$2 * h),
      LineTo(pts.first.$1 * w, pts.first.$2 * h),
    ];
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

  /// Neutral / flat-mouth smiley (basic).
  static VsdxShape neutralSmiley({
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
    final er = math.min(w, h) * 0.06;
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
            EllipseCmd(
                cx: w * 0.35,
                cy: h * 0.62,
                aX: w * 0.35 + er,
                aY: h * 0.62,
                bX: w * 0.35,
                bY: h * 0.62 - er),
            EllipseCmd(
                cx: w * 0.65,
                cy: h * 0.62,
                aX: w * 0.65 + er,
                aY: h * 0.62,
                bX: w * 0.65,
                bY: h * 0.62 - er),
            MoveTo(w * 0.30, h * 0.32),
            LineTo(w * 0.70, h * 0.32),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Sad smiley (basic).
  static VsdxShape sadSmiley({
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
    final er = math.min(w, h) * 0.06;
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
            EllipseCmd(
                cx: w * 0.35,
                cy: h * 0.62,
                aX: w * 0.35 + er,
                aY: h * 0.62,
                bX: w * 0.35,
                bY: h * 0.62 - er),
            EllipseCmd(
                cx: w * 0.65,
                cy: h * 0.62,
                aX: w * 0.65 + er,
                aY: h * 0.62,
                bX: w * 0.65,
                bY: h * 0.62 - er),
            MoveTo(w * 0.28, h * 0.28),
            EllipticalArcTo(
                x: w * 0.72, y: h * 0.28, controlX: w / 2, controlY: h * 0.45),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// UML module / component-like block with two side tabs.
  static VsdxShape umlModule({
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
    final tw = w * 0.18, th = h * 0.18;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(tw, h),
          LineTo(w, h),
          LineTo(w, 0),
          LineTo(tw, 0),
          LineTo(tw, h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, h * 0.72),
          LineTo(tw * 1.4, h * 0.72),
          LineTo(tw * 1.4, h * 0.72 - th),
          LineTo(0, h * 0.72 - th),
          LineTo(0, h * 0.72),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, h * 0.42),
          LineTo(tw * 1.4, h * 0.42),
          LineTo(tw * 1.4, h * 0.42 - th),
          LineTo(0, h * 0.42 - th),
          LineTo(0, h * 0.42),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// UML sequence lifeline: head box + vertical stem.
  static VsdxShape umlLifeline({
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
    final head = math.min(h * 0.22, 0.55);
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
          LineTo(w, h),
          LineTo(w, h - head),
          LineTo(0, h - head),
          LineTo(0, h),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(w / 2, h - head),
            LineTo(w / 2, 0),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// UML activation bar (thin filled rectangle on a lifeline).
  static VsdxShape umlActivationBar({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) =>
      rectangle(
        id: id,
        pinX: pinX,
        pinY: pinY,
        width: width,
        height: height,
        fill: fill,
        line: line,
        name: name,
      );

  /// UML destruction marker (large X).
  static VsdxShape umlDestruction({
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
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, h),
            LineTo(w, 0),
            MoveTo(0, 0),
            LineTo(w, h),
          ],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// UML provided interface (lollipop): small circle.
  static VsdxShape providedInterface({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) =>
      ellipse(
        id: id,
        pinX: pinX,
        pinY: pinY,
        width: width,
        height: height,
        fill: fill,
        line: line,
        name: name,
      );

  /// UML required interface (socket): open C-shaped arc.
  static VsdxShape requiredInterface({
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
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(w, h * 0.15),
            EllipticalArcTo(x: w, y: h * 0.85, controlX: 0, controlY: h / 2),
          ],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// UML sequence frame: outer rect + top-left title tab.
  static VsdxShape umlFrame({
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
    final th = h * 0.14, tw = w * 0.35;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, h),
            LineTo(w, h),
            LineTo(w, 0),
            LineTo(0, 0),
            LineTo(0, h),
          ],
        ),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, h),
          LineTo(tw, h),
          LineTo(tw, h - th),
          LineTo(0, h - th),
          LineTo(0, h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// BPMN message start/intermediate: circle with envelope.
  static VsdxShape bpmnMessageEvent({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
    bool intermediate = false,
  }) {
    final w = width.abs();
    final h = height.abs();
    final geoms = <VsdxGeometry>[
      VsdxGeometry(commands: <VsdxPathCommand>[
        EllipseCmd(cx: w / 2, cy: h / 2, aX: w, aY: h / 2, bX: w / 2, bY: 0),
      ]),
    ];
    if (intermediate) {
      geoms.add(VsdxGeometry(
        noFill: true,
        commands: <VsdxPathCommand>[
          EllipseCmd(
            cx: w / 2,
            cy: h / 2,
            aX: w * 0.88,
            aY: h / 2,
            bX: w / 2,
            bY: h * 0.12,
          ),
        ],
      ));
    }
    final ix = w * 0.28, iy = h * 0.38, iw = w * 0.44, ih = h * 0.28;
    geoms.add(VsdxGeometry(
      noFill: true,
      commands: <VsdxPathCommand>[
        MoveTo(ix, iy + ih),
        LineTo(ix + iw, iy + ih),
        LineTo(ix + iw, iy),
        LineTo(ix, iy),
        LineTo(ix, iy + ih),
        MoveTo(ix, iy + ih),
        LineTo(ix + iw / 2, iy + ih * 0.45),
        LineTo(ix + iw, iy + ih),
      ],
    ));
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: geoms,
      fill: fill,
      line: line,
    );
  }

  /// BPMN timer event: circle with simple clock hands.
  static VsdxShape bpmnTimerEvent({
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
            EllipseCmd(
              cx: w / 2,
              cy: h / 2,
              aX: w * 0.78,
              aY: h / 2,
              bX: w / 2,
              bY: h * 0.22,
            ),
            MoveTo(w / 2, h / 2),
            LineTo(w / 2, h * 0.72),
            MoveTo(w / 2, h / 2),
            LineTo(w * 0.68, h / 2),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// BPMN terminate end: thick outer circle + filled inner disc.
  static VsdxShape bpmnTerminateEvent({
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
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
            cx: w / 2,
            cy: h / 2,
            aX: w * 0.72,
            aY: h / 2,
            bX: w / 2,
            bY: h * 0.28,
          ),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// BPMN complex gateway: diamond with asterisk.
  static VsdxShape bpmnComplexGateway({
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
    const k = 0.32;
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
            MoveTo(w / 2, h * k),
            LineTo(w / 2, h * (1 - k)),
            MoveTo(w * k, h / 2),
            LineTo(w * (1 - k), h / 2),
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

  /// BPMN event-based gateway: diamond + inner double circle.
  static VsdxShape bpmnEventBasedGateway({
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
            EllipseCmd(
              cx: w / 2,
              cy: h / 2,
              aX: w * 0.72,
              aY: h / 2,
              bX: w / 2,
              bY: h * 0.28,
            ),
            EllipseCmd(
              cx: w / 2,
              cy: h / 2,
              aX: w * 0.60,
              aY: h / 2,
              bX: w / 2,
              bY: h * 0.40,
            ),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// General container: large rounded box with a top title band.
  static VsdxShape container({
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
    final band = h * 0.18;
    final r = math.min(w, h) * 0.06;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      shapeKind: VsdxShapeKind.container,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(r, h),
          LineTo(w - r, h),
          EllipticalArcTo(x: w, y: h - r, controlX: w, controlY: h),
          LineTo(w, r),
          EllipticalArcTo(x: w - r, y: 0, controlX: w, controlY: 0),
          LineTo(r, 0),
          EllipticalArcTo(x: 0, y: r, controlX: 0, controlY: 0),
          LineTo(0, h - r),
          EllipticalArcTo(x: r, y: h, controlX: 0, controlY: h),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, h - band),
            LineTo(w, h - band),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Rectangle with hatch/pattern fill approximated as NoFill stroke lines.
  ///
  /// [style]: `diag` | `diagRev` | `vert` | `hor` | `grid` | `diagGrid`.
  static VsdxShape rectWithHatch({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    String style = 'diag',
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    final step = math.max(math.min(w, h) * 0.12, 0.08);
    final hatch = <VsdxPathCommand>[];
    void addLine(double x0, double y0, double x1, double y1) {
      hatch
        ..add(MoveTo(x0, y0))
        ..add(LineTo(x1, y1));
    }

    if (style == 'diag' || style == 'diagGrid' || style == 'grid') {
      // / diagonals
      for (var t = -h; t < w + h; t += step) {
        final x0 = t.clamp(0.0, w);
        final y0 = (t < 0) ? -t : 0.0;
        final x1 = (t + h).clamp(0.0, w);
        final y1 = (t + h > w) ? h - (t + h - w) : h;
        if ((x1 - x0).abs() > 1e-6 || (y1 - y0).abs() > 1e-6) {
          addLine(x0, y0, x1, y1);
        }
      }
    }
    if (style == 'diagRev' || style == 'diagGrid') {
      // \ diagonals
      for (var t = 0.0; t < w + h; t += step) {
        final x0 = t.clamp(0.0, w);
        final y0 = (t > w) ? h - (t - w) : h;
        final x1 = (t - h).clamp(0.0, w);
        final y1 = (t > h) ? 0.0 : h - t;
        if ((x1 - x0).abs() > 1e-6 || (y1 - y0).abs() > 1e-6) {
          addLine(x0, y0, x1, y1);
        }
      }
    }
    if (style == 'vert' || style == 'grid') {
      for (var x = step; x < w; x += step) {
        addLine(x, 0, x, h);
      }
    }
    if (style == 'hor' || style == 'grid') {
      for (var y = step; y < h; y += step) {
        addLine(0, y, w, y);
      }
    }

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
          LineTo(w, h),
          LineTo(w, 0),
          LineTo(0, 0),
          LineTo(0, h),
        ]),
        if (hatch.isNotEmpty)
          VsdxGeometry(noFill: true, commands: hatch),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Diagonal-rounded rectangle: one corner (top-right) rounded, rest sharp.
  static VsdxShape diagonalRoundedRectangle({
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
    final r = math.min(w, h) * 0.28;
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
          LineTo(w - r, h),
          EllipticalArcTo(x: w, y: h - r, controlX: w, controlY: h),
          LineTo(w, 0),
          LineTo(0, 0),
          LineTo(0, h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Corner-rounded rectangle: only bottom-left corner rounded.
  static VsdxShape cornerRoundedRectangle({
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
    final r = math.min(w, h) * 0.28;
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
          LineTo(w, h),
          LineTo(w, 0),
          LineTo(r, 0),
          EllipticalArcTo(x: 0, y: r, controlX: 0, controlY: 0),
          LineTo(0, h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Three-corner rounded rectangle (top-left sharp).
  static VsdxShape threeCornerRoundedRectangle({
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
    final r = math.min(w, h) * 0.22;
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
          LineTo(w - r, h),
          EllipticalArcTo(x: w, y: h - r, controlX: w, controlY: h),
          LineTo(w, r),
          EllipticalArcTo(x: w - r, y: 0, controlX: w, controlY: 0),
          LineTo(r, 0),
          EllipticalArcTo(x: 0, y: r, controlX: 0, controlY: 0),
          LineTo(0, h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Rounded frame: outer rounded rect + inner rounded hole outline.
  static VsdxShape roundedFrame({
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
    final r = math.min(w, h) * 0.12;
    final inset = math.min(w, h) * 0.14;
    final ri = math.max(r * 0.6, 0.02);
    List<VsdxPathCommand> roundRect(
        double x0, double y0, double x1, double y1, double rr) {
      return <VsdxPathCommand>[
        MoveTo(x0 + rr, y1),
        LineTo(x1 - rr, y1),
        EllipticalArcTo(x: x1, y: y1 - rr, controlX: x1, controlY: y1),
        LineTo(x1, y0 + rr),
        EllipticalArcTo(x: x1 - rr, y: y0, controlX: x1, controlY: y0),
        LineTo(x0 + rr, y0),
        EllipticalArcTo(x: x0, y: y0 + rr, controlX: x0, controlY: y0),
        LineTo(x0, y1 - rr),
        EllipticalArcTo(x: x0 + rr, y: y1, controlX: x0, controlY: y1),
      ];
    }

    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: roundRect(0, 0, w, h, r)),
        VsdxGeometry(
          noFill: true,
          commands: roundRect(inset, inset, w - inset, h - inset, ri),
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Plaque frame: plaque outer + inset plaque outline.
  static VsdxShape plaqueFrame({
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
    final c = math.min(w, h) * 0.18;
    final inset = math.min(w, h) * 0.14;
    final ci = c * 0.7;
    List<VsdxPathCommand> plaque(
        double x0, double y0, double x1, double y1, double cc) {
      return <VsdxPathCommand>[
        MoveTo(x0 + cc, y1),
        LineTo(x1 - cc, y1),
        LineTo(x1, y1 - cc),
        LineTo(x1, y0 + cc),
        LineTo(x1 - cc, y0),
        LineTo(x0 + cc, y0),
        LineTo(x0, y0 + cc),
        LineTo(x0, y1 - cc),
        LineTo(x0 + cc, y1),
      ];
    }

    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: plaque(0, 0, w, h, c)),
        VsdxGeometry(
          noFill: true,
          commands: plaque(inset, inset, w - inset, h - inset, ci),
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// UML actor lifeline: stick-figure head + stem.
  static VsdxShape umlActorLifeline({
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
    final head = math.min(h * 0.28, 0.7);
    final cx = w / 2;
    final hr = math.min(w, head) * 0.22;
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
              cx: cx,
              cy: h - hr,
              aX: cx + hr,
              aY: h - hr,
              bX: cx,
              bY: h - 2 * hr),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(cx, h - 2 * hr),
            LineTo(cx, h - head * 0.55),
            MoveTo(w * 0.15, h - head * 0.75),
            LineTo(w * 0.85, h - head * 0.75),
            MoveTo(cx, h - head * 0.55),
            LineTo(w * 0.2, h - head),
            MoveTo(cx, h - head * 0.55),
            LineTo(w * 0.8, h - head),
            MoveTo(cx, h - head),
            LineTo(cx, 0),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// UML boundary/entity/control lifeline: stereotype head + stem.
  /// [kind]: `boundary` | `entity` | `control`.
  static VsdxShape umlStereoLifeline({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    String kind = 'entity',
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    final head = math.min(h * 0.22, 0.55);
    final cx = w / 2;
    final r = math.min(w, head) * 0.35;
    final geoms = <VsdxGeometry>[
      VsdxGeometry(commands: <VsdxPathCommand>[
        EllipseCmd(
            cx: cx, cy: h - head / 2, aX: cx + r, aY: h - head / 2, bX: cx, bY: h - head / 2 - r),
      ]),
      VsdxGeometry(
        noFill: true,
        commands: <VsdxPathCommand>[
          MoveTo(cx, h - head / 2 - r),
          LineTo(cx, 0),
        ],
      ),
    ];
    if (kind == 'boundary') {
      geoms.add(VsdxGeometry(
        noFill: true,
        commands: <VsdxPathCommand>[
          MoveTo(w * 0.08, h - head * 0.85),
          LineTo(w * 0.08, h - head * 0.15),
          MoveTo(w * 0.08, h - head / 2),
          LineTo(cx - r, h - head / 2),
        ],
      ));
    } else if (kind == 'entity') {
      geoms.add(VsdxGeometry(
        noFill: true,
        commands: <VsdxPathCommand>[
          MoveTo(cx - r, h - head / 2 - r),
          LineTo(cx + r, h - head / 2 - r),
        ],
      ));
    } else if (kind == 'control') {
      geoms.add(VsdxGeometry(
        noFill: true,
        commands: <VsdxPathCommand>[
          MoveTo(cx + r * 0.3, h - head / 2 + r * 0.85),
          EllipticalArcTo(
              x: cx + r * 0.85,
              y: h - head / 2 + r * 0.2,
              controlX: cx + r * 1.1,
              controlY: h - head / 2 + r),
          LineTo(cx + r * 0.55, h - head / 2 + r * 0.55),
        ],
      ));
    }
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: geoms,
      fill: fill,
      line: line,
    );
  }

  /// BPMN cancel intermediate: double circle + X.
  static VsdxShape bpmnCancelEvent({
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
    const k = 0.28;
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
            EllipseCmd(
              cx: w / 2,
              cy: h / 2,
              aX: w * 0.88,
              aY: h / 2,
              bX: w / 2,
              bY: h * 0.12,
            ),
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

  /// BPMN compensation marker: two side-by-side triangles (rewind).
  static VsdxShape bpmnCompensation({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
    bool asEvent = false,
  }) {
    final w = width.abs();
    final h = height.abs();
    final geoms = <VsdxGeometry>[];
    if (asEvent) {
      geoms.add(VsdxGeometry(commands: <VsdxPathCommand>[
        EllipseCmd(cx: w / 2, cy: h / 2, aX: w, aY: h / 2, bX: w / 2, bY: 0),
      ]));
      geoms.add(VsdxGeometry(
        noFill: true,
        commands: <VsdxPathCommand>[
          EllipseCmd(
            cx: w / 2,
            cy: h / 2,
            aX: w * 0.88,
            aY: h / 2,
            bX: w / 2,
            bY: h * 0.12,
          ),
        ],
      ));
    }
    final midY = h / 2;
    final tH = h * (asEvent ? 0.28 : 0.45);
    geoms.add(VsdxGeometry(
      noFill: true,
      commands: <VsdxPathCommand>[
        MoveTo(w * 0.52, midY),
        LineTo(w * 0.78, midY + tH),
        LineTo(w * 0.78, midY - tH),
        LineTo(w * 0.52, midY),
        MoveTo(w * 0.22, midY),
        LineTo(w * 0.48, midY + tH),
        LineTo(w * 0.48, midY - tH),
        LineTo(w * 0.22, midY),
      ],
    ));
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: geoms,
      fill: fill,
      line: line,
    );
  }

  /// BPMN link event: circle with right-pointing arrow.
  static VsdxShape bpmnLinkEvent({
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
            MoveTo(w * 0.22, h * 0.42),
            LineTo(w * 0.55, h * 0.42),
            LineTo(w * 0.55, h * 0.28),
            LineTo(w * 0.78, h * 0.5),
            LineTo(w * 0.55, h * 0.72),
            LineTo(w * 0.55, h * 0.58),
            LineTo(w * 0.22, h * 0.58),
            LineTo(w * 0.22, h * 0.42),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// BPMN loop marker: circular arrow.
  static VsdxShape bpmnLoopMarker({
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
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(w * 0.2, h * 0.55),
            EllipticalArcTo(
                x: w * 0.8, y: h * 0.55, controlX: w / 2, controlY: h * 0.95),
            EllipticalArcTo(
                x: w * 0.35, y: h * 0.25, controlX: w * 0.85, controlY: h * 0.15),
            LineTo(w * 0.22, h * 0.38),
            MoveTo(w * 0.35, h * 0.25),
            LineTo(w * 0.48, h * 0.18),
          ],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// BPMN multi-instance marker: three vertical bars.
  static VsdxShape bpmnMultiInstance({
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
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(w * 0.25, h * 0.15),
            LineTo(w * 0.25, h * 0.85),
            MoveTo(w * 0.5, h * 0.15),
            LineTo(w * 0.5, h * 0.85),
            MoveTo(w * 0.75, h * 0.15),
            LineTo(w * 0.75, h * 0.85),
          ],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// BPMN multiple intermediate event: double circle + pentagon.
  static VsdxShape bpmnMultipleEvent({
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
            EllipseCmd(
              cx: w / 2,
              cy: h / 2,
              aX: w * 0.88,
              aY: h / 2,
              bX: w / 2,
              bY: h * 0.12,
            ),
            MoveTo(w * 0.5, h * 0.72),
            LineTo(w * 0.72, h * 0.58),
            LineTo(w * 0.64, h * 0.32),
            LineTo(w * 0.36, h * 0.32),
            LineTo(w * 0.28, h * 0.58),
            LineTo(w * 0.5, h * 0.72),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// BPMN rule / conditional event: circle with lined table glyph.
  static VsdxShape bpmnRuleEvent({
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
    final x0 = w * 0.32, x1 = w * 0.68, y0 = h * 0.32, y1 = h * 0.68;
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
            MoveTo(x0, y1),
            LineTo(x1, y1),
            LineTo(x1, y0),
            LineTo(x0, y0),
            LineTo(x0, y1),
            MoveTo(x0, y0 + (y1 - y0) / 3),
            LineTo(x1, y0 + (y1 - y0) / 3),
            MoveTo(x0, y0 + 2 * (y1 - y0) / 3),
            LineTo(x1, y0 + 2 * (y1 - y0) / 3),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// BPMN ad-hoc marker: tilde (~).
  static VsdxShape bpmnAdHoc({
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
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(w * 0.1, h * 0.45),
            EllipticalArcTo(
                x: w * 0.5, y: h * 0.55, controlX: w * 0.3, controlY: h * 0.75),
            EllipticalArcTo(
                x: w * 0.9, y: h * 0.45, controlX: w * 0.7, controlY: h * 0.25),
          ],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// Left curly bracket (misc).
  static VsdxShape curlyBracket({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    bool flipH = false,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    final xTip = flipH ? w : 0.0;
    final xBody = flipH ? 0.0 : w;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(xBody, h),
            EllipticalArcTo(
                x: w / 2, y: h * 0.75, controlX: xBody, controlY: h * 0.88),
            LineTo(w / 2, h * 0.55),
            EllipticalArcTo(
                x: xTip, y: h / 2, controlX: w / 2, controlY: h * 0.55),
            EllipticalArcTo(
                x: w / 2, y: h * 0.45, controlX: w / 2, controlY: h * 0.45),
            LineTo(w / 2, h * 0.25),
            EllipticalArcTo(
                x: xBody, y: 0, controlX: xBody, controlY: h * 0.12),
          ],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// Crossbar / dimension bar (misc): line with end ticks.
  static VsdxShape crossbar({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    bool vertical = false,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    final cmds = <VsdxPathCommand>[];
    if (vertical) {
      cmds
        ..add(MoveTo(w / 2, 0))
        ..add(LineTo(w / 2, h))
        ..add(MoveTo(0, 0))
        ..add(LineTo(w, 0))
        ..add(MoveTo(0, h))
        ..add(LineTo(w, h));
    } else {
      cmds
        ..add(MoveTo(0, h / 2))
        ..add(LineTo(w, h / 2))
        ..add(MoveTo(0, 0))
        ..add(LineTo(0, h))
        ..add(MoveTo(w, 0))
        ..add(LineTo(w, h));
    }
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(noFill: true, commands: cmds),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// Thick backbone / bus line (misc).
  static VsdxShape backbone({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    bool vertical = false,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    final cmds = vertical
        ? <VsdxPathCommand>[
            MoveTo(w * 0.2, 0),
            LineTo(w * 0.8, 0),
            LineTo(w * 0.8, h),
            LineTo(w * 0.2, h),
            LineTo(w * 0.2, 0),
          ]
        : <VsdxPathCommand>[
            MoveTo(0, h * 0.2),
            LineTo(w, h * 0.2),
            LineTo(w, h * 0.8),
            LineTo(0, h * 0.8),
            LineTo(0, h * 0.2),
          ];
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

  /// Zigzag polyline (misc).
  static VsdxShape zigzag({
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
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, h * 0.2),
            LineTo(w * 0.25, h * 0.8),
            LineTo(w * 0.5, h * 0.2),
            LineTo(w * 0.75, h * 0.8),
            LineTo(w, h * 0.2),
          ],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// Connection waypoint / junction dot (misc).
  static VsdxShape waypoint({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) =>
      ellipse(
        id: id,
        pinX: pinX,
        pinY: pinY,
        width: width,
        height: height,
        fill: fill,
        line: line,
        name: name,
      );

  /// Isometric square / diamond-ish iso rectangle (misc).
  static VsdxShape isometricSquare({
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
          LineTo(w, h * 0.5),
          LineTo(w / 2, 0),
          LineTo(0, h * 0.5),
          LineTo(w / 2, h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Double rounded rectangle (advanced).
  static VsdxShape doubleRoundedRectangle({
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
    final r = math.min(w, h) * 0.18;
    final inset = math.min(w, h) * 0.12;
    final ri = math.max(r * 0.55, 0.02);
    List<VsdxPathCommand> rr(
        double x0, double y0, double x1, double y1, double rad) {
      return <VsdxPathCommand>[
        MoveTo(x0 + rad, y1),
        LineTo(x1 - rad, y1),
        EllipticalArcTo(x: x1, y: y1 - rad, controlX: x1, controlY: y1),
        LineTo(x1, y0 + rad),
        EllipticalArcTo(x: x1 - rad, y: y0, controlX: x1, controlY: y0),
        LineTo(x0 + rad, y0),
        EllipticalArcTo(x: x0, y: y0 + rad, controlX: x0, controlY: y0),
        LineTo(x0, y1 - rad),
        EllipticalArcTo(x: x0 + rad, y: y1, controlX: x0, controlY: y1),
      ];
    }

    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: rr(0, 0, w, h, r)),
        VsdxGeometry(
          noFill: true,
          commands: rr(inset, inset, w - inset, h - inset, ri),
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Process bar: chevron chain (advanced).
  static VsdxShape processBar({
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
    final seg = w / 3;
    final tip = seg * 0.22;
    VsdxGeometry chevron(double x0) {
      return VsdxGeometry(commands: <VsdxPathCommand>[
        MoveTo(x0, h),
        LineTo(x0 + seg - tip, h),
        LineTo(x0 + seg, h / 2),
        LineTo(x0 + seg - tip, 0),
        LineTo(x0, 0),
        LineTo(x0 + tip, h / 2),
        LineTo(x0, h),
      ]);
    }

    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        chevron(0),
        chevron(seg),
        chevron(2 * seg),
      ],
      fill: fill,
      line: line,
    );
  }

  /// List item row (advanced / ER table seed).
  static VsdxShape listItem({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    String? name,
    String text = 'List Item',
  }) =>
      textBox(
        id: id,
        pinX: pinX,
        pinY: pinY,
        width: width,
        height: height,
        text: text,
        name: name,
      );

  /// Freehand / scribble stroke (drawio Freehand): a plain 1-D polyline
  /// through page-space [points] (≥2). Not a glueable connector — no
  /// `ObjType=2` / connector dynamics — so Visio treats it as ink.
  static VsdxShape freehand({
    required int id,
    required List<Offset2D> points,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    if (points.length < 2) {
      throw ArgumentError.value(points, 'points', 'need at least 2 points');
    }
    var minX = points.first.x, maxX = points.first.x;
    var minY = points.first.y, maxY = points.first.y;
    for (final p in points) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
    // Degenerate scribbles (all points coincide) get a tiny box so the shape
    // still has a non-zero hit target after save.
    final w = math.max(maxX - minX, 1e-3);
    final h = math.max(maxY - minY, 1e-3);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: (minX + maxX) / 2,
      pinY: (minY + maxY) / 2,
      width: w,
      height: h,
      is1D: true,
      // Explicit shape (not connector): writer defaults null+is1D → ObjType=2.
      objType: 1,
      beginX: points.first.x,
      beginY: points.first.y,
      endX: points.last.x,
      endY: points.last.y,
      noAlignBox: true,
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          commands: <VsdxPathCommand>[
            MoveTo(points.first.x - minX, points.first.y - minY),
            for (final p in points.skip(1))
              LineTo(p.x - minX, p.y - minY),
          ],
          noFill: true,
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// Straight 1-D line from page point ([ax],[ay]) to ([bx],[by]) (inches).
  ///
  /// Emits Edraw/Visio-friendly Pin formulas and connector dynamics so 万兴图示
  /// treats the edge as a glueable connector (not a static stroke).
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
      noAlignBox: true,
      shapeSplittable: true,
      formulas: const <String, String>{
        'PinX': '(BeginX+EndX)*0.5',
        'PinY': '(BeginY+EndY)*0.5',
      },
      connectorProps: const VsdxConnectorProps(
        glueType: 2,
        conFixedCode: 0,
        dynFeedback: 2,
        noLiveDynamics: true,
        conLineRouteExt: 1,
        shapeRouteStyle: 16,
      ),
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
