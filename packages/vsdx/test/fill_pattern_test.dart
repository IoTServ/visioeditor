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

  test('VSDX classic gradient pattern is materialised without stop section', () {
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
    expect(fill.gradient!.dir, 4);
    expect(fill.gradient!.stops.first.color, const VsdxColor(0xFFF4F9FF));
    expect(fill.gradient!.stops.last.color, const VsdxColor(0xFFDFF4D5));
  });
}
