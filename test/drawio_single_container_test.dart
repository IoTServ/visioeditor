import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  EditorController controllerWithShape(
    VsdxShape Function(int id, double x, double y) builder,
  ) {
    final controller = EditorController()..newDocument();
    addTearDown(controller.dispose);
    controller.addShapeFromBuilderAt(builder, 4, 4);
    return controller;
  }

  test('container override preserves unrelated User cells', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
    ).copyWith(
      userCells: const <VsdxUserCell>[
        VsdxUserCell(name: 'foreignMeta', value: 'keep'),
      ],
    );

    final container = shape.withContainerEnabled(true);
    expect(container.shapeKind, VsdxShapeKind.container);
    expect(container.containerOverride, isTrue);
    expect(
      container.userCells
          .firstWhere((cell) => cell.name == 'foreignMeta')
          .value,
      'keep',
    );

    final normal = container.withContainerEnabled(false);
    expect(normal.shapeKind, VsdxShapeKind.normal);
    expect(normal.containerOverride, isFalse);
    expect(
      normal.userCells.firstWhere((cell) => cell.name == 'foreignMeta').value,
      'keep',
    );
  });

  test('single Group and Ungroup toggle containment with undo', () {
    final controller = controllerWithShape(
      (id, x, y) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: x,
        pinY: y,
        width: 2,
        height: 2,
      ),
    );
    final id = controller.singleSelectedId!;
    expect(controller.canGroup, isTrue);
    expect(controller.currentPage!.findDropContainerAt(4, 4), isNull);

    controller.groupSelection();
    expect(controller.singleSelectedId, id);
    expect(
      controller.currentPage!.findShapeById(id)!.shapeKind,
      VsdxShapeKind.container,
    );
    expect(controller.currentPage!.findDropContainerAt(4, 4), id);
    expect(controller.canUngroup, isTrue);

    controller.undo();
    expect(
      controller.currentPage!.findShapeById(id)!.shapeKind,
      VsdxShapeKind.normal,
    );
    controller.redo();
    expect(
      controller.currentPage!.findShapeById(id)!.shapeKind,
      VsdxShapeKind.container,
    );

    controller.collapseSelection();
    expect(controller.currentPage!.findShapeById(id)!.collapsed, isTrue);
    controller.ungroupSelection();
    expect(controller.singleSelectedId, id);
    final normal = controller.currentPage!.findShapeById(id)!;
    expect(normal.shapeKind, VsdxShapeKind.normal);
    expect(normal.collapsed, isFalse);
    expect(normal.height, closeTo(2, 1e-9));
    expect(controller.currentPage!.findDropContainerAt(4, 4), isNull);
  });

  test('positive and negative container overrides survive VSDX round-trip', () {
    final promoted = controllerWithShape(
      (id, x, y) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: x,
        pinY: y,
        width: 2,
        height: 1,
      ),
    );
    promoted.groupSelection();
    final promotedShape =
        const DocumentParser().parse(promoted.exportToBytes()).pages.single.shapes.single;
    expect(promotedShape.shapeKind, VsdxShapeKind.container);
    expect(promotedShape.containerOverride, isTrue);

    final demoted = controllerWithShape(
      (id, x, y) => VsdxShapeFactory.container(
        id: id,
        pinX: x,
        pinY: y,
        width: 3,
        height: 2,
      ),
    );
    expect(demoted.canUngroup, isTrue);
    demoted.ungroupSelection();
    final demotedShape =
        const DocumentParser().parse(demoted.exportToBytes()).pages.single.shapes.single;
    expect(demotedShape.name, startsWith('Container.'));
    expect(demotedShape.shapeKind, VsdxShapeKind.normal);
    expect(demotedShape.containerOverride, isFalse);
  });
}
