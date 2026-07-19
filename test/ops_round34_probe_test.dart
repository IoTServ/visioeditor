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

  /// Whether [id]'s local→page map reflects (det &lt; 0).
  bool pageReflects(EditorController e, int id) {
    final page = e.currentPage!;
    final s = page.findShapeById(id)!;
    final lx = s.effectiveLocPinX;
    final ly = s.effectiveLocPinY;
    final origin = page.localToPageDeep(id, Offset2D(lx, ly));
    final right = page.localToPageDeep(id, Offset2D(lx + 1, ly));
    final up = page.localToPageDeep(id, Offset2D(lx, ly + 1));
    final rx = right.x - origin.x;
    final ry = right.y - origin.y;
    final ux = up.x - origin.x;
    final uy = up.y - origin.y;
    return (rx * uy - ry * ux) < 0;
  }

  test('reparent flipY shape into container keeps page reflection', () {
    final e = ctrl();
    final id = rect(e, 3, 3);
    e.flipVertical();
    expect(pageReflects(e, id), isTrue);
    final before = e.currentPage!.shapePageAabb(id)!;
    final box = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    e.setSelection([id]);
    e.reparentSelectionInto(box.id);
    expect(pageReflects(e, id), isTrue);
    final after = e.currentPage!.shapePageAabb(id)!;
    expect(after.left, closeTo(before.left, 1e-6));
    expect(after.top, closeTo(before.top, 1e-6));
  });

  test('pasteAt offsets connector begin/end with pin', () {
    final e = ctrl();
    e.createConnector(2, 4, 5, 4);
    final c = e.currentPage!.shapes.lastWhere((s) => s.is1D);
    final beginX = c.beginX!;
    final endX = c.endX!;
    e.setSelection([c.id]);
    e.copySelection();
    e.pasteAt();
    final p = e.currentPage!.findShapeById(e.singleSelectedId!)!;
    expect(p.beginX! - beginX, closeTo(p.pinX - c.pinX, 1e-6));
    expect(p.endX! - endX, closeTo(p.pinX - c.pinX, 1e-6));
    expect(p.beginY! - c.beginY!, closeTo(p.pinY - c.pinY, 1e-6));
  });

  test('pasteAt centres NURBS connector on stroke AABB not Begin→End chord', () {
    final e = ctrl();
    final id = e.currentPage!.nextFreeShapeId();
    // Bowed NURBS: Begin→End chord mid is Y=2, but the stroke peaks near Y≈3.
    // LocPin/Pin are intentionally out of sync with factory F= (Begin-origin
    // override); paste recalculates the full XForm so the stroke AABB stays put.
    final conn = VsdxShapeFactory.line(id: id, ax: 1, ay: 2, bx: 4, by: 2)
        .copyWith(
      width: 3,
      height: 1.2,
      locPinXInches: 0,
      locPinYInches: 0,
      pinX: 1,
      pinY: 2,
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, 0),
            NurbsTo(
              x: 3,
              y: 0,
              controlPoints: <Offset2D>[
                Offset2D(1, 1),
                Offset2D(2, 1),
              ],
              weights: <double>[1, 1, 1, 1],
              // Clamped degree-3 knot vector (cps=4 → 8 knots).
              knots: <double>[0, 0, 0, 0, 1, 1, 1, 1],
              degree: 3,
            ),
          ],
        ),
      ],
    );
    e.updateCurrentPage((p) => p.addShape(conn));
    e.setSelection([id]);
    e.copySelection();
    e.pasteAt(cx: 6, cy: 5);
    final pasted = e.currentPage!.findShapeById(e.singleSelectedId!)!;
    final aabb = e.currentPage!.shapePageAabb(pasted.id)!;
    expect((aabb.left + aabb.right) / 2, closeTo(6, 0.2));
    expect((aabb.bottom + aabb.top) / 2, closeTo(5, 0.2));
  });

  test('pasteAt offsets connector waypoints with pin', () {
    final e = ctrl();
    e.createConnector(2, 4, 6, 4);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setConnectorWaypoints(conn, [const Offset2D(4, 5)]);
    final before = e.currentPage!.findShapeById(conn)!;
    e.setSelection([conn]);
    e.copySelection();
    e.pasteAt();
    final p = e.currentPage!.findShapeById(e.singleSelectedId!)!;
    expect(p.waypoints, hasLength(1));
    expect(
      p.waypoints.first.x - before.waypoints.first.x,
      closeTo(p.pinX - before.pinX, 1e-6),
    );
    expect(
      p.waypoints.first.y - before.waypoints.first.y,
      closeTo(p.pinY - before.pinY, 1e-6),
    );
  });

  test('alignLeft ignores 1D co-selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 5);
    e.createConnector(1, 2, 9, 2);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([a, b]);
    e.alignLeft();
    final leftRoots = e.currentPage!.shapePageAabb(a)!.left;
    e.undo();
    e.setSelection([a, conn, b]);
    e.alignLeft();
    expect(e.currentPage!.shapePageAabb(a)!.left, closeTo(leftRoots, 1e-3));
    expect(e.currentPage!.shapePageAabb(b)!.left, closeTo(leftRoots, 1e-3));
  });

  test('shapePageAngle under rotated group matches selectedGeometry', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.rotateShape(g, math.pi / 6);
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    e.setSelection([child]);
    expect(
      e.selectedGeometry!.angleDeg,
      closeTo(e.currentPage!.shapePageAngle(child) * 180 / math.pi, 0.01),
    );
  });
}
