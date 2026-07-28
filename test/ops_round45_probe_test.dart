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

  VsdxShape rectangle(int id, double x, double y) =>
      VsdxShapeFactory.rectangle(
        id: id,
        pinX: x,
        pinY: y,
        width: 1.5,
        height: 1,
      );

  test('palette insertion can ignore the remembered default style', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(rectangle, 5, 5);
    e.setFillColor(const VsdxColor(0xFFE53935));

    e.addShapeFromBuilderAt(
      rectangle,
      7,
      5,
      inheritStyle: false,
    );

    expect(
      e.singleSelected!.fill.foreground,
      VsdxColor.white,
    );
    e.addShapeFromBuilderAt(rectangle, 9, 5);
    expect(
      e.singleSelected!.fill.foreground,
      const VsdxColor(0xFFE53935),
    );
  });

  test('bottom-left palette insertion is below and left-aligned to drawing', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(rectangle, 5, 5);
    final existing = e.singleSelectedId!;
    final before = e.currentPage!.shapePageAabb(existing)!;

    e.addShapeFromBuilderBottomLeft(rectangle);

    final inserted = e.currentPage!.shapePageAabb(e.singleSelectedId!)!;
    expect(inserted.left, closeTo(before.left, 0.11));
    expect(inserted.bottom, lessThan(before.bottom));
  });

  test('palette quick-add inserts and glues beside selected shape', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(rectangle, 4, 4);
    final source = e.singleSelectedId!;

    expect(e.canQuickAddSelection, isTrue);
    e.quickAddSelectionWithBuilder(rectangle);

    final target = e.singleSelectedId!;
    expect(target, isNot(source));
    expect(e.currentPage!.shapes.where((shape) => shape.is1D), hasLength(1));
    expect(
      e.currentPage!.connects.map((row) => row.toSheetId).toSet(),
      equals(<int>{source, target}),
    );
    expect(
      e.currentPage!.shapePageAabb(target)!.left,
      greaterThan(e.currentPage!.shapePageAabb(source)!.right),
    );
  });

  test('palette insertion can overlay instead of entering a container', () {
    final e = ctrl();
    final container = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 5,
      pinY: 4,
      width: 5,
      height: 4,
    );
    e.updateCurrentPage((page) => page.addShape(container));

    e.addShapeFromBuilderAt(
      rectangle,
      5,
      4,
      allowContainment: false,
    );
    final overlay = e.singleSelectedId!;
    expect(
      e.currentPage!.shapes.map((shape) => shape.id),
      contains(overlay),
    );
    expect(
      e.currentPage!.findShapeById(container.id)!.children,
      isEmpty,
    );

    e.addShapeFromBuilderAt(rectangle, 5, 4);
    final contained = e.singleSelectedId!;
    expect(
      e.currentPage!.findShapeById(container.id)!.children
          .map((shape) => shape.id),
      contains(contained),
    );
  });
}
