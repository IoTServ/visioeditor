import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

void main() {
  const parser = DocumentParser();

  test('shape copyWith updates only the requested field', () {
    final doc = parser.parse(_fixture('test9_rect_and_line.vsdx'));
    final shape = doc.pages.first.shapes.first;
    final moved = shape.copyWith(pinX: shape.pinX + 1.5);

    expect(moved.pinX, closeTo(shape.pinX + 1.5, 1e-9));
    expect(moved.pinY, shape.pinY);
    expect(moved.width, shape.width);
    expect(moved.id, shape.id);
    expect(moved.name, shape.name);
    // Original is untouched (immutability).
    expect(shape.pinX, isNot(moved.pinX));
  });

  test('updateShapeById moves one shape and shares the rest', () {
    final doc = parser.parse(_fixture('test9_rect_and_line.vsdx'));
    final page = doc.pages.first;
    final target = page.shapes.first;

    final newPage = page.updateShapeById(
      target.id,
      (s) => s.copyWith(pinX: s.pinX + 2, pinY: s.pinY + 3),
    );

    expect(identical(newPage, page), isFalse);
    final movedTarget = newPage.findShapeById(target.id)!;
    expect(movedTarget.pinX, closeTo(target.pinX + 2, 1e-9));
    expect(movedTarget.pinY, closeTo(target.pinY + 3, 1e-9));

    // Untouched siblings keep their identity (structural sharing).
    if (page.shapes.length > 1) {
      expect(identical(newPage.shapes.last, page.shapes.last), isTrue);
    }
    // Original page still reports the old position.
    expect(page.findShapeById(target.id)!.pinX, target.pinX);
  });

  test('updateShapeById with an unknown id returns the same page', () {
    final doc = parser.parse(_fixture('test9_rect_and_line.vsdx'));
    final page = doc.pages.first;
    final same = page.updateShapeById(-999, (s) => s.copyWith(pinX: 0));
    expect(identical(same, page), isTrue);
  });

  test('resizeTo scales a rectangle geometry with its box', () {
    final rect = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 0,
      pinY: 0,
      width: 2,
      height: 1,
    );
    final bigger = rect.resizeTo(pinX: 0, pinY: 0, width: 4, height: 2);
    expect(bigger.width, closeTo(4, 1e-9));
    expect(bigger.height, closeTo(2, 1e-9));
    // The far corner LineTo(2,·) should now reach x = 4 (doubled).
    final reachesFarX = bigger.geometries.first.commands
        .any((c) => c is LineTo && (c.x - 4).abs() < 1e-9);
    expect(reachesFarX, isTrue);
  });

  test('rerouteConnectors keeps a glued connector attached to moved shapes', () {
    // Build a page: two rectangles + a connector glued between them.
    final r1 = VsdxShapeFactory.rectangle(
        id: 1, pinX: 1, pinY: 1, width: 1, height: 1);
    final r2 = VsdxShapeFactory.rectangle(
        id: 2, pinX: 5, pinY: 5, width: 1, height: 1);
    final conn = VsdxShapeFactory.line(id: 3, ax: 1, ay: 1, bx: 5, by: 5);
    var page = VsdxPage(
      id: 0,
      name: 'P1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: [r1, r2, conn],
      connects: const [
        VsdxConnect(
            fromSheetId: 3, fromCell: 'BeginX', toSheetId: 1, toCell: 'PinX'),
        VsdxConnect(
            fromSheetId: 3, fromCell: 'EndX', toSheetId: 2, toCell: 'PinX'),
      ],
    );

    // Move r2 to a new centre; the connector's end must follow, attaching to
    // the shapes' bounding-box edges (not their centres).
    page = page
        .updateShapeById(2, (s) => s.copyWith(pinX: 7, pinY: 3))
        .rerouteConnectors();

    final connector = page.findShapeById(3)!;
    // r1 (1,1) 1x1 → right edge x = 1.5 toward the moved r2.
    expect(connector.beginX, closeTo(1.5, 1e-6));
    // r2 moved to (7,3) 1x1 → left edge x = 6.5 toward r1.
    expect(connector.endX, closeTo(6.5, 1e-6));
    // The end followed the moved shape (within its vertical extent).
    expect(connector.endY, inInclusiveRange(2.5, 3.5));
  });

  test('a glued connector routes as an elbow between offset shapes', () {
    final r1 = VsdxShapeFactory.rectangle(
        id: 1, pinX: 1, pinY: 1, width: 1, height: 1);
    final r2 = VsdxShapeFactory.rectangle(
        id: 2, pinX: 5, pinY: 4, width: 1, height: 1);
    final conn = VsdxShapeFactory.line(id: 3, ax: 1, ay: 1, bx: 5, by: 4);
    final page = VsdxPage(
      id: 0,
      name: 'P1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: [r1, r2, conn],
      connects: const [
        VsdxConnect(
            fromSheetId: 3, fromCell: 'BeginX', toSheetId: 1, toCell: 'PinX'),
        VsdxConnect(
            fromSheetId: 3, fromCell: 'EndX', toSheetId: 2, toCell: 'PinX'),
      ],
    ).rerouteConnectors();

    // Elbow route => more than a single straight segment (MoveTo + 2+ LineTo).
    expect(page.findShapeById(3)!.geometries.first.commands.length,
        greaterThan(2));
  });

  test('curveThrough samples a smooth spline that hits its control points', () {
    const control = <Offset2D>[
      Offset2D(0, 0),
      Offset2D(2, 3),
      Offset2D(5, 1),
    ];
    final curve = VsdxPage.curveThrough(control, segmentsPerSpan: 8);
    // Endpoints stay exact and the sampled polyline is far denser.
    expect(curve.first, const Offset2D(0, 0));
    expect(curve.last, const Offset2D(5, 1));
    expect(curve.length, 1 + (control.length - 1) * 8);
    // The interior control point lies on the sampled curve (segment boundary).
    expect(
      curve.any((p) => (p.x - 2).abs() < 1e-9 && (p.y - 3).abs() < 1e-9),
      isTrue,
    );
    // Fewer than three points can't bend — returned unchanged.
    expect(
      VsdxPage.curveThrough(const <Offset2D>[Offset2D(0, 0), Offset2D(1, 1)]),
      hasLength(2),
    );
  });

  test('a curved connector bakes a smooth polyline that survives reroute', () {
    final r1 = VsdxShapeFactory.rectangle(
        id: 1, pinX: 1, pinY: 1, width: 1, height: 1);
    final r2 = VsdxShapeFactory.rectangle(
        id: 2, pinX: 5, pinY: 4, width: 1, height: 1);
    final conn = VsdxShapeFactory.line(id: 3, ax: 1, ay: 1, bx: 5, by: 4);
    var page = VsdxPage(
      id: 0,
      name: 'P1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: [r1, r2, conn],
      connects: const [
        VsdxConnect(
            fromSheetId: 3, fromCell: 'BeginX', toSheetId: 1, toCell: 'PinX'),
        VsdxConnect(
            fromSheetId: 3, fromCell: 'EndX', toSheetId: 2, toCell: 'PinX'),
      ],
    ).rerouteConnectors();

    final elbowCount = page.findShapeById(3)!.geometries.first.commands.length;

    // Switch to curved: geometry becomes a dense smooth polyline.
    page = page.setConnectorStyle({3}, straight: false, curved: true);
    final curved = page.findShapeById(3)!;
    expect(curved.curved, isTrue);
    expect(curved.straightRoute, isFalse);
    expect(page.isConnectorCurved(3), isTrue);
    expect(curved.geometries.first.commands.length, greaterThan(elbowCount));
    // Purely MoveTo/LineTo — so it round-trips as ordinary geometry.
    expect(
      curved.geometries.first.commands
          .every((c) => c is MoveTo || c is LineTo),
      isTrue,
    );

    // Moving a glued shape re-routes but keeps the curved preference + density.
    page = page
        .updateShapeById(1, (s) => s.copyWith(pinX: 2, pinY: 2))
        .rerouteConnectors();
    final rerouted = page.findShapeById(3)!;
    expect(rerouted.curved, isTrue);
    expect(rerouted.geometries.first.commands.length, greaterThan(elbowCount));
  });

  test('roundCorners fillets interior bends but keeps the endpoints exact', () {
    // An L route with one sharp 90° corner at (4, 0).
    const control = <Offset2D>[
      Offset2D(0, 0),
      Offset2D(4, 0),
      Offset2D(4, 4),
    ];
    final rounded = VsdxPage.roundCorners(control, radius: 1, segmentsPerCorner: 6);
    // Endpoints stay put; the polyline is denser than the 3-point control.
    expect(rounded.first, const Offset2D(0, 0));
    expect(rounded.last, const Offset2D(4, 4));
    expect(rounded.length, greaterThan(control.length));
    // The sharp corner vertex itself is gone — the fillet backs off from it.
    expect(
      rounded.any((p) => (p.x - 4).abs() < 1e-9 && (p.y - 0).abs() < 1e-9),
      isFalse,
    );
    // Every filleted point stays within the corner's quadrant (0..4, 0..4).
    for (final p in rounded) {
      expect(p.x, inInclusiveRange(0 - 1e-9, 4 + 1e-9));
      expect(p.y, inInclusiveRange(0 - 1e-9, 4 + 1e-9));
    }
    // Fewer than three points can't bend — returned unchanged.
    expect(
      VsdxPage.roundCorners(const <Offset2D>[Offset2D(0, 0), Offset2D(2, 2)]),
      hasLength(2),
    );
  });

  test('a rounded connector bakes filleted corners that survive reroute', () {
    final r1 = VsdxShapeFactory.rectangle(
        id: 1, pinX: 1, pinY: 1, width: 1, height: 1);
    final r2 = VsdxShapeFactory.rectangle(
        id: 2, pinX: 5, pinY: 4, width: 1, height: 1);
    final conn = VsdxShapeFactory.line(id: 3, ax: 1, ay: 1, bx: 5, by: 4);
    var page = VsdxPage(
      id: 0,
      name: 'P1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: [r1, r2, conn],
      connects: const [
        VsdxConnect(
            fromSheetId: 3, fromCell: 'BeginX', toSheetId: 1, toCell: 'PinX'),
        VsdxConnect(
            fromSheetId: 3, fromCell: 'EndX', toSheetId: 2, toCell: 'PinX'),
      ],
    ).rerouteConnectors();

    final elbowCount = page.findShapeById(3)!.geometries.first.commands.length;
    final elbowBegin =
        (page.findShapeById(3)!.beginX!, page.findShapeById(3)!.beginY!);
    final elbowEnd =
        (page.findShapeById(3)!.endX!, page.findShapeById(3)!.endY!);

    // Round the corners: geometry densifies but endpoints stay pinned.
    page = page.setConnectorRounded({3}, true);
    final rounded = page.findShapeById(3)!;
    expect(rounded.rounded, isTrue);
    expect(page.isConnectorRounded(3), isTrue);
    expect(rounded.geometries.first.commands.length, greaterThan(elbowCount));
    // Still ordinary MoveTo/LineTo — so it round-trips as plain geometry.
    expect(
      rounded.geometries.first.commands.every((c) => c is MoveTo || c is LineTo),
      isTrue,
    );
    expect(rounded.beginX, closeTo(elbowBegin.$1, 1e-9));
    expect(rounded.beginY, closeTo(elbowBegin.$2, 1e-9));
    expect(rounded.endX, closeTo(elbowEnd.$1, 1e-9));
    expect(rounded.endY, closeTo(elbowEnd.$2, 1e-9));

    // Moving a glued shape re-routes but keeps the rounded preference + density.
    page = page
        .updateShapeById(1, (s) => s.copyWith(pinX: 2, pinY: 2))
        .rerouteConnectors();
    final rerouted = page.findShapeById(3)!;
    expect(rerouted.rounded, isTrue);
    expect(rerouted.geometries.first.commands.length, greaterThan(elbowCount));
  });

  test('connectorMidpoint returns the arc-length midpoint of the route', () {
    // Straight horizontal connector: the midpoint is the geometric centre.
    final straight = VsdxShapeFactory.line(id: 1, ax: 1, ay: 2, bx: 5, by: 2)
        .copyWith(straightRoute: true);
    final m = VsdxPage.connectorMidpoint(straight);
    expect(m.x, closeTo(3, 1e-9));
    expect(m.y, closeTo(2, 1e-9));

    // Route with a waypoint: (0,0) → (0,4) → (4,0). Segment lengths 4 and
    // 4√2; the arc-length midpoint lands part-way down the second segment.
    final bent = VsdxShapeFactory.line(id: 2, ax: 0, ay: 0, bx: 4, by: 0)
        .copyWith(waypoints: const <Offset2D>[Offset2D(0, 4)]);
    final m2 = VsdxPage.connectorMidpoint(bent);
    expect(m2.x, closeTo(0.585786, 1e-4));
    expect(m2.y, closeTo(3.414214, 1e-4));
  });

  test('document.replacePage swaps a single page immutably', () {
    final doc = parser.parse(_fixture('test1.vsdx'));
    final page0 = doc.pages.first;
    final edited = page0.updateShapeById(
      page0.shapes.first.id,
      (s) => s.copyWith(pinX: s.pinX + 1),
    );
    final newDoc = doc.replacePage(0, edited);

    expect(identical(newDoc, doc), isFalse);
    expect(newDoc.pages.first.shapes.first.pinX,
        closeTo(page0.shapes.first.pinX + 1, 1e-9));
    // Original document unchanged.
    expect(doc.pages.first.shapes.first.pinX, page0.shapes.first.pinX);
  });
}
