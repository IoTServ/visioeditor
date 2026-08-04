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
        d.ops
            .whereType<MetafileTextOp>()
            .where((op) => op.advancesX != null),
        isNotEmpty,
      );
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
