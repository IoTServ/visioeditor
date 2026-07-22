import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('SVG combines multi NoFill=0 geometries with evenodd', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 4,
      heightInches: 4,
      shapes: [
        VsdxShape(
          id: 1,
          name: 'Frame',
          pinX: 2,
          pinY: 2,
          width: 3,
          height: 3,
          fill: const VsdxFill(
            foreground: VsdxColor(0xFF000000),
            pattern: 1,
          ),
          line: const VsdxLine(pattern: 0),
          geometries: [
            VsdxGeometry(commands: const [
              MoveTo(0, 0),
              LineTo(3, 0),
              LineTo(3, 3),
              LineTo(0, 3),
              LineTo(0, 0),
            ]),
            VsdxGeometry(commands: const [
              MoveTo(0.5, 0.5),
              LineTo(2.5, 0.5),
              LineTo(2.5, 2.5),
              LineTo(0.5, 2.5),
              LineTo(0.5, 0.5),
            ]),
          ],
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('fill-rule="evenodd"'), isTrue);
    // One combined fill path, not two solid fills.
    expect('fill-rule="evenodd"'.allMatches(svg).length, 1);
  });

  test('SVG keeps separate fills when inner geom is NoFill', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 4,
      heightInches: 4,
      shapes: [
        VsdxShapeFactory.doubleRectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1.5,
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    // doubleRectangle inner is NoFill — must NOT collapse to evenodd hole.
    expect(svg.contains('fill-rule="evenodd"'), isFalse);
  });
}
