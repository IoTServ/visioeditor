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

    test('page ops switch batch context and survive a writer round-trip', () {
      final original = const VsdxWriter().emptyDocument();
      final doc = const DocumentParser().parse(original);
      final result = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'add_page',
          'name': 'Canvas',
          'width': 12,
          'height': 7,
          'background': '#112233',
        },
        <String, dynamic>{
          'op': 'add_shape',
          'stencil': 'process',
          'text': 'On the new page',
        },
        <String, dynamic>{'op': 'rename_page', 'name': 'Page-1'},
        <String, dynamic>{'op': 'duplicate_page', 'name': 'Review'},
        <String, dynamic>{
          'op': 'set_page',
          'width': 14,
          'height': 8,
          'landscape': true,
          'background': 'none',
        },
      ]);

      expect(result.document.pages, hasLength(3));
      expect(result.createdPageIds, hasLength(2));
      expect(result.createdIds, hasLength(1));
      expect(result.pageIndex, 2);
      expect(result.activatePage, isTrue);
      expect(result.document.pages[0].shapes, isEmpty);
      expect(result.document.pages[1].name, 'Page-1 2');
      expect(result.document.pages[1].backgroundColor?.value, 0xFF112233);
      expect(
        result.document.pages[1].shapes.single.text,
        'On the new page',
      );
      expect(result.document.pages[2].name, 'Review');
      expect(result.document.pages[2].widthInches, 14);
      expect(result.document.pages[2].heightInches, 8);
      expect(result.document.pages[2].backgroundColor, isNull);
      expect(
        result.document.pages.map((page) => page.id).toSet(),
        hasLength(3),
      );

      final reopened = const DocumentParser().parse(
        const VsdxWriter().write(
          originalBytes: original,
          edited: result.document,
        ),
      );
      expect(reopened.pages, hasLength(3));
      expect(reopened.pages[1].name, 'Page-1 2');
      expect(reopened.pages[2].shapes.single.text, 'On the new page');
      expect(validateDocument(reopened).where((i) => i.severity == 'error'),
          isEmpty);
    });

    test('page move/delete preserve active id and clear background links', () {
      final original = const VsdxWriter().emptyDocument();
      final doc = const DocumentParser().parse(original);
      final backgroundId = doc.nextPageId();
      final result = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'add_page',
          'name': 'Background',
          'isBackground': true,
        },
        <String, dynamic>{'op': 'add_page', 'name': 'Main'},
        <String, dynamic>{
          'op': 'set_page',
          'backgroundPageId': backgroundId,
        },
        <String, dynamic>{'op': 'move_page', 'from': 2, 'to': 0},
        <String, dynamic>{'op': 'delete_page', 'index': 2},
      ]);

      expect(
          result.document.pages.map((p) => p.name), <String>['Main', 'Page-1']);
      expect(result.pageIndex, 0);
      expect(result.document.pages.first.backgroundPageId, isNull);
      expect(result.log, isEmpty);
    });

    test('layer ops mirror draw.io and survive a writer round-trip', () {
      final original = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(original);
      doc = doc.replacePage(
        0,
        doc.pages.first.copyWith(
          shapes: <VsdxShape>[
            VsdxShapeFactory.rectangle(
              id: 1,
              pinX: 2,
              pinY: 2,
              width: 1,
              height: 1,
            ),
            VsdxShapeFactory.rectangle(
              id: 2,
              pinX: 4,
              pinY: 2,
              width: 1,
              height: 1,
            ),
          ],
        ),
      );

      final result = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'add_layer',
          'name': 'Architecture',
          'ids': <int>[1],
          'active': true,
          'color': '#336699',
          'colorTransparency': 0.25,
        },
        <String, dynamic>{
          'op': 'add_shape',
          'text': 'Active layer shape',
        },
        <String, dynamic>{
          'op': 'assign_layer',
          'ids': <int>[2],
          'layerId': 0,
          'mode': 'add',
        },
        <String, dynamic>{
          'op': 'set_layer',
          'id': 0,
          'name': 'Infrastructure',
          'visible': false,
          'print': false,
          'locked': true,
          'snap': false,
        },
      ]);

      expect(result.log, isEmpty);
      expect(result.createdLayerIds, <int>[0]);
      expect(result.createdIds, hasLength(1));
      final page = result.document.pages.single;
      final layer = page.layers.single;
      expect(layer.name, 'Infrastructure');
      expect(layer.active, isTrue);
      expect(layer.visible, isFalse);
      expect(layer.print, isFalse);
      expect(layer.locked, isTrue);
      expect(layer.snap, isFalse);
      expect(layer.color?.value, 0xFF336699);
      expect(layer.colorTrans, closeTo(0.25, 1e-9));
      expect(page.findShapeById(1)!.layerMemberIds, <int>[0]);
      expect(page.findShapeById(2)!.layerMemberIds, <int>[0]);
      expect(
        page.findShapeById(result.createdIds.single)!.layerMemberIds,
        <int>[0],
      );

      final listed = listLayers(result.document);
      expect(listed.single['shapeIds'], containsAll(<int>[1, 2]));
      expect(listed.single['shapes'], 3);

      final reopened = const DocumentParser().parse(
        const VsdxWriter().write(
          originalBytes: original,
          edited: result.document,
        ),
      );
      expect(reopened.pages.single.layers.single.name, 'Infrastructure');
      expect(reopened.pages.single.layers.single.visible, isFalse);
      expect(reopened.pages.single.findShapeById(1)!.layerMemberIds, <int>[0]);
      expect(
        validateDocument(reopened).where((i) => i.severity == 'error'),
        isEmpty,
      );
    });

    test('delete_layer removes nested shape membership recursively', () {
      final original = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(original);
      final child = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 1,
        pinY: 0.5,
        width: 1,
        height: 0.5,
      ).copyWith(layerMemberIds: const <int>[3]);
      final group = VsdxShape(
        id: 1,
        name: 'Group.1',
        pinX: 3,
        pinY: 4,
        width: 2,
        height: 1,
        shapeKind: VsdxShapeKind.group,
        children: <VsdxShape>[child],
        layerMemberIds: const <int>[3],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
      );
      doc = doc.replacePage(
        0,
        doc.pages.first.copyWith(
          layers: const <VsdxLayer>[VsdxLayer(id: 3, name: 'Nested')],
          shapes: <VsdxShape>[group],
        ),
      );

      final result = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{'op': 'delete_layer', 'layerId': 3},
      ]);

      expect(result.log, isEmpty);
      expect(result.document.pages.single.layers, isEmpty);
      expect(
        result.document.pages.single.findShapeById(1)!.layerMemberIds,
        isEmpty,
      );
      expect(
        result.document.pages.single.findShapeById(2)!.layerMemberIds,
        isEmpty,
      );
    });

    test('shape data and hyperlinks mirror draw.io and round-trip', () {
      final original = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(original);
      doc = doc.replacePage(
        0,
        doc.pages.first.copyWith(
          shapes: <VsdxShape>[
            VsdxShapeFactory.rectangle(
              id: 1,
              pinX: 2,
              pinY: 2,
              width: 2,
              height: 1,
            ),
          ],
        ),
      );

      final result = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_data',
          'id': 1,
          'properties': <dynamic>[
            <String, dynamic>{
              'name': 'Owner',
              'label': 'Service owner',
              'value': 'Platform',
              'prompt': 'Owning team',
            },
            <String, dynamic>{
              'name': 'Cost',
              'value': 42.5,
              'type': 2,
              'format': '#,##0.00',
              'sortKey': '02',
            },
            <String, dynamic>{
              'name': 'Owner',
              'value': 'duplicate',
            },
          ],
        },
        <String, dynamic>{
          'op': 'set_links',
          'id': 1,
          'links': <dynamic>[
            <String, dynamic>{
              'id': 5,
              'description': 'Service docs',
              'address': 'https://example.com/docs',
              'newWindow': true,
              'default': true,
            },
            <String, dynamic>{
              'id': 5,
              'description': 'Overview page',
              'subAddress': '#Page-1',
              'default': true,
            },
          ],
        },
      ]);

      expect(result.log, <String>[
        'set_data: duplicate property name "Owner" skipped',
        'set_links: duplicate/invalid id 5 reassigned to 0',
      ]);
      final shape = result.document.pages.single.findShapeById(1)!;
      expect(shape.userProperties, hasLength(2));
      expect(shape.userProperties[0].label, 'Service owner');
      expect(shape.userProperties[1].value, '42.5');
      expect(shape.userProperties[1].type, 2);
      expect(shape.hyperlinks.map((link) => link.id), <int>[5, 0]);
      expect(shape.hyperlinks.first.isDefault, isTrue);
      expect(shape.hyperlinks.last.isDefault, isFalse);
      expect(
          shape.primaryHyperlink?.effectiveTarget, 'https://example.com/docs');

      final listed = listShapes(result.document).single;
      expect((listed['data'] as List).first['name'], 'Owner');
      expect((listed['links'] as List).first['target'],
          'https://example.com/docs');
      expect((listed['links'] as List).last['target'], '#Page-1');

      final reopened = const DocumentParser().parse(
        const VsdxWriter().write(
          originalBytes: original,
          edited: result.document,
        ),
      );
      final reopenedShape = reopened.pages.single.findShapeById(1)!;
      expect(reopenedShape.userProperties, shape.userProperties);
      expect(reopenedShape.hyperlinks, shape.hyperlinks);

      final cleared = applyOps(reopened, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_shape_data',
          'id': 1,
          'data': <dynamic>[],
        },
        <String, dynamic>{
          'op': 'set_shape_links',
          'id': 1,
          'links': <dynamic>[],
        },
      ]);
      expect(cleared.document.pages.single.findShapeById(1)!.userProperties,
          isEmpty);
      expect(
          cleared.document.pages.single.findShapeById(1)!.hyperlinks, isEmpty);
    });

    test('connector route, waypoints, and endpoints mirror draw.io', () {
      final original = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(original);
      var page = doc.pages.first;
      final a = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 1,
      );
      final b = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 7,
        pinY: 3,
        width: 2,
        height: 1,
      );
      page = page.copyWith(shapes: <VsdxShape>[a, b]);
      final link = buildConnector(id: 3, page: page, a: a, b: b);
      page = page
          .addShape(link.connector)
          .copyWith(connects: link.connects)
          .rerouteConnectors();
      doc = doc.replacePage(0, page);

      final result = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_connector',
          'id': 3,
          'route': 'orthogonal',
          'rounded': true,
          'waypoints': <dynamic>[
            <String, dynamic>{'x': 3, 'y': 4},
            <dynamic>[6, 4],
          ],
        },
        <String, dynamic>{
          'op': 'reconnect_connector',
          'id': 3,
          'end': 'end',
          'target': 2,
          'connectionPoint': 1,
        },
        <String, dynamic>{
          'op': 'reconnect_connector',
          'id': 3,
          'end': 'begin',
          'x': 1,
          'y': 1,
        },
      ]);

      expect(result.log, isEmpty);
      final editedPage = result.document.pages.single;
      final connector = editedPage.findShapeById(3)!;
      expect(connector.straightRoute, isFalse);
      expect(connector.curved, isFalse);
      expect(connector.rounded, isTrue);
      expect(connector.waypoints, hasLength(2));
      expect(connector.waypoints[0].x, closeTo(3, 1e-6));
      expect(connector.waypoints[0].y, closeTo(4, 1e-6));
      expect(connector.waypoints[1].x, closeTo(6, 1e-6));
      expect(connector.waypoints[1].y, closeTo(4, 1e-6));
      expect(connector.beginX, closeTo(1, 1e-6));
      expect(connector.beginY, closeTo(1, 1e-6));
      expect(
        editedPage.connects.where((connect) => connect.isBegin),
        isEmpty,
      );
      final endConnect =
          editedPage.connects.singleWhere((connect) => connect.isEnd);
      expect(endConnect.toSheetId, 2);
      expect(endConnect.toPart, 101);
      expect(editedPage.findShapeById(2)!.connectionPoints, isNotEmpty);

      final listed =
          listShapes(result.document).singleWhere((entry) => entry['id'] == 3);
      expect(listed['route'], 'orthogonal');
      expect(listed['rounded'], isTrue);
      expect(listed['waypoints'], hasLength(2));
      expect((listed['begin'] as Map).containsKey('targetId'), isFalse);
      expect((listed['end'] as Map)['targetId'], 2);
      expect((listed['end'] as Map)['connectionPoint'], 1);

      final reopened = const DocumentParser().parse(
        const VsdxWriter().write(
          originalBytes: original,
          edited: result.document,
        ),
      );
      final persisted = reopened.pages.single.findShapeById(3)!;
      expect(persisted.rounded, isTrue);
      expect(persisted.waypoints, hasLength(2));
      expect(
        reopened.pages.single.connects
            .singleWhere((connect) => connect.isEnd)
            .toPart,
        101,
      );

      final cleared = applyOps(reopened, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_connector',
          'id': 3,
          'route': 'straight',
          'waypoints': <dynamic>[],
        },
      ]);
      final straight = cleared.document.pages.single.findShapeById(3)!;
      expect(straight.straightRoute, isTrue);
      expect(straight.waypoints, isEmpty);
    });

    test('connection points mirror draw.io editing and preserve fixed glue',
        () {
      final original = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(original);
      var page = doc.pages.first;
      final a = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 4,
        pinY: 3,
        width: 2,
        height: 2,
      );
      final b = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 8,
        pinY: 3,
        width: 2,
        height: 1,
      );
      page = page.copyWith(shapes: <VsdxShape>[a, b]);
      final link = buildConnector(id: 3, page: page, a: a, b: b);
      page = page
          .addShape(link.connector)
          .copyWith(connects: link.connects)
          .rerouteConnectors();
      doc = doc.replacePage(0, page);

      final result = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_connection_points',
          'id': 1,
          'coordinateSpace': 'page',
          'points': <dynamic>[
            <String, dynamic>{
              'x': 4,
              'y': 4,
              'dirX': 0,
              'dirY': 1,
              'type': 2,
              'prompt': 'North',
            },
            <String, dynamic>{'x': 5, 'y': 3},
          ],
        },
        <String, dynamic>{
          'op': 'reconnect_connector',
          'id': 3,
          'end': 'begin',
          'target': 1,
          'connectionPoint': 1,
        },
      ]);

      expect(result.log, isEmpty);
      final editedPage = result.document.pages.single;
      final shape = editedPage.findShapeById(1)!;
      expect(shape.connectionPoints, hasLength(2));
      expect(shape.connectionPoints[0].x, closeTo(1, 1e-6));
      expect(shape.connectionPoints[0].y, closeTo(2, 1e-6));
      expect(shape.connectionPoints[0].type, 2);
      expect(shape.connectionPoints[0].prompt, 'North');
      expect(shape.connectionPoints[1].x, closeTo(2, 1e-6));
      expect(shape.connectionPoints[1].y, closeTo(1, 1e-6));
      final beginConnect = editedPage.connects.singleWhere(
          (connect) => connect.fromSheetId == 3 && connect.isBegin);
      expect(beginConnect.toPart, 101);

      final listed =
          listShapes(result.document).singleWhere((entry) => entry['id'] == 1);
      final listedPoints = listed['connectionPoints'] as List;
      expect(listedPoints, hasLength(2));
      expect(listedPoints.first['index'], 0);
      expect(listedPoints.first['x'], 1);
      expect(listedPoints.first['pageX'], 4);
      expect(listedPoints.first['pageY'], 4);
      expect(listedPoints.first['prompt'], 'North');

      final reopened = const DocumentParser().parse(
        const VsdxWriter().write(
          originalBytes: original,
          edited: result.document,
        ),
      );
      expect(reopened.pages.single.findShapeById(1)!.connectionPoints,
          shape.connectionPoints);
      expect(
        reopened.pages.single.connects
            .singleWhere(
              (connect) => connect.fromSheetId == 3 && connect.isBegin,
            )
            .toPart,
        101,
      );

      final shortened = applyOps(reopened, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_connection_points',
          'id': 1,
          'points': <dynamic>[
            <String, dynamic>{'x': 1, 'y': 2},
          ],
        },
      ]);
      final remapped = shortened.document.pages.single.connects.singleWhere(
        (connect) => connect.fromSheetId == 3 && connect.isBegin,
      );
      expect(remapped.toPart, 3);
      expect(remapped.toCell, 'PinX');

      final cleared = applyOps(shortened.document, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_connection_points',
          'id': 1,
          'points': <dynamic>[],
        },
      ]);
      expect(
        cleared.document.pages.single.findShapeById(1)!.connectionPoints,
        isEmpty,
      );
    });

    test('rejected and empty op batches preserve document identity', () {
      final doc = built();
      final target = doc.pages.single.shapes.firstWhere((s) => !s.is1D);

      final empty = applyOps(doc, const <Map<String, dynamic>>[]);
      expect(empty.document, same(doc));

      final invalid = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'move_shape',
          'id': target.id,
          'x': 'NaN',
          'y': target.pinY,
        },
        <String, dynamic>{'op': 'does_not_exist'},
        <String, dynamic>{
          'op': 'add_shape',
          'w': -1,
          'h': 1,
        },
        <String, dynamic>{
          'op': 'delete_shape',
          'id': double.nan,
        },
        <String, dynamic>{'op': 'delete_page'},
        <String, dynamic>{
          'op': 'set_page',
          'backgroundPageId': 999999,
        },
        <String, dynamic>{'op': 'set_layer', 'layerId': 999999},
        <String, dynamic>{'op': 'delete_layer', 'layerId': 999999},
        <String, dynamic>{
          'op': 'assign_layer',
          'ids': <int>[target.id],
          'layerId': 999999,
        },
        <String, dynamic>{'op': 'set_data', 'id': target.id},
        <String, dynamic>{'op': 'set_links', 'id': target.id},
        <String, dynamic>{'op': 'set_connector', 'id': target.id},
        <String, dynamic>{
          'op': 'reconnect_connector',
          'id': target.id,
          'end': 'end',
        },
        <String, dynamic>{
          'op': 'set_connection_points',
          'id': target.id,
        },
        <String, dynamic>{
          'op': 'reparent_shapes',
          'ids': <int>[target.id],
        },
        <String, dynamic>{
          'op': 'set_collapsed',
          'id': target.id,
        },
      ]);
      expect(invalid.document, same(doc));
      expect(invalid.log, hasLength(16));
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
        r.document.pages.first
            .findShapeById(id)!
            .geometries
            .every((g) => g.noFill),
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
      final target =
          doc.pages.single.shapes.firstWhere((s) => s.text == 'Do work');
      final r = applyOps(doc, _ops('''
        { "ops": [
          { "op": "set_style", "ids": ["shape:${target.id}"], "fill": "#F8CECC", "glass": true },
          { "op": "set_text", "id": ${target.id}, "text": "Renamed" }
        ] }'''));
      final s =
          r.document.pages.single.shapes.firstWhere((s) => s.id == target.id);
      expect(s.text, 'Renamed');
      expect(s.fill.foreground?.value, 0xFFF8CECC);
      expect(s.glassEffect, isTrue);
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
          'dashPattern': <double>[8, 4, 2, 4],
          'fixedDash': true,
          'flowAnimation': true,
          'flowDurationMs': 900,
          'flowTiming': 'ease-in-out',
          'flowDirection': 'alternate-reverse',
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      expect(after.line.color?.value, 0xFFFF0000);
      expect(after.line.beginArrow, 1);
      expect(after.line.endArrow, 4);
      expect(after.line.beginArrowSizeInches, closeTo(0.15, 1e-9));
      expect(after.line.endArrowSizeInches, closeTo(0.2, 1e-9));
      expect(after.line.weightInches, closeTo(0.02, 1e-9));
      expect(after.line.customDashPattern, <double>[8, 4, 2, 4]);
      expect(after.line.fixedDash, isTrue);
      expect(after.flowAnimation, isTrue);
      expect(after.flowAnimationDurationMs, 900);
      expect(after.flowAnimationTiming, VsdxFlowAnimationTiming.easeInOut);
      expect(
        after.flowAnimationDirection,
        VsdxFlowAnimationDirection.alternateReverse,
      );
      expect(
        after.userCells.any(
          (cell) =>
              cell.name == VsdxShape.userDashPattern &&
              cell.value == '8 4 2 4',
        ),
        isTrue,
      );
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
          'shadowPattern': 2,
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
      expect(after.shadow.pattern, 2);
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
      expect(cleared.glow.sizeInches, closeTo(0.12, 1e-9));
      expect(cleared.glow.color?.value, 0xFF00AADD);
      expect(cleared.shadow.enabled, isFalse);
      expect(cleared.shadow.pattern, 2);
      expect(cleared.shadow.color?.value, 0xFF333333);
      expect(cleared.shadow.offsetXInches, closeTo(0.1, 1e-9));
      // Re-enable restores companions and prior glow size.
      final on = applyOps(off.document, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'glow': true,
          'shadow': true,
        },
      ]);
      final restored = on.document.pages.first.findShapeById(id)!;
      expect(restored.glow.enabled, isTrue);
      expect(restored.glow.sizeInches, closeTo(0.12, 1e-9));
      expect(restored.glow.color?.value, 0xFF00AADD);
      expect(restored.shadow.enabled, isTrue);
      expect(restored.shadow.pattern, 2);
      expect(restored.shadow.color?.value, 0xFF333333);
    });

    test('set_style glow:true from disabled uses default size', () {
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
          'reflection': true,
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      expect(after.glow.enabled, isTrue);
      expect(after.glow.sizeInches, closeTo(0.05, 1e-9));
      expect(after.reflection.enabled, isTrue);
      expect(after.reflection.sizeInches, closeTo(0.3, 1e-9));
    });

    test('set_style angle and layerMember', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.copyWith(
          layers: const [
            VsdxLayer(id: 0, name: 'Default'),
            VsdxLayer(id: 1, name: 'Extra'),
          ],
        ).addShape(
          VsdxShapeFactory.rectangle(
            id: id,
            pinX: 1,
            pinY: 1,
            width: 2,
            height: 1,
          ).copyWith(formulas: const <String, String>{'Angle': 'Inh'}),
        ),
      );
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'angle': 90, // degrees (not radians)
          'layerMember': '0;1',
          'themeIndex': 2,
          'textAngle': 45,
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      expect(after.angleRad, closeTo(3.141592653589793 / 2, 1e-9));
      expect(after.formulas, isNot(contains('Angle')));
      expect(after.layerMemberIds, [0, 1]);
      expect(after.themeIndex, 2);
      expect(
        after.richText.textBlock.angleRad,
        closeTo(3.141592653589793 / 4, 1e-9),
      );
      final cleared = applyOps(r.document, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'layers': <int>[],
        },
      ]);
      expect(
        cleared.document.pages.first.findShapeById(id)!.layerMemberIds,
        isEmpty,
      );
    });

    test('set_style rotation reroutes glued connectors like the canvas', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      var page = doc.pages.first;
      final a = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 3,
        pinY: 3,
        width: 4,
        height: 1,
      );
      final b = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 8,
        pinY: 3,
        width: 1,
        height: 1,
      );
      page = page.copyWith(shapes: <VsdxShape>[a, b]);
      final link = buildConnector(id: 3, page: page, a: a, b: b);
      page = page
          .addShape(link.connector)
          .copyWith(connects: link.connects)
          .rerouteConnectors();
      doc = doc.replacePage(0, page);
      final before = page.findShapeById(3)!.beginX!;

      final result = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'id': 1,
          'angle': 90,
        },
      ]);
      final after = result.document.pages.first.findShapeById(3)!.beginX!;

      // A 4×1 box rotated 90° has a different right-hand perimeter. Keeping
      // the old BeginX would leave the connector visibly floating inside it.
      expect((after - before).abs(), greaterThan(0.5));

      final saved = const VsdxWriter().write(
        originalBytes: blank,
        edited: result.document,
      );
      final reopened = const DocumentParser().parse(saved).pages.first;
      expect(
        reopened.findShapeById(1)!.angleRad,
        closeTo(3.141592653589793 / 2, 1e-9),
      );
      expect(reopened.findShapeById(3)!.beginX, closeTo(after, 1e-6));
    });

    test('set_style connector dynamics on 1-D', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(
          VsdxShapeFactory.line(
            id: id,
            ax: 1,
            ay: 1,
            bx: 3,
            by: 2,
          ),
        ),
      );
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'glueType': 3,
          'conFixedCode': 1,
          'shapeRouteStyle': 16,
          'conLineJumpDirX': 1,
          'shapePlaceFlip': 2,
          'noLiveDynamics': true,
        },
      ]);
      final props = r.document.pages.first.findShapeById(id)!.connectorProps!;
      expect(props.glueType, 3);
      expect(props.conFixedCode, 1);
      expect(props.shapeRouteStyle, 16);
      expect(props.conLineJumpDirX, 1);
      expect(props.shapePlaceFlip, 2);
      expect(props.noLiveDynamics, isTrue);
    });

    test('set_style noAlignBox and selectMode', () {
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
          'noAlignBox': true,
          'shapeSplittable': true,
          'selectMode': 1,
          'isTextEditTarget': true,
          'dontMoveChildren': true,
          'eventDblClick': 'OPENTEXTWIN()',
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      expect(after.noAlignBox, isTrue);
      expect(after.shapeSplittable, isTrue);
      expect(after.selectMode, 1);
      expect(after.isTextEditTarget, isTrue);
      expect(after.dontMoveChildren, isTrue);
      expect(after.eventDblClick, 'OPENTEXTWIN()');
    });

    test('set_style fillTheme and lineTheme', () {
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
          'fillTheme': 3,
          'lineTheme': 4,
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      expect(after.fill.themeForegroundIndex, 3);
      expect(after.fill.foreground, isNull);
      expect(after.line.themeColorIndex, 4);
      expect(after.line.color, isNull);
    });

    test('set_style flipX/Y and locked unlock', () {
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
          ).copyWith(locked: true),
        ),
      );
      final blocked = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'fill': '#FF0000',
        },
      ]);
      expect(blocked.log.any((m) => m.contains('locked')), isTrue);
      expect(
        blocked.document.pages.first.findShapeById(id)!.fill.foreground?.value,
        isNot(0xFFFF0000),
      );

      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'locked': false,
          'flipX': true,
          'flipY': true,
          'fill': '#00AA00',
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      expect(after.locked, isFalse);
      expect(after.flipX, isTrue);
      expect(after.flipY, isTrue);
      expect(after.fill.foreground?.value, 0xFF00AA00);
    });

    test('set_style lineSpacing null does not clear absolute', () {
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
            richText: VsdxRichText(
              runs: [
                VsdxTextRun(
                  text: 'Hi',
                  paraStyle: const VsdxParaStyle(
                    lineSpacingAbsoluteInches: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'lineSpacing': 'not-a-number',
        },
      ]);
      final p = r.document.pages.first
          .findShapeById(id)!
          .richText
          .runs
          .first
          .paraStyle;
      expect(p.lineSpacingAbsoluteInches, closeTo(0.2, 1e-9));
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
          'lineJoin': 'miter-clip',
          'miterLimit': 8,
          'italic': true,
          'bold': true,
          'align': 'center',
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      expect(after.richText.textBlock.hideText, isTrue);
      expect(after.line.cap, LineCap.square);
      expect(after.line.join, VsdxLineJoin.miterClip);
      expect(after.line.miterLimit, 8);
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
            'angle': 90, // degrees
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
      expect(
        after.fill.gradient!.angleRad,
        closeTo(3.141592653589793 / 2, 1e-9),
      );
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

    test('set_style strikethrough', () {
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
          'strikethrough': true,
        },
      ]);
      expect(
        r.document.pages.first
            .findShapeById(id)!
            .richText
            .runs
            .first
            .charStyle
            .strikethrough,
        isTrue,
      );
    });

    test('set_style char extras and fillBackgroundTransparency', () {
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
          'doubleUnderline': true,
          'overline': true,
          'smallCaps': true,
          'textCase': 'allcaps',
          'letterSpacingPt': 1.5,
          'textTransparency': 0.25,
          'langId': 'zh-CN',
          'asianFont': 'SimSun',
          'fillBackgroundTransparency': 0.4,
          'doubleStrikethrough': true,
          'textPosition': 'superscript',
          'fontScale': 0.85,
          'complexScriptFont': 'Arial',
          'complexScriptSizePt': 10,
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      final c = after.richText.runs.first.charStyle;
      expect(c.doubleUnderline, isTrue);
      expect(c.overline, isTrue);
      expect(c.style.smallCaps, isTrue);
      expect(c.textCase, VsdxTextCase.allCaps);
      expect(c.letterSpacingInches, closeTo(1.5 / 72.0, 1e-9));
      expect(c.transparency, closeTo(0.25, 1e-9));
      expect(c.langId, 'zh-CN');
      expect(c.asianFont, 'SimSun');
      expect(after.fill.backgroundTransparency, closeTo(0.4, 1e-9));
      expect(c.doubleStrikethrough, isTrue);
      expect(c.position, VsdxTextPosition.superscript);
      expect(c.fontScale, closeTo(0.85, 1e-9));
      expect(c.complexScriptFont, 'Arial');
      expect(c.complexScriptSizeInches, closeTo(10 / 72.0, 1e-9));
    });

    test('set_style textBackground margins and paragraph indent', () {
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
          'textBackground': '#FFEEDD',
          'textBackgroundTransparency': 0.2,
          'marginLeft': 0.1,
          'marginRight': 0.12,
          'indentFirst': 0.25,
          'spaceBefore': 0.05,
          'lineSpacing': 1.5,
          'bullet': 1,
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      final tb = after.richText.textBlock;
      expect(tb.backgroundColor?.value, 0xFFFFEEDD);
      expect(tb.backgroundTransparency, closeTo(0.2, 1e-9));
      expect(tb.marginLeftInches, closeTo(0.1, 1e-9));
      expect(tb.marginRightInches, closeTo(0.12, 1e-9));
      final p = after.richText.runs.first.paraStyle;
      expect(p.indentFirstInches, closeTo(0.25, 1e-9));
      expect(p.spaceBeforeInches, closeTo(0.05, 1e-9));
      expect(p.lineSpacing, closeTo(1.5, 1e-9));
      expect(p.bullet, 1);
    });

    test('withLabel empty keeps textBlock; set_style textDirection/bulletFont',
        () {
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
            text: 'Hi',
            richText: VsdxRichText(
              runs: const [VsdxTextRun(text: 'Hi')],
              textBlock: const VsdxTextBlock(
                textDirection: 1,
                defaultTabStopInches: 0.75,
                marginLeftInches: 0.2,
              ),
            ),
          ),
        ),
      );
      final cleared = withLabel(doc.pages.first.findShapeById(id)!, '');
      expect(cleared.text, isEmpty);
      expect(cleared.richText.runs, isEmpty);
      expect(cleared.richText.textBlock.textDirection, 1);
      expect(
          cleared.richText.textBlock.defaultTabStopInches, closeTo(0.75, 1e-9));
      expect(cleared.richText.textBlock.marginLeftInches, closeTo(0.2, 1e-9));

      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'textDirection': 'horizontal',
          'defaultTabStop': 0.6,
          'bulletFont': 'Segoe UI Symbol',
          'bulletFontSizePt': 12,
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      expect(after.richText.textBlock.textDirection, 0);
      expect(after.richText.textBlock.defaultTabStopInches, closeTo(0.6, 1e-9));
      expect(after.richText.runs.first.paraStyle.bulletFont, 'Segoe UI Symbol');
      expect(
        after.richText.runs.first.paraStyle.bulletFontSizeInches,
        closeTo(12 / 72.0, 1e-9),
      );
    });

    test(
        'set_style lineSpacing clears absolute; applyCharStyle keeps textBlock',
        () {
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
            richText: VsdxRichText(
              textBlock: const VsdxTextBlock(
                textDirection: 1,
                marginLeftInches: 0.15,
              ),
              runs: [
                VsdxTextRun(
                  text: '',
                  paraStyle: const VsdxParaStyle(
                    lineSpacingAbsoluteInches: 0.2,
                    lineSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final styled = applyCharStyle(
        doc.pages.first.findShapeById(id)!,
        bold: true,
      );
      expect(styled.richText.textBlock.textDirection, 1);
      expect(styled.richText.textBlock.marginLeftInches, closeTo(0.15, 1e-9));
      expect(styled.richText.runs.first.charStyle.style.bold, isTrue);

      final r = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'lineSpacing': 1.5,
          'textPosAfterBullet': 0.08,
        },
      ]);
      final after = r.document.pages.first.findShapeById(id)!;
      final p = after.richText.runs.first.paraStyle;
      expect(p.lineSpacing, closeTo(1.5, 1e-9));
      expect(p.lineSpacingAbsoluteInches, 0);
      expect(p.lineSpacingSolid, isFalse);
      expect(p.textPosAfterBulletInches, closeTo(0.08, 1e-9));
      expect(after.richText.textBlock.textDirection, 1);

      // Both relative + absolute in one op: relative must clear absolute.
      final both = applyOps(r.document, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_style',
          'ids': <String>['shape:$id'],
          'lineSpacingAbsolute': 0.3,
          'lineSpacing': 1.2,
        },
      ]);
      final p2 = both.document.pages.first
          .findShapeById(id)!
          .richText
          .runs
          .first
          .paraStyle;
      expect(p2.lineSpacing, closeTo(1.2, 1e-9));
      expect(p2.lineSpacingAbsoluteInches, 0);
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

    test('applyOpsBytes does not rewrite a rejected batch', () {
      final original = DiagramSpec.parse(_spec).build();
      final result = applyOpsBytesResult(original, '''
        { "ops": [ { "op": "delete_shape", "id": 99999 } ] }''');
      expect(result.bytes, same(original));
      expect(result.changed, isFalse);
      expect(result.pageIndex, 0);
      expect(result.log.single, contains('not found'));
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
      final style = r.document.pages.first
          .findShapeById(id)!
          .richText
          .runs
          .single
          .charStyle;
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
      doc = doc.replacePage(
          0, doc.pages.first.copyWith(shapes: <VsdxShape>[group]));
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

    test('duplicate_shape remaps ids, formulas, and internal connector glue',
        () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      var page = doc.pages.first.copyWith(
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
          ).copyWith(
            formulas: const <String, String>{'PinX': 'Sheet.1!PinX+4'},
          ),
        ],
      );
      final link = buildConnector(
        id: 3,
        page: page,
        a: page.findShapeById(1)!,
        b: page.findShapeById(2)!,
      );
      page = page
          .addShape(link.connector)
          .copyWith(connects: link.connects)
          .syncGlueTriggers()
          .rerouteConnectors();
      doc = doc.replacePage(0, page);

      final result = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'duplicate_shape',
          'ids': <int>[1, 2, 3],
          'dx': 0.5,
          'dy': -0.25,
        },
      ]);
      final after = result.document.pages.first;
      expect(result.createdIds, hasLength(3));
      expect(after.shapes, hasLength(6));
      expect(after.connects, hasLength(4));
      expect(after.shapes.map((s) => s.id).toSet(), hasLength(6));

      final newConnector = after.findShapeById(result.createdIds.last)!;
      final newRows = after.connects
          .where((c) => c.fromSheetId == newConnector.id)
          .toList();
      expect(newRows, hasLength(2));
      expect(
        newRows.map((c) => c.toSheetId).toSet(),
        result.createdIds.take(2).toSet(),
      );
      final newTarget = after.findShapeById(result.createdIds[1])!;
      expect(
        newTarget.formulas['PinX'],
        contains('Sheet.${result.createdIds.first}!'),
      );
      expect(newTarget.formulas['PinX'], isNot(contains('Sheet.1!')));

      final reopened = const DocumentParser().parse(
        const VsdxWriter().write(
          originalBytes: blank,
          edited: result.document,
        ),
      );
      expect(validateDocument(reopened).where((i) => i.severity == 'error'),
          isEmpty);
      expect(reopened.pages.first.connects, hasLength(4));
    });

    test('group and ungroup provide draw.io structural edits', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      doc = doc.replacePage(
        0,
        doc.pages.first.copyWith(
          shapes: <VsdxShape>[
            VsdxShapeFactory.rectangle(
              id: 1,
              pinX: 2,
              pinY: 2,
              width: 1,
              height: 1,
            ),
            VsdxShapeFactory.rectangle(
              id: 2,
              pinX: 4,
              pinY: 2,
              width: 1,
              height: 1,
            ),
          ],
        ),
      );

      final grouped = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'group',
          'ids': <int>[1, 2],
          'name': 'Pair',
        },
      ]);
      expect(grouped.createdIds, hasLength(1));
      final groupId = grouped.createdIds.single;
      final group = grouped.document.pages.first.findShapeById(groupId)!;
      expect(group.shapeKind, VsdxShapeKind.group);
      expect(group.name, 'Pair');
      expect(group.children.map((s) => s.id), <int>[1, 2]);
      expect(grouped.document.pages.first.shapes, hasLength(1));

      final ungrouped = applyOps(grouped.document, <Map<String, dynamic>>[
        <String, dynamic>{'op': 'ungroup', 'id': groupId},
      ]);
      expect(ungrouped.document.pages.first.findShapeById(groupId), isNull);
      expect(
          ungrouped.document.pages.first.shapes.map((s) => s.id), <int>[1, 2]);
    });

    test('reparent_shapes preserves page geometry and connector glue', () {
      final original = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(original);
      var page = doc.pages.first;
      final container = VsdxShapeFactory.container(
        id: 1,
        pinX: 5,
        pinY: 4,
        width: 4,
        height: 3,
      );
      final child = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 4,
        pinY: 4,
        width: 1,
        height: 1,
      );
      final outside = VsdxShapeFactory.rectangle(
        id: 3,
        pinX: 8,
        pinY: 4,
        width: 1,
        height: 1,
      );
      page = page.copyWith(shapes: <VsdxShape>[container, child, outside]);
      final link = buildConnector(id: 4, page: page, a: child, b: outside);
      page = page
          .addShape(link.connector)
          .copyWith(connects: link.connects)
          .rerouteConnectors();
      doc = doc.replacePage(0, page);
      final beforePin = page.shapePinPage(child.id);
      final beforeConnects = page.connects;

      final nested = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'reparent_shapes',
          'ids': <dynamic>[child.id],
          'parent': container.id,
        },
      ]);

      expect(nested.log, isEmpty);
      final nestedPage = nested.document.pages.first;
      expect(nestedPage.findParentId(child.id), container.id);
      expect(nestedPage.shapePinPage(child.id).x, closeTo(beforePin.x, 1e-6));
      expect(nestedPage.shapePinPage(child.id).y, closeTo(beforePin.y, 1e-6));
      expect(nestedPage.connects, beforeConnects);
      expect(
        listShapes(nested.document)
            .singleWhere((entry) => entry['id'] == child.id)['parentId'],
        container.id,
      );

      final reopened = const DocumentParser().parse(
        const VsdxWriter().write(
          originalBytes: original,
          edited: nested.document,
        ),
      );
      final reopenedPage = reopened.pages.first;
      expect(reopenedPage.findParentId(child.id), container.id);
      expect(reopenedPage.shapePinPage(child.id).x, closeTo(beforePin.x, 1e-6));
      expect(reopenedPage.shapePinPage(child.id).y, closeTo(beforePin.y, 1e-6));
      expect(
        reopenedPage.connects
            .map((connect) => (
                  connect.fromSheetId,
                  connect.fromCell,
                  connect.fromPart,
                  connect.toSheetId,
                  connect.toCell,
                  connect.toPart,
                ))
            .toList(),
        beforeConnects
            .map((connect) => (
                  connect.fromSheetId,
                  connect.fromCell,
                  connect.fromPart,
                  connect.toSheetId,
                  connect.toCell,
                  connect.toPart,
                ))
            .toList(),
      );

      final ejected = applyOps(reopened, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'reparent_shapes',
          'ids': <dynamic>['shape:${child.id}'],
          'parent': 'none',
        },
      ]);
      final ejectedPage = ejected.document.pages.first;
      expect(ejected.log, isEmpty);
      expect(ejectedPage.findParentId(child.id), isNull);
      expect(ejectedPage.shapePinPage(child.id).x, closeTo(beforePin.x, 1e-6));
      expect(ejectedPage.shapePinPage(child.id).y, closeTo(beforePin.y, 1e-6));
      expect(
        ejectedPage.connects
            .map((connect) => (
                  connect.fromSheetId,
                  connect.fromCell,
                  connect.fromPart,
                  connect.toSheetId,
                  connect.toCell,
                  connect.toPart,
                ))
            .toList(),
        beforeConnects
            .map((connect) => (
                  connect.fromSheetId,
                  connect.fromCell,
                  connect.fromPart,
                  connect.toSheetId,
                  connect.toCell,
                  connect.toPart,
                ))
            .toList(),
      );
    });

    test('set_collapsed hides children and restores their connector glue', () {
      final original = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(original);
      var page = doc.pages.first;
      final container = VsdxShapeFactory.container(
        id: 1,
        pinX: 5,
        pinY: 4,
        width: 4,
        height: 3,
      );
      final child = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 4.5,
        pinY: 3.5,
        width: 1,
        height: 1,
      );
      final outside = VsdxShapeFactory.rectangle(
        id: 3,
        pinX: 8,
        pinY: 4,
        width: 1,
        height: 1,
      );
      page = page.copyWith(shapes: <VsdxShape>[
        container,
        child,
        outside
      ]).reparentShape(child.id, container.id);
      final link = buildConnector(
        id: 4,
        page: page,
        a: page.findShapeById(child.id)!,
        b: outside,
      );
      page = page
          .addShape(link.connector)
          .copyWith(connects: link.connects)
          .rerouteConnectors();
      doc = doc.replacePage(0, page);

      final folded = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_collapsed',
          'id': container.id,
          'collapsed': true,
        },
      ]);

      expect(folded.log, isEmpty);
      final foldedPage = folded.document.pages.first;
      final foldedHost = foldedPage.findShapeById(container.id)!;
      expect(foldedHost.collapsed, isTrue);
      expect(foldedHost.height, lessThan(container.height));
      expect(foldedPage.findParentId(child.id), container.id);
      expect(
        foldedPage.connects.any((connect) => connect.toSheetId == child.id),
        isFalse,
      );
      expect(
        foldedPage.findShapeById(link.connector.id)!.formulas['BegTrigger'],
        isNull,
      );
      final listed = listShapes(folded.document)
          .singleWhere((entry) => entry['id'] == container.id);
      expect(listed['container'], isTrue);
      expect(listed['foldable'], isTrue);
      expect(listed['collapsed'], isTrue);

      final reopened = const DocumentParser().parse(
        const VsdxWriter().write(
          originalBytes: original,
          edited: folded.document,
        ),
      );
      expect(
        reopened.pages.first.findShapeById(container.id)!.shapeKind,
        VsdxShapeKind.container,
      );
      expect(
          reopened.pages.first.findShapeById(container.id)!.collapsed, isTrue);
      expect(
        reopened.pages.first.connects
            .any((connect) => connect.toSheetId == child.id),
        isFalse,
      );

      final expanded = applyOps(reopened, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_container_collapsed',
          'id': 'shape:${container.id}',
          'collapsed': false,
        },
      ]);
      expect(expanded.log, isEmpty);
      final expandedPage = expanded.document.pages.first;
      final expandedHost = expandedPage.findShapeById(container.id)!;
      expect(expandedHost.collapsed, isFalse);
      expect(expandedHost.height, closeTo(container.height, 1e-6));
      expect(
        expandedPage.connects.any((connect) =>
            connect.fromSheetId == link.connector.id &&
            connect.toSheetId == child.id),
        isTrue,
      );
      expect(
        expandedPage.findShapeById(link.connector.id)!.formulas['BegTrigger'],
        contains('Sheet.${child.id}!'),
      );
      expect(
        expandedHost.userCells
            .any((cell) => cell.name == VsdxShape.userCollapsedGlue),
        isFalse,
      );

      final locked = expanded.document.replacePage(
        0,
        expandedPage.updateShapeById(
          container.id,
          (shape) => shape.copyWith(locked: true),
        ),
      );
      final blocked = applyOps(locked, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_collapsed',
          'id': container.id,
          'collapsed': true,
        },
      ]);
      expect(blocked.document, same(locked));
      expect(blocked.log.single, contains('locked'));
    });

    test('align and distribute use rotation-aware page bounds', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      doc = doc.replacePage(
        0,
        doc.pages.first.copyWith(
          shapes: <VsdxShape>[
            VsdxShapeFactory.rectangle(
              id: 1,
              pinX: 1.5,
              pinY: 2,
              width: 1,
              height: 1,
            ),
            VsdxShapeFactory.rectangle(
              id: 2,
              pinX: 5,
              pinY: 4,
              width: 2,
              height: 1,
            ).copyWith(angleRad: 0.35),
            VsdxShapeFactory.rectangle(
              id: 3,
              pinX: 8.5,
              pinY: 6,
              width: 1,
              height: 1,
            ),
          ],
        ),
      );

      final aligned = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'align',
          'ids': <int>[1, 2, 3],
          'mode': 'middle',
        },
      ]).document.pages.first;
      final centres = <double>[
        for (final id in <int>[1, 2, 3])
          () {
            final b = aligned.shapePageAabb(id)!;
            return (b.bottom + b.top) / 2;
          }(),
      ];
      expect(centres[1], closeTo(centres[0], 1e-9));
      expect(centres[2], closeTo(centres[0], 1e-9));

      final distributed = applyOps(
        doc.replacePage(
          0,
          doc.pages.first.updateShapeById(
            2,
            (s) => VsdxPage.translateShape(s, -1.3, 0),
          ),
        ),
        <Map<String, dynamic>>[
          <String, dynamic>{
            'op': 'distribute',
            'ids': <int>[1, 2, 3],
            'axis': 'horizontal',
          },
        ],
      ).document.pages.first;
      final boxes = <dynamic>[
        for (final id in <int>[1, 2, 3]) distributed.shapePageAabb(id)!,
      ]..sort((a, b) => a.left.compareTo(b.left));
      final gapA = boxes[1].left - boxes[0].right;
      final gapB = boxes[2].left - boxes[1].right;
      expect(gapA, closeTo(gapB, 1e-9));
    });

    test('z_order supports draw.io front/back/step actions', () {
      final blank = const VsdxWriter().emptyDocument();
      var doc = const DocumentParser().parse(blank);
      doc = doc.replacePage(
        0,
        doc.pages.first.copyWith(
          shapes: <VsdxShape>[
            for (var id = 1; id <= 3; id++)
              VsdxShapeFactory.rectangle(
                id: id,
                pinX: id.toDouble(),
                pinY: 2,
                width: 1,
                height: 1,
              ),
          ],
        ),
      );
      final front = applyOps(doc, <Map<String, dynamic>>[
        <String, dynamic>{'op': 'z_order', 'id': 1, 'action': 'front'},
      ]).document;
      expect(front.pages.first.shapes.map((s) => s.id), <int>[2, 3, 1]);
      final backward = applyOps(front, <Map<String, dynamic>>[
        <String, dynamic>{'op': 'z_order', 'id': 1, 'action': 'backward'},
      ]).document;
      expect(backward.pages.first.shapes.map((s) => s.id), <int>[2, 1, 3]);
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
            fromSheetId: 999,
            fromCell: 'BeginX',
            toSheetId: 998,
            toCell: 'PinX'),
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
      expect(
          validateDocument(doc).where((i) => i.severity == 'error'), isEmpty);
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
