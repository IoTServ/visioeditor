import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:vsdx/src/parser/style_parser.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

/// Replace one part inside a .vsdx zip and return the re-encoded bytes.
Uint8List _rezipWith(Uint8List src, String partName, List<int> newBytes) {
  final archive = ZipDecoder().decodeBytes(src);
  final out = Archive();
  final target = partName.startsWith('/') ? partName.substring(1) : partName;
  for (final f in archive) {
    if (f.name == target) {
      out.addFile(ArchiveFile(f.name, newBytes.length, newBytes));
    } else {
      out.addFile(ArchiveFile(f.name, f.size, f.content));
    }
  }
  return Uint8List.fromList(ZipEncoder().encode(out)!);
}

Map<String, String?> _shapeCellFormulas(
  Uint8List bytes,
  int shapeId,
  Iterable<String> names,
) {
  final pkg = VsdxPackage.open(bytes);
  final pagePart =
      pkg.allPartNames.firstWhere((p) => p.endsWith('pages/page1.xml'));
  final xml = pkg.readPartXml(pagePart)!;
  final shape = xml.descendants.whereType<XmlElement>().firstWhere(
        (e) =>
            e.name.local == 'Shape' &&
            e.getAttribute('ID') == shapeId.toString(),
      );
  final cells = <String, XmlElement>{
    for (final e in shape.childElements)
      if (e.name.local == 'Cell' && e.getAttribute('N') != null)
        e.getAttribute('N')!: e,
  };
  return <String, String?>{
    for (final name in names) name: cells[name]?.getAttribute('F'),
  };
}

void main() {
  const parser = DocumentParser();
  const writer = VsdxWriter();

  test('identity save preserves 1D XForm and theme formulas', () {
    final cases = <({
      String fixture,
      int shapeId,
      List<String> cells,
    })>[
      (
        fixture: 'test9_rect_and_line.vsdx',
        shapeId: 2,
        cells: <String>[
          'PinX',
          'PinY',
          'Width',
          'LocPinX',
          'LocPinY',
          'TextBkgnd',
        ],
      ),
      (
        fixture: 'test4_connectors.vsdx',
        shapeId: 6,
        cells: <String>[
          'PinX',
          'PinY',
          'Width',
          'Height',
          'LocPinX',
          'LocPinY',
        ],
      ),
      (
        fixture: '数据治理.vsdx',
        shapeId: 137,
        cells: <String>[
          'PinX',
          'PinY',
          'Width',
          'Height',
          'LocPinX',
          'LocPinY',
          'FlipX',
          'FlipY',
        ],
      ),
    ];

    for (final testCase in cases) {
      final raw = _fixture(testCase.fixture);
      final before = _shapeCellFormulas(raw, testCase.shapeId, testCase.cells);
      final out = writer.write(originalBytes: raw, edited: parser.parse(raw));
      final after = _shapeCellFormulas(out, testCase.shapeId, testCase.cells);
      expect(
        after,
        before,
        reason: '${testCase.fixture} shape ${testCase.shapeId}',
      );
    }
  });

  // Regression: the writer must serialise a cell's `V` in Visio's internal
  // units (inches), leaving the `U` *display* attribute alone — mirroring the
  // parser. workflow.vsdx's `PageWidth` carries `U="MM"`; writing 20 in must
  // emit `V="20"` (not the millimetre value 508), so Visio / libvisio read it
  // back correctly.
  test('writes cell V in internal inches even when U is a non-inch unit', () {
    final bytes = _fixture('workflow.vsdx');
    final doc = parser.parse(bytes);
    final page = doc.pages.first;
    expect(page.widthInches, closeTo(11.9583, 0.01)); // fixture sanity

    final edited =
        doc.replacePage(0, page.copyWith(widthInches: 20, heightInches: 15));
    final out = writer.write(originalBytes: bytes, edited: edited);

    // Re-parsing preserves the inch dimensions.
    final reparsed = parser.parse(out).pages.first;
    expect(reparsed.widthInches, closeTo(20, 1e-3));
    expect(reparsed.heightInches, closeTo(15, 1e-3));

    // The raw serialized value is the inch number, and the display unit is kept.
    final pkg = VsdxPackage.open(out);
    final pagesPart =
        pkg.allPartNames.firstWhere((p) => p.endsWith('pages/pages.xml'));
    final pageWidth = pkg
        .readPartXml(pagesPart)!
        .descendants
        .whereType<XmlElement>()
        .firstWhere((e) =>
            e.name.local == 'Cell' && e.getAttribute('N') == 'PageWidth');
    expect(double.parse(pageWidth.getAttribute('V')!), closeTo(20, 1e-3));
    expect(pageWidth.getAttribute('U'), 'MM'); // display unit untouched
  });

  test('round-trips an edited pin position (Slice-0)', () {
    final bytes = _fixture('test9_rect_and_line.vsdx');
    final doc = parser.parse(bytes);
    final page = doc.pages.first;
    final target = page.shapes.first;

    final edited = doc.replacePage(
      0,
      page.updateShapeById(
        target.id,
        (s) => s.copyWith(pinX: s.pinX + 1.0, pinY: s.pinY - 0.5),
      ),
    );

    final outBytes = writer.write(originalBytes: bytes, edited: edited);
    final reopened = parser.parse(outBytes);
    final moved = reopened.pages.first.findShapeById(target.id)!;

    expect(moved.pinX, closeTo(target.pinX + 1.0, 1e-4));
    expect(moved.pinY, closeTo(target.pinY - 0.5, 1e-4));
  });

  test('leaves untouched shapes and pages unchanged', () {
    final bytes = _fixture('test9_rect_and_line.vsdx');
    final doc = parser.parse(bytes);
    final page = doc.pages.first;
    if (page.shapes.length < 2) return; // fixture has a single shape

    final target = page.shapes.first;
    final other = page.shapes[1];
    final edited = doc.replacePage(
      0,
      page.updateShapeById(
        target.id,
        (s) => s.copyWith(pinX: s.pinX + 1.0),
      ),
    );

    final reopened = parser.parse(
      writer.write(originalBytes: bytes, edited: edited),
    );
    final otherAfter = reopened.pages.first.findShapeById(other.id)!;
    expect(otherAfter.pinX, closeTo(other.pinX, 1e-9));
    expect(otherAfter.pinY, closeTo(other.pinY, 1e-9));
  });

  test('no-op save preserves values and all part names', () {
    final bytes = _fixture('test1.vsdx');
    final doc = parser.parse(bytes);

    final outBytes = writer.write(originalBytes: bytes, edited: doc);

    // Every part of the original package survives verbatim.
    final before = VsdxPackage.open(bytes).allPartNames.toSet();
    final after = VsdxPackage.open(outBytes).allPartNames.toSet();
    expect(after, equals(before));

    // Values are stable across a no-edit round-trip.
    final reopened = parser.parse(outBytes);
    expect(reopened.pages.length, doc.pages.length);
    final a = doc.pages.first.shapes.first;
    final b = reopened.pages.first.findShapeById(a.id)!;
    expect(b.pinX, closeTo(a.pinX, 1e-9));
    expect(b.pinY, closeTo(a.pinY, 1e-9));
  });

  test('creates a rectangle that survives a round-trip', () {
    final bytes = _fixture('test1.vsdx');
    final doc = parser.parse(bytes);
    final page = doc.pages.first;
    final id = page.nextFreeShapeId();
    final rect = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 3,
      pinY: 4,
      width: 2,
      height: 1,
    );
    final edited = doc.replacePage(0, page.addShape(rect));

    final reopened = parser.parse(
      writer.write(originalBytes: bytes, edited: edited),
    );
    final created = reopened.pages.first.findShapeById(id);
    expect(created, isNotNull);
    expect(created!.pinX, closeTo(3, 1e-4));
    expect(created.pinY, closeTo(4, 1e-4));
    expect(created.width, closeTo(2, 1e-4));
    expect(created.height, closeTo(1, 1e-4));
    expect(created.geometries, isNotEmpty);
  });

  test('creates a borderless text box that survives a round-trip', () {
    final bytes = _fixture('test1.vsdx');
    final doc = parser.parse(bytes);
    final page = doc.pages.first;
    final id = page.nextFreeShapeId();
    final box = VsdxShapeFactory.textBox(
      id: id,
      pinX: 3,
      pinY: 4,
      width: 2,
      height: 0.5,
      text: 'Label',
    );
    final edited = doc.replacePage(0, page.addShape(box));

    final reopened = parser.parse(
      writer.write(originalBytes: bytes, edited: edited),
    );
    final created = reopened.pages.first.findShapeById(id);
    expect(created, isNotNull);
    // No fill, no border — only the label is drawn.
    expect(created!.fill.pattern, 0);
    expect(created.line.pattern, 0);
    final text = created.richText.runs.isNotEmpty
        ? created.richText.plainText
        : (created.text ?? '');
    expect(text, 'Label');
  });

  test('deletes a shape across a round-trip', () {
    final bytes = _fixture('test1.vsdx');
    final doc = parser.parse(bytes);
    final page = doc.pages.first;
    final victim = page.shapes.first.id;
    final edited = doc.replacePage(0, page.removeShapeById(victim));

    final reopened = parser.parse(
      writer.write(originalBytes: bytes, edited: edited),
    );
    expect(reopened.pages.first.findShapeById(victim), isNull);
  });

  test('emits a valid blank document that accepts new shapes', () {
    final blank = writer.emptyDocument();
    final doc = parser.parse(blank);
    expect(doc.pages, hasLength(1));
    expect(doc.pages.first.shapes, isEmpty);
    expect(doc.pages.first.widthInches, closeTo(8.5, 1e-6));

    final page = doc.pages.first;
    final id = page.nextFreeShapeId();
    final withRect = doc.replacePage(
      0,
      page.addShape(VsdxShapeFactory.rectangle(
        id: id,
        pinX: 2,
        pinY: 2,
        width: 1,
        height: 1,
      )),
    );
    final reopened = parser.parse(
      writer.write(originalBytes: blank, edited: withRect),
    );
    expect(reopened.pages.first.findShapeById(id), isNotNull);
  });

  test('new shapes always emit LocPin (Edraw/libvisio default is 0,0)', () {
    // Untitled333.vsdx regression: omitting LocPin made Edraw/libvisio treat
    // the pin as the shape's bottom-left, shifting every centred shape by
    // half its width/height versus this editor (and Visio's Width*0.5 default).
    final blank = writer.emptyDocument();
    final doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final edited = doc.replacePage(
      0,
      doc.pages.first.addShape(VsdxShapeFactory.rectangle(
        id: id,
        pinX: 4.25,
        pinY: 9.75,
        width: 1.5,
        height: 1.0,
      )),
    );
    final out = writer.write(originalBytes: blank, edited: edited);
    final pageXml = VsdxPackage.open(out)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(pageXml, contains('N="LocPinX"'));
    expect(pageXml, contains('N="LocPinY"'));
    expect(pageXml, contains('Width*0.5'));
    expect(pageXml, contains('Height*0.5'));

    final reopened = parser.parse(out).pages.first.findShapeById(id)!;
    expect(reopened.effectiveLocPinX, closeTo(0.75, 1e-6));
    expect(reopened.effectiveLocPinY, closeTo(0.5, 1e-6));
  });

  test('new connectors emit ObjType=2', () {
    final blank = writer.emptyDocument();
    final doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final edited = doc.replacePage(
      0,
      doc.pages.first.addShape(VsdxShapeFactory.line(
        id: id,
        ax: 1,
        ay: 1,
        bx: 3,
        by: 2,
      )),
    );
    final out = writer.write(originalBytes: blank, edited: edited);
    final pageXml = VsdxPackage.open(out)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(pageXml, contains('N="ObjType"'));
    expect(pageXml, contains('V="2"'));
    expect(parser.parse(out).pages.first.findShapeById(id)!.objType, 2);
  });

  test('freehand stroke round-trips as 1-D MoveTo/LineTo ink (ObjType=1)', () {
    final blank = writer.emptyDocument();
    final doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final stroke = VsdxShapeFactory.freehand(
      id: id,
      points: const <Offset2D>[
        Offset2D(1, 1),
        Offset2D(2, 2.5),
        Offset2D(4, 1.5),
      ],
    );
    final edited = doc.replacePage(0, doc.pages.first.addShape(stroke));
    final out = writer.write(originalBytes: blank, edited: edited);
    final again = parser.parse(out).pages.first.findShapeById(id)!;
    expect(again.is1D, isTrue);
    expect(again.objType, 1); // not a glueable connector
    expect(again.beginX, closeTo(1, 1e-6));
    expect(again.endX, closeTo(4, 1e-6));
    expect(again.geometries.single.commands.length, 3);
    expect(
      again.geometries.single.commands.every((c) => c is MoveTo || c is LineTo),
      isTrue,
    );
  });

  test('emptyDocument ships StyleSheets and FaceNames for Edraw', () {
    final blank = writer.emptyDocument();
    final docXml = VsdxPackage.open(blank)
        .readPartXml('/visio/document.xml')!
        .toXmlString();
    expect(docXml, contains('<StyleSheets>'));
    expect(docXml, contains('NameU="No Style"'));
    expect(docXml, contains('<FaceNames>'));
  });

  test('filled shapes emit NoFill=0 so Edraw does not hollow them', () {
    // 万兴图示 defaults a missing Geometry/NoFill cell to 1 (no fill).
    final blank = writer.emptyDocument();
    final doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 4,
      pinY: 5,
      width: 1.5,
      height: 1.0,
    ).copyWith(
      fill: const VsdxFill(foreground: VsdxColor(0xFF42A5F5), pattern: 1),
    );
    final out = writer.write(
      originalBytes: blank,
      edited: doc.replacePage(0, doc.pages.first.addShape(shape)),
    );
    final pageXml = VsdxPackage.open(out)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(pageXml, contains('N="NoFill" V="0"'));
    expect(pageXml, contains('N="NoLine" V="0"'));
    expect(pageXml, contains('N="FillForegnd" V="#42A5F5"'));
  });

  test('plain .text emits Character/Paragraph + pp/cp for Edraw', () {
    final blank = writer.emptyDocument();
    final doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    // Plain text without rich runs — the path Untitled333 used.
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 4,
      pinY: 5,
      width: 1.2,
      height: 0.5,
    ).copyWith(text: 'Text');
    final edited = doc.replacePage(0, doc.pages.first.addShape(shape));
    final out = writer.write(originalBytes: blank, edited: edited);
    final pageXml = VsdxPackage.open(out)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(pageXml, contains('N="Character"'));
    expect(pageXml, contains('N="Paragraph"'));
    expect(pageXml, contains('<pp'));
    expect(pageXml, contains('<cp'));
    expect(pageXml, contains('N="LineCap"'));
    expect(pageXml, contains('N="VerticalAlign"'));
    expect(pageXml, contains('N="TxtPinX"'));
    expect(pageXml, contains('AsianFont'));
    expect(pageXml, contains('HorzAlign'));
    // Proportional size for 0.5" tall box: 0.5*0.18 = 0.09".
    expect(pageXml, contains('N="Size"'));
    final reopened = parser.parse(out).pages.first.findShapeById(id)!;
    expect(reopened.richText.runs, isNotEmpty);
    expect(reopened.richText.runs.first.charStyle.fontSizeInches,
        closeTo(0.09, 1e-4));
    expect(reopened.richText.runs.first.paraStyle.horizontalAlign,
        VsdxHorzAlign.center);
  });

  test('Paragraph full alignment writes and reopens as HorzAlign 4', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 3,
      height: 1,
    ).copyWith(
      richText: const VsdxRichText(runs: <VsdxTextRun>[
        VsdxTextRun(
          text: 'Distributed',
          paraStyle: VsdxParaStyle(
            horizontalAlign: VsdxHorzAlign.full,
          ),
        ),
      ]),
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));

    final out = writer.write(originalBytes: blank, edited: doc);
    final pageXml = VsdxPackage.open(out)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(pageXml, contains('N="HorzAlign" V="4"'));
    final reopened = parser.parse(out).pages.first.findShapeById(id)!;
    expect(
      reopened.richText.runs.first.paraStyle.horizontalAlign,
      VsdxHorzAlign.full,
    );
  });

  test('heal injects missing docProps/core.xml on save', () {
    // test5_master references core in .rels but the part is absent.
    final bytes = File('test/fixtures/test5_master.vsdx').readAsBytesSync();
    expect(
      VsdxPackage.open(bytes).readPartBytes('/docProps/core.xml'),
      isNull,
    );
    final doc = parser.parse(bytes);
    final out = writer.write(originalBytes: bytes, edited: doc);
    final pkg = VsdxPackage.open(out);
    final core = pkg.readPartBytes('/docProps/core.xml');
    expect(core, isNotNull);
    final coreBytes = core!;
    expect(utf8.decode(coreBytes), contains('coreProperties'));
    expect(utf8.decode(coreBytes), contains('dc:creator'));
  });

  test('save adds Character when Text has pp but no Character section', () {
    final bytes = File('test/fixtures/test2.vsdx').readAsBytesSync();
    final doc = parser.parse(bytes);
    final out = writer.write(originalBytes: bytes, edited: doc);
    final pageXml = VsdxPackage.open(out)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    // Shape 9 historically had Paragraph + <pp> only — Edraw needs Character.
    expect(pageXml, contains('N="Character"'));
    final issues = <String>[];
    final xml = XmlDocument.parse(pageXml);
    for (final sh in xml.findAllElements('Shape')) {
      final texts = sh.findElements('Text');
      if (texts.isEmpty || texts.first.innerText.trim().isEmpty) continue;
      final hasChar = sh.childElements.any(
        (c) => c.name.local == 'Section' && c.getAttribute('N') == 'Character',
      );
      if (!hasChar) issues.add('id=${sh.getAttribute('ID')}');
    }
    expect(issues, isEmpty, reason: 'text without Character: $issues');
  });

  test('Foreign picture caption emits Character/Paragraph', () {
    final blank = writer.emptyDocument();
    final doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    const part = '/visio/media/image_caption_test.png';
    final png = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x00,
    ]);
    final shape = VsdxShapeFactory.picture(
      id: id,
      pinX: 2,
      pinY: 3,
      width: 1,
      height: 1,
      imagePartName: part,
    ).copyWith(text: 'Caption');
    final edited = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: png, mimeType: 'image/png'),
          ),
        )
        .replacePage(0, doc.pages.first.addShape(shape));
    final out = writer.write(originalBytes: blank, edited: edited);
    final pageXml = VsdxPackage.open(out)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(pageXml, contains('Type="Foreign"'));
    expect(pageXml, contains('N="Character"'));
    expect(pageXml, contains('N="Paragraph"'));
    expect(pageXml, contains('Caption'));
    expect(pageXml, contains('<pp'));
  });

  test('Chinese labels emit Microsoft YaHei AsianFont for Edraw', () {
    final blank = writer.emptyDocument();
    final doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 4,
      pinY: 5,
      width: 1.6,
      height: 0.9,
    ).copyWith(text: '开始');
    final out = writer.write(
      originalBytes: blank,
      edited: doc.replacePage(0, doc.pages.first.addShape(shape)),
    );
    final pageXml = VsdxPackage.open(out)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(pageXml, contains('Microsoft YaHei'));
    expect(pageXml, contains('zh-CN'));
    expect(pageXml, contains('开始'));
    final docXml =
        VsdxPackage.open(out).readPartXml('/visio/document.xml')!.toXmlString();
    expect(docXml, contains('Microsoft YaHei'));
  });

  test('re-saving labelled shape without TxtPin injects centred text box', () {
    // Brand-new write, then strip Txt* / VerticalAlign to mimic Untitled333.
    final blank = writer.emptyDocument();
    final doc0 = parser.parse(blank);
    final id = doc0.pages.first.nextFreeShapeId();
    final withText = doc0.replacePage(
      0,
      doc0.pages.first.addShape(VsdxShapeFactory.rectangle(
        id: id,
        pinX: 4,
        pinY: 5,
        width: 1.2,
        height: 0.5,
      ).copyWith(text: 'Text')),
    );
    final mid = writer.write(originalBytes: blank, edited: withText);
    final pkg = VsdxPackage.open(mid);
    final pageXml = pkg.readPartXml('/visio/pages/page1.xml')!;
    for (final shape in pageXml.rootElement.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'Shape')) {
      for (final cell in shape.descendants.whereType<XmlElement>().toList()) {
        if (cell.name.local != 'Cell') continue;
        final n = cell.getAttribute('N') ?? '';
        if (n.startsWith('Txt') ||
            n == 'VerticalAlign' ||
            n.endsWith('Margin')) {
          cell.remove();
        }
        // Simulate older exports that wrote left-aligned labels.
        if (n == 'HorzAlign') {
          cell.setAttribute('V', '0');
        }
      }
    }
    final stripped = _rezipWith(
      mid,
      'visio/pages/page1.xml',
      utf8.encode(pageXml.toXmlString()),
    );
    final reopened = parser.parse(stripped);
    expect(
      reopened.pages.first
          .findShapeById(id)!
          .richText
          .runs
          .first
          .paraStyle
          .horizontalAlign,
      VsdxHorzAlign.left,
    );
    final out = writer.write(originalBytes: stripped, edited: reopened);
    final outPage = VsdxPackage.open(out)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(outPage, contains('N="TxtPinX"'));
    expect(outPage, contains('N="TxtWidth"'));
    expect(outPage, contains('N="VerticalAlign"'));
    expect(outPage, contains('F="Width*0.5"'));
    // Explicit left HorzAlign must survive text-box heal (do not force center).
    expect(outPage, contains('N="HorzAlign" V="0"'));
  });

  test('re-saving a legacy blank export injects LocPin + StyleSheets', () {
    // Simulate Untitled333: shapes without LocPin, document without StyleSheets.
    final legacyBlank = writer.emptyDocument();
    // Strip StyleSheets from a copy to mimic the pre-fix blank.
    final pkg0 = VsdxPackage.open(legacyBlank);
    final docXml = pkg0.readPartXml('/visio/document.xml')!;
    for (final c in docXml.rootElement.childElements.toList()) {
      if (c.name.local == 'StyleSheets' || c.name.local == 'FaceNames') {
        c.remove();
      }
    }
    final stripped = _rezipWith(
      legacyBlank,
      'visio/document.xml',
      utf8.encode(docXml.toXmlString()),
    );
    final base = parser.parse(stripped);
    final id = base.pages.first.nextFreeShapeId();
    final edited = base.replacePage(
      0,
      base.pages.first.addShape(VsdxShapeFactory.rectangle(
        id: id,
        pinX: 4.25,
        pinY: 9.75,
        width: 1.5,
        height: 1.0,
      ).copyWith(text: 'Hi')),
    );
    // First write builds shapes with LocPin into stripped blank…
    final mid = writer.write(originalBytes: stripped, edited: edited);
    // …then parse + no-op save must still restore StyleSheets on document.xml.
    final midDoc = parser.parse(mid);
    final out = writer.write(originalBytes: mid, edited: midDoc);
    final outDoc =
        VsdxPackage.open(out).readPartXml('/visio/document.xml')!.toXmlString();
    expect(outDoc, contains('<StyleSheets>'));
    final pageXml = VsdxPackage.open(out)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(pageXml, contains('N="LocPinX"'));
    expect(pageXml, contains('N="Character"'));
  });

  test('rotates a shape across a round-trip', () {
    final bytes = _fixture('test9_rect_and_line.vsdx');
    final doc = parser.parse(bytes);
    final page = doc.pages.first;
    final target = page.shapes.first;
    final edited = doc.replacePage(
      0,
      page.updateShapeById(target.id, (s) => s.copyWith(angleRad: 0.5)),
    );
    final reopened = parser.parse(
      writer.write(originalBytes: bytes, edited: edited),
    );
    expect(reopened.pages.first.findShapeById(target.id)!.angleRad,
        closeTo(0.5, 1e-4));
  });

  test('resized geometry round-trips (existing-shape geometry patch)', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(VsdxShapeFactory.rectangle(
        id: id,
        pinX: 3,
        pinY: 3,
        width: 1,
        height: 1,
      )),
    );
    // Save + reopen so the rectangle becomes an *existing* shape.
    final bytes1 = writer.write(originalBytes: blank, edited: doc);
    final r1 = parser.parse(bytes1);

    // Resize it to 3x1 and round-trip again.
    final resized = r1.replacePage(
      0,
      r1.pages.first.updateShapeById(
        id,
        (s) => s.resizeTo(pinX: s.pinX, pinY: s.pinY, width: 3, height: 1),
      ),
    );
    final r2 =
        parser.parse(writer.write(originalBytes: bytes1, edited: resized));
    final s2 = r2.pages.first.findShapeById(id)!;
    expect(s2.width, closeTo(3, 1e-4));
    final xs = s2.geometries
        .expand((g) => g.commands)
        .whereType<LineTo>()
        .map((c) => c.x)
        .toList();
    expect(xs.reduce((a, b) => a > b ? a : b), closeTo(3, 1e-3));
  });

  test('RelCubBezTo geometry survives resize → save → reopen', () {
    final bytes = _fixture('workflow.vsdx');
    final doc = parser.parse(bytes);
    final page = doc.pages.first;
    VsdxShape? target;
    for (final s in page.shapes) {
      final n = s.geometries
          .expand((g) => g.commands)
          .whereType<RelCubBezTo>()
          .length;
      if (n > 0) {
        target = s;
        break;
      }
    }
    expect(target, isNotNull);
    final before = target!.geometries
        .expand((g) => g.commands)
        .whereType<RelCubBezTo>()
        .length;
    final resized = doc.replacePage(
      0,
      page.updateShapeById(
        target.id,
        (s) => s.resizeTo(
          pinX: s.pinX,
          pinY: s.pinY,
          width: s.width * 1.5,
          height: s.height * 1.5,
        ),
      ),
    );
    final reopened = parser.parse(
      writer.write(originalBytes: bytes, edited: resized),
    );
    final after = reopened.pages.first.findShapeById(target.id)!;
    final afterCount = after.geometries
        .expand((g) => g.commands)
        .whereType<RelCubBezTo>()
        .length;
    expect(afterCount, before);
    expect(after.width, closeTo(target.width * 1.5, 1e-4));
  });

  test('master-instance partial geometry override survives resize round-trip',
      () {
    // test9 shape 3 inherits MoveTo(0,0) from its master, overrides LineTo IX=2
    // and deletes IX=3. After a resize + save + reparse the geometry must stay
    // [MoveTo, LineTo] — the deleted master row must not re-inherit.
    final bytes = _fixture('test9_rect_and_line.vsdx');
    final doc = parser.parse(bytes);
    final target = doc.pages.first.findShapeById(3)!;
    expect(target.geometries.single.commands, hasLength(2));

    final resized = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        3,
        (s) => s.resizeTo(
          pinX: s.pinX,
          pinY: s.pinY,
          width: s.width * 1.5,
          height: s.height * 1.5,
        ),
      ),
    );
    final out = writer.write(originalBytes: bytes, edited: resized);
    final after = parser.parse(out).pages.first.findShapeById(3)!;
    final cmds = after.geometries.single.commands;
    expect(cmds, hasLength(2),
        reason: 'deleted master row must not re-inherit after rebuild');
    expect(cmds[0], isA<MoveTo>());
    expect(cmds[1], isA<LineTo>());
  });

  test('text-block TxtPin / TxtAngle / margins round-trip on new shape', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final block = VsdxTextBlock(
      pinXInches: 0.25,
      pinYInches: 0.5,
      locPinXInches: 0.1,
      locPinYInches: 0.2,
      widthInches: 1.5,
      heightInches: 0.75,
      angleRad: 0.3,
      verticalAlign: VsdxVertAlign.top,
      marginLeftInches: 0.1,
      marginRightInches: 0.11,
      marginTopInches: 0.12,
      marginBottomInches: 0.13,
    );
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          richText: VsdxRichText(
            runs: const <VsdxTextRun>[VsdxTextRun(text: 'Label')],
            textBlock: block,
          ),
        ),
      ),
    );
    final after = parser
        .parse(writer.write(originalBytes: blank, edited: doc))
        .pages
        .first
        .findShapeById(id)!
        .richText
        .textBlock;
    expect(after.pinXInches, closeTo(0.25, 1e-6));
    expect(after.pinYInches, closeTo(0.5, 1e-6));
    expect(after.locPinXInches, closeTo(0.1, 1e-6));
    expect(after.locPinYInches, closeTo(0.2, 1e-6));
    expect(after.widthInches, closeTo(1.5, 1e-6));
    expect(after.heightInches, closeTo(0.75, 1e-6));
    expect(after.angleRad, closeTo(0.3, 1e-6));
    expect(after.verticalAlign, VsdxVertAlign.top);
    expect(after.marginLeftInches, closeTo(0.1, 1e-6));
    expect(after.marginRightInches, closeTo(0.11, 1e-6));
    expect(after.marginTopInches, closeTo(0.12, 1e-6));
    expect(after.marginBottomInches, closeTo(0.13, 1e-6));
  });

  test('absolute caption below scrubs stale Height* TxtPinY on save', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    // First write with centred Height* formulas (as Visio masters often do).
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 0.75,
          height: 0.75,
        ).copyWith(
          text: 'Cloud',
          formulas: const <String, String>{
            'TxtPinX': 'Width*0.5',
            'TxtPinY': 'Height*0.5',
            'TxtWidth': 'Width*1',
            'TxtHeight': 'Height*1',
          },
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[VsdxTextRun(text: 'Cloud')],
            textBlock: VsdxTextBlock(
              pinXInches: 0.375,
              pinYInches: 0.375,
              widthInches: 0.75,
              heightInches: 0.75,
            ),
          ),
        ),
      ),
    );
    final bytes = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(bytes);
    const labelH = 0.22;
    // Hang caption below: pin on bottom edge, locPin at top of label
    // (Edraw-safe; avoids negative TxtPinY).
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          formulas: Map<String, String>.of(s.formulas)
            ..remove('TxtPinX')
            ..remove('TxtPinY')
            ..remove('TxtWidth')
            ..remove('TxtHeight')
            ..remove('TxtLocPinX')
            ..remove('TxtLocPinY'),
          richText: s.richText.copyWith(
            textBlock: VsdxTextBlock(
              pinXInches: 0.375,
              pinYInches: 0,
              locPinXInches: 0.375,
              locPinYInches: labelH,
              widthInches: 0.75,
              heightInches: labelH,
            ),
          ),
        ),
      ),
    );
    final out = writer.write(originalBytes: bytes, edited: doc);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.richText.textBlock.pinYInches, closeTo(0, 1e-6));
    expect(after.richText.textBlock.locPinYInches, closeTo(labelH, 1e-6));
    expect(after.formulas['TxtPinY'], isNull);
    // Resize after reopen must not snap the caption back into the box.
    final grown = after.resizeTo(
      pinX: after.pinX,
      pinY: after.pinY,
      width: 1.5,
      height: 1.5,
    );
    expect(grown.richText.textBlock.pinYInches, closeTo(0, 1e-6));
    expect(
      grown.richText.textBlock.pinYInches! -
          grown.richText.textBlock.locPinYInches!,
      lessThan(0),
    );
  });

  test('Foreign picture caption below uses non-negative TxtPinY for Edraw', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    const part = '/visio/media/image_caption_below.png';
    final png = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x00,
    ]);
    const labelH = 0.22;
    final shape = VsdxShapeFactory.picture(
      id: id,
      pinX: 2,
      pinY: 3,
      width: 0.75,
      height: 0.75,
      imagePartName: part,
    ).copyWith(
      text: 'Cloud',
      richText: VsdxRichText(
        runs: const <VsdxTextRun>[
          VsdxTextRun(
            text: 'Cloud',
            paraStyle: VsdxParaStyle(horizontalAlign: VsdxHorzAlign.center),
          ),
        ],
        textBlock: VsdxTextBlock(
          pinXInches: 0.375,
          pinYInches: 0,
          locPinXInches: 0.375,
          locPinYInches: labelH,
          widthInches: 0.75,
          heightInches: labelH,
          verticalAlign: VsdxVertAlign.middle,
        ),
      ),
    );
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: png, mimeType: 'image/png'),
          ),
        )
        .replacePage(0, doc.pages.first.addShape(shape));
    final out = writer.write(originalBytes: blank, edited: doc);
    final pageXml = VsdxPackage.open(out)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(pageXml, contains('Type="Foreign"'));
    expect(pageXml, contains('Cloud'));
    // EdrawMax ignores / clamps negative TxtPinY — export must stay ≥ 0.
    expect(pageXml, isNot(contains('N="TxtPinY" V="-')));
    expect(pageXml, contains('N="TxtPinY" V="0"'));
    expect(pageXml, contains('N="TxtLocPinY" V="0.22"'));
    expect(pageXml, contains('N="TxtHeight" V="0.22"'));
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.richText.textBlock.pinYInches, closeTo(0, 1e-6));
    expect(after.richText.textBlock.locPinYInches, closeTo(labelH, 1e-6));
  });

  test('writer rewrites negative TxtPinY caption into Edraw-safe form', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    const part = '/visio/media/image_neg_pin.png';
    final png = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ]);
    const labelH = 0.22;
    // Legacy model used negative TxtPinY; export must rewrite for Edraw.
    final shape = VsdxShapeFactory.picture(
      id: id,
      pinX: 2,
      pinY: 3,
      width: 0.75,
      height: 0.75,
      imagePartName: part,
    ).copyWith(
      text: 'Cloud',
      richText: VsdxRichText(
        runs: const <VsdxTextRun>[VsdxTextRun(text: 'Cloud')],
        textBlock: VsdxTextBlock(
          pinXInches: 0.375,
          pinYInches: -labelH / 2,
          locPinXInches: 0.375,
          locPinYInches: labelH / 2,
          widthInches: 0.75,
          heightInches: labelH,
        ),
      ),
    );
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: png, mimeType: 'image/png'),
          ),
        )
        .replacePage(0, doc.pages.first.addShape(shape));
    final pageXml =
        VsdxPackage.open(writer.write(originalBytes: blank, edited: doc))
            .readPartXml('/visio/pages/page1.xml')!
            .toXmlString();
    expect(pageXml, isNot(contains('N="TxtPinY" V="-')));
    expect(pageXml, contains('N="TxtPinY" V="0"'));
    expect(pageXml, contains('N="TxtLocPinY" V="0.22"'));
  });

  test('clearing Txt* formulas scrubs SETATREF from XML even when V matches',
      () {
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
          text: 'Label',
          formulas: const <String, String>{
            'TxtPinX': 'SETATREF(Controls.TextPosition)',
            'TxtPinY': 'SETATREF(Controls.TextPosition.Y)',
            'TxtWidth': 'TEXTWIDTH(TheText)',
          },
          controls: const <VsdxControlRow>[
            VsdxControlRow(name: 'TextPosition', x: 0.5, y: 0.5),
          ],
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[VsdxTextRun(text: 'Label')],
            textBlock: VsdxTextBlock(
              pinXInches: 0.5,
              pinYInches: 0.5,
              widthInches: 1,
              heightInches: 1,
            ),
          ),
        ),
      ),
    );
    final bytes = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(bytes);
    expect(doc.pages.first.findShapeById(id)!.formulas['TxtPinX'],
        contains('SETATREF'));
    // Absolute caption placement clears formulas but keeps the same pin V.
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          formulas: Map<String, String>.of(s.formulas)
            ..remove('TxtPinX')
            ..remove('TxtPinY')
            ..remove('TxtWidth')
            ..remove('TxtHeight'),
          richText: s.richText.copyWith(
            textBlock: const VsdxTextBlock(
              pinXInches: 0.5,
              pinYInches: 0,
              locPinXInches: 0.5,
              locPinYInches: 0.22,
              widthInches: 1,
              heightInches: 0.22,
            ),
          ),
        ),
      ),
    );
    final out = writer.write(originalBytes: bytes, edited: doc);
    final pageXml = VsdxPackage.open(out)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(pageXml, isNot(contains('SETATREF(Controls.TextPosition')));
    expect(pageXml, isNot(contains('TEXTWIDTH(TheText)')));
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.formulas['TxtPinX'], isNull);
    expect(after.formulas['TxtPinY'], isNull);
    expect(after.richText.textBlock.pinYInches, closeTo(0, 1e-6));
  });

  test('page rename round-trips', () {
    final bytes = _fixture('test1.vsdx');
    final doc = parser.parse(bytes);
    final renamed = doc.replacePage(
      0,
      doc.pages.first.copyWith(name: 'Renamed Page'),
    );
    final reopened =
        parser.parse(writer.write(originalBytes: bytes, edited: renamed));
    expect(reopened.pages.first.name, 'Renamed Page');
  });

  test('adding a page round-trips (new part + rels + content-type)', () {
    final bytes = _fixture('test1.vsdx');
    final doc = parser.parse(bytes);
    final before = doc.pages.length;
    final newPage = VsdxPage(
      id: doc.nextPageId(),
      name: 'Added',
      widthInches: 8.5,
      heightInches: 11,
      shapes: [
        VsdxShapeFactory.rectangle(
            id: 1, pinX: 3, pinY: 3, width: 2, height: 1),
      ],
    );
    final edited = doc.insertPage(doc.pages.length, newPage);
    final reopened =
        parser.parse(writer.write(originalBytes: bytes, edited: edited));
    expect(reopened.pages.length, before + 1);
    final added = reopened.pages.firstWhere((p) => p.name == 'Added');
    expect(added.shapes, isNotEmpty);
    // original page 0 survives intact
    expect(reopened.pages.first.name, doc.pages.first.name);
  });

  test('deleting a page round-trips', () {
    // Build a 2-page doc first (blank + added), then delete one.
    final bytes = _fixture('test1.vsdx');
    final doc = parser.parse(bytes);
    final twoPage = doc.insertPage(
      doc.pages.length,
      VsdxPage(
        id: doc.nextPageId(),
        name: 'Temp',
        widthInches: 8.5,
        heightInches: 11,
        shapes: const [],
      ),
    );
    final bytes2 = writer.write(originalBytes: bytes, edited: twoPage);
    final r2 = parser.parse(bytes2);
    expect(r2.pages.length, doc.pages.length + 1);

    // Now delete the 'Temp' page.
    final tempIndex = r2.pages.indexWhere((p) => p.name == 'Temp');
    final afterDelete = r2.removePageAt(tempIndex);
    final r3 =
        parser.parse(writer.write(originalBytes: bytes2, edited: afterDelete));
    expect(r3.pages.length, doc.pages.length);
    expect(r3.pages.any((p) => p.name == 'Temp'), isFalse);
  });

  test('z-order (send to back) round-trips', () {
    final blank = writer.emptyDocument();
    final doc = parser.parse(blank);
    var page = doc.pages.first;
    final a = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.rectangle(
        id: a, pinX: 2, pinY: 2, width: 1, height: 1));
    final b = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.rectangle(
        id: b, pinX: 3, pinY: 3, width: 1, height: 1));
    final bytes1 =
        writer.write(originalBytes: blank, edited: doc.replacePage(0, page));
    final r1 = parser.parse(bytes1);
    expect(r1.pages.first.shapes.map((s) => s.id).toList(), [a, b]);

    final edited = r1.replacePage(0, r1.pages.first.sendToBack(b));
    final r2 =
        parser.parse(writer.write(originalBytes: bytes1, edited: edited));
    expect(r2.pages.first.shapes.map((s) => s.id).toList(), [b, a]);
  });

  test('flip flags round-trip', () {
    final bytes = _fixture('test9_rect_and_line.vsdx');
    final doc = parser.parse(bytes);
    final page = doc.pages.first;
    final target = page.shapes.first;
    final edited = doc.replacePage(
      0,
      page.updateShapeById(
        target.id,
        (s) => s.copyWith(flipX: true, flipY: true),
      ),
    );
    final reopened = parser.parse(
      writer.write(originalBytes: bytes, edited: edited),
    );
    final after = reopened.pages.first.findShapeById(target.id)!;
    expect(after.flipX, isTrue);
    expect(after.flipY, isTrue);
  });

  test('one-step z-order (bring forward) round-trips', () {
    final blank = writer.emptyDocument();
    final doc = parser.parse(blank);
    var page = doc.pages.first;
    final a = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.rectangle(
        id: a, pinX: 2, pinY: 2, width: 1, height: 1));
    final b = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.rectangle(
        id: b, pinX: 3, pinY: 3, width: 1, height: 1));
    final c = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.rectangle(
        id: c, pinX: 4, pinY: 4, width: 1, height: 1));
    final bytes1 =
        writer.write(originalBytes: blank, edited: doc.replacePage(0, page));
    final r1 = parser.parse(bytes1);
    expect(r1.pages.first.shapes.map((s) => s.id).toList(), [a, b, c]);

    // Bring the backmost shape one step forward: [a,b,c] -> [b,a,c].
    final edited = r1.replacePage(0, r1.pages.first.bringForward(a));
    final r2 =
        parser.parse(writer.write(originalBytes: bytes1, edited: edited));
    expect(r2.pages.first.shapes.map((s) => s.id).toList(), [b, a, c]);
  });

  test('in-group child z-order round-trips through the patch writer', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    final a = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.rectangle(
        id: a, pinX: 2, pinY: 2, width: 1, height: 1));
    final b = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.rectangle(
        id: b, pinX: 3.5, pinY: 2, width: 1, height: 1));
    final gid = page.nextFreeShapeId();
    page = page.group(<int>{a, b}, groupId: gid);
    final bytes1 =
        writer.write(originalBytes: blank, edited: doc.replacePage(0, page));
    final r1 = parser.parse(bytes1);
    final group = r1.pages.first.findShapeById(gid)!;
    expect(group.children.map((s) => s.id).toList(), [a, b]);

    // Bring the first child forward inside the group: [a,b] -> [b,a].
    final edited = r1.replacePage(0, r1.pages.first.bringForward(a));
    expect(
      edited.pages.first.findShapeById(gid)!.children.map((s) => s.id).toList(),
      [b, a],
    );
    final r2 =
        parser.parse(writer.write(originalBytes: bytes1, edited: edited));
    expect(
      r2.pages.first.findShapeById(gid)!.children.map((s) => s.id).toList(),
      [b, a],
    );
  });

  test('grouping then ungrouping shapes round-trips', () {
    // Two existing rectangles.
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    final a = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.rectangle(
        id: a, pinX: 2, pinY: 2, width: 1, height: 1));
    final b = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.rectangle(
        id: b, pinX: 5, pinY: 5, width: 1, height: 1));
    final bytes1 =
        writer.write(originalBytes: blank, edited: doc.replacePage(0, page));
    final r1 = parser.parse(bytes1);

    // Group A + B into a new group shape.
    final p1 = r1.pages.first;
    final gid = p1.nextFreeShapeId();
    final grouped = r1.replacePage(0, p1.group({a, b}, groupId: gid));
    final bytes2 = writer.write(originalBytes: bytes1, edited: grouped);
    final p2 = parser.parse(bytes2).pages.first;

    // Only the group is top-level; members are nested with local coords.
    expect(p2.shapes.map((s) => s.id).toList(), [gid]);
    final g = p2.shapes.first;
    expect(g.width, closeTo(4, 1e-3));
    expect(g.height, closeTo(4, 1e-3));
    expect(g.children.map((c) => c.id), containsAll(<int>[a, b]));
    final childA = g.children.firstWhere((c) => c.id == a);
    expect(childA.pinX, closeTo(0.5, 1e-3)); // 2 - (2-1) left edge
    expect(childA.pinY, closeTo(0.5, 1e-3));
    expect(p2.findShapeById(a), isNotNull); // recursion still finds it

    // Ungroup → children promoted back to their original page positions.
    final ungrouped = parser.parse(bytes2).replacePage(0, p2.ungroup(gid));
    final p3 = parser
        .parse(writer.write(originalBytes: bytes2, edited: ungrouped))
        .pages
        .first;
    expect(p3.findShapeById(gid), isNull);
    expect(p3.shapes.map((s) => s.id), containsAll(<int>[a, b]));
    final ra = p3.findShapeById(a)!;
    final rb = p3.findShapeById(b)!;
    expect(ra.pinX, closeTo(2, 1e-3));
    expect(ra.pinY, closeTo(2, 1e-3));
    expect(rb.pinX, closeTo(5, 1e-3));
    expect(rb.pinY, closeTo(5, 1e-3));
  });

  test('rounded rectangle (elliptical arcs) round-trips', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final rr = VsdxShapeFactory.roundedRectangle(
      id: id,
      pinX: 3,
      pinY: 3,
      width: 3,
      height: 2,
      radius: 0.5,
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(rr));
    final reopened =
        parser.parse(writer.write(originalBytes: blank, edited: doc));
    final s = reopened.pages.first.findShapeById(id)!;
    final cmds = s.geometries.first.commands;
    expect(cmds.first, isA<MoveTo>());
    expect((cmds.first as MoveTo).x, closeTo(0.5, 1e-4)); // MoveTo(r, 0)
    final arcs = cmds.whereType<EllipticalArcTo>().toList();
    expect(arcs.length, 4);
    // One corner arc ends at (width, r) = (3, 0.5).
    expect(
      arcs.any((a) => (a.x - 3).abs() < 1e-3 && (a.y - 0.5).abs() < 1e-3),
      isTrue,
    );
  });

  test('a polygon stencil shape round-trips', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final diamond = VsdxShapeFactory.polygon(
      id: id,
      pinX: 3,
      pinY: 3,
      width: 2,
      height: 2,
      unit: const [
        Offset2D(0.5, 1),
        Offset2D(1, 0.5),
        Offset2D(0.5, 0),
        Offset2D(0, 0.5),
      ],
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(diamond));
    final reopened =
        parser.parse(writer.write(originalBytes: blank, edited: doc));
    final s = reopened.pages.first.findShapeById(id);
    expect(s, isNotNull);
    expect(s!.geometries, isNotEmpty);
    expect(s.geometries.first.commands.length, greaterThanOrEqualTo(5));
  });

  test('composite stencil shapes (cube / cylinder / delay) round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final page = doc.pages.first;

    final cubeId = page.nextFreeShapeId();
    final p1 = page.addShape(VsdxShapeFactory.cube(
        id: cubeId, pinX: 3, pinY: 3, width: 2, height: 2));
    final cylId = p1.nextFreeShapeId();
    final p2 = p1.addShape(VsdxShapeFactory.cylinder(
        id: cylId, pinX: 6, pinY: 3, width: 1.5, height: 2));
    final delayId = p2.nextFreeShapeId();
    final p3 = p2.addShape(VsdxShapeFactory.delay(
        id: delayId, pinX: 3, pinY: 6, width: 2, height: 1));
    doc = doc.replacePage(0, p3);

    final reopened =
        parser.parse(writer.write(originalBytes: blank, edited: doc));

    // Cube: two geometries, the second (inner edges) suppresses fill.
    final rc = reopened.pages.first.findShapeById(cubeId)!;
    expect(rc.geometries.length, 2);
    expect(rc.geometries[1].noFill, isTrue);

    // Cylinder: barrel body + cap arc → elliptical arcs survive.
    final ry = reopened.pages.first.findShapeById(cylId)!;
    expect(
      ry.geometries.expand((g) => g.commands).whereType<EllipticalArcTo>(),
      isNotEmpty,
    );

    // Delay: the right semicircle arc survives.
    final rd = reopened.pages.first.findShapeById(delayId)!;
    expect(
      rd.geometries.first.commands.whereType<EllipticalArcTo>().length,
      greaterThanOrEqualTo(1),
    );
  });

  test('text formatting round-trips (Character/Paragraph created)', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final rect = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 3,
      pinY: 3,
      width: 2,
      height: 1,
    ).copyWith(text: 'Hi');
    doc = doc.replacePage(0, doc.pages.first.addShape(rect));
    final bytes1 = writer.write(originalBytes: blank, edited: doc);
    final r1 = parser.parse(bytes1);
    final s1 = r1.pages.first.findShapeById(id)!;

    final runs = s1.richText.runs.isNotEmpty
        ? s1.richText.runs
        : <VsdxTextRun>[VsdxTextRun(text: s1.text ?? 'Hi')];
    final newRuns = <VsdxTextRun>[
      for (final r in runs)
        r.copyWith(
          charStyle: r.charStyle.copyWith(
            fontSizeInches: 0.5,
            style: const VsdxFontStyle(bold: true),
            color: const VsdxColor(0xFF112233),
          ),
          paraStyle:
              r.paraStyle.copyWith(horizontalAlign: VsdxHorzAlign.center),
        ),
    ];
    final edited = r1.replacePage(
      0,
      r1.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(richText: s.richText.copyWith(runs: newRuns)),
      ),
    );
    final r2 =
        parser.parse(writer.write(originalBytes: bytes1, edited: edited));
    final rt = r2.pages.first.findShapeById(id)!.richText;
    expect(rt.runs, isNotEmpty);
    expect(rt.runs.first.charStyle.fontSizeInches, closeTo(0.5, 1e-3));
    expect(rt.runs.first.charStyle.style.bold, isTrue);
    expect(rt.runs.first.charStyle.color?.value, 0xFF112233);
    expect(rt.runs.first.paraStyle.horizontalAlign, VsdxHorzAlign.center);
  });

  test('layer visibility round-trips when a page has layers', () {
    const candidates = <String>[
      'test1.vsdx',
      'test3_house.vsdx',
      'test5_master.vsdx',
      'test6_shape_properties.vsdx',
      'test10_nested_shapes.vsdx',
      'test12_colors.vsdx',
    ];
    for (final name in candidates) {
      final bytes = _fixture(name);
      final doc = parser.parse(bytes);
      for (var pi = 0; pi < doc.pages.length; pi++) {
        final page = doc.pages[pi];
        if (page.layers.isEmpty) continue;
        final layer = page.layers.first;
        final toggled = page.copyWith(layers: [
          for (final l in page.layers)
            if (l.id == layer.id) l.copyWith(visible: !l.visible) else l,
        ]);
        final reopened = parser.parse(
          writer.write(
            originalBytes: bytes,
            edited: doc.replacePage(pi, toggled),
          ),
        );
        final rl =
            reopened.pages[pi].layers.firstWhere((l) => l.id == layer.id);
        expect(rl.visible, !layer.visible);
        return; // one fixture with layers is enough
      }
    }
    // No fixture carried layers; nothing to verify (still a valid pass).
  });

  test('layer rename + snap patch round-trips on an existing page', () {
    const candidates = <String>[
      'test1.vsdx',
      'test3_house.vsdx',
      'test5_master.vsdx',
      'test6_shape_properties.vsdx',
      'test10_nested_shapes.vsdx',
      'test12_colors.vsdx',
    ];
    for (final name in candidates) {
      final bytes = _fixture(name);
      final doc = parser.parse(bytes);
      for (var pi = 0; pi < doc.pages.length; pi++) {
        final page = doc.pages[pi];
        if (page.layers.isEmpty) continue;
        final layer = page.layers.first;
        final edited = page.copyWith(layers: [
          for (final l in page.layers)
            if (l.id == layer.id)
              l.copyWith(name: 'Renamed_${l.id}', snap: !l.snap)
            else
              l,
        ]);
        final reopened = parser.parse(
          writer.write(
            originalBytes: bytes,
            edited: doc.replacePage(pi, edited),
          ),
        );
        final rl =
            reopened.pages[pi].layers.firstWhere((l) => l.id == layer.id);
        expect(rl.name, 'Renamed_${layer.id}');
        expect(rl.snap, !layer.snap);
        return; // one fixture with layers is enough
      }
    }
  });

  test('a glued connector round-trips its <Connects>', () {
    final blank = writer.emptyDocument();
    final doc = parser.parse(blank);
    var page = doc.pages.first;
    final r1 = VsdxShapeFactory.rectangle(
        id: page.nextFreeShapeId(), pinX: 2, pinY: 2, width: 1, height: 1);
    page = page.addShape(r1);
    final r2 = VsdxShapeFactory.rectangle(
        id: page.nextFreeShapeId(), pinX: 5, pinY: 5, width: 1, height: 1);
    page = page.addShape(r2);
    final connId = page.nextFreeShapeId();
    page = page
        .addShape(VsdxShapeFactory.line(id: connId, ax: 2, ay: 2, bx: 5, by: 5))
        .copyWith(connects: [
      VsdxConnect(
          fromSheetId: connId,
          fromCell: 'BeginX',
          fromPart: 9,
          toSheetId: r1.id,
          toCell: 'PinX',
          toPart: 3),
      VsdxConnect(
          fromSheetId: connId,
          fromCell: 'EndX',
          fromPart: 12,
          toSheetId: r2.id,
          toCell: 'PinX',
          toPart: 3),
    ]);

    final reopened = parser.parse(
      writer.write(originalBytes: blank, edited: doc.replacePage(0, page)),
    );
    expect(reopened.pages.first.connects, hasLength(2));
    expect(reopened.pages.first.findShapeById(connId), isNotNull);
  });

  test('a curved connector bakes its spline into round-tripping geometry', () {
    final blank = writer.emptyDocument();
    final doc = parser.parse(blank);
    var page = doc.pages.first;
    final aId = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.rectangle(
        id: aId, pinX: 2, pinY: 2, width: 1, height: 1));
    final bId = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.rectangle(
        id: bId, pinX: 6, pinY: 5, width: 1, height: 1));
    final connId = page.nextFreeShapeId();
    page = page
        .addShape(VsdxShapeFactory.line(id: connId, ax: 2, ay: 2, bx: 6, by: 5))
        .copyWith(connects: [
      VsdxConnect(
          fromSheetId: connId,
          fromCell: 'BeginX',
          toSheetId: aId,
          toCell: 'PinX'),
      VsdxConnect(
          fromSheetId: connId,
          fromCell: 'EndX',
          toSheetId: bId,
          toCell: 'PinX'),
    ]).rerouteConnectors();
    // Make the connector curved, then bake it in.
    page = page.setConnectorStyle({connId}, straight: false, curved: true);
    final before = page.findShapeById(connId)!.geometries.first.commands.length;
    expect(before, greaterThan(4)); // dense sampled spline

    final reopened = parser.parse(
      writer.write(originalBytes: blank, edited: doc.replacePage(0, page)),
    );
    final rc = reopened.pages.first.findShapeById(connId)!;
    // The dense smooth polyline survives verbatim as MoveTo/LineTo geometry.
    expect(rc.geometries.first.commands.length, before);
    expect(
      rc.geometries.first.commands.every((c) => c is MoveTo || c is LineTo),
      isTrue,
    );
  });

  test('a rounded connector bakes its fillets into round-tripping geometry',
      () {
    final blank = writer.emptyDocument();
    final doc = parser.parse(blank);
    var page = doc.pages.first;
    final aId = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.rectangle(
        id: aId, pinX: 2, pinY: 2, width: 1, height: 1));
    final bId = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.rectangle(
        id: bId, pinX: 6, pinY: 5, width: 1, height: 1));
    final connId = page.nextFreeShapeId();
    page = page
        .addShape(VsdxShapeFactory.line(id: connId, ax: 2, ay: 2, bx: 6, by: 5))
        .copyWith(connects: [
      VsdxConnect(
          fromSheetId: connId,
          fromCell: 'BeginX',
          toSheetId: aId,
          toCell: 'PinX'),
      VsdxConnect(
          fromSheetId: connId,
          fromCell: 'EndX',
          toSheetId: bId,
          toCell: 'PinX'),
    ]).rerouteConnectors();
    final elbow = page.findShapeById(connId)!.geometries.first.commands.length;
    // Round the elbow corners, then bake it in.
    page = page.setConnectorRounded({connId}, true);
    final before = page.findShapeById(connId)!.geometries.first.commands.length;
    expect(before, greaterThan(elbow)); // filleted polyline is denser

    final reopened = parser.parse(
      writer.write(originalBytes: blank, edited: doc.replacePage(0, page)),
    );
    final rc = reopened.pages.first.findShapeById(connId)!;
    // The filleted polyline survives verbatim as MoveTo/LineTo geometry.
    expect(rc.geometries.first.commands.length, before);
    expect(
      rc.geometries.first.commands.every((c) => c is MoveTo || c is LineTo),
      isTrue,
    );
  });

  test('changes fill colour across a round-trip', () {
    final bytes = _fixture('test9_rect_and_line.vsdx');
    final doc = parser.parse(bytes);
    final page = doc.pages.first;
    final target = page.shapes.first;
    final edited = doc.replacePage(
      0,
      page.updateShapeById(
        target.id,
        (s) => s.copyWith(
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000)),
        ),
      ),
    );

    final reopened = parser.parse(
      writer.write(originalBytes: bytes, edited: edited),
    );
    final after = reopened.pages.first.findShapeById(target.id)!;
    expect(after.fill.foreground?.value, 0xFFFF0000);
  });

  test('line style (dash / arrows / opacity) round-trips', () {
    final bytes = _fixture('test9_rect_and_line.vsdx');
    final doc = parser.parse(bytes);
    final page = doc.pages.first;
    final target = page.shapes.first;
    final edited = doc.replacePage(
      0,
      page.updateShapeById(
        target.id,
        (s) => s.copyWith(
          line: s.line.copyWith(
            pattern: 3,
            beginArrow: 1,
            endArrow: 5,
            beginArrowSizeInches: 0.225, // bucket 4
            endArrowSizeInches: 0.375, // bucket 6
            cap: LineCap.square,
            transparency: 0.4,
          ),
          fill: s.fill.copyWith(
            foregroundTransparency: 0.25,
            background: const VsdxColor(0xFF00AA00),
            backgroundTransparency: 0.1,
          ),
        ),
      ),
    );

    final output = writer.write(originalBytes: bytes, edited: edited);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(output)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final targetXml = XmlDocument.parse(pageXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere((e) =>
            e.name.local == 'Shape' &&
            e.getAttribute('ID') == target.id.toString());
    final lineCapCell =
        targetXml.descendants.whereType<XmlElement>().firstWhere(
              (e) => e.name.local == 'Cell' && e.getAttribute('N') == 'LineCap',
            );
    expect(
      lineCapCell.getAttribute('V'),
      '2',
      reason: 'libvisio renders raw LineCap=2 as a square SVG cap',
    );
    final reopened = parser.parse(output);
    final after = reopened.pages.first.findShapeById(target.id)!;
    expect(after.line.pattern, 3);
    expect(after.line.beginArrow, 1);
    expect(after.line.endArrow, 5);
    expect(after.line.beginArrowSizeInches, closeTo(0.225, 1e-4));
    expect(after.line.endArrowSizeInches, closeTo(0.375, 1e-4));
    expect(after.line.cap, LineCap.square);
    expect(after.line.transparency, closeTo(0, 1e-4));
    expect(
      after.line.color?.value,
      colourForLibvisioAlpha(
        target.line.color ?? VsdxColor.black,
        0.4,
      ).value,
    );
    expect(after.fill.foregroundTransparency, closeTo(0.25, 1e-4));
    expect(after.fill.background?.value, 0xFF00AA00);
    expect(after.fill.backgroundTransparency, closeTo(0.1, 1e-4));
  });

  test('LayerMember + User cells round-trip on new shape', () {
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
          layerMemberIds: const <int>[0, 2],
          userCells: const <VsdxUserCell>[
            VsdxUserCell(name: 'visVersion', value: '1', prompt: 'ver'),
          ],
        ).withTooltip('Review owner\nbefore approval'),
      ),
    );
    final after = parser
        .parse(writer.write(originalBytes: blank, edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(after.layerMemberIds, <int>[0, 2]);
    expect(after.userCells, hasLength(2));
    final version =
        after.userCells.firstWhere((cell) => cell.name == 'visVersion');
    expect(version.value, '1');
    expect(version.prompt, 'ver');
    expect(after.tooltip, 'Review owner\nbefore approval');
  });

  test('Character Pos/Letterspace + Paragraph indents round-trip', () {
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
          width: 2,
          height: 1,
        ).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'Hi',
                charStyle: VsdxCharStyle(
                  letterSpacingInches: 0.02,
                  position: VsdxTextPosition.superscript,
                  transparency: 0.3,
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                  indentFirstInches: 0.15,
                  indentLeftInches: 0.1,
                  spaceBeforeInches: 0.05,
                  lineSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final run = parser
        .parse(writer.write(originalBytes: blank, edited: doc))
        .pages
        .first
        .findShapeById(id)!
        .richText
        .runs
        .first;
    expect(run.charStyle.letterSpacingInches, closeTo(0, 1e-6));
    expect(
      run.charStyle.fontScale,
      closeTo(
        fontScaleForLibvisioWrite(
          const VsdxCharStyle(
            letterSpacingInches: 0.02,
            position: VsdxTextPosition.superscript,
            transparency: 0.3,
          ),
          'Hi',
        ),
        1e-9,
      ),
    );
    expect(run.charStyle.position, VsdxTextPosition.superscript);
    expect(run.charStyle.transparency, closeTo(0, 1e-6));
    expect(
      run.charStyle.color?.value,
      colourForLibvisioAlpha(VsdxColor.black, 0.3).value,
    );
    expect(run.paraStyle.horizontalAlign, VsdxHorzAlign.center);
    expect(run.paraStyle.indentFirstInches, closeTo(0.15, 1e-6));
    expect(run.paraStyle.indentLeftInches, closeTo(0.1, 1e-6));
    expect(run.paraStyle.spaceBeforeInches, closeTo(0.05, 1e-6));
    expect(run.paraStyle.lineSpacing, closeTo(1.5, 1e-6));
  });

  test('shape data (custom properties) round-trips: create, edit, add, remove',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final rect = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 3,
      pinY: 3,
      width: 2,
      height: 1,
    ).copyWith(userProperties: const <VsdxUserProperty>[
      VsdxUserProperty(name: 'Cost', label: 'Unit cost', value: '42', type: 2),
      VsdxUserProperty(name: 'Owner', value: 'Alice'),
    ]);
    doc = doc.replacePage(0, doc.pages.first.addShape(rect));

    // 1) New shape emits its Property section.
    final bytes1 = writer.write(originalBytes: blank, edited: doc);
    final s1 = parser.parse(bytes1).pages.first.findShapeById(id)!;
    expect(s1.userProperties, hasLength(2));
    final cost1 = s1.userProperties.firstWhere((p) => p.name == 'Cost');
    expect(cost1.value, '42');
    expect(cost1.label, 'Unit cost');
    expect(cost1.type, 2);

    // 2) Edit an existing value, add a new property, drop another — patched
    //    in place on the now-existing shape.
    final r1 = parser.parse(bytes1);
    final edited = r1.replacePage(
      0,
      r1.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(userProperties: <VsdxUserProperty>[
          s.userProperties
              .firstWhere((p) => p.name == 'Cost')
              .copyWith(value: '99'),
          const VsdxUserProperty(name: 'Status', value: 'Active'),
        ]),
      ),
    );
    final s2 = parser
        .parse(writer.write(originalBytes: bytes1, edited: edited))
        .pages
        .first
        .findShapeById(id)!;
    final names = s2.userProperties.map((p) => p.name).toSet();
    expect(names, <String>{'Cost', 'Status'}); // Owner removed
    expect(s2.userProperties.firstWhere((p) => p.name == 'Cost').value, '99');
    expect(s2.userProperties.firstWhere((p) => p.name == 'Status').value,
        'Active');
    // The edited "Cost" row kept its label from the original.
    expect(s2.userProperties.firstWhere((p) => p.name == 'Cost').label,
        'Unit cost');
  });

  test('page size and background colour round-trip', () {
    final bytes = _fixture('test1.vsdx');
    final doc = parser.parse(bytes);
    final edited = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        widthInches: 17,
        heightInches: 11,
        backgroundColor: const VsdxColor(0xFFF2F2F2),
      ),
    );

    final reopened = parser.parse(
      writer.write(originalBytes: bytes, edited: edited),
    );
    final p = reopened.pages.first;
    expect(p.widthInches, closeTo(17, 1e-3));
    expect(p.heightInches, closeTo(11, 1e-3));
    expect(p.backgroundColor?.value, 0xFFF2F2F2);
  });

  test('clearing PageColor via withoutBackgroundColor round-trips', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(backgroundColor: const VsdxColor(0xFFF2F2F2)),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    expect(parser.parse(mid).pages.first.backgroundColor?.value, 0xFFF2F2F2);
    expect(
      parser.parse(mid).pages.first.shapes.first.name,
      kLibvisioPageColorShapeName,
      reason: 'PageColor is not a token; Draw paints a full-page plate',
    );

    // copyWith(backgroundColor: null) must NOT clear — use the explicit API.
    final stuck = parser.parse(mid).pages.first;
    expect(
      stuck.copyWith(backgroundColor: null).backgroundColor?.value,
      0xFFF2F2F2,
    );

    doc = parser.parse(mid);
    doc = doc.replacePage(0, doc.pages.first.withoutBackgroundColor());
    final out = writer.write(originalBytes: mid, edited: doc);
    expect(parser.parse(out).pages.first.backgroundColor, isNull,
        reason: 'writer must drop PageColor cell on clear');
    expect(
      parser.parse(out).pages.first.shapes.where(
            (s) => s.name == kLibvisioPageColorShapeName,
          ),
      isEmpty,
      reason: 'clearing PageColor must drop the Draw plate',
    );
  });

  test('Glass bakes a sibling highlight and clears on disable', () {
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
          width: 1.5,
          height: 0.8,
          fill: const VsdxFill(foreground: VsdxColor(0xFF1565C0), pattern: 1),
        ).withGlassEffect(true),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final midDoc = parser.parse(mid);
    expect(
      midDoc.pages.first.shapes.where(isLibvisioGlassPlate),
      hasLength(1),
    );
    expect(midDoc.pages.first.findShapeById(id)!.glassEffect, isFalse);

    doc = midDoc.replacePage(
      0,
      midDoc.pages.first.copyWith(
        shapes: [
          for (final s in midDoc.pages.first.shapes)
            if (!isLibvisioGlassPlate(s)) s,
        ],
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    expect(
      parser.parse(out).pages.first.shapes.where(isLibvisioGlassPlate),
      isEmpty,
      reason: 'deleting the baked plate must drop it on save',
    );
  });

  test('Label Border bakes a sibling stroke and clears on disable', () {
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
          width: 1.5,
          height: 0.8,
          fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
          line: const VsdxLine(pattern: 0),
        )
            .copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[VsdxTextRun(text: 'Hi')],
              ),
            )
            .withLabelBorderColor(const VsdxColor(0xFF1565C0)),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final midDoc = parser.parse(mid);
    expect(
      midDoc.pages.first.shapes.where(isLibvisioLabelBorderPlate),
      hasLength(1),
    );
    expect(midDoc.pages.first.findShapeById(id)!.labelBorderColor, isNull);

    doc = midDoc.replacePage(
      0,
      midDoc.pages.first.copyWith(
        shapes: [
          for (final s in midDoc.pages.first.shapes)
            if (!isLibvisioLabelBorderPlate(s)) s,
        ],
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    expect(
      parser.parse(out).pages.first.shapes.where(isLibvisioLabelBorderPlate),
      isEmpty,
      reason: 'deleting the baked plate must drop it on save',
    );
  });

  test('filled LineColorTrans bakes a sibling ribbon and clears on disable',
      () {
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
          width: 1.5,
          height: 0.8,
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
          line: const VsdxLine(
            color: VsdxColor.black,
            weightInches: 0.08,
            transparency: 0.5,
          ),
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final midDoc = parser.parse(mid);
    expect(
      midDoc.pages.first.shapes.where(isLibvisioStrokeRibbonPlate),
      hasLength(1),
    );
    expect(midDoc.pages.first.findShapeById(id)!.line.pattern, 0);

    doc = midDoc.replacePage(
      0,
      midDoc.pages.first.copyWith(
        shapes: [
          for (final s in midDoc.pages.first.shapes)
            if (!isLibvisioStrokeRibbonPlate(s)) s,
        ],
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    expect(
      parser.parse(out).pages.first.shapes.where(isLibvisioStrokeRibbonPlate),
      isEmpty,
      reason: 'deleting the baked plate must drop it on save',
    );
  });

  test('Label Padding bakes into Margin cells and clears the User row', () {
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
          width: 1.5,
          height: 0.8,
          fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
          line: const VsdxLine(pattern: 0),
        )
            .copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[VsdxTextRun(text: 'Hi')],
                textBlock: VsdxTextBlock(
                  marginLeftInches: 0.04,
                  marginRightInches: 0.04,
                  marginTopInches: 0.04,
                  marginBottomInches: 0.04,
                ),
              ),
            )
            .withLabelPadding(
              const VsdxLabelPadding(top: 4, right: 8, bottom: 12, left: 16),
            ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final midDoc = parser.parse(mid);
    final after = midDoc.pages.first.findShapeById(id)!;
    expect(after.labelPadding.isZero, isTrue);
    expect(
      after.richText.textBlock.marginLeftInches,
      closeTo(0.04 + 16 / kLibvisioLabelPaddingPxPerInch, 1e-9),
    );
    expect(
      after.richText.textBlock.marginRightInches,
      closeTo(0.04 + 8 / kLibvisioLabelPaddingPxPerInch, 1e-9),
    );
    expect(
      after.richText.textBlock.marginTopInches,
      closeTo(0.04 + 4 / kLibvisioLabelPaddingPxPerInch, 1e-9),
    );
    expect(
      after.richText.textBlock.marginBottomInches,
      closeTo(0.04 + 12 / kLibvisioLabelPaddingPxPerInch, 1e-9),
    );

    final again = writer.write(originalBytes: mid, edited: midDoc);
    final twice = parser.parse(again).pages.first.findShapeById(id)!;
    expect(
      twice.richText.textBlock.marginLeftInches,
      closeTo(after.richText.textBlock.marginLeftInches, 1e-12),
      reason: 'a second save must not stack another inset',
    );
  });

  test('Word Wrap off bakes TxtWidth and clears the User row', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    const label = 'NO WRAP NO WRAP NO WRAP';
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 0.8,
          height: 0.6,
          fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          formulas: const <String, String>{
            'TxtWidth': 'Width*1',
            'TxtLocPinX': 'TxtWidth*0.5',
          },
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[VsdxTextRun(text: label)],
          ),
        ).withWordWrap(false),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final midDoc = parser.parse(mid);
    final after = midDoc.pages.first.findShapeById(id)!;
    expect(after.wordWrap, isTrue);
    expect(
      after.richText.textBlock.widthInches,
      greaterThan(0.8),
    );
    expect(after.formulas['TxtWidth'], isNull,
        reason: 'Width*1 would snap Draw back to the shape width');
    expect(after.formulas['TxtLocPinX'], isNull);

    final again = writer.write(originalBytes: mid, edited: midDoc);
    final twice = parser.parse(again).pages.first.findShapeById(id)!;
    expect(
      twice.richText.textBlock.widthInches,
      closeTo(after.richText.textBlock.widthInches!, 1e-12),
      reason: 'a second save must not stack another TxtWidth',
    );
  });

  test('geometry SoftEdges bakes a PNG sibling and clears the source fill', () {
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
          width: 1.2,
          height: 0.8,
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
          line: const VsdxLine(pattern: 0, softEdgesInches: 0.08),
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final midDoc = parser.parse(mid);
    expect(midDoc.pages.first.findShapeById(id)!.fill.pattern, 0);
    expect(midDoc.pages.first.findShapeById(id)!.line.softEdgesInches, 0);
    expect(
      midDoc.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
    );

    final again = writer.write(originalBytes: mid, edited: midDoc);
    expect(
      parser.parse(again).pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
      reason: 'a second save must not stack another SoftEdges plate',
    );
  });

  test('unfilled stroke SoftEdges bakes a PNG ring and clears the source line',
      () {
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
          width: 1.2,
          height: 0.8,
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.1,
            softEdgesInches: 0.08,
          ),
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final midDoc = parser.parse(mid);
    expect(midDoc.pages.first.findShapeById(id)!.line.pattern, 0);
    expect(midDoc.pages.first.findShapeById(id)!.line.softEdgesInches, 0);
    expect(
      midDoc.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
    );
    expect(
      midDoc.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single.width,
      greaterThan(1.2),
    );

    final again = writer.write(originalBytes: mid, edited: midDoc);
    expect(
      parser.parse(again).pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
      reason: 'a second save must not stack another SoftEdges plate',
    );
  });

  test('filled+stroked SoftEdges bakes a PNG and clears fill and line', () {
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
          width: 1.2,
          height: 0.8,
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.08,
            softEdgesInches: 0.08,
          ),
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final midDoc = parser.parse(mid);
    expect(midDoc.pages.first.findShapeById(id)!.fill.pattern, 0);
    expect(midDoc.pages.first.findShapeById(id)!.line.pattern, 0);
    expect(midDoc.pages.first.findShapeById(id)!.line.softEdgesInches, 0);
    expect(
      midDoc.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
    );
    expect(
      midDoc.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single.width,
      greaterThan(1.2),
    );

    final again = writer.write(originalBytes: mid, edited: midDoc);
    expect(
      parser.parse(again).pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
      reason: 'a second save must not stack another SoftEdges plate',
    );
  });

  test('ShadowBlur bakes a PNG sibling and clears the source shadow', () {
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
          width: 1.2,
          height: 0.8,
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
        ).copyWith(
          shadow: const VsdxShadow(
            enabled: true,
            color: VsdxColor(0xFF000000),
            offsetXInches: 0.2,
            offsetYInches: -0.15,
            blurInches: 0.08,
            transparency: 0.4,
          ),
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final midDoc = parser.parse(mid);
    expect(midDoc.pages.first.findShapeById(id)!.shadow.enabled, isFalse);
    expect(midDoc.pages.first.findShapeById(id)!.shadow.blurInches, 0);
    expect(midDoc.pages.first.findShapeById(id)!.fill.pattern, 1);
    expect(
      midDoc.pages.first.shapes.where(isLibvisioShadowPlate),
      hasLength(1),
    );

    final again = writer.write(originalBytes: mid, edited: midDoc);
    expect(
      parser.parse(again).pages.first.shapes.where(isLibvisioShadowPlate),
      hasLength(1),
      reason: 'a second save must not stack another Shadow plate',
    );
  });

  test('Curved Text bakes per-glyph siblings and hides the source', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 4,
          pinY: 5,
          width: 1.0,
          height: 3.0,
        ).withCurvedText(true).copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'ARC',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.4,
                      color: VsdxColor(0xFF000000),
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final midDoc = parser.parse(mid);
    final source = midDoc.pages.first.findShapeById(id)!;
    expect(source.curvedText, isFalse);
    expect(source.richText.textBlock.hideText, isTrue);
    expect(source.richText.plainText, 'ARC');
    final plates =
        midDoc.pages.first.shapes.where(isLibvisioCurvedTextPlate).toList()
          ..sort(
            (a, b) => int.parse(a.name.split('.')[1])
                .compareTo(int.parse(b.name.split('.')[1])),
          );
    expect(plates, hasLength(3));
    expect(
      plates.map((s) => s.richText.plainText).join(),
      'ARC',
    );
    expect(plates[1].pinY, greaterThan(plates[0].pinY + 0.08));
    expect(plates[1].pinY, greaterThan(plates[2].pinY + 0.08));
    expect(plates[0].pinX, lessThan(plates[1].pinX));
    expect(plates[1].pinX, lessThan(plates[2].pinX));

    final again = writer.write(originalBytes: mid, edited: midDoc);
    expect(
      parser.parse(again).pages.first.shapes.where(isLibvisioCurvedTextPlate),
      hasLength(3),
      reason: 'a second save must not stack another Curved Text plate',
    );
  });

  test('Shape Inside bakes per-line siblings and hides the source', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.ellipse(
          id: id,
          pinX: 4,
          pinY: 5,
          width: 3,
          height: 4,
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(pattern: 0),
        ).withShapeInside(true).copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'SHAPE INSIDE FLOW ALONG THE ELLIPSE',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.22,
                      color: VsdxColor(0xFF000000),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                    ),
                  ),
                ],
                textBlock: VsdxTextBlock(
                  verticalAlign: VsdxVertAlign.top,
                ),
              ),
            ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final midDoc = parser.parse(mid);
    final source = midDoc.pages.first.findShapeById(id)!;
    expect(source.shapeInside, isFalse);
    expect(source.richText.textBlock.hideText, isTrue);
    final plates =
        midDoc.pages.first.shapes.where(isLibvisioShapeInsidePlate).toList()
          ..sort(
            (a, b) => int.parse(a.name.split('.')[1])
                .compareTo(int.parse(b.name.split('.')[1])),
          );
    expect(plates.length, greaterThanOrEqualTo(2));
    expect(plates.first.width, lessThan(plates.last.width - 0.2));

    final again = writer.write(originalBytes: mid, edited: midDoc);
    expect(
      parser.parse(again).pages.first.shapes.where(isLibvisioShapeInsidePlate),
      hasLength(plates.length),
      reason: 'a second save must not stack another Shape Inside plate',
    );
  });

  test('Rotate with Edge bakes TxtAngle and clears the User row', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(
          id: id,
          ax: 2,
          ay: 3,
          bx: 6.5,
          by: 7.5,
        ).withAutoRotateLabel(true).copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'ROTATE',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.35,
                      color: VsdxColor(0xFF000000),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final midDoc = parser.parse(mid);
    final source = midDoc.pages.first.findShapeById(id)!;
    expect(source.autoRotateLabel, isFalse);
    expect(source.richText.textBlock.angleRad, closeTo(math.pi / 4, 1e-6));
    expect(source.richText.textBlock.widthInches, greaterThan(0.5));

    final again = writer.write(originalBytes: mid, edited: midDoc);
    expect(
      parser
          .parse(again)
          .pages
          .first
          .findShapeById(id)!
          .richText
          .textBlock
          .angleRad,
      closeTo(math.pi / 4, 1e-6),
    );
  });

  test('Shape Opacity bakes FillForegndTrans and clears the User row', () {
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
          width: 1.5,
          height: 0.8,
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).withShapeOpacity(0.4),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final midDoc = parser.parse(mid);
    final after = midDoc.pages.first.findShapeById(id)!;
    expect(after.shapeOpacity, 1);
    expect(after.fill.foregroundTransparency, closeTo(0.6, 1e-9));

    doc = midDoc.replacePage(
      0,
      midDoc.pages.first.updateShapeById(
        id,
        (shape) => shape.copyWith(
            fill: shape.fill.copyWith(
          foregroundTransparency: 0,
        )),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    expect(
      parser
          .parse(out)
          .pages
          .first
          .findShapeById(id)!
          .fill
          .foregroundTransparency,
      closeTo(0, 1e-9),
      reason: 'clearing the baked fade must write FillForegndTrans 0',
    );
  });

  test('Reflection bakes a sibling plate and clears on disable', () {
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
          width: 1.5,
          height: 0.8,
          fill: const VsdxFill(foreground: VsdxColor(0xFF336699), pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.4,
            distanceInches: 0.06,
            transparency: 0.5,
          ),
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final midDoc = parser.parse(mid);
    expect(
      midDoc.pages.first.shapes.where(isLibvisioReflectionPlate),
      hasLength(1),
    );
    expect(midDoc.pages.first.findShapeById(id)!.reflection.enabled, isFalse);

    doc = midDoc.replacePage(
      0,
      midDoc.pages.first.copyWith(
        shapes: [
          for (final s in midDoc.pages.first.shapes)
            if (!isLibvisioReflectionPlate(s)) s,
        ],
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    expect(
      parser.parse(out).pages.first.shapes.where(isLibvisioReflectionPlate),
      isEmpty,
      reason: 'deleting the baked plate must drop it on save',
    );
  });

  test('Background / BackPage attributes round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final fg = doc.pages.first;
    final bgId = doc.nextPageId();
    doc = doc.insertPage(
      1,
      VsdxPage(
        id: bgId,
        name: 'Background-1',
        widthInches: fg.widthInches,
        heightInches: fg.heightInches,
        shapes: const <VsdxShape>[],
        isBackgroundPage: true,
      ),
    );
    doc = doc.replacePage(
      0,
      fg.copyWith(backgroundPageId: bgId, isBackgroundPage: false),
    );

    final reopened = parser.parse(
      writer.write(originalBytes: blank, edited: doc),
    );
    expect(reopened.pages.length, 2);
    final page0 = reopened.pages.firstWhere((p) => p.id == fg.id);
    final page1 = reopened.pages.firstWhere((p) => p.id == bgId);
    expect(page1.isBackgroundPage, isTrue);
    expect(page1.backgroundPageId, isNull);
    expect(page0.isBackgroundPage, isFalse);
    expect(page0.backgroundPageId, bgId);

    // Clearing BackPage and the Background flag also round-trips.
    final cleared = reopened
        .replacePage(
          reopened.pages.indexWhere((p) => p.id == fg.id),
          page0.copyWith(backgroundPageId: null),
        )
        .replacePage(
          reopened.pages.indexWhere((p) => p.id == bgId),
          page1.copyWith(isBackgroundPage: false),
        );
    final again = parser.parse(
      writer.write(
        originalBytes: writer.write(originalBytes: blank, edited: doc),
        edited: cleared,
      ),
    );
    expect(
        again.pages.firstWhere((p) => p.id == fg.id).backgroundPageId, isNull);
    expect(
        again.pages.firstWhere((p) => p.id == bgId).isBackgroundPage, isFalse);
  });

  test('font / underline / vertical align + shadow round-trip', () {
    final bytes = _fixture('test9_rect_and_line.vsdx');
    final doc = parser.parse(bytes);
    final page = doc.pages.first;
    final target = page.shapes.first;
    final edited = doc.replacePage(
      0,
      page.updateShapeById(
        target.id,
        (s) => s.copyWith(
          shadow: const VsdxShadow(blurInches: 0),
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'Hi',
                charStyle:
                    VsdxCharStyle(fontFamily: 'Georgia', underline: true),
              ),
            ],
            textBlock: VsdxTextBlock(verticalAlign: VsdxVertAlign.bottom),
          ),
        ),
      ),
    );

    final reopened = parser.parse(
      writer.write(originalBytes: bytes, edited: edited),
    );
    final after = reopened.pages.first.findShapeById(target.id)!;
    expect(after.shadow.enabled, isTrue);
    expect(after.richText.textBlock.verticalAlign, VsdxVertAlign.bottom);
    expect(after.richText.runs.first.charStyle.fontFamily, 'Georgia');
    expect(after.richText.runs.first.charStyle.underline, isTrue);
  });

  test('shadow / glow theme QuickStyle slots round-trip', () {
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
          width: 2,
          height: 1,
        ).copyWith(
          shadow: const VsdxShadow(
            themeColorIndex: ThemeSlot.accent1,
            offsetXInches: 0.1,
            offsetYInches: 0.1,
          ),
          glow: const VsdxGlow(
            themeColorIndex: ThemeSlot.accent2,
            sizeInches: 0.06,
          ),
        ),
      ),
    );
    final saved = writer.write(originalBytes: blank, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="QuickStyleShadowColor"'), isTrue);
    expect(pageXml.contains('N="QuickStyleEffectColor"'), isTrue);
    expect(pageXml.contains('THEMEVAL()'), isTrue);
    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.shadow.enabled, isTrue);
    expect(after.shadow.themeColorIndex, ThemeSlot.accent1);
    expect(after.shadow.color, isNull);
    expect(after.glow.enabled, isFalse,
        reason: 'Glow on a filled stroke bakes a sibling halo');
    expect(after.glow.themeColorIndex, ThemeSlot.accent2);
    expect(after.glow.color, isNull);
    expect(
      parser.parse(saved).pages.first.shapes.where(isLibvisioGlowPlate),
      hasLength(1),
    );
    expect(
      parser
          .parse(saved)
          .pages
          .first
          .shapes
          .where(isLibvisioGlowPlate)
          .single
          .line
          .hasLine,
      isTrue,
      reason: 'theme-only Glow keeps a LineWeight halo so THEMEVAL() survives',
    );
  });

  test('HideText / TextBkgnd / Rounding / Glow round-trip', () {
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
          width: 2,
          height: 1,
        ).copyWith(
          line: const VsdxLine(roundingInches: 0.05),
          glow: const VsdxGlow(
            sizeInches: 0.08,
            color: VsdxColor(0xFFFF0000),
            transparency: 0.2,
          ),
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[VsdxTextRun(text: 'Hidden')],
            textBlock: VsdxTextBlock(
              hideText: true,
              backgroundColor: VsdxColor(0xFFFFFF00),
            ),
          ),
        ),
      ),
    );
    final savedDoc =
        parser.parse(writer.write(originalBytes: blank, edited: doc));
    final after = savedDoc.pages.first.findShapeById(id)!;
    expect(after.richText.textBlock.hideText, isTrue);
    expect(after.richText.textBlock.backgroundColor?.value, 0xFFFFFF00);
    expect(after.line.roundingInches, closeTo(0, 1e-6),
        reason:
            'Rounding is baked into Geometry; the cell must stay 0 for Visio');
    expect(
      after.geometries.expand((g) => g.commands).whereType<RelQuadBezTo>(),
      isNotEmpty,
    );
    expect(after.glow.enabled, isFalse,
        reason: 'Glow on a filled stroke bakes a sibling halo');
    expect(after.glow.sizeInches, 0);
    expect(after.glow.color?.value, 0xFFFF0000);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioGlowPlate),
      hasLength(1),
    );
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioGlowPlate).single.hasImage,
      isTrue,
      reason: 'resolved RGB Glow on a filled stroke bakes a Gaussian PNG',
    );
  });

  test('clearing TextBkgnd via withoutBackgroundColor round-trips', () {
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
          width: 2,
          height: 1,
        ).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[VsdxTextRun(text: 'Plate')],
            textBlock: VsdxTextBlock(
              backgroundColor: VsdxColor(0xFFFFFF00),
            ),
          ),
        ),
      ),
    );
    final withBg = writer.write(originalBytes: blank, edited: doc);
    expect(
      parser
          .parse(withBg)
          .pages
          .first
          .findShapeById(id)!
          .richText
          .textBlock
          .backgroundColor
          ?.value,
      0xFFFFFF00,
    );
    // copyWith(backgroundColor: null) must NOT clear — use the explicit API.
    final stuck = parser.parse(withBg).pages.first.findShapeById(id)!;
    expect(
      stuck.richText.textBlock.copyWith(backgroundColor: null).backgroundColor,
      isNotNull,
    );
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          richText: s.richText.copyWith(
            textBlock: s.richText.textBlock.withoutBackgroundColor(),
          ),
        ),
      ),
    );
    final cleared = parser
        .parse(writer.write(originalBytes: withBg, edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(cleared.richText.textBlock.backgroundColor, isNull,
        reason: 'writer must emit TextBkgnd=0 and parser treat it as clear');
  });

  test('style-only edit preserves existing <cp> markers in Text', () {
    final bytes = _fixture('workflow.vsdx');
    final doc = parser.parse(bytes);
    // Find a shape that already has multi-marker text in the package.
    final archive = ZipDecoder().decodeBytes(bytes);
    String? pageXml;
    for (final f in archive.files) {
      if (f.name.contains('pages/page') && f.name.endsWith('.xml')) {
        pageXml = utf8.decode(f.content as List<int>);
        break;
      }
    }
    expect(pageXml, isNotNull);
    expect(pageXml!, contains('<cp'));

    // No-op write (identity) must keep <cp>.
    final out = writer.write(originalBytes: bytes, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .files
          .firstWhere(
              (f) => f.name.contains('pages/page') && f.name.endsWith('.xml'))
          .content as List<int>,
    );
    expect(outXml.contains('<cp'), isTrue);
  });

  test('a hyperlink round-trips: create, edit, remove', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final rect = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 3,
      pinY: 3,
      width: 2,
      height: 1,
    ).copyWith(hyperlinks: const <VsdxHyperlink>[
      VsdxHyperlink(
        id: 0,
        address: 'https://example.com',
        description: 'Example',
        isDefault: true,
      ),
    ]);
    doc = doc.replacePage(0, doc.pages.first.addShape(rect));

    // 1) A new shape emits its Hyperlink section.
    final bytes1 = writer.write(originalBytes: blank, edited: doc);
    final s1 = parser.parse(bytes1).pages.first.findShapeById(id)!;
    expect(s1.hyperlinks, hasLength(1));
    expect(s1.primaryHyperlink?.address, 'https://example.com');
    expect(s1.primaryHyperlink?.description, 'Example');

    // 2) Edit the address in place on the now-existing shape.
    final r1 = parser.parse(bytes1);
    final edited = r1.replacePage(
      0,
      r1.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(hyperlinks: <VsdxHyperlink>[
          s.hyperlinks.first.copyWith(address: 'https://microsoft.com'),
        ]),
      ),
    );
    final bytes2 = writer.write(originalBytes: bytes1, edited: edited);
    final s2 = parser.parse(bytes2).pages.first.findShapeById(id)!;
    expect(s2.primaryHyperlink?.address, 'https://microsoft.com');

    // 3) Remove the link → the whole section is dropped.
    final r2 = parser.parse(bytes2);
    final cleared = r2.replacePage(
      0,
      r2.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(hyperlinks: const <VsdxHyperlink>[]),
      ),
    );
    final s3 = parser
        .parse(writer.write(originalBytes: bytes2, edited: cleared))
        .pages
        .first
        .findShapeById(id)!;
    expect(s3.hyperlinks, isEmpty);
  });

  test('lock/unlock round-trips (drawio Lock/Unlock)', () {
    final bytes = _fixture('test9_rect_and_line.vsdx');
    final doc = parser.parse(bytes);
    final page = doc.pages.first;
    final target = page.shapes.first;
    expect(target.locked, isFalse); // fixtures start unlocked

    // 1) Lock the shape → protection cells are written and read back, and
    //    the geometry is left untouched.
    final locked = doc.replacePage(
      0,
      page.updateShapeById(target.id, (s) => s.copyWith(locked: true)),
    );
    final bytes1 = writer.write(originalBytes: bytes, edited: locked);
    final s1 = parser.parse(bytes1).pages.first.findShapeById(target.id)!;
    expect(s1.locked, isTrue);
    expect(s1.pinX, closeTo(target.pinX, 1e-9));
    expect(s1.width, closeTo(target.width, 1e-9));

    // 2) Unlock it again → the flag clears on reopen.
    final r1 = parser.parse(bytes1);
    final unlocked = r1.replacePage(
      0,
      r1.pages.first
          .updateShapeById(target.id, (s) => s.copyWith(locked: false)),
    );
    final s2 = parser
        .parse(writer.write(originalBytes: bytes1, edited: unlocked))
        .pages
        .first
        .findShapeById(target.id)!;
    expect(s2.locked, isFalse);
  });

  test('a new locked shape emits protection cells', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final rect = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 3,
      pinY: 3,
      width: 2,
      height: 1,
    ).copyWith(locked: true);
    doc = doc.replacePage(0, doc.pages.first.addShape(rect));
    final s = parser
        .parse(writer.write(originalBytes: blank, edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(s.locked, isTrue);
  });

  test('inserts an image (media part + ForeignData) that round-trips', () {
    final bytes = _fixture('test9_rect_and_line.vsdx');
    final doc = parser.parse(bytes);
    final page = doc.pages.first;
    final id = page.nextFreeShapeId();
    const part = '/visio/media/image_inserted_test.png';
    final payload = Uint8List.fromList(
        <int>[0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    final pic = VsdxShapeFactory.picture(
      id: id,
      pinX: 3,
      pinY: 3,
      width: 2,
      height: 1.5,
      imagePartName: part,
    );
    final edited = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: payload, mimeType: 'image/png'),
          ),
        )
        .replacePage(0, page.addShape(pic));

    final out = writer.write(originalBytes: bytes, edited: edited);
    final reopened = parser.parse(out);
    final s = reopened.pages.first.findShapeById(id)!;
    expect(s.hasImage, isTrue);
    expect(s.imagePartName, isNotNull);
    expect(s.imagePartName, endsWith('media/image_inserted_test.png'));
    expect(s.width, closeTo(2, 1e-9));
    expect(s.height, closeTo(1.5, 1e-9));
    // The embedded media survived, byte-for-byte, and resolves from the shape.
    final img = reopened.images.findByPart(s.imagePartName!);
    expect(img, isNotNull);
    expect(img!.bytes, equals(payload));

    // A second (no-op) save keeps the image: its media part is now baseline.
    final out2 = writer.write(originalBytes: out, edited: reopened);
    final reopened2 = parser.parse(out2);
    final s2 = reopened2.pages.first.findShapeById(id)!;
    expect(s2.imagePartName, isNotNull);
    expect(
        reopened2.images.findByPart(s2.imagePartName!)!.bytes, equals(payload));
  });

  test('picture Foreign XML has ImgWidth/ImgHeight for Edraw/Visio', () {
    final blank = writer.emptyDocument();
    final doc = parser.parse(blank);
    final page = doc.pages.first;
    final id = page.nextFreeShapeId();
    const part = '/visio/media/image_edraw.png';
    // Minimal valid-looking PNG header bytes (content is irrelevant to XML).
    final payload = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      1,
      2,
      3,
      4,
    ]);
    final pic = VsdxShapeFactory.picture(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 1.25,
      height: 0.75,
      imagePartName: part,
    );
    expect(pic.geometries, isNotEmpty);
    final edited = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: payload, mimeType: 'image/png'),
          ),
        )
        .replacePage(0, page.addShape(pic));

    final out = writer.write(originalBytes: blank, edited: edited);
    final archive = ZipDecoder().decodeBytes(out);
    final pageXml = utf8.decode(
      archive.findFile('visio/pages/page1.xml')!.content as List<int>,
    );
    expect(pageXml, contains('Type="Foreign"'));
    expect(pageXml, contains('N="ImgOffsetX"'));
    expect(pageXml, contains('N="ImgOffsetY"'));
    expect(pageXml, contains('N="ImgWidth"'));
    expect(pageXml, contains('N="ImgHeight"'));
    expect(pageXml, contains('ForeignData'));
    expect(pageXml, contains('CompressionType="PNG"'));
    expect(pageXml, contains('Section N="Geometry"'));
    expect(archive.findFile('visio/media/image_edraw.png'), isNotNull);
    final rels = utf8.decode(
      archive.findFile('visio/pages/_rels/page1.xml.rels')!.content
          as List<int>,
    );
    expect(rels, contains('relationships/image'));
    expect(rels, contains('../media/image_edraw.png'));
  });

  test('custom ImgWidth crop formula is preserved on rewrite', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    final id = page.nextFreeShapeId();
    const part = '/visio/media/image_crop.png';
    final payload = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      9,
      8,
      7,
      6,
    ]);
    final pic = VsdxShapeFactory.picture(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 2,
      imagePartName: part,
    );
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: payload, mimeType: 'image/png'),
          ),
        )
        .replacePage(0, page.addShape(pic));
    final out1 = writer.write(originalBytes: blank, edited: doc);

    // Patch a non-default crop formula into the saved XML, then rewrite.
    final archive = ZipDecoder().decodeBytes(out1);
    var pageXml = utf8.decode(
      archive.findFile('visio/pages/page1.xml')!.content as List<int>,
    );
    expect(pageXml, contains('<Cell N="ImgWidth" V="2" F="Width*1"/>'));
    pageXml = pageXml.replaceFirst(
      '<Cell N="ImgWidth" V="2" F="Width*1"/>',
      '<Cell N="ImgWidth" V="1" F="Width*0.5"/>',
    );
    final rebuilt = Archive();
    for (final f in archive.files) {
      if (f.name == 'visio/pages/page1.xml') {
        final bytes = utf8.encode(pageXml);
        rebuilt.addFile(ArchiveFile(f.name, bytes.length, bytes));
      } else if (f.isFile) {
        rebuilt.addFile(
          ArchiveFile(f.name, f.size, f.content as List<int>),
        );
      }
    }
    final patchedBytes = Uint8List.fromList(ZipEncoder().encode(rebuilt)!);
    doc = parser.parse(patchedBytes);
    final touched = doc.pages.first.findShapeById(id)!;
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(id, (_) => touched),
    );
    final out2 = writer.write(originalBytes: patchedBytes, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder().decodeBytes(out2).findFile('visio/pages/page1.xml')!.content
          as List<int>,
    );
    expect(
      outXml,
      contains('<Cell N="ImgWidth" V="1" F="Width*0.5"/>'),
      reason: 'custom crop formula/V must survive rewrite',
    );
  });

  test('absolute ImgWidth without F= survives patch (not rewritten to Width*1)',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    const part = '/visio/media/image_abs_crop.png';
    final payload = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      1,
      2,
      3,
      4,
    ]);
    // Absolute crop: V≠Width and no F= (common Visio / hand-authored crop).
    final pic = VsdxShapeFactory.picture(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 2,
      imagePartName: part,
    ).copyWith(
      imgWidthInches: 1,
      imgHeightInches: 1.25,
    );
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: payload, mimeType: 'image/png'),
          ),
        )
        .replacePage(0, doc.pages.first.addShape(pic));
    final out1 = writer.write(originalBytes: blank, edited: doc);
    // Trigger patch path (move) without changing crop.
    doc = parser.parse(out1);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.25),
      ),
    );
    final out2 = writer.write(originalBytes: out1, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder().decodeBytes(out2).findFile('visio/pages/page1.xml')!.content
          as List<int>,
    );
    expect(outXml, isNot(contains('N="ImgWidth" V="2" F="Width*1"')),
        reason: 'must not invent full-frame Width*1 over absolute crop');
    expect(outXml, contains('N="ImgWidth" V="1"'));
    expect(outXml, contains('N="ImgHeight" V="1.25"'));
    final after = parser.parse(out2).pages.first.findShapeById(id)!;
    expect(after.imgWidthInches, closeTo(1, 1e-6));
    expect(after.imgHeightInches, closeTo(1.25, 1e-6));
    expect(after.formulas['ImgWidth'], isNull);
  });

  test('custom ImgOffset crop formula is preserved on rewrite', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    final id = page.nextFreeShapeId();
    const part = '/visio/media/image_offset_crop.png';
    final payload = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      9,
      8,
      7,
      6,
    ]);
    final pic = VsdxShapeFactory.picture(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 2,
      imagePartName: part,
    ).copyWith(
      formulas: const <String, String>{
        'ImgOffsetX': 'Width*0.1',
        'ImgOffsetY': 'Height*0.05',
      },
      imgOffsetXInches: 0.2,
      imgOffsetYInches: 0.1,
    );
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: payload, mimeType: 'image/png'),
          ),
        )
        .replacePage(0, page.addShape(pic));
    final out1 = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(out1);
    expect(
        doc.pages.first.findShapeById(id)!.formulas['ImgOffsetX'], 'Width*0.1');
    // Trigger a patch rewrite (move the picture) without changing formulas.
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.5),
      ),
    );
    final out2 = writer.write(originalBytes: out1, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder().decodeBytes(out2).findFile('visio/pages/page1.xml')!.content
          as List<int>,
    );
    expect(
      outXml,
      contains('N="ImgOffsetX"'),
      reason: 'ImgOffsetX cell must remain',
    );
    expect(outXml, contains('F="Width*0.1"'),
        reason: 'custom ImgOffsetX formula must survive patch');
    expect(outXml, contains('F="Height*0.05"'),
        reason: 'custom ImgOffsetY formula must survive patch');
    final after = parser.parse(out2).pages.first.findShapeById(id)!;
    expect(after.formulas['ImgOffsetX'], 'Width*0.1');
    expect(after.formulas['ImgOffsetY'], 'Height*0.05');
  });

  test('resizing a picture patches ImgWidth/ImgHeight cached V=', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    final id = page.nextFreeShapeId();
    const part = '/visio/media/image_resize.png';
    final payload = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      9,
      8,
      7,
      6,
    ]);
    final pic = VsdxShapeFactory.picture(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 1,
      height: 1,
      imagePartName: part,
    );
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: payload, mimeType: 'image/png'),
          ),
        )
        .replacePage(0, page.addShape(pic));
    final out1 = writer.write(originalBytes: blank, edited: doc);

    // Incremental patch path: reopen baseline then resize.
    doc = parser.parse(out1);
    page = doc.pages.first;
    final resized = page.findShapeById(id)!.copyWith(width: 2.5, height: 1.5);
    doc = doc.replacePage(0, page.updateShapeById(id, (_) => resized));
    final out2 = writer.write(originalBytes: out1, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder().decodeBytes(out2).findFile('visio/pages/page1.xml')!.content
          as List<int>,
    );
    String? cellV(String name) {
      final m = RegExp(
        'Cell[^>]*N="$name"[^>]*V="([^"]*)"|Cell[^>]*V="([^"]*)"[^>]*N="$name"',
      ).firstMatch(pageXml);
      return m?.group(1) ?? m?.group(2);
    }

    // Cached V= must track the new size (Edraw ignores F=Width*1 alone).
    expect(cellV('ImgWidth'), '2.5');
    expect(cellV('ImgHeight'), '1.5');
    expect(cellV('Width'), '2.5');
    expect(cellV('Height'), '1.5');
  });

  test('replaceImage embeds the new media part on save', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    final id = page.nextFreeShapeId();
    const part1 = '/visio/media/image_a.png';
    const part2 = '/visio/media/image_b.png';
    final bytesA =
        Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 1, 1, 1, 1]);
    final bytesB =
        Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 2, 2, 2, 2]);
    final pic = VsdxShapeFactory.picture(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 1,
      height: 1,
      imagePartName: part1,
    );
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part1, bytes: bytesA, mimeType: 'image/png'),
          ),
        )
        .replacePage(0, page.addShape(pic));
    final out1 = writer.write(originalBytes: blank, edited: doc);

    // Swap media on the same shape id (editor replaceImage).
    final replaced = pic.copyWith(imagePartName: part2);
    doc = parser.parse(out1);
    page = doc.pages.first;
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part2, bytes: bytesB, mimeType: 'image/png'),
          ),
        )
        .replacePage(0, page.updateShapeById(id, (_) => replaced));
    final out2 = writer.write(originalBytes: out1, edited: doc);
    final archive = ZipDecoder().decodeBytes(out2);
    expect(archive.findFile('visio/media/image_b.png'), isNotNull);
    // Orphan media from the replaced picture must be pruned.
    expect(archive.findFile('visio/media/image_a.png'), isNull);
    // Page rels must not keep a dangling Relationship to the pruned part.
    final relsEntry = archive.findFile('visio/pages/_rels/page1.xml.rels');
    expect(relsEntry, isNotNull);
    final relsXml = utf8.decode(relsEntry!.content as List<int>);
    expect(relsXml, isNot(contains('image_a.png')));
    expect(relsXml, contains('image_b.png'));
    final reopened = parser.parse(out2);
    final s = reopened.pages.first.findShapeById(id)!;
    expect(s.imagePartName, endsWith('image_b.png'));
    expect(reopened.images.findByPart(s.imagePartName!)!.bytes, equals(bytesB));
  });

  test('deleting a picture prunes its media part on save', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    final id = page.nextFreeShapeId();
    const part = '/visio/media/image_gone.png';
    final bytes = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 3, 3, 3, 3]);
    final pic = VsdxShapeFactory.picture(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 1,
      height: 1,
      imagePartName: part,
    );
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: bytes, mimeType: 'image/png'),
          ),
        )
        .replacePage(0, page.addShape(pic));
    final out1 = writer.write(originalBytes: blank, edited: doc);
    expect(
      ZipDecoder().decodeBytes(out1).findFile('visio/media/image_gone.png'),
      isNotNull,
    );

    doc = parser.parse(out1);
    doc = doc.replacePage(0, doc.pages.first.removeShapeById(id));
    final out2 = writer.write(originalBytes: out1, edited: doc);
    expect(
      ZipDecoder().decodeBytes(out2).findFile('visio/media/image_gone.png'),
      isNull,
    );
  });

  test('media referenced by an additional master prototype is retained', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    const part = '/visio/media/image_additional_master.png';
    final bytes = Uint8List.fromList(
      <int>[0x89, 0x50, 0x4E, 0x47, 4, 4, 4, 4],
    );
    final picture = VsdxShapeFactory.picture(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 1,
      height: 1,
      imagePartName: part,
    );
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: bytes, mimeType: 'image/png'),
          ),
        )
        .replacePage(0, doc.pages.first.addShape(picture));
    final withMedia = writer.write(originalBytes: blank, edited: doc);

    doc = parser.parse(withMedia);
    final primary = VsdxShapeFactory.rectangle(
      id: 100,
      pinX: 1,
      pinY: 1,
      width: 1,
      height: 1,
    );
    final master = VsdxMaster(
      id: 10,
      name: 'Multiple top-level shapes',
      prototype: primary,
      additionalPrototypes: <VsdxShape>[
        doc.pages.first.findShapeById(id)!,
      ],
    );
    doc = doc
        .copyWith(masters: MasterRegistry(<int, VsdxMaster>{10: master}))
        .replacePage(0, doc.pages.first.removeShapeById(id));

    final saved = writer.write(originalBytes: withMedia, edited: doc);
    expect(
      ZipDecoder()
          .decodeBytes(saved)
          .findFile('visio/media/image_additional_master.png'),
      isNotNull,
    );
  });

  test('connector endpoint reconnect / detach round-trips', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    final a = VsdxShapeFactory.rectangle(
        id: page.nextFreeShapeId(), pinX: 2, pinY: 5, width: 1, height: 1);
    page = page.addShape(a);
    final b = VsdxShapeFactory.rectangle(
        id: page.nextFreeShapeId(), pinX: 6, pinY: 5, width: 1, height: 1);
    page = page.addShape(b);
    final cRect = VsdxShapeFactory.rectangle(
        id: page.nextFreeShapeId(), pinX: 6, pinY: 8, width: 1, height: 1);
    page = page.addShape(cRect);
    final connId = page.nextFreeShapeId();
    final conn = VsdxShapeFactory.line(id: connId, ax: 2, ay: 5, bx: 6, by: 5);
    page = page.addShape(conn).copyWith(connects: <VsdxConnect>[
      VsdxConnect(
          fromSheetId: connId,
          fromCell: 'BeginX',
          fromPart: 9,
          toSheetId: a.id,
          toCell: 'PinX',
          toPart: 3),
      VsdxConnect(
          fromSheetId: connId,
          fromCell: 'EndX',
          fromPart: 12,
          toSheetId: b.id,
          toCell: 'PinX',
          toPart: 3),
    ]).rerouteConnectors();
    doc = doc.replacePage(0, page);

    // 1) Reconnect the END from b to c.
    final reconnected = doc.replacePage(
      0,
      doc.pages.first.setConnectorEndpoint(connId,
          begin: false, targetShapeId: cRect.id, x: 6, y: 8),
    );
    final bytes1 = writer.write(originalBytes: blank, edited: reconnected);
    final r1 = parser.parse(bytes1);
    final ends1 = r1.pages.first.connects
        .where((e) => e.fromSheetId == connId && e.isEnd)
        .toList();
    expect(ends1.length, 1);
    expect(ends1.single.toSheetId, cRect.id);
    // The begin end stays glued to a.
    final begins1 = r1.pages.first.connects
        .where((e) => e.fromSheetId == connId && e.isBegin)
        .toList();
    expect(begins1.single.toSheetId, a.id);

    // 2) Detach the END → its connect row is gone; the begin stays glued.
    final detached = r1.replacePage(
      0,
      r1.pages.first.setConnectorEndpoint(connId,
          begin: false, targetShapeId: null, x: 7, y: 9),
    );
    final r2 =
        parser.parse(writer.write(originalBytes: bytes1, edited: detached));
    final conns2 =
        r2.pages.first.connects.where((e) => e.fromSheetId == connId).toList();
    expect(conns2.where((e) => e.isEnd), isEmpty);
    expect(conns2.where((e) => e.isBegin).length, 1);
    // The detached end floats at (approximately) the drop point.
    final c2 = r2.pages.first.findShapeById(connId)!;
    expect(c2.endX, closeTo(7, 1e-6));
    expect(c2.endY, closeTo(9, 1e-6));
  });

  test('inserts an image into a blank document (creates the page rels part)',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    const part = '/visio/media/image1.png';
    final payload = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 42, 7, 7]);
    final pic = VsdxShapeFactory.picture(
      id: id,
      pinX: 4,
      pinY: 5,
      width: 3,
      height: 2,
      imagePartName: part,
    );
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: payload, mimeType: 'image/png'),
          ),
        )
        .replacePage(0, doc.pages.first.addShape(pic));
    final reopened =
        parser.parse(writer.write(originalBytes: blank, edited: doc));
    final s = reopened.pages.first.findShapeById(id)!;
    expect(s.hasImage, isTrue);
    expect(s.imagePartName, isNotNull);
    final img = reopened.images.findByPart(s.imagePartName!);
    expect(img, isNotNull);
    expect(img!.bytes, equals(payload));
  });

  test('fixed connection point round-trips (materialise + patch)', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    final a = VsdxShapeFactory.rectangle(
        id: page.nextFreeShapeId(), pinX: 2, pinY: 5, width: 1, height: 1);
    page = page.addShape(a);
    final b = VsdxShapeFactory.rectangle(
        id: page.nextFreeShapeId(), pinX: 6, pinY: 5, width: 2, height: 2);
    page = page.addShape(b);
    // Materialise glue points in the model (writer no longer invents them).
    page = page
        .materializeConnectionPoints(a.id)
        .materializeConnectionPoints(b.id);
    final connId = page.nextFreeShapeId();
    final conn = VsdxShapeFactory.line(id: connId, ax: 2, ay: 5, bx: 6, by: 5);
    page = page.addShape(conn).copyWith(connects: <VsdxConnect>[
      VsdxConnect(
          fromSheetId: connId,
          fromCell: 'BeginX',
          fromPart: 9,
          toSheetId: a.id,
          toCell: 'PinX',
          toPart: 3),
    ]).rerouteConnectors();
    doc = doc.replacePage(0, page);

    final bytes1 = writer.write(originalBytes: blank, edited: doc);
    final r1 = parser.parse(bytes1);
    expect(r1.pages.first.findShapeById(b.id)!.connectionPoints.length, 5);

    // Glue the END to b's top connection point (index 0). Connection already
    // exists from the first write; the second write patches ToPart / endpoint.
    final edited = r1.replacePage(
      0,
      r1.pages.first.setConnectorEndpoint(
        connId,
        begin: false,
        targetShapeId: b.id,
        connectionPointIndex: 0,
        x: 6,
        y: 6,
      ),
    );
    final r2 =
        parser.parse(writer.write(originalBytes: bytes1, edited: edited));
    final rb = r2.pages.first.findShapeById(b.id)!;
    expect(rb.connectionPoints.length, 5); // standard set round-tripped
    final endConnect = r2.pages.first.connects
        .firstWhere((e) => e.fromSheetId == connId && e.isEnd);
    expect(endConnect.toSheetId, b.id);
    expect(endConnect.toPart, 100); // fixed point index 0
    // b: pin (6,5), 2×2 → top-centre local (1,2) → page (6,6).
    final conn2 = r2.pages.first.findShapeById(connId)!;
    expect(conn2.endX, closeTo(6, 1e-6));
    expect(conn2.endY, closeTo(6, 1e-6));
  });

  test('UML / cloud stencil shapes round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;

    final classId = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.umlClass(
        id: classId, pinX: 3, pinY: 3, width: 2, height: 1.6));
    final cloudId = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.cloud(
        id: cloudId, pinX: 6, pinY: 3, width: 2, height: 1.4));
    final noteId = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.note(
        id: noteId, pinX: 3, pinY: 6, width: 1.5, height: 1.5));
    doc = doc.replacePage(0, page);

    final reopened =
        parser.parse(writer.write(originalBytes: blank, edited: doc));

    // Class: rectangle + NoFill divider lines.
    final rc = reopened.pages.first.findShapeById(classId)!;
    expect(rc.geometries.length, 2);
    expect(rc.geometries[1].noFill, isTrue);

    // Cloud: a closed outline of elliptical arcs.
    final rcl = reopened.pages.first.findShapeById(cloudId)!;
    expect(
      rcl.geometries.first.commands.whereType<EllipticalArcTo>().length,
      greaterThanOrEqualTo(6),
    );

    // Note: cut-corner outline + NoFill fold lines.
    final rn = reopened.pages.first.findShapeById(noteId)!;
    expect(rn.geometries.length, 2);
    expect(rn.geometries[1].noFill, isTrue);
  });

  test('connector begin end glues to a fixed connection point', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    final a = VsdxShapeFactory.rectangle(
        id: page.nextFreeShapeId(), pinX: 2, pinY: 5, width: 2, height: 2);
    page = page.addShape(a);
    final connId = page.nextFreeShapeId();
    page = page.addShape(
        VsdxShapeFactory.line(id: connId, ax: 2, ay: 5, bx: 6, by: 5));
    // Glue the BEGIN end to a's right connection point (index 1).
    page = page.setConnectorEndpoint(
      connId,
      begin: true,
      targetShapeId: a.id,
      connectionPointIndex: 1,
      x: 2,
      y: 5,
    );
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    final ra = r.pages.first.findShapeById(a.id)!;
    expect(ra.connectionPoints.length, 5); // standard set materialised
    final beginConnect = r.pages.first.connects
        .firstWhere((e) => e.fromSheetId == connId && e.isBegin);
    expect(beginConnect.toSheetId, a.id);
    expect(beginConnect.toPart, 101); // fixed point index 1 → 100 + 1
    // a: pin (2,5), 2×2 → right-middle local (2,1) → page (3,5).
    final conn2 = r.pages.first.findShapeById(connId)!;
    expect(conn2.beginX, closeTo(3, 1e-6));
    expect(conn2.beginY, closeTo(5, 1e-6));
  });

  test('flowchart / heart stencil shapes round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;

    final orId = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.orGate(
        id: orId, pinX: 3, pinY: 3, width: 1, height: 1));
    final sortId = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.sort(
        id: sortId, pinX: 6, pinY: 3, width: 1.5, height: 1));
    final displayId = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.display(
        id: displayId, pinX: 3, pinY: 6, width: 1.5, height: 1));
    final heartId = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.heart(
        id: heartId, pinX: 6, pinY: 6, width: 1.2, height: 1.1));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));

    // Or: circle (ellipse) + NoFill cross lines.
    final rOr = r.pages.first.findShapeById(orId)!;
    expect(rOr.geometries.length, 2);
    expect(rOr.geometries[1].noFill, isTrue);
    expect(rOr.geometries.first.commands.whereType<EllipseCmd>(), isNotEmpty);

    // Sort: diamond + NoFill midline.
    final rSort = r.pages.first.findShapeById(sortId)!;
    expect(rSort.geometries.length, 2);
    expect(rSort.geometries[1].noFill, isTrue);

    // Display: a right semicircle (elliptical arc) survives.
    final rDisp = r.pages.first.findShapeById(displayId)!;
    expect(rDisp.geometries.first.commands.whereType<EllipticalArcTo>(),
        isNotEmpty);

    // Heart: four elliptical arcs.
    final rHeart = r.pages.first.findShapeById(heartId)!;
    expect(
      rHeart.geometries.first.commands.whereType<EllipticalArcTo>().length,
      greaterThanOrEqualTo(4),
    );
  });

  test('drawio-parity stencil shapes (tape / stored / bpmn / uml) round-trip',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;

    void add(VsdxShape s) => page = page.addShape(s);
    final tapeId = page.nextFreeShapeId();
    add(VsdxShapeFactory.tape(
        id: tapeId, pinX: 2, pinY: 8, width: 1.5, height: 1));
    final storedId = page.nextFreeShapeId();
    add(VsdxShapeFactory.storedData(
        id: storedId, pinX: 4, pinY: 8, width: 1.5, height: 1));
    final multiId = page.nextFreeShapeId();
    add(VsdxShapeFactory.multiDocument(
        id: multiId, pinX: 6, pinY: 8, width: 1.5, height: 1.2));
    final dblId = page.nextFreeShapeId();
    add(VsdxShapeFactory.doubleRectangle(
        id: dblId, pinX: 2, pinY: 5, width: 1.5, height: 1));
    final gwId = page.nextFreeShapeId();
    add(VsdxShapeFactory.bpmnGateway(
        id: gwId, pinX: 4, pinY: 5, width: 1.1, height: 1.1));
    final compId = page.nextFreeShapeId();
    add(VsdxShapeFactory.umlComponent(
        id: compId, pinX: 6, pinY: 5, width: 1.5, height: 1.1));
    final annId = page.nextFreeShapeId();
    add(VsdxShapeFactory.annotation(
        id: annId, pinX: 2, pinY: 2, width: 1.2, height: 1));
    final coneId = page.nextFreeShapeId();
    add(VsdxShapeFactory.cone(
        id: coneId, pinX: 4, pinY: 2, width: 1.2, height: 1.3));
    final weakId = page.nextFreeShapeId();
    add(VsdxShapeFactory.weakEntity(
        id: weakId, pinX: 6, pinY: 2, width: 1.5, height: 1));
    final poolId = page.nextFreeShapeId();
    add(VsdxShapeFactory.bpmnPool(
        id: poolId, pinX: 3, pinY: 0.5, width: 2.4, height: 1.4));
    final layerId = page.nextFreeShapeId();
    add(VsdxShapeFactory.layeredRectangle(
        id: layerId, pinX: 7, pinY: 0.5, width: 1.5, height: 1));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(
        r.pages.first
            .findShapeById(tapeId)!
            .geometries
            .first
            .commands
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(storedId)!
            .geometries
            .first
            .commands
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(multiId)!.geometries.length, 2);
    expect(r.pages.first.findShapeById(dblId)!.geometries.length, 2);
    expect(r.pages.first.findShapeById(dblId)!.geometries[1].noFill, isTrue);
    expect(r.pages.first.findShapeById(gwId)!.geometries.length, 2);
    expect(r.pages.first.findShapeById(compId)!.geometries.length, 2);
    expect(r.pages.first.findShapeById(annId)!.geometries.length, 2);
    expect(
        r.pages.first
            .findShapeById(coneId)!
            .geometries
            .first
            .commands
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(weakId)!.geometries.length, 2);
    expect(r.pages.first.findShapeById(poolId)!.geometries.length,
        greaterThanOrEqualTo(1));
    expect(r.pages.first.findShapeById(layerId)!.geometries.length,
        greaterThanOrEqualTo(2));
  });

  test(
      'drawio-parity misc shapes (parallelepiped / callout / list / image / '
      'partial rectangle) round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final pldId = page.nextFreeShapeId();
    add(VsdxShapeFactory.parallelepiped(
        id: pldId, pinX: 2, pinY: 8, width: 1.5, height: 1));
    final rrcId = page.nextFreeShapeId();
    add(VsdxShapeFactory.roundedRectangularCallout(
        id: rrcId, pinX: 4, pinY: 8, width: 1.5, height: 1.1));
    final listId = page.nextFreeShapeId();
    add(VsdxShapeFactory.list(
        id: listId, pinX: 6, pinY: 8, width: 1.6, height: 1.4, text: 'List'));
    final imgId = page.nextFreeShapeId();
    add(VsdxShapeFactory.imagePlaceholder(
        id: imgId, pinX: 2, pinY: 5, width: 1.4, height: 1.1));
    // Open-side variants: horizontal rails only, then vertical rails only.
    final prHId = page.nextFreeShapeId();
    add(VsdxShapeFactory.partialRectangle(
        id: prHId,
        pinX: 4,
        pinY: 5,
        width: 1.5,
        height: 1,
        top: true,
        bottom: true,
        left: false,
        right: false));
    final prVId = page.nextFreeShapeId();
    add(VsdxShapeFactory.partialRectangle(
        id: prVId,
        pinX: 6,
        pinY: 5,
        width: 1.5,
        height: 1,
        top: false,
        bottom: false));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    final pld = r.pages.first.findShapeById(pldId)!;
    expect(pld.geometries.length, 3);
    expect(
        r.pages.first
            .findShapeById(rrcId)!
            .geometries
            .first
            .commands
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    final list = r.pages.first.findShapeById(listId)!;
    expect(list.geometries.length, 4);
    expect(list.text, 'List');
    expect(
        r.pages.first
            .findShapeById(imgId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>(),
        isNotEmpty);
    // Horizontal-rails partial rectangle: two disjoint segments (2×MoveTo).
    final prH = r.pages.first.findShapeById(prHId)!;
    expect(prH.geometries.single.commands.whereType<MoveTo>().length, 2);
    expect(prH.geometries.single.noFill, isTrue);
    final prV = r.pages.first.findShapeById(prVId)!;
    expect(prV.geometries.single.commands.whereType<MoveTo>().length, 2);
  });

  test(
      'drawio-parity network shapes (server / firewall / mobile / monitor / '
      'laptop / printer / wireless / router) round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final srvId = page.nextFreeShapeId();
    add(VsdxShapeFactory.networkServer(
        id: srvId, pinX: 1, pinY: 8, width: 1, height: 1.4));
    final fwId = page.nextFreeShapeId();
    add(VsdxShapeFactory.networkFirewall(
        id: fwId, pinX: 3, pinY: 8, width: 1.4, height: 1.2));
    final mobId = page.nextFreeShapeId();
    add(VsdxShapeFactory.networkMobile(
        id: mobId, pinX: 5, pinY: 8, width: 0.9, height: 1.5));
    final monId = page.nextFreeShapeId();
    add(VsdxShapeFactory.networkMonitor(
        id: monId, pinX: 7, pinY: 8, width: 1.5, height: 1.3));
    final lapId = page.nextFreeShapeId();
    add(VsdxShapeFactory.networkLaptop(
        id: lapId, pinX: 1, pinY: 5, width: 1.6, height: 1.2));
    final prnId = page.nextFreeShapeId();
    add(VsdxShapeFactory.networkPrinter(
        id: prnId, pinX: 3, pinY: 5, width: 1.4, height: 1.3));
    final wifiId = page.nextFreeShapeId();
    add(VsdxShapeFactory.networkWireless(
        id: wifiId, pinX: 5, pinY: 5, width: 1.3, height: 1.3));
    final rtrId = page.nextFreeShapeId();
    add(VsdxShapeFactory.networkRouter(
        id: rtrId, pinX: 7, pinY: 5, width: 1.4, height: 1.2));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    // Server: body + slot rails + LED.
    expect(r.pages.first.findShapeById(srvId)!.geometries.length, 3);
    // Firewall: outer wall + mortar sub-paths (several MoveTo).
    expect(
        r.pages.first
            .findShapeById(fwId)!
            .geometries
            .last
            .commands
            .whereType<MoveTo>()
            .length,
        greaterThan(3));
    // Mobile: rounded body carries corner arcs + round home button.
    final mob = r.pages.first.findShapeById(mobId)!;
    expect(
        mob.geometries.first.commands.whereType<EllipticalArcTo>(), isNotEmpty);
    expect(mob.geometries.expand((g) => g.commands).whereType<EllipseCmd>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(monId)!.geometries.length, 4);
    expect(r.pages.first.findShapeById(lapId)!.geometries.length, 3);
    expect(r.pages.first.findShapeById(prnId)!.geometries.length, 4);
    // Wireless: emitter ellipse + 3 arcs.
    final wifi = r.pages.first.findShapeById(wifiId)!;
    expect(wifi.geometries.length, 4);
    expect(
        wifi.geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>()
            .length,
        3);
    expect(r.pages.first.findShapeById(rtrId)!.geometries.length, 3);
  });

  test(
      'drawio-parity network+/mockup/electrical/signs starter shapes round-trip',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final swId = page.nextFreeShapeId();
    add(VsdxShapeFactory.networkSwitch(
        id: swId, pinX: 1, pinY: 9, width: 1.6, height: 0.9));
    final hubId = page.nextFreeShapeId();
    add(VsdxShapeFactory.networkHub(
        id: hubId, pinX: 3, pinY: 9, width: 1.3, height: 1.3));
    final pcId = page.nextFreeShapeId();
    add(VsdxShapeFactory.networkPc(
        id: pcId, pinX: 5, pinY: 9, width: 1.6, height: 1.3));
    final cbId = page.nextFreeShapeId();
    add(VsdxShapeFactory.mockupCheckbox(
        id: cbId, pinX: 7, pinY: 9, width: 0.55, height: 0.55));
    final winId = page.nextFreeShapeId();
    add(VsdxShapeFactory.mockupWindow(
        id: winId, pinX: 1, pinY: 6, width: 2.0, height: 1.4));
    final togId = page.nextFreeShapeId();
    add(VsdxShapeFactory.mockupToggle(
        id: togId, pinX: 4, pinY: 6, width: 1.1, height: 0.5));
    final resId = page.nextFreeShapeId();
    add(VsdxShapeFactory.electricalResistor(
        id: resId, pinX: 6, pinY: 6, width: 1.6, height: 0.55));
    final capId = page.nextFreeShapeId();
    add(VsdxShapeFactory.electricalCapacitor(
        id: capId, pinX: 8, pinY: 6, width: 1.2, height: 0.8));
    final diodeId = page.nextFreeShapeId();
    add(VsdxShapeFactory.electricalDiode(
        id: diodeId, pinX: 1, pinY: 3, width: 1.3, height: 0.7));
    final gndId = page.nextFreeShapeId();
    add(VsdxShapeFactory.electricalGround(
        id: gndId, pinX: 3, pinY: 3, width: 0.9, height: 0.8));
    final warnId = page.nextFreeShapeId();
    add(VsdxShapeFactory.signWarning(
        id: warnId, pinX: 5, pinY: 3, width: 1.2, height: 1.1));
    final aidId = page.nextFreeShapeId();
    add(VsdxShapeFactory.signFirstAid(
        id: aidId, pinX: 7, pinY: 3, width: 1.1, height: 1.1));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(r.pages.first.findShapeById(swId)!.geometries.length, 3);
    expect(
        r.pages.first
            .findShapeById(hubId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(pcId)!.geometries.length, 6);
    expect(r.pages.first.findShapeById(cbId)!.geometries.length, 2);
    expect(r.pages.first.findShapeById(winId)!.text, 'Window');
    expect(
        r.pages.first
            .findShapeById(togId)!
            .geometries
            .first
            .commands
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first.findShapeById(resId)!.geometries.single.noFill, isTrue);
    expect(
        r.pages.first
            .findShapeById(capId)!
            .geometries
            .single
            .commands
            .whereType<MoveTo>()
            .length,
        greaterThanOrEqualTo(3));
    expect(r.pages.first.findShapeById(diodeId)!.geometries.length, 2);
    expect(
        r.pages.first.findShapeById(gndId)!.geometries.single.noFill, isTrue);
    expect(r.pages.first.findShapeById(warnId)!.geometries.length, 2);
    expect(r.pages.first.findShapeById(aidId)!.geometries.length, 2);
  });

  test(
      'drawio-parity batch64 expansions (tablet/search/fuse/biohazard) round-trip',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final tabId = page.nextFreeShapeId();
    add(VsdxShapeFactory.networkTablet(
        id: tabId, pinX: 1, pinY: 8, width: 1.6, height: 1.1));
    final lbId = page.nextFreeShapeId();
    add(VsdxShapeFactory.networkLoadBalancer(
        id: lbId, pinX: 3, pinY: 8, width: 1.4, height: 1.2));
    final searchId = page.nextFreeShapeId();
    add(VsdxShapeFactory.mockupSearchBox(
        id: searchId, pinX: 5, pinY: 8, width: 1.8, height: 0.5));
    final loadId = page.nextFreeShapeId();
    add(VsdxShapeFactory.mockupLoadingCircle(
        id: loadId, pinX: 7, pinY: 8, width: 0.8, height: 0.8));
    final fuseId = page.nextFreeShapeId();
    add(VsdxShapeFactory.electricalFuse(
        id: fuseId, pinX: 1, pinY: 5, width: 1.5, height: 0.55));
    final invId = page.nextFreeShapeId();
    add(VsdxShapeFactory.electricalInverter(
        id: invId, pinX: 3, pinY: 5, width: 1.3, height: 0.9));
    final smokeId = page.nextFreeShapeId();
    add(VsdxShapeFactory.signNoSmoking(
        id: smokeId, pinX: 5, pinY: 5, width: 1.1, height: 1.1));
    final bioId = page.nextFreeShapeId();
    add(VsdxShapeFactory.signBiohazard(
        id: bioId, pinX: 7, pinY: 5, width: 1.1, height: 1.1));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(
        r.pages.first
            .findShapeById(tabId)!
            .geometries
            .first
            .commands
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(lbId)!.geometries.length, 2);
    expect(
        r.pages.first
            .findShapeById(searchId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>(),
        isNotEmpty);
    expect(
        r.pages.first.findShapeById(loadId)!.geometries.single.noFill, isTrue);
    expect(
        r.pages.first.findShapeById(fuseId)!.geometries.single.noFill, isTrue);
    expect(r.pages.first.findShapeById(invId)!.geometries.length, 3);
    expect(r.pages.first.findShapeById(smokeId)!.geometries.length,
        greaterThan(1));
    expect(
        r.pages.first
            .findShapeById(bioId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(3));
  });

  test('drawio-parity batch65 (IEEE gates + floorplan) round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final andId = page.nextFreeShapeId();
    add(VsdxShapeFactory.electricalAndGate(
        id: andId, pinX: 1, pinY: 8, width: 1.4, height: 1.0));
    final xorId = page.nextFreeShapeId();
    add(VsdxShapeFactory.electricalXorGate(
        id: xorId, pinX: 3, pinY: 8, width: 1.4, height: 1.0));
    final bufId = page.nextFreeShapeId();
    add(VsdxShapeFactory.electricalBuffer(
        id: bufId, pinX: 5, pinY: 8, width: 1.3, height: 0.9));
    final doorId = page.nextFreeShapeId();
    add(VsdxShapeFactory.floorplanDoor(
        id: doorId, pinX: 1, pinY: 5, width: 1.4, height: 1.2));
    final stairsId = page.nextFreeShapeId();
    add(VsdxShapeFactory.floorplanStairs(
        id: stairsId, pinX: 3, pinY: 5, width: 1.0, height: 1.6));
    final elevId = page.nextFreeShapeId();
    add(VsdxShapeFactory.floorplanElevator(
        id: elevId, pinX: 5, pinY: 5, width: 1.1, height: 1.1));
    final plantId = page.nextFreeShapeId();
    add(VsdxShapeFactory.floorplanPlant(
        id: plantId, pinX: 7, pinY: 5, width: 0.9, height: 0.9));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(r.pages.first.findShapeById(andId)!.geometries.length, 2);
    expect(
        r.pages.first
            .findShapeById(xorId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first.findShapeById(bufId)!.geometries.length, greaterThan(1));
    expect(
        r.pages.first
            .findShapeById(doorId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(stairsId)!
            .geometries
            .single
            .commands
            .whereType<MoveTo>()
            .length,
        greaterThanOrEqualTo(6));
    expect(r.pages.first.findShapeById(elevId)!.geometries.length, 2);
    expect(
        r.pages.first
            .findShapeById(plantId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>(),
        isNotEmpty);
  });

  test('drawio-parity batch66 floorplan expansion round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final ddId = page.nextFreeShapeId();
    add(VsdxShapeFactory.floorplanDoubleDoor(
        id: ddId, pinX: 1, pinY: 8, width: 1.8, height: 1.2));
    final tubId = page.nextFreeShapeId();
    add(VsdxShapeFactory.floorplanBathtub(
        id: tubId, pinX: 3, pinY: 8, width: 1.8, height: 0.9));
    final islandId = page.nextFreeShapeId();
    add(VsdxShapeFactory.floorplanKitchenIsland(
        id: islandId, pinX: 5, pinY: 8, width: 1.8, height: 1.0));
    final parkId = page.nextFreeShapeId();
    add(VsdxShapeFactory.floorplanParkingSpace(
        id: parkId, pinX: 7, pinY: 8, width: 1.4, height: 2.2));
    final colId = page.nextFreeShapeId();
    add(VsdxShapeFactory.floorplanColumn(
        id: colId, pinX: 1, pinY: 4, width: 0.55, height: 0.55));
    final escId = page.nextFreeShapeId();
    add(VsdxShapeFactory.floorplanEscalator(
        id: escId, pinX: 3, pinY: 4, width: 1.2, height: 1.8));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(
        r.pages.first
            .findShapeById(ddId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>()
            .length,
        greaterThanOrEqualTo(2));
    expect(
        r.pages.first
            .findShapeById(tubId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(islandId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(3));
    expect(
        r.pages.first.findShapeById(parkId)!.geometries.single.noFill, isTrue);
    expect(
        r.pages.first
            .findShapeById(colId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(escId)!
            .geometries
            .single
            .commands
            .whereType<MoveTo>()
            .length,
        greaterThanOrEqualTo(5));
  });

  test('drawio-parity batch67 EIP starter (channel/router/filter) round-trip',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final chId = page.nextFreeShapeId();
    add(VsdxShapeFactory.eipMessageChannel(
        id: chId, pinX: 1, pinY: 8, width: 1.8, height: 0.45));
    final dlId = page.nextFreeShapeId();
    add(VsdxShapeFactory.eipDeadLetterChannel(
        id: dlId, pinX: 3, pinY: 8, width: 1.8, height: 0.45));
    final aggId = page.nextFreeShapeId();
    add(VsdxShapeFactory.eipAggregator(
        id: aggId, pinX: 5, pinY: 8, width: 1.7, height: 1.0));
    final routerId = page.nextFreeShapeId();
    add(VsdxShapeFactory.eipContentBasedRouter(
        id: routerId, pinX: 1, pinY: 5, width: 1.7, height: 1.0));
    final filterId = page.nextFreeShapeId();
    add(VsdxShapeFactory.eipMessageFilter(
        id: filterId, pinX: 3, pinY: 5, width: 1.7, height: 1.0));
    final adapterId = page.nextFreeShapeId();
    add(VsdxShapeFactory.eipChannelAdapter(
        id: adapterId, pinX: 5, pinY: 5, width: 0.7, height: 1.2));
    final tapId = page.nextFreeShapeId();
    add(VsdxShapeFactory.eipWireTap(
        id: tapId, pinX: 7, pinY: 5, width: 1.7, height: 1.0));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(
        r.pages.first
            .findShapeById(chId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(dlId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(aggId)!.geometries.length,
        greaterThanOrEqualTo(6));
    expect(
        r.pages.first
            .findShapeById(routerId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(4));
    expect(r.pages.first.findShapeById(filterId)!.geometries.length, 2);
    expect(r.pages.first.findShapeById(adapterId)!.geometries.length, 1);
    expect(
        r.pages.first
            .findShapeById(tapId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>(),
        isNotEmpty);
  });

  test('drawio-parity batch68 EIP expansion (claim/store/router) round-trip',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final claimId = page.nextFreeShapeId();
    add(VsdxShapeFactory.eipClaimCheck(
        id: claimId, pinX: 1, pinY: 8, width: 1.7, height: 1.0));
    final reseqId = page.nextFreeShapeId();
    add(VsdxShapeFactory.eipResequencer(
        id: reseqId, pinX: 3, pinY: 8, width: 1.7, height: 1.0));
    final storeId = page.nextFreeShapeId();
    add(VsdxShapeFactory.eipMessageStore(
        id: storeId, pinX: 5, pinY: 8, width: 1.7, height: 1.0));
    final dynId = page.nextFreeShapeId();
    add(VsdxShapeFactory.eipDynamicRouter(
        id: dynId, pinX: 1, pinY: 5, width: 1.7, height: 1.0));
    final busId = page.nextFreeShapeId();
    add(VsdxShapeFactory.eipControlBus(
        id: busId, pinX: 3, pinY: 5, width: 1.1, height: 0.7));
    final envId = page.nextFreeShapeId();
    add(VsdxShapeFactory.eipEnvelopeWrapper(
        id: envId, pinX: 5, pinY: 5, width: 1.7, height: 1.0));
    final slipId = page.nextFreeShapeId();
    add(VsdxShapeFactory.eipRoutingSlip(
        id: slipId, pinX: 7, pinY: 5, width: 1.7, height: 1.0));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(r.pages.first.findShapeById(claimId)!.geometries.length,
        greaterThanOrEqualTo(5));
    expect(r.pages.first.findShapeById(reseqId)!.geometries.length,
        greaterThanOrEqualTo(7));
    expect(
        r.pages.first
            .findShapeById(storeId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(dynId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(4));
    expect(
        r.pages.first
            .findShapeById(busId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(envId)!.geometries.length, 3);
    expect(r.pages.first.findShapeById(slipId)!.geometries.length, 6);
  });

  test('drawio-parity batch69 EIP finish + AWS starter round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final proxyId = page.nextFreeShapeId();
    add(VsdxShapeFactory.eipSmartProxy(
        id: proxyId, pinX: 1, pinY: 8, width: 0.9, height: 1.2));
    final txId = page.nextFreeShapeId();
    add(VsdxShapeFactory.eipTransactionalClient(
        id: txId, pinX: 3, pinY: 8, width: 1.7, height: 1.0));
    final dtId = page.nextFreeShapeId();
    add(VsdxShapeFactory.eipDatatypeChannel(
        id: dtId, pinX: 5, pinY: 8, width: 1.8, height: 0.45));
    final invId = page.nextFreeShapeId();
    add(VsdxShapeFactory.eipInvalidMessageChannel(
        id: invId, pinX: 7, pinY: 8, width: 1.8, height: 0.45));
    final ec2Id = page.nextFreeShapeId();
    add(VsdxShapeFactory.awsEc2(
        id: ec2Id, pinX: 1, pinY: 5, width: 1.2, height: 1.1));
    final s3Id = page.nextFreeShapeId();
    add(VsdxShapeFactory.awsS3(
        id: s3Id, pinX: 3, pinY: 5, width: 1.1, height: 1.2));
    final lambdaId = page.nextFreeShapeId();
    add(VsdxShapeFactory.awsLambda(
        id: lambdaId, pinX: 5, pinY: 5, width: 1.1, height: 1.1));
    final sqsId = page.nextFreeShapeId();
    add(VsdxShapeFactory.awsSqs(
        id: sqsId, pinX: 7, pinY: 5, width: 1.5, height: 0.9));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(
        r.pages.first
            .findShapeById(proxyId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(4));
    expect(
        r.pages.first
            .findShapeById(txId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(dtId)!.geometries.length,
        greaterThanOrEqualTo(3));
    expect(r.pages.first.findShapeById(invId)!.geometries.length,
        greaterThanOrEqualTo(3));
    expect(r.pages.first.findShapeById(ec2Id)!.geometries.length, 4);
    expect(
        r.pages.first
            .findShapeById(s3Id)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(lambdaId)!.geometries.length, 2);
    expect(r.pages.first.findShapeById(sqsId)!.geometries.length, 4);
  });

  test('drawio-parity batch70 AWS expansion (iam/eks/kinesis) round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final iamId = page.nextFreeShapeId();
    add(VsdxShapeFactory.awsIam(
        id: iamId, pinX: 1, pinY: 8, width: 1.0, height: 1.2));
    final elbId = page.nextFreeShapeId();
    add(VsdxShapeFactory.awsElb(
        id: elbId, pinX: 3, pinY: 8, width: 1.5, height: 1.2));
    final eksId = page.nextFreeShapeId();
    add(VsdxShapeFactory.awsEks(
        id: eksId, pinX: 5, pinY: 8, width: 1.2, height: 1.2));
    final stepId = page.nextFreeShapeId();
    add(VsdxShapeFactory.awsStepFunctions(
        id: stepId, pinX: 7, pinY: 8, width: 1.4, height: 1.3));
    final kinId = page.nextFreeShapeId();
    add(VsdxShapeFactory.awsKinesis(
        id: kinId, pinX: 1, pinY: 5, width: 1.4, height: 1.0));
    final ebId = page.nextFreeShapeId();
    add(VsdxShapeFactory.awsEventBridge(
        id: ebId, pinX: 3, pinY: 5, width: 1.3, height: 1.2));
    final auroraId = page.nextFreeShapeId();
    add(VsdxShapeFactory.awsAurora(
        id: auroraId, pinX: 5, pinY: 5, width: 1.3, height: 1.2));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(
        r.pages.first
            .findShapeById(iamId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(elbId)!.geometries.length, 5);
    expect(
        r.pages.first
            .findShapeById(eksId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(7));
    expect(
        r.pages.first
            .findShapeById(stepId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(kinId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(ebId)!.geometries.length,
        greaterThanOrEqualTo(7));
    expect(
        r.pages.first
            .findShapeById(auroraId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(3));
  });

  test('drawio-parity batch71 Azure starter (vm/cosmos/keyvault) round-trip',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final vmId = page.nextFreeShapeId();
    add(VsdxShapeFactory.azureVirtualMachine(
        id: vmId, pinX: 1, pinY: 8, width: 1.3, height: 1.2));
    final fnId = page.nextFreeShapeId();
    add(VsdxShapeFactory.azureFunctions(
        id: fnId, pinX: 3, pinY: 8, width: 1.1, height: 1.1));
    final cosmosId = page.nextFreeShapeId();
    add(VsdxShapeFactory.azureCosmosDb(
        id: cosmosId, pinX: 5, pinY: 8, width: 1.2, height: 1.2));
    final aksId = page.nextFreeShapeId();
    add(VsdxShapeFactory.azureAks(
        id: aksId, pinX: 7, pinY: 8, width: 1.2, height: 1.2));
    final kvId = page.nextFreeShapeId();
    add(VsdxShapeFactory.azureKeyVault(
        id: kvId, pinX: 1, pinY: 5, width: 1.1, height: 1.2));
    final busId = page.nextFreeShapeId();
    add(VsdxShapeFactory.azureServiceBus(
        id: busId, pinX: 3, pinY: 5, width: 1.4, height: 1.1));
    final monId = page.nextFreeShapeId();
    add(VsdxShapeFactory.azureMonitor(
        id: monId, pinX: 5, pinY: 5, width: 1.2, height: 1.1));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(r.pages.first.findShapeById(vmId)!.geometries.length, 4);
    expect(
        r.pages.first
            .findShapeById(fnId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(cosmosId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(5));
    expect(r.pages.first.findShapeById(aksId)!.geometries.length, 3);
    expect(
        r.pages.first
            .findShapeById(kvId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(busId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(3));
    expect(
        r.pages.first
            .findShapeById(monId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
  });

  test('drawio-parity batch72 GCP starter (compute/gke/pubsub) round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final ceId = page.nextFreeShapeId();
    add(VsdxShapeFactory.gcpComputeEngine(
        id: ceId, pinX: 1, pinY: 8, width: 1.3, height: 1.2));
    final fnId = page.nextFreeShapeId();
    add(VsdxShapeFactory.gcpCloudFunctions(
        id: fnId, pinX: 3, pinY: 8, width: 1.1, height: 1.1));
    final gkeId = page.nextFreeShapeId();
    add(VsdxShapeFactory.gcpGke(
        id: gkeId, pinX: 5, pinY: 8, width: 1.2, height: 1.2));
    final vpcId = page.nextFreeShapeId();
    add(VsdxShapeFactory.gcpVpcNetwork(
        id: vpcId, pinX: 7, pinY: 8, width: 1.5, height: 1.1));
    final pubId = page.nextFreeShapeId();
    add(VsdxShapeFactory.gcpPubSub(
        id: pubId, pinX: 1, pinY: 5, width: 1.2, height: 1.2));
    final spanId = page.nextFreeShapeId();
    add(VsdxShapeFactory.gcpCloudSpanner(
        id: spanId, pinX: 3, pinY: 5, width: 1.3, height: 1.2));
    final monId = page.nextFreeShapeId();
    add(VsdxShapeFactory.gcpCloudMonitoring(
        id: monId, pinX: 5, pinY: 5, width: 1.2, height: 1.1));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(r.pages.first.findShapeById(ceId)!.geometries.length, 4);
    expect(
        r.pages.first
            .findShapeById(fnId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(gkeId)!.geometries.length, 5);
    expect(
        r.pages.first
            .findShapeById(vpcId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(pubId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(5));
    expect(
        r.pages.first
            .findShapeById(spanId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(5));
    expect(
        r.pages.first
            .findShapeById(monId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
  });

  test(
      'drawio-parity batch83 Oracle expansion (api-gw/fastconnect/devops) round-trip',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final gwId = page.nextFreeShapeId();
    add(VsdxShapeFactory.oracleApiGateway(
        id: gwId, pinX: 1, pinY: 8, width: 1.2, height: 1.2));
    final scId = page.nextFreeShapeId();
    add(VsdxShapeFactory.oracleServiceConnector(
        id: scId, pinX: 3, pinY: 8, width: 1.4, height: 1.0));
    final evId = page.nextFreeShapeId();
    add(VsdxShapeFactory.oracleEvents(
        id: evId, pinX: 5, pinY: 8, width: 1.2, height: 1.2));
    final dsId = page.nextFreeShapeId();
    add(VsdxShapeFactory.oracleDataScience(
        id: dsId, pinX: 7, pinY: 8, width: 1.2, height: 1.2));
    final fcId = page.nextFreeShapeId();
    add(VsdxShapeFactory.oracleFastConnect(
        id: fcId, pinX: 1, pinY: 5, width: 1.4, height: 1.2));
    final nlbId = page.nextFreeShapeId();
    add(VsdxShapeFactory.oracleNetworkLoadBalancer(
        id: nlbId, pinX: 3, pinY: 5, width: 1.2, height: 1.2));
    final cgId = page.nextFreeShapeId();
    add(VsdxShapeFactory.oracleCloudGuard(
        id: cgId, pinX: 5, pinY: 5, width: 1.1, height: 1.2));
    final doId = page.nextFreeShapeId();
    add(VsdxShapeFactory.oracleDevOps(
        id: doId, pinX: 7, pinY: 5, width: 1.4, height: 1.1));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(
        r.pages.first
            .findShapeById(gwId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(4));
    expect(
        r.pages.first
            .findShapeById(scId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(2));
    expect(r.pages.first.findShapeById(evId)!.geometries.length, 2);
    expect(
        r.pages.first
            .findShapeById(dsId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(fcId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(nlbId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(5));
    expect(
        r.pages.first
            .findShapeById(cgId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(doId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(3));
  });

  test(
      'drawio-parity batch82 IBM expansion (schematics/satellite/aspera) round-trip',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final atId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ibmActivityTracker(
        id: atId, pinX: 1, pinY: 8, width: 1.3, height: 1.1));
    final logId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ibmLogAnalysis(
        id: logId, pinX: 3, pinY: 8, width: 1.2, height: 1.2));
    final schId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ibmSchematics(
        id: schId, pinX: 5, pinY: 8, width: 1.2, height: 1.3));
    final satId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ibmSatellite(
        id: satId, pinX: 7, pinY: 8, width: 1.2, height: 1.2));
    final pvsId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ibmPowerVs(
        id: pvsId, pinX: 1, pinY: 5, width: 1.3, height: 1.2));
    final cisId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ibmCis(
        id: cisId, pinX: 3, pinY: 5, width: 1.2, height: 1.2));
    final aspId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ibmAspera(
        id: aspId, pinX: 5, pinY: 5, width: 1.3, height: 1.0));
    final secId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ibmSecurityAdvisor(
        id: secId, pinX: 7, pinY: 5, width: 1.1, height: 1.2));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(
        r.pages.first
            .findShapeById(atId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(5));
    expect(r.pages.first.findShapeById(logId)!.geometries.length, 2);
    expect(r.pages.first.findShapeById(schId)!.geometries.length, 4);
    expect(
        r.pages.first
            .findShapeById(satId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(2));
    expect(r.pages.first.findShapeById(pvsId)!.geometries.length, 4);
    expect(
        r.pages.first
            .findShapeById(cisId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(4));
    expect(r.pages.first.findShapeById(aspId)!.geometries.length, 2);
    expect(
        r.pages.first
            .findShapeById(secId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
  });

  test('drawio-parity batch81 Alibaba expansion (cdn/flink/nat) round-trip',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final cdnId = page.nextFreeShapeId();
    add(VsdxShapeFactory.alibabaCdn(
        id: cdnId, pinX: 1, pinY: 8, width: 1.2, height: 1.2));
    final wafId = page.nextFreeShapeId();
    add(VsdxShapeFactory.alibabaWaf(
        id: wafId, pinX: 3, pinY: 8, width: 1.1, height: 1.2));
    final dwId = page.nextFreeShapeId();
    add(VsdxShapeFactory.alibabaDataWorks(
        id: dwId, pinX: 5, pinY: 8, width: 1.2, height: 1.2));
    final flinkId = page.nextFreeShapeId();
    add(VsdxShapeFactory.alibabaFlink(
        id: flinkId, pinX: 7, pinY: 8, width: 1.5, height: 1.0));
    final mseId = page.nextFreeShapeId();
    add(VsdxShapeFactory.alibabaMse(
        id: mseId, pinX: 1, pinY: 5, width: 1.2, height: 1.2));
    final eipId = page.nextFreeShapeId();
    add(VsdxShapeFactory.alibabaEip(
        id: eipId, pinX: 3, pinY: 5, width: 1.1, height: 1.1));
    final natId = page.nextFreeShapeId();
    add(VsdxShapeFactory.alibabaNatGateway(
        id: natId, pinX: 5, pinY: 5, width: 1.3, height: 1.2));
    final dtsId = page.nextFreeShapeId();
    add(VsdxShapeFactory.alibabaDts(
        id: dtsId, pinX: 7, pinY: 5, width: 1.2, height: 1.3));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(
        r.pages.first
            .findShapeById(cdnId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(wafId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(dwId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(flinkId)!.geometries.length, 3);
    expect(
        r.pages.first
            .findShapeById(mseId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(5));
    expect(
        r.pages.first
            .findShapeById(eipId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(2));
    expect(
        r.pages.first
            .findShapeById(natId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(4));
    expect(r.pages.first.findShapeById(dtsId)!.geometries.length, 2);
  });

  test('drawio-parity batch80 Oracle starter (adb/oke/exadata) round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final ciId = page.nextFreeShapeId();
    add(VsdxShapeFactory.oracleComputeInstance(
        id: ciId, pinX: 1, pinY: 8, width: 1.3, height: 1.2));
    final adbId = page.nextFreeShapeId();
    add(VsdxShapeFactory.oracleAutonomousDatabase(
        id: adbId, pinX: 3, pinY: 8, width: 1.2, height: 1.3));
    final okeId = page.nextFreeShapeId();
    add(VsdxShapeFactory.oracleOke(
        id: okeId, pinX: 5, pinY: 8, width: 1.2, height: 1.2));
    final vcnId = page.nextFreeShapeId();
    add(VsdxShapeFactory.oracleVcn(
        id: vcnId, pinX: 7, pinY: 8, width: 1.5, height: 1.1));
    final streamId = page.nextFreeShapeId();
    add(VsdxShapeFactory.oracleStreaming(
        id: streamId, pinX: 1, pinY: 5, width: 1.4, height: 1.0));
    final exaId = page.nextFreeShapeId();
    add(VsdxShapeFactory.oracleExadata(
        id: exaId, pinX: 3, pinY: 5, width: 1.3, height: 1.3));
    final hwId = page.nextFreeShapeId();
    add(VsdxShapeFactory.oracleMysqlHeatwave(
        id: hwId, pinX: 5, pinY: 5, width: 1.4, height: 1.2));
    final ggId = page.nextFreeShapeId();
    add(VsdxShapeFactory.oracleGoldenGate(
        id: ggId, pinX: 7, pinY: 5, width: 1.5, height: 1.0));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(r.pages.first.findShapeById(ciId)!.geometries.length, 4);
    expect(
        r.pages.first
            .findShapeById(adbId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(okeId)!.geometries.length, 4);
    expect(
        r.pages.first
            .findShapeById(vcnId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(streamId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(exaId)!.geometries.length, 5);
    expect(
        r.pages.first
            .findShapeById(hwId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(ggId)!.geometries.length, 3);
  });

  test('drawio-parity batch79 IBM starter (vpc/db2/watsonx) round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final vpcId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ibmVpc(
        id: vpcId, pinX: 1, pinY: 8, width: 1.5, height: 1.1));
    final cosId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ibmCloudObjectStorage(
        id: cosId, pinX: 3, pinY: 8, width: 1.2, height: 1.3));
    final iksId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ibmIks(
        id: iksId, pinX: 5, pinY: 8, width: 1.2, height: 1.2));
    final db2Id = page.nextFreeShapeId();
    add(VsdxShapeFactory.ibmDb2(
        id: db2Id, pinX: 7, pinY: 8, width: 1.2, height: 1.2));
    final esId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ibmEventStreams(
        id: esId, pinX: 1, pinY: 5, width: 1.4, height: 1.0));
    final wxId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ibmWatsonx(
        id: wxId, pinX: 3, pinY: 5, width: 1.3, height: 1.2));
    final ceId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ibmCodeEngine(
        id: ceId, pinX: 5, pinY: 5, width: 1.3, height: 1.0));
    final kpId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ibmKeyProtect(
        id: kpId, pinX: 7, pinY: 5, width: 1.1, height: 1.2));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(
        r.pages.first
            .findShapeById(vpcId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(cosId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(iksId)!.geometries.length, 4);
    expect(
        r.pages.first
            .findShapeById(db2Id)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(esId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(wxId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(6));
    expect(
        r.pages.first
            .findShapeById(ceId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(kpId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
  });

  test('drawio-parity batch78 Alibaba starter (ecs/oss/ack) round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final ecsId = page.nextFreeShapeId();
    add(VsdxShapeFactory.alibabaEcs(
        id: ecsId, pinX: 1, pinY: 8, width: 1.3, height: 1.2));
    final ossId = page.nextFreeShapeId();
    add(VsdxShapeFactory.alibabaOss(
        id: ossId, pinX: 3, pinY: 8, width: 1.2, height: 1.3));
    final slbId = page.nextFreeShapeId();
    add(VsdxShapeFactory.alibabaSlb(
        id: slbId, pinX: 5, pinY: 8, width: 1.2, height: 1.2));
    final ackId = page.nextFreeShapeId();
    add(VsdxShapeFactory.alibabaAck(
        id: ackId, pinX: 7, pinY: 8, width: 1.2, height: 1.2));
    final polarId = page.nextFreeShapeId();
    add(VsdxShapeFactory.alibabaPolarDb(
        id: polarId, pinX: 1, pinY: 5, width: 1.2, height: 1.3));
    final mqId = page.nextFreeShapeId();
    add(VsdxShapeFactory.alibabaRocketMq(
        id: mqId, pinX: 3, pinY: 5, width: 1.2, height: 1.2));
    final cenId = page.nextFreeShapeId();
    add(VsdxShapeFactory.alibabaCen(
        id: cenId, pinX: 5, pinY: 5, width: 1.2, height: 1.2));
    final slsId = page.nextFreeShapeId();
    add(VsdxShapeFactory.alibabaSls(
        id: slsId, pinX: 7, pinY: 5, width: 1.2, height: 1.1));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(r.pages.first.findShapeById(ecsId)!.geometries.length, 4);
    expect(
        r.pages.first
            .findShapeById(ossId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(slbId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(4));
    expect(r.pages.first.findShapeById(ackId)!.geometries.length, 4);
    expect(
        r.pages.first
            .findShapeById(polarId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(mqId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(5));
    expect(
        r.pages.first
            .findShapeById(cenId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(5));
    expect(
        r.pages.first
            .findShapeById(slsId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
  });

  test('drawio-parity batch77 AWS expansion2 (fargate/glue/waf) round-trip',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final fgId = page.nextFreeShapeId();
    add(VsdxShapeFactory.awsFargate(
        id: fgId, pinX: 1, pinY: 8, width: 1.3, height: 1.0));
    final glueId = page.nextFreeShapeId();
    add(VsdxShapeFactory.awsGlue(
        id: glueId, pinX: 3, pinY: 8, width: 1.2, height: 1.3));
    final athId = page.nextFreeShapeId();
    add(VsdxShapeFactory.awsAthena(
        id: athId, pinX: 5, pinY: 8, width: 1.2, height: 1.2));
    final emrId = page.nextFreeShapeId();
    add(VsdxShapeFactory.awsEmr(
        id: emrId, pinX: 7, pinY: 8, width: 1.2, height: 1.2));
    final smId = page.nextFreeShapeId();
    add(VsdxShapeFactory.awsSecretsManager(
        id: smId, pinX: 1, pinY: 5, width: 1.1, height: 1.2));
    final pipeId = page.nextFreeShapeId();
    add(VsdxShapeFactory.awsCodePipeline(
        id: pipeId, pinX: 3, pinY: 5, width: 1.5, height: 1.0));
    final wafId = page.nextFreeShapeId();
    add(VsdxShapeFactory.awsWaf(
        id: wafId, pinX: 5, pinY: 5, width: 1.1, height: 1.2));
    final tgId = page.nextFreeShapeId();
    add(VsdxShapeFactory.awsTransitGateway(
        id: tgId, pinX: 7, pinY: 5, width: 1.2, height: 1.2));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(
        r.pages.first
            .findShapeById(fgId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(glueId)!.geometries.length, 2);
    expect(
        r.pages.first
            .findShapeById(athId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(emrId)!.geometries.length, 4);
    expect(
        r.pages.first
            .findShapeById(smId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(pipeId)!.geometries.length, 3);
    expect(
        r.pages.first
            .findShapeById(wafId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(tgId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(6));
  });

  test('drawio-parity batch76 Cisco expansion (wlc/ise/core) round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final wlcId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ciscoWirelessController(
        id: wlcId, pinX: 1, pinY: 8, width: 1.4, height: 1.0));
    final atmId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ciscoAtmSwitch(
        id: atmId, pinX: 3, pinY: 8, width: 1.2, height: 1.2));
    final vpnId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ciscoVpnConcentrator(
        id: vpnId, pinX: 5, pinY: 8, width: 1.4, height: 1.1));
    final bridgeId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ciscoWirelessBridge(
        id: bridgeId, pinX: 7, pinY: 8, width: 1.4, height: 1.1));
    final iseId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ciscoIse(
        id: iseId, pinX: 1, pinY: 5, width: 1.1, height: 1.2));
    final dnaId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ciscoDnaCenter(
        id: dnaId, pinX: 3, pinY: 5, width: 1.2, height: 1.2));
    final tpId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ciscoTelepresence(
        id: tpId, pinX: 5, pinY: 5, width: 1.4, height: 1.2));
    final coreId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ciscoCoreSwitch(
        id: coreId, pinX: 7, pinY: 5, width: 1.4, height: 1.3));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(
        r.pages.first
            .findShapeById(wlcId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(atmId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(4));
    expect(
        r.pages.first
            .findShapeById(vpnId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(bridgeId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(2));
    expect(
        r.pages.first
            .findShapeById(iseId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(dnaId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(5));
    expect(r.pages.first.findShapeById(tpId)!.geometries.length, 4);
    expect(r.pages.first.findShapeById(coreId)!.geometries.length, 4);
  });

  test(
      'drawio-parity batch75 GCP expansion (dataflow/firestore/vertex) round-trip',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final dfId = page.nextFreeShapeId();
    add(VsdxShapeFactory.gcpDataflow(
        id: dfId, pinX: 1, pinY: 8, width: 1.5, height: 1.0));
    final dpId = page.nextFreeShapeId();
    add(VsdxShapeFactory.gcpDataproc(
        id: dpId, pinX: 3, pinY: 8, width: 1.2, height: 1.2));
    final compId = page.nextFreeShapeId();
    add(VsdxShapeFactory.gcpCloudComposer(
        id: compId, pinX: 5, pinY: 8, width: 1.3, height: 1.2));
    final armorId = page.nextFreeShapeId();
    add(VsdxShapeFactory.gcpCloudArmor(
        id: armorId, pinX: 7, pinY: 8, width: 1.1, height: 1.2));
    final schedId = page.nextFreeShapeId();
    add(VsdxShapeFactory.gcpCloudScheduler(
        id: schedId, pinX: 1, pinY: 5, width: 1.1, height: 1.1));
    final fsId = page.nextFreeShapeId();
    add(VsdxShapeFactory.gcpFirestore(
        id: fsId, pinX: 3, pinY: 5, width: 1.1, height: 1.3));
    final secId = page.nextFreeShapeId();
    add(VsdxShapeFactory.gcpSecretManager(
        id: secId, pinX: 5, pinY: 5, width: 1.1, height: 1.2));
    final vtxId = page.nextFreeShapeId();
    add(VsdxShapeFactory.gcpVertexAi(
        id: vtxId, pinX: 7, pinY: 5, width: 1.3, height: 1.2));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(r.pages.first.findShapeById(dfId)!.geometries.length, 3);
    expect(r.pages.first.findShapeById(dpId)!.geometries.length, 4);
    expect(
        r.pages.first
            .findShapeById(compId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(6));
    expect(
        r.pages.first
            .findShapeById(armorId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(schedId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(fsId)!.geometries.length, 3);
    expect(
        r.pages.first
            .findShapeById(secId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(vtxId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(6));
  });

  test('drawio-parity batch74 Azure expansion (aci/iot/firewall) round-trip',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final aciId = page.nextFreeShapeId();
    add(VsdxShapeFactory.azureContainerInstances(
        id: aciId, pinX: 1, pinY: 8, width: 1.2, height: 1.3));
    final redisId = page.nextFreeShapeId();
    add(VsdxShapeFactory.azureRedisCache(
        id: redisId, pinX: 3, pinY: 8, width: 1.2, height: 1.2));
    final fdId = page.nextFreeShapeId();
    add(VsdxShapeFactory.azureFrontDoor(
        id: fdId, pinX: 5, pinY: 8, width: 1.2, height: 1.2));
    final logicId = page.nextFreeShapeId();
    add(VsdxShapeFactory.azureLogicApps(
        id: logicId, pinX: 7, pinY: 8, width: 1.3, height: 1.2));
    final iotId = page.nextFreeShapeId();
    add(VsdxShapeFactory.azureIotHub(
        id: iotId, pinX: 1, pinY: 5, width: 1.2, height: 1.2));
    final fwId = page.nextFreeShapeId();
    add(VsdxShapeFactory.azureFirewall(
        id: fwId, pinX: 3, pinY: 5, width: 1.2, height: 1.3));
    final bastionId = page.nextFreeShapeId();
    add(VsdxShapeFactory.azureBastion(
        id: bastionId, pinX: 5, pinY: 5, width: 1.1, height: 1.2));
    final devopsId = page.nextFreeShapeId();
    add(VsdxShapeFactory.azureDevOps(
        id: devopsId, pinX: 7, pinY: 5, width: 1.2, height: 1.2));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(r.pages.first.findShapeById(aciId)!.geometries.length, 4);
    expect(
        r.pages.first
            .findShapeById(redisId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(fdId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(4));
    expect(
        r.pages.first
            .findShapeById(logicId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(3));
    expect(
        r.pages.first
            .findShapeById(iotId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(5));
    expect(r.pages.first.findShapeById(fwId)!.geometries.length, 2);
    expect(
        r.pages.first
            .findShapeById(bastionId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(devopsId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
  });

  test('drawio-parity batch73 Cisco starter (router/asa/ap) round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    void add(VsdxShape s) => page = page.addShape(s);

    final rtrId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ciscoRouter(
        id: rtrId, pinX: 1, pinY: 8, width: 1.4, height: 1.0));
    final swId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ciscoSwitch(
        id: swId, pinX: 3, pinY: 8, width: 1.5, height: 0.9));
    final asaId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ciscoAsaFirewall(
        id: asaId, pinX: 5, pinY: 8, width: 1.3, height: 1.1));
    final apId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ciscoAccessPoint(
        id: apId, pinX: 7, pinY: 8, width: 1.2, height: 1.1));
    final phoneId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ciscoIpPhone(
        id: phoneId, pinX: 1, pinY: 5, width: 1.3, height: 1.1));
    final wanId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ciscoWanRouter(
        id: wanId, pinX: 3, pinY: 5, width: 1.4, height: 1.2));
    final fiId = page.nextFreeShapeId();
    add(VsdxShapeFactory.ciscoFabricInterconnect(
        id: fiId, pinX: 5, pinY: 5, width: 1.5, height: 1.1));
    doc = doc.replacePage(0, page);

    final r = parser.parse(writer.write(originalBytes: blank, edited: doc));
    expect(
        r.pages.first
            .findShapeById(rtrId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(3));
    expect(
        r.pages.first
            .findShapeById(swId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(asaId)!.geometries.length, 3);
    expect(
        r.pages.first
            .findShapeById(apId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(r.pages.first.findShapeById(phoneId)!.geometries.length, 3);
    expect(
        r.pages.first
            .findShapeById(wanId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipticalArcTo>(),
        isNotEmpty);
    expect(
        r.pages.first
            .findShapeById(fiId)!
            .geometries
            .expand((g) => g.commands)
            .whereType<EllipseCmd>()
            .length,
        greaterThanOrEqualTo(3));
  });

  // Regression: `_buildShapeElement` used to omit arrows, flips, transparencies,
  // shadow, LocPin, VerticalAlign and Character/Paragraph sections — so a
  // freshly-created (or reparented) shape looked very different after save +
  // reopen. An unfilled 1-D with LineColorTrans also bakes a FillForegndTrans
  // ribbon and arrow Geometry because libvisio has no LineColorTrans token
  // and sizes markers from line weight, not BeginArrowSize.
  test(
      'newly emitted shapes preserve style / text / LocPin (buildShape parity)',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;

    final connId = page.nextFreeShapeId();
    page = page.addShape(VsdxShapeFactory.line(
      id: connId,
      ax: 1,
      ay: 1,
      bx: 4,
      by: 2,
      line: const VsdxLine(
        color: VsdxColor.black,
        beginArrow: 1,
        endArrow: 4,
        transparency: 0.3,
        pattern: 2,
      ),
    ));

    final labelId = page.nextFreeShapeId();
    page = page.addShape(
      VsdxShapeFactory.textBox(
        id: labelId,
        pinX: 6,
        pinY: 4,
        width: 2,
        height: 0.6,
        text: 'Bold Red',
      ).copyWith(
        richText: const VsdxRichText(
          runs: <VsdxTextRun>[
            VsdxTextRun(
              text: 'Bold Red',
              charStyle: VsdxCharStyle(
                fontFamily: 'Arial',
                fontSizeInches: 0.25,
                style: VsdxFontStyle.boldStyle,
                color: VsdxColor(0xFFCC0000),
                underline: true,
              ),
              paraStyle: VsdxParaStyle(horizontalAlign: VsdxHorzAlign.center),
            ),
          ],
          textBlock: VsdxTextBlock(verticalAlign: VsdxVertAlign.bottom),
        ),
      ),
    );

    final styledId = page.nextFreeShapeId();
    page = page.addShape(
      VsdxShapeFactory.rectangle(
        id: styledId,
        pinX: 3,
        pinY: 5,
        width: 2,
        height: 1,
        fill: const VsdxFill(
          foreground: VsdxColor(0xFF3366CC),
          foregroundTransparency: 0.5,
        ),
        line: const VsdxLine(color: VsdxColor.black, transparency: 0.25),
      ).copyWith(
        flipX: true,
        shadow: const VsdxShadow(blurInches: 0),
        // Off-centre LocPin (not the default width/2, height/2).
        locPinXInches: 0.25,
        locPinYInches: 0.75,
      ),
    );

    doc = doc.replacePage(0, page);
    final out = parser.parse(writer.write(originalBytes: blank, edited: doc));
    final rp = out.pages.first;

    final conn = rp.findShapeById(connId)!;
    expect(conn.is1D, isTrue);
    expect(conn.line.beginArrow, 0);
    expect(conn.line.endArrow, 0);
    expect(conn.line.pattern, 0);
    expect(conn.fill.foregroundTransparency, closeTo(0.3, 1e-4));
    expect(conn.geometries.where((g) => !g.noFill).length,
        greaterThanOrEqualTo(2));

    final label = rp.findShapeById(labelId)!;
    expect(label.richText.textBlock.verticalAlign, VsdxVertAlign.bottom);
    expect(label.richText.runs, isNotEmpty);
    final char = label.richText.runs.first.charStyle;
    expect(char.fontSizeInches, closeTo(0.25, 1e-4));
    expect(char.style.bold, isTrue);
    expect(char.underline, isTrue);
    expect(char.color?.value, 0xFFCC0000);
    expect(char.fontFamily, 'Arial');
    expect(label.richText.runs.first.paraStyle.horizontalAlign,
        VsdxHorzAlign.center);
    expect(label.richText.plainText, 'Bold Red');

    final styled = rp.findShapeById(styledId)!;
    expect(styled.flipX, isTrue);
    expect(styled.shadow.enabled, isTrue);
    expect(styled.fill.foregroundTransparency, closeTo(0.5, 1e-4));
    expect(styled.line.transparency, closeTo(0, 1e-4));
    expect(
      styled.line.color?.value,
      colourForLibvisioAlpha(VsdxColor.black, 0.25).value,
    );
    expect(styled.effectiveLocPinX, closeTo(0.25, 1e-4));
    expect(styled.effectiveLocPinY, closeTo(0.75, 1e-4));
  });

  test('resize patches LocPin to the new effective centre', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    // Explicit centre LocPin so the XML carries LocPinX/Y cells.
    final rect = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 3,
      pinY: 3,
      width: 2,
      height: 1,
    ).copyWith(locPinXInches: 1.0, locPinYInches: 0.5);
    doc = doc.replacePage(0, doc.pages.first.addShape(rect));
    final bytes1 = writer.write(originalBytes: blank, edited: doc);

    final r1 = parser.parse(bytes1);
    final resized = r1.replacePage(
      0,
      r1.pages.first.updateShapeById(
        id,
        (s) => s.resizeTo(pinX: 3, pinY: 3, width: 4, height: 2),
      ),
    );
    final after = parser
        .parse(writer.write(originalBytes: bytes1, edited: resized))
        .pages
        .first
        .findShapeById(id)!;
    expect(after.width, closeTo(4, 1e-4));
    expect(after.height, closeTo(2, 1e-4));
    // LocPin scaled with the box (was centre → still centre).
    expect(after.effectiveLocPinX, closeTo(2.0, 1e-4));
    expect(after.effectiveLocPinY, closeTo(1.0, 1e-4));
  });

  // libvisio / Visio parametric shapes rely on F=Width*… / Scratch.* surviving
  // a resize. Full Geometry rebuilds used to strip those formulas.
  test('resize keeps Width/Scratch geometry formulas (workflow)', () {
    final bytes = _fixture('workflow.vsdx');
    final doc = parser.parse(bytes);
    final page = doc.pages.first;
    final shape = page.shapes.firstWhere(
      (s) => s.geometries.isNotEmpty && s.width > 0.5 && s.height > 0.5,
    );
    final resized = doc.replacePage(
      0,
      page.updateShapeById(
        shape.id,
        (s) => s.resizeTo(
          pinX: s.pinX,
          pinY: s.pinY,
          width: s.width * 2,
          height: s.height * 2,
        ),
      ),
    );
    final out = writer.write(originalBytes: bytes, edited: resized);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    // Parametric rounded-rect / connection formulas must still be present.
    expect(pageXml.contains('F="Scratch.X1"'), isTrue);
    expect(pageXml.contains('F="Width*0.5"'), isTrue);
    expect(pageXml.contains('F="Height*0.5"'), isTrue);
    // LocPin on the resized shape keeps its original F= (e.g. (EndX-BeginX)/2
    // or Width*0.5) — attribute order is F before N in Visio XML.
    final shapeXml = RegExp(
      'ID="${shape.id}"[\\s\\S]*?(?=<Shape |</Shapes>)',
    ).firstMatch(pageXml)?.group(0);
    expect(shapeXml, isNotNull);
    final locPinX =
        RegExp(r'<Cell[^>]*N="LocPinX"[^>]*/?>').firstMatch(shapeXml!);
    if (locPinX != null) {
      expect(locPinX.group(0)!.contains('F="'), isTrue,
          reason: 'LocPinX should retain F= after proportional resize');
    }
  });

  // Style-only Character edits must keep unmodelled cells (FontScale, …).
  test('style edit preserves Character FontScale / AsianFont cells', () {
    final bytes = _fixture('workflow.vsdx');
    final doc = parser.parse(bytes);
    final page = doc.pages.first;
    final shape = page.shapes.firstWhere(
      (s) => s.richText.runs.isNotEmpty && (s.text?.isNotEmpty ?? false),
    );
    final edited = doc.replacePage(
      0,
      page.updateShapeById(shape.id, (s) {
        final run = s.richText.runs.first;
        return s.copyWith(
          richText: s.richText.copyWith(
            runs: [
              run.copyWith(
                charStyle: run.charStyle.copyWith(
                  style: const VsdxFontStyle(bold: true),
                ),
              ),
            ],
          ),
        );
      }),
    );
    final out = writer.write(originalBytes: bytes, edited: edited);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final shapeXml = RegExp(
      'ID="${shape.id}"[\\s\\S]*?(?=<Shape |</Shapes>)',
    ).firstMatch(pageXml)!.group(0)!;
    expect(shapeXml.contains('N="FontScale"'), isTrue);
    expect(
        shapeXml.contains('N="AsianFont"') || shapeXml.contains('N="LangID"'),
        isTrue);
  });

  test('connection point add / move / remove round-trips', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final rect = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
    ).copyWith(
      connectionPoints: VsdxPage.defaultConnectionPoints(2, 1),
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(rect));
    final bytes1 = writer.write(originalBytes: blank, edited: doc);

    // Drop the centre point (index 4) and nudge the top point.
    doc = parser.parse(bytes1);
    final edited = doc.pages.first
        .removeConnectionPoint(id, 4)
        .moveConnectionPoint(id, 0, 1.5, 1.0);
    final out = writer.write(
      originalBytes: bytes1,
      edited: doc.replacePage(0, edited),
    );
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.connectionPoints.length, 4);
    expect(after.connectionPoints[0].x, closeTo(1.5, 1e-6));
    expect(after.connectionPoints[0].y, closeTo(1.0, 1e-6));
    expect(after.connectionPoints[0].xFormula, isNotNull);
    // Adding a custom point also round-trips.
    doc = parser.parse(out);
    final withExtra = doc.pages.first.addConnectionPoint(id, 0.25, 0.25);
    final out2 = writer.write(
      originalBytes: out,
      edited: doc.replacePage(0, withExtra),
    );
    final again = parser.parse(out2).pages.first.findShapeById(id)!;
    expect(again.connectionPoints.length, 5);
    expect(again.connectionPoints.last.x, closeTo(0.25, 1e-6));
  });

  test('materialised connection points write DirX/DirY/Type', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final a = VsdxShapeFactory.rectangle(
        id: 1, pinX: 2, pinY: 2, width: 1, height: 1);
    final b = VsdxShapeFactory.rectangle(
        id: 2, pinX: 5, pinY: 2, width: 1, height: 1);
    doc = doc.replacePage(0, doc.pages.first.addShape(a).addShape(b));
    final bytes1 = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(bytes1);
    final page = doc.pages.first.updateShapeById(
      2,
      (s) => s.copyWith(
        connectionPoints: VsdxPage.defaultConnectionPoints(s.width, s.height),
      ),
    );
    final out =
        writer.write(originalBytes: bytes1, edited: doc.replacePage(0, page));
    final after = parser.parse(out).pages.first.findShapeById(2)!;
    expect(after.connectionPoints.length, 5);
    expect(after.connectionPoints[0].dirY, closeTo(1, 1e-9));
    expect(after.connectionPoints[1].dirX, closeTo(1, 1e-9));
    expect(after.connectionPoints[2].dirY, closeTo(-1, 1e-9));
    expect(after.connectionPoints[3].dirX, closeTo(-1, 1e-9));
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="DirX"'), isTrue);
    expect(pageXml.contains('N="DirY"'), isTrue);
    expect(pageXml.contains('N="Type"'), isTrue);
    expect(pageXml.contains('N="AutoGen"'), isTrue);
  });

  test('LineGradient round-trips on new shape', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final grad = VsdxGradient(
      type: VsdxGradientType.linear,
      angleRad: 0.5,
      stops: const [
        VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
        VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
      ],
    );
    final rect = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
    ).copyWith(line: VsdxLine(gradient: grad, weightInches: 0.05));
    doc = doc.replacePage(0, doc.pages.first.addShape(rect));
    final out = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.line.hasGradient, isTrue);
    expect(after.line.gradient!.stops.length, 2);
    expect(after.line.gradient!.angleRad, closeTo(0.5, 1e-6));
  });

  // libvisio CharIX / ParaIX fields: Case, FontScale, smallcaps, Bullet, Flags.
  test('Character Case/FontScale/smallCaps + Paragraph Bullet/Flags round-trip',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final rect = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
    ).copyWith(
      text: 'Hello',
      richText: VsdxRichText(
        runs: [
          VsdxTextRun(
            text: 'Hello',
            charStyle: const VsdxCharStyle(
              fontSizeInches: 14 / 72,
              style: VsdxFontStyle(bold: true, smallCaps: true),
              textCase: VsdxTextCase.allCaps,
              fontScale: 0.9,
              doubleUnderline: true,
            ),
            paraStyle: const VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
              bullet: 1,
              bulletStr: '•',
              flags: 2,
            ),
          ),
        ],
      ),
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(rect));
    final out = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    final run = after.richText.runs.first;
    expect(run.charStyle.style.smallCaps, isTrue);
    expect(run.charStyle.textCase, VsdxTextCase.allCaps);
    expect(run.charStyle.fontScale, closeTo(0.9, 1e-6));
    expect(run.charStyle.doubleUnderline, isTrue);
    expect(run.paraStyle.bullet, 1);
    expect(run.paraStyle.bulletStr, '•');
    expect(run.paraStyle.flags, 2);
  });

  test('Control + Scratch round-trip (group rebuild path)', () {
    // Parse fixtures that carry the sections, then force a shape rebuild by
    // grouping — writer must re-emit Control/Scratch with formulas.
    final bytes = _fixture('test5_master.vsdx');
    final doc = parser.parse(bytes);
    final withControl =
        doc.pages.first.shapes.where((s) => s.controls.isNotEmpty).toList();
    expect(withControl, isNotEmpty);
    final c0 = withControl.first.controls.first;
    expect(c0.name, 'TextPosition');
    expect(c0.dynXFormula, isNotNull);

    final wf = parser.parse(_fixture('workflow.vsdx'));
    final withScratch =
        wf.pages.first.shapes.where((s) => s.scratch.isNotEmpty).toList();
    expect(withScratch, isNotEmpty);
    expect(withScratch.first.scratch.first.xFormula, contains('MIN'));

    // Rebuild a new shape carrying both sections.
    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 3,
      pinY: 3,
      width: 2,
      height: 1,
    ).copyWith(
      controls: [
        VsdxControlRow(
          name: 'TextPosition',
          x: 1.0,
          y: 0,
          dynX: 1.0,
          dynY: 0,
          dynXFormula: 'TextPosition',
          dynYFormula: 'TextPosition.Y',
          prompt: 'Reposition Text',
        ),
      ],
      scratch: [
        const VsdxScratchRow(
          ix: 0,
          x: 0.5,
          xFormula: 'MIN(Height/2,Width/2)',
        ),
      ],
      richText: const VsdxRichText(
        runs: [VsdxTextRun(text: 'Label')],
        textBlock: VsdxTextBlock(pinXInches: 1.0, pinYInches: 0),
      ),
    );
    outDoc = outDoc.replacePage(0, outDoc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="Control"'), isTrue);
    expect(pageXml.contains('N="TextPosition"'), isTrue);
    expect(pageXml.contains('F="TextPosition"'), isTrue);
    expect(
        pageXml.contains('N="XDyn"') || pageXml.contains('N="DynX"'), isTrue);
    expect(pageXml.contains('N="Scratch"'), isTrue);
    expect(pageXml.contains('F="MIN(Height/2,Width/2)"'), isTrue);

    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.controls.single.name, 'TextPosition');
    expect(after.controls.single.dynXFormula, 'TextPosition');
    expect(after.scratch.single.xFormula, 'MIN(Height/2,Width/2)');
  });

  test('TxtPin SETATREF formula survives pin cache update', () {
    final bytes = _fixture('test5_master.vsdx');
    final doc = parser.parse(bytes);
    final shape = doc.pages.first.shapes.firstWhere(
      (s) => s.controls.isNotEmpty && s.richText.textBlock.pinXInches != null,
    );
    final pin = shape.richText.textBlock.pinXInches!;
    final edited = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        shape.id,
        (s) => s.copyWith(
          richText: s.richText.copyWith(
            textBlock: s.richText.textBlock.copyWith(
              pinXInches: pin + 0.01,
            ),
          ),
        ),
      ),
    );
    final out = writer.write(originalBytes: bytes, edited: edited);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('SETATREF(Controls.TextPosition)'), isTrue);
  });

  test('text edit emits <tp> for tab characters', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final rect = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
    ).copyWith(
      text: 'A\tB',
      richText: const VsdxRichText(
        runs: [VsdxTextRun(text: 'A\tB')],
      ),
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(rect));
    final out = writer.write(originalBytes: blank, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
        pageXml.contains('<tp IX="0"/>') || pageXml.contains("<tp IX=\"0\"/>"),
        isTrue);
    expect(pageXml, contains('\t'));
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.richText.plainText.contains('\t'), isTrue);
  });

  test('locale Character fonts and sizes round-trip on new shape', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final rect = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
    ).copyWith(
      text: '你好 سلام',
      richText: VsdxRichText(
        runs: [
          VsdxTextRun(
            text: '你好 سلام',
            charStyle: const VsdxCharStyle(
              fontFamily: 'Arial',
              asianFont: 'Microsoft YaHei',
              complexScriptFont: 'Times New Roman',
              complexScriptSizeInches: 0.22,
              langId: 'zh-CN',
            ),
          ),
        ],
      ),
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(rect));
    final after = parser
        .parse(writer.write(originalBytes: blank, edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    final c = after.richText.runs.first.charStyle;
    expect(c.asianFont, 'Microsoft YaHei');
    expect(c.langId, 'zh-CN');
    expect(c.complexScriptFont, 'Times New Roman');
    expect(c.complexScriptSizeInches, closeTo(0.22, 1e-9));
  });

  test('Master attribute survives parse → rebuild write', () {
    final bytes = _fixture('test5_master.vsdx');
    final doc = parser.parse(bytes);
    final shaped = doc.pages.first.shapes.where((s) => s.masterId != null);
    expect(shaped, isNotEmpty);
    final s = shaped.first;
    // Force rebuild by grouping alone then writing a copy as new shape.
    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    final clone = s.copyWith(id: id, pinX: 1, pinY: 1);
    outDoc = outDoc.replacePage(0, outDoc.pages.first.addShape(clone));
    final out = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('Master="${s.masterId}"'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.masterId, s.masterId);
  });

  test('MasterShape + style attrs survive parse → rebuild', () {
    final bytes = _fixture('test5_master.vsdx');
    final doc = parser.parse(bytes);
    VsdxShape? withMasterShape;
    void walk(VsdxShape s) {
      if (s.masterShapeId != null) withMasterShape ??= s;
      for (final c in s.children) {
        walk(c);
      }
    }

    for (final s in doc.pages.first.shapes) {
      walk(s);
    }
    expect(withMasterShape, isNotNull);
    final s = withMasterShape!;

    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    final clone = s.copyWith(
      id: id,
      pinX: 1,
      pinY: 1,
      children: const [],
      lineStyleId: s.lineStyleId ?? 3,
      fillStyleId: s.fillStyleId ?? 3,
      textStyleId: s.textStyleId ?? 3,
    );
    outDoc = outDoc.replacePage(0, outDoc.pages.first.addShape(clone));
    final out = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('MasterShape="${s.masterShapeId}"'), isTrue);
    expect(pageXml.contains('LineStyle="'), isTrue);
    expect(pageXml.contains('FillStyle="'), isTrue);
    expect(pageXml.contains('TextStyle="'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.masterShapeId, s.masterShapeId);
    expect(after.lineStyleId, clone.lineStyleId);
  });

  test('Field section + fld marker round-trip on rebuild', () {
    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    const display = '42';
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 1.5,
      height: 0.5,
    ).copyWith(
      fields: const [
        VsdxFieldRow(
          ix: 0,
          value: display,
          valueFormula: 'PAGENUMBER()',
          format: 'esc(0)',
          formatFormula: 'FIELDPICTURE(0)',
          type: 0,
          uiCat: 0,
          uiCod: 0,
          uiFmt: 0,
          calendar: 0,
          objectKind: 0,
        ),
      ],
      richText: const VsdxRichText(
        runs: [
          VsdxTextRun(
            text: display,
            fieldSpans: [VsdxFieldSpan(start: 0, length: 2, ix: 0)],
          ),
        ],
      ),
    );
    outDoc = outDoc.replacePage(0, outDoc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="Field"'), isTrue);
    expect(pageXml.contains('F="PAGENUMBER()"'), isTrue);
    expect(
        pageXml.contains('<fld IX="0">42</fld>') ||
            pageXml.contains("<fld IX=\"0\">42</fld>"),
        isTrue);

    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.fields, isNotEmpty);
    expect(after.fields.first.valueFormula, 'PAGENUMBER()');
    expect(after.richText.runs.first.fieldSpans, isNotEmpty);
    expect(after.richText.plainText, display);
  });

  test('style-range edit keeps fld markers through write/read', () {
    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    const display = 'X42Y';
    final base = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 1.5,
      height: 0.5,
    ).copyWith(
      fields: const [
        VsdxFieldRow(
          ix: 0,
          value: '42',
          valueFormula: 'PAGENUMBER()',
          type: 0,
        ),
      ],
      richText: const VsdxRichText(
        runs: [
          VsdxTextRun(
            text: display,
            fieldSpans: [VsdxFieldSpan(start: 1, length: 2, ix: 0)],
          ),
        ],
      ),
      text: display,
    );
    final styled = applyCharStyleToRange(
      base.richText,
      start: 0,
      end: 1,
      update: (c) => c.copyWith(style: c.style.copyWith(bold: true)),
    );
    outDoc = outDoc.replacePage(
      0,
      outDoc.pages.first.addShape(
        base.copyWith(richText: styled, text: styled.plainText),
      ),
    );
    final saved = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('<fld IX="0">'), isTrue);
    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.richText.plainText, display);
    var offset = 0;
    final abs = <VsdxFieldSpan>[];
    for (final r in after.richText.runs) {
      for (final f in r.fieldSpans) {
        abs.add(VsdxFieldSpan(
          start: offset + f.start,
          length: f.length,
          ix: f.ix,
        ));
      }
      offset += r.text.length;
    }
    expect(abs, isNotEmpty);
    expect(abs.first.start, 1);
    expect(abs.first.length, 2);
    expect(abs.first.ix, 0);
  });

  test('NoSnap / NoQuickDrag survive geometry rebuild', () {
    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(
      geometries: [
        VsdxGeometry(
          commands: const [
            MoveTo(0, 0),
            LineTo(2, 0),
            LineTo(2, 1),
            LineTo(0, 1),
            LineTo(0, 0),
          ],
          noSnap: true,
          noQuickDrag: true,
        ),
      ],
    );
    outDoc = outDoc.replacePage(0, outDoc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="NoSnap" V="1"'), isTrue);
    expect(pageXml.contains('N="NoQuickDrag" V="1"'), isTrue);
    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.geometries.first.noSnap, isTrue);
    expect(after.geometries.first.noQuickDrag, isTrue);
  });

  test('NoFill-only edit keeps Geometry formulas (no full rebuild)', () {
    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(
      geometries: [
        VsdxGeometry(
          commands: const [
            MoveTo(0, 0),
            LineTo(2, 0),
            LineTo(2, 1),
            LineTo(0, 1),
            LineTo(0, 0),
          ],
          commandFormulas: const [
            {'X': 'Width*0', 'Y': 'Height*0'},
            {'X': 'Width*1', 'Y': 'Height*0'},
            {'X': 'Width*1', 'Y': 'Height*1'},
            {'X': 'Width*0', 'Y': 'Height*1'},
            {'X': 'Width*0', 'Y': 'Height*0'},
          ],
        ),
      ],
    );
    outDoc = outDoc.replacePage(0, outDoc.pages.first.addShape(shape));
    final mid = writer.write(originalBytes: blank, edited: outDoc);
    final midDoc = parser.parse(mid);
    final edited = midDoc.replacePage(
      0,
      midDoc.pages.first.updateShapeById(id, (s) {
        return s.copyWith(
          fill: const VsdxFill(pattern: 0),
          geometries: syncGeometryNoFill(s.geometries, hollow: true),
        );
      }),
    );
    final out = writer.write(originalBytes: mid, edited: edited);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="NoFill" V="1"'), isTrue);
    expect(pageXml.contains('F="Width*1"'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.geometries.first.noFill, isTrue);
    expect(after.geometries.first.formulasAt(1)['X'], 'Width*1');
  });

  test('group rebuild preserves opaque EventDblClick / ObjType', () {
    final bytes = _fixture('test5_master.vsdx');
    final doc = parser.parse(bytes);
    final page = doc.pages.first;
    expect(page.shapes.length, greaterThanOrEqualTo(2));
    final a = page.shapes[0].id;
    final b = page.shapes[1].id;
    final gid = page.nextFreeShapeId();
    final grouped = doc.replacePage(0, page.group({a, b}, groupId: gid));
    final out = writer.write(originalBytes: bytes, edited: grouped);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="EventDblClick"'), isTrue);
    expect(pageXml.contains('OPENTEXTWIN()'), isTrue);
    expect(pageXml.contains('N="ObjType"'), isTrue);
  });

  test('EventDblClick F=Inh is not re-emitted on group rebuild', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final otherId = id + 1;
    final gid = otherId + 1;
    doc = doc.replacePage(
      0,
      doc.pages.first
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id,
              pinX: 1,
              pinY: 1,
              width: 2,
              height: 1,
            ).copyWith(
              eventDblClick: '0',
              formulas: const {'EventDblClick': 'Inh'},
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: otherId,
              pinX: 4,
              pinY: 1,
              width: 1,
              height: 1,
            ),
          ),
    );
    doc = doc.replacePage(
      0,
      doc.pages.first.group({id, otherId}, groupId: gid),
    );
    final out = writer.write(originalBytes: blank, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = RegExp(r'<Cell N="EventDblClick"[^/]*/>').firstMatch(pageXml);
    if (cell != null) {
      expect(cell.group(0)!.contains('F="Inh"'), isFalse);
    }
  });

  test('multi-run Character/Paragraph rows on rebuild', () {
    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
    ).copyWith(
      richText: VsdxRichText(
        runs: [
          VsdxTextRun(
            text: 'Hi ',
            charStyle: VsdxCharStyle.defaults.copyWith(
              fontSizeInches: 12 / 72,
              style: const VsdxFontStyle(bold: true),
            ),
          ),
          VsdxTextRun(
            text: 'there',
            charStyle: VsdxCharStyle.defaults.copyWith(
              fontSizeInches: 10 / 72,
              style: const VsdxFontStyle(italic: true),
            ),
          ),
        ],
      ),
    );
    outDoc = outDoc.replacePage(0, outDoc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('IX="0"'), isTrue);
    expect(pageXml.contains('IX="1"'), isTrue);
    expect(pageXml.contains('<cp IX="1"/>') || pageXml.contains("cp IX=\"1\""),
        isTrue);
    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.richText.runs, hasLength(2));
    expect(after.richText.runs[0].charStyle.style.bold, isTrue);
    expect(after.richText.runs[1].charStyle.style.italic, isTrue);
  });

  test('Tabs section + tp IX round-trip', () {
    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 3,
      height: 1,
    ).copyWith(
      richText: const VsdxRichText(
        runs: [
          VsdxTextRun(
            text: 'A\tB\tC',
            tabIndices: [0, 1],
          ),
        ],
        tabSets: [
          VsdxTabSet(
            ix: 0,
            stops: [VsdxTabStop(positionInches: 0.5, alignment: 0)],
          ),
          VsdxTabSet(
            ix: 1,
            stops: [
              VsdxTabStop(positionInches: 1.25, alignment: 1),
              VsdxTabStop(positionInches: 2.0, alignment: 2),
            ],
          ),
        ],
      ),
    );
    outDoc = outDoc.replacePage(0, outDoc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="Tabs"'), isTrue);
    expect(pageXml.contains('N="Position1"'), isTrue);
    expect(pageXml.contains('N="Alignment1"'), isTrue);
    expect(pageXml.contains('<tp IX="0"/>') || pageXml.contains('tp IX="0"'),
        isTrue);
    expect(pageXml.contains('<tp IX="1"/>') || pageXml.contains('tp IX="1"'),
        isTrue);
    expect('\t'.allMatches(pageXml), hasLength(2));
    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.richText.tabSets, hasLength(2));
    expect(after.richText.tabSets[1].stops, hasLength(2));
    expect(
        after.richText.tabSets[1].stops[0].positionInches, closeTo(1.25, 1e-6));
    expect(after.richText.runs.first.tabIndices, [0, 1]);
  });

  test('themeColorIndex writes THEMEVAL on rebuild', () {
    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(
      fill: const VsdxFill(themeForegroundIndex: 3, pattern: 1),
      line: const VsdxLine(themeColorIndex: 2),
      richText: VsdxRichText(
        runs: [
          VsdxTextRun(
            text: 'T',
            charStyle: VsdxCharStyle.defaults.copyWith(themeColorIndex: 1),
          ),
        ],
      ),
    );
    outDoc = outDoc.replacePage(0, outDoc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('F="THEMEVAL()"'), isTrue);
    expect(pageXml.contains('N="QuickStyleFillColor" V="3"'), isTrue);
    expect(pageXml.contains('N="QuickStyleLineColor" V="2"'), isTrue);
    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.fill.themeForegroundIndex, 3);
    expect(after.line.themeColorIndex, 2);
    expect(after.richText.runs.first.charStyle.themeColorIndex, 1,
        reason: 'fresh Character emit must cache theme slot in Color V');
  });

  test('unbound Character Color clears THEMEVAL on patch', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          richText: VsdxRichText(
            runs: [
              VsdxTextRun(
                text: 'Hi',
                charStyle: VsdxCharStyle.defaults.copyWith(themeColorIndex: 3),
              ),
            ],
          ),
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    expect(
      doc.pages.first
          .findShapeById(id)!
          .richText
          .runs
          .first
          .charStyle
          .themeColorIndex,
      3,
    );
    // Clear colour + theme (pasteStyle / default inheritance path).
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          richText: VsdxRichText(
            runs: [
              VsdxTextRun(
                text: 'Hi',
                charStyle: VsdxCharStyle.defaults.copyWith(
                  clearThemeColorIndex: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(r'N="Color"[^>]*F="THEMEVAL').hasMatch(pageXml),
      isFalse,
      reason: 'unbound text colour must not keep Character Color THEMEVAL',
    );
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.richText.runs.first.charStyle.themeColorIndex, isNull);
    expect(after.richText.runs.first.charStyle.color, isNull);
  });

  test('Reflection Dist/Blur F=Inh scrub when reflection disabled', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.2,
            distanceInches: 0.05,
            blurInches: 0.04,
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="ReflectionSize"[^/]*/>'),
      '<Cell N="ReflectionSize" V="0.2" F="Inh"/>',
    );
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="ReflectionDist"[^/]*/>'),
      '<Cell N="ReflectionDist" V="0.05" F="Inh"/>',
    );
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="ReflectionBlur"[^/]*/>'),
      '<Cell N="ReflectionBlur" V="0.04" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(id)!.reflection.enabled, isFalse);
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final size = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) =>
              e.name.local == 'Cell' && e.getAttribute('N') == 'ReflectionSize',
        );
    expect(size.getAttribute('V'), '0');
    expect(size.getAttribute('F'), isNull);
    for (final name in ['ReflectionDist', 'ReflectionBlur']) {
      final cell = XmlDocument.parse(outXml)
          .descendants
          .whereType<XmlElement>()
          .firstWhere(
            (e) => e.name.local == 'Cell' && e.getAttribute('N') == name,
          );
      expect(cell.getAttribute('F'), isNull, reason: name);
      // Companions keep model values (Inh→null→defaults), not forced zeros.
      final v = double.parse(cell.getAttribute('V')!);
      expect(v, greaterThanOrEqualTo(0), reason: name);
    }
  });

  test('disabled reflection keeps Dist/Blur through save → reopen', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.4,
            distanceInches: 0.12,
            blurInches: 0.07,
            transparency: 0.45,
          ),
        ),
      ),
    );
    var bytes = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(bytes);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          reflection: s.reflection.copyWith(enabled: false),
        ),
      ),
    );
    bytes = writer.write(originalBytes: bytes, edited: doc);
    final after = parser.parse(bytes).pages.first.findShapeById(id)!;
    expect(after.reflection.enabled, isFalse);
    expect(after.reflection.distanceInches, closeTo(0.12, 1e-6));
    expect(after.reflection.blurInches, closeTo(0.07, 1e-6));
    expect(after.reflection.transparency, closeTo(0.45, 1e-6));
    // Size stays available for toggle-on (controller restores when ≤0).
    expect(after.reflection.sizeInches, 0);
  });

  test('CompoundType 0 survives group rebuild', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final a = doc.pages.first.nextFreeShapeId();
    final b = a + 1;
    final gid = b + 1;
    doc = doc.replacePage(
      0,
      doc.pages.first
          .addShape(
            VsdxShapeFactory.rectangle(
              id: a,
              pinX: 1,
              pinY: 1,
              width: 1,
              height: 1,
            ).copyWith(line: const VsdxLine(compoundType: 1)),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: b,
              pinX: 3,
              pinY: 1,
              width: 1,
              height: 1,
            ),
          ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        a,
        (s) => s.copyWith(line: s.line.copyWith(compoundType: 0)),
      ),
    );
    doc = doc.replacePage(
      0,
      doc.pages.first.group({a, b}, groupId: gid),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="CompoundType" V="0"'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(a)!;
    expect(after.line.compoundType, 0);
  });

  test('Visio XDyn/XCon/CanGlue Control round-trip', () {
    final bytes = _fixture('test9_rect_and_line.vsdx');
    final doc = parser.parse(bytes);
    VsdxShape? withCtrl;
    void walk(VsdxShape s) {
      if (s.controls.isNotEmpty && s.controls.any((c) => c.useVisioDynNames)) {
        withCtrl ??= s;
      }
      for (final c in s.children) {
        walk(c);
      }
    }

    for (final s in doc.pages.first.shapes) {
      walk(s);
    }
    expect(withCtrl, isNotNull);
    final found = withCtrl!.controls.firstWhere((c) => c.useVisioDynNames);
    expect(found.dynXFormula, isNotNull);

    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(controls: [found]);
    outDoc = outDoc.replacePage(0, outDoc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="XDyn"'), isTrue);
    expect(pageXml.contains('N="XCon"'), isTrue);
    expect(pageXml.contains('N="CanGlue"'), isTrue);
    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.controls.single.useVisioDynNames, isTrue);
    expect(after.controls.single.dynXFormula, found.dynXFormula);
    expect(after.controls.single.conXFormula, found.conXFormula);
  });

  test('Property SortKey/Invisible + User Value F= round-trip', () {
    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(
      userProperties: const [
        VsdxUserProperty(
          name: 'Cost',
          label: 'Cost',
          value: '42',
          type: 2,
          sortKey: '01',
          invisible: true,
          verify: true,
          langId: 'en-US',
          calendar: 0,
        ),
      ],
      userCells: const [
        VsdxUserCell(
          name: 'Half',
          value: '1',
          valueFormula: 'Width/2',
        ),
      ],
    );
    outDoc = outDoc.replacePage(0, outDoc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="SortKey"'), isTrue);
    expect(pageXml.contains('N="Invisible" V="1"'), isTrue);
    expect(pageXml.contains('F="Width/2"'), isTrue);
    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.userProperties.single.sortKey, '01');
    expect(after.userProperties.single.invisible, isTrue);
    expect(after.userCells.single.valueFormula, 'Width/2');
  });

  test('SoftEdgesSize + CompoundType round-trip', () {
    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(
      line: const VsdxLine(
        softEdgesInches: 0.05,
        compoundType: 1,
        roundingInches: 0.1,
      ),
    );
    outDoc = outDoc.replacePage(0, outDoc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="SoftEdgesSize"'), isTrue);
    expect(pageXml.contains('N="CompoundType" V="0"'), isTrue);
    expect(
      '<Section N="Geometry"'.allMatches(pageXml).length,
      2,
      reason: 'source box + SoftEdges plate; compound rails live in the PNG',
    );
    final afterDoc = parser.parse(saved);
    final after = afterDoc.pages.first.findShapeById(id)!;
    expect(after.line.softEdgesInches, closeTo(0, 1e-6),
        reason: 'SoftEdgesSize is not a token; the halo is a PNG sibling');
    expect(after.fill.pattern, 0);
    expect(
      afterDoc.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
    );
    expect(after.line.compoundType, 0);
    expect(after.line.pattern, 0);
  });

  test('SoftEdgesSize + LineGradient round-trip', () {
    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    const wash = VsdxGradient(
      stops: <VsdxGradientStop>[
        VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
        VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
      ],
    );
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
      fill: const VsdxFill(pattern: 0),
    ).copyWith(
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.08,
        softEdgesInches: 0.05,
        gradient: wash,
      ),
    );
    outDoc = outDoc.replacePage(0, outDoc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="SoftEdgesSize"'), isTrue);
    expect(
      '<Section N="Geometry"'.allMatches(pageXml).length,
      2,
      reason: 'source box + SoftEdges plate; LineGradient lives in the PNG',
    );
    final afterDoc = parser.parse(saved);
    final after = afterDoc.pages.first.findShapeById(id)!;
    expect(after.line.softEdgesInches, closeTo(0, 1e-6),
        reason: 'SoftEdgesSize is not a token; the halo is a PNG sibling');
    expect(after.line.pattern, 0);
    expect(after.line.hasGradient, isFalse);
    expect(
      afterDoc.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
    );
  });

  test('expanded Lock* cells written when locked', () {
    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 1,
      height: 1,
    ).copyWith(locked: true);
    outDoc = outDoc.replacePage(0, outDoc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="LockGroup"'), isTrue);
    expect(pageXml.contains('N="LockCalcWH"'), isTrue);
    expect(pageXml.contains('N="LockVtxEdit"'), isTrue);
    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.locked, isTrue);
  });

  test('Connection X/Y formulas survive rebuild', () {
    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
    ).copyWith(
      connectionPoints: const [
        VsdxConnectionPoint(
          0,
          0.5,
          xFormula: 'Width*0',
          yFormula: 'Height*0.5',
        ),
        VsdxConnectionPoint(
          2,
          0.5,
          xFormula: 'Width*1',
          yFormula: 'Height*0.5',
        ),
      ],
    );
    outDoc = outDoc.replacePage(0, outDoc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('F="Width*0"'), isTrue);
    expect(pageXml.contains('F="Height*0.5"'), isTrue);
    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.connectionPoints.first.xFormula, 'Width*0');
    expect(after.connectionPoints.first.yFormula, 'Height*0.5');
  });

  test('connector XForm PAR(PNT) + BegTrigger round-trip on rebuild', () {
    final bytes = _fixture('workflow.vsdx');
    final doc = parser.parse(bytes);
    final connectors = doc.pages.first.shapes
        .where((s) =>
            s.is1D &&
            s.formulas.containsKey('BeginX') &&
            s.formulas['BeginX']!.contains('PAR(PNT'))
        .toList();
    expect(connectors, isNotEmpty);
    final src = connectors.first;

    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    final clone = src.copyWith(
      id: id,
      children: const [],
      // Keep formulas / connector props / 1-D endpoints.
    );
    outDoc = outDoc.replacePage(0, outDoc.pages.first.addShape(clone));
    final saved = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('PAR(PNT'), isTrue);
    expect(pageXml.contains('N="BegTrigger"'), isTrue);
    expect(pageXml.contains('_XFTRIGGER'), isTrue);
    expect(pageXml.contains('N="GlueType"'), isTrue);
    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.formulas['BeginX'], src.formulas['BeginX']);
    expect(after.formulas['PinX'], src.formulas['PinX']);
    expect(after.formulas['BegTrigger'], src.formulas['BegTrigger']);
    expect(after.connectorProps?.glueType, src.connectorProps?.glueType);
  });

  test('detach clears PAR(PNT) and XFTRIGGER from saved page XML', () {
    final bytes = _fixture('workflow.vsdx');
    final doc = parser.parse(bytes);
    final page0 = doc.pages.first;
    final connector = page0.shapes.firstWhere(
      (s) =>
          s.is1D &&
          (s.formulas['BeginX']?.contains('PAR(PNT') ?? false) &&
          s.formulas.containsKey('BegTrigger'),
    );
    final beginGlue = page0.connects.firstWhere(
      (c) => c.fromSheetId == connector.id && c.isBegin,
    );
    final editedPage = page0.setConnectorEndpoint(
      connector.id,
      begin: true,
      targetShapeId: null,
      x: connector.beginX ?? connector.pinX,
      y: connector.beginY ?? connector.pinY,
    );
    final editedConn = editedPage.findShapeById(connector.id)!;
    expect(editedConn.formulas.containsKey('BegTrigger'), isFalse);
    expect(editedConn.formulas['BeginX'] ?? '', isNot(contains('PAR(PNT')));

    final saved = writer.write(
      originalBytes: bytes,
      edited: doc.replacePage(0, editedPage),
    );
    final after = parser.parse(saved).pages.first.findShapeById(connector.id)!;
    expect(after.formulas.containsKey('BegTrigger'), isFalse);
    expect(after.formulas['BeginX'] ?? '', isNot(contains('PAR(PNT')));
    expect(
      after.formulas.values
          .any((f) => f.contains('Sheet.${beginGlue.toSheetId}!')),
      isFalse,
    );
  });

  test('delete glue target clears EndTrigger F= on save', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final a = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 1,
      pinY: 2,
      width: 1,
      height: 1,
    );
    final b = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 4,
      pinY: 2,
      width: 1,
      height: 1,
    );
    final conn =
        VsdxShapeFactory.line(id: 3, ax: 1, ay: 2, bx: 4, by: 2).copyWith(
      formulas: const <String, String>{
        'BegTrigger': '_XFTRIGGER(Sheet.1!EventXFMod)',
        'EndTrigger': '_XFTRIGGER(Sheet.2!EventXFMod)',
        'BeginX': 'PAR(PNT(Sheet.1!Connections.X1,Sheet.1!Connections.Y1))',
        'EndX': 'PAR(PNT(Sheet.2!Connections.X1,Sheet.2!Connections.Y1))',
      },
    );
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        shapes: <VsdxShape>[a, b, conn],
        connects: const <VsdxConnect>[
          VsdxConnect(
            fromSheetId: 3,
            fromCell: 'BeginX',
            fromPart: 9,
            toSheetId: 1,
            toCell: 'PinX',
            toPart: 3,
          ),
          VsdxConnect(
            fromSheetId: 3,
            fromCell: 'EndX',
            fromPart: 12,
            toSheetId: 2,
            toCell: 'PinX',
            toPart: 3,
          ),
        ],
      ),
    );
    final withGlue = writer.write(originalBytes: blank, edited: doc);
    var mid = parser.parse(withGlue);
    mid = mid.replacePage(0, mid.pages.first.removeShapeById(2));
    final saved = writer.write(originalBytes: withGlue, edited: mid);
    final after = parser.parse(saved).pages.first.findShapeById(3)!;
    expect(after.formulas.containsKey('EndTrigger'), isFalse);
    expect(after.formulas['EndX'] ?? '', isNot(contains('Sheet.2!')));
    expect(after.formulas['BegTrigger'], contains('Sheet.1!'));
  });

  test('ShdwPattern alias round-trips with ShadowPattern', () {
    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(
      shadow: const VsdxShadow(
        enabled: true,
        offsetXInches: 0.1,
        blurInches: 0,
      ),
    );
    outDoc = outDoc.replacePage(0, outDoc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="ShadowPattern"'), isTrue);
    expect(pageXml.contains('N="ShdwPattern"'), isTrue);
    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.shadow.enabled, isTrue);

    // Parser accepts ShdwPattern alone (Lucidchart / Visio alias).
    const style = StyleParser();
    final el = XmlDocument.parse('''
      <Shape ID="1" Type="Shape">
        <Cell N="PinX" V="1"/><Cell N="PinY" V="1"/>
        <Cell N="Width" V="1"/><Cell N="Height" V="1"/>
        <Cell N="ShdwPattern" V="1"/>
        <Cell N="ShadowOffsetX" V="0.1"/>
      </Shape>''').rootElement;
    expect(style.parseShadow(el).enabled, isTrue);
  });

  test('ShadowPattern id > 1 survives export round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          shadow: const VsdxShadow(
            enabled: true,
            pattern: 3,
            offsetXInches: 0.1,
            blurInches: 0,
          ),
        ),
      ),
    );
    final out = writer.write(originalBytes: blank, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="ShadowPattern" V="3"'), isTrue);
    expect(pageXml.contains('N="ShdwPattern" V="3"'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.shadow.enabled, isTrue);
    expect(after.shadow.pattern, 3);
  });

  test('MS FillGradientDir radial/rectangular/path round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(
            pattern: 1,
            gradient: VsdxGradient(
              type: VsdxGradientType.radial,
              dir: 4,
              stops: [
                VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
                VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
              ],
            ),
          ),
        ),
      ),
    );
    var out = writer.write(originalBytes: blank, edited: doc);
    var pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="FillGradientDir" V="4"'), isTrue);
    expect(pageXml.contains('N="FillGradientDir" V="35"'), isFalse);
    var after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.fill.gradient!.type, VsdxGradientType.radial);
    expect(after.fill.gradient!.dir, 4);

    // Rectangular origin preset 9 and path 13.
    doc = parser.parse(out);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          fill: s.fill.copyWith(
            gradient: VsdxGradient(
              type: VsdxGradientType.rectangular,
              dir: 9,
              stops: s.fill.gradient!.stops,
            ),
          ),
        ),
      ),
    );
    out = writer.write(originalBytes: out, edited: doc);
    after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.fill.gradient!.type, VsdxGradientType.rectangular);
    expect(after.fill.gradient!.dir, 9);

    doc = parser.parse(out);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          fill: s.fill.copyWith(
            gradient: VsdxGradient(
              type: VsdxGradientType.path,
              dir: 13,
              stops: s.fill.gradient!.stops,
            ),
          ),
        ),
      ),
    );
    out = writer.write(originalBytes: out, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="FillGradientDir" V="13"'), isTrue);
    after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.fill.gradient!.type, VsdxGradientType.path);
    expect(after.fill.gradient!.dir, 13);
  });

  test('legacy FillGradientDir 35 still parses as radial', () {
    const style = StyleParser();
    final el = XmlDocument.parse('''
      <Shape ID="1" Type="Shape">
        <Cell N="FillGradientEnabled" V="1"/>
        <Cell N="FillGradientDir" V="35"/>
        <Cell N="FillGradientAngle" V="0"/>
        <Section N="FillGradient">
          <Row IX="0">
            <Cell N="GradientStopPosition" V="0"/>
            <Cell N="GradientStopColor" V="#FF0000"/>
          </Row>
          <Row IX="1">
            <Cell N="GradientStopPosition" V="1"/>
            <Cell N="GradientStopColor" V="#0000FF"/>
          </Row>
        </Section>
      </Shape>''').rootElement;
    final fill = style.parseFill(el);
    expect(fill.gradient, isNotNull);
    expect(fill.gradient!.type, VsdxGradientType.radial);
    expect(fill.gradient!.dir, 35);
  });

  test('SpLine=0 solid writes V="0" not omitted', () {
    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(
      richText: VsdxRichText(
        runs: [
          VsdxTextRun(
            text: 'solid',
            paraStyle: VsdxParaStyle.defaults.copyWith(lineSpacingSolid: true),
          ),
        ],
      ),
    );
    outDoc = outDoc.replacePage(0, outDoc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="SpLine" V="0"'), isTrue);
    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.richText.runs.first.paraStyle.lineSpacingSolid, isTrue);
  });

  test('Txt* SETATREF / TEXTWIDTH formulas survive group rebuild', () {
    final bytes = _fixture('test5_master.vsdx');
    final doc = parser.parse(bytes);
    final src = doc.pages.first.shapes.firstWhere(
      (s) =>
          s.formulas['TxtPinX']?.contains('SETATREF') == true &&
          s.formulas.containsKey('TxtWidth'),
    );
    expect(
        src.formulas['TxtPinX'], contains('SETATREF(Controls.TextPosition)'));

    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    outDoc = outDoc.replacePage(
      0,
      outDoc.pages.first.addShape(src.copyWith(id: id, children: const [])),
    );
    final saved = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('SETATREF(Controls.TextPosition)'), isTrue);
    expect(
        pageXml.contains('TEXTWIDTH(TheText)') || pageXml.contains('TxtWidth'),
        isTrue);
    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.formulas['TxtPinX'], src.formulas['TxtPinX']);
    expect(after.formulas['TxtPinY'], src.formulas['TxtPinY']);
    expect(after.formulas['TxtWidth'], src.formulas['TxtWidth']);
  });

  test('Geometry Scratch.X1 / Width* formulas survive group rebuild', () {
    final bytes = _fixture('workflow.vsdx');
    final doc = parser.parse(bytes);
    final src = doc.pages.first.shapes.firstWhere((s) {
      for (final g in s.geometries) {
        for (var i = 0; i < g.commands.length; i++) {
          final f = g.formulasAt(i)['X'];
          if (f != null && f.contains('Scratch.X1')) return true;
        }
      }
      return false;
    });
    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    outDoc = outDoc.replacePage(
      0,
      outDoc.pages.first.addShape(src.copyWith(id: id, children: const [])),
    );
    final saved = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('F="Scratch.X1"'), isTrue);
    expect(pageXml.contains('F="Width*0') || pageXml.contains('F="Width-'),
        isTrue);
    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    var found = false;
    for (final g in after.geometries) {
      for (var i = 0; i < g.commands.length; i++) {
        if (g.formulasAt(i)['X']?.contains('Scratch.X1') == true) {
          found = true;
        }
      }
    }
    expect(found, isTrue);
  });

  test('Scratch C/D cells round-trip on rebuild', () {
    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(
      scratch: const [
        VsdxScratchRow(
          ix: 0,
          x: 0.25,
          y: 0,
          a: 0,
          b: 0,
          c: 0.1,
          d: 0.2,
          xFormula: 'MIN(Height/2,Width/2)',
          cFormula: 'Width*0.05',
          dFormula: 'Height*0.1',
        ),
      ],
    );
    outDoc = outDoc.replacePage(0, outDoc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="C"'), isTrue);
    expect(pageXml.contains('N="D"'), isTrue);
    expect(pageXml.contains('F="Width*0.05"'), isTrue);
    expect(pageXml.contains('F="Height*0.1"'), isTrue);
    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.scratch.single.c, closeTo(0.1, 1e-6));
    expect(after.scratch.single.d, closeTo(0.2, 1e-6));
    expect(after.scratch.single.cFormula, 'Width*0.05');
    expect(after.scratch.single.dFormula, 'Height*0.1');
  });

  test('ForeignType EnhMetaFile + CompressionType round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    const part = '/visio/media/image_emf_test.emf';
    final payload = Uint8List.fromList(<int>[0x01, 0x00, 0x00, 0x00, 0xEE]);
    final pic = VsdxShapeFactory.picture(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 1,
      height: 1,
      imagePartName: part,
    ).copyWith(
      foreignType: 'EnhMetaFile',
    );
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(
              partName: part,
              bytes: payload,
              mimeType: 'image/x-emf',
            ),
          ),
        )
        .replacePage(0, doc.pages.first.addShape(pic));
    final out = writer.write(originalBytes: blank, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('ForeignType="EnhMetaFile"'), isTrue);
    expect(pageXml.contains('ForeignType="Bitmap"'), isFalse);
    final reopened = parser.parse(out);
    final after = reopened.pages.first.findShapeById(id)!;
    expect(after.foreignType, 'EnhMetaFile');
    expect(after.hasImage, isTrue);
    expect(
      reopened.images.findByPart(after.imagePartName!)!.bytes,
      payload,
      reason: 'EMF ForeignData bytes must survive VSDX write and reopen',
    );
  });

  test('ForeignType Bitmap writes CompressionType=PNG', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    const part = '/visio/media/image_png_test.png';
    final pic = VsdxShapeFactory.picture(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 1,
      height: 1,
      imagePartName: part,
    );
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(
              partName: part,
              bytes: Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]),
              mimeType: 'image/png',
            ),
          ),
        )
        .replacePage(0, doc.pages.first.addShape(pic));
    final out = writer.write(originalBytes: blank, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('ForeignType="Bitmap"'), isTrue);
    expect(pageXml.contains('CompressionType="PNG"'), isTrue);
  });

  test('ObjType / EventDblClick / NoAlignBox survive brand-new rebuild', () {
    final bytes = _fixture('workflow.vsdx');
    final doc = parser.parse(bytes);
    final src = doc.pages.first.shapes.firstWhere(
      (s) =>
          s.objType != null &&
          s.formulas.containsKey('EventDblClick') &&
          s.noAlignBox,
    );
    final blank = writer.emptyDocument();
    var outDoc = parser.parse(blank);
    final id = outDoc.pages.first.nextFreeShapeId();
    outDoc = outDoc.replacePage(
      0,
      outDoc.pages.first.addShape(src.copyWith(id: id, children: const [])),
    );
    final saved = writer.write(originalBytes: blank, edited: outDoc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(saved)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="ObjType"'), isTrue);
    expect(pageXml.contains('OPENTEXTWIN()'), isTrue);
    expect(pageXml.contains('N="NoAlignBox"'), isTrue);
    expect(pageXml.contains('N="ShapeSplittable"'), isTrue);
    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.objType, src.objType);
    expect(after.formulas['EventDblClick'], src.formulas['EventDblClick']);
    expect(after.noAlignBox, isTrue);
    expect(after.shapeSplittable, isTrue);
  });

  test('LockTheme* cells written when shape is locked', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(locked: true);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final out = writer.write(originalBytes: blank, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="LockThemeColors"'), isTrue);
    expect(pageXml.contains('N="LockThemeFonts"'), isTrue);
    expect(pageXml.contains('N="LockCustProp"'), isTrue);
  });

  test('FillGradient theme palette index stop round-trips', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(
      fill: VsdxFill(
        pattern: 1,
        gradient: VsdxGradient(
          type: VsdxGradientType.linear,
          angleRad: 0,
          stops: const [
            VsdxGradientStop(position: 0, themeColorIndex: 1),
            VsdxGradientStop(position: 1, themeColorIndex: 4),
          ],
        ),
      ),
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final out = writer.write(originalBytes: blank, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="FillGradient"'), isTrue);
    expect(
      RegExp(r'N="GradientStopColor"[^>]*F="THEMEVAL').hasMatch(pageXml) ||
          RegExp(r'F="THEMEVAL\(\)"[^>]*N="GradientStopColor"')
              .hasMatch(pageXml),
      isTrue,
      reason:
          'theme gradient stops must bind via THEMEVAL like Character Color',
    );
    expect(
        pageXml.contains('N="GradientStopColor" V="1"') ||
            pageXml.contains('V="1" N="GradientStopColor"'),
        isTrue);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.fill.gradient, isNotNull);
    expect(after.fill.gradient!.stops.first.themeColorIndex, 1);
    expect(after.fill.gradient!.stops.last.themeColorIndex, 4);
  });

  test('LineGradient theme palette index stop round-trips', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(
      line: const VsdxLine(
        weightInches: 0.04,
        gradient: VsdxGradient(
          type: VsdxGradientType.linear,
          angleRad: 0,
          stops: [
            VsdxGradientStop(position: 0, themeColorIndex: 2),
            VsdxGradientStop(position: 1, themeColorIndex: 5),
          ],
        ),
      ),
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final out = writer.write(originalBytes: blank, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="LineGradient"'), isTrue);
    expect(
      RegExp(r'N="GradientStopColor"[^>]*F="THEMEVAL').hasMatch(pageXml) ||
          RegExp(r'F="THEMEVAL\(\)"[^>]*N="GradientStopColor"')
              .hasMatch(pageXml),
      isTrue,
    );
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.line.gradient!.stops.first.themeColorIndex, 2);
    expect(after.line.gradient!.stops.last.themeColorIndex, 5);
  });

  test('MS LineGradientDir radial round-trips', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          line: const VsdxLine(
            weightInches: 0.05,
            gradient: VsdxGradient(
              type: VsdxGradientType.radial,
              dir: 4,
              stops: [
                VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
                VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
              ],
            ),
          ),
        ),
      ),
    );
    final out = writer.write(originalBytes: blank, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="LineGradientDir" V="4"'), isTrue);
    expect(pageXml.contains('N="LineGradientDir" V="35"'), isFalse);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.line.gradient!.type, VsdxGradientType.radial);
    expect(after.line.gradient!.dir, 4);
  });

  test('glow colour edited then disabled survives single save', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    // Baseline: plain rectangle with no GlowColor cell.
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    // Enable + set colour + disable in one edit before the only save.
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          glow: const VsdxGlow(
            enabled: false,
            color: VsdxColor(0xFF00BCD4),
            sizeInches: 0,
            transparency: 0.35,
          ),
        ),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.glow.enabled, isFalse);
    expect(after.glow.color?.value, 0xFF00BCD4,
        reason: 'patch must inject GlowColor on disable→save');
    expect(after.glow.transparency, closeTo(0.35, 1e-6));
  });

  test('reflection Dist edited then disabled survives single save', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          reflection: const VsdxReflection(
            enabled: false,
            sizeInches: 0,
            distanceInches: 0.14,
            blurInches: 0.09,
            transparency: 0.4,
          ),
        ),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.reflection.enabled, isFalse);
    expect(after.reflection.distanceInches, closeTo(0.14, 1e-6));
    expect(after.reflection.blurInches, closeTo(0.09, 1e-6));
  });

  test('SoftEdgesSize F=Inh scrubs to literal 0 when model is zero', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(line: const VsdxLine(softEdgesInches: 0.08)),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="SoftEdgesSize"[^/]*/>'),
      '<Cell N="SoftEdgesSize" V="0.08" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    // Parser maps Inh→0; model stays 0 — still must scrub F=Inh on write.
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(id)!.line.softEdgesInches, 0);
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final soft = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) =>
              e.name.local == 'Cell' && e.getAttribute('N') == 'SoftEdgesSize',
        );
    expect(soft.getAttribute('V'), '0');
    expect(soft.getAttribute('F'), isNull);
  });

  test('Rounding V= F=Inh inherits zero default (not stale V)', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(line: const VsdxLine(roundingInches: 0.15)),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="Rounding"[^/]*/>'),
      '<Cell N="Rounding" V="0.15" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    // No master/stylesheet Rounding → Inh resolves to 0 (SoftEdges-style).
    expect(doc.pages.first.findShapeById(id)!.line.roundingInches,
        closeTo(0.0, 1e-9));
  });

  test('Rounding F=Inh inherits Master radius', () {
    const style = StyleParser();
    final line = style.parseLine(
      XmlDocument.parse(
        '<Shape><Cell N="Rounding" V="0" F="Inh"/></Shape>',
      ).rootElement,
      defaults: const VsdxLine(roundingInches: 0.25),
    );
    expect(line.roundingInches, closeTo(0.25, 1e-9));
  });

  test('ReflectionDist/Blur F=Inh keep cached V while reflection stays on', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.4,
            distanceInches: 0.12,
            blurInches: 0.08,
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="ReflectionDist"[^/]*/>'),
      '<Cell N="ReflectionDist" V="0.12" F="Inh"/>',
    );
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="ReflectionBlur"[^/]*/>'),
      '<Cell N="ReflectionBlur" V="0.08" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    final midShape = doc.pages.first.findShapeById(id)!;
    expect(midShape.reflection.enabled, isFalse,
        reason: 'Reflection* is not a token; Size is baked to 0');
    expect(midShape.reflection.distanceInches, closeTo(0.12, 1e-6));
    expect(midShape.reflection.blurInches, closeTo(0.08, 1e-6));
    expect(
      doc.pages.first.shapes.where(isLibvisioReflectionPlate),
      hasLength(1),
    );
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.reflection.distanceInches, closeTo(0.12, 1e-6));
    expect(after.reflection.blurInches, closeTo(0.08, 1e-6));
  });

  test('ShadowBlur cell is literal 0 on the source after bake', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          shadow: const VsdxShadow(
            enabled: true,
            blurInches: 0.09,
            offsetXInches: 0.15,
            offsetYInches: 0.1,
          ),
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    expect(
        parser.parse(mid).pages.first.findShapeById(id)!.shadow.blurInches, 0);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(mid)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final source = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) =>
              e.name.local == 'Shape' && e.getAttribute('ID') == id.toString(),
        );
    final blur = source.childElements.firstWhere(
      (e) => e.name.local == 'Cell' && e.getAttribute('N') == 'ShadowBlur',
    );
    expect(blur.getAttribute('V'), '0');
    expect(blur.getAttribute('F'), isNull);
  });

  test('GlowSize F=Inh scrubs to literal 0 when glow disabled', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          glow: const VsdxGlow(
            enabled: true,
            sizeInches: 0.1,
            transparency: 0.2,
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="GlowSize"[^/]*/>'),
      '<Cell N="GlowSize" V="0.1" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    // Inh → disabled model; write must still scrub F=.
    expect(doc.pages.first.findShapeById(id)!.glow.enabled, isFalse);
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final glow = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) => e.name.local == 'Cell' && e.getAttribute('N') == 'GlowSize',
        );
    expect(glow.getAttribute('V'), '0');
    expect(glow.getAttribute('F'), isNull);
  });

  test('FillGradientEnabled V=0 F=Inh scrubs when model has no gradient', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      '</Shape>',
      '<Cell N="FillGradientEnabled" V="0" F="Inh"/></Shape>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(id)!.fill.gradient, isNull);
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) =>
              e.name.local == 'Cell' &&
              e.getAttribute('N') == 'FillGradientEnabled',
        );
    expect(cell.getAttribute('V'), '0');
    expect(cell.getAttribute('F'), isNull);
  });

  test('LineGradientEnabled V=0 F=Inh scrubs when model has no gradient', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      '</Shape>',
      '<Cell N="LineGradientEnabled" V="0" F="Inh"/></Shape>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(id)!.line.gradient, isNull);
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) =>
              e.name.local == 'Cell' &&
              e.getAttribute('N') == 'LineGradientEnabled',
        );
    expect(cell.getAttribute('V'), '0');
    expect(cell.getAttribute('F'), isNull);
  });

  test('FillGradientEnabled V=1 F=Inh scrubs while gradient stays on', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
          fill: const VsdxFill(
            pattern: 1,
            gradient: VsdxGradient(
              type: VsdxGradientType.linear,
              stops: [
                VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
                VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
              ],
            ),
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      'N="FillGradientEnabled" V="1"',
      'N="FillGradientEnabled" V="1" F="Inh"',
    );
    if (!pageXml.contains('FillGradientEnabled" V="1" F="Inh"')) {
      pageXml = pageXml.replaceFirst(
        RegExp(r'<Cell N="FillGradientEnabled"[^/]*/>'),
        '<Cell N="FillGradientEnabled" V="1" F="Inh"/>',
      );
    }
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    // A save of a modern FillGradient also writes classic FillPattern 25–40
    // so LibreOffice still paints a wash. F=Inh on FillGradientEnabled
    // drops the stop section, but the classic id remains.
    expect(doc.pages.first.findShapeById(id)!.fill.hasGradient, isTrue);
    const grad = VsdxGradient(
      type: VsdxGradientType.linear,
      stops: [
        VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
        VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
      ],
    );
    // Re-apply gradient so writer scrubs Enabled Inh while keeping it on.
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(fill: s.fill.withGradient(grad), pinX: s.pinX + 0.25),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) =>
              e.name.local == 'Cell' &&
              e.getAttribute('N') == 'FillGradientEnabled',
        );
    expect(cell.getAttribute('V'), '1');
    expect(cell.getAttribute('F'), isNull);
    expect(parser.parse(out).pages.first.findShapeById(id)!.fill.hasGradient,
        isTrue);
  });

  test('LineGradientEnabled V=1 F=Inh scrubs while gradient stays on', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          line: const VsdxLine(
            weightInches: 0.04,
            gradient: VsdxGradient(
              type: VsdxGradientType.linear,
              stops: [
                VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
                VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
              ],
            ),
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      'N="LineGradientEnabled" V="1"',
      'N="LineGradientEnabled" V="1" F="Inh"',
    );
    if (!pageXml.contains('LineGradientEnabled" V="1" F="Inh"')) {
      pageXml = pageXml.replaceFirst(
        RegExp(r'<Cell N="LineGradientEnabled"[^/]*/>'),
        '<Cell N="LineGradientEnabled" V="1" F="Inh"/>',
      );
    }
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(id)!.line.hasGradient, isFalse);
    const grad = VsdxGradient(
      type: VsdxGradientType.linear,
      stops: [
        VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
        VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
      ],
    );
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(line: s.line.withGradient(grad), pinX: s.pinX + 0.25),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) =>
              e.name.local == 'Cell' &&
              e.getAttribute('N') == 'LineGradientEnabled',
        );
    expect(cell.getAttribute('V'), '1');
    expect(cell.getAttribute('F'), isNull);
  });

  test('ShadowPattern V=1 F=Inh scrubs while shadow stays on', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          shadow: const VsdxShadow(
            enabled: true,
            pattern: 1,
            offsetXInches: 0.12,
            transparency: 0.35,
            blurInches: 0,
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    // Keep Pattern as a literal enable bit; only companions carry F=Inh
    // (Pattern F=Inh without a master resolves to 0 — disabled).
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="ShadowForegndTrans"[^/]*/>'),
      '<Cell N="ShadowForegndTrans" V="0.35" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(id)!.shadow.enabled, isTrue);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.25),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    for (final name in ['ShadowPattern', 'ShdwPattern', 'ShadowForegndTrans']) {
      final cell = XmlDocument.parse(outXml)
          .descendants
          .whereType<XmlElement>()
          .firstWhere(
            (e) => e.name.local == 'Cell' && e.getAttribute('N') == name,
          );
      expect(cell.getAttribute('F'), isNull, reason: name);
      if (name == 'ShadowForegndTrans') {
        expect(double.parse(cell.getAttribute('V')!), closeTo(0, 1e-6),
            reason: 'ShdwForegndTrans is not a token; alpha is baked into RGB');
      } else {
        expect(cell.getAttribute('V'), '1', reason: name);
      }
    }
    expect(parser.parse(out).pages.first.findShapeById(id)!.shadow.enabled,
        isTrue);
  });

  test('Glow/Reflection companion F=Inh scrubs while effects stay on', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          glow: const VsdxGlow(
            enabled: true,
            sizeInches: 0.1,
            transparency: 0.25,
          ),
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.5,
            distanceInches: 0.08,
            transparency: 0.3,
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    // Size cells must stay literal — F=Inh on Size is parsed as disabled
    // (inheritFrom 0). Companions keep V= while F=Inh is the stale-inherit
    // hazard when the effect model is unchanged.
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="GlowColorTrans"[^/]*/>'),
      '<Cell N="GlowColorTrans" V="0.25" F="Inh"/>',
    );
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="ReflectionTransparency"[^/]*/>'),
      '<Cell N="ReflectionTransparency" V="0.3" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    final shape = doc.pages.first.findShapeById(id)!;
    expect(shape.glow.enabled, isFalse,
        reason: 'Glow on a filled stroke bakes a sibling halo');
    expect(shape.reflection.enabled, isFalse,
        reason: 'Reflection* is not a token; Size is baked to 0');
    expect(shape.glow.transparency, closeTo(0.25, 1e-6));
    expect(shape.reflection.transparency, closeTo(0.3, 1e-6));
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.25),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final sourceEl = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) => e.name.local == 'Shape' && e.getAttribute('ID') == '$id',
        );
    for (final entry in {
      'GlowColorTrans': 0.25,
      'ReflectionTransparency': 0.3,
    }.entries) {
      final cell = sourceEl.children.whereType<XmlElement>().firstWhere(
            (e) => e.name.local == 'Cell' && e.getAttribute('N') == entry.key,
          );
      expect(cell.getAttribute('F'), isNull, reason: entry.key);
      expect(double.parse(cell.getAttribute('V')!), closeTo(entry.value, 1e-6),
          reason: entry.key);
    }
  });

  test('FillGradientDir/Angle F=Inh scrub while gradient stays on', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
          fill: const VsdxFill(
            pattern: 1,
            gradient: VsdxGradient(
              type: VsdxGradientType.radial,
              angleRad: 0.75,
              stops: [
                VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
                VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
              ],
            ),
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="FillGradientDir"[^/]*/>'),
      '<Cell N="FillGradientDir" V="4" F="Inh"/>',
    );
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="FillGradientAngle"[^/]*/>'),
      '<Cell N="FillGradientAngle" V="0.75" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    final g = doc.pages.first.findShapeById(id)!.fill.gradient!;
    expect(g.type, VsdxGradientType.radial);
    expect(g.angleRad, closeTo(0.75, 1e-6));
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.25),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final dir = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) =>
              e.name.local == 'Cell' &&
              e.getAttribute('N') == 'FillGradientDir',
        );
    final angle = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) =>
              e.name.local == 'Cell' &&
              e.getAttribute('N') == 'FillGradientAngle',
        );
    expect(dir.getAttribute('V'), '4');
    expect(dir.getAttribute('F'), isNull);
    expect(double.parse(angle.getAttribute('V')!), closeTo(0.75, 1e-6));
    expect(angle.getAttribute('F'), isNull);
  });

  test('Foreign SoftEdges survives group rebuild', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final picId = doc.pages.first.nextFreeShapeId();
    final otherId = picId + 1;
    final gid = otherId + 1;
    const part = '/visio/media/image_soft_group.png';
    final payload = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      1,
      2,
      3,
      4,
    ]);
    final pic = VsdxShapeFactory.picture(
      id: picId,
      pinX: 2,
      pinY: 2,
      width: 1.5,
      height: 1,
      imagePartName: part,
    ).copyWith(
      line: const VsdxLine(softEdgesInches: 0.06, compoundType: 0),
      layerMemberIds: const [0],
      connectionPoints: VsdxPage.defaultConnectionPoints(1.5, 1),
    );
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: payload, mimeType: 'image/png'),
          ),
        )
        .replacePage(
          0,
          doc.pages.first
              .copyWith(
                layers: const [
                  VsdxLayer(id: 0, name: 'Default'),
                ],
              )
              .addShape(pic)
              .addShape(
                VsdxShapeFactory.rectangle(
                  id: otherId,
                  pinX: 4,
                  pinY: 2,
                  width: 1,
                  height: 1,
                ),
              ),
        );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    expect(
      doc.pages.first.findShapeById(picId)!.line.softEdgesInches,
      closeTo(0.06, 1e-6),
    );
    doc = doc.replacePage(
      0,
      doc.pages.first.group({picId, otherId}, groupId: gid),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="SoftEdgesSize"'), isTrue);
    expect(pageXml.contains('N="CompoundType" V="0"'), isTrue);
    expect(pageXml.contains('N="LayerMember"'), isTrue);
    expect(pageXml.contains('N="Connection"'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(picId)!;
    expect(after.line.softEdgesInches, closeTo(0.06, 1e-6));
    expect(after.line.compoundType, 0);
    expect(after.layerMemberIds, [0]);
    expect(after.connectionPoints, isNotEmpty);
    expect(after.hasImage, isTrue);
  });

  test('ShadowPattern F=Inh scrubs when shadow disabled', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(shadow: const VsdxShadow(enabled: true, blurInches: 0)),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="ShadowPattern"[^/]*/>'),
      '<Cell N="ShadowPattern" V="0" F="Inh"/>',
    );
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="ShdwPattern"[^/]*/>'),
      '<Cell N="ShdwPattern" V="0" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(id)!.shadow.enabled, isFalse);
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    for (final name in ['ShadowPattern', 'ShdwPattern']) {
      final cell = XmlDocument.parse(outXml)
          .descendants
          .whereType<XmlElement>()
          .where(
            (e) => e.name.local == 'Cell' && e.getAttribute('N') == name,
          )
          .firstOrNull;
      if (cell == null) continue;
      expect(cell.getAttribute('V'), '0', reason: name);
      expect(cell.getAttribute('F'), isNull, reason: name);
    }
  });

  test('BeginArrowSize F=Inh scrubs when arrow is set', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(
          id: id,
          ax: 1,
          ay: 1,
          bx: 3,
          by: 1,
        ).copyWith(
          line: const VsdxLine(
            beginArrow: 4,
            beginArrowSizeInches: 0.125,
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="BeginArrowSize"[^/]*/>'),
      '<Cell N="BeginArrowSize" V="2" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) =>
              e.name.local == 'Cell' && e.getAttribute('N') == 'BeginArrowSize',
        );
    expect(cell.getAttribute('V'), '2');
    expect(cell.getAttribute('F'), isNull);
  });

  test('VerticalAlign F=Inh scrubs to literal model value', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(text: 'Hi'),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    if (pageXml.contains('N="VerticalAlign"')) {
      pageXml = pageXml.replaceFirst(
        RegExp(r'<Cell N="VerticalAlign"[^/]*/>'),
        '<Cell N="VerticalAlign" V="1" F="Inh"/>',
      );
    } else {
      pageXml = pageXml.replaceFirst(
        '</Shape>',
        '<Cell N="VerticalAlign" V="1" F="Inh"/></Shape>',
      );
    }
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) =>
              e.name.local == 'Cell' && e.getAttribute('N') == 'VerticalAlign',
        );
    expect(cell.getAttribute('F'), isNull);
  });

  test('hyperlink ExtraInfo clears on patch when set to null', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(hyperlinks: const [
          VsdxHyperlink(
            id: 0,
            address: 'https://example.com',
            extraInfo: 'keep-me',
            isDefault: true,
          ),
        ]),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    expect(
      utf8.decode(
        ZipDecoder()
            .decodeBytes(mid)
            .firstWhere((f) => f.name.contains('pages/page1.xml'))
            .content as List<int>,
      ),
      contains('ExtraInfo'),
    );
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(hyperlinks: [
          VsdxHyperlink(
            id: s.hyperlinks.first.id,
            address: s.hyperlinks.first.address,
            description: s.hyperlinks.first.description,
            isDefault: s.hyperlinks.first.isDefault,
          ),
        ]),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('ExtraInfo'), isFalse);
    expect(
        parser
            .parse(out)
            .pages
            .first
            .findShapeById(id)!
            .hyperlinks
            .first
            .extraInfo,
        isNull);
  });

  test('clearing FillGradient drops Inh formula on FillGradientEnabled', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final withGrad = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(
      fill: const VsdxFill(
        pattern: 1,
        gradient: VsdxGradient(
          type: VsdxGradientType.linear,
          stops: [
            VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
            VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
          ],
        ),
      ),
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(withGrad));
    final mid = writer.write(originalBytes: blank, edited: doc);

    // Inject F="Inh" on FillGradientEnabled (stylesheet inheritance).
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      'N="FillGradientEnabled" V="1"',
      'N="FillGradientEnabled" V="1" F="Inh"',
    );
    if (!pageXml.contains('F="Inh"')) {
      pageXml = pageXml.replaceFirst(
        RegExp(r'<Cell N="FillGradientEnabled"[^/]*/>'),
        '<Cell N="FillGradientEnabled" V="1" F="Inh"/>',
      );
    }
    final tainted = _rezipWith(
      mid,
      pageFile.name,
      utf8.encode(pageXml),
    );

    doc = parser.parse(tainted);
    final cleared = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(fill: s.fill.withGradient(null)),
      ),
    );
    final out = writer.write(originalBytes: tainted, edited: cleared);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final enabled = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) =>
              e.name.local == 'Cell' &&
              e.getAttribute('N') == 'FillGradientEnabled',
        );
    expect(enabled.getAttribute('V'), '0');
    expect(enabled.getAttribute('F'), isNull,
        reason: 'Inh must not survive clearing the gradient');
    expect(parser.parse(out).pages.first.findShapeById(id)!.fill.hasGradient,
        isFalse);
  });

  test('clearing LineGradient drops Inh formula on LineGradientEnabled', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final withGrad = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(
      line: const VsdxLine(
        weightInches: 0.05,
        gradient: VsdxGradient(
          type: VsdxGradientType.linear,
          stops: [
            VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
            VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
          ],
        ),
      ),
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(withGrad));
    final mid = writer.write(originalBytes: blank, edited: doc);

    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      'N="LineGradientEnabled" V="1"',
      'N="LineGradientEnabled" V="1" F="Inh"',
    );
    if (!pageXml.contains('LineGradientEnabled') ||
        !pageXml.contains('F="Inh"')) {
      pageXml = pageXml.replaceFirst(
        RegExp(r'<Cell N="LineGradientEnabled"[^/]*/>'),
        '<Cell N="LineGradientEnabled" V="1" F="Inh"/>',
      );
    }
    final tainted = _rezipWith(
      mid,
      pageFile.name,
      utf8.encode(pageXml),
    );

    doc = parser.parse(tainted);
    final cleared = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(line: s.line.withGradient(null)),
      ),
    );
    final out = writer.write(originalBytes: tainted, edited: cleared);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final enabled = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) =>
              e.name.local == 'Cell' &&
              e.getAttribute('N') == 'LineGradientEnabled',
        );
    expect(enabled.getAttribute('V'), '0');
    expect(enabled.getAttribute('F'), isNull,
        reason: 'Inh must not survive clearing the line gradient');
    expect(parser.parse(out).pages.first.findShapeById(id)!.line.hasGradient,
        isFalse);
  });

  test('Property Value F= + Ask round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(
      userProperties: const [
        VsdxUserProperty(
          name: 'Cost',
          label: 'Cost',
          value: '1',
          valueFormula: 'Width/2',
          type: 2,
          ask: true,
        ),
      ],
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final out = writer.write(originalBytes: blank, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('F="Width/2"'), isTrue);
    expect(pageXml.contains('N="Ask"'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.userProperties.single.valueFormula, 'Width/2');
    expect(after.userProperties.single.ask, isTrue);
  });

  test('Property Format F= round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(
      userProperties: const [
        VsdxUserProperty(
          name: 'Cost',
          label: 'Cost',
          value: '1.5',
          format: '#,##0.00',
          formatFormula: 'FIELDPICTURE(0)',
          type: 2,
        ),
      ],
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final out = writer.write(originalBytes: blank, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('F="FIELDPICTURE(0)"'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.userProperties.single.formatFormula, 'FIELDPICTURE(0)');
    expect(after.userProperties.single.format, '#,##0.00');
  });

  test('Hyperlink ExtraInfo / Invisible / SortKey round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(
      hyperlinks: const [
        VsdxHyperlink(
          id: 0,
          description: 'Docs',
          address: 'https://example.com',
          addressFormula: 'GUARD("https://example.com")',
          extraInfo: 'q=1',
          invisible: true,
          sortKey: 'a',
          isDefault: true,
        ),
      ],
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final out = writer.write(originalBytes: blank, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="ExtraInfo"'), isTrue);
    expect(pageXml.contains('N="Invisible"'), isTrue);
    expect(pageXml.contains('N="SortKey"'), isTrue);
    expect(
      pageXml.contains('GUARD("https://example.com")') ||
          pageXml.contains('GUARD(&quot;https://example.com&quot;)'),
      isTrue,
    );
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.hyperlinks.single.extraInfo, 'q=1');
    expect(after.hyperlinks.single.invisible, isTrue);
    expect(after.hyperlinks.single.sortKey, 'a');
    expect(after.hyperlinks.single.addressFormula, contains('GUARD'));
  });

  test('ThemeIndex + QuickStyle*Matrix survive rebuild', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(
      themeIndex: 0,
      quickStyleFillMatrix: 100,
      quickStyleLineMatrix: 100,
      quickStyleEffectsMatrix: 100,
      quickStyleFontMatrix: 100,
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final out = writer.write(originalBytes: blank, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="ThemeIndex"'), isTrue);
    expect(pageXml.contains('N="QuickStyleFillMatrix"'), isTrue);
    expect(pageXml.contains('N="QuickStyleFontMatrix"'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.themeIndex, 0);
    expect(after.quickStyleFillMatrix, 100);
    expect(after.quickStyleFontMatrix, 100);
  });

  test('PageSheet scale/shadow/jumps round-trip on new page', () {
    final blank = writer.emptyDocument();
    final doc = parser.parse(blank);
    expect(doc.pages.first.pageSheet.pageScaleUnit, 'PT');
    expect(doc.pages.first.pageSheet.shadowOffsetXInches, closeTo(0.125, 1e-6));

    // Clone workflow PageSheet onto a blank doc page and rebuild.
    final wf = parser.parse(_fixture('workflow.vsdx'));
    final sheet = wf.pages.first.pageSheet;
    expect(sheet.lineJumpCode, isNotNull);
    expect(sheet.pageScaleUnit, 'PT');

    final edited = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        widthInches: 11.9583,
        heightInches: 7.14583,
        pageSheet: sheet,
      ),
    );
    final out = writer.write(originalBytes: blank, edited: edited);
    final pagesXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.endsWith('pages/pages.xml'))
          .content as List<int>,
    );
    expect(pagesXml.contains('N="PageScale"'), isTrue);
    expect(pagesXml.contains('U="PT"'), isTrue);
    expect(pagesXml.contains('N="ShdwOffsetX"'), isTrue);
    expect(pagesXml.contains('N="LineJumpCode"'), isTrue);
    expect(pagesXml.contains('N="DrawingResizeType"'), isTrue);

    final after = parser.parse(out).pages.first;
    expect(after.pageSheet.pageScale, closeTo(sheet.pageScale, 1e-9));
    expect(after.pageSheet.pageScaleUnit, sheet.pageScaleUnit);
    expect(after.pageSheet.shadowOffsetXInches,
        closeTo(sheet.shadowOffsetXInches, 1e-6));
    expect(after.pageSheet.lineJumpCode, sheet.lineJumpCode);
    expect(after.pageSheet.lineJumpStyle, sheet.lineJumpStyle);
    expect(after.pageSheet.drawingResizeType, sheet.drawingResizeType);
    expect(after.pageSheet.pageShapeSplit, sheet.pageShapeSplit);
  });

  test('PageSheet display units patch when scale values stay unchanged', () {
    final blank = writer.emptyDocument();
    final doc = parser.parse(blank);
    final editedSheet = doc.pages.first.pageSheet.copyWith(
      pageScaleUnit: 'IN',
      drawingScaleUnit: 'CM',
    );
    final edited = doc.replacePage(
      0,
      doc.pages.first.copyWith(pageSheet: editedSheet),
    );

    final out = writer.write(originalBytes: blank, edited: edited);
    final after = parser.parse(out).pages.first.pageSheet;
    expect(after.pageScale, editedSheet.pageScale);
    expect(after.drawingScale, editedSheet.drawingScale);
    expect(after.pageScaleUnit, 'IN');
    expect(after.drawingScaleUnit, 'CM');
  });

  test('PageSheet VariationColorIndex/StyleIndex round-trip on new page', () {
    final blank = writer.emptyDocument();
    final doc = parser.parse(blank);
    final sheet = doc.pages.first.pageSheet.copyWith(
      variationColorIndex: 3,
      variationStyleIndex: 1,
    );
    final edited =
        doc.replacePage(0, doc.pages.first.copyWith(pageSheet: sheet));
    final out = writer.write(originalBytes: blank, edited: edited);
    final pagesXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.endsWith('pages/pages.xml'))
          .content as List<int>,
    );
    expect(pagesXml.contains('N="VariationColorIndex"'), isTrue);
    expect(pagesXml.contains('N="VariationStyleIndex"'), isTrue);
    final after = parser.parse(out).pages.first;
    expect(after.pageSheet.variationColorIndex, 3);
    expect(after.pageSheet.variationStyleIndex, 1);
  });

  test('Actions section Menu/Action F= round-trip on rebuild', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(
      actions: const [
        VsdxActionRow(
          name: 'Row_1',
          ix: 1,
          menu: 'Open docs',
          action: '0',
          actionFormula: 'RUNADDON("Open")',
          tag: 'docs',
          sortKey: '01',
        ),
      ],
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final out = writer.write(originalBytes: blank, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="Actions"'), isTrue);
    expect(pageXml.contains('N="Menu"'), isTrue);
    expect(
      pageXml.contains('RUNADDON("Open")') ||
          pageXml.contains('RUNADDON(&quot;Open&quot;)'),
      isTrue,
    );
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.actions.single.menu, 'Open docs');
    expect(after.actions.single.actionFormula, contains('RUNADDON'));
    expect(after.actions.single.tag, 'docs');
    expect(after.actions.single.sortKey, '01');
  });

  test('group SelectMode/DisplayMode/IsTextEditTarget round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(
      isTextEditTarget: true,
      dontMoveChildren: true,
      selectMode: 1,
      displayMode: 2,
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final out = writer.write(originalBytes: blank, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="IsTextEditTarget"'), isTrue);
    expect(pageXml.contains('N="DontMoveChildren"'), isTrue);
    expect(pageXml.contains('N="SelectMode"'), isTrue);
    expect(pageXml.contains('N="DisplayMode"'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.isTextEditTarget, isTrue);
    expect(after.dontMoveChildren, isTrue);
    expect(after.selectMode, 1);
    expect(after.displayMode, 2);
  });

  test('connector ConLineRouteExt / jump dirs / ShapePlaceFlip round-trip', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 0.1,
    ).copyWith(
      connectorProps: const VsdxConnectorProps(
        conLineRouteExt: 1,
        conLineJumpStyle: 2,
        conLineJumpDirX: 1,
        conLineJumpDirY: 0,
        shapePlaceFlip: 1,
        shapeRouteStyle: 1,
      ),
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final out = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.connectorProps?.conLineRouteExt, 1);
    expect(after.connectorProps?.conLineJumpStyle, 2);
    expect(after.connectorProps?.conLineJumpDirX, 1);
    expect(after.connectorProps?.conLineJumpDirY, 0);
    expect(after.connectorProps?.shapePlaceFlip, 1);
    expect(after.connectorProps?.shapeRouteStyle, 1);
  });

  test('page ViewScale / ViewCenter* round-trip on new page', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final page = doc.pages.first.copyWith(
      viewScale: 0.75,
      viewCenterX: 4.5,
      viewCenterY: 3.25,
    );
    doc = doc.replacePage(0, page);
    final out = writer.write(originalBytes: blank, edited: doc);
    final pagesXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/pages.xml'))
          .content as List<int>,
    );
    expect(pagesXml.contains('ViewScale='), isTrue);
    expect(pagesXml.contains('ViewCenterX='), isTrue);
    expect(pagesXml.contains('ViewCenterY='), isTrue);
    final after = parser.parse(out).pages.first;
    expect(after.viewScale, closeTo(0.75, 1e-6));
    expect(after.viewCenterX, closeTo(4.5, 1e-6));
    expect(after.viewCenterY, closeTo(3.25, 1e-6));
  });

  test('Layer Snap/Glue/NameUniv/ColorTrans/Status round-trip on new page', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final page = doc.pages.first.copyWith(
      layers: const [
        VsdxLayer(
          id: 0,
          name: 'Foreground',
          nameUniv: 'Foreground',
          snap: false,
          glue: false,
          colorTrans: 0.25,
          status: 1,
        ),
      ],
    );
    doc = doc.replacePage(0, page);
    final out = writer.write(originalBytes: blank, edited: doc);
    final pagesXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/pages.xml'))
          .content as List<int>,
    );
    expect(pagesXml.contains('N="Layer"'), isTrue);
    expect(pagesXml.contains('N="Snap"'), isTrue);
    expect(pagesXml.contains('N="Glue"'), isTrue);
    expect(pagesXml.contains('N="NameUniv"'), isTrue);
    final after = parser.parse(out).pages.first.layers.single;
    expect(after.name, 'Foreground');
    expect(after.nameUniv, 'Foreground');
    expect(after.snap, isFalse);
    expect(after.glue, isFalse);
    expect(after.colorTrans, closeTo(0.25, 1e-6));
    expect(after.status, 1);
  });

  test('theme colours keep THEMEVAL on rebuild; stale pattern formulas scrub',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final id = doc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(
      fill: const VsdxFill(themeForegroundIndex: ThemeSlot.accent1),
      line: const VsdxLine(themeColorIndex: ThemeSlot.accent2),
      formulas: const {
        // Stale pattern THEMEVAL must not survive rebuild.
        'FillPattern': 'THEMEVAL()',
        'LinePattern': 'THEMEVAL()',
        'FillForegnd': 'THEMEVAL()',
        'LineColor': 'THEMEVAL()',
      },
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final out = writer.write(originalBytes: blank, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(r'N="FillForegnd"[^>]*F="THEMEVAL').hasMatch(pageXml),
      isTrue,
    );
    expect(
      RegExp(r'N="LineColor"[^>]*F="THEMEVAL').hasMatch(pageXml),
      isTrue,
    );
    expect(
      RegExp(r'N="FillPattern"[^>]*F="THEMEVAL').hasMatch(pageXml),
      isFalse,
      reason: 'pattern cells are literal ints — THEMEVAL must not rebuild',
    );
    expect(
      RegExp(r'N="LinePattern"[^>]*F="THEMEVAL').hasMatch(pageXml),
      isFalse,
    );
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.fill.themeForegroundIndex, ThemeSlot.accent1);
    expect(after.line.themeColorIndex, ThemeSlot.accent2);
    expect(after.formulas['FillForegnd'], contains('THEMEVAL'));
    expect(after.formulas['LineColor'], contains('THEMEVAL'));
    expect(after.formulas['FillPattern'], isNull);
    expect(after.formulas['LinePattern'], isNull);
  });

  test('Foreign dual theme fill emits named THEMEVAL for FillBkgnd', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final picId = doc.pages.first.nextFreeShapeId();
    const part = '/visio/media/image_dual_theme.png';
    final payload = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      1,
      2,
      3,
      4,
    ]);
    final pic = VsdxShapeFactory.picture(
      id: picId,
      pinX: 2,
      pinY: 2,
      width: 1.5,
      height: 1,
      imagePartName: part,
    ).copyWith(
      fill: const VsdxFill(
        themeForegroundIndex: ThemeSlot.accent1,
        themeBackgroundIndex: ThemeSlot.accent3,
        pattern: 1,
      ),
    );
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: payload, mimeType: 'image/png'),
          ),
        )
        .replacePage(0, doc.pages.first.addShape(pic));
    final out = writer.write(originalBytes: blank, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(
        r'N="FillBkgnd"[^>]*F="THEMEVAL\((?:&quot;|")AccentColor3(?:&quot;|")\)"',
      ).hasMatch(pageXml),
      isTrue,
    );
    expect(RegExp(r'N="Transparency"\s+V="0').hasMatch(pageXml), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(picId)!;
    expect(after.fill.themeForegroundIndex, ThemeSlot.accent1);
    expect(after.fill.themeBackgroundIndex, ThemeSlot.accent3);
    expect(after.imageTransparency, closeTo(0, 1e-6));
  });

  test('LineCap / HideText / CompoundType F=Inh scrub when values match', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(text: 'Hi'),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="LineCap"[^/]*/>'),
      '<Cell N="LineCap" V="0" F="Inh"/>',
    );
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="CompoundType"[^/]*/>'),
      '<Cell N="CompoundType" V="0" F="Inh"/>',
    );
    if (pageXml.contains('N="HideText"')) {
      pageXml = pageXml.replaceFirst(
        RegExp(r'<Cell N="HideText"[^/]*/>'),
        '<Cell N="HideText" V="0" F="Inh"/>',
      );
    } else {
      pageXml = pageXml.replaceFirst(
        '</Shape>',
        '<Cell N="HideText" V="0" F="Inh"/></Shape>',
      );
    }
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    for (final name in ['LineCap', 'CompoundType', 'HideText']) {
      final cell = XmlDocument.parse(outXml)
          .descendants
          .whereType<XmlElement>()
          .firstWhere(
            (e) => e.name.local == 'Cell' && e.getAttribute('N') == name,
          );
      expect(cell.getAttribute('F'), isNull, reason: name);
      expect(cell.getAttribute('V'), '0', reason: name);
    }
  });

  test('textual true character and HideText values survive synthesis', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          text: 'Hidden strike',
          richText: const VsdxRichText(
            runs: [
              VsdxTextRun(
                text: 'Hidden strike',
                charStyle: VsdxCharStyle(strikethrough: true),
              ),
            ],
            textBlock: VsdxTextBlock(hideText: true),
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="HideText"[^/]*/>'),
      '<Cell N="HideText" V="true"/>',
    );
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="Strikethru"[^/]*/>'),
      '<Cell N="Strikethru" V="true"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));

    doc = parser.parse(mid);
    var shape = doc.pages.first.findShapeById(id)!;
    expect(shape.richText.textBlock.hideText, isTrue);
    expect(shape.richText.runs.single.charStyle.strikethrough, isTrue);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );

    final out = writer.write(originalBytes: mid, edited: doc);
    shape = parser.parse(out).pages.first.findShapeById(id)!;
    expect(shape.richText.textBlock.hideText, isTrue);
    expect(shape.richText.runs.single.charStyle.strikethrough, isTrue);
  });

  test('disabled SoftEdges/Glow/Gradient emit V=0 on group rebuild', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final a = doc.pages.first.nextFreeShapeId();
    final b = a + 1;
    final gid = b + 1;
    doc = doc.replacePage(
      0,
      doc.pages.first
          .addShape(
            VsdxShapeFactory.rectangle(
              id: a,
              pinX: 1,
              pinY: 1,
              width: 1,
              height: 1,
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: b,
              pinX: 3,
              pinY: 1,
              width: 1,
              height: 1,
            ),
          ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.group({a, b}, groupId: gid),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="SoftEdgesSize" V="0"'), isTrue);
    expect(pageXml.contains('N="GlowSize" V="0"'), isTrue);
    expect(pageXml.contains('N="FillGradientEnabled" V="0"'), isTrue);
    expect(pageXml.contains('N="LineGradientEnabled" V="0"'), isTrue);
    expect(pageXml.contains('N="ReflectionSize" V="0"'), isTrue);
  });

  test('Foreign User/Control/Scratch survive group rebuild', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final picId = doc.pages.first.nextFreeShapeId();
    final otherId = picId + 1;
    final gid = otherId + 1;
    const part = '/visio/media/image_user_group.png';
    final payload = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      1,
      2,
      3,
      4,
    ]);
    final pic = VsdxShapeFactory.picture(
      id: picId,
      pinX: 2,
      pinY: 2,
      width: 1.5,
      height: 1,
      imagePartName: part,
    ).copyWith(
      userCells: const [
        VsdxUserCell(name: 'visVersion', value: '1'),
      ],
      controls: const [
        VsdxControlRow(name: 'Row_1', x: 0.5, y: 0.5),
      ],
      scratch: const [
        VsdxScratchRow(ix: 0, x: 1, y: 2),
      ],
    );
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: payload, mimeType: 'image/png'),
          ),
        )
        .replacePage(
          0,
          doc.pages.first.addShape(pic).addShape(
                VsdxShapeFactory.rectangle(
                  id: otherId,
                  pinX: 4,
                  pinY: 2,
                  width: 1,
                  height: 1,
                ),
              ),
        );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.group({picId, otherId}, groupId: gid),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="User"'), isTrue);
    expect(pageXml.contains('N="Control"'), isTrue);
    expect(pageXml.contains('N="Scratch"'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(picId)!;
    expect(after.userCells.single.name, 'visVersion');
    expect(after.controls.single.name, 'Row_1');
    expect(after.scratch.single.ix, 0);
  });

  test('BeginArrow/EndArrow F=Inh scrub when arrows are zero', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(id: id, ax: 1, ay: 1, bx: 3, by: 1),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    for (final name in ['BeginArrow', 'EndArrow']) {
      if (pageXml.contains('N="$name"')) {
        pageXml = pageXml.replaceFirst(
          RegExp('<Cell N="$name"[^/]*/>'),
          '<Cell N="$name" V="0" F="Inh"/>',
        );
      } else {
        pageXml = pageXml.replaceFirst(
          '</Shape>',
          '<Cell N="$name" V="0" F="Inh"/></Shape>',
        );
      }
    }
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          line: s.line.copyWith(transparency: 0.1),
        ),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    for (final name in ['BeginArrow', 'EndArrow']) {
      final cell = XmlDocument.parse(outXml)
          .descendants
          .whereType<XmlElement>()
          .firstWhere(
            (e) => e.name.local == 'Cell' && e.getAttribute('N') == name,
          );
      expect(cell.getAttribute('V'), '0', reason: name);
      expect(cell.getAttribute('F'), isNull, reason: name);
    }
  });

  test('LeftMargin F=Inh scrubs to literal model value', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(text: 'Hi'),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    if (pageXml.contains('N="LeftMargin"')) {
      pageXml = pageXml.replaceFirst(
        RegExp(r'<Cell N="LeftMargin"[^/]*/>'),
        '<Cell N="LeftMargin" V="0.04" F="Inh"/>',
      );
    } else {
      pageXml = pageXml.replaceFirst(
        '</Shape>',
        '<Cell N="LeftMargin" V="0.04" F="Inh"/></Shape>',
      );
    }
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) => e.name.local == 'Cell' && e.getAttribute('N') == 'LeftMargin',
        );
    expect(cell.getAttribute('F'), isNull);
  });

  test('ObjType / NoAlignBox patch without rebuild', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          objType: 1,
          noAlignBox: true,
          shapeSplittable: true,
          eventDblClick: 'OPENTEXTDLG()',
        ),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="ObjType" V="1"'), isTrue);
    expect(pageXml.contains('N="NoAlignBox" V="1"'), isTrue);
    expect(pageXml.contains('N="ShapeSplittable" V="1"'), isTrue);
    expect(pageXml.contains('OPENTEXTDLG()'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.objType, 1);
    expect(after.noAlignBox, isTrue);
    expect(after.shapeSplittable, isTrue);
    expect(after.eventDblClick, 'OPENTEXTDLG()');
  });

  test('Foreign Field/Actions survive group rebuild', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final picId = doc.pages.first.nextFreeShapeId();
    final otherId = picId + 1;
    final gid = otherId + 1;
    const part = '/visio/media/image_field_group.png';
    final payload = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      1,
      2,
      3,
      4,
    ]);
    final pic = VsdxShapeFactory.picture(
      id: picId,
      pinX: 2,
      pinY: 2,
      width: 1.5,
      height: 1,
      imagePartName: part,
    ).copyWith(
      text: 'Cap',
      fields: const [
        VsdxFieldRow(ix: 0, value: '1', valueFormula: 'Width'),
      ],
      actions: const [
        VsdxActionRow(
          name: 'Row_1',
          ix: 1,
          menu: 'Do it',
          action: '0',
          actionFormula: 'RUNADDON("X")',
        ),
      ],
    );
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: payload, mimeType: 'image/png'),
          ),
        )
        .replacePage(
          0,
          doc.pages.first.addShape(pic).addShape(
                VsdxShapeFactory.rectangle(
                  id: otherId,
                  pinX: 4,
                  pinY: 2,
                  width: 1,
                  height: 1,
                ),
              ),
        );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.group({picId, otherId}, groupId: gid),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="Field"'), isTrue);
    expect(pageXml.contains('N="Actions"'), isTrue);
    expect(pageXml.contains('N="VerticalAlign"'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(picId)!;
    expect(after.fields, isNotEmpty);
    expect(after.actions.single.menu, 'Do it');
    expect(after.text, contains('Cap'));
  });

  test('ShadowPattern alone inherits page ShdwOffset offsets', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    // Custom page offsets (not the Visio 0.125/-0.125 defaults).
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        pageSheet: doc.pages.first.pageSheet.copyWith(
          shadowOffsetXInches: 0.25,
          shadowOffsetYInches: -0.2,
        ),
      ),
    );
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          shadow: const VsdxShadow(
            enabled: true,
            offsetXInches: 0.25,
            offsetYInches: -0.2,
            blurInches: 0,
          ),
        ),
      ),
    );
    final withOffsets = writer.write(originalBytes: blank, edited: doc);
    // Strip shape ShadowOffset* so reopen must fall back to page Sheet.
    final archive = ZipDecoder().decodeBytes(withOffsets);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml
        .replaceAll(RegExp(r'<Cell N="ShadowOffsetX"[^/]*/>'), '')
        .replaceAll(RegExp(r'<Cell N="ShadowOffsetY"[^/]*/>'), '');
    final rebuilt = Archive();
    for (final f in archive) {
      if (f.name.contains('pages/page1.xml')) {
        final bytes = utf8.encode(pageXml);
        rebuilt.addFile(ArchiveFile(f.name, bytes.length, bytes));
      } else {
        rebuilt.addFile(f);
      }
    }
    final stripped = Uint8List.fromList(ZipEncoder().encode(rebuilt)!);
    final after = parser.parse(stripped).pages.first.findShapeById(id)!;
    expect(after.shadow.enabled, isTrue);
    expect(after.shadow.offsetXInches, closeTo(0.25, 1e-6));
    expect(after.shadow.offsetYInches, closeTo(-0.2, 1e-6));

    // Direct StyleParser: pattern only → page offsets.
    const style = StyleParser();
    final el = XmlDocument.parse('''
      <Shape ID="1" Type="Shape">
        <Cell N="ShadowPattern" V="1"/>
      </Shape>''').rootElement;
    final parsed = style.parseShadow(
      el,
      pageOffsetXInches: 0.125,
      pageOffsetYInches: -0.125,
    );
    expect(parsed.enabled, isTrue);
    expect(parsed.offsetXInches, closeTo(0.125, 1e-6));
    expect(parsed.offsetYInches, closeTo(-0.125, 1e-6));
  });

  test('Foreign ThemeIndex / EventDblClick survive group rebuild', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final picId = doc.pages.first.nextFreeShapeId();
    final otherId = picId + 1;
    final gid = otherId + 1;
    const part = '/visio/media/image_meta_group.png';
    final payload = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      1,
      2,
      3,
      4,
    ]);
    final pic = VsdxShapeFactory.picture(
      id: picId,
      pinX: 2,
      pinY: 2,
      width: 1.5,
      height: 1,
      imagePartName: part,
    ).copyWith(
      themeIndex: 2,
      eventDblClick: '0',
      formulas: const {'EventDblClick': 'OPENTEXTWIN()'},
      objType: 1,
      selectMode: 1,
      imageTransparency: 0.4,
    );
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: payload, mimeType: 'image/png'),
          ),
        )
        .replacePage(
          0,
          doc.pages.first.addShape(pic).addShape(
                VsdxShapeFactory.rectangle(
                  id: otherId,
                  pinX: 4,
                  pinY: 2,
                  width: 1,
                  height: 1,
                ),
              ),
        );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    // Clear image transparency — must not resurrect via opaque after group.
    doc = doc.replacePage(
      0,
      doc.pages.first
          .updateShapeById(picId, (s) => s.copyWith(imageTransparency: 0))
          .group({picId, otherId}, groupId: gid),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="ThemeIndex"'), isTrue);
    expect(pageXml.contains('OPENTEXTWIN()'), isTrue);
    expect(pageXml.contains('N="ObjType"'), isTrue);
    expect(pageXml.contains('N="SelectMode"'), isTrue);
    // ImgOffset emitted once by builder (not duplicated via opaque).
    expect(RegExp(r'N="ImgOffsetX"').allMatches(pageXml).length, 1);
    // Transparency always emitted (incl. 0) so Master tone cannot revive.
    expect(RegExp(r'N="Transparency"\s+V="0').hasMatch(pageXml), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(picId)!;
    expect(after.themeIndex, 2);
    expect(after.formulas['EventDblClick'], 'OPENTEXTWIN()');
    expect(after.objType, 1);
    expect(after.selectMode, 1);
    expect(after.imageTransparency, closeTo(0, 1e-6));
    expect(after.hasImage, isTrue);
  });

  test('ConFixedCode F=Inh scrubbed on connector ensure', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final conn = VsdxShapeFactory.line(
      id: id,
      ax: 1,
      ay: 2,
      bx: 4,
      by: 2,
    ).reshapeAsPolyline(const <Offset2D>[
      Offset2D(1, 2),
      Offset2D(2.5, 2),
      Offset2D(4, 2),
    ]);
    doc = doc.replacePage(0, doc.pages.first.addShape(conn));
    final mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    // Inject stale F=Inh on ConFixedCode.
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="ConFixedCode"[^/]*/>'),
      '<Cell N="ConFixedCode" V="3" F="Inh"/>',
    );
    final tainted = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(tainted);
    // Touch connector so ensure path runs on write.
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (shape) => shape.copyWith(
          connectorProps: (shape.connectorProps ??
                  const VsdxConnectorProps(conFixedCode: 3))
              .copyWith(conFixedCode: 3),
        ),
      ),
    );
    final out = writer.write(originalBytes: tainted, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final match = RegExp(r'<Cell N="ConFixedCode"[^/]*/>').firstMatch(outXml);
    expect(match, isNotNull);
    expect(match!.group(0)!.contains('F='), isFalse);
    expect(match.group(0)!.contains('V="3"'), isTrue);
  });

  test('GlueType / DynFeedback F=Inh scrubbed when connector props unchanged',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final conn = VsdxShapeFactory.line(id: id, ax: 1, ay: 2, bx: 4, by: 2);
    doc = doc.replacePage(0, doc.pages.first.addShape(conn));
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="GlueType"[^/]*/>'),
      '<Cell N="GlueType" V="2" F="Inh"/>',
    );
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="DynFeedback"[^/]*/>'),
      '<Cell N="DynFeedback" V="2" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    // Touch pin only — connectorProps model stays equal.
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.01),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    for (final name in ['GlueType', 'DynFeedback']) {
      final cell = XmlDocument.parse(outXml)
          .descendants
          .whereType<XmlElement>()
          .firstWhere(
            (e) => e.name.local == 'Cell' && e.getAttribute('N') == name,
          );
      expect(cell.getAttribute('F'), isNull, reason: name);
      expect(cell.getAttribute('V'), '2', reason: name);
    }
  });

  test('Layer Visible F=Inh scrubbed when layers model unchanged', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        layers: const [
          VsdxLayer(id: 0, name: 'Default', visible: false),
        ],
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pagesFile =
        archive.firstWhere((f) => f.name.contains('pages/pages.xml'));
    var pagesXml = utf8.decode(pagesFile.content as List<int>);
    pagesXml = pagesXml.replaceFirst(
      RegExp(r'<Cell N="Visible"[^/]*/>'),
      '<Cell N="Visible" V="false" F="Inh"/>',
    );
    mid = _rezipWith(mid, pagesFile.name, utf8.encode(pagesXml));
    doc = parser.parse(mid);
    expect(doc.pages.first.layers.single.visible, isFalse);
    // Shape touch forces a write; layers model stays equal.
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 1,
          height: 1,
        ),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outPages = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/pages.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outPages)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) => e.name.local == 'Cell' && e.getAttribute('N') == 'Visible',
        );
    expect(cell.getAttribute('F'), isNull);
    expect(cell.getAttribute('V'), '0');
    expect(parser.parse(out).pages.first.layers.single.visible, isFalse);
  });

  test('GlowColor / ShadowForegnd F=Inh scrubbed while effects stay on', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          glow: const VsdxGlow(
            enabled: true,
            sizeInches: 0.1,
            color: VsdxColor(0xFF00AADD),
          ),
          shadow: const VsdxShadow(
            enabled: true,
            pattern: 1,
            color: VsdxColor(0xFF334455),
            blurInches: 0,
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="GlowColor"[^/]*/>'),
      '<Cell N="GlowColor" V="#00aadd" F="Inh"/>',
    );
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="ShadowForegnd"[^/]*/>'),
      '<Cell N="ShadowForegnd" V="#334455" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    for (final name in ['GlowColor', 'ShadowForegnd']) {
      final cell = XmlDocument.parse(outXml)
          .descendants
          .whereType<XmlElement>()
          .firstWhere(
            (e) => e.name.local == 'Cell' && e.getAttribute('N') == name,
          );
      expect(cell.getAttribute('F'), isNull, reason: name);
    }
  });

  test('Control / Scratch / Field / Character F=Inh scrubbed when model equal',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          text: 'Hi',
          controls: const [
            VsdxControlRow(name: 'TextPosition', x: 0.5, y: 0.5),
          ],
          scratch: const [
            VsdxScratchRow(ix: 0, x: 1, y: 2, a: 3, b: 4),
          ],
          fields: const [
            VsdxFieldRow(ix: 0, value: '42', type: 0),
          ],
          richText: VsdxRichText(runs: [
            VsdxTextRun(
              text: 'Hi',
              charStyle: VsdxCharStyle(fontSizeInches: 12 / 72),
            ),
          ]),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      '<Cell N="CanGlue" V="0"/>',
      '<Cell N="CanGlue" V="0" F="Inh"/>',
    );
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="A" V="3"[^/]*/>'),
      '<Cell N="A" V="3" F="Inh"/>',
    );
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="Value" V="42"[^/]*/>'),
      '<Cell N="Value" V="42" U="STR" F="Inh"/>',
    );
    final sizeMatch =
        RegExp(r'<Section N="Character">[\s\S]*?<Cell N="Size"[^/]*/>')
            .firstMatch(pageXml);
    if (sizeMatch != null) {
      final old = sizeMatch.group(0)!;
      pageXml = pageXml.replaceFirst(
        old,
        old.contains('F=')
            ? old.replaceFirst(RegExp(r'F="[^"]*"'), 'F="Inh"')
            : old.replaceFirst('/>', ' F="Inh"/>'),
      );
    }
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(outXml.contains('N="CanGlue" V="0" F="Inh"'), isFalse);
    expect(
      RegExp(r'<Cell N="A" V="3"[^>]*F="Inh"').hasMatch(outXml),
      isFalse,
    );
    expect(
      RegExp(r'<Cell N="Value" V="42"[^>]*F="Inh"').hasMatch(outXml),
      isFalse,
    );
    expect(
      RegExp(r'<Section N="Character">[\s\S]*?<Cell N="Size"[^>]*F="Inh"')
          .hasMatch(outXml),
      isFalse,
    );
  });

  test('FillGradient stop Color F=Inh scrubbed when gradient unchanged', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(
            gradient: VsdxGradient(
              stops: [
                VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
                VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
              ],
            ),
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    // Taint only the first stop colour cell inside FillGradient.
    final stopMatch = RegExp(
      r'<Section N="FillGradient">[\s\S]*?<Cell N="GradientStopColor"[^/]*/>',
    ).firstMatch(pageXml);
    expect(stopMatch, isNotNull);
    final oldStop = stopMatch!.group(0)!;
    final taintedStop = oldStop.replaceFirst(
      RegExp(r'<Cell N="GradientStopColor"[^/]*/>'),
      '<Cell N="GradientStopColor" V="#FF0000" F="Inh"/>',
    );
    pageXml = pageXml.replaceFirst(oldStop, taintedStop);
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(id)!.fill.hasGradient, isTrue);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(
        r'<Section N="FillGradient">[\s\S]*?<Cell N="GradientStopColor"[^>]*F="Inh"',
      ).hasMatch(outXml),
      isFalse,
    );
  });

  test('LocPinX F=Inh scrubbed when pin model unchanged', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="LocPinX"[^/]*/>'),
      '<Cell N="LocPinX" V="1" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinY: s.pinY + 0.05),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final match = RegExp(r'<Cell N="LocPinX"[^/]*/>').firstMatch(outXml);
    expect(match, isNotNull);
    expect(match!.group(0)!.contains('F="Inh"'), isFalse);
  });

  test('Geometry MoveTo X F=Inh scrubbed when geometry model equal', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    final geoMatch = RegExp(
      r'<Section N="Geometry"[\s\S]*?<Row[^>]*T="MoveTo"[\s\S]*?<Cell N="X"[^/]*/>',
    ).firstMatch(pageXml);
    expect(geoMatch, isNotNull);
    final old = geoMatch!.group(0)!;
    final tainted = old.replaceFirst(
      RegExp(r'<Cell N="X"[^/]*/>'),
      '<Cell N="X" V="0" F="Inh"/>',
    );
    pageXml = pageXml.replaceFirst(old, tainted);
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(
        r'<Row[^>]*T="MoveTo"[\s\S]*?<Cell N="X"[^>]*F="Inh"',
      ).hasMatch(outXml),
      isFalse,
    );
  });

  test('theme GlowColor F=Inh scrubbed to THEMEVAL when model unchanged', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          glow: const VsdxGlow(
            enabled: true,
            sizeInches: 0.1,
            themeColorIndex: ThemeSlot.accent1,
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="GlowColor"[^/]*/>'),
      '<Cell N="GlowColor" V="0" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(r'N="GlowColor"[^>]*F="Inh"').hasMatch(outXml),
      isFalse,
    );
    expect(
      RegExp(r'N="GlowColor"[^>]*F="THEMEVAL').hasMatch(outXml) ||
          RegExp(r'F="THEMEVAL\(\)"[^>]*N="GlowColor"').hasMatch(outXml),
      isTrue,
    );
  });

  test('QuickStyleFillColor F=Inh scrubbed when theme fill unchanged', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(
            pattern: 1,
            themeForegroundIndex: ThemeSlot.accent1,
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="QuickStyleFillColor"[^/]*/>'),
      '<Cell N="QuickStyleFillColor" V="${ThemeSlot.accent1}" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    // QuickStyle Inh without Master → theme slot cleared (not forced to lt1).
    expect(
      doc.pages.first.findShapeById(id)!.fill.themeForegroundIndex,
      isNull,
    );
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          pinX: s.pinX + 0.1,
          fill: s.fill.copyWith(themeForegroundIndex: ThemeSlot.accent1),
        ),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) =>
              e.name.local == 'Cell' &&
              e.getAttribute('N') == 'QuickStyleFillColor',
        );
    expect(cell.getAttribute('F'), isNull);
    expect(cell.getAttribute('V'), ThemeSlot.accent1.toString());
  });

  test('AsianFont F=Inh scrubbed when rich text model unchanged', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          text: '你好',
          richText: VsdxRichText(runs: [
            VsdxTextRun(
              text: '你好',
              charStyle: const VsdxCharStyle(
                fontFamily: 'Arial',
                asianFont: 'Microsoft YaHei',
              ),
            ),
          ]),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    expect(pageXml.contains('N="AsianFont"'), isTrue);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="AsianFont"[^/]*/>'),
      '<Cell N="AsianFont" V="Microsoft YaHei" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    // Re-apply asianFont (Inh without Master clears it) then scrub on save.
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          pinX: s.pinX + 0.1,
          richText: VsdxRichText(runs: [
            for (final r in s.richText.runs)
              r.copyWith(
                charStyle: r.charStyle.copyWith(asianFont: 'Microsoft YaHei'),
              ),
          ]),
        ),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) => e.name.local == 'Cell' && e.getAttribute('N') == 'AsianFont',
        );
    expect(cell.getAttribute('F'), isNull);
    expect(cell.getAttribute('V'), 'Microsoft YaHei');
  });

  test('Font / LangID F=Inh dropped when unbound in model', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          text: 'Hi',
          richText: VsdxRichText(runs: [
            VsdxTextRun(
              text: 'Hi',
              charStyle: const VsdxCharStyle(
                fontFamily: 'Arial',
                langId: 'en-US',
              ),
            ),
          ]),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    expect(pageXml.contains('N="Font"'), isTrue);
    expect(pageXml.contains('N="LangID"'), isTrue);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="Font"[^/]*/>'),
      '<Cell N="Font" V="Arial" F="INH"/>',
    );
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="LangID"[^/]*/>'),
      '<Cell N="LangID" V="en-US" F="Inh()"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    // Clear unbound fonts in model so equal-path scrub drops Inh cells.
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          pinX: s.pinX + 0.1,
          richText: VsdxRichText(runs: [
            for (final r in s.richText.runs)
              r.copyWith(
                charStyle: r.charStyle.copyWith(
                  clearFontFamily: true,
                  clearLangId: true,
                ),
              ),
          ]),
        ),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(RegExp(r'N="Font"[^>]*F=').hasMatch(outXml), isFalse);
    expect(RegExp(r'N="LangID"[^>]*F=').hasMatch(outXml), isFalse);
  });

  test('PageWidth F=INH scrubbed via isInhFormula', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pagesFile =
        archive.firstWhere((f) => f.name.endsWith('pages/pages.xml'));
    var pagesXml = utf8.decode(pagesFile.content as List<int>);
    pagesXml = pagesXml.replaceFirst(
      RegExp(r'<Cell N="PageWidth"[^/]*/>'),
      '<Cell N="PageWidth" V="8.5" F="INH"/>',
    );
    final tainted = _rezipWith(mid, pagesFile.name, utf8.encode(pagesXml));
    doc = parser.parse(tainted);
    final out = writer.write(originalBytes: tainted, edited: doc);
    pagesXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.endsWith('pages/pages.xml'))
          .content as List<int>,
    );
    final cell = RegExp(r'<Cell N="PageWidth"[^/]*/>').firstMatch(pagesXml);
    expect(cell, isNotNull);
    expect(cell!.group(0)!.toUpperCase().contains('F="INH"'), isFalse);
  });

  test('disabled shadow rebuild emits ShadowPattern and ShdwPattern 0', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(shadow: const VsdxShadow(enabled: true, blurInches: 0)),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(shadow: VsdxShadow.disabled),
      ),
    );
    // Force rebuild path via group+ungroup of two shapes.
    final otherId = doc.pages.first.nextFreeShapeId();
    final gid = otherId + 1;
    doc = doc.replacePage(
      0,
      doc.pages.first
          .addShape(
        VsdxShapeFactory.rectangle(
          id: otherId,
          pinX: 4,
          pinY: 1,
          width: 1,
          height: 1,
        ),
      )
          .group({id, otherId}, groupId: gid),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="ShadowPattern" V="0"'), isTrue);
    expect(pageXml.contains('N="ShdwPattern" V="0"'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.shadow.enabled, isFalse);
  });

  test('Foreign ImgWidth crop formula survives group rebuild', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final picId = doc.pages.first.nextFreeShapeId();
    final otherId = picId + 1;
    final gid = otherId + 1;
    const part = '/visio/media/image_crop_group.png';
    final payload = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      5,
      6,
      7,
      8,
    ]);
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: payload, mimeType: 'image/png'),
          ),
        )
        .replacePage(
          0,
          doc.pages.first.addShape(
            VsdxShapeFactory.picture(
              id: picId,
              pinX: 2,
              pinY: 2,
              width: 2,
              height: 2,
              imagePartName: part,
            ),
          ),
        );
    final mid = writer.write(originalBytes: blank, edited: doc);
    // Inject crop formula, reparse so formulas map picks it up.
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="ImgWidth"[^/]*/>'),
      '<Cell N="ImgWidth" V="1" F="Width*0.5"/>',
    );
    final cropped = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(cropped);
    expect(doc.pages.first.findShapeById(picId)!.formulas['ImgWidth'],
        'Width*0.5');
    doc = doc.replacePage(
      0,
      doc.pages.first
          .addShape(
        VsdxShapeFactory.rectangle(
          id: otherId,
          pinX: 5,
          pinY: 2,
          width: 1,
          height: 1,
        ),
      )
          .group({picId, otherId}, groupId: gid),
    );
    final out = writer.write(originalBytes: cropped, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(outXml.contains('N="ImgWidth"'), isTrue);
    expect(outXml.contains('F="Width*0.5"'), isTrue);
    expect(outXml.contains('N="FillGradientEnabled" V="0"'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(picId)!;
    expect(after.formulas['ImgWidth'], 'Width*0.5');
    expect(after.hasImage, isTrue);
  });

  test('fine-grained LockTextEdit survives group rebuild when unlocked', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final a = doc.pages.first.nextFreeShapeId();
    final b = a + 1;
    final gid = b + 1;
    doc = doc.replacePage(
      0,
      doc.pages.first
          .addShape(
            VsdxShapeFactory.rectangle(
              id: a,
              pinX: 1,
              pinY: 1,
              width: 1,
              height: 1,
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: b,
              pinX: 3,
              pinY: 1,
              width: 1,
              height: 1,
            ),
          ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    // Inject LockTextEdit=1 on shape A without LockMoveX (not fully locked).
    pageXml = pageXml.replaceFirst(
      '<Shape ID="$a"',
      '<Shape ID="$a"',
    );
    // Insert LockTextEdit after first Cell of shape A.
    pageXml = pageXml.replaceFirst(
      RegExp('<Shape ID="$a"[^>]*>\\s*<Cell '),
      '<Shape ID="$a" NameU="Sheet.$a" Name="Sheet.$a" Type="Shape">'
      '<Cell N="LockTextEdit" V="1"/><Cell ',
    );
    final tainted = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(tainted);
    expect(doc.pages.first.findShapeById(a)!.locked, isFalse);
    doc = doc.replacePage(
      0,
      doc.pages.first.group({a, b}, groupId: gid),
    );
    final out = writer.write(originalBytes: tainted, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(outXml.contains('N="LockTextEdit" V="1"'), isTrue);
  });

  test('fine-grained LockTextEdit survives pin patch when unlocked', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp('<Shape ID="$id"[^>]*>\\s*<Cell '),
      '<Shape ID="$id" NameU="Sheet.$id" Name="Sheet.$id" Type="Shape">'
      '<Cell N="LockTextEdit" V="1"/><Cell ',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(id)!.locked, isFalse);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.25),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(outXml.contains('N="LockTextEdit" V="1"'), isTrue,
        reason: 'unlocked pin patch must not zero fine-grained Lock*');
  });

  test('Connection DirX F=Inh scrubs on pin patch', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          connectionPoints: const [
            VsdxConnectionPoint(1, 0.5, dirX: 1, dirY: 0),
          ],
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="DirX"[^/]*/>'),
      '<Cell N="DirX" V="1" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final dir = RegExp(r'<Cell N="DirX"[^/]*/>').firstMatch(outXml)!.group(0)!;
    expect(dir.contains('F="Inh"'), isFalse);
    expect(dir.contains('V="1"'), isTrue);
  });

  test('VerticalAlign middle emitted on unlabeled shape group rebuild', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final otherId = id + 1;
    final gid = otherId + 1;
    doc = doc.replacePage(
      0,
      doc.pages.first
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id,
              pinX: 1,
              pinY: 1,
              width: 2,
              height: 1,
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: otherId,
              pinX: 4,
              pinY: 1,
              width: 1,
              height: 1,
            ),
          ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.group({id, otherId}, groupId: gid),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    // Both unlabeled rects must carry explicit middle align (V=1).
    expect(
      RegExp(r'N="VerticalAlign"\s+V="1"').allMatches(pageXml).length,
      greaterThanOrEqualTo(2),
    );
    // TxtAngle=0 and empty LayerMember always present after rebuild.
    expect(RegExp(r'N="TxtAngle"\s+V="0').allMatches(pageXml).length,
        greaterThanOrEqualTo(2));
    expect(RegExp(r'N="LayerMember"\s+V=""').allMatches(pageXml).length,
        greaterThanOrEqualTo(2));
  });

  test('cleared LayerMember stays empty across group rebuild', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final otherId = id + 1;
    final gid = otherId + 1;
    doc = doc.replacePage(
      0,
      doc.pages.first
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id,
              pinX: 1,
              pinY: 1,
              width: 2,
              height: 1,
            ).copyWith(layerMemberIds: const [0]),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: otherId,
              pinX: 4,
              pinY: 1,
              width: 1,
              height: 1,
            ),
          ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    // Clear membership then group (rebuild path).
    doc = doc.replacePage(
      0,
      doc.pages.first
          .updateShapeById(id, (s) => s.copyWith(layerMemberIds: const []))
          .group({id, otherId}, groupId: gid),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.layerMemberIds, isEmpty);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="LayerMember" V=""'), isTrue);
  });

  test('cleared arrows and HideText=0 survive group rebuild', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final otherId = id + 1;
    final gid = otherId + 1;
    doc = doc.replacePage(
      0,
      doc.pages.first
          .addShape(
            VsdxShapeFactory.line(id: id, ax: 1, ay: 2, bx: 4, by: 2).copyWith(
              line: const VsdxLine(beginArrow: 0, endArrow: 0),
              richText: const VsdxRichText(
                runs: [VsdxTextRun(text: 'x')],
                textBlock: VsdxTextBlock(hideText: false),
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: otherId,
              pinX: 5,
              pinY: 2,
              width: 1,
              height: 1,
            ),
          ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.group({id, otherId}, groupId: gid),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="BeginArrow" V="0"'), isTrue);
    expect(pageXml.contains('N="EndArrow" V="0"'), isTrue);
    expect(pageXml.contains('N="HideText" V="0"'), isTrue);
    expect(pageXml.contains('N="FlipX" V="0"'), isTrue);
  });

  test('hyperlink ExtraInfo survives address-only rewrite', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final link = const VsdxHyperlink(
      id: 1,
      address: 'https://example.com/old',
      description: 'Old',
      extraInfo: 'utm=1',
      frame: '_blank',
      newWindow: true,
      sortKey: 'A',
      isDefault: true,
    );
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(hyperlinks: [link]),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    // Mimic Edit Link dialog: change URL/label but keep ExtraInfo via copy fields.
    final updated = link.copyWith(
      address: 'https://example.com/new',
      description: 'New',
    );
    expect(updated.extraInfo, 'utm=1');
    expect(updated.frame, '_blank');
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(hyperlinks: [updated]),
      ),
    );
    final after = parser
        .parse(writer.write(originalBytes: mid, edited: doc))
        .pages
        .first
        .findShapeById(id)!
        .hyperlinks
        .single;
    expect(after.address, 'https://example.com/new');
    expect(after.extraInfo, 'utm=1');
    expect(after.frame, '_blank');
    expect(after.newWindow, isTrue);
    expect(after.sortKey, 'A');
  });

  test('cleared fill transparency and TextDirection survive group rebuild', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final otherId = id + 1;
    final gid = otherId + 1;
    doc = doc.replacePage(
      0,
      doc.pages.first
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id,
              pinX: 1,
              pinY: 1,
              width: 2,
              height: 1,
            ).copyWith(
              fill: const VsdxFill(
                foreground: VsdxColor(0xFFFF0000),
                foregroundTransparency: 0,
              ),
              richText: const VsdxRichText(
                runs: [VsdxTextRun(text: 't')],
                textBlock: VsdxTextBlock(textDirection: 0),
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: otherId,
              pinX: 4,
              pinY: 1,
              width: 1,
              height: 1,
            ),
          ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.group({id, otherId}, groupId: gid),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="FillForegndTrans"'), isTrue);
    expect(pageXml.contains('N="TextDirection" V="0"'), isTrue);
    expect(pageXml.contains('N="LockMoveX" V="0"'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.fill.foregroundTransparency, closeTo(0, 1e-6));
    expect(after.richText.textBlock.textDirection, 0);
  });

  test('rebuild keeps Visio default text margins and NoAlignBox=0', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final otherId = id + 1;
    final gid = otherId + 1;
    doc = doc.replacePage(
      0,
      doc.pages.first
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id,
              pinX: 1,
              pinY: 1,
              width: 2,
              height: 1,
            ).copyWith(
              noAlignBox: false,
              richText: const VsdxRichText(
                runs: [VsdxTextRun(text: 'Label')],
                textBlock: VsdxTextBlock(
                  // Visio default margins (0.04"), not Edraw's ~4pt.
                  marginLeftInches: 0.04,
                  marginRightInches: 0.04,
                  marginTopInches: 0.04,
                  marginBottomInches: 0.04,
                ),
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: otherId,
              pinX: 4,
              pinY: 1,
              width: 1,
              height: 1,
            ),
          ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.group({id, otherId}, groupId: gid),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="LeftMargin" V="0.04"'), isTrue);
    expect(pageXml.contains('0.05555555555555555'), isFalse);
    expect(pageXml.contains('N="NoAlignBox" V="0"'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.richText.textBlock.marginLeftInches, closeTo(0.04, 1e-6));
    expect(after.noAlignBox, isFalse);
  });

  test('Foreign Img* F=Inh scrubbed on patch', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final picId = doc.pages.first.nextFreeShapeId();
    const part = '/visio/media/image_inh_tone.png';
    final payload = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      9,
      8,
      7,
      6,
    ]);
    final pic = VsdxShapeFactory.picture(
      id: picId,
      pinX: 2,
      pinY: 2,
      width: 1.5,
      height: 1,
      imagePartName: part,
    ).copyWith(
      imageTransparency: 0.25,
      imageBlur: 0.1,
      imageBrightness: 0.05,
      imageContrast: 0.15,
      imgOffsetXInches: 0.1,
      imgOffsetYInches: 0.2,
    );
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: payload, mimeType: 'image/png'),
          ),
        )
        .replacePage(0, doc.pages.first.addShape(pic));
    final mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    for (final name in const [
      'Transparency',
      'Blur',
      'Brightness',
      'Contrast',
      'ImgOffsetX',
      'ImgOffsetY',
    ]) {
      pageXml = pageXml.replaceFirst(
        RegExp('<Cell N="$name"[^/]*/>'),
        '<Cell N="$name" V="0.5" F="Inh"/>',
      );
    }
    final tainted = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(tainted);
    // Without master, Inh must not adopt stale V=0.5.
    final parsed = doc.pages.first.findShapeById(picId)!;
    expect(parsed.imageTransparency, closeTo(0, 1e-6));
    expect(parsed.imageBlur, closeTo(0, 1e-6));
    expect(parsed.imageBrightness, closeTo(0.5, 1e-6));
    expect(parsed.imageContrast, closeTo(0.5, 1e-6));
    expect(parsed.imgOffsetXInches, closeTo(0, 1e-6));
    expect(parsed.imgOffsetYInches, closeTo(0, 1e-6));
    // Re-apply model values so patch syncs + scrubs Inh.
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        picId,
        (s) => s.copyWith(
          imageTransparency: 0.25,
          imageBlur: 0.1,
          imageBrightness: 0.05,
          imageContrast: 0.15,
          imgOffsetXInches: 0.1,
          imgOffsetYInches: 0.2,
        ),
      ),
    );
    final out = writer.write(originalBytes: tainted, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    for (final name in const [
      'Transparency',
      'Blur',
      'Brightness',
      'Contrast',
      'ImgOffsetX',
      'ImgOffsetY',
    ]) {
      final m = RegExp('<Cell N="$name"[^/]*/>').firstMatch(pageXml);
      expect(m, isNotNull, reason: name);
      expect(m!.group(0)!.contains('F="Inh"'), isFalse, reason: name);
    }
    final after = parser.parse(out).pages.first.findShapeById(picId)!;
    expect(after.imageTransparency, closeTo(0.25, 1e-6));
    expect(after.imageBlur, closeTo(0.1, 1e-6));
    expect(after.imgOffsetXInches, closeTo(0.1, 1e-6));
  });

  test('connector ensure honours NoAlignBox/ShapeSplittable=0', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final conn = VsdxShapeFactory.line(
      id: id,
      ax: 1,
      ay: 2,
      bx: 4,
      by: 2,
    ).reshapeAsPolyline(const <Offset2D>[
      Offset2D(1, 2),
      Offset2D(2.5, 2),
      Offset2D(4, 2),
    ]).copyWith(noAlignBox: false, shapeSplittable: false);
    doc = doc.replacePage(0, doc.pages.first.addShape(conn));
    final mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    // Simulate Edraw defaults forcing both flags on.
    for (final name in const ['NoAlignBox', 'ShapeSplittable']) {
      if (pageXml.contains('N="$name"')) {
        pageXml = pageXml.replaceFirst(
          RegExp('<Cell N="$name"[^/]*/>'),
          '<Cell N="$name" V="1"/>',
        );
      } else {
        pageXml = pageXml.replaceFirst(
          '</Shape>',
          '<Cell N="$name" V="1"/></Shape>',
        );
      }
    }
    final tainted = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(tainted);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(noAlignBox: false, shapeSplittable: false),
      ),
    );
    final out = writer.write(originalBytes: tainted, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="NoAlignBox" V="0"'), isTrue);
    expect(pageXml.contains('N="ShapeSplittable" V="0"'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.noAlignBox, isFalse);
    expect(after.shapeSplittable, isFalse);
  });

  test('disabled shadow rebuild emits companion offset/blur/trans', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final otherId = id + 1;
    final gid = otherId + 1;
    doc = doc.replacePage(
      0,
      doc.pages.first
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id,
              pinX: 1,
              pinY: 1,
              width: 2,
              height: 1,
            ).copyWith(
              shadow: const VsdxShadow(
                enabled: false,
                color: VsdxColor(0xFF1565C0),
                offsetXInches: 0.12,
                offsetYInches: -0.08,
                blurInches: 0.05,
                transparency: 0.3,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: otherId,
              pinX: 4,
              pinY: 1,
              width: 1,
              height: 1,
            ),
          ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.group({id, otherId}, groupId: gid),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="ShadowPattern" V="0"'), isTrue);
    expect(pageXml.contains('N="ShdwPattern" V="0"'), isTrue);
    expect(pageXml.contains('N="ShadowOffsetX"'), isTrue);
    expect(pageXml.contains('N="ShapeShdwOffsetX"'), isTrue);
    expect(pageXml.contains('N="ShapeShdwOffsetY"'), isTrue);
    expect(pageXml.contains('N="ShadowBlur"'), isTrue);
    expect(pageXml.contains('N="ShadowForegndTrans"'), isTrue);
    expect(pageXml.contains('N="ShdwForegndTrans"'), isTrue);
    expect(pageXml.contains('N="ShadowForegnd"'), isTrue);
    expect(pageXml.contains('N="ShdwForegnd"'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.shadow.enabled, isFalse);
    expect(after.shadow.offsetXInches, closeTo(0.12, 1e-6));
    expect(after.shadow.blurInches, closeTo(0.05, 1e-6));
    expect(after.shadow.color?.value, 0xFF1565C0);
  });

  test('disabled glow rebuild keeps GlowColor for re-enable', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final otherId = id + 1;
    final gid = otherId + 1;
    doc = doc.replacePage(
      0,
      doc.pages.first
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id,
              pinX: 1,
              pinY: 1,
              width: 2,
              height: 1,
            ).copyWith(
              glow: const VsdxGlow(
                enabled: false,
                color: VsdxColor(0xFF00AA00),
                sizeInches: 0,
                transparency: 0.4,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: otherId,
              pinX: 4,
              pinY: 1,
              width: 1,
              height: 1,
            ),
          ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.group({id, otherId}, groupId: gid),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="GlowSize" V="0"'), isTrue);
    expect(pageXml.contains('N="GlowColor"'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.glow.enabled, isFalse);
    expect(after.glow.color?.value, 0xFF00AA00);
  });

  test('FillForegnd / FillPattern F=Inh scrubbed on rebuild', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final otherId = id + 1;
    final gid = otherId + 1;
    doc = doc.replacePage(
      0,
      doc.pages.first
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id,
              pinX: 1,
              pinY: 1,
              width: 2,
              height: 1,
            ).copyWith(
              fill: const VsdxFill(
                foreground: VsdxColor(0xFFFF0000),
                pattern: 1,
              ),
              formulas: const {
                'FillForegnd': 'Inh',
                'FillPattern': 'Inh',
              },
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: otherId,
              pinX: 4,
              pinY: 1,
              width: 1,
              height: 1,
            ),
          ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.group({id, otherId}, groupId: gid),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final ff = RegExp(r'<Cell N="FillForegnd"[^/]*/>').firstMatch(pageXml);
    final fp = RegExp(r'<Cell N="FillPattern"[^/]*/>').firstMatch(pageXml);
    expect(ff, isNotNull);
    expect(fp, isNotNull);
    expect(ff!.group(0)!.contains('F="Inh"'), isFalse);
    expect(fp!.group(0)!.contains('F="Inh"'), isFalse);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.fill.foreground?.value, 0xFFFF0000);
    expect(after.fill.pattern, 1);
  });

  test('FlipX F=Inh scrubs when flip is false', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    if (pageXml.contains('N="FlipX"')) {
      pageXml = pageXml.replaceFirst(
        RegExp(r'<Cell N="FlipX"[^/]*/>'),
        '<Cell N="FlipX" V="0" F="Inh"/>',
      );
    } else {
      pageXml = pageXml.replaceFirst(
        '</Shape>',
        '<Cell N="FlipX" V="0" F="Inh"/></Shape>',
      );
    }
    final tainted = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(tainted);
    // Touch a style cell so patch runs while Flip stays false.
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          fill: s.fill.copyWith(foreground: const VsdxColor(0xFF00FF00)),
        ),
      ),
    );
    final out = writer.write(originalBytes: tainted, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final flip = RegExp(r'<Cell N="FlipX"[^/]*/>').firstMatch(pageXml);
    expect(flip, isNotNull);
    expect(flip!.group(0)!.contains('F="Inh"'), isFalse);
    expect(flip.group(0)!.contains('V="0"'), isTrue);
  });

  test('TextBkgnd F=Inh scrubs when background is clear', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          richText: const VsdxRichText(
            runs: [VsdxTextRun(text: 'Hi')],
          ),
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    if (pageXml.contains('N="TextBkgnd"')) {
      pageXml = pageXml.replaceFirst(
        RegExp(r'<Cell N="TextBkgnd"[^/]*/>'),
        '<Cell N="TextBkgnd" V="0" F="Inh"/>',
      );
    } else {
      pageXml = pageXml.replaceFirst(
        '</Shape>',
        '<Cell N="TextBkgnd" V="0" F="Inh"/></Shape>',
      );
    }
    final tainted = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(tainted);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          fill: s.fill.copyWith(foreground: const VsdxColor(0xFF0000FF)),
        ),
      ),
    );
    final out = writer.write(originalBytes: tainted, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final tb = RegExp(r'<Cell N="TextBkgnd"[^/]*/>').firstMatch(pageXml);
    expect(tb, isNotNull);
    expect(tb!.group(0)!.contains('F="Inh"'), isFalse);
    expect(tb.group(0)!.contains('V="0"'), isTrue);
  });

  test('Foreign ImgWidth F=Inh becomes Width*1 on patch', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final picId = doc.pages.first.nextFreeShapeId();
    const part = '/visio/media/image_inh_wh.png';
    final payload = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      5,
      4,
      3,
      2,
    ]);
    final pic = VsdxShapeFactory.picture(
      id: picId,
      pinX: 2,
      pinY: 2,
      width: 1.5,
      height: 1,
      imagePartName: part,
    );
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: payload, mimeType: 'image/png'),
          ),
        )
        .replacePage(0, doc.pages.first.addShape(pic));
    final mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="ImgWidth"[^/]*/>'),
      '<Cell N="ImgWidth" V="1.5" F="Inh"/>',
    );
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="ImgHeight"[^/]*/>'),
      '<Cell N="ImgHeight" V="1" F="Inh"/>',
    );
    final tainted = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(tainted);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        picId,
        (s) => s.copyWith(imageTransparency: 0.1),
      ),
    );
    final out = writer.write(originalBytes: tainted, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final w = RegExp(r'<Cell N="ImgWidth"[^/]*/>').firstMatch(pageXml);
    final h = RegExp(r'<Cell N="ImgHeight"[^/]*/>').firstMatch(pageXml);
    expect(w, isNotNull);
    expect(h, isNotNull);
    expect(w!.group(0)!.contains('F="Inh"'), isFalse);
    expect(h!.group(0)!.contains('F="Inh"'), isFalse);
    expect(w.group(0)!.contains('Width*1'), isTrue);
    expect(h.group(0)!.contains('Height*1'), isTrue);
  });

  test('Foreign ImgWidth F=Inh keeps custom crop as literal', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final picId = doc.pages.first.nextFreeShapeId();
    const part = '/visio/media/image_inh_crop.png';
    final payload = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      9,
      8,
      7,
      6,
    ]);
    final pic = VsdxShapeFactory.picture(
      id: picId,
      pinX: 2,
      pinY: 2,
      width: 1.5,
      height: 1,
      imagePartName: part,
    ).copyWith(imgWidthInches: 0.5, imgHeightInches: 0.4);
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: payload, mimeType: 'image/png'),
          ),
        )
        .replacePage(0, doc.pages.first.addShape(pic));
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="ImgWidth"[^/]*/>'),
      '<Cell N="ImgWidth" V="0.5" F="Inh"/>',
    );
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="ImgHeight"[^/]*/>'),
      '<Cell N="ImgHeight" V="0.4" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(picId)!.imgWidthInches,
        closeTo(0.5, 1e-6));
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        picId,
        (s) => s.copyWith(imageTransparency: 0.05),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final w = RegExp(r'<Cell N="ImgWidth"[^/]*/>').firstMatch(pageXml)!;
    final h = RegExp(r'<Cell N="ImgHeight"[^/]*/>').firstMatch(pageXml)!;
    expect(w.group(0)!.contains('F="Inh"'), isFalse);
    expect(h.group(0)!.contains('F="Inh"'), isFalse);
    expect(w.group(0)!.contains('Width*1'), isFalse);
    expect(
        double.parse(RegExp(r'V="([^"]+)"').firstMatch(w.group(0)!)!.group(1)!),
        closeTo(0.5, 1e-6));
    expect(
        double.parse(RegExp(r'V="([^"]+)"').firstMatch(h.group(0)!)!.group(1)!),
        closeTo(0.4, 1e-6));
  });

  test('TxtAngle F=Inh scrubs and is not re-synced from formulas', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          text: 'Label',
          richText: const VsdxRichText(
            runs: [VsdxTextRun(text: 'Label')],
            textBlock: VsdxTextBlock(angleRad: 0),
          ),
          formulas: const {'TxtAngle': 'Inh'},
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="TxtAngle"[^/]*/>'),
      '<Cell N="TxtAngle" V="0" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    // Keep formulas map carrying Inh (as after a typical reopen) and move.
    final shape = doc.pages.first.findShapeById(id)!;
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          pinX: s.pinX + 0.1,
          formulas: {...s.formulas, 'TxtAngle': 'Inh'},
        ),
      ),
    );
    expect(shape.richText.textBlock.angleRad, 0);
    final out = writer.write(originalBytes: mid, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = RegExp(r'<Cell N="TxtAngle"[^/]*/>').firstMatch(pageXml)!;
    expect(cell.group(0)!.contains('F="Inh"'), isFalse);
    expect(cell.group(0)!.contains('V="0"'), isTrue);
  });

  test('BeginX/PinX F=Inh scrub and are not re-synced from formulas', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(
          id: id,
          ax: 1,
          ay: 1,
          bx: 3,
          by: 2,
        ).copyWith(
          formulas: const {'BeginX': 'Inh', 'PinX': 'Inh'},
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="BeginX"[^/]*/>'),
      '<Cell N="BeginX" V="1" F="Inh"/>',
    );
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="PinX"[^/]*/>'),
      '<Cell N="PinX" V="2" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          pinY: s.pinY + 0.05,
          formulas: {...s.formulas, 'BeginX': 'Inh', 'PinX': 'Inh'},
        ),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final begin = RegExp(r'<Cell N="BeginX"[^/]*/>').firstMatch(pageXml)!;
    expect(begin.group(0)!.contains('F="Inh"'), isFalse,
        reason: begin.group(0));
    final pin = RegExp(r'<Cell N="PinX"[^/]*/>').firstMatch(pageXml)!;
    // Connector ensure may replace Inh with (BeginX+EndX)*0.5 — never Inh.
    expect(pin.group(0)!.contains('F="Inh"'), isFalse, reason: pin.group(0));
  });

  test('Angle F=Inh scrubbed on group rebuild', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final otherId = id + 1;
    final gid = otherId + 1;
    const angle = 0.5;
    doc = doc.replacePage(
      0,
      doc.pages.first
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id,
              pinX: 1,
              pinY: 1,
              width: 2,
              height: 1,
            ).copyWith(
              angleRad: angle,
              formulas: const {'Angle': 'Inh'},
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: otherId,
              pinX: 4,
              pinY: 1,
              width: 1,
              height: 1,
            ),
          ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.group({id, otherId}, groupId: gid),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final ang = RegExp(r'<Cell N="Angle"[^/]*/>').firstMatch(pageXml);
    expect(ang, isNotNull);
    expect(ang!.group(0)!.contains('F="Inh"'), isFalse);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.angleRad, closeTo(angle, 1e-6));
  });

  test('SoftEdgesSize=0 injected when cell missing', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    // Strip SoftEdgesSize so patch must re-inject literal 0.
    pageXml = pageXml.replaceAll(RegExp(r'<Cell N="SoftEdgesSize"[^/]*/>'), '');
    final tainted = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(tainted);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          fill: s.fill.copyWith(foreground: const VsdxColor(0xFF112233)),
        ),
      ),
    );
    final out = writer.write(originalBytes: tainted, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="SoftEdgesSize"'), isTrue);
    final soft = RegExp(r'<Cell N="SoftEdgesSize"[^/]*/>').firstMatch(pageXml);
    expect(soft, isNotNull);
    expect(soft!.group(0)!.contains('F="Inh"'), isFalse);
  });

  test('disabled shadow injects ShadowPattern=0 when missing', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml
        .replaceAll(RegExp(r'<Cell N="ShadowPattern"[^/]*/>'), '')
        .replaceAll(RegExp(r'<Cell N="ShdwPattern"[^/]*/>'), '');
    final tainted = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(tainted);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          fill: s.fill.copyWith(foreground: const VsdxColor(0xFF445566)),
        ),
      ),
    );
    final out = writer.write(originalBytes: tainted, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="ShadowPattern" V="0"'), isTrue);
    expect(pageXml.contains('N="ShdwPattern" V="0"'), isTrue);
  });

  test('PageSheet ShdwOffsetX F=Inh scrubbed when value unchanged', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pagesFile =
        archive.firstWhere((f) => f.name.endsWith('pages/pages.xml'));
    var pagesXml = utf8.decode(pagesFile.content as List<int>);
    expect(pagesXml.contains('N="ShdwOffsetX"'), isTrue);
    pagesXml = pagesXml.replaceFirst(
      RegExp(r'<Cell N="ShdwOffsetX"[^/]*/>'),
      '<Cell N="ShdwOffsetX" V="0.125" F="Inh"/>',
    );
    final tainted = _rezipWith(mid, pagesFile.name, utf8.encode(pagesXml));
    doc = parser.parse(tainted);
    // PageSheet model equals defaults — still must scrub Inh on write.
    final out = writer.write(originalBytes: tainted, edited: doc);
    pagesXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.endsWith('pages/pages.xml'))
          .content as List<int>,
    );
    final shdw = RegExp(r'<Cell N="ShdwOffsetX"[^/]*/>').firstMatch(pagesXml);
    expect(shdw, isNotNull);
    expect(shdw!.group(0)!.contains('F="Inh"'), isFalse);
  });

  test('PageColor F=Inh dropped when model background is null', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    expect(doc.pages.first.backgroundColor, isNull);
    final mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pagesFile =
        archive.firstWhere((f) => f.name.endsWith('pages/pages.xml'));
    var pagesXml = utf8.decode(pagesFile.content as List<int>);
    if (pagesXml.contains('N="PageColor"')) {
      pagesXml = pagesXml.replaceFirst(
        RegExp(r'<Cell N="PageColor"[^/]*/>'),
        '<Cell N="PageColor" V="#ffcccc" F="Inh"/>',
      );
    } else {
      pagesXml = pagesXml.replaceFirst(
        '<PageSheet>',
        '<PageSheet><Cell N="PageColor" V="#ffcccc" F="Inh"/>',
      );
    }
    final tainted = _rezipWith(mid, pagesFile.name, utf8.encode(pagesXml));
    doc = parser.parse(tainted);
    expect(doc.pages.first.backgroundColor, isNull);
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        widthInches: doc.pages.first.widthInches + 0.1,
      ),
    );
    final out = writer.write(originalBytes: tainted, edited: doc);
    pagesXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.endsWith('pages/pages.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(r'N="PageColor"[^>]*F="Inh"').hasMatch(pagesXml),
      isFalse,
    );
  });

  test('DocumentSettings PageColor/GlueType round-trip and Inh scrub', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(
          settings: const VsdxDocumentSettings(
            defaultPageBackgroundColor: VsdxColor(0xFFEEFFEE),
            glueType: 9,
            snapEnabled: false,
            gridDensityX: 2,
            gridDensityY: 3,
          ),
        );
    var mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    expect(doc.settings.defaultPageBackgroundColor?.value, 0xFFEEFFEE);
    expect(doc.settings.glueType, 9);
    expect(doc.settings.snapEnabled, isFalse);
    expect(doc.settings.gridDensityX, 2);
    expect(doc.settings.gridDensityY, 3);

    final archive = ZipDecoder().decodeBytes(mid);
    final docFile = archive.firstWhere((f) => f.name.endsWith('document.xml'));
    var docXml = utf8.decode(docFile.content as List<int>);
    docXml = docXml.replaceFirst(
      RegExp(r'<Cell N="PageColor"[^/]*/>'),
      '<Cell N="PageColor" V="#eeffee" F="Inh"/>',
    );
    docXml = docXml.replaceFirst(
      RegExp(r'<Cell N="GlueType"[^/]*/>'),
      '<Cell N="GlueType" V="9" F="Inh"/>',
    );
    mid = _rezipWith(mid, docFile.name, utf8.encode(docXml));
    doc = parser.parse(mid);
    // PageColor Inh → null; GlueType Inh → default 0.
    expect(doc.settings.defaultPageBackgroundColor, isNull);
    expect(doc.settings.glueType, 0);
    final out = writer.write(originalBytes: mid, edited: doc);
    docXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.endsWith('document.xml'))
          .content as List<int>,
    );
    expect(RegExp(r'N="PageColor"').hasMatch(docXml), isFalse);
    final glue = RegExp(r'<Cell N="GlueType"[^/]*/>').firstMatch(docXml);
    expect(glue, isNotNull);
    expect(glue!.group(0)!.contains('F="Inh"'), isFalse);
    expect(glue.group(0)!.contains('V="0"'), isTrue);
  });

  test('PageWidth F=Inh scrubbed when size unchanged', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pagesFile =
        archive.firstWhere((f) => f.name.endsWith('pages/pages.xml'));
    var pagesXml = utf8.decode(pagesFile.content as List<int>);
    final widthMatch =
        RegExp(r'<Cell N="PageWidth"[^/]*/>').firstMatch(pagesXml);
    expect(widthMatch, isNotNull);
    final v =
        RegExp(r'V="([^"]*)"').firstMatch(widthMatch!.group(0)!)!.group(1)!;
    pagesXml = pagesXml.replaceFirst(
      RegExp(r'<Cell N="PageWidth"[^/]*/>'),
      '<Cell N="PageWidth" V="$v" F="Inh"/>',
    );
    final tainted = _rezipWith(mid, pagesFile.name, utf8.encode(pagesXml));
    doc = parser.parse(tainted);
    expect(doc.pages.first.widthInches, closeTo(double.parse(v), 1e-6));
    final out = writer.write(originalBytes: tainted, edited: doc);
    pagesXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.endsWith('pages/pages.xml'))
          .content as List<int>,
    );
    final cell = RegExp(r'<Cell N="PageWidth"[^/]*/>').firstMatch(pagesXml);
    expect(cell, isNotNull);
    expect(cell!.group(0)!.contains('F="Inh"'), isFalse);
  });

  test('cleared connection points stay empty across second save', () {
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
          width: 2,
          height: 1,
        ).copyWith(
          connectionPoints: VsdxPage.defaultConnectionPoints(2, 1),
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(id)!.connectionPoints.length, 5);
    // Delete every blue point.
    var page = doc.pages.first;
    while (page.findShapeById(id)!.connectionPoints.isNotEmpty) {
      page = page.removeConnectionPoint(id, 0);
    }
    doc = doc.replacePage(0, page);
    final cleared = writer.write(originalBytes: mid, edited: doc);
    expect(
      parser.parse(cleared).pages.first.findShapeById(id)!.connectionPoints,
      isEmpty,
    );
    // Second save must not re-inject defaults.
    final again = writer.write(
      originalBytes: cleared,
      edited: parser.parse(cleared),
    );
    expect(
      parser.parse(again).pages.first.findShapeById(id)!.connectionPoints,
      isEmpty,
    );
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(again)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="Connection"'), isFalse);
  });

  test('clearing fieldSpans rewrites Text and drops fld markers', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          text: 'W',
          fields: const [
            VsdxFieldRow(ix: 0, value: '2', valueFormula: 'Width'),
          ],
          richText: const VsdxRichText(
            runs: [
              VsdxTextRun(
                text: 'W',
                fieldSpans: [VsdxFieldSpan(start: 0, length: 1, ix: 0)],
              ),
            ],
          ),
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    var pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(mid)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('<fld'), isTrue);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          fields: const <VsdxFieldRow>[],
          richText: VsdxRichText(
            runs: [
              VsdxTextRun(
                text: s.richText.plainText,
                charStyle: s.richText.runs.first.charStyle,
                paraStyle: s.richText.runs.first.paraStyle,
              ),
            ],
          ),
        ),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('<fld'), isFalse);
    expect(pageXml.contains('N="Field"'), isFalse);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.fields, isEmpty);
    expect(after.richText.runs.first.fieldSpans, isEmpty);
  });

  test('NoShow F=Inh scrubbed on geometry ensure', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    if (pageXml.contains('N="NoShow"')) {
      pageXml = pageXml.replaceFirst(
        RegExp(r'<Cell N="NoShow"[^/]*/>'),
        '<Cell N="NoShow" V="0" F="Inh"/>',
      );
    } else {
      pageXml = pageXml.replaceFirst(
        '<Section N="Geometry"',
        '<Section N="Geometry"><Cell N="NoShow" V="0" F="Inh"/>',
      );
    }
    final tainted = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(tainted);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          fill: s.fill.copyWith(foreground: const VsdxColor(0xFFABCDEF)),
        ),
      ),
    );
    final out = writer.write(originalBytes: tainted, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final noShow = RegExp(r'<Cell N="NoShow"[^/]*/>').firstMatch(pageXml);
    expect(noShow, isNotNull);
    expect(noShow!.group(0)!.contains('F="Inh"'), isFalse);
  });

  test('QuickStyleFillMatrix F=Inh scrubbed when value unchanged', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(quickStyleFillMatrix: 1),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="QuickStyleFillMatrix"[^/]*/>'),
      '<Cell N="QuickStyleFillMatrix" V="1" F="Inh"/>',
    );
    final tainted = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(tainted);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          fill: s.fill.copyWith(foreground: const VsdxColor(0xFF112233)),
        ),
      ),
    );
    final out = writer.write(originalBytes: tainted, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final m =
        RegExp(r'<Cell N="QuickStyleFillMatrix"[^/]*/>').firstMatch(pageXml);
    expect(m, isNotNull);
    expect(m!.group(0)!.contains('F="Inh"'), isFalse);
  });

  test('Character Font/LangID clear on patch', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          text: 'Hi',
          richText: const VsdxRichText(
            runs: [
              VsdxTextRun(
                text: 'Hi',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Georgia',
                  asianFont: 'SimSun',
                  langId: 'zh-CN',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) {
          final run = s.richText.runs.first;
          return s.copyWith(
            richText: s.richText.copyWith(
              runs: [
                run.copyWith(
                  charStyle: run.charStyle.copyWith(
                    clearFontFamily: true,
                    clearAsianFont: true,
                    clearLangId: true,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="Font"'), isFalse);
    expect(pageXml.contains('N="AsianFont"'), isFalse);
    expect(pageXml.contains('N="LangID"'), isFalse);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.richText.runs.first.charStyle.fontFamily, isNull);
    expect(after.richText.runs.first.charStyle.asianFont, isNull);
    expect(after.richText.runs.first.charStyle.langId, isNull);
  });

  test('empty text drops Character/Paragraph on patch', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          text: 'Hi',
          richText: const VsdxRichText(
            runs: [
              VsdxTextRun(
                text: 'Hi',
                charStyle: VsdxCharStyle(fontFamily: 'Georgia'),
              ),
            ],
          ),
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(text: '', richText: VsdxRichText.empty),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="Character"'), isFalse);
    expect(pageXml.contains('N="Paragraph"'), isFalse);
    expect(pageXml.contains('Georgia'), isFalse);
  });

  test('User Prompt and Property SortKey clear on patch', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          userCells: const [
            VsdxUserCell(name: 'Row_1', value: '1', prompt: 'hint'),
          ],
          userProperties: const [
            VsdxUserProperty(
              name: 'Prop1',
              value: 'x',
              sortKey: '01',
              langId: 'en-US',
              calendar: 0,
            ),
          ],
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          userCells: [
            s.userCells.first.copyWith(clearPrompt: true),
          ],
          userProperties: [
            s.userProperties.first.copyWith(
              clearSortKey: true,
              clearLangId: true,
              clearCalendar: true,
            ),
          ],
        ),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="Prompt"'), isFalse);
    expect(pageXml.contains('N="SortKey"'), isFalse);
    // LangID/Calendar may appear elsewhere; check inside Property row context.
    expect(
      RegExp(r'<Section N="Property"[\s\S]*?N="LangID"').hasMatch(pageXml),
      isFalse,
    );
    expect(
      RegExp(r'<Section N="Property"[\s\S]*?N="Calendar"').hasMatch(pageXml),
      isFalse,
    );
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.userCells.first.prompt, isNull);
    expect(after.userProperties.first.sortKey, isNull);
    expect(after.userProperties.first.langId, isNull);
    expect(after.userProperties.first.calendar, isNull);
  });

  test('Layer Color F=Inh keeps cached value through synthesis', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        layers: const [
          VsdxLayer(id: 0, name: 'Default'),
        ],
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pagesFile =
        archive.firstWhere((f) => f.name.endsWith('pages/pages.xml'));
    var pagesXml = utf8.decode(pagesFile.content as List<int>);
    // libvisio consumes the cached V even when the formula is Inh.
    if (!pagesXml.contains('N="Color"')) {
      pagesXml = pagesXml.replaceFirstMapped(
        RegExp(r'(<Section N="Layer">\s*<Row[^>]*>)'),
        (m) => '${m.group(1)}<Cell N="Color" V="#ff0000" F="Inh"/>',
      );
    } else {
      pagesXml = pagesXml.replaceFirst(
        RegExp(r'<Cell N="Color"[^/]*/>'),
        '<Cell N="Color" V="#ff0000" F="Inh"/>',
      );
    }
    mid = _rezipWith(mid, pagesFile.name, utf8.encode(pagesXml));
    doc = parser.parse(mid);
    expect(
      doc.pages.first.layers.first.color,
      const VsdxColor(0xFFFF0000),
    );
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        widthInches: doc.pages.first.widthInches + 0.1,
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.endsWith('pages/pages.xml'))
          .content as List<int>,
    );
    final colorCell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) => e.name.local == 'Cell' && e.getAttribute('N') == 'Color',
        );
    expect(colorCell.getAttribute('F'), isNull);
    expect(colorCell.getAttribute('V'), '#FF0000');
    expect(
      parser.parse(out).pages.first.layers.first.color,
      const VsdxColor(0xFFFF0000),
    );
  });

  test('Layer NameUniv F=Inh keeps cached value through synthesis', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        layers: const [
          VsdxLayer(id: 0, name: 'Default'),
        ],
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pagesFile =
        archive.firstWhere((f) => f.name.endsWith('pages/pages.xml'));
    var pagesXml = utf8.decode(pagesFile.content as List<int>);
    if (!pagesXml.contains('N="NameUniv"')) {
      pagesXml = pagesXml.replaceFirstMapped(
        RegExp(r'(<Section N="Layer">\s*<Row[^>]*>)'),
        (m) => '${m.group(1)}<Cell N="NameUniv" V="Default" F="Inh"/>',
      );
    } else {
      pagesXml = pagesXml.replaceFirst(
        RegExp(r'<Cell N="NameUniv"[^/]*/>'),
        '<Cell N="NameUniv" V="Default" F="Inh"/>',
      );
    }
    mid = _rezipWith(mid, pagesFile.name, utf8.encode(pagesXml));
    doc = parser.parse(mid);
    expect(doc.pages.first.layers.first.nameUniv, 'Default');
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        widthInches: doc.pages.first.widthInches + 0.1,
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.endsWith('pages/pages.xml'))
          .content as List<int>,
    );
    final nameUnivCell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) => e.name.local == 'Cell' && e.getAttribute('N') == 'NameUniv',
        );
    expect(nameUnivCell.getAttribute('F'), isNull);
    expect(nameUnivCell.getAttribute('V'), 'Default');
    expect(parser.parse(out).pages.first.layers.first.nameUniv, 'Default');
  });

  test('Layer Color/NameUniv clear on patch', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        layers: const [
          VsdxLayer(
            id: 0,
            name: 'Default',
            color: VsdxColor(0xFFFF0000),
            nameUniv: 'Default',
          ),
        ],
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    expect(doc.pages.first.layers.first.color, isNotNull);
    expect(doc.pages.first.layers.first.nameUniv, 'Default');
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        layers: [
          doc.pages.first.layers.first.copyWith(
            clearColor: true,
            clearNameUniv: true,
          ),
        ],
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(r'<Section N="Layer"[\s\S]*?N="Color"').hasMatch(pageXml),
      isFalse,
    );
    expect(
      RegExp(r'<Section N="Layer"[\s\S]*?N="NameUniv"').hasMatch(pageXml),
      isFalse,
    );
    final layer = parser.parse(out).pages.first.layers.first;
    expect(layer.color, isNull);
    expect(layer.nameUniv, isNull);
  });

  test('PageSheet LineToLine/LineJumpFactor clear on patch', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        pageSheet: doc.pages.first.pageSheet.copyWith(
          lineToLineXInches: 0.13,
          lineToLineYInches: 0.13,
          lineJumpFactorX: 0.65,
          lineJumpFactorY: 0.65,
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    expect(doc.pages.first.pageSheet.lineJumpFactorX, closeTo(0.65, 1e-6));
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        pageSheet: doc.pages.first.pageSheet.copyWith(
          clearLineToLineX: true,
          clearLineToLineY: true,
          clearLineJumpFactorX: true,
          clearLineJumpFactorY: true,
        ),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pagesXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.endsWith('pages/pages.xml'))
          .content as List<int>,
    );
    expect(pagesXml.contains('N="LineToLineX"'), isFalse);
    expect(pagesXml.contains('N="LineToLineY"'), isFalse);
    expect(pagesXml.contains('N="LineJumpFactorX"'), isFalse);
    expect(pagesXml.contains('N="LineJumpFactorY"'), isFalse);
    final sheet = parser.parse(out).pages.first.pageSheet;
    expect(sheet.lineToLineXInches, isNull);
    expect(sheet.lineToLineYInches, isNull);
    expect(sheet.lineJumpFactorX, isNull);
    expect(sheet.lineJumpFactorY, isNull);
  });

  test('Paragraph BulletStr/Font clear on patch', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          text: 'Item',
          richText: const VsdxRichText(
            runs: [
              VsdxTextRun(
                text: 'Item',
                paraStyle: VsdxParaStyle(
                  bullet: 1,
                  bulletStr: '•',
                  bulletFont: 'Segoe UI',
                  bulletFontSizeInches: 0.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) {
          final run = s.richText.runs.first;
          return s.copyWith(
            richText: s.richText.copyWith(
              runs: [
                run.copyWith(
                  paraStyle: run.paraStyle.copyWith(
                    bullet: 0,
                    clearBulletStr: true,
                    clearBulletFont: true,
                    clearBulletFontSize: true,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="BulletStr"'), isFalse);
    expect(pageXml.contains('N="BulletFont"'), isFalse);
    expect(pageXml.contains('N="BulletFontSize"'), isFalse);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.richText.runs.first.paraStyle.bulletStr, isNull);
    expect(after.richText.runs.first.paraStyle.bulletFont, isNull);
    expect(after.richText.runs.first.paraStyle.bulletFontSizeInches, isNull);
  });

  test('Hyperlink Description clear on patch', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          hyperlinks: const [
            VsdxHyperlink(
              id: 1,
              address: 'https://example.com',
              description: 'Example',
            ),
          ],
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          hyperlinks: [
            s.hyperlinks.first.copyWith(clearDescription: true),
          ],
        ),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(r'<Section N="Hyperlink"[\s\S]*?N="Description"')
          .hasMatch(pageXml),
      isFalse,
    );
    expect(
      parser
          .parse(out)
          .pages
          .first
          .findShapeById(id)!
          .hyperlinks
          .first
          .description,
      isNull,
    );
  });

  test('Hyperlink SubAddress/ExtraInfo F=Inh scrubbed when model equal', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          hyperlinks: const [
            VsdxHyperlink(
              id: 1,
              address: 'https://example.com',
              subAddress: 'page2',
              extraInfo: 'utm=1',
            ),
          ],
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(id)!.hyperlinks.first.subAddress,
        'page2');
    expect(
        doc.pages.first.findShapeById(id)!.hyperlinks.first.extraInfo, 'utm=1');
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="SubAddress"[^/]*/>'),
      '<Cell N="SubAddress" V="page2" F="Inh"/>',
    );
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="ExtraInfo"[^/]*/>'),
      '<Cell N="ExtraInfo" V="utm=1" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    // Keep pre-mutation model (values still set); only bump pinX so equal-path
    // scrub runs against originalBytes that still carry F=Inh.
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    for (final name in ['SubAddress', 'ExtraInfo']) {
      final cell = XmlDocument.parse(pageXml)
          .descendants
          .whereType<XmlElement>()
          .firstWhere(
            (e) => e.name.local == 'Cell' && e.getAttribute('N') == name,
          );
      expect(cell.getAttribute('F'), isNull, reason: name);
      expect(cell.getAttribute('V'), name == 'SubAddress' ? 'page2' : 'utm=1');
    }
  });

  test('unbound FillBkgnd F=Inh dropped when model background is null', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
          fill: const VsdxFill(
            pattern: 1,
            foreground: VsdxColor(0xFFFF0000),
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    if (pageXml.contains('N="FillBkgnd"')) {
      pageXml = pageXml.replaceFirst(
        RegExp(r'<Cell N="FillBkgnd"[^/]*/>'),
        '<Cell N="FillBkgnd" V="#00ff00" F="Inh"/>',
      );
    } else {
      pageXml = pageXml.replaceFirst(
        '</Shape>',
        '<Cell N="FillBkgnd" V="#00ff00" F="Inh"/></Shape>',
      );
    }
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(id)!.fill.background, isNull);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(RegExp(r'N="FillBkgnd"[^>]*F="Inh"').hasMatch(pageXml), isFalse);
  });

  test('Character Color clear + AsianFont stays cleared after group rebuild',
      () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final otherId = id + 1;
    final gid = id + 2;
    doc = doc.replacePage(
      0,
      doc.pages.first
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id,
              pinX: 1,
              pinY: 1,
              width: 2,
              height: 1,
            ).copyWith(
              text: 'Hi',
              richText: const VsdxRichText(
                runs: [
                  VsdxTextRun(
                    text: 'Hi',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Georgia',
                      asianFont: 'SimSun',
                      color: VsdxColor(0xFFCC0000),
                    ),
                  ),
                ],
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: otherId,
              pinX: 4,
              pinY: 1,
              width: 1,
              height: 1,
            ),
          ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) {
          final run = s.richText.runs.first;
          return s.copyWith(
            richText: s.richText.copyWith(
              runs: [
                run.copyWith(
                  charStyle: run.charStyle.copyWith(
                    clearAsianFont: true,
                    clearColor: true,
                    clearThemeColorIndex: true,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    final cleared = writer.write(originalBytes: mid, edited: doc);
    doc = parser.parse(cleared);
    doc = doc.replacePage(
      0,
      doc.pages.first.group({id, otherId}, groupId: gid),
    );
    final out = writer.write(originalBytes: cleared, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    // Latin text with cleared AsianFont must not revive on group rebuild.
    final shapeXml = RegExp(
      r'<Shape[^>]*ID="' + id.toString() + r'"[\s\S]*?</Shape>',
    ).firstMatch(pageXml)?.group(0);
    expect(shapeXml, isNotNull);
    expect(shapeXml!.contains('N="AsianFont"'), isFalse);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.richText.runs.first.charStyle.asianFont, isNull);
    expect(after.richText.runs.first.charStyle.color, isNull);
  });

  test('Control Prompt clear on patch', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          controls: const [
            VsdxControlRow(name: 'Row_1', x: 0.5, y: 0.5, prompt: 'Drag me'),
          ],
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(id)!.controls.first.prompt, 'Drag me');
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          controls: [
            s.controls.first.copyWith(clearPrompt: true),
          ],
        ),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(r'<Section N="Control"[\s\S]*?N="Prompt"').hasMatch(pageXml),
      isFalse,
    );
    expect(
      parser.parse(out).pages.first.findShapeById(id)!.controls.first.prompt,
      isNull,
    );
  });

  test('PageSheet LineJumpCode F=Inh dropped when model is null', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pagesFile =
        archive.firstWhere((f) => f.name.endsWith('pages/pages.xml'));
    var pagesXml = utf8.decode(pagesFile.content as List<int>);
    if (pagesXml.contains('N="LineJumpCode"')) {
      pagesXml = pagesXml.replaceFirst(
        RegExp(r'<Cell N="LineJumpCode"[^/]*/>'),
        '<Cell N="LineJumpCode" V="1" F="Inh"/>',
      );
    } else {
      pagesXml = pagesXml.replaceFirst(
        '<PageSheet>',
        '<PageSheet><Cell N="LineJumpCode" V="1" F="Inh"/>',
      );
    }
    mid = _rezipWith(mid, pagesFile.name, utf8.encode(pagesXml));
    doc = parser.parse(mid);
    expect(doc.pages.first.pageSheet.lineJumpCode, isNull);
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        widthInches: doc.pages.first.widthInches + 0.1,
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    pagesXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.endsWith('pages/pages.xml'))
          .content as List<int>,
    );
    expect(RegExp(r'N="LineJumpCode"[^>]*F="Inh"').hasMatch(pagesXml), isFalse);
  });

  test('ThemeIndex F=Inh scrubbed when value unchanged', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(themeIndex: 1),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(id)!.themeIndex, 1);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="ThemeIndex"[^/]*/>'),
      '<Cell N="ThemeIndex" V="1" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    // Keep pre-mutation model (themeIndex: 1); pin bump triggers equal-path scrub.
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(RegExp(r'N="ThemeIndex"[^>]*F="Inh"').hasMatch(pageXml), isFalse);
    expect(RegExp(r'N="ThemeIndex"[^>]*V="1"').hasMatch(pageXml), isTrue);
  });

  test('ThemeIndex F=Inh dropped when model themeIndex is null', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(id)!.themeIndex, isNull);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    // Inject before </Shape> without re-parse so model stays null.
    final close = pageXml.lastIndexOf('</Shape>');
    pageXml =
        '${pageXml.substring(0, close)}<Cell N="ThemeIndex" V="1" F="Inh"/>${pageXml.substring(close)}';
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(RegExp(r'N="ThemeIndex"[^>]*F="Inh"').hasMatch(pageXml), isFalse);
  });

  test('Property Label F=Inh scrubbed when model label is null', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          userProperties: const [
            VsdxUserProperty(name: 'Prop.Cost', value: '10'),
          ],
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    expect(
        doc.pages.first.findShapeById(id)!.userProperties.first.label, isNull);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      '<Row N="Prop.Cost" IX="1">',
      '<Row N="Prop.Cost" IX="1"><Cell N="Label" V="Cost" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(r'<Section N="Property"[\s\S]*?N="Label"[^>]*F="Inh"')
          .hasMatch(pageXml),
      isFalse,
    );
  });

  test('Connection X/Prompt F=Inh scrubbed when points equal', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          connectionPoints: const [
            VsdxConnectionPoint(1, 0.5, dirX: 1, dirY: 0),
          ],
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      '<Section N="Connection"><Row IX="0"><Cell N="X" V="1"/>',
      '<Section N="Connection"><Row IX="0">'
          '<Cell N="Prompt" V="tip" F="Inh"/>'
          '<Cell N="X" V="1" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(r'<Section N="Connection"[\s\S]*?N="X"[^>]*F="Inh"')
          .hasMatch(pageXml),
      isFalse,
    );
    expect(
      RegExp(r'<Section N="Connection"[\s\S]*?N="Prompt"[^>]*F="Inh"')
          .hasMatch(pageXml),
      isFalse,
    );
  });

  test('Control Prompt F=Inh scrubbed when model prompt is null', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          controls: const [
            VsdxControlRow(name: 'Row_1', x: 0.5, y: 0.5),
          ],
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      '<Row N="Row_1">',
      '<Row N="Row_1"><Cell N="Prompt" V="tip" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(r'<Section N="Control"[\s\S]*?N="Prompt"[^>]*F="Inh"')
          .hasMatch(pageXml),
      isFalse,
    );
  });

  test('Field UICat F=Inh scrubbed when model uiCat is null', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          text: '42',
          fields: const [VsdxFieldRow(ix: 0, value: '42', type: 0)],
          richText: VsdxRichText(runs: [
            VsdxTextRun(
              text: '42',
              fieldSpans: const [VsdxFieldSpan(ix: 0, start: 0, length: 2)],
            ),
          ]),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(id)!.fields.first.uiCat, isNull);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      '<Section N="Field"><Row IX="0">',
      '<Section N="Field"><Row IX="0"><Cell N="UICat" V="1" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(r'<Section N="Field"[\s\S]*?N="UICat"[^>]*F="Inh"')
          .hasMatch(pageXml),
      isFalse,
    );
  });

  test('ConLineJumpCode F=Inh dropped when connector prop is null', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final conn = VsdxShapeFactory.line(id: id, ax: 1, ay: 2, bx: 4, by: 2);
    doc = doc.replacePage(0, doc.pages.first.addShape(conn));
    var mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(id)!.connectorProps?.conLineJumpCode,
        isNull);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    if (pageXml.contains('N="ConLineJumpCode"')) {
      pageXml = pageXml.replaceFirst(
        RegExp(r'<Cell N="ConLineJumpCode"[^/]*/>'),
        '<Cell N="ConLineJumpCode" V="1" F="Inh"/>',
      );
    } else {
      final close = pageXml.lastIndexOf('</Shape>');
      pageXml =
          '${pageXml.substring(0, close)}<Cell N="ConLineJumpCode" V="1" F="Inh"/>${pageXml.substring(close)}';
    }
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.01),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(r'N="ConLineJumpCode"[^>]*F="Inh"').hasMatch(outXml),
      isFalse,
    );
  });

  test('Property Format formula preserved and DataLinked Inh scrubbed', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          userProperties: const [
            VsdxUserProperty(
              name: 'Prop.Cost',
              value: '10',
              format: '0.00',
              formatFormula: 'FIELDPICTURE(0)',
              dataLinked: true,
            ),
          ],
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    final prop = doc.pages.first.findShapeById(id)!.userProperties.first;
    expect(prop.formatFormula, isNotNull);
    expect(prop.dataLinked, isTrue);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="DataLinked"[^/]*/>'),
      '<Cell N="DataLinked" V="1" F="Inh"/>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(r'N="DataLinked"[^>]*F="Inh"').hasMatch(pageXml),
      isFalse,
    );
    final formatCell = XmlDocument.parse(pageXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere((e) =>
            e.name.local == 'Cell' &&
            e.getAttribute('N') == 'Format' &&
            e.parent?.parent?.getAttribute('N') == 'Property');
    expect(formatCell.getAttribute('F'), 'FIELDPICTURE(0)');
  });

  test('Tabs Position1 F=Inh scrubbed when stops equal', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          text: 'Hi',
          richText: VsdxRichText(
            runs: const [VsdxTextRun(text: 'Hi')],
            tabSets: [
              VsdxTabSet(
                ix: 0,
                stops: const [
                  VsdxTabStop(positionInches: 0.5, alignment: 0),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    // Inject Visio-native 1-based Position1 with F=Inh alongside any Position0.
    if (pageXml.contains('N="Position1"')) {
      pageXml = pageXml.replaceFirst(
        RegExp(r'<Cell N="Position1"[^/]*/>'),
        '<Cell N="Position1" V="0.5" F="Inh"/>',
      );
    } else {
      pageXml = pageXml.replaceFirst(
        '<Section N="Tabs"><Row IX="0">',
        '<Section N="Tabs"><Row IX="0"><Cell N="Position1" V="0.5" F="Inh"/>'
            '<Cell N="Alignment1" V="0"/>',
      );
    }
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(r'<Section N="Tabs"[\s\S]*?N="Position1"[^>]*F="Inh"')
          .hasMatch(pageXml),
      isFalse,
    );
    // Dual Position0+Position1 must not remain (would parse as two stops).
    expect(pageXml.contains('N="Position0"'), isFalse);
    expect(
      parser
          .parse(out)
          .pages
          .first
          .findShapeById(id)!
          .richText
          .tabSets
          .first
          .stops,
      hasLength(1),
    );
  });

  test('Tabs dual Position0+Position1 collapses to one stop', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          text: 'Hi',
          richText: VsdxRichText(
            runs: const [VsdxTextRun(text: 'Hi')],
            tabSets: [
              VsdxTabSet(
                ix: 0,
                stops: const [
                  VsdxTabStop(positionInches: 0.5, alignment: 0),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    // Force both 0-based and 1-based cells for the same stop.
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Section N="Tabs"><Row IX="0">[\s\S]*?</Row></Section>'),
      '<Section N="Tabs"><Row IX="0">'
      '<Cell N="Position0" V="0.5"/>'
      '<Cell N="Alignment0" V="0"/>'
      '<Cell N="Position1" V="0.5" F="Inh"/>'
      '<Cell N="Alignment1" V="0"/>'
      '</Row></Section>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.richText.tabSets.first.stops, hasLength(1));
    pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="Position0"'), isFalse);
    expect(pageXml.contains('N="Position1"'), isTrue);
  });

  test('Tabs dual Position0+Position1 parses as one stop', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          text: 'Hi',
          richText: VsdxRichText(
            runs: const [VsdxTextRun(text: 'Hi')],
            tabSets: [
              VsdxTabSet(
                ix: 0,
                stops: const [
                  VsdxTabStop(positionInches: 0.5, alignment: 0),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Section N="Tabs"><Row IX="0">[\s\S]*?</Row></Section>'),
      '<Section N="Tabs"><Row IX="0">'
      '<Cell N="Position0" V="0.5"/>'
      '<Cell N="Alignment0" V="0"/>'
      '<Cell N="Position1" V="0.5"/>'
      '<Cell N="Alignment1" V="0"/>'
      '</Row></Section>',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    expect(
      doc.pages.first.findShapeById(id)!.richText.tabSets.first.stops,
      hasLength(1),
    );
  });

  test('Layer ColorTrans/Status F=Inh keep cached V', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        layers: const [
          VsdxLayer(
            id: 0,
            name: 'Default',
            colorTrans: 0.25,
            status: 1,
          ),
        ],
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pagesFile =
        archive.firstWhere((f) => f.name.endsWith('pages/pages.xml'));
    var pagesXml = utf8.decode(pagesFile.content as List<int>);
    pagesXml = pagesXml.replaceFirst(
      RegExp(r'<Cell N="ColorTrans"[^/]*/>'),
      '<Cell N="ColorTrans" V="0.25" F="Inh"/>',
    );
    pagesXml = pagesXml.replaceFirst(
      RegExp(r'<Cell N="Status"[^/]*/>'),
      '<Cell N="Status" V="1" F="Inh"/>',
    );
    mid = _rezipWith(mid, pagesFile.name, utf8.encode(pagesXml));
    doc = parser.parse(mid);
    expect(doc.pages.first.layers.first.colorTrans, closeTo(0.25, 1e-6));
    expect(doc.pages.first.layers.first.status, 1);
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        widthInches: doc.pages.first.widthInches + 0.1,
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    pagesXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.endsWith('pages/pages.xml'))
          .content as List<int>,
    );
    expect(RegExp(r'N="ColorTrans"[^>]*F="Inh"').hasMatch(pagesXml), isFalse);
    expect(RegExp(r'N="Status"[^>]*F="Inh"').hasMatch(pagesXml), isFalse);
    final after = parser.parse(out).pages.first.layers.first;
    expect(after.colorTrans, closeTo(0.25, 1e-6));
    expect(after.status, 1);
  });

  test('ForeignType patch updates ForeignData attrs without rebuild', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    const part = '/visio/media/image_emf_patch.emf';
    final payload = Uint8List.fromList(<int>[0x01, 0x00, 0x00, 0x00, 0xEE]);
    final pic = VsdxShapeFactory.picture(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 1,
      height: 1,
      imagePartName: part,
    ).copyWith(foreignType: 'EnhMetaFile');
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(
              partName: part,
              bytes: payload,
              mimeType: 'image/x-emf',
            ),
          ),
        )
        .replacePage(0, doc.pages.first.addShape(pic));
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(id)!.foreignType, 'EnhMetaFile');
    // Patch-only change: switch ForeignType while keeping the same media.
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          foreignType: 'Bitmap',
          foreignCompressionType: 'PNG',
          pinX: s.pinX + 0.01,
        ),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('ForeignType="Bitmap"'), isTrue);
    expect(pageXml.contains('CompressionType="PNG"'), isTrue);
    expect(pageXml.contains('ForeignType="EnhMetaFile"'), isFalse);
  });

  test('unbound ShadowForegnd/GlowColor F=Inh dropped on equal-path', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          // Enabled effects with no solid/theme colour — rebuild omits
          // ShadowForegnd / GlowColor; residual F=Inh must still be scrubbed.
          // transparency: 0 so ShdwForegndTrans is not premultiplied into RGB.
          shadow: const VsdxShadow(
              enabled: true, pattern: 1, transparency: 0, blurInches: 0),
          glow: const VsdxGlow(enabled: true, sizeInches: 0.08),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    // Inject residual Inh colour cells that rebuild would not emit.
    // Empty V= so parse keeps color=null (non-empty V would become solid
    // when honorInh is false on a shape without an enabled master shadow).
    if (!pageXml.contains('N="ShadowForegnd"')) {
      pageXml = pageXml.replaceFirst(
        RegExp(r'(<Cell N="ShadowPattern"[^/]*/>)'),
        r'$1<Cell N="ShadowForegnd" V="" F="Inh"/>',
      );
    } else {
      pageXml = pageXml.replaceFirst(
        RegExp(r'<Cell N="ShadowForegnd"[^/]*/>'),
        '<Cell N="ShadowForegnd" V="" F="Inh"/>',
      );
    }
    if (!pageXml.contains('N="GlowColor"')) {
      pageXml = pageXml.replaceFirst(
        RegExp(r'(<Cell N="GlowSize"[^/]*/>)'),
        r'$1<Cell N="GlowColor" V="" F="Inh"/>',
      );
    } else {
      pageXml = pageXml.replaceFirst(
        RegExp(r'<Cell N="GlowColor"[^/]*/>'),
        '<Cell N="GlowColor" V="" F="Inh"/>',
      );
    }
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    final shape = doc.pages.first.findShapeById(id)!;
    expect(shape.shadow.color, isNull);
    expect(shape.glow.color, isNull);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(RegExp(r'N="ShadowForegnd"[^>]*F="Inh"').hasMatch(outXml), isFalse);
    expect(RegExp(r'N="GlowColor"[^>]*F="Inh"').hasMatch(outXml), isFalse);
  });

  test('Tabs Position0/1/2 distinct stops keep all three', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          text: 'Hi',
          richText: const VsdxRichText(
            runs: [VsdxTextRun(text: 'Hi')],
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    // Pure 0-based multi-stop row — must not drop Position0.
    if (pageXml.contains('N="Tabs"')) {
      pageXml = pageXml.replaceFirst(
        RegExp(r'<Section N="Tabs">[\s\S]*?</Section>'),
        '<Section N="Tabs"><Row IX="0">'
        '<Cell N="Position0" V="0.25"/>'
        '<Cell N="Alignment0" V="0"/>'
        '<Cell N="Position1" V="0.5"/>'
        '<Cell N="Alignment1" V="1"/>'
        '<Cell N="Position2" V="0.75"/>'
        '<Cell N="Alignment2" V="2"/>'
        '</Row></Section>',
      );
    } else {
      pageXml = pageXml.replaceFirst(
        '</Shape>',
        '<Section N="Tabs"><Row IX="0">'
            '<Cell N="Position0" V="0.25"/>'
            '<Cell N="Alignment0" V="0"/>'
            '<Cell N="Position1" V="0.5"/>'
            '<Cell N="Alignment1" V="1"/>'
            '<Cell N="Position2" V="0.75"/>'
            '<Cell N="Alignment2" V="2"/>'
            '</Row></Section></Shape>',
      );
    }
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    final stops =
        doc.pages.first.findShapeById(id)!.richText.tabSets.first.stops;
    expect(stops, hasLength(3));
    expect(stops[0].positionInches, closeTo(0.25, 1e-9));
    expect(stops[1].positionInches, closeTo(0.5, 1e-9));
    expect(stops[2].positionInches, closeTo(0.75, 1e-9));
  });

  test('Layer Name F=Inh keeps cached V', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        layers: const [
          VsdxLayer(id: 0, name: 'CachedLayer'),
        ],
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pagesFile =
        archive.firstWhere((f) => f.name.endsWith('pages/pages.xml'));
    var pagesXml = utf8.decode(pagesFile.content as List<int>);
    pagesXml = pagesXml.replaceFirst(
      RegExp(r'<Cell N="Name"[^/]*/>'),
      '<Cell N="Name" V="CachedLayer" F="Inh"/>',
    );
    mid = _rezipWith(mid, pagesFile.name, utf8.encode(pagesXml));
    doc = parser.parse(mid);
    expect(doc.pages.first.layers.first.name, 'CachedLayer');
  });

  test('FillGradientDir/Angle dropped when gradient cleared on equal-path', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          fill: VsdxFill(
            pattern: 1,
            foreground: const VsdxColor(0xFF336699),
            gradient: VsdxGradient(
              stops: const [
                VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
                VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
              ],
              angleRad: 0.5,
              dir: 4,
            ),
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    // Clear gradient in model but leave Dir/Angle Inh cells in XML.
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          fill: s.fill.withGradient(null),
          pinX: s.pinX + 0.01,
        ),
      ),
    );
    var mid2 = writer.write(originalBytes: mid, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid2);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    // Re-inject residual Dir/Angle with F=Inh while model stays gradient-free.
    if (!pageXml.contains('N="FillGradientDir"')) {
      pageXml = pageXml.replaceFirst(
        RegExp(r'(<Cell N="FillGradientEnabled"[^/]*/>)'),
        r'$1<Cell N="FillGradientDir" V="4" F="Inh"/>'
        '<Cell N="FillGradientAngle" V="0.5" F="Inh"/>',
      );
    } else {
      pageXml = pageXml.replaceFirst(
        RegExp(r'<Cell N="FillGradientDir"[^/]*/>'),
        '<Cell N="FillGradientDir" V="4" F="Inh"/>',
      );
      pageXml = pageXml.replaceFirst(
        RegExp(r'<Cell N="FillGradientAngle"[^/]*/>'),
        '<Cell N="FillGradientAngle" V="0.5" F="Inh"/>',
      );
    }
    mid2 = _rezipWith(mid2, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid2);
    expect(doc.pages.first.findShapeById(id)!.fill.gradient, isNull);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid2, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(outXml.contains('N="FillGradientDir"'), isFalse);
    expect(outXml.contains('N="FillGradientAngle"'), isFalse);
    expect(
      RegExp(r'N="FillGradientEnabled"[^>]*F="Inh"').hasMatch(outXml),
      isFalse,
    );
  });

  test('BeginArrowSize injects model bucket when cell missing', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(
          id: id,
          ax: 1,
          ay: 1,
          bx: 3,
          by: 1,
        ).copyWith(
          line: const VsdxLine(
            beginArrow: 4,
            beginArrowSizeInches: 0.225, // bucket 4
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    // Strip BeginArrowSize so ensure path must re-inject from the in-memory
    // model (do not re-parse, or the size would fall back to Visio default).
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="BeginArrowSize"[^/]*/>'),
      '',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.05),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) =>
              e.name.local == 'Cell' && e.getAttribute('N') == 'BeginArrowSize',
        );
    expect(cell.getAttribute('V'), '4');
    expect(cell.getAttribute('F'), isNull);
  });

  test('FillGradientEnabled=0 injected when cell missing on equal-path', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="FillGradientEnabled"[^/]*/>'),
      '',
    );
    // Leave a residual FillGradient section that equal-path must drop.
    if (!pageXml.contains('N="FillGradient"')) {
      pageXml = pageXml.replaceFirst(
        '</Shape>',
        '<Section N="FillGradient">'
            '<Row IX="0"><Cell N="GradientStopColor" V="#FF0000"/>'
            '<Cell N="Pos" V="0"/></Row></Section></Shape>',
      );
    }
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.1),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) =>
              e.name.local == 'Cell' &&
              e.getAttribute('N') == 'FillGradientEnabled',
        );
    expect(cell.getAttribute('V'), '0');
    expect(cell.getAttribute('F'), isNull);
    expect(outXml.contains('N="FillGradient"'), isFalse);
  });

  test('FillPattern injected when cell missing on equal-path', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(pattern: 1, foreground: VsdxColor(0xFF336699)),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="FillPattern"[^/]*/>'),
      '',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    // Keep in-memory model (pattern 1); do not re-parse.
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.05),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) => e.name.local == 'Cell' && e.getAttribute('N') == 'FillPattern',
        );
    expect(cell.getAttribute('V'), '1');
    expect(cell.getAttribute('F'), isNull);
  });

  test('FillForegndTrans injected when cell missing on equal-path', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(
            pattern: 1,
            foreground: VsdxColor(0xFF336699),
            foregroundTransparency: 0.35,
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="FillForegndTrans"[^/]*/>'),
      '',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.05),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) =>
              e.name.local == 'Cell' &&
              e.getAttribute('N') == 'FillForegndTrans',
        );
    expect(double.parse(cell.getAttribute('V')!), closeTo(0.35, 1e-6));
    expect(cell.getAttribute('F'), isNull);
  });

  test('HideText injected when cell missing on equal-path', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          text: 'Hi',
          richText: const VsdxRichText(
            runs: [VsdxTextRun(text: 'Hi')],
            textBlock: VsdxTextBlock(hideText: true),
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="HideText"[^/]*/>'),
      '',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.05),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) => e.name.local == 'Cell' && e.getAttribute('N') == 'HideText',
        );
    expect(cell.getAttribute('V'), '1');
    expect(cell.getAttribute('F'), isNull);
  });

  test('FillForegnd injected when cell missing on equal-path', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(
            pattern: 1,
            foreground: VsdxColor(0xFF336699),
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="FillForegnd"[^/]*/>'),
      '',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.05),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) => e.name.local == 'Cell' && e.getAttribute('N') == 'FillForegnd',
        );
    expect(cell.getAttribute('V')!.toUpperCase(), '#336699');
    expect(cell.getAttribute('F'), isNull);
  });

  test('ThemeIndex injected when cell missing on equal-path', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(themeIndex: 2),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="ThemeIndex"[^/]*/>'),
      '',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.05),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) => e.name.local == 'Cell' && e.getAttribute('N') == 'ThemeIndex',
        );
    expect(cell.getAttribute('V'), '2');
    expect(cell.getAttribute('F'), isNull);
  });

  test('TextBkgnd solid color injected when cell missing', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          text: 'Hi',
          richText: const VsdxRichText(
            runs: [VsdxTextRun(text: 'Hi')],
            textBlock: VsdxTextBlock(
              backgroundColor: VsdxColor(0xFFFFCC00),
            ),
          ),
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="TextBkgnd"[^/]*/>'),
      '',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.05),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) => e.name.local == 'Cell' && e.getAttribute('N') == 'TextBkgnd',
        );
    expect(cell.getAttribute('V')!.toUpperCase(), '#FFCC00');
    expect(cell.getAttribute('F'), isNull);
  });

  test('LockMoveX=0 injected when cell missing on unlocked equal-path', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="LockMoveX"[^/]*/>'),
      '',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(id)!.locked, isFalse);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.05),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) => e.name.local == 'Cell' && e.getAttribute('N') == 'LockMoveX',
        );
    expect(cell.getAttribute('V'), '0');
    expect(cell.getAttribute('F'), isNull);
  });

  test('EventDblClick injected when cell missing on equal-path', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(eventDblClick: 'OPENTEXTWIN()'),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="EventDblClick"[^/]*/>'),
      '',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.05),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) =>
              e.name.local == 'Cell' && e.getAttribute('N') == 'EventDblClick',
        );
    expect(cell.getAttribute('V'), 'OPENTEXTWIN()');
  });

  test('FillForegnd #FFFFFF injected when pattern=1 and foreground null', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(pattern: 1), // null foreground
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    // Strip FillForegnd if rebuild emitted it, then pin-patch.
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    pageXml = pageXml.replaceFirst(
      RegExp(r'<Cell N="FillForegnd"[^/]*/>'),
      '',
    );
    mid = _rezipWith(mid, pageFile.name, utf8.encode(pageXml));
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(pinX: s.pinX + 0.05),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final cell = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) => e.name.local == 'Cell' && e.getAttribute('N') == 'FillForegnd',
        );
    expect(cell.getAttribute('V')!.toUpperCase(), '#FFFFFF');
    expect(cell.getAttribute('F'), isNull);
  });

  test('group without FillPattern cell does not get pattern=1 injected', () {
    // Chinese Edraw fixtures use bare groups (no Fill* cells). Parser defaults
    // to libvisio's pattern=0; equal-path must not materialise FillPattern.
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final a = doc.pages.first.nextFreeShapeId();
    final b = a + 1;
    final gid = b + 1;
    var page = doc.pages.first
        .addShape(VsdxShapeFactory.rectangle(
            id: a, pinX: 1, pinY: 1, width: 1, height: 1))
        .addShape(VsdxShapeFactory.rectangle(
            id: b, pinX: 3, pinY: 1, width: 1, height: 1));
    page = page.group({a, b}, groupId: gid);
    doc = doc.replacePage(0, page);
    var mid = writer.write(originalBytes: blank, edited: doc);
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    final pageXml = utf8.decode(pageFile.content as List<int>);
    final docXml = XmlDocument.parse(pageXml);
    final groupEl = docXml.descendants.whereType<XmlElement>().firstWhere(
          (e) =>
              e.name.local == 'Shape' &&
              e.getAttribute('ID') == '$gid' &&
              e.getAttribute('Type') == 'Group',
        );
    for (final c in groupEl.childElements.toList()) {
      if (c.name.local == 'Cell' &&
          (c.getAttribute('N') == 'FillPattern' ||
              c.getAttribute('N') == 'FillForegnd')) {
        groupEl.children.remove(c);
      }
    }
    mid = _rezipWith(mid, pageFile.name, utf8.encode(docXml.toXmlString()));
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(gid)!.fill.pattern, 0);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        gid,
        (s) => s.copyWith(pinX: s.pinX + 0.05),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    final outGroup = XmlDocument.parse(outXml)
        .descendants
        .whereType<XmlElement>()
        .firstWhere(
          (e) =>
              e.name.local == 'Shape' &&
              e.getAttribute('ID') == '$gid' &&
              e.getAttribute('Type') == 'Group',
        );
    final hasPattern = outGroup.childElements.any(
      (c) => c.name.local == 'Cell' && c.getAttribute('N') == 'FillPattern',
    );
    expect(hasPattern, isFalse);
  });

  test('literal connector Pin edit is not overwritten by midpoint formula', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(id: id, ax: 1, ay: 2, bx: 4, by: 5),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    final before = doc.pages.first.findShapeById(id)!;
    final edited = before.copyWith(
      pinX: before.pinX + 0.5,
      pinY: before.pinY + 0.25,
    );
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(id, (_) => edited),
    );

    final out = writer.write(originalBytes: mid, edited: doc);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.pinX, closeTo(edited.pinX, 1e-6));
    expect(after.pinY, closeTo(edited.pinY, 1e-6));

    final pageXml =
        VsdxPackage.open(out).readPartXml('/visio/pages/page1.xml')!;
    XmlElement pin(String name) =>
        pageXml.descendants.whereType<XmlElement>().firstWhere((element) =>
            element.name.local == 'Cell' && element.getAttribute('N') == name);
    expect(pin('PinX').getAttribute('F'), isNull);
    expect(pin('PinY').getAttribute('F'), isNull);
  });
}
