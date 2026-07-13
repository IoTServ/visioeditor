/// Visio Shape — the atomic display element.
///
/// Field set grows alongside the milestones:
///  * M0 — XForm (PinX/PinY/Width/Height/Angle) + plain text + sub-shapes
///  * M3 — geometry sections, fill, line
///  * M3+ — master ref, layers, custom data (planned)
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'connect.dart';
import 'effects.dart';
import 'fill.dart';
import 'geometry.dart';
import 'hyperlink.dart';
import 'line.dart';
import 'rich_text.dart';
import 'shape_kind.dart';
import 'user_property.dart';

@immutable
class VsdxShape {
  const VsdxShape({
    required this.id,
    required this.name,
    required this.pinX,
    required this.pinY,
    required this.width,
    required this.height,
    this.angleRad = 0,
    this.text,
    this.richText = VsdxRichText.empty,
    this.children = const <VsdxShape>[],
    this.geometries = const <VsdxGeometry>[],
    this.fill = VsdxFill.defaultFill,
    this.line = VsdxLine.defaultLine,
    this.shadow = VsdxShadow.disabled,
    this.glow = VsdxGlow.disabled,
    this.reflection = VsdxReflection.disabled,
    this.layerMemberIds = const <int>[],
    this.is1D = false,
    this.beginX,
    this.beginY,
    this.endX,
    this.endY,
    this.straightRoute = false,
    this.curved = false,
    this.waypoints = const <Offset2D>[],
    this.flipX = false,
    this.flipY = false,
    this.locked = false,
    this.imagePartName,
    this.connects = const <VsdxConnect>[],
    this.hyperlinks = const <VsdxHyperlink>[],
    this.userProperties = const <VsdxUserProperty>[],
    this.userCells = const <VsdxUserCell>[],
    this.masterName,
    this.shapeKind = VsdxShapeKind.normal,
  });

  /// Visio shape id (`Shape ID="..."`); unique within the page.
  final int id;

  /// `NameU` attribute, defaults to `Sheet.<id>`.
  final String name;

  /// All coordinates are in **page inches** (see `lib/utils/units.dart`).
  /// `pinX`/`pinY` is the shape anchor — see `lib/utils/transform.dart`.
  final double pinX;
  final double pinY;
  final double width;
  final double height;

  /// Rotation about pin, **radians** (CCW per Visio convention, flipped at
  /// render time when mapping to Flutter's coordinate system).
  final double angleRad;

  /// Plain text content — convenience cache populated from [richText] for
  /// shapes that don't carry any style markup.
  final String? text;

  /// Full rich-text body (runs, char/para style, text block geometry).
  final VsdxRichText richText;

  /// Sub-shapes (Group). Empty for atomic shapes.
  final List<VsdxShape> children;

  /// Zero or more `<Section N="Geometry">` blocks attached to this shape.
  /// Renderers draw all of them in source order.
  final List<VsdxGeometry> geometries;

  final VsdxFill fill;
  final VsdxLine line;
  final VsdxShadow shadow;
  final VsdxGlow glow;
  final VsdxReflection reflection;

  /// Layer membership — parsed from `LayerMember` cell `"0;3;5"`.
  /// Empty list ⇒ no explicit layer (always drawn).
  final List<int> layerMemberIds;

  /// `true` when this is a 1-D shape (line / connector). 1-D shapes carry
  /// `BeginX`/`BeginY`/`EndX`/`EndY` instead of (or in addition to) a Pin.
  final bool is1D;

  /// Begin point (`BeginX`/`BeginY`) in page-local inches — only set for
  /// 1-D shapes.
  final double? beginX;
  final double? beginY;
  final double? endX;
  final double? endY;

  /// Routing preference for connectors: `true` = a single straight segment,
  /// `false` (default) = orthogonal elbow. Session-level (not persisted as a
  /// dedicated cell); the drawn geometry itself is what round-trips.
  final bool straightRoute;

  /// When `true`, this connector is drawn as a smooth (drawio "curved") spline
  /// through its route control points instead of a polyline. The smooth curve
  /// is baked into the geometry as a densely-sampled `LineTo` polyline, so it
  /// round-trips as ordinary geometry; this flag is session-level and only
  /// steers how [VsdxPage.rerouteConnectors] rebuilds that geometry.
  final bool curved;

  /// User-placed interior bend points for a connector, in page inches. When
  /// non-empty the route runs begin → waypoints → end (overriding straight /
  /// elbow). Session-level; the drawn geometry is what round-trips.
  final List<Offset2D> waypoints;

  /// `FlipX` / `FlipY` flags from the shape's XForm.
  final bool flipX;
  final bool flipY;

  /// drawio-style "locked" flag. When `true` the shape can be selected but not
  /// moved, resized, rotated, deleted or text-edited (drawio's Lock/Unlock,
  /// Cmd+L). Round-trips to Visio's protection cells (`LockMoveX`/`LockMoveY`/
  /// `LockWidth`/`LockHeight`/`LockAspect`/`LockRotate`/`LockDelete`/
  /// `LockTextEdit`); `LockMoveX` is the canonical bit read back on parse.
  final bool locked;

  /// Absolute part name of the embedded picture this shape displays
  /// (`/visio/media/imageN.png`), or `null` when the shape is not a
  /// picture. Renderers resolve the actual bytes via
  /// [VsdxDocument.images.findByPart].
  final String? imagePartName;

  /// `<Connect>` rows on this shape (typically only set on the page-sheet
  /// for connector wiring; most user shapes leave this empty).
  final List<VsdxConnect> connects;

  /// `<Section N="Hyperlink">` rows. Empty for the vast majority of shapes.
  final List<VsdxHyperlink> hyperlinks;

  /// `<Section N="Property">` rows — Visio's user-facing "Shape Data"
  /// fields. Surface in the inspector panel and the search index.
  final List<VsdxUserProperty> userProperties;

  /// `<Section N="User">` rows — programmer-facing scratch cells. Mostly
  /// useful for tooling and CLI text dumps.
  final List<VsdxUserCell> userCells;

  /// `Master.NameU` of the master this shape was instantiated from
  /// (`null` when the shape carries no `Master` attribute or its master
  /// went missing). Useful for container/swimlane detection and stencil
  /// browsing UI.
  final String? masterName;

  /// Heuristic semantic classification (container / swimlane / callout …).
  /// See [ShapeKindDetector] in `lib/parser/shape_kind_detector.dart`.
  final VsdxShapeKind shapeKind;

  /// True when the shape has at least one geometry section to draw.
  bool get hasGeometry => geometries.any((g) => !g.noShow);

  /// True when the shape has an embedded picture reference.
  bool get hasImage => imagePartName != null;

  /// The primary hyperlink to invoke on click (or `null` for none).
  /// Picks the first `isDefault == true`, falling back to row IX=0.
  VsdxHyperlink? get primaryHyperlink {
    if (hyperlinks.isEmpty) return null;
    for (final h in hyperlinks) {
      if (h.isDefault) return h;
    }
    for (final h in hyperlinks) {
      if (h.id == 0) return h;
    }
    return hyperlinks.first;
  }

  /// Convenience: is this shape on at least one of the given layer ids?
  bool isOnAnyLayer(Iterable<int> visibleLayerIds) {
    if (layerMemberIds.isEmpty) return true;
    for (final id in layerMemberIds) {
      if (visibleLayerIds.contains(id)) return true;
    }
    return false;
  }

  /// Functional update. Nullable fields keep their current value when the
  /// corresponding argument is omitted (they cannot be reset to `null` via
  /// `copyWith`; construct a new [VsdxShape] for that rare case).
  VsdxShape copyWith({
    int? id,
    String? name,
    double? pinX,
    double? pinY,
    double? width,
    double? height,
    double? angleRad,
    String? text,
    VsdxRichText? richText,
    List<VsdxShape>? children,
    List<VsdxGeometry>? geometries,
    VsdxFill? fill,
    VsdxLine? line,
    VsdxShadow? shadow,
    VsdxGlow? glow,
    VsdxReflection? reflection,
    List<int>? layerMemberIds,
    bool? is1D,
    double? beginX,
    double? beginY,
    double? endX,
    double? endY,
    bool? straightRoute,
    bool? curved,
    List<Offset2D>? waypoints,
    bool? flipX,
    bool? flipY,
    bool? locked,
    String? imagePartName,
    List<VsdxConnect>? connects,
    List<VsdxHyperlink>? hyperlinks,
    List<VsdxUserProperty>? userProperties,
    List<VsdxUserCell>? userCells,
    String? masterName,
    VsdxShapeKind? shapeKind,
  }) {
    return VsdxShape(
      id: id ?? this.id,
      name: name ?? this.name,
      pinX: pinX ?? this.pinX,
      pinY: pinY ?? this.pinY,
      width: width ?? this.width,
      height: height ?? this.height,
      angleRad: angleRad ?? this.angleRad,
      text: text ?? this.text,
      richText: richText ?? this.richText,
      children: children ?? this.children,
      geometries: geometries ?? this.geometries,
      fill: fill ?? this.fill,
      line: line ?? this.line,
      shadow: shadow ?? this.shadow,
      glow: glow ?? this.glow,
      reflection: reflection ?? this.reflection,
      layerMemberIds: layerMemberIds ?? this.layerMemberIds,
      is1D: is1D ?? this.is1D,
      beginX: beginX ?? this.beginX,
      beginY: beginY ?? this.beginY,
      endX: endX ?? this.endX,
      endY: endY ?? this.endY,
      straightRoute: straightRoute ?? this.straightRoute,
      curved: curved ?? this.curved,
      waypoints: waypoints ?? this.waypoints,
      flipX: flipX ?? this.flipX,
      flipY: flipY ?? this.flipY,
      locked: locked ?? this.locked,
      imagePartName: imagePartName ?? this.imagePartName,
      connects: connects ?? this.connects,
      hyperlinks: hyperlinks ?? this.hyperlinks,
      userProperties: userProperties ?? this.userProperties,
      userCells: userCells ?? this.userCells,
      masterName: masterName ?? this.masterName,
      shapeKind: shapeKind ?? this.shapeKind,
    );
  }

  /// Resize to a new [width]/[height] (and re-centre at [pinX]/[pinY]),
  /// scaling every geometry command so the drawn path fills the new box.
  VsdxShape resizeTo({
    required double pinX,
    required double pinY,
    required double width,
    required double height,
  }) {
    final sx = this.width == 0 ? 1.0 : width / this.width;
    final sy = this.height == 0 ? 1.0 : height / this.height;
    final scaled = <VsdxGeometry>[
      for (final g in geometries)
        VsdxGeometry(
          commands: <VsdxPathCommand>[
            for (final cmd in g.commands) scalePathCommand(cmd, sx, sy),
          ],
          noFill: g.noFill,
          noLine: g.noLine,
          noShow: g.noShow,
        ),
    ];
    return copyWith(
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      geometries: scaled,
    );
  }

  /// Re-position this shape as a straight 1-D line between page points
  /// ([ax],[ay]) and ([bx],[by]); recomputes pin / size / begin-end and the
  /// local geometry. Used by connector re-routing.
  VsdxShape reshapeAsLine({
    required double ax,
    required double ay,
    required double bx,
    required double by,
  }) {
    final left = math.min(ax, bx);
    final right = math.max(ax, bx);
    final bottom = math.min(ay, by);
    final top = math.max(ay, by);
    return copyWith(
      pinX: (left + right) / 2,
      pinY: (bottom + top) / 2,
      width: right - left,
      height: top - bottom,
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
    );
  }

  /// Re-position this shape as a 1-D polyline through page-space [points]
  /// (≥2). Recomputes pin / size / begin-end and the local geometry. Used by
  /// connector re-routing (straight or elbow).
  VsdxShape reshapeAsPolyline(List<Offset2D> points) {
    if (points.length < 2) return this;
    var minX = points.first.x, maxX = points.first.x;
    var minY = points.first.y, maxY = points.first.y;
    for (final p in points) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
    final commands = <VsdxPathCommand>[
      MoveTo(points.first.x - minX, points.first.y - minY),
      for (final p in points.skip(1)) LineTo(p.x - minX, p.y - minY),
    ];
    return copyWith(
      pinX: (minX + maxX) / 2,
      pinY: (minY + maxY) / 2,
      width: maxX - minX,
      height: maxY - minY,
      is1D: true,
      beginX: points.first.x,
      beginY: points.first.y,
      endX: points.last.x,
      endY: points.last.y,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: commands, noFill: true),
      ],
    );
  }

  @override
  String toString() =>
      'VsdxShape(#$id $name, pin=($pinX,$pinY), size=${width}x$height'
      '${text != null ? ', text=${text!.length} chars' : ''}'
      '${children.isNotEmpty ? ', children=${children.length}' : ''}'
      '${geometries.isNotEmpty ? ', geometries=${geometries.length}' : ''}'
      '${is1D ? ', 1D' : ''}'
      '${shapeKind != VsdxShapeKind.normal ? ', $shapeKind' : ''})';
}
