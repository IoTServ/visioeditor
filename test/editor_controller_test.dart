import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  EditorController newDocWithTwoRects() {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2)
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(4, 4, 5, 5);
    return c;
  }

  test('group then ungroup round-trips through the controller', () {
    final c = newDocWithTwoRects();
    expect(c.currentPage!.shapes.length, 2);

    c.selectAll();
    expect(c.canGroup, isTrue);
    expect(c.canUngroup, isFalse);

    c.groupSelection();
    final group = c.currentPage!.shapes.single;
    expect(c.currentPage!.shapes.length, 1);
    expect(group.children.length, 2);
    expect(c.selection, <int>{group.id});
    expect(c.canUngroup, isTrue);

    c.ungroupSelection();
    expect(c.currentPage!.shapes.length, 2);
    // Both promoted children end up selected, so they can be regrouped.
    expect(c.canGroup, isTrue);
  });

  test('grouping is a single undo step', () {
    final c = newDocWithTwoRects()..selectAll();
    c.groupSelection();
    expect(c.currentPage!.shapes.length, 1);
    c.undo();
    expect(c.currentPage!.shapes.length, 2);
  });

  test('line style setters update the model', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 3);
    final id = c.currentPage!.shapes.single.id;
    c.setSelection(<int>{id});

    c.setLinePattern(2);
    c.setLineArrows(begin: 1, end: 1);
    c.setLineOpacity(0.5);
    c.setFillOpacity(0.25);

    final s = c.currentPage!.findShapeById(id)!;
    expect(s.line.pattern, 2);
    expect(s.line.beginArrow, 1);
    expect(s.line.endArrow, 1);
    expect(s.line.transparency, closeTo(0.5, 1e-9));
    expect(s.fill.foregroundTransparency, closeTo(0.75, 1e-9));
  });

  test('connector routing style toggles and survives reroute', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2);
    final a = c.currentPage!.shapes.last.id;
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(6, 6, 7, 7);
    final b = c.currentPage!.shapes.last.id;

    c.createConnector(1.5, 1.5, 6.5, 6.5, beginTarget: a, endTarget: b);
    final conn = c.selection.single;
    expect(c.hasConnectorSelected, isTrue);
    expect(c.selectedConnectorStraight, isFalse); // default = orthogonal

    c.setConnectorStyle(straight: true);
    expect(c.selectedConnectorStraight, isTrue);

    // Moving a glued shape re-routes but keeps the straight preference.
    c.setSelection(<int>{a});
    c.moveSelectionBy(0.5, 0);
    c.setSelection(<int>{conn});
    expect(c.selectedConnectorStraight, isTrue);

    c.setConnectorStyle(straight: false);
    expect(c.selectedConnectorStraight, isFalse);
  });

  test('connector waypoints: add / move / remove and survive reroute', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2);
    final a = c.currentPage!.shapes.last.id;
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(6, 6, 7, 7);
    final b = c.currentPage!.shapes.last.id;
    c.createConnector(1.5, 1.5, 6.5, 6.5, beginTarget: a, endTarget: b);
    final conn = c.selection.single;

    expect(c.connectorWaypoints(conn), isEmpty);

    c.addWaypoint(conn, 0, const Offset2D(4, 2));
    expect(c.connectorWaypoints(conn), <Offset2D>[const Offset2D(4, 2)]);
    // Route now runs begin → waypoint → end.
    expect(
      VsdxPage.connectorRoute(c.currentPage!.findShapeById(conn)!).length,
      3,
    );

    c.moveWaypoint(conn, 0, const Offset2D(4, 3));
    expect(c.connectorWaypoints(conn).first, const Offset2D(4, 3));

    // Moving a glued shape reroutes but keeps the waypoint.
    c.setSelection(<int>{a});
    c.moveSelectionBy(0.5, 0);
    expect(c.connectorWaypoints(conn), <Offset2D>[const Offset2D(4, 3)]);

    // Removing it returns to an auto route.
    c.removeWaypoint(conn, 0);
    expect(c.connectorWaypoints(conn), isEmpty);
  });

  test('text (underline / font / vertical align) and shadow setters', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 3);
    final id = c.currentPage!.shapes.single.id;
    c.setSelection(<int>{id});

    c.setShapeText(id, 'Hi');
    c.setUnderline(true);
    c.setFontFamily('Georgia');
    c.setTextVerticalAlign(VsdxVertAlign.bottom);
    c.setShadow(true);

    final s = c.currentPage!.findShapeById(id)!;
    expect(s.richText.runs.first.charStyle.underline, isTrue);
    expect(s.richText.runs.first.charStyle.fontFamily, 'Georgia');
    expect(s.richText.textBlock.verticalAlign, VsdxVertAlign.bottom);
    expect(s.shadow.enabled, isTrue);
    expect(c.selectedHasShadow, isTrue);
    expect(c.selectedVerticalAlign, VsdxVertAlign.bottom);
  });

  test('copy/paste style transfers fill between shapes', () {
    final c = newDocWithTwoRects();
    final ids = <int>[for (final s in c.currentPage!.shapes) s.id];

    c.setSelection(<int>{ids.first});
    c.setFillColor(const VsdxColor(0xFFFF0000));
    c.copyStyle();
    expect(c.hasStyleClipboard, isTrue);

    c.setSelection(<int>{ids.last});
    c.pasteStyle();
    final pasted = c.currentPage!.findShapeById(ids.last)!;
    expect(pasted.fill.foreground?.value, const VsdxColor(0xFFFF0000).value);
  });
}
