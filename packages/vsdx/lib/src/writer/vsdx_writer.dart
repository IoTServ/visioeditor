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
import '../model/custom_property.dart';
import '../model/document.dart';
import '../model/document_settings.dart';
import '../model/drawing_scale.dart';
import '../model/effects.dart';
import '../model/fill.dart';
import '../model/geometry.dart';
import '../model/hyperlink.dart';
import '../model/image.dart';
import '../model/layer.dart';
import '../model/line.dart';
import '../model/master.dart';
import '../model/page.dart';
import '../model/rich_text.dart';
import '../model/shape.dart';
import '../model/sheet_sections.dart';
import '../model/theme.dart';
import '../model/user_property.dart';
import '../parser/cell_helpers.dart' show isInhFormula;
import '../parser/document_parser.dart';
import '../parser/package_reader.dart';
import '../parser/relationships.dart';
import '../utils/color.dart';

class VsdxWriter {
  const VsdxWriter({
    this.preserveTextBlockCoordinates = false,
    this.preserveUnchangedPackage = false,
  });

  /// Keep negative `TxtPinY` values semantically faithful instead of
  /// converting them to the equivalent EdrawMax-compatible representation.
  ///
  /// Normal editor saves retain the compatibility rewrite. VSD import
  /// synthesis enables this because its fresh VSDX is the only round-trip
  /// carrier for binary text-block coordinates and must not discard gaps
  /// below captions.
  final bool preserveTextBlockCoordinates;

  /// Return the original package byte-for-byte when its parsed editable model
  /// has not changed. Editor saves enable this to preserve sparse inheritance,
  /// unknown recovery structures, and exact libvisio rendering. It remains
  /// opt-in for migration/repair callers that intentionally normalise legacy
  /// packages by parsing and saving without a user edit.
  final bool preserveUnchangedPackage;

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
    // A true no-op save must be byte-preserving.  Apart from avoiding ZIP/XML
    // churn, this keeps sparse master inheritance and recovery-only packages
    // (for example libvisio's recursion-cycle corpus) render-equivalent.
    if (preserveUnchangedPackage &&
        _documentPatchInputsEqual(baseline, edited)) {
      return Uint8List.fromList(originalBytes);
    }
    final pkg = VsdxPackage.open(originalBytes);
    final resolver = RelationshipResolver(pkg);
    final patched = <String, Uint8List>{}; // archive name (no slash) -> bytes
    final removed = <String>{};

    final docPart = pkg.resolveDocumentPartName();
    // Back-fill minimal StyleSheets / FaceNames on legacy blank exports so
    // Edraw can resolve Default*Style (otherwise fills/text look wrong).
    // Also patch DocumentSettings cells (PageColor / Glue / Snap / grid).
    final docXml = pkg.readPartXml(docPart);
    if (docXml != null) {
      var docDirty = false;
      if (_ensureDocumentStyles(docXml)) docDirty = true;
      if (_patchDocumentSettings(
          docXml, baseline.settings, edited.settings)) {
        docDirty = true;
      }
      if (docDirty) {
        patched[_noSlash(docPart)] =
            Uint8List.fromList(utf8.encode(docXml.toXmlString()));
      }
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
      if (_patchPage(
        xml,
        visioSourceScalePage(bp),
        visioSourceScalePage(ep),
        imageRels: imageRels,
      )) {
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
      final sourceBp = visioSourceScalePage(bp);
      final sourceEp = visioSourceScalePage(ep);
      if (bp.name != ep.name) {
        el.setAttribute('NameU', ep.name);
        if (el.getAttribute('Name') != null) el.setAttribute('Name', ep.name);
        pagesDirty = true;
      }
      if (_patchLayerRows(el, bp, ep)) pagesDirty = true;
      if (_patchPageProperties(el, sourceBp, sourceEp)) pagesDirty = true;
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
      final sourceEp = visioSourceScalePage(ep);
      final fileName = 'page$nextNum.xml';
      final partName = 'visio/pages/$fileName';
      nextNum++;
      final rId = 'rId$nextRId';
      nextRId++;
      root.children.add(_buildPageIndexElement(sourceEp, rId));
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
        utf8.encode(
          _buildPageContentsXml(sourceEp, imageRels: imageRels),
        ),
      );
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
      for (final shape in m.additionalPrototypes) {
        walk(shape);
      }
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
    String core(String tag, String? value) => value == null || value.isEmpty
        ? ''
        : '<$tag>${_xmlEscape(value)}</$tag>';
    String date(String tag, String? value) => value == null || value.isEmpty
        ? ''
        : '<dcterms:$tag xsi:type="dcterms:W3CDTF">'
            '${_xmlEscape(value)}</dcterms:$tag>';
    patched[coreName] = Uint8List.fromList(utf8.encode(
      '$decl\n'
      '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      '$titleXml'
      '<dc:creator>$creatorXml</dc:creator>'
      '${core('dc:subject', edited.subject)}'
      '${core('cp:keywords', edited.keywords)}'
      '${core('dc:description', edited.description)}'
      '${core('cp:lastModifiedBy', edited.lastModifiedBy)}'
      '${date('created', edited.created)}'
      '${date('modified', edited.modified)}'
      '${core('dc:language', edited.language)}'
      '${core('cp:category', edited.category)}'
      '</cp:coreProperties>',
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
      // Value-unchanged still scrubs residual F=Inh (same as PageWidth).
      bool sync(String name, String want, bool modelChanged) {
        if (modelChanged) {
          _writeValue(_ensureCell(row, name), want);
          return true;
        }
        final cell = _findCell(row, name);
        if (cell == null) return false;
        final f = cell.getAttribute('F');
        if (cell.getAttribute('V') == want && (f == null || f.isEmpty)) {
          return false;
        }
        _writeValue(cell, want);
        return true;
      }

      changed |= sync('Name', layer.name, layer.name != base.name);
      changed |= sync(
          'Visible', layer.visible ? '1' : '0', layer.visible != base.visible);
      changed |=
          sync('Lock', layer.locked ? '1' : '0', layer.locked != base.locked);
      changed |=
          sync('Print', layer.print ? '1' : '0', layer.print != base.print);
      changed |=
          sync('Active', layer.active ? '1' : '0', layer.active != base.active);
      changed |= sync('Snap', layer.snap ? '1' : '0', layer.snap != base.snap);
      changed |= sync('Glue', layer.glue ? '1' : '0', layer.glue != base.glue);
      if (layer.color?.value != base.color?.value) {
        if (layer.color != null) {
          _writeValue(_ensureCell(row, 'Color'), _hex(layer.color!));
        } else {
          _removeNamedCells(row, const ['Color']);
        }
        changed = true;
      } else if (layer.color != null) {
        changed |= sync('Color', _hex(layer.color!), false);
      } else {
        // Model has no colour — still scrub residual F=Inh or drop the cell.
        final colorCell = _findCell(row, 'Color');
        if (colorCell != null &&
            isInhFormula(colorCell.getAttribute('F'))) {
          _removeNamedCells(row, const ['Color']);
          changed = true;
        }
      }
      if (layer.nameUniv != base.nameUniv) {
        if (layer.nameUniv != null) {
          _writeValue(_ensureCell(row, 'NameUniv'), layer.nameUniv!);
        } else {
          _removeNamedCells(row, const ['NameUniv']);
        }
        changed = true;
      } else if (layer.nameUniv != null) {
        changed |= sync('NameUniv', layer.nameUniv!, false);
      } else {
        // Model has no NameUniv — still scrub residual F=Inh (same as Color).
        final univCell = _findCell(row, 'NameUniv');
        if (univCell != null &&
            isInhFormula(univCell.getAttribute('F'))) {
          _removeNamedCells(row, const ['NameUniv']);
          changed = true;
        }
      }
      changed |= sync(
        'ColorTrans',
        _fmt(layer.colorTrans),
        (layer.colorTrans - base.colorTrans).abs() > _epsilon,
      );
      changed |= sync(
          'Status', layer.status.toString(), layer.status != base.status);
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
    final sheetEl = _firstChild(pageEl, 'PageSheet');
    final hasInh = sheetEl != null && _pageSheetHasInh(sheetEl);
    if (!needWidth &&
        !needHeight &&
        !needColor &&
        !needSheet &&
        !needView &&
        !needBackgroundFlag &&
        !needBackPage &&
        !hasInh) {
      return false;
    }
    final sheet = sheetEl ?? _ensurePageSheet(pageEl);
    var changed = false;
    final widthInh = isInhFormula(_pageSheetCellF(sheet, 'PageWidth'));
    final heightInh = isInhFormula(_pageSheetCellF(sheet, 'PageHeight'));
    if (needWidth || widthInh) {
      // `V` is written in Visio's internal units (inches); the existing `U`
      // display attribute is left untouched. See readLengthInches.
      // Value-unchanged but F=Inh still scrubs (same as ShdwOffset*).
      _writeValue(
          _ensurePageSheetCell(sheet, 'PageWidth'), _fmt(ep.widthInches));
      changed = true;
    }
    if (needHeight || heightInh) {
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
        changed |= _removePageSheetCells(sheet, const ['PageColor']);
      }
    } else if (ep.backgroundColor == null) {
      // Model has no colour — still drop residual F=Inh (same as Layer Color).
      final f = _pageSheetCellF(sheet, 'PageColor');
      if (isInhFormula(f)) {
        changed |= _removePageSheetCells(sheet, const ['PageColor']);
      }
    }
    if (needSheet || hasInh) {
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
      final inh = isInhFormula(_pageSheetCellF(sheet, name));
      if ((b - e).abs() <= _epsilon && !inh) return;
      _writeValue(_ensurePageSheetCell(sheet, name), _fmt(e),
          preserveFormula: _pageSheetCellHasFormula(sheet, name));
      changed = true;
    }

    void raw(
      String name,
      String b,
      String e, {
      String? baseUnit,
      String? editedUnit,
    }) {
      final inh = isInhFormula(_pageSheetCellF(sheet, name));
      final unitChanged = baseUnit != editedUnit;
      if (b == e && !inh && !unitChanged) return;
      final cell = _ensurePageSheetCell(sheet, name);
      _writeValue(cell, e,
          preserveFormula: _pageSheetCellHasFormula(sheet, name));
      if (unitChanged) {
        if (editedUnit == null || editedUnit.isEmpty) {
          cell.removeAttribute('U');
        } else {
          cell.setAttribute('U', editedUnit);
        }
      }
      changed = true;
    }

    void flag(String name, bool b, bool e) {
      final inh = isInhFormula(_pageSheetCellF(sheet, name));
      if (b == e && !inh) return;
      _writeValue(_ensurePageSheetCell(sheet, name), e ? '1' : '0');
      changed = true;
    }

    len('ShdwOffsetX', base.shadowOffsetXInches, edited.shadowOffsetXInches);
    len('ShdwOffsetY', base.shadowOffsetYInches, edited.shadowOffsetYInches);
    raw('PageScale', _fmt(base.pageScale), _fmt(edited.pageScale),
        baseUnit: base.pageScaleUnit, editedUnit: edited.pageScaleUnit);
    raw('DrawingScale', _fmt(base.drawingScale), _fmt(edited.drawingScale),
        baseUnit: base.drawingScaleUnit,
        editedUnit: edited.drawingScaleUnit);
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
    // Optional PageSheet cells: when model is null, still drop residual F=Inh
    // (parser treats Inh-without-master as absent — same as PageColor).
    bool dropOptional(String name, Object? editedVal, Object? baseVal) {
      if (editedVal != null) return false;
      if (baseVal != null || isInhFormula(_pageSheetCellF(sheet, name))) {
        return _removePageSheetCells(sheet, [name]);
      }
      return false;
    }

    if (edited.lineJumpCode != null) {
      raw('LineJumpCode', (base.lineJumpCode ?? -1).toString(),
          edited.lineJumpCode.toString());
    } else {
      changed |= dropOptional('LineJumpCode', null, base.lineJumpCode);
    }
    if (edited.lineJumpStyle != null) {
      raw('LineJumpStyle', (base.lineJumpStyle ?? -1).toString(),
          edited.lineJumpStyle.toString());
    } else {
      changed |= dropOptional('LineJumpStyle', null, base.lineJumpStyle);
    }
    if (edited.lineJumpDirX != null) {
      raw('PageLineJumpDirX', (base.lineJumpDirX ?? -1).toString(),
          edited.lineJumpDirX.toString());
    } else {
      changed |= dropOptional('PageLineJumpDirX', null, base.lineJumpDirX);
    }
    if (edited.lineJumpDirY != null) {
      raw('PageLineJumpDirY', (base.lineJumpDirY ?? -1).toString(),
          edited.lineJumpDirY.toString());
    } else {
      changed |= dropOptional('PageLineJumpDirY', null, base.lineJumpDirY);
    }
    if (edited.lineToLineXInches != null) {
      len('LineToLineX', base.lineToLineXInches ?? 0, edited.lineToLineXInches!);
    } else {
      changed |=
          dropOptional('LineToLineX', null, base.lineToLineXInches);
    }
    if (edited.lineToLineYInches != null) {
      len('LineToLineY', base.lineToLineYInches ?? 0, edited.lineToLineYInches!);
    } else {
      changed |=
          dropOptional('LineToLineY', null, base.lineToLineYInches);
    }
    if (edited.lineJumpFactorX != null) {
      raw('LineJumpFactorX', _fmt(base.lineJumpFactorX ?? -1),
          _fmt(edited.lineJumpFactorX!));
    } else {
      changed |=
          dropOptional('LineJumpFactorX', null, base.lineJumpFactorX);
    }
    if (edited.lineJumpFactorY != null) {
      raw('LineJumpFactorY', _fmt(base.lineJumpFactorY ?? -1),
          _fmt(edited.lineJumpFactorY!));
    } else {
      changed |=
          dropOptional('LineJumpFactorY', null, base.lineJumpFactorY);
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
    } else {
      changed |= dropOptional(
          'VariationColorIndex', null, base.variationColorIndex);
    }
    if (edited.variationStyleIndex != null) {
      raw('VariationStyleIndex', (base.variationStyleIndex ?? -1).toString(),
          edited.variationStyleIndex.toString());
    } else {
      changed |= dropOptional(
          'VariationStyleIndex', null, base.variationStyleIndex);
    }
    return changed;
  }

  static String? _pageSheetCellF(XmlElement sheet, String name) {
    for (final el in sheet.childElements) {
      if (el.name.local == 'Cell' && el.getAttribute('N') == name) {
        return el.getAttribute('F');
      }
    }
    return null;
  }

  static bool _pageSheetHasInh(XmlElement sheet) {
    for (final el in sheet.childElements) {
      if (el.name.local == 'Cell' && isInhFormula(el.getAttribute('F'))) {
        return true;
      }
    }
    return false;
  }

  bool _removePageSheetCells(XmlElement sheet, List<String> names) {
    final want = names.toSet();
    var any = false;
    for (final el in sheet.childElements.toList()) {
      if (el.name.local != 'Cell') continue;
      final n = el.getAttribute('N');
      if (n != null && want.contains(n)) {
        el.parent?.children.remove(el);
        any = true;
      }
    }
    return any;
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
      '<Cell N="LeftMargin" V="0.04"/>'
      '<Cell N="RightMargin" V="0.04"/>'
      '<Cell N="TopMargin" V="0.04"/>'
      '<Cell N="BottomMargin" V="0.04"/>'
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

  /// Patch `<DocumentSettings>` cells / Default*Style attrs in document.xml.
  ///
  /// Scrubs residual `F=Inh` and writes model literals; drops `PageColor` when
  /// the model has no document background colour.
  bool _patchDocumentSettings(
    XmlDocument docXml,
    VsdxDocumentSettings base,
    VsdxDocumentSettings edited,
  ) {
    final root = docXml.rootElement;
    if (root.name.local != 'VisioDocument') return false;
    XmlElement? settings;
    for (final c in root.childElements) {
      if (c.name.local == 'DocumentSettings') {
        settings = c;
        break;
      }
    }
    final hasInh = settings != null &&
        settings.childElements.any(
          (e) =>
              e.name.local == 'Cell' && isInhFormula(e.getAttribute('F')),
        );
    final need = base != edited || hasInh;
    if (!need) return false;

    if (settings == null) {
      settings = XmlElement(XmlName('DocumentSettings'));
      // Prefer before StyleSheets / FaceNames when present.
      XmlNode? insertBefore;
      for (final c in root.childElements) {
        if (c.name.local == 'StyleSheets' || c.name.local == 'FaceNames') {
          insertBefore = c;
          break;
        }
      }
      if (insertBefore != null) {
        root.children.insert(root.children.indexOf(insertBefore), settings);
      } else {
        root.children.add(settings);
      }
    }
    final sheet = settings;

    var changed = false;
    void patchAttr(String name, int? want) {
      final cur = int.tryParse(sheet.getAttribute(name) ?? '');
      if (cur == want) return;
      if (want == null) {
        sheet.removeAttribute(name);
      } else {
        sheet.setAttribute(name, want.toString());
      }
      changed = true;
    }

    patchAttr('DefaultTextStyle', edited.defaultTextStyleId);
    patchAttr('DefaultLineStyle', edited.defaultLineStyleId);
    patchAttr('DefaultFillStyle', edited.defaultFillStyleId);

    if (edited.defaultPageBackgroundColor != null) {
      final want = _hex(edited.defaultPageBackgroundColor!);
      final c = _ensureCell(sheet, 'PageColor');
      if (c.getAttribute('V') != want ||
          isInhFormula(c.getAttribute('F'))) {
        _writeValue(c, want);
        changed = true;
      }
    } else {
      final colorCell = _findCell(sheet, 'PageColor');
      if (colorCell != null) {
        _removeNamedCells(sheet, const ['PageColor']);
        changed = true;
      }
    }

    changed |=
        _ensureLiteralInt(sheet, 'GlueType', edited.glueType);
    changed |= _ensureLiteralInt(
        sheet, 'SnapEnabled', edited.snapEnabled ? 1 : 0);
    changed |=
        _ensureLiteralInt(sheet, 'GridDensityX', edited.gridDensityX);
    changed |=
        _ensureLiteralInt(sheet, 'GridDensityY', edited.gridDensityY);
    return changed;
  }

  /// Generate a minimal, valid blank `.vsdx` (one empty page). Used as the
  /// base for "New drawing": the editor parses it, then normal
  /// load-preserve-patch saves append the user's shapes into `page1.xml`.
  Uint8List emptyDocument({
    double widthInches = 8.5,
    double heightInches = 11.0,
    String? title,
    String? creator,
    String? subject,
    String? keywords,
    String? description,
    String? lastModifiedBy,
    String? created,
    String? modified,
    String? language,
    String? category,
    String? company,
    String? template,
  }) {
    const decl = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
    final creatorXml = VsdxWriter._xmlEscape(creator ?? 'Editor for Visio Diagrams');
    final titleXml = (title != null && title.isNotEmpty)
        ? '<dc:title>${VsdxWriter._xmlEscape(title)}</dc:title>'
        : '';
    String core(String tag, String? value) =>
        value == null || value.isEmpty
            ? ''
            : '<$tag>${VsdxWriter._xmlEscape(value)}</$tag>';
    String date(String tag, String? value) =>
        value == null || value.isEmpty
            ? ''
            : '<dcterms:$tag xsi:type="dcterms:W3CDTF">'
                '${VsdxWriter._xmlEscape(value)}</dcterms:$tag>';
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
          '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
          '$titleXml'
          '<dc:creator>$creatorXml</dc:creator>'
          '${core('dc:subject', subject)}'
          '${core('cp:keywords', keywords)}'
          '${core('dc:description', description)}'
          '${core('cp:lastModifiedBy', lastModifiedBy)}'
          '${date('created', created)}'
          '${date('modified', modified)}'
          '${core('dc:language', language)}'
          '${core('cp:category', category)}'
          '</cp:coreProperties>',
      'docProps/app.xml': '$decl\n'
          '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
          '<Application>Editor for Visio Diagrams</Application>'
          '${core('Company', company)}'
          '${core('Template', template)}'
          '</Properties>',
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

  /// Attach the semantic [document]'s masters to a freshly synthesised VSDX.
  ///
  /// Legacy VSD/VDX import resolves master inheritance eagerly, so the page
  /// shapes are already complete. Preserve the separate master registry too,
  /// using the relationship chain consumed by libvisio/LibreOffice:
  /// document -> masters.xml -> masterN.xml.
  Uint8List attachSyntheticMasters({
    required Uint8List originalBytes,
    required VsdxDocument document,
  }) {
    final masters = document.masters.all.toList(growable: false);
    if (masters.isEmpty) return originalBytes;

    final pkg = VsdxPackage.open(originalBytes);
    final resolver = RelationshipResolver(pkg);
    final docPart = pkg.resolveDocumentPartName();
    if (resolver.singleTargetOfType(docPart, VsdxRelType.masters) != null) {
      return originalBytes;
    }

    final contentTypes = pkg.readPartXml('/[Content_Types].xml');
    if (contentTypes == null) return originalBytes;

    final patched = <String, Uint8List>{};
    final docRelsPart = _relsPartFor(docPart);
    final docRels = pkg.readPartXml(docRelsPart) ??
        XmlDocument.parse(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
          '<Relationships xmlns="$_relNs"/>',
        );
    final mastersRelId = 'rId${_maxRelId(docRels) + 1}';
    docRels.rootElement.children.add(XmlElement(XmlName('Relationship'), [
      XmlAttribute(XmlName('Id'), mastersRelId),
      XmlAttribute(
        XmlName('Type'),
        'http://schemas.microsoft.com/visio/2010/relationships/masters',
      ),
      XmlAttribute(XmlName('Target'), 'masters/masters.xml'),
    ]));
    patched[_noSlash(docRelsPart)] =
        Uint8List.fromList(utf8.encode(docRels.toXmlString()));

    _ensurePartOverride(
      contentTypes,
      '/visio/masters/masters.xml',
      'application/vnd.ms-visio.masters+xml',
    );

    final masterIndexRows = <XmlNode>[];
    final masterRelationships = <XmlNode>[];
    for (var i = 0; i < masters.length; i++) {
      final master = masters[i];
      final number = i + 1;
      final fileName = 'master$number.xml';
      final partName = '/visio/masters/$fileName';
      final relId = 'rId$number';

      final imageShapes = <VsdxShape>[];
      void collectImages(VsdxShape shape) {
        if (shape.hasImage) imageShapes.add(shape);
        for (final child in shape.children) {
          collectImages(child);
        }
      }

      collectImages(master.prototype);
      for (final shape in master.additionalPrototypes) {
        collectImages(shape);
      }
      final imageRels = _prepareImageParts(
        pkg: pkg,
        edited: document,
        rebuiltImageShapes: imageShapes,
        pagePart: partName,
        patched: patched,
        ctXml: contentTypes,
        markCtDirty: () {},
      );

      patched[_noSlash(partName)] = Uint8List.fromList(utf8.encode(
        _buildMasterContentsXml(master, imageRels: imageRels),
      ));
      _ensurePartOverride(
        contentTypes,
        partName,
        'application/vnd.ms-visio.master+xml',
      );
      masterIndexRows.add(_buildMasterIndexElement(master, relId));
      masterRelationships.add(XmlElement(XmlName('Relationship'), [
        XmlAttribute(XmlName('Id'), relId),
        XmlAttribute(
          XmlName('Type'),
          'http://schemas.microsoft.com/visio/2010/relationships/master',
        ),
        XmlAttribute(XmlName('Target'), fileName),
      ]));
    }

    final mastersRoot = XmlElement(
      XmlName('Masters'),
      <XmlAttribute>[
        XmlAttribute(XmlName('xmlns'), _mainNs),
        XmlAttribute(XmlName('r', 'xmlns'), _officeRelNs),
      ],
      masterIndexRows,
    );
    patched['visio/masters/masters.xml'] = Uint8List.fromList(utf8.encode(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
      '${mastersRoot.toXmlString()}',
    ));
    final mastersRelsRoot = XmlElement(
      XmlName('Relationships'),
      <XmlAttribute>[XmlAttribute(XmlName('xmlns'), _relNs)],
      masterRelationships,
    );
    patched['visio/masters/_rels/masters.xml.rels'] =
        Uint8List.fromList(utf8.encode(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
      '${mastersRelsRoot.toXmlString()}',
    ));
    patched['[Content_Types].xml'] =
        Uint8List.fromList(utf8.encode(contentTypes.toXmlString()));
    return _rezip(originalBytes, patched);
  }

  bool _ensurePartOverride(
    XmlDocument contentTypes,
    String partName,
    String contentType,
  ) {
    for (final child in contentTypes.rootElement.childElements) {
      if (child.name.local == 'Override' &&
          child.getAttribute('PartName') == partName) {
        return false;
      }
    }
    contentTypes.rootElement.children.add(XmlElement(XmlName('Override'), [
      XmlAttribute(XmlName('PartName'), partName),
      XmlAttribute(XmlName('ContentType'), contentType),
    ]));
    return true;
  }

  XmlElement _buildMasterIndexElement(VsdxMaster master, String relId) {
    final width = master.pageWidthInches > 0
        ? master.pageWidthInches
        : master.prototype.width.abs();
    final height = master.pageHeightInches > 0
        ? master.pageHeightInches
        : master.prototype.height.abs();
    return XmlElement(
      XmlName('Master'),
      <XmlAttribute>[
        XmlAttribute(XmlName('ID'), master.id.toString()),
        XmlAttribute(XmlName('NameU'), master.name),
        XmlAttribute(XmlName('Name'), master.name),
      ],
      <XmlNode>[
        XmlElement(XmlName('PageSheet'), const [], <XmlNode>[
          _cell('PageWidth', _fmt(width)),
          _cell('PageHeight', _fmt(height)),
          ..._pageSheetExtraCells(master.pageSheet),
        ]),
        XmlElement(
          XmlName('Rel'),
          <XmlAttribute>[XmlAttribute(XmlName('id', 'r'), relId)],
        ),
      ],
    );
  }

  String _buildMasterContentsXml(
    VsdxMaster master, {
    Map<String, String> imageRels = const <String, String>{},
  }) {
    final root = XmlElement(
      XmlName('MasterContents'),
      <XmlAttribute>[
        XmlAttribute(XmlName('xmlns'), _mainNs),
        XmlAttribute(XmlName('r', 'xmlns'), _officeRelNs),
      ],
      <XmlNode>[
        XmlElement(XmlName('Shapes'), const [], <XmlNode>[
          _buildShapeElement(master.prototype, imageRels: imageRels),
          for (final shape in master.additionalPrototypes)
            _buildShapeElement(shape, imageRels: imageRels),
        ]),
      ],
    );
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '${root.toXmlString()}';
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

  static bool _connectsEqual(List<VsdxConnect> a, List<VsdxConnect> b) {
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

  /// Preserve source XML for a shape whose editable inputs are unchanged.
  /// Besides avoiding needless package churn, this is essential for master
  /// instances: the parser exposes their resolved ShapeSheet values, while
  /// the source may contain only a few local overrides.  Materialising the
  /// resolved values can change what libvisio/Visio renders.  Descendants are
  /// still visited independently by [_patchPage].
  static bool _shapePatchInputsEqual(VsdxShape a, VsdxShape b) =>
      a.id == b.id &&
      a.name == b.name &&
      a.pinX == b.pinX &&
      a.pinY == b.pinY &&
      a.width == b.width &&
      a.height == b.height &&
      a.locPinXInches == b.locPinXInches &&
      a.locPinYInches == b.locPinYInches &&
      a.angleRad == b.angleRad &&
      a.text == b.text &&
      _richTextEqual(a.richText, b.richText) &&
      _textBlocksEqual(a.richText.textBlock, b.richText.textBlock) &&
      _shapeGeometriesEqual(a.geometries, b.geometries) &&
      _fillsEqual(a.fill, b.fill) &&
      _linesEqual(a.line, b.line) &&
      _shadowsEqual(a.shadow, b.shadow) &&
      _glowsEqual(a.glow, b.glow) &&
      _reflectionsEqual(a.reflection, b.reflection) &&
      _intListsEqual(a.layerMemberIds, b.layerMemberIds) &&
      a.is1D == b.is1D &&
      a.beginX == b.beginX &&
      a.beginY == b.beginY &&
      a.endX == b.endX &&
      a.endY == b.endY &&
      a.straightRoute == b.straightRoute &&
      a.curved == b.curved &&
      a.rounded == b.rounded &&
      _listEqual(a.waypoints, b.waypoints) &&
      a.flipX == b.flipX &&
      a.flipY == b.flipY &&
      a.locked == b.locked &&
      a.imagePartName == b.imagePartName &&
      a.imgOffsetXInches == b.imgOffsetXInches &&
      a.imgOffsetYInches == b.imgOffsetYInches &&
      a.imgWidthInches == b.imgWidthInches &&
      a.imgHeightInches == b.imgHeightInches &&
      a.imageTransparency == b.imageTransparency &&
      a.imageBlur == b.imageBlur &&
      a.imageBrightness == b.imageBrightness &&
      a.imageContrast == b.imageContrast &&
      a.foreignType == b.foreignType &&
      a.foreignCompressionType == b.foreignCompressionType &&
      a.objType == b.objType &&
      a.resizeMode == b.resizeMode &&
      a.eventDblClick == b.eventDblClick &&
      a.noAlignBox == b.noAlignBox &&
      a.shapeSplittable == b.shapeSplittable &&
      a.themeIndex == b.themeIndex &&
      a.quickStyleFillMatrix == b.quickStyleFillMatrix &&
      a.quickStyleLineMatrix == b.quickStyleLineMatrix &&
      a.quickStyleEffectsMatrix == b.quickStyleEffectsMatrix &&
      a.quickStyleFontMatrix == b.quickStyleFontMatrix &&
      a.isTextEditTarget == b.isTextEditTarget &&
      a.dontMoveChildren == b.dontMoveChildren &&
      a.selectMode == b.selectMode &&
      a.displayMode == b.displayMode &&
      _connectsEqual(a.connects, b.connects) &&
      _connectionPointsEqual(a.connectionPoints, b.connectionPoints) &&
      _hyperlinksEqual(a.hyperlinks, b.hyperlinks) &&
      _userPropsEqual(a.userProperties, b.userProperties) &&
      _userCellsEqual(a.userCells, b.userCells) &&
      _listEqual(a.controls, b.controls) &&
      _listEqual(a.scratch, b.scratch) &&
      _listEqual(a.fields, b.fields) &&
      _actionsEqual(a.actions, b.actions) &&
      a.masterId == b.masterId &&
      a.masterShapeId == b.masterShapeId &&
      a.lineStyleId == b.lineStyleId &&
      a.fillStyleId == b.fillStyleId &&
      a.textStyleId == b.textStyleId &&
      _mapEqual(a.formulas, b.formulas) &&
      a.connectorProps == b.connectorProps;

  static bool _documentPatchInputsEqual(VsdxDocument a, VsdxDocument b) =>
      a.settings == b.settings &&
      a.title == b.title &&
      a.creator == b.creator &&
      a.subject == b.subject &&
      a.keywords == b.keywords &&
      a.description == b.description &&
      a.lastModifiedBy == b.lastModifiedBy &&
      a.created == b.created &&
      a.modified == b.modified &&
      a.language == b.language &&
      a.category == b.category &&
      a.company == b.company &&
      a.template == b.template &&
      a.applicationName == b.applicationName &&
      _customPropertiesEqual(a.customProperties, b.customProperties) &&
      _themesEqual(a.theme, b.theme) &&
      _imagesEqual(a.images, b.images) &&
      _pagesEqual(a.pages, b.pages);

  static bool _pagesEqual(List<VsdxPage> a, List<VsdxPage> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.id != y.id ||
          x.name != y.name ||
          x.widthInches != y.widthInches ||
          x.heightInches != y.heightInches ||
          x.backgroundColor != y.backgroundColor ||
          x.isBackgroundPage != y.isBackgroundPage ||
          x.backgroundPageId != y.backgroundPageId ||
          x.pageSheet != y.pageSheet ||
          x.viewScale != y.viewScale ||
          x.viewCenterX != y.viewCenterX ||
          x.viewCenterY != y.viewCenterY ||
          !_listEqual(x.layers, y.layers) ||
          !_connectsEqual(x.connects, y.connects) ||
          !_shapeTreesEqual(x.shapes, y.shapes)) {
        return false;
      }
    }
    return true;
  }

  static bool _shapeTreesEqual(List<VsdxShape> a, List<VsdxShape> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_shapePatchInputsEqual(a[i], b[i]) ||
          !_shapeTreesEqual(a[i].children, b[i].children)) {
        return false;
      }
    }
    return true;
  }

  static bool _customPropertiesEqual(
    List<VsdxCustomProperty> a,
    List<VsdxCustomProperty> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.name != y.name ||
          x.value != y.value ||
          x.valueType != y.valueType ||
          x.propertyId != y.propertyId) {
        return false;
      }
    }
    return true;
  }

  static bool _themesEqual(VsdxTheme a, VsdxTheme b) {
    if (a.colors.length != b.colors.length ||
        a.variationColors.length != b.variationColors.length ||
        a.fillStyleColors.length != b.fillStyleColors.length ||
        a.variationFillStyleIndices.length !=
            b.variationFillStyleIndices.length) {
      return false;
    }
    for (final entry in a.colors.entries) {
      if (b.colors[entry.key] != entry.value) return false;
    }
    for (var i = 0; i < a.variationColors.length; i++) {
      if (!_listEqual(a.variationColors[i], b.variationColors[i])) return false;
    }
    if (!_listEqual(a.fillStyleColors, b.fillStyleColors)) return false;
    for (var i = 0; i < a.variationFillStyleIndices.length; i++) {
      if (!_listEqual(a.variationFillStyleIndices[i],
          b.variationFillStyleIndices[i])) {
        return false;
      }
    }
    return true;
  }

  static bool _imagesEqual(ImageRegistry a, ImageRegistry b) {
    if (a.length != b.length) return false;
    for (final x in a.all) {
      final y = b.findByPart(x.partName);
      if (y == null ||
          x.mimeType != y.mimeType ||
          x.bytes.length != y.bytes.length) {
        return false;
      }
      for (var i = 0; i < x.bytes.length; i++) {
        if (x.bytes[i] != y.bytes[i]) return false;
      }
    }
    return true;
  }

  static bool _textBlocksEqual(VsdxTextBlock a, VsdxTextBlock b) =>
      a.pinXInches == b.pinXInches &&
      a.pinYInches == b.pinYInches &&
      a.locPinXInches == b.locPinXInches &&
      a.locPinYInches == b.locPinYInches &&
      a.widthInches == b.widthInches &&
      a.heightInches == b.heightInches &&
      a.angleRad == b.angleRad &&
      a.verticalAlign == b.verticalAlign &&
      a.marginLeftInches == b.marginLeftInches &&
      a.marginRightInches == b.marginRightInches &&
      a.marginTopInches == b.marginTopInches &&
      a.marginBottomInches == b.marginBottomInches &&
      a.hideText == b.hideText &&
      a.backgroundColor == b.backgroundColor &&
      a.backgroundTransparency == b.backgroundTransparency &&
      a.textDirection == b.textDirection &&
      a.defaultTabStopInches == b.defaultTabStopInches;

  static bool _shapeGeometriesEqual(
    List<VsdxGeometry> a,
    List<VsdxGeometry> b,
  ) {
    if (!_geometriesEqual(a, b)) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.noFill != y.noFill ||
          x.noLine != y.noLine ||
          x.noShow != y.noShow ||
          x.noSnap != y.noSnap ||
          x.noQuickDrag != y.noQuickDrag ||
          x.hitBox != y.hitBox ||
          x.ix != y.ix ||
          x.deleted != y.deleted ||
          !_intListsEqual(x.rowIndices, y.rowIndices) ||
          !_setsEqual(x.deletedRowIndices, y.deletedRowIndices) ||
          !_setsEqual(x.definedFlagCells, y.definedFlagCells)) {
        return false;
      }
    }
    return true;
  }

  static bool _setsEqual<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);

  static bool _fillsEqual(VsdxFill a, VsdxFill b) =>
      a.foreground == b.foreground &&
      a.background == b.background &&
      a.foregroundTransparency == b.foregroundTransparency &&
      a.backgroundTransparency == b.backgroundTransparency &&
      a.pattern == b.pattern &&
      a.themeForegroundIndex == b.themeForegroundIndex &&
      a.themeBackgroundIndex == b.themeBackgroundIndex &&
      _gradientsEqual(a.gradient, b.gradient);

  static bool _linesEqual(VsdxLine a, VsdxLine b) =>
      a.color == b.color &&
      a.weightInches == b.weightInches &&
      a.pattern == b.pattern &&
      a.cap == b.cap &&
      a.transparency == b.transparency &&
      a.themeColorIndex == b.themeColorIndex &&
      a.beginArrow == b.beginArrow &&
      a.endArrow == b.endArrow &&
      a.beginArrowSizeInches == b.beginArrowSizeInches &&
      a.endArrowSizeInches == b.endArrowSizeInches &&
      a.roundingInches == b.roundingInches &&
      _nullableDoubleListsEqual(a.customDashPattern, b.customDashPattern) &&
      a.fixedDash == b.fixedDash &&
      a.join == b.join &&
      a.miterLimit == b.miterLimit &&
      a.softEdgesInches == b.softEdgesInches &&
      a.compoundType == b.compoundType &&
      _gradientsEqual(a.gradient, b.gradient);

  static bool _nullableDoubleListsEqual(List<double>? a, List<double>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _shadowsEqual(VsdxShadow a, VsdxShadow b) =>
      a.color == b.color &&
      a.themeColorIndex == b.themeColorIndex &&
      a.offsetXInches == b.offsetXInches &&
      a.offsetYInches == b.offsetYInches &&
      a.blurInches == b.blurInches &&
      a.transparency == b.transparency &&
      a.enabled == b.enabled &&
      a.pattern == b.pattern;

  static bool _glowsEqual(VsdxGlow a, VsdxGlow b) =>
      a.color == b.color &&
      a.themeColorIndex == b.themeColorIndex &&
      a.sizeInches == b.sizeInches &&
      a.transparency == b.transparency &&
      a.enabled == b.enabled;

  static bool _reflectionsEqual(VsdxReflection a, VsdxReflection b) =>
      a.sizeInches == b.sizeInches &&
      a.distanceInches == b.distanceInches &&
      a.transparency == b.transparency &&
      a.blurInches == b.blurInches &&
      a.enabled == b.enabled;

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
    // Persist editor-owned route flags and exact legacy-VSD marker sizes into
    // User cells before diffing so both remain editable across reopen.
    base = base.persistRouteState().persistVsdArrowSizes();
    final importedVsdArrowSizes = base.userCells.any((cell) =>
        cell.name == VsdxShape.userVsdBeginArrowSize ||
        cell.name == VsdxShape.userVsdEndArrowSize);
    edited = edited
        .persistRouteState()
        .persistVsdArrowSizes(force: importedVsdArrowSizes);
    final inheritsShapeSheet = el.getAttribute('Master') != null ||
        el.getAttribute('MasterShape') != null;
    if ((preserveUnchangedPackage || inheritsShapeSheet) &&
        _shapePatchInputsEqual(base, edited)) {
      return false;
    }
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
      changed |= _syncForeignDataAttrs(el, edited);
    }
    changed |= _ensureLineFillBasics(el, edited);
    changed |= _patchAngle(el, 'Angle', base.angleRad, edited.angleRad);
    // Scrub Angle F=Inh when the model holds a literal (keep real formulas).
    if (_nonInhFormula(edited.formulas['Angle']) == null) {
      changed |= _ensureLiteralLength(el, 'Angle', edited.angleRad);
    } else {
      changed |=
          _syncCellFormulaAttr(el, 'Angle', edited.formulas['Angle']);
    }
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
    // Never re-emit Master F=Inh (same scrub as TxtAngle / Angle).
    for (final name in const ['BeginX', 'BeginY', 'EndX', 'EndY']) {
      final f = _nonInhFormula(edited.formulas[name]);
      if (f != null) {
        changed |= _syncCellFormulaAttr(el, name, f);
      } else {
        final c = _findCell(el, name);
        final raw = (c?.getAttribute('F') ?? '').trim().toUpperCase();
        if (raw == 'INH' || raw.startsWith('INH(') || edited.formulas[name] != null) {
          changed |= _clearCellFormulaAttr(el, name);
        }
      }
    }
    bool xformValueUnchanged(String name) => switch (name) {
          'PinX' => (base.pinX - edited.pinX).abs() <= _epsilon,
          'PinY' => (base.pinY - edited.pinY).abs() <= _epsilon,
          'Width' => (base.width - edited.width).abs() <= _epsilon,
          'Height' => (base.height - edited.height).abs() <= _epsilon,
          'LocPinX' =>
            (base.effectiveLocPinX - edited.effectiveLocPinX).abs() <= _epsilon,
          'LocPinY' =>
            (base.effectiveLocPinY - edited.effectiveLocPinY).abs() <= _epsilon,
          _ => false,
        };
    // PinX/Y / LocPin / size: keep real parametric formulas. For unchanged
    // 1-D shapes also retain local F=Inh — it is part of the original XForm
    // contract and must not be materialised merely by open→save.
    for (final name in const [
      'PinX',
      'PinY',
      'Width',
      'Height',
      'LocPinX',
      'LocPinY',
    ]) {
      final c = _findCell(el, name);
      final raw = (c?.getAttribute('F') ?? '').trim().toUpperCase();
      if ((raw == 'INH' || raw.startsWith('INH(')) &&
          edited.is1D &&
          xformValueUnchanged(name)) {
        continue;
      }
      final f = _nonInhFormula(edited.formulas[name]);
      if (f != null) {
        changed |= _syncCellFormulaAttr(el, name, f);
      } else {
        if (raw == 'INH' || raw.startsWith('INH(')) {
          changed |= _clearCellFormulaAttr(el, name);
        }
      }
    }
    changed |= _patchBool(el, 'FlipX', base.flipX, edited.flipX);
    changed |= _patchBool(el, 'FlipY', base.flipY, edited.flipY);
    // Preserve meaningful formulas such as `(FALSE)` on identity saves;
    // F=Inh is still scrubbed (the model has already resolved inheritance).
    bool preserveFlipFormula(String name, bool unchanged) {
      final raw = (_cellFormula(el, name) ?? '').trim();
      return unchanged && raw.isNotEmpty && !isInhFormula(raw);
    }

    if (!preserveFlipFormula('FlipX', base.flipX == edited.flipX)) {
      changed |= _ensureLiteralInt(el, 'FlipX', edited.flipX ? 1 : 0);
    }
    if (!preserveFlipFormula('FlipY', base.flipY == edited.flipY)) {
      changed |= _ensureLiteralInt(el, 'FlipY', edited.flipY ? 1 : 0);
    }
    // Group behaviour (libvisio IsTextEditTarget / DontMoveChildren / …).
    changed |= _patchBool(
        el, 'IsTextEditTarget', base.isTextEditTarget, edited.isTextEditTarget);
    changed |= _ensureLiteralInt(
        el, 'IsTextEditTarget', edited.isTextEditTarget ? 1 : 0);
    changed |= _patchBool(
        el, 'DontMoveChildren', base.dontMoveChildren, edited.dontMoveChildren);
    changed |= _ensureLiteralInt(
        el, 'DontMoveChildren', edited.dontMoveChildren ? 1 : 0);
    changed |= _patchOptionalIntCell(
        el, 'SelectMode', base.selectMode, edited.selectMode);
    changed |= _patchOptionalIntCell(
        el, 'DisplayMode', base.displayMode, edited.displayMode);
    if (edited.selectMode != null) {
      changed |= _ensureLiteralInt(el, 'SelectMode', edited.selectMode!);
    }
    if (edited.displayMode != null) {
      changed |= _ensureLiteralInt(el, 'DisplayMode', edited.displayMode!);
    }
    // Protection (drawio "Lock/Unlock").
    changed |= _patchLock(el, base, edited);
    // Style.
    changed |= _patchColorOrTheme(el, 'FillForegnd', 'QuickStyleFillColor',
        baseColor: base.fill.foreground,
        baseTheme: base.fill.themeForegroundIndex,
        editedColor: edited.fill.foreground,
        editedTheme: edited.fill.themeForegroundIndex);
    // Match rebuild: a standalone filled leaf needs an explicit foreground so
    // Edraw does not treat a missing FillForegnd as hollow. Materialise the
    // resolved model colour on equal-path saves too; keep genuine
    // Master/FillStyle inheritance untouched.
    final inheritsFill = el.getAttribute('Master') != null ||
        el.getAttribute('MasterShape') != null ||
        el.getAttribute('FillStyle') != null;
    if (edited.fill.pattern != 0 &&
        edited.children.isEmpty &&
        edited.fill.themeForegroundIndex == null &&
        !inheritsFill &&
        !_hasCell(el, 'FillForegnd')) {
      final foreground =
          edited.fill.foreground ?? const VsdxColor(0xFFFFFFFF);
      _writeValue(_ensureCell(el, 'FillForegnd'), _hex(foreground));
      changed = true;
    }
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
    // Groups often omit Fill* entirely and inherit via StyleSheet. Materialising
    // the parser default pattern=1 without FillForegnd makes Edraw treat the
    // container as a hollow phantom fill. Only ensure when the cell already
    // exists (scrub Inh) or the shape is a leaf (rebuild always emits pattern).
    if (edited.children.isEmpty || _hasCell(el, 'FillPattern')) {
      changed |= _ensureLiteralInt(el, 'FillPattern', edited.fill.pattern);
    }
    changed |= _patchColorOrTheme(el, 'LineColor', 'QuickStyleLineColor',
        baseColor: base.line.color,
        baseTheme: base.line.themeColorIndex,
        editedColor: edited.line.color,
        editedTheme: edited.line.themeColorIndex);
    changed |= _patchLength(el, 'LineWeight', base.line.weightInches, edited.line.weightInches);
    changed |= _ensureLiteralLength(el, 'LineWeight', edited.line.weightInches);
    changed |= _patchInt(el, 'LinePattern', base.line.pattern, edited.line.pattern);
    changed |= _ensureLiteralInt(el, 'LinePattern', edited.line.pattern);
    changed |= _patchInt(el, 'LineCap', _lineCapInt(base.line.cap), _lineCapInt(edited.line.cap));
    changed |= _ensureLiteralInt(el, 'LineCap', _lineCapInt(edited.line.cap));
    changed |= _patchInt(el, 'BeginArrow', base.line.beginArrow, edited.line.beginArrow);
    changed |= _ensureLiteralInt(el, 'BeginArrow', edited.line.beginArrow);
    changed |= _patchInt(el, 'EndArrow', base.line.endArrow, edited.line.endArrow);
    changed |= _ensureLiteralInt(el, 'EndArrow', edited.line.endArrow);
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
    // Use ensure (not force) so a missing cell is injected from the model.
    changed |= _ensureLiteralInt(
        el,
        'BeginArrowSize',
        _arrowSizeToBucket(edited.line.beginArrowSizeInches));
    changed |= _ensureLiteralInt(
        el,
        'EndArrowSize',
        _arrowSizeToBucket(edited.line.endArrowSizeInches));
    changed |= _patchRatio(el, 'FillForegndTrans',
        base.fill.foregroundTransparency, edited.fill.foregroundTransparency);
    changed |= _ensureLiteralLength(
        el, 'FillForegndTrans', edited.fill.foregroundTransparency);
    changed |= _patchRatio(el, 'FillBkgndTrans',
        base.fill.backgroundTransparency, edited.fill.backgroundTransparency);
    changed |= _ensureLiteralLength(
        el, 'FillBkgndTrans', edited.fill.backgroundTransparency);
    changed |= _patchRatio(
        el, 'LineColorTrans', base.line.transparency, edited.line.transparency);
    changed |=
        _ensureLiteralLength(el, 'LineColorTrans', edited.line.transparency);
    changed |= _patchLength(
        el, 'Rounding', base.line.roundingInches, edited.line.roundingInches);
    // Ensure missing SoftEdges/Rounding/CompoundType cells (rebuild always
    // emits them; StyleSheet can revive 0 defaults when cells are absent).
    changed |=
        _ensureLiteralLength(el, 'Rounding', edited.line.roundingInches);
    changed |= _patchLength(
        el, 'SoftEdgesSize', base.line.softEdgesInches, edited.line.softEdgesInches);
    changed |=
        _ensureLiteralLength(el, 'SoftEdgesSize', edited.line.softEdgesInches);
    changed |= _patchInt(
        el, 'CompoundType', base.line.compoundType, edited.line.compoundType);
    changed |=
        _ensureLiteralInt(el, 'CompoundType', edited.line.compoundType);
    changed |= _patchLayerMember(el, base.layerMemberIds, edited.layerMemberIds);
    // Text block transform (TxtPin / TxtWidth / TxtAngle / margins) +
    // HideText / TextBkgnd + drop shadow / glow / reflection.
    changed |= _patchTextBlock(
      el,
      base.richText.textBlock,
      edited.richText.textBlock,
      edited,
    );
    changed |= _patchShadow(el, base.shadow, edited.shadow);
    changed |= _patchGlow(el, base.glow, edited.glow);
    changed |= _patchReflection(el, base.reflection, edited.reflection);
    // Effects: force literal cell values without F= so StyleSheet Inh cannot
    // override enable bits / companions whether the effect is on or off
    // (mirrors SoftEdgesSize / FillGradientEnabled scrub paths).
    if (!edited.shadow.enabled) {
      // Inject / scrub pattern=0 so StyleSheet cannot revive a shadow on 2-D
      // shapes (connectors already ensure via _ensureConnectorDynamics).
      for (final name in const ['ShadowPattern', 'ShdwPattern']) {
        final c = _ensureCell(el, name);
        if (c.getAttribute('V') != '0' ||
            (c.getAttribute('F') ?? '').isNotEmpty) {
          _writeValue(c, '0');
          changed = true;
        }
      }
    } else {
      // Shadow still on — drop F=Inh on pattern so inheritance cannot clear it.
      changed |=
          _ensureLiteralInt(el, 'ShadowPattern', edited.shadow.xmlPattern);
      changed |=
          _ensureLiteralInt(el, 'ShdwPattern', edited.shadow.xmlPattern);
    }
    // Keep companion V= (re-enable), scrub F=Inh on or off.
    changed |= _ensureLiteralLength(
        el, 'ShadowOffsetX', edited.shadow.offsetXInches);
    changed |= _ensureLiteralLength(
        el, 'ShadowOffsetY', edited.shadow.offsetYInches);
    changed |=
        _ensureLiteralLength(el, 'ShadowBlur', edited.shadow.blurInches);
    changed |= _ensureLiteralLength(
        el, 'ShadowForegndTrans', edited.shadow.transparency);
    // Colour companions: scrub F=Inh even when the effect model is unchanged
    // (Trans/Size already scrubbed above; colour was previously skipped).
    // Unbound (null color + null theme): drop residual cells / Inh so a
    // stylesheet cannot revive ShadowForegnd on reopen (rebuild omits them).
    if (edited.shadow.color != null) {
      changed |=
          _forceLiteralColor(el, 'ShadowForegnd', edited.shadow.color!);
    } else if (edited.shadow.themeColorIndex != null) {
      // Theme-bound: rewrite THEMEVAL if F=Inh (solid path uses forceLiteral).
      changed |= _patchColorOrTheme(
        el,
        'ShadowForegnd',
        'QuickStyleShadowColor',
        baseColor: null,
        baseTheme: edited.shadow.themeColorIndex,
        editedColor: null,
        editedTheme: edited.shadow.themeColorIndex,
      );
    } else {
      changed |= _patchColorOrTheme(
        el,
        'ShadowForegnd',
        'QuickStyleShadowColor',
        baseColor: null,
        baseTheme: null,
        editedColor: null,
        editedTheme: null,
      );
    }
    if (!edited.glow.enabled) {
      changed |= _forceLiteralZeroLength(el, 'GlowSize');
    } else {
      changed |=
          _ensureLiteralLength(el, 'GlowSize', edited.glow.sizeInches);
    }
    changed |=
        _ensureLiteralLength(el, 'GlowColorTrans', edited.glow.transparency);
    if (edited.glow.color != null) {
      changed |= _forceLiteralColor(el, 'GlowColor', edited.glow.color!);
    } else if (edited.glow.themeColorIndex != null) {
      changed |= _patchColorOrTheme(
        el,
        'GlowColor',
        'QuickStyleEffectColor',
        baseColor: null,
        baseTheme: edited.glow.themeColorIndex,
        editedColor: null,
        editedTheme: edited.glow.themeColorIndex,
      );
    } else {
      changed |= _patchColorOrTheme(
        el,
        'GlowColor',
        'QuickStyleEffectColor',
        baseColor: null,
        baseTheme: null,
        editedColor: null,
        editedTheme: null,
      );
    }
    if (!edited.reflection.enabled) {
      changed |= _forceLiteralZeroLength(el, 'ReflectionSize');
    } else {
      changed |= _ensureLiteralLength(
          el, 'ReflectionSize', edited.reflection.sizeInches);
    }
    // Dist/Blur/Trans kept for toggle-off → save → reopen → toggle-on.
    changed |= _ensureLiteralLength(
        el, 'ReflectionDist', edited.reflection.distanceInches);
    changed |= _ensureLiteralLength(
        el, 'ReflectionBlur', edited.reflection.blurInches);
    changed |= _ensureLiteralLength(
        el, 'ReflectionTransparency', edited.reflection.transparency);
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
    changed |= _ensureConnectorDynamics(el, base, edited);
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
      changed |= _ensureLiteralInt(el, 'ThemeIndex', edited.themeIndex!);
    }
    changed |= _patchOptionalIntCell(el, 'QuickStyleFillMatrix',
        base.quickStyleFillMatrix, edited.quickStyleFillMatrix);
    changed |= _patchOptionalIntCell(el, 'QuickStyleLineMatrix',
        base.quickStyleLineMatrix, edited.quickStyleLineMatrix);
    changed |= _patchOptionalIntCell(el, 'QuickStyleEffectsMatrix',
        base.quickStyleEffectsMatrix, edited.quickStyleEffectsMatrix);
    changed |= _patchOptionalIntCell(el, 'QuickStyleFontMatrix',
        base.quickStyleFontMatrix, edited.quickStyleFontMatrix);
    if (edited.quickStyleFillMatrix != null) {
      changed |= _ensureLiteralInt(
          el, 'QuickStyleFillMatrix', edited.quickStyleFillMatrix!);
    }
    if (edited.quickStyleLineMatrix != null) {
      changed |= _ensureLiteralInt(
          el, 'QuickStyleLineMatrix', edited.quickStyleLineMatrix!);
    }
    if (edited.quickStyleEffectsMatrix != null) {
      changed |= _ensureLiteralInt(
          el, 'QuickStyleEffectsMatrix', edited.quickStyleEffectsMatrix!);
    }
    if (edited.quickStyleFontMatrix != null) {
      changed |= _ensureLiteralInt(
          el, 'QuickStyleFontMatrix', edited.quickStyleFontMatrix!);
    }
    // ObjType / NoAlignBox / etc. — rebuild emits them; patch must too so
    // in-place edits survive save without a group rebuild.
    changed |=
        _patchOptionalIntCell(el, 'ObjType', base.objType, edited.objType);
    changed |= _patchOptionalIntCell(
        el, 'ResizeMode', base.resizeMode, edited.resizeMode);
    if (edited.objType != null) {
      changed |= _ensureLiteralInt(el, 'ObjType', edited.objType!);
    }
    if (edited.resizeMode != null) {
      changed |= _ensureLiteralInt(el, 'ResizeMode', edited.resizeMode!);
    }
    changed |=
        _patchFlagCell(el, 'NoAlignBox', base.noAlignBox, edited.noAlignBox);
    changed |= _patchFlagCell(
        el, 'ShapeSplittable', base.shapeSplittable, edited.shapeSplittable);
    changed |= _patchOptionalStringCell(
        el, 'EventDblClick', base.eventDblClick, edited.eventDblClick);
    // Ensure EventDblClick when model holds a literal or formula (rebuild emits
    // it; equal-path previously skipped a missing cell).
    if (edited.eventDblClick != null ||
        edited.formulas.containsKey('EventDblClick')) {
      final modelF = _nonInhFormula(edited.formulas['EventDblClick']);
      final wantV = edited.eventDblClick ?? '0';
      final c = _ensureCell(el, 'EventDblClick');
      if (modelF != null) {
        if (c.getAttribute('V') != wantV || c.getAttribute('F') != modelF) {
          _writeValue(c, wantV, preserveFormula: true);
          c.setAttribute('F', modelF);
          changed = true;
        }
      } else if (c.getAttribute('V') != wantV ||
          (c.getAttribute('F') ?? '').isNotEmpty) {
        _writeValue(c, wantV);
        changed = true;
      }
    }
    return changed;
  }

  /// Patch a boolean ShapeSheet flag cell. Always write `V="0"`/`"1"` so Master
  /// inheritance cannot revive a cleared flag after save (do not delete the cell).
  bool _patchFlagCell(XmlElement shape, String cell, bool base, bool edited) {
    if (base == edited) {
      // Scrub F=Inh whether the flag is on or off (cleared false must stick).
      // Ensure so a missing NoAlignBox / ShapeSplittable is injected.
      return _ensureLiteralInt(shape, cell, edited ? 1 : 0);
    }
    _writeValue(_ensureCell(shape, cell), edited ? '1' : '0');
    return true;
  }

  /// Patch an optional string cell (remove when [edited] is null).
  bool _patchOptionalStringCell(
    XmlElement shape,
    String cell,
    String? base,
    String? edited,
  ) {
    if (base == edited) {
      // Equal null still drops residual F=Inh (EventDblClick etc.).
      if (edited == null) {
        final existing = _findCell(shape, cell);
        if (existing != null && isInhFormula(existing.getAttribute('F'))) {
          return _removeNamedCells(shape, [cell]);
        }
        return false;
      }
      // Equal non-null: still inject when the cell is missing.
      if (!_hasCell(shape, cell)) {
        _writeValue(_ensureCell(shape, cell), edited);
        return true;
      }
      return false;
    }
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
    if (base == edited) {
      // Equal null still drops residual F=Inh (ThemeIndex / SelectMode / …).
      if (edited == null) {
        final existing = _findCell(shape, cell);
        if (existing != null && isInhFormula(existing.getAttribute('F'))) {
          existing.parent?.children.remove(existing);
          return true;
        }
      }
      return false;
    }
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
      // Never re-emit Master F=Inh — treat like a cleared formula.
      final f = _nonInhFormula(entry.value);
      if (f == null) {
        changed |= _clearCellFormulaAttr(el, entry.key);
        continue;
      }
      final prev = base.formulas[entry.key];
      if (prev == entry.value) continue;
      final cell = _ensureCell(el, entry.key);
      if (cell.getAttribute('F') == f) continue;
      cell.setAttribute('F', f);
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
  /// THEMEVAL / Inh formula (leftover from theme → solid / no-fill / pattern
  /// edits, or Master inheritance). Rebuild must not re-emit these.
  Set<String> _staleThemeFormulaKeys(VsdxShape s) {
    final out = <String>{};
    bool isThemeVal(String? f) =>
        f != null &&
        RegExp(r'THEMEVAL\s*\(', caseSensitive: false).hasMatch(f);
    bool isInh(String? f) {
      if (f == null) return false;
      final u = f.trim().toUpperCase();
      return u == 'INH' || u.startsWith('INH(');
    }
    if ((isThemeVal(s.formulas['FillForegnd']) &&
            (s.fill.foreground != null ||
                s.fill.themeForegroundIndex == null)) ||
        isInh(s.formulas['FillForegnd'])) {
      out.add('FillForegnd');
    }
    if ((isThemeVal(s.formulas['FillBkgnd']) &&
            (s.fill.background != null ||
                s.fill.themeBackgroundIndex == null)) ||
        isInh(s.formulas['FillBkgnd'])) {
      out.add('FillBkgnd');
    }
    if ((isThemeVal(s.formulas['LineColor']) &&
            (s.line.color != null || s.line.themeColorIndex == null)) ||
        isInh(s.formulas['LineColor'])) {
      out.add('LineColor');
    }
    // Pattern cells are always literal ints in the model — leftover THEMEVAL
    // / Inh would resurrect theme / Master pattern on a second save.
    if (isThemeVal(s.formulas['FillPattern']) ||
        isInh(s.formulas['FillPattern'])) {
      out.add('FillPattern');
    }
    if (isThemeVal(s.formulas['LinePattern']) ||
        isInh(s.formulas['LinePattern'])) {
      out.add('LinePattern');
    }
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
    var changed = false;
    // BegTrigger / EndTrigger are formula cells (`_XFTRIGGER(...)`) — only
    // rewrite when the model value changes. Never scrub residual F= on equal
    // (would flatten `_XFTRIGGER` into a bare V=).
    if (e?.begTrigger != null) {
      changed |=
          _patchStringCell(el, 'BegTrigger', b?.begTrigger, e!.begTrigger!);
    }
    if (e?.endTrigger != null) {
      changed |=
          _patchStringCell(el, 'EndTrigger', b?.endTrigger, e!.endTrigger!);
    }
    // Optional ints: write literal when set; when null still drop residual
    // F=Inh (same as PageSheet LineJump* / ThemeIndex).
    changed |= _dropOptionalConnectorInt(el, 'GlueType', e?.glueType);
    changed |= _dropOptionalConnectorInt(el, 'ConFixedCode', e?.conFixedCode);
    changed |= _dropOptionalConnectorInt(el, 'DynFeedback', e?.dynFeedback);
    if (e != null) {
      changed |= _patchBool(el, 'NoLiveDynamics', b?.noLiveDynamics ?? false,
          e.noLiveDynamics);
      changed |= _forceLiteralInt(
          el, 'NoLiveDynamics', e.noLiveDynamics ? 1 : 0);
    }
    changed |=
        _dropOptionalConnectorInt(el, 'ConLineJumpCode', e?.conLineJumpCode);
    changed |=
        _dropOptionalConnectorInt(el, 'ConLineRouteExt', e?.conLineRouteExt);
    changed |=
        _dropOptionalConnectorInt(el, 'ConLineJumpStyle', e?.conLineJumpStyle);
    changed |=
        _dropOptionalConnectorInt(el, 'ConLineJumpDirX', e?.conLineJumpDirX);
    changed |=
        _dropOptionalConnectorInt(el, 'ConLineJumpDirY', e?.conLineJumpDirY);
    changed |=
        _dropOptionalConnectorInt(el, 'ShapeRouteStyle', e?.shapeRouteStyle);
    changed |=
        _dropOptionalConnectorInt(el, 'ShapePlaceFlip', e?.shapePlaceFlip);
    return changed;
  }

  /// Write a connector optional int, or drop the cell when null + residual Inh.
  bool _dropOptionalConnectorInt(XmlElement el, String name, int? value) {
    if (value != null) return _ensureLiteralInt(el, name, value);
    final cell = _findCell(el, name);
    if (cell != null && isInhFormula(cell.getAttribute('F'))) {
      return _removeNamedCells(el, [name]);
    }
    return false;
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
      // Values unchanged — still scrub residual Dir*/Type F=Inh.
      return _scrubConnectionCompanionInh(el, edited);
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
        // Dir*/Type/AutoGen — update cached V; drop F=Inh (not parametric).
        final dirXCell = _ensureCell(rows[i], 'DirX');
        final dirYCell = _ensureCell(rows[i], 'DirY');
        _writeValue(dirXCell, _fmt(p.dirX),
            preserveFormula: _isParametricFormula(dirXCell.getAttribute('F')));
        _writeValue(dirYCell, _fmt(p.dirY),
            preserveFormula: _isParametricFormula(dirYCell.getAttribute('F')));
        _writeValue(_ensureCell(rows[i], 'Type'), p.type.toString());
        _writeValue(_ensureCell(rows[i], 'AutoGen'), p.autoGen ? '1' : '0');
        if (p.prompt != null) {
          _writeValue(_ensureCell(rows[i], 'Prompt'), p.prompt!);
        } else {
          _removeNamedCells(rows[i], const ['Prompt']);
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

  /// When Connection points are unchanged, still drop companion F=Inh so
  /// Master inheritance cannot revive stale Dir*/Type after a pin-only save.
  bool _scrubConnectionCompanionInh(XmlElement el, VsdxShape edited) {
    if (edited.connectionPoints.isEmpty) return false;
    XmlElement? section;
    for (final s in el.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'Connection') {
        section = s;
        break;
      }
    }
    if (section == null) return false;
    final rows =
        section.childElements.where((r) => r.name.local == 'Row').toList();
    var changed = false;
    for (var i = 0; i < edited.connectionPoints.length && i < rows.length; i++) {
      final p = edited.connectionPoints[i];
      changed |= _scrubFormulaOrLiteral(
          rows[i], 'X', _fmt(p.x), formula: p.xFormula);
      changed |= _scrubFormulaOrLiteral(
          rows[i], 'Y', _fmt(p.y), formula: p.yFormula);
      final dirXCell = _ensureCell(rows[i], 'DirX');
      final dirYCell = _ensureCell(rows[i], 'DirY');
      changed |= _writeValueIfNeeded(dirXCell, _fmt(p.dirX));
      changed |= _writeValueIfNeeded(dirYCell, _fmt(p.dirY));
      changed |=
          _writeValueIfNeeded(_ensureCell(rows[i], 'Type'), p.type.toString());
      changed |= _writeValueIfNeeded(
          _ensureCell(rows[i], 'AutoGen'), p.autoGen ? '1' : '0');
      if (p.prompt != null) {
        changed |=
            _writeValueIfNeeded(_ensureCell(rows[i], 'Prompt'), p.prompt!);
      } else {
        changed |= _removeInhOrDrop(rows[i], 'Prompt');
      }
    }
    return changed;
  }

  /// Write [value] and clear F=/E= when the cell still carries Inh or differs.
  bool _writeValueIfNeeded(XmlElement cell, String value) {
    final f = cell.getAttribute('F');
    final v = cell.getAttribute('V');
    if (_isParametricFormula(f)) {
      if (v == value) return false;
      cell.setAttribute('V', value);
      return true;
    }
    if (v == value && (f == null || f.isEmpty)) return false;
    _writeValue(cell, value);
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
      return _scrubUserPropertyInh(el, edited);
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
      if (p.label != null) {
        _writeValue(_ensureCell(row, 'Label'), p.label!);
      } else {
        _removeNamedCells(row, const ['Label']);
      }
      if (p.prompt != null) {
        _writeValue(_ensureCell(row, 'Prompt'), p.prompt!);
      } else {
        _removeNamedCells(row, const ['Prompt']);
      }
      if (p.format != null) {
        _writeValue(_ensureCell(row, 'Format'), p.format!,
            preserveFormula: p.formatFormula != null);
      } else if (p.formatFormula != null) {
        _writeValue(_ensureCell(row, 'Format'), '',
            preserveFormula: true);
      } else {
        _removeNamedCells(row, const ['Format']);
      }
      if (p.formatFormula != null) {
        _ensureCell(row, 'Format').setAttribute('F', p.formatFormula!);
      }
      _writeValue(_ensureCell(row, 'Type'), p.type.toString());
      if (p.sortKey != null) {
        _writeValue(_ensureCell(row, 'SortKey'), p.sortKey!);
      } else {
        _removeNamedCells(row, const ['SortKey']);
      }
      _writeValue(_ensureCell(row, 'Invisible'), p.invisible ? '1' : '0');
      _writeValue(_ensureCell(row, 'Verify'), p.verify ? '1' : '0');
      _writeValue(_ensureCell(row, 'Ask'), p.ask ? '1' : '0');
      _writeValue(_ensureCell(row, 'DataLinked'), p.dataLinked ? '1' : '0');
      if (p.langId != null) {
        _writeValue(_ensureCell(row, 'LangID'), p.langId!);
      } else {
        _removeNamedCells(row, const ['LangID']);
      }
      if (p.calendar != null) {
        _writeValue(_ensureCell(row, 'Calendar'), p.calendar.toString());
      } else {
        _removeNamedCells(row, const ['Calendar']);
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
    if (_userCellsEqual(base.userCells, edited.userCells)) {
      return _scrubUserCellInh(el, edited);
    }
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
      } else {
        _removeNamedCells(row, const ['Prompt']);
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
    if (_listEqual(base.controls, edited.controls)) {
      return _scrubControlsInh(el, edited);
    }
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

  /// When Control rows are unchanged, still drop F=Inh on modeled cells.
  bool _scrubControlsInh(XmlElement el, VsdxShape edited) {
    if (edited.controls.isEmpty) return false;
    XmlElement? section;
    for (final s in el.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'Control') {
        section = s;
        break;
      }
    }
    if (section == null) return false;
    final rowByName = <String, XmlElement>{};
    for (final row in _rowsOf(section)) {
      final n = row.getAttribute('N');
      if (n != null) rowByName[n] = row;
    }
    var changed = false;
    for (final r in edited.controls) {
      final row = rowByName[r.name];
      if (row == null) continue;
      changed |= _scrubFormulaOrLiteral(
          row, 'X', _fmt(r.x), formula: r.xFormula);
      changed |= _scrubFormulaOrLiteral(
          row, 'Y', _fmt(r.y), formula: r.yFormula);
      if (r.useVisioDynNames) {
        changed |= _scrubFormulaOrLiteral(
            row, 'XDyn', _fmt(r.dynX), formula: r.dynXFormula);
        changed |= _scrubFormulaOrLiteral(
            row, 'YDyn', _fmt(r.dynY), formula: r.dynYFormula);
        changed |= _scrubFormulaOrLiteral(
            row, 'XCon', _fmt(r.conX), formula: r.conXFormula);
        changed |= _scrubFormulaOrLiteral(
            row, 'YCon', _fmt(r.conY), formula: r.conYFormula);
      } else {
        changed |= _scrubFormulaOrLiteral(
            row, 'DynX', _fmt(r.dynX), formula: r.dynXFormula);
        changed |= _scrubFormulaOrLiteral(
            row, 'DynY', _fmt(r.dynY), formula: r.dynYFormula);
        changed |= _scrubFormulaOrLiteral(
            row, 'ConX', _fmt(r.conX), formula: r.conXFormula);
        changed |= _scrubFormulaOrLiteral(
            row, 'ConY', _fmt(r.conY), formula: r.conYFormula);
      }
      changed |= _writeValueIfNeeded(
          _ensureCell(row, 'CanGlue'), r.canGlue ? '1' : '0');
      if (r.prompt != null) {
        changed |= _writeValueIfNeeded(_ensureCell(row, 'Prompt'), r.prompt!);
      } else {
        changed |= _removeInhOrDrop(row, 'Prompt');
      }
    }
    return changed;
  }

  /// Rebuild `<Section N="Scratch">` when rows change.
  bool _patchScratch(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_listEqual(base.scratch, edited.scratch)) {
      return _scrubScratchInh(el, edited);
    }
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

  bool _scrubScratchInh(XmlElement el, VsdxShape edited) {
    if (edited.scratch.isEmpty) return false;
    XmlElement? section;
    for (final s in el.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'Scratch') {
        section = s;
        break;
      }
    }
    if (section == null) return false;
    final rowByIx = <int, XmlElement>{};
    for (final row in _rowsOf(section)) {
      final ix = int.tryParse(row.getAttribute('IX') ?? '');
      if (ix != null) rowByIx[ix] = row;
    }
    var changed = false;
    for (final r in edited.scratch) {
      final row = rowByIx[r.ix];
      if (row == null) continue;
      changed |= _scrubFormulaOrLiteral(
          row, 'X', _fmt(r.x), formula: r.xFormula);
      changed |= _scrubFormulaOrLiteral(
          row, 'Y', _fmt(r.y), formula: r.yFormula);
      changed |= _scrubFormulaOrLiteral(
          row, 'A', _fmt(r.a), formula: r.aFormula);
      changed |= _scrubFormulaOrLiteral(
          row, 'B', _fmt(r.b), formula: r.bFormula);
      if (r.c != 0 || r.cFormula != null || _findCell(row, 'C') != null) {
        changed |= _scrubFormulaOrLiteral(
            row, 'C', _fmt(r.c), formula: r.cFormula);
      }
      if (r.d != 0 || r.dFormula != null || _findCell(row, 'D') != null) {
        changed |= _scrubFormulaOrLiteral(
            row, 'D', _fmt(r.d), formula: r.dFormula);
      }
    }
    return changed;
  }

  /// Rebuild `<Section N="Field">` when rows change.
  bool _patchFields(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_listEqual(base.fields, edited.fields)) {
      return _scrubFieldsInh(el, edited);
    }
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

  bool _scrubFieldsInh(XmlElement el, VsdxShape edited) {
    if (edited.fields.isEmpty) return false;
    XmlElement? section;
    for (final s in el.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'Field') {
        section = s;
        break;
      }
    }
    if (section == null) return false;
    final rowByIx = <int, XmlElement>{};
    for (final row in _rowsOf(section)) {
      final ix = int.tryParse(row.getAttribute('IX') ?? '');
      if (ix != null) rowByIx[ix] = row;
    }
    var changed = false;
    for (final r in edited.fields) {
      final row = rowByIx[r.ix];
      if (row == null) continue;
      changed |= _scrubFormulaOrLiteral(
          row, 'Value', r.value ?? '', formula: r.valueFormula);
      changed |= _scrubFormulaOrLiteral(
          row, 'Format', r.format ?? '', formula: r.formatFormula);
      changed |=
          _writeValueIfNeeded(_ensureCell(row, 'Type'), r.type.toString());
      if (r.uiCat != null) {
        changed |=
            _writeValueIfNeeded(_ensureCell(row, 'UICat'), r.uiCat.toString());
      } else {
        changed |= _removeInhOrDrop(row, 'UICat');
      }
      if (r.uiCod != null) {
        changed |=
            _writeValueIfNeeded(_ensureCell(row, 'UICod'), r.uiCod.toString());
      } else {
        changed |= _removeInhOrDrop(row, 'UICod');
      }
      if (r.uiFmt != null) {
        changed |=
            _writeValueIfNeeded(_ensureCell(row, 'UIFmt'), r.uiFmt.toString());
      } else {
        changed |= _removeInhOrDrop(row, 'UIFmt');
      }
      if (r.calendar != null) {
        changed |= _writeValueIfNeeded(
            _ensureCell(row, 'Calendar'), r.calendar.toString());
      } else {
        changed |= _removeInhOrDrop(row, 'Calendar');
      }
      if (r.objectKind != null) {
        changed |= _writeValueIfNeeded(
            _ensureCell(row, 'ObjectKind'), r.objectKind.toString());
      } else {
        changed |= _removeInhOrDrop(row, 'ObjectKind');
      }
    }
    return changed;
  }

  /// Scrub F=Inh (or restore non-Inh formula) on an existing/ensured cell.
  bool _scrubFormulaOrLiteral(
    XmlElement row,
    String name,
    String value, {
    String? formula,
  }) {
    final cell = _ensureCell(row, name);
    final wantF = _nonInhFormula(formula);
    if (wantF != null) {
      var changed = false;
      if (cell.getAttribute('F') != wantF) {
        cell.setAttribute('F', wantF);
        changed = true;
      }
      if (cell.getAttribute('V') != value) {
        cell.setAttribute('V', value);
        changed = true;
      }
      return changed;
    }
    return _writeValueIfNeeded(cell, value);
  }

  static bool _listEqual<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _patchLayerMember(XmlElement el, List<int> base, List<int> edited) {
    final want = edited.isEmpty ? '' : edited.join(';');
    if (_intListsEqual(base, edited)) {
      // Explicit empty must still exist so Master LayerMember cannot revive.
      final c = _ensureCell(el, 'LayerMember');
      if ((c.getAttribute('F') ?? '').isEmpty && c.getAttribute('V') == want) {
        return false;
      }
      _writeValue(c, want);
      return true;
    }
    _writeValue(_ensureCell(el, 'LayerMember'), want);
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
    if (_hyperlinksEqual(base.hyperlinks, edited.hyperlinks)) {
      return _scrubHyperlinkInh(el, edited);
    }
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
      if (h.description != null) {
        _writeValue(_ensureCell(row, 'Description'), h.description!);
      } else {
        _removeNamedCells(row, const ['Description']);
      }
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

  /// When Property rows are unchanged, still drop F=Inh on modelled cells.
  bool _scrubUserPropertyInh(XmlElement el, VsdxShape edited) {
    if (edited.userProperties.isEmpty) return false;
    XmlElement? section;
    for (final s in el.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'Property') {
        section = s;
        break;
      }
    }
    if (section == null) return false;
    final rowByName = <String, XmlElement>{};
    for (final row in _rowsOf(section)) {
      final n =
          row.getAttribute('N') ?? 'Row${row.getAttribute('IX') ?? ''}';
      rowByName[n] = row;
    }
    var changed = false;
    for (final p in edited.userProperties) {
      final row = rowByName[p.name];
      if (row == null) continue;
      changed |= _writeValueIfNeeded(
          _ensureCell(row, 'Value'), p.value ?? '');
      if (p.valueFormula != null) {
        final cell = _ensureCell(row, 'Value');
        final f = _nonInhFormula(p.valueFormula);
        if (f != null && cell.getAttribute('F') != f) {
          cell.setAttribute('F', f);
          changed = true;
        } else if (f == null && isInhFormula(cell.getAttribute('F'))) {
          cell.removeAttribute('F');
          changed = true;
        }
      } else if (isInhFormula(_ensureCell(row, 'Value').getAttribute('F'))) {
        _writeValue(_ensureCell(row, 'Value'), p.value ?? '');
        changed = true;
      }
      if (p.label != null) {
        changed |= _writeValueIfNeeded(_ensureCell(row, 'Label'), p.label!);
      } else {
        changed |= _removeInhOrDrop(row, 'Label');
      }
      if (p.prompt != null) {
        changed |= _writeValueIfNeeded(_ensureCell(row, 'Prompt'), p.prompt!);
      } else {
        changed |= _removeInhOrDrop(row, 'Prompt');
      }
      if (p.format != null || p.formatFormula != null) {
        changed |= _scrubFormulaOrLiteral(
            row, 'Format', p.format ?? '', formula: p.formatFormula);
      } else {
        changed |= _removeInhOrDrop(row, 'Format');
      }
      if (p.sortKey != null) {
        changed |=
            _writeValueIfNeeded(_ensureCell(row, 'SortKey'), p.sortKey!);
      } else {
        changed |= _removeInhOrDrop(row, 'SortKey');
      }
      if (p.langId != null) {
        changed |= _writeValueIfNeeded(_ensureCell(row, 'LangID'), p.langId!);
      } else {
        changed |= _removeInhOrDrop(row, 'LangID');
      }
      if (p.calendar != null) {
        changed |= _writeValueIfNeeded(
            _ensureCell(row, 'Calendar'), p.calendar.toString());
      } else {
        changed |= _removeInhOrDrop(row, 'Calendar');
      }
      changed |=
          _writeValueIfNeeded(_ensureCell(row, 'Type'), p.type.toString());
      changed |= _writeValueIfNeeded(
          _ensureCell(row, 'Invisible'), p.invisible ? '1' : '0');
      changed |=
          _writeValueIfNeeded(_ensureCell(row, 'Verify'), p.verify ? '1' : '0');
      changed |=
          _writeValueIfNeeded(_ensureCell(row, 'Ask'), p.ask ? '1' : '0');
      changed |= _writeValueIfNeeded(
          _ensureCell(row, 'DataLinked'), p.dataLinked ? '1' : '0');
    }
    return changed;
  }

  /// When User rows are unchanged, still drop F=Inh on Value/Prompt.
  bool _scrubUserCellInh(XmlElement el, VsdxShape edited) {
    if (edited.userCells.isEmpty) return false;
    XmlElement? section;
    for (final s in el.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'User') {
        section = s;
        break;
      }
    }
    if (section == null) return false;
    final rowByName = <String, XmlElement>{};
    for (final row in _rowsOf(section)) {
      final n = row.getAttribute('N');
      if (n != null) rowByName[n] = row;
    }
    var changed = false;
    for (final c in edited.userCells) {
      final row = rowByName[c.name];
      if (row == null) continue;
      changed |=
          _writeValueIfNeeded(_ensureCell(row, 'Value'), c.value ?? '');
      if (c.valueFormula != null) {
        final cell = _ensureCell(row, 'Value');
        final f = _nonInhFormula(c.valueFormula);
        if (f != null && cell.getAttribute('F') != f) {
          cell.setAttribute('F', f);
          changed = true;
        } else if (f == null && isInhFormula(cell.getAttribute('F'))) {
          cell.removeAttribute('F');
          changed = true;
        }
      } else if (isInhFormula(_ensureCell(row, 'Value').getAttribute('F'))) {
        _writeValue(_ensureCell(row, 'Value'), c.value ?? '');
        changed = true;
      }
      if (c.prompt != null) {
        changed |= _writeValueIfNeeded(_ensureCell(row, 'Prompt'), c.prompt!);
      } else {
        changed |= _removeInhOrDrop(row, 'Prompt');
      }
    }
    return changed;
  }

  /// When Hyperlink rows are unchanged, still drop F=Inh on Address/flags /
  /// SubAddress/ExtraInfo/Frame/SortKey/Description.
  bool _scrubHyperlinkInh(XmlElement el, VsdxShape edited) {
    if (edited.hyperlinks.isEmpty) return false;
    XmlElement? section;
    for (final s in el.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'Hyperlink') {
        section = s;
        break;
      }
    }
    if (section == null) return false;
    final rowByIx = <int, XmlElement>{};
    for (final row in _rowsOf(section)) {
      final ix = int.tryParse(row.getAttribute('IX') ?? '');
      if (ix != null) rowByIx[ix] = row;
    }
    var changed = false;
    for (final h in edited.hyperlinks) {
      final row = rowByIx[h.id];
      if (row == null) continue;
      changed |=
          _writeValueIfNeeded(_ensureCell(row, 'Address'), h.address ?? '');
      final addr = _ensureCell(row, 'Address');
      final af = _nonInhFormula(h.addressFormula);
      if (af != null) {
        if (addr.getAttribute('F') != af) {
          addr.setAttribute('F', af);
          changed = true;
        }
      } else if (isInhFormula(addr.getAttribute('F'))) {
        addr.removeAttribute('F');
        changed = true;
      }
      changed |= _writeValueIfNeeded(
          _ensureCell(row, 'SubAddress'), h.subAddress ?? '');
      if (h.description != null) {
        changed |=
            _writeValueIfNeeded(_ensureCell(row, 'Description'), h.description!);
      } else {
        changed |= _removeInhOrDrop(row, 'Description');
      }
      if (h.extraInfo != null) {
        changed |=
            _writeValueIfNeeded(_ensureCell(row, 'ExtraInfo'), h.extraInfo!);
      } else {
        changed |= _removeInhOrDrop(row, 'ExtraInfo');
      }
      if (h.frame != null) {
        changed |= _writeValueIfNeeded(_ensureCell(row, 'Frame'), h.frame!);
      } else {
        changed |= _removeInhOrDrop(row, 'Frame');
      }
      if (h.sortKey != null) {
        changed |=
            _writeValueIfNeeded(_ensureCell(row, 'SortKey'), h.sortKey!);
      } else {
        changed |= _removeInhOrDrop(row, 'SortKey');
      }
      changed |= _writeValueIfNeeded(
          _ensureCell(row, 'NewWindow'), h.newWindow ? '1' : '0');
      changed |= _writeValueIfNeeded(
          _ensureCell(row, 'Default'), h.isDefault ? '1' : '0');
      changed |= _writeValueIfNeeded(
          _ensureCell(row, 'Invisible'), h.invisible ? '1' : '0');
    }
    return changed;
  }

  bool _patchActions(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_actionsEqual(base.actions, edited.actions)) {
      return _scrubActionsInh(el, edited);
    }
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

  bool _scrubActionsInh(XmlElement el, VsdxShape edited) {
    if (edited.actions.isEmpty) return false;
    XmlElement? section;
    for (final s in el.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'Actions') {
        section = s;
        break;
      }
    }
    if (section == null) return false;
    final rowByName = <String, XmlElement>{};
    for (final row in _rowsOf(section)) {
      final n = row.getAttribute('N');
      if (n != null) rowByName[n] = row;
    }
    var changed = false;
    for (final r in edited.actions) {
      final row = rowByName[r.name];
      if (row == null) continue;
      if (r.menu != null) {
        changed |= _writeValueIfNeeded(_ensureCell(row, 'Menu'), r.menu!);
      } else {
        changed |= _removeInhOrDrop(row, 'Menu');
      }
      if (r.action != null || r.actionFormula != null) {
        changed |= _scrubFormulaOrLiteral(
            row, 'Action', r.action ?? '0', formula: r.actionFormula);
      } else {
        changed |= _removeInhOrDrop(row, 'Action');
      }
      if (r.checked || _findCell(row, 'Checked') != null) {
        changed |= _writeValueIfNeeded(
            _ensureCell(row, 'Checked'), r.checked ? '1' : '0');
      }
      if (r.disabled || _findCell(row, 'Disabled') != null) {
        changed |= _writeValueIfNeeded(
            _ensureCell(row, 'Disabled'), r.disabled ? '1' : '0');
      }
      if (r.readOnly || _findCell(row, 'ReadOnly') != null) {
        changed |= _writeValueIfNeeded(
            _ensureCell(row, 'ReadOnly'), r.readOnly ? '1' : '0');
      }
      if (r.invisible || _findCell(row, 'Invisible') != null) {
        changed |= _writeValueIfNeeded(
            _ensureCell(row, 'Invisible'), r.invisible ? '1' : '0');
      }
      if (r.tag != null) {
        changed |= _writeValueIfNeeded(_ensureCell(row, 'Tag'), r.tag!);
      } else {
        changed |= _removeInhOrDrop(row, 'Tag');
      }
      if (r.buttonFace != 0 || _findCell(row, 'ButtonFace') != null) {
        changed |= _writeValueIfNeeded(
            _ensureCell(row, 'ButtonFace'), r.buttonFace.toString());
      }
      if (r.sortKey != null) {
        changed |= _writeValueIfNeeded(_ensureCell(row, 'SortKey'), r.sortKey!);
      } else {
        changed |= _removeInhOrDrop(row, 'SortKey');
      }
    }
    return changed;
  }

  static bool _actionsEqual(List<VsdxActionRow> a, List<VsdxActionRow> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _patchRichText(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_richTextEqual(base.richText, edited.richText)) {
      return _scrubRichTextInh(el, edited);
    }
    final runs = edited.richText.runs;
    if (runs.isEmpty) {
      // Align with rebuild: no text runs → drop Character / Paragraph.
      return _removeCharacterParagraphSections(el);
    }

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

  /// When rich text model is unchanged, still scrub F=Inh on Character /
  /// Paragraph managed cells (Size/Color/HorzAlign/…).
  bool _scrubRichTextInh(XmlElement el, VsdxShape edited) {
    final runs = edited.richText.runs;
    if (runs.isEmpty) return false;
    XmlElement? charSection;
    XmlElement? paraSection;
    for (final s in el.childElements) {
      if (s.name.local != 'Section') continue;
      final n = s.getAttribute('N');
      if (n == 'Character') charSection = s;
      if (n == 'Paragraph') paraSection = s;
    }
    if (charSection == null && paraSection == null) return false;
    var changed = false;
    final charRows = charSection == null ? const <XmlElement>[] : _rowsOf(charSection);
    final paraRows = paraSection == null ? const <XmlElement>[] : _rowsOf(paraSection);
    for (var i = 0; i < runs.length; i++) {
      if (i < charRows.length) {
        changed |= _scrubCharRowInh(charRows[i], runs[i].charStyle);
      }
      if (i < paraRows.length) {
        changed |= _scrubParaRowInh(paraRows[i], runs[i].paraStyle);
      }
    }
    return changed;
  }

  bool _scrubCharRowInh(XmlElement row, VsdxCharStyle c) {
    var changed = false;
    changed |= _writeValueIfNeeded(
        _ensureCell(row, 'Size'), _fmt(c.fontSizeInches));
    changed |= _writeValueIfNeeded(
        _ensureCell(row, 'Style'), _charStyleBits(c).toString());
    if (c.color != null) {
      changed |=
          _writeValueIfNeeded(_ensureCell(row, 'Color'), _hex(c.color!));
    } else if (c.themeColorIndex != null) {
      final cell = _ensureCell(row, 'Color');
      if (cell.getAttribute('F') != 'THEMEVAL()' ||
          cell.getAttribute('V') != c.themeColorIndex!.toString()) {
        _writeValue(cell, c.themeColorIndex!.toString(), preserveFormula: true);
        cell.setAttribute('F', 'THEMEVAL()');
        changed = true;
      }
    } else {
      changed |= _removeInhOrDrop(row, 'Color');
    }
    if (c.fontFamily != null && c.fontFamily!.isNotEmpty) {
      changed |=
          _writeValueIfNeeded(_ensureCell(row, 'Font'), c.fontFamily!);
    } else {
      changed |= _removeInhOrDrop(row, 'Font');
    }
    changed |= _writeValueIfNeeded(
        _ensureCell(row, 'Strikethru'), c.strikethrough ? '1' : '0');
    changed |= _writeValueIfNeeded(
        _ensureCell(row, 'DblUnderline'), c.doubleUnderline ? '1' : '0');
    changed |= _writeValueIfNeeded(_ensureCell(row, 'DoubleStrikethrough'),
        c.doubleStrikethrough ? '1' : '0');
    changed |= _writeValueIfNeeded(
        _ensureCell(row, 'Overline'), c.overline ? '1' : '0');
    changed |= _writeValueIfNeeded(
        _ensureCell(row, 'Letterspace'), _fmt(c.letterSpacingInches));
    changed |= _writeValueIfNeeded(
        _ensureCell(row, 'Pos'), _textPositionInt(c.position).toString());
    changed |= _writeValueIfNeeded(
        _ensureCell(row, 'Case'), _textCaseInt(c.textCase).toString());
    changed |=
        _writeValueIfNeeded(_ensureCell(row, 'FontScale'), _fmt(c.fontScale));
    changed |= _writeValueIfNeeded(
        _ensureCell(row, 'ColorTrans'), _fmt(c.transparency));
    if (c.langId != null && c.langId!.isNotEmpty) {
      changed |= _writeValueIfNeeded(_ensureCell(row, 'LangID'), c.langId!);
    } else {
      changed |= _removeInhOrDrop(row, 'LangID');
    }
    if (c.asianFont != null && c.asianFont!.isNotEmpty) {
      changed |=
          _writeValueIfNeeded(_ensureCell(row, 'AsianFont'), c.asianFont!);
    } else {
      changed |= _removeInhOrDrop(row, 'AsianFont');
    }
    if (c.complexScriptFont != null && c.complexScriptFont!.isNotEmpty) {
      changed |= _writeValueIfNeeded(
          _ensureCell(row, 'ComplexScriptFont'), c.complexScriptFont!);
    } else {
      changed |= _removeInhOrDrop(row, 'ComplexScriptFont');
    }
    if (c.complexScriptSizeInches != null) {
      changed |= _writeValueIfNeeded(_ensureCell(row, 'ComplexScriptSize'),
          _fmt(c.complexScriptSizeInches!));
    } else {
      changed |= _removeInhOrDrop(row, 'ComplexScriptSize');
    }
    return changed;
  }

  bool _scrubParaRowInh(XmlElement row, VsdxParaStyle p) {
    var changed = false;
    changed |= _writeValueIfNeeded(
      _ensureCell(row, 'HorzAlign'),
      _alignToInt(p.horizontalAlign).toString(),
    );
    changed |= _writeValueIfNeeded(
        _ensureCell(row, 'IndFirst'), _fmt(p.indentFirstInches));
    changed |= _writeValueIfNeeded(
        _ensureCell(row, 'IndLeft'), _fmt(p.indentLeftInches));
    changed |= _writeValueIfNeeded(
        _ensureCell(row, 'IndRight'), _fmt(p.indentRightInches));
    changed |= _writeValueIfNeeded(
        _ensureCell(row, 'SpBefore'), _fmt(p.spaceBeforeInches));
    changed |= _writeValueIfNeeded(
        _ensureCell(row, 'SpAfter'), _fmt(p.spaceAfterInches));
    changed |= _writeValueIfNeeded(
        _ensureCell(row, 'SpLine'), _fmt(_spLineValue(p) ?? -1));
    changed |=
        _writeValueIfNeeded(_ensureCell(row, 'Bullet'), p.bullet.toString());
    if (p.bulletStr != null) {
      changed |=
          _writeValueIfNeeded(_ensureCell(row, 'BulletStr'), p.bulletStr!);
    } else {
      changed |= _removeInhOrDrop(row, 'BulletStr');
    }
    if (p.bulletFont != null) {
      changed |=
          _writeValueIfNeeded(_ensureCell(row, 'BulletFont'), p.bulletFont!);
    } else {
      changed |= _removeInhOrDrop(row, 'BulletFont');
    }
    if (p.bulletFontSizeInches != null) {
      changed |= _writeValueIfNeeded(
          _ensureCell(row, 'BulletFontSize'), _fmt(p.bulletFontSizeInches!));
    } else {
      changed |= _removeInhOrDrop(row, 'BulletFontSize');
    }
    changed |= _writeValueIfNeeded(
        _ensureCell(row, 'TextPosAfterBullet'),
        _fmt(p.textPosAfterBulletInches));
    changed |= _writeValueIfNeeded(
        _ensureCell(row, 'Flags'), p.flags.toString());
    return changed;
  }

  /// Drop a cell that still carries residual `F=Inh` (equal-path scrub).
  bool _removeInhOrDrop(XmlElement row, String name) {
    final cell = _findCell(row, name);
    if (cell == null) return false;
    if (!isInhFormula(cell.getAttribute('F'))) return false;
    return _removeNamedCells(row, [name]);
  }

  /// Drop local Character / Paragraph sections (empty label / clear text).
  bool _removeCharacterParagraphSections(XmlElement el) {
    var changed = false;
    for (final child in el.childElements.toList()) {
      if (child.name.local != 'Section') continue;
      final n = child.getAttribute('N');
      if (n == 'Character' || n == 'Paragraph') {
        child.parent?.children.remove(child);
        changed = true;
      }
    }
    return changed;
  }

  bool _patchTabs(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (_tabSetsEqual(base.richText.tabSets, edited.richText.tabSets)) {
      return _scrubTabsInh(el, edited);
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

  bool _scrubTabsInh(XmlElement el, VsdxShape edited) {
    XmlElement? section;
    for (final s in el.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == 'Tabs') {
        section = s;
        break;
      }
    }
    if (edited.richText.tabSets.isEmpty) {
      // Equal-path must still drop residual Tabs (incl. F=Inh rows).
      if (section == null) return false;
      section.parent?.children.remove(section);
      return true;
    }
    if (section == null) return false;
    final rowByIx = <int, XmlElement>{};
    for (final row in _rowsOf(section)) {
      final ix = int.tryParse(row.getAttribute('IX') ?? '');
      if (ix != null) rowByIx[ix] = row;
    }
    var changed = false;
    for (final set in edited.richText.tabSets) {
      final row = rowByIx[set.ix];
      if (row == null) continue;
      for (var i = 0; i < set.stops.length; i++) {
        // Visio PositionN / AlignmentN are 1-based. Always scrub to that
        // scheme so a Position0+Position1 pair cannot parse as two stops.
        final n1 = i + 1;
        changed |= _writeValueIfNeeded(_ensureCell(row, 'Position$n1'),
            _fmt(set.stops[i].positionInches));
        changed |= _writeValueIfNeeded(_ensureCell(row, 'Alignment$n1'),
            set.stops[i].alignment.toString());
      }
      // Drop legacy 0-based twins and any surplus beyond 1..stops.length.
      if (_findCell(row, 'Position0') != null ||
          _findCell(row, 'Alignment0') != null) {
        changed |= _removeNamedCells(row, const ['Position0', 'Alignment0']);
      }
      for (final cell in row.childElements.toList()) {
        final name = cell.getAttribute('N') ?? '';
        final m = RegExp(r'^(Position|Alignment)(\d+)$').firstMatch(name);
        if (m == null) continue;
        final n = int.parse(m.group(2)!);
        if (n < 1 || n > set.stops.length) {
          changed |= _removeNamedCells(row, [name]);
        }
      }
    }
    return changed;
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
    if (c.fontFamily != null && c.fontFamily!.isNotEmpty) {
      _writeValue(_ensureCell(row, 'Font'), c.fontFamily!);
    } else {
      // Match rebuild: omit Font when unbound so a prior face cannot stick.
      _removeNamedCells(row, const ['Font']);
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
    } else {
      _removeNamedCells(row, const ['AsianFont']);
    }
    if (c.complexScriptFont != null && c.complexScriptFont!.isNotEmpty) {
      _writeValue(_ensureCell(row, 'ComplexScriptFont'), c.complexScriptFont!);
    } else {
      _removeNamedCells(row, const ['ComplexScriptFont']);
    }
    if (c.langId != null && c.langId!.isNotEmpty) {
      _writeValue(_ensureCell(row, 'LangID'), c.langId!);
    } else {
      _removeNamedCells(row, const ['LangID']);
    }
    if (c.complexScriptSizeInches != null) {
      _writeValue(_ensureCell(row, 'ComplexScriptSize'),
          _fmt(c.complexScriptSizeInches!));
    } else {
      _removeNamedCells(row, const ['ComplexScriptSize']);
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
    if (p.bulletStr != null) {
      _writeValue(_ensureCell(row, 'BulletStr'), p.bulletStr!);
    } else {
      _removeNamedCells(row, const ['BulletStr']);
    }
    if (p.bulletFont != null) {
      _writeValue(_ensureCell(row, 'BulletFont'), p.bulletFont!);
    } else {
      _removeNamedCells(row, const ['BulletFont']);
    }
    if (p.bulletFontSizeInches != null) {
      _writeValue(
          _ensureCell(row, 'BulletFontSize'), _fmt(p.bulletFontSizeInches!));
    } else {
      _removeNamedCells(row, const ['BulletFontSize']);
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
        LineCap.square => 2,
        LineCap.extended => 1,
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
        VsdxHorzAlign.full => 4,
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
    if (_geometriesEqual(base.geometries, edited.geometries)) {
      return _scrubGeometryInh(el, edited);
    }
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

  /// When geometry model is unchanged, still drop residual F=Inh on numeric
  /// cells (keep Width*/Height*/Scratch parametric formulas).
  bool _scrubGeometryInh(XmlElement el, VsdxShape edited) {
    if (edited.geometries.isEmpty) return false;
    if (!edited.geometries.every(_canRebuild)) return false;
    final sections = <XmlElement>[
      for (final child in el.childElements)
        if (child.name.local == 'Section' &&
            child.getAttribute('N') == 'Geometry')
          child,
    ];
    if (sections.length != edited.geometries.length) return false;
    var changed = false;
    for (var si = 0; si < edited.geometries.length; si++) {
      final ge = edited.geometries[si];
      final rows = sections[si]
          .childElements
          .where((r) => r.name.local == 'Row')
          .toList();
      if (rows.length != ge.commands.length) continue;
      for (var ri = 0; ri < ge.commands.length; ri++) {
        final vals = _commandNumericCells(ge.commands[ri]);
        if (vals == null) continue;
        final row = rows[ri];
        for (final e in vals.entries) {
          final cell = _findCell(row, e.key);
          if (cell == null) continue;
          if (!isInhFormula(cell.getAttribute('F'))) continue;
          _writeValue(cell, _fmt(e.value));
          changed = true;
        }
      }
    }
    return changed;
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
      // Flags are applied after by [_ensureGeometryNoFillNoLine]; do not abort
      // in-place coordinate patches when only NoFill/NoLine/… changed.
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
          if ((oldV - newV).abs() <= _epsilon) {
            // Value unchanged — still scrub residual F=Inh (keep Width* etc.).
            if (isInhFormula(cell.getAttribute('F'))) {
              _writeValue(cell, _fmt(newV));
            }
            continue;
          }
          var keep = _formulaFitsScale(
              cell.getAttribute('F'), oldV, newV, sx: sx, sy: sy);
          // C (angle) / D (eccentricity) are not Width/Height scales — keeping
          // a constant F= would undo resized V in Visio/Edraw.
          if ((ce is EllipticalArcTo || ce is RelEllipticalArcTo) &&
              (name == 'C' || name == 'D')) {
            keep = false;
          }
          // Never preserve Master inherit as a "scale formula".
          if (isInhFormula(cell.getAttribute('F'))) keep = false;
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
      // Section flags (NoFill/NoLine/…) are synced separately by
      // [_ensureGeometryNoFillNoLine]; comparing them here forced a full
      // Geometry rebuild that dropped Width*/Scratch/unmodelled cells.
      if (ga.commands.length != gb.commands.length) {
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
      // Explicit colour: _writeValue drops THEMEVAL / Inh so the chosen colour
      // is honoured (the parser then ignores QuickStyle*).
      final curF = _cellFormula(shape, cell);
      final hasThemeF = curF != null &&
          RegExp(r'THEMEVAL\s*\(', caseSensitive: false).hasMatch(curF);
      final hasInh = isInhFormula(curF);
      final cellMissing = !_hasCell(shape, cell);
      var changed = false;
      // Also inject when the colour cell is absent (FillPattern/Trans already
      // ensure; Edraw is picky about a missing FillForegnd).
      if (!(baseTheme == null &&
          editedTheme == null &&
          baseColor?.value == editedColor.value &&
          !hasThemeF &&
          !hasInh &&
          !cellMissing)) {
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
      if (baseTheme == editedTheme &&
          baseColor == null &&
          formulaOk &&
          _hasCell(shape, cell)) {
        // Colour binding unchanged — still scrub QuickStyle* F=Inh.
        if (writeQuickStyle) {
          return _ensureLiteralInt(shape, quickStyleCell, editedTheme);
        }
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
    // Unbound colour (null color + null theme) — still drop residual F=Inh
    // so stylesheet cannot revive FillBkgnd / LineColor on reopen.
    final curF = _cellFormula(shape, cell);
    if (isInhFormula(curF)) {
      var changed = _removeNamedCells(shape, [cell]);
      if (writeQuickStyle) {
        changed |= _removeNamedCells(shape, [quickStyleCell]);
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

  /// Rewrite `<Text>` when the visible plain string **or** field/tab markers
  /// change. Prefer emitting `<cp>/<pp>` markers for multi-run rich text so
  /// Character / Paragraph row indices stay wired. Before each literal `\t`,
  /// emit `<tp IX="0"/>` to select its tab set, then retain the U+0009 text
  /// character that libvisio turns into `insertTab()`.
  bool _patchTextContent(XmlElement el, VsdxShape base, VsdxShape edited) {
    final basePlain =
        base.richText.runs.isNotEmpty ? base.richText.plainText : (base.text ?? '');
    final editedPlain = edited.richText.runs.isNotEmpty
        ? edited.richText.plainText
        : (edited.text ?? '');
    final markersChanged = !_textMarkersEqual(base.richText, edited.richText);
    if (editedPlain == basePlain && !markersChanged) return false;

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

  /// True when field spans / tab indices differ (plain text may be unchanged).
  static bool _textMarkersEqual(VsdxRichText a, VsdxRichText b) {
    if (a.runs.length != b.runs.length) return false;
    for (var i = 0; i < a.runs.length; i++) {
      if (!_listEqual(a.runs[i].fieldSpans, b.runs[i].fieldSpans)) {
        return false;
      }
      if (!_intListsEqual(a.runs[i].tabIndices, b.runs[i].tabIndices)) {
        return false;
      }
    }
    return true;
  }

  void _patchTextStyleSections(XmlElement el, List<VsdxTextRun> runs) {
    // Always drop existing Character/Paragraph first so an empty label does
    // not leave stale Font rows (rebuild omits both sections when no text).
    for (final child in el.childElements.toList()) {
      if (child.name.local != 'Section') continue;
      final n = child.getAttribute('N');
      if (n == 'Character' || n == 'Paragraph') child.remove();
    }
    if (runs.isEmpty) return;
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

  /// Emit one rich-text run: tabs → `<tp/>` + U+0009, fields → `<fld IX>`.
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

  /// Split [text] on `\t`, selecting the Tabs row with `<tp IX="…"/>` before
  /// retaining each literal U+0009. [tabIndices] supplies the row IX for each
  /// tab (defaults to 0).
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
        out.add(XmlText('\t'));
      }
    }
  }

  bool _patchShadow(XmlElement el, VsdxShadow base, VsdxShadow edited) {
    if (base.enabled == edited.enabled &&
        base.pattern == edited.pattern &&
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
        el, 'ShadowPattern', base.xmlPattern, edited.xmlPattern);
    changed |= _patchInt(
        el, 'ShdwPattern', base.xmlPattern, edited.xmlPattern);
    // Sync companions whether on or off so enable→edit→disable→save keeps
    // colour / offsets (rebuild already did; patch previously skipped).
    final forceCompanions = !edited.enabled || !base.enabled;
    if (edited.color == null && edited.themeColorIndex == null) {
      if (_removeNamedCells(
          el, const ['ShadowForegnd', 'QuickStyleShadowColor'])) {
        changed = true;
      }
    } else if (forceCompanions ||
        edited.color != null ||
        edited.themeColorIndex != null ||
        base.color != null ||
        base.themeColorIndex != null) {
      changed |= _patchColorOrTheme(
        el,
        'ShadowForegnd',
        'QuickStyleShadowColor',
        baseColor: forceCompanions ? null : base.color,
        baseTheme: forceCompanions ? null : base.themeColorIndex,
        editedColor: edited.color,
        editedTheme: edited.themeColorIndex,
      );
    }
    if (forceCompanions ||
        (base.offsetXInches - edited.offsetXInches).abs() > _epsilon) {
      _writeValue(
          _ensureCell(el, 'ShadowOffsetX'), _fmt(edited.offsetXInches));
      changed = true;
    }
    if (forceCompanions ||
        (base.offsetYInches - edited.offsetYInches).abs() > _epsilon) {
      _writeValue(
          _ensureCell(el, 'ShadowOffsetY'), _fmt(edited.offsetYInches));
      changed = true;
    }
    if (forceCompanions ||
        (base.blurInches - edited.blurInches).abs() > _epsilon) {
      _writeValue(_ensureCell(el, 'ShadowBlur'), _fmt(edited.blurInches));
      changed = true;
    }
    if (forceCompanions ||
        (base.transparency - edited.transparency).abs() > _epsilon) {
      _writeValue(
          _ensureCell(el, 'ShadowForegndTrans'), _fmt(edited.transparency));
      changed = true;
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
      _writeValue(_ensureCell(el, 'GlowSize'), '0');
      changed = true;
      // Sync companions on disable so enable→edit colour→disable→save keeps
      // the new colour (cell may never have existed before this write).
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
          baseColor: null,
          baseTheme: null,
          editedColor: edited.color,
          editedTheme: edited.themeColorIndex,
        );
      }
      _writeValue(
          _ensureCell(el, 'GlowColorTrans'), _fmt(edited.transparency));
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
      _writeValue(_ensureCell(el, 'ReflectionSize'), '0');
      // Inject Dist/Blur/Trans even when cells were never written (first
      // disable→save after editing companions only in memory).
      _writeValue(
          _ensureCell(el, 'ReflectionDist'), _fmt(edited.distanceInches));
      _writeValue(
          _ensureCell(el, 'ReflectionBlur'), _fmt(edited.blurInches));
      _writeValue(_ensureCell(el, 'ReflectionTransparency'),
          _fmt(edited.transparency));
      return true;
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
            _gradientDirFor(eg).toString());
        _writeValue(_ensureCell(el, 'FillGradientAngle'), _fmt(eg.angleRad));
        _insertBeforeTextOrShapes(el, _buildFillGradientSection(eg));
      } else {
        // Clearing must drop Inh/parametric F= so Visio cannot revive the
        // deleted FillGradient section via inheritance.
        _writeValue(_ensureCell(el, 'FillGradientEnabled'), '0');
        // Rebuild omits Dir/Angle when gradient is off — drop residual cells.
        _removeNamedCells(
            el, const ['FillGradientDir', 'FillGradientAngle']);
      }
      return true;
    }
    // Models already agree on "no gradient" but XML may still say V=0 F=Inh
    // (and leftover Dir/Angle / section from a prior enabled state). Rebuild
    // always emits Enabled=0 and omits Dir/Angle / section — match that.
    if (eg == null || eg.stops.isEmpty) {
      var changed = false;
      final residual = <XmlElement>[
        for (final child in el.childElements)
          if (child.name.local == 'Section' &&
              child.getAttribute('N') == 'FillGradient')
            child,
      ];
      for (final s in residual) {
        el.children.remove(s);
        changed = true;
      }
      changed |= _ensureLiteralInt(el, 'FillGradientEnabled', 0);
      changed |= _removeNamedCells(
          el, const ['FillGradientDir', 'FillGradientAngle']);
      return changed;
    }
    // Gradient still on — drop F=Inh on Enabled/Dir/Angle so stylesheet
    // inheritance cannot override the local literals.
    var scrubbed = _scrubEnabledFlagCell(el, 'FillGradientEnabled');
    scrubbed |=
        _ensureLiteralInt(el, 'FillGradientDir', _gradientDirFor(eg));
    scrubbed |=
        _ensureLiteralLength(el, 'FillGradientAngle', eg.angleRad);
    scrubbed |= _scrubGradientStopInh(el, 'FillGradient', eg);
    return scrubbed;
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
            _gradientDirFor(eg).toString());
        _writeValue(_ensureCell(el, 'LineGradientAngle'), _fmt(eg.angleRad));
        _insertBeforeTextOrShapes(el, _buildLineGradientSection(eg));
      } else {
        _writeValue(_ensureCell(el, 'LineGradientEnabled'), '0');
        _removeNamedCells(
            el, const ['LineGradientDir', 'LineGradientAngle']);
      }
      return true;
    }
    if (eg == null || eg.stops.isEmpty) {
      var changed = false;
      final residual = <XmlElement>[
        for (final child in el.childElements)
          if (child.name.local == 'Section' &&
              child.getAttribute('N') == 'LineGradient')
            child,
      ];
      for (final s in residual) {
        el.children.remove(s);
        changed = true;
      }
      changed |= _ensureLiteralInt(el, 'LineGradientEnabled', 0);
      changed |= _removeNamedCells(
          el, const ['LineGradientDir', 'LineGradientAngle']);
      return changed;
    }
    var scrubbed = _scrubEnabledFlagCell(el, 'LineGradientEnabled');
    scrubbed |=
        _ensureLiteralInt(el, 'LineGradientDir', _gradientDirFor(eg));
    scrubbed |=
        _ensureLiteralLength(el, 'LineGradientAngle', eg.angleRad);
    scrubbed |= _scrubGradientStopInh(el, 'LineGradient', eg);
    return scrubbed;
  }

  /// Scrub F=Inh on FillGradient / LineGradient stop cells while the model
  /// gradient is unchanged.
  bool _scrubGradientStopInh(
      XmlElement el, String sectionName, VsdxGradient eg) {
    XmlElement? section;
    for (final s in el.childElements) {
      if (s.name.local == 'Section' && s.getAttribute('N') == sectionName) {
        section = s;
        break;
      }
    }
    if (section == null) return false;
    final rows = _rowsOf(section);
    var changed = false;
    for (var i = 0; i < eg.stops.length && i < rows.length; i++) {
      final stop = eg.stops[i];
      final row = rows[i];
      changed |= _writeValueIfNeeded(
          _ensureCell(row, 'GradientStopPosition'), _fmt(stop.position));
      if (stop.color != null) {
        changed |= _writeValueIfNeeded(
            _ensureCell(row, 'GradientStopColor'), _hex(stop.color!));
      } else if (stop.themeColorIndex != null) {
        final cell = _ensureCell(row, 'GradientStopColor');
        if (cell.getAttribute('F') != 'THEMEVAL()' ||
            cell.getAttribute('V') != stop.themeColorIndex.toString()) {
          _writeValue(cell, stop.themeColorIndex.toString(),
              preserveFormula: true);
          cell.setAttribute('F', 'THEMEVAL()');
          changed = true;
        } else if (isInhFormula(cell.getAttribute('F'))) {
          cell.setAttribute('F', 'THEMEVAL()');
          changed = true;
        }
      }
      if (stop.transparency > _epsilon ||
          _findCell(row, 'GradientStopColorTrans') != null) {
        changed |= _writeValueIfNeeded(
            _ensureCell(row, 'GradientStopColorTrans'),
            _fmt(stop.transparency));
      }
    }
    return changed;
  }

  /// When the model has a flag on, force literal `V=1` without `F=` so
  /// stylesheet `Inh` cannot replace the local enable bit.
  bool _scrubEnabledFlagCell(XmlElement shape, String cell) {
    final c = _findCell(shape, cell);
    if (c == null) {
      _writeValue(_ensureCell(shape, cell), '1');
      return true;
    }
    final f = c.getAttribute('F');
    final v = c.getAttribute('V');
    final already =
        (v == '1' || v == '1.0') && (f == null || f.isEmpty);
    if (already) return false;
    _writeValue(c, '1');
    return true;
  }

  static bool _gradientsEqual(VsdxGradient? a, VsdxGradient? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a.type != b.type ||
        _gradientDirFor(a) != _gradientDirFor(b) ||
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
        // MS FillGradientDir / LineGradientDir canonical defaults.
        VsdxGradientType.linear => 0,
        VsdxGradientType.radial => 4, // mid of 1–7 (centre-ish)
        VsdxGradientType.rectangular => 10, // mid of 8–12
        VsdxGradientType.path => 13,
      };

  static int _gradientDirFor(VsdxGradient g) =>
      g.dir ?? _gradientDirFromType(g.type);

  /// Patch text-block transform cells so TxtPin / TxtWidth / TxtAngle / margins
  /// survive a save (parser already reads them; previously only VerticalAlign
  /// was written back).
  ///
  /// Width*/Height* formulas are preserved only when they still evaluate to the
  /// edited cache value — otherwise absolute caption placement (e.g. icon
  /// label below the picture) would snap back on resize / reopen.
  bool _patchTextBlock(
    XmlElement el,
    VsdxTextBlock base,
    VsdxTextBlock edited,
    VsdxShape shape,
  ) {
    // Rewrite negative TxtPinY to pin@0 + LocPin=TxtHeight so EdrawMax keeps
    // captions below the glyph (it clamps / ignores negative pins).
    if (!preserveTextBlockCoordinates) {
      edited = _edrawSafeCaptionBelow(edited);
    }
    var changed = false;
    changed |= _patchNullableLength(
      el,
      'TxtPinX',
      base.pinXInches,
      edited.pinXInches,
      preserveFormula:
          _preserveTxtLengthFormula(el, 'TxtPinX', edited.pinXInches, shape),
    );
    changed |= _patchNullableLength(
      el,
      'TxtPinY',
      base.pinYInches,
      edited.pinYInches,
      preserveFormula:
          _preserveTxtLengthFormula(el, 'TxtPinY', edited.pinYInches, shape),
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
      preserveFormula:
          _preserveTxtLengthFormula(el, 'TxtWidth', edited.widthInches, shape),
    );
    changed |= _patchNullableLength(
      el,
      'TxtHeight',
      base.heightInches,
      edited.heightInches,
      preserveFormula: _preserveTxtLengthFormula(
          el, 'TxtHeight', edited.heightInches, shape),
    );
    changed |=
        _patchAngle(el, 'TxtAngle', base.angleRad, edited.angleRad);
    // Scrub F=Inh / ensure cell even when angle stays 0 (Master π/2 revive).
    // Do not re-apply formulas['TxtAngle']=Inh via sync below.
    if (_nonInhFormula(shape.formulas['TxtAngle']) == null) {
      changed |= _ensureLiteralLength(el, 'TxtAngle', edited.angleRad);
    }
    // Same for TxtPin*/Width/Height when model holds a literal (no SETATREF…).
    for (final entry in <(String, double?)>[
      ('TxtPinX', edited.pinXInches),
      ('TxtPinY', edited.pinYInches),
      ('TxtLocPinX', edited.locPinXInches),
      ('TxtLocPinY', edited.locPinYInches),
      ('TxtWidth', edited.widthInches),
      ('TxtHeight', edited.heightInches),
    ]) {
      final v = entry.$2;
      if (v == null) continue;
      if (_nonInhFormula(shape.formulas[entry.$1]) != null) continue;
      changed |= _ensureLiteralLength(el, entry.$1, v);
    }
    changed |= _patchInt(el, 'VerticalAlign', _vAlignInt(base.verticalAlign),
        _vAlignInt(edited.verticalAlign));
    // Model verticalAlign is authoritative — scrub F=Inh even when value matches.
    changed |= _ensureLiteralInt(
        el, 'VerticalAlign', _vAlignInt(edited.verticalAlign));
    changed |= _patchInt(
        el, 'HideText', base.hideText ? 1 : 0, edited.hideText ? 1 : 0);
    changed |= _ensureLiteralInt(el, 'HideText', edited.hideText ? 1 : 0);
    changed |= _patchInt(
        el, 'TextDirection', base.textDirection, edited.textDirection);
    changed |= _ensureLiteralInt(el, 'TextDirection', edited.textDirection);
    changed |= _patchLength(el, 'DefaultTabStop', base.defaultTabStopInches,
        edited.defaultTabStopInches);
    changed |= _ensureLiteralLength(
        el, 'DefaultTabStop', edited.defaultTabStopInches);
    final textBkgndFormula = (_cellFormula(el, 'TextBkgnd') ?? '').trim();
    final preserveTextBkgndFormula =
        base.backgroundColor?.value == edited.backgroundColor?.value &&
            textBkgndFormula.isNotEmpty &&
            !isInhFormula(textBkgndFormula);
    if (edited.backgroundColor != null) {
      changed |= _patchColor(
          el, 'TextBkgnd', base.backgroundColor, edited.backgroundColor);
      if (!preserveTextBkgndFormula) {
        changed |=
            _ensureLiteralColor(el, 'TextBkgnd', edited.backgroundColor!);
      }
    } else if (!preserveTextBkgndFormula) {
      // Always literal 0 when transparent — scrub F=Inh / match rebuild.
      final c = _ensureCell(el, 'TextBkgnd');
      if (c.getAttribute('V') != '0' ||
          (c.getAttribute('F') ?? '').isNotEmpty) {
        _writeValue(c, '0');
        changed = true;
      }
    }
    changed |= _patchRatio(
        el,
        'TextBkgndTrans',
        base.backgroundTransparency,
        edited.backgroundTransparency);
    changed |= _ensureLiteralLength(
        el, 'TextBkgndTrans', edited.backgroundTransparency);
    changed |= _patchLength(
        el, 'LeftMargin', base.marginLeftInches, edited.marginLeftInches);
    changed |=
        _ensureLiteralLength(el, 'LeftMargin', edited.marginLeftInches);
    changed |= _patchLength(
        el, 'RightMargin', base.marginRightInches, edited.marginRightInches);
    changed |=
        _ensureLiteralLength(el, 'RightMargin', edited.marginRightInches);
    changed |= _patchLength(
        el, 'TopMargin', base.marginTopInches, edited.marginTopInches);
    changed |= _ensureLiteralLength(el, 'TopMargin', edited.marginTopInches);
    changed |= _patchLength(
        el, 'BottomMargin', base.marginBottomInches, edited.marginBottomInches);
    changed |=
        _ensureLiteralLength(el, 'BottomMargin', edited.marginBottomInches);
    // Honour the *edited* model for Txt* F= (like Begin/End): clearing
    // formulas in setIconCaptionBelow must scrub SETATREF/TEXTWIDTH/Height*
    // from XML even when V= is unchanged. Never re-emit Master F=Inh.
    changed |= _syncCellFormulaAttr(
        el, 'TxtPinX', _nonInhFormula(shape.formulas['TxtPinX']));
    changed |= _syncCellFormulaAttr(
        el, 'TxtPinY', _nonInhFormula(shape.formulas['TxtPinY']));
    changed |= _syncCellFormulaAttr(
        el, 'TxtWidth', _nonInhFormula(shape.formulas['TxtWidth']));
    changed |= _syncCellFormulaAttr(
        el, 'TxtHeight', _nonInhFormula(shape.formulas['TxtHeight']));
    changed |= _syncCellFormulaAttr(
        el, 'TxtLocPinX', _nonInhFormula(shape.formulas['TxtLocPinX']));
    changed |= _syncCellFormulaAttr(
        el, 'TxtLocPinY', _nonInhFormula(shape.formulas['TxtLocPinY']));
    changed |= _syncCellFormulaAttr(
        el, 'TxtAngle', _nonInhFormula(shape.formulas['TxtAngle']));
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
    if (!preserveTextBlockCoordinates) {
      b = _edrawSafeCaptionBelow(b);
    }
    void addLen(String name, double? v, {String? defaultFormula, double? fallback}) {
      var f = _nonInhFormula(formulas[name]) ?? defaultFormula;
      final value = v ?? fallback;
      if (value == null && f == null) return;
      // Stale Width*/Height* (or any parametric that no longer matches V) must
      // not be re-emitted — absolute caption pins would otherwise revive.
      if (f != null &&
          value != null &&
          shapeForDefaults != null &&
          !_txtFormulaAgreesWithValue(f, value, shapeForDefaults)) {
        f = null;
      }
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
    // Always emit TxtAngle (incl. 0) so Master text rotation cannot revive
    // after an explicit upright override + group rebuild.
    children.add(_cell(
      'TxtAngle',
      _fmt(b.angleRad),
      formula: _nonInhFormula(formulas['TxtAngle']),
    ));
    // Always emit VerticalAlign (incl. middle) so StyleSheet / Master cannot
    // revive a non-middle align after clear + group rebuild — mirrors HideText.
    children.add(
        _cell('VerticalAlign', _vAlignInt(b.verticalAlign).toString()));
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
    // Always emit model margins (patch force-writes them). Do not rewrite the
    // Visio default 0.04" to Edraw's ~4pt (0.055…) — that corrupted rebuilds.
    children
      ..add(_cell('LeftMargin', _fmt(b.marginLeftInches)))
      ..add(_cell('RightMargin', _fmt(b.marginRightInches)))
      ..add(_cell('TopMargin', _fmt(b.marginTopInches)))
      ..add(_cell('BottomMargin', _fmt(b.marginBottomInches)));
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
  /// Creates the cell when missing so Master effects cannot stay invisible.
  bool _forceLiteralZeroLength(XmlElement shape, String cell) {
    final c = _ensureCell(shape, cell);
    final f = c.getAttribute('F');
    final v = c.getAttribute('V');
    final already =
        (v == '0' || v == '0.0') && (f == null || f.isEmpty);
    if (already) return false;
    _writeValue(c, '0');
    return true;
  }

  /// Ensure an int cell exists as literal [value] without `F=`.
  bool _ensureLiteralInt(XmlElement shape, String cell, int value) {
    final c = _ensureCell(shape, cell);
    final f = c.getAttribute('F');
    final v = c.getAttribute('V');
    final want = value.toString();
    final already = v == want && (f == null || f.isEmpty);
    if (already) return false;
    _writeValue(c, want);
    return true;
  }

  /// Ensure a length cell exists as literal [value] without `F=`.
  bool _ensureLiteralLength(XmlElement shape, String cell, double value) {
    final c = _ensureCell(shape, cell);
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

  /// Ensure an int cell is literal [value] without `F=` (scrub Inh / stale F).
  /// No-op when the cell is absent (use [_ensureLiteralInt] to inject).
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

  /// Ensure a colour cell exists as literal hex without `F=`.
  bool _ensureLiteralColor(XmlElement shape, String cell, VsdxColor color) {
    final c = _ensureCell(shape, cell);
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

  /// Ensure a colour cell is literal hex without `F=`.
  /// No-op when the cell is absent (use [_ensureLiteralColor] to inject).
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
    // Inh follows Master — never preserve across a local V= write.
    if (formula == 'Inh') return false;
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
  /// Scrubs residual LockMove* F=Inh; leaves fine-grained Visio locks opaque
  /// when the shape stays unlocked (LockTextEdit / LockWidth / …).
  bool _patchLock(XmlElement el, VsdxShape base, VsdxShape edited) {
    if (base.locked == edited.locked) {
      var changed = false;
      if (edited.locked) {
        for (final name in _lockCells) {
          changed |= _ensureLiteralInt(el, name, 1);
        }
      } else {
        // Ensure (not force) so missing LockMove* cells are injected — Master
        // LockMoveX can otherwise revive after unlock + pin-only save.
        changed |= _ensureLiteralInt(el, 'LockMoveX', 0);
        changed |= _ensureLiteralInt(el, 'LockMoveY', 0);
      }
      return changed;
    }
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
      final v = cell?.getAttribute('V') ?? '0';
      if (cell == null ||
          v == '0' ||
          isInhFormula(cell.getAttribute('F'))) {
        changed |= _ensureLiteralInt(
          el,
          'BeginArrowSize',
          _arrowSizeToBucket(s.line.beginArrowSizeInches),
        );
      }
    }
    if (s.line.endArrow != 0) {
      final cell = _findCell(el, 'EndArrowSize');
      final v = cell?.getAttribute('V') ?? '0';
      if (cell == null ||
          v == '0' ||
          isInhFormula(cell.getAttribute('F'))) {
        changed |= _ensureLiteralInt(
          el,
          'EndArrowSize',
          _arrowSizeToBucket(s.line.endArrowSizeInches),
        );
      }
    }
    return changed;
  }

  /// Write model Connection points when a 2-D shape has none in XML.
  /// Does **not** invent defaults — an intentional empty list (user deleted
  /// every blue point) must survive a second save / group rebuild.
  bool _ensureConnectionPoints(XmlElement el, VsdxShape s) {
    if (s.is1D) return false;
    if (el.getAttribute('Master') != null ||
        el.getAttribute('MasterShape') != null) {
      return false;
    }
    if (s.connectionPoints.isEmpty) return false;
    for (final child in el.childElements) {
      if (child.name.local == 'Section' &&
          child.getAttribute('N') == 'Connection') {
        return false;
      }
    }
    el.children.add(_buildConnectionSection(s.connectionPoints));
    return true;
  }

  /// Write Edraw-default connector dynamics when a 1-D **connector** lacks them.
  /// Skips freehand ink (`ObjType=1`) which uses an AABB local frame, not the
  /// Visio Begin-origin Width=EndX-BeginX convention.
  bool _ensureConnectorDynamics(
    XmlElement el,
    VsdxShape base,
    VsdxShape s,
  ) {
    if (!s.is1D) return false;
    // Freehand / ink strokes are 1-D but not glueable connectors.
    if (s.objType != null && s.objType != 2) return false;
    var changed = false;
    // Inject missing cells *and* scrub residual F=Inh on present ones.
    void put(String name, String value) {
      final cell = _ensureCell(el, name);
      if (cell.getAttribute('V') != value ||
          (cell.getAttribute('F') ?? '').isNotEmpty) {
        _writeValue(cell, value);
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
    put('ShdwPattern', s.shadow.xmlPattern.toString());
    // Honour model NoAlignBox / ShapeSplittable / NoLiveDynamics (do not force
    // Edraw defaults over cleared false — rebuild already emits literal 0/1).
    final noLive = s.connectorProps?.noLiveDynamics ?? true;
    for (final entry in <(String, String)>[
      ('NoAlignBox', s.noAlignBox ? '1' : '0'),
      ('ShapeSplittable', s.shapeSplittable ? '1' : '0'),
      ('NoLiveDynamics', noLive ? '1' : '0'),
    ]) {
      final cell = _ensureCell(el, entry.$1);
      if (cell.getAttribute('V') != entry.$2 ||
          cell.getAttribute('F') != null) {
        _writeValue(cell, entry.$2);
        changed = true;
      }
    }
    // Pin centred on Begin/End — Edraw samples always carry these formulas.
    void putPinFormula(
      String name,
      String fallback,
      double value, {
      required bool relationHolds,
      required bool modelUnchanged,
    }) {
      // Equal-path saves preserve original SQRT/GUARD/DL/Inh formulas.
      // Missing cells are still healed below for old Edraw exports.
      if (modelUnchanged && _findCell(el, name) != null) return;
      final cell = _ensureCell(el, name);
      if (!relationHolds) {
        final parsed = double.tryParse(cell.getAttribute('V') ?? '');
        if (cell.getAttribute('F') != null ||
            parsed == null ||
            (parsed - value).abs() > _epsilon) {
          _writeValue(cell, _fmt(value));
          changed = true;
        }
        return;
      }
      final formula = _nonInhFormula(s.formulas[name]) ?? fallback;
      if (cell.getAttribute('F') != formula) {
        cell.setAttribute('F', formula);
        changed = true;
      }
      if (cell.getAttribute('V') == null) {
        cell.setAttribute('V', _fmt(value));
        changed = true;
      }
    }

    final bx = s.beginX ?? 0;
    final by = s.beginY ?? 0;
    final ex = s.endX ?? 0;
    final ey = s.endY ?? 0;
    putPinFormula(
      'PinX',
      '(BeginX+EndX)*0.5',
      s.pinX,
      relationHolds: (s.pinX - (bx + ex) * 0.5).abs() <= _epsilon,
      modelUnchanged: (base.pinX - s.pinX).abs() <= _epsilon,
    );
    putPinFormula(
      'PinY',
      '(BeginY+EndY)*0.5',
      s.pinY,
      relationHolds: (s.pinY - (by + ey) * 0.5).abs() <= _epsilon,
      modelUnchanged: (base.pinY - s.pinY).abs() <= _epsilon,
    );
    // Visio 1-D size / LocPin — required so Geometry rooted at Begin (0,0)
    // places correctly when Width/Height are signed End−Begin deltas.
    final dx = ex - bx;
    final dy = ey - by;
    putPinFormula(
      'Width',
      'EndX-BeginX',
      s.width,
      relationHolds: (s.width - dx).abs() <= _epsilon,
      modelUnchanged: (base.width - s.width).abs() <= _epsilon,
    );
    putPinFormula(
      'Height',
      'EndY-BeginY',
      s.height,
      relationHolds: (s.height - dy).abs() <= _epsilon,
      modelUnchanged: (base.height - s.height).abs() <= _epsilon,
    );
    putPinFormula(
      'LocPinX',
      '(EndX-BeginX)/2',
      s.effectiveLocPinX,
      relationHolds: (s.effectiveLocPinX - dx * 0.5).abs() <= _epsilon,
      modelUnchanged:
          (base.effectiveLocPinX - s.effectiveLocPinX).abs() <= _epsilon,
    );
    putPinFormula(
      'LocPinY',
      '(EndY-BeginY)/2',
      s.effectiveLocPinY,
      relationHolds: (s.effectiveLocPinY - dy * 0.5).abs() <= _epsilon,
      modelUnchanged:
          (base.effectiveLocPinY - s.effectiveLocPinY).abs() <= _epsilon,
    );
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
      final wantShow = g?.noShow ?? false;
      final wantSnap = g?.noSnap ?? false;
      final wantQuick = g?.noQuickDrag ?? false;
      changed |= _syncGeometryFlagCell(section, 'NoFill', wantFill);
      changed |= _syncGeometryFlagCell(section, 'NoLine', wantLine);
      // Scrub F=Inh on companions rebuild always emits as literals.
      changed |= _syncGeometryFlagCell(section, 'NoShow', wantShow);
      changed |= _syncGeometryFlagCell(section, 'NoSnap', wantSnap);
      changed |= _syncGeometryFlagCell(section, 'NoQuickDrag', wantQuick);
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
      final modelF = _nonInhFormula(s.formulas[entry.$1]);
      final curF = cell.getAttribute('F');
      if (modelF != null) {
        // Preserve parametric crop offsets (Width*0.1, …); only refresh V=.
        if (cell.getAttribute('V') != next) {
          cell.setAttribute('V', next);
          changed = true;
        }
        if (curF != modelF) {
          cell.setAttribute('F', modelF);
          changed = true;
        }
      } else if (cell.getAttribute('V') != next ||
          (curF != null && curF.isNotEmpty)) {
        // Absolute offset — scrub F=Inh / stale formulas.
        _writeValue(cell, next);
        changed = true;
      }
    }
    for (final entry in <(String, double, String, double, String?, double?)>[
      (
        'ImgWidth',
        s.effectiveImgWidth,
        'Width*1',
        s.width,
        s.formulas['ImgWidth'],
        s.imgWidthInches,
      ),
      (
        'ImgHeight',
        s.effectiveImgHeight,
        'Height*1',
        s.height,
        s.formulas['ImgHeight'],
        s.imgHeightInches,
      ),
    ]) {
      final cell = _ensureCell(el, entry.$1);
      final defaultF = entry.$3;
      final defaultFNorm = defaultF.replaceAll(' ', '');
      final shapeSize = entry.$4;
      final modelF = _nonInhFormula(entry.$5);
      final explicit = entry.$6;
      final curF = (cell.getAttribute('F') ?? '').replaceAll(' ', '');
      final modelIsCustom = modelF != null &&
          modelF.replaceAll(' ', '') != defaultFNorm;
      // Full-frame when model says so, or when size is implicit / matches the
      // box. Empty F= with V≠size is an absolute crop — do NOT invent Width*1.
      final modelIsDefault = !modelIsCustom &&
          (modelF == null
              ? (explicit == null ||
                  (explicit - shapeSize).abs() <= _epsilon)
              : true);
      // F=Inh alone must not force full-frame when the model holds a crop —
      // scrub Inh to a literal V= instead (below).
      final treatAsDefault = modelIsDefault;
      if (modelIsCustom) {
        final next = _fmt(entry.$2);
        if (cell.getAttribute('V') != next) {
          cell.setAttribute('V', next);
          changed = true;
        }
        if (cell.getAttribute('F') != modelF) {
          cell.setAttribute('F', modelF);
          changed = true;
        }
      } else if (treatAsDefault) {
        final next = _fmt(shapeSize);
        if (cell.getAttribute('V') != next) {
          cell.setAttribute('V', next);
          changed = true;
        }
        if (curF != defaultFNorm) {
          cell.setAttribute('F', defaultF);
          changed = true;
        }
      } else {
        final next = _fmt(entry.$2);
        if (cell.getAttribute('V') != next || curF.isNotEmpty) {
          _writeValue(cell, next);
          changed = true;
        }
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
      // Scrub F=Inh so Master tone cannot override cleared/edited values.
      if (cell.getAttribute('V') != next || cell.getAttribute('F') != null) {
        _writeValue(cell, next);
        changed = true;
      }
    }
    return changed;
  }

  /// Keep `<ForeignData ForeignType=… CompressionType=…>` in sync on the
  /// patch path (rebuild already emits them from the model).
  bool _syncForeignDataAttrs(XmlElement el, VsdxShape s) {
    XmlElement? foreign;
    for (final c in el.childElements) {
      if (c.name.local == 'ForeignData') {
        foreign = c;
        break;
      }
    }
    if (foreign == null) return false;
    final part = s.imagePartName;
    final wantType = s.foreignType ??
        VsdxImage.foreignTypeFor(
          mimeType: '',
          partName: part ?? '',
        );
    final wantCompression = _vsdxCompressionFor(s, wantType, part);
    var changed = false;
    if (foreign.getAttribute('ForeignType') != wantType) {
      foreign.setAttribute('ForeignType', wantType);
      changed = true;
    }
    if (wantCompression == null) {
      if (foreign.getAttribute('CompressionType') != null) {
        foreign.removeAttribute('CompressionType');
        changed = true;
      }
    } else if (foreign.getAttribute('CompressionType') != wantCompression) {
      foreign.setAttribute('CompressionType', wantCompression);
      changed = true;
    }
    return changed;
  }

  /// VDX stores an uncompressed Bitmap as a headerless DIB, whereas an OPC
  /// image part contains a complete BMP file. libvisio interprets an explicit
  /// `CompressionType="None"` as the former and prepends a BMP header. Omit
  /// that legacy marker after the payload has been normalised for VSDX so a
  /// VDX -> VSDX round-trip does not acquire a second, invalid file header.
  static String? _vsdxCompressionFor(
      VsdxShape shape, String foreignType, String? part) {
    final explicit = shape.foreignCompressionType;
    if (explicit != null && explicit.toLowerCase() == 'none') return null;
    return explicit ??
        (foreignType == 'Bitmap'
            ? VsdxImage.compressionTypeFor(
                mimeType: '',
                partName: part ?? '',
              )
            : null);
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
    // Match Visio / VsdxTextBlock defaults (0.04"), not Edraw's ~4pt rewrite.
    final tb = s.richText.textBlock;
    for (final entry in <(String, double)>[
      ('LeftMargin', tb.marginLeftInches),
      ('RightMargin', tb.marginRightInches),
      ('TopMargin', tb.marginTopInches),
      ('BottomMargin', tb.marginBottomInches),
    ]) {
      if (!_hasCell(el, entry.$1)) {
        _writeValue(_ensureCell(el, entry.$1), _fmt(entry.$2));
      }
    }
    // Our canvas centres plain labels when Paragraph/HorzAlign is missing.
    // Preserve an explicit left (0) / right (2) / justify (3) already in XML.
    _ensureParagraphHorzAlignForTextBox(el, s);
    return true;
  }

  /// When synthesising a text box, set Paragraph/HorzAlign from the model if
  /// the cell is missing. Never upgrade an explicit left (0) to center.
  bool _ensureParagraphHorzAlignForTextBox(XmlElement el, VsdxShape s) {
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
    // Keep any explicit alignment already written.
    if (cur == '0' || cur == '1' || cur == '2' || cur == '3' || cur == '4') {
      return false;
    }
    final modelAlign = s.richText.runs.isNotEmpty
        ? s.richText.runs.first.paraStyle.horizontalAlign
        : VsdxHorzAlign.center;
    final want = switch (modelAlign) {
      VsdxHorzAlign.left => '0',
      VsdxHorzAlign.right => '2',
      VsdxHorzAlign.justify => '3',
      VsdxHorzAlign.full => '4',
      VsdxHorzAlign.center => '1',
    };
    cell.setAttribute('V', want);
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
    bool unresolvedWalkGlue(String name, double? value) =>
        value != null &&
        value.abs() <= _epsilon &&
        s.formulas[name]?.toUpperCase().contains('_WALKGLUE') == true;
    final retainConnectorFrame = s.is1D &&
        unresolvedWalkGlue('BeginX', s.beginX) &&
        unresolvedWalkGlue('BeginY', s.beginY) &&
        unresolvedWalkGlue('EndX', s.endX) &&
        unresolvedWalkGlue('EndY', s.endY);
    // --- XForm ---------------------------------------------------------------
    final children = <XmlNode>[
      _cell('PinX', _fmt(s.pinX), formula: _nonInhFormula(s.formulas['PinX'])),
      _cell('PinY', _fmt(s.pinY), formula: _nonInhFormula(s.formulas['PinY'])),
      _cell('Width', _fmt(s.width),
          formula: _nonInhFormula(s.formulas['Width'])),
      _cell('Height', _fmt(s.height),
          formula: _nonInhFormula(s.formulas['Height'])),
    ];
    // Always emit LocPin. Visio's *formula* default is Width/2, Height/2, but
    // when the cells are absent Edraw / libvisio fall back to (0,0) (= pin at
    // the shape's bottom-left), shifting every centred shape by half its size.
    // Writing the cells (with Width*0.5 / Height*0.5 when centred) keeps
    // exports aligned with how this editor and Visio place the pin.
    // One exception is an unresolved VDX WALKGLUE route: its literal LocPin
    // belongs to the retained master frame, and recalculating it collapses the
    // cached Geometry in LibreOffice.
    final locPinXF = _nonInhFormula(s.formulas['LocPinX']) ??
        (!retainConnectorFrame &&
                (s.effectiveLocPinX - s.width / 2).abs() <= _epsilon
            ? 'Width*0.5'
            : null);
    final locPinYF = _nonInhFormula(s.formulas['LocPinY']) ??
        (!retainConnectorFrame &&
                (s.effectiveLocPinY - s.height / 2).abs() <= _epsilon
            ? 'Height*0.5'
            : null);
    children
      ..add(_cell('LocPinX', _fmt(s.effectiveLocPinX), formula: locPinXF))
      ..add(_cell('LocPinY', _fmt(s.effectiveLocPinY), formula: locPinYF));
    children.add(_cell('Angle', _fmt(s.angleRad),
        formula: _nonInhFormula(s.formulas['Angle'])));
    // Always emit Flip* (incl. 0) so Master FlipX cannot revive after clear.
    children
      ..add(_cell('FlipX', s.flipX ? '1' : '0'))
      ..add(_cell('FlipY', s.flipY ? '1' : '0'));
    if (s.is1D) {
      children
        ..add(_cell('BeginX', _fmt(s.beginX ?? 0),
            formula: _nonInhFormula(s.formulas['BeginX'])))
        ..add(_cell('BeginY', _fmt(s.beginY ?? 0),
            formula: _nonInhFormula(s.formulas['BeginY'])))
        ..add(_cell('EndX', _fmt(s.endX ?? 0),
            formula: _nonInhFormula(s.formulas['EndX'])))
        ..add(_cell('EndY', _fmt(s.endY ?? 0),
            formula: _nonInhFormula(s.formulas['EndY'])));
    }
    final cp = s.connectorProps;
    if (cp != null && !cp.isEmpty) {
      if (cp.begTrigger != null || s.formulas.containsKey('BegTrigger')) {
        children.add(_cell('BegTrigger', cp.begTrigger ?? '0',
            formula: _nonInhFormula(s.formulas['BegTrigger'])));
      }
      if (cp.endTrigger != null || s.formulas.containsKey('EndTrigger')) {
        children.add(_cell('EndTrigger', cp.endTrigger ?? '0',
            formula: _nonInhFormula(s.formulas['EndTrigger'])));
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
      // Always emit NoLiveDynamics (incl. 0) so Master cannot revive it.
      children.add(_cell('NoLiveDynamics', cp.noLiveDynamics ? '1' : '0'));
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
      // Drop F=Inh; keep real XFTRIGGER formulas only.
      if (s.formulas.containsKey('BegTrigger')) {
        children.add(_cell('BegTrigger', '0',
            formula: _nonInhFormula(s.formulas['BegTrigger'])));
      }
      if (s.formulas.containsKey('EndTrigger')) {
        children.add(_cell('EndTrigger', '0',
            formula: _nonInhFormula(s.formulas['EndTrigger'])));
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
    // Always emit LayerMember (incl. empty) so clearing layers survives
    // group rebuild — absent cell would re-inherit Master membership.
    children.add(_cell('LayerMember', s.layerMemberIds.join(';')));
    // --- Effects / text block ------------------------------------------------
    if (s.shadow.enabled) {
      children.add(_cell('ShadowPattern', s.shadow.xmlPattern.toString()));
      children.add(_cell('ShdwPattern', s.shadow.xmlPattern.toString()));
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
      // explicitly disables it. Emit both aliases + companions (patch does),
      // including Foregnd/theme so toggle-off → rebuild → reopen restores colour.
      children
        ..add(_cell('ShadowPattern', '0'))
        ..add(_cell('ShdwPattern', '0'));
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
      // Size=0 disables; keep colour/theme companions for re-enable after rebuild.
      children.add(_cell('GlowSize', '0'));
      if (s.glow.color != null) {
        children.add(_cell('GlowColor', _hex(s.glow.color!)));
      } else if (s.glow.themeColorIndex != null) {
        children.add(_cell('GlowColor', '0', formula: 'THEMEVAL()'));
        children.add(_cell(
            'QuickStyleEffectColor', s.glow.themeColorIndex!.toString()));
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
    } else {
      // Size=0 disables; keep companions for re-enable after rebuild.
      children
        ..add(_cell('ReflectionSize', '0'))
        ..add(_cell('ReflectionDist', _fmt(s.reflection.distanceInches)))
        ..add(_cell(
            'ReflectionTransparency', _fmt(s.reflection.transparency)))
        ..add(_cell('ReflectionBlur', _fmt(s.reflection.blurInches)));
    }
    if (s.fill.gradient != null && s.fill.gradient!.stops.isNotEmpty) {
      children
        ..add(_cell('FillGradientEnabled', '1'))
        ..add(_cell('FillGradientDir',
            _gradientDirFor(s.fill.gradient!).toString()))
        ..add(_cell('FillGradientAngle', _fmt(s.fill.gradient!.angleRad)));
    } else {
      children.add(_cell('FillGradientEnabled', '0'));
    }
    if (s.line.gradient != null && s.line.gradient!.stops.isNotEmpty) {
      children
        ..add(_cell('LineGradientEnabled', '1'))
        ..add(_cell('LineGradientDir',
            _gradientDirFor(s.line.gradient!).toString()))
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
        formula: _nonInhFormula(s.formulas['EventDblClick']),
      ));
    }
    for (final name in const <String>['TheText', 'EventXFMod', 'EventDrop']) {
      final formula = _nonInhFormula(s.formulas[name]);
      if (formula != null) {
        children.add(_cell(name, '0', formula: formula));
      }
    }
    children
      ..add(_cell('NoAlignBox', s.noAlignBox ? '1' : '0'))
      ..add(_cell('ShapeSplittable', s.shapeSplittable ? '1' : '0'));
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
    children
      ..add(_cell('IsTextEditTarget', s.isTextEditTarget ? '1' : '0'))
      ..add(_cell('DontMoveChildren', s.dontMoveChildren ? '1' : '0'));
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
    // Emit edge glue points so 万兴图示 attaches connectors at mid-sides.
    // Honour intentional empty lists (do not re-inject defaults after clear).
    if (s.connectionPoints.isNotEmpty) {
      children.add(_buildConnectionSection(s.connectionPoints));
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
    // AsianFont / ComplexScriptFont: honour cleared null (patch deletes these).
    // Only inject Edraw defaults for CJK text that still has no asian face.
    if (c.asianFont != null && c.asianFont!.isNotEmpty) {
      cells.add(_cell('AsianFont', c.asianFont!));
    } else if (cjk) {
      cells.add(_cell('AsianFont', _defaultAsianFont));
    }
    if (c.fontFamily != null && c.fontFamily!.isNotEmpty) {
      cells.add(_cell('Font', c.fontFamily!));
    } else if (cjk) {
      cells.add(_cell('Font', _defaultAsianFont));
    }
    if (c.complexScriptFont != null && c.complexScriptFont!.isNotEmpty) {
      cells.add(_cell('ComplexScriptFont', c.complexScriptFont!));
    } else if (cjk) {
      final asianFace = (c.asianFont != null && c.asianFont!.isNotEmpty)
          ? c.asianFont!
          : _defaultAsianFont;
      cells.add(_cell('ComplexScriptFont', asianFace));
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
      ..add(_cell('ColorTrans', _fmt(c.transparency)))
      ..add(_cell('FontScale', _fmt(c.fontScale)));
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
    // Align with [_writeParaRow]: always emit managed cells (incl. 0) so
    // cleared spacing / bullets cannot revive via Master on group rebuild.
    return <XmlNode>[
      _cell('HorzAlign', _alignToInt(p.horizontalAlign).toString()),
      _cell('IndFirst', _fmt(p.indentFirstInches)),
      _cell('IndLeft', _fmt(p.indentLeftInches)),
      _cell('IndRight', _fmt(p.indentRightInches)),
      _cell('SpBefore', _fmt(p.spaceBeforeInches)),
      _cell('SpAfter', _fmt(p.spaceAfterInches)),
      _cell('SpLine', _fmt(_spLineValue(p) ?? -1)),
      _cell('Bullet', p.bullet.toString()),
      if (p.bulletStr != null) _cell('BulletStr', p.bulletStr!),
      if (p.bulletFont != null) _cell('BulletFont', p.bulletFont!),
      if (p.bulletFontSizeInches != null)
        _cell('BulletFontSize', _fmt(p.bulletFontSizeInches!)),
      _cell('TextPosAfterBullet', _fmt(p.textPosAfterBulletInches)),
      _cell('Flags', p.flags.toString()),
    ];
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
              _cell('Position${i + 1}', _fmt(set.stops[i].positionInches)),
              _cell('Alignment${i + 1}', set.stops[i].alignment.toString()),
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
    'ObjType', 'ResizeMode', 'TheText', 'EventDblClick', 'EventXFMod',
    'EventDrop', 'NoAlignBox', 'ShapeSplittable',
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
    final compression = _vsdxCompressionFor(s, foreignType, part);
    final bgSlot = s.fill.themeBackgroundIndex;
    final fgSlot = s.fill.themeForegroundIndex;
    final namedBg = (bgSlot != null && fgSlot != null && fgSlot != bgSlot)
        ? ThemeSlot.themeValName(bgSlot)
        : null;
    final children = <XmlNode>[
      _cell('PinX', _fmt(s.pinX), formula: _nonInhFormula(s.formulas['PinX'])),
      _cell('PinY', _fmt(s.pinY), formula: _nonInhFormula(s.formulas['PinY'])),
      _cell('Width', _fmt(s.width),
          formula: _nonInhFormula(s.formulas['Width'])),
      _cell('Height', _fmt(s.height),
          formula: _nonInhFormula(s.formulas['Height'])),
      _cell(
        'LocPinX',
        _fmt(s.effectiveLocPinX),
        formula: _nonInhFormula(s.formulas['LocPinX']) ??
            ((s.effectiveLocPinX - s.width / 2).abs() <= _epsilon
                ? 'Width*0.5'
                : null),
      ),
      _cell(
        'LocPinY',
        _fmt(s.effectiveLocPinY),
        formula: _nonInhFormula(s.formulas['LocPinY']) ??
            ((s.effectiveLocPinY - s.height / 2).abs() <= _epsilon
                ? 'Height*0.5'
                : null),
      ),
      _cell('Angle', _fmt(s.angleRad),
          formula: _nonInhFormula(s.formulas['Angle'])),
      // MS-VSDX §2.2.6 Image — Edraw / Visio use these to place the bitmap
      // inside the Foreign shape. Without them many hosts show an empty box.
      // Drop F=Inh so Master image placement cannot override the model.
      _cell('ImgOffsetX', _fmt(s.imgOffsetXInches),
          formula: _nonInhFormula(s.formulas['ImgOffsetX'])),
      _cell('ImgOffsetY', _fmt(s.imgOffsetYInches),
          formula: _nonInhFormula(s.formulas['ImgOffsetY'])),
      _cell(
        'ImgWidth',
        _fmt(s.effectiveImgWidth),
        formula: _nonInhFormula(s.formulas['ImgWidth']) ??
            (s.imgWidthInches == null ||
                    (s.imgWidthInches! - s.width).abs() <= _epsilon
                ? 'Width*1'
                : null),
      ),
      _cell(
        'ImgHeight',
        _fmt(s.effectiveImgHeight),
        formula: _nonInhFormula(s.formulas['ImgHeight']) ??
            (s.imgHeightInches == null ||
                    (s.imgHeightInches! - s.height).abs() <= _epsilon
                ? 'Height*1'
                : null),
      ),
      // Always emit image tone (incl. defaults) so StyleSheet / Master values
      // cannot revive after Foreign rebuild or group — mirrors SoftEdges.
      _cell('Transparency', _fmt(s.imageTransparency)),
      _cell('Blur', _fmt(s.imageBlur)),
      _cell('Brightness', _fmt(s.imageBrightness)),
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
      else if (bgSlot != null) ...[
        _cell(
          'FillBkgnd',
          '0',
          formula: namedBg != null ? 'THEMEVAL("$namedBg")' : 'THEMEVAL()',
        ),
        if (fgSlot == null) _cell('QuickStyleFillColor', bgSlot.toString()),
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
      // Always emit (incl. empty) — mirrors normal shape rebuild.
      _cell('LayerMember', s.layerMemberIds.join(';')),
      _cell('FlipX', s.flipX ? '1' : '0'),
      _cell('FlipY', s.flipY ? '1' : '0'),
    ];
    if (s.shadow.enabled) {
      children.add(_cell('ShadowPattern', s.shadow.xmlPattern.toString()));
      children.add(_cell('ShdwPattern', s.shadow.xmlPattern.toString()));
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
      children
        ..add(_cell('ShadowPattern', '0'))
        ..add(_cell('ShdwPattern', '0'));
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
      if (s.glow.color != null) {
        children.add(_cell('GlowColor', _hex(s.glow.color!)));
      } else if (s.glow.themeColorIndex != null) {
        children.add(_cell('GlowColor', '0', formula: 'THEMEVAL()'));
        children.add(_cell(
            'QuickStyleEffectColor', s.glow.themeColorIndex!.toString()));
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
    } else {
      // Size=0 disables; keep companions for re-enable after Foreign rebuild.
      children
        ..add(_cell('ReflectionSize', '0'))
        ..add(_cell('ReflectionDist', _fmt(s.reflection.distanceInches)))
        ..add(_cell(
            'ReflectionTransparency', _fmt(s.reflection.transparency)))
        ..add(_cell('ReflectionBlur', _fmt(s.reflection.blurInches)));
    }
    // Match Shape rebuild: always emit gradient enable flags (incl. 0).
    if (s.fill.gradient != null && s.fill.gradient!.stops.isNotEmpty) {
      children
        ..add(_cell('FillGradientEnabled', '1'))
        ..add(_cell('FillGradientDir',
            _gradientDirFor(s.fill.gradient!).toString()))
        ..add(_cell('FillGradientAngle', _fmt(s.fill.gradient!.angleRad)));
    } else {
      children.add(_cell('FillGradientEnabled', '0'));
    }
    if (s.line.gradient != null && s.line.gradient!.stops.isNotEmpty) {
      children
        ..add(_cell('LineGradientEnabled', '1'))
        ..add(_cell('LineGradientDir',
            _gradientDirFor(s.line.gradient!).toString()))
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
        formula: _nonInhFormula(s.formulas['EventDblClick']),
      ));
    }
    for (final name in const <String>['TheText', 'EventXFMod', 'EventDrop']) {
      final formula = _nonInhFormula(s.formulas[name]);
      if (formula != null) {
        children.add(_cell(name, '0', formula: formula));
      }
    }
    children
      ..add(_cell('NoAlignBox', s.noAlignBox ? '1' : '0'))
      ..add(_cell('ShapeSplittable', s.shapeSplittable ? '1' : '0'));
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
    children
      ..add(_cell('IsTextEditTarget', s.isTextEditTarget ? '1' : '0'))
      ..add(_cell('DontMoveChildren', s.dontMoveChildren ? '1' : '0'));
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
    XmlElement? pictureText;
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
      pictureText = textEl;
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
    // Edge glue points — honour model (incl. intentional empty after clear).
    if (s.connectionPoints.isNotEmpty) {
      children.add(_buildConnectionSection(s.connectionPoints));
    }
    if (s.hyperlinks.isNotEmpty) {
      children.add(_buildHyperlinkSection(s.hyperlinks));
    }
    // Sheet_Type requires every Cell / Section before ShapeSheet_Type's Text
    // and ForeignData tail. LibreOffice/libvisio follows that ordering when it
    // consumes the relationship, even though our parser is intentionally lax.
    _appendOpaqueChildren(children, s, opaqueById);
    if (pictureText != null) children.add(pictureText);
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
            if (p.format != null || p.formatFormula != null)
              _cell('Format', p.format ?? '', formula: p.formatFormula),
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
                if (r.format != null || r.formatFormula != null)
                  _fieldCell(
                    'Format',
                    r.format ?? '',
                    formula: r.formatFormula,
                  ),
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
                if (r.action != null || r.actionFormula != null)
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

  /// Drop Master `F=Inh` so rebuild emits a local formula / literal instead.
  static String? _nonInhFormula(String? f) {
    if (f == null || f.isEmpty) return null;
    final u = f.trim().toUpperCase();
    if (u == 'INH' || u.startsWith('INH(')) return null;
    return f;
  }

  static bool _isParametricFormula(String? f) {
    if (f == null || f.isEmpty || f == 'No Formula') return false;
    // Inh is Master inherit, not a local parametric — scrub on V= writes.
    final u0 = f.trim().toUpperCase();
    if (u0 == 'INH' || u0.startsWith('INH(')) return false;
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

  /// SETATREF / TEXTWIDTH / … — keep even when V was force-edited.
  static bool _isComplexTxtParametric(String? f) {
    if (f == null || f.isEmpty || f == 'No Formula' || f == 'Inh') return false;
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
        u.contains('MAX(');
  }

  /// Evaluate simple `Width*k` / `Height*k` (and `TxtWidth*k` / `TxtHeight*k`
  /// when [txtWidth]/[txtHeight] are known). Returns null if not a simple ratio.
  static double? _evalSimpleDimRatioFormula(
    String f, {
    required double width,
    required double height,
    double? txtWidth,
    double? txtHeight,
  }) {
    final u = f.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final m = RegExp(r'^(WIDTH|HEIGHT|TXTWIDTH|TXTHEIGHT)\*([0-9]*\.?[0-9]+)$')
        .firstMatch(u);
    if (m == null) return null;
    final k = double.tryParse(m.group(2)!);
    if (k == null) return null;
    switch (m.group(1)) {
      case 'WIDTH':
        return width * k;
      case 'HEIGHT':
        return height * k;
      case 'TXTWIDTH':
        return txtWidth == null ? null : txtWidth * k;
      case 'TXTHEIGHT':
        return txtHeight == null ? null : txtHeight * k;
    }
    return null;
  }

  /// True when [f] still agrees with [value] for [shape] (keep F=), or when it
  /// is a complex parametric we must not scrub.
  bool _txtFormulaAgreesWithValue(String f, double value, VsdxShape shape) {
    if (_isComplexTxtParametric(f)) return true;
    final block = shape.richText.textBlock;
    final expected = _evalSimpleDimRatioFormula(
      f,
      width: shape.width,
      height: shape.height,
      txtWidth: block.widthInches ?? shape.width,
      txtHeight: block.heightInches ?? shape.height,
    );
    if (expected != null) return (expected - value).abs() <= _epsilon;
    // Unknown Width*/Height* expression — honour the edited V.
    return !_isParametricFormula(f);
  }

  /// Rewrite a caption that uses a negative [VsdxTextBlock.pinYInches] into the
  /// Edraw-safe form `TxtPinY≥0`, `TxtLocPinY=TxtHeight` while keeping the same
  /// painted box when the caption already sits flush under the shape.
  static VsdxTextBlock _edrawSafeCaptionBelow(VsdxTextBlock b) {
    final pinY = b.pinYInches;
    final th = b.heightInches;
    if (pinY == null || th == null || th <= _epsilon || pinY >= -_epsilon) {
      return b;
    }
    final locY = b.locPinYInches ?? th / 2;
    final top = pinY - locY + th; // top edge of the text block in shape space
    // EdrawMax clamps negative TxtPinY — never emit a negative pin. When the
    // caption already had a gap below the shape (top<0), pin at 0 and hang the
    // label fully under the glyph (gap is sacrificed for host compatibility).
    return b.copyWith(
      pinYInches: top < -_epsilon ? 0.0 : top,
      locPinYInches: th,
    );
  }

  /// Preserve Txt* `F=` only when the **model** still carries that formula and
  /// it agrees with the edited cache (or is SETATREF/TEXTWIDTH/…). If the
  /// model cleared the formula (absolute caption), never keep XML F=.
  bool _preserveTxtLengthFormula(
    XmlElement el,
    String cellName,
    double? editedValue,
    VsdxShape shape,
  ) {
    if (editedValue == null) return false;
    final modelF = shape.formulas[cellName];
    if (modelF == null || modelF.isEmpty) return false;
    final f = _cellFormula(el, cellName);
    if (!_isParametricFormula(f)) return false;
    return _txtFormulaAgreesWithValue(f!, editedValue, shape);
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
    // Dart's shortest representation is guaranteed to parse back to the same
    // IEEE-754 value. Fixed 9-decimal output visibly changed imported VSD
    // TextBlock coordinates, font sizes and geometry after VSDX synthesis.
    var s = v.toString();
    if (!s.contains('e') && s.endsWith('.0')) {
      s = s.substring(0, s.length - 2);
    }
    return s == '-0' || s == '-0.0' ? '0' : s;
  }

  static XmlElement? _firstChild(XmlElement parent, String local) {
    for (final el in parent.childElements) {
      if (el.name.local == local) return el;
    }
    return null;
  }
}
