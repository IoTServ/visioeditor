/// Reverse of [mermaidToSpec]: a `.vsdx` → a Mermaid `flowchart` (structural).
///
/// Emits one node per leaf 2-D shape (label preserved) and one edge per
/// connector, resolving endpoints via the page's `<Connect>` rows. Group
/// shells are skipped so members remain addressable after Group. Styling /
/// exact shapes don't survive (Mermaid is structural), matching drawio's
/// `drawio2mermaid`.
///
/// See `docs/MCP_SKILL_PLAN.md` (M5).
library;

import 'dart:math' as math;

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
    buf.writeln('flowchart ${_inferDirection(page)}');
    final index = page.connectIndex;
    final emitted = <int>{};

    for (final s in _walkShapes(page.shapes)) {
      if (s.is1D || s.children.isNotEmpty) continue;
      emitted.add(s.id);
      buf.writeln('  n${s.id}["${_escape(_label(s), fallback: 'n${s.id}')}"]');
    }
    for (final e in _walkShapes(page.shapes)) {
      if (!e.is1D) continue;
      final ends = index.forConnector(e.id);
      final from =
          ends.where((c) => c.isBegin).map((c) => c.toSheetId).firstOrNull;
      final to = ends.where((c) => c.isEnd).map((c) => c.toSheetId).firstOrNull;
      if (from == null || to == null) continue;
      if (!emitted.contains(from) || !emitted.contains(to)) continue;
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

/// Depth-first walk of [roots] including nested group children.
Iterable<VsdxShape> _walkShapes(Iterable<VsdxShape> roots) sync* {
  for (final s in roots) {
    yield s;
    if (s.children.isNotEmpty) yield* _walkShapes(s.children);
  }
}

/// Infer Mermaid direction from leaf-node page pins (LR vs TD).
String _inferDirection(VsdxPage page) {
  final pins = <Offset2D>[
    for (final s in _walkShapes(page.shapes))
      if (!s.is1D && s.children.isEmpty) page.shapePinPage(s.id),
  ];
  if (pins.length < 2) return 'TD';
  var minX = pins.first.x, maxX = pins.first.x;
  var minY = pins.first.y, maxY = pins.first.y;
  for (final p in pins.skip(1)) {
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
  }
  final spanX = maxX - minX;
  final spanY = maxY - minY;
  // Prefer LR when the layout is clearly wider than tall.
  return spanX > spanY * 1.15 ? 'LR' : 'TD';
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
