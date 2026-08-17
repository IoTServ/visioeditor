import 'package:flutter_test/flutter_test.dart';
import 'package:vsdx/vsdx.dart';

import 'package:visioeditor/render/path_builder.dart';

void main() {
  test('Canvas ArcTo uses libvisio minor arc below half-chord bow', () {
    const geometry = VsdxGeometry(
      commands: <VsdxPathCommand>[
        MoveTo(0, 0),
        ArcTo(x: 2, y: 0, bow: 0.6),
      ],
    );

    final path = buildPath(
      geometry,
      widthInches: 2,
      heightInches: 1,
    );
    final bounds = path.getBounds();

    expect(bounds.width, closeTo(2, 1e-6));
    expect(bounds.height, closeTo(0.6, 1e-6));
    expect(bounds.top, closeTo(-0.6, 1e-6));
    expect(bounds.bottom, closeTo(0, 1e-6));
  });
}
