import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vsdx/agent.dart';

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
}
