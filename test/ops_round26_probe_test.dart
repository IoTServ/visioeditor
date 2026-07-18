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

  int rect(EditorController e, double x, double y) {
    e.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1, height: 0.6),
        x,
        y);
    return e.singleSelectedId!;
  }

  test('deleteSelection scrubs connector Connect rows', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    expect(e.currentPage!.connects, isNotEmpty);
    e.setSelection([conn]);
    e.deleteSelection();
    expect(e.currentPage!.findShapeById(conn), isNull);
    expect(
      e.currentPage!.connects.any((c) => c.fromSheetId == conn),
      isFalse,
    );
  });

  test('deleteSelection of target scrubs toSheet Connect rows', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([b]);
    e.deleteSelection();
    expect(e.currentPage!.findShapeById(b), isNull);
    expect(e.currentPage!.findShapeById(conn), isNotNull);
    expect(
      e.currentPage!.connects.any((c) => c.toSheetId == b),
      isFalse,
    );
  });

  test('cut connector scrubs page Connect rows', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.cut();
    expect(
      e.currentPage!.connects.any((c) => c.fromSheetId == conn),
      isFalse,
    );
  });

  test('unfold after deleting connector while folded has no zombie glue', () {
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
    e.updateCurrentPage(
      (p) => p
          .addShape(
            VsdxShapeFactory.rectangle(
              id: childId,
              pinX: 4,
              pinY: 3.5,
              width: 1,
              height: 0.8,
            ),
          )
          .reparentShape(childId, box.id),
    );
    final outer = rect(e, 1, 4);
    e.createConnector(1, 4, 4, 3.5, beginTarget: outer, endTarget: childId);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;

    e.toggleCollapsed(box.id);
    expect(e.isCollapsed(box.id), isTrue);
    e.setSelection([conn]);
    e.deleteSelection();
    e.toggleCollapsed(box.id);
    expect(e.isCollapsed(box.id), isFalse);
    expect(
      e.currentPage!.connects.any((c) => c.fromSheetId == conn),
      isFalse,
    );
    expect(
      e.currentPage!
          .findShapeById(box.id)!
          .userCells
          .any((c) => c.name == VsdxShape.userCollapsedGlue),
      isFalse,
    );
  });

  test('removeSelectedLane on locked lane is no-op', () {
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
    final lane =
        SwimlaneOps.lanesOf(e.currentPage!.findShapeById(poolId)!).first;
    e.setSelection([lane.id]);
    e.setSelectionLocked(true);
    expect(e.canRemoveLane, isFalse);
    e.removeSelectedLane();
    expect(
      SwimlaneOps.lanesOf(e.currentPage!.findShapeById(poolId)!).length,
      2,
    );
  });

  test('mergeSelectedCells refuses when any cell is locked', () {
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
    e.setSelection([cells[0].id]);
    e.setSelectionLocked(true);
    e.setSelection([cells[0].id, cells[1].id]);
    expect(e.canMergeCells, isFalse);
    e.mergeSelectedCells();
    expect(
      TableOps.isMerged(
        TableOps.cellsOf(e.currentPage!.findShapeById(tableId)!).first,
      ),
      isFalse,
    );
  });

  test('isShapeVisible respects layer visibility', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.addLayer(name: 'HideMe');
    final layerId = e.currentPage!.layers.last.id;
    e.setSelection([a]);
    e.assignSelectionToLayer(layerId);
    expect(e.currentPage!.isShapeVisible(e.currentPage!.findShapeById(a)!),
        isTrue);
    e.toggleLayerVisibility(layerId);
    expect(e.currentPage!.isShapeVisible(e.currentPage!.findShapeById(a)!),
        isFalse);
  });

  test('movePageGuide updates position; survives page switch', () {
    final e = ctrl();
    e.addPageGuide(vertical: true, pos: 2);
    expect(e.pageGuides.single.pos, closeTo(2, 1e-9));
    e.movePageGuide(0, 3.5);
    expect(e.pageGuides.single.pos, closeTo(3.5, 1e-9));
    e.addPage();
    e.selectPage(1);
    expect(e.pageGuides, isEmpty);
    e.selectPage(0);
    expect(e.pageGuides.single.pos, closeTo(3.5, 1e-9));
  });

  test('reparentShape preserves Connect rows', () {
    final e = ctrl();
    final box = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final before = e.currentPage!.connects.length;
    e.setSelection([a]);
    e.reparentSelectionInto(box.id);
    expect(e.currentPage!.connects.length, before);
    expect(
      e.currentPage!.connects.any((c) => c.toSheetId == a),
      isTrue,
    );
  });
}
