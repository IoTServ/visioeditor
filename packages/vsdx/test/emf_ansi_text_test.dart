import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

int _aligned4(int value) => (value + 3) & ~3;

void _addRecord(BytesBuilder out, int type, Uint8List payload) {
  final size = _aligned4(payload.length + 8);
  final header = ByteData(8)
    ..setUint32(0, type, Endian.little)
    ..setUint32(4, size, Endian.little);
  out.add(header.buffer.asUint8List());
  out.add(payload);
  for (var i = payload.length + 8; i < size; i++) {
    out.addByte(0);
  }
}

BytesBuilder _emfWithFont(int charset) {
  final out = BytesBuilder();
  final header = ByteData(88)
    ..setUint32(0, 1, Endian.little)
    ..setUint32(4, 88, Endian.little)
    ..setInt32(16, 160, Endian.little)
    ..setInt32(20, 100, Endian.little)
    ..setUint32(40, 0x464D4520, Endian.little);
  out.add(header.buffer.asUint8List());

  final font = ByteData(96)..setUint32(0, 1, Endian.little);
  const logFont = 4;
  font
    ..setInt32(logFont, 18, Endian.little)
    ..setInt32(logFont + 16, 400, Endian.little)
    ..setUint8(logFont + 23, charset);
  for (var i = 0; i < 'Arial'.length; i++) {
    font.setUint16(
      logFont + 28 + i * 2,
      'Arial'.codeUnitAt(i),
      Endian.little,
    );
  }
  _addRecord(out, 82, font.buffer.asUint8List()); // EXTCREATEFONTINDIRECTW

  final select = ByteData(4)..setUint32(0, 1, Endian.little);
  _addRecord(out, 37, select.buffer.asUint8List()); // SELECTOBJECT
  return out;
}

Uint8List _extTextEmf({
  required bool ansi,
  required int charset,
  required List<int> sourceBytes,
  required int sourceLength,
  required List<int> advancesX,
  List<int>? advancesY,
}) {
  final out = _emfWithFont(charset);
  final valuesPerUnit = advancesY == null ? 1 : 2;
  final stringOffset = 76;
  final dxOffset = _aligned4(stringOffset + sourceBytes.length);
  final recordSize = dxOffset + sourceLength * valuesPerUnit * 4;
  final payload = ByteData(recordSize - 8);
  const text = 28;
  payload
    ..setInt32(text, 10, Endian.little)
    ..setInt32(text + 4, 30, Endian.little)
    ..setUint32(text + 8, sourceLength, Endian.little)
    ..setUint32(text + 12, stringOffset, Endian.little)
    ..setUint32(text + 16, advancesY == null ? 0 : 0x2000, Endian.little)
    ..setUint32(text + 36, dxOffset, Endian.little);
  payload.buffer.asUint8List().setRange(
        stringOffset - 8,
        stringOffset - 8 + sourceBytes.length,
        sourceBytes,
      );
  var p = dxOffset - 8;
  for (var i = 0; i < sourceLength; i++) {
    payload.setInt32(p, advancesX[i], Endian.little);
    p += 4;
    if (advancesY != null) {
      payload.setInt32(p, advancesY[i], Endian.little);
      p += 4;
    }
  }
  _addRecord(
    out,
    ansi ? 83 : 84,
    payload.buffer.asUint8List(),
  );
  _addRecord(out, 14, Uint8List(0));
  return Uint8List.fromList(out.toBytes());
}

Uint8List _polyTextEmf({required bool ansi}) {
  final out = _emfWithFont(0);
  final first = ansi ? <int>[0x41] : <int>[0x41, 0x00];
  final second = ansi ? <int>[0x42] : <int>[0x42, 0x00];
  const stringsOffset = 120;
  final secondOffset = stringsOffset + first.length;
  final recordSize = _aligned4(secondOffset + second.length);
  final payload = ByteData(recordSize - 8)..setUint32(28, 2, Endian.little);

  void entry(int at, int x, int stringOffset) {
    payload
      ..setInt32(at, x, Endian.little)
      ..setInt32(at + 4, 20, Endian.little)
      ..setUint32(at + 8, 1, Endian.little)
      ..setUint32(at + 12, stringOffset, Endian.little);
  }

  entry(32, 10, stringsOffset);
  entry(72, 30, secondOffset);
  payload.buffer.asUint8List()
    ..setRange(stringsOffset - 8, stringsOffset - 8 + first.length, first)
    ..setRange(secondOffset - 8, secondOffset - 8 + second.length, second);
  _addRecord(out, ansi ? 96 : 97, payload.buffer.asUint8List());
  _addRecord(out, 14, Uint8List(0));
  return Uint8List.fromList(out.toBytes());
}

VsdxPage _picturePage(String part) => VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 2,
      heightInches: 2,
      shapes: <VsdxShape>[
        VsdxShapeFactory.picture(
          id: 1,
          pinX: 1,
          pinY: 1,
          width: 1,
          height: 1,
          imagePartName: part,
        ),
      ],
    );

void main() {
  test('EMR_EXTTEXTOUTA decodes LOGFONT charset and reaches SVG', () {
    final bytes = _extTextEmf(
      ansi: true,
      charset: 0xcc, // RUSSIAN_CHARSET / Windows-1251
      sourceBytes: const <int>[0xcf, 0xf0, 0xe8, 0xe2, 0xe5, 0xf2],
      sourceLength: 6,
      advancesX: const <int>[4, 5, 6, 7, 8, 9],
    );
    final drawing = parseEmfDrawing(bytes);
    final text = drawing!.ops.whereType<MetafileTextOp>().single;
    expect(text.text, 'Привет');
    expect(text.face, 'Arial');
    expect(text.advancesX, <double>[4, 5, 6, 7, 8, 9]);

    const part = '/visio/media/ansi.emf';
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: bytes,
      mimeType: 'image/x-emf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(
      _picturePage(part),
      images: images,
    );
    expect(svg, contains('font-family="Arial"'));
    expect(svg, contains('>П</tspan>'));
    expect(svg, contains('>т</tspan>'));
  });

  test('EMR_EXTTEXTOUTA combines Shift-JIS ETO_PDY per Unicode glyph', () {
    final drawing = parseEmfDrawing(_extTextEmf(
      ansi: true,
      charset: 0x80, // SHIFTJIS_CHARSET
      sourceBytes: const <int>[0x93, 0xfa, 0x96, 0x7b], // 日本
      sourceLength: 4,
      advancesX: const <int>[3, 4, 5, 6],
      advancesY: const <int>[1, 2, 3, 4],
    ));
    final text = drawing!.ops.whereType<MetafileTextOp>().single;
    expect(text.text, '日本');
    expect(text.advancesX, <double>[7, 11]);
    expect(text.advancesY, <double>[3, 7]);
  });

  test('EMR_EXTTEXTOUTW combines UTF-16 surrogate advances', () {
    final drawing = parseEmfDrawing(_extTextEmf(
      ansi: false,
      charset: 0,
      sourceBytes: const <int>[0x3d, 0xd8, 0x00, 0xde], // U+1F600
      sourceLength: 2,
      advancesX: const <int>[5, 7],
    ));
    final text = drawing!.ops.whereType<MetafileTextOp>().single;
    expect(text.text, '😀');
    expect(text.advancesX, <double>[12]);
  });

  test('EMR_POLYTEXTOUTA/W emit every EMRTEXT entry', () {
    for (final ansi in <bool>[true, false]) {
      final drawing = parseEmfDrawing(_polyTextEmf(ansi: ansi));
      final text = drawing!.ops.whereType<MetafileTextOp>().toList();
      expect(text.map((op) => op.text), <String>['A', 'B']);
      expect(text.map((op) => op.x), <double>[10, 30]);
    }
  });

  test('ANSI EMF bytes survive VSDX write and reopen', () {
    const part = '/visio/media/ansi-roundtrip.emf';
    final payload = _extTextEmf(
      ansi: true,
      charset: 0xcc,
      sourceBytes: const <int>[0xcf, 0xf0, 0xe8, 0xe2, 0xe5, 0xf2],
      sourceLength: 6,
      advancesX: const <int>[4, 5, 6, 7, 8, 9],
    );
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    const parser = DocumentParser();
    var document = parser.parse(blank);
    final page = document.pages.first;
    final picture = VsdxShapeFactory.picture(
      id: page.nextFreeShapeId(),
      pinX: 1,
      pinY: 1,
      width: 1,
      height: 1,
      imagePartName: part,
    ).copyWith(foreignType: 'EnhMetaFile');
    document = document
        .copyWith(
          images: document.images.withImage(VsdxImage(
            partName: part,
            bytes: payload,
            mimeType: 'image/x-emf',
          )),
        )
        .replacePage(0, page.addShape(picture));

    final reopened = parser.parse(writer.write(
      originalBytes: blank,
      edited: document,
    ));
    final image = reopened.images.findByPart(part)!;
    expect(image.bytes, payload);
    final text =
        parseEmfDrawing(image.bytes)!.ops.whereType<MetafileTextOp>().single;
    expect(text.text, 'Привет');
  });
}
