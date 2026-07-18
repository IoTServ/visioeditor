import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

/// Minimal harness that mirrors app-level [CallbackShortcuts] for Delete /
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

  Map<ShortcutActivator, VoidCallback> bindingsFor(EditorController c) {
    void deleteSel() {
      if (c.hasSelection || c.editingConnectionPoints) c.deleteSelection();
    }

    void nudge(double dx, double dy) {
      if (!c.hasSelection || c.editingConnectionPoints) return;
      final step = c.snapToGrid ? c.gridInches : 0.1;
      c.moveSelectionBy(dx * step, dy * step);
    }

    return <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.delete): deleteSel,
      const SingleActivator(LogicalKeyboardKey.backspace): deleteSel,
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => nudge(-1, 0),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => nudge(1, 0),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => nudge(0, 1),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => nudge(0, -1),
    };
  }

  Future<void> pumpHarness(WidgetTester tester, EditorController c) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: CallbackShortcuts(
          bindings: bindingsFor(c),
          child: Scaffold(
            body: Focus(
              focusNode: focus,
              autofocus: true,
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    focus.requestFocus();
    await tester.pump();
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
}
