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
  });
}
