import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';
import 'package:vsdx/src/parser/stylesheet_parser.dart';
import 'package:xml/xml.dart';

void main() {
  test('resolveFill walks FillStyle parent chain like resolveLine', () {
    const parent = VsdxStyleSheet(
      id: 1,
      name: 'ParentFill',
      fill: VsdxFill(
        foreground: VsdxColor(0xFFE53935),
        pattern: 1,
      ),
    );
    const child = VsdxStyleSheet(
      id: 2,
      name: 'ChildFill',
      fillStyleId: 1,
      fill: VsdxFill(pattern: 2),
    );
    const registry = StyleSheetRegistry(<int, VsdxStyleSheet>{
      1: parent,
      2: child,
    });
    final fill = registry.resolveFill(2)!;
    expect(fill.pattern, 2);
    expect(fill.foreground?.value, 0xFFE53935);
  });

  test('resolveLine still resolves weight/colour', () {
    const sheet = VsdxStyleSheet(
      id: 3,
      name: 'LineSheet',
      line: VsdxLine(
        color: VsdxColor(0xFF1565C0),
        weightInches: 0.02,
        pattern: 2,
      ),
    );
    const registry = StyleSheetRegistry(<int, VsdxStyleSheet>{3: sheet});
    final line = registry.resolveLine(3)!;
    expect(line.color?.value, 0xFF1565C0);
    expect(line.weightInches, closeTo(0.02, 1e-9));
    expect(line.pattern, 2);
  });

  test('resolveLine skips F=Inh LineWeight and takes parent', () {
    const parent = VsdxStyleSheet(
      id: 10,
      name: 'ParentLine',
      line: VsdxLine(weightInches: 0.05, pattern: 1),
      lineDefinedCells: {'LineWeight', 'LinePattern'},
    );
    const child = VsdxStyleSheet(
      id: 11,
      name: 'ChildLine',
      lineStyleId: 10,
      // SoftEdges only — LineWeight Inh is not in defined cells.
      line: VsdxLine(softEdgesInches: 0.1, weightInches: 0.01),
      lineDefinedCells: {'SoftEdgesSize'},
    );
    const registry = StyleSheetRegistry(<int, VsdxStyleSheet>{
      10: parent,
      11: child,
    });
    final line = registry.resolveLine(11)!;
    expect(line.weightInches, closeTo(0.05, 1e-9));
    expect(line.softEdgesInches, closeTo(0.1, 1e-9));
  });

  test('resolveLine picks up Rounding from LineStyle chain', () {
    const sheet = VsdxStyleSheet(
      id: 12,
      name: 'RoundLine',
      line: VsdxLine(roundingInches: 0.125, weightInches: 0.01),
      lineDefinedCells: {'Rounding', 'LineWeight'},
    );
    const registry = StyleSheetRegistry(<int, VsdxStyleSheet>{12: sheet});
    final line = registry.resolveLine(12)!;
    expect(line.roundingInches, closeTo(0.125, 1e-9));
  });

  test('parses direct StyleSheet line fill and shadow cells', () {
    final xml = XmlDocument.parse('''
      <VisioDocument>
        <StyleSheets>
          <StyleSheet ID="0" NameU="No Style">
            <Cell N="LineWeight" V="0.01041666666666667"/>
            <Cell N="LineColor" V="0"/>
            <Cell N="LinePattern" V="2"/>
            <Cell N="LineCap" V="2"/>
            <Cell N="BeginArrow" V="4"/>
            <Cell N="EndArrow" V="5"/>
            <Cell N="LineColorTrans" V="0.25"/>
            <Cell N="FillForegnd" V="1"/>
            <Cell N="FillBkgnd" V="2"/>
            <Cell N="FillPattern" V="3"/>
            <Cell N="FillForegndTrans" V="0.4"/>
            <Cell N="FillBkgndTrans" V="0.6"/>
            <Cell N="ShdwForegnd" V="3"/>
            <Cell N="ShdwPattern" V="1"/>
            <Cell N="ShapeShdwOffsetX" V="0.125"/>
            <Cell N="ShapeShdwOffsetY" V="-0.25"/>
            <Cell N="ShdwForegndTrans" V="0.5"/>
            <Cell N="LeftMargin" V="0.2"/>
            <Cell N="RightMargin" V="0.3"/>
            <Cell N="TopMargin" V="0.4"/>
            <Cell N="BottomMargin" V="0.5"/>
            <Cell N="VerticalAlign" V="2"/>
            <Cell N="TextBkgnd" V="2"/>
            <Cell N="TextBkgndTrans" V="0.25"/>
            <Cell N="DefaultTabStop" V="0.75"/>
            <Cell N="TextDirection" V="1"/>
            <Section N="Character">
              <Row IX="0">
                <Cell N="Font" V="Calibri"/>
                <Cell N="Size" V="0.2"/>
                <Cell N="Style" V="15"/>
                <Cell N="Color" V="#123456" F="THEMEGUARD(RGB(18,52,86))"/>
                <Cell N="Strikethru" V="1"/>
                <Cell N="DblUnderline" V="1"/>
                <Cell N="DoubleStrikethrough" V="1"/>
                <Cell N="Overline" V="1"/>
                <Cell N="ColorTrans" V="0.25"/>
                <Cell N="Letterspace" V="0.02"/>
                <Cell N="Pos" V="1"/>
                <Cell N="Case" V="1"/>
                <Cell N="FontScale" V="0.8"/>
                <Cell N="AsianFont" V="SimSun"/>
                <Cell N="ComplexScriptFont" V="Arial"/>
                <Cell N="LangID" V="zh-CN"/>
                <Cell N="ComplexScriptSize" V="0.18"/>
              </Row>
            </Section>
            <Section N="Paragraph">
              <Row IX="0">
                <Cell N="HorzAlign" V="1"/>
                <Cell N="IndFirst" V="0.1"/>
                <Cell N="SpLine" V="-1.5"/>
                <Cell N="Bullet" V="2"/>
                <Cell N="BulletStr" V="•"/>
              </Row>
            </Section>
          </StyleSheet>
          <StyleSheet ID="3" NameU="Normal" LineStyle="0" FillStyle="0" TextStyle="0">
            <Cell N="LineWeight" V="Themed" F="Inh"/>
            <Cell N="FillPattern" V="Themed" F="Inh"/>
            <Cell N="ShdwPattern" V="Themed" F="Inh"/>
            <Section N="Character">
              <Row IX="0">
                <Cell N="Size" V="0.2" F="Inh"/>
                <Cell N="Case" V="2"/>
              </Row>
            </Section>
          </StyleSheet>
        </StyleSheets>
      </VisioDocument>
    ''');
    final registry = const StyleSheetParser().parse(xml);

    final line = registry.resolveLine(3)!;
    expect(line.weightInches, closeTo(0.01041666666666667, 1e-12));
    expect(line.color, VsdxColor.black);
    expect(line.pattern, 2);
    expect(line.cap, LineCap.extended);
    expect(line.beginArrow, 4);
    expect(line.endArrow, 5);
    expect(line.transparency, closeTo(0.25, 1e-12));

    final fill = registry.resolveFill(3)!;
    expect(fill.foreground, VsdxColor.white);
    expect(fill.background, const VsdxColor(0xFFFF0000));
    expect(fill.pattern, 3);
    expect(fill.foregroundTransparency, closeTo(0.4, 1e-12));
    expect(fill.backgroundTransparency, closeTo(0.6, 1e-12));

    final shadow = registry.resolveShadow(3)!;
    expect(shadow.enabled, isTrue);
    expect(shadow.color, const VsdxColor(0xFF00FF00));
    expect(shadow.offsetXInches, closeTo(0.125, 1e-12));
    expect(shadow.offsetYInches, closeTo(-0.25, 1e-12));
    expect(shadow.transparency, closeTo(0.5, 1e-12));

    final para = registry.resolveParaStyle(3)!;
    expect(para.horizontalAlign, VsdxHorzAlign.center);
    expect(para.indentFirstInches, closeTo(0.1, 1e-12));
    expect(para.lineSpacing, closeTo(1.5, 1e-12));
    expect(para.bullet, 2);
    expect(para.bulletStr, '•');

    final block = registry.resolveTextBlock(3)!;
    expect(block.marginLeftInches, closeTo(0.2, 1e-12));
    expect(block.marginRightInches, closeTo(0.3, 1e-12));
    expect(block.marginTopInches, closeTo(0.4, 1e-12));
    expect(block.marginBottomInches, closeTo(0.5, 1e-12));
    expect(block.verticalAlign, VsdxVertAlign.bottom);
    expect(block.backgroundColor, const VsdxColor(0xFFFF0000));
    expect(block.backgroundTransparency, closeTo(0.25, 1e-12));
    expect(block.defaultTabStopInches, closeTo(0.75, 1e-12));
    expect(block.textDirection, 1);

    final char = registry.resolveCharStyle(3)!;
    expect(char.fontFamily, 'Calibri');
    expect(char.fontSizeInches, closeTo(0.2, 1e-12));
    expect(char.style.bold, isTrue);
    expect(char.style.italic, isTrue);
    expect(char.style.smallCaps, isTrue);
    expect(char.underline, isTrue);
    expect(char.color, const VsdxColor(0xFF123456));
    expect(char.themeColorIndex, isNull);
    expect(char.strikethrough, isTrue);
    expect(char.doubleUnderline, isTrue);
    expect(char.doubleStrikethrough, isTrue);
    expect(char.overline, isTrue);
    expect(char.transparency, closeTo(0.25, 1e-12));
    expect(char.letterSpacingInches, closeTo(0.02, 1e-12));
    expect(char.position, VsdxTextPosition.superscript);
    expect(char.textCase, VsdxTextCase.initialCaps);
    expect(char.fontScale, closeTo(0.8, 1e-12));
    expect(char.asianFont, 'SimSun');
    expect(char.complexScriptFont, 'Arial');
    expect(char.langId, 'zh-CN');
    expect(char.complexScriptSizeInches, closeTo(0.18, 1e-12));
  });
}
