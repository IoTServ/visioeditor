import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;
import 'package:visioeditor/io/image_export.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FlipX/FlipY text stays upright through groups and VSDX round-trip',
      () async {
    const writer = VsdxWriter();
    const parser = DocumentParser();
    final blank = writer.emptyDocument();
    var document = parser.parse(blank);
    final page = document.pages.first;
    VsdxRichText flipText(String text) => VsdxRichText(
          runs: <VsdxTextRun>[
            VsdxTextRun(
              text: text,
              charStyle: const VsdxCharStyle(
                fontFamily: 'Arial',
                fontSizeInches: 0.5,
                color: VsdxColor(0xFF000000),
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
        );
    final flipXText = VsdxShapeFactory.rectangle(
      id: page.nextFreeShapeId(),
      pinX: 2,
      pinY: 6,
      width: 3,
      height: 1.5,
    ).copyWith(
      flipX: true,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      richText: flipText('LEFT'),
    );
    final flipYText = VsdxShapeFactory.rectangle(
      id: flipXText.id + 1,
      pinX: 2,
      pinY: 3,
      width: 3,
      height: 1.5,
    ).copyWith(
      flipY: true,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      richText: flipText('TOP'),
    );
    final nestedText = VsdxShapeFactory.rectangle(
      id: flipYText.id + 2,
      pinX: 1.5,
      pinY: 0.75,
      width: 3,
      height: 1.5,
    ).copyWith(
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      richText: flipText('LEFT'),
    );
    final flipXGroup = VsdxShapeFactory.rectangle(
      id: flipYText.id + 1,
      pinX: 6,
      pinY: 6,
      width: 3,
      height: 1.5,
    ).copyWith(
      flipX: true,
      shapeKind: VsdxShapeKind.group,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      children: <VsdxShape>[nestedText],
    );
    document = document.replacePage(
      0,
      page.copyWith(
        shapes: <VsdxShape>[flipXText, flipYText, flipXGroup],
      ),
    );

    final reopened = parser.parse(
      writer.write(originalBytes: blank, edited: document),
    );
    expect(reopened.pages.first.findShapeById(flipXText.id)!.flipX, isTrue);
    expect(reopened.pages.first.findShapeById(flipYText.id)!.flipY, isTrue);
    expect(reopened.pages.first.findShapeById(flipXGroup.id)!.flipX, isTrue);
    final png = await renderPageToPng(
      reopened.pages.first,
      theme: reopened.theme,
      images: reopened.images,
      pxPerInch: 96,
    );
    final rendered = raster.decodePng(png!)!;
    final reopenedPage = reopened.pages.first;
    int darkPixels(double x0, double y0, double x1, double y1) {
      final left = (x0 * 96).round();
      final right = (x1 * 96).round();
      final top = ((reopenedPage.heightInches - y1) * 96).round();
      final bottom = ((reopenedPage.heightInches - y0) * 96).round();
      var count = 0;
      for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) {
          final pixel = rendered.getPixel(x, y);
          if (pixel.r < 120 && pixel.g < 120 && pixel.b < 120) count++;
        }
      }
      return count;
    }

    final flipXLeft = darkPixels(0.55, 5.35, 2.0, 6.65);
    final flipXRight = darkPixels(2.0, 5.35, 3.45, 6.65);
    expect(flipXLeft, greaterThan(flipXRight * 2));
    final flipYTop = darkPixels(0.55, 3.0, 3.45, 3.7);
    final flipYBottom = darkPixels(0.55, 2.3, 3.45, 3.0);
    expect(flipYTop, greaterThan(flipYBottom * 2));
    final nestedLeft = darkPixels(4.55, 5.35, 6.0, 6.65);
    final nestedRight = darkPixels(6.0, 5.35, 7.45, 6.65);
    expect(nestedLeft, greaterThan(nestedRight * 2));
  });
}
