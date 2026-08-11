import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _wordRecord(int function, List<int> words) {
  final out = Uint8List(6 + words.length * 2);
  final data = ByteData.sublistView(out)
    ..setUint32(0, out.length ~/ 2, Endian.little)
    ..setUint16(4, function, Endian.little);
  for (var i = 0; i < words.length; i++) {
    data.setUint16(6 + i * 2, words[i] & 0xffff, Endian.little);
  }
  return out;
}

Uint8List _brushRecord(int colorRef) {
  final out = Uint8List(14);
  ByteData.sublistView(out)
    ..setUint32(0, 7, Endian.little)
    ..setUint16(4, 0x02fc, Endian.little)
    ..setUint16(6, 0, Endian.little) // BS_SOLID
    ..setUint32(8, colorRef, Endian.little)
    ..setUint16(12, 0, Endian.little);
  return out;
}

Uint8List _penRecord(
    {required int style, required int width, int colorRef = 0}) {
  final out = Uint8List(16);
  ByteData.sublistView(out)
    ..setUint32(0, 8, Endian.little)
    ..setUint16(4, 0x02fa, Endian.little)
    ..setUint16(6, style, Endian.little)
    ..setInt16(8, width, Endian.little)
    ..setInt16(10, 0, Endian.little)
    ..setUint32(12, colorRef, Endian.little);
  return out;
}

Uint8List _setPixelRecord(int colorRef, int x, int y) {
  final out = Uint8List(14);
  ByteData.sublistView(out)
    ..setUint32(0, 7, Endian.little)
    ..setUint16(4, 0x041f, Endian.little)
    ..setUint32(6, colorRef, Endian.little)
    ..setInt16(10, y, Endian.little)
    ..setInt16(12, x, Endian.little);
  return out;
}

Uint8List _patBltRecord(
  int rasterOperation,
  int x,
  int y,
  int width,
  int height,
) {
  final out = Uint8List(18);
  ByteData.sublistView(out)
    ..setUint32(0, 9, Endian.little)
    ..setUint16(4, 0x061d, Endian.little)
    ..setUint32(6, rasterOperation, Endian.little)
    ..setInt16(10, height, Endian.little)
    ..setInt16(12, width, Endian.little)
    ..setInt16(14, y, Endian.little)
    ..setInt16(16, x, Endian.little);
  return out;
}

Uint8List _sourceLessBltRecord(
  int function,
  int rasterOperation,
  int x,
  int y,
  int width,
  int height,
) {
  final stretched = function == 0x0b23 || function == 0x0b41;
  final out = Uint8List(stretched ? 28 : 24);
  final data = ByteData.sublistView(out)
    ..setUint32(0, out.length ~/ 2, Endian.little)
    ..setUint16(4, function, Endian.little)
    ..setUint32(6, rasterOperation, Endian.little);
  var p = 10;
  if (stretched) {
    data.setInt16(p, height, Endian.little);
    data.setInt16(p + 2, width, Endian.little);
    p += 4;
  }
  data.setInt16(p, 0, Endian.little); // YSrc
  data.setInt16(p + 2, 0, Endian.little); // XSrc
  data.setUint16(p + 4, 0, Endian.little); // Reserved
  data.setInt16(p + 6, height, Endian.little);
  data.setInt16(p + 8, width, Endian.little);
  data.setInt16(p + 10, y, Endian.little);
  data.setInt16(p + 12, x, Endian.little);
  return out;
}

Uint8List _twoByTwoDib() {
  final out = Uint8List(56);
  ByteData.sublistView(out)
    ..setUint32(0, 40, Endian.little) // BITMAPINFOHEADER
    ..setInt32(4, 2, Endian.little)
    ..setInt32(8, 2, Endian.little) // bottom-up
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, 24, Endian.little)
    ..setUint32(20, 16, Endian.little);
  // Two padded BGR scanlines: bottom blue/white, top red/green.
  out.setRange(40, 56, const <int>[
    255,
    0,
    0,
    255,
    255,
    255,
    0,
    0,
    0,
    0,
    255,
    0,
    255,
    0,
    0,
    0,
  ]);
  return out;
}

Uint8List _dibBltRecord(
  int function, {
  required int x,
  required int y,
  required int width,
  required int height,
  int sourceX = 0,
  int sourceY = 0,
  int sourceWidth = 0,
  int sourceHeight = 0,
  int rasterOperation = 0x00cc0020,
}) {
  final dib = _twoByTwoDib();
  final stretched = function == 0x0b41 || function == 0x0f43;
  final hasColorUsage = function == 0x0f43;
  final fixedBytes = 4 + (hasColorUsage ? 2 : 0) + (stretched ? 4 : 0) + 12;
  final out = Uint8List(6 + fixedBytes + dib.length);
  final data = ByteData.sublistView(out)
    ..setUint32(0, out.length ~/ 2, Endian.little)
    ..setUint16(4, function, Endian.little)
    ..setUint32(6, rasterOperation, Endian.little);
  var p = 10;
  if (hasColorUsage) {
    data.setUint16(p, 0, Endian.little); // DIB_RGB_COLORS
    p += 2;
  }
  if (stretched) {
    data.setInt16(p, sourceHeight, Endian.little);
    data.setInt16(p + 2, sourceWidth, Endian.little);
    p += 4;
  }
  data.setInt16(p, sourceY, Endian.little);
  data.setInt16(p + 2, sourceX, Endian.little);
  data.setInt16(p + 4, height, Endian.little);
  data.setInt16(p + 6, width, Endian.little);
  data.setInt16(p + 8, y, Endian.little);
  data.setInt16(p + 10, x, Endian.little);
  p += 12;
  out.setRange(p, out.length, dib);
  return out;
}

Uint8List _setDibToDevRecord({
  required int x,
  required int y,
  required int sourceX,
  required int sourceY,
  required int width,
  required int height,
  required int startScan,
  required int scanCount,
}) {
  final dib = _twoByTwoDib();
  final out = Uint8List(24 + dib.length);
  ByteData.sublistView(out)
    ..setUint32(0, out.length ~/ 2, Endian.little)
    ..setUint16(4, 0x0d33, Endian.little)
    ..setUint16(6, 0, Endian.little) // DIB_RGB_COLORS
    ..setUint16(8, scanCount, Endian.little)
    ..setUint16(10, startScan, Endian.little)
    ..setUint16(12, sourceY, Endian.little)
    ..setUint16(14, sourceX, Endian.little)
    ..setUint16(16, height, Endian.little)
    ..setUint16(18, width, Endian.little)
    ..setUint16(20, y, Endian.little)
    ..setUint16(22, x, Endian.little);
  out.setRange(24, out.length, dib);
  return out;
}

Uint8List _dibPatternBrushRecord({
  required int style,
  Uint8List? target,
}) {
  final pattern = target ?? _twoByTwoDib();
  final out = Uint8List(10 + pattern.length);
  ByteData.sublistView(out)
    ..setUint32(0, out.length ~/ 2, Endian.little)
    ..setUint16(4, 0x0142, Endian.little)
    ..setUint16(6, style, Endian.little)
    ..setUint16(8, 0, Endian.little); // DIB_RGB_COLORS
  out.setRange(10, out.length, pattern);
  return out;
}

Uint8List _bitmap16Pattern({required int headerSize}) {
  final out = Uint8List(headerSize + 4);
  ByteData.sublistView(out)
    ..setInt16(0, 0, Endian.little) // Type
    ..setInt16(2, 8, Endian.little)
    ..setInt16(4, 2, Endian.little)
    ..setInt16(6, 2, Endian.little) // WORD-aligned source rows
    ..setUint8(8, 1)
    ..setUint8(9, 1);
  out.setRange(headerSize, out.length, const <int>[0xaa, 0, 0x55, 0]);
  return out;
}

Uint8List _createPatternBrushRecord() {
  final target = _bitmap16Pattern(headerSize: 32);
  final out = Uint8List(6 + target.length);
  ByteData.sublistView(out)
    ..setUint32(0, out.length ~/ 2, Endian.little)
    ..setUint16(4, 0x01f9, Endian.little);
  out.setRange(6, out.length, target);
  return out;
}

Uint8List _polyPolygonRecord() {
  const polygons = <List<(int, int)>>[
    <(int, int)>[(0, 0), (100, 0), (100, 100), (0, 100)],
    <(int, int)>[(25, 25), (75, 25), (75, 75), (25, 75)],
  ];
  final paramsLength = 2 +
      polygons.length * 2 +
      polygons.fold<int>(0, (sum, points) => sum + points.length * 4);
  final out = Uint8List(6 + paramsLength);
  final data = ByteData.sublistView(out)
    ..setUint32(0, out.length ~/ 2, Endian.little)
    ..setUint16(4, 0x0538, Endian.little)
    ..setUint16(6, polygons.length, Endian.little);
  var offset = 8;
  for (final points in polygons) {
    data.setUint16(offset, points.length, Endian.little);
    offset += 2;
  }
  for (final points in polygons) {
    for (final (x, y) in points) {
      data.setInt16(offset, x, Endian.little);
      data.setInt16(offset + 2, y, Endian.little);
      offset += 4;
    }
  }
  return out;
}

Uint8List _textOutRecord(String text, int x, int y) {
  final bytes = Uint8List.fromList(text.codeUnits);
  final padded = bytes.length + (bytes.length.isOdd ? 1 : 0);
  final out = Uint8List(6 + 2 + padded + 4);
  final data = ByteData.sublistView(out)
    ..setUint32(0, out.length ~/ 2, Endian.little)
    ..setUint16(4, 0x0521, Endian.little)
    ..setUint16(6, bytes.length, Endian.little);
  out.setRange(8, 8 + bytes.length, bytes);
  data.setInt16(8 + padded, y, Endian.little);
  data.setInt16(10 + padded, x, Endian.little);
  return out;
}

Uint8List _wmf(List<Uint8List> records) {
  final eof = _wordRecord(0, const <int>[]);
  final totalBytes = 18 +
      records.fold<int>(0, (sum, record) => sum + record.length) +
      eof.length;
  final out = Uint8List(totalBytes);
  final data = ByteData.sublistView(out)
    ..setUint16(0, 1, Endian.little)
    ..setUint16(2, 9, Endian.little)
    ..setUint16(4, 0x0300, Endian.little)
    ..setUint32(6, totalBytes ~/ 2, Endian.little)
    ..setUint16(10, 4, Endian.little);
  var maxWords = 3;
  var offset = 18;
  for (final record in <Uint8List>[...records, eof]) {
    out.setRange(offset, offset + record.length, record);
    offset += record.length;
    maxWords = record.length ~/ 2 > maxWords ? record.length ~/ 2 : maxWords;
  }
  data.setUint32(12, maxWords, Endian.little);
  return out;
}

VsdxPage _imagePage(String part) => VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 1,
      heightInches: 1,
      shapes: <VsdxShape>[
        VsdxShapeFactory.picture(
          id: 1,
          pinX: 0.5,
          pinY: 0.5,
          width: 1,
          height: 1,
          imagePartName: part,
        ),
      ],
    );

void main() {
  test('POLYPOLYGON remains one even-odd compound path through round-trip', () {
    final payload = _wmf(<Uint8List>[
      _brushRecord(0x000000ff), // COLORREF red
      _wordRecord(0x012d, const <int>[0]),
      _wordRecord(0x0106, const <int>[1]), // ALTERNATE
      _polyPolygonRecord(),
    ]);
    final drawing = parseWmfDrawing(payload)!;
    final path = drawing.ops.whereType<MetafilePathOp>().single;
    expect(path.fillArgb, 0xffff0000);
    expect(path.evenOddFill, isTrue);
    expect(path.additionalContours, hasLength(1));
    final winding = parseWmfDrawing(_wmf(<Uint8List>[
      _brushRecord(0x000000ff),
      _wordRecord(0x012d, const <int>[0]),
      _wordRecord(0x0106, const <int>[2]), // WINDING
      _polyPolygonRecord(),
    ]))!
        .ops
        .whereType<MetafilePathOp>()
        .single;
    expect(winding.evenOddFill, isFalse);

    const part = '/visio/media/compound.wmf';
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-wmf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(
      _imagePage(part),
      images: images,
    );
    expect(svg, contains('fill-rule="evenodd"'));
    expect(RegExp(r'<path d="M [^"]+ M ').hasMatch(svg), isTrue);

    const parser = DocumentParser();
    const writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var document = parser.parse(blank);
    document =
        document.copyWith(images: images).replacePage(0, _imagePage(part));
    final reopened = parser.parse(writer.write(
      originalBytes: blank,
      edited: document,
    ));
    final roundTripped = reopened.images.findByPart(part)!.bytes;
    expect(roundTripped, payload);
    expect(
      parseWmfDrawing(roundTripped)!
          .ops
          .whereType<MetafilePathOp>()
          .single
          .additionalContours,
      hasLength(1),
    );
  });

  test('WMF SaveDC clips and positive RestoreDC unwind the full stack', () {
    final payload = _wmf(<Uint8List>[
      _wordRecord(0x001e, const <int>[]),
      _wordRecord(0x0416, const <int>[80, 80, 20, 20]),
      _wordRecord(0x001e, const <int>[]),
      _wordRecord(0x0415, const <int>[60, 60, 40, 40]),
      _wordRecord(0x041b, const <int>[100, 100, 0, 0]),
      _wordRecord(0x0127, const <int>[1]),
      _wordRecord(0x0214, const <int>[0, 0]),
      _wordRecord(0x0213, const <int>[100, 100]),
    ]);
    final drawing = parseWmfDrawing(payload)!;
    expect(drawing.ops.whereType<MetafileSaveDcOp>(), hasLength(2));
    expect(drawing.ops.whereType<MetafileClipRectOp>(), hasLength(2));
    expect(
      drawing.ops.whereType<MetafileRestoreDcOp>().single.count,
      2,
    );
    final clips = drawing.ops.whereType<MetafileClipRectOp>().toList();
    expect(clips.first.mode, MetafileClipCombineMode.intersect);
    expect(clips.last.mode, MetafileClipCombineMode.exclude);

    const part = '/visio/media/clipped.wmf';
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-wmf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(
      _imagePage(part),
      images: images,
    );
    expect(RegExp('id="wmf-dc-clip-').allMatches(svg), hasLength(2));
  });

  test('SETTEXTJUSTIFICATION distributes signed width over spaces', () {
    for (final extra in <int>[6, -2]) {
      final payload = _wmf(<Uint8List>[
        _wordRecord(0x0103, const <int>[8]), // MM_ANISOTROPIC
        _wordRecord(0x020a, <int>[2, extra]),
        _textOutRecord('A B C', 10, 20),
      ]);
      final text =
          parseWmfDrawing(payload)!.ops.whereType<MetafileTextOp>().single;
      final perBreak = extra / 2;
      expect(text.advancesX, hasLength(5));
      expect(
        text.advancesX![1] - text.advancesX![0],
        closeTo(perBreak, 1e-9),
      );
      expect(
        text.advancesX![3] - text.advancesX![2],
        closeTo(perBreak, 1e-9),
      );
    }
  });

  test('window and viewport records map paths clips text and pen metrics', () {
    final payload = _wmf(<Uint8List>[
      _penRecord(style: 1, width: 3), // PS_DASH
      _wordRecord(0x012d, const <int>[0]),
      _wordRecord(0x0103, const <int>[8]), // MM_ANISOTROPIC
      _wordRecord(0x020b, const <int>[20, 10]),
      _wordRecord(0x020c, const <int>[100, 200]),
      _wordRecord(0x020d, const <int>[7, 5]),
      _wordRecord(0x020e, const <int>[-300, 400]),
      _wordRecord(0x0416, const <int>[120, 210, 20, 10]),
      _wordRecord(0x0214, const <int>[20, 10]),
      _wordRecord(0x0213, const <int>[120, 210]),
      _textOutRecord('Mapped', 110, 70),
    ]);

    final drawing = parseWmfDrawing(payload)!;
    expect(drawing.width, closeTo(400, 1e-9));
    expect(drawing.height, closeTo(300, 1e-9));

    final clip = drawing.ops.whereType<MetafileClipRectOp>().single.rect;
    expect(clip.left, closeTo(5, 1e-9));
    expect(clip.top, closeTo(-293, 1e-9));
    expect(clip.right, closeTo(405, 1e-9));
    expect(clip.bottom, closeTo(7, 1e-9));

    final path = drawing.ops.whereType<MetafilePathOp>().single;
    expect(path.points.first.x, closeTo(5, 1e-9));
    expect(path.points.first.y, closeTo(7, 1e-9));
    expect(path.points.last.x, closeTo(405, 1e-9));
    expect(path.points.last.y, closeTo(-293, 1e-9));
    expect(path.strokeWidth, closeTo(6, 1e-9));
    expect(path.strokeDashPattern, <double>[24, 8]);

    final text = drawing.ops.whereType<MetafileTextOp>().single;
    expect(text.x, closeTo(205, 1e-9));
    expect(text.y, closeTo(-143, 1e-9));
    expect(text.fontHeight, closeTo(36, 1e-9));

    const part = '/visio/media/mapped.wmf';
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-wmf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(
      _imagePage(part),
      images: images,
    );
    expect(svg, contains('<clipPath'));
    expect(svg, contains('stroke-dasharray='));
    expect(svg, contains('Mapped'));

    const parser = DocumentParser();
    const writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var document = parser.parse(blank);
    document = document.copyWith(images: images).replacePage(
          0,
          _imagePage(part),
        );
    final reopened = parser.parse(writer.write(
      originalBytes: blank,
      edited: document,
    ));
    final roundTripped = reopened.images.findByPart(part)!.bytes;
    expect(roundTripped, payload);
    final reopenedPath =
        parseWmfDrawing(roundTripped)!.ops.whereType<MetafilePathOp>().single;
    expect(reopenedPath.points.last.x, closeTo(405, 1e-9));
    expect(reopenedPath.points.last.y, closeTo(-293, 1e-9));
  });

  test('offset and scale mapping state is restored by RestoreDC', () {
    final payload = _wmf(<Uint8List>[
      _wordRecord(0x0103, const <int>[8]), // MM_ANISOTROPIC
      _wordRecord(0x020b, const <int>[0, 0]),
      _wordRecord(0x020c, const <int>[100, 100]),
      _wordRecord(0x020d, const <int>[0, 0]),
      _wordRecord(0x020e, const <int>[100, 100]),
      _wordRecord(0x001e, const <int>[]), // SaveDC
      _wordRecord(0x020f, const <int>[20, 10]),
      _wordRecord(0x0211, const <int>[7, 5]),
      _wordRecord(0x0410, const <int>[1, 2, 1, 2]),
      _wordRecord(0x0412, const <int>[1, 3, 1, 4]),
      _wordRecord(0x0214, const <int>[20, 10]),
      _wordRecord(0x0213, const <int>[120, 110]),
      _wordRecord(0x0127, const <int>[0xffff]), // RestoreDC(-1)
      _wordRecord(0x0410, const <int>[0, 5, 1, 7]), // invalid, ignored
      _wordRecord(0x0214, const <int>[0, 0]),
      _wordRecord(0x0213, const <int>[100, 100]),
    ]);

    final drawing = parseWmfDrawing(payload)!;
    final paths = drawing.ops.whereType<MetafilePathOp>().toList();
    expect(paths, hasLength(2));
    expect(paths.first.points.first.x, closeTo(5, 1e-9));
    expect(paths.first.points.first.y, closeTo(7, 1e-9));
    expect(paths.first.points.last.x, closeTo(205, 1e-9));
    expect(paths.first.points.last.y, closeTo(157, 1e-9));
    expect(paths.last.points.first.x, closeTo(0, 1e-9));
    expect(paths.last.points.first.y, closeTo(0, 1e-9));
    expect(paths.last.points.last.x, closeTo(100, 1e-9));
    expect(paths.last.points.last.y, closeTo(100, 1e-9));
    expect(drawing.ops.whereType<MetafileSaveDcOp>(), hasLength(1));
    expect(drawing.ops.whereType<MetafileRestoreDcOp>(), hasLength(1));
  });

  test('fixed physical mapping modes retain their bottom-up Y axis', () {
    for (final mapMode in <int>[2, 3, 4, 5, 6]) {
      final drawing = parseWmfDrawing(_wmf(<Uint8List>[
        _wordRecord(0x0103, <int>[mapMode]),
        _wordRecord(0x0214, const <int>[0, 0]),
        _wordRecord(0x0213, const <int>[100, 50]),
      ]))!;
      final path = drawing.ops.whereType<MetafilePathOp>().single;
      expect(path.points.first.x, closeTo(0, 1e-9));
      expect(path.points.first.y, closeTo(0, 1e-9));
      expect(path.points.last.x, closeTo(50, 1e-9));
      expect(path.points.last.y, closeTo(-100, 1e-9));
    }
  });

  test('pixel and source-less raster records render through all WMF forms', () {
    final payload = _wmf(<Uint8List>[
      _brushRecord(0x00ff0000), // COLORREF blue
      _wordRecord(0x012d, const <int>[0]),
      _wordRecord(0x0103, const <int>[8]), // MM_ANISOTROPIC
      _wordRecord(0x020b, const <int>[0, 0]),
      _wordRecord(0x020c, const <int>[100, 100]),
      _wordRecord(0x020d, const <int>[7, 5]),
      _wordRecord(0x020e, const <int>[300, 200]),
      _setPixelRecord(0x000000ff, 12, 22), // COLORREF red
      _patBltRecord(0x00f00021, 10, 20, 30, 15), // PATCOPY
      _patBltRecord(0x00000042, 50, 20, 10, 15), // BLACKNESS
      _patBltRecord(0x00ff0062, 70, 20, 10, 15), // WHITENESS
      _sourceLessBltRecord(0x0922, 0x00f00021, 10, 40, 10, 10),
      _sourceLessBltRecord(0x0940, 0x00f00021, 25, 40, 10, 10),
      _sourceLessBltRecord(0x0b23, 0x00f00021, 40, 40, 10, 10),
      _sourceLessBltRecord(0x0b41, 0x00f00021, 55, 40, 10, 10),
      _dibBltRecord(
        0x0940,
        x: 70,
        y: 40,
        width: 10,
        height: 10,
        rasterOperation: 0x00f00021,
      ),
    ]);

    final drawing = parseWmfDrawing(payload)!;
    final pixel = drawing.ops.whereType<MetafilePixelOp>().single;
    expect(pixel.x, closeTo(29, 1e-9));
    expect(pixel.y, closeTo(73, 1e-9));
    expect(pixel.argb, 0xffff0000);

    final paths = drawing.ops.whereType<MetafilePathOp>().toList();
    expect(paths, hasLength(8));
    expect(
      paths.map((path) => path.fillArgb),
      <int>[
        0xff0000ff,
        0xff000000,
        0xffffffff,
        0xff0000ff,
        0xff0000ff,
        0xff0000ff,
        0xff0000ff,
        0xff0000ff,
      ],
    );
    expect(paths.every((path) => path.fill && !path.stroke), isTrue);
    expect(
      paths.first.points.map((point) => (point.x, point.y)),
      <(double, double)>[(25, 67), (85, 67), (85, 112), (25, 112)],
    );

    const part = '/visio/media/raster-records.wmf';
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-wmf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(
      _imagePage(part),
      images: images,
    );
    expect(svg, contains('fill="#ff0000"'));
    expect(svg, contains('fill="#0000ff"'));
    expect(svg, contains('fill="#000000"'));
    expect(svg, contains('fill="#ffffff"'));

    const parser = DocumentParser();
    const writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var document = parser.parse(blank);
    document = document.copyWith(images: images).replacePage(
          0,
          _imagePage(part),
        );
    final reopened = parser.parse(writer.write(
      originalBytes: blank,
      edited: document,
    ));
    final roundTripped = reopened.images.findByPart(part)!.bytes;
    expect(roundTripped, payload);
    final reopenedDrawing = parseWmfDrawing(roundTripped)!;
    expect(reopenedDrawing.ops.whereType<MetafilePixelOp>(), hasLength(1));
    expect(reopenedDrawing.ops.whereType<MetafilePathOp>(), hasLength(8));
  });

  test('SETTEXTCHAREXTRA combines with justification and restores with DC', () {
    final payload = _wmf(<Uint8List>[
      _wordRecord(0x0108, const <int>[3]),
      _wordRecord(0x001e, const <int>[]),
      _wordRecord(0x0108, const <int>[7]),
      _textOutRecord('A B', 10, 10),
      _wordRecord(0x0127, const <int>[0xffff]),
      _wordRecord(0x020a, const <int>[1, 4]),
      _textOutRecord('A B', 10, 30),
    ]);

    final texts =
        parseWmfDrawing(payload)!.ops.whereType<MetafileTextOp>().toList();
    expect(texts, hasLength(2));
    for (final advance in texts.first.advancesX!) {
      expect(advance, closeTo(13.6, 1e-9));
    }
    expect(texts.last.advancesX, hasLength(3));
    expect(texts.last.advancesX![0], closeTo(9.6, 1e-9));
    expect(texts.last.advancesX![1], closeTo(13.6, 1e-9));
    expect(texts.last.advancesX![2], closeTo(9.6, 1e-9));
  });

  test('embedded DIB records retain crop, placement, order, and round-trip',
      () {
    final payload = _wmf(<Uint8List>[
      _setPixelRecord(0x000000ff, 1, 1),
      _dibBltRecord(0x0940, x: 10, y: 20, width: 12, height: 8),
      _dibBltRecord(
        0x0b41,
        x: 30,
        y: 20,
        width: 14,
        height: 8,
        sourceX: 1,
        sourceWidth: 1,
        sourceHeight: 2,
      ),
      _dibBltRecord(
        0x0f43,
        x: 60,
        y: 20,
        width: -10,
        height: 8,
        sourceWidth: 2,
        sourceHeight: 2,
      ),
      _setPixelRecord(0x00ff0000, 79, 39),
    ]);

    final drawing = parseWmfDrawing(payload)!;
    expect(drawing.ops.map((op) => op.runtimeType), <Type>[
      MetafilePixelOp,
      MetafileBitmapOp,
      MetafileBitmapOp,
      MetafileBitmapOp,
      MetafilePixelOp,
    ]);
    final bitmaps = drawing.ops.whereType<MetafileBitmapOp>().toList();
    expect(bitmaps, hasLength(3));
    expect((bitmaps.first.pixelWidth, bitmaps.first.pixelHeight), (2, 2));
    expect(bitmaps.first.bmpBytes.sublist(0, 2), <int>[0x42, 0x4d]);
    expect(bitmaps.first.destination, isA<MetafileRect>());
    expect(
      (
        bitmaps.first.destination.left,
        bitmaps.first.destination.top,
        bitmaps.first.destination.right,
        bitmaps.first.destination.bottom,
      ),
      (10, 20, 22, 28),
    );
    expect(bitmaps.first.source, isNull);
    expect(
      (
        bitmaps[1].source!.left,
        bitmaps[1].source!.top,
        bitmaps[1].source!.right,
        bitmaps[1].source!.bottom,
      ),
      (1, 0, 2, 2),
    );
    expect(bitmaps.last.destination.left, 60);
    expect(bitmaps.last.destination.right, 50);

    const part = '/visio/media/embedded-dibs.wmf';
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-wmf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(
      _imagePage(part),
      images: images,
    );
    expect(RegExp('data:image/bmp;base64,').allMatches(svg), hasLength(3));
    expect(svg, contains('viewBox="1 0 1 2"'));
    expect(svg, contains('scale(-1 1)'));
    final firstPixel = svg.indexOf('fill="#ff0000"');
    final firstBitmap = svg.indexOf('data:image/bmp;base64,');
    final lastPixel = svg.indexOf('fill="#0000ff"');
    expect(firstPixel, lessThan(firstBitmap));
    expect(lastPixel, greaterThan(firstBitmap));

    const parser = DocumentParser();
    const writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var document = parser.parse(blank);
    document =
        document.copyWith(images: images).replacePage(0, _imagePage(part));
    final reopened = parser.parse(writer.write(
      originalBytes: blank,
      edited: document,
    ));
    final roundTripped = reopened.images.findByPart(part)!.bytes;
    expect(roundTripped, payload);
    expect(
      parseWmfDrawing(roundTripped)!.ops.whereType<MetafileBitmapOp>(),
      hasLength(3),
    );
  });

  test('ROP2 and stretch mode replay and restore through WMF round-trip', () {
    final payload = _wmf(<Uint8List>[
      _brushRecord(0x000000ff), // COLORREF red
      _wordRecord(0x012d, const <int>[0]),
      _wordRecord(0x0104, const <int>[6]), // R2_NOT
      _wordRecord(0x041b, const <int>[20, 20, 0, 0]),
      _wordRecord(0x001e, const <int>[]), // SaveDC
      _wordRecord(0x0104, const <int>[11]), // R2_NOP
      _wordRecord(0x041b, const <int>[20, 50, 0, 30]),
      _wordRecord(0x0107, const <int>[3]), // COLORONCOLOR
      _dibBltRecord(
        0x0b41,
        x: 0,
        y: 30,
        width: 20,
        height: 20,
        sourceWidth: 2,
        sourceHeight: 2,
      ),
      _wordRecord(0x001e, const <int>[]), // SaveDC
      _wordRecord(0x0107, const <int>[4]), // HALFTONE
      _dibBltRecord(
        0x0b41,
        x: 30,
        y: 30,
        width: 20,
        height: 20,
        sourceWidth: 2,
        sourceHeight: 2,
      ),
      _wordRecord(0x0127, const <int>[0xffff]), // RestoreDC(-1)
      _dibBltRecord(
        0x0b41,
        x: 60,
        y: 30,
        width: 20,
        height: 20,
        sourceWidth: 2,
        sourceHeight: 2,
      ),
      _wordRecord(0x0127, const <int>[0xffff]), // RestoreDC(-1)
      _wordRecord(0x041b, const <int>[20, 80, 0, 60]),
    ]);

    final drawing = parseWmfDrawing(payload)!;
    expect(
      drawing.ops
          .whereType<MetafilePathOp>()
          .map((path) => path.rasterOperation),
      <MetafileRasterOperation>[
        MetafileRasterOperation.invert,
        MetafileRasterOperation.nop,
        MetafileRasterOperation.invert,
      ],
    );
    expect(
      drawing.ops.whereType<MetafileBitmapOp>().map((bitmap) => bitmap.filter),
      <MetafileBitmapFilter>[
        MetafileBitmapFilter.nearest,
        MetafileBitmapFilter.linear,
        MetafileBitmapFilter.nearest,
      ],
    );

    const part = '/visio/media/raster-state.wmf';
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-wmf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(
      _imagePage(part),
      images: images,
    );
    expect(RegExp('mix-blend-mode:difference').allMatches(svg), hasLength(2));
    expect(RegExp('image-rendering:pixelated').allMatches(svg), hasLength(2));

    const parser = DocumentParser();
    const writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var document = parser.parse(blank);
    document =
        document.copyWith(images: images).replacePage(0, _imagePage(part));
    final reopened = parser.parse(writer.write(
      originalBytes: blank,
      edited: document,
    ));
    final roundTripped = reopened.images.findByPart(part)!.bytes;
    expect(roundTripped, payload);
    final reopenedDrawing = parseWmfDrawing(roundTripped)!;
    expect(
      reopenedDrawing.ops
          .whereType<MetafilePathOp>()
          .map((path) => path.rasterOperation),
      <MetafileRasterOperation>[
        MetafileRasterOperation.invert,
        MetafileRasterOperation.nop,
        MetafileRasterOperation.invert,
      ],
    );
    expect(
      reopenedDrawing.ops
          .whereType<MetafileBitmapOp>()
          .map((bitmap) => bitmap.filter),
      <MetafileBitmapFilter>[
        MetafileBitmapFilter.nearest,
        MetafileBitmapFilter.linear,
        MetafileBitmapFilter.nearest,
      ],
    );
  });

  test('SETDIBTODEV renders its selected scan lines and round-trips', () {
    final payload = _wmf(<Uint8List>[
      _setPixelRecord(0x000000ff, 1, 1),
      _setDibToDevRecord(
        x: 10,
        y: 20,
        sourceX: 1,
        sourceY: 0,
        width: 1,
        height: 2,
        startScan: 1,
        scanCount: 1,
      ),
      _setPixelRecord(0x00ff0000, 12, 22),
    ]);

    final drawing = parseWmfDrawing(payload)!;
    expect(drawing.ops.map((op) => op.runtimeType), <Type>[
      MetafilePixelOp,
      MetafileBitmapOp,
      MetafilePixelOp,
    ]);
    final bitmap = drawing.ops.whereType<MetafileBitmapOp>().single;
    expect((bitmap.pixelWidth, bitmap.pixelHeight), (2, 2));
    expect(
      (
        bitmap.destination.left,
        bitmap.destination.top,
        bitmap.destination.right,
        bitmap.destination.bottom,
      ),
      (10, 20, 11, 21),
    );
    expect(
      (
        bitmap.source!.left,
        bitmap.source!.top,
        bitmap.source!.right,
        bitmap.source!.bottom,
      ),
      (1, 1, 2, 2),
    );

    const part = '/visio/media/set-dib-to-dev.wmf';
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-wmf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(
      _imagePage(part),
      images: images,
    );
    expect(svg, contains('data:image/bmp;base64,'));
    expect(svg, contains('viewBox="1 1 1 1"'));
    expect(svg.indexOf('fill="#ff0000"'), lessThan(svg.indexOf('data:image')));
    expect(
        svg.indexOf('fill="#0000ff"'), greaterThan(svg.indexOf('data:image')));

    const parser = DocumentParser();
    const writer = VsdxWriter();
    final blank = writer.emptyDocument();
    final edited = parser
        .parse(blank)
        .copyWith(images: images)
        .replacePage(0, _imagePage(part));
    final reopened = parser.parse(writer.write(
      originalBytes: blank,
      edited: edited,
    ));
    final roundTripped = reopened.images.findByPart(part)!.bytes;
    expect(roundTripped, payload);
    final reopenedBitmap =
        parseWmfDrawing(roundTripped)!.ops.whereType<MetafileBitmapOp>().single;
    expect(reopenedBitmap.source!.top, 1);
    expect(reopenedBitmap.destination.bottom, 21);
  });

  test('WMF DIB and Bitmap16 pattern brushes render and round-trip', () {
    final payload = _wmf(<Uint8List>[
      _dibPatternBrushRecord(style: 5), // BS_DIBPATTERNPT with a DIB
      _dibPatternBrushRecord(
        style: 3,
        target: _bitmap16Pattern(headerSize: 10),
      ),
      _createPatternBrushRecord(),
      _wordRecord(0x012d, const <int>[0]),
      _wordRecord(0x041b, const <int>[20, 20, 0, 0]),
      _wordRecord(0x012d, const <int>[1]),
      _wordRecord(0x041b, const <int>[20, 50, 0, 30]),
      _wordRecord(0x012d, const <int>[2]),
      _wordRecord(0x041b, const <int>[20, 80, 0, 60]),
    ]);

    final paths = parseWmfDrawing(payload)!
        .ops
        .whereType<MetafilePathOp>()
        .toList(growable: false);
    expect(paths, hasLength(3));
    expect(paths.every((path) => path.fill), isTrue);
    expect(paths.every((path) => path.fillPatternBmpBytes != null), isTrue);
    final bitmap16Bmps = paths
        .skip(1)
        .map((path) => ByteData.sublistView(path.fillPatternBmpBytes!))
        .toList(growable: false);
    for (final bmp in bitmap16Bmps) {
      expect(bmp.getUint8(0), 0x42);
      expect(bmp.getUint8(1), 0x4d);
      expect(bmp.getInt32(18, Endian.little), 8);
      expect(bmp.getInt32(22, Endian.little), -2);
      expect(bmp.getUint16(28, Endian.little), 1);
    }

    const part = '/visio/media/pattern-brushes.wmf';
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-wmf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(
      _imagePage(part),
      images: images,
    );
    expect(RegExp(r'<pattern id="wmf-bitmap-pattern-').allMatches(svg),
        hasLength(3));
    expect(RegExp('data:image/bmp;base64,').allMatches(svg), hasLength(3));

    const parser = DocumentParser();
    const writer = VsdxWriter();
    final blank = writer.emptyDocument();
    final edited = parser
        .parse(blank)
        .copyWith(images: images)
        .replacePage(0, _imagePage(part));
    final reopened = parser.parse(writer.write(
      originalBytes: blank,
      edited: edited,
    ));
    final roundTripped = reopened.images.findByPart(part)!.bytes;
    expect(roundTripped, payload);
    expect(
      parseWmfDrawing(roundTripped)!
          .ops
          .whereType<MetafilePathOp>()
          .where((path) => path.fillPatternBmpBytes != null),
      hasLength(3),
    );
  });
}
