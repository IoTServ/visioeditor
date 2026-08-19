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
