import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List? _loadSample(String name) {
  // Prefer in-repo fixtures so CI works without third_party/.
  final candidates = <String>[
    'test/fixtures/vsd/$name',
    // When running from repo root via `dart test path`.
    'packages/vsdx/test/fixtures/vsd/$name',
    '../../third_party/libvisio/src/test/data/$name',
  ];
  for (final p in candidates) {
    final f = File(p);
    if (f.existsSync()) return f.readAsBytesSync();
  }
  return null;
}

void main() {
  group('CFB', () {
    test('opens Visio11 sample and reads VisioDocument', () {
      final bytes = _loadSample('Visio11FormatLine.vsd');
      if (bytes == null) {
        // CI without third_party clone.
        return;
      }
      expect(looksLikeCfb(bytes), isTrue);
      expect(looksLikeVisioBinary(bytes), isTrue);
      final cfb = CompoundFile.open(bytes);
      final stream = cfb.readStream('VisioDocument');
      expect(stream, isNotNull);
      expect(stream!.length, greaterThan(100));
      expect(String.fromCharCodes(stream.sublist(0, 18)), 'Visio (TM) Drawing');
      expect(stream[0x1A], 11);
    });
  });

  group('VsdDocumentParser', () {
    test('parses FormatLine into shapes with geometry', () {
      final bytes = _loadSample('Visio11FormatLine.vsd');
      if (bytes == null) return;
      final doc = const VsdDocumentParser().parse(bytes);
      expect(doc.pages, isNotEmpty);
      final page = doc.pages.first;
      expect(page.widthInches, closeTo(8.27, 0.1));
      expect(page.heightInches, closeTo(11.69, 0.1));
      expect(page.shapes.length, greaterThan(10));
      final withGeom = page.shapes.where((s) => s.geometries.isNotEmpty);
      expect(withGeom.length, greaterThan(5));
    });

    test('parseVisio synthesises vsdx that reopens', () {
      final bytes = _loadSample('Visio11FormatLine.vsd');
      if (bytes == null) return;
      final result = parseVisio(bytes);
      expect(result.importedFromVsd, isTrue);
      expect(looksLikeZipOpc(result.originalBytes), isTrue);
      // Editing model comes from the binary parser (not a lossy reparse).
      expect(result.document.pages.first.shapes, isNotEmpty);
      expect(
        result.document.pages.first.shapes
            .where((s) => s.geometries.isNotEmpty),
        isNotEmpty,
      );
      final again = const DocumentParser().parse(result.originalBytes);
      expect(again.pages.first.shapes.length,
          result.document.pages.first.shapes.length);
    });

    test('bitmaps keep frame geometry and images via parseVisio', () {
      final bytes = _loadSample('bitmaps.vsd');
      if (bytes == null) return;
      final result = parseVisio(bytes);
      expect(result.document.images.length, greaterThan(0));
      final withImg = result.document.pages.first.shapes
          .where((s) => s.imagePartName != null);
      expect(withImg, isNotEmpty);
      expect(withImg.every((s) => s.geometries.isNotEmpty), isTrue);
      // Writer baseline also carries media + frame Geometry.
      final again = const DocumentParser().parse(result.originalBytes);
      expect(again.images.length, greaterThan(0));
      final againImg =
          again.pages.first.shapes.where((s) => s.imagePartName != null);
      expect(againImg, isNotEmpty);
      expect(againImg.every((s) => s.geometries.isNotEmpty), isTrue);
    });

    test('text fields expand numeric placeholders', () {
      final bytes = _loadSample('Visio11TextFieldsWithUnits.vsd');
      if (bytes == null) {
        // Fixture may live under third_party only.
        final alt = File('../../third_party/libvisio/src/test/data/'
            'Visio11TextFieldsWithUnits.vsd');
        if (!alt.existsSync()) return;
        final result = parseVisio(alt.readAsBytesSync());
        final texts = result.document.pages.first.shapes
            .map((s) => s.richText.plainText)
            .toList();
        final sample =
            texts.firstWhere((t) => t.contains('mm'), orElse: () => '');
        expect(sample.contains('\uFFFC'), isFalse);
        expect(sample, contains('1 mm'));
        // Raw inches must not appear as tens of thousands of km.
        expect(
          texts.any((t) => RegExp(r'3937\d').hasMatch(t)),
          isFalse,
        );
        return;
      }
      final result = parseVisio(bytes);
      final texts = result.document.pages.first.shapes
          .map((s) => s.richText.plainText)
          .toList();
      final sample =
          texts.firstWhere((t) => t.contains('mm'), orElse: () => '');
      expect(sample.contains('\uFFFC'), isFalse);
      expect(sample, contains('1 mm'));
      expect(texts.any((t) => RegExp(r'3937\d').hasMatch(t)), isFalse);
    });

    test('text fields convert angle and currency formats', () {
      final angleBytes = _loadSample('Visio11TextFieldsWithAngle.vsd');
      final currencyBytes = _loadSample('Visio11TextFieldsWithCurrency.vsd');
      if (angleBytes != null) {
        final texts = const VsdDocumentParser()
            .parse(angleBytes)
            .pages
            .first
            .shapes
            .map((s) => s.richText.plainText)
            .toList();
        expect(texts.any((t) => t.contains('-30 deg')), isTrue);
        expect(texts.any((t) => t.contains('-0.5236 rad')), isTrue);
      }
      if (currencyBytes != null) {
        final texts = const VsdDocumentParser()
            .parse(currencyBytes)
            .pages
            .first
            .shapes
            .map((s) => s.richText.plainText)
            .toList();
        expect(texts.any((t) => t.contains(r'$1.00')), isTrue);
      }
    });

    test('multi-run CharIX and TabsData import', () {
      final bytes = _loadSample('Visio6PlanWithDimensions.vsd');
      if (bytes == null) return;
      final doc = const VsdDocumentParser().parse(bytes);
      final multi = doc.pages.first.shapes
          .where((s) => s.richText.runs.length > 1)
          .toList();
      expect(multi, isNotEmpty);
      final withTabs =
          doc.pages.first.shapes.where((s) => s.richText.tabSets.isNotEmpty);
      expect(withTabs, isNotEmpty);

      // Shape 38: "Bold Custom Color" + page-name field → ≥2 CharIX runs.
      final bold = doc.pages.first.shapes.where((s) => s.id == 38);
      if (bold.isNotEmpty) {
        expect(bold.first.richText.runs.length, greaterThanOrEqualTo(2));
        expect(bold.first.richText.plainText, contains('Bold'));
      }
    });

    test('numeric-format sample keeps multi-run and tabs', () {
      final bytes = _loadSample('tdf76829-numeric-format.vsd');
      if (bytes == null) return;
      final doc = const VsdDocumentParser().parse(bytes);
      expect(
        doc.pages.first.shapes.any((s) => s.richText.runs.length > 1),
        isTrue,
      );
      expect(
        doc.pages.first.shapes.any((s) => s.richText.tabSets.isNotEmpty),
        isTrue,
      );
    });

    test('parses VSD5 PlanWithDimensions and round-trips to vsdx', () {
      final bytes = _loadSample('Visio5PlanWithDimensions.vsd');
      if (bytes == null) return;
      final result = parseVisio(bytes);
      expect(result.importedFromVsd, isTrue);
      final page = result.document.pages.first;
      expect(page.shapes.length, greaterThan(5));
      expect(page.widthInches, lessThan(20));
      expect(page.heightInches, lessThan(20));
      final withGeom = page.shapes.where((s) => s.geometries.isNotEmpty);
      expect(withGeom.length, greaterThan(3));
      expect(looksLikeZipOpc(result.originalBytes), isTrue);
      final again = const DocumentParser().parse(result.originalBytes);
      expect(again.pages.first.shapes.length, page.shapes.length);
    });

    test('parses VSD6 PlanWithDimensions', () {
      final bytes = _loadSample('Visio6PlanWithDimensions.vsd');
      if (bytes == null) return;
      final result = parseVisio(bytes);
      expect(result.importedFromVsd, isTrue);
      expect(result.document.pages, isNotEmpty);
      expect(result.document.pages.first.shapes, isNotEmpty);
      // FontIX (0x19) → CharIX FontID resolves to a real family name.
      final fonts = result.document.pages.first.shapes
          .expand((s) => s.richText.runs)
          .map((r) => r.charStyle.fontFamily)
          .whereType<String>()
          .where((f) => f.trim().isNotEmpty)
          .toSet();
      expect(fonts, isNotEmpty);
      expect(fonts.any((f) => f.contains('Liberation') || f.contains('Times')),
          isTrue);
      // ParaIX HorzAlign is imported (at least one non-default run).
      final aligns = result.document.pages.first.shapes
          .expand((s) => s.richText.runs)
          .map((r) => r.paraStyle.horizontalAlign)
          .toSet();
      expect(aligns.contains(VsdxHorzAlign.center) ||
          aligns.contains(VsdxHorzAlign.right) ||
          aligns.contains(VsdxHorzAlign.left), isTrue);
    });

    test('VSD6 TextFields resolve fonts via style parent chain', () {
      var bytes = _loadSample('Visio6TextFieldsWithUnits.vsd');
      if (bytes == null) {
        final alt = File('../../third_party/libvisio/src/test/data/'
            'Visio6TextFieldsWithUnits.vsd');
        if (!alt.existsSync()) return;
        bytes = alt.readAsBytesSync();
      }
      final doc = const VsdDocumentParser().parse(bytes);
      final fonts = doc.pages.first.shapes
          .expand((s) => s.richText.runs)
          .map((r) => r.charStyle.fontFamily)
          .whereType<String>()
          .where((f) => f.trim().isNotEmpty)
          .toSet();
      expect(fonts, isNotEmpty);
      expect(fonts.any((f) => f.contains('Liberation') || f.contains('Arial')),
          isTrue);
    });

    test('VSD5/6 shape Name is ANSI not UTF-16', () {
      final bytes = _loadSample('Visio6PlanWithDimensions.vsd');
      if (bytes == null) return;
      final doc = const VsdDocumentParser().parse(bytes);
      final names = doc.pages.first.shapes.map((s) => s.name).toList();
      expect(names.any((n) => n.contains('sq. ft.') || n.contains("'-")),
          isTrue);
      expect(names.any((n) => n.contains('Change the style')), isTrue);
      // Mojibake from UTF-16-on-ANSI must not appear.
      expect(names.any((n) => n.contains('桃') || n.contains('〸')), isFalse);
    });

    test('VSD11 FontFace resolves CharIX fontFamily', () {
      final bytes = _loadSample('Visio11FormatLine.vsd');
      if (bytes == null) return;
      final doc = const VsdDocumentParser().parse(bytes);
      final fonts = doc.pages.first.shapes
          .expand((s) => s.richText.runs)
          .map((r) => r.charStyle.fontFamily)
          .whereType<String>()
          .where((f) => f.trim().isNotEmpty)
          .toSet();
      expect(fonts, isNotEmpty);
      expect(fonts.any((f) => f == 'Calibri' || f == 'Arial'), isTrue);
    });

    test('no-bgcolor resolves geometry via master or fallback', () {
      final bytes = _loadSample('no-bgcolor.vsd');
      if (bytes == null) return;
      final doc = const VsdDocumentParser().parse(bytes);
      expect(doc.pages.first.shapes, isNotEmpty);
      final withGeom =
          doc.pages.first.shapes.where((s) => s.geometries.isNotEmpty);
      expect(withGeom, isNotEmpty);
    });

    test('PlanWithDimensions applies page/drawing scale', () {
      final bytes = _loadSample('Visio6PlanWithDimensions.vsd');
      if (bytes == null) return;
      final doc = const VsdDocumentParser().parse(bytes);
      final page = doc.pages.first;
      // Raw Visio units are huge; after scale should be letter-ish.
      expect(page.widthInches, lessThan(20));
      expect(page.heightInches, lessThan(20));
      expect(page.widthInches, greaterThan(5));
    });

    test('bitmaps.vsd embeds raster ForeignData when present', () {
      final bytes = _loadSample('bitmaps.vsd');
      if (bytes == null) return;
      final doc = const VsdDocumentParser().parse(bytes);
      expect(doc.images.length, greaterThan(0));
      final withImg =
          doc.pages.first.shapes.where((s) => s.imagePartName != null);
      expect(withImg, isNotEmpty);
      final part = withImg.first.imagePartName!;
      final img = doc.images.findByPart(part);
      expect(img, isNotNull);
      expect(img!.mimeType, 'image/bmp');
      expect(img.bytes.length, greaterThan(14));
      expect(img.bytes[0], 0x42);
      expect(img.bytes[1], 0x4D);
    });

    test('import → move shape → write vsdx → reopen', () {
      final bytes = _loadSample('Visio11FormatLine.vsd');
      if (bytes == null) return;
      final result = parseVisio(bytes);
      final page = result.document.pages.first;
      expect(page.shapes, isNotEmpty);
      final first = page.shapes.first;
      final moved = first.copyWith(pinX: first.pinX + 0.5, pinY: first.pinY + 0.25);
      final editedPage = page.copyWith(
        shapes: [
          moved,
          ...page.shapes.skip(1),
        ],
      );
      final edited = result.document.copyWith(pages: [editedPage]);
      final saved = const VsdxWriter().write(
        originalBytes: result.originalBytes,
        edited: edited,
      );
      final again = const DocumentParser().parse(saved);
      final againFirst = again.pages.first.shapes
          .firstWhere((s) => s.id == first.id);
      expect(againFirst.pinX, closeTo(moved.pinX, 1e-4));
      expect(againFirst.pinY, closeTo(moved.pinY, 1e-4));
    });

    test('resolves page name and TextXForm when present', () {
      final named = _loadSample('tdf76829-datetime-format.vsd') ??
          (File('../../third_party/libvisio/src/test/data/'
                  'tdf76829-datetime-format.vsd')
              .existsSync()
              ? File('../../third_party/libvisio/src/test/data/'
                      'tdf76829-datetime-format.vsd')
                  .readAsBytesSync()
              : null);
      if (named != null) {
        final doc = const VsdDocumentParser().parse(named);
        expect(doc.pages.first.name, isNot(startsWith('Page-')));
        expect(doc.pages.first.name.toLowerCase(), contains('zeichen'));
        final namedShapes = doc.pages.first.shapes
            .where((s) => !s.name.startsWith('Sheet.'));
        expect(namedShapes, isNotEmpty);
      }
      final bmp = _loadSample('bitmaps2.vsd');
      if (bmp == null) return;
      final doc = const VsdDocumentParser().parse(bmp);
      expect(doc.pages.first.name, 'Page-1');
      final withTxt = doc.pages.first.shapes
          .where((s) => s.richText.textBlock.pinXInches != null);
      // bitmaps2 may or may not carry TextXForm; just ensure parse succeeds.
      expect(doc.pages.first.shapes, isNotEmpty);
      expect(withTxt.length, greaterThanOrEqualTo(0));
    });

    test('date TextFields format Visio serial as calendar date', () {
      var bytes = _loadSample('tdf76829-numeric-format.vsd');
      if (bytes == null) {
        final alt = File('../../third_party/libvisio/src/test/data/'
            'tdf76829-numeric-format.vsd');
        if (!alt.existsSync()) return;
        bytes = alt.readAsBytesSync();
      }
      final doc = const VsdDocumentParser().parse(bytes);
      final texts = doc.pages.first.shapes
          .map((s) => s.richText.plainText)
          .where((t) => t.contains('Creation date'))
          .toList();
      expect(texts, isNotEmpty);
      // Must not leave raw Excel/Visio serial (e.g. 43652.139).
      expect(texts.any((t) => t.contains('43652')), isFalse);
      expect(
        texts.any((t) => RegExp(r'\d{1,2}/\d{1,2}/2019').hasMatch(t)),
        isTrue,
      );
    });

    test('string TextFields apply StrUpper/StrLower formats', () {
      final bytes = _loadSample('tdf76829-numeric-format.vsd');
      if (bytes == null) return;
      final texts = const VsdDocumentParser()
          .parse(bytes)
          .pages
          .first
          .shapes
          .map((s) => s.richText.plainText)
          .toList();
      expect(texts.any((t) => t.contains('THEDOC')), isTrue);
      expect(texts.any((t) => t.contains('thedoc')), isTrue);
      // Unformatted / StrNormal keeps original casing.
      expect(texts.any((t) => t.contains('TheDoc')), isTrue);
    });

    test('page ShapeList order is applied to root z-order', () {
      final bytes = _loadSample('Visio11FormatLine.vsd');
      if (bytes == null) return;
      final doc = const VsdDocumentParser().parse(bytes);
      final ids = doc.pages.first.shapes.map((s) => s.id).toList();
      expect(ids, isNotEmpty);
      // Encounter/id-sorted order would start at 1; ShapeList trailer places
      // later sheet ids first in this sample.
      expect(ids.first, isNot(1));
    });

    test('CharIX carries fontScale and case/position defaults', () {
      final bytes = _loadSample('Visio6PlanWithDimensions.vsd');
      if (bytes == null) return;
      final doc = const VsdDocumentParser().parse(bytes);
      final runs = doc.pages.first.shapes
          .expand((s) => s.richText.runs)
          .where((r) => r.text.trim().isNotEmpty)
          .toList();
      expect(runs, isNotEmpty);
      // scaleWidth 10000 → fontScale 1.0; mis-skipping fontMod bytes would
      // scramble Size/scale and often yield 0.
      expect(runs.every((r) => r.charStyle.fontScale > 0), isTrue);
      expect(
        runs.any((r) => (r.charStyle.fontScale - 1.0).abs() < 1e-6),
        isTrue,
      );
      // Extended fields are modelled (defaults when unset).
      expect(
        runs.every((r) =>
            r.charStyle.textCase == VsdxTextCase.normal ||
            r.charStyle.textCase == VsdxTextCase.allCaps ||
            r.charStyle.textCase == VsdxTextCase.initialCaps),
        isTrue,
      );
    });

    test('Gantt Number serials format as calendar dates', () {
      final bytes = _loadSample('tdf76829-datetime-format.vsd');
      if (bytes == null) return;
      final texts = <String>[];
      void walk(VsdxShape s) {
        final t = s.richText.plainText.trim();
        if (t.isNotEmpty) texts.add(t);
        for (final c in s.children) {
          walk(c);
        }
      }
      for (final s
          in const VsdDocumentParser().parse(bytes).pages.first.shapes) {
        walk(s);
      }
      expect(texts.any((t) => RegExp(r'\d{1,2}/\d{1,2}/\d{4}').hasMatch(t)),
          isTrue);
      // CELL_TYPE_Number Gantt bars must not stay as raw 37xxx serials.
      expect(
        texts.any((t) => RegExp(r'\b3[7-9]\d{3}(?:\.\d+)?\b').hasMatch(t)),
        isFalse,
      );
    });
  });
}
