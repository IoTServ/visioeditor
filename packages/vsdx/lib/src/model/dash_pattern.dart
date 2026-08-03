/// Visio `LinePattern` → dash/gap lengths in **inches**.
///
/// Built-in patterns are authored relative to the stroke weight. The table is
/// the complete `VSDContentCollector::_lineProperties` mapping used by
/// libvisio/LibreOffice (`draw:dots*-length` and `draw:distance`, expressed as
/// percentages of the line width).
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
    case 2:
      return scaled(const [6, 3]);
    case 3:
      return scaled(const [1, 3]);
    case 4:
      return scaled(const [6, 3, 1, 3]);
    case 5:
      return scaled(const [6, 3, 1, 3, 1, 3]);
    case 6:
      return scaled(const [6, 3, 6, 3, 1, 3]);
    case 7:
      return scaled(const [14, 2, 6, 2]);
    case 8:
      return scaled(const [14, 2, 6, 2, 6, 2]);
    case 9:
      return scaled(const [3, 2]);
    case 10:
      return scaled(const [1, 2]);
    case 11:
      return scaled(const [3, 2, 1, 2]);
    case 12:
      return scaled(const [3, 2, 1, 2, 1, 2]);
    case 13:
      return scaled(const [3, 2, 3, 2, 1, 2]);
    case 14:
      return scaled(const [7, 2, 3, 2]);
    case 15:
      return scaled(const [7, 2, 3, 2, 3, 2]);
    case 16:
      return scaled(const [11, 5]);
    case 17:
      return scaled(const [1, 5]);
    case 18:
      return scaled(const [11, 5, 1, 5]);
    case 19:
      return scaled(const [11, 5, 1, 5, 1, 5]);
    case 20:
      return scaled(const [11, 5, 11, 5, 1, 5]);
    case 21:
      return scaled(const [27, 5, 11, 5]);
    case 22:
      return scaled(const [27, 5, 11, 5, 11, 5]);
    case 23:
      return scaled(const [2, 2]);
    default:
      // libvisio treats custom/unknown pattern ids as solid until the custom
      // line-pattern stencil is understood. draw.io custom arrays are handled
      // separately by [effectiveDashPatternForLine].
      return null;
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
