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
import 'image.dart';
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
  /// (e.g. `/visio/media/image7.png`). Includes a rectangular geometry frame
  /// for hit-testing / Edraw-Visio import, and the writer emits MS-VSDX
  /// `ImgOffset*` / `ImgWidth` / `ImgHeight` plus `<ForeignData>`.
  static VsdxShape picture({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    required String imagePartName,
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
          // Frame matches the image box; NoFill/NoLine so only the bitmap shows.
          noFill: true,
          noLine: true,
          commands: <VsdxPathCommand>[
            const MoveTo(0, 0),
            LineTo(w, 0),
            LineTo(w, h),
            LineTo(0, h),
            const LineTo(0, 0),
          ],
        ),
      ],
      imagePartName: imagePartName,
      foreignType: VsdxImage.foreignTypeFor(mimeType: '', partName: imagePartName),
      foreignCompressionType:
          VsdxImage.compressionTypeFor(mimeType: '', partName: imagePartName),
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
          noFill: true,
          hitBox: true,
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
          noFill: true,
          hitBox: true,
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
  /// Open-sided rectangle (drawio `shape=partialRectangle`). Each of
  /// [top]/[right]/[bottom]/[left] toggles whether that border edge is
  /// stroked. The default (every side but [top]) reproduces drawio's
  /// `top=0` ∪ variant; e.g. `left=false,right=false` draws only the top
  /// and bottom rails, `top=false,bottom=false` only the two verticals.
  static VsdxShape partialRectangle({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    bool top = false,
    bool right = true,
    bool bottom = true,
    bool left = true,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    // Walk the border counter-clockwise from the top-left corner. A MoveTo is
    // emitted only when the pen was lifted (an edge was skipped), so adjacent
    // drawn edges remain a single connected sub-path (the all-but-top default
    // stays byte-identical to the historical ∪ path).
    final edges = <List<double>>[
      <double>[0, h, 0, 0, left ? 1 : 0], // left  : TL → BL
      <double>[0, 0, w, 0, bottom ? 1 : 0], // bottom: BL → BR
      <double>[w, 0, w, h, right ? 1 : 0], // right : BR → TR
      <double>[w, h, 0, h, top ? 1 : 0], // top   : TR → TL
    ];
    final commands = <VsdxPathCommand>[];
    double? curX, curY;
    for (final e in edges) {
      if (e[4] == 0) {
        curX = null;
        curY = null;
        continue;
      }
      if (curX != e[0] || curY != e[1]) commands.add(MoveTo(e[0], e[1]));
      commands.add(LineTo(e[2], e[3]));
      curX = e[2];
      curY = e[3];
    }
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(noFill: true, commands: commands),
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
    // Two NoFill=0 ellipses become one evenodd path in canvas, SVG and
    // libvisio `_fillAndShadowProperties` (`svg:fill-rule=evenodd`), which
    // punches the inner disk into a ring. Outer stroke + inner fill keeps
    // the filled terminate marker Draw will collect.
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
            EllipseCmd(
                cx: w / 2, cy: h / 2, aX: w, aY: h / 2, bX: w / 2, bY: 0),
          ],
        ),
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
      // Keep the semantic type detectable after a VSDX writer round-trip.
      // Empty containers have neither a Master nor nested <Shapes> to hint it.
      name: name ?? 'Container.$id',
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

  /// Parallelepiped / oblique 3-D box (drawio basic `Parallelepiped`),
  /// drawn with visible top and right faces so it reads as a solid rather
  /// than a plain parallelogram.
  static VsdxShape parallelepiped({
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
    final d = math.min(w, h) * 0.28;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        // Outer silhouette.
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, 0),
          LineTo(w - d, 0),
          LineTo(w, d),
          LineTo(w, h),
          LineTo(d, h),
          LineTo(0, h - d),
          LineTo(0, 0),
        ]),
        // Front-face top and right inner edges (the L-shaped junction).
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, h - d),
          LineTo(w - d, h - d),
          LineTo(w - d, 0),
        ]),
        // Diagonal from the junction to the back top-right corner.
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(w - d, h - d),
          LineTo(w, h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Rounded rectangular callout / speech bubble (drawio basic
  /// `Rounded Rectangular Callout`): a rounded-corner body with a tail
  /// pointing to the bottom-left.
  static VsdxShape roundedRectangularCallout({
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
    final by = h * 0.28; // body bottom edge (tail occupies the strip below).
    final bodyH = h - by;
    final r = math.min(w, bodyH) * 0.18;
    final tailRight = (w * 0.42).clamp(r, w - r).toDouble();
    final tailLeft = (w * 0.24).clamp(r, w - r).toDouble();
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
          LineTo(w, by + r),
          EllipticalArcTo(x: w - r, y: by, controlX: w, controlY: by),
          LineTo(tailRight, by),
          LineTo(w * 0.08, 0),
          LineTo(tailLeft, by),
          LineTo(r, by),
          EllipticalArcTo(x: 0, y: by + r, controlX: 0, controlY: by),
          LineTo(0, h - r),
          EllipticalArcTo(x: r, y: h, controlX: 0, controlY: h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Stacked list container (drawio general/advanced `List` and misc
  /// `Vertical List`): a titled box divided into three item rows.
  static VsdxShape list({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? text,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    final titleY = h * 0.72; // divider under the title band.
    final row1 = titleY * (2 / 3);
    final row2 = titleY * (1 / 3);
    VsdxGeometry rail(double y) => VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[MoveTo(0, y), LineTo(w, y)],
        );
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      text: text,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
        rail(titleY),
        rail(row1),
        rail(row2),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Image / icon placeholder (drawio misc `Image`): a frame containing a
  /// simple mountains-and-sun glyph.
  static VsdxShape imagePlaceholder({
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
    final sun = math.min(w, h) * 0.09;
    final sx = w * 0.70;
    final sy = h * 0.70;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        // Frame.
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
        // Sun.
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            EllipseCmd(cx: sx, cy: sy, aX: sx + sun, aY: sy, bX: sx, bY: sy + sun),
          ],
        ),
        // Mountain range.
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(w * 0.08, h * 0.30),
          LineTo(w * 0.30, h * 0.62),
          LineTo(w * 0.45, h * 0.45),
          LineTo(w * 0.68, h * 0.75),
          LineTo(w * 0.92, h * 0.30),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  // --- Network shapes (drawio `mxgraph.networks`) -------------------------
  // Clean, recognisable geometric renderings of the common vendor-neutral
  // network devices; silhouettes follow draw.io's networks library.

  /// Server tower: tall box with slot rails and a status LED.
  static VsdxShape networkServer({
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
          MoveTo(0.24 * w, 0),
          LineTo(0.76 * w, 0),
          LineTo(0.76 * w, h),
          LineTo(0.24 * w, h),
          LineTo(0.24 * w, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.32 * w, 0.86 * h),
          LineTo(0.68 * w, 0.86 * h),
          MoveTo(0.32 * w, 0.74 * h),
          LineTo(0.68 * w, 0.74 * h),
        ]),
        // LED used to be NoFill=0, which evenodd-punched a hole through
        // the chassis in canvas, SVG and libvisio `_fillAndShadowProperties`.
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0.32 * w, 0.1 * h),
            LineTo(0.44 * w, 0.1 * h),
            LineTo(0.44 * w, 0.18 * h),
            LineTo(0.32 * w, 0.18 * h),
            LineTo(0.32 * w, 0.1 * h),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Firewall: an offset brick wall.
  static VsdxShape networkFirewall({
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
    const rows = 4;
    final rh = h / rows;
    final mortar = <VsdxPathCommand>[];
    for (var i = 1; i < rows; i++) {
      mortar
        ..add(MoveTo(0, i * rh))
        ..add(LineTo(w, i * rh));
    }
    for (var r = 0; r < rows; r++) {
      final y0 = r * rh;
      final y1 = (r + 1) * rh;
      // Even rows split in thirds; odd rows offset by half a brick.
      final xs = r.isEven
          ? <double>[w / 3, 2 * w / 3]
          : <double>[w / 6, w / 2, 5 * w / 6];
      for (final x in xs) {
        mortar
          ..add(MoveTo(x, y0))
          ..add(LineTo(x, y1));
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
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(noFill: true, commands: mortar),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Smartphone / mobile: rounded body, screen, speaker and home button.
  static VsdxShape networkMobile({
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
    final r = 0.12 * w;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.18 * w + r, h),
          LineTo(0.82 * w - r, h),
          EllipticalArcTo(x: 0.82 * w, y: h - r, controlX: 0.82 * w, controlY: h),
          LineTo(0.82 * w, r),
          EllipticalArcTo(x: 0.82 * w - r, y: 0, controlX: 0.82 * w, controlY: 0),
          LineTo(0.18 * w + r, 0),
          EllipticalArcTo(x: 0.18 * w, y: r, controlX: 0.18 * w, controlY: 0),
          LineTo(0.18 * w, h - r),
          EllipticalArcTo(x: 0.18 * w + r, y: h, controlX: 0.18 * w, controlY: h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.26 * w, 0.14 * h),
          LineTo(0.74 * w, 0.14 * h),
          LineTo(0.74 * w, 0.86 * h),
          LineTo(0.26 * w, 0.86 * h),
          LineTo(0.26 * w, 0.14 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.43 * w, 0.93 * h),
          LineTo(0.57 * w, 0.93 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.07 * h,
              aX: 0.53 * w,
              aY: 0.07 * h,
              bX: 0.5 * w,
              bY: 0.1 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Desktop monitor: screen with inner bezel, neck and base.
  static VsdxShape networkMonitor({
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
          MoveTo(0.05 * w, 0.32 * h),
          LineTo(0.95 * w, 0.32 * h),
          LineTo(0.95 * w, h),
          LineTo(0.05 * w, h),
          LineTo(0.05 * w, 0.32 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.12 * w, 0.42 * h),
          LineTo(0.88 * w, 0.42 * h),
          LineTo(0.88 * w, 0.92 * h),
          LineTo(0.12 * w, 0.92 * h),
          LineTo(0.12 * w, 0.42 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.43 * w, 0.1 * h),
          LineTo(0.57 * w, 0.1 * h),
          LineTo(0.57 * w, 0.32 * h),
          LineTo(0.43 * w, 0.32 * h),
          LineTo(0.43 * w, 0.1 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.28 * w, 0),
          LineTo(0.72 * w, 0),
          LineTo(0.72 * w, 0.1 * h),
          LineTo(0.28 * w, 0.1 * h),
          LineTo(0.28 * w, 0),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Laptop: screen over a tapered keyboard base.
  static VsdxShape networkLaptop({
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
          MoveTo(0.17 * w, 0.32 * h),
          LineTo(0.83 * w, 0.32 * h),
          LineTo(0.83 * w, h),
          LineTo(0.17 * w, h),
          LineTo(0.17 * w, 0.32 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.23 * w, 0.4 * h),
          LineTo(0.77 * w, 0.4 * h),
          LineTo(0.77 * w, 0.92 * h),
          LineTo(0.23 * w, 0.92 * h),
          LineTo(0.23 * w, 0.4 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.05 * w, 0),
          LineTo(0.95 * w, 0),
          LineTo(0.83 * w, 0.32 * h),
          LineTo(0.17 * w, 0.32 * h),
          LineTo(0.05 * w, 0),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Printer: body with paper feed and an output tray.
  static VsdxShape networkPrinter({
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
        // Paper feed (behind body).
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.28 * w, 0.6 * h),
          LineTo(0.28 * w, 0.95 * h),
          LineTo(0.72 * w, 0.95 * h),
          LineTo(0.72 * w, 0.6 * h),
        ]),
        // Body.
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.08 * w, 0.14 * h),
          LineTo(0.92 * w, 0.14 * h),
          LineTo(0.92 * w, 0.62 * h),
          LineTo(0.08 * w, 0.62 * h),
          LineTo(0.08 * w, 0.14 * h),
        ]),
        // Output tray (front, on top of body).
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.24 * w, 0),
          LineTo(0.76 * w, 0),
          LineTo(0.76 * w, 0.2 * h),
          LineTo(0.24 * w, 0.2 * h),
          LineTo(0.24 * w, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.16 * w, 0.44 * h),
          LineTo(0.84 * w, 0.44 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Wireless signal: stacked arcs over an emitter dot.
  static VsdxShape networkWireless({
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
    final cx = 0.5 * w;
    final cy = 0.12 * h;
    final hw = <double>[0.22 * w, 0.35 * w, 0.48 * w];
    // Arc apex height ≈ half-width keeps the sweep close to a semicircle
    // rather than the pointed peak a taller quadratic control would give.
    final ph = <double>[0.22 * h, 0.35 * h, 0.48 * h];
    final arcs = <VsdxGeometry>[
      for (var i = 0; i < 3; i++)
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(cx - hw[i], cy),
          EllipticalArcTo(
              x: cx + hw[i], y: cy, controlX: cx, controlY: cy + ph[i]),
        ]),
    ];
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
              cy: cy,
              aX: cx + 0.06 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.06 * h),
        ]),
        ...arcs,
      ],
      fill: fill,
      line: line,
    );
  }

  /// Router: flat box with two antennas and status ports.
  static VsdxShape networkRouter({
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
          MoveTo(0.12 * w, 0.12 * h),
          LineTo(0.88 * w, 0.12 * h),
          LineTo(0.88 * w, 0.55 * h),
          LineTo(0.12 * w, 0.55 * h),
          LineTo(0.12 * w, 0.12 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.34 * w, 0.55 * h),
          LineTo(0.27 * w, 0.96 * h),
          MoveTo(0.62 * w, 0.55 * h),
          LineTo(0.69 * w, 0.96 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.22 * w, 0.3 * h),
          LineTo(0.5 * w, 0.3 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Network switch: flat chassis with a row of RJ-45 ports.
  static VsdxShape networkSwitch({
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
    final ports = <VsdxPathCommand>[];
    const n = 6;
    final gap = w * 0.04;
    final pw = (w * 0.8 - gap * (n - 1)) / n;
    final ph = h * 0.28;
    final y0 = h * 0.22;
    var x = w * 0.1;
    for (var i = 0; i < n; i++) {
      ports
        ..add(MoveTo(x, y0))
        ..add(LineTo(x + pw, y0))
        ..add(LineTo(x + pw, y0 + ph))
        ..add(LineTo(x, y0 + ph))
        ..add(LineTo(x, y0));
      x += pw + gap;
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
          MoveTo(0.05 * w, 0.12 * h),
          LineTo(0.95 * w, 0.12 * h),
          LineTo(0.95 * w, 0.88 * h),
          LineTo(0.05 * w, 0.88 * h),
          LineTo(0.05 * w, 0.12 * h),
        ]),
        VsdxGeometry(noFill: true, commands: ports),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.12 * w, 0.72 * h),
          LineTo(0.28 * w, 0.72 * h),
          EllipseCmd(
              cx: 0.82 * w,
              cy: 0.72 * h,
              aX: 0.85 * w,
              aY: 0.72 * h,
              bX: 0.82 * w,
              bY: 0.78 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Network hub: round body with radiating spoke ports.
  static VsdxShape networkHub({
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
    final cx = w / 2;
    final cy = h / 2;
    final spokes = <VsdxPathCommand>[];
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      spokes
        ..add(MoveTo(cx, cy))
        ..add(LineTo(cx + 0.42 * w * math.cos(a), cy + 0.42 * h * math.sin(a)));
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
          EllipseCmd(cx: cx, cy: cy, aX: w, aY: cy, bX: cx, bY: 0),
        ]),
        VsdxGeometry(noFill: true, commands: spokes),
        // Inner disc used to be NoFill=0, which evenodd-punched a hole through
        // the hub in canvas, SVG and libvisio `_fillAndShadowProperties`.
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: cx,
                cy: cy,
                aX: cx + 0.12 * w,
                aY: cy,
                bX: cx,
                bY: cy + 0.12 * h),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Desktop PC: tower + monitor silhouette.
  static VsdxShape networkPc({
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
        // Monitor.
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.28 * w, 0.38 * h),
          LineTo(0.95 * w, 0.38 * h),
          LineTo(0.95 * w, h),
          LineTo(0.28 * w, h),
          LineTo(0.28 * w, 0.38 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.35 * w, 0.48 * h),
          LineTo(0.88 * w, 0.48 * h),
          LineTo(0.88 * w, 0.9 * h),
          LineTo(0.35 * w, 0.9 * h),
          LineTo(0.35 * w, 0.48 * h),
        ]),
        // Stand.
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.55 * w, 0.22 * h),
          LineTo(0.68 * w, 0.22 * h),
          LineTo(0.68 * w, 0.38 * h),
          LineTo(0.55 * w, 0.38 * h),
          LineTo(0.55 * w, 0.22 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.45 * w, 0.12 * h),
          LineTo(0.78 * w, 0.12 * h),
          LineTo(0.78 * w, 0.22 * h),
          LineTo(0.45 * w, 0.22 * h),
          LineTo(0.45 * w, 0.12 * h),
        ]),
        // Tower.
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.05 * w, 0),
          LineTo(0.28 * w, 0),
          LineTo(0.28 * w, 0.72 * h),
          LineTo(0.05 * w, 0.72 * h),
          LineTo(0.05 * w, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.1 * w, 0.55 * h),
          LineTo(0.23 * w, 0.55 * h),
          MoveTo(0.1 * w, 0.42 * h),
          LineTo(0.23 * w, 0.42 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  // --- Mockup (drawio mxgraph.mockup.*) ------------------------------------

  /// Checkbox (on): square with a tick.
  static VsdxShape mockupCheckbox({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    bool checked = true,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    final geos = <VsdxGeometry>[
      VsdxGeometry(commands: <VsdxPathCommand>[
        MoveTo(0, 0),
        LineTo(w, 0),
        LineTo(w, h),
        LineTo(0, h),
        LineTo(0, 0),
      ]),
    ];
    if (checked) {
      geos.add(VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
        MoveTo(0.18 * w, 0.5 * h),
        LineTo(0.4 * w, 0.22 * h),
        LineTo(0.82 * w, 0.78 * h),
      ]));
    }
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: geos,
      fill: fill,
      line: line,
    );
  }

  /// Radio button (on): circle with filled centre.
  static VsdxShape mockupRadio({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    bool selected = true,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    final cx = w / 2;
    final cy = h / 2;
    // Two NoFill=0 ellipses become one evenodd path in canvas, SVG and
    // libvisio `_fillAndShadowProperties` (`svg:fill-rule=evenodd`), which
    // punches the centre into a ring. Outer stroke + inner fill keeps the
    // selected disc Draw will collect.
    final geos = <VsdxGeometry>[
      VsdxGeometry(
        noFill: true,
        commands: <VsdxPathCommand>[
          EllipseCmd(cx: cx, cy: cy, aX: w, aY: cy, bX: cx, bY: 0),
        ],
      ),
    ];
    if (selected) {
      geos.add(VsdxGeometry(commands: <VsdxPathCommand>[
        EllipseCmd(
            cx: cx,
            cy: cy,
            aX: cx + 0.28 * w,
            aY: cy,
            bX: cx,
            bY: cy + 0.28 * h),
      ]));
    }
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: geos,
      fill: fill,
      line: line,
    );
  }

  /// Text field / input box with a caret hint.
  static VsdxShape mockupTextField({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
    String text = '',
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
      text: text,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.08 * w, 0.22 * h),
          LineTo(0.08 * w, 0.78 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Combo / select field with a drop-down chevron.
  static VsdxShape mockupComboBox({
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
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.78 * w, 0),
          LineTo(0.78 * w, h),
          MoveTo(0.84 * w, 0.62 * h),
          LineTo(0.89 * w, 0.38 * h),
          LineTo(0.94 * w, 0.62 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Application window with title bar and close chrome.
  static VsdxShape mockupWindow({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
    String text = 'Window',
  }) {
    final w = width.abs();
    final h = height.abs();
    final title = 0.18 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      text: text,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, h - title),
          LineTo(w, h - title),
          MoveTo(0.82 * w, h - title * 0.35),
          LineTo(0.9 * w, h - title * 0.65),
          MoveTo(0.82 * w, h - title * 0.65),
          LineTo(0.9 * w, h - title * 0.35),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Horizontal progress / loading bar.
  static VsdxShape mockupProgressBar({
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
    // Two NoFill=0 rectangles become one evenodd path in canvas, SVG and
    // libvisio `_fillAndShadowProperties` (`svg:fill-rule=evenodd`), which
    // punches the 55% overlap into an inverted empty track. Stroke the
    // full track and fill the progress so Draw keeps the bar.
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
            MoveTo(0, 0),
            LineTo(w, 0),
            LineTo(w, h),
            LineTo(0, h),
            LineTo(0, 0),
          ],
        ),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, 0),
          LineTo(0.55 * w, 0),
          LineTo(0.55 * w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Horizontal slider with track and thumb.
  static VsdxShape mockupSlider({
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
    final cy = h / 2;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.05 * w, cy),
          LineTo(0.95 * w, cy),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.45 * w,
              cy: cy,
              aX: 0.45 * w + 0.12 * h,
              aY: cy,
              bX: 0.45 * w,
              bY: cy + 0.12 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Horizontal tab bar with three tabs.
  static VsdxShape mockupTabBar({
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
    final th = 0.45 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h - th),
          LineTo(0, h - th),
          LineTo(0, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, h - th),
          LineTo(0, h),
          LineTo(0.3 * w, h),
          LineTo(0.3 * w, h - th),
          MoveTo(0.32 * w, h - th),
          LineTo(0.32 * w, h),
          LineTo(0.62 * w, h),
          LineTo(0.62 * w, h - th),
          MoveTo(0.64 * w, h - th),
          LineTo(0.64 * w, h),
          LineTo(0.94 * w, h),
          LineTo(0.94 * w, h - th),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Menu bar: strip with three item separators.
  static VsdxShape mockupMenuBar({
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
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.28 * w, 0.2 * h),
          LineTo(0.28 * w, 0.8 * h),
          MoveTo(0.52 * w, 0.2 * h),
          LineTo(0.52 * w, 0.8 * h),
          MoveTo(0.76 * w, 0.2 * h),
          LineTo(0.76 * w, 0.8 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// On/Off toggle switch.
  static VsdxShape mockupToggle({
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
    final r = h / 2;
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
          EllipticalArcTo(x: w, y: r, controlX: w, controlY: h),
          EllipticalArcTo(x: w - r, y: 0, controlX: w, controlY: 0),
          LineTo(r, 0),
          EllipticalArcTo(x: 0, y: r, controlX: 0, controlY: 0),
          EllipticalArcTo(x: r, y: h, controlX: 0, controlY: h),
        ]),
        // Thumb used to be NoFill=0, which evenodd-punched a hole through the
        // track in canvas, SVG and libvisio `_fillAndShadowProperties`.
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: 0.72 * w,
                cy: r,
                aX: 0.72 * w + 0.35 * r,
                aY: r,
                bX: 0.72 * w,
                bY: r + 0.35 * r),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  // --- Electrical (drawio mxgraph.electrical.*) ----------------------------

  /// IEEE-style resistor zigzag.
  static VsdxShape electricalResistor({
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
    final mid = h / 2;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, mid),
          LineTo(0.12 * w, mid),
          LineTo(0.2 * w, h),
          LineTo(0.32 * w, 0),
          LineTo(0.44 * w, h),
          LineTo(0.56 * w, 0),
          LineTo(0.68 * w, h),
          LineTo(0.8 * w, 0),
          LineTo(0.88 * w, mid),
          LineTo(w, mid),
        ]),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// Capacitor: two parallel plates with leads.
  static VsdxShape electricalCapacitor({
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
    final mid = h / 2;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, mid),
          LineTo(0.38 * w, mid),
          MoveTo(0.38 * w, 0.1 * h),
          LineTo(0.38 * w, 0.9 * h),
          MoveTo(0.62 * w, 0.1 * h),
          LineTo(0.62 * w, 0.9 * h),
          MoveTo(0.62 * w, mid),
          LineTo(w, mid),
        ]),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// Inductor: series of loops.
  static VsdxShape electricalInductor({
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
    final mid = h / 2;
    final cmds = <VsdxPathCommand>[MoveTo(0, mid), LineTo(0.12 * w, mid)];
    for (var i = 0; i < 4; i++) {
      final x0 = (0.12 + i * 0.18) * w;
      final x1 = x0 + 0.18 * w;
      cmds.add(EllipticalArcTo(
          x: x1, y: mid, controlX: (x0 + x1) / 2, controlY: h * 0.95));
    }
    cmds.add(LineTo(w, mid));
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

  /// Diode: triangle + cathode bar.
  static VsdxShape electricalDiode({
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
    final mid = h / 2;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.28 * w, 0),
          LineTo(0.72 * w, mid),
          LineTo(0.28 * w, h),
          LineTo(0.28 * w, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, mid),
          LineTo(0.28 * w, mid),
          MoveTo(0.72 * w, 0.12 * h),
          LineTo(0.72 * w, 0.88 * h),
          MoveTo(0.72 * w, mid),
          LineTo(w, mid),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Earth / ground symbol (three descending bars).
  static VsdxShape electricalGround({
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.5 * w, h),
          LineTo(0.5 * w, 0.55 * h),
          MoveTo(0.15 * w, 0.55 * h),
          LineTo(0.85 * w, 0.55 * h),
          MoveTo(0.28 * w, 0.32 * h),
          LineTo(0.72 * w, 0.32 * h),
          MoveTo(0.4 * w, 0.1 * h),
          LineTo(0.6 * w, 0.1 * h),
        ]),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// Battery: long / short plate pair with leads.
  static VsdxShape electricalBattery({
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
    final mid = h / 2;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, mid),
          LineTo(0.28 * w, mid),
          MoveTo(0.28 * w, 0.15 * h),
          LineTo(0.28 * w, 0.85 * h),
          MoveTo(0.42 * w, 0.35 * h),
          LineTo(0.42 * w, 0.65 * h),
          MoveTo(0.56 * w, 0.15 * h),
          LineTo(0.56 * w, 0.85 * h),
          MoveTo(0.7 * w, 0.35 * h),
          LineTo(0.7 * w, 0.65 * h),
          MoveTo(0.7 * w, mid),
          LineTo(w, mid),
        ]),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// LED: diode body with two emission arrows.
  static VsdxShape electricalLed({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final diode = electricalDiode(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      fill: fill,
      line: line,
      name: name,
    );
    final w = width.abs();
    final h = height.abs();
    return diode.copyWith(geometries: <VsdxGeometry>[
      ...diode.geometries,
      VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
        MoveTo(0.52 * w, 0.92 * h),
        LineTo(0.68 * w, 0.78 * h),
        MoveTo(0.58 * w, 0.98 * h),
        LineTo(0.74 * w, 0.84 * h),
      ]),
    ]);
  }

  /// Transformer: two inductor coils with a core bar.
  static VsdxShape electricalTransformer({
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.22 * w, 0),
          LineTo(0.22 * w, 0.15 * h),
          EllipticalArcTo(
              x: 0.22 * w, y: 0.35 * h, controlX: 0.08 * w, controlY: 0.25 * h),
          EllipticalArcTo(
              x: 0.22 * w, y: 0.55 * h, controlX: 0.08 * w, controlY: 0.45 * h),
          EllipticalArcTo(
              x: 0.22 * w, y: 0.75 * h, controlX: 0.08 * w, controlY: 0.65 * h),
          LineTo(0.22 * w, h),
          MoveTo(0.78 * w, 0),
          LineTo(0.78 * w, 0.15 * h),
          EllipticalArcTo(
              x: 0.78 * w, y: 0.35 * h, controlX: 0.92 * w, controlY: 0.25 * h),
          EllipticalArcTo(
              x: 0.78 * w, y: 0.55 * h, controlX: 0.92 * w, controlY: 0.45 * h),
          EllipticalArcTo(
              x: 0.78 * w, y: 0.75 * h, controlX: 0.92 * w, controlY: 0.65 * h),
          LineTo(0.78 * w, h),
          MoveTo(0.45 * w, 0.12 * h),
          LineTo(0.45 * w, 0.88 * h),
          MoveTo(0.55 * w, 0.12 * h),
          LineTo(0.55 * w, 0.88 * h),
        ]),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// AC source: circle with sine wave.
  static VsdxShape electricalAcSource({
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
    final cx = w / 2;
    final cy = h / 2;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(cx: cx, cy: cy, aX: w, aY: cy, bX: cx, bY: 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.22 * w, cy),
          EllipticalArcTo(
              x: 0.5 * w, y: cy, controlX: 0.36 * w, controlY: 0.78 * h),
          EllipticalArcTo(
              x: 0.78 * w, y: cy, controlX: 0.64 * w, controlY: 0.22 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Electrical SPST switch (open contact).
  static VsdxShape electricalSwitch({
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
    final mid = h / 2;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, mid),
          LineTo(0.28 * w, mid),
          EllipseCmd(
              cx: 0.32 * w,
              cy: mid,
              aX: 0.36 * w,
              aY: mid,
              bX: 0.32 * w,
              bY: mid + 0.08 * h),
          MoveTo(0.32 * w, mid),
          LineTo(0.72 * w, 0.85 * h),
          EllipseCmd(
              cx: 0.76 * w,
              cy: mid,
              aX: 0.8 * w,
              aY: mid,
              bX: 0.76 * w,
              bY: mid + 0.08 * h),
          MoveTo(0.76 * w, mid),
          LineTo(w, mid),
        ]),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  // --- Signs (drawio mxGraph.signs.*) --------------------------------------

  /// Warning triangle with exclamation mark.
  static VsdxShape signWarning({
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
          MoveTo(0.5 * w, h),
          LineTo(w, 0),
          LineTo(0, 0),
          LineTo(0.5 * w, h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.5 * w, 0.55 * h),
          LineTo(0.5 * w, 0.28 * h),
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.16 * h,
              aX: 0.5 * w + 0.04 * w,
              aY: 0.16 * h,
              bX: 0.5 * w,
              bY: 0.16 * h + 0.04 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// No Entry: filled circle with a horizontal bar.
  static VsdxShape signNoEntry({
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
    final cx = w / 2;
    final cy = h / 2;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(cx: cx, cy: cy, aX: w, aY: cy, bX: cx, bY: 0),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.4 * h),
          LineTo(0.8 * w, 0.4 * h),
          LineTo(0.8 * w, 0.6 * h),
          LineTo(0.2 * w, 0.6 * h),
          LineTo(0.2 * w, 0.4 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Mandatory action: circle with a filled centre disc.
  static VsdxShape signMandatory({
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
    final cx = w / 2;
    final cy = h / 2;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(cx: cx, cy: cy, aX: w, aY: cy, bX: cx, bY: 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: cy,
              aX: cx + 0.55 * w / 2,
              aY: cy,
              bX: cx,
              bY: cy + 0.55 * h / 2),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Emergency exit: doorway with a running figure arrow.
  static VsdxShape signExit({
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
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.18 * w, 0.15 * h),
          LineTo(0.18 * w, 0.85 * h),
          LineTo(0.55 * w, 0.85 * h),
          LineTo(0.55 * w, 0.15 * h),
          LineTo(0.18 * w, 0.15 * h),
          MoveTo(0.62 * w, 0.5 * h),
          LineTo(0.88 * w, 0.5 * h),
          LineTo(0.78 * w, 0.65 * h),
          MoveTo(0.88 * w, 0.5 * h),
          LineTo(0.78 * w, 0.35 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Radiation trefoil (three blades around a centre).
  static VsdxShape signRadiation({
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
    final cx = w / 2;
    final cy = h / 2;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(cx: cx, cy: cy, aX: w, aY: cy, bX: cx, bY: 0),
        ]),
        // Inner disc used to be NoFill=0, which evenodd-punched a hole through
        // the trefoil in canvas, SVG and libvisio `_fillAndShadowProperties`.
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: cx,
                cy: cy,
                aX: cx + 0.12 * w,
                aY: cy,
                bX: cx,
                bY: cy + 0.12 * h),
          ],
        ),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(cx, cy + 0.12 * h),
          LineTo(cx, 0.92 * h),
          MoveTo(cx + 0.1 * w, cy - 0.06 * h),
          LineTo(0.88 * w, 0.22 * h),
          MoveTo(cx - 0.1 * w, cy - 0.06 * h),
          LineTo(0.12 * w, 0.22 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// First aid: square with a medical cross.
  static VsdxShape signFirstAid({
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
    final t = 0.18;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo((0.5 - t / 2) * w, 0.2 * h),
          LineTo((0.5 + t / 2) * w, 0.2 * h),
          LineTo((0.5 + t / 2) * w, (0.5 - t / 2) * h),
          LineTo(0.8 * w, (0.5 - t / 2) * h),
          LineTo(0.8 * w, (0.5 + t / 2) * h),
          LineTo((0.5 + t / 2) * w, (0.5 + t / 2) * h),
          LineTo((0.5 + t / 2) * w, 0.8 * h),
          LineTo((0.5 - t / 2) * w, 0.8 * h),
          LineTo((0.5 - t / 2) * w, (0.5 + t / 2) * h),
          LineTo(0.2 * w, (0.5 + t / 2) * h),
          LineTo(0.2 * w, (0.5 - t / 2) * h),
          LineTo((0.5 - t / 2) * w, (0.5 - t / 2) * h),
          LineTo((0.5 - t / 2) * w, 0.2 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// High voltage: triangle with a lightning bolt.
  static VsdxShape signHighVoltage({
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
          MoveTo(0.5 * w, h),
          LineTo(w, 0),
          LineTo(0, 0),
          LineTo(0.5 * w, h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.55 * w, 0.72 * h),
          LineTo(0.42 * w, 0.42 * h),
          LineTo(0.52 * w, 0.42 * h),
          LineTo(0.4 * w, 0.18 * h),
          LineTo(0.58 * w, 0.48 * h),
          LineTo(0.48 * w, 0.48 * h),
          LineTo(0.6 * w, 0.72 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Fragile: box with a cracked glass glyph.
  static VsdxShape signFragile({
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
          MoveTo(0.15 * w, 0),
          LineTo(0.85 * w, 0),
          LineTo(0.85 * w, 0.55 * h),
          LineTo(0.7 * w, h),
          LineTo(0.3 * w, h),
          LineTo(0.15 * w, 0.55 * h),
          LineTo(0.15 * w, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.42 * w, 0.75 * h),
          LineTo(0.5 * w, 0.45 * h),
          LineTo(0.58 * w, 0.75 * h),
          MoveTo(0.35 * w, 0.35 * h),
          LineTo(0.5 * w, 0.2 * h),
          LineTo(0.65 * w, 0.35 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  // --- Batch 64 expansions (Network / Mockup / Electrical / Signs) ----------

  /// Tablet: landscape body with a home bar.
  static VsdxShape networkTablet({
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
    final r = 0.08 * math.min(w, h);
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.08 * w, 0.12 * h),
          LineTo(0.92 * w, 0.12 * h),
          LineTo(0.92 * w, 0.88 * h),
          LineTo(0.08 * w, 0.88 * h),
          LineTo(0.08 * w, 0.12 * h),
          MoveTo(0.42 * w, 0.05 * h),
          LineTo(0.58 * w, 0.05 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Desk phone: handset over a base with keypad hint.
  static VsdxShape networkPhone({
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
          MoveTo(0.15 * w, 0),
          LineTo(0.85 * w, 0),
          LineTo(0.9 * w, 0.55 * h),
          LineTo(0.1 * w, 0.55 * h),
          LineTo(0.15 * w, 0),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.22 * w, 0.62 * h),
          LineTo(0.78 * w, 0.62 * h),
          LineTo(0.72 * w, h),
          LineTo(0.28 * w, h),
          LineTo(0.22 * w, 0.62 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.35 * w, 0.72 * h),
          LineTo(0.65 * w, 0.72 * h),
          MoveTo(0.35 * w, 0.82 * h),
          LineTo(0.65 * w, 0.82 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Cable modem / gateway box with LED dots.
  static VsdxShape networkModem({
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
          MoveTo(0.08 * w, 0.2 * h),
          LineTo(0.92 * w, 0.2 * h),
          LineTo(0.92 * w, 0.85 * h),
          LineTo(0.08 * w, 0.85 * h),
          LineTo(0.08 * w, 0.2 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.45 * h),
          LineTo(0.35 * w, 0.45 * h),
          MoveTo(0.45 * w, 0.45 * h),
          LineTo(0.6 * w, 0.45 * h),
          MoveTo(0.7 * w, 0.45 * h),
          LineTo(0.85 * w, 0.45 * h),
          EllipseCmd(
              cx: 0.25 * w,
              cy: 0.65 * h,
              aX: 0.28 * w,
              aY: 0.65 * h,
              bX: 0.25 * w,
              bY: 0.7 * h),
          EllipseCmd(
              cx: 0.4 * w,
              cy: 0.65 * h,
              aX: 0.43 * w,
              aY: 0.65 * h,
              bX: 0.4 * w,
              bY: 0.7 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// External storage / disk array cylinder stack front.
  static VsdxShape networkStorage({
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
          MoveTo(0.12 * w, 0.1 * h),
          LineTo(0.88 * w, 0.1 * h),
          LineTo(0.88 * w, 0.9 * h),
          LineTo(0.12 * w, 0.9 * h),
          LineTo(0.12 * w, 0.1 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.12 * w, 0.35 * h),
          LineTo(0.88 * w, 0.35 * h),
          MoveTo(0.12 * w, 0.6 * h),
          LineTo(0.88 * w, 0.6 * h),
          MoveTo(0.25 * w, 0.2 * h),
          LineTo(0.55 * w, 0.2 * h),
          MoveTo(0.25 * w, 0.45 * h),
          LineTo(0.55 * w, 0.45 * h),
          MoveTo(0.25 * w, 0.7 * h),
          LineTo(0.55 * w, 0.7 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Load balancer: hexagon with left/right arrows.
  static VsdxShape networkLoadBalancer({
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
          MoveTo(0.25 * w, h),
          LineTo(0.75 * w, h),
          LineTo(w, 0.5 * h),
          LineTo(0.75 * w, 0),
          LineTo(0.25 * w, 0),
          LineTo(0, 0.5 * h),
          LineTo(0.25 * w, h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.22 * w, 0.5 * h),
          LineTo(0.42 * w, 0.5 * h),
          LineTo(0.35 * w, 0.62 * h),
          MoveTo(0.42 * w, 0.5 * h),
          LineTo(0.35 * w, 0.38 * h),
          MoveTo(0.58 * w, 0.5 * h),
          LineTo(0.78 * w, 0.5 * h),
          LineTo(0.71 * w, 0.62 * h),
          MoveTo(0.78 * w, 0.5 * h),
          LineTo(0.71 * w, 0.38 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Security camera on a mount arm.
  static VsdxShape networkSecurityCamera({
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
          MoveTo(0.15 * w, 0.35 * h),
          LineTo(0.7 * w, 0.35 * h),
          LineTo(0.85 * w, 0.55 * h),
          LineTo(0.85 * w, 0.8 * h),
          LineTo(0.15 * w, 0.8 * h),
          LineTo(0.15 * w, 0.35 * h),
        ]),
        // Lens used to be NoFill=0, which evenodd-punched a hole through
        // the housing in canvas, SVG and libvisio `_fillAndShadowProperties`.
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: 0.5 * w,
                cy: 0.58 * h,
                aX: 0.62 * w,
                aY: 0.58 * h,
                bX: 0.5 * w,
                bY: 0.72 * h),
          ],
        ),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.35 * w, 0.35 * h),
          LineTo(0.2 * w, 0.1 * h),
          LineTo(0.55 * w, 0.1 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Search box with a magnifying-glass glyph.
  static VsdxShape mockupSearchBox({
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
    final cx = 0.14 * w;
    final cy = 0.5 * h;
    final r = 0.22 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx, cy: cy, aX: cx + r, aY: cy, bX: cx, bY: cy + r),
          MoveTo(cx + 0.7 * r, cy - 0.7 * r),
          LineTo(cx + 1.5 * r, cy - 1.4 * r),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Five-star rating strip.
  static VsdxShape mockupStarRating({
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
    final cmds = <VsdxPathCommand>[];
    for (var i = 0; i < 5; i++) {
      final x0 = (i + 0.1) * w / 5;
      final x1 = (i + 0.9) * w / 5;
      final xm = (x0 + x1) / 2;
      cmds
        ..add(MoveTo(xm, h))
        ..add(LineTo(x1, 0.55 * h))
        ..add(LineTo(x1, 0))
        ..add(LineTo(x0, 0))
        ..add(LineTo(x0, 0.55 * h))
        ..add(LineTo(xm, h));
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

  /// Help icon: circle with a question mark.
  static VsdxShape mockupHelpIcon({
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
    final cx = w / 2;
    final cy = h / 2;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(cx: cx, cy: cy, aX: w, aY: cy, bX: cx, bY: 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.35 * w, 0.62 * h),
          EllipticalArcTo(
              x: 0.5 * w, y: 0.72 * h, controlX: 0.35 * w, controlY: 0.78 * h),
          EllipticalArcTo(
              x: 0.65 * w, y: 0.55 * h, controlX: 0.65 * w, controlY: 0.72 * h),
          LineTo(0.5 * w, 0.42 * h),
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.25 * h,
              aX: 0.54 * w,
              aY: 0.25 * h,
              bX: 0.5 * w,
              bY: 0.3 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Information icon: circle with an "i".
  static VsdxShape mockupInfoIcon({
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
    final cx = w / 2;
    final cy = h / 2;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(cx: cx, cy: cy, aX: w, aY: cy, bX: cx, bY: 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: 0.72 * h,
              aX: cx + 0.05 * w,
              aY: 0.72 * h,
              bX: cx,
              bY: 0.78 * h),
          MoveTo(cx, 0.55 * h),
          LineTo(cx, 0.22 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Loading spinner: open arc circle.
  static VsdxShape mockupLoadingCircle({
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.85 * w, 0.5 * h),
          EllipticalArcTo(
              x: 0.5 * w, y: 0.85 * h, controlX: 0.85 * w, controlY: 0.85 * h),
          EllipticalArcTo(
              x: 0.15 * w, y: 0.5 * h, controlX: 0.15 * w, controlY: 0.85 * h),
          EllipticalArcTo(
              x: 0.5 * w, y: 0.15 * h, controlX: 0.15 * w, controlY: 0.15 * h),
        ]),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// Horizontal splitter / resize handle.
  static VsdxShape mockupHorizontalSplitter({
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
    final mid = h / 2;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, mid),
          LineTo(w, mid),
          MoveTo(0.42 * w, 0.2 * h),
          LineTo(0.5 * w, 0.05 * h),
          LineTo(0.58 * w, 0.2 * h),
          MoveTo(0.42 * w, 0.8 * h),
          LineTo(0.5 * w, 0.95 * h),
          LineTo(0.58 * w, 0.8 * h),
        ]),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// Dropdown menu panel with three rows.
  static VsdxShape mockupDropdownMenu({
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
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, 0.67 * h),
          LineTo(w, 0.67 * h),
          MoveTo(0, 0.33 * h),
          LineTo(w, 0.33 * h),
          MoveTo(0.12 * w, 0.78 * h),
          LineTo(0.7 * w, 0.78 * h),
          MoveTo(0.12 * w, 0.5 * h),
          LineTo(0.7 * w, 0.5 * h),
          MoveTo(0.12 * w, 0.18 * h),
          LineTo(0.7 * w, 0.18 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Fuse: rectangle between leads with an S filament.
  static VsdxShape electricalFuse({
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
    final mid = h / 2;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, mid),
          LineTo(0.2 * w, mid),
          MoveTo(0.2 * w, 0.25 * h),
          LineTo(0.8 * w, 0.25 * h),
          LineTo(0.8 * w, 0.75 * h),
          LineTo(0.2 * w, 0.75 * h),
          LineTo(0.2 * w, 0.25 * h),
          MoveTo(0.28 * w, mid),
          EllipticalArcTo(
              x: 0.5 * w, y: mid, controlX: 0.39 * w, controlY: 0.55 * h),
          EllipticalArcTo(
              x: 0.72 * w, y: mid, controlX: 0.61 * w, controlY: 0.45 * h),
          MoveTo(0.8 * w, mid),
          LineTo(w, mid),
        ]),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// DC source: circle with + / − marks.
  static VsdxShape electricalDcSource({
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
    final cx = w / 2;
    final cy = h / 2;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(cx: cx, cy: cy, aX: w, aY: cy, bX: cx, bY: 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.35 * w, 0.65 * h),
          LineTo(0.5 * w, 0.65 * h),
          MoveTo(0.42 * w, 0.55 * h),
          LineTo(0.42 * w, 0.75 * h),
          MoveTo(0.55 * w, 0.35 * h),
          LineTo(0.7 * w, 0.35 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Logic inverter (NOT): triangle + bubble.
  static VsdxShape electricalInverter({
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
          MoveTo(0.1 * w, 0),
          LineTo(0.7 * w, 0.5 * h),
          LineTo(0.1 * w, h),
          LineTo(0.1 * w, 0),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.82 * w,
              cy: 0.5 * h,
              aX: 0.9 * w,
              aY: 0.5 * h,
              bX: 0.82 * w,
              bY: 0.62 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, 0.5 * h),
          LineTo(0.1 * w, 0.5 * h),
          MoveTo(0.9 * w, 0.5 * h),
          LineTo(w, 0.5 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Potentiometer: resistor body with a wiper arrow.
  static VsdxShape electricalPotentiometer({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final base = electricalResistor(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      fill: fill,
      line: line,
      name: name,
    );
    final w = width.abs();
    final h = height.abs();
    return base.copyWith(geometries: <VsdxGeometry>[
      ...base.geometries,
      VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
        MoveTo(0.5 * w, 0),
        LineTo(0.5 * w, 0.35 * h),
        LineTo(0.42 * w, 0.22 * h),
        MoveTo(0.5 * w, 0.35 * h),
        LineTo(0.58 * w, 0.22 * h),
      ]),
    ]);
  }

  /// Circuit breaker: switch with a curved trip mark.
  static VsdxShape electricalCircuitBreaker({
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
    final mid = h / 2;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, mid),
          LineTo(0.25 * w, mid),
          EllipseCmd(
              cx: 0.3 * w,
              cy: mid,
              aX: 0.35 * w,
              aY: mid,
              bX: 0.3 * w,
              bY: mid + 0.08 * h),
          MoveTo(0.3 * w, mid),
          LineTo(0.65 * w, 0.85 * h),
          EllipseCmd(
              cx: 0.72 * w,
              cy: mid,
              aX: 0.77 * w,
              aY: mid,
              bX: 0.72 * w,
              bY: mid + 0.08 * h),
          MoveTo(0.72 * w, mid),
          LineTo(w, mid),
          MoveTo(0.45 * w, 0.7 * h),
          EllipticalArcTo(
              x: 0.6 * w, y: 0.45 * h, controlX: 0.6 * w, controlY: 0.7 * h),
        ]),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// Crystal oscillator: rectangle between leads.
  static VsdxShape electricalCrystal({
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
    final mid = h / 2;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, mid),
          LineTo(0.28 * w, mid),
          MoveTo(0.28 * w, 0.2 * h),
          LineTo(0.72 * w, 0.2 * h),
          LineTo(0.72 * w, 0.8 * h),
          LineTo(0.28 * w, 0.8 * h),
          LineTo(0.28 * w, 0.2 * h),
          MoveTo(0.38 * w, 0.32 * h),
          LineTo(0.62 * w, 0.32 * h),
          LineTo(0.62 * w, 0.68 * h),
          LineTo(0.38 * w, 0.68 * h),
          LineTo(0.38 * w, 0.32 * h),
          MoveTo(0.72 * w, mid),
          LineTo(w, mid),
        ]),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// Incandescent lamp: circle with an X filament.
  static VsdxShape electricalLamp({
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
    final cx = w / 2;
    final cy = h / 2;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(cx: cx, cy: cy, aX: w, aY: cy, bX: cx, bY: 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.3 * w, 0.3 * h),
          LineTo(0.7 * w, 0.7 * h),
          MoveTo(0.7 * w, 0.3 * h),
          LineTo(0.3 * w, 0.7 * h),
          MoveTo(0, cy),
          LineTo(0.12 * w, cy),
          MoveTo(0.88 * w, cy),
          LineTo(w, cy),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// No Smoking: circle, slash, and cigarette glyph.
  static VsdxShape signNoSmoking({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final base = noSymbol(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      fill: fill,
      line: line,
      name: name,
    );
    final w = width.abs();
    final h = height.abs();
    return base.copyWith(geometries: <VsdxGeometry>[
      ...base.geometries,
      VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
        MoveTo(0.22 * w, 0.42 * h),
        LineTo(0.7 * w, 0.42 * h),
        LineTo(0.7 * w, 0.58 * h),
        LineTo(0.22 * w, 0.58 * h),
        MoveTo(0.72 * w, 0.5 * h),
        LineTo(0.82 * w, 0.62 * h),
        MoveTo(0.72 * w, 0.5 * h),
        LineTo(0.82 * w, 0.38 * h),
      ]),
    ]);
  }

  /// Biohazard trefoil (three interlocking arcs).
  static VsdxShape signBiohazard({
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
    final cx = w / 2;
    final cy = h / 2;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(cx: cx, cy: cy, aX: w, aY: cy, bX: cx, bY: 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: 0.72 * h,
              aX: cx + 0.18 * w,
              aY: 0.72 * h,
              bX: cx,
              bY: 0.9 * h),
          EllipseCmd(
              cx: 0.32 * w,
              cy: 0.38 * h,
              aX: 0.5 * w,
              aY: 0.38 * h,
              bX: 0.32 * w,
              bY: 0.56 * h),
          EllipseCmd(
              cx: 0.68 * w,
              cy: 0.38 * h,
              aX: 0.86 * w,
              aY: 0.38 * h,
              bX: 0.68 * w,
              bY: 0.56 * h),
          EllipseCmd(
              cx: cx,
              cy: cy,
              aX: cx + 0.1 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.1 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Pedestrian crossing: rectangle with a walking figure.
  static VsdxShape signPedestrianCrossing({
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
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.78 * h,
              aX: 0.58 * w,
              aY: 0.78 * h,
              bX: 0.5 * w,
              bY: 0.9 * h),
          MoveTo(0.5 * w, 0.68 * h),
          LineTo(0.5 * w, 0.4 * h),
          MoveTo(0.35 * w, 0.55 * h),
          LineTo(0.65 * w, 0.55 * h),
          MoveTo(0.5 * w, 0.4 * h),
          LineTo(0.35 * w, 0.22 * h),
          MoveTo(0.5 * w, 0.4 * h),
          LineTo(0.65 * w, 0.22 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Keep Dry: umbrella under rain drops.
  static VsdxShape signKeepDry({
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
          MoveTo(0.1 * w, 0.45 * h),
          EllipticalArcTo(
              x: 0.9 * w, y: 0.45 * h, controlX: 0.5 * w, controlY: 0.95 * h),
          LineTo(0.1 * w, 0.45 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.5 * w, 0.45 * h),
          LineTo(0.5 * w, 0.15 * h),
          LineTo(0.62 * w, 0.15 * h),
          MoveTo(0.25 * w, 0.85 * h),
          LineTo(0.25 * w, 0.7 * h),
          MoveTo(0.4 * w, 0.9 * h),
          LineTo(0.4 * w, 0.75 * h),
          MoveTo(0.6 * w, 0.9 * h),
          LineTo(0.6 * w, 0.75 * h),
          MoveTo(0.75 * w, 0.85 * h),
          LineTo(0.75 * w, 0.7 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Slip hazard: figure with a skid arc.
  static VsdxShape signSlipHazard({
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
          MoveTo(0.5 * w, h),
          LineTo(w, 0),
          LineTo(0, 0),
          LineTo(0.5 * w, h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.45 * w,
              cy: 0.55 * h,
              aX: 0.52 * w,
              aY: 0.55 * h,
              bX: 0.45 * w,
              bY: 0.65 * h),
          MoveTo(0.45 * w, 0.48 * h),
          LineTo(0.55 * w, 0.28 * h),
          LineTo(0.7 * w, 0.18 * h),
          MoveTo(0.35 * w, 0.22 * h),
          EllipticalArcTo(
              x: 0.65 * w, y: 0.12 * h, controlX: 0.5 * w, controlY: 0.05 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Fire extinguisher silhouette.
  static VsdxShape signFireExtinguisher({
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
          MoveTo(0.3 * w, 0),
          LineTo(0.7 * w, 0),
          LineTo(0.75 * w, 0.7 * h),
          LineTo(0.25 * w, 0.7 * h),
          LineTo(0.3 * w, 0),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.4 * w, 0.7 * h),
          LineTo(0.6 * w, 0.7 * h),
          LineTo(0.6 * w, 0.85 * h),
          LineTo(0.4 * w, 0.85 * h),
          LineTo(0.4 * w, 0.7 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.55 * w, 0.85 * h),
          LineTo(0.75 * w, h),
          MoveTo(0.45 * w, 0.55 * h),
          LineTo(0.2 * w, 0.55 * h),
          LineTo(0.15 * w, 0.7 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  // --- Batch 65: IEEE logic gates + Floorplan starter ----------------------

  /// IEEE AND gate (D-shape) with two input leads and one output.
  static VsdxShape electricalAndGate({
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
          MoveTo(0.15 * w, 0),
          LineTo(0.55 * w, 0),
          EllipticalArcTo(
              x: 0.55 * w, y: h, controlX: 0.95 * w, controlY: 0.5 * h),
          LineTo(0.15 * w, h),
          LineTo(0.15 * w, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, 0.3 * h),
          LineTo(0.15 * w, 0.3 * h),
          MoveTo(0, 0.7 * h),
          LineTo(0.15 * w, 0.7 * h),
          MoveTo(0.85 * w, 0.5 * h),
          LineTo(w, 0.5 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IEEE OR gate (shield) with two inputs and one output.
  static VsdxShape electricalOrGate({
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
          MoveTo(0.12 * w, 0),
          EllipticalArcTo(
              x: 0.9 * w, y: 0.5 * h, controlX: 0.55 * w, controlY: 0.05 * h),
          EllipticalArcTo(
              x: 0.12 * w, y: h, controlX: 0.55 * w, controlY: 0.95 * h),
          EllipticalArcTo(
              x: 0.12 * w, y: 0, controlX: 0.28 * w, controlY: 0.5 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, 0.28 * h),
          LineTo(0.2 * w, 0.28 * h),
          MoveTo(0, 0.72 * h),
          LineTo(0.2 * w, 0.72 * h),
          MoveTo(0.9 * w, 0.5 * h),
          LineTo(w, 0.5 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// NAND = AND body + output bubble.
  static VsdxShape electricalNandGate({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final and = electricalAndGate(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      fill: fill,
      line: line,
      name: name,
    );
    final w = width.abs();
    final h = height.abs();
    return and.copyWith(geometries: <VsdxGeometry>[
      and.geometries.first,
      VsdxGeometry(commands: <VsdxPathCommand>[
        EllipseCmd(
            cx: 0.88 * w,
            cy: 0.5 * h,
            aX: 0.94 * w,
            aY: 0.5 * h,
            bX: 0.88 * w,
            bY: 0.58 * h),
      ]),
      VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
        MoveTo(0, 0.3 * h),
        LineTo(0.15 * w, 0.3 * h),
        MoveTo(0, 0.7 * h),
        LineTo(0.15 * w, 0.7 * h),
        MoveTo(0.94 * w, 0.5 * h),
        LineTo(w, 0.5 * h),
      ]),
    ]);
  }

  /// NOR = OR body + output bubble.
  static VsdxShape electricalNorGate({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final or = electricalOrGate(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      fill: fill,
      line: line,
      name: name,
    );
    final w = width.abs();
    final h = height.abs();
    return or.copyWith(geometries: <VsdxGeometry>[
      or.geometries.first,
      VsdxGeometry(commands: <VsdxPathCommand>[
        EllipseCmd(
            cx: 0.9 * w,
            cy: 0.5 * h,
            aX: 0.96 * w,
            aY: 0.5 * h,
            bX: 0.9 * w,
            bY: 0.58 * h),
      ]),
      VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
        MoveTo(0, 0.28 * h),
        LineTo(0.2 * w, 0.28 * h),
        MoveTo(0, 0.72 * h),
        LineTo(0.2 * w, 0.72 * h),
        MoveTo(0.96 * w, 0.5 * h),
        LineTo(w, 0.5 * h),
      ]),
    ]);
  }

  /// XOR = OR body with an extra curved input bar.
  static VsdxShape electricalXorGate({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final or = electricalOrGate(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      fill: fill,
      line: line,
      name: name,
    );
    final w = width.abs();
    final h = height.abs();
    return or.copyWith(geometries: <VsdxGeometry>[
      ...or.geometries,
      VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
        MoveTo(0.05 * w, 0),
        EllipticalArcTo(
            x: 0.05 * w, y: h, controlX: 0.2 * w, controlY: 0.5 * h),
      ]),
    ]);
  }

  /// XNOR = XOR + output bubble.
  static VsdxShape electricalXnorGate({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final xor = electricalXorGate(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      fill: fill,
      line: line,
      name: name,
    );
    final w = width.abs();
    final h = height.abs();
    final geos = List<VsdxGeometry>.from(xor.geometries);
    // Replace the short output lead with bubble + lead.
    geos[1] = VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
      MoveTo(0, 0.28 * h),
      LineTo(0.2 * w, 0.28 * h),
      MoveTo(0, 0.72 * h),
      LineTo(0.2 * w, 0.72 * h),
      MoveTo(0.96 * w, 0.5 * h),
      LineTo(w, 0.5 * h),
    ]);
    geos.insert(
      1,
      VsdxGeometry(commands: <VsdxPathCommand>[
        EllipseCmd(
            cx: 0.9 * w,
            cy: 0.5 * h,
            aX: 0.96 * w,
            aY: 0.5 * h,
            bX: 0.9 * w,
            bY: 0.58 * h),
      ]),
    );
    return xor.copyWith(geometries: geos);
  }

  /// Buffer (amplifier triangle) with input/output leads.
  static VsdxShape electricalBuffer({
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
          MoveTo(0.15 * w, 0),
          LineTo(0.85 * w, 0.5 * h),
          LineTo(0.15 * w, h),
          LineTo(0.15 * w, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, 0.5 * h),
          LineTo(0.15 * w, 0.5 * h),
          MoveTo(0.85 * w, 0.5 * h),
          LineTo(w, 0.5 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Floorplan wall segment (thick bar).
  static VsdxShape floorplanWall({
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
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Door: wall jambs + quarter-circle swing.
  static VsdxShape floorplanDoor({
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, 0.85 * h),
          LineTo(0.12 * w, 0.85 * h),
          MoveTo(0.88 * w, 0.85 * h),
          LineTo(w, 0.85 * h),
          MoveTo(0.12 * w, 0.85 * h),
          LineTo(0.12 * w, 0.1 * h),
          MoveTo(0.12 * w, 0.85 * h),
          EllipticalArcTo(
              x: 0.88 * w, y: 0.85 * h, controlX: 0.5 * w, controlY: 0.05 * h),
        ]),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// Window opening in a wall (double glazing lines).
  static VsdxShape floorplanWindowOpening({
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, 0.7 * h),
          LineTo(0.15 * w, 0.7 * h),
          MoveTo(0.85 * w, 0.7 * h),
          LineTo(w, 0.7 * h),
          MoveTo(0, 0.3 * h),
          LineTo(0.15 * w, 0.3 * h),
          MoveTo(0.85 * w, 0.3 * h),
          LineTo(w, 0.3 * h),
          MoveTo(0.15 * w, 0.2 * h),
          LineTo(0.85 * w, 0.2 * h),
          LineTo(0.85 * w, 0.8 * h),
          LineTo(0.15 * w, 0.8 * h),
          LineTo(0.15 * w, 0.2 * h),
          MoveTo(0.5 * w, 0.2 * h),
          LineTo(0.5 * w, 0.8 * h),
        ]),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// Top-down dining / meeting table.
  static VsdxShape floorplanTable({
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
    final r = 0.12 * math.min(w, h);
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
      ],
      fill: fill,
      line: line,
    );
  }

  /// Top-down chair (seat + backrest).
  static VsdxShape floorplanChair({
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
          MoveTo(0.15 * w, 0),
          LineTo(0.85 * w, 0),
          LineTo(0.85 * w, 0.65 * h),
          LineTo(0.15 * w, 0.65 * h),
          LineTo(0.15 * w, 0),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.1 * w, 0.65 * h),
          LineTo(0.9 * w, 0.65 * h),
          LineTo(0.9 * w, h),
          LineTo(0.1 * w, h),
          LineTo(0.1 * w, 0.65 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Office desk with a knee well.
  static VsdxShape floorplanDesk({
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
          MoveTo(0, 0.45 * h),
          LineTo(w, 0.45 * h),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0.45 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, 0),
          LineTo(0.28 * w, 0),
          LineTo(0.28 * w, 0.45 * h),
          LineTo(0, 0.45 * h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.72 * w, 0),
          LineTo(w, 0),
          LineTo(w, 0.45 * h),
          LineTo(0.72 * w, 0.45 * h),
          LineTo(0.72 * w, 0),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Single bed with pillow.
  static VsdxShape floorplanBed({
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
    // Two NoFill=0 rectangles become one evenodd path in canvas, SVG and
    // libvisio `_fillAndShadowProperties` (`svg:fill-rule=evenodd`), which
    // punches the pillow into a mattress hole. Stroke the pillow on a
    // filled mattress so Draw keeps the bed solid.
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0.15 * w, 0.7 * h),
            LineTo(0.85 * w, 0.7 * h),
            LineTo(0.85 * w, 0.9 * h),
            LineTo(0.15 * w, 0.9 * h),
            LineTo(0.15 * w, 0.7 * h),
          ],
        ),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, 0.55 * h),
          LineTo(w, 0.55 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Sofa with arms and back.
  static VsdxShape floorplanSofa({
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
          MoveTo(0.08 * w, 0),
          LineTo(0.92 * w, 0),
          LineTo(0.92 * w, 0.7 * h),
          LineTo(0.08 * w, 0.7 * h),
          LineTo(0.08 * w, 0),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, 0.7 * h),
          LineTo(w, 0.7 * h),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0.7 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.33 * w, 0),
          LineTo(0.33 * w, 0.7 * h),
          MoveTo(0.67 * w, 0),
          LineTo(0.67 * w, 0.7 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Bathroom sink (counter + basin).
  static VsdxShape floorplanSink({
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
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.45 * h,
              aX: 0.78 * w,
              aY: 0.45 * h,
              bX: 0.5 * w,
              bY: 0.75 * h),
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.45 * h,
              aX: 0.55 * w,
              aY: 0.45 * h,
              bX: 0.5 * w,
              bY: 0.52 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Toilet: tank + oval bowl (top-down).
  static VsdxShape floorplanToilet({
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
          MoveTo(0.15 * w, 0.65 * h),
          LineTo(0.85 * w, 0.65 * h),
          LineTo(0.85 * w, h),
          LineTo(0.15 * w, h),
          LineTo(0.15 * w, 0.65 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.35 * h,
              aX: 0.8 * w,
              aY: 0.35 * h,
              bX: 0.5 * w,
              bY: 0.65 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Straight stairs (parallel treads).
  static VsdxShape floorplanStairs({
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
    final cmds = <VsdxPathCommand>[
      MoveTo(0, 0),
      LineTo(w, 0),
      LineTo(w, h),
      LineTo(0, h),
      LineTo(0, 0),
    ];
    for (var i = 1; i < 6; i++) {
      final y = i * h / 6;
      cmds
        ..add(MoveTo(0, y))
        ..add(LineTo(w, y));
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

  /// Elevator cab with diagonal cross and door gap.
  static VsdxShape floorplanElevator({
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
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, 0),
          LineTo(w, h),
          MoveTo(w, 0),
          LineTo(0, h),
          MoveTo(0.5 * w, 0.15 * h),
          LineTo(0.5 * w, 0.85 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Potted plant (plan view).
  static VsdxShape floorplanPlant({
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
    final cx = w / 2;
    final cy = h / 2;
    final spokes = <VsdxPathCommand>[];
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      spokes
        ..add(MoveTo(cx, cy))
        ..add(LineTo(cx + 0.42 * w * math.cos(a), cy + 0.42 * h * math.sin(a)));
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
          EllipseCmd(cx: cx, cy: cy, aX: w, aY: cy, bX: cx, bY: 0),
        ]),
        VsdxGeometry(noFill: true, commands: spokes),
        // Inner disc used to be NoFill=0, which evenodd-punched a hole through
        // the foliage in canvas, SVG and libvisio `_fillAndShadowProperties`.
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: cx,
                cy: cy,
                aX: cx + 0.15 * w,
                aY: cy,
                bX: cx,
                bY: cy + 0.15 * h),
          ],
        ),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Refrigerator (top-down cabinet with door split).
  static VsdxShape floorplanRefrigerator({
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
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, 0.35 * h),
          LineTo(w, 0.35 * h),
          MoveTo(0.85 * w, 0.1 * h),
          LineTo(0.85 * w, 0.25 * h),
          MoveTo(0.85 * w, 0.5 * h),
          LineTo(0.85 * w, 0.85 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Double door: two jambs + two quarter-circle swings.
  static VsdxShape floorplanDoubleDoor({
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, 0.88 * h),
          LineTo(0.08 * w, 0.88 * h),
          MoveTo(0.92 * w, 0.88 * h),
          LineTo(w, 0.88 * h),
          MoveTo(0.08 * w, 0.88 * h),
          LineTo(0.08 * w, 0.12 * h),
          MoveTo(0.92 * w, 0.88 * h),
          LineTo(0.92 * w, 0.12 * h),
          MoveTo(0.08 * w, 0.88 * h),
          EllipticalArcTo(
              x: 0.5 * w, y: 0.88 * h, controlX: 0.29 * w, controlY: 0.08 * h),
          MoveTo(0.92 * w, 0.88 * h),
          EllipticalArcTo(
              x: 0.5 * w, y: 0.88 * h, controlX: 0.71 * w, controlY: 0.08 * h),
        ]),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// Sliding door: wall tracks + offset door panel.
  static VsdxShape floorplanSlidingDoor({
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, 0.55 * h),
          LineTo(w, 0.55 * h),
          MoveTo(0, 0.45 * h),
          LineTo(w, 0.45 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.08 * w, 0.28 * h),
          LineTo(0.55 * w, 0.28 * h),
          LineTo(0.55 * w, 0.72 * h),
          LineTo(0.08 * w, 0.72 * h),
          LineTo(0.08 * w, 0.28 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Bathtub (rounded rectangle + drain).
  static VsdxShape floorplanBathtub({
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
    final r = 0.22 * math.min(w, h);
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.22 * w,
              cy: 0.5 * h,
              aX: 0.3 * w,
              aY: 0.5 * h,
              bX: 0.22 * w,
              bY: 0.62 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Shower stall (square + spray arcs).
  static VsdxShape floorplanShower({
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
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.8 * h),
          EllipticalArcTo(
              x: 0.8 * w, y: 0.8 * h, controlX: 0.5 * w, controlY: 0.45 * h),
          MoveTo(0.28 * w, 0.72 * h),
          EllipticalArcTo(
              x: 0.72 * w, y: 0.72 * h, controlX: 0.5 * w, controlY: 0.52 * h),
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.28 * h,
              aX: 0.58 * w,
              aY: 0.28 * h,
              bX: 0.5 * w,
              bY: 0.36 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Closet / wardrobe footprint with hanging rod.
  static VsdxShape floorplanCloset({
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
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.12 * w, 0.55 * h),
          LineTo(0.88 * w, 0.55 * h),
          MoveTo(0.2 * w, 0.55 * h),
          LineTo(0.2 * w, 0.25 * h),
          MoveTo(0.4 * w, 0.55 * h),
          LineTo(0.4 * w, 0.25 * h),
          MoveTo(0.6 * w, 0.55 * h),
          LineTo(0.6 * w, 0.25 * h),
          MoveTo(0.8 * w, 0.55 * h),
          LineTo(0.8 * w, 0.25 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Bookshelf (shelves in plan as parallel lines).
  static VsdxShape floorplanBookshelf({
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
    final cmds = <VsdxPathCommand>[
      MoveTo(0, 0),
      LineTo(w, 0),
      LineTo(w, h),
      LineTo(0, h),
      LineTo(0, 0),
    ];
    for (var i = 1; i < 4; i++) {
      final x = i * w / 4;
      cmds
        ..add(MoveTo(x, 0.1 * h))
        ..add(LineTo(x, 0.9 * h));
    }
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: cmds),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Fireplace (hearth + chimney throat).
  static VsdxShape floorplanFireplace({
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
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, 0.45 * h),
          LineTo(0, 0.45 * h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.28 * w, 0.45 * h),
          LineTo(0.72 * w, 0.45 * h),
          LineTo(0.65 * w, h),
          LineTo(0.35 * w, h),
          LineTo(0.28 * w, 0.45 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Kitchen island (counter + cooktop circles).
  static VsdxShape floorplanKitchenIsland({
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
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.3 * w,
              cy: 0.5 * h,
              aX: 0.42 * w,
              aY: 0.5 * h,
              bX: 0.3 * w,
              bY: 0.68 * h),
          EllipseCmd(
              cx: 0.55 * w,
              cy: 0.5 * h,
              aX: 0.67 * w,
              aY: 0.5 * h,
              bX: 0.55 * w,
              bY: 0.68 * h),
          EllipseCmd(
              cx: 0.8 * w,
              cy: 0.5 * h,
              aX: 0.9 * w,
              aY: 0.5 * h,
              bX: 0.8 * w,
              bY: 0.62 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Parking space (stall outline + diagonal hatch).
  static VsdxShape floorplanParkingSpace({
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
          MoveTo(0.15 * w, 0.2 * h),
          LineTo(0.85 * w, 0.8 * h),
        ]),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }

  /// TV stand / media console.
  static VsdxShape floorplanTvStand({
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
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, 0.45 * h),
          LineTo(0, 0.45 * h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.12 * w, 0.45 * h),
          LineTo(0.88 * w, 0.45 * h),
          LineTo(0.88 * w, h),
          LineTo(0.12 * w, h),
          LineTo(0.12 * w, 0.45 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Office file cabinet.
  static VsdxShape floorplanFileCabinet({
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
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0, 0.33 * h),
          LineTo(w, 0.33 * h),
          MoveTo(0, 0.66 * h),
          LineTo(w, 0.66 * h),
          MoveTo(0.75 * w, 0.12 * h),
          LineTo(0.88 * w, 0.12 * h),
          MoveTo(0.75 * w, 0.45 * h),
          LineTo(0.88 * w, 0.45 * h),
          MoveTo(0.75 * w, 0.78 * h),
          LineTo(0.88 * w, 0.78 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Structural column (filled circle / square hybrid).
  static VsdxShape floorplanColumn({
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
    final cx = w / 2;
    final cy = h / 2;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(cx: cx, cy: cy, aX: w, aY: cy, bX: cx, bY: 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.2 * h),
          LineTo(0.8 * w, 0.2 * h),
          LineTo(0.8 * w, 0.8 * h),
          LineTo(0.2 * w, 0.8 * h),
          LineTo(0.2 * w, 0.2 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Escalator (treads + direction arrow).
  static VsdxShape floorplanEscalator({
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
    final cmds = <VsdxPathCommand>[
      MoveTo(0, 0),
      LineTo(w, 0),
      LineTo(w, h),
      LineTo(0, h),
      LineTo(0, 0),
    ];
    for (var i = 1; i < 5; i++) {
      final t = i / 5;
      cmds
        ..add(MoveTo(t * w * 0.85, 0.1 * h))
        ..add(LineTo(t * w * 0.85 + 0.12 * w, 0.9 * h));
    }
    cmds
      ..add(MoveTo(0.2 * w, 0.55 * h))
      ..add(LineTo(0.75 * w, 0.55 * h))
      ..add(LineTo(0.62 * w, 0.4 * h))
      ..add(MoveTo(0.75 * w, 0.55 * h))
      ..add(LineTo(0.62 * w, 0.7 * h));
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

  /// Office copier / printer footprint.
  static VsdxShape floorplanCopier({
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
          MoveTo(0, 0.15 * h),
          LineTo(w, 0.15 * h),
          LineTo(w, 0.85 * h),
          LineTo(0, 0.85 * h),
          LineTo(0, 0.15 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.15 * w, 0.85 * h),
          LineTo(0.85 * w, 0.85 * h),
          LineTo(0.85 * w, h),
          LineTo(0.15 * w, h),
          LineTo(0.15 * w, 0.85 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.4 * h),
          LineTo(0.8 * w, 0.4 * h),
          MoveTo(0.2 * w, 0.55 * h),
          LineTo(0.8 * w, 0.55 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  // ---------------------------------------------------------------------------
  // EIP (Enterprise Integration Patterns) — draw.io mxgraph.eip.*
  // Icons follow the classic Hohpe/Woolf stencil look: outer box + message
  // squares + arrows. Coordinates are Y-up (draw.io XML is Y-down).
  // ---------------------------------------------------------------------------

  static VsdxGeometry _eipOuterBox(double w, double h) => VsdxGeometry(
        commands: <VsdxPathCommand>[
          MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          LineTo(0, 0),
        ],
      );

  /// Message square; [x]/[y] are bottom-left corners in local inches.
  static VsdxGeometry _eipMessageSquare(
      double x, double y, double sideX, double sideY) {
    return VsdxGeometry(commands: <VsdxPathCommand>[
      MoveTo(x, y),
      LineTo(x + sideX, y),
      LineTo(x + sideX, y + sideY),
      LineTo(x, y + sideY),
      LineTo(x, y),
    ]);
  }

  static VsdxGeometry _eipArrowRight(
      double tipX, double midY, double len, double half) {
    return VsdxGeometry(commands: <VsdxPathCommand>[
      MoveTo(tipX - len, midY - half),
      LineTo(tipX - len, midY + half),
      LineTo(tipX, midY),
      LineTo(tipX - len, midY - half),
    ]);
  }

  /// Horizontal message pipe (mxgraph.eip.messageChannel).
  static VsdxShape eipMessageChannel({
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
    final cy = 0.5 * h;
    final t = 0.35 * h;
    final r = math.min(0.12 * w, t);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(r, cy - t),
          LineTo(w - r, cy - t),
          EllipticalArcTo(
              x: w - r, y: cy + t, controlX: w, controlY: cy),
          LineTo(r, cy + t),
          EllipticalArcTo(x: r, y: cy - t, controlX: 0, controlY: cy),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: w - r,
              cy: cy,
              aX: w - r + 0.55 * r,
              aY: cy,
              bX: w - r,
              bY: cy + 0.55 * t),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Dead Letter Channel: pipe + circled X marker.
  static VsdxShape eipDeadLetterChannel({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final base = eipMessageChannel(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      fill: fill,
      line: line,
      name: name,
    );
    final w = width.abs();
    final h = height.abs();
    final cx = 0.5 * w;
    final cy = 0.5 * h;
    final rr = 0.28 * h;
    return base.copyWith(geometries: <VsdxGeometry>[
      ...base.geometries,
      VsdxGeometry(commands: <VsdxPathCommand>[
        EllipseCmd(
            cx: cx,
            cy: cy,
            aX: cx + rr,
            aY: cy,
            bX: cx,
            bY: cy + rr),
      ]),
      VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
        MoveTo(cx - 0.45 * rr, cy - 0.45 * rr),
        LineTo(cx + 0.45 * rr, cy + 0.45 * rr),
        MoveTo(cx + 0.45 * rr, cy - 0.45 * rr),
        LineTo(cx - 0.45 * rr, cy + 0.45 * rr),
      ]),
    ]);
  }

  /// Aggregator: three messages in → one out.
  static VsdxShape eipAggregator({
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
    final sx = 16 / 150 * w;
    final sy = 16 / 90 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        _eipMessageSquare(10 / 150 * w, (1 - 32 / 90) * h, sx, sy),
        _eipMessageSquare(10 / 150 * w, (1 - 53 / 90) * h, sx, sy),
        _eipMessageSquare(10 / 150 * w, (1 - 76 / 90) * h, sx, sy),
        _eipMessageSquare(124 / 150 * w, (1 - 53 / 90) * h, sx, sy),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(50 / 150 * w, 0.5 * h),
          LineTo(95 / 150 * w, 0.5 * h),
        ]),
        _eipArrowRight(100 / 150 * w, 0.5 * h, 13 / 150 * w, 6 / 90 * h),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Splitter: one message in → three out.
  static VsdxShape eipSplitter({
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
    final sx = 16 / 150 * w;
    final sy = 16 / 90 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        _eipMessageSquare(10 / 150 * w, (1 - 53 / 90) * h, sx, sy),
        _eipMessageSquare(124 / 150 * w, (1 - 32 / 90) * h, sx, sy),
        _eipMessageSquare(124 / 150 * w, (1 - 53 / 90) * h, sx, sy),
        _eipMessageSquare(124 / 150 * w, (1 - 76 / 90) * h, sx, sy),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(50 / 150 * w, 0.5 * h),
          LineTo(95 / 150 * w, 0.5 * h),
        ]),
        _eipArrowRight(100 / 150 * w, 0.5 * h, 13 / 150 * w, 6 / 90 * h),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Content Based Router: hub with three outbound routes.
  static VsdxShape eipContentBasedRouter({
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
    VsdxGeometry dot(double cx, double cy) {
      final r = 4 / 150 * w;
      return VsdxGeometry(commands: <VsdxPathCommand>[
        EllipseCmd(
            cx: cx, cy: cy, aX: cx + r, aY: cy, bX: cx, bY: cy + r),
      ]);
    }

    final hubX = 45 / 150 * w;
    final hubY = 0.5 * h;
    final outX = 105 / 150 * w;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        dot(hubX, hubY),
        dot(outX, (1 - 24 / 90) * h),
        dot(outX, 0.5 * h),
        dot(outX, (1 - 66 / 90) * h),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(hubX, hubY),
          LineTo(outX, (1 - 24 / 90) * h),
          MoveTo(hubX, hubY),
          LineTo(outX, 0.5 * h),
          MoveTo(hubX, hubY),
          LineTo(outX, (1 - 66 / 90) * h),
          MoveTo(20 / 150 * w, hubY),
          LineTo(hubX, hubY),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Message Filter: funnel glyph inside the box.
  static VsdxShape eipMessageFilter({
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
    // Funnel from draw.io Message Filter (Y flipped).
    double xOf(double x) => x / 150 * w;
    double yOf(double yTop) => (1 - yTop / 90) * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(xOf(50), yOf(70)),
          LineTo(xOf(100), yOf(70)),
          LineTo(xOf(86), yOf(45)),
          LineTo(xOf(86), yOf(20)),
          LineTo(xOf(64), yOf(20)),
          LineTo(xOf(64), yOf(45)),
          LineTo(xOf(50), yOf(70)),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Message Translator: two document panels with transform marks.
  static VsdxShape eipMessageTranslator({
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
    double xOf(double x) => x / 150 * w;
    double yBottomOf(double yTop, double hh) => (1 - (yTop + hh) / 90) * h;
    final panelH = 60 / 90 * h;
    final panelW = 40 / 150 * w;
    final leftY = yBottomOf(15, 60);
    final rightY = yBottomOf(15, 60);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(xOf(15), leftY),
          LineTo(xOf(15) + panelW, leftY),
          LineTo(xOf(15) + panelW, leftY + panelH),
          LineTo(xOf(15), leftY + panelH),
          LineTo(xOf(15), leftY),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(xOf(95), rightY),
          LineTo(xOf(95) + panelW, rightY),
          LineTo(xOf(95) + panelW, rightY + panelH),
          LineTo(xOf(95), rightY + panelH),
          LineTo(xOf(95), rightY),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(xOf(60), 0.5 * h),
          LineTo(xOf(88), 0.5 * h),
          MoveTo(xOf(22), (1 - 30 / 90) * h),
          LineTo(xOf(48), (1 - 30 / 90) * h),
          MoveTo(xOf(22), (1 - 45 / 90) * h),
          LineTo(xOf(48), (1 - 45 / 90) * h),
          MoveTo(xOf(22), (1 - 60 / 90) * h),
          LineTo(xOf(48), (1 - 60 / 90) * h),
          MoveTo(xOf(102), (1 - 35 / 90) * h),
          LineTo(xOf(128), (1 - 50 / 90) * h),
          MoveTo(xOf(102), (1 - 50 / 90) * h),
          LineTo(xOf(128), (1 - 35 / 90) * h),
          MoveTo(xOf(102), (1 - 55 / 90) * h),
          LineTo(xOf(128), (1 - 55 / 90) * h),
        ]),
        _eipArrowRight(xOf(90), 0.5 * h, 10 / 150 * w, 5 / 90 * h),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Content Enricher: message + enrichment square + plus.
  static VsdxShape eipContentEnricher({
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
    final sx = 16 / 150 * w;
    final sy = 16 / 90 * h;
    final ex = 25 / 150 * w;
    final ey = 25 / 90 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        _eipMessageSquare(10 / 150 * w, (1 - 53 / 90) * h, sx, sy),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(115 / 150 * w, (1 - 53 / 90) * h),
          LineTo(115 / 150 * w + ex, (1 - 53 / 90) * h),
          LineTo(115 / 150 * w + ex, (1 - 53 / 90) * h + ey),
          LineTo(115 / 150 * w, (1 - 53 / 90) * h + ey),
          LineTo(115 / 150 * w, (1 - 53 / 90) * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(50 / 150 * w, 0.5 * h),
          LineTo(100 / 150 * w, 0.5 * h),
          MoveTo(115 / 150 * w + 0.5 * ex, (1 - 53 / 90) * h + 0.2 * ey),
          LineTo(115 / 150 * w + 0.5 * ex, (1 - 53 / 90) * h + 0.8 * ey),
          MoveTo(115 / 150 * w + 0.2 * ex, (1 - 53 / 90) * h + 0.5 * ey),
          LineTo(115 / 150 * w + 0.8 * ex, (1 - 53 / 90) * h + 0.5 * ey),
        ]),
        _eipArrowRight(105 / 150 * w, 0.5 * h, 12 / 150 * w, 6 / 90 * h),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Messaging Gateway: channel into a gateway portal.
  static VsdxShape eipMessagingGateway({
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
        _eipOuterBox(w, h),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(109 / 150 * w, (1 - 82 / 90) * h),
          LineTo(136 / 150 * w, (1 - 82 / 90) * h),
          LineTo(136 / 150 * w, (1 - 8 / 90) * h),
          LineTo(109 / 150 * w, (1 - 8 / 90) * h),
          LineTo(109 / 150 * w, (1 - 82 / 90) * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(11 / 150 * w, 0.5 * h),
          LineTo(56 / 150 * w, 0.5 * h),
        ]),
        _eipArrowRight(70 / 150 * w, 0.5 * h, 14 / 150 * w, 7 / 90 * h),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(80 / 150 * w, 0.35 * h),
          LineTo(105 / 150 * w, 0.5 * h),
          LineTo(80 / 150 * w, 0.65 * h),
          LineTo(80 / 150 * w, 0.35 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Channel Adapter: trapezoid wedge (draw.io tall adapter).
  static VsdxShape eipChannelAdapter({
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
          LineTo(w, (1 - 25 / 90) * h),
          LineTo(w, (1 - 65 / 90) * h),
          LineTo(0, 0),
          LineTo(0, h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Wire Tap: through-line with a downward tap.
  static VsdxShape eipWireTap({
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
    final cx = 75 / 150 * w;
    final cy = 0.5 * h;
    final r = 4 / 150 * w;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx, cy: cy, aX: cx + r, aY: cy, bX: cx, bY: cy + r),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(20 / 150 * w, cy),
          LineTo(130 / 150 * w, cy),
          MoveTo(cx, cy),
          LineTo(cx, 15 / 90 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(cx - 6 / 150 * w, 20 / 90 * h),
          LineTo(cx + 6 / 150 * w, 20 / 90 * h),
          LineTo(cx, 8 / 90 * h),
          LineTo(cx - 6 / 150 * w, 20 / 90 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Recipient List: same topology as Content Based Router (list fan-out).
  static VsdxShape eipRecipientList({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    return eipContentBasedRouter(
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

  /// Competing Consumers: one channel feeding three consumer arrows.
  static VsdxShape eipCompetingConsumers({
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
    VsdxGeometry chevron(double tipX, double midY) => VsdxGeometry(
          commands: <VsdxPathCommand>[
            MoveTo(tipX - 14 / 150 * w, midY - 8 / 90 * h),
            LineTo(tipX, midY),
            LineTo(tipX - 14 / 150 * w, midY + 8 / 90 * h),
            LineTo(tipX - 8 / 150 * w, midY),
            LineTo(tipX - 14 / 150 * w, midY - 8 / 90 * h),
          ],
        );
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(11 / 150 * w, 0.5 * h),
          LineTo(56 / 150 * w, 0.5 * h),
          MoveTo(70 / 150 * w, (1 - 25 / 90) * h),
          LineTo(110 / 150 * w, (1 - 25 / 90) * h),
          MoveTo(70 / 150 * w, 0.5 * h),
          LineTo(110 / 150 * w, 0.5 * h),
          MoveTo(70 / 150 * w, (1 - 65 / 90) * h),
          LineTo(110 / 150 * w, (1 - 65 / 90) * h),
          MoveTo(56 / 150 * w, 0.5 * h),
          LineTo(70 / 150 * w, (1 - 25 / 90) * h),
          MoveTo(56 / 150 * w, 0.5 * h),
          LineTo(70 / 150 * w, 0.5 * h),
          MoveTo(56 / 150 * w, 0.5 * h),
          LineTo(70 / 150 * w, (1 - 65 / 90) * h),
        ]),
        chevron(125 / 150 * w, (1 - 25 / 90) * h),
        chevron(125 / 150 * w, 0.5 * h),
        chevron(125 / 150 * w, (1 - 65 / 90) * h),
        _eipArrowRight(68 / 150 * w, 0.5 * h, 12 / 150 * w, 6 / 90 * h),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Event Driven Consumer: inbound arrow into a consumer diamond.
  static VsdxShape eipEventDrivenConsumer({
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
        _eipOuterBox(w, h),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(11 / 150 * w, 0.5 * h),
          LineTo(56 / 150 * w, 0.5 * h),
        ]),
        _eipArrowRight(68 / 150 * w, 0.5 * h, 14 / 150 * w, 7 / 90 * h),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(124 / 150 * w, 0.5 * h),
          LineTo(132 / 150 * w, (1 - 37 / 90) * h),
          LineTo(140 / 150 * w, 0.5 * h),
          LineTo(132 / 150 * w, (1 - 53 / 90) * h),
          LineTo(124 / 150 * w, 0.5 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(102 / 150 * w, (1 - 39 / 90) * h),
          LineTo(102 / 150 * w, (1 - 51 / 90) * h),
          LineTo(115 / 150 * w, 0.5 * h),
          LineTo(102 / 150 * w, (1 - 39 / 90) * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Messaging Bridge: two half-channels linked by a bridge bar.
  static VsdxShape eipMessagingBridge({
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
    final cy = 0.5 * h;
    final t = 0.12 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(15 / 150 * w, cy - t),
          LineTo(55 / 150 * w, cy - t),
          LineTo(55 / 150 * w, cy + t),
          LineTo(15 / 150 * w, cy + t),
          LineTo(15 / 150 * w, cy - t),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(95 / 150 * w, cy - t),
          LineTo(135 / 150 * w, cy - t),
          LineTo(135 / 150 * w, cy + t),
          LineTo(95 / 150 * w, cy + t),
          LineTo(95 / 150 * w, cy - t),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(55 / 150 * w, cy),
          LineTo(95 / 150 * w, cy),
          MoveTo(70 / 150 * w, cy + 0.18 * h),
          LineTo(80 / 150 * w, cy + 0.18 * h),
          LineTo(80 / 150 * w, cy - 0.18 * h),
          LineTo(70 / 150 * w, cy - 0.18 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Process Manager: box with a control node and radiating links.
  static VsdxShape eipProcessManager({
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
    final cx = 0.5 * w;
    final cy = 0.42 * h;
    final r = 8 / 150 * w;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx, cy: cy, aX: cx + r, aY: cy, bX: cx, bY: cy + r),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(cx, cy),
          LineTo(30 / 150 * w, 20 / 90 * h),
          MoveTo(cx, cy),
          LineTo(75 / 150 * w, 15 / 90 * h),
          MoveTo(cx, cy),
          LineTo(120 / 150 * w, 20 / 90 * h),
          MoveTo(cx, cy),
          LineTo(40 / 150 * w, 70 / 90 * h),
          MoveTo(cx, cy),
          LineTo(110 / 150 * w, 70 / 90 * h),
        ]),
        _eipMessageSquare(22 / 150 * w, 12 / 90 * h, 14 / 150 * w, 14 / 90 * h),
        _eipMessageSquare(68 / 150 * w, 8 / 90 * h, 14 / 150 * w, 14 / 90 * h),
        _eipMessageSquare(112 / 150 * w, 12 / 90 * h, 14 / 150 * w, 14 / 90 * h),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Claim Check: large payload stub → claim ticket + small message.
  static VsdxShape eipClaimCheck({
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
    final sx = 16 / 150 * w;
    final sy = 16 / 90 * h;
    final lx = 25 / 150 * w;
    final ly = 25 / 90 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(10 / 150 * w, (1 - 53 / 90) * h),
          LineTo(10 / 150 * w + lx, (1 - 53 / 90) * h),
          LineTo(10 / 150 * w + lx, (1 - 53 / 90) * h + ly),
          LineTo(10 / 150 * w, (1 - 53 / 90) * h + ly),
          LineTo(10 / 150 * w, (1 - 53 / 90) * h),
        ]),
        _eipMessageSquare(124 / 150 * w, (1 - 53 / 90) * h, sx, sy),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(50 / 150 * w, 0.5 * h),
          LineTo(95 / 150 * w, 0.5 * h),
        ]),
        _eipArrowRight(100 / 150 * w, 0.5 * h, 13 / 150 * w, 6 / 90 * h),
        // Claim ticket (simplified stub).
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(118 / 150 * w, 12 / 90 * h),
          LineTo(142 / 150 * w, 12 / 90 * h),
          LineTo(146 / 150 * w, 18 / 90 * h),
          LineTo(142 / 150 * w, 24 / 90 * h),
          LineTo(118 / 150 * w, 24 / 90 * h),
          EllipticalArcTo(
              x: 118 / 150 * w,
              y: 12 / 90 * h,
              controlX: 112 / 150 * w,
              controlY: 18 / 90 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Resequencer: unordered inputs → ordered message chain.
  static VsdxShape eipResequencer({
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
    final sx = 16 / 150 * w;
    final sy = 16 / 90 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        _eipMessageSquare(22 / 150 * w, (1 - 32 / 90) * h, sx, sy),
        _eipMessageSquare(10 / 150 * w, (1 - 53 / 90) * h, sx, sy),
        _eipMessageSquare(22 / 150 * w, (1 - 76 / 90) * h, sx, sy),
        _eipMessageSquare(76 / 150 * w, (1 - 53 / 90) * h, sx, sy),
        _eipMessageSquare(100 / 150 * w, (1 - 53 / 90) * h, sx, sy),
        _eipMessageSquare(124 / 150 * w, (1 - 53 / 90) * h, sx, sy),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(35 / 150 * w, 0.5 * h),
          LineTo(65 / 150 * w, 0.5 * h),
        ]),
        _eipArrowRight(68.5 / 150 * w, 0.5 * h, 13 / 150 * w, 6 / 90 * h),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Composed Message Processor: split → process → aggregate pipeline.
  static VsdxShape eipComposedMessageProcessor({
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
    final sx = 16 / 150 * w;
    final sy = 16 / 90 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        _eipMessageSquare(10 / 150 * w, (1 - 53 / 90) * h, sx, sy),
        _eipMessageSquare(67 / 150 * w, (1 - 32 / 90) * h, sx, sy),
        _eipMessageSquare(67 / 150 * w, (1 - 53 / 90) * h, sx, sy),
        _eipMessageSquare(67 / 150 * w, (1 - 76 / 90) * h, sx, sy),
        _eipMessageSquare(124 / 150 * w, (1 - 53 / 90) * h, sx, sy),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(35 / 150 * w, 0.5 * h),
          LineTo(55 / 150 * w, 0.5 * h),
          MoveTo(95 / 150 * w, 0.5 * h),
          LineTo(115 / 150 * w, 0.5 * h),
        ]),
        _eipArrowRight(60 / 150 * w, 0.5 * h, 13 / 150 * w, 6 / 90 * h),
        _eipArrowRight(115 / 150 * w, 0.5 * h, 13 / 150 * w, 6 / 90 * h),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Content Filter: large message → smaller message.
  static VsdxShape eipContentFilter({
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
    final sx = 16 / 150 * w;
    final sy = 16 / 90 * h;
    final lx = 25 / 150 * w;
    final ly = 25 / 90 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(10 / 150 * w, (1 - 53 / 90) * h),
          LineTo(10 / 150 * w + lx, (1 - 53 / 90) * h),
          LineTo(10 / 150 * w + lx, (1 - 53 / 90) * h + ly),
          LineTo(10 / 150 * w, (1 - 53 / 90) * h + ly),
          LineTo(10 / 150 * w, (1 - 53 / 90) * h),
        ]),
        _eipMessageSquare(124 / 150 * w, (1 - 53 / 90) * h, sx, sy),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(50 / 150 * w, 0.5 * h),
          LineTo(95 / 150 * w, 0.5 * h),
          MoveTo(14 / 150 * w, (1 - 38 / 90) * h),
          LineTo(30 / 150 * w, (1 - 38 / 90) * h),
          MoveTo(14 / 150 * w, (1 - 45 / 90) * h),
          LineTo(30 / 150 * w, (1 - 45 / 90) * h),
          MoveTo(14 / 150 * w, (1 - 52 / 90) * h),
          LineTo(22 / 150 * w, (1 - 52 / 90) * h),
        ]),
        _eipArrowRight(100 / 150 * w, 0.5 * h, 13 / 150 * w, 6 / 90 * h),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Control Bus: compact rounded control pill.
  static VsdxShape eipControlBus({
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
    final r = 0.22 * math.min(w, h);
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.22 * w, 0.5 * h),
          LineTo(0.78 * w, 0.5 * h),
          MoveTo(0.35 * w, 0.28 * h),
          LineTo(0.35 * w, 0.72 * h),
          MoveTo(0.5 * w, 0.28 * h),
          LineTo(0.5 * w, 0.72 * h),
          MoveTo(0.65 * w, 0.28 * h),
          LineTo(0.65 * w, 0.72 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Detour: primary path with an alternate diagonal route.
  static VsdxShape eipDetour({
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
    VsdxGeometry dot(double cx, double cy) {
      final r = 4 / 150 * w;
      return VsdxGeometry(commands: <VsdxPathCommand>[
        EllipseCmd(
            cx: cx, cy: cy, aX: cx + r, aY: cy, bX: cx, bY: cy + r),
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
        _eipOuterBox(w, h),
        dot(45 / 150 * w, (1 - 66 / 90) * h),
        dot(105 / 150 * w, (1 - 24 / 90) * h),
        dot(105 / 150 * w, (1 - 66 / 90) * h),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(20 / 150 * w, (1 - 66 / 90) * h),
          LineTo(140 / 150 * w, (1 - 66 / 90) * h),
          MoveTo(105 / 150 * w, (1 - 24 / 90) * h),
          LineTo(45 / 150 * w, (1 - 66 / 90) * h),
          MoveTo(105 / 150 * w, (1 - 24 / 90) * h),
          LineTo(140 / 150 * w, (1 - 24 / 90) * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Durable Subscriber: mailbox / inbox glyph.
  static VsdxShape eipDurableSubscriber({
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
          MoveTo(0, (1 - 23 / 35) * h),
          LineTo(w, (1 - 23 / 35) * h),
          LineTo(w, (1 - 14 / 35) * h),
          EllipticalArcTo(
              x: 0,
              y: (1 - 14 / 35) * h,
              controlX: 0.5 * w,
              controlY: 0),
          LineTo(0, (1 - 23 / 35) * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, (1 - 23 / 35) * h),
          LineTo(0.2 * w, (1 - 30 / 35) * h),
          EllipticalArcTo(
              x: 0.8 * w,
              y: (1 - 30 / 35) * h,
              controlX: 0.5 * w,
              controlY: h),
          LineTo(0.8 * w, (1 - 23 / 35) * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.5 * w,
              cy: (1 - 18 / 35) * h,
              aX: 0.58 * w,
              aY: (1 - 18 / 35) * h,
              bX: 0.5 * w,
              bY: (1 - 12 / 35) * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Dynamic Router: hub with a dashed control drop line.
  static VsdxShape eipDynamicRouter({
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
    VsdxGeometry dot(double cx, double cy) {
      final r = 4 / 150 * w;
      return VsdxGeometry(commands: <VsdxPathCommand>[
        EllipseCmd(
            cx: cx, cy: cy, aX: cx + r, aY: cy, bX: cx, bY: cy + r),
      ]);
    }

    final hubX = 45 / 150 * w;
    final hubY = 0.5 * h;
    final outX = 105 / 150 * w;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        dot(hubX, hubY),
        dot(outX, (1 - 24 / 90) * h),
        dot(outX, 0.5 * h),
        dot(outX, (1 - 66 / 90) * h),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(10 / 150 * w, hubY),
          LineTo(hubX, hubY),
          MoveTo(hubX, hubY),
          LineTo(outX, (1 - 24 / 90) * h),
          MoveTo(hubX, hubY),
          LineTo(outX, 0.5 * h),
          MoveTo(outX, (1 - 24 / 90) * h),
          LineTo(140 / 150 * w, (1 - 24 / 90) * h),
          MoveTo(outX, 0.5 * h),
          LineTo(140 / 150 * w, 0.5 * h),
          MoveTo(outX, (1 - 66 / 90) * h),
          LineTo(140 / 150 * w, (1 - 66 / 90) * h),
          // Control drop (dashed appearance via segments).
          MoveTo(75 / 150 * w, (1 - 35 / 90) * h),
          LineTo(75 / 150 * w, (1 - 45 / 90) * h),
          MoveTo(75 / 150 * w, (1 - 52 / 90) * h),
          LineTo(75 / 150 * w, (1 - 62 / 90) * h),
          MoveTo(75 / 150 * w, (1 - 69 / 90) * h),
          LineTo(75 / 150 * w, (1 - 85 / 90) * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Envelope Wrapper: yellow envelope glyph inside the box.
  static VsdxShape eipEnvelopeWrapper({
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
    final x0 = 37 / 150 * w;
    final y0 = (1 - 68 / 90) * h;
    final ew = 76 / 150 * w;
    final eh = 46 / 90 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(x0, y0),
          LineTo(x0 + ew, y0),
          LineTo(x0 + ew, y0 + eh),
          LineTo(x0, y0 + eh),
          LineTo(x0, y0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(x0, y0 + eh),
          LineTo(x0 + 0.5 * ew, y0 + 0.45 * eh),
          LineTo(x0 + ew, y0 + eh),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Message Dispatcher: one input fanning to multiple consumers.
  static VsdxShape eipMessageDispatcher({
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
    VsdxGeometry diamond(double cx, double cy, double s) => VsdxGeometry(
          commands: <VsdxPathCommand>[
            MoveTo(cx - s, cy),
            LineTo(cx, cy + s),
            LineTo(cx + s, cy),
            LineTo(cx, cy - s),
            LineTo(cx - s, cy),
          ],
        );
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(11 / 150 * w, 0.5 * h),
          LineTo(56 / 150 * w, 0.5 * h),
          MoveTo(70 / 150 * w, 0.5 * h),
          LineTo(100 / 150 * w, (1 - 18 / 90) * h),
          MoveTo(70 / 150 * w, 0.5 * h),
          LineTo(100 / 150 * w, 0.5 * h),
          MoveTo(70 / 150 * w, 0.5 * h),
          LineTo(100 / 150 * w, (1 - 72 / 90) * h),
        ]),
        _eipArrowRight(68 / 150 * w, 0.5 * h, 14 / 150 * w, 7 / 90 * h),
        diamond(132 / 150 * w, (1 - 14 / 90) * h, 8 / 150 * w),
        diamond(132 / 150 * w, 0.5 * h, 8 / 150 * w),
        diamond(132 / 150 * w, (1 - 76 / 90) * h, 8 / 150 * w),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Message Store: cylinder / database drum.
  static VsdxShape eipMessageStore({
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
    final left = 40 / 150 * w;
    final right = 110 / 150 * w;
    final top = (1 - 25 / 90) * h;
    final bottom = (1 - 70 / 90) * h;
    final cx = 0.5 * (left + right);
    final ry = 5 / 90 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(left, top),
          EllipticalArcTo(
              x: right, y: top, controlX: cx, controlY: top + ry),
          LineTo(right, bottom),
          EllipticalArcTo(
              x: left, y: bottom, controlX: cx, controlY: bottom - ry),
          LineTo(left, top),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(left, top),
          EllipticalArcTo(
              x: right, y: top, controlX: cx, controlY: top - ry),
          MoveTo(left, 0.55 * h),
          EllipticalArcTo(
              x: right, y: 0.55 * h, controlX: cx, controlY: 0.55 * h - ry),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Normalizer: heterogeneous inputs → one canonical message.
  static VsdxShape eipNormalizer({
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
    final sx = 16 / 150 * w;
    final sy = 16 / 90 * h;
    final r = 8 / 150 * w;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 18 / 150 * w,
              cy: (1 - 27 / 90) * h,
              aX: 18 / 150 * w + r,
              aY: (1 - 27 / 90) * h,
              bX: 18 / 150 * w,
              bY: (1 - 27 / 90) * h + r),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(25 / 150 * w, 0.5 * h),
          LineTo(33 / 150 * w, (1 - 37 / 90) * h),
          LineTo(41 / 150 * w, 0.5 * h),
          LineTo(33 / 150 * w, (1 - 53 / 90) * h),
          LineTo(25 / 150 * w, 0.5 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(10 / 150 * w, (1 - 71 / 90) * h),
          LineTo(26 / 150 * w, (1 - 71 / 90) * h),
          LineTo(18 / 150 * w, (1 - 55 / 90) * h),
          LineTo(10 / 150 * w, (1 - 71 / 90) * h),
        ]),
        _eipMessageSquare(124 / 150 * w, (1 - 53 / 90) * h, sx, sy),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(50 / 150 * w, 0.5 * h),
          LineTo(95 / 150 * w, 0.5 * h),
        ]),
        _eipArrowRight(100 / 150 * w, 0.5 * h, 13 / 150 * w, 6 / 90 * h),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Polling Consumer: inbound channel with a polling arc.
  static VsdxShape eipPollingConsumer({
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
        _eipOuterBox(w, h),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(11 / 150 * w, 0.5 * h),
          LineTo(56 / 150 * w, 0.5 * h),
          MoveTo(55 / 150 * w, (1 - 54 / 90) * h),
          EllipticalArcTo(
              x: 55 / 150 * w,
              y: (1 - 36 / 90) * h,
              controlX: 90 / 150 * w,
              controlY: 0.5 * h),
        ]),
        _eipArrowRight(68 / 150 * w, 0.5 * h, 14 / 150 * w, 7 / 90 * h),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(124 / 150 * w, 0.5 * h),
          LineTo(132 / 150 * w, (1 - 37 / 90) * h),
          LineTo(140 / 150 * w, 0.5 * h),
          LineTo(132 / 150 * w, (1 - 53 / 90) * h),
          LineTo(124 / 150 * w, 0.5 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Routing Slip: chain of message squares.
  static VsdxShape eipRoutingSlip({
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
    final sx = 16 / 150 * w;
    final sy = 16 / 90 * h;
    final y = (1 - 53 / 90) * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        _eipMessageSquare(10 / 150 * w, y, sx, sy),
        _eipMessageSquare(48 / 150 * w, y, sx, sy),
        _eipMessageSquare(86 / 150 * w, y, sx, sy),
        _eipMessageSquare(124 / 150 * w, y, sx, sy),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(26 / 150 * w, 0.5 * h),
          LineTo(48 / 150 * w, 0.5 * h),
          MoveTo(64 / 150 * w, 0.5 * h),
          LineTo(86 / 150 * w, 0.5 * h),
          MoveTo(102 / 150 * w, 0.5 * h),
          LineTo(124 / 150 * w, 0.5 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Selective Consumer: channel through a selection ring.
  static VsdxShape eipSelectiveConsumer({
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
    final cx = 80 / 150 * w;
    final cy = 0.5 * h;
    final r = 20 / 150 * w;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx, cy: cy, aX: cx + r, aY: cy, bX: cx, bY: cy + r),
          MoveTo(11 / 150 * w, cy),
          LineTo(60 / 150 * w, cy),
          MoveTo(100 / 150 * w, cy),
          LineTo(130 / 150 * w, cy),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(124 / 150 * w, cy),
          LineTo(132 / 150 * w, cy + 8 / 90 * h),
          LineTo(140 / 150 * w, cy),
          LineTo(132 / 150 * w, cy - 8 / 90 * h),
          LineTo(124 / 150 * w, cy),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Service Activator: channel → activator diamond → service.
  static VsdxShape eipServiceActivator({
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
        _eipOuterBox(w, h),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(11 / 150 * w, 0.5 * h),
          LineTo(56 / 150 * w, 0.5 * h),
          MoveTo(85 / 150 * w, 0.5 * h),
          LineTo(105 / 150 * w, 0.5 * h),
        ]),
        _eipArrowRight(68 / 150 * w, 0.5 * h, 14 / 150 * w, 7 / 90 * h),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(61 / 150 * w, 0.5 * h),
          LineTo(69 / 150 * w, (1 - 37 / 90) * h),
          LineTo(77 / 150 * w, 0.5 * h),
          LineTo(69 / 150 * w, (1 - 53 / 90) * h),
          LineTo(61 / 150 * w, 0.5 * h),
        ]),
        _eipArrowRight(120 / 150 * w, 0.5 * h, 13 / 150 * w, 6 / 90 * h),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(124 / 150 * w, 0.5 * h),
          LineTo(132 / 150 * w, (1 - 37 / 90) * h),
          LineTo(140 / 150 * w, 0.5 * h),
          LineTo(132 / 150 * w, (1 - 53 / 90) * h),
          LineTo(124 / 150 * w, 0.5 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Smart Proxy: tall box with inbound fan-in and outbound arrow.
  static VsdxShape eipSmartProxy({
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
    VsdxGeometry dot(double cx, double cy) {
      final r = 4 / 70 * w;
      return VsdxGeometry(commands: <VsdxPathCommand>[
        EllipseCmd(
            cx: cx, cy: cy, aX: cx + r, aY: cy, bX: cx, bY: cy + r),
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
        _eipOuterBox(w, h),
        dot(25 / 70 * w, (1 - 25 / 90) * h),
        dot(25 / 70 * w, (1 - 58 / 90) * h),
        dot(25 / 70 * w, (1 - 69 / 90) * h),
        dot(25 / 70 * w, (1 - 80 / 90) * h),
        dot(45 / 70 * w, (1 - 69 / 90) * h),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(8 / 70 * w, (1 - 25 / 90) * h),
          LineTo(62 / 70 * w, (1 - 25 / 90) * h),
          MoveTo(8 / 70 * w, (1 - 58 / 90) * h),
          LineTo(25 / 70 * w, (1 - 58 / 90) * h),
          MoveTo(8 / 70 * w, (1 - 69 / 90) * h),
          LineTo(25 / 70 * w, (1 - 69 / 90) * h),
          MoveTo(8 / 70 * w, (1 - 80 / 90) * h),
          LineTo(25 / 70 * w, (1 - 80 / 90) * h),
          MoveTo(25 / 70 * w, (1 - 58 / 90) * h),
          LineTo(45 / 70 * w, (1 - 69 / 90) * h),
          MoveTo(45 / 70 * w, (1 - 69 / 90) * h),
          LineTo(62 / 70 * w, (1 - 69 / 90) * h),
          MoveTo(0.5 * w, (1 - 25 / 90) * h),
          LineTo(0.5 * w, (1 - 33 / 90) * h),
          MoveTo(0.5 * w, (1 - 39 / 90) * h),
          LineTo(0.5 * w, (1 - 50 / 90) * h),
          MoveTo(0.5 * w, (1 - 54 / 90) * h),
          LineTo(0.5 * w, (1 - 63 / 90) * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.5 * w - 4 / 70 * w, (1 - 33 / 90) * h),
          LineTo(0.5 * w + 4 / 70 * w, (1 - 33 / 90) * h),
          LineTo(0.5 * w, (1 - 39 / 90) * h),
          LineTo(0.5 * w - 4 / 70 * w, (1 - 33 / 90) * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Transactional Client: client oval + message square on a channel.
  static VsdxShape eipTransactionalClient({
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
    final cx = 85 / 150 * w;
    final cy = 0.5 * h;
    final rx = 55 / 150 * w;
    final ry = 33 / 90 * h;
    final sx = 26 / 150 * w;
    final sy = 26 / 90 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: cy,
              aX: cx + rx,
              aY: cy,
              bX: cx,
              bY: cy + ry),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(88 / 150 * w, (1 - 58 / 90) * h),
          LineTo(88 / 150 * w + sx, (1 - 58 / 90) * h),
          LineTo(88 / 150 * w + sx, (1 - 58 / 90) * h + sy),
          LineTo(88 / 150 * w, (1 - 58 / 90) * h + sy),
          LineTo(88 / 150 * w, (1 - 58 / 90) * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(11 / 150 * w, 0.5 * h),
          LineTo(56 / 150 * w, 0.5 * h),
        ]),
        _eipArrowRight(68 / 150 * w, 0.5 * h, 14 / 150 * w, 7 / 90 * h),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Channel Purger: funnel / trash glyph emptying the channel.
  static VsdxShape eipChannelPurger({
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
    double xOf(double x) => x / 150 * w;
    double yOf(double yTop) => (1 - yTop / 90) * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(xOf(50), yOf(20)),
          LineTo(xOf(100), yOf(20)),
          LineTo(xOf(85), yOf(70)),
          LineTo(xOf(65), yOf(70)),
          LineTo(xOf(50), yOf(20)),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(xOf(65), yOf(70)),
          LineTo(xOf(50), yOf(20)),
          LineTo(xOf(85), yOf(20)),
          LineTo(xOf(78), yOf(70)),
          LineTo(xOf(65), yOf(70)),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Test Message: probe circle injecting into an outbound message chain.
  static VsdxShape eipTestMessage({
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
    final sx = 16 / 150 * w;
    final sy = 16 / 90 * h;
    final r = 8 / 150 * w;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        _eipOuterBox(w, h),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 18 / 150 * w,
              cy: 0.5 * h,
              aX: 18 / 150 * w + r,
              aY: 0.5 * h,
              bX: 18 / 150 * w,
              bY: 0.5 * h + r),
        ]),
        _eipMessageSquare(76 / 150 * w, (1 - 53 / 90) * h, sx, sy),
        _eipMessageSquare(100 / 150 * w, (1 - 53 / 90) * h, sx, sy),
        _eipMessageSquare(124 / 150 * w, (1 - 53 / 90) * h, sx, sy),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(24 / 150 * w, 0.5 * h),
          LineTo(63 / 150 * w, 0.5 * h),
        ]),
        _eipArrowRight(68.5 / 150 * w, 0.5 * h, 13 / 150 * w, 6 / 90 * h),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Datatype Channel: message pipe with typed marker squares.
  static VsdxShape eipDatatypeChannel({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final base = eipMessageChannel(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      fill: fill,
      line: line,
      name: name,
    );
    final w = width.abs();
    final h = height.abs();
    final cy = 0.5 * h;
    final side = 0.28 * h;
    final geos = <VsdxGeometry>[...base.geometries];
    for (var i = 1; i * 0.22 * w + 0.12 * w < w - 0.15 * w; i++) {
      final x = i * 0.22 * w;
      geos.add(_eipMessageSquare(x, cy - 0.5 * side, side, side));
    }
    return base.copyWith(geometries: geos);
  }

  /// Invalid Message Channel: pipe with a warning triangle marker.
  static VsdxShape eipInvalidMessageChannel({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    VsdxFill fill = _defaultFill,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final base = eipMessageChannel(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      fill: fill,
      line: line,
      name: name,
    );
    final w = width.abs();
    final h = height.abs();
    final cx = 0.5 * w;
    final cy = 0.5 * h;
    return base.copyWith(geometries: <VsdxGeometry>[
      ...base.geometries,
      VsdxGeometry(commands: <VsdxPathCommand>[
        MoveTo(cx, cy + 0.22 * h),
        LineTo(cx - 0.18 * h, cy - 0.18 * h),
        LineTo(cx + 0.18 * h, cy - 0.18 * h),
        LineTo(cx, cy + 0.22 * h),
      ]),
      VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
        MoveTo(cx, cy - 0.08 * h),
        LineTo(cx, cy + 0.06 * h),
        MoveTo(cx, cy + 0.1 * h),
        LineTo(cx, cy + 0.14 * h),
      ]),
    ]);
  }

  // ---------------------------------------------------------------------------
  // AWS architecture starters (draw.io mxgraph.aws4.*) — geometric icons.
  // Not brand-mark replicas; clean compute / storage / messaging glyphs.
  // ---------------------------------------------------------------------------

  /// EC2: compute instance (cube with face accents).
  static VsdxShape awsEc2({
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
    final d = 0.22 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, 0),
          LineTo(w - d, 0),
          LineTo(w - d, h - d),
          LineTo(0, h - d),
          LineTo(0, 0),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(w - d, 0),
          LineTo(w, d),
          LineTo(w, h),
          LineTo(w - d, h - d),
          LineTo(w - d, 0),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0, h - d),
          LineTo(w - d, h - d),
          LineTo(w, h),
          LineTo(d, h),
          LineTo(0, h - d),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.18 * w, 0.25 * (h - d)),
          LineTo(0.72 * (w - d), 0.25 * (h - d)),
          MoveTo(0.18 * w, 0.45 * (h - d)),
          LineTo(0.72 * (w - d), 0.45 * (h - d)),
          MoveTo(0.18 * w, 0.65 * (h - d)),
          LineTo(0.55 * (w - d), 0.65 * (h - d)),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// S3: storage bucket (trapezoid body + lid).
  static VsdxShape awsS3({
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
          MoveTo(0.12 * w, 0.78 * h),
          LineTo(0.88 * w, 0.78 * h),
          LineTo(0.78 * w, 0.15 * h),
          LineTo(0.22 * w, 0.15 * h),
          LineTo(0.12 * w, 0.78 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.18 * w, 0.15 * h),
          LineTo(0.82 * w, 0.15 * h),
          LineTo(0.82 * w, 0.28 * h),
          LineTo(0.18 * w, 0.28 * h),
          LineTo(0.18 * w, 0.15 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.5 * w, 0.28 * h),
          LineTo(0.5 * w, 0.72 * h),
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.55 * h,
              aX: 0.62 * w,
              aY: 0.55 * h,
              bX: 0.5 * w,
              bY: 0.66 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Lambda: hexagon function badge.
  static VsdxShape awsLambda({
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
          MoveTo(0.25 * w, h),
          LineTo(0.75 * w, h),
          LineTo(w, 0.5 * h),
          LineTo(0.75 * w, 0),
          LineTo(0.25 * w, 0),
          LineTo(0, 0.5 * h),
          LineTo(0.25 * w, h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.32 * w, 0.78 * h),
          LineTo(0.48 * w, 0.78 * h),
          LineTo(0.62 * w, 0.22 * h),
          LineTo(0.78 * w, 0.22 * h),
          MoveTo(0.4 * w, 0.5 * h),
          LineTo(0.68 * w, 0.5 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// VPC: region cloud with dashed-style perimeter segments.
  static VsdxShape awsVpc({
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
    final r = 0.12 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(r, h),
          LineTo(w - r, h),
          EllipticalArcTo(x: w, y: h - r, controlX: w, controlY: h),
          LineTo(w, r),
          EllipticalArcTo(x: w - r, y: 0, controlX: w, controlY: 0),
          LineTo(r, 0),
          EllipticalArcTo(x: 0, y: r, controlX: 0, controlY: 0),
          LineTo(0, h - r),
          EllipticalArcTo(x: r, y: h, controlX: 0, controlY: h),
          MoveTo(0.2 * w, 0.35 * h),
          LineTo(0.45 * w, 0.35 * h),
          MoveTo(0.55 * w, 0.35 * h),
          LineTo(0.8 * w, 0.35 * h),
          MoveTo(0.2 * w, 0.65 * h),
          LineTo(0.45 * w, 0.65 * h),
          MoveTo(0.55 * w, 0.65 * h),
          LineTo(0.8 * w, 0.65 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.28 * w,
              cy: 0.5 * h,
              aX: 0.4 * w,
              aY: 0.5 * h,
              bX: 0.28 * w,
              bY: 0.62 * h),
          EllipseCmd(
              cx: 0.55 * w,
              cy: 0.5 * h,
              aX: 0.72 * w,
              aY: 0.5 * h,
              bX: 0.55 * w,
              bY: 0.68 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// RDS: relational database drum.
  static VsdxShape awsRds({
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
    final cx = 0.5 * w;
    final top = 0.78 * h;
    final bottom = 0.18 * h;
    final ry = 0.1 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.15 * w, top),
          EllipticalArcTo(
              x: 0.85 * w, y: top, controlX: cx, controlY: top + ry),
          LineTo(0.85 * w, bottom),
          EllipticalArcTo(
              x: 0.15 * w, y: bottom, controlX: cx, controlY: bottom - ry),
          LineTo(0.15 * w, top),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.15 * w, top),
          EllipticalArcTo(
              x: 0.85 * w, y: top, controlX: cx, controlY: top - ry),
          MoveTo(0.15 * w, 0.55 * h),
          EllipticalArcTo(
              x: 0.85 * w,
              y: 0.55 * h,
              controlX: cx,
              controlY: 0.55 * h - ry),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// DynamoDB: three stacked table slabs.
  static VsdxShape awsDynamoDb({
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
    VsdxGeometry slab(double y0, double y1) => VsdxGeometry(
          commands: <VsdxPathCommand>[
            MoveTo(0.1 * w, y0),
            LineTo(0.9 * w, y0),
            LineTo(0.9 * w, y1),
            LineTo(0.1 * w, y1),
            LineTo(0.1 * w, y0),
          ],
        );
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        slab(0.72 * h, 0.95 * h),
        slab(0.42 * h, 0.65 * h),
        slab(0.12 * h, 0.35 * h),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.28 * w, 0.83 * h),
          LineTo(0.72 * w, 0.83 * h),
          MoveTo(0.28 * w, 0.53 * h),
          LineTo(0.72 * w, 0.53 * h),
          MoveTo(0.28 * w, 0.23 * h),
          LineTo(0.72 * w, 0.23 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// SQS: message queue (rail + message cards).
  static VsdxShape awsSqs({
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
    final cardW = 0.18 * w;
    final cardH = 0.45 * h;
    final y = 0.28 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.08 * w, 0.5 * h),
          LineTo(0.92 * w, 0.5 * h),
          MoveTo(0.08 * w, 0.35 * h),
          LineTo(0.08 * w, 0.65 * h),
          MoveTo(0.92 * w, 0.35 * h),
          LineTo(0.92 * w, 0.65 * h),
        ]),
        for (final x in <double>[0.16, 0.4, 0.64])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(x * w, y),
            LineTo(x * w + cardW, y),
            LineTo(x * w + cardW, y + cardH),
            LineTo(x * w, y + cardH),
            LineTo(x * w, y),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// SNS: notification hub with fan-out.
  static VsdxShape awsSns({
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
    final cx = 0.35 * w;
    final cy = 0.5 * h;
    final r = 0.14 * math.min(w, h);
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
              cx: cx, cy: cy, aX: cx + r, aY: cy, bX: cx, bY: cy + r),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.08 * w, cy),
          LineTo(cx - r, cy),
          MoveTo(cx + r, cy),
          LineTo(0.72 * w, 0.22 * h),
          MoveTo(cx + r, cy),
          LineTo(0.78 * w, cy),
          MoveTo(cx + r, cy),
          LineTo(0.72 * w, 0.78 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.82 * w,
              cy: 0.22 * h,
              aX: 0.9 * w,
              aY: 0.22 * h,
              bX: 0.82 * w,
              bY: 0.3 * h),
          EllipseCmd(
              cx: 0.88 * w,
              cy: cy,
              aX: 0.96 * w,
              aY: cy,
              bX: 0.88 * w,
              bY: cy + 0.08 * h),
          EllipseCmd(
              cx: 0.82 * w,
              cy: 0.78 * h,
              aX: 0.9 * w,
              aY: 0.78 * h,
              bX: 0.82 * w,
              bY: 0.86 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// CloudFront: edge / CDN globe.
  static VsdxShape awsCloudFront({
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
    final cx = 0.5 * w;
    final cy = 0.5 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(cx: cx, cy: cy, aX: w, aY: cy, bX: cx, bY: 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: cy,
              aX: cx + 0.28 * w,
              aY: cy,
              bX: cx,
              bY: h),
          MoveTo(0.08 * w, cy),
          LineTo(0.92 * w, cy),
          MoveTo(cx, 0.08 * h),
          LineTo(cx, 0.92 * h),
          MoveTo(0.2 * w, 0.25 * h),
          LineTo(0.8 * w, 0.25 * h),
          MoveTo(0.2 * w, 0.75 * h),
          LineTo(0.8 * w, 0.75 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// API Gateway: portal arch over a channel.
  static VsdxShape awsApiGateway({
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
          MoveTo(0.15 * w, 0),
          LineTo(0.85 * w, 0),
          LineTo(0.85 * w, 0.35 * h),
          EllipticalArcTo(
              x: 0.15 * w, y: 0.35 * h, controlX: 0.5 * w, controlY: 0.7 * h),
          LineTo(0.15 * w, 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.05 * w, 0.55 * h),
          LineTo(0.35 * w, 0.55 * h),
          MoveTo(0.65 * w, 0.55 * h),
          LineTo(0.95 * w, 0.55 * h),
          MoveTo(0.35 * w, 0.4 * h),
          LineTo(0.35 * w, 0.7 * h),
          MoveTo(0.65 * w, 0.4 * h),
          LineTo(0.65 * w, 0.7 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.42 * w, 0.48 * h),
          LineTo(0.58 * w, 0.55 * h),
          LineTo(0.42 * w, 0.62 * h),
          LineTo(0.42 * w, 0.48 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IAM: identity key inside a shield.
  static VsdxShape awsIam({
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
          MoveTo(0.5 * w, h),
          LineTo(0.92 * w, 0.72 * h),
          LineTo(0.92 * w, 0.35 * h),
          EllipticalArcTo(
              x: 0.08 * w, y: 0.35 * h, controlX: 0.5 * w, controlY: 0.05 * h),
          LineTo(0.08 * w, 0.72 * h),
          LineTo(0.5 * w, h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.38 * w,
              cy: 0.48 * h,
              aX: 0.5 * w,
              aY: 0.48 * h,
              bX: 0.38 * w,
              bY: 0.6 * h),
          MoveTo(0.48 * w, 0.48 * h),
          LineTo(0.78 * w, 0.48 * h),
          LineTo(0.78 * w, 0.38 * h),
          MoveTo(0.68 * w, 0.48 * h),
          LineTo(0.68 * w, 0.42 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// ELB: classic load balancer (bar + three targets).
  static VsdxShape awsElb({
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
          MoveTo(0.1 * w, 0.7 * h),
          LineTo(0.9 * w, 0.7 * h),
          LineTo(0.9 * w, 0.88 * h),
          LineTo(0.1 * w, 0.88 * h),
          LineTo(0.1 * w, 0.7 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.5 * w, 0.7 * h),
          LineTo(0.5 * w, 0.52 * h),
          MoveTo(0.22 * w, 0.52 * h),
          LineTo(0.78 * w, 0.52 * h),
          MoveTo(0.22 * w, 0.52 * h),
          LineTo(0.22 * w, 0.35 * h),
          MoveTo(0.5 * w, 0.52 * h),
          LineTo(0.5 * w, 0.35 * h),
          MoveTo(0.78 * w, 0.52 * h),
          LineTo(0.78 * w, 0.35 * h),
        ]),
        for (final x in <double>[0.12, 0.4, 0.68])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(x * w, 0.08 * h),
            LineTo(x * w + 0.2 * w, 0.08 * h),
            LineTo(x * w + 0.2 * w, 0.35 * h),
            LineTo(x * w, 0.35 * h),
            LineTo(x * w, 0.08 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// ECS: container cluster (hex cells).
  static VsdxShape awsEcs({
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
    List<VsdxPathCommand> hex(double cx, double cy, double r) =>
        <VsdxPathCommand>[
          MoveTo(cx + r, cy),
          LineTo(cx + 0.5 * r, cy + 0.866 * r),
          LineTo(cx - 0.5 * r, cy + 0.866 * r),
          LineTo(cx - r, cy),
          LineTo(cx - 0.5 * r, cy - 0.866 * r),
          LineTo(cx + 0.5 * r, cy - 0.866 * r),
          LineTo(cx + r, cy),
        ];
    final r = 0.2 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: hex(0.32 * w, 0.58 * h, r)),
        VsdxGeometry(commands: hex(0.68 * w, 0.58 * h, r)),
        VsdxGeometry(commands: hex(0.5 * w, 0.28 * h, r)),
      ],
      fill: fill,
      line: line,
    );
  }

  /// EKS: Kubernetes-style wheel of hex pods.
  static VsdxShape awsEks({
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
    final cx = 0.5 * w;
    final cy = 0.5 * h;
    final r = 0.42 * math.min(w, h);
    final geos = <VsdxGeometry>[
      VsdxGeometry(commands: <VsdxPathCommand>[
        EllipseCmd(cx: cx, cy: cy, aX: cx + r, aY: cy, bX: cx, bY: cy + r),
      ]),
      VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
        for (var i = 0; i < 6; i++) ...[
          MoveTo(cx, cy),
          LineTo(
            cx + r * math.cos(i * math.pi / 3),
            cy + r * math.sin(i * math.pi / 3),
          ),
        ],
      ]),
    ];
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3 + math.pi / 6;
      final px = cx + 0.62 * r * math.cos(a);
      final py = cy + 0.62 * r * math.sin(a);
      final pr = 0.12 * r;
      geos.add(VsdxGeometry(commands: <VsdxPathCommand>[
        EllipseCmd(
            cx: px, cy: py, aX: px + pr, aY: py, bX: px, bY: py + pr),
      ]));
    }
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: geos,
      fill: fill,
      line: line,
    );
  }

  /// Step Functions: state-machine workflow (rounded boxes + arrows).
  static VsdxShape awsStepFunctions({
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
    final r = 0.08 * math.min(w, h);
    VsdxGeometry box(double x0, double y0, double x1, double y1) {
      return VsdxGeometry(commands: <VsdxPathCommand>[
        MoveTo(x0 + r, y1),
        LineTo(x1 - r, y1),
        EllipticalArcTo(x: x1, y: y1 - r, controlX: x1, controlY: y1),
        LineTo(x1, y0 + r),
        EllipticalArcTo(x: x1 - r, y: y0, controlX: x1, controlY: y0),
        LineTo(x0 + r, y0),
        EllipticalArcTo(x: x0, y: y0 + r, controlX: x0, controlY: y0),
        LineTo(x0, y1 - r),
        EllipticalArcTo(x: x0 + r, y: y1, controlX: x0, controlY: y1),
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
        box(0.1 * w, 0.7 * h, 0.45 * w, 0.92 * h),
        box(0.55 * w, 0.4 * h, 0.9 * w, 0.62 * h),
        box(0.1 * w, 0.1 * h, 0.45 * w, 0.32 * h),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.45 * w, 0.81 * h),
          LineTo(0.55 * w, 0.81 * h),
          LineTo(0.55 * w, 0.51 * h),
          MoveTo(0.55 * w, 0.51 * h),
          LineTo(0.45 * w, 0.51 * h),
          LineTo(0.45 * w, 0.21 * h),
          MoveTo(0.5 * w, 0.81 * h),
          LineTo(0.55 * w, 0.81 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.55 * w, 0.51 * h),
          LineTo(0.5 * w, 0.56 * h),
          LineTo(0.5 * w, 0.46 * h),
          LineTo(0.55 * w, 0.51 * h),
          MoveTo(0.28 * w, 0.32 * h),
          LineTo(0.33 * w, 0.38 * h),
          LineTo(0.23 * w, 0.38 * h),
          LineTo(0.28 * w, 0.32 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// CloudWatch: monitoring gauge / eye.
  static VsdxShape awsCloudWatch({
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
    final cx = 0.5 * w;
    final cy = 0.48 * h;
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
              cx: cx, cy: cy, aX: 0.92 * w, aY: cy, bX: cx, bY: 0.18 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: cy,
              aX: cx + 0.18 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.18 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(cx, cy),
          LineTo(cx + 0.22 * w, cy + 0.22 * h),
          MoveTo(0.15 * w, 0.12 * h),
          LineTo(0.35 * w, 0.22 * h),
          MoveTo(0.85 * w, 0.12 * h),
          LineTo(0.65 * w, 0.22 * h),
          MoveTo(0.2 * w, 0.85 * h),
          LineTo(0.8 * w, 0.85 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Kinesis: streaming data waves.
  static VsdxShape awsKinesis({
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.25, 0.5, 0.75]) ...[
            MoveTo(0.08 * w, y * h),
            EllipticalArcTo(
                x: 0.35 * w,
                y: y * h,
                controlX: 0.22 * w,
                controlY: y * h + 0.12 * h),
            EllipticalArcTo(
                x: 0.65 * w,
                y: y * h,
                controlX: 0.5 * w,
                controlY: y * h - 0.12 * h),
            EllipticalArcTo(
                x: 0.92 * w,
                y: y * h,
                controlX: 0.78 * w,
                controlY: y * h + 0.12 * h),
          ],
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.78 * w, 0.42 * h),
          LineTo(0.95 * w, 0.5 * h),
          LineTo(0.78 * w, 0.58 * h),
          LineTo(0.78 * w, 0.42 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// ElastiCache: stacked cache tiers.
  static VsdxShape awsElastiCache({
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
        for (final entry in <List<double>>[
          [0.15, 0.7, 0.85, 0.92],
          [0.22, 0.42, 0.78, 0.64],
          [0.3, 0.14, 0.7, 0.36],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(entry[0] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[1] * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.35 * w, 0.81 * h),
          LineTo(0.65 * w, 0.81 * h),
          MoveTo(0.4 * w, 0.53 * h),
          LineTo(0.6 * w, 0.53 * h),
          MoveTo(0.42 * w, 0.25 * h),
          LineTo(0.58 * w, 0.25 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Redshift: columnar analytics warehouse.
  static VsdxShape awsRedshift({
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
          MoveTo(0.1 * w, 0.15 * h),
          LineTo(0.9 * w, 0.15 * h),
          LineTo(0.9 * w, 0.9 * h),
          LineTo(0.1 * w, 0.9 * h),
          LineTo(0.1 * w, 0.15 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final x in <double>[0.3, 0.5, 0.7]) ...[
            MoveTo(x * w, 0.22 * h),
            LineTo(x * w, 0.82 * h),
          ],
          MoveTo(0.18 * w, 0.35 * h),
          LineTo(0.82 * w, 0.35 * h),
          MoveTo(0.18 * w, 0.55 * h),
          LineTo(0.82 * w, 0.55 * h),
          MoveTo(0.18 * w, 0.75 * h),
          LineTo(0.82 * w, 0.75 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// EventBridge: event bus with radiating rules.
  static VsdxShape awsEventBridge({
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
    final cx = 0.5 * w;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.15 * w, 0.4 * h),
          LineTo(0.85 * w, 0.4 * h),
          LineTo(0.85 * w, 0.6 * h),
          LineTo(0.15 * w, 0.6 * h),
          LineTo(0.15 * w, 0.4 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(cx, 0.6 * h),
          LineTo(0.22 * w, 0.15 * h),
          MoveTo(cx, 0.6 * h),
          LineTo(cx, 0.12 * h),
          MoveTo(cx, 0.6 * h),
          LineTo(0.78 * w, 0.15 * h),
          MoveTo(cx, 0.4 * h),
          LineTo(0.22 * w, 0.85 * h),
          MoveTo(cx, 0.4 * h),
          LineTo(cx, 0.88 * h),
          MoveTo(cx, 0.4 * h),
          LineTo(0.78 * w, 0.85 * h),
        ]),
        for (final p in <List<double>>[
          [0.22, 0.15],
          [0.5, 0.12],
          [0.78, 0.15],
          [0.22, 0.85],
          [0.5, 0.88],
          [0.78, 0.85],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.05 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Cognito: user pool (people + circle).
  static VsdxShape awsCognito({
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.5 * h,
              aX: 0.92 * w,
              aY: 0.5 * h,
              bX: 0.5 * w,
              bY: 0.08 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.58 * h,
              aX: 0.62 * w,
              aY: 0.58 * h,
              bX: 0.5 * w,
              bY: 0.7 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.32 * w, 0.22 * h),
          LineTo(0.68 * w, 0.22 * h),
          LineTo(0.72 * w, 0.42 * h),
          LineTo(0.28 * w, 0.42 * h),
          LineTo(0.32 * w, 0.22 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Route 53: DNS globe with route markers.
  static VsdxShape awsRoute53({
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
    final cx = 0.5 * w;
    final cy = 0.5 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(cx: cx, cy: cy, aX: w, aY: cy, bX: cx, bY: 0),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: cy,
              aX: cx + 0.25 * w,
              aY: cy,
              bX: cx,
              bY: h),
          MoveTo(0.1 * w, cy),
          LineTo(0.9 * w, cy),
          MoveTo(0.2 * w, 0.28 * h),
          LineTo(0.8 * w, 0.28 * h),
          MoveTo(0.2 * w, 0.72 * h),
          LineTo(0.8 * w, 0.72 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.5 * w, 0.78 * h),
          LineTo(0.62 * w, 0.55 * h),
          LineTo(0.5 * w, 0.6 * h),
          LineTo(0.38 * w, 0.55 * h),
          LineTo(0.5 * w, 0.78 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// EFS: shared filesystem tree nodes.
  static VsdxShape awsEfs({
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
          MoveTo(0.35 * w, 0.7 * h),
          LineTo(0.65 * w, 0.7 * h),
          LineTo(0.65 * w, 0.95 * h),
          LineTo(0.35 * w, 0.95 * h),
          LineTo(0.35 * w, 0.7 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.5 * w, 0.7 * h),
          LineTo(0.5 * w, 0.48 * h),
          MoveTo(0.2 * w, 0.48 * h),
          LineTo(0.8 * w, 0.48 * h),
          MoveTo(0.2 * w, 0.48 * h),
          LineTo(0.2 * w, 0.32 * h),
          MoveTo(0.5 * w, 0.48 * h),
          LineTo(0.5 * w, 0.32 * h),
          MoveTo(0.8 * w, 0.48 * h),
          LineTo(0.8 * w, 0.32 * h),
        ]),
        for (final x in <double>[0.08, 0.38, 0.68])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(x * w, 0.08 * h),
            LineTo(x * w + 0.24 * w, 0.08 * h),
            LineTo(x * w + 0.24 * w, 0.32 * h),
            LineTo(x * w, 0.32 * h),
            LineTo(x * w, 0.08 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Aurora: clustered relational engine (primary + replicas).
  static VsdxShape awsAurora({
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
    final cx = 0.5 * w;
    final top = 0.85 * h;
    final bottom = 0.45 * h;
    final ry = 0.08 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, top),
          EllipticalArcTo(
              x: 0.8 * w, y: top, controlX: cx, controlY: top + ry),
          LineTo(0.8 * w, bottom),
          EllipticalArcTo(
              x: 0.2 * w, y: bottom, controlX: cx, controlY: bottom - ry),
          LineTo(0.2 * w, top),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, top),
          EllipticalArcTo(
              x: 0.8 * w, y: top, controlX: cx, controlY: top - ry),
          MoveTo(0.35 * w, 0.45 * h),
          LineTo(0.22 * w, 0.18 * h),
          MoveTo(0.5 * w, 0.45 * h),
          LineTo(0.5 * w, 0.15 * h),
          MoveTo(0.65 * w, 0.45 * h),
          LineTo(0.78 * w, 0.18 * h),
        ]),
        for (final p in <List<double>>[
          [0.22, 0.18],
          [0.5, 0.15],
          [0.78, 0.18],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.07 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.07 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Fargate: serverless container capsule.
  static VsdxShape awsFargate({
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
    final r = 0.22 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(r, 0.78 * h),
          LineTo(w - r, 0.78 * h),
          EllipticalArcTo(
              x: w, y: 0.78 * h - r, controlX: w, controlY: 0.78 * h),
          LineTo(w, 0.22 * h + r),
          EllipticalArcTo(
              x: w - r, y: 0.22 * h, controlX: w, controlY: 0.22 * h),
          LineTo(r, 0.22 * h),
          EllipticalArcTo(
              x: 0, y: 0.22 * h + r, controlX: 0, controlY: 0.22 * h),
          LineTo(0, 0.78 * h - r),
          EllipticalArcTo(x: r, y: 0.78 * h, controlX: 0, controlY: 0.78 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.4 * h),
          LineTo(0.8 * w, 0.4 * h),
          MoveTo(0.2 * w, 0.55 * h),
          LineTo(0.65 * w, 0.55 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.7 * w, 0.48 * h),
          LineTo(0.85 * w, 0.58 * h),
          LineTo(0.7 * w, 0.68 * h),
          LineTo(0.7 * w, 0.48 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// ECR: container registry vault with tag.
  static VsdxShape awsEcr({
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
          MoveTo(0.15 * w, 0.2 * h),
          LineTo(0.85 * w, 0.2 * h),
          LineTo(0.85 * w, 0.85 * h),
          LineTo(0.15 * w, 0.85 * h),
          LineTo(0.15 * w, 0.2 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.55 * w, 0.32 * h),
          LineTo(0.78 * w, 0.32 * h),
          LineTo(0.78 * w, 0.52 * h),
          LineTo(0.55 * w, 0.52 * h),
          LineTo(0.55 * w, 0.32 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.25 * w, 0.38 * h),
          LineTo(0.48 * w, 0.38 * h),
          MoveTo(0.25 * w, 0.55 * h),
          LineTo(0.48 * w, 0.55 * h),
          MoveTo(0.25 * w, 0.7 * h),
          LineTo(0.7 * w, 0.7 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Glue: ETL funnel with transform stages.
  static VsdxShape awsGlue({
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
          MoveTo(0.1 * w, 0.15 * h),
          LineTo(0.9 * w, 0.15 * h),
          LineTo(0.68 * w, 0.48 * h),
          LineTo(0.68 * w, 0.85 * h),
          LineTo(0.32 * w, 0.85 * h),
          LineTo(0.32 * w, 0.48 * h),
          LineTo(0.1 * w, 0.15 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.22 * w, 0.3 * h),
          LineTo(0.78 * w, 0.3 * h),
          MoveTo(0.4 * w, 0.58 * h),
          LineTo(0.6 * w, 0.58 * h),
          MoveTo(0.4 * w, 0.72 * h),
          LineTo(0.6 * w, 0.72 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Athena: query magnifier over table grid.
  static VsdxShape awsAthena({
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
          MoveTo(0.1 * w, 0.15 * h),
          LineTo(0.7 * w, 0.15 * h),
          LineTo(0.7 * w, 0.7 * h),
          LineTo(0.1 * w, 0.7 * h),
          LineTo(0.1 * w, 0.15 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.22 * w, 0.35 * h),
          LineTo(0.58 * w, 0.35 * h),
          MoveTo(0.22 * w, 0.5 * h),
          LineTo(0.58 * w, 0.5 * h),
          MoveTo(0.35 * w, 0.22 * h),
          LineTo(0.35 * w, 0.62 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.72 * w,
              cy: 0.62 * h,
              aX: 0.88 * w,
              aY: 0.62 * h,
              bX: 0.72 * w,
              bY: 0.78 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.84 * w, 0.74 * h),
          LineTo(0.95 * w, 0.9 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// EMR: Hadoop/Spark cluster hexes.
  static VsdxShape awsEmr({
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
    List<VsdxPathCommand> hex(double cx, double cy, double r) =>
        <VsdxPathCommand>[
          MoveTo(cx + r, cy),
          LineTo(cx + 0.5 * r, cy + 0.866 * r),
          LineTo(cx - 0.5 * r, cy + 0.866 * r),
          LineTo(cx - r, cy),
          LineTo(cx - 0.5 * r, cy - 0.866 * r),
          LineTo(cx + 0.5 * r, cy - 0.866 * r),
          LineTo(cx + r, cy),
        ];
    final r = 0.18 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: hex(0.3 * w, 0.58 * h, r)),
        VsdxGeometry(commands: hex(0.7 * w, 0.58 * h, r)),
        VsdxGeometry(commands: hex(0.5 * w, 0.28 * h, r)),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.3 * w, 0.58 * h),
          LineTo(0.5 * w, 0.28 * h),
          LineTo(0.7 * w, 0.58 * h),
          LineTo(0.3 * w, 0.58 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// SageMaker: ML notebook with model node.
  static VsdxShape awsSageMaker({
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
    final r = 0.08 * math.min(w, h);
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.18 * w, 0.25 * h),
          LineTo(0.55 * w, 0.25 * h),
          MoveTo(0.18 * w, 0.42 * h),
          LineTo(0.7 * w, 0.42 * h),
          MoveTo(0.18 * w, 0.59 * h),
          LineTo(0.45 * w, 0.59 * h),
        ]),
        for (final p in <List<double>>[
          [0.7, 0.7],
          [0.85, 0.55],
          [0.85, 0.85],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.05 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.05 * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.7 * w, 0.7 * h),
          LineTo(0.85 * w, 0.55 * h),
          MoveTo(0.7 * w, 0.7 * h),
          LineTo(0.85 * w, 0.85 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// CloudTrail: audit trail path with footprint marks.
  static VsdxShape awsCloudTrail({
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.15 * w, 0.75 * h),
          LineTo(0.35 * w, 0.55 * h),
          LineTo(0.55 * w, 0.65 * h),
          LineTo(0.75 * w, 0.35 * h),
          LineTo(0.9 * w, 0.25 * h),
        ]),
        for (final p in <List<double>>[
          [0.15, 0.75],
          [0.35, 0.55],
          [0.55, 0.65],
          [0.75, 0.35],
          [0.9, 0.25],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.05 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Secrets Manager: vault with keyhole (plural name vs GCP).
  static VsdxShape awsSecretsManager({
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
          MoveTo(0.2 * w, 0.35 * h),
          LineTo(0.8 * w, 0.35 * h),
          LineTo(0.8 * w, 0.9 * h),
          LineTo(0.2 * w, 0.9 * h),
          LineTo(0.2 * w, 0.35 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.32 * w, 0.35 * h),
          EllipticalArcTo(
              x: 0.68 * w, y: 0.35 * h, controlX: 0.5 * w, controlY: 0.08 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.55 * h,
              aX: 0.58 * w,
              aY: 0.55 * h,
              bX: 0.5 * w,
              bY: 0.63 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.46 * w, 0.6 * h),
          LineTo(0.54 * w, 0.6 * h),
          LineTo(0.54 * w, 0.78 * h),
          LineTo(0.46 * w, 0.78 * h),
          LineTo(0.46 * w, 0.6 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// CodePipeline: CI/CD stage chevrons.
  static VsdxShape awsCodePipeline({
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
    VsdxGeometry chevron(double x0, double x1) => VsdxGeometry(
          commands: <VsdxPathCommand>[
            MoveTo(x0, 0.28 * h),
            LineTo(x1 - 0.07 * w, 0.28 * h),
            LineTo(x1, 0.5 * h),
            LineTo(x1 - 0.07 * w, 0.72 * h),
            LineTo(x0, 0.72 * h),
            LineTo(x0 + 0.07 * w, 0.5 * h),
            LineTo(x0, 0.28 * h),
          ],
        );
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        chevron(0.05 * w, 0.38 * w),
        chevron(0.34 * w, 0.67 * w),
        chevron(0.63 * w, 0.96 * w),
      ],
      fill: fill,
      line: line,
    );
  }

  /// CodeBuild: build brick with hammer stroke.
  static VsdxShape awsCodeBuild({
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
    final r = 0.1 * math.min(w, h);
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
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.65 * h),
          LineTo(0.55 * w, 0.65 * h),
          LineTo(0.55 * w, 0.85 * h),
          LineTo(0.2 * w, 0.85 * h),
          LineTo(0.2 * w, 0.65 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.45 * w, 0.55 * h),
          LineTo(0.72 * w, 0.22 * h),
          MoveTo(0.65 * w, 0.28 * h),
          LineTo(0.8 * w, 0.35 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// WAF: web application firewall shield.
  static VsdxShape awsWaf({
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
          MoveTo(0.5 * w, 0.08 * h),
          LineTo(0.9 * w, 0.28 * h),
          LineTo(0.84 * w, 0.62 * h),
          EllipticalArcTo(
              x: 0.16 * w, y: 0.62 * h, controlX: 0.5 * w, controlY: 0.95 * h),
          LineTo(0.1 * w, 0.28 * h),
          LineTo(0.5 * w, 0.08 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.3 * w, 0.4 * h),
          LineTo(0.7 * w, 0.4 * h),
          MoveTo(0.35 * w, 0.55 * h),
          LineTo(0.65 * w, 0.55 * h),
          MoveTo(0.5 * w, 0.28 * h),
          LineTo(0.5 * w, 0.7 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Transit Gateway: hub with radiating attachments.
  static VsdxShape awsTransitGateway({
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
    final cx = 0.5 * w;
    final cy = 0.5 * h;
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
              cy: cy,
              aX: cx + 0.16 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.16 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final a in <double>[0, 0.2, 0.4, 0.6, 0.8]) ...[
            MoveTo(cx, cy),
            LineTo(
                cx + 0.38 * w * math.cos(a * 2 * math.pi),
                cy + 0.38 * h * math.sin(a * 2 * math.pi)),
          ],
        ]),
        for (final a in <double>[0, 0.2, 0.4, 0.6, 0.8])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: cx + 0.38 * w * math.cos(a * 2 * math.pi),
                cy: cy + 0.38 * h * math.sin(a * 2 * math.pi),
                aX: cx + 0.38 * w * math.cos(a * 2 * math.pi) + 0.05 * w,
                aY: cy + 0.38 * h * math.sin(a * 2 * math.pi),
                bX: cx + 0.38 * w * math.cos(a * 2 * math.pi),
                bY: cy + 0.38 * h * math.sin(a * 2 * math.pi) + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Direct Connect: dedicated link to cloud outline.
  static VsdxShape awsDirectConnect({
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
          MoveTo(0.08 * w, 0.55 * h),
          LineTo(0.42 * w, 0.55 * h),
          LineTo(0.42 * w, 0.85 * h),
          LineTo(0.08 * w, 0.85 * h),
          LineTo(0.08 * w, 0.55 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.55 * w, 0.48 * h),
          EllipticalArcTo(
              x: 0.7 * w, y: 0.32 * h, controlX: 0.52 * w, controlY: 0.3 * h),
          EllipticalArcTo(
              x: 0.88 * w, y: 0.42 * h, controlX: 0.82 * w, controlY: 0.18 * h),
          EllipticalArcTo(
              x: 0.82 * w, y: 0.62 * h, controlX: 0.95 * w, controlY: 0.62 * h),
          LineTo(0.62 * w, 0.62 * h),
          EllipticalArcTo(
              x: 0.55 * w, y: 0.48 * h, controlX: 0.5 * w, controlY: 0.62 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.42 * w, 0.7 * h),
          LineTo(0.58 * w, 0.55 * h),
          MoveTo(0.15 * w, 0.65 * h),
          LineTo(0.35 * w, 0.65 * h),
          MoveTo(0.15 * w, 0.75 * h),
          LineTo(0.35 * w, 0.75 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// OpenSearch: search cluster with magnifier.
  static VsdxShape awsOpenSearch({
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
        for (final p in <List<double>>[
          [0.28, 0.35],
          [0.55, 0.28],
          [0.4, 0.62],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.12 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.12 * h),
          ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.72 * w,
              cy: 0.68 * h,
              aX: 0.88 * w,
              aY: 0.68 * h,
              bX: 0.72 * w,
              bY: 0.84 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.84 * w, 0.8 * h),
          LineTo(0.95 * w, 0.95 * h),
          MoveTo(0.28 * w, 0.35 * h),
          LineTo(0.55 * w, 0.28 * h),
          LineTo(0.4 * w, 0.62 * h),
          LineTo(0.28 * w, 0.35 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  // ---------------------------------------------------------------------------
  // Azure architecture starters (draw.io azure / azure2) — geometric icons.
  // Not brand-mark replicas; clean compute / data / identity glyphs.
  // ---------------------------------------------------------------------------

  /// Virtual Machine: tower + monitor.
  static VsdxShape azureVirtualMachine({
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
          MoveTo(0.08 * w, 0.2 * h),
          LineTo(0.55 * w, 0.2 * h),
          LineTo(0.55 * w, 0.95 * h),
          LineTo(0.08 * w, 0.95 * h),
          LineTo(0.08 * w, 0.2 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.15 * w, 0.35 * h),
          LineTo(0.48 * w, 0.35 * h),
          MoveTo(0.15 * w, 0.5 * h),
          LineTo(0.48 * w, 0.5 * h),
          MoveTo(0.15 * w, 0.65 * h),
          LineTo(0.35 * w, 0.65 * h),
          EllipseCmd(
              cx: 0.42 * w,
              cy: 0.8 * h,
              aX: 0.48 * w,
              aY: 0.8 * h,
              bX: 0.42 * w,
              bY: 0.86 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.58 * w, 0.45 * h),
          LineTo(0.95 * w, 0.45 * h),
          LineTo(0.95 * w, 0.85 * h),
          LineTo(0.58 * w, 0.85 * h),
          LineTo(0.58 * w, 0.45 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.68 * w, 0.3 * h),
          LineTo(0.85 * w, 0.3 * h),
          LineTo(0.85 * w, 0.45 * h),
          LineTo(0.68 * w, 0.45 * h),
          LineTo(0.68 * w, 0.3 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// App Service: web app hexagon with globe.
  static VsdxShape azureAppService({
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
    final cx = 0.5 * w;
    final cy = 0.5 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.25 * w, h),
          LineTo(0.75 * w, h),
          LineTo(w, 0.5 * h),
          LineTo(0.75 * w, 0),
          LineTo(0.25 * w, 0),
          LineTo(0, 0.5 * h),
          LineTo(0.25 * w, h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: cy,
              aX: cx + 0.22 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.22 * h),
          EllipseCmd(
              cx: cx,
              cy: cy,
              aX: cx + 0.1 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.22 * h),
          MoveTo(cx - 0.22 * w, cy),
          LineTo(cx + 0.22 * w, cy),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Azure Functions: bolt inside a rounded tile.
  static VsdxShape azureFunctions({
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
    final r = 0.14 * math.min(w, h);
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
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.55 * w, 0.85 * h),
          LineTo(0.35 * w, 0.5 * h),
          LineTo(0.5 * w, 0.5 * h),
          LineTo(0.4 * w, 0.15 * h),
          LineTo(0.68 * w, 0.55 * h),
          LineTo(0.52 * w, 0.55 * h),
          LineTo(0.55 * w, 0.85 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Blob Storage: stacked soft cylinders.
  static VsdxShape azureBlobStorage({
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
    final cx = 0.5 * w;
    final ry = 0.08 * h;
    VsdxGeometry drum(double top, double bottom) => VsdxGeometry(
          commands: <VsdxPathCommand>[
            MoveTo(0.18 * w, top),
            EllipticalArcTo(
                x: 0.82 * w, y: top, controlX: cx, controlY: top + ry),
            LineTo(0.82 * w, bottom),
            EllipticalArcTo(
                x: 0.18 * w, y: bottom, controlX: cx, controlY: bottom - ry),
            LineTo(0.18 * w, top),
          ],
        );
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        drum(0.78 * h, 0.55 * h),
        drum(0.5 * h, 0.28 * h),
        drum(0.22 * h, 0.08 * h),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.18 * w, 0.78 * h),
          EllipticalArcTo(
              x: 0.82 * w, y: 0.78 * h, controlX: cx, controlY: 0.78 * h - ry),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// SQL Database: classic DB drum with SQL accent.
  static VsdxShape azureSqlDatabase({
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
    final cx = 0.5 * w;
    final top = 0.8 * h;
    final bottom = 0.2 * h;
    final ry = 0.1 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.15 * w, top),
          EllipticalArcTo(
              x: 0.85 * w, y: top, controlX: cx, controlY: top + ry),
          LineTo(0.85 * w, bottom),
          EllipticalArcTo(
              x: 0.15 * w, y: bottom, controlX: cx, controlY: bottom - ry),
          LineTo(0.15 * w, top),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.15 * w, top),
          EllipticalArcTo(
              x: 0.85 * w, y: top, controlX: cx, controlY: top - ry),
          MoveTo(0.15 * w, 0.55 * h),
          EllipticalArcTo(
              x: 0.85 * w,
              y: 0.55 * h,
              controlX: cx,
              controlY: 0.55 * h - ry),
          MoveTo(0.32 * w, 0.42 * h),
          LineTo(0.32 * w, 0.68 * h),
          MoveTo(0.32 * w, 0.55 * h),
          LineTo(0.48 * w, 0.55 * h),
          MoveTo(0.55 * w, 0.42 * h),
          LineTo(0.7 * w, 0.42 * h),
          LineTo(0.55 * w, 0.68 * h),
          LineTo(0.7 * w, 0.68 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Cosmos DB: multi-model atom / orbit.
  static VsdxShape azureCosmosDb({
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
    final cx = 0.5 * w;
    final cy = 0.5 * h;
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
              cy: cy,
              aX: cx + 0.12 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.12 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx, cy: cy, aX: 0.92 * w, aY: cy, bX: cx, bY: 0.35 * h),
          EllipseCmd(
              cx: cx,
              cy: cy,
              aX: cx + 0.2 * w,
              aY: cy,
              bX: cx,
              bY: 0.92 * h),
        ]),
        for (final p in <List<double>>[
          [0.18, 0.5],
          [0.82, 0.5],
          [0.5, 0.18],
          [0.5, 0.82],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.05 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// AKS: managed Kubernetes hex ring.
  static VsdxShape azureAks({
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
    final cx = 0.5 * w;
    final cy = 0.5 * h;
    final r = 0.38 * math.min(w, h);
    List<VsdxPathCommand> hex(double hx, double hy, double hr) =>
        <VsdxPathCommand>[
          MoveTo(hx + hr, hy),
          LineTo(hx + 0.5 * hr, hy + 0.866 * hr),
          LineTo(hx - 0.5 * hr, hy + 0.866 * hr),
          LineTo(hx - hr, hy),
          LineTo(hx - 0.5 * hr, hy - 0.866 * hr),
          LineTo(hx + 0.5 * hr, hy - 0.866 * hr),
          LineTo(hx + hr, hy),
        ];
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: hex(cx, cy, r)),
        VsdxGeometry(commands: hex(cx, cy, 0.45 * r)),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (var i = 0; i < 6; i++) ...[
            MoveTo(cx, cy),
            LineTo(
              cx + r * math.cos(i * math.pi / 3),
              cy + r * math.sin(i * math.pi / 3),
            ),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Virtual Network: cloud region with linked subnets.
  static VsdxShape azureVirtualNetwork({
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
    final r = 0.12 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
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
        for (final p in <List<double>>[
          [0.22, 0.35],
          [0.5, 0.65],
          [0.78, 0.35],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.1 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.1 * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.3 * w, 0.4 * h),
          LineTo(0.45 * w, 0.58 * h),
          MoveTo(0.7 * w, 0.4 * h),
          LineTo(0.55 * w, 0.58 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Application Gateway: WAF / routing shield portal.
  static VsdxShape azureApplicationGateway({
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
          MoveTo(0.5 * w, h),
          LineTo(0.9 * w, 0.7 * h),
          LineTo(0.9 * w, 0.35 * h),
          EllipticalArcTo(
              x: 0.1 * w, y: 0.35 * h, controlX: 0.5 * w, controlY: 0.08 * h),
          LineTo(0.1 * w, 0.7 * h),
          LineTo(0.5 * w, h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.55 * h),
          LineTo(0.45 * w, 0.55 * h),
          MoveTo(0.55 * w, 0.55 * h),
          LineTo(0.8 * w, 0.55 * h),
          MoveTo(0.45 * w, 0.4 * h),
          LineTo(0.45 * w, 0.7 * h),
          MoveTo(0.55 * w, 0.4 * h),
          LineTo(0.55 * w, 0.7 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.42 * w, 0.48 * h),
          LineTo(0.58 * w, 0.55 * h),
          LineTo(0.42 * w, 0.62 * h),
          LineTo(0.42 * w, 0.48 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Azure AD: identity directory (users + badge).
  static VsdxShape azureActiveDirectory({
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
          MoveTo(0.15 * w, 0.15 * h),
          LineTo(0.85 * w, 0.15 * h),
          LineTo(0.85 * w, 0.9 * h),
          LineTo(0.15 * w, 0.9 * h),
          LineTo(0.15 * w, 0.15 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.38 * w,
              cy: 0.45 * h,
              aX: 0.48 * w,
              aY: 0.45 * h,
              bX: 0.38 * w,
              bY: 0.55 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.25 * w, 0.28 * h),
          LineTo(0.52 * w, 0.28 * h),
          LineTo(0.55 * w, 0.4 * h),
          LineTo(0.22 * w, 0.4 * h),
          LineTo(0.25 * w, 0.28 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.62 * w, 0.35 * h),
          LineTo(0.78 * w, 0.35 * h),
          MoveTo(0.62 * w, 0.5 * h),
          LineTo(0.78 * w, 0.5 * h),
          MoveTo(0.62 * w, 0.65 * h),
          LineTo(0.72 * w, 0.65 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Key Vault: locked vault box.
  static VsdxShape azureKeyVault({
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
          MoveTo(0.18 * w, 0.15 * h),
          LineTo(0.82 * w, 0.15 * h),
          LineTo(0.82 * w, 0.9 * h),
          LineTo(0.18 * w, 0.9 * h),
          LineTo(0.18 * w, 0.15 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.48 * h,
              aX: 0.62 * w,
              aY: 0.48 * h,
              bX: 0.5 * w,
              bY: 0.6 * h),
          MoveTo(0.5 * w, 0.6 * h),
          LineTo(0.5 * w, 0.75 * h),
          MoveTo(0.42 * w, 0.75 * h),
          LineTo(0.58 * w, 0.75 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.35 * w, 0.35 * h),
          LineTo(0.65 * w, 0.35 * h),
          LineTo(0.65 * w, 0.22 * h),
          EllipticalArcTo(
              x: 0.35 * w,
              y: 0.22 * h,
              controlX: 0.5 * w,
              controlY: 0.08 * h),
          LineTo(0.35 * w, 0.35 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Service Bus: messaging bus with topic branches.
  static VsdxShape azureServiceBus({
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
          MoveTo(0.1 * w, 0.42 * h),
          LineTo(0.7 * w, 0.42 * h),
          LineTo(0.7 * w, 0.58 * h),
          LineTo(0.1 * w, 0.58 * h),
          LineTo(0.1 * w, 0.42 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.7 * w, 0.5 * h),
          LineTo(0.82 * w, 0.22 * h),
          MoveTo(0.7 * w, 0.5 * h),
          LineTo(0.9 * w, 0.5 * h),
          MoveTo(0.7 * w, 0.5 * h),
          LineTo(0.82 * w, 0.78 * h),
        ]),
        for (final p in <List<double>>[
          [0.82, 0.22],
          [0.9, 0.5],
          [0.82, 0.78],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.06 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.06 * h),
          ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.18 * w, 0.35 * h),
          LineTo(0.3 * w, 0.35 * h),
          LineTo(0.3 * w, 0.22 * h),
          LineTo(0.18 * w, 0.22 * h),
          LineTo(0.18 * w, 0.35 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Event Hubs: high-throughput event ingest funnel.
  static VsdxShape azureEventHubs({
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
          MoveTo(0.15 * w, 0.85 * h),
          LineTo(0.85 * w, 0.85 * h),
          LineTo(0.7 * w, 0.45 * h),
          LineTo(0.3 * w, 0.45 * h),
          LineTo(0.15 * w, 0.85 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.35 * w, 0.45 * h),
          LineTo(0.65 * w, 0.45 * h),
          LineTo(0.65 * w, 0.2 * h),
          LineTo(0.35 * w, 0.2 * h),
          LineTo(0.35 * w, 0.45 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.12 * h),
          LineTo(0.35 * w, 0.28 * h),
          MoveTo(0.5 * w, 0.08 * h),
          LineTo(0.5 * w, 0.2 * h),
          MoveTo(0.8 * w, 0.12 * h),
          LineTo(0.65 * w, 0.28 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Azure Monitor: metrics waveform in a tile.
  static VsdxShape azureMonitor({
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
    final r = 0.12 * math.min(w, h);
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.15 * w, 0.55 * h),
          LineTo(0.3 * w, 0.55 * h),
          LineTo(0.4 * w, 0.3 * h),
          LineTo(0.55 * w, 0.7 * h),
          LineTo(0.68 * w, 0.45 * h),
          LineTo(0.85 * w, 0.45 * h),
          MoveTo(0.15 * w, 0.78 * h),
          LineTo(0.85 * w, 0.78 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Azure Container Instances: stacked container slots.
  static VsdxShape azureContainerInstances({
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
        for (final entry in <List<double>>[
          [0.15, 0.12, 0.85, 0.38],
          [0.2, 0.4, 0.8, 0.66],
          [0.25, 0.68, 0.75, 0.9],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(entry[0] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[1] * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.25, 0.53, 0.79]) ...[
            MoveTo(0.32 * w, y * h),
            LineTo(0.68 * w, y * h),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Azure Container Registry: registry vault with tag badge.
  static VsdxShape azureContainerRegistry({
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
    final r = 0.1 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(r, 0.85 * h),
          LineTo(w - r, 0.85 * h),
          EllipticalArcTo(
              x: w, y: 0.85 * h - r, controlX: w, controlY: 0.85 * h),
          LineTo(w, 0.2 * h + r),
          EllipticalArcTo(x: w - r, y: 0.2 * h, controlX: w, controlY: 0.2 * h),
          LineTo(r, 0.2 * h),
          EllipticalArcTo(
              x: 0, y: 0.2 * h + r, controlX: 0, controlY: 0.2 * h),
          LineTo(0, 0.85 * h - r),
          EllipticalArcTo(x: r, y: 0.85 * h, controlX: 0, controlY: 0.85 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.55 * w, 0.35 * h),
          LineTo(0.85 * w, 0.35 * h),
          LineTo(0.85 * w, 0.55 * h),
          LineTo(0.55 * w, 0.55 * h),
          LineTo(0.55 * w, 0.35 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.4 * h),
          LineTo(0.45 * w, 0.4 * h),
          MoveTo(0.2 * w, 0.55 * h),
          LineTo(0.45 * w, 0.55 * h),
          MoveTo(0.2 * w, 0.7 * h),
          LineTo(0.7 * w, 0.7 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Azure Redis Cache: stacked cache tiers with keyhole.
  static VsdxShape azureRedisCache({
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
        for (final entry in <List<double>>[
          [0.15, 0.68, 0.85, 0.9],
          [0.22, 0.4, 0.78, 0.62],
          [0.3, 0.12, 0.7, 0.34],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(entry[0] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[1] * h),
          ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.79 * h,
              aX: 0.56 * w,
              aY: 0.79 * h,
              bX: 0.5 * w,
              bY: 0.85 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Azure Front Door: edge gateway with fan-out.
  static VsdxShape azureFrontDoor({
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
    final cx = 0.5 * w;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.35 * h),
          LineTo(0.8 * w, 0.35 * h),
          LineTo(0.8 * w, 0.58 * h),
          LineTo(0.2 * w, 0.58 * h),
          LineTo(0.2 * w, 0.35 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(cx, 0.1 * h),
          LineTo(cx, 0.35 * h),
          MoveTo(cx, 0.58 * h),
          LineTo(0.18 * w, 0.88 * h),
          MoveTo(cx, 0.58 * h),
          LineTo(cx, 0.9 * h),
          MoveTo(cx, 0.58 * h),
          LineTo(0.82 * w, 0.88 * h),
        ]),
        for (final p in <List<double>>[
          [0.5, 0.1],
          [0.18, 0.88],
          [0.5, 0.9],
          [0.82, 0.88],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.05 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Azure API Management: gateway portal with key badge.
  static VsdxShape azureApiManagement({
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
    final r = 0.1 * math.min(w, h);
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.3 * h),
          LineTo(0.55 * w, 0.3 * h),
          MoveTo(0.2 * w, 0.5 * h),
          LineTo(0.7 * w, 0.5 * h),
          MoveTo(0.2 * w, 0.7 * h),
          LineTo(0.45 * w, 0.7 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.75 * w,
              cy: 0.7 * h,
              aX: 0.82 * w,
              aY: 0.7 * h,
              bX: 0.75 * w,
              bY: 0.78 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Azure Logic Apps: workflow chain of linked nodes.
  static VsdxShape azureLogicApps({
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
        for (final p in <List<double>>[
          [0.2, 0.25],
          [0.5, 0.5],
          [0.8, 0.75],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.1 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.1 * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.28 * w, 0.3 * h),
          LineTo(0.42 * w, 0.45 * h),
          MoveTo(0.58 * w, 0.55 * h),
          LineTo(0.72 * w, 0.7 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.18 * w, 0.55 * h),
          LineTo(0.32 * w, 0.55 * h),
          LineTo(0.32 * w, 0.85 * h),
          LineTo(0.18 * w, 0.85 * h),
          LineTo(0.18 * w, 0.55 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Azure Data Factory: pipeline funnel with stages.
  static VsdxShape azureDataFactory({
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
          MoveTo(0.1 * w, 0.15 * h),
          LineTo(0.9 * w, 0.15 * h),
          LineTo(0.7 * w, 0.45 * h),
          LineTo(0.7 * w, 0.85 * h),
          LineTo(0.3 * w, 0.85 * h),
          LineTo(0.3 * w, 0.45 * h),
          LineTo(0.1 * w, 0.15 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.22 * w, 0.3 * h),
          LineTo(0.78 * w, 0.3 * h),
          MoveTo(0.38 * w, 0.55 * h),
          LineTo(0.62 * w, 0.55 * h),
          MoveTo(0.38 * w, 0.7 * h),
          LineTo(0.62 * w, 0.7 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Azure Synapse Analytics: analytics warehouse grid.
  static VsdxShape azureSynapseAnalytics({
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
          MoveTo(0.1 * w, 0.12 * h),
          LineTo(0.9 * w, 0.12 * h),
          LineTo(0.9 * w, 0.9 * h),
          LineTo(0.1 * w, 0.9 * h),
          LineTo(0.1 * w, 0.12 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final x in <double>[0.3, 0.5, 0.7]) ...[
            MoveTo(x * w, 0.2 * h),
            LineTo(x * w, 0.82 * h),
          ],
          MoveTo(0.18 * w, 0.35 * h),
          LineTo(0.82 * w, 0.35 * h),
          MoveTo(0.18 * w, 0.55 * h),
          LineTo(0.82 * w, 0.55 * h),
          MoveTo(0.18 * w, 0.75 * h),
          LineTo(0.82 * w, 0.75 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.55 * w, 0.2 * h),
          LineTo(0.65 * w, 0.2 * h),
          LineTo(0.65 * w, 0.82 * h),
          LineTo(0.55 * w, 0.82 * h),
          LineTo(0.55 * w, 0.2 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Azure IoT Hub: hub with radiating device nodes.
  static VsdxShape azureIotHub({
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
    final cx = 0.5 * w;
    final cy = 0.5 * h;
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
              cy: cy,
              aX: cx + 0.16 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.16 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(cx, cy),
          LineTo(0.18 * w, 0.2 * h),
          MoveTo(cx, cy),
          LineTo(0.82 * w, 0.2 * h),
          MoveTo(cx, cy),
          LineTo(0.18 * w, 0.8 * h),
          MoveTo(cx, cy),
          LineTo(0.82 * w, 0.8 * h),
        ]),
        for (final p in <List<double>>[
          [0.18, 0.2],
          [0.82, 0.2],
          [0.18, 0.8],
          [0.82, 0.8],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.06 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.06 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Azure Event Grid: event topic with subscriber rays.
  static VsdxShape azureEventGrid({
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
          MoveTo(0.15 * w, 0.35 * h),
          LineTo(0.85 * w, 0.35 * h),
          LineTo(0.85 * w, 0.55 * h),
          LineTo(0.15 * w, 0.55 * h),
          LineTo(0.15 * w, 0.35 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.5 * w, 0.55 * h),
          LineTo(0.22 * w, 0.85 * h),
          MoveTo(0.5 * w, 0.55 * h),
          LineTo(0.5 * w, 0.88 * h),
          MoveTo(0.5 * w, 0.55 * h),
          LineTo(0.78 * w, 0.85 * h),
          MoveTo(0.5 * w, 0.35 * h),
          LineTo(0.5 * w, 0.12 * h),
        ]),
        for (final p in <List<double>>[
          [0.22, 0.85],
          [0.5, 0.88],
          [0.78, 0.85],
          [0.5, 0.12],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.05 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Azure Firewall: brick wall security appliance.
  static VsdxShape azureFirewall({
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
    final bricks = <VsdxPathCommand>[];
    const rows = 4;
    for (var row = 0; row < rows; row++) {
      final y0 = (0.2 + row * 0.16) * h;
      final y1 = y0 + 0.14 * h;
      final offset = row.isOdd ? 0.08 * w : 0.0;
      final cols = row.isOdd ? 3 : 4;
      final bw = (0.84 * w - (cols - 1) * 0.02 * w) / cols;
      for (var c = 0; c < cols; c++) {
        final x0 = 0.08 * w + offset + c * (bw + 0.02 * w);
        bricks
          ..add(MoveTo(x0, y0))
          ..add(LineTo(x0 + bw, y0))
          ..add(LineTo(x0 + bw, y1))
          ..add(LineTo(x0, y1))
          ..add(LineTo(x0, y0));
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
          MoveTo(0.06 * w, 0.12 * h),
          LineTo(0.94 * w, 0.12 * h),
          LineTo(0.94 * w, 0.9 * h),
          LineTo(0.06 * w, 0.9 * h),
          LineTo(0.06 * w, 0.12 * h),
        ]),
        VsdxGeometry(noFill: true, commands: bricks),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Azure Bastion: jump-host bastion with lock.
  static VsdxShape azureBastion({
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
          MoveTo(0.2 * w, 0.35 * h),
          LineTo(0.8 * w, 0.35 * h),
          LineTo(0.8 * w, 0.88 * h),
          LineTo(0.2 * w, 0.88 * h),
          LineTo(0.2 * w, 0.35 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.32 * w, 0.35 * h),
          EllipticalArcTo(
              x: 0.68 * w, y: 0.35 * h, controlX: 0.5 * w, controlY: 0.08 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.55 * h,
              aX: 0.58 * w,
              aY: 0.55 * h,
              bX: 0.5 * w,
              bY: 0.63 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.46 * w, 0.6 * h),
          LineTo(0.54 * w, 0.6 * h),
          LineTo(0.54 * w, 0.78 * h),
          LineTo(0.46 * w, 0.78 * h),
          LineTo(0.46 * w, 0.6 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Azure DNS: name-service globe with NS rays.
  static VsdxShape azureDns({
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
    final cx = 0.5 * w;
    final cy = 0.5 * h;
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
              cy: cy,
              aX: cx + 0.35 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.35 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: cy,
              aX: cx + 0.15 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.35 * h),
          MoveTo(0.15 * w, cy),
          LineTo(0.85 * w, cy),
          MoveTo(cx, 0.15 * h),
          LineTo(cx, 0.85 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Azure DevOps: sprint board with pipeline chevron.
  static VsdxShape azureDevOps({
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
    final r = 0.08 * math.min(w, h);
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.18 * w, 0.25 * h),
          LineTo(0.55 * w, 0.25 * h),
          MoveTo(0.18 * w, 0.42 * h),
          LineTo(0.7 * w, 0.42 * h),
          MoveTo(0.18 * w, 0.59 * h),
          LineTo(0.45 * w, 0.59 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.55 * w, 0.68 * h),
          LineTo(0.75 * w, 0.68 * h),
          LineTo(0.85 * w, 0.8 * h),
          LineTo(0.75 * w, 0.92 * h),
          LineTo(0.55 * w, 0.92 * h),
          LineTo(0.65 * w, 0.8 * h),
          LineTo(0.55 * w, 0.68 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Compute Engine: isometric compute cube with status LED.
  static VsdxShape gcpComputeEngine({
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
    final d = 0.2 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.05 * w, 0.1 * h),
          LineTo(0.7 * w, 0.1 * h),
          LineTo(0.7 * w, 0.75 * h),
          LineTo(0.05 * w, 0.75 * h),
          LineTo(0.05 * w, 0.1 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.7 * w, 0.1 * h),
          LineTo(0.7 * w + d, 0.1 * h + d),
          LineTo(0.7 * w + d, 0.75 * h + d),
          LineTo(0.7 * w, 0.75 * h),
          LineTo(0.7 * w, 0.1 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.05 * w, 0.75 * h),
          LineTo(0.7 * w, 0.75 * h),
          LineTo(0.7 * w + d, 0.75 * h + d),
          LineTo(0.05 * w + d, 0.75 * h + d),
          LineTo(0.05 * w, 0.75 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.55 * w,
              cy: 0.42 * h,
              aX: 0.62 * w,
              aY: 0.42 * h,
              bX: 0.55 * w,
              bY: 0.5 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP App Engine: layered platform stack.
  static VsdxShape gcpAppEngine({
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
        for (final entry in <List<double>>[
          [0.12, 0.12, 0.88, 0.34],
          [0.18, 0.38, 0.82, 0.6],
          [0.24, 0.64, 0.76, 0.88],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(entry[0] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[1] * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.28 * w, 0.23 * h),
          LineTo(0.72 * w, 0.23 * h),
          MoveTo(0.32 * w, 0.49 * h),
          LineTo(0.68 * w, 0.49 * h),
          MoveTo(0.36 * w, 0.76 * h),
          LineTo(0.64 * w, 0.76 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Cloud Functions: function badge with lambda stroke.
  static VsdxShape gcpCloudFunctions({
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
    final r = 0.18 * math.min(w, h);
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.3 * w, 0.78 * h),
          LineTo(0.45 * w, 0.78 * h),
          LineTo(0.58 * w, 0.22 * h),
          LineTo(0.74 * w, 0.22 * h),
          MoveTo(0.38 * w, 0.5 * h),
          LineTo(0.66 * w, 0.5 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Cloud Storage: bucket with handle arc.
  static VsdxShape gcpCloudStorage({
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
          MoveTo(0.15 * w, 0.82 * h),
          LineTo(0.85 * w, 0.82 * h),
          LineTo(0.78 * w, 0.28 * h),
          LineTo(0.22 * w, 0.28 * h),
          LineTo(0.15 * w, 0.82 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.28 * h),
          LineTo(0.8 * w, 0.28 * h),
          LineTo(0.8 * w, 0.4 * h),
          LineTo(0.2 * w, 0.4 * h),
          LineTo(0.2 * w, 0.28 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.32 * w, 0.28 * h),
          EllipticalArcTo(
              x: 0.68 * w,
              y: 0.28 * h,
              controlX: 0.5 * w,
              controlY: 0.08 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Cloud SQL: cylinder database.
  static VsdxShape gcpCloudSql({
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
    final left = 0.18 * w;
    final right = 0.82 * w;
    final cx = 0.5 * w;
    final rx = 0.5 * (right - left);
    final ry = 0.08 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(left, 0.78 * h),
          LineTo(left, 0.28 * h),
          EllipticalArcTo(
              x: right, y: 0.28 * h, controlX: cx, controlY: 0.28 * h + ry),
          LineTo(right, 0.78 * h),
          EllipticalArcTo(
              x: left, y: 0.78 * h, controlX: cx, controlY: 0.78 * h - ry),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: 0.28 * h,
              aX: cx + rx,
              aY: 0.28 * h,
              bX: cx,
              bY: 0.28 * h + ry),
          MoveTo(left, 0.5 * h),
          EllipticalArcTo(
              x: right, y: 0.5 * h, controlX: cx, controlY: 0.5 * h + ry),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP BigQuery: columnar analytics grid.
  static VsdxShape gcpBigQuery({
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
          MoveTo(0.1 * w, 0.12 * h),
          LineTo(0.9 * w, 0.12 * h),
          LineTo(0.9 * w, 0.9 * h),
          LineTo(0.1 * w, 0.9 * h),
          LineTo(0.1 * w, 0.12 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final x in <double>[0.3, 0.5, 0.7]) ...[
            MoveTo(x * w, 0.2 * h),
            LineTo(x * w, 0.82 * h),
          ],
          MoveTo(0.18 * w, 0.35 * h),
          LineTo(0.82 * w, 0.35 * h),
          MoveTo(0.18 * w, 0.55 * h),
          LineTo(0.82 * w, 0.55 * h),
          MoveTo(0.18 * w, 0.75 * h),
          LineTo(0.82 * w, 0.75 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.34 * w, 0.58 * h),
          LineTo(0.46 * w, 0.58 * h),
          LineTo(0.46 * w, 0.82 * h),
          LineTo(0.34 * w, 0.82 * h),
          LineTo(0.34 * w, 0.58 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP GKE: hex cluster of pods.
  static VsdxShape gcpGke({
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
    List<VsdxPathCommand> hex(double cx, double cy, double r) {
      final pts = <List<double>>[
        for (var i = 0; i < 6; i++)
          [
            cx + r * math.cos(math.pi / 6 + i * math.pi / 3),
            cy + r * math.sin(math.pi / 6 + i * math.pi / 3),
          ],
      ];
      return <VsdxPathCommand>[
        MoveTo(pts[0][0], pts[0][1]),
        for (var i = 1; i < 6; i++) LineTo(pts[i][0], pts[i][1]),
        LineTo(pts[0][0], pts[0][1]),
      ];
    }

    final r = 0.18 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: hex(0.5 * w, 0.55 * h, 0.38 * math.min(w, h))),
        VsdxGeometry(commands: hex(0.5 * w, 0.55 * h, r)),
        VsdxGeometry(commands: hex(0.32 * w, 0.35 * h, r * 0.7)),
        VsdxGeometry(commands: hex(0.68 * w, 0.35 * h, r * 0.7)),
        VsdxGeometry(commands: hex(0.5 * w, 0.78 * h, r * 0.7)),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP VPC Network: cloud outline with subnet nodes.
  static VsdxShape gcpVpcNetwork({
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
          MoveTo(0.2 * w, 0.62 * h),
          EllipticalArcTo(
              x: 0.38 * w, y: 0.42 * h, controlX: 0.18 * w, controlY: 0.4 * h),
          EllipticalArcTo(
              x: 0.62 * w, y: 0.35 * h, controlX: 0.5 * w, controlY: 0.18 * h),
          EllipticalArcTo(
              x: 0.82 * w, y: 0.55 * h, controlX: 0.88 * w, controlY: 0.3 * h),
          EllipticalArcTo(
              x: 0.72 * w, y: 0.78 * h, controlX: 0.9 * w, controlY: 0.78 * h),
          LineTo(0.28 * w, 0.78 * h),
          EllipticalArcTo(
              x: 0.2 * w, y: 0.62 * h, controlX: 0.12 * w, controlY: 0.78 * h),
        ]),
        for (final p in <List<double>>[
          [0.35, 0.55],
          [0.5, 0.48],
          [0.65, 0.58],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.04 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.04 * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.35 * w, 0.55 * h),
          LineTo(0.5 * w, 0.48 * h),
          LineTo(0.65 * w, 0.58 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Cloud Load Balancing: fan-in / fan-out balancer.
  static VsdxShape gcpCloudLoadBalancing({
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
    final cx = 0.5 * w;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.3 * w, 0.42 * h),
          LineTo(0.7 * w, 0.42 * h),
          LineTo(0.7 * w, 0.62 * h),
          LineTo(0.3 * w, 0.62 * h),
          LineTo(0.3 * w, 0.42 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(cx, 0.12 * h),
          LineTo(cx, 0.42 * h),
          MoveTo(cx, 0.62 * h),
          LineTo(0.2 * w, 0.88 * h),
          MoveTo(cx, 0.62 * h),
          LineTo(cx, 0.88 * h),
          MoveTo(cx, 0.62 * h),
          LineTo(0.8 * w, 0.88 * h),
        ]),
        for (final p in <List<double>>[
          [0.5, 0.12],
          [0.2, 0.88],
          [0.5, 0.88],
          [0.8, 0.88],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.05 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Cloud IAM: identity shield with keyhole.
  static VsdxShape gcpCloudIam({
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
          MoveTo(0.5 * w, 0.08 * h),
          LineTo(0.88 * w, 0.28 * h),
          LineTo(0.82 * w, 0.62 * h),
          EllipticalArcTo(
              x: 0.18 * w, y: 0.62 * h, controlX: 0.5 * w, controlY: 0.95 * h),
          LineTo(0.12 * w, 0.28 * h),
          LineTo(0.5 * w, 0.08 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.42 * h,
              aX: 0.58 * w,
              aY: 0.42 * h,
              bX: 0.5 * w,
              bY: 0.5 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.46 * w, 0.48 * h),
          LineTo(0.54 * w, 0.48 * h),
          LineTo(0.54 * w, 0.68 * h),
          LineTo(0.46 * w, 0.68 * h),
          LineTo(0.46 * w, 0.48 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Pub/Sub: topic hub with subscriber rays.
  static VsdxShape gcpPubSub({
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
    final cx = 0.5 * w;
    final cy = 0.42 * h;
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
              cy: cy,
              aX: cx + 0.14 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.14 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(cx, cy + 0.14 * h),
          LineTo(0.18 * w, 0.85 * h),
          MoveTo(cx, cy + 0.14 * h),
          LineTo(cx, 0.88 * h),
          MoveTo(cx, cy + 0.14 * h),
          LineTo(0.82 * w, 0.85 * h),
          MoveTo(cx, cy - 0.14 * h),
          LineTo(cx, 0.1 * h),
        ]),
        for (final p in <List<double>>[
          [0.18, 0.85],
          [0.5, 0.88],
          [0.82, 0.85],
          [0.5, 0.1],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.05 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Cloud Spanner: distributed DB nodes.
  static VsdxShape gcpCloudSpanner({
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
        for (final p in <List<double>>[
          [0.22, 0.28],
          [0.78, 0.28],
          [0.22, 0.72],
          [0.78, 0.72],
          [0.5, 0.5],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.08 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.08 * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.22 * w, 0.28 * h),
          LineTo(0.5 * w, 0.5 * h),
          LineTo(0.78 * w, 0.28 * h),
          MoveTo(0.22 * w, 0.72 * h),
          LineTo(0.5 * w, 0.5 * h),
          LineTo(0.78 * w, 0.72 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Cloud Run: container with play chevron.
  static VsdxShape gcpCloudRun({
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
    final r = 0.12 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(r, 0.85 * h),
          LineTo(w - r, 0.85 * h),
          EllipticalArcTo(
              x: w, y: 0.85 * h - r, controlX: w, controlY: 0.85 * h),
          LineTo(w, 0.2 * h + r),
          EllipticalArcTo(x: w - r, y: 0.2 * h, controlX: w, controlY: 0.2 * h),
          LineTo(r, 0.2 * h),
          EllipticalArcTo(
              x: 0, y: 0.2 * h + r, controlX: 0, controlY: 0.2 * h),
          LineTo(0, 0.85 * h - r),
          EllipticalArcTo(x: r, y: 0.85 * h, controlX: 0, controlY: 0.85 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.12 * w, 0.35 * h),
          LineTo(0.88 * w, 0.35 * h),
          MoveTo(0.12 * w, 0.55 * h),
          LineTo(0.88 * w, 0.55 * h),
          MoveTo(0.12 * w, 0.7 * h),
          LineTo(0.55 * w, 0.7 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.62 * w, 0.62 * h),
          LineTo(0.82 * w, 0.72 * h),
          LineTo(0.62 * w, 0.82 * h),
          LineTo(0.62 * w, 0.62 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Cloud Monitoring: dashboard tile with sparkline.
  static VsdxShape gcpCloudMonitoring({
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
    final r = 0.1 * math.min(w, h);
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.15 * w, 0.65 * h),
          LineTo(0.32 * w, 0.45 * h),
          LineTo(0.45 * w, 0.55 * h),
          LineTo(0.6 * w, 0.28 * h),
          LineTo(0.75 * w, 0.4 * h),
          LineTo(0.88 * w, 0.22 * h),
          MoveTo(0.15 * w, 0.8 * h),
          LineTo(0.88 * w, 0.8 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Bigtable: wide-column store grid.
  static VsdxShape gcpBigtable({
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
          MoveTo(0.1 * w, 0.15 * h),
          LineTo(0.9 * w, 0.15 * h),
          LineTo(0.9 * w, 0.9 * h),
          LineTo(0.1 * w, 0.9 * h),
          LineTo(0.1 * w, 0.15 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final x in <double>[0.28, 0.46, 0.64, 0.82]) ...[
            MoveTo(x * w, 0.22 * h),
            LineTo(x * w, 0.82 * h),
          ],
          for (final y in <double>[0.35, 0.55, 0.75]) ...[
            MoveTo(0.16 * w, y * h),
            LineTo(0.84 * w, y * h),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Dataflow: streaming pipeline chevrons.
  static VsdxShape gcpDataflow({
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
    VsdxGeometry chevron(double x0, double x1) => VsdxGeometry(
          commands: <VsdxPathCommand>[
            MoveTo(x0, 0.25 * h),
            LineTo(x1 - 0.08 * w, 0.25 * h),
            LineTo(x1, 0.5 * h),
            LineTo(x1 - 0.08 * w, 0.75 * h),
            LineTo(x0, 0.75 * h),
            LineTo(x0 + 0.08 * w, 0.5 * h),
            LineTo(x0, 0.25 * h),
          ],
        );
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        chevron(0.05 * w, 0.4 * w),
        chevron(0.35 * w, 0.7 * w),
        chevron(0.65 * w, 1.0 * w),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Dataproc: spark/cluster hex pods.
  static VsdxShape gcpDataproc({
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
    List<VsdxPathCommand> hex(double cx, double cy, double r) =>
        <VsdxPathCommand>[
          MoveTo(cx + r, cy),
          LineTo(cx + 0.5 * r, cy + 0.866 * r),
          LineTo(cx - 0.5 * r, cy + 0.866 * r),
          LineTo(cx - r, cy),
          LineTo(cx - 0.5 * r, cy - 0.866 * r),
          LineTo(cx + 0.5 * r, cy - 0.866 * r),
          LineTo(cx + r, cy),
        ];
    final r = 0.18 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: hex(0.3 * w, 0.55 * h, r)),
        VsdxGeometry(commands: hex(0.7 * w, 0.55 * h, r)),
        VsdxGeometry(commands: hex(0.5 * w, 0.28 * h, r)),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.3 * w, 0.55 * h),
          LineTo(0.5 * w, 0.28 * h),
          LineTo(0.7 * w, 0.55 * h),
          LineTo(0.3 * w, 0.55 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Cloud Composer: DAG of workflow nodes.
  static VsdxShape gcpCloudComposer({
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
        for (final p in <List<double>>[
          [0.2, 0.25],
          [0.5, 0.25],
          [0.8, 0.25],
          [0.35, 0.55],
          [0.65, 0.55],
          [0.5, 0.82],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.08 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.08 * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.25 * h),
          LineTo(0.35 * w, 0.55 * h),
          MoveTo(0.5 * w, 0.25 * h),
          LineTo(0.35 * w, 0.55 * h),
          MoveTo(0.5 * w, 0.25 * h),
          LineTo(0.65 * w, 0.55 * h),
          MoveTo(0.8 * w, 0.25 * h),
          LineTo(0.65 * w, 0.55 * h),
          MoveTo(0.35 * w, 0.55 * h),
          LineTo(0.5 * w, 0.82 * h),
          MoveTo(0.65 * w, 0.55 * h),
          LineTo(0.5 * w, 0.82 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Cloud Armor: shield with armor plate.
  static VsdxShape gcpCloudArmor({
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
          MoveTo(0.5 * w, 0.08 * h),
          LineTo(0.9 * w, 0.28 * h),
          LineTo(0.84 * w, 0.62 * h),
          EllipticalArcTo(
              x: 0.16 * w, y: 0.62 * h, controlX: 0.5 * w, controlY: 0.95 * h),
          LineTo(0.1 * w, 0.28 * h),
          LineTo(0.5 * w, 0.08 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.28 * w, 0.4 * h),
          LineTo(0.72 * w, 0.4 * h),
          MoveTo(0.32 * w, 0.55 * h),
          LineTo(0.68 * w, 0.55 * h),
          MoveTo(0.5 * w, 0.28 * h),
          LineTo(0.5 * w, 0.72 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Cloud CDN: edge cache with globe arcs.
  static VsdxShape gcpCloudCdn({
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
    final cx = 0.5 * w;
    final cy = 0.48 * h;
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
              cy: cy,
              aX: cx + 0.32 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.28 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: cy,
              aX: cx + 0.12 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.28 * h),
          MoveTo(0.18 * w, cy),
          LineTo(0.82 * w, cy),
        ]),
        for (final x in <double>[0.2, 0.5, 0.8])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(x * w - 0.06 * w, 0.82 * h),
            LineTo(x * w + 0.06 * w, 0.82 * h),
            LineTo(x * w + 0.06 * w, 0.95 * h),
            LineTo(x * w - 0.06 * w, 0.95 * h),
            LineTo(x * w - 0.06 * w, 0.82 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Memorystore: in-memory cache stack.
  static VsdxShape gcpMemorystore({
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
        for (final entry in <List<double>>[
          [0.15, 0.7, 0.85, 0.92],
          [0.22, 0.42, 0.78, 0.64],
          [0.3, 0.14, 0.7, 0.36],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(entry[0] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[1] * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.35 * w, 0.81 * h),
          LineTo(0.65 * w, 0.81 * h),
          MoveTo(0.4 * w, 0.53 * h),
          LineTo(0.6 * w, 0.53 * h),
          MoveTo(0.42 * w, 0.25 * h),
          LineTo(0.58 * w, 0.25 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Cloud Build: build brick with hammer stroke.
  static VsdxShape gcpCloudBuild({
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
    final r = 0.1 * math.min(w, h);
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
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.65 * h),
          LineTo(0.55 * w, 0.65 * h),
          LineTo(0.55 * w, 0.85 * h),
          LineTo(0.2 * w, 0.85 * h),
          LineTo(0.2 * w, 0.65 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.45 * w, 0.55 * h),
          LineTo(0.72 * w, 0.22 * h),
          MoveTo(0.65 * w, 0.28 * h),
          LineTo(0.8 * w, 0.35 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Artifact Registry: package vault with tag.
  static VsdxShape gcpArtifactRegistry({
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
          MoveTo(0.15 * w, 0.25 * h),
          LineTo(0.85 * w, 0.25 * h),
          LineTo(0.85 * w, 0.85 * h),
          LineTo(0.15 * w, 0.85 * h),
          LineTo(0.15 * w, 0.25 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.55 * w, 0.35 * h),
          LineTo(0.78 * w, 0.35 * h),
          LineTo(0.78 * w, 0.55 * h),
          LineTo(0.55 * w, 0.55 * h),
          LineTo(0.55 * w, 0.35 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.25 * w, 0.4 * h),
          LineTo(0.48 * w, 0.4 * h),
          MoveTo(0.25 * w, 0.55 * h),
          LineTo(0.48 * w, 0.55 * h),
          MoveTo(0.25 * w, 0.7 * h),
          LineTo(0.7 * w, 0.7 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Cloud Scheduler: clock face with cron ticks.
  static VsdxShape gcpCloudScheduler({
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
    final cx = 0.5 * w;
    final cy = 0.5 * h;
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
              cy: cy,
              aX: cx + 0.38 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.38 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(cx, cy),
          LineTo(cx, 0.22 * h),
          MoveTo(cx, cy),
          LineTo(0.72 * w, 0.58 * h),
          for (final a in <double>[0, 0.25, 0.5, 0.75]) ...[
            MoveTo(
                cx + 0.3 * w * math.cos(a * 2 * math.pi),
                cy + 0.3 * h * math.sin(a * 2 * math.pi)),
            LineTo(
                cx + 0.38 * w * math.cos(a * 2 * math.pi),
                cy + 0.38 * h * math.sin(a * 2 * math.pi)),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Cloud Tasks: queue of task cards.
  static VsdxShape gcpCloudTasks({
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
        for (final entry in <List<double>>[
          [0.12, 0.15, 0.78, 0.4],
          [0.18, 0.38, 0.84, 0.63],
          [0.24, 0.61, 0.9, 0.88],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(entry[0] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[1] * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.27, 0.5, 0.74]) ...[
            MoveTo(0.3 * w, y * h),
            LineTo(0.7 * w, y * h),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Firestore: document store with flame tip.
  static VsdxShape gcpFirestore({
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
          MoveTo(0.2 * w, 0.2 * h),
          LineTo(0.7 * w, 0.2 * h),
          LineTo(0.85 * w, 0.35 * h),
          LineTo(0.85 * w, 0.88 * h),
          LineTo(0.2 * w, 0.88 * h),
          LineTo(0.2 * w, 0.2 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.7 * w, 0.2 * h),
          LineTo(0.7 * w, 0.35 * h),
          LineTo(0.85 * w, 0.35 * h),
          LineTo(0.7 * w, 0.2 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.32 * w, 0.48 * h),
          LineTo(0.7 * w, 0.48 * h),
          MoveTo(0.32 * w, 0.62 * h),
          LineTo(0.7 * w, 0.62 * h),
          MoveTo(0.32 * w, 0.76 * h),
          LineTo(0.58 * w, 0.76 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Secret Manager: vault with keyhole.
  static VsdxShape gcpSecretManager({
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
          MoveTo(0.2 * w, 0.35 * h),
          LineTo(0.8 * w, 0.35 * h),
          LineTo(0.8 * w, 0.9 * h),
          LineTo(0.2 * w, 0.9 * h),
          LineTo(0.2 * w, 0.35 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.32 * w, 0.35 * h),
          EllipticalArcTo(
              x: 0.68 * w, y: 0.35 * h, controlX: 0.5 * w, controlY: 0.08 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.55 * h,
              aX: 0.58 * w,
              aY: 0.55 * h,
              bX: 0.5 * w,
              bY: 0.63 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.46 * w, 0.6 * h),
          LineTo(0.54 * w, 0.6 * h),
          LineTo(0.54 * w, 0.78 * h),
          LineTo(0.46 * w, 0.78 * h),
          LineTo(0.46 * w, 0.6 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// GCP Vertex AI: neural-net node cluster.
  static VsdxShape gcpVertexAi({
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
        for (final p in <List<double>>[
          [0.2, 0.25],
          [0.2, 0.5],
          [0.2, 0.75],
          [0.5, 0.35],
          [0.5, 0.65],
          [0.8, 0.5],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.07 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.07 * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.25, 0.5, 0.75]) ...[
            MoveTo(0.2 * w, y * h),
            LineTo(0.5 * w, 0.35 * h),
            MoveTo(0.2 * w, y * h),
            LineTo(0.5 * w, 0.65 * h),
          ],
          MoveTo(0.5 * w, 0.35 * h),
          LineTo(0.8 * w, 0.5 * h),
          MoveTo(0.5 * w, 0.65 * h),
          LineTo(0.8 * w, 0.5 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Cisco Router: rounded chassis with dual antennae and status LEDs.
  static VsdxShape ciscoRouter({
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
    final r = 0.08 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(r, 0.72 * h),
          LineTo(w - r, 0.72 * h),
          EllipticalArcTo(
              x: w, y: 0.72 * h - r, controlX: w, controlY: 0.72 * h),
          LineTo(w, 0.28 * h + r),
          EllipticalArcTo(
              x: w - r, y: 0.28 * h, controlX: w, controlY: 0.28 * h),
          LineTo(r, 0.28 * h),
          EllipticalArcTo(
              x: 0, y: 0.28 * h + r, controlX: 0, controlY: 0.28 * h),
          LineTo(0, 0.72 * h - r),
          EllipticalArcTo(x: r, y: 0.72 * h, controlX: 0, controlY: 0.72 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.22 * w, 0.28 * h),
          LineTo(0.18 * w, 0.08 * h),
          MoveTo(0.78 * w, 0.28 * h),
          LineTo(0.82 * w, 0.08 * h),
          MoveTo(0.2 * w, 0.72 * h),
          LineTo(0.16 * w, 0.92 * h),
          MoveTo(0.8 * w, 0.72 * h),
          LineTo(0.84 * w, 0.92 * h),
        ]),
        for (final x in <double>[0.3, 0.42, 0.54])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: x * w,
                cy: 0.5 * h,
                aX: x * w + 0.035 * w,
                aY: 0.5 * h,
                bX: x * w,
                bY: 0.5 * h + 0.04 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Cisco Switch: wide chassis with dense port bank.
  static VsdxShape ciscoSwitch({
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
    final ports = <VsdxPathCommand>[];
    const n = 8;
    final gap = w * 0.02;
    final pw = (w * 0.84 - gap * (n - 1)) / n;
    final ph = h * 0.22;
    final y0 = h * 0.38;
    var x = w * 0.08;
    for (var i = 0; i < n; i++) {
      ports
        ..add(MoveTo(x, y0))
        ..add(LineTo(x + pw, y0))
        ..add(LineTo(x + pw, y0 + ph))
        ..add(LineTo(x, y0 + ph))
        ..add(LineTo(x, y0));
      x += pw + gap;
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
          MoveTo(0.04 * w, 0.22 * h),
          LineTo(0.96 * w, 0.22 * h),
          LineTo(0.96 * w, 0.78 * h),
          LineTo(0.04 * w, 0.78 * h),
          LineTo(0.04 * w, 0.22 * h),
        ]),
        VsdxGeometry(noFill: true, commands: ports),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.1 * w, 0.3 * h),
          LineTo(0.28 * w, 0.3 * h),
          EllipseCmd(
              cx: 0.88 * w,
              cy: 0.3 * h,
              aX: 0.91 * w,
              aY: 0.3 * h,
              bX: 0.88 * w,
              bY: 0.36 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// ASA Firewall: security appliance with shield badge.
  static VsdxShape ciscoAsaFirewall({
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
          MoveTo(0.08 * w, 0.2 * h),
          LineTo(0.92 * w, 0.2 * h),
          LineTo(0.92 * w, 0.78 * h),
          LineTo(0.08 * w, 0.78 * h),
          LineTo(0.08 * w, 0.2 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.5 * w, 0.32 * h),
          LineTo(0.72 * w, 0.4 * h),
          LineTo(0.68 * w, 0.58 * h),
          EllipticalArcTo(
              x: 0.32 * w, y: 0.58 * h, controlX: 0.5 * w, controlY: 0.72 * h),
          LineTo(0.28 * w, 0.4 * h),
          LineTo(0.5 * w, 0.32 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.28, 0.7]) ...[
            MoveTo(0.14 * w, y * h),
            LineTo(0.26 * w, y * h),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Access Point: ceiling AP dome with RF arcs.
  static VsdxShape ciscoAccessPoint({
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
    final cx = 0.5 * w;
    final cy = 0.55 * h;
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
              cy: cy,
              aX: cx + 0.28 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.22 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: cy,
              aX: cx + 0.1 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.08 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.22 * w, 0.28 * h),
          EllipticalArcTo(
              x: 0.78 * w, y: 0.28 * h, controlX: cx, controlY: 0.08 * h),
          MoveTo(0.3 * w, 0.38 * h),
          EllipticalArcTo(
              x: 0.7 * w, y: 0.38 * h, controlX: cx, controlY: 0.22 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Nexus Switch: modular data-center chassis.
  static VsdxShape ciscoNexusSwitch({
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
          MoveTo(0.06 * w, 0.1 * h),
          LineTo(0.94 * w, 0.1 * h),
          LineTo(0.94 * w, 0.9 * h),
          LineTo(0.06 * w, 0.9 * h),
          LineTo(0.06 * w, 0.1 * h),
        ]),
        for (final y in <double>[0.22, 0.42, 0.62])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(0.14 * w, y * h),
            LineTo(0.86 * w, y * h),
            LineTo(0.86 * w, (y + 0.14) * h),
            LineTo(0.14 * w, (y + 0.14) * h),
            LineTo(0.14 * w, y * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.18 * w, 0.82 * h),
          LineTo(0.4 * w, 0.82 * h),
          EllipseCmd(
              cx: 0.78 * w,
              cy: 0.82 * h,
              aX: 0.82 * w,
              aY: 0.82 * h,
              bX: 0.78 * w,
              bY: 0.87 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Catalyst Switch: enterprise stackable switch.
  static VsdxShape ciscoCatalystSwitch({
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
        for (final entry in <List<double>>[
          [0.08, 0.12, 0.92, 0.38],
          [0.1, 0.4, 0.9, 0.66],
          [0.12, 0.68, 0.88, 0.9],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(entry[0] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[1] * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.25, 0.53, 0.79]) ...[
            MoveTo(0.2 * w, y * h),
            LineTo(0.55 * w, y * h),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IP Phone: desk set with handset and keypad.
  static VsdxShape ciscoIpPhone({
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
    final r = 0.08 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(r, 0.15 * h),
          LineTo(0.62 * w - r, 0.15 * h),
          EllipticalArcTo(
              x: 0.62 * w, y: 0.15 * h + r, controlX: 0.62 * w, controlY: 0.15 * h),
          LineTo(0.62 * w, 0.85 * h - r),
          EllipticalArcTo(
              x: 0.62 * w - r, y: 0.85 * h, controlX: 0.62 * w, controlY: 0.85 * h),
          LineTo(r, 0.85 * h),
          EllipticalArcTo(
              x: 0, y: 0.85 * h - r, controlX: 0, controlY: 0.85 * h),
          LineTo(0, 0.15 * h + r),
          EllipticalArcTo(x: r, y: 0.15 * h, controlX: 0, controlY: 0.15 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.7 * w, 0.22 * h),
          LineTo(0.95 * w, 0.18 * h),
          LineTo(0.92 * w, 0.78 * h),
          LineTo(0.68 * w, 0.72 * h),
          LineTo(0.7 * w, 0.22 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final row in <double>[0.35, 0.5, 0.65])
            for (final col in <double>[0.15, 0.3, 0.45]) ...[
              MoveTo(col * w, row * h),
              LineTo((col + 0.08) * w, row * h),
              LineTo((col + 0.08) * w, (row + 0.08) * h),
              LineTo(col * w, (row + 0.08) * h),
              LineTo(col * w, row * h),
            ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Call Manager: UC server tower with LCD strip.
  static VsdxShape ciscoCallManager({
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
          MoveTo(0.22 * w, 0.08 * h),
          LineTo(0.78 * w, 0.08 * h),
          LineTo(0.78 * w, 0.92 * h),
          LineTo(0.22 * w, 0.92 * h),
          LineTo(0.22 * w, 0.08 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.3 * w, 0.18 * h),
          LineTo(0.7 * w, 0.18 * h),
          LineTo(0.7 * w, 0.38 * h),
          LineTo(0.3 * w, 0.38 * h),
          LineTo(0.3 * w, 0.18 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.5, 0.62, 0.74]) ...[
            MoveTo(0.32 * w, y * h),
            LineTo(0.68 * w, y * h),
          ],
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.86 * h,
              aX: 0.56 * w,
              aY: 0.86 * h,
              bX: 0.5 * w,
              bY: 0.9 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Layer 3 Switch: switch body with routing diamond.
  static VsdxShape ciscoLayer3Switch({
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
          MoveTo(0.06 * w, 0.28 * h),
          LineTo(0.94 * w, 0.28 * h),
          LineTo(0.94 * w, 0.72 * h),
          LineTo(0.06 * w, 0.72 * h),
          LineTo(0.06 * w, 0.28 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.5 * w, 0.38 * h),
          LineTo(0.68 * w, 0.5 * h),
          LineTo(0.5 * w, 0.62 * h),
          LineTo(0.32 * w, 0.5 * h),
          LineTo(0.5 * w, 0.38 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final x in <double>[0.14, 0.24, 0.76, 0.86]) ...[
            MoveTo(x * w, 0.36 * h),
            LineTo(x * w, 0.64 * h),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// WAN Router: edge router linked to cloud outline.
  static VsdxShape ciscoWanRouter({
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
          MoveTo(0.08 * w, 0.55 * h),
          LineTo(0.48 * w, 0.55 * h),
          LineTo(0.48 * w, 0.85 * h),
          LineTo(0.08 * w, 0.85 * h),
          LineTo(0.08 * w, 0.55 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.55 * w, 0.48 * h),
          EllipticalArcTo(
              x: 0.7 * w, y: 0.32 * h, controlX: 0.52 * w, controlY: 0.3 * h),
          EllipticalArcTo(
              x: 0.88 * w, y: 0.42 * h, controlX: 0.82 * w, controlY: 0.18 * h),
          EllipticalArcTo(
              x: 0.82 * w, y: 0.62 * h, controlX: 0.95 * w, controlY: 0.62 * h),
          LineTo(0.62 * w, 0.62 * h),
          EllipticalArcTo(
              x: 0.55 * w, y: 0.48 * h, controlX: 0.5 * w, controlY: 0.62 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.48 * w, 0.7 * h),
          LineTo(0.58 * w, 0.55 * h),
          MoveTo(0.16 * w, 0.65 * h),
          LineTo(0.36 * w, 0.65 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Voice Gateway: gateway box with phone handset glyph.
  static VsdxShape ciscoVoiceGateway({
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
          MoveTo(0.1 * w, 0.22 * h),
          LineTo(0.9 * w, 0.22 * h),
          LineTo(0.9 * w, 0.78 * h),
          LineTo(0.1 * w, 0.78 * h),
          LineTo(0.1 * w, 0.22 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.32 * w, 0.35 * h),
          LineTo(0.48 * w, 0.35 * h),
          LineTo(0.52 * w, 0.45 * h),
          LineTo(0.48 * w, 0.65 * h),
          LineTo(0.32 * w, 0.65 * h),
          LineTo(0.28 * w, 0.45 * h),
          LineTo(0.32 * w, 0.35 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.58 * w, 0.4 * h),
          EllipticalArcTo(
              x: 0.78 * w, y: 0.4 * h, controlX: 0.68 * w, controlY: 0.28 * h),
          MoveTo(0.62 * w, 0.52 * h),
          EllipticalArcTo(
              x: 0.74 * w, y: 0.52 * h, controlX: 0.68 * w, controlY: 0.44 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// UCS: blade chassis with slot separators.
  static VsdxShape ciscoUcs({
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
          MoveTo(0.08 * w, 0.12 * h),
          LineTo(0.92 * w, 0.12 * h),
          LineTo(0.92 * w, 0.88 * h),
          LineTo(0.08 * w, 0.88 * h),
          LineTo(0.08 * w, 0.12 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final x in <double>[0.28, 0.48, 0.68]) ...[
            MoveTo(x * w, 0.2 * h),
            LineTo(x * w, 0.8 * h),
          ],
          for (final y in <double>[0.35, 0.55, 0.75]) ...[
            MoveTo(0.14 * w, y * h),
            LineTo(0.86 * w, y * h),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Fabric Interconnect: FI pair with fabric fabric links.
  static VsdxShape ciscoFabricInterconnect({
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
        for (final entry in <List<double>>[
          [0.08, 0.18, 0.48, 0.55],
          [0.52, 0.18, 0.92, 0.55],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(entry[0] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[1] * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.48 * w, 0.3 * h),
          LineTo(0.52 * w, 0.3 * h),
          MoveTo(0.48 * w, 0.42 * h),
          LineTo(0.52 * w, 0.42 * h),
          MoveTo(0.28 * w, 0.55 * h),
          LineTo(0.28 * w, 0.82 * h),
          MoveTo(0.72 * w, 0.55 * h),
          LineTo(0.72 * w, 0.82 * h),
          MoveTo(0.18 * w, 0.82 * h),
          LineTo(0.82 * w, 0.82 * h),
        ]),
        for (final x in <double>[0.28, 0.5, 0.72])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: x * w,
                cy: 0.82 * h,
                aX: x * w + 0.04 * w,
                aY: 0.82 * h,
                bX: x * w,
                bY: 0.82 * h + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Content Engine: cache appliance with disk glyph.
  static VsdxShape ciscoContentEngine({
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
    final cx = 0.5 * w;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.12 * w, 0.25 * h),
          LineTo(0.88 * w, 0.25 * h),
          LineTo(0.88 * w, 0.78 * h),
          LineTo(0.12 * w, 0.78 * h),
          LineTo(0.12 * w, 0.25 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: 0.5 * h,
              aX: cx + 0.18 * w,
              aY: 0.5 * h,
              bX: cx,
              bY: 0.5 * h + 0.14 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: 0.5 * h,
              aX: cx + 0.08 * w,
              aY: 0.5 * h,
              bX: cx,
              bY: 0.5 * h + 0.06 * h),
          MoveTo(0.2 * w, 0.35 * h),
          LineTo(0.35 * w, 0.35 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Wireless Controller: WLC chassis with RF badge.
  static VsdxShape ciscoWirelessController({
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
          MoveTo(0.08 * w, 0.25 * h),
          LineTo(0.92 * w, 0.25 * h),
          LineTo(0.92 * w, 0.75 * h),
          LineTo(0.08 * w, 0.75 * h),
          LineTo(0.08 * w, 0.25 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.55 * w, 0.4 * h),
          EllipticalArcTo(
              x: 0.85 * w, y: 0.4 * h, controlX: 0.7 * w, controlY: 0.22 * h),
          MoveTo(0.6 * w, 0.5 * h),
          EllipticalArcTo(
              x: 0.8 * w, y: 0.5 * h, controlX: 0.7 * w, controlY: 0.38 * h),
          MoveTo(0.18 * w, 0.4 * h),
          LineTo(0.42 * w, 0.4 * h),
          MoveTo(0.18 * w, 0.55 * h),
          LineTo(0.42 * w, 0.55 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// PIX Firewall: classic security brick appliance.
  static VsdxShape ciscoPixFirewall({
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
          MoveTo(0.1 * w, 0.2 * h),
          LineTo(0.9 * w, 0.2 * h),
          LineTo(0.9 * w, 0.8 * h),
          LineTo(0.1 * w, 0.8 * h),
          LineTo(0.1 * w, 0.2 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.35, 0.5, 0.65]) ...[
            MoveTo(0.18 * w, y * h),
            LineTo(0.82 * w, y * h),
          ],
          for (final x in <double>[0.35, 0.55, 0.75]) ...[
            MoveTo(x * w, 0.28 * h),
            LineTo(x * w, 0.72 * h),
          ],
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.42 * w, 0.38 * h),
          LineTo(0.58 * w, 0.38 * h),
          LineTo(0.58 * w, 0.62 * h),
          LineTo(0.42 * w, 0.62 * h),
          LineTo(0.42 * w, 0.38 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// ATM Switch: diamond fabric with port nodes.
  static VsdxShape ciscoAtmSwitch({
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
    final cx = 0.5 * w;
    final cy = 0.5 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(cx, 0.12 * h),
          LineTo(0.88 * w, cy),
          LineTo(cx, 0.88 * h),
          LineTo(0.12 * w, cy),
          LineTo(cx, 0.12 * h),
        ]),
        for (final p in <List<double>>[
          [0.5, 0.12],
          [0.88, 0.5],
          [0.5, 0.88],
          [0.12, 0.5],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.05 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Workgroup Switch: compact stackable access switch.
  static VsdxShape ciscoWorkgroupSwitch({
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
    final ports = <VsdxPathCommand>[];
    const n = 5;
    final gap = w * 0.03;
    final pw = (w * 0.8 - gap * (n - 1)) / n;
    final ph = h * 0.25;
    final y0 = h * 0.4;
    var x = w * 0.1;
    for (var i = 0; i < n; i++) {
      ports
        ..add(MoveTo(x, y0))
        ..add(LineTo(x + pw, y0))
        ..add(LineTo(x + pw, y0 + ph))
        ..add(LineTo(x, y0 + ph))
        ..add(LineTo(x, y0));
      x += pw + gap;
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
          MoveTo(0.06 * w, 0.25 * h),
          LineTo(0.94 * w, 0.25 * h),
          LineTo(0.94 * w, 0.78 * h),
          LineTo(0.06 * w, 0.78 * h),
          LineTo(0.06 * w, 0.25 * h),
        ]),
        VsdxGeometry(noFill: true, commands: ports),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Content Switch: load-balancing content switch.
  static VsdxShape ciscoContentSwitch({
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
    final cx = 0.5 * w;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.15 * w, 0.35 * h),
          LineTo(0.85 * w, 0.35 * h),
          LineTo(0.85 * w, 0.65 * h),
          LineTo(0.15 * w, 0.65 * h),
          LineTo(0.15 * w, 0.35 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(cx, 0.12 * h),
          LineTo(cx, 0.35 * h),
          MoveTo(cx, 0.65 * h),
          LineTo(0.2 * w, 0.88 * h),
          MoveTo(cx, 0.65 * h),
          LineTo(cx, 0.9 * h),
          MoveTo(cx, 0.65 * h),
          LineTo(0.8 * w, 0.88 * h),
        ]),
        for (final p in <List<double>>[
          [0.5, 0.12],
          [0.2, 0.88],
          [0.5, 0.9],
          [0.8, 0.88],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.05 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// VPN Concentrator: tunnel concentrator with dual endpoints.
  static VsdxShape ciscoVpnConcentrator({
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
          MoveTo(0.25 * w, 0.3 * h),
          LineTo(0.75 * w, 0.3 * h),
          LineTo(0.75 * w, 0.7 * h),
          LineTo(0.25 * w, 0.7 * h),
          LineTo(0.25 * w, 0.3 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.08 * w, 0.5 * h),
          LineTo(0.25 * w, 0.5 * h),
          MoveTo(0.75 * w, 0.5 * h),
          LineTo(0.92 * w, 0.5 * h),
          MoveTo(0.35 * w, 0.42 * h),
          EllipticalArcTo(
              x: 0.65 * w, y: 0.42 * h, controlX: 0.5 * w, controlY: 0.28 * h),
          MoveTo(0.35 * w, 0.58 * h),
          EllipticalArcTo(
              x: 0.65 * w, y: 0.58 * h, controlX: 0.5 * w, controlY: 0.72 * h),
        ]),
        for (final x in <double>[0.08, 0.92])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: x * w,
                cy: 0.5 * h,
                aX: x * w + 0.05 * w,
                aY: 0.5 * h,
                bX: x * w,
                bY: 0.5 * h + 0.06 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Wireless Bridge: point-to-point bridge with dual dishes.
  static VsdxShape ciscoWirelessBridge({
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
        for (final x in <double>[0.22, 0.78])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: x * w,
                cy: 0.45 * h,
                aX: x * w + 0.14 * w,
                aY: 0.45 * h,
                bX: x * w,
                bY: 0.45 * h + 0.18 * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.36 * w, 0.45 * h),
          LineTo(0.64 * w, 0.45 * h),
          MoveTo(0.22 * w, 0.63 * h),
          LineTo(0.22 * w, 0.88 * h),
          MoveTo(0.78 * w, 0.63 * h),
          LineTo(0.78 * w, 0.88 * h),
          MoveTo(0.12 * w, 0.88 * h),
          LineTo(0.32 * w, 0.88 * h),
          MoveTo(0.68 * w, 0.88 * h),
          LineTo(0.88 * w, 0.88 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Meraki AP: cloud-managed AP tile.
  static VsdxShape ciscoMerakiAp({
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
    final r = 0.12 * math.min(w, h);
    final cx = 0.5 * w;
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
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: 0.55 * h,
              aX: cx + 0.18 * w,
              aY: 0.55 * h,
              bX: cx,
              bY: 0.55 * h + 0.14 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.28 * w, 0.28 * h),
          EllipticalArcTo(
              x: 0.72 * w, y: 0.28 * h, controlX: cx, controlY: 0.1 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Cisco ISE: identity services engine badge.
  static VsdxShape ciscoIse({
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
          MoveTo(0.5 * w, 0.1 * h),
          LineTo(0.88 * w, 0.3 * h),
          LineTo(0.82 * w, 0.7 * h),
          EllipticalArcTo(
              x: 0.18 * w, y: 0.7 * h, controlX: 0.5 * w, controlY: 0.95 * h),
          LineTo(0.12 * w, 0.3 * h),
          LineTo(0.5 * w, 0.1 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.42 * h,
              aX: 0.6 * w,
              aY: 0.42 * h,
              bX: 0.5 * w,
              bY: 0.52 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.35 * w, 0.62 * h),
          LineTo(0.65 * w, 0.62 * h),
          MoveTo(0.4 * w, 0.72 * h),
          LineTo(0.6 * w, 0.72 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// DNA Center: campus controller hub.
  static VsdxShape ciscoDnaCenter({
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
    final cx = 0.5 * w;
    final cy = 0.5 * h;
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
              cy: cy,
              aX: cx + 0.18 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.18 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: cy,
              aX: cx + 0.36 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.36 * h),
          for (final a in <double>[0, 0.25, 0.5, 0.75]) ...[
            MoveTo(cx, cy),
            LineTo(
                cx + 0.36 * w * math.cos(a * 2 * math.pi),
                cy + 0.36 * h * math.sin(a * 2 * math.pi)),
          ],
        ]),
        for (final a in <double>[0, 0.25, 0.5, 0.75])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: cx + 0.36 * w * math.cos(a * 2 * math.pi),
                cy: cy + 0.36 * h * math.sin(a * 2 * math.pi),
                aX: cx + 0.36 * w * math.cos(a * 2 * math.pi) + 0.05 * w,
                aY: cy + 0.36 * h * math.sin(a * 2 * math.pi),
                bX: cx + 0.36 * w * math.cos(a * 2 * math.pi),
                bY: cy + 0.36 * h * math.sin(a * 2 * math.pi) + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Telepresence: room system with screen and camera.
  static VsdxShape ciscoTelepresence({
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
          MoveTo(0.1 * w, 0.15 * h),
          LineTo(0.9 * w, 0.15 * h),
          LineTo(0.9 * w, 0.7 * h),
          LineTo(0.1 * w, 0.7 * h),
          LineTo(0.1 * w, 0.15 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.25 * h),
          LineTo(0.8 * w, 0.25 * h),
          LineTo(0.8 * w, 0.6 * h),
          LineTo(0.2 * w, 0.6 * h),
          LineTo(0.2 * w, 0.25 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.45 * w, 0.7 * h),
          LineTo(0.45 * w, 0.85 * h),
          MoveTo(0.55 * w, 0.7 * h),
          LineTo(0.55 * w, 0.85 * h),
          MoveTo(0.3 * w, 0.85 * h),
          LineTo(0.7 * w, 0.85 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.42 * h,
              aX: 0.58 * w,
              aY: 0.42 * h,
              bX: 0.5 * w,
              bY: 0.5 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Expressway: edge traversal gateway.
  static VsdxShape ciscoExpressway({
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
          MoveTo(0.15 * w, 0.35 * h),
          LineTo(0.55 * w, 0.2 * h),
          LineTo(0.85 * w, 0.35 * h),
          LineTo(0.85 * w, 0.7 * h),
          LineTo(0.55 * w, 0.85 * h),
          LineTo(0.15 * w, 0.7 * h),
          LineTo(0.15 * w, 0.35 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.28 * w, 0.5 * h),
          LineTo(0.72 * w, 0.5 * h),
          MoveTo(0.62 * w, 0.4 * h),
          LineTo(0.72 * w, 0.5 * h),
          LineTo(0.62 * w, 0.6 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Core Switch: chassis with dual supervisor slots.
  static VsdxShape ciscoCoreSwitch({
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
          MoveTo(0.06 * w, 0.1 * h),
          LineTo(0.94 * w, 0.1 * h),
          LineTo(0.94 * w, 0.9 * h),
          LineTo(0.06 * w, 0.9 * h),
          LineTo(0.06 * w, 0.1 * h),
        ]),
        for (final entry in <List<double>>[
          [0.12, 0.18, 0.48, 0.42],
          [0.52, 0.18, 0.88, 0.42],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(entry[0] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[1] * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.52, 0.65, 0.78]) ...[
            MoveTo(0.14 * w, y * h),
            LineTo(0.86 * w, y * h),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Branch Router: compact branch edge router.
  static VsdxShape ciscoBranchRouter({
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
    final r = 0.08 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(r, 0.7 * h),
          LineTo(w - r, 0.7 * h),
          EllipticalArcTo(
              x: w, y: 0.7 * h - r, controlX: w, controlY: 0.7 * h),
          LineTo(w, 0.3 * h + r),
          EllipticalArcTo(
              x: w - r, y: 0.3 * h, controlX: w, controlY: 0.3 * h),
          LineTo(r, 0.3 * h),
          EllipticalArcTo(
              x: 0, y: 0.3 * h + r, controlX: 0, controlY: 0.3 * h),
          LineTo(0, 0.7 * h - r),
          EllipticalArcTo(x: r, y: 0.7 * h, controlX: 0, controlY: 0.7 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.25 * w, 0.3 * h),
          LineTo(0.2 * w, 0.1 * h),
          MoveTo(0.75 * w, 0.3 * h),
          LineTo(0.8 * w, 0.1 * h),
          MoveTo(0.22 * w, 0.5 * h),
          LineTo(0.5 * w, 0.5 * h),
        ]),
        for (final x in <double>[0.6, 0.72])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: x * w,
                cy: 0.5 * h,
                aX: x * w + 0.035 * w,
                aY: 0.5 * h,
                bX: x * w,
                bY: 0.5 * h + 0.04 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba ECS: compute tower with status LEDs.
  static VsdxShape alibabaEcs({
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
    final d = 0.18 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.08 * w, 0.12 * h),
          LineTo(0.72 * w, 0.12 * h),
          LineTo(0.72 * w, 0.78 * h),
          LineTo(0.08 * w, 0.78 * h),
          LineTo(0.08 * w, 0.12 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.72 * w, 0.12 * h),
          LineTo(0.72 * w + d, 0.12 * h + d),
          LineTo(0.72 * w + d, 0.78 * h + d),
          LineTo(0.72 * w, 0.78 * h),
          LineTo(0.72 * w, 0.12 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.08 * w, 0.78 * h),
          LineTo(0.72 * w, 0.78 * h),
          LineTo(0.72 * w + d, 0.78 * h + d),
          LineTo(0.08 * w + d, 0.78 * h + d),
          LineTo(0.08 * w, 0.78 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.28, 0.42, 0.56]) ...[
            MoveTo(0.18 * w, y * h),
            LineTo(0.58 * w, y * h),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba OSS: object storage bucket.
  static VsdxShape alibabaOss({
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
          MoveTo(0.15 * w, 0.82 * h),
          LineTo(0.85 * w, 0.82 * h),
          LineTo(0.78 * w, 0.28 * h),
          LineTo(0.22 * w, 0.28 * h),
          LineTo(0.15 * w, 0.82 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.28 * h),
          LineTo(0.8 * w, 0.28 * h),
          LineTo(0.8 * w, 0.4 * h),
          LineTo(0.2 * w, 0.4 * h),
          LineTo(0.2 * w, 0.28 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.5 * w, 0.4 * h),
          LineTo(0.5 * w, 0.72 * h),
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.58 * h,
              aX: 0.62 * w,
              aY: 0.58 * h,
              bX: 0.5 * w,
              bY: 0.68 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba SLB: server load balancer fan-out.
  static VsdxShape alibabaSlb({
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
    final cx = 0.5 * w;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.25 * w, 0.38 * h),
          LineTo(0.75 * w, 0.38 * h),
          LineTo(0.75 * w, 0.58 * h),
          LineTo(0.25 * w, 0.58 * h),
          LineTo(0.25 * w, 0.38 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(cx, 0.12 * h),
          LineTo(cx, 0.38 * h),
          MoveTo(cx, 0.58 * h),
          LineTo(0.18 * w, 0.88 * h),
          MoveTo(cx, 0.58 * h),
          LineTo(cx, 0.9 * h),
          MoveTo(cx, 0.58 * h),
          LineTo(0.82 * w, 0.88 * h),
        ]),
        for (final p in <List<double>>[
          [0.5, 0.12],
          [0.18, 0.88],
          [0.5, 0.9],
          [0.82, 0.88],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.05 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba ACK: Kubernetes hex cluster.
  static VsdxShape alibabaAck({
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
    List<VsdxPathCommand> hex(double cx, double cy, double r) =>
        <VsdxPathCommand>[
          MoveTo(cx + r, cy),
          LineTo(cx + 0.5 * r, cy + 0.866 * r),
          LineTo(cx - 0.5 * r, cy + 0.866 * r),
          LineTo(cx - r, cy),
          LineTo(cx - 0.5 * r, cy - 0.866 * r),
          LineTo(cx + 0.5 * r, cy - 0.866 * r),
          LineTo(cx + r, cy),
        ];
    final r = 0.18 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: hex(0.5 * w, 0.55 * h, 0.36 * math.min(w, h))),
        VsdxGeometry(commands: hex(0.5 * w, 0.55 * h, r)),
        VsdxGeometry(commands: hex(0.32 * w, 0.35 * h, r * 0.7)),
        VsdxGeometry(commands: hex(0.68 * w, 0.35 * h, r * 0.7)),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba Function Compute: serverless function badge.
  static VsdxShape alibabaFunctionCompute({
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
          MoveTo(0.25 * w, h),
          LineTo(0.75 * w, h),
          LineTo(w, 0.5 * h),
          LineTo(0.75 * w, 0),
          LineTo(0.25 * w, 0),
          LineTo(0, 0.5 * h),
          LineTo(0.25 * w, h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.32 * w, 0.78 * h),
          LineTo(0.48 * w, 0.78 * h),
          LineTo(0.62 * w, 0.22 * h),
          LineTo(0.78 * w, 0.22 * h),
          MoveTo(0.4 * w, 0.5 * h),
          LineTo(0.68 * w, 0.5 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba PolarDB: clustered relational engine.
  static VsdxShape alibabaPolarDb({
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
    final cx = 0.5 * w;
    final left = 0.18 * w;
    final right = 0.82 * w;
    final ry = 0.08 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(left, 0.78 * h),
          LineTo(left, 0.32 * h),
          EllipticalArcTo(
              x: right, y: 0.32 * h, controlX: cx, controlY: 0.32 * h + ry),
          LineTo(right, 0.78 * h),
          EllipticalArcTo(
              x: left, y: 0.78 * h, controlX: cx, controlY: 0.78 * h - ry),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: 0.32 * h,
              aX: cx + 0.32 * w,
              aY: 0.32 * h,
              bX: cx,
              bY: 0.32 * h + ry),
          MoveTo(0.35 * w, 0.32 * h),
          LineTo(0.22 * w, 0.12 * h),
          MoveTo(0.5 * w, 0.32 * h),
          LineTo(0.5 * w, 0.1 * h),
          MoveTo(0.65 * w, 0.32 * h),
          LineTo(0.78 * w, 0.12 * h),
        ]),
        for (final p in <List<double>>[
          [0.22, 0.12],
          [0.5, 0.1],
          [0.78, 0.12],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.06 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.06 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba TableStore: wide-column NoSQL grid.
  static VsdxShape alibabaTableStore({
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
          MoveTo(0.1 * w, 0.15 * h),
          LineTo(0.9 * w, 0.15 * h),
          LineTo(0.9 * w, 0.9 * h),
          LineTo(0.1 * w, 0.9 * h),
          LineTo(0.1 * w, 0.15 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final x in <double>[0.3, 0.5, 0.7]) ...[
            MoveTo(x * w, 0.22 * h),
            LineTo(x * w, 0.82 * h),
          ],
          for (final y in <double>[0.35, 0.55, 0.75]) ...[
            MoveTo(0.18 * w, y * h),
            LineTo(0.82 * w, y * h),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba MaxCompute: big-data warehouse funnel.
  static VsdxShape alibabaMaxCompute({
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
          MoveTo(0.1 * w, 0.15 * h),
          LineTo(0.9 * w, 0.15 * h),
          LineTo(0.7 * w, 0.48 * h),
          LineTo(0.7 * w, 0.85 * h),
          LineTo(0.3 * w, 0.85 * h),
          LineTo(0.3 * w, 0.48 * h),
          LineTo(0.1 * w, 0.15 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.22 * w, 0.3 * h),
          LineTo(0.78 * w, 0.3 * h),
          MoveTo(0.38 * w, 0.58 * h),
          LineTo(0.62 * w, 0.58 * h),
          MoveTo(0.38 * w, 0.72 * h),
          LineTo(0.62 * w, 0.72 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba RocketMQ: message broker with topic rays.
  static VsdxShape alibabaRocketMq({
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
    final cx = 0.5 * w;
    final cy = 0.4 * h;
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
              cy: cy,
              aX: cx + 0.14 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.14 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(cx, cy + 0.14 * h),
          LineTo(0.18 * w, 0.85 * h),
          MoveTo(cx, cy + 0.14 * h),
          LineTo(cx, 0.88 * h),
          MoveTo(cx, cy + 0.14 * h),
          LineTo(0.82 * w, 0.85 * h),
          MoveTo(cx, cy - 0.14 * h),
          LineTo(cx, 0.1 * h),
        ]),
        for (final p in <List<double>>[
          [0.18, 0.85],
          [0.5, 0.88],
          [0.82, 0.85],
          [0.5, 0.1],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.05 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba RAM: identity key / access control.
  static VsdxShape alibabaRam({
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
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.32 * h,
              aX: 0.68 * w,
              aY: 0.32 * h,
              bX: 0.5 * w,
              bY: 0.5 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.42 * w, 0.48 * h),
          LineTo(0.58 * w, 0.48 * h),
          LineTo(0.58 * w, 0.78 * h),
          LineTo(0.42 * w, 0.78 * h),
          LineTo(0.42 * w, 0.48 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.58 * w, 0.62 * h),
          LineTo(0.82 * w, 0.62 * h),
          MoveTo(0.72 * w, 0.62 * h),
          LineTo(0.72 * w, 0.78 * h),
          MoveTo(0.82 * w, 0.62 * h),
          LineTo(0.82 * w, 0.72 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba CEN: cloud enterprise network hub.
  static VsdxShape alibabaCen({
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
    final cx = 0.5 * w;
    final cy = 0.5 * h;
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
              cy: cy,
              aX: cx + 0.16 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.16 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final a in <double>[0, 0.25, 0.5, 0.75]) ...[
            MoveTo(cx, cy),
            LineTo(
                cx + 0.38 * w * math.cos(a * 2 * math.pi),
                cy + 0.38 * h * math.sin(a * 2 * math.pi)),
          ],
        ]),
        for (final a in <double>[0, 0.25, 0.5, 0.75])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: cx + 0.38 * w * math.cos(a * 2 * math.pi),
                cy: cy + 0.38 * h * math.sin(a * 2 * math.pi),
                aX: cx + 0.38 * w * math.cos(a * 2 * math.pi) + 0.06 * w,
                aY: cy + 0.38 * h * math.sin(a * 2 * math.pi),
                bX: cx + 0.38 * w * math.cos(a * 2 * math.pi),
                bY: cy + 0.38 * h * math.sin(a * 2 * math.pi) + 0.06 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba SLS: log service stream lines.
  static VsdxShape alibabaSls({
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
    final r = 0.1 * math.min(w, h);
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.28, 0.45, 0.62]) ...[
            MoveTo(0.15 * w, y * h),
            LineTo(0.85 * w, y * h),
          ],
          MoveTo(0.15 * w, 0.78 * h),
          LineTo(0.55 * w, 0.78 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba NAS: network attached storage drawers.
  static VsdxShape alibabaNas({
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
        for (final entry in <List<double>>[
          [0.15, 0.12, 0.85, 0.38],
          [0.15, 0.4, 0.85, 0.66],
          [0.15, 0.68, 0.85, 0.9],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(entry[0] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[1] * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.25, 0.53, 0.79]) ...[
            MoveTo(0.25 * w, y * h),
            LineTo(0.55 * w, y * h),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba AnalyticDB: analytics warehouse columns.
  static VsdxShape alibabaAnalyticDb({
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
          MoveTo(0.1 * w, 0.12 * h),
          LineTo(0.9 * w, 0.12 * h),
          LineTo(0.9 * w, 0.9 * h),
          LineTo(0.1 * w, 0.9 * h),
          LineTo(0.1 * w, 0.12 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final x in <double>[0.3, 0.5, 0.7]) ...[
            MoveTo(x * w, 0.2 * h),
            LineTo(x * w, 0.82 * h),
          ],
          MoveTo(0.18 * w, 0.35 * h),
          LineTo(0.82 * w, 0.35 * h),
          MoveTo(0.18 * w, 0.55 * h),
          LineTo(0.82 * w, 0.55 * h),
          MoveTo(0.18 * w, 0.75 * h),
          LineTo(0.82 * w, 0.75 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.34 * w, 0.55 * h),
          LineTo(0.46 * w, 0.55 * h),
          LineTo(0.46 * w, 0.82 * h),
          LineTo(0.34 * w, 0.82 * h),
          LineTo(0.34 * w, 0.55 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba CDN: edge cache with globe arcs.
  static VsdxShape alibabaCdn({
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
    final cx = 0.5 * w;
    final cy = 0.48 * h;
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
              cy: cy,
              aX: cx + 0.32 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.28 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: cy,
              aX: cx + 0.12 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.28 * h),
          MoveTo(0.18 * w, cy),
          LineTo(0.82 * w, cy),
        ]),
        for (final x in <double>[0.2, 0.5, 0.8])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(x * w - 0.06 * w, 0.82 * h),
            LineTo(x * w + 0.06 * w, 0.82 * h),
            LineTo(x * w + 0.06 * w, 0.95 * h),
            LineTo(x * w - 0.06 * w, 0.95 * h),
            LineTo(x * w - 0.06 * w, 0.82 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba WAF: web application firewall shield.
  static VsdxShape alibabaWaf({
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
          MoveTo(0.5 * w, 0.08 * h),
          LineTo(0.9 * w, 0.28 * h),
          LineTo(0.84 * w, 0.62 * h),
          EllipticalArcTo(
              x: 0.16 * w, y: 0.62 * h, controlX: 0.5 * w, controlY: 0.95 * h),
          LineTo(0.1 * w, 0.28 * h),
          LineTo(0.5 * w, 0.08 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.3 * w, 0.4 * h),
          LineTo(0.7 * w, 0.4 * h),
          MoveTo(0.35 * w, 0.55 * h),
          LineTo(0.65 * w, 0.55 * h),
          MoveTo(0.5 * w, 0.28 * h),
          LineTo(0.5 * w, 0.7 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba DataWorks: data pipeline board.
  static VsdxShape alibabaDataWorks({
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
    final r = 0.08 * math.min(w, h);
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.18 * w, 0.25 * h),
          LineTo(0.55 * w, 0.25 * h),
          MoveTo(0.18 * w, 0.42 * h),
          LineTo(0.7 * w, 0.42 * h),
          MoveTo(0.18 * w, 0.59 * h),
          LineTo(0.45 * w, 0.59 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.55 * w, 0.68 * h),
          LineTo(0.75 * w, 0.68 * h),
          LineTo(0.85 * w, 0.8 * h),
          LineTo(0.75 * w, 0.92 * h),
          LineTo(0.55 * w, 0.92 * h),
          LineTo(0.65 * w, 0.8 * h),
          LineTo(0.55 * w, 0.68 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba Hologres: real-time warehouse grid.
  static VsdxShape alibabaHologres({
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
          MoveTo(0.1 * w, 0.12 * h),
          LineTo(0.9 * w, 0.12 * h),
          LineTo(0.9 * w, 0.9 * h),
          LineTo(0.1 * w, 0.9 * h),
          LineTo(0.1 * w, 0.12 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final x in <double>[0.3, 0.5, 0.7]) ...[
            MoveTo(x * w, 0.2 * h),
            LineTo(x * w, 0.82 * h),
          ],
          MoveTo(0.18 * w, 0.35 * h),
          LineTo(0.82 * w, 0.35 * h),
          MoveTo(0.18 * w, 0.55 * h),
          LineTo(0.82 * w, 0.55 * h),
          MoveTo(0.18 * w, 0.75 * h),
          LineTo(0.82 * w, 0.75 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.55 * w, 0.2 * h),
          LineTo(0.65 * w, 0.2 * h),
          LineTo(0.65 * w, 0.82 * h),
          LineTo(0.55 * w, 0.82 * h),
          LineTo(0.55 * w, 0.2 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba Flink: streaming compute chevrons.
  static VsdxShape alibabaFlink({
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
    VsdxGeometry chevron(double x0, double x1) => VsdxGeometry(
          commands: <VsdxPathCommand>[
            MoveTo(x0, 0.28 * h),
            LineTo(x1 - 0.07 * w, 0.28 * h),
            LineTo(x1, 0.5 * h),
            LineTo(x1 - 0.07 * w, 0.72 * h),
            LineTo(x0, 0.72 * h),
            LineTo(x0 + 0.07 * w, 0.5 * h),
            LineTo(x0, 0.28 * h),
          ],
        );
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        chevron(0.05 * w, 0.38 * w),
        chevron(0.34 * w, 0.67 * w),
        chevron(0.63 * w, 0.96 * w),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba MSE: microservices engine hub.
  static VsdxShape alibabaMse({
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
    final cx = 0.5 * w;
    final cy = 0.5 * h;
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
              cy: cy,
              aX: cx + 0.16 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.16 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final a in <double>[0, 0.25, 0.5, 0.75]) ...[
            MoveTo(cx, cy),
            LineTo(
                cx + 0.36 * w * math.cos(a * 2 * math.pi),
                cy + 0.36 * h * math.sin(a * 2 * math.pi)),
          ],
        ]),
        for (final a in <double>[0, 0.25, 0.5, 0.75])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: cx + 0.36 * w * math.cos(a * 2 * math.pi),
                cy: cy + 0.36 * h * math.sin(a * 2 * math.pi),
                aX: cx + 0.36 * w * math.cos(a * 2 * math.pi) + 0.06 * w,
                aY: cy + 0.36 * h * math.sin(a * 2 * math.pi),
                bX: cx + 0.36 * w * math.cos(a * 2 * math.pi),
                bY: cy + 0.36 * h * math.sin(a * 2 * math.pi) + 0.06 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba ASM: service mesh hex cells.
  static VsdxShape alibabaAsm({
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
    List<VsdxPathCommand> hex(double cx, double cy, double r) =>
        <VsdxPathCommand>[
          MoveTo(cx + r, cy),
          LineTo(cx + 0.5 * r, cy + 0.866 * r),
          LineTo(cx - 0.5 * r, cy + 0.866 * r),
          LineTo(cx - r, cy),
          LineTo(cx - 0.5 * r, cy - 0.866 * r),
          LineTo(cx + 0.5 * r, cy - 0.866 * r),
          LineTo(cx + r, cy),
        ];
    final r = 0.18 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: hex(0.3 * w, 0.55 * h, r)),
        VsdxGeometry(commands: hex(0.7 * w, 0.55 * h, r)),
        VsdxGeometry(commands: hex(0.5 * w, 0.28 * h, r)),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.3 * w, 0.55 * h),
          LineTo(0.5 * w, 0.28 * h),
          LineTo(0.7 * w, 0.55 * h),
          LineTo(0.3 * w, 0.55 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba ACR: container registry vault.
  static VsdxShape alibabaAcr({
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
          MoveTo(0.15 * w, 0.2 * h),
          LineTo(0.85 * w, 0.2 * h),
          LineTo(0.85 * w, 0.85 * h),
          LineTo(0.15 * w, 0.85 * h),
          LineTo(0.15 * w, 0.2 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.55 * w, 0.32 * h),
          LineTo(0.78 * w, 0.32 * h),
          LineTo(0.78 * w, 0.52 * h),
          LineTo(0.55 * w, 0.52 * h),
          LineTo(0.55 * w, 0.32 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.25 * w, 0.38 * h),
          LineTo(0.48 * w, 0.38 * h),
          MoveTo(0.25 * w, 0.55 * h),
          LineTo(0.48 * w, 0.55 * h),
          MoveTo(0.25 * w, 0.7 * h),
          LineTo(0.7 * w, 0.7 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba EIP: elastic public IP badge.
  static VsdxShape alibabaEip({
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
    final cx = 0.5 * w;
    final cy = 0.5 * h;
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
              cy: cy,
              aX: cx + 0.38 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.38 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.22 * w, cy),
          LineTo(0.78 * w, cy),
          MoveTo(cx, 0.22 * h),
          LineTo(cx, 0.78 * h),
          EllipseCmd(
              cx: cx,
              cy: cy,
              aX: cx + 0.18 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.38 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba NAT Gateway: outbound NAT appliance.
  static VsdxShape alibabaNatGateway({
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
          MoveTo(0.15 * w, 0.35 * h),
          LineTo(0.85 * w, 0.35 * h),
          LineTo(0.85 * w, 0.7 * h),
          LineTo(0.15 * w, 0.7 * h),
          LineTo(0.15 * w, 0.35 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.28 * w, 0.2 * h),
          LineTo(0.28 * w, 0.35 * h),
          MoveTo(0.5 * w, 0.15 * h),
          LineTo(0.5 * w, 0.35 * h),
          MoveTo(0.72 * w, 0.2 * h),
          LineTo(0.72 * w, 0.35 * h),
          MoveTo(0.5 * w, 0.7 * h),
          LineTo(0.5 * w, 0.88 * h),
        ]),
        for (final p in <List<double>>[
          [0.28, 0.2],
          [0.5, 0.15],
          [0.72, 0.2],
          [0.5, 0.88],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.05 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba KMS: key management vault.
  static VsdxShape alibabaKms({
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
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.32 * h,
              aX: 0.68 * w,
              aY: 0.32 * h,
              bX: 0.5 * w,
              bY: 0.5 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.42 * w, 0.48 * h),
          LineTo(0.58 * w, 0.48 * h),
          LineTo(0.58 * w, 0.78 * h),
          LineTo(0.42 * w, 0.78 * h),
          LineTo(0.42 * w, 0.48 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.58 * w, 0.62 * h),
          LineTo(0.82 * w, 0.62 * h),
          MoveTo(0.72 * w, 0.62 * h),
          LineTo(0.72 * w, 0.78 * h),
          MoveTo(0.82 * w, 0.62 * h),
          LineTo(0.82 * w, 0.72 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba ARMS: APM metrics sparkline.
  static VsdxShape alibabaArms({
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
    final r = 0.1 * math.min(w, h);
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.15 * w, 0.65 * h),
          LineTo(0.32 * w, 0.45 * h),
          LineTo(0.45 * w, 0.55 * h),
          LineTo(0.6 * w, 0.28 * h),
          LineTo(0.75 * w, 0.4 * h),
          LineTo(0.88 * w, 0.22 * h),
          MoveTo(0.15 * w, 0.8 * h),
          LineTo(0.88 * w, 0.8 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba Lindorm: multi-model store stack.
  static VsdxShape alibabaLindorm({
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
        for (final entry in <List<double>>[
          [0.15, 0.7, 0.85, 0.92],
          [0.22, 0.42, 0.78, 0.64],
          [0.3, 0.14, 0.7, 0.36],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(entry[0] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[1] * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.35 * w, 0.81 * h),
          LineTo(0.65 * w, 0.81 * h),
          MoveTo(0.4 * w, 0.53 * h),
          LineTo(0.6 * w, 0.53 * h),
          MoveTo(0.42 * w, 0.25 * h),
          LineTo(0.58 * w, 0.25 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Alibaba DTS: data transmission funnel.
  static VsdxShape alibabaDts({
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
          MoveTo(0.1 * w, 0.15 * h),
          LineTo(0.9 * w, 0.15 * h),
          LineTo(0.7 * w, 0.48 * h),
          LineTo(0.7 * w, 0.85 * h),
          LineTo(0.3 * w, 0.85 * h),
          LineTo(0.3 * w, 0.48 * h),
          LineTo(0.1 * w, 0.15 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.22 * w, 0.3 * h),
          LineTo(0.78 * w, 0.3 * h),
          MoveTo(0.38 * w, 0.58 * h),
          LineTo(0.62 * w, 0.58 * h),
          MoveTo(0.38 * w, 0.72 * h),
          LineTo(0.62 * w, 0.72 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM VPC: region cloud with subnet nodes.
  static VsdxShape ibmVpc({
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
          MoveTo(0.2 * w, 0.62 * h),
          EllipticalArcTo(
              x: 0.38 * w, y: 0.42 * h, controlX: 0.18 * w, controlY: 0.4 * h),
          EllipticalArcTo(
              x: 0.62 * w, y: 0.35 * h, controlX: 0.5 * w, controlY: 0.18 * h),
          EllipticalArcTo(
              x: 0.82 * w, y: 0.55 * h, controlX: 0.88 * w, controlY: 0.3 * h),
          EllipticalArcTo(
              x: 0.72 * w, y: 0.78 * h, controlX: 0.9 * w, controlY: 0.78 * h),
          LineTo(0.28 * w, 0.78 * h),
          EllipticalArcTo(
              x: 0.2 * w, y: 0.62 * h, controlX: 0.12 * w, controlY: 0.78 * h),
        ]),
        for (final p in <List<double>>[
          [0.35, 0.55],
          [0.5, 0.48],
          [0.65, 0.58],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.04 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.04 * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.35 * w, 0.55 * h),
          LineTo(0.5 * w, 0.48 * h),
          LineTo(0.65 * w, 0.58 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM Cloud Object Storage: COS bucket.
  static VsdxShape ibmCloudObjectStorage({
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
          MoveTo(0.15 * w, 0.82 * h),
          LineTo(0.85 * w, 0.82 * h),
          LineTo(0.78 * w, 0.28 * h),
          LineTo(0.22 * w, 0.28 * h),
          LineTo(0.15 * w, 0.82 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.28 * h),
          LineTo(0.8 * w, 0.28 * h),
          LineTo(0.8 * w, 0.4 * h),
          LineTo(0.2 * w, 0.4 * h),
          LineTo(0.2 * w, 0.28 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.32 * w, 0.28 * h),
          EllipticalArcTo(
              x: 0.68 * w,
              y: 0.28 * h,
              controlX: 0.5 * w,
              controlY: 0.08 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM IKS: Kubernetes hex cluster.
  static VsdxShape ibmIks({
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
    List<VsdxPathCommand> hex(double cx, double cy, double r) =>
        <VsdxPathCommand>[
          MoveTo(cx + r, cy),
          LineTo(cx + 0.5 * r, cy + 0.866 * r),
          LineTo(cx - 0.5 * r, cy + 0.866 * r),
          LineTo(cx - r, cy),
          LineTo(cx - 0.5 * r, cy - 0.866 * r),
          LineTo(cx + 0.5 * r, cy - 0.866 * r),
          LineTo(cx + r, cy),
        ];
    final r = 0.18 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: hex(0.5 * w, 0.55 * h, 0.36 * math.min(w, h))),
        VsdxGeometry(commands: hex(0.5 * w, 0.55 * h, r)),
        VsdxGeometry(commands: hex(0.32 * w, 0.35 * h, r * 0.7)),
        VsdxGeometry(commands: hex(0.68 * w, 0.35 * h, r * 0.7)),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM ROKS: OpenShift-style wheel.
  static VsdxShape ibmRoks({
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
    final cx = 0.5 * w;
    final cy = 0.5 * h;
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
              cy: cy,
              aX: cx + 0.38 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.38 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: cy,
              aX: cx + 0.14 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.14 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final a in <double>[0, 0.2, 0.4, 0.6, 0.8]) ...[
            MoveTo(
                cx + 0.14 * w * math.cos(a * 2 * math.pi),
                cy + 0.14 * h * math.sin(a * 2 * math.pi)),
            LineTo(
                cx + 0.38 * w * math.cos(a * 2 * math.pi),
                cy + 0.38 * h * math.sin(a * 2 * math.pi)),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM Db2: cylinder database.
  static VsdxShape ibmDb2({
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
    final left = 0.18 * w;
    final right = 0.82 * w;
    final cx = 0.5 * w;
    final ry = 0.08 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(left, 0.78 * h),
          LineTo(left, 0.28 * h),
          EllipticalArcTo(
              x: right, y: 0.28 * h, controlX: cx, controlY: 0.28 * h + ry),
          LineTo(right, 0.78 * h),
          EllipticalArcTo(
              x: left, y: 0.78 * h, controlX: cx, controlY: 0.78 * h - ry),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: 0.28 * h,
              aX: cx + 0.32 * w,
              aY: 0.28 * h,
              bX: cx,
              bY: 0.28 * h + ry),
          MoveTo(left, 0.5 * h),
          EllipticalArcTo(
              x: right, y: 0.5 * h, controlX: cx, controlY: 0.5 * h + ry),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM Cloudant: document store with couch glyph.
  static VsdxShape ibmCloudant({
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
          MoveTo(0.2 * w, 0.2 * h),
          LineTo(0.7 * w, 0.2 * h),
          LineTo(0.85 * w, 0.35 * h),
          LineTo(0.85 * w, 0.88 * h),
          LineTo(0.2 * w, 0.88 * h),
          LineTo(0.2 * w, 0.2 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.7 * w, 0.2 * h),
          LineTo(0.7 * w, 0.35 * h),
          LineTo(0.85 * w, 0.35 * h),
          LineTo(0.7 * w, 0.2 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.32 * w, 0.48 * h),
          LineTo(0.7 * w, 0.48 * h),
          MoveTo(0.32 * w, 0.62 * h),
          LineTo(0.7 * w, 0.62 * h),
          MoveTo(0.32 * w, 0.76 * h),
          LineTo(0.58 * w, 0.76 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM Event Streams: Kafka-style stream waves.
  static VsdxShape ibmEventStreams({
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.25, 0.5, 0.75]) ...[
            MoveTo(0.08 * w, y * h),
            EllipticalArcTo(
                x: 0.35 * w,
                y: y * h,
                controlX: 0.22 * w,
                controlY: y * h + 0.12 * h),
            EllipticalArcTo(
                x: 0.65 * w,
                y: y * h,
                controlX: 0.5 * w,
                controlY: y * h - 0.12 * h),
            EllipticalArcTo(
                x: 0.92 * w,
                y: y * h,
                controlX: 0.78 * w,
                controlY: y * h + 0.12 * h),
          ],
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.78 * w, 0.42 * h),
          LineTo(0.95 * w, 0.5 * h),
          LineTo(0.78 * w, 0.58 * h),
          LineTo(0.78 * w, 0.42 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM MQ: message queue broker.
  static VsdxShape ibmMq({
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
    final cx = 0.5 * w;
    final cy = 0.42 * h;
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
              cy: cy,
              aX: cx + 0.14 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.14 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(cx, cy + 0.14 * h),
          LineTo(0.18 * w, 0.85 * h),
          MoveTo(cx, cy + 0.14 * h),
          LineTo(cx, 0.88 * h),
          MoveTo(cx, cy + 0.14 * h),
          LineTo(0.82 * w, 0.85 * h),
        ]),
        for (final p in <List<double>>[
          [0.18, 0.85],
          [0.5, 0.88],
          [0.82, 0.85],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.05 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM watsonx: AI neural-net cluster.
  static VsdxShape ibmWatsonx({
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
        for (final p in <List<double>>[
          [0.2, 0.25],
          [0.2, 0.5],
          [0.2, 0.75],
          [0.5, 0.35],
          [0.5, 0.65],
          [0.8, 0.5],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.07 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.07 * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.25, 0.5, 0.75]) ...[
            MoveTo(0.2 * w, y * h),
            LineTo(0.5 * w, 0.35 * h),
            MoveTo(0.2 * w, y * h),
            LineTo(0.5 * w, 0.65 * h),
          ],
          MoveTo(0.5 * w, 0.35 * h),
          LineTo(0.8 * w, 0.5 * h),
          MoveTo(0.5 * w, 0.65 * h),
          LineTo(0.8 * w, 0.5 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM Code Engine: serverless run capsule.
  static VsdxShape ibmCodeEngine({
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
    final r = 0.2 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(r, 0.78 * h),
          LineTo(w - r, 0.78 * h),
          EllipticalArcTo(
              x: w, y: 0.78 * h - r, controlX: w, controlY: 0.78 * h),
          LineTo(w, 0.22 * h + r),
          EllipticalArcTo(
              x: w - r, y: 0.22 * h, controlX: w, controlY: 0.22 * h),
          LineTo(r, 0.22 * h),
          EllipticalArcTo(
              x: 0, y: 0.22 * h + r, controlX: 0, controlY: 0.22 * h),
          LineTo(0, 0.78 * h - r),
          EllipticalArcTo(x: r, y: 0.78 * h, controlX: 0, controlY: 0.78 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.62 * w, 0.4 * h),
          LineTo(0.82 * w, 0.5 * h),
          LineTo(0.62 * w, 0.6 * h),
          LineTo(0.62 * w, 0.4 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.4 * h),
          LineTo(0.5 * w, 0.4 * h),
          MoveTo(0.2 * w, 0.55 * h),
          LineTo(0.45 * w, 0.55 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM API Connect: API portal gateway.
  static VsdxShape ibmApiConnect({
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
    final r = 0.1 * math.min(w, h);
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.3 * h),
          LineTo(0.55 * w, 0.3 * h),
          MoveTo(0.2 * w, 0.5 * h),
          LineTo(0.7 * w, 0.5 * h),
          MoveTo(0.2 * w, 0.7 * h),
          LineTo(0.45 * w, 0.7 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.75 * w,
              cy: 0.7 * h,
              aX: 0.82 * w,
              aY: 0.7 * h,
              bX: 0.75 * w,
              bY: 0.78 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM App ID: identity badge.
  static VsdxShape ibmAppId({
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
          MoveTo(0.5 * w, 0.1 * h),
          LineTo(0.88 * w, 0.3 * h),
          LineTo(0.82 * w, 0.7 * h),
          EllipticalArcTo(
              x: 0.18 * w, y: 0.7 * h, controlX: 0.5 * w, controlY: 0.95 * h),
          LineTo(0.12 * w, 0.3 * h),
          LineTo(0.5 * w, 0.1 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.4 * h,
              aX: 0.6 * w,
              aY: 0.4 * h,
              bX: 0.5 * w,
              bY: 0.52 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.35 * w, 0.62 * h),
          LineTo(0.65 * w, 0.62 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM Key Protect: vault with keyhole.
  static VsdxShape ibmKeyProtect({
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
          MoveTo(0.2 * w, 0.35 * h),
          LineTo(0.8 * w, 0.35 * h),
          LineTo(0.8 * w, 0.9 * h),
          LineTo(0.2 * w, 0.9 * h),
          LineTo(0.2 * w, 0.35 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.32 * w, 0.35 * h),
          EllipticalArcTo(
              x: 0.68 * w, y: 0.35 * h, controlX: 0.5 * w, controlY: 0.08 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.55 * h,
              aX: 0.58 * w,
              aY: 0.55 * h,
              bX: 0.5 * w,
              bY: 0.63 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.46 * w, 0.6 * h),
          LineTo(0.54 * w, 0.6 * h),
          LineTo(0.54 * w, 0.78 * h),
          LineTo(0.46 * w, 0.78 * h),
          LineTo(0.46 * w, 0.6 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM Direct Link: dedicated interconnect.
  static VsdxShape ibmDirectLink({
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
          MoveTo(0.08 * w, 0.55 * h),
          LineTo(0.42 * w, 0.55 * h),
          LineTo(0.42 * w, 0.85 * h),
          LineTo(0.08 * w, 0.85 * h),
          LineTo(0.08 * w, 0.55 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.55 * w, 0.48 * h),
          EllipticalArcTo(
              x: 0.7 * w, y: 0.32 * h, controlX: 0.52 * w, controlY: 0.3 * h),
          EllipticalArcTo(
              x: 0.88 * w, y: 0.42 * h, controlX: 0.82 * w, controlY: 0.18 * h),
          EllipticalArcTo(
              x: 0.82 * w, y: 0.62 * h, controlX: 0.95 * w, controlY: 0.62 * h),
          LineTo(0.62 * w, 0.62 * h),
          EllipticalArcTo(
              x: 0.55 * w, y: 0.48 * h, controlX: 0.5 * w, controlY: 0.62 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.42 * w, 0.7 * h),
          LineTo(0.58 * w, 0.55 * h),
          MoveTo(0.15 * w, 0.65 * h),
          LineTo(0.35 * w, 0.65 * h),
          MoveTo(0.15 * w, 0.75 * h),
          LineTo(0.35 * w, 0.75 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM Activity Tracker: audit trail footprints.
  static VsdxShape ibmActivityTracker({
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.15 * w, 0.75 * h),
          LineTo(0.35 * w, 0.55 * h),
          LineTo(0.55 * w, 0.65 * h),
          LineTo(0.75 * w, 0.35 * h),
          LineTo(0.9 * w, 0.25 * h),
        ]),
        for (final p in <List<double>>[
          [0.15, 0.75],
          [0.35, 0.55],
          [0.55, 0.65],
          [0.75, 0.35],
          [0.9, 0.25],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.05 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM Log Analysis: log stream lines in a tile.
  static VsdxShape ibmLogAnalysis({
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
    final r = 0.1 * math.min(w, h);
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.28, 0.45, 0.62]) ...[
            MoveTo(0.15 * w, y * h),
            LineTo(0.85 * w, y * h),
          ],
          MoveTo(0.15 * w, 0.78 * h),
          LineTo(0.55 * w, 0.78 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM Schematics: IaC template stack.
  static VsdxShape ibmSchematics({
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
        for (final entry in <List<double>>[
          [0.12, 0.15, 0.78, 0.4],
          [0.18, 0.38, 0.84, 0.63],
          [0.24, 0.61, 0.9, 0.88],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(entry[0] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[1] * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.27, 0.5, 0.74]) ...[
            MoveTo(0.3 * w, y * h),
            LineTo(0.7 * w, y * h),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM Satellite: hybrid edge satellite node.
  static VsdxShape ibmSatellite({
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
    final cx = 0.5 * w;
    final cy = 0.55 * h;
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
              cy: cy,
              aX: cx + 0.22 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.18 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.22 * w, 0.28 * h),
          EllipticalArcTo(
              x: 0.78 * w, y: 0.28 * h, controlX: cx, controlY: 0.08 * h),
          MoveTo(0.3 * w, 0.38 * h),
          EllipticalArcTo(
              x: 0.7 * w, y: 0.38 * h, controlX: cx, controlY: 0.22 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: cy,
              aX: cx + 0.08 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.08 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM Power VS: Power Virtual Server chassis.
  static VsdxShape ibmPowerVs({
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
    final d = 0.18 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.08 * w, 0.12 * h),
          LineTo(0.72 * w, 0.12 * h),
          LineTo(0.72 * w, 0.78 * h),
          LineTo(0.08 * w, 0.78 * h),
          LineTo(0.08 * w, 0.12 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.72 * w, 0.12 * h),
          LineTo(0.72 * w + d, 0.12 * h + d),
          LineTo(0.72 * w + d, 0.78 * h + d),
          LineTo(0.72 * w, 0.78 * h),
          LineTo(0.72 * w, 0.12 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.08 * w, 0.78 * h),
          LineTo(0.72 * w, 0.78 * h),
          LineTo(0.72 * w + d, 0.78 * h + d),
          LineTo(0.08 * w + d, 0.78 * h + d),
          LineTo(0.08 * w, 0.78 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.55 * w, 0.28 * h),
          LineTo(0.65 * w, 0.42 * h),
          LineTo(0.55 * w, 0.56 * h),
          LineTo(0.45 * w, 0.42 * h),
          LineTo(0.55 * w, 0.28 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM Bare Metal: dense rack server.
  static VsdxShape ibmBareMetal({
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
          MoveTo(0.12 * w, 0.1 * h),
          LineTo(0.88 * w, 0.1 * h),
          LineTo(0.88 * w, 0.9 * h),
          LineTo(0.12 * w, 0.9 * h),
          LineTo(0.12 * w, 0.1 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.28, 0.45, 0.62, 0.78]) ...[
            MoveTo(0.22 * w, y * h),
            LineTo(0.78 * w, y * h),
          ],
        ]),
        for (final y in <double>[0.28, 0.45, 0.62, 0.78])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: 0.78 * w,
                cy: y * h,
                aX: 0.84 * w,
                aY: y * h,
                bX: 0.78 * w,
                bY: y * h + 0.04 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM Block Storage: stacked block volumes.
  static VsdxShape ibmBlockStorage({
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
        for (final entry in <List<double>>[
          [0.15, 0.15, 0.85, 0.4],
          [0.15, 0.42, 0.85, 0.67],
          [0.15, 0.69, 0.85, 0.9],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(entry[0] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[1] * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.27, 0.54, 0.79]) ...[
            MoveTo(0.28 * w, y * h),
            LineTo(0.72 * w, y * h),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM File Storage: file share drawers.
  static VsdxShape ibmFileStorage({
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
        for (final entry in <List<double>>[
          [0.15, 0.12, 0.85, 0.38],
          [0.15, 0.4, 0.85, 0.66],
          [0.15, 0.68, 0.85, 0.9],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(entry[0] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[1] * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.25, 0.53, 0.79]) ...[
            MoveTo(0.25 * w, y * h),
            LineTo(0.55 * w, y * h),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM CIS: Cloud Internet Services edge.
  static VsdxShape ibmCis({
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
    final cx = 0.5 * w;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.35 * h),
          LineTo(0.8 * w, 0.35 * h),
          LineTo(0.8 * w, 0.58 * h),
          LineTo(0.2 * w, 0.58 * h),
          LineTo(0.2 * w, 0.35 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(cx, 0.1 * h),
          LineTo(cx, 0.35 * h),
          MoveTo(cx, 0.58 * h),
          LineTo(0.18 * w, 0.88 * h),
          MoveTo(cx, 0.58 * h),
          LineTo(cx, 0.9 * h),
          MoveTo(cx, 0.58 * h),
          LineTo(0.82 * w, 0.88 * h),
        ]),
        for (final p in <List<double>>[
          [0.5, 0.1],
          [0.18, 0.88],
          [0.5, 0.9],
          [0.82, 0.88],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.05 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM Internet Services: DNS / CDN / WAF edge stack.
  static VsdxShape ibmInternetServices({
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
    final cx = 0.5 * w;
    final cy = 0.55 * h;
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
              cy: cy,
              aX: cx + 0.38 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.32 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(cx - 0.18 * w, cy - 0.28 * h),
          LineTo(cx - 0.18 * w, cy + 0.28 * h),
          MoveTo(cx + 0.18 * w, cy - 0.28 * h),
          LineTo(cx + 0.18 * w, cy + 0.28 * h),
          MoveTo(cx - 0.35 * w, cy - 0.1 * h),
          EllipticalArcTo(
              x: cx + 0.35 * w,
              y: cy - 0.1 * h,
              controlX: cx,
              controlY: cy - 0.22 * h),
          MoveTo(cx - 0.35 * w, cy + 0.12 * h),
          EllipticalArcTo(
              x: cx + 0.35 * w,
              y: cy + 0.12 * h,
              controlX: cx,
              controlY: cy + 0.24 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.22 * w, 0.12 * h),
          LineTo(0.78 * w, 0.12 * h),
          LineTo(0.78 * w, 0.28 * h),
          LineTo(0.22 * w, 0.28 * h),
          LineTo(0.22 * w, 0.12 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM Aspera: high-speed transfer arrow.
  static VsdxShape ibmAspera({
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
          MoveTo(0.08 * w, 0.38 * h),
          LineTo(0.58 * w, 0.38 * h),
          LineTo(0.58 * w, 0.22 * h),
          LineTo(0.92 * w, 0.5 * h),
          LineTo(0.58 * w, 0.78 * h),
          LineTo(0.58 * w, 0.62 * h),
          LineTo(0.08 * w, 0.62 * h),
          LineTo(0.08 * w, 0.38 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.18 * w, 0.28 * h),
          LineTo(0.35 * w, 0.28 * h),
          MoveTo(0.18 * w, 0.72 * h),
          LineTo(0.35 * w, 0.72 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM Certificate Manager: cert badge with seal.
  static VsdxShape ibmCertificateManager({
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
          MoveTo(0.18 * w, 0.15 * h),
          LineTo(0.82 * w, 0.15 * h),
          LineTo(0.82 * w, 0.75 * h),
          LineTo(0.5 * w, 0.9 * h),
          LineTo(0.18 * w, 0.75 * h),
          LineTo(0.18 * w, 0.15 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.3 * w, 0.35 * h),
          LineTo(0.7 * w, 0.35 * h),
          MoveTo(0.3 * w, 0.5 * h),
          LineTo(0.7 * w, 0.5 * h),
          MoveTo(0.3 * w, 0.65 * h),
          LineTo(0.55 * w, 0.65 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.65 * w,
              cy: 0.72 * h,
              aX: 0.75 * w,
              aY: 0.72 * h,
              bX: 0.65 * w,
              bY: 0.82 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM Toolchain: CI/CD linked stages.
  static VsdxShape ibmToolchain({
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
        for (final p in <List<double>>[
          [0.2, 0.5],
          [0.5, 0.5],
          [0.8, 0.5],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.1 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.12 * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.3 * w, 0.5 * h),
          LineTo(0.4 * w, 0.5 * h),
          MoveTo(0.6 * w, 0.5 * h),
          LineTo(0.7 * w, 0.5 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.15 * w, 0.2 * h),
          LineTo(0.35 * w, 0.2 * h),
          LineTo(0.35 * w, 0.32 * h),
          LineTo(0.15 * w, 0.32 * h),
          LineTo(0.15 * w, 0.2 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// IBM Security Advisor: security posture shield.
  static VsdxShape ibmSecurityAdvisor({
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
          MoveTo(0.5 * w, 0.08 * h),
          LineTo(0.9 * w, 0.28 * h),
          LineTo(0.84 * w, 0.62 * h),
          EllipticalArcTo(
              x: 0.16 * w, y: 0.62 * h, controlX: 0.5 * w, controlY: 0.95 * h),
          LineTo(0.1 * w, 0.28 * h),
          LineTo(0.5 * w, 0.08 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.35 * w, 0.45 * h),
          LineTo(0.48 * w, 0.6 * h),
          LineTo(0.7 * w, 0.35 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Oracle Compute Instance: isometric compute cube.
  static VsdxShape oracleComputeInstance({
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
    final d = 0.18 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.08 * w, 0.12 * h),
          LineTo(0.72 * w, 0.12 * h),
          LineTo(0.72 * w, 0.78 * h),
          LineTo(0.08 * w, 0.78 * h),
          LineTo(0.08 * w, 0.12 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.72 * w, 0.12 * h),
          LineTo(0.72 * w + d, 0.12 * h + d),
          LineTo(0.72 * w + d, 0.78 * h + d),
          LineTo(0.72 * w, 0.78 * h),
          LineTo(0.72 * w, 0.12 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.08 * w, 0.78 * h),
          LineTo(0.72 * w, 0.78 * h),
          LineTo(0.72 * w + d, 0.78 * h + d),
          LineTo(0.08 * w + d, 0.78 * h + d),
          LineTo(0.08 * w, 0.78 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.28, 0.42, 0.56]) ...[
            MoveTo(0.18 * w, y * h),
            LineTo(0.58 * w, y * h),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Oracle Autonomous Database: ADB cylinder with autonomy badge.
  static VsdxShape oracleAutonomousDatabase({
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
    final left = 0.18 * w;
    final right = 0.82 * w;
    final cx = 0.5 * w;
    final ry = 0.08 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(left, 0.78 * h),
          LineTo(left, 0.32 * h),
          EllipticalArcTo(
              x: right, y: 0.32 * h, controlX: cx, controlY: 0.32 * h + ry),
          LineTo(right, 0.78 * h),
          EllipticalArcTo(
              x: left, y: 0.78 * h, controlX: cx, controlY: 0.78 * h - ry),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: 0.32 * h,
              aX: cx + 0.32 * w,
              aY: 0.32 * h,
              bX: cx,
              bY: 0.32 * h + ry),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.72 * w,
              cy: 0.18 * h,
              aX: 0.82 * w,
              aY: 0.18 * h,
              bX: 0.72 * w,
              bY: 0.28 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Oracle Object Storage: storage bucket.
  static VsdxShape oracleObjectStorage({
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
          MoveTo(0.15 * w, 0.82 * h),
          LineTo(0.85 * w, 0.82 * h),
          LineTo(0.78 * w, 0.28 * h),
          LineTo(0.22 * w, 0.28 * h),
          LineTo(0.15 * w, 0.82 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.28 * h),
          LineTo(0.8 * w, 0.28 * h),
          LineTo(0.8 * w, 0.4 * h),
          LineTo(0.2 * w, 0.4 * h),
          LineTo(0.2 * w, 0.28 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.32 * w, 0.28 * h),
          EllipticalArcTo(
              x: 0.68 * w,
              y: 0.28 * h,
              controlX: 0.5 * w,
              controlY: 0.08 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Oracle Block Volume: stacked disk volumes.
  static VsdxShape oracleBlockVolume({
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
        for (final entry in <List<double>>[
          [0.15, 0.15, 0.85, 0.4],
          [0.15, 0.42, 0.85, 0.67],
          [0.15, 0.69, 0.85, 0.9],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(entry[0] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[1] * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.27, 0.54, 0.79]) ...[
            MoveTo(0.28 * w, y * h),
            LineTo(0.72 * w, y * h),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Oracle OKE: Kubernetes Engine hex cluster.
  static VsdxShape oracleOke({
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
    List<VsdxPathCommand> hex(double cx, double cy, double r) =>
        <VsdxPathCommand>[
          MoveTo(cx + r, cy),
          LineTo(cx + 0.5 * r, cy + 0.866 * r),
          LineTo(cx - 0.5 * r, cy + 0.866 * r),
          LineTo(cx - r, cy),
          LineTo(cx - 0.5 * r, cy - 0.866 * r),
          LineTo(cx + 0.5 * r, cy - 0.866 * r),
          LineTo(cx + r, cy),
        ];
    final r = 0.18 * math.min(w, h);
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: hex(0.5 * w, 0.55 * h, 0.36 * math.min(w, h))),
        VsdxGeometry(commands: hex(0.5 * w, 0.55 * h, r)),
        VsdxGeometry(commands: hex(0.32 * w, 0.35 * h, r * 0.7)),
        VsdxGeometry(commands: hex(0.68 * w, 0.35 * h, r * 0.7)),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Oracle Functions: serverless hex badge.
  static VsdxShape oracleFunctions({
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
          MoveTo(0.25 * w, h),
          LineTo(0.75 * w, h),
          LineTo(w, 0.5 * h),
          LineTo(0.75 * w, 0),
          LineTo(0.25 * w, 0),
          LineTo(0, 0.5 * h),
          LineTo(0.25 * w, h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.32 * w, 0.78 * h),
          LineTo(0.48 * w, 0.78 * h),
          LineTo(0.62 * w, 0.22 * h),
          LineTo(0.78 * w, 0.22 * h),
          MoveTo(0.4 * w, 0.5 * h),
          LineTo(0.68 * w, 0.5 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Oracle VCN: virtual cloud network outline.
  static VsdxShape oracleVcn({
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
          MoveTo(0.2 * w, 0.62 * h),
          EllipticalArcTo(
              x: 0.38 * w, y: 0.42 * h, controlX: 0.18 * w, controlY: 0.4 * h),
          EllipticalArcTo(
              x: 0.62 * w, y: 0.35 * h, controlX: 0.5 * w, controlY: 0.18 * h),
          EllipticalArcTo(
              x: 0.82 * w, y: 0.55 * h, controlX: 0.88 * w, controlY: 0.3 * h),
          EllipticalArcTo(
              x: 0.72 * w, y: 0.78 * h, controlX: 0.9 * w, controlY: 0.78 * h),
          LineTo(0.28 * w, 0.78 * h),
          EllipticalArcTo(
              x: 0.2 * w, y: 0.62 * h, controlX: 0.12 * w, controlY: 0.78 * h),
        ]),
        for (final p in <List<double>>[
          [0.35, 0.55],
          [0.5, 0.48],
          [0.65, 0.58],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.04 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.04 * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.35 * w, 0.55 * h),
          LineTo(0.5 * w, 0.48 * h),
          LineTo(0.65 * w, 0.58 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Oracle Load Balancer: fan-out balancer.
  static VsdxShape oracleLoadBalancer({
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
    final cx = 0.5 * w;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.25 * w, 0.38 * h),
          LineTo(0.75 * w, 0.38 * h),
          LineTo(0.75 * w, 0.58 * h),
          LineTo(0.25 * w, 0.58 * h),
          LineTo(0.25 * w, 0.38 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(cx, 0.12 * h),
          LineTo(cx, 0.38 * h),
          MoveTo(cx, 0.58 * h),
          LineTo(0.18 * w, 0.88 * h),
          MoveTo(cx, 0.58 * h),
          LineTo(cx, 0.9 * h),
          MoveTo(cx, 0.58 * h),
          LineTo(0.82 * w, 0.88 * h),
        ]),
        for (final p in <List<double>>[
          [0.5, 0.12],
          [0.18, 0.88],
          [0.5, 0.9],
          [0.82, 0.88],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.05 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Oracle Streaming: data stream waves.
  static VsdxShape oracleStreaming({
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.25, 0.5, 0.75]) ...[
            MoveTo(0.08 * w, y * h),
            EllipticalArcTo(
                x: 0.35 * w,
                y: y * h,
                controlX: 0.22 * w,
                controlY: y * h + 0.12 * h),
            EllipticalArcTo(
                x: 0.65 * w,
                y: y * h,
                controlX: 0.5 * w,
                controlY: y * h - 0.12 * h),
            EllipticalArcTo(
                x: 0.92 * w,
                y: y * h,
                controlX: 0.78 * w,
                controlY: y * h + 0.12 * h),
          ],
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.78 * w, 0.42 * h),
          LineTo(0.95 * w, 0.5 * h),
          LineTo(0.78 * w, 0.58 * h),
          LineTo(0.78 * w, 0.42 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Oracle Vault: secrets vault with keyhole.
  static VsdxShape oracleVault({
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
          MoveTo(0.2 * w, 0.35 * h),
          LineTo(0.8 * w, 0.35 * h),
          LineTo(0.8 * w, 0.9 * h),
          LineTo(0.2 * w, 0.9 * h),
          LineTo(0.2 * w, 0.35 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.32 * w, 0.35 * h),
          EllipticalArcTo(
              x: 0.68 * w, y: 0.35 * h, controlX: 0.5 * w, controlY: 0.08 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.5 * w,
              cy: 0.55 * h,
              aX: 0.58 * w,
              aY: 0.55 * h,
              bX: 0.5 * w,
              bY: 0.63 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.46 * w, 0.6 * h),
          LineTo(0.54 * w, 0.6 * h),
          LineTo(0.54 * w, 0.78 * h),
          LineTo(0.46 * w, 0.78 * h),
          LineTo(0.46 * w, 0.6 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Oracle Exadata: engineered system chassis.
  static VsdxShape oracleExadata({
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
          MoveTo(0.08 * w, 0.1 * h),
          LineTo(0.92 * w, 0.1 * h),
          LineTo(0.92 * w, 0.9 * h),
          LineTo(0.08 * w, 0.9 * h),
          LineTo(0.08 * w, 0.1 * h),
        ]),
        for (final y in <double>[0.22, 0.42, 0.62])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(0.16 * w, y * h),
            LineTo(0.84 * w, y * h),
            LineTo(0.84 * w, (y + 0.14) * h),
            LineTo(0.16 * w, (y + 0.14) * h),
            LineTo(0.16 * w, y * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.2 * w, 0.82 * h),
          LineTo(0.45 * w, 0.82 * h),
          EllipseCmd(
              cx: 0.75 * w,
              cy: 0.82 * h,
              aX: 0.8 * w,
              aY: 0.82 * h,
              bX: 0.75 * w,
              bY: 0.87 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Oracle MySQL HeatWave: accelerated analytics DB.
  static VsdxShape oracleMysqlHeatwave({
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
    final left = 0.15 * w;
    final right = 0.7 * w;
    final cx = 0.425 * w;
    final ry = 0.07 * h;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(left, 0.75 * h),
          LineTo(left, 0.3 * h),
          EllipticalArcTo(
              x: right, y: 0.3 * h, controlX: cx, controlY: 0.3 * h + ry),
          LineTo(right, 0.75 * h),
          EllipticalArcTo(
              x: left, y: 0.75 * h, controlX: cx, controlY: 0.75 * h - ry),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: cx,
              cy: 0.3 * h,
              aX: cx + 0.275 * w,
              aY: 0.3 * h,
              bX: cx,
              bY: 0.3 * h + ry),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.72 * w, 0.25 * h),
          LineTo(0.88 * w, 0.45 * h),
          LineTo(0.78 * w, 0.45 * h),
          LineTo(0.92 * w, 0.75 * h),
          LineTo(0.76 * w, 0.55 * h),
          LineTo(0.85 * w, 0.55 * h),
          LineTo(0.72 * w, 0.25 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Oracle GoldenGate: replication pipeline chevrons.
  static VsdxShape oracleGoldenGate({
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
    VsdxGeometry chevron(double x0, double x1) => VsdxGeometry(
          commands: <VsdxPathCommand>[
            MoveTo(x0, 0.28 * h),
            LineTo(x1 - 0.07 * w, 0.28 * h),
            LineTo(x1, 0.5 * h),
            LineTo(x1 - 0.07 * w, 0.72 * h),
            LineTo(x0, 0.72 * h),
            LineTo(x0 + 0.07 * w, 0.5 * h),
            LineTo(x0, 0.28 * h),
          ],
        );
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        chevron(0.05 * w, 0.38 * w),
        chevron(0.34 * w, 0.67 * w),
        chevron(0.63 * w, 0.96 * w),
      ],
      fill: fill,
      line: line,
    );
  }

  /// Oracle Analytics Cloud: analytics dashboard tile.
  static VsdxShape oracleAnalyticsCloud({
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
    final r = 0.1 * math.min(w, h);
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.15 * w, 0.65 * h),
          LineTo(0.32 * w, 0.45 * h),
          LineTo(0.45 * w, 0.55 * h),
          LineTo(0.6 * w, 0.28 * h),
          LineTo(0.75 * w, 0.4 * h),
          LineTo(0.88 * w, 0.22 * h),
          MoveTo(0.15 * w, 0.8 * h),
          LineTo(0.88 * w, 0.8 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// OCI API Gateway: gateway portal with routes.
  static VsdxShape oracleApiGateway({
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
    final cx = 0.5 * w;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.18 * w, 0.28 * h),
          LineTo(0.82 * w, 0.28 * h),
          LineTo(0.82 * w, 0.62 * h),
          LineTo(0.18 * w, 0.62 * h),
          LineTo(0.18 * w, 0.28 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(cx, 0.08 * h),
          LineTo(cx, 0.28 * h),
          MoveTo(cx, 0.62 * h),
          LineTo(0.2 * w, 0.9 * h),
          MoveTo(cx, 0.62 * h),
          LineTo(cx, 0.92 * h),
          MoveTo(cx, 0.62 * h),
          LineTo(0.8 * w, 0.9 * h),
          MoveTo(0.28 * w, 0.4 * h),
          LineTo(0.72 * w, 0.4 * h),
          MoveTo(0.28 * w, 0.5 * h),
          LineTo(0.55 * w, 0.5 * h),
        ]),
        for (final p in <List<double>>[
          [0.5, 0.08],
          [0.2, 0.9],
          [0.5, 0.92],
          [0.8, 0.9],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.05 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// OCI Service Connector: pipe linking source to target.
  static VsdxShape oracleServiceConnector({
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
          EllipseCmd(
              cx: 0.2 * w,
              cy: 0.5 * h,
              aX: 0.32 * w,
              aY: 0.5 * h,
              bX: 0.2 * w,
              bY: 0.68 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.8 * w,
              cy: 0.5 * h,
              aX: 0.92 * w,
              aY: 0.5 * h,
              bX: 0.8 * w,
              bY: 0.68 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.32 * w, 0.38 * h),
          LineTo(0.68 * w, 0.38 * h),
          LineTo(0.68 * w, 0.62 * h),
          LineTo(0.32 * w, 0.62 * h),
          LineTo(0.32 * w, 0.38 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.4 * w, 0.5 * h),
          LineTo(0.6 * w, 0.5 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// OCI Notifications: bell / alert tile.
  static VsdxShape oracleNotifications({
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
          MoveTo(0.5 * w, 0.12 * h),
          EllipticalArcTo(
              x: 0.28 * w, y: 0.42 * h, controlX: 0.28 * w, controlY: 0.18 * h),
          LineTo(0.22 * w, 0.68 * h),
          LineTo(0.78 * w, 0.68 * h),
          LineTo(0.72 * w, 0.42 * h),
          EllipticalArcTo(
              x: 0.5 * w, y: 0.12 * h, controlX: 0.72 * w, controlY: 0.18 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.35 * w, 0.68 * h),
          EllipticalArcTo(
              x: 0.65 * w, y: 0.68 * h, controlX: 0.5 * w, controlY: 0.9 * h),
          LineTo(0.35 * w, 0.68 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.72 * w,
              cy: 0.22 * h,
              aX: 0.82 * w,
              aY: 0.22 * h,
              bX: 0.72 * w,
              bY: 0.32 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// OCI Events: event burst rays from a core.
  static VsdxShape oracleEvents({
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
    final cx = 0.5 * w;
    final cy = 0.5 * h;
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
              cy: cy,
              aX: cx + 0.16 * w,
              aY: cy,
              bX: cx,
              bY: cy + 0.16 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final p in <List<double>>[
            [0.5, 0.1, 0.5, 0.28],
            [0.5, 0.72, 0.5, 0.9],
            [0.1, 0.5, 0.28, 0.5],
            [0.72, 0.5, 0.9, 0.5],
            [0.22, 0.22, 0.34, 0.34],
            [0.66, 0.66, 0.78, 0.78],
            [0.78, 0.22, 0.66, 0.34],
            [0.22, 0.78, 0.34, 0.66],
          ]) ...[
            MoveTo(p[0] * w, p[1] * h),
            LineTo(p[2] * w, p[3] * h),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// OCI Data Science: notebook / ML tile.
  static VsdxShape oracleDataScience({
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
    final r = 0.1 * math.min(w, h);
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
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.18 * w, 0.28 * h),
          LineTo(0.55 * w, 0.28 * h),
          MoveTo(0.18 * w, 0.45 * h),
          LineTo(0.72 * w, 0.45 * h),
          MoveTo(0.18 * w, 0.62 * h),
          LineTo(0.45 * w, 0.62 * h),
          MoveTo(0.18 * w, 0.78 * h),
          LineTo(0.62 * w, 0.78 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.78 * w,
              cy: 0.28 * h,
              aX: 0.88 * w,
              aY: 0.28 * h,
              bX: 0.78 * w,
              bY: 0.38 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// OCI Data Flow: spark / parallel flow arrows.
  static VsdxShape oracleDataFlow({
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
        for (final y in <double>[0.22, 0.45, 0.68])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(0.08 * w, y * h),
            LineTo(0.62 * w, y * h),
            LineTo(0.62 * w, (y - 0.08) * h),
            LineTo(0.92 * w, (y + 0.08) * h),
            LineTo(0.62 * w, (y + 0.16) * h),
            LineTo(0.62 * w, (y + 0.08) * h),
            LineTo(0.08 * w, (y + 0.08) * h),
            LineTo(0.08 * w, y * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// OCI Data Catalog: catalog card stack.
  static VsdxShape oracleDataCatalog({
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
        for (final entry in <List<double>>[
          [0.12, 0.12, 0.78, 0.38],
          [0.18, 0.35, 0.84, 0.62],
          [0.24, 0.58, 0.9, 0.88],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(entry[0] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[1] * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.25, 0.48, 0.72]) ...[
            MoveTo(0.32 * w, y * h),
            LineTo(0.7 * w, y * h),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// OCI FastConnect: dedicated interconnect.
  static VsdxShape oracleFastConnect({
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
          MoveTo(0.08 * w, 0.55 * h),
          LineTo(0.4 * w, 0.55 * h),
          LineTo(0.4 * w, 0.85 * h),
          LineTo(0.08 * w, 0.85 * h),
          LineTo(0.08 * w, 0.55 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.58 * w, 0.48 * h),
          EllipticalArcTo(
              x: 0.72 * w, y: 0.32 * h, controlX: 0.55 * w, controlY: 0.3 * h),
          EllipticalArcTo(
              x: 0.9 * w, y: 0.42 * h, controlX: 0.84 * w, controlY: 0.18 * h),
          EllipticalArcTo(
              x: 0.84 * w, y: 0.62 * h, controlX: 0.97 * w, controlY: 0.62 * h),
          LineTo(0.65 * w, 0.62 * h),
          EllipticalArcTo(
              x: 0.58 * w, y: 0.48 * h, controlX: 0.52 * w, controlY: 0.62 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.4 * w, 0.7 * h),
          LineTo(0.6 * w, 0.55 * h),
          MoveTo(0.15 * w, 0.65 * h),
          LineTo(0.33 * w, 0.65 * h),
          MoveTo(0.15 * w, 0.75 * h),
          LineTo(0.33 * w, 0.75 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// OCI File Storage: NFS share drawers.
  static VsdxShape oracleFileStorage({
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
        for (final entry in <List<double>>[
          [0.15, 0.12, 0.85, 0.38],
          [0.15, 0.4, 0.85, 0.66],
          [0.15, 0.68, 0.85, 0.9],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(entry[0] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[1] * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.25, 0.53, 0.79]) ...[
            MoveTo(0.25 * w, y * h),
            LineTo(0.55 * w, y * h),
            MoveTo(0.7 * w, y * h - 0.04 * h),
            LineTo(0.78 * w, y * h + 0.04 * h),
            MoveTo(0.78 * w, y * h - 0.04 * h),
            LineTo(0.7 * w, y * h + 0.04 * h),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// OCI Bastion: fortified access gate.
  static VsdxShape oracleBastion({
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
          MoveTo(0.12 * w, 0.35 * h),
          LineTo(0.12 * w, 0.9 * h),
          LineTo(0.88 * w, 0.9 * h),
          LineTo(0.88 * w, 0.35 * h),
          LineTo(0.75 * w, 0.35 * h),
          LineTo(0.75 * w, 0.18 * h),
          LineTo(0.25 * w, 0.18 * h),
          LineTo(0.25 * w, 0.35 * h),
          LineTo(0.12 * w, 0.35 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.38 * w, 0.55 * h),
          LineTo(0.62 * w, 0.55 * h),
          LineTo(0.62 * w, 0.9 * h),
          LineTo(0.38 * w, 0.9 * h),
          LineTo(0.38 * w, 0.55 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
              cx: 0.55 * w,
              cy: 0.7 * h,
              aX: 0.59 * w,
              aY: 0.7 * h,
              bX: 0.55 * w,
              bY: 0.74 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// OCI Network Load Balancer: L4 fan-out.
  static VsdxShape oracleNetworkLoadBalancer({
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
    final cx = 0.5 * w;
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
              cy: 0.38 * h,
              aX: cx + 0.28 * w,
              aY: 0.38 * h,
              bX: cx,
              bY: 0.55 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(cx, 0.1 * h),
          LineTo(cx, 0.22 * h),
          MoveTo(cx, 0.55 * h),
          LineTo(0.15 * w, 0.88 * h),
          MoveTo(cx, 0.55 * h),
          LineTo(cx, 0.9 * h),
          MoveTo(cx, 0.55 * h),
          LineTo(0.85 * w, 0.88 * h),
        ]),
        for (final p in <List<double>>[
          [0.5, 0.1],
          [0.15, 0.88],
          [0.5, 0.9],
          [0.85, 0.88],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.05 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.05 * h),
          ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// OCI Cloud Guard: posture shield.
  static VsdxShape oracleCloudGuard({
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
          MoveTo(0.5 * w, 0.08 * h),
          LineTo(0.9 * w, 0.28 * h),
          LineTo(0.84 * w, 0.62 * h),
          EllipticalArcTo(
              x: 0.16 * w, y: 0.62 * h, controlX: 0.5 * w, controlY: 0.95 * h),
          LineTo(0.1 * w, 0.28 * h),
          LineTo(0.5 * w, 0.08 * h),
        ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.35 * w, 0.42 * h),
          LineTo(0.48 * w, 0.58 * h),
          LineTo(0.7 * w, 0.32 * h),
          MoveTo(0.28 * w, 0.7 * h),
          LineTo(0.72 * w, 0.7 * h),
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// OCI Resource Manager: IaC stack layers.
  static VsdxShape oracleResourceManager({
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
        for (final entry in <List<double>>[
          [0.12, 0.15, 0.78, 0.4],
          [0.18, 0.38, 0.84, 0.63],
          [0.24, 0.61, 0.9, 0.88],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(entry[0] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[1] * h),
            LineTo(entry[2] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[3] * h),
            LineTo(entry[0] * w, entry[1] * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          for (final y in <double>[0.27, 0.5, 0.74]) ...[
            MoveTo(0.3 * w, y * h),
            LineTo(0.7 * w, y * h),
          ],
        ]),
      ],
      fill: fill,
      line: line,
    );
  }

  /// OCI DevOps: CI/CD pipeline stages.
  static VsdxShape oracleDevOps({
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
        for (final p in <List<double>>[
          [0.2, 0.5],
          [0.5, 0.5],
          [0.8, 0.5],
        ])
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
                cx: p[0] * w,
                cy: p[1] * h,
                aX: p[0] * w + 0.1 * w,
                aY: p[1] * h,
                bX: p[0] * w,
                bY: p[1] * h + 0.12 * h),
          ]),
        VsdxGeometry(noFill: true, commands: <VsdxPathCommand>[
          MoveTo(0.3 * w, 0.5 * h),
          LineTo(0.4 * w, 0.5 * h),
          MoveTo(0.6 * w, 0.5 * h),
          LineTo(0.7 * w, 0.5 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.12 * w, 0.18 * h),
          LineTo(0.38 * w, 0.18 * h),
          LineTo(0.38 * w, 0.32 * h),
          LineTo(0.12 * w, 0.32 * h),
          LineTo(0.12 * w, 0.18 * h),
        ]),
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(0.62 * w, 0.68 * h),
          LineTo(0.88 * w, 0.68 * h),
          LineTo(0.88 * w, 0.82 * h),
          LineTo(0.62 * w, 0.82 * h),
          LineTo(0.62 * w, 0.68 * h),
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
  /// Uses Visio Begin-origin XForm (`Width=EndX-BeginX`) and `ConFixedCode=3`
  /// so 万兴图示 keeps baked elbow Geometry instead of freely re-routing.
  static VsdxShape line({
    required int id,
    required double ax,
    required double ay,
    required double bx,
    required double by,
    VsdxLine line = _defaultLine,
    String? name,
  }) {
    final w = bx - ax;
    final h = by - ay;
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: (ax + bx) / 2,
      pinY: (ay + by) / 2,
      width: w,
      height: h,
      locPinXInches: w / 2,
      locPinYInches: h / 2,
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
        'Width': 'EndX-BeginX',
        'Height': 'EndY-BeginY',
        'LocPinX': '(EndX-BeginX)/2',
        'LocPinY': '(EndY-BeginY)/2',
      },
      connectorProps: const VsdxConnectorProps(
        glueType: 2,
        // 3 = Reroute on crossover (Visio authored elbows). 0 = freely —
        // 万兴图示 then replaces Geometry with a Begin→End straight line.
        conFixedCode: 3,
        dynFeedback: 2,
        noLiveDynamics: true,
        conLineRouteExt: 1,
        shapeRouteStyle: 16,
      ),
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          commands: <VsdxPathCommand>[
            const MoveTo(0, 0),
            LineTo(w, h),
          ],
          noFill: true,
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
  }
}
