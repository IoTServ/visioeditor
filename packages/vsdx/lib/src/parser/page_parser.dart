/// Parses a single `pageN.xml` part into a list of [VsdxShape].
///
/// M0/M1 scope: extract the absolute essentials needed for the placeholder
/// renderer (id, name, pin, size, angle, plain text, sub-shapes). Style,
/// geometry, master inheritance and richtext arrive in M2/M3/M6.
library;

import 'package:logging/logging.dart';
import 'package:xml/xml.dart';

import '../core/exceptions.dart';
import '../model/dash_pattern.dart';
import '../model/effects.dart';
import '../model/fill.dart';
import '../model/geometry.dart';
import '../model/line.dart';
import '../model/master.dart';
import '../model/rich_text.dart';
import '../model/shape.dart';
import '../model/sheet_sections.dart';
import '../model/stylesheet.dart';
import 'cell_helpers.dart';
import 'geometry_parser.dart';
import 'hyperlink_parser.dart';
import 'layer_parser.dart';
import 'rich_text_parser.dart';
import 'shape_kind_detector.dart';
import 'style_parser.dart';
import 'user_property_parser.dart';

final _log = Logger('vsdx.parser.page');

class PageParser {
  const PageParser({
    GeometryParser geometry = const GeometryParser(),
    StyleParser style = const StyleParser(),
    RichTextParser richText = const RichTextParser(),
    MasterRegistry masters = MasterRegistry.empty,
    StyleSheetRegistry stylesheets = StyleSheetRegistry.empty,
    Map<String, String>? imageRels,
    this.pageShadowOffsetXInches = 0.125,
    this.pageShadowOffsetYInches = -0.125,
  })  : _geometry = geometry,
        _style = style,
        _richText = richText,
        _masters = masters,
        _stylesheets = stylesheets,
        _imageRels = imageRels;

  final GeometryParser _geometry;
  final StyleParser _style;
  final RichTextParser _richText;
  final MasterRegistry _masters;
  final StyleSheetRegistry _stylesheets;

  /// Optional mapping `rId → absolute media part name` for `<ForeignData>`
  /// references on this page. The PagesParser injects it per page.
  final Map<String, String>? _imageRels;

  /// PageSheet `ShdwOffsetX` / `ShdwOffsetY` — used when a shape enables
  /// shadow without its own `ShadowOffset*` cells (Visio behaviour).
  final double pageShadowOffsetXInches;
  final double pageShadowOffsetYInches;

  /// Spawn a sibling parser configured with a different rich-text field
  /// resolver — used by the PagesParser to push page-specific values
  /// (page name, page index, total pages) before parsing shapes.
  PageParser withFieldResolver(FieldResolver resolver) => PageParser(
        geometry: _geometry,
        style: _style,
        richText: _richText.withFieldResolver(resolver),
        masters: _masters,
        stylesheets: _stylesheets,
        imageRels: _imageRels,
        pageShadowOffsetXInches: pageShadowOffsetXInches,
        pageShadowOffsetYInches: pageShadowOffsetYInches,
      );

  /// Override page-level shadow offsets from PageSheet.
  PageParser withPageShadowOffsets(double x, double y) => PageParser(
        geometry: _geometry,
        style: _style,
        richText: _richText,
        masters: _masters,
        stylesheets: _stylesheets,
        imageRels: _imageRels,
        pageShadowOffsetXInches: x,
        pageShadowOffsetYInches: y,
      );

  /// Returns the top-level shapes of [pageDoc]. Group sub-shapes are
  /// represented via [VsdxShape.children] (recursion is bounded by Visio's
  /// own depth — we add a soft safety cap to guard pathological inputs).
  List<VsdxShape> parseShapes(XmlDocument pageDoc, {required String partName}) {
    final root = pageDoc.rootElement;
    // <PageContents><Shapes><Shape .../></Shapes></PageContents>
    final shapesEl = _firstChildLocal(root, 'Shapes');
    if (shapesEl == null) return const <VsdxShape>[];
    return _readShapes(shapesEl, partName: partName, depth: 0);
  }

  List<VsdxShape> _readShapes(
    XmlElement shapesEl, {
    required String partName,
    required int depth,
    VsdxMaster? inheritedMaster,
    String? inheritedShapeName,
  }) {
    if (depth > 64) {
      // Visio caps practical nesting well below this; bail out loudly.
      throw VsdxParseException(
        'Shape nesting depth exceeds safety cap (64)',
        partName: partName,
      );
    }
    final out = <VsdxShape>[];
    for (final el in shapesEl.childElements) {
      if (el.name.local != 'Shape') continue;
      try {
        out.add(_readShape(
          el,
          partName: partName,
          depth: depth,
          inheritedMaster: inheritedMaster,
          inheritedShapeName: inheritedShapeName,
        ));
      } catch (e, st) {
        // Per ARCHITECTURE §5.7: parse failures on a single shape must not
        // sink the whole page.
        _log.warning(
          () => 'Skipping malformed shape in $partName: $e',
          e,
          st,
        );
      }
    }
    return out;
  }

  VsdxShape _readShape(
    XmlElement shapeEl, {
    required String partName,
    required int depth,
    VsdxMaster? inheritedMaster,
    String? inheritedShapeName,
  }) {
    final idStr = shapeEl.getAttribute('ID');
    final id = idStr == null ? -1 : int.tryParse(idStr) ?? -1;
    // libvisio uses the universal name only. A nested shape without NameU
    // inherits its enclosing group's universal name; the localized Name
    // attribute is not used as the shape type.
    final libvisioName = shapeEl.getAttribute('NameU') ?? inheritedShapeName;
    final nameU = libvisioName ?? 'Sheet.$id';

    // Resolve the inheritance prototype up front; subsequent reads use its
    // geometry / fill / line / text as defaults. `Master="M"` binds a whole
    // subtree to master M and inherits its top shape; a nested `MasterShape="N"`
    // (no Master) inherits the master sub-shape N from that same context
    // (Visio / libvisio resolve instance sub-shapes this way).
    final masterIdStr = shapeEl.getAttribute('Master');
    final masterId = masterIdStr == null ? null : int.tryParse(masterIdStr);
    final masterShapeStr = shapeEl.getAttribute('MasterShape');
    final masterShapeId =
        masterShapeStr == null ? null : int.tryParse(masterShapeStr);
    // libvisio keeps the enclosing group's master page for nested master
    // references. A child cannot switch to an unrelated stencil by repeating
    // Master; MasterShape is resolved inside the inherited master context.
    final hasMasterReference = masterId != null || masterShapeId != null;
    final master = depth > 0 && hasMasterReference
        ? inheritedMaster
        : masterId != null
            ? _masters.find(masterId)
            : inheritedMaster;
    final VsdxShape? proto;
    if (masterShapeId != null && master != null) {
      proto = master.findShape(masterShapeId);
    } else if (masterId != null) {
      proto = master?.prototype;
    } else {
      proto = null;
    }

    double? instanceLength(String name, double? inherited) {
      final cell = findCell(shapeEl, name);
      if (masterShapeId != null &&
          cell != null &&
          isInhFormula(cell.getAttribute('F'))) {
        final cached = double.tryParse(cell.getAttribute('V') ?? '');
        if (cached != null) return cached;
      }
      return readLengthInches(shapeEl, name, inheritFrom: inherited);
    }

    final pinX = instanceLength('PinX', proto?.pinX) ?? proto?.pinX ?? 0;
    final pinY = instanceLength('PinY', proto?.pinY) ?? proto?.pinY ?? 0;
    final width = instanceLength('Width', proto?.width) ?? proto?.width ?? 0.0;
    final height =
        instanceLength('Height', proto?.height) ?? proto?.height ?? 0.0;
    // LocPinX/LocPinY — the in-shape point that sits on the pin (and the
    // rotation centre). Usually the centre for 2-D shapes, but connectors and
    // some stencils pin off-centre; keep it so geometry maps to the right spot.
    final locPinX = instanceLength('LocPinX', proto?.locPinXInches) ??
        proto?.locPinXInches ??
        0.0;
    final locPinY = instanceLength('LocPinY', proto?.locPinYInches) ??
        proto?.locPinYInches ??
        0.0;
    final angleRad =
        readAngleRadians(shapeEl, 'Angle', inheritFrom: proto?.angleRad) ??
            proto?.angleRad ??
            0.0;
    final flipX = _readBoolCell(shapeEl, 'FlipX', inheritFrom: proto?.flipX) ??
        proto?.flipX ??
        false;
    final flipY = _readBoolCell(shapeEl, 'FlipY', inheritFrom: proto?.flipY) ??
        proto?.flipY ??
        false;
    // drawio-style "locked": read back the canonical protection bit written by
    // the writer (a shape is treated as locked when its move is locked).
    final locked =
        _readBoolCell(shapeEl, 'LockMoveX', inheritFrom: proto?.locked) ??
            proto?.locked ??
            false;

    final shapeTypeAttr = shapeEl.getAttribute('Type');
    final has1DTransform = const <String>[
      'BeginX',
      'BeginY',
      'BegTrigger',
      'EndTrigger',
      'EndX',
      'EndY',
    ].any((name) => findCell(shapeEl, name) != null);
    // libvisio allocates XForm1D when any endpoint or trigger cell exists;
    // producer output does not need a Type attribute or both X coordinates.
    final is1D = has1DTransform || proto?.is1D == true;
    final beginX =
        readLengthInches(shapeEl, 'BeginX', inheritFrom: proto?.beginX) ??
            proto?.beginX ??
            (is1D ? 0.0 : null);
    final beginY =
        readLengthInches(shapeEl, 'BeginY', inheritFrom: proto?.beginY) ??
            proto?.beginY ??
            (is1D ? 0.0 : null);
    final endX = readLengthInches(shapeEl, 'EndX', inheritFrom: proto?.endX) ??
        proto?.endX ??
        (is1D ? 0.0 : null);
    final endY = readLengthInches(shapeEl, 'EndY', inheritFrom: proto?.endY) ??
        proto?.endY ??
        (is1D ? 0.0 : null);

    // Nested <Shapes> ⇒ a group. Children inherit the same master context so
    // their `MasterShape="N"` references resolve against master [master].
    final childGroup = _firstChildLocal(shapeEl, 'Shapes');
    final children = childGroup == null
        ? const <VsdxShape>[]
        : _readShapes(
            childGroup,
            partName: partName,
            depth: depth + 1,
            inheritedMaster: master,
            inheritedShapeName: libvisioName,
          );

    var geometries = _geometry.parse(shapeEl);
    if (proto != null && proto.geometries.isNotEmpty) {
      // Inherit master geometry by IX: instance rows override same-IX master
      // rows, `Del` removes them, and section flags inherit unless overridden
      // (mirrors libvisio's per-IX geometry inheritance).
      geometries = GeometryParser.mergeInherited(
        proto.geometries,
        geometries,
        // libvisio's VSDXMLParserBase reads Geometry V= directly even when
        // F="Inh". The value is Visio's instance-sized formula cache; using
        // the master's cached coordinate distorts resized master instances.
        preferInstanceCachedInh: true,
      );
    }

    // Picture / Foreign shapes typically have no fill or stroke; when the
    // cells are absent (older writers omitted them), default to pattern 0
    // rather than Visio's solid defaults so round-trips stay visually empty.
    final isForeign = shapeTypeAttr == 'Foreign';
    final fillStyleId = int.tryParse(shapeEl.getAttribute('FillStyle') ?? '') ??
        proto?.fillStyleId;
    final sheetFill =
        fillStyleId != null ? _stylesheets.resolveFill(fillStyleId) : null;
    // libvisio reads evaluated V= colour caches from master instances even
    // when F="Inh", instead of replacing them with the stencil's current
    // QuickStyle colour.
    final preferCachedInhStyle = proto != null;
    final fill = _style.parseFill(
      shapeEl,
      defaults: proto?.fill ?? sheetFill ?? libvisioShapeFillDefault,
      preferCachedInh: preferCachedInhStyle,
    );
    final lineStyleId = int.tryParse(shapeEl.getAttribute('LineStyle') ?? '') ??
        proto?.lineStyleId;
    final sheetLine =
        lineStyleId != null ? _stylesheets.resolveLine(lineStyleId) : null;
    var line = _style.parseLine(
      shapeEl,
      defaults: proto?.line ??
          sheetLine ??
          (isForeign ? const VsdxLine(pattern: 0) : VsdxLine.defaultLine),
      preferCachedInh: preferCachedInhStyle,
    );
    final sheetShadow = fillStyleId == null
        ? null
        : _stylesheets.resolveShadow(
            fillStyleId,
            pageOffsetXInches: pageShadowOffsetXInches,
            pageOffsetYInches: pageShadowOffsetYInches,
          );
    final shadow = _style.parseShadow(
      shapeEl,
      defaults: proto?.shadow ?? sheetShadow ?? VsdxShadow.disabled,
      pageOffsetXInches: pageShadowOffsetXInches,
      pageOffsetYInches: pageShadowOffsetYInches,
    );
    final glow = _style.parseGlow(
      shapeEl,
      defaults: proto?.glow ?? VsdxGlow.disabled,
    );
    final reflection = _style.parseReflection(
      shapeEl,
      defaults: proto?.reflection ?? VsdxReflection.disabled,
    );

    // Character defaults (libvisio order):
    //   1. shape's own TextStyle stylesheet
    //   2. master TextStyle / prototype Character
    //   3. document DefaultTextStyle
    // Do NOT apply DefaultTextStyle when the shape only has a Master — that
    // would wipe Connector=8pt / stencil Character=10pt with Normal=12pt.
    final ownTextStyleId =
        int.tryParse(shapeEl.getAttribute('TextStyle') ?? '');
    final textStyleId = ownTextStyleId ?? proto?.textStyleId;
    final ownSheetChar = ownTextStyleId == null
        ? null
        : _stylesheets.resolveCharStyle(ownTextStyleId);
    final inheritedSheetChar = proto?.textStyleId == null
        ? null
        : _stylesheets.resolveCharStyle(proto!.textStyleId!);
    final protoChar = proto?.richText.runs.isNotEmpty == true
        ? proto!.richText.runs.first.charStyle
        : null;
    // An instance's explicit TextStyle wins. Otherwise a Character row on the
    // Master is more specific than the Master's own TextStyle stylesheet.
    // Choosing the inherited stylesheet first flattened 10 pt stencil text to
    // the document's 12 pt default in common Visio fixtures.
    final defaultChar = ownSheetChar ??
        protoChar ??
        inheritedSheetChar ??
        _stylesheets.resolveCharStyle(null) ??
        libvisioCharacterStyleDefault;
    final protoPara = proto?.richText.runs.isNotEmpty == true
        ? proto!.richText.runs.first.paraStyle
        : libvisioParagraphStyleDefault;
    final defaultPara = ownTextStyleId != null
        ? (_stylesheets.resolveParaStyle(
              ownTextStyleId,
              defaults: protoPara,
            ) ??
            protoPara)
        : (proto != null
            ? protoPara
            : (_stylesheets.resolveParaStyle(
                  null,
                  defaults: protoPara,
                ) ??
                protoPara));
    final protoBlock =
        proto?.richText.textBlock ?? libvisioTextBlockStyleDefault;
    final defaultBlock = ownTextStyleId != null
        ? (_stylesheets.resolveTextBlock(
              ownTextStyleId,
              defaults: protoBlock,
            ) ??
            protoBlock)
        : (proto != null
            ? protoBlock
            : (_stylesheets.resolveTextBlock(
                  null,
                  defaults: protoBlock,
                ) ??
                protoBlock));

    // DiagramML commonly stores a dynamic field's display cache in the
    // Field row while leaving `<fld IX="…"/>` empty. Parse rows first so the
    // rich-text stream can resolve those markers the way libvisio's collector
    // does when it flushes a shape.
    final ownFields = _readFields(shapeEl, inherit: proto?.fields);
    final fields =
        ownFields.isEmpty && proto != null ? proto.fields : ownFields;

    var richText = _richText.parse(
      shapeEl,
      defaultChar: defaultChar,
      defaultPara: defaultPara,
      // Inherit the Master's text-block transform (TxtAngle, TxtPin/LocPin,
      // vertical align, …) so shapes that leave their text orientation on the
      // Master aren't forced back to horizontal.
      defaultBlock: defaultBlock,
      inheritTabs: proto?.richText.tabSets ?? const <VsdxTabSet>[],
      fields: fields,
      preferCachedInh: preferCachedInhStyle,
    );
    // Masters often carry TextStyle but no <Text>. Seed an empty run so
    // instance shapes that inherit the prototype pick up the stylesheet size
    // (libvisio does the same via the master's TextStyle attribute).
    // (Character-without-Text is already seeded inside RichTextParser.)
    if (richText.runs.isEmpty && ownSheetChar != null) {
      richText = VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(
            text: '',
            charStyle: ownSheetChar,
            paraStyle: defaultPara,
          ),
        ],
        textBlock: richText.textBlock,
        tabSets: richText.tabSets,
      );
    }
    final hasLocalText = _firstChildLocal(shapeEl, 'Text') != null;
    final effectiveRich = !hasLocalText && proto != null
        ? _inheritMasterText(richText, proto, defaultChar, defaultPara)
        : richText;
    final plain = readShapeText(shapeEl) ??
        (effectiveRich.runs.isEmpty
            ? null
            : (effectiveRich.plainText.isEmpty
                ? null
                : effectiveRich.plainText)) ??
        proto?.text;

    final layerMembers = LayerParser.parseLayerMembersOrNull(shapeEl);
    final imagePartName =
        _resolveForeignDataPart(shapeEl) ?? proto?.imagePartName;
    final foreignMeta = _readForeignDataMeta(shapeEl);
    final foreignType = foreignMeta.$1 ?? proto?.foreignType;
    final foreignCompressionType =
        foreignMeta.$2 ?? proto?.foreignCompressionType;
    // Image Properties (MS-VSDX §2.2.6) — top-level cells on Foreign shapes.
    // F=Inh without a master must use model defaults (not stale V=).
    final imgOffsetX = readLengthInches(
          shapeEl,
          'ImgOffsetX',
          inheritFrom: proto?.imgOffsetXInches ?? 0.0,
        ) ??
        _double(shapeEl, 'ImgOffsetX',
            inheritFrom: proto?.imgOffsetXInches ?? 0.0) ??
        proto?.imgOffsetXInches ??
        0.0;
    final imgOffsetY = readLengthInches(
          shapeEl,
          'ImgOffsetY',
          inheritFrom: proto?.imgOffsetYInches ?? 0.0,
        ) ??
        _double(shapeEl, 'ImgOffsetY',
            inheritFrom: proto?.imgOffsetYInches ?? 0.0) ??
        proto?.imgOffsetYInches ??
        0.0;
    final imgWidth = readLengthInches(
          shapeEl,
          'ImgWidth',
          inheritFrom: proto?.imgWidthInches,
        ) ??
        _double(shapeEl, 'ImgWidth', inheritFrom: proto?.imgWidthInches) ??
        proto?.imgWidthInches;
    final imgHeight = readLengthInches(
          shapeEl,
          'ImgHeight',
          inheritFrom: proto?.imgHeightInches,
        ) ??
        _double(shapeEl, 'ImgHeight', inheritFrom: proto?.imgHeightInches) ??
        proto?.imgHeightInches;
    // Top-level Image `Transparency` (not Character-row Transparency).
    final imageTransparency = (_double(
              shapeEl,
              'Transparency',
              inheritFrom: proto?.imageTransparency ?? 0.0,
            ) ??
            proto?.imageTransparency ??
            0.0)
        .clamp(0.0, 1.0);
    final imageBlur = (_double(
              shapeEl,
              'Blur',
              inheritFrom: proto?.imageBlur ?? 0.0,
            ) ??
            proto?.imageBlur ??
            0.0)
        .clamp(0.0, 1.0);
    final imageBrightness = (_double(
              shapeEl,
              'Brightness',
              inheritFrom: proto?.imageBrightness ?? 0.5,
            ) ??
            proto?.imageBrightness ??
            0.5)
        .clamp(0.0, 1.0);
    final imageContrast = (_double(
              shapeEl,
              'Contrast',
              inheritFrom: proto?.imageContrast ?? 0.5,
            ) ??
            proto?.imageContrast ??
            0.5)
        .clamp(0.0, 1.0);
    final ownConnPts =
        _readConnectionPoints(shapeEl, inherit: proto?.connectionPoints);
    final connectionPoints = ownConnPts.isEmpty && proto != null
        ? proto.connectionPoints
        : ownConnPts;
    final ownHyperlinks =
        const HyperlinkParser().parse(shapeEl, inherit: proto?.hyperlinks);
    final hyperlinks = ownHyperlinks.isEmpty && proto != null
        ? proto.hyperlinks
        : ownHyperlinks;

    const userParser = UserPropertyParser();
    final ownProps =
        userParser.parseProperties(shapeEl, inherit: proto?.userProperties);
    final props =
        ownProps.isEmpty && proto != null ? proto.userProperties : ownProps;
    final ownUserCells =
        userParser.parseUserCells(shapeEl, inherit: proto?.userCells);
    final userCells =
        ownUserCells.isEmpty && proto != null ? proto.userCells : ownUserCells;
    List<double>? drawioDashPattern;
    var drawioFixedDash = false;
    for (final cell in userCells) {
      if (cell.name == VsdxShape.userLineJoin) {
        final join = VsdxLineJoin.parse(cell.value);
        if (join != null) line = line.copyWith(join: join);
      } else if (cell.name == VsdxShape.userMiterLimit) {
        final limit = double.tryParse(cell.value ?? '');
        if (limit != null && limit >= 1) {
          line = line.copyWith(miterLimit: limit.clamp(1.0, 100.0).toDouble());
        }
      } else if (cell.name == VsdxShape.userDashPattern) {
        drawioDashPattern = parseDrawioDashPattern(cell.value);
      } else if (cell.name == VsdxShape.userFixedDash) {
        drawioFixedDash = cell.value == '1';
      } else if (cell.name == VsdxShape.userVsdBeginArrowSize) {
        final size = double.tryParse(cell.value ?? '');
        if (size != null && size > 0 && line.hasBeginArrow) {
          line = line.copyWith(beginArrowSizeInches: size);
        }
      } else if (cell.name == VsdxShape.userVsdEndArrowSize) {
        final size = double.tryParse(cell.value ?? '');
        if (size != null && size > 0 && line.hasEndArrow) {
          line = line.copyWith(endArrowSizeInches: size);
        }
      }
    }
    if (drawioDashPattern != null) {
      line = line.copyWith(
        customDashPattern: List<double>.unmodifiable(drawioDashPattern),
        fixedDash: drawioFixedDash,
      );
    }
    final ownControls = _readControls(shapeEl, inherit: proto?.controls);
    final controls =
        ownControls.isEmpty && proto != null ? proto.controls : ownControls;
    final ownScratch = _readScratch(shapeEl, inherit: proto?.scratch);
    final scratch =
        ownScratch.isEmpty && proto != null ? proto.scratch : ownScratch;
    final ownActions = _readActions(shapeEl, inherit: proto?.actions);
    final actions =
        ownActions.isEmpty && proto != null ? proto.actions : ownActions;
    final masterName = masterId != null
        ? (master?.name ?? proto?.masterName)
        : proto?.masterName;

    final formulas = _readFormulas(shapeEl, proto?.formulas);
    final objType =
        _int(shapeEl, 'ObjType', inheritFrom: proto?.objType) ?? proto?.objType;
    // XForm1D midpoint formulas are authoritative over their cached V values.
    // Several real files carry stale Pin caches; using them shifts the line
    // until the first save. Do not canonicalise a literal Pin edit: Writer
    // intentionally removes the formula when the model moves Pin directly.
    final connectorFrame = is1D &&
        (objType == null || objType == 2) &&
        beginX != null &&
        beginY != null &&
        endX != null &&
        endY != null;
    final canonicalPinX =
        connectorFrame && _referencesBoth(formulas['PinX'], 'BeginX', 'EndX');
    final canonicalPinY =
        connectorFrame && _referencesBoth(formulas['PinY'], 'BeginY', 'EndY');
    final shapePinX = canonicalPinX ? (beginX + endX) * 0.5 : pinX;
    final shapePinY = canonicalPinY ? (beginY + endY) * 0.5 : pinY;
    final connectorProps = _readConnectorProps(
          shapeEl,
          inherit: proto?.connectorProps,
        ) ??
        proto?.connectorProps;

    const kindDetector = ShapeKindDetector();
    final shapeKind = kindDetector.detect(
      xmlType: shapeTypeAttr,
      name: nameU,
      masterName: masterName,
      is1D: is1D,
      hasImage: imagePartName != null,
      childCount: children.length,
      containerOverride: () {
        for (final cell in userCells) {
          if (cell.name == VsdxShape.userContainer) {
            return cell.value == '1';
          }
        }
        return null;
      }(),
      userProperties: props,
    );

    var parsed = VsdxShape(
      id: id,
      name: nameU,
      pinX: shapePinX,
      pinY: shapePinY,
      width: width,
      height: height,
      locPinXInches: locPinX,
      locPinYInches: locPinY,
      angleRad: angleRad,
      text: plain,
      richText: effectiveRich,
      children: children,
      geometries: tagStructuralHitBoxes(geometries),
      fill: fill,
      line: line,
      shadow: shadow,
      glow: glow,
      reflection: reflection,
      // LayerMember is shape-local in libvisio and is not copied from a
      // Master when the page instance omits it. LayerParser still consumes a
      // cached V= from an explicit F="Inh" cell, matching VSDXParser.
      layerMemberIds: layerMembers ?? const <int>[],
      is1D: is1D,
      beginX: beginX,
      beginY: beginY,
      endX: endX,
      endY: endY,
      flipX: flipX,
      flipY: flipY,
      locked: locked,
      imagePartName: imagePartName,
      imgOffsetXInches: imgOffsetX,
      imgOffsetYInches: imgOffsetY,
      imgWidthInches: imgWidth,
      imgHeightInches: imgHeight,
      imageTransparency: imageTransparency,
      imageBlur: imageBlur,
      imageBrightness: imageBrightness,
      imageContrast: imageContrast,
      foreignType: foreignType,
      foreignCompressionType: foreignCompressionType,
      objType: objType,
      resizeMode: _int(shapeEl, 'ResizeMode', inheritFrom: proto?.resizeMode) ??
          proto?.resizeMode,
      eventDblClick: () {
        final cell = findCell(shapeEl, 'EventDblClick');
        if (cell == null) return proto?.eventDblClick;
        if (isInhFormula(cell.getAttribute('F'))) return proto?.eventDblClick;
        return cell.getAttribute('V') ?? proto?.eventDblClick;
      }(),
      noAlignBox: _readBoolCell(shapeEl, 'NoAlignBox',
              inheritFrom: proto?.noAlignBox) ??
          proto?.noAlignBox ??
          false,
      shapeSplittable: _readBoolCell(shapeEl, 'ShapeSplittable',
              inheritFrom: proto?.shapeSplittable) ??
          proto?.shapeSplittable ??
          false,
      themeIndex: _int(shapeEl, 'ThemeIndex', inheritFrom: proto?.themeIndex) ??
          proto?.themeIndex,
      quickStyleFillMatrix: _int(shapeEl, 'QuickStyleFillMatrix',
              inheritFrom: proto?.quickStyleFillMatrix) ??
          proto?.quickStyleFillMatrix ??
          _stylesheets.resolveQuickStyleFillMatrix(fillStyleId),
      quickStyleLineMatrix: _int(shapeEl, 'QuickStyleLineMatrix',
              inheritFrom: proto?.quickStyleLineMatrix) ??
          proto?.quickStyleLineMatrix ??
          _stylesheets.resolveQuickStyleLineMatrix(lineStyleId),
      quickStyleEffectsMatrix: _int(shapeEl, 'QuickStyleEffectsMatrix',
              inheritFrom: proto?.quickStyleEffectsMatrix) ??
          proto?.quickStyleEffectsMatrix,
      quickStyleFontMatrix: _int(shapeEl, 'QuickStyleFontMatrix',
              inheritFrom: proto?.quickStyleFontMatrix) ??
          proto?.quickStyleFontMatrix,
      isTextEditTarget: _readBoolCell(shapeEl, 'IsTextEditTarget',
              inheritFrom: proto?.isTextEditTarget) ??
          proto?.isTextEditTarget ??
          false,
      dontMoveChildren: _readBoolCell(shapeEl, 'DontMoveChildren',
              inheritFrom: proto?.dontMoveChildren) ??
          proto?.dontMoveChildren ??
          false,
      selectMode: _int(shapeEl, 'SelectMode', inheritFrom: proto?.selectMode) ??
          proto?.selectMode,
      displayMode:
          _int(shapeEl, 'DisplayMode', inheritFrom: proto?.displayMode) ??
              proto?.displayMode,
      connectionPoints: connectionPoints,
      hyperlinks: hyperlinks,
      userProperties: props,
      userCells: userCells,
      controls: controls,
      scratch: scratch,
      fields: fields,
      actions: actions,
      masterId: masterId,
      masterShapeId: masterShapeId,
      masterName: masterName,
      lineStyleId: lineStyleId,
      fillStyleId: fillStyleId,
      textStyleId: textStyleId,
      formulas: formulas,
      connectorProps: connectorProps,
      shapeKind: shapeKind,
    );
    // Master instances inherit formulas such as LocPinX=Width*0.5 and
    // Geometry.X=Width*1. Their cached values in the master describe the
    // stencil's default size, while the instance can carry a different
    // literal Width/Height. Re-evaluate after applying the instance XForm so
    // geometry, text blocks and connection points expand with that instance,
    // matching libvisio/LibreOffice.
    if (proto != null) {
      // Inherited Scratch rows keep the master's evaluated V= cache, exactly
      // as libvisio does; geometry/XForm formulas may still consume it while
      // adapting to the instance Width/Height.
      parsed = parsed.recalculateLocalFormulas(recalculateScratch: false);
    }
    return parsed.restoreRouteState();
  }

  /// `<Section N="Control">` — named handle rows (libvisio / MS-VSDX).
  /// Accepts Visio `XDyn`/`XCon` names and Lucidchart `DynX`/`ConX` aliases.
  List<VsdxControlRow> _readControls(
    XmlElement shapeEl, {
    List<VsdxControlRow>? inherit,
  }) {
    final byName = <String, VsdxControlRow>{
      if (inherit != null)
        for (final c in inherit) c.name: c,
    };
    final out = <VsdxControlRow>[];
    for (final section in shapeEl.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Control') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final name = row.getAttribute('N');
        if (name == null || name.isEmpty) continue;
        final proto = byName[name];
        final hasVisioDyn = findCell(row, 'XDyn') != null ||
            findCell(row, 'YDyn') != null ||
            findCell(row, 'XCon') != null ||
            findCell(row, 'YCon') != null;
        final dynXName = hasVisioDyn ? 'XDyn' : 'DynX';
        final dynYName = hasVisioDyn ? 'YDyn' : 'DynY';
        final conXName = hasVisioDyn ? 'XCon' : 'ConX';
        final conYName = hasVisioDyn ? 'YCon' : 'ConY';
        out.add(VsdxControlRow(
          name: name,
          x: _double(row, 'X', inheritFrom: proto?.x) ?? proto?.x ?? 0,
          y: _double(row, 'Y', inheritFrom: proto?.y) ?? proto?.y ?? 0,
          conX: _double(row, conXName, inheritFrom: proto?.conX) ??
              _double(row, 'ConX', inheritFrom: proto?.conX) ??
              proto?.conX ??
              0,
          conY: _double(row, conYName, inheritFrom: proto?.conY) ??
              _double(row, 'ConY', inheritFrom: proto?.conY) ??
              proto?.conY ??
              0,
          dynX: _double(row, dynXName, inheritFrom: proto?.dynX) ??
              _double(row, 'DynX', inheritFrom: proto?.dynX) ??
              proto?.dynX ??
              0,
          dynY: _double(row, dynYName, inheritFrom: proto?.dynY) ??
              _double(row, 'DynY', inheritFrom: proto?.dynY) ??
              proto?.dynY ??
              0,
          xFormula: _formulaOrInherit(row, 'X', proto?.xFormula),
          yFormula: _formulaOrInherit(row, 'Y', proto?.yFormula),
          dynXFormula: _formulaOrInherit(row, dynXName, proto?.dynXFormula) ??
              _formulaOrInherit(row, 'DynX', proto?.dynXFormula),
          dynYFormula: _formulaOrInherit(row, dynYName, proto?.dynYFormula) ??
              _formulaOrInherit(row, 'DynY', proto?.dynYFormula),
          conXFormula: _formulaOrInherit(row, conXName, proto?.conXFormula) ??
              _formulaOrInherit(row, 'ConX', proto?.conXFormula),
          conYFormula: _formulaOrInherit(row, conYName, proto?.conYFormula) ??
              _formulaOrInherit(row, 'ConY', proto?.conYFormula),
          canGlue: (_int(row, 'CanGlue',
                      inheritFrom:
                          proto == null ? null : (proto.canGlue ? 1 : 0)) ??
                  (proto?.canGlue == true ? 1 : 0)) !=
              0,
          prompt: () {
            final cell = findCell(row, 'Prompt');
            if (cell == null) return proto?.prompt;
            if (isInhFormula(cell.getAttribute('F'))) return proto?.prompt;
            final p = cell.getAttribute('V');
            return (p == null || p.isEmpty) ? null : p;
          }(),
          useVisioDynNames: hasVisioDyn ||
              (findCell(row, 'DynX') == null && findCell(row, 'ConX') == null),
        ));
      }
    }
    return List.unmodifiable(out);
  }

  /// `<Section N="Scratch">` — indexed parametric cells.
  List<VsdxScratchRow> _readScratch(
    XmlElement shapeEl, {
    List<VsdxScratchRow>? inherit,
  }) {
    final byIx = <int, VsdxScratchRow>{
      if (inherit != null)
        for (final s in inherit) s.ix: s,
    };
    final out = <VsdxScratchRow>[];
    for (final section in shapeEl.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Scratch') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final ix = int.tryParse(row.getAttribute('IX') ?? '') ?? out.length;
        final proto = byIx[ix];
        out.add(VsdxScratchRow(
          ix: ix,
          x: readLengthInches(row, 'X', inheritFrom: proto?.x) ??
              _double(row, 'X', inheritFrom: proto?.x) ??
              proto?.x ??
              0,
          y: readLengthInches(row, 'Y', inheritFrom: proto?.y) ??
              _double(row, 'Y', inheritFrom: proto?.y) ??
              proto?.y ??
              0,
          a: readLengthInches(row, 'A', inheritFrom: proto?.a) ??
              _double(row, 'A', inheritFrom: proto?.a) ??
              proto?.a ??
              0,
          b: readLengthInches(row, 'B', inheritFrom: proto?.b) ??
              _double(row, 'B', inheritFrom: proto?.b) ??
              proto?.b ??
              0,
          c: readLengthInches(row, 'C', inheritFrom: proto?.c) ??
              _double(row, 'C', inheritFrom: proto?.c) ??
              proto?.c ??
              0,
          d: readLengthInches(row, 'D', inheritFrom: proto?.d) ??
              _double(row, 'D', inheritFrom: proto?.d) ??
              proto?.d ??
              0,
          xFormula: _formulaOrInherit(row, 'X', proto?.xFormula),
          yFormula: _formulaOrInherit(row, 'Y', proto?.yFormula),
          aFormula: _formulaOrInherit(row, 'A', proto?.aFormula),
          bFormula: _formulaOrInherit(row, 'B', proto?.bFormula),
          cFormula: _formulaOrInherit(row, 'C', proto?.cFormula),
          dFormula: _formulaOrInherit(row, 'D', proto?.dFormula),
        ));
      }
    }
    return List.unmodifiable(out);
  }

  /// Prefer a real parametric `F=`; `F=Inh` falls back to the master formula.
  static String? _formulaOrInherit(
    XmlElement parent,
    String name,
    String? inherit,
  ) {
    final f = _formula(parent, name);
    if (f == null) return inherit;
    if (isInhFormula(f)) return inherit;
    return f;
  }

  static String? _formula(XmlElement parent, String name) {
    final cell = findCell(parent, name);
    final f = cell?.getAttribute('F');
    if (f == null || f.isEmpty || f == 'No Formula') return null;
    return f;
  }

  static bool _referencesBoth(String? formula, String a, String b) {
    if (formula == null) return false;
    final upper = formula.toUpperCase();
    return upper.contains(a.toUpperCase()) && upper.contains(b.toUpperCase());
  }

  static const _formulaCellNames = <String>{
    'PinX',
    'PinY',
    'Width',
    'Height',
    'LocPinX',
    'LocPinY',
    'Angle',
    'BeginX',
    'BeginY',
    'EndX',
    'EndY',
    'BegTrigger',
    'EndTrigger',
    // Text-block transform — SETATREF(Controls.*) / TEXTWIDTH / Width*…
    'TxtPinX',
    'TxtPinY',
    'TxtWidth',
    'TxtHeight',
    'TxtLocPinX',
    'TxtLocPinY',
    'TxtAngle',
    // ShapeSheet event formulas. VSD imports populate all four from Event
    // chunks; keep them when the synthesized VSDX is parsed again.
    'TheText',
    'EventDblClick',
    'EventXFMod',
    'EventDrop',
    'FillPattern',
    'LinePattern',
    'FillForegnd',
    'FillBkgnd',
    'LineColor',
    // Foreign image crop — keep F= through group rebuild.
    'ImgOffsetX',
    'ImgOffsetY',
    'ImgWidth',
    'ImgHeight',
  };

  /// Inherit a Master's label when the instance has no local `<Text>`.
  ///
  /// A local Character/Paragraph section may still override the inherited
  /// label's formatting. [RichTextParser] represents that case as one or more
  /// empty, style-only runs; attach the Master's text to those styles instead
  /// of leaving an empty rich-text body that renderers treat as unstyled text.
  VsdxRichText _inheritMasterText(
    VsdxRichText local,
    VsdxShape proto,
    VsdxCharStyle defaultChar,
    VsdxParaStyle defaultPara,
  ) {
    final protoRich = proto.richText;
    final inheritedText = protoRich.plainText.isNotEmpty
        ? protoRich.plainText
        : (proto.text ?? '');
    if (inheritedText.isEmpty) return local;

    final localStyleOnly =
        local.runs.isNotEmpty && local.runs.every((run) => run.text.isEmpty);
    final List<VsdxTextRun> runs;
    if (localStyleOnly) {
      final style = local.runs.first;
      if (protoRich.plainText.isNotEmpty) {
        runs = <VsdxTextRun>[
          for (final run in protoRich.runs)
            run.copyWith(
              charStyle: style.charStyle,
              paraStyle: style.paraStyle,
            ),
        ];
      } else {
        runs = <VsdxTextRun>[
          style.copyWith(
            text: inheritedText,
            fieldSpans: const <VsdxFieldSpan>[],
            tabIndices: const <int>[],
          ),
        ];
      }
    } else if (protoRich.plainText.isNotEmpty) {
      runs = <VsdxTextRun>[...protoRich.runs];
    } else {
      final style = protoRich.runs.isNotEmpty ? protoRich.runs.first : null;
      runs = <VsdxTextRun>[
        VsdxTextRun(
          text: inheritedText,
          charStyle: style?.charStyle ?? defaultChar,
          paraStyle: style?.paraStyle ?? defaultPara,
        ),
      ];
    }

    return VsdxRichText(
      runs: List<VsdxTextRun>.unmodifiable(runs),
      textBlock: local.textBlock,
      tabSets: local.tabSets,
    );
  }

  /// Collect parametric `F=` for XForm / 1-D / trigger / text-block cells.
  Map<String, String> _readFormulas(
    XmlElement shapeEl,
    Map<String, String>? inherit,
  ) {
    final out = <String, String>{
      if (inherit != null) ...inherit,
    };
    for (final name in _formulaCellNames) {
      final cell = findCell(shapeEl, name);
      if (cell == null) continue;
      final f = cell.getAttribute('F');
      if (f == null || f.trim().isEmpty) {
        // A local literal cell replaces, rather than supplements, the
        // master's formula (notably an instance Width/Height/Pin).
        out.remove(name);
        continue;
      }
      if (isInhFormula(f)) continue;
      out[name] = f;
    }
    return Map.unmodifiable(out);
  }

  VsdxConnectorProps? _readConnectorProps(
    XmlElement shapeEl, {
    VsdxConnectorProps? inherit,
  }) {
    final begCell = findCell(shapeEl, 'BegTrigger');
    final endCell = findCell(shapeEl, 'EndTrigger');
    final beg = (begCell != null && isInhFormula(begCell.getAttribute('F')))
        ? inherit?.begTrigger
        : begCell?.getAttribute('V');
    final end = (endCell != null && isInhFormula(endCell.getAttribute('F')))
        ? inherit?.endTrigger
        : endCell?.getAttribute('V');
    final glue = _int(shapeEl, 'GlueType', inheritFrom: inherit?.glueType) ??
        inherit?.glueType;
    final fixed =
        _int(shapeEl, 'ConFixedCode', inheritFrom: inherit?.conFixedCode) ??
            inherit?.conFixedCode;
    final dyn =
        _int(shapeEl, 'DynFeedback', inheritFrom: inherit?.dynFeedback) ??
            inherit?.dynFeedback;
    final noLive = _readBoolCell(shapeEl, 'NoLiveDynamics',
            inheritFrom: inherit?.noLiveDynamics) ??
        inherit?.noLiveDynamics;
    final jump = _int(shapeEl, 'ConLineJumpCode',
            inheritFrom: inherit?.conLineJumpCode) ??
        inherit?.conLineJumpCode;
    final routeExt = _int(shapeEl, 'ConLineRouteExt',
            inheritFrom: inherit?.conLineRouteExt) ??
        inherit?.conLineRouteExt;
    final jumpStyle = _int(shapeEl, 'ConLineJumpStyle',
            inheritFrom: inherit?.conLineJumpStyle) ??
        inherit?.conLineJumpStyle;
    final jumpDirX = _int(shapeEl, 'ConLineJumpDirX',
            inheritFrom: inherit?.conLineJumpDirX) ??
        inherit?.conLineJumpDirX;
    final jumpDirY = _int(shapeEl, 'ConLineJumpDirY',
            inheritFrom: inherit?.conLineJumpDirY) ??
        inherit?.conLineJumpDirY;
    final route = _int(shapeEl, 'ShapeRouteStyle',
            inheritFrom: inherit?.shapeRouteStyle) ??
        inherit?.shapeRouteStyle;
    final placeFlip =
        _int(shapeEl, 'ShapePlaceFlip', inheritFrom: inherit?.shapePlaceFlip) ??
            inherit?.shapePlaceFlip;
    final props = VsdxConnectorProps(
      begTrigger: (beg == null || beg.isEmpty) ? null : beg,
      endTrigger: (end == null || end.isEmpty) ? null : end,
      glueType: glue,
      conFixedCode: fixed,
      dynFeedback: dyn,
      noLiveDynamics: noLive ?? false,
      conLineJumpCode: jump,
      conLineRouteExt: routeExt,
      conLineJumpStyle: jumpStyle,
      conLineJumpDirX: jumpDirX,
      conLineJumpDirY: jumpDirY,
      shapeRouteStyle: route,
      shapePlaceFlip: placeFlip,
    );
    return props.isEmpty ? null : props;
  }

  /// `<Section N="Field">` — dynamic text field rows (`<fld IX>`).
  List<VsdxFieldRow> _readFields(
    XmlElement shapeEl, {
    List<VsdxFieldRow>? inherit,
  }) {
    final byIx = <int, VsdxFieldRow>{
      if (inherit != null)
        for (final f in inherit) f.ix: f,
    };
    final out = <VsdxFieldRow>[];
    for (final section in shapeEl.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Field') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final ix = int.tryParse(row.getAttribute('IX') ?? '') ?? out.length;
        final proto = byIx[ix];
        final valueCell = findCell(row, 'Value');
        final formatCell = findCell(row, 'Format');
        out.add(VsdxFieldRow(
          ix: ix,
          value: _stringCellOrInherit(valueCell, proto?.value),
          valueFormula: _formulaOrInherit(row, 'Value', proto?.valueFormula),
          format: _stringCellOrInherit(formatCell, proto?.format),
          formatFormula: _formulaOrInherit(row, 'Format', proto?.formatFormula),
          type: _int(row, 'Type', inheritFrom: proto?.type) ?? proto?.type ?? 0,
          uiCat: _int(row, 'UICat', inheritFrom: proto?.uiCat) ?? proto?.uiCat,
          uiCod: _int(row, 'UICod', inheritFrom: proto?.uiCod) ?? proto?.uiCod,
          uiFmt: _int(row, 'UIFmt', inheritFrom: proto?.uiFmt) ?? proto?.uiFmt,
          calendar: _int(row, 'Calendar', inheritFrom: proto?.calendar) ??
              proto?.calendar,
          objectKind: _int(row, 'ObjectKind', inheritFrom: proto?.objectKind) ??
              proto?.objectKind,
        ));
      }
    }
    return List.unmodifiable(out);
  }

  /// `<Section N="Actions">` — context-menu / right-click action rows.
  List<VsdxActionRow> _readActions(
    XmlElement shapeEl, {
    List<VsdxActionRow>? inherit,
  }) {
    final byName = <String, VsdxActionRow>{
      if (inherit != null)
        for (final a in inherit) a.name: a,
    };
    final out = <VsdxActionRow>[];
    for (final section in shapeEl.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Actions') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final name = row.getAttribute('N') ??
            'Row${row.getAttribute('IX') ?? out.length}';
        final ix = int.tryParse(row.getAttribute('IX') ?? '') ?? out.length;
        final proto = byName[name];
        out.add(VsdxActionRow(
          name: name,
          ix: ix,
          menu: _stringCellOrInherit(findCell(row, 'Menu'), proto?.menu),
          action: _stringCellOrInherit(findCell(row, 'Action'), proto?.action),
          actionFormula: _formulaOrInherit(row, 'Action', proto?.actionFormula),
          checked: (_int(row, 'Checked',
                      inheritFrom:
                          proto == null ? null : (proto.checked ? 1 : 0)) ??
                  (proto?.checked == true ? 1 : 0)) !=
              0,
          disabled: (_int(row, 'Disabled',
                      inheritFrom:
                          proto == null ? null : (proto.disabled ? 1 : 0)) ??
                  (proto?.disabled == true ? 1 : 0)) !=
              0,
          readOnly: (_int(row, 'ReadOnly',
                      inheritFrom:
                          proto == null ? null : (proto.readOnly ? 1 : 0)) ??
                  (proto?.readOnly == true ? 1 : 0)) !=
              0,
          invisible: (_int(row, 'Invisible',
                      inheritFrom:
                          proto == null ? null : (proto.invisible ? 1 : 0)) ??
                  (proto?.invisible == true ? 1 : 0)) !=
              0,
          tag: _stringCellOrInherit(findCell(row, 'Tag'), proto?.tag),
          buttonFace: _int(row, 'ButtonFace', inheritFrom: proto?.buttonFace) ??
              proto?.buttonFace ??
              0,
          sortKey:
              _stringCellOrInherit(findCell(row, 'SortKey'), proto?.sortKey),
        ));
      }
    }
    return List.unmodifiable(out);
  }

  /// Read a string cell; `F=Inh` / missing → [inherit].
  static String? _stringCellOrInherit(XmlElement? cell, String? inherit) {
    if (cell == null) return inherit;
    if (isInhFormula(cell.getAttribute('F'))) return inherit;
    return cell.getAttribute('V');
  }

  /// Resolve a shape's `<ForeignData>` reference to an absolute part name.
  /// Returns `null` when the shape has no foreign data or when the parser
  /// wasn't given a rels map (page-less parser used by Master parsing).
  String? _resolveForeignDataPart(XmlElement shapeEl) {
    final rels = _imageRels;
    if (rels == null || rels.isEmpty) return null;
    for (final child in shapeEl.childElements) {
      if (child.name.local != 'ForeignData') continue;
      for (final rel in child.childElements) {
        if (rel.name.local != 'Rel') continue;
        final rId = rel.getAttribute('r:id') ??
            rel.getAttribute('id') ??
            rel.getAttribute('Id');
        if (rId == null) continue;
        return rels[rId];
      }
    }
    return null;
  }

  /// `(ForeignType, CompressionType)` attributes on `<ForeignData>`.
  (String?, String?) _readForeignDataMeta(XmlElement shapeEl) {
    for (final child in shapeEl.childElements) {
      if (child.name.local != 'ForeignData') continue;
      final type = child.getAttribute('ForeignType');
      final compression = child.getAttribute('CompressionType');
      return (
        (type == null || type.isEmpty) ? null : type,
        (compression == null || compression.isEmpty) ? null : compression,
      );
    }
    return (null, null);
  }

  /// Read `<Section N="Connection">` rows into shape-local connection points
  /// (X/Y in inches, in row order). Empty when the shape has no such section.
  List<VsdxConnectionPoint> _readConnectionPoints(
    XmlElement shapeEl, {
    List<VsdxConnectionPoint>? inherit,
  }) {
    final out = <VsdxConnectionPoint>[];
    for (final section in shapeEl.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Connection') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final proto = (inherit != null && out.length < inherit.length)
            ? inherit[out.length]
            : null;
        final x = readLengthInches(row, 'X', inheritFrom: proto?.x) ?? proto?.x;
        final y = readLengthInches(row, 'Y', inheritFrom: proto?.y) ?? proto?.y;
        if (x == null || y == null) continue;
        final dirX = _double(row, 'DirX', inheritFrom: proto?.dirX) ??
            proto?.dirX ??
            0.0;
        final dirY = _double(row, 'DirY', inheritFrom: proto?.dirY) ??
            proto?.dirY ??
            0.0;
        final type =
            _int(row, 'Type', inheritFrom: proto?.type) ?? proto?.type ?? 0;
        final autoGen = (_int(row, 'AutoGen',
                    inheritFrom:
                        proto == null ? null : (proto.autoGen ? 1 : 0)) ??
                (proto?.autoGen == true ? 1 : 0)) !=
            0;
        final promptCell = findCell(row, 'Prompt');
        final prompt = () {
          if (promptCell == null) return proto?.prompt;
          if (isInhFormula(promptCell.getAttribute('F'))) return proto?.prompt;
          final p = promptCell.getAttribute('V');
          return (p == null || p.isEmpty) ? null : p;
        }();
        out.add(VsdxConnectionPoint(
          x,
          y,
          dirX: dirX,
          dirY: dirY,
          type: type,
          autoGen: autoGen,
          prompt: prompt,
          xFormula: _formulaOrInherit(row, 'X', proto?.xFormula),
          yFormula: _formulaOrInherit(row, 'Y', proto?.yFormula),
        ));
      }
    }
    return List.unmodifiable(out);
  }

  static double? _double(XmlElement parent, String name,
      {double? inheritFrom}) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    if (isInhFormula(cell.getAttribute('F'))) {
      if (inheritFrom != null) return inheritFrom;
    }
    return double.tryParse(cell.getAttribute('V') ?? '');
  }

  static int? _int(XmlElement parent, String name, {int? inheritFrom}) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    if (isInhFormula(cell.getAttribute('F'))) {
      if (inheritFrom != null) return inheritFrom;
    }
    return int.tryParse(cell.getAttribute('V') ?? '');
  }

  bool? _readBoolCell(XmlElement parent, String name, {bool? inheritFrom}) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    if (isInhFormula(cell.getAttribute('F'))) {
      if (inheritFrom != null) return inheritFrom;
    }
    final v = cell.getAttribute('V');
    if (v == null) return null;
    return v == '1' || v.toLowerCase() == 'true';
  }

  static XmlElement? _firstChildLocal(XmlElement parent, String local) {
    for (final el in parent.childElements) {
      if (el.name.local == local) return el;
    }
    return null;
  }
}
