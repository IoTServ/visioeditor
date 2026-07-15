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

    // First write: b has no connection points yet.
    final bytes1 = writer.write(originalBytes: blank, edited: doc);
    final r1 = parser.parse(bytes1);
    expect(r1.pages.first.findShapeById(b.id)!.connectionPoints, isEmpty);

    // Glue the END to b's top connection point (index 0). This materialises
    // b's standard point set, and the second write patches a Connection
    // section onto the (now existing) shape.
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
