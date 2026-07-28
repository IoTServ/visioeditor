import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/canvas_camera.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/editor/page_canvas.dart';
import 'package:visioeditor/editor/quick_add_picker.dart';
import 'package:visioeditor/editor/stencils.dart';
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

Future<void> _tapCanvasAt(WidgetTester tester, Offset point) async {
  await tester.tapAt(point);
  // PageCanvas also recognises double taps, so the single-tap callback waits
  // for the double-tap window to expire.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Future<void> _doubleTapCanvasAt(WidgetTester tester, Offset point) async {
  await tester.tapAt(point);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(point);
  await tester.pumpAndSettle();
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

  testWidgets('double-click blank canvas inserts from the quick shape picker',
      (tester) async {
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      camera: camera,
    );
    final page = controller.currentPage!;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final point = _pagePoint(origin, camera, page, 2.2, 7.3);

    await _doubleTapCanvasAt(tester, point);
    expect(find.byType(QuickAddPicker), findsOneWidget);
    expect(find.byIcon(Icons.copy_outlined), findsNothing);

    final pickerCell = find.descendant(
      of: find.byType(QuickAddPicker),
      matching: find.byType(InkWell),
    );
    await tester.tap(pickerCell.first);
    await tester.pumpAndSettle();

    expect(find.byType(QuickAddPicker), findsNothing);
    expect(controller.currentPage!.shapes, hasLength(1));
    final inserted = controller.singleSelected!;
    expect(inserted.pinX, closeTo(controller.snap(2.2), 0.01));
    expect(inserted.pinY, closeTo(controller.snap(7.3), 0.01));
  });

  testWidgets('stencil drop replaces shape; Shift-drop overlaps it',
      (tester) async {
    final controller = EditorController()..newDocument();
    final camera = CanvasCamera();
    addTearDown(controller.dispose);
    addTearDown(camera.dispose);
    controller.addShapeFromBuilderAt(
      (id, x, y) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: x,
        pinY: y,
        width: 2,
        height: 1,
      ),
      4.25,
      5.5,
    );
    final target = controller.singleSelectedId!;
    final stencil = Stencil(
      'Ellipse',
      (id, x, y) => VsdxShapeFactory.ellipse(
        id: id,
        pinX: x,
        pinY: y,
        width: 1.5,
        height: 1,
      ),
    );
    const dragKey = Key('test-stencil-drag');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 800,
            child: Stack(
              children: [
                Positioned.fill(
                  child: PageCanvas(controller: controller, camera: camera),
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: Draggable<Stencil>(
                    key: dragKey,
                    data: stencil,
                    dragAnchorStrategy: pointerDragAnchorStrategy,
                    feedback: const ColoredBox(
                      color: Colors.blue,
                      child: SizedBox(width: 40, height: 40),
                    ),
                    child: const ColoredBox(
                      color: Colors.blue,
                      child: SizedBox(width: 40, height: 40),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));

    final destination = _pagePoint(
      tester.getTopLeft(find.byType(PageCanvas)),
      camera,
      controller.currentPage!,
      4.25,
      5.5,
    );
    await tester.dragFrom(
      tester.getCenter(find.byKey(dragKey)),
      destination - tester.getCenter(find.byKey(dragKey)),
    );
    await tester.pumpAndSettle();

    expect(controller.currentPage!.shapes, hasLength(1));
    expect(
      controller.currentPage!
          .findShapeById(target)!
          .geometries
          .first
          .commands
          .whereType<EllipseCmd>(),
      isNotEmpty,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.dragFrom(
      tester.getCenter(find.byKey(dragKey)),
      destination - tester.getCenter(find.byKey(dragKey)),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(controller.currentPage!.shapes, hasLength(2));
    expect(controller.currentPage!.shapes.every((shape) => !shape.is1D), isTrue);
  });

  testWidgets('typing replaces a selected label and Enter commits it',
      (tester) async {
    late int shapeId;
    final controller = await _pumpCanvas(
      tester,
      const Size(900, 700),
      setUp: (c) {
        shapeId = _addRect(c);
        c.setShapeText(shapeId, 'Old label');
      },
    );
    final inlineEditor = find.descendant(
      of: find.byType(PageCanvas),
      matching: find.byType(TextField),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyN, character: 'N');
    await tester.pumpAndSettle();

    expect(inlineEditor, findsOneWidget);
    expect(tester.widget<TextField>(inlineEditor).controller!.text, 'N');
    await tester.enterText(inlineEditor, 'New label');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(inlineEditor, findsOneWidget);
    expect(
      tester.widget<TextField>(inlineEditor).controller!.text,
      'New label\n',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(inlineEditor, findsNothing);
    expect(
      controller.currentPage!.findShapeById(shapeId)!.richText.plainText,
      'New label\n',
    );
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

  testWidgets('Alt drag bypasses page-centre, guide and grid snapping', (
    tester,
  ) async {
    late int id;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) {
        c.addShapeFromBuilderAt(
          (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 2,
            height: 1,
          ),
          2,
          5.5,
        );
        id = c.singleSelectedId!;
      },
      camera: camera,
    );
    final page = controller.currentPage!;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final before = page.findShapeById(id)!;
    final start = _pagePoint(origin, camera, page, before.pinX, before.pinY);
    final destination = _pagePoint(origin, camera, page, 4.22, before.pinY);

    await tester.dragFrom(start, destination - start);
    await tester.pumpAndSettle();
    expect(
      controller.currentPage!.findShapeById(id)!.pinX,
      closeTo(page.widthInches / 2, 0.01),
    );

    controller.undo();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.dragFrom(start, destination - start);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    final precise = controller.currentPage!.findShapeById(id)!;
    expect(precise.pinX, closeTo(4.22, 0.015));
    expect(controller.currentPage!.shapes, hasLength(1));
  });

  testWidgets('Alt+Shift blank-canvas drag moves the selection remotely', (
    tester,
  ) async {
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
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final before = page.findShapeById(id)!;
    final start = _pagePoint(origin, camera, page, 7.5, 8.5);
    const delta = Offset(48, -30);
    final dx = delta.dx /
        (camera.scale * camera.content.width / page.widthInches);
    final dy = -delta.dy /
        (camera.scale * camera.content.height / page.heightInches);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.dragFrom(start, delta);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    final moved = controller.currentPage!.findShapeById(id)!;
    expect(moved.pinX, closeTo(before.pinX + dx, 0.03));
    expect(moved.pinY, closeTo(before.pinY + dy, 0.03));

    controller.undo();
    expect(controller.currentPage!.findShapeById(id)!.pinX, before.pinX);
    expect(controller.currentPage!.findShapeById(id)!.pinY, before.pinY);
  });

  testWidgets('Alt+Ctrl+Shift blank-canvas drag displaces an area', (
    tester,
  ) async {
    final ids = <String, int>{};
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) {
        if (c.snapToGrid) c.toggleSnap();
        for (final entry in <String, Offset>{
          'fixed': const Offset(2, 8),
          'right': const Offset(6.5, 8),
          'below': const Offset(2, 3),
          'both': const Offset(6.5, 3),
        }.entries) {
          c.addShapeFromBuilderAt(
            (id, cx, cy) => VsdxShapeFactory.rectangle(
              id: id,
              pinX: cx,
              pinY: cy,
              width: 1,
              height: 0.6,
            ),
            entry.value.dx,
            entry.value.dy,
          );
          ids[entry.key] = c.singleSelectedId!;
        }
        c.clearSelection();
      },
      camera: camera,
    );
    final page = controller.currentPage!;
    final before = <String, VsdxShape>{
      for (final entry in ids.entries)
        entry.key: page.findShapeById(entry.value)!,
    };
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final start = _pagePoint(origin, camera, page, 4.25, 5.5);
    const delta = Offset(60, 42);
    final dx = delta.dx /
        (camera.scale * camera.content.width / page.widthInches);
    final dy = -delta.dy /
        (camera.scale * camera.content.height / page.heightInches);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.dragFrom(start, delta);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    VsdxShape after(String name) =>
        controller.currentPage!.findShapeById(ids[name]!)!;
    expect(after('fixed').pinX, before['fixed']!.pinX);
    expect(after('fixed').pinY, before['fixed']!.pinY);
    expect(after('right').pinX, closeTo(before['right']!.pinX + dx, 0.03));
    expect(after('right').pinY, before['right']!.pinY);
    expect(after('below').pinX, before['below']!.pinX);
    expect(after('below').pinY, closeTo(before['below']!.pinY + dy, 0.03));
    expect(after('both').pinX, closeTo(before['both']!.pinX + dx, 0.03));
    expect(after('both').pinY, closeTo(before['both']!.pinY + dy, 0.03));

    controller.undo();
    for (final entry in before.entries) {
      expect(after(entry.key).pinX, entry.value.pinX);
      expect(after(entry.key).pinY, entry.value.pinY);
    }
  });

  testWidgets('Ctrl drag clones instead of using Alt duplication', (
    tester,
  ) async {
    late int originalId;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) => originalId = _addRect(c),
      camera: camera,
    );
    final page = controller.currentPage!;
    final original = page.findShapeById(originalId)!;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final start = _pagePoint(
      origin,
      camera,
      page,
      original.pinX,
      original.pinY,
    );
    final destination = _pagePoint(
      origin,
      camera,
      page,
      original.pinX + 1,
      original.pinY,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.dragFrom(start, destination - start);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    final next = controller.currentPage!;
    expect(next.shapes, hasLength(2));
    expect(next.findShapeById(originalId)!.pinX, original.pinX);
    expect(controller.singleSelectedId, isNot(originalId));
  });

  testWidgets('Alt click cycles down through overlapping shapes',
      (tester) async {
    late int bottom;
    late int top;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) {
        bottom = _addRect(c);
        top = _addRect(c);
        c.clearSelection();
      },
      camera: camera,
    );
    final page = controller.currentPage!;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final point = _pagePoint(origin, camera, page, 3, 5);

    await _tapCanvasAt(tester, point);
    expect(controller.singleSelectedId, top);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await _tapCanvasAt(tester, point);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(controller.singleSelectedId, bottom);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await _tapCanvasAt(tester, point);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(controller.singleSelectedId, top);
  });

  testWidgets('Ctrl click toggles shapes in a multi-selection', (tester) async {
    late int a;
    late int b;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) {
        a = _addRect(c);
        c.addShapeFromBuilderAt(
          (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 2,
            height: 1,
          ),
          6,
          5,
        );
        b = c.singleSelectedId!;
        c.clearSelection();
      },
      camera: camera,
    );
    final page = controller.currentPage!;
    final origin = tester.getTopLeft(find.byType(PageCanvas));

    await _tapCanvasAt(tester, _pagePoint(origin, camera, page, 3, 5));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await _tapCanvasAt(tester, _pagePoint(origin, camera, page, 6, 5));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(controller.selection, unorderedEquals(<int>[a, b]));
  });

  testWidgets('Space drag pans even when it starts on a selected shape',
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
    final beforeShape = page.findShapeById(id)!;
    final beforeOffset = camera.offset;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final start =
        _pagePoint(origin, camera, page, beforeShape.pinX, beforeShape.pinY);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.dragFrom(start, const Offset(48, 24));
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);

    final afterShape = controller.currentPage!.findShapeById(id)!;
    expect(afterShape.pinX, beforeShape.pinX);
    expect(afterShape.pinY, beforeShape.pinY);
    expect(camera.offset, isNot(beforeOffset));
  });

  testWidgets('Alt wheel zooms and Shift wheel scrolls horizontally',
      (tester) async {
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    await _pumpCanvas(
      tester,
      const Size(1000, 800),
      camera: camera,
    );
    final point = tester.getCenter(find.byType(PageCanvas));
    final beforeScale = camera.scale;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: point,
        scrollDelta: const Offset(0, -20),
      ),
    );
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(camera.scale, greaterThan(beforeScale));

    final beforeOffset = camera.offset;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: point,
        scrollDelta: const Offset(0, 20),
      ),
    );
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(camera.offset.dx, isNot(beforeOffset.dx));
    expect(camera.offset.dy, closeTo(beforeOffset.dy, 1e-9));
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

  testWidgets('marquee drag selects fully enclosed shapes',
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

  testWidgets('Alt marquee includes a partially intersecting shape',
      (tester) async {
    late int id;
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
            width: 2,
            height: 1,
          ),
          3,
          8,
        );
        id = c.singleSelectedId!;
        c.clearSelection();
      },
      camera: camera,
    );
    final page = controller.currentPage!;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final start = _pagePoint(origin, camera, page, 0.5, 9.5);
    final end = _pagePoint(origin, camera, page, 2.5, 6.5);

    await tester.dragFrom(start, end - start);
    await tester.pumpAndSettle();
    expect(controller.selection, isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.dragFrom(start, end - start);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    expect(controller.singleSelectedId, id);
  });

  testWidgets('Alt+Shift marquee subtracts intersecting shapes only', (
    tester,
  ) async {
    late int left;
    late int right;
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
            width: 2,
            height: 1,
          ),
          3,
          8,
        );
        left = c.singleSelectedId!;
        c.addShapeFromBuilderAt(
          (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 2,
            height: 1,
          ),
          7,
          8,
        );
        right = c.singleSelectedId!;
        c.setSelection(<int>{left, right});
      },
      camera: camera,
    );
    final page = controller.currentPage!;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    // Starting on the left shape makes Alt force a marquee; the box only
    // intersects that shape, so Alt+Shift removes it without toggling others.
    final start = _pagePoint(origin, camera, page, 3, 8);
    final end = _pagePoint(origin, camera, page, 4.5, 6.8);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.dragFrom(start, end - start);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    expect(controller.selection, <int>{right});
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

  testWidgets('Alt endpoint drop over a shape stays floating', (tester) async {
    late int connector;
    late int alternate;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) {
        c
          ..setTool(EditorTool.rectangle)
          ..createShapeByDrag(1, 4, 3, 6);
        final source = c.singleSelectedId!;
        c
          ..setTool(EditorTool.rectangle)
          ..createShapeByDrag(5, 4, 7, 6);
        final target = c.singleSelectedId!;
        c
          ..setTool(EditorTool.rectangle)
          ..createShapeByDrag(5, 1, 7, 3);
        alternate = c.singleSelectedId!;
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
    final route = VsdxPage.connectorRoute(page.findShapeById(connector)!);
    final alternateShape = page.findShapeById(alternate)!;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final start = _pagePoint(
      origin,
      camera,
      page,
      route.last.x,
      route.last.y,
    );
    final destination = _pagePoint(
      origin,
      camera,
      page,
      alternateShape.pinX,
      alternateShape.pinY,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.dragFrom(start, destination - start);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    page = controller.currentPage!;
    expect(
      page.connects.where((c) => c.fromSheetId == connector && c.isEnd),
      isEmpty,
    );
    final floating = VsdxPage.connectorRoute(
      page.findShapeById(connector)!,
    ).last;
    expect(floating.x, closeTo(alternateShape.pinX, 0.05));
    expect(floating.y, closeTo(alternateShape.pinY, 0.05));
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

  testWidgets(
      'connector tool snaps to a blue point approached from outside the AABB',
      (tester) async {
    late int target;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) {
        if (c.snapToGrid) c.toggleSnap();
        // Pin centre (3,5), 2×1 box → right edge at x=4, right CP at (4, 5).
        c.addShapeFromBuilderAt(
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
        target = c.singleSelectedId!;
        c.setTool(EditorTool.connector);
      },
      camera: camera,
    );
    final page = controller.currentPage!;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    // Start in empty space; end just outside the right CP so AABB miss + CP hit.
    final start = _pagePoint(origin, camera, page, 0.5, 5.0);
    final end = _pagePoint(origin, camera, page, 4.08, 5.0);

    final gesture = await tester.startGesture(start);
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final conn = controller.currentPage!;
    final glue = conn.connects.where((c) => c.isEnd).toList();
    expect(glue, isNotEmpty);
    expect(glue.single.toSheetId, target);
    expect(glue.single.toPart, greaterThanOrEqualTo(100));
  });

  testWidgets('pan tool drags the viewport without moving shapes',
      (tester) async {
    late int id;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) {
        id = _addRect(c);
        c.setTool(EditorTool.pan);
      },
      camera: camera,
    );
    final page = controller.currentPage!;
    final before = page.findShapeById(id)!;
    final offsetBefore = camera.offset;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final start = _pagePoint(origin, camera, page, before.pinX, before.pinY);
    const delta = Offset(48, -30);

    await tester.dragFrom(start, delta);
    await tester.pumpAndSettle();

    expect(controller.currentPage!.findShapeById(id)!.pinX, before.pinX);
    expect(controller.currentPage!.findShapeById(id)!.pinY, before.pinY);
    expect(camera.offset.dx - offsetBefore.dx, closeTo(delta.dx, 0.5));
    expect(camera.offset.dy - offsetBefore.dy, closeTo(delta.dy, 0.5));
    expect(controller.tool, EditorTool.pan);
  });

  testWidgets('pan tool pinch zooms around the focal point', (tester) async {
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) => c.setTool(EditorTool.pan),
      camera: camera,
    );
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final focal = origin + const Offset(500, 400);
    final scaleBefore = camera.scale;
    final contentBefore =
        (focal - origin - camera.offset) / camera.scale;

    final gesture = await tester.createGesture();
    await gesture.down(focal + const Offset(-40, 0));
    final gesture2 = await tester.createGesture();
    await gesture2.down(focal + const Offset(40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-40, 0));
    await gesture2.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.up();
    await gesture2.up();
    await tester.pumpAndSettle();

    expect(camera.scale, greaterThan(scaleBefore * 1.05));
    final contentAfter =
        (focal - origin - camera.offset) / camera.scale;
    expect(contentAfter.dx, closeTo(contentBefore.dx, 2));
    expect(contentAfter.dy, closeTo(contentBefore.dy, 2));
  });

  testWidgets('compact layout keeps selection for touch quick-add chrome',
      (tester) async {
    // Compact width enables touch chrome (selection-based quick-add arrows).
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late int id;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(400, 800),
      setUp: (c) => id = _addRect(c),
      camera: camera,
    );
    expect(MediaQuery.sizeOf(tester.element(find.byType(PageCanvas))).width,
        lessThan(720));
    expect(controller.selection, <int>{id});

    // Sanity: directional quick-add still creates a connected neighbour
    // (same controller path the arrow picker uses after a stencil tap).
    final before = controller.currentPage!.shapes.length;
    controller.quickAddInDirection(
      id,
      1, // east
      build: (nid, cx, cy) => VsdxShapeFactory.rectangle(
        id: nid,
        pinX: cx,
        pinY: cy,
        width: 1.5,
        height: 1,
      ),
      cx: 5.5,
      cy: 5,
    );
    expect(controller.currentPage!.shapes.length, greaterThan(before));
    expect(controller.currentPage!.connects, isNotEmpty);
  });
}
