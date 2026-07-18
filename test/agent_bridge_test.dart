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
  var _id = 0;

  Future<Map<String, dynamic>> call(String method,
      [Map<String, dynamic>? params]) async {
    final id = ++_id;
    socket.add(jsonEncode(<String, dynamic>{
      'id': id,
      'method': method,
      'params': params ?? const <String, dynamic>{},
    }));
    return incoming.firstWhere((m) => m['id'] == id);
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('agent_bridge_test');
    file = File('${tmp.path}/diagram.vsdx');
    await file.writeAsBytes(DiagramSpec.parse(_spec).build());

    workspace = EditorWorkspace();
    await workspace.openBytes(await file.readAsBytes(),
        path: file.path, name: 'diagram.vsdx');

    bridge = AgentBridge(workspace: workspace, openPath: (p) async {});
    await bridge.start();

    socket = await WebSocket.connect(
        'ws://127.0.0.1:${bridge.port}/?token=${bridge.token}');
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
        <String, dynamic>{'op': 'add_shape', 'text': 'Saved', 'x': 1.0, 'y': 1.0},
      ],
    });
    final r = await call('save');
    expect(r['ok'], isTrue);
    final reopened =
        const DocumentParser().parse(await file.readAsBytes());
    expect(reopened.pages.single.shapes.any((s) => s.text == 'Saved'), isTrue);
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
      reloaded = workspace.active?.document?.pages.single.shapes
              .any((s) => s.text == 'Reloaded') ??
          false;
    }
    expect(reloaded, isTrue);
  });
}
