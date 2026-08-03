import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('SVG skips one invalid geometry and keeps later shapes', () {
    final broken = VsdxShape(
      id: 1,
      name: 'Broken',
      pinX: 1,
      pinY: 1,
      width: 1,
      height: 1,
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          commands: <VsdxPathCommand>[
            MoveTo(0, 0),
            // A negative degree is not produced by the parser, but models a
            // damaged/foreign curve reaching the release renderer.
            NurbsTo(
              x: 1,
              y: 1,
              controlPoints: <Offset2D>[],
              degree: -1,
            ),
          ],
        ),
      ],
    );
    final valid = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 3,
      pinY: 1,
      width: 1,
      height: 1,
    ).copyWith(
      fill: const VsdxFill(foreground: VsdxColor(0xFF00FF00)),
    );
    final page = VsdxPage(
      id: 0,
      name: 'Recovery',
      widthInches: 4,
      heightInches: 2,
      shapes: <VsdxShape>[broken, valid],
    );

    final svg = VsdxToSvgSerializer().serializePage(page);

    expect(svg, contains('#00ff00'));
    expect(svg, endsWith('</svg>\n'));
  });
}
