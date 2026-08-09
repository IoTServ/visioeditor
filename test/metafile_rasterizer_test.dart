import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/render/metafile_rasterizer.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _emfWithStockGrayBrush() {
  final bytes = Uint8List(132);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 1, Endian.little); // EMR_HEADER
  data.setUint32(4, 88, Endian.little);
  data.setInt32(16, 100, Endian.little);
  data.setInt32(20, 100, Endian.little);
  data.setUint32(40, 0x464D4520, Endian.little); // " EMF"

  const select = 88;
  data.setUint32(select, 37, Endian.little); // EMR_SELECTOBJECT
  data.setUint32(select + 4, 12, Endian.little);
  data.setUint32(select + 8, 0x80000002, Endian.little); // GRAY_BRUSH

  const rectangle = 100;
  data.setUint32(rectangle, 43, Endian.little); // EMR_RECTANGLE
  data.setUint32(rectangle + 4, 24, Endian.little);
  data.setInt32(rectangle + 8, 10, Endian.little);
  data.setInt32(rectangle + 12, 10, Endian.little);
  data.setInt32(rectangle + 16, 50, Endian.little);
  data.setInt32(rectangle + 20, 50, Endian.little);
  data.setUint32(124, 14, Endian.little); // EMR_EOF
  data.setUint32(128, 8, Endian.little);
  return bytes;
}

Uint8List _emfWithPolyDraw() {
  final bytes = Uint8List(216);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 1, Endian.little); // EMR_HEADER
  data.setUint32(4, 88, Endian.little);
  data.setInt32(16, 100, Endian.little);
  data.setInt32(20, 100, Endian.little);
  data.setUint32(40, 0x464D4520, Endian.little); // " EMF"

  const record = 88;
  data.setUint32(record, 56, Endian.little); // EMR_POLYDRAW
  data.setUint32(record + 4, 92, Endian.little);
  data.setInt32(record + 16, 100, Endian.little);
  data.setInt32(record + 20, 100, Endian.little);
  data.setUint32(record + 24, 7, Endian.little);
  const points = <(int, int)>[
    (10, 50),
    (30, 20),
    (50, 50),
    (60, 50),
    (70, 10),
    (90, 90),
    (100, 50),
  ];
  var pointOffset = record + 28;
  for (final point in points) {
    data.setInt32(pointOffset, point.$1, Endian.little);
    data.setInt32(pointOffset + 4, point.$2, Endian.little);
    pointOffset += 8;
  }
  bytes.setRange(pointOffset, pointOffset + 7, const <int>[
    0x06,
    0x02,
    0x03,
    0x06,
    0x04,
    0x04,
    0x05,
  ]);

  const lineTo = 180;
  data.setUint32(lineTo, 54, Endian.little); // EMR_LINETO
  data.setUint32(lineTo + 4, 16, Endian.little);
  data.setInt32(lineTo + 8, 90, Endian.little);
  data.setInt32(lineTo + 12, 100, Endian.little);
  const eof = 196;
  data.setUint32(eof, 14, Endian.little);
  data.setUint32(eof + 4, 20, Endian.little);
  return bytes;
}

Uint8List _emfWithPathBracket(int fillMode) {
  final out = BytesBuilder();
  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    out.add(data.buffer.asUint8List());
  }

  void i32(int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.little);
    out.add(data.buffer.asUint8List());
  }

  void pointRecord(int type, int x, int y) {
    u32(type);
    u32(16);
    i32(x);
    i32(y);
  }

  void emptyRecord(int type) {
    u32(type);
    u32(8);
  }

  u32(1);
  u32(88);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  out.add(const <int>[0x20, 0x45, 0x4D, 0x46]);
  while (out.length < 88) {
    out.addByte(0);
  }
  u32(39); // EMR_CREATEBRUSHINDIRECT
  u32(24);
  u32(1);
  u32(0);
  u32(0x000000FF);
  u32(0);
  u32(37); // EMR_SELECTOBJECT
  u32(12);
  u32(1);
  u32(19); // EMR_SETPOLYFILLMODE
  u32(12);
  u32(fillMode);
  emptyRecord(59); // EMR_BEGINPATH
  for (final point in const <(int, int)>[
    (10, 10),
    (90, 10),
    (90, 90),
    (10, 90),
  ]) {
    pointRecord(point == const (10, 10) ? 27 : 54, point.$1, point.$2);
  }
  emptyRecord(61); // EMR_CLOSEFIGURE
  for (final point in const <(int, int)>[
    (30, 30),
    (70, 30),
    (70, 70),
    (30, 70),
  ]) {
    pointRecord(point == const (30, 30) ? 27 : 54, point.$1, point.$2);
  }
  emptyRecord(61);
  emptyRecord(60); // EMR_ENDPATH
  u32(63); // EMR_STROKEANDFILLPATH
  u32(24);
  i32(10);
  i32(10);
  i32(90);
  i32(90);
  u32(14);
  u32(20);
  u32(0);
  u32(16);
  u32(20);
  return Uint8List.fromList(out.toBytes());
}

Uint8List _twoByTwoBmp() {
  final out = Uint8List(70);
  ByteData.sublistView(out)
    ..setUint8(0, 0x42)
    ..setUint8(1, 0x4d)
    ..setUint32(2, 70, Endian.little)
    ..setUint32(10, 54, Endian.little)
    ..setUint32(14, 40, Endian.little)
    ..setInt32(18, 2, Endian.little)
    ..setInt32(22, 2, Endian.little)
    ..setUint16(26, 1, Endian.little)
    ..setUint16(28, 24, Endian.little)
    ..setUint32(34, 16, Endian.little);
  out.setRange(54, 70, const <int>[
    255, 0, 0, 255, 255, 255, 0, 0,
    0, 0, 255, 0, 255, 0, 0, 0,
  ]);
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Canvas replays pixels as crisp device cells in paint order', () async {
    const drawing = MetafileDrawing(
      minX: 0,
      minY: 0,
      maxX: 4,
      maxY: 4,
      ops: <Object>[
        MetafilePixelOp(x: 1, y: 1, argb: 0xffff0000),
        MetafilePixelOp(x: 1, y: 1, argb: 0xff0000ff),
      ],
    );
    final image = await rasterizeMetafileDrawing(drawing, maxEdge: 40);
    final data = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    final center = (15 * image.width + 15) * 4;
    expect(bytes.sublist(center, center + 4), <int>[0, 0, 255, 255]);
    final outside = (5 * image.width + 5) * 4;
    expect(bytes[outside + 3], 0);
    image.dispose();
  });

  test('Canvas decodes embedded BMP ops with crop, order, and mirroring',
      () async {
    final bmp = _twoByTwoBmp();
    final drawing = MetafileDrawing(
      minX: 0,
      minY: 0,
      maxX: 8,
      maxY: 4,
      ops: <Object>[
        MetafileBitmapOp(
          bmpBytes: bmp,
          pixelWidth: 2,
          pixelHeight: 2,
          destination: const MetafileRect(0, 0, 4, 4),
        ),
        const MetafilePixelOp(x: 0, y: 0, argb: 0xff000000),
        MetafileBitmapOp(
          bmpBytes: bmp,
          pixelWidth: 2,
          pixelHeight: 2,
          destination: const MetafileRect(8, 0, 4, 4),
          source: const MetafileRect(0, 0, 2, 1),
        ),
      ],
    );
    final image = await rasterizeMetafileDrawing(drawing, maxEdge: 80);
    final data = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();

    List<int> pixel(int x, int y) {
      final offset = (y * image.width + x) * 4;
      return bytes.sublist(offset, offset + 4);
    }

    void expectColor(int x, int y, List<int> expected) {
      final actual = pixel(x, y);
      for (var i = 0; i < 4; i++) {
        expect(actual[i], closeTo(expected[i], 4));
      }
    }

    expectColor(5, 5, <int>[0, 0, 0, 255]); // later SETPIXEL
    expectColor(35, 5, <int>[0, 255, 0, 255]);
    expectColor(5, 35, <int>[0, 0, 255, 255]);
    expectColor(35, 35, <int>[255, 255, 255, 255]);
    // The second op crops the top row and mirrors it horizontally.
    expectColor(45, 20, <int>[0, 255, 0, 255]);
    expectColor(75, 20, <int>[255, 0, 0, 255]);
    image.dispose();
  });

  test('Canvas applies EMF clip regions and restores saved DC clips', () async {
    const fullRect = <MetafilePoint>[
      MetafilePoint(0, 0),
      MetafilePoint(100, 0),
      MetafilePoint(100, 100),
      MetafilePoint(0, 100),
    ];
    const drawing = MetafileDrawing(
      minX: 0,
      minY: 0,
      maxX: 100,
      maxY: 100,
      ops: <Object>[
        MetafilePathOp(
          points: fullRect,
          closed: true,
          fill: true,
          stroke: false,
          fillArgb: 0xff0000ff,
          strokeArgb: 0,
          strokeWidth: 0,
        ),
        MetafileSaveDcOp(),
        MetafileClipRectOp(
          rect: MetafileRect(25, 25, 75, 75),
          mode: MetafileClipCombineMode.intersect,
        ),
        MetafilePathOp(
          points: fullRect,
          closed: true,
          fill: true,
          stroke: false,
          fillArgb: 0xffff0000,
          strokeArgb: 0,
          strokeWidth: 0,
        ),
        MetafileRestoreDcOp(),
        MetafileClipRectOp(
          rect: MetafileRect(40, 40, 60, 60),
          mode: MetafileClipCombineMode.exclude,
        ),
        MetafilePathOp(
          points: fullRect,
          closed: true,
          fill: true,
          stroke: false,
          fillArgb: 0xff00ff00,
          strokeArgb: 0,
          strokeWidth: 0,
        ),
      ],
    );
    final image = await rasterizeMetafileDrawing(drawing, maxEdge: 100);
    final data = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    List<int> rgbaAt(int x, int y) {
      final offset = (y * image.width + x) * 4;
      return bytes.sublist(offset, offset + 4);
    }

    expect(rgbaAt(10, 10), <int>[0, 255, 0, 255]);
    expect(rgbaAt(50, 50), <int>[255, 0, 0, 255]);
    image.dispose();
  });

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

  test('Canvas replays selected EMF stock gray brush', () async {
    final drawing = parseEmfDrawing(_emfWithStockGrayBrush());
    expect(drawing, isNotNull);
    final image = await rasterizeMetafileDrawing(drawing!, maxEdge: 100);
    final data = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    int channelAt(int x, int y, int channel) =>
        bytes[(y * image.width + x) * 4 + channel];

    expect(channelAt(20, 20, 0), inInclusiveRange(126, 130));
    expect(channelAt(20, 20, 1), inInclusiveRange(126, 130));
    expect(channelAt(20, 20, 2), inInclusiveRange(126, 130));
    expect(channelAt(20, 20, 3), 255);
    expect(channelAt(5, 5, 3), 0);
    image.dispose();
  });

  test('Canvas replays EMF POLYDRAW line and cubic figures', () async {
    final drawing = parseEmfDrawing(_emfWithPolyDraw());
    expect(drawing, isNotNull);
    expect(drawing!.ops.whereType<MetafilePathOp>(), hasLength(3));
    final image = await rasterizeMetafileDrawing(drawing, maxEdge: 100);
    expect(image, isNotNull);
    final data = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(data, isNotNull);
    final bytes = data!.buffer.asUint8List();
    var opaquePixels = 0;
    for (var i = 3; i < bytes.length; i += 4) {
      if (bytes[i] != 0) opaquePixels++;
    }
    expect(opaquePixels, greaterThan(100));
    image.dispose();
  });

  test('Canvas honours EMF ALTERNATE and WINDING compound path fill',
      () async {
    Future<int> alphaAtCenter(int fillMode) async {
      final drawing = parseEmfDrawing(_emfWithPathBracket(fillMode))!;
      final image = await rasterizeMetafileDrawing(drawing, maxEdge: 100);
      final data = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List();
      final alpha = bytes[(50 * image.width + 50) * 4 + 3];
      image.dispose();
      return alpha;
    }

    expect(await alphaAtCenter(1), 0, reason: 'ALTERNATE leaves a hole');
    expect(await alphaAtCenter(2), 255, reason: 'WINDING fills the centre');
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

  test('Canvas replays GDI dashed pen gaps', () async {
    const drawing = MetafileDrawing(
      minX: 0,
      minY: 0,
      maxX: 32,
      maxY: 32,
      ops: <Object>[
        MetafilePathOp(
          points: <MetafilePoint>[
            MetafilePoint(0, 16),
            MetafilePoint(32, 16),
          ],
          closed: false,
          fill: false,
          stroke: true,
          fillArgb: 0,
          strokeArgb: 0xFF000000,
          strokeWidth: 1,
          strokeDashPattern: <double>[6, 6],
        ),
      ],
    );

    final image = await rasterizeMetafileDrawing(drawing, maxEdge: 64);
    final data = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    int alphaNear(int x) {
      var alpha = 0;
      for (var y = 30; y <= 34; y++) {
        final value = bytes[(y * image.width + x) * 4 + 3];
        if (value > alpha) alpha = value;
      }
      return alpha;
    }

    expect(alphaNear(6), greaterThan(32)); // first dash
    expect(alphaNear(18), lessThan(32)); // first gap
    expect(alphaNear(30), greaterThan(32)); // second dash
    image.dispose();
  });

  test('Canvas replays GDI rounded rectangle corners', () async {
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
          fillArgb: 0xFF000000,
          strokeArgb: 0,
          strokeWidth: 1,
          cornerRadiusX: 8,
          cornerRadiusY: 8,
        ),
      ],
    );

    final image = await rasterizeMetafileDrawing(drawing, maxEdge: 64);
    final data = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    int alphaAt(int x, int y) => bytes[(y * image.width + x) * 4 + 3];

    expect(alphaAt(2, 2), lessThan(32));
    expect(alphaAt(32, 2), greaterThan(224));
    expect(alphaAt(32, 32), 255);
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
