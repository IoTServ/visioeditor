import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:vsdx/src/parser/geometry_parser.dart';
import 'package:vsdx/src/parser/page_parser.dart';
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

Uint8List _missingPagePropsPackage() => _rewritePackage(
      const VsdxWriter().emptyDocument(),
      const <String, Map<String, String>>{
        'visio/pages/pages.xml': <String, String>{
          '<Cell N="PageWidth" V="8.5"/>': '',
          '<Cell N="PageHeight" V="11"/>': '',
          '<Cell N="ShdwOffsetX" V="0.125"/>': '',
          '<Cell N="ShdwOffsetY" V="-0.125"/>': '',
        },
      },
    );

Uint8List _layerCachedValuePackage({required bool visible}) {
  const parser = DocumentParser();
  const writer = VsdxWriter();
  final blank = writer.emptyDocument();
  var document = parser.parse(blank);
  final page = document.pages.single.copyWith(
    layers: <VsdxLayer>[
      VsdxLayer(
        id: 0,
        name: 'Cached layer',
        visible: visible,
        print: false,
        color: const VsdxColor(0xFFFF0000),
      ),
    ],
  );
  final shape = VsdxShapeFactory.rectangle(
    id: page.nextFreeShapeId(),
    pinX: 2,
    pinY: 2,
    width: 2,
    height: 1,
  ).copyWith(
    text: 'LAYER_INH_CACHE',
    layerMemberIds: const <int>[0],
  );
  document = document.replacePage(0, page.addShape(shape));
  final bytes = writer.write(originalBytes: blank, edited: document);
  return _rewritePackage(
    bytes,
    <String, Map<String, String>>{
      'visio/pages/pages.xml': <String, String>{
        '<Cell N="Visible" V="${visible ? 1 : 0}"/>':
            '<Cell N="Visible" V="${visible ? 1 : 0}" F="Inh"/>',
        '<Cell N="Print" V="0"/>': '<Cell N="Print" V="0" F="Inh"/>',
        '<Cell N="Color" V="#FF0000"/>':
            '<Cell N="Color" V="#FF0000" F="Inh"/>',
      },
    },
  );
}

Uint8List _textBooleanPackage({bool hideText = false}) {
  const parser = DocumentParser();
  const writer = VsdxWriter();
  final blank = writer.emptyDocument();
  var document = parser.parse(blank);
  final page = document.pages.single;
  final shape = VsdxShapeFactory.rectangle(
    id: page.nextFreeShapeId(),
    pinX: 2,
    pinY: 2,
    width: 2,
    height: 1,
  ).copyWith(
    text: 'TEXT_BOOLEAN',
    richText: VsdxRichText(
      runs: const [
        VsdxTextRun(
          text: 'TEXT_BOOLEAN',
          charStyle: VsdxCharStyle(strikethrough: true),
        ),
      ],
      textBlock: VsdxTextBlock(hideText: hideText),
    ),
  );
  document = document.replacePage(0, page.addShape(shape));
  final bytes = writer.write(originalBytes: blank, edited: document);
  return _rewritePackage(
    bytes,
    <String, Map<String, String>>{
      'visio/pages/page1.xml': <String, String>{
        '<Cell N="HideText" V="${hideText ? 1 : 0}"/>':
            '<Cell N="HideText" V="${hideText ? 'true' : 'false'}"/>',
        '<Cell N="Strikethru" V="1"/>': '<Cell N="Strikethru" V="true"/>',
      },
    },
  );
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

  test('Text normalizes Unicode separators like libvisio', () {
    final pageXml = XmlDocument.parse(
      '<PageContents><Shapes><Shape ID="1" NameU="Text">'
      '<Text>A\u2028B<fld IX="4">F\u2029G</fld>C</Text>'
      '</Shape></Shapes></PageContents>',
    );

    final shape = const PageParser()
        .parseShapes(pageXml, partName: '/visio/pages/page1.xml')
        .single;
    expect(shape.text, 'A\nBF\nGC');
    expect(shape.richText.plainText, 'A\nBF\nGC');
    expect(shape.richText.runs, hasLength(1));
    expect(shape.richText.runs.single.fieldSpans, hasLength(1));
    expect(shape.richText.runs.single.fieldSpans.single.start, 3);
    expect(shape.richText.runs.single.fieldSpans.single.length, 3);
  });

  test('Sparse VSDX text starts from libvisio paragraph and block defaults',
      () {
    final pageXml = XmlDocument.parse(
      '<PageContents><Shapes><Shape ID="1" NameU="Text">'
      '<Text>Unstyled</Text>'
      '</Shape></Shapes></PageContents>',
    );

    final shape = const PageParser()
        .parseShapes(pageXml, partName: '/visio/pages/page1.xml')
        .single;
    final character = shape.richText.runs.single.charStyle;
    final paragraph = shape.richText.runs.single.paraStyle;
    final block = shape.richText.textBlock;

    expect(character.fontFamily, 'Arial');
    expect(character.fontSizeInches, closeTo(12 / 72, 1e-9));
    expect(character.color, VsdxColor.black);
    expect(character.transparency, 0);
    expect(paragraph.horizontalAlign, VsdxHorzAlign.center);
    expect(paragraph.lineSpacing, closeTo(1.2, 1e-9));
    expect(paragraph.lineSpacingAbsoluteInches, 0);
    expect(paragraph.lineSpacingSolid, isFalse);
    expect(block.verticalAlign, VsdxVertAlign.middle);
    expect(block.marginLeftInches, 0);
    expect(block.marginRightInches, 0);
    expect(block.marginTopInches, 0);
    expect(block.marginBottomInches, 0);
    expect(block.defaultTabStopInches, closeTo(0.5, 1e-9));
  });

  test('zero VSDX shadow offsets fall back to PageSheet per axis', () {
    final pageXml = XmlDocument.parse(
      '<PageContents><Shapes><Shape ID="1" NameU="Shadow">'
      '<Cell N="ShadowPattern" V="1"/>'
      '<Cell N="ShadowOffsetX" V="0"/>'
      '<Cell N="ShapeShdwOffsetY" V="-0.2"/>'
      '</Shape></Shapes></PageContents>',
    );

    final shape = const PageParser()
        .withPageShadowOffsets(0.3, -0.4)
        .parseShapes(pageXml, partName: '/visio/pages/page1.xml')
        .single;

    expect(shape.shadow.enabled, isTrue);
    expect(shape.shadow.offsetXInches, closeTo(0.3, 1e-12));
    expect(shape.shadow.offsetYInches, closeTo(-0.2, 1e-12));
  });

  test('Nested shapes inherit only the parent NameU like libvisio', () {
    final pageXml = XmlDocument.parse(
      '<PageContents><Shapes>'
      '<Shape ID="1" NameU="UniversalParent" Name="LocalizedParent">'
      '<Shapes>'
      '<Shape ID="2" Name="LocalizedChild"/>'
      '<Shape ID="3" NameU="UniversalChild" Name="LocalizedChild"/>'
      '</Shapes></Shape>'
      '<Shape ID="4" Name="LocalizedTop"/>'
      '</Shapes></PageContents>',
    );

    final shapes = const PageParser()
        .parseShapes(pageXml, partName: '/visio/pages/page1.xml');
    expect(shapes[0].name, 'UniversalParent');
    expect(shapes[0].children[0].name, 'UniversalParent');
    expect(shapes[0].children[1].name, 'UniversalChild');
    expect(shapes[1].name, 'Sheet.4');
  });

  test('Sparse shape XForms keep libvisio zero defaults', () {
    final pageXml = XmlDocument.parse(
      '<PageContents><Shapes>'
      '<Shape ID="1"/>'
      '<Shape ID="2"><Cell N="BeginY" V="2"/></Shape>'
      '<Shape ID="3"><Cell N="BegTrigger" V="9" '
      'F="_XFTRIGGER(Sheet.9!EventXFMod)"/></Shape>'
      '</Shapes></PageContents>',
    );

    final shapes = const PageParser()
        .parseShapes(pageXml, partName: '/visio/pages/page1.xml');
    final sparse = shapes[0];
    expect(sparse.pinX, 0);
    expect(sparse.pinY, 0);
    expect(sparse.width, 0);
    expect(sparse.height, 0);
    expect(sparse.locPinXInches, 0);
    expect(sparse.locPinYInches, 0);
    expect(sparse.effectiveLocPinX, 0);
    expect(sparse.effectiveLocPinY, 0);
    expect(sparse.fill.pattern, 0);
    expect(sparse.fill.foreground, isNull);
    expect(sparse.fill.background, isNull);

    final beginYOnly = shapes[1];
    expect(beginYOnly.is1D, isTrue);
    expect(beginYOnly.beginX, 0);
    expect(beginYOnly.beginY, 2);
    expect(beginYOnly.endX, 0);
    expect(beginYOnly.endY, 0);

    final triggerOnly = shapes[2];
    expect(triggerOnly.is1D, isTrue);
    expect(triggerOnly.beginX, 0);
    expect(triggerOnly.beginY, 0);
    expect(triggerOnly.endX, 0);
    expect(triggerOnly.endY, 0);
  });

  test('VSDX LineCap numeric values follow libvisio rendering semantics', () {
    final pageXml = XmlDocument.parse(
      '<PageContents><Shapes>'
      '<Shape ID="1"><Cell N="LineCap" V="0"/></Shape>'
      '<Shape ID="2"><Cell N="LineCap" V="1"/></Shape>'
      '<Shape ID="3"><Cell N="LineCap" V="2"/></Shape>'
      '</Shapes></PageContents>',
    );

    final shapes = const PageParser()
        .parseShapes(pageXml, partName: '/visio/pages/page1.xml');
    expect(shapes[0].line.cap, LineCap.round);
    // libvisio maps raw 1 to SVG butt and raw 2 to SVG square.
    expect(shapes[1].line.cap, LineCap.extended);
    expect(shapes[2].line.cap, LineCap.square);
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

  test('Page drawing scale uses libvisio absolute ratio semantics', () {
    final bytes = _rewritePackage(
      _scaledDrawingPackage(),
      const <String, Map<String, String>>{
        'visio/pages/pages.xml': <String, String>{
          '<Cell N="PageScale" V="2" U="PT" F="Inh"/>':
              '<Cell N="PageScale" V="-2" U="PT" F="Inh"/>',
        },
      },
    );

    final page = const DocumentParser().parse(bytes).pages.single;
    expect(page.widthInches, closeTo(17, 1e-9));
    expect(page.heightInches, closeTo(22, 1e-9));
    expect(page.shapes.single.pinX, closeTo(2, 1e-9));
    expect(page.shapes.single.pinY, closeTo(4, 1e-9));
  });

  test('scaled VSDX edits write source cells without double scaling', () {
    final bytes = _scaledDrawingPackage();
    final parser = const DocumentParser();
    final before = parser.parse(bytes);
    final page = before.pages.single;
    final shape = page.shapes.single;
    final geometry = shape.geometries.single;
    final editedShape = shape.copyWith(
      pinX: 3,
      pinY: 5,
      line: shape.line.copyWith(weightInches: 0.03),
      geometries: <VsdxGeometry>[
        geometry.copyWith(
          commands: const <VsdxPathCommand>[
            MoveTo(0, 0),
            LineTo(5, 3),
          ],
        ),
      ],
      richText: shape.richText.copyWith(
        textBlock: shape.richText.textBlock.copyWith(
          widthInches: 5,
          heightInches: 3,
        ),
      ),
    );
    final edited = before.replacePage(
      0,
      page
          .copyWith(widthInches: 18, heightInches: 24)
          .updateShapeById(shape.id, (_) => editedShape),
    );

    final reopened = parser
        .parse(
          const VsdxWriter().write(originalBytes: bytes, edited: edited),
        )
        .pages
        .single;
    final after = reopened.shapes.single;

    expect(reopened.widthInches, closeTo(18, 1e-9));
    expect(reopened.heightInches, closeTo(24, 1e-9));
    expect(reopened.pageSheet.pageScale, 2);
    expect(reopened.pageSheet.drawingScale, 1);
    expect(after.pinX, closeTo(3, 1e-9));
    expect(after.pinY, closeTo(5, 1e-9));
    expect(after.line.weightInches, closeTo(0.03, 1e-9));
    final line = after.geometries.single.commands.last as LineTo;
    expect(line.x, closeTo(5, 1e-9));
    expect(line.y, closeTo(3, 1e-9));
    expect(after.richText.textBlock.widthInches, closeTo(5, 1e-9));
    expect(after.richText.textBlock.heightInches, closeTo(3, 1e-9));
  });

  final oracle = LibvisioOracle.tryLoad();

  test('missing VSDX page properties retain libvisio zero defaults', () {
    final page =
        const DocumentParser().parse(_missingPagePropsPackage()).pages.single;

    expect(page.widthInches, 0);
    expect(page.heightInches, 0);
    expect(page.pageSheet.shadowOffsetXInches, 0);
    expect(page.pageSheet.shadowOffsetYInches, 0);
  });

  test('Layer row cached values match libvisio F=Inh semantics', () {
    final page = const DocumentParser()
        .parse(_layerCachedValuePackage(visible: false))
        .pages
        .single;
    final layer = page.layers.single;

    expect(layer.visible, isFalse);
    expect(layer.print, isFalse);
    expect(layer.color, const VsdxColor(0xFFFF0000));
    expect(page.shapes.single.layerMemberIds, const <int>[0]);
  });

  test('Layer Color cached V with F=Inh matches the libvisio oracle', () {
    final pages = oracle!.svgPages(_layerCachedValuePackage(visible: false));

    expect(pages, isNotNull);
    expect(pages!.single, contains('stroke: #ff0000'));
    // librevenge's SVG generator does not serialize libvisio's draw:display
    // property, so visibility itself is covered by the parsed model assertion.
    expect(pages.single, contains('LAYER_INH_CACHE'));
  }, skip: oracle == null ? 'libvisio oracle is unavailable' : null);

  test('text boolean spellings remain parseable by the libvisio oracle', () {
    final bytes = _textBooleanPackage();
    final hiddenBytes = _textBooleanPackage(hideText: true);
    final shape =
        const DocumentParser().parse(bytes).pages.single.shapes.single;
    final pages = oracle!.svgPages(bytes);
    final hiddenPages = oracle.svgPages(hiddenBytes);

    expect(shape.richText.textBlock.hideText, isFalse);
    expect(shape.richText.runs.single.charStyle.strikethrough, isTrue);
    expect(pages, isNotNull);
    expect(hiddenPages, isNotNull);
    expect(pages!.single, contains('TEXT_BOOLEAN'));
    expect(hiddenPages!.single, isNot(contains('TEXT_BOOLEAN')));
  }, skip: oracle == null ? 'libvisio oracle is unavailable' : null);

  test('missing VSDX page dimensions match the libvisio oracle', () {
    final pages = oracle!.svgPages(_missingPagePropsPackage());
    expect(pages, isNotNull);
    expect(pages, hasLength(1));
    final size = RegExp(r'width="([0-9.]+)in"\s+height="([0-9.]+)in"')
        .firstMatch(pages!.single);
    expect(size, isNotNull);
    expect(double.parse(size!.group(1)!), 0);
    expect(double.parse(size.group(2)!), 0);
  }, skip: oracle == null ? 'libvisio oracle is unavailable' : null);

  test('scaled drawing canvas matches the libvisio oracle', () {
    final pages = oracle!.svgPages(_scaledDrawingPackage());
    expect(pages, isNotNull);
    expect(pages, hasLength(1));
    expect(pages!.single, contains('fill: none;'));
    final size = RegExp(r'width="([0-9.]+)in"\s+height="([0-9.]+)in"')
        .firstMatch(pages.single);
    expect(size, isNotNull);
    expect(double.parse(size!.group(1)!), closeTo(17, 0.001));
    expect(double.parse(size.group(2)!), closeTo(22, 0.001));
  }, skip: oracle == null ? 'libvisio oracle is unavailable' : null);

  test('End Event keeps libvisio cached outline and white inner fill', () {
    final fixture = File(
      '../../third_party/libvisio/src/test/data/testfile6.vsdx',
    );
    expect(fixture.existsSync(), isTrue);
    final doc = const DocumentParser().parse(fixture.readAsBytesSync());
    final outer = doc.pages.single.findShapeById(421)!;
    final inner = doc.pages.single.findShapeById(424)!;

    // vsd2raw/libvisio emits #3d64ac for both outlines. These values are
    // evaluated instance caches stored with F="Inh" and must not be replaced
    // with the master stencil's current QuickStyle line colour.
    expect(outer.line.color, const VsdxColor(0xFF3D64AC));
    expect(outer.line.themeColorIndex, isNull);
    expect(inner.line.color, const VsdxColor(0xFF3D64AC));
    expect(inner.line.themeColorIndex, isNull);

    // QuickStyle 101 + FillMatrix 101 selects variation fill style 3. Its
    // first two phClr stops are unresolved by libvisio, while the final lt1
    // stop resolves to the Office 2019 light colour #feffff.
    expect(inner.fill.themeForegroundIndex, 101);
    expect(
      doc.theme.resolveFill(
        inner.fill.themeForegroundIndex!,
        fillMatrix: inner.quickStyleFillMatrix,
      ),
      const VsdxColor(0xFFFEFFFF),
    );
  });

  test('master instance keeps libvisio text transform and colour caches', () {
    final fixture = File(
      '../../third_party/libvisio/src/test/data/'
      'tdf154379-QuickStyleFillMatrix.vsdx',
    );
    expect(fixture.existsSync(), isTrue);
    final doc = const DocumentParser().parse(fixture.readAsBytesSync());
    final shape = doc.pages.single.findShapeById(317)!;
    final block = shape.richText.textBlock;
    final runs = shape.richText.runs
        .where((run) => run.text.isNotEmpty)
        .toList(growable: false);

    expect(block.pinXInches, closeTo(0.8473050162022133, 1e-12));
    expect(block.pinYInches, closeTo(0.635478762151662, 1e-12));
    expect(block.widthInches, closeTo(1.694610032404427, 1e-12));
    expect(block.heightInches, closeTo(0.7625745145819943, 1e-12));
    expect(block.locPinXInches, closeTo(0.8473050162022133, 1e-12));
    expect(block.locPinYInches, closeTo(0.3812872572909972, 1e-12));
    expect(runs, isNotEmpty);
    for (final run in runs) {
      expect(run.charStyle.color, const VsdxColor(0xFF5B9BD5));
      expect(run.charStyle.themeColorIndex, isNull);
      expect(run.paraStyle.horizontalAlign, VsdxHorzAlign.center);
    }
  });
}
