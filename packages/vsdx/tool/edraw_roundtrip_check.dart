/// End-to-end format check for the editor pipeline:
/// - `.vsdx` open → light edit → write → reopen
/// - `.vsd` import → synthesise `.vsdx` → light edit → write → reopen
/// - Structural checks Edraw historically cares about
///
/// Output: `~/Desktop/visioeditor_edraw_check/`
///
/// Note: binary `.vsd` *write-back* is not implemented (libvisio is read-only;
/// no OLE2 ShapeSheet writer). Save path is always `.vsdx`.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

void main() {
  final outDir = Directory(
    '${Platform.environment['HOME']}/Desktop/visioeditor_edraw_check',
  );
  if (outDir.existsSync()) outDir.deleteSync(recursive: true);
  outDir.createSync(recursive: true);

  final report = StringBuffer()
    ..writeln('# Visioeditor format round-trip / Edraw check')
    ..writeln('out: ${outDir.path}')
    ..writeln('')
    ..writeln('## Capability')
    ..writeln('- Open: `.vsdx` (OPC) + legacy `.vsd` (OLE2)')
    ..writeln('- Edit: shared `VsdxDocument` model')
    ..writeln('- Save / Save As: **`.vsdx` only** (no binary `.vsd` writer)')
    ..writeln('');

  report.writeln('## .vsdx round-trip');
  for (final f in _collect('*.vsdx', [
    Directory('test/fixtures'),
    Directory('../../test/fixtures'), // when run from packages/vsdx
  ])) {
    report.writeln(_checkVsdx(f, outDir));
  }

  report.writeln('');
  report.writeln('## .vsd → .vsdx import / edit / save');
  for (final f in _collect('*.vsd', [
    Directory('../../third_party/libvisio/src/test/data'),
    Directory('test/fixtures/vsd'),
    Directory('test/fixtures/vsd/external'),
  ])) {
    report.writeln(_checkVsd(f, outDir));
  }

  final path = '${outDir.path}/REPORT.md';
  File(path).writeAsStringSync(report.toString());
  print(report);
  print('Wrote $path');
}

List<File> _collect(String globSuffix, List<Directory> dirs) {
  final seen = <String>{};
  final out = <File>[];
  final ext = globSuffix.replaceAll('*', '');
  for (final d in dirs) {
    if (!d.existsSync()) continue;
    for (final e in d.listSync(recursive: true).whereType<File>()) {
      if (!e.path.toLowerCase().endsWith(ext)) continue;
      final name = e.uri.pathSegments.last;
      if (!seen.add(name)) continue;
      out.add(e);
    }
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

String _checkVsdx(File f, Directory outDir) {
  final name = f.uri.pathSegments.last;
  final stem = name.replaceAll(RegExp(r'\.vsdx$', caseSensitive: false), '');
  try {
    final bytes = f.readAsBytesSync();
    final parsed = parseVisio(bytes);
    expectTrue(!parsed.importedFromVsd, 'expected OPC');
    final edited = _nudgeFirstShape(parsed.document);
    final written = const VsdxWriter().write(
      originalBytes: parsed.originalBytes,
      edited: edited,
    );
    final outPath = '${outDir.path}/vsdx_$stem.vsdx';
    File(outPath).writeAsBytesSync(written);
    final reopened = parseVisio(written);
    expectTrue(!reopened.importedFromVsd, 'reopen OPC');
    final checks = _edrawStructuralChecks(written);
    final line =
        '- OK $name → vsdx_$stem.vsdx pages=${reopened.document.pages.length} '
        'shapes=${_countShapes(reopened.document)} edraw=[${checks.join(", ")}]';
    print(line);
    return line;
  } catch (e) {
    final line = '- FAIL $name: $e';
    print(line);
    return line;
  }
}

String _checkVsd(File f, Directory outDir) {
  final name = f.uri.pathSegments.last;
  final stem = name.replaceAll(RegExp(r'\.vsd$', caseSensitive: false), '');
  try {
    final parsed = parseVisio(f.readAsBytesSync());
    expectTrue(parsed.importedFromVsd, 'expected VSD import');
    final synthPath = '${outDir.path}/from_vsd_$stem.vsdx';
    File(synthPath).writeAsBytesSync(parsed.originalBytes);

    final edited = _nudgeFirstShape(parsed.document);
    final written = const VsdxWriter().write(
      originalBytes: parsed.originalBytes,
      edited: edited,
    );
    final editedPath = '${outDir.path}/from_vsd_${stem}_edited.vsdx';
    File(editedPath).writeAsBytesSync(written);

    final reopened = parseVisio(written);
    expectTrue(!reopened.importedFromVsd, 'edited must be OPC');
    final checks = _edrawStructuralChecks(written);
    final line =
        '- OK $name → from_vsd_$stem.vsdx pages=${parsed.document.pages.length} '
        'shapes=${_countShapes(parsed.document)} '
        'edraw=[${checks.join(", ")}]';
    print(line);
    return line;
  } catch (e) {
    final line = '- FAIL $name: $e';
    print(line);
    return line;
  }
}

VsdxDocument _nudgeFirstShape(VsdxDocument doc) {
  if (doc.pages.isEmpty || doc.pages.first.shapes.isEmpty) return doc;
  final page = doc.pages.first;
  final s0 = page.shapes.first;
  final moved = s0.copyWith(pinX: s0.pinX + 0.05);
  return doc.copyWith(
    pages: [
      page.copyWith(shapes: [moved, ...page.shapes.skip(1)]),
      ...doc.pages.skip(1),
    ],
  );
}

void expectTrue(bool v, String msg) {
  if (!v) throw StateError(msg);
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
      if (texts.isNotEmpty && texts.first.innerText.trim().isNotEmpty) {
        withText++;
        final hasChar = sh.childElements.any(
          (c) =>
              c.name.local == 'Section' && c.getAttribute('N') == 'Character',
        );
        if (!hasChar) missingChar++;
      }
    }
    if (missingLoc > 0) {
      issues.add('missing-LocPin:$missingLoc/${shapes.length}');
    }
    if (missingChar > 0) {
      issues.add('text-no-Character:$missingChar/$withText');
    }
    if (missingFg > 0) issues.add('fill-no-Foregnd:$missingFg');
  }
  if (issues.isEmpty) issues.add('ok');
  return issues;
}
