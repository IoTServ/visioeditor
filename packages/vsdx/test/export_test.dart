import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

void main() {
  const parser = DocumentParser();

  test('serializes a document to SVG', () {
    final doc = parser.parse(_fixture('test9_rect_and_line.vsdx'));
    final svg = VsdxToSvgSerializer().serializeDocument(doc);
    expect(svg, contains('<svg'));
    expect(svg, contains('</svg>'));
    expect(svg.length, greaterThan(100));
  });

  test('serializes a single page to SVG', () {
    final doc = parser.parse(_fixture('test1.vsdx'));
    final svg = VsdxToSvgSerializer().serializePage(
      doc.pages.first,
      theme: doc.theme,
      images: doc.images,
    );
    expect(svg, contains('<svg'));
  });

  test('SVG composites BackPage underlay and skips background pages', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final fg = doc.pages.first;
    final bgId = doc.nextPageId();
    final bgRect = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000)));
    doc = doc.insertPage(
      1,
      VsdxPage(
        id: bgId,
        name: 'Background-1',
        widthInches: fg.widthInches,
        heightInches: fg.heightInches,
        shapes: <VsdxShape>[bgRect],
        isBackgroundPage: true,
      ),
    );
    final fgRect = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 4,
      pinY: 4,
      width: 1,
      height: 1,
    );
    doc = doc.replacePage(
      0,
      fg.copyWith(backgroundPageId: bgId, shapes: <VsdxShape>[fgRect]),
    );

    final svg = VsdxToSvgSerializer().serializeDocument(doc);
    expect(svg, contains('class="underlay"'));
    expect(svg, contains('#ff0000'));
    // Background page is not emitted as its own sheet.
    expect(svg, isNot(contains('page-2')));
  });

  test('SVG print filter omits non-printable layers', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final page = doc.pages.first;
    final layers = <VsdxLayer>[
      const VsdxLayer(id: 0, name: 'PrintMe', visible: true, print: true),
      const VsdxLayer(id: 1, name: 'NoPrint', visible: true, print: false),
    ];
    final a = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 1,
      pinY: 1,
      width: 1,
      height: 1,
    ).copyWith(
      layerMemberIds: const <int>[0],
      fill: const VsdxFill(foreground: VsdxColor(0xFF00FF00)),
    );
    final b = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 3,
      pinY: 1,
      width: 1,
      height: 1,
    ).copyWith(
      layerMemberIds: const <int>[1],
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF00FF)),
    );
    doc = doc.replacePage(
      0,
      page.copyWith(layers: layers, shapes: <VsdxShape>[a, b]),
    );

    final svg = VsdxToSvgSerializer(layerFilter: SvgLayerFilter.print)
        .serializePage(doc.pages.first);
    expect(svg, contains('#00ff00'));
    expect(svg, isNot(contains('#ff00ff')));
  });
}
