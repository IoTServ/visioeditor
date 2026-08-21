import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('radialGradientOrigin maps FillGradientDir 1–7', () {
    final o1 = radialGradientOrigin(
      dir: 1,
      minX: 0,
      minY: 0,
      width: 10,
      height: 8,
    );
    expect(o1.x, 0);
    expect(o1.y, 0);

    final o4 = radialGradientOrigin(
      dir: 4,
      minX: 0,
      minY: 0,
      width: 10,
      height: 8,
    );
    expect(o4.x, 5);
    expect(o4.y, 4);

    final o7 = radialGradientOrigin(
      dir: 7,
      minX: 0,
      minY: 0,
      width: 10,
      height: 8,
    );
    expect(o7.x, 10);
    expect(o7.y, 8);
  });

  test('sampleVisioGradientRgba matches canvas linear left-to-right', () {
    const stops = <({double position, int r, int g, int b, int a})>[
      (position: 0, r: 255, g: 0, b: 0, a: 255),
      (position: 1, r: 0, g: 0, b: 255, a: 255),
    ];
    final left = sampleVisioGradientRgba(
      x: 0,
      y: 4,
      minX: 0,
      minY: 0,
      width: 10,
      height: 8,
      linear: true,
      angleRad: 0,
      stops: stops,
    );
    final right = sampleVisioGradientRgba(
      x: 10,
      y: 4,
      minX: 0,
      minY: 0,
      width: 10,
      height: 8,
      linear: true,
      angleRad: 0,
      stops: stops,
    );
    expect(left.r, greaterThan(left.b + 80));
    expect(right.b, greaterThan(right.r + 80));
  });

  test('SVG rectangular fill gradient emits radialGradient', () {
    final blank = const VsdxWriter().emptyDocument();
    var doc = const DocumentParser().parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(
            gradient: VsdxGradient(
              type: VsdxGradientType.rectangular,
              dir: 1,
              stops: [
                VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
                VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
              ],
            ),
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('radialGradient'));
    expect(svg, isNot(contains('linearGradient id="grad-')));
  });
}
