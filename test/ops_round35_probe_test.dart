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

  test('group shifts connector waypoints with begin/end', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 6, 4);
    e.createConnector(2, 4, 6, 4);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setConnectorWaypoints(conn, [const Offset2D(4, 5)]);
    final before = e.currentPage!.findShapeById(conn)!;
    final bx = before.beginX!;
    final wx = before.waypoints.first.x;
    e.setSelection([a, b, conn]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    final nested = e.currentPage!
        .findShapeById(g)!
        .children
        .firstWhere((s) => s.is1D);
    expect(
      nested.waypoints.first.x - wx,
      closeTo(nested.beginX! - bx, 1e-6),
    );
    expect(
      nested.waypoints.first.y - before.waypoints.first.y,
      closeTo(nested.beginY! - before.beginY!, 1e-6),
    );
  });

  test('rotate group then ungroup keeps waypoint with begin', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 6, 4);
    e.createConnector(2, 4, 6, 4);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setConnectorWaypoints(conn, [const Offset2D(4, 5)]);
    e.setSelection([a, b, conn]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.rotateShape(g, math.pi / 2);
    e.ungroupSelection();
    final after = e.currentPage!.findShapeById(conn)!;
    // 90° Visio CCW about group centre ≈ (4,4): (4,5) → (3,4).
    expect(after.waypoints.first.x, closeTo(3, 0.35));
    expect(after.waypoints.first.y, closeTo(4, 0.35));
    // Waypoint must track begin/end (not stay at pre-rotation page coords).
    expect(after.beginX, closeTo(4, 0.35));
    expect(after.waypoints.first.x, isNot(closeTo(4, 0.2)));
  });

  test('deleteCurrentPage clears guides so reused page id is clean', () {
    final e = ctrl();
    e.addPage();
    e.selectPage(1);
    e.addPageGuide(vertical: true, pos: 7.7);
    expect(e.pageGuides, isNotEmpty);
    final id = e.currentPage!.id;
    e.deleteCurrentPage();
    e.addPage();
    e.selectPage(e.pageCount - 1);
    expect(e.currentPage!.id, id);
    expect(e.pageGuides, isEmpty);
  });

  test('pasteStyle from 1D does not clear Soft Edges on 2D', () {
    final e = ctrl();
    final box = rect(e, 2, 4);
    e.setSelection([box]);
    e.setSoftEdges(true);
    expect(
      e.currentPage!.findShapeById(box)!.line.softEdgesInches,
      greaterThan(0),
    );
    e.createConnector(4, 4, 6, 4);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.copyStyle();
    e.setSelection([box]);
    e.pasteStyle();
    expect(
      e.currentPage!.findShapeById(box)!.line.softEdgesInches,
      greaterThan(0),
    );
  });

  test('canUngroup is true for nested group selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 3, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final inner = e.singleSelectedId!;
    final c = rect(e, 5, 4);
    e.setSelection([inner, c]);
    e.groupSelection();
    e.setSelection([inner]);
    expect(e.canUngroup, isTrue);
    e.ungroupSelection();
    expect(e.currentPage!.findShapeById(inner), isNull);
    expect(e.currentPage!.findParentId(a), isNotNull);
  });
}
