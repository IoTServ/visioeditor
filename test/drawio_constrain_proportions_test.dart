import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  EditorController controller() {
    final value = EditorController()..newDocument();
    addTearDown(value.dispose);
    return value;
  }

  int rectangle(EditorController value, double x, double y) {
    value.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 2,
        height: 1,
      ),
      x,
      y,
    );
    return value.singleSelectedId!;
  }

  int line(EditorController value, double y) {
    value
      ..setTool(EditorTool.line)
      ..createShapeByDrag(1, y, 4, y);
    return value.singleSelectedId!;
  }

  test(
    'Constrain Proportions preserves metadata and survives VSDX round-trip',
    () {
      final value = controller();
      final id = rectangle(value, 2, 5);
      value.updateCurrentPage(
        (page) => page.updateShapeById(
          id,
          (shape) => shape.copyWith(
            userCells: const <VsdxUserCell>[
              VsdxUserCell(name: 'foreignMeta', value: 'keep'),
            ],
          ),
        ),
      );

      expect(value.selectedConstrainProportions, isFalse);
      value.setConstrainProportions(true);
      final changed = value.currentPage!.findShapeById(id)!;
      expect(changed.constrainProportions, isTrue);
      expect(
        changed.userCells
            .firstWhere((cell) => cell.name == 'foreignMeta')
            .value,
        'keep',
      );
      value.undo();
      expect(
        value.currentPage!.findShapeById(id)!.constrainProportions,
        isFalse,
      );
      value.redo();

      final reopened = const DocumentParser()
          .parse(value.exportToBytes())
          .pages
          .single
          .findShapeById(id)!;
      expect(reopened.constrainProportions, isTrue);
      expect(
        reopened.userCells
            .firstWhere((cell) => cell.name == 'foreignMeta')
            .value,
        'keep',
      );
    },
  );

  test('numeric width and height edits preserve ratio and top-left anchor', () {
    final value = controller();
    final id = rectangle(value, 3, 5);
    value.setConstrainProportions(true);
    final page = value.currentPage!;
    final before = page.shapePageAabb(id)!;

    value.setSelectedWidth(4);
    var shape = value.currentPage!.findShapeById(id)!;
    var bounds = value.currentPage!.shapePageAabb(id)!;
    expect(shape.width, closeTo(4, 1e-9));
    expect(shape.height, closeTo(2, 1e-9));
    expect(bounds.left, closeTo(before.left, 1e-9));
    expect(bounds.top, closeTo(before.top, 1e-9));

    value.undo();
    shape = value.currentPage!.findShapeById(id)!;
    expect(shape.width, closeTo(2, 1e-9));
    expect(shape.height, closeTo(1, 1e-9));
    expect(shape.constrainProportions, isTrue);

    value.setSelectedHeight(3);
    shape = value.currentPage!.findShapeById(id)!;
    bounds = value.currentPage!.shapePageAabb(id)!;
    expect(shape.width, closeTo(6, 1e-9));
    expect(shape.height, closeTo(3, 1e-9));
    expect(bounds.left, closeTo(before.left, 1e-9));
    expect(bounds.top, closeTo(before.top, 1e-9));
  });

  test('controller ignores connectors and locked vertices', () {
    final value = controller();
    final vertex = rectangle(value, 2, 5);
    final edge = line(value, 3);

    value.setSelection([edge]);
    expect(value.canSetConstrainProportions, isFalse);
    value.setConstrainProportions(true);
    expect(
      value.currentPage!.findShapeById(edge)!.constrainProportions,
      isFalse,
    );

    value.updateCurrentPage(
      (page) =>
          page.updateShapeById(vertex, (shape) => shape.copyWith(locked: true)),
    );
    value.setSelection([vertex]);
    expect(value.canSetConstrainProportions, isFalse);
    value.setConstrainProportions(true);
    expect(
      value.currentPage!.findShapeById(vertex)!.constrainProportions,
      isFalse,
    );
  });

  test('default and copied vertex styles carry Constrain Proportions', () {
    final value = controller();
    final source = rectangle(value, 2, 5);
    value
      ..setConstrainProportions(true)
      ..setSelectionAsDefaultStyle();

    final inherited = rectangle(value, 5, 5);
    expect(
      value.currentPage!.findShapeById(inherited)!.constrainProportions,
      isTrue,
    );

    value
      ..clearDefaultStyle()
      ..setSelection([source])
      ..copyStyle();
    final target = rectangle(value, 8, 5);
    expect(
      value.currentPage!.findShapeById(target)!.constrainProportions,
      isFalse,
    );
    value.pasteStyle();
    expect(
      value.currentPage!.findShapeById(target)!.constrainProportions,
      isTrue,
    );
  });
}
