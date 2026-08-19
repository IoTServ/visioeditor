// Corpus-wide parity probe: parse → render → round-trip every Visio file we can
// find, and diff the result against libvisio (the reference importer LibreOffice
// itself drives through `librevenge`). Reports one line per file so a coverage
// hole shows up as a row instead of a silent skip.
//
// Usage:
//   dart run tool/libvisio_parity_audit.dart [--verbose] [--features] [filter]
//
// `--features` switches to a per-drawing-feature diff: libvisio renders through
// `drawPath` / `drawGraphicObject` plus a text stack, so every other "type" is
// carried by the style properties it sets (gradient, hatch or bitmap fill,
// dashes, markers, shadow, text decoration). A file where libvisio paints one
// of those and we paint none is a type we silently drop.
//
// The libvisio columns need native/libvisio_shim.dylib (native/build.sh).
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:vsdx/vsdx.dart';

import '../test/support/libvisio_features.dart';
import '../test/support/libvisio_oracle.dart';

const _sourceDirectories = <String>[
  '../../third_party/libvisio/src/test/data',
  'test/fixtures',
  'test/fixtures/vsd',
  'test/fixtures/vsd/external',
  '../../assets/examples',
];

const _visioExtensions = <String>{
  '.vsd', '.vss', '.vst', // binary
  '.vdx', '.vsx', '.vtx', // DiagramML
  '.vsdx', '.vsdm', '.vstx', '.vstm', '.vssx', '.vssm', // OPC
};

void main(List<String> args) {
  final verbose = args.contains('--verbose');
  final filter = args.firstWhere(
    (a) => !a.startsWith('--'),
    orElse: () => '',
  );
  final oracle = LibvisioOracle.tryLoad();
  if (oracle == null) {
    print('WARNING: libvisio shim missing — libvisio columns will read "n/a"');
  }

  final files = _collectFiles(filter);
  if (files.isEmpty) {
    stderr.writeln('no Visio files matched');
    exit(2);
  }

  if (args.contains('--features')) {
    _featureAudit(files, oracle, verbose: verbose);
    return;
  }

  final problems = <String>[];
  print(
    '${'file'.padRight(46)}'
    'pages  shapes  svg     roundtrip  libvisio  lv-roundtrip',
  );
  print('-' * 108);

  for (final file in files) {
    final label = _label(file);
    final bytes = Uint8List.fromList(file.readAsBytesSync());

    VisioParseResult? parsed;
    try {
      parsed = parseVisio(bytes, sourceName: file.path);
    } catch (error) {
      problems.add('$label: parse failed: $error');
      print('${label.padRight(46)}PARSE FAIL  $error');
      continue;
    }

    final document = parsed.document;
    final shapes = _countShapes(document);
    final svgReport = _renderReport(document, label, problems);
    final roundTrip = _roundTripReport(parsed, label, problems);
    final lv = _oracleReport(oracle, bytes, document, label, problems,
        stencils: _isStencil(file.path));
    final lvRoundTrip = roundTrip.bytes == null
        ? 'skip'
        : _oracleReport(
            oracle,
            roundTrip.bytes!,
            document,
            '$label (saved)',
            problems,
          );

    print(
      '${label.padRight(46)}'
      '${'${document.pages.length}'.padRight(7)}'
      '${'$shapes'.padRight(8)}'
      '${svgReport.padRight(8)}'
      '${roundTrip.summary.padRight(11)}'
      '${lv.padRight(10)}'
      '$lvRoundTrip',
    );
  }

  print('');
  if (problems.isEmpty) {
    print('OK — ${files.length} files parsed, rendered and round-tripped');
    return;
  }
  print('${problems.length} problem(s):');
  for (final problem in problems) {
    print('  - $problem');
  }
  if (verbose) exit(1);
}

// --- feature diff -----------------------------------------------------------

void _featureAudit(
  List<File> files,
  LibvisioOracle? oracle, {
  required bool verbose,
}) {
  if (oracle == null) {
    stderr.writeln('--features needs the libvisio shim (native/build.sh)');
    exit(2);
  }
  final names = libvisioFeaturePatterns.keys.toList();
  final missing = <String, List<String>>{for (final n in names) n: <String>[]};
  final extra = <String, List<String>>{for (final n in names) n: <String>[]};
  var compared = 0;

  for (final file in files) {
    final label = _label(file);
    final bytes = Uint8List.fromList(file.readAsBytesSync());
    final referencePages = oracle.svgPages(bytes);
    if (referencePages == null) continue;

    final VsdxDocument document;
    try {
      document = parseVisio(bytes, sourceName: file.path).document;
    } catch (_) {
      continue;
    }
    // Compare whole documents: libvisio flattens background pages into the
    // pages that reference them, so a per-page pairing would report phantom
    // differences on every drawing that uses one.
    final ours = StringBuffer();
    for (final page in document.pages) {
      ours.write(
        VsdxToSvgSerializer().serializePage(
          page,
          theme: document.theme,
          images: document.images,
          underlayPage: document.backgroundFor(page),
        ),
      );
    }
    final reference = referencePages.join();
    compared++;

    for (final name in names) {
      final inReference =
          paintsLibvisioFeature(name, reference, libvisio: true);
      final inOurs =
          paintsLibvisioFeature(name, ours.toString(), libvisio: false);
      if (inReference && !inOurs) missing[name]!.add(label);
      if (inOurs && !inReference) extra[name]!.add(label);
    }
  }

  print('compared $compared files against libvisio\n');
  print('feature      libvisio-only  ours-only');
  print('-' * 60);
  for (final name in names) {
    print(
      '${name.padRight(13)}'
      '${'${missing[name]!.length}'.padRight(15)}'
      '${extra[name]!.length}',
    );
  }

  var gaps = 0;
  for (final name in names) {
    if (missing[name]!.isEmpty) continue;
    gaps += missing[name]!.length;
    print('\n$name missing in ${missing[name]!.length} file(s):');
    for (final label in missing[name]!) {
      print('  - $label');
    }
  }
  if (verbose) {
    for (final name in names) {
      if (extra[name]!.isEmpty) continue;
      print('\n$name drawn only by us in ${extra[name]!.length} file(s):');
      for (final label in extra[name]!) {
        print('  - $label');
      }
    }
  }
  if (gaps == 0) {
    print('\nOK — every feature libvisio paints is painted here too');
  }
}

// --- collection -------------------------------------------------------------

List<File> _collectFiles(String filter) {
  final out = <File>[];
  for (final directory in _sourceDirectories) {
    final dir = Directory(directory);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      if (dot < 0) continue;
      if (!_visioExtensions.contains(name.substring(dot).toLowerCase())) {
        continue;
      }
      if (filter.isNotEmpty && !name.contains(filter)) continue;
      out.add(entity);
    }
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

String _label(File file) {
  final segments = file.uri.pathSegments;
  final name = segments.last;
  final parent = segments.length > 1 ? segments[segments.length - 2] : '';
  return parent == 'data' ? 'upstream/$name' : '$parent/$name';
}

bool _isStencil(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.vss') ||
      lower.endsWith('.vssx') ||
      lower.endsWith('.vssm') ||
      lower.endsWith('.vsx');
}

// --- reports ----------------------------------------------------------------

int _countShapes(VsdxDocument document) {
  var total = 0;
  void walk(VsdxShape shape) {
    total++;
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final page in document.pages) {
    for (final shape in page.shapes) {
      walk(shape);
    }
  }
  return total;
}

String _renderReport(
  VsdxDocument document,
  String label,
  List<String> problems,
) {
  var drawn = 0;
  for (final page in document.pages) {
    if (page.isBackgroundPage) continue;
    final String svg;
    try {
      svg = VsdxToSvgSerializer().serializePage(
        page,
        theme: document.theme,
        images: document.images,
        underlayPage: document.backgroundFor(page),
      );
    } catch (error) {
      problems.add('$label: SVG render failed on ${page.name}: $error');
      return 'FAIL';
    }
    final elements = _drawableCount(svg);
    if (elements == 0 && _pageHasGeometry(page)) {
      problems.add('$label: page "${page.name}" rendered no drawable element');
    }
    drawn += elements;
  }
  return '$drawn';
}

int _drawableCount(String svg) => RegExp(
      r'<(path|rect|ellipse|circle|polygon|polyline|line|image|text)\b',
    ).allMatches(svg).length;

bool _pageHasGeometry(VsdxPage page) {
  bool walk(VsdxShape shape) {
    if (shape.geometries.any((g) => g.commands.isNotEmpty)) return true;
    if (shape.richText.plainText.trim().isNotEmpty) return true;
    if (shape.hasImage) return true;
    return shape.children.any(walk);
  }

  return page.shapes.any(walk);
}

class _RoundTrip {
  const _RoundTrip(this.summary, this.bytes);

  final String summary;
  final Uint8List? bytes;
}

_RoundTrip _roundTripReport(
  VisioParseResult parsed,
  String label,
  List<String> problems,
) {
  final Uint8List saved;
  try {
    saved = const VsdxWriter().write(
      originalBytes: parsed.originalBytes,
      edited: parsed.document,
    );
  } catch (error) {
    problems.add('$label: write failed: $error');
    return const _RoundTrip('WRITE', null);
  }
  final VsdxDocument reopened;
  try {
    reopened = const DocumentParser().parse(saved);
  } catch (error) {
    problems.add('$label: reopen failed: $error');
    return _RoundTrip('REOPEN', saved);
  }
  final before = parsed.document;
  if (reopened.pages.length != before.pages.length) {
    problems.add(
      '$label: round-trip pages ${reopened.pages.length} != '
      '${before.pages.length}',
    );
    return _RoundTrip('pages!', saved);
  }
  final beforeText = _visibleText(before);
  final afterText = _visibleText(reopened);
  if (beforeText != afterText) {
    problems.add('$label: round-trip lost text');
    return _RoundTrip('text!', saved);
  }
  final beforeShapes = _countShapes(before);
  final afterShapes = _countShapes(reopened);
  if (afterShapes < beforeShapes) {
    problems.add(
      '$label: round-trip shapes $afterShapes < $beforeShapes',
    );
    return _RoundTrip('shapes!', saved);
  }
  return _RoundTrip('ok', saved);
}

String _visibleText(VsdxDocument document) {
  final buffer = StringBuffer();
  void walk(VsdxShape shape) {
    if (!shape.richText.textBlock.hideText) {
      buffer.write(shape.richText.plainText.replaceAll(RegExp(r'\s+'), ''));
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final page in document.pages) {
    for (final shape in page.shapes) {
      walk(shape);
    }
  }
  final chars = buffer.toString().split('')..sort();
  return chars.join();
}

String _oracleReport(
  LibvisioOracle? oracle,
  Uint8List bytes,
  VsdxDocument document,
  String label,
  List<String> problems, {
  bool stencils = false,
}) {
  if (oracle == null) return 'n/a';
  final pages =
      stencils ? oracle.stencilSvgPages(bytes) : oracle.svgPages(bytes);
  if (pages == null) return 'reject';
  if (pages.length != document.pages.length) {
    return '${pages.length}p!';
  }
  return '${pages.length}p';
}
