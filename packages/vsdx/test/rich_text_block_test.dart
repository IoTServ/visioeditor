import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';
import 'package:vsdx/src/parser/rich_text_parser.dart';
import 'package:xml/xml.dart';

/// The text-block transform (most importantly `TxtAngle`, which drives vertical
/// / rotated labels) must inherit from the Master when the instance omits it —
/// otherwise a shape whose text orientation lives on its Master renders
/// horizontally. Matches Visio / libvisio cell inheritance.
void main() {
  const parser = RichTextParser();

  XmlElement shape(String inner) =>
      XmlDocument.parse('<Shape>$inner</Shape>').rootElement;

  test('TxtAngle is inherited from the master when the instance omits it', () {
    final el = shape('<Text>Label</Text>'); // own text, no TxtAngle cell
    final rich = parser.parse(
      el,
      defaultBlock: const VsdxTextBlock(angleRad: math.pi / 2),
    );
    expect(rich.runs, isNotEmpty);
    expect(rich.textBlock.angleRad, closeTo(math.pi / 2, 1e-9));
  });

  test('an explicit TxtAngle on the instance overrides the master', () {
    final el = shape('<Cell N="TxtAngle" V="0"/><Text>Label</Text>');
    final rich = parser.parse(
      el,
      defaultBlock: const VsdxTextBlock(angleRad: math.pi / 2),
    );
    expect(rich.textBlock.angleRad, 0);
  });

  test('vertical align + margins also inherit from the master', () {
    final el = shape('<Text>Label</Text>');
    final rich = parser.parse(
      el,
      defaultBlock: const VsdxTextBlock(
        verticalAlign: VsdxVertAlign.top,
        marginLeftInches: 0.2,
      ),
    );
    expect(rich.textBlock.verticalAlign, VsdxVertAlign.top);
    expect(rich.textBlock.marginLeftInches, closeTo(0.2, 1e-9));
  });

  group('SpLine line spacing', () {
    XmlElement paraShape(String spLineV) => shape(
          '<Section N="Paragraph"><Row IX="0">'
          '<Cell N="SpLine" V="$spLineV"/>'
          '</Row></Section>'
          '<Text>Wrapped label</Text>',
        );

    test('a negative SpLine becomes a positive line-height multiple', () {
      // Visio stores 120% line spacing as -1.2; it must map to a *positive*
      // Flutter height multiple, otherwise wrapped lines stack upward.
      final para = parser.parse(paraShape('-1.2')).runs.first.paraStyle;
      expect(para.lineSpacing, closeTo(1.2, 1e-9));
      expect(para.lineSpacingAbsoluteInches, 0);
    });

    test('a zero SpLine is single ("set solid") spacing', () {
      final para = parser.parse(paraShape('0')).runs.first.paraStyle;
      expect(para.lineSpacing, 1.0);
      expect(para.lineSpacingAbsoluteInches, 0);
    });

    test('a positive SpLine is absolute inches, kept off the multiple', () {
      final para = parser.parse(paraShape('0.25')).runs.first.paraStyle;
      expect(para.lineSpacingAbsoluteInches, closeTo(0.25, 1e-9));
      expect(para.lineSpacing, 1.0);
    });

    test('a missing SpLine inherits the master paragraph spacing', () {
      final rich = parser.parse(
        shape('<Text>Label</Text>'),
        defaultPara: const VsdxParaStyle(lineSpacing: 1.5),
      );
      expect(rich.runs.first.paraStyle.lineSpacing, closeTo(1.5, 1e-9));
    });
  });
}
