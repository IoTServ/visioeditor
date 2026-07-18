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

  test('createShapeByDrag undo restores prior selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setTool(EditorTool.rectangle);
    e.createShapeByDrag(4, 4, 5.5, 4.75);
    final b = e.singleSelectedId!;
    expect(b, isNot(a));
    e.undo();
    expect(e.selection, contains(a));
    expect(e.currentPage!.findShapeById(b), isNull);
  });

  test('createConnector undo restores prior selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setSelection([a]);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.singleSelectedId!;
    expect(e.currentPage!.findShapeById(conn)!.is1D, isTrue);
    e.undo();
    expect(e.selection, equals({a}));
    expect(e.currentPage!.findShapeById(conn), isNull);
  });

  test('groupSelection undo restores prior multi-selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.undo();
    expect(e.selection, equals({a, b}));
    expect(e.currentPage!.findShapeById(g), isNull);
  });

  test('ungroupSelection undo restores group selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.ungroupSelection();
    expect(e.selection, equals({a, b}));
    e.undo();
    expect(e.selection, equals({g}));
    expect(e.currentPage!.findShapeById(g), isNotNull);
  });

  test('matchSelectionWidth uses first selected as reference', () {
    final e = ctrl();
    final a = rect(e, 2, 4, w: 2.0, h: 0.5);
    final b = rect(e, 5, 4, w: 1.0, h: 0.8);
    e.setSelection([a, b]);
    e.matchSelectionWidth();
    expect(e.currentPage!.findShapeById(b)!.width, closeTo(2.0, 1e-9));
    expect(e.currentPage!.findShapeById(a)!.width, closeTo(2.0, 1e-9));
  });

  test('theme slot skips shapes on locked layer', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.addLayer(name: 'Locked', assignSelection: true);
    final layerId = e.currentPage!.layers.last.id;
    e.toggleLayerLocked(layerId);
    expect(e.isOnLockedLayer(a), isTrue);
    final before = e.currentPage!.findShapeById(a)!.fill;
    e.setFillThemeSlot(1);
    final after = e.currentPage!.findShapeById(a)!.fill;
    expect(after, before);
  });

  test('addRowToSelectedTable undo restores prior cell selection', () {
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
    final table = e.currentPage!.findShapeById(tableId)!;
    final cell = TableOps.cellsOf(table).first;
    e.setSelection([cell.id]);
    e.addRowToSelectedTable();
    expect(e.selection, equals({tableId}));
    e.undo();
    expect(e.selection, equals({cell.id}));
    expect(TableOps.dimensions(e.currentPage!.findShapeById(tableId)!).rows, 2);
  });

  test('paste undo restores prior selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a]);
    e.copySelection();
    e.setSelection([b]);
    e.paste();
    expect(e.selection.length, 1);
    expect(e.selection.contains(b), isFalse);
    e.undo();
    expect(e.selection, equals({b}));
    expect(e.currentPage!.shapes.length, 2);
  });

  test('createFreehand undo restores prior selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.createFreehand([
      const Offset2D(1, 1),
      const Offset2D(1.5, 1.2),
      const Offset2D(2, 1.5),
    ]);
    final stroke = e.singleSelectedId!;
    e.undo();
    expect(e.selection, equals({a}));
    expect(e.currentPage!.findShapeById(stroke), isNull);
  });

  test('connectDirectional undo restores prior selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelection([a]);
    e.connectDirectional(a, 1, cloneX: 5, cloneY: 4);
    expect(e.selection.length, 1);
    expect(e.selection.contains(a), isFalse);
    e.undo();
    expect(e.selection, equals({a}));
    expect(e.currentPage!.shapes.length, 1);
  });
}
