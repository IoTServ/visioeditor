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

  int pool(EditorController e) {
    e.addShapeFromBuilderAt(
      (id, cx, cy) => SwimlaneOps.assemblePool(
        poolId: id,
        pinX: cx,
        pinY: cy,
        width: 4,
        height: 3,
        laneCount: 2,
      ),
      5,
      4,
    );
    return e.singleSelectedId!;
  }

  test('addLane then undo restores lane count and selection', () {
    final e = ctrl();
    final poolId = pool(e);
    expect(SwimlaneOps.lanesOf(e.currentPage!.findShapeById(poolId)!),
        hasLength(2));
    e.addLaneToSelectedPool();
    expect(SwimlaneOps.lanesOf(e.currentPage!.findShapeById(poolId)!),
        hasLength(3));
    e.undo();
    expect(SwimlaneOps.lanesOf(e.currentPage!.findShapeById(poolId)!),
        hasLength(2));
    expect(e.selection, equals({poolId}));
  });

  test('removeSelectedLane keeps at least one lane', () {
    final e = ctrl();
    final poolId = pool(e);
    final lanes = SwimlaneOps.lanesOf(e.currentPage!.findShapeById(poolId)!);
    e.setSelection([lanes.first.id]);
    e.removeSelectedLane();
    expect(SwimlaneOps.lanesOf(e.currentPage!.findShapeById(poolId)!),
        hasLength(1));
    e.setSelection([
      SwimlaneOps.lanesOf(e.currentPage!.findShapeById(poolId)!).first.id,
    ]);
    expect(e.canRemoveLane, isFalse);
    e.removeSelectedLane(); // no-op
    expect(SwimlaneOps.lanesOf(e.currentPage!.findShapeById(poolId)!),
        hasLength(1));
  });

  test('pasteStyle onto connector keeps fill pattern 0', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setFillColor(const VsdxColor(0xFFFF0000));
    e.setLineColor(const VsdxColor(0xFF00FF00));
    e.copyStyle();
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.singleSelectedId!;
    e.pasteStyle();
    final c = e.currentPage!.findShapeById(conn)!;
    expect(c.line.color, const VsdxColor(0xFF00FF00));
    // 1-D shapes should not gain a solid fill from a vertex style.
    expect(c.fill.pattern, 0);
  });

  test('pasteStyle from connector strips arrows on rectangle', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    e.copyStyle();
    e.setSelection([a]);
    e.pasteStyle();
    final line = e.currentPage!.findShapeById(a)!.line;
    expect(line.beginArrow, 0);
    expect(line.endArrow, 0);
  });

  test('drop into swimlane hits the lane not only the pool', () {
    final e = ctrl();
    final poolId = pool(e);
    final p = e.currentPage!.findShapeById(poolId)!;
    final lane = SwimlaneOps.lanesOf(p).first;
    final laneAabb = e.currentPage!.shapePageAabb(lane.id)!;
    final cx = (laneAabb.left + laneAabb.right) / 2;
    final cy = (laneAabb.bottom + laneAabb.top) / 2;
    // Palette drop at the lane centre auto-contains (addShapeFromBuilderAt).
    final child = rect(e, cx, cy);
    expect(e.currentPage!.findParentId(child), lane.id);
    // Explicit drop from outside still prefers the lane over the pool.
    final outsider = rect(e, 1, 1);
    e.setSelection([outsider]);
    final drop = e.applyDropContainmentAt(cx, cy, transient: false);
    expect(drop, lane.id);
    expect(e.currentPage!.findParentId(outsider), lane.id);
  });

  test('createShapeByDrag reparents into swimlane under pin', () {
    final e = ctrl();
    final poolId = pool(e);
    final lane =
        SwimlaneOps.lanesOf(e.currentPage!.findShapeById(poolId)!).first;
    final laneAabb = e.currentPage!.shapePageAabb(lane.id)!;
    final cx = (laneAabb.left + laneAabb.right) / 2;
    final cy = (laneAabb.bottom + laneAabb.top) / 2;
    e
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(cx - 0.4, cy - 0.3, cx + 0.4, cy + 0.3);
    final id = e.singleSelectedId!;
    expect(e.currentPage!.findParentId(id), lane.id);
  });

  test('resize pool reflows lane heights', () {
    final e = ctrl();
    final poolId = pool(e);
    final before = SwimlaneOps.lanesOf(e.currentPage!.findShapeById(poolId)!);
    expect(before.first.height, closeTo(1.5, 1e-6));
    e.resizeShape(poolId, pinX: 5, pinY: 4, width: 4, height: 5);
    final after = SwimlaneOps.lanesOf(e.currentPage!.findShapeById(poolId)!);
    expect(after.first.height, closeTo(2.5, 1e-6));
    expect(after.last.height, closeTo(2.5, 1e-6));
  });

  test('selectConnectors includes edges nested in a group', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.singleSelectedId!;
    e.selectAll();
    e.groupSelection();
    e.selectConnectors();
    expect(e.selection, equals({conn}));
  });

  test('applyEdit during transaction commits gesture first', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.beginTransaction();
    e.moveSelectionBy(1, 0, transient: true);
    e.setFillColor(const VsdxColor(0xFFFF0000)); // discrete applyEdit
    expect(e.currentPage!.findShapeById(a)!.pinX, closeTo(3, 1e-6));
    e.undo(); // undo fill
    expect(e.currentPage!.findShapeById(a)!.fill.foreground,
        isNot(const VsdxColor(0xFFFF0000)));
    expect(e.currentPage!.findShapeById(a)!.pinX, closeTo(3, 1e-6));
    e.undo(); // undo move
    expect(e.currentPage!.findShapeById(a)!.pinX, closeTo(2, 1e-6));
  });

  test('matchSelectionSize with rotated reference keeps size', () {
    final e = ctrl();
    final a = rect(e, 2, 4, w: 2, h: 1);
    final b = rect(e, 5, 4, w: 1, h: 0.5);
    e.setSelection([a]);
    e.rotateSelection90();
    e.setSelection([a, b]);
    e.matchSelectionSize();
    final bs = e.currentPage!.findShapeById(b)!;
    expect(bs.width, closeTo(2, 1e-6));
    expect(bs.height, closeTo(1, 1e-6));
  });

  test('beginTransaction cancel restores selection and document', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.beginTransaction();
    e.moveSelectionBy(1, 0, transient: true);
    expect(e.currentPage!.findShapeById(a)!.pinX, closeTo(3, 1e-6));
    e.cancelTransaction();
    expect(e.currentPage!.findShapeById(a)!.pinX, closeTo(2, 1e-6));
    expect(e.selection, equals({a}));
    expect(e.canUndo, isTrue); // create still undoable; cancel added nothing
  });

  test('reconnectEndpoint no-op when connector locked', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.singleSelectedId!;
    final before = e.currentPage!.findShapeById(conn)!.endX;
    e.setSelectionLocked(true);
    e.reconnectEndpoint(conn, begin: false, x: 8, y: 1);
    expect(e.currentPage!.findShapeById(conn)!.endX, before);
  });

  test('duplicateSelection then undo restores prior selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.duplicateSelection();
    final dup = e.singleSelectedId!;
    expect(dup, isNot(a));
    e.undo();
    expect(e.selection, equals({a}));
    expect(e.currentPage!.findShapeById(dup), isNull);
  });

  test('bringSelectionForward on top-level only affects page order', () {
    final e = ctrl();
    final a = rect(e, 1, 4);
    final b = rect(e, 3, 4);
    final d = rect(e, 5, 4);
    e.setSelection([a]);
    e.bringSelectionForward();
    final order = e.currentPage!.shapes.map((s) => s.id).toList();
    // a should move past b
    expect(order, [b, a, d]);
  });
}
