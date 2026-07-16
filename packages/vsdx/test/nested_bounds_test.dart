import 'dart:io';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  group('nested Group child page bounds', () {
    late VsdxPage page;

    setUpAll(() {
      final bytes = File('test/fixtures/数据治理.vsdx').readAsBytesSync();
      page = const DocumentParser().parse(bytes).pages.first;
    });

    test('shapePageAabb maps group fill children to page coords', () {
      // Group 128 (数据应用/运营外框) at page pin ≈ (8.17, 3.66);
      // child 129 stores Pin in parent-local inches ≈ (0.66, 0.84).
      final child = page.findShapeById(129)!;
      expect(child.pinX, lessThan(2));
      expect(child.pinY, lessThan(2));

      final aabb = page.shapePageAabb(129)!;
      expect(aabb.left, closeTo(7.508, 0.02));
      expect(aabb.right, closeTo(8.837, 0.02));
      expect(aabb.bottom, closeTo(2.816, 0.02));
      expect(aabb.top, closeTo(4.505, 0.02));

      // Pin in page space matches the group centre.
      final pin = page.shapePinPage(129);
      expect(pin.x, closeTo(8.173, 0.02));
      expect(pin.y, closeTo(3.660, 0.02));
    });

    test('left-column frame group 125/126 has the same nesting pattern', () {
      final child = page.findShapeById(126)!;
      expect(child.pinX, lessThan(2));
      final aabb = page.shapePageAabb(126)!;
      expect(aabb.left, closeTo(1.591, 0.02));
      expect(aabb.right, closeTo(2.920, 0.02));
      // Must not sit near the page origin (the old broken selection location).
      expect(aabb.left, greaterThan(1.0));
      expect(aabb.bottom, greaterThan(1.0));
    });

    test('pageToLocalDeep round-trips through a nested child', () {
      const local = Offset2D(0.3, 0.5);
      final pagePt = page.localToPageDeep(129, local);
      final back = page.pageToLocalDeep(129, pagePt);
      expect(back.x, closeTo(local.x, 1e-9));
      expect(back.y, closeTo(local.y, 1e-9));
    });

    test('localToPage honours non-centre LocPin', () {
      final s = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 5,
        pinY: 4,
        width: 2,
        height: 2,
      ).copyWith(locPinXInches: 0, locPinYInches: 0);
      // Local origin maps to pin when LocPin is (0,0).
      final origin = VsdxPage.localToPage(s, const Offset2D(0, 0));
      expect(origin.x, closeTo(5, 1e-9));
      expect(origin.y, closeTo(4, 1e-9));
      // Local centre is offset from pin by (w/2, h/2).
      final mid = VsdxPage.localToPage(s, const Offset2D(1, 1));
      expect(mid.x, closeTo(6, 1e-9));
      expect(mid.y, closeTo(5, 1e-9));
    });
  });
}
