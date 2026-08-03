import 'package:flutter_test/flutter_test.dart';
import 'package:vsdx/vsdx.dart';

import 'package:visioeditor/render/path_builder.dart';

void main() {
  test('Canvas path builder uses page-clipped InfiniteLine endpoints', () {
    const geometry = VsdxGeometry(
      commands: <VsdxPathCommand>[
        InfiniteLineCmd(x: 0, y: 0.005, a: 0.01, b: 0.005),
      ],
    );

    final path = buildPath(
      geometry,
      widthInches: 0.01,
      heightInches: 0.01,
      infiniteLineResolver: (p, q) => const <Offset2D>[
        Offset2D(-4.995, 0.005),
        Offset2D(5.005, 0.005),
      ],
    );
    final bounds = path.getBounds();

    expect(bounds.left, closeTo(-4.995, 1e-6));
    expect(bounds.right, closeTo(5.005, 1e-6));
    expect(bounds.top, closeTo(0.005, 1e-6));
    expect(bounds.bottom, closeTo(0.005, 1e-6));
  });
}
