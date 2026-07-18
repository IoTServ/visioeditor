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
      {double w = 1, double h = 0.6, String? text}) {
    e.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: w, height: h),
        x,
        y);
    final id = e.singleSelectedId!;
    if (text != null) e.setShapeText(id, text);
    return id;
  }

  test('setLineArrows on 2D should not stamp arrowheads', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelection([a]);
    e.setEndArrow(1);
    final line = e.currentPage!.findShapeById(a)!.line;
    // Expected: 2-D boxes never keep connector arrowheads (pasteStyle rule).
    expect(line.endArrow, 0);
  });

  test('setLineArrows mixed 1D+2D only affects connectors', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([a, conn]);
    e.setEndArrow(1);
    expect(e.currentPage!.findShapeById(a)!.line.endArrow, 0);
    expect(e.currentPage!.findShapeById(conn)!.line.endArrow, 1);
  });

  test('groupSelection skips locked members', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    final c = rect(e, 3, 2);
    e.setSelection([a]);
    e.setSelectionLocked(true);
    e.setSelection([a, b, c]);
    e.groupSelection();
    // Locked A must not enter the group; B+C group or no-op if <2 movable.
    expect(e.currentPage!.findParentId(a), isNull);
    final parentB = e.currentPage!.findParentId(b);
    final parentC = e.currentPage!.findParentId(c);
    expect(parentB, isNotNull);
    expect(parentB, parentC);
  });

  test('groupSelection all-locked is no-op', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setSelection([a, b]);
    e.setSelectionLocked(true);
    e.groupSelection();
    expect(e.currentPage!.findParentId(a), isNull);
    expect(e.currentPage!.findParentId(b), isNull);
    // Only the lock edit should be undoable on top — group must not push.
    e.undo(); // unlock
    expect(e.currentPage!.shapes.length, 2);
  });

  test('ungroupSelection skips locked groups', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final gid = e.singleSelectedId!;
    e.setSelectionLocked(true);
    e.ungroupSelection();
    expect(e.currentPage!.findShapeById(gid)?.children, isNotEmpty);
  });

  test('duplicateSelection skips locked shapes', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setSelection([a]);
    e.setSelectionLocked(true);
    e.setSelection([a, b]);
    final before = e.currentPage!.shapes.length;
    e.duplicateSelection();
    // Only unlocked B should clone → +1 shape.
    expect(e.currentPage!.shapes.length, before + 1);
  });

  test('flip locked-only creates no undo beyond lock', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelectionLocked(true);
    e.flipHorizontal();
    e.undo(); // unlock
    expect(e.currentPage!.findShapeById(a)!.flipX, isFalse);
  });

  test('rotateSelection90 locked-only is no-op', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelectionLocked(true);
    final angle = e.currentPage!.findShapeById(a)!.angleRad;
    e.rotateSelection90();
    expect(e.currentPage!.findShapeById(a)!.angleRad, angle);
  });

  test('setLineArrowSizes on 2D is ignored', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final before = e.currentPage!.findShapeById(a)!.line.endArrowSizeInches;
    e.setEndArrowSize(0.3);
    expect(e.currentPage!.findShapeById(a)!.line.endArrowSizeInches, before);
  });

  test('addConnectionPointAtLocal skips locked', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelectionLocked(true);
    final before = e.currentPage!.findShapeById(a)!.connectionPoints.length;
    e.addConnectionPointAtLocal(0.5, 0.5);
    expect(
      e.currentPage!.findShapeById(a)!.connectionPoints.length,
      before,
    );
  });

  test('deleteLayer removes membership from nested children', () {
    final e = ctrl();
    final page0 = e.currentPage!;
    final box = VsdxShapeFactory.container(
      id: page0.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    final childId = e.currentPage!.nextFreeShapeId();
    final child = VsdxShapeFactory.rectangle(
      id: childId,
      pinX: 4,
      pinY: 3.5,
      width: 1,
      height: 0.8,
    );
    e.updateCurrentPage((p) => p.addShape(child).reparentShape(childId, box.id));
    e.setSelection([childId]);
    e.addLayer(name: 'L', assignSelection: true);
    final layerId = e.currentPage!.layers.last.id;
    expect(
      e.currentPage!.findShapeById(childId)!.layerMemberIds,
      contains(layerId),
    );
    e.deleteLayer(layerId);
    expect(
      e.currentPage!.findShapeById(childId)!.layerMemberIds,
      isNot(contains(layerId)),
    );
  });

  test('pasteStyle does not put arrows on 2D from 1D source', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.setEndArrow(1);
    e.copyStyle();
    e.setSelection([a]);
    e.pasteStyle();
    expect(e.currentPage!.findShapeById(a)!.line.endArrow, 0);
  });

  test('setNoLine on 1D-only is allowed (connectors can be hidden)', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.setNoLine();
    expect(e.currentPage!.findShapeById(conn)!.line.pattern, 0);
  });

  test('bringSelectionForward locked-only is no-op', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setSelection([a]);
    e.setSelectionLocked(true);
    final orderBefore =
        e.currentPage!.shapes.map((s) => s.id).toList(growable: false);
    e.setSelection([a]);
    e.bringSelectionForward();
    expect(
      e.currentPage!.shapes.map((s) => s.id).toList(growable: false),
      orderBefore,
    );
    // silence unused
    expect(b, isNotNull);
  });
}
