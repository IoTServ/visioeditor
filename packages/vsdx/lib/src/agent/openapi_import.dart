/// OpenAPI 3.x / Swagger 2.0 spec (JSON or YAML) → [DiagramSpec] API diagram.
///
/// Each operation becomes a node coloured by HTTP method (GET blue, POST green,
/// PUT/PATCH orange, DELETE red); each component schema becomes a node; edges
/// link an operation to the schemas it references (`$ref`) and schemas to each
/// other. Mirrors drawio-skill's `openapiimports`. See
/// `docs/MCP_SKILL_PLAN.md` (M5).
library;

import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'diagram_spec.dart';

const _methods = <String>['get', 'post', 'put', 'patch', 'delete', 'head', 'options'];

const _methodFill = <String, String>{
  'get': '#DAE8FC',
  'post': '#D5E8D4',
  'put': '#FFE6CC',
  'patch': '#FFE6CC',
  'delete': '#F8CECC',
  'head': '#E1D5E7',
  'options': '#E1D5E7',
};

/// Parse an OpenAPI/Swagger [source] (JSON or YAML) into a [DiagramSpec].
DiagramSpec openapiToSpec(String source, {int maxNodes = 200}) {
  final spec = _decode(source);
  final title = _str((spec['info'] as Map?)?['title']) ?? 'API';

  // Schemas: OpenAPI 3 → components/schemas; Swagger 2 → definitions.
  final schemas = <String, dynamic>{
    ...?(_asMap(_asMap(spec['components'])?['schemas'])),
    ...?_asMap(spec['definitions']),
  };
  final schemaNames = schemas.keys.toSet();

  final nodes = <NodeSpec>[];
  final edges = <EdgeSpec>[];
  final seenEdge = <String>{};
  final schemaNodeId = <String, String>{
    for (final n in schemaNames) n: 'schema:$n',
  };

  void addEdge(String from, String to, {String? label}) {
    if (from == to) return;
    if (seenEdge.add('$from\u0000$to')) {
      edges.add(EdgeSpec(from: from, to: to, label: label, arrow: true));
    }
  }

  // Operation nodes + operation→schema edges.
  final paths = _asMap(spec['paths']) ?? const <dynamic, dynamic>{};
  for (final entry in paths.entries) {
    final path = '${entry.key}';
    final item = _asMap(entry.value);
    if (item == null) continue;
    for (final method in _methods) {
      final op = _asMap(item[method]);
      if (op == null) continue;
      if (nodes.length >= maxNodes) break;
      final id = 'op:${method.toUpperCase()} $path';
      nodes.add(NodeSpec(
        id: id,
        stencil: 'rounded',
        text: '${method.toUpperCase()} $path',
        fill: _methodFill[method] ?? '#E1D5E7',
        line: '#6C8EBF',
      ));
      for (final ref in _collectRefs(op)) {
        final target = schemaNodeId[ref];
        if (target != null) addEdge(id, target);
      }
    }
  }

  // Schema nodes + schema→schema edges.
  for (final name in schemaNames) {
    if (nodes.length >= maxNodes) break;
    nodes.add(NodeSpec(
      id: schemaNodeId[name]!,
      stencil: 'process',
      text: name,
      fill: '#F5F5F5',
      line: '#666666',
    ));
  }
  for (final name in schemaNames) {
    for (final ref in _collectRefs(schemas[name])) {
      final target = schemaNodeId[ref];
      if (target != null) addEdge(schemaNodeId[name]!, target);
    }
  }

  return DiagramSpec(
    title: title,
    direction: 'LR',
    spacing: 0.8,
    nodes: nodes,
    edges: edges,
  );
}

/// Build `.vsdx` bytes directly from an OpenAPI/Swagger spec.
List<int> openapiToVsdx(String source, {int maxNodes = 200}) =>
    openapiToSpec(source, maxNodes: maxNodes).build();

// --- helpers ---------------------------------------------------------------

Map<String, dynamic> _decode(String source) {
  final t = source.trimLeft();
  if (t.startsWith('{')) {
    return (jsonDecode(source) as Map).cast<String, dynamic>();
  }
  final y = loadYaml(source);
  // Normalise YamlMap/YamlList to plain Map/List via JSON round-trip.
  return (jsonDecode(jsonEncode(y)) as Map).cast<String, dynamic>();
}

Map<dynamic, dynamic>? _asMap(Object? v) =>
    v is Map ? v : null;

String? _str(Object? v) => v == null ? null : '$v';

/// Recursively collect every schema name referenced via `$ref` under [node].
Set<String> _collectRefs(Object? node) {
  final out = <String>{};
  void walk(Object? n) {
    if (n is Map) {
      for (final e in n.entries) {
        if (e.key == r'$ref' && e.value is String) {
          final name = _refName(e.value as String);
          if (name != null) out.add(name);
        } else {
          walk(e.value);
        }
      }
    } else if (n is List) {
      for (final e in n) {
        walk(e);
      }
    }
  }

  walk(node);
  return out;
}

/// `#/components/schemas/Pet` / `#/definitions/Pet` → `Pet`.
String? _refName(String ref) {
  if (!ref.startsWith('#/')) return null;
  final parts = ref.split('/');
  return parts.isEmpty ? null : parts.last;
}
