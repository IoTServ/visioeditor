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

Uint8List _point(int x, int y) => (ByteData(8)
      ..setInt32(0, x, Endian.little)
      ..setInt32(4, y, Endian.little))
    .buffer
    .asUint8List();

Uint8List _rect(int left, int top, int right, int bottom) => (ByteData(16)
      ..setInt32(0, left, Endian.little)
      ..setInt32(4, top, Endian.little)
      ..setInt32(8, right, Endian.little)
      ..setInt32(12, bottom, Endian.little))
    .buffer
    .asUint8List();

Uint8List _region(int left, int top, int right, int bottom) {
  final data = ByteData(48)
    ..setUint32(0, 32, Endian.little)
    ..setUint32(4, 1, Endian.little) // RDH_RECTANGLES
    ..setUint32(8, 1, Endian.little)
    ..setUint32(12, 16, Endian.little)
    ..setInt32(16, left, Endian.little)
    ..setInt32(20, top, Endian.little)
    ..setInt32(24, right, Endian.little)
    ..setInt32(28, bottom, Endian.little)
    ..setInt32(32, left, Endian.little)
    ..setInt32(36, top, Endian.little)
    ..setInt32(40, right, Endian.little)
    ..setInt32(44, bottom, Endian.little);
  return data.buffer.asUint8List();
}

Uint8List _clipEmf({bool malformedRegion = false}) {
  final output = BytesBuilder();
  output.add((ByteData(88)
        ..setUint32(0, 1, Endian.little)
        ..setUint32(4, 88, Endian.little)
        ..setInt32(16, 40, Endian.little)
        ..setInt32(20, 40, Endian.little)
        ..setUint32(40, 0x464d4520, Endian.little))
      .buffer
      .asUint8List());
  _record(output, 59); // EMR_BEGINPATH
  _record(output, 27, _point(2, 2));
  _record(output, 54, _point(38, 2));
  _record(output, 54, _point(20, 38));
  _record(output, 61); // EMR_CLOSEFIGURE
  _record(output, 60); // EMR_ENDPATH
  _record(output, 67,
      (ByteData(4)..setUint32(0, 1, Endian.little)).buffer.asUint8List());
  _record(output, 43, _rect(0, 0, 40, 40));

  _record(output, 33); // EMR_SAVEDC
  final region = _region(15, 15, 25, 25);
  final extClip = ByteData(8 + region.length)
    ..setUint32(0, malformedRegion ? 0xffff : region.length, Endian.little)
    ..setUint32(4, 4, Endian.little); // RGN_DIFF
  extClip.buffer.asUint8List().setRange(8, 8 + region.length, region);
  _record(output, 75, extClip.buffer.asUint8List());
  _record(output, 43, _rect(0, 0, 40, 40));
  _record(output, 34,
      (ByteData(4)..setInt32(0, -1, Endian.little)).buffer.asUint8List());
  _record(output, 43, _rect(0, 0, 40, 40));
  _record(output, 14);
  return Uint8List.fromList(output.toBytes());
}

VsdxPage _page(String part) => VsdxPage(
      id: 0,
      name: 'Clip',
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
  test('EMR path and extended-region clipping reach SVG and round-trip', () {
    final payload = _clipEmf();
    final drawing = parseEmfDrawing(payload)!;
    expect(
      drawing.ops.whereType<MetafileClipPathOp>().map((op) => op.mode),
      <MetafileClipCombineMode>[
        MetafileClipCombineMode.intersect,
        MetafileClipCombineMode.exclude,
      ],
    );
    expect(drawing.ops.whereType<MetafileSaveDcOp>(), hasLength(1));
    expect(drawing.ops.whereType<MetafileRestoreDcOp>(), hasLength(1));

    const part = '/visio/media/path-clipped.emf';
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-emf',
    ));
    final svg =
        VsdxToSvgSerializer().serializePage(_page(part), images: images);
    expect(
      RegExp('<clipPath id="wmf-dc-path-clip-').allMatches(svg),
      hasLength(2),
    );
    expect(svg, contains('clip-rule="evenodd"'));

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
      parseEmfDrawing(roundTripped)!.ops.whereType<MetafileClipPathOp>(),
      hasLength(2),
    );
  });

  test('malformed extended clip region does not consume later records', () {
    final drawing = parseEmfDrawing(_clipEmf(malformedRegion: true))!;
    expect(drawing.ops.whereType<MetafileClipPathOp>(), hasLength(1));
    expect(drawing.ops.whereType<MetafilePathOp>(), hasLength(3));
  });
}
