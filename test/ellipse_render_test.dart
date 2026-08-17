import 'package:flutter_test/flutter_test.dart';
import 'package:vsdx/vsdx.dart';

import 'package:visioeditor/render/path_builder.dart';

void main() {
  test('Canvas keeps a rotated affine Ellipse as a continuous conic', () {
    const geometry = VsdxGeometry(
      commands: <VsdxPathCommand>[
        EllipseCmd(cx: 3, cy: 2, aX: 4.2, aY: 2.7, bX: 2.55, bY: 2.9),
      ],
    );

    final path = buildPath(
      geometry,
      widthInches: 6,
      heightInches: 4,
    );
    final metric = path.computeMetrics().single;
    final authoredStart = metric.getTangentForOffset(0)!;
    final start = metric.getTangentForOffset(1e-5)!.vector;
    final end = metric.getTangentForOffset(metric.length - 1e-5)!.vector;

    expect(metric.isClosed, isTrue);
    expect(authoredStart.position.dx, closeTo(4.2, 1e-6));
    expect(authoredStart.position.dy, closeTo(2.7, 1e-6));
    expect(authoredStart.vector.dx / authoredStart.vector.dy,
        closeTo(-0.5, 1e-3));
    expect(start.dx, closeTo(end.dx, 1e-3));
    expect(start.dy, closeTo(end.dy, 1e-3));
  });

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
