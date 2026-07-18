import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/io/image_export.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EditorController ctrl() {
    final c = EditorController()
      ..newDocument(widthInches: 11, heightInches: 8.5);
    addTearDown(c.dispose);
    return c;
  }

  int rect(EditorController e, double x, double y,
      {double w = 1, double h = 0.6, String? text}) {
    e.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: w, height: h),
        x,
        y);
    final id = e.singleSelectedId!;
    if (text != null) e.setShapeText(id, text);
    return id;
  }

  double angleDelta(double a, double b) {
    var d = a - b;
    while (d > math.pi) {
      d -= 2 * math.pi;
    }
    while (d < -math.pi) {
      d += 2 * math.pi;
    }
    return d;
  }

  test('setSelectedAngleDegrees with flipY sets page angle', () {
    final e = ctrl();
    final id = rect(e, 3, 3);
    e.flipVertical();
    expect(e.currentPage!.findShapeById(id)!.flipY, isTrue);
    e.setSelectedAngleDegrees(0);
    expect(
      angleDelta(e.currentPage!.shapePageAngle(id), 0),
      closeTo(0, 1e-6),
    );
  });

  test('hidden group children are not auto-route obstacles', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 3.5, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.addLayer(name: 'H');
    final layerId = e.currentPage!.layers.last.id;
    e.setSelection([g]);
    e.assignSelectionToLayer(layerId);
    e.toggleLayerVisibility(layerId);

    e.createConnector(1, 4, 6, 4);
    final conn = e.singleSelectedId!;
    e.setConnectorStyle(straight: false);
    final after = e.currentPage!.findShapeById(conn)!;
    // Clear path at y=4 once the group is hidden → straight segment.
    expect(after.geometries.first.commands, hasLength(2));
  });

  test('mergeCells preserves rich style and clears covered text', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(
      (id, cx, cy) => TableOps.assembleTable(
        tableId: id,
        pinX: cx,
        pinY: cy,
        width: 3,
        height: 2,
        rows: 1,
        cols: 2,
      ),
      4,
      4,
    );
    final tableId = e.singleSelectedId!;
    final cells = TableOps.cellsOf(e.currentPage!.findShapeById(tableId)!);
    final c0 = cells.firstWhere((c) => TableOps.cellCol(c) == 0);
    final c1 = cells.firstWhere((c) => TableOps.cellCol(c) == 1);
    e.setSelection([c0.id]);
    e.setShapeText(c0.id, 'Bold');
    e.setBold(true);
    e.setSelection([c1.id]);
    e.setShapeText(c1.id, 'Plain');
    e.setSelection([c0.id, c1.id]);
    e.mergeSelectedCells();
    final master = e.currentPage!.findShapeById(c0.id)!;
    expect(master.richText.plainText, contains('Bold'));
    expect(master.richText.plainText, contains('Plain'));
    expect(
      master.richText.runs.any((r) => r.charStyle.style.bold),
      isTrue,
    );
    final covered = e.currentPage!.findShapeById(c1.id)!;
    expect(TableOps.isCovered(covered), isTrue);
    expect(covered.richText.plainText.trim(), isEmpty);
    e.setSelection([c0.id]);
    e.unmergeSelectedCell();
    expect(
      e.currentPage!.findShapeById(c1.id)!.richText.plainText.trim(),
      isEmpty,
    );
  });

  test('duplicateSelection remaps connector XFTRIGGER after targets', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.singleSelectedId!;
    // Clone connector before its targets so idMap is incomplete mid-pass.
    e.setSelection([conn, a, b]);
    e.duplicateSelection();
    final page = e.currentPage!;
    final copyConn = page.shapes.lastWhere((s) => s.is1D && s.id != conn);
    final beg = copyConn.formulas['BegTrigger'] ?? '';
    final end = copyConn.formulas['EndTrigger'] ?? '';
    expect(beg.contains('Sheet.$a!'), isFalse);
    expect(end.contains('Sheet.$b!'), isFalse);
    expect(beg.contains('Sheet.'), isTrue);
    expect(end.contains('Sheet.'), isTrue);
  });

  test('reconnectEndpoint updates EndTrigger XFTRIGGER', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    final c = rect(e, 8, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.singleSelectedId!;
    e.reconnectEndpoint(
      conn,
      begin: false,
      targetShapeId: c,
      x: 8,
      y: 4,
    );
    final formulas = e.currentPage!.findShapeById(conn)!.formulas;
    expect(formulas['EndTrigger'], contains('Sheet.$c!'));
    expect(formulas['EndTrigger'], isNot(contains('Sheet.$b!')));
  });

  test('PNG export uses underlay printable layers separately', () async {
    final e = ctrl();
    e.addPage();
    e.selectPage(1);
    e.setPageIsBackground(true);
    e.addLayer(name: 'BgOnly');
    final bgLayer = e.currentPage!.layers.last.id;
    final bgShape = rect(e, 2, 2);
    e.setSelection([bgShape]);
    e.assignSelectionToLayer(bgLayer);
    final bgId = e.currentPage!.id;

    e.selectPage(0);
    e.setBackgroundPage(bgId);
    e.addLayer(name: 'FgOnly');
    // Foreground printable set must not hide the background layer by id.
    final png = await renderPageToPng(
      e.currentPage!,
      underlayPage: e.resolvedBackgroundPage,
    );
    expect(png, isNotNull);
    expect(png!.length, greaterThan(100));
  });
}
