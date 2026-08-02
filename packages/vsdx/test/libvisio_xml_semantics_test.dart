import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:vsdx/src/parser/geometry_parser.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

Uint8List _rewritePackage(
  Uint8List input,
  Map<String, Map<String, String>> substitutions,
) {
  final source = ZipDecoder().decodeBytes(input);
  final output = Archive();
  for (final file in source) {
    final raw = file.content;
    var bytes = raw is Uint8List ? raw : Uint8List.fromList(raw as List<int>);
    final edits = substitutions[file.name];
    if (edits != null) {
      var text = utf8.decode(bytes);
      for (final edit in edits.entries) {
        expect(text, contains(edit.key), reason: file.name);
        text = text.replaceAll(edit.key, edit.value);
      }
      bytes = Uint8List.fromList(utf8.encode(text));
    }
    output.addFile(ArchiveFile(file.name, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(output)!);
}

void main() {
  test('Page uses display Name, XML true, and ignores rows without ID', () {
    final bytes = _rewritePackage(
      const VsdxWriter().emptyDocument(),
      const <String, Map<String, String>>{
        'visio/pages/pages.xml': <String, String>{
          'NameU="Page-1" Name="Page-1" ': 'NameU="Universal" Name="Localized" '
              'Background="true" BackPage="-1" ',
          '</Pages>': '<Page Name="Missing ID"/></Pages>',
        },
      },
    );

    final pages = const DocumentParser().parse(bytes).pages;
    expect(pages, hasLength(1));
    expect(pages.single.name, 'Localized');
    expect(pages.single.isBackgroundPage, isTrue);
    expect(pages.single.backgroundPageId, isNull);
  });

  test('Geometry accepts libvisio XML true spelling for flags and Del', () {
    final shape = XmlDocument.parse(
      '<Shape>'
      '<Section N="Geometry" IX="0" Del="true"/>'
      '<Section N="Geometry" IX="1">'
      '<Cell N="NoFill" V="true"/><Cell N="NoLine" V="true"/>'
      '<Cell N="NoShow" V="true"/><Cell N="NoSnap" V="true"/>'
      '<Cell N="NoQuickDrag" V="true"/>'
      '<Row T="MoveTo" IX="4" Del="true">'
      '<Cell N="X" V="1"/><Cell N="Y" V="2"/>'
      '</Row>'
      '</Section>'
      '</Shape>',
    ).rootElement;

    final geometries = const GeometryParser().parse(shape);
    expect(geometries, hasLength(2));
    expect(geometries[0].deleted, isTrue);
    expect(geometries[1].noFill, isTrue);
    expect(geometries[1].noLine, isTrue);
    expect(geometries[1].noShow, isTrue);
    expect(geometries[1].noSnap, isTrue);
    expect(geometries[1].noQuickDrag, isTrue);
    expect(geometries[1].commands, isEmpty);
    expect(geometries[1].deletedRowIndices, contains(4));
  });
}
