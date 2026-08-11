import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _record(int function, List<int> words) {
  final out = Uint8List(6 + words.length * 2);
  final data = ByteData.sublistView(out)
    ..setUint32(0, out.length ~/ 2, Endian.little)
    ..setUint16(4, function, Endian.little);
  for (var index = 0; index < words.length; index++) {
    data.setUint16(6 + index * 2, words[index] & 0xffff, Endian.little);
  }
  return out;
}

Uint8List _brushRecord(int colorRef) {
  final out = Uint8List(14);
  ByteData.sublistView(out)
    ..setUint32(0, 7, Endian.little)
    ..setUint16(4, 0x02fc, Endian.little)
    ..setUint16(6, 0, Endian.little)
    ..setUint32(8, colorRef, Endian.little)
    ..setUint16(12, 0, Endian.little);
  return out;
}

Uint8List _regionRecord({bool corruptCount2 = false}) {
  // Three rectangles represented by two scan bands:
  //   0..20: [0,60], 20..60: [0,20] U [40,60].
  final out = Uint8List(56);
  ByteData.sublistView(out)
    ..setUint32(0, out.length ~/ 2, Endian.little)
    ..setUint16(4, 0x06ff, Endian.little)
    ..setUint16(6, 0, Endian.little) // nextInChain
    ..setUint16(8, 6, Endian.little) // region object
    ..setUint32(10, 0, Endian.little) // ignored object count
    ..setUint16(14, 50, Endian.little) // region bytes
    ..setUint16(16, 2, Endian.little) // ScanCount
    ..setUint16(18, 4, Endian.little) // maxScan
    ..setInt16(20, 0, Endian.little) // bounds left
    ..setInt16(22, 0, Endian.little) // bounds top
    ..setInt16(24, 60, Endian.little) // bounds right
    ..setInt16(26, 60, Endian.little) // bounds bottom
    ..setUint16(28, 2, Endian.little)
    ..setUint16(30, 0, Endian.little)
    ..setUint16(32, 20, Endian.little)
    ..setUint16(34, 0, Endian.little)
    ..setUint16(36, 60, Endian.little)
    ..setUint16(38, 2, Endian.little)
    ..setUint16(40, 4, Endian.little)
    ..setUint16(42, 20, Endian.little)
    ..setUint16(44, 60, Endian.little)
    ..setUint16(46, 0, Endian.little)
    ..setUint16(48, 20, Endian.little)
    ..setUint16(50, 40, Endian.little)
    ..setUint16(52, 60, Endian.little)
    ..setUint16(54, corruptCount2 ? 2 : 4, Endian.little);
  return out;
}

Uint8List _wmf(List<Uint8List> records) {
  final eof = _record(0, const <int>[]);
  final totalBytes = 18 +
      records.fold<int>(0, (sum, record) => sum + record.length) +
      eof.length;
  final out = Uint8List(totalBytes);
  final data = ByteData.sublistView(out)
    ..setUint16(0, 1, Endian.little)
    ..setUint16(2, 9, Endian.little)
    ..setUint16(4, 0x0300, Endian.little)
    ..setUint32(6, totalBytes ~/ 2, Endian.little)
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
  test('WMF scan regions fill frame invert clip and round-trip', () {
    final payload = _wmf(<Uint8List>[
      _regionRecord(), // object 0
      _brushRecord(0x000000ff), // object 1, red COLORREF
      _brushRecord(0x0000ff00), // object 2, green COLORREF
      _record(0x012d, const <int>[2]),
      _record(0x0228, const <int>[0, 1]), // FILLREGION
      _record(0x012b, const <int>[0]), // PAINTREGION
      _record(0x012a, const <int>[0]), // INVERTREGION
      _record(0x0429, const <int>[0, 1, 5, 5]), // FRAMEREGION
      _record(0x012c, const <int>[0]), // SELECTCLIPREGION
      _record(0x041b, const <int>[80, 80, 0, 0]),
    ]);

    final drawing = parseWmfDrawing(payload)!;
    final paths = drawing.ops.whereType<MetafilePathOp>().toList();
    expect(paths, hasLength(5));
    expect(paths.first.fillArgb, 0xffff0000);
    expect(paths.first.additionalContours, hasLength(2));
    expect(paths[1].fillArgb, 0xff00ff00);
    expect(paths[2].rasterOperation, MetafileRasterOperation.invert);
    expect(paths[3].additionalContours, isNotEmpty);
    final clip = drawing.ops.whereType<MetafileClipPathOp>().single;
    expect(clip.additionalContours, hasLength(2));
    expect(clip.evenOddFill, isFalse);

    const part = '/visio/media/regions.wmf';
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-wmf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(
      _imagePage(part),
      images: images,
    );
    expect(svg, contains('mix-blend-mode:difference'));
    expect(svg, contains('<clipPath'));
    expect(svg, contains('clip-rule="nonzero"'));

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
    expect(parseWmfDrawing(roundTripped)!.ops.whereType<MetafilePathOp>(),
        hasLength(5));
  });

  test('malformed WMF region reserves its object slot and is ignored', () {
    final drawing = parseWmfDrawing(_wmf(<Uint8List>[
      _regionRecord(corruptCount2: true), // invalid object 0
      _brushRecord(0x0000ff00), // valid object 1
      _record(0x012d, const <int>[1]),
      _record(0x041b, const <int>[20, 20, 0, 0]),
    ]))!;
    final path = drawing.ops.whereType<MetafilePathOp>().single;
    expect(path.fillArgb, 0xff00ff00);
  });
}
