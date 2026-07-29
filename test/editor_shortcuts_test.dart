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
    VoidCallback? onSaveAs,
    VoidCallback? onEditLink,
  }) {
    void deleteSel({bool includeConnected = false}) {
      if (isEditableTextFocused()) return;
      if (c.hasSelection || c.editingConnectionPoints) {
        c.deleteSelection(includeConnected: includeConnected);
      }
    }

    void nudge(double dx, double dy) {
      if (isEditableTextFocused()) return;
      if (!c.hasSelection || c.editingConnectionPoints) return;
      final step = c.snapToGrid ? c.gridInches : 0.1;
      c.moveSelectionBy(dx * step, dy * step);
    }

    void nudgeOrMovePage(double dx, double dy) {
      if (isEditableTextFocused()) return;
      if (c.hasSelection) {
        nudge(dx, dy);
      } else if (dx < 0) {
        c.moveCurrentPageBy(-1);
      } else if (dx > 0) {
        c.moveCurrentPageBy(1);
      } else if (dy > 0) {
        c.moveCurrentPageToBoundary(last: false);
      } else if (dy < 0) {
        c.moveCurrentPageToBoundary(last: true);
      }
    }

    void resizeSelection(double dw, double dh, {bool byPoint = false}) {
      if (isEditableTextFocused()) return;
      final geometry = c.selectedGeometry;
      if (geometry == null ||
          c.singleSelected?.is1D == true ||
          c.editingConnectionPoints) {
        return;
      }
      final step = byPoint ? 1 / 72 : (c.snapToGrid ? c.gridInches : 0.1);
      if (dw != 0) c.setSelectedWidth(geometry.w + dw * step);
      if (dh != 0) c.setSelectedHeight(geometry.h + dh * step);
    }

    void resizeOrSelectPage(double dw, double dh) {
      if (isEditableTextFocused()) return;
      if (c.hasSelection) {
        resizeSelection(dw, dh, byPoint: true);
      } else if (dw < 0) {
        c.selectRelativePage(-1);
      } else if (dw > 0) {
        c.selectRelativePage(1);
      } else if (dh < 0) {
        c.selectBoundaryPage(last: false);
      } else if (dh > 0) {
        c.selectBoundaryPage(last: true);
      }
    }

    void adjustWholeLabelTextSize(double deltaPoints) {
      if (!c.hasSelection) return;
      if (isEditableTextFocused() && c.textEditShapeId == null) return;
      c.adjustWholeLabelTextSizePoints(deltaPoints);
    }

    // Match app bindings: these do not themselves guard on text focus — the
    // host must defer the chords so EditableText receives them.
    void undo() {
      if (c.canUndo) c.undo();
    }

    final bold = onBold ?? () {};
    final find = onFind ?? () {};
    final rotate = onRotate ?? c.turnSelection;
    final saveAs = onSaveAs ?? () {};
    final editLink = onEditLink ?? () {};

    return <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.delete): deleteSel,
      const SingleActivator(LogicalKeyboardKey.backspace): deleteSel,
      const SingleActivator(
        LogicalKeyboardKey.delete,
        meta: true,
      ): () => deleteSel(includeConnected: true),
      const SingleActivator(
        LogicalKeyboardKey.delete,
        control: true,
      ): () => deleteSel(includeConnected: true),
      const SingleActivator(
        LogicalKeyboardKey.backspace,
        meta: true,
      ): () => deleteSel(includeConnected: true),
      const SingleActivator(
        LogicalKeyboardKey.backspace,
        control: true,
      ): () => deleteSel(includeConnected: true),
      const SingleActivator(
        LogicalKeyboardKey.delete,
        shift: true,
      ): c.clearSelectionLabels,
      const SingleActivator(
        LogicalKeyboardKey.backspace,
        shift: true,
      ): c.clearSelectionLabels,
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => nudge(-1, 0),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => nudge(1, 0),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => nudge(0, 1),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => nudge(0, -1),
      const SingleActivator(
        LogicalKeyboardKey.arrowLeft,
        shift: true,
      ): () => nudgeOrMovePage(-1, 0),
      const SingleActivator(
        LogicalKeyboardKey.arrowRight,
        shift: true,
      ): () => nudgeOrMovePage(1, 0),
      const SingleActivator(
        LogicalKeyboardKey.arrowUp,
        shift: true,
      ): () => nudgeOrMovePage(0, 1),
      const SingleActivator(
        LogicalKeyboardKey.arrowDown,
        shift: true,
      ): () => nudgeOrMovePage(0, -1),
      const SingleActivator(
        LogicalKeyboardKey.arrowLeft,
        meta: true,
      ): () => resizeOrSelectPage(-1, 0),
      const SingleActivator(
        LogicalKeyboardKey.arrowRight,
        meta: true,
      ): () => resizeOrSelectPage(1, 0),
      const SingleActivator(
        LogicalKeyboardKey.arrowUp,
        control: true,
      ): () => resizeOrSelectPage(0, -1),
      const SingleActivator(
        LogicalKeyboardKey.arrowDown,
        control: true,
      ): () => resizeOrSelectPage(0, 1),
      const SingleActivator(LogicalKeyboardKey.enter):
          c.requestEditSelectionLabel,
      const SingleActivator(LogicalKeyboardKey.f2):
          c.requestEditSelectionLabel,
      const SingleActivator(
        LogicalKeyboardKey.enter,
        meta: true,
      ): c.duplicateSelectionFromEnter,
      const SingleActivator(
        LogicalKeyboardKey.enter,
        control: true,
      ): c.duplicateSelectionFromEnter,
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
        LogicalKeyboardKey.pageUp,
        meta: true,
        shift: true,
      ): () => c.selectRelativePage(-1),
      const SingleActivator(
        LogicalKeyboardKey.pageDown,
        control: true,
        shift: true,
      ): () => c.selectRelativePage(1),
      const SingleActivator(
        LogicalKeyboardKey.numpadAdd,
        meta: true,
        shift: true,
      ): () => adjustWholeLabelTextSize(1),
      const SingleActivator(
        LogicalKeyboardKey.numpadSubtract,
        control: true,
        shift: true,
      ): () => adjustWholeLabelTextSize(-1),
      const SingleActivator(
        LogicalKeyboardKey.bracketRight,
        meta: true,
        shift: true,
      ): () => adjustWholeLabelTextSize(1),
      const SingleActivator(
        LogicalKeyboardKey.bracketLeft,
        control: true,
        shift: true,
      ): () => adjustWholeLabelTextSize(-1),
      const SingleActivator(
        LogicalKeyboardKey.keyF,
        meta: true,
        alt: true,
        shift: true,
      ): c.bringSelectionForward,
      const SingleActivator(
        LogicalKeyboardKey.keyF,
        control: true,
        alt: true,
        shift: true,
      ): c.bringSelectionForward,
      const SingleActivator(
        LogicalKeyboardKey.keyB,
        meta: true,
        alt: true,
        shift: true,
      ): c.sendSelectionBackward,
      const SingleActivator(
        LogicalKeyboardKey.keyB,
        control: true,
        alt: true,
        shift: true,
      ): c.sendSelectionBackward,
      const SingleActivator(
        LogicalKeyboardKey.keyR,
        alt: true,
        shift: true,
      ): c.clearSelectedConnectorWaypoints,
      const SingleActivator(
        LogicalKeyboardKey.keyB,
        alt: true,
        shift: true,
      ): c.copyShapeData,
      const SingleActivator(
        LogicalKeyboardKey.keyE,
        alt: true,
        shift: true,
      ): () => c.pasteShapeData(includeLabel: true),
      const SingleActivator(
        LogicalKeyboardKey.keyC,
        alt: true,
        shift: true,
      ): c.copyTextStyle,
      const SingleActivator(
        LogicalKeyboardKey.keyV,
        alt: true,
        shift: true,
      ): c.pasteSelectionSize,
      const SingleActivator(
        LogicalKeyboardKey.keyF,
        alt: true,
        shift: true,
      ): c.copySelectionSize,
      const SingleActivator(
        LogicalKeyboardKey.keyX,
        alt: true,
        shift: true,
      ): c.selectChildren,
      const SingleActivator(
        LogicalKeyboardKey.keyT,
        alt: true,
        shift: true,
      ): c.selectSubtree,
      const SingleActivator(
        LogicalKeyboardKey.keyP,
        alt: true,
        shift: true,
      ): c.selectRelatedParent,
      const SingleActivator(
        LogicalKeyboardKey.keyS,
        alt: true,
        shift: true,
      ): c.selectSiblings,
      const SingleActivator(
        LogicalKeyboardKey.keyL,
        alt: true,
        shift: true,
      ): editLink,
      const SingleActivator(
        LogicalKeyboardKey.keyQ,
        alt: true,
        shift: true,
      ): () {
        if (c.editingConnectionPoints) {
          c.endEditConnectionPoints();
        } else {
          c.beginEditConnectionPoints();
        }
      },
      const SingleActivator(
        LogicalKeyboardKey.keyA,
        alt: true,
        shift: true,
      ): c.toggleConnectionArrows,
      const SingleActivator(
        LogicalKeyboardKey.keyO,
        alt: true,
        shift: true,
      ): c.toggleConnectionPoints,
      const SingleActivator(
        LogicalKeyboardKey.arrowUp,
        alt: true,
        shift: true,
      ): () => c.connectSelectionInDirection(0),
      const SingleActivator(
        LogicalKeyboardKey.arrowRight,
        alt: true,
        shift: true,
      ): () => c.connectSelectionInDirection(1),
      const SingleActivator(
        LogicalKeyboardKey.arrowDown,
        alt: true,
        shift: true,
      ): () => c.connectSelectionInDirection(2),
      const SingleActivator(
        LogicalKeyboardKey.arrowLeft,
        alt: true,
        shift: true,
      ): () => c.connectSelectionInDirection(3),
      const SingleActivator(
        LogicalKeyboardKey.tab,
        alt: true,
      ): c.selectParentShape,
      const SingleActivator(LogicalKeyboardKey.home): c.requestResetView,
      const SingleActivator(
        LogicalKeyboardKey.keyJ,
        meta: true,
      ): c.requestFitToWindow,
      const SingleActivator(
        LogicalKeyboardKey.keyJ,
        control: true,
      ): c.requestFitToWindow,
      const SingleActivator(
        LogicalKeyboardKey.keyH,
        meta: true,
        shift: true,
      ): c.requestFitToWindow,
      const SingleActivator(
        LogicalKeyboardKey.keyH,
        control: true,
        shift: true,
      ): c.requestFitToWindow,
      const SingleActivator(
        LogicalKeyboardKey.keyE,
        meta: true,
        shift: true,
      ): c.selectConnectors,
      const SingleActivator(
        LogicalKeyboardKey.keyE,
        control: true,
        shift: true,
      ): c.selectConnectors,
      const SingleActivator(
        LogicalKeyboardKey.keyS,
        meta: true,
        shift: true,
      ): saveAs,
      const SingleActivator(
        LogicalKeyboardKey.keyS,
        control: true,
        shift: true,
      ): saveAs,
      const SingleActivator(
        LogicalKeyboardKey.keyG,
        meta: true,
        shift: true,
      ): c.toggleGrid,
      const SingleActivator(
        LogicalKeyboardKey.keyG,
        control: true,
        shift: true,
      ): c.toggleGrid,
      const SingleActivator(
        LogicalKeyboardKey.home,
        meta: true,
      ): c.collapseSelection,
      const SingleActivator(
        LogicalKeyboardKey.home,
        control: true,
      ): c.collapseSelection,
      const SingleActivator(
        LogicalKeyboardKey.end,
        meta: true,
      ): c.expandSelection,
      const SingleActivator(
        LogicalKeyboardKey.end,
        control: true,
      ): c.expandSelection,
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): undo,
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): undo,
      const SingleActivator(
        LogicalKeyboardKey.keyY,
        meta: true,
        shift: true,
      ): c.autosizeSelection,
      const SingleActivator(
        LogicalKeyboardKey.keyY,
        control: true,
        shift: true,
      ): c.autosizeSelection,
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
    VoidCallback? onSaveAs,
    VoidCallback? onEditLink,
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
            onSaveAs: onSaveAs,
            onEditLink: onEditLink,
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

  testWidgets('Ctrl+Delete removes selection and incident connectors',
      (tester) async {
    final c = ctrlWithRect();
    final source = c.singleSelectedId!;
    c.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1.5,
        height: 1,
      ),
      5,
      3,
    );
    final target = c.singleSelectedId!;
    c.createConnector(2, 3, 5, 3,
        beginTarget: source, endTarget: target);
    final connector = c.singleSelectedId!;
    c.selectOnly(source);
    await pumpHarness(tester, c);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(c.currentPage!.findShapeById(source), isNull);
    expect(c.currentPage!.findShapeById(target), isNotNull);
    expect(c.currentPage!.findShapeById(connector), isNull);
    c.undo();
    expect(c.currentPage!.findShapeById(source), isNotNull);
    expect(c.currentPage!.findShapeById(connector), isNotNull);
  });

  testWidgets('Shift+Backspace clears selected labels in one undo step',
      (tester) async {
    final c = ctrlWithRect();
    final first = c.singleSelectedId!;
    c.setShapeText(first, 'Alpha');
    c.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.ellipse(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1,
        height: 1,
      ),
      5,
      3,
    );
    final second = c.singleSelectedId!;
    c.setShapeText(second, 'Beta');
    c.setSelection(<int>{first, second});
    await pumpHarness(tester, c);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(c.currentPage!.findShapeById(first)!.richText.plainText, isEmpty);
    expect(c.currentPage!.findShapeById(second)!.richText.plainText, isEmpty);
    c.undo();
    expect(c.currentPage!.findShapeById(first)!.richText.plainText, 'Alpha');
    expect(c.currentPage!.findShapeById(second)!.richText.plainText, 'Beta');
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

  testWidgets('page-aware arrow shortcuts navigate and reorder tabs',
      (tester) async {
    final c = EditorController()..newDocument();
    addTearDown(c.dispose);
    c
      ..addPage()
      ..addPage()
      ..selectBoundaryPage(last: false)
      ..clearSelection();
    final ids = c.document!.pages.map((page) => page.id).toList();
    await pumpHarness(tester, c);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(c.currentPageIndex, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(c.currentPageIndex, 2);
    expect(c.document!.pages.map((page) => page.id), <int>[
      ids[0],
      ids[2],
      ids[1],
    ]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(c.currentPageIndex, 1);
  });

  testWidgets('Cmd+Home collapses and Cmd+End expands selected container',
      (tester) async {
    final c = EditorController()..newDocument();
    addTearDown(c.dispose);
    final page = c.currentPage!;
    final container = VsdxShapeFactory.container(
      id: page.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    c.updateCurrentPage((p) => p.addShape(container));
    c.selectOnly(container.id);
    await pumpHarness(tester, c);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(c.isCollapsed(container.id), isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(c.isCollapsed(container.id), isFalse);
  });

  testWidgets(
      'Enter requests label edit and Cmd+Enter duplicates a table row',
      (tester) async {
    final c = EditorController()..newDocument();
    addTearDown(c.dispose);
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
    final tableId = c.singleSelectedId!;
    final cell = TableOps.cellsOf(c.currentPage!.findShapeById(tableId)!).first;
    c.selectOnly(cell.id);
    await pumpHarness(tester, c);

    final requestSerial = c.textEditRequestSerial;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(c.textEditRequestSerial, requestSerial + 1);
    expect(c.textEditRequestShapeId, cell.id);
    expect(
      TableOps.dimensions(c.currentPage!.findShapeById(tableId)!).rows,
      2,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(
      TableOps.dimensions(c.currentPage!.findShapeById(tableId)!).rows,
      3,
    );
    expect(
      c.selection.every(
        (id) => TableOps.cellRow(c.currentPage!.findShapeById(id)!) == 1,
      ),
      isTrue,
    );

    c.selectOnly(tableId);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(c.currentPage!.shapes, hasLength(2));
    expect(
      TableOps.isTable(c.currentPage!.findShapeById(c.singleSelectedId!)!),
      isTrue,
    );
  });

  testWidgets(
      'F2, Home, Cmd+J, Cmd+Shift+H and Cmd+Shift+G match draw.io commands',
      (tester) async {
    final c = ctrlWithRect();
    await pumpHarness(tester, c);

    final editSerial = c.textEditRequestSerial;
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    expect(c.textEditRequestSerial, editSerial + 1);

    final resetSerial = c.resetViewSerial;
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(c.resetViewSerial, resetSerial + 1);

    final fitSerial = c.fitSerial;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(c.fitSerial, fitSerial + 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(c.fitSerial, fitSerial + 2);

    final gridWasVisible = c.showGrid;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(c.showGrid, isNot(gridWasVisible));
  });

  testWidgets('Cmd+Shift+E selects connectors', (tester) async {
    final c = ctrlWithRect();
    final source = c.singleSelectedId!;
    c.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1.5,
        height: 1,
      ),
      6,
      3,
    );
    final target = c.singleSelectedId!;
    c.createConnector(
      2,
      3,
      6,
      3,
      beginTarget: source,
      endTarget: target,
    );
    final connector = c.singleSelectedId!;
    c.clearSelection();
    await pumpHarness(tester, c);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(c.selection, <int>{connector});
  });

  testWidgets('Ctrl+Enter duplicates an ordinary multi-selection',
      (tester) async {
    final c = ctrlWithRect();
    final firstId = c.singleSelectedId!;
    c.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.ellipse(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1,
        height: 1,
      ),
      5,
      3,
    );
    final secondId = c.singleSelectedId!;
    c.setSelection(<int>{firstId, secondId});
    await pumpHarness(tester, c);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(c.currentPage!.shapes, hasLength(4));
    expect(c.selection, hasLength(2));
    expect(c.selection, isNot(contains(firstId)));
    expect(c.selection, isNot(contains(secondId)));
  });

  testWidgets('Delete removes the row of a selected table cell',
      (tester) async {
    final c = EditorController()..newDocument();
    addTearDown(c.dispose);
    c.addShapeFromBuilderAt(
      (id, cx, cy) => TableOps.assembleTable(
        tableId: id,
        pinX: cx,
        pinY: cy,
        width: 3,
        height: 3,
        rows: 3,
        cols: 2,
      ),
      3,
      4,
    );
    final tableId = c.singleSelectedId!;
    final cell = TableOps.cellsOf(c.currentPage!.findShapeById(tableId)!)
        .firstWhere((shape) => TableOps.cellRow(shape) == 1);
    c.selectOnly(cell.id);
    await pumpHarness(tester, c);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();

    expect(
      TableOps.dimensions(c.currentPage!.findShapeById(tableId)!).rows,
      2,
    );
    expect(c.selection, <int>{tableId});
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

  testWidgets('Cmd+arrow resizes the selected shape by one point',
      (tester) async {
    final c = ctrlWithRect();
    final id = c.selection.single;
    final before = c.currentPage!.findShapeById(id)!;
    await pumpHarness(tester, c);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    final after = c.currentPage!.findShapeById(id)!;
    expect(after.width, closeTo(before.width + 1 / 72, 1e-9));
    expect(after.height, before.height);
  });

  testWidgets('Cmd+Shift+Y autosizes the selected shape', (tester) async {
    final c = ctrlWithRect();
    final id = c.selection.single;
    c.setShapeText(id, 'First line\nSecond line\nThird line');
    final beforeHeight = c.currentPage!.findShapeById(id)!.height;
    await pumpHarness(tester, c);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(
      c.currentPage!.findShapeById(id)!.height,
      isNot(closeTo(beforeHeight, 1e-9)),
    );
  });

  testWidgets('Cmd+Shift+NumPad plus and } adjust the whole selected label', (
    tester,
  ) async {
    final c = ctrlWithRect();
    final id = c.selection.single;
    c.setShapeText(id, 'Label');
    final before =
        c.currentPage!
            .findShapeById(id)!
            .richText
            .runs
            .first
            .charStyle
            .fontSizeInches *
        72;
    await pumpHarness(tester, c);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadAdd);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    final after =
        c.currentPage!
            .findShapeById(id)!
            .richText
            .runs
            .first
            .charStyle
            .fontSizeInches *
        72;
    expect(after, closeTo(before + 2, 1e-9));
  });

  testWidgets('draw.io single-layer ordering chords move one z-step',
      (tester) async {
    final c = ctrlWithRect();
    final first = c.singleSelectedId!;
    c.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.ellipse(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1,
        height: 1,
      ),
      4,
      3,
    );
    final second = c.singleSelectedId!;
    c.selectOnly(first);
    await pumpHarness(tester, c);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(c.currentPage!.shapes.map((s) => s.id), <int>[second, first]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(c.currentPage!.shapes.map((s) => s.id), <int>[first, second]);
  });

  testWidgets('NumPad text-size chord is deferred in a regular text field', (
    tester,
  ) async {
    final c = ctrlWithRect();
    final id = c.selection.single;
    c.setShapeText(id, 'Label');
    final before = c.currentPage!
        .findShapeById(id)!
        .richText
        .runs
        .first
        .charStyle;
    final input = TextEditingController(text: 'query');
    addTearDown(input.dispose);
    await pumpHarness(
      tester,
      c,
      body: TextField(controller: input, autofocus: true),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadSubtract);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(
      c.currentPage!
          .findShapeById(id)!
          .richText
          .runs
          .first
          .charStyle
          .fontSizeInches,
      before.fontSizeInches,
    );
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

  testWidgets('Alt+Shift+L and Q edit links and connection points',
      (tester) async {
    final c = ctrlWithRect();
    var editLinkHits = 0;
    await pumpHarness(tester, c, onEditLink: () => editLinkHits++);

    Future<void> altShift(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
    }

    await altShift(LogicalKeyboardKey.keyL);
    expect(editLinkHits, 1);

    await altShift(LogicalKeyboardKey.keyQ);
    expect(c.editingConnectionPoints, isTrue);
    expect(c.singleSelected!.connectionPoints, isNotEmpty);

    await altShift(LogicalKeyboardKey.keyQ);
    expect(c.editingConnectionPoints, isFalse);
  });

  testWidgets('Alt+Shift+A and O toggle connection affordances',
      (tester) async {
    final c = ctrlWithRect();
    await pumpHarness(tester, c);

    Future<void> altShift(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
    }

    expect(c.connectionArrowsEnabled, isTrue);
    expect(c.connectionPointsEnabled, isTrue);
    await altShift(LogicalKeyboardKey.keyA);
    await altShift(LogicalKeyboardKey.keyO);
    expect(c.connectionArrowsEnabled, isFalse);
    expect(c.connectionPointsEnabled, isFalse);

    await altShift(LogicalKeyboardKey.keyA);
    await altShift(LogicalKeyboardKey.keyO);
    expect(c.connectionArrowsEnabled, isTrue);
    expect(c.connectionPointsEnabled, isTrue);
  });

  testWidgets('Cmd/Ctrl+R reverses a selected connector', (tester) async {
    final c = ctrlWithRect();
    final source = c.singleSelectedId!;
    c.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1.5,
        height: 1,
      ),
      6,
      3,
    );
    final target = c.singleSelectedId!;
    c.createConnector(
      2,
      3,
      6,
      3,
      beginTarget: source,
      endTarget: target,
    );
    final connector = c.singleSelectedId!;
    await pumpHarness(tester, c);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    final rows = c.currentPage!.connects
        .where((connect) => connect.fromSheetId == connector)
        .toList();
    expect(rows.singleWhere((connect) => connect.isBegin).toSheetId, target);
    expect(rows.singleWhere((connect) => connect.isEnd).toSheetId, source);
  });

  testWidgets('Alt+Shift+B/E copies data and pastes the source label',
      (tester) async {
    final c = ctrlWithRect();
    final source = c.singleSelectedId!;
    c.setShapeText(source, 'Source');
    c.setShapeProperties(source, const <VsdxUserProperty>[
      VsdxUserProperty(name: 'Owner', value: 'Alice'),
    ]);
    c.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1.5,
        height: 1,
      ),
      5,
      3,
    );
    final target = c.singleSelectedId!;
    c.setShapeText(target, 'Target');
    c.selectOnly(source);
    await pumpHarness(tester, c);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();

    c.selectOnly(target);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();

    final pasted = c.currentPage!.findShapeById(target)!;
    expect(pasted.userProperties.single.name, 'Owner');
    expect(pasted.userProperties.single.value, 'Alice');
    expect(pasted.richText.plainText, 'Source');
  });

  testWidgets('Alt+Shift tree shortcuts follow connector relationships',
      (tester) async {
    final c = ctrlWithRect();
    final root = c.singleSelectedId!;
    c.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1,
        height: 0.6,
      ),
      4,
      4,
    );
    final left = c.singleSelectedId!;
    c.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1,
        height: 0.6,
      ),
      6,
      4,
    );
    final right = c.singleSelectedId!;
    c.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1,
        height: 0.6,
      ),
      4,
      6,
    );
    final leaf = c.singleSelectedId!;
    c
      ..createConnector(
        2,
        3,
        4,
        4,
        beginTarget: root,
        endTarget: left,
      )
      ..createConnector(
        2,
        3,
        6,
        4,
        beginTarget: root,
        endTarget: right,
      )
      ..createConnector(
        4,
        4,
        4,
        6,
        beginTarget: left,
        endTarget: leaf,
      )
      ..selectOnly(root);
    await pumpHarness(tester, c);

    Future<void> altShift(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
    }

    await altShift(LogicalKeyboardKey.keyX);
    expect(c.selection, <int>{left, right});

    c.selectOnly(root);
    await altShift(LogicalKeyboardKey.keyT);
    final connectors = c.currentPage!.shapes
        .where((shape) => shape.isGlueableConnector)
        .map((shape) => shape.id);
    expect(c.selection, <int>{root, left, right, leaf, ...connectors});

    c.selectOnly(left);
    await altShift(LogicalKeyboardKey.keyP);
    expect(c.singleSelectedId, root);

    c.selectOnly(left);
    await altShift(LogicalKeyboardKey.keyS);
    expect(c.selection, <int>{left, right});
  });

  testWidgets('Alt+Shift+F/V copies and pastes shape size', (tester) async {
    final c = ctrlWithRect();
    final source = c.singleSelectedId!;
    c.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 3,
        height: 2,
      ),
      5,
      3,
    );
    final target = c.singleSelectedId!;
    c.selectOnly(source);
    await pumpHarness(tester, c);

    Future<void> altShift(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
    }

    await altShift(LogicalKeyboardKey.keyF);
    c.selectOnly(target);
    await altShift(LogicalKeyboardKey.keyV);

    final resized = c.currentPage!.findShapeById(target)!;
    expect(resized.width, 1.5);
    expect(resized.height, 1);
  });

  testWidgets('Alt+Shift+C copies only text style',
      (tester) async {
    final c = ctrlWithRect();
    final source = c.singleSelectedId!;
    c
      ..setShapeText(source, 'Source')
      ..setBold(true);
    c.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1.5,
        height: 1,
      ),
      5,
      3,
    );
    final target = c.singleSelectedId!;
    c
      ..setShapeText(target, 'Target')
      ..setFillColor(const VsdxColor(0xFF00AA00))
      ..selectOnly(source);
    await pumpHarness(tester, c);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();

    c.selectOnly(target);
    c.pasteTextStyle();
    await tester.pump();

    final pasted = c.currentPage!.findShapeById(target)!;
    expect(pasted.richText.plainText, 'Target');
    expect(pasted.richText.runs.first.charStyle.style.bold, isTrue);
    expect(pasted.fill.foreground?.value, 0xFF00AA00);
  });

  testWidgets('Alt+Shift+arrow clones and connects without canvas focus',
      (tester) async {
    final c = ctrlWithRect();
    final before = c.currentPage!.shapes.length;
    await pumpHarness(tester, c);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();

    expect(c.currentPage!.shapes, hasLength(before + 2));
    expect(c.currentPage!.connects, hasLength(2));
  });

  testWidgets('Alt+Shift+arrow is deferred while editing text',
      (tester) async {
    final c = ctrlWithRect();
    final before = c.currentPage!.shapes.length;
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

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();

    expect(c.currentPage!.shapes, hasLength(before));
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

  testWidgets('modified delete shortcuts are deferred in a text field',
      (tester) async {
    final c = ctrlWithRect();
    final id = c.selection.single;
    final search = TextEditingController(text: 'alpha beta');
    addTearDown(search.dispose);
    await pumpHarness(
      tester,
      c,
      body: TextField(controller: search, autofocus: true),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    expect(
      EditorCallbackShortcuts.isTextEditingShortcut(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.delete,
          logicalKey: LogicalKeyboardKey.delete,
          timeStamp: Duration.zero,
        ),
      ),
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(c.currentPage!.findShapeById(id), isNotNull);
  });

  testWidgets('Enter edit and duplicate shortcuts are deferred in a text field',
      (tester) async {
    final c = ctrlWithRect();
    final search = TextEditingController(text: 'abc');
    addTearDown(search.dispose);
    await pumpHarness(
      tester,
      c,
      body: TextField(controller: search, autofocus: true),
    );
    await tester.pump();

    expect(
      EditorCallbackShortcuts.isTextEditingShortcut(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.enter,
          logicalKey: LogicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        ),
      ),
      isTrue,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    expect(
      EditorCallbackShortcuts.isTextEditingShortcut(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.enter,
          logicalKey: LogicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        ),
      ),
      isTrue,
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
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

  testWidgets('Cmd+Shift+S remains a Save As document chord while typing',
      (tester) async {
    final c = ctrlWithRect();
    var saveAsHits = 0;
    final search = TextEditingController(text: 'hello');
    addTearDown(search.dispose);

    await pumpHarness(
      tester,
      c,
      onSaveAs: () => saveAsHits++,
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
    expect(
      EditorCallbackShortcuts.isTextEditingShortcut(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.home,
          logicalKey: LogicalKeyboardKey.home,
          timeStamp: Duration.zero,
        ),
      ),
      isTrue,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(saveAsHits, 1);
  });
}
