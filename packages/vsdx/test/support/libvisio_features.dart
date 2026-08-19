/// Drawing features to diff against libvisio, the importer LibreOffice drives.
///
/// libvisio's whole painting surface is `drawPath`, `drawGraphicObject` and a
/// text stack (see `VSDOutputElementList.cpp`), so every other "type" a Visio
/// document can carry rides on the graphic style it sets: gradient, hatch or
/// bitmap fill, dashes, line-end markers, drop shadow, text decoration. A
/// document where libvisio paints one of those and we paint none is a whole
/// feature silently dropped, which per-file pixel metrics can easily hide.
///
/// Shared by `test/libvisio_feature_parity_test.dart` and
/// `tool/libvisio_parity_audit.dart`.
library;

/// Feature name → pattern matching either SVG dialect. libvisio's generator
/// namespaces every element (`svg:path`); ours does not.
const libvisioFeaturePatterns = <String, String>{
  'image': r'<(?:svg:)?image\b',
  'text': r'<(?:svg:)?tspan\b',
  'gradient': r'<(?:svg:)?(?:linear|radial)Gradient\b',
  'pattern': r'<(?:svg:)?pattern\b',
  'marker': r'<(?:svg:)?marker\b',
  'shadow': r'<(?:svg:)?filter\b',
  'dash': r'stroke-dasharray="(?!none)',
  'decoration': r'text-decoration="(?!none)',
};

/// Our unblurred drop shadow: an offset silhouette drawn without a stroke.
/// libvisio always wraps a shadow in a filter; we only need one to blur.
final _offsetShadowPath = RegExp(r'stroke="none" transform="translate\(');

final _libvisioPathElement = RegExp(
  r'<svg:(?:path|polyline)\b[^>]*>',
  dotAll: true,
);

final _pathData = RegExp(r'\sd="([^"]*)"', dotAll: true);

/// Whether [svg] paints [feature].
///
/// Set [libvisio] for the oracle's output. Two features need more than a
/// pattern match, because the raw SVG overstates what LibreOffice draws:
///
///  * **shadow** — libvisio emits an `svg:filter` for every shadow; an
///    unblurred shadow needs no filter in our output.
///  * **marker** — libvisio attaches `marker-start` / `marker-end` to closed
///    paths too, but LibreOffice paints line endings only where a subpath
///    stays open. `44501.vsd` is the witness: its rectangle carries two
///    markers and LibreOffice renders it without an arrowhead.
bool paintsLibvisioFeature(
  String feature,
  String svg, {
  required bool libvisio,
}) {
  final matched = RegExp(libvisioFeaturePatterns[feature]!).hasMatch(svg);
  switch (feature) {
    case 'shadow':
      return libvisio ? matched : matched || _offsetShadowPath.hasMatch(svg);
    case 'marker':
      return libvisio ? _referencesVisibleMarker(svg) : matched;
    default:
      return matched;
  }
}

bool _referencesVisibleMarker(String svg) {
  for (final element in _libvisioPathElement.allMatches(svg)) {
    final markup = element.group(0)!;
    if (!markup.contains('marker-start:') && !markup.contains('marker-end:')) {
      continue;
    }
    final data = _pathData.firstMatch(markup);
    // A polyline is always open; a path is decorated only where some subpath
    // does not close.
    if (data == null || _hasOpenSubpath(data.group(1)!)) return true;
  }
  return false;
}

bool _hasOpenSubpath(String d) {
  for (final subpath in d.split(RegExp(r'(?=[Mm])'))) {
    final trimmed = subpath.trim();
    if (trimmed.isEmpty) continue;
    if (!trimmed.toUpperCase().endsWith('Z')) return true;
  }
  return false;
}

/// What libvisio reads out of a document, reduced to the things a save must
/// not change. Everything is measured from libvisio's own SVG, so both sides
/// of a round-trip are observed by the importer LibreOffice actually uses.
class LibvisioObservation {
  const LibvisioObservation({
    required this.pages,
    required this.sizes,
    required this.letters,
    required this.features,
    required this.drawn,
  });

  factory LibvisioObservation.of(List<String> svgPages) {
    final joined = svgPages.join();
    return LibvisioObservation(
      pages: svgPages.length,
      sizes: <String>[for (final page in svgPages) _pageSize(page)],
      letters: _letters(joined),
      features: <String>{
        for (final feature in libvisioFeaturePatterns.keys)
          if (paintsLibvisioFeature(feature, joined, libvisio: true)) feature,
      },
      drawn: _drawnElement.allMatches(joined).length,
    );
  }

  final int pages;
  final List<String> sizes;

  /// Case-folded letters of every rendered span, sorted.
  ///
  /// A save legitimately reformats field values: libvisio reads `300.0000`
  /// straight out of a legacy VSD and `25 ft` back out of the VSDX we write,
  /// because the VSDX carries the format the binary record only implied. It
  /// also applies the StrUpper / StrLower formats libvisio ignores. Digits,
  /// punctuation and case therefore move around, while a label that
  /// disappeared shows up as missing letters either way.
  final String letters;

  final Set<String> features;
  final int drawn;

  /// libvisio reports `0.00x0.00` when the source declares no page size at
  /// all. LibreOffice then falls back to A4 for the original and for anything
  /// we save from it, so there is no size to preserve.
  bool get hasDegenerateSize => sizes.every(isDegenerateSize);

  static bool isDegenerateSize(String size) =>
      size == '0.00x0.00' || size == '?';
}

final _svgSize = RegExp(r'width="([0-9.]+)in"\s+height="([0-9.]+)in"');
final _drawnElement =
    RegExp(r'<svg:(?:path|polyline|polygon|ellipse|rect|image)\b');
final _span = RegExp(
  r'<(?:svg:)?tspan\b[^>]*>(.*?)</(?:svg:)?tspan>',
  dotAll: true,
);
final _letter = RegExp(r'\p{L}', unicode: true);

String _pageSize(String svg) {
  final match = _svgSize.firstMatch(svg);
  if (match == null) return '?';
  final width = double.parse(match.group(1)!).toStringAsFixed(2);
  final height = double.parse(match.group(2)!).toStringAsFixed(2);
  return '${width}x$height';
}

String _letters(String svg) {
  final out = <String>[];
  for (final span in _span.allMatches(svg)) {
    out.addAll(
      _letter
          .allMatches(unescapeXml(span.group(1)!).toLowerCase())
          .map((m) => m.group(0)!),
    );
  }
  out.sort();
  return out.join();
}

String unescapeXml(String xml) => xml
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// Characters in the sorted multiset [before] that [after] does not have.
String missingLetters(String before, String after) {
  final remaining = after.split('');
  final lost = StringBuffer();
  for (final character in before.split('')) {
    final at = remaining.indexOf(character);
    if (at < 0) {
      lost.write(character);
    } else {
      remaining.removeAt(at);
    }
  }
  return lost.toString();
}
