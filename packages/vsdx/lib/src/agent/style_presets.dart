/// Named **style presets** for Diagram Spec builds — palette / role / shape
/// hints aligned with drawio-skill's `styles/` schema (subset we can apply in
/// Visio: fill, stroke, text colour, edge colour, page background, stencil).
///
/// Agents may set `"style": "corporate"` on a Spec, pass CLI `--style`, or MCP
/// `create_diagram({ style })`. Explicit node `fill`/`line` always win.
/// See `skills/visioeditor-skill/styles/` and `docs/MCP_SKILL_PLAN.md` (M4).
library;

import 'diagram_spec.dart';

/// A fill + stroke pair from a preset palette slot.
class StyleColors {
  const StyleColors({required this.fill, required this.stroke});
  final String fill;
  final String stroke;
}

/// One named preset (default / corporate / dark …).
class StylePreset {
  const StylePreset({
    required this.name,
    required this.palette,
    required this.roles,
    required this.shapes,
    this.edgeColor,
    this.fontColor,
    this.background,
  });

  final String name;
  final Map<String, StyleColors> palette;
  final Map<String, String> roles; // semantic role → palette key
  final Map<String, String> shapes; // role → draw.io-ish shape hint
  final String? edgeColor;
  final String? fontColor;
  final String? background;

  StyleColors colorsForRole(String? role) {
    final slot = roles[role ?? 'service'] ?? 'primary';
    return palette[slot] ?? palette['primary']!;
  }

  /// Map a role to a visioeditor stencil name, or `null` to leave as-is.
  String? stencilForRole(String? role) {
    final hint = shapes[role ?? 'service'];
    if (hint == null) return null;
    final h = hint.toLowerCase();
    if (h.contains('cylinder')) return 'cylinder';
    if (h.contains('rhombus') || h.contains('diamond')) return 'diamond';
    if (h.contains('swimlane')) return 'swimlane';
    if (h.contains('ellipse') || h.contains('oval')) return 'ellipse';
    if (h.contains('hexagon')) return 'hexagon';
    if (h.contains('rounded=1') || h.contains('rounded=true')) return 'rounded';
    if (h.contains('rounded=0')) return 'rectangle';
    return null;
  }
}

/// Built-in presets (colours match drawio-skill built-ins).
final Map<String, StylePreset> kStylePresets = <String, StylePreset>{
  'default': StylePreset(
    name: 'default',
    palette: const <String, StyleColors>{
      'primary': StyleColors(fill: '#DAE8FC', stroke: '#6C8EBF'),
      'success': StyleColors(fill: '#D5E8D4', stroke: '#82B366'),
      'warning': StyleColors(fill: '#FFF2CC', stroke: '#D6B656'),
      'accent': StyleColors(fill: '#FFE6CC', stroke: '#D79B00'),
      'danger': StyleColors(fill: '#F8CECC', stroke: '#B85450'),
      'neutral': StyleColors(fill: '#F5F5F5', stroke: '#666666'),
      'secondary': StyleColors(fill: '#E1D5E7', stroke: '#9673A6'),
    },
    roles: const <String, String>{
      'service': 'primary',
      'database': 'success',
      'queue': 'warning',
      'gateway': 'accent',
      'error': 'danger',
      'external': 'neutral',
      'security': 'secondary',
    },
    shapes: const <String, String>{
      'service': 'rounded=1',
      'database': 'shape=cylinder3',
      'queue': 'rounded=1',
      'decision': 'rhombus',
      'external': 'rounded=1',
      'container': 'swimlane',
    },
  ),
  'corporate': StylePreset(
    name: 'corporate',
    palette: const <String, StyleColors>{
      'primary': StyleColors(fill: '#E3F2FD', stroke: '#1565C0'),
      'success': StyleColors(fill: '#E8F5E9', stroke: '#2E7D32'),
      'warning': StyleColors(fill: '#FFF9C4', stroke: '#F57C00'),
      'accent': StyleColors(fill: '#FFF3E0', stroke: '#E65100'),
      'danger': StyleColors(fill: '#FFEBEE', stroke: '#C62828'),
      'neutral': StyleColors(fill: '#ECEFF1', stroke: '#455A64'),
      'secondary': StyleColors(fill: '#F3E5F5', stroke: '#6A1B9A'),
    },
    roles: const <String, String>{
      'service': 'primary',
      'database': 'success',
      'queue': 'warning',
      'gateway': 'accent',
      'error': 'danger',
      'external': 'neutral',
      'security': 'secondary',
    },
    shapes: const <String, String>{
      'service': 'rounded=0',
      'database': 'shape=cylinder3',
      'queue': 'rounded=0',
      'decision': 'rhombus',
      'external': 'rounded=0',
      'container': 'swimlane',
    },
  ),
  'dark': StylePreset(
    name: 'dark',
    palette: const <String, StyleColors>{
      'primary': StyleColors(fill: '#004870', stroke: '#33B6FF'),
      'success': StyleColors(fill: '#007052', stroke: '#33FFC7'),
      'warning': StyleColors(fill: '#5A4916', stroke: '#D7B85B'),
      'accent': StyleColors(fill: '#705100', stroke: '#FFC633'),
      'danger': StyleColors(fill: '#502220', stroke: '#C4716E'),
      'neutral': StyleColors(fill: '#383838', stroke: '#999999'),
      'secondary': StyleColors(fill: '#3D2C45', stroke: '#A182B0'),
    },
    roles: const <String, String>{
      'service': 'primary',
      'database': 'success',
      'queue': 'warning',
      'gateway': 'accent',
      'error': 'danger',
      'external': 'neutral',
      'security': 'secondary',
    },
    shapes: const <String, String>{
      'service': 'rounded=1',
      'database': 'shape=cylinder3',
      'queue': 'rounded=1',
      'decision': 'rhombus',
      'external': 'rounded=1',
      'container': 'swimlane',
    },
    edgeColor: '#BBBBBB',
    fontColor: '#F0F0F0',
    background: '#1E1E1E',
  ),
};

/// Sorted preset names for CLI / MCP discovery.
List<String> listStylePresets() =>
    (kStylePresets.keys.toList()..sort());

/// Look up a preset by [name], or `null` if unknown.
StylePreset? stylePreset(String name) => kStylePresets[name.trim().toLowerCase()];

/// Apply [styleName] to [spec]: fill gaps in fill/line/textColor/stencil from
/// roles, and edge/page colours from extras. Unknown name throws.
///
/// Nodes with an explicit `fill`/`line` keep them. When [role] is set (or the
/// stencil is still the default `rectangle`), role→stencil mapping may apply.
DiagramSpec applyStylePreset(DiagramSpec spec, String styleName) {
  final preset = stylePreset(styleName);
  if (preset == null) {
    throw ArgumentError(
        'unknown style "$styleName" (known: ${listStylePresets().join(', ')})');
  }

  final nodes = <NodeSpec>[
    for (final n in spec.nodes)
      () {
        final colors = preset.colorsForRole(n.role);
        final mapped = preset.stencilForRole(n.role);
        final useMapped = mapped != null &&
            (n.role != null || n.stencil == 'rectangle');
        return NodeSpec(
          id: n.id,
          stencil: useMapped ? mapped : n.stencil,
          text: n.text,
          x: n.x,
          y: n.y,
          w: n.w,
          h: n.h,
          fill: n.fill ?? colors.fill,
          line: n.line ?? colors.stroke,
          textColor: n.textColor ?? preset.fontColor,
          bold: n.bold,
          role: n.role,
        );
      }(),
  ];

  final edges = <EdgeSpec>[
    for (final e in spec.edges)
      EdgeSpec(
        from: e.from,
        to: e.to,
        label: e.label,
        line: e.line ?? preset.edgeColor,
        arrow: e.arrow,
      ),
  ];

  return DiagramSpec(
    title: spec.title,
    // Already applied — avoid double-applying in [DiagramSpec.build].
    style: null,
    direction: spec.direction,
    spacing: spec.spacing,
    page: PageSpec(
      width: spec.page.width,
      height: spec.page.height,
      background: spec.page.background ?? preset.background,
    ),
    nodes: nodes,
    edges: edges,
  );
}
