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

  test('ConLineJumpDirX Down flips horizontal hop to −Y', () {
    final route = <Offset2D>[const Offset2D(0, 1), const Offset2D(4, 1)];
    final unders = <List<Offset2D>>[
      <Offset2D>[const Offset2D(2, 0), const Offset2D(2, 2)],
    ];
    final up = polylineWithJumpsSvg(route, unders, 0.2, dirX: 1);
    final down = polylineWithJumpsSvg(route, unders, 0.2, dirX: 2);
    // Default/Up uses sweep=0; Down uses sweep=1 on the hop arc.
    expect(up, contains('A 0.2000 0.2000 0 0 0 '));
    expect(down, contains('A 0.2000 0.2000 0 0 1 '));
    expect(lineJumpHopSign(sdx: 4, sdy: 0, dirX: 1), 1.0);
    expect(lineJumpHopSign(sdx: 4, sdy: 0, dirX: 2), -1.0);
  });

  test('effectiveLineJumpDir inherits page when ConDir is 0/null', () {
    expect(effectiveLineJumpDir(null, 2), 2);
    expect(effectiveLineJumpDir(0, 1), 1);
    expect(effectiveLineJumpDir(2, 1), 2);
    expect(effectiveLineJumpDir(0, 0), isNull);
  });

  test('ConLineJumpCode Never/Other/Neither refuse hops; Always overrides page',
      () {
    expect(
      connectorLineJumpsEnabled(null, pageLineJumpCode: 4),
      isTrue,
    );
    expect(
      connectorLineJumpsEnabled(0, pageLineJumpCode: 4),
      isTrue,
    );
    expect(
      connectorLineJumpsEnabled(1, pageLineJumpCode: 4),
      isFalse,
      reason: 'Never',
    );
    expect(
      connectorLineJumpsEnabled(2, pageLineJumpCode: 0),
      isTrue,
      reason: 'Always over page None',
    );
    expect(
      connectorLineJumpsEnabled(3, pageLineJumpCode: 4),
      isFalse,
      reason: 'Other — this connector does not hop',
    );
    expect(
      connectorLineJumpsEnabled(4, pageLineJumpCode: 4),
      isFalse,
      reason: 'Neither',
    );
    expect(
      connectorLineJumpsEnabled(0, pageLineJumpCode: 0),
      isFalse,
    );
  });

  test('LineJumpCode 5 reverses peer z-order; Neither peers are skipped', () {
    expect(
      lineJumpPeerIndices(k: 1, routeCount: 3, pageJumpCode: 4),
      <int>[0],
    );
    expect(
      lineJumpPeerIndices(k: 0, routeCount: 3, pageJumpCode: 5),
      <int>[1, 2],
    );
    expect(
      lineJumpShapeMayHop(k: 0, routeCount: 3, pageJumpCode: 5),
      isTrue,
    );
    expect(
      lineJumpShapeMayHop(k: 0, routeCount: 3, pageJumpCode: 4),
      isFalse,
    );
    expect(
      lineJumpShapeMayHop(
        k: 0,
        routeCount: 2,
        pageJumpCode: 4,
        peerConCodes: <int?>[0, 3],
      ),
      isTrue,
      reason: 'Other peer must open the z-gate for lower connector',
    );
    expect(
      lineJumpShapeMayHop(
        k: 0,
        routeCount: 2,
        pageJumpCode: 0,
        selfConCode: 2,
        peerConCodes: <int?>[2, 0],
      ),
      isTrue,
      reason: 'Always hops even when page is None and z=0',
    );
    expect(
      lineJumpPeerIndices(
        k: 1,
        routeCount: 2,
        pageJumpCode: 4,
        peerConCodes: <int?>[4, 0],
      ),
      isEmpty,
      reason: 'Neither peer suppresses the crossing',
    );
    expect(
      lineJumpPeerIndices(
        k: 0,
        routeCount: 2,
        pageJumpCode: 4,
        selfConCode: 0,
        peerConCodes: <int?>[0, 3],
      ),
      <int>[1],
      reason: 'Other peer forces lower z to hop',
    );
  });

  test('SVG ConLineJumpCode Other on top forces lower connector to hop', () {
    final h = VsdxShapeFactory.line(id: 1, ax: 1, ay: 3, bx: 5, by: 3);
    final v = VsdxShapeFactory.line(id: 2, ax: 3, ay: 5, bx: 3, by: 1).copyWith(
      connectorProps: const VsdxConnectorProps(conLineJumpCode: 3),
    );
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[h, v],
      pageSheet: const VsdxPageSheet(lineJumpCode: 4),
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(RegExp(r'\sA\s').hasMatch(svg), isTrue,
        reason: 'lower connector must hop when peer is Other');
  });

  test('SVG LineJumpCode 5 emits hops on first-drawn connector', () {
    final h = VsdxShapeFactory.line(id: 1, ax: 1, ay: 3, bx: 5, by: 3);
    final v = VsdxShapeFactory.line(id: 2, ax: 3, ay: 5, bx: 3, by: 1);
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[h, v],
      pageSheet: const VsdxPageSheet(lineJumpCode: 5),
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(RegExp(r'\sA\s').hasMatch(svg), isTrue);
  });

  test('LineJumpCode Horizontal skips vertical segment hops', () {
    final route = <Offset2D>[const Offset2D(2, 0), const Offset2D(2, 4)];
    final unders = <List<Offset2D>>[
      <Offset2D>[const Offset2D(0, 2), const Offset2D(4, 2)],
    ];
    final d = polylineWithJumpsSvg(
      route,
      unders,
      0.2,
      pageJumpCode: 1,
    );
    expect(RegExp(r'\sA\s').hasMatch(d), isFalse,
        reason: 'vertical segment must not hop when page is Horizontal');
    expect(lineJumpAppliesToSegment(1, 0, 4), isFalse);
    expect(lineJumpAppliesToSegment(1, 4, 0), isTrue);
    expect(lineJumpAppliesToSegment(2, 0, 4), isTrue);
  });

  test('page LineToLine×Factor resolves hop radius', () {
    expect(
      pageLineJumpRadius(lineToLineInches: 0.125, jumpFactor: 0.8),
      closeTo(0.1, 1e-9),
    );
    expect(
      resolveLineJumpRadius(
        uiRadius: 0.07,
        lineToLineInches: 0.125,
        jumpFactor: 0.8,
      ),
      closeTo(0.1, 1e-9),
    );
    expect(
      resolveLineJumpRadius(
        uiRadius: 0.2,
        lineToLineInches: 0.125,
        jumpFactor: 0.8,
      ),
      closeTo(0.2, 1e-9),
      reason: 'UI override wins when not at engine default',
    );
  });

  test('page PageLineJumpDirX Down flips hop when ConDir unset', () {
    final route = <Offset2D>[const Offset2D(0, 1), const Offset2D(4, 1)];
    final unders = <List<Offset2D>>[
      <Offset2D>[const Offset2D(2, 0), const Offset2D(2, 2)],
    ];
    final d = effectiveLineJumpDir(0, 2);
    final down = polylineWithJumpsSvg(route, unders, 0.2, dirX: d);
    expect(down, contains('A 0.2000 0.2000 0 0 1 '));
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

  test('draw.io Line jump emits paired crossing marks', () {
    final route = <Offset2D>[const Offset2D(0, 1), const Offset2D(4, 1)];
    final unders = <List<Offset2D>>[
      <Offset2D>[const Offset2D(2, 0), const Offset2D(2, 2)],
    ];
    final d = polylineWithJumpsSvg(
      route,
      unders,
      0.2,
      customStyle: 'line',
    );
    expect(d.contains(' A '), isFalse);
    expect(' M '.allMatches(d).length, 3,
        reason: 'two crossing marks plus resume point');
  });

  test('SVG honours per-connector draw.io jump style and size', () {
    final lower = VsdxShapeFactory.line(id: 1, ax: 1, ay: 3, bx: 5, by: 3);
    final upper = VsdxShapeFactory.line(id: 2, ax: 3, ay: 5, bx: 3, by: 1)
        .withDrawioLineJumpStyle('arc')
        .withDrawioLineJumpSize(0.13);
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[lower, upper],
      pageSheet: const VsdxPageSheet(lineJumpCode: 0),
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg, contains('A 0.13 0.13'));
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
