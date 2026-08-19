import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as raster;
import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _twoPixelTiff() {
  final image = raster.Image(width: 2, height: 1)
    ..setPixelRgba(0, 0, 255, 0, 0, 255)
    ..setPixelRgba(1, 0, 0, 0, 255, 255);
  return raster.encodeTiff(image, singleFrame: true);
}

void main() {
  test('TIFF ForeignData becomes a PNG rendering payload', () {
    final tiff = _twoPixelTiff();
    final source = VsdxImage(
      partName: '/visio/media/foreign.tiff',
      bytes: tiff,
      mimeType: 'image/tiff',
    );

    expect(source.isFlutterDecodable, isFalse);
    final rendered = source.rasterForRendering();
    expect(rendered, isNotNull);
    expect(rendered!.mimeType, 'image/png');
    expect(rendered.bytes.take(8),
        <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

    final decoded = raster.decodePng(rendered.bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 2);
    expect(decoded.height, 1);
    // Rendering conversion must never replace the lossless source payload.
    expect(source.bytes, tiff);
  });

  test('TIFF picture renders in SVG and survives VSDX round-trip', () {
    const writer = VsdxWriter();
    const parser = DocumentParser();
    final tiff = _twoPixelTiff();
    const part = '/visio/media/foreign.tiff';
    final blank = writer.emptyDocument();
    var document = parser.parse(blank);
    final page = document.pages.first;
    final picture = VsdxShapeFactory.picture(
      id: page.nextFreeShapeId(),
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
      imagePartName: part,
    );
    document = document
        .copyWith(
          images: document.images.withImage(
            VsdxImage(partName: part, bytes: tiff, mimeType: 'image/tiff'),
          ),
        )
        .replacePage(0, page.addShape(picture));

    final beforeSvg = VsdxToSvgSerializer().serializePage(
      document.pages.first,
      images: document.images,
    );
    expect(beforeSvg, contains('href="data:image/png;base64,'));

    final saved = writer.write(originalBytes: blank, edited: document);
    final pageXml = VsdxPackage.open(saved)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(pageXml, contains('ForeignType="Bitmap"'));
    expect(pageXml, contains('CompressionType="TIFF"'));
    final reopened = parser.parse(saved);
    expect(
      reopened.pages.first.shapes.single.foreignCompressionType,
      'TIFF',
    );
    final reopenedImage = reopened.images.findByPart(part);
    expect(reopenedImage, isNotNull);
    expect(reopenedImage!.mimeType, 'image/tiff');
    expect(reopenedImage.bytes, tiff);
    final afterSvg = VsdxToSvgSerializer().serializePage(
      reopened.pages.first,
      images: reopened.images,
    );
    final png = reopenedImage.rasterForRendering()!;
    expect(afterSvg, contains(base64Encode(png.bytes)));
  });

  test('writer bakes Image Properties into PNG for LibreOffice', () {
    const writer = VsdxWriter();
    const parser = DocumentParser();
    final src = raster.Image(width: 4, height: 4);
    for (final pixel in src) {
      pixel
        ..r = 255
        ..g = 0
        ..b = 0
        ..a = 255;
    }
    final png = raster.encodePng(src);
    const part = '/visio/media/image_tone.png';
    final blank = writer.emptyDocument();
    var document = parser.parse(blank);
    final page = document.pages.first;
    final picture = VsdxShapeFactory.picture(
      id: page.nextFreeShapeId(),
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
      imagePartName: part,
    ).copyWith(
      imageTransparency: 0.5,
      imageBrightness: 0.7,
    );
    document = document
        .copyWith(
          images: document.images.withImage(
            VsdxImage(partName: part, bytes: png, mimeType: 'image/png'),
          ),
        )
        .replacePage(0, page.addShape(picture));
    final saved = writer.write(originalBytes: blank, edited: document);
    final reopened = parser.parse(saved);
    final after = reopened.pages.first.shapes.single;
    expect(after.imageTransparency, closeTo(0, 1e-6));
    expect(after.imageBrightness, closeTo(0.5, 1e-6));
    expect(after.imagePartName, isNot(part));
    final baked = reopened.images.findByPart(after.imagePartName!);
    expect(baked, isNotNull);
    final decoded = raster.decodePng(baked!.bytes);
    expect(decoded, isNotNull);
    expect(decoded!.getPixel(0, 0).aNormalized, closeTo(0.5, 0.05));
  });

  test('malformed TIFF keeps release rendering best-effort', () {
    final source = VsdxImage(
      partName: '/visio/media/broken.tif',
      bytes: Uint8List.fromList(<int>[0x49, 0x49, 0x2a]),
      mimeType: 'image/tiff',
    );

    expect(source.rasterForRendering(), isNull);
  });

  test('Visio bitmap compression covers every libvisio raster format', () {
    for (final entry in const <(String, String, String)>[
      ('image/jpeg', '/visio/media/image.jpg', 'JPEG'),
      ('image/gif', '/visio/media/image.gif', 'GIF'),
      ('image/tiff', '/visio/media/image.tiff', 'TIFF'),
      ('image/png', '/visio/media/image.png', 'PNG'),
    ]) {
      expect(
        VsdxImage.compressionTypeFor(
          mimeType: entry.$1,
          partName: entry.$2,
        ),
        entry.$3,
      );
    }
  });
}
