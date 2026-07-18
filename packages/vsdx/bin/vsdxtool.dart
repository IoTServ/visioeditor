/// `vsdxtool` — the headless Agent backend for visioeditor.
///
/// Turns a **Diagram Spec** into a round-trip-faithful `.vsdx`, applies
/// **Edit Ops** to an existing file, renders SVG previews, and lints / explains
/// documents — all in pure Dart (no Flutter, no Electron). Compile a single
/// binary with `dart compile exe bin/vsdxtool.dart -o vsdxtool`.
///
/// See `docs/MCP_SKILL_PLAN.md`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:vsdx/agent.dart';
import 'package:vsdx/vsdx.dart';

Future<void> main(List<String> args) async {
  final runner = CommandRunner<int>(
    'vsdxtool',
    'Headless .vsdx authoring/editing backend for AI agents (visioeditor).',
  )
    ..addCommand(_BuildCommand())
    ..addCommand(_ImportMermaidCommand())
    ..addCommand(_ImportSqlCommand())
    ..addCommand(_ImportCodeCommand())
    ..addCommand(_ImportOpenapiCommand())
    ..addCommand(_ImportIacCommand())
    ..addCommand(_PatchCommand())
    ..addCommand(_RenderCommand())
    ..addCommand(_ToMermaidCommand())
    ..addCommand(_ValidateCommand())
    ..addCommand(_ExplainCommand())
    ..addCommand(_ShapesCommand())
    ..addCommand(_VersionCommand());
  try {
    final code = await runner.run(args) ?? 0;
    exitCode = code;
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  }
}

Uint8List _readBytes(String path) =>
    Uint8List.fromList(File(path).readAsBytesSync());

class _BuildCommand extends Command<int> {
  _BuildCommand() {
    argParser
      ..addOption('output', abbr: 'o', help: 'Output .vsdx path.', mandatory: true)
      ..addOption('spec',
          abbr: 's', help: 'Diagram Spec JSON path (or read stdin if omitted).');
  }
  @override
  String get name => 'build';
  @override
  String get description => 'Build a .vsdx from a Diagram Spec JSON.';

  @override
  int run() {
    final specPath = argResults!['spec'] as String?;
    final jsonText =
        specPath != null ? File(specPath).readAsStringSync() : _readAllStdin();
    final spec = DiagramSpec.parse(jsonText);
    final bytes = spec.build();
    final out = argResults!['output'] as String;
    File(out).writeAsBytesSync(bytes);
    stdout.writeln(
        'built $out (${bytes.length} bytes, ${spec.nodes.length} nodes, '
        '${spec.edges.length} edges)');
    return 0;
  }
}

class _ImportMermaidCommand extends Command<int> {
  _ImportMermaidCommand() {
    argParser
      ..addOption('input',
          abbr: 'i', help: 'Mermaid (.mmd) path (or read stdin if omitted).')
      ..addOption('output', abbr: 'o', help: 'Output .vsdx path.', mandatory: true);
  }
  @override
  String get name => 'import-mermaid';
  @override
  String get description =>
      'Convert a Mermaid flowchart/graph to an editable .vsdx.';

  @override
  int run() {
    final input = argResults!['input'] as String?;
    final text = input != null ? File(input).readAsStringSync() : _readAllStdin();
    final spec = mermaidToSpec(text);
    final bytes = spec.build();
    final out = argResults!['output'] as String;
    File(out).writeAsBytesSync(bytes);
    stdout.writeln('imported $out (${bytes.length} bytes, '
        '${spec.nodes.length} nodes, ${spec.edges.length} edges)');
    return 0;
  }
}

class _ImportSqlCommand extends Command<int> {
  _ImportSqlCommand() {
    argParser
      ..addOption('input',
          abbr: 'i', help: 'SQL DDL (.sql) path (or read stdin if omitted).')
      ..addOption('output', abbr: 'o', help: 'Output .vsdx path.', mandatory: true);
  }
  @override
  String get name => 'import-sql';
  @override
  String get description =>
      'Convert SQL DDL (CREATE TABLE …) to an editable ER diagram .vsdx.';

  @override
  int run() {
    final input = argResults!['input'] as String?;
    final text = input != null ? File(input).readAsStringSync() : _readAllStdin();
    final spec = sqlToSpec(text);
    final bytes = spec.build();
    final out = argResults!['output'] as String;
    File(out).writeAsBytesSync(bytes);
    stdout.writeln('imported $out (${bytes.length} bytes, '
        '${spec.nodes.length} tables, ${spec.edges.length} FKs)');
    return 0;
  }
}

class _ImportCodeCommand extends Command<int> {
  _ImportCodeCommand() {
    argParser
      ..addOption('dir',
          abbr: 'd', help: 'Project root to scan (default: current dir).')
      ..addOption('lang',
          help: 'dart | python | js | go | rust (auto-detected if omitted).')
      ..addOption('max', help: 'Max source files.', defaultsTo: '300')
      ..addOption('output', abbr: 'o', help: 'Output .vsdx path.', mandatory: true);
  }
  @override
  String get name => 'import-code';
  @override
  String get description =>
      'Visualize a codebase import graph (Dart/Python/JS-TS) as an editable .vsdx.';

  @override
  int run() {
    final dir = (argResults!['dir'] as String?) ?? Directory.current.path;
    final spec = codeToSpec(
      dir,
      language: argResults!['lang'] as String?,
      maxFiles: int.tryParse(argResults!['max'] as String) ?? 300,
    );
    final bytes = spec.build();
    final out = argResults!['output'] as String;
    File(out).writeAsBytesSync(bytes);
    stdout.writeln('imported $out (${bytes.length} bytes, '
        '${spec.nodes.length} modules, ${spec.edges.length} imports)');
    return 0;
  }
}

class _ImportOpenapiCommand extends Command<int> {
  _ImportOpenapiCommand() {
    argParser
      ..addOption('input',
          abbr: 'i', help: 'OpenAPI/Swagger spec (.yaml/.json), or stdin.')
      ..addOption('output', abbr: 'o', help: 'Output .vsdx path.', mandatory: true);
  }
  @override
  String get name => 'import-openapi';
  @override
  String get description =>
      'Convert an OpenAPI/Swagger spec (JSON/YAML) to an editable API diagram .vsdx.';

  @override
  int run() {
    final input = argResults!['input'] as String?;
    final text = input != null ? File(input).readAsStringSync() : _readAllStdin();
    final spec = openapiToSpec(text);
    final bytes = spec.build();
    final out = argResults!['output'] as String;
    File(out).writeAsBytesSync(bytes);
    stdout.writeln('imported $out (${bytes.length} bytes, '
        '${spec.nodes.length} nodes, ${spec.edges.length} refs)');
    return 0;
  }
}

class _ImportIacCommand extends Command<int> {
  _ImportIacCommand() {
    argParser
      ..addOption('input',
          abbr: 'i',
          help: 'docker-compose / Kubernetes YAML / Terraform .tf path, or stdin.')
      ..addOption('output', abbr: 'o', help: 'Output .vsdx path.', mandatory: true);
  }
  @override
  String get name => 'import-iac';
  @override
  String get description =>
      'Convert docker-compose / Kubernetes YAML / Terraform HCL to an '
      'architecture diagram .vsdx.';

  @override
  int run() {
    final input = argResults!['input'] as String?;
    final text = input != null ? File(input).readAsStringSync() : _readAllStdin();
    final spec = iacToSpec(text);
    final bytes = spec.build();
    final out = argResults!['output'] as String;
    File(out).writeAsBytesSync(bytes);
    stdout.writeln('imported $out (${bytes.length} bytes, '
        '${spec.nodes.length} resources, ${spec.edges.length} links)');
    return 0;
  }
}

class _PatchCommand extends Command<int> {
  _PatchCommand() {
    argParser
      ..addOption('input', abbr: 'i', help: 'Input .vsdx path.', mandatory: true)
      ..addOption('ops', help: 'Edit Ops JSON path.', mandatory: true)
      ..addOption('output',
          abbr: 'o', help: 'Output .vsdx path (defaults to overwriting input).');
  }
  @override
  String get name => 'patch';
  @override
  String get description => 'Apply Edit Ops JSON to a .vsdx (round-trip faithful).';

  @override
  int run() {
    final input = argResults!['input'] as String;
    final opsJson = File(argResults!['ops'] as String).readAsStringSync();
    final out = (argResults!['output'] as String?) ?? input;
    final bytes = applyOpsBytes(_readBytes(input), opsJson);
    File(out).writeAsBytesSync(bytes);
    stdout.writeln('patched $out (${bytes.length} bytes)');
    return 0;
  }
}

class _RenderCommand extends Command<int> {
  _RenderCommand() {
    argParser
      ..addOption('input', abbr: 'i', help: 'Input .vsdx path.', mandatory: true)
      ..addOption('output', abbr: 'o', help: 'Output .svg path.', mandatory: true);
  }
  @override
  String get name => 'render';
  @override
  String get description => 'Render a .vsdx to SVG (headless).';

  @override
  int run() {
    final doc = const DocumentParser().parse(_readBytes(argResults!['input'] as String));
    final svg = VsdxToSvgSerializer().serializeDocument(doc);
    final out = argResults!['output'] as String;
    File(out).writeAsStringSync(svg);
    stdout.writeln('rendered $out (${svg.length} bytes, ${doc.pages.length} pages)');
    return 0;
  }
}

class _ToMermaidCommand extends Command<int> {
  _ToMermaidCommand() {
    argParser
      ..addOption('input', abbr: 'i', help: 'Input .vsdx path.', mandatory: true)
      ..addOption('output',
          abbr: 'o', help: 'Output .md path (prints to stdout if omitted).')
      ..addFlag('fenced',
          help: 'Wrap each page in a ```mermaid fence.', defaultsTo: false);
  }
  @override
  String get name => 'to-mermaid';
  @override
  String get description => 'Convert a .vsdx to a Mermaid flowchart (structural).';

  @override
  int run() {
    final doc = const DocumentParser().parse(_readBytes(argResults!['input'] as String));
    final mmd = documentToMermaid(doc, fenced: argResults!['fenced'] as bool);
    final out = argResults!['output'] as String?;
    if (out == null) {
      stdout.write(mmd);
    } else {
      File(out).writeAsStringSync(mmd);
      stdout.writeln('wrote $out (${mmd.length} bytes)');
    }
    return 0;
  }
}

class _ValidateCommand extends Command<int> {
  _ValidateCommand() {
    argParser
      ..addOption('input', abbr: 'i', help: 'Input .vsdx path.', mandatory: true)
      ..addFlag('strict',
          help: 'Exit non-zero on warnings too (default: errors only).',
          defaultsTo: false);
  }
  @override
  String get name => 'validate';
  @override
  String get description => 'Structural lint of a .vsdx.';

  @override
  int run() {
    final doc = const DocumentParser().parse(_readBytes(argResults!['input'] as String));
    final issues = validateDocument(doc);
    for (final i in issues) {
      stdout.writeln(i);
    }
    final errors = issues.where((i) => i.severity == 'error').length;
    final warnings = issues.length - errors;
    stdout.writeln('$errors error(s), $warnings warning(s)');
    final strict = argResults!['strict'] as bool;
    return errors > 0 || (strict && warnings > 0) ? 1 : 0;
  }
}

class _ExplainCommand extends Command<int> {
  _ExplainCommand() {
    argParser
      ..addOption('input', abbr: 'i', help: 'Input .vsdx path.', mandatory: true)
      ..addOption('output',
          abbr: 'o', help: 'Output .md path (prints to stdout if omitted).');
  }
  @override
  String get name => 'explain';
  @override
  String get description => 'Describe a .vsdx as structured Markdown.';

  @override
  int run() {
    final doc = const DocumentParser().parse(_readBytes(argResults!['input'] as String));
    final md = explainDocument(doc);
    final out = argResults!['output'] as String?;
    if (out == null) {
      stdout.write(md);
    } else {
      File(out).writeAsStringSync(md);
      stdout.writeln('wrote $out (${md.length} bytes)');
    }
    return 0;
  }
}

class _ShapesCommand extends Command<int> {
  _ShapesCommand() {
    argParser.addOption('limit', help: 'Max results.', defaultsTo: '20');
  }
  @override
  String get name => 'shapes';
  @override
  String get description => 'Search the stencil catalog (e.g. `shapes search db`).';

  @override
  int run() {
    final rest = argResults!.rest;
    final query = rest.isEmpty
        ? ''
        : (rest.first == 'search' ? rest.skip(1).join(' ') : rest.join(' '));
    final limit = int.tryParse(argResults!['limit'] as String) ?? 20;
    final hits = searchStencils(query, limit: limit);
    for (final e in hits) {
      final aliases = e.aliases.isEmpty ? '' : ' (aka ${e.aliases.join(', ')})';
      stdout.writeln('${e.name.padRight(14)} [${e.group}]$aliases');
    }
    return 0;
  }
}

class _VersionCommand extends Command<int> {
  @override
  String get name => 'version';
  @override
  String get description => 'Print the engine version.';
  @override
  int run() {
    stdout.writeln('vsdxtool (engine $kVsdxEngineVersion)');
    return 0;
  }
}

String _readAllStdin() {
  final buf = StringBuffer();
  String? line;
  while ((line = stdin.readLineSync(encoding: utf8)) != null) {
    buf.writeln(line);
  }
  return buf.toString();
}
