import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/quick_add_picker.dart';
import 'package:visioeditor/editor/stencils.dart';

void main() {
  test('quickAddStencils offers everyday General/Flowchart shapes', () {
    final list = quickAddStencils();
    expect(list, isNotEmpty);
    expect(list.length, lessThanOrEqualTo(35));
    final names = list.map((s) => s.name).toSet();
    expect(names, contains('Rectangle'));
    expect(names, contains('Diamond'));
    expect(names, contains('Decision'));
    expect(names, isNot(contains('Table')));
    expect(names, isNot(contains('Text')));
    expect(names, isNot(contains('Container')));
    // No duplicate names across General + Flowchart merges.
    expect(names.length, list.length);
  });

  testWidgets('QuickAddPicker selects stencil and dismisses', (tester) async {
    Stencil? chosen;
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickAddPicker(
            anchorGlobal: const Offset(120, 120),
            onSelect: (s) => chosen = s,
            onDuplicate: () {},
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // First grid cell after the Duplicate row.
    final cells = find.byType(InkWell);
    expect(cells, findsWidgets);
    // Skip the Duplicate InkWell (first); tap a shape cell.
    await tester.tap(cells.at(1));
    await tester.pumpAndSettle();
    expect(chosen, isNotNull);
    expect(dismissed, isFalse); // select path calls onSelect, not onDismiss

    // Outside tap dismisses.
    chosen = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickAddPicker(
            anchorGlobal: const Offset(120, 120),
            onSelect: (s) => chosen = s,
            onDuplicate: () {},
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    dismissed = false;
    // Tap the transparent barrier (Stack's first child fills the screen).
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
    expect(chosen, isNull);
  });

  testWidgets('QuickAddPicker duplicate row fires callback', (tester) async {
    var duplicated = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: QuickAddPicker(
            anchorGlobal: const Offset(200, 200),
            onSelect: (_) {},
            onDuplicate: () => duplicated = true,
            onDismiss: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.copy_outlined));
    await tester.pumpAndSettle();
    expect(duplicated, isTrue);
  });
}
