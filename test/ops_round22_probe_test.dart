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

  test('addLaneToSelectedPool on locked pool is no-op', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(
      (id, cx, cy) => SwimlaneOps.assemblePool(
        poolId: id,
        pinX: cx,
        pinY: cy,
        width: 5,
        height: 3,
        laneCount: 2,
      ),
      4,
      4,
    );
    final poolId = e.singleSelectedId!;
    e.setSelectionLocked(true);
    expect(e.currentPage!.findShapeById(poolId)!.locked, isTrue);
    final before =
        SwimlaneOps.lanesOf(e.currentPage!.findShapeById(poolId)!).length;
    expect(e.canAddLane, isFalse);
    e.addLaneToSelectedPool();
    expect(
      SwimlaneOps.lanesOf(e.currentPage!.findShapeById(poolId)!).length,
      before,
    );
  });

  test('addRowToSelectedTable on locked table is no-op', () {
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
    expect(e.currentPage!.findShapeById(tableId)!.locked, isTrue);
    expect(e.canAddTableRow, isFalse);
    e.addRowToSelectedTable();
    expect(TableOps.dimensions(e.currentPage!.findShapeById(tableId)!).rows, 2);
  });

  test('applyDropContainmentAt skips locked shapes', () {
    final e = ctrl();
    final box = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    // Create outside the host so palette auto-containment does not nest first.
    final child = rect(e, 1, 1);
    e.setSelection([child]);
    e.setSelectionLocked(true);
    e.applyDropContainmentAt(4, 4, transient: false);
    expect(e.currentPage!.findParentId(child), isNull);
  });

  test('toggleCollapsed fold then unfold restores glue', () {
    final e = ctrl();
    final box = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    final childId = e.currentPage!.nextFreeShapeId();
    final child = VsdxShapeFactory.rectangle(
      id: childId,
      pinX: 4,
      pinY: 3.5,
      width: 1,
      height: 0.8,
    );
    e.updateCurrentPage(
        (p) => p.addShape(child).reparentShape(childId, box.id));
    final outer = rect(e, 1, 4);
    e.createConnector(1, 4, 4, 3.5, beginTarget: outer, endTarget: childId);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    expect(
      e.currentPage!.connects.any(
        (c) => c.fromSheetId == conn && c.toSheetId == childId,
      ),
      isTrue,
    );

    e.toggleCollapsed(box.id);
    expect(e.isCollapsed(box.id), isTrue);
    expect(
      e.currentPage!.connects.any((c) => c.toSheetId == childId),
      isFalse,
    );

    e.toggleCollapsed(box.id);
    expect(e.isCollapsed(box.id), isFalse);
    expect(
      e.currentPage!.connects.any(
        (c) => c.fromSheetId == conn && c.toSheetId == childId,
      ),
      isTrue,
    );
  });

  test('newDocument clears page guides from prior document', () {
    final e = ctrl();
    e.addPageGuide(vertical: true, pos: 3);
    expect(e.pageGuides, isNotEmpty);
    e.newDocument(widthInches: 11, heightInches: 8.5);
    expect(e.pageGuides, isEmpty);
  });

  test('mergeSelectedCells on locked table is no-op', () {
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
    final cells = TableOps.cellsOf(e.currentPage!.findShapeById(tableId)!);
    e.setSelection([cells[0].id, cells[1].id]);
    e.setSelection([tableId]);
    e.setSelectionLocked(true);
    e.setSelection([cells[0].id, cells[1].id]);
    // Table host is locked; structure edits must refuse.
    expect(e.canMergeCells, isFalse);
    e.mergeSelectedCells();
    final after = TableOps.cellsOf(e.currentPage!.findShapeById(tableId)!);
    expect(TableOps.isMerged(after[0]), isFalse);
  });

  test('alignLeft with single selection snaps to page edge', () {
    final e = ctrl();
    final a = rect(e, 3, 4, w: 1, h: 0.6);
    e.setSelection([a]);
    e.alignLeft();
    final s = e.currentPage!.findShapeById(a)!;
    final left = e.currentPage!.shapePinPage(a).x - s.width / 2;
    expect(left, closeTo(0, 1e-6));
  });

  test('resizeTableColumn on locked table is no-op', () {
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
    final before = e.currentPage!.findShapeById(tableId)!;
    final w0 = TableOps.cellsOf(before).first.width;
    e.setSelectionLocked(true);
    e.resizeTableColumn(tableId, 0, 0.3);
    final after = e.currentPage!.findShapeById(tableId)!;
    expect(TableOps.cellsOf(after).first.width, closeTo(w0, 1e-9));
  });
}
