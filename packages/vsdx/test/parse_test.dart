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
}
