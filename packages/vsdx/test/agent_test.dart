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
