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

  test('unmergeSelectedCell on locked table is no-op', () {
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
    e.mergeSelectedCells();
    final master = e.singleSelectedId!;
    expect(TableOps.isMerged(e.currentPage!.findShapeById(master)!), isTrue);

    e.setSelection([tableId]);
    e.setSelectionLocked(true);
    e.setSelection([master]);
    expect(e.canUnmergeCell, isFalse);
    e.unmergeSelectedCell();
    expect(TableOps.isMerged(e.currentPage!.findShapeById(master)!), isTrue);
  });

  test('alignTop / alignBottom / alignMiddle page align', () {
    final e = ctrl();
    final a = rect(e, 3, 4, w: 1, h: 0.6);
    e.setSelection([a]);
    e.alignTop();
    var s = e.currentPage!.findShapeById(a)!;
    final top = e.currentPage!.shapePinPage(a).y + s.height / 2;
    expect(top, closeTo(e.currentPage!.heightInches, 1e-6));

    e.alignBottom();
    s = e.currentPage!.findShapeById(a)!;
    final bottom = e.currentPage!.shapePinPage(a).y - s.height / 2;
    expect(bottom, closeTo(0, 1e-6));

    e.alignMiddle();
    expect(
      e.currentPage!.shapePinPage(a).y,
      closeTo(e.currentPage!.heightInches / 2, 1e-6),
    );
  });

  test('setSelectedY moves AABB top; locked is no-op', () {
    final e = ctrl();
    final a = rect(e, 3, 4);
    e.setSelection([a]);
    e.setSelectedY(2);
    final page = e.currentPage!;
    final s = page.findShapeById(a)!;
    final topFromPageTop = page.heightInches - (page.shapePinPage(a).y + s.height / 2);
    expect(topFromPageTop, closeTo(2, 0.15));
    e.setSelectionLocked(true);
    e.setSelectedY(5);
    final topLocked =
        page.heightInches - (e.currentPage!.shapePinPage(a).y + s.height / 2);
    expect(topLocked, closeTo(2, 0.15));
  });

  test('toggleLayerPrint toggles and undoes', () {
    final e = ctrl();
    e.addLayer(name: 'PrintMe');
    final layerId = e.currentPage!.layers.last.id;
    final before = e.currentPage!.layers.lastWhere((l) => l.id == layerId).print;
    e.toggleLayerPrint(layerId);
    expect(
      e.currentPage!.layers.lastWhere((l) => l.id == layerId).print,
      isNot(before),
    );
    e.undo();
    expect(
      e.currentPage!.layers.lastWhere((l) => l.id == layerId).print,
      before,
    );
  });

  test('cancelTransaction discards move', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelection([a]);
    final x0 = e.currentPage!.shapePinPage(a).x;
    e.beginTransaction();
    e.moveSelectionBy(2, 0, transient: true);
    expect(e.currentPage!.shapePinPage(a).x, closeTo(x0 + 2, 0.2));
    e.cancelTransaction();
    expect(e.currentPage!.shapePinPage(a).x, closeTo(x0, 0.2));
    // Cancelled transient must not leave a move on the undo stack.
    e.undo(); // undoes shape creation
    expect(e.currentPage!.findShapeById(a), isNull);
  });

  test('selectNextShape reverse cycles selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    final c = rect(e, 6, 4);
    e.setSelection([b]);
    e.selectNextShape(reverse: true);
    expect(e.selection.length, 1);
    expect(e.selection.contains(b), isFalse);
    // Still one of the page shapes.
    expect({a, b, c}.contains(e.selection.single), isTrue);
  });

  test('setBeginArrowSize only affects 1D', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    final boxSizeBefore =
        e.currentPage!.findShapeById(a)!.line.beginArrowSizeInches;
    e.setSelection([a, conn]);
    e.setBeginArrowSize(0.25);
    expect(
      e.currentPage!.findShapeById(conn)!.line.beginArrowSizeInches,
      closeTo(0.25, 1e-9),
    );
    expect(
      e.currentPage!.findShapeById(a)!.line.beginArrowSizeInches,
      boxSizeBefore,
    );
  });

  test('dontMoveChildren container move keeps child page pin', () {
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
    // Mark container dontMoveChildren if supported.
    final host = e.currentPage!.findShapeById(box.id)!;
    if (!host.dontMoveChildren) {
      e.updateCurrentPage(
        (p) => p.updateShapeById(
          box.id,
          (s) => s.copyWith(dontMoveChildren: true),
        ),
      );
    }
    final childPageBefore = e.currentPage!.shapePinPage(childId);
    e.setSelection([box.id]);
    e.moveSelectionBy(1, 0);
    final childPageAfter = e.currentPage!.shapePinPage(childId);
    expect(childPageAfter.x, closeTo(childPageBefore.x, 1e-6));
    expect(childPageAfter.y, closeTo(childPageBefore.y, 1e-6));
  });
}
