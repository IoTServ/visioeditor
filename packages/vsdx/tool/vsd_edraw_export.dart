/// Batch: `.vsd` → `parseVisio` → write `.vsdx` + structural Edraw checks.
///
/// Output: `~/Desktop/vsd_edraw_export/`
// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

void main(List<String> args) {
  final outDir = Directory(
    '${Platform.environment['HOME']}/Desktop/vsd_edraw_export',
  );
  if (outDir.existsSync()) {
    outDir.deleteSync(recursive: true);
  }
  outDir.createSync(recursive: true);

  final srcDirs = <Directory>[
    Directory('../../third_party/libvisio/src/test/data'),
    Directory('test/fixtures/vsd'),
    Directory('test/fixtures/vsd/external'),
  ];
  final seen = <String>{};
  final files = <File>[];
  for (final d in srcDirs) {
    if (!d.existsSync()) continue;
    for (final f in d.listSync().whereType<File>()) {
      if (!f.path.endsWith('.vsd')) continue;
      final name = f.uri.pathSegments.last;
      if (!seen.add(name)) continue;
      files.add(f);
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));

  final report = StringBuffer()
    ..writeln('# VSD → VSDX Edraw export report')
    ..writeln('out: ${outDir.path}')
    ..writeln('');

  for (final f in files) {
    final name = f.uri.pathSegments.last;
    final stem = name.replaceAll(RegExp(r'\.vsd$', caseSensitive: false), '');
    final outPath = '${outDir.path}/$stem.vsdx';
    try {
      final parsed = parseVisio(f.readAsBytesSync());
      File(outPath).writeAsBytesSync(parsed.originalBytes);

      // Light edit → rewrite (exercises writer LocPin / Character / NoFill).
      final editedPath = '${outDir.path}/${stem}_edited.vsdx';
      final doc = parsed.document;
      if (doc.pages.isNotEmpty && doc.pages.first.shapes.isNotEmpty) {
        final page = doc.pages.first;
        final s0 = page.shapes.first;
        final moved = s0.copyWith(pinX: s0.pinX + 0.05);
        final newPage = page.copyWith(
          shapes: [
            moved,
            ...page.shapes.skip(1),
          ],
        );
        final edited = doc.copyWith(pages: [newPage, ...doc.pages.skip(1)]);
        final rewritten = const VsdxWriter().write(
          originalBytes: parsed.originalBytes,
          edited: edited,
        );
        File(editedPath).writeAsBytesSync(rewritten);
      }

      final checks = _edrawStructuralChecks(File(outPath).readAsBytesSync());
      final line =
          '$name → $stem.vsdx pages=${parsed.document.pages.length} '
          'shapes=${_countShapes(parsed.document)} '
          'title=${parsed.document.title ?? "-"} '
          'edraw=[${checks.join(", ")}]';
      print(line);
      report.writeln('- $line');
    } catch (e, st) {
      print('FAIL $name: $e');
      report.writeln('- FAIL $name: $e');
      stderr.writeln(st);
    }
  }

  File('${outDir.path}/REPORT.md').writeAsStringSync(report.toString());
  print('\nWrote ${outDir.path}');
}

int _countShapes(VsdxDocument doc) {
  var n = 0;
  void walk(VsdxShape s) {
    n++;
    for (final c in s.children) {
      walk(c);
    }
  }

  for (final p in doc.pages) {
    for (final s in p.shapes) {
      walk(s);
    }
  }
  return n;
}

/// Cheap structural checks Edraw historically cares about.
List<String> _edrawStructuralChecks(Uint8List vsdx) {
  final issues = <String>[];
  final zip = ZipDecoder().decodeBytes(vsdx);
  final names = zip.map((e) => e.name).toSet();
  if (!names.any((n) => n.endsWith('docProps/core.xml'))) {
    issues.add('missing-core');
  }
  ArchiveFile? docXml;
  ArchiveFile? pagesXml;
  ArchiveFile? page1;
  for (final e in zip) {
    if (e.name.endsWith('visio/document.xml')) docXml = e;
    if (e.name.endsWith('visio/pages/pages.xml')) pagesXml = e;
    if (e.name.endsWith('visio/pages/page1.xml')) page1 = e;
  }
  if (docXml == null) {
    issues.add('missing-document');
    return issues;
  }
  final docStr = utf8.decode(docXml.content as List<int>);
  if (!docStr.contains('StyleSheets')) issues.add('no-StyleSheets');
  if (!docStr.contains('FaceNames')) issues.add('no-FaceNames');

  if (pagesXml != null) {
    final pagesStr = utf8.decode(pagesXml.content as List<int>);
    if (!pagesStr.contains('ViewCenterX')) issues.add('no-ViewCenter');
  } else {
    issues.add('no-pages.xml');
  }

  if (page1 != null) {
    final pageStr = utf8.decode(page1.content as List<int>);
    final xml = XmlDocument.parse(pageStr);
    final shapes = xml.findAllElements('Shape').toList();
    var missingLoc = 0;
    var missingChar = 0;
    var withText = 0;
    var missingFg = 0;
    for (final sh in shapes) {
      final hasLoc = sh.childElements.any(
        (c) => c.name.local == 'Cell' && c.getAttribute('N') == 'LocPinX',
      );
      if (!hasLoc) missingLoc++;
      final hasPattern = sh.childElements.any(
        (c) =>
            c.name.local == 'Cell' &&
            c.getAttribute('N') == 'FillPattern' &&
            c.getAttribute('V') != '0',
      );
      final hasFg = sh.childElements.any(
        (c) => c.name.local == 'Cell' && c.getAttribute('N') == 'FillForegnd',
      );
      if (hasPattern && !hasFg) missingFg++;
      final texts = sh.findElements('Text');
      if (texts.isNotEmpty &&
          texts.first.innerText.trim().isNotEmpty) {
        withText++;
        final hasChar = sh.childElements.any(
          (c) =>
              c.name.local == 'Section' && c.getAttribute('N') == 'Character',
        );
        if (!hasChar) missingChar++;
      }
    }
    if (missingLoc > 0) issues.add('missing-LocPin:$missingLoc/${shapes.length}');
    if (missingChar > 0) {
      issues.add('text-no-Character:$missingChar/$withText');
    }
    if (missingFg > 0) issues.add('fill-no-Foregnd:$missingFg');
  }
  if (issues.isEmpty) issues.add('ok');
  return issues;
}
