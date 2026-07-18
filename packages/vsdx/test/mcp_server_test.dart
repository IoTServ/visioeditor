import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vsdx/agent.dart';
import 'package:vsdx/vsdx.dart';

const _spec = {
  'title': 'MCP Flow',
  'nodes': [
    {'id': 'a', 'stencil': 'terminator', 'text': 'Start'},
    {'id': 'b', 'stencil': 'process', 'text': 'Work'},
    {'id': 'c', 'stencil': 'cylinder', 'text': 'DB'},
  ],
  'edges': [
    {'from': 'a', 'to': 'b'},
    {'from': 'b', 'to': 'c', 'label': 'save'},
  ],
};

void main() {
  late McpServer server;
  late Directory tmp;

  setUp(() {
    server = McpServer(name: 'visioeditor', version: '0.1.0');
    // File tools only — live tools need the running app.
    registerVsdxMcpTools(server, includeLiveTools: false);
    tmp = Directory.systemTemp.createTempSync('mcp_test');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<Map<String, dynamic>> rpc(String method,
          [Map<String, dynamic>? params]) async =>
      (await server.handle(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': method,
        if (params != null) 'params': params,
      }))!;

  Future<Map<String, dynamic>> callTool(
      String name, Map<String, dynamic> args) async {
    final resp = await rpc('tools/call',
        <String, dynamic>{'name': name, 'arguments': args});
    return resp['result'] as Map<String, dynamic>;
  }

  String firstText(Map<String, dynamic> result) =>
      (result['content'] as List).first['text'] as String;

  test('initialize returns serverInfo + tools capability', () async {
    final r = await rpc('initialize', <String, dynamic>{
      'protocolVersion': '2024-11-05',
      'capabilities': <String, dynamic>{},
    });
    final result = r['result'] as Map<String, dynamic>;
    expect(result['serverInfo']['name'], 'visioeditor');
    expect((result['capabilities'] as Map).containsKey('tools'), isTrue);
  });

  test('notifications/initialized yields no response', () async {
    final r = await server
        .handle(<String, dynamic>{'jsonrpc': '2.0', 'method': 'notifications/initialized'});
    expect(r, isNull);
  });

  test('tools/list advertises the file tools', () async {
    final r = await rpc('tools/list');
    final names = <String>[
      for (final t in (r['result']['tools'] as List)) t['name'] as String,
    ];
    expect(
        names,
        containsAll(<String>[
          'create_diagram',
          'apply_ops',
          'export',
          'validate',
          'explain',
          'search_shapes',
        ]));
    // Live tools excluded in this configuration.
    expect(names, isNot(contains('snapshot')));
  });

  test('create_diagram builds + validates a .vsdx', () async {
    final path = '${tmp.path}/flow.vsdx';
    final result = await callTool('create_diagram',
        <String, dynamic>{'spec': _spec, 'path': path});
    expect(result['isError'], isFalse);
    expect(firstText(result), contains('validation: clean'));
    expect(File(path).existsSync(), isTrue);
  });

  test('apply_ops then explain reflects the edit', () async {
    final path = '${tmp.path}/flow.vsdx';
    await callTool('create_diagram', <String, dynamic>{'spec': _spec, 'path': path});
    await callTool('apply_ops', <String, dynamic>{
      'path': path,
      'ops': <dynamic>[
        <String, dynamic>{'op': 'add_shape', 'text': 'Cache', 'x': 1.0, 'y': 1.0},
      ],
    });
    final explained = await callTool('explain', <String, dynamic>{'path': path});
    expect(firstText(explained), contains('Cache'));
  });

  test('export writes SVG', () async {
    final path = '${tmp.path}/flow.vsdx';
    await callTool('create_diagram', <String, dynamic>{'spec': _spec, 'path': path});
    final result =
        await callTool('export', <String, dynamic>{'path': path, 'format': 'svg'});
    expect(result['isError'], isFalse);
    expect(File('${tmp.path}/flow.svg').existsSync(), isTrue);
  });

  test('search_shapes resolves aliases', () async {
    final result =
        await callTool('search_shapes', <String, dynamic>{'query': 'database'});
    expect(firstText(result), contains('cylinder'));
  });

  test('tools/call on an unknown tool is a soft error', () async {
    final result = await callTool('nope', <String, dynamic>{});
    expect(result['isError'], isTrue);
  });

  test('create_diagram accepts a stringified spec', () async {
    final path = '${tmp.path}/str.vsdx';
    final result = await callTool('create_diagram',
        <String, dynamic>{'spec': jsonEncode(_spec), 'path': path});
    expect(result['isError'], isFalse);
    expect(File(path).existsSync(), isTrue);
  });

  group('convenience edit tools (file mode)', () {
    late String path;
    setUp(() async {
      path = '${tmp.path}/edit.vsdx';
      await callTool('create_diagram', <String, dynamic>{
        'spec': <String, dynamic>{
          'nodes': <dynamic>[
            <String, dynamic>{'id': 'a', 'text': 'A'},
            <String, dynamic>{'id': 'b', 'text': 'B'},
          ],
        },
        'path': path,
      });
    });

    List<VsdxShape> shapes() => const DocumentParser()
        .parse(File(path).readAsBytesSync())
        .pages
        .single
        .shapes;
    int idOf(String text) => shapes().firstWhere((s) => s.text == text).id;

    test('add_shape → set_text → delete_shape', () async {
      await callTool('add_shape', <String, dynamic>{
        'path': path,
        'stencil': 'process',
        'text': 'C',
        'x': 1.0,
        'y': 1.0,
      });
      expect(shapes().any((s) => s.text == 'C'), isTrue);
      final id = idOf('C');
      await callTool('set_text',
          <String, dynamic>{'path': path, 'id': id, 'text': 'C2'});
      expect(shapes().any((s) => s.text == 'C2'), isTrue);
      await callTool('delete_shape', <String, dynamic>{'path': path, 'id': id});
      expect(shapes().any((s) => s.id == id), isFalse);
    });

    test('set_style sets fill (by "shape:<id>")', () async {
      final id = idOf('A');
      await callTool('set_style', <String, dynamic>{
        'path': path,
        'ids': <dynamic>['shape:$id'],
        'fill': '#FF0000',
      });
      expect(shapes().firstWhere((s) => s.id == id).fill.foreground?.value,
          0xFFFF0000);
    });

    test('move_shape sets the centre', () async {
      final id = idOf('A');
      await callTool(
          'move_shape', <String, dynamic>{'path': path, 'id': id, 'x': 6.0, 'y': 5.0});
      final s = shapes().firstWhere((s) => s.id == id);
      expect(s.pinX, closeTo(6.0, 1e-6));
      expect(s.pinY, closeTo(5.0, 1e-6));
    });

    test('add_connector links two shapes', () async {
      final before = shapes().where((s) => s.is1D).length;
      await callTool('add_connector', <String, dynamic>{
        'path': path,
        'from': 'shape:${idOf('A')}',
        'to': 'shape:${idOf('B')}',
        'label': 'x',
      });
      expect(shapes().where((s) => s.is1D).length, before + 1);
    });

    test('list_shapes returns ids + text as JSON', () async {
      final result = await callTool('list_shapes', <String, dynamic>{'path': path});
      final text = firstText(result);
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      final list = decoded['shapes'] as List;
      final texts = list.map((s) => s['text']).toSet();
      expect(texts, containsAll(<String>['A', 'B']));
      expect(list.first.containsKey('id'), isTrue);
    });
  });
}
