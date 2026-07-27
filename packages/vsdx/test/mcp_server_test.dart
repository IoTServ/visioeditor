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
    final resp = await rpc(
        'tools/call', <String, dynamic>{'name': name, 'arguments': args});
    return resp['result'] as Map<String, dynamic>;
  }

  String firstText(Map<String, dynamic> result) =>
      (result['content'] as List).first['text'] as String;

  void writeTwoPageDocument(String path) {
    final original = const VsdxWriter().emptyDocument();
    var doc = const DocumentParser().parse(original);
    final first = doc.pages.first.copyWith(
      shapes: <VsdxShape>[
        withLabel(
          VsdxShapeFactory.rectangle(
            id: 1,
            pinX: 2,
            pinY: 2,
            width: 1,
            height: 1,
          ),
          'First page',
        ),
      ],
    );
    final second = VsdxPage(
      id: doc.nextPageId(),
      name: 'Page-2',
      widthInches: first.widthInches,
      heightInches: first.heightInches,
      shapes: <VsdxShape>[
        withLabel(
          VsdxShapeFactory.rectangle(
            id: 1,
            pinX: 4,
            pinY: 4,
            width: 1,
            height: 1,
          ),
          'Second page',
        ),
      ],
    );
    doc = doc.copyWith(pages: <VsdxPage>[first, second]);
    File(path).writeAsBytesSync(
      const VsdxWriter().write(originalBytes: original, edited: doc),
    );
  }

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
    final r = await server.handle(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'notifications/initialized'
    });
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
          'list_pages',
          'list_layers',
          'search_shapes',
          'list_styles',
          'add_layer',
          'set_layer',
          'delete_layer',
          'assign_layer',
          'set_shape_data',
          'set_shape_links',
          'add_page',
          'duplicate_page',
          'rename_page',
          'delete_page',
          'move_page',
          'set_page',
          'resize_shape',
          'duplicate_shapes',
          'group_shapes',
          'ungroup_shapes',
          'arrange_shape',
          'align_shapes',
          'distribute_shapes',
        ]));
    // Live tools excluded in this configuration.
    expect(names, isNot(contains('snapshot')));
    expect(names, isNot(contains('select')));
  });

  test('list_styles names the built-in presets', () async {
    final result = await callTool('list_styles', <String, dynamic>{});
    final text = firstText(result);
    expect(text, contains('default'));
    expect(text, contains('corporate'));
    expect(text, contains('dark'));
  });

  test('tools/list includes live select when enabled', () async {
    final live = McpServer(name: 'visioeditor', version: '0.1.0');
    registerVsdxMcpTools(live, includeLiveTools: true);
    final r = await live.handle(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/list',
    });
    final names = <String>[
      for (final t in (r!['result']['tools'] as List)) t['name'] as String,
    ];
    expect(
        names,
        containsAll(<String>[
          'select',
          'select_page',
          'select_layer',
          'open_in_app',
          'live_apply_ops',
          'snapshot',
          'get_app_state',
        ]));
    expect(names, hasLength(48));
  });

  test('create_diagram builds + validates a .vsdx', () async {
    final path = '${tmp.path}/flow.vsdx';
    final result = await callTool(
        'create_diagram', <String, dynamic>{'spec': _spec, 'path': path});
    expect(result['isError'], isFalse);
    expect(firstText(result), contains('validation: clean'));
    expect(File(path).existsSync(), isTrue);
  });

  test('apply_ops then explain reflects the edit', () async {
    final path = '${tmp.path}/flow.vsdx';
    await callTool(
        'create_diagram', <String, dynamic>{'spec': _spec, 'path': path});
    await callTool('apply_ops', <String, dynamic>{
      'path': path,
      'ops': <dynamic>[
        <String, dynamic>{
          'op': 'add_shape',
          'text': 'Cache',
          'x': 1.0,
          'y': 1.0
        },
      ],
    });
    final explained =
        await callTool('explain', <String, dynamic>{'path': path});
    expect(firstText(explained), contains('Cache'));
  });

  test('apply_ops page edits only the requested page', () async {
    final path = '${tmp.path}/pages.vsdx';
    writeTwoPageDocument(path);

    final result = await callTool('apply_ops', <String, dynamic>{
      'path': path,
      'page': 1,
      'ops': <dynamic>[
        <String, dynamic>{
          'op': 'set_text',
          'id': 1,
          'text': 'Edited second page',
        },
      ],
    });

    expect(firstText(result), contains('page 1'));
    final pages =
        const DocumentParser().parse(File(path).readAsBytesSync()).pages;
    expect(pages[0].findShapeById(1)!.text, 'First page');
    expect(pages[1].findShapeById(1)!.text, 'Edited second page');
  });

  test('rejected apply_ops neither rewrites nor claims to patch the file',
      () async {
    final path = '${tmp.path}/no-op.vsdx';
    await callTool(
        'create_diagram', <String, dynamic>{'spec': _spec, 'path': path});
    final file = File(path);
    final fixed = DateTime.utc(2001, 2, 3, 4, 5, 6);
    file.setLastModifiedSync(fixed);

    final result = await callTool('apply_ops', <String, dynamic>{
      'path': path,
      'ops': <dynamic>[
        <String, dynamic>{'op': 'delete_shape', 'id': 999999},
      ],
    });

    expect(firstText(result), startsWith('No changes to'));
    expect(firstText(result),
        contains('Skipped: delete_shape: shape 999999 not found'));
    expect(file.lastModifiedSync(), fixed.toLocal());
  });

  test('list_shapes reports the effective clamped page', () async {
    final path = '${tmp.path}/pages.vsdx';
    writeTwoPageDocument(path);

    final result = await callTool('list_shapes', <String, dynamic>{
      'path': path,
      'page': 99,
    });
    final decoded = jsonDecode(firstText(result)) as Map<String, dynamic>;

    expect(decoded['page'], 1);
    expect(
      (decoded['shapes'] as List).single['text'],
      'Second page',
    );
  });

  test('page convenience tools manage tabs and list page setup', () async {
    final path = '${tmp.path}/page-tools.vsdx';
    await callTool(
        'create_diagram', <String, dynamic>{'spec': _spec, 'path': path});

    final added = await callTool('add_page', <String, dynamic>{
      'path': path,
      'name': 'Ops',
      'width': 6,
      'height': 10,
      'background': '#ABCDEF',
    });
    expect(firstText(added), contains('Created page ids:'));
    await callTool('rename_page', <String, dynamic>{
      'path': path,
      'index': 1,
      'name': 'Canvas',
    });
    await callTool('set_page', <String, dynamic>{
      'path': path,
      'index': 1,
      'landscape': true,
    });
    await callTool('duplicate_page', <String, dynamic>{
      'path': path,
      'index': 1,
      'name': 'Copy',
    });
    await callTool('move_page', <String, dynamic>{
      'path': path,
      'from': 2,
      'to': 0,
    });
    await callTool('delete_page', <String, dynamic>{
      'path': path,
      'index': 1,
    });

    final listed =
        await callTool('list_pages', <String, dynamic>{'path': path});
    final decoded = jsonDecode(firstText(listed)) as Map<String, dynamic>;
    final pages = (decoded['pages'] as List).cast<Map<String, dynamic>>();
    expect(pages.map((page) => page['name']), <String>['Copy', 'Canvas']);
    expect(pages.first['width'], 10);
    expect(pages.first['height'], 6);
    expect(pages.first['background'], '#ABCDEF');
    expect(pages.map((page) => page['id']).toSet(), hasLength(2));
  });

  test('export writes SVG', () async {
    final path = '${tmp.path}/flow.vsdx';
    await callTool(
        'create_diagram', <String, dynamic>{'spec': _spec, 'path': path});
    final result = await callTool(
        'export', <String, dynamic>{'path': path, 'format': 'svg'});
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
      await callTool(
          'set_text', <String, dynamic>{'path': path, 'id': id, 'text': 'C2'});
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
      await callTool('move_shape',
          <String, dynamic>{'path': path, 'id': id, 'x': 6.0, 'y': 5.0});
      final s = shapes().firstWhere((s) => s.id == id);
      expect(s.pinX, closeTo(6.0, 1e-6));
      expect(s.pinY, closeTo(5.0, 1e-6));
    });

    test('resize_shape exposes the existing Edit Op as a convenience tool',
        () async {
      final id = idOf('A');
      await callTool('resize_shape', <String, dynamic>{
        'path': path,
        'id': id,
        'w': 2.5,
        'h': 1.25,
      });
      final s = shapes().firstWhere((shape) => shape.id == id);
      expect(s.width, closeTo(2.5, 1e-6));
      expect(s.height, closeTo(1.25, 1e-6));
    });

    test('structural convenience tools mirror draw.io arrange commands',
        () async {
      await callTool('add_shape', <String, dynamic>{
        'path': path,
        'stencil': 'process',
        'text': 'C',
        'x': 4.5,
        'y': 5.5,
      });
      final a = idOf('A');
      final b = idOf('B');
      final c = idOf('C');

      await callTool('align_shapes', <String, dynamic>{
        'path': path,
        'ids': <int>[a, b, c],
        'mode': 'middle',
      });
      final aligned = shapes();
      final centres = <double>[
        for (final id in <int>[a, b, c])
          aligned.firstWhere((s) => s.id == id).pinY,
      ];
      expect(centres[1], closeTo(centres[0], 1e-6));
      expect(centres[2], closeTo(centres[0], 1e-6));

      await callTool('distribute_shapes', <String, dynamic>{
        'path': path,
        'ids': <int>[a, b, c],
        'axis': 'horizontal',
      });
      final distributed = shapes()
          .where((s) => <int>{a, b, c}.contains(s.id))
          .toList()
        ..sort((x, y) => x.pinX.compareTo(y.pinX));
      final gap1 = distributed[1].pinX -
          distributed[1].width / 2 -
          (distributed[0].pinX + distributed[0].width / 2);
      final gap2 = distributed[2].pinX -
          distributed[2].width / 2 -
          (distributed[1].pinX + distributed[1].width / 2);
      expect(gap1, closeTo(gap2, 1e-6));

      final beforeDuplicate = shapes().length;
      await callTool('duplicate_shapes', <String, dynamic>{
        'path': path,
        'ids': <int>[a, b],
        'dx': 0.5,
        'dy': 0.5,
      });
      expect(shapes(), hasLength(beforeDuplicate + 2));

      await callTool('group_shapes', <String, dynamic>{
        'path': path,
        'ids': <int>[a, b],
        'name': 'AB',
      });
      final group =
          shapes().firstWhere((s) => s.shapeKind == VsdxShapeKind.group);
      expect(group.name, 'AB');
      expect(group.children.map((s) => s.id).toSet(), <int>{a, b});

      await callTool('ungroup_shapes', <String, dynamic>{
        'path': path,
        'ids': <int>[group.id],
      });
      expect(
        shapes().where((s) => s.shapeKind == VsdxShapeKind.group),
        isEmpty,
      );

      await callTool('arrange_shape', <String, dynamic>{
        'path': path,
        'id': a,
        'action': 'front',
      });
      expect(shapes().last.id, a);
    });

    test('layer convenience tools mirror draw.io layer controls', () async {
      final a = idOf('A');
      final b = idOf('B');

      final added = await callTool('add_layer', <String, dynamic>{
        'path': path,
        'name': 'Domain',
        'ids': <int>[a],
        'active': true,
        'color': '#336699',
      });
      expect(firstText(added), contains('Created layer ids: 0'));

      await callTool('assign_layer', <String, dynamic>{
        'path': path,
        'ids': <int>[b],
        'layerId': 0,
        'mode': 'add',
      });
      await callTool('set_layer', <String, dynamic>{
        'path': path,
        'layerId': 0,
        'name': 'Infrastructure',
        'visible': false,
        'print': false,
        'locked': true,
      });

      final listed =
          await callTool('list_layers', <String, dynamic>{'path': path});
      final decoded = jsonDecode(firstText(listed)) as Map<String, dynamic>;
      final layers = decoded['layers'] as List;
      expect(layers, hasLength(1));
      expect(layers.single['name'], 'Infrastructure');
      expect(layers.single['visible'], isFalse);
      expect(layers.single['print'], isFalse);
      expect(layers.single['locked'], isTrue);
      expect(layers.single['shapeIds'], containsAll(<int>[a, b]));

      final listedShapes =
          await callTool('list_shapes', <String, dynamic>{'path': path});
      final shapeJson = (jsonDecode(firstText(listedShapes))
          as Map<String, dynamic>)['shapes'] as List;
      expect(
        shapeJson.firstWhere((shape) => shape['id'] == a)['layerIds'],
        <int>[0],
      );

      await callTool('delete_layer', <String, dynamic>{
        'path': path,
        'layerId': 0,
      });
      final reopened =
          const DocumentParser().parse(File(path).readAsBytesSync());
      expect(reopened.pages.single.layers, isEmpty);
      expect(reopened.pages.single.findShapeById(a)!.layerMemberIds, isEmpty);
      expect(reopened.pages.single.findShapeById(b)!.layerMemberIds, isEmpty);
    });

    test('metadata convenience tools mirror draw.io Edit Data and Edit Link',
        () async {
      final a = idOf('A');

      await callTool('set_shape_data', <String, dynamic>{
        'path': path,
        'id': '$a',
        'properties': <dynamic>[
          <String, dynamic>{
            'name': 'Owner',
            'label': 'Service owner',
            'value': 'Platform',
          },
          <String, dynamic>{
            'name': 'Cost',
            'value': 42,
            'type': 2,
          },
        ],
      });
      await callTool('set_shape_links', <String, dynamic>{
        'path': path,
        'id': '$a',
        'links': <dynamic>[
          <String, dynamic>{
            'description': 'Docs',
            'address': 'https://example.com/docs',
            'newWindow': true,
          },
          <String, dynamic>{
            'description': 'Page',
            'subAddress': '#Page-1',
          },
        ],
      });

      final listed =
          await callTool('list_shapes', <String, dynamic>{'path': path});
      final decoded = jsonDecode(firstText(listed)) as Map<String, dynamic>;
      final shape =
          (decoded['shapes'] as List).firstWhere((entry) => entry['id'] == a);
      expect((shape['data'] as List).first['name'], 'Owner');
      expect((shape['data'] as List).last['value'], '42');
      expect(
          (shape['links'] as List).first['target'], 'https://example.com/docs');
      expect((shape['links'] as List).first['default'], isTrue);
      expect((shape['links'] as List).last['target'], '#Page-1');

      final reopened =
          const DocumentParser().parse(File(path).readAsBytesSync());
      final persisted = reopened.pages.single.findShapeById(a)!;
      expect(persisted.userProperties, hasLength(2));
      expect(persisted.hyperlinks, hasLength(2));
      expect(persisted.primaryHyperlink?.description, 'Docs');
    });

    test('convenience tools accept a page index', () async {
      writeTwoPageDocument(path);
      await callTool('move_shape', <String, dynamic>{
        'path': path,
        'page': 1,
        'id': 1,
        'x': 7.0,
        'y': 6.0,
      });
      final pages =
          const DocumentParser().parse(File(path).readAsBytesSync()).pages;
      expect(pages[0].findShapeById(1)!.pinX, closeTo(2.0, 1e-6));
      expect(pages[1].findShapeById(1)!.pinX, closeTo(7.0, 1e-6));
      expect(pages[1].findShapeById(1)!.pinY, closeTo(6.0, 1e-6));
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
      final result =
          await callTool('list_shapes', <String, dynamic>{'path': path});
      final text = firstText(result);
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      final list = decoded['shapes'] as List;
      final texts = list.map((s) => s['text']).toSet();
      expect(texts, containsAll(<String>['A', 'B']));
      expect(list.first.containsKey('id'), isTrue);
    });
  });
}
