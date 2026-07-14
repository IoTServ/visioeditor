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
}
