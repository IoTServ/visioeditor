import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/edit_tooltip_dialog.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('shape tooltip preserves unrelated User cells and clears cleanly', () {
    final base = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
    ).copyWith(
      userCells: const [
        VsdxUserCell(name: 'foreignMeta', value: 'keep'),
      ],
    );

    final configured = base.withTooltip('  Review owner\nbefore approval  ');
    expect(configured.tooltip, 'Review owner\nbefore approval');
    expect(
      configured.userCells.firstWhere((cell) => cell.name == 'foreignMeta').value,
      'keep',
    );

    final cleared = configured.withTooltip('  ');
    expect(cleared.tooltip, isNull);
    expect(cleared.userCells.single.name, 'foreignMeta');
  });

  test('controller tooltip edit is undoable and honours the display toggle', () {
    final controller = EditorController()..newDocument();
    addTearDown(controller.dispose);
    controller.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 2,
        height: 1,
      ),
      3,
      4,
    );
    final id = controller.singleSelectedId!;

    controller.setShapeTooltip(id, 'Owner: Alice');
    expect(controller.currentPage!.findShapeById(id)!.tooltip, 'Owner: Alice');
    final documentBeforeNoop = controller.document;
    controller.setShapeTooltip(id, '  Owner: Alice  ');
    expect(identical(controller.document, documentBeforeNoop), isTrue);
    controller.undo();
    expect(controller.currentPage!.findShapeById(id)!.tooltip, isNull);
    controller.redo();
    expect(controller.currentPage!.findShapeById(id)!.tooltip, 'Owner: Alice');

    expect(controller.canEditTooltip, isTrue);
    controller.toggleLock();
    expect(controller.canEditTooltip, isFalse);
    controller.setShapeTooltip(id, 'Owner: Bob');
    expect(controller.currentPage!.findShapeById(id)!.tooltip, 'Owner: Alice');

    expect(controller.tooltipsEnabled, isTrue);
    controller.toggleTooltips();
    expect(controller.tooltipsEnabled, isFalse);
  });

  testWidgets('Edit Tooltip dialog applies and clears text', (tester) async {
    final controller = EditorController()..newDocument();
    addTearDown(controller.dispose);
    controller.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 2,
        height: 1,
      ),
      3,
      4,
    );
    final id = controller.singleSelectedId!;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showEditTooltipDialog(context, controller, id),
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );

    Future<void> open() async {
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
    }

    await open();
    await tester.enterText(
      find.byKey(const ValueKey('edit-tooltip-field')),
      'Line one\nLine two',
    );
    await tester.tap(find.byKey(const ValueKey('apply-tooltip')));
    await tester.pumpAndSettle();
    expect(
      controller.currentPage!.findShapeById(id)!.tooltip,
      'Line one\nLine two',
    );

    await open();
    await tester.enterText(
      find.byKey(const ValueKey('edit-tooltip-field')),
      '',
    );
    await tester.tap(find.byKey(const ValueKey('apply-tooltip')));
    await tester.pumpAndSettle();
    expect(controller.currentPage!.findShapeById(id)!.tooltip, isNull);
  });
}
