import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

/// Elbow connectors must export Visio's Begin-origin XForm + ConFixedCode≠0
/// so 万兴图示 / Edraw keep the baked Geometry instead of collapsing to a
/// straight Begin→End line.
void main() {
  const writer = VsdxWriter();
  const parser = DocumentParser();

  test('reshapeAsPolyline uses Begin-origin local coords and locks ConFixedCode',
      () {
    final line = VsdxShapeFactory.line(id: 1, ax: 1, ay: 5, bx: 5, by: 1);
    final elbow = line.reshapeAsPolyline(const <Offset2D>[
      Offset2D(1, 5),
      Offset2D(3, 5),
      Offset2D(3, 1),
      Offset2D(5, 1),
    ]);

    expect(elbow.width, closeTo(4.0, 1e-9)); // EndX − BeginX
    expect(elbow.height, closeTo(-4.0, 1e-9)); // EndY − BeginY (signed!)
    expect(elbow.beginX, closeTo(1, 1e-9));
    expect(elbow.beginY, closeTo(5, 1e-9));
    expect(elbow.endX, closeTo(5, 1e-9));
    expect(elbow.endY, closeTo(1, 1e-9));
    expect(elbow.connectorProps?.conFixedCode, 3);
    expect(elbow.formulas['Width'], 'EndX-BeginX');
    expect(elbow.formulas['Height'], 'EndY-BeginY');

    final cmds = elbow.geometries.single.commands;
    expect(cmds.first, isA<MoveTo>());
    expect((cmds.first as MoveTo).x, closeTo(0, 1e-9));
    expect((cmds.first as MoveTo).y, closeTo(0, 1e-9));
    final last = cmds.last as LineTo;
    expect(last.x, closeTo(elbow.width, 1e-9));
    expect(last.y, closeTo(elbow.height, 1e-9));
    // First bend after Begin stays at local Y=0 (horizontal leg).
    final mid = cmds[1] as LineTo;
    expect(mid.x, closeTo(2, 1e-9));
    expect(mid.y, closeTo(0, 1e-9));
  });

  test('exported elbow keeps multi-segment Geometry and ConFixedCode=3', () {
    final blank = writer.emptyDocument();
    final doc = parser.parse(blank);
    final r1 = VsdxShapeFactory.rectangle(
        id: 1, pinX: 1, pinY: 5, width: 1, height: 1);
    final r2 = VsdxShapeFactory.rectangle(
        id: 2, pinX: 6, pinY: 2, width: 1, height: 1);
    final conn = VsdxShapeFactory.line(id: 3, ax: 1.5, ay: 5, bx: 5.5, by: 2);
    final page = doc.pages.first
        .copyWith(
          shapes: <VsdxShape>[r1, r2, conn],
          connects: const <VsdxConnect>[
            VsdxConnect(
                fromSheetId: 3,
                fromCell: 'BeginX',
                toSheetId: 1,
                toCell: 'PinX'),
            VsdxConnect(
                fromSheetId: 3, fromCell: 'EndX', toSheetId: 2, toCell: 'PinX'),
          ],
        )
        .rerouteConnectors();

    final baked = page.findShapeById(3)!;
    expect(baked.geometries.single.commands.length, greaterThanOrEqualTo(3));
    expect(baked.connectorProps?.conFixedCode, 3);

    final bytes = writer.write(
      originalBytes: blank,
      edited: doc.replacePage(0, page),
    );
    final xml = utf8.decode(
      ZipDecoder()
          .decodeBytes(bytes)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(r'V="3"[^>]*N="ConFixedCode"|N="ConFixedCode"[^>]*V="3"')
          .hasMatch(xml),
      isTrue,
      reason: 'ConFixedCode must be 3 so Edraw does not freely re-route',
    );
    expect(xml.contains('F="EndX-BeginX"'), isTrue);
    expect(xml.contains('F="EndY-BeginY"'), isTrue);
    expect('T="LineTo"'.allMatches(xml).length, greaterThanOrEqualTo(2));
  });
}
