import 'package:test/test.dart';
import 'package:vsdx/src/parser/style_parser.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

void main() {
  const style = StyleParser();

  final masterGrad = VsdxGradient(
    type: VsdxGradientType.linear,
    angleRad: 0,
    stops: const [
      VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
      VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
    ],
  );

  test('FillGradientEnabled=0 does not inherit Master gradient', () {
    final el = XmlDocument.parse(
      '<Shape>'
      '<Cell N="FillPattern" V="1"/>'
      '<Cell N="FillGradientEnabled" V="0"/>'
      '</Shape>',
    ).rootElement;
    final fill = style.parseFill(
      el,
      defaults: VsdxFill(pattern: 1, gradient: masterGrad),
    );
    expect(fill.gradient, isNull);
  });

  test('missing FillGradientEnabled still inherits Master gradient', () {
    final el = XmlDocument.parse(
      '<Shape><Cell N="FillPattern" V="1"/></Shape>',
    ).rootElement;
    final fill = style.parseFill(
      el,
      defaults: VsdxFill(pattern: 1, gradient: masterGrad),
    );
    expect(fill.gradient, isNotNull);
    expect(fill.gradient!.stops, hasLength(2));
  });

  test('LineGradientEnabled=0 does not inherit Master gradient', () {
    final el = XmlDocument.parse(
      '<Shape>'
      '<Cell N="LinePattern" V="1"/>'
      '<Cell N="LineGradientEnabled" V="0"/>'
      '</Shape>',
    ).rootElement;
    final line = style.parseLine(
      el,
      defaults: VsdxLine(gradient: masterGrad),
    );
    expect(line.gradient, isNull);
  });

  test('LineWeight F=Inh inherits Master weight (not cached V=0)', () {
    final el = XmlDocument.parse(
      '<Shape>'
      '<Cell N="LinePattern" V="1"/>'
      '<Cell N="LineWeight" V="0" F="Inh"/>'
      '</Shape>',
    ).rootElement;
    final line = style.parseLine(
      el,
      defaults: const VsdxLine(weightInches: 0.05),
    );
    expect(line.weightInches, closeTo(0.05, 1e-9));
  });
}
