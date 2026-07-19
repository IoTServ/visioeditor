import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  group('setConnectorStyle obstacle avoidance', () {
    test('orthogonal restyle excludes glued targets like rerouteConnectors', () {
      // Two boxes with an obstacle between them; glued connector should elbow
      // around the obstacle both after reroute and after setConnectorStyle.
      final a = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 1,
        pinY: 3,
        width: 1,
        height: 1,
      );
      final b = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 7,
        pinY: 3,
        width: 1,
        height: 1,
      );
      final wall = VsdxShapeFactory.rectangle(
        id: 3,
        pinX: 4,
        pinY: 3,
        width: 1,
        height: 3,
      );
      final conn = VsdxShapeFactory.line(id: 4, ax: 1, ay: 3, bx: 7, by: 3);
      var page = VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 10,
        heightInches: 10,
        shapes: <VsdxShape>[a, b, wall, conn],
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

      page = page.setConnectorStyle({4}, straight: false, curved: false);
      final route = page.drawnConnectorPagePolyline(page.findShapeById(4)!);
      expect(route.length, greaterThan(2));
      // A through-wall chord would stay near y=3 with |x-4|<0.6 on every
      // segment; a bypass must leave that corridor.
      final crossesWall = route.any(
        (p) => (p.x - 4).abs() < 0.6 && (p.y - 3).abs() < 0.4,
      );
      expect(crossesWall, isFalse);
    });
  });

  group('connectionIndexForPageDir', () {
    test('maps page-north to local right after 90° rotate', () {
      // Unrotated: CP0 = top (north). Rotate +90° CCW about pin: local top
      // becomes page west; local right becomes page north.
      final box = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 4,
        pinY: 4,
        width: 2,
        height: 2,
      ).copyWith(angleRad: 1.5707963267948966); // π/2
      final page = VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 10,
        heightInches: 10,
        shapes: <VsdxShape>[box],
      );
      // Page north → nearest side CP should be local right (index 1).
      expect(page.connectionIndexForPageDir(1, 0), 1);
      // Page east → local bottom (index 2).
      expect(page.connectionIndexForPageDir(1, 1), 2);
    });

    test('considers custom CPs beyond the first four', () {
      // Master-style: centre first, then a lone east side point at index 4.
      final box = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 4,
        pinY: 4,
        width: 2,
        height: 2,
      ).copyWith(
        connectionPoints: const <VsdxConnectionPoint>[
          VsdxConnectionPoint(1, 1, dirX: 0, dirY: 0), // centre
          VsdxConnectionPoint(1, 2, dirX: 0, dirY: 1), // north
          VsdxConnectionPoint(1, 0, dirX: 0, dirY: -1), // south
          VsdxConnectionPoint(0, 1, dirX: -1, dirY: 0), // west
          VsdxConnectionPoint(2, 1, dirX: 1, dirY: 0), // east (index 4)
        ],
      );
      final page = VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 10,
        heightInches: 10,
        shapes: <VsdxShape>[box],
      );
      expect(page.connectionIndexForPageDir(1, 1), 4); // page east
      expect(page.connectionIndexForPageDir(1, 0), 1); // page north
    });
  });

  group('setConnectorRounded preserves obstacle elbows', () {
    test('toggling rounded off keeps auto-routed detour', () {
      final a = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 1,
        pinY: 3,
        width: 1,
        height: 1,
      );
      final b = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 7,
        pinY: 3,
        width: 1,
        height: 1,
      );
      final wall = VsdxShapeFactory.rectangle(
        id: 3,
        pinX: 4,
        pinY: 3,
        width: 1,
        height: 3,
      );
      final conn = VsdxShapeFactory.line(id: 4, ax: 1, ay: 3, bx: 7, by: 3);
      var page = VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 10,
        heightInches: 10,
        shapes: <VsdxShape>[a, b, wall, conn],
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
      page = page.setConnectorRounded({4}, true);
      page = page.setConnectorRounded({4}, false);
      final route = page.drawnConnectorPagePolyline(page.findShapeById(4)!);
      // Straight through the wall would keep y≈3; obstacle detour must bend.
      expect(route.any((p) => (p.y - 3).abs() > 0.5), isTrue);
    });
  });

  group('autoRoutedConnectorPolyline whole-shape glue', () {
    test('aims perimeter attach at opposite pin, not stale End', () {
      final diamond = VsdxShapeFactory.polygon(
        id: 1,
        pinX: 2,
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
        pinY: 5,
        width: 1,
        height: 1,
      );
      // Begin/End still at pins (geometry-less style before first paint reroute).
      final conn = VsdxShapeFactory.line(id: 3, ax: 2, ay: 3, bx: 8, by: 5);
      final page = VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 12,
        heightInches: 10,
        shapes: <VsdxShape>[diamond, other, conn],
        connects: const <VsdxConnect>[
          VsdxConnect(
            fromSheetId: 3,
            fromCell: 'BeginX',
            toSheetId: 1,
            toCell: 'PinX',
          ),
          VsdxConnect(
            fromSheetId: 3,
            fromCell: 'EndX',
            toSheetId: 2,
            toCell: 'PinX',
          ),
        ],
      );
      final route = page.autoRoutedConnectorPolyline(conn);
      expect(route.length, greaterThanOrEqualTo(2));
      // Begin should leave the diamond pin (2,3) and land on an edge.
      expect(route.first.x, isNot(closeTo(2, 1e-3)));
      // Aiming at opposite pin (8,5) hits diamond toward the right tip ≈ (3,3).
      expect(route.first.x, greaterThan(2.5));
    });
  });
}
