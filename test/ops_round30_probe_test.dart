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
      {double w = 1, double h = 0.6}) {
    e.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: w, height: h),
        x,
        y);
    return e.singleSelectedId!;
  }

  int container(EditorController e, double x, double y) {
    final id = e.currentPage!.nextFreeShapeId();
    e.updateCurrentPage(
      (p) => p.addShape(
        VsdxShapeFactory.container(
          id: id,
          pinX: x,
          pinY: y,
          width: 4,
          height: 3,
        ),
      ),
    );
    return id;
  }

  test('cut nested child paste follows page pin', () {
    final e = ctrl();
    final box = container(e, 5, 4);
    final child = rect(e, 5, 4);
    e.setSelection([child]);
    e.reparentSelectionInto(box);
    final before = e.currentPage!.shapePinPage(child);
    final localPin = e.currentPage!.findShapeById(child)!.pinX;
    e.setSelection([child]);
    e.cut();
    e.pasteAt();
    final pasted = e.singleSelectedId!;
    final after = e.currentPage!.shapePinPage(pasted);
    expect(after.x, isNot(closeTo(localPin + 0.25, 0.05)));
    expect(after.x, closeTo(before.x + 0.25, 0.05));
    expect(after.y, closeTo(before.y - 0.25, 0.05));
  });

  test('reparentSelectionInto group+child keeps child in group', () {
    final e = ctrl();
    final box = container(e, 6, 4);
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    e.setSelection([g, child]);
    e.reparentSelectionInto(box);
    expect(e.currentPage!.findParentId(g), box);
    expect(e.currentPage!.findParentId(child), g);
  });

  test('applyDropContainmentAt group+child keeps child in group', () {
    final e = ctrl();
    final box = container(e, 6, 4);
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    e.setSelection([g, child]);
    e.applyDropContainmentAt(6, 4, transient: false);
    expect(e.currentPage!.findParentId(g), box);
    expect(e.currentPage!.findParentId(child), g);
  });

  test('distributeHorizontally ignores co-selected nested child', () {
    final e = ctrl();
    final left = rect(e, 1, 4, w: 1, h: 0.6);
    final midA = rect(e, 3, 4, w: 1, h: 0.6);
    final midB = rect(e, 4.2, 4, w: 1, h: 0.6);
    e.setSelection([midA, midB]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    final right = rect(e, 8, 4, w: 1, h: 0.6);

    // Roots-only baseline on a fresh controller.
    final e2 = ctrl();
    final l2 = rect(e2, 1, 4, w: 1, h: 0.6);
    final m2a = rect(e2, 3, 4, w: 1, h: 0.6);
    final m2b = rect(e2, 4.2, 4, w: 1, h: 0.6);
    e2.setSelection([m2a, m2b]);
    e2.groupSelection();
    final g2 = e2.singleSelectedId!;
    final r2 = rect(e2, 8, 4, w: 1, h: 0.6);
    e2.setSelection([l2, g2, r2]);
    e2.distributeHorizontally();
    final baseLeft = e2.currentPage!.shapePageAabb(l2)!.left;
    final baseGroup = e2.currentPage!.shapePageAabb(g2)!.left;
    final baseRight = e2.currentPage!.shapePageAabb(r2)!.left;

    e.setSelection([left, g, child, right]);
    e.distributeHorizontally();
    expect(e.currentPage!.shapePageAabb(left)!.left, closeTo(baseLeft, 1e-3));
    expect(e.currentPage!.shapePageAabb(g)!.left, closeTo(baseGroup, 1e-3));
    expect(e.currentPage!.shapePageAabb(right)!.left, closeTo(baseRight, 1e-3));
  });

  test('connectDirectional nested source seeds page-space endpoint', () {
    final e = ctrl();
    final box = container(e, 4, 4);
    final nested = rect(e, 4, 4);
    e.setSelection([nested]);
    e.reparentSelectionInto(box);
    final srcPin = e.currentPage!.shapePinPage(nested);
    final localPin = e.currentPage!.findShapeById(nested)!.pinX;
    expect(localPin, isNot(closeTo(srcPin.x, 1e-3)));
    e.connectDirectional(
      nested,
      1,
      cloneX: srcPin.x + 2,
      cloneY: srcPin.y,
    );
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D);
    final begin = VsdxPage.connectorRoute(conn).first;
    // Facing CP is ~half-width east of page pin — still page space, not local.
    expect(begin.x, closeTo(srcPin.x + 0.5, 0.35));
    expect(begin.x, isNot(closeTo(localPin, 0.35)));
    expect(begin.y, closeTo(srcPin.y, 0.35));
  });

  test('connectDirectional nested clone keeps page angle', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.rotateShape(g, math.pi / 2);
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    final pin = e.currentPage!.shapePinPage(child);
    // Local angle under rotated parent is ~0; page heading is ~π/2.
    expect(e.currentPage!.findShapeById(child)!.angleRad, closeTo(0, 1e-6));
    e.connectDirectional(child, 1, cloneX: pin.x + 2.5, cloneY: pin.y);
    final clone = e.currentPage!.findShapeById(e.singleSelectedId!)!;
    expect(clone.angleRad.abs(), greaterThan(1.0));
  });
}
