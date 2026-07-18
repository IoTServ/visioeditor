import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
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

  test('moveConnectionPoint reroutes glued connector endpoint', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 6, 4);
    e.setSelection([a]);
    e.beginEditConnectionPoints();
    // Default mid-right point index 1 (Connections.X2).
    e.createConnector(
      2,
      4,
      6,
      4,
      beginTarget: a,
      endTarget: b,
      beginConnectionPointIndex: 1,
    );
    final connId = e.singleSelectedId!;
    e.endEditConnectionPoints();
    e.setSelection([a]);
    e.beginEditConnectionPoints();
    e.moveConnectionPointAtLocal(1, 1.0, 0.1);
    final page = e.currentPage!;
    final expected = page.localToPageDeep(a, const Offset2D(1.0, 0.1));
    final conn = page.findShapeById(connId)!;
    expect(conn.beginX, closeTo(expected.x, 1e-6));
    expect(conn.beginY, closeTo(expected.y, 1e-6));
  });

  test('replaceAllFind skips children under locked-layer group', () {
    final e = ctrl();
    final a = rect(e, 2, 4, text: 'foo');
    final b = rect(e, 3, 4, text: 'foo');
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.addLayer(name: 'Lock');
    final layerId = e.currentPage!.layers.last.id;
    e.setSelection([g]);
    e.assignSelectionToLayer(layerId);
    e.toggleLayerLocked(layerId);
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    e.updateFind('foo');
    e.replaceAllFind('bar');
    expect(
      e.currentPage!.findShapeById(child)!.richText.plainText,
      'foo',
    );
  });

  test('setConnectorStyle orthogonal nested ignores phantom local obstacles',
      () {
    final e = ctrl();
    // Phantom obstacle at page (2,4): only blocks if local Begin/End are
    // wrongly fed to page-space _autoRoute.
    rect(e, 2, 4, w: 1.2, h: 1.2);
    final conn = VsdxShapeFactory.line(
      id: 50,
      ax: 0.5,
      ay: 1.0,
      bx: 3.5,
      by: 1.0,
    ).copyWith(straightRoute: true);
    final group = VsdxShape(
      id: 40,
      name: 'G',
      pinX: 8,
      pinY: 4,
      width: 4,
      height: 2,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      shapeKind: VsdxShapeKind.group,
      children: <VsdxShape>[conn],
    );
    e.updateCurrentPage(
      (p) => p.copyWith(shapes: <VsdxShape>[...p.shapes, group]),
    );
    e.setSelection([50]);
    e.setConnectorStyle(straight: false);
    final after = e.currentPage!.findShapeById(50)!;
    // Real page segment is ~(6.5,4)→(9.5,4): clear of the phantom → straight.
    expect(after.geometries.first.commands, hasLength(2));
    expect(after.beginX, closeTo(0.5, 1e-6));
    expect(after.endX, closeTo(3.5, 1e-6));
  });

  test('removeSelectedLane prunes Connect to deleted lane content', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(
      (id, cx, cy) => SwimlaneOps.assemblePool(
        poolId: id,
        pinX: cx,
        pinY: cy,
        width: 4,
        height: 3,
        laneCount: 2,
      ),
      5,
      4,
    );
    final poolId = e.singleSelectedId!;
    final lanes = SwimlaneOps.lanesOf(e.currentPage!.findShapeById(poolId)!);
    final lane0 = lanes.first.id;
    final outside = rect(e, 1, 4);
    final inner = rect(e, 5, 4);
    e.setSelection([inner]);
    e.reparentSelectionInto(lane0);
    e.createConnector(1, 4, 5, 4, beginTarget: outside, endTarget: inner);
    expect(e.currentPage!.connects, isNotEmpty);
    e.setSelection([lane0]);
    e.removeSelectedLane();
    expect(e.currentPage!.findShapeById(inner), isNull);
    expect(
      e.currentPage!.connects.any((c) => c.toSheetId == inner),
      isFalse,
    );
  });

  test('removeRowFromSelectedTable prunes Connect to deleted cells', () {
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
      4,
      4,
    );
    final tableId = e.singleSelectedId!;
    final cell = TableOps.cellsOf(e.currentPage!.findShapeById(tableId)!)
        .firstWhere((c) => TableOps.cellRow(c) == 0);
    final outside = rect(e, 1, 4);
    e.createConnector(1, 4, 4, 4, beginTarget: outside, endTarget: cell.id);
    e.setSelection([cell.id]);
    e.removeRowFromSelectedTable();
    expect(e.currentPage!.findShapeById(cell.id), isNull);
    expect(
      e.currentPage!.connects.any((c) => c.toSheetId == cell.id),
      isFalse,
    );
  });

  test('layoutLanes keeps pool-level content above lanes', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(
      (id, cx, cy) => SwimlaneOps.assemblePool(
        poolId: id,
        pinX: cx,
        pinY: cy,
        width: 4,
        height: 3,
        laneCount: 2,
      ),
      5,
      4,
    );
    final poolId = e.singleSelectedId!;
    final overlay = rect(e, 5, 4);
    e.setSelection([overlay]);
    e.reparentSelectionInto(poolId);
    e.addLaneToSelectedPool();
    final kids = e.currentPage!.findShapeById(poolId)!.children;
    final overlayIdx = kids.indexWhere((c) => c.id == overlay);
    final lastLaneIdx = kids.lastIndexWhere(SwimlaneOps.isLane);
    expect(overlayIdx, greaterThan(lastLaneIdx));
  });
}
