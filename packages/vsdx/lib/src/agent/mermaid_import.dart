/// Mermaid `flowchart` / `graph` → [DiagramSpec] (→ `.vsdx`).
///
/// Supports the common flowchart subset: a direction header, node shapes
/// (`[]` `()` `([])` `[()]` `{}` `{{}}` `[//]` `(())`), edge operators
/// (`-->` `---` `-.->` `==>` `--x` `--o`), pipe labels (`-->|text|`) and the
/// inline label form (`A -- text --> B`), and edge chains (`A --> B --> C`).
///
/// Enough to turn most Markdown Mermaid flowcharts into an editable Visio
/// diagram; richer Mermaid types (sequence, gantt, …) are out of scope here.
/// See `docs/MCP_SKILL_PLAN.md` (M5).
library;

import 'diagram_spec.dart';

/// Parse Mermaid [source] into a [DiagramSpec].
DiagramSpec mermaidToSpec(String source) {
  final title = _frontMatterTitle(source);
  var direction = 'TB';
  final nodes = <String, NodeSpec>{};
  final order = <String>[];
  final edges = <EdgeSpec>[];

  NodeSpec node(String id) => nodes.putIfAbsent(id, () {
        order.add(id);
        return NodeSpec(id: id, text: id);
      });

  for (var raw in _statements(source)) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    // Header: "flowchart TD" / "graph LR".
    final header = RegExp(r'^(?:flowchart|graph)\s+([A-Za-z]{2})\b')
        .firstMatch(line);
    if (header != null) {
      direction = _direction(header.group(1)!);
      continue;
    }
    // Skip directives/class/style/subgraph lines we don't model.
    if (RegExp(r'^(subgraph|end|class|classDef|style|linkStyle|click|%%)\b')
        .hasMatch(line)) {
      continue;
    }

    _parseChain(_normalizeInlineLabels(' $line '), node, edges);
  }

  return DiagramSpec(
    title: title,
    direction: direction,
    nodes: <NodeSpec>[for (final id in order) nodes[id]!],
    edges: edges,
  );
}

/// Build `.vsdx` bytes directly from Mermaid text.
List<int> mermaidToVsdx(String source) => mermaidToSpec(source).build();

// --- parsing ---------------------------------------------------------------

final _nodeRe = RegExp(
  r'^([A-Za-z0-9_]+)'
  r'(\[\(.*?\)\]|\(\(.*?\)\)|\(\[.*?\]\)|\{\{.*?\}\}|\[/.*?/\]|\[.*?\]|\(.*?\)|\{.*?\})?',
);

final _edgeRe = RegExp(
  r'^\s*(-\.->|-{2,3}>|={2,}>|--[xo]|-{2,3}|-\.-|={2,})\s*(?:\|([^|]*)\|)?\s*',
);

void _parseChain(
  String statement,
  NodeSpec Function(String id) node,
  List<EdgeSpec> edges,
) {
  var rest = statement.trim();
  String? prev;
  ({String? label, bool arrow})? pending;

  while (rest.isNotEmpty) {
    final nm = _nodeRe.matchAsPrefix(rest);
    if (nm == null) break;
    final id = nm.group(1)!;
    final shapeTok = nm.group(2);
    final n = node(id);
    if (shapeTok != null) {
      final parsed = _parseShape(shapeTok);
      // A later, explicit shape/label wins over the default id text.
      n.stencil = parsed.$1;
      n.text = parsed.$2;
    }
    rest = rest.substring(nm.end).trimLeft();

    if (prev != null && pending != null) {
      edges.add(EdgeSpec(
          from: prev, to: id, label: _nullIfEmpty(pending.label), arrow: pending.arrow));
    }
    prev = id;

    final em = _edgeRe.matchAsPrefix(rest);
    if (em == null) break;
    pending = (label: em.group(2)?.trim(), arrow: em.group(1)!.contains('>') ||
        em.group(1)!.endsWith('x') ||
        em.group(1)!.endsWith('o'));
    rest = rest.substring(em.end).trimLeft();
  }
}

(String, String) _parseShape(String tok) {
  String inner(String open, String close) =>
      _clean(tok.substring(open.length, tok.length - close.length));
  if (tok.startsWith('[(') && tok.endsWith(')]')) return ('cylinder', inner('[(', ')]'));
  if (tok.startsWith('((') && tok.endsWith('))')) return ('ellipse', inner('((', '))'));
  if (tok.startsWith('([') && tok.endsWith('])')) return ('terminator', inner('([', '])'));
  if (tok.startsWith('{{') && tok.endsWith('}}')) return ('hexagon', inner('{{', '}}'));
  if (tok.startsWith('[/') && tok.endsWith('/]')) return ('data', inner('[/', '/]'));
  if (tok.startsWith('[') && tok.endsWith(']')) return ('process', inner('[', ']'));
  if (tok.startsWith('(') && tok.endsWith(')')) return ('rounded', inner('(', ')'));
  if (tok.startsWith('{') && tok.endsWith('}')) return ('diamond', inner('{', '}'));
  return ('process', _clean(tok));
}

String _clean(String s) {
  var t = s.trim();
  if ((t.startsWith('"') && t.endsWith('"')) ||
      (t.startsWith("'") && t.endsWith("'"))) {
    t = t.substring(1, t.length - 1);
  }
  return t
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll('&nbsp;', ' ')
      .trim();
}

String? _nullIfEmpty(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

/// Convert `A -- text --> B` / `A == text ==> B` / `A -. text .-> B` into the
/// canonical pipe-label form so the chain parser handles them uniformly.
String _normalizeInlineLabels(String s) => s
    .replaceAllMapped(RegExp(r'\s--\s+(.+?)\s+-->\s'), (m) => ' -->|${m[1]}| ')
    .replaceAllMapped(RegExp(r'\s==\s+(.+?)\s+==>\s'), (m) => ' ==>|${m[1]}| ')
    .replaceAllMapped(RegExp(r'\s-\.\s+(.+?)\s+\.->\s'), (m) => ' -.->|${m[1]}| ');

Iterable<String> _statements(String source) sync* {
  for (final line in source.split('\n')) {
    var l = line;
    final c = l.indexOf('%%');
    if (c >= 0) l = l.substring(0, c);
    for (final part in l.split(';')) {
      if (part.trim().isNotEmpty) yield part;
    }
  }
}

String _direction(String d) {
  switch (d.toUpperCase()) {
    case 'LR':
    case 'RL':
      return 'LR';
    default:
      return 'TB'; // TD / TB / BT
  }
}

String? _frontMatterTitle(String source) {
  final m = RegExp(r'^---\s*\n(.*?)\n---', dotAll: true).firstMatch(source);
  if (m == null) return null;
  final t = RegExp(r'title:\s*(.+)').firstMatch(m.group(1)!);
  return t?.group(1)?.trim();
}
