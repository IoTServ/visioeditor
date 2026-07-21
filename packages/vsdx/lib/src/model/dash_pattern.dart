/// Visio `LinePattern` → dash/gap lengths in **inches**.
///
/// Built-in patterns are authored relative to the stroke weight (Visio sizes
/// unscaled line patterns so master height ≈ LineWeight). The table below is
/// expressed as multiples of [weightInches] using the historical fixed table
/// at the default weight `0.01"` as the reference (e.g. pattern 2 was
/// `0.10 0.05` → `10w 5w`).
library;

/// Dash/gap pairs for [linePattern], or `null` for solid / no-line.
///
/// [weightInches] defaults to Visio's ≈0.01" stroke so callers that omit it
/// keep the previous absolute-inch appearance.
List<double>? dashPatternFor(
  int linePattern, {
  double weightInches = 0.01,
}) {
  final w = weightInches > 1e-9 ? weightInches : 0.01;
  List<double> scaled(List<double> multiplesOfWeight) =>
      [for (final m in multiplesOfWeight) m * w];

  switch (linePattern) {
    case 0:
    case 1:
      return null;
    case 2: // dashed
      return scaled(const [10, 5]);
    case 3: // dotted
      return scaled(const [2, 4]);
    case 4: // dash-dot
      return scaled(const [12, 5, 2, 5]);
    case 5: // dash-dot-dot
      return scaled(const [12, 5, 2, 5, 2, 5]);
    case 6: // short dash
      return scaled(const [6, 4]);
    case 7: // dash long-gap
      return scaled(const [10, 10]);
    case 8: // sparse dash
      return scaled(const [8, 12]);
    case 9: // long-dash
      return scaled(const [20, 5]);
    case 10: // long-dash-dot
      return scaled(const [20, 5, 2, 5]);
    case 11: // long-dash-dot-dot
      return scaled(const [20, 5, 2, 5, 2, 5]);
    case 12: // medium dash
      return scaled(const [14, 6]);
    case 13: // medium dash-dot
      return scaled(const [14, 5, 2, 5]);
    case 14: // medium dash-dot-dot
      return scaled(const [14, 5, 2, 5, 2, 5]);
    case 15: // fine dots
      return scaled(const [1.5, 3]);
    case 16: // dash-gap-dash
      return scaled(const [10, 4, 4, 4]);
    case 17:
    case 18:
      return scaled(const [16, 6]);
    case 19:
    case 20:
      return scaled(const [10, 5, 3, 5]);
    case 21:
    case 22:
    case 23:
      return scaled(const [8, 4, 2, 4]);
    default:
      return scaled(const [8, 4]);
  }
}

/// Format [dashPatternFor] for SVG `stroke-dasharray`, or `''` when solid.
String dashArrayAttr(
  int linePattern, {
  double weightInches = 0.01,
  String Function(double v)? format,
}) {
  final dashes = dashPatternFor(linePattern, weightInches: weightInches);
  if (dashes == null || dashes.isEmpty) return '';
  final fmt = format ??
      (double v) {
        if (v == v.truncateToDouble()) return v.toStringAsFixed(0);
        return v
            .toStringAsFixed(3)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
      };
  return dashes.map(fmt).join(' ');
}
