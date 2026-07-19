import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

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
    final boxId = c.currentPage!.shapes.single.id;
    c.setSelection(<int>{boxId});

    c.setLinePattern(2);
    c.setLineOpacity(0.5);
    c.setFillOpacity(0.25);

    final box = c.currentPage!.findShapeById(boxId)!;
    expect(box.line.pattern, 2);
    expect(box.line.transparency, closeTo(0.5, 1e-9));
    expect(box.fill.foregroundTransparency, closeTo(0.75, 1e-9));
    // Arrowheads are 1-D only — stamping them on a box is ignored.
    c.setLineArrows(begin: 1, end: 1);
    expect(c.currentPage!.findShapeById(boxId)!.line.beginArrow, 0);

    c
      ..setTool(EditorTool.line)
      ..createShapeByDrag(1, 1, 4, 1);
    final lineId = c.currentPage!.shapes.last.id;
    c.setSelection(<int>{lineId});
    c.setLineArrows(begin: 1, end: 1);
    final line = c.currentPage!.findShapeById(lineId)!;
    expect(line.line.beginArrow, 1);
    expect(line.line.endArrow, 1);
  });

  test('begin/end arrowhead type setters update the model', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.line)
      ..createShapeByDrag(1, 1, 4, 1);
    final id = c.currentPage!.shapes.single.id;
    c.setSelection(<int>{id});

    c.setBeginArrow(10); // diamond
    c.setEndArrow(4); // filled triangle
    final s = c.currentPage!.findShapeById(id)!;
    expect(s.line.beginArrow, 10);
    expect(s.line.endArrow, 4);

    c.setEndArrow(0); // none
    expect(c.currentPage!.findShapeById(id)!.line.endArrow, 0);
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

  test('connector three-way style: straight / orthogonal / curved', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2);
    final a = c.currentPage!.shapes.last.id;
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(6, 5, 7, 6);
    final b = c.currentPage!.shapes.last.id;

    c.createConnector(1.5, 1.5, 6.5, 5.5, beginTarget: a, endTarget: b);
    final conn = c.selection.single;
    expect(c.selectedConnectorRouteStyle, ConnectorRouteStyle.orthogonal);
    final orthoCount =
        c.currentPage!.findShapeById(conn)!.geometries.first.commands.length;

    // Curved → geometry becomes a dense smooth polyline.
    c.setConnectorRouteStyle(ConnectorRouteStyle.curved);
    expect(c.selectedConnectorRouteStyle, ConnectorRouteStyle.curved);
    expect(
      c.currentPage!.findShapeById(conn)!.geometries.first.commands.length,
      greaterThan(orthoCount),
    );

    // Moving a glued shape re-routes but keeps the curved preference.
    c.setSelection(<int>{a});
    c.moveSelectionBy(0.5, 0);
    c.setSelection(<int>{conn});
    expect(c.selectedConnectorRouteStyle, ConnectorRouteStyle.curved);

    // Back to straight.
    c.setConnectorRouteStyle(ConnectorRouteStyle.straight);
    expect(c.selectedConnectorRouteStyle, ConnectorRouteStyle.straight);
    expect(c.selectedConnectorStraight, isTrue);
  });

  test('connector rounded corners toggle, survive reroute, and undo', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2);
    final a = c.currentPage!.shapes.last.id;
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(6, 5, 7, 6);
    final b = c.currentPage!.shapes.last.id;

    c.createConnector(1.5, 1.5, 6.5, 5.5, beginTarget: a, endTarget: b);
    final conn = c.selection.single;
    expect(c.selectedConnectorRounded, isFalse);
    final sharpCount =
        c.currentPage!.findShapeById(conn)!.geometries.first.commands.length;

    // Round the elbow corners → geometry densifies with fillets.
    c.setConnectorRounded(true);
    expect(c.selectedConnectorRounded, isTrue);
    expect(
      c.currentPage!.findShapeById(conn)!.geometries.first.commands.length,
      greaterThan(sharpCount),
    );

    // Moving a glued shape re-routes but keeps the rounded preference.
    c.setSelection(<int>{a});
    c.moveSelectionBy(0.5, 0);
    c.setSelection(<int>{conn});
    expect(c.selectedConnectorRounded, isTrue);

    // Toggling rounded off is a single undo step.
    c.setConnectorRounded(false);
    expect(c.selectedConnectorRounded, isFalse);
    c.undo();
    expect(c.selectedConnectorRounded, isTrue);
  });

  test('setShapeHyperlinks sets, clears, and undoes a shape link', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 2);
    final id = c.currentPage!.shapes.last.id;
    c.setSelection(<int>{id});
    expect(c.selectedLink, isNull);

    c.setShapeHyperlinks(id, const <VsdxHyperlink>[
      VsdxHyperlink(id: 0, address: 'https://example.com', isDefault: true),
    ]);
    expect(c.selectedHyperlinks, hasLength(1));
    expect(c.selectedLink?.address, 'https://example.com');

    // Clear it.
    c.setShapeHyperlinks(id, const <VsdxHyperlink>[]);
    c.setSelection(<int>{id});
    expect(c.selectedLink, isNull);

    // Undo restores the link (re-select to read it back).
    c.undo();
    c.setSelection(<int>{id});
    expect(c.selectedLink?.address, 'https://example.com');
  });

  test('revealPagePoint centres on a point without changing selection', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2);
    final id = c.currentPage!.shapes.last.id;
    c.setSelection(<int>{id});
    final serial0 = c.revealSerial;

    c.revealPagePoint(3.5, 4.25);
    expect(c.revealPoint, isNotNull);
    expect(c.revealPoint!.x, closeTo(3.5, 1e-9));
    expect(c.revealPoint!.y, closeTo(4.25, 1e-9));
    expect(c.revealShapeId, isNull);
    expect(c.revealSerial, serial0 + 1);
    expect(c.selection, <int>{id}); // selection untouched

    // A shape/selection reveal clears the pending point.
    c.revealShape(id);
    expect(c.revealPoint, isNull);
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

  test('arrange: flip, rotate 90° and numeric geometry', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 2); // 2in x 1in at left=1, top(Y-up)=2
    final id = c.currentPage!.shapes.single.id;
    c.setSelection(<int>{id});

    // Flip toggles the mirror flags.
    c.flipHorizontal();
    expect(c.currentPage!.findShapeById(id)!.flipX, isTrue);
    c.flipVertical();
    expect(c.currentPage!.findShapeById(id)!.flipY, isTrue);

    // Rotate 90° clockwise subtracts a quarter turn (Visio CCW convention).
    c.rotateSelection90();
    expect(c.currentPage!.findShapeById(id)!.angleRad, closeTo(-math.pi / 2, 1e-9));
    c.rotateSelection90(clockwise: false);
    expect(c.currentPage!.findShapeById(id)!.angleRad, closeTo(0, 1e-9));

    // Numeric width keeps the left edge fixed.
    final before = c.currentPage!.findShapeById(id)!;
    final left = before.pinX - before.width / 2;
    c.setSelectedWidth(4);
    final after = c.currentPage!.findShapeById(id)!;
    expect(after.width, closeTo(4, 1e-9));
    expect(after.pinX - after.width / 2, closeTo(left, 1e-9));

    // X sets the left edge directly.
    c.setSelectedX(0);
    final moved = c.currentPage!.findShapeById(id)!;
    expect(moved.pinX - moved.width / 2, closeTo(0, 1e-9));
  });

  test('rotateSelection90 recalculates dependent Angle formulas', () {
    final c = EditorController()..newDocument();
    final a = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
    );
    final b = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 5,
      pinY: 2,
      width: 2,
      height: 1,
    ).copyWith(
      locPinXInches: 1,
      formulas: const <String, String>{
        'LocPinX': 'Sheet.1!Angle+1',
      },
    );
    c.updateCurrentPage((p) => p.copyWith(shapes: <VsdxShape>[a, b]));
    c.setSelection(<int>{1});
    c.rotateSelection90(); // Angle → -π/2
    expect(
      c.currentPage!.findShapeById(2)!.locPinXInches,
      closeTo(1 - math.pi / 2, 1e-6),
    );
  });

  test('rotateSelection90 on 1D rewrites Begin/End and keeps Angle 0', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.line)
      ..createShapeByDrag(1, 3, 5, 3);
    final id = c.currentPage!.shapes.single.id;
    c.setSelection(<int>{id});
    final before = c.currentPage!.findShapeById(id)!;
    expect(before.beginY, closeTo(before.endY!, 1e-6));
    c.rotateSelection90(clockwise: false); // +90° CCW about pin
    final after = c.currentPage!.findShapeById(id)!;
    expect(after.angleRad, 0);
    expect(after.flipX, isFalse);
    // Horizontal → vertical about pin (3,3): ends near x=3.
    expect(after.beginX, closeTo(3, 0.15));
    expect(after.endX, closeTo(3, 0.15));
    expect((after.beginY! - after.endY!).abs(), greaterThan(1.5));
  });

  test('flipHorizontal on 1D mirrors Begin/End without FlipX', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.line)
      ..createShapeByDrag(1, 3, 5, 3);
    final id = c.currentPage!.shapes.single.id;
    c.setSelection(<int>{id});
    final before = c.currentPage!.findShapeById(id)!;
    c.flipHorizontal();
    final after = c.currentPage!.findShapeById(id)!;
    expect(after.flipX, isFalse);
    expect(after.angleRad, 0);
    expect(after.beginX, closeTo(before.endX!, 1e-6));
    expect(after.endX, closeTo(before.beginX!, 1e-6));
  });

  test('resize with corner LocPin keeps page AABB after pin+nudge', () {
    final c = EditorController()..newDocument();
    final box = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
    ).copyWith(locPinXInches: 0, locPinYInches: 0);
    c.updateCurrentPage((p) => p.copyWith(shapes: <VsdxShape>[box]));
    c.setSelection(<int>{1});
    final before = c.currentPage!.shapePageAabb(1)!;
    // Canvas-handle path: resize about Pin, then nudge AABB left/bottom.
    c.resizeShape(
      1,
      pinX: box.pinX,
      pinY: box.pinY,
      width: 4,
      height: 2,
      transient: true,
    );
    final mid = c.currentPage!.shapePageAabb(1)!;
    c.moveSelectionBy(before.left - mid.left, before.bottom - mid.bottom,
        transient: true);
    final after = c.currentPage!.shapePageAabb(1)!;
    expect(after.left, closeTo(before.left, 1e-6));
    expect(after.bottom, closeTo(before.bottom, 1e-6));
    expect(after.right - after.left, closeTo(4, 1e-6));
    expect(after.top - after.bottom, closeTo(2, 1e-6));
    // Pin stays at the corner LocPin (left/bottom), not the AABB centre.
    final pin = c.currentPage!.shapePinPage(1);
    expect(pin.x, closeTo(after.left, 1e-6));
    expect(pin.y, closeTo(after.bottom, 1e-6));
  });

  test('rotateShape on glued connector is not undone by reroute', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 3.5, 2, 4.5);
    final a = c.selection.single;
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(5, 3.5, 6, 4.5);
    final b = c.selection.single;
    c.createConnector(1.5, 4, 5.5, 4, beginTarget: a, endTarget: b);
    final connId = c.selection.single;
    c.setSelection(<int>{connId});
    c.setSelectedAngleDegrees(90); // via rotateShape
    final after = c.currentPage!.findShapeById(connId)!;
    expect(after.beginX, closeTo(after.endX!, 0.35));
    expect((after.beginY! - after.endY!).abs(), greaterThan(1.5));
  });

  test('resizeShape on glued connector is not undone by reroute', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 3.5, 2, 4.5);
    final a = c.selection.single;
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(5, 3.5, 6, 4.5);
    final b = c.selection.single;
    c.createConnector(1.5, 4, 5.5, 4, beginTarget: a, endTarget: b);
    final connId = c.selection.single;
    final before = c.currentPage!.findShapeById(connId)!;
    final pinX = before.pinX;
    final pinY = before.pinY;
    c.resizeShape(
      connId,
      pinX: pinX,
      pinY: pinY,
      width: before.width * 0.5,
      height: before.height,
    );
    final after = c.currentPage!.findShapeById(connId)!;
    expect(after.width.abs(), closeTo(before.width.abs() * 0.5, 0.25));
  });

  test('rotateSelection90 on glued connector is not undone by reroute', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 3.5, 2, 4.5);
    final a = c.selection.single;
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(5, 3.5, 6, 4.5);
    final b = c.selection.single;
    c.createConnector(1.5, 4, 5.5, 4, beginTarget: a, endTarget: b);
    final connId = c.selection.single;
    expect(c.currentPage!.connects.where((x) => x.fromSheetId == connId),
        isNotEmpty);
    c.setSelection(<int>{connId});
    c.rotateSelection90(clockwise: false); // +90° CCW about pin
    final after = c.currentPage!.findShapeById(connId)!;
    // Must stay a vertical bake — reroute must not snap ends back onto A/B.
    expect(after.beginX, closeTo(after.endX!, 0.35));
    expect((after.beginY! - after.endY!).abs(), greaterThan(1.5));
  });

  test('flipHorizontal on glued connector is not undone by reroute', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 3.5, 2, 4.5);
    final a = c.selection.single;
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(5, 3.5, 6, 4.5);
    final b = c.selection.single;
    c.createConnector(1.5, 4, 5.5, 4, beginTarget: a, endTarget: b);
    final connId = c.selection.single;
    final before = c.currentPage!.findShapeById(connId)!;
    c.setSelection(<int>{connId});
    c.flipHorizontal();
    final after = c.currentPage!.findShapeById(connId)!;
    // Mirror swaps ends about pin; glue reroute must not restore A→B order.
    expect(after.beginX, closeTo(before.endX!, 0.4));
    expect(after.endX, closeTo(before.beginX!, 0.4));
  });

  test('one-step z-order moves the selection forward and backward', () {
    final c = newDocWithTwoRects();
    final ids = <int>[for (final s in c.currentPage!.shapes) s.id];
    // Initial order: [first, second].
    c.setSelection(<int>{ids.first});
    c.bringSelectionForward();
    expect(c.currentPage!.shapes.map((s) => s.id).toList(), [ids.last, ids.first]);
    c.sendSelectionBackward();
    expect(c.currentPage!.shapes.map((s) => s.id).toList(), [ids.first, ids.last]);
  });

  test('new shapes inherit the last-used fill / line style', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 3);
    final first = c.currentPage!.shapes.single.id;
    c.setSelection(<int>{first});
    c.setFillColor(const VsdxColor(0xFF00FF00));
    c.setLineColor(const VsdxColor(0xFF0000FF));

    // A brand-new rectangle picks up the remembered fill + line.
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(5, 5, 6, 6);
    final second = c.currentPage!.shapes.last;
    expect(second.id, isNot(first));
    expect(second.fill.foreground?.value, 0xFF00FF00);
    expect(second.line.color?.value, 0xFF0000FF);

    // A new line inherits the stroke but never gains a fill.
    c
      ..setTool(EditorTool.line)
      ..createShapeByDrag(1, 6, 4, 6);
    final line = c.currentPage!.shapes.last;
    expect(line.line.color?.value, 0xFF0000FF);
    expect(line.fill.pattern, 0);
  });

  test('corner radius rounds a rectangle and toggles back to square', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 4, 3);
    final id = c.currentPage!.shapes.single.id;
    c.setSelection(<int>{id});
    expect(c.selectedCornerRadius, 0); // plain rectangle

    c.setCornerRadius(0.3);
    expect(c.selectedCornerRadius, closeTo(0.3, 1e-9));
    expect(
      c.currentPage!
          .findShapeById(id)!
          .geometries
          .first
          .commands
          .whereType<EllipticalArcTo>()
          .length,
      4,
    );

    c.setCornerRadius(0); // back to square
    expect(c.selectedCornerRadius, 0);
    expect(
      c.currentPage!
          .findShapeById(id)!
          .geometries
          .first
          .commands
          .whereType<EllipticalArcTo>(),
      isEmpty,
    );
  });

  test('cancelTransaction reverts a transient drag without history', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 3);
    final id = c.currentPage!.shapes.single.id;
    c.setSelection(<int>{id});
    final x0 = c.currentPage!.findShapeById(id)!.pinX;

    c.beginTransaction();
    c.moveSelectionBy(2, 0, transient: true);
    expect(c.currentPage!.findShapeById(id)!.pinX, closeTo(x0 + 2, 1e-9));

    c.cancelTransaction();
    expect(c.currentPage!.findShapeById(id)!.pinX, closeTo(x0, 1e-9));

    // The cancelled drag left no undo step: the next undo removes the shape.
    c.undo();
    expect(c.currentPage!.shapes, isEmpty);
  });

  test('find matches shapes by text, selects and cycles', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2);
    final a = c.currentPage!.shapes.last.id;
    c.setShapeText(a, 'Alpha');
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(4, 4, 5, 5);
    final b = c.currentPage!.shapes.last.id;
    c.setShapeText(b, 'Beta');
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(6, 6, 7, 7);
    final d = c.currentPage!.shapes.last.id;
    c.setShapeText(d, 'Alphabet');

    c.updateFind('alph');
    expect(c.findMatchCount, 2); // Alpha + Alphabet
    expect(c.findCurrentOrdinal, 1);
    expect(c.selection, <int>{a}); // first match selected

    final serial = c.revealSerial;
    c.findNext();
    expect(c.findCurrentOrdinal, 2);
    expect(c.selection, <int>{d});
    expect(c.revealSerial, greaterThan(serial)); // asked the canvas to reveal

    c.findNext(); // wraps back to the first
    expect(c.findCurrentOrdinal, 1);
    expect(c.selection, <int>{a});

    c.clearFind();
    expect(c.findMatchCount, 0);
    expect(c.findQuery, isEmpty);
  });

  test('addLaneToSelectedPool and removeSelectedLane', () {
    final c = EditorController()..newDocument();
    c.addShapeFromBuilderAt(
      (id, cx, cy) => SwimlaneOps.assemblePool(
        poolId: id,
        pinX: cx,
        pinY: cy,
        width: 4,
        height: 3,
        laneCount: 2,
      ),
      4,
      5,
    );
    final poolId = c.selection.single;
    expect(c.canAddLane, isTrue);
    expect(SwimlaneOps.lanesOf(c.currentPage!.findShapeById(poolId)!),
        hasLength(2));

    c.addLaneToSelectedPool();
    expect(SwimlaneOps.lanesOf(c.currentPage!.findShapeById(poolId)!),
        hasLength(3));
    final laneId = c.selection.single;
    expect(c.canRemoveLane, isTrue);

    c.removeSelectedLane();
    expect(SwimlaneOps.lanesOf(c.currentPage!.findShapeById(poolId)!),
        hasLength(2));
    expect(c.selection, <int>{poolId});
    expect(c.currentPage!.findShapeById(laneId), isNull);
  });

  test('table add/remove row and column', () {
    final c = EditorController()..newDocument();
    c.addShapeFromBuilderAt(
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
      4,
    );
    final tableId = c.selection.single;
    expect(c.canAddTableRow, isTrue);
    expect(TableOps.dimensions(c.currentPage!.findShapeById(tableId)!).rows, 2);

    c.addRowToSelectedTable();
    expect(TableOps.dimensions(c.currentPage!.findShapeById(tableId)!).rows, 3);
    c.addColumnToSelectedTable();
    expect(TableOps.dimensions(c.currentPage!.findShapeById(tableId)!).cols, 3);

    // Select a cell then delete its row.
    final cell = TableOps.cellsOf(c.currentPage!.findShapeById(tableId)!)
        .firstWhere((x) => TableOps.cellRow(x) == 1);
    c.selectOnly(cell.id);
    expect(c.canRemoveTableRow, isTrue);
    c.removeRowFromSelectedTable();
    expect(TableOps.dimensions(c.currentPage!.findShapeById(tableId)!).rows, 2);
  });

  test('mergeSelectedCells and unmergeSelectedCell', () {
    final c = EditorController()..newDocument();
    c.addShapeFromBuilderAt(
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
      4,
    );
    final tableId = c.selection.single;
    final cells = TableOps.cellsOf(c.currentPage!.findShapeById(tableId)!);
    final a = cells.firstWhere(
        (x) => TableOps.cellRow(x) == 0 && TableOps.cellCol(x) == 0);
    final b = cells.firstWhere(
        (x) => TableOps.cellRow(x) == 0 && TableOps.cellCol(x) == 1);
    c
      ..selectOnly(a.id)
      ..toggleSelection(b.id);
    expect(c.canMergeCells, isTrue);
    c.mergeSelectedCells();
    final master = c.currentPage!.findShapeById(a.id)!;
    expect(TableOps.colSpan(master), 2);
    expect(c.canUnmergeCell, isTrue);
    c.unmergeSelectedCell();
    expect(TableOps.colSpan(c.currentPage!.findShapeById(a.id)!), 1);
    expect(
      TableOps.cellsOf(c.currentPage!.findShapeById(tableId)!)
          .where(TableOps.isCovered),
      isEmpty,
    );
  });

  test('mergeSelectedCells remaps glue from covered cells to master', () {
    final c = EditorController()..newDocument();
    c.addShapeFromBuilderAt(
      (id, cx, cy) => TableOps.assembleTable(
        tableId: id,
        pinX: cx,
        pinY: cy,
        width: 4,
        height: 3,
        rows: 2,
        cols: 2,
      ),
      3,
      4,
    );
    final tableId = c.selection.single;
    final cells = TableOps.cellsOf(c.currentPage!.findShapeById(tableId)!);
    final master = cells.firstWhere(
        (x) => TableOps.cellRow(x) == 0 && TableOps.cellCol(x) == 0);
    final covered = cells.firstWhere(
        (x) => TableOps.cellRow(x) == 0 && TableOps.cellCol(x) == 1);
    final pin = c.currentPage!.shapePinPage(covered.id);
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(7, 3, 8, 4);
    final box = c.currentPage!.shapes.lastWhere((s) => !s.is1D && s.id != tableId).id;
    c.createConnector(pin.x, pin.y, 7.5, 3.5,
        beginTarget: covered.id, endTarget: box);
    final conn = c.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    expect(
      c.currentPage!.connects
          .any((e) => e.fromSheetId == conn && e.toSheetId == covered.id),
      isTrue,
    );
    c
      ..selectOnly(master.id)
      ..toggleSelection(covered.id);
    c.mergeSelectedCells();
    expect(TableOps.isCovered(c.currentPage!.findShapeById(covered.id)!), isTrue);
    final beginGlue = c.currentPage!.connects
        .firstWhere((e) => e.fromSheetId == conn && e.isBegin);
    expect(beginGlue.toSheetId, master.id);
    expect(
      c.currentPage!.findShapeById(conn)!.formulas['BegTrigger'],
      contains('Sheet.${master.id}!'),
    );
    expect(
      c.currentPage!.findShapeById(conn)!.formulas['BegTrigger'],
      isNot(contains('Sheet.${covered.id}!')),
    );
  });

  test('replaceFind and replaceAllFind update labels', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2);
    final a = c.currentPage!.shapes.last.id;
    c.setShapeText(a, 'Alpha');
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(4, 4, 5, 5);
    final b = c.currentPage!.shapes.last.id;
    c.setShapeText(b, 'Alphabet');

    c.updateFind('alph');
    expect(c.findMatchCount, 2);
    c.replaceFind('Z');
    // "Alpha" → first "Alph" (len 4) replaced → "Za"
    expect(c.currentPage!.findShapeById(a)!.richText.plainText, 'Za');
    // After replace, advances toward remaining "Alphabet"
    expect(c.selection, <int>{b});

    c.replaceAllFind('Q');
    expect(c.currentPage!.findShapeById(b)!.richText.plainText, 'Qabet');
    expect(c.findMatchCount, 0);

    c.undo(); // undo replace-all
    expect(c.currentPage!.findShapeById(b)!.richText.plainText, 'Alphabet');
  });

  test('align single selection to page', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(2, 2, 3, 3); // 1×1 at pin (2.5, 2.5)
    final id = c.currentPage!.shapes.single.id;
    c.setSelection(<int>{id});

    c.alignLeft();
    expect(c.currentPage!.findShapeById(id)!.pinX, closeTo(0.5, 1e-9));

    c.alignRight();
    final w = c.pageSize!.width;
    expect(c.currentPage!.findShapeById(id)!.pinX, closeTo(w - 0.5, 1e-9));

    c.alignCenterH();
    expect(c.currentPage!.findShapeById(id)!.pinX, closeTo(w / 2, 1e-9));

    c.alignBottom();
    expect(c.currentPage!.findShapeById(id)!.pinY, closeTo(0.5, 1e-9));

    c.alignTop();
    final h = c.pageSize!.height;
    expect(c.currentPage!.findShapeById(id)!.pinY, closeTo(h - 0.5, 1e-9));

    c.alignMiddle();
    expect(c.currentPage!.findShapeById(id)!.pinY, closeTo(h / 2, 1e-9));
  });

  test('find whole word excludes substring hits', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2);
    final a = c.currentPage!.shapes.last.id;
    c.setShapeText(a, 'cat');
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(3, 3, 4, 4);
    final b = c.currentPage!.shapes.last.id;
    c.setShapeText(b, 'concatenate');

    c.updateFind('cat');
    expect(c.findMatchCount, 2);
    c.setFindWholeWord(true);
    expect(c.findMatchCount, 1);
    expect(c.selection, <int>{a});

    c.replaceAllFind('dog');
    expect(c.currentPage!.findShapeById(a)!.richText.plainText, 'dog');
    expect(c.currentPage!.findShapeById(b)!.richText.plainText, 'concatenate');
  });

  test('find spans pages, match case, and replace-all is one undo', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2);
    final a = c.currentPage!.shapes.last.id;
    c.setShapeText(a, 'Alpha');
    c.addPage();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2);
    final b = c.currentPage!.shapes.last.id;
    c.setShapeText(b, 'alpha');

    c.selectPage(0);
    c.updateFind('alpha');
    expect(c.findMatchCount, 2); // case-insensitive by default
    expect(c.findCurrentPageIndex, 0);
    c.findNext();
    expect(c.currentPageIndex, 1);
    expect(c.selection, <int>{b});
    expect(c.findQuery, 'alpha'); // page switch via find keeps query

    c.setFindMatchCase(true);
    expect(c.findMatchCount, 1); // only lowercase "alpha"
    expect(c.selection, <int>{b});

    c.setFindMatchCase(false);
    c.replaceAllFind('Z');
    expect(c.document!.pages[0].findShapeById(a)!.richText.plainText, 'Z');
    expect(c.document!.pages[1].findShapeById(b)!.richText.plainText, 'Z');
    c.undo();
    expect(c.document!.pages[0].findShapeById(a)!.richText.plainText, 'Alpha');
    expect(c.document!.pages[1].findShapeById(b)!.richText.plainText, 'alpha');
  });

  test('setFillGradient installs and clears gradient fill', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 2);
    final id = c.currentPage!.shapes.single.id;
    c.setSelection(<int>{id});

    c.setFillGradient(
      const VsdxGradient(
        type: VsdxGradientType.linear,
        angleRad: 0.5,
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFF1565C0)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFFFFFFFF)),
        ],
      ),
    );
    final g = c.currentPage!.findShapeById(id)!.fill.gradient!;
    expect(g.type, VsdxGradientType.linear);
    expect(g.stops.length, 2);
    expect(g.angleRad, closeTo(0.5, 1e-9));

    c.setFillGradient(null);
    expect(c.currentPage!.findShapeById(id)!.fill.hasGradient, isFalse);

    // Solid swatch clears any previous gradient.
    c.setFillGradient(
      const VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
        ],
      ),
    );
    c.setFillColor(const VsdxColor(0xFF00FF00));
    expect(c.currentPage!.findShapeById(id)!.fill.hasGradient, isFalse);
    expect(c.currentPage!.findShapeById(id)!.fill.foreground?.value,
        0xFF00FF00);
  });

  test('setLineGradient installs and clears; setNoLine clears gradient', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 2);
    final id = c.currentPage!.shapes.single.id;
    c.setSelection(<int>{id});

    c.setLineGradient(
      const VsdxGradient(
        type: VsdxGradientType.linear,
        angleRad: 0.25,
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFF212121)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF90CAF9)),
        ],
      ),
    );
    final line = c.currentPage!.findShapeById(id)!.line;
    expect(line.hasGradient, isTrue);
    expect(line.gradient!.type, VsdxGradientType.linear);
    expect(line.gradient!.angleRad, closeTo(0.25, 1e-9));
    expect(line.pattern, isNonZero);

    c.setLineGradient(null);
    expect(c.currentPage!.findShapeById(id)!.line.hasGradient, isFalse);

    c.setLineGradient(
      const VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
        ],
      ),
    );
    c.setLineColor(const VsdxColor(0xFF00FF00));
    expect(c.currentPage!.findShapeById(id)!.line.hasGradient, isFalse);

    c.setLineGradient(
      const VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFF000000)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFFFFFFFF)),
        ],
      ),
    );
    c.setNoLine();
    final cleared = c.currentPage!.findShapeById(id)!.line;
    expect(cleared.pattern, 0);
    expect(cleared.hasGradient, isFalse);
  });

  test('updateShadow sets colour / offset / blur / opacity', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 2);
    final id = c.currentPage!.shapes.single.id;
    c.setSelection(<int>{id});

    c.setShadow(true);
    c.updateShadow(
      color: const VsdxColor(0xFF1565C0),
      offsetXInches: 0.12,
      offsetYInches: -0.08,
      blurInches: 0.1,
      transparency: 0.25,
    );
    final shadow = c.selectedShadow!;
    expect(shadow.enabled, isTrue);
    expect(shadow.color?.value, 0xFF1565C0);
    expect(shadow.offsetXInches, closeTo(0.12, 1e-9));
    expect(shadow.offsetYInches, closeTo(-0.08, 1e-9));
    expect(shadow.blurInches, closeTo(0.1, 1e-9));
    expect(shadow.transparency, closeTo(0.25, 1e-9));

    c.setShadow(false);
    expect(c.selectedHasShadow, isFalse);
    expect(c.currentPage!.findShapeById(id)!.shadow.enabled, isFalse);
  });

  test('glow and reflection setters update selection effects', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 2);
    final id = c.currentPage!.shapes.single.id;
    c.setSelection(<int>{id});

    c.setGlow(true);
    c.updateGlow(
      color: const VsdxColor(0xFFFFC107),
      sizeInches: 0.1,
      transparency: 0.3,
    );
    expect(c.selectedHasGlow, isTrue);
    expect(c.selectedGlow!.color?.value, 0xFFFFC107);
    expect(c.selectedGlow!.sizeInches, closeTo(0.1, 1e-9));
    expect(c.selectedGlow!.transparency, closeTo(0.3, 1e-9));

    c.setReflection(true);
    c.updateReflection(
      sizeInches: 0.4,
      distanceInches: 0.05,
      blurInches: 0.03,
      transparency: 0.5,
    );
    expect(c.selectedHasReflection, isTrue);
    final refl = c.selectedReflection!;
    expect(refl.sizeInches, closeTo(0.4, 1e-9));
    expect(refl.distanceInches, closeTo(0.05, 1e-9));
    expect(refl.blurInches, closeTo(0.03, 1e-9));
    expect(refl.transparency, closeTo(0.5, 1e-9));

    c.setGlow(false);
    c.setReflection(false);
    expect(c.selectedHasGlow, isFalse);
    expect(c.selectedHasReflection, isFalse);
    expect(c.currentPage!.findShapeById(id)!.glow.enabled, isFalse);
    expect(c.currentPage!.findShapeById(id)!.reflection.enabled, isFalse);
  });

  test('compound type, para spacing, and strikethrough', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 2);
    final id = c.currentPage!.shapes.single.id;
    c.setSelection(<int>{id});
    c.setShapeText(id, 'Hello\nWorld');

    c.setCompoundType(1);
    expect(c.currentPage!.findShapeById(id)!.line.compoundType, 1);
    c.setCompoundType(2);
    expect(c.selectedLine?.compoundType, 2);

    c.setSpaceBeforeInches(12 / 72);
    c.setSpaceAfterInches(6 / 72);
    final para = c.selectedParaStyle!;
    expect(para.spaceBeforeInches, closeTo(12 / 72, 1e-9));
    expect(para.spaceAfterInches, closeTo(6 / 72, 1e-9));

    c.setStrikethrough(true);
    expect(c.selectedCharStyle?.strikethrough, isTrue);
    c.toggleStrikethrough();
    expect(c.selectedCharStyle?.strikethrough, isFalse);
  });

  test('soft edges, line spacing, and line jump radius', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 2);
    final id = c.currentPage!.shapes.single.id;
    c.setSelection(<int>{id});
    c.setShapeText(id, 'Hello');

    c.setSoftEdges(true);
    expect(c.selectedHasSoftEdges, isTrue);
    expect(c.selectedSoftEdgesInches, closeTo(0.05, 1e-9));
    c.updateSoftEdges(0.12);
    expect(c.currentPage!.findShapeById(id)!.line.softEdgesInches,
        closeTo(0.12, 1e-9));
    c.setSoftEdges(false);
    expect(c.selectedHasSoftEdges, isFalse);

    c.setLineSpacing(1.5);
    expect(c.selectedParaStyle?.lineSpacing, closeTo(1.5, 1e-9));
    expect(
      c.currentPage!.findShapeById(id)!.richText.runs.first.paraStyle.lineSpacing,
      closeTo(1.5, 1e-9),
    );

    expect(c.showLineJumps, isTrue);
    c.setLineJumpRadius(0.15);
    expect(c.lineJumpRadiusInches, closeTo(0.15, 1e-9));
    c.toggleLineJumps();
    expect(c.showLineJumps, isFalse);
  });

  test('arrow size, fill pattern, and match size', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 2);
    final a = c.currentPage!.shapes.single.id;
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(4, 1, 5, 3);
    final b = c.currentPage!.shapes.last.id;
    c
      ..setTool(EditorTool.line)
      ..createShapeByDrag(1, 4, 4, 4);
    final lineId = c.currentPage!.shapes.last.id;
    c.setSelection(<int>{lineId});

    c.setEndArrow(4);
    c.setEndArrowSize(0.225);
    expect(
      c.currentPage!.findShapeById(lineId)!.line.endArrowSizeInches,
      closeTo(0.225, 1e-9),
    );

    c.setSelection(<int>{a});
    c.setFillPattern(6);
    expect(c.currentPage!.findShapeById(a)!.fill.pattern, 6);
    c.setFillGradient(
      const VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
        ],
      ),
    );
    expect(c.currentPage!.findShapeById(a)!.fill.hasGradient, isTrue);
    c.setFillPattern(4);
    expect(c.currentPage!.findShapeById(a)!.fill.pattern, 4);
    expect(c.currentPage!.findShapeById(a)!.fill.hasGradient, isFalse);

    c.setSelection(<int>{a, b});
    final aw = c.currentPage!.findShapeById(a)!.width;
    final ah = c.currentPage!.findShapeById(a)!.height;
    c.matchSelectionWidth();
    expect(c.currentPage!.findShapeById(b)!.width, closeTo(aw, 1e-9));
    c.matchSelectionHeight();
    expect(c.currentPage!.findShapeById(b)!.height, closeTo(ah, 1e-9));

    // Resize b, then same-size restores both dimensions from a.
    c.setSelection(<int>{b});
    c.setSelectedWidth(1.0);
    c.setSelectedHeight(1.0);
    c.setSelection(<int>{a, b});
    c.matchSelectionSize();
    expect(c.currentPage!.findShapeById(b)!.width, closeTo(aw, 1e-9));
    expect(c.currentPage!.findShapeById(b)!.height, closeTo(ah, 1e-9));
  });

  test('movePage reorders while keeping the active page', () {
    final c = EditorController()..newDocument();
    final first = c.document!.pages.first.id;
    c.addPage();
    c.addPage();
    expect(c.pageCount, 3);
    expect(c.currentPageIndex, 2);
    final third = c.document!.pages[2].id;

    c.movePage(2, 0);
    expect(c.document!.pages.map((p) => p.id).toList(),
        <int>[third, first, c.document!.pages[2].id]);
    expect(c.currentPageIndex, 0);
    expect(c.document!.pages[0].id, third);

    c.movePage(0, 2);
    expect(c.document!.pages.last.id, third);
    expect(c.currentPageIndex, 2);
  });

  test('text tool creates a borderless, selected text box', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.text)
      ..createShapeByDrag(2, 2, 2, 2); // click ⇒ default-sized text box
    final s = c.currentPage!.shapes.single;
    expect(c.selection, <int>{s.id});
    expect(c.tool, EditorTool.select); // reverts after creating
    expect(s.fill.pattern, 0); // no fill
    expect(s.line.pattern, 0); // no border
    // An untyped box is "blank" (the canvas removes it on empty commit).
    expect(c.isBlankTextBox(s.id), isTrue);

    c.setShapeText(s.id, 'Hello');
    expect(c.isBlankTextBox(s.id), isFalse);
  });

  test('createFreehand paints a 1-D polyline stroke; undo removes it', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.freehand)
      ..createFreehand(<Offset2D>[
        const Offset2D(1, 1),
        const Offset2D(1.02, 1.01), // within simplify threshold — dropped
        const Offset2D(2, 1.5),
        const Offset2D(3, 1),
      ]);
    final s = c.currentPage!.shapes.single;
    expect(c.selection, <int>{s.id});
    expect(c.tool, EditorTool.select);
    expect(s.is1D, isTrue);
    expect(s.objType, 1); // ink shape, not a glueable connector (ObjType=2)
    expect(s.beginX, closeTo(1, 1e-9));
    expect(s.endX, closeTo(3, 1e-9));
    // Geometry is MoveTo + at least two LineTos after simplification.
    final cmds = s.geometries.single.commands;
    expect(cmds.first, isA<MoveTo>());
    expect(cmds.whereType<LineTo>().length, greaterThanOrEqualTo(2));

    c.undo();
    expect(c.currentPage!.shapes, isEmpty);
  });

  test('createFreehand ignores a single-point (click) stroke', () {
    final c = EditorController()..newDocument();
    c.createFreehand(<Offset2D>[const Offset2D(1, 1)]);
    expect(c.currentPage!.shapes, isEmpty);
  });

  test('page guides add / move / remove / clear are per-page', () {
    final c = EditorController()..newDocument();
    final page0 = c.currentPage!.id;
    c.addPageGuide(vertical: true, pos: 2.0);
    c.addPageGuide(vertical: false, pos: 3.0);
    expect(c.pageGuides.length, 2);
    expect(c.hasPageGuides, isTrue);

    c.movePageGuide(0, 2.5);
    expect(c.pageGuides[0].pos, closeTo(2.5, 1e-9));

    c.addPage(); // new page starts with no guides
    expect(c.pageGuides, isEmpty);
    c.addPageGuide(vertical: true, pos: 1.0);
    expect(c.pageGuides.length, 1);

    c.selectPage(0);
    expect(c.currentPage!.id, page0);
    expect(c.pageGuides.length, 2);

    c.removePageGuide(1);
    expect(c.pageGuides.length, 1);
    c.clearPageGuides();
    expect(c.hasPageGuides, isFalse);
  });

  test('setShapeText preserves mixed run styles; range bold splits a run', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 2);
    final id = c.currentPage!.shapes.single.id;
    c
      ..selectOnly(id)
      ..setShapeText(id, 'Hello World');
    // Seed two runs via range formatting session.
    c.setTextEditSession(shapeId: id, start: 0, end: 5);
    c.setBold(true);
    final rich = c.currentPage!.findShapeById(id)!.richText;
    expect(rich.runs.length, greaterThanOrEqualTo(2));
    expect(rich.runs.first.charStyle.style.bold, isTrue);
    expect(rich.plainText, 'Hello World');

    // Editing the plain text must not flatten the bold prefix.
    c.setTextEditSession();
    c.setShapeText(id, 'Hello World!');
    final after = c.currentPage!.findShapeById(id)!.richText;
    expect(charStyleAt(after, 0)!.style.bold, isTrue);
    expect(after.plainText, 'Hello World!');
  });

  test('new connectors carry a default end arrowhead', () {
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
    final conn = c.currentPage!.findShapeById(c.selection.single)!;
    expect(conn.is1D, isTrue);
    expect(conn.line.endArrow, isNot(0)); // points at its target
    expect(conn.line.beginArrow, 0);
  });

  test('deleteShapeById removes a single shape', () {
    final c = newDocWithTwoRects();
    final ids = <int>[for (final s in c.currentPage!.shapes) s.id];
    c.deleteShapeById(ids.first);
    expect(c.currentPage!.shapes.map((s) => s.id).toList(), <int>[ids.last]);
    expect(c.selection.contains(ids.first), isFalse);
  });

  test('deleteShapeById clears nested children from selection', () {
    final c = newDocWithTwoRects()..selectAll();
    c.groupSelection();
    final group = c.currentPage!.shapes.single;
    final childIds = <int>[for (final ch in group.children) ch.id];
    c.setSelection(<int>{group.id, ...childIds});
    c.deleteShapeById(group.id);
    expect(c.currentPage!.shapes, isEmpty);
    expect(c.selection, isEmpty);
  });

  test('shape data: set / edit / dedupe, exposed and undoable', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 3);
    final id = c.currentPage!.shapes.single.id;
    c.setSelection(<int>{id});
    expect(c.singleSelectedId, id);
    expect(c.selectedProperties, isEmpty);

    c.setShapeProperties(id, const <VsdxUserProperty>[
      VsdxUserProperty(name: 'Cost', value: '10'),
      VsdxUserProperty(name: 'Owner', value: 'Bob'),
      VsdxUserProperty(name: '', value: 'ignored'), // blank name dropped
      VsdxUserProperty(name: 'Cost', value: 'dup'), // duplicate dropped
    ]);
    expect(c.selectedProperties.map((p) => p.name).toList(), ['Cost', 'Owner']);
    expect(c.selectedProperties.first.value, '10');

    // Editing is a single undo step back to no data.
    c.undo();
    expect(c.selectedProperties, isEmpty);
  });

  test('page setup: size, orientation and background are undoable', () {
    final c = EditorController()..newDocument();
    expect(c.pageSize!.width, closeTo(8.5, 1e-6));
    expect(c.pageBackgroundColor, isNull);

    c.setPageSize(11, 17);
    expect(c.pageSize!.width, closeTo(11, 1e-9));
    expect(c.pageSize!.height, closeTo(17, 1e-9));
    expect(c.pageIsLandscape, isFalse);

    // Landscape swaps width/height, preserving the paper size.
    c.setPageLandscape(true);
    expect(c.pageSize!.width, closeTo(17, 1e-9));
    expect(c.pageSize!.height, closeTo(11, 1e-9));
    expect(c.pageIsLandscape, isTrue);
    // Re-applying the same orientation is a no-op.
    c.setPageLandscape(true);
    expect(c.pageSize!.width, closeTo(17, 1e-9));

    c.setBackgroundColor(const VsdxColor(0xFFEEEEEE));
    expect(c.pageBackgroundColor?.value, 0xFFEEEEEE);

    // Each discrete change is a single undo step.
    c.undo(); // background
    expect(c.pageBackgroundColor, isNull);
    c.undo(); // orientation swap
    expect(c.pageSize!.width, closeTo(11, 1e-9));
    expect(c.pageSize!.height, closeTo(17, 1e-9));
  });

  test('background page: mark, assign BackPage, resolve, undo', () {
    final c = EditorController()..newDocument();
    c.addPage();
    expect(c.pageCount, 2);
    final bgId = c.currentPage!.id; // page added after the first
    c.setPageIsBackground(true);
    expect(c.currentPage!.isBackgroundPage, isTrue);
    expect(c.currentPage!.backgroundPageId, isNull);

    c.selectPage(0);
    final fgId = c.currentPage!.id;
    expect(c.backgroundPageOptions.map((p) => p.id), contains(bgId));
    c.setBackgroundPage(bgId);
    expect(c.currentPage!.id, fgId);
    expect(c.currentPage!.backgroundPageId, bgId);
    expect(c.currentPage!.isBackgroundPage, isFalse);
    expect(c.resolvedBackgroundPage?.id, bgId);
    // Target was auto-marked as a Visio background page.
    expect(
      c.document!.pages.firstWhere((p) => p.id == bgId).isBackgroundPage,
      isTrue,
    );

    // Self-assign is a no-op.
    c.setBackgroundPage(fgId);
    expect(c.currentPage!.backgroundPageId, bgId);

    c.setBackgroundPage(null);
    expect(c.currentPage!.backgroundPageId, isNull);
    expect(c.resolvedBackgroundPage, isNull);

    c.undo(); // clear
    expect(c.currentPage!.backgroundPageId, bgId);
    c.undo(); // assign
    expect(c.currentPage!.backgroundPageId, isNull);
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

  test('lock: locked shapes resist move / rotate / delete; toggle undoable', () {
    final c = newDocWithTwoRects();
    final first = c.currentPage!.shapes.first.id;
    c.setSelection(<int>{first});
    expect(c.selectionLocked, isFalse);

    // Lock the selection (drawio Cmd+L).
    c.toggleLock();
    expect(c.selectionLocked, isTrue);
    expect(c.currentPage!.findShapeById(first)!.locked, isTrue);

    final before = c.currentPage!.findShapeById(first)!;
    // A locked shape doesn't move…
    c.moveSelectionBy(1, 1);
    expect(c.currentPage!.findShapeById(first)!.pinX, closeTo(before.pinX, 1e-9));
    expect(c.currentPage!.findShapeById(first)!.pinY, closeTo(before.pinY, 1e-9));
    // …nor rotate…
    c.rotateSelection90();
    expect(c.currentPage!.findShapeById(first)!.angleRad,
        closeTo(before.angleRad, 1e-9));
    // …nor delete.
    c.deleteSelection();
    expect(c.currentPage!.findShapeById(first), isNotNull);

    // Unlocking is a single undo step back to the locked state.
    c.toggleLock();
    expect(c.selectionLocked, isFalse);
    c.undo();
    expect(c.currentPage!.findShapeById(first)!.locked, isTrue);
  });

  test('lock: a mixed selection still moves its unlocked members', () {
    final c = newDocWithTwoRects();
    final ids = <int>[for (final s in c.currentPage!.shapes) s.id];

    // Lock only the first shape, then select both.
    c.setSelection(<int>{ids.first});
    c.toggleLock();
    c.setSelection(ids.toSet());
    expect(c.selectionLocked, isFalse); // not every shape is locked

    final lockedBefore = c.currentPage!.findShapeById(ids.first)!;
    final freeBefore = c.currentPage!.findShapeById(ids.last)!;
    c.moveSelectionBy(0.5, 0);
    // The locked shape stays put; the free one shifts.
    expect(c.currentPage!.findShapeById(ids.first)!.pinX,
        closeTo(lockedBefore.pinX, 1e-9));
    expect(c.currentPage!.findShapeById(ids.last)!.pinX,
        closeTo(freeBefore.pinX + 0.5, 1e-9));
  });

  test('insertImage adds a picture with embedded bytes; undo removes it', () {
    final c = EditorController()..newDocument();
    final bytes = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 9, 8, 7, 6]);
    expect(c.currentPage!.shapes, isEmpty);

    c.insertImage(bytes, fileExtension: 'png', widthInches: 2, heightInches: 1);

    final shape = c.currentPage!.shapes.single;
    expect(shape.hasImage, isTrue);
    expect(c.selection, <int>{shape.id});
    final part = shape.imagePartName!;
    expect(part, startsWith('/visio/media/image'));
    expect(part, endsWith('.png'));
    // Bytes are embedded on the document so the canvas renders before saving.
    final img = c.document!.images.findByPart(part);
    expect(img, isNotNull);
    expect(img!.bytes, equals(bytes));
    // Honours the requested aspect ratio (2:1) after fitting to the page.
    expect(shape.width / shape.height, closeTo(2.0, 1e-6));

    // A single undo step removes the picture again.
    c.undo();
    expect(c.currentPage!.shapes, isEmpty);
  });

  test('insertImage mints a fresh part name after undo (no cache collision)',
      () {
    final c = EditorController()..newDocument();
    c.insertImage(Uint8List.fromList(<int>[1, 2, 3]),
        fileExtension: 'png', widthInches: 1, heightInches: 1);
    final first = c.currentPage!.shapes.single.imagePartName;
    c.undo();
    c.insertImage(Uint8List.fromList(<int>[4, 5, 6]),
        fileExtension: 'png', widthInches: 1, heightInches: 1);
    final second = c.currentPage!.shapes.single.imagePartName;
    expect(second, isNot(equals(first)));
  });

  test('insertImage at (cx,cy) centres the picture on the drop point', () {
    final c = EditorController()..newDocument();
    c.insertImage(
      Uint8List.fromList(<int>[1, 2, 3]),
      fileExtension: 'png',
      widthInches: 1,
      heightInches: 1,
      cx: 3.0,
      cy: 4.0,
    );
    final s = c.currentPage!.shapes.single;
    // Default grid is 0.25"; snap(3) / snap(4) stay on the grid.
    expect(s.pinX, closeTo(3.0, 1e-9));
    expect(s.pinY, closeTo(4.0, 1e-9));
  });

  test('replaceImage swaps media bytes; keeps pin/size; undo restores', () {
    final c = EditorController()..newDocument();
    final firstBytes = Uint8List.fromList(<int>[1, 2, 3]);
    final secondBytes = Uint8List.fromList(<int>[9, 8, 7]);
    c.insertImage(firstBytes,
        fileExtension: 'png', widthInches: 2, heightInches: 1, cx: 2, cy: 3);
    final shape = c.currentPage!.shapes.single;
    final id = shape.id;
    final oldPart = shape.imagePartName!;
    final w = shape.width;
    final h = shape.height;
    final pinX = shape.pinX;
    final pinY = shape.pinY;

    expect(c.canReplaceSelectedImage, isTrue);
    expect(c.pictureShapeAt(pinX, pinY), id);

    c.replaceImage(id, secondBytes, fileExtension: 'jpg');
    final after = c.currentPage!.findShapeById(id)!;
    expect(after.imagePartName, isNot(equals(oldPart)));
    expect(after.imagePartName, endsWith('.jpg'));
    expect(after.width, closeTo(w, 1e-9));
    expect(after.height, closeTo(h, 1e-9));
    expect(after.pinX, closeTo(pinX, 1e-9));
    expect(after.pinY, closeTo(pinY, 1e-9));
    expect(c.document!.images.findByPart(after.imagePartName!)!.bytes,
        equals(secondBytes));

    c.undo();
    final restored = c.currentPage!.findShapeById(id)!;
    expect(restored.imagePartName, oldPart);
    expect(c.document!.images.findByPart(oldPart)!.bytes, equals(firstBytes));
  });

  test('reconnectEndpoint reglues one end, detaches the other; undoable', () {
    final c = newDocWithTwoRects();
    final rects = c.currentPage!.shapes.toList();
    final a = rects[0], b = rects[1];
    // A third rectangle to reconnect onto.
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(7, 2, 8, 3);
    final third = c.currentPage!.shapes.last;

    c.createConnector(a.pinX, a.pinY, b.pinX, b.pinY,
        beginTarget: a.id, endTarget: b.id);
    final connId = c.currentPage!.shapes.last.id;
    expect(
      c.currentPage!.connects
          .where((e) => e.fromSheetId == connId && e.isEnd)
          .single
          .toSheetId,
      b.id,
    );

    // Reconnect the end onto the third rectangle.
    c.reconnectEndpoint(connId,
        begin: false, targetShapeId: third.id, x: third.pinX, y: third.pinY);
    expect(
      c.currentPage!.connects
          .where((e) => e.fromSheetId == connId && e.isEnd)
          .single
          .toSheetId,
      third.id,
    );

    // Detach the begin end → its connect row is removed.
    c.reconnectEndpoint(connId,
        begin: true, targetShapeId: null, x: 0.5, y: 0.5);
    expect(
      c.currentPage!.connects
          .where((e) => e.fromSheetId == connId && e.isBegin),
      isEmpty,
    );

    // Undo restores the begin glue (single step).
    c.undo();
    expect(
      c.currentPage!.connects
          .where((e) => e.fromSheetId == connId && e.isBegin)
          .length,
      1,
    );
  });

  test('clearSelectedConnectorWaypoints resets the route (undoable)', () {
    final c = newDocWithTwoRects();
    final rects = c.currentPage!.shapes.toList();
    final a = rects[0], b = rects[1];
    c.createConnector(a.pinX, a.pinY, b.pinX, b.pinY,
        beginTarget: a.id, endTarget: b.id);
    final connId = c.currentPage!.shapes.last.id;

    c.setSelection(<int>{connId});
    c.addWaypoint(connId, 0, const Offset2D(3, 3));
    expect(c.currentPage!.findShapeById(connId)!.waypoints, isNotEmpty);
    expect(c.canClearWaypoints, isTrue);

    c.clearSelectedConnectorWaypoints();
    expect(c.currentPage!.findShapeById(connId)!.waypoints, isEmpty);
    expect(c.canClearWaypoints, isFalse);

    // Undo restores the bend point.
    c.undo();
    expect(c.currentPage!.findShapeById(connId)!.waypoints, isNotEmpty);
  });

  test('reconnectEndpoint pins an end to a fixed connection point', () {
    final c = newDocWithTwoRects();
    final rects = c.currentPage!.shapes.toList();
    final a = rects[0], b = rects[1];
    c.createConnector(a.pinX, a.pinY, b.pinX, b.pinY,
        beginTarget: a.id, endTarget: b.id);
    final connId = c.currentPage!.shapes.last.id;

    // Pin the end to b's top connection point (index 0).
    c.reconnectEndpoint(connId,
        begin: false,
        targetShapeId: b.id,
        connectionPointIndex: 0,
        x: b.pinX,
        y: b.pinY);

    final page = c.currentPage!;
    final bAfter = page.findShapeById(b.id)!;
    expect(bAfter.connectionPoints.length, 5); // standard set materialised
    final endConnect =
        page.connects.firstWhere((e) => e.fromSheetId == connId && e.isEnd);
    expect(endConnect.toPart, 100); // fixed point index 0
    // The end sits exactly on b's top-centre connection point.
    final conn = page.findShapeById(connId)!;
    final top = VsdxPage.connectionPointPage(bAfter, 0);
    expect(conn.endX, closeTo(top.x, 1e-6));
    expect(conn.endY, closeTo(top.y, 1e-6));
  });

  test('createConnector without CP index uses whole-shape perimeter glue', () {
    final c = newDocWithTwoRects();
    final rects = c.currentPage!.shapes.toList();
    final a = rects[0], b = rects[1];
    c.createConnector(a.pinX, a.pinY, b.pinX, b.pinY,
        beginTarget: a.id, endTarget: b.id);
    final connId = c.currentPage!.shapes.last.id;
    final page = c.currentPage!;
    final begin = page.connects
        .firstWhere((e) => e.fromSheetId == connId && e.isBegin);
    final end =
        page.connects.firstWhere((e) => e.fromSheetId == connId && e.isEnd);
    // draw.io-style floating glue — not forced onto mid-edge Connection rows.
    expect(begin.toPart, 3);
    expect(end.toPart, 3);
    expect(begin.toCell, 'PinX');
    expect(end.toCell, 'PinX');
    // Endpoints sit on the shape bodies (AABB edges for rectangles).
    final conn = page.findShapeById(connId)!;
    expect(conn.beginX, isNot(closeTo(a.pinX, 1e-3)));
    expect(conn.endX, isNot(closeTo(b.pinX, 1e-3)));
  });

  test('memo line from connector does not stamp arrows onto new boxes', () {
    // Styling a connector then dropping a rectangle must not export EndArrow
    // on the box (万兴图示 would draw stray arrowheads on vertices).
    final c = EditorController()..newDocument();
    addTearDown(c.dispose);
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1, height: 0.6),
        2,
        8);
    final a = c.singleSelectedId!;
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1, height: 0.6),
        5,
        8);
    final b = c.singleSelectedId!;
    c.createConnector(2.5, 8, 4.5, 8, beginTarget: a, endTarget: b);
    c
      ..setEndArrow(10)
      ..setBeginArrow(4)
      ..setLinePattern(2);

    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2),
        3.5,
        6);
    final circle = c.currentPage!.findShapeById(c.singleSelectedId!)!;
    expect(circle.is1D, isFalse);
    expect(circle.line.endArrow, 0);
    expect(circle.line.beginArrow, 0);
    // Dash / weight from the memo stroke still apply (drawio-like).
    expect(circle.line.pattern, 2);
  });

  test('addShapeFromBuilderAt drops a shape centred on the given point', () {
    final c = EditorController()..newDocument();
    c.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
          id: id, pinX: cx, pinY: cy, width: 1, height: 1),
      3,
      4,
    );
    final s = c.currentPage!.shapes.single;
    expect(s.pinX, closeTo(3, 1e-9));
    expect(s.pinY, closeTo(4, 1e-9));
    expect(c.selection, <int>{s.id});
  });

  test('pasteAt centres the clipboard on the target point', () {
    final c = newDocWithTwoRects();
    final first = c.currentPage!.shapes.first;
    c.setSelection(<int>{first.id});
    c.copySelection();
    c.pasteAt(cx: 6, cy: 3);
    final pasted = c.currentPage!.shapes.last;
    expect(pasted.pinX, closeTo(6, 1e-9));
    expect(pasted.pinY, closeTo(3, 1e-9));
    expect(c.selection, <int>{pasted.id});
  });

  test('inserted image survives an export / reopen round-trip', () {
    final c = EditorController()..newDocument();
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9]);
    c.insertImage(bytes, fileExtension: 'png', widthInches: 3, heightInches: 2);
    final id = c.currentPage!.shapes.single.id;

    final reopened = const DocumentParser().parse(c.exportToBytes());
    final s = reopened.pages.first.findShapeById(id)!;
    expect(s.hasImage, isTrue);
    final img = reopened.images.findByPart(s.imagePartName!);
    expect(img, isNotNull);
    expect(img!.bytes, equals(bytes));
  });

  test('select connectors / vertices / next shape', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2)
      ..setTool(EditorTool.line)
      ..createShapeByDrag(1, 1, 4, 2)
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(4, 4, 5, 5);
    expect(c.currentPage!.shapes.length, 3);

    c.selectConnectors();
    expect(c.selection.length, 1);
    expect(c.currentPage!.findShapeById(c.selection.first)!.is1D, isTrue);

    c.selectVertices();
    expect(c.selection.length, 2);
    expect(
      c.selection.every((id) => !c.currentPage!.findShapeById(id)!.is1D),
      isTrue,
    );

    c.selectOnly(c.currentPage!.shapes.first.id);
    final first = c.singleSelectedId!;
    c.selectNextShape();
    expect(c.singleSelectedId, isNot(first));
    c.selectNextShape(reverse: true);
    expect(c.singleSelectedId, first);

    c.setShapeText(first, 'Hi');
    c.toggleBold();
    expect(c.selectedCharStyle?.style.bold, isTrue);
  });

  test('edit connection points: materialise, add, move, remove, undo', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 2);
    final id = c.currentPage!.shapes.single.id;
    c.setSelection(<int>{id});
    expect(c.canEditConnectionPoints, isTrue);
    expect(c.currentPage!.findShapeById(id)!.connectionPoints, isEmpty);

    c.beginEditConnectionPoints();
    expect(c.editingConnectionPoints, isTrue);
    expect(c.currentPage!.findShapeById(id)!.connectionPoints.length, 5);

    c.addConnectionPointAtLocal(0.25, 0.5);
    expect(c.currentPage!.findShapeById(id)!.connectionPoints.length, 6);
    expect(c.selectedConnectionPointIndex, 5);

    c.moveConnectionPointAtLocal(5, 0.5, 0.75);
    final moved = c.currentPage!.findShapeById(id)!.connectionPoints[5];
    expect(moved.x, closeTo(0.5, 1e-9));
    expect(moved.y, closeTo(0.75, 1e-9));

    c.removeSelectedConnectionPoint();
    expect(c.currentPage!.findShapeById(id)!.connectionPoints.length, 5);

    // Delete while editing removes a point, not the shape.
    c.selectConnectionPoint(0);
    c.deleteSelection();
    expect(c.currentPage!.findShapeById(id), isNotNull);
    expect(c.currentPage!.findShapeById(id)!.connectionPoints.length, 4);

    c.endEditConnectionPoints();
    expect(c.editingConnectionPoints, isFalse);
    expect(c.selection, <int>{id});

    c.undo(); // end is not an edit; undo delete point
    expect(c.currentPage!.findShapeById(id)!.connectionPoints.length, 5);
  });

  test('opens the bundled workflow.vsdx example end-to-end', () async {
    // Exercises the app's real open pipeline (bytes → DocumentParser → model)
    // against the real-world sample behind the "workflow" chip on the empty
    // state, so a broken/unparseable example fails here instead of at runtime.
    final bytes = File('assets/examples/workflow.vsdx').readAsBytesSync();
    final c = EditorController();
    await c.openBytes(bytes, name: 'workflow.vsdx');

    expect(c.error, isNull);
    expect(c.hasDocument, isTrue);
    expect(c.fileName, 'workflow.vsdx');
    expect(c.document!.pages, isNotEmpty);
    expect(c.document!.pages.first.shapes, isNotEmpty);
  });

  test('duplicate connector alone clears dangling XFTRIGGER', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 3, 2, 4);
    final a = c.currentPage!.shapes.last.id;
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(5, 3, 6, 4);
    final b = c.currentPage!.shapes.last.id;
    c.createConnector(1.5, 3.5, 5.5, 3.5, beginTarget: a, endTarget: b);
    final conn = c.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    expect(
      c.currentPage!.findShapeById(conn)!.formulas['BegTrigger'],
      contains('Sheet.$a!'),
    );
    c
      ..setSelection(<int>{conn})
      ..duplicateSelection();
    final copy = c.currentPage!.shapes.lastWhere((s) => s.is1D && s.id != conn);
    expect(copy.formulas.containsKey('BegTrigger'), isFalse);
    expect(copy.formulas.containsKey('EndTrigger'), isFalse);
    expect(
      c.currentPage!.connects.any((e) => e.fromSheetId == copy.id),
      isFalse,
    );
  });

  test('resizeTableColumn reroutes glued connectors with the cell', () {
    final c = EditorController()..newDocument();
    c.addShapeFromBuilderAt(
      (id, cx, cy) => TableOps.assembleTable(
        tableId: id,
        pinX: cx,
        pinY: cy,
        width: 4,
        height: 2,
        rows: 2,
        cols: 2,
      ),
      3,
      4,
    );
    final tableId = c.selection.single;
    final cells = TableOps.cellsOf(c.currentPage!.findShapeById(tableId)!);
    // Right-hand cell: its centre shifts when the shared divider moves.
    final cell = cells.firstWhere(
      (x) => TableOps.cellRow(x) == 0 && TableOps.cellCol(x) == 1,
    );
    final pinBefore = c.currentPage!.shapePinPage(cell.id);
    // Box above the cell so perimeter glue sits on the top edge near the
    // cell centre (outer vertical edges stay fixed when fractions redistribute).
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(
        pinBefore.x - 0.4,
        pinBefore.y + 1.5,
        pinBefore.x + 0.4,
        pinBefore.y + 2.2,
      );
    final box =
        c.currentPage!.shapes.lastWhere((s) => !s.is1D && s.id != tableId).id;
    c.createConnector(
      pinBefore.x,
      pinBefore.y,
      pinBefore.x,
      pinBefore.y + 1.8,
      beginTarget: cell.id,
      endTarget: box,
    );
    final conn = c.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    final beginBefore = c.currentPage!.findShapeById(conn)!.beginX!;
    c.resizeTableColumn(tableId, 0, 0.5);
    final pinAfter = c.currentPage!.shapePinPage(cell.id);
    final beginAfter = c.currentPage!.findShapeById(conn)!.beginX!;
    // Growing col0 shrinks col1 toward the right edge → centre moves right.
    expect(pinAfter.x, greaterThan(pinBefore.x + 0.1));
    expect(beginAfter, isNot(closeTo(beginBefore, 0.05)));
    expect(beginAfter, closeTo(pinAfter.x, 0.35));
  });

  test('matchSelectionSize scales group children', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2)
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(2.2, 1, 3.2, 2);
    c.selectAll();
    c.groupSelection();
    final gid = c.selection.single;
    final group0 = c.currentPage!.findShapeById(gid)!;
    final childW0 = group0.children.first.width;
    final groupW0 = group0.width;
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(5, 1, 9, 5); // 4×4 reference
    final ref = c.currentPage!.shapes.lastWhere((s) => s.id != gid).id;
    c.setSelection(<int>{ref, gid});
    c.matchSelectionSize();
    final group = c.currentPage!.findShapeById(gid)!;
    expect(group.width, closeTo(4, 1e-6));
    expect(group.height, closeTo(4, 1e-6));
    expect(
      group.children.first.width,
      closeTo(childW0 * (4 / groupW0), 0.1),
    );
  });

  test('alignLeft includes freehand ink AABB with 2-D shapes', () {
    final c = EditorController()..newDocument();
    c.createFreehand(<Offset2D>[
      const Offset2D(3, 1),
      const Offset2D(4, 1.5),
      const Offset2D(5, 1),
    ]);
    final inkId = c.selection.single;
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2);
    final boxId = c.selection.single;
    c.setSelection(<int>{inkId, boxId});
    c.alignLeft();
    final ink = c.currentPage!.findShapeById(inkId)!;
    final box = c.currentPage!.findShapeById(boxId)!;
    final inkLeft = c.currentPage!.shapePageAabb(inkId)!.left;
    final boxLeft = box.pinX - box.width / 2;
    expect(inkLeft, closeTo(boxLeft, 0.05));
    expect(ink.isInk, isTrue);
  });

  test('selectVertices includes freehand ink', () {
    final c = EditorController()..newDocument();
    c.createFreehand(<Offset2D>[
      const Offset2D(1, 1),
      const Offset2D(2, 1.5),
      const Offset2D(3, 1),
    ]);
    final inkId = c.selection.single;
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(4, 1, 5, 2);
    final boxId = c.selection.single;
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(6, 1, 7, 2);
    final box2 = c.selection.single;
    c.createConnector(4.5, 1.5, 6.5, 1.5, beginTarget: boxId, endTarget: box2);
    c.selectVertices();
    expect(c.selection, containsAll(<int>[inkId, boxId, box2]));
    expect(
      c.selection.any(
        (id) => c.currentPage!.findShapeById(id)!.isGlueableConnector,
      ),
      isFalse,
    );
  });

  test('freehand ink is not treated as a glueable connector', () {
    final c = EditorController()..newDocument();
    c.createFreehand(<Offset2D>[
      const Offset2D(1, 1),
      const Offset2D(2, 1.5),
      const Offset2D(3, 1),
    ]);
    final ink = c.currentPage!.shapes.single;
    expect(ink.isInk, isTrue);
    expect(ink.isGlueableConnector, isFalse);
    expect(c.hasConnectorSelected, isFalse);
    final geomBefore = ink.geometries.first.commands.length;
    c.setConnectorRouteStyle(ConnectorRouteStyle.straight);
    expect(
      c.currentPage!.findShapeById(ink.id)!.geometries.first.commands.length,
      geomBefore,
    );
    c.rotateSelection90();
    final after = c.currentPage!.findShapeById(ink.id)!;
    // Ink uses AABB-local Angle (not Begin/End bake).
    expect(after.angleRad.abs(), greaterThan(1e-6));
    expect(after.objType, 1);
    // Begin/End follow the transformed stroke tips (CW −90° about pin).
    final begin = VsdxPage.localToPage(
      after,
      Offset2D(
        (after.geometries.first.commands.first as MoveTo).x,
        (after.geometries.first.commands.first as MoveTo).y,
      ),
    );
    expect(after.beginX, closeTo(begin.x, 1e-6));
    expect(after.beginY, closeTo(begin.y, 1e-6));
  });

  test('rotateSelection90 compensates flipY under a parent group', () {
    final c = EditorController()..newDocument();
    final parent = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    ).copyWith(shapeKind: VsdxShapeKind.group);
    final child = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 2,
      pinY: 1.5,
      width: 1,
      height: 0.6,
    ).copyWith(flipY: true);
    c.updateCurrentPage(
      (p) => p.copyWith(
        shapes: <VsdxShape>[
          parent.copyWith(children: <VsdxShape>[child]),
        ],
      ),
    );
    final before = c.currentPage!.shapePageAngle(2);
    c.setSelection(<int>{2});
    c.rotateSelection90(clockwise: false); // +90° page
    final after = c.currentPage!.shapePageAngle(2);
    var delta = after - before;
    while (delta > math.pi) {
      delta -= 2 * math.pi;
    }
    while (delta < -math.pi) {
      delta += 2 * math.pi;
    }
    expect(delta, closeTo(math.pi / 2, 1e-6));
  });

  test('resize pool scales content inside lanes', () {
    final c = EditorController()..newDocument();
    c.addShapeFromBuilderAt(
      (id, cx, cy) => SwimlaneOps.assemblePool(
        poolId: id,
        pinX: cx,
        pinY: cy,
        width: 4,
        height: 3,
        laneCount: 2,
      ),
      4,
      4,
    );
    final poolId = c.selection.single;
    final lane = SwimlaneOps.lanesOf(c.currentPage!.findShapeById(poolId)!).first;
    final nested = VsdxShapeFactory.rectangle(
      id: c.currentPage!.nextFreeShapeId(),
      pinX: lane.width / 2,
      pinY: lane.height / 2,
      width: 0.8,
      height: 0.4,
    );
    c.updateCurrentPage((p) {
      final host = p.findShapeById(poolId)!;
      final lanes = SwimlaneOps.lanesOf(host);
      final first = lanes.first.copyWith(children: <VsdxShape>[nested]);
      return p.updateShapeById(
        poolId,
        (_) => host.copyWith(
          children: <VsdxShape>[
            first,
            ...lanes.skip(1),
            ...SwimlaneOps.nonLaneChildren(host),
          ],
        ),
      );
    });
    final pinBefore = c.currentPage!.shapePinPage(nested.id);
    final pool = c.currentPage!.findShapeById(poolId)!;
    c.resizeShape(
      poolId,
      pinX: pool.pinX,
      pinY: pool.pinY,
      width: pool.width,
      height: pool.height * 2,
    );
    final pinAfter = c.currentPage!.shapePinPage(nested.id);
    // Doubling pool height doubles lane height; content centre moves with it.
    expect(pinAfter.y, isNot(closeTo(pinBefore.y, 0.05)));
    final laneAfter =
        SwimlaneOps.lanesOf(c.currentPage!.findShapeById(poolId)!).first;
    expect(
      c.currentPage!.findShapeById(nested.id)!.height,
      closeTo(0.4 * (laneAfter.height / (3 / 2)), 0.15),
    );
  });

  test('resize table frame reflows cells to fill the new box', () {
    final c = EditorController()..newDocument();
    c.addShapeFromBuilderAt(
      (id, cx, cy) => TableOps.assembleTable(
        tableId: id,
        pinX: cx,
        pinY: cy,
        width: 4,
        height: 2,
        rows: 2,
        cols: 2,
      ),
      3,
      4,
    );
    final tableId = c.selection.single;
    final cell0 = TableOps.cellsOf(c.currentPage!.findShapeById(tableId)!).first;
    final w0 = cell0.width;
    c.resizeShape(
      tableId,
      pinX: 3,
      pinY: 4,
      width: 6,
      height: 2,
    );
    final cell1 = TableOps.cellsOf(c.currentPage!.findShapeById(tableId)!).first;
    expect(cell1.width, closeTo(w0 * 1.5, 0.05));
  });

  test('group Same Size scales freehand ink without collapsing to a line', () {
    final c = EditorController()..newDocument();
    c.createFreehand(<Offset2D>[
      const Offset2D(1, 1),
      const Offset2D(1.5, 1.4),
      const Offset2D(2, 1.1),
      const Offset2D(2.5, 1.5),
    ]);
    final inkId = c.selection.single;
    final cmds0 =
        c.currentPage!.findShapeById(inkId)!.geometries.first.commands.length;
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(4, 1, 5, 2);
    c.setSelection(<int>{inkId, c.currentPage!.shapes.last.id});
    c.groupSelection();
    final gid = c.selection.single;
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(6, 1, 10, 5); // 4×4 ref
    final ref = c.currentPage!.shapes.lastWhere((s) => s.id != gid).id;
    c.setSelection(<int>{ref, gid});
    c.matchSelectionSize();
    final ink = c.currentPage!.findShapeById(inkId)!;
    expect(ink.isInk, isTrue);
    expect(ink.geometries.first.commands.length, cmds0);
    expect(ink.objType, 1);
  });
}
