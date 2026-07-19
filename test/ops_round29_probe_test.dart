import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('createShapeByDrag hairline drag uses default size', () {
    final e = ctrl();
    e.setTool(EditorTool.rectangle);
    e.createShapeByDrag(3, 4, 3.02, 4.5);
    final s = e.currentPage!.findShapeById(e.singleSelectedId!)!;
    expect(s.width, closeTo(1.5, 1e-6));
    expect(s.height, closeTo(0.75, 1e-6));
  });

  test('setSelectedWidth on rotated shape keeps page AABB left', () {
    final e = ctrl();
    final id = rect(e, 4, 4, w: 2, h: 1);
    e.rotateShape(id, math.pi / 4);
    final before = e.currentPage!.shapePageAabb(id)!;
    e.setSelectedWidth(3);
    final after = e.currentPage!.shapePageAabb(id)!;
    expect(after.left, closeTo(before.left, 1e-3));
    expect(e.currentPage!.findShapeById(id)!.width, closeTo(3, 1e-6));
  });

  test('matchSelectionSize under rotated group keeps child AABB', () {
    final e = ctrl();
    final a = rect(e, 2, 4, w: 2, h: 1);
    final b = rect(e, 5, 4, w: 1, h: 0.5);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.rotateShape(g, math.pi / 6);
    final kids = e.currentPage!.findShapeById(g)!.children;
    final ref = kids.first.id;
    final target = kids.last.id;
    final beforeTarget = e.currentPage!.shapePageAabb(target)!;
    e.setSelection([ref, target]);
    e.matchSelectionSize();
    final after = e.currentPage!.shapePageAabb(target)!;
    expect(after.left, closeTo(beforeTarget.left, 1e-2));
    expect(after.top, closeTo(beforeTarget.top, 1e-2));
    expect(e.currentPage!.findShapeById(target)!.width, closeTo(2, 1e-6));
  });

  test('matchSelectionSize group+child co-selection scales via group only', () {
    final e = ctrl();
    final a = rect(e, 2, 4, w: 2, h: 1);
    final b = rect(e, 5, 4, w: 1, h: 0.5);
    final c = rect(e, 8, 4, w: 1.5, h: 0.8);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    final groupW0 = e.currentPage!.findShapeById(g)!.width;
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    final childW = e.currentPage!.findShapeById(child)!.width;
    // Co-selecting group+child must not double-apply Same Size to the child;
    // the child scales with the group frame (same as resize handles).
    e.setSelection([c, g, child]);
    e.matchSelectionSize();
    expect(e.currentPage!.findShapeById(g)!.width, closeTo(1.5, 1e-6));
    expect(
      e.currentPage!.findShapeById(child)!.width,
      closeTo(childW * (1.5 / groupW0), 1e-3),
    );
  });

  test('reconnectEndpoint to nested child glues Connects', () {
    final e = ctrl();
    final box = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    final nested = rect(e, 4, 4);
    e.setSelection([nested]);
    e.reparentSelectionInto(box.id);
    final outer = rect(e, 8, 4);
    e.createConnector(8, 4, 9, 4, beginTarget: outer);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    final pin = e.currentPage!.shapePinPage(nested);
    e.reconnectEndpoint(
      conn,
      begin: false,
      targetShapeId: nested,
      x: pin.x,
      y: pin.y,
    );
    final glued = e.currentPage!.connects
        .where((c) => c.fromSheetId == conn && c.fromCell.startsWith('End'))
        .map((c) => c.toSheetId)
        .toSet();
    expect(glued, contains(nested));
  });

  test('reconnectEndpoint detach nested connector uses page→local', () {
    final e = ctrl();
    final box = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 5,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    final a = rect(e, 3.5, 4);
    final b = rect(e, 6.5, 4);
    e.createConnector(3.5, 4, 6.5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.reparentSelectionInto(box.id);
    expect(e.currentPage!.findParentId(conn), box.id);
    // Detach end to a page point to the right of the container.
    e.reconnectEndpoint(conn, begin: false, targetShapeId: null, x: 9, y: 4);
    final s = e.currentPage!.findShapeById(conn)!;
    final route = VsdxPage.connectorRoute(s);
    final parentLocal = route.last;
    final pageEnd =
        e.currentPage!.localToPageDeep(box.id, parentLocal);
    expect(pageEnd.x, closeTo(9, 0.15));
    expect(pageEnd.y, closeTo(4, 0.15));
  });

  test('paste nested child alone keeps page position (+ offset)', () {
    final e = ctrl();
    final box = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 5,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    final child = rect(e, 5, 4);
    e.setSelection([child]);
    e.reparentSelectionInto(box.id);
    final before = e.currentPage!.shapePinPage(child);
    final localPin = e.currentPage!.findShapeById(child)!.pinX;
    e.setSelection([child]);
    e.copySelection();
    e.pasteAt();
    final pasted = e.singleSelectedId!;
    final after = e.currentPage!.shapePinPage(pasted);
    // Must follow page pin, not the parent-local pin left on the clipboard.
    expect(after.x, isNot(closeTo(localPin + 0.25, 0.05)));
    expect(after.x, closeTo(before.x + 0.25, 0.05));
    expect(after.y, closeTo(before.y - 0.25, 0.05));
  });

  test('createConnector seeds use shapePinPage for nested targets', () {
    final e = ctrl();
    final box = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    final nested = rect(e, 4, 4);
    e.setSelection([nested]);
    e.reparentSelectionInto(box.id);
    final outer = rect(e, 8, 4);
    final pin = e.currentPage!.shapePinPage(nested);
    e.createConnector(8, 4, pin.x, pin.y,
        beginTarget: outer, endTarget: nested);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    final endGlue = e.currentPage!.connects
        .where((c) => c.fromSheetId == conn && c.fromCell.startsWith('End'))
        .single;
    expect(endGlue.toSheetId, nested);
  });

  test('nested pageToLocalDeep differs from shallow pageToLocal', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.rotateShape(g, math.pi / 2);
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    final page = e.currentPage!;
    final pagePt = page.shapePinPage(child);
    final shallow =
        VsdxPage.pageToLocal(page.findShapeById(child)!, pagePt);
    final deep = page.pageToLocalDeep(child, pagePt);
    expect(shallow.x, isNot(closeTo(deep.x, 1e-3)));
    expect(deep.x, closeTo(page.findShapeById(child)!.width / 2, 0.1));
    expect(deep.y, closeTo(page.findShapeById(child)!.height / 2, 0.1));
  });
}
