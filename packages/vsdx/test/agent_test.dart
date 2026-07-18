import 'dart:convert';

import 'package:test/test.dart';
import 'package:vsdx/agent.dart';
import 'package:vsdx/vsdx.dart';

const _spec = '''
{
  "title": "Flow",
  "layout": { "direction": "TB", "spacing": 0.6 },
  "nodes": [
    { "id": "a", "stencil": "terminator", "text": "Start" },
    { "id": "b", "stencil": "process", "text": "Do work", "fill": "#DAE8FC" },
    { "id": "c", "stencil": "decision", "text": "OK?" },
    { "id": "d", "stencil": "cylinder", "text": "DB" }
  ],
  "edges": [
    { "from": "a", "to": "b" },
    { "from": "b", "to": "c" },
    { "from": "c", "to": "d", "label": "yes" }
  ]
}
''';

List<Map<String, dynamic>> _ops(String json) => <Map<String, dynamic>>[
      for (final o in (jsonDecode(json)['ops'] as List))
        (o as Map).cast<String, dynamic>(),
    ];

void main() {
  group('DiagramSpec.build', () {
    test('produces a round-trip-faithful .vsdx with nodes + connectors', () {
      final bytes = DiagramSpec.parse(_spec).build();
      final doc = const DocumentParser().parse(bytes);

      expect(doc.pages, hasLength(1));
      final page = doc.pages.single;
      final nodes = page.shapes.where((s) => !s.is1D).toList();
      final edges = page.shapes.where((s) => s.is1D).toList();
      expect(nodes, hasLength(4));
      expect(edges, hasLength(3));

      final texts = nodes.map((s) => s.text).toSet();
      expect(texts, containsAll(<String>['Start', 'Do work', 'OK?', 'DB']));

      // Connectors carry page-level Connect rows (glue) for each endpoint.
      expect(page.connects.length, 6);
    });

    test('auto-layout gives every node a distinct position', () {
      final spec = DiagramSpec.parse(_spec);
      spec.build();
      final centres = spec.nodes.map((n) => '${n.cx},${n.cy}').toSet();
      expect(centres, hasLength(spec.nodes.length));
    });

    test('honours a paper-size + landscape page spec', () {
      final bytes = DiagramSpec.parse('''
        { "page": { "size": "letter", "landscape": true },
          "nodes": [ { "id": "x", "text": "X" } ] }
      ''').build();
      final page = const DocumentParser().parse(bytes).pages.single;
      expect(page.widthInches, greaterThan(page.heightInches));
    });
  });

  group('applyOps', () {
    VsdxDocument built() =>
        const DocumentParser().parse(DiagramSpec.parse(_spec).build());

    test('add_shape appends a labelled shape', () {
      final doc = built();
      final before = doc.pages.single.shapes.length;
      final r = applyOps(doc, _ops('''
        { "ops": [ { "op": "add_shape", "stencil": "process",
                     "text": "New", "x": 2, "y": 2 } ] }'''));
      final page = r.document.pages.single;
      expect(page.shapes.length, before + 1);
      expect(page.shapes.any((s) => s.text == 'New'), isTrue);
      expect(r.createdIds, hasLength(1));
    });

    test('set_style + set_text mutate the target shape', () {
      final doc = built();
      final target = doc.pages.single.shapes.firstWhere((s) => s.text == 'Do work');
      final r = applyOps(doc, _ops('''
        { "ops": [
          { "op": "set_style", "ids": ["shape:${target.id}"], "fill": "#F8CECC" },
          { "op": "set_text", "id": ${target.id}, "text": "Renamed" }
        ] }'''));
      final s = r.document.pages.single.shapes.firstWhere((s) => s.id == target.id);
      expect(s.text, 'Renamed');
      expect(s.fill.foreground?.value, 0xFFF8CECC);
    });

    test('delete_shape removes the shape and prunes its connects', () {
      final doc = built();
      final victim = doc.pages.single.shapes.firstWhere((s) => s.text == 'OK?');
      final r = applyOps(doc, _ops('''
        { "ops": [ { "op": "delete_shape", "id": ${victim.id} } ] }'''));
      final page = r.document.pages.single;
      expect(page.shapes.any((s) => s.id == victim.id), isFalse);
      expect(page.connects.any((c) => c.toSheetId == victim.id), isFalse);
    });

    test('applyOpsBytes round-trips through the writer', () {
      final original = DiagramSpec.parse(_spec).build();
      final out = applyOpsBytes(original, '''
        { "ops": [ { "op": "add_shape", "text": "Extra", "x": 1, "y": 1 } ] }''');
      final page = const DocumentParser().parse(out).pages.single;
      expect(page.shapes.any((s) => s.text == 'Extra'), isTrue);
    });
  });

  group('inspect', () {
    test('validate flags dangling connects', () {
      final doc = built();
      // Corrupt: point a connect at a non-existent shape.
      final page = doc.pages.single;
      final broken = page.copyWith(connects: <VsdxConnect>[
        ...page.connects,
        const VsdxConnect(
            fromSheetId: 999, fromCell: 'BeginX', toSheetId: 998, toCell: 'PinX'),
      ]);
      final issues = validateDocument(doc.replacePage(0, broken));
      expect(issues.any((i) => i.severity == 'error'), isTrue);
    });

    test('explain lists shapes and connections', () {
      final md = explainDocument(built());
      expect(md, contains('# Flow'));
      expect(md, contains('Do work'));
      expect(md, contains('—yes→'));
    });
  });

  test('stencil search resolves aliases', () {
    expect(canonicalStencil('database'), 'cylinder');
    expect(canonicalStencil('decision'), 'diamond');
    expect(searchStencils('db').map((e) => e.name), contains('cylinder'));
  });
}

VsdxDocument built() =>
    const DocumentParser().parse(DiagramSpec.parse(_spec).build());
