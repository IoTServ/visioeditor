import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  const router = ObstacleRouter();

  group('ObstacleRouter', () {
    test('uses a simple elbow when the path is clear', () {
      final route = router.route(
        0,
        0,
        4,
        2,
        obstacles: const <RouteAabb>[],
      );
      expect(route.first, const Offset2D(0, 0));
      expect(route.last, const Offset2D(4, 2));
      // Horizontal-first elbow: mid X bend.
      expect(route, hasLength(4));
      expect(route[1].x, closeTo(2, 1e-9));
      expect(route[1].y, closeTo(0, 1e-9));
    });

    test('skirts around a blocking rectangle between endpoints', () {
      // Start left, end right; a tall obstacle sits in the middle so the
      // classic mid-X elbow would cut through it.
      const wall = RouteAabb(1.5, -1, 2.5, 3);
      final route = router.route(
        0,
        1,
        4,
        1,
        obstacles: const <RouteAabb>[wall],
      );
      expect(route.first, const Offset2D(0, 1));
      expect(route.last, const Offset2D(4, 1));
      // No segment may enter the obstacle interior.
      for (var i = 0; i < route.length - 1; i++) {
        expect(
          wall.blocksSegment(
            route[i].x,
            route[i].y,
            route[i + 1].x,
            route[i + 1].y,
          ),
          isFalse,
          reason: 'segment ${route[i]}→${route[i + 1]} crosses obstacle',
        );
      }
      // Must bend (more than a straight line).
      expect(route.length, greaterThan(2));
    });

    test('prefers clear vertical-first when horizontal-first is blocked', () {
      // Horizontal mid segment would hit the wall; vertical-first clears it.
      const wall = RouteAabb(1.2, 0.4, 2.8, 1.6);
      final route = router.route(
        0,
        1,
        4,
        1,
        obstacles: const <RouteAabb>[wall],
      );
      for (var i = 0; i < route.length - 1; i++) {
        expect(
          wall.blocksSegment(
            route[i].x,
            route[i].y,
            route[i + 1].x,
            route[i + 1].y,
          ),
          isFalse,
        );
      }
    });

    test('endSide north forces a vertical last segment (jetty)', () {
      // Without a jetty, H-first would end with a horizontal stub along y=by.
      final route = router.route(
        0,
        3,
        2,
        1,
        obstacles: const <RouteAabb>[],
        endSide: RouteSide.north,
      );
      expect(route.length, greaterThanOrEqualTo(2));
      final tip = route.last;
      final prev = route[route.length - 2];
      expect(tip, const Offset2D(2, 1));
      // Last segment must be vertical into the north edge.
      expect(prev.x, closeTo(tip.x, 1e-9));
      expect(prev.y, greaterThan(tip.y));
    });

    test('beginSide east forces a horizontal first segment (jetty)', () {
      final route = router.route(
        1,
        1,
        4,
        3,
        obstacles: const <RouteAabb>[],
        beginSide: RouteSide.east,
      );
      final a = route.first;
      final next = route[1];
      expect(a, const Offset2D(1, 1));
      expect(next.y, closeTo(a.y, 1e-9));
      expect(next.x, greaterThan(a.x));
    });
  });

  group('VsdxPage.rerouteConnectors obstacle avoidance', () {
    test('glued connector avoids a shape sitting between its ends', () {
      final left = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 1,
        pinY: 3,
        width: 1,
        height: 1,
      );
      final right = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 7,
        pinY: 3,
        width: 1,
        height: 1,
      );
      // Blocker centred between left and right on the direct corridor.
      final blocker = VsdxShapeFactory.rectangle(
        id: 3,
        pinX: 4,
        pinY: 3,
        width: 1.5,
        height: 2,
      );
      final conn = VsdxShapeFactory.line(id: 4, ax: 1, ay: 3, bx: 7, by: 3);
      final page = VsdxPage(
        id: 0,
        name: 'P1',
        widthInches: 10,
        heightInches: 10,
        shapes: <VsdxShape>[left, right, blocker, conn],
        connects: const <VsdxConnect>[
          VsdxConnect(
            fromSheetId: 4,
            fromCell: 'BeginX',
            toSheetId: 1,
            toCell: 'PinX',
          ),
          VsdxConnect(
            fromSheetId: 4,
            fromCell: 'EndX',
            toSheetId: 2,
            toCell: 'PinX',
          ),
        ],
      ).rerouteConnectors();

      final route = VsdxPage.connectorRoute(page.findShapeById(4)!);
      expect(route.length, greaterThan(2));

      final obstacle = RouteAabb.fromCenter(
        pinX: 4,
        pinY: 3,
        width: 1.5,
        height: 2,
        pad: ObstacleRouter.defaultClearance,
      );
      for (var i = 0; i < route.length - 1; i++) {
        expect(
          obstacle.blocksSegment(
            route[i].x,
            route[i].y,
            route[i + 1].x,
            route[i + 1].y,
          ),
          isFalse,
          reason: 'auto-routed segment crosses blocker',
        );
      }
    });

    test('connectorRoute recovers baked avoiding polyline from geometry', () {
      final left = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 1,
        pinY: 2,
        width: 1,
        height: 1,
      );
      final right = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 6,
        pinY: 2,
        width: 1,
        height: 1,
      );
      final blocker = VsdxShapeFactory.rectangle(
        id: 3,
        pinX: 3.5,
        pinY: 2,
        width: 1,
        height: 2,
      );
      final conn = VsdxShapeFactory.line(id: 4, ax: 1, ay: 2, bx: 6, by: 2);
      final page = VsdxPage(
        id: 0,
        name: 'P1',
        widthInches: 10,
        heightInches: 10,
        shapes: <VsdxShape>[left, right, blocker, conn],
        connects: const <VsdxConnect>[
          VsdxConnect(
            fromSheetId: 4,
            fromCell: 'BeginX',
            toSheetId: 1,
            toCell: 'PinX',
          ),
          VsdxConnect(
            fromSheetId: 4,
            fromCell: 'EndX',
            toSheetId: 2,
            toCell: 'PinX',
          ),
        ],
      ).rerouteConnectors();

      final s = page.findShapeById(4)!;
      expect(s.waypoints, isEmpty); // auto route is not user waypoints
      final route = VsdxPage.connectorRoute(s);
      expect(route.length, greaterThan(2));
      expect(s.geometries.first.commands.length, route.length);
    });
  });
}
