/// Walks `visio/pages/pages.xml`, following each `<Rel r:id="..."/>` to load
/// the per-page `pageN.xml`. Each resolved page is materialised into
/// [VsdxPage] (with shapes parsed via [PageParser]).
library;

import 'package:logging/logging.dart';
import 'package:xml/xml.dart';

import '../core/exceptions.dart';
import '../model/connect.dart';
import '../model/layer.dart';
import '../model/master.dart';
import '../model/page.dart';
import '../model/shape.dart';
import '../utils/color.dart';
import 'cell_helpers.dart';
import 'connect_parser.dart';
import 'layer_parser.dart';
import 'package_reader.dart';
import 'page_parser.dart';
import 'relationships.dart';
import 'rich_text_parser.dart';

final _log = Logger('vsdx.parser.pages');

class PagesParser {
  PagesParser(
    this._package, {
    PageParser? pageParser,
    MasterRegistry masters = MasterRegistry.empty,
  })  : _resolver = RelationshipResolver(_package),
        _pageParserFactory =
            ((Map<String, String>? rels) => pageParser ??
                PageParser(masters: masters, imageRels: rels)),
        _hasInjectedParser = pageParser != null;

  final VsdxPackage _package;
  final RelationshipResolver _resolver;

  /// We pass per-page image rels through the factory so each shape resolves
  /// `<ForeignData r:id="...">` against the right rels file.
  final PageParser Function(Map<String, String>?) _pageParserFactory;
  final bool _hasInjectedParser;

  /// Locate `visio/pages/pages.xml` via the document part's relationships and
  /// return a fully-populated page list. If no `pages` relationship exists
  /// (highly unusual but technically possible) the result is an empty list.
  List<VsdxPage> parsePages({required String documentPartName}) {
    final pagesPart =
        _resolver.singleTargetOfType(documentPartName, VsdxRelType.pages);
    if (pagesPart == null) {
      _log.warning('No pages.xml relationship found from $documentPartName');
      return const <VsdxPage>[];
    }

    final indexXml = _package.readPartXml(pagesPart);
    if (indexXml == null) {
      throw VsdxParseException(
        'pages.xml part declared in relationships but missing from archive',
        partName: pagesPart,
      );
    }

    final pageEls = indexXml.rootElement.childElements
        .where((el) => el.name.local == 'Page')
        .toList(growable: false);

    final out = <VsdxPage>[];
    for (var i = 0; i < pageEls.length; i++) {
      final page = _readIndexEntry(
        pageEls[i],
        pagesPart: pagesPart,
        pageIndex: i,
        totalPages: pageEls.length,
      );
      if (page != null) out.add(page);
    }
    return out;
  }

  VsdxPage? _readIndexEntry(
    XmlElement pageEl, {
    required String pagesPart,
    required int pageIndex,
    required int totalPages,
  }) {
    final idStr = pageEl.getAttribute('ID');
    final id = idStr == null ? -1 : int.tryParse(idStr) ?? -1;
    final name = pageEl.getAttribute('NameU') ??
        pageEl.getAttribute('Name') ??
        'Page-$id';
    final isBackground =
        (pageEl.getAttribute('Background') ?? '').trim() == '1';
    final backPageStr = pageEl.getAttribute('BackPage');
    final backPageId = backPageStr == null ? null : int.tryParse(backPageStr);

    // Default to US letter so we always have *some* sensible canvas; the
    // PageSheet usually overrides.
    double width = 8.5;
    double height = 11.0;
    var layers = const <VsdxLayer>[];
    VsdxColor? bgColor;
    final pageSheet = _firstChildLocal(pageEl, 'PageSheet');
    if (pageSheet != null) {
      width = readLengthInches(pageSheet, 'PageWidth') ?? width;
      height = readLengthInches(pageSheet, 'PageHeight') ?? height;
      layers = const LayerParser().parseLayers(pageSheet);
      bgColor = _readPageColor(pageSheet);
    }

    // <Rel r:id="rIdN"/> → pageN.xml
    final relEl = _firstChildLocal(pageEl, 'Rel');
    final shapes = <VsdxShape>[];
    var connects = const <VsdxConnect>[];
    if (relEl != null) {
      final rId = relEl.getAttribute('r:id') ?? relEl.attrIdFallback();
      if (rId != null) {
        final target = _resolver.followById(pagesPart, rId);
        if (target != null) {
          final pageXml = _package.readPartXml(target);
          if (pageXml != null) {
            final imageRels = _hasInjectedParser
                ? null
                : _collectImageRels(target);
            var parser = _pageParserFactory(imageRels);
            if (!_hasInjectedParser) {
              parser = parser.withFieldResolver(FieldResolver(
                pageName: name,
                pageIndex: pageIndex,
                totalPages: totalPages,
              ));
            }
            shapes
              ..clear()
              ..addAll(parser.parseShapes(pageXml, partName: target));
            connects = const ConnectParser().parsePage(pageXml.rootElement);
          } else {
            _log.warning('Page part $target empty or unreadable');
          }
        } else {
          _log.warning(
            'Page entry $id references unknown relationship $rId in $pagesPart',
          );
        }
      }
    }

    return VsdxPage(
      id: id,
      name: name,
      widthInches: width,
      heightInches: height,
      shapes: shapes,
      layers: layers,
      connects: connects,
      backgroundColor: bgColor,
      isBackgroundPage: isBackground,
      backgroundPageId: backPageId,
    );
  }

  VsdxColor? _readPageColor(XmlElement pageSheet) {
    for (final el in pageSheet.childElements) {
      if (el.name.local != 'Cell') continue;
      if (el.getAttribute('N') != 'PageColor') continue;
      final v = el.getAttribute('V');
      if (v == null || v.isEmpty) return null;
      return VsdxColor.tryParse(v);
    }
    return null;
  }

  /// Build `{rId → absolute media part}` for the given page part.
  Map<String, String> _collectImageRels(String pagePart) {
    final out = <String, String>{};
    for (final rel in _package.readPartRelationships(pagePart)) {
      if (!VsdxRelType.image.matches(rel.type)) continue;
      out[rel.id] =
          _package.resolveRelationshipTarget(pagePart, rel.target);
    }
    return out;
  }

  static XmlElement? _firstChildLocal(XmlElement parent, String local) {
    for (final el in parent.childElements) {
      if (el.name.local == local) return el;
    }
    return null;
  }
}

extension on XmlElement {
  /// Some VSDX writers omit the canonical `r:` prefix and emit `id="..."`
  /// directly on `<Rel>`. Be lenient.
  String? attrIdFallback() => getAttribute('id') ?? getAttribute('Id');
}
