import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  EditorController controller() {
    final value = EditorController()..newDocument();
    addTearDown(value.dispose);
    return value;
  }

  test('collapsible override preserves unrelated User cells', () {
    final normal = VsdxShapeFactory.rectangle(
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
    final container = VsdxShapeFactory.container(
      id: 2,
      pinX: 4,
      pinY: 4,
      width: 3,
      height: 2,
    );

    expect(normal.collapsible, isFalse);
    expect(normal.withCollapsible(true).collapsible, isTrue);
    expect(container.collapsible, isTrue);
    final disabled = container.withCollapsible(false);
    expect(disabled.collapsible, isFalse);
    expect(
      normal
          .withCollapsible(true)
          .userCells
          .firstWhere((cell) => cell.name == 'foreignMeta')
          .value,
      'keep',
    );
  });

  test('disabling a collapsed host restores geometry and hidden glue', () {
    final value = controller();
    final page = value.currentPage!;
    final host = VsdxShapeFactory.container(
      id: page.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    value.updateCurrentPage((page) => page.addShape(host));
    final childId = value.currentPage!.nextFreeShapeId();
    final child = VsdxShapeFactory.rectangle(
      id: childId,
      pinX: 4,
      pinY: 3.5,
      width: 1,
      height: 0.8,
    );
    value.updateCurrentPage(
      (page) => page.addShape(child).reparentShape(childId, host.id),
    );
    value.addShapeFromBuilderAt(
      (id, x, y) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: x,
        pinY: y,
        width: 1,
        height: 1,
      ),
      8,
      4,
    );
    final otherId = value.singleSelectedId!;
    value.createConnector(
      4,
      3.5,
      8,
      4,
      beginTarget: childId,
      endTarget: otherId,
    );
    final connectorId =
        value.currentPage!.shapes.lastWhere((shape) => shape.is1D).id;
    value.setSelection(<int>[host.id]);

    value.collapseSelection();
    expect(value.currentPage!.findShapeById(host.id)!.collapsed, isTrue);
    expect(
      value.currentPage!.connects
          .where((connect) => connect.fromSheetId == connectorId)
          .any((connect) => connect.toSheetId == childId),
      isFalse,
    );

    value.setSelectionCollapsible(false);
    final restored = value.currentPage!.findShapeById(host.id)!;
    expect(restored.collapsible, isFalse);
    expect(restored.collapsed, isFalse);
    expect(restored.height, closeTo(3, 1e-9));
    expect(value.canCollapseSelection, isFalse);
    expect(
      value.currentPage!.connects
          .where((connect) => connect.fromSheetId == connectorId)
          .any((connect) => connect.toSheetId == childId),
      isTrue,
    );

    value.undo();
    final folded = value.currentPage!.findShapeById(host.id)!;
    expect(folded.collapsible, isTrue);
    expect(folded.collapsed, isTrue);
  });

  test('ordinary vertex can opt into folding and round-trips', () {
    final value = controller();
    value.addShapeFromBuilderAt(
      (id, x, y) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: x,
        pinY: y,
        width: 2,
        height: 1,
      ),
      4,
      4,
    );
    final id = value.singleSelectedId!;
    expect(value.selectionCollapsible, isFalse);

    value.toggleSelectionCollapsible();
    expect(value.selectionCollapsible, isTrue);
    expect(value.canCollapseSelection, isTrue);
    final reopened =
        const DocumentParser().parse(value.exportToBytes()).pages.single;
    expect(reopened.findShapeById(id)!.shapeKind, VsdxShapeKind.normal);
    expect(reopened.findShapeById(id)!.collapsible, isTrue);

    value.collapseSelection();
    expect(value.currentPage!.findShapeById(id)!.collapsed, isTrue);
  });

  test('an imported disabled-but-collapsed host can still expand', () {
    final host = VsdxShapeFactory.container(
      id: 1,
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    ).fold().withCollapsible(false);
    final page = VsdxPage(
      id: 1,
      name: 'Page-1',
      widthInches: 10,
      heightInches: 10,
      shapes: <VsdxShape>[host],
    );

    final expanded = page.setCollapsed(host.id, false).findShapeById(host.id)!;
    expect(expanded.collapsible, isFalse);
    expect(expanded.collapsed, isFalse);
    expect(expanded.height, closeTo(3, 1e-9));
  });
}
