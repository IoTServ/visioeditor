import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

List<String> _fixtureNames() => Directory('test/fixtures')
    .listSync()
    .whereType<File>()
    .map((f) => f.uri.pathSegments.last)
    .where((n) => n.endsWith('.vsdx'))
    .toList()
  ..sort();

/// Total number of `<Row>`s under a shape's *own* `<Section N="Geometry">`
/// blocks, summed over every page part. Master geometry lives in a different
/// part and is intentionally excluded.
int _rawOwnGeometryRows(VsdxPackage pkg) {
  var total = 0;
  for (final part in pkg.allPartNames) {
    if (!part.endsWith('.xml') ||
        !part.contains('pages/page') ||
        part.endsWith('pages.xml')) {
      continue;
    }
    final xml = pkg.readPartXml(part);
    if (xml == null) continue;
    for (final shape in xml.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'Shape')) {
      for (final sec in shape.childElements.where((e) =>
          e.name.local == 'Section' && e.getAttribute('N') == 'Geometry')) {
        total += sec.childElements.where((e) => e.name.local == 'Row').length;
      }
    }
  }
  return total;
}

/// Total number of parsed [VsdxPathCommand]s across every shape (recursing
/// into groups).
int _parsedGeometryCommands(VsdxDocument doc) {
  var total = 0;
  void walk(VsdxShape s) {
    for (final g in s.geometries) {
      total += g.commands.length;
    }
    for (final c in s.children) {
      walk(c);
    }
  }

  for (final p in doc.pages) {
    for (final s in p.shapes) {
      walk(s);
    }
  }
  return total;
}

bool _hasMasters(VsdxPackage pkg) =>
    pkg.allPartNames.any((p) => p.contains('masters/'));

void main() {
  const parser = DocumentParser();

  test('opens the OPC package of test1.vsdx', () {
    final pkg = VsdxPackage.open(_fixture('test1.vsdx'));
    expect(pkg.allPartNames, isNotEmpty);
  });

  test('parses test1.vsdx into a non-empty document', () {
    final doc = parser.parse(_fixture('test1.vsdx'));
    expect(doc.pages, isNotEmpty);
    expect(doc.pages.first.shapes, isNotEmpty);
  });

  test('parses rectangle + line sample with geometry', () {
    final doc = parser.parse(_fixture('test9_rect_and_line.vsdx'));
    expect(doc.pages, isNotEmpty);
    final shapes = doc.pages.first.shapes;
    expect(shapes, isNotEmpty);
    // page carries a positive extent (inches)
    expect(doc.pages.first.widthInches, greaterThan(0));
    expect(doc.pages.first.heightInches, greaterThan(0));
  });

  test('parses connectors sample', () {
    final doc = parser.parse(_fixture('test4_connectors.vsdx'));
    expect(doc.pages, isNotEmpty);
  });

  test('parses the bundled workflow.vsdx sample', () {
    final doc = parser.parse(_fixture('workflow.vsdx'));
    expect(doc.pages, isNotEmpty);
    expect(doc.pages.first.shapes, isNotEmpty);
  });

  // --- libvisio parity: every fixture parses, and no geometry is dropped ----
  //
  // Test plan: for each bundled fixture we (a) smoke-parse it and assert the
  // page has a positive extent, and (b) assert that every geometry `<Row>` the
  // shape owns produced a parsed path command — i.e. the parser recognises the
  // same geometry vocabulary libvisio does. (Fixtures whose shapes inherit
  // geometry from masters live in a separate part, so the strict row==command
  // count only applies to the master-free files.)
  group('fixture smoke + geometry coverage', () {
    final names = _fixtureNames();

    test('there are fixtures to check', () => expect(names, isNotEmpty));

    for (final name in names) {
      test('$name parses with a positive page extent', () {
        final doc = parser.parse(_fixture(name));
        expect(doc.pages, isNotEmpty, reason: name);
        for (final p in doc.pages) {
          expect(p.widthInches, greaterThan(0), reason: '$name: ${p.name} w');
          expect(p.heightInches, greaterThan(0), reason: '$name: ${p.name} h');
        }
      });

      test('$name drops no geometry rows (parsed commands == own rows)', () {
        final bytes = _fixture(name);
        final pkg = VsdxPackage.open(bytes);
        if (_hasMasters(pkg)) return; // inherited geometry, counts diverge
        final rawRows = _rawOwnGeometryRows(pkg);
        final parsed = _parsedGeometryCommands(parser.parse(bytes));
        expect(parsed, rawRows,
            reason: '$name: parsed $parsed path commands for $rawRows '
                'geometry <Row>s — an unhandled row type was dropped');
      });
    }
  });

  test('workflow.vsdx keeps its RelCubBezTo (cubic Bézier) segments', () {
    final doc = parser.parse(_fixture('workflow.vsdx'));
    var rel = 0;
    void walk(VsdxShape s) {
      for (final g in s.geometries) {
        rel += g.commands.whereType<RelCubBezTo>().length;
      }
      for (final c in s.children) {
        walk(c);
      }
    }

    for (final s in doc.pages.first.shapes) {
      walk(s);
    }
    // The rounded start/end shapes contribute eight RelCubBezTo rows in total.
    expect(rel, 8);
  });

  // Regression: a cell's `V` is always in Visio's internal units (inches for
  // length), and the `U` attribute is only the *display* unit. workflow.vsdx
  // stores `PageWidth V="11.9583" U="MM"` (= 11.96 inches shown as mm) and
  // `Size V="0.138889" U="PT"` (= 10 pt). The parser must take `V` verbatim,
  // not rescale it by `U` — otherwise the page came out ~25x too small and text
  // ~72x too small.
  group('cell V is read in internal units (U is display-only)', () {
    test('page size with U="MM" parses as inches, not millimetres', () {
      final page = parser.parse(_fixture('workflow.vsdx')).pages.first;
      expect(page.widthInches, closeTo(11.9583, 0.01));
      expect(page.heightInches, closeTo(7.14583, 0.01));
    });

    test('font size with U="PT" parses as internal inches (10 pt)', () {
      final page = parser.parse(_fixture('workflow.vsdx')).pages.first;
      final withText =
          page.shapes.firstWhere((s) => s.richText.runs.isNotEmpty);
      final pt = withText.richText.runs.first.charStyle.fontSizeInches * 72;
      expect(pt, closeTo(10.0, 0.2));
    });

    test('shape geometry stays in inches (U="IN" is identity)', () {
      final page = parser.parse(_fixture('workflow.vsdx')).pages.first;
      final s = page.shapes.firstWhere((s) => !s.is1D);
      // Rounded to real Visio inch extents, not scaled fractions of them.
      expect(s.width, greaterThan(0.5));
      expect(s.height, greaterThan(0.2));
    });
  });
}
