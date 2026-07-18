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

  double angleDelta(double a, double b) {
    var d = a - b;
    while (d > math.pi) {
      d -= 2 * math.pi;
    }
    while (d < -math.pi) {
      d += 2 * math.pi;
    }
    return d;
  }

  test('pasteStyle theme fill installs Office theme on empty doc', () {
    final e = ctrl();
    final src = rect(e, 2, 4);
    e.setSelection([src]);
    e.setFillThemeSlot(ThemeSlot.accent1);
    e.copyStyle();
    e.newDocument(widthInches: 11, heightInches: 8.5);
    expect(e.documentTheme.isEmpty, isTrue);
    final dst = rect(e, 3, 3);
    e.setSelection([dst]);
    e.pasteStyle();
    expect(e.documentTheme.isEmpty, isFalse);
    expect(
      e.currentPage!.findShapeById(dst)!.fill.themeForegroundIndex,
      ThemeSlot.accent1,
    );
  });

  test('selectNextShape from nested child advances top-level sibling', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 3, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    final c = rect(e, 6, 4);
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    e.setSelection([child]);
    e.selectNextShape();
    expect(e.singleSelectedId, c);
  });

  test('find skips children of collapsed containers', () {
    final e = ctrl();
    final inner = rect(e, 3, 3, text: 'secret');
    final box = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    e.setSelection([inner]);
    e.reparentSelectionInto(box.id);
    e.toggleCollapsed(box.id);
    e.updateFind('secret');
    expect(e.findMatchCount, 0);
  });

  test('hide layer drops selection of shapes on that layer', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.addLayer(name: 'L');
    final layerId = e.currentPage!.layers.last.id;
    e.setSelection([a]);
    e.assignSelectionToLayer(layerId);
    e.toggleLayerVisibility(layerId);
    expect(e.selection, isEmpty);
  });

  test('hide group layer prunes nested child selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 3, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    e.addLayer(name: 'G');
    final layerId = e.currentPage!.layers.last.id;
    e.setSelection([g]);
    e.assignSelectionToLayer(layerId);
    e.setSelection([child]);
    expect(e.currentPage!.isShapeTreeVisible(child), isTrue);
    e.toggleLayerVisibility(layerId);
    expect(e.currentPage!.isShapeTreeVisible(child), isFalse);
    expect(e.selection, isEmpty);
  });

  test('replaceAllFind skips hidden layer and collapsed children', () {
    final e = ctrl();
    final hidden = rect(e, 1, 4, text: 'foo');
    final folded = rect(e, 3, 3, text: 'foo');
    final visible = rect(e, 6, 4, text: 'foo');
    e.addLayer(name: 'H');
    final layerId = e.currentPage!.layers.last.id;
    e.setSelection([hidden]);
    e.assignSelectionToLayer(layerId);
    e.toggleLayerVisibility(layerId);

    final box = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 3,
      height: 2,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    e.setSelection([folded]);
    e.reparentSelectionInto(box.id);
    e.toggleCollapsed(box.id);

    e.updateFind('foo');
    expect(e.findMatchCount, 1);
    e.replaceAllFind('bar');
    expect(
      e.currentPage!.findShapeById(hidden)!.richText.plainText,
      'foo',
    );
    expect(
      e.currentPage!.findShapeById(folded)!.richText.plainText,
      'foo',
    );
    expect(
      e.currentPage!.findShapeById(visible)!.richText.plainText,
      'bar',
    );
  });

  test('hide layer invalidates find matches before replace', () {
    final e = ctrl();
    final a = rect(e, 2, 4, text: 'foo');
    e.addLayer(name: 'H');
    final layerId = e.currentPage!.layers.last.id;
    e.setSelection([a]);
    e.assignSelectionToLayer(layerId);
    e.updateFind('foo');
    expect(e.findMatchCount, 1);
    e.toggleLayerVisibility(layerId);
    expect(e.findMatchCount, 0);
    e.replaceFind('bar');
    expect(e.currentPage!.findShapeById(a)!.richText.plainText, 'foo');
  });

  test('rotateSelection90 under flipped group turns page-clockwise', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 3.5, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.flipHorizontal();
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    e.setSelection([child]);
    final before = e.currentPage!.shapePageAngle(child);
    e.rotateSelection90(clockwise: true);
    final after = e.currentPage!.shapePageAngle(child);
    expect(angleDelta(after, before - math.pi / 2), closeTo(0, 1e-6));
  });

  test('setSelectedWidth on rotated shape is one undo step', () {
    final e = ctrl();
    final id = rect(e, 3, 3, w: 2, h: 1);
    e.rotateShape(id, math.pi / 4);
    final before = e.currentPage!.findShapeById(id)!;
    final pinX = before.pinX;
    final pinY = before.pinY;
    final w = before.width;
    e.setSelectedWidth(w + 1);
    expect(e.currentPage!.findShapeById(id)!.width, closeTo(w + 1, 1e-9));
    e.undo();
    final after = e.currentPage!.findShapeById(id)!;
    expect(after.width, closeTo(w, 1e-9));
    expect(after.pinX, closeTo(pinX, 1e-6));
    expect(after.pinY, closeTo(pinY, 1e-6));
  });

  test('ungroup with non-centre LocPin keeps child page pin', () {
    final e = ctrl();
    final child = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 1,
      pinY: 1,
      width: 1,
      height: 1,
    );
    final group = VsdxShape(
      id: 1,
      name: 'G',
      pinX: 5,
      pinY: 5,
      width: 4,
      height: 4,
      locPinXInches: 0,
      locPinYInches: 0,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      shapeKind: VsdxShapeKind.group,
      children: <VsdxShape>[child],
    );
    e.updateCurrentPage((p) => p.copyWith(shapes: <VsdxShape>[group]));
    final before = e.currentPage!.shapePinPage(2);
    e.setSelection([1]);
    e.ungroupSelection();
    final after = e.currentPage!.findShapeById(2)!;
    expect(after.pinX, closeTo(before.x, 1e-9));
    expect(after.pinY, closeTo(before.y, 1e-9));
  });
}
