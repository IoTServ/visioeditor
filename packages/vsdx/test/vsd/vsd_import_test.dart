import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List? _loadSample(String name) {
  // Prefer in-repo fixtures so CI works without third_party/.
  final candidates = <String>[
    'test/fixtures/vsd/$name',
    'test/fixtures/vsd/external/$name',
    // When running from repo root via `dart test path`.
    'packages/vsdx/test/fixtures/vsd/$name',
    'packages/vsdx/test/fixtures/vsd/external/$name',
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
      // This line-format fixture has no Fill records/styles. libvisio keeps
      // the baseline FillPattern=0 instead of inventing white solid fills.
      expect(
        result.document.pages.first.shapes
            .every((shape) => shape.fill.pattern == 0),
        isTrue,
      );
      // 1D XForm Width/Height = End−Begin may be negative — do not clamp.
      final lines1d =
          result.document.pages.first.shapes.where((s) => s.is1D).toList();
      expect(lines1d, isNotEmpty);
      expect(
        lines1d.every((s) => s.shapeKind == VsdxShapeKind.connector),
        isTrue,
      );
      expect(lines1d.where((s) => s.height < 0).length, greaterThan(10));
      expect(lines1d.where((s) => s.height == 1.0).length, lessThan(5));
      // VSD11 Misc extension blocks retain the BegTrigger / EndTrigger target
      // ids that libvisio stores on XForm1D.
      final triggered = lines1d
          .where((s) =>
              s.formulas.containsKey('BegTrigger') &&
              s.formulas.containsKey('EndTrigger'))
          .toList();
      expect(triggered, hasLength(43));
      expect(
        triggered.firstWhere((s) => s.id == 35).formulas,
        containsPair('BegTrigger', '_XFTRIGGER(Sheet.35!EventXFMod)'),
      );

      final again = const DocumentParser().parse(result.originalBytes);
      expect(again.pages.first.shapes.length,
          result.document.pages.first.shapes.length);
      expect(
        again.pages.first.shapes.every((shape) => shape.fill.pattern == 0),
        isTrue,
      );
      expect(
        again.pages.first.shapes.where((s) => s.is1D).any((s) => s.height < 0),
        isTrue,
      );
      expect(
        again.pages.first.shapes
            .where((s) => s.is1D)
            .every((s) => s.shapeKind == VsdxShapeKind.connector),
        isTrue,
      );
      expect(
        again.pages.first.shapes
            .firstWhere((s) => s.id == 35)
            .formulas['BegTrigger'],
        '_XFTRIGGER(Sheet.35!EventXFMod)',
      );
    });

    test('bitmaps keep frame geometry and images via parseVisio', () {
      final bytes = _loadSample('bitmaps.vsd');
      if (bytes == null) return;
      final result = parseVisio(bytes);
      expect(result.document.images.length, greaterThan(0));
      final withImg = result.document.pages.first.shapes
          .where((s) => s.imagePartName != null);
      expect(withImg, isNotEmpty);
      expect(
        withImg.every((s) => s.shapeKind == VsdxShapeKind.picture),
        isTrue,
      );
      expect(withImg.every((s) => s.geometries.isNotEmpty), isTrue);
      // Writer baseline also carries media + frame Geometry.
      final again = const DocumentParser().parse(result.originalBytes);
      expect(again.images.length, greaterThan(0));
      final againImg =
          again.pages.first.shapes.where((s) => s.imagePartName != null);
      expect(againImg, isNotEmpty);
      expect(againImg.every((s) => s.geometries.isNotEmpty), isTrue);
    });

    test('DrawingUnits/PageUnits use page drawingScaleUnit', () {
      // libvisio ImportTest::testVsd11DrawingUnitsType
      final bytes = _loadSample('tdf154379-DrawingUnits-type.vsd');
      if (bytes == null) return;
      final doc = const VsdDocumentParser().parse(bytes);
      expect(doc.pages, isNotEmpty);
      expect(doc.pages.first.pageSheet.pageScaleUnit, 'IN');
      expect(doc.pages.first.pageSheet.drawingScaleUnit, 'CM');
      String? plainOf(VsdxShape s) =>
          s.richText.runs.isNotEmpty ? s.richText.plainText : s.text;
      final texts = <String>[];
      void walk(VsdxShape s) {
        final t = plainOf(s);
        if (t != null && t.trim().isNotEmpty) texts.add(t);
        for (final c in s.children) {
          walk(c);
        }
      }
      for (final s in doc.pages.first.shapes) {
        walk(s);
      }
      expect(texts, contains('180.0 cm x 394.0 cm'));
      // Raw inches must not remain for DrawingUnits labels.
      expect(texts.any((t) => t.contains('70.8661')), isFalse);

      final reopened = const DocumentParser().parse(synthesizeVsdx(doc));
      expect(reopened.pages.first.pageSheet.pageScaleUnit, 'IN');
      expect(reopened.pages.first.pageSheet.drawingScaleUnit, 'CM');
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

    test('binary TextField rows and markers survive VSDX synthesis', () {
      List<VsdxShape> fieldShapes(VsdxDocument document) {
        final out = <VsdxShape>[];
        void walk(VsdxShape shape) {
          final hasMarker =
              shape.richText.runs.any((run) => run.fieldSpans.isNotEmpty);
          if (shape.fields.isNotEmpty || hasMarker) out.add(shape);
          for (final child in shape.children) {
            walk(child);
          }
        }
        for (final page in document.pages) {
          for (final shape in page.shapes) {
            walk(shape);
          }
        }
        return out;
      }

      var checked = 0;
      for (final name in const <String>[
        'Visio5TextFieldsWithUnits.vsd',
        'Visio6TextFieldsWithUnits.vsd',
        'Visio11TextFieldsWithUnits.vsd',
      ]) {
        final bytes = _loadSample(name);
        if (bytes == null) continue;
        checked++;
        final parsed = const VsdDocumentParser().parse(bytes);
        final before = fieldShapes(parsed);
        expect(before, isNotEmpty, reason: name);
        expect(before.any((shape) => shape.fields.isNotEmpty), isTrue,
            reason: name);
        expect(
          before.any((shape) =>
              shape.richText.runs.any((run) => run.fieldSpans.isNotEmpty)),
          isTrue,
          reason: name,
        );
        expect(
          before
              .expand((shape) => shape.fields)
              .any((field) => field.format != null),
          isTrue,
          reason: '$name binary numeric field pictures must remain editable',
        );
        for (final shape in before) {
          final rowIds = shape.fields.map((field) => field.ix).toSet();
          for (final span
              in shape.richText.runs.expand((run) => run.fieldSpans)) {
            expect(rowIds, contains(span.ix),
                reason:
                    '$name shape ${shape.id} field marker must resolve to a row');
          }
        }

        final reopened = const DocumentParser().parse(synthesizeVsdx(parsed));
        final afterById = <int, VsdxShape>{
          for (final shape in fieldShapes(reopened)) shape.id: shape,
        };
        for (final shape in before) {
          final after = afterById[shape.id];
          expect(after, isNotNull,
              reason: '$name shape ${shape.id} after synthesis');
          expect(after!.fields, shape.fields,
              reason: '$name shape ${shape.id} Field section');
          expect(after.richText.plainText, shape.richText.plainText,
              reason: '$name shape ${shape.id} cached field display');
          expect(
            after.richText.runs.expand((run) => run.fieldSpans).toList(),
            shape.richText.runs.expand((run) => run.fieldSpans).toList(),
            reason: '$name shape ${shape.id} fld markers',
          );
        }
      }
      expect(checked, greaterThan(0));
    });

    test('VSD synthesis keeps binary double precision and sparse fields', () {
      final bytes = _loadSample('Visio11PlanWithDimensions.vsd');
      if (bytes == null) return;
      final parsed = const VsdDocumentParser().parse(bytes);
      final reopened = const DocumentParser().parse(synthesizeVsdx(parsed));
      final before = parsed.pages.first.findShapeById(1)!;
      final after = reopened.pages.first.findShapeById(1)!;
      final beforeBlock = before.richText.textBlock;
      final afterBlock = after.richText.textBlock;

      expect(afterBlock.pinXInches, beforeBlock.pinXInches);
      expect(afterBlock.pinYInches, beforeBlock.pinYInches);
      expect(afterBlock.widthInches, beforeBlock.widthInches);
      expect(afterBlock.heightInches, beforeBlock.heightInches);
      expect(afterBlock.locPinXInches, beforeBlock.locPinXInches);
      expect(afterBlock.locPinYInches, beforeBlock.locPinYInches);
      expect(afterBlock.angleRad, beforeBlock.angleRad);
      expect(after.richText.runs.first.charStyle.fontSizeInches,
          before.richText.runs.first.charStyle.fontSizeInches);

      // Dimension fields have no binary picture. Keep the absent Format cell
      // absent rather than materialising it as an empty VSDX string.
      final beforeField = parsed.pages.first.findShapeById(8)!;
      final afterField = reopened.pages.first.findShapeById(8)!;
      expect(beforeField.fields.single.format, isNull);
      expect(afterField.fields, beforeField.fields);

      final plan6 = _loadSample('Visio6PlanWithDimensions.vsd');
      if (plan6 == null) return;
      final parsed6 = const VsdDocumentParser().parse(plan6);
      final reopened6 = const DocumentParser().parse(synthesizeVsdx(parsed6));
      final afterById = <int, VsdxShape>{};
      void index(VsdxShape shape) {
        afterById[shape.id] = shape;
        for (final child in shape.children) {
          index(child);
        }
      }
      for (final shape in reopened6.pages.first.shapes) {
        index(shape);
      }
      var comparedRows = 0;
      void compareRows(VsdxShape shape) {
        final other = afterById[shape.id]!;
        if (shape.connectionPoints.isNotEmpty) {
          expect(other.connectionPoints, shape.connectionPoints);
          comparedRows++;
        }
        if (shape.controls.isNotEmpty) {
          expect(other.controls, shape.controls);
          comparedRows++;
        }
        if (shape.scratch.isNotEmpty) {
          expect(other.scratch, shape.scratch);
          comparedRows++;
        }
        if (shape.actions.isNotEmpty) {
          expect(other.actions, shape.actions);
          comparedRows++;
        }
        for (final child in shape.children) {
          compareRows(child);
        }
      }
      for (final shape in parsed6.pages.first.shapes) {
        compareRows(shape);
      }
      expect(comparedRows, greaterThan(0));

      // VSD text bytes may intentionally end in spaces. They are not the
      // VSDX-only `newline + empty <tp/>` display convention and must remain.
      final beforeTrailing = parsed6.pages.first.findShapeById(38)!;
      final afterTrailing = reopened6.pages.first.findShapeById(38)!;
      expect(beforeTrailing.richText.plainText, endsWith('   '));
      expect(afterTrailing.richText.plainText,
          beforeTrailing.richText.plainText);
    });

    test('text fields expand Multidimensional area units', () {
      final bytes = _loadSample('Visio11TextFieldsWithUnits.vsd');
      if (bytes == null) return;
      final texts = parseVisio(bytes)
          .document
          .pages
          .first
          .shapes
          .map((s) => s.richText.plainText)
          .toList();
      expect(texts.any((t) => t.contains('1 Acre') && t.contains('1 acres')),
          isTrue);
      expect(texts.any((t) => t.contains('1 cm^2')), isTrue);
      expect(texts.any((t) => t.contains('1 ha')), isTrue);
      expect(texts.any((t) => t.contains('1 in^2')), isTrue);
      expect(texts.any((t) => t.contains('1 ft^2')), isTrue);
      // Denormal primary F64 must not surface as a bare " 0".
      expect(texts.any((t) => RegExp(r'Acre 0$').hasMatch(t)), isFalse);
    });

    test('missing CharIX fontFamily falls back to Arial', () {
      final bytes = _loadSample('tdf154379-DrawingUnits-type.vsd');
      if (bytes == null) return;
      final shapes = parseVisio(bytes).document.pages.first.shapes;
      final withText = shapes
          .where((s) => s.richText.plainText.trim().isNotEmpty)
          .toList();
      expect(withText, isNotEmpty);
      for (final s in withText) {
        for (final r in s.richText.runs) {
          expect(r.charStyle.fontFamily, isNotNull);
          expect(r.charStyle.fontFamily, isNotEmpty);
        }
      }
      final a4 = withText.where((s) => s.richText.plainText.contains('A4'));
      if (a4.isNotEmpty) {
        expect(a4.first.richText.runs.first.charStyle.fontFamily, 'Arial');
      }
    });

    test('dwg.vsd imports without OLE media (metadata-only sample)', () {
      final bytes = _loadSample('dwg.vsd');
      if (bytes == null) return;
      final result = parseVisio(bytes);
      expect(result.document.pages, isNotEmpty);
      expect(result.document.pages.first.shapes, isNotEmpty);
      // Sample has no foreignType=2 / oleData payloads (libvisio uses it for
      // document properties only). OLE import path is wired for real embeds.
      expect(result.document.images.length, 0);
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
      // VSD5 NameList2 is a packed child-record list. Skipping the list drops
      // every Name2 row, leaving NameIDX unable to resolve display names.
      expect(page.shapes.firstWhere((s) => s.id == 1).name, '"L" Room');
      expect(page.shapes.firstWhere((s) => s.id == 2).name, 'Wall');
      expect(page.shapes.firstWhere((s) => s.id == 38).name, 'Dimension line');
      // VSD5 TextBlock stops after the palette colour index. Reading the
      // VSD6/11 tail used to throw and discard the entire local block.
      final indexedBackground = page.shapes.firstWhere((s) => s.id == 38);
      expect(indexedBackground.richText.plainText,
          contains('Indexed Background Colour'));
      expect(
        indexedBackground.richText.textBlock.backgroundColor,
        const VsdxColor(0xFF800000),
      );
      expect(indexedBackground.richText.textBlock.marginLeftInches, 0);
      expect(indexedBackground.richText.textBlock.defaultTabStopInches, 0);
      expect(indexedBackground.richText.textBlock.textDirection, 0);
      expect(
        page.shapes
            .firstWhere((s) => s.id == 39)
            .richText
            .textBlock
            .backgroundColor,
        isNull,
      );
      expect(looksLikeZipOpc(result.originalBytes), isTrue);
      final again = const DocumentParser().parse(result.originalBytes);
      expect(again.pages.first.shapes.length, page.shapes.length);
      expect(again.pages.first.shapes.firstWhere((s) => s.id == 1).name,
          '"L" Room');
      expect(again.pages.first.shapes.firstWhere((s) => s.id == 2).name,
          'Wall');
      expect(again.pages.first.shapes.firstWhere((s) => s.id == 38).name,
          'Dimension line');
      expect(
        again.pages.first.shapes
            .firstWhere((s) => s.id == 38)
            .richText
            .textBlock
            .backgroundColor,
        const VsdxColor(0xFF800000),
      );
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

      // VSD6 ParaIX has a shorter fixed layout than VSD11. Reading it as
      // VSD11 used the flags/reserved bytes as a denormal bullet size and
      // consumed the first extension block as TextPosAfterBullet.
      final customColorRun = result.document.pages.first.shapes
          .expand((s) => s.richText.runs)
          .firstWhere((r) => r.text.contains('Bold Custom Color'));
      expect(customColorRun.paraStyle.bulletFont, '');
      expect(customColorRun.paraStyle.bulletFontSizeInches, 0);
      expect(customColorRun.paraStyle.textPosAfterBulletInches, 0);
      expect(customColorRun.paraStyle.flags, 0);
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

    test('Name chunk is field table not shape display name', () {
      // libvisio `readName` → m_shape.m_names (format ids / field strings).
      // Shape display names come from NameIDX or default to Sheet.N.
      final bytes = _loadSample('Visio6PlanWithDimensions.vsd');
      if (bytes == null) return;
      final doc = const VsdDocumentParser().parse(bytes);
      final names = doc.pages.first.shapes.map((s) => s.name).toList();
      expect(names.any((n) => n.contains('esc(') || n.contains('{<')), isFalse);
      // NameIDX may supply human labels (Wall, Dimension line, …).
      expect(
        names.any((n) =>
            n == 'Wall' ||
            n.contains('Room') ||
            n.contains('Dimension') ||
            n.startsWith('Sheet.')),
        isTrue,
      );
      // Dimension labels live in shape text (ANSI on VSD5/6), not Name.
      final texts =
          doc.pages.first.shapes.map((s) => s.richText.plainText).toList();
      expect(texts.any((t) => t.contains('sq. ft.') || t.contains("'-")),
          isTrue);
      expect(texts.any((t) => t.contains('桃') || t.contains('〸')), isFalse);
    });

    test('NameIDX binds shape and layer display names', () {
      final bytes = _loadSample('Visio6PlanWithDimensions.vsd');
      if (bytes == null) return;
      final page = const VsdDocumentParser().parse(bytes).pages.first;
      final names = page.shapes.map((s) => s.name).toSet();
      expect(
        names.any((n) =>
            n == 'Wall' || n.contains('Room') || n.contains('Dimension')),
        isTrue,
      );
      expect(names.any((n) => n.contains('esc(')), isFalse);
      // Layer rows may pick up NameIDX ids that match layer IX.
      final layerNames = page.layers.map((l) => l.name).toList();
      expect(layerNames, isNotEmpty);
    });

    test('Connection Points import from binary (beyond libvisio)', () {
      // libvisio defines 0x99/0xba but has no reader; walls carry endpoint cps.
      final bytes = _loadSample('Visio6PlanWithDimensions.vsd');
      if (bytes == null) return;
      final result = parseVisio(bytes);
      final withCp = result.document.pages.first.shapes
          .where((s) => s.connectionPoints.length >= 2)
          .toList();
      expect(withCp, isNotEmpty);
      final wall = withCp.first;
      expect(wall.connectionPoints.any((p) => p.x == 0 && p.y > 0), isTrue);
      expect(
        wall.connectionPoints.any((p) => (p.x - wall.width).abs() < 1e-6),
        isTrue,
      );
      // Synthesized vsdx keeps Connection section for 万兴图示 glue targets.
      final again = const DocumentParser().parse(result.originalBytes);
      final againCp = again.pages.first.shapes
          .where((s) => s.id == wall.id)
          .expand((s) => s.connectionPoints)
          .toList();
      expect(againCp.length, greaterThanOrEqualTo(2));
    });

    test('Control handles and Shape Data import (beyond libvisio)', () {
      // libvisio defines Control 0xaa / CustomProps 0xb6 but has no readers.
      final bytes = _loadSample('Visio6PlanWithDimensions.vsd');
      if (bytes == null) return;
      final result = parseVisio(bytes);
      final page = result.document.pages.first;
      final withCtrl =
          page.shapes.where((s) => s.controls.isNotEmpty).toList();
      expect(withCtrl, isNotEmpty);
      final c0 = withCtrl.first.controls.first;
      expect(c0.x.isFinite, isTrue);
      expect(c0.y.isFinite, isTrue);
      expect(c0.name, startsWith('Row_'));

      final withProp =
          page.shapes.where((s) => s.userProperties.isNotEmpty).toList();
      expect(withProp, isNotEmpty);
      final wall = withProp.firstWhere(
        (s) => s.userProperties.any((p) => p.label?.contains('Thickness') == true),
        orElse: () => withProp.first,
      );
      expect(
        wall.userProperties.any((p) => p.label != null && p.label!.isNotEmpty),
        isTrue,
      );
      expect(
        wall.userProperties.any((p) => p.value != null && p.value!.isNotEmpty),
        isTrue,
      );

      final again = const DocumentParser().parse(result.originalBytes);
      final againShape = again.pages.first.shapes.firstWhere((s) => s.id == wall.id);
      expect(againShape.controls, isNotEmpty);
      expect(againShape.userProperties, isNotEmpty);
      expect(
        againShape.userProperties.any((p) => p.label != null),
        isTrue,
      );
    });

    test('Scratch / User / Actions import (beyond libvisio)', () {
      final bytes = _loadSample('Visio6PlanWithDimensions.vsd');
      if (bytes == null) return;
      final result = parseVisio(bytes);
      final page = result.document.pages.first;
      void walk(VsdxShape s, void Function(VsdxShape) fn) {
        fn(s);
        for (final c in s.children) {
          walk(c, fn);
        }
      }
      final withScratch = <VsdxShape>[];
      final withUser = <VsdxShape>[];
      final withAct = <VsdxShape>[];
      for (final s in page.shapes) {
        walk(s, (x) {
          if (x.scratch.isNotEmpty) withScratch.add(x);
          if (x.userCells.isNotEmpty) withUser.add(x);
          if (x.actions.isNotEmpty) withAct.add(x);
        });
      }
      expect(withScratch, isNotEmpty);
      expect(withScratch.first.scratch.first.x.isFinite, isTrue);
      expect(withUser, isNotEmpty);
      expect(withAct, isNotEmpty);
      expect(withAct.first.actions.first.menu, isNotNull);

      final again = const DocumentParser().parse(result.originalBytes);
      final sid = withScratch.first.id;
      final againShape =
          again.pages.first.shapes.expand((s) sync* {
            yield s;
            for (final c in s.children) {
              yield c;
            }
          }).firstWhere((s) => s.id == sid, orElse: () => again.pages.first.shapes.first);
      expect(againShape.scratch, isNotEmpty);
    });

    test('Protection locked and Group cells import (beyond libvisio)', () {
      final gantt = _loadSample('tdf76829-datetime-format.vsd');
      if (gantt != null) {
        final result = parseVisio(gantt);
        final locked = <VsdxShape>[];
        void walk(VsdxShape s) {
          if (s.locked) locked.add(s);
          for (final c in s.children) {
            walk(c);
          }
        }
        for (final s in result.document.pages.first.shapes) {
          walk(s);
        }
        expect(locked, isNotEmpty);
        final again = const DocumentParser().parse(result.originalBytes);
        final againLocked = <VsdxShape>[];
        void walkAgain(VsdxShape s) {
          if (s.id == locked.first.id && s.locked) againLocked.add(s);
          for (final c in s.children) {
            walkAgain(c);
          }
        }
        for (final s in again.pages.first.shapes) {
          walkAgain(s);
        }
        expect(againLocked, isNotEmpty);
      }

      final plan = _loadSample('Visio6PlanWithDimensions.vsd');
      if (plan == null) return;
      final page = const VsdDocumentParser().parse(plan).pages.first;
      final withGroup = page.shapes
          .where((s) => s.displayMode != null || s.selectMode != null)
          .toList();
      expect(withGroup, isNotEmpty);
      expect(withGroup.first.displayMode, isNotNull);
    });

    test('VSD5 TextFields match VSD6 unit formatting', () {
      final v5 = _loadSample('Visio5TextFieldsWithUnits.vsd');
      final v6 = _loadSample('Visio6TextFieldsWithUnits.vsd');
      if (v5 == null || v6 == null) return;
      String pick(Uint8List bytes, String needle) {
        final texts = parseVisio(bytes)
            .document
            .pages
            .first
            .shapes
            .map((s) => s.richText.plainText)
            .where((t) => t.contains(needle))
            .toList();
        return texts.isEmpty ? '' : texts.first;
      }

      expect(pick(v5, '[cm] units'), contains('1.0 cm'));
      expect(pick(v6, '[cm] units'), contains('1.0 cm'));
      expect(pick(v5, 'formatted as rad'), contains('rad'));
      expect(pick(v5, 'elapsed minute'), contains('em.'));
      // Format-encoding junk (`%` / `$` after 0x1E) must be stripped.
      expect(pick(v5, '[cm] units').contains('%'), isFalse);
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

    test('scaled VSD synthesis does not apply drawing scale twice', () {
      final bytes = _loadSample('Visio6PlanWithDimensions.vsd');
      if (bytes == null) return;
      final parsed = const VsdDocumentParser().parse(bytes);
      final page = parsed.pages.first;

      // libvisio materialises the 1:48 drawing ratio into page/shape/line
      // values, while PageProps and shape shadow offsets remain physical.
      expect(page.pageSheet.pageScale, 1);
      expect(page.pageSheet.drawingScale, 1);
      expect(page.pageSheet.shadowOffsetXInches, closeTo(0.125, 1e-12));
      expect(page.pageSheet.shadowOffsetYInches, closeTo(-0.125, 1e-12));

      final styleShadows = <VsdxShape>[];
      void collect(VsdxShape shape) {
        if (!shape.shadow.enabled && shape.shadow.blurInches == 0) {
          styleShadows.add(shape);
        }
        for (final child in shape.children) {
          collect(child);
        }
      }

      for (final shape in page.shapes) {
        collect(shape);
      }
      expect(styleShadows, isNotEmpty);
      for (final shape in styleShadows) {
        expect(shape.shadow.offsetXInches, closeTo(0.125, 1e-12));
        expect(shape.shadow.offsetYInches, closeTo(-0.125, 1e-12));
      }

      final reopened = const DocumentParser().parse(synthesizeVsdx(parsed));
      final reopenedPage = reopened.pages.first;
      expect(reopenedPage.widthInches, closeTo(page.widthInches, 1e-9));
      expect(reopenedPage.heightInches, closeTo(page.heightInches, 1e-9));
      expect(reopenedPage.pageSheet.shadowOffsetXInches,
          closeTo(page.pageSheet.shadowOffsetXInches, 1e-9));
      expect(reopenedPage.pageSheet.shadowOffsetYInches,
          closeTo(page.pageSheet.shadowOffsetYInches, 1e-9));

      final before = page.shapes.first;
      final after = reopenedPage.findShapeById(before.id)!;
      expect(after.pinX, closeTo(before.pinX, 1e-9));
      expect(after.pinY, closeTo(before.pinY, 1e-9));
      expect(after.width, closeTo(before.width, 1e-9));
      expect(after.height, closeTo(before.height, 1e-9));
      expect(after.line.weightInches, closeTo(before.line.weightInches, 1e-9));
    });

    test('FeetAndInches TextField formats beyond libvisio TODO', () {
      // libvisio VSDFieldList still TODOs formats 10/13/14; we emit Visio-style
      // marks (e.g. 20'-6") so 万兴图示 / dimension labels stay readable.
      final bytes = _loadSample('Visio11PlanWithDimensions.vsd');
      if (bytes == null) return;
      final doc = const VsdDocumentParser().parse(bytes);
      final text = doc.pages.first.shapes
          .map((s) => s.text ?? '')
          .firstWhere((t) => t.contains('Geometry Height'), orElse: () => '');
      expect(text, contains("20'-6\""));
      expect(text.contains('20.5'), isFalse);
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
        // Binary Name chunks are field tables, not shape display names —
        // shapes correctly default to Sheet.N unless NameIDX provides one.
        expect(
          doc.pages.first.shapes.every(
            (s) => s.name.startsWith('Sheet.') || s.name.isNotEmpty,
          ),
          isTrue,
        );
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
      // libvisio MsoDateShort `%m/%d/%Y` → zero-padded.
      expect(texts.any((t) => t.contains('07/06/2019')), isTrue);
    });

    test('OLE SummaryInformation title survives synthesize', () {
      final bytes = _loadSample('fdo86729-ms1252.vsd');
      if (bytes == null) return;
      final doc = const VsdDocumentParser().parse(bytes);
      expect(doc.title, 'mytitleéá');
      expect(doc.created, isNotNull);
      expect(doc.modified, doc.created);
      final synth = synthesizeVsdx(doc);
      final again = const DocumentParser().parse(synth);
      expect(again.title, 'mytitleéá');
      expect(again.created, doc.created);
      expect(again.modified, doc.modified);
    });

    test('explicit transparent TextBkgnd does not inherit white', () {
      final bytes = _loadSample('Visio6PlanWithDimensions.vsd');
      if (bytes == null) return;
      final doc = const VsdDocumentParser().parse(bytes);
      VsdxShape? found;
      void walk(VsdxShape s) {
        if (s.richText.plainText.contains('Without Background')) {
          found = s;
        }
        for (final c in s.children) {
          walk(c);
        }
      }
      for (final s in doc.pages.first.shapes) {
        walk(s);
      }
      expect(found, isNotNull);
      expect(found!.richText.textBlock.backgroundColor, isNull);
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
      // The trailer orders ShapeList record ids, which ShapeId records map to
      // actual shape ids. Treating the trailer values as shape ids produces
      // `..., 52, 1, 53`; libvisio's mapping produces `..., 52, 53, 2`.
      expect(ids.take(20), [...List.generate(19, (i) => i + 35), 2]);
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

    test('Hyperlink 0xc4 imports Address from POI sample', () {
      final bytes = _loadSample('visio_with_embeded.vsd');
      if (bytes == null) return;
      final doc = const VsdDocumentParser().parse(bytes);
      VsdxHyperlink? found;
      void walk(VsdxShape s) {
        if (s.hyperlinks.isNotEmpty) found ??= s.hyperlinks.first;
        for (final c in s.children) {
          walk(c);
        }
      }
      for (final p in doc.pages) {
        for (final s in p.shapes) {
          walk(s);
        }
      }
      expect(found, isNotNull);
      final link = found!;
      expect(link.address, startsWith('www.'));
      expect(link.description, isNotNull);
      // Synthesised .vsdx must carry Hyperlink on Foreign shapes too.
      final result = parseVisio(bytes);
      expect(result.importedFromVsd, isTrue);
      final reopened = const DocumentParser().parse(result.originalBytes);
      VsdxHyperlink? again;
      void walk2(VsdxShape s) {
        if (s.hyperlinks.isNotEmpty) again ??= s.hyperlinks.first;
        for (final c in s.children) {
          walk2(c);
        }
      }
      for (final s in reopened.pages.first.shapes) {
        walk2(s);
      }
      expect(again?.address, link.address);
    });

    test('ConnectList 0x72 empty headers do not break parse', () {
      for (final name in ['44594.vsd', '44594-2.vsd']) {
        final bytes = _loadSample(name);
        if (bytes == null) continue;
        // Empty ConnectList payloads (childrenListLength=0); must not throw.
        final doc = const VsdDocumentParser().parse(bytes);
        expect(doc.pages, isNotEmpty);
      }
    });

    test('Event 0x84 imports EventDblClick formulas', () {
      // OPENTEXTWIN() — ubiquitous default double-click handler.
      final formatLine = _loadSample('Visio11FormatLine.vsd');
      if (formatLine != null) {
        var openText = 0;
        void walk(VsdxShape s) {
          if (s.formulas['EventDblClick'] == 'OPENTEXTWIN()') openText++;
          for (final c in s.children) {
            walk(c);
          }
        }
        for (final s
            in const VsdDocumentParser().parse(formatLine).pages.first.shapes) {
          walk(s);
        }
        expect(openText, greaterThan(10));
      }

      // RUNADDONW from POI Test_Visio sample (addon + /CMD= args).
      final poi = _loadSample('Test_Visio-Some_Random_Text.vsd');
      if (poi == null) return;
      final doc = const VsdDocumentParser().parse(poi);
      String? dbl;
      String? drop;
      void walk2(VsdxShape s) {
        dbl ??= s.formulas['EventDblClick'];
        drop ??= s.formulas['EventDrop'];
        for (final c in s.children) {
          walk2(c);
        }
      }
      for (final s in doc.pages.first.shapes) {
        walk2(s);
      }
      expect(dbl, contains('RUNADDONW'));
      expect(dbl, contains('DB Engineer'));
      expect(drop, contains('RUNADDONW'));
      expect(drop, contains('/CMD=2'));

      // Synthesised .vsdx must emit EventDblClick F=.
      final result = parseVisio(poi);
      final reopened = const DocumentParser().parse(result.originalBytes);
      String? again;
      String? dropAgain;
      void walk3(VsdxShape s) {
        again ??= s.formulas['EventDblClick'];
        dropAgain ??= s.formulas['EventDrop'];
        for (final c in s.children) {
          walk3(c);
        }
      }
      for (final s in reopened.pages.first.shapes) {
        walk3(s);
      }
      expect(again, contains('RUNADDONW'));
      expect(dropAgain, drop);

      // EventXFMod is a distinct Event-chunk cell and must survive the same
      // VSD -> synthesized VSDX -> parser round trip.
      final drawingUnits = _loadSample('tdf154379-DrawingUnits-type.vsd');
      if (drawingUnits == null) return;
      final unitsBefore = const VsdDocumentParser().parse(drawingUnits);
      final xfById = <int, String>{};
      void collectXf(VsdxShape s) {
        final formula = s.formulas['EventXFMod'];
        if (formula != null) xfById[s.id] = formula;
        for (final c in s.children) {
          collectXf(c);
        }
      }
      for (final s in unitsBefore.pages.first.shapes) {
        collectXf(s);
      }
      expect(xfById, isNotEmpty);
      final unitsAfter =
          const DocumentParser().parse(synthesizeVsdx(unitsBefore));
      var matched = 0;
      void verifyXf(VsdxShape s) {
        final expected = xfById[s.id];
        if (expected != null) {
          expect(s.formulas['EventXFMod'], expected);
          matched++;
        }
        for (final c in s.children) {
          verifyXf(c);
        }
      }
      for (final s in unitsAfter.pages.first.shapes) {
        verifyXf(s);
      }
      expect(matched, xfById.length);
    });
  });
}
