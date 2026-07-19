/// Default fill/stroke palettes for the stencil library (draw.io-like).
///
/// Applied when a [Stencil] is dropped or clicked into the canvas so new shapes
/// are not plain white/black. Explicit user memo styles in the editor still win.
library;

import 'model/shape.dart';
import 'utils/color.dart';

/// A fill + stroke pair (hex `#RRGGBB` or `#AARRGGBB`).
class StencilColors {
  const StencilColors(this.fill, this.stroke);
  final String fill;
  final String stroke;
}

/// draw.io default palette slots.
const StencilColors kStencilPrimary =
    StencilColors('#DAE8FC', '#6C8EBF');
const StencilColors kStencilSuccess =
    StencilColors('#D5E8D4', '#82B366');
const StencilColors kStencilWarning =
    StencilColors('#FFF2CC', '#D6B656');
const StencilColors kStencilAccent =
    StencilColors('#FFE6CC', '#D79B00');
const StencilColors kStencilDanger =
    StencilColors('#F8CECC', '#B85450');
const StencilColors kStencilNeutral =
    StencilColors('#F5F5F5', '#666666');
const StencilColors kStencilSecondary =
    StencilColors('#E1D5E7', '#9673A6');
const StencilColors kStencilContainer =
    StencilColors('#F5F5F5', '#6C8EBF');

/// Soft brand-ish colours for cloud / vendor libraries.
const StencilColors kStencilAws =
    StencilColors('#FFF8E7', '#D9822B');
const StencilColors kStencilAzure =
    StencilColors('#E3F2FD', '#1565C0');
const StencilColors kStencilGcp =
    StencilColors('#E8F0FE', '#1A73E8');
const StencilColors kStencilCisco =
    StencilColors('#E0F7FA', '#049FD9');
const StencilColors kStencilAlibaba =
    StencilColors('#FFF3E0', '#FF6A00');
const StencilColors kStencilIbm =
    StencilColors('#EDF5FF', '#0F62FE');
const StencilColors kStencilOracle =
    StencilColors('#FCE8E6', '#C74634');

/// Group → default colours. Unknown groups fall back to [kStencilPrimary].
const Map<String, StencilColors> kStencilGroupColors = <String, StencilColors>{
  'General': kStencilPrimary,
  'Flowchart': kStencilPrimary,
  'Arrows': kStencilPrimary,
  'Basic': kStencilPrimary,
  'Containers': kStencilContainer,
  'UML': kStencilSecondary,
  'ER': kStencilSuccess,
  'BPMN': kStencilAccent,
  'Misc': kStencilNeutral,
  'Advanced': kStencilSecondary,
  'Network': StencilColors('#E6F2FF', '#3B7DD8'),
  'Mockup': StencilColors('#ECEFF1', '#546E7A'),
  'Electrical': StencilColors('#FFFDE7', '#F9A825'),
  'Signs': kStencilDanger,
  'Floorplan': StencilColors('#EFEBE9', '#6D4C41'),
  'EIP': StencilColors('#E8F5E9', '#43A047'),
  'AWS': kStencilAws,
  'Azure': kStencilAzure,
  'GCP': kStencilGcp,
  'Cisco': kStencilCisco,
  'Alibaba': kStencilAlibaba,
  'IBM': kStencilIbm,
  'Oracle': kStencilOracle,
};

/// Per-stencil overrides (mainly Flowchart / General semantics).
const Map<String, StencilColors> kStencilNameColors = <String, StencilColors>{
  // Flowchart roles
  'Decision': kStencilWarning,
  'Terminator': kStencilSuccess,
  'Start': kStencilSuccess,
  'Data': kStencilAccent,
  'Document': kStencilSecondary,
  'Multi-Document': kStencilSecondary,
  'Manual Input': kStencilAccent,
  'Manual Operation': kStencilAccent,
  'Preparation': kStencilSecondary,
  'Delay': kStencilWarning,
  'Display': kStencilPrimary,
  'Database': kStencilSuccess,
  'Direct Data': kStencilSuccess,
  'Stored Data': kStencilSuccess,
  'Sequential Data': kStencilSuccess,
  'Internal Storage': kStencilSuccess,
  'Tape': kStencilAccent,
  'Merge': kStencilWarning,
  'Extract': kStencilWarning,
  'Collate': kStencilNeutral,
  'Sort': kStencilNeutral,
  'Or': kStencilNeutral,
  'Summing Junction': kStencilNeutral,
  'Loop Limit': kStencilWarning,
  'Off-Page Ref': kStencilNeutral,
  'On-Page Ref': kStencilNeutral,
  'Annotation': kStencilWarning,
  'Card': kStencilAccent,
  'Step': kStencilPrimary,
  'Transfer': kStencilPrimary,
  'Predefined Process': kStencilPrimary,
  'Parallel Mode': kStencilSecondary,
  // General
  'Diamond': kStencilWarning,
  'Cylinder': kStencilSuccess,
  'Cloud': StencilColors('#E3F2FD', '#5B9BD5'),
  'Note': kStencilWarning,
  'Actor': kStencilNeutral,
  'Data Storage': kStencilSuccess,
  'Container': kStencilContainer,
  'Horizontal Container': kStencilContainer,
  'List': kStencilContainer,
  'Table': kStencilContainer,
  'Callout': kStencilWarning,
  // BPMN
  'Task': kStencilPrimary,
  'User Task': kStencilPrimary,
  'Service Task': kStencilPrimary,
  'Script Task': kStencilSecondary,
  'Manual Task': kStencilAccent,
  'Business Rule Task': kStencilSecondary,
  'Gateway': kStencilWarning,
  'Exclusive Gateway': kStencilWarning,
  'Parallel Gateway': kStencilWarning,
  'Inclusive Gateway': kStencilWarning,
  'Complex Gateway': kStencilWarning,
  'Event-Based Gateway': kStencilWarning,
  'Start Event': kStencilSuccess,
  'Message Start': kStencilSuccess,
  'Timer Start': kStencilSuccess,
  'Intermediate Event': kStencilAccent,
  'Message Intermediate': kStencilAccent,
  'Timer Intermediate': kStencilAccent,
  'End Event': kStencilDanger,
  'Terminate': kStencilDanger,
  'Compensation': kStencilDanger,
  'Data Object': kStencilSecondary,
  'Data Store': kStencilSuccess,
  'Message': kStencilAccent,
  'Pool': kStencilContainer,
  'Horizontal Lane': kStencilContainer,
  'Vertical Lane': kStencilContainer,
  'Vertical Pool': kStencilContainer,
  'Conversation': kStencilSecondary,
  // Misc
  'End': kStencilDanger,
  'Error': kStencilDanger,
  'Event': kStencilSuccess,
};

VsdxColor? _parseHex(String? hex) {
  if (hex == null) return null;
  var h = hex.trim();
  if (h.isEmpty) return null;
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 3) {
    h = h.split('').map((c) => '$c$c').join();
  }
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : VsdxColor(v);
}

/// Resolve colours for a stencil by optional explicit pair, then name, then group.
StencilColors? resolveStencilColors({
  StencilColors? explicit,
  String? name,
  String? group,
}) {
  if (explicit != null) return explicit;
  if (name != null) {
    final byName = kStencilNameColors[name];
    if (byName != null) return byName;
  }
  if (group != null) return kStencilGroupColors[group] ?? kStencilPrimary;
  return kStencilPrimary;
}

/// Apply fill/stroke to a freshly built shape. Skips text boxes (no fill & no
/// line). Preserves arrowheads and dash patterns on 1D / connector-like shapes.
VsdxShape applyStencilStyle(
  VsdxShape shape, {
  StencilColors? colors,
  double lineWeightInches = 0.012,
}) {
  if (colors == null) return shape;

  // Text / invisible decoration: leave alone.
  if (!shape.is1D && !shape.fill.hasFill && !shape.line.hasLine) {
    return shape;
  }

  final fillColor = _parseHex(colors.fill);
  final lineColor = _parseHex(colors.stroke);

  var fill = shape.fill;
  var line = shape.line;

  if (shape.is1D) {
    if (lineColor != null && line.hasLine) {
      line = line.copyWith(
        color: lineColor,
        weightInches: lineWeightInches,
      );
    }
    return identical(line, shape.line) ? shape : shape.copyWith(line: line);
  }

  if (fillColor != null && fill.hasFill) {
    fill = fill.withSolidForeground(fillColor);
  }
  if (lineColor != null && line.hasLine) {
    line = line.copyWith(
      color: lineColor,
      weightInches: lineWeightInches,
    );
  }
  if (identical(fill, shape.fill) && identical(line, shape.line)) {
    return shape;
  }
  return shape.copyWith(fill: fill, line: line);
}
