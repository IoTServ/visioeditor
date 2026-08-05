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

void _pixel(BytesBuilder out, int x, int y, int colorRef) {
  final payload = ByteData(12)
    ..setInt32(0, x, Endian.little)
    ..setInt32(4, y, Endian.little)
    ..setUint32(8, colorRef, Endian.little);
  _record(out, 15, payload.buffer.asUint8List());
}

Uint8List _pixelEmf({bool malformedFirst = false}) {
  final out = BytesBuilder();
  final header = ByteData(88)
    ..setUint32(0, 1, Endian.little)
    ..setUint32(4, 88, Endian.little)
    ..setInt32(16, 10, Endian.little)
    ..setInt32(20, 10, Endian.little)
    ..setUint32(40, 0x464d4520, Endian.little);
  out.add(header.buffer.asUint8List());
  if (malformedFirst) {
    _record(out, 15, Uint8List(8));
  }
  _pixel(out, 2, 3, 0x000000ff); // COLORREF red
  _pixel(out, 6, 7, 0x00ff0000); // COLORREF blue
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
  test('EMR_SETPIXELV retains coordinates, COLORREF, and SVG paint order', () {
    final drawing = parseEmfDrawing(_pixelEmf());
    final pixels = drawing!.ops.whereType<MetafilePixelOp>().toList();
    expect(pixels, hasLength(2));
    expect((pixels[0].x, pixels[0].y, pixels[0].argb), (2, 3, 0xffff0000));
    expect((pixels[1].x, pixels[1].y, pixels[1].argb), (6, 7, 0xff0000ff));

    const part = '/visio/media/pixels.emf';
    final svg = VsdxToSvgSerializer().serializePage(
      _page(part),
      images: ImageRegistry.empty.withImage(VsdxImage(
        partName: part,
        bytes: _pixelEmf(),
        mimeType: 'image/x-emf',
      )),
    );
    final red = svg.indexOf(
      '<rect x="2" y="3" width="1" height="1" fill="#ff0000"',
    );
    final blue = svg.indexOf(
      '<rect x="6" y="7" width="1" height="1" fill="#0000ff"',
    );
    expect(red, greaterThanOrEqualTo(0));
    expect(blue, greaterThan(red));
    expect(svg, contains('shape-rendering="crispEdges"'));
  });

  test('short EMR_SETPIXELV is skipped and later pixels survive', () {
    final drawing = parseEmfDrawing(_pixelEmf(malformedFirst: true));
    final pixels = drawing!.ops.whereType<MetafilePixelOp>().toList();
    expect(pixels, hasLength(2));
    expect(pixels.last.argb, 0xff0000ff);
  });

  test('pixel EMF bytes survive VSDX write and reopen', () {
    const part = '/visio/media/pixels-roundtrip.emf';
    final payload = _pixelEmf();
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    const parser = DocumentParser();
    var document = parser.parse(blank);
    final page = document.pages.first;
    document = document
        .copyWith(
          images: document.images.withImage(VsdxImage(
            partName: part,
            bytes: payload,
            mimeType: 'image/x-emf',
          )),
        )
        .replacePage(
          0,
          page.addShape(VsdxShapeFactory.picture(
            id: page.nextFreeShapeId(),
            pinX: 1,
            pinY: 1,
            width: 1,
            height: 1,
            imagePartName: part,
          ).copyWith(foreignType: 'EnhMetaFile')),
        );

    final reopened = parser.parse(writer.write(
      originalBytes: blank,
      edited: document,
    ));
    final image = reopened.images.findByPart(part)!;
    expect(image.bytes, payload);
    expect(
      parseEmfDrawing(image.bytes)!.ops.whereType<MetafilePixelOp>(),
      hasLength(2),
    );
  });
}
