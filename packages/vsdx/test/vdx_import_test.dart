import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

Uint8List _fixture() =>
    File('test/fixtures/vdx_all_types.vdx').readAsBytesSync();

List<VsdxShape> _allShapes(VsdxDocument document) {
  final out = <VsdxShape>[];
  void visit(VsdxShape shape) {
    out.add(shape);
    for (final child in shape.children) {
      visit(child);
    }
  }

  for (final page in document.pages) {
    for (final shape in page.shapes) {
      visit(shape);
    }
  }
  return out;
}

Set<Type> _commandTypes(VsdxShape shape) => <Type>{
      for (final geometry in shape.geometries)
        for (final command in geometry.commands) command.runtimeType,
    };

void main() {
  group('DiagramML VDX/VSX/VTX import', () {
    test('normalises every libvisio drawing component into the shared model',
        () {
      final source = _fixture();
      expect(looksLikeVdx(source), isTrue);

      final result = parseVisio(source, sourceName: 'coverage.vdx');
      expect(result.importedFromVsd, isTrue);
      expect(result.document.title, 'DiagramML parser coverage');
      expect(result.document.creator, 'visioeditor tests');
      expect(result.document.pages, hasLength(1));
      expect(result.document.masters.length, 1);
      expect(result.document.images.length, 2);

      final page = result.document.pages.single;
      expect(page.name, 'Coverage');
      expect(page.widthInches, 10);
      expect(page.heightInches, 7);
      expect(page.layers, hasLength(2));
      expect(page.layers.first.visible, isTrue);
      expect(page.layers.last.visible, isFalse);
      expect(page.connects, hasLength(2));

      final shapes = _allShapes(result.document);
      expect(shapes, hasLength(9));
      final masterInstance = page.findShapeById(1)!;
      expect(masterInstance.geometries.single.commands, hasLength(5));
      expect(masterInstance.fill.foreground, const VsdxColor(0xFFE2F0D9));
      expect(masterInstance.richText.plainText,
          contains('All rich text retained'));
      expect(
          masterInstance.richText.plainText, contains('Second line and tab'));
      expect(masterInstance.richText.runs.length, greaterThanOrEqualTo(2));
      expect(masterInstance.richText.tabSets, hasLength(1));

      final curves = page.findShapeById(2)!;
      expect(
        _commandTypes(curves),
        containsAll(<Type>[
          CubBezTo,
          QuadBezTo,
          ArcTo,
          EllipseCmd,
          EllipticalArcTo,
        ]),
      );
      final group = page.findShapeById(3)!;
      expect(
          group.children.map((shape) => shape.id), orderedEquals(<int>[4, 5]));
      expect(page.findShapeById(6)!.is1D, isTrue);
      expect(page.findShapeById(6)!.line.endArrow, 4);
      final inheritedStyle = page.findShapeById(7)!;
      expect(inheritedStyle.line.cap, LineCap.square);
      expect(inheritedStyle.line.beginArrow, 4);
      expect(inheritedStyle.line.endArrow, 13);
      expect(inheritedStyle.line.roundingInches, closeTo(0.08, 1e-9));
      expect(inheritedStyle.fill.foregroundTransparency, closeTo(0.15, 1e-9));
      expect(inheritedStyle.fill.backgroundTransparency, closeTo(0.35, 1e-9));
      expect(inheritedStyle.shadow.enabled, isTrue);
      expect(inheritedStyle.shadow.color, const VsdxColor(0xFF44546A));
      expect(inheritedStyle.shadow.offsetXInches, closeTo(0.2, 1e-9));
      expect(inheritedStyle.shadow.offsetYInches, closeTo(-0.15, 1e-9));
      expect(inheritedStyle.richText.textBlock.marginLeftInches,
          closeTo(0.05, 1e-9));
      expect(inheritedStyle.richText.textBlock.defaultTabStopInches,
          closeTo(0.4, 1e-9));
      expect(
        _commandTypes(inheritedStyle),
        containsAll(<Type>[
          RelMoveTo,
          RelLineTo,
          RelCubBezTo,
          RelQuadBezTo,
          RelArcTo,
          PolylineTo,
        ]),
      );
      final image = page.findShapeById(8)!;
      expect(image.hasImage, isTrue);
      expect(
          result.document.images.findByPart(image.imagePartName!), isNotNull);
      final dibImageShape = page.findShapeById(9)!;
      expect(dibImageShape.hasImage, isTrue);
      final dibImage =
          result.document.images.findByPart(dibImageShape.imagePartName!)!;
      expect(dibImage.mimeType, 'image/bmp');
      expect(dibImage.partName, endsWith('.bmp'));
      expect(dibImage.bytes, hasLength(58));
      expect(dibImage.bytes.sublist(0, 2), orderedEquals(<int>[0x42, 0x4D]));
      expect(dibImage.bytes.sublist(10, 14), orderedEquals(<int>[54, 0, 0, 0]));
      final svg = VsdxToSvgSerializer().serializePage(
        page,
        images: result.document.images,
      );
      expect(svg, contains('data:image/bmp;base64,Qk0'));
    });

    test('VDX import synthesises an editable VSDX without losing visible data',
        () {
      final imported = parseVisio(_fixture(), sourceName: 'coverage.vdx');
      final reopened = parseVisio(
        imported.originalBytes,
        sourceName: 'coverage.vsdx',
      ).document;

      expect(reopened.pages, hasLength(1));
      expect(_allShapes(reopened), hasLength(9));
      expect(reopened.images.length, 2);
      final allText = _allShapes(reopened)
          .map((shape) => shape.richText.plainText)
          .join('\n');
      for (final expected in const <String>[
        'All rich text retained',
        'Second line and tab',
        'Bezier, arcs, ellipse',
        'Grouped child A',
        'Grouped child B',
        '1-D connector',
        'Relative and polyline rows',
      ]) {
        expect(allText, contains(expected));
      }
      expect(reopened.pages.single.findShapeById(8)!.hasImage, isTrue);
      final reopenedDibShape = reopened.pages.single.findShapeById(9)!;
      expect(reopenedDibShape.hasImage, isTrue);
      final reopenedDib =
          reopened.images.findByPart(reopenedDibShape.imagePartName!)!;
      expect(reopenedDib.mimeType, 'image/bmp');
      expect(reopenedDib.bytes.sublist(0, 2), orderedEquals(<int>[0x42, 0x4D]));
      final reopenedSvg = VsdxToSvgSerializer().serializePage(
        reopened.pages.single,
        images: reopened.images,
      );
      expect(reopenedSvg, contains('data:image/bmp;base64,Qk0'));
      final package = VsdxPackage.open(imported.originalBytes);
      final pageXml = package.readPartXml('/visio/pages/page1.xml')!;
      final picture = pageXml.descendants.whereType<XmlElement>().singleWhere(
          (element) =>
              element.name.local == 'Shape' &&
              element.getAttribute('ID') == '9');
      final foreignData = picture.childElements
          .singleWhere((element) => element.name.local == 'ForeignData');
      expect(foreignData.getAttribute('ForeignType'), 'Bitmap');
      expect(foreignData.getAttribute('CompressionType'), isNull,
          reason: 'the VSDX media part already contains a complete BMP header');
      final childNames =
          picture.childElements.map((element) => element.name.local).toList();
      expect(childNames.last, 'ForeignData');
      expect(childNames.lastIndexOf('Section'),
          lessThan(childNames.indexOf('ForeignData')));
      expect(
        _commandTypes(reopened.pages.single.findShapeById(7)!),
        contains(PolylineTo),
      );
      final inheritedStyle = reopened.pages.single.findShapeById(7)!;
      expect(inheritedStyle.line.cap, LineCap.square);
      expect(inheritedStyle.line.beginArrow, 4);
      expect(inheritedStyle.line.endArrow, 13);
      expect(inheritedStyle.line.roundingInches, closeTo(0.08, 1e-9));
      expect(inheritedStyle.fill.foregroundTransparency, closeTo(0.15, 1e-9));
      expect(inheritedStyle.shadow.enabled, isTrue);
      expect(inheritedStyle.shadow.color, const VsdxColor(0xFF44546A));
      expect(inheritedStyle.shadow.offsetXInches, closeTo(0.2, 1e-9));
      expect(inheritedStyle.richText.textBlock.defaultTabStopInches,
          closeTo(0.4, 1e-9));
    });

    test('VSX extracts masters as pages; VTX imports drawing pages', () {
      final source = _fixture();
      final stencil = parseVisio(source, sourceName: 'coverage.vsx');
      expect(stencil.document.pages, hasLength(1));
      expect(stencil.document.pages.single.name, 'Master Rectangle');
      expect(stencil.document.pages.single.shapes, hasLength(1));
      expect(
        stencil.document.pages.single.shapes.single.richText.plainText,
        'Master fallback text',
      );
      expect(
        const DocumentParser().parse(stencil.originalBytes).pages,
        hasLength(1),
      );

      final template = parseVisio(source, sourceName: 'coverage.vtx');
      expect(template.document.pages.single.name, 'Coverage');
      expect(_allShapes(template.document), hasLength(9));
    });

    test('accepts UTF-16 DiagramML and rejects unrelated XML', () {
      final xml = utf8.decode(_fixture());
      final units = xml.codeUnits;
      final utf16le = BytesBuilder(copy: false)..add(const <int>[0xFF, 0xFE]);
      for (final unit in units) {
        utf16le.add(<int>[unit & 0xFF, unit >> 8]);
      }
      final bytes = utf16le.takeBytes();
      expect(looksLikeVdx(bytes), isTrue);
      expect(
        parseVisio(bytes, sourceName: 'utf16.vdx').document.pages,
        hasLength(1),
      );

      final unrelated = Uint8List.fromList(utf8.encode('<root/>'));
      expect(looksLikeVdx(unrelated), isFalse);
      expect(() => parseVisio(unrelated), throwsA(isA<VsdxFormatException>()));
    });
  });
}
