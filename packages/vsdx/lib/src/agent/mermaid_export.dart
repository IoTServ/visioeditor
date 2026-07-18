/// Reverse of [mermaidToSpec]: a `.vsdx` → a Mermaid `flowchart` (structural).
///
/// Emits one node per 2-D shape (label preserved) and one edge per connector,
/// resolving endpoints via the page's `<Connect>` rows. Styling / exact shapes
/// don't survive (Mermaid is structural), matching drawio's `drawio2mermaid`.
/// Handy for dropping a diagram into a Markdown README that GitHub renders.
///
/// See `docs/MCP_SKILL_PLAN.md` (M5).
library;

import 'package:collection/collection.dart';
import 'package:vsdx/vsdx.dart';

/// Convert [doc] (or a single [pageIndex]) to Mermaid `flowchart` text.
/// Set [fenced] to wrap each page in a ```` ```mermaid ```` block.
String documentToMermaid(VsdxDocument doc, {int? pageIndex, bool fenced = false}) {
  final buf = StringBuffer();
  final pages = pageIndex == null
      ? doc.pages
      : <VsdxPage>[doc.pages[pageIndex.clamp(0, doc.pages.length - 1)]];

  for (final page in pages) {
    if (fenced) buf.writeln('```mermaid');
    buf.writeln('flowchart TD');
    final index = page.connectIndex;

    for (final s in page.shapes) {
      if (s.is1D) continue;
      buf.writeln('  n${s.id}["${_escape(_label(s), fallback: 'n${s.id}')}"]');
    }
    for (final e in page.shapes) {
      if (!e.is1D) continue;
      final ends = index.forConnector(e.id);
      final from =
          ends.where((c) => c.isBegin).map((c) => c.toSheetId).firstOrNull;
      final to = ends.where((c) => c.isEnd).map((c) => c.toSheetId).firstOrNull;
      if (from == null || to == null) continue;
      final label = _label(e).trim();
      if (label.isEmpty) {
        buf.writeln('  n$from --> n$to');
      } else {
        buf.writeln('  n$from -->|${_escape(label)}| n$to');
      }
    }
    if (fenced) buf.writeln('```');
    buf.writeln();
  }
  return '${buf.toString().trimRight()}\n';
}

String _label(VsdxShape s) {
  final t = s.text ?? s.richText.plainText;
  return t.trim();
}

String _escape(String s, {String fallback = ''}) {
  final t = s.isEmpty ? fallback : s;
  return t
      .replaceAll('\n', ' ')
      .replaceAll('"', "'")
      .replaceAll('|', '/');
}
