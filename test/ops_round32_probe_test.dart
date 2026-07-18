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

  test('duplicate collapsed host remaps internal stashed glue', () {
    final e = ctrl();
    final box = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    final a = rect(e, 3, 4);
    final b = rect(e, 5, 4);
    e.setSelection([a]);
    e.reparentSelectionInto(box.id);
    e.setSelection([b]);
    e.reparentSelectionInto(box.id);
    e.createConnector(3, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.reparentSelectionInto(box.id);

    e.toggleCollapsed(box.id);
    expect(e.isCollapsed(box.id), isTrue);
    e.setSelection([box.id]);
    e.duplicateSelection();
    final copyId = e.singleSelectedId!;
    expect(copyId, isNot(box.id));
    expect(e.isCollapsed(copyId), isTrue);

    // Original external-looking stash must not point at pre-copy ids after remap;
    // unfold the copy and ensure glue is between the copy's own sheets only.
    e.toggleCollapsed(copyId);
    final copySubtree = <int>{};
    void walk(VsdxShape s) {
      copySubtree.add(s.id);
      for (final c in s.children) {
        walk(c);
      }
    }

    walk(e.currentPage!.findShapeById(copyId)!);
    for (final c in e.currentPage!.connects) {
      if (copySubtree.contains(c.fromSheetId) ||
          copySubtree.contains(c.toSheetId)) {
        expect(copySubtree.contains(c.fromSheetId), isTrue);
        expect(copySubtree.contains(c.toSheetId), isTrue);
      }
    }
    // Original still collapsed with its own stash / no cross-wire to copy.
    expect(e.isCollapsed(box.id), isTrue);
  });

  test('copy child under flipped group bakes flipX', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.setSelection([g]);
    e.flipHorizontal();
    expect(e.currentPage!.findShapeById(g)!.flipX, isTrue);
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    expect(e.currentPage!.findShapeById(child)!.flipX, isFalse);
    e.setSelection([child]);
    e.copySelection();
    e.pasteAt();
    final pasted = e.currentPage!.findShapeById(e.singleSelectedId!)!;
    expect(pasted.flipX, isTrue);
  });

  test('resize nested group scales grandchild about updated LocPin', () {
    final e = ctrl();
    final a = rect(e, 2, 4, w: 1, h: 0.6);
    final b = rect(e, 3.2, 4, w: 1, h: 0.6);
    e.setSelection([a, b]);
    e.groupSelection();
    final mid = e.singleSelectedId!;
    final c = rect(e, 6, 4, w: 1, h: 0.6);
    e.setSelection([mid, c]);
    e.groupSelection();
    final outer = e.singleSelectedId!;
    final midShape = e.currentPage!.findShapeById(mid)!;
    final grand = midShape.children.first;
    final beforeLocal = grand.pinX;
    final group = e.currentPage!.findShapeById(outer)!;
    e.resizeShape(
      outer,
      pinX: group.pinX,
      pinY: group.pinY,
      width: group.width * 2,
      height: group.height,
    );
    final midAfter = e.currentPage!.findShapeById(mid)!;
    final grandAfter = midAfter.children.first;
    // About LocPin: local pin scales ~2× (not stuck near old centre math).
    expect(grandAfter.pinX, closeTo(beforeLocal * 2, 0.15));
  });

  test('pasteAt centres shape with corner LocPin', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 2,
        height: 1,
      ).copyWith(locPinXInches: 0, locPinYInches: 0),
      3,
      3,
    );
    final id = e.singleSelectedId!;
    e.setSelection([id]);
    e.copySelection();
    e.pasteAt(cx: 7, cy: 4);
    final pasted = e.singleSelectedId!;
    final aabb = e.currentPage!.shapePageAabb(pasted)!;
    final cx = (aabb.left + aabb.right) / 2;
    final cy = (aabb.bottom + aabb.top) / 2;
    expect(cx, closeTo(7, 0.05));
    expect(cy, closeTo(4, 0.05));
  });

  test('ungroup flipped group bakes flip onto children', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.flipHorizontal();
    e.ungroupSelection();
    expect(e.currentPage!.findShapeById(g), isNull);
    expect(e.currentPage!.findShapeById(a)!.flipX, isTrue);
    expect(e.currentPage!.findShapeById(b)!.flipX, isTrue);
  });
}
