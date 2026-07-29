import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('Snap Selection to Grid quantises vertex geometry in one undo step', () {
    final controller = EditorController()..newDocument();
    addTearDown(controller.dispose);
    controller.addShapeFromBuilderAt(
      (id, _, _) => VsdxShapeFactory.rectangle(
        id: id,
        // left=.18, bottom=.37 with an implicit centre LocPin.
        pinX: 0.745,
        pinY: 0.68,
        width: 1.13,
        height: 0.62,
      ),
      0,
      0,
    );
    final id = controller.singleSelectedId!;
    if (controller.snapToGrid) controller.toggleSnap();
    expect(controller.canSnapSelectionToGrid, isTrue);

    controller.snapSelectionToGrid();
    var shape = controller.currentPage!.findShapeById(id)!;
    expect(shape.width, closeTo(1.25, 1e-9));
    expect(shape.height, closeTo(0.5, 1e-9));
    expect(shape.pinX - shape.effectiveLocPinX, closeTo(0.25, 1e-9));
    expect(shape.pinY - shape.effectiveLocPinY, closeTo(0.25, 1e-9));
    expect(controller.canSnapSelectionToGrid, isFalse);

    final snappedDocument = controller.document;
    controller.snapSelectionToGrid();
    expect(identical(controller.document, snappedDocument), isTrue);

    controller.undo();
    shape = controller.currentPage!.findShapeById(id)!;
    expect(shape.width, closeTo(1.13, 1e-9));
    expect(shape.height, closeTo(0.62, 1e-9));
    controller.redo();
    expect(controller.currentPage!.findShapeById(id)!.width, 1.25);
  });

  test('Snap Selection to Grid rounds connector waypoints but not endpoints',
      () {
    final controller = EditorController()..newDocument();
    addTearDown(controller.dispose);
    controller.addShapeFromBuilderAt(
      (id, _, _) =>
          VsdxShapeFactory.line(id: id, ax: 1.1, ay: 1.2, bx: 4.4, by: 4.6),
      0,
      0,
    );
    final id = controller.singleSelectedId!;
    controller.setConnectorWaypoints(
      id,
      const <Offset2D>[Offset2D(2.37, 3.62)],
    );
    final before = controller.currentPage!.findShapeById(id)!;
    expect(controller.canSnapSelectionToGrid, isTrue);

    controller.snapSelectionToGrid();
    final after = controller.currentPage!.findShapeById(id)!;
    expect(after.waypoints.single.x, closeTo(2.25, 1e-9));
    expect(after.waypoints.single.y, closeTo(3.5, 1e-9));
    expect(after.beginX, closeTo(before.beginX!, 1e-9));
    expect(after.beginY, closeTo(before.beginY!, 1e-9));
    expect(after.endX, closeTo(before.endX!, 1e-9));
    expect(after.endY, closeTo(before.endY!, 1e-9));

    controller.undo();
    final restored = controller.currentPage!.findShapeById(id)!;
    expect(restored.waypoints.single.x, closeTo(2.37, 1e-9));
    expect(restored.waypoints.single.y, closeTo(3.62, 1e-9));
  });

  test('locked shapes are excluded from Snap Selection to Grid', () {
    final controller = EditorController()..newDocument();
    addTearDown(controller.dispose);
    controller.addShapeFromBuilderAt(
      (id, _, _) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: 1.07,
        pinY: 1.09,
        width: 1.13,
        height: 0.62,
      ),
      0,
      0,
    );
    controller.toggleLock();
    final before = controller.document;
    expect(controller.canSnapSelectionToGrid, isFalse);
    controller.snapSelectionToGrid();
    expect(identical(controller.document, before), isTrue);
  });
}
