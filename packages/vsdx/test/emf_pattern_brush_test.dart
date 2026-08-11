import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void _record(BytesBuilder output, int type, Uint8List payload) {
  final size = (payload.length + 11) & ~3;
  output.add((ByteData(8)
        ..setUint32(0, type, Endian.little)
        ..setUint32(4, size, Endian.little))
      .buffer
      .asUint8List());
  output.add(payload);
  for (var i = payload.length + 8; i < size; i++) {
    output.addByte(0);
  }
}

Uint8List _checkerBits() => Uint8List.fromList(<int>[
      0, 0, 0, 255, 255, 255, 0, 0, // bottom: black, white, padding
      255, 255, 255, 0, 0, 0, 0, 0, // top: white, black, padding
    ]);

Uint8List _bitmapInfo() {
  final info = ByteData(40)
    ..setUint32(0, 40, Endian.little)
    ..setInt32(4, 2, Endian.little)
    ..setInt32(8, 2, Endian.little)
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, 24, Endian.little)
    ..setUint32(20, 16, Endian.little);
  return info.buffer.asUint8List();
}

void _patternBrush(BytesBuilder output, int type, int handle,
    {bool malformed = false}) {
  final info = _bitmapInfo();
  final bits = _checkerBits();
  final payload = ByteData(24 + info.length + bits.length)
    ..setUint32(0, handle, Endian.little)
    ..setUint32(4, 0, Endian.little) // DIB_RGB_COLORS
    ..setUint32(8, malformed ? 0xffff : 32, Endian.little)
    ..setUint32(12, info.length, Endian.little)
    ..setUint32(16, 72, Endian.little)
    ..setUint32(20, bits.length, Endian.little);
  payload.buffer.asUint8List().setRange(24, 24 + info.length, info);
  payload.buffer
      .asUint8List()
      .setRange(24 + info.length, payload.lengthInBytes, bits);
  _record(output, type, payload.buffer.asUint8List());
}

void _select(BytesBuilder output, int handle) {
  final payload = ByteData(4)..setUint32(0, handle, Endian.little);
  _record(output, 37, payload.buffer.asUint8List());
}

void _rectangle(BytesBuilder output, int left, int right) {
  final payload = ByteData(16)
    ..setInt32(0, left, Endian.little)
    ..setInt32(4, 0, Endian.little)
    ..setInt32(8, right, Endian.little)
    ..setInt32(12, 20, Endian.little);
  _record(output, 43, payload.buffer.asUint8List());
}

Uint8List _patternEmf({bool malformedFirst = false}) {
  final output = BytesBuilder();
  output.add((ByteData(88)
        ..setUint32(0, 1, Endian.little)
        ..setUint32(4, 88, Endian.little)
        ..setInt32(16, 40, Endian.little)
        ..setInt32(20, 20, Endian.little)
        ..setUint32(40, 0x464d4520, Endian.little))
      .buffer
      .asUint8List());
  _patternBrush(output, 93, 1, malformed: malformedFirst);
  _select(output, 1);
  _rectangle(output, 0, 20);
  _patternBrush(output, 94, 2);
  _select(output, 2);
  _rectangle(output, 20, 40);
  _record(output, 14, Uint8List(0));
  return Uint8List.fromList(output.toBytes());
}

VsdxPage _page(String partName) => VsdxPage(
      id: 0,
      name: 'Patterns',
      widthInches: 1,
      heightInches: 0.5,
      shapes: <VsdxShape>[
        VsdxShapeFactory.picture(
          id: 1,
          pinX: 0.5,
          pinY: 0.25,
          width: 1,
          height: 0.5,
          imagePartName: partName,
        ),
      ],
    );

void main() {
  test('EMR mono and DIB pattern brushes tile through paths and SVG', () {
    final payload = _patternEmf();
    final paths = parseEmfDrawing(payload)!.ops.whereType<MetafilePathOp>();
    expect(paths, hasLength(2));
    for (final path in paths) {
      final bmp = path.fillPatternBmpBytes!;
      expect(bmp.sublist(0, 2), <int>[0x42, 0x4d]);
      expect(ByteData.sublistView(bmp).getInt32(18, Endian.little), 2);
      expect(ByteData.sublistView(bmp).getInt32(22, Endian.little), 2);
    }

    const part = '/visio/media/patterns.emf';
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-emf',
    ));
    final svg =
        VsdxToSvgSerializer().serializePage(_page(part), images: images);
    expect(RegExp('wmf-bitmap-pattern-').allMatches(svg), hasLength(4));
    expect(RegExp('data:image/bmp;base64,').allMatches(svg), hasLength(2));

    const parser = DocumentParser();
    const writer = VsdxWriter();
    final blank = writer.emptyDocument();
    final edited = parser
        .parse(blank)
        .copyWith(images: images)
        .replacePage(0, _page(part));
    final reopened = parser.parse(writer.write(
      originalBytes: blank,
      edited: edited,
    ));
    final roundTripped = reopened.images.findByPart(part)!.bytes;
    expect(roundTripped, payload);
    expect(
      parseEmfDrawing(roundTripped)!.ops.whereType<MetafilePathOp>(),
      hasLength(2),
    );
  });

  test('malformed pattern brush does not consume later records', () {
    final paths = parseEmfDrawing(_patternEmf(malformedFirst: true))!
        .ops
        .whereType<MetafilePathOp>()
        .where((path) => path.fillPatternBmpBytes != null)
        .toList();
    expect(paths, hasLength(1));
    expect(paths.single.points.first.x, 20);
    expect(paths.single.fillPatternBmpBytes, isNotNull);
  });
}
