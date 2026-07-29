import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  EditorController ctrl() {
    final c = EditorController()
      ..newDocument(widthInches: 11, heightInches: 8.5);
    addTearDown(c.dispose);
    return c;
  }

  int rect(EditorController e, double x, double y,
      {double w = 1, double h = 0.6}) {
    e.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: w, height: h),
        x,
        y);
    return e.singleSelectedId!;
  }

  /// Palette drops now materialise default glue points; clear them when a test
  /// needs an intentionally empty Connection section (locked-shape guards).
  void clearConnectionPoints(EditorController e, int shapeId) {
    e.updateCurrentPage(
      (p) => p.updateShapeById(
        shapeId,
        (s) => s.copyWith(connectionPoints: const <VsdxConnectionPoint>[]),
      ),
    );
  }

  void lockOnLayer(EditorController e, int shapeId) {
    e.updateCurrentPage((p) {
      final layers = <VsdxLayer>[
        ...p.layers,
        const VsdxLayer(id: 99, name: 'Locked', locked: true),
      ];
      return p.copyWith(layers: layers).updateShapeById(
            shapeId,
            (s) => s.copyWith(layerMemberIds: const <int>[99]),
          );
    });
  }

  test('createConnector with CP index does not materialize on locked target',
      () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    clearConnectionPoints(e, a);
    clearConnectionPoints(e, b);
    e.setSelection([b]);
    e.setSelectionLocked(true);
    expect(e.currentPage!.findShapeById(b)!.connectionPoints, isEmpty);

    e.createConnector(
      2,
      4,
      5,
      4,
      beginTarget: a,
      endTarget: b,
      beginConnectionPointIndex: 0,
      endConnectionPointIndex: 2,
    );

    expect(e.currentPage!.findShapeById(b)!.connectionPoints, isEmpty);
    // Unlocked begin target may still materialize.
    expect(e.currentPage!.findShapeById(a)!.connectionPoints, isNotEmpty);
    expect(
      e.currentPage!.connects.any((c) => c.toSheetId == b),
      isTrue,
    );
  });

  test('createConnector CP index skips materialize on locked-layer target', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    clearConnectionPoints(e, b);
    lockOnLayer(e, b);
    expect(e.isOnLockedLayer(b), isTrue);

    e.createConnector(
      2,
      4,
      5,
      4,
      beginTarget: a,
      endTarget: b,
      endConnectionPointIndex: 1,
    );

    expect(e.currentPage!.findShapeById(b)!.connectionPoints, isEmpty);
  });

  test('reconnectEndpoint does not materialize CPs on locked target', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    clearConnectionPoints(e, a);
    clearConnectionPoints(e, b);
    // Whole-shape glue — does not materialize CPs.
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    expect(e.currentPage!.findShapeById(b)!.connectionPoints, isEmpty);
    e.setSelection([b]);
    e.setSelectionLocked(true);

    e.reconnectEndpoint(
      conn,
      begin: false,
      targetShapeId: b,
      connectionPointIndex: 0,
      x: 5,
      y: 4,
    );

    expect(e.currentPage!.findShapeById(b)!.connectionPoints, isEmpty);
    expect(
      e.currentPage!.connects.any(
        (c) => c.fromSheetId == conn && c.toSheetId == b,
      ),
      isTrue,
    );
  });

  test('addWaypoint on locked-layer connector is no-op', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    lockOnLayer(e, conn);
    e.addWaypoint(conn, 0, const Offset2D(3.5, 5));
    expect(e.currentPage!.findShapeById(conn)!.waypoints, isEmpty);
  });

  test('materializeConnectionPoints no-op on locked shape', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    clearConnectionPoints(e, a);
    e.setSelection([a]);
    e.setSelectionLocked(true);
    final next = e.currentPage!.materializeConnectionPoints(a);
    expect(next.findShapeById(a)!.connectionPoints, isEmpty);
  });

  test('custom fixed point falls back to whole-shape glue on locked target',
      () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    clearConnectionPoints(e, b);
    e.setSelection([b]);
    e.setSelectionLocked(true);

    e.createConnector(
      2,
      4,
      5,
      4,
      beginTarget: a,
      endTarget: b,
      endFixedAtPosition: true,
    );

    final page = e.currentPage!;
    final connector = e.singleSelectedId!;
    expect(page.findShapeById(b)!.connectionPoints, isEmpty);
    final end = page.connects.singleWhere(
      (c) => c.fromSheetId == connector && c.isEnd,
    );
    expect(end.toSheetId, b);
    expect(VsdxPage.fixedConnectionIndex(end), isNull);
    expect(end.toPart, 3);
    expect(
      page.addConnectionPoint(b, 0.5, 0.3).findShapeById(b)!.connectionPoints,
      isEmpty,
    );
  });

  test('resizeTableRow undo; locked table is no-op', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(
      (id, cx, cy) => TableOps.assembleTable(
        tableId: id,
        pinX: cx,
        pinY: cy,
        width: 2.4,
        height: 1.2,
        rows: 2,
        cols: 2,
      ),
      4,
      4,
    );
    final tableId = e.singleSelectedId!;
    final h0 = TableOps.cellsOf(e.currentPage!.findShapeById(tableId)!).first.height;
    e.resizeTableRow(tableId, 0, 0.2);
    final h1 = TableOps.cellsOf(e.currentPage!.findShapeById(tableId)!).first.height;
    expect(h1, isNot(closeTo(h0, 1e-9)));
    e.undo();
    expect(
      TableOps.cellsOf(e.currentPage!.findShapeById(tableId)!).first.height,
      closeTo(h0, 1e-9),
    );

    e.setSelection([tableId]);
    e.setSelectionLocked(true);
    e.resizeTableRow(tableId, 0, 0.3);
    expect(
      TableOps.cellsOf(e.currentPage!.findShapeById(tableId)!).first.height,
      closeTo(h0, 1e-9),
    );
  });

  test('addColumnToSelectedTable on locked table is no-op', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(
      (id, cx, cy) => TableOps.assembleTable(
        tableId: id,
        pinX: cx,
        pinY: cy,
        width: 2.4,
        height: 1.0,
        rows: 2,
        cols: 2,
      ),
      4,
      4,
    );
    final tableId = e.singleSelectedId!;
    e.setSelectionLocked(true);
    expect(e.canAddTableColumn, isFalse);
    e.addColumnToSelectedTable();
    expect(TableOps.dimensions(e.currentPage!.findShapeById(tableId)!).cols, 2);
  });

  test('commitTransaction folds move + drop into one undo', () {
    final e = ctrl();
    final box = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    final child = rect(e, 1, 1);
    e.setSelection([child]);
    e.beginTransaction();
    e.moveSelectionBy(3, 3, transient: true);
    e.applyDropContainmentAt(4, 4, transient: true);
    e.commitTransaction();
    expect(e.currentPage!.findParentId(child), box.id);
    e.undo();
    expect(e.currentPage!.findParentId(child), isNull);
    expect(e.currentPage!.shapePinPage(child).x, closeTo(1, 0.2));
  });

  test('alignRight single selection snaps to page edge; locked no-op', () {
    final e = ctrl();
    final a = rect(e, 3, 4, w: 1, h: 0.6);
    e.setSelection([a]);
    e.alignRight();
    final s = e.currentPage!.findShapeById(a)!;
    final right = e.currentPage!.shapePinPage(a).x + s.width / 2;
    expect(right, closeTo(e.currentPage!.widthInches, 1e-6));

    e.moveSelectionBy(-2, 0);
    e.setSelectionLocked(true);
    final xLocked = e.currentPage!.shapePinPage(a).x;
    e.alignRight();
    expect(e.currentPage!.shapePinPage(a).x, closeTo(xLocked, 1e-9));
  });
}
