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
    Map<String, String>? imageRels,
  })  : _geometry = geometry,
        _style = style,
        _richText = richText,
        _masters = masters,
        _imageRels = imageRels;

  final GeometryParser _geometry;
  final StyleParser _style;
  final RichTextParser _richText;
  final MasterRegistry _masters;

  /// Optional mapping `rId → absolute media part name` for `<ForeignData>`
  /// references on this page. The PagesParser injects it per page.
  final Map<String, String>? _imageRels;

  /// Spawn a sibling parser configured with a different rich-text field
  /// resolver — used by the PagesParser to push page-specific values
  /// (page name, page index, total pages) before parsing shapes.
  PageParser withFieldResolver(FieldResolver resolver) => PageParser(
        geometry: _geometry,
        style: _style,
        richText: _richText.withFieldResolver(resolver),
        masters: _masters,
        imageRels: _imageRels,
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
    final VsdxShape? proto;
    if (masterId != null) {
      proto = master?.prototype;
    } else {
      final masterShapeStr = shapeEl.getAttribute('MasterShape');
      final masterShapeId =
          masterShapeStr == null ? null : int.tryParse(masterShapeStr);
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
    if (geometries.isEmpty && proto != null) {
      geometries = proto.geometries;
    }

    final fill = _style.parseFill(
      shapeEl,
      defaults: proto?.fill ?? VsdxFill.defaultFill,
    );
    final line = _style.parseLine(
      shapeEl,
      defaults: proto?.line ?? VsdxLine.defaultLine,
    );
    final shadow = _style.parseShadow(
      shapeEl,
      defaults: proto?.shadow ?? VsdxShadow.disabled,
    );
    final glow = _style.parseGlow(
      shapeEl,
      defaults: proto?.glow ?? VsdxGlow.disabled,
    );
    final reflection = _style.parseReflection(
      shapeEl,
      defaults: proto?.reflection ?? VsdxReflection.disabled,
    );

    final richText = _richText.parse(
      shapeEl,
      defaultChar: proto?.richText.runs.isNotEmpty == true
          ? proto!.richText.runs.first.charStyle
          : VsdxCharStyle.defaults,
      defaultPara: proto?.richText.runs.isNotEmpty == true
          ? proto!.richText.runs.first.paraStyle
          : VsdxParaStyle.defaults,
    );
    final effectiveRich = richText.runs.isEmpty &&
            proto != null &&
            proto.richText.runs.isNotEmpty
        ? proto.richText
        : richText;
    final plain = readShapeText(shapeEl) ??
        (effectiveRich.runs.isEmpty ? null : effectiveRich.plainText) ??
        proto?.text;

    final layerMembers = LayerParser.parseLayerMembers(shapeEl);
    final imagePartName = _resolveForeignDataPart(shapeEl) ??
        proto?.imagePartName;
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
    final masterName = masterId != null
        ? (master?.name ?? proto?.masterName)
        : proto?.masterName;

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
      connectionPoints: connectionPoints,
      hyperlinks: hyperlinks,
      userProperties: props,
      userCells: userCells,
      masterName: masterName,
      shapeKind: shapeKind,
    );
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

  /// Read `<Section N="Connection">` rows into shape-local connection points
  /// (X/Y in inches, in row order). Empty when the shape has no such section.
  List<Offset2D> _readConnectionPoints(XmlElement shapeEl) {
    final out = <Offset2D>[];
    for (final section in shapeEl.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Connection') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final x = readLengthInches(row, 'X');
        final y = readLengthInches(row, 'Y');
        if (x == null || y == null) continue;
        out.add(Offset2D(x, y));
      }
    }
    return List.unmodifiable(out);
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
