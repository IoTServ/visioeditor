import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:vsdx/src/parser/geometry_parser.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

import 'support/libvisio_oracle.dart';

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

Uint8List _scaledDrawingPackage() => _rewritePackage(
      const VsdxWriter().emptyDocument(),
      const <String, Map<String, String>>{
        'visio/pages/pages.xml': <String, String>{
          '<Cell N="PageScale" V="1" U="PT"/>':
              '<Cell N="PageScale" V="2" U="PT" F="Inh"/>',
        },
        'visio/pages/page1.xml': <String, String>{
          '<Shapes/>': '<Shapes>'
              '<Shape ID="1" NameU="Scaled">'
              '<Cell N="PinX" V="1"/><Cell N="PinY" V="2"/>'
              '<Cell N="Width" V="2"/><Cell N="Height" V="1"/>'
              '<Cell N="LocPinX" V="1"/><Cell N="LocPinY" V="0.5"/>'
              '<Cell N="TxtPinX" V="1"/><Cell N="TxtPinY" V="0.5"/>'
              '<Cell N="TxtWidth" V="2"/><Cell N="TxtHeight" V="1"/>'
              '<Cell N="LeftMargin" V="0.1"/>'
              '<Cell N="LineWeight" V="0.01"/>'
              '<Cell N="Rounding" V="0.125"/>'
              '<Section N="Character"><Row IX="0">'
              '<Cell N="Size" V="0.2"/>'
              '</Row></Section>'
              '<Section N="Geometry" IX="0">'
              '<Row T="MoveTo" IX="1">'
              '<Cell N="X" V="0"/><Cell N="Y" V="0"/>'
              '</Row><Row T="LineTo" IX="2">'
              '<Cell N="X" V="2"/><Cell N="Y" V="1"/>'
              '</Row></Section>'
              '<Text><cp IX="0"/>Scaled</Text>'
              '</Shape></Shapes>',
        },
      },
    );

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

  test('Page drawing scale materializes drawable coordinates like libvisio',
      () {
    final bytes = _scaledDrawingPackage();

    final page = const DocumentParser().parse(bytes).pages.single;
    final shape = page.shapes.single;
    expect(page.widthInches, closeTo(17, 1e-9));
    expect(page.heightInches, closeTo(22, 1e-9));
    expect(page.pageSheet.pageScale, 2);
    expect(page.pageSheet.drawingScale, 1);
    expect(shape.pinX, closeTo(2, 1e-9));
    expect(shape.pinY, closeTo(4, 1e-9));
    expect(shape.width, closeTo(4, 1e-9));
    expect(shape.height, closeTo(2, 1e-9));
    expect(shape.locPinXInches, closeTo(2, 1e-9));
    expect(shape.locPinYInches, closeTo(1, 1e-9));
    expect(shape.richText.textBlock.pinXInches, closeTo(2, 1e-9));
    expect(shape.richText.textBlock.pinYInches, closeTo(1, 1e-9));
    expect(shape.richText.textBlock.widthInches, closeTo(4, 1e-9));
    expect(shape.richText.textBlock.heightInches, closeTo(2, 1e-9));
    expect(shape.line.weightInches, closeTo(0.02, 1e-9));
    expect(shape.line.roundingInches, closeTo(0.25, 1e-9));
    final line = shape.geometries.single.commands.last as LineTo;
    expect(line.x, closeTo(4, 1e-9));
    expect(line.y, closeTo(2, 1e-9));

    // libvisio scales the text frame, not typography or text padding.
    expect(shape.richText.runs.single.charStyle.fontSizeInches,
        closeTo(0.2, 1e-9));
    expect(shape.richText.textBlock.marginLeftInches, closeTo(0.1, 1e-9));
  });

  final oracle = LibvisioOracle.tryLoad();
  test('scaled drawing canvas matches the libvisio oracle', () {
    final pages = oracle!.svgPages(_scaledDrawingPackage());
    expect(pages, isNotNull);
    expect(pages, hasLength(1));
    final size = RegExp(r'width="([0-9.]+)in"\s+height="([0-9.]+)in"')
        .firstMatch(pages!.single);
    expect(size, isNotNull);
    expect(double.parse(size!.group(1)!), closeTo(17, 0.001));
    expect(double.parse(size.group(2)!), closeTo(22, 0.001));
  }, skip: oracle == null ? 'libvisio oracle is unavailable' : null);
}
