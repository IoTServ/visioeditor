import 'package:flutter_test/flutter_test.dart';
import 'package:vsdx/vsdx.dart';

import 'package:visioeditor/render/path_builder.dart';

void main() {
  test('Canvas uses libvisio LineTo fallback for zero-eccentricity arc', () {
    const geometry = VsdxGeometry(
      commands: <VsdxPathCommand>[
        MoveTo(0, 0),
        EllipticalArcTo(
          x: 2,
          y: 0,
          controlX: 1,
          controlY: 1,
          angle: 0,
          eccentricity: 0,
        ),
      ],
    );

    final bounds = buildPath(
      geometry,
      widthInches: 2,
      heightInches: 1,
    ).getBounds();

    expect(bounds.width, closeTo(2, 1e-9));
    expect(bounds.height, closeTo(0, 1e-9));
  });
}
