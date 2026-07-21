import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/canvas_camera.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/editor/page_canvas.dart';
import 'package:vsdx/vsdx.dart';

/// The white page "sheet" is the only DecoratedBox that carries a drop shadow.
final Finder _pageSheet = find.byWidgetPredicate(
  (w) =>
      w is DecoratedBox &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).boxShadow != null,
);

Future<EditorController> _pumpCanvas(
  WidgetTester tester,
  Size viewport, {
  void Function(EditorController controller)? setUp,
  CanvasCamera? camera,
}) async {
  final c = EditorController()..newDocument(); // blank 8.5 x 11 portrait page
  addTearDown(c.dispose);
  setUp?.call(c);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: viewport.width,
            height: viewport.height,
            child: PageCanvas(controller: c, camera: camera),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The fit-to-window runs in a post-frame callback, then setState re-lays out.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return c;
}

Offset _pagePoint(
  Offset canvasOrigin,
  CanvasCamera camera,
  VsdxPage page,
  double x,
  double y,
) {
  final content = Offset(
    x / page.widthInches * camera.content.width,
    (page.heightInches - y) / page.heightInches * camera.content.height,
  );
  return canvasOrigin + camera.offset + content * camera.scale;
}

int _addRect(EditorController controller) {
  controller.addShapeFromBuilderAt(
    (id, cx, cy) => VsdxShapeFactory.rectangle(
      id: id,
      pinX: cx,
      pinY: cy,
      width: 2,
      height: 1,
    ),
    3,
    5,
  );
  if (controller.snapToGrid) controller.toggleSnap();
  return controller.singleSelectedId!;
}

void main() {
  // Regression: the page sheet used to inherit the Stack's viewport-capped
  // (loose) constraints, so it was clamped to the canvas area before the view
  // transform scaled it. That squashed the page — visibly wrong in any window
  // where the page is larger than the canvas (i.e. most non-maximized windows).
  const pageAspect = 8.5 / 11.0;

  testWidgets('page keeps its aspect ratio when larger than the viewport',
      (tester) async {
    await _pumpCanvas(tester, const Size(320, 240));
    expect(_pageSheet, findsOneWidget);
    final r = tester.getRect(_pageSheet);
    expect(r.width / r.height, closeTo(pageAspect, 0.01));
    // And the fitted page must actually be smaller than the viewport it fits in.
    expect(r.width, lessThanOrEqualTo(320));
    expect(r.height, lessThanOrEqualTo(240));
  });

  testWidgets('page keeps its aspect ratio in a large viewport', (tester) async {
    await _pumpCanvas(tester, const Size(1200, 900));
    expect(_pageSheet, findsOneWidget);
    final r = tester.getRect(_pageSheet);
    expect(r.width / r.height, closeTo(pageAspect, 0.01));
  });

  testWidgets('shape drag commits one undoable page-space move', (tester) async {
    late int id;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) => id = _addRect(c),
      camera: camera,
    );
    final page = controller.currentPage!;
    final before = page.findShapeById(id)!;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final start = _pagePoint(origin, camera, page, before.pinX, before.pinY);
    const delta = Offset(36, -24);

    await tester.dragFrom(start, delta);
    await tester.pumpAndSettle();

    final moved = controller.currentPage!.findShapeById(id)!;
    expect(
      moved.pinX - before.pinX,
      closeTo(
        delta.dx /
            (camera.scale * camera.content.width / page.widthInches),
        0.03,
      ),
    );
    expect(
      moved.pinY - before.pinY,
      closeTo(
        -delta.dy /
            (camera.scale * camera.content.height / page.heightInches),
        0.03,
      ),
    );
    controller.undo();
    expect(controller.currentPage!.findShapeById(id)!.pinX, before.pinX);
    expect(controller.currentPage!.findShapeById(id)!.pinY, before.pinY);
    controller.redo();
    expect(controller.currentPage!.findShapeById(id)!.pinX, moved.pinX);
    expect(controller.currentPage!.findShapeById(id)!.pinY, moved.pinY);
  });

  testWidgets('right resize handle changes geometry and undo restores it',
      (tester) async {
    late int id;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) => id = _addRect(c),
      camera: camera,
    );
    final page = controller.currentPage!;
    final before = page.findShapeById(id)!;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final handle = _pagePoint(
      origin,
      camera,
      page,
      before.pinX + before.width / 2,
      before.pinY,
    );

    await tester.dragFrom(handle, const Offset(40, 0));
    await tester.pumpAndSettle();

    final resized = controller.currentPage!.findShapeById(id)!;
    expect(resized.width, greaterThan(before.width + 0.1));
    expect(resized.pinX, greaterThan(before.pinX));
    controller.undo();
    final restored = controller.currentPage!.findShapeById(id)!;
    expect(restored.width, closeTo(before.width, 1e-9));
    expect(restored.pinX, closeTo(before.pinX, 1e-9));
  });

  testWidgets('rotation handle tracks pointer heading and is undoable',
      (tester) async {
    late int id;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) => id = _addRect(c),
      camera: camera,
    );
    final page = controller.currentPage!;
    final before = page.findShapeById(id)!;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final centre = _pagePoint(
      origin,
      camera,
      page,
      before.pinX,
      before.pinY,
    );
    final top = _pagePoint(
      origin,
      camera,
      page,
      before.pinX,
      before.pinY + before.height / 2,
    );
    final knob = top + const Offset(0, -22);

    await tester.dragFrom(knob, centre + const Offset(60, 0) - knob);
    await tester.pumpAndSettle();

    final rotated = controller.currentPage!.findShapeById(id)!;
    expect(rotated.angleRad, closeTo(-math.pi / 2, 0.05));
    controller.undo();
    expect(controller.currentPage!.findShapeById(id)!.angleRad,
        closeTo(before.angleRad, 1e-9));
  });

  testWidgets('Escape cancels an in-progress shape drag', (tester) async {
    late int id;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) => id = _addRect(c),
      camera: camera,
    );
    final page = controller.currentPage!;
    final before = page.findShapeById(id)!;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final start = _pagePoint(origin, camera, page, before.pinX, before.pinY);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(48, 0));
    await tester.pump();
    expect(controller.currentPage!.findShapeById(id)!.pinX, isNot(before.pinX));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final restored = controller.currentPage!.findShapeById(id)!;
    expect(restored.pinX, closeTo(before.pinX, 1e-9));
    expect(restored.pinY, closeTo(before.pinY, 1e-9));
  });

  testWidgets('marquee drag selects shapes whose bounds intersect',
      (tester) async {
    late int a;
    late int b;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) {
        if (c.snapToGrid) c.toggleSnap();
        c.addShapeFromBuilderAt(
          (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 1.5,
            height: 1,
          ),
          2,
          8,
        );
        a = c.singleSelectedId!;
        c.addShapeFromBuilderAt(
          (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 1.5,
            height: 1,
          ),
          5,
          8,
        );
        b = c.singleSelectedId!;
        c.clearSelection();
      },
      camera: camera,
    );
    expect(controller.selection, isEmpty);
    final page = controller.currentPage!;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    // Empty page space above both shapes, then drag a box covering both.
    final start = _pagePoint(origin, camera, page, 0.5, 9.5);
    final end = _pagePoint(origin, camera, page, 6.5, 6.5);

    final gesture = await tester.startGesture(start);
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.selection, unorderedEquals(<int>[a, b]));
  });

  testWidgets('connector endpoint drag detaches once and undo restores glue',
      (tester) async {
    late int target;
    late int connector;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) {
        if (c.snapToGrid) c.toggleSnap();
        c
          ..setTool(EditorTool.rectangle)
          ..createShapeByDrag(1, 4, 3, 6);
        final source = c.singleSelectedId!;
        c
          ..setTool(EditorTool.rectangle)
          ..createShapeByDrag(5, 4, 7, 6);
        target = c.singleSelectedId!;
        c.createConnector(
          2,
          5,
          6,
          5,
          beginTarget: source,
          endTarget: target,
        );
        connector = c.singleSelectedId!;
      },
      camera: camera,
    );
    var page = controller.currentPage!;
    final shape = page.findShapeById(connector)!;
    final route = VsdxPage.connectorRoute(shape);
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final start = _pagePoint(
      origin,
      camera,
      page,
      route.last.x,
      route.last.y,
    );
    final destination = _pagePoint(origin, camera, page, 7.5, 2.5);

    await tester.dragFrom(start, destination - start);
    await tester.pumpAndSettle();

    page = controller.currentPage!;
    expect(
      page.connects.where((c) => c.fromSheetId == connector && c.isEnd),
      isEmpty,
    );
    final moved = VsdxPage.connectorRoute(page.findShapeById(connector)!).last;
    expect(moved.x, closeTo(7.5, 0.05));
    expect(moved.y, closeTo(2.5, 0.05));

    controller.undo();
    page = controller.currentPage!;
    expect(
      page.connects
          .singleWhere((c) => c.fromSheetId == connector && c.isEnd)
          .toSheetId,
      target,
    );
  });

  testWidgets('connector segment midpoint drag creates one undoable waypoint',
      (tester) async {
    late int connector;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) {
        if (c.snapToGrid) c.toggleSnap();
        c.createConnector(2, 5, 6, 5);
        connector = c.singleSelectedId!;
      },
      camera: camera,
    );
    final page = controller.currentPage!;
    final route =
        VsdxPage.connectorRoute(page.findShapeById(connector)!);
    expect(route, hasLength(2));
    final midpoint = Offset2D(
      (route.first.x + route.last.x) / 2,
      (route.first.y + route.last.y) / 2,
    );
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final start = _pagePoint(
      origin,
      camera,
      page,
      midpoint.x,
      midpoint.y,
    );
    final destination =
        _pagePoint(origin, camera, page, midpoint.x, midpoint.y + 1);

    await tester.dragFrom(start, destination - start);
    await tester.pumpAndSettle();

    final waypoints = controller.connectorWaypoints(connector);
    expect(waypoints, hasLength(1));
    expect(waypoints.single.x, closeTo(midpoint.x, 0.05));
    expect(waypoints.single.y, closeTo(midpoint.y + 1, 0.05));
    controller.undo();
    expect(controller.connectorWaypoints(connector), isEmpty);
  });
}
