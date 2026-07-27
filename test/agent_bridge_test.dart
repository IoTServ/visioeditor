import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vsdx/agent.dart';
import 'package:vsdx/vsdx.dart';
import 'package:visioeditor/agent_bridge/agent_bridge.dart';
import 'package:visioeditor/editor/editor_workspace.dart';

const _spec =
    '{"nodes":[{"id":"a","text":"A"},{"id":"b","text":"B"}],'
    '"edges":[{"from":"a","to":"b"}]}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late File file;
  late EditorWorkspace workspace;
  late AgentBridge bridge;
  late WebSocket socket;
  late Stream<Map<String, dynamic>> incoming;
  late Future<void> Function(String path) openPathHandler;
  var requestIdSeed = 0;

  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    final id = ++requestIdSeed;
    socket.add(
      jsonEncode(<String, dynamic>{
        'id': id,
        'method': method,
        'params': params ?? const <String, dynamic>{},
      }),
    );
    return incoming.firstWhere((m) => m['id'] == id);
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('agent_bridge_test');
    file = File('${tmp.path}/diagram.vsdx');
    await file.writeAsBytes(DiagramSpec.parse(_spec).build());

    workspace = EditorWorkspace();
    await workspace.openBytes(
      await file.readAsBytes(),
      path: file.path,
      name: 'diagram.vsdx',
    );

    openPathHandler = (p) async {};
    bridge = AgentBridge(
      workspace: workspace,
      openPath: (p) => openPathHandler(p),
    );
    await bridge.start();

    socket = await WebSocket.connect(
      'ws://127.0.0.1:${bridge.port}/?token=${bridge.token}',
    );
    incoming = socket
        .map((d) => (jsonDecode(d as String) as Map).cast<String, dynamic>())
        .asBroadcastStream();
  });

  tearDown(() async {
    await socket.close();
    await bridge.stop();
    workspace.dispose();
    await tmp.delete(recursive: true);
  });

  test('rejects a connection without the token', () async {
    await expectLater(
      WebSocket.connect('ws://127.0.0.1:${bridge.port}/?token=wrong'),
      throwsA(isA<WebSocketException>()),
    );
  });

  test('ping returns engine version', () async {
    final r = await call('ping');
    expect(r['ok'], isTrue);
    expect((r['result'] as Map)['pong'], isTrue);
  });

  test('getState reports the open document', () async {
    final r = await call('getState');
    final state = r['result'] as Map;
    expect(state['hasDocument'], isTrue);
    expect((state['pages'] as List), hasLength(1));
    expect((state['pages'] as List).first['shapes'], greaterThanOrEqualTo(3));
    expect(state['layers'], isEmpty);
  });

  test('listShapes returns the active page shapes with ids', () async {
    final r = await call('listShapes');
    final shapes = (r['result'] as Map)['shapes'] as List;
    expect(shapes, isNotEmpty);
    expect(shapes.first.containsKey('id'), isTrue);
    final texts = shapes.map((s) => s['text']).toSet();
    expect(texts, containsAll(<String>['A', 'B']));
  });

  test('select accepts nested ids returned by listShapes', () async {
    final c = workspace.active!;
    c.addShapeFromBuilderAt(
      (id, x, y) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: x,
        pinY: y,
        width: 1,
        height: 1,
      ),
      2,
      2,
    );
    final a = c.singleSelectedId!;
    c.addShapeFromBuilderAt(
      (id, x, y) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: x,
        pinY: y,
        width: 1,
        height: 1,
      ),
      4,
      2,
    );
    final b = c.singleSelectedId!;
    c.setSelection(<int>[a, b]);
    c.groupSelection();

    final listed = await call('listShapes');
    final shapes = (listed['result'] as Map)['shapes'] as List;
    final nested = shapes.cast<Map>().firstWhere(
      (s) => s.containsKey('parentId'),
    );
    final nestedId = nested['id'] as int;

    final selected = await call('select', <String, dynamic>{
      'ids': <dynamic>[nestedId],
    });
    expect(selected['ok'], isTrue);
    expect((selected['result'] as Map)['selection'], <int>[nestedId]);
    expect((selected['result'] as Map).containsKey('unknown'), isFalse);
  });

  test('select highlights shapes and clears with an empty list', () async {
    final listed = await call('listShapes');
    final shapes = (listed['result'] as Map)['shapes'] as List;
    final idA = shapes.firstWhere((s) => s['text'] == 'A')['id'] as int;
    final idB = shapes.firstWhere((s) => s['text'] == 'B')['id'] as int;

    final r = await call('select', <String, dynamic>{
      'ids': <dynamic>[idA, idB, 99999],
    });
    expect(r['ok'], isTrue);
    final state = r['result'] as Map;
    expect(state['selection'], containsAll(<int>[idA, idB]));
    expect(state['unknown'], contains(99999));
    expect(workspace.active!.selection, containsAll(<int>[idA, idB]));

    final cleared = await call('select', <String, dynamic>{'ids': <dynamic>[]});
    expect(cleared['ok'], isTrue);
    expect((cleared['result'] as Map)['selection'], isEmpty);
    expect(workspace.active!.selection, isEmpty);
  });

  test('applyOps edits the in-memory model (instant, no disk write)', () async {
    final before = File(file.path).statSync().modified;
    final r = await call('applyOps', <String, dynamic>{
      'ops': <dynamic>[
        <String, dynamic>{'op': 'add_shape', 'text': 'C', 'x': 1.0, 'y': 1.0},
      ],
    });
    expect(r['ok'], isTrue);
    // The active document grew…
    final doc = workspace.active!.document!;
    expect(doc.pages.single.shapes.any((s) => s.text == 'C'), isTrue);
    // …but the file on disk is untouched (in-memory preview).
    expect(File(file.path).statSync().modified, before);
  });

  test('applyOps returns created ids and invalid batches stay clean', () async {
    final c = workspace.active!;
    final added = await call('applyOps', <String, dynamic>{
      'ops': <dynamic>[
        <String, dynamic>{'op': 'add_shape', 'text': 'Created'},
      ],
    });
    final addedResult = added['result'] as Map;
    expect(addedResult['changed'], isTrue);
    expect(addedResult['created'], hasLength(1));

    // Return to the clean baseline, then prove a rejected op is a true no-op:
    // no dirty flag and no junk undo entry.
    c.undo();
    expect(c.isDirty, isFalse);
    expect(c.canUndo, isFalse);
    final invalid = await call('applyOps', <String, dynamic>{
      'ops': <dynamic>[
        <String, dynamic>{'op': 'move_shape', 'id': 99999, 'x': 1, 'y': 1},
      ],
    });
    final invalidResult = invalid['result'] as Map;
    expect(invalidResult['changed'], isFalse);
    expect(invalidResult['log'], isNotEmpty);
    expect(c.isDirty, isFalse);
    expect(c.canUndo, isFalse);
  });

  test('requests execute in WebSocket order across async open', () async {
    final next = File('${tmp.path}/next.vsdx');
    await next.writeAsBytes(
      DiagramSpec.parse(
        '{"nodes":[{"id":"next","text":"Next document"}]}',
      ).build(),
    );
    final gate = Completer<void>();
    openPathHandler = (path) async {
      await gate.future;
      await workspace.openBytes(
        await File(path).readAsBytes(),
        path: path,
        name: 'next.vsdx',
      );
    };

    final openId = ++requestIdSeed;
    final applyId = ++requestIdSeed;
    final openReply = incoming.firstWhere((m) => m['id'] == openId);
    final applyReply = incoming.firstWhere((m) => m['id'] == applyId);
    socket
      ..add(
        jsonEncode(<String, dynamic>{
          'id': openId,
          'method': 'open',
          'params': <String, dynamic>{'path': next.path},
        }),
      )
      ..add(
        jsonEncode(<String, dynamic>{
          'id': applyId,
          'method': 'applyOps',
          'params': <String, dynamic>{
            'ops': <dynamic>[
              <String, dynamic>{'op': 'add_shape', 'text': 'After open'},
            ],
          },
        }),
      );

    await Future<void>.delayed(const Duration(milliseconds: 20));
    gate.complete();
    expect((await openReply)['ok'], isTrue);
    expect((await applyReply)['ok'], isTrue);
    expect(workspace.active!.filePath, next.path);
    expect(
      workspace.active!.document!.pages.single.shapes.any(
        (s) => s.text == 'After open',
      ),
      isTrue,
    );
  });

  test(
    'applyOps is L3 co-editing: one undoable step, history preserved',
    () async {
      final c = workspace.active!;
      final beforeShapes = c.document!.pages.single.shapes.length;
      expect(c.canUndo, isFalse); // freshly opened document
      await call('applyOps', <String, dynamic>{
        'ops': <dynamic>[
          <String, dynamic>{
            'op': 'add_shape',
            'text': 'Live',
            'x': 1.0,
            'y': 1.0,
          },
        ],
      });
      expect(c.canUndo, isTrue);
      expect(c.document!.pages.single.shapes.length, beforeShapes + 1);
      // The user can undo the Agent's edit.
      c.undo();
      expect(c.document!.pages.single.shapes.length, beforeShapes);
      expect(
        c.document!.pages.single.shapes.any((s) => s.text == 'Live'),
        isFalse,
      );
    },
  );

  test('draw.io structural ops apply live as one undoable batch', () async {
    final c = workspace.active!;
    final page = c.document!.pages.single;
    final a = page.shapes.firstWhere((s) => s.text == 'A').id;
    final b = page.shapes.firstWhere((s) => s.text == 'B').id;
    final before = page.shapes.length;

    final response = await call('applyOps', <String, dynamic>{
      'ops': <dynamic>[
        <String, dynamic>{
          'op': 'duplicate_shape',
          'ids': <int>[a, b],
          'dx': 0.4,
          'dy': 0.4,
        },
        <String, dynamic>{
          'op': 'group',
          'ids': <int>[a, b],
          'name': 'Live group',
        },
      ],
    });

    expect(response['ok'], isTrue);
    final result = response['result'] as Map;
    expect(result['changed'], isTrue);
    expect(result['created'], hasLength(3));
    expect(
      c.document!.pages.single.shapes
          .where((s) => s.shapeKind == VsdxShapeKind.group)
          .single
          .name,
      'Live group',
    );
    expect(c.canUndo, isTrue);

    c.undo();
    expect(c.document!.pages.single.shapes, hasLength(before));
    expect(
      c.document!.pages.single.shapes.where(
        (s) => s.shapeKind == VsdxShapeKind.group,
      ),
      isEmpty,
    );
  });

  test('draw.io container hierarchy applies live and undoes cleanly', () async {
    final c = workspace.active!;
    final added = await call('applyOps', <String, dynamic>{
      'ops': <dynamic>[
        <String, dynamic>{
          'op': 'add_shape',
          'stencil': 'Container',
          'text': 'Live host',
          'x': 5,
          'y': 4,
          'w': 5,
          'h': 3,
        },
      ],
    });
    expect(added['ok'], isTrue);
    final host = ((added['result'] as Map)['created'] as List).single as int;
    final beforePage = c.document!.pages.single;
    final a = beforePage.shapes.firstWhere((shape) => shape.text == 'A').id;
    final b = beforePage.shapes.firstWhere((shape) => shape.text == 'B').id;
    final beforeA = beforePage.shapePinPage(a);
    final beforeB = beforePage.shapePinPage(b);
    final beforeConnects = beforePage.connects;

    final response = await call('applyOps', <String, dynamic>{
      'ops': <dynamic>[
        <String, dynamic>{
          'op': 'reparent_shapes',
          'ids': <dynamic>[a, 'shape:$b'],
          'parent': '$host',
        },
      ],
    });

    expect(response['ok'], isTrue);
    expect((response['result'] as Map)['changed'], isTrue);
    final editedPage = c.document!.pages.single;
    expect(VsdxPage.isDropContainer(editedPage.findShapeById(host)!), isTrue);
    expect(editedPage.findParentId(a), host);
    expect(editedPage.findParentId(b), host);
    expect(editedPage.shapePinPage(a).x, closeTo(beforeA.x, 1e-6));
    expect(editedPage.shapePinPage(a).y, closeTo(beforeA.y, 1e-6));
    expect(editedPage.shapePinPage(b).x, closeTo(beforeB.x, 1e-6));
    expect(editedPage.shapePinPage(b).y, closeTo(beforeB.y, 1e-6));
    expect(editedPage.connects, beforeConnects);

    final listed = await call('listShapes');
    final listedShapes = (listed['result'] as Map)['shapes'] as List;
    expect(
      listedShapes.singleWhere((shape) => shape['id'] == a)['parentId'],
      host,
    );

    expect(c.canUndo, isTrue);
    c.undo();
    final restoredPage = c.document!.pages.single;
    expect(restoredPage.findShapeById(host), isNotNull);
    expect(restoredPage.findParentId(a), isNull);
    expect(restoredPage.findParentId(b), isNull);
    expect(restoredPage.shapePinPage(a).x, closeTo(beforeA.x, 1e-6));
    expect(restoredPage.shapePinPage(b).x, closeTo(beforeB.x, 1e-6));
    expect(restoredPage.connects, beforeConnects);
  });

  test(
    'draw.io container collapse applies live and restores hidden glue',
    () async {
      final c = workspace.active!;
      final added = await call('applyOps', <String, dynamic>{
        'ops': <dynamic>[
          <String, dynamic>{
            'op': 'add_shape',
            'stencil': 'Container',
            'text': 'Fold host',
            'x': 5,
            'y': 4,
            'w': 5,
            'h': 3,
          },
        ],
      });
      final host = ((added['result'] as Map)['created'] as List).single as int;
      final page = c.document!.pages.single;
      final a = page.shapes.firstWhere((shape) => shape.text == 'A').id;
      final connector = page.shapes.singleWhere(
        (shape) => shape.isGlueableConnector,
      );
      final nested = await call('applyOps', <String, dynamic>{
        'ops': <dynamic>[
          <String, dynamic>{
            'op': 'reparent_shapes',
            'ids': <int>[a],
            'parent': host,
          },
        ],
      });
      expect((nested['result'] as Map)['changed'], isTrue);
      final expandedPage = c.document!.pages.single;
      final expandedHeight = expandedPage.findShapeById(host)!.height;
      expect(expandedPage.findParentId(a), host);
      expect(
        expandedPage.connects.any(
          (connect) =>
              connect.fromSheetId == connector.id && connect.toSheetId == a,
        ),
        isTrue,
      );

      final selected = await call('select', <String, dynamic>{
        'ids': <int>[a],
      });
      expect((selected['result'] as Map)['selection'], <int>[a]);

      final response = await call('applyOps', <String, dynamic>{
        'ops': <dynamic>[
          <String, dynamic>{
            'op': 'set_collapsed',
            'id': host,
            'collapsed': true,
          },
        ],
      });

      expect(response['ok'], isTrue);
      expect((response['result'] as Map)['changed'], isTrue);
      expect((response['result'] as Map)['selection'], isEmpty);
      final foldedPage = c.document!.pages.single;
      expect(foldedPage.findShapeById(host)!.collapsed, isTrue);
      expect(foldedPage.findShapeById(host)!.height, lessThan(expandedHeight));
      expect(foldedPage.findParentId(a), host);
      expect(
        foldedPage.connects.any(
          (connect) =>
              connect.fromSheetId == connector.id && connect.toSheetId == a,
        ),
        isFalse,
      );

      final listed = await call('listShapes');
      final listedShapes = (listed['result'] as Map)['shapes'] as List;
      final listedHost = listedShapes.singleWhere(
        (shape) => shape['id'] == host,
      );
      expect(listedHost['container'], isTrue);
      expect(listedHost['foldable'], isTrue);
      expect(listedHost['collapsed'], isTrue);

      c.undo();
      final restoredPage = c.document!.pages.single;
      expect(restoredPage.findShapeById(host)!.collapsed, isFalse);
      expect(restoredPage.findShapeById(host)!.height, expandedHeight);
      expect(restoredPage.findParentId(a), host);
      expect(
        restoredPage.connects.any(
          (connect) =>
              connect.fromSheetId == connector.id && connect.toSheetId == a,
        ),
        isTrue,
      );
      expect(c.selection, <int>{a});
    },
  );

  test(
    'draw.io layer controls apply live, select objects, and undo cleanly',
    () async {
      final c = workspace.active!;
      final page = c.document!.pages.single;
      final a = page.shapes.firstWhere((shape) => shape.text == 'A').id;
      final b = page.shapes.firstWhere((shape) => shape.text == 'B').id;

      final added = await call('applyOps', <String, dynamic>{
        'ops': <dynamic>[
          <String, dynamic>{
            'op': 'add_layer',
            'name': 'Live layer',
            'ids': <int>[a, b],
            'active': true,
            'color': '#336699',
          },
        ],
      });
      expect(added['ok'], isTrue);
      final addedResult = added['result'] as Map;
      expect(addedResult['createdLayers'], <int>[0]);
      expect((addedResult['layers'] as List).single['name'], 'Live layer');

      final listed = await call('listLayers');
      final layers = (listed['result'] as Map)['layers'] as List;
      expect(layers, hasLength(1));
      expect(layers.single['shapeIds'], containsAll(<int>[a, b]));

      final selected = await call('selectLayer', <String, dynamic>{
        'layerId': 0,
      });
      expect(selected['ok'], isTrue);
      expect(
        (selected['result'] as Map)['selection'],
        containsAll(<int>[a, b]),
      );
      expect(c.selection, containsAll(<int>[a, b]));

      final hidden = await call('applyOps', <String, dynamic>{
        'ops': <dynamic>[
          <String, dynamic>{'op': 'set_layer', 'layerId': 0, 'visible': false},
        ],
      });
      expect(hidden['ok'], isTrue);
      expect(c.selection, isEmpty);

      final hiddenSelection = await call('selectLayer', <String, dynamic>{
        'layerId': 0,
      });
      expect((hiddenSelection['result'] as Map)['selection'], isEmpty);

      c.undo();
      expect(c.document!.pages.single.layers.single.visible, isTrue);
      expect(c.selection, containsAll(<int>[a, b]));
    },
  );

  test(
    'draw.io shape data and links apply live as one undoable batch',
    () async {
      final c = workspace.active!;
      final a = c.document!.pages.single.shapes
          .firstWhere((shape) => shape.text == 'A')
          .id;

      final response = await call('applyOps', <String, dynamic>{
        'ops': <dynamic>[
          <String, dynamic>{
            'op': 'set_data',
            'id': a,
            'properties': <dynamic>[
              <String, dynamic>{'name': 'Owner', 'value': 'Platform'},
            ],
          },
          <String, dynamic>{
            'op': 'set_links',
            'id': a,
            'links': <dynamic>[
              <String, dynamic>{
                'description': 'Docs',
                'address': 'https://example.com/docs',
              },
            ],
          },
        ],
      });

      expect(response['ok'], isTrue);
      expect((response['result'] as Map)['changed'], isTrue);
      final shape = c.document!.pages.single.findShapeById(a)!;
      expect(shape.userProperties.single.value, 'Platform');
      expect(
        shape.primaryHyperlink?.effectiveTarget,
        'https://example.com/docs',
      );

      final listed = await call('listShapes');
      final listedShape = ((listed['result'] as Map)['shapes'] as List)
          .firstWhere((entry) => entry['id'] == a);
      expect((listedShape['data'] as List).single['name'], 'Owner');
      expect((listedShape['links'] as List).single['default'], isTrue);

      expect(c.canUndo, isTrue);
      c.undo();
      final restored = c.document!.pages.single.findShapeById(a)!;
      expect(restored.userProperties, isEmpty);
      expect(restored.hyperlinks, isEmpty);
    },
  );

  test('draw.io connector edits apply live as one undoable batch', () async {
    final c = workspace.active!;
    final page = c.document!.pages.single;
    final connector = page.shapes.singleWhere(
      (shape) => shape.isGlueableConnector,
    );
    final originalCurved = connector.curved;
    final originalRounded = connector.rounded;
    final originalWaypoints = connector.waypoints;
    final originalBeginTarget = page.connects
        .singleWhere(
          (connect) => connect.fromSheetId == connector.id && connect.isBegin,
        )
        .toSheetId;
    final originalEndTarget = page.connects
        .singleWhere(
          (connect) => connect.fromSheetId == connector.id && connect.isEnd,
        )
        .toSheetId;

    final response = await call('applyOps', <String, dynamic>{
      'ops': <dynamic>[
        <String, dynamic>{
          'op': 'set_connector',
          'id': connector.id,
          'route': 'curved',
          'rounded': true,
          'waypoints': <dynamic>[
            <String, dynamic>{'x': 3, 'y': 4},
          ],
        },
        <String, dynamic>{
          'op': 'reconnect_connector',
          'id': connector.id,
          'end': 'begin',
          'x': 1,
          'y': 1,
        },
      ],
    });

    expect(response['ok'], isTrue);
    expect((response['result'] as Map)['changed'], isTrue);
    final editedPage = c.document!.pages.single;
    final edited = editedPage.findShapeById(connector.id)!;
    expect(edited.curved, isTrue);
    expect(edited.rounded, isTrue);
    expect(edited.waypoints, hasLength(1));
    expect(
      editedPage.connects.where(
        (connect) => connect.fromSheetId == connector.id && connect.isBegin,
      ),
      isEmpty,
    );

    final listed = await call('listShapes');
    final listedConnector = ((listed['result'] as Map)['shapes'] as List)
        .singleWhere((entry) => entry['id'] == connector.id);
    expect(listedConnector['route'], 'curved');
    expect(listedConnector['waypoints'], hasLength(1));
    expect((listedConnector['begin'] as Map).containsKey('targetId'), isFalse);
    expect((listedConnector['end'] as Map)['targetId'], originalEndTarget);

    expect(c.canUndo, isTrue);
    c.undo();
    final restoredPage = c.document!.pages.single;
    final restored = restoredPage.findShapeById(connector.id)!;
    expect(restored.curved, originalCurved);
    expect(restored.rounded, originalRounded);
    expect(restored.waypoints, originalWaypoints);
    expect(
      restoredPage.connects
          .singleWhere(
            (connect) => connect.fromSheetId == connector.id && connect.isBegin,
          )
          .toSheetId,
      originalBeginTarget,
    );
    expect(
      restoredPage.connects
          .singleWhere(
            (connect) => connect.fromSheetId == connector.id && connect.isEnd,
          )
          .toSheetId,
      originalEndTarget,
    );
  });

  test('draw.io connection points apply live as one undoable batch', () async {
    final c = workspace.active!;
    final page = c.document!.pages.single;
    final a = page.shapes.firstWhere((shape) => shape.text == 'A');
    final connector = page.shapes.singleWhere(
      (shape) => shape.isGlueableConnector,
    );
    final originalPoints = a.connectionPoints;
    final originalBegin = page.connects.singleWhere(
      (connect) => connect.fromSheetId == connector.id && connect.isBegin,
    );
    final corner = page.localToPageDeep(a.id, const Offset2D(0, 0));
    final rightMiddle = page.localToPageDeep(
      a.id,
      Offset2D(a.width, a.height / 2),
    );

    final response = await call('applyOps', <String, dynamic>{
      'ops': <dynamic>[
        <String, dynamic>{
          'op': 'set_connection_points',
          'id': a.id,
          'coordinateSpace': 'page',
          'points': <dynamic>[
            <String, dynamic>{'x': corner.x, 'y': corner.y, 'prompt': 'Corner'},
            <String, dynamic>{
              'x': rightMiddle.x,
              'y': rightMiddle.y,
              'dirX': 1,
              'dirY': 0,
            },
          ],
        },
        <String, dynamic>{
          'op': 'reconnect_connector',
          'id': connector.id,
          'end': 'begin',
          'target': a.id,
          'connectionPoint': 1,
        },
      ],
    });

    expect(response['ok'], isTrue);
    expect((response['result'] as Map)['changed'], isTrue);
    final editedPage = c.document!.pages.single;
    expect(editedPage.findShapeById(a.id)!.connectionPoints, hasLength(2));
    expect(
      editedPage.connects
          .singleWhere(
            (connect) => connect.fromSheetId == connector.id && connect.isBegin,
          )
          .toPart,
      101,
    );

    final listed = await call('listShapes');
    final listedShapes = (listed['result'] as Map)['shapes'] as List;
    final listedA = listedShapes.singleWhere((entry) => entry['id'] == a.id);
    expect(listedA['connectionPoints'], hasLength(2));
    expect((listedA['connectionPoints'] as List).first['prompt'], 'Corner');
    final listedConnector = listedShapes.singleWhere(
      (entry) => entry['id'] == connector.id,
    );
    expect((listedConnector['begin'] as Map)['connectionPoint'], 1);

    expect(c.canUndo, isTrue);
    c.undo();
    final restoredPage = c.document!.pages.single;
    expect(restoredPage.findShapeById(a.id)!.connectionPoints, originalPoints);
    final restoredBegin = restoredPage.connects.singleWhere(
      (connect) => connect.fromSheetId == connector.id && connect.isBegin,
    );
    expect(restoredBegin.toSheetId, originalBegin.toSheetId);
    expect(restoredBegin.toPart, originalBegin.toPart);
  });

  test(
    'page ops switch live context, expose setup, and undo as one step',
    () async {
      final c = workspace.active!;
      final beforeShapes = c.document!.pages.single.shapes.length;

      final response = await call('applyOps', <String, dynamic>{
        'ops': <dynamic>[
          <String, dynamic>{
            'op': 'add_page',
            'name': 'Live page',
            'width': 13,
            'height': 7,
            'background': '#E1F5FE',
          },
          <String, dynamic>{'op': 'add_shape', 'text': 'Created on page two'},
        ],
      });

      expect(response['ok'], isTrue);
      final result = response['result'] as Map;
      expect(result['changed'], isTrue);
      expect(result['page'], 1);
      expect(result['currentPage'], 1);
      expect(result['createdPages'], hasLength(1));
      expect(c.currentPageIndex, 1);
      expect(c.document!.pages, hasLength(2));
      expect(c.document!.pages[1].shapes.single.text, 'Created on page two');
      final livePage = (result['pages'] as List)[1] as Map;
      expect(livePage['name'], 'Live page');
      expect(livePage['width'], 13);
      expect(livePage['height'], 7);
      expect(livePage['background'], '#E1F5FE');

      final selected = await call('selectPage', <String, dynamic>{'page': 0});
      expect(selected['ok'], isTrue);
      expect((selected['result'] as Map)['currentPage'], 0);
      expect(c.currentPageIndex, 0);

      c.undo();
      expect(c.currentPageIndex, 0);
      expect(c.document!.pages, hasLength(1));
      expect(c.document!.pages.single.shapes, hasLength(beforeShapes));
    },
  );

  test('applyOps page targets a non-active page and reports it', () async {
    final c = workspace.active!;
    c.addPage();
    c.selectPage(0);
    expect(c.currentPageIndex, 0);

    final r = await call('applyOps', <String, dynamic>{
      'page': 1,
      'ops': <dynamic>[
        <String, dynamic>{'op': 'add_shape', 'text': 'Page two'},
      ],
    });

    expect(r['ok'], isTrue);
    final result = r['result'] as Map;
    expect(result['page'], 1);
    expect(result['changed'], isTrue);
    expect(c.currentPageIndex, 0);
    expect(
      c.document!.pages[0].shapes.any((s) => s.text == 'Page two'),
      isFalse,
    );
    expect(
      c.document!.pages[1].shapes.any((s) => s.text == 'Page two'),
      isTrue,
    );

    c.undo();
    expect(c.currentPageIndex, 0);
    expect(
      c.document!.pages[1].shapes.any((s) => s.text == 'Page two'),
      isFalse,
    );
  });

  test('snapshot returns a PNG', () async {
    final r = await call('snapshot');
    expect(r['ok'], isTrue, reason: '${r['error']}');
    final bytes = base64Decode(r['result'] as String);
    // PNG magic number.
    expect(bytes.sublist(0, 4), <int>[0x89, 0x50, 0x4E, 0x47]);
  });

  test('save writes the current model back to disk', () async {
    await call('applyOps', <String, dynamic>{
      'ops': <dynamic>[
        <String, dynamic>{
          'op': 'add_shape',
          'text': 'Saved',
          'x': 1.0,
          'y': 1.0,
        },
      ],
    });
    final r = await call('save');
    expect(r['ok'], isTrue);
    final reopened = const DocumentParser().parse(await file.readAsBytes());
    expect(reopened.pages.single.shapes.any((s) => s.text == 'Saved'), isTrue);
  });

  test('reload rejects corrupt bytes without clearing the canvas', () async {
    final c = workspace.active!;
    final before = c.document;
    await file.writeAsString('not a vsdx');

    final r = await call('reload');
    expect(r['ok'], isFalse);
    expect(c.document, same(before));
    expect(c.error, isNull);
  });

  test('L1: external file change auto-reloads a clean document', () async {
    // Simulate `vsdxtool patch` rewriting the file with an extra node.
    const spec2 =
        '{"nodes":[{"id":"a","text":"A"},{"id":"b","text":"B"},'
        '{"id":"c","text":"Reloaded"}],"edges":[{"from":"a","to":"b"}]}';
    // Ensure a strictly-later mtime.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await file.writeAsBytes(DiagramSpec.parse(spec2).build());

    // Poll interval is 800ms; wait for the watcher to pick it up.
    var reloaded = false;
    for (var i = 0; i < 20 && !reloaded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      reloaded =
          workspace.active?.document?.pages.single.shapes.any(
            (s) => s.text == 'Reloaded',
          ) ??
          false;
    }
    expect(reloaded, isTrue);
  });
}
