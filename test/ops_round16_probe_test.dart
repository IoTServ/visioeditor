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

  test('softEdges memo does not seed Soft Edges onto new 1D', () {
    final e = ctrl();
    rect(e, 2, 4);
    e.setSoftEdges(true);
    e.setTool(EditorTool.line);
    e.createShapeByDrag(1, 1, 3, 1);
    final line = e.currentPage!.shapes.lastWhere((s) => s.is1D);
    expect(line.line.softEdgesInches, 0);
  });

  test('fillTheme on locked-only does not install theme', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelectionLocked(true);
    expect(e.document!.theme.isEmpty, isTrue);
    e.setFillThemeSlot(0);
    expect(e.document!.theme.isEmpty, isTrue);
    expect(e.currentPage!.findShapeById(a)!.locked, isTrue);
  });

  test('fillTheme on 1D-only does not install theme', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    expect(e.document!.theme.isEmpty, isTrue);
    e.setFillThemeSlot(0);
    expect(e.document!.theme.isEmpty, isTrue);
  });

  test('lineTheme on locked does not install theme', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelectionLocked(true);
    e.setLineThemeSlot(0);
    expect(e.document!.theme.isEmpty, isTrue);
    expect(a, isNotNull);
  });

  test('textTheme on locked range does not install theme', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setShapeText(a, 'hello');
    e.setTextEditSession(shapeId: a, start: 0, end: 5);
    e.setSelectionLocked(true);
    e.setTextThemeSlot(0);
    expect(e.document!.theme.isEmpty, isTrue);
  });

  test('connectDirectional from locked is no-op', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelectionLocked(true);
    final before = e.currentPage!.shapes.length;
    e.connectDirectional(a, 1, cloneX: 4, cloneY: 4);
    expect(e.currentPage!.shapes.length, before);
  });

  test('group with one locked leaves locked outside', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelectionLocked(true);
    final b = rect(e, 4, 4);
    final c = rect(e, 3, 2);
    e.setSelection([a, b, c]);
    expect(e.canGroup, isTrue); // B+C still groupable
    e.groupSelection();
    expect(e.currentPage!.findParentId(a), isNull);
    expect(e.currentPage!.findParentId(b), isNotNull);
  });

  test('ungroup locked group is no-op', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    e.setSelectionLocked(true);
    expect(e.canUngroup, isFalse);
    e.ungroupSelection();
    expect(e.currentPage!.shapes.length, 1);
  });

  test('createConnector does not inherit Soft Edges from 2D memo', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSoftEdges(true);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D);
    expect(conn.line.softEdgesInches, 0);
  });

  test('pasteStyle does not paste Soft Edges onto 1D', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSoftEdges(true);
    e.copyStyle();
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.pasteStyle();
    expect(e.currentPage!.findShapeById(conn)!.line.softEdgesInches, 0);
  });

  test('replaceFind name-only does not jump page', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setShapeText(a, 'zzz');
    e.updateCurrentPage(
      (p) => p.updateShapeById(a, (s) => s.copyWith(name: 'UniqueNameXYZ')),
    );
    e.addPage();
    final b = rect(e, 3, 3);
    e.setShapeText(b, 'keep');
    e.updateFind('UniqueNameXYZ');
    e.selectPage(1);
    e.setSelection([b]);
    e.replaceFind('Nope');
    expect(e.currentPageIndex, 1);
    expect(e.selection, equals({b}));
  });
}
