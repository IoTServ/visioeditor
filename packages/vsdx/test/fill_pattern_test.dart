import 'package:test/test.dart';
import 'package:vsdx/src/parser/style_parser.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

void main() {
  test('libvisio hatch map covers every FillPattern 2-24', () {
    for (var pattern = 2; pattern <= 24; pattern++) {
      expect(libvisioHatchSpec(pattern), isNotNull, reason: 'pattern $pattern');
    }
    expect(libvisioHatchSpec(1), isNull);
    expect(libvisioHatchSpec(25), isNull);

    expect(libvisioHatchSpec(2)!.angleDegrees, 45);
    expect(libvisioHatchSpec(3)!.style, VsdxHatchStyle.double);
    expect(libvisioHatchSpec(4)!.angleDegrees, 45);
    expect(libvisioHatchSpec(7)!.angleDegrees, 90);
    expect(libvisioHatchSpec(8)!.style, VsdxHatchStyle.triple);
    expect(libvisioHatchSpec(8)!.distanceInches, 0.05);
    expect(libvisioHatchSpec(23)!.style, VsdxHatchStyle.double);
  });

  test('sampleVisioHatchRgba matches horizontal FillPattern 6', () {
    final spec = libvisioHatchSpec(6)!;
    const fg = (r: 255, g: 0, b: 0, a: 255);
    const bg = (r: 0, g: 0, b: 255, a: 255);
    final onLine = sampleVisioHatchRgba(
      spec: spec,
      x: 0.2,
      y: 0.05,
      foreground: fg,
      background: bg,
    );
    final inGap = sampleVisioHatchRgba(
      spec: spec,
      x: 0.2,
      y: 0.0,
      foreground: fg,
      background: bg,
    );
    expect(onLine.r, greaterThan(onLine.b + 80));
    expect(inGap.b, greaterThan(inGap.r + 80));
  });

  test('VSDX classic gradient pattern is materialised without stop section',
      () {
    final shape = XmlDocument.parse(
      '<Shape>'
      '<Cell N="FillForegnd" V="#f4f9ff"/>'
      '<Cell N="FillBkgnd" V="#dff4d5"/>'
      '<Cell N="FillPattern" V="40"/>'
      '<Cell N="FillGradientEnabled" V="0"/>'
      '</Shape>',
    ).rootElement;
    final fill = const StyleParser().parseFill(shape);
    expect(fill.pattern, 40);
    expect(fill.gradient, isNotNull);
    expect(fill.gradient!.type, VsdxGradientType.radial);
    expect(fill.gradient!.dir, 3);
    expect(fill.gradient!.stops.first.color, const VsdxColor(0xFFF4F9FF));
    expect(fill.gradient!.stops.last.color, const VsdxColor(0xFFDFF4D5));
  });

  test('paintGradient materialises classic FillPattern 25–40 without parse',
      () {
    const fill = VsdxFill(
      foreground: VsdxColor(0xFFFF0000),
      background: VsdxColor(0xFF0000FF),
      pattern: 40,
    );
    expect(fill.hasGradient, isFalse);
    expect(fill.paintGradient, isNotNull);
    expect(fill.paintGradient!.type, VsdxGradientType.radial);
    expect(fill.paintGradient!.dir, 3);

    final page = const DocumentParser()
        .parse(const VsdxWriter().emptyDocument())
        .pages
        .first;
    final svg = VsdxToSvgSerializer().serializePage(
      page.addShape(
        VsdxShapeFactory.rectangle(
          id: page.nextFreeShapeId(),
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 2,
          fill: fill,
        ),
      ),
    );
    expect(svg, contains('radialGradient'));
  });

  test('FillGradient with FillPattern=1 maps to a classic id libvisio paints',
      () {
    for (var pattern = 25; pattern <= 40; pattern++) {
      final classic = withLibvisioClassicGradient(
        VsdxFill(
          foreground: const VsdxColor(0xFFFF0000),
          background: const VsdxColor(0xFF0000FF),
          pattern: pattern,
        ),
      );
      final modern = classic.copyWith(pattern: 1);
      expect(
        fillPatternForLibvisioWrite(modern),
        pattern,
        reason: 'FillPattern $pattern',
      );
    }
    expect(fillPatternForLibvisioWrite(const VsdxFill(pattern: 0)), 0);
    expect(
      fillPatternForLibvisioWrite(
        const VsdxFill(
          pattern: 0,
          gradient: VsdxGradient(
            stops: [
              VsdxGradientStop(position: 0, color: VsdxColor(0xFF8DC0FF)),
              VsdxGradientStop(position: 1, color: VsdxColor(0xFF467DFE)),
            ],
          ),
        ),
      ),
      inInclusiveRange(25, 40),
      reason: 'omitted FillPattern still maps FillGradient to classic 25–40',
    );
    expect(fillPatternForLibvisioWrite(const VsdxFill(pattern: 2)), 2);
    expect(
      fillPatternForLibvisioWrite(const VsdxFill(pattern: 41)),
      1,
      reason: 'ids above 40 become solid foreground, not Draw\'s bg fallback',
    );
  });

  test('FillPattern=0 FillGradient still paints and writes classic ids', () {
    const fill = VsdxFill(
      pattern: 0,
      gradient: VsdxGradient(
        angleRad: 3.92699,
        stops: [
          VsdxGradientStop(
            position: 0,
            color: VsdxColor(0xFF8DC0FF),
            transparency: 1,
          ),
          VsdxGradientStop(position: 0.2, color: VsdxColor(0xFFACCFFF)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF467DFE)),
        ],
      ),
    );
    expect(fill.hasFill, isTrue);
    expect(fill.paintGradient, isNotNull);
    final write = fillForLibvisioWrite(fill);
    expect(write.pattern, inInclusiveRange(25, 40));
    expect(write.foreground, const VsdxColor(0xFFACCFFF),
        reason: 'skip the fully-transparent first stop for FillForegnd');
    expect(write.background, const VsdxColor(0xFF467DFE));

    final page = const DocumentParser()
        .parse(const VsdxWriter().emptyDocument())
        .pages
        .first;
    final svg = VsdxToSvgSerializer().serializePage(
      page.addShape(
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
          fill: fill,
        ),
      ),
    );
    expect(svg, contains('linearGradient'));
    expect(svg, contains('url(#grad-'));
  });

  test('geometry-less FillPattern=1 writes 0 so Edraw cannot fill the text box',
      () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 1,
      pinY: 1,
      width: 1,
      height: 0.3,
      fill: const VsdxFill(
        pattern: 1,
        foreground: VsdxColor(0xFFFFFFFF),
      ),
    ).copyWith(geometries: const <VsdxGeometry>[]);
    expect(shape.fill.pattern, 1);
    expect(libvisioShapeWrite(shape).fill.pattern, 0);
  });
}
