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

  test('distributeVertically keeps locked middle shape fixed', () {
    final e = ctrl();
    final a = rect(e, 2, 2);
    final b = rect(e, 2, 4);
    final c = rect(e, 2, 7);
    e.setSelection([b]);
    e.setSelectionLocked(true);
    final midY = e.currentPage!.shapePinPage(b).y;
    e.setSelection([a, b, c]);
    e.distributeVertically();
    expect(e.currentPage!.shapePinPage(b).y, closeTo(midY, 1e-9));
    expect(e.currentPage!.findShapeById(b)!.locked, isTrue);
  });

  test('matchSelectionHeight uses 2D reference not 1D', () {
    final e = ctrl();
    final a = rect(e, 2, 4, h: 0.6);
    final b = rect(e, 5, 4, h: 1.2);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    // Leading connector must not become the size reference.
    e.setSelection([conn, b, a]);
    e.matchSelectionHeight();
    expect(e.currentPage!.findShapeById(a)!.height, closeTo(1.2, 1e-6));
    expect(e.currentPage!.findShapeById(b)!.height, closeTo(1.2, 1e-6));
    expect(e.currentPage!.findShapeById(a)!.height, greaterThan(0.5));
  });

  test('removeColumnFromSelectedTable removes selected column', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(
      (id, cx, cy) => TableOps.assembleTable(
        tableId: id,
        pinX: cx,
        pinY: cy,
        width: 3.0,
        height: 1.0,
        rows: 2,
        cols: 3,
      ),
      4,
      4,
    );
    final tableId = e.singleSelectedId!;
    final cells = TableOps.cellsOf(e.currentPage!.findShapeById(tableId)!);
    final col0 = cells.firstWhere((c) => TableOps.cellCol(c) == 0);
    e.setSelection([col0.id]);
    e.removeColumnFromSelectedTable();
    expect(TableOps.dimensions(e.currentPage!.findShapeById(tableId)!).cols, 2);
    e.undo();
    expect(TableOps.dimensions(e.currentPage!.findShapeById(tableId)!).cols, 3);
  });

  test('setBackgroundPage rejects self and undoes', () {
    final e = ctrl();
    e.addPage();
    final a = e.document!.pages[0].id;
    final b = e.document!.pages[1].id;
    e.selectPage(0);
    e.setBackgroundPage(a); // self — no-op
    expect(e.document!.pages[0].isBackgroundPage, isFalse);
    e.setBackgroundPage(b);
    expect(e.document!.pages[1].isBackgroundPage, isTrue);
    e.undo();
    expect(e.document!.pages[1].isBackgroundPage, isFalse);
  });

  test('findPrevious cycles matches without mutating text', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setShapeText(a, 'foo');
    e.setShapeText(b, 'foo');
    e.updateFind('foo');
    e.findNext();
    final first = e.selection.single;
    e.findPrevious();
    final second = e.selection.single;
    expect(second, isNot(first));
    expect(e.currentPage!.findShapeById(a)!.richText.plainText, 'foo');
    expect(e.currentPage!.findShapeById(b)!.richText.plainText, 'foo');
  });

  test('toggleCollapsed unfold undo keeps glue detached until fold undone', () {
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
    e.toggleCollapsed(box.id);
    e.toggleCollapsed(box.id); // unfold — glue restored
    expect(
      e.currentPage!.connects.any((c) => c.toSheetId == childId),
      isTrue,
    );
    e.undo(); // back to folded
    expect(e.isCollapsed(box.id), isTrue);
    expect(
      e.currentPage!.connects.any((c) => c.toSheetId == childId),
      isFalse,
    );
    e.undo(); // back to pre-fold
    expect(e.isCollapsed(box.id), isFalse);
    expect(
      e.currentPage!.connects.any((c) => c.toSheetId == childId),
      isTrue,
    );
  });

  test('closeDocument clears page guides', () {
    final e = ctrl();
    e.addPageGuide(vertical: false, pos: 2);
    expect(e.hasPageGuides, isTrue);
    e.closeDocument();
    e.newDocument();
    expect(e.pageGuides, isEmpty);
  });

  test('removeSelectedLane on locked pool is no-op', () {
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
    e.setSelection([poolId]);
    e.setSelectionLocked(true);
    e.setSelection([lane.id]);
    expect(e.canRemoveLane, isFalse);
    e.removeSelectedLane();
    expect(
      SwimlaneOps.lanesOf(e.currentPage!.findShapeById(poolId)!).length,
      2,
    );
  });
}
