import 'dart:convert';
import 'dart:io';
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

void main() {
  const parser = DocumentParser();
  const writer = VsdxWriter();

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
    final edited =
        doc.replacePage(0, doc.pages.first.addShape(stroke));
    final out = writer.write(originalBytes: blank, edited: edited);
    final again = parser.parse(out).pages.first.findShapeById(id)!;
    expect(again.is1D, isTrue);
    expect(again.objType, 1); // not a glueable connector
    expect(again.beginX, closeTo(1, 1e-6));
    expect(again.endX, closeTo(4, 1e-6));
    expect(again.geometries.single.commands.length, 3);
    expect(
      again.geometries.single.commands
          .every((c) => c is MoveTo || c is LineTo),
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
      id: id, pinX: 4, pinY: 5, width: 1.5, height: 1.0,
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
    final edited =
        doc.replacePage(0, doc.pages.first.addShape(shape));
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

  test('heal injects missing docProps/core.xml on save', () {
    // test5_master references core in .rels but the part is absent.
    final bytes =
        File('test/fixtures/test5_master.vsdx').readAsBytesSync();
    expect(
      VsdxPackage.open(bytes).readPartBytes('/docProps/core.xml'),
      isNull,
    );
    final doc = parser.parse(bytes);
    final out = writer.write(originalBytes: bytes, edited: doc);
    final pkg = VsdxPackage.open(out);
    final core = pkg.readPartBytes('/docProps/core.xml');
    expect(core, isNotNull);
    expect(utf8.decode(core!), contains('coreProperties'));
    expect(utf8.decode(core!), contains('dc:creator'));
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
        (c) =>
            c.name.local == 'Section' && c.getAttribute('N') == 'Character',
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
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x00,
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
      id: id, pinX: 4, pinY: 5, width: 1.6, height: 0.9,
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
    final docXml = VsdxPackage.open(out)
        .readPartXml('/visio/document.xml')!
        .toXmlString();
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
        id: id, pinX: 4, pinY: 5, width: 1.2, height: 0.5,
      ).copyWith(text: 'Text')),
    );
    final mid = writer.write(originalBytes: blank, edited: withText);
    final pkg = VsdxPackage.open(mid);
    final pageXml = pkg.readPartXml('/visio/pages/page1.xml')!;
    for (final shape in pageXml.rootElement.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'Shape')) {
      for (final cell in shape.childElements.toList()) {
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
    final out = writer.write(originalBytes: stripped, edited: reopened);
    final outPage = VsdxPackage.open(out)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(outPage, contains('N="TxtPinX"'));
    expect(outPage, contains('N="TxtWidth"'));
    expect(outPage, contains('N="VerticalAlign"'));
    expect(outPage, contains('F="Width*0.5"'));
    // Injecting the centred text box also upgrades left HorzAlign → center.
    expect(outPage, contains('N="HorzAlign" V="1"'));
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
        id: id, pinX: 4.25, pinY: 9.75, width: 1.5, height: 1.0,
      ).copyWith(text: 'Hi')),
    );
    // First write builds shapes with LocPin into stripped blank…
    final mid = writer.write(originalBytes: stripped, edited: edited);
    // …then parse + no-op save must still restore StyleSheets on document.xml.
    final midDoc = parser.parse(mid);
    final out = writer.write(originalBytes: mid, edited: midDoc);
    final outDoc = VsdxPackage.open(out)
        .readPartXml('/visio/document.xml')!
        .toXmlString();
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
    final r2 = parser.parse(writer.write(originalBytes: bytes1, edited: resized));
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
    final after =
        parser.parse(writer.write(originalBytes: blank, edited: doc))
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
    final bytes1 = writer.write(originalBytes: blank, edited: doc.replacePage(0, page));
    final r1 = parser.parse(bytes1);
    expect(r1.pages.first.shapes.map((s) => s.id).toList(), [a, b]);

    final edited = r1.replacePage(0, r1.pages.first.sendToBack(b));
    final r2 = parser.parse(writer.write(originalBytes: bytes1, edited: edited));
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
    final r2 = parser.parse(writer.write(originalBytes: bytes1, edited: edited));
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
    final edited =
        r1.replacePage(0, r1.pages.first.bringForward(a));
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
    final bytes1 = writer.write(originalBytes: blank, edited: doc.replacePage(0, page));
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
    final ungrouped =
        parser.parse(bytes2).replacePage(0, p2.ungroup(gid));
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
    final reopened = parser.parse(writer.write(originalBytes: blank, edited: doc));
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
          paraStyle: r.paraStyle.copyWith(horizontalAlign: VsdxHorzAlign.center),
        ),
    ];
    final edited = r1.replacePage(
      0,
      r1.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(richText: s.richText.copyWith(runs: newRuns)),
      ),
    );
    final r2 = parser.parse(writer.write(originalBytes: bytes1, edited: edited));
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
          fromSheetId: connId, fromCell: 'BeginX', toSheetId: aId, toCell: 'PinX'),
      VsdxConnect(
          fromSheetId: connId, fromCell: 'EndX', toSheetId: bId, toCell: 'PinX'),
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

  test('a rounded connector bakes its fillets into round-tripping geometry', () {
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
          fromSheetId: connId, fromCell: 'BeginX', toSheetId: aId, toCell: 'PinX'),
      VsdxConnect(
          fromSheetId: connId, fromCell: 'EndX', toSheetId: bId, toCell: 'PinX'),
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

    final reopened = parser.parse(
      writer.write(originalBytes: bytes, edited: edited),
    );
    final after = reopened.pages.first.findShapeById(target.id)!;
    expect(after.line.pattern, 3);
    expect(after.line.beginArrow, 1);
    expect(after.line.endArrow, 5);
    expect(after.line.beginArrowSizeInches, closeTo(0.225, 1e-4));
    expect(after.line.endArrowSizeInches, closeTo(0.375, 1e-4));
    expect(after.line.cap, LineCap.square);
    expect(after.line.transparency, closeTo(0.4, 1e-4));
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
        ),
      ),
    );
    final after = parser
        .parse(writer.write(originalBytes: blank, edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(after.layerMemberIds, <int>[0, 2]);
    expect(after.userCells, hasLength(1));
    expect(after.userCells.first.name, 'visVersion');
    expect(after.userCells.first.value, '1');
    expect(after.userCells.first.prompt, 'ver');
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
    expect(run.charStyle.letterSpacingInches, closeTo(0.02, 1e-6));
    expect(run.charStyle.position, VsdxTextPosition.superscript);
    expect(run.charStyle.transparency, closeTo(0.3, 1e-6));
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
    expect(
        s2.userProperties.firstWhere((p) => p.name == 'Status').value, 'Active');
    // The edited "Cost" row kept its label from the original.
    expect(
        s2.userProperties.firstWhere((p) => p.name == 'Cost').label, 'Unit cost');
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
    expect(again.pages.firstWhere((p) => p.id == fg.id).backgroundPageId,
        isNull);
    expect(again.pages.firstWhere((p) => p.id == bgId).isBackgroundPage,
        isFalse);
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
          shadow: const VsdxShadow(),
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
    expect(after.glow.enabled, isTrue);
    expect(after.glow.themeColorIndex, ThemeSlot.accent2);
    expect(after.glow.color, isNull);
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
    final after = parser
        .parse(writer.write(originalBytes: blank, edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(after.richText.textBlock.hideText, isTrue);
    expect(after.richText.textBlock.backgroundColor?.value, 0xFFFFFF00);
    expect(after.line.roundingInches, closeTo(0.05, 1e-6));
    expect(after.glow.enabled, isTrue);
    expect(after.glow.sizeInches, closeTo(0.08, 1e-6));
    expect(after.glow.color?.value, 0xFFFF0000);
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
          .firstWhere((f) =>
              f.name.contains('pages/page') && f.name.endsWith('.xml'))
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
    expect(reopened2.images.findByPart(s2.imagePartName!)!.bytes,
        equals(payload));
  });

  test('picture Foreign XML has ImgWidth/ImgHeight for Edraw/Visio', () {
    final blank = writer.emptyDocument();
    final doc = parser.parse(blank);
    final page = doc.pages.first;
    final id = page.nextFreeShapeId();
    const part = '/visio/media/image_edraw.png';
    // Minimal valid-looking PNG header bytes (content is irrelevant to XML).
    final payload = Uint8List.fromList(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4,
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
      archive.findFile('visio/pages/_rels/page1.xml.rels')!.content as List<int>,
    );
    expect(rels, contains('relationships/image'));
    expect(rels, contains('../media/image_edraw.png'));
  });

  test('resizing a picture patches ImgWidth/ImgHeight cached V=', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    final id = page.nextFreeShapeId();
    const part = '/visio/media/image_resize.png';
    final payload = Uint8List.fromList(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 9, 8, 7, 6,
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
      ZipDecoder()
          .decodeBytes(out2)
          .findFile('visio/pages/page1.xml')!
          .content as List<int>,
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
    final bytesA = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 1, 1, 1, 1]);
    final bytesB = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 2, 2, 2, 2]);
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
    final reopened = parser.parse(out2);
    final s = reopened.pages.first.findShapeById(id)!;
    expect(s.imagePartName, endsWith('image_b.png'));
    expect(reopened.images.findByPart(s.imagePartName!)!.bytes, equals(bytesB));
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
    final conn =
        VsdxShapeFactory.line(id: connId, ax: 2, ay: 5, bx: 6, by: 5);
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
      doc.pages.first
          .setConnectorEndpoint(connId, begin: false, targetShapeId: cRect.id, x: 6, y: 8),
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
      r1.pages.first
          .setConnectorEndpoint(connId, begin: false, targetShapeId: null, x: 7, y: 9),
    );
    final r2 = parser.parse(writer.write(originalBytes: bytes1, edited: detached));
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
    final connId = page.nextFreeShapeId();
    final conn =
        VsdxShapeFactory.line(id: connId, ax: 2, ay: 5, bx: 6, by: 5);
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

    // First write: 2-D shapes without Connection rows get the standard mid-
    // edge set so 万兴图示 glues to borders (not an empty / odd attachment).
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
    final r2 = parser.parse(writer.write(originalBytes: bytes1, edited: edited));
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

  test('drawio-parity stencil shapes (tape / stored / bpmn / uml) round-trip', () {
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
    expect(r.pages.first.findShapeById(poolId)!.geometries.length, greaterThanOrEqualTo(1));
    expect(r.pages.first.findShapeById(layerId)!.geometries.length, greaterThanOrEqualTo(2));
  });

  test('drawio-parity misc shapes (parallelepiped / callout / list / image / '
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

  test('drawio-parity network shapes (server / firewall / mobile / monitor / '
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
    expect(mob.geometries.first.commands.whereType<EllipticalArcTo>(),
        isNotEmpty);
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

  test('drawio-parity network+/mockup/electrical/signs starter shapes round-trip',
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
    expect(r.pages.first.findShapeById(resId)!.geometries.single.noFill, isTrue);
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
    expect(r.pages.first.findShapeById(gndId)!.geometries.single.noFill, isTrue);
    expect(r.pages.first.findShapeById(warnId)!.geometries.length, 2);
    expect(r.pages.first.findShapeById(aidId)!.geometries.length, 2);
  });

  test('drawio-parity batch64 expansions (tablet/search/fuse/biohazard) round-trip',
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
    expect(r.pages.first.findShapeById(loadId)!.geometries.single.noFill, isTrue);
    expect(r.pages.first.findShapeById(fuseId)!.geometries.single.noFill, isTrue);
    expect(r.pages.first.findShapeById(invId)!.geometries.length, 3);
    expect(r.pages.first.findShapeById(smokeId)!.geometries.length, greaterThan(1));
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
    expect(r.pages.first.findShapeById(bufId)!.geometries.length, greaterThan(1));
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
    expect(r.pages.first.findShapeById(parkId)!.geometries.single.noFill, isTrue);
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
    expect(
        r.pages.first.findShapeById(invId)!.geometries.length,
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

  test('drawio-parity batch72 GCP starter (compute/gke/pubsub) round-trip',
      () {
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

  test('drawio-parity batch83 Oracle expansion (api-gw/fastconnect/devops) round-trip',
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

  test('drawio-parity batch82 IBM expansion (schematics/satellite/aspera) round-trip',
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

  test('drawio-parity batch80 Oracle starter (adb/oke/exadata) round-trip',
      () {
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

  test('drawio-parity batch75 GCP expansion (dataflow/firestore/vertex) round-trip',
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
  // reopen. Assert the emit path matches what the parser round-trips.
  test('newly emitted shapes preserve style / text / LocPin (buildShape parity)',
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
        shadow: const VsdxShadow(),
        // Off-centre LocPin (not the default width/2, height/2).
        locPinXInches: 0.25,
        locPinYInches: 0.75,
      ),
    );

    doc = doc.replacePage(0, page);
    final out = parser.parse(writer.write(originalBytes: blank, edited: doc));
    final rp = out.pages.first;

    final conn = rp.findShapeById(connId)!;
    expect(conn.line.beginArrow, 1);
    expect(conn.line.endArrow, 4);
    expect(conn.line.transparency, closeTo(0.3, 1e-4));
    expect(conn.line.pattern, 2);

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
    expect(styled.line.transparency, closeTo(0.25, 1e-4));
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
    final locPinX = RegExp(r'<Cell[^>]*N="LocPinX"[^>]*/?>')
        .firstMatch(shapeXml!);
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
    expect(shapeXml.contains('N="AsianFont"') || shapeXml.contains('N="LangID"'),
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
    final out = writer.write(
        originalBytes: bytes1, edited: doc.replacePage(0, page));
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
    final withControl = doc.pages.first.shapes
        .where((s) => s.controls.isNotEmpty)
        .toList();
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
    expect(pageXml.contains('<tp IX="0"/>') || pageXml.contains("<tp IX=\"0\"/>"),
        isTrue);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.richText.plainText.contains('\t'), isTrue);
  });

  test('AsianFont / LangID round-trip on new shape', () {
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
      text: '你好',
      richText: VsdxRichText(
        runs: [
          VsdxTextRun(
            text: '你好',
            charStyle: const VsdxCharStyle(
              fontFamily: 'Arial',
              asianFont: 'Microsoft YaHei',
              complexScriptFont: 'Arial',
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
    expect(c.complexScriptFont, 'Arial');
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
    expect(pageXml.contains('<fld IX="0">42</fld>') ||
        pageXml.contains("<fld IX=\"0\">42</fld>"), isTrue);

    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.fields, isNotEmpty);
    expect(after.fields.first.valueFormula, 'PAGENUMBER()');
    expect(after.richText.runs.first.fieldSpans, isNotEmpty);
    expect(after.richText.plainText, display);
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
    expect(pageXml.contains('N="Position0"'), isTrue);
    expect(pageXml.contains('N="Alignment1"'), isTrue);
    expect(pageXml.contains('<tp IX="0"/>') || pageXml.contains('tp IX="0"'),
        isTrue);
    expect(pageXml.contains('<tp IX="1"/>') || pageXml.contains('tp IX="1"'),
        isTrue);
    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.richText.tabSets, hasLength(2));
    expect(after.richText.tabSets[1].stops, hasLength(2));
    expect(after.richText.tabSets[1].stops[0].positionInches,
        closeTo(1.25, 1e-6));
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
  });

  test('Visio XDyn/XCon/CanGlue Control round-trip', () {
    final bytes = _fixture('test9_rect_and_line.vsdx');
    final doc = parser.parse(bytes);
    VsdxShape? withCtrl;
    void walk(VsdxShape s) {
      if (s.controls.isNotEmpty &&
          s.controls.any((c) => c.useVisioDynNames)) {
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
    expect(pageXml.contains('N="CompoundType" V="1"'), isTrue);
    final after = parser.parse(saved).pages.first.findShapeById(id)!;
    expect(after.line.softEdgesInches, closeTo(0.05, 1e-6));
    expect(after.line.compoundType, 1);
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
      shadow: const VsdxShadow(enabled: true, offsetXInches: 0.1),
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
    expect(src.formulas['TxtPinX'], contains('SETATREF(Controls.TextPosition)'));

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
    expect(pageXml.contains('TEXTWIDTH(TheText)') || pageXml.contains('TxtWidth'),
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
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.foreignType, 'EnhMetaFile');
    expect(after.hasImage, isTrue);
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
    expect(pageXml.contains('N="GradientStopColor" V="1"') ||
            pageXml.contains('V="1" N="GradientStopColor"'),
        isTrue);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.fill.gradient, isNotNull);
    expect(after.fill.gradient!.stops.first.themeColorIndex, 1);
    expect(after.fill.gradient!.stops.last.themeColorIndex, 4);
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

  test('FillPattern / LineColor F= formulas round-trip on rebuild', () {
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
      formulas: const {
        'FillPattern': 'THEMEVAL()',
        'LineColor': 'THEMEVAL()',
        'LinePattern': 'THEMEVAL()',
        'FillForegnd': 'THEMEVAL()',
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
    expect(pageXml.contains('N="FillPattern"'), isTrue);
    expect(pageXml.contains('N="LineColor"'), isTrue);
    expect(pageXml.contains('F="THEMEVAL()"'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.formulas['FillPattern'], 'THEMEVAL()');
    expect(after.formulas['LineColor'], 'THEMEVAL()');
    expect(after.formulas['LinePattern'], 'THEMEVAL()');
    expect(after.formulas['FillForegnd'], 'THEMEVAL()');
  });
}
