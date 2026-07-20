import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

/// Quick-add + property edits → writer → reopen → SVG, catching glue / style drift.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const writer = VsdxWriter();
  const parser = DocumentParser();

  EditorController ctrl() {
    final c = EditorController()
      ..newDocument(widthInches: 11, heightInches: 8.5);
    addTearDown(c.dispose);
    return c;
  }

  test('quickAdd + style edits survive vsdx export → reopen', () async {
    final e = ctrl();
    e.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1.5,
        height: 0.9,
      ),
      2.5,
      5.0,
    );
    final src = e.singleSelectedId!;
    e
      ..setFillColor(const VsdxColor(0xFFE53935))
      ..setLineColor(const VsdxColor(0xFFB71C1C))
      ..setLineWeight(0.03)
      ..setShapeText(src, 'Source')
      ..setBold(true)
      ..setTextColor(const VsdxColor(0xFFFFFFFF));

    e.quickAddInDirection(
      src,
      1,
      build: (id, cx, cy) => VsdxShapeFactory.ellipse(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1.4,
        height: 0.9,
      ),
      cx: 5.0,
      cy: 5.0,
    );
    final tgt = e.singleSelectedId!;
    e
      ..setFillColor(const VsdxColor(0xFF1E88E5))
      ..setLineColor(const VsdxColor(0xFF0D47A1))
      ..setShapeText(tgt, 'Target')
      ..setFillOpacity(0.7);

    // Second quick-add south from the target (Decision diamond).
    e.quickAddInDirection(
      tgt,
      2,
      build: (id, cx, cy) => VsdxShapeFactory.polygon(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1.2,
        height: 1.0,
        unit: const [
          Offset2D(0.5, 1),
          Offset2D(1, 0.5),
          Offset2D(0.5, 0),
          Offset2D(0, 0.5),
        ],
      ),
      cx: 5.0,
      cy: 3.0,
    );
    final decision = e.singleSelectedId!;
    e
      ..setFillColor(const VsdxColor(0xFFFDD835))
      ..setShapeText(decision, 'OK?');

    // Style the south-bound connector (last 1-D shape).
    final southConn = e.currentPage!.shapes.lastWhere((s) => s.is1D);
    e.setSelection([southConn.id]);
    e
      ..setLineArrows(begin: 0, end: 4)
      ..setLineColor(const VsdxColor(0xFF388E3C));

    final before = e.document!;
    expect(before.pages.first.shapes.where((s) => !s.is1D).length, 3);
    expect(before.pages.first.shapes.where((s) => s.is1D).length, 2);
    expect(before.pages.first.connects.length, greaterThanOrEqualTo(4));

    final blank = writer.emptyDocument(widthInches: 11, heightInches: 8.5);
    final outBytes = writer.write(originalBytes: blank, edited: before);
    final after = parser.parse(outBytes);
    final page = after.pages.first;

    expect(page.shapes.where((s) => !s.is1D).length, 3);
    expect(page.shapes.where((s) => s.is1D).length, 2);

    final src2 = page.findShapeById(src)!;
    final tgt2 = page.findShapeById(tgt)!;
    final dec2 = page.findShapeById(decision)!;
    expect(src2.text, 'Source');
    expect(src2.fill.foreground?.value, 0xFFE53935);
    expect(src2.line.color?.value, 0xFFB71C1C);
    expect(src2.richText.runs.first.charStyle.style.bold, isTrue);
    expect(tgt2.text, 'Target');
    expect(tgt2.fill.foreground?.value, 0xFF1E88E5);
    expect(tgt2.fill.foregroundTransparency, closeTo(0.3, 0.02));
    expect(dec2.text, 'OK?');
    expect(dec2.fill.foreground?.value, 0xFFFDD835);
    expect(src2.connectionPoints, isNotEmpty);
    expect(tgt2.connectionPoints, isNotEmpty);

    // Glue rows survive with fixed connection-point ToPart.
    for (final conn in page.shapes.where((s) => s.is1D)) {
      final rows = page.connects.where((c) => c.fromSheetId == conn.id);
      expect(rows.length, 2, reason: 'connector ${conn.id} glued both ends');
      for (final r in rows) {
        expect(r.toPart, greaterThanOrEqualTo(100),
            reason: 'fixed CP glue on ${r.fromCell}');
      }
      expect(conn.formulas['BegTrigger'], contains('XFTRIGGER'));
      expect(conn.formulas['EndTrigger'], contains('XFTRIGGER'));
    }

    final south2 = page.findShapeById(southConn.id)!;
    expect(south2.line.endArrow, 4);
    expect(south2.line.color?.value, 0xFF388E3C);

    // SVG export paints fills / strokes (display path).
    final svg = VsdxToSvgSerializer().serializePage(page, theme: after.theme);
    expect(svg.toUpperCase(), contains('E53935'));
    expect(svg.toUpperCase(), contains('1E88E5'));
    expect(svg, contains('Source'));
    expect(svg, contains('Target'));
  });

  test('quickAdd stencil inherits memo fill and round-trips', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.roundedRectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1.5,
        height: 0.8,
      ),
      3.0,
      4.0,
    );
    e
      ..setFillColor(const VsdxColor(0xFF43A047))
      ..setLineColor(const VsdxColor(0xFF1B5E20))
      ..setLineWeight(0.04);

    final src = e.singleSelectedId!;
    e.quickAddInDirection(
      src,
      1,
      build: (id, cx, cy) => VsdxShapeFactory.roundedRectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1.5,
        height: 0.8,
      ),
      cx: 5.5,
      cy: 4.0,
    );
    final clone = e.singleSelectedId!;
    // Memo style from the last edit should seed the quick-added shape.
    final added = e.currentPage!.findShapeById(clone)!;
    expect(added.fill.foreground?.value, 0xFF43A047);
    expect(added.line.color?.value, 0xFF1B5E20);
    expect(added.line.weightInches, closeTo(0.04, 1e-6));

    final blank = writer.emptyDocument(widthInches: 11, heightInches: 8.5);
    final out = writer.write(originalBytes: blank, edited: e.document!);
    final reopened = parser.parse(out);
    final again = reopened.pages.first.findShapeById(clone)!;
    expect(again.fill.foreground?.value, 0xFF43A047);
    expect(again.line.weightInches, closeTo(0.04, 1e-6));
  });

  test('palette drop materialises connection points across save → reopen', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1.4,
        height: 0.8,
      ),
      4.0,
      4.0,
    );
    final id = e.singleSelectedId!;
    final before = e.currentPage!.findShapeById(id)!;
    expect(before.connectionPoints.length, greaterThanOrEqualTo(4));

    final blank = writer.emptyDocument(widthInches: 11, heightInches: 8.5);
    final out = writer.write(originalBytes: blank, edited: e.document!);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.connectionPoints.length, before.connectionPoints.length);
  });

  test('text tool box materialises CPs and round-trips', () {
    final e = ctrl();
    e.setTool(EditorTool.text);
    e.createShapeByDrag(3, 4, 3.05, 4.05);
    final id = e.singleSelectedId!;
    final box = e.currentPage!.findShapeById(id)!;
    expect(box.connectionPoints.length, greaterThanOrEqualTo(4));

    final blank = writer.emptyDocument(widthInches: 11, heightInches: 8.5);
    final out = writer.write(originalBytes: blank, edited: e.document!);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.connectionPoints.length, box.connectionPoints.length);
  });

  test('insertImage materialises CPs across save → reopen', () {
    final e = ctrl();
    e.insertImage(
      Uint8List.fromList(<int>[137, 80, 78, 71, 0, 1, 2, 3]),
      fileExtension: 'png',
      widthInches: 1.5,
      heightInches: 1.0,
      cx: 4,
      cy: 4,
    );
    final id = e.singleSelectedId!;
    final pic = e.currentPage!.findShapeById(id)!;
    expect(pic.connectionPoints.length, greaterThanOrEqualTo(4));

    final blank = writer.emptyDocument(widthInches: 11, heightInches: 8.5);
    final out = writer.write(originalBytes: blank, edited: e.document!);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.connectionPoints.length, pic.connectionPoints.length);
  });

  test('table cells and swimlane lanes keep CPs across save → reopen', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(
      (id, cx, cy) => TableOps.assembleTable(
        tableId: id,
        pinX: cx,
        pinY: cy,
        width: 3,
        height: 2,
        rows: 2,
        cols: 2,
      ),
      3,
      5,
    );
    final tableId = e.singleSelectedId!;
    final table = e.currentPage!.findShapeById(tableId)!;
    final cells = TableOps.cellsOf(table);
    expect(cells, isNotEmpty);
    for (final c in cells) {
      expect(c.connectionPoints.length, greaterThanOrEqualTo(4),
          reason: 'cell ${c.id}');
      // Layout must refresh absolute Connection V (not stay stuck at 1×1 birth).
      final right = c.connectionPoints[1];
      expect(right.x, closeTo(c.width, 1e-6), reason: 'cell ${c.id} right CP');
    }

    e.addShapeFromBuilderAt(
      (id, cx, cy) => SwimlaneOps.assemblePool(
        poolId: id,
        pinX: cx,
        pinY: cy,
        width: 4,
        height: 3,
        laneCount: 2,
      ),
      8,
      5,
    );
    final poolId = e.singleSelectedId!;
    final pool = e.currentPage!.findShapeById(poolId)!;
    expect(pool.connectionPoints.length, greaterThanOrEqualTo(4));
    final lanes = SwimlaneOps.lanesOf(pool);
    expect(lanes.length, 2);
    for (final lane in lanes) {
      expect(lane.connectionPoints.length, greaterThanOrEqualTo(4),
          reason: 'lane ${lane.id}');
      final right = lane.connectionPoints[1];
      expect(right.x, closeTo(lane.width, 1e-6), reason: 'lane ${lane.id} CP');
    }

    final blank = writer.emptyDocument(widthInches: 11, heightInches: 8.5);
    final out = writer.write(originalBytes: blank, edited: e.document!);
    final page = parser.parse(out).pages.first;
    for (final c in TableOps.cellsOf(page.findShapeById(tableId)!)) {
      expect(c.connectionPoints.length, greaterThanOrEqualTo(4));
      expect(c.connectionPoints[1].x, closeTo(c.width, 1e-6));
    }
    final pool2 = page.findShapeById(poolId)!;
    expect(pool2.connectionPoints.length, greaterThanOrEqualTo(4));
    for (final lane in SwimlaneOps.lanesOf(pool2)) {
      expect(lane.connectionPoints.length, greaterThanOrEqualTo(4));
      expect(lane.connectionPoints[1].x, closeTo(lane.width, 1e-6));
    }
  });
}
