/// Visualize a codebase: scan a project directory, extract the **import graph**
/// (which module imports which), and emit a [DiagramSpec] → `.vsdx`.
///
/// Supports Dart, Python, JavaScript/TypeScript, Go, and Rust. Only
/// *intra-project* edges are kept (external / SDK packages are dropped), so the
/// diagram shows the project's own module structure. Matches drawio-skill's
/// `pyimports` / `jsimports` importers in spirit. See `docs/MCP_SKILL_PLAN.md`
/// (M5).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'diagram_spec.dart';

/// Directories never worth scanning.
const _skipDirs = <String>{
  '.git', 'node_modules', 'build', '.dart_tool', '.pub-cache', 'dist',
  '__pycache__', '.venv', 'venv', '.idea', '.vscode', 'coverage', '.next',
  'vendor', 'target', '.cargo',
};

const _langExts = <String, List<String>>{
  'dart': <String>['.dart'],
  'python': <String>['.py'],
  'js': <String>['.js', '.jsx', '.ts', '.tsx', '.mjs', '.cjs'],
  'go': <String>['.go'],
  'rust': <String>['.rs'],
};

/// Build an import-graph [DiagramSpec] for the project at [root].
///
/// [language] is auto-detected from file counts when omitted. At most
/// [maxFiles] source files are included.
DiagramSpec codeToSpec(String root, {String? language, int maxFiles = 300}) {
  final lang = language ?? _detectLanguage(root);
  if (lang == 'go') return _goToSpec(root, maxFiles);
  final exts = _langExts[lang] ?? const <String>['.dart'];
  final files = _scan(root, exts, maxFiles);

  final idByFile = <String, String>{};
  final idByKey = <String, String>{};
  final labels = <String, String>{};
  for (final f in files) {
    final rel = _rel(root, f);
    var id = _stripExt(rel, exts);
    // Rust `foo/mod.rs` is the module `foo` (like Python `__init__.py`).
    if (lang == 'rust' && p.posix.basename(id) == 'mod') {
      id = p.posix.dirname(id);
    }
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

// --- Go (package-based) ----------------------------------------------------

/// Go is package-based: a package is a directory. Nodes are packages; edges are
/// intra-module imports resolved via the `go.mod` module path.
DiagramSpec _goToSpec(String root, int maxFiles) {
  final module = _goModulePath(root);
  final files = _scan(root, const <String>['.go'], maxFiles)
      .where((f) => !f.endsWith('_test.go'))
      .toList();

  final pkgDirs = <String>{};
  final filesByPkg = <String, List<String>>{};
  for (final f in files) {
    final dir = p.posix.dirname(_rel(root, f));
    final pkg = dir.isEmpty ? '.' : dir;
    pkgDirs.add(pkg);
    filesByPkg.putIfAbsent(pkg, () => <String>[]).add(f);
  }

  final nodes = <NodeSpec>[
    for (final pkg in pkgDirs.toList()..sort())
      NodeSpec(
        id: 'pkg:$pkg',
        stencil: 'rounded',
        text: pkg == '.'
            ? (module.isEmpty ? 'main' : p.posix.basename(module))
            : p.posix.basename(pkg),
        fill: '#DAE8FC',
        line: '#6C8EBF',
      ),
  ];

  final edges = <EdgeSpec>[];
  final seen = <String>{};
  if (module.isNotEmpty) {
    for (final entry in filesByPkg.entries) {
      final srcPkg = entry.key;
      for (final f in entry.value) {
        String content;
        try {
          content = File(f).readAsStringSync();
        } catch (_) {
          continue;
        }
        for (final imp in extractImports(content, 'go')) {
          final target = _goResolve(imp, module);
          if (target == null || target == srcPkg || !pkgDirs.contains(target)) {
            continue;
          }
          if (seen.add('$srcPkg\u0000$target')) {
            edges.add(EdgeSpec(from: 'pkg:$srcPkg', to: 'pkg:$target', arrow: true));
          }
        }
      }
    }
  }

  return DiagramSpec(
    title: 'Go packages '
        '(${module.isEmpty ? p.basename(p.normalize(root)) : p.posix.basename(module)})',
    direction: 'LR',
    spacing: 0.7,
    nodes: nodes,
    edges: edges,
  );
}

String _goModulePath(String root) {
  final f = File(p.join(root, 'go.mod'));
  if (!f.existsSync()) return '';
  for (final line in f.readAsLinesSync()) {
    final m = RegExp(r'^\s*module\s+(\S+)').firstMatch(line);
    if (m != null) return m.group(1)!;
  }
  return '';
}

/// Resolve a Go import path to a project package dir (posix), or `null` for an
/// external / stdlib import.
String? _goResolve(String importPath, String module) {
  if (importPath == module) return '.';
  final prefix = '$module/';
  if (!importPath.startsWith(prefix)) return null;
  final sub = importPath.substring(prefix.length);
  return sub.isEmpty ? '.' : sub;
}

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
final _rustModRe = RegExp(
    r'^\s*(?:pub(?:\s*\([^)]*\))?\s+)?mod\s+(\w+)\s*;',
    multiLine: true);
final _rustUseCrateRe = RegExp(
    r'^\s*(?:pub(?:\s*\([^)]*\))?\s+)?use\s+crate::([\w:]+)',
    multiLine: true);
final _rustUseSuperRe = RegExp(
    r'^\s*(?:pub(?:\s*\([^)]*\))?\s+)?use\s+((?:super::)+[\w:]*)',
    multiLine: true);
final _rustUseSelfRe = RegExp(
    r'^\s*(?:pub(?:\s*\([^)]*\))?\s+)?use\s+self::([\w:]+)',
    multiLine: true);

/// Extract raw import specifiers from [content] for [language].
List<String> extractImports(String content, String language) {
  final out = <String>[];
  switch (language) {
    case 'go':
      // import ( "a" \n alias "b" )
      for (final m in RegExp(r'import\s*\(([^)]*)\)', dotAll: true).allMatches(content)) {
        for (final q in RegExp('"([^"]+)"').allMatches(m.group(1)!)) {
          out.add(q.group(1)!);
        }
      }
      // import "single"  (optional alias/dot/underscore)
      for (final m in RegExp(r'^\s*import\s+(?:[A-Za-z0-9_.]+\s+)?"([^"]+)"',
              multiLine: true)
          .allMatches(content)) {
        out.add(m.group(1)!);
      }
    case 'rust':
      for (final m in _rustModRe.allMatches(content)) {
        out.add('mod:${m.group(1)!}');
      }
      for (final m in _rustUseCrateRe.allMatches(content)) {
        out.add('crate:${_rustTrimPath(m.group(1)!)}');
      }
      for (final m in _rustUseSuperRe.allMatches(content)) {
        out.add(_rustTrimPath(m.group(1)!));
      }
      for (final m in _rustUseSelfRe.allMatches(content)) {
        out.add('self:${_rustTrimPath(m.group(1)!)}');
      }
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
    case 'rust':
      return _resolveRust(spec, file, root, idByKey);
    default:
      return null;
  }
}

String _rustTrimPath(String path) {
  var t = path.trim();
  while (t.endsWith('::')) {
    t = t.substring(0, t.length - 2);
  }
  return t;
}

/// Resolve Rust `mod:name` / `crate:…` / `super::…` / `self:…` to a module id.
String? _resolveRust(
    String spec, String file, String root, Map<String, String> idByKey) {
  if (spec.startsWith('mod:')) {
    final name = spec.substring(4);
    return _rustLookup(_rustChildModDir(file), <String>[name], root, idByKey);
  }
  if (spec.startsWith('crate:')) {
    final srcRoot = _rustSrcRoot(file, root);
    if (srcRoot == null) return null;
    final parts = _rustParts(spec.substring('crate:'.length));
    return _rustLookupLongest(srcRoot, parts, root, idByKey);
  }
  if (spec.startsWith('super::')) {
    var rest = spec;
    var ups = 0;
    while (rest.startsWith('super::')) {
      ups++;
      rest = rest.substring('super::'.length);
    }
    var dir = _rustParentModDir(file);
    for (var i = 1; i < ups; i++) {
      if (dir == null) return null;
      dir = p.dirname(dir);
    }
    if (dir == null) return null;
    final parts = _rustParts(rest);
    if (parts.isEmpty) return idByKey[_rel(root, dir)];
    return _rustLookupLongest(dir, parts, root, idByKey);
  }
  if (spec.startsWith('self:')) {
    final parts = _rustParts(spec.substring('self:'.length));
    if (parts.isEmpty) return null;
    return _rustLookupLongest(_rustChildModDir(file), parts, root, idByKey);
  }
  return null;
}

List<String> _rustParts(String path) => path
    .split('::')
    .where((s) => s.isNotEmpty)
    .toList();

String? _rustLookupLongest(String baseDir, List<String> parts, String root,
    Map<String, String> idByKey) {
  for (var n = parts.length; n >= 1; n--) {
    final hit = _rustLookup(baseDir, parts.sublist(0, n), root, idByKey);
    if (hit != null) return hit;
  }
  return null;
}

/// Directory that owns child `mod name;` declarations for [file].
String _rustChildModDir(String file) {
  final base = p.basename(file).toLowerCase();
  if (base == 'mod.rs' || base == 'lib.rs' || base == 'main.rs') {
    return p.dirname(file);
  }
  final stem = p.basenameWithoutExtension(file);
  return p.join(p.dirname(file), stem);
}

/// Parent module directory of [file], or `null` at crate root.
String? _rustParentModDir(String file) {
  final base = p.basename(file).toLowerCase();
  if (base == 'lib.rs' || base == 'main.rs') return null;
  if (base == 'mod.rs') return p.dirname(p.dirname(file));
  return p.dirname(file);
}

/// Crate `src/` directory containing `lib.rs` / `main.rs`, walking up from [file].
String? _rustSrcRoot(String file, String root) {
  var dir = p.dirname(file);
  final rootNorm = p.normalize(root);
  while (true) {
    if (File(p.join(dir, 'lib.rs')).existsSync() ||
        File(p.join(dir, 'main.rs')).existsSync()) {
      return dir;
    }
    final parent = p.dirname(dir);
    if (parent == dir) break;
    if (!_isUnder(parent, rootNorm) && p.normalize(parent) != rootNorm) break;
    dir = parent;
  }
  // Fallback: <crate>/src when Cargo.toml is present.
  dir = p.dirname(file);
  while (true) {
    final cargo = File(p.join(dir, 'Cargo.toml'));
    final src = p.join(dir, 'src');
    if (cargo.existsSync() && Directory(src).existsSync()) return src;
    final parent = p.dirname(dir);
    if (parent == dir) break;
    if (!_isUnder(parent, rootNorm) && p.normalize(parent) != rootNorm) break;
    dir = parent;
  }
  return null;
}

bool _isUnder(String path, String root) {
  final n = p.normalize(path);
  final r = p.normalize(root);
  return n == r || p.isWithin(r, n);
}

String? _rustLookup(String baseDir, List<String> parts, String root,
    Map<String, String> idByKey) {
  if (parts.isEmpty) return null;
  final abs = p.normalize(p.joinAll(<String>[baseDir, ...parts]));
  return idByKey[_rel(root, abs)];
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
  final counts = <String, int>{
    for (final k in _langExts.keys) k: 0,
  };
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
