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
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1,
        height: 0.6,
      ),
      x,
      y,
    );
    return e.singleSelectedId!;
  }

  test('individual shape deltas skip locks and undo as one edit', () {
    final e = ctrl();
    final movable = rect(e, 2, 6);
    final locked = rect(e, 7, 2);
    e.setSelection(<int>{locked});
    e.setSelectionLocked(true);
    final beforeMovable = e.currentPage!.findShapeById(movable)!;
    final beforeLocked = e.currentPage!.findShapeById(locked)!;

    e.moveShapesBy(<int, Offset2D>{
      movable: const Offset2D(1.25, -0.75),
      locked: const Offset2D(-2, 2),
    });

    var shape = e.currentPage!.findShapeById(movable)!;
    expect(shape.pinX, closeTo(beforeMovable.pinX + 1.25, 1e-9));
    expect(shape.pinY, closeTo(beforeMovable.pinY - 0.75, 1e-9));
    shape = e.currentPage!.findShapeById(locked)!;
    expect(shape.pinX, beforeLocked.pinX);
    expect(shape.pinY, beforeLocked.pinY);

    e.undo();
    shape = e.currentPage!.findShapeById(movable)!;
    expect(shape.pinX, beforeMovable.pinX);
    expect(shape.pinY, beforeMovable.pinY);
  });

  test('remote connector move detaches stationary targets in one undo', () {
    final e = ctrl();
    final source = rect(e, 2, 4);
    final target = rect(e, 7, 4);
    e.createConnector(2, 4, 7, 4, beginTarget: source, endTarget: target);
    final connector = e.singleSelectedId!;
    final before = e.currentPage!.findShapeById(connector)!;
    expect(
      e.currentPage!.connects.where((c) => c.fromSheetId == connector),
      hasLength(2),
    );

    e.beginTransaction();
    e.detachSelectionConnectorsFromStationaryShapes(transient: true);
    e.moveSelectionBy(1, 0.5, transient: true);
    e.commitTransaction();

    final moved = e.currentPage!.findShapeById(connector)!;
    expect(
      e.currentPage!.connects.where((c) => c.fromSheetId == connector),
      isEmpty,
    );
    expect(moved.beginX, closeTo(before.beginX! + 1, 1e-9));
    expect(moved.beginY, closeTo(before.beginY! + 0.5, 1e-9));
    expect(moved.endX, closeTo(before.endX! + 1, 1e-9));
    expect(moved.endY, closeTo(before.endY! + 0.5, 1e-9));

    e.undo();
    expect(
      e.currentPage!.connects.where((c) => c.fromSheetId == connector),
      hasLength(2),
    );
    expect(e.currentPage!.findShapeById(connector)!.beginX, before.beginX);
    expect(e.currentPage!.findShapeById(connector)!.endX, before.endX);
  });

  test('remote connector move preserves glue to targets moving with it', () {
    final e = ctrl();
    final source = rect(e, 2, 4);
    final target = rect(e, 7, 4);
    e.createConnector(2, 4, 7, 4, beginTarget: source, endTarget: target);
    final connector = e.singleSelectedId!;
    e.setSelection(<int>{source, connector});

    e.detachSelectionConnectorsFromStationaryShapes();

    final glue = e.currentPage!.connects
        .where((c) => c.fromSheetId == connector)
        .toList();
    expect(glue, hasLength(1));
    expect(glue.single.toSheetId, source);
  });
}
