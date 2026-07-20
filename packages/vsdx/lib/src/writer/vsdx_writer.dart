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

import '../export/theme_serializer.dart';
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
import '../model/theme.dart';
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
    // Back-fill minimal StyleSheets / FaceNames on legacy blank exports so
    // Edraw can resolve Default*Style (otherwise fills/text look wrong).
    final docXml = pkg.readPartXml(docPart);
    if (docXml != null && _ensureDocumentStyles(docXml)) {
      patched[_noSlash(docPart)] =
          Uint8List.fromList(utf8.encode(docXml.toXmlString()));
    }
    final pagesPart = resolver.singleTargetOfType(docPart, VsdxRelType.pages);
    final pagesXml = pagesPart == null ? null : pkg.readPartXml(pagesPart);
    if (pagesPart == null || pagesXml == null) {
      _healMissingCore(pkg, patched, edited);
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
        rebuiltImageShapes: _imageShapesNeedingRels(bp, ep),
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
      if (_ensurePageViewCenter(el, ep)) pagesDirty = true;
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

    // 3) Persist the document theme palette (draw.io theme gallery). When the
    // edited theme differs from the baseline we patch or create theme1.xml and
    // wire document.xml.rels + Content_Types.
    _prepareThemePart(
      pkg: pkg,
      resolver: resolver,
      docPart: docPart,
      baseline: baseline.theme,
      edited: edited.theme,
      patched: patched,
      ctXml: ctXml,
      markCtDirty: () => ctDirty = true,
    );

    // Heal broken OPC that references docProps/core.xml but omits the part
    // (common in third-party fixtures). Edraw / Visio expect the part present.
    _healMissingCore(
      pkg,
      patched,
      edited,
      ctXml: ctXml,
      markCtDirty: () => ctDirty = true,
    );

    // Drop media parts no longer referenced by any page/master shape so
    // replaceImage / delete-picture do not leave orphaned zip entries.
    _pruneUnreferencedMedia(
      pkg: pkg,
      edited: edited,
      removed: removed,
      patched: patched,
    );

    if (ctDirty && ctXml != null) {
      patched['[Content_Types].xml'] =
          Uint8List.fromList(utf8.encode(ctXml.toXmlString()));
    }

    return _rezip(originalBytes, patched, removed);
  }

  /// Mark unreferenced `visio/media/*` parts for removal. Returns whether any
  /// were queued. Masters are scanned so shared stencil media is kept.
  bool _pruneUnreferencedMedia({
    required VsdxPackage pkg,
    required VsdxDocument edited,
    required Set<String> removed,
    required Map<String, Uint8List> patched,
  }) {
    final referenced = <String>{};
    void consider(String? part) {
      if (part == null || part.isEmpty) return;
      referenced.add(_noSlash(part));
    }

    void walk(VsdxShape s) {
      consider(s.imagePartName);
      for (final c in s.children) {
        walk(c);
      }
    }

    for (final page in edited.pages) {
      for (final s in page.shapes) {
        walk(s);
      }
    }
    for (final m in edited.masters.all) {
      walk(m.prototype);
    }

    var any = false;
    final pruned = <String>{};
    final candidates = <String>{
      for (final name in pkg.allPartNames)
        if (_noSlash(name).startsWith('visio/media/')) _noSlash(name),
      for (final name in patched.keys)
        if (name.startsWith('visio/media/')) name,
    };
    for (final media in candidates) {
      if (referenced.contains(media)) continue;
      if (removed.add(media)) any = true;
      patched.remove(media);
      pruned.add(media);
    }
    if (pruned.isNotEmpty) {
      _pruneDanglingImageRelationships(
        pkg: pkg,
        patched: patched,
        prunedMedia: pruned,
      );
    }
    return any;
  }

  /// Drop image Relationships whose Target points at a media part just pruned,
  /// so page/master `.rels` do not keep dangling `../media/…` entries.
  void _pruneDanglingImageRelationships({
    required VsdxPackage pkg,
    required Map<String, Uint8List> patched,
    required Set<String> prunedMedia,
  }) {
    final relParts = <String>{
      for (final name in pkg.allPartNames)
        if (_noSlash(name).endsWith('.rels')) _noSlash(name),
      for (final name in patched.keys)
        if (name.endsWith('.rels')) name,
    };
    for (final relsNoSlash in relParts) {
      XmlDocument? relsXml;
      if (patched.containsKey(relsNoSlash)) {
        relsXml = XmlDocument.parse(utf8.decode(patched[relsNoSlash]!));
      } else {
        relsXml = pkg.readPartXml('/$relsNoSlash');
      }
      if (relsXml == null) continue;

      // Owner part for relative Target resolution: …/_rels/foo.xml.rels → …/foo.xml
      final ownerPart = _ownerPartForRels(relsNoSlash);
      var dirty = false;
      final doomed = <XmlElement>[];
      for (final rel in relsXml.rootElement.childElements) {
        if (rel.name.local != 'Relationship') continue;
        if (rel.getAttribute('Type') != _imageRelType) continue;
        final target = rel.getAttribute('Target');
        if (target == null) continue;
        final abs = _noSlash(_absoluteMediaPart('/$ownerPart', target));
        if (!prunedMedia.contains(abs)) continue;
        doomed.add(rel);
      }
      for (final el in doomed) {
        el.parent?.children.remove(el);
        dirty = true;
      }
      if (dirty) {
        patched[relsNoSlash] =
            Uint8List.fromList(utf8.encode(relsXml.toXmlString()));
      }
    }
  }

  /// Map `visio/pages/_rels/page1.xml.rels` → `visio/pages/page1.xml`.
  static String _ownerPartForRels(String relsNoSlash) {
    final marker = '/_rels/';
    final idx = relsNoSlash.indexOf(marker);
    if (idx < 0) {
      // Package root `_rels/.rels` — absolute targets only.
      return '';
    }
    final dir = relsNoSlash.substring(0, idx);
    var base = relsNoSlash.substring(idx + marker.length);
    if (base.endsWith('.rels')) {
      base = base.substring(0, base.length - '.rels'.length);
    }
    return dir.isEmpty ? base : '$dir/$base';
  }

  /// Inject a minimal `docProps/core.xml` when the package omits it so Save
  /// always produces a structurally complete OPC (Edraw / Visio expect it).
  void _healMissingCore(
    VsdxPackage pkg,
    Map<String, Uint8List> patched,
    VsdxDocument edited, {
    XmlDocument? ctXml,
    void Function()? markCtDirty,
  }) {
    const coreName = 'docProps/core.xml';
    if (pkg.readPartBytes('/$coreName') != null ||
        patched.containsKey(coreName)) {
      return;
    }

    const decl = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
    final creatorXml =
        _xmlEscape(edited.creator ?? 'Editor for Visio Diagrams');
    final titleXml = (edited.title != null && edited.title!.isNotEmpty)
        ? '<dc:title>${_xmlEscape(edited.title!)}</dc:title>'
        : '';
    patched[coreName] = Uint8List.fromList(utf8.encode(
      '$decl\n'
      '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '$titleXml'
      '<dc:creator>$creatorXml</dc:creator></cp:coreProperties>',
    ));

    final types = ctXml ?? pkg.readPartXml('/[Content_Types].xml');
    if (types != null) {
      final hasOverride = types.rootElement.childElements.any((el) {
        if (el.name.local != 'Override') return false;
        final pn = el.getAttribute('PartName') ?? '';
        return pn == '/docProps/core.xml' || pn == 'docProps/core.xml';
      });
      if (!hasOverride) {
        types.rootElement.children.add(XmlElement(
          XmlName('Override'),
          <XmlAttribute>[
            XmlAttribute(XmlName('PartName'), '/docProps/core.xml'),
            XmlAttribute(
              XmlName('ContentType'),
              'application/vnd.openxmlformats-package.core-properties+xml',
            ),
          ],
        ));
        patched['[Content_Types].xml'] =
            Uint8List.fromList(utf8.encode(types.toXmlString()));
        markCtDirty?.call();
      }
    }

    final rels = pkg.readPartXml('/_rels/.rels');
    if (rels == null) return;
    final hasCoreRel = rels.rootElement.childElements.any((el) {
      if (el.name.local != 'Relationship') return false;
      final t = el.getAttribute('Type') ?? '';
      final target = el.getAttribute('Target') ?? '';
      return t.contains('core-properties') ||
          target == 'docProps/core.xml' ||
          target.endsWith('/docProps/core.xml');
    });
    if (hasCoreRel) return;
    var maxId = 0;
    for (final el in rels.rootElement.childElements) {
      if (el.name.local != 'Relationship') continue;
      final id = el.getAttribute('Id') ?? '';
      final m = RegExp(r'rId(\d+)$').firstMatch(id);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > maxId) maxId = n;
      }
    }
    rels.rootElement.children.add(XmlElement(
      XmlName('Relationship'),
      <XmlAttribute>[
        XmlAttribute(XmlName('Id'), 'rId${maxId + 1}'),
        XmlAttribute(
          XmlName('Type'),
          'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties',
        ),
        XmlAttribute(XmlName('Target'), 'docProps/core.xml'),
      ],
    ));
    patched['_rels/.rels'] =
        Uint8List.fromList(utf8.encode(rels.toXmlString()));
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
    // Drop Layer rows that no longer exist in the edited model (delete layer).
    final keep = <int>{for (final l in ep.layers) l.id};
    for (final entry in rows.entries.toList()) {
      if (keep.contains(entry.key)) continue;
      section.children.remove(entry.value);
      changed = true;
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
    final needBackgroundFlag = bp.isBackgroundPage != ep.isBackgroundPage;
    final needBackPage = bp.backgroundPageId != ep.backgroundPageId;
    if (!needWidth &&
        !needHeight &&
        !needColor &&
        !needSheet &&
        !needView &&
        !needBackgroundFlag &&
        !needBackPage) {
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
    if (needColor) {
      if (ep.backgroundColor != null) {
        _writeValue(_ensurePageSheetCell(sheet, 'PageColor'),
            _hex(ep.backgroundColor!));
        changed = true;
      } else {
        // Cleared PageColor — remove the cell so reopen inherits default white
        // (same model as null [VsdxPage.backgroundColor]).
        for (final el in sheet.childElements.toList()) {
          if (el.name.local == 'Cell' && el.getAttribute('N') == 'PageColor') {
            el.parent?.children.remove(el);
            changed = true;
          }
        }
      }
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
    // Visio pages.xml: Background="1" marks a background page; BackPage="N"
    // references that page's ID from a foreground page (drawio "Background").
    if (needBackgroundFlag) {
      if (ep.isBackgroundPage) {
        pageEl.setAttribute('Background', '1');
      } else {
        pageEl.removeAttribute('Background');
      }
      changed = true;
    }
    if (needBackPage) {
      final id = ep.backgroundPageId;
      if (id == null) {
        pageEl.removeAttribute('BackPage');
      } else {
        pageEl.setAttribute('BackPage', id.toString());
      }
      changed = true;
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

  /// Ensure `<Page ViewCenter*>` so 万兴图示 opens focused on content.
  bool _ensurePageViewCenter(XmlElement pageEl, VsdxPage page) {
    final center = _pageViewCenter(page);
    var changed = false;
    if (pageEl.getAttribute('ViewScale') == null) {
      pageEl.setAttribute('ViewScale', _fmt(page.viewScale ?? 1.0));
      changed = true;
    }
    if (pageEl.getAttribute('ViewCenterX') == null) {
      pageEl.setAttribute(
          'ViewCenterX', _fmt(page.viewCenterX ?? center.$1));
      changed = true;
    }
    if (pageEl.getAttribute('ViewCenterY') == null) {
      pageEl.setAttribute(
          'ViewCenterY', _fmt(page.viewCenterY ?? center.$2));
      changed = true;
    }
    return changed;
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
    if (edited.lineJumpDirX != null) {
      raw('PageLineJumpDirX', (base.lineJumpDirX ?? -1).toString(),
          edited.lineJumpDirX.toString());
    }
    if (edited.lineJumpDirY != null) {
      raw('PageLineJumpDirY', (base.lineJumpDirY ?? -1).toString(),
          edited.lineJumpDirY.toString());
    }
    if (edited.lineToLineXInches != null) {
      len('LineToLineX', base.lineToLineXInches ?? 0, edited.lineToLineXInches!);
    }
    if (edited.lineToLineYInches != null) {
      len('LineToLineY', base.lineToLineYInches ?? 0, edited.lineToLineYInches!);
    }
    if (edited.lineJumpFactorX != null) {
      raw('LineJumpFactorX', _fmt(base.lineJumpFactorX ?? -1),
          _fmt(edited.lineJumpFactorX!));
    }
    if (edited.lineJumpFactorY != null) {
      raw('LineJumpFactorY', _fmt(base.lineJumpFactorY ?? -1),
          _fmt(edited.lineJumpFactorY!));
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
    // 万兴图示 opens at ViewCenter; without it the viewport often lands on an
    // empty corner of Letter pages so filled shapes look "missing".
    final center = _pageViewCenter(ep);
    final viewScale = ep.viewScale ?? 1.0;
    final viewCenterX = ep.viewCenterX ?? center.$1;
    final viewCenterY = ep.viewCenterY ?? center.$2;
    final attrs = <XmlAttribute>[
      XmlAttribute(XmlName('ID'), ep.id.toString()),
      XmlAttribute(XmlName('NameU'), ep.name),
      XmlAttribute(XmlName('Name'), ep.name),
      XmlAttribute(XmlName('ViewScale'), _fmt(viewScale)),
      XmlAttribute(XmlName('ViewCenterX'), _fmt(viewCenterX)),
      XmlAttribute(XmlName('ViewCenterY'), _fmt(viewCenterY)),
    ];
    if (ep.isBackgroundPage) {
      attrs.add(XmlAttribute(XmlName('Background'), '1'));
    }
    if (ep.backgroundPageId != null) {
      attrs.add(
          XmlAttribute(XmlName('BackPage'), ep.backgroundPageId.toString()));
    }
    return XmlElement(
      XmlName('Page'),
      attrs,
      <XmlNode>[pageSheet, rel],
    );
  }

  /// Content centroid in inches, or the page centre when the page is empty.
  (double, double) _pageViewCenter(VsdxPage page) {
    final w = page.widthInches <= 0 ? 8.5 : page.widthInches;
    final h = page.heightInches <= 0 ? 11.0 : page.heightInches;
    if (page.shapes.isEmpty) return (w / 2, h / 2);
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final s in page.shapes) {
      final hw = (s.width.abs()) / 2;
      final hh = (s.height.abs()) / 2;
      final left = s.pinX - hw;
      final right = s.pinX + hw;
      final bottom = s.pinY - hh;
      final top = s.pinY + hh;
      if (left < minX) minX = left;
      if (right > maxX) maxX = right;
      if (bottom < minY) minY = bottom;
      if (top > maxY) maxY = top;
    }
    if (!minX.isFinite) return (w / 2, h / 2);
    return ((minX + maxX) / 2, (minY + maxY) / 2);
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
        if (s.lineJumpDirX != null)
          _cell('PageLineJumpDirX', s.lineJumpDirX.toString()),
        if (s.lineJumpDirY != null)
          _cell('PageLineJumpDirY', s.lineJumpDirY.toString()),
        if (s.lineToLineXInches != null)
          _cell('LineToLineX', _fmt(s.lineToLineXInches!)),
        if (s.lineToLineYInches != null)
          _cell('LineToLineY', _fmt(s.lineToLineYInches!)),
        if (s.lineJumpFactorX != null)
          _cell('LineJumpFactorX', _fmt(s.lineJumpFactorX!)),
        if (s.lineJumpFactorY != null)
          _cell('LineJumpFactorY', _fmt(s.lineJumpFactorY!)),
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

  /// Picture shapes the writer will emit fresh `<ForeignData>` for: newly
  /// inserted ids, reparented pictures, or pictures whose media part changed
  /// ([replaceImage]).
  List<VsdxShape> _imageShapesNeedingRels(VsdxPage baseline, VsdxPage edited) {
    final baseParent = <int, int?>{};
    final baseImagePart = <int, String?>{};
    void mapBase(VsdxShape s, int? parent) {
      baseParent[s.id] = parent;
      baseImagePart[s.id] = s.imagePartName;
      for (final c in s.children) {
        mapBase(c, s.id);
      }
    }

    for (final s in baseline.shapes) {
      mapBase(s, null);
    }

    final out = <VsdxShape>[];
    void walk(VsdxShape s, int? parent) {
      if (s.hasImage) {
        final isNew = !baseParent.containsKey(s.id);
        final reparented = !isNew && baseParent[s.id] != parent;
        final partChanged =
            !isNew && baseImagePart[s.id] != s.imagePartName;
        if (isNew || reparented || partChanged) out.add(s);
      }
      for (final c in s.children) {
        walk(c, s.id);
      }
    }

    for (final s in edited.shapes) {
      walk(s, null);
    }
    return out;
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

    // Reuse existing image relationships so rebuild/replaceImage don't mint
    // duplicate rIds for media already linked from this page.
    final relByPart = <String, String>{};
    for (final rel in relsXml.rootElement.childElements) {
      if (rel.name.local != 'Relationship') continue;
      if (rel.getAttribute('Type') != _imageRelType) continue;
      final id = rel.getAttribute('Id');
      final target = rel.getAttribute('Target');
      if (id == null || target == null) continue;
      final abs = _absoluteMediaPart(pagePart, target);
      relByPart[abs] = id;
      // Also index without a leading slash — packages mix both forms.
      if (abs.startsWith('/')) {
        relByPart[abs.substring(1)] = id;
      } else {
        relByPart['/$abs'] = id;
      }
    }

    var nextRId = _maxRelId(relsXml) + 1;
    var relsDirty = false;
    for (final s in rebuiltImageShapes) {
      final part = s.imagePartName;
      if (part == null) continue;
      if (!relByPart.containsKey(part)) {
        final rId = 'rId$nextRId';
        nextRId++;
        relByPart[part] = rId;
        if (part.startsWith('/')) {
          relByPart[part.substring(1)] = rId;
        } else {
          relByPart['/$part'] = rId;
        }
        relsXml.rootElement.children.add(XmlElement(XmlName('Relationship'), [
          XmlAttribute(XmlName('Id'), rId),
          XmlAttribute(XmlName('Type'), _imageRelType),
          XmlAttribute(XmlName('Target'), _mediaTargetFrom(pagePart, part)),
        ]));
        relsDirty = true;
      }

      // Embed the bytes when this media part is not already in the package.
      final mediaNoSlash = _noSlash(part);
      if (!patched.containsKey(mediaNoSlash) &&
          pkg.readPartBytes(part) == null &&
          pkg.readPartBytes('/$mediaNoSlash') == null) {
        final img = edited.images.findByPart(part) ??
            edited.images.findByPart('/$mediaNoSlash') ??
            edited.images.findByPart(mediaNoSlash);
        if (img != null) {
          patched[mediaNoSlash] = Uint8List.fromList(img.bytes);
          if (ctXml != null &&
              _ensureMediaContentType(ctXml, part, img.mimeType)) {
            markCtDirty();
          }
        }
      }
    }

    if (relsDirty || !patched.containsKey(relsNoSlash)) {
      patched[relsNoSlash] =
          Uint8List.fromList(utf8.encode(relsXml.toXmlString()));
    }
    return relByPart;
  }

  /// Resolve a page-relative media target (`../media/image1.png`) to an
  /// absolute part name (`/visio/media/image1.png`).
  static String _absoluteMediaPart(String pagePart, String target) {
    final t = target.trim();
    if (t.startsWith('/')) return t;
    if (t.startsWith('../media/')) {
      return '/visio/media/${t.substring('../media/'.length)}';
    }
    if (t.startsWith('media/')) return '/visio/$t';
    if (t.startsWith('visio/media/')) return '/$t';
    // Fall back: treat as a file under visio/media.
    final name = t.contains('/') ? t.substring(t.lastIndexOf('/') + 1) : t;
    return '/visio/media/$name';
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

  /// Relationship type for the DrawingML theme part (OOXML / Visio).
  static const String _themeRelType =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme';
  static const String _themeContentType =
      'application/vnd.openxmlformats-officedocument.theme+xml';
  static const String _defaultThemePart = 'visio/theme/theme1.xml';

  /// Persist [edited] theme colours into the package when they differ from
  /// [baseline]. Patches an existing theme part's `<a:clrScheme>` (keeping
  /// fonts/effects) or creates `theme1.xml` + document rel + Content_Types
  /// override. Empty [edited] is a no-op so we never wipe a baseline theme.
  void _prepareThemePart({
    required VsdxPackage pkg,
    required RelationshipResolver resolver,
    required String docPart,
    required VsdxTheme baseline,
    required VsdxTheme edited,
    required Map<String, Uint8List> patched,
    required XmlDocument? ctXml,
    required void Function() markCtDirty,
  }) {
    if (edited.isEmpty) return;
    if (ThemeSerializer.themesEqual(baseline, edited)) return;

    final name = ThemeSerializer.nameFor(edited);
    final existingPart =
        resolver.singleTargetOfType(docPart, VsdxRelType.theme);

    if (existingPart != null) {
      final xml = pkg.readPartXml(existingPart);
      if (xml != null) {
        ThemeSerializer.patchClrScheme(xml, edited, name: name);
        patched[_noSlash(existingPart)] =
            Uint8List.fromList(utf8.encode(xml.toXmlString()));
        return;
      }
    }

    // No usable theme part — emit a minimal DrawingML theme and wire it up.
    patched[_defaultThemePart] = Uint8List.fromList(
      utf8.encode(ThemeSerializer.emit(edited, name: name)),
    );

    if (ctXml != null &&
        _ensureThemeOverride(ctXml, '/$_defaultThemePart')) {
      markCtDirty();
    }

    final relsPart = _relsPartFor(docPart);
    final relsNoSlash = _noSlash(relsPart);
    final XmlDocument relsXml;
    if (patched.containsKey(relsNoSlash)) {
      relsXml = XmlDocument.parse(utf8.decode(patched[relsNoSlash]!));
    } else {
      relsXml = pkg.readPartXml(relsPart) ??
          XmlDocument.parse(
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
            '<Relationships xmlns="$_relNs"/>',
          );
    }

    final hasThemeRel = relsXml.rootElement.childElements.any((el) {
      if (el.name.local != 'Relationship') return false;
      return (el.getAttribute('Type') ?? '').endsWith('/theme');
    });
    if (!hasThemeRel) {
      final rId = 'rId${_maxRelId(relsXml) + 1}';
      relsXml.rootElement.children.add(XmlElement(XmlName('Relationship'), [
        XmlAttribute(XmlName('Id'), rId),
        XmlAttribute(XmlName('Type'), _themeRelType),
        XmlAttribute(XmlName('Target'), 'theme/theme1.xml'),
      ]));
    }
    patched[relsNoSlash] =
        Uint8List.fromList(utf8.encode(relsXml.toXmlString()));
  }

  /// Ensure `[Content_Types].xml` has an Override for the theme part.
  bool _ensureThemeOverride(XmlDocument ctXml, String partName) {
    for (final el in ctXml.rootElement.childElements) {
      if (el.name.local == 'Override' &&
          el.getAttribute('PartName') == partName) {
        return false;
      }
    }
    ctXml.rootElement.children.add(XmlElement(XmlName('Override'), [
      XmlAttribute(XmlName('PartName'), partName),
      XmlAttribute(XmlName('ContentType'), _themeContentType),
    ]));
    return true;
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

  /// Minimal `<StyleSheets>` + `<FaceNames>` fragment used by [emptyDocument]
  /// and by [_ensureDocumentStyles] when patching legacy blanks.
  /// Default CJK face Edraw / Visio ship with — required so Chinese labels
  /// don't render as tofu (□□) in 万兴图示.
  static const String _defaultAsianFont = 'Microsoft YaHei';

  static const String _minimalStylesXml =
      '<FaceNames>'
      '<FaceName NameU="Arial" UnicodeRanges="-459292017 -1073730379 9 0" CharSets="1610612799 0" Panose="2 11 6 4 2 2 2 2 2 4" Flags="325"/>'
      '<FaceName NameU="Calibri" UnicodeRanges="-469750017 -1073732485 9 0" CharSets="536871423 0" Panose="2 15 5 2 2 2 4 3 2 4" Flags="325"/>'
      '<FaceName NameU="Microsoft YaHei" UnicodeRanges="-2147483648 0 0 0" CharSets="262145 0" Panose="2 11 5 3 2 2 2 2 2 4" Flags="325"/>'
      '<FaceName NameU="PingFang SC" UnicodeRanges="-2147483648 0 0 0" CharSets="262145 0" Panose="2 11 5 3 2 2 2 2 2 4" Flags="325"/>'
      '<FaceName NameU="Songti SC" UnicodeRanges="-2147483648 0 0 0" CharSets="262145 0" Panose="2 1 6 0 4 1 1 1 1 1" Flags="325"/>'
      '</FaceNames>'
      '<StyleSheets>'
      '<StyleSheet ID="0" NameU="No Style" Name="No Style">'
      '<Cell N="EnableLineProps" V="1"/>'
      '<Cell N="EnableFillProps" V="1"/>'
      '<Cell N="EnableTextProps" V="1"/>'
      '<Cell N="LineWeight" V="0.01"/>'
      '<Cell N="LineColor" V="#000000"/>'
      '<Cell N="LinePattern" V="1"/>'
      '<Cell N="LineCap" V="0"/>'
      '<Cell N="BeginArrow" V="0"/>'
      '<Cell N="EndArrow" V="0"/>'
      '<Cell N="BeginArrowSize" V="2"/>'
      '<Cell N="EndArrowSize" V="2"/>'
      '<Cell N="FillForegnd" V="#FFFFFF"/>'
      '<Cell N="FillBkgnd" V="#FFFFFF"/>'
      '<Cell N="FillPattern" V="1"/>'
      '<Cell N="ShdwPattern" V="0"/>'
      '<Cell N="ShapeShdwShow" V="0"/>'
      '<Cell N="VerticalAlign" V="1"/>'
      '<Cell N="LeftMargin" V="0.05555555555555555"/>'
      '<Cell N="RightMargin" V="0.05555555555555555"/>'
      '<Cell N="TopMargin" V="0.05555555555555555"/>'
      '<Cell N="BottomMargin" V="0.05555555555555555"/>'
      '<Section N="Character">'
      '<Row IX="0">'
      '<Cell N="Font" V="Arial"/>'
      '<Cell N="Color" V="#000000"/>'
      '<Cell N="Style" V="0"/>'
      '<Cell N="Size" V="0.1666666666666667"/>'
      '<Cell N="AsianFont" V="Microsoft YaHei"/>'
      '<Cell N="LangID" V="zh-CN"/>'
      '</Row>'
      '</Section>'
      '<Section N="Paragraph">'
      '<Row IX="0">'
      '<Cell N="HorzAlign" V="1"/>'
      '<Cell N="SpLine" V="-1.2"/>'
      '</Row>'
      '</Section>'
      '</StyleSheet>'
      '</StyleSheets>';

  /// Inject FaceNames + StyleSheets into [document.xml] when missing.
  bool _ensureDocumentStyles(XmlDocument docXml) {
    final root = docXml.rootElement;
    if (root.name.local != 'VisioDocument') return false;
    var hasSheets = false;
    var hasFaces = false;
    for (final c in root.childElements) {
      if (c.name.local == 'StyleSheets') hasSheets = true;
      if (c.name.local == 'FaceNames') hasFaces = true;
    }
    if (hasSheets && hasFaces) return false;
    final wrap = XmlDocument.parse('<Wrap>$_minimalStylesXml</Wrap>').rootElement;
    if (!hasFaces) {
      for (final n in wrap.childElements) {
        if (n.name.local == 'FaceNames') {
          root.children.add(n.copy());
          break;
        }
      }
    }
    if (!hasSheets) {
      for (final n in wrap.childElements) {
        if (n.name.local == 'StyleSheets') {
          root.children.add(n.copy());
          break;
        }
      }
    }
    return true;
  }

  /// Generate a minimal, valid blank `.vsdx` (one empty page). Used as the
  /// base for "New drawing": the editor parses it, then normal
  /// load-preserve-patch saves append the user's shapes into `page1.xml`.
  Uint8List emptyDocument({
    double widthInches = 8.5,
    double heightInches = 11.0,
    String? title,
    String? creator,
  }) {
    const decl = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
    final creatorXml = VsdxWriter._xmlEscape(creator ?? 'Editor for Visio Diagrams');
    final titleXml = (title != null && title.isNotEmpty)
        ? '<dc:title>${VsdxWriter._xmlEscape(title)}</dc:title>'
        : '';
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
          '$titleXml'
          '<dc:creator>$creatorXml</dc:creator></cp:coreProperties>',
      'docProps/app.xml': '$decl\n'
          '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
          '<Application>Editor for Visio Diagrams</Application></Properties>',
      // Minimal StyleSheets + FaceNames so Edraw / Visio resolve Default*Style
      // (previously pointed at missing sheet 0 → hollow fills, wrong text size).
      'visio/document.xml': '$decl\n'
          '<VisioDocument xmlns="$_mainNs" xmlns:r="$_officeRelNs">'
          '<DocumentSettings TopPage="0" DefaultTextStyle="0" DefaultLineStyle="0" DefaultFillStyle="0" DefaultGuideStyle="0">'
          '<GlueSettings>9</GlueSettings>'
          '<SnapSettings>65847</SnapSettings>'
          '<DynamicGridEnabled>1</DynamicGridEnabled>'
          '</DocumentSettings>'
          '$_minimalStylesXml'
          '</VisioDocument>',
      'visio/_rels/document.xml.rels': '$decl\n'
          '<Relationships xmlns="$_relNs">'
          '<Relationship Id="rId1" Type="http://schemas.microsoft.com/visio/2010/relationships/pages" Target="pages/pages.xml"/>'
          '</Relationships>',
      'visio/pages/pages.xml': '$decl\n'
          '<Pages xmlns="$_mainNs" xmlns:r="$_officeRelNs">'
          '<Page ID="0" NameU="Page-1" Name="Page-1" '
          'ViewScale="1" ViewCenterX="${_fmt(widthInches / 2)}" ViewCenterY="${_fmt(heightInches / 2)}">'
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

    // A shape must be rebuilt (fresh element) when it is new, has changed
    // parent (grouped / ungrouped), or its embedded media part changed
    // (replaceImage). Others are patched in place.
    bool needsRebuild(int id) {
      if (!origParent.containsKey(id) || origParent[id] != editedParent[id]) {
        return true;
      }
      final base = baseline.findShapeById(id);
      final ed = edited.findShapeById(id);
      if (base != null &&
          ed != null &&
          (base.imagePartName != ed.imagePartName ||
              base.hasImage != ed.hasImage)) {
        return true;
      }
      return false;
    }

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

    // 4) Reorder <Shape> elements to match the model's z-order at every nesting
    //    level (top-level page shapes and children inside groups/containers).
    final topShapes = shapesEl;
    if (topShapes != null && _reorderShapesTree(topShapes, edited.shapes)) {
      changed = true;
    }

    // 5) Reconcile <Connects> (glue) when it changed vs the baseline.
    if (!_connectsEqual(baseline.connects, edited.connects)) {
      _writeConnects(root, edited.connects);
      changed = true;
    }

    return changed;
  }

  /// Reorder `<Shape>` children of [shapesEl] to match [order], then recurse
  /// into each group's nested `<Shapes>` so in-group z-order survives save.
  bool _reorderShapesTree(XmlElement shapesEl, List<VsdxShape> order) {
    var changed = _reorderShapes(shapesEl, order);
    final byId = <int, XmlElement>{};
    for (final el in shapesEl.childElements) {
      if (el.name.local != 'Shape') continue;
      final id = int.tryParse(el.getAttribute('ID') ?? '');
      if (id != null) byId[id] = el;
    }
    for (final s in order) {
      if (s.children.isEmpty) continue;
      final el = byId[s.id];
      if (el == null) continue;
      final nested = _firstChild(el, 'Shapes');
      if (nested == null) continue;
      changed |= _reorderShapesTree(nested, s.children);
    }
    return changed;
  }

  /// Reorder the direct `<Shape>` children of [shapesEl] to match [order].
  /// Returns whether the order actually changed.
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
    // Persist drawio-style route flags into User cells before diffing so a
    // curved / waypointed connector keeps its edit state across reopen.
    base = base.persistRouteState();
    edited = edited.persistRouteState();
    var changed = false;
    changed |= _patchLength(el, 'PinX', base.pinX, edited.pinX);
    changed |= _patchLength(el, 'PinY', base.pinY, edited.pinY);
    // For connectors (ObjType=2), Width/Height are End−Begin (may be signed).
    // Preserve / restore those formulas after the numeric V= patch so 万兴图示
    // keeps the Visio 1-D convention instead of treating size as an AABB.
    final connectorXForm = edited.is1D &&
        (edited.objType == null || edited.objType == 2);
    changed |= _patchLength(
      el,
      'Width',
      base.width,
      edited.width,
      preserveFormula: connectorXForm &&
          (edited.formulas['Width'] != null ||
              _cellHasParametricFormula(el, 'Width')),
    );
    changed |= _patchLength(
      el,
      'Height',
      base.height,
      edited.height,
      preserveFormula: connectorXForm &&
          (edited.formulas['Height'] != null ||
              _cellHasParametricFormula(el, 'Height')),
    );
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
    // Older exports omitted LocPin; Edraw then pins at (0,0). Back-fill on save.
    changed |= _ensureLocPinPresent(el, edited);
    // Picture shapes need Img* cells; keep cached V= in sync with Width/Height
    // so hosts that ignore F= (notably Edraw) still show the resized bitmap.
    if (edited.hasImage) {
      changed |= _syncImageSizeCells(el, edited);
    }
    changed |= _ensureLineFillBasics(el, edited);
    changed |= _patchAngle(el, 'Angle', base.angleRad, edited.angleRad);
    // Honour the *edited* model for Begin/End F= — baseline XML PAR(PNT…)
    // must not survive after glue detach / reconnect cleared those formulas.
    changed |= _patchNullableLength(el, 'BeginX', base.beginX, edited.beginX,
        preserveFormula: _isParametricFormula(edited.formulas['BeginX']));
    changed |= _patchNullableLength(el, 'BeginY', base.beginY, edited.beginY,
        preserveFormula: _isParametricFormula(edited.formulas['BeginY']));
    changed |= _patchNullableLength(el, 'EndX', base.endX, edited.endX,
        preserveFormula: _isParametricFormula(edited.formulas['EndX']));
    changed |= _patchNullableLength(el, 'EndY', base.endY, edited.endY,
        preserveFormula: _isParametricFormula(edited.formulas['EndY']));
    // Values may be unchanged after detach; still strip stale F= from XML.
    changed |= _syncCellFormulaAttr(el, 'BeginX', edited.formulas['BeginX']);
    changed |= _syncCellFormulaAttr(el, 'BeginY', edited.formulas['BeginY']);
    changed |= _syncCellFormulaAttr(el, 'EndX', edited.formulas['EndX']);
    changed |= _syncCellFormulaAttr(el, 'EndY', edited.formulas['EndY']);
    changed |= _patchBool(el, 'FlipX', base.flipX, edited.flipX);
    changed |= _patchBool(el, 'FlipY', base.flipY, edited.flipY);
    // Group behaviour (libvisio IsTextEditTarget / DontMoveChildren / …).
    changed |= _patchBool(
        el, 'IsTextEditTarget', base.isTextEditTarget, edited.isTextEditTarget);
    changed |= _patchBool(
        el, 'DontMoveChildren', base.dontMoveChildren, edited.dontMoveChildren);
    changed |= _patchOptionalIntCell(
        el, 'SelectMode', base.selectMode, edited.selectMode);
    changed |= _patchOptionalIntCell(
        el, 'DisplayMode', base.displayMode, edited.displayMode);
    if (edited.selectMode != null) {
      changed |= _forceLiteralInt(el, 'SelectMode', edited.selectMode!);
    }
    if (edited.displayMode != null) {
      changed |= _forceLiteralInt(el, 'DisplayMode', edited.displayMode!);
    }
    // Protection (drawio "Lock/Unlock").
    changed |= _patchLock(el, base, edited);
    // Style.
    changed |= _patchColorOrTheme(el, 'FillForegnd', 'QuickStyleFillColor',
        baseColor: base.fill.foreground,
        baseTheme: base.fill.themeForegroundIndex,
        editedColor: edited.fill.foreground,
        editedTheme: edited.fill.themeForegroundIndex);
    // Pattern / theme FillBkgnd. Only touch QuickStyleFillColor when the
    // foreground is not theme-bound (same rule as fresh shape emission) so a
    // theme FillBkgnd patch cannot overwrite FillForegnd's slot. When both
    // slots differ, write THEMEVAL("AccentColorN") instead of bare THEMEVAL().
    changed |= _patchColorOrTheme(el, 'FillBkgnd', 'QuickStyleFillColor',
        baseColor: base.fill.background,
        baseTheme: base.fill.themeBackgroundIndex,
        editedColor: edited.fill.background,
        editedTheme: edited.fill.themeBackgroundIndex,
        writeQuickStyle: edited.fill.themeForegroundIndex == null,
        themeValFormula: () {
          final bg = edited.fill.themeBackgroundIndex;
          final fg = edited.fill.themeForegroundIndex;
          if (bg == null || fg == null || fg == bg) return null;
          final name = ThemeSlot.themeValName(bg);
          return name == null ? null : 'THEMEVAL("$name")';
        }());
    changed |= _patchInt(el, 'FillPattern', base.fill.pattern, edited.fill.pattern);
    changed |= _forceLiteralInt(el, 'FillPattern', edited.fill.pattern);
    changed |= _patchColorOrTheme(el, 'LineColor', 'QuickStyleLineColor',
        baseColor: base.line.color,
        baseTheme: base.line.themeColorIndex,
        editedColor: edited.line.color,
        editedTheme: edited.line.themeColorIndex);
    changed |= _patchLength(el, 'LineWeight', base.line.weightInches, edited.line.weightInches);
    changed |= _forceLiteralLength(el, 'LineWeight', edited.line.weightInches);
    changed |= _patchInt(el, 'LinePattern', base.line.pattern, edited.line.pattern);
    changed |= _forceLiteralInt(el, 'LinePattern', edited.line.pattern);
    changed |= _patchInt(el, 'LineCap', _lineCapInt(base.line.cap), _lineCapInt(edited.line.cap));
    changed |= _forceLiteralInt(el, 'LineCap', _lineCapInt(edited.line.cap));
    changed |= _patchInt(el, 'BeginArrow', base.line.beginArrow, edited.line.beginArrow);
    changed |= _forceLiteralInt(el, 'BeginArrow', edited.line.beginArrow);
    changed |= _patchInt(el, 'EndArrow', base.line.endArrow, edited.line.endArrow);
    changed |= _forceLiteralInt(el, 'EndArrow', edited.line.endArrow);
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
    // Arrow sizes: scrub Inh whether the arrow is on or off (StyleSheet can
    // still revive size companions when Begin/EndArrow is literal 0).
    changed |= _forceLiteralInt(
        el,
        'BeginArrowSize',
        _arrowSizeToBucket(edited.line.beginArrowSizeInches));
    changed |= _forceLiteralInt(
        el,
        'EndArrowSize',
        _arrowSizeToBucket(edited.line.endArrowSizeInches));
    changed |= _patchRatio(el, 'FillForegndTrans',
        base.fill.foregroundTransparency, edited.fill.foregroundTransparency);
    changed |= _forceLiteralRatio(
        el, 'FillForegndTrans', edited.fill.foregroundTransparency);
    changed |= _patchRatio(el, 'FillBkgndTrans',
        base.fill.backgroundTransparency, edited.fill.backgroundTransparency);
    changed |= _forceLiteralRatio(
        el, 'FillBkgndTrans', edited.fill.backgroundTransparency);
    changed |= _patchRatio(
        el, 'LineColorTrans', base.line.transparency, edited.line.transparency);
    changed |= _forceLiteralRatio(el, 'LineColorTrans', edited.line.transparency);
    changed |= _patchLength(
        el, 'Rounding', base.line.roundingInches, edited.line.roundingInches);
    changed |= _forceLiteralLength(el, 'Rounding', edited.line.roundingInches);
    changed |= _patchLength(
        el, 'SoftEdgesSize', base.line.softEdgesInches, edited.line.softEdgesInches);
    changed |=
        _forceLiteralLength(el, 'SoftEdgesSize', edited.line.softEdgesInches);
    changed |= _patchInt(
        el, 'CompoundType', base.line.compoundType, edited.line.compoundType);
    changed |= _forceLiteralInt(el, 'CompoundType', edited.line.compoundType);
    changed |= _patchLayerMember(el, base.layerMemberIds, edited.layerMemberIds);
    // Text block transform (TxtPin / TxtWidth / TxtAngle / margins) +
    // HideText / TextBkgnd + drop shadow / glow / reflection.
    changed |= _patchTextBlock(el, base.richText.textBlock, edited.richText.textBlock);
    changed |= _patchShadow(el, base.shadow, edited.shadow);
    changed |= _patchGlow(el, base.glow, edited.glow);
    changed |= _patchReflection(el, base.reflection, edited.reflection);
    // Disabled effects: force literal V=0 even when base/edited already match
    // as "off" so F=Inh cannot revive Glow/Reflection via StyleSheet inherit.
    if (!edited.shadow.enabled) {
      changed |= _scrubDisabledFlagCell(el, 'ShadowPattern');
      changed |= _scrubDisabledFlagCell(el, 'ShdwPattern');
    }
    if (!edited.glow.enabled) {
      changed |= _forceLiteralZeroLength(el, 'GlowSize');
      // Companion can still carry F=Inh after Size is scrubbed.
      changed |=
          _forceLiteralLength(el, 'GlowColorTrans', edited.glow.transparency);
    }
    if (!edited.shadow.enabled) {
      // Keep companion V= (re-enable), but scrub F=Inh so StyleSheet cannot
      // override offsets / blur while the pattern is off.
      changed |= _forceLiteralLength(
          el, 'ShadowOffsetX', edited.shadow.offsetXInches);
      changed |= _forceLiteralLength(
          el, 'ShadowOffsetY', edited.shadow.offsetYInches);
      changed |=
          _forceLiteralLength(el, 'ShadowBlur', edited.shadow.blurInches);
      changed |= _forceLiteralLength(
          el, 'ShadowForegndTrans', edited.shadow.transparency);
    }
    if (!edited.reflection.enabled) {
      changed |= _forceLiteralZeroLength(el, 'ReflectionSize');
      // Companion cells can still carry F=Inh after Size is scrubbed.
      changed |= _forceLiteralZeroLength(el, 'ReflectionDist');
      changed |= _forceLiteralZeroLength(el, 'ReflectionBlur');
      changed |= _forceLiteralZeroLength(el, 'ReflectionTransparency');
    }
    changed |= _patchGradient(el, base.fill, edited.fill);
    changed |= _patchLineGradient(el, base.line, edited.line);
    // Text content — only rewrite `<Text>` when the plain string changes so
    // existing `<cp>/<pp>/<fld>` markers survive style-only edits (libvisio
    // round-trip). When content does change we rebuild from rich runs with
    // cp/pp markers when possible.
    changed |= _patchTextContent(el, base, edited);
    // Older exports wrote bare <Text> without Character — Edraw then uses a
    // wrong default size. Ensure style sections exist whenever there is text.
    changed |= _ensureTextStyleSections(el, edited);
    // Older exports also omitted Txt* / VerticalAlign; Visio defaults to a
    // full-shape centred box, but Edraw treats missing TxtPin as top-left.
    changed |= _ensureCentredTextBox(el, edited);
    // Geometry (regenerate when it changed and every command is representable,
    // e.g. after resize scaling or connector re-routing).
    changed |= _patchGeometry(el, base, edited);
    // Edraw defaults absent NoFill → 1 (hollow); inject explicit 0/1.
    changed |= _ensureGeometryNoFillNoLine(el, edited);
    // Edge glue points for 2-D shapes (Edraw attaches oddly without them).
    changed |= _ensureConnectionPoints(el, edited);
    // 1-D dynamics Edraw expects on every connector (GlueType / route style).
    changed |= _ensureConnectorDynamics(el, edited);
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
    // Theme / QuickStyle matrix cells (parser reads them; fresh write emits
    // them — patch must too or edit→save drops ThemeIndex).
    changed |= _patchOptionalIntCell(
        el, 'ThemeIndex', base.themeIndex, edited.themeIndex);
    if (edited.themeIndex != null) {
      changed |= _forceLiteralInt(el, 'ThemeIndex', edited.themeIndex!);
    }
    changed |= _patchOptionalIntCell(el, 'QuickStyleFillMatrix',
        base.quickStyleFillMatrix, edited.quickStyleFillMatrix);
    changed |= _patchOptionalIntCell(el, 'QuickStyleLineMatrix',
        base.quickStyleLineMatrix, edited.quickStyleLineMatrix);
    changed |= _patchOptionalIntCell(el, 'QuickStyleEffectsMatrix',
        base.quickStyleEffectsMatrix, edited.quickStyleEffectsMatrix);
    changed |= _patchOptionalIntCell(el, 'QuickStyleFontMatrix',
        base.quickStyleFontMatrix, edited.quickStyleFontMatrix);
    // ObjType / NoAlignBox / etc. — rebuild emits them; patch must too so
    // in-place edits survive save without a group rebuild.
    changed |=
        _patchOptionalIntCell(el, 'ObjType', base.objType, edited.objType);
    changed |= _patchOptionalIntCell(
        el, 'ResizeMode', base.resizeMode, edited.resizeMode);
    changed |=
        _patchFlagCell(el, 'NoAlignBox', base.noAlignBox, edited.noAlignBox);
    changed |= _patchFlagCell(
        el, 'ShapeSplittable', base.shapeSplittable, edited.shapeSplittable);
    changed |= _patchOptionalStringCell(
        el, 'EventDblClick', base.eventDblClick, edited.eventDblClick);
    return changed;
  }

  /// Patch a boolean ShapeSheet flag cell (`V="1"` present ⇒ true; absent ⇒ false).
  bool _patchFlagCell(XmlElement shape, String cell, bool base, bool edited) {
    if (base == edited) {
      if (!edited) return false;
      return _forceLiteralInt(shape, cell, 1);
    }
    if (!edited) return _removeNamedCells(shape, [cell]);
    _writeValue(_ensureCell(shape, cell), '1');
    return true;
  }

  /// Patch an optional string cell (remove when [edited] is null).
  bool _patchOptionalStringCell(
    XmlElement shape,
    String cell,
    String? base,
    String? edited,
  ) {
    if (base == edited) return false;
    if (edited == null) return _removeNamedCells(shape, [cell]);
    _writeValue(_ensureCell(shape, cell), edited);
    return true;
  }

  /// Patch a top-level ShapeSheet int cell that may be absent (`null`).
  bool _patchOptionalIntCell(
    XmlElement shape,
    String cell,
    int? base,
    int? edited,
  ) {
    if (base == edited) return false;
    if (edited == null) {
      final existing = _findCell(shape, cell);
      if (existing == null) return false;
      existing.parent?.children.remove(existing);
      return true;
    }
    _writeValue(_ensureCell(shape, cell), edited.toString());
    return true;
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
  /// Also clears `F=` (and inert trigger `V`) for keys removed from [edited].
  ///
  /// Stale `THEMEVAL` entries left on [edited.formulas] after a solid-colour
  /// override are stripped — otherwise a second save (same in-memory model)
  /// rewrites `F="THEMEVAL()"` over an explicit `V="#…"`.
  bool _patchFormulas(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_mapEqual(base.formulas, edited.formulas)) {
      // Still scrub stale theme formulas that match base-for-base (both dirty).
      var scrubbed = false;
      for (final key in _staleThemeFormulaKeys(edited)) {
        scrubbed |= _clearCellFormulaAttr(el, key);
      }
      return scrubbed;
    }
    var changed = false;
    final stale = _staleThemeFormulaKeys(edited);
    for (final entry in edited.formulas.entries) {
      if (stale.contains(entry.key)) {
        changed |= _clearCellFormulaAttr(el, entry.key);
        continue;
      }
      final prev = base.formulas[entry.key];
      if (prev == entry.value) continue;
      final cell = _ensureCell(el, entry.key);
      cell.setAttribute('F', entry.value);
      changed = true;
    }
    for (final key in base.formulas.keys) {
      if (edited.formulas.containsKey(key) && !stale.contains(key)) continue;
      changed |= _clearCellFormulaAttr(el, key, zeroTriggerValue: true);
    }
    // Stale keys only on edited (not in base) still need XML cleared.
    for (final key in stale) {
      if (base.formulas.containsKey(key)) continue;
      changed |= _clearCellFormulaAttr(el, key);
    }
    return changed;
  }

  /// Cells whose model no longer carries a theme binding but still list a
  /// THEMEVAL formula (leftover from theme → solid / no-fill / pattern edits).
  Set<String> _staleThemeFormulaKeys(VsdxShape s) {
    final out = <String>{};
    bool isThemeVal(String? f) =>
        f != null &&
        RegExp(r'THEMEVAL\s*\(', caseSensitive: false).hasMatch(f);
    if (isThemeVal(s.formulas['FillForegnd']) &&
        (s.fill.foreground != null || s.fill.themeForegroundIndex == null)) {
      out.add('FillForegnd');
    }
    if (isThemeVal(s.formulas['FillBkgnd']) &&
        (s.fill.background != null || s.fill.themeBackgroundIndex == null)) {
      out.add('FillBkgnd');
    }
    if (isThemeVal(s.formulas['LineColor']) &&
        (s.line.color != null || s.line.themeColorIndex == null)) {
      out.add('LineColor');
    }
    // Pattern cells are always literal ints in the model — a leftover
    // THEMEVAL would resurrect theme pattern on a second save.
    if (isThemeVal(s.formulas['FillPattern'])) out.add('FillPattern');
    if (isThemeVal(s.formulas['LinePattern'])) out.add('LinePattern');
    return out;
  }

  /// Align a cell's `F=` with the model formula (or strip it when absent).
  bool _syncCellFormulaAttr(XmlElement el, String cellName, String? formula) {
    if (formula != null && formula.isNotEmpty) {
      final cell = _ensureCell(el, cellName);
      if (cell.getAttribute('F') == formula) return false;
      cell.setAttribute('F', formula);
      return true;
    }
    return _clearCellFormulaAttr(el, cellName);
  }

  bool _clearCellFormulaAttr(
    XmlElement el,
    String cellName, {
    bool zeroTriggerValue = false,
  }) {
    final cell = _findCell(el, cellName);
    if (cell == null) return false;
    var changed = false;
    if (cell.getAttribute('F') != null) {
      cell.removeAttribute('F');
      changed = true;
    }
    if (cell.getAttribute('E') != null) {
      cell.removeAttribute('E');
      changed = true;
    }
    if (zeroTriggerValue &&
        (cellName == 'BegTrigger' || cellName == 'EndTrigger') &&
        cell.getAttribute('V') != '0') {
      cell.setAttribute('V', '0');
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

  /// Patch the shape's `<Section N="Connection">` to match the edited model:
  /// insert a fresh section when missing, rewrite / append rows in place
  /// (preserving unmodelled cells), drop surplus rows when shortened, and
  /// remove the whole section when the edited list is empty.
  bool _patchConnectionPoints(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_connectionPointsEqual(
        base.connectionPoints, edited.connectionPoints)) {
      return false;
    }
    XmlElement? section;
    for (final s in el.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'Connection') {
        section = s;
        break;
      }
    }
    if (edited.connectionPoints.isEmpty) {
      if (section == null) return false;
      section.parent?.children.remove(section);
      return true;
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
        // When the model carries an explicit formula that changed (user drag),
        // rewrite F=; otherwise keep a scale-fitting formula.
        final rewriteXF = p.xFormula != null &&
            (old == null || p.xFormula != old.xFormula || !keepX);
        final rewriteYF = p.yFormula != null &&
            (old == null || p.yFormula != old.yFormula || !keepY);
        _writeValue(xCell, _fmt(p.x),
            preserveFormula: (!rewriteXF) && (keepX || p.xFormula != null));
        _writeValue(yCell, _fmt(p.y),
            preserveFormula: (!rewriteYF) && (keepY || p.yFormula != null));
        if (rewriteXF) {
          xCell.setAttribute('F', p.xFormula!);
        } else if (!keepX && p.xFormula != null) {
          xCell.setAttribute('F', p.xFormula!);
        }
        if (rewriteYF) {
          yCell.setAttribute('F', p.yFormula!);
        } else if (!keepY && p.yFormula != null) {
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
        rows[i].setAttribute('IX', i.toString());
      } else {
        section.children.add(_connectionRow(i, p));
      }
    }
    // Drop surplus rows when the edited list is shorter (connection-point
    // delete in the editor).
    for (var i = rows.length - 1; i >= edited.connectionPoints.length; i--) {
      rows[i].parent?.children.remove(rows[i]);
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
      } else {
        _removeNamedCells(row, const ['ExtraInfo']);
      }
      if (h.frame != null) {
        _writeValue(_ensureCell(row, 'Frame'), h.frame!);
      } else {
        _removeNamedCells(row, const ['Frame']);
      }
      _writeValue(_ensureCell(row, 'NewWindow'), h.newWindow ? '1' : '0');
      _writeValue(_ensureCell(row, 'Default'), h.isDefault ? '1' : '0');
      _writeValue(_ensureCell(row, 'Invisible'), h.invisible ? '1' : '0');
      if (h.sortKey != null) {
        _writeValue(_ensureCell(row, 'SortKey'), h.sortKey!);
      } else {
        _removeNamedCells(row, const ['SortKey']);
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
      // Encode the theme slot in V (a cached value Visio recomputes from the
      // THEMEVAL formula) so the specific accent survives a round-trip.
      final cell = _ensureCell(row, 'Color');
      _writeValue(cell, c.themeColorIndex!.toString(), preserveFormula: true);
      cell.setAttribute('F', 'THEMEVAL()');
    } else {
      // Match [_charCells] rebuild: omit Color when unbound so a prior
      // THEMEVAL cannot revive on the next reopen.
      _removeNamedCells(row, const ['Color']);
    }
    if (c.fontFamily != null) {
      _writeValue(_ensureCell(row, 'Font'), c.fontFamily!);
    }
    _writeValue(_ensureCell(row, 'Strikethru'), c.strikethrough ? '1' : '0');
    // Always write these managed cells so clearing a style (e.g. DblUnderline
    // true→false) on the patch path actually removes the effect from XML.
    _writeValue(_ensureCell(row, 'DblUnderline'), c.doubleUnderline ? '1' : '0');
    _writeValue(_ensureCell(row, 'DoubleStrikethrough'),
        c.doubleStrikethrough ? '1' : '0');
    _writeValue(_ensureCell(row, 'Overline'), c.overline ? '1' : '0');
    _writeValue(_ensureCell(row, 'Letterspace'), _fmt(c.letterSpacingInches));
    _writeValue(
        _ensureCell(row, 'Pos'), _textPositionInt(c.position).toString());
    _writeValue(
        _ensureCell(row, 'Case'), _textCaseInt(c.textCase).toString());
    _writeValue(_ensureCell(row, 'FontScale'), _fmt(c.fontScale));
    _writeValue(_ensureCell(row, 'ColorTrans'), _fmt(c.transparency));
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
    // Always write managed Paragraph cells so clearing a style on the patch
    // path (Bullet 1→0, SpBefore .2→0, …) actually updates the XML row.
    _writeValue(
      _ensureCell(row, 'HorzAlign'),
      _alignToInt(p.horizontalAlign).toString(),
    );
    _writeValue(_ensureCell(row, 'IndFirst'), _fmt(p.indentFirstInches));
    _writeValue(_ensureCell(row, 'IndLeft'), _fmt(p.indentLeftInches));
    _writeValue(_ensureCell(row, 'IndRight'), _fmt(p.indentRightInches));
    _writeValue(_ensureCell(row, 'SpBefore'), _fmt(p.spaceBeforeInches));
    _writeValue(_ensureCell(row, 'SpAfter'), _fmt(p.spaceAfterInches));
    // Visio default single spacing is SpLine = -1 (percentage); omit→inherit
    // would leave a stale absolute value after the user resets spacing.
    _writeValue(_ensureCell(row, 'SpLine'), _fmt(_spLineValue(p) ?? -1));
    _writeValue(_ensureCell(row, 'Bullet'), p.bullet.toString());
    _writeValue(_ensureCell(row, 'BulletStr'), p.bulletStr ?? '');
    _writeValue(_ensureCell(row, 'BulletFont'), p.bulletFont ?? '');
    if (p.bulletFontSizeInches != null) {
      _writeValue(
          _ensureCell(row, 'BulletFontSize'), _fmt(p.bulletFontSizeInches!));
    } else {
      _writeValue(_ensureCell(row, 'BulletFontSize'), '0');
    }
    _writeValue(_ensureCell(row, 'TextPosAfterBullet'),
        _fmt(p.textPosAfterBulletInches));
    _writeValue(_ensureCell(row, 'Flags'), p.flags.toString());
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
          var keep = _formulaFitsScale(
              cell.getAttribute('F'), oldV, newV, sx: sx, sy: sy);
          // C (angle) / D (eccentricity) are not Width/Height scales — keeping
          // a constant F= would undo resized V in Visio/Edraw.
          if ((ce is EllipticalArcTo || ce is RelEllipticalArcTo) &&
              (name == 'C' || name == 'D')) {
            keep = false;
          }
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
        NurbsTo(
          :final x,
          :final y,
          :final weights,
          :final knots,
        ) =>
          {
            'X': x,
            'Y': y,
            // MS-VSDX NURBSTo: A=2nd-to-last knot, B=last weight,
            // C=first knot, D=first weight.
            'A': knots.length >= 2 ? knots[knots.length - 2] : 0.0,
            'B': weights.isNotEmpty ? weights.last : 1.0,
            'C': knots.isNotEmpty ? knots.first : 0.0,
            'D': weights.isNotEmpty ? weights.first : 1.0,
          },
      };

  Map<String, String>? _commandFormulaCells(VsdxPathCommand cmd) =>
      switch (cmd) {
        PolylineTo(
          :final vertices,
          :final vertsRelative,
          :final vertsYRelative,
        ) =>
          {
            // POLYLINE(xType,yType,…): 0 = % of Width/Height, 1 = local inches.
            'A': () {
              // Rel* only affects the endpoint row type; formula flags are independent.
              final xt = vertsRelative ? 0 : 1;
              final yt = vertsYRelative ? 0 : 1;
              final buf = StringBuffer('POLYLINE($xt,$yt');
              for (final v in vertices) {
                buf.write(',${_fmt(v.x)},${_fmt(v.y)}');
              }
              buf.write(')');
              return buf.toString();
            }(),
          },
        NurbsTo(
          :final controlPoints,
          :final weights,
          :final knots,
          :final degree,
          :final cpRelative,
          :final cpYRelative,
        ) =>
          {
            'E': _nurbsEFormula(
              controlPoints: controlPoints,
              weights: weights,
              knots: knots,
              degree: degree,
              xType: cpRelative ? 0 : 1,
              yType: cpYRelative ? 0 : 1,
            ),
          },
        _ => null,
      };

  /// Build `NURBS(knotLast,degree,xType,yType,…)` from assembled or interior
  /// knot/weight vectors (libvisio layout: `[C,…,A,knotLast]` / `[D,…,B]`).
  String _nurbsEFormula({
    required List<Offset2D> controlPoints,
    required List<double> weights,
    required List<double> knots,
    required int degree,
    required int xType,
    required int yType,
  }) {
    final knotLast = knots.isNotEmpty ? knots.last : 1.0;
    final fullW = weights.length == controlPoints.length + 2;
    final fullK = knots.length >= controlPoints.length + 3;
    final buf = StringBuffer('NURBS(${_fmt(knotLast)},$degree,$xType,$yType');
    for (var i = 0; i < controlPoints.length; i++) {
      final p = controlPoints[i];
      final knot = fullK
          ? knots[i + 1]
          : (i < knots.length ? knots[i] : (i + 1).toDouble());
      final weight = fullW
          ? weights[i + 1]
          : (i < weights.length ? weights[i] : 1.0);
      buf.write(',${_fmt(p.x)},${_fmt(p.y)},${_fmt(knot)},${_fmt(weight)}');
    }
    buf.write(')');
    return buf.toString();
  }

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
        // Structural compare — PolylineTo/NurbsTo toString omits vertex data.
        if (!pathCommandsEqual(ga.commands[j], gb.commands[j])) {
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

  /// Patch a colour cell that may be either an explicit colour **or** a
  /// theme-slot binding (`THEMEVAL()` + a `QuickStyle*Color` index). The parser
  /// keys off the `THEMEVAL` formula: switching to a solid colour drops it,
  /// switching to a theme slot (re)writes it. Without this, re-binding an
  /// existing shape to a theme colour silently reverted to its old solid colour
  /// on save, because [_patchColor] ignores a `null` (theme-bound) colour.
  bool _patchColorOrTheme(
    XmlElement shape,
    String cell,
    String quickStyleCell, {
    required VsdxColor? baseColor,
    required int? baseTheme,
    required VsdxColor? editedColor,
    required int? editedTheme,
    bool writeQuickStyle = true,
    String? themeValFormula,
  }) {
    if (editedColor != null) {
      // Explicit colour: _writeValue drops any inherited THEMEVAL formula so
      // the chosen colour is honoured (the parser then ignores QuickStyle*).
      final curF = _cellFormula(shape, cell);
      final hasThemeF = curF != null &&
          RegExp(r'THEMEVAL\s*\(', caseSensitive: false).hasMatch(curF);
      var changed = false;
      if (!(baseTheme == null &&
          editedTheme == null &&
          baseColor?.value == editedColor.value &&
          !hasThemeF)) {
        _writeValue(_ensureCell(shape, cell), _hex(editedColor));
        changed = true;
      }
      // Drop leftover QuickStyle* when no longer theme-bound (Shadow/Glow
      // already remove companion cells; Fill/Line previously left them).
      if (editedTheme == null && writeQuickStyle) {
        if (_removeNamedCells(shape, [quickStyleCell])) changed = true;
      }
      return changed;
    }
    if (editedTheme != null) {
      final wantF = themeValFormula ?? 'THEMEVAL()';
      final curF = _cellFormula(shape, cell);
      final formulaOk = curF == wantF ||
          (themeValFormula == null &&
              (curF == null ||
                  RegExp(r'^THEMEVAL\s*\(\s*\)$', caseSensitive: false)
                      .hasMatch(curF)));
      if (baseTheme == editedTheme && baseColor == null && formulaOk) {
        return false;
      }
      final c = _ensureCell(shape, cell);
      _writeValue(c, '0', preserveFormula: true);
      c.setAttribute('F', wantF);
      if (writeQuickStyle) {
        _writeValue(
            _ensureCell(shape, quickStyleCell), editedTheme.toString());
      }
      return true;
    }
    // Theme cleared with no replacement colour (e.g. FillBkgnd after solid).
    if (baseTheme != null ||
        (_cellFormula(shape, cell) != null &&
            RegExp(r'THEMEVAL\s*\(', caseSensitive: false)
                .hasMatch(_cellFormula(shape, cell)!))) {
      var changed = false;
      // Remove the colour cell entirely so reopen does not parse leftover
      // V="0" as palette[0] black. Rebuild path also omits unbound colours.
      if (_removeNamedCells(shape, [cell])) {
        changed = true;
      } else {
        final c = _findCell(shape, cell);
        if (c != null) {
          c.removeAttribute('F');
          c.removeAttribute('E');
          changed = true;
        }
      }
      if (writeQuickStyle) {
        if (_removeNamedCells(shape, [quickStyleCell])) changed = true;
      }
      return changed;
    }
    return false;
  }

  static String? _cellFormula(XmlElement shape, String cell) {
    for (final el in shape.childElements) {
      if (el.name.local == 'Cell' && el.getAttribute('N') == cell) {
        return el.getAttribute('F');
      }
    }
    return null;
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
    final runs = _effectiveTextRuns(edited);
    for (var i = 0; i < runs.length; i++) {
      textEl.children.add(XmlElement(
        XmlName('pp'),
        <XmlAttribute>[XmlAttribute(XmlName('IX'), i.toString())],
      ));
      textEl.children.add(XmlElement(
        XmlName('cp'),
        <XmlAttribute>[XmlAttribute(XmlName('IX'), i.toString())],
      ));
      _appendRunText(textEl.children, runs[i]);
    }
    // Keep Character / Paragraph sections in sync when content is rewritten.
    _patchTextStyleSections(el, runs);
    return true;
  }

  void _patchTextStyleSections(XmlElement el, List<VsdxTextRun> runs) {
    if (runs.isEmpty) return;
    for (final child in el.childElements.toList()) {
      if (child.name.local != 'Section') continue;
      final n = child.getAttribute('N');
      if (n == 'Character' || n == 'Paragraph') child.remove();
    }
    XmlElement? textEl;
    for (final c in el.childElements) {
      if (c.name.local == 'Text') {
        textEl = c;
        break;
      }
    }
    final insertAt =
        textEl == null ? el.children.length : el.children.indexOf(textEl);
    el.children.insert(insertAt, _buildCharacterSection(runs));
    el.children.insert(insertAt + 1, _buildParagraphSection(runs));
  }

  /// Rich runs, or a synthesised run from plain [VsdxShape.text] using the same
  /// proportional size the Flutter painter uses for unstyled labels — so Edraw
  /// matches in-app appearance after export.
  static List<VsdxTextRun> _effectiveTextRuns(VsdxShape s) {
    if (s.richText.runs.isNotEmpty) return s.richText.runs;
    final t = s.text;
    if (t == null || t.isEmpty) return const <VsdxTextRun>[];
    final box = math.min(s.width.abs(), s.height.abs());
    final sizeInches = (s.is1D ? 0.14 : box * 0.18).clamp(4.0 / 72.0, 1.0);
    final cjk = _containsCjk(t);
    return <VsdxTextRun>[
      VsdxTextRun(
        text: t,
        charStyle: VsdxCharStyle(
          fontSizeInches: sizeInches,
          fontFamily: cjk ? _defaultAsianFont : 'Arial',
          asianFont: _defaultAsianFont,
          langId: cjk ? 'zh-CN' : null,
        ),
        // Match the canvas (centred labels) and Edraw flowchart defaults.
        paraStyle:
            const VsdxParaStyle(horizontalAlign: VsdxHorzAlign.center),
      ),
    ];
  }

  static bool _containsCjk(String s) {
    for (final r in s.runes) {
      if (r >= 0x4E00 && r <= 0x9FFF) return true;
      if (r >= 0x3400 && r <= 0x4DBF) return true;
      if (r >= 0xF900 && r <= 0xFAFF) return true;
    }
    return false;
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
        base.themeColorIndex == edited.themeColorIndex &&
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
      // Re-enable after Pattern=0: model defaults match so _patchLength /
      // _patchColorOrTheme would skip and leave stale Offset/Foregnd in XML.
      final reenable = !base.enabled;
      if (reenable ||
          edited.color != null ||
          edited.themeColorIndex != null ||
          base.color != null ||
          base.themeColorIndex != null) {
        if (edited.color == null && edited.themeColorIndex == null) {
          // Default shadow has no authored colour — drop stale cells so reopen
          // does not resurrect a previous solid / theme Foregnd.
          if (_removeNamedCells(el, const ['ShadowForegnd', 'QuickStyleShadowColor'])) {
            changed = true;
          }
        } else {
          changed |= _patchColorOrTheme(
            el,
            'ShadowForegnd',
            'QuickStyleShadowColor',
            baseColor: reenable ? null : base.color,
            baseTheme: reenable ? null : base.themeColorIndex,
            editedColor: edited.color,
            editedTheme: edited.themeColorIndex,
          );
        }
      }
      if (reenable ||
          (base.offsetXInches - edited.offsetXInches).abs() > _epsilon) {
        _writeValue(
            _ensureCell(el, 'ShadowOffsetX'), _fmt(edited.offsetXInches));
        changed = true;
      }
      if (reenable ||
          (base.offsetYInches - edited.offsetYInches).abs() > _epsilon) {
        _writeValue(
            _ensureCell(el, 'ShadowOffsetY'), _fmt(edited.offsetYInches));
        changed = true;
      }
      if (reenable ||
          (base.blurInches - edited.blurInches).abs() > _epsilon) {
        _writeValue(_ensureCell(el, 'ShadowBlur'), _fmt(edited.blurInches));
        changed = true;
      }
      if (reenable ||
          (base.transparency - edited.transparency).abs() > _epsilon) {
        _writeValue(
            _ensureCell(el, 'ShadowForegndTrans'), _fmt(edited.transparency));
        changed = true;
      }
    }
    return changed;
  }

  /// Remove shape-level `<Cell N="…">` entries. Returns true if any removed.
  bool _removeNamedCells(XmlElement shape, List<String> names) {
    final want = names.toSet();
    var any = false;
    for (final el in shape.childElements.toList()) {
      if (el.name.local != 'Cell') continue;
      final n = el.getAttribute('N');
      if (n != null && want.contains(n)) {
        el.parent?.children.remove(el);
        any = true;
      }
    }
    return any;
  }

  bool _patchGlow(XmlElement el, VsdxGlow base, VsdxGlow edited) {
    if (base.enabled == edited.enabled &&
        base.color?.value == edited.color?.value &&
        base.themeColorIndex == edited.themeColorIndex &&
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
    // Re-enable after Size=0: force Size/Color/Trans so stale GlowColor cannot
    // resurrect over a default (null-colour) model — same rule as Shadow.
    final reenable = !base.enabled;
    if (reenable ||
        (base.sizeInches - edited.sizeInches).abs() > _epsilon) {
      _writeValue(_ensureCell(el, 'GlowSize'), _fmt(edited.sizeInches));
      changed = true;
    }
    if (reenable ||
        edited.color != null ||
        edited.themeColorIndex != null ||
        base.color != null ||
        base.themeColorIndex != null) {
      if (edited.color == null && edited.themeColorIndex == null) {
        if (_removeNamedCells(
            el, const ['GlowColor', 'QuickStyleEffectColor'])) {
          changed = true;
        }
      } else {
        changed |= _patchColorOrTheme(
          el,
          'GlowColor',
          'QuickStyleEffectColor',
          baseColor: reenable ? null : base.color,
          baseTheme: reenable ? null : base.themeColorIndex,
          editedColor: edited.color,
          editedTheme: edited.themeColorIndex,
        );
      }
    }
    if (reenable ||
        (base.transparency - edited.transparency).abs() > _epsilon) {
      _writeValue(
          _ensureCell(el, 'GlowColorTrans'), _fmt(edited.transparency));
      changed = true;
    }
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
    // Re-enable after Size=0: force Size/Dist/Blur/Trans so stale XML cells
    // cannot resurrect prior custom values over the new model defaults.
    final reenable = !base.enabled;
    if (reenable ||
        (base.sizeInches - edited.sizeInches).abs() > _epsilon) {
      _writeValue(_ensureCell(el, 'ReflectionSize'), _fmt(edited.sizeInches));
      changed = true;
    }
    if (reenable ||
        (base.distanceInches - edited.distanceInches).abs() > _epsilon) {
      _writeValue(
          _ensureCell(el, 'ReflectionDist'), _fmt(edited.distanceInches));
      changed = true;
    }
    if (reenable ||
        (base.transparency - edited.transparency).abs() > _epsilon) {
      _writeValue(_ensureCell(el, 'ReflectionTransparency'),
          _fmt(edited.transparency));
      changed = true;
    }
    if (reenable ||
        (base.blurInches - edited.blurInches).abs() > _epsilon) {
      _writeValue(_ensureCell(el, 'ReflectionBlur'), _fmt(edited.blurInches));
      changed = true;
    }
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
        // Literal V=1 — do not keep F="Inh" / parametric, which would ignore V.
        _writeValue(_ensureCell(el, 'FillGradientEnabled'), '1');
        _writeValue(_ensureCell(el, 'FillGradientDir'),
            _gradientDirFromType(eg.type).toString());
        _writeValue(_ensureCell(el, 'FillGradientAngle'), _fmt(eg.angleRad));
        _insertBeforeTextOrShapes(el, _buildFillGradientSection(eg));
      } else {
        // Clearing must drop Inh/parametric F= so Visio cannot revive the
        // deleted FillGradient section via inheritance.
        _writeValue(_ensureCell(el, 'FillGradientEnabled'), '0');
      }
      return true;
    }
    // Models already agree on "no gradient" but XML may still say V=0 F=Inh.
    if (eg == null || eg.stops.isEmpty) {
      return _scrubDisabledFlagCell(el, 'FillGradientEnabled');
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
        _writeValue(_ensureCell(el, 'LineGradientEnabled'), '1');
        _writeValue(_ensureCell(el, 'LineGradientDir'),
            _gradientDirFromType(eg.type).toString());
        _writeValue(_ensureCell(el, 'LineGradientAngle'), _fmt(eg.angleRad));
        _insertBeforeTextOrShapes(el, _buildLineGradientSection(eg));
      } else {
        _writeValue(_ensureCell(el, 'LineGradientEnabled'), '0');
      }
      return true;
    }
    if (eg == null || eg.stops.isEmpty) {
      return _scrubDisabledFlagCell(el, 'LineGradientEnabled');
    }
    return false;
  }

  /// When the model has a flag off, force literal `V=0` without `F=` so
  /// stylesheet `Inh` cannot revive the feature on reopen.
  bool _scrubDisabledFlagCell(XmlElement shape, String cell) {
    final c = _findCell(shape, cell);
    if (c == null) return false;
    final f = c.getAttribute('F');
    final v = c.getAttribute('V');
    final already =
        (v == '0' || v == '0.0') && (f == null || f.isEmpty);
    if (already) return false;
    _writeValue(c, '0');
    return true;
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
    // Model verticalAlign is authoritative — scrub F=Inh even when value matches.
    changed |= _forceLiteralInt(
        el, 'VerticalAlign', _vAlignInt(edited.verticalAlign));
    changed |= _patchInt(
        el, 'HideText', base.hideText ? 1 : 0, edited.hideText ? 1 : 0);
    changed |= _forceLiteralInt(el, 'HideText', edited.hideText ? 1 : 0);
    changed |= _patchInt(
        el, 'TextDirection', base.textDirection, edited.textDirection);
    changed |= _forceLiteralInt(el, 'TextDirection', edited.textDirection);
    changed |= _patchLength(el, 'DefaultTabStop', base.defaultTabStopInches,
        edited.defaultTabStopInches);
    changed |= _forceLiteralLength(
        el, 'DefaultTabStop', edited.defaultTabStopInches);
    if (edited.backgroundColor != null) {
      changed |= _patchColor(
          el, 'TextBkgnd', base.backgroundColor, edited.backgroundColor);
      changed |= _forceLiteralColor(el, 'TextBkgnd', edited.backgroundColor!);
    } else if (base.backgroundColor != null) {
      _writeValue(_ensureCell(el, 'TextBkgnd'), '0');
      changed = true;
    }
    changed |= _patchRatio(
        el,
        'TextBkgndTrans',
        base.backgroundTransparency,
        edited.backgroundTransparency);
    changed |= _forceLiteralRatio(
        el, 'TextBkgndTrans', edited.backgroundTransparency);
    changed |= _patchLength(
        el, 'LeftMargin', base.marginLeftInches, edited.marginLeftInches);
    changed |=
        _forceLiteralLength(el, 'LeftMargin', edited.marginLeftInches);
    changed |= _patchLength(
        el, 'RightMargin', base.marginRightInches, edited.marginRightInches);
    changed |=
        _forceLiteralLength(el, 'RightMargin', edited.marginRightInches);
    changed |= _patchLength(
        el, 'TopMargin', base.marginTopInches, edited.marginTopInches);
    changed |= _forceLiteralLength(el, 'TopMargin', edited.marginTopInches);
    changed |= _patchLength(
        el, 'BottomMargin', base.marginBottomInches, edited.marginBottomInches);
    changed |=
        _forceLiteralLength(el, 'BottomMargin', edited.marginBottomInches);
    return changed;
  }

  /// Emit text-block cells for a brand-new shape (non-default values only).
  /// [formulas] carries Txt* `F=` (`SETATREF`, `TEXTWIDTH`, `Width*…`).
  /// When [hasLabel] and [shapeForDefaults] are set, synthesise a centred
  /// text box (TxtPin*/TxtWidth/TxtHeight + VerticalAlign) for EdrawMax.
  void _appendTextBlockCells(
    List<XmlNode> children,
    VsdxTextBlock b, {
    Map<String, String> formulas = const <String, String>{},
    VsdxShape? shapeForDefaults,
    bool hasLabel = false,
  }) {
    void addLen(String name, double? v, {String? defaultFormula, double? fallback}) {
      final f = formulas[name] ?? defaultFormula;
      final value = v ?? fallback;
      if (value == null && f == null) return;
      children.add(_cell(name, _fmt(value ?? 0), formula: f));
    }

    // Edraw needs an explicit text box + VerticalAlign for centred labels;
    // without Txt* cells Chinese/Latin text often sits at the top-left.
    final fillBox = hasLabel &&
        shapeForDefaults != null &&
        !shapeForDefaults.is1D &&
        b.pinXInches == null &&
        !formulas.containsKey('TxtPinX');
    final w = shapeForDefaults?.width ?? 0;
    final h = shapeForDefaults?.height ?? 0;

    addLen('TxtPinX', b.pinXInches,
        defaultFormula: fillBox ? 'Width*0.5' : null,
        fallback: fillBox ? w / 2 : null);
    addLen('TxtPinY', b.pinYInches,
        defaultFormula: fillBox ? 'Height*0.5' : null,
        fallback: fillBox ? h / 2 : null);
    addLen('TxtWidth', b.widthInches,
        defaultFormula: fillBox ? 'Width*1' : null,
        fallback: fillBox ? w : null);
    addLen('TxtHeight', b.heightInches,
        defaultFormula: fillBox ? 'Height*1' : null,
        fallback: fillBox ? h : null);
    addLen('TxtLocPinX', b.locPinXInches,
        defaultFormula: fillBox ? 'TxtWidth*0.5' : null,
        fallback: fillBox ? w / 2 : null);
    addLen('TxtLocPinY', b.locPinYInches,
        defaultFormula: fillBox ? 'TxtHeight*0.5' : null,
        fallback: fillBox ? h / 2 : null);
    if (b.angleRad.abs() > _epsilon || formulas.containsKey('TxtAngle')) {
      children.add(
          _cell('TxtAngle', _fmt(b.angleRad), formula: formulas['TxtAngle']));
    }
    if (hasLabel || b.verticalAlign != VsdxVertAlign.middle) {
      children.add(
          _cell('VerticalAlign', _vAlignInt(b.verticalAlign).toString()));
    }
    // Always emit HideText (incl. 0) so Master HideText=1 cannot revive after
    // the user un-hides on a group-rebuild path.
    children.add(_cell('HideText', b.hideText ? '1' : '0'));
    if (b.backgroundColor != null) {
      children.add(_cell('TextBkgnd', _hex(b.backgroundColor!)));
    } else {
      // Explicit clear — matches patch path and prevents Master TextBkgnd
      // inheritance on reopen (parser treats V=0 as transparent).
      children.add(_cell('TextBkgnd', '0'));
    }
    // Always emit Trans / Direction / DefaultTabStop (incl. defaults) so Master
    // values cannot revive after clear + group rebuild.
    children.add(_cell('TextBkgndTrans', _fmt(b.backgroundTransparency)));
    children.add(_cell('TextDirection', b.textDirection.toString()));
    children.add(_cell('DefaultTabStop', _fmt(b.defaultTabStopInches)));
    const d = VsdxTextBlock.defaults;
    final margin = hasLabel ? 0.05555555555555555 : null;
    if ((b.marginLeftInches - d.marginLeftInches).abs() > _epsilon) {
      children.add(_cell('LeftMargin', _fmt(b.marginLeftInches)));
    } else if (margin != null) {
      children.add(_cell('LeftMargin', _fmt(margin)));
    }
    if ((b.marginRightInches - d.marginRightInches).abs() > _epsilon) {
      children.add(_cell('RightMargin', _fmt(b.marginRightInches)));
    } else if (margin != null) {
      children.add(_cell('RightMargin', _fmt(margin)));
    }
    if ((b.marginTopInches - d.marginTopInches).abs() > _epsilon) {
      children.add(_cell('TopMargin', _fmt(b.marginTopInches)));
    } else if (margin != null) {
      children.add(_cell('TopMargin', _fmt(margin)));
    }
    if ((b.marginBottomInches - d.marginBottomInches).abs() > _epsilon) {
      children.add(_cell('BottomMargin', _fmt(b.marginBottomInches)));
    } else if (margin != null) {
      children.add(_cell('BottomMargin', _fmt(margin)));
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

  /// When the model length is 0, ensure XML is literal `V=0` without `F=Inh`
  /// (even if base already parsed as 0 and `_patchLength` was a no-op).
  bool _forceLiteralZeroLength(XmlElement shape, String cell) {
    final c = _findCell(shape, cell);
    if (c == null) return false;
    final f = c.getAttribute('F');
    final v = c.getAttribute('V');
    final already =
        (v == '0' || v == '0.0') && (f == null || f.isEmpty);
    if (already) return false;
    _writeValue(c, '0');
    return true;
  }

  /// Ensure an int cell is literal [value] without `F=` (scrub Inh / stale F).
  bool _forceLiteralInt(XmlElement shape, String cell, int value) {
    final c = _findCell(shape, cell);
    if (c == null) return false;
    final f = c.getAttribute('F');
    final v = c.getAttribute('V');
    final want = value.toString();
    final already = v == want && (f == null || f.isEmpty);
    if (already) return false;
    _writeValue(c, want);
    return true;
  }

  /// Ensure a length cell is literal [value] without `F=`.
  bool _forceLiteralLength(XmlElement shape, String cell, double value) {
    final c = _findCell(shape, cell);
    if (c == null) return false;
    final f = c.getAttribute('F');
    final v = c.getAttribute('V');
    final parsed = v == null ? null : double.tryParse(v);
    final already = (f == null || f.isEmpty) &&
        parsed != null &&
        (parsed - value).abs() <= _epsilon;
    if (already) return false;
    _writeValue(c, _fmt(value));
    return true;
  }

  /// Ensure a 0..1 ratio cell is literal [value] without `F=`.
  bool _forceLiteralRatio(XmlElement shape, String cell, double value) =>
      _forceLiteralLength(shape, cell, value);

  /// Ensure a colour cell is literal hex without `F=`.
  bool _forceLiteralColor(XmlElement shape, String cell, VsdxColor color) {
    final c = _findCell(shape, cell);
    if (c == null) return false;
    final f = c.getAttribute('F');
    final v = c.getAttribute('V');
    final want = _hex(color);
    final already = (f == null || f.isEmpty) &&
        v != null &&
        v.toUpperCase() == want.toUpperCase();
    if (already) return false;
    _writeValue(c, want);
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

  bool _hasCell(XmlElement shape, String name) => _findCell(shape, name) != null;

  XmlElement? _findCell(XmlElement shape, String name) {
    for (final el in shape.childElements) {
      if (el.name.local == 'Cell' && el.getAttribute('N') == name) return el;
    }
    return null;
  }

  /// Write LineCap / ObjType when absent (Edraw is picky about both).
  /// Also upgrade arrow-size bucket 0→2 when an arrow is present so legacy
  /// files reopen in 万兴图示 with Visio-default arrowheads.
  bool _ensureLineFillBasics(XmlElement el, VsdxShape s) {
    var changed = false;
    if (!_hasCell(el, 'LineCap')) {
      _ensureCell(el, 'LineCap')
          .setAttribute('V', _lineCapInt(s.line.cap).toString());
      changed = true;
    }
    if (s.is1D && !_hasCell(el, 'ObjType')) {
      _ensureCell(el, 'ObjType').setAttribute('V', (s.objType ?? 2).toString());
      changed = true;
    }
    if (s.line.beginArrow != 0) {
      final cell = _findCell(el, 'BeginArrowSize');
      if (cell == null || (cell.getAttribute('V') ?? '0') == '0') {
        _ensureCell(el, 'BeginArrowSize').setAttribute('V', '2');
        changed = true;
      }
    }
    if (s.line.endArrow != 0) {
      final cell = _findCell(el, 'EndArrowSize');
      if (cell == null || (cell.getAttribute('V') ?? '0') == '0') {
        _ensureCell(el, 'EndArrowSize').setAttribute('V', '2');
        changed = true;
      }
    }
    return changed;
  }

  /// Write default mid-edge Connection points when a 2-D shape has none.
  bool _ensureConnectionPoints(XmlElement el, VsdxShape s) {
    if (s.is1D) return false;
    if (el.getAttribute('Master') != null ||
        el.getAttribute('MasterShape') != null) {
      return false;
    }
    for (final child in el.childElements) {
      if (child.name.local == 'Section' &&
          child.getAttribute('N') == 'Connection') {
        return false;
      }
    }
    final cps = s.connectionPoints.isNotEmpty
        ? s.connectionPoints
        : VsdxPage.defaultConnectionPoints(s.width, s.height);
    if (cps.isEmpty) return false;
    el.children.add(_buildConnectionSection(cps));
    return true;
  }

  /// Write Edraw-default connector dynamics when a 1-D **connector** lacks them.
  /// Skips freehand ink (`ObjType=1`) which uses an AABB local frame, not the
  /// Visio Begin-origin Width=EndX-BeginX convention.
  bool _ensureConnectorDynamics(XmlElement el, VsdxShape s) {
    if (!s.is1D) return false;
    // Freehand / ink strokes are 1-D but not glueable connectors.
    if (s.objType != null && s.objType != 2) return false;
    var changed = false;
    void put(String name, String value) {
      if (!_hasCell(el, name)) {
        _ensureCell(el, name).setAttribute('V', value);
        changed = true;
      }
    }

    put('GlueType', (s.connectorProps?.glueType ?? 2).toString());
    put('ConLineRouteExt', (s.connectorProps?.conLineRouteExt ?? 1).toString());
    put('ShapeRouteStyle',
        (s.connectorProps?.shapeRouteStyle ?? 16).toString());
    put('DynFeedback', (s.connectorProps?.dynFeedback ?? 2).toString());
    // Default 3 (reroute on crossover) — matches Visio fixtures. Never use 0
    // (reroute freely): 万兴图示 then discards multi-segment Geometry.
    put('ConFixedCode', (s.connectorProps?.conFixedCode ?? 3).toString());
    put('NoAlignBox', '1');
    put('NoLiveDynamics', '1');
    put('ShapeSplittable', '1');
    put('ShdwPattern', s.shadow.enabled ? '1' : '0');
    // Pin centred on Begin/End — Edraw samples always carry these formulas.
    void putPinFormula(String name, String fallback, double value) {
      final cell = _ensureCell(el, name);
      final formula = s.formulas[name] ?? fallback;
      if (cell.getAttribute('F') != formula) {
        cell.setAttribute('F', formula);
        changed = true;
      }
      if (cell.getAttribute('V') == null) {
        cell.setAttribute('V', _fmt(value));
        changed = true;
      }
    }

    putPinFormula('PinX', '(BeginX+EndX)*0.5', s.pinX);
    putPinFormula('PinY', '(BeginY+EndY)*0.5', s.pinY);
    // Visio 1-D size / LocPin — required so Geometry rooted at Begin (0,0)
    // places correctly when Width/Height are signed End−Begin deltas.
    putPinFormula('Width', 'EndX-BeginX', s.width);
    putPinFormula('Height', 'EndY-BeginY', s.height);
    putPinFormula('LocPinX', '(EndX-BeginX)/2', s.effectiveLocPinX);
    putPinFormula('LocPinY', '(EndY-BeginY)/2', s.effectiveLocPinY);
    // If an older export left ConFixedCode=0, force it up to the model value.
    final wantFixed = s.connectorProps?.conFixedCode ?? 3;
    final fixedCell = _ensureCell(el, 'ConFixedCode');
    if (fixedCell.getAttribute('V') != wantFixed.toString() ||
        fixedCell.getAttribute('F') != null) {
      _writeValue(fixedCell, wantFixed.toString());
      changed = true;
    }
    return changed;
  }

  /// Sync Geometry NoFill/NoLine to the model. Edraw treats missing NoFill as
  /// 1 (no fill), so filled shapes export hollow unless we emit V="0". Also
  /// force-updates stale cells after UI setNoFill / setNoLine.
  bool _ensureGeometryNoFillNoLine(XmlElement el, VsdxShape s) {
    final sections = <XmlElement>[
      for (final child in el.childElements)
        if (child.name.local == 'Section' &&
            child.getAttribute('N') == 'Geometry')
          child,
    ];
    if (sections.isEmpty) return false;
    var changed = false;
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      final g = i < s.geometries.length ? s.geometries[i] : null;
      final wantFill = g?.noFill ?? false;
      final wantLine = g?.noLine ?? false;
      changed |= _syncGeometryFlagCell(section, 'NoFill', wantFill);
      changed |= _syncGeometryFlagCell(section, 'NoLine', wantLine);
    }
    return changed;
  }

  bool _syncGeometryFlagCell(XmlElement section, String name, bool want) {
    final wantV = want ? '1' : '0';
    final existing = _findCell(section, name);
    if (existing != null) {
      if (existing.getAttribute('V') == wantV &&
          existing.getAttribute('F') == null) {
        return false;
      }
      _writeValue(existing, wantV);
      return true;
    }
    // Insert before first Row so flags stay section-level.
    var insertAt = 0;
    for (var j = 0; j < section.children.length; j++) {
      final n = section.children[j];
      if (n is XmlElement && n.name.local == 'Row') {
        insertAt = j;
        break;
      }
    }
    section.children.insert(insertAt, _cell(name, wantV));
    return true;
  }

  /// Write LocPinX/Y when absent so Edraw/libvisio don't default to (0,0).
  /// Ensure Foreign/Image shapes carry ImgOffset*/ImgWidth/ImgHeight and that
  /// the cached `V=` matches the shape size when the formula is the default
  /// full-frame mapping (Edraw often ignores `F=`). Custom crop formulas keep
  /// their `F=` but refresh `V=` from the model so pan/crop edits persist.
  bool _syncImageSizeCells(XmlElement el, VsdxShape s) {
    var changed = false;
    for (final entry in <(String, double)>[
      ('ImgOffsetX', s.imgOffsetXInches),
      ('ImgOffsetY', s.imgOffsetYInches),
    ]) {
      final cell = _ensureCell(el, entry.$1);
      final next = _fmt(entry.$2);
      if (cell.getAttribute('V') != next) {
        cell.setAttribute('V', next);
        changed = true;
      }
    }
    for (final entry in <(String, double, String, double)>[
      ('ImgWidth', s.effectiveImgWidth, 'Width*1', s.width),
      ('ImgHeight', s.effectiveImgHeight, 'Height*1', s.height),
    ]) {
      final cell = _ensureCell(el, entry.$1);
      final f = (cell.getAttribute('F') ?? '').replaceAll(' ', '');
      final defaultF = entry.$3.replaceAll(' ', '');
      final isDefaultMapping = f.isEmpty || f == defaultF;
      final next = _fmt(isDefaultMapping ? entry.$4 : entry.$2);
      if (cell.getAttribute('V') != next) {
        cell.setAttribute('V', next);
        changed = true;
      }
      if (isDefaultMapping && (cell.getAttribute('F') ?? '').isEmpty) {
        cell.setAttribute('F', entry.$3);
        changed = true;
      }
    }
    for (final entry in <(String, double)>[
      ('Transparency', s.imageTransparency.clamp(0.0, 1.0)),
      ('Blur', s.imageBlur.clamp(0.0, 1.0)),
      ('Brightness', s.imageBrightness.clamp(0.0, 1.0)),
      ('Contrast', s.imageContrast.clamp(0.0, 1.0)),
    ]) {
      final cell = _ensureCell(el, entry.$1);
      final next = _fmt(entry.$2);
      if (cell.getAttribute('V') != next) {
        cell.setAttribute('V', next);
        changed = true;
      }
    }
    return changed;
  }

  bool _ensureLocPinPresent(XmlElement el, VsdxShape s) {
    var changed = false;
    if (!_hasCell(el, 'LocPinX')) {
      final cell = _ensureCell(el, 'LocPinX');
      cell.setAttribute('V', _fmt(s.effectiveLocPinX));
      if ((s.effectiveLocPinX - s.width / 2).abs() <= _epsilon) {
        cell.setAttribute('F', 'Width*0.5');
      }
      changed = true;
    }
    if (!_hasCell(el, 'LocPinY')) {
      final cell = _ensureCell(el, 'LocPinY');
      cell.setAttribute('V', _fmt(s.effectiveLocPinY));
      if ((s.effectiveLocPinY - s.height / 2).abs() <= _epsilon) {
        cell.setAttribute('F', 'Height*0.5');
      }
      changed = true;
    }
    return changed;
  }

  /// Inject Visio-default text box (full width/height, centred) when a labelled
  /// 2-D shape has no TxtPinX — required for EdrawMax to centre the label.
  bool _ensureCentredTextBox(XmlElement el, VsdxShape s) {
    if (el.getAttribute('Master') != null ||
        el.getAttribute('MasterShape') != null) {
      return false;
    }
    if (s.is1D || _effectiveTextRuns(s).isEmpty) return false;
    if (_hasCell(el, 'TxtPinX')) return false;

    final w = s.width.abs();
    final h = s.height.abs();
    void put(String name, double v, String f) {
      final cell = _ensureCell(el, name);
      cell.setAttribute('V', _fmt(v));
      cell.setAttribute('F', f);
    }

    put('TxtPinX', w / 2, 'Width*0.5');
    put('TxtPinY', h / 2, 'Height*0.5');
    put('TxtWidth', w, 'Width*1');
    put('TxtHeight', h, 'Height*1');
    put('TxtLocPinX', w / 2, 'TxtWidth*0.5');
    put('TxtLocPinY', h / 2, 'TxtHeight*0.5');
    if (!_hasCell(el, 'VerticalAlign')) {
      _writeValue(_ensureCell(el, 'VerticalAlign'), '1');
    }
    // Small margins match Edraw flowchart defaults (~4pt).
    const m = 0.05555555555555555;
    for (final name in const [
      'LeftMargin',
      'RightMargin',
      'TopMargin',
      'BottomMargin',
    ]) {
      if (!_hasCell(el, name)) {
        _writeValue(_ensureCell(el, name), _fmt(m));
      }
    }
    // Our canvas centres plain labels; older exports wrote HorzAlign=0.
    // Align Paragraph when we synthesise the Edraw text box.
    _ensureParagraphHorzAlignCenter(el);
    return true;
  }

  /// Set Paragraph/HorzAlign=1 when missing or left (0).
  bool _ensureParagraphHorzAlignCenter(XmlElement el) {
    XmlElement? para;
    for (final child in el.childElements) {
      if (child.name.local == 'Section' &&
          child.getAttribute('N') == 'Paragraph') {
        para = child;
        break;
      }
    }
    if (para == null) return false;
    XmlElement? row;
    for (final r in para.childElements) {
      if (r.name.local == 'Row') {
        row = r;
        break;
      }
    }
    if (row == null) {
      row = XmlElement(
        XmlName('Row'),
        <XmlAttribute>[XmlAttribute(XmlName('IX'), '0')],
      );
      para.children.add(row);
    }
    final cell = _ensureCell(row, 'HorzAlign');
    final cur = cell.getAttribute('V');
    if (cur == '1') return false;
    cell.setAttribute('V', '1');
    return true;
  }

  bool _ensureTextStyleSections(XmlElement el, VsdxShape s) {
    // Only act when this shape already has a *local* non-empty <Text>. That
    // covers bare Text (older exports), Paragraph-only + <pp> (third-party
    // fixtures), and Master instances that overrode text locally — Edraw
    // needs a sibling Character section or it picks a wrong default size.
    // Shapes that inherit Text purely from a Master keep master Character.
    final runs = _effectiveTextRuns(s);
    if (runs.isEmpty) return false;
    var hasChar = false;
    XmlElement? textEl;
    for (final child in el.childElements) {
      if (child.name.local == 'Section' &&
          child.getAttribute('N') == 'Character') {
        hasChar = true;
      }
      if (child.name.local == 'Text') textEl = child;
    }
    if (hasChar || textEl == null) return false;
    final plain = textEl.innerText;
    if (plain.trim().isEmpty) return false;
    final hasMarker = textEl.childElements
        .any((c) => c.name.local == 'cp' || c.name.local == 'pp');
    _patchTextStyleSections(el, runs);
    if (!hasMarker) {
      // Upgrade bare <Text>hello</Text> to pp/cp so Character rows apply.
      textEl.children.clear();
      for (var i = 0; i < runs.length; i++) {
        textEl.children.add(XmlElement(
          XmlName('pp'),
          <XmlAttribute>[XmlAttribute(XmlName('IX'), i.toString())],
        ));
        textEl.children.add(XmlElement(
          XmlName('cp'),
          <XmlAttribute>[XmlAttribute(XmlName('IX'), i.toString())],
        ));
        _appendRunText(
          textEl.children,
          runs[i].copyWith(text: i == 0 ? plain : runs[i].text),
        );
      }
    }
    return true;
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
    s = s.persistRouteState();
    if (s.hasImage) {
      return _buildPictureElement(s, imageRels, opaqueById: opaqueById);
    }
    // Drop stale THEMEVAL keys left after theme→solid / no-fill edits so a
    // group rebuild cannot resurrect them (patch path already scrubbed).
    final staleTheme = _staleThemeFormulaKeys(s);
    String? formulaOf(String key) =>
        staleTheme.contains(key) ? null : s.formulas[key];
    // --- XForm ---------------------------------------------------------------
    final children = <XmlNode>[
      _cell('PinX', _fmt(s.pinX), formula: s.formulas['PinX']),
      _cell('PinY', _fmt(s.pinY), formula: s.formulas['PinY']),
      _cell('Width', _fmt(s.width), formula: s.formulas['Width']),
      _cell('Height', _fmt(s.height), formula: s.formulas['Height']),
    ];
    // Always emit LocPin. Visio's *formula* default is Width/2, Height/2, but
    // when the cells are absent Edraw / libvisio fall back to (0,0) (= pin at
    // the shape's bottom-left), shifting every centred shape by half its size.
    // Writing the cells (with Width*0.5 / Height*0.5 when centred) keeps
    // exports aligned with how this editor and Visio place the pin.
    final locPinXF = s.formulas['LocPinX'] ??
        ((s.effectiveLocPinX - s.width / 2).abs() <= _epsilon
            ? 'Width*0.5'
            : null);
    final locPinYF = s.formulas['LocPinY'] ??
        ((s.effectiveLocPinY - s.height / 2).abs() <= _epsilon
            ? 'Height*0.5'
            : null);
    children
      ..add(_cell('LocPinX', _fmt(s.effectiveLocPinX), formula: locPinXF))
      ..add(_cell('LocPinY', _fmt(s.effectiveLocPinY), formula: locPinYF));
    children.add(_cell('Angle', _fmt(s.angleRad), formula: s.formulas['Angle']));
    // Always emit Flip* (incl. 0) so Master FlipX cannot revive after clear.
    children
      ..add(_cell('FlipX', s.flipX ? '1' : '0'))
      ..add(_cell('FlipY', s.flipY ? '1' : '0'));
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
          formula: formulaOf('FillForegnd')));
    } else if (s.fill.themeForegroundIndex != null) {
      children.add(_cell('FillForegnd', '0',
          formula: formulaOf('FillForegnd') ?? 'THEMEVAL()'));
      children.add(
          _cell('QuickStyleFillColor', s.fill.themeForegroundIndex!.toString()));
    } else if (formulaOf('FillForegnd') != null) {
      children.add(_cell('FillForegnd', '0', formula: formulaOf('FillForegnd')));
    } else if (s.fill.pattern != 0 && s.children.isEmpty) {
      // VSD import / defaultFill often leave foreground null while pattern=1.
      // Visio resolves via StyleSheets; 万兴图示 treats missing FillForegnd as
      // hollow — emit opaque white (Visio "No Style" default). Skip groups:
      // inventing a fill on a container paints a phantom rectangle after reopen.
      children.add(_cell('FillForegnd', '#FFFFFF'));
    }
    if (s.fill.background != null) {
      children.add(_cell('FillBkgnd', _hex(s.fill.background!),
          formula: formulaOf('FillBkgnd')));
    } else if (s.fill.themeBackgroundIndex != null) {
      final bgSlot = s.fill.themeBackgroundIndex!;
      final fgSlot = s.fill.themeForegroundIndex;
      // When fg and bg use different theme slots they cannot share one
      // QuickStyleFillColor — emit THEMEVAL("AccentColorN") for the bg cell.
      final named = (fgSlot != null && fgSlot != bgSlot)
          ? ThemeSlot.themeValName(bgSlot)
          : null;
      final bgFormula = formulaOf('FillBkgnd') ??
          (named != null ? 'THEMEVAL("$named")' : 'THEMEVAL()');
      children.add(_cell('FillBkgnd', '0', formula: bgFormula));
      // When only the background is theme-bound, emit QuickStyleFillColor so
      // parseFill can recover themeBackgroundIndex (libvisio / Visio).
      if (fgSlot == null) {
        children.add(
            _cell('QuickStyleFillColor', bgSlot.toString()));
      }
    } else if (formulaOf('FillBkgnd') != null) {
      children.add(_cell('FillBkgnd', '0', formula: formulaOf('FillBkgnd')));
    }
    // FillBkgnd default comes from document StyleSheets (No Style) when omitted.
    children.add(_cell('FillPattern', s.fill.pattern.toString(),
        formula: formulaOf('FillPattern')));
    // Always emit Trans (incl. 0) so Master transparency cannot revive after
    // clear + group rebuild (patch already force-writes these).
    children
      ..add(_cell('FillForegndTrans', _fmt(s.fill.foregroundTransparency)))
      ..add(_cell('FillBkgndTrans', _fmt(s.fill.backgroundTransparency)));
    // --- Line ----------------------------------------------------------------
    if (s.line.color != null) {
      children.add(_cell('LineColor', _hex(s.line.color!),
          formula: formulaOf('LineColor')));
    } else if (s.line.themeColorIndex != null) {
      children.add(_cell('LineColor', '0',
          formula: formulaOf('LineColor') ?? 'THEMEVAL()'));
      children
          .add(_cell('QuickStyleLineColor', s.line.themeColorIndex!.toString()));
    } else if (formulaOf('LineColor') != null) {
      children.add(_cell('LineColor', '0', formula: formulaOf('LineColor')));
    }
    children
      ..add(_cell('LineWeight', _fmt(s.line.weightInches)))
      ..add(_cell('LinePattern', s.line.pattern.toString(),
          formula: formulaOf('LinePattern')))
      // Always emit LineCap (Visio/Edraw "No Style" default is 0 = round).
      ..add(_cell('LineCap', _lineCapInt(s.line.cap).toString()))
      ..add(_cell('LineColorTrans', _fmt(s.line.transparency)));
    // Always emit arrows (incl. 0) so StyleSheet cannot revive arrowheads
    // after the user cleared them on a rebuild path (patch already forces 0).
    children
      ..add(_cell('BeginArrow', s.line.beginArrow.toString()))
      ..add(_cell(
          'BeginArrowSize',
          _arrowSizeToBucket(s.line.beginArrowSizeInches).toString()))
      ..add(_cell('EndArrow', s.line.endArrow.toString()))
      ..add(_cell(
          'EndArrowSize',
          _arrowSizeToBucket(s.line.endArrowSizeInches).toString()));
    // Always emit SoftEdges/Rounding (incl. 0) so StyleSheet cannot revive
    // feathering after a group rebuild cleared the effect in the model.
    children
      ..add(_cell('Rounding', _fmt(s.line.roundingInches)))
      ..add(_cell('SoftEdgesSize', _fmt(s.line.softEdgesInches)))
      // Always emit CompoundType (incl. 0) so StyleSheet inheritance cannot
      // revive double-line after the user cleared compound on a rebuild path.
      ..add(_cell('CompoundType', s.line.compoundType.toString()));
    if (s.layerMemberIds.isNotEmpty) {
      children.add(_cell('LayerMember', s.layerMemberIds.join(';')));
    }
    // --- Effects / text block ------------------------------------------------
    if (s.shadow.enabled) {
      children.add(_cell('ShadowPattern', '1'));
      children.add(_cell('ShdwPattern', '1'));
      if (s.shadow.color != null) {
        children.add(_cell('ShadowForegnd', _hex(s.shadow.color!)));
      } else if (s.shadow.themeColorIndex != null) {
        // Match Fill/Line theme binding: THEMEVAL() + QuickStyle slot.
        children.add(_cell('ShadowForegnd', '0', formula: 'THEMEVAL()'));
        children.add(_cell(
            'QuickStyleShadowColor', s.shadow.themeColorIndex!.toString()));
      }
      children
        ..add(_cell('ShadowOffsetX', _fmt(s.shadow.offsetXInches)))
        ..add(_cell('ShadowOffsetY', _fmt(s.shadow.offsetYInches)))
        ..add(_cell('ShadowBlur', _fmt(s.shadow.blurInches)))
        ..add(_cell('ShadowForegndTrans', _fmt(s.shadow.transparency)));
    } else {
      // Edraw StyleSheet defaults can leave a residual shadow unless the shape
      // explicitly disables it. Emit both aliases (patch path already does).
      children.add(_cell('ShadowPattern', '0'));
      children.add(_cell('ShdwPattern', '0'));
    }
    if (s.glow.enabled) {
      children.add(_cell('GlowSize', _fmt(s.glow.sizeInches)));
      if (s.glow.color != null) {
        children.add(_cell('GlowColor', _hex(s.glow.color!)));
      } else if (s.glow.themeColorIndex != null) {
        children.add(_cell('GlowColor', '0', formula: 'THEMEVAL()'));
        children.add(_cell(
            'QuickStyleEffectColor', s.glow.themeColorIndex!.toString()));
      }
      children.add(_cell('GlowColorTrans', _fmt(s.glow.transparency)));
    } else {
      children.add(_cell('GlowSize', '0'));
    }
    if (s.reflection.enabled) {
      children
        ..add(_cell('ReflectionSize', _fmt(s.reflection.sizeInches)))
        ..add(_cell('ReflectionDist', _fmt(s.reflection.distanceInches)))
        ..add(_cell(
            'ReflectionTransparency', _fmt(s.reflection.transparency)))
        ..add(_cell('ReflectionBlur', _fmt(s.reflection.blurInches)));
    } else {
      children.add(_cell('ReflectionSize', '0'));
    }
    if (s.fill.gradient != null && s.fill.gradient!.stops.isNotEmpty) {
      children
        ..add(_cell('FillGradientEnabled', '1'))
        ..add(_cell('FillGradientDir',
            _gradientDirFromType(s.fill.gradient!.type).toString()))
        ..add(_cell('FillGradientAngle', _fmt(s.fill.gradient!.angleRad)));
    } else {
      children.add(_cell('FillGradientEnabled', '0'));
    }
    if (s.line.gradient != null && s.line.gradient!.stops.isNotEmpty) {
      children
        ..add(_cell('LineGradientEnabled', '1'))
        ..add(_cell('LineGradientDir',
            _gradientDirFromType(s.line.gradient!.type).toString()))
        ..add(_cell('LineGradientAngle', _fmt(s.line.gradient!.angleRad)));
    } else {
      children.add(_cell('LineGradientEnabled', '0'));
    }
    // Character / Paragraph — one row per rich-text run (matches <cp>/<pp>).
    // Computed early so text-block defaults know whether a label is present.
    final textRuns = _effectiveTextRuns(s);
    _appendTextBlockCells(
      children,
      s.richText.textBlock,
      formulas: s.formulas,
      shapeForDefaults: s,
      hasLabel: textRuns.isNotEmpty,
    );
    // Visio / Edraw treat ObjType=2 as a connector (glue, routing, line ends).
    // Brand-new 1-D shapes from our factory leave objType null — emit the
    // connector value so other apps recognise the edge.
    final objType = s.objType ?? (s.is1D ? 2 : null);
    if (objType != null) {
      children.add(_cell('ObjType', objType.toString()));
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
    } else {
      // Always emit LockMoveX=0 so Master LockMoveX cannot revive after unlock
      // + group rebuild (other Lock* stay opaque for fine-grained Visio locks).
      children.add(_cell('LockMoveX', '0'));
    }
    // --- Sections ------------------------------------------------------------
    // Plain `.text` without runs is synthesised so Edraw gets an explicit Size
    // matching this editor's proportional label (not a missing-style default).
    if (textRuns.isNotEmpty) {
      children
        ..add(_buildCharacterSection(textRuns))
        ..add(_buildParagraphSection(textRuns));
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
    // Emit edge glue points so 万兴图示 attaches connectors at mid-sides
    // (missing Connection → Edraw falls back to Pin/odd corners).
    final cps = s.connectionPoints.isNotEmpty
        ? s.connectionPoints
        : (!s.is1D
            ? VsdxPage.defaultConnectionPoints(s.width, s.height)
            : const <VsdxConnectionPoint>[]);
    if (cps.isNotEmpty) {
      children.add(_buildConnectionSection(cps));
    }
    // Unmodelled cells / sections from the prior XML (group rebuild).
    _appendOpaqueChildren(children, s, opaqueById);
    // --- Text ----------------------------------------------------------------
    // Always emit <pp>/<cp> markers (Edraw / Visio do even for a single run).
    if (textRuns.isNotEmpty) {
      final textEl = XmlElement(XmlName('Text'));
      for (var i = 0; i < textRuns.length; i++) {
        textEl.children.add(XmlElement(
          XmlName('pp'),
          <XmlAttribute>[XmlAttribute(XmlName('IX'), i.toString())],
        ));
        textEl.children.add(XmlElement(
          XmlName('cp'),
          <XmlAttribute>[XmlAttribute(XmlName('IX'), i.toString())],
        ));
        _appendRunText(textEl.children, textRuns[i]);
      }
      if (textEl.children.isNotEmpty) children.add(textEl);
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
          _charCells(runs[i].charStyle, text: runs[i].text),
        ),
    ];
    return XmlElement(
      XmlName('Section'),
      <XmlAttribute>[XmlAttribute(XmlName('N'), 'Character')],
      rows,
    );
  }

  List<XmlNode> _charCells(VsdxCharStyle c, {String text = ''}) {
    final cjk = _containsCjk(text);
    final cells = <XmlNode>[
      _cell('Size', _fmt(c.fontSizeInches)),
      _cell('Style', _charStyleBits(c).toString()),
    ];
    // Only emit Color when the model set one. Forcing #000000 on null made
    // editor-created labels (color: null) drift to black after save→reopen.
    // Edraw / Visio still resolve black via DefaultTextStyle / StyleSheets.
    if (c.color != null) {
      cells.add(_cell('Color', _hex(c.color!)));
    } else if (c.themeColorIndex != null) {
      // Match [_writeCharRow]: cache the theme slot in V so accent survives
      // fresh emit → reopen (parser reads V when F=THEMEVAL()).
      cells.add(_cell(
        'Color',
        c.themeColorIndex!.toString(),
        formula: 'THEMEVAL()',
      ));
    }
    // AsianFont (+ ComplexScriptFont) required for CJK in 万兴图示; Font
    // only when set or CJK. Match Edraw's 人才招聘 Character row shape.
    final asian = (c.asianFont != null && c.asianFont!.isNotEmpty)
        ? c.asianFont!
        : _defaultAsianFont;
    if (c.fontFamily != null && c.fontFamily!.isNotEmpty) {
      cells.add(_cell('Font', c.fontFamily!));
    } else if (cjk) {
      cells.add(_cell('Font', _defaultAsianFont));
    }
    cells.add(_cell('AsianFont', asian));
    if (cjk ||
        (c.complexScriptFont != null && c.complexScriptFont!.isNotEmpty)) {
      cells.add(_cell(
        'ComplexScriptFont',
        (c.complexScriptFont != null && c.complexScriptFont!.isNotEmpty)
            ? c.complexScriptFont!
            : asian,
      ));
    }
    // Always emit clearable style flags (incl. 0) so StyleSheet/Master cannot
    // revive after group rebuild. Keep FontScale omit-when-default for CJK.
    cells
      ..add(_cell('Strikethru', c.strikethrough ? '1' : '0'))
      ..add(_cell('DblUnderline', c.doubleUnderline ? '1' : '0'))
      ..add(_cell('DoubleStrikethrough', c.doubleStrikethrough ? '1' : '0'))
      ..add(_cell('Overline', c.overline ? '1' : '0'))
      ..add(_cell('Letterspace', _fmt(c.letterSpacingInches)))
      ..add(_cell('Pos', _textPositionInt(c.position).toString()))
      ..add(_cell('Case', _textCaseInt(c.textCase).toString()))
      ..add(_cell('ColorTrans', _fmt(c.transparency)));
    if ((c.fontScale - 1.0).abs() > _epsilon) {
      cells.add(_cell('FontScale', _fmt(c.fontScale)));
    }
    final lang = c.langId ?? (cjk ? 'zh-CN' : null);
    if (lang != null && lang.isNotEmpty) {
      cells.add(_cell('LangID', lang));
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
    // Always emit Bullet (incl. 0) so cleared bullets cannot revive via Master.
    cells.add(_cell('Bullet', p.bullet.toString()));
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

  /// Append opaque nodes for [s]. When locked, skip Lock* (builder emits them).
  void _appendOpaqueChildren(
    List<XmlNode> children,
    VsdxShape s,
    Map<int, List<XmlNode>> opaqueById,
  ) {
    final opaque = opaqueById[s.id];
    if (opaque == null || opaque.isEmpty) return;
    for (final n in opaque) {
      if (s.locked && n is XmlElement && n.name.local == 'Cell') {
        final name = n.getAttribute('N');
        if (name != null && name.startsWith('Lock')) continue;
      }
      children.add(n.copy());
    }
  }

  /// Cells that `_buildShapeElement` may emit (everything else is opaque).
  ///
  /// Fine-grained Lock* (except LockMoveX ↔ [VsdxShape.locked]) stay opaque so
  /// Visio-only protections (LockTextEdit / LockFormat / …) survive grouping.
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
    'ShadowPattern', 'ShdwPattern', 'ShadowForegnd', 'QuickStyleShadowColor',
    'ShadowOffsetX', 'ShadowOffsetY', 'ShadowBlur', 'ShadowForegndTrans',
    'GlowSize', 'GlowColor', 'QuickStyleEffectColor', 'GlowColorTrans',
    'ReflectionSize', 'ReflectionDist', 'ReflectionTransparency',
    'ReflectionBlur',
    'TxtPinX', 'TxtPinY', 'TxtWidth', 'TxtHeight', 'TxtLocPinX', 'TxtLocPinY',
    'TxtAngle', 'VerticalAlign', 'LeftMargin', 'RightMargin', 'TopMargin',
    'BottomMargin', 'HideText', 'TextBkgnd', 'TextBkgndTrans', 'TextDirection',
    'DefaultTabStop',
    // Only LockMoveX is modeled (↔ locked). Other Lock* survive via opaque.
    'LockMoveX',
    'ObjType', 'ResizeMode', 'EventDblClick', 'NoAlignBox', 'ShapeSplittable',
    'ThemeIndex', 'QuickStyleFillMatrix', 'QuickStyleLineMatrix',
    'QuickStyleEffectsMatrix', 'QuickStyleFontMatrix',
    'IsTextEditTarget', 'DontMoveChildren', 'SelectMode', 'DisplayMode',
    // Foreign / Image cells — builder owns these; keep out of opaque so
    // cleared tone / crop cannot resurrect on group rebuild.
    'ImgOffsetX', 'ImgOffsetY', 'ImgWidth', 'ImgHeight',
    'Transparency', 'Blur', 'Brightness', 'Contrast',
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
  XmlElement _buildPictureElement(
    VsdxShape s,
    Map<String, String> imageRels, {
    Map<int, List<XmlNode>> opaqueById = const <int, List<XmlNode>>{},
  }) {
    final part = s.imagePartName;
    final rId = part == null
        ? null
        : (imageRels[part] ??
            imageRels[_noSlash(part)] ??
            imageRels['/${_noSlash(part)}']);
    final foreignType = s.foreignType ??
        VsdxImage.foreignTypeFor(
          mimeType: '',
          partName: part ?? '',
        );
    final compression = s.foreignCompressionType ??
        (foreignType == 'Bitmap'
            ? VsdxImage.compressionTypeFor(
                mimeType: '',
                partName: part ?? '',
              )
            : null);
    final children = <XmlNode>[
      _cell('PinX', _fmt(s.pinX), formula: s.formulas['PinX']),
      _cell('PinY', _fmt(s.pinY), formula: s.formulas['PinY']),
      _cell('Width', _fmt(s.width), formula: s.formulas['Width']),
      _cell('Height', _fmt(s.height), formula: s.formulas['Height']),
      _cell(
        'LocPinX',
        _fmt(s.effectiveLocPinX),
        formula: s.formulas['LocPinX'] ??
            ((s.effectiveLocPinX - s.width / 2).abs() <= _epsilon
                ? 'Width*0.5'
                : null),
      ),
      _cell(
        'LocPinY',
        _fmt(s.effectiveLocPinY),
        formula: s.formulas['LocPinY'] ??
            ((s.effectiveLocPinY - s.height / 2).abs() <= _epsilon
                ? 'Height*0.5'
                : null),
      ),
      _cell('Angle', _fmt(s.angleRad), formula: s.formulas['Angle']),
      // MS-VSDX §2.2.6 Image — Edraw / Visio use these to place the bitmap
      // inside the Foreign shape. Without them many hosts show an empty box.
      _cell('ImgOffsetX', _fmt(s.imgOffsetXInches),
          formula: s.formulas['ImgOffsetX']),
      _cell('ImgOffsetY', _fmt(s.imgOffsetYInches),
          formula: s.formulas['ImgOffsetY']),
      _cell(
        'ImgWidth',
        _fmt(s.effectiveImgWidth),
        formula: s.formulas['ImgWidth'] ??
            (s.imgWidthInches == null ||
                    (s.imgWidthInches! - s.width).abs() <= _epsilon
                ? 'Width*1'
                : null),
      ),
      _cell(
        'ImgHeight',
        _fmt(s.effectiveImgHeight),
        formula: s.formulas['ImgHeight'] ??
            (s.imgHeightInches == null ||
                    (s.imgHeightInches! - s.height).abs() <= _epsilon
                ? 'Height*1'
                : null),
      ),
      if (s.imageTransparency > _epsilon)
        _cell('Transparency', _fmt(s.imageTransparency)),
      if (s.imageBlur > _epsilon) _cell('Blur', _fmt(s.imageBlur)),
      if ((s.imageBrightness - 0.5).abs() > _epsilon)
        _cell('Brightness', _fmt(s.imageBrightness)),
      if ((s.imageContrast - 0.5).abs() > _epsilon)
        _cell('Contrast', _fmt(s.imageContrast)),
      // Pictures are typically fill-less / stroke-less; emit the zero patterns
      // explicitly so reopen doesn't fall back to Visio's solid defaults.
      _cell('FillPattern', s.fill.pattern.toString()),
      if (s.fill.foreground != null)
        _cell('FillForegnd', _hex(s.fill.foreground!))
      else if (s.fill.themeForegroundIndex != null) ...[
        _cell('FillForegnd', '0', formula: 'THEMEVAL()'),
        _cell('QuickStyleFillColor', s.fill.themeForegroundIndex!.toString()),
      ],
      if (s.fill.background != null)
        _cell('FillBkgnd', _hex(s.fill.background!))
      else if (s.fill.themeBackgroundIndex != null) ...[
        _cell('FillBkgnd', '0', formula: 'THEMEVAL()'),
        if (s.fill.themeForegroundIndex == null)
          _cell('QuickStyleFillColor', s.fill.themeBackgroundIndex!.toString()),
      ],
      _cell('FillForegndTrans', _fmt(s.fill.foregroundTransparency)),
      _cell('FillBkgndTrans', _fmt(s.fill.backgroundTransparency)),
      _cell('LinePattern', s.line.pattern.toString()),
      _cell('LineWeight', _fmt(s.line.weightInches)),
      _cell('LineCap', _lineCapInt(s.line.cap).toString()),
      if (s.line.color != null)
        _cell('LineColor', _hex(s.line.color!))
      else if (s.line.themeColorIndex != null) ...[
        _cell('LineColor', '0', formula: 'THEMEVAL()'),
        _cell('QuickStyleLineColor', s.line.themeColorIndex!.toString()),
      ],
      _cell('LineColorTrans', _fmt(s.line.transparency)),
      // Always emit arrows (incl. 0) — modeled cells, opaque cannot preserve.
      _cell('BeginArrow', s.line.beginArrow.toString()),
      _cell(
          'BeginArrowSize',
          _arrowSizeToBucket(s.line.beginArrowSizeInches).toString()),
      _cell('EndArrow', s.line.endArrow.toString()),
      _cell(
          'EndArrowSize',
          _arrowSizeToBucket(s.line.endArrowSizeInches).toString()),
      // SoftEdges / Rounding / CompoundType — always emit (incl. 0) so
      // StyleSheet inheritance cannot revive effects after Foreign rebuild.
      _cell('SoftEdgesSize', _fmt(s.line.softEdgesInches)),
      _cell('Rounding', _fmt(s.line.roundingInches)),
      _cell('CompoundType', s.line.compoundType.toString()),
      if (s.layerMemberIds.isNotEmpty)
        _cell('LayerMember', s.layerMemberIds.join(';')),
      _cell('FlipX', s.flipX ? '1' : '0'),
      _cell('FlipY', s.flipY ? '1' : '0'),
    ];
    if (s.shadow.enabled) {
      children.add(_cell('ShadowPattern', '1'));
      children.add(_cell('ShdwPattern', '1'));
      if (s.shadow.color != null) {
        children.add(_cell('ShadowForegnd', _hex(s.shadow.color!)));
      } else if (s.shadow.themeColorIndex != null) {
        children.add(_cell('ShadowForegnd', '0', formula: 'THEMEVAL()'));
        children.add(_cell(
            'QuickStyleShadowColor', s.shadow.themeColorIndex!.toString()));
      }
      children
        ..add(_cell('ShadowOffsetX', _fmt(s.shadow.offsetXInches)))
        ..add(_cell('ShadowOffsetY', _fmt(s.shadow.offsetYInches)))
        ..add(_cell('ShadowBlur', _fmt(s.shadow.blurInches)))
        ..add(_cell('ShadowForegndTrans', _fmt(s.shadow.transparency)));
    } else {
      children.add(_cell('ShadowPattern', '0'));
      children.add(_cell('ShdwPattern', '0'));
    }
    if (s.glow.enabled) {
      children.add(_cell('GlowSize', _fmt(s.glow.sizeInches)));
      if (s.glow.color != null) {
        children.add(_cell('GlowColor', _hex(s.glow.color!)));
      } else if (s.glow.themeColorIndex != null) {
        children.add(_cell('GlowColor', '0', formula: 'THEMEVAL()'));
        children.add(_cell(
            'QuickStyleEffectColor', s.glow.themeColorIndex!.toString()));
      }
      children.add(_cell('GlowColorTrans', _fmt(s.glow.transparency)));
    } else {
      children.add(_cell('GlowSize', '0'));
    }
    if (s.reflection.enabled) {
      children
        ..add(_cell('ReflectionSize', _fmt(s.reflection.sizeInches)))
        ..add(_cell('ReflectionDist', _fmt(s.reflection.distanceInches)))
        ..add(_cell(
            'ReflectionTransparency', _fmt(s.reflection.transparency)))
        ..add(_cell('ReflectionBlur', _fmt(s.reflection.blurInches)));
    } else {
      children.add(_cell('ReflectionSize', '0'));
    }
    // Match Shape rebuild: always emit gradient enable flags (incl. 0).
    if (s.fill.gradient != null && s.fill.gradient!.stops.isNotEmpty) {
      children
        ..add(_cell('FillGradientEnabled', '1'))
        ..add(_cell('FillGradientDir',
            _gradientDirFromType(s.fill.gradient!.type).toString()))
        ..add(_cell('FillGradientAngle', _fmt(s.fill.gradient!.angleRad)));
    } else {
      children.add(_cell('FillGradientEnabled', '0'));
    }
    if (s.line.gradient != null && s.line.gradient!.stops.isNotEmpty) {
      children
        ..add(_cell('LineGradientEnabled', '1'))
        ..add(_cell('LineGradientDir',
            _gradientDirFromType(s.line.gradient!.type).toString()))
        ..add(_cell('LineGradientAngle', _fmt(s.line.gradient!.angleRad)));
    } else {
      children.add(_cell('LineGradientEnabled', '0'));
    }
    if (s.locked) {
      for (final name in _lockCells) {
        children.add(_cell(name, '1'));
      }
    } else {
      children.add(_cell('LockMoveX', '0'));
    }
    // Meta cells — match normal shapes so ThemeIndex / EventDblClick / ObjType
    // survive a Foreign group rebuild (they are modeled, not opaque).
    final picObjType = s.objType;
    if (picObjType != null) {
      children.add(_cell('ObjType', picObjType.toString()));
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
    // Caption + text-block (Txt*/VerticalAlign) — match normal shapes so
    // Edraw places Foreign captions correctly after a group rebuild.
    final pictureRuns = _effectiveTextRuns(s);
    _appendTextBlockCells(
      children,
      s.richText.textBlock,
      formulas: s.formulas,
      shapeForDefaults: s,
      hasLabel: pictureRuns.isNotEmpty,
    );
    if (pictureRuns.isNotEmpty) {
      children
        ..add(_buildCharacterSection(pictureRuns))
        ..add(_buildParagraphSection(pictureRuns));
      if (s.richText.tabSets.isNotEmpty) {
        children.add(_buildTabsSection(s.richText.tabSets));
      }
      if (s.fill.gradient != null && s.fill.gradient!.stops.isNotEmpty) {
        children.add(_buildFillGradientSection(s.fill.gradient!));
      }
      if (s.line.gradient != null && s.line.gradient!.stops.isNotEmpty) {
        children.add(_buildLineGradientSection(s.line.gradient!));
      }
      final textEl = XmlElement(XmlName('Text'));
      for (var i = 0; i < pictureRuns.length; i++) {
        textEl.children.add(XmlElement(
          XmlName('pp'),
          <XmlAttribute>[XmlAttribute(XmlName('IX'), i.toString())],
        ));
        textEl.children.add(XmlElement(
          XmlName('cp'),
          <XmlAttribute>[XmlAttribute(XmlName('IX'), i.toString())],
        ));
        _appendRunText(textEl.children, pictureRuns[i]);
      }
      children.add(textEl);
    } else {
      if (s.richText.tabSets.isNotEmpty) {
        children.add(_buildTabsSection(s.richText.tabSets));
      }
      if (s.fill.gradient != null && s.fill.gradient!.stops.isNotEmpty) {
        children.add(_buildFillGradientSection(s.fill.gradient!));
      }
      if (s.line.gradient != null && s.line.gradient!.stops.isNotEmpty) {
        children.add(_buildLineGradientSection(s.line.gradient!));
      }
    }
    // Emit frame Geometry (required by Edraw/Visio for Foreign hit-testing).
    // Fall back to a Width×Height rectangle when the model has none.
    var gIx = 0;
    var emittedGeom = false;
    for (final g in s.geometries) {
      if (!_canRebuild(g)) continue;
      final section = _buildGeometrySection(g, gIx++);
      if (section != null) {
        children.add(section);
        emittedGeom = true;
      }
    }
    if (!emittedGeom) {
      final frame = VsdxGeometry(
        noFill: true,
        noLine: true,
        commands: <VsdxPathCommand>[
          const MoveTo(0, 0),
          LineTo(s.width, 0),
          LineTo(s.width, s.height),
          LineTo(0, s.height),
          const LineTo(0, 0),
        ],
      );
      final section = _buildGeometrySection(frame, 0);
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
    // Edge glue points — match normal shapes so connectors can attach after
    // a Foreign group rebuild (Connection is modeled, not opaque-preserved).
    final cps = s.connectionPoints.isNotEmpty
        ? s.connectionPoints
        : VsdxPage.defaultConnectionPoints(s.width, s.height);
    if (cps.isNotEmpty) {
      children.add(_buildConnectionSection(cps));
    }
    if (s.hyperlinks.isNotEmpty) {
      children.add(_buildHyperlinkSection(s.hyperlinks));
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
    // Unmodelled cells / sections from the prior XML (group rebuild).
    _appendOpaqueChildren(children, s, opaqueById);
    return XmlElement(
      XmlName('Shape'),
      <XmlAttribute>[
        XmlAttribute(XmlName('ID'), s.id.toString()),
        XmlAttribute(XmlName('NameU'), s.name),
        XmlAttribute(XmlName('Name'), s.name),
        XmlAttribute(XmlName('Type'), 'Foreign'),
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

  /// Hex colour, or theme slot with `THEMEVAL()` (matches Character Color).
  List<XmlNode> _gradientStopColorCells(VsdxGradientStop stop) {
    if (stop.color != null) {
      return [_cell('GradientStopColor', _hex(stop.color!))];
    }
    if (stop.themeColorIndex != null) {
      return [
        _cell(
          'GradientStopColor',
          stop.themeColorIndex.toString(),
          formula: 'THEMEVAL()',
        ),
      ];
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
    // Always emit NoFill/NoLine/NoShow/NoSnap/NoQuickDrag. Visio defaults
    // missing NoFill to 0 (filled), but 万兴图示 treats a missing cell as
    // NoFill=1 → hollow shapes; the other three flags follow the same pattern
    // in Edraw samples (always written as 0 when inactive).
    rows.add(_cell('NoFill', g.noFill ? '1' : '0'));
    rows.add(_cell('NoLine', g.noLine ? '1' : '0'));
    rows.add(_cell('NoShow', g.noShow ? '1' : '0'));
    rows.add(_cell('NoSnap', g.noSnap ? '1' : '0'));
    rows.add(_cell('NoQuickDrag', g.noQuickDrag ? '1' : '0'));
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
      case PolylineTo(
          :final x,
          :final y,
          :final vertices,
          :final relative,
          :final vertsRelative,
          :final vertsYRelative,
        ):
        // POLYLINE(xType,yType,…): 0 = % of Width/Height, 1 = local inches.
        // Rel* only affects the endpoint; formula flags are independent.
        final xt = vertsRelative ? 0 : 1;
        final yt = vertsYRelative ? 0 : 1;
        final buf = StringBuffer('POLYLINE($xt,$yt');
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
          :final cpRelative,
          :final cpYRelative,
        ):
        return _rowFormula(relative ? 'RelNURBSTo' : 'NURBSTo', ix, {
          'X': _fmt(x),
          'Y': _fmt(y),
          'A': _fmt(knots.length >= 2 ? knots[knots.length - 2] : 0.0),
          'B': _fmt(weights.isNotEmpty ? weights.last : 1.0),
          'C': _fmt(knots.isNotEmpty ? knots.first : 0.0),
          'D': _fmt(weights.isNotEmpty ? weights.first : 1.0),
          'E': _nurbsEFormula(
            controlPoints: controlPoints,
            weights: weights,
            knots: knots,
            degree: degree,
            xType: cpRelative ? 0 : 1,
            yType: cpYRelative ? 0 : 1,
          ),
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

  static String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

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
