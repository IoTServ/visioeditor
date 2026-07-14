import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

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
