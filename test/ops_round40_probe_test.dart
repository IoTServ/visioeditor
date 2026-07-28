import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EditorController ctrl() {
    final c = EditorController()
      ..newDocument(widthInches: 11, heightInches: 8.5);
    addTearDown(c.dispose);
    return c;
  }

  int rect(
    EditorController e,
    double x,
    double y, {
    double w = 1,
    double h = 0.6,
  }) {
    e.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: w,
        height: h,
      ),
      x,
      y,
    );
    return e.singleSelectedId!;
  }

  (double, double) centre(VsdxPage page, int id) {
    final b = page.shapePageAabb(id)!;
    return ((b.left + b.right) / 2, (b.bottom + b.top) / 2);
  }

  test('swapSelectionPositions exchanges page centres and is undoable', () {
    final e = ctrl();
    final a = rect(e, 2, 3, w: 2, h: 1);
    final b = rect(e, 7, 5, w: 1, h: 2);
    final beforeA = centre(e.currentPage!, a);
    final beforeB = centre(e.currentPage!, b);

    e.setSelection([a, b]);
    expect(e.canSwapSelection, isTrue);
    e.swapSelectionPositions();

    expect(centre(e.currentPage!, a).$1, closeTo(beforeB.$1, 1e-9));
    expect(centre(e.currentPage!, a).$2, closeTo(beforeB.$2, 1e-9));
    expect(centre(e.currentPage!, b).$1, closeTo(beforeA.$1, 1e-9));
    expect(centre(e.currentPage!, b).$2, closeTo(beforeA.$2, 1e-9));
    expect(e.currentPage!.findShapeById(a)!.width, 2);
    expect(e.currentPage!.findShapeById(b)!.height, 2);

    e.undo();
    expect(centre(e.currentPage!, a).$1, closeTo(beforeA.$1, 1e-9));
    expect(centre(e.currentPage!, b).$1, closeTo(beforeB.$1, 1e-9));
  });

  test('copy and paste size preserves target page top-left', () {
    final e = ctrl();
    final source = rect(e, 2, 4, w: 2.5, h: 1.25);
    final target = rect(e, 7, 4, w: 1, h: 0.5);
    e.setSelection([source]);
    expect(e.canCopySize, isTrue);
    e.copySelectionSize();

    e.setSelection([target]);
    final before = e.currentPage!.shapePageAabb(target)!;
    expect(e.canPasteSize, isTrue);
    e.pasteSelectionSize();

    final shape = e.currentPage!.findShapeById(target)!;
    final after = e.currentPage!.shapePageAabb(target)!;
    expect(shape.width, closeTo(2.5, 1e-9));
    expect(shape.height, closeTo(1.25, 1e-9));
    expect(after.left, closeTo(before.left, 1e-9));
    expect(after.top, closeTo(before.top, 1e-9));

    e.undo();
    expect(e.currentPage!.findShapeById(target)!.width, closeTo(1, 1e-9));
    expect(e.canPasteSize, isTrue);
  });

  test('reverse connector swaps glue, fixed points, route, and arrows', () {
    final e = ctrl();
    final a = rect(e, 2, 4, w: 1.5, h: 1);
    final b = rect(e, 7, 4, w: 1.5, h: 1);
    e.createConnector(
      2,
      4,
      7,
      4,
      beginTarget: a,
      endTarget: b,
      beginConnectionPointIndex: 1,
      endConnectionPointIndex: 3,
    );
    final connectorId = e.singleSelectedId!;
    e.setConnectorWaypoints(connectorId, const <Offset2D>[
      Offset2D(3, 5),
      Offset2D(6, 3),
    ]);
    final before = e.currentPage!.findShapeById(connectorId)!;
    expect(before.line.beginArrow, 0);
    expect(before.line.endArrow, 4);

    e.reverseSelectedConnectors();

    final page = e.currentPage!;
    final connector = page.findShapeById(connectorId)!;
    final begin = page.connects.firstWhere(
      (c) => c.fromSheetId == connectorId && c.isBegin,
    );
    final end = page.connects.firstWhere(
      (c) => c.fromSheetId == connectorId && c.isEnd,
    );
    expect(begin.toSheetId, b);
    expect(begin.toPart, 103);
    expect(end.toSheetId, a);
    expect(end.toPart, 101);
    expect(connector.waypoints, hasLength(2));
    expect(connector.waypoints.first.x, closeTo(6, 1e-9));
    expect(connector.waypoints.last.x, closeTo(3, 1e-9));
    expect(connector.line.beginArrow, 4);
    expect(connector.line.endArrow, 0);
    expect(connector.formulas['BegTrigger'], contains('Sheet.$b'));
    expect(connector.formulas['EndTrigger'], contains('Sheet.$a'));

    e.undo();
    final restored = e.currentPage!.findShapeById(connectorId)!;
    expect(restored.line.beginArrow, 0);
    expect(restored.line.endArrow, 4);
  });

  test('reverse connector preserves imported baked bends as waypoints', () {
    final connector = VsdxShapeFactory.line(
      id: 1,
      ax: 1,
      ay: 1,
      bx: 5,
      by: 4,
    ).copyWith(straightRoute: false).reshapeAsPolyline(
      const <Offset2D>[
        Offset2D(1, 1),
        Offset2D(2, 3),
        Offset2D(4, 2),
        Offset2D(5, 4),
      ],
    );
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 11,
      heightInches: 8.5,
      shapes: <VsdxShape>[connector],
    ).reverseConnector(1);
    final reversed = page.findShapeById(1)!;

    expect(reversed.beginX, closeTo(5, 1e-9));
    expect(reversed.beginY, closeTo(4, 1e-9));
    expect(reversed.endX, closeTo(1, 1e-9));
    expect(reversed.endY, closeTo(1, 1e-9));
    expect(
      reversed.waypoints,
      const <Offset2D>[Offset2D(4, 2), Offset2D(2, 3)],
    );
  });
}
