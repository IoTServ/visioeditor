import 'dart:math' as math;

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

  test('rich text range edit ignores shape lock', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setShapeText(a, 'hello');
    e.setTextEditSession(shapeId: a, start: 0, end: 5);
    e.setSelectionLocked(true);
    e.toggleBold();
    expect(
      e.currentPage!.findShapeById(a)!.richText.runs.first.charStyle.style.bold,
      isFalse,
    );
  });

  test('rich text range edit ignores locked layer', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setShapeText(a, 'hello');
    e.addLayer(name: 'L', assignSelection: true);
    final layerId = e.currentPage!.layers.last.id;
    e.toggleLayerLocked(layerId);
    e.setTextEditSession(shapeId: a, start: 0, end: 5);
    e.toggleBold();
    expect(
      e.currentPage!.findShapeById(a)!.richText.runs.first.charStyle.style.bold,
      isFalse,
    );
  });

  test('matchSelectionSize rotated keeps AABB top-left (drawio)', () {
    final e = ctrl();
    final a = rect(e, 2, 4, w: 2, h: 1);
    final b = rect(e, 5, 4, w: 1, h: 0.5);
    e.rotateShape(b, math.pi / 4);
    final before = e.currentPage!.shapePageAabb(b)!;
    e.setSelection([a, b]);
    e.matchSelectionSize();
    final after = e.currentPage!.shapePageAabb(b)!;
    expect(after.left, closeTo(before.left, 1e-3));
    expect(after.top, closeTo(before.top, 1e-3));
  });

  test('layoutLanesPreservingSizes clamps total to minLaneSize', () {
    final pool = SwimlaneOps.assemblePool(
      poolId: 1,
      pinX: 5,
      pinY: 4,
      width: 4,
      height: 3,
      laneCount: 2,
    );
    // Shrink a lane below min
    final lanes = SwimlaneOps.lanesOf(pool);
    final shrunk = pool.copyWith(
      children: [
        for (final c in pool.children)
          if (c.id == lanes.first.id)
            c.copyWith(height: 0.05, pinY: 0.025)
          else
            c,
      ],
    );
    final laid = SwimlaneOps.layoutLanesPreservingSizes(shrunk);
    final after = SwimlaneOps.lanesOf(laid);
    final sum = after.fold<double>(0, (s, l) => s + l.height.abs());
    expect(sum, closeTo(laid.height, 1e-9));
    expect(after.first.height, closeTo(SwimlaneOps.minLaneSize, 1e-9));
  });

  test('pasteStyle transfers shadow/glow/reflection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a]);
    e.setShadow(true);
    e.setGlow(true);
    e.setReflection(true);
    e.copyStyle();
    e.setSelection([b]);
    e.pasteStyle();
    final s = e.currentPage!.findShapeById(b)!;
    expect(s.shadow.enabled, isTrue);
    expect(s.glow.enabled, isTrue);
    expect(s.reflection.enabled, isTrue);
  });

  test('lane resize then undo restores pool height', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(
      (id, cx, cy) => SwimlaneOps.assemblePool(
          poolId: id, pinX: cx, pinY: cy, width: 4, height: 3, laneCount: 2),
      5.5,
      4.25,
    );
    final poolId = e.singleSelectedId!;
    final poolH = e.currentPage!.findShapeById(poolId)!.height;
    final lane = SwimlaneOps.lanesOf(e.currentPage!.findShapeById(poolId)!).first;
    e.resizeShape(lane.id,
        pinX: lane.pinX, pinY: 1.25, width: lane.width, height: 2.5);
    expect(e.currentPage!.findShapeById(poolId)!.height, greaterThan(poolH));
    e.undo();
    expect(e.currentPage!.findShapeById(poolId)!.height, closeTo(poolH, 1e-6));
  });

  test('selectedGeometry x/y for rotated shape is AABB top-left', () {
    final e = ctrl();
    final a = rect(e, 5, 4, w: 2, h: 1);
    e.rotateShape(a, math.pi / 4);
    final g = e.selectedGeometry!;
    final aabb = e.currentPage!.shapePageAabb(a)!;
    final pageH = e.currentPage!.heightInches;
    // selectedGeometry uses Y-down from page top
    expect(g.x, closeTo(aabb.left, 1e-3));
    expect(g.y, closeTo(pageH - aabb.top, 1e-3));
  });

  test('setSelectedX on rotated moves by local box not AABB', () {
    final e = ctrl();
    final a = rect(e, 5, 4, w: 2, h: 1);
    e.rotateShape(a, math.pi / 4);
    final before = e.currentPage!.shapePageAabb(a)!;
    e.setSelectedX(before.left + 1);
    final after = e.currentPage!.shapePageAabb(a)!;
    expect(after.left, closeTo(before.left + 1, 1e-3));
  });

  test('duplicateCurrentPage clears selection without restoring on undo shapes', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.duplicateCurrentPage();
    expect(e.selection, isEmpty);
    e.undo();
    expect(e.currentPageIndex, 0);
    expect(e.selection, equals({a}));
  });

  test('deleteSelection removes the selected shape', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.deleteSelection();
    expect(e.currentPage!.findShapeById(a), isNull);
  });
}
