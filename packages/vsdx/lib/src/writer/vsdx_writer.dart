/// Serialises an edited [VsdxDocument] back to a `.vsdx` byte buffer using the
/// **load-preserve-patch** strategy (see `docs/VSDX_WRITE.md`):
///
///  * Every part of the original package is copied through verbatim.
///  * Only the `visio/pages/pageN.xml` parts that contain edited shapes are
///    re-serialised, and within them only the `<Cell>`s whose value actually
///    changed are rewritten — formulas on untouched cells are preserved.
///
/// This keeps masters, themes, styles, media, unknown parts and formulas
/// intact, which a full "re-emit the semantic model" writer could not.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../model/connect.dart';
import '../model/document.dart';
import '../model/geometry.dart';
import '../model/layer.dart';
import '../model/page.dart';
import '../model/shape.dart';
import '../parser/document_parser.dart';
import '../parser/package_reader.dart';
import '../parser/relationships.dart';
import '../utils/color.dart';
import '../utils/units.dart';

class VsdxWriter {
  const VsdxWriter();

  /// Values within this many inches / radians of the baseline are treated as
  /// unchanged and left alone (preserving any original formula).
  static const double _epsilon = 1e-6;

  /// Write [edited] back over [originalBytes], returning the new `.vsdx` bytes.
  ///
  /// [originalBytes] must be the buffer [edited] was originally parsed from;
  /// the writer re-parses it as the baseline to diff against and as the source
  /// of every untouched part.
  Uint8List write({
    required Uint8List originalBytes,
    required VsdxDocument edited,
  }) {
    final baseline = const DocumentParser().parse(originalBytes);
    final pkg = VsdxPackage.open(originalBytes);
    final resolver = RelationshipResolver(pkg);

    final docPart = pkg.resolveDocumentPartName();
    final pagesPart = resolver.singleTargetOfType(docPart, VsdxRelType.pages);
    final pagesXml = pagesPart == null ? null : pkg.readPartXml(pagesPart);
    final pagePartByIndex = (pagesPart != null && pagesXml != null)
        ? _resolvePagePartsFrom(pagesXml, pagesPart, resolver)
        : const <int, String>{};

    final patched = <String, Uint8List>{}; // archive name (no slash) -> bytes
    final pages = edited.pages.length;
    for (var i = 0; i < pages && i < baseline.pages.length; i++) {
      final partName = pagePartByIndex[i];
      if (partName == null) continue;
      final xml = pkg.readPartXml(partName);
      if (xml == null) continue;
      if (_patchPage(xml, baseline.pages[i], edited.pages[i])) {
        patched[_noSlash(partName)] = Uint8List.fromList(
          utf8.encode(xml.toXmlString()),
        );
      }
    }

    // Layer visibility / lock / print lives on the PageSheet inside pages.xml.
    if (pagesPart != null &&
        pagesXml != null &&
        _patchLayers(pagesXml, baseline, edited)) {
      patched[_noSlash(pagesPart)] =
          Uint8List.fromList(utf8.encode(pagesXml.toXmlString()));
    }

    return _rezip(originalBytes, patched);
  }

  // --- Emit-from-scratch (new blank document) --------------------------------

  static const String _mainNs =
      'http://schemas.microsoft.com/office/visio/2012/main';
  static const String _relNs =
      'http://schemas.openxmlformats.org/package/2006/relationships';
  static const String _officeRelNs =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  /// Generate a minimal, valid blank `.vsdx` (one empty page). Used as the
  /// base for "New drawing": the editor parses it, then normal
  /// load-preserve-patch saves append the user's shapes into `page1.xml`.
  Uint8List emptyDocument({
    double widthInches = 8.5,
    double heightInches = 11.0,
  }) {
    const decl = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
    final parts = <String, String>{
      '[Content_Types].xml': '$decl\n'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/visio/document.xml" ContentType="application/vnd.ms-visio.drawing.main+xml"/>'
          '<Override PartName="/visio/pages/pages.xml" ContentType="application/vnd.ms-visio.pages+xml"/>'
          '<Override PartName="/visio/pages/page1.xml" ContentType="application/vnd.ms-visio.page+xml"/>'
          '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
          '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
          '</Types>',
      '_rels/.rels': '$decl\n'
          '<Relationships xmlns="$_relNs">'
          '<Relationship Id="rId1" Type="http://schemas.microsoft.com/visio/2010/relationships/document" Target="visio/document.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
          '<Relationship Id="rId3" Type="$_officeRelNs/extended-properties" Target="docProps/app.xml"/>'
          '</Relationships>',
      'docProps/core.xml': '$decl\n'
          '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">'
          '<dc:creator>Editor for Visio Diagrams</dc:creator></cp:coreProperties>',
      'docProps/app.xml': '$decl\n'
          '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
          '<Application>Editor for Visio Diagrams</Application></Properties>',
      'visio/document.xml': '$decl\n'
          '<VisioDocument xmlns="$_mainNs" xmlns:r="$_officeRelNs">'
          '<DocumentSettings TopPage="0" DefaultTextStyle="0" DefaultLineStyle="0" DefaultFillStyle="0" DefaultGuideStyle="0"/>'
          '</VisioDocument>',
      'visio/_rels/document.xml.rels': '$decl\n'
          '<Relationships xmlns="$_relNs">'
          '<Relationship Id="rId1" Type="http://schemas.microsoft.com/visio/2010/relationships/pages" Target="pages/pages.xml"/>'
          '</Relationships>',
      'visio/pages/pages.xml': '$decl\n'
          '<Pages xmlns="$_mainNs" xmlns:r="$_officeRelNs">'
          '<Page ID="0" NameU="Page-1" Name="Page-1">'
          '<PageSheet>'
          '<Cell N="PageWidth" V="${_fmt(widthInches)}"/>'
          '<Cell N="PageHeight" V="${_fmt(heightInches)}"/>'
          '</PageSheet>'
          '<Rel r:id="rId1"/>'
          '</Page></Pages>',
      'visio/pages/_rels/pages.xml.rels': '$decl\n'
          '<Relationships xmlns="$_relNs">'
          '<Relationship Id="rId1" Type="http://schemas.microsoft.com/visio/2010/relationships/page" Target="page1.xml"/>'
          '</Relationships>',
      'visio/pages/page1.xml': '$decl\n'
          '<PageContents xmlns="$_mainNs" xmlns:r="$_officeRelNs"><Shapes/></PageContents>',
    };

    final archive = Archive();
    parts.forEach((name, xml) {
      final bytes = utf8.encode(xml);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    });
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw StateError('Failed to encode blank .vsdx');
    }
    return Uint8List.fromList(encoded);
  }

  // --- Page/part resolution --------------------------------------------------

  Map<int, String> _resolvePagePartsFrom(
    XmlDocument pagesXml,
    String pagesPart,
    RelationshipResolver resolver,
  ) {
    final out = <int, String>{};
    final pageEls = pagesXml.rootElement.childElements
        .where((el) => el.name.local == 'Page')
        .toList(growable: false);
    for (var i = 0; i < pageEls.length; i++) {
      final relEl = _firstChild(pageEls[i], 'Rel');
      if (relEl == null) continue;
      final rId = relEl.getAttribute('r:id') ??
          relEl.getAttribute('id') ??
          relEl.getAttribute('Id');
      if (rId == null) continue;
      final target = resolver.followById(pagesPart, rId);
      if (target != null) out[i] = target;
    }
    return out;
  }

  /// Patch layer Visible / Lock / Print cells on each page's PageSheet when
  /// they changed vs the baseline. Returns whether anything was written.
  bool _patchLayers(
    XmlDocument pagesXml,
    VsdxDocument baseline,
    VsdxDocument edited,
  ) {
    var changed = false;
    final pageEls = pagesXml.rootElement.childElements
        .where((el) => el.name.local == 'Page')
        .toList(growable: false);
    final n = math.min(
      pageEls.length,
      math.min(baseline.pages.length, edited.pages.length),
    );
    for (var i = 0; i < n; i++) {
      final baseLayers = baseline.pages[i].layers;
      final editLayers = edited.pages[i].layers;
      if (_layersEqual(baseLayers, editLayers)) continue;
      final pageSheet = _firstChild(pageEls[i], 'PageSheet');
      if (pageSheet == null) continue;
      XmlElement? section;
      for (final s in pageSheet.childElements) {
        if (s.name.local == 'Section' && s.getAttribute('N') == 'Layer') {
          section = s;
          break;
        }
      }
      if (section == null) continue;
      final rows = <int, XmlElement>{};
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final ix = int.tryParse(
            row.getAttribute('IX') ?? row.getAttribute('N') ?? '');
        if (ix != null) rows[ix] = row;
      }
      for (final layer in editLayers) {
        final base = _findLayer(baseLayers, layer.id);
        final row = rows[layer.id];
        if (base == null || row == null) continue;
        if (layer.visible != base.visible) {
          _writeValue(_ensureCell(row, 'Visible'), layer.visible ? '1' : '0');
          changed = true;
        }
        if (layer.locked != base.locked) {
          _writeValue(_ensureCell(row, 'Lock'), layer.locked ? '1' : '0');
          changed = true;
        }
        if (layer.print != base.print) {
          _writeValue(_ensureCell(row, 'Print'), layer.print ? '1' : '0');
          changed = true;
        }
      }
    }
    return changed;
  }

  static bool _layersEqual(List<VsdxLayer> a, List<VsdxLayer> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].visible != b[i].visible ||
          a[i].locked != b[i].locked ||
          a[i].print != b[i].print) {
        return false;
      }
    }
    return true;
  }

  static VsdxLayer? _findLayer(List<VsdxLayer> list, int id) {
    for (final l in list) {
      if (l.id == id) return l;
    }
    return null;
  }

  // --- Patching --------------------------------------------------------------

  bool _patchPage(XmlDocument pageXml, VsdxPage baseline, VsdxPage edited) {
    final root = pageXml.rootElement;
    var shapesEl = _firstChild(root, 'Shapes');

    final elements = <int, XmlElement>{};
    if (shapesEl != null) _indexShapes(shapesEl, elements);

    var changed = false;

    // 1) Patch existing shapes (matched by id, recursing into groups).
    void patchWalk(VsdxShape s) {
      final base = baseline.findShapeById(s.id);
      final el = elements[s.id];
      if (base != null && el != null && _patchShape(el, base, s)) {
        changed = true;
      }
      for (final c in s.children) {
        patchWalk(c);
      }
    }

    for (final s in edited.shapes) {
      patchWalk(s);
    }

    // 2) Remove shapes that were deleted from the model.
    final editedIds = <int>{};
    void collect(VsdxShape s) {
      editedIds.add(s.id);
      for (final c in s.children) {
        collect(c);
      }
    }

    for (final s in edited.shapes) {
      collect(s);
    }
    elements.forEach((id, el) {
      if (!editedIds.contains(id)) {
        el.parent?.children.remove(el);
        changed = true;
      }
    });

    // 3) Append newly-created top-level shapes.
    final added = edited.shapes
        .where((s) => !elements.containsKey(s.id))
        .toList(growable: false);
    if (added.isNotEmpty) {
      shapesEl ??= _ensureShapesElement(root);
      for (final s in added) {
        shapesEl.children.add(_buildShapeElement(s));
        changed = true;
      }
    }

    // 4) Reconcile <Connects> (glue) when it changed vs the baseline.
    if (!_connectsEqual(baseline.connects, edited.connects)) {
      _writeConnects(root, edited.connects);
      changed = true;
    }

    return changed;
  }

  bool _connectsEqual(List<VsdxConnect> a, List<VsdxConnect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.fromSheetId != y.fromSheetId ||
          x.fromCell != y.fromCell ||
          x.fromPart != y.fromPart ||
          x.toSheetId != y.toSheetId ||
          x.toCell != y.toCell ||
          x.toPart != y.toPart) {
        return false;
      }
    }
    return true;
  }

  void _writeConnects(XmlElement root, List<VsdxConnect> connects) {
    var el = _firstChild(root, 'Connects');
    if (el == null) {
      el = XmlElement(XmlName('Connects'));
      root.children.add(el);
    } else {
      el.children.clear();
    }
    for (final c in connects) {
      el.children.add(XmlElement(XmlName('Connect'), <XmlAttribute>[
        XmlAttribute(XmlName('FromSheet'), c.fromSheetId.toString()),
        XmlAttribute(XmlName('FromCell'), c.fromCell),
        if (c.fromPart != null)
          XmlAttribute(XmlName('FromPart'), c.fromPart.toString()),
        XmlAttribute(XmlName('ToSheet'), c.toSheetId.toString()),
        XmlAttribute(XmlName('ToCell'), c.toCell),
        if (c.toPart != null)
          XmlAttribute(XmlName('ToPart'), c.toPart.toString()),
      ]));
    }
  }

  void _indexShapes(XmlElement shapesEl, Map<int, XmlElement> out) {
    for (final el in shapesEl.childElements) {
      if (el.name.local != 'Shape') continue;
      final id = int.tryParse(el.getAttribute('ID') ?? '');
      if (id != null) out[id] = el;
      final nested = _firstChild(el, 'Shapes');
      if (nested != null) _indexShapes(nested, out);
    }
  }

  bool _patchShape(XmlElement el, VsdxShape base, VsdxShape edited) {
    var changed = false;
    changed |= _patchLength(el, 'PinX', base.pinX, edited.pinX);
    changed |= _patchLength(el, 'PinY', base.pinY, edited.pinY);
    changed |= _patchLength(el, 'Width', base.width, edited.width);
    changed |= _patchLength(el, 'Height', base.height, edited.height);
    changed |= _patchAngle(el, 'Angle', base.angleRad, edited.angleRad);
    changed |= _patchNullableLength(el, 'BeginX', base.beginX, edited.beginX);
    changed |= _patchNullableLength(el, 'BeginY', base.beginY, edited.beginY);
    changed |= _patchNullableLength(el, 'EndX', base.endX, edited.endX);
    changed |= _patchNullableLength(el, 'EndY', base.endY, edited.endY);
    changed |= _patchBool(el, 'FlipX', base.flipX, edited.flipX);
    changed |= _patchBool(el, 'FlipY', base.flipY, edited.flipY);
    // Style.
    changed |= _patchColor(el, 'FillForegnd', base.fill.foreground, edited.fill.foreground);
    changed |= _patchInt(el, 'FillPattern', base.fill.pattern, edited.fill.pattern);
    changed |= _patchColor(el, 'LineColor', base.line.color, edited.line.color);
    changed |= _patchLength(el, 'LineWeight', base.line.weightInches, edited.line.weightInches);
    changed |= _patchInt(el, 'LinePattern', base.line.pattern, edited.line.pattern);
    // Text (plain-text replacement; rich runs are not preserved on edit).
    changed |= _patchText(el, base.text, edited.text);
    // Geometry (regenerate when it changed and every command is representable,
    // e.g. after resize scaling or connector re-routing).
    changed |= _patchGeometry(el, base, edited);
    return changed;
  }

  bool _patchGeometry(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_geometriesEqual(base.geometries, edited.geometries)) return false;
    if (!edited.geometries.every(_canRebuild)) return false;
    final existing = <XmlElement>[
      for (final child in el.childElements)
        if (child.name.local == 'Section' &&
            child.getAttribute('N') == 'Geometry')
          child,
    ];
    for (final s in existing) {
      el.children.remove(s);
    }
    // Insert before the first Text/Shapes child so the cell/section/text order
    // stays schema-friendly; otherwise append.
    var insertAt = el.children.length;
    for (var i = 0; i < el.children.length; i++) {
      final node = el.children[i];
      if (node is XmlElement &&
          (node.name.local == 'Text' || node.name.local == 'Shapes')) {
        insertAt = i;
        break;
      }
    }
    var ix = 0;
    final sections = <XmlElement>[
      for (final g in edited.geometries)
        if (_buildGeometrySection(g, ix++) case final s?) s,
    ];
    el.children.insertAll(insertAt, sections);
    return true;
  }

  static bool _canRebuild(VsdxGeometry g) => g.commands.every(
        (c) => c is MoveTo || c is LineTo || c is EllipseCmd,
      );

  static bool _geometriesEqual(List<VsdxGeometry> a, List<VsdxGeometry> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final ga = a[i], gb = b[i];
      if (ga.noFill != gb.noFill ||
          ga.noLine != gb.noLine ||
          ga.noShow != gb.noShow ||
          ga.commands.length != gb.commands.length) {
        return false;
      }
      for (var j = 0; j < ga.commands.length; j++) {
        if (ga.commands[j].toString() != gb.commands[j].toString()) {
          return false;
        }
      }
    }
    return true;
  }

  bool _patchColor(XmlElement shape, String cell, VsdxColor? base, VsdxColor? value) {
    if (value == null) return false;
    if (base != null && base.value == value.value) return false;
    _writeValue(_ensureCell(shape, cell), _hex(value));
    return true;
  }

  bool _patchInt(XmlElement shape, String cell, int base, int value) {
    if (base == value) return false;
    _writeValue(_ensureCell(shape, cell), value.toString());
    return true;
  }

  bool _patchText(XmlElement shape, String? base, String? value) {
    if (value == null || value == base) return false;
    XmlElement? textEl;
    for (final el in shape.childElements) {
      if (el.name.local == 'Text') {
        textEl = el;
        break;
      }
    }
    if (textEl == null) {
      textEl = XmlElement(XmlName('Text'));
      shape.children.add(textEl);
    }
    textEl.children
      ..clear()
      ..add(XmlText(value));
    return true;
  }

  bool _patchLength(XmlElement shape, String cell, double base, double value) {
    if ((base - value).abs() <= _epsilon) return false;
    final el = _ensureCell(shape, cell);
    final unit = VsdxLengthUnit.tryParse(el.getAttribute('U'));
    _writeValue(el, _fmt(fromInches(value, unit)));
    return true;
  }

  bool _patchNullableLength(
    XmlElement shape,
    String cell,
    double? base,
    double? value,
  ) {
    if (value == null) return false;
    if (base != null && (base - value).abs() <= _epsilon) return false;
    final el = _ensureCell(shape, cell);
    final unit = VsdxLengthUnit.tryParse(el.getAttribute('U'));
    _writeValue(el, _fmt(fromInches(value, unit)));
    return true;
  }

  bool _patchAngle(XmlElement shape, String cell, double base, double value) {
    if ((base - value).abs() <= _epsilon) return false;
    final el = _ensureCell(shape, cell);
    final unit = VsdxAngleUnit.tryParse(el.getAttribute('U'));
    _writeValue(el, _fmt(fromRadians(value, unit)));
    return true;
  }

  bool _patchBool(XmlElement shape, String cell, bool base, bool value) {
    if (base == value) return false;
    _writeValue(_ensureCell(shape, cell), value ? '1' : '0');
    return true;
  }

  /// Set `V=` and drop any stale `F=`/`E=` so Visio keeps our literal instead
  /// of recomputing over it.
  void _writeValue(XmlElement cell, String value) {
    cell.setAttribute('V', value);
    if (cell.getAttribute('F') != null) cell.removeAttribute('F');
    if (cell.getAttribute('E') != null) cell.removeAttribute('E');
  }

  XmlElement _ensureCell(XmlElement shape, String name) {
    for (final el in shape.childElements) {
      if (el.name.local == 'Cell' && el.getAttribute('N') == name) return el;
    }
    final cell = XmlElement(XmlName('Cell'), <XmlAttribute>[
      XmlAttribute(XmlName('N'), name),
      XmlAttribute(XmlName('V'), '0'),
    ]);
    shape.children.add(cell);
    return cell;
  }

  // --- New-shape emission ----------------------------------------------------

  XmlElement _ensureShapesElement(XmlElement root) {
    final existing = _firstChild(root, 'Shapes');
    if (existing != null) return existing;
    final el = XmlElement(XmlName('Shapes'));
    root.children.add(el);
    return el;
  }

  XmlElement _buildShapeElement(VsdxShape s) {
    final children = <XmlNode>[
      _cell('PinX', _fmt(s.pinX)),
      _cell('PinY', _fmt(s.pinY)),
      _cell('Width', _fmt(s.width)),
      _cell('Height', _fmt(s.height)),
      _cell('Angle', _fmt(s.angleRad)),
    ];
    if (s.is1D) {
      children
        ..add(_cell('BeginX', _fmt(s.beginX ?? 0)))
        ..add(_cell('BeginY', _fmt(s.beginY ?? 0)))
        ..add(_cell('EndX', _fmt(s.endX ?? 0)))
        ..add(_cell('EndY', _fmt(s.endY ?? 0)));
    }
    if (s.fill.foreground != null) {
      children.add(_cell('FillForegnd', _hex(s.fill.foreground!)));
    }
    children.add(_cell('FillPattern', s.fill.pattern.toString()));
    if (s.line.color != null) {
      children.add(_cell('LineColor', _hex(s.line.color!)));
    }
    children
      ..add(_cell('LineWeight', _fmt(s.line.weightInches)))
      ..add(_cell('LinePattern', s.line.pattern.toString()));
    var ix = 0;
    for (final g in s.geometries) {
      final section = _buildGeometrySection(g, ix++);
      if (section != null) children.add(section);
    }
    if (s.text != null && s.text!.isNotEmpty) {
      children.add(XmlElement(XmlName('Text'), const [], [XmlText(s.text!)]));
    }
    return XmlElement(
      XmlName('Shape'),
      <XmlAttribute>[
        XmlAttribute(XmlName('ID'), s.id.toString()),
        XmlAttribute(XmlName('NameU'), s.name),
        XmlAttribute(XmlName('Name'), s.name),
        XmlAttribute(XmlName('Type'), 'Shape'),
      ],
      children,
    );
  }

  XmlElement? _buildGeometrySection(VsdxGeometry g, int ix) {
    final rows = <XmlNode>[];
    if (g.noFill) rows.add(_cell('NoFill', '1'));
    if (g.noLine) rows.add(_cell('NoLine', '1'));
    var rowIx = 1;
    for (final cmd in g.commands) {
      final row = _buildRow(cmd, rowIx);
      if (row != null) {
        rows.add(row);
        rowIx++;
      }
    }
    if (rows.isEmpty) return null;
    return XmlElement(
      XmlName('Section'),
      <XmlAttribute>[
        XmlAttribute(XmlName('N'), 'Geometry'),
        XmlAttribute(XmlName('IX'), ix.toString()),
      ],
      rows,
    );
  }

  XmlElement? _buildRow(VsdxPathCommand cmd, int ix) {
    switch (cmd) {
      case MoveTo(:final x, :final y):
        return _row('MoveTo', ix, {'X': x, 'Y': y});
      case LineTo(:final x, :final y):
        return _row('LineTo', ix, {'X': x, 'Y': y});
      case EllipseCmd(
          :final cx,
          :final cy,
          :final aX,
          :final aY,
          :final bX,
          :final bY,
        ):
        return _row('Ellipse', ix,
            {'X': cx, 'Y': cy, 'A': aX, 'B': aY, 'C': bX, 'D': bY});
      default:
        return null;
    }
  }

  XmlElement _row(String type, int ix, Map<String, double> cells) {
    final children = <XmlNode>[
      for (final e in cells.entries) _cell(e.key, _fmt(e.value)),
    ];
    return XmlElement(
      XmlName('Row'),
      <XmlAttribute>[
        XmlAttribute(XmlName('T'), type),
        XmlAttribute(XmlName('IX'), ix.toString()),
      ],
      children,
    );
  }

  XmlElement _cell(String name, String value) => XmlElement(
        XmlName('Cell'),
        <XmlAttribute>[
          XmlAttribute(XmlName('N'), name),
          XmlAttribute(XmlName('V'), value),
        ],
      );

  static String _hex(VsdxColor c) =>
      '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  // --- Re-zip ----------------------------------------------------------------

  Uint8List _rezip(Uint8List originalBytes, Map<String, Uint8List> patched) {
    final archive = ZipDecoder().decodeBytes(originalBytes);
    final out = Archive();
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final bytes = patched[f.name] ?? _fileBytes(f);
      out.addFile(ArchiveFile(f.name, bytes.length, bytes));
    }
    final encoded = ZipEncoder().encode(out);
    if (encoded == null) {
      throw StateError('Failed to encode the .vsdx archive');
    }
    return Uint8List.fromList(encoded);
  }

  static Uint8List _fileBytes(ArchiveFile f) {
    final c = f.content;
    return c is Uint8List ? c : Uint8List.fromList(c as List<int>);
  }

  // --- Helpers ---------------------------------------------------------------

  static String _noSlash(String s) => s.startsWith('/') ? s.substring(1) : s;

  static String _fmt(double v) {
    if (!v.isFinite) return '0';
    var s = v.toStringAsFixed(9);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return s == '-0' ? '0' : s;
  }

  static XmlElement? _firstChild(XmlElement parent, String local) {
    for (final el in parent.childElements) {
      if (el.name.local == local) return el;
    }
    return null;
  }
}
