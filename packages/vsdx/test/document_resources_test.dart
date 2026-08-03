import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:vsdx/src/parser/rich_text_parser.dart';
import 'package:vsdx/src/parser/stylesheet_parser.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

Uint8List _rewritePackage(
  Uint8List input,
  Map<String, Map<String, String>> substitutions,
) {
  final source = ZipDecoder().decodeBytes(input);
  final output = Archive();
  for (final file in source) {
    final raw = file.content;
    var bytes = raw is Uint8List ? raw : Uint8List.fromList(raw as List<int>);
    final edits = substitutions[file.name];
    if (edits != null) {
      var text = utf8.decode(bytes);
      for (final edit in edits.entries) {
        expect(text, contains(edit.key), reason: file.name);
        text = text.replaceAll(edit.key, edit.value);
      }
      bytes = Uint8List.fromList(utf8.encode(text));
    }
    output.addFile(ArchiveFile(file.name, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(output)!);
}

void main() {
  test('classic numeric colour palette matches libvisio', () {
    expect(VsdxColor.tryParse('14'), const VsdxColor(0xFFC0C0C0));
    expect(VsdxColor.tryParse('15'), const VsdxColor(0xFFE6E6E6));
    expect(VsdxColor.tryParse('19'), const VsdxColor(0xFF808080));
    expect(VsdxColor.tryParse('23'), const VsdxColor(0xFF1A1A1A));
  });

  test('document Colors and FaceNames tables resolve like libvisio', () {
    final bytes = _rewritePackage(
      const VsdxWriter().emptyDocument(),
      const {
        'visio/document.xml': {
          '<GlueSettings>9</GlueSettings>':
              '<Cell N="PageColor" V="2"/><GlueSettings>9</GlueSettings>',
          '<FaceNames>': '<Colors><ColorEntry IX="2" RGB="#123456"/></Colors>'
              '<FaceNames><FaceName NameU="Palette Font"/>',
          '<Cell N="FillForegnd" V="#FFFFFF"/>':
              '<Cell N="FillForegnd" V="2"/>',
        },
        'visio/pages/pages.xml': {
          '<Cell N="PageWidth"':
              '<Cell N="PageColor" V="2"/><Cell N="PageWidth"',
          '</PageSheet>': '<Section N="Layer"><Row IX="0">'
              '<Cell N="Name" V="Palette Layer"/>'
              '<Cell N="Color" V="2"/>'
              '</Row></Section></PageSheet>',
        },
        'visio/pages/page1.xml': {
          '<Shapes/>':
              '<Shapes><Shape ID="1" NameU="Palette shape" Type="Shape" '
                  'LineStyle="0" FillStyle="0" TextStyle="0">'
                  '<Cell N="PinX" V="1"/><Cell N="PinY" V="1"/>'
                  '<Cell N="Width" V="1"/><Cell N="Height" V="1"/>'
                  '<Cell N="LineColor" V="15"/>'
                  '<Section N="Character"><Row IX="0">'
                  '<Cell N="Font" V="0"/><Cell N="Color" V="23"/>'
                  '<Cell N="Size" V="0.1666666666666667"/>'
                  '</Row></Section><Text>Palette</Text>'
                  '</Shape></Shapes>',
        },
      },
    );

    final document = const DocumentParser().parse(bytes);
    const custom = VsdxColor(0xFF123456);
    expect(document.settings.defaultPageBackgroundColor, custom);
    expect(document.pages, hasLength(1));
    final page = document.pages.single;
    expect(page.backgroundColor, custom);
    expect(page.layers.single.color, custom);

    final shape = page.shapes.single;
    expect(shape.fill.foreground, custom);
    expect(shape.line.color, const VsdxColor(0xFFE6E6E6));
    final run = shape.richText.runs.single;
    expect(run.charStyle.color, const VsdxColor(0xFF1A1A1A));
    expect(run.charStyle.fontFamily, 'Palette Font');
  });

  test('paragraph bullet fonts and Visio 2002 sentinel match libvisio', () {
    const inherited = VsdxParaStyle(
      bulletStr: '•',
      bulletFont: 'Inherited Font',
    );
    final shape = XmlDocument.parse(
      '<Shape><Section N="Paragraph"><Row IX="0">'
      '<Cell N="Bullet" V="1"/>'
      '<Cell N="BulletStr" V="\uE000"/>'
      '<Cell N="BulletFont" V="1"/>'
      '<Cell N="BulletFontSize" V="-0.5"/>'
      '</Row></Section><Text><pp IX="0"/>Item</Text></Shape>',
    ).rootElement;
    final rich = const RichTextParser(
      fontNames: <int, String>{0: 'Zero Font', 1: 'Wingdings'},
    ).parse(shape, defaultPara: inherited);
    final paragraph = rich.runs.single.paraStyle;
    expect(paragraph.bulletFont, 'Wingdings');
    expect(paragraph.bulletStr, '•');
    expect(paragraph.bulletFontSizeInches, -0.5);
    expect(
      paragraph.effectiveBulletFontSizeInches(0.2),
      closeTo(0.1, 1e-12),
    );

    final zeroFontShape = XmlDocument.parse(
      '<Shape><Section N="Paragraph"><Row IX="0">'
      '<Cell N="BulletFont" V="0"/>'
      '</Row></Section><Text><pp IX="0"/>Item</Text></Shape>',
    ).rootElement;
    final zeroFont = const RichTextParser(
      fontNames: <int, String>{0: 'Zero Font'},
    ).parse(zeroFontShape, defaultPara: inherited);
    expect(zeroFont.runs.single.paraStyle.bulletFont, 'Inherited Font');
  });

  test('stylesheet bullet sentinels do not mask parent values', () {
    final document = XmlDocument.parse(
      '<VisioDocument><StyleSheets>'
      '<StyleSheet ID="1"><Section N="Paragraph"><Row IX="0">'
      '<Cell N="BulletStr" V="•"/>'
      '<Cell N="BulletFont" V="1"/>'
      '</Row></Section></StyleSheet>'
      '<StyleSheet ID="2" TextStyle="1">'
      '<Section N="Paragraph"><Row IX="0">'
      '<Cell N="BulletStr" V="\uE000"/>'
      '<Cell N="BulletFont" V="0"/>'
      '</Row></Section></StyleSheet>'
      '</StyleSheets></VisioDocument>',
    );
    final registry = const StyleSheetParser(
      fontNames: <int, String>{1: 'Wingdings'},
    ).parse(document);
    final paragraph = registry.resolveParaStyle(2)!;
    expect(paragraph.bulletStr, '•');
    expect(paragraph.bulletFont, 'Wingdings');
  });
}
