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
  if (args.contains('--roundtrip')) {
    _roundTripAudit(files, oracle, verbose: verbose);
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

// --- round-trip through the reference consumer -------------------------------

/// What libvisio sees in a document, reduced to the things a save must not
/// change. Everything here is read out of libvisio's own SVG, so the two sides
/// are measured by the same importer LibreOffice uses.
class _Seen {
  const _Seen({
    required this.pages,
    required this.sizes,
    required this.text,
    required this.features,
    required this.drawn,
  });

  final int pages;
  final List<String> sizes;
  final String text;
  final Set<String> features;
  final int drawn;

  static _Seen of(List<String> svgPages) {
    final joined = svgPages.join();
    final sizes = <String>[];
    for (final page in svgPages) {
      final m = RegExp(r'width="([0-9.]+)in"\s+height="([0-9.]+)in"')
          .firstMatch(page);
      sizes.add(m == null
          ? '?'
          : '${double.parse(m.group(1)!).toStringAsFixed(2)}x'
              '${double.parse(m.group(2)!).toStringAsFixed(2)}');
    }
    // Case-folded letters only. A save legitimately reformats field values —
    // libvisio reads `300.0000` straight out of a legacy VSD and `25 ft` back
    // out of the VSDX we write, because the VSDX carries the format the binary
    // record only implied — and it applies the StrUpper / StrLower formats
    // that libvisio ignores. Digits, punctuation and case therefore move
    // around; losing a whole label shows up in the letters either way.
    final characters = <String>[];
    for (final m in RegExp(
      r'<(?:svg:)?tspan\b[^>]*>(.*?)</(?:svg:)?tspan>',
      dotAll: true,
    ).allMatches(joined)) {
      characters.addAll(
        RegExp(r'\p{L}', unicode: true)
            .allMatches(_unescape(m.group(1)!).toLowerCase())
            .map((c) => c.group(0)!),
      );
    }
    characters.sort();
    return _Seen(
      pages: svgPages.length,
      sizes: sizes,
      text: characters.join(),
      features: <String>{
        for (final feature in libvisioFeaturePatterns.keys)
          if (paintsLibvisioFeature(feature, joined, libvisio: true)) feature,
      },
      drawn: RegExp(r'<svg:(?:path|polyline|polygon|ellipse|rect|image)\b')
          .allMatches(joined)
          .length,
    );
  }
}

void _roundTripAudit(
  List<File> files,
  LibvisioOracle? oracle, {
  required bool verbose,
}) {
  if (oracle == null) {
    stderr.writeln('--roundtrip needs the libvisio shim (native/build.sh)');
    exit(2);
  }
  print('Comparing what libvisio sees before and after a save.\n');
  print(
    '${'file'.padRight(46)}'
    '${'pages'.padRight(12)}${'size'.padRight(8)}'
    '${'text'.padRight(8)}${'features'.padRight(10)}drawn',
  );
  print('-' * 96);

  final problems = <String>[];
  var compared = 0;

  for (final file in files) {
    final label = _label(file);
    final bytes = Uint8List.fromList(file.readAsBytesSync());
    final beforePages = oracle.svgPages(bytes);
    if (beforePages == null) continue;

    final VisioParseResult parsed;
    try {
      parsed = parseVisio(bytes, sourceName: file.path);
    } catch (error) {
      problems.add('$label: parse failed: $error');
      continue;
    }
    final Uint8List saved;
    try {
      saved = const VsdxWriter().write(
        originalBytes: parsed.originalBytes,
        edited: parsed.document,
      );
    } catch (error) {
      problems.add('$label: write failed: $error');
      continue;
    }
    final afterPages = oracle.svgPages(saved);
    if (afterPages == null) {
      problems.add('$label: libvisio cannot reopen the saved package');
      print('${label.padRight(46)}REOPEN FAIL');
      continue;
    }

    final before = _Seen.of(beforePages);
    final after = _Seen.of(afterPages);
    compared++;

    final lostFeatures = before.features.difference(after.features);
    // A saved package that draws fewer objects has dropped geometry; more is
    // usually the writer expanding a master reference into explicit shapes.
    final drawnRatio = before.drawn == 0 ? 1.0 : after.drawn / before.drawn;
    // BeginArrowSize is not a token, so a save may bake markers into Geometry.
    if (lostFeatures.remove('marker') && drawnRatio < 0.95) {
      lostFeatures.add('marker');
    }

    // Compare the saved page count with our own model, not with libvisio's
    // reading of the source. `recursion-cycle.vsdx` points its page
    // relationship back at `pages.xml`, and libvisio follows the loop into a
    // phantom second page (LibreOffice reports three); the writer must simply
    // emit the one page we parsed.
    if (after.pages != parsed.document.pages.length) {
      problems.add(
        '$label: saved ${after.pages} pages, model has '
        '${parsed.document.pages.length}',
      );
    }
    // A source without a PageSheet has no page size at all, so libvisio
    // reports 0x0 and LibreOffice falls back to A4 for both the original and
    // the saved package. There is nothing to preserve in that case.
    final sizeChanged = !before.sizes.every(_isDegenerateSize) &&
        before.sizes.join(',') != after.sizes.join(',');
    if (sizeChanged) {
      problems.add(
        '$label: page size ${before.sizes.join(",")} → ${after.sizes.join(",")}',
      );
    }
    final lostText = _missingFrom(before.text, after.text);
    if (lostText.isNotEmpty) {
      problems.add('$label: text lost "$lostText"');
    }
    if (lostFeatures.isNotEmpty) {
      problems.add('$label: lost ${lostFeatures.join(", ")}');
    }
    if (drawnRatio < 0.95) {
      problems.add(
        '$label: drawn objects ${before.drawn} → ${after.drawn}',
      );
    }

    final pagesWrong = after.pages != parsed.document.pages.length;
    final row = '${label.padRight(46)}'
        '${'${before.pages}→${after.pages}'.padRight(12)}'
        '${(sizeChanged ? "DIFF" : "ok").padRight(8)}'
        '${(lostText.isEmpty ? "ok" : "LOST").padRight(8)}'
        '${(lostFeatures.isEmpty ? "ok" : lostFeatures.join("/")).padRight(10)}'
        '${before.drawn}→${after.drawn}';
    if (verbose ||
        pagesWrong ||
        lostText.isNotEmpty ||
        lostFeatures.isNotEmpty ||
        drawnRatio < 0.95 ||
        sizeChanged) {
      print(row);
    }
  }

  print('\ncompared $compared files');
  if (problems.isEmpty) {
    print('OK — a save preserves everything libvisio reads back');
    return;
  }
  print('${problems.length} problem(s):');
  for (final problem in problems) {
    print('  - $problem');
  }
}

/// libvisio reports `0.00x0.00` for a page whose source carries no PageSheet.
bool _isDegenerateSize(String size) => size == '0.00x0.00' || size == '?';

String _unescape(String xml) => xml
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// Characters present in the sorted multiset [before] but not in [after].
String _missingFrom(String before, String after) {
  final remaining = after.split('');
  final lost = StringBuffer();
  for (final character in before.split('')) {
    final at = remaining.indexOf(character);
    if (at < 0) {
      lost.write(character);
    } else {
      remaining.removeAt(at);
    }
  }
  return lost.toString();
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
