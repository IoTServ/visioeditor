/// Declarative **Diagram Spec** (v0) → `.vsdx` bytes.
///
/// A spec lists `nodes` (optionally with explicit inch coordinates) and `edges`;
/// when coordinates are omitted a simple layered auto-layout places them. The
/// document is assembled with [VsdxShapeFactory] + [VsdxWriter] exactly like
/// `tool/gen_example_templates.dart`, so the output round-trips faithfully and
/// renders identically in the editor.
///
/// Schema reference: `skills/visioeditor-skill/references/spec-schema.md`.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vsdx/vsdx.dart';

import 'agent_style.dart';
import 'stencil_catalog.dart';

/// A node in a [DiagramSpec]. Coordinates ([x]/[y]) are page inches with the
/// origin at the bottom-left (Visio convention); omit them to auto-layout.
class NodeSpec {
  NodeSpec({
    required this.id,
    this.stencil = 'rectangle',
    this.text = '',
    this.x,
    this.y,
    this.w,
    this.h,
    this.fill,
    this.line,
    this.textColor,
    this.bold = false,
  });

  factory NodeSpec.fromJson(Map<String, dynamic> j) => NodeSpec(
        id: '${j['id']}',
        stencil: (j['stencil'] ?? j['shape'] ?? 'rectangle').toString(),
        text: (j['text'] ?? j['label'] ?? '').toString(),
        x: _d(j['x']),
        y: _d(j['y']),
        w: _d(j['w'] ?? j['width']),
        h: _d(j['h'] ?? j['height']),
        fill: j['fill']?.toString(),
        line: (j['line'] ?? j['stroke'])?.toString(),
        textColor: (j['textColor'] ?? j['fontColor'])?.toString(),
        bold: j['bold'] == true,
      );

  final String id;
  String stencil;
  String text;
  double? x;
  double? y;
  double? w;
  double? h;
  final String? fill;
  final String? line;
  final String? textColor;
  final bool bold;

  // Resolved by layout:
  double cx = 0;
  double cy = 0;
  double rw = 1.7;
  double rh = 0.9;
  int shapeId = 0;
}

/// A directed edge between two node ids.
class EdgeSpec {
  EdgeSpec({
    required this.from,
    required this.to,
    this.label,
    this.line,
    this.arrow = true,
  });

  factory EdgeSpec.fromJson(Map<String, dynamic> j) => EdgeSpec(
        from: '${j['from'] ?? j['source']}',
        to: '${j['to'] ?? j['target']}',
        label: j['label']?.toString(),
        line: (j['line'] ?? j['stroke'])?.toString(),
        arrow: j['arrow'] == null
            ? true
            : (j['arrow'].toString().toLowerCase() != 'none' &&
                j['arrow'] != false),
      );

  final String from;
  final String to;
  final String? label;
  final String? line;
  final bool arrow;
}

/// Page-level settings for a [DiagramSpec].
class PageSpec {
  PageSpec({this.width, this.height, this.background});

  factory PageSpec.fromJson(Map<String, dynamic> j) {
    double? w = _d(j['width']);
    double? h = _d(j['height']);
    final size = j['size']?.toString().toLowerCase();
    if (size != null && _paperSizes.containsKey(size)) {
      final (pw, ph) = _paperSizes[size]!;
      w ??= pw;
      h ??= ph;
    }
    final landscape = j['landscape'] == true;
    if (landscape && w != null && h != null && h > w) {
      final t = w;
      w = h;
      h = t;
    }
    return PageSpec(width: w, height: h, background: j['background']?.toString());
  }

  final double? width;
  final double? height;
  final String? background;

  static const Map<String, (double, double)> _paperSizes = {
    'letter': (8.5, 11.0),
    'legal': (8.5, 14.0),
    'tabloid': (11.0, 17.0),
    'a3': (11.69, 16.54),
    'a4': (8.27, 11.69),
    'a5': (5.83, 8.27),
  };
}

/// A full diagram description parsed from JSON.
class DiagramSpec {
  DiagramSpec({
    this.title,
    this.direction = 'TB',
    this.spacing = 0.6,
    PageSpec? page,
    List<NodeSpec>? nodes,
    List<EdgeSpec>? edges,
  })  : page = page ?? PageSpec(),
        nodes = nodes ?? <NodeSpec>[],
        edges = edges ?? <EdgeSpec>[];

  factory DiagramSpec.fromJson(Map<String, dynamic> j) {
    final layout = (j['layout'] as Map?)?.cast<String, dynamic>();
    return DiagramSpec(
      title: j['title']?.toString(),
      direction:
          (layout?['direction'] ?? j['direction'] ?? 'TB').toString().toUpperCase(),
      spacing: _d(layout?['spacing'] ?? j['spacing']) ?? 0.6,
      page: PageSpec.fromJson(
          ((j['page'] as Map?)?.cast<String, dynamic>()) ?? const {}),
      nodes: <NodeSpec>[
        for (final n in (j['nodes'] as List? ?? const []))
          NodeSpec.fromJson((n as Map).cast<String, dynamic>()),
      ],
      edges: <EdgeSpec>[
        for (final e in (j['edges'] as List? ?? const []))
          EdgeSpec.fromJson((e as Map).cast<String, dynamic>()),
      ],
    );
  }

  static DiagramSpec parse(String jsonText) =>
      DiagramSpec.fromJson((jsonDecode(jsonText) as Map).cast<String, dynamic>());

  final String? title;
  final String direction;
  final double spacing;
  final PageSpec page;
  final List<NodeSpec> nodes;
  final List<EdgeSpec> edges;

  /// Build the `.vsdx` bytes for this spec.
  Uint8List build() => buildDiagramBytes(this);
}

double? _d(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

/// Simple layered auto-layout. Mutates each node's `cx/cy/rw/rh` and returns
/// the page size (inches) needed to fit the result plus margins.
({double pageW, double pageH}) layoutDiagram(
  List<NodeSpec> nodes,
  List<EdgeSpec> edges, {
  String direction = 'TB',
  double spacing = 0.6,
  double defaultW = 1.7,
  double defaultH = 0.9,
  double margin = 0.8,
}) {
  for (final n in nodes) {
    n.rw = (n.w ?? defaultW).abs();
    n.rh = (n.h ?? defaultH).abs();
  }
  if (nodes.isEmpty) return (pageW: 8.5, pageH: 11.0);

  final explicit = nodes.every((n) => n.x != null && n.y != null);
  if (explicit) {
    var maxX = 0.0, maxY = 0.0;
    for (final n in nodes) {
      n.cx = n.x!;
      n.cy = n.y!;
      maxX = math.max(maxX, n.cx + n.rw / 2);
      maxY = math.max(maxY, n.cy + n.rh / 2);
    }
    return (pageW: maxX + margin, pageH: maxY + margin);
  }

  // Longest-path layering (cycle-safe: bounded relaxation).
  final idIndex = <String, int>{for (var i = 0; i < nodes.length; i++) nodes[i].id: i};
  final layer = List<int>.filled(nodes.length, 0);
  for (var iter = 0; iter < nodes.length; iter++) {
    var changed = false;
    for (final e in edges) {
      final u = idIndex[e.from];
      final v = idIndex[e.to];
      if (u == null || v == null) continue;
      if (layer[v] < layer[u] + 1) {
        layer[v] = layer[u] + 1;
        changed = true;
      }
    }
    if (!changed) break;
  }
  final maxLayer = layer.reduce(math.max);
  final byLayer = <int, List<int>>{};
  for (var i = 0; i < nodes.length; i++) {
    byLayer.putIfAbsent(layer[i], () => <int>[]).add(i);
  }

  final tb = direction.toUpperCase() != 'LR';
  final layerMain = <int, double>{}; // max size along the layer axis
  final layerCross = <int, double>{}; // total size across the layer
  for (final entry in byLayer.entries) {
    var main = 0.0, cross = 0.0;
    for (final i in entry.value) {
      main = math.max(main, tb ? nodes[i].rh : nodes[i].rw);
      cross += tb ? nodes[i].rw : nodes[i].rh;
    }
    cross += spacing * (entry.value.length - 1);
    layerMain[entry.key] = main;
    layerCross[entry.key] = cross;
  }
  var maxCross = 0.0;
  for (final c in layerCross.values) {
    maxCross = math.max(maxCross, c);
  }

  var cursor = margin;
  final layerStart = <int, double>{};
  for (var l = 0; l <= maxLayer; l++) {
    layerStart[l] = cursor;
    cursor += (layerMain[l] ?? 0) + spacing;
  }
  final pageMain = cursor - spacing + margin;
  final pageCross = maxCross + margin * 2;
  final pageW = tb ? pageCross : pageMain;
  final pageH = tb ? pageMain : pageCross;

  for (var l = 0; l <= maxLayer; l++) {
    final list = byLayer[l] ?? const <int>[];
    var crossCursor = margin + (maxCross - (layerCross[l] ?? 0)) / 2;
    final mainCenter = (layerStart[l] ?? margin) + (layerMain[l] ?? 0) / 2;
    for (final i in list) {
      final n = nodes[i];
      final crossSize = tb ? n.rw : n.rh;
      final crossCenter = crossCursor + crossSize / 2;
      crossCursor += crossSize + spacing;
      if (tb) {
        n.cx = crossCenter;
        n.cy = pageH - mainCenter; // flip to Visio Y-up
      } else {
        n.cx = mainCenter;
        n.cy = pageH - crossCenter;
      }
    }
  }
  return (pageW: pageW, pageH: pageH);
}

/// Assemble the `.vsdx` bytes for [spec].
Uint8List buildDiagramBytes(DiagramSpec spec) {
  final laid = layoutDiagram(
    spec.nodes,
    spec.edges,
    direction: spec.direction,
    spacing: spec.spacing,
  );
  final pageW = spec.page.width ?? laid.pageW;
  final pageH = spec.page.height ?? laid.pageH;

  const writer = VsdxWriter();
  final blank = writer.emptyDocument(
    widthInches: pageW,
    heightInches: pageH,
    title: spec.title,
  );
  var doc = const DocumentParser().parse(blank);

  var nextId = 1;
  final byNodeId = <String, VsdxShape>{};
  final shapes = <VsdxShape>[];
  for (final n in spec.nodes) {
    n.shapeId = nextId++;
    var s = buildStencilShape(
      stencil: n.stencil,
      id: n.shapeId,
      cx: n.cx,
      cy: n.cy,
      w: n.rw,
      h: n.rh,
      fill: fillFromHex(n.fill),
      line: lineFromHex(n.line),
    );
    if (n.text.isNotEmpty) {
      s = withLabel(s, n.text, bold: n.bold, colorHex: n.textColor);
    }
    byNodeId[n.id] = s;
    shapes.add(s);
  }

  final connects = <VsdxConnect>[];
  for (final e in spec.edges) {
    final a = byNodeId[e.from];
    final b = byNodeId[e.to];
    if (a == null || b == null) continue;
    final link = buildConnector(
      id: nextId++,
      a: a,
      b: b,
      label: e.label,
      lineHex: e.line,
      arrow: e.arrow,
    );
    shapes.add(link.connector);
    connects.addAll(link.connects);
  }

  final bg = parseColorOrNull(spec.page.background);
  var page = doc.pages.first.copyWith(
    name: spec.title ?? 'Page-1',
    widthInches: pageW,
    heightInches: pageH,
    shapes: shapes,
    connects: connects,
    backgroundColor: bg,
  );
  page = page.rerouteConnectors();
  doc = doc
      .replacePage(0, page)
      .copyWith(title: spec.title, creator: 'Editor for Visio Diagrams');
  return writer.write(originalBytes: blank, edited: doc);
}
