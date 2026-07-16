import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/render/vsdx_painter.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  group('VsdxShape.collapsed', () {
    test('withCollapsed round-trips via User.veCollapsed', () {
      final box = VsdxShapeFactory.container(
        id: 1,
        pinX: 4,
        pinY: 4,
        width: 4,
        height: 3,
      );
      expect(box.collapsed, isFalse);
      final folded = box.withCollapsed(true);
      expect(folded.collapsed, isTrue);
      expect(
        folded.userCells.any((c) => c.name == VsdxShape.userCollapsed),
        isTrue,
      );
      expect(folded.withCollapsed(false).collapsed, isFalse);
    });

    test('fold shrinks height to the header and unfold restores it', () {
      final box = VsdxShapeFactory.container(
        id: 1,
        pinX: 4,
        pinY: 4,
        width: 4,
        height: 3,
      );
      final topBefore = box.pinY + box.height / 2;
      final folded = box.fold();
      expect(folded.collapsed, isTrue);
      expect(folded.height, lessThan(box.height));
      expect(folded.storedExpandedHeight, closeTo(3, 1e-6));
      // Top edge stays put (Y-up).
      expect(folded.pinY + folded.height / 2, closeTo(topBefore, 1e-6));

      final opened = folded.unfold();
      expect(opened.collapsed, isFalse);
      expect(opened.height, closeTo(3, 1e-6));
      expect(opened.pinY + opened.height / 2, closeTo(topBefore, 1e-6));
      expect(opened.storedExpandedHeight, isNull);
    });
  });

  group('draw order / hit tree', () {
    test('collapsed container omits children from the visible draw order', () {
      final box = VsdxShapeFactory.container(
        id: 1,
        pinX: 4,
        pinY: 4,
        width: 4,
        height: 3,
      );
      final child = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 4,
        pinY: 3.5,
        width: 1,
        height: 0.8,
      );
      var page = VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 10,
        heightInches: 10,
        shapes: <VsdxShape>[box, child],
      ).reparentShape(2, 1);
      expect(page.findShapeById(1)!.children, hasLength(1));

      // Mimic page_canvas._drawOrder
      List<int> order(VsdxPage p) {
        final out = <int>[];
        void walk(VsdxShape s) {
          out.add(s.id);
          if (s.collapsed) return;
          for (final c in s.children) {
            walk(c);
          }
        }

        for (final s in p.shapes) {
          walk(s);
        }
        return out;
      }

      expect(order(page), containsAll(<int>[1, 2]));
      page = page.updateShapeById(1, (s) => s.withCollapsed(true));
      expect(order(page), <int>[1]);
      expect(order(page), isNot(contains(2)));
    });
  });

  test('toggleCollapsed hides children from selection and undoes', () {
    final c = EditorController()..newDocument();
    final page0 = c.currentPage!;
    final box = VsdxShapeFactory.container(
      id: page0.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    c.updateCurrentPage((p) => p.addShape(box));
    final childId = c.currentPage!.nextFreeShapeId();
    final child = VsdxShapeFactory.rectangle(
      id: childId,
      pinX: 4,
      pinY: 3.5,
      width: 1,
      height: 0.8,
    );
    c.updateCurrentPage((p) => p.addShape(child).reparentShape(childId, box.id));
    c.selectOnly(childId);
    expect(c.selection, <int>{childId});

    c.toggleCollapsed(box.id);
    expect(c.isCollapsed(box.id), isTrue);
    expect(c.selection.contains(childId), isFalse);
    expect(c.currentPage!.findShapeById(box.id)!.children, hasLength(1));
    expect(c.currentPage!.findShapeById(box.id)!.height, lessThan(3));

    c.undo();
    expect(c.isCollapsed(box.id), isFalse);
    expect(c.currentPage!.findShapeById(box.id)!.height, closeTo(3, 1e-3));
  });

  test('collapse chevron local centre sits in the header band', () {
    final box = VsdxShapeFactory.container(
      id: 1,
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    final c = VsdxPainter.collapseChevronLocalCenter(box);
    expect(c.dy, greaterThan(box.height * 0.8)); // near the top (Y-up)
    expect(c.dx, lessThan(box.width * 0.2));
  });

  test('plain groups are not foldable; containers are', () {
    expect(VsdxShapeKind.group.isFoldable, isFalse);
    expect(VsdxShapeKind.normal.isFoldable, isFalse);
    expect(VsdxShapeKind.container.isFoldable, isTrue);
    expect(VsdxShapeKind.swimlane.isFoldable, isTrue);
  });
}
