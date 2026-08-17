import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('ArcTo endpoint arrows follow exact circular derivatives', () {
    final tangents = geometryEndpointTangents(
      const VsdxGeometry(
        commands: <VsdxPathCommand>[
          MoveTo(0, 0),
          ArcTo(x: 2, y: 0, bow: 0.6),
        ],
      ),
      widthInches: 2,
      heightInches: 1,
    )!;

    expect(tangents.start, const Offset2D(0, 0));
    expect(tangents.end, const Offset2D(2, 0));
    expect(tangents.startForward.x, greaterThan(0));
    expect(tangents.startForward.y, lessThan(0));
    expect(tangents.endForward.x, greaterThan(0));
    expect(tangents.endForward.y, greaterThan(0));
    expect(
      tangents.startForward.y / tangents.startForward.x,
      closeTo(-1 / 0.5333333333333333, 1e-9),
    );
  });

  test('EllipticalArcTo endpoint arrows use ellipse traversal tangents', () {
    final tangents = geometryEndpointTangents(
      const VsdxGeometry(
        commands: <VsdxPathCommand>[
          MoveTo(1, 0),
          EllipticalArcTo(
            x: 0,
            y: 1,
            controlX: math.sqrt1_2,
            controlY: math.sqrt1_2,
          ),
        ],
      ),
      widthInches: 1,
      heightInches: 1,
    )!;

    expect(tangents.startForward.x, closeTo(0, 1e-9));
    expect(tangents.startForward.y, greaterThan(0));
    expect(tangents.endForward.x, lessThan(0));
    expect(tangents.endForward.y, closeTo(0, 1e-9));
  });

  test('degenerate curve controls select the next non-zero derivative', () {
    final tangents = geometryEndpointTangents(
      const VsdxGeometry(
        commands: <VsdxPathCommand>[
          MoveTo(0, 0),
          CubBezTo(x: 2, y: 2, x1: 0, y1: 0, x2: 0, y2: 2),
        ],
      ),
      widthInches: 2,
      heightInches: 2,
    )!;

    expect(tangents.startForward, const Offset2D(0, 2));
    expect(tangents.endForward, const Offset2D(2, 0));
  });

  test('zero-length endpoint segments preserve the nearest real direction', () {
    final tangents = geometryEndpointTangents(
      const VsdxGeometry(
        commands: <VsdxPathCommand>[
          MoveTo(0, 0),
          LineTo(0, 0),
          LineTo(2, 0),
          LineTo(2, 0),
        ],
      ),
      widthInches: 2,
      heightInches: 1,
    )!;

    expect(tangents.start, const Offset2D(0, 0));
    expect(tangents.end, const Offset2D(2, 0));
    expect(tangents.startForward, const Offset2D(2, 0));
    expect(tangents.endForward, const Offset2D(2, 0));
  });

  test('InfiniteLine arrows use its libvisio-style clipped page span', () {
    final tangents = geometryEndpointTangents(
      const VsdxGeometry(
        commands: <VsdxPathCommand>[
          InfiniteLineCmd(x: 0, y: 0.5, a: 2, b: 0.5),
        ],
      ),
      widthInches: 2,
      heightInches: 1,
      infiniteLineResolver: (p, q) => const <Offset2D>[
        Offset2D(-3, 0.5),
        Offset2D(7, 0.5),
      ],
    )!;

    expect(tangents.start, const Offset2D(-3, 0.5));
    expect(tangents.end, const Offset2D(7, 0.5));
    expect(tangents.startForward, const Offset2D(10, 0));
    expect(tangents.endForward, const Offset2D(10, 0));
  });

  test('multi-M Geometry exposes markers for every libvisio subpath', () {
    const geometry = VsdxGeometry(
      commands: <VsdxPathCommand>[
        MoveTo(0, 0),
        LineTo(1, 0),
        EllipseCmd(cx: 2, cy: 1, aX: 3, aY: 1, bX: 2, bY: 2),
        MoveTo(4, 0),
        LineTo(5, 0),
      ],
    );

    final subpaths = geometrySubpathEndpointTangents(
      geometry,
      widthInches: 5,
      heightInches: 2,
    );

    expect(subpaths, hasLength(2));
    expect(subpaths[0].start, const Offset2D(0, 0));
    expect(subpaths[0].end, const Offset2D(1, 0));
    expect(subpaths[1].start, const Offset2D(4, 0));
    expect(subpaths[1].end, const Offset2D(5, 0));

    final aggregate = geometryEndpointTangents(
      geometry,
      widthInches: 5,
      heightInches: 2,
    )!;
    expect(aggregate.start, subpaths.first.start);
    expect(aggregate.end, subpaths.last.end);
  });

  test('closed line-command subpaths suppress markers like libvisio', () {
    const geometry = VsdxGeometry(
      commands: <VsdxPathCommand>[
        MoveTo(0, 0),
        LineTo(2, 0),
        LineTo(2, 1),
        LineTo(0, 0),
      ],
    );

    expect(
      geometrySubpathEndpointTangents(
        geometry,
        widthInches: 2,
        heightInches: 1,
      ),
      isEmpty,
    );
    expect(
      geometryEndpointTangents(
        geometry,
        widthInches: 2,
        heightInches: 1,
      ),
      isNull,
    );
  });
}
