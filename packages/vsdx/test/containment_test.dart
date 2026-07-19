import 'dart:math' as math;

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

    test('reparent 1D into rotated group keeps Angle 0 and page endpoints', () {
      final group = VsdxShape(
        id: 1,
        name: 'Group.1',
        pinX: 4,
        pinY: 4,
        width: 4,
        height: 3,
        angleRad: math.pi / 2,
        shapeKind: VsdxShapeKind.group,
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
      );
      final a = VsdxShapeFactory.rectangle(
          id: 2, pinX: 2, pinY: 5, width: 1, height: 1);
      final b = VsdxShapeFactory.rectangle(
          id: 3, pinX: 6, pinY: 5, width: 1, height: 1);
      final conn = VsdxShapeFactory.line(id: 4, ax: 2.5, ay: 5, bx: 5.5, by: 5);
      var page = pageWith(<VsdxShape>[group, a, b, conn]).copyWith(
        connects: const [
          VsdxConnect(
              fromSheetId: 4, fromCell: 'BeginX', toSheetId: 2, toCell: 'PinX'),
          VsdxConnect(
              fromSheetId: 4, fromCell: 'EndX', toSheetId: 3, toCell: 'PinX'),
        ],
      ).rerouteConnectors();
      final beforeBegin = page.findShapeById(4)!.beginX!;
      final beforeEnd = page.findShapeById(4)!.endX!;
      page = page.reparentShape(4, 1).rerouteConnectors(movedShapeIds: {4, 2, 3});
      final nested = page.findShapeById(4)!;
      expect(nested.angleRad, 0);
      expect(nested.flipX, isFalse);
      // Page-space begin/end stay on the glue targets (not double-rotated).
      final pageBegin = page.localToPageDeep(4, Offset2D(0, 0));
      // Begin is at local (0,0) after reshape; map via shape pin frame:
      final beginPage = Offset2D(nested.beginX!, nested.beginY!);
      final parent = page.findShapeById(1)!;
      final beginOnPage = VsdxPage.localToPage(parent, beginPage);
      expect(beginOnPage.x, closeTo(beforeBegin, 0.6));
      final endOnPage =
          VsdxPage.localToPage(parent, Offset2D(nested.endX!, nested.endY!));
      expect(endOnPage.x, closeTo(beforeEnd, 0.6));
      expect(pageBegin.x, isNot(equals(double.nan)));
    });

    test('ungroup rotated group finalizes nested 1D Angle to 0', () {
      final conn = VsdxShapeFactory.line(id: 2, ax: 1, ay: 1.5, bx: 3, by: 1.5);
      final group = VsdxShape(
        id: 1,
        name: 'Group.1',
        pinX: 3,
        pinY: 3,
        width: 4,
        height: 3,
        angleRad: math.pi / 2,
        shapeKind: VsdxShapeKind.group,
        children: <VsdxShape>[conn],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
      );
      var page = pageWith(<VsdxShape>[group]);
      page = page.ungroup(1);
      final top = page.findShapeById(2)!;
      expect(page.findParentId(2), isNull);
      expect(top.angleRad, 0);
      expect(top.is1D, isTrue);
      expect(top.beginX, isNotNull);
      expect(top.endX, isNotNull);
    });
  });

  group('group AABB', () {
    test('group frame includes elbow bend outside Begin→End box', () {
      final box = VsdxShapeFactory.rectangle(
          id: 1, pinX: 1, pinY: 3, width: 1, height: 1);
      // Elbow: (2,3) → (4,3) → (4,5) → (6,5) — bend above the W×H box.
      final conn = VsdxShapeFactory.line(id: 2, ax: 2, ay: 3, bx: 6, by: 5)
          .copyWith(waypoints: const [Offset2D(4, 3), Offset2D(4, 5)])
          .reshapeAsPolyline(const [
        Offset2D(2, 3),
        Offset2D(4, 3),
        Offset2D(4, 5),
        Offset2D(6, 5),
      ]);
      var page = pageWith(<VsdxShape>[box, conn]);
      page = page.group({1, 2}, groupId: 10);
      final g = page.findShapeById(10)!;
      expect(g.height, greaterThan(2.0));
      final aabb = page.shapePageAabb(2)!;
      expect(aabb.top, closeTo(5, 1e-6));
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
