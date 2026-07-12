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
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../model/connect.dart';
import '../model/document.dart';
import '../model/geometry.dart';
import '../model/layer.dart';
import '../model/page.dart';
import '../model/rich_text.dart';
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
    final patched = <String, Uint8List>{}; // archive name (no slash) -> bytes
    final removed = <String>{};

    final docPart = pkg.resolveDocumentPartName();
    final pagesPart = resolver.singleTargetOfType(docPart, VsdxRelType.pages);
    final pagesXml = pagesPart == null ? null : pkg.readPartXml(pagesPart);
    if (pagesPart == null || pagesXml == null) {
      return _rezip(originalBytes, patched, removed);
    }

    final pagePartByIndex = _resolvePagePartsFrom(pagesXml, pagesPart, resolver);
    final partByBaselineId = <int, String>{};
    for (var i = 0; i < baseline.pages.length; i++) {
      final part = pagePartByIndex[i];
      if (part != null) partByBaselineId[baseline.pages[i].id] = part;
    }
    final baselineById = <int, VsdxPage>{
      for (final p in baseline.pages) p.id: p,
    };
    final editedIds = <int>{for (final p in edited.pages) p.id};

    // 1) Patch the content parts of pages kept from the baseline (by ID).
    for (final ep in edited.pages) {
      final bp = baselineById[ep.id];
      final part = partByBaselineId[ep.id];
      if (bp == null || part == null) continue;
      final xml = pkg.readPartXml(part);
      if (xml == null) continue;
      if (_patchPage(xml, bp, ep)) {
        patched[_noSlash(part)] =
            Uint8List.fromList(utf8.encode(xml.toXmlString()));
      }
    }

    // 2) pages.xml (+rels, +[Content_Types]) surgery: rename/layers, remove,
    //    add, reorder.
    final pagesRelsPart = _relsPartFor(pagesPart);
    final pagesRelsXml = pkg.readPartXml(pagesRelsPart);
    final ctXml = pkg.readPartXml('/[Content_Types].xml');
    final root = pagesXml.rootElement;
    var pagesDirty = false, relsDirty = false, ctDirty = false;

    final pageElById = <int, XmlElement>{};
    for (final el in root.childElements) {
      if (el.name.local != 'Page') continue;
      final id = int.tryParse(el.getAttribute('ID') ?? '');
      if (id != null) pageElById[id] = el;
    }

    // 2a) Kept pages: name + layer flags.
    for (final ep in edited.pages) {
      final bp = baselineById[ep.id];
      final el = pageElById[ep.id];
      if (bp == null || el == null) continue;
      if (bp.name != ep.name) {
        el.setAttribute('NameU', ep.name);
        if (el.getAttribute('Name') != null) el.setAttribute('Name', ep.name);
        pagesDirty = true;
      }
      if (_patchLayerRows(el, bp, ep)) pagesDirty = true;
      if (_patchPageProperties(el, bp, ep)) pagesDirty = true;
    }

    // 2b) Removed pages.
    for (final bp in baseline.pages) {
      if (editedIds.contains(bp.id)) continue;
      final el = pageElById[bp.id];
      if (el != null) {
        final rId = _relIdOf(el);
        el.parent?.children.remove(el);
        pagesDirty = true;
        if (rId != null &&
            pagesRelsXml != null &&
            _removeRelationship(pagesRelsXml, rId)) {
          relsDirty = true;
        }
      }
      final part = partByBaselineId[bp.id];
      if (part != null) {
        removed
          ..add(_noSlash(part))
          ..add(_noSlash(_relsPartFor(part)));
        if (ctXml != null && _removeOverride(ctXml, part)) ctDirty = true;
      }
    }

    // 2c) Added pages (new part + <Page> + relationship + content-type).
    var nextNum = _maxPageNumber(pagePartByIndex.values) + 1;
    var nextRId = pagesRelsXml == null ? 1 : _maxRelId(pagesRelsXml) + 1;
    for (final ep in edited.pages) {
      if (baselineById.containsKey(ep.id)) continue;
      final fileName = 'page$nextNum.xml';
      final partName = 'visio/pages/$fileName';
      nextNum++;
      final rId = 'rId$nextRId';
      nextRId++;
      root.children.add(_buildPageIndexElement(ep, rId));
      pagesDirty = true;
      if (pagesRelsXml != null) {
        _addPageRelationship(pagesRelsXml, rId, fileName);
        relsDirty = true;
      }
      if (ctXml != null) {
        _addPageOverride(ctXml, '/$partName');
        ctDirty = true;
      }
      patched[partName] =
          Uint8List.fromList(utf8.encode(_buildPageContentsXml(ep)));
    }

    // 2d) Reorder <Page> elements to the edited page order.
    if (_reorderPages(root, edited.pages)) pagesDirty = true;

    if (pagesDirty) {
      patched[_noSlash(pagesPart)] =
          Uint8List.fromList(utf8.encode(pagesXml.toXmlString()));
    }
    if (relsDirty && pagesRelsXml != null) {
      patched[_noSlash(pagesRelsPart)] =
          Uint8List.fromList(utf8.encode(pagesRelsXml.toXmlString()));
    }
    if (ctDirty && ctXml != null) {
      patched['[Content_Types].xml'] =
          Uint8List.fromList(utf8.encode(ctXml.toXmlString()));
    }

    return _rezip(originalBytes, patched, removed);
  }

  // --- pages.xml helpers -----------------------------------------------------

  bool _patchLayerRows(XmlElement pageEl, VsdxPage bp, VsdxPage ep) {
    if (_layersEqual(bp.layers, ep.layers)) return false;
    final pageSheet = _firstChild(pageEl, 'PageSheet');
    if (pageSheet == null) return false;
    XmlElement? section;
    for (final s in pageSheet.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'Layer') {
        section = s;
        break;
      }
    }
    if (section == null) return false;
    final rows = <int, XmlElement>{};
    for (final row in section.childElements) {
      if (row.name.local != 'Row') continue;
      final ix =
          int.tryParse(row.getAttribute('IX') ?? row.getAttribute('N') ?? '');
      if (ix != null) rows[ix] = row;
    }
    var changed = false;
    for (final layer in ep.layers) {
      final base = _findLayer(bp.layers, layer.id);
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
    return changed;
  }

  /// Patch the page-level `<PageSheet>` cells the editor can change: page size
  /// (`PageWidth` / `PageHeight`, drawio Paper Size) and background colour
  /// (`PageColor`, drawio Background). Returns whether anything changed.
  bool _patchPageProperties(XmlElement pageEl, VsdxPage bp, VsdxPage ep) {
    final needWidth = (bp.widthInches - ep.widthInches).abs() > _epsilon;
    final needHeight = (bp.heightInches - ep.heightInches).abs() > _epsilon;
    final needColor = bp.backgroundColor?.value != ep.backgroundColor?.value;
    if (!needWidth && !needHeight && !needColor) return false;
    final sheet = _firstChild(pageEl, 'PageSheet') ?? _ensurePageSheet(pageEl);
    var changed = false;
    if (needWidth) {
      final cell = _ensurePageSheetCell(sheet, 'PageWidth');
      final unit = VsdxLengthUnit.tryParse(cell.getAttribute('U'));
      _writeValue(cell, _fmt(fromInches(ep.widthInches, unit)));
      changed = true;
    }
    if (needHeight) {
      final cell = _ensurePageSheetCell(sheet, 'PageHeight');
      final unit = VsdxLengthUnit.tryParse(cell.getAttribute('U'));
      _writeValue(cell, _fmt(fromInches(ep.heightInches, unit)));
      changed = true;
    }
    if (needColor && ep.backgroundColor != null) {
      _writeValue(
          _ensurePageSheetCell(sheet, 'PageColor'), _hex(ep.backgroundColor!));
      changed = true;
    }
    return changed;
  }

  /// Find or create a `<Page>`'s `<PageSheet>` (which must precede `<Rel>`).
  XmlElement _ensurePageSheet(XmlElement pageEl) {
    final existing = _firstChild(pageEl, 'PageSheet');
    if (existing != null) return existing;
    final sheet = XmlElement(XmlName('PageSheet'));
    pageEl.children.insert(0, sheet);
    return sheet;
  }

  /// Like [_ensureCell], but for a `<PageSheet>`: new cells are inserted before
  /// the first `<Section>` so the Cell-before-Section element order stays valid.
  XmlElement _ensurePageSheetCell(XmlElement pageSheet, String name) {
    for (final el in pageSheet.childElements) {
      if (el.name.local == 'Cell' && el.getAttribute('N') == name) return el;
    }
    final cell = XmlElement(XmlName('Cell'), <XmlAttribute>[
      XmlAttribute(XmlName('N'), name),
      XmlAttribute(XmlName('V'), '0'),
    ]);
    var at = pageSheet.children.length;
    for (var i = 0; i < pageSheet.children.length; i++) {
      final n = pageSheet.children[i];
      if (n is XmlElement && n.name.local == 'Section') {
        at = i;
        break;
      }
    }
    pageSheet.children.insert(at, cell);
    return cell;
  }

  static String _relsPartFor(String partName) {
    final noSlash = _noSlash(partName);
    final idx = noSlash.lastIndexOf('/');
    final dir = idx < 0 ? '' : noSlash.substring(0, idx);
    final base = idx < 0 ? noSlash : noSlash.substring(idx + 1);
    return '/${dir.isEmpty ? '' : '$dir/'}_rels/$base.rels';
  }

  static String? _relIdOf(XmlElement pageEl) {
    final rel = _firstChild(pageEl, 'Rel');
    if (rel == null) return null;
    return rel.getAttribute('r:id') ??
        rel.getAttribute('id') ??
        rel.getAttribute('Id');
  }

  static bool _removeRelationship(XmlDocument relsXml, String rId) {
    for (final el in relsXml.rootElement.childElements) {
      if (el.name.local == 'Relationship' && el.getAttribute('Id') == rId) {
        el.parent?.children.remove(el);
        return true;
      }
    }
    return false;
  }

  static bool _removeOverride(XmlDocument ctXml, String partName) {
    final target = partName.startsWith('/') ? partName : '/$partName';
    for (final el in ctXml.rootElement.childElements) {
      if (el.name.local == 'Override' &&
          el.getAttribute('PartName') == target) {
        el.parent?.children.remove(el);
        return true;
      }
    }
    return false;
  }

  static int _maxPageNumber(Iterable<String> partNames) {
    var max = 0;
    final re = RegExp(r'page(\d+)\.xml$');
    for (final p in partNames) {
      final m = re.firstMatch(p);
      if (m != null) {
        final n = int.tryParse(m.group(1)!);
        if (n != null && n > max) max = n;
      }
    }
    return max;
  }

  static int _maxRelId(XmlDocument relsXml) {
    var max = 0;
    final re = RegExp(r'(\d+)$');
    for (final el in relsXml.rootElement.childElements) {
      if (el.name.local != 'Relationship') continue;
      final m = re.firstMatch(el.getAttribute('Id') ?? '');
      if (m != null) {
        final n = int.tryParse(m.group(1)!);
        if (n != null && n > max) max = n;
      }
    }
    return max;
  }

  void _addPageRelationship(XmlDocument relsXml, String rId, String targetFile) {
    relsXml.rootElement.children.add(XmlElement(XmlName('Relationship'), [
      XmlAttribute(XmlName('Id'), rId),
      XmlAttribute(XmlName('Type'),
          'http://schemas.microsoft.com/visio/2010/relationships/page'),
      XmlAttribute(XmlName('Target'), targetFile),
    ]));
  }

  void _addPageOverride(XmlDocument ctXml, String partName) {
    ctXml.rootElement.children.add(XmlElement(XmlName('Override'), [
      XmlAttribute(XmlName('PartName'), partName),
      XmlAttribute(
          XmlName('ContentType'), 'application/vnd.ms-visio.page+xml'),
    ]));
  }

  XmlElement _buildPageIndexElement(VsdxPage ep, String rId) {
    final pageSheet = XmlElement(XmlName('PageSheet'), const [], <XmlNode>[
      _cell('PageWidth', _fmt(ep.widthInches <= 0 ? 8.5 : ep.widthInches)),
      _cell('PageHeight', _fmt(ep.heightInches <= 0 ? 11.0 : ep.heightInches)),
      if (ep.backgroundColor != null)
        _cell('PageColor', _hex(ep.backgroundColor!)),
    ]);
    final rel = XmlElement(
      XmlName('Rel'),
      <XmlAttribute>[XmlAttribute(XmlName('id', 'r'), rId)],
    );
    return XmlElement(
      XmlName('Page'),
      <XmlAttribute>[
        XmlAttribute(XmlName('ID'), ep.id.toString()),
        XmlAttribute(XmlName('NameU'), ep.name),
        XmlAttribute(XmlName('Name'), ep.name),
      ],
      <XmlNode>[pageSheet, rel],
    );
  }

  String _buildPageContentsXml(VsdxPage ep) {
    final shapes = XmlElement(XmlName('Shapes'), const [], <XmlNode>[
      for (final s in ep.shapes) _buildShapeElement(s),
    ]);
    final root = XmlElement(
      XmlName('PageContents'),
      <XmlAttribute>[
        XmlAttribute(XmlName('xmlns'), _mainNs),
        XmlAttribute(XmlName('r', 'xmlns'), _officeRelNs),
      ],
      <XmlNode>[shapes],
    );
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '${root.toXmlString()}';
  }

  bool _reorderPages(XmlElement root, List<VsdxPage> order) {
    final byId = <int, XmlElement>{};
    final pageEls = <XmlElement>[];
    for (final el in root.childElements) {
      if (el.name.local != 'Page') continue;
      pageEls.add(el);
      final id = int.tryParse(el.getAttribute('ID') ?? '');
      if (id != null) byId[id] = el;
    }
    if (pageEls.length < 2) return false;
    final desired = <XmlElement>[];
    final used = <int>{};
    for (final p in order) {
      final el = byId[p.id];
      if (el != null && used.add(p.id)) desired.add(el);
    }
    for (final el in pageEls) {
      if (!desired.contains(el)) desired.add(el);
    }
    var same = true;
    for (var i = 0; i < pageEls.length; i++) {
      if (!identical(pageEls[i], desired[i])) {
        same = false;
        break;
      }
    }
    if (same) return false;
    for (final el in pageEls) {
      root.children.remove(el);
    }
    root.children.addAll(desired);
    return true;
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
    final origParent = <int, int?>{}; // id → parent Shape id (null = top level)
    if (shapesEl != null) _indexShapes(shapesEl, elements, origParent);

    // Parent map of the edited tree (id → parent id / null).
    final editedParent = <int, int?>{};
    void mapParents(VsdxShape s, int? parent) {
      editedParent[s.id] = parent;
      for (final c in s.children) {
        mapParents(c, s.id);
      }
    }

    for (final s in edited.shapes) {
      mapParents(s, null);
    }

    // A shape must be rebuilt (fresh element) when it is new or has changed
    // parent (grouped / ungrouped). Others are patched in place.
    bool needsRebuild(int id) =>
        !origParent.containsKey(id) || origParent[id] != editedParent[id];

    var changed = false;

    // 1) Patch existing, structurally-unchanged shapes (matched by id).
    void patchWalk(VsdxShape s) {
      if (!needsRebuild(s.id)) {
        final base = baseline.findShapeById(s.id);
        final el = elements[s.id];
        if (base != null && el != null && _patchShape(el, base, s)) {
          changed = true;
        }
      }
      for (final c in s.children) {
        patchWalk(c);
      }
    }

    for (final s in edited.shapes) {
      patchWalk(s);
    }

    // 2) Remove elements deleted from the model or moved to a new parent
    //    (they are rebuilt in their new location in step 3).
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
      if (!editedIds.contains(id) || needsRebuild(id)) {
        el.parent?.children.remove(el);
        changed = true;
      }
    });

    // 3) Build fresh elements for new / reparented shapes, inserting each at the
    //    highest changed level (a rebuilt group emits its whole subtree).
    void insertWalk(VsdxShape s, int? parent) {
      final parentRebuilt = parent != null && needsRebuild(parent);
      if (needsRebuild(s.id) && !parentRebuilt) {
        final container = parent == null
            ? (shapesEl ??= _ensureShapesElement(root))
            : _ensureNestedShapes(elements[parent]!);
        container.children.add(_buildShapeElement(s));
        changed = true;
        return; // descendants are emitted as part of this subtree
      }
      for (final c in s.children) {
        insertWalk(c, s.id);
      }
    }

    for (final s in edited.shapes) {
      insertWalk(s, null);
    }

    // 4) Reorder <Shape> elements to match the model's z-order (top level).
    final topShapes = shapesEl;
    if (topShapes != null && _reorderShapes(topShapes, edited.shapes)) {
      changed = true;
    }

    // 5) Reconcile <Connects> (glue) when it changed vs the baseline.
    if (!_connectsEqual(baseline.connects, edited.connects)) {
      _writeConnects(root, edited.connects);
      changed = true;
    }

    return changed;
  }

  /// Reorder the direct `<Shape>` children of [shapesEl] to match [order]
  /// (top-level model z-order). Returns whether the order actually changed.
  bool _reorderShapes(XmlElement shapesEl, List<VsdxShape> order) {
    final byId = <int, XmlElement>{};
    final shapeEls = <XmlElement>[];
    for (final el in shapesEl.childElements) {
      if (el.name.local != 'Shape') continue;
      shapeEls.add(el);
      final id = int.tryParse(el.getAttribute('ID') ?? '');
      if (id != null) byId[id] = el;
    }
    if (shapeEls.length < 2) return false;

    final desired = <XmlElement>[];
    final used = <int>{};
    for (final s in order) {
      final el = byId[s.id];
      if (el != null && used.add(s.id)) desired.add(el);
    }
    // Keep any shape elements not mentioned in `order` in their prior slots.
    for (final el in shapeEls) {
      if (!desired.contains(el)) desired.add(el);
    }
    // No change? (same identity order)
    var same = true;
    for (var i = 0; i < shapeEls.length; i++) {
      if (!identical(shapeEls[i], desired[i])) {
        same = false;
        break;
      }
    }
    if (same) return false;

    // Rebuild children: non-Shape nodes stay where they are relative to the
    // shape block by simply re-appending shapes in the new order after
    // removing the old ones.
    for (final el in shapeEls) {
      shapesEl.children.remove(el);
    }
    shapesEl.children.addAll(desired);
    return true;
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

  void _indexShapes(
    XmlElement shapesEl,
    Map<int, XmlElement> out, [
    Map<int, int?>? parents,
    int? parentId,
  ]) {
    for (final el in shapesEl.childElements) {
      if (el.name.local != 'Shape') continue;
      final id = int.tryParse(el.getAttribute('ID') ?? '');
      if (id != null) {
        out[id] = el;
        if (parents != null) parents[id] = parentId;
      }
      final nested = _firstChild(el, 'Shapes');
      if (nested != null) _indexShapes(nested, out, parents, id);
    }
  }

  /// Find or create the nested `<Shapes>` container of a group `<Shape>`.
  XmlElement _ensureNestedShapes(XmlElement shapeEl) {
    final existing = _firstChild(shapeEl, 'Shapes');
    if (existing != null) return existing;
    final s = XmlElement(XmlName('Shapes'));
    shapeEl.children.add(s);
    return s;
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
    changed |= _patchInt(el, 'BeginArrow', base.line.beginArrow, edited.line.beginArrow);
    changed |= _patchInt(el, 'EndArrow', base.line.endArrow, edited.line.endArrow);
    changed |= _patchRatio(el, 'FillForegndTrans',
        base.fill.foregroundTransparency, edited.fill.foregroundTransparency);
    changed |= _patchRatio(
        el, 'LineColorTrans', base.line.transparency, edited.line.transparency);
    // Text block vertical alignment + drop shadow toggle.
    changed |= _patchInt(el, 'VerticalAlign',
        _vAlignInt(base.richText.textBlock.verticalAlign),
        _vAlignInt(edited.richText.textBlock.verticalAlign));
    changed |= _patchInt(el, 'ShadowPattern',
        base.shadow.enabled ? 1 : 0, edited.shadow.enabled ? 1 : 0);
    // Text (plain-text replacement; rich runs are not preserved on edit).
    changed |= _patchText(el, base.text, edited.text);
    // Geometry (regenerate when it changed and every command is representable,
    // e.g. after resize scaling or connector re-routing).
    changed |= _patchGeometry(el, base, edited);
    // Text formatting (Character size/color/style + Paragraph alignment).
    changed |= _patchRichText(el, base, edited);
    return changed;
  }

  bool _patchRichText(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_richTextEqual(base.richText, edited.richText)) return false;
    final runs = edited.richText.runs;
    if (runs.isEmpty) return false;
    final target = runs.first; // our editor formats the whole text uniformly
    var changed = false;

    final charSection = _ensureSection(el, 'Character');
    final charRows = _rowsOf(charSection);
    if (charRows.isEmpty) charRows.add(_addRow(charSection, 0));
    final styleInt = (target.charStyle.style.bold ? 0x01 : 0) |
        (target.charStyle.style.italic ? 0x02 : 0) |
        (target.charStyle.underline ? 0x04 : 0);
    for (final row in charRows) {
      final sizeCell = _ensureCell(row, 'Size');
      final unit = VsdxLengthUnit.tryParse(sizeCell.getAttribute('U'));
      _writeValue(sizeCell, _fmt(fromInches(target.charStyle.fontSizeInches, unit)));
      _writeValue(_ensureCell(row, 'Style'), styleInt.toString());
      if (target.charStyle.color != null) {
        _writeValue(_ensureCell(row, 'Color'), _hex(target.charStyle.color!));
      }
      if (target.charStyle.fontFamily != null) {
        _writeValue(_ensureCell(row, 'Font'), target.charStyle.fontFamily!);
      }
      changed = true;
    }

    final paraSection = _ensureSection(el, 'Paragraph');
    final paraRows = _rowsOf(paraSection);
    if (paraRows.isEmpty) paraRows.add(_addRow(paraSection, 0));
    for (final row in paraRows) {
      _writeValue(
        _ensureCell(row, 'HorzAlign'),
        _alignToInt(target.paraStyle.horizontalAlign).toString(),
      );
      changed = true;
    }
    return changed;
  }

  XmlElement _ensureSection(XmlElement shape, String name) {
    for (final s in shape.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == name) return s;
    }
    final section = XmlElement(
      XmlName('Section'),
      <XmlAttribute>[XmlAttribute(XmlName('N'), name)],
    );
    _insertBeforeTextOrShapes(shape, section);
    return section;
  }

  void _insertBeforeTextOrShapes(XmlElement el, XmlElement node) {
    var at = el.children.length;
    for (var i = 0; i < el.children.length; i++) {
      final n = el.children[i];
      if (n is XmlElement &&
          (n.name.local == 'Text' || n.name.local == 'Shapes')) {
        at = i;
        break;
      }
    }
    el.children.insert(at, node);
  }

  List<XmlElement> _rowsOf(XmlElement section) => <XmlElement>[
        for (final r in section.childElements)
          if (r.name.local == 'Row') r,
      ];

  XmlElement _addRow(XmlElement section, int ix) {
    final row = XmlElement(
      XmlName('Row'),
      <XmlAttribute>[XmlAttribute(XmlName('IX'), ix.toString())],
    );
    section.children.add(row);
    return row;
  }

  static int _alignToInt(VsdxHorzAlign a) => switch (a) {
        VsdxHorzAlign.left => 0,
        VsdxHorzAlign.center => 1,
        VsdxHorzAlign.right => 2,
        VsdxHorzAlign.justify => 3,
      };

  static int _vAlignInt(VsdxVertAlign a) => switch (a) {
        VsdxVertAlign.top => 0,
        VsdxVertAlign.middle => 1,
        VsdxVertAlign.bottom => 2,
      };

  static bool _richTextEqual(VsdxRichText a, VsdxRichText b) {
    if (a.runs.length != b.runs.length) return false;
    for (var i = 0; i < a.runs.length; i++) {
      final ra = a.runs[i], rb = b.runs[i];
      if (ra.text != rb.text) return false;
      final ca = ra.charStyle, cb = rb.charStyle;
      if ((ca.fontSizeInches - cb.fontSizeInches).abs() > 1e-9 ||
          ca.style.bold != cb.style.bold ||
          ca.style.italic != cb.style.italic ||
          ca.underline != cb.underline ||
          ca.fontFamily != cb.fontFamily ||
          ca.color?.value != cb.color?.value ||
          ra.paraStyle.horizontalAlign != rb.paraStyle.horizontalAlign) {
        return false;
      }
    }
    return true;
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
        (c) =>
            c is MoveTo || c is LineTo || c is EllipseCmd || c is EllipticalArcTo,
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

  /// Patch a plain 0..1 ratio cell (e.g. `FillForegndTrans` / `LineColorTrans`).
  bool _patchRatio(XmlElement shape, String cell, double base, double value) {
    if ((base - value).abs() <= _epsilon) return false;
    _writeValue(_ensureCell(shape, cell), _fmt(value));
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
    final isGroup = s.children.isNotEmpty;
    if (isGroup) {
      children.add(XmlElement(XmlName('Shapes'), const <XmlAttribute>[], <XmlNode>[
        for (final c in s.children) _buildShapeElement(c),
      ]));
    }
    return XmlElement(
      XmlName('Shape'),
      <XmlAttribute>[
        XmlAttribute(XmlName('ID'), s.id.toString()),
        XmlAttribute(XmlName('NameU'), s.name),
        XmlAttribute(XmlName('Name'), s.name),
        XmlAttribute(XmlName('Type'), isGroup ? 'Group' : 'Shape'),
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
      case EllipticalArcTo(
          :final x,
          :final y,
          :final controlX,
          :final controlY,
          :final angle,
          :final eccentricity,
        ):
        return _row('EllipticalArcTo', ix, {
          'X': x,
          'Y': y,
          'A': controlX,
          'B': controlY,
          'C': angle,
          'D': eccentricity,
        });
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

  Uint8List _rezip(
    Uint8List originalBytes,
    Map<String, Uint8List> patched, [
    Set<String> removed = const <String>{},
  ]) {
    final archive = ZipDecoder().decodeBytes(originalBytes);
    final out = Archive();
    final seen = <String>{};
    for (final f in archive.files) {
      if (!f.isFile) continue;
      if (removed.contains(f.name)) continue;
      final bytes = patched[f.name] ?? _fileBytes(f);
      out.addFile(ArchiveFile(f.name, bytes.length, bytes));
      seen.add(f.name);
    }
    // Brand-new parts (e.g. added pages) not present in the original archive.
    patched.forEach((name, bytes) {
      if (!seen.contains(name) && !removed.contains(name)) {
        out.addFile(ArchiveFile(name, bytes.length, bytes));
      }
    });
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
