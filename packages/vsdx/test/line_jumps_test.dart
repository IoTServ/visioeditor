import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('segmentIntersection finds a proper interior crossing', () {
    final p = segmentIntersection(
      const Offset2D(0, 0),
      const Offset2D(2, 2),
      const Offset2D(0, 2),
      const Offset2D(2, 0),
    );
    expect(p, isNotNull);
    expect(p!.x, closeTo(1, 1e-9));
    expect(p.y, closeTo(1, 1e-9));
  });

  test('lineJumpsEnabledForCode turns jumps off only for code 0', () {
    expect(lineJumpsEnabledForCode(0), isFalse);
    expect(lineJumpsEnabledForCode(null), isTrue);
    expect(lineJumpsEnabledForCode(4), isTrue);
  });

  test('polylineWithJumpsSvg inserts an arc at a crossing', () {
    final route = <Offset2D>[const Offset2D(0, 1), const Offset2D(4, 1)];
    final unders = <List<Offset2D>>[
      <Offset2D>[const Offset2D(2, 0), const Offset2D(2, 2)],
    ];
    final plain = polylineSvg(route);
    final jumped = polylineWithJumpsSvg(route, unders, 0.2);
    expect(plain.contains(' A '), isFalse);
    expect(jumped.contains(' A '), isTrue);
    expect(jumped.length, greaterThan(plain.length));
  });

  test('polylineWithJumpsSvg keeps hops on short dense segments', () {
    // Curved connectors bake ~0.08" LineTo segments; default r=0.07 used to
    // drop every hop because half > 0.5. Crossing must be strictly interior
    // to a short segment (not on a vertex).
    final route = <Offset2D>[
      for (var x = 0.0; x <= 4.0 + 1e-9; x += 0.08) Offset2D(x, 1),
    ];
    final unders = <List<Offset2D>>[
      <Offset2D>[const Offset2D(2.04, 0), const Offset2D(2.04, 2)],
    ];
    final jumped = polylineWithJumpsSvg(route, unders, 0.07);
    expect(jumped.contains(' A '), isTrue,
        reason: 'short segments must shrink hop radius, not skip jumps');
  });

  test('SVG export emits arc jumps for crossing connectors', () {
    final h = VsdxShapeFactory.line(id: 1, ax: 1, ay: 3, bx: 5, by: 3);
    final v = VsdxShapeFactory.line(id: 2, ax: 3, ay: 5, bx: 3, by: 1);
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[h, v],
      pageSheet: const VsdxPageSheet(lineJumpCode: 4),
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(RegExp(r'\sA\s').hasMatch(svg), isTrue);
  });

  test('SVG export omits jumps when LineJumpCode is None', () {
    final h = VsdxShapeFactory.line(id: 1, ax: 1, ay: 3, bx: 5, by: 3);
    final v = VsdxShapeFactory.line(id: 2, ax: 3, ay: 5, bx: 3, by: 1);
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[h, v],
      pageSheet: const VsdxPageSheet(lineJumpCode: 0),
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(RegExp(r'\sA\s').hasMatch(svg), isFalse);
  });

  test('SVG export honours drawLineJumps=false UI toggle', () {
    final h = VsdxShapeFactory.line(id: 1, ax: 1, ay: 3, bx: 5, by: 3);
    final v = VsdxShapeFactory.line(id: 2, ax: 3, ay: 5, bx: 3, by: 1);
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[h, v],
      pageSheet: const VsdxPageSheet(lineJumpCode: 4),
    );
    final on = VsdxToSvgSerializer().serializePage(page);
    final off = VsdxToSvgSerializer(drawLineJumps: false).serializePage(page);
    expect(RegExp(r'\sA\s').hasMatch(on), isTrue);
    expect(RegExp(r'\sA\s').hasMatch(off), isFalse);
  });

  test('SVG export honours custom lineJumpRadiusInches', () {
    final h = VsdxShapeFactory.line(id: 1, ax: 1, ay: 3, bx: 5, by: 3);
    final v = VsdxShapeFactory.line(id: 2, ax: 3, ay: 5, bx: 3, by: 1);
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[h, v],
      pageSheet: const VsdxPageSheet(lineJumpCode: 4),
    );
    final small = VsdxToSvgSerializer(lineJumpRadiusInches: 0.05)
        .serializePage(page);
    final large = VsdxToSvgSerializer(lineJumpRadiusInches: 0.2)
        .serializePage(page);
    expect(small, contains('A 0.05 0.05'));
    expect(large, contains('A 0.2 0.2'));
    expect(small.contains('A 0.2 0.2'), isFalse);
  });

  test('SVG LineJumpStyle Gap omits arc and opens a break', () {
    final h = VsdxShapeFactory.line(id: 1, ax: 1, ay: 3, bx: 5, by: 3);
    final v = VsdxShapeFactory.line(id: 2, ax: 3, ay: 5, bx: 3, by: 1);
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[h, v],
      pageSheet: const VsdxPageSheet(lineJumpCode: 4, lineJumpStyle: 2),
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(RegExp(r'\sA\s').hasMatch(svg), isFalse,
        reason: 'Gap style must not emit arc hops');
    // Gap inserts an M after the approach L (break in the stroke).
    expect(RegExp(r'L [^"]+ M ').hasMatch(svg), isTrue);
  });

  test('SVG LineJumpStyle Square emits rectangular hop', () {
    final route = <Offset2D>[const Offset2D(0, 1), const Offset2D(4, 1)];
    final unders = <List<Offset2D>>[
      <Offset2D>[const Offset2D(2, 0), const Offset2D(2, 2)],
    ];
    final d = polylineWithJumpsSvg(route, unders, 0.2, style: 3);
    expect(d.contains(' A '), isFalse);
    // in → up → across → down (three L segments after approach)
    expect(RegExp(r'L [\d.]+ [\d.]+ L [\d.]+ [\d.]+ L [\d.]+ [\d.]+')
        .hasMatch(d), isTrue);
  });

  test('drawnConnectorPagePolyline keeps dense curved geometry', () {
    final r1 = VsdxShapeFactory.rectangle(
        id: 1, pinX: 1, pinY: 1, width: 1, height: 1);
    final r2 = VsdxShapeFactory.rectangle(
        id: 2, pinX: 5, pinY: 4, width: 1, height: 1);
    final conn = VsdxShapeFactory.line(id: 3, ax: 1, ay: 1, bx: 5, by: 4);
    var page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[r1, r2, conn],
      connects: const [
        VsdxConnect(
            fromSheetId: 3, fromCell: 'BeginX', toSheetId: 1, toCell: 'PinX'),
        VsdxConnect(
            fromSheetId: 3, fromCell: 'EndX', toSheetId: 2, toCell: 'PinX'),
      ],
    ).rerouteConnectors();
    page = page.setConnectorStyle({3}, straight: false, curved: true);
    final curved = page.findShapeById(3)!;
    final geomPts = curved.geometries.first.commands
        .where((c) => c is MoveTo || c is LineTo)
        .length;
    expect(geomPts, greaterThan(4));
    final drawn = page.drawnConnectorPagePolyline(curved);
    expect(drawn.length, geomPts);
  });

  test('SVG export keeps curved stroke when there is no crossing', () {
    final r1 = VsdxShapeFactory.rectangle(
        id: 1, pinX: 1, pinY: 1, width: 1, height: 1);
    final r2 = VsdxShapeFactory.rectangle(
        id: 2, pinX: 5, pinY: 4, width: 1, height: 1);
    final conn = VsdxShapeFactory.line(id: 3, ax: 1, ay: 1, bx: 5, by: 4);
    var page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[r1, r2, conn],
      connects: const [
        VsdxConnect(
            fromSheetId: 3, fromCell: 'BeginX', toSheetId: 1, toCell: 'PinX'),
        VsdxConnect(
            fromSheetId: 3, fromCell: 'EndX', toSheetId: 2, toCell: 'PinX'),
      ],
      pageSheet: const VsdxPageSheet(lineJumpCode: 4),
    ).rerouteConnectors();
    page = page.setConnectorStyle({3}, straight: false, curved: true);
    final geomCount =
        page.findShapeById(3)!.geometries.first.commands.length;
    final svg = VsdxToSvgSerializer().serializePage(page);
    // Elbow fallback is a few L segments; dense curve has many more.
    final lCount = RegExp(r'\sL\s').allMatches(svg).length;
    expect(lCount, greaterThanOrEqualTo(geomCount - 1));
    expect(RegExp(r'\sA\s').hasMatch(svg), isFalse);
  });
}
