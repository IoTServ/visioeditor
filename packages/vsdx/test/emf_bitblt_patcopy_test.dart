import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void _record(BytesBuilder out, int type, Uint8List payload) {
  final size = (payload.length + 11) & ~3;
  final header = ByteData(8)
    ..setUint32(0, type, Endian.little)
    ..setUint32(4, size, Endian.little);
  out.add(header.buffer.asUint8List());
  out.add(payload);
  for (var i = payload.length + 8; i < size; i++) {
    out.addByte(0);
  }
}

void _brush(BytesBuilder out, int handle, int colorRef) {
  final payload = ByteData(16)
    ..setInt32(0, handle, Endian.little)
    ..setUint32(4, 0, Endian.little)
    ..setUint32(8, colorRef, Endian.little);
  _record(out, 39, payload.buffer.asUint8List());
  final select = ByteData(4)..setUint32(0, handle, Endian.little);
  _record(out, 37, select.buffer.asUint8List());
}

void _bitBlt(
  BytesBuilder out,
  int x,
  int y,
  int width,
  int height, {
  int rasterOperation = 0x00f00021,
}) {
  // EMR_BITBLT fixed record: Bounds(16), destination rect(16), ROP3(4),
  // source/XFORM/background/usage/DIB offsets(56). No source DIB is required
  // by PATCOPY because the selected brush supplies every output pixel.
  final payload = ByteData(92)
    ..setInt32(0, x, Endian.little)
    ..setInt32(4, y, Endian.little)
    ..setInt32(8, x + width, Endian.little)
    ..setInt32(12, y + height, Endian.little)
    ..setInt32(16, x, Endian.little)
    ..setInt32(20, y, Endian.little)
    ..setInt32(24, width, Endian.little)
    ..setInt32(28, height, Endian.little)
    ..setUint32(32, rasterOperation, Endian.little);
  _record(out, 76, payload.buffer.asUint8List());
}

Uint8List _patCopyEmf({bool malformedFirst = false}) {
  final out = BytesBuilder();
  final header = ByteData(88)
    ..setUint32(0, 1, Endian.little)
    ..setUint32(4, 88, Endian.little)
    ..setInt32(16, 100, Endian.little)
    ..setInt32(20, 100, Endian.little)
    ..setUint32(40, 0x464d4520, Endian.little);
  out.add(header.buffer.asUint8List());
  if (malformedFirst) {
    _record(out, 76, Uint8List(20));
  }
  _brush(out, 1, 0x00ff0000); // COLORREF blue
  _bitBlt(out, 10, 20, 30, 15);
  _brush(out, 2, 0x000000ff); // COLORREF red
  _bitBlt(out, 50, 60, 20, 25);
  _bitBlt(out, 5, 5, 2, 3, rasterOperation: 0x00000042); // BLACKNESS
  _bitBlt(out, 8, 5, 2, 3, rasterOperation: 0x00ff0062); // WHITENESS
  _record(out, 14, Uint8List(0));
  return Uint8List.fromList(out.toBytes());
}

VsdxPage _page(String part) => VsdxPage(
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
  test('source-less EMR_BITBLT PATCOPY paints the selected brush', () {
    final drawing = parseEmfDrawing(_patCopyEmf());
    final paths = drawing!.ops.whereType<MetafilePathOp>().toList();
    expect(paths, hasLength(4));
    expect(paths[0].fillArgb, 0xff0000ff);
    expect(paths[0].stroke, isFalse);
    expect(
      paths[0].points.map((point) => (point.x, point.y)),
      <(double, double)>[(10, 20), (40, 20), (40, 35), (10, 35)],
    );
    expect(paths[1].fillArgb, 0xffff0000);
    expect(paths[2].fillArgb, 0xff000000);
    expect(paths[3].fillArgb, 0xffffffff);
  });

  test('short BITBLT is skipped and later PATCOPY records survive', () {
    final paths = parseEmfDrawing(_patCopyEmf(malformedFirst: true))!
        .ops
        .whereType<MetafilePathOp>();
    expect(paths, hasLength(4));
  });

  test('PATCOPY reaches SVG and survives VSDX writer round-trip', () {
    const part = '/visio/media/patcopy.emf';
    final payload = _patCopyEmf();
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-emf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(
      _page(part),
      images: images,
    );
    expect(svg, contains('fill="#0000ff"'));
    expect(svg, contains('fill="#ff0000"'));
    expect(svg, contains('fill="#000000"'));
    expect(svg, contains('fill="#ffffff"'));

    const parser = DocumentParser();
    const writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var document = parser.parse(blank);
    document = document.copyWith(images: images).replacePage(0, _page(part));
    final reopened = parser.parse(writer.write(
      originalBytes: blank,
      edited: document,
    ));
    final image = reopened.images.findByPart(part)!;
    expect(image.bytes, payload);
    expect(
      parseEmfDrawing(image.bytes)!.ops.whereType<MetafilePathOp>(),
      hasLength(4),
    );
  });
}
