import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;
import 'package:visioeditor/io/image_export.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Canvas applies ComplexScriptSize only to complex-script glyphs',
    () async {
      const writer = VsdxWriter();
      const parser = DocumentParser();
      final blank = writer.emptyDocument();
      var document = parser.parse(blank);
      final page = document.pages.first;

      VsdxShape label(
        int id,
        double y, {
        double x = 3,
        double width = 4,
        double? complexSize,
        bool curved = false,
      }) {
        final shape = VsdxShapeFactory.rectangle(
          id: id,
          pinX: x,
          pinY: y,
          width: width,
          height: 1.5,
        ).copyWith(
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(pattern: 0),
          richText: VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'سلام',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  complexScriptFont: 'Arial',
                  fontSizeInches: 0.12,
                  complexScriptSizeInches: complexSize,
                  color: VsdxColor.black,
                ),
                paraStyle: const VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.left,
                ),
              ),
            ],
            textBlock: const VsdxTextBlock(
              verticalAlign: VsdxVertAlign.top,
              marginLeftInches: 0.1,
              marginRightInches: 0.1,
              marginTopInches: 0.1,
              marginBottomInches: 0.1,
            ),
          ),
        );
        return curved ? shape.withCurvedText(true) : shape;
      }

      final normal = label(page.nextFreeShapeId(), 2);
      final enlarged = label(normal.id + 1, 5, complexSize: 0.45);
      final curvedNormal = label(
        enlarged.id + 1,
        2,
        x: 6.8,
        width: 3,
        curved: true,
      );
      final curvedEnlarged = label(
        curvedNormal.id + 1,
        5,
        x: 6.8,
        width: 3,
        complexSize: 0.45,
        curved: true,
      );
      document = document.replacePage(
        0,
        page.copyWith(
          shapes: <VsdxShape>[
            normal,
            enlarged,
            curvedNormal,
            curvedEnlarged,
          ],
        ),
      );
      final reopened = parser.parse(
        writer.write(originalBytes: blank, edited: document),
      );
      final png = await renderPageToPng(
        reopened.pages.first,
        theme: reopened.theme,
        images: reopened.images,
        pxPerInch: 96,
      );
      final image = raster.decodePng(png!)!;

      int darkPixels(VsdxShape shape) {
        final left = ((shape.pinX - shape.width / 2) * 96).round();
        final right = ((shape.pinX + shape.width / 2) * 96).round();
        final top =
            ((reopened.pages.first.heightInches -
                        shape.pinY -
                        shape.height / 2) *
                    96)
                .round();
        final bottom =
            ((reopened.pages.first.heightInches -
                        shape.pinY +
                        shape.height / 2) *
                    96)
                .round();
        var count = 0;
        for (var y = top; y < bottom; y++) {
          for (var x = left; x < right; x++) {
            final pixel = image.getPixel(x, y);
            if (pixel.r < 160 && pixel.g < 160 && pixel.b < 160) count++;
          }
        }
        return count;
      }

      final normalPixels = darkPixels(
        reopened.pages.first.findShapeById(normal.id)!,
      );
      final enlargedPixels = darkPixels(
        reopened.pages.first.findShapeById(enlarged.id)!,
      );
      expect(normalPixels, greaterThan(0));
      expect(enlargedPixels, greaterThan(normalPixels * 2));
      final curvedNormalPixels = darkPixels(
        reopened.pages.first.findShapeById(curvedNormal.id)!,
      );
      final curvedEnlargedPixels = darkPixels(
        reopened.pages.first.findShapeById(curvedEnlarged.id)!,
      );
      expect(curvedNormalPixels, greaterThan(0));
      expect(curvedEnlargedPixels, greaterThan(curvedNormalPixels * 2));
    },
  );

  test('complex-script classifier covers Office shaping scripts', () {
    expect(isVisioComplexScriptRune('ش'.runes.single), isTrue);
    expect(isVisioComplexScriptRune('ש'.runes.single), isTrue);
    expect(isVisioComplexScriptRune('क'.runes.single), isTrue);
    expect(isVisioComplexScriptRune('A'.runes.single), isFalse);
    expect(isVisioComplexScriptRune('中'.runes.single), isFalse);
  });
}
