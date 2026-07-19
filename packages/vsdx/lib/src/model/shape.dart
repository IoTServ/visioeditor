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
import '../parser/formula.dart';

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
    this.imgOffsetXInches = 0,
    this.imgOffsetYInches = 0,
    this.imgWidthInches,
    this.imgHeightInches,
    this.imageTransparency = 0,
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

  /// Image Properties `ImgOffsetX` / `ImgOffsetY` — placement of the bitmap
  /// inside the Foreign shape (local inches, Y-up). Default `(0, 0)`.
  final double imgOffsetXInches;
  final double imgOffsetYInches;

  /// Image Properties `ImgWidth` / `ImgHeight`. `null` ⇒ fill the shape
  /// (`Width` / `Height`). Crop/pan use values that differ from the frame.
  final double? imgWidthInches;
  final double? imgHeightInches;

  /// Image Properties `Transparency` (0 = opaque … 1 = invisible).
  final double imageTransparency;

  /// Effective image width inside the Foreign frame.
  double get effectiveImgWidth => imgWidthInches ?? width;

  /// Effective image height inside the Foreign frame.
  double get effectiveImgHeight => imgHeightInches ?? height;

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

  /// Glueable dynamic connector (`ObjType` unset or `2`). Freehand ink is
  /// also 1-D but uses `ObjType=1` (AABB-local geometry) and must not go
  /// through waypoint / Begin–End reshape / glue paths.
  bool get isGlueableConnector => is1D && (objType == null || objType == 2);

  /// Freehand / scribble stroke (`ObjType=1`).
  bool get isInk => is1D && objType == 1;

  /// Refresh Begin/End from the first and last ink geometry vertices after
  /// Pin / Size / Angle / Flip changes. Begin/End stay in the same parent
  /// (or page) frame as [pinX]/[pinY] so Visio/Edraw selection matches paint.
  VsdxShape syncInkEndpoints() {
    if (!isInk) return this;
    Offset2D? first;
    Offset2D? last;
    for (final g in geometries) {
      if (g.noShow) continue;
      for (final c in g.commands) {
        if (c is MoveTo) {
          first ??= Offset2D(c.x, c.y);
          last = Offset2D(c.x, c.y);
        } else if (c is LineTo) {
          last = Offset2D(c.x, c.y);
          first ??= last;
        }
      }
      if (first != null && last != null) break;
    }
    if (first == null || last == null) return this;
    Offset2D toParent(Offset2D local) {
      var dx = local.x - effectiveLocPinX;
      var dy = local.y - effectiveLocPinY;
      if (flipX) dx = -dx;
      if (flipY) dy = -dy;
      if (angleRad != 0) {
        final cosA = math.cos(angleRad), sinA = math.sin(angleRad);
        final rx = dx * cosA - dy * sinA;
        final ry = dx * sinA + dy * cosA;
        dx = rx;
        dy = ry;
      }
      return Offset2D(pinX + dx, pinY + dy);
    }

    final b = toParent(first);
    final e = toParent(last);
    return copyWith(beginX: b.x, beginY: b.y, endX: e.x, endY: e.y);
  }

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
    double? imgOffsetXInches,
    double? imgOffsetYInches,
    double? imgWidthInches,
    double? imgHeightInches,
    double? imageTransparency,
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
      imgOffsetXInches: imgOffsetXInches ?? this.imgOffsetXInches,
      imgOffsetYInches: imgOffsetYInches ?? this.imgOffsetYInches,
      imgWidthInches: imgWidthInches ?? this.imgWidthInches,
      imgHeightInches: imgHeightInches ?? this.imgHeightInches,
      imageTransparency: imageTransparency ?? this.imageTransparency,
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

  /// Deep-clone this shape (and every descendant) with freshly allocated ids
  /// from [allocId]. Used by duplicate / paste / directional-clone so nested
  /// group members never collide with the originals on the same page.
  ///
  /// When [idMap] is provided it is filled with `oldId → newId` for the whole
  /// subtree. Cross-sheet `Sheet.n!` formulas are rewritten via that map.
  VsdxShape withRemappedIds(
    int Function() allocId, {
    double? pinX,
    double? pinY,
    Map<int, int>? idMap,
  }) {
    final map = idMap ?? <int, int>{};
    VsdxShape assignIds(VsdxShape s, {double? px, double? py}) {
      final newId = allocId();
      map[s.id] = newId;
      final defaultName = 'Sheet.${s.id}';
      return s.copyWith(
        id: newId,
        name: s.name == defaultName ? 'Sheet.$newId' : s.name,
        pinX: px ?? s.pinX,
        pinY: py ?? s.pinY,
        children: <VsdxShape>[
          for (final c in s.children) assignIds(c),
        ],
      );
    }

    final cloned = assignIds(this, px: pinX, py: pinY);
    return rewriteSheetRefsInTree(cloned, map);
  }

  /// Rewrite `Sheet.n!` formulas / collapsed-glue payloads in [s] via [idMap].
  /// Used after multi-root paste so cross-shape XFTRIGGER refs resolve once
  /// every clone id is known.
  static VsdxShape rewriteSheetRefsInTree(
    VsdxShape s,
    Map<int, int> idMap,
  ) =>
      _rewriteSheetRefsInTree(s, idMap);

  static VsdxShape _rewriteSheetRefsInTree(
    VsdxShape s,
    Map<int, int> idMap,
  ) {
    final newChildren = <VsdxShape>[
      for (final c in s.children) _rewriteSheetRefsInTree(c, idMap),
    ];
    Map<String, String>? formulas;
    if (s.formulas.isNotEmpty) {
      final next = <String, String>{};
      var changed = false;
      for (final e in s.formulas.entries) {
        final rewritten = rewriteSheetRefs(e.value, idMap);
        next[e.key] = rewritten;
        if (rewritten != e.value) changed = true;
      }
      if (changed) formulas = next;
    }
    List<VsdxUserCell>? userCells;
    if (s.userCells.isNotEmpty) {
      final next = <VsdxUserCell>[];
      var changed = false;
      for (final c in s.userCells) {
        if (c.name == userCollapsedGlue && c.value != null) {
          final rewritten = _remapCollapsedGlueValue(c.value!, idMap);
          next.add(rewritten == c.value
              ? c
              : VsdxUserCell(name: c.name, value: rewritten));
          if (rewritten != c.value) changed = true;
        } else {
          next.add(c);
        }
      }
      if (changed) userCells = next;
    }
    var childrenChanged = false;
    for (var i = 0; i < newChildren.length; i++) {
      if (!identical(newChildren[i], s.children[i])) {
        childrenChanged = true;
        break;
      }
    }
    if (formulas == null && userCells == null && !childrenChanged) return s;
    return s.copyWith(
      formulas: formulas,
      userCells: userCells,
      children: childrenChanged ? newChildren : null,
    );
  }

  /// Remap `fromSheetId` / `toSheetId` inside a [userCollapsedGlue] payload.
  /// Rows whose either end is outside [idMap] are dropped so a cloned host
  /// cannot resurrect glue onto shapes that were not copied.
  static String _remapCollapsedGlueValue(String raw, Map<int, int> idMap) {
    if (raw.isEmpty) return raw;
    if (idMap.isEmpty) return '';
    final out = <String>[];
    var changed = false;
    for (final line in raw.split('\n')) {
      if (line.isEmpty) continue;
      final p = line.split('\t');
      if (p.length < 5) {
        changed = true;
        continue;
      }
      final fromId = int.tryParse(p[0]);
      final toId = int.tryParse(p[3]);
      if (fromId == null || toId == null) {
        changed = true;
        continue;
      }
      final nf = idMap[fromId];
      final nt = idMap[toId];
      if (nf == null || nt == null) {
        changed = true;
        continue;
      }
      if (nf != fromId || nt != toId) changed = true;
      p[0] = '$nf';
      p[3] = '$nt';
      out.add(p.join('\t'));
    }
    if (!changed && out.length == raw.split('\n').where((l) => l.isNotEmpty).length) {
      return raw;
    }
    return out.join('\n');
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

  /// User-cell flag: paint this shape's label along an arc inside the text
  /// block (editor "Curved Text"). Round-trips via `User.veCurvedText`.
  static const String userCurvedText = 'veCurvedText';

  /// Stored expanded height (inches) while [collapsed], so unfold restores size.
  static const String userExpandedHeight = 'veExpandedHeight';

  /// Serialized [VsdxConnect] rows detached while [collapsed] so unfold (and
  /// undo) can restore glue to hidden children. Editor-owned; not used by Visio.
  static const String userCollapsedGlue = 'veCollapsedGlue';

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

  /// Whether the label is painted along an arc (editor Curved Text).
  bool get curvedText {
    for (final c in userCells) {
      if (c.name == userCurvedText) return c.value == '1';
    }
    return false;
  }

  /// Set / clear Curved Text via [userCurvedText]. Round-trips as a `User` cell.
  VsdxShape withCurvedText(bool value) {
    final others = <VsdxUserCell>[
      for (final c in userCells)
        if (c.name != userCurvedText) c,
    ];
    if (!value) {
      if (others.length == userCells.length) return this;
      return copyWith(userCells: others);
    }
    return copyWith(
      userCells: <VsdxUserCell>[
        ...others,
        const VsdxUserCell(name: userCurvedText, value: '1'),
      ],
    );
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
    // Freehand ink is 1-D but must not grow connector route User cells.
    if (!isGlueableConnector) return this;
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
  /// Then re-evaluates local ShapeSheet formulas (Connection / LocPin /
  /// Scratch / Controls / User) that depend on Width/Height/Pin*.
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
    // [recalculateLocalFormulas] may then override from LocPinX/Y formulas.
    final newLocPinX = locPinXInches == null
        ? null
        : (this.width == 0 ? locPinXInches : locPinXInches! * sx);
    final newLocPinY = locPinYInches == null
        ? null
        : (this.height == 0 ? locPinYInches : locPinYInches! * sy);
    // Absolute Connection / Control cells (no Width*/Height* F=) scale with
    // the box so VSD imports and hand-placed glue points stay proportional;
    // formula-driven cells keep their V and are refreshed by recalc below.
    bool hasF(String? f) => f != null && f.isNotEmpty;
    final scaledCPs = ((sx - 1).abs() < 1e-12 && (sy - 1).abs() < 1e-12)
        ? connectionPoints
        : <VsdxConnectionPoint>[
            for (final p in connectionPoints)
              p.copyWith(
                x: hasF(p.xFormula) ? p.x : p.x * sx,
                y: hasF(p.yFormula) ? p.y : p.y * sy,
              ),
          ];
    final scaledControls = ((sx - 1).abs() < 1e-12 && (sy - 1).abs() < 1e-12)
        ? controls
        : <VsdxControlRow>[
            for (final r in controls)
              r.copyWith(
                x: hasF(r.xFormula) ? r.x : r.x * sx,
                y: hasF(r.yFormula) ? r.y : r.y * sy,
                dynX: hasF(r.dynXFormula) ? r.dynX : r.dynX * sx,
                dynY: hasF(r.dynYFormula) ? r.dynY : r.dynY * sy,
                conX: hasF(r.conXFormula) ? r.conX : r.conX * sx,
                conY: hasF(r.conYFormula) ? r.conY : r.conY * sy,
              ),
          ];
    // Absolute Scratch.X/Y (common VSD intermediate points) scale with the box;
    // A–D often hold angles / flags and stay put when formula-less.
    final scaledScratch = ((sx - 1).abs() < 1e-12 && (sy - 1).abs() < 1e-12)
        ? scratch
        : <VsdxScratchRow>[
            for (final r in scratch)
              r.copyWith(
                x: hasF(r.xFormula) ? r.x : r.x * sx,
                y: hasF(r.yFormula) ? r.y : r.y * sy,
              ),
          ];
    // Absolute text-block cells (no Width*/Height* formula) scale with the box
    // so custom TxtPin/TxtWidth placement stays proportional after resize.
    final block = richText.textBlock;
    final scaledBlock = ((sx - 1).abs() < 1e-12 && (sy - 1).abs() < 1e-12)
        ? block
        : block.copyWith(
            pinXInches: block.pinXInches == null
                ? null
                : block.pinXInches! * sx,
            pinYInches: block.pinYInches == null
                ? null
                : block.pinYInches! * sy,
            locPinXInches: block.locPinXInches == null
                ? null
                : block.locPinXInches! * sx,
            locPinYInches: block.locPinYInches == null
                ? null
                : block.locPinYInches! * sy,
            widthInches: block.widthInches == null
                ? null
                : block.widthInches! * sx,
            heightInches: block.heightInches == null
                ? null
                : block.heightInches! * sy,
          );
    return copyWith(
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      locPinXInches: newLocPinX,
      locPinYInches: newLocPinY,
      geometries: scaled,
      connectionPoints: scaledCPs,
      controls: scaledControls,
      scratch: scaledScratch,
      richText: identical(scaledBlock, block)
          ? richText
          : richText.copyWith(textBlock: scaledBlock),
    ).recalculateLocalFormulas().syncInkEndpoints();
  }

  /// Look up a Transform / 1-D endpoint cell for cross-sheet `Sheet.n!Cell`
  /// resolution. Returns `null` for unsupported cell names.
  double? lookupSheetCell(String cell) {
    switch (cell.toUpperCase()) {
      case 'PINX':
        return pinX;
      case 'PINY':
        return pinY;
      case 'WIDTH':
        return width;
      case 'HEIGHT':
        return height;
      case 'ANGLE':
        return angleRad;
      case 'LOCPINX':
        return locPinXInches;
      case 'LOCPINY':
        return locPinYInches;
      case 'BEGINX':
        return beginX;
      case 'BEGINY':
        return beginY;
      case 'ENDX':
        return endX;
      case 'ENDY':
        return endY;
      default:
        return null;
    }
  }

  /// Resolve a local ShapeSheet ref (`Controls.*` / `User.*` / `Prop.*` /
  /// transform cells) for SETATREF recalc / redirect.
  double? lookupLocalRef(String ref) {
    final t = ref.trim();
    if (t.isEmpty) return null;

    final ctrl = RegExp(
      r'^Controls\.([A-Za-z_][\w]*)(?:\.([A-Za-z_][\w]*))?$',
      caseSensitive: false,
    ).firstMatch(t);
    if (ctrl != null) {
      final name = ctrl.group(1)!;
      VsdxControlRow? row;
      for (final c in controls) {
        if (c.name == name) {
          row = c;
          break;
        }
      }
      if (row == null) return null;
      final cell = ctrl.group(2)?.toUpperCase();
      if (cell == null) return row.x;
      return switch (cell) {
        'Y' || 'YDYN' || 'DYNY' => row.y,
        'X' || 'XDYN' || 'DYNX' => row.x,
        'XCON' || 'CONX' => row.conX,
        'YCON' || 'CONY' => row.conY,
        _ => row.x,
      };
    }

    final user = RegExp(
      r'^User\.([A-Za-z_][\w]*)$',
      caseSensitive: false,
    ).firstMatch(t);
    if (user != null) {
      final name = user.group(1)!;
      for (final c in userCells) {
        if (c.name == name) return _parseNumericCache(c.value);
      }
      return null;
    }

    final prop = RegExp(
      r'^Prop\.([A-Za-z_][\w]*)$',
      caseSensitive: false,
    ).firstMatch(t);
    if (prop != null) {
      final name = prop.group(1)!;
      for (final p in userProperties) {
        if (p.name == name) return _parseNumericCache(p.value);
      }
      return null;
    }

    return lookupSheetCell(t);
  }

  static double? _parseNumericCache(String? raw) {
    if (raw == null) return null;
    final t = raw.trim();
    if (t.isEmpty) return null;
    // Strip a trailing Visio unit token when present (`1.25 in`).
    final m = RegExp(r'^([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)').firstMatch(t);
    if (m == null) return null;
    return double.tryParse(m.group(1)!);
  }

  static String _formatNumericCache(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e15) return '${v.toInt()}';
    return '$v';
  }

  /// Write [value] into a local `Controls.*` / `User.*` / `Prop.*` ref.
  VsdxShape writeLocalRef(String ref, double value) {
    final t = ref.trim();
    final ctrl = RegExp(
      r'^Controls\.([A-Za-z_][\w]*)(?:\.([A-Za-z_][\w]*))?$',
      caseSensitive: false,
    ).firstMatch(t);
    if (ctrl != null) {
      final name = ctrl.group(1)!;
      final cell = ctrl.group(2)?.toUpperCase();
      final out = <VsdxControlRow>[];
      var touched = false;
      for (final c in controls) {
        if (c.name != name) {
          out.add(c);
          continue;
        }
        touched = true;
        if (cell == null ||
            cell == 'X' ||
            cell == 'XDYN' ||
            cell == 'DYNX') {
          out.add(c.copyWith(x: value));
        } else if (cell == 'Y' ||
            cell == 'YDYN' ||
            cell == 'DYNY') {
          out.add(c.copyWith(y: value));
        } else if (cell == 'XCON' || cell == 'CONX') {
          out.add(c.copyWith(conX: value));
        } else if (cell == 'YCON' || cell == 'CONY') {
          out.add(c.copyWith(conY: value));
        } else {
          out.add(c.copyWith(x: value));
        }
      }
      return touched ? copyWith(controls: out) : this;
    }

    final user = RegExp(
      r'^User\.([A-Za-z_][\w]*)$',
      caseSensitive: false,
    ).firstMatch(t);
    if (user != null) {
      final name = user.group(1)!;
      final asStr = _formatNumericCache(value);
      final out = <VsdxUserCell>[];
      var found = false;
      for (final c in userCells) {
        if (c.name != name) {
          out.add(c);
          continue;
        }
        found = true;
        out.add(c.copyWith(value: asStr));
      }
      if (!found) {
        out.add(VsdxUserCell(name: name, value: asStr));
      }
      return copyWith(userCells: out);
    }

    final prop = RegExp(
      r'^Prop\.([A-Za-z_][\w]*)$',
      caseSensitive: false,
    ).firstMatch(t);
    if (prop != null) {
      final name = prop.group(1)!;
      final asStr = _formatNumericCache(value);
      final out = <VsdxUserProperty>[];
      var found = false;
      for (final p in userProperties) {
        if (p.name != name) {
          out.add(p);
          continue;
        }
        found = true;
        out.add(p.copyWith(value: asStr));
      }
      if (!found) {
        out.add(VsdxUserProperty(name: name, value: asStr));
      }
      return copyWith(userProperties: out);
    }

    return this;
  }

  /// `F=` on a local `Controls.*` / `User.*` / `Prop.*` cell, if any.
  String? formulaOfLocalRef(String ref) {
    final t = ref.trim();
    final ctrl = RegExp(
      r'^Controls\.([A-Za-z_][\w]*)(?:\.([A-Za-z_][\w]*))?$',
      caseSensitive: false,
    ).firstMatch(t);
    if (ctrl != null) {
      final name = ctrl.group(1)!;
      VsdxControlRow? row;
      for (final c in controls) {
        if (c.name == name) {
          row = c;
          break;
        }
      }
      if (row == null) return null;
      final cell = ctrl.group(2)?.toUpperCase();
      if (cell == null ||
          cell == 'X' ||
          cell == 'XDYN' ||
          cell == 'DYNX') {
        return row.xFormula;
      }
      if (cell == 'Y' || cell == 'YDYN' || cell == 'DYNY') {
        return row.yFormula;
      }
      if (cell == 'XCON' || cell == 'CONX') return row.conXFormula;
      if (cell == 'YCON' || cell == 'CONY') return row.conYFormula;
      return row.xFormula;
    }

    final user = RegExp(
      r'^User\.([A-Za-z_][\w]*)$',
      caseSensitive: false,
    ).firstMatch(t);
    if (user != null) {
      final name = user.group(1)!;
      for (final c in userCells) {
        if (c.name == name) return c.valueFormula;
      }
      return null;
    }

    final prop = RegExp(
      r'^Prop\.([A-Za-z_][\w]*)$',
      caseSensitive: false,
    ).firstMatch(t);
    if (prop != null) {
      final name = prop.group(1)!;
      for (final p in userProperties) {
        if (p.name == name) return p.valueFormula;
      }
      return null;
    }

    return null;
  }

  /// Redirect incoming cell values through SETATREF / SETATREFEVAL formulas
  /// (e.g. after the editor moves TxtPin). Writes the transformed value into
  /// the referenced Controls / User / Prop cell, following SETATREF chains.
  VsdxShape applySetAtRefInputs(Map<String, double> incomingByCell) {
    if (incomingByCell.isEmpty) return this;
    final locals = <String, double>{
      'Width': width,
      'Height': height,
      'PinX': pinX,
      'PinY': pinY,
      'Angle': angleRad,
      if (locPinXInches != null) 'LocPinX': locPinXInches!,
      if (locPinYInches != null) 'LocPinY': locPinYInches!,
      if (beginX != null) 'BeginX': beginX!,
      if (beginY != null) 'BeginY': beginY!,
      if (endX != null) 'EndX': endX!,
      if (endY != null) 'EndY': endY!,
    };
    var next = this;
    var touched = false;
    for (final e in incomingByCell.entries) {
      final formula = next.formulas[e.key];
      final redirect = computeSetAtRefRedirect(
        formula,
        e.value,
        locals: locals,
        cellLookup: next.lookupLocalRef,
        formulaOfRef: next.formulaOfLocalRef,
      );
      if (redirect == null) continue;
      final written = next.writeLocalRef(redirect.reference, redirect.value);
      if (!identical(written, next)) {
        next = written;
        touched = true;
      }
    }
    return touched ? next : this;
  }

  /// All `F=` strings on this shape that may contain `Sheet.n!` refs.
  Iterable<String> get formulaSources sync* {
    yield* formulas.values;
    for (final p in connectionPoints) {
      final xf = p.xFormula;
      final yf = p.yFormula;
      if (xf != null && xf.isNotEmpty) yield xf;
      if (yf != null && yf.isNotEmpty) yield yf;
    }
    for (final r in scratch) {
      for (final f in <String?>[
        r.xFormula,
        r.yFormula,
        r.aFormula,
        r.bFormula,
        r.cFormula,
        r.dFormula,
      ]) {
        if (f != null && f.isNotEmpty) yield f;
      }
    }
    for (final r in controls) {
      for (final f in <String?>[
        r.xFormula,
        r.yFormula,
        r.dynXFormula,
        r.dynYFormula,
        r.conXFormula,
        r.conYFormula,
      ]) {
        if (f != null && f.isNotEmpty) yield f;
      }
    }
    for (final c in userCells) {
      final f = c.valueFormula;
      if (f != null && f.isNotEmpty) yield f;
    }
    for (final g in geometries) {
      for (final row in g.commandFormulas) {
        for (final f in row.values) {
          if (f.isNotEmpty) yield f;
        }
      }
    }
  }

  /// Whether any formula on this shape references a sheet id in [ids].
  bool referencesAnySheet(Set<int> ids) {
    if (ids.isEmpty) return false;
    for (final f in formulaSources) {
      if (formulaReferencesAnySheet(f, ids)) return true;
    }
    return false;
  }

  /// Re-evaluate local ShapeSheet formulas against this shape's current
  /// Width / Height / Pin* / Begin* / End* / Angle (and Scratch.* after the
  /// Scratch section is refreshed) and write updated cache values. Formulas
  /// that cannot be resolved (`SETATREF`, unresolved cross-sheet, theme, …)
  /// keep their previous `V` and retain `F=`.
  ///
  /// Pass [sheetLookup] to resolve `Sheet.n!Cell` against sibling shapes
  /// (see [VsdxPage.recalculateFormulas]).
  VsdxShape recalculateLocalFormulas({
    double? Function(int sheetId, String cell)? sheetLookup,
  }) {
    final locals = <String, double>{
      'Width': width,
      'Height': height,
      'PinX': pinX,
      'PinY': pinY,
      'Angle': angleRad,
      if (locPinXInches != null) 'LocPinX': locPinXInches!,
      if (locPinYInches != null) 'LocPinY': locPinYInches!,
      if (beginX != null) 'BeginX': beginX!,
      if (beginY != null) 'BeginY': beginY!,
      if (endX != null) 'EndX': endX!,
      if (endY != null) 'EndY': endY!,
    };

    double? eval(String? f) => evaluateFormula(
          f,
          locals: locals,
          sheetLookup: sheetLookup,
          cellLookup: lookupLocalRef,
        );

    void bindScratch(List<VsdxScratchRow> rows) {
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        void put(String cell, double v) {
          locals['SCRATCH.$cell${r.ix}'] = v;
          locals['SCRATCH.$cell${i + 1}'] = v;
        }
        put('X', r.x);
        put('Y', r.y);
        put('A', r.a);
        put('B', r.b);
        put('C', r.c);
        put('D', r.d);
      }
    }

    List<VsdxScratchRow> evalScratch(List<VsdxScratchRow> rows) {
      final out = <VsdxScratchRow>[];
      for (final r in rows) {
        final nx = eval(r.xFormula);
        final ny = eval(r.yFormula);
        final na = eval(r.aFormula);
        final nb = eval(r.bFormula);
        final nc = eval(r.cFormula);
        final nd = eval(r.dFormula);
        if (nx == null &&
            ny == null &&
            na == null &&
            nb == null &&
            nc == null &&
            nd == null) {
          out.add(r);
          continue;
        }
        out.add(r.copyWith(
          x: nx ?? r.x,
          y: ny ?? r.y,
          a: na ?? r.a,
          b: nb ?? r.b,
          c: nc ?? r.c,
          d: nd ?? r.d,
        ));
      }
      return out;
    }

    var changed = false;

    List<VsdxConnectionPoint>? nextPts;
    if (connectionPoints.isNotEmpty) {
      final out = <VsdxConnectionPoint>[];
      for (final p in connectionPoints) {
        final nx = eval(p.xFormula);
        final ny = eval(p.yFormula);
        if (nx == null && ny == null) {
          out.add(p);
          continue;
        }
        changed = true;
        out.add(p.copyWith(x: nx ?? p.x, y: ny ?? p.y));
      }
      nextPts = out;
    }

    double? nextLocX = locPinXInches;
    double? nextLocY = locPinYInches;
    var nextPinX = pinX;
    var nextPinY = pinY;
    var nextWidth = width;
    var nextHeight = height;

    // XForm cache cells that commonly carry F= (1-D Begin-origin connectors,
    // Guard'd sizes, …). Width/Height first so LocPin Width*0.5 sees them;
    // Pin after LocPin so midpoint formulas stay consistent with Begin/End.
    void applyXForm(String cell, void Function(double v) set) {
      final f = formulas[cell];
      if (f == null) return;
      final v = eval(f);
      if (v == null) return;
      set(v);
    }

    applyXForm('Width', (v) {
      if ((nextWidth - v).abs() > 1e-12) {
        nextWidth = v;
        locals['Width'] = v;
        changed = true;
      }
    });
    applyXForm('Height', (v) {
      if ((nextHeight - v).abs() > 1e-12) {
        nextHeight = v;
        locals['Height'] = v;
        changed = true;
      }
    });

    final locXF = formulas['LocPinX'];
    final locYF = formulas['LocPinY'];
    if (locXF != null) {
      final v = eval(locXF);
      if (v != null && (nextLocX == null || (nextLocX - v).abs() > 1e-12)) {
        nextLocX = v;
        locals['LocPinX'] = v;
        changed = true;
      }
    }
    if (locYF != null) {
      final v = eval(locYF);
      if (v != null && (nextLocY == null || (nextLocY - v).abs() > 1e-12)) {
        nextLocY = v;
        locals['LocPinY'] = v;
        changed = true;
      }
    }

    applyXForm('PinX', (v) {
      if ((nextPinX - v).abs() > 1e-12) {
        nextPinX = v;
        locals['PinX'] = v;
        changed = true;
      }
    });
    applyXForm('PinY', (v) {
      if ((nextPinY - v).abs() > 1e-12) {
        nextPinY = v;
        locals['PinY'] = v;
        changed = true;
      }
    });

    // Scratch: Width/Height pass, then up to two passes with Scratch.* bound
    // so rows that reference earlier Scratch cells can settle.
    List<VsdxScratchRow>? nextScratch;
    var effectiveScratch = scratch;
    if (scratch.isNotEmpty) {
      var rows = evalScratch(scratch);
      if (rows != scratch) changed = true;
      for (var pass = 0; pass < 2; pass++) {
        bindScratch(rows);
        final again = evalScratch(rows);
        if (again == rows) break;
        rows = again;
        changed = true;
      }
      bindScratch(rows);
      nextScratch = rows;
      effectiveScratch = rows;
    } else {
      bindScratch(effectiveScratch);
    }

    List<VsdxControlRow>? nextControls;
    if (controls.isNotEmpty) {
      final out = <VsdxControlRow>[];
      for (final r in controls) {
        final nx = eval(r.xFormula);
        final ny = eval(r.yFormula);
        final ndx = eval(r.dynXFormula);
        final ndy = eval(r.dynYFormula);
        final ncx = eval(r.conXFormula);
        final ncy = eval(r.conYFormula);
        if (nx == null &&
            ny == null &&
            ndx == null &&
            ndy == null &&
            ncx == null &&
            ncy == null) {
          out.add(r);
          continue;
        }
        changed = true;
        out.add(r.copyWith(
          x: nx ?? r.x,
          y: ny ?? r.y,
          dynX: ndx ?? r.dynX,
          dynY: ndy ?? r.dynY,
          conX: ncx ?? r.conX,
          conY: ncy ?? r.conY,
        ));
      }
      nextControls = out;
    }

    List<VsdxUserCell>? nextUsers;
    if (userCells.isNotEmpty) {
      final out = <VsdxUserCell>[];
      for (final c in userCells) {
        final v = eval(c.valueFormula);
        if (v == null) {
          out.add(c);
          continue;
        }
        final asStr = v == v.roundToDouble() ? '${v.toInt()}' : '$v';
        if (c.value == asStr) {
          out.add(c);
          continue;
        }
        changed = true;
        out.add(c.copyWith(value: asStr));
      }
      nextUsers = out;
    }

    List<VsdxGeometry>? nextGeoms;
    if (geometries.isNotEmpty) {
      final out = <VsdxGeometry>[];
      var geomChanged = false;
      for (final g in geometries) {
        if (g.commandFormulas.isEmpty) {
          out.add(g);
          continue;
        }
        final cmds = <VsdxPathCommand>[];
        var sectionChanged = false;
        for (var i = 0; i < g.commands.length; i++) {
          final cmd = g.commands[i];
          final f = g.formulasAt(i);
          if (f.isEmpty) {
            cmds.add(cmd);
            continue;
          }
          final next = applyPathCommandFormulas(cmd, f, eval);
          if (!identical(next, cmd) && next != cmd) {
            sectionChanged = true;
          }
          cmds.add(next);
        }
        if (sectionChanged) {
          geomChanged = true;
          out.add(g.copyWith(commands: cmds));
        } else {
          out.add(g);
        }
      }
      if (geomChanged) {
        changed = true;
        nextGeoms = out;
      }
    }

    if (!changed) return syncSetAtRefFromControls();
    return copyWith(
      pinX: nextPinX,
      pinY: nextPinY,
      width: nextWidth,
      height: nextHeight,
      connectionPoints: nextPts,
      locPinXInches: nextLocX,
      locPinYInches: nextLocY,
      scratch: nextScratch,
      controls: nextControls,
      userCells: nextUsers,
      geometries: nextGeoms,
    ).syncSetAtRefFromControls();
  }

  /// Pull `TxtPin*` / `TxtWidth` / `TxtHeight` cache values from formulas
  /// (SETATREF or Width*/Height* expressions).
  VsdxShape syncSetAtRefFromControls() {
    final fx = formulas['TxtPinX'];
    final fy = formulas['TxtPinY'];
    final fw = formulas['TxtWidth'];
    final fh = formulas['TxtHeight'];
    if (fx == null && fy == null && fw == null && fh == null) return this;

    final locals = <String, double>{
      'Width': width,
      'Height': height,
      'PinX': pinX,
      'PinY': pinY,
      'Angle': angleRad,
      if (locPinXInches != null) 'LocPinX': locPinXInches!,
      if (locPinYInches != null) 'LocPinY': locPinYInches!,
      if (beginX != null) 'BeginX': beginX!,
      if (beginY != null) 'BeginY': beginY!,
      if (endX != null) 'EndX': endX!,
      if (endY != null) 'EndY': endY!,
    };

    double? resolve(String? formula, {required bool forY}) {
      if (formula == null || formula.isEmpty) return null;
      // Bare SETATREF(Controls.Name) on TxtPinY → Controls.Name.Y.
      final ctrl = parseSetAtRefControl(formula);
      if (ctrl != null && ctrl.cell == null && forY) {
        return lookupLocalRef('Controls.${ctrl.name}.Y');
      }
      return evaluateFormula(
        formula,
        locals: locals,
        cellLookup: lookupLocalRef,
      );
    }

    final block = richText.textBlock;
    var txtPinX = block.pinXInches;
    var txtPinY = block.pinYInches;
    var txtW = block.widthInches;
    var txtH = block.heightInches;
    var touched = false;
    final rx = resolve(fx, forY: false);
    if (rx != null && (txtPinX == null || (txtPinX - rx).abs() > 1e-12)) {
      txtPinX = rx;
      touched = true;
    }
    final ry = resolve(fy, forY: true);
    if (ry != null && (txtPinY == null || (txtPinY - ry).abs() > 1e-12)) {
      txtPinY = ry;
      touched = true;
    }
    final rw = resolve(fw, forY: false);
    if (rw != null && (txtW == null || (txtW - rw).abs() > 1e-12)) {
      txtW = rw;
      touched = true;
    }
    final rh = resolve(fh, forY: true);
    if (rh != null && (txtH == null || (txtH - rh).abs() > 1e-12)) {
      txtH = rh;
      touched = true;
    }
    if (!touched) return this;
    return copyWith(
      richText: richText.copyWith(
        textBlock: block.copyWith(
          pinXInches: txtPinX,
          pinYInches: txtPinY,
          widthInches: txtW,
          heightInches: txtH,
        ),
      ),
    );
  }

  /// Push current `TxtPinX` / `TxtPinY` cache values through SETATREF /
  /// SETATREFEVAL into the referenced Controls / User / Prop cells.
  VsdxShape pushSetAtRefToControls() {
    final pinX = richText.textBlock.pinXInches;
    final pinY = richText.textBlock.pinYInches;
    if (pinX == null && pinY == null) return this;
    return applySetAtRefInputs(<String, double>{
      if (pinX != null) 'TxtPinX': pinX,
      if (pinY != null) 'TxtPinY': pinY,
    });
  }

  /// Re-position this shape as a straight 1-D line between page points
  /// ([ax],[ay]) and ([bx],[by]). Delegates to [reshapeAsPolyline] so the
  /// Visio Begin-origin XForm convention is shared.
  VsdxShape reshapeAsLine({
    required double ax,
    required double ay,
    required double bx,
    required double by,
  }) =>
      reshapeAsPolyline(<Offset2D>[Offset2D(ax, ay), Offset2D(bx, by)]);

  /// Re-position this shape as a 1-D polyline through page-space [points]
  /// (≥2). Uses Visio / 万兴图示 connector convention so exported elbows survive:
  ///
  /// * local `MoveTo(0,0)` = Begin; last vertex = `(Width, Height)` = End
  /// * `Width = EndX−BeginX`, `Height = EndY−BeginY` (may be negative)
  /// * `ConFixedCode = 3` so hosts don't freely re-route over baked Geometry
  VsdxShape reshapeAsPolyline(List<Offset2D> points) {
    if (points.length < 2) return this;
    final ax = points.first.x;
    final ay = points.first.y;
    final bx = points.last.x;
    final by = points.last.y;
    final w = bx - ax;
    final h = by - ay;
    final commands = <VsdxPathCommand>[
      const MoveTo(0, 0),
      for (final p in points.skip(1)) LineTo(p.x - ax, p.y - ay),
    ];
    final props = (connectorProps ?? const VsdxConnectorProps()).copyWith(
      // Match Visio dynamic connectors (fixture ConFixedCode=3): preserve the
      // baked Geometry in 万兴图示 / Visio instead of "Reroute freely" (0).
      conFixedCode: 3,
      noLiveDynamics: true,
      glueType: connectorProps?.glueType ?? 2,
      dynFeedback: connectorProps?.dynFeedback ?? 2,
      conLineRouteExt: connectorProps?.conLineRouteExt ?? 1,
      shapeRouteStyle: connectorProps?.shapeRouteStyle ?? 16,
    );
    final nextFormulas = Map<String, String>.from(formulas)
      ..['PinX'] = '(BeginX+EndX)*0.5'
      ..['PinY'] = '(BeginY+EndY)*0.5'
      ..['Width'] = 'EndX-BeginX'
      ..['Height'] = 'EndY-BeginY'
      ..['LocPinX'] = '(EndX-BeginX)/2'
      ..['LocPinY'] = '(EndY-BeginY)/2';
    // Baked Begin/End values replace dynamic glue formulas; leaving PAR(PNT…)
    // or Sheet.n! refs would make Visio/Edraw snap the endpoint back on open.
    for (final key in const <String>['BeginX', 'BeginY', 'EndX', 'EndY']) {
      final f = nextFormulas[key];
      if (f == null) continue;
      if (f.toUpperCase().contains('PAR(PNT') || f.contains('Sheet.')) {
        nextFormulas.remove(key);
      }
    }
    // Visio 1-D connectors express orientation via Begin/End, not Angle/Flip.
    // Clearing residual Angle after reparent/ungroup avoids double-rotation
    // when Geometry is Begin-local and Width = EndX−BeginX.
    return copyWith(
      pinX: (ax + bx) / 2,
      pinY: (ay + by) / 2,
      width: w,
      height: h,
      locPinXInches: w / 2,
      locPinYInches: h / 2,
      is1D: true,
      objType: objType ?? 2,
      beginX: ax,
      beginY: ay,
      endX: bx,
      endY: by,
      angleRad: 0,
      flipX: false,
      flipY: false,
      formulas: nextFormulas,
      connectorProps: props,
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
