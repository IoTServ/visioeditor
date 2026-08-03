import 'package:flutter_test/flutter_test.dart';
import 'package:vsdx/vsdx.dart';

import 'package:visioeditor/render/path_builder.dart';

void main() {
  test('Canvas preserves libvisio zero-axis Ellipse line fallback', () {
    const geometry = VsdxGeometry(
      commands: <VsdxPathCommand>[
        EllipseCmd(cx: 1, cy: 1, aX: 1, aY: 1, bX: 1, bY: 2),
      ],
    );

    final bounds = buildPath(
      geometry,
      widthInches: 2,
      heightInches: 2,
    ).getBounds();

    expect(bounds.left, closeTo(1, 1e-9));
    expect(bounds.top, closeTo(1, 1e-9));
    expect(bounds.width, closeTo(0, 1e-9));
    expect(bounds.height, closeTo(1, 1e-9));
  });
}
