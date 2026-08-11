import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/stencil_library_catalog.dart';
import 'package:visioeditor/editor/stencil_library_dialog.dart';
import 'package:visioeditor/editor/stencils.dart';

void main() {
  test('library paths hide source labels and merge equivalent categories', () {
    expect(stencilLibraryPath('Draw.io / Electrical / Resistors'), <String>[
      'Electrical',
      'Resistors',
    ]);
    expect(
      stencilLibraryPath('Draw.io JS / ArchiMate3 / Archimate 3.2 / Generic'),
      <String>['ArchiMate 3.2', 'Generic'],
    );
    expect(stencilLibraryDisplayName('Draw.io JS / Basic / basic'), 'Basic');

    final tree = buildStencilLibraryTree(kStencilGroups);
    final allNodes = <StencilLibraryNode>[];
    void visit(StencilLibraryNode node) {
      allNodes.add(node);
      node.children.forEach(visit);
    }

    tree.forEach(visit);
    expect(
      allNodes.any((node) => node.label.toLowerCase().contains('draw.io')),
      isFalse,
    );
    expect(
      allNodes.expand((node) => node.groups).map((group) => group.name).toSet(),
      kStencilGroups.map((group) => group.name).toSet(),
    );

    final basic = tree.singleWhere((node) => node.label == 'Basic');
    expect(basic.groups.length, greaterThanOrEqualTo(2));
  });

  testWidgets('browser exposes checkable tree and live preview panes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StencilLibraryDialog(
            initialSelection: const <String>{},
            thumbnailBuilder: (context, stencil) =>
                const ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('stencil-library-tree')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('stencil-library-preview')),
      findsOneWidget,
    );
    expect(find.textContaining('Draw.io'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('AWS'),
      180,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('stencil-library-tree')),
        matching: find.byType(Scrollable),
      ),
      maxScrolls: 30,
    );
    final awsRow = find.byKey(const ValueKey('stencil-library-node-aws'));
    expect(awsRow, findsOneWidget);
    await tester.tap(
      find.descendant(of: awsRow, matching: find.byType(Checkbox)),
    );
    await tester.pump();
    expect(
      tester
          .widget<Checkbox>(
            find.descendant(of: awsRow, matching: find.byType(Checkbox)),
          )
          .value,
      isTrue,
    );

    await tester.tap(find.text('AWS').first);
    await tester.pump();
    expect(find.text('Compute'), findsOneWidget);
    expect(find.textContaining('Draw.io'), findsNothing);
  });

  testWidgets('multi-keyword search previews and returns a shape to insert', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    StencilLibraryDialogResult? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                chosen = await showDialog<StencilLibraryDialogResult>(
                  context: context,
                  builder: (context) => StencilLibraryDialog(
                    initialSelection: const <String>{},
                    thumbnailBuilder: (context, stencil) =>
                        const ColoredBox(color: Colors.blue),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'decision flowchart');
    await tester.pump();

    expect(
      find.textContaining('Search shapes: decision flowchart'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stencil-library-clear-search')),
      findsOneWidget,
    );
    expect(find.text('Decision'), findsWidgets);
    expect(find.textContaining('Draw.io'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('stencil-library-preview-tile-0')),
    );
    await tester.pumpAndSettle();

    expect(chosen, isNotNull);
    expect(chosen!.stencil, isNotNull);
    expect(chosen!.stencil!.name.toLowerCase(), contains('decision'));
    expect(chosen!.selectedGroups, contains(chosen!.stencil!.group));
  });
}
