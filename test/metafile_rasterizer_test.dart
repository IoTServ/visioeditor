import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/render/metafile_rasterizer.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Canvas replays opaque GDI hatched brush foreground and background',
      () async {
    const drawing = MetafileDrawing(
      minX: 0,
      minY: 0,
      maxX: 32,
      maxY: 32,
      ops: <Object>[
        MetafilePathOp(
          points: <MetafilePoint>[
            MetafilePoint(0, 0),
            MetafilePoint(32, 0),
            MetafilePoint(32, 32),
            MetafilePoint(0, 32),
          ],
          closed: true,
          fill: true,
          stroke: false,
          fillArgb: 0xFF008000,
          strokeArgb: 0,
          strokeWidth: 1,
          fillHatch: 4,
          fillBackgroundArgb: 0xFFFFFFFF,
        ),
      ],
    );

    final image = await rasterizeMetafileDrawing(drawing, maxEdge: 64);
    expect(image, isNotNull);
    final data = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(data, isNotNull);
    final bytes = data!.buffer.asUint8List();
    var green = 0;
    var white = 0;
    for (var i = 0; i + 3 < bytes.length; i += 4) {
      if (bytes[i + 1] > bytes[i] + 20 &&
          bytes[i + 1] > bytes[i + 2] + 20 &&
          bytes[i + 3] == 255) {
        green++;
      }
      if (bytes[i] == 255 &&
          bytes[i + 1] == 255 &&
          bytes[i + 2] == 255 &&
          bytes[i + 3] == 255) {
        white++;
      }
    }
    expect(green, greaterThan(50));
    expect(white, greaterThan(500));
    image.dispose();
  });

  test('Canvas replays ExtTextOut per-glyph advances', () async {
    const drawing = MetafileDrawing(
      minX: 0,
      minY: 0,
      maxX: 48,
      maxY: 32,
      ops: <Object>[
        MetafileTextOp(
          text: 'II',
          x: 0,
          y: 20,
          fontHeight: 12,
          argb: 0xFF000000,
          advancesX: <double>[20, 20],
        ),
      ],
    );

    final image = await rasterizeMetafileDrawing(drawing, maxEdge: 96);
    expect(image, isNotNull);
    final data = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(data, isNotNull);
    final bytes = data!.buffer.asUint8List();
    var rightGlyphPixels = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 34; x < image.width; x++) {
        final i = (y * image.width + x) * 4;
        if (bytes[i + 3] > 32) rightGlyphPixels++;
      }
    }
    expect(rightGlyphPixels, greaterThan(2));
    image.dispose();
  });

  test('Canvas rotates and styles LOGFONT text around its reference point',
      () async {
    const drawing = MetafileDrawing(
      minX: 0,
      minY: 0,
      maxX: 48,
      maxY: 48,
      ops: <Object>[
        MetafileTextOp(
          text: 'IIII',
          x: 24,
          y: 40,
          fontHeight: 12,
          argb: 0xFF000000,
          advancesX: <double>[6, 6, 6, 6],
          fontWeight: 700,
          italic: true,
          underline: true,
          strikeThrough: true,
          escapementDegrees: 90,
        ),
      ],
    );

    final image = await rasterizeMetafileDrawing(drawing, maxEdge: 96);
    expect(image, isNotNull);
    final data = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(data, isNotNull);
    final bytes = data!.buffer.asUint8List();
    var upperBandPixels = 0;
    for (var y = 0; y < image.height ~/ 2; y++) {
      for (var x = 0; x < image.width; x++) {
        final i = (y * image.width + x) * 4;
        if (bytes[i + 3] > 32) upperBandPixels++;
      }
    }
    expect(upperBandPixels, greaterThan(2));
    image.dispose();
  });

  test('Canvas honours GDI top and bottom text reference points', () async {
    const drawing = MetafileDrawing(
      minX: 0,
      minY: 0,
      maxX: 48,
      maxY: 40,
      ops: <Object>[
        MetafileTextOp(
          text: 'M',
          x: 2,
          y: 20,
          fontHeight: 10,
          argb: 0x00000000,
          backgroundArgb: 0xFFFF0000,
          align: 0x00,
        ),
        MetafileTextOp(
          text: 'M',
          x: 18,
          y: 20,
          fontHeight: 10,
          argb: 0x00000000,
          backgroundArgb: 0xFF00FF00,
          align: 0x08,
        ),
      ],
    );

    final image = await rasterizeMetafileDrawing(drawing, maxEdge: 96);
    expect(image, isNotNull);
    final data = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(data, isNotNull);
    final bytes = data!.buffer.asUint8List();
    var redBelowReference = 0;
    var greenAboveReference = 0;
    final referenceY = image.height ~/ 2;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final i = (y * image.width + x) * 4;
        if (y >= referenceY && bytes[i] > 200 && bytes[i + 1] < 40) {
          redBelowReference++;
        }
        if (y < referenceY && bytes[i + 1] > 200 && bytes[i] < 40) {
          greenAboveReference++;
        }
      }
    }
    expect(redBelowReference, greaterThan(20));
    expect(greenAboveReference, greaterThan(20));
    image.dispose();
  });

  test('Canvas honours ExtTextOut opaque and clipping rectangles', () async {
    const drawing = MetafileDrawing(
      minX: 0,
      minY: 0,
      maxX: 32,
      maxY: 32,
      ops: <Object>[
        MetafileTextOp(
          text: 'MMMM',
          x: 2,
          y: 10,
          fontHeight: 12,
          argb: 0xFF000000,
          backgroundArgb: 0xFFFF0000,
          opaqueRect: MetafileRect(2, 2, 30, 8),
          clipRect: MetafileRect(2, 10, 8, 24),
        ),
      ],
    );

    final image = await rasterizeMetafileDrawing(drawing, maxEdge: 96);
    expect(image, isNotNull);
    final data = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    var opaqueFarRight = 0;
    var clippedTextPixels = 0;
    var leakedTextPixels = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final i = (y * image.width + x) * 4;
        final red = bytes[i] > 200 && bytes[i + 1] < 40 && bytes[i + 2] < 40;
        final black = bytes[i] < 50 &&
            bytes[i + 1] < 50 &&
            bytes[i + 2] < 50 &&
            bytes[i + 3] > 32;
        if (red && x > 60) opaqueFarRight++;
        if (black && x < 24) clippedTextPixels++;
        if (black && x > 28) leakedTextPixels++;
      }
    }
    expect(opaqueFarRight, greaterThan(100));
    expect(clippedTextPixels, greaterThan(2));
    expect(leakedTextPixels, 0);
    image.dispose();
  });
}
