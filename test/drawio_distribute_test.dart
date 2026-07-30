import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  EditorController controller() {
    final value = EditorController()
      ..newDocument(widthInches: 12, heightInches: 9);
    addTearDown(value.dispose);
    return value;
  }

  int rectangle(
    EditorController controller,
    double x,
    double y, {
    double width = 1,
    double height = 1,
  }) {
    controller.addShapeFromBuilderAt(
      (id, _, _) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: x,
        pinY: y,
        width: width,
        height: height,
      ),
      0,
      0,
    );
    return controller.singleSelectedId!;
  }

  test('primary horizontal distribute equalises centres like draw.io', () {
    final value = controller();
    final left = rectangle(value, 1, 4, width: 1);
    final middle = rectangle(value, 3, 4, width: 2);
    final right = rectangle(value, 8, 4, width: 3);
    value.setSelection(<int>[right, middle, left]);

    value.distributeHorizontally();

    expect(value.currentPage!.shapePinPage(left).x, closeTo(1, 1e-9));
    expect(value.currentPage!.shapePinPage(middle).x, closeTo(4.5, 1e-9));
    expect(value.currentPage!.shapePinPage(right).x, closeTo(8, 1e-9));
    value.undo();
    expect(value.currentPage!.shapePinPage(middle).x, closeTo(3, 1e-9));
  });

  test('horizontal spacing distribute equalises visible gaps', () {
    final value = controller();
    final left = rectangle(value, 1, 4, width: 1);
    final middle = rectangle(value, 3, 4, width: 2);
    final right = rectangle(value, 8, 4, width: 3);
    value.setSelection(<int>[left, middle, right]);

    value.distributeHorizontalSpacing();

    final a = value.currentPage!.shapePageAabb(left)!;
    final b = value.currentPage!.shapePageAabb(middle)!;
    final c = value.currentPage!.shapePageAabb(right)!;
    expect(b.left - a.right, closeTo(c.left - b.right, 1e-9));
    expect(value.currentPage!.shapePinPage(middle).x, closeTo(4, 1e-9));
  });

  test('vertical distribute and spacing remain distinct for unequal heights',
      () {
    final value = controller();
    final bottom = rectangle(value, 5, 1, height: 1);
    final middle = rectangle(value, 5, 3, height: 2);
    final top = rectangle(value, 5, 8, height: 3);
    value.setSelection(<int>[bottom, middle, top]);

    value.distributeVertically();
    expect(value.currentPage!.shapePinPage(middle).y, closeTo(4.5, 1e-9));
    value.undo();
    value.distributeVerticalSpacing();
    expect(value.currentPage!.shapePinPage(middle).y, closeTo(4, 1e-9));
  });

  test('distribution availability ignores connector-only count', () {
    final value = controller();
    final first = rectangle(value, 1, 4);
    final second = rectangle(value, 4, 4);
    value.createConnector(1, 4, 4, 4);
    final connector =
        value.currentPage!.shapes.lastWhere((shape) => shape.is1D).id;
    value.setSelection(<int>[first, connector, second]);
    expect(value.canDistributeSelection, isFalse);

    final third = rectangle(value, 7, 4);
    value.setSelection(<int>[first, connector, second, third]);
    expect(value.canDistributeSelection, isTrue);
  });
}
