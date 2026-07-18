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

  test('selectPage clears stale text edit session', () {
    final e = ctrl();
    final a = rect(e, 2, 4, text: 'hello');
    e.setTextEditSession(shapeId: a, start: 0, end: 0);
    expect(e.textEditShapeId, a);
    e.addPage();
    final b = rect(e, 3, 3, text: 'world');
    expect(e.textEditShapeId, isNull);
    e.setSelection([b]);
    e.setBold(true);
    expect(
      e.currentPage!.findShapeById(b)!.richText.runs.first.charStyle.style.bold,
      isTrue,
    );
  });

  test('deleteCurrentPage clears BackPage refs to deleted id', () {
    final e = ctrl();
    e.addPage();
    e.selectPage(1);
    e.setPageIsBackground(true);
    final bgId = e.currentPage!.id;
    e.selectPage(0);
    e.setBackgroundPage(bgId);
    expect(e.currentPage!.backgroundPageId, bgId);
    e.selectPage(1);
    e.deleteCurrentPage();
    expect(e.currentPageIndex, 0);
    expect(e.currentPage!.backgroundPageId, isNull);
    e.undo();
    expect(e.document!.pages.any((p) => p.id == bgId), isTrue);
    final fg = e.document!.pages.firstWhere((p) => p.id != bgId);
    expect(fg.backgroundPageId, bgId);
  });

  test('locked ancestor layer blocks editing nested child', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 3, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    e.addLayer(name: 'LockMe');
    final layerId = e.currentPage!.layers.last.id;
    e.setSelection([g]);
    e.assignSelectionToLayer(layerId);
    e.toggleLayerLocked(layerId);
    expect(e.isOnLockedLayer(child), isTrue);
    final pinX = e.currentPage!.findShapeById(child)!.pinX;
    e.setSelection([child]);
    e.moveSelectionBy(0.5, 0);
    expect(e.currentPage!.findShapeById(child)!.pinX, closeTo(pinX, 1e-9));
  });

  test('reparentSelectionInto rejects locked and hidden containers', () {
    final e = ctrl();
    final movable = rect(e, 1, 4);
    final lockedHost = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 3,
      height: 2,
    ).copyWith(locked: true);
    e.updateCurrentPage((p) => p.addShape(lockedHost));
    e.setSelection([movable]);
    e.reparentSelectionInto(lockedHost.id);
    expect(e.currentPage!.findParentId(movable), isNull);

    final hiddenHost = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 7,
      pinY: 4,
      width: 3,
      height: 2,
    );
    e.updateCurrentPage((p) => p.addShape(hiddenHost));
    e.addLayer(name: 'H');
    final layerId = e.currentPage!.layers.last.id;
    e.setSelection([hiddenHost.id]);
    e.assignSelectionToLayer(layerId);
    e.toggleLayerVisibility(layerId);
    e.setSelection([movable]);
    e.reparentSelectionInto(hiddenHost.id);
    expect(e.currentPage!.findParentId(movable), isNull);
  });

  test('applyDropContainmentAt ignores locked drop target', () {
    final e = ctrl();
    final movable = rect(e, 1, 4);
    final host = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 3,
      height: 2,
    ).copyWith(locked: true);
    e.updateCurrentPage((p) => p.addShape(host));
    e.setSelection([movable]);
    final drop = e.applyDropContainmentAt(4, 4, transient: false);
    expect(drop, isNull);
    expect(e.currentPage!.findParentId(movable), isNull);
  });
}
