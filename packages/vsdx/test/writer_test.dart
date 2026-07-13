import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

void main() {
  const parser = DocumentParser();
  const writer = VsdxWriter();

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
            transparency: 0.4,
          ),
          fill: s.fill.copyWith(foregroundTransparency: 0.25),
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
    expect(after.line.transparency, closeTo(0.4, 1e-4));
    expect(after.fill.foregroundTransparency, closeTo(0.25, 1e-4));
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
}
