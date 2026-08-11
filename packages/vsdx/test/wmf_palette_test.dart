import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _record(int function, Uint8List params) {
  final out = Uint8List(6 + params.length + (params.length.isOdd ? 1 : 0));
  ByteData.sublistView(out)
    ..setUint32(0, out.length ~/ 2, Endian.little)
    ..setUint16(4, function, Endian.little);
  out.setRange(6, 6 + params.length, params);
  return out;
}

Uint8List _words(int function, List<int> words) {
  final params = Uint8List(words.length * 2);
  final data = ByteData.sublistView(params);
  for (var i = 0; i < words.length; i++) {
    data.setUint16(i * 2, words[i] & 0xffff, Endian.little);
  }
  return _record(function, params);
}

Uint8List _palette(List<(int, int, int)> colors) {
  final params = Uint8List(4 + colors.length * 4);
  ByteData.sublistView(params)
    ..setUint16(0, 0x0300, Endian.little)
    ..setUint16(2, colors.length, Endian.little);
  for (var i = 0; i < colors.length; i++) {
    final (red, green, blue) = colors[i];
    params[4 + i * 4] = red;
    params[5 + i * 4] = green;
    params[6 + i * 4] = blue;
  }
  return _record(0x00f7, params);
}

Uint8List _indexedDib({required int colorUsage}) {
  final tableBytes = colorUsage == 1 ? 4 : 0;
  final out = Uint8List(40 + tableBytes + 4);
  final data = ByteData.sublistView(out)
    ..setUint32(0, 40, Endian.little)
    ..setInt32(4, 2, Endian.little)
    ..setInt32(8, 1, Endian.little)
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, 1, Endian.little)
    ..setUint32(20, 4, Endian.little)
    ..setUint32(32, 2, Endian.little);
  if (colorUsage == 1) {
    data
      ..setUint16(40, 1, Endian.little)
      ..setUint16(42, 0, Endian.little);
  }
  // Pixel indexes 0 then 1, padded to a DWORD scan line.
  out[40 + tableBytes] = 0x40;
  return out;
}

Uint8List _stretchDib(int colorUsage, int x) {
  final dib = _indexedDib(colorUsage: colorUsage);
  final params = Uint8List(22 + dib.length);
  ByteData.sublistView(params)
    ..setUint32(0, 0x00cc0020, Endian.little)
    ..setUint16(4, colorUsage, Endian.little)
    ..setInt16(6, 1, Endian.little)
    ..setInt16(8, 2, Endian.little)
    ..setInt16(10, 0, Endian.little)
    ..setInt16(12, 0, Endian.little)
    ..setInt16(14, 10, Endian.little)
    ..setInt16(16, 20, Endian.little)
    ..setInt16(18, 0, Endian.little)
    ..setInt16(20, x, Endian.little);
  params.setRange(22, params.length, dib);
  return _record(0x0f43, params);
}

Uint8List _setDibToDev(int colorUsage) {
  final dib = _indexedDib(colorUsage: colorUsage);
  final params = Uint8List(18 + dib.length);
  ByteData.sublistView(params)
    ..setUint16(0, colorUsage, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, 0, Endian.little)
    ..setUint16(6, 0, Endian.little)
    ..setUint16(8, 0, Endian.little)
    ..setUint16(10, 1, Endian.little)
    ..setUint16(12, 2, Endian.little)
    ..setUint16(14, 20, Endian.little)
    ..setUint16(16, 0, Endian.little);
  params.setRange(18, params.length, dib);
  return _record(0x0d33, params);
}

Uint8List _patternBrush(int colorUsage) {
  final dib = _indexedDib(colorUsage: colorUsage);
  final params = Uint8List(4 + dib.length);
  ByteData.sublistView(params)
    ..setUint16(0, 5, Endian.little) // BS_DIBPATTERNPT
    ..setUint16(2, colorUsage, Endian.little);
  params.setRange(4, params.length, dib);
  return _record(0x0142, params);
}

Uint8List _setPaletteEntries(
  int start,
  List<(int, int, int)> colors, {
  int function = 0x0037,
}) {
  final params = Uint8List(4 + colors.length * 4);
  ByteData.sublistView(params)
    ..setUint16(0, start, Endian.little)
    ..setUint16(2, colors.length, Endian.little);
  for (var i = 0; i < colors.length; i++) {
    final (red, green, blue) = colors[i];
    params[4 + i * 4] = red;
    params[5 + i * 4] = green;
    params[6 + i * 4] = blue;
  }
  return _record(function, params);
}

Uint8List _wmf(List<Uint8List> records) {
  final eof = _words(0, const <int>[]);
  final total = 18 +
      records.fold<int>(0, (sum, record) => sum + record.length) +
      eof.length;
  final out = Uint8List(total);
  final data = ByteData.sublistView(out)
    ..setUint16(0, 1, Endian.little)
    ..setUint16(2, 9, Endian.little)
    ..setUint16(4, 0x0300, Endian.little)
    ..setUint32(6, total ~/ 2, Endian.little)
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

void _expectPalette(Uint8List bmp, List<List<int>> bgr) {
  final data = ByteData.sublistView(bmp);
  expect(data.getUint32(10, Endian.little), 62);
  for (var i = 0; i < bgr.length; i++) {
    expect(bmp.sublist(54 + i * 4, 57 + i * 4), bgr[i]);
  }
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
  test('logical palettes render all WMF DIB color-usage forms and round-trip',
      () {
    final payload = _wmf(<Uint8List>[
      _palette(const <(int, int, int)>[(255, 0, 0), (0, 255, 0)]),
      _words(0x0234, const <int>[0]), // SELECTPALETTE
      _stretchDib(1, 0), // DIB_PAL_COLORS: table indexes [1, 0].
      _setDibToDev(1),
      _patternBrush(1),
      _words(0x012d, const <int>[1]),
      _words(0x041b, const <int>[30, 30, 10, 10]),
      _stretchDib(2, 30), // DIB_PAL_INDICES: pixels index the palette.
    ]);

    final drawing = parseWmfDrawing(payload)!;
    final bitmaps = drawing.ops.whereType<MetafileBitmapOp>().toList();
    expect(bitmaps, hasLength(3));
    _expectPalette(bitmaps[0].bmpBytes, const <List<int>>[
      <int>[0, 255, 0],
      <int>[0, 0, 255],
    ]);
    _expectPalette(bitmaps[1].bmpBytes, const <List<int>>[
      <int>[0, 255, 0],
      <int>[0, 0, 255],
    ]);
    _expectPalette(bitmaps[2].bmpBytes, const <List<int>>[
      <int>[0, 0, 255],
      <int>[0, 255, 0],
    ]);
    final pattern =
        drawing.ops.whereType<MetafilePathOp>().single.fillPatternBmpBytes!;
    _expectPalette(pattern, const <List<int>>[
      <int>[0, 255, 0],
      <int>[0, 0, 255],
    ]);

    const part = '/visio/media/palette.wmf';
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-wmf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(
      _imagePage(part),
      images: images,
    );
    expect(RegExp('data:image/bmp;base64,').allMatches(svg), hasLength(4));

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
    expect(parseWmfDrawing(roundTripped)!.ops.whereType<MetafileBitmapOp>(),
        hasLength(3));
  });

  test('palette selection and edits participate in DC state', () {
    final payload = _wmf(<Uint8List>[
      _palette(const <(int, int, int)>[(255, 0, 0), (0, 255, 0)]),
      _palette(const <(int, int, int)>[(0, 0, 255), (255, 255, 0)]),
      _words(0x0234, const <int>[0]),
      _words(0x001e, const <int>[]), // SaveDC
      _words(0x0234, const <int>[1]),
      _stretchDib(2, 0),
      _words(0x0127, const <int>[0xffff]), // RestoreDC(-1)
      _setPaletteEntries(1, const <(int, int, int)>[(255, 255, 255)]),
      _setPaletteEntries(
        0,
        const <(int, int, int)>[(0, 255, 255)],
        function: 0x0436, // ANIMATEPALETTE
      ),
      _words(0x0139, const <int>[3]), // RESIZEPALETTE, adds black.
      _words(0x0035, const <int>[]), // REALIZEPALETTE
      _stretchDib(2, 30),
    ]);

    final bitmaps = parseWmfDrawing(payload)!
        .ops
        .whereType<MetafileBitmapOp>()
        .toList(growable: false);
    expect(bitmaps, hasLength(2));
    _expectPalette(bitmaps[0].bmpBytes, const <List<int>>[
      <int>[255, 0, 0],
      <int>[0, 255, 255],
    ]);
    _expectPalette(bitmaps[1].bmpBytes, const <List<int>>[
      <int>[255, 255, 0],
      <int>[255, 255, 255],
    ]);
  });
}
