import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void _record(BytesBuilder output, int type, [Uint8List? payload]) {
  payload ??= Uint8List(0);
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

void _extPen(BytesBuilder output, int handle, int joinBits) {
  final payload = ByteData(44)
    ..setInt32(0, handle, Endian.little)
    ..setUint32(20, 0x00010000 | joinBits, Endian.little) // PS_GEOMETRIC
    ..setUint32(24, 6, Endian.little)
    ..setUint32(28, 0, Endian.little) // BS_SOLID
    ..setUint32(32, 0x000000ff, Endian.little);
  _record(output, 95, payload.buffer.asUint8List());
}

void _select(BytesBuilder output, int handle) {
  final payload = ByteData(4)..setUint32(0, handle, Endian.little);
  _record(output, 37, payload.buffer.asUint8List());
}

void _miter(BytesBuilder output, double limit) {
  final payload = ByteData(4)..setFloat32(0, limit, Endian.little);
  _record(output, 58, payload.buffer.asUint8List());
}

void _polyline(BytesBuilder output, int y) {
  final payload = ByteData(44)
    ..setInt32(0, 0, Endian.little)
    ..setInt32(4, y - 8, Endian.little)
    ..setInt32(8, 40, Endian.little)
    ..setInt32(12, y + 8, Endian.little)
    ..setUint32(16, 3, Endian.little)
    ..setInt32(20, 2, Endian.little)
    ..setInt32(24, y + 8, Endian.little)
    ..setInt32(28, 20, Endian.little)
    ..setInt32(32, y - 8, Endian.little)
    ..setInt32(36, 38, Endian.little)
    ..setInt32(40, y + 8, Endian.little);
  _record(output, 4, payload.buffer.asUint8List());
}

Uint8List _penEmf() {
  final output = BytesBuilder();
  output.add((ByteData(88)
        ..setUint32(0, 1, Endian.little)
        ..setUint32(4, 88, Endian.little)
        ..setInt32(16, 40, Endian.little)
        ..setInt32(20, 60, Endian.little)
        ..setUint32(40, 0x464d4520, Endian.little))
      .buffer
      .asUint8List());
  _extPen(output, 1, 0x00002000); // PS_JOIN_MITER
  _select(output, 1);
  _miter(output, 2.5);
  _polyline(output, 10);
  _record(output, 33); // EMR_SAVEDC
  _extPen(output, 2, 0x00001000); // PS_JOIN_BEVEL
  _select(output, 2);
  _miter(output, 8);
  _polyline(output, 30);
  final restore = ByteData(4)..setInt32(0, -1, Endian.little);
  _record(output, 34, restore.buffer.asUint8List());
  _polyline(output, 50);
  _record(output, 14);
  return Uint8List.fromList(output.toBytes());
}

VsdxPage _page(String part) => VsdxPage(
      id: 0,
      name: 'Joins',
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
  test('EMF geometric pen joins and miter limit render and round-trip', () {
    final payload = _penEmf();
    final paths =
        parseEmfDrawing(payload)!.ops.whereType<MetafilePathOp>().toList();
    expect(paths.map((path) => path.strokeJoin), <MetafileStrokeJoin>[
      MetafileStrokeJoin.miter,
      MetafileStrokeJoin.bevel,
      MetafileStrokeJoin.miter,
    ]);
    expect(paths.map((path) => path.strokeMiterLimit), <double>[2.5, 8, 2.5]);

    const part = '/visio/media/joins.emf';
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-emf',
    ));
    final svg =
        VsdxToSvgSerializer().serializePage(_page(part), images: images);
    expect(RegExp('stroke-linejoin="miter"').allMatches(svg), hasLength(2));
    expect(svg, contains('stroke-linejoin="bevel"'));
    expect(RegExp('stroke-miterlimit="2.5"').allMatches(svg), hasLength(2));

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
      hasLength(3),
    );
  });
}
