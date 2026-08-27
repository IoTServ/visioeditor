import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('radialGradientOrigin maps MS-VSDX FillGradientDir 1–12', () {
    const minX = 0.0, minY = 0.0, width = 10.0, height = 8.0;
    ({double x, double y}) at(int dir) => radialGradientOrigin(
          dir: dir,
          minX: minX,
          minY: minY,
          width: width,
          height: height,
        );

    // Visio Y-up: minY is the visual bottom.
    expect(at(1).x, 10); // radial bottom-right
    expect(at(1).y, 0);
    expect(at(2).x, 0); // radial bottom-left
    expect(at(2).y, 0);
    expect(at(3).x, 5); // radial centre
    expect(at(3).y, 4);
    expect(at(4).x, 5); // radial centre-bottom
    expect(at(4).y, 0);
    expect(at(5).x, 5); // radial centre-top
    expect(at(5).y, 8);
    expect(at(7).x, 0); // radial top-left
    expect(at(7).y, 8);
    expect(at(8).x, 10); // rectangular bottom-right
    expect(at(8).y, 0);
    expect(at(9).x, 0); // rectangular bottom-left
    expect(at(9).y, 0);
    expect(at(10).x, 5);
    expect(at(10).y, 4);
    expect(at(12).x, 0); // rectangular top-left
    expect(at(12).y, 8);
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

  test('rectangularGradientT matches ODF box isolines', () {
    const minX = 0.0, minY = 0.0, width = 10.0, height = 4.0;
    final centre = rectangularGradientT(
      5,
      2,
      minX: minX,
      minY: minY,
      width: width,
      height: height,
    );
    expect(centre, closeTo(0, 1e-9));

    final midTop = rectangularGradientT(
      5,
      3.6,
      minX: minX,
      minY: minY,
      width: width,
      height: height,
    );
    final midSide = rectangularGradientT(
      1,
      2,
      minX: minX,
      minY: minY,
      width: width,
      height: height,
    );
    final corner = rectangularGradientT(
      1,
      3.6,
      minX: minX,
      minY: minY,
      width: width,
      height: height,
    );
    expect(midTop, closeTo(0.8, 1e-9));
    expect(midSide, closeTo(0.8, 1e-9));
    expect(corner, closeTo(0.8, 1e-9));

    expect(
      rectangularGradientT(
        0,
        0,
        minX: minX,
        minY: minY,
        width: width,
        height: height,
        dir: 9,
      ),
      closeTo(0, 1e-9),
      reason: 'FillGradientDir 9 is rectangle-from-bottom-left',
    );
    expect(
      rectangularGradientT(
        10,
        4,
        minX: minX,
        minY: minY,
        width: width,
        height: height,
        dir: 9,
      ),
      closeTo(1, 1e-9),
    );

    final radialTop = sampleVisioGradientRgba(
      x: 5,
      y: 3.6,
      minX: minX,
      minY: minY,
      width: width,
      height: height,
      linear: false,
      angleRad: 0,
      stops: const <({double position, int r, int g, int b, int a})>[
        (position: 0, r: 255, g: 0, b: 255, a: 255),
        (position: 1, r: 255, g: 255, b: 255, a: 255),
      ],
    );
    final rectTop = sampleVisioGradientRgba(
      x: 5,
      y: 3.6,
      minX: minX,
      minY: minY,
      width: width,
      height: height,
      linear: false,
      rectangular: true,
      angleRad: 0,
      stops: const <({double position, int r, int g, int b, int a})>[
        (position: 0, r: 255, g: 0, b: 255, a: 255),
        (position: 1, r: 255, g: 255, b: 255, a: 255),
      ],
    );
    final rectCorner = sampleVisioGradientRgba(
      x: 1,
      y: 3.6,
      minX: minX,
      minY: minY,
      width: width,
      height: height,
      linear: false,
      rectangular: true,
      angleRad: 0,
      stops: const <({double position, int r, int g, int b, int a})>[
        (position: 0, r: 255, g: 0, b: 255, a: 255),
        (position: 1, r: 255, g: 255, b: 255, a: 255),
      ],
    );
    expect(rectTop.g, rectCorner.g,
        reason: 'rectangular isolines share Chebyshev t');
    expect((radialTop.g - rectTop.g).abs(), greaterThan(20),
        reason: 'a radial disc washes the short side first');
  });

  test('pathGradientT matches centre rectangular on a box', () {
    const minX = 0.0, minY = 0.0, width = 10.0, height = 4.0;
    expect(
      pathGradientT(5, 2, minX: minX, minY: minY, width: width, height: height),
      closeTo(0, 1e-9),
    );
    final top = pathGradientT(
      5,
      4,
      minX: minX,
      minY: minY,
      width: width,
      height: height,
    );
    final side = pathGradientT(
      0,
      2,
      minX: minX,
      minY: minY,
      width: width,
      height: height,
    );
    expect(top, closeTo(1, 1e-9));
    expect(side, closeTo(1, 1e-9));
    expect(
      ellipticalPathGradientT(
        5,
        4,
        minX: minX,
        minY: minY,
        width: width,
        height: height,
      ),
      closeTo(1, 1e-9),
    );
    final ellipse45 = ellipticalPathGradientT(
      5 + 5 * 0.70710678118,
      2 + 2 * 0.70710678118,
      minX: minX,
      minY: minY,
      width: width,
      height: height,
    );
    expect(ellipse45, closeTo(1, 0.02));
    expect(
      pathGradientT(
        5 + 5 * 0.70710678118,
        2 + 2 * 0.70710678118,
        minX: minX,
        minY: minY,
        width: width,
        height: height,
      ),
      closeTo(0.70710678118, 0.02),
      reason: 'box path is Chebyshev; 45° is inside the rectangle outline',
    );

    const stops = <({double position, int r, int g, int b, int a})>[
      (position: 0, r: 255, g: 0, b: 255, a: 255),
      (position: 1, r: 255, g: 255, b: 255, a: 255),
    ];
    final pathTop = sampleVisioGradientRgba(
      x: 5,
      y: 3.6,
      minX: minX,
      minY: minY,
      width: width,
      height: height,
      linear: false,
      path: true,
      angleRad: 0,
      stops: stops,
    );
    final radialTop = sampleVisioGradientRgba(
      x: 5,
      y: 3.6,
      minX: minX,
      minY: minY,
      width: width,
      height: height,
      linear: false,
      angleRad: 0,
      stops: stops,
    );
    expect(pathTop.g, greaterThan(radialTop.g + 20),
        reason: 'path short-edge is t≈1; radial disc is still magenta');
  });

  test('SVG rectangular fill gradient emits concentric rect pattern', () {
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
    expect(svg, contains('patternUnits="userSpaceOnUse"'));
    expect(svg, isNot(contains('radialGradient')));
    expect(svg, isNot(contains('linearGradient id="grad-')));
  });

  test('SVG path fill gradient emits concentric scaled copies', () {
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
              type: VsdxGradientType.path,
              dir: 13,
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
    expect(svg, contains('patternUnits="userSpaceOnUse"'));
    expect(svg, contains('scale('));
    expect(svg, isNot(contains('radialGradient')));
  });

  test('SVG classic FillPattern 36–39 anchor the MS-VSDX corner', () {
    final blank = const VsdxWriter().emptyDocument();
    final page = const DocumentParser().parse(blank).pages.first;
    // 2×1 box centred at (2,2): x spans 1..3, y spans 1.5..2.5 (Visio Y-up).
    String svgFor(int pattern) {
      final doc = const DocumentParser().parse(blank);
      return VsdxToSvgSerializer().serializePage(
        doc.pages.first.addShape(
          VsdxShapeFactory.rectangle(
            id: page.nextFreeShapeId(),
            pinX: 2,
            pinY: 2,
            width: 2,
            height: 1,
            fill: VsdxFill(
              foreground: const VsdxColor(0xFFFF00FF),
              background: VsdxColor.white,
              pattern: pattern,
            ),
            line: const VsdxLine(pattern: 0),
          ),
        ),
      );
    }

    ({double cx, double cy}) centreOf(String svg) {
      final match = RegExp(r'<radialGradient[^>]*cx="([-0-9.]+)"[^>]*'
              r'cy="([-0-9.]+)"')
          .firstMatch(svg);
      expect(match, isNotNull, reason: 'radialGradient must carry cx/cy');
      return (
        cx: double.parse(match!.group(1)!),
        cy: double.parse(match.group(2)!),
      );
    }

    // ODF svg:cx/cy are 0 at Draw's top-left, so 36/37 sit on the visual top
    // edge (largest Y in Visio inches) and 38/39 on the bottom.
    final p36 = centreOf(svgFor(36));
    final p37 = centreOf(svgFor(37));
    final p38 = centreOf(svgFor(38));
    final p39 = centreOf(svgFor(39));
    final p40 = centreOf(svgFor(40));

    expect(p36.cx, p38.cx, reason: '36 / 38 are the left edge');
    expect(p37.cx, p39.cx, reason: '37 / 39 are the right edge');
    expect(p36.cx, lessThan(p37.cx));
    expect(p36.cy, p37.cy, reason: '36 / 37 are the visual top edge');
    expect(p38.cy, p39.cy, reason: '38 / 39 are the visual bottom edge');
    expect(p38.cy, lessThan(p36.cy), reason: 'Visio inches are Y-up');
    expect(p40.cx, closeTo((p36.cx + p37.cx) / 2, 1e-9));
    expect(p40.cy, closeTo((p38.cy + p36.cy) / 2, 1e-9));
    // A 2×1 box: the corner presets must be one full width / height apart.
    expect(p37.cx - p36.cx, closeTo(2, 1e-9));
    expect(p36.cy - p38.cy, closeTo(1, 1e-9));
  });
}
