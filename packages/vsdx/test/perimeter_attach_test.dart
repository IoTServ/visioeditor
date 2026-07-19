import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  group('ShapePerimeter', () {
    test('diamond outline attach hits a diamond edge, not the AABB', () {
      // Diamond inscribed in 2×2 box centred at origin of local coords:
      // vertices (1,2), (2,1), (1,0), (0,1) — mid-side of AABB is NOT on the
      // diamond; horizontal ray from centre should hit x=0 or x=2 at y=1.
      final diamond = VsdxShapeFactory.polygon(
        id: 1,
        pinX: 5,
        pinY: 5,
        width: 2,
        height: 2,
        unit: const <Offset2D>[
          Offset2D(0.5, 1),
          Offset2D(1, 0.5),
          Offset2D(0.5, 0),
          Offset2D(0, 0.5),
        ],
      );
      final page = VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 10,
        heightInches: 10,
        shapes: <VsdxShape>[diamond],
      );

      // Aim right → right diamond tip at (6, 5), not AABB right mid (6, 5)
      // wait: pin (5,5), tip at local (2,1) → page (6,5). AABB right mid is
      // also (6,5). Aim diagonally up-right toward (8,8):
      // AABB would hit top or right of box; diamond hits a slanted edge.
      final hit = page.perimeterAttach(1, 8, 8);
      // Line from (5,5) toward (8,8) is y-5 = x-5. Diamond edges:
      // top-right: (1,2)-(2,1) → local line x+y=3 → page (x-4)+(y-4)=3 →
      // x+y=11. Intersect with y=x: 2x=11 → x=5.5, y=5.5.
      expect(hit.x, closeTo(5.5, 1e-6));
      expect(hit.y, closeTo(5.5, 1e-6));
      // AABB attach would be at t=min(1/3,1/3)*3 = 1 → (6,6).
      expect(hit.x, isNot(closeTo(6.0, 1e-3)));
    });

    test('ellipse attach lands on the oval, not the bounding box corner ray', () {
      final oval = VsdxShapeFactory.ellipse(
        id: 1,
        pinX: 4,
        pinY: 4,
        width: 4,
        height: 2,
      );
      final page = VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 10,
        heightInches: 10,
        shapes: <VsdxShape>[oval],
      );

      // Horizontal: right tip of ellipse at x = 6.
      final right = page.perimeterAttach(1, 10, 4);
      expect(right.x, closeTo(6.0, 1e-6));
      expect(right.y, closeTo(4.0, 1e-6));

      // 45°-ish aim toward (10, 7): direction (6, 3) from pin.
      // Unit-circle solve yields t = √2/6 → page (4+√2, 4+√2/2).
      final diag = page.perimeterAttach(1, 10, 7);
      final s2 = math.sqrt(2);
      expect(diag.x, closeTo(4 + s2, 1e-5));
      expect(diag.y, closeTo(4 + s2 / 2, 1e-5));
      // AABB would hit at (6, 5) along the same aim — farther out.
      expect(diag.x, lessThan(6.0 - 1e-3));
      expect(diag.y, lessThan(5.0 - 1e-3));
    });

    test('rerouteConnectors uses geometry perimeter for whole-shape glue', () {
      final diamond = VsdxShapeFactory.polygon(
        id: 1,
        pinX: 3,
        pinY: 3,
        width: 2,
        height: 2,
        unit: const <Offset2D>[
          Offset2D(0.5, 1),
          Offset2D(1, 0.5),
          Offset2D(0.5, 0),
          Offset2D(0, 0.5),
        ],
      );
      final other = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 8,
        pinY: 8,
        width: 1,
        height: 1,
      );
      final conn = VsdxShapeFactory.line(id: 3, ax: 3, ay: 3, bx: 8, by: 8);
      final page = VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 12,
        heightInches: 12,
        shapes: <VsdxShape>[diamond, other, conn],
        connects: const <VsdxConnect>[
          VsdxConnect(
            fromSheetId: 3,
            fromCell: 'BeginX',
            fromPart: 9,
            toSheetId: 1,
            toCell: 'PinX',
            toPart: 3,
          ),
          VsdxConnect(
            fromSheetId: 3,
            fromCell: 'EndX',
            fromPart: 12,
            toSheetId: 2,
            toCell: 'PinX',
            toPart: 3,
          ),
        ],
      ).rerouteConnectors();

      final c = page.findShapeById(3)!;
      // Begin on diamond slanted edge at (3.5, 3.5), not AABB (4,4).
      expect(c.beginX, closeTo(3.5, 1e-6));
      expect(c.beginY, closeTo(3.5, 1e-6));
    });

    test('rerouteConnectors approaches oval top with a vertical last segment', () {
      // Source above target oval: without jetty, H-first ends with a horizontal
      // stub along the oval's top — arrow slides parallel to the edge.
      final source = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 4,
        pinY: 8,
        width: 1.5,
        height: 1,
      );
      final oval = VsdxShapeFactory.ellipse(
        id: 2,
        pinX: 4,
        pinY: 3,
        width: 3,
        height: 2,
      );
      final conn = VsdxShapeFactory.line(id: 3, ax: 4, ay: 8, bx: 4, by: 3);
      final page = VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 10,
        heightInches: 10,
        shapes: <VsdxShape>[source, oval, conn],
        connects: const <VsdxConnect>[
          VsdxConnect(
            fromSheetId: 3,
            fromCell: 'BeginX',
            fromPart: 9,
            toSheetId: 1,
            toCell: 'PinX',
            toPart: 3,
          ),
          VsdxConnect(
            fromSheetId: 3,
            fromCell: 'EndX',
            fromPart: 12,
            toSheetId: 2,
            toCell: 'PinX',
            toPart: 3,
          ),
        ],
      ).rerouteConnectors();

      final route = VsdxPage.connectorRoute(page.findShapeById(3)!);
      expect(route.length, greaterThanOrEqualTo(2));
      final tip = route.last;
      final prev = route[route.length - 2];
      // Attach on oval top → last segment vertical (same X, prev above tip).
      expect(prev.x, closeTo(tip.x, 1e-6));
      expect(prev.y, greaterThan(tip.y + 1e-3));
      // Tip should sit on the oval top, not float at the pin.
      expect(tip.y, closeTo(4.0, 0.05));
    });
  });
}
