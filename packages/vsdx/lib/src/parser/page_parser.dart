/// Parses a single `pageN.xml` part into a list of [VsdxShape].
///
/// M0/M1 scope: extract the absolute essentials needed for the placeholder
/// renderer (id, name, pin, size, angle, plain text, sub-shapes). Style,
/// geometry, master inheritance and richtext arrive in M2/M3/M6.
library;

import 'package:logging/logging.dart';
import 'package:xml/xml.dart';

import '../core/exceptions.dart';
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
  }) {
    final idStr = shapeEl.getAttribute('ID');
    final id = idStr == null ? -1 : int.tryParse(idStr) ?? -1;
    final nameU = shapeEl.getAttribute('NameU') ??
        shapeEl.getAttribute('Name') ??
        'Sheet.$id';

    // Resolve the inheritance prototype up front; subsequent reads use its
    // geometry / fill / line / text as defaults. `Master="M"` binds a whole
    // subtree to master M and inherits its top shape; a nested `MasterShape="N"`
    // (no Master) inherits the master sub-shape N from that same context
    // (Visio / libvisio resolve instance sub-shapes this way).
    final masterIdStr = shapeEl.getAttribute('Master');
    final masterId = masterIdStr == null ? null : int.tryParse(masterIdStr);
    final master = masterId != null ? _masters.find(masterId) : inheritedMaster;
    final masterShapeStr = shapeEl.getAttribute('MasterShape');
    final masterShapeId =
        masterShapeStr == null ? null : int.tryParse(masterShapeStr);
    final VsdxShape? proto;
    if (masterId != null) {
      proto = master?.prototype;
    } else {
      proto = (masterShapeId != null && master != null)
          ? master.findShape(masterShapeId)
          : null;
    }

    final pinX = readLengthInches(shapeEl, 'PinX', inheritFrom: proto?.pinX) ??
        proto?.pinX ??
        0;
    final pinY = readLengthInches(shapeEl, 'PinY', inheritFrom: proto?.pinY) ??
        proto?.pinY ??
        0;
    final width = readLengthInches(shapeEl, 'Width', inheritFrom: proto?.width) ??
        proto?.width ??
        1.0;
    final height =
        readLengthInches(shapeEl, 'Height', inheritFrom: proto?.height) ??
            proto?.height ??
            1.0;
    // LocPinX/LocPinY — the in-shape point that sits on the pin (and the
    // rotation centre). Usually the centre for 2-D shapes, but connectors and
    // some stencils pin off-centre; keep it so geometry maps to the right spot.
    final locPinX =
        readLengthInches(shapeEl, 'LocPinX', inheritFrom: proto?.locPinXInches) ??
            proto?.locPinXInches;
    final locPinY =
        readLengthInches(shapeEl, 'LocPinY', inheritFrom: proto?.locPinYInches) ??
            proto?.locPinYInches;
    final angleRad =
        readAngleRadians(shapeEl, 'Angle', inheritFrom: proto?.angleRad) ??
            proto?.angleRad ??
            0.0;
    final flipX = _readBoolCell(shapeEl, 'FlipX') ?? proto?.flipX ?? false;
    final flipY = _readBoolCell(shapeEl, 'FlipY') ?? proto?.flipY ?? false;
    // drawio-style "locked": read back the canonical protection bit written by
    // the writer (a shape is treated as locked when its move is locked).
    final locked = _readBoolCell(shapeEl, 'LockMoveX') ?? proto?.locked ?? false;

    final shapeTypeAttr = shapeEl.getAttribute('Type');
    final has1DEndpoints = findCell(shapeEl, 'BeginX') != null ||
        findCell(shapeEl, 'EndX') != null;
    final is1D = shapeTypeAttr == 'Shape' && has1DEndpoints ||
        proto?.is1D == true;
    final beginX = readLengthInches(shapeEl, 'BeginX') ?? proto?.beginX;
    final beginY = readLengthInches(shapeEl, 'BeginY') ?? proto?.beginY;
    final endX = readLengthInches(shapeEl, 'EndX') ?? proto?.endX;
    final endY = readLengthInches(shapeEl, 'EndY') ?? proto?.endY;

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
          );

    var geometries = _geometry.parse(shapeEl);
    if (proto != null && proto.geometries.isNotEmpty) {
      // Inherit master geometry by IX: instance rows override same-IX master
      // rows, `Del` removes them, and section flags inherit unless overridden
      // (mirrors libvisio's per-IX geometry inheritance).
      geometries = GeometryParser.mergeInherited(proto.geometries, geometries);
    }

    // Picture / Foreign shapes typically have no fill or stroke; when the
    // cells are absent (older writers omitted them), default to pattern 0
    // rather than Visio's solid defaults so round-trips stay visually empty.
    final isForeign = shapeTypeAttr == 'Foreign';
    final fill = _style.parseFill(
      shapeEl,
      defaults: proto?.fill ??
          (isForeign ? const VsdxFill(pattern: 0) : VsdxFill.defaultFill),
    );
    final lineStyleId = int.tryParse(shapeEl.getAttribute('LineStyle') ?? '') ??
        proto?.lineStyleId;
    final sheetLine =
        lineStyleId != null ? _stylesheets.resolveLine(lineStyleId) : null;
    final line = _style.parseLine(
      shapeEl,
      defaults: proto?.line ??
          sheetLine ??
          (isForeign ? const VsdxLine(pattern: 0) : VsdxLine.defaultLine),
    );
    final shadow = _style.parseShadow(
      shapeEl,
      defaults: proto?.shadow ?? VsdxShadow.disabled,
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
    //   2. master prototype Character / seeded TextStyle
    //   3. document DefaultTextStyle
    // Do NOT apply DefaultTextStyle when the shape only has a Master — that
    // would wipe Connector=8pt / stencil Character=10pt with Normal=12pt.
    final ownTextStyleId =
        int.tryParse(shapeEl.getAttribute('TextStyle') ?? '');
    final fillStyleId = int.tryParse(shapeEl.getAttribute('FillStyle') ?? '') ??
        proto?.fillStyleId;
    final textStyleId = ownTextStyleId ?? proto?.textStyleId;
    final sheetChar = ownTextStyleId != null
        ? _stylesheets.resolveCharStyle(ownTextStyleId)
        : null;
    final protoChar = proto?.richText.runs.isNotEmpty == true
        ? proto!.richText.runs.first.charStyle
        : null;
    final defaultChar = sheetChar ??
        protoChar ??
        _stylesheets.resolveCharStyle(null) ??
        VsdxCharStyle.defaults;
    final defaultPara = proto?.richText.runs.isNotEmpty == true
        ? proto!.richText.runs.first.paraStyle
        : VsdxParaStyle.defaults;

    var richText = _richText.parse(
      shapeEl,
      defaultChar: defaultChar,
      defaultPara: defaultPara,
      // Inherit the Master's text-block transform (TxtAngle, TxtPin/LocPin,
      // vertical align, …) so shapes that leave their text orientation on the
      // Master aren't forced back to horizontal.
      defaultBlock: proto?.richText.textBlock ?? VsdxTextBlock.defaults,
    );
    // Masters often carry TextStyle but no <Text>. Seed an empty run so
    // instance shapes that inherit the prototype pick up the stylesheet size
    // (libvisio does the same via the master's TextStyle attribute).
    // (Character-without-Text is already seeded inside RichTextParser.)
    if (richText.runs.isEmpty && sheetChar != null) {
      richText = VsdxRichText(
        runs: <VsdxTextRun>[VsdxTextRun(text: '', charStyle: sheetChar)],
        textBlock: richText.textBlock,
      );
    }
    final effectiveRich = richText.runs.isEmpty &&
            proto != null &&
            proto.richText.runs.isNotEmpty
        ? proto.richText
        : richText;
    final plain = readShapeText(shapeEl) ??
        (effectiveRich.runs.isEmpty
            ? null
            : (effectiveRich.plainText.isEmpty
                ? null
                : effectiveRich.plainText)) ??
        proto?.text;

    final layerMembers = LayerParser.parseLayerMembers(shapeEl);
    final imagePartName = _resolveForeignDataPart(shapeEl) ??
        proto?.imagePartName;
    final foreignMeta = _readForeignDataMeta(shapeEl);
    final foreignType = foreignMeta.$1 ?? proto?.foreignType;
    final foreignCompressionType =
        foreignMeta.$2 ?? proto?.foreignCompressionType;
    // Image Properties (MS-VSDX §2.2.6) — top-level cells on Foreign shapes.
    final imgOffsetX = readLengthInches(shapeEl, 'ImgOffsetX') ??
        _double(shapeEl, 'ImgOffsetX') ??
        proto?.imgOffsetXInches ??
        0.0;
    final imgOffsetY = readLengthInches(shapeEl, 'ImgOffsetY') ??
        _double(shapeEl, 'ImgOffsetY') ??
        proto?.imgOffsetYInches ??
        0.0;
    final imgWidth = readLengthInches(shapeEl, 'ImgWidth') ??
        _double(shapeEl, 'ImgWidth') ??
        proto?.imgWidthInches;
    final imgHeight = readLengthInches(shapeEl, 'ImgHeight') ??
        _double(shapeEl, 'ImgHeight') ??
        proto?.imgHeightInches;
    // Top-level Image `Transparency` (not Character-row Transparency).
    final imageTransparency = (_double(shapeEl, 'Transparency') ??
            proto?.imageTransparency ??
            0.0)
        .clamp(0.0, 1.0);
    final imageBlur =
        (_double(shapeEl, 'Blur') ?? proto?.imageBlur ?? 0.0).clamp(0.0, 1.0);
    final imageBrightness =
        (_double(shapeEl, 'Brightness') ?? proto?.imageBrightness ?? 0.5)
            .clamp(0.0, 1.0);
    final imageContrast =
        (_double(shapeEl, 'Contrast') ?? proto?.imageContrast ?? 0.5)
            .clamp(0.0, 1.0);
    final ownConnPts = _readConnectionPoints(shapeEl);
    final connectionPoints = ownConnPts.isEmpty && proto != null
        ? proto.connectionPoints
        : ownConnPts;
    final ownHyperlinks = const HyperlinkParser().parse(shapeEl);
    final hyperlinks =
        ownHyperlinks.isEmpty && proto != null ? proto.hyperlinks : ownHyperlinks;

    const userParser = UserPropertyParser();
    final ownProps = userParser.parseProperties(shapeEl);
    final props = ownProps.isEmpty && proto != null
        ? proto.userProperties
        : ownProps;
    final ownUserCells = userParser.parseUserCells(shapeEl);
    final userCells = ownUserCells.isEmpty && proto != null
        ? proto.userCells
        : ownUserCells;
    final ownControls = _readControls(shapeEl);
    final controls =
        ownControls.isEmpty && proto != null ? proto.controls : ownControls;
    final ownScratch = _readScratch(shapeEl);
    final scratch =
        ownScratch.isEmpty && proto != null ? proto.scratch : ownScratch;
    final ownFields = _readFields(shapeEl);
    final fields =
        ownFields.isEmpty && proto != null ? proto.fields : ownFields;
    final ownActions = _readActions(shapeEl);
    final actions =
        ownActions.isEmpty && proto != null ? proto.actions : ownActions;
    final masterName = masterId != null
        ? (master?.name ?? proto?.masterName)
        : proto?.masterName;

    final formulas = _readFormulas(shapeEl, proto?.formulas);
    final connectorProps = _readConnectorProps(shapeEl) ?? proto?.connectorProps;

    const kindDetector = ShapeKindDetector();
    final shapeKind = kindDetector.detect(
      xmlType: shapeTypeAttr,
      name: nameU,
      masterName: masterName,
      is1D: is1D,
      hasImage: imagePartName != null,
      childCount: children.length,
      userProperties: props,
    );

    return VsdxShape(
      id: id,
      name: nameU,
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      locPinXInches: locPinX,
      locPinYInches: locPinY,
      angleRad: angleRad,
      text: plain,
      richText: effectiveRich,
      children: children,
      geometries: geometries,
      fill: fill,
      line: line,
      shadow: shadow,
      glow: glow,
      reflection: reflection,
      layerMemberIds: layerMembers.isEmpty && proto != null
          ? proto.layerMemberIds
          : layerMembers,
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
      objType: _int(shapeEl, 'ObjType') ?? proto?.objType,
      resizeMode: _int(shapeEl, 'ResizeMode') ?? proto?.resizeMode,
      eventDblClick: findCell(shapeEl, 'EventDblClick')?.getAttribute('V') ??
          proto?.eventDblClick,
      noAlignBox: _readBoolCell(shapeEl, 'NoAlignBox') ??
          proto?.noAlignBox ??
          false,
      shapeSplittable: _readBoolCell(shapeEl, 'ShapeSplittable') ??
          proto?.shapeSplittable ??
          false,
      themeIndex: _int(shapeEl, 'ThemeIndex') ?? proto?.themeIndex,
      quickStyleFillMatrix:
          _int(shapeEl, 'QuickStyleFillMatrix') ?? proto?.quickStyleFillMatrix,
      quickStyleLineMatrix:
          _int(shapeEl, 'QuickStyleLineMatrix') ?? proto?.quickStyleLineMatrix,
      quickStyleEffectsMatrix: _int(shapeEl, 'QuickStyleEffectsMatrix') ??
          proto?.quickStyleEffectsMatrix,
      quickStyleFontMatrix:
          _int(shapeEl, 'QuickStyleFontMatrix') ?? proto?.quickStyleFontMatrix,
      isTextEditTarget: _readBoolCell(shapeEl, 'IsTextEditTarget') ??
          proto?.isTextEditTarget ??
          false,
      dontMoveChildren: _readBoolCell(shapeEl, 'DontMoveChildren') ??
          proto?.dontMoveChildren ??
          false,
      selectMode: _int(shapeEl, 'SelectMode') ?? proto?.selectMode,
      displayMode: _int(shapeEl, 'DisplayMode') ?? proto?.displayMode,
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
    ).restoreRouteState();
  }

  /// `<Section N="Control">` — named handle rows (libvisio / MS-VSDX).
  /// Accepts Visio `XDyn`/`XCon` names and Lucidchart `DynX`/`ConX` aliases.
  List<VsdxControlRow> _readControls(XmlElement shapeEl) {
    final out = <VsdxControlRow>[];
    for (final section in shapeEl.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Control') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final name = row.getAttribute('N');
        if (name == null || name.isEmpty) continue;
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
          x: _double(row, 'X') ?? 0,
          y: _double(row, 'Y') ?? 0,
          conX: _double(row, conXName) ?? _double(row, 'ConX') ?? 0,
          conY: _double(row, conYName) ?? _double(row, 'ConY') ?? 0,
          dynX: _double(row, dynXName) ?? _double(row, 'DynX') ?? 0,
          dynY: _double(row, dynYName) ?? _double(row, 'DynY') ?? 0,
          xFormula: _formula(row, 'X'),
          yFormula: _formula(row, 'Y'),
          dynXFormula: _formula(row, dynXName) ?? _formula(row, 'DynX'),
          dynYFormula: _formula(row, dynYName) ?? _formula(row, 'DynY'),
          conXFormula: _formula(row, conXName) ?? _formula(row, 'ConX'),
          conYFormula: _formula(row, conYName) ?? _formula(row, 'ConY'),
          canGlue: (_int(row, 'CanGlue') ?? 0) != 0,
          prompt: () {
            final p = findCell(row, 'Prompt')?.getAttribute('V');
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
  List<VsdxScratchRow> _readScratch(XmlElement shapeEl) {
    final out = <VsdxScratchRow>[];
    for (final section in shapeEl.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Scratch') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final ix = int.tryParse(row.getAttribute('IX') ?? '') ?? out.length;
        out.add(VsdxScratchRow(
          ix: ix,
          x: readLengthInches(row, 'X') ?? _double(row, 'X') ?? 0,
          y: readLengthInches(row, 'Y') ?? _double(row, 'Y') ?? 0,
          a: readLengthInches(row, 'A') ?? _double(row, 'A') ?? 0,
          b: readLengthInches(row, 'B') ?? _double(row, 'B') ?? 0,
          c: readLengthInches(row, 'C') ?? _double(row, 'C') ?? 0,
          d: readLengthInches(row, 'D') ?? _double(row, 'D') ?? 0,
          xFormula: _formula(row, 'X'),
          yFormula: _formula(row, 'Y'),
          aFormula: _formula(row, 'A'),
          bFormula: _formula(row, 'B'),
          cFormula: _formula(row, 'C'),
          dFormula: _formula(row, 'D'),
        ));
      }
    }
    return List.unmodifiable(out);
  }

  static String? _formula(XmlElement parent, String name) {
    final cell = findCell(parent, name);
    final f = cell?.getAttribute('F');
    if (f == null || f.isEmpty || f == 'No Formula') return null;
    return f;
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
    'EventDblClick',
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

  /// Collect parametric `F=` for XForm / 1-D / trigger / text-block cells.
  Map<String, String> _readFormulas(
    XmlElement shapeEl,
    Map<String, String>? inherit,
  ) {
    final out = <String, String>{
      if (inherit != null) ...inherit,
    };
    for (final name in _formulaCellNames) {
      final f = _formula(shapeEl, name);
      if (f != null) out[name] = f;
    }
    return Map.unmodifiable(out);
  }

  VsdxConnectorProps? _readConnectorProps(XmlElement shapeEl) {
    final beg = findCell(shapeEl, 'BegTrigger')?.getAttribute('V');
    final end = findCell(shapeEl, 'EndTrigger')?.getAttribute('V');
    final glue = _int(shapeEl, 'GlueType');
    final fixed = _int(shapeEl, 'ConFixedCode');
    final dyn = _int(shapeEl, 'DynFeedback');
    final noLive = _readBoolCell(shapeEl, 'NoLiveDynamics');
    final jump = _int(shapeEl, 'ConLineJumpCode');
    final routeExt = _int(shapeEl, 'ConLineRouteExt');
    final jumpStyle = _int(shapeEl, 'ConLineJumpStyle');
    final jumpDirX = _int(shapeEl, 'ConLineJumpDirX');
    final jumpDirY = _int(shapeEl, 'ConLineJumpDirY');
    final route = _int(shapeEl, 'ShapeRouteStyle');
    final placeFlip = _int(shapeEl, 'ShapePlaceFlip');
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
  List<VsdxFieldRow> _readFields(XmlElement shapeEl) {
    final out = <VsdxFieldRow>[];
    for (final section in shapeEl.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Field') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final ix = int.tryParse(row.getAttribute('IX') ?? '') ?? out.length;
        final valueCell = findCell(row, 'Value');
        final formatCell = findCell(row, 'Format');
        out.add(VsdxFieldRow(
          ix: ix,
          value: valueCell?.getAttribute('V'),
          valueFormula: _formula(row, 'Value'),
          format: formatCell?.getAttribute('V'),
          formatFormula: _formula(row, 'Format'),
          type: _int(row, 'Type') ?? 0,
          uiCat: _int(row, 'UICat'),
          uiCod: _int(row, 'UICod'),
          uiFmt: _int(row, 'UIFmt'),
          calendar: _int(row, 'Calendar'),
          objectKind: _int(row, 'ObjectKind'),
        ));
      }
    }
    return List.unmodifiable(out);
  }

  /// `<Section N="Actions">` — context-menu / right-click action rows.
  List<VsdxActionRow> _readActions(XmlElement shapeEl) {
    final out = <VsdxActionRow>[];
    for (final section in shapeEl.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Actions') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final name = row.getAttribute('N') ??
            'Row${row.getAttribute('IX') ?? out.length}';
        final ix = int.tryParse(row.getAttribute('IX') ?? '') ?? out.length;
        out.add(VsdxActionRow(
          name: name,
          ix: ix,
          menu: findCell(row, 'Menu')?.getAttribute('V'),
          action: findCell(row, 'Action')?.getAttribute('V'),
          actionFormula: _formula(row, 'Action'),
          checked: (_int(row, 'Checked') ?? 0) != 0,
          disabled: (_int(row, 'Disabled') ?? 0) != 0,
          readOnly: (_int(row, 'ReadOnly') ?? 0) != 0,
          invisible: (_int(row, 'Invisible') ?? 0) != 0,
          tag: findCell(row, 'Tag')?.getAttribute('V'),
          buttonFace: _int(row, 'ButtonFace') ?? 0,
          sortKey: findCell(row, 'SortKey')?.getAttribute('V'),
        ));
      }
    }
    return List.unmodifiable(out);
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
  List<VsdxConnectionPoint> _readConnectionPoints(XmlElement shapeEl) {
    final out = <VsdxConnectionPoint>[];
    for (final section in shapeEl.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Connection') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final x = readLengthInches(row, 'X');
        final y = readLengthInches(row, 'Y');
        if (x == null || y == null) continue;
        final dirX = _double(row, 'DirX') ?? 0.0;
        final dirY = _double(row, 'DirY') ?? 0.0;
        final type = _int(row, 'Type') ?? 0;
        final autoGen = (_int(row, 'AutoGen') ?? 0) != 0;
        final promptCell = findCell(row, 'Prompt');
        final prompt = promptCell?.getAttribute('V');
        out.add(VsdxConnectionPoint(
          x,
          y,
          dirX: dirX,
          dirY: dirY,
          type: type,
          autoGen: autoGen,
          prompt: (prompt == null || prompt.isEmpty) ? null : prompt,
          xFormula: _formula(row, 'X'),
          yFormula: _formula(row, 'Y'),
        ));
      }
    }
    return List.unmodifiable(out);
  }

  static double? _double(XmlElement parent, String name) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    return double.tryParse(cell.getAttribute('V') ?? '');
  }

  static int? _int(XmlElement parent, String name) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    return int.tryParse(cell.getAttribute('V') ?? '');
  }

  bool? _readBoolCell(XmlElement parent, String name) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
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
