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

BytesBuilder _emfHeader() {
  final out = BytesBuilder();
  final header = ByteData(88)
    ..setUint32(0, 1, Endian.little)
    ..setUint32(4, 88, Endian.little)
    ..setInt32(16, 200, Endian.little)
    ..setInt32(20, 100, Endian.little)
    ..setUint32(40, 0x464d4520, Endian.little);
  out.add(header.buffer.asUint8List());
  return out;
}

void _addFont(BytesBuilder out, int charset) {
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
  _addRecord(out, 82, font.buffer.asUint8List());
  _addRecord(
    out,
    37,
    (ByteData(4)..setUint32(0, 1, Endian.little)).buffer.asUint8List(),
  );
}

void _addUint32Record(BytesBuilder out, int type, int value) {
  _addRecord(
    out,
    type,
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List(),
  );
}

void _addSmallText(
  BytesBuilder out, {
  required int x,
  required int y,
  required int options,
  required List<int> stringBytes,
  required int sourceLength,
  List<int> rect = const <int>[0, 0, 80, 30],
}) {
  final noRect = (options & 0x0100) != 0;
  final payload = ByteData(28 + (noRect ? 0 : 16) + stringBytes.length)
    ..setInt32(0, x, Endian.little)
    ..setInt32(4, y, Endian.little)
    ..setUint32(8, sourceLength, Endian.little)
    ..setUint32(12, options, Endian.little)
    ..setUint32(16, 1, Endian.little) // GM_COMPATIBLE
    ..setFloat32(20, 1, Endian.little)
    ..setFloat32(24, 1, Endian.little);
  var stringAt = 28;
  if (!noRect) {
    payload
      ..setInt32(28, rect[0], Endian.little)
      ..setInt32(32, rect[1], Endian.little)
      ..setInt32(36, rect[2], Endian.little)
      ..setInt32(40, rect[3], Endian.little);
    stringAt += 16;
  }
  payload.buffer.asUint8List().setRange(
        stringAt,
        stringAt + stringBytes.length,
        stringBytes,
      );
  _addRecord(out, 108, payload.buffer.asUint8List());
}

Uint8List _finish(BytesBuilder out) {
  _addRecord(out, 14, Uint8List(0));
  return Uint8List.fromList(out.toBytes());
}

Uint8List _unicodeSmallText() {
  final out = _emfHeader();
  _addFont(out, 0);
  _addUint32Record(out, 18, 2); // SETBKMODE OPAQUE
  _addUint32Record(out, 25, 0x00332211); // SETBKCOLOR RGB(11,22,33)
  _addSmallText(
    out,
    x: 10,
    y: 20,
    options: 0x0006, // ETO_OPAQUE | ETO_CLIPPED
    stringBytes: const <int>[0x48, 0, 0x69, 0],
    sourceLength: 2,
    rect: const <int>[5, 6, 70, 32],
  );
  return _finish(out);
}

Uint8List _ansiSmallText() {
  final out = _emfHeader();
  _addFont(out, 0xcc); // RUSSIAN_CHARSET / Windows-1251
  _addUint32Record(out, 18, 2); // OPAQUE, overridden by ETO_NO_RECT
  _addSmallText(
    out,
    x: 12,
    y: 24,
    options: 0x0300, // ETO_NO_RECT | ETO_SMALL_CHARS
    stringBytes: const <int>[0xcf, 0xf0, 0xe8, 0xe2, 0xe5, 0xf2],
    sourceLength: 6,
  );
  return _finish(out);
}

VsdxPage _picturePage(String part) => VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 2,
      heightInches: 1,
      shapes: <VsdxShape>[
        VsdxShapeFactory.picture(
          id: 1,
          pinX: 1,
          pinY: 0.5,
          width: 2,
          height: 1,
          imagePartName: part,
        ),
      ],
    );

void main() {
  test('EMR_SMALLTEXTOUT replays Unicode, opaque rect, clip, and SVG', () {
    final bytes = _unicodeSmallText();
    final drawing = parseEmfDrawing(bytes);
    final text = drawing!.ops.whereType<MetafileTextOp>().single;
    expect(text.text, 'Hi');
    expect(text.x, 10);
    expect(text.y, 20);
    expect(text.backgroundArgb, 0xff112233);
    expect(text.opaqueRect!.corners.first.x, 5);
    expect(text.opaqueRect!.corners.last.y, 32);
    expect(text.clipRect, same(text.opaqueRect));

    const part = '/visio/media/small-text.emf';
    final svg = VsdxToSvgSerializer().serializePage(
      _picturePage(part),
      images: ImageRegistry.empty.withImage(VsdxImage(
        partName: part,
        bytes: bytes,
        mimeType: 'image/x-emf',
      )),
    );
    expect(svg, contains('clipPath'));
    expect(svg, contains('#112233'));
    expect(svg, contains('>Hi</text>'));
  });

  test('EMR_SMALLTEXTOUT decodes small chars using LOGFONT charset', () {
    final drawing = parseEmfDrawing(_ansiSmallText());
    final text = drawing!.ops.whereType<MetafileTextOp>().single;
    expect(text.text, 'Привет');
    expect(text.face, 'Arial');
    expect(text.backgroundArgb, isNull,
        reason: 'ETO_NO_RECT temporarily forces transparent background');
    expect(text.opaqueRect, isNull);
    expect(text.clipRect, isNull);
  });

  test('malformed small text is skipped without losing later records', () {
    final out = _emfHeader();
    _addSmallText(
      out,
      x: 10,
      y: 20,
      options: 0x0300,
      stringBytes: const <int>[0x41],
      sourceLength: 100,
    );
    final rectangle = ByteData(16)
      ..setInt32(0, 20, Endian.little)
      ..setInt32(4, 30, Endian.little)
      ..setInt32(8, 60, Endian.little)
      ..setInt32(12, 70, Endian.little);
    _addRecord(out, 43, rectangle.buffer.asUint8List());

    final drawing = parseEmfDrawing(_finish(out));
    expect(drawing!.ops.whereType<MetafileTextOp>(), isEmpty);
    expect(drawing.ops.whereType<MetafilePathOp>(), hasLength(1));
  });

  test('small text EMF survives VSDX write and reopen', () {
    const part = '/visio/media/small-text-roundtrip.emf';
    final payload = _ansiSmallText();
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
      parseEmfDrawing(image.bytes)!.ops.whereType<MetafileTextOp>().single.text,
      'Привет',
    );
  });
}
