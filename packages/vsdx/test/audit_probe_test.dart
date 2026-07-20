import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  const parser = DocumentParser();
  const writer = VsdxWriter();

  test('audit probe: styles, hit-box, foreign tone round-trip via group', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    var page = doc.pages.first;
    var id = page.nextFreeShapeId();
    final rectId = id++;
    final annId = id++;
    final dblId = id++;
    final parId = id++;
    final picId = id++;
    final rect = VsdxShapeFactory.rectangle(
      id: rectId,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(
      fill: const VsdxFill(
        themeForegroundIndex: ThemeSlot.accent1,
        themeBackgroundIndex: ThemeSlot.accent3,
        pattern: 2,
      ),
      line: const VsdxLine(
        themeColorIndex: ThemeSlot.accent2,
        softEdgesInches: 0.05,
        compoundType: 1,
      ),
      shadow: const VsdxShadow(
        enabled: true,
        offsetXInches: 0.1,
        offsetYInches: -0.1,
        blurInches: 0.08,
      ),
      glow: const VsdxGlow(
        enabled: true,
        sizeInches: 0.12,
        color: VsdxColor(0xFFFF0000),
      ),
      text: 'Hello',
      richText: VsdxRichText(
        runs: [
          VsdxTextRun(
            text: 'Hello',
            charStyle: const VsdxCharStyle(fontSizeInches: 0.15),
          ),
        ],
        textBlock: const VsdxTextBlock(verticalAlign: VsdxVertAlign.top),
      ),
    );
    final ann = VsdxShapeFactory.annotation(
      id: annId,
      pinX: 4,
      pinY: 2,
      width: 1,
      height: 2,
    );
    final dbl = VsdxShapeFactory.doubleRectangle(
      id: dblId,
      pinX: 6,
      pinY: 2,
      width: 2,
      height: 1.5,
    );
    final par = VsdxShapeFactory.parallelMode(
      id: parId,
      pinX: 8,
      pinY: 2,
      width: 1.5,
      height: 1,
    );
    const part = '/visio/media/t.png';
    final pic = VsdxShapeFactory.picture(
      id: picId,
      pinX: 2,
      pinY: 4,
      width: 1.5,
      height: 1,
      imagePartName: part,
    ).copyWith(
      imageTransparency: 0,
      imageBrightness: 0.5,
      imageContrast: 0.5,
      imageBlur: 0,
    );
    final payload = Uint8List.fromList(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4,
    ]);
    page = page
        .addShape(rect)
        .addShape(ann)
        .addShape(dbl)
        .addShape(par)
        .addShape(pic);
    page = page.updateShapeById(annId, (s) {
      var geos = syncGeometryNoFill(s.geometries, hollow: true);
      geos = syncGeometryNoLine(geos, hollow: true);
      geos = syncGeometryNoFill(geos, hollow: false);
      geos = syncGeometryNoLine(geos, hollow: false);
      return s.copyWith(
        geometries: geos,
        fill: const VsdxFill(pattern: 1, foreground: VsdxColor(0xFF00FF00)),
        line: s.line.copyWith(pattern: 1),
      );
    });
    final gid = page.nextFreeShapeId();
    page = page.group({rectId, picId}, groupId: gid);
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: payload, mimeType: 'image/png'),
          ),
        )
        .replacePage(0, page);

    final out = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(out).pages.first;

    final annAfter = after.findShapeById(annId)!;
    expect(annAfter.geometries[0].hitBox, isTrue);
    expect(annAfter.geometries[0].noLine, isTrue);
    expect(annAfter.geometries[0].noFill, isTrue);
    expect(annAfter.geometries[1].noLine, isFalse);
    expect(annAfter.geometries[1].noFill, isTrue);

    final picAfter = after.findShapeById(picId)!;
    expect(picAfter.imageTransparency, closeTo(0, 1e-6));
    expect(picAfter.imageBrightness, closeTo(0.5, 1e-6));
    expect(picAfter.imageContrast, closeTo(0.5, 1e-6));
    expect(picAfter.imageBlur, closeTo(0, 1e-6));

    final rectAfter = after.findShapeById(rectId)!;
    expect(rectAfter.fill.themeForegroundIndex, ThemeSlot.accent1);
    expect(rectAfter.fill.themeBackgroundIndex, ThemeSlot.accent3);
    expect(rectAfter.line.themeColorIndex, ThemeSlot.accent2);
    expect(rectAfter.line.softEdgesInches, closeTo(0.05, 1e-6));
    expect(rectAfter.line.compoundType, 1);
    expect(rectAfter.glow.enabled, isTrue);
    expect(rectAfter.shadow.enabled, isTrue);
    expect(rectAfter.richText.textBlock.verticalAlign, VsdxVertAlign.top);

    final dblAfter = after.findShapeById(dblId)!;
    expect(dblAfter.geometries[0].noFill, isFalse);
    expect(dblAfter.geometries[1].noFill, isTrue);

    final parAfter = after.findShapeById(parId)!;
    expect(parAfter.geometries[0].hitBox, isTrue);
    expect(parAfter.geometries[0].noLine, isTrue);
    expect(parAfter.geometries[1].noLine, isFalse);
  });
}
