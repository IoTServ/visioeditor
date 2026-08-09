import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _wordRecord(int function, List<int> words) {
  final out = Uint8List(6 + words.length * 2);
  final data = ByteData.sublistView(out)
    ..setUint32(0, out.length ~/ 2, Endian.little)
    ..setUint16(4, function, Endian.little);
  for (var i = 0; i < words.length; i++) {
    data.setUint16(6 + i * 2, words[i] & 0xffff, Endian.little);
  }
  return out;
}

Uint8List _brushRecord(int colorRef) {
  final out = Uint8List(14);
  ByteData.sublistView(out)
    ..setUint32(0, 7, Endian.little)
    ..setUint16(4, 0x02fc, Endian.little)
    ..setUint16(6, 0, Endian.little) // BS_SOLID
    ..setUint32(8, colorRef, Endian.little)
    ..setUint16(12, 0, Endian.little);
  return out;
}

Uint8List _polyPolygonRecord() {
  const polygons = <List<(int, int)>>[
    <(int, int)>[(0, 0), (100, 0), (100, 100), (0, 100)],
    <(int, int)>[(25, 25), (75, 25), (75, 75), (25, 75)],
  ];
  final paramsLength = 2 +
      polygons.length * 2 +
      polygons.fold<int>(0, (sum, points) => sum + points.length * 4);
  final out = Uint8List(6 + paramsLength);
  final data = ByteData.sublistView(out)
    ..setUint32(0, out.length ~/ 2, Endian.little)
    ..setUint16(4, 0x0538, Endian.little)
    ..setUint16(6, polygons.length, Endian.little);
  var offset = 8;
  for (final points in polygons) {
    data.setUint16(offset, points.length, Endian.little);
    offset += 2;
  }
  for (final points in polygons) {
    for (final (x, y) in points) {
      data.setInt16(offset, x, Endian.little);
      data.setInt16(offset + 2, y, Endian.little);
      offset += 4;
    }
  }
  return out;
}

Uint8List _textOutRecord(String text, int x, int y) {
  final bytes = Uint8List.fromList(text.codeUnits);
  final padded = bytes.length + (bytes.length.isOdd ? 1 : 0);
  final out = Uint8List(6 + 2 + padded + 4);
  final data = ByteData.sublistView(out)
    ..setUint32(0, out.length ~/ 2, Endian.little)
    ..setUint16(4, 0x0521, Endian.little)
    ..setUint16(6, bytes.length, Endian.little);
  out.setRange(8, 8 + bytes.length, bytes);
  data.setInt16(8 + padded, y, Endian.little);
  data.setInt16(10 + padded, x, Endian.little);
  return out;
}

Uint8List _wmf(List<Uint8List> records) {
  final eof = _wordRecord(0, const <int>[]);
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
  test('POLYPOLYGON remains one even-odd compound path through round-trip', () {
    final payload = _wmf(<Uint8List>[
      _brushRecord(0x000000ff), // COLORREF red
      _wordRecord(0x012d, const <int>[0]),
      _wordRecord(0x0106, const <int>[1]), // ALTERNATE
      _polyPolygonRecord(),
    ]);
    final drawing = parseWmfDrawing(payload)!;
    final path = drawing.ops.whereType<MetafilePathOp>().single;
    expect(path.fillArgb, 0xffff0000);
    expect(path.evenOddFill, isTrue);
    expect(path.additionalContours, hasLength(1));
    final winding = parseWmfDrawing(_wmf(<Uint8List>[
      _brushRecord(0x000000ff),
      _wordRecord(0x012d, const <int>[0]),
      _wordRecord(0x0106, const <int>[2]), // WINDING
      _polyPolygonRecord(),
    ]))!
        .ops
        .whereType<MetafilePathOp>()
        .single;
    expect(winding.evenOddFill, isFalse);

    const part = '/visio/media/compound.wmf';
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-wmf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(
      _imagePage(part),
      images: images,
    );
    expect(svg, contains('fill-rule="evenodd"'));
    expect(RegExp(r'<path d="M [^"]+ M ').hasMatch(svg), isTrue);

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
      parseWmfDrawing(roundTripped)!
          .ops
          .whereType<MetafilePathOp>()
          .single
          .additionalContours,
      hasLength(1),
    );
  });

  test('WMF SaveDC clips and positive RestoreDC unwind the full stack', () {
    final payload = _wmf(<Uint8List>[
      _wordRecord(0x001e, const <int>[]),
      _wordRecord(0x0416, const <int>[80, 80, 20, 20]),
      _wordRecord(0x001e, const <int>[]),
      _wordRecord(0x0415, const <int>[60, 60, 40, 40]),
      _wordRecord(0x041b, const <int>[100, 100, 0, 0]),
      _wordRecord(0x0127, const <int>[1]),
      _wordRecord(0x0214, const <int>[0, 0]),
      _wordRecord(0x0213, const <int>[100, 100]),
    ]);
    final drawing = parseWmfDrawing(payload)!;
    expect(drawing.ops.whereType<MetafileSaveDcOp>(), hasLength(2));
    expect(drawing.ops.whereType<MetafileClipRectOp>(), hasLength(2));
    expect(
      drawing.ops.whereType<MetafileRestoreDcOp>().single.count,
      2,
    );
    final clips = drawing.ops.whereType<MetafileClipRectOp>().toList();
    expect(clips.first.mode, MetafileClipCombineMode.intersect);
    expect(clips.last.mode, MetafileClipCombineMode.exclude);

    const part = '/visio/media/clipped.wmf';
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-wmf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(
      _imagePage(part),
      images: images,
    );
    expect(RegExp('id="wmf-dc-clip-').allMatches(svg), hasLength(2));
  });

  test('SETTEXTJUSTIFICATION distributes signed width over spaces', () {
    for (final extra in <int>[6, -2]) {
      final payload = _wmf(<Uint8List>[
        _wordRecord(0x0103, const <int>[8]), // MM_ANISOTROPIC
        _wordRecord(0x020a, <int>[2, extra]),
        _textOutRecord('A B C', 10, 20),
      ]);
      final text =
          parseWmfDrawing(payload)!.ops.whereType<MetafileTextOp>().single;
      final perBreak = extra / 2;
      expect(text.advancesX, hasLength(5));
      expect(
        text.advancesX![1] - text.advancesX![0],
        closeTo(perBreak, 1e-9),
      );
      expect(
        text.advancesX![3] - text.advancesX![2],
        closeTo(perBreak, 1e-9),
      );
    }
  });
}
