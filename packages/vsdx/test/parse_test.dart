import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

Uint8List _withoutPart(Uint8List bytes, String partName) {
  final source = ZipDecoder().decodeBytes(bytes);
  final output = Archive();
  for (final file in source) {
    if (file.name == partName) continue;
    output.addFile(ArchiveFile(file.name, file.size, file.content));
  }
  return Uint8List.fromList(ZipEncoder().encode(output)!);
}

Uint8List _replacePart(
  Uint8List bytes,
  String partName,
  Uint8List replacement,
) {
  final source = ZipDecoder().decodeBytes(bytes);
  final output = Archive();
  for (final file in source) {
    if (file.name == partName) {
      output.addFile(ArchiveFile(file.name, replacement.length, replacement));
    } else {
      output.addFile(ArchiveFile(file.name, file.size, file.content));
    }
  }
  return Uint8List.fromList(ZipEncoder().encode(output)!);
}

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

  test('parses package with absent or malformed Content_Types like libvisio',
      () {
    final original = _fixture('test9_rect_and_line.vsdx');
    final before = parser.parse(original);
    final damagedPackages = <Uint8List>[
      _withoutPart(original, '[Content_Types].xml'),
      _replacePart(
        original,
        '[Content_Types].xml',
        Uint8List.fromList('<broken'.codeUnits),
      ),
    ];

    for (final damaged in damagedPackages) {
      final pkg = VsdxPackage.open(damaged);
      expect(pkg.resolveDocumentPartName(), '/visio/document.xml');
      expect(
        pkg.contentTypes.mimeFor('/visio/pages/page1.xml'),
        'application/xml',
      );
      expect(
          pkg.contentTypes.mimeFor('/visio/media/image1.webp'), 'image/webp');

      final after = parser.parse(damaged);
      expect(after.pages.length, before.pages.length);
      expect(after.pages.first.widthInches, before.pages.first.widthInches);
      expect(after.pages.first.heightInches, before.pages.first.heightInches);
      expect(after.pages.first.shapes.length, before.pages.first.shapes.length);
    }
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

  // Regression: a shape's text block is pinned by its *local* pin (TxtLocPin),
  // not its centre. workflow.vsdx's "开始"/"结束" pills pin the block by its top
  // (TxtLocPinY == TxtHeight), so without parsing TxtLocPin the label floated to
  // the top edge instead of centring in the pill.
  test('text block TxtLocPin is parsed and re-centres the label', () {
    final doc = parser.parse(_fixture('workflow.vsdx'));
    bool isStart(VsdxShape s) =>
        (s.richText.plainText).contains('开始') ||
        (s.text ?? '').contains('开始');
    final start = doc.pages.first.shapes.firstWhere(isStart);
    final b = start.richText.textBlock;

    expect(b.locPinYInches, isNotNull);
    // The pill pins the block by its top edge.
    expect(b.locPinYInches!, closeTo(start.height, 0.02));

    // Block centre = pin - locPin + size/2 must land on the shape centre, so
    // the (vertically-centred) label sits in the middle of the pill.
    final th = b.heightInches ?? start.height;
    final centreY = (b.pinYInches ?? start.height / 2) -
        (b.locPinYInches ?? th / 2) +
        th / 2;
    expect(centreY, closeTo(start.height / 2, 0.02));
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

  test('Master Character and inherited labels remain rich text', () {
    List<VsdxShape> flatten(VsdxDocument doc) {
      final out = <VsdxShape>[];
      void walk(VsdxShape shape) {
        out.add(shape);
        shape.children.forEach(walk);
      }

      for (final page in doc.pages) {
        page.shapes.forEach(walk);
      }
      return out;
    }

    for (final name in <String>[
      'test3_house.vsdx',
      'test4_connectors.vsdx',
    ]) {
      final sizes = <double>{
        for (final shape in flatten(parser.parse(_fixture(name))))
          for (final run in shape.richText.runs)
            if (run.text.trim().isNotEmpty)
              (run.charStyle.fontSizeInches * 72 * 2).round() / 2,
      };
      expect(sizes, contains(10.0), reason: '$name Master Character size');
    }

    for (final name in <String>[
      'test_master.vsdx',
      'test_master_multiple_child_shapes.vsdx',
    ]) {
      final inherited = flatten(parser.parse(_fixture(name)))
          .where((shape) =>
              (shape.masterId != null || shape.masterShapeId != null) &&
              (shape.text?.isNotEmpty ?? false))
          .toList();
      expect(inherited, isNotEmpty, reason: '$name inherited labels');
      for (final shape in inherited) {
        // `shape.text` is the legacy trimmed convenience value; richText is
        // the lossless source and retains xml:space="preserve" line endings.
        expect(shape.richText.plainText.trim(), shape.text!.trim(),
            reason: '$name shape ${shape.id} should retain Master text style');
      }
    }
  });

  test('connector Pin follows authoritative Begin/End cells', () {
    final page = parser.parse(_fixture('test4_connectors.vsdx')).pages.first;
    final connectors = page.shapes.where((shape) => shape.is1D).toList();
    expect(connectors, isNotEmpty);
    for (final shape in connectors) {
      expect(shape.pinX, closeTo((shape.beginX! + shape.endX!) * 0.5, 1e-9));
      expect(shape.pinY, closeTo((shape.beginY! + shape.endY!) * 0.5, 1e-9));
    }
  });

  test('test11_rotate keeps the independent size of every page', () {
    final pages = parser.parse(_fixture('test11_rotate.vsdx')).pages;

    expect(pages, hasLength(3));
    expect(pages[0].heightInches, closeTo(22.88582677165354, 1e-9));
    expect(pages[1].heightInches, closeTo(11.69291338582677, 1e-9));
    expect(pages[2].heightInches, closeTo(11.69291338582677, 1e-9));
  });
}
