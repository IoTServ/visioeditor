/// Maps a Diagram Spec `stencil` name to a concrete [VsdxShape] built from the
/// pure-Dart [VsdxShapeFactory].
///
/// Only white-listed geometry commands are used (rect / rounded-rect / ellipse
/// / polygon / cylinder / text box), so every shape round-trips through
/// [VsdxWriter] unchanged. This is the **curated core set** for the initial
/// Agent slice; wiring the full ~300-stencil catalog (`lib/editor/stencils.dart`)
/// is a later milestone — see `docs/MCP_SKILL_PLAN.md` (M5).
library;

import 'package:vsdx/vsdx.dart';

/// One entry in the searchable stencil catalog.
class StencilEntry {
  const StencilEntry(this.name, this.group, this.aliases);
  final String name;
  final String group;
  final List<String> aliases;
}

/// The curated core stencils, grouped like draw.io's everyday libraries.
const List<StencilEntry> kCoreStencils = <StencilEntry>[
  StencilEntry('rectangle', 'General', ['process', 'box', 'node', 'task', 'step']),
  StencilEntry('rounded', 'General', ['roundedrectangle', 'roundrect']),
  StencilEntry('ellipse', 'General', ['oval', 'circle']),
  StencilEntry('terminator', 'Flowchart', ['start', 'end', 'state']),
  StencilEntry('diamond', 'Flowchart', ['decision', 'condition', 'gateway']),
  StencilEntry('data', 'Flowchart', ['parallelogram', 'io', 'input', 'output']),
  StencilEntry('hexagon', 'Flowchart', ['preparation']),
  StencilEntry('triangle', 'General', []),
  StencilEntry('cylinder', 'Containers', ['database', 'db', 'store', 'storage']),
  StencilEntry('text', 'General', ['textbox', 'label', 'note']),
];

/// Resolve [stencil] (case-insensitive, alias-aware) to its canonical name, or
/// `rectangle` when unknown.
String canonicalStencil(String stencil) {
  final q = stencil.toLowerCase().trim();
  for (final e in kCoreStencils) {
    if (e.name == q || e.aliases.contains(q)) return e.name;
  }
  return 'rectangle';
}

/// Fuzzy search over the catalog names + aliases.
List<StencilEntry> searchStencils(String query, {int limit = 10}) {
  final q = query.toLowerCase().trim();
  if (q.isEmpty) return kCoreStencils.take(limit).toList();
  final hits = <StencilEntry>[
    for (final e in kCoreStencils)
      if (e.name.contains(q) ||
          e.group.toLowerCase().contains(q) ||
          e.aliases.any((a) => a.contains(q)))
        e,
  ];
  return hits.take(limit).toList();
}

/// Build a 2-D shape for [stencil], centred at ([cx],[cy]) inches, [w]×[h].
VsdxShape buildStencilShape({
  required String stencil,
  required int id,
  required double cx,
  required double cy,
  required double w,
  required double h,
  required VsdxFill fill,
  required VsdxLine line,
}) {
  VsdxShape poly(List<Offset2D> unit) => VsdxShapeFactory.polygon(
        id: id,
        pinX: cx,
        pinY: cy,
        width: w,
        height: h,
        unit: unit,
        fill: fill,
        line: line,
      );

  switch (canonicalStencil(stencil)) {
    case 'rounded':
      return VsdxShapeFactory.roundedRectangle(
          id: id, pinX: cx, pinY: cy, width: w, height: h, fill: fill, line: line);
    case 'ellipse':
    case 'terminator':
      return VsdxShapeFactory.ellipse(
          id: id, pinX: cx, pinY: cy, width: w, height: h, fill: fill, line: line);
    case 'diamond':
      return poly(const <Offset2D>[
        Offset2D(0.5, 1),
        Offset2D(1, 0.5),
        Offset2D(0.5, 0),
        Offset2D(0, 0.5),
      ]);
    case 'data':
      return poly(const <Offset2D>[
        Offset2D(0.25, 0),
        Offset2D(1, 0),
        Offset2D(0.75, 1),
        Offset2D(0, 1),
      ]);
    case 'hexagon':
      return poly(const <Offset2D>[
        Offset2D(0.25, 0),
        Offset2D(0.75, 0),
        Offset2D(1, 0.5),
        Offset2D(0.75, 1),
        Offset2D(0.25, 1),
        Offset2D(0, 0.5),
      ]);
    case 'triangle':
      return poly(const <Offset2D>[
        Offset2D(0.5, 1),
        Offset2D(1, 0),
        Offset2D(0, 0),
      ]);
    case 'cylinder':
      return VsdxShapeFactory.cylinder(
          id: id, pinX: cx, pinY: cy, width: w, height: h, fill: fill, line: line);
    case 'text':
      return VsdxShapeFactory.textBox(
          id: id, pinX: cx, pinY: cy, width: w, height: h, text: '');
    case 'rectangle':
    default:
      return VsdxShapeFactory.rectangle(
          id: id, pinX: cx, pinY: cy, width: w, height: h, fill: fill, line: line);
  }
}
