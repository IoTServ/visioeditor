import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/render/connector_router.dart';
import 'package:vsdx/vsdx.dart';

/// A glued connector must attach on the target shape's *perimeter* (aimed at
/// the opposite end), never its centre — otherwise the arrow head is drawn
/// inside the rectangle / diamond it points at (the reported workflow.vsdx bug).
void main() {
  const router = ConnectorRouter();

  VsdxPage pageWith(VsdxShape target, VsdxShape connector) => VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 10,
        heightInches: 10,
        shapes: <VsdxShape>[target, connector],
        connects: <VsdxConnect>[
          VsdxConnect(
            fromSheetId: connector.id,
            fromCell: 'EndX',
            fromPart: 12,
            toSheetId: target.id,
            toCell: 'PinX',
            toPart: 3,
          ),
        ],
      );

  test('horizontal glue lands on the left edge, not the centre', () {
    // Target rectangle centred at (5,5), 2 x 1 → left edge x = 4.
    final target =
        VsdxShapeFactory.rectangle(id: 1, pinX: 5, pinY: 5, width: 2, height: 1);
    // Connector arrives from the left; its End is glued to the target.
    final connector = VsdxShapeFactory.line(id: 2, ax: 0, ay: 5, bx: 5, by: 5);

    final routed = router.route(connector, page: pageWith(target, connector))!;

    expect(routed.end.dx, closeTo(4.0, 1e-6)); // perimeter, not centre (5.0)
    expect(routed.end.dy, closeTo(5.0, 1e-6));
    expect(routed.begin.dx, closeTo(0.0, 1e-6)); // un-glued end untouched
  });

  test('diamond glue lands on a slanted edge, not the AABB', () {
    final target = VsdxShapeFactory.polygon(
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
    final connector = VsdxShapeFactory.line(id: 2, ax: 0, ay: 0, bx: 5, by: 5);
    final routed = router.route(connector, page: pageWith(target, connector))!;
    // Ray from (0,0) aim — attach from centre (5,5) toward begin (0,0)
    // → diamond edge at (4.5, 4.5).
    expect(routed.end.dx, closeTo(4.5, 1e-6));
    expect(routed.end.dy, closeTo(4.5, 1e-6));
  });

  test('vertical glue lands on the bottom edge', () {
    final target =
        VsdxShapeFactory.rectangle(id: 1, pinX: 5, pinY: 5, width: 2, height: 1);
    // Connector arrives from below.
    final connector = VsdxShapeFactory.line(id: 2, ax: 5, ay: 0, bx: 5, by: 5);

    final routed = router.route(connector, page: pageWith(target, connector))!;

    expect(routed.end.dx, closeTo(5.0, 1e-6));
    expect(routed.end.dy, closeTo(4.5, 1e-6)); // bottom edge, not centre (5.0)
  });
}
