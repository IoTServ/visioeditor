import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/metafile/$name').readAsBytesSync();

void main() {
  group('WMF vector parse', () {
    test('Visio5 plan thumbnail has polygons and text', () {
      final d = parseWmfDrawing(_fixture('Visio5PlanWithDimensions.wmf'));
      expect(d, isNotNull);
      expect(d!.ops.whereType<MetafilePathOp>().length, greaterThan(5));
      expect(d.ops.whereType<MetafileTextOp>(), isNotEmpty);
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
    });

    test('rejects random bytes', () {
      expect(parseWmfDrawing(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });

  group('EMF / OLE presentation', () {
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
      final d = parseMetafileDrawing(
        _fixture('Visio5PlanWithDimensions.wmf'),
        mimeType: 'image/x-wmf',
        partName: '/visio/media/x.wmf',
      );
      expect(d, isNotNull);
      expect(d!.ops.length, greaterThan(10));
    });
  });
}
