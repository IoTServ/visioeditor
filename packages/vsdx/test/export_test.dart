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

  test('SVG text-anchor follows Paragraph HorzAlign', () {
    final blank = const VsdxWriter().emptyDocument();
    var doc = parser.parse(blank);
    final page = doc.pages.first;
    final left = VsdxShapeFactory.rectangle(
      id: page.nextFreeShapeId(),
      pinX: 2,
      pinY: 5,
      width: 2,
      height: 0.6,
    ).copyWith(
      richText: VsdxRichText(runs: [
        VsdxTextRun(
          text: 'Left',
          paraStyle: const VsdxParaStyle(horizontalAlign: VsdxHorzAlign.left),
        ),
      ]),
    );
    final center = VsdxShapeFactory.rectangle(
      id: page.nextFreeShapeId() + 1,
      pinX: 5,
      pinY: 5,
      width: 2,
      height: 0.6,
    ).copyWith(
      richText: VsdxRichText(runs: [
        VsdxTextRun(
          text: 'Center',
          paraStyle: const VsdxParaStyle(horizontalAlign: VsdxHorzAlign.center),
        ),
      ]),
    );
    doc = doc.replacePage(
      0,
      page.addShape(left).addShape(center),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('text-anchor="start"'));
    expect(svg, contains('text-anchor="middle"'));
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

  test('SVG stroke-linecap follows LineCap', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(id: id, ax: 1, ay: 1, bx: 3, by: 1).copyWith(
              line: const VsdxLine(cap: LineCap.square, weightInches: 0.05),
            ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('stroke-linecap="square"'));
  });

  test('SVG fill-opacity multiplies colour ARGB alpha', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 1,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(
            foreground: VsdxColor(0x8000FF00), // 50% green
            foregroundTransparency: 0.0,
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('fill-opacity="0.502"'));
  });

  test('SVG omits children of collapsed containers', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final hostId = doc.pages.first.nextFreeShapeId();
    final childId = hostId + 1;
    final child = VsdxShapeFactory.rectangle(
      id: childId,
      pinX: 1,
      pinY: 1,
      width: 1,
      height: 0.5,
    ).copyWith(
      fill: const VsdxFill(foreground: VsdxColor(0xFF00ABCD)),
      richText: const VsdxRichText(runs: [VsdxTextRun(text: 'SecretChild')]),
    );
    final host = VsdxShapeFactory.container(
      id: hostId,
      pinX: 3,
      pinY: 3,
      width: 3,
      height: 2,
    ).copyWith(children: <VsdxShape>[child]).fold();
    doc = doc.replacePage(0, doc.pages.first.addShape(host));
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, isNot(contains('SecretChild')));
    expect(svg, isNot(contains('#00abcd')));
  });
}
