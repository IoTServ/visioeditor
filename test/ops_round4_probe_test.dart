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

  test('matchSize with single selection is no-op', () {
    final e = ctrl();
    final a = rect(e, 2, 4, w: 1.5);
    e.matchSelectionSize();
    expect(e.currentPage!.findShapeById(a)!.width, 1.5);
  });

  test('ungroup then delete child then undo twice restores group', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.ungroupSelection();
    e.setSelection([a]);
    e.deleteSelection();
    expect(e.currentPage!.findShapeById(a), isNull);
    e.undo(); // restore a
    expect(e.currentPage!.findShapeById(a), isNotNull);
    e.undo(); // restore group
    expect(e.currentPage!.findShapeById(g), isNotNull);
  });

  test('selectAll then group includes connector as child', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    e.selectAll();
    expect(e.selection.length, 3);
    e.groupSelection();
    expect(e.currentPage!.shapes, hasLength(1));
    final g = e.currentPage!.shapes.single;
    expect(g.children, hasLength(3));
    // Ungroup should restore glue on the page.
    e.ungroupSelection();
    expect(e.currentPage!.shapes, hasLength(3));
    final conn = e.currentPage!.shapes.firstWhere((s) => s.is1D);
    expect(
      e.currentPage!.connects.where((c) => c.fromSheetId == conn.id).length,
      2,
    );
  });

  test('setShapeText empty on blank text box stays blank', () {
    final e = ctrl();
    e.setTool(EditorTool.text);
    e.createShapeByDrag(1, 1, 2, 2);
    final id = e.singleSelectedId!;
    expect(e.isBlankTextBox(id), isTrue);
    e.setShapeText(id, '');
    expect(e.isBlankTextBox(id), isTrue);
  });

  test('paste glued pair: moving target reroutes pasted connector', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([a, b, conn]);
    e.copySelection();
    e.paste();
    final page = e.currentPage!;
    final newConn = page.shapes.lastWhere((s) => s.is1D && s.id != conn);
    expect(
      page.connects.where((c) => c.fromSheetId == newConn.id).length,
      2,
    );
    final targets = page.connects
        .where((c) => c.fromSheetId == newConn.id)
        .map((c) => c.toSheetId)
        .toSet();
    final t = targets.first;
    final beforeBegin = page.findShapeById(newConn.id)!.beginX!;
    final beforeEnd = page.findShapeById(newConn.id)!.endX!;
    e.setSelection([t]);
    e.moveSelectionBy(1, 0);
    final after = e.currentPage!.findShapeById(newConn.id)!;
    // At least one endpoint should have moved with the target.
    expect(
      (after.beginX! - beforeBegin).abs() > 0.1 ||
          (after.endX! - beforeEnd).abs() > 0.1,
      isTrue,
      reason: 'pasted connector did not follow moved target',
    );
  });

  test('addPage undo restores prior selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    expect(e.selection, contains(a));
    e.addPage();
    expect(e.selection, isEmpty);
    e.undo();
    expect(e.currentPageIndex, 0);
    expect(e.selection, contains(a));
  });

  test('distribute 3 shapes evenly', () {
    final e = ctrl();
    final a = rect(e, 1, 4);
    final b = rect(e, 2, 4);
    final d = rect(e, 7, 4);
    e.setSelection([a, b, d]);
    e.distributeHorizontally();
    final xs = [a, b, d]
        .map((id) => e.currentPage!.findShapeById(id)!.pinX)
        .toList()
      ..sort();
    expect(xs[1] - xs[0], closeTo(xs[2] - xs[1], 1e-6));
  });

  test('flip then undo restores connector endpoints near pins', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([a]);
    e.flipHorizontal();
    e.undo();
    final cshape = e.currentPage!.findShapeById(conn)!;
    final pinA = e.currentPage!.shapePinPage(a);
    expect((cshape.beginX! - pinA.x).abs(), lessThanOrEqualTo(0.55));
  });

  test('edit connection points add/remove/undo', () {
    final e = ctrl();
    rect(e, 3, 4);
    e.beginEditConnectionPoints();
    expect(e.editingConnectionPoints, isTrue);
    final before =
        e.currentPage!.findShapeById(e.singleSelectedId!)!.connectionPoints.length;
    e.addConnectionPointAtLocal(0.25, 0.5);
    expect(
      e.currentPage!.findShapeById(e.singleSelectedId!)!.connectionPoints.length,
      before + 1,
    );
    e.endEditConnectionPoints();
    expect(e.editingConnectionPoints, isFalse);
    e.undo();
    expect(
      e.currentPage!.findShapeById(e.selection.single)!.connectionPoints.length,
      before,
    );
  });

  test('group containing connector then ungroup keeps page connects', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    final connectsBefore = e.currentPage!.connects.length;
    e.setSelection([a, b, conn]);
    e.groupSelection();
    // While grouped, page-level connects to members may be rewritten.
    e.ungroupSelection();
    expect(e.currentPage!.connects.length, connectsBefore);
    final pinA = e.currentPage!.shapePinPage(a);
    final pinB = e.currentPage!.shapePinPage(b);
    final cshape = e.currentPage!.findShapeById(conn)!;
    expect((cshape.beginX! - pinA.x).abs(), lessThanOrEqualTo(0.55));
    expect((cshape.endX! - pinB.x).abs(), lessThanOrEqualTo(0.55));
  });

  test('createFreehand then delete then undo restores stroke', () {
    final e = ctrl();
    e.createFreehand([
      const Offset2D(1, 1),
      const Offset2D(2, 2),
      const Offset2D(3, 1.5),
    ]);
    final id = e.singleSelectedId!;
    expect(e.currentPage!.findShapeById(id)!.is1D, isTrue);
    e.deleteSelection();
    expect(e.currentPage!.shapes, isEmpty);
    e.undo();
    expect(e.currentPage!.findShapeById(id), isNotNull);
    expect(e.selection, contains(id));
  });
}
