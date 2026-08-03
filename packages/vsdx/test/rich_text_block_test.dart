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

  test('TxtAngle F=Inh inherits master angle (not cached V=0)', () {
    final el = shape(
      '<Cell N="TxtAngle" V="0" F="Inh"/><Text>Label</Text>',
    );
    final rich = parser.parse(
      el,
      defaultBlock: const VsdxTextBlock(angleRad: math.pi / 2),
    );
    expect(rich.textBlock.angleRad, closeTo(math.pi / 2, 1e-9));
  });

  test('Paragraph HorzAlign=4 remains libvisio full alignment', () {
    final rich = parser.parse(
      shape(
        '<Section N="Paragraph"><Row IX="0">'
        '<Cell N="HorzAlign" V="4"/>'
        '</Row></Section><Text><pp IX="0"/>Distributed</Text>',
      ),
    );
    expect(
      rich.runs.single.paraStyle.horizontalAlign,
      VsdxHorzAlign.full,
    );
  });

  test('TxtWidth F=Inh inherits master width (not cached V=0)', () {
    final el = shape(
      '<Cell N="TxtWidth" V="0" F="Inh"/><Text>Label</Text>',
    );
    final rich = parser.parse(
      el,
      defaultBlock: const VsdxTextBlock(widthInches: 1.25),
    );
    expect(rich.textBlock.widthInches, closeTo(1.25, 1e-9));
  });

  test('LeftMargin F=Inh inherits master margin (not cached V=0)', () {
    final el = shape(
      '<Cell N="LeftMargin" V="0" F="Inh"/><Text>Label</Text>',
    );
    final rich = parser.parse(
      el,
      defaultBlock: const VsdxTextBlock(marginLeftInches: 0.2),
    );
    expect(rich.textBlock.marginLeftInches, closeTo(0.2, 1e-9));
  });

  test('HideText F=Inh inherits master hide (not cached V=0)', () {
    final el = shape(
      '<Cell N="HideText" V="0" F="Inh"/><Text>Label</Text>',
    );
    final rich = parser.parse(
      el,
      defaultBlock: const VsdxTextBlock(hideText: true),
    );
    expect(rich.textBlock.hideText, isTrue);
  });

  test('libvisio true/false spellings parse for text boolean cells', () {
    final rich = parser.parse(
      shape(
        '<Cell N="HideText" V="false"/>'
        '<Section N="Character"><Row IX="0">'
        '<Cell N="Strikethru" V="true"/>'
        '<Cell N="DblUnderline" V="true"/>'
        '<Cell N="DoubleStrikethrough" V="false"/>'
        '<Cell N="Overline" V="true"/>'
        '</Row></Section>'
        '<Text><cp IX="0"/>Label</Text>',
      ),
      defaultBlock: const VsdxTextBlock(hideText: true),
      defaultChar: const VsdxCharStyle(
        strikethrough: false,
        doubleUnderline: false,
        doubleStrikethrough: true,
        overline: false,
      ),
    );
    final style = rich.runs.single.charStyle;

    expect(rich.textBlock.hideText, isFalse);
    expect(style.strikethrough, isTrue);
    expect(style.doubleUnderline, isTrue);
    expect(style.doubleStrikethrough, isFalse);
    expect(style.overline, isTrue);
  });

  test('ordinary trailing whitespace is preserved without a tab marker', () {
    final rich = parser.parse(shape('<Text>Label  \n</Text>'));
    expect(rich.plainText, 'Label  \n');
  });

  test('tp selects a tab set but does not invent a tab character', () {
    final rich = parser.parse(shape('<Text>Label\n<tp IX="0"/></Text>'));
    expect(rich.plainText, 'Label\n');
    expect(rich.runs.single.tabIndices, isEmpty);
  });

  test('literal XML tab uses the active tp tab set like libvisio', () {
    final rich = parser.parse(
      shape('<Text>A<tp IX="3"/>\tB<tp IX="1"/>\tC</Text>'),
    );
    expect(rich.plainText, 'A\tB\tC');
    expect(rich.runs.single.tabIndices, [3, 1]);
  });

  test('tab field alignment covers left center right and decimal', () {
    const sets = [
      VsdxTabSet(
        ix: 7,
        stops: [
          VsdxTabStop(positionInches: 1),
          VsdxTabStop(positionInches: 2, alignment: 1),
          VsdxTabStop(positionInches: 3, alignment: 2),
          VsdxTabStop(positionInches: 4, alignment: 3),
        ],
      ),
    ];
    double start(double current) => visioTabFieldStart(
          tabSets: sets,
          tabSetIx: 7,
          currentPosition: current,
          followingWidth: 0.8,
          decimalPrefixWidth: 0.25,
          defaultTabStop: 0.5,
        );
    expect(start(0.2), closeTo(1, 1e-9));
    expect(start(1.2), closeTo(1.6, 1e-9));
    expect(start(2.2), closeTo(2.2, 1e-9));
    expect(start(3.2), closeTo(3.75, 1e-9));
    expect(
      visioTabFieldStart(
        tabSets: sets,
        tabSetIx: 99,
        currentPosition: 1.1,
        followingWidth: 0.2,
        decimalPrefixWidth: 0.1,
        defaultTabStop: 0.5,
      ),
      closeTo(1.5, 1e-9),
    );
  });

  test('VerticalAlign F=Inh inherits master top (not cached V=1)', () {
    final el = shape(
      '<Cell N="VerticalAlign" V="1" F="Inh"/><Text>Label</Text>',
    );
    final rich = parser.parse(
      el,
      defaultBlock: const VsdxTextBlock(verticalAlign: VsdxVertAlign.top),
    );
    expect(rich.textBlock.verticalAlign, VsdxVertAlign.top);
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

    test('SpLine F=Inh inherits master spacing (ignores stale V)', () {
      final rich = parser.parse(
        shape(
          '<Section N="Paragraph"><Row IX="0">'
          '<Cell N="SpLine" V="-1" F="Inh"/>'
          '</Row></Section>'
          '<Text>Label</Text>',
        ),
        defaultPara: const VsdxParaStyle(lineSpacing: 1.5),
      );
      expect(rich.runs.first.paraStyle.lineSpacing, closeTo(1.5, 1e-9));
    });
  });

  test('Character Size F=Inh inherits master font size', () {
    final rich = parser.parse(
      shape(
        '<Section N="Character"><Row IX="0">'
        '<Cell N="Size" V="0.1" F="Inh"/>'
        '</Row></Section>'
        '<Text>Label</Text>',
      ),
      defaultChar: const VsdxCharStyle(fontSizeInches: 0.25),
    );
    expect(rich.runs.first.charStyle.fontSizeInches, closeTo(0.25, 1e-9));
  });

  test('Character LangID/Color F=Inh inherit master', () {
    final rich = parser.parse(
      shape(
        '<Section N="Character"><Row IX="0">'
        '<Cell N="LangID" V="en-US" F="Inh"/>'
        '<Cell N="Color" V="#000000" F="Inh"/>'
        '<Cell N="Font" V="Arial" F="Inh"/>'
        '</Row></Section>'
        '<Text>Label</Text>',
      ),
      defaultChar: const VsdxCharStyle(
        fontFamily: 'Calibri',
        langId: 'zh-CN',
        color: VsdxColor(0xFFFF0000),
      ),
    );
    final c = rich.runs.first.charStyle;
    expect(c.langId, 'zh-CN');
    expect(c.color?.value, 0xFFFF0000);
    expect(c.fontFamily, 'Calibri');
  });

  test('absent Font stays null (does not materialise defaults)', () {
    final rich = parser.parse(
      shape(
        '<Section N="Character"><Row IX="0">'
        '<Cell N="Size" V="0.1667"/>'
        '</Row></Section>'
        '<Text>Label</Text>',
      ),
      defaultChar: const VsdxCharStyle(fontFamily: 'Arial'),
    );
    expect(rich.runs.first.charStyle.fontFamily, isNull);
  });

  test('absent TextBkgnd inherits master colour', () {
    final rich = parser.parse(
      shape('<Text>Label</Text>'),
      defaultBlock: const VsdxTextBlock(
        backgroundColor: VsdxColor(0xFFFFFF00),
      ),
    );
    expect(rich.textBlock.backgroundColor?.value, 0xFFFFFF00);
  });

  test('explicit TextBkgnd=0 does not inherit master colour', () {
    final rich = parser.parse(
      shape('<Cell N="TextBkgnd" V="0"/><Text>Label</Text>'),
      defaultBlock: const VsdxTextBlock(
        backgroundColor: VsdxColor(0xFFFFFF00),
      ),
    );
    expect(rich.textBlock.backgroundColor, isNull);
  });

  test('TextBkgnd F=Inh inherits master colour (not cached clear)', () {
    final rich = parser.parse(
      shape('<Cell N="TextBkgnd" V="0" F="Inh"/><Text>Label</Text>'),
      defaultBlock: const VsdxTextBlock(
        backgroundColor: VsdxColor(0xFFFFFF00),
      ),
    );
    expect(rich.textBlock.backgroundColor?.value, 0xFFFFFF00);
  });

  test('Tabs Alignment F=Inh inherits master stop', () {
    final rich = parser.parse(
      shape(
        '<Section N="Tabs">'
        '<Row IX="0">'
        '<Cell N="Position1" V="0" F="Inh"/>'
        '<Cell N="Alignment1" V="0" F="Inh"/>'
        '<Cell N="Position2" V="1.5"/>'
        '<Cell N="Alignment2" V="2"/>'
        '</Row>'
        '</Section>'
        '<Text>A\tB</Text>',
      ),
      inheritTabs: const [
        VsdxTabSet(
          ix: 0,
          stops: [
            VsdxTabStop(positionInches: 0.5, alignment: 1),
            VsdxTabStop(positionInches: 1.0, alignment: 0),
          ],
        ),
      ],
    );
    expect(rich.tabSets, hasLength(1));
    expect(rich.tabSets.single.stops, hasLength(2));
    expect(rich.tabSets.single.stops[0].positionInches, closeTo(0.5, 1e-9));
    expect(rich.tabSets.single.stops[0].alignment, 1);
    expect(rich.tabSets.single.stops[1].positionInches, closeTo(1.5, 1e-9));
    expect(rich.tabSets.single.stops[1].alignment, 2);
  });
}
