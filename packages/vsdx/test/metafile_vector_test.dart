import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/metafile/$name').readAsBytesSync();

Uint8List _emfWithPositionedText() {
  final bytes = Uint8List(192);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 1, Endian.little); // EMR_HEADER
  data.setUint32(4, 88, Endian.little);
  data.setInt32(8, 0, Endian.little);
  data.setInt32(12, 0, Endian.little);
  data.setInt32(16, 100, Endian.little);
  data.setInt32(20, 100, Endian.little);
  data.setUint32(40, 0x464D4520, Endian.little); // " EMF"

  const record = 88;
  data.setUint32(record, 84, Endian.little); // EMR_EXTTEXTOUTW
  data.setUint32(record + 4, 96, Endian.little);
  const text = record + 36;
  data.setInt32(text, 10, Endian.little);
  data.setInt32(text + 4, 30, Endian.little);
  data.setUint32(text + 8, 2, Endian.little);
  data.setUint32(text + 12, 76, Endian.little); // offString
  data.setUint32(text + 16, 0x2000, Endian.little); // ETO_PDY
  data.setUint32(text + 36, 80, Endian.little); // offDx
  data.setUint16(record + 76, 0x41, Endian.little);
  data.setUint16(record + 78, 0x42, Endian.little);
  data.setInt32(record + 80, 13, Endian.little);
  data.setInt32(record + 84, 3, Endian.little);
  data.setInt32(record + 88, 21, Endian.little);
  data.setInt32(record + 92, -2, Endian.little);

  data.setUint32(record + 96, 14, Endian.little); // EMR_EOF
  data.setUint32(record + 100, 8, Endian.little);
  return bytes;
}

Uint8List _emfWithTextBounds({bool empty = false}) {
  final bytes = Uint8List(192);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 1, Endian.little); // EMR_HEADER
  data.setUint32(4, 88, Endian.little);
  data.setInt32(16, 100, Endian.little);
  data.setInt32(20, 100, Endian.little);
  data.setUint32(40, 0x464D4520, Endian.little); // " EMF"

  const record = 88;
  data.setUint32(record, 84, Endian.little); // EMR_EXTTEXTOUTW
  data.setUint32(record + 4, 96, Endian.little);
  const text = record + 36;
  data.setInt32(text, 4, Endian.little);
  data.setInt32(text + 4, 5, Endian.little);
  data.setUint32(text + 8, empty ? 0 : 1, Endian.little);
  data.setUint32(text + 12, empty ? 0 : 76, Endian.little);
  data.setUint32(text + 16, 0x0006, Endian.little); // OPAQUE | CLIPPED
  data.setInt32(text + 20, 2, Endian.little);
  data.setInt32(text + 24, 3, Endian.little);
  data.setInt32(text + 28, 11, Endian.little);
  data.setInt32(text + 32, 13, Endian.little);
  if (!empty) data.setUint16(record + 76, 0x41, Endian.little);

  data.setUint32(record + 96, 14, Endian.little); // EMR_EOF
  data.setUint32(record + 100, 8, Endian.little);
  return bytes;
}

Uint8List _emfWithStyledText() {
  final bytes = Uint8List(308);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 1, Endian.little); // EMR_HEADER
  data.setUint32(4, 88, Endian.little);
  data.setInt32(8, 0, Endian.little);
  data.setInt32(12, 0, Endian.little);
  data.setInt32(16, 100, Endian.little);
  data.setInt32(20, 100, Endian.little);
  data.setUint32(40, 0x464D4520, Endian.little); // " EMF"

  const font = 88;
  data.setUint32(font, 82, Endian.little); // EMR_EXTCREATEFONTINDIRECTW
  data.setUint32(font + 4, 104, Endian.little);
  data.setUint32(font + 8, 1, Endian.little); // object handle
  const logFont = font + 12;
  data.setInt32(logFont, 20, Endian.little); // lfHeight
  data.setInt32(logFont + 8, 900, Endian.little); // lfEscapement
  data.setInt32(logFont + 16, 700, Endian.little); // lfWeight
  data.setUint8(logFont + 20, 1); // lfItalic
  data.setUint8(logFont + 21, 1); // lfUnderline
  data.setUint8(logFont + 22, 1); // lfStrikeOut
  for (var i = 0; i < 'Arial'.length; i++) {
    data.setUint16(logFont + 28 + i * 2, 'Arial'.codeUnitAt(i), Endian.little);
  }

  const select = 192;
  data.setUint32(select, 37, Endian.little); // EMR_SELECTOBJECT
  data.setUint32(select + 4, 12, Endian.little);
  data.setUint32(select + 8, 1, Endian.little);

  const record = 204;
  data.setUint32(record, 84, Endian.little); // EMR_EXTTEXTOUTW
  data.setUint32(record + 4, 96, Endian.little);
  const text = record + 36;
  data.setInt32(text, 10, Endian.little);
  data.setInt32(text + 4, 30, Endian.little);
  data.setUint32(text + 8, 2, Endian.little);
  data.setUint32(text + 12, 76, Endian.little); // offString
  data.setUint32(text + 36, 80, Endian.little); // offDx
  data.setUint16(record + 76, 0x41, Endian.little);
  data.setUint16(record + 78, 0x42, Endian.little);
  data.setInt32(record + 80, 13, Endian.little);
  data.setInt32(record + 84, 21, Endian.little);

  data.setUint32(300, 14, Endian.little); // EMR_EOF
  data.setUint32(304, 8, Endian.little);
  return bytes;
}

Uint8List _wmfWithEncodedText({
  required List<int> textBytes,
  required int charset,
  required List<int> advances,
  String face = 'Arial',
}) {
  final textPadding = textBytes.length.isOdd ? 1 : 0;
  final textRecordBytes =
      6 + 8 + textBytes.length + textPadding + advances.length * 2;
  const fontRecordBytes = 56;
  const selectRecordBytes = 8;
  const eofRecordBytes = 6;
  final totalBytes = 18 +
      fontRecordBytes +
      selectRecordBytes +
      textRecordBytes +
      eofRecordBytes;
  final bytes = Uint8List(totalBytes);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 1, Endian.little); // MEMORYMETAFILE
  data.setUint16(2, 9, Endian.little); // header words
  data.setUint16(4, 0x0300, Endian.little);
  data.setUint32(6, totalBytes ~/ 2, Endian.little);
  data.setUint16(10, 1, Endian.little); // object count
  data.setUint32(12, 28, Endian.little); // largest record words

  const font = 18;
  data.setUint32(font, fontRecordBytes ~/ 2, Endian.little);
  data.setUint16(font + 4, 0x02fb, Endian.little); // CREATEFONTINDIRECT
  const logFont = font + 6;
  data.setInt16(logFont, 20, Endian.little);
  data.setUint8(logFont + 13, charset);
  for (var i = 0; i < face.length && i < 31; i++) {
    data.setUint8(logFont + 18 + i, face.codeUnitAt(i));
  }

  const select = font + fontRecordBytes;
  data.setUint32(select, selectRecordBytes ~/ 2, Endian.little);
  data.setUint16(select + 4, 0x012d, Endian.little); // SELECTOBJECT
  data.setUint16(select + 6, 0, Endian.little);

  const text = select + selectRecordBytes;
  data.setUint32(text, textRecordBytes ~/ 2, Endian.little);
  data.setUint16(text + 4, 0x0a32, Endian.little); // EXTTEXTOUT
  const textParams = text + 6;
  data.setInt16(textParams, 30, Endian.little);
  data.setInt16(textParams + 2, 10, Endian.little);
  data.setUint16(textParams + 4, textBytes.length, Endian.little);
  data.setUint16(textParams + 6, 0, Endian.little);
  bytes.setRange(textParams + 8, textParams + 8 + textBytes.length, textBytes);
  var advanceOffset = textParams + 8 + textBytes.length + textPadding;
  for (final advance in advances) {
    data.setInt16(advanceOffset, advance, Endian.little);
    advanceOffset += 2;
  }

  final eof = text + textRecordBytes;
  data.setUint32(eof, eofRecordBytes ~/ 2, Endian.little);
  return bytes;
}

Uint8List _wmfWithTextBounds({bool empty = false}) {
  final bytes = Uint8List(48);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 1, Endian.little);
  data.setUint16(2, 9, Endian.little);
  data.setUint16(4, 0x0300, Endian.little);
  data.setUint32(6, bytes.length ~/ 2, Endian.little);
  data.setUint32(12, 12, Endian.little);

  const record = 18;
  data.setUint32(record, 12, Endian.little);
  data.setUint16(record + 4, 0x0a32, Endian.little); // EXTTEXTOUT
  const text = record + 6;
  data.setInt16(text, 5, Endian.little);
  data.setInt16(text + 2, 4, Endian.little);
  data.setUint16(text + 4, empty ? 0 : 1, Endian.little);
  data.setUint16(text + 6, 0x0006, Endian.little); // OPAQUE | CLIPPED
  data.setInt16(text + 8, 2, Endian.little);
  data.setInt16(text + 10, 3, Endian.little);
  data.setInt16(text + 12, 11, Endian.little);
  data.setInt16(text + 14, 13, Endian.little);
  if (!empty) data.setUint8(text + 16, 0x41);

  data.setUint32(42, 3, Endian.little); // EOF
  return bytes;
}

Uint8List _wmfWithUpdateCpText() {
  final bytes = Uint8List(78);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 1, Endian.little);
  data.setUint16(2, 9, Endian.little);
  data.setUint16(4, 0x0300, Endian.little);
  data.setUint32(6, bytes.length ~/ 2, Endian.little);
  data.setUint32(12, 9, Endian.little);

  const align = 18;
  data.setUint32(align, 4, Endian.little);
  data.setUint16(align + 4, 0x012e, Endian.little); // SETTEXTALIGN
  data.setUint16(align + 6, 0x0001, Endian.little); // TA_UPDATECP

  const move = 26;
  data.setUint32(move, 5, Endian.little);
  data.setUint16(move + 4, 0x0214, Endian.little); // MOVETO
  data.setInt16(move + 6, 20, Endian.little);
  data.setInt16(move + 8, 10, Endian.little);

  void writeText(int offset, int character, int advance) {
    data.setUint32(offset, 9, Endian.little);
    data.setUint16(offset + 4, 0x0a32, Endian.little); // EXTTEXTOUT
    data.setInt16(offset + 6, 999, Endian.little);
    data.setInt16(offset + 8, 999, Endian.little);
    data.setUint16(offset + 10, 1, Endian.little);
    data.setUint8(offset + 14, character);
    data.setInt16(offset + 16, advance, Endian.little);
  }

  writeText(36, 0x41, 6);
  writeText(54, 0x42, 7);
  data.setUint32(72, 3, Endian.little); // EOF
  return bytes;
}

Uint8List _emfWithUpdateCpText() {
  final bytes = Uint8List(316);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 1, Endian.little); // EMR_HEADER
  data.setUint32(4, 88, Endian.little);
  data.setInt32(8, 0, Endian.little);
  data.setInt32(12, 0, Endian.little);
  data.setInt32(16, 100, Endian.little);
  data.setInt32(20, 100, Endian.little);
  data.setUint32(40, 0x464D4520, Endian.little); // " EMF"

  const align = 88;
  data.setUint32(align, 22, Endian.little); // EMR_SETTEXTALIGN
  data.setUint32(align + 4, 12, Endian.little);
  data.setUint32(align + 8, 1, Endian.little); // TA_UPDATECP

  const move = 100;
  data.setUint32(move, 27, Endian.little); // EMR_MOVETOEX
  data.setUint32(move + 4, 16, Endian.little);
  data.setInt32(move + 8, 10, Endian.little);
  data.setInt32(move + 12, 20, Endian.little);

  void writeText(int offset, int character, int advance) {
    data.setUint32(offset, 84, Endian.little); // EMR_EXTTEXTOUTW
    data.setUint32(offset + 4, 96, Endian.little);
    final text = offset + 36;
    data.setInt32(text, 999, Endian.little);
    data.setInt32(text + 4, 999, Endian.little);
    data.setUint32(text + 8, 1, Endian.little);
    data.setUint32(text + 12, 76, Endian.little);
    data.setUint32(text + 36, 80, Endian.little);
    data.setUint16(offset + 76, character, Endian.little);
    data.setInt32(offset + 80, advance, Endian.little);
  }

  writeText(116, 0x41, 6);
  writeText(212, 0x42, 7);
  data.setUint32(308, 14, Endian.little); // EMR_EOF
  data.setUint32(312, 8, Endian.little);
  return bytes;
}

void main() {
  group('WMF vector parse', () {
    test('Visio5 plan thumbnail has polygons and text', () {
      final d = parseWmfDrawing(_fixture('Visio5PlanWithDimensions.wmf'));
      expect(d, isNotNull);
      expect(d!.ops.whereType<MetafilePathOp>().length, greaterThan(5));
      expect(d.ops.whereType<MetafileTextOp>(), isNotEmpty);
      final areaLabel = d.ops
          .whereType<MetafileTextOp>()
          .firstWhere((op) => op.text == '80,00 sq. ft.');
      expect(
        areaLabel.advancesX,
        <double>[9, 9, 4, 9, 9, 5, 8, 9, 4, 5, 4, 4, 4],
      );
      expect(areaLabel.advancesY, isNull);
      expect(
        d.ops
            .whereType<MetafileTextOp>()
            .any((op) => op.escapementDegrees == 90),
        isTrue,
      );
      final hatch = d.ops
          .whereType<MetafilePathOp>()
          .where((op) => op.fillHatch != null)
          .toList();
      expect(hatch, isNotEmpty);
      expect(hatch.any((op) => op.fillHatch == 3), isTrue);
      expect(hatch.any((op) => op.fillArgb == 0xFF008000), isTrue);
      expect(
        hatch.any((op) => op.fillBackgroundArgb == 0xFFFFFFFF),
        isTrue,
      );
      expect(d.width, greaterThan(10));
      expect(d.height, greaterThan(10));
    });

    test('Visio6 plan thumbnail parses', () {
      final d = parseWmfDrawing(_fixture('Visio6PlanWithDimensions.wmf'));
      expect(d, isNotNull);
      expect(d!.ops, isNotEmpty);
      final bold = d.ops
          .whereType<MetafileTextOp>()
          .firstWhere((op) => op.text == 'Bold Custom Color ');
      expect(bold.fontWeight, 700);
      expect(bold.italic, isTrue);
      final vertical = d.ops
          .whereType<MetafileTextOp>()
          .firstWhere((op) => op.text == '6\'-0"');
      expect(vertical.escapementDegrees, 90);
      expect(
        d.ops.whereType<MetafileTextOp>().where((op) => op.advancesX != null),
        isNotEmpty,
      );
    });

    test('LOGFONT charset decodes Cyrillic ExtTextOut bytes', () {
      final drawing = parseWmfDrawing(_wmfWithEncodedText(
        textBytes: const <int>[0xcf, 0xf0, 0xe8, 0xe2, 0xe5, 0xf2],
        charset: 0xcc, // RUSSIAN_CHARSET / Windows-1251
        advances: const <int>[5, 5, 5, 5, 5, 5],
      ));
      final text = drawing!.ops.whereType<MetafileTextOp>().single;
      expect(text.text, 'Привет');
      expect(text.advancesX, const <double>[5, 5, 5, 5, 5, 5]);
    });

    test('LOGFONT charset combines Shift-JIS byte advances per glyph', () {
      final drawing = parseWmfDrawing(_wmfWithEncodedText(
        textBytes: const <int>[0x93, 0xfa, 0x96, 0x7b],
        charset: 0x80, // SHIFTJIS_CHARSET
        advances: const <int>[3, 4, 5, 6],
      ));
      final text = drawing!.ops.whereType<MetafileTextOp>().single;
      expect(text.text, '日本');
      expect(text.advancesX, const <double>[7, 11]);
    });

    test('Symbol face selects the Microsoft Symbol byte mapping', () {
      final drawing = parseWmfDrawing(_wmfWithEncodedText(
        textBytes: const <int>[0x41, 0x61],
        charset: 0,
        advances: const <int>[5, 5],
        face: 'Symbol',
      ));
      final text = drawing!.ops.whereType<MetafileTextOp>().single;
      expect(text.text, 'Αα');
      expect(text.advancesX, const <double>[5, 5]);
    });

    test('TA_UPDATECP uses MoveTo and advances consecutive WMF text', () {
      final drawing = parseWmfDrawing(_wmfWithUpdateCpText());
      final text = drawing!.ops.whereType<MetafileTextOp>().toList();
      expect(text, hasLength(2));
      expect((text[0].x, text[0].y), (10, 20));
      expect((text[1].x, text[1].y), (16, 20));
    });

    test('ExtTextOut retains opaque and clipping rectangles without text', () {
      for (final empty in <bool>[false, true]) {
        final drawing = parseWmfDrawing(_wmfWithTextBounds(empty: empty));
        final text = drawing!.ops.whereType<MetafileTextOp>().single;
        expect(text.text, empty ? '' : 'A');
        expect(text.backgroundArgb, 0xFFFFFFFF);
        expect(
          (
            text.opaqueRect!.left,
            text.opaqueRect!.top,
            text.opaqueRect!.right,
            text.opaqueRect!.bottom,
          ),
          (2, 3, 11, 13),
        );
        expect(text.clipRect, isNotNull);
      }
    });

    test('rejects random bytes', () {
      expect(parseWmfDrawing(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });

  group('EMF / OLE presentation', () {
    test('ExtTextOutW retains 32-bit ETO_PDY per-glyph advances', () {
      final drawing = parseEmfDrawing(_emfWithPositionedText());
      expect(drawing, isNotNull);
      final text = drawing!.ops.whereType<MetafileTextOp>().single;
      expect(text.text, 'AB');
      expect(text.advancesX, <double>[13, 21]);
      expect(text.advancesY, <double>[3, -2]);
    });

    test('ExtTextOutW retains opaque and clipping rectangles without text', () {
      for (final empty in <bool>[false, true]) {
        final drawing = parseEmfDrawing(_emfWithTextBounds(empty: empty));
        final text = drawing!.ops.whereType<MetafileTextOp>().single;
        expect(text.text, empty ? '' : 'A');
        expect(text.backgroundArgb, 0xFFFFFFFF);
        expect(
          (
            text.clipRect!.left,
            text.clipRect!.top,
            text.clipRect!.right,
            text.clipRect!.bottom,
          ),
          (2, 3, 11, 13),
        );
        expect(text.opaqueRect, isNotNull);
      }
    });

    test('ExtCreateFontIndirectW retains LOGFONT style and escapement', () {
      final drawing = parseEmfDrawing(_emfWithStyledText());
      expect(drawing, isNotNull);
      final text = drawing!.ops.whereType<MetafileTextOp>().single;
      expect(text.face, 'Arial');
      expect(text.fontHeight, 20);
      expect(text.fontWeight, 700);
      expect(text.italic, isTrue);
      expect(text.underline, isTrue);
      expect(text.strikeThrough, isTrue);
      expect(text.escapementDegrees, 90);
    });

    test('TA_UPDATECP uses MoveToEx and advances consecutive EMF text', () {
      final drawing = parseEmfDrawing(_emfWithUpdateCpText());
      final text = drawing!.ops.whereType<MetafileTextOp>().toList();
      expect(text, hasLength(2));
      expect((text[0].x, text[0].y), (10, 20));
      expect((text[1].x, text[1].y), (16, 20));
    });

    test('TA_UPDATECP rotates the next point with LOGFONT escapement', () {
      const op = MetafileTextOp(
        text: 'A',
        x: 10,
        y: 20,
        fontHeight: 12,
        argb: 0xFF000000,
        align: 1,
        advancesX: <double>[6],
        escapementDegrees: 90,
      );
      final next = metafileTextUpdatedCurrentPoint(op);
      expect(next.x, closeTo(10, 1e-9));
      expect(next.y, closeTo(14, 1e-9));
    });

    test('OLE OlePres EMF vector-parses from visio_with_embeded', () {
      final vsd = File('test/fixtures/vsd/external/visio_with_embeded.vsd')
          .readAsBytesSync();
      final doc = parseVisio(vsd).document;
      MetafileDrawing? drawing;
      for (final img in doc.images.all) {
        if (!img.mimeType.contains('ole')) continue;
        drawing = parseMetafileDrawing(
          img.bytes,
          mimeType: img.mimeType,
          partName: img.partName,
        );
        if (drawing != null && !drawing.isEmpty) break;
      }
      expect(drawing, isNotNull);
      expect(drawing!.ops.whereType<MetafilePathOp>(), isNotEmpty);
    });

    test('extractOlePresentationMetafile finds EMF', () {
      final vsd = File('test/fixtures/vsd/external/visio_with_embeded.vsd')
          .readAsBytesSync();
      final doc = parseVisio(vsd).document;
      var found = false;
      for (final img in doc.images.all) {
        if (!img.mimeType.contains('ole')) continue;
        final cfb = CompoundFile.open(img.bytes);
        for (final name in cfb.entryNames) {
          if (!name.contains('Pres')) continue;
          final data = cfb.readStream(name);
          if (data == null) continue;
          final emf = extractOlePresentationMetafile(img.bytes);
          if (emf != null && looksLikeEmf(emf)) {
            found = true;
            final d = parseEmfDrawing(emf);
            // Truncated dual-mode streams may still yield some polygons.
            expect(d == null || d.ops.isNotEmpty, isTrue);
          }
        }
      }
      expect(found, isTrue);
    });
  });

  group('parseMetafileDrawing facade', () {
    test('routes .wmf by extension', () {
      final bytes = _fixture('Visio5PlanWithDimensions.wmf');
      final direct = parseWmfDrawing(bytes)!;
      final d = parseMetafileDrawing(
        bytes,
        mimeType: 'image/x-wmf',
        partName: '/visio/media/x.wmf',
      );
      expect(d, isNotNull);
      expect(d!.ops.length, direct.ops.length);
      expect(
        d.ops.whereType<MetafileTextOp>().map((op) => op.text),
        direct.ops.whereType<MetafileTextOp>().map((op) => op.text),
      );
      expect(
        d.ops
            .whereType<MetafileTextOp>()
            .any((op) => op.escapementDegrees == 90),
        isTrue,
      );
    });
  });
}
