import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  VsdxPage pageWith(List<VsdxShape> shapes) => VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 10,
        heightInches: 10,
        shapes: shapes,
      );

  group('pageToLocal / localToPage', () {
    test('round-trips an axis-aligned parent', () {
      final parent = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 4,
        pinY: 3,
        width: 2,
        height: 2,
      );
      const page = Offset2D(4.5, 3.25);
      final local = VsdxPage.pageToLocal(parent, page);
      final back = VsdxPage.localToPage(parent, local);
      expect(back.x, closeTo(page.x, 1e-9));
      expect(back.y, closeTo(page.y, 1e-9));
    });
  });

  group('reparentShape', () {
    test('drops a top-level shape into a container and preserves page pin', () {
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
      expect(box.shapeKind, VsdxShapeKind.container);

      var page = pageWith(<VsdxShape>[box, child]);
      expect(page.findParentId(2), isNull);

      page = page.reparentShape(2, 1);
      expect(page.findParentId(2), 1);
      expect(page.shapes.where((s) => s.id == 2), isEmpty);
      final parent = page.findShapeById(1)!;
      expect(parent.children, hasLength(1));
      final nested = parent.children.single;
      expect(nested.id, 2);
      // On-page pin unchanged.
      final pagePin = VsdxPage.localToPage(parent, Offset2D(nested.pinX, nested.pinY));
      expect(pagePin.x, closeTo(4, 1e-6));
      expect(pagePin.y, closeTo(3.5, 1e-6));
    });

    test('ejects a child back to the top level', () {
      final box = VsdxShapeFactory.container(
        id: 1,
        pinX: 4,
        pinY: 4,
        width: 4,
        height: 3,
      );
      final child = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 4.2,
        pinY: 3.8,
        width: 1,
        height: 0.8,
      );
      var page = pageWith(<VsdxShape>[box, child]).reparentShape(2, 1);
      page = page.reparentShape(2, null);
      expect(page.findParentId(2), isNull);
      final top = page.findShapeById(2)!;
      expect(top.pinX, closeTo(4.2, 1e-6));
      expect(top.pinY, closeTo(3.8, 1e-6));
      expect(page.findShapeById(1)!.children, isEmpty);
    });

    test('refuses to nest a shape under its own descendant', () {
      final outer = VsdxShapeFactory.container(
        id: 1,
        pinX: 4,
        pinY: 4,
        width: 5,
        height: 4,
      );
      final inner = VsdxShapeFactory.container(
        id: 2,
        pinX: 4,
        pinY: 4,
        width: 2,
        height: 2,
      );
      var page = pageWith(<VsdxShape>[outer, inner]).reparentShape(2, 1);
      final before = page;
      page = page.reparentShape(1, 2); // would create a cycle
      expect(identical(page, before) || page.findParentId(1) == null, isTrue);
      expect(page.findParentId(2), 1);
    });
  });

  group('findDropContainerAt', () {
    test('returns the container under the point', () {
      final box = VsdxShapeFactory.container(
        id: 1,
        pinX: 4,
        pinY: 4,
        width: 4,
        height: 3,
      );
      final other = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 8,
        pinY: 8,
        width: 1,
        height: 1,
      );
      final page = pageWith(<VsdxShape>[box, other]);
      expect(page.findDropContainerAt(4, 4, excludeIds: {2}), 1);
      expect(page.findDropContainerAt(8, 8, excludeIds: {2}), isNull);
    });

    test('excludes the dragged shape and its ancestors', () {
      final box = VsdxShapeFactory.container(
        id: 1,
        pinX: 4,
        pinY: 4,
        width: 4,
        height: 3,
      );
      final page = pageWith(<VsdxShape>[box]);
      expect(page.findDropContainerAt(4, 4, excludeIds: {1}), isNull);
    });
  });

  group('translateShape dontMoveChildren', () {
    test('keeps child page position when parent moves', () {
      final child = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 1,
        pinY: 1,
        width: 1,
        height: 1,
      );
      final parent = VsdxShapeFactory.container(
        id: 1,
        pinX: 3,
        pinY: 3,
        width: 4,
        height: 4,
      ).copyWith(
        dontMoveChildren: true,
        children: <VsdxShape>[child],
      );
      final pagePinBefore =
          VsdxPage.localToPage(parent, Offset2D(child.pinX, child.pinY));
      final moved = VsdxPage.translateShape(parent, 2, 1);
      expect(moved.pinX, closeTo(5, 1e-9));
      expect(moved.pinY, closeTo(4, 1e-9));
      final pagePinAfter = VsdxPage.localToPage(
        moved,
        Offset2D(moved.children.single.pinX, moved.children.single.pinY),
      );
      expect(pagePinAfter.x, closeTo(pagePinBefore.x, 1e-6));
      expect(pagePinAfter.y, closeTo(pagePinBefore.y, 1e-6));
    });

    test('moves children with the parent by default', () {
      final child = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 1,
        pinY: 1,
        width: 1,
        height: 1,
      );
      final parent = VsdxShapeFactory.container(
        id: 1,
        pinX: 3,
        pinY: 3,
        width: 4,
        height: 4,
      ).copyWith(children: <VsdxShape>[child]);
      final pagePinBefore =
          VsdxPage.localToPage(parent, Offset2D(child.pinX, child.pinY));
      final moved = VsdxPage.translateShape(parent, 2, 1);
      final pagePinAfter = VsdxPage.localToPage(
        moved,
        Offset2D(moved.children.single.pinX, moved.children.single.pinY),
      );
      expect(pagePinAfter.x, closeTo(pagePinBefore.x + 2, 1e-6));
      expect(pagePinAfter.y, closeTo(pagePinBefore.y + 1, 1e-6));
    });
  });
}
