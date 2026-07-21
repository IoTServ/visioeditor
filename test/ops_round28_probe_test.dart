import 'package:flutter/services.dart';
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

  int rect(EditorController e, double x, double y) {
    e.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1, height: 0.6),
        x,
        y);
    return e.singleSelectedId!;
  }

  test('moveSelectionBy on group+child does not double-move child', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    final before = e.currentPage!.shapePinPage(child);
    e.setSelection([g, child]);
    e.moveSelectionBy(1, 0);
    final after = e.currentPage!.shapePinPage(child);
    expect(after.x - before.x, closeTo(1, 1e-6));
    expect(after.y - before.y, closeTo(0, 1e-6));
  });

  test('flipHorizontal on group+child does not flip child twice', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    e.setSelection([g, child]);
    e.flipHorizontal();
    expect(e.currentPage!.findShapeById(g)!.flipX, isTrue);
    expect(e.currentPage!.findShapeById(child)!.flipX, isFalse);
  });

  test('rotateSelection90 on group+child only rotates group', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    final childAngle = e.currentPage!.findShapeById(child)!.angleRad;
    e.setSelection([g, child]);
    e.rotateSelection90();
    expect(e.currentPage!.findShapeById(g)!.angleRad, isNot(0));
    expect(e.currentPage!.findShapeById(child)!.angleRad, childAngle);
  });

  test('pasteFromSystem accepts plain text after image-only copy', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // Re-bind immediately before paste so parallel clipboard tests cannot
    // clobber this mock between copy and sync.
    String? stored = 'hello from outside';
    void bind() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          // Ignore writes from image-only copy (empty / labels).
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': stored};
        }
        return null;
      });
    }

    bind();
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final e = ctrl();
    e.insertImage(
      Uint8List.fromList([1, 2, 3, 4]),
      fileExtension: 'png',
      widthInches: 1,
      heightInches: 1,
      cx: 3,
      cy: 3,
    );
    e.copySelection();
    await Future<void>.delayed(Duration.zero);
    bind();
    stored = 'hello from outside';
    await e.pasteFromSystem(cx: 5, cy: 5);
    final pasted = e.currentPage!.shapes.last;
    expect(pasted.hasImage, isFalse);
    final label = (pasted.text ?? pasted.richText.plainText).trim();
    expect(label, 'hello from outside');
  });

  test('replaceImage on hidden-layer picture is no-op', () {
    final e = ctrl();
    e.insertImage(
      Uint8List.fromList([1, 2, 3, 4]),
      fileExtension: 'png',
      widthInches: 1,
      heightInches: 1,
      cx: 3,
      cy: 3,
    );
    final img = e.currentPage!.shapes.singleWhere((s) => s.hasImage).id;
    final part = e.currentPage!.findShapeById(img)!.imagePartName;
    e.addLayer(name: 'Hide');
    final layerId = e.currentPage!.layers.last.id;
    e.setSelection([img]);
    e.assignSelectionToLayer(layerId);
    e.toggleLayerVisibility(layerId);
    expect(e.canReplaceSelectedImage, isFalse);
    e.replaceImage(
      img,
      Uint8List.fromList([9, 9, 9, 9]),
      fileExtension: 'png',
    );
    expect(e.currentPage!.findShapeById(img)!.imagePartName, part);
  });

  test('ungroupSelection keeps non-group co-selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    final c = rect(e, 6, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.setSelection([g, c]);
    e.ungroupSelection();
    expect(e.selection.contains(c), isTrue);
    expect(e.selection.contains(g), isFalse);
    expect(e.selection.length, greaterThanOrEqualTo(3));
  });

  test('setSelectedX under rotated group moves page AABB', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.rotateShape(g, 0.6);
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    e.setSelection([child]);
    final left0 = e.currentPage!.shapePageAabb(child)!.left;
    e.setSelectedX(left0 + 1);
    final left1 = e.currentPage!.shapePageAabb(child)!.left;
    expect(left1 - left0, closeTo(1, 0.05));
  });

  test('alignLeft uses page AABB for nested child', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.rotateShape(g, 0.4);
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    final outer = rect(e, 1, 2);
    e.setSelection([child, outer]);
    e.alignLeft();
    final leftChild = e.currentPage!.shapePageAabb(child)!.left;
    final leftOuter = e.currentPage!.shapePageAabb(outer)!.left;
    expect(leftChild, closeTo(leftOuter, 0.05));
  });
}
