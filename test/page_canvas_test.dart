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

  testWidgets('controller Home request restores a centred 100% canvas view',
      (tester) async {
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(320, 240),
      camera: camera,
    );
    expect(camera.scale, lessThan(1));

    controller.requestResetView();
    await tester.pumpAndSettle();
    await tester.pump();

    expect(camera.scale, 1);
    expect(
      camera.offset,
      Offset(
        (camera.viewport.width - camera.content.width) / 2,
        (camera.viewport.height - camera.content.height) / 2,
      ),
    );
  });

  testWidgets('controller can fit the page width without constraining height',
      (tester) async {
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(320, 240),
      camera: camera,
    );
    final initialScale = camera.scale;

    controller.requestFitPageWidth();
    await tester.pumpAndSettle();
    await tester.pump();

    final expectedScale = (camera.viewport.width - 80) / camera.content.width;
    expect(camera.scale, closeTo(expectedScale, 1e-9));
    expect(camera.scale, greaterThan(initialScale));
    expect(
      camera.offset.dx,
      closeTo(
        (camera.viewport.width - camera.content.width * expectedScale) / 2,
        1e-9,
      ),
    );
    // Portrait content is deliberately taller than the viewport at this zoom.
    expect(
      camera.content.height * camera.scale,
      greaterThan(camera.viewport.height),
    );
  });

  testWidgets('zoom percentage menu offers draw.io presets and custom zoom',
      (tester) async {
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    await _pumpCanvas(tester, const Size(800, 600), camera: camera);
    Future<void> openZoomMenu() async {
      tester
          .state<PopupMenuButtonState<Object>>(
            find.byKey(const ValueKey('zoom-menu')),
          )
          .showButtonMenu();
      await tester.pumpAndSettle();
    }

    await openZoomMenu();
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('400%'), findsOneWidget);
    expect(find.text('Fit Page Width'), findsOneWidget);
    expect(find.text('Custom…'), findsOneWidget);

    await tester.tap(find.text('200%'));
    await tester.pumpAndSettle();
    await tester.pump();
    expect(camera.scale, 2);

    await openZoomMenu();
    await tester.ensureVisible(find.text('Custom…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom…'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('custom-zoom-field')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('custom-zoom-field')),
      '175',
    );
    await tester.tap(find.byKey(const ValueKey('apply-custom-zoom')));
    await tester.pumpAndSettle();
    await tester.pump();
    expect(camera.scale, 1.75);
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

  testWidgets('stencil drop attaches to free connector end; Alt disables it',
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
        width: 1.5,
        height: 1,
      ),
      2,
      5,
    );
    final source = controller.singleSelectedId!;
    controller.createConnector(2, 5, 6, 5, beginTarget: source);
    final connector = controller.singleSelectedId!;
    final stencil = Stencil(
      'Rectangle',
      (id, x, y) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: x,
        pinY: y,
        width: 1.5,
        height: 1,
      ),
    );
    const dragKey = Key('test-connector-stencil-drag');

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

    final page = controller.currentPage!;
    final route = page.drawnConnectorPagePolyline(
      page.findShapeById(connector)!,
    );
    final destination = _pagePoint(
      tester.getTopLeft(find.byType(PageCanvas)),
      camera,
      page,
      route.last.x,
      route.last.y,
    );
    final start = tester.getCenter(find.byKey(dragKey));
    await tester.dragFrom(start, destination - start);
    await tester.pumpAndSettle();

    final attached = controller.singleSelectedId!;
    expect(
      controller.currentPage!.connects.any(
        (row) =>
            row.fromSheetId == connector &&
            row.isEnd &&
            row.toSheetId == attached,
      ),
      isTrue,
    );

    controller.undo();
    expect(controller.currentPage!.findShapeById(attached), isNull);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.dragFrom(start, destination - start);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(controller.currentPage!.shapes, hasLength(3));
    expect(
      controller.currentPage!.connects
          .where((row) => row.fromSheetId == connector && row.isEnd),
      isEmpty,
    );
  });

  testWidgets(
      'stencil drop on direction arrow inserts and connects; Alt disables it',
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
    final source = controller.singleSelectedId!;
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
    const dragKey = Key('test-direction-stencil-drag');

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

    final page = controller.currentPage!;
    final sourceBounds = page.shapePageAabb(source)!;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final sourceEdge = _pagePoint(
      origin,
      camera,
      page,
      sourceBounds.right,
      (sourceBounds.bottom + sourceBounds.top) / 2,
    );
    // Direction arrows use a fixed 22 logical-pixel gap on desktop.
    final destination = sourceEdge + const Offset(22, 0);
    final start = tester.getCenter(find.byKey(dragKey));
    await tester.dragFrom(start, destination - start);
    await tester.pumpAndSettle();

    final inserted = controller.singleSelectedId!;
    final connector = controller.currentPage!.shapes.singleWhere(
      (shape) => shape.isGlueableConnector,
    );
    expect(controller.currentPage!.shapes, hasLength(3));
    expect(
      controller.currentPage!.shapePageAabb(inserted)!.left,
      greaterThan(controller.currentPage!.shapePageAabb(source)!.right),
    );
    expect(
      controller.currentPage!.connects.any(
        (row) =>
            row.fromSheetId == connector.id &&
            row.isBegin &&
            row.toSheetId == source,
      ),
      isTrue,
    );
    expect(
      controller.currentPage!.connects.any(
        (row) =>
            row.fromSheetId == connector.id &&
            row.isEnd &&
            row.toSheetId == inserted,
      ),
      isTrue,
    );

    controller.undo();
    expect(controller.currentPage!.shapes, hasLength(1));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.dragFrom(start, destination - start);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(controller.currentPage!.shapes, hasLength(2));
    expect(controller.currentPage!.shapes.any((shape) => shape.is1D), isFalse);
    expect(controller.currentPage!.connects, isEmpty);
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

  testWidgets('controller Enter request opens the selected inline label editor',
      (tester) async {
    late int shapeId;
    final controller = await _pumpCanvas(
      tester,
      const Size(900, 700),
      setUp: (c) {
        shapeId = _addRect(c);
        c.setShapeText(shapeId, 'Edit me');
      },
    );
    final inlineEditor = find.descendant(
      of: find.byType(PageCanvas),
      matching: find.byType(TextField),
    );
    expect(inlineEditor, findsNothing);

    controller.requestEditSelectionLabel();
    await tester.pumpAndSettle();

    expect(inlineEditor, findsOneWidget);
    final field = tester.widget<TextField>(inlineEditor);
    expect(field.controller!.text, 'Edit me');
    expect(field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 7));
    expect(controller.textEditShapeId, shapeId);
  });

  testWidgets('inline Cmd+comma and Cmd+period toggle subscript and superscript',
      (tester) async {
    late int shapeId;
    final controller = await _pumpCanvas(
      tester,
      const Size(900, 700),
      setUp: (c) {
        shapeId = _addRect(c);
        c.setShapeText(shapeId, 'H2O');
      },
    );
    controller.requestEditSelectionLabel();
    await tester.pumpAndSettle();
    final inlineEditor = find.descendant(
      of: find.byType(PageCanvas),
      matching: find.byType(TextField),
    );
    final textController =
        tester.widget<TextField>(inlineEditor).controller!;
    textController.selection =
        const TextSelection(baseOffset: 1, extentOffset: 2);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    var rich = controller.currentPage!.findShapeById(shapeId)!.richText;
    expect(charStyleAt(rich, 1)!.position, VsdxTextPosition.subscript);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    rich = controller.currentPage!.findShapeById(shapeId)!.richText;
    expect(charStyleAt(rich, 1)!.position, VsdxTextPosition.normal);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    rich = controller.currentPage!.findShapeById(shapeId)!.richText;
    expect(charStyleAt(rich, 1)!.position, VsdxTextPosition.superscript);
    expect(rich.plainText, 'H2O');
  });

  testWidgets('canvas Shift+Delete clears labels without deleting shapes',
      (tester) async {
    late int source;
    late int target;
    late int connector;
    final controller = await _pumpCanvas(
      tester,
      const Size(900, 700),
      setUp: (c) {
        source = _addRect(c);
        c.setShapeText(source, 'Keep shape');
        c.addShapeFromBuilderAt(
          (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 1,
            height: 1,
          ),
          6,
          5,
        );
        target = c.singleSelectedId!;
        c.createConnector(3, 5, 6, 5,
            beginTarget: source, endTarget: target);
        connector = c.singleSelectedId!;
        c.selectOnly(source);
      },
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(
      controller.currentPage!.findShapeById(source)!.richText.plainText,
      isEmpty,
    );
    expect(controller.currentPage!.findShapeById(connector), isNotNull);

    controller.undo();
    expect(
      controller.currentPage!.findShapeById(source)!.richText.plainText,
      'Keep shape',
    );
    expect(controller.currentPage!.findShapeById(target), isNotNull);
    expect(controller.currentPage!.findShapeById(connector), isNotNull);
  });

  testWidgets('canvas Ctrl+Delete removes incident connectors', (tester) async {
    late int source;
    late int target;
    late int connector;
    final controller = await _pumpCanvas(
      tester,
      const Size(900, 700),
      setUp: (c) {
        source = _addRect(c);
        c.addShapeFromBuilderAt(
          (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 1,
            height: 1,
          ),
          6,
          5,
        );
        target = c.singleSelectedId!;
        c.createConnector(3, 5, 6, 5,
            beginTarget: source, endTarget: target);
        connector = c.singleSelectedId!;
        c.selectOnly(source);
      },
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(controller.currentPage!.findShapeById(source), isNull);
    expect(controller.currentPage!.findShapeById(target), isNotNull);
    expect(controller.currentPage!.findShapeById(connector), isNull);
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

  testWidgets('Alt+Shift click removes a shape from the selection',
      (tester) async {
    late int left;
    late int right;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) {
        left = _addRect(c);
        c.addShapeFromBuilderAt(
          (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 2,
            height: 1,
          ),
          7,
          5,
        );
        right = c.singleSelectedId!;
        c.setSelection(<int>[left, right]);
      },
      camera: camera,
    );
    final point = _pagePoint(
      tester.getTopLeft(find.byType(PageCanvas)),
      camera,
      controller.currentPage!,
      3,
      5,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await _tapCanvasAt(tester, point);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    expect(controller.selection, equals(<int>{right}));
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

  testWidgets('plain groups select root first then drill into children',
      (tester) async {
    late int groupId;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) {
        c
          ..setTool(EditorTool.rectangle)
          ..createShapeByDrag(1, 4, 3, 6);
        c
          ..setTool(EditorTool.rectangle)
          ..createShapeByDrag(5, 4, 7, 6);
        c.selectAll();
        c.groupSelection();
        groupId = c.singleSelectedId!;
        c.clearSelection();
      },
      camera: camera,
    );
    var page = controller.currentPage!;
    final group = page.findShapeById(groupId)!;
    final firstId = group.children.first.id;
    final secondId = group.children.last.id;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    Offset centreOf(int id) {
      final bounds = page.shapePageAabb(id)!;
      return _pagePoint(
        origin,
        camera,
        page,
        (bounds.left + bounds.right) / 2,
        (bounds.bottom + bounds.top) / 2,
      );
    }

    final first = centreOf(firstId);
    final second = centreOf(secondId);
    await _tapCanvasAt(tester, first);
    expect(controller.selection, <int>{groupId});

    await _tapCanvasAt(tester, first);
    expect(controller.selection, <int>{firstId});

    // Once inside a group, a sibling is selected directly.
    await _tapCanvasAt(tester, second);
    expect(controller.selection, <int>{secondId});

    // Alt bypasses the root-first group selection.
    controller.clearSelection();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    try {
      await _tapCanvasAt(tester, first);
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    }
    expect(controller.selection, <int>{firstId});

    // Starting a normal drag inside an unselected group moves the group root.
    controller.clearSelection();
    await tester.pump();
    final beforeFirst = page.shapePageAabb(firstId)!;
    final beforeSecond = page.shapePageAabb(secondId)!;
    await tester.dragFrom(first, const Offset(96, 0));
    await tester.pumpAndSettle();
    page = controller.currentPage!;
    final afterFirst = page.shapePageAabb(firstId)!;
    final afterSecond = page.shapePageAabb(secondId)!;
    expect(controller.selection, <int>{groupId});
    final firstDelta = afterFirst.left - beforeFirst.left;
    final secondDelta = afterSecond.left - beforeSecond.left;
    expect(firstDelta, greaterThan(0.5));
    expect(secondDelta, closeTo(firstDelta, 1e-6));
  });

  testWidgets('group child can be removed by menu or dragged out',
      (tester) async {
    late int groupId;
    late int childId;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) {
        c
          ..setTool(EditorTool.rectangle)
          ..createShapeByDrag(1, 4, 3, 6);
        c
          ..setTool(EditorTool.rectangle)
          ..createShapeByDrag(5, 4, 7, 6);
        c.selectAll();
        c.groupSelection();
        groupId = c.singleSelectedId!;
        childId =
            c.currentPage!.findShapeById(groupId)!.children.first.id;
        c.setSelection(<int>{childId});
      },
      camera: camera,
    );
    var page = controller.currentPage!;
    final before = page.shapePageAabb(childId)!;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final childCentre = _pagePoint(
      origin,
      camera,
      page,
      (before.left + before.right) / 2,
      (before.bottom + before.top) / 2,
    );

    await tester.tapAt(childCentre, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Remove from Group'), findsOneWidget);
    await tester.ensureVisible(find.text('Remove from Group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from Group'));
    await tester.pumpAndSettle();
    expect(controller.currentPage!.findParentId(childId), isNull);

    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.currentPage!.findParentId(childId), groupId);

    await tester.dragFrom(childCentre, const Offset(0, -200));
    await tester.pumpAndSettle();
    page = controller.currentPage!;
    expect(page.findParentId(childId), isNull);
    expect(page.shapePageAabb(childId)!.bottom, greaterThan(before.top));

    controller.undo();
    expect(controller.currentPage!.findParentId(childId), groupId);
    final restored = controller.currentPage!.shapePageAabb(childId)!;
    expect(restored.left, closeTo(before.left, 1e-6));
    expect(restored.bottom, closeTo(before.bottom, 1e-6));
  });

  testWidgets('container context menu collapses and expands selection',
      (tester) async {
    late int containerId;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) {
        c.addShapeFromBuilderAt(
          (id, cx, cy) => VsdxShapeFactory.container(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 4,
            height: 3,
          ),
          4,
          5,
        );
        containerId = c.singleSelectedId!;
      },
      camera: camera,
    );
    final origin = tester.getTopLeft(find.byType(PageCanvas));

    Offset centre() {
      final page = controller.currentPage!;
      final bounds = page.shapePageAabb(containerId)!;
      return _pagePoint(
        origin,
        camera,
        page,
        (bounds.left + bounds.right) / 2,
        (bounds.bottom + bounds.top) / 2,
      );
    }

    await tester.tapAt(centre(), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Collapse Selection'), findsOneWidget);
    expect(find.text('Expand Selection'), findsNothing);
    await tester.ensureVisible(find.text('Collapse Selection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Collapse Selection'));
    await tester.pumpAndSettle();
    expect(controller.isCollapsed(containerId), isTrue);

    await tester.tapAt(centre(), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Expand Selection'), findsOneWidget);
    expect(find.text('Collapse Selection'), findsNothing);
    await tester.ensureVisible(find.text('Expand Selection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expand Selection'));
    await tester.pumpAndSettle();
    expect(controller.isCollapsed(containerId), isFalse);
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

  testWidgets('Alt endpoint drop creates one undoable custom fixed point',
      (tester) async {
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
    final alternatePointCount = alternateShape.connectionPoints.length;
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
    try {
      await tester.dragFrom(start, destination - start);
      await tester.pumpAndSettle();
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    }

    page = controller.currentPage!;
    final endGlue = page.connects
        .singleWhere((c) => c.fromSheetId == connector && c.isEnd);
    expect(endGlue.toSheetId, alternate);
    expect(VsdxPage.fixedConnectionIndex(endGlue), alternatePointCount);
    expect(
      page.findShapeById(alternate)!.connectionPoints,
      hasLength(alternatePointCount + 1),
    );
    final fixed = VsdxPage.connectorRoute(
      page.findShapeById(connector)!,
    ).last;
    expect(fixed.x, closeTo(alternateShape.pinX, 0.05));
    expect(fixed.y, closeTo(alternateShape.pinY, 0.05));

    controller.undo();
    page = controller.currentPage!;
    expect(
      page.findShapeById(alternate)!.connectionPoints,
      hasLength(alternatePointCount),
    );
    expect(
      page.connects
          .singleWhere((c) => c.fromSheetId == connector && c.isEnd)
          .toSheetId,
      isNot(alternate),
    );
  });

  testWidgets('Shift endpoint drop forces floating shape glue', (tester) async {
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
    final alternatePointCount = alternateShape.connectionPoints.length;
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

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    try {
      await tester.dragFrom(start, destination - start);
      await tester.pumpAndSettle();
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }

    page = controller.currentPage!;
    final endGlue = page.connects
        .singleWhere((c) => c.fromSheetId == connector && c.isEnd);
    expect(endGlue.toSheetId, alternate);
    expect(VsdxPage.fixedConnectionIndex(endGlue), isNull);
    expect(endGlue.toPart, 3);
    expect(
      page.findShapeById(alternate)!.connectionPoints,
      hasLength(alternatePointCount),
    );
  });

  testWidgets('connector label diamond drags to an undoable page position',
      (tester) async {
    late int connector;
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
        c.createConnector(
          2,
          5,
          6,
          5,
          beginTarget: source,
          endTarget: target,
        );
        connector = c.singleSelectedId!;
        c.setShapeText(connector, 'Approval');
      },
      camera: camera,
    );
    var page = controller.currentPage!;
    final shape = page.findShapeById(connector)!;
    final midpoint = VsdxPage.connectorMidpoint(shape);
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final start = _pagePoint(
      origin,
      camera,
      page,
      midpoint.x,
      midpoint.y,
    );
    final destination = _pagePoint(origin, camera, page, 4.0, 3.0);

    await tester.dragFrom(start, destination - start);
    await tester.pumpAndSettle();

    page = controller.currentPage!;
    final moved = page.findShapeById(connector)!;
    final block = moved.richText.textBlock;
    final label = page.localToPageDeep(
      connector,
      Offset2D(block.pinXInches!, block.pinYInches!),
    );
    expect(label.x, closeTo(4.0, 0.05));
    expect(label.y, closeTo(3.0, 0.05));

    controller.undo();
    expect(
      controller.currentPage!
          .findShapeById(connector)!
          .richText
          .textBlock
          .pinXInches,
      isNull,
    );
  });

  testWidgets('connector label rotate handle writes one undoable angle',
      (tester) async {
    late int connector;
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
        c.createConnector(
          2,
          5,
          6,
          5,
          beginTarget: source,
          endTarget: target,
        );
        connector = c.singleSelectedId!;
        c.setShapeText(connector, 'Approval');
      },
      camera: camera,
    );
    final page = controller.currentPage!;
    final shape = page.findShapeById(connector)!;
    final midpoint = VsdxPage.connectorMidpoint(shape);
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final anchor = _pagePoint(
      origin,
      camera,
      page,
      midpoint.x,
      midpoint.y,
    );
    final start = anchor + const Offset(0, -26);
    final destination = anchor + const Offset(60, 0);

    await tester.dragFrom(start, destination - start);
    await tester.pumpAndSettle();

    expect(
      controller.currentPage!
          .findShapeById(connector)!
          .richText
          .textBlock
          .angleRad,
      closeTo(-math.pi / 2, 0.05),
    );
    controller.undo();
    expect(
      controller.currentPage!
          .findShapeById(connector)!
          .richText
          .textBlock
          .angleRad,
      closeTo(0, 1e-9),
    );
  });

  testWidgets('blank context menu selects all edges or vertices',
      (tester) async {
    late int connector;
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
        c.createConnector(
          2,
          5,
          6,
          5,
          beginTarget: source,
          endTarget: target,
        );
        connector = c.singleSelectedId!;
        c.clearSelection();
      },
      camera: camera,
    );
    final page = controller.currentPage!;
    final blank = _pagePoint(
      tester.getTopLeft(find.byType(PageCanvas)),
      camera,
      page,
      9,
      1,
    );

    await tester.tapAt(blank, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Select Edges'), findsOneWidget);
    expect(find.text('Select Vertices'), findsOneWidget);
    await tester.tap(find.text('Select Edges'));
    await tester.pumpAndSettle();
    expect(controller.selection, <int>{connector});

    // A blank-canvas right click exposes the page selection commands even
    // while an edge is selected.
    await tester.tapAt(blank, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select Vertices'));
    await tester.pumpAndSettle();
    expect(controller.selection, hasLength(2));
    expect(
      controller.selection.every(
        (id) => !controller.currentPage!.findShapeById(id)!.is1D,
      ),
      isTrue,
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

  testWidgets('connector context menu adds and removes a waypoint',
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
    final midpoint = Offset2D(
      (route.first.x + route.last.x) / 2,
      (route.first.y + route.last.y) / 2,
    );
    final screenPoint = _pagePoint(
      tester.getTopLeft(find.byType(PageCanvas)),
      camera,
      page,
      midpoint.x,
      midpoint.y,
    );

    await tester.tapAt(screenPoint, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Add Waypoint'), findsOneWidget);
    expect(find.text('Remove Waypoint'), findsNothing);

    await tester.tap(find.text('Add Waypoint'));
    await tester.pumpAndSettle();
    expect(controller.connectorWaypoints(connector), hasLength(1));
    expect(
      controller.connectorWaypoints(connector).single.x,
      closeTo(midpoint.x, 0.05),
    );
    expect(
      controller.connectorWaypoints(connector).single.y,
      closeTo(midpoint.y, 0.05),
    );

    await tester.tapAt(screenPoint, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Remove Waypoint'), findsOneWidget);
    expect(find.text('Add Waypoint'), findsNothing);
    expect(find.text('Clear Waypoints'), findsOneWidget);

    await tester.tap(find.text('Remove Waypoint'));
    await tester.pumpAndSettle();
    expect(controller.connectorWaypoints(connector), isEmpty);

    controller.undo();
    expect(controller.connectorWaypoints(connector), hasLength(1));
    controller.undo();
    expect(controller.connectorWaypoints(connector), isEmpty);
  });

  testWidgets('shape context menu selects connections and clears anchors',
      (tester) async {
    late int source;
    late int target;
    late int connector;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) {
        source = _addRect(c);
        c.addShapeFromBuilderAt(
          (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 2,
            height: 1,
          ),
          7,
          5,
        );
        target = c.singleSelectedId!;
        c.createConnector(
          3,
          5,
          7,
          5,
          beginTarget: source,
          endTarget: target,
          beginConnectionPointIndex: 1,
          endConnectionPointIndex: 3,
        );
        connector = c.singleSelectedId!;
        c.selectOnly(source);
      },
      camera: camera,
    );
    final page = controller.currentPage!;
    final sourceShape = page.findShapeById(source)!;
    final sourcePoint = _pagePoint(
      tester.getTopLeft(find.byType(PageCanvas)),
      camera,
      page,
      sourceShape.pinX,
      sourceShape.pinY,
    );

    await tester.tapAt(sourcePoint, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Select Connections'), findsOneWidget);
    expect(find.text('Clear Anchors'), findsOneWidget);

    await tester.tap(find.text('Select Connections'));
    await tester.pumpAndSettle();
    expect(controller.selection, <int>{source, connector});

    await tester.tapAt(sourcePoint, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear Anchors'));
    await tester.pumpAndSettle();

    final rows = controller.currentPage!.connects
        .where((connect) => connect.fromSheetId == connector)
        .toList();
    expect(rows, hasLength(2));
    expect(rows.every((connect) => connect.toPart == 3), isTrue);
    expect(
      rows.map((connect) => connect.toSheetId),
      containsAll(<int>[source, target]),
    );
  });

  testWidgets('shape context menu selects connector-tree children',
      (tester) async {
    late int root;
    late int upper;
    late int lower;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) {
        root = _addRect(c);
        c.addShapeFromBuilderAt(
          (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 1.5,
            height: 0.8,
          ),
          6,
          6,
        );
        upper = c.singleSelectedId!;
        c.addShapeFromBuilderAt(
          (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 1.5,
            height: 0.8,
          ),
          6,
          4,
        );
        lower = c.singleSelectedId!;
        c
          ..createConnector(
            3,
            5,
            6,
            6,
            beginTarget: root,
            endTarget: upper,
          )
          ..createConnector(
            3,
            5,
            6,
            4,
            beginTarget: root,
            endTarget: lower,
          )
          ..selectOnly(root);
      },
      camera: camera,
    );
    final page = controller.currentPage!;
    final rootShape = page.findShapeById(root)!;
    final point = _pagePoint(
      tester.getTopLeft(find.byType(PageCanvas)),
      camera,
      page,
      rootShape.pinX,
      rootShape.pinY,
    );

    await tester.tapAt(point, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Select Children'), findsOneWidget);
    expect(find.text('Select Subtree'), findsOneWidget);

    await tester.tap(find.text('Select Children'));
    await tester.pumpAndSettle();
    expect(controller.selection, <int>{upper, lower});
  });

  testWidgets('context menu copies shape data, preserves label, and turns shape',
      (tester) async {
    late int source;
    late int target;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(1000, 800),
      setUp: (c) {
        source = _addRect(c);
        c.setShapeText(source, 'Source');
        c.setShapeProperties(source, const <VsdxUserProperty>[
          VsdxUserProperty(
            name: 'Owner',
            label: 'Process owner',
            value: 'Alice',
            prompt: 'Team or person',
          ),
        ]);
        c.addShapeFromBuilderAt(
          (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 2,
            height: 1,
          ),
          7,
          5,
        );
        target = c.singleSelectedId!;
        c.setShapeText(target, 'Target');
        c.selectOnly(source);
      },
      camera: camera,
    );
    final page = controller.currentPage!;
    final canvasOrigin = tester.getTopLeft(find.byType(PageCanvas));
    Offset shapePoint(int id) {
      final shape = page.findShapeById(id)!;
      return _pagePoint(
        canvasOrigin,
        camera,
        page,
        shape.pinX,
        shape.pinY,
      );
    }

    await tester.tapAt(shapePoint(source), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Copy Data'), findsOneWidget);
    expect(find.text('Turn / Reverse'), findsOneWidget);
    await tester.ensureVisible(find.text('Copy Data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy Data'));
    await tester.pumpAndSettle();

    await tester.tapAt(shapePoint(target), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Paste Data'), findsOneWidget);
    await tester.ensureVisible(find.text('Paste Data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste Data'));
    await tester.pumpAndSettle();

    var pasted = controller.currentPage!.findShapeById(target)!;
    expect(pasted.userProperties.single.name, 'Owner');
    expect(pasted.userProperties.single.label, 'Process owner');
    expect(pasted.userProperties.single.prompt, 'Team or person');
    expect(pasted.richText.plainText, 'Target');

    await tester.tapAt(shapePoint(target), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Turn / Reverse'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn / Reverse'));
    await tester.pumpAndSettle();

    pasted = controller.currentPage!.findShapeById(target)!;
    expect(pasted.angleRad, closeTo(-math.pi / 2, 1e-9));
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

  testWidgets('disabled connection points use floating perimeter glue',
      (tester) async {
    late int target;
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
          5,
        );
        target = c.singleSelectedId!;
        c
          ..toggleConnectionPoints()
          ..setTool(EditorTool.connector);
      },
      camera: camera,
    );
    final page = controller.currentPage!;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final start = _pagePoint(origin, camera, page, 0.5, 5.0);
    final end = _pagePoint(origin, camera, page, 4.08, 5.0);

    final gesture = await tester.startGesture(start);
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final glue = controller.currentPage!.connects.where((c) => c.isEnd).single;
    expect(glue.toSheetId, target);
    expect(glue.toPart, lessThan(100));
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

  testWidgets('right and middle mouse drags temporarily pan the canvas',
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
    final before = controller.currentPage!.findShapeById(id)!;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    const delta = Offset(54, -28);

    for (final buttons in <int>[kSecondaryButton, kTertiaryButton]) {
      final offsetBefore = camera.offset;
      final start = _pagePoint(
        origin,
        camera,
        controller.currentPage!,
        before.pinX,
        before.pinY,
      );
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: buttons,
      );
      await gesture.down(start);
      await gesture.moveBy(delta);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(camera.offset.dx - offsetBefore.dx, closeTo(delta.dx, 0.5));
      expect(camera.offset.dy - offsetBefore.dy, closeTo(delta.dy, 0.5));
      expect(controller.currentPage!.findShapeById(id)!.pinX, before.pinX);
      expect(controller.currentPage!.findShapeById(id)!.pinY, before.pinY);
      expect(find.text('Paste Here'), findsNothing);
    }
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

  testWidgets(
      'direction arrow drag connects; Ctrl-drag clones at the drop point',
      (tester) async {
    // Compact width exposes the selection-based direction arrows without
    // relying on a desktop hover event.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late int source;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(400, 800),
      setUp: (c) {
        source = _addRect(c);
        c.setShapeText(source, 'Clone me');
      },
      camera: camera,
    );
    final page = controller.currentPage!;
    final sourceBounds = page.shapePageAabb(source)!;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final eastEdge = _pagePoint(
      origin,
      camera,
      page,
      sourceBounds.right,
      (sourceBounds.bottom + sourceBounds.top) / 2,
    );
    // Compact/touch direction arrows use a fixed 38 logical-pixel gap.
    final eastArrow = eastEdge + const Offset(38, 0);
    final cloneDrop = _pagePoint(origin, camera, page, 7, 3.5);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.dragFrom(eastArrow, cloneDrop - eastArrow);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final clone = controller.singleSelected!;
    final connector = controller.currentPage!.shapes.singleWhere(
      (shape) => shape.isGlueableConnector,
    );
    expect(controller.currentPage!.shapes, hasLength(3));
    expect(clone.id, isNot(source));
    expect(clone.richText.plainText, 'Clone me');
    expect(clone.pinX, closeTo(controller.snap(7), 0.01));
    expect(clone.pinY, closeTo(controller.snap(3.5), 0.01));
    expect(
      controller.currentPage!.connects.any(
        (row) =>
            row.fromSheetId == connector.id &&
            row.isBegin &&
            row.toSheetId == source,
      ),
      isTrue,
    );
    expect(
      controller.currentPage!.connects.any(
        (row) =>
            row.fromSheetId == connector.id &&
            row.isEnd &&
            row.toSheetId == clone.id,
      ),
      isTrue,
    );

    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.currentPage!.shapes, hasLength(1));
    expect(controller.selection, <int>{source});

    final floatingDrop = _pagePoint(origin, camera, page, 7, 7);
    await tester.dragFrom(eastArrow, floatingDrop - eastArrow);
    await tester.pumpAndSettle();

    expect(controller.currentPage!.shapes, hasLength(2));
    final floatingConnector = controller.singleSelected!;
    expect(floatingConnector.isGlueableConnector, isTrue);
    expect(
      controller.currentPage!.connects.any(
        (row) =>
            row.fromSheetId == floatingConnector.id &&
            row.isBegin &&
            row.toSheetId == source,
      ),
      isTrue,
    );
    expect(
      controller.currentPage!.connects
          .where((row) =>
              row.fromSheetId == floatingConnector.id && row.isEnd),
      isEmpty,
    );
  });

  testWidgets('disabled connection arrows leave no invisible drag target',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late int source;
    final camera = CanvasCamera();
    addTearDown(camera.dispose);
    final controller = await _pumpCanvas(
      tester,
      const Size(400, 800),
      setUp: (c) {
        source = _addRect(c);
        c.toggleConnectionArrows();
      },
      camera: camera,
    );
    final page = controller.currentPage!;
    final sourceBounds = page.shapePageAabb(source)!;
    final origin = tester.getTopLeft(find.byType(PageCanvas));
    final eastEdge = _pagePoint(
      origin,
      camera,
      page,
      sourceBounds.right,
      (sourceBounds.bottom + sourceBounds.top) / 2,
    );
    final eastArrow = eastEdge + const Offset(38, 0);
    final drop = _pagePoint(origin, camera, page, 7, 7);

    await tester.dragFrom(eastArrow, drop - eastArrow);
    await tester.pumpAndSettle();

    expect(controller.currentPage!.shapes, hasLength(1));
    expect(controller.currentPage!.connects, isEmpty);
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
