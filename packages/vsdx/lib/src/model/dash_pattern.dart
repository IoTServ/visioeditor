/// Visio `LinePattern` → dash/gap lengths in **inches**.
///
/// Built-in patterns are authored relative to the stroke weight (Visio sizes
/// unscaled line patterns so master height ≈ LineWeight). The table below is
/// expressed as multiples of [weightInches] using the historical fixed table
/// at the default weight `0.01"` as the reference (e.g. pattern 2 was
/// `0.10 0.05` → `10w 5w`).
library;

import 'line.dart';

/// One draw.io canvas unit at the editor's SVG/CSS reference density.
const double drawioDashUnitInches = 1 / 96;

/// Parse draw.io's whitespace/comma-separated positive `dashPattern` values.
/// Returns `null` for an empty or invalid sequence.
List<double>? parseDrawioDashPattern(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  final values = <double>[];
  for (final part in text.split(RegExp(r'[\s,]+'))) {
    final value = double.tryParse(part);
    if (value == null || !value.isFinite || value <= 0) return null;
    values.add(value);
  }
  return values.isEmpty ? null : values;
}

/// Format raw draw.io dash values without converting them to inches.
String formatDrawioDashPattern(List<double>? values) {
  if (values == null || values.isEmpty) return '';
  return values.map((value) {
    if (value == value.truncateToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }).join(' ');
}

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

/// Effective dash/gap lengths in inches for a complete line style.
///
/// Custom draw.io values override Visio [VsdxLine.pattern]. Non-fixed values
/// are multiples of line weight; fixed values use CSS/SVG display units.
List<double>? effectiveDashPatternForLine(VsdxLine line) {
  if (!line.hasLine) return null;
  final custom = line.customDashPattern;
  if (custom != null && custom.isNotEmpty) {
    final unit = line.fixedDash
        ? drawioDashUnitInches
        : (line.weightInches > 1e-9 ? line.weightInches : 0.01);
    return <double>[for (final value in custom) value * unit];
  }
  return dashPatternFor(
    line.pattern,
    weightInches: line.weightInches,
  );
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

/// Format [effectiveDashPatternForLine] for SVG `stroke-dasharray`.
String effectiveDashArrayAttr(
  VsdxLine line, {
  String Function(double v)? format,
}) {
  final dashes = effectiveDashPatternForLine(line);
  if (dashes == null || dashes.isEmpty) return '';
  final fmt = format ??
      (double value) {
        if (value == value.truncateToDouble()) return value.toStringAsFixed(0);
        return value
            .toStringAsFixed(3)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
      };
  return dashes.map(fmt).join(' ');
}
