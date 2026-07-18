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
      5.5,
      4.25,
    );
    return e.singleSelectedId!;
  }

  test('drop into lane preserves shapePinPage', () {
    final e = ctrl();
    final poolId = pool(e);
    final lane =
        SwimlaneOps.lanesOf(e.currentPage!.findShapeById(poolId)!).first;
    final laneAabb = e.currentPage!.shapePageAabb(lane.id)!;
    final cx = (laneAabb.left + laneAabb.right) / 2;
    final cy = (laneAabb.bottom + laneAabb.top) / 2;
    final id = rect(e, cx, cy);
    final before = e.currentPage!.shapePinPage(id);
    e.setSelection([id]);
    e.applyDropContainmentAt(cx, cy, transient: false);
    expect(e.currentPage!.findParentId(id), lane.id);
    final after = e.currentPage!.shapePinPage(id);
    expect(after.x, closeTo(before.x, 1e-6));
    expect(after.y, closeTo(before.y, 1e-6));
  });

  test('cut group+child clears descendant selection ids', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 3, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    e.setSelection([g, child]);
    e.cut();
    expect(e.selection.contains(child), isFalse);
    expect(e.selection.contains(g), isFalse);
    expect(
      e.selection.every((id) => e.currentPage!.findShapeById(id) != null),
      isTrue,
    );
  });

  test('delete unlocked parent with locked child clears ghost child id', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 3, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    e.setSelection([child]);
    e.setSelectionLocked(true);
    e.setSelection([g, child]);
    e.deleteSelection();
    expect(e.currentPage!.findShapeById(g), isNull);
    expect(e.currentPage!.findShapeById(child), isNull);
    expect(e.selection.contains(child), isFalse);
    expect(e.selection, isEmpty);
  });

  test('ungroupSelection on nested group promotes children', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 3, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final inner = e.singleSelectedId!;
    final c = rect(e, 5, 4);
    e.setSelection([inner, c]);
    e.groupSelection();
    final outer = e.singleSelectedId!;
    e.setSelection([inner]);
    e.ungroupSelection();
    expect(e.currentPage!.findShapeById(inner), isNull);
    expect(e.currentPage!.findParentId(a), outer);
    expect(e.currentPage!.findParentId(b), outer);
  });

  test('resize group scales children', () {
    final e = ctrl();
    final a = rect(e, 2, 4, w: 1, h: 0.6);
    final b = rect(e, 4, 4, w: 1, h: 0.6);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    final group = e.currentPage!.findShapeById(g)!;
    final child = group.children.first;
    final beforeW = child.width;
    e.resizeShape(
      g,
      pinX: group.pinX,
      pinY: group.pinY,
      width: group.width * 2,
      height: group.height,
    );
    final after = e.currentPage!.findShapeById(g)!.children.first;
    expect(after.width, closeTo(beforeW * 2, 1e-6));
  });

  test('pasteStyle seeds empty text run', () {
    final e = ctrl();
    final src = rect(e, 2, 4);
    e.setShapeText(src, 'BoldSrc');
    e.setSelection([src]);
    e.setBold(true);
    e.copyStyle();
    final dst = rect(e, 5, 4);
    e.setSelection([dst]);
    e.pasteStyle();
    final runs = e.currentPage!.findShapeById(dst)!.richText.runs;
    expect(runs, isNotEmpty);
    expect(runs.first.charStyle.style.bold, isTrue);
  });
}
