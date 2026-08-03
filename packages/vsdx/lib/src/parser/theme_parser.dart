/// Parse `visio/theme/theme1.xml` into a [VsdxTheme].
///
/// We only consume the `<a:clrScheme>` block — fonts and effects come later.
/// Two colour formats appear in the wild:
///   * `<a:srgbClr val="44546A"/>` — direct hex
///   * `<a:sysClr val="window" lastClr="FFFFFF"/>` — system role, with the
///     last seen concrete value in `lastClr`. We always read `lastClr`.
///
/// Themes are optional from the package's point of view; if the relationship
/// is missing we return [VsdxTheme.empty] and the renderer falls back to
/// neutral defaults.
library;

import 'package:logging/logging.dart';
import 'package:xml/xml.dart';

import '../model/theme.dart';
import '../utils/color.dart';
import 'package_reader.dart';
import 'relationships.dart';

final _log = Logger('vsdx.parser.theme');

class ThemeParser {
  ThemeParser(this._package) : _resolver = RelationshipResolver(_package);

  final VsdxPackage _package;
  final RelationshipResolver _resolver;

  static const Map<String, int> _slotForName = <String, int>{
    'dk1': ThemeSlot.dk1,
    'lt1': ThemeSlot.lt1,
    'dk2': ThemeSlot.dk2,
    'lt2': ThemeSlot.lt2,
    'accent1': ThemeSlot.accent1,
    'accent2': ThemeSlot.accent2,
    'accent3': ThemeSlot.accent3,
    'accent4': ThemeSlot.accent4,
    'accent5': ThemeSlot.accent5,
    'accent6': ThemeSlot.accent6,
    'hlink': ThemeSlot.hyperlink,
    'folHlink': ThemeSlot.followedHyperlink,
  };

  /// Resolve a DrawingML clrScheme child local-name to a [ThemeSlot] id.
  static int? slotForName(String localName) => _slotForName[localName];

  VsdxTheme parseTheme({required String documentPartName}) {
    final themePart =
        _resolver.singleTargetOfType(documentPartName, VsdxRelType.theme);
    if (themePart == null) {
      _log.fine(() => 'No theme relationship from $documentPartName');
      return VsdxTheme.empty;
    }
    XmlDocument? doc;
    try {
      doc = _package.readPartXml(themePart);
    } catch (_) {
      _log.warning('Theme part is malformed; using empty theme: $themePart');
      return VsdxTheme.empty;
    }
    if (doc == null) {
      _log.warning('Theme declared but missing in archive: $themePart');
      return VsdxTheme.empty;
    }
    return parseDocument(doc);
  }

  /// Pure-XML entry point — convenient for tests and for callers that
  /// already have the bytes loaded.
  static VsdxTheme parseDocument(XmlDocument doc) {
    final scheme = _findFirstByLocal(doc.rootElement, 'clrScheme');
    if (scheme == null) {
      _log.warning('Theme document has no clrScheme element');
      return VsdxTheme.empty;
    }
    final colors = <int, VsdxColor>{};
    for (final el in scheme.childElements) {
      final slot = _slotForName[el.name.local];
      if (slot == null) continue;
      final c = _readColorChild(el);
      if (c != null) colors[slot] = c;
    }
    final variationColors = <List<VsdxColor?>>[];
    final variationList = _findFirstByLocal(
      scheme,
      'variationClrSchemeLst',
    );
    if (variationList != null) {
      for (final variation in variationList.childElements) {
        if (variation.name.local != 'variationClrScheme') continue;
        final entries = List<VsdxColor?>.filled(7, null);
        for (final child in variation.childElements) {
          final match = RegExp(r'^varColor([1-7])$').firstMatch(
            child.name.local,
          );
          if (match == null) continue;
          final index = int.parse(match.group(1)!) - 1;
          entries[index] = _readColorChild(child);
        }
        variationColors.add(List<VsdxColor?>.unmodifiable(entries));
      }
    }
    final fillStyleColors = <VsdxColor?>[];
    final fillStyleList = _findFirstByLocal(doc.rootElement, 'fillStyleLst');
    if (fillStyleList != null) {
      for (final style in fillStyleList.childElements) {
        fillStyleColors.add(_readDirectFillStyleColor(style, colors));
      }
    }
    final variationFillStyleIndices = <List<int?>>[];
    final variationStyleList = _findFirstByLocal(
      doc.rootElement,
      'variationStyleSchemeLst',
    );
    if (variationStyleList != null) {
      for (final scheme in variationStyleList.childElements) {
        if (scheme.name.local != 'variationStyleScheme') continue;
        final indices = <int?>[];
        for (final style in scheme.childElements) {
          if (style.name.local != 'varStyle') continue;
          indices.add(int.tryParse(style.getAttribute('fillIdx') ?? ''));
        }
        variationFillStyleIndices.add(List<int?>.unmodifiable(indices));
      }
    }
    return VsdxTheme(
      colors: Map.unmodifiable(colors),
      variationColors: List<List<VsdxColor?>>.unmodifiable(variationColors),
      fillStyleColors: List<VsdxColor?>.unmodifiable(fillStyleColors),
      variationFillStyleIndices:
          List<List<int?>>.unmodifiable(variationFillStyleIndices),
    );
  }

  static VsdxColor? _readDirectFillStyleColor(
    XmlElement style,
    Map<int, VsdxColor> colors,
  ) {
    // Match libvisio's readThemeColour loop: inspect every colour child and
    // keep the last directly-resolvable value. In particular, a gradient may
    // begin with unresolved phClr stops and end with lt1; returning at the
    // first phClr incorrectly leaves QuickStyle's accent colour in place.
    VsdxColor? result;
    for (final node in style.descendants.whereType<XmlElement>()) {
      switch (node.name.local) {
        case 'schemeClr':
          final slot = _slotForName[node.getAttribute('val')];
          result = slot == null ? null : colors[slot];
        case 'srgbClr':
          final value = node.getAttribute('val');
          result = value == null ? null : VsdxColor.tryParse('#$value');
        case 'sysClr':
          final value = node.getAttribute('lastClr');
          result = value == null ? null : VsdxColor.tryParse('#$value');
      }
    }
    return result;
  }

  static VsdxColor? _readColorChild(XmlElement parent) {
    for (final el in parent.childElements) {
      switch (el.name.local) {
        case 'srgbClr':
          final v = el.getAttribute('val');
          if (v != null) return VsdxColor.tryParse('#$v');
        case 'sysClr':
          final last = el.getAttribute('lastClr');
          if (last != null) return VsdxColor.tryParse('#$last');
      }
    }
    return null;
  }

  static XmlElement? _findFirstByLocal(XmlElement root, String localName) {
    for (final node in root.descendants) {
      if (node is XmlElement && node.name.local == localName) return node;
    }
    return null;
  }
}
