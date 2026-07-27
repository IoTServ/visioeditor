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
