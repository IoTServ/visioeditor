import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _bmi({required int bpp}) {
  final out = Uint8List(40);
  ByteData.sublistView(out)
    ..setUint32(0, 40, Endian.little)
    ..setInt32(4, 2, Endian.little)
    ..setInt32(8, 2, Endian.little)
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, bpp, Endian.little)
    ..setUint32(20, 16, Endian.little);
  return out;
}

Uint8List _bits({required int bpp}) => Uint8List.fromList(
      bpp == 24
          ? const <int>[
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
            ]
          : const <int>[
              255,
              0,
              0,
              255,
              255,
              255,
              255,
              255,
              0,
              0,
              255,
              64,
              0,
              255,
              0,
              192,
            ],
    );

Uint8List _maskBmi() {
  final out = Uint8List(40);
  ByteData.sublistView(out)
    ..setUint32(0, 40, Endian.little)
    ..setInt32(4, 2, Endian.little)
    ..setInt32(8, 2, Endian.little)
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, 1, Endian.little)
    ..setUint32(20, 8, Endian.little);
  return out;
}

Uint8List _maskBits() => Uint8List.fromList(const <int>[
      0x40, 0, 0, 0, // bottom row: skip, copy
      0x80, 0, 0, 0, // top row: copy, skip
    ]);

Uint8List _pixel(int x, int y, int colorRef) {
  final out = Uint8List(20);
  ByteData.sublistView(out)
    ..setUint32(0, 15, Endian.little)
    ..setUint32(4, 20, Endian.little)
    ..setInt32(8, x, Endian.little)
    ..setInt32(12, y, Endian.little)
    ..setUint32(16, colorRef, Endian.little);
  return out;
}

Uint8List _commonBlt(
  int type, {
  int x = 10,
  int sourceX = 0,
  int sourceWidth = 2,
  bool alpha = false,
  bool transparent = false,
}) {
  final fixed = type == 76 ? 100 : 108;
  final bmi = _bmi(bpp: alpha ? 32 : 24);
  final bits = _bits(bpp: alpha ? 32 : 24);
  final out = Uint8List(fixed + bmi.length + bits.length);
  final data = ByteData.sublistView(out)
    ..setUint32(0, type, Endian.little)
    ..setUint32(4, out.length, Endian.little)
    ..setInt32(16, 120, Endian.little) // Bounds right
    ..setInt32(20, 80, Endian.little) // Bounds bottom
    ..setInt32(24, x, Endian.little)
    ..setInt32(28, 10, Endian.little)
    ..setInt32(32, 12, Endian.little)
    ..setInt32(36, 8, Endian.little)
    ..setUint32(
      40,
      alpha
          ? 0x01800000 // AC_SRC_ALPHA + constant alpha 128
          : transparent
              ? 0x000000ff // COLORREF red
              : 0x00cc0020,
      Endian.little,
    )
    ..setInt32(44, sourceX, Endian.little)
    ..setInt32(48, 0, Endian.little)
    // XformSrc identity at record offsets 52..75.
    ..setFloat32(52, 1, Endian.little)
    ..setFloat32(68, 1, Endian.little)
    ..setUint32(80, 0, Endian.little) // UsageSrc
    ..setUint32(84, fixed, Endian.little)
    ..setUint32(88, bmi.length, Endian.little)
    ..setUint32(92, fixed + bmi.length, Endian.little)
    ..setUint32(96, bits.length, Endian.little);
  if (type != 76) {
    data.setInt32(100, sourceWidth, Endian.little);
    data.setInt32(104, 2, Endian.little);
  }
  out.setRange(fixed, fixed + bmi.length, bmi);
  out.setRange(fixed + bmi.length, out.length, bits);
  return out;
}

Uint8List _stretchDibits() {
  final bmi = _bmi(bpp: 24);
  final bits = _bits(bpp: 24);
  const fixed = 80;
  final out = Uint8List(fixed + bmi.length + bits.length);
  ByteData.sublistView(out)
    ..setUint32(0, 81, Endian.little)
    ..setUint32(4, out.length, Endian.little)
    ..setInt32(24, 50, Endian.little)
    ..setInt32(28, 10, Endian.little)
    ..setInt32(32, 0, Endian.little)
    ..setInt32(36, 0, Endian.little)
    ..setInt32(40, 2, Endian.little)
    ..setInt32(44, 2, Endian.little)
    ..setUint32(48, fixed, Endian.little)
    ..setUint32(52, bmi.length, Endian.little)
    ..setUint32(56, fixed + bmi.length, Endian.little)
    ..setUint32(60, bits.length, Endian.little)
    ..setUint32(64, 0, Endian.little)
    ..setUint32(68, 0x00cc0020, Endian.little)
    ..setInt32(72, -12, Endian.little)
    ..setInt32(76, 8, Endian.little);
  out.setRange(fixed, fixed + bmi.length, bmi);
  out.setRange(fixed + bmi.length, out.length, bits);
  return out;
}

Uint8List _setDibitsToDevice() {
  final bmi = _bmi(bpp: 24);
  final bits = _bits(bpp: 24);
  const fixed = 76;
  final out = Uint8List(fixed + bmi.length + bits.length);
  ByteData.sublistView(out)
    ..setUint32(0, 80, Endian.little)
    ..setUint32(4, out.length, Endian.little)
    ..setInt32(24, 70, Endian.little)
    ..setInt32(28, 10, Endian.little)
    ..setInt32(32, 0, Endian.little)
    ..setInt32(36, 0, Endian.little)
    ..setInt32(40, 2, Endian.little)
    ..setInt32(44, 2, Endian.little)
    ..setUint32(48, fixed, Endian.little)
    ..setUint32(52, bmi.length, Endian.little)
    ..setUint32(56, fixed + bmi.length, Endian.little)
    ..setUint32(60, bits.length, Endian.little)
    ..setUint32(64, 0, Endian.little)
    ..setUint32(68, 0, Endian.little)
    ..setUint32(72, 2, Endian.little);
  out.setRange(fixed, fixed + bmi.length, bmi);
  out.setRange(fixed + bmi.length, out.length, bits);
  return out;
}

Uint8List _maskBlt() {
  final bmi = _bmi(bpp: 24);
  final bits = _bits(bpp: 24);
  final maskBmi = _maskBmi();
  final maskBits = _maskBits();
  const fixed = 128;
  final out = Uint8List(
    fixed + bmi.length + bits.length + maskBmi.length + maskBits.length,
  );
  final sourceBmiOffset = fixed;
  final sourceBitsOffset = sourceBmiOffset + bmi.length;
  final maskBmiOffset = sourceBitsOffset + bits.length;
  final maskBitsOffset = maskBmiOffset + maskBmi.length;
  ByteData.sublistView(out)
    ..setUint32(0, 78, Endian.little)
    ..setUint32(4, out.length, Endian.little)
    ..setInt32(24, 80, Endian.little)
    ..setInt32(28, 30, Endian.little)
    ..setInt32(32, 12, Endian.little)
    ..setInt32(36, 8, Endian.little)
    ..setUint32(40, 0xaacc0020, Endian.little)
    ..setFloat32(52, 1, Endian.little)
    ..setFloat32(68, 1, Endian.little)
    ..setUint32(80, 0, Endian.little)
    ..setUint32(84, sourceBmiOffset, Endian.little)
    ..setUint32(88, bmi.length, Endian.little)
    ..setUint32(92, sourceBitsOffset, Endian.little)
    ..setUint32(96, bits.length, Endian.little)
    ..setUint32(108, 0, Endian.little)
    ..setUint32(112, maskBmiOffset, Endian.little)
    ..setUint32(116, maskBmi.length, Endian.little)
    ..setUint32(120, maskBitsOffset, Endian.little)
    ..setUint32(124, maskBits.length, Endian.little);
  out.setRange(sourceBmiOffset, sourceBitsOffset, bmi);
  out.setRange(sourceBitsOffset, maskBmiOffset, bits);
  out.setRange(maskBmiOffset, maskBitsOffset, maskBmi);
  out.setRange(maskBitsOffset, out.length, maskBits);
  return out;
}

Uint8List _plgBlt() {
  final bmi = _bmi(bpp: 24);
  final bits = _bits(bpp: 24);
  final maskBmi = _maskBmi();
  final maskBits = _maskBits();
  const fixed = 140;
  final out = Uint8List(
    fixed + bmi.length + bits.length + maskBmi.length + maskBits.length,
  );
  final sourceBmiOffset = fixed;
  final sourceBitsOffset = sourceBmiOffset + bmi.length;
  final maskBmiOffset = sourceBitsOffset + bits.length;
  final maskBitsOffset = maskBmiOffset + maskBmi.length;
  ByteData.sublistView(out)
    ..setUint32(0, 79, Endian.little)
    ..setUint32(4, out.length, Endian.little)
    ..setInt32(24, 85, Endian.little)
    ..setInt32(28, 30, Endian.little)
    ..setInt32(32, 105, Endian.little)
    ..setInt32(36, 35, Endian.little)
    ..setInt32(40, 80, Endian.little)
    ..setInt32(44, 50, Endian.little)
    ..setInt32(56, 2, Endian.little)
    ..setInt32(60, 2, Endian.little)
    ..setFloat32(64, 1, Endian.little)
    ..setFloat32(80, 1, Endian.little)
    ..setUint32(92, 0, Endian.little)
    ..setUint32(96, sourceBmiOffset, Endian.little)
    ..setUint32(100, bmi.length, Endian.little)
    ..setUint32(104, sourceBitsOffset, Endian.little)
    ..setUint32(108, bits.length, Endian.little)
    ..setUint32(120, 0, Endian.little)
    ..setUint32(124, maskBmiOffset, Endian.little)
    ..setUint32(128, maskBmi.length, Endian.little)
    ..setUint32(132, maskBitsOffset, Endian.little)
    ..setUint32(136, maskBits.length, Endian.little);
  out.setRange(sourceBmiOffset, sourceBitsOffset, bmi);
  out.setRange(sourceBitsOffset, maskBmiOffset, bits);
  out.setRange(maskBmiOffset, maskBitsOffset, maskBmi);
  out.setRange(maskBitsOffset, out.length, maskBits);
  return out;
}

Uint8List _emf(List<Uint8List> records) {
  final total =
      88 + records.fold<int>(0, (sum, record) => sum + record.length) + 8;
  final out = Uint8List(total);
  final data = ByteData.sublistView(out)
    ..setUint32(0, 1, Endian.little)
    ..setUint32(4, 88, Endian.little)
    ..setInt32(16, 120, Endian.little)
    ..setInt32(20, 80, Endian.little)
    ..setInt32(32, 3175, Endian.little)
    ..setInt32(36, 2117, Endian.little)
    ..setUint32(40, 0x464d4520, Endian.little)
    ..setUint32(44, 0x00010000, Endian.little)
    ..setUint32(48, total, Endian.little)
    ..setUint32(52, records.length + 2, Endian.little)
    ..setUint16(56, 1, Endian.little);
  var offset = 88;
  for (final record in records) {
    out.setRange(offset, offset + record.length, record);
    offset += record.length;
  }
  data.setUint32(offset, 14, Endian.little);
  data.setUint32(offset + 4, 8, Endian.little);
  return out;
}

VsdxPage _imagePage(String part) => VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 2,
      heightInches: 1,
      shapes: <VsdxShape>[
        VsdxShapeFactory.picture(
          id: 1,
          pinX: 1,
          pinY: 0.5,
          width: 2,
          height: 1,
          imagePartName: part,
        ),
      ],
    );

void main() {
  test('all EMF bitmap records retain placement, alpha, order, and round-trip',
      () {
    final payload = _emf(<Uint8List>[
      _pixel(1, 1, 0x000000ff),
      _commonBlt(76, x: 10),
      _commonBlt(77, x: 30, sourceX: 2, sourceWidth: -2),
      _stretchDibits(),
      _setDibitsToDevice(),
      _maskBlt(),
      _plgBlt(),
      _commonBlt(114, x: 85, alpha: true),
      _commonBlt(116, x: 100, transparent: true),
      _pixel(119, 79, 0x00ff0000),
    ]);

    final drawing = parseEmfDrawing(payload)!;
    expect(drawing.ops.map((op) => op.runtimeType), <Type>[
      MetafilePixelOp,
      MetafileBitmapOp,
      MetafileBitmapOp,
      MetafileBitmapOp,
      MetafileBitmapOp,
      MetafileBitmapOp,
      MetafileBitmapOp,
      MetafileBitmapOp,
      MetafileBitmapOp,
      MetafilePixelOp,
    ]);
    final bitmaps = drawing.ops.whereType<MetafileBitmapOp>().toList();
    expect(bitmaps, hasLength(8));
    expect(bitmaps.first.destination, isA<MetafileRect>());
    expect(bitmaps[1].source!.left, 2);
    expect(bitmaps[1].source!.right, 0);
    expect(bitmaps[2].destination.left, 50);
    expect(bitmaps[2].destination.right, 38);
    expect(bitmaps[4].destination.left, 80);
    expect(bitmaps[4].bmpBytes[141], 0);
    expect(bitmaps[4].bmpBytes[145], 255);
    expect(
      bitmaps[5]
          .destinationParallelogram!
          .map((point) => <double>[point.x, point.y]),
      <List<double>>[
        <double>[85, 30],
        <double>[105, 35],
        <double>[80, 50],
      ],
    );
    expect(bitmaps[6].opacity, closeTo(128 / 255, 1e-12));
    expect(
        ByteData.sublistView(bitmaps[6].bmpBytes).getUint32(14, Endian.little),
        124);
    final transparent = bitmaps[7].bmpBytes;
    expect(ByteData.sublistView(transparent).getUint32(14, Endian.little), 124);
    expect(transparent[149], 0); // top-left red pixel matched the color key
    expect(transparent[153], 255); // adjacent green pixel remains opaque

    const part = '/visio/media/mixed.emf';
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-emf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(
      _imagePage(part),
      images: images,
    );
    expect(RegExp('data:image/bmp;base64,').allMatches(svg), hasLength(8));
    expect(svg, contains('scale(-1 1)'));
    expect(svg, contains('matrix(20 5 -5 20 85 30)'));
    expect(svg, contains('opacity="0.502"'));
    expect(svg.indexOf('fill="#ff0000"'), lessThan(svg.indexOf('data:image')));
    expect(svg.lastIndexOf('fill="#0000ff"'),
        greaterThan(svg.lastIndexOf('data:image')));

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
      parseEmfDrawing(roundTripped)!.ops.whereType<MetafileBitmapOp>(),
      hasLength(8),
    );
  });
}
