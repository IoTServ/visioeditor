/// Visualize a codebase: scan a project directory, extract the **import graph**
/// (which module imports which), and emit a [DiagramSpec] → `.vsdx`.
///
/// Supports Dart, Python, and JavaScript/TypeScript. Only *intra-project* edges
/// are kept (external / SDK packages are dropped), so the diagram shows the
/// project's own module structure. Matches drawio-skill's `pyimports` /
/// `jsimports` importers in spirit. See `docs/MCP_SKILL_PLAN.md` (M5).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'diagram_spec.dart';

/// Directories never worth scanning.
const _skipDirs = <String>{
  '.git', 'node_modules', 'build', '.dart_tool', '.pub-cache', 'dist',
  '__pycache__', '.venv', 'venv', '.idea', '.vscode', 'coverage', '.next',
};

const _langExts = <String, List<String>>{
  'dart': <String>['.dart'],
  'python': <String>['.py'],
  'js': <String>['.js', '.jsx', '.ts', '.tsx', '.mjs', '.cjs'],
};

/// Build an import-graph [DiagramSpec] for the project at [root].
///
/// [language] is auto-detected from file counts when omitted. At most
/// [maxFiles] source files are included.
DiagramSpec codeToSpec(String root, {String? language, int maxFiles = 300}) {
  final lang = language ?? _detectLanguage(root);
  final exts = _langExts[lang] ?? const <String>['.dart'];
  final files = _scan(root, exts, maxFiles);

  final idByFile = <String, String>{};
  final idByKey = <String, String>{};
  final labels = <String, String>{};
  for (final f in files) {
    final rel = _rel(root, f);
    final id = _stripExt(rel, exts);
    idByFile[f] = id;
    labels[id] = p.posix.basename(id);
    idByKey[id] = id;
    final base = p.posix.basename(id);
    if (lang == 'python' && base == '__init__') {
      idByKey[p.posix.dirname(id)] = id; // `import pkg` → pkg/__init__.py
    }
    if (lang == 'js' && base == 'index') {
      idByKey[p.posix.dirname(id)] = id; // `./a` → a/index.*
    }
  }

  final edges = <EdgeSpec>[];
  final seen = <String>{};
  for (final f in files) {
    final src = idByFile[f]!;
    String content;
    try {
      content = File(f).readAsStringSync();
    } catch (_) {
      continue;
    }
    for (final spec in extractImports(content, lang)) {
      final target = _resolve(spec, f, root, lang, exts, idByKey);
      if (target == null || target == src) continue;
      if (seen.add('$src\u0000$target')) {
        edges.add(EdgeSpec(from: src, to: target, arrow: true));
      }
    }
  }

  final nodes = <NodeSpec>[
    for (final f in files)
      NodeSpec(
        id: idByFile[f]!,
        stencil: 'rounded',
        text: labels[idByFile[f]!]!,
        fill: '#DAE8FC',
        line: '#6C8EBF',
      ),
  ];

  return DiagramSpec(
    title: 'Code structure (${p.basename(p.normalize(root))})',
    direction: 'LR',
    spacing: 0.7,
    nodes: nodes,
    edges: edges,
  );
}

/// Build `.vsdx` bytes for the project at [root].
List<int> codeToVsdx(String root, {String? language, int maxFiles = 300}) =>
    codeToSpec(root, language: language, maxFiles: maxFiles).build();

// --- import extraction (testable, pure) ------------------------------------

final _dartImportRe =
    RegExp(r'''(?:import|export)\s+['"]([^'"]+)['"]''');
final _pyImportRe = RegExp(r'^\s*import\s+([\w.]+)', multiLine: true);
final _pyFromRe = RegExp(
    r'^\s*from\s+(\.*[\w.]*)\s+import\s+([^\n#]+)',
    multiLine: true);
final _jsFromRe =
    RegExp(r'''(?:import|export)\b[^'"]*?\bfrom\s*['"]([^'"]+)['"]''');
final _jsBareImportRe = RegExp(r'''import\s+['"]([^'"]+)['"]''');
final _jsRequireRe = RegExp(r'''require\(\s*['"]([^'"]+)['"]\s*\)''');

/// Extract raw import specifiers from [content] for [language].
List<String> extractImports(String content, String language) {
  final out = <String>[];
  switch (language) {
    case 'python':
      for (final m in _pyImportRe.allMatches(content)) {
        out.add(m.group(1)!);
      }
      for (final m in _pyFromRe.allMatches(content)) {
        final base = m.group(1)!;
        out.add(base); // the package/module itself
        // `from X import a, b` → also try submodules X.a / X.b (kept only if
        // they resolve to a real file during resolution).
        for (final name in _pyNames(m.group(2)!)) {
          out.add(base.endsWith('.') ? '$base$name' : '$base.$name');
        }
      }
    case 'js':
      for (final m in _jsFromRe.allMatches(content)) {
        out.add(m.group(1)!);
      }
      for (final m in _jsBareImportRe.allMatches(content)) {
        out.add(m.group(1)!);
      }
      for (final m in _jsRequireRe.allMatches(content)) {
        out.add(m.group(1)!);
      }
    case 'dart':
    default:
      for (final m in _dartImportRe.allMatches(content)) {
        out.add(m.group(1)!);
      }
  }
  return out;
}

/// Imported names from a Python `from … import <names>` clause.
List<String> _pyNames(String raw) {
  var t = raw.trim();
  if (t.startsWith('(')) t = t.replaceAll('(', '').replaceAll(')', '');
  return <String>[
    for (final part in t.split(','))
      if (part.trim().split(RegExp(r'\s+')).first case final n
          when n.isNotEmpty && n != '*')
        n,
  ];
}

// --- resolution ------------------------------------------------------------

String? _resolve(String spec, String file, String root, String lang,
    List<String> exts, Map<String, String> idByKey) {
  switch (lang) {
    case 'dart':
      if (spec.startsWith('dart:')) return null;
      if (spec.startsWith('package:')) {
        // package:<pkg>/rest.dart → lib/rest
        final rest = spec.substring('package:'.length);
        final slash = rest.indexOf('/');
        if (slash < 0) return null;
        final key = _stripExt('lib/${rest.substring(slash + 1)}', exts);
        return idByKey[key];
      }
      if (spec.contains(':')) return null; // other schemes
      return _resolveRelative(spec, file, root, exts, idByKey);
    case 'js':
      if (!spec.startsWith('.')) return null; // bare / external
      return _resolveRelative(spec, file, root, exts, idByKey);
    case 'python':
      return _resolvePython(spec, file, root, idByKey);
    default:
      return null;
  }
}

String? _resolveRelative(String spec, String file, String root,
    List<String> exts, Map<String, String> idByKey) {
  final dir = p.dirname(file);
  final abs = p.normalize(p.join(dir, spec));
  final rel = _rel(root, abs);
  final key = _stripExt(rel, exts);
  return idByKey[key];
}

String? _resolvePython(
    String spec, String file, String root, Map<String, String> idByKey) {
  if (spec.isEmpty) return null;
  if (spec.startsWith('.')) {
    // Relative import: leading dots = how far up from the file's package.
    var dots = 0;
    while (dots < spec.length && spec[dots] == '.') {
      dots++;
    }
    final rest = spec.substring(dots);
    var baseDir = p.dirname(file);
    for (var i = 1; i < dots; i++) {
      baseDir = p.dirname(baseDir);
    }
    final relParts = rest.isEmpty ? const <String>[] : rest.split('.');
    final abs = p.normalize(p.joinAll(<String>[baseDir, ...relParts]));
    return idByKey[_rel(root, abs)];
  }
  // Absolute dotted module a.b.c → a/b/c (file or package).
  final key = spec.split('.').join('/');
  return idByKey[key];
}

// --- scanning --------------------------------------------------------------

List<String> _scan(String root, List<String> exts, int maxFiles) {
  final out = <String>[];
  final dir = Directory(root);
  if (!dir.existsSync()) return out;
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final path = entity.path;
    final segments = p.split(p.relative(path, from: root));
    if (segments.any(_skipDirs.contains)) continue;
    if (!exts.contains(p.extension(path).toLowerCase())) continue;
    out.add(path);
    if (out.length >= maxFiles) break;
  }
  out.sort();
  return out;
}

String _detectLanguage(String root) {
  final counts = <String, int>{'dart': 0, 'python': 0, 'js': 0};
  final dir = Directory(root);
  if (!dir.existsSync()) return 'dart';
  var scanned = 0;
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final segments = p.split(p.relative(entity.path, from: root));
    if (segments.any(_skipDirs.contains)) continue;
    final ext = p.extension(entity.path).toLowerCase();
    for (final e in _langExts.entries) {
      if (e.value.contains(ext)) counts[e.key] = counts[e.key]! + 1;
    }
    if (++scanned > 2000) break;
  }
  var best = 'dart';
  var bestCount = -1;
  for (final e in counts.entries) {
    if (e.value > bestCount) {
      best = e.key;
      bestCount = e.value;
    }
  }
  return best;
}

String _rel(String root, String abs) =>
    p.posix.normalize(p.relative(abs, from: root).replaceAll(r'\', '/'));

String _stripExt(String relPosix, List<String> exts) {
  for (final e in exts) {
    if (relPosix.toLowerCase().endsWith(e)) {
      return relPosix.substring(0, relPosix.length - e.length);
    }
  }
  return relPosix;
}
