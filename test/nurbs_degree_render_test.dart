import 'package:flutter_test/flutter_test.dart';
import 'package:vsdx/vsdx.dart';

import 'package:visioeditor/render/path_builder.dart';

void main() {
  test('Canvas caps NURBS degree at libvisio maximum 8', () {
    const controls = <Offset2D>[
      Offset2D(1, 1),
      Offset2D(2, -1),
      Offset2D(3, 1),
      Offset2D(4, -1),
      Offset2D(5, 1),
      Offset2D(6, -1),
      Offset2D(7, 1),
      Offset2D(8, -1),
    ];
    VsdxGeometry geometry(int degree) => VsdxGeometry(
      commands: <VsdxPathCommand>[
        const MoveTo(0, 0),
        NurbsTo(x: 9, y: 0, controlPoints: controls, degree: degree),
      ],
    );

    final degree8 = buildPath(
      geometry(8),
      widthInches: 9,
      heightInches: 2,
    ).getBounds();
    final degree9 = buildPath(
      geometry(9),
      widthInches: 9,
      heightInches: 2,
    ).getBounds();

    expect(degree9.left, closeTo(degree8.left, 1e-12));
    expect(degree9.top, closeTo(degree8.top, 1e-12));
    expect(degree9.right, closeTo(degree8.right, 1e-12));
    expect(degree9.bottom, closeTo(degree8.bottom, 1e-12));
  });
}
