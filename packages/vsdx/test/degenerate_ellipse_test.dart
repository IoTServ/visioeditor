import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  const ellipse = EllipseCmd(
    cx: 1,
    cy: 1,
    aX: 1,
    aY: 1,
    bX: 1,
    bY: 2,
  );

  test('zero-axis Ellipse follows libvisio A-to-B line fallback', () {
    expect(
      visioDegenerateEllipsePath(ellipse),
      const <Offset2D>[
        Offset2D(1, 1),
        Offset2D(1, 2),
        Offset2D(1, 1),
      ],
    );
    expect(
      visioDegenerateEllipsePath(
        const EllipseCmd(
          cx: 1,
          cy: 1,
          aX: 2,
          aY: 1,
          bX: 1,
          bY: 2,
        ),
      ),
      isNull,
    );
  });

  test('perimeter preserves degenerate Ellipse line segments', () {
    const shape = VsdxShape(
      id: 1,
      name: 'DegenerateEllipse',
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 2,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[ellipse]),
      ],
    );

    expect(
      ShapePerimeter.outlineSegments(shape),
      contains((const Offset2D(1, 1), const Offset2D(1, 2))),
    );
  });

  test('SVG preserves degenerate Ellipse as a closed line', () {
    const shape = VsdxShape(
      id: 1,
      name: 'DegenerateEllipse',
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 2,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[ellipse]),
      ],
    );
    const page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 4,
      heightInches: 4,
      shapes: <VsdxShape>[shape],
    );

    final svg = VsdxToSvgSerializer().serializePage(page);

    expect(svg, contains('M 1 1 L 1 2 L 1 1 Z'));
  });
}
