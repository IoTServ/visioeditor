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

  test('addLayer assignSelection skips locked shapes', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setSelection([a]);
    e.setSelectionLocked(true);
    e.setSelection([a, b]);
    e.addLayer(name: 'L', assignSelection: true);
    final layerId = e.currentPage!.layers.last.id;
    expect(
      e.currentPage!.findShapeById(a)!.layerMemberIds,
      isNot(contains(layerId)),
    );
    expect(
      e.currentPage!.findShapeById(b)!.layerMemberIds,
      contains(layerId),
    );
  });

  test('assignSelectionToLayer skips locked', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.addLayer(name: 'L');
    final layerId = e.currentPage!.layers.last.id;
    e.setSelection([a]);
    e.setSelectionLocked(true);
    e.setSelection([a, b]);
    e.assignSelectionToLayer(layerId);
    expect(
      e.currentPage!.findShapeById(a)!.layerMemberIds,
      isNot(contains(layerId)),
    );
    expect(
      e.currentPage!.findShapeById(b)!.layerMemberIds,
      contains(layerId),
    );
  });

  test('setConnectorStyle on 2D selection is no-op', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelection([a]);
    e.setConnectorStyle(straight: true);
    // Must not push a phantom undo beyond shape create.
    e.undo();
    expect(e.currentPage!.findShapeById(a), isNull);
  });

  test('setConnectorRounded on mixed only affects 1D', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([a, conn]);
    e.setConnectorRounded(true);
    expect(e.currentPage!.findShapeById(conn)!.rounded, isTrue);
  });

  test('matchSelectionSize skips locked members', () {
    final e = ctrl();
    final a = rect(e, 2, 4, w: 2, h: 1);
    final b = rect(e, 5, 4, w: 1, h: 0.5);
    e.setSelection([b]);
    e.setSelectionLocked(true);
    e.setSelection([a, b]);
    e.matchSelectionSize();
    final bs = e.currentPage!.findShapeById(b)!;
    expect(bs.width, closeTo(1, 1e-9));
    expect(bs.height, closeTo(0.5, 1e-9));
  });

  test('deleteSelection keeps locked shapes', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setSelection([a]);
    e.setSelectionLocked(true);
    e.setSelection([a, b]);
    e.deleteSelection();
    expect(e.currentPage!.findShapeById(a), isNotNull);
    expect(e.currentPage!.findShapeById(b), isNull);
  });

  test('alignLeft skips locked', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setSelection([a]);
    e.setSelectionLocked(true);
    e.setSelection([a, b]);
    final ax = e.currentPage!.findShapeById(a)!.pinX;
    e.alignLeft();
    expect(e.currentPage!.findShapeById(a)!.pinX, ax);
  });

  test('page guide add/remove is session-level (not document undo)', () {
    final e = ctrl();
    e.addPageGuide(vertical: true, pos: 3);
    expect(e.pageGuides, isNotEmpty);
    e.undo(); // only undoes newDocument baseline noise if any — guides stay
    expect(e.pageGuides, isNotEmpty);
    e.removePageGuide(0);
    expect(e.pageGuides, isEmpty);
  });

  test('setCurvedText skips 1D', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.setCurvedText(true);
    expect(e.currentPage!.findShapeById(conn)!.curvedText, isFalse);
  });

  test('copy then paste across page keeps unique ids', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelection([a]);
    e.copySelection();
    e.addPage();
    expect(e.currentPageIndex, 1);
    e.paste();
    final ids = e.currentPage!.shapes.map((s) => s.id).toSet();
    expect(e.currentPage!.shapes, hasLength(1));
    expect(ids.length, 1);
    // Original stays on page 0.
    expect(e.document!.pages[0].findShapeById(a), isNotNull);
  });

  test('ungroup undo restores group selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final gid = e.singleSelectedId!;
    e.ungroupSelection();
    expect(e.currentPage!.findShapeById(gid), isNull);
    e.undo();
    expect(e.selection, contains(gid));
    expect(e.currentPage!.findShapeById(gid)?.children.length, 2);
  });
}
