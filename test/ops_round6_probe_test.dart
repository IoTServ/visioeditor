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

  (double, double, double, double) bounds(VsdxShape s) => (
        s.pinX - s.width / 2,
        s.pinY - s.height / 2,
        s.pinX + s.width / 2,
        s.pinY + s.height / 2,
      );

  test('flipHorizontal reroutes glued connector', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4,
        beginTarget: a, endTarget: b, beginConnectionPointIndex: 1);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D);
    final before = conn.beginX!;
    e.setSelection([a]);
    e.flipHorizontal();
    final after = e.currentPage!.findShapeById(conn.id)!.beginX!;
    expect((after - before).abs(), greaterThan(0.05));
  });

  test('connectDirectional writes XFTRIGGER formulas', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.connectDirectional(a, 1, cloneX: 5, cloneY: 4);
    final conn = e.currentPage!.shapes.firstWhere((s) => s.is1D);
    expect(conn.formulas['BegTrigger'], contains('Sheet.$a'));
    expect(conn.formulas['EndTrigger'], isNotNull);
  });

  test('removeRow uses multi-selected cell row', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(
      (id, cx, cy) => TableOps.assembleTable(
        tableId: id,
        pinX: cx,
        pinY: cy,
        width: 3,
        height: 2,
        rows: 3,
        cols: 2,
      ),
      4,
      4,
    );
    final tableId = e.singleSelectedId!;
    final cells = TableOps.cellsOf(e.currentPage!.findShapeById(tableId)!);
    final row0 = cells
        .where((c) => TableOps.cellRow(c) == 0)
        .map((c) => c.id)
        .toList();
    e.setSelection(row0);
    e.removeRowFromSelectedTable();
    final dims = TableOps.dimensions(e.currentPage!.findShapeById(tableId)!);
    expect(dims.rows, 2);
    for (final id in row0) {
      expect(e.currentPage!.findShapeById(id), isNull);
    }
  });

  test('setShapeProperties no-op when locked', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelectionLocked(true);
    e.setShapeProperties(a, [
      const VsdxUserProperty(name: 'x', value: '1'),
    ]);
    expect(e.currentPage!.findShapeById(a)!.userProperties, isEmpty);
  });

  test('discardAbandonedShape collapses create history', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setTool(EditorTool.text);
    e.createShapeByDrag(1, 1, 2.5, 1.5);
    final box = e.singleSelectedId!;
    expect(e.isBlankTextBox(box), isTrue);
    e.discardAbandonedShape(box);
    expect(e.currentPage!.findShapeById(box), isNull);
    expect(e.selection, equals({a}));
    // One undo should restore [a]'s create, not the abandoned text box.
    e.undo();
    expect(e.currentPage!.findShapeById(box), isNull);
    expect(e.currentPage!.findShapeById(a), isNull);
  });

  test('undo exits connection-point edit mode', () {
    final e = ctrl();
    rect(e, 3, 4);
    e.beginEditConnectionPoints();
    expect(e.editingConnectionPoints, isTrue);
    e.undo(); // undo materialize
    expect(e.editingConnectionPoints, isFalse);
  });

  test('replaceFind undo restores prior page selection', () {
    final e = ctrl();
    e.setShapeText(rect(e, 2, 4), 'alpha');
    e.addPage();
    final b = rect(e, 3, 3);
    e.setShapeText(b, 'keep');
    e.updateFind('alpha');
    expect(e.findCurrentPageIndex, 0);
    e.selectPage(1);
    e.setSelection([b]);
    e.replaceFind('beta');
    e.undo();
    expect(e.currentPageIndex, 1);
    expect(e.selection, equals({b}));
    expect(
      e.document!.pages[0].shapes.first.richText.plainText,
      'alpha',
    );
  });

  test('distribute unequal widths equalises gaps', () {
    final e = ctrl();
    final a = rect(e, 1, 4, w: 1);
    final b = rect(e, 3, 4, w: 2);
    final d = rect(e, 8, 4, w: 1);
    e.setSelection([a, b, d]);
    e.distributeHorizontally();
    final ba = bounds(e.currentPage!.findShapeById(a)!);
    final bb = bounds(e.currentPage!.findShapeById(b)!);
    final bd = bounds(e.currentPage!.findShapeById(d)!);
    expect(bb.$1 - ba.$3, closeTo(bd.$1 - bb.$3, 1e-6));
  });
}
