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
import 'sheet_sections.dart';
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
    this.locPinXInches,
    this.locPinYInches,
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
    this.rounded = false,
    this.waypoints = const <Offset2D>[],
    this.flipX = false,
    this.flipY = false,
    this.locked = false,
    this.imagePartName,
    this.foreignType,
    this.foreignCompressionType,
    this.objType,
    this.resizeMode,
    this.eventDblClick,
    this.noAlignBox = false,
    this.shapeSplittable = false,
    this.themeIndex,
    this.quickStyleFillMatrix,
    this.quickStyleLineMatrix,
    this.quickStyleEffectsMatrix,
    this.quickStyleFontMatrix,
    this.isTextEditTarget = false,
    this.dontMoveChildren = false,
    this.selectMode,
    this.displayMode,
    this.connects = const <VsdxConnect>[],
    this.connectionPoints = const <VsdxConnectionPoint>[],
    this.hyperlinks = const <VsdxHyperlink>[],
    this.userProperties = const <VsdxUserProperty>[],
    this.userCells = const <VsdxUserCell>[],
    this.controls = const <VsdxControlRow>[],
    this.scratch = const <VsdxScratchRow>[],
    this.fields = const <VsdxFieldRow>[],
    this.actions = const <VsdxActionRow>[],
    this.masterId,
    this.masterShapeId,
    this.masterName,
    this.lineStyleId,
    this.fillStyleId,
    this.textStyleId,
    this.formulas = const <String, String>{},
    this.connectorProps,
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

  /// `LocPinX` / `LocPinY` — the point *inside* the shape (measured from its
  /// lower-left in local inches) that coincides with [pinX]/[pinY] and is the
  /// rotation centre. `null` ⇒ the shape's centre (`width/2`, `height/2`), the
  /// Visio default. Connectors (and some stencils) pin off-centre — and often
  /// carry signed width/height — so honouring this is required to place their
  /// geometry correctly, matching libvisio. See [effectiveLocPinX].
  final double? locPinXInches;
  final double? locPinYInches;

  /// The effective local pin X, defaulting to the shape centre when unset.
  double get effectiveLocPinX => locPinXInches ?? width / 2;

  /// The effective local pin Y, defaulting to the shape centre when unset.
  double get effectiveLocPinY => locPinYInches ?? height / 2;

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
  /// `false` (default) = orthogonal elbow. The drawn geometry is baked into
  /// ordinary `LineTo`s; the flag itself round-trips via [persistRouteState]
  /// (`User.veStraight`) so re-routing after reopen keeps the choice.
  final bool straightRoute;

  /// When `true`, this connector is drawn as a smooth (drawio "curved") spline
  /// through its route control points instead of a polyline. The smooth curve
  /// is baked into the geometry as a densely-sampled `LineTo` polyline; the
  /// flag round-trips via [persistRouteState] (`User.veCurved`).
  final bool curved;

  /// When `true`, the connector's route corners are **rounded** off with small
  /// fillets (drawio's "Rounded" edge option) instead of drawn as sharp
  /// right-angle bends. Applies to the straight-with-waypoints and orthogonal
  /// elbow routes; ignored when [curved] is set (which is already smooth). The
  /// fillet is baked into geometry; the flag round-trips via
  /// [persistRouteState] (`User.veRounded`).
  final bool rounded;

  /// User-placed interior bend points for a connector, in page inches. When
  /// non-empty the route runs begin → waypoints → end (overriding straight /
  /// elbow). Geometry is baked for display; the list round-trips via
  /// [persistRouteState] (`User.veWaypoints`).
  final List<Offset2D> waypoints;

  /// Fixed connection points (drawio's blue connection points), in
  /// **shape-local inches** (origin bottom-left, Y-up — the same frame as
  /// geometry). A glued connector end that targets index `k` here is written
  /// with `ToPart = 100 + k`; [VsdxPage.connectionPointPage] maps a point to
  /// page coordinates. Round-trips to Visio's `<Section N="Connection">`.
  final List<VsdxConnectionPoint> connectionPoints;

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

  /// `<ForeignData ForeignType="…">` — `Bitmap` / `EnhMetaFile` / `MetaFile` /
  /// `Object`. Inferred from MIME/extension when null on write.
  final String? foreignType;

  /// Optional `CompressionType` on `<ForeignData>` (`JPEG` / `PNG` / …).
  final String? foreignCompressionType;

  /// `ObjType` — Visio object kind (`1` = shape, `2` = connector, …).
  final int? objType;

  /// `ResizeMode` cell (usually `0`).
  final int? resizeMode;

  /// `EventDblClick` cached `V=` (formula lives in [formulas]).
  final String? eventDblClick;

  /// `NoAlignBox` — hide the alignment box (common on connectors).
  final bool noAlignBox;

  /// `ShapeSplittable` — connector may be split by overlapping shapes.
  final bool shapeSplittable;

  /// `ThemeIndex` — document theme slot (0 = default / none).
  final int? themeIndex;

  /// QuickStyle matrix cells (`QuickStyleFillMatrix` / Line / Effects / Font).
  final int? quickStyleFillMatrix;
  final int? quickStyleLineMatrix;
  final int? quickStyleEffectsMatrix;
  final int? quickStyleFontMatrix;

  /// `IsTextEditTarget` — group members that own the text edit target.
  final bool isTextEditTarget;

  /// `DontMoveChildren` — keep children fixed when the group moves.
  final bool dontMoveChildren;

  /// `SelectMode` / `DisplayMode` — group selection / display behaviour.
  final int? selectMode;
  final int? displayMode;

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

  /// `<Section N="Control">` rows — text/connector handles (`Controls.*`).
  final List<VsdxControlRow> controls;

  /// `<Section N="Scratch">` rows — parametric intermediates (`Scratch.X1`).
  final List<VsdxScratchRow> scratch;

  /// `<Section N="Field">` rows — dynamic text (`<fld IX>`).
  final List<VsdxFieldRow> fields;

  /// `<Section N="Actions">` rows — context-menu actions.
  final List<VsdxActionRow> actions;

  /// `Master="N"` attribute on the shape element (`null` when absent).
  /// Written back on rebuild so stencil instances keep their master link.
  final int? masterId;

  /// `MasterShape="N"` — nested instance of a master sub-shape.
  final int? masterShapeId;

  /// `Master.NameU` of the master this shape was instantiated from
  /// (`null` when the shape carries no `Master` attribute or its master
  /// went missing). Useful for container/swimlane detection and stencil
  /// browsing UI.
  final String? masterName;

  /// ShapeSheet style inheritance attributes (`LineStyle` / `FillStyle` /
  /// `TextStyle`) — stylesheet row ids written back on rebuild.
  final int? lineStyleId;
  final int? fillStyleId;
  final int? textStyleId;

  /// Parametric `F=` values for XForm / 1-D / trigger cells (`PinX`, `BeginX`,
  /// `BegTrigger`, …). Required so group rebuild keeps PAR(PNT…) glue.
  final Map<String, String> formulas;

  /// Connector layout dynamics (`GlueType`, `ConFixedCode`, …).
  final VsdxConnectorProps? connectorProps;

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
    double? locPinXInches,
    double? locPinYInches,
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
    bool? rounded,
    List<Offset2D>? waypoints,
    List<VsdxConnectionPoint>? connectionPoints,
    bool? flipX,
    bool? flipY,
    bool? locked,
    String? imagePartName,
    String? foreignType,
    String? foreignCompressionType,
    int? objType,
    int? resizeMode,
    String? eventDblClick,
    bool? noAlignBox,
    bool? shapeSplittable,
    int? themeIndex,
    int? quickStyleFillMatrix,
    int? quickStyleLineMatrix,
    int? quickStyleEffectsMatrix,
    int? quickStyleFontMatrix,
    bool? isTextEditTarget,
    bool? dontMoveChildren,
    int? selectMode,
    int? displayMode,
    List<VsdxConnect>? connects,
    List<VsdxHyperlink>? hyperlinks,
    List<VsdxUserProperty>? userProperties,
    List<VsdxUserCell>? userCells,
    List<VsdxControlRow>? controls,
    List<VsdxScratchRow>? scratch,
    List<VsdxFieldRow>? fields,
    List<VsdxActionRow>? actions,
    int? masterId,
    int? masterShapeId,
    String? masterName,
    int? lineStyleId,
    int? fillStyleId,
    int? textStyleId,
    Map<String, String>? formulas,
    VsdxConnectorProps? connectorProps,
    VsdxShapeKind? shapeKind,
  }) {
    return VsdxShape(
      id: id ?? this.id,
      name: name ?? this.name,
      pinX: pinX ?? this.pinX,
      pinY: pinY ?? this.pinY,
      width: width ?? this.width,
      height: height ?? this.height,
      locPinXInches: locPinXInches ?? this.locPinXInches,
      locPinYInches: locPinYInches ?? this.locPinYInches,
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
      rounded: rounded ?? this.rounded,
      waypoints: waypoints ?? this.waypoints,
      connectionPoints: connectionPoints ?? this.connectionPoints,
      flipX: flipX ?? this.flipX,
      flipY: flipY ?? this.flipY,
      locked: locked ?? this.locked,
      imagePartName: imagePartName ?? this.imagePartName,
      foreignType: foreignType ?? this.foreignType,
      foreignCompressionType:
          foreignCompressionType ?? this.foreignCompressionType,
      objType: objType ?? this.objType,
      resizeMode: resizeMode ?? this.resizeMode,
      eventDblClick: eventDblClick ?? this.eventDblClick,
      noAlignBox: noAlignBox ?? this.noAlignBox,
      shapeSplittable: shapeSplittable ?? this.shapeSplittable,
      themeIndex: themeIndex ?? this.themeIndex,
      quickStyleFillMatrix: quickStyleFillMatrix ?? this.quickStyleFillMatrix,
      quickStyleLineMatrix: quickStyleLineMatrix ?? this.quickStyleLineMatrix,
      quickStyleEffectsMatrix:
          quickStyleEffectsMatrix ?? this.quickStyleEffectsMatrix,
      quickStyleFontMatrix: quickStyleFontMatrix ?? this.quickStyleFontMatrix,
      isTextEditTarget: isTextEditTarget ?? this.isTextEditTarget,
      dontMoveChildren: dontMoveChildren ?? this.dontMoveChildren,
      selectMode: selectMode ?? this.selectMode,
      displayMode: displayMode ?? this.displayMode,
      connects: connects ?? this.connects,
      hyperlinks: hyperlinks ?? this.hyperlinks,
      userProperties: userProperties ?? this.userProperties,
      userCells: userCells ?? this.userCells,
      controls: controls ?? this.controls,
      scratch: scratch ?? this.scratch,
      fields: fields ?? this.fields,
      actions: actions ?? this.actions,
      masterId: masterId ?? this.masterId,
      masterShapeId: masterShapeId ?? this.masterShapeId,
      masterName: masterName ?? this.masterName,
      lineStyleId: lineStyleId ?? this.lineStyleId,
      fillStyleId: fillStyleId ?? this.fillStyleId,
      textStyleId: textStyleId ?? this.textStyleId,
      formulas: formulas ?? this.formulas,
      connectorProps: connectorProps ?? this.connectorProps,
      shapeKind: shapeKind ?? this.shapeKind,
    );
  }

  /// User-cell names that carry drawio-style connector route state across
  /// save → reopen. Geometry alone is already baked; these restore editability.
  static const String userRouteStraight = 'veStraight';
  static const String userRouteCurved = 'veCurved';
  static const String userRouteRounded = 'veRounded';
  static const String userRouteWaypoints = 'veWaypoints';

  /// User-cell flag: draw.io-style collapsed container / swimlane. When set to
  /// `'1'`, children stay in the model but are not painted or hit-tested.
  static const String userCollapsed = 'veCollapsed';

  /// Stored expanded height (inches) while [collapsed], so unfold restores size.
  static const String userExpandedHeight = 'veExpandedHeight';

  static const Set<String> _routeUserCellNames = {
    userRouteStraight,
    userRouteCurved,
    userRouteRounded,
    userRouteWaypoints,
  };

  /// Whether this structural container is collapsed (children hidden).
  bool get collapsed {
    for (final c in userCells) {
      if (c.name == userCollapsed) return c.value == '1';
    }
    return false;
  }

  /// Expanded height stored when the shape was last folded, if any.
  double? get storedExpandedHeight {
    for (final c in userCells) {
      if (c.name == userExpandedHeight) {
        return double.tryParse(c.value ?? '');
      }
    }
    return null;
  }

  /// Set / clear the collapsed flag via [userCollapsed]. Round-trips through
  /// the writer as a `User` cell. Prefer [fold] / [unfold] when also shrinking
  /// the header height (draw.io behaviour).
  VsdxShape withCollapsed(bool value) {
    final others = <VsdxUserCell>[
      for (final c in userCells)
        if (c.name != userCollapsed) c,
    ];
    if (!value) {
      if (others.length == userCells.length) return this;
      return copyWith(userCells: others);
    }
    return copyWith(
      userCells: <VsdxUserCell>[
        ...others,
        const VsdxUserCell(name: userCollapsed, value: '1'),
      ],
    );
  }

  /// Header height used when folding a structural container (inches).
  static double collapsedHeaderHeight(VsdxShape s) {
    if (s.shapeKind == VsdxShapeKind.swimlane) {
      return (s.height * 0.2).clamp(0.4, 0.65);
    }
    return (s.height * 0.18).clamp(0.35, math.max(0.35, s.height));
  }

  /// Fold this container: hide children, shrink height to the title band, keep
  /// the **top** edge fixed (Y-up). Stores the previous height for [unfold].
  VsdxShape fold() {
    if (collapsed) return this;
    final expandedH = height;
    final newH = collapsedHeaderHeight(this);
    final top = pinY + height / 2;
    final newPinY = top - newH / 2;
    final others = <VsdxUserCell>[
      for (final c in userCells)
        if (c.name != userCollapsed && c.name != userExpandedHeight) c,
    ];
    final flagged = copyWith(
      userCells: <VsdxUserCell>[
        ...others,
        const VsdxUserCell(name: userCollapsed, value: '1'),
        VsdxUserCell(name: userExpandedHeight, value: '$expandedH'),
      ],
    );
    if ((newH - expandedH).abs() < 1e-6) return flagged;
    return flagged.resizeTo(
      pinX: pinX,
      pinY: newPinY,
      width: width,
      height: newH,
    );
  }

  /// Unfold this container: restore height from [storedExpandedHeight] (or keep
  /// current), show children again, keep the **top** edge fixed.
  VsdxShape unfold() {
    if (!collapsed) return this;
    final restoreH = storedExpandedHeight ?? height;
    final top = pinY + height / 2;
    final newPinY = top - restoreH / 2;
    final others = <VsdxUserCell>[
      for (final c in userCells)
        if (c.name != userCollapsed && c.name != userExpandedHeight) c,
    ];
    final cleared = copyWith(userCells: others);
    if ((restoreH - height).abs() < 1e-6) return cleared;
    return cleared.resizeTo(
      pinX: pinX,
      pinY: newPinY,
      width: width,
      height: restoreH,
    );
  }

  /// Mirror [straightRoute] / [curved] / [rounded] / [waypoints] into
  /// [userCells] so the writer emits them. No-op for non-connectors with no
  /// route state. Safe to call repeatedly.
  VsdxShape persistRouteState() {
    if (!is1D) return this;
    final others = <VsdxUserCell>[
      for (final c in userCells)
        if (!_routeUserCellNames.contains(c.name)) c,
    ];
    final add = <VsdxUserCell>[
      if (straightRoute)
        const VsdxUserCell(name: userRouteStraight, value: '1'),
      if (curved) const VsdxUserCell(name: userRouteCurved, value: '1'),
      if (rounded) const VsdxUserCell(name: userRouteRounded, value: '1'),
      if (waypoints.isNotEmpty)
        VsdxUserCell(
          name: userRouteWaypoints,
          value: [
            for (final p in waypoints) '${p.x},${p.y}',
          ].join(';'),
        ),
    ];
    final hadRoute =
        userCells.any((c) => _routeUserCellNames.contains(c.name));
    if (add.isEmpty && !hadRoute) return this;
    return copyWith(userCells: <VsdxUserCell>[...others, ...add]);
  }

  /// Restore [straightRoute] / [curved] / [rounded] / [waypoints] from
  /// [userCells] written by [persistRouteState]. No-op when none are present.
  VsdxShape restoreRouteState() {
    if (userCells.isEmpty) return this;
    bool? straight;
    bool? curve;
    bool? round;
    List<Offset2D>? wps;
    for (final c in userCells) {
      switch (c.name) {
        case userRouteStraight:
          straight = c.value == '1';
        case userRouteCurved:
          curve = c.value == '1';
        case userRouteRounded:
          round = c.value == '1';
        case userRouteWaypoints:
          wps = _parseRouteWaypoints(c.value);
      }
    }
    if (straight == null && curve == null && round == null && wps == null) {
      return this;
    }
    return copyWith(
      straightRoute: straight ?? false,
      curved: curve ?? false,
      rounded: round ?? false,
      waypoints: wps ?? const <Offset2D>[],
    );
  }

  static List<Offset2D>? _parseRouteWaypoints(String? raw) {
    if (raw == null || raw.isEmpty) return const <Offset2D>[];
    final out = <Offset2D>[];
    for (final part in raw.split(';')) {
      final comma = part.indexOf(',');
      if (comma <= 0) continue;
      final x = double.tryParse(part.substring(0, comma).trim());
      final y = double.tryParse(part.substring(comma + 1).trim());
      if (x == null || y == null) continue;
      out.add(Offset2D(x, y));
    }
    return out;
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
        g.copyWith(
          commands: <VsdxPathCommand>[
            for (final cmd in g.commands) scalePathCommand(cmd, sx, sy),
          ],
          // Keep parametric Geometry F= (Scratch.X1 / Width*) across resize;
          // copyWith preserves ix / rowIndices / deletedRowIndices so master
          // inheritance stays stable after a rebuild.
          commandFormulas: g.commandFormulas,
        ),
    ];
    // Keep LocPin at the same *relative* position inside the box so a
    // centre-pinned shape stays centre-pinned after resize (and an off-centre
    // LocPin scales with the box). When LocPin was unset (implicit centre),
    // leave it unset so the writer / renderer keep defaulting to width/2.
    final newLocPinX = locPinXInches == null
        ? null
        : (this.width == 0 ? locPinXInches : locPinXInches! * sx);
    final newLocPinY = locPinYInches == null
        ? null
        : (this.height == 0 ? locPinYInches : locPinYInches! * sy);
    return copyWith(
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      locPinXInches: newLocPinX,
      locPinYInches: newLocPinY,
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
