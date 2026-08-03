/// Walks `visio/pages/pages.xml`, following each `<Rel r:id="..."/>` to load
/// the per-page `pageN.xml`. Each resolved page is materialised into
/// [VsdxPage] (with shapes parsed via [PageParser]).
library;

import 'package:logging/logging.dart';
import 'package:xml/xml.dart';

import '../model/connect.dart';
import '../model/drawing_scale.dart';
import '../model/layer.dart';
import '../model/master.dart';
import '../model/page.dart';
import '../model/shape.dart';
import '../model/stylesheet.dart';
import '../utils/color.dart';
import 'cell_helpers.dart';
import 'connect_parser.dart';
import 'layer_parser.dart';
import 'package_reader.dart';
import 'page_parser.dart';
import 'relationships.dart';
import 'rich_text_parser.dart';
import 'style_parser.dart';

final _log = Logger('vsdx.parser.pages');

// VSDXParser::readPageSheetProperties starts these collector-facing values at
// zero. Keep the richer model defaults for newly-created pages, but do not
// invent Visio's usual shadow offsets while importing an omitted PageSheet.
const _libvisioPageSheetDefaults = VsdxPageSheet(
  shadowOffsetXInches: 0,
  shadowOffsetYInches: 0,
);

class PagesParser {
  PagesParser(
    this._package, {
    PageParser? pageParser,
    MasterRegistry masters = MasterRegistry.empty,
    StyleSheetRegistry stylesheets = StyleSheetRegistry.empty,
    Map<int, VsdxColor> colorPalette = const <int, VsdxColor>{},
    Map<int, String> fontNames = const <int, String>{},
  })  : _resolver = RelationshipResolver(_package),
        _pageParserFactory = ((Map<String, String>? rels) =>
            pageParser ??
            PageParser(
              style: StyleParser(colorPalette: colorPalette),
              richText: RichTextParser(
                colorPalette: colorPalette,
                fontNames: fontNames,
              ),
              masters: masters,
              stylesheets: stylesheets,
              imageRels: rels,
            )),
        _hasInjectedParser = pageParser != null,
        _colorPalette = colorPalette;

  final VsdxPackage _package;
  final RelationshipResolver _resolver;

  /// We pass per-page image rels through the factory so each shape resolves
  /// `<ForeignData r:id="...">` against the right rels file.
  final PageParser Function(Map<String, String>?) _pageParserFactory;
  final bool _hasInjectedParser;
  final Map<int, VsdxColor> _colorPalette;

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

    XmlDocument? indexXml;
    try {
      indexXml = _package.readPartXml(pagesPart);
    } catch (_) {
      _log.warning('pages.xml is malformed; returning no pages: $pagesPart');
      return const <VsdxPage>[];
    }
    if (indexXml == null) {
      _log.warning('pages.xml declared but missing: $pagesPart');
      return const <VsdxPage>[];
    }

    final pageEls = indexXml.rootElement.childElements
        .where((el) =>
            el.name.local == 'Page' &&
            int.tryParse(el.getAttribute('ID') ?? '') != null)
        .toList(growable: false);

    final out = <VsdxPage>[];
    for (var i = 0; i < pageEls.length; i++) {
      try {
        final page = _readIndexEntry(
          pageEls[i],
          pagesPart: pagesPart,
          pageIndex: i,
          totalPages: pageEls.length,
        );
        if (page != null) out.add(page);
      } catch (error, stackTrace) {
        _log.warning(
          'Skipping malformed page index entry ${i + 1} in $pagesPart',
          error,
          stackTrace,
        );
      }
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
    final id = idStr == null ? null : int.tryParse(idStr);
    // libvisio ignores Page rows without a usable ID.
    if (id == null) return null;
    // Name is the localized/display label; NameU is only the fallback.
    final name = pageEl.getAttribute('Name') ??
        pageEl.getAttribute('NameU') ??
        'Page-$id';
    final isBackground = isXmlTrue(pageEl.getAttribute('Background'));
    final backPageStr = pageEl.getAttribute('BackPage');
    final parsedBackPageId =
        backPageStr == null ? null : int.tryParse(backPageStr);
    final backPageId = parsedBackPageId != null && parsedBackPageId >= 0
        ? parsedBackPageId
        : null;
    final viewScale = double.tryParse(pageEl.getAttribute('ViewScale') ?? '');
    final viewCenterX =
        double.tryParse(pageEl.getAttribute('ViewCenterX') ?? '');
    final viewCenterY =
        double.tryParse(pageEl.getAttribute('ViewCenterY') ?? '');

    // libvisio starts every VSDX page at 0 × 0 and only changes the canvas
    // when PageWidth / PageHeight cells are actually present.
    double width = 0;
    double height = 0;
    var layers = const <VsdxLayer>[];
    VsdxColor? bgColor;
    var sheet = _libvisioPageSheetDefaults;
    final pageSheet = _firstChildLocal(pageEl, 'PageSheet');
    if (pageSheet != null) {
      // PageSheet has no master prototype in libvisio: its collector consumes
      // the cached V= even when a producer leaves F="Inh" on these cells.
      width = readLengthInches(pageSheet, 'PageWidth') ?? width;
      height = readLengthInches(pageSheet, 'PageHeight') ?? height;
      layers = LayerParser(colorPalette: _colorPalette).parseLayers(pageSheet);
      bgColor = _readPageColor(pageSheet);
      sheet = _readPageSheet(pageSheet);
    }
    // libvisio materialises PageScale / DrawingScale into the page canvas and
    // every drawable coordinate. Keep the original cells in [pageSheet] for
    // round-trip, but expose physical page inches from the parsed model just
    // like the binary VSD path does.
    final drawingScale = visioDrawingScale(sheet);
    width *= drawingScale;
    height *= drawingScale;

    // <Rel r:id="rIdN"/> → pageN.xml
    final relEl = _firstChildLocal(pageEl, 'Rel');
    final shapes = <VsdxShape>[];
    var connects = const <VsdxConnect>[];
    if (relEl != null) {
      final rId = relEl.getAttribute('r:id') ?? relEl.attrIdFallback();
      if (rId != null) {
        final target = _resolver.followById(pagesPart, rId);
        if (target != null) {
          XmlDocument? pageXml;
          try {
            pageXml = _package.readPartXml(target);
          } catch (_) {
            _log.warning('Page part is malformed; keeping empty page: $target');
          }
          if (pageXml != null) {
            final imageRels =
                _hasInjectedParser ? null : _collectImageRels(target);
            var parser = _pageParserFactory(imageRels);
            if (!_hasInjectedParser) {
              parser = parser.withFieldResolver(FieldResolver(
                pageName: name,
                pageIndex: pageIndex,
                totalPages: totalPages,
              ));
            }
            parser = parser.withPageShadowOffsets(
              sheet.shadowOffsetXInches,
              sheet.shadowOffsetYInches,
            );
            try {
              final parsed = parser.parseShapes(pageXml, partName: target);
              for (final shape in parsed) {
                try {
                  shapes.add(scaleVisioDrawingShape(shape, drawingScale));
                } catch (error, stackTrace) {
                  // A single malformed transform must not discard the other
                  // shapes that PageParser already recovered from this page.
                  _log.warning(
                    'Shape ${shape.id} could not be scaled; skipping it',
                    error,
                    stackTrace,
                  );
                }
              }
            } catch (error, stackTrace) {
              _log.warning(
                'Page content could not be parsed; keeping empty page: $target',
                error,
                stackTrace,
              );
            }
            try {
              connects = const ConnectParser().parsePage(pageXml.rootElement);
            } catch (error, stackTrace) {
              // Connect rows enrich routing but are not required to display
              // the page's shapes. Keep the recovered drawing when damaged.
              _log.warning(
                'Connect rows could not be parsed; keeping shapes: $target',
                error,
                stackTrace,
              );
              connects = const <VsdxConnect>[];
            }
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
      pageSheet: sheet,
      viewScale: viewScale,
      viewCenterX: viewCenterX,
      viewCenterY: viewCenterY,
    );
  }

  VsdxPageSheet _readPageSheet(XmlElement pageSheet) {
    int? i(
      String n, {
      int? inheritFrom,
      bool useCachedValue = false,
    }) {
      final cell = findCell(pageSheet, n);
      if (cell == null) return null;
      if (!useCachedValue && isInhFormula(cell.getAttribute('F'))) {
        return inheritFrom; // null ⇒ treat Inh as absent
      }
      return int.tryParse(cell.getAttribute('V') ?? '') ??
          double.tryParse(cell.getAttribute('V') ?? '')?.toInt();
    }

    double? d(
      String n, {
      double? inheritFrom,
      bool useCachedValue = false,
    }) {
      final cell = findCell(pageSheet, n);
      if (cell == null) return null;
      if (!useCachedValue && isInhFormula(cell.getAttribute('F'))) {
        return inheritFrom;
      }
      return double.tryParse(cell.getAttribute('V') ?? '');
    }

    bool b(String n, bool fallback) =>
        (i(n, inheritFrom: fallback ? 1 : 0) ?? (fallback ? 1 : 0)) != 0;

    String? unit(String n) => findCell(pageSheet, n)?.getAttribute('U');

    const def = _libvisioPageSheetDefaults;
    return VsdxPageSheet(
      shadowOffsetXInches:
          readLengthInches(pageSheet, 'ShdwOffsetX') ?? def.shadowOffsetXInches,
      shadowOffsetYInches:
          readLengthInches(pageSheet, 'ShdwOffsetY') ?? def.shadowOffsetYInches,
      pageScale:
          d('PageScale', inheritFrom: def.pageScale, useCachedValue: true) ??
              def.pageScale,
      pageScaleUnit: unit('PageScale') ?? def.pageScaleUnit,
      drawingScale: d('DrawingScale',
              inheritFrom: def.drawingScale, useCachedValue: true) ??
          def.drawingScale,
      drawingScaleUnit: unit('DrawingScale') ?? def.drawingScaleUnit,
      drawingSizeType: i('DrawingSizeType', inheritFrom: def.drawingSizeType) ??
          def.drawingSizeType,
      drawingScaleType:
          i('DrawingScaleType', inheritFrom: def.drawingScaleType) ??
              def.drawingScaleType,
      drawingResizeType:
          i('DrawingResizeType', inheritFrom: def.drawingResizeType) ??
              def.drawingResizeType,
      inhibitSnap: b('InhibitSnap', def.inhibitSnap),
      pageLockReplace: b('PageLockReplace', def.pageLockReplace),
      pageLockDuplicate: b('PageLockDuplicate', def.pageLockDuplicate),
      uiVisibility:
          i('UIVisibility', inheritFrom: def.uiVisibility) ?? def.uiVisibility,
      shadowType: i('ShdwType', inheritFrom: def.shadowType) ?? def.shadowType,
      shadowObliqueAngle:
          d('ShdwObliqueAngle', inheritFrom: def.shadowObliqueAngle) ??
              def.shadowObliqueAngle,
      shadowScaleFactor:
          d('ShdwScaleFactor', inheritFrom: def.shadowScaleFactor) ??
              def.shadowScaleFactor,
      pageShapeSplit: b('PageShapeSplit', def.pageShapeSplit),
      lineJumpCode: i('LineJumpCode'),
      lineJumpStyle: i('LineJumpStyle'),
      lineJumpDirX: i('PageLineJumpDirX'),
      lineJumpDirY: i('PageLineJumpDirY'),
      lineToLineXInches:
          readLengthInches(pageSheet, 'LineToLineX') ?? d('LineToLineX'),
      lineToLineYInches:
          readLengthInches(pageSheet, 'LineToLineY') ?? d('LineToLineY'),
      lineJumpFactorX: d('LineJumpFactorX'),
      lineJumpFactorY: d('LineJumpFactorY'),
      marginLeftInches: readLengthInches(pageSheet, 'PageLeftMargin',
              inheritFrom: def.marginLeftInches) ??
          def.marginLeftInches,
      marginRightInches: readLengthInches(pageSheet, 'PageRightMargin',
              inheritFrom: def.marginRightInches) ??
          def.marginRightInches,
      marginTopInches: readLengthInches(pageSheet, 'PageTopMargin',
              inheritFrom: def.marginTopInches) ??
          def.marginTopInches,
      marginBottomInches: readLengthInches(pageSheet, 'PageBottomMargin',
              inheritFrom: def.marginBottomInches) ??
          def.marginBottomInches,
      printPageOrientation:
          i('PrintPageOrientation', inheritFrom: def.printPageOrientation) ??
              def.printPageOrientation,
      variationColorIndex: i('VariationColorIndex', useCachedValue: true),
      variationStyleIndex: i('VariationStyleIndex', useCachedValue: true),
    );
  }

  VsdxColor? _readPageColor(XmlElement pageSheet) {
    for (final el in pageSheet.childElements) {
      if (el.name.local != 'Cell') continue;
      if (el.getAttribute('N') != 'PageColor') continue;
      // F=Inh with no stylesheet inherit source → treat as absent (white default).
      if (isInhFormula(el.getAttribute('F'))) return null;
      final v = el.getAttribute('V');
      if (v == null || v.isEmpty) return null;
      return VsdxColor.tryParse(v, palette: _colorPalette);
    }
    return null;
  }

  /// Build `{rId → absolute media part}` for the given page part.
  Map<String, String> _collectImageRels(String pagePart) {
    final out = <String, String>{};
    for (final rel in _package.readPartRelationships(pagePart)) {
      if (!VsdxRelType.image.matches(rel.type)) continue;
      out[rel.id] = _package.resolveRelationshipTarget(pagePart, rel.target);
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
