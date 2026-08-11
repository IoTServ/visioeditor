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
  final create = ByteData(16)
    ..setInt32(0, handle, Endian.little)
    ..setUint32(4, 0, Endian.little)
    ..setUint32(8, colorRef, Endian.little);
  _record(out, 39, create.buffer.asUint8List());
  final select = ByteData(4)..setUint32(0, handle, Endian.little);
  _record(out, 37, select.buffer.asUint8List());
}

void _rectRecord(
  BytesBuilder out,
  int type,
  int left,
  int top,
  int right,
  int bottom,
) {
  final rect = ByteData(16)
    ..setInt32(0, left, Endian.little)
    ..setInt32(4, top, Endian.little)
    ..setInt32(8, right, Endian.little)
    ..setInt32(12, bottom, Endian.little);
  _record(out, type, rect.buffer.asUint8List());
}

Uint8List _clippedEmf() {
  final out = BytesBuilder();
  final header = ByteData(88)
    ..setUint32(0, 1, Endian.little)
    ..setUint32(4, 88, Endian.little)
    ..setInt32(16, 100, Endian.little)
    ..setInt32(20, 100, Endian.little)
    ..setUint32(40, 0x464d4520, Endian.little);
  out.add(header.buffer.asUint8List());

  _brush(out, 1, 0x00ff0000); // COLORREF blue
  _rectRecord(out, 43, 0, 0, 100, 100);
  _record(out, 33, Uint8List(0)); // EMR_SAVEDC
  _rectRecord(out, 30, 25, 25, 75, 75); // EMR_INTERSECTCLIPRECT
  final offsetClip = ByteData(8)
    ..setInt32(0, 5, Endian.little)
    ..setInt32(4, -3, Endian.little);
  _record(out, 26, offsetClip.buffer.asUint8List()); // EMR_OFFSETCLIPRGN
  _brush(out, 2, 0x000000ff); // COLORREF red
  _rectRecord(out, 43, 0, 0, 100, 100);
  final restore = ByteData(4)..setInt32(0, -1, Endian.little);
  _record(out, 34, restore.buffer.asUint8List()); // EMR_RESTOREDC
  _rectRecord(out, 29, 40, 40, 60, 60); // EMR_EXCLUDECLIPRECT
  _brush(out, 3, 0x0000ff00); // COLORREF green
  _rectRecord(out, 43, 0, 0, 100, 100);
  _record(out, 14, Uint8List(0));
  return Uint8List.fromList(out.toBytes());
}

Uint8List _rop2Emf() {
  final out = BytesBuilder();
  final header = ByteData(88)
    ..setUint32(0, 1, Endian.little)
    ..setUint32(4, 88, Endian.little)
    ..setInt32(16, 100, Endian.little)
    ..setInt32(20, 100, Endian.little)
    ..setUint32(40, 0x464d4520, Endian.little);
  out.add(header.buffer.asUint8List());
  _brush(out, 1, 0x000000ff);
  _rectRecord(out, 43, 0, 0, 20, 20);
  final invert = ByteData(4)..setUint32(0, 6, Endian.little);
  _record(out, 20, invert.buffer.asUint8List()); // R2_NOT
  _rectRecord(out, 43, 25, 0, 45, 20);
  final nop = ByteData(4)..setUint32(0, 11, Endian.little);
  _record(out, 20, nop.buffer.asUint8List()); // R2_NOP
  _rectRecord(out, 43, 0, 25, 20, 45);
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
  test('EMF retains intersect/exclude clip state across SaveDC/RestoreDC', () {
    final drawing = parseEmfDrawing(_clippedEmf())!;
    expect(drawing.ops.whereType<MetafilePathOp>(), hasLength(3));
    expect(drawing.ops.whereType<MetafileSaveDcOp>(), hasLength(1));
    expect(drawing.ops.whereType<MetafileRestoreDcOp>().single.count, 1);
    final offset = drawing.ops.whereType<MetafileOffsetClipOp>().single;
    expect(offset.dx, 5);
    expect(offset.dy, -3);
    expect(
      drawing.ops.whereType<MetafileClipRectOp>().map((op) => op.mode),
      <MetafileClipCombineMode>[
        MetafileClipCombineMode.intersect,
        MetafileClipCombineMode.exclude,
      ],
    );
  });

  test('clip regions reach SVG and survive VSDX writer round-trip', () {
    const part = '/visio/media/clipped.emf';
    final payload = _clippedEmf();
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-emf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(
      _page(part),
      images: images,
    );
    expect(RegExp('<clipPath id="wmf-dc-clip-').allMatches(svg), hasLength(2));
    expect(svg, contains('id="wmf-dc-offset-clip-'));
    expect(svg, contains('M 30 22 L 80 22 L 80 72 L 30 72 Z'));
    expect(svg, contains('clip-rule="evenodd"'));

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
      parseEmfDrawing(image.bytes)!.ops.whereType<MetafileClipRectOp>(),
      hasLength(2),
    );
    expect(
      parseEmfDrawing(image.bytes)!.ops.whereType<MetafileOffsetClipOp>(),
      hasLength(1),
    );
  });

  test('EMR_SETROP2 follows LibreOffice invert/xor/nop state mapping', () {
    final payload = _rop2Emf();
    final drawing = parseEmfDrawing(payload)!;
    final paths = drawing.ops.whereType<MetafilePathOp>().toList();
    expect(paths, hasLength(3));
    expect(paths[0].rasterOperation, MetafileRasterOperation.overpaint);
    expect(paths[1].rasterOperation, MetafileRasterOperation.invert);
    expect(paths[2].rasterOperation, MetafileRasterOperation.nop);
    final svg = VsdxToSvgSerializer().serializePage(
      _page('/visio/media/rop2.emf'),
      images: ImageRegistry.empty.withImage(VsdxImage(
        partName: '/visio/media/rop2.emf',
        bytes: payload,
        mimeType: 'image/x-emf',
      )),
    );
    expect(svg, contains('mix-blend-mode:difference'));

    const parser = DocumentParser();
    const writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var document = parser.parse(blank);
    document = document
        .copyWith(
          images: ImageRegistry.empty.withImage(VsdxImage(
            partName: '/visio/media/rop2.emf',
            bytes: payload,
            mimeType: 'image/x-emf',
          )),
        )
        .replacePage(0, _page('/visio/media/rop2.emf'));
    final reopened = parser.parse(writer.write(
      originalBytes: blank,
      edited: document,
    ));
    expect(
      reopened.images.findByPart('/visio/media/rop2.emf')!.bytes,
      payload,
    );
  });
}
