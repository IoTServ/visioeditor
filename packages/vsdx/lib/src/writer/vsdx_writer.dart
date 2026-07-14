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
import '../model/effects.dart';
import '../model/fill.dart';
import '../model/geometry.dart';
import '../model/hyperlink.dart';
import '../model/image.dart';
import '../model/layer.dart';
import '../model/line.dart';
import '../model/page.dart';
import '../model/rich_text.dart';
import '../model/shape.dart';
import '../model/sheet_sections.dart';
import '../model/user_property.dart';
import '../parser/document_parser.dart';
import '../parser/package_reader.dart';
import '../parser/relationships.dart';
import '../utils/color.dart';

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

    // [Content_Types].xml is read up-front: inserting an image needs to
    // register a media content-type default while patching page content parts.
    final ctXml = pkg.readPartXml('/[Content_Types].xml');
    var ctDirty = false;

    // 1) Patch the content parts of pages kept from the baseline (by ID).
    for (final ep in edited.pages) {
      final bp = baselineById[ep.id];
      final part = partByBaselineId[ep.id];
      if (bp == null || part == null) continue;
      final xml = pkg.readPartXml(part);
      if (xml == null) continue;
      // Embed any images newly added to this kept page (media bytes + page
      // rels + content-type), yielding the {mediaPart -> rId} map the shape
      // builder needs for the fresh <ForeignData> references.
      final imageRels = _prepareImageParts(
        pkg: pkg,
        edited: edited,
        rebuiltImageShapes: _newImageShapes(bp, ep),
        pagePart: part,
        patched: patched,
        ctXml: ctXml,
        markCtDirty: () => ctDirty = true,
      );
      if (_patchPage(xml, bp, ep, imageRels: imageRels)) {
        patched[_noSlash(part)] =
            Uint8List.fromList(utf8.encode(xml.toXmlString()));
      }
    }

    // 2) pages.xml (+rels, +[Content_Types]) surgery: rename/layers, remove,
    //    add, reorder.
    final pagesRelsPart = _relsPartFor(pagesPart);
    final pagesRelsXml = pkg.readPartXml(pagesRelsPart);
    final root = pagesXml.rootElement;
    var pagesDirty = false, relsDirty = false;

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
      // A freshly-added page has no rels part yet; embed its images (creating
      // the rels part) before serialising the shapes that reference them.
      final imageRels = _prepareImageParts(
        pkg: pkg,
        edited: edited,
        rebuiltImageShapes: _imageShapes(ep),
        pagePart: '/$partName',
        patched: patched,
        ctXml: ctXml,
        markCtDirty: () => ctDirty = true,
      );
      patched[partName] = Uint8List.fromList(
          utf8.encode(_buildPageContentsXml(ep, imageRels: imageRels)));
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
    final pageSheet = _firstChild(pageEl, 'PageSheet') ?? _ensurePageSheet(pageEl);
    XmlElement? section;
    for (final s in pageSheet.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'Layer') {
        section = s;
        break;
      }
    }
    if (section == null) {
      if (ep.layers.isEmpty) return false;
      pageSheet.children.add(_buildLayerSection(ep.layers));
      return true;
    }
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
      var row = rows[layer.id];
      if (row == null) {
        // New layer row — emit a full row matching `_buildLayerSection`.
        section.children.add(XmlElement(
          XmlName('Row'),
          <XmlAttribute>[XmlAttribute(XmlName('IX'), layer.id.toString())],
          <XmlNode>[
            _cell('Name', layer.name),
            _cell('Visible', layer.visible ? '1' : '0'),
            _cell('Print', layer.print ? '1' : '0'),
            _cell('Active', layer.active ? '1' : '0'),
            _cell('Lock', layer.locked ? '1' : '0'),
            _cell('Snap', layer.snap ? '1' : '0'),
            _cell('Glue', layer.glue ? '1' : '0'),
            if (layer.color != null) _cell('Color', _hex(layer.color!)),
            if (layer.colorTrans > _epsilon)
              _cell('ColorTrans', _fmt(layer.colorTrans)),
            if (layer.nameUniv != null) _cell('NameUniv', layer.nameUniv!),
            if (layer.status != 0) _cell('Status', layer.status.toString()),
          ],
        ));
        changed = true;
        continue;
      }
      if (base == null) continue;
      if (layer.name != base.name) {
        _writeValue(_ensureCell(row, 'Name'), layer.name);
        changed = true;
      }
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
      if (layer.active != base.active) {
        _writeValue(_ensureCell(row, 'Active'), layer.active ? '1' : '0');
        changed = true;
      }
      if (layer.snap != base.snap) {
        _writeValue(_ensureCell(row, 'Snap'), layer.snap ? '1' : '0');
        changed = true;
      }
      if (layer.glue != base.glue) {
        _writeValue(_ensureCell(row, 'Glue'), layer.glue ? '1' : '0');
        changed = true;
      }
      if (layer.color?.value != base.color?.value && layer.color != null) {
        _writeValue(_ensureCell(row, 'Color'), _hex(layer.color!));
        changed = true;
      }
      if (layer.nameUniv != base.nameUniv && layer.nameUniv != null) {
        _writeValue(_ensureCell(row, 'NameUniv'), layer.nameUniv!);
        changed = true;
      }
      if ((layer.colorTrans - base.colorTrans).abs() > _epsilon) {
        _writeValue(_ensureCell(row, 'ColorTrans'), _fmt(layer.colorTrans));
        changed = true;
      }
      if (layer.status != base.status) {
        _writeValue(_ensureCell(row, 'Status'), layer.status.toString());
        changed = true;
      }
    }
    return changed;
  }

  /// Patch the page-level `<PageSheet>` cells the editor can change: page size
  /// (`PageWidth` / `PageHeight`, drawio Paper Size), background colour
  /// (`PageColor`), and the remaining PageSheet props (scale / shadow / jumps).
  bool _patchPageProperties(XmlElement pageEl, VsdxPage bp, VsdxPage ep) {
    final needWidth = (bp.widthInches - ep.widthInches).abs() > _epsilon;
    final needHeight = (bp.heightInches - ep.heightInches).abs() > _epsilon;
    final needColor = bp.backgroundColor?.value != ep.backgroundColor?.value;
    final needSheet = bp.pageSheet != ep.pageSheet;
    final needView = bp.viewScale != ep.viewScale ||
        bp.viewCenterX != ep.viewCenterX ||
        bp.viewCenterY != ep.viewCenterY;
    if (!needWidth && !needHeight && !needColor && !needSheet && !needView) {
      return false;
    }
    final sheet = _firstChild(pageEl, 'PageSheet') ?? _ensurePageSheet(pageEl);
    var changed = false;
    if (needWidth) {
      // `V` is written in Visio's internal units (inches); the existing `U`
      // display attribute is left untouched. See readLengthInches.
      _writeValue(
          _ensurePageSheetCell(sheet, 'PageWidth'), _fmt(ep.widthInches));
      changed = true;
    }
    if (needHeight) {
      _writeValue(
          _ensurePageSheetCell(sheet, 'PageHeight'), _fmt(ep.heightInches));
      changed = true;
    }
    if (needColor && ep.backgroundColor != null) {
      _writeValue(
          _ensurePageSheetCell(sheet, 'PageColor'), _hex(ep.backgroundColor!));
      changed = true;
    }
    if (needSheet) {
      changed |= _patchPageSheetCells(sheet, bp.pageSheet, ep.pageSheet);
    }
    if (needView) {
      changed |= _patchDoubleAttr(pageEl, 'ViewScale', bp.viewScale, ep.viewScale);
      changed |=
          _patchDoubleAttr(pageEl, 'ViewCenterX', bp.viewCenterX, ep.viewCenterX);
      changed |=
          _patchDoubleAttr(pageEl, 'ViewCenterY', bp.viewCenterY, ep.viewCenterY);
    }
    return changed;
  }

  bool _patchDoubleAttr(
      XmlElement el, String name, double? base, double? edited) {
    if (base == edited) return false;
    if (base != null &&
        edited != null &&
        (base - edited).abs() <= _epsilon) {
      return false;
    }
    if (edited == null) {
      el.removeAttribute(name);
    } else {
      el.setAttribute(name, _fmt(edited));
    }
    return true;
  }

  bool _patchPageSheetCells(
      XmlElement sheet, VsdxPageSheet base, VsdxPageSheet edited) {
    var changed = false;
    void len(String name, double b, double e) {
      if ((b - e).abs() <= _epsilon) return;
      _writeValue(_ensurePageSheetCell(sheet, name), _fmt(e),
          preserveFormula: _pageSheetCellHasFormula(sheet, name));
      changed = true;
    }

    void raw(String name, String b, String e, {String? unit}) {
      if (b == e) return;
      final cell = _ensurePageSheetCell(sheet, name);
      _writeValue(cell, e,
          preserveFormula: _pageSheetCellHasFormula(sheet, name));
      if (unit != null && unit.isNotEmpty && cell.getAttribute('U') == null) {
        cell.setAttribute('U', unit);
      }
      changed = true;
    }

    void flag(String name, bool b, bool e) {
      if (b == e) return;
      _writeValue(_ensurePageSheetCell(sheet, name), e ? '1' : '0');
      changed = true;
    }

    len('ShdwOffsetX', base.shadowOffsetXInches, edited.shadowOffsetXInches);
    len('ShdwOffsetY', base.shadowOffsetYInches, edited.shadowOffsetYInches);
    raw('PageScale', _fmt(base.pageScale), _fmt(edited.pageScale),
        unit: edited.pageScaleUnit);
    raw('DrawingScale', _fmt(base.drawingScale), _fmt(edited.drawingScale),
        unit: edited.drawingScaleUnit);
    raw('DrawingSizeType', base.drawingSizeType.toString(),
        edited.drawingSizeType.toString());
    raw('DrawingScaleType', base.drawingScaleType.toString(),
        edited.drawingScaleType.toString());
    raw('DrawingResizeType', base.drawingResizeType.toString(),
        edited.drawingResizeType.toString());
    flag('InhibitSnap', base.inhibitSnap, edited.inhibitSnap);
    flag('PageLockReplace', base.pageLockReplace, edited.pageLockReplace);
    flag('PageLockDuplicate', base.pageLockDuplicate, edited.pageLockDuplicate);
    raw('UIVisibility', base.uiVisibility.toString(),
        edited.uiVisibility.toString());
    raw('ShdwType', base.shadowType.toString(), edited.shadowType.toString());
    raw('ShdwObliqueAngle', _fmt(base.shadowObliqueAngle),
        _fmt(edited.shadowObliqueAngle));
    raw('ShdwScaleFactor', _fmt(base.shadowScaleFactor),
        _fmt(edited.shadowScaleFactor));
    flag('PageShapeSplit', base.pageShapeSplit, edited.pageShapeSplit);
    if (edited.lineJumpCode != null) {
      raw('LineJumpCode', (base.lineJumpCode ?? -1).toString(),
          edited.lineJumpCode.toString());
    }
    if (edited.lineJumpStyle != null) {
      raw('LineJumpStyle', (base.lineJumpStyle ?? -1).toString(),
          edited.lineJumpStyle.toString());
    }
    len('PageLeftMargin', base.marginLeftInches, edited.marginLeftInches);
    len('PageRightMargin', base.marginRightInches, edited.marginRightInches);
    len('PageTopMargin', base.marginTopInches, edited.marginTopInches);
    len('PageBottomMargin', base.marginBottomInches, edited.marginBottomInches);
    raw('PrintPageOrientation', base.printPageOrientation.toString(),
        edited.printPageOrientation.toString());
    if (edited.variationColorIndex != null) {
      raw('VariationColorIndex', (base.variationColorIndex ?? -1).toString(),
          edited.variationColorIndex.toString());
    }
    if (edited.variationStyleIndex != null) {
      raw('VariationStyleIndex', (base.variationStyleIndex ?? -1).toString(),
          edited.variationStyleIndex.toString());
    }
    return changed;
  }

  static bool _pageSheetCellHasFormula(XmlElement sheet, String name) {
    for (final el in sheet.childElements) {
      if (el.name.local == 'Cell' && el.getAttribute('N') == name) {
        return _isParametricFormula(el.getAttribute('F'));
      }
    }
    return false;
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
    final pageSheetChildren = <XmlNode>[
      _cell('PageWidth', _fmt(ep.widthInches <= 0 ? 8.5 : ep.widthInches)),
      _cell('PageHeight', _fmt(ep.heightInches <= 0 ? 11.0 : ep.heightInches)),
      if (ep.backgroundColor != null)
        _cell('PageColor', _hex(ep.backgroundColor!)),
      ..._pageSheetExtraCells(ep.pageSheet),
      if (ep.layers.isNotEmpty) _buildLayerSection(ep.layers),
    ];
    final pageSheet = XmlElement(XmlName('PageSheet'), const [], pageSheetChildren);
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
        if (ep.viewScale != null)
          XmlAttribute(XmlName('ViewScale'), _fmt(ep.viewScale!)),
        if (ep.viewCenterX != null)
          XmlAttribute(XmlName('ViewCenterX'), _fmt(ep.viewCenterX!)),
        if (ep.viewCenterY != null)
          XmlAttribute(XmlName('ViewCenterY'), _fmt(ep.viewCenterY!)),
      ],
      <XmlNode>[pageSheet, rel],
    );
  }

  XmlElement _buildLayerSection(List<VsdxLayer> layers) => XmlElement(
        XmlName('Section'),
        <XmlAttribute>[XmlAttribute(XmlName('N'), 'Layer')],
        <XmlNode>[
          for (final layer in layers)
            XmlElement(
              XmlName('Row'),
              <XmlAttribute>[XmlAttribute(XmlName('IX'), layer.id.toString())],
              <XmlNode>[
                _cell('Name', layer.name),
                _cell('Visible', layer.visible ? '1' : '0'),
                _cell('Print', layer.print ? '1' : '0'),
                _cell('Active', layer.active ? '1' : '0'),
                _cell('Lock', layer.locked ? '1' : '0'),
                _cell('Snap', layer.snap ? '1' : '0'),
                _cell('Glue', layer.glue ? '1' : '0'),
                if (layer.color != null) _cell('Color', _hex(layer.color!)),
                if (layer.colorTrans > _epsilon)
                  _cell('ColorTrans', _fmt(layer.colorTrans)),
                if (layer.nameUniv != null) _cell('NameUniv', layer.nameUniv!),
                if (layer.status != 0) _cell('Status', layer.status.toString()),
              ],
            ),
        ],
      );

  /// Emit Visio-default PageSheet cells (scale / shadow / jumps / margins).
  List<XmlNode> _pageSheetExtraCells(VsdxPageSheet s) => <XmlNode>[
        _cell('ShdwOffsetX', _fmt(s.shadowOffsetXInches)),
        _cell('ShdwOffsetY', _fmt(s.shadowOffsetYInches)),
        _cell('PageScale', _fmt(s.pageScale), unit: s.pageScaleUnit),
        _cell('DrawingScale', _fmt(s.drawingScale), unit: s.drawingScaleUnit),
        _cell('DrawingSizeType', s.drawingSizeType.toString()),
        _cell('DrawingScaleType', s.drawingScaleType.toString()),
        _cell('InhibitSnap', s.inhibitSnap ? '1' : '0'),
        _cell('PageLockReplace', s.pageLockReplace ? '1' : '0'),
        _cell('PageLockDuplicate', s.pageLockDuplicate ? '1' : '0'),
        _cell('UIVisibility', s.uiVisibility.toString()),
        _cell('ShdwType', s.shadowType.toString()),
        _cell('ShdwObliqueAngle', _fmt(s.shadowObliqueAngle)),
        _cell('ShdwScaleFactor', _fmt(s.shadowScaleFactor)),
        _cell('DrawingResizeType', s.drawingResizeType.toString()),
        _cell('PageShapeSplit', s.pageShapeSplit ? '1' : '0'),
        if (s.lineJumpCode != null)
          _cell('LineJumpCode', s.lineJumpCode.toString()),
        if (s.lineJumpStyle != null)
          _cell('LineJumpStyle', s.lineJumpStyle.toString()),
        _cell('PageLeftMargin', _fmt(s.marginLeftInches)),
        _cell('PageRightMargin', _fmt(s.marginRightInches)),
        _cell('PageTopMargin', _fmt(s.marginTopInches)),
        _cell('PageBottomMargin', _fmt(s.marginBottomInches)),
        _cell('PrintPageOrientation', s.printPageOrientation.toString()),
        if (s.variationColorIndex != null)
          _cell('VariationColorIndex', s.variationColorIndex.toString()),
        if (s.variationStyleIndex != null)
          _cell('VariationStyleIndex', s.variationStyleIndex.toString()),
      ];

  String _buildPageContentsXml(
    VsdxPage ep, {
    Map<String, String> imageRels = const <String, String>{},
  }) {
    final shapes = XmlElement(XmlName('Shapes'), const [], <XmlNode>[
      for (final s in ep.shapes) _buildShapeElement(s, imageRels: imageRels),
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

  // --- Image / ForeignData embedding -----------------------------------------

  static const String _imageRelType =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/image';

  /// Every picture shape on [page] (recursing into groups).
  List<VsdxShape> _imageShapes(VsdxPage page) {
    final out = <VsdxShape>[];
    void walk(VsdxShape s) {
      if (s.hasImage) out.add(s);
      for (final c in s.children) {
        walk(c);
      }
    }

    for (final s in page.shapes) {
      walk(s);
    }
    return out;
  }

  /// Picture shapes present in [edited] but not in [baseline] (matched by id) —
  /// i.e. the ones the writer will build fresh and therefore needs to wire a
  /// `<ForeignData>` relationship for.
  List<VsdxShape> _newImageShapes(VsdxPage baseline, VsdxPage edited) {
    final baseIds = <int>{};
    void collectIds(VsdxShape s) {
      baseIds.add(s.id);
      for (final c in s.children) {
        collectIds(c);
      }
    }

    for (final s in baseline.shapes) {
      collectIds(s);
    }
    return [for (final s in _imageShapes(edited)) if (!baseIds.contains(s.id)) s];
  }

  /// For the picture shapes in [rebuiltImageShapes] (which the writer is about
  /// to serialise on the page at [pagePart]), make sure each referenced media
  /// part is embedded (bytes + content-type) and reachable through the page's
  /// rels part, then return the `{mediaPart -> rId}` map to stamp onto the new
  /// `<ForeignData>` elements. Mutates [patched] (media bytes + rels part) and
  /// [ctXml] (a content-type default per media extension).
  Map<String, String> _prepareImageParts({
    required VsdxPackage pkg,
    required VsdxDocument edited,
    required List<VsdxShape> rebuiltImageShapes,
    required String pagePart,
    required Map<String, Uint8List> patched,
    required XmlDocument? ctXml,
    required void Function() markCtDirty,
  }) {
    if (rebuiltImageShapes.isEmpty) return const <String, String>{};

    final relsPart = _relsPartFor(pagePart);
    final relsNoSlash = _noSlash(relsPart);
    // Reuse an already-patched rels doc, else the original, else a fresh one.
    XmlDocument relsXml;
    if (patched.containsKey(relsNoSlash)) {
      relsXml = XmlDocument.parse(utf8.decode(patched[relsNoSlash]!));
    } else {
      relsXml = pkg.readPartXml(relsPart) ??
          XmlDocument.parse(
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
            '<Relationships xmlns="$_relNs"/>',
          );
    }

    var nextRId = _maxRelId(relsXml) + 1;
    final relByPart = <String, String>{};
    for (final s in rebuiltImageShapes) {
      final part = s.imagePartName;
      if (part == null || relByPart.containsKey(part)) continue;
      final rId = 'rId$nextRId';
      nextRId++;
      relByPart[part] = rId;
      relsXml.rootElement.children.add(XmlElement(XmlName('Relationship'), [
        XmlAttribute(XmlName('Id'), rId),
        XmlAttribute(XmlName('Type'), _imageRelType),
        XmlAttribute(XmlName('Target'), _mediaTargetFrom(pagePart, part)),
      ]));

      // Embed the bytes when this media part is not already in the package.
      final mediaNoSlash = _noSlash(part);
      if (!patched.containsKey(mediaNoSlash) &&
          pkg.readPartBytes(part) == null) {
        final img = edited.images.findByPart(part);
        if (img != null) {
          patched[mediaNoSlash] = Uint8List.fromList(img.bytes);
          if (ctXml != null &&
              _ensureMediaContentType(ctXml, part, img.mimeType)) {
            markCtDirty();
          }
        }
      }
    }

    patched[relsNoSlash] =
        Uint8List.fromList(utf8.encode(relsXml.toXmlString()));
    return relByPart;
  }

  /// Relationship target from a page part (e.g. `/visio/pages/page1.xml`) to a
  /// media part (e.g. `/visio/media/image1.png`), expressed relative to the
  /// page's own folder — Visio stores `../media/imageN.ext`.
  static String _mediaTargetFrom(String pagePart, String mediaPart) {
    final media = _noSlash(mediaPart);
    final page = _noSlash(pagePart);
    final pageDir = page.contains('/') ? page.substring(0, page.lastIndexOf('/')) : '';
    // Both live under visio/; the page sits one folder deeper (visio/pages),
    // so a single `..` hop reaches visio/ then down into media/.
    if (pageDir == 'visio/pages' && media.startsWith('visio/media/')) {
      return '../${media.substring('visio/'.length)}';
    }
    // Generic fallback: absolute-from-package target.
    return '/$media';
  }

  /// Ensure `[Content_Types].xml` can serve [mediaPart]. Adds a `<Default>` for
  /// the file extension when one is missing. Returns whether it changed.
  bool _ensureMediaContentType(
    XmlDocument ctXml,
    String mediaPart,
    String mimeType,
  ) {
    final dot = mediaPart.lastIndexOf('.');
    if (dot < 0) return false;
    final ext = mediaPart.substring(dot + 1).toLowerCase();
    if (ext.isEmpty) return false;
    for (final el in ctXml.rootElement.childElements) {
      if (el.name.local == 'Default' &&
          (el.getAttribute('Extension') ?? '').toLowerCase() == ext) {
        return false; // already covered
      }
    }
    final mime = mimeType.isNotEmpty ? mimeType : VsdxImage.mimeForExtension(ext);
    if (mime.isEmpty) return false;
    ctXml.rootElement.children.insert(
      0,
      XmlElement(XmlName('Default'), [
        XmlAttribute(XmlName('Extension'), ext),
        XmlAttribute(XmlName('ContentType'), mime),
      ]),
    );
    return true;
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
          '<Cell N="ShdwOffsetX" V="0.125"/>'
          '<Cell N="ShdwOffsetY" V="-0.125"/>'
          '<Cell N="PageScale" V="1" U="PT"/>'
          '<Cell N="DrawingScale" V="1" U="PT"/>'
          '<Cell N="DrawingSizeType" V="0"/>'
          '<Cell N="DrawingScaleType" V="0"/>'
          '<Cell N="InhibitSnap" V="0"/>'
          '<Cell N="PageLockReplace" V="0"/>'
          '<Cell N="PageLockDuplicate" V="0"/>'
          '<Cell N="UIVisibility" V="0"/>'
          '<Cell N="ShdwType" V="0"/>'
          '<Cell N="ShdwObliqueAngle" V="0"/>'
          '<Cell N="ShdwScaleFactor" V="1"/>'
          '<Cell N="DrawingResizeType" V="2"/>'
          '<Cell N="PageShapeSplit" V="1"/>'
          '<Cell N="PageLeftMargin" V="0"/>'
          '<Cell N="PageRightMargin" V="0"/>'
          '<Cell N="PageTopMargin" V="0"/>'
          '<Cell N="PageBottomMargin" V="0"/>'
          '<Cell N="PrintPageOrientation" V="2"/>'
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
          a[i].name != b[i].name ||
          a[i].nameUniv != b[i].nameUniv ||
          a[i].visible != b[i].visible ||
          a[i].locked != b[i].locked ||
          a[i].print != b[i].print ||
          a[i].active != b[i].active ||
          a[i].snap != b[i].snap ||
          a[i].glue != b[i].glue ||
          a[i].status != b[i].status ||
          a[i].color != b[i].color ||
          (a[i].colorTrans - b[i].colorTrans).abs() > _epsilon) {
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

  bool _patchPage(
    XmlDocument pageXml,
    VsdxPage baseline,
    VsdxPage edited, {
    Map<String, String> imageRels = const <String, String>{},
  }) {
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

    // Snapshot unmodelled Cell/Section clones *before* removing rebuilt
    // elements so EventDblClick / ObjType / QuickStyle* survive grouping.
    final opaqueById = <int, List<XmlNode>>{};
    for (final entry in elements.entries) {
      if (needsRebuild(entry.key)) {
        opaqueById[entry.key] = _extractOpaqueChildren(entry.value);
      }
    }

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
        container.children.add(_buildShapeElement(
          s,
          imageRels: imageRels,
          opaqueById: opaqueById,
        ));
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
    // LocPin follows the shape when it is resized (effective centre moves) or
    // when an off-centre pin is edited explicitly. Compare the *effective*
    // values so a null LocPin (implicit centre) still updates after resize.
    // When the relative pin position is unchanged, keep F=Width*0.5 etc.
    changed |= _patchLength(
      el,
      'LocPinX',
      base.effectiveLocPinX,
      edited.effectiveLocPinX,
      preserveFormula: _sameRatio(
          base.effectiveLocPinX, base.width, edited.effectiveLocPinX, edited.width),
    );
    changed |= _patchLength(
      el,
      'LocPinY',
      base.effectiveLocPinY,
      edited.effectiveLocPinY,
      preserveFormula: _sameRatio(
          base.effectiveLocPinY, base.height, edited.effectiveLocPinY, edited.height),
    );
    changed |= _patchAngle(el, 'Angle', base.angleRad, edited.angleRad);
    changed |= _patchNullableLength(el, 'BeginX', base.beginX, edited.beginX,
        preserveFormula: _cellHasParametricFormula(el, 'BeginX'));
    changed |= _patchNullableLength(el, 'BeginY', base.beginY, edited.beginY,
        preserveFormula: _cellHasParametricFormula(el, 'BeginY'));
    changed |= _patchNullableLength(el, 'EndX', base.endX, edited.endX,
        preserveFormula: _cellHasParametricFormula(el, 'EndX'));
    changed |= _patchNullableLength(el, 'EndY', base.endY, edited.endY,
        preserveFormula: _cellHasParametricFormula(el, 'EndY'));
    changed |= _patchBool(el, 'FlipX', base.flipX, edited.flipX);
    changed |= _patchBool(el, 'FlipY', base.flipY, edited.flipY);
    // Group behaviour (libvisio IsTextEditTarget / DontMoveChildren / …).
    changed |= _patchBool(
        el, 'IsTextEditTarget', base.isTextEditTarget, edited.isTextEditTarget);
    changed |= _patchBool(
        el, 'DontMoveChildren', base.dontMoveChildren, edited.dontMoveChildren);
    if (edited.selectMode != null) {
      changed |=
          _patchInt(el, 'SelectMode', base.selectMode ?? -1, edited.selectMode!);
    }
    if (edited.displayMode != null) {
      changed |= _patchInt(
          el, 'DisplayMode', base.displayMode ?? -1, edited.displayMode!);
    }
    // Protection (drawio "Lock/Unlock").
    changed |= _patchLock(el, base, edited);
    // Style.
    changed |= _patchColor(el, 'FillForegnd', base.fill.foreground, edited.fill.foreground);
    changed |= _patchColor(el, 'FillBkgnd', base.fill.background, edited.fill.background);
    changed |= _patchInt(el, 'FillPattern', base.fill.pattern, edited.fill.pattern);
    changed |= _patchColor(el, 'LineColor', base.line.color, edited.line.color);
    changed |= _patchLength(el, 'LineWeight', base.line.weightInches, edited.line.weightInches);
    changed |= _patchInt(el, 'LinePattern', base.line.pattern, edited.line.pattern);
    changed |= _patchInt(el, 'LineCap', _lineCapInt(base.line.cap), _lineCapInt(edited.line.cap));
    changed |= _patchInt(el, 'BeginArrow', base.line.beginArrow, edited.line.beginArrow);
    changed |= _patchInt(el, 'EndArrow', base.line.endArrow, edited.line.endArrow);
    changed |= _patchInt(
        el,
        'BeginArrowSize',
        _arrowSizeToBucket(base.line.beginArrowSizeInches),
        _arrowSizeToBucket(edited.line.beginArrowSizeInches));
    changed |= _patchInt(
        el,
        'EndArrowSize',
        _arrowSizeToBucket(base.line.endArrowSizeInches),
        _arrowSizeToBucket(edited.line.endArrowSizeInches));
    changed |= _patchRatio(el, 'FillForegndTrans',
        base.fill.foregroundTransparency, edited.fill.foregroundTransparency);
    changed |= _patchRatio(el, 'FillBkgndTrans',
        base.fill.backgroundTransparency, edited.fill.backgroundTransparency);
    changed |= _patchRatio(
        el, 'LineColorTrans', base.line.transparency, edited.line.transparency);
    changed |= _patchLength(
        el, 'Rounding', base.line.roundingInches, edited.line.roundingInches);
    changed |= _patchLength(
        el, 'SoftEdgesSize', base.line.softEdgesInches, edited.line.softEdgesInches);
    changed |= _patchInt(
        el, 'CompoundType', base.line.compoundType, edited.line.compoundType);
    changed |= _patchLayerMember(el, base.layerMemberIds, edited.layerMemberIds);
    // Text block transform (TxtPin / TxtWidth / TxtAngle / margins) +
    // HideText / TextBkgnd + drop shadow / glow / reflection.
    changed |= _patchTextBlock(el, base.richText.textBlock, edited.richText.textBlock);
    changed |= _patchShadow(el, base.shadow, edited.shadow);
    changed |= _patchGlow(el, base.glow, edited.glow);
    changed |= _patchReflection(el, base.reflection, edited.reflection);
    changed |= _patchGradient(el, base.fill, edited.fill);
    changed |= _patchLineGradient(el, base.line, edited.line);
    // Text content — only rewrite `<Text>` when the plain string changes so
    // existing `<cp>/<pp>/<fld>` markers survive style-only edits (libvisio
    // round-trip). When content does change we rebuild from rich runs with
    // cp/pp markers when possible.
    changed |= _patchTextContent(el, base, edited);
    // Geometry (regenerate when it changed and every command is representable,
    // e.g. after resize scaling or connector re-routing).
    changed |= _patchGeometry(el, base, edited);
    // Text formatting (Character size/color/style + Paragraph alignment).
    changed |= _patchRichText(el, base, edited);
    // Tabs section (libvisio PositionN / AlignmentN).
    changed |= _patchTabs(el, base, edited);
    // Shape data (drawio "Edit Data" → <Section N="Property">).
    changed |= _patchUserProperties(el, base, edited);
    // User-defined cells (`<Section N="User">`).
    changed |= _patchUserCells(el, base, edited);
    // Control / Scratch — required for SETATREF(Controls.*) and Scratch.* geometry.
    changed |= _patchControls(el, base, edited);
    changed |= _patchScratch(el, base, edited);
    // Field — dynamic text rows referenced by `<fld IX>`.
    changed |= _patchFields(el, base, edited);
    // Hyperlinks (drawio "Edit Link" → <Section N="Hyperlink">).
    changed |= _patchHyperlinks(el, base, edited);
    // Actions — context-menu rows.
    changed |= _patchActions(el, base, edited);
    // Fixed connection points (drawio blue points → <Section N="Connection">).
    changed |= _patchConnectionPoints(el, base, edited);
    // Parametric XForm / trigger formulas + connector dynamics.
    changed |= _patchFormulas(el, base, edited);
    changed |= _patchConnectorProps(el, base, edited);
    // ShapeSheet inheritance attrs (MasterShape / LineStyle / FillStyle / TextStyle).
    changed |= _patchIntAttr(el, 'Master', base.masterId, edited.masterId);
    changed |=
        _patchIntAttr(el, 'MasterShape', base.masterShapeId, edited.masterShapeId);
    changed |=
        _patchIntAttr(el, 'LineStyle', base.lineStyleId, edited.lineStyleId);
    changed |=
        _patchIntAttr(el, 'FillStyle', base.fillStyleId, edited.fillStyleId);
    changed |=
        _patchIntAttr(el, 'TextStyle', base.textStyleId, edited.textStyleId);
    return changed;
  }

  /// Set / clear an integer XML attribute on [el]. Returns true when mutated.
  bool _patchIntAttr(XmlElement el, String name, int? base, int? edited) {
    if (base == edited) return false;
    if (edited == null) {
      el.removeAttribute(name);
    } else {
      el.setAttribute(name, edited.toString());
    }
    return true;
  }

  /// Write / update ShapeSheet `F=` for XForm / trigger cells from the model.
  bool _patchFormulas(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_mapEqual(base.formulas, edited.formulas)) return false;
    var changed = false;
    for (final entry in edited.formulas.entries) {
      final prev = base.formulas[entry.key];
      if (prev == entry.value) continue;
      final cell = _ensureCell(el, entry.key);
      cell.setAttribute('F', entry.value);
      changed = true;
    }
    return changed;
  }

  bool _patchConnectorProps(XmlElement el, VsdxShape base, VsdxShape edited) {
    final b = base.connectorProps;
    final e = edited.connectorProps;
    if (b == e) return false;
    if (e == null) return false;
    var changed = false;
    if (e.begTrigger != null) {
      changed |= _patchStringCell(el, 'BegTrigger', b?.begTrigger, e.begTrigger!);
    }
    if (e.endTrigger != null) {
      changed |= _patchStringCell(el, 'EndTrigger', b?.endTrigger, e.endTrigger!);
    }
    if (e.glueType != null) {
      changed |= _patchInt(el, 'GlueType', b?.glueType ?? -1, e.glueType!);
    }
    if (e.conFixedCode != null) {
      changed |=
          _patchInt(el, 'ConFixedCode', b?.conFixedCode ?? -1, e.conFixedCode!);
    }
    if (e.dynFeedback != null) {
      changed |=
          _patchInt(el, 'DynFeedback', b?.dynFeedback ?? -1, e.dynFeedback!);
    }
    changed |= _patchBool(el, 'NoLiveDynamics', b?.noLiveDynamics ?? false,
        e.noLiveDynamics);
    if (e.conLineJumpCode != null) {
      changed |= _patchInt(
          el, 'ConLineJumpCode', b?.conLineJumpCode ?? -1, e.conLineJumpCode!);
    }
    if (e.conLineRouteExt != null) {
      changed |= _patchInt(
          el, 'ConLineRouteExt', b?.conLineRouteExt ?? -1, e.conLineRouteExt!);
    }
    if (e.conLineJumpStyle != null) {
      changed |= _patchInt(
          el, 'ConLineJumpStyle', b?.conLineJumpStyle ?? -1, e.conLineJumpStyle!);
    }
    if (e.conLineJumpDirX != null) {
      changed |= _patchInt(
          el, 'ConLineJumpDirX', b?.conLineJumpDirX ?? -1, e.conLineJumpDirX!);
    }
    if (e.conLineJumpDirY != null) {
      changed |= _patchInt(
          el, 'ConLineJumpDirY', b?.conLineJumpDirY ?? -1, e.conLineJumpDirY!);
    }
    if (e.shapeRouteStyle != null) {
      changed |= _patchInt(
          el, 'ShapeRouteStyle', b?.shapeRouteStyle ?? -1, e.shapeRouteStyle!);
    }
    if (e.shapePlaceFlip != null) {
      changed |= _patchInt(
          el, 'ShapePlaceFlip', b?.shapePlaceFlip ?? -1, e.shapePlaceFlip!);
    }
    return changed;
  }

  bool _patchStringCell(
      XmlElement el, String name, String? base, String edited) {
    if (base == edited) return false;
    final cell = _ensureCell(el, name);
    _writeValue(cell, edited, preserveFormula: cell.getAttribute('F') != null);
    return true;
  }

  static bool _mapEqual(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  /// Patch the shape's `<Section N="Connection">` to match the edited model's
  /// fixed connection points. Points are only ever added (materialised on glue)
  /// or left alone in our editor, so this appends a fresh section when the base
  /// had none, and otherwise rewrites each row's cells in place (preserving
  /// any unmodelled cells) — never clearing an existing section.
  bool _patchConnectionPoints(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_connectionPointsEqual(
        base.connectionPoints, edited.connectionPoints)) {
      return false;
    }
    if (edited.connectionPoints.isEmpty) return false;
    XmlElement? section;
    for (final s in el.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'Connection') {
        section = s;
        break;
      }
    }
    if (section == null) {
      _insertBeforeTextOrShapes(
          el, _buildConnectionSection(edited.connectionPoints));
      return true;
    }
    final rows =
        section.childElements.where((r) => r.name.local == 'Row').toList();
    final sx = base.width == 0 ? 1.0 : edited.width / base.width;
    final sy = base.height == 0 ? 1.0 : edited.height / base.height;
    for (var i = 0; i < edited.connectionPoints.length; i++) {
      final p = edited.connectionPoints[i];
      if (i < rows.length) {
        final old = i < base.connectionPoints.length
            ? base.connectionPoints[i]
            : null;
        final xCell = _ensureCell(rows[i], 'X');
        final yCell = _ensureCell(rows[i], 'Y');
        final keepX = old != null &&
            _formulaFitsScale(xCell.getAttribute('F'), old.x, p.x,
                sx: sx, sy: sy);
        final keepY = old != null &&
            _formulaFitsScale(yCell.getAttribute('F'), old.y, p.y,
                sx: sx, sy: sy);
        _writeValue(xCell, _fmt(p.x),
            preserveFormula: keepX || p.xFormula != null);
        _writeValue(yCell, _fmt(p.y),
            preserveFormula: keepY || p.yFormula != null);
        if (!keepX && p.xFormula != null) {
          xCell.setAttribute('F', p.xFormula!);
        }
        if (!keepY && p.yFormula != null) {
          yCell.setAttribute('F', p.yFormula!);
        }
        // Dir*/Type/AutoGen — update cached V but keep any Width* formulas.
        final dirXCell = _ensureCell(rows[i], 'DirX');
        final dirYCell = _ensureCell(rows[i], 'DirY');
        _writeValue(dirXCell, _fmt(p.dirX),
            preserveFormula: dirXCell.getAttribute('F') != null);
        _writeValue(dirYCell, _fmt(p.dirY),
            preserveFormula: dirYCell.getAttribute('F') != null);
        _writeValue(_ensureCell(rows[i], 'Type'), p.type.toString());
        _writeValue(_ensureCell(rows[i], 'AutoGen'), p.autoGen ? '1' : '0');
        if (p.prompt != null) {
          _writeValue(_ensureCell(rows[i], 'Prompt'), p.prompt!);
        }
      } else {
        section.children.add(_connectionRow(i, p));
      }
    }
    return true;
  }

  static bool _connectionPointsEqual(
      List<VsdxConnectionPoint> a, List<VsdxConnectionPoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  XmlElement _buildConnectionSection(List<VsdxConnectionPoint> points) =>
      XmlElement(
        XmlName('Section'),
        <XmlAttribute>[XmlAttribute(XmlName('N'), 'Connection')],
        <XmlNode>[
          for (var i = 0; i < points.length; i++) _connectionRow(i, points[i]),
        ],
      );

  XmlElement _connectionRow(int ix, VsdxConnectionPoint p) => XmlElement(
        XmlName('Row'),
        <XmlAttribute>[XmlAttribute(XmlName('IX'), ix.toString())],
        <XmlNode>[
          _cell('X', _fmt(p.x), formula: p.xFormula),
          _cell('Y', _fmt(p.y), formula: p.yFormula),
          _cell('DirX', _fmt(p.dirX)),
          _cell('DirY', _fmt(p.dirY)),
          _cell('Type', p.type.toString()),
          _cell('AutoGen', p.autoGen ? '1' : '0'),
          if (p.prompt != null) _cell('Prompt', p.prompt!),
        ],
      );

  /// Patch the shape's `<Section N="Property">` (Visio "Shape Data") to match
  /// the edited model: existing rows (matched by their `N` name) keep every
  /// unmodelled cell and only get their `Value`/`Label`/`Prompt`/`Format`/`Type`
  /// rewritten; new properties append fresh rows; dropped ones are removed. An
  /// empty edited set removes the section entirely.
  bool _patchUserProperties(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_userPropsEqual(base.userProperties, edited.userProperties)) {
      return false;
    }
    XmlElement? section;
    for (final s in el.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'Property') {
        section = s;
        break;
      }
    }
    if (edited.userProperties.isEmpty) {
      if (section == null) return false;
      section.parent?.children.remove(section);
      return true;
    }
    section ??= _ensureSection(el, 'Property');

    final rowByName = <String, XmlElement>{};
    for (final row in _rowsOf(section)) {
      final n =
          row.getAttribute('N') ?? 'Row${row.getAttribute('IX') ?? ''}';
      rowByName[n] = row;
    }
    final editedNames = <String>{for (final p in edited.userProperties) p.name};
    for (final entry in rowByName.entries) {
      if (!editedNames.contains(entry.key)) {
        entry.value.parent?.children.remove(entry.value);
      }
    }
    var nextIx = _maxRowIx(section) + 1;
    for (final p in edited.userProperties) {
      var row = rowByName[p.name];
      if (row == null) {
        row = XmlElement(XmlName('Row'), <XmlAttribute>[
          XmlAttribute(XmlName('N'), p.name),
          XmlAttribute(XmlName('IX'), (nextIx++).toString()),
        ]);
        section.children.add(row);
      }
      _writeValue(_ensureCell(row, 'Value'), p.value ?? '',
          preserveFormula: p.valueFormula != null);
      if (p.valueFormula != null) {
        _ensureCell(row, 'Value').setAttribute('F', p.valueFormula!);
      }
      if (p.label != null) _writeValue(_ensureCell(row, 'Label'), p.label!);
      if (p.prompt != null) _writeValue(_ensureCell(row, 'Prompt'), p.prompt!);
      if (p.format != null) _writeValue(_ensureCell(row, 'Format'), p.format!);
      _writeValue(_ensureCell(row, 'Type'), p.type.toString());
      if (p.sortKey != null) {
        _writeValue(_ensureCell(row, 'SortKey'), p.sortKey!);
      }
      _writeValue(_ensureCell(row, 'Invisible'), p.invisible ? '1' : '0');
      _writeValue(_ensureCell(row, 'Verify'), p.verify ? '1' : '0');
      _writeValue(_ensureCell(row, 'Ask'), p.ask ? '1' : '0');
      _writeValue(_ensureCell(row, 'DataLinked'), p.dataLinked ? '1' : '0');
      if (p.langId != null) {
        _writeValue(_ensureCell(row, 'LangID'), p.langId!);
      }
      if (p.calendar != null) {
        _writeValue(_ensureCell(row, 'Calendar'), p.calendar.toString());
      }
    }
    return true;
  }

  static int _maxRowIx(XmlElement section) {
    var max = 0;
    for (final row in section.childElements) {
      if (row.name.local != 'Row') continue;
      final ix = int.tryParse(row.getAttribute('IX') ?? '');
      if (ix != null && ix > max) max = ix;
    }
    return max;
  }

  static bool _userPropsEqual(
    List<VsdxUserProperty> a,
    List<VsdxUserProperty> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Patch `<Section N="User">` to match [edited.userCells] (symmetric to
  /// Property). Empty edited list drops the section.
  bool _patchUserCells(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_userCellsEqual(base.userCells, edited.userCells)) return false;
    XmlElement? section;
    for (final s in el.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'User') {
        section = s;
        break;
      }
    }
    if (edited.userCells.isEmpty) {
      if (section == null) return false;
      section.parent?.children.remove(section);
      return true;
    }
    section ??= _ensureSection(el, 'User');
    final rowByName = <String, XmlElement>{};
    for (final row in _rowsOf(section)) {
      final n = row.getAttribute('N');
      if (n != null) rowByName[n] = row;
    }
    final editedNames = <String>{for (final c in edited.userCells) c.name};
    for (final entry in rowByName.entries) {
      if (!editedNames.contains(entry.key)) {
        entry.value.parent?.children.remove(entry.value);
      }
    }
    var nextIx = _maxRowIx(section) + 1;
    for (final c in edited.userCells) {
      var row = rowByName[c.name];
      if (row == null) {
        row = XmlElement(XmlName('Row'), <XmlAttribute>[
          XmlAttribute(XmlName('N'), c.name),
          XmlAttribute(XmlName('IX'), (nextIx++).toString()),
        ]);
        section.children.add(row);
      }
      _writeValue(_ensureCell(row, 'Value'), c.value ?? '',
          preserveFormula: c.valueFormula != null);
      if (c.valueFormula != null) {
        _ensureCell(row, 'Value').setAttribute('F', c.valueFormula!);
      }
      if (c.prompt != null) {
        _writeValue(_ensureCell(row, 'Prompt'), c.prompt!);
      }
    }
    return true;
  }

  static bool _userCellsEqual(List<VsdxUserCell> a, List<VsdxUserCell> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Rebuild `<Section N="Control">` when the model list changes (group rebuild
  /// / handle edit). Empty list removes the section.
  bool _patchControls(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_listEqual(base.controls, edited.controls)) return false;
    XmlElement? section;
    for (final s in el.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'Control') {
        section = s;
        break;
      }
    }
    if (edited.controls.isEmpty) {
      if (section == null) return false;
      section.parent?.children.remove(section);
      return true;
    }
    if (section != null) section.parent?.children.remove(section);
    _insertBeforeTextOrShapes(el, _buildControlSection(edited.controls));
    return true;
  }

  /// Rebuild `<Section N="Scratch">` when rows change.
  bool _patchScratch(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_listEqual(base.scratch, edited.scratch)) return false;
    XmlElement? section;
    for (final s in el.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'Scratch') {
        section = s;
        break;
      }
    }
    if (edited.scratch.isEmpty) {
      if (section == null) return false;
      section.parent?.children.remove(section);
      return true;
    }
    if (section != null) section.parent?.children.remove(section);
    _insertBeforeTextOrShapes(el, _buildScratchSection(edited.scratch));
    return true;
  }

  /// Rebuild `<Section N="Field">` when rows change.
  bool _patchFields(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_listEqual(base.fields, edited.fields)) return false;
    XmlElement? section;
    for (final s in el.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'Field') {
        section = s;
        break;
      }
    }
    if (edited.fields.isEmpty) {
      if (section == null) return false;
      section.parent?.children.remove(section);
      return true;
    }
    if (section != null) section.parent?.children.remove(section);
    _insertBeforeTextOrShapes(el, _buildFieldSection(edited.fields));
    return true;
  }

  static bool _listEqual<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _patchLayerMember(XmlElement el, List<int> base, List<int> edited) {
    if (_intListsEqual(base, edited)) return false;
    if (edited.isEmpty) {
      // Clearing membership: write empty string (Visio convention).
      _writeValue(_ensureCell(el, 'LayerMember'), '');
      return true;
    }
    _writeValue(_ensureCell(el, 'LayerMember'), edited.join(';'));
    return true;
  }

  static bool _intListsEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Patch the shape's `<Section N="Hyperlink">` (drawio "Edit Link") to match
  /// the edited model: existing rows (matched by their `IX`) keep any unmodelled
  /// cell and only get the standard cells rewritten; new links append fresh
  /// rows; dropped ones are removed. An empty edited set removes the section.
  bool _patchHyperlinks(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_hyperlinksEqual(base.hyperlinks, edited.hyperlinks)) return false;
    XmlElement? section;
    for (final s in el.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'Hyperlink') {
        section = s;
        break;
      }
    }
    if (edited.hyperlinks.isEmpty) {
      if (section == null) return false;
      section.parent?.children.remove(section);
      return true;
    }
    section ??= _ensureSection(el, 'Hyperlink');

    final rowByIx = <int, XmlElement>{};
    for (final row in _rowsOf(section)) {
      final ix = int.tryParse(row.getAttribute('IX') ?? '');
      if (ix != null) rowByIx[ix] = row;
    }
    final editedIds = <int>{for (final h in edited.hyperlinks) h.id};
    for (final entry in rowByIx.entries) {
      if (!editedIds.contains(entry.key)) {
        entry.value.parent?.children.remove(entry.value);
      }
    }
    for (final h in edited.hyperlinks) {
      var row = rowByIx[h.id];
      if (row == null) {
        row = XmlElement(XmlName('Row'), <XmlAttribute>[
          XmlAttribute(XmlName('IX'), h.id.toString()),
        ]);
        section.children.add(row);
      }
      _writeValue(_ensureCell(row, 'Address'), h.address ?? '',
          preserveFormula: h.addressFormula != null);
      if (h.addressFormula != null) {
        _ensureCell(row, 'Address').setAttribute('F', h.addressFormula!);
      }
      _writeValue(_ensureCell(row, 'SubAddress'), h.subAddress ?? '');
      _writeValue(_ensureCell(row, 'Description'), h.description ?? '');
      if (h.extraInfo != null) {
        _writeValue(_ensureCell(row, 'ExtraInfo'), h.extraInfo!);
      }
      if (h.frame != null) _writeValue(_ensureCell(row, 'Frame'), h.frame!);
      _writeValue(_ensureCell(row, 'NewWindow'), h.newWindow ? '1' : '0');
      _writeValue(_ensureCell(row, 'Default'), h.isDefault ? '1' : '0');
      _writeValue(_ensureCell(row, 'Invisible'), h.invisible ? '1' : '0');
      if (h.sortKey != null) {
        _writeValue(_ensureCell(row, 'SortKey'), h.sortKey!);
      }
    }
    return true;
  }

  static bool _hyperlinksEqual(List<VsdxHyperlink> a, List<VsdxHyperlink> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _patchActions(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_actionsEqual(base.actions, edited.actions)) return false;
    XmlElement? section;
    for (final s in el.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'Actions') {
        section = s;
        break;
      }
    }
    if (edited.actions.isEmpty) {
      if (section == null) return false;
      section.parent?.children.remove(section);
      return true;
    }
    if (section != null) {
      section.parent?.children.remove(section);
    }
    _insertBeforeTextOrShapes(el, _buildActionsSection(edited.actions));
    return true;
  }

  static bool _actionsEqual(List<VsdxActionRow> a, List<VsdxActionRow> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _patchRichText(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_richTextEqual(base.richText, edited.richText)) return false;
    final runs = edited.richText.runs;
    if (runs.isEmpty) return false;

    final charSection = _ensureSection(el, 'Character');
    final paraSection = _ensureSection(el, 'Paragraph');
    // Update rows in place so unmodelled cells (FontScale, AsianFont, LangID,
    // Flags, Bullet*, …) survive style edits — matches libvisio round-trip
    // expectations for Visio XML fidelity.
    final charRows = _rowsOf(charSection);
    final paraRows = _rowsOf(paraSection);
    final n = runs.length;
    for (var i = 0; i < n; i++) {
      final charRow =
          i < charRows.length ? charRows[i] : _addRow(charSection, i);
      charRow.setAttribute('IX', i.toString());
      _writeCharRow(charRow, runs[i].charStyle);
      final paraRow =
          i < paraRows.length ? paraRows[i] : _addRow(paraSection, i);
      paraRow.setAttribute('IX', i.toString());
      _writeParaRow(paraRow, runs[i].paraStyle);
    }
    for (var i = charRows.length - 1; i >= n; i--) {
      charSection.children.remove(charRows[i]);
    }
    for (var i = paraRows.length - 1; i >= n; i--) {
      paraSection.children.remove(paraRows[i]);
    }
    return true;
  }

  bool _patchTabs(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_tabSetsEqual(base.richText.tabSets, edited.richText.tabSets)) {
      return false;
    }
    XmlElement? section;
    for (final s in el.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'Tabs') {
        section = s;
        break;
      }
    }
    if (edited.richText.tabSets.isEmpty) {
      if (section == null) return false;
      section.parent?.children.remove(section);
      return true;
    }
    if (section != null) section.parent?.children.remove(section);
    _insertBeforeTextOrShapes(el, _buildTabsSection(edited.richText.tabSets));
    return true;
  }

  void _writeCharRow(XmlElement row, VsdxCharStyle c) {
    _writeValue(_ensureCell(row, 'Size'), _fmt(c.fontSizeInches));
    _writeValue(_ensureCell(row, 'Style'), _charStyleBits(c).toString());
    if (c.color != null) {
      _writeValue(_ensureCell(row, 'Color'), _hex(c.color!));
    } else if (c.themeColorIndex != null) {
      final cell = _ensureCell(row, 'Color');
      _writeValue(cell, '0', preserveFormula: true);
      cell.setAttribute('F', 'THEMEVAL()');
    }
    if (c.fontFamily != null) {
      _writeValue(_ensureCell(row, 'Font'), c.fontFamily!);
    }
    _writeValue(_ensureCell(row, 'Strikethru'), c.strikethrough ? '1' : '0');
    if (c.doubleUnderline) {
      _writeValue(_ensureCell(row, 'DblUnderline'), '1');
    }
    if (c.doubleStrikethrough) {
      _writeValue(_ensureCell(row, 'DoubleStrikethrough'), '1');
    }
    if (c.overline) {
      _writeValue(_ensureCell(row, 'Overline'), '1');
    }
    if (c.letterSpacingInches.abs() > _epsilon) {
      _writeValue(_ensureCell(row, 'Letterspace'), _fmt(c.letterSpacingInches));
    }
    if (c.position != VsdxTextPosition.normal) {
      _writeValue(
          _ensureCell(row, 'Pos'), _textPositionInt(c.position).toString());
    }
    if (c.textCase != VsdxTextCase.normal) {
      _writeValue(
          _ensureCell(row, 'Case'), _textCaseInt(c.textCase).toString());
    }
    if ((c.fontScale - 1.0).abs() > _epsilon) {
      _writeValue(_ensureCell(row, 'FontScale'), _fmt(c.fontScale));
    }
    if (c.transparency > _epsilon) {
      _writeValue(_ensureCell(row, 'ColorTrans'), _fmt(c.transparency));
    }
    if (c.asianFont != null && c.asianFont!.isNotEmpty) {
      _writeValue(_ensureCell(row, 'AsianFont'), c.asianFont!);
    }
    if (c.complexScriptFont != null && c.complexScriptFont!.isNotEmpty) {
      _writeValue(_ensureCell(row, 'ComplexScriptFont'), c.complexScriptFont!);
    }
    if (c.langId != null && c.langId!.isNotEmpty) {
      _writeValue(_ensureCell(row, 'LangID'), c.langId!);
    }
    if (c.complexScriptSizeInches != null) {
      _writeValue(_ensureCell(row, 'ComplexScriptSize'),
          _fmt(c.complexScriptSizeInches!));
    }
  }

  void _writeParaRow(XmlElement row, VsdxParaStyle p) {
    _writeValue(
      _ensureCell(row, 'HorzAlign'),
      _alignToInt(p.horizontalAlign).toString(),
    );
    if (p.indentFirstInches.abs() > _epsilon) {
      _writeValue(_ensureCell(row, 'IndFirst'), _fmt(p.indentFirstInches));
    }
    if (p.indentLeftInches.abs() > _epsilon) {
      _writeValue(_ensureCell(row, 'IndLeft'), _fmt(p.indentLeftInches));
    }
    if (p.indentRightInches.abs() > _epsilon) {
      _writeValue(_ensureCell(row, 'IndRight'), _fmt(p.indentRightInches));
    }
    if (p.spaceBeforeInches.abs() > _epsilon) {
      _writeValue(_ensureCell(row, 'SpBefore'), _fmt(p.spaceBeforeInches));
    }
    if (p.spaceAfterInches.abs() > _epsilon) {
      _writeValue(_ensureCell(row, 'SpAfter'), _fmt(p.spaceAfterInches));
    }
    final spLine = _spLineValue(p);
    if (spLine != null) {
      _writeValue(_ensureCell(row, 'SpLine'), _fmt(spLine));
    }
    if (p.bullet != 0) {
      _writeValue(_ensureCell(row, 'Bullet'), p.bullet.toString());
    }
    if (p.bulletStr != null && p.bulletStr!.isNotEmpty) {
      _writeValue(_ensureCell(row, 'BulletStr'), p.bulletStr!);
    }
    if (p.bulletFont != null && p.bulletFont!.isNotEmpty) {
      _writeValue(_ensureCell(row, 'BulletFont'), p.bulletFont!);
    }
    if (p.bulletFontSizeInches != null) {
      _writeValue(
          _ensureCell(row, 'BulletFontSize'), _fmt(p.bulletFontSizeInches!));
    }
    if (p.textPosAfterBulletInches.abs() > _epsilon) {
      _writeValue(_ensureCell(row, 'TextPosAfterBullet'),
          _fmt(p.textPosAfterBulletInches));
    }
    if (p.flags != 0) {
      _writeValue(_ensureCell(row, 'Flags'), p.flags.toString());
    }
  }

  /// Encode [VsdxParaStyle] line spacing back to Visio's `SpLine` cell.
  /// Returns `null` when the value is the default omitted single spacing.
  static double? _spLineValue(VsdxParaStyle p) {
    if (p.lineSpacingAbsoluteInches > 1e-9) {
      return p.lineSpacingAbsoluteInches;
    }
    if (p.lineSpacingSolid) return 0.0;
    if ((p.lineSpacing - 1.0).abs() <= 1e-9) return null;
    return -p.lineSpacing;
  }

  static int _textPositionInt(VsdxTextPosition p) => switch (p) {
        VsdxTextPosition.normal => 0,
        VsdxTextPosition.superscript => 1,
        VsdxTextPosition.subscript => 2,
      };

  static int _textCaseInt(VsdxTextCase c) => switch (c) {
        VsdxTextCase.normal => 0,
        VsdxTextCase.allCaps => 1,
        VsdxTextCase.initialCaps => 2,
      };

  static int _lineCapInt(LineCap c) => switch (c) {
        LineCap.round => 0,
        LineCap.square => 1,
        LineCap.extended => 2,
      };

  /// Inverse of [StyleParser]'s `_arrowSizeFromBucket` — pick the nearest
  /// Visio bucket (0..6) for a length in inches.
  static int _arrowSizeToBucket(double inches) {
    const buckets = <double>[
      0.0625,
      0.0875,
      0.125,
      0.175,
      0.225,
      0.30,
      0.375,
    ];
    var best = 2;
    var bestDist = double.infinity;
    for (var i = 0; i < buckets.length; i++) {
      final d = (buckets[i] - inches).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
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
    if (!_tabSetsEqual(a.tabSets, b.tabSets)) return false;
    for (var i = 0; i < a.runs.length; i++) {
      final ra = a.runs[i], rb = b.runs[i];
      if (ra.text != rb.text) return false;
      if (!_intListsEqual(ra.tabIndices, rb.tabIndices)) return false;
      if (!_listEqual(ra.fieldSpans, rb.fieldSpans)) return false;
      final ca = ra.charStyle, cb = rb.charStyle;
      final pa = ra.paraStyle, pb = rb.paraStyle;
      if ((ca.fontSizeInches - cb.fontSizeInches).abs() > 1e-9 ||
          ca.style.bold != cb.style.bold ||
          ca.style.italic != cb.style.italic ||
          ca.style.smallCaps != cb.style.smallCaps ||
          ca.underline != cb.underline ||
          ca.strikethrough != cb.strikethrough ||
          ca.doubleUnderline != cb.doubleUnderline ||
          ca.doubleStrikethrough != cb.doubleStrikethrough ||
          ca.overline != cb.overline ||
          ca.fontFamily != cb.fontFamily ||
          ca.color?.value != cb.color?.value ||
          ca.themeColorIndex != cb.themeColorIndex ||
          (ca.letterSpacingInches - cb.letterSpacingInches).abs() > 1e-9 ||
          ca.position != cb.position ||
          ca.textCase != cb.textCase ||
          (ca.fontScale - cb.fontScale).abs() > 1e-9 ||
          ca.asianFont != cb.asianFont ||
          ca.complexScriptFont != cb.complexScriptFont ||
          ca.langId != cb.langId ||
          ca.complexScriptSizeInches != cb.complexScriptSizeInches ||
          (ca.transparency - cb.transparency).abs() > 1e-9 ||
          pa.horizontalAlign != pb.horizontalAlign ||
          (pa.indentFirstInches - pb.indentFirstInches).abs() > 1e-9 ||
          (pa.indentLeftInches - pb.indentLeftInches).abs() > 1e-9 ||
          (pa.indentRightInches - pb.indentRightInches).abs() > 1e-9 ||
          (pa.spaceBeforeInches - pb.spaceBeforeInches).abs() > 1e-9 ||
          (pa.spaceAfterInches - pb.spaceAfterInches).abs() > 1e-9 ||
          (pa.lineSpacing - pb.lineSpacing).abs() > 1e-9 ||
          (pa.lineSpacingAbsoluteInches - pb.lineSpacingAbsoluteInches).abs() >
              1e-9 ||
          pa.lineSpacingSolid != pb.lineSpacingSolid ||
          pa.bullet != pb.bullet ||
          pa.bulletStr != pb.bulletStr ||
          pa.bulletFont != pb.bulletFont ||
          pa.bulletFontSizeInches != pb.bulletFontSizeInches ||
          (pa.textPosAfterBulletInches - pb.textPosAfterBulletInches).abs() >
              1e-9 ||
          pa.flags != pb.flags) {
        return false;
      }
    }
    return true;
  }

  static bool _tabSetsEqual(List<VsdxTabSet> a, List<VsdxTabSet> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _patchGeometry(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_geometriesEqual(base.geometries, edited.geometries)) return false;
    if (!edited.geometries.every(_canRebuild)) return false;
    // Prefer in-place V= updates so Width*/Height*/Scratch formulas and
    // unmodelled cells (NoSnap, A–D on NURBS, …) survive resize.
    if (_tryPatchGeometryInPlace(el, base, edited)) return true;
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

  /// Updates existing Geometry rows' numeric `V=` when command topology matches.
  /// Returns `false` when a full rebuild is required (type/count mismatch).
  bool _tryPatchGeometryInPlace(
      XmlElement el, VsdxShape base, VsdxShape edited) {
    if (base.geometries.length != edited.geometries.length) return false;
    final sections = <XmlElement>[
      for (final child in el.childElements)
        if (child.name.local == 'Section' &&
            child.getAttribute('N') == 'Geometry')
          child,
    ];
    if (sections.length != edited.geometries.length) return false;

    final sx = base.width == 0 ? 1.0 : edited.width / base.width;
    final sy = base.height == 0 ? 1.0 : edited.height / base.height;

    for (var si = 0; si < edited.geometries.length; si++) {
      final gb = base.geometries[si];
      final ge = edited.geometries[si];
      if (gb.commands.length != ge.commands.length) return false;
      if (gb.noFill != ge.noFill ||
          gb.noLine != ge.noLine ||
          gb.noShow != ge.noShow ||
          gb.noSnap != ge.noSnap ||
          gb.noQuickDrag != ge.noQuickDrag) {
        return false;
      }
      final rows = sections[si]
          .childElements
          .where((r) => r.name.local == 'Row')
          .toList();
      if (rows.length != ge.commands.length) return false;
      for (var ri = 0; ri < ge.commands.length; ri++) {
        final cb = gb.commands[ri];
        final ce = ge.commands[ri];
        if (cb.runtimeType != ce.runtimeType) return false;
        final row = rows[ri];
        final expectedT = _commandTypeName(ce);
        if (expectedT != null && row.getAttribute('T') != expectedT) {
          return false;
        }
        final oldVals = _commandNumericCells(cb);
        final newVals = _commandNumericCells(ce);
        if (oldVals == null || newVals == null) return false;
        if (oldVals.keys.toSet() != newVals.keys.toSet()) return false;
        for (final name in newVals.keys) {
          final cell = _ensureCell(row, name);
          final oldV = oldVals[name]!;
          final newV = newVals[name]!;
          if ((oldV - newV).abs() <= _epsilon) continue;
          final keep = _formulaFitsScale(
              cell.getAttribute('F'), oldV, newV, sx: sx, sy: sy);
          _writeValue(cell, _fmt(newV), preserveFormula: keep);
        }
        // Formula-bearing A/E payloads (POLYLINE / NURBS) — only when the
        // rebuilt string differs; those cells are the data, not parametric F=.
        final oldFormula = _commandFormulaCells(cb);
        final newFormula = _commandFormulaCells(ce);
        if (oldFormula != null && newFormula != null) {
          for (final e in newFormula.entries) {
            if (oldFormula[e.key] == e.value) continue;
            _writeValue(_ensureCell(row, e.key), e.value);
          }
        }
      }
    }
    return true;
  }

  /// Visio row `T=` for [cmd], or null when unknown.
  static String? _commandTypeName(VsdxPathCommand cmd) => switch (cmd) {
        MoveTo() => 'MoveTo',
        LineTo() => 'LineTo',
        RelMoveTo() => 'RelMoveTo',
        RelLineTo() => 'RelLineTo',
        CubBezTo() => 'CubBezTo',
        RelCubBezTo() => 'RelCubBezTo',
        QuadBezTo() => 'QuadBezTo',
        RelQuadBezTo() => 'RelQuadBezTo',
        ArcTo() => 'ArcTo',
        RelArcTo() => 'RelArcTo',
        EllipseCmd() => 'Ellipse',
        EllipticalArcTo() => 'EllipticalArcTo',
        RelEllipticalArcTo() => 'RelEllipticalArcTo',
        PolylineTo(:final relative) => relative ? 'RelPolylineTo' : 'PolylineTo',
        InfiniteLineCmd(:final relative) =>
          relative ? 'RelInfiniteLine' : 'InfiniteLine',
        SplineStart(:final relative) =>
          relative ? 'RelSplineStart' : 'SplineStart',
        SplineKnot(:final relative) => relative ? 'RelSplineKnot' : 'SplineKnot',
        NurbsTo(:final relative) => relative ? 'RelNURBSTo' : 'NURBSTo',
      };

  /// Numeric geometry cells (inches or unitless fractions / angles).
  Map<String, double>? _commandNumericCells(VsdxPathCommand cmd) =>
      switch (cmd) {
        MoveTo(:final x, :final y) => {'X': x, 'Y': y},
        LineTo(:final x, :final y) => {'X': x, 'Y': y},
        RelMoveTo(:final fx, :final fy) => {'X': fx, 'Y': fy},
        RelLineTo(:final fx, :final fy) => {'X': fx, 'Y': fy},
        CubBezTo(
          :final x,
          :final y,
          :final x1,
          :final y1,
          :final x2,
          :final y2,
        ) =>
          {'X': x, 'Y': y, 'A': x1, 'B': y1, 'C': x2, 'D': y2},
        RelCubBezTo(
          :final fx,
          :final fy,
          :final fx1,
          :final fy1,
          :final fx2,
          :final fy2,
        ) =>
          {'X': fx, 'Y': fy, 'A': fx1, 'B': fy1, 'C': fx2, 'D': fy2},
        QuadBezTo(:final x, :final y, :final x1, :final y1) =>
          {'X': x, 'Y': y, 'A': x1, 'B': y1},
        RelQuadBezTo(:final fx, :final fy, :final fx1, :final fy1) =>
          {'X': fx, 'Y': fy, 'A': fx1, 'B': fy1},
        ArcTo(:final x, :final y, :final bow) => {'X': x, 'Y': y, 'A': bow},
        RelArcTo(:final fx, :final fy, :final fbow) =>
          {'X': fx, 'Y': fy, 'A': fbow},
        EllipseCmd(
          :final cx,
          :final cy,
          :final aX,
          :final aY,
          :final bX,
          :final bY,
        ) =>
          {'X': cx, 'Y': cy, 'A': aX, 'B': aY, 'C': bX, 'D': bY},
        EllipticalArcTo(
          :final x,
          :final y,
          :final controlX,
          :final controlY,
          :final angle,
          :final eccentricity,
        ) =>
          {
            'X': x,
            'Y': y,
            'A': controlX,
            'B': controlY,
            'C': angle,
            'D': eccentricity,
          },
        RelEllipticalArcTo(
          :final fx,
          :final fy,
          :final fcx,
          :final fcy,
          :final angle,
          :final eccentricity,
        ) =>
          {
            'X': fx,
            'Y': fy,
            'A': fcx,
            'B': fcy,
            'C': angle,
            'D': eccentricity,
          },
        PolylineTo(:final x, :final y) => {'X': x, 'Y': y},
        InfiniteLineCmd(:final x, :final y, :final a, :final b) =>
          {'X': x, 'Y': y, 'A': a, 'B': b},
        SplineStart(
          :final x,
          :final y,
          :final a,
          :final b,
          :final c,
          :final degree,
        ) =>
          {'X': x, 'Y': y, 'A': a, 'B': b, 'C': c, 'D': degree.toDouble()},
        SplineKnot(:final x, :final y, :final knot) =>
          {'X': x, 'Y': y, 'A': knot},
        NurbsTo(:final x, :final y) => {'X': x, 'Y': y},
      };

  Map<String, String>? _commandFormulaCells(VsdxPathCommand cmd) =>
      switch (cmd) {
        PolylineTo(:final vertices, :final relative) => {
            'A': () {
              final buf =
                  StringBuffer(relative ? 'POLYLINE(0,1' : 'POLYLINE(0,0');
              for (final v in vertices) {
                buf.write(',${_fmt(v.x)},${_fmt(v.y)}');
              }
              buf.write(')');
              return buf.toString();
            }(),
          },
        NurbsTo(
          :final x,
          :final y,
          :final controlPoints,
          :final weights,
          :final knots,
          :final degree,
        ) =>
          {
            'E': () {
              final knotLast = knots.isNotEmpty ? knots.last : 1.0;
              final buf = StringBuffer(
                  'NURBS(${_fmt(knotLast)},$degree,${_fmt(x)},${_fmt(y)}');
              for (var i = 0; i < controlPoints.length; i++) {
                final p = controlPoints[i];
                final knot = i < knots.length ? knots[i] : (i + 1).toDouble();
                final weight = i < weights.length ? weights[i] : 1.0;
                buf.write(
                    ',${_fmt(p.x)},${_fmt(p.y)},${_fmt(knot)},${_fmt(weight)}');
              }
              buf.write(')');
              return buf.toString();
            }(),
          },
        _ => null,
      };

  static bool _canRebuild(VsdxGeometry g) => g.commands.every(_canRebuildCmd);

  static bool _canRebuildCmd(VsdxPathCommand c) => switch (c) {
        MoveTo() ||
        LineTo() ||
        RelMoveTo() ||
        RelLineTo() ||
        CubBezTo() ||
        RelCubBezTo() ||
        QuadBezTo() ||
        RelQuadBezTo() ||
        ArcTo() ||
        RelArcTo() ||
        EllipticalArcTo() ||
        RelEllipticalArcTo() ||
        EllipseCmd() ||
        PolylineTo() ||
        InfiniteLineCmd() ||
        SplineStart() ||
        SplineKnot() ||
        NurbsTo() =>
          true,
      };

  static bool _geometriesEqual(List<VsdxGeometry> a, List<VsdxGeometry> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final ga = a[i], gb = b[i];
      if (ga.noFill != gb.noFill ||
          ga.noLine != gb.noLine ||
          ga.noShow != gb.noShow ||
          ga.noSnap != gb.noSnap ||
          ga.noQuickDrag != gb.noQuickDrag ||
          ga.commands.length != gb.commands.length) {
        return false;
      }
      for (var j = 0; j < ga.commands.length; j++) {
        if (ga.commands[j].toString() != gb.commands[j].toString()) {
          return false;
        }
        final fa = ga.formulasAt(j);
        final fb = gb.formulasAt(j);
        if (fa.length != fb.length) return false;
        for (final e in fa.entries) {
          if (fb[e.key] != e.value) return false;
        }
      }
    }
    return true;
  }

  bool _patchColor(XmlElement shape, String cell, VsdxColor? base, VsdxColor? value) {
    if (value == null) return false;
    if (base != null && base.value == value.value) return false;
    // An explicit colour edit overrides any inherited THEMEVAL()/formula, so
    // let _writeValue drop F=/E= (default). Keeping the formula would make
    // Visio/libvisio recompute from the theme and ignore the chosen colour.
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

  /// Rewrite `<Text>` only when the visible plain string changes. Prefer
  /// emitting `<cp>/<pp>` markers for multi-run rich text so Character /
  /// Paragraph row indices stay wired (aligns with how Visio / libvisio
  /// store styled text). Literal `\t` in runs is written back as
  /// `<tp IX="0"/>` (Visio tab-stop marker).
  bool _patchTextContent(XmlElement el, VsdxShape base, VsdxShape edited) {
    final basePlain =
        base.richText.runs.isNotEmpty ? base.richText.plainText : (base.text ?? '');
    final editedPlain = edited.richText.runs.isNotEmpty
        ? edited.richText.plainText
        : (edited.text ?? '');
    if (editedPlain == basePlain) return false;

    XmlElement? textEl;
    for (final child in el.childElements) {
      if (child.name.local == 'Text') {
        textEl = child;
        break;
      }
    }
    if (textEl == null) {
      textEl = XmlElement(XmlName('Text'));
      el.children.add(textEl);
    }
    textEl.children.clear();
    final runs = edited.richText.runs;
    if (runs.isEmpty) {
      _appendTextWithTabs(textEl.children, editedPlain);
    } else if (runs.length == 1) {
      _appendRunText(textEl.children, runs.first);
    } else {
      for (var i = 0; i < runs.length; i++) {
        textEl.children.add(XmlElement(
          XmlName('cp'),
          <XmlAttribute>[XmlAttribute(XmlName('IX'), i.toString())],
        ));
        textEl.children.add(XmlElement(
          XmlName('pp'),
          <XmlAttribute>[XmlAttribute(XmlName('IX'), i.toString())],
        ));
        _appendRunText(textEl.children, runs[i]);
      }
    }
    return true;
  }

  /// Emit one rich-text run: tabs → `<tp/>`, field spans → `<fld IX>`.
  void _appendRunText(List<XmlNode> out, VsdxTextRun run) {
    final text = run.text;
    final spans = [...run.fieldSpans]
      ..sort((a, b) => a.start.compareTo(b.start));
    var i = 0;
    var si = 0;
    var nextTab = 0;
    void emitPlain(String chunk) {
      final n = '\t'.allMatches(chunk).length;
      final slice = run.tabIndices.skip(nextTab).take(n).toList();
      nextTab += n;
      _appendTextWithTabs(out, chunk, slice);
    }

    while (si < spans.length || i < text.length) {
      final nextField =
          si < spans.length ? spans[si].start.clamp(0, text.length) : text.length;
      if (i < nextField) {
        emitPlain(text.substring(i, nextField));
        i = nextField;
      }
      if (si >= spans.length) break;
      final sp = spans[si++];
      final start = sp.start.clamp(0, text.length);
      final end = (sp.start + sp.length).clamp(0, text.length);
      if (start > i) {
        emitPlain(text.substring(i, start));
        i = start;
      }
      final display = start < end ? text.substring(start, end) : '';
      out.add(XmlElement(
        XmlName('fld'),
        <XmlAttribute>[XmlAttribute(XmlName('IX'), sp.ix.toString())],
        display.isEmpty ? const <XmlNode>[] : <XmlNode>[XmlText(display)],
      ));
      if (end > i) i = end;
    }
  }

  /// Split [text] on `\t` and emit Visio `<tp IX="…"/>` markers between chunks.
  /// [tabIndices] supplies the Tabs-row IX for each tab (defaults to 0).
  void _appendTextWithTabs(
    List<XmlNode> out,
    String text, [
    List<int> tabIndices = const <int>[],
  ]) {
    if (!text.contains('\t')) {
      if (text.isNotEmpty) out.add(XmlText(text));
      return;
    }
    final parts = text.split('\t');
    var ti = 0;
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) out.add(XmlText(parts[i]));
      if (i < parts.length - 1) {
        final ix =
            ti < tabIndices.length ? tabIndices[ti++] : 0;
        out.add(XmlElement(
          XmlName('tp'),
          <XmlAttribute>[XmlAttribute(XmlName('IX'), ix.toString())],
        ));
      }
    }
  }

  bool _patchShadow(XmlElement el, VsdxShadow base, VsdxShadow edited) {
    if (base.enabled == edited.enabled &&
        base.color?.value == edited.color?.value &&
        (base.offsetXInches - edited.offsetXInches).abs() <= _epsilon &&
        (base.offsetYInches - edited.offsetYInches).abs() <= _epsilon &&
        (base.blurInches - edited.blurInches).abs() <= _epsilon &&
        (base.transparency - edited.transparency).abs() <= _epsilon) {
      return false;
    }
    var changed = false;
    changed |= _patchInt(
        el, 'ShadowPattern', base.enabled ? 1 : 0, edited.enabled ? 1 : 0);
    changed |= _patchInt(
        el, 'ShdwPattern', base.enabled ? 1 : 0, edited.enabled ? 1 : 0);
    if (edited.enabled) {
      if (edited.color != null) {
        changed |= _patchColor(el, 'ShadowForegnd', base.color, edited.color);
      }
      changed |= _patchLength(
          el, 'ShadowOffsetX', base.offsetXInches, edited.offsetXInches);
      changed |= _patchLength(
          el, 'ShadowOffsetY', base.offsetYInches, edited.offsetYInches);
      changed |=
          _patchLength(el, 'ShadowBlur', base.blurInches, edited.blurInches);
      changed |= _patchRatio(
          el, 'ShadowForegndTrans', base.transparency, edited.transparency);
    }
    return changed;
  }

  bool _patchGlow(XmlElement el, VsdxGlow base, VsdxGlow edited) {
    if (base.enabled == edited.enabled &&
        base.color?.value == edited.color?.value &&
        (base.sizeInches - edited.sizeInches).abs() <= _epsilon &&
        (base.transparency - edited.transparency).abs() <= _epsilon) {
      return false;
    }
    var changed = false;
    if (!edited.enabled) {
      if (base.enabled) {
        _writeValue(_ensureCell(el, 'GlowSize'), '0');
        changed = true;
      }
      return changed;
    }
    changed |=
        _patchLength(el, 'GlowSize', base.sizeInches, edited.sizeInches);
    if (edited.color != null) {
      changed |= _patchColor(el, 'GlowColor', base.color, edited.color);
    }
    changed |= _patchRatio(
        el, 'GlowColorTrans', base.transparency, edited.transparency);
    return changed;
  }

  bool _patchReflection(
      XmlElement el, VsdxReflection base, VsdxReflection edited) {
    if (base.enabled == edited.enabled &&
        (base.sizeInches - edited.sizeInches).abs() <= _epsilon &&
        (base.distanceInches - edited.distanceInches).abs() <= _epsilon &&
        (base.transparency - edited.transparency).abs() <= _epsilon &&
        (base.blurInches - edited.blurInches).abs() <= _epsilon) {
      return false;
    }
    var changed = false;
    if (!edited.enabled) {
      if (base.enabled) {
        _writeValue(_ensureCell(el, 'ReflectionSize'), '0');
        changed = true;
      }
      return changed;
    }
    changed |= _patchLength(
        el, 'ReflectionSize', base.sizeInches, edited.sizeInches);
    changed |= _patchLength(
        el, 'ReflectionDist', base.distanceInches, edited.distanceInches);
    changed |= _patchRatio(
        el, 'ReflectionTransparency', base.transparency, edited.transparency);
    changed |= _patchLength(
        el, 'ReflectionBlur', base.blurInches, edited.blurInches);
    return changed;
  }

  bool _patchGradient(XmlElement el, VsdxFill base, VsdxFill edited) {
    final bg = base.gradient;
    final eg = edited.gradient;
    if (!_gradientsEqual(bg, eg)) {
      // Drop existing FillGradient section(s).
      final existing = <XmlElement>[
        for (final child in el.childElements)
          if (child.name.local == 'Section' &&
              child.getAttribute('N') == 'FillGradient')
            child,
      ];
      for (final s in existing) {
        el.children.remove(s);
      }
      if (eg != null && eg.stops.isNotEmpty) {
        _writeValue(
          _ensureCell(el, 'FillGradientEnabled'),
          '1',
          preserveFormula:
              _cellHasParametricFormula(el, 'FillGradientEnabled'),
        );
        _writeValue(_ensureCell(el, 'FillGradientDir'),
            _gradientDirFromType(eg.type).toString());
        _writeValue(_ensureCell(el, 'FillGradientAngle'), _fmt(eg.angleRad));
        _insertBeforeTextOrShapes(el, _buildFillGradientSection(eg));
      } else {
        _writeValue(
          _ensureCell(el, 'FillGradientEnabled'),
          '0',
          preserveFormula:
              _cellHasParametricFormula(el, 'FillGradientEnabled'),
        );
      }
      return true;
    }
    return false;
  }

  /// Mirror of [_patchGradient] for `LineGradient*` / `<Section N="LineGradient">`.
  bool _patchLineGradient(XmlElement el, VsdxLine base, VsdxLine edited) {
    final bg = base.gradient;
    final eg = edited.gradient;
    if (!_gradientsEqual(bg, eg)) {
      final existing = <XmlElement>[
        for (final child in el.childElements)
          if (child.name.local == 'Section' &&
              child.getAttribute('N') == 'LineGradient')
            child,
      ];
      for (final s in existing) {
        el.children.remove(s);
      }
      if (eg != null && eg.stops.isNotEmpty) {
        _writeValue(
          _ensureCell(el, 'LineGradientEnabled'),
          '1',
          preserveFormula:
              _cellHasParametricFormula(el, 'LineGradientEnabled'),
        );
        _writeValue(_ensureCell(el, 'LineGradientDir'),
            _gradientDirFromType(eg.type).toString());
        _writeValue(_ensureCell(el, 'LineGradientAngle'), _fmt(eg.angleRad));
        _insertBeforeTextOrShapes(el, _buildLineGradientSection(eg));
      } else {
        _writeValue(
          _ensureCell(el, 'LineGradientEnabled'),
          '0',
          preserveFormula:
              _cellHasParametricFormula(el, 'LineGradientEnabled'),
        );
      }
      return true;
    }
    return false;
  }

  static bool _gradientsEqual(VsdxGradient? a, VsdxGradient? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a.type != b.type ||
        (a.angleRad - b.angleRad).abs() > 1e-9 ||
        a.stops.length != b.stops.length) {
      return false;
    }
    for (var i = 0; i < a.stops.length; i++) {
      final sa = a.stops[i], sb = b.stops[i];
      if ((sa.position - sb.position).abs() > 1e-9 ||
          sa.color?.value != sb.color?.value ||
          sa.themeColorIndex != sb.themeColorIndex ||
          (sa.transparency - sb.transparency).abs() > 1e-9) {
        return false;
      }
    }
    return true;
  }

  static int _gradientDirFromType(VsdxGradientType t) => switch (t) {
        VsdxGradientType.linear => 0,
        VsdxGradientType.rectangular => 31,
        VsdxGradientType.radial => 35,
        VsdxGradientType.path => 39,
      };

  /// Patch text-block transform cells so TxtPin / TxtWidth / TxtAngle / margins
  /// survive a save (parser already reads them; previously only VerticalAlign
  /// was written back).
  bool _patchTextBlock(XmlElement el, VsdxTextBlock base, VsdxTextBlock edited) {
    var changed = false;
    changed |= _patchNullableLength(
      el,
      'TxtPinX',
      base.pinXInches,
      edited.pinXInches,
      preserveFormula: _cellHasParametricFormula(el, 'TxtPinX'),
    );
    changed |= _patchNullableLength(
      el,
      'TxtPinY',
      base.pinYInches,
      edited.pinYInches,
      preserveFormula: _cellHasParametricFormula(el, 'TxtPinY'),
    );
    changed |= _patchNullableLength(
      el,
      'TxtLocPinX',
      base.locPinXInches,
      edited.locPinXInches,
      preserveFormula: base.locPinXInches != null &&
          edited.locPinXInches != null &&
          base.widthInches != null &&
          edited.widthInches != null &&
          _sameRatio(base.locPinXInches!, base.widthInches!,
              edited.locPinXInches!, edited.widthInches!),
    );
    changed |= _patchNullableLength(
      el,
      'TxtLocPinY',
      base.locPinYInches,
      edited.locPinYInches,
      preserveFormula: base.locPinYInches != null &&
          edited.locPinYInches != null &&
          base.heightInches != null &&
          edited.heightInches != null &&
          _sameRatio(base.locPinYInches!, base.heightInches!,
              edited.locPinYInches!, edited.heightInches!),
    );
    changed |= _patchNullableLength(
      el,
      'TxtWidth',
      base.widthInches,
      edited.widthInches,
      preserveFormula: _cellHasParametricFormula(el, 'TxtWidth'),
    );
    changed |= _patchNullableLength(
      el,
      'TxtHeight',
      base.heightInches,
      edited.heightInches,
      preserveFormula: _cellHasParametricFormula(el, 'TxtHeight'),
    );
    changed |=
        _patchAngle(el, 'TxtAngle', base.angleRad, edited.angleRad);
    changed |= _patchInt(el, 'VerticalAlign', _vAlignInt(base.verticalAlign),
        _vAlignInt(edited.verticalAlign));
    changed |= _patchInt(
        el, 'HideText', base.hideText ? 1 : 0, edited.hideText ? 1 : 0);
    changed |= _patchInt(
        el, 'TextDirection', base.textDirection, edited.textDirection);
    changed |= _patchLength(el, 'DefaultTabStop', base.defaultTabStopInches,
        edited.defaultTabStopInches);
    if (edited.backgroundColor != null) {
      changed |= _patchColor(
          el, 'TextBkgnd', base.backgroundColor, edited.backgroundColor);
    } else if (base.backgroundColor != null) {
      _writeValue(_ensureCell(el, 'TextBkgnd'), '0');
      changed = true;
    }
    changed |= _patchLength(
        el, 'LeftMargin', base.marginLeftInches, edited.marginLeftInches);
    changed |= _patchLength(
        el, 'RightMargin', base.marginRightInches, edited.marginRightInches);
    changed |= _patchLength(
        el, 'TopMargin', base.marginTopInches, edited.marginTopInches);
    changed |= _patchLength(
        el, 'BottomMargin', base.marginBottomInches, edited.marginBottomInches);
    return changed;
  }

  /// Emit text-block cells for a brand-new shape (non-default values only).
  /// [formulas] carries Txt* `F=` (`SETATREF`, `TEXTWIDTH`, `Width*…`).
  void _appendTextBlockCells(
    List<XmlNode> children,
    VsdxTextBlock b, [
    Map<String, String> formulas = const <String, String>{},
  ]) {
    void addLen(String name, double? v) {
      final f = formulas[name];
      if (v == null && f == null) return;
      children.add(_cell(name, _fmt(v ?? 0), formula: f));
    }

    addLen('TxtPinX', b.pinXInches);
    addLen('TxtPinY', b.pinYInches);
    addLen('TxtLocPinX', b.locPinXInches);
    addLen('TxtLocPinY', b.locPinYInches);
    addLen('TxtWidth', b.widthInches);
    addLen('TxtHeight', b.heightInches);
    if (b.angleRad.abs() > _epsilon || formulas.containsKey('TxtAngle')) {
      children.add(
          _cell('TxtAngle', _fmt(b.angleRad), formula: formulas['TxtAngle']));
    }
    if (b.verticalAlign != VsdxVertAlign.middle) {
      children.add(_cell('VerticalAlign', _vAlignInt(b.verticalAlign).toString()));
    }
    if (b.hideText) children.add(_cell('HideText', '1'));
    if (b.backgroundColor != null) {
      children.add(_cell('TextBkgnd', _hex(b.backgroundColor!)));
    }
    if (b.textDirection != 0) {
      children.add(_cell('TextDirection', b.textDirection.toString()));
    }
    if ((b.defaultTabStopInches - 0.5).abs() > _epsilon) {
      children.add(_cell('DefaultTabStop', _fmt(b.defaultTabStopInches)));
    }
    const d = VsdxTextBlock.defaults;
    if ((b.marginLeftInches - d.marginLeftInches).abs() > _epsilon) {
      children.add(_cell('LeftMargin', _fmt(b.marginLeftInches)));
    }
    if ((b.marginRightInches - d.marginRightInches).abs() > _epsilon) {
      children.add(_cell('RightMargin', _fmt(b.marginRightInches)));
    }
    if ((b.marginTopInches - d.marginTopInches).abs() > _epsilon) {
      children.add(_cell('TopMargin', _fmt(b.marginTopInches)));
    }
    if ((b.marginBottomInches - d.marginBottomInches).abs() > _epsilon) {
      children.add(_cell('BottomMargin', _fmt(b.marginBottomInches)));
    }
  }

  // A cell's `V` is always in Visio's internal units — inches for length,
  // radians for angle — regardless of its `U` display attribute, so these
  // patchers write the model value verbatim and leave `U` alone. (Mirrors
  // readLengthInches / readAngleRadians.)
  bool _patchLength(
    XmlElement shape,
    String cell,
    double base,
    double value, {
    bool preserveFormula = false,
  }) {
    if ((base - value).abs() <= _epsilon) return false;
    _writeValue(_ensureCell(shape, cell), _fmt(value),
        preserveFormula: preserveFormula);
    return true;
  }

  bool _patchNullableLength(
    XmlElement shape,
    String cell,
    double? base,
    double? value, {
    bool preserveFormula = false,
  }) {
    if (value == null) return false;
    if (base != null && (base - value).abs() <= _epsilon) return false;
    _writeValue(_ensureCell(shape, cell), _fmt(value),
        preserveFormula: preserveFormula);
    return true;
  }

  bool _patchAngle(XmlElement shape, String cell, double base, double value) {
    if ((base - value).abs() <= _epsilon) return false;
    _writeValue(_ensureCell(shape, cell), _fmt(value));
    return true;
  }

  bool _patchBool(XmlElement shape, String cell, bool base, bool value) {
    if (base == value) return false;
    _writeValue(_ensureCell(shape, cell), value ? '1' : '0');
    return true;
  }

  /// True when [a]/[refA] ≈ [b]/[refB] (relative position unchanged).
  static bool _sameRatio(double a, double refA, double b, double refB) {
    if (refA.abs() <= _epsilon && refB.abs() <= _epsilon) return true;
    if (refA.abs() <= _epsilon || refB.abs() <= _epsilon) return false;
    return ((a / refA) - (b / refB)).abs() <= 1e-4;
  }

  /// Keep `F=` when the new cached `V` still matches a Width/Height resize of
  /// the old value (or is unchanged). Otherwise the formula is stale and must
  /// be stripped so Visio honours the literal.
  static bool _formulaFitsScale(
    String? formula,
    double oldV,
    double newV, {
    required double sx,
    required double sy,
  }) {
    if (formula == null || formula.isEmpty || formula == 'No Formula') {
      return false;
    }
    if (formula == 'Inh') return true;
    final tol = _epsilon + (oldV.abs() + newV.abs()) * 1e-6;
    if (oldV.abs() <= _epsilon && newV.abs() <= _epsilon) return true;
    for (final s in <double>[sx, sy, 1.0]) {
      if ((newV - oldV * s).abs() <= tol) return true;
    }
    return false;
  }

  /// Visio protection cells written for a drawio-style locked shape. All are
  /// set to `1` when locked and back to `0` when unlocked. `LockMoveX` is the
  /// canonical bit the parser reads to recover the locked state.
  static const _lockCells = <String>[
    'LockMoveX',
    'LockMoveY',
    'LockWidth',
    'LockHeight',
    'LockAspect',
    'LockRotate',
    'LockDelete',
    'LockTextEdit',
    'LockGroup',
    'LockCalcWH',
    'LockFormat',
    'LockBegin',
    'LockEnd',
    'LockVtxEdit',
    'LockSelect',
    'LockCrop',
    'LockCustProp',
    'LockFromGroupFormat',
    'LockThemeColors',
    'LockThemeEffects',
    'LockThemeConnectors',
    'LockThemeFonts',
    'LockThemeIndex',
    'LockReplace',
    'LockVariation',
    'LockPreview',
  ];

  /// Patch the shape's protection cells to reflect [edited]'s locked flag.
  /// Only writes when the flag actually flipped relative to the baseline.
  bool _patchLock(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (base.locked == edited.locked) return false;
    final v = edited.locked ? '1' : '0';
    for (final name in _lockCells) {
      _writeValue(_ensureCell(el, name), v);
    }
    return true;
  }

  /// Set `V=`. When [preserveFormula] is false, drop stale `F=`/`E=` so Visio
  /// keeps our literal instead of recomputing over it.
  void _writeValue(
    XmlElement cell,
    String value, {
    bool preserveFormula = false,
  }) {
    cell.setAttribute('V', value);
    if (!preserveFormula) {
      if (cell.getAttribute('F') != null) cell.removeAttribute('F');
      if (cell.getAttribute('E') != null) cell.removeAttribute('E');
    }
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

  XmlElement _buildShapeElement(
    VsdxShape s, {
    Map<String, String> imageRels = const <String, String>{},
    Map<int, List<XmlNode>> opaqueById = const <int, List<XmlNode>>{},
  }) {
    if (s.hasImage) return _buildPictureElement(s, imageRels);
    // --- XForm ---------------------------------------------------------------
    final children = <XmlNode>[
      _cell('PinX', _fmt(s.pinX), formula: s.formulas['PinX']),
      _cell('PinY', _fmt(s.pinY), formula: s.formulas['PinY']),
      _cell('Width', _fmt(s.width), formula: s.formulas['Width']),
      _cell('Height', _fmt(s.height), formula: s.formulas['Height']),
    ];
    // LocPin — only when it isn't the shape centre (the Visio default the
    // parser assumes when the cells are absent). Off-centre pins arise on
    // regrouped stencil shapes and must survive the rebuild.
    if ((s.effectiveLocPinX - s.width / 2).abs() > _epsilon ||
        s.formulas.containsKey('LocPinX')) {
      children.add(_cell('LocPinX', _fmt(s.effectiveLocPinX),
          formula: s.formulas['LocPinX']));
    }
    if ((s.effectiveLocPinY - s.height / 2).abs() > _epsilon ||
        s.formulas.containsKey('LocPinY')) {
      children.add(_cell('LocPinY', _fmt(s.effectiveLocPinY),
          formula: s.formulas['LocPinY']));
    }
    children.add(_cell('Angle', _fmt(s.angleRad), formula: s.formulas['Angle']));
    if (s.flipX) children.add(_cell('FlipX', '1'));
    if (s.flipY) children.add(_cell('FlipY', '1'));
    if (s.is1D) {
      children
        ..add(_cell('BeginX', _fmt(s.beginX ?? 0),
            formula: s.formulas['BeginX']))
        ..add(_cell('BeginY', _fmt(s.beginY ?? 0),
            formula: s.formulas['BeginY']))
        ..add(_cell('EndX', _fmt(s.endX ?? 0), formula: s.formulas['EndX']))
        ..add(_cell('EndY', _fmt(s.endY ?? 0), formula: s.formulas['EndY']));
    }
    final cp = s.connectorProps;
    if (cp != null && !cp.isEmpty) {
      if (cp.begTrigger != null || s.formulas.containsKey('BegTrigger')) {
        children.add(_cell('BegTrigger', cp.begTrigger ?? '0',
            formula: s.formulas['BegTrigger']));
      }
      if (cp.endTrigger != null || s.formulas.containsKey('EndTrigger')) {
        children.add(_cell('EndTrigger', cp.endTrigger ?? '0',
            formula: s.formulas['EndTrigger']));
      }
      if (cp.glueType != null) {
        children.add(_cell('GlueType', cp.glueType.toString()));
      }
      if (cp.conFixedCode != null) {
        children.add(_cell('ConFixedCode', cp.conFixedCode.toString()));
      }
      if (cp.dynFeedback != null) {
        children.add(_cell('DynFeedback', cp.dynFeedback.toString()));
      }
      if (cp.noLiveDynamics) {
        children.add(_cell('NoLiveDynamics', '1'));
      }
      if (cp.conLineJumpCode != null) {
        children.add(_cell('ConLineJumpCode', cp.conLineJumpCode.toString()));
      }
      if (cp.conLineRouteExt != null) {
        children.add(_cell('ConLineRouteExt', cp.conLineRouteExt.toString()));
      }
      if (cp.conLineJumpStyle != null) {
        children.add(_cell('ConLineJumpStyle', cp.conLineJumpStyle.toString()));
      }
      if (cp.conLineJumpDirX != null) {
        children.add(_cell('ConLineJumpDirX', cp.conLineJumpDirX.toString()));
      }
      if (cp.conLineJumpDirY != null) {
        children.add(_cell('ConLineJumpDirY', cp.conLineJumpDirY.toString()));
      }
      if (cp.shapeRouteStyle != null) {
        children.add(_cell('ShapeRouteStyle', cp.shapeRouteStyle.toString()));
      }
      if (cp.shapePlaceFlip != null) {
        children.add(_cell('ShapePlaceFlip', cp.shapePlaceFlip.toString()));
      }
    } else {
      if (s.formulas.containsKey('BegTrigger')) {
        children.add(_cell('BegTrigger', '0', formula: s.formulas['BegTrigger']));
      }
      if (s.formulas.containsKey('EndTrigger')) {
        children.add(_cell('EndTrigger', '0', formula: s.formulas['EndTrigger']));
      }
    }
    // --- Fill ----------------------------------------------------------------
    if (s.fill.foreground != null) {
      children.add(_cell('FillForegnd', _hex(s.fill.foreground!),
          formula: s.formulas['FillForegnd']));
    } else if (s.fill.themeForegroundIndex != null) {
      children.add(_cell('FillForegnd', '0',
          formula: s.formulas['FillForegnd'] ?? 'THEMEVAL()'));
      children.add(
          _cell('QuickStyleFillColor', s.fill.themeForegroundIndex!.toString()));
    } else if (s.formulas.containsKey('FillForegnd')) {
      children.add(_cell('FillForegnd', '0', formula: s.formulas['FillForegnd']));
    }
    if (s.fill.background != null) {
      children.add(_cell('FillBkgnd', _hex(s.fill.background!),
          formula: s.formulas['FillBkgnd']));
    } else if (s.fill.themeBackgroundIndex != null) {
      children.add(_cell('FillBkgnd', '0',
          formula: s.formulas['FillBkgnd'] ?? 'THEMEVAL()'));
    } else if (s.formulas.containsKey('FillBkgnd')) {
      children.add(_cell('FillBkgnd', '0', formula: s.formulas['FillBkgnd']));
    }
    children.add(_cell('FillPattern', s.fill.pattern.toString(),
        formula: s.formulas['FillPattern']));
    if (s.fill.foregroundTransparency > _epsilon) {
      children.add(
          _cell('FillForegndTrans', _fmt(s.fill.foregroundTransparency)));
    }
    if (s.fill.backgroundTransparency > _epsilon) {
      children.add(
          _cell('FillBkgndTrans', _fmt(s.fill.backgroundTransparency)));
    }
    // --- Line ----------------------------------------------------------------
    if (s.line.color != null) {
      children.add(_cell('LineColor', _hex(s.line.color!),
          formula: s.formulas['LineColor']));
    } else if (s.line.themeColorIndex != null) {
      children.add(_cell('LineColor', '0',
          formula: s.formulas['LineColor'] ?? 'THEMEVAL()'));
      children
          .add(_cell('QuickStyleLineColor', s.line.themeColorIndex!.toString()));
    } else if (s.formulas.containsKey('LineColor')) {
      children.add(_cell('LineColor', '0', formula: s.formulas['LineColor']));
    }
    children
      ..add(_cell('LineWeight', _fmt(s.line.weightInches)))
      ..add(_cell('LinePattern', s.line.pattern.toString(),
          formula: s.formulas['LinePattern']));
    if (s.line.cap != LineCap.round) {
      children.add(_cell('LineCap', _lineCapInt(s.line.cap).toString()));
    }
    if (s.line.transparency > _epsilon) {
      children.add(_cell('LineColorTrans', _fmt(s.line.transparency)));
    }
    if (s.line.beginArrow != 0) {
      children.add(_cell('BeginArrow', s.line.beginArrow.toString()));
      children.add(_cell(
          'BeginArrowSize',
          _arrowSizeToBucket(s.line.beginArrowSizeInches).toString()));
    }
    if (s.line.endArrow != 0) {
      children.add(_cell('EndArrow', s.line.endArrow.toString()));
      children.add(_cell(
          'EndArrowSize',
          _arrowSizeToBucket(s.line.endArrowSizeInches).toString()));
    }
    if (s.line.roundingInches > _epsilon) {
      children.add(_cell('Rounding', _fmt(s.line.roundingInches)));
    }
    if (s.line.softEdgesInches > _epsilon) {
      children.add(_cell('SoftEdgesSize', _fmt(s.line.softEdgesInches)));
    }
    if (s.line.compoundType != 0) {
      children.add(_cell('CompoundType', s.line.compoundType.toString()));
    }
    if (s.layerMemberIds.isNotEmpty) {
      children.add(_cell('LayerMember', s.layerMemberIds.join(';')));
    }
    // --- Effects / text block ------------------------------------------------
    if (s.shadow.enabled) {
      children.add(_cell('ShadowPattern', '1'));
      children.add(_cell('ShdwPattern', '1'));
      if (s.shadow.color != null) {
        children.add(_cell('ShadowForegnd', _hex(s.shadow.color!)));
      }
      children
        ..add(_cell('ShadowOffsetX', _fmt(s.shadow.offsetXInches)))
        ..add(_cell('ShadowOffsetY', _fmt(s.shadow.offsetYInches)))
        ..add(_cell('ShadowBlur', _fmt(s.shadow.blurInches)))
        ..add(_cell('ShadowForegndTrans', _fmt(s.shadow.transparency)));
    }
    if (s.glow.enabled) {
      children.add(_cell('GlowSize', _fmt(s.glow.sizeInches)));
      if (s.glow.color != null) {
        children.add(_cell('GlowColor', _hex(s.glow.color!)));
      }
      children.add(_cell('GlowColorTrans', _fmt(s.glow.transparency)));
    }
    if (s.reflection.enabled) {
      children
        ..add(_cell('ReflectionSize', _fmt(s.reflection.sizeInches)))
        ..add(_cell('ReflectionDist', _fmt(s.reflection.distanceInches)))
        ..add(_cell(
            'ReflectionTransparency', _fmt(s.reflection.transparency)))
        ..add(_cell('ReflectionBlur', _fmt(s.reflection.blurInches)));
    }
    if (s.fill.gradient != null && s.fill.gradient!.stops.isNotEmpty) {
      children
        ..add(_cell('FillGradientEnabled', '1'))
        ..add(_cell('FillGradientDir',
            _gradientDirFromType(s.fill.gradient!.type).toString()))
        ..add(_cell('FillGradientAngle', _fmt(s.fill.gradient!.angleRad)));
    }
    if (s.line.gradient != null && s.line.gradient!.stops.isNotEmpty) {
      children
        ..add(_cell('LineGradientEnabled', '1'))
        ..add(_cell('LineGradientDir',
            _gradientDirFromType(s.line.gradient!.type).toString()))
        ..add(_cell('LineGradientAngle', _fmt(s.line.gradient!.angleRad)));
    }
    _appendTextBlockCells(children, s.richText.textBlock, s.formulas);
    if (s.objType != null) {
      children.add(_cell('ObjType', s.objType.toString()));
    }
    if (s.resizeMode != null) {
      children.add(_cell('ResizeMode', s.resizeMode.toString()));
    }
    if (s.eventDblClick != null || s.formulas.containsKey('EventDblClick')) {
      children.add(_cell(
        'EventDblClick',
        s.eventDblClick ?? '0',
        formula: s.formulas['EventDblClick'],
      ));
    }
    if (s.noAlignBox) children.add(_cell('NoAlignBox', '1'));
    if (s.shapeSplittable) children.add(_cell('ShapeSplittable', '1'));
    if (s.themeIndex != null) {
      children.add(_cell('ThemeIndex', s.themeIndex.toString()));
    }
    if (s.quickStyleFillMatrix != null) {
      children.add(
          _cell('QuickStyleFillMatrix', s.quickStyleFillMatrix.toString()));
    }
    if (s.quickStyleLineMatrix != null) {
      children.add(
          _cell('QuickStyleLineMatrix', s.quickStyleLineMatrix.toString()));
    }
    if (s.quickStyleEffectsMatrix != null) {
      children.add(_cell(
          'QuickStyleEffectsMatrix', s.quickStyleEffectsMatrix.toString()));
    }
    if (s.quickStyleFontMatrix != null) {
      children.add(
          _cell('QuickStyleFontMatrix', s.quickStyleFontMatrix.toString()));
    }
    if (s.isTextEditTarget) children.add(_cell('IsTextEditTarget', '1'));
    if (s.dontMoveChildren) children.add(_cell('DontMoveChildren', '1'));
    if (s.selectMode != null) {
      children.add(_cell('SelectMode', s.selectMode.toString()));
    }
    if (s.displayMode != null) {
      children.add(_cell('DisplayMode', s.displayMode.toString()));
    }
    if (s.locked) {
      for (final name in _lockCells) {
        children.add(_cell(name, '1'));
      }
    }
    // --- Sections ------------------------------------------------------------
    // Character / Paragraph — one row per rich-text run (matches <cp>/<pp>).
    if (s.richText.runs.isNotEmpty) {
      children
        ..add(_buildCharacterSection(s.richText.runs))
        ..add(_buildParagraphSection(s.richText.runs));
    }
    if (s.richText.tabSets.isNotEmpty) {
      children.add(_buildTabsSection(s.richText.tabSets));
    }
    if (s.fill.gradient != null && s.fill.gradient!.stops.isNotEmpty) {
      children.add(_buildFillGradientSection(s.fill.gradient!));
    }
    if (s.line.gradient != null && s.line.gradient!.stops.isNotEmpty) {
      children.add(_buildLineGradientSection(s.line.gradient!));
    }
    var ix = 0;
    for (final g in s.geometries) {
      final section = _buildGeometrySection(g, ix++);
      if (section != null) children.add(section);
    }
    if (s.userProperties.isNotEmpty) {
      children.add(_buildPropertySection(s.userProperties));
    }
    if (s.userCells.isNotEmpty) {
      children.add(_buildUserSection(s.userCells));
    }
    if (s.controls.isNotEmpty) {
      children.add(_buildControlSection(s.controls));
    }
    if (s.scratch.isNotEmpty) {
      children.add(_buildScratchSection(s.scratch));
    }
    if (s.fields.isNotEmpty) {
      children.add(_buildFieldSection(s.fields));
    }
    if (s.actions.isNotEmpty) {
      children.add(_buildActionsSection(s.actions));
    }
    if (s.hyperlinks.isNotEmpty) {
      children.add(_buildHyperlinkSection(s.hyperlinks));
    }
    if (s.connectionPoints.isNotEmpty) {
      children.add(_buildConnectionSection(s.connectionPoints));
    }
    // Unmodelled cells / sections from the prior XML (group rebuild).
    final opaque = opaqueById[s.id];
    if (opaque != null && opaque.isNotEmpty) {
      children.addAll(opaque.map((n) => n.copy()));
    }
    // --- Text ----------------------------------------------------------------
    if (s.richText.runs.isNotEmpty) {
      final textEl = XmlElement(XmlName('Text'));
      if (s.richText.runs.length == 1) {
        _appendRunText(textEl.children, s.richText.runs.first);
      } else {
        for (var i = 0; i < s.richText.runs.length; i++) {
          textEl.children.add(XmlElement(
            XmlName('cp'),
            <XmlAttribute>[XmlAttribute(XmlName('IX'), i.toString())],
          ));
          textEl.children.add(XmlElement(
            XmlName('pp'),
            <XmlAttribute>[XmlAttribute(XmlName('IX'), i.toString())],
          ));
          _appendRunText(textEl.children, s.richText.runs[i]);
        }
      }
      if (textEl.children.isNotEmpty) children.add(textEl);
    } else if (s.text != null && s.text!.isNotEmpty) {
      final textEl = XmlElement(XmlName('Text'));
      _appendTextWithTabs(textEl.children, s.text!);
      children.add(textEl);
    }
    final isGroup = s.children.isNotEmpty;
    if (isGroup) {
      children.add(XmlElement(XmlName('Shapes'), const <XmlAttribute>[], <XmlNode>[
        for (final c in s.children)
          _buildShapeElement(c, imageRels: imageRels, opaqueById: opaqueById),
      ]));
    }
    return XmlElement(
      XmlName('Shape'),
      <XmlAttribute>[
        XmlAttribute(XmlName('ID'), s.id.toString()),
        XmlAttribute(XmlName('NameU'), s.name),
        XmlAttribute(XmlName('Name'), s.name),
        XmlAttribute(XmlName('Type'), isGroup ? 'Group' : 'Shape'),
        if (s.masterId != null)
          XmlAttribute(XmlName('Master'), s.masterId!.toString()),
        if (s.masterShapeId != null)
          XmlAttribute(XmlName('MasterShape'), s.masterShapeId!.toString()),
        if (s.lineStyleId != null)
          XmlAttribute(XmlName('LineStyle'), s.lineStyleId!.toString()),
        if (s.fillStyleId != null)
          XmlAttribute(XmlName('FillStyle'), s.fillStyleId!.toString()),
        if (s.textStyleId != null)
          XmlAttribute(XmlName('TextStyle'), s.textStyleId!.toString()),
      ],
      children,
    );
  }

  /// Style bitmask for a `<Cell N="Style">` value: bold=0x01, italic=0x02,
  /// underline=0x04, smallcaps=0x08 (mirrors libvisio / [RichTextParser]).
  static int _charStyleBits(VsdxCharStyle c) =>
      (c.style.bold ? 0x01 : 0) |
      (c.style.italic ? 0x02 : 0) |
      (c.underline ? 0x04 : 0) |
      (c.style.smallCaps ? 0x08 : 0);

  /// Build `<Section N="Character">` with one row per rich-text run.
  XmlElement _buildCharacterSection(List<VsdxTextRun> runs) {
    final rows = <XmlNode>[
      for (var i = 0; i < runs.length; i++)
        XmlElement(
          XmlName('Row'),
          <XmlAttribute>[XmlAttribute(XmlName('IX'), i.toString())],
          _charCells(runs[i].charStyle),
        ),
    ];
    return XmlElement(
      XmlName('Section'),
      <XmlAttribute>[XmlAttribute(XmlName('N'), 'Character')],
      rows,
    );
  }

  List<XmlNode> _charCells(VsdxCharStyle c) {
    final cells = <XmlNode>[
      _cell('Size', _fmt(c.fontSizeInches)),
      _cell('Style', _charStyleBits(c).toString()),
    ];
    if (c.color != null) {
      cells.add(_cell('Color', _hex(c.color!)));
    } else if (c.themeColorIndex != null) {
      cells.add(_cell('Color', '0', formula: 'THEMEVAL()'));
    }
    if (c.fontFamily != null && c.fontFamily!.isNotEmpty) {
      cells.add(_cell('Font', c.fontFamily!));
    }
    if (c.strikethrough) cells.add(_cell('Strikethru', '1'));
    if (c.doubleUnderline) cells.add(_cell('DblUnderline', '1'));
    if (c.doubleStrikethrough) cells.add(_cell('DoubleStrikethrough', '1'));
    if (c.overline) cells.add(_cell('Overline', '1'));
    if (c.letterSpacingInches.abs() > _epsilon) {
      cells.add(_cell('Letterspace', _fmt(c.letterSpacingInches)));
    }
    if (c.position != VsdxTextPosition.normal) {
      cells.add(_cell('Pos', _textPositionInt(c.position).toString()));
    }
    if (c.textCase != VsdxTextCase.normal) {
      cells.add(_cell('Case', _textCaseInt(c.textCase).toString()));
    }
    if ((c.fontScale - 1.0).abs() > _epsilon) {
      cells.add(_cell('FontScale', _fmt(c.fontScale)));
    }
    if (c.transparency > _epsilon) {
      cells.add(_cell('ColorTrans', _fmt(c.transparency)));
    }
    if (c.asianFont != null && c.asianFont!.isNotEmpty) {
      cells.add(_cell('AsianFont', c.asianFont!));
    }
    if (c.complexScriptFont != null && c.complexScriptFont!.isNotEmpty) {
      cells.add(_cell('ComplexScriptFont', c.complexScriptFont!));
    }
    if (c.langId != null && c.langId!.isNotEmpty) {
      cells.add(_cell('LangID', c.langId!));
    }
    if (c.complexScriptSizeInches != null) {
      cells.add(_cell('ComplexScriptSize', _fmt(c.complexScriptSizeInches!)));
    }
    return cells;
  }

  /// Build `<Section N="Paragraph">` with one row per rich-text run.
  XmlElement _buildParagraphSection(List<VsdxTextRun> runs) {
    final rows = <XmlNode>[
      for (var i = 0; i < runs.length; i++)
        XmlElement(
          XmlName('Row'),
          <XmlAttribute>[XmlAttribute(XmlName('IX'), i.toString())],
          _paraCells(runs[i].paraStyle),
        ),
    ];
    return XmlElement(
      XmlName('Section'),
      <XmlAttribute>[XmlAttribute(XmlName('N'), 'Paragraph')],
      rows,
    );
  }

  List<XmlNode> _paraCells(VsdxParaStyle p) {
    final cells = <XmlNode>[
      _cell('HorzAlign', _alignToInt(p.horizontalAlign).toString()),
    ];
    if (p.indentFirstInches.abs() > _epsilon) {
      cells.add(_cell('IndFirst', _fmt(p.indentFirstInches)));
    }
    if (p.indentLeftInches.abs() > _epsilon) {
      cells.add(_cell('IndLeft', _fmt(p.indentLeftInches)));
    }
    if (p.indentRightInches.abs() > _epsilon) {
      cells.add(_cell('IndRight', _fmt(p.indentRightInches)));
    }
    if (p.spaceBeforeInches.abs() > _epsilon) {
      cells.add(_cell('SpBefore', _fmt(p.spaceBeforeInches)));
    }
    if (p.spaceAfterInches.abs() > _epsilon) {
      cells.add(_cell('SpAfter', _fmt(p.spaceAfterInches)));
    }
    final spLine = _spLineValue(p);
    if (spLine != null) {
      cells.add(_cell('SpLine', _fmt(spLine)));
    }
    if (p.bullet != 0) {
      cells.add(_cell('Bullet', p.bullet.toString()));
    }
    if (p.bulletStr != null && p.bulletStr!.isNotEmpty) {
      cells.add(_cell('BulletStr', p.bulletStr!));
    }
    if (p.bulletFont != null && p.bulletFont!.isNotEmpty) {
      cells.add(_cell('BulletFont', p.bulletFont!));
    }
    if (p.bulletFontSizeInches != null) {
      cells.add(_cell('BulletFontSize', _fmt(p.bulletFontSizeInches!)));
    }
    if (p.textPosAfterBulletInches.abs() > _epsilon) {
      cells.add(_cell('TextPosAfterBullet', _fmt(p.textPosAfterBulletInches)));
    }
    if (p.flags != 0) {
      cells.add(_cell('Flags', p.flags.toString()));
    }
    return cells;
  }

  /// `<Section N="Tabs">` — libvisio `PositionN` / `AlignmentN` cells.
  XmlElement _buildTabsSection(List<VsdxTabSet> sets) {
    final rows = <XmlNode>[
      for (final set in sets)
        XmlElement(
          XmlName('Row'),
          <XmlAttribute>[XmlAttribute(XmlName('IX'), set.ix.toString())],
          <XmlNode>[
            for (var i = 0; i < set.stops.length; i++) ...[
              _cell('Position$i', _fmt(set.stops[i].positionInches)),
              _cell('Alignment$i', set.stops[i].alignment.toString()),
            ],
          ],
        ),
    ];
    return XmlElement(
      XmlName('Section'),
      <XmlAttribute>[XmlAttribute(XmlName('N'), 'Tabs')],
      rows,
    );
  }

  /// Clone unmodelled top-level Cell / Section nodes for group rebuild.
  List<XmlNode> _extractOpaqueChildren(XmlElement shape) {
    final out = <XmlNode>[];
    for (final child in shape.childElements) {
      switch (child.name.local) {
        case 'Cell':
          final n = child.getAttribute('N');
          if (n != null && !_modeledShapeCells.contains(n)) {
            out.add(child.copy());
          }
        case 'Section':
          final n = child.getAttribute('N');
          if (n != null && !_modeledSections.contains(n)) {
            out.add(child.copy());
          }
        default:
          break;
      }
    }
    return out;
  }

  /// Cells that `_buildShapeElement` may emit (everything else is opaque).
  static const _modeledShapeCells = <String>{
    'PinX', 'PinY', 'Width', 'Height', 'LocPinX', 'LocPinY', 'Angle',
    'FlipX', 'FlipY', 'BeginX', 'BeginY', 'EndX', 'EndY',
    'BegTrigger', 'EndTrigger', 'GlueType', 'ConFixedCode', 'DynFeedback',
    'NoLiveDynamics', 'ConLineJumpCode', 'ShapeRouteStyle',
    'ConLineRouteExt', 'ConLineJumpStyle', 'ConLineJumpDirX', 'ConLineJumpDirY',
    'ShapePlaceFlip',
    'FillForegnd', 'FillBkgnd', 'FillPattern', 'FillForegndTrans',
    'FillBkgndTrans', 'FillGradientEnabled', 'FillGradientDir',
    'FillGradientAngle', 'QuickStyleFillColor',
    'LineColor', 'LineWeight', 'LinePattern', 'LineCap', 'LineColorTrans',
    'BeginArrow', 'BeginArrowSize', 'EndArrow', 'EndArrowSize', 'Rounding',
    'SoftEdgesSize', 'CompoundType',
    'LineGradientEnabled', 'LineGradientDir', 'LineGradientAngle',
    'QuickStyleLineColor', 'LayerMember',
    'ShadowPattern', 'ShdwPattern', 'ShadowForegnd', 'ShadowOffsetX',
    'ShadowOffsetY', 'ShadowBlur', 'ShadowForegndTrans',
    'GlowSize', 'GlowColor', 'GlowColorTrans',
    'ReflectionSize', 'ReflectionDist', 'ReflectionTransparency',
    'ReflectionBlur',
    'TxtPinX', 'TxtPinY', 'TxtWidth', 'TxtHeight', 'TxtLocPinX', 'TxtLocPinY',
    'TxtAngle', 'VerticalAlign', 'LeftMargin', 'RightMargin', 'TopMargin',
    'BottomMargin', 'HideText', 'TextBkgnd', 'TextDirection', 'DefaultTabStop',
    'LockMoveX', 'LockMoveY', 'LockWidth', 'LockHeight', 'LockAspect',
    'LockRotate', 'LockDelete', 'LockTextEdit',
    'LockGroup', 'LockCalcWH', 'LockFormat', 'LockBegin', 'LockEnd',
    'LockVtxEdit', 'LockSelect',
    'LockCrop', 'LockCustProp', 'LockFromGroupFormat',
    'LockThemeColors', 'LockThemeEffects', 'LockThemeConnectors',
    'LockThemeFonts', 'LockThemeIndex', 'LockReplace', 'LockVariation',
    'LockPreview',
    'ObjType', 'ResizeMode', 'EventDblClick', 'NoAlignBox', 'ShapeSplittable',
    'ThemeIndex', 'QuickStyleFillMatrix', 'QuickStyleLineMatrix',
    'QuickStyleEffectsMatrix', 'QuickStyleFontMatrix',
    'IsTextEditTarget', 'DontMoveChildren', 'SelectMode', 'DisplayMode',
  };

  static const _modeledSections = <String>{
    'Geometry',
    'Character',
    'Paragraph',
    'Tabs',
    'Property',
    'User',
    'Control',
    'Scratch',
    'Field',
    'Hyperlink',
    'Actions',
    'Connection',
    'FillGradient',
    'LineGradient',
  };

  /// Build a Visio `Type="Foreign"` picture shape: XForm cells plus the
  /// `<ForeignData>` element pointing (via [imageRels]) at the embedded media
  /// relationship. Round-trips back through [PageParser._resolveForeignDataPart].
  XmlElement _buildPictureElement(VsdxShape s, Map<String, String> imageRels) {
    final rId = imageRels[s.imagePartName];
    final foreignType = s.foreignType ??
        VsdxImage.foreignTypeFor(
          mimeType: '',
          partName: s.imagePartName ?? '',
        );
    final compression = s.foreignCompressionType ??
        (foreignType == 'Bitmap'
            ? VsdxImage.compressionTypeFor(
                mimeType: '',
                partName: s.imagePartName ?? '',
              )
            : null);
    final children = <XmlNode>[
      _cell('PinX', _fmt(s.pinX)),
      _cell('PinY', _fmt(s.pinY)),
      _cell('Width', _fmt(s.width)),
      _cell('Height', _fmt(s.height)),
      _cell('LocPinX', _fmt(s.width / 2)),
      _cell('LocPinY', _fmt(s.height / 2)),
      _cell('Angle', _fmt(s.angleRad)),
      if (s.flipX) _cell('FlipX', '1'),
      if (s.flipY) _cell('FlipY', '1'),
    ];
    if (s.locked) {
      for (final name in _lockCells) {
        children.add(_cell(name, '1'));
      }
    }
    if (s.text != null && s.text!.isNotEmpty) {
      children.add(XmlElement(XmlName('Text'), const [], [XmlText(s.text!)]));
    }
    if (rId != null) {
      children.add(XmlElement(
        XmlName('ForeignData'),
        <XmlAttribute>[
          XmlAttribute(XmlName('ForeignType'), foreignType),
          if (compression != null && compression.isNotEmpty)
            XmlAttribute(XmlName('CompressionType'), compression),
        ],
        <XmlNode>[
          XmlElement(XmlName('Rel'),
              <XmlAttribute>[XmlAttribute(XmlName('id', 'r'), rId)]),
        ],
      ));
    }
    return XmlElement(
      XmlName('Shape'),
      <XmlAttribute>[
        XmlAttribute(XmlName('ID'), s.id.toString()),
        XmlAttribute(XmlName('NameU'), s.name),
        XmlAttribute(XmlName('Name'), s.name),
        XmlAttribute(XmlName('Type'), 'Foreign'),
      ],
      children,
    );
  }

  /// Build a fresh `<Section N="Property">` for a brand-new shape's Shape Data.
  XmlElement _buildPropertySection(List<VsdxUserProperty> props) {
    var ix = 1;
    final rows = <XmlNode>[
      for (final p in props)
        XmlElement(
          XmlName('Row'),
          <XmlAttribute>[
            XmlAttribute(XmlName('N'), p.name),
            XmlAttribute(XmlName('IX'), (ix++).toString()),
          ],
          <XmlNode>[
            if (p.label != null) _cell('Label', p.label!),
            _cell('Value', p.value ?? '', formula: p.valueFormula),
            if (p.prompt != null) _cell('Prompt', p.prompt!),
            if (p.format != null) _cell('Format', p.format!),
            _cell('Type', p.type.toString()),
            if (p.sortKey != null) _cell('SortKey', p.sortKey!),
            if (p.invisible) _cell('Invisible', '1'),
            if (p.verify) _cell('Verify', '1'),
            if (p.ask) _cell('Ask', '1'),
            if (p.dataLinked) _cell('DataLinked', '1'),
            if (p.langId != null) _cell('LangID', p.langId!),
            if (p.calendar != null) _cell('Calendar', p.calendar.toString()),
          ],
        ),
    ];
    return XmlElement(
      XmlName('Section'),
      <XmlAttribute>[XmlAttribute(XmlName('N'), 'Property')],
      rows,
    );
  }

  /// Build a fresh `<Section N="User">` for a brand-new shape's user cells.
  XmlElement _buildUserSection(List<VsdxUserCell> cells) {
    var ix = 1;
    final rows = <XmlNode>[
      for (final c in cells)
        XmlElement(
          XmlName('Row'),
          <XmlAttribute>[
            XmlAttribute(XmlName('N'), c.name),
            XmlAttribute(XmlName('IX'), (ix++).toString()),
          ],
          <XmlNode>[
            _cell('Value', c.value ?? '', formula: c.valueFormula),
            if (c.prompt != null) _cell('Prompt', c.prompt!),
          ],
        ),
    ];
    return XmlElement(
      XmlName('Section'),
      <XmlAttribute>[XmlAttribute(XmlName('N'), 'User')],
      rows,
    );
  }

  XmlElement _buildControlSection(List<VsdxControlRow> rows) => XmlElement(
        XmlName('Section'),
        <XmlAttribute>[XmlAttribute(XmlName('N'), 'Control')],
        <XmlNode>[
          for (final r in rows)
            XmlElement(
              XmlName('Row'),
              <XmlAttribute>[XmlAttribute(XmlName('N'), r.name)],
              <XmlNode>[
                _cell('X', _fmt(r.x), formula: r.xFormula),
                _cell('Y', _fmt(r.y), formula: r.yFormula),
                if (r.useVisioDynNames) ...[
                  _cell('XDyn', _fmt(r.dynX), formula: r.dynXFormula),
                  _cell('YDyn', _fmt(r.dynY), formula: r.dynYFormula),
                  _cell('XCon', _fmt(r.conX), formula: r.conXFormula),
                  _cell('YCon', _fmt(r.conY), formula: r.conYFormula),
                ] else ...[
                  _cell('ConX', _fmt(r.conX), formula: r.conXFormula),
                  _cell('ConY', _fmt(r.conY), formula: r.conYFormula),
                  _cell('DynX', _fmt(r.dynX), formula: r.dynXFormula),
                  _cell('DynY', _fmt(r.dynY), formula: r.dynYFormula),
                ],
                _cell('CanGlue', r.canGlue ? '1' : '0'),
                if (r.prompt != null) _cell('Prompt', r.prompt!),
              ],
            ),
        ],
      );

  XmlElement _buildScratchSection(List<VsdxScratchRow> rows) => XmlElement(
        XmlName('Section'),
        <XmlAttribute>[XmlAttribute(XmlName('N'), 'Scratch')],
        <XmlNode>[
          for (final r in rows)
            XmlElement(
              XmlName('Row'),
              <XmlAttribute>[XmlAttribute(XmlName('IX'), r.ix.toString())],
              <XmlNode>[
                _cell('X', _fmt(r.x), formula: r.xFormula),
                _cell('Y', _fmt(r.y), formula: r.yFormula),
                _cell('A', _fmt(r.a), formula: r.aFormula),
                _cell('B', _fmt(r.b), formula: r.bFormula),
                if (r.c != 0 || r.cFormula != null)
                  _cell('C', _fmt(r.c), formula: r.cFormula),
                if (r.d != 0 || r.dFormula != null)
                  _cell('D', _fmt(r.d), formula: r.dFormula),
              ],
            ),
        ],
      );

  XmlElement _buildFieldSection(List<VsdxFieldRow> rows) => XmlElement(
        XmlName('Section'),
        <XmlAttribute>[XmlAttribute(XmlName('N'), 'Field')],
        <XmlNode>[
          for (final r in rows)
            XmlElement(
              XmlName('Row'),
              <XmlAttribute>[XmlAttribute(XmlName('IX'), r.ix.toString())],
              <XmlNode>[
                _fieldCell('Value', r.value ?? '', formula: r.valueFormula),
                _fieldCell('Format', r.format ?? '', formula: r.formatFormula),
                _cell('Type', r.type.toString()),
                if (r.uiCat != null) _cell('UICat', r.uiCat.toString()),
                if (r.uiCod != null) _cell('UICod', r.uiCod.toString()),
                if (r.uiFmt != null) _cell('UIFmt', r.uiFmt.toString()),
                if (r.calendar != null) _cell('Calendar', r.calendar.toString()),
                if (r.objectKind != null)
                  _cell('ObjectKind', r.objectKind.toString()),
              ],
            ),
        ],
      );

  XmlElement _buildActionsSection(List<VsdxActionRow> rows) => XmlElement(
        XmlName('Section'),
        <XmlAttribute>[XmlAttribute(XmlName('N'), 'Actions')],
        <XmlNode>[
          for (final r in rows)
            XmlElement(
              XmlName('Row'),
              <XmlAttribute>[
                XmlAttribute(XmlName('N'), r.name),
                XmlAttribute(XmlName('IX'), r.ix.toString()),
              ],
              <XmlNode>[
                if (r.menu != null) _cell('Menu', r.menu!),
                _cell('Action', r.action ?? '0', formula: r.actionFormula),
                if (r.checked) _cell('Checked', '1'),
                if (r.disabled) _cell('Disabled', '1'),
                if (r.readOnly) _cell('ReadOnly', '1'),
                if (r.invisible) _cell('Invisible', '1'),
                if (r.tag != null) _cell('Tag', r.tag!),
                if (r.buttonFace != 0)
                  _cell('ButtonFace', r.buttonFace.toString()),
                if (r.sortKey != null) _cell('SortKey', r.sortKey!),
              ],
            ),
        ],
      );

  /// Field Value/Format cells commonly carry `U="STR"`.
  XmlElement _fieldCell(String name, String value, {String? formula}) =>
      XmlElement(
        XmlName('Cell'),
        <XmlAttribute>[
          XmlAttribute(XmlName('N'), name),
          XmlAttribute(XmlName('V'), value),
          XmlAttribute(XmlName('U'), 'STR'),
          if (formula != null && formula.isNotEmpty)
            XmlAttribute(XmlName('F'), formula),
        ],
      );

  XmlElement _buildFillGradientSection(VsdxGradient g) {
    var ix = 0;
    final rows = <XmlNode>[
      for (final stop in g.stops)
        XmlElement(
          XmlName('Row'),
          <XmlAttribute>[XmlAttribute(XmlName('IX'), (ix++).toString())],
          <XmlNode>[
            _cell('GradientStopPosition', _fmt(stop.position)),
            ..._gradientStopColorCells(stop),
            if (stop.transparency > _epsilon)
              _cell('GradientStopColorTrans', _fmt(stop.transparency)),
          ],
        ),
    ];
    return XmlElement(
      XmlName('Section'),
      <XmlAttribute>[XmlAttribute(XmlName('N'), 'FillGradient')],
      rows,
    );
  }

  XmlElement _buildLineGradientSection(VsdxGradient g) {
    var ix = 0;
    final rows = <XmlNode>[
      for (final stop in g.stops)
        XmlElement(
          XmlName('Row'),
          <XmlAttribute>[XmlAttribute(XmlName('IX'), (ix++).toString())],
          <XmlNode>[
            _cell('GradientStopPosition', _fmt(stop.position)),
            ..._gradientStopColorCells(stop),
            if (stop.transparency > _epsilon)
              _cell('GradientStopColorTrans', _fmt(stop.transparency)),
          ],
        ),
    ];
    return XmlElement(
      XmlName('Section'),
      <XmlAttribute>[XmlAttribute(XmlName('N'), 'LineGradient')],
      rows,
    );
  }

  /// Hex colour, or bare theme palette index (`V="1"`) when only
  /// [VsdxGradientStop.themeColorIndex] is set.
  List<XmlNode> _gradientStopColorCells(VsdxGradientStop stop) {
    if (stop.color != null) {
      return [_cell('GradientStopColor', _hex(stop.color!))];
    }
    if (stop.themeColorIndex != null) {
      return [_cell('GradientStopColor', stop.themeColorIndex.toString())];
    }
    return const [];
  }

  /// Build a fresh `<Section N="Hyperlink">` for a brand-new shape's links.
  XmlElement _buildHyperlinkSection(List<VsdxHyperlink> links) {
    final rows = <XmlNode>[
      for (final h in links)
        XmlElement(
          XmlName('Row'),
          <XmlAttribute>[XmlAttribute(XmlName('IX'), h.id.toString())],
          <XmlNode>[
            _cell('Address', h.address ?? '', formula: h.addressFormula),
            _cell('SubAddress', h.subAddress ?? ''),
            if (h.description != null) _cell('Description', h.description!),
            if (h.extraInfo != null) _cell('ExtraInfo', h.extraInfo!),
            if (h.frame != null) _cell('Frame', h.frame!),
            _cell('NewWindow', h.newWindow ? '1' : '0'),
            _cell('Default', h.isDefault ? '1' : '0'),
            if (h.invisible) _cell('Invisible', '1'),
            if (h.sortKey != null) _cell('SortKey', h.sortKey!),
          ],
        ),
    ];
    return XmlElement(
      XmlName('Section'),
      <XmlAttribute>[XmlAttribute(XmlName('N'), 'Hyperlink')],
      rows,
    );
  }

  XmlElement? _buildGeometrySection(VsdxGeometry g, int ix) {
    final rows = <XmlNode>[];
    if (g.noFill) rows.add(_cell('NoFill', '1'));
    if (g.noLine) rows.add(_cell('NoLine', '1'));
    // NoShow must survive a geometry rebuild — otherwise a hidden guide
    // geometry (common in stencils) becomes visible after editing the shape.
    if (g.noShow) rows.add(_cell('NoShow', '1'));
    if (g.noSnap) rows.add(_cell('NoSnap', '1'));
    if (g.noQuickDrag) rows.add(_cell('NoQuickDrag', '1'));
    // When the geometry was parsed (row IX known) preserve the source row IX so
    // an instance that inherits/overrides master rows keeps aligning by IX on
    // re-parse; otherwise number rows sequentially (freshly-built shapes).
    final useSourceIx = g.rowIndices.length == g.commands.length &&
        g.rowIndices.isNotEmpty;
    var rowIx = 1;
    var cmdIx = 0;
    for (final cmd in g.commands) {
      final thisIx = useSourceIx ? g.rowIndices[cmdIx] : rowIx;
      final row = _buildRow(cmd, thisIx, formulas: g.formulasAt(cmdIx));
      if (row != null) {
        rows.add(row);
        rowIx++;
      }
      cmdIx++;
    }
    // Re-emit `Del` rows for master rows this instance deleted, so the merge
    // reproduces on the next parse instead of re-inheriting them.
    for (final delIx in g.deletedRowIndices) {
      rows.add(XmlElement(XmlName('Row'), <XmlAttribute>[
        XmlAttribute(XmlName('IX'), delIx.toString()),
        XmlAttribute(XmlName('Del'), '1'),
      ]));
    }
    if (rows.isEmpty) return null;
    return XmlElement(
      XmlName('Section'),
      <XmlAttribute>[
        XmlAttribute(XmlName('N'), 'Geometry'),
        XmlAttribute(XmlName('IX'), (useSourceIx ? g.ix : ix).toString()),
      ],
      rows,
    );
  }

  XmlElement? _buildRow(
    VsdxPathCommand cmd,
    int ix, {
    Map<String, String> formulas = const <String, String>{},
  }) {
    switch (cmd) {
      case MoveTo(:final x, :final y):
        return _row('MoveTo', ix, {'X': x, 'Y': y}, formulas: formulas);
      case LineTo(:final x, :final y):
        return _row('LineTo', ix, {'X': x, 'Y': y}, formulas: formulas);
      case RelMoveTo(:final fx, :final fy):
        return _row('RelMoveTo', ix, {'X': fx, 'Y': fy}, formulas: formulas);
      case RelLineTo(:final fx, :final fy):
        return _row('RelLineTo', ix, {'X': fx, 'Y': fy}, formulas: formulas);
      case CubBezTo(
          :final x,
          :final y,
          :final x1,
          :final y1,
          :final x2,
          :final y2,
        ):
        return _row('CubBezTo', ix, {
          'X': x,
          'Y': y,
          'A': x1,
          'B': y1,
          'C': x2,
          'D': y2,
        }, formulas: formulas);
      case RelCubBezTo(
          :final fx,
          :final fy,
          :final fx1,
          :final fy1,
          :final fx2,
          :final fy2,
        ):
        return _row('RelCubBezTo', ix, {
          'X': fx,
          'Y': fy,
          'A': fx1,
          'B': fy1,
          'C': fx2,
          'D': fy2,
        }, formulas: formulas);
      case QuadBezTo(:final x, :final y, :final x1, :final y1):
        return _row('QuadBezTo', ix, {'X': x, 'Y': y, 'A': x1, 'B': y1},
            formulas: formulas);
      case RelQuadBezTo(:final fx, :final fy, :final fx1, :final fy1):
        return _row('RelQuadBezTo', ix, {
          'X': fx,
          'Y': fy,
          'A': fx1,
          'B': fy1,
        }, formulas: formulas);
      case ArcTo(:final x, :final y, :final bow):
        return _row('ArcTo', ix, {'X': x, 'Y': y, 'A': bow},
            formulas: formulas);
      case RelArcTo(:final fx, :final fy, :final fbow):
        return _row('RelArcTo', ix, {'X': fx, 'Y': fy, 'A': fbow},
            formulas: formulas);
      case EllipseCmd(
          :final cx,
          :final cy,
          :final aX,
          :final aY,
          :final bX,
          :final bY,
        ):
        return _row('Ellipse', ix,
            {'X': cx, 'Y': cy, 'A': aX, 'B': aY, 'C': bX, 'D': bY},
            formulas: formulas);
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
        }, formulas: formulas);
      case RelEllipticalArcTo(
          :final fx,
          :final fy,
          :final fcx,
          :final fcy,
          :final angle,
          :final eccentricity,
        ):
        return _row('RelEllipticalArcTo', ix, {
          'X': fx,
          'Y': fy,
          'A': fcx,
          'B': fcy,
          'C': angle,
          'D': eccentricity,
        }, formulas: formulas);
      case PolylineTo(:final x, :final y, :final vertices, :final relative):
        final buf = StringBuffer(relative ? 'POLYLINE(0,1' : 'POLYLINE(0,0');
        for (final v in vertices) {
          buf.write(',${_fmt(v.x)},${_fmt(v.y)}');
        }
        buf.write(')');
        return _rowFormula(relative ? 'RelPolylineTo' : 'PolylineTo', ix, {
          'X': _fmt(x),
          'Y': _fmt(y),
          'A': buf.toString(),
        }, formulas: formulas);
      case InfiniteLineCmd(:final x, :final y, :final a, :final b, :final relative):
        return _row(relative ? 'RelInfiniteLine' : 'InfiniteLine', ix,
            {'X': x, 'Y': y, 'A': a, 'B': b},
            formulas: formulas);
      case SplineStart(
          :final x,
          :final y,
          :final a,
          :final b,
          :final c,
          :final degree,
          :final relative,
        ):
        return _row(relative ? 'RelSplineStart' : 'SplineStart', ix, {
          'X': x,
          'Y': y,
          'A': a,
          'B': b,
          'C': c,
          'D': degree.toDouble(),
        }, formulas: formulas);
      case SplineKnot(:final x, :final y, :final knot, :final relative):
        return _row(relative ? 'RelSplineKnot' : 'SplineKnot', ix,
            {'X': x, 'Y': y, 'A': knot},
            formulas: formulas);
      case NurbsTo(
          :final x,
          :final y,
          :final controlPoints,
          :final weights,
          :final knots,
          :final degree,
          :final relative,
        ):
        final knotLast = knots.isNotEmpty ? knots.last : 1.0;
        final buf = StringBuffer(
            'NURBS(${_fmt(knotLast)},$degree,${_fmt(x)},${_fmt(y)}');
        for (var i = 0; i < controlPoints.length; i++) {
          final p = controlPoints[i];
          final knot = i < knots.length ? knots[i] : (i + 1).toDouble();
          final weight = i < weights.length ? weights[i] : 1.0;
          buf.write(',${_fmt(p.x)},${_fmt(p.y)},${_fmt(knot)},${_fmt(weight)}');
        }
        buf.write(')');
        return _rowFormula(relative ? 'RelNURBSTo' : 'NURBSTo', ix, {
          'X': _fmt(x),
          'Y': _fmt(y),
          'E': buf.toString(),
        }, formulas: formulas);
    }
  }

  XmlElement _row(
    String type,
    int ix,
    Map<String, double> cells, {
    Map<String, String> formulas = const <String, String>{},
  }) {
    final children = <XmlNode>[
      for (final e in cells.entries)
        _cell(e.key, _fmt(e.value), formula: formulas[e.key]),
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

  /// Geometry row whose cells include a formula string (e.g. `POLYLINE(...)`).
  XmlElement _rowFormula(
    String type,
    int ix,
    Map<String, String> cells, {
    Map<String, String> formulas = const <String, String>{},
  }) {
    final children = <XmlNode>[
      for (final e in cells.entries)
        _cell(e.key, e.value, formula: formulas[e.key]),
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

  /// True when an existing cell carries a parametric `F=` that should survive
  /// a cached-`V` update (SETATREF, PAR(PNT…), Scratch/Controls, TEXTHEIGHT…).
  bool _cellHasParametricFormula(XmlElement shape, String cellName) {
    for (final el in shape.childElements) {
      if (el.name.local == 'Cell' && el.getAttribute('N') == cellName) {
        return _isParametricFormula(el.getAttribute('F'));
      }
    }
    return false;
  }

  static bool _isParametricFormula(String? f) {
    if (f == null || f.isEmpty || f == 'No Formula') return false;
    if (f == 'Inh') return true;
    final u = f.toUpperCase();
    return u.contains('SETATREF') ||
        u.contains('PAR(PNT') ||
        u.contains('CONTROLS.') ||
        u.contains('SCRATCH.') ||
        u.contains('TEXTHEIGHT') ||
        u.contains('TEXTWIDTH') ||
        u.contains('THETEXT') ||
        u.contains('GUARD(') ||
        u.contains('MIN(') ||
        u.contains('MAX(') ||
        u.contains('WIDTH') ||
        u.contains('HEIGHT') ||
        u.contains('BEGINX') ||
        u.contains('BEGINY') ||
        u.contains('ENDX') ||
        u.contains('ENDY');
  }

  XmlElement _cell(String name, String value, {String? formula, String? unit}) =>
      XmlElement(
        XmlName('Cell'),
        <XmlAttribute>[
          XmlAttribute(XmlName('N'), name),
          XmlAttribute(XmlName('V'), value),
          if (unit != null && unit.isNotEmpty)
            XmlAttribute(XmlName('U'), unit),
          if (formula != null && formula.isNotEmpty)
            XmlAttribute(XmlName('F'), formula),
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
