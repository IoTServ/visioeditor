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
