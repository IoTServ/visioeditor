import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset/charset.dart' as charset;
import 'package:cp949_codec/cp949_codec.dart' as korean;
import 'package:enough_convert/enough_convert.dart' as enough;
import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

Uint8List _fixture() =>
    File('test/fixtures/vdx_all_types.vdx').readAsBytesSync();

Uint8List _utf32(
  String value, {
  required bool littleEndian,
  required bool bom,
}) {
  final out = BytesBuilder(copy: false);
  if (bom) {
    out.add(littleEndian
        ? const <int>[0xFF, 0xFE, 0, 0]
        : const <int>[0, 0, 0xFE, 0xFF]);
  }
  for (final rune in value.runes) {
    final data = ByteData(4)
      ..setUint32(
        0,
        rune,
        littleEndian ? Endian.little : Endian.big,
      );
    out.add(data.buffer.asUint8List());
  }
  return out.takeBytes();
}

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
      expect(shapes, hasLength(10));
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
      expect(curves.fields, hasLength(1));
      expect(curves.fields.single.value, 'Cached field text');
      expect(
        curves.richText.plainText,
        'Bezier, arcs, ellipse: Cached field text',
      );
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
          RelEllipticalArcTo,
          PolylineTo,
        ]),
      );
      final advancedGeometry = page.findShapeById(10)!;
      expect(
        _commandTypes(advancedGeometry),
        containsAll(<Type>[
          InfiniteLineCmd,
          SplineStart,
          SplineKnot,
          NurbsTo,
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
      expect(_allShapes(reopened), hasLength(10));
      expect(reopened.images.length, 2);
      final allText = _allShapes(reopened)
          .map((shape) => shape.richText.plainText)
          .join('\n');
      for (final expected in const <String>[
        'All rich text retained',
        'Second line and tab',
        'Bezier, arcs, ellipse',
        'Cached field text',
        'Grouped child A',
        'Grouped child B',
        '1-D connector',
        'Relative and polyline rows',
        'Spline, NURBS, infinite line',
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
        containsAll(<Type>[PolylineTo, RelEllipticalArcTo]),
      );
      expect(
        _commandTypes(reopened.pages.single.findShapeById(10)!),
        containsAll(<Type>[
          InfiniteLineCmd,
          SplineStart,
          SplineKnot,
          NurbsTo,
        ]),
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
      expect(_allShapes(template.document), hasLength(10));
    });

    test('uses V caches for whitespace-only leaves and sniffs bitmap payloads',
        () {
      final xml = utf8
          .decode(_fixture())
          .replaceFirst(
            '<PinX>2</PinX>',
            '<PinX V="2">\n  </PinX>',
          )
          .replaceFirst(
            ' ForeignType="Bitmap" CompressionType="PNG"',
            ' ForeignType="Bitmap"',
          );
      final result = parseVisio(
        Uint8List.fromList(utf8.encode(xml)),
        sourceName: 'third-party.vdx',
      );

      expect(result.document.pages.single.findShapeById(1)!.pinX, 2);
      final imageShape = result.document.pages.single.findShapeById(8)!;
      final image = result.document.images.findByPart(
        imageShape.imagePartName!,
      )!;
      expect(image.mimeType, 'image/png');
      expect(image.bytes.sublist(0, 4), <int>[0x89, 0x50, 0x4E, 0x47]);
    });

    test('renders empty fld markers from DiagramML Field.Value caches', () {
      final imported = parseVisio(
        _fixture(),
        sourceName: 'field-cache.vdx',
      );
      final shape = imported.document.pages.single.findShapeById(2)!;

      expect(shape.fields, hasLength(1));
      expect(shape.fields.single.value, 'Cached field text');
      expect(
        shape.richText.plainText,
        'Bezier, arcs, ellipse: Cached field text',
      );
      expect(shape.richText.runs.single.fieldSpans, hasLength(1));
      expect(
        VsdxToSvgSerializer().serializePage(
          imported.document.pages.single,
          images: imported.document.images,
        ),
        contains('Bezier, arcs, ellipse: Cached field text'),
      );

      final reopened = const DocumentParser().parse(imported.originalBytes);
      final reopenedShape = reopened.pages.single.findShapeById(2)!;
      expect(reopenedShape.fields.single.value, 'Cached field text');
      expect(
        reopenedShape.richText.plainText,
        'Bezier, arcs, ellipse: Cached field text',
      );
      expect(reopenedShape.richText.runs.single.fieldSpans, hasLength(1));
    });

    test('accepts UTF-16/32 DiagramML and rejects unrelated XML', () {
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

      for (final littleEndian in const <bool>[true, false]) {
        for (final bom in const <bool>[true, false]) {
          final declaration = littleEndian ? 'UTF-32LE' : 'UTF-32BE';
          final utf32 = _utf32(
            xml.replaceFirst('encoding="UTF-8"', 'encoding="$declaration"'),
            littleEndian: littleEndian,
            bom: bom,
          );
          expect(looksLikeVdx(utf32), isTrue, reason: '$declaration bom=$bom');
          expect(
            parseVisio(utf32, sourceName: 'utf32.vdx').document.pages,
            hasLength(1),
            reason: '$declaration bom=$bom',
          );
        }
      }

      final unrelated = Uint8List.fromList(utf8.encode('<root/>'));
      expect(looksLikeVdx(unrelated), isFalse);
      expect(() => parseVisio(unrelated), throwsA(isA<VsdxFormatException>()));
    });

    test('honours declared single- and multi-byte XML encodings end to end',
        () {
      final source = utf8.decode(_fixture());
      final cases = <({String declaration, Encoding codec, String text})>[
        (
          declaration: 'windows-1252',
          codec: charset.windows1252,
          text: 'Résumé “VDX” — €',
        ),
        (
          declaration: 'Shift_JIS',
          codec: charset.shiftJis,
          text: '日本語のVDX往復',
        ),
        (
          declaration: 'GBK',
          codec: charset.gbk,
          text: '简体中文VDX往返',
        ),
        (
          declaration: 'Big5',
          codec: const enough.Big5Codec(),
          text: '繁體中文VDX往返',
        ),
        (
          declaration: 'EUC-KR',
          codec: const korean.CP949Codec(allowInvalid: true),
          text: '한국어 VDX 왕복',
        ),
      ];

      for (final testCase in cases) {
        final xml = source
            .replaceFirst(
                'encoding="UTF-8"', 'encoding="${testCase.declaration}"')
            .replaceFirst(
              'DiagramML parser coverage',
              testCase.text,
            )
            .replaceFirst(
              'Spline, NURBS, infinite line',
              testCase.text,
            );
        final bytes = Uint8List.fromList(testCase.codec.encode(xml));
        expect(looksLikeVdx(bytes), isTrue, reason: testCase.declaration);

        final imported = parseVisio(
          bytes,
          sourceName: 'encoded-${testCase.declaration}.vdx',
        );
        expect(imported.document.title, testCase.text);
        expect(
          imported.document.pages.single.findShapeById(10)!.richText.plainText,
          testCase.text,
        );
        expect(
          VsdxToSvgSerializer().serializePage(
            imported.document.pages.single,
            images: imported.document.images,
          ),
          contains(testCase.text),
        );

        final reopened = const DocumentParser().parse(imported.originalBytes);
        expect(reopened.title, testCase.text);
        expect(
          reopened.pages.single.findShapeById(10)!.richText.plainText,
          testCase.text,
        );
      }
    });
  });
}
