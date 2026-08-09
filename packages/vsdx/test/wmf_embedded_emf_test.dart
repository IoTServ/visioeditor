import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _blueRectangleEmf() {
  final bytes = Uint8List(156);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 1, Endian.little);
  data.setUint32(4, 88, Endian.little);
  data.setInt32(16, 100, Endian.little);
  data.setInt32(20, 100, Endian.little);
  data.setUint32(40, 0x464d4520, Endian.little);

  data.setUint32(88, 39, Endian.little); // EMR_CREATEBRUSHINDIRECT
  data.setUint32(92, 24, Endian.little);
  data.setUint32(96, 1, Endian.little);
  data.setUint32(100, 0, Endian.little); // BS_SOLID
  data.setUint32(104, 0x00ff0000, Endian.little); // COLORREF blue
  data.setUint32(112, 37, Endian.little); // EMR_SELECTOBJECT
  data.setUint32(116, 12, Endian.little);
  data.setUint32(120, 1, Endian.little);
  data.setUint32(124, 43, Endian.little); // EMR_RECTANGLE
  data.setUint32(128, 24, Endian.little);
  data.setInt32(132, 10, Endian.little);
  data.setInt32(136, 10, Endian.little);
  data.setInt32(140, 90, Endian.little);
  data.setInt32(144, 90, Endian.little);
  data.setUint32(148, 14, Endian.little);
  data.setUint32(152, 8, Endian.little);
  return bytes;
}

Uint8List _escapeRecord(Uint8List payload) {
  final dataLength = payload.length;
  final sizeWords = ((dataLength + 1) >> 1) + 5;
  final record = Uint8List(sizeWords * 2);
  ByteData.sublistView(record)
    ..setUint32(0, sizeWords, Endian.little)
    ..setUint16(4, 0x0626, Endian.little)
    ..setUint16(6, 15, Endian.little)
    ..setUint16(8, dataLength, Endian.little);
  record.setRange(10, 10 + dataLength, payload);
  return record;
}

Uint8List _wmfcRecord(
  Uint8List chunk, {
  required int chunkCount,
  required int remainingSize,
  required int totalSize,
}) {
  final comment = Uint8List(34 + chunk.length);
  ByteData.sublistView(comment)
    ..setUint32(0, 0x43464d57, Endian.little) // WMFC
    ..setUint32(4, 1, Endian.little)
    ..setUint32(8, 0x00010000, Endian.little)
    ..setUint16(12, 0, Endian.little)
    ..setUint32(14, 0, Endian.little)
    ..setUint32(18, chunkCount, Endian.little)
    ..setUint32(22, chunk.length, Endian.little)
    ..setUint32(26, remainingSize, Endian.little)
    ..setUint32(30, totalSize, Endian.little);
  comment.setRange(34, comment.length, chunk);
  return _escapeRecord(comment);
}

Uint8List _wmfWithRecords(List<Uint8List> records) {
  final size =
      18 + records.fold<int>(0, (sum, record) => sum + record.length) + 6;
  final out = Uint8List(size);
  final data = ByteData.sublistView(out)
    ..setUint16(0, 1, Endian.little)
    ..setUint16(2, 9, Endian.little)
    ..setUint16(4, 0x0300, Endian.little)
    ..setUint32(6, size ~/ 2, Endian.little);
  var offset = 18;
  for (final record in records) {
    out.setRange(offset, offset + record.length, record);
    offset += record.length;
  }
  data.setUint32(offset, 3, Endian.little);
  data.setUint16(offset + 4, 0, Endian.little);
  return out;
}

Uint8List _embeddedEmfWmf({bool inconsistentTotal = false}) {
  final emf = _blueRectangleEmf();
  // Put a complete drawable record in the malformed first chunk to prove the
  // facade never mistakes a rejected WMFC fragment for a standalone EMF.
  final split = inconsistentTotal ? 148 : 70;
  return _wmfWithRecords(<Uint8List>[
    _wmfcRecord(
      Uint8List.sublistView(emf, 0, split),
      chunkCount: 2,
      remainingSize: emf.length - split,
      totalSize: emf.length,
    ),
    _wmfcRecord(
      Uint8List.sublistView(emf, split),
      chunkCount: 2,
      remainingSize: 0,
      totalSize: emf.length + (inconsistentTotal ? 1 : 0),
    ),
  ]);
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
  test('WMFC META_ESCAPE chunks reconstruct their authoritative EMF', () {
    final emf = extractWmfEmbeddedEmf(_embeddedEmfWmf());
    expect(emf, _blueRectangleEmf());
    final drawing = parseEmfDrawing(emf!);
    expect(
        drawing!.ops.whereType<MetafilePathOp>().single.fillArgb, 0xff0000ff);
  });

  test('embedded EMF reaches SVG and survives raw WMF round-trip', () {
    const part = '/visio/media/dual-mode.wmf';
    final payload = _embeddedEmfWmf();
    final drawing = parseMetafileDrawing(
      payload,
      mimeType: 'image/x-wmf',
      partName: part,
    );
    expect(drawing, isNotNull);
    expect(drawing!.ops.whereType<MetafilePathOp>(), hasLength(1));

    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-wmf',
    ));
    final svg =
        VsdxToSvgSerializer().serializePage(_page(part), images: images);
    expect(svg, contains('fill="#0000ff"'));

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
    expect(extractWmfEmbeddedEmf(image.bytes), _blueRectangleEmf());
  });

  test('malformed WMFC and MathType private escapes are skipped safely', () {
    final malformed = _embeddedEmfWmf(inconsistentTotal: true);
    expect(extractWmfEmbeddedEmf(malformed), isNull);
    expect(
      parseMetafileDrawing(malformed, mimeType: 'image/x-wmf'),
      isNull,
      reason: 'a rejected first WMFC chunk is not a standalone EMF',
    );
    final mathType = _wmfWithRecords(<Uint8List>[
      _escapeRecord(Uint8List.fromList(utf8.encode('MathType private data'))),
    ]);
    expect(extractWmfEmbeddedEmf(mathType), isNull);
    expect(parseMetafileDrawing(mathType, mimeType: 'image/x-wmf'), isNull);
  });
}
