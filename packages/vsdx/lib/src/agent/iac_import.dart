/// Infrastructure-as-Code → [DiagramSpec] architecture diagram.
///
/// Auto-detects **docker-compose** (`services:`), **Kubernetes** manifests
/// (`kind:` / multi-doc YAML), and **Terraform** HCL (`resource` / `module` /
/// `data` blocks) and draws the resource graph:
///   * compose: one node per service, edges from `depends_on` / `links`, named
///     `volumes` as cylinders.
///   * k8s: one node per resource (coloured by kind); Service→workload (label
///     selector), Ingress→Service (backends), workload→ConfigMap/Secret/PVC
///     (volumes + envFrom).
///   * terraform: one node per resource/module/data; edges from `depends_on`
///     and in-body references (`aws_instance.web`, `module.vpc`,
///     `data.aws_ami.x`, `${…}` interpolations).
///
/// Mirrors drawio-skill's `composeimports` / `k8simports`. See
/// `docs/MCP_SKILL_PLAN.md` (M5).
library;

import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'diagram_spec.dart';

/// Parse IaC [source] (compose / Kubernetes YAML / Terraform HCL) into a
/// [DiagramSpec].
DiagramSpec iacToSpec(String source) {
  if (_looksTerraform(source)) return _terraformToSpec(source);
  final docs = <Map<String, dynamic>>[];
  for (final node in loadYamlStream(source)) {
    final v = jsonDecode(jsonEncode(node));
    if (v is Map) docs.add(v.cast<String, dynamic>());
  }
  if (docs.isEmpty) {
    return DiagramSpec(title: 'Infrastructure', direction: 'LR');
  }
  final hasKind = docs.any((d) => d.containsKey('kind'));
  final looksCompose = docs.first.containsKey('services') && !hasKind;
  return looksCompose ? _composeToSpec(docs.first) : _k8sToSpec(docs);
}

/// Build `.vsdx` bytes directly from IaC source.
List<int> iacToVsdx(String source) => iacToSpec(source).build();

bool _looksTerraform(String source) {
  // Prefer HCL keywords with quoted labels over YAML `resource:` keys.
  return RegExp(
    r'^\s*(?:resource|module|data|terraform|provider)\s+"',
    multiLine: true,
  ).hasMatch(source);
}

// --- docker-compose --------------------------------------------------------

DiagramSpec _composeToSpec(Map<String, dynamic> doc) {
  final nodes = <NodeSpec>[];
  final edges = <EdgeSpec>[];
  final services = _asMap(doc['services']);
  final namedVolumes = _asMap(doc['volumes'])?.keys.map((k) => '$k').toSet() ??
      <String>{};

  for (final vol in namedVolumes) {
    nodes.add(NodeSpec(
      id: 'vol:$vol',
      stencil: 'cylinder',
      text: vol,
      fill: '#D5E8D4',
      line: '#82B366',
    ));
  }

  services?.forEach((k, v) {
    final name = '$k';
    final svc = _asMap(v) ?? const <dynamic, dynamic>{};
    final image = _str(svc['image']);
    nodes.add(NodeSpec(
      id: 'svc:$name',
      stencil: 'rounded',
      text: image == null ? name : '$name\n$image',
      fill: '#DAE8FC',
      line: '#6C8EBF',
      bold: true,
    ));
  });

  services?.forEach((k, v) {
    final name = '$k';
    final svc = _asMap(v) ?? const <dynamic, dynamic>{};
    for (final dep in _depends(svc)) {
      if (services.containsKey(dep)) {
        edges.add(EdgeSpec(from: 'svc:$name', to: 'svc:$dep', arrow: true));
      }
    }
    for (final vol in _mountedNamedVolumes(svc, namedVolumes)) {
      edges.add(EdgeSpec(from: 'svc:$name', to: 'vol:$vol', arrow: true));
    }
  });

  return DiagramSpec(
    title: 'docker-compose',
    direction: 'LR',
    spacing: 0.8,
    nodes: nodes,
    edges: edges,
  );
}

Iterable<String> _depends(Map<dynamic, dynamic> svc) sync* {
  final d = svc['depends_on'];
  if (d is List) {
    for (final e in d) {
      yield '$e';
    }
  } else if (d is Map) {
    for (final k in d.keys) {
      yield '$k';
    }
  }
  final links = svc['links'];
  if (links is List) {
    for (final e in links) {
      yield '$e'.split(':').first; // "db:database" -> "db"
    }
  }
}

Iterable<String> _mountedNamedVolumes(
    Map<dynamic, dynamic> svc, Set<String> named) sync* {
  final vols = svc['volumes'];
  if (vols is! List) return;
  for (final v in vols) {
    String? src;
    if (v is String) {
      src = v.split(':').first;
    } else if (v is Map) {
      src = _str(v['source']);
    }
    if (src != null && named.contains(src)) yield src;
  }
}

// --- kubernetes ------------------------------------------------------------

const _k8sFill = <String, String>{
  'deployment': '#DAE8FC',
  'statefulset': '#DAE8FC',
  'daemonset': '#DAE8FC',
  'replicaset': '#DAE8FC',
  'pod': '#DAE8FC',
  'job': '#DAE8FC',
  'cronjob': '#DAE8FC',
  'service': '#D5E8D4',
  'ingress': '#FFE6CC',
  'configmap': '#F5F5F5',
  'secret': '#F5F5F5',
  'persistentvolumeclaim': '#D5E8D4',
  'persistentvolume': '#D5E8D4',
};

String _k8sStencil(String kind) {
  switch (kind) {
    case 'service':
      return 'ellipse';
    case 'ingress':
      return 'hexagon';
    case 'configmap':
    case 'secret':
      return 'data';
    case 'persistentvolumeclaim':
    case 'persistentvolume':
      return 'cylinder';
    default:
      return 'rounded';
  }
}

DiagramSpec _k8sToSpec(List<Map<String, dynamic>> docs) {
  final nodes = <NodeSpec>[];
  final edges = <EdgeSpec>[];
  final byId = <String>{};
  final seenEdge = <String>{};
  // Index workloads by their pod-template labels for Service selector matching.
  final workloads = <(String id, Map<String, dynamic> labels)>[];

  String idOf(String kind, String name) => 'k8s:$kind/$name';

  void addNode(String kind, String name) {
    final id = idOf(kind, name);
    if (!byId.add(id)) return;
    nodes.add(NodeSpec(
      id: id,
      stencil: _k8sStencil(kind),
      text: '$name\n($kind)',
      fill: _k8sFill[kind] ?? '#E1D5E7',
      line: '#6C8EBF',
    ));
  }

  void addEdge(String from, String to, {String? label}) {
    if (from == to || !byId.contains(from) || !byId.contains(to)) return;
    if (seenEdge.add('$from\u0000$to')) {
      edges.add(EdgeSpec(from: from, to: to, label: label, arrow: true));
    }
  }

  // First pass: nodes.
  for (final doc in docs) {
    final kind = _str(doc['kind'])?.toLowerCase();
    final name = _str(_asMap(doc['metadata'])?['name']);
    if (kind == null || name == null) continue;
    addNode(kind, name);
    final tmplLabels = _asMap(_asMap(_asMap(_asMap(doc['spec'])?['template'])?[
                'metadata'])?['labels']) ??
        const <dynamic, dynamic>{};
    if (_k8sFill[kind] == '#DAE8FC') {
      workloads.add((idOf(kind, name), tmplLabels.map((k, v) => MapEntry('$k', v))));
    }
  }

  // Second pass: edges.
  for (final doc in docs) {
    final kind = _str(doc['kind'])?.toLowerCase();
    final name = _str(_asMap(doc['metadata'])?['name']);
    if (kind == null || name == null) continue;
    final id = idOf(kind, name);
    final spec = _asMap(doc['spec']);

    if (kind == 'service') {
      final selector = _asMap(spec?['selector']);
      if (selector != null && selector.isNotEmpty) {
        for (final w in workloads) {
          if (_matchesSelector(selector, w.$2)) addEdge(id, w.$1);
        }
      }
    } else if (kind == 'ingress') {
      for (final svc in _ingressServices(spec)) {
        addEdge(id, idOf('service', svc));
      }
    } else {
      // Workloads: link to ConfigMap / Secret / PVC referenced by the pod spec.
      final podSpec = _asMap(_asMap(spec?['template'])?['spec']) ?? _asMap(spec);
      for (final ref in _workloadRefs(podSpec)) {
        addEdge(id, ref);
      }
    }
  }

  return DiagramSpec(
    title: 'Kubernetes',
    direction: 'LR',
    spacing: 0.8,
    nodes: nodes,
    edges: edges,
  );
}

bool _matchesSelector(
    Map<dynamic, dynamic> selector, Map<String, dynamic> labels) {
  for (final e in selector.entries) {
    if ('${labels['${e.key}']}' != '${e.value}') return false;
  }
  return true;
}

Iterable<String> _ingressServices(Map<dynamic, dynamic>? spec) sync* {
  // Default backend (v1: spec.defaultBackend.service.name).
  final def = _asMap(_asMap(spec?['defaultBackend'])?['service']);
  final defName = _str(def?['name']);
  if (defName != null) yield defName;
  final rules = spec?['rules'];
  if (rules is! List) return;
  for (final rule in rules) {
    final paths = _asMap(_asMap(rule)?['http'])?['paths'];
    if (paths is! List) continue;
    for (final path in paths) {
      final backend = _asMap(_asMap(path)?['backend']);
      // networking.k8s.io/v1
      final v1 = _str(_asMap(backend?['service'])?['name']);
      if (v1 != null) yield v1;
      // extensions/v1beta1
      final beta = _str(backend?['serviceName']);
      if (beta != null) yield beta;
    }
  }
}

/// ConfigMap/Secret/PVC ids referenced by a pod spec (volumes + envFrom).
Iterable<String> _workloadRefs(Map<dynamic, dynamic>? podSpec) sync* {
  if (podSpec == null) return;
  final volumes = podSpec['volumes'];
  if (volumes is List) {
    for (final v in volumes) {
      final vm = _asMap(v);
      final cm = _str(_asMap(vm?['configMap'])?['name']);
      if (cm != null) yield 'k8s:configmap/$cm';
      final sec = _str(_asMap(vm?['secret'])?['secretName']);
      if (sec != null) yield 'k8s:secret/$sec';
      final pvc = _str(_asMap(vm?['persistentVolumeClaim'])?['claimName']);
      if (pvc != null) yield 'k8s:persistentvolumeclaim/$pvc';
    }
  }
  final containers = podSpec['containers'];
  if (containers is List) {
    for (final c in containers) {
      final envFrom = _asMap(c)?['envFrom'];
      if (envFrom is List) {
        for (final e in envFrom) {
          final cm = _str(_asMap(_asMap(e)?['configMapRef'])?['name']);
          if (cm != null) yield 'k8s:configmap/$cm';
          final sec = _str(_asMap(_asMap(e)?['secretRef'])?['name']);
          if (sec != null) yield 'k8s:secret/$sec';
        }
      }
    }
  }
}

// --- terraform (HCL subset) ------------------------------------------------

final _tfBlockRe = RegExp(
  r'^\s*(resource|data|module)\s+"([^"]+)"(?:\s+"([^"]+)")?\s*\{',
  multiLine: true,
);

/// Strip `#` / `//` line comments and `/* … */` block comments (best-effort).
String _tfStripComments(String source) {
  final noBlock = source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return noBlock
      .split('\n')
      .map((line) {
        final hash = line.indexOf('#');
        final slash = line.indexOf('//');
        var cut = line.length;
        if (hash >= 0) cut = hash;
        if (slash >= 0 && slash < cut) cut = slash;
        return line.substring(0, cut);
      })
      .join('\n');
}

/// Extract `{ … }` body starting at [openBrace] (index of `{`), or `null`.
String? _tfBlockBody(String source, int openBrace) {
  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    final c = source[i];
    if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return source.substring(openBrace + 1, i);
    }
  }
  return null;
}

class _TfNode {
  _TfNode({
    required this.kind,
    required this.type,
    required this.name,
    required this.body,
  });
  final String kind; // resource | data | module
  final String type; // aws_instance / module label / …
  final String name;
  final String body;

  String get id => kind == 'module'
      ? 'tf:module.$name'
      : kind == 'data'
          ? 'tf:data.$type.$name'
          : 'tf:$type.$name';

  /// Address forms that other blocks may reference.
  Iterable<String> get addresses sync* {
    yield id;
    if (kind == 'module') {
      yield 'module.$name';
    } else if (kind == 'data') {
      yield 'data.$type.$name';
    } else {
      yield '$type.$name';
    }
  }
}

DiagramSpec _terraformToSpec(String source) {
  final cleaned = _tfStripComments(source);
  final nodes = <_TfNode>[];
  for (final m in _tfBlockRe.allMatches(cleaned)) {
    final kind = m.group(1)!;
    final a = m.group(2)!;
    final b = m.group(3);
    if (kind == 'module') {
      if (b != null) continue; // malformed
      final body = _tfBlockBody(cleaned, m.end - 1);
      if (body == null) continue;
      nodes.add(_TfNode(kind: kind, type: 'module', name: a, body: body));
    } else {
      if (b == null) continue;
      final body = _tfBlockBody(cleaned, m.end - 1);
      if (body == null) continue;
      nodes.add(_TfNode(kind: kind, type: a, name: b, body: body));
    }
  }

  final byAddress = <String, String>{}; // address → node id
  for (final n in nodes) {
    for (final a in n.addresses) {
      byAddress[a] = n.id;
    }
  }

  final outNodes = <NodeSpec>[
    for (final n in nodes)
      NodeSpec(
        id: n.id,
        stencil: n.kind == 'module'
            ? 'hexagon'
            : n.kind == 'data'
                ? 'data'
                : 'rounded',
        text: n.kind == 'module'
            ? 'module.${n.name}'
            : n.kind == 'data'
                ? 'data.${n.type}.${n.name}'
                : '${n.type}.${n.name}',
        fill: _tfFill(n),
        line: '#6C8EBF',
        bold: n.kind == 'module',
      ),
  ];

  final edges = <EdgeSpec>[];
  final seen = <String>{};
  for (final n in nodes) {
    for (final target in _tfRefs(n.body, byAddress, n.id)) {
      if (seen.add('${n.id}\u0000$target')) {
        edges.add(EdgeSpec(from: n.id, to: target, arrow: true));
      }
    }
  }

  return DiagramSpec(
    title: 'Terraform',
    direction: 'LR',
    spacing: 0.8,
    nodes: outNodes,
    edges: edges,
  );
}

String _tfFill(_TfNode n) {
  if (n.kind == 'module') return '#E1D5E7';
  if (n.kind == 'data') return '#F5F5F5';
  final t = n.type;
  if (t.startsWith('aws_')) return '#FFD966';
  if (t.startsWith('google_') || t.startsWith('gcp_')) return '#DAE8FC';
  if (t.startsWith('azurerm_') || t.startsWith('azure_')) return '#B0E3E6';
  return '#D5E8D4';
}

/// Resolve references in a block body to other node ids.
Iterable<String> _tfRefs(
    String body, Map<String, String> byAddress, String selfId) sync* {
  final found = <String>{};

  // depends_on = [ aws_instance.web, module.vpc ]
  for (final m in RegExp(r'depends_on\s*=\s*\[([^\]]*)\]').allMatches(body)) {
    for (final part in m.group(1)!.split(',')) {
      final addr = part.trim().replaceAll('"', '').replaceAll("'", '');
      final id = byAddress[addr];
      if (id != null && id != selfId) found.add(id);
    }
  }

  // Bare / interpolation references: module.x, data.t.n, type.name
  final patterns = <RegExp>[
    RegExp(r'\bmodule\.([A-Za-z0-9_-]+)'),
    RegExp(r'\bdata\.([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)'),
    RegExp(r'\b([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)'),
  ];
  for (final re in patterns) {
    for (final m in re.allMatches(body)) {
      final addr = m.group(0)!;
      // Skip false positives like var.x / local.x / path.module / count.index
      if (addr.startsWith('var.') ||
          addr.startsWith('local.') ||
          addr.startsWith('path.') ||
          addr.startsWith('count.') ||
          addr.startsWith('each.') ||
          addr.startsWith('terraform.') ||
          addr.startsWith('provider.')) {
        continue;
      }
      final id = byAddress[addr];
      if (id != null && id != selfId) found.add(id);
    }
  }

  // Also match full data./module. addresses already handled; for
  // `type.name.attr` the third pattern may capture `type.name` — good.

  yield* found;
}

// --- helpers ---------------------------------------------------------------

Map<dynamic, dynamic>? _asMap(Object? v) => v is Map ? v : null;
String? _str(Object? v) => v == null ? null : '$v';
