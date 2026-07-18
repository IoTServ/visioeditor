import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vsdx/agent.dart';

/// Exercises the newline-delimited JSON-RPC [McpServer.serve] loop end-to-end
/// (framing + notification handling + real tool execution) using in-memory
/// streams and a file-backed sink — the same path the stdio server runs.
void main() {
  test('serve() runs a full initialize → tools/list → tools/call session',
      () async {
    final tmp = Directory.systemTemp.createTempSync('mcp_stdio');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final diagramPath = '${tmp.path}/d.vsdx';

    final requests = <String>[
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': <String, dynamic>{
          'protocolVersion': '2024-11-05',
          'capabilities': <String, dynamic>{},
        },
      }),
      // A notification (no id) must NOT get a response.
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      }),
      jsonEncode(<String, dynamic>{'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'}),
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': <String, dynamic>{
          'name': 'create_diagram',
          'arguments': <String, dynamic>{
            'spec': <String, dynamic>{
              'title': 'T',
              'nodes': <dynamic>[
                <String, dynamic>{'id': 'a', 'text': 'A'},
                <String, dynamic>{'id': 'b', 'text': 'B'},
              ],
              'edges': <dynamic>[
                <String, dynamic>{'from': 'a', 'to': 'b'},
              ],
            },
            'path': diagramPath,
          },
        },
      }),
    ];

    final server = McpServer(name: 'visioeditor', version: '0.1.0');
    registerVsdxMcpTools(server, includeLiveTools: false);

    final outFile = File('${tmp.path}/out.ndjson');
    final sink = outFile.openWrite();
    await server.serve(input: Stream<String>.fromIterable(requests), output: sink);
    await sink.flush();
    await sink.close();

    final lines = outFile
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty)
        .map((l) => (jsonDecode(l) as Map).cast<String, dynamic>())
        .toList();

    // 3 requests with ids produced 3 responses; the notification produced none.
    expect(lines, hasLength(3));
    final byId = <Object?, Map<String, dynamic>>{for (final l in lines) l['id']: l};
    expect(byId[1]!['result']['serverInfo']['name'], 'visioeditor');
    expect((byId[2]!['result']['tools'] as List), isNotEmpty);
    expect(byId[3]!['result']['isError'], isFalse);
    expect(File(diagramPath).existsSync(), isTrue);
  });

  test('malformed frames are ignored, valid ones still answered', () async {
    final server = McpServer(name: 'visioeditor', version: '0.1.0');
    registerVsdxMcpTools(server, includeLiveTools: false);
    final tmp = Directory.systemTemp.createTempSync('mcp_stdio2');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final outFile = File('${tmp.path}/o.ndjson');
    final sink = outFile.openWrite();
    await server.serve(
      input: Stream<String>.fromIterable(<String>[
        'not json',
        '',
        jsonEncode(<String, dynamic>{'jsonrpc': '2.0', 'id': 9, 'method': 'ping'}),
      ]),
      output: sink,
    );
    await sink.flush();
    await sink.close();
    final lines =
        outFile.readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
    expect(lines, hasLength(1));
    expect((jsonDecode(lines.first) as Map)['id'], 9);
  });
}
