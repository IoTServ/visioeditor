import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/editor/editor_shortcuts.dart';
import 'package:vsdx/vsdx.dart';

/// Minimal harness that mirrors app-level [EditorCallbackShortcuts] for Delete /
/// Backspace / arrows so we can verify they mutate the controller without the
/// canvas [Focus] node holding primary focus.
void main() {
  EditorController ctrlWithRect() {
    final c = EditorController()
      ..newDocument(widthInches: 11, heightInches: 8.5);
    addTearDown(c.dispose);
    c.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1.5,
        height: 1,
      ),
      2,
      3,
    );
    return c;
  }

  bool isEditableTextFocused() {
    final primary = FocusManager.instance.primaryFocus;
    final ctx = primary?.context;
    if (ctx == null) return false;
    return ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  Map<ShortcutActivator, VoidCallback> bindingsFor(
    EditorController c, {
    VoidCallback? onBold,
    VoidCallback? onFind,
    VoidCallback? onRotate,
  }) {
    void deleteSel() {
      if (isEditableTextFocused()) return;
      if (c.hasSelection || c.editingConnectionPoints) c.deleteSelection();
    }

    void nudge(double dx, double dy) {
      if (isEditableTextFocused()) return;
      if (!c.hasSelection || c.editingConnectionPoints) return;
      final step = c.snapToGrid ? c.gridInches : 0.1;
      c.moveSelectionBy(dx * step, dy * step);
    }

    void resizeSelection(double dw, double dh) {
      if (isEditableTextFocused()) return;
      final geometry = c.selectedGeometry;
      if (geometry == null ||
          c.singleSelected?.is1D == true ||
          c.editingConnectionPoints) {
        return;
      }
      final step = c.snapToGrid ? c.gridInches : 0.1;
      if (dw != 0) c.setSelectedWidth(geometry.w + dw * step);
      if (dh != 0) c.setSelectedHeight(geometry.h + dh * step);
    }

    // Match app bindings: these do not themselves guard on text focus — the
    // host must defer the chords so EditableText receives them.
    void undo() {
      if (c.canUndo) c.undo();
    }

    final bold = onBold ?? () {};
    final find = onFind ?? () {};
    final rotate = onRotate ?? () {};

    return <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.delete): deleteSel,
      const SingleActivator(LogicalKeyboardKey.backspace): deleteSel,
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => nudge(-1, 0),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => nudge(1, 0),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => nudge(0, 1),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => nudge(0, -1),
      const SingleActivator(
        LogicalKeyboardKey.arrowLeft,
        meta: true,
        shift: true,
      ): () => resizeSelection(-1, 0),
      const SingleActivator(
        LogicalKeyboardKey.arrowRight,
        meta: true,
        shift: true,
      ): () => resizeSelection(1, 0),
      const SingleActivator(
        LogicalKeyboardKey.arrowUp,
        meta: true,
        shift: true,
      ): () => resizeSelection(0, -1),
      const SingleActivator(
        LogicalKeyboardKey.arrowDown,
        meta: true,
        shift: true,
      ): () => resizeSelection(0, 1),
      const SingleActivator(
        LogicalKeyboardKey.arrowRight,
        control: true,
        shift: true,
      ): () => resizeSelection(1, 0),
      const SingleActivator(
        LogicalKeyboardKey.keyR,
        alt: true,
        shift: true,
      ): c.clearSelectedConnectorWaypoints,
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): undo,
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): undo,
      const SingleActivator(LogicalKeyboardKey.keyB, meta: true): bold,
      const SingleActivator(LogicalKeyboardKey.keyB, control: true): bold,
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true): find,
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): find,
      const SingleActivator(LogicalKeyboardKey.keyR, meta: true): rotate,
      const SingleActivator(LogicalKeyboardKey.keyR, control: true): rotate,
    };
  }

  Future<void> pumpHarness(
    WidgetTester tester,
    EditorController c, {
    Widget? body,
    VoidCallback? onBold,
    VoidCallback? onFind,
    VoidCallback? onRotate,
  }) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: EditorCallbackShortcuts(
          bindings: bindingsFor(
            c,
            onBold: onBold,
            onFind: onFind,
            onRotate: onRotate,
          ),
          isEditableTextFocused: isEditableTextFocused,
          child: Scaffold(
            body: body ??
                Focus(
                  focusNode: focus,
                  autofocus: true,
                  child: const SizedBox(width: 100, height: 100),
                ),
          ),
        ),
      ),
    );
    await tester.pump();
    if (body == null) {
      focus.requestFocus();
      await tester.pump();
    }
  }

  testWidgets('Delete removes selection without canvas focus', (tester) async {
    final c = ctrlWithRect();
    final id = c.selection.single;
    await pumpHarness(tester, c);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();

    expect(c.currentPage!.findShapeById(id), isNull);
    expect(c.selection, isEmpty);
  });

  testWidgets('Backspace removes selection without canvas focus',
      (tester) async {
    final c = ctrlWithRect();
    final id = c.selection.single;
    await pumpHarness(tester, c);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(c.currentPage!.findShapeById(id), isNull);
  });

  testWidgets('Arrow keys nudge selection without canvas focus',
      (tester) async {
    final c = ctrlWithRect();
    if (c.snapToGrid) c.toggleSnap();
    final id = c.selection.single;
    final before = c.currentPage!.findShapeById(id)!;
    await pumpHarness(tester, c);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    final after = c.currentPage!.findShapeById(id)!;
    expect(after.pinX, closeTo(before.pinX + 0.1, 1e-9));
    expect(after.pinY, closeTo(before.pinY, 1e-9));
  });

  testWidgets('Cmd+Shift+arrow resizes the selected shape',
      (tester) async {
    final c = ctrlWithRect();
    if (c.snapToGrid) c.toggleSnap();
    final id = c.selection.single;
    final before = c.currentPage!.findShapeById(id)!;
    await pumpHarness(tester, c);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    final after = c.currentPage!.findShapeById(id)!;
    expect(after.width, closeTo(before.width + 0.1, 1e-9));
    expect(after.height, before.height);
  });

  testWidgets('Alt+Shift+R clears selected connector waypoints',
      (tester) async {
    final c = ctrlWithRect();
    c.createConnector(2, 3, 6, 3);
    final connector = c.singleSelectedId!;
    c.addWaypoint(connector, 0, const Offset2D(4, 4));
    expect(c.canClearWaypoints, isTrue);
    await pumpHarness(tester, c);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();

    expect(c.currentPage!.findShapeById(connector)!.waypoints, isEmpty);
  });

  testWidgets('Backspace edits search field instead of deleting shapes',
      (tester) async {
    final c = ctrlWithRect();
    final id = c.selection.single;
    final search = TextEditingController(text: 'abc');
    addTearDown(search.dispose);

    await pumpHarness(
      tester,
      c,
      body: TextField(
        controller: search,
        autofocus: true,
      ),
    );
    await tester.pump();
    expect(isEditableTextFocused(), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(search.text, 'ab');
    expect(c.currentPage!.findShapeById(id), isNotNull);
  });

  testWidgets('Cmd/Ctrl+Z with text focus does not undo the document',
      (tester) async {
    final c = ctrlWithRect();
    final id = c.selection.single;
    final search = TextEditingController(text: 'hello');
    addTearDown(search.dispose);

    await pumpHarness(
      tester,
      c,
      body: TextField(
        controller: search,
        autofocus: true,
      ),
    );
    await tester.pump();
    expect(isEditableTextFocused(), isTrue);
    expect(c.canUndo, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    // Document undo would remove the rect; deferral must leave it alone.
    expect(c.currentPage!.findShapeById(id), isNotNull);
    expect(c.canUndo, isTrue);
  });

  testWidgets('Cmd/Ctrl+B with text focus does not toggle shape bold',
      (tester) async {
    final c = ctrlWithRect();
    var boldHits = 0;
    final search = TextEditingController(text: 'hello');
    addTearDown(search.dispose);

    await pumpHarness(
      tester,
      c,
      onBold: () => boldHits++,
      body: TextField(
        controller: search,
        autofocus: true,
      ),
    );
    await tester.pump();
    expect(isEditableTextFocused(), isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(boldHits, 0);
  });

  testWidgets('Cmd/Ctrl+F and R with text focus do not open find or rotate',
      (tester) async {
    final c = ctrlWithRect();
    var findHits = 0;
    var rotateHits = 0;
    final search = TextEditingController(text: 'hello');
    addTearDown(search.dispose);

    await pumpHarness(
      tester,
      c,
      onFind: () => findHits++,
      onRotate: () => rotateHits++,
      body: TextField(
        controller: search,
        autofocus: true,
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(findHits, 0);
    expect(rotateHits, 0);
  });

  testWidgets('Cmd+S is still recognised as a document chord while typing',
      (tester) async {
    final c = ctrlWithRect();
    final search = TextEditingController(text: 'hello');
    addTearDown(search.dispose);

    await pumpHarness(
      tester,
      c,
      body: TextField(
        controller: search,
        autofocus: true,
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    expect(
      EditorCallbackShortcuts.isTextEditingShortcut(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyS,
          logicalKey: LogicalKeyboardKey.keyS,
          timeStamp: Duration.zero,
        ),
      ),
      isFalse,
    );
    expect(
      EditorCallbackShortcuts.isTextEditingShortcut(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyF,
          logicalKey: LogicalKeyboardKey.keyF,
          timeStamp: Duration.zero,
        ),
      ),
      isTrue,
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  });
}
