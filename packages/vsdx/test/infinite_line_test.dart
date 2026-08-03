import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('InfiniteLine clipping matches libvisio page-border intersections', () {
    final clipped = clipInfiniteLineToPage(
      const Offset2D(2, 1),
      const Offset2D(4, 5),
      pageWidth: 10,
      pageHeight: 6,
    );

    expect(clipped, isNotNull);
    expect(clipped!.first.x, closeTo(1.5, 1e-12));
    expect(clipped.first.y, closeTo(0, 1e-12));
    expect(clipped.last.x, closeTo(4.5, 1e-12));
    expect(clipped.last.y, closeTo(6, 1e-12));
  });

  test('InfiniteLine clipping preserves horizontal and vertical spans', () {
    expect(
      clipInfiniteLineToPage(
        const Offset2D(3, 2),
        const Offset2D(3, 4),
        pageWidth: 10,
        pageHeight: 6,
      ),
      const <Offset2D>[Offset2D(3, 0), Offset2D(3, 6)],
    );
    expect(
      clipInfiniteLineToPage(
        const Offset2D(2, 4),
        const Offset2D(8, 4),
        pageWidth: 10,
        pageHeight: 6,
      ),
      const <Offset2D>[Offset2D(0, 4), Offset2D(10, 4)],
    );
  });

  test('SVG InfiniteLine reaches page edges for a tiny shape', () {
    const shape = VsdxShape(
      id: 1,
      name: 'Infinite',
      pinX: 5,
      pinY: 3,
      width: 0.01,
      height: 0.01,
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            InfiniteLineCmd(x: 0, y: 0.005, a: 0.01, b: 0.005),
          ],
        ),
      ],
    );
    const page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 10,
      heightInches: 6,
      shapes: <VsdxShape>[shape],
    );

    final svg = VsdxToSvgSerializer().serializePage(page);

    expect(svg, contains('M -4.995 0.005 L 5.005 0.005'));
  });
}
