import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
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

  test('FillPattern THEMEVAL does not resurrect on second save', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ),
      ),
    );
    var mid = writer.write(originalBytes: blank, edited: doc);
    // Inject theme formula on FillPattern.
    final archive = ZipDecoder().decodeBytes(mid);
    final pageFile =
        archive.firstWhere((f) => f.name.contains('pages/page1.xml'));
    var pageXml = utf8.decode(pageFile.content as List<int>);
    if (pageXml.contains('N="FillPattern"')) {
      pageXml = pageXml.replaceFirst(
        RegExp(r'<Cell N="FillPattern"[^/]*/>'),
        '<Cell N="FillPattern" V="1" F="THEMEVAL()"/>',
      );
    } else {
      pageXml = pageXml.replaceFirst(
        '</Shape>',
        '<Cell N="FillPattern" V="1" F="THEMEVAL()"/></Shape>',
      );
    }
    mid = Uint8List.fromList(
      ZipEncoder().encode(
        () {
          final out = Archive();
          for (final f in archive) {
            if (f.name == pageFile.name) {
              final bytes = utf8.encode(pageXml);
              out.addFile(ArchiveFile(f.name, bytes.length, bytes));
            } else {
              out.addFile(ArchiveFile(f.name, f.size, f.content));
            }
          }
          return out;
        }(),
      )!,
    );
    doc = parser.parse(mid);
    // Mimic setNoFill: pattern=0 but stale formulas map kept.
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(fill: s.fill.copyWith(pattern: 0)),
      ),
    );
    final once = writer.write(originalBytes: mid, edited: doc);
    final twice = writer.write(originalBytes: once, edited: doc);
    final outXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(twice)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(r'N="FillPattern"[^>]*F="THEMEVAL').hasMatch(outXml),
      isFalse,
    );
    expect(parser.parse(twice).pages.first.findShapeById(id)!.fill.pattern, 0);
  });

  test('theme→solid survives a second save without reparse', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
          fill: const VsdxFill(themeForegroundIndex: ThemeSlot.accent1),
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    // Reparse so formulas carry THEMEVAL, then override to solid in memory.
    doc = parser.parse(mid);
    final solidPage = doc.pages.first.updateShapeById(
      id,
      (s) => s.copyWith(
        fill: s.fill.withSolidForeground(const VsdxColor(0xFF00FF00)),
      ),
    );
    doc = doc.replacePage(0, solidPage);
    final once = writer.write(originalBytes: mid, edited: doc);
    // Second save with the same in-memory model (stale formulas map).
    final twice = writer.write(originalBytes: once, edited: doc);
    final after = parser.parse(twice).pages.first.findShapeById(id)!;
    expect(after.fill.foreground?.value, 0xFF00FF00);
    expect(after.fill.themeForegroundIndex, isNull);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(twice)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(r'N="FillForegnd"[^>]*F="THEMEVAL').hasMatch(pageXml),
      isFalse,
      reason: 'second save must not resurrect THEMEVAL over solid V',
    );
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

  test('theme→solid survives group rebuild without THEMEVAL', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final a = doc.pages.first.nextFreeShapeId();
    final b = a + 1;
    final gid = b + 1;
    doc = doc.replacePage(
      0,
      doc.pages.first
          .addShape(
            VsdxShapeFactory.rectangle(
              id: a,
              pinX: 1,
              pinY: 1,
              width: 1,
              height: 1,
              fill: const VsdxFill(themeForegroundIndex: ThemeSlot.accent1),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: b,
              pinX: 3,
              pinY: 1,
              width: 1,
              height: 1,
            ),
          ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    // Override to solid while leaving stale formulas map (THEMEVAL).
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        a,
        (s) => s.copyWith(
          fill: s.fill.withSolidForeground(const VsdxColor(0xFF00AA55)),
        ),
      ),
    );
    // Group forces rebuild of child shape XML.
    doc = doc.replacePage(
      0,
      doc.pages.first.group({a, b}, groupId: gid),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(
      RegExp(r'N="FillForegnd"[^>]*F="THEMEVAL').hasMatch(pageXml),
      isFalse,
      reason: 'group rebuild must not resurrect THEMEVAL over solid V',
    );
    final after = parser.parse(out).pages.first.findShapeById(a)!;
    expect(after.fill.foreground?.value, 0xFF00AA55);
    expect(after.fill.themeForegroundIndex, isNull);
  });
}
