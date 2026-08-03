import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:vsdx/src/parser/theme_parser.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

void main() {
  const writer = VsdxWriter();
  const parser = DocumentParser();

  test('empty doc + Green theme round-trips via theme1.xml', () {
    final blank = writer.emptyDocument();
    final baseline = parser.parse(blank);
    expect(baseline.theme.isEmpty, isTrue);

    final edited = baseline.copyWith(theme: VsdxTheme.green);
    final out = writer.write(originalBytes: blank, edited: edited);
    final reopened = parser.parse(out);

    expect(
      reopened.theme.resolve(ThemeSlot.accent1)?.value,
      VsdxTheme.green.resolve(ThemeSlot.accent1)!.value,
    );
    expect(
      reopened.theme.resolve(ThemeSlot.dk2)?.value,
      VsdxTheme.green.resolve(ThemeSlot.dk2)!.value,
    );

    final pkg = VsdxPackage.open(out);
    expect(pkg.readPartBytes('/visio/theme/theme1.xml'), isNotNull);
    final ct = pkg.readPartXml('/[Content_Types].xml')!.toXmlString();
    expect(ct, contains('/visio/theme/theme1.xml'));
    expect(ct, contains('officedocument.theme+xml'));
    final rels =
        pkg.readPartXml('/visio/_rels/document.xml.rels')!.toXmlString();
    expect(rels, contains('/theme'));
    expect(rels, contains('theme/theme1.xml'));
  });

  test('patching an existing theme keeps fontScheme / fmtScheme', () {
    final withTheme = _packageWithMarkedTheme(VsdxTheme.office);
    final baseline = parser.parse(withTheme);
    expect(baseline.theme.resolve(ThemeSlot.accent1), isNotNull);

    final edited = baseline.copyWith(theme: VsdxTheme.green);
    final out = writer.write(originalBytes: withTheme, edited: edited);

    final themeXml = utf8.decode(
      VsdxPackage.open(out).readPartBytes('/visio/theme/theme1.xml')!,
    );
    expect(themeXml, contains('<a:fontScheme'));
    expect(themeXml, contains('KEEP_FONT_MARKER'));
    expect(themeXml, contains('<a:fmtScheme'));
    expect(themeXml, contains('KEEP_FMT_MARKER'));
    expect(themeXml.toUpperCase(), contains('70AD47'));

    final reopened = parser.parse(out);
    expect(
      reopened.theme.resolve(ThemeSlot.accent1)?.value,
      VsdxTheme.green.resolve(ThemeSlot.accent1)!.value,
    );
  });

  test('unchanged theme stays byte-passthrough', () {
    final withTheme = _packageWithTheme(VsdxTheme.office);
    final before =
        VsdxPackage.open(withTheme).readPartBytes('/visio/theme/theme1.xml')!;
    final baseline = parser.parse(withTheme);
    final page = baseline.pages.first;
    final id = page.nextFreeShapeId();
    final edited = baseline.replacePage(
      0,
      page.addShape(VsdxShapeFactory.rectangle(
        id: id,
        pinX: 1,
        pinY: 1,
        width: 1,
        height: 1,
      )),
    );
    final out = writer.write(originalBytes: withTheme, edited: edited);
    final after =
        VsdxPackage.open(out).readPartBytes('/visio/theme/theme1.xml')!;
    expect(after, orderedEquals(before));
  });

  test('ThemeSerializer.emit parses back to the same palette', () {
    final xml = ThemeSerializer.emit(VsdxTheme.blue, name: 'Blue');
    final parsed = ThemeParser.parseDocument(XmlDocument.parse(xml));
    expect(ThemeSerializer.themesEqual(parsed, VsdxTheme.blue), isTrue);
  });

  test('ThemeParser resolves QuickStyle variation colours by page index', () {
    final parsed = ThemeParser.parseDocument(XmlDocument.parse('''
      <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
          xmlns:vt="http://schemas.microsoft.com/office/visio/2012/theme">
        <a:themeElements>
          <a:clrScheme name="Variation test">
            <a:dk1><a:srgbClr val="000000"/></a:dk1>
            <a:extLst><a:ext><vt:variationClrSchemeLst>
              <vt:variationClrScheme>
                <vt:varColor1><a:srgbClr val="112233"/></vt:varColor1>
                <vt:varColor7><a:srgbClr val="778899"/></vt:varColor7>
              </vt:variationClrScheme>
              <vt:variationClrScheme>
                <vt:varColor1><a:srgbClr val="AABBCC"/></vt:varColor1>
                <vt:varColor7><a:srgbClr val="DDEEFF"/></vt:varColor7>
              </vt:variationClrScheme>
            </vt:variationClrSchemeLst></a:ext></a:extLst>
          </a:clrScheme>
        </a:themeElements>
      </a:theme>
    '''));

    expect(parsed.variationColors, hasLength(2));
    expect(parsed.resolve(100)?.value, 0xFF112233);
    expect(parsed.resolve(200, variationIndex: 1)?.value, 0xFFAABBCC);
    expect(parsed.resolve(106)?.value, 0xFF778899);
    expect(parsed.resolve(206, variationIndex: 1)?.value, 0xFFDDEEFF);
    expect(
      parsed.resolve(200, variationIndex: 99)?.value,
      0xFF112233,
      reason: 'libvisio falls back to variation zero',
    );
  });

  test('ThemeParser resolves variation fill style matrix like libvisio', () {
    final parsed = ThemeParser.parseDocument(XmlDocument.parse('''
      <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
          xmlns:vt="http://schemas.microsoft.com/office/visio/2012/theme">
        <a:themeElements>
          <a:clrScheme name="Matrix test">
            <a:dk1><a:srgbClr val="000000"/></a:dk1>
            <a:extLst><a:ext><vt:variationClrSchemeLst>
              <vt:variationClrScheme>
                <vt:varColor1><a:srgbClr val="A5A5A5"/></vt:varColor1>
              </vt:variationClrScheme>
            </vt:variationClrSchemeLst></a:ext></a:extLst>
          </a:clrScheme>
          <a:fmtScheme name="Matrix test"><a:fillStyleLst>
            <a:solidFill><a:srgbClr val="111111"/></a:solidFill>
            <a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill>
          </a:fillStyleLst></a:fmtScheme>
          <a:extLst><a:ext><vt:variationStyleSchemeLst>
            <vt:variationStyleScheme>
              <vt:varStyle fillIdx="1"/><vt:varStyle fillIdx="1"/>
              <vt:varStyle fillIdx="1"/><vt:varStyle fillIdx="1"/>
            </vt:variationStyleScheme>
            <vt:variationStyleScheme>
              <vt:varStyle fillIdx="2"/><vt:varStyle fillIdx="1"/>
              <vt:varStyle fillIdx="1"/><vt:varStyle fillIdx="1"/>
            </vt:variationStyleScheme>
          </vt:variationStyleSchemeLst></a:ext></a:extLst>
        </a:themeElements>
      </a:theme>
    '''));

    expect(parsed.resolveFill(100, fillMatrix: 1)?.value, 0xFF111111);
    expect(
      parsed
          .resolveFill(
            100,
            variationColorIndex: 0,
            variationStyleIndex: 1,
            fillMatrix: 100,
          )
          ?.value,
      0xFFFFFFFF,
    );
  });
}

Uint8List _packageWithTheme(VsdxTheme theme) {
  const writer = VsdxWriter();
  final blank = writer.emptyDocument();
  return writer.write(
    originalBytes: blank,
    edited: DocumentParser().parse(blank).copyWith(theme: theme),
  );
}

/// Like [_packageWithTheme], but renames font/fmt schemes so patch tests can
/// prove those sections survive a clrScheme update.
Uint8List _packageWithMarkedTheme(VsdxTheme theme) {
  final withTheme = _packageWithTheme(theme);
  var xml = utf8.decode(
    VsdxPackage.open(withTheme).readPartBytes('/visio/theme/theme1.xml')!,
  );
  xml = xml.replaceFirst(
    RegExp(r'<a:fontScheme name="[^"]*"'),
    '<a:fontScheme name="KEEP_FONT_MARKER"',
  );
  xml = xml.replaceFirst(
    RegExp(r'<a:fmtScheme name="[^"]*"'),
    '<a:fmtScheme name="KEEP_FMT_MARKER"',
  );
  return _rezipWith(withTheme, 'visio/theme/theme1.xml', utf8.encode(xml));
}

Uint8List _rezipWith(Uint8List src, String partName, List<int> newBytes) {
  final archive = ZipDecoder().decodeBytes(src);
  final out = Archive();
  final target = partName.startsWith('/') ? partName.substring(1) : partName;
  for (final f in archive) {
    if (f.name == target) {
      out.addFile(ArchiveFile(f.name, newBytes.length, newBytes));
    } else {
      out.addFile(ArchiveFile(f.name, f.size, f.content));
    }
  }
  return Uint8List.fromList(ZipEncoder().encode(out)!);
}
