/// Maps a Diagram Spec `stencil` name to a concrete [VsdxShape] built from the
/// pure-Dart [VsdxShapeFactory].
///
/// Only white-listed geometry commands are used (rect / rounded-rect / ellipse
/// / polygon / cylinder / text box), so every shape round-trips through
/// [VsdxWriter] unchanged. This is the **curated core set** for the initial
/// Agent slice; wiring the full ~300-stencil catalog (`lib/editor/stencils.dart`)
/// is a later milestone — see `docs/MCP_SKILL_PLAN.md` (M5).
library;

import 'package:vsdx/stencils.dart';
import 'package:vsdx/vsdx.dart';

import 'agent_style.dart';

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

/// Resolve [stencil] (case-insensitive, alias-aware) to its canonical core
/// name, or `rectangle` when unknown.
String canonicalStencil(String stencil) => coreNameOrNull(stencil) ?? 'rectangle';

/// The canonical core stencil name for [stencil], or `null` when it isn't a
/// core shape (so callers can fall through to the full catalog).
String? coreNameOrNull(String stencil) {
  final q = stencil.toLowerCase().trim();
  for (final e in kCoreStencils) {
    if (e.name == q || e.aliases.contains(q)) return e.name;
  }
  return null;
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

/// The full ~300-shape library (draw.io parity), indexed by normalised name.
final Map<String, Stencil> _catalogByNorm = <String, Stencil>{
  for (final s in kStencils) _norm(s.name): s,
};
final Map<String, String> _groupByNorm = <String, String>{
  for (final g in kStencilGroups)
    for (final s in g.stencils) _norm(s.name): g.name,
};

/// Resolve [stencil] to a concrete shape: the curated core (clean size + fill),
/// else the full catalog (resized, styling overridden only when given), else a
/// rectangle. This is the single entry point used by build + add_shape.
VsdxShape resolveStencilShape({
  required String stencil,
  required int id,
  required double cx,
  required double cy,
  required double w,
  required double h,
  String? fillHex,
  String? lineHex,
}) {
  final core = coreNameOrNull(stencil);
  if (core != null) {
    return buildStencilShape(
      stencil: core,
      id: id,
      cx: cx,
      cy: cy,
      w: w,
      h: h,
      fill: fillFromHex(fillHex),
      line: lineFromHex(lineHex),
    );
  }
  final cat = _catalogByNorm[_norm(stencil)];
  if (cat != null) {
    var s = cat.build(id, cx, cy).resizeTo(pinX: cx, pinY: cy, width: w, height: h);
    if (fillHex != null && fillHex.trim().isNotEmpty) {
      s = s.copyWith(fill: fillFromHex(fillHex));
    }
    if (lineHex != null && lineHex.trim().isNotEmpty) {
      s = s.copyWith(line: lineFromHex(lineHex));
    }
    return s;
  }
  return buildStencilShape(
    stencil: 'rectangle',
    id: id,
    cx: cx,
    cy: cy,
    w: w,
    h: h,
    fill: fillFromHex(fillHex),
    line: lineFromHex(lineHex),
  );
}

/// Search the curated core **plus** the full ~300-shape catalog by name/group.
List<StencilEntry> searchStencils(String query, {int limit = 10}) {
  final q = _norm(query);
  final results = <StencilEntry>[];
  final seen = <String>{};
  for (final e in kCoreStencils) {
    if (q.isEmpty ||
        _norm(e.name).contains(q) ||
        _norm(e.group).contains(q) ||
        e.aliases.any((a) => _norm(a).contains(q))) {
      results.add(e);
      seen.add(_norm(e.name));
    }
  }
  for (final s in kStencils) {
    if (results.length >= limit) break;
    final n = _norm(s.name);
    if (seen.contains(n)) continue;
    final group = _groupByNorm[n] ?? '';
    if (q.isEmpty || n.contains(q) || _norm(group).contains(q)) {
      results.add(StencilEntry(s.name, group, const <String>[]));
      seen.add(n);
    }
  }
  return results.take(limit).toList();
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
