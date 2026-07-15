import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

/// Binding a shape's fill / line / text to a document **theme slot** must
/// survive a save→reopen. The writer's patch path used to ignore a null
/// (theme-bound) colour, so re-theming an existing shape silently reverted to
/// its old solid colour — making the "Theme" swatch look identical to a plain
/// fill colour once the file was reopened.
Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

void main() {
  final parser = DocumentParser();
  final writer = VsdxWriter();

  VsdxShape firstFilled(VsdxPage page) =>
      page.shapes.firstWhere((s) => !s.is1D);

  test('emit path: theme-bound fill round-trips with its slot', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final rect = VsdxShapeFactory.rectangle(
      id: id, pinX: 2, pinY: 2, width: 2, height: 1,
    ).copyWith(fill: const VsdxFill(themeForegroundIndex: ThemeSlot.accent1));
    doc = doc
        .copyWith(theme: VsdxTheme.office)
        .replacePage(0, doc.pages.first.addShape(rect));
    final after = parser
        .parse(writer.write(originalBytes: blank, edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(after.fill.themeForegroundIndex, ThemeSlot.accent1);
    expect(after.fill.foreground, isNull);
  });

  test('patch path: re-binding an existing fill to a theme slot round-trips',
      () {
    final bytes = _fixture('test1.vsdx');
    final doc = parser.parse(bytes);
    final page = doc.pages.first;
    final target = firstFilled(page);
    final edited = doc.copyWith(theme: VsdxTheme.office).replacePage(
          0,
          page.updateShapeById(
            target.id,
            (s) => s.copyWith(
              fill: s.fill.withThemeForeground(ThemeSlot.accent2),
            ),
          ),
        );
    final after = parser
        .parse(writer.write(originalBytes: bytes, edited: edited))
        .pages
        .first
        .findShapeById(target.id)!;
    expect(after.fill.themeForegroundIndex, ThemeSlot.accent2);
    expect(after.fill.foreground, isNull,
        reason: 'stale solid FillForegnd must be replaced by the theme slot');
  });

  test('patch path: re-binding line + text to theme slots round-trips', () {
    final bytes = _fixture('test1.vsdx');
    final doc = parser.parse(bytes);
    final page = doc.pages.first;
    final target =
        page.shapes.firstWhere((s) => !s.is1D && s.richText.runs.isNotEmpty);
    final edited = doc.copyWith(theme: VsdxTheme.office).replacePage(
          0,
          page.updateShapeById(
            target.id,
            (s) => s.copyWith(
              line: s.line.withThemeColor(ThemeSlot.accent3),
              richText: s.richText.copyWith(runs: <VsdxTextRun>[
                for (final r in s.richText.runs)
                  r.copyWith(
                    charStyle: r.charStyle.withThemeColor(ThemeSlot.accent4),
                  ),
              ]),
            ),
          ),
        );
    final after = parser
        .parse(writer.write(originalBytes: bytes, edited: edited))
        .pages
        .first
        .findShapeById(target.id)!;
    expect(after.line.themeColorIndex, ThemeSlot.accent3);
    expect(after.line.color, isNull);
    expect(after.richText.runs.first.charStyle.themeColorIndex,
        ThemeSlot.accent4);
  });

  test('switching a theme-bound fill back to a solid colour round-trips', () {
    final bytes = _fixture('test1.vsdx');
    final doc = parser.parse(bytes);
    final page = doc.pages.first;
    final target = firstFilled(page);
    // First bind to a theme slot, then override with an explicit colour.
    final themed = page.updateShapeById(
      target.id,
      (s) => s.copyWith(fill: s.fill.withThemeForeground(ThemeSlot.accent5)),
    );
    final solid = themed.updateShapeById(
      target.id,
      (s) => s.copyWith(
        fill: s.fill.withSolidForeground(const VsdxColor(0xFF123456)),
      ),
    );
    final edited = doc.copyWith(theme: VsdxTheme.office).replacePage(0, solid);
    final after = parser
        .parse(writer.write(originalBytes: bytes, edited: edited))
        .pages
        .first
        .findShapeById(target.id)!;
    expect(after.fill.foreground?.value, 0xFF123456);
    expect(after.fill.themeForegroundIndex, isNull,
        reason: 'explicit colour must clear the THEMEVAL binding');
  });

  test('same theme slot resolves to different colours per document theme', () {
    final office = VsdxTheme.office.resolve(ThemeSlot.accent1);
    final other = VsdxTheme.builtins
        .firstWhere((t) => t.name != 'Office')
        .theme
        .resolve(ThemeSlot.accent1);
    expect(office, isNotNull);
    expect(other, isNotNull);
    expect(office!.value == other!.value, isFalse);
  });
}
