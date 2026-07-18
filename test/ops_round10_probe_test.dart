import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/edit_link_dialog.dart';
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

  int rotatedRect(EditorController e, double x, double y,
      {double w = 1, double h = 0.6, double angle = 0}) {
    final id = rect(e, x, y, w: w, h: h);
    e.rotateShape(id, angle);
    return id;
  }

  test('matchSelectionSize rotated 45 keeps page AABB top-left', () {
    final e = ctrl();
    final a = rect(e, 2, 4, w: 2, h: 1);
    final b = rotatedRect(e, 5, 4, w: 1, h: 0.5, angle: math.pi / 4);
    final before = e.currentPage!.shapePageAabb(b)!;
    e.setSelection([a, b]);
    e.matchSelectionSize();
    final after = e.currentPage!.shapePageAabb(b)!;
    expect(after.left, closeTo(before.left, 1e-3));
    expect(after.top, closeTo(before.top, 1e-3));
    final shaped = e.currentPage!.findShapeById(b)!;
    expect(shaped.width, closeTo(2, 1e-6));
    expect(shaped.height, closeTo(1, 1e-6));
  });

  test('lane resize grows pool height', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(
      (id, cx, cy) => SwimlaneOps.assemblePool(
          poolId: id,
          pinX: cx,
          pinY: cy,
          width: 4,
          height: 3,
          laneCount: 2),
      5.5,
      4.25,
    );
    final poolId = e.singleSelectedId!;
    final pool = e.currentPage!.findShapeById(poolId)!;
    final lane = SwimlaneOps.lanesOf(pool).first;
    final poolH = pool.height;
    e.resizeShape(
      lane.id,
      pinX: lane.pinX,
      pinY: lane.pinY,
      width: lane.width,
      height: lane.height + 1,
    );
    final afterPool = e.currentPage!.findShapeById(poolId)!;
    expect(afterPool.height, closeTo(poolH + 1, 1e-6));
    final afterLanes = SwimlaneOps.lanesOf(afterPool);
    expect(afterLanes.first.height, closeTo(lane.height + 1, 1e-6));
  });

  test('edit link merge keeps secondary via mergeEditedPrimaryLink', () {
    final existing = [
      const VsdxHyperlink(id: 0, address: 'https://a.example', isDefault: true),
      const VsdxHyperlink(id: 1, address: 'https://b.example', isDefault: false),
    ];
    final merged = mergeEditedPrimaryLink(
      existing: existing,
      editedPrimary: const VsdxHyperlink(
        id: 0,
        address: 'https://c.example',
        isDefault: true,
      ),
    );
    expect(merged, hasLength(2));
    expect(merged.any((h) => h.address == 'https://b.example'), isTrue);
  });

  test('toggleBold on locked is no-op', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setShapeText(a, 'hello');
    e.setSelectionLocked(true);
    e.toggleBold();
    final s = e.currentPage!.findShapeById(a)!;
    expect(s.richText.runs.first.charStyle.style.bold, isFalse);
  });

  test('movePage keeps selection on active page', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.addPage();
    e.selectPage(0);
    e.setSelection([a]);
    e.movePage(0, 1);
    expect(e.selection, equals({a}));
  });

  test('pasteStyle on locked-layer shape is skipped', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a]);
    e.setFillColor(const VsdxColor(0xFFFF0000));
    e.copyStyle();
    e.addLayer(name: 'Locked');
    final layerId = e.currentPage!.layers.last.id;
    e.setSelection([b]);
    e.assignSelectionToLayer(layerId);
    e.toggleLayerLocked(layerId);
    e.pasteStyle();
    expect(e.currentPage!.findShapeById(b)!.fill.foreground,
        isNot(const VsdxColor(0xFFFF0000)));
  });

  test('bringSelectionToFront lifts nested block inside group', () {
    final e = ctrl();
    final a = rect(e, 1, 4);
    final b = rect(e, 3, 4);
    final c = rect(e, 5, 4);
    e.setSelection([a, b, c]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.setSelection([a, b]);
    e.bringSelectionToFront();
    expect(
      e.currentPage!.findShapeById(g)!.children.map((s) => s.id).toList(),
      [c, a, b],
    );
  });

  test('sendSelectionBackward nested one step', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.setSelection([b]);
    e.sendSelectionBackward();
    expect(
      e.currentPage!.findShapeById(g)!.children.map((s) => s.id).toList(),
      [b, a],
    );
  });

  test('replaceImage undo restores prior selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.insertImage(Uint8List.fromList([1, 2, 3, 4]),
        fileExtension: 'png', widthInches: 1, heightInches: 1, cx: 3, cy: 3);
    final pic = e.singleSelectedId!;
    e.setSelection([a]);
    e.replaceImage(
        pic, Uint8List.fromList([9, 9, 9, 9]), fileExtension: 'png');
    expect(e.selection, equals({pic}));
    e.undo();
    expect(e.selection, equals({a}));
  });
}
