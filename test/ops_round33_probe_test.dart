import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/editor/shape_clipboard.dart';
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

  test('reparent into flipX parent preserves page chirality', () {
    final e = ctrl();
    final box = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    e.setSelection([box.id]);
    e.flipHorizontal();
    final id = rect(e, 4, 4);
    final before = e.currentPage!.shapePageAabb(id)!;
    e.setSelection([id]);
    e.reparentSelectionInto(box.id);
    final child = e.currentPage!.findShapeById(id)!;
    final after = e.currentPage!.shapePageAabb(id)!;
    expect(after.left, closeTo(before.left, 1e-6));
    expect(after.right, closeTo(before.right, 1e-6));
    // Baked so parent flip does not double-mirror the geometry.
    expect(child.flipX, isTrue);
  });

  test('dontMoveChildren move under flipped host keeps child flip', () {
    final e = ctrl();
    final box = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    e.setSelection([box.id]);
    e.flipHorizontal();
    final child = rect(e, 4, 4);
    e.setSelection([child]);
    e.reparentSelectionInto(box.id);
    final flipBefore = e.currentPage!.findShapeById(child)!.flipX;
    e.updateCurrentPage(
      (p) => p.updateShapeById(
        box.id,
        (s) => s.copyWith(dontMoveChildren: true),
      ),
    );
    e.setSelection([box.id]);
    e.moveSelectionBy(0.5, 0);
    expect(e.currentPage!.findShapeById(child)!.flipX, flipBefore);
  });

  test('setSelectedAngleDegrees uses page degrees under rotated parent', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.rotateShape(g, math.pi / 6);
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    e.setSelection([child]);
    expect(e.selectedGeometry!.angleDeg, closeTo(30, 0.5));
    e.setSelectedAngleDegrees(45);
    expect(e.selectedGeometry!.angleDeg, closeTo(45, 0.5));
    expect(
      e.currentPage!.shapePageAngle(child) * 180 / math.pi,
      closeTo(45, 0.5),
    );
  });

  test('pasteFromSystem keeps picture after copy of labeled image', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? stored;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments;
        if (args is Map && args['text'] is String) {
          stored = args['text'] as String;
        }
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return stored == null ? null : <String, dynamic>{'text': stored};
      }
      return null;
    });
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
    final img = e.singleSelectedId!;
    e.setShapeText(img, 'caption');
    e.copySelection();
    await Future<void>.delayed(Duration.zero);
    // Labeled image writes a media-bearing envelope (not plain caption text).
    expect(stored, isNotNull);
    expect(stored!, startsWith(ShapeClipboardCodec.prefix));
    expect(stored!.contains('caption'), isFalse);
    await e.pasteFromSystem(cx: 6, cy: 4);
    expect(e.currentPage!.findShapeById(e.singleSelectedId!)!.hasImage, isTrue);
  });

  test('distributeHorizontally ignores 1D co-selection', () {
    final e = ctrl();
    final a = rect(e, 1, 4, w: 1, h: 0.6);
    final b = rect(e, 4, 4, w: 1, h: 0.6);
    final c = rect(e, 7, 4, w: 1, h: 0.6);
    e.createConnector(2, 4, 3, 4);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([a, b, c]);
    e.distributeHorizontally();
    final gapRoots = e.currentPage!.shapePageAabb(b)!.left;
    e.undo();
    e.setSelection([a, conn, b, c]);
    e.distributeHorizontally();
    expect(e.currentPage!.shapePageAabb(b)!.left, closeTo(gapRoots, 1e-3));
  });

  test('softEdges memo prefers 2D in mixed selection', () {
    final e = ctrl();
    final box = rect(e, 2, 4);
    e.createConnector(4, 4, 6, 4);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn, box]);
    e.setSoftEdges(true);
    e.setTool(EditorTool.rectangle);
    e.createShapeByDrag(1, 1, 2.5, 2);
    final created = e.currentPage!.findShapeById(e.singleSelectedId!)!;
    expect(created.line.softEdgesInches, greaterThan(0));
  });
}
