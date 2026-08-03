import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;
import 'package:visioeditor/io/image_export.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PNG export paints embedded raster (not only a placeholder)', () async {
    // Build a known-good solid red PNG via the Flutter codec so we don't
    // depend on hand-crafted bytes staying valid across platforms.
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 16, 16),
      ui.Paint()..color = const ui.Color(0xFFFF0000),
    );
    final picture = recorder.endRecording();
    final raster = await picture.toImage(16, 16);
    final encoded =
        await raster.toByteData(format: ui.ImageByteFormat.png);
    raster.dispose();
    picture.dispose();
    expect(encoded, isNotNull);
    final pngBytes = encoded!.buffer.asUint8List();

    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    final parser = const DocumentParser();
    var doc = parser.parse(blank);
    final page = doc.pages.first;
    final id = page.nextFreeShapeId();
    const part = '/visio/media/image1.png';
    final pic = VsdxShapeFactory.picture(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 1,
      height: 1,
      imagePartName: part,
    );
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(
              partName: part,
              bytes: pngBytes,
              mimeType: 'image/png',
            ),
          ),
        )
        .replacePage(0, page.addShape(pic));

    final exported = await renderPageToPng(
      doc.pages.first,
      theme: doc.theme,
      images: doc.images,
      pxPerInch: 96,
    );
    expect(exported, isNotNull);

    final codec = await ui.instantiateImageCodec(exported!);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final rgba = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(rgba, isNotNull);

    final w = img.width;
    final h = img.height;
    final pageH = doc.pages.first.heightInches <= 0
        ? 11.0
        : doc.pages.first.heightInches;
    // Pin is the shape centre; export canvas is Y-down from the page top.
    final cx = (2.0 * 96).round();
    final cy = ((pageH - 2.0) * 96).round();
    var redPixels = 0;
    for (var dy = -12; dy <= 12; dy++) {
      for (var dx = -12; dx <= 12; dx++) {
        final x = (cx + dx).clamp(0, w - 1);
        final y = (cy + dy).clamp(0, h - 1);
        final o = (y * w + x) * 4;
        final r = rgba!.getUint8(o);
        final g = rgba.getUint8(o + 1);
        final b = rgba.getUint8(o + 2);
        if (r > 200 && g < 40 && b < 40) redPixels++;
      }
    }
    img.dispose();
    expect(redPixels, greaterThan(20),
        reason: 'expected solid-red embedded image around ($cx,$cy) '
            'on ${w}x$h export; got $redPixels red pixels');
  });

  test('picture FlipY mirrors pixels and survives VSDX round-trip', () async {
    final source = raster.Image(width: 8, height: 8);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgba(
          x,
          y,
          y < source.height ~/ 2 ? 255 : 0,
          0,
          y < source.height ~/ 2 ? 0 : 255,
          255,
        );
      }
    }
    final pngBytes = raster.encodePng(source);
    const part = '/visio/media/flipy.png';
    const writer = VsdxWriter();
    const parser = DocumentParser();
    final blank = writer.emptyDocument();
    var document = parser.parse(blank);
    final page = document.pages.first;
    final normalId = page.nextFreeShapeId();
    final flippedId = normalId + 1;
    final normal = VsdxShapeFactory.picture(
      id: normalId,
      pinX: 2,
      pinY: 2.5,
      width: 1.5,
      height: 2,
      imagePartName: part,
    );
    final flipped = VsdxShapeFactory.picture(
      id: flippedId,
      pinX: 4.5,
      pinY: 2.5,
      width: 1.5,
      height: 2,
      imagePartName: part,
    ).copyWith(flipY: true);
    document = document
        .copyWith(
          images: document.images.withImage(
            VsdxImage(
              partName: part,
              bytes: pngBytes,
              mimeType: 'image/png',
            ),
          ),
        )
        .replacePage(0, page.copyWith(shapes: <VsdxShape>[normal, flipped]));

    final reopened = parser.parse(
      writer.write(originalBytes: blank, edited: document),
    );
    expect(reopened.pages.first.findShapeById(flippedId)!.flipY, isTrue);
    final exported = await renderPageToPng(
      reopened.pages.first,
      theme: reopened.theme,
      images: reopened.images,
      pxPerInch: 96,
    );
    expect(exported, isNotNull);
    final codec = await ui.instantiateImageCodec(exported!);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(rgba, isNotNull);
    final pageHeight = reopened.pages.first.heightInches;

    (int, int, int) rgbAt(double pageX, double pageY) {
      final x = (pageX * 96).round().clamp(0, image.width - 1);
      final y = ((pageHeight - pageY) * 96)
          .round()
          .clamp(0, image.height - 1);
      final offset = (y * image.width + x) * 4;
      return (
        rgba!.getUint8(offset),
        rgba.getUint8(offset + 1),
        rgba.getUint8(offset + 2),
      );
    }

    final normalTop = rgbAt(2, 3);
    final normalBottom = rgbAt(2, 2);
    final flippedTop = rgbAt(4.5, 3);
    final flippedBottom = rgbAt(4.5, 2);
    expect(normalTop.$1, greaterThan(200));
    expect(normalTop.$3, lessThan(50));
    expect(normalBottom.$3, greaterThan(200));
    expect(normalBottom.$1, lessThan(50));
    expect(flippedTop.$3, greaterThan(200));
    expect(flippedTop.$1, lessThan(50));
    expect(flippedBottom.$1, greaterThan(200));
    expect(flippedBottom.$3, lessThan(50));
    image.dispose();
    codec.dispose();
  });

  test('ForeignData is not clipped by Geometry after VSDX round-trip',
      () async {
    final source = raster.Image(width: 8, height: 8);
    raster.fill(source, color: raster.ColorRgb8(255, 0, 0));
    const part = '/visio/media/geometry-foreign-data.png';
    const writer = VsdxWriter();
    const parser = DocumentParser();
    final blank = writer.emptyDocument();
    var document = parser.parse(blank);
    final page = document.pages.first;
    final shape = VsdxShapeFactory.picture(
      id: page.nextFreeShapeId(),
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 2,
      imagePartName: part,
    ).copyWith(
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          noLine: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, 0),
            LineTo(2, 0),
            LineTo(1, 2),
            LineTo(0, 0),
          ],
        ),
      ],
    );
    document = document
        .copyWith(
          images: document.images.withImage(
            VsdxImage(
              partName: part,
              bytes: raster.encodePng(source),
              mimeType: 'image/png',
            ),
          ),
        )
        .replacePage(0, page.addShape(shape));

    final reopened = parser.parse(
      writer.write(originalBytes: blank, edited: document),
    );
    final exported = await renderPageToPng(
      reopened.pages.first,
      theme: reopened.theme,
      images: reopened.images,
      pxPerInch: 96,
    );
    expect(exported, isNotNull);
    final codec = await ui.instantiateImageCodec(exported!);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(rgba, isNotNull);

    // Inside the 2x2 ForeignData rectangle, but outside its triangle Geometry.
    final x = (1.2 * 96).round();
    final y = ((reopened.pages.first.heightInches - 2.7) * 96).round();
    final offset = (y * image.width + x) * 4;
    expect(rgba!.getUint8(offset), greaterThan(200));
    expect(rgba.getUint8(offset + 1), lessThan(50));
    expect(rgba.getUint8(offset + 2), lessThan(50));
    image.dispose();
    codec.dispose();
  });

  test('PNG export honours Color-by-Layer view', () async {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 4,
      heightInches: 4,
      layers: const <VsdxLayer>[
        VsdxLayer(
          id: 0,
          name: 'Red',
          color: VsdxColor(0xFFFF0000),
        ),
      ],
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 1,
          height: 1,
          fill: const VsdxFill(foreground: VsdxColor(0xFF00FF00)),
        ).copyWith(layerMemberIds: const <int>[0]),
      ],
    );

    final exported = await renderPageToPng(
      page,
      pxPerInch: 96,
      colorByLayer: true,
    );
    expect(exported, isNotNull);
    final codec = await ui.instantiateImageCodec(exported!);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(rgba, isNotNull);
    final offset = ((2 * 96) * image.width + (2 * 96)) * 4;
    expect(rgba!.getUint8(offset), greaterThan(220));
    expect(rgba.getUint8(offset + 1), lessThan(40));
    expect(rgba.getUint8(offset + 2), lessThan(40));
    image.dispose();
  });
}
