import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
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
}
