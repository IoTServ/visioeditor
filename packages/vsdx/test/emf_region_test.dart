import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void _record(BytesBuilder output, int type, Uint8List payload) {
  final size = (payload.length + 11) & ~3;
  final header = ByteData(8)
    ..setUint32(0, type, Endian.little)
    ..setUint32(4, size, Endian.little);
  output.add(header.buffer.asUint8List());
  output.add(payload);
  for (var i = payload.length + 8; i < size; i++) {
    output.addByte(0);
  }
}

void _brush(BytesBuilder output, int handle, int colorRef,
    {bool select = true}) {
  final create = ByteData(16)
    ..setInt32(0, handle, Endian.little)
    ..setUint32(4, 0, Endian.little) // BS_SOLID
    ..setUint32(8, colorRef, Endian.little);
  _record(output, 39, create.buffer.asUint8List());
  if (select) {
    final selectPayload = ByteData(4)..setUint32(0, handle, Endian.little);
    _record(output, 37, selectPayload.buffer.asUint8List());
  }
}

Uint8List _regionData({int declaredCount = 2}) {
  final output = ByteData(64)
    ..setUint32(0, 32, Endian.little) // RGNDATAHEADER size
    ..setUint32(4, 1, Endian.little) // RDH_RECTANGLES
    ..setUint32(8, declaredCount, Endian.little)
    ..setUint32(12, 32, Endian.little)
    ..setInt32(16, 5, Endian.little)
    ..setInt32(20, 10, Endian.little)
    ..setInt32(24, 90, Endian.little)
    ..setInt32(28, 80, Endian.little)
    ..setInt32(32, 5, Endian.little)
    ..setInt32(36, 10, Endian.little)
    ..setInt32(40, 35, Endian.little)
    ..setInt32(44, 40, Endian.little)
    ..setInt32(48, 35, Endian.little)
    ..setInt32(52, 10, Endian.little)
    ..setInt32(56, 90, Endian.little)
    ..setInt32(60, 40, Endian.little);
  return output.buffer.asUint8List();
}

void _fillRegion(
  BytesBuilder output,
  int brushHandle, {
  int declaredCount = 2,
}) {
  final region = _regionData(declaredCount: declaredCount);
  final payload = ByteData(24 + region.length)
    ..setInt32(0, 5, Endian.little)
    ..setInt32(4, 10, Endian.little)
    ..setInt32(8, 90, Endian.little)
    ..setInt32(12, 80, Endian.little)
    ..setUint32(16, region.length, Endian.little)
    ..setUint32(20, brushHandle, Endian.little);
  payload.buffer.asUint8List().setRange(24, 24 + region.length, region);
  _record(output, 71, payload.buffer.asUint8List()); // EMR_FILLRGN
}

void _paintRegion(BytesBuilder output) {
  final region = _regionData();
  final payload = ByteData(20 + region.length)
    ..setInt32(0, 5, Endian.little)
    ..setInt32(4, 10, Endian.little)
    ..setInt32(8, 90, Endian.little)
    ..setInt32(12, 80, Endian.little)
    ..setUint32(16, region.length, Endian.little);
  payload.buffer.asUint8List().setRange(20, 20 + region.length, region);
  _record(output, 74, payload.buffer.asUint8List()); // EMR_PAINTRGN
}

void _frameRegion(
  BytesBuilder output,
  int brushHandle, {
  int width = 3,
  int height = 5,
}) {
  final region = _regionData();
  final payload = ByteData(32 + region.length)
    ..setInt32(0, 5, Endian.little)
    ..setInt32(4, 10, Endian.little)
    ..setInt32(8, 90, Endian.little)
    ..setInt32(12, 80, Endian.little)
    ..setUint32(16, region.length, Endian.little)
    ..setUint32(20, brushHandle, Endian.little)
    ..setInt32(24, width, Endian.little)
    ..setInt32(28, height, Endian.little);
  payload.buffer.asUint8List().setRange(32, 32 + region.length, region);
  _record(output, 72, payload.buffer.asUint8List()); // EMR_FRAMERGN
}

void _invertRegion(BytesBuilder output) {
  final region = _regionData();
  final payload = ByteData(20 + region.length)
    ..setInt32(0, 5, Endian.little)
    ..setInt32(4, 10, Endian.little)
    ..setInt32(8, 90, Endian.little)
    ..setInt32(12, 80, Endian.little)
    ..setUint32(16, region.length, Endian.little);
  payload.buffer.asUint8List().setRange(20, 20 + region.length, region);
  _record(output, 73, payload.buffer.asUint8List()); // EMR_INVERTRGN
}

Uint8List _regionEmf({bool malformedFirst = false}) {
  final output = BytesBuilder();
  final header = ByteData(88)
    ..setUint32(0, 1, Endian.little)
    ..setUint32(4, 88, Endian.little)
    ..setInt32(16, 100, Endian.little)
    ..setInt32(20, 100, Endian.little)
    ..setUint32(40, 0x464d4520, Endian.little);
  output.add(header.buffer.asUint8List());
  _brush(output, 1, 0x000000ff, select: false); // COLORREF red
  _brush(output, 2, 0x00ff0000); // COLORREF blue, selected
  _fillRegion(output, 1, declaredCount: malformedFirst ? 3 : 2);
  _paintRegion(output);
  _record(output, 14, Uint8List(0));
  return Uint8List.fromList(output.toBytes());
}

Uint8List _regionEffectsEmf() {
  final output = BytesBuilder();
  final header = ByteData(88)
    ..setUint32(0, 1, Endian.little)
    ..setUint32(4, 88, Endian.little)
    ..setInt32(16, 100, Endian.little)
    ..setInt32(20, 100, Endian.little)
    ..setUint32(40, 0x464d4520, Endian.little);
  output.add(header.buffer.asUint8List());
  _brush(output, 1, 0x0000ff00, select: false); // COLORREF green
  _frameRegion(output, 1);
  _invertRegion(output);
  _record(output, 14, Uint8List(0));
  return Uint8List.fromList(output.toBytes());
}

VsdxPage _page(String partName) => VsdxPage(
      id: 0,
      name: 'Regions',
      widthInches: 1,
      heightInches: 1,
      shapes: <VsdxShape>[
        VsdxShapeFactory.picture(
          id: 1,
          pinX: 0.5,
          pinY: 0.5,
          width: 1,
          height: 1,
          imagePartName: partName,
        ),
      ],
    );

void main() {
  test('EMR_FILLRGN and EMR_PAINTRGN retain rectangle unions and brushes', () {
    final drawing = parseEmfDrawing(_regionEmf())!;
    final regions = drawing.ops.whereType<MetafilePathOp>().toList();
    expect(regions, hasLength(2));
    expect(regions.first.fillArgb, 0xffff0000);
    expect(regions.last.fillArgb, 0xff0000ff);
    for (final region in regions) {
      expect(region.fill, isTrue);
      expect(region.stroke, isFalse);
      expect(region.points, hasLength(4));
      expect(region.additionalContours, hasLength(1));
      expect(region.evenOddFill, isFalse);
    }
  });

  test('malformed RGNDATA is skipped without losing later region records', () {
    final drawing = parseEmfDrawing(_regionEmf(malformedFirst: true))!;
    final region = drawing.ops.whereType<MetafilePathOp>().single;
    expect(region.fillArgb, 0xff0000ff);
    expect(region.additionalContours, hasLength(1));
  });

  test('EMR_FRAMERGN and EMR_INVERTRGN retain region effects', () {
    final drawing = parseEmfDrawing(_regionEffectsEmf())!;
    final effects = drawing.ops.whereType<MetafilePathOp>().toList();
    expect(effects, hasLength(2));

    final frame = effects.first;
    expect(frame.fillArgb, 0xff00ff00);
    // The two source rectangles share an edge; only the six exterior bands
    // remain, with no false frame on their internal boundary.
    expect(frame.additionalContours, hasLength(5));
    expect(frame.rasterOperation, MetafileRasterOperation.overpaint);
    expect((frame.points.first.x, frame.points.first.y), (5, 10));
    expect((frame.points[2].x, frame.points[2].y), (35, 15));

    final inverted = effects.last;
    expect(inverted.additionalContours, hasLength(1));
    expect(inverted.rasterOperation, MetafileRasterOperation.invert);
  });

  test('EMF regions reach SVG and survive VSDX writer round-trip', () {
    const partName = '/visio/media/regions.emf';
    final payload = _regionEmf();
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: partName,
      bytes: payload,
      mimeType: 'image/x-emf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(
      _page(partName),
      images: images,
    );
    expect(svg, contains('fill="#ff0000"'));
    expect(svg, contains('fill="#0000ff"'));

    const parser = DocumentParser();
    const writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var document = parser.parse(blank);
    document =
        document.copyWith(images: images).replacePage(0, _page(partName));
    final reopened = parser.parse(writer.write(
      originalBytes: blank,
      edited: document,
    ));
    final roundTripped = reopened.images.findByPart(partName)!.bytes;
    expect(roundTripped, payload);
    expect(
      parseEmfDrawing(roundTripped)!.ops.whereType<MetafilePathOp>(),
      hasLength(2),
    );
  });

  test('EMF region effects reach SVG and survive VSDX writer round-trip', () {
    const partName = '/visio/media/region-effects.emf';
    final payload = _regionEffectsEmf();
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: partName,
      bytes: payload,
      mimeType: 'image/x-emf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(
      _page(partName),
      images: images,
    );
    expect(svg, contains('fill="#00ff00"'));
    expect(svg, contains('mix-blend-mode:difference'));

    const parser = DocumentParser();
    const writer = VsdxWriter();
    final blank = writer.emptyDocument();
    final edited = parser
        .parse(blank)
        .copyWith(images: images)
        .replacePage(0, _page(partName));
    final reopened = parser.parse(writer.write(
      originalBytes: blank,
      edited: edited,
    ));
    expect(reopened.images.findByPart(partName)!.bytes, payload);
  });
}
