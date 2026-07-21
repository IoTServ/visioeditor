import 'dart:convert';
import 'dart:io';

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

    test('add_connector refuses 1-D from/to targets', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final box = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 1,
        height: 1,
      );
      final ink = VsdxShapeFactory.freehand(
        id: 2,
        points: const <Offset2D>[
          Offset2D(4, 2),
          Offset2D(5, 3),
        ],
      );
      doc = doc.replacePage(
        0,
        doc.pages.first.copyWith(shapes: <VsdxShape>[box, ink]),
      );
      final before = doc.pages.single.shapes.length;
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{'op': 'add_connector', 'from': 1, 'to': 2},
      ]);
      expect(r.document.pages.single.shapes.length, before);
      expect(r.log.any((m) => m.contains('2-D')), isTrue);
    });

    test('set_style logs invalid fill color instead of silent no-op', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(
          VsdxShapeFactory.rectangle(
            id: id,
            pinX: 2,
            pinY: 2,
            width: 1,
            height: 1,
            fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000)),
          ),
        ),
      );
      final before = doc.pages.first.findShapeById(id)!.fill.foreground?.value;
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'fill': 'not-a-color',
        },
      ]);
      expect(
        r.document.pages.first.findShapeById(id)!.fill.foreground?.value,
        before,
      );
      expect(r.log.any((m) => m.contains('invalid fill')), isTrue);
    });

    test('set_style fill none keeps colour like UI setNoFill', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(
          VsdxShapeFactory.rectangle(
            id: id,
            pinX: 2,
            pinY: 2,
            width: 1,
            height: 1,
            fill: const VsdxFill(
              foreground: VsdxColor(0xFF123456),
              foregroundTransparency: 0.25,
              themeForegroundIndex: ThemeSlot.accent1,
            ),
          ),
        ),
      );
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'fill': 'none',
        },
      ]);
      final fill = r.document.pages.first.findShapeById(id)!.fill;
      expect(fill.pattern, 0);
      expect(fill.hasFill, isFalse);
      expect(fill.foreground?.value, 0xFF123456);
      expect(fill.foregroundTransparency, closeTo(0.25, 1e-9));
      expect(fill.themeForegroundIndex, isNull);
      expect(fill.gradient, isNull);
      expect(
        r.document.pages.first.findShapeById(id)!.geometries.every((g) => g.noFill),
        isTrue,
      );
    });

    test('add_connector line none hides the stroke', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      doc = doc.replacePage(
        0,
        doc.pages.first.copyWith(
          shapes: <VsdxShape>[
            VsdxShapeFactory.rectangle(
              id: 1,
              pinX: 2,
              pinY: 3,
              width: 1,
              height: 1,
            ),
            VsdxShapeFactory.rectangle(
              id: 2,
              pinX: 6,
              pinY: 3,
              width: 1,
              height: 1,
            ),
          ],
        ),
      );
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'add_connector',
          'from': 1,
          'to': 2,
          'line': 'none',
        },
      ]);
      expect(r.createdIds, hasLength(1));
      final c = r.document.pages.single.findShapeById(r.createdIds.single)!;
      expect(c.line.hasLine, isFalse);
      expect(c.line.pattern, 0);
      // Geometry NoLine must track LinePattern=0 so Edraw does not stroke.
      expect(c.geometries.isNotEmpty, isTrue);
      expect(c.geometries.every((g) => g.noLine), isTrue);
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

    test('set_style line color preserves begin/end arrows', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      final line = VsdxShapeFactory.line(
        id: id,
        ax: 1,
        ay: 1,
        bx: 3,
        by: 1,
      ).copyWith(
        line: const VsdxLine(
          color: VsdxColor(0xFF333333),
          weightInches: 0.02,
          beginArrow: 1,
          endArrow: 4,
          beginArrowSizeInches: 0.15,
          endArrowSizeInches: 0.2,
        ),
      );
      doc = doc.replacePage(0, doc.pages.first.addShape(line));
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'line': '#FF0000',
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      expect(after.line.color?.value, 0xFFFF0000);
      expect(after.line.beginArrow, 1);
      expect(after.line.endArrow, 4);
      expect(after.line.beginArrowSizeInches, closeTo(0.15, 1e-9));
      expect(after.line.endArrowSizeInches, closeTo(0.2, 1e-9));
      expect(after.line.weightInches, closeTo(0.02, 1e-9));
    });

    test('set_style weight / arrows / textColor / opacity', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(
          VsdxShapeFactory.rectangle(
            id: id,
            pinX: 1,
            pinY: 1,
            width: 2,
            height: 1,
          ).copyWith(text: 'Label'),
        ),
      );
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'weight': 0.04,
          'beginArrow': 1,
          'endArrow': 4,
          'textColor': '#FF0000',
          'bold': true,
          'opacity': 0.5,
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      expect(after.line.weightInches, closeTo(0.04, 1e-9));
      expect(after.line.beginArrow, 1);
      expect(after.line.endArrow, 4);
      expect(after.fill.foregroundTransparency, closeTo(0.5, 1e-9));
      expect(after.richText.runs.first.charStyle.color?.value, 0xFFFF0000);
      expect(after.richText.runs.first.charStyle.style.bold, isTrue);
      expect(after.text, 'Label');
    });

    test('set_style dash / rounding / softEdges / pt / verticalAlign', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(
          VsdxShapeFactory.rectangle(
            id: id,
            pinX: 1,
            pinY: 1,
            width: 2,
            height: 1,
          ).copyWith(text: 'Label'),
        ),
      );
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'linePattern': 2,
          'rounding': 0.1,
          'softEdges': 0.05,
          'compoundType': 1,
          'beginArrowSize': 0.2,
          'endArrowSize': 0.25,
          'lineTransparency': 0.3,
          'pt': 14,
          'verticalAlign': 'top',
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      expect(after.line.pattern, 2);
      expect(after.line.roundingInches, closeTo(0.1, 1e-9));
      expect(after.line.softEdgesInches, closeTo(0.05, 1e-9));
      expect(after.line.compoundType, 1);
      expect(after.line.beginArrowSizeInches, closeTo(0.2, 1e-9));
      expect(after.line.endArrowSizeInches, closeTo(0.25, 1e-9));
      expect(after.line.transparency, closeTo(0.3, 1e-9));
      expect(after.richText.runs.first.charStyle.fontSizeInches,
          closeTo(14 / 72, 1e-9));
      expect(after.richText.textBlock.verticalAlign, VsdxVertAlign.top);
    });

    test('set_style glow and shadow', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(
          VsdxShapeFactory.rectangle(
            id: id,
            pinX: 1,
            pinY: 1,
            width: 2,
            height: 1,
          ),
        ),
      );
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'glow': true,
          'glowSize': 0.12,
          'glowColor': '#00AADD',
          'shadow': true,
          'shadowColor': '#333333',
          'shadowBlur': 0.08,
          'shadowOffsetX': 0.1,
          'shadowOffsetY': 0.15,
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      expect(after.glow.enabled, isTrue);
      expect(after.glow.sizeInches, closeTo(0.12, 1e-9));
      expect(after.glow.color?.value, 0xFF00AADD);
      expect(after.shadow.enabled, isTrue);
      expect(after.shadow.color?.value, 0xFF333333);
      expect(after.shadow.blurInches, closeTo(0.08, 1e-9));
      expect(after.shadow.offsetXInches, closeTo(0.1, 1e-9));
      expect(after.shadow.offsetYInches, closeTo(0.15, 1e-9));
      final off = applyOps(r.document, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'glow': 'none',
          'shadow': false,
        },
      ]);
      final cleared = off.document.pages.first.findShapeById(id)!;
      expect(cleared.glow.enabled, isFalse);
      expect(cleared.shadow.enabled, isFalse);
    });

    test('set_style reflection enable and size', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(
          VsdxShapeFactory.rectangle(
            id: id,
            pinX: 1,
            pinY: 1,
            width: 2,
            height: 1,
          ),
        ),
      );
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'reflection': true,
          'reflectionSize': 0.4,
          'reflectionDist': 0.05,
          'reflectionBlur': 0.02,
          'reflectionTransparency': 0.5,
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      expect(after.reflection.enabled, isTrue);
      expect(after.reflection.sizeInches, closeTo(0.4, 1e-9));
      expect(after.reflection.distanceInches, closeTo(0.05, 1e-9));
      expect(after.reflection.blurInches, closeTo(0.02, 1e-9));
      expect(after.reflection.transparency, closeTo(0.5, 1e-9));
      final off = applyOps(r.document, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'reflection': 'none',
        },
      ]);
      expect(off.document.pages.first.findShapeById(id)!.reflection.enabled,
          isFalse);
    });

    test('set_style hideText / lineCap / italic / align', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(
          VsdxShapeFactory.rectangle(
            id: id,
            pinX: 1,
            pinY: 1,
            width: 2,
            height: 1,
          ).copyWith(text: 'Hi'),
        ),
      );
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'hideText': true,
          'lineCap': 'square',
          'italic': true,
          'bold': true,
          'align': 'center',
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      expect(after.richText.textBlock.hideText, isTrue);
      expect(after.line.cap, LineCap.square);
      expect(after.richText.runs.first.charStyle.style.italic, isTrue);
      expect(after.richText.runs.first.charStyle.style.bold, isTrue);
      expect(after.richText.runs.first.paraStyle.horizontalAlign,
          VsdxHorzAlign.center);
    });

    test('set_style fillGradient and lineGradient', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(
          VsdxShapeFactory.rectangle(
            id: id,
            pinX: 1,
            pinY: 1,
            width: 2,
            height: 1,
          ),
        ),
      );
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'fillGradient': <String, dynamic>{
            'type': 'linear',
            'stops': <Map<String, dynamic>>[
              <String, dynamic>{'pos': 0, 'color': '#FF0000'},
              <String, dynamic>{'pos': 1, 'color': '#0000FF'},
            ],
          },
          'lineGradient': true,
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      expect(after.fill.hasGradient, isTrue);
      expect(after.fill.gradient!.stops, hasLength(2));
      expect(after.fill.gradient!.stops.first.color?.value, 0xFFFF0000);
      expect(after.line.hasGradient, isTrue);
      final cleared = applyOps(r.document, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'fillGradient': 'none',
          'lineGradient': false,
        },
      ]);
      final done = cleared.document.pages.first.findShapeById(id)!;
      expect(done.fill.hasGradient, isFalse);
      expect(done.line.hasGradient, isFalse);
    });

    test('set_style bold on empty text keeps Character style', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(
          VsdxShapeFactory.rectangle(
            id: id,
            pinX: 1,
            pinY: 1,
            width: 2,
            height: 1,
          ).copyWith(
            // Master-like: Character present, no visible text.
            richText: VsdxRichText(runs: [
              VsdxTextRun(
                text: '',
                charStyle: const VsdxCharStyle(
                  fontSizeInches: 14 / 72,
                  color: VsdxColor(0xFF336699),
                ),
              ),
            ]),
          ),
        ),
      );
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'bold': true,
          'italic': true,
          'underline': true,
          'pt': 18,
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      expect(after.richText.runs, isNotEmpty);
      expect(after.richText.runs.first.charStyle.style.bold, isTrue);
      expect(after.richText.runs.first.charStyle.style.italic, isTrue);
      expect(after.richText.runs.first.charStyle.underline, isTrue);
      expect(after.richText.runs.first.charStyle.fontSizeInches,
          closeTo(18 / 72, 1e-9));
      expect(after.richText.runs.first.charStyle.color?.value, 0xFF336699);
    });

    test('set_style fillPattern and fillBackground', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(
          VsdxShapeFactory.rectangle(
            id: id,
            pinX: 1,
            pinY: 1,
            width: 2,
            height: 1,
          ),
        ),
      );
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'fillPattern': 3,
          'fillBackground': '#00AA00',
          'fontFamily': 'Arial',
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      expect(after.fill.pattern, 3);
      expect(after.fill.background?.value, 0xFF00AA00);
      expect(after.fill.gradient, isNull);
      expect(after.richText.runs.first.charStyle.fontFamily, 'Arial');
    });

    test('withLabel style-only keeps Field rows', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      final field = const VsdxFieldRow(ix: 0, value: '42', type: 0);
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(
          VsdxShapeFactory.rectangle(
            id: id,
            pinX: 1,
            pinY: 1,
            width: 2,
            height: 1,
          ).copyWith(
            text: '42',
            fields: <VsdxFieldRow>[field],
            richText: VsdxRichText(runs: <VsdxTextRun>[
              VsdxTextRun(
                text: '42',
                fieldSpans: const <VsdxFieldSpan>[
                  VsdxFieldSpan(ix: 0, start: 0, length: 2),
                ],
              ),
            ]),
          ),
        ),
      );
      final before = doc.pages.first.findShapeById(id)!;
      final styled = withLabel(before, '42', bold: true, colorHex: '#00AA00');
      expect(styled.fields, hasLength(1));
      expect(styled.fields.first.ix, 0);
      expect(styled.richText.runs.first.fieldSpans, hasLength(1));
      expect(styled.richText.runs.first.charStyle.style.bold, isTrue);
      final rewritten = withLabel(before, 'Hello');
      expect(rewritten.fields, isEmpty);
      expect(rewritten.richText.runs.first.fieldSpans, isEmpty);
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

    test('locked shapes reject mutate ops', () {
      final doc = built();
      final target = doc.pages.single.shapes.first;
      final lockedDoc = doc.replacePage(
        0,
        doc.pages.single.updateShapeById(
          target.id,
          (s) => s.copyWith(locked: true),
        ),
      );
      final pinX = lockedDoc.pages.single.findShapeById(target.id)!.pinX;
      final r = applyOps(lockedDoc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'id': target.id,
          'fill': '#FF0000',
        },
        <String, dynamic>{
          'op': 'move_shape',
          'id': target.id,
          'x': 9.0,
          'y': 9.0,
        },
        <String, dynamic>{'op': 'delete_shape', 'id': target.id},
      ]);
      expect(r.log.any((l) => l.contains('locked')), isTrue);
      final after = r.document.pages.single.findShapeById(target.id)!;
      expect(after.pinX, closeTo(pinX, 1e-9));
      expect(after.fill.foreground?.value, isNot(0xFFFF0000));
    });

    test('applyOpsBytes round-trips through the writer', () {
      final original = DiagramSpec.parse(_spec).build();
      final out = applyOpsBytes(original, '''
        { "ops": [ { "op": "add_shape", "text": "Extra", "x": 1, "y": 1 } ] }''');
      final page = const DocumentParser().parse(out).pages.single;
      expect(page.shapes.any((s) => s.text == 'Extra'), isTrue);
    });

    test('rejects trailing-digit node labels as shape ids', () {
      final doc = built();
      final first = doc.pages.single.shapes.first;
      final originalText = first.text;
      final r = applyOps(doc, _ops('''
        { "ops": [ { "op": "set_text", "id": "db1", "text": "HACKED" } ] }'''));
      expect(r.log, isNotEmpty);
      expect(r.log.first, contains('invalid id'));
      expect(
        r.document.pages.single.findShapeById(first.id)!.text,
        originalText,
      );
    });

    test('logs when target shape id is missing', () {
      final doc = built();
      final r = applyOps(doc, _ops('''
        { "ops": [
          { "op": "set_text", "id": 99999, "text": "Nope" },
          { "op": "move_shape", "id": 99999, "x": 1, "y": 2 },
          { "op": "delete_shape", "id": 99999 }
        ] }'''));
      expect(r.log, hasLength(3));
      expect(r.log.every((l) => l.contains('not found')), isTrue);
    });

    test('resize_shape scales 1D Begin→End without glue undo', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      final line = VsdxShapeFactory.line(
        id: id,
        ax: 1,
        ay: 1,
        bx: 3,
        by: 1,
      );
      doc = doc.replacePage(0, doc.pages.first.addShape(line));
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'resize_shape',
          'id': id,
          'w': 4,
          'h': line.height,
        },
      ]);
      final resized = r.document.pages.first.findShapeById(id)!;
      expect(resized.beginX, closeTo(1, 1e-9));
      expect(resized.endX, closeTo(5, 1e-9));
      expect(resized.width, closeTo(4, 1e-9));
    });

    test('resize_shape preserves direction of right-to-left 1D', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      // End left of Begin → negative Width.
      final line = VsdxShapeFactory.line(
        id: id,
        ax: 5,
        ay: 2,
        bx: 3,
        by: 2,
      );
      expect(line.width, lessThan(0));
      doc = doc.replacePage(0, doc.pages.first.addShape(line));
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'resize_shape',
          'id': id,
          'w': 4,
          'h': 0,
        },
      ]);
      final resized = r.document.pages.first.findShapeById(id)!;
      expect(resized.beginX, closeTo(5, 1e-9));
      expect(resized.endX, closeTo(1, 1e-9)); // still leftward
      expect(resized.width, closeTo(-4, 1e-9));
    });

    test('set_text empty clears the label', () {
      final doc = built();
      final id = doc.pages.single.shapes.first.id;
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{'op': 'set_text', 'id': id, 'text': ''},
      ]);
      final s = r.document.pages.single.findShapeById(id)!;
      expect(s.text, isEmpty);
      expect(s.richText.isEmpty, isTrue);
    });

    test('set_text preserves existing bold and colour', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      final styled = VsdxShapeFactory.rectangle(
        id: id,
        pinX: 2,
        pinY: 2,
        width: 1.5,
        height: 0.8,
      ).copyWith(
        text: 'Old',
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: 'Old',
            charStyle: const VsdxCharStyle(
              fontSizeInches: 14 / 72.0,
              color: VsdxColor(0xFFCC0000),
              style: VsdxFontStyle.boldStyle,
            ),
          ),
        ]),
      );
      doc = doc.replacePage(0, doc.pages.first.addShape(styled));
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{'op': 'set_text', 'id': id, 'text': 'New'},
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      expect(after.text, 'New');
      final style = after.richText.runs.single.charStyle;
      expect(style.style.bold, isTrue);
      expect(style.color?.value, 0xFFCC0000);
      expect(style.fontSizeInches, closeTo(14 / 72.0, 1e-9));
    });

    test('set_text preserves theme text colour slot', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      final styled = VsdxShapeFactory.rectangle(
        id: id,
        pinX: 2,
        pinY: 2,
        width: 1.5,
        height: 0.8,
      ).copyWith(
        text: 'Old',
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: 'Old',
            charStyle: VsdxCharStyle(
              fontSizeInches: 12 / 72.0,
            ).withThemeColor(ThemeSlot.accent1),
          ),
        ]),
      );
      doc = doc.replacePage(0, doc.pages.first.addShape(styled));
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{'op': 'set_text', 'id': id, 'text': 'New'},
      ]);
      final style = r.document.pages.first.findShapeById(id)!.richText.runs.single.charStyle;
      expect(style.color, isNull);
      expect(style.themeColorIndex, ThemeSlot.accent1);
    });

    test('set_text textColor none clears solid and theme colour', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final solidId = doc.pages.first.nextFreeShapeId();
      final themeId = solidId + 1;
      doc = doc.replacePage(
        0,
        doc.pages.first
            .addShape(
              VsdxShapeFactory.rectangle(
                id: solidId,
                pinX: 2,
                pinY: 2,
                width: 1.5,
                height: 0.8,
              ).copyWith(
                text: 'Old',
                richText: const VsdxRichText(runs: [
                  VsdxTextRun(
                    text: 'Old',
                    charStyle: VsdxCharStyle(
                      fontSizeInches: 12 / 72.0,
                      color: VsdxColor(0xFFCC0000),
                    ),
                  ),
                ]),
              ),
            )
            .addShape(
              VsdxShapeFactory.rectangle(
                id: themeId,
                pinX: 4,
                pinY: 2,
                width: 1.5,
                height: 0.8,
              ).copyWith(
                text: 'Old',
                richText: VsdxRichText(runs: [
                  VsdxTextRun(
                    text: 'Old',
                    charStyle: VsdxCharStyle(
                      fontSizeInches: 12 / 72.0,
                    ).withThemeColor(ThemeSlot.accent1),
                  ),
                ]),
              ),
            ),
      );
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_text',
          'id': solidId,
          'text': 'New',
          'textColor': 'none',
        },
        <String, dynamic>{
          'op': 'set_text',
          'id': themeId,
          'text': 'New',
          'textColor': 'none',
        },
      ]);
      final solid = r.document.pages.first
          .findShapeById(solidId)!
          .richText
          .runs
          .single
          .charStyle;
      final theme = r.document.pages.first
          .findShapeById(themeId)!
          .richText
          .runs
          .single
          .charStyle;
      expect(solid.color, isNull);
      expect(solid.themeColorIndex, isNull);
      expect(theme.color, isNull);
      expect(theme.themeColorIndex, isNull);
    });

    test('set_style line none clears line gradient', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      final shaped = VsdxShapeFactory.rectangle(
        id: id,
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 1,
      ).copyWith(
        line: const VsdxLine(
          color: VsdxColor.black,
          weightInches: 0.02,
          gradient: VsdxGradient(
            stops: <VsdxGradientStop>[
              VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
              VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
            ],
          ),
        ),
      );
      doc = doc.replacePage(0, doc.pages.first.addShape(shaped));
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'line': 'none',
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      expect(after.line.hasLine, isFalse);
      expect(after.line.gradient, isNull);
    });

    test('resize_shape scales group children with the box', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final child = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 1,
        pinY: 0.5,
        width: 1,
        height: 0.5,
      );
      final group = VsdxShape(
        id: 1,
        name: 'Group.1',
        pinX: 3,
        pinY: 4,
        width: 2,
        height: 1,
        shapeKind: VsdxShapeKind.group,
        children: <VsdxShape>[child],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
      );
      doc = doc.replacePage(0, doc.pages.first.copyWith(shapes: <VsdxShape>[group]));
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'resize_shape',
          'id': 1,
          'w': 4,
          'h': 2,
        },
      ]);
      final afterChild = r.document.pages.first.findShapeById(2)!;
      expect(afterChild.width, closeTo(2, 1e-6));
      expect(afterChild.height, closeTo(1, 1e-6));
      expect(afterChild.pinX, closeTo(2, 1e-6));
      expect(afterChild.pinY, closeTo(1, 1e-6));
    });

    test('delete_shape clears stale EndTrigger on remaining connectors', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      var page = doc.pages.first;
      final a = VsdxShapeFactory.rectangle(
          id: 1, pinX: 2, pinY: 2, width: 1, height: 1);
      final b = VsdxShapeFactory.rectangle(
          id: 2, pinX: 5, pinY: 2, width: 1, height: 1);
      final conn = VsdxShapeFactory.line(id: 3, ax: 2, ay: 2, bx: 5, by: 2)
          .copyWith(formulas: <String, String>{
        'BegTrigger': '_XFTRIGGER(Sheet.1!EventXFMod)',
        'EndTrigger': '_XFTRIGGER(Sheet.2!EventXFMod)',
      });
      page = page.copyWith(
        shapes: <VsdxShape>[a, b, conn],
        connects: <VsdxConnect>[
          const VsdxConnect(
            fromSheetId: 3,
            fromCell: 'BeginX',
            fromPart: 9,
            toSheetId: 1,
            toCell: 'PinX',
            toPart: 3,
          ),
          const VsdxConnect(
            fromSheetId: 3,
            fromCell: 'EndX',
            fromPart: 12,
            toSheetId: 2,
            toCell: 'PinX',
            toPart: 3,
          ),
        ],
      );
      doc = doc.replacePage(0, page);
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{'op': 'delete_shape', 'id': 2},
      ]);
      final after = r.document.pages.first.findShapeById(3)!;
      expect(after.formulas.containsKey('EndTrigger'), isFalse);
      expect(after.formulas['BegTrigger'], contains('Sheet.1!'));
      expect(r.document.pages.first.connects, hasLength(1));
    });

    test('pruneConnectsReferencing clears EndTrigger for deleted targets', () {
      final a = VsdxShapeFactory.rectangle(
          id: 1, pinX: 2, pinY: 2, width: 1, height: 1);
      final b = VsdxShapeFactory.rectangle(
          id: 2, pinX: 5, pinY: 2, width: 1, height: 1);
      final conn = VsdxShapeFactory.line(id: 3, ax: 2, ay: 2, bx: 5, by: 2)
          .copyWith(formulas: <String, String>{
        'BegTrigger': '_XFTRIGGER(Sheet.1!EventXFMod)',
        'EndTrigger': '_XFTRIGGER(Sheet.2!EventXFMod)',
      });
      var page = VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 8,
        heightInches: 11,
        shapes: <VsdxShape>[a, b, conn],
        connects: const [
          VsdxConnect(
            fromSheetId: 3,
            fromCell: 'BeginX',
            fromPart: 9,
            toSheetId: 1,
            toCell: 'PinX',
            toPart: 3,
          ),
          VsdxConnect(
            fromSheetId: 3,
            fromCell: 'EndX',
            fromPart: 12,
            toSheetId: 2,
            toCell: 'PinX',
            toPart: 3,
          ),
        ],
      );
      page = page.pruneConnectsReferencing({2});
      expect(page.connects, hasLength(1));
      final after = page.findShapeById(3)!;
      expect(after.formulas.containsKey('EndTrigger'), isFalse);
      expect(after.formulas['BegTrigger'], contains('Sheet.1!'));
    });

    test('syncGlueTriggers rewrites BegTrigger after Connect remap', () {
      final a = VsdxShapeFactory.rectangle(
          id: 1, pinX: 2, pinY: 2, width: 1, height: 1);
      final b = VsdxShapeFactory.rectangle(
          id: 2, pinX: 5, pinY: 2, width: 1, height: 1);
      final conn = VsdxShapeFactory.line(id: 3, ax: 2, ay: 2, bx: 5, by: 2)
          .copyWith(formulas: <String, String>{
        'BegTrigger': '_XFTRIGGER(Sheet.1!EventXFMod)',
      });
      var page = VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 8,
        heightInches: 11,
        shapes: <VsdxShape>[a, b, conn],
        connects: const [
          VsdxConnect(
            fromSheetId: 3,
            fromCell: 'BeginX',
            fromPart: 9,
            toSheetId: 2,
            toCell: 'PinX',
            toPart: 3,
          ),
        ],
      );
      page = page.syncGlueTriggers(connectorIds: {3});
      expect(
        page.findShapeById(3)!.formulas['BegTrigger'],
        contains('Sheet.2!'),
      );
    });

    test('syncGlueTriggers clears orphan BeginX PAR when triggers already null',
        () {
      final conn = VsdxShapeFactory.line(id: 3, ax: 1, ay: 1, bx: 3, by: 1)
          .copyWith(formulas: <String, String>{
        'BeginX': 'PAR(PNT(Sheet.1!Connections.X1,Sheet.1!Connections.Y1))',
        'Width': 'EndX-BeginX',
      });
      var page = VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 8,
        heightInches: 11,
        shapes: <VsdxShape>[conn],
      );
      page = page.syncGlueTriggers(connectorIds: {3});
      expect(page.findShapeById(3)!.formulas.containsKey('BeginX'), isFalse);
      expect(page.findShapeById(3)!.formulas['Width'], 'EndX-BeginX');
    });

    test('move_shape recalculates dependent Sheet.n! LocPin formulas', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final a = VsdxShapeFactory.rectangle(
        id: 10,
        pinX: 3,
        pinY: 1,
        width: 2,
        height: 1,
      );
      final b = VsdxShapeFactory.rectangle(
        id: 20,
        pinX: 1,
        pinY: 1,
        width: 2,
        height: 2,
      ).copyWith(
        locPinXInches: 1.5,
        formulas: const <String, String>{
          'LocPinX': 'Sheet.10!PinX*0.5',
        },
      );
      doc = doc.replacePage(
        0,
        doc.pages.first.copyWith(shapes: <VsdxShape>[a, b]),
      );
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{'op': 'move_shape', 'id': 10, 'x': 5, 'y': 1},
      ]);
      expect(
        r.document.pages.first.findShapeById(20)!.locPinXInches,
        closeTo(2.5, 1e-6),
      );
    });

    test('move_shape translates Begin/End with the pin', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      final line = VsdxShapeFactory.line(
        id: id,
        ax: 1,
        ay: 1,
        bx: 3,
        by: 2,
      );
      doc = doc.replacePage(0, doc.pages.first.addShape(line));
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'move_shape',
          'id': id,
          'x': line.pinX + 2,
          'y': line.pinY + 1,
        },
      ]);
      final moved = r.document.pages.first.findShapeById(id)!;
      expect(moved.pinX, closeTo(line.pinX + 2, 1e-9));
      expect(moved.pinY, closeTo(line.pinY + 1, 1e-9));
      expect(moved.beginX, closeTo(3, 1e-9));
      expect(moved.beginY, closeTo(2, 1e-9));
      expect(moved.endX, closeTo(5, 1e-9));
      expect(moved.endY, closeTo(3, 1e-9));
    });

    test('move_shape uses page pins for nested group children', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      var page = doc.pages.first;
      final child = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 1,
        pinY: 0.5,
        width: 1,
        height: 0.5,
      );
      final group = VsdxShape(
        id: 1,
        name: 'Group.1',
        pinX: 3,
        pinY: 4,
        width: 3,
        height: 2,
        children: <VsdxShape>[child],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
      );
      doc = doc.replacePage(0, page.copyWith(shapes: <VsdxShape>[group]));
      page = doc.pages.first;
      final beforePage = page.shapePinPage(2);
      // listShapes-style target: move page pin by (+1, +0.5).
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'move_shape',
          'id': 2,
          'x': beforePage.x + 1,
          'y': beforePage.y + 0.5,
        },
      ]);
      final afterPage = r.document.pages.first.shapePinPage(2);
      expect(afterPage.x, closeTo(beforePage.x + 1, 1e-6));
      expect(afterPage.y, closeTo(beforePage.y + 0.5, 1e-6));
      // Parent-local pin should have moved, not jumped to absolute page coords.
      final local = r.document.pages.first.findShapeById(2)!;
      expect(local.pinX, closeTo(child.pinX + 1, 1e-6));
      expect(local.pinY, closeTo(child.pinY + 0.5, 1e-6));
    });

    test('move_shape on group re-routes connectors glued to children', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final childA = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 0.75,
        pinY: 0.5,
        width: 1,
        height: 0.6,
      );
      final childB = VsdxShapeFactory.rectangle(
        id: 3,
        pinX: 2.25,
        pinY: 0.5,
        width: 1,
        height: 0.6,
      );
      final group = VsdxShape(
        id: 1,
        name: 'Group.1',
        pinX: 3,
        pinY: 4,
        width: 3.5,
        height: 1.5,
        children: <VsdxShape>[childA, childB],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
      );
      final outside = VsdxShapeFactory.rectangle(
        id: 4,
        pinX: 7,
        pinY: 4,
        width: 1,
        height: 0.6,
      );
      final conn = VsdxShapeFactory.line(id: 5, ax: 3, ay: 4, bx: 7, by: 4);
      var page = doc.pages.first.copyWith(
        shapes: <VsdxShape>[group, outside, conn],
        connects: const [
          VsdxConnect(
              fromSheetId: 5, fromCell: 'BeginX', toSheetId: 3, toCell: 'PinX'),
          VsdxConnect(
              fromSheetId: 5, fromCell: 'EndX', toSheetId: 4, toCell: 'PinX'),
        ],
      ).rerouteConnectors();
      doc = doc.replacePage(0, page);
      final beforeBegin = page.findShapeById(5)!.beginX!;
      final groupPin = page.shapePinPage(1);
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'move_shape',
          'id': 1,
          'x': groupPin.x + 1.5,
          'y': groupPin.y,
        },
      ]);
      final after = r.document.pages.first.findShapeById(5)!;
      expect(after.beginX, closeTo(beforeBegin + 1.5, 0.35),
          reason: 'begin should follow the glued group child');
    });

    test('move_shape does not re-route unrelated glued connectors', () {
        final bytes = File(
          File('test/fixtures/test4_connectors.vsdx').existsSync()
              ? 'test/fixtures/test4_connectors.vsdx'
              : 'packages/vsdx/test/fixtures/test4_connectors.vsdx',
        ).readAsBytesSync();
      final doc = const DocumentParser().parse(bytes);
      final page = doc.pages.first;
      String sig(VsdxShape s) {
        final g = s.geometries.isNotEmpty ? s.geometries.first : null;
        return '${s.beginX},${s.beginY}->${s.endX},${s.endY}|${g?.commands.length}';
      }

      final before = <int, String>{
        for (final s in page.shapes)
          if (s.is1D) s.id: sig(s),
      };
      final connected = <int>{
        for (final c in page.connects) c.fromSheetId,
        for (final c in page.connects) c.toSheetId,
      };
      int? victim;
      for (final s in page.shapes) {
        if (!s.is1D && !connected.contains(s.id) && s.children.isEmpty) {
          victim = s.id;
          break;
        }
      }
      if (victim == null) return;
      final pin = page.shapePinPage(victim);
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'move_shape',
          'id': victim,
          'x': pin.x + 0.5,
          'y': pin.y,
        },
      ]);
      final afterPage = r.document.pages.first;
      final drifted = <int>[
        for (final e in before.entries)
          if (afterPage.findShapeById(e.key) case final VsdxShape s)
            if (sig(s) != e.value) e.key,
      ];
      expect(drifted, isEmpty,
          reason: 'unrelated move changed connectors $drifted');
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

    test('validate flags duplicate ids nested under a group', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      var page = doc.pages.first;
      final a = VsdxShapeFactory.rectangle(
          id: 1, pinX: 2, pinY: 2, width: 1, height: 1);
      final b = VsdxShapeFactory.rectangle(
          id: 2, pinX: 4, pinY: 2, width: 1, height: 1);
      // Illegally reuse id 2 as a nested sibling under a group shell.
      final group = VsdxShape(
        id: 10,
        name: 'Group.10',
        pinX: 3,
        pinY: 2,
        width: 3,
        height: 1.2,
        children: <VsdxShape>[a, b, b.copyWith(pinX: 5)],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
      );
      doc = doc.replacePage(0, page.copyWith(shapes: <VsdxShape>[group]));
      final issues = validateDocument(doc);
      expect(
        issues.any((i) => i.message.contains('duplicate shape id 2')),
        isTrue,
      );
    });

    test('validate flags missing backgroundPageId', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final page = doc.pages.first;
      doc = doc.replacePage(
        0,
        page.copyWith(backgroundPageId: 999),
      );
      final issues = validateDocument(doc);
      expect(
        issues.any((i) => i.message.contains('backgroundPageId 999')),
        isTrue,
      );
    });

    test('removePageAt clears dangling backgroundPageId', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final fg = doc.pages.first;
      final bgId = doc.nextPageId();
      doc = doc.insertPage(
        1,
        VsdxPage(
          id: bgId,
          name: 'Background-1',
          widthInches: fg.widthInches,
          heightInches: fg.heightInches,
          shapes: const <VsdxShape>[],
          isBackgroundPage: true,
        ),
      );
      doc = doc.replacePage(0, fg.copyWith(backgroundPageId: bgId));
      expect(doc.pages.first.backgroundPageId, bgId);
      doc = doc.removePageAt(1);
      expect(doc.pages, hasLength(1));
      expect(doc.pages.first.backgroundPageId, isNull);
      expect(validateDocument(doc).where((i) => i.severity == 'error'), isEmpty);
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
