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

  test('FillPattern F=Inh inherits Master hatch (not cached V=1)', () {
    final el = XmlDocument.parse(
      '<Shape>'
      '<Cell N="FillPattern" V="1" F="Inh"/>'
      '</Shape>',
    ).rootElement;
    final fill = style.parseFill(
      el,
      defaults: const VsdxFill(pattern: 7),
    );
    expect(fill.pattern, 7);
  });

  test('LinePattern/LineCap/CompoundType F=Inh inherit Master', () {
    final el = XmlDocument.parse(
      '<Shape>'
      '<Cell N="LinePattern" V="1" F="Inh"/>'
      '<Cell N="LineCap" V="0" F="Inh"/>'
      '<Cell N="CompoundType" V="0" F="Inh"/>'
      '</Shape>',
    ).rootElement;
    final line = style.parseLine(
      el,
      defaults: const VsdxLine(
        pattern: 4,
        cap: LineCap.square,
        compoundType: 2,
      ),
    );
    expect(line.pattern, 4);
    expect(line.cap, LineCap.square);
    expect(line.compoundType, 2);
  });

  test('BeginArrow/EndArrow F=Inh inherit Master arrows', () {
    final el = XmlDocument.parse(
      '<Shape>'
      '<Cell N="BeginArrow" V="0" F="Inh"/>'
      '<Cell N="EndArrow" V="0" F="Inh"/>'
      '<Cell N="BeginArrowSize" V="2" F="Inh"/>'
      '<Cell N="LineColorTrans" V="0" F="Inh"/>'
      '</Shape>',
    ).rootElement;
    final line = style.parseLine(
      el,
      defaults: const VsdxLine(
        beginArrow: 5,
        endArrow: 4,
        beginArrowSizeInches: 0.225,
        transparency: 0.35,
      ),
    );
    expect(line.beginArrow, 5);
    expect(line.endArrow, 4);
    expect(line.beginArrowSizeInches, closeTo(0.225, 1e-9));
    expect(line.transparency, closeTo(0.35, 1e-9));
  });

  test('FillForegndTrans F=Inh inherits Master transparency', () {
    final el = XmlDocument.parse(
      '<Shape>'
      '<Cell N="FillPattern" V="1"/>'
      '<Cell N="FillForegndTrans" V="0" F="Inh"/>'
      '</Shape>',
    ).rootElement;
    final fill = style.parseFill(
      el,
      defaults: const VsdxFill(pattern: 1, foregroundTransparency: 0.4),
    );
    expect(fill.foregroundTransparency, closeTo(0.4, 1e-9));
  });

  test('GlowColorTrans F=Inh inherits Master transparency', () {
    final el = XmlDocument.parse(
      '<Shape>'
      '<Cell N="GlowSize" V="0.1"/>'
      '<Cell N="GlowColorTrans" V="0" F="Inh"/>'
      '</Shape>',
    ).rootElement;
    final glow = style.parseGlow(
      el,
      defaults: const VsdxGlow(
        enabled: true,
        sizeInches: 0.1,
        transparency: 0.55,
      ),
    );
    expect(glow.enabled, isTrue);
    expect(glow.transparency, closeTo(0.55, 1e-9));
  });
}
