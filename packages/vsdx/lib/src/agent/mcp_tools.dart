/// Registers the visioeditor Agent toolset on an [McpServer].
///
/// **File tools** (no app needed): `create_diagram`, `apply_ops`, `export`,
/// `validate`, `explain`, `list_pages`, `list_layers`, `list_shapes`,
/// `search_shapes`, `list_styles`, plus page/layer/shape/metadata convenience
/// edits.
/// **Live tools** (drive the running editor via the bridge): `open_in_app`,
/// `live_apply_ops`, `select_page`, `select_layer`, `select`, `snapshot`,
/// `get_app_state`.
///
/// Split out from the `bin/` entry so it can be unit-tested. See
/// `docs/MCP_SKILL_PLAN.md` (M3).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:vsdx/vsdx.dart';

import 'bridge_client.dart';
import 'code_import.dart';
import 'diagram_spec.dart';
import 'edit_ops.dart';
import 'iac_import.dart';
import 'inspect.dart';
import 'mcp_server.dart';
import 'mermaid_export.dart';
import 'mermaid_import.dart';
import 'openapi_import.dart';
import 'sql_import.dart';
import 'stencil_catalog.dart';
import 'style_presets.dart';

/// Register every Agent tool on [server]. Set [includeLiveTools] to `false`
/// (e.g. in tests) to skip the bridge-backed tools.
void registerVsdxMcpTools(McpServer server, {bool includeLiveTools = true}) {
  _registerFileTools(server);
  _registerEditTools(server);
  if (includeLiveTools) _registerLiveTools(server);
}

Uint8List _read(String path) =>
    Uint8List.fromList(File(path).readAsBytesSync());

String _abs(String path) => File(path).absolute.path;

Map<String, dynamic> _asMap(Object? v) {
  if (v is Map) return v.cast<String, dynamic>();
  if (v is String) return (jsonDecode(v) as Map).cast<String, dynamic>();
  throw ArgumentError('expected a JSON object or string');
}

List<dynamic> _asList(Object? v) {
  if (v is List) return v;
  if (v is Map && v['ops'] is List) return v['ops'] as List;
  if (v is String) {
    final decoded = jsonDecode(v);
    if (decoded is List) return decoded;
    if (decoded is Map && decoded['ops'] is List) return decoded['ops'] as List;
  }
  throw ArgumentError('expected a JSON array of ops');
}

String _validationSummary(Uint8List bytes) {
  final doc = const DocumentParser().parse(bytes);
  final issues = validateDocument(doc);
  if (issues.isEmpty) return 'validation: clean';
  final errors = issues.where((i) => i.severity == 'error').length;
  return 'validation: $errors error(s), ${issues.length - errors} warning(s)\n'
      '${issues.take(10).map((i) => '  $i').join('\n')}';
}

void _registerFileTools(McpServer server) {
  server.addTool(McpTool(
    name: 'create_diagram',
    description:
        'Build a .vsdx from a Diagram Spec (nodes + edges; layered auto-layout '
        'when coordinates are omitted). Optional style preset (default/'
        'corporate/dark) fills colours from node roles. Set open=true to also '
        'open it in the running editor for live preview.',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'spec': <String, dynamic>{
          'type': 'object',
          'description':
              'Diagram Spec v0: {title?, style?, layout?:{direction,spacing}, '
                  'page?, nodes:[{id,stencil,text,role?,x?,y?,w?,h?,fill?,line?,'
                  'bold?}], edges:[{from,to,label?,arrow?,line?}]}',
        },
        'style': <String, dynamic>{
          'type': 'string',
          'enum': <String>['default', 'corporate', 'dark'],
          'description':
              'Style preset (overrides spec.style). Use list_styles to discover.',
        },
        'path': <String, dynamic>{
          'type': 'string',
          'description': 'Output .vsdx path (default: ./<title>.vsdx).',
        },
        'open': <String, dynamic>{
          'type': 'boolean',
          'description': 'Open in the running editor after building.',
        },
      },
      'required': <String>['spec'],
    },
    handler: (args) async {
      final raw = _asMap(args['spec']);
      if (args['style'] != null) raw['style'] = args['style'];
      final spec = DiagramSpec.fromJson(raw);
      final bytes = spec.build();
      final path = (args['path'] as String?) ??
          '${(spec.title ?? 'diagram').replaceAll(RegExp(r'[^\w.-]+'), '_')}.vsdx';
      File(path).writeAsBytesSync(bytes);
      final out = StringBuffer()
        ..writeln('Built ${_abs(path)}')
        ..writeln('${spec.nodes.length} nodes, ${spec.edges.length} edges, '
            '${bytes.length} bytes')
        ..writeln(_validationSummary(bytes));
      if (args['open'] == true) {
        try {
          final client = await BridgeClient.connect();
          await client.call('open', <String, dynamic>{'path': _abs(path)});
          await client.close();
          out.writeln('Opened in the running editor (live preview).');
        } catch (e) {
          out.writeln('Note: could not open in app ($e).');
        }
      }
      return <McpContent>[McpContent.text(out.toString().trimRight())];
    },
  ));

  server.addTool(McpTool(
    name: 'import_mermaid',
    description:
        'Convert a Mermaid flowchart/graph to an editable .vsdx. Set open=true '
        'to also open it in the running editor.',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'text': <String, dynamic>{
          'type': 'string',
          'description': 'Mermaid source.'
        },
        'path': <String, dynamic>{'type': 'string'},
        'open': <String, dynamic>{'type': 'boolean'},
      },
      'required': <String>['text', 'path'],
    },
    handler: (args) async {
      final spec = mermaidToSpec('${args['text']}');
      final bytes = spec.build();
      final path = args['path'] as String;
      File(path).writeAsBytesSync(bytes);
      final out = StringBuffer()
        ..writeln('Imported ${_abs(path)}')
        ..writeln('${spec.nodes.length} nodes, ${spec.edges.length} edges')
        ..writeln(_validationSummary(bytes));
      if (args['open'] == true) {
        try {
          final client = await BridgeClient.connect();
          await client.call('open', <String, dynamic>{'path': _abs(path)});
          await client.close();
          out.writeln('Opened in the running editor (live preview).');
        } catch (e) {
          out.writeln('Note: could not open in app ($e).');
        }
      }
      return <McpContent>[McpContent.text(out.toString().trimRight())];
    },
  ));

  server.addTool(McpTool(
    name: 'import_code',
    description: 'Visualize a codebase import graph '
        '(Dart / Python / JS-TS / Go / Rust) as an editable .vsdx '
        '(one box per module/package, edges = imports). '
        'Set open=true to open it in the running editor.',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'dir': <String, dynamic>{
          'type': 'string',
          'description': 'Project root to scan.',
        },
        'language': <String, dynamic>{
          'type': 'string',
          'enum': <String>['dart', 'python', 'js', 'go', 'rust'],
          'description': 'Auto-detected if omitted.',
        },
        'path': <String, dynamic>{'type': 'string'},
        'max': <String, dynamic>{'type': 'integer', 'default': 300},
        'open': <String, dynamic>{'type': 'boolean'},
      },
      'required': <String>['dir', 'path'],
    },
    handler: (args) async {
      final spec = codeToSpec(
        args['dir'] as String,
        language: args['language'] as String?,
        maxFiles: (args['max'] as num?)?.toInt() ?? 300,
      );
      final bytes = spec.build();
      final path = args['path'] as String;
      File(path).writeAsBytesSync(bytes);
      final out = StringBuffer()
        ..writeln('Imported ${_abs(path)}')
        ..writeln('${spec.nodes.length} modules, ${spec.edges.length} imports')
        ..writeln(_validationSummary(bytes));
      if (args['open'] == true) {
        try {
          final client = await BridgeClient.connect();
          await client.call('open', <String, dynamic>{'path': _abs(path)});
          await client.close();
          out.writeln('Opened in the running editor (live preview).');
        } catch (e) {
          out.writeln('Note: could not open in app ($e).');
        }
      }
      return <McpContent>[McpContent.text(out.toString().trimRight())];
    },
  ));

  server.addTool(McpTool(
    name: 'import_iac',
    description: 'Convert docker-compose / Kubernetes YAML / Terraform HCL to '
        'an architecture diagram .vsdx (auto-detected; services/workloads/'
        'resources + dependency edges, '
        'volumes/PVCs, Service/Ingress links). Set open=true to open it.',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'yaml': <String, dynamic>{
          'type': 'string',
          'description':
              'docker-compose / Kubernetes YAML, or Terraform (.tf) HCL source.',
        },
        'path': <String, dynamic>{'type': 'string'},
        'open': <String, dynamic>{'type': 'boolean'},
      },
      'required': <String>['yaml', 'path'],
    },
    handler: (args) async {
      final spec = iacToSpec('${args['yaml']}');
      final bytes = spec.build();
      final path = args['path'] as String;
      File(path).writeAsBytesSync(bytes);
      final out = StringBuffer()
        ..writeln('Imported ${_abs(path)}')
        ..writeln('${spec.nodes.length} resources, ${spec.edges.length} links')
        ..writeln(_validationSummary(bytes));
      if (args['open'] == true) {
        try {
          final client = await BridgeClient.connect();
          await client.call('open', <String, dynamic>{'path': _abs(path)});
          await client.close();
          out.writeln('Opened in the running editor (live preview).');
        } catch (e) {
          out.writeln('Note: could not open in app ($e).');
        }
      }
      return <McpContent>[McpContent.text(out.toString().trimRight())];
    },
  ));

  server.addTool(McpTool(
    name: 'import_openapi',
    description: 'Convert an OpenAPI 3 / Swagger 2 spec (JSON or YAML) to an '
        'editable API diagram .vsdx (operations coloured by HTTP method + '
        r'schema nodes + $ref edges). Set open=true to open it in the editor.',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'spec': <String, dynamic>{
          'type': 'string',
          'description': 'OpenAPI/Swagger source (JSON or YAML).',
        },
        'path': <String, dynamic>{'type': 'string'},
        'open': <String, dynamic>{'type': 'boolean'},
      },
      'required': <String>['spec', 'path'],
    },
    handler: (args) async {
      final spec = openapiToSpec('${args['spec']}');
      final bytes = spec.build();
      final path = args['path'] as String;
      File(path).writeAsBytesSync(bytes);
      final out = StringBuffer()
        ..writeln('Imported ${_abs(path)}')
        ..writeln('${spec.nodes.length} nodes, ${spec.edges.length} refs')
        ..writeln(_validationSummary(bytes));
      if (args['open'] == true) {
        try {
          final client = await BridgeClient.connect();
          await client.call('open', <String, dynamic>{'path': _abs(path)});
          await client.close();
          out.writeln('Opened in the running editor (live preview).');
        } catch (e) {
          out.writeln('Note: could not open in app ($e).');
        }
      }
      return <McpContent>[McpContent.text(out.toString().trimRight())];
    },
  ));

  server.addTool(McpTool(
    name: 'import_sql',
    description: 'Convert SQL DDL (CREATE TABLE …) to an editable ER diagram '
        '.vsdx (tables + PK/FK, foreign-key edges). Set open=true to open it '
        'in the running editor.',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'sql': <String, dynamic>{
          'type': 'string',
          'description': 'SQL DDL text.'
        },
        'path': <String, dynamic>{'type': 'string'},
        'open': <String, dynamic>{'type': 'boolean'},
      },
      'required': <String>['sql', 'path'],
    },
    handler: (args) async {
      final spec = sqlToSpec('${args['sql']}');
      final bytes = spec.build();
      final path = args['path'] as String;
      File(path).writeAsBytesSync(bytes);
      final out = StringBuffer()
        ..writeln('Imported ${_abs(path)}')
        ..writeln('${spec.nodes.length} tables, ${spec.edges.length} FKs')
        ..writeln(_validationSummary(bytes));
      if (args['open'] == true) {
        try {
          final client = await BridgeClient.connect();
          await client.call('open', <String, dynamic>{'path': _abs(path)});
          await client.close();
          out.writeln('Opened in the running editor (live preview).');
        } catch (e) {
          out.writeln('Note: could not open in app ($e).');
        }
      }
      return <McpContent>[McpContent.text(out.toString().trimRight())];
    },
  ));

  server.addTool(McpTool(
    name: 'apply_ops',
    description:
        'Apply Edit Ops to an existing .vsdx (round-trip faithful). Ops: '
        'add/duplicate/rename/delete/move/set page; add/set/delete/assign '
        'layer; add/configure/reconnect connector; style/text/data/links/'
        'connection-points/move/resize/duplicate/reparent/group/ungroup/'
        'collapse/z-order/align/distribute/delete shape.',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'path': <String, dynamic>{'type': 'string'},
        'ops': <String, dynamic>{
          'type': 'array',
          'description': 'Array of Edit Op objects.',
        },
        'page': <String, dynamic>{
          'type': 'integer',
          'default': 0,
          'description': 'Zero-based page index.',
        },
      },
      'required': <String>['path', 'ops'],
    },
    handler: (args) async {
      final path = args['path'] as String;
      final ops = _asList(args['ops']);
      final page = (args['page'] as num?)?.toInt() ?? 0;
      final original = _read(path);
      final applied = applyOpsBytesResult(
        original,
        jsonEncode(<String, dynamic>{'ops': ops}),
        pageIndex: page,
      );
      if (applied.changed) File(path).writeAsBytesSync(applied.bytes);
      return <McpContent>[
        McpContent.text(
            '${applied.changed ? 'Patched' : 'No changes to'} ${_abs(path)} '
            '(page ${applied.pageIndex}, ${applied.bytes.length} bytes)\n'
            '${_validationSummary(applied.bytes)}'
            '${applied.createdPageIds.isEmpty ? '' : '\nCreated page ids: ${applied.createdPageIds.join(', ')}'}'
            '${applied.createdLayerIds.isEmpty ? '' : '\nCreated layer ids: ${applied.createdLayerIds.join(', ')}'}'
            '${applied.log.isEmpty ? '' : '\nSkipped: ${applied.log.join('; ')}'}'),
      ];
    },
  ));

  server.addTool(McpTool(
    name: 'export',
    description: 'Export a .vsdx to SVG. (PNG: use snapshot with the app, or '
        "the editor's Export menu.)",
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'path': <String, dynamic>{'type': 'string'},
        'format': <String, dynamic>{
          'type': 'string',
          'enum': <String>['svg'],
          'default': 'svg',
        },
        'out': <String, dynamic>{'type': 'string'},
      },
      'required': <String>['path'],
    },
    handler: (args) async {
      final path = args['path'] as String;
      final format = (args['format'] as String?) ?? 'svg';
      if (format != 'svg') {
        throw ArgumentError('only svg is supported headlessly; '
            'use snapshot (app) or the editor Export menu for png/pdf');
      }
      final doc = const DocumentParser().parse(_read(path));
      // Match editor Export SVG: print layers only (skip non-printable).
      final svg = VsdxToSvgSerializer(layerFilter: SvgLayerFilter.print)
          .serializeDocument(doc);
      final out = (args['out'] as String?) ??
          path.replaceAll(RegExp(r'\.vsdx$', caseSensitive: false), '.svg');
      File(out).writeAsStringSync(svg);
      return <McpContent>[
        McpContent.text('Wrote ${_abs(out)} (${svg.length} bytes)'),
      ];
    },
  ));

  server.addTool(McpTool(
    name: 'validate',
    description: 'Structural lint of a .vsdx (duplicate ids, dangling '
        'connectors, off-page shapes, overlaps).',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'path': <String, dynamic>{'type': 'string'},
      },
      'required': <String>['path'],
    },
    handler: (args) async => <McpContent>[
      McpContent.text(_validationSummary(_read(args['path'] as String))),
    ],
  ));

  server.addTool(McpTool(
    name: 'explain',
    description: 'Describe a .vsdx as structured Markdown (shapes + '
        'connections per page).',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'path': <String, dynamic>{'type': 'string'},
      },
      'required': <String>['path'],
    },
    handler: (args) async {
      final doc = const DocumentParser().parse(_read(args['path'] as String));
      return <McpContent>[McpContent.text(explainDocument(doc))];
    },
  ));

  server.addTool(McpTool(
    name: 'to_mermaid',
    description: 'Convert a .vsdx to a Mermaid flowchart (structural — nodes + '
        'edges + labels). Good for embedding a diagram in Markdown.',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'path': <String, dynamic>{'type': 'string'},
        'fenced': <String, dynamic>{
          'type': 'boolean',
          'description': 'Wrap in a ```mermaid fence.',
        },
      },
      'required': <String>['path'],
    },
    handler: (args) async {
      final doc = const DocumentParser().parse(_read(args['path'] as String));
      final mmd = documentToMermaid(doc, fenced: args['fenced'] == true);
      return <McpContent>[McpContent.text(mmd)];
    },
  ));

  server.addTool(McpTool(
    name: 'list_pages',
    description: 'List page tabs and page setup as JSON (stable id, current '
        'index/name, size, shape count, background settings). Give `path` for '
        'a file; omit to read the running app.',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'path': <String, dynamic>{'type': 'string'},
      },
    },
    handler: (args) async {
      const enc = JsonEncoder.withIndent('  ');
      final path = args['path'] as String?;
      if (path != null) {
        final doc = const DocumentParser().parse(_read(path));
        return <McpContent>[
          McpContent.text(enc.convert(<String, dynamic>{
            'currentPage': 0,
            'pages': listPages(doc),
          })),
        ];
      }
      final client = await BridgeClient.connect();
      try {
        final state = await client.call('getState');
        return <McpContent>[
          McpContent.text(enc.convert(<String, dynamic>{
            'currentPage': state['currentPage'],
            'pages': state['pages'],
          })),
        ];
      } finally {
        await client.close();
      }
    },
  ));

  server.addTool(McpTool(
    name: 'list_layers',
    description: 'List a page\'s layers as JSON (stable id, name, visibility, '
        'lock/print flags, color, and assigned shape ids). Give `path` for a '
        'file; omit to read the running app.',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'path': <String, dynamic>{'type': 'string'},
        'page': <String, dynamic>{'type': 'integer', 'default': 0},
      },
    },
    handler: (args) async {
      const enc = JsonEncoder.withIndent('  ');
      final path = args['path'] as String?;
      if (path != null) {
        final doc = const DocumentParser().parse(_read(path));
        final requested = (args['page'] as num?)?.toInt() ?? 0;
        final page =
            doc.pages.isEmpty ? 0 : requested.clamp(0, doc.pages.length - 1);
        return <McpContent>[
          McpContent.text(enc.convert(<String, dynamic>{
            'page': page,
            'layers': listLayers(doc, pageIndex: page),
          })),
        ];
      }
      final client = await BridgeClient.connect();
      try {
        final result = await client.call('listLayers', <String, dynamic>{
          if (args['page'] != null) 'page': args['page'],
        });
        return <McpContent>[McpContent.text(enc.convert(result))];
      } finally {
        await client.close();
      }
    },
  ));

  server.addTool(McpTool(
    name: 'list_shapes',
    description: 'List a page\'s shapes as JSON (id, text, connector, x/y/w/h, '
        'parent/container/collapse state, layers, Shape Data, hyperlinks, '
        'connection points, and connector routing). Use it to find ids and '
        'metadata before editing. Give `path` for a file; omit to read the '
        'running app.',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'path': <String, dynamic>{'type': 'string'},
        'page': <String, dynamic>{'type': 'integer', 'default': 0},
      },
    },
    handler: (args) async {
      const enc = JsonEncoder.withIndent('  ');
      final path = args['path'] as String?;
      if (path != null) {
        final doc = const DocumentParser().parse(_read(path));
        final requested = (args['page'] as num?)?.toInt() ?? 0;
        final page =
            doc.pages.isEmpty ? 0 : requested.clamp(0, doc.pages.length - 1);
        return <McpContent>[
          McpContent.text(enc.convert(<String, dynamic>{
            'page': page,
            'shapes': listShapes(doc, pageIndex: page),
          })),
        ];
      }
      final client = await BridgeClient.connect();
      try {
        final res = await client.call('listShapes', <String, dynamic>{
          if (args['page'] != null) 'page': args['page'],
        });
        return <McpContent>[McpContent.text(enc.convert(res))];
      } finally {
        await client.close();
      }
    },
  ));

  server.addTool(McpTool(
    name: 'search_shapes',
    description: 'Search the stencil catalog for a shape name to use as a '
        'node "stencil" (e.g. "database" -> cylinder).',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'query': <String, dynamic>{'type': 'string'},
        'limit': <String, dynamic>{'type': 'integer', 'default': 10},
      },
      'required': <String>['query'],
    },
    handler: (args) async {
      final hits = searchStencils('${args['query']}',
          limit: (args['limit'] as num?)?.toInt() ?? 10);
      final text = hits.isEmpty
          ? 'no matches'
          : hits
              .map((e) => '${e.name}  [${e.group}]'
                  '${e.aliases.isEmpty ? '' : '  (aka ${e.aliases.join(', ')})'}')
              .join('\n');
      return <McpContent>[McpContent.text(text)];
    },
  ));

  server.addTool(McpTool(
    name: 'list_styles',
    description:
        'List Diagram Spec style presets (default / corporate / dark). '
        'Use with create_diagram({ style }) or put "style" / node "role" in the '
        'spec (roles: service, database, queue, gateway, error, external, '
        'security).',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{},
    },
    handler: (args) async {
      final lines = <String>[
        for (final name in listStylePresets())
          () {
            final p = stylePreset(name)!;
            final primary = p.palette['primary']!;
            return '$name  primary=${primary.fill}/${primary.stroke}'
                '${p.background == null ? '' : '  bg=${p.background}'}';
          }(),
      ];
      return <McpContent>[McpContent.text(lines.join('\n'))];
    },
  ));
}

/// One-shape convenience edits. Each routes to a **file** when `path` is given,
/// else to the **running app** (via the bridge) — same underlying Edit Op.
void _registerEditTools(McpServer server) {
  Map<String, dynamic> op(
      String name, Map<String, dynamic> args, List<String> keys) {
    return <String, dynamic>{
      'op': name,
      for (final k in keys)
        if (args.containsKey(k)) k: args[k],
    };
  }

  Future<List<McpContent>> applyOne(
      Map<String, dynamic> args, Map<String, dynamic> single) async {
    final path = args['path'] as String?;
    final page = (args['page'] as num?)?.toInt();
    if (path != null) {
      final original = _read(path);
      final pageIndex = page ?? 0;
      final applied = applyOpsBytesResult(
        original,
        jsonEncode(<String, dynamic>{
          'ops': <dynamic>[single]
        }),
        pageIndex: pageIndex,
      );
      if (applied.changed) File(path).writeAsBytesSync(applied.bytes);
      return <McpContent>[
        McpContent.text(
          '${applied.changed ? 'Applied to' : 'No changes to'} ${_abs(path)} '
          '(page ${applied.pageIndex})\n${_validationSummary(applied.bytes)}'
          '${applied.createdPageIds.isEmpty ? '' : '\nCreated page ids: ${applied.createdPageIds.join(', ')}'}'
          '${applied.createdLayerIds.isEmpty ? '' : '\nCreated layer ids: ${applied.createdLayerIds.join(', ')}'}'
          '${applied.log.isEmpty ? '' : '\nSkipped: ${applied.log.join('; ')}'}',
        ),
      ];
    }
    final client = await BridgeClient.connect();
    try {
      final state = await client.call('applyOps', <String, dynamic>{
        'ops': <dynamic>[single],
        if (page != null) 'page': page,
      });
      return <McpContent>[
        McpContent.text('Applied live. ${jsonEncode(state)}')
      ];
    } finally {
      await client.close();
    }
  }

  // Shared: an optional file path; omit to edit the running app's active doc.
  Map<String, dynamic> withPath(Map<String, dynamic> props) =>
      <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'path': <String, dynamic>{
            'type': 'string',
            'description': 'Target .vsdx file; omit to edit the running app.',
          },
          'page': <String, dynamic>{
            'type': 'integer',
            'description':
                'Zero-based page index (default: page 0 for files, current page live).',
          },
          ...props,
        },
      };

  server.addTool(McpTool(
    name: 'add_layer',
    description: 'Add a layer on a page, optionally assigning existing '
        'editable shapes to it.',
    inputSchema: withPath(<String, dynamic>{
      'name': <String, dynamic>{'type': 'string'},
      'ids': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{},
      },
      'visible': <String, dynamic>{'type': 'boolean'},
      'locked': <String, dynamic>{'type': 'boolean'},
      'print': <String, dynamic>{'type': 'boolean'},
      'active': <String, dynamic>{'type': 'boolean'},
      'snap': <String, dynamic>{'type': 'boolean'},
      'glue': <String, dynamic>{'type': 'boolean'},
      'color': <String, dynamic>{'type': 'string'},
      'colorTransparency': <String, dynamic>{'type': 'number'},
      'nameUniv': <String, dynamic>{'type': 'string'},
      'status': <String, dynamic>{'type': 'integer'},
    }),
    handler: (args) => applyOne(
      args,
      op('add_layer', args, <String>[
        'name',
        'ids',
        'visible',
        'locked',
        'print',
        'active',
        'snap',
        'glue',
        'color',
        'colorTransparency',
        'nameUniv',
        'status',
      ]),
    ),
  ));

  server.addTool(McpTool(
    name: 'set_layer',
    description: 'Rename or update visibility, lock, print, snap/glue, color '
        'and other properties of a layer.',
    inputSchema: withPath(<String, dynamic>{
      'layerId': <String, dynamic>{'type': 'integer'},
      'name': <String, dynamic>{'type': 'string'},
      'visible': <String, dynamic>{'type': 'boolean'},
      'locked': <String, dynamic>{'type': 'boolean'},
      'print': <String, dynamic>{'type': 'boolean'},
      'active': <String, dynamic>{'type': 'boolean'},
      'snap': <String, dynamic>{'type': 'boolean'},
      'glue': <String, dynamic>{'type': 'boolean'},
      'color': <String, dynamic>{
        'type': 'string',
        'description': '#RRGGBB or none.',
      },
      'colorTransparency': <String, dynamic>{'type': 'number'},
      'nameUniv': <String, dynamic>{'type': 'string'},
      'status': <String, dynamic>{'type': 'integer'},
    })
      ..['required'] = <String>['layerId'],
    handler: (args) => applyOne(
      args,
      op('set_layer', args, <String>[
        'layerId',
        'name',
        'visible',
        'locked',
        'print',
        'active',
        'snap',
        'glue',
        'color',
        'colorTransparency',
        'nameUniv',
        'status',
      ]),
    ),
  ));

  server.addTool(McpTool(
    name: 'delete_layer',
    description: 'Delete a layer and remove its id from every shape '
        'membership without deleting the shapes.',
    inputSchema: withPath(<String, dynamic>{
      'layerId': <String, dynamic>{'type': 'integer'},
    })
      ..['required'] = <String>['layerId'],
    handler: (args) =>
        applyOne(args, op('delete_layer', args, <String>['layerId'])),
  ));

  server.addTool(McpTool(
    name: 'assign_layer',
    description: 'Replace, add, remove, or clear layer membership for shapes. '
        'Locked shapes and locked-layer shapes are skipped.',
    inputSchema: withPath(<String, dynamic>{
      'ids': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{},
      },
      'layerId': <String, dynamic>{'type': 'integer'},
      'mode': <String, dynamic>{
        'type': 'string',
        'enum': <String>['replace', 'add', 'remove', 'clear'],
        'default': 'replace',
      },
    })
      ..['required'] = <String>['ids'],
    handler: (args) => applyOne(
      args,
      op('assign_layer', args, <String>['ids', 'layerId', 'mode']),
    ),
  ));

  server.addTool(McpTool(
    name: 'add_page',
    description: 'Add a blank page tab and make it the batch/live context. '
        'Defaults to immediately after the current page and copies its size.',
    inputSchema: withPath(<String, dynamic>{
      'index': <String, dynamic>{
        'type': 'integer',
        'description': 'Insertion index (default: after current page).',
      },
      'name': <String, dynamic>{'type': 'string'},
      'width': <String, dynamic>{'type': 'number'},
      'height': <String, dynamic>{'type': 'number'},
      'background': <String, dynamic>{
        'type': 'string',
        'description': 'Page color (#RRGGBB) or none.',
      },
      'isBackground': <String, dynamic>{'type': 'boolean'},
    }),
    handler: (args) => applyOne(
      args,
      op('add_page', args, <String>[
        'index',
        'name',
        'width',
        'height',
        'background',
        'isBackground',
      ]),
    ),
  ));

  server.addTool(McpTool(
    name: 'duplicate_page',
    description: 'Duplicate a page tab with a fresh stable page id and switch '
        'the batch/live context to the copy.',
    inputSchema: withPath(<String, dynamic>{
      'index': <String, dynamic>{
        'type': 'integer',
        'description': 'Page to copy (default: current context).',
      },
      'name': <String, dynamic>{'type': 'string'},
    }),
    handler: (args) =>
        applyOne(args, op('duplicate_page', args, <String>['index', 'name'])),
  ));

  server.addTool(McpTool(
    name: 'rename_page',
    description: 'Rename a page tab; duplicate names are disambiguated.',
    inputSchema: withPath(<String, dynamic>{
      'index': <String, dynamic>{
        'type': 'integer',
        'description': 'Page to rename (default: current context).',
      },
      'name': <String, dynamic>{'type': 'string'},
    })
      ..['required'] = <String>['name'],
    handler: (args) =>
        applyOne(args, op('rename_page', args, <String>['index', 'name'])),
  ));

  server.addTool(McpTool(
    name: 'delete_page',
    description: 'Delete a page tab while keeping at least one page. '
        'Dangling background-page references are cleared.',
    inputSchema: withPath(<String, dynamic>{
      'index': <String, dynamic>{
        'type': 'integer',
        'description': 'Page to delete (default: current context).',
      },
    }),
    handler: (args) =>
        applyOne(args, op('delete_page', args, <String>['index'])),
  ));

  server.addTool(McpTool(
    name: 'move_page',
    description: 'Move a page tab to another zero-based position while '
        'preserving the active page by stable id.',
    inputSchema: withPath(<String, dynamic>{
      'from': <String, dynamic>{
        'type': 'integer',
        'description': 'Source index (default: current context).',
      },
      'to': <String, dynamic>{'type': 'integer'},
    })
      ..['required'] = <String>['to'],
    handler: (args) =>
        applyOne(args, op('move_page', args, <String>['from', 'to'])),
  ));

  server.addTool(McpTool(
    name: 'set_page',
    description: 'Set page size/orientation/color/background role or assign a '
        'background page by stable page id.',
    inputSchema: withPath(<String, dynamic>{
      'index': <String, dynamic>{
        'type': 'integer',
        'description': 'Page to edit (default: current context).',
      },
      'width': <String, dynamic>{'type': 'number'},
      'height': <String, dynamic>{'type': 'number'},
      'landscape': <String, dynamic>{'type': 'boolean'},
      'background': <String, dynamic>{
        'type': 'string',
        'description': 'Page color (#RRGGBB) or none.',
      },
      'isBackground': <String, dynamic>{'type': 'boolean'},
      'backgroundPageId': <String, dynamic>{
        'description': 'Stable page id, or "none" to clear.',
      },
    }),
    handler: (args) => applyOne(
      args,
      op('set_page', args, <String>[
        'index',
        'width',
        'height',
        'landscape',
        'background',
        'isBackground',
        'backgroundPageId',
      ]),
    ),
  ));

  server.addTool(McpTool(
    name: 'add_shape',
    description: 'Add one shape. See search_shapes for stencil names.',
    inputSchema: withPath(<String, dynamic>{
      'stencil': <String, dynamic>{'type': 'string'},
      'text': <String, dynamic>{'type': 'string'},
      'x': <String, dynamic>{'type': 'number'},
      'y': <String, dynamic>{'type': 'number'},
      'w': <String, dynamic>{'type': 'number'},
      'h': <String, dynamic>{'type': 'number'},
      'fill': <String, dynamic>{'type': 'string'},
      'line': <String, dynamic>{'type': 'string'},
      'bold': <String, dynamic>{'type': 'boolean'},
      'layerId': <String, dynamic>{
        'type': 'integer',
        'description': 'Layer id; defaults to the active layer, if any.',
      },
    })
      ..['required'] = <String>['stencil'],
    handler: (args) => applyOne(
        args,
        op('add_shape', args, <String>[
          'stencil',
          'text',
          'x',
          'y',
          'w',
          'h',
          'fill',
          'line',
          'bold',
          'textColor',
          'layerId',
        ])),
  ));

  server.addTool(McpTool(
    name: 'add_connector',
    description: 'Connect two shapes by id (e.g. "shape:5" or 5).',
    inputSchema: withPath(<String, dynamic>{
      'from': <String, dynamic>{'type': 'string'},
      'to': <String, dynamic>{'type': 'string'},
      'label': <String, dynamic>{'type': 'string'},
      'arrow': <String, dynamic>{'type': 'boolean'},
      'line': <String, dynamic>{'type': 'string'},
      'layerId': <String, dynamic>{
        'type': 'integer',
        'description': 'Layer id; defaults to the active layer, if any.',
      },
    })
      ..['required'] = <String>['from', 'to'],
    handler: (args) => applyOne(
        args,
        op('add_connector', args,
            <String>['from', 'to', 'label', 'arrow', 'line', 'layerId'])),
  ));

  server.addTool(McpTool(
    name: 'set_connector',
    description: 'Set a connector route (straight/orthogonal/curved), rounded '
        'corners, and page-coordinate bend points. An empty waypoints array '
        'implements draw.io Clear Waypoints.',
    inputSchema: withPath(<String, dynamic>{
      'id': <String, dynamic>{'type': 'string'},
      'route': <String, dynamic>{
        'type': 'string',
        'enum': <String>['straight', 'orthogonal', 'curved'],
      },
      'rounded': <String, dynamic>{'type': 'boolean'},
      'waypoints': <String, dynamic>{
        'type': 'array',
        'description': 'Interior bend points in page inches.',
        'items': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'x': <String, dynamic>{'type': 'number'},
            'y': <String, dynamic>{'type': 'number'},
          },
          'required': <String>['x', 'y'],
        },
      },
    })
      ..['required'] = <String>['id'],
    handler: (args) => applyOne(
      args,
      op(
        'set_connector',
        args,
        <String>['id', 'route', 'rounded', 'waypoints'],
      ),
    ),
  ));

  server.addTool(McpTool(
    name: 'reconnect_connector',
    description: 'Reconnect one connector endpoint to a 2-D shape, optionally '
        'at a fixed connection point. Omit target and provide x/y to detach.',
    inputSchema: withPath(<String, dynamic>{
      'id': <String, dynamic>{'type': 'string'},
      'end': <String, dynamic>{
        'type': 'string',
        'enum': <String>['begin', 'end'],
      },
      'target': <String, dynamic>{
        'type': 'string',
        'description': 'Target shape id; omit or use none to detach.',
      },
      'connectionPoint': <String, dynamic>{
        'type': 'integer',
        'description': 'Optional zero-based fixed connection-point index.',
      },
      'x': <String, dynamic>{
        'type': 'number',
        'description': 'Detached endpoint x in page inches.',
      },
      'y': <String, dynamic>{
        'type': 'number',
        'description': 'Detached endpoint y in page inches.',
      },
    })
      ..['required'] = <String>['id', 'end'],
    handler: (args) => applyOne(
      args,
      op(
        'reconnect_connector',
        args,
        <String>['id', 'end', 'target', 'connectionPoint', 'x', 'y'],
      ),
    ),
  ));

  server.addTool(McpTool(
    name: 'set_style',
    description:
        'Set fill/line/weight/arrows/text/dash/rounding/glow/shadow/reflection and related style on shapes.',
    inputSchema: withPath(<String, dynamic>{
      'ids': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{'type': 'string'},
      },
      'fill': <String, dynamic>{'type': 'string'},
      'line': <String, dynamic>{'type': 'string'},
      'fillPattern': <String, dynamic>{'type': 'integer'},
      'fillBackground': <String, dynamic>{'type': 'string'},
      'weight': <String, dynamic>{'type': 'number'},
      'beginArrow': <String, dynamic>{'type': 'integer'},
      'endArrow': <String, dynamic>{'type': 'integer'},
      'beginArrowSize': <String, dynamic>{'type': 'number'},
      'endArrowSize': <String, dynamic>{'type': 'number'},
      'linePattern': <String, dynamic>{'type': 'integer'},
      'dashPattern': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{'type': 'number', 'exclusiveMinimum': 0},
        'minItems': 1,
      },
      'fixedDash': <String, dynamic>{'type': 'boolean'},
      'lineTransparency': <String, dynamic>{'type': 'number'},
      'lineCap': <String, dynamic>{'type': 'string'},
      'lineJoin': <String, dynamic>{
        'type': 'string',
        'enum': <String>['miter', 'arcs', 'bevel', 'miter-clip', 'round'],
      },
      'miterLimit': <String, dynamic>{'type': 'number', 'minimum': 1},
      'glass': <String, dynamic>{'type': 'boolean'},
      'rounding': <String, dynamic>{'type': 'number'},
      'softEdges': <String, dynamic>{'type': 'number'},
      'compoundType': <String, dynamic>{'type': 'integer'},
      'flipX': <String, dynamic>{'type': 'boolean'},
      'flipY': <String, dynamic>{'type': 'boolean'},
      'locked': <String, dynamic>{'type': 'boolean'},
      'angle': <String, dynamic>{
        'type': 'number',
        'description': 'Shape rotation in degrees',
      },
      'angleRad': <String, dynamic>{
        'type': 'number',
        'description': 'Shape rotation in radians',
      },
      'rotateDeg': <String, dynamic>{'type': 'number'},
      'layerMember': <String, dynamic>{},
      'layers': <String, dynamic>{},
      'themeIndex': <String, dynamic>{'type': 'integer'},
      'quickStyleFillMatrix': <String, dynamic>{'type': 'integer'},
      'quickStyleLineMatrix': <String, dynamic>{'type': 'integer'},
      'quickStyleEffectsMatrix': <String, dynamic>{'type': 'integer'},
      'quickStyleFontMatrix': <String, dynamic>{'type': 'integer'},
      'textAngle': <String, dynamic>{
        'type': 'number',
        'description': 'Text block angle in degrees',
      },
      'textAngleRad': <String, dynamic>{'type': 'number'},
      'glueType': <String, dynamic>{'type': 'integer'},
      'conFixedCode': <String, dynamic>{'type': 'integer'},
      'dynFeedback': <String, dynamic>{'type': 'integer'},
      'shapeRouteStyle': <String, dynamic>{'type': 'integer'},
      'conLineJumpCode': <String, dynamic>{'type': 'integer'},
      'conLineRouteExt': <String, dynamic>{'type': 'integer'},
      'conLineJumpStyle': <String, dynamic>{'type': 'integer'},
      'conLineJumpDirX': <String, dynamic>{'type': 'integer'},
      'conLineJumpDirY': <String, dynamic>{'type': 'integer'},
      'shapePlaceFlip': <String, dynamic>{'type': 'integer'},
      'noLiveDynamics': <String, dynamic>{'type': 'boolean'},
      'noAlignBox': <String, dynamic>{'type': 'boolean'},
      'shapeSplittable': <String, dynamic>{'type': 'boolean'},
      'selectMode': <String, dynamic>{'type': 'integer'},
      'displayMode': <String, dynamic>{'type': 'integer'},
      'isTextEditTarget': <String, dynamic>{'type': 'boolean'},
      'dontMoveChildren': <String, dynamic>{'type': 'boolean'},
      'objType': <String, dynamic>{'type': 'integer'},
      'resizeMode': <String, dynamic>{'type': 'integer'},
      'eventDblClick': <String, dynamic>{'type': 'string'},
      'fillTheme': <String, dynamic>{'type': 'integer'},
      'fillBackgroundTheme': <String, dynamic>{'type': 'integer'},
      'lineTheme': <String, dynamic>{'type': 'integer'},
      'glow': <String, dynamic>{},
      'glowSize': <String, dynamic>{'type': 'number'},
      'glowColor': <String, dynamic>{'type': 'string'},
      'glowTransparency': <String, dynamic>{'type': 'number'},
      'shadow': <String, dynamic>{},
      'shadowColor': <String, dynamic>{'type': 'string'},
      'shadowBlur': <String, dynamic>{'type': 'number'},
      'shadowOffsetX': <String, dynamic>{'type': 'number'},
      'shadowOffsetY': <String, dynamic>{'type': 'number'},
      'shadowTransparency': <String, dynamic>{'type': 'number'},
      'shadowPattern': <String, dynamic>{'type': 'integer'},
      'reflection': <String, dynamic>{},
      'reflectionSize': <String, dynamic>{'type': 'number'},
      'reflectionDist': <String, dynamic>{'type': 'number'},
      'reflectionBlur': <String, dynamic>{'type': 'number'},
      'reflectionTransparency': <String, dynamic>{'type': 'number'},
      'textColor': <String, dynamic>{'type': 'string'},
      'bold': <String, dynamic>{'type': 'boolean'},
      'italic': <String, dynamic>{'type': 'boolean'},
      'underline': <String, dynamic>{'type': 'boolean'},
      'strikethrough': <String, dynamic>{'type': 'boolean'},
      'doubleUnderline': <String, dynamic>{'type': 'boolean'},
      'doubleStrikethrough': <String, dynamic>{'type': 'boolean'},
      'overline': <String, dynamic>{'type': 'boolean'},
      'smallCaps': <String, dynamic>{'type': 'boolean'},
      'fontFamily': <String, dynamic>{'type': 'string'},
      'letterSpacing': <String, dynamic>{'type': 'number'},
      'letterSpacingPt': <String, dynamic>{'type': 'number'},
      'textTransparency': <String, dynamic>{'type': 'number'},
      'textCase': <String, dynamic>{'type': 'string'},
      'textPosition': <String, dynamic>{'type': 'string'},
      'fontScale': <String, dynamic>{'type': 'number'},
      'langId': <String, dynamic>{'type': 'string'},
      'asianFont': <String, dynamic>{'type': 'string'},
      'complexScriptFont': <String, dynamic>{'type': 'string'},
      'complexScriptSize': <String, dynamic>{'type': 'number'},
      'complexScriptSizePt': <String, dynamic>{'type': 'number'},
      'hideText': <String, dynamic>{'type': 'boolean'},
      'pt': <String, dynamic>{'type': 'number'},
      'fontSize': <String, dynamic>{'type': 'number'},
      'opacity': <String, dynamic>{'type': 'number'},
      'fillTransparency': <String, dynamic>{'type': 'number'},
      'fillBackgroundTransparency': <String, dynamic>{'type': 'number'},
      'fillGradient': <String, dynamic>{},
      'lineGradient': <String, dynamic>{},
      'verticalAlign': <String, dynamic>{'type': 'string'},
      'align': <String, dynamic>{'type': 'string'},
      'horizontalAlign': <String, dynamic>{'type': 'string'},
      'textBackground': <String, dynamic>{'type': 'string'},
      'textBackgroundTransparency': <String, dynamic>{'type': 'number'},
      'marginLeft': <String, dynamic>{'type': 'number'},
      'marginRight': <String, dynamic>{'type': 'number'},
      'marginTop': <String, dynamic>{'type': 'number'},
      'marginBottom': <String, dynamic>{'type': 'number'},
      'indentFirst': <String, dynamic>{'type': 'number'},
      'indentLeft': <String, dynamic>{'type': 'number'},
      'indentRight': <String, dynamic>{'type': 'number'},
      'spaceBefore': <String, dynamic>{'type': 'number'},
      'spaceAfter': <String, dynamic>{'type': 'number'},
      'lineSpacing': <String, dynamic>{'type': 'number'},
      'lineSpacingAbsolute': <String, dynamic>{'type': 'number'},
      'lineSpacingAbsolutePt': <String, dynamic>{'type': 'number'},
      'spLine': <String, dynamic>{'type': 'number'},
      'textPosAfterBullet': <String, dynamic>{'type': 'number'},
      'bullet': <String, dynamic>{'type': 'integer'},
      'bulletStr': <String, dynamic>{'type': 'string'},
      'bulletFont': <String, dynamic>{'type': 'string'},
      'bulletFontSize': <String, dynamic>{'type': 'number'},
      'bulletFontSizePt': <String, dynamic>{'type': 'number'},
      'textDirection': <String, dynamic>{'type': 'string'},
      'defaultTabStop': <String, dynamic>{'type': 'number'},
      'imageTransparency': <String, dynamic>{'type': 'number'},
      'imageBlur': <String, dynamic>{'type': 'number'},
      'imageBrightness': <String, dynamic>{'type': 'number'},
      'imageContrast': <String, dynamic>{'type': 'number'},
    })
      ..['required'] = <String>['ids'],
    handler: (args) => applyOne(
        args,
        op('set_style', args, <String>[
          'ids',
          'fill',
          'line',
          'fillPattern',
          'fillBackground',
          'weight',
          'beginArrow',
          'endArrow',
          'beginArrowSize',
          'endArrowSize',
          'linePattern',
          'dashPattern',
          'fixedDash',
          'lineTransparency',
          'lineCap',
          'lineJoin',
          'miterLimit',
          'glass',
          'rounding',
          'softEdges',
          'compoundType',
          'flipX',
          'flipY',
          'locked',
          'angle',
          'angleRad',
          'rotateDeg',
          'layerMember',
          'layers',
          'themeIndex',
          'quickStyleFillMatrix',
          'quickStyleLineMatrix',
          'quickStyleEffectsMatrix',
          'quickStyleFontMatrix',
          'textAngle',
          'textAngleRad',
          'glueType',
          'conFixedCode',
          'dynFeedback',
          'shapeRouteStyle',
          'conLineJumpCode',
          'conLineRouteExt',
          'conLineJumpStyle',
          'conLineJumpDirX',
          'conLineJumpDirY',
          'shapePlaceFlip',
          'noLiveDynamics',
          'noAlignBox',
          'shapeSplittable',
          'selectMode',
          'displayMode',
          'isTextEditTarget',
          'dontMoveChildren',
          'objType',
          'resizeMode',
          'eventDblClick',
          'fillTheme',
          'fillBackgroundTheme',
          'lineTheme',
          'glow',
          'glowSize',
          'glowColor',
          'glowTransparency',
          'shadow',
          'shadowColor',
          'shadowBlur',
          'shadowOffsetX',
          'shadowOffsetY',
          'shadowTransparency',
          'shadowPattern',
          'reflection',
          'reflectionSize',
          'reflectionDist',
          'reflectionBlur',
          'reflectionTransparency',
          'textColor',
          'bold',
          'italic',
          'underline',
          'strikethrough',
          'doubleUnderline',
          'doubleStrikethrough',
          'overline',
          'smallCaps',
          'fontFamily',
          'letterSpacing',
          'letterSpacingPt',
          'textTransparency',
          'textCase',
          'textPosition',
          'fontScale',
          'langId',
          'asianFont',
          'complexScriptFont',
          'complexScriptSize',
          'complexScriptSizePt',
          'hideText',
          'pt',
          'fontSize',
          'opacity',
          'fillTransparency',
          'fillBackgroundTransparency',
          'fillGradient',
          'lineGradient',
          'verticalAlign',
          'align',
          'horizontalAlign',
          'textBackground',
          'textBackgroundTransparency',
          'marginLeft',
          'marginRight',
          'marginTop',
          'marginBottom',
          'indentFirst',
          'indentLeft',
          'indentRight',
          'spaceBefore',
          'spaceAfter',
          'lineSpacing',
          'lineSpacingAbsolute',
          'lineSpacingAbsolutePt',
          'spLine',
          'textPosAfterBullet',
          'bullet',
          'bulletStr',
          'bulletFont',
          'bulletFontSize',
          'bulletFontSizePt',
          'textDirection',
          'defaultTabStop',
          'imageTransparency',
          'imageBlur',
          'imageBrightness',
          'imageContrast',
        ])),
  ));

  server.addTool(McpTool(
    name: 'set_text',
    description: "Set a shape's text label by id.",
    inputSchema: withPath(<String, dynamic>{
      'id': <String, dynamic>{'type': 'string'},
      'text': <String, dynamic>{'type': 'string'},
      'bold': <String, dynamic>{'type': 'boolean'},
    })
      ..['required'] = <String>['id', 'text'],
    handler: (args) => applyOne(args,
        op('set_text', args, <String>['id', 'text', 'bold', 'textColor'])),
  ));

  server.addTool(McpTool(
    name: 'set_shape_data',
    description: 'Replace a shape\'s draw.io-style custom data fields. '
        'An empty properties array clears Shape Data.',
    inputSchema: withPath(<String, dynamic>{
      'id': <String, dynamic>{'type': 'string'},
      'properties': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'name': <String, dynamic>{'type': 'string'},
            'label': <String, dynamic>{'type': 'string'},
            'value': <String, dynamic>{},
            'valueFormula': <String, dynamic>{'type': 'string'},
            'prompt': <String, dynamic>{'type': 'string'},
            'format': <String, dynamic>{'type': 'string'},
            'formatFormula': <String, dynamic>{'type': 'string'},
            'type': <String, dynamic>{'type': 'integer'},
            'sortKey': <String, dynamic>{'type': 'string'},
            'invisible': <String, dynamic>{'type': 'boolean'},
            'verify': <String, dynamic>{'type': 'boolean'},
            'ask': <String, dynamic>{'type': 'boolean'},
            'dataLinked': <String, dynamic>{'type': 'boolean'},
            'langId': <String, dynamic>{'type': 'string'},
            'calendar': <String, dynamic>{'type': 'integer'},
          },
          'required': <String>['name'],
        },
      },
    })
      ..['required'] = <String>['id', 'properties'],
    handler: (args) => applyOne(
      args,
      op('set_data', args, <String>['id', 'properties']),
    ),
  ));

  server.addTool(McpTool(
    name: 'set_shape_links',
    description: 'Replace all hyperlinks on a shape (external URLs and '
        'in-document subAddress targets). An empty links array clears them.',
    inputSchema: withPath(<String, dynamic>{
      'id': <String, dynamic>{'type': 'string'},
      'links': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'id': <String, dynamic>{'type': 'integer'},
            'description': <String, dynamic>{'type': 'string'},
            'address': <String, dynamic>{'type': 'string'},
            'addressFormula': <String, dynamic>{'type': 'string'},
            'subAddress': <String, dynamic>{'type': 'string'},
            'extraInfo': <String, dynamic>{'type': 'string'},
            'frame': <String, dynamic>{'type': 'string'},
            'newWindow': <String, dynamic>{'type': 'boolean'},
            'default': <String, dynamic>{'type': 'boolean'},
            'invisible': <String, dynamic>{'type': 'boolean'},
            'sortKey': <String, dynamic>{'type': 'string'},
          },
        },
      },
    })
      ..['required'] = <String>['id', 'links'],
    handler: (args) => applyOne(
      args,
      op('set_links', args, <String>['id', 'links']),
    ),
  ));

  server.addTool(McpTool(
    name: 'set_connection_points',
    description: 'Replace a 2-D shape\'s draw.io-style fixed connection '
        'points. Coordinates are shape-local inches by default; use '
        'coordinateSpace=page for page inches. An empty points array removes '
        'the explicit points and safely falls fixed glue back to the shape.',
    inputSchema: withPath(<String, dynamic>{
      'id': <String, dynamic>{'type': 'string'},
      'coordinateSpace': <String, dynamic>{
        'type': 'string',
        'enum': <String>['local', 'page'],
        'default': 'local',
      },
      'points': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'x': <String, dynamic>{'type': 'number'},
            'y': <String, dynamic>{'type': 'number'},
            'dirX': <String, dynamic>{'type': 'number'},
            'dirY': <String, dynamic>{'type': 'number'},
            'type': <String, dynamic>{'type': 'integer'},
            'autoGen': <String, dynamic>{'type': 'boolean'},
            'prompt': <String, dynamic>{'type': 'string'},
          },
          'required': <String>['x', 'y'],
        },
      },
    })
      ..['required'] = <String>['id', 'points'],
    handler: (args) => applyOne(
      args,
      op(
        'set_connection_points',
        args,
        <String>['id', 'coordinateSpace', 'points'],
      ),
    ),
  ));

  server.addTool(McpTool(
    name: 'move_shape',
    description: 'Move a shape to a new centre (x,y inches).',
    inputSchema: withPath(<String, dynamic>{
      'id': <String, dynamic>{'type': 'string'},
      'x': <String, dynamic>{'type': 'number'},
      'y': <String, dynamic>{'type': 'number'},
    })
      ..['required'] = <String>['id', 'x', 'y'],
    handler: (args) =>
        applyOne(args, op('move_shape', args, <String>['id', 'x', 'y'])),
  ));

  server.addTool(McpTool(
    name: 'resize_shape',
    description: 'Resize a shape to w×h inches, preserving its centre.',
    inputSchema: withPath(<String, dynamic>{
      'id': <String, dynamic>{'type': 'string'},
      'w': <String, dynamic>{'type': 'number'},
      'h': <String, dynamic>{'type': 'number'},
    })
      ..['required'] = <String>['id', 'w', 'h'],
    handler: (args) =>
        applyOne(args, op('resize_shape', args, <String>['id', 'w', 'h'])),
  ));

  server.addTool(McpTool(
    name: 'duplicate_shapes',
    description: 'Duplicate one or more shapes with fresh ids. Internal '
        'connector glue and Sheet.n! references are remapped.',
    inputSchema: withPath(<String, dynamic>{
      'ids': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{'type': 'string'},
      },
      'dx': <String, dynamic>{
        'type': 'number',
        'description': 'Horizontal offset in inches (default 0.25).',
      },
      'dy': <String, dynamic>{
        'type': 'number',
        'description': 'Vertical offset in inches (default -0.25).',
      },
    })
      ..['required'] = <String>['ids'],
    handler: (args) => applyOne(
        args, op('duplicate_shape', args, <String>['ids', 'dx', 'dy'])),
  ));

  server.addTool(McpTool(
    name: 'reparent_shapes',
    description: 'Move shapes into a draw.io-style container/group while '
        'preserving their page positions and connector glue. Use parent=none '
        'to move them back to the page root.',
    inputSchema: withPath(<String, dynamic>{
      'ids': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{'type': 'string'},
      },
      'parent': <String, dynamic>{
        'type': 'string',
        'description': 'Container shape id, or "none" for the page root.',
      },
    })
      ..['required'] = <String>['ids', 'parent'],
    handler: (args) => applyOne(
      args,
      op('reparent_shapes', args, <String>['ids', 'parent']),
    ),
  ));

  server.addTool(McpTool(
    name: 'set_container_collapsed',
    description: 'Collapse or expand a draw.io-style container/swimlane. '
        'Hidden children remain in the model; glue to them is restored on '
        'expand when both endpoints still exist.',
    inputSchema: withPath(<String, dynamic>{
      'id': <String, dynamic>{'type': 'string'},
      'collapsed': <String, dynamic>{'type': 'boolean'},
    })
      ..['required'] = <String>['id', 'collapsed'],
    handler: (args) => applyOne(
      args,
      op('set_collapsed', args, <String>['id', 'collapsed']),
    ),
  ));

  server.addTool(McpTool(
    name: 'group_shapes',
    description: 'Group at least two editable top-level shapes.',
    inputSchema: withPath(<String, dynamic>{
      'ids': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{'type': 'string'},
      },
      'name': <String, dynamic>{'type': 'string'},
    })
      ..['required'] = <String>['ids'],
    handler: (args) =>
        applyOne(args, op('group', args, <String>['ids', 'name'])),
  ));

  server.addTool(McpTool(
    name: 'ungroup_shapes',
    description: 'Ungroup one or more ordinary groups (tables, charts, and '
        'swimlanes remain structured).',
    inputSchema: withPath(<String, dynamic>{
      'ids': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{'type': 'string'},
      },
    })
      ..['required'] = <String>['ids'],
    handler: (args) => applyOne(args, op('ungroup', args, <String>['ids'])),
  ));

  server.addTool(McpTool(
    name: 'arrange_shape',
    description: 'Change one shape in the sibling z-order.',
    inputSchema: withPath(<String, dynamic>{
      'id': <String, dynamic>{'type': 'string'},
      'action': <String, dynamic>{
        'type': 'string',
        'enum': <String>['front', 'forward', 'backward', 'back'],
      },
    })
      ..['required'] = <String>['id', 'action'],
    handler: (args) =>
        applyOne(args, op('z_order', args, <String>['id', 'action'])),
  ));

  server.addTool(McpTool(
    name: 'align_shapes',
    description: 'Align shapes by rotation-aware page bounds. A single shape '
        'aligns to the page; multiple shapes align to their selection bounds.',
    inputSchema: withPath(<String, dynamic>{
      'ids': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{'type': 'string'},
      },
      'mode': <String, dynamic>{
        'type': 'string',
        'enum': <String>[
          'left',
          'right',
          'center',
          'top',
          'bottom',
          'middle',
        ],
      },
    })
      ..['required'] = <String>['ids', 'mode'],
    handler: (args) =>
        applyOne(args, op('align', args, <String>['ids', 'mode'])),
  ));

  server.addTool(McpTool(
    name: 'distribute_shapes',
    description: 'Equalize horizontal or vertical gaps between at least three '
        'shapes using rotation-aware page bounds.',
    inputSchema: withPath(<String, dynamic>{
      'ids': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{'type': 'string'},
      },
      'axis': <String, dynamic>{
        'type': 'string',
        'enum': <String>['horizontal', 'vertical'],
      },
    })
      ..['required'] = <String>['ids', 'axis'],
    handler: (args) =>
        applyOne(args, op('distribute', args, <String>['ids', 'axis'])),
  ));

  server.addTool(McpTool(
    name: 'delete_shape',
    description: 'Delete a shape by id.',
    inputSchema: withPath(<String, dynamic>{
      'id': <String, dynamic>{'type': 'string'},
    })
      ..['required'] = <String>['id'],
    handler: (args) => applyOne(args, op('delete_shape', args, <String>['id'])),
  ));
}

void _registerLiveTools(McpServer server) {
  Future<T> withBridge<T>(Future<T> Function(BridgeClient c) body) async {
    final c = await BridgeClient.connect();
    try {
      return await body(c);
    } finally {
      await c.close();
    }
  }

  server.addTool(McpTool(
    name: 'open_in_app',
    description: 'Open a .vsdx in the running editor (requires "Agent live '
        'preview" enabled in the app).',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'path': <String, dynamic>{'type': 'string'},
      },
      'required': <String>['path'],
    },
    handler: (args) async => withBridge((c) async {
      final state = await c.call(
          'open', <String, dynamic>{'path': _abs(args['path'] as String)});
      return <McpContent>[McpContent.text('Opened. ${jsonEncode(state)}')];
    }),
  ));

  server.addTool(McpTool(
    name: 'live_apply_ops',
    description: 'Apply Edit Ops to the active document in the running editor '
        '(in-memory, instant preview, one action). Same ops as apply_ops.',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'ops': <String, dynamic>{'type': 'array'},
        'page': <String, dynamic>{
          'type': 'integer',
          'description': 'Zero-based page index (default: current page).',
        },
      },
      'required': <String>['ops'],
    },
    handler: (args) async => withBridge((c) async {
      final state = await c.call('applyOps', <String, dynamic>{
        'ops': _asList(args['ops']),
        if (args['page'] != null) 'page': args['page'],
      });
      return <McpContent>[McpContent.text('Applied. ${jsonEncode(state)}')];
    }),
  ));

  server.addTool(McpTool(
    name: 'select_page',
    description: 'Switch the visible page tab in the running editor by '
        'zero-based index. Use list_pages/get_app_state to discover pages.',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'page': <String, dynamic>{'type': 'integer'},
      },
      'required': <String>['page'],
    },
    handler: (args) async => withBridge((c) async {
      final state =
          await c.call('selectPage', <String, dynamic>{'page': args['page']});
      return <McpContent>[
        McpContent.text(const JsonEncoder.withIndent('  ').convert(state)),
      ];
    }),
  ));

  server.addTool(McpTool(
    name: 'select_layer',
    description: 'Select visible, editable objects assigned to a layer in the '
        'running editor. Optionally switches to the requested page first.',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'layerId': <String, dynamic>{'type': 'integer'},
        'page': <String, dynamic>{'type': 'integer'},
      },
      'required': <String>['layerId'],
    },
    handler: (args) async => withBridge((c) async {
      final state = await c.call('selectLayer', <String, dynamic>{
        'layerId': args['layerId'],
        if (args['page'] != null) 'page': args['page'],
      });
      return <McpContent>[
        McpContent.text(const JsonEncoder.withIndent('  ').convert(state)),
      ];
    }),
  ));

  server.addTool(McpTool(
    name: 'select',
    description: 'Select shapes in the running editor by id (highlights them '
        'for the user). Pass an empty list to clear. Use list_shapes / '
        'get_app_state first to discover ids. Requires Agent live preview.',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'ids': <String, dynamic>{
          'type': 'array',
          'items': <String, dynamic>{'type': 'integer'},
          'description': 'Shape ids on the active page (empty = clear).',
        },
      },
      'required': <String>['ids'],
    },
    handler: (args) async => withBridge((c) async {
      final ids = (args['ids'] as List?) ?? const <dynamic>[];
      final state = await c.call('select', <String, dynamic>{'ids': ids});
      return <McpContent>[
        McpContent.text(const JsonEncoder.withIndent('  ').convert(state)),
      ];
    }),
  ));

  server.addTool(McpTool(
    name: 'snapshot',
    description: 'Render the active page in the running editor to a PNG image '
        '(for visual self-check).',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'page': <String, dynamic>{
          'type': 'integer',
          'description': 'Page index (default: current).',
        },
      },
    },
    handler: (args) async => withBridge((c) async {
      final page = (args['page'] as num?)?.toInt() ?? -1;
      final res = await c.call('snapshot', <String, dynamic>{'page': page});
      return <McpContent>[McpContent.image(res['result'] as String)];
    }),
  ));

  server.addTool(McpTool(
    name: 'get_app_state',
    description: 'Report the running editor state (open document, pages, '
        'selection, dirty flag).',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{},
    },
    handler: (args) async => withBridge((c) async {
      final state = await c.call('getState');
      return <McpContent>[
        McpContent.text(const JsonEncoder.withIndent('  ').convert(state)),
      ];
    }),
  ));
}
