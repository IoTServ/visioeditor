import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/editor/page_canvas.dart';
import 'package:visioeditor/main.dart';
import 'package:visioeditor/settings/app_settings.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EditorController controller() {
    final value = EditorController()..newDocument();
    addTearDown(value.dispose);
    return value;
  }

  int rectangle(EditorController value, double x, {double width = 2}) {
    value.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: width,
        height: 1,
      ),
      x,
      5,
    );
    return value.singleSelectedId!;
  }

  double maxPoints(VsdxShape shape) => shape.richText.runs
      .map((run) => run.charStyle.fontSizeInches * 72)
      .reduce((a, b) => a > b ? a : b);

  test('Automatic Text Size refits on label and bounds changes', () {
    final value = controller();
    final id = rectangle(value, 2);
    value
      ..setShapeText(id, 'Short')
      ..setAutosizeText(true);

    var shape = value.currentPage!.findShapeById(id)!;
    final shortSize = maxPoints(shape);
    expect(shape.autosizeText, isTrue);
    expect(shortSize, greaterThan(12));

    value.setShapeText(
      id,
      'A much longer label that needs several wrapped lines to fit',
    );
    shape = value.currentPage!.findShapeById(id)!;
    final longSize = maxPoints(shape);
    expect(longSize, lessThan(shortSize));

    value.resizeShape(
      id,
      pinX: shape.pinX,
      pinY: shape.pinY,
      width: 3,
      height: 1.5,
    );
    shape = value.currentPage!.findShapeById(id)!;
    expect(maxPoints(shape), greaterThan(longSize));

    final beforeMargins = maxPoints(shape);
    value.setTextMargins(left: 0.4, right: 0.4, top: 0.2, bottom: 0.2);
    shape = value.currentPage!.findShapeById(id)!;
    expect(maxPoints(shape), lessThan(beforeMargins));
  });

  test(
    'rich-text ratios, fitted size, undo and disabled state are preserved',
    () {
      final value = controller();
      final id = rectangle(value, 2);
      value.updateCurrentPage(
        (page) => page.updateShapeById(
          id,
          (shape) => shape.copyWith(
            text: 'Title body',
            richText: shape.richText.copyWith(
              runs: const <VsdxTextRun>[
                VsdxTextRun(
                  text: 'Title ',
                  charStyle: VsdxCharStyle(fontSizeInches: 20 / 72),
                ),
                VsdxTextRun(
                  text: 'body',
                  charStyle: VsdxCharStyle(fontSizeInches: 10 / 72),
                ),
              ],
            ),
          ),
        ),
      );

      value.setAutosizeText(true);
      var shape = value.currentPage!.findShapeById(id)!;
      final sizes = shape.richText.runs
          .map((run) => run.charStyle.fontSizeInches)
          .toList();
      expect(sizes.first / sizes.last, closeTo(2, 1e-9));
      value.undo();
      expect(value.currentPage!.findShapeById(id)!.autosizeText, isFalse);
      value.redo();

      shape = value.currentPage!.findShapeById(id)!;
      final fitted = maxPoints(shape);
      value.setAutosizeText(false);
      shape = value.currentPage!.findShapeById(id)!;
      expect(shape.autosizeText, isFalse);
      expect(maxPoints(shape), closeTo(fitted, 1e-9));
    },
  );

  test('User metadata, VSDX and style workflows carry autosizeText', () {
    final value = controller();
    final source = rectangle(value, 2);
    value
      ..setShapeText(source, 'Source label')
      ..updateCurrentPage(
        (page) => page.updateShapeById(
          source,
          (shape) => shape.copyWith(
            userCells: <VsdxUserCell>[
              ...shape.userCells,
              const VsdxUserCell(name: 'foreignMeta', value: 'keep'),
            ],
          ),
        ),
      )
      ..setAutosizeText(true)
      ..copyStyle();

    final target = rectangle(value, 5);
    value
      ..setShapeText(target, 'Target')
      ..pasteStyle();
    expect(value.currentPage!.findShapeById(target)!.autosizeText, isTrue);

    value
      ..setSelection(<int>[source])
      ..copyTextStyle()
      ..setSelection(<int>[target])
      ..setAutosizeText(false)
      ..pasteTextStyle();
    expect(value.currentPage!.findShapeById(target)!.autosizeText, isTrue);

    value
      ..setSelection(<int>[source])
      ..setSelectionAsDefaultStyle();
    final inherited = rectangle(value, 8);
    value.setShapeText(inherited, 'Inherited automatic label');
    expect(value.currentPage!.findShapeById(inherited)!.autosizeText, isTrue);
    value.clearDefaultStyle();

    final reopened = const DocumentParser()
        .parse(value.exportToBytes())
        .pages
        .single
        .findShapeById(source)!;
    expect(reopened.autosizeText, isTrue);
    expect(
      reopened.userCells
          .singleWhere((cell) => cell.name == 'foreignMeta')
          .value,
      'keep',
    );
    expect(
      maxPoints(reopened),
      closeTo(maxPoints(value.currentPage!.findShapeById(source)!), 1e-4),
    );
  });

  test(
    'Automatic Text Size is vertex-only and locked shapes are protected',
    () {
      final value = controller();
      final vertex = rectangle(value, 2);
      value.setShapeText(vertex, 'Vertex');
      value
        ..setTool(EditorTool.line)
        ..createShapeByDrag(1, 3, 4, 3);
      final edge = value.singleSelectedId!;
      value.setSelection(<int>[vertex, edge]);
      expect(value.canSetAutosizeText, isTrue);
      value.setAutosizeText(true);
      expect(value.currentPage!.findShapeById(vertex)!.autosizeText, isTrue);
      expect(value.currentPage!.findShapeById(edge)!.autosizeText, isFalse);

      value.updateCurrentPage(
        (page) => page.updateShapeById(
          vertex,
          (shape) => shape.copyWith(locked: true),
        ),
      );
      value
        ..setSelection(<int>[vertex])
        ..setAutosizeText(false);
      expect(value.currentPage!.findShapeById(vertex)!.autosizeText, isTrue);
      expect(value.canSetAutosizeText, isFalse);
    },
  );

  testWidgets('Format Text exposes Automatic Text Size', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = await AppSettings.load();
    await tester.pumpWidget(VisioEditorApp(settings: settings));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'New drawing'));
    await tester.pumpAndSettle();

    final canvas = tester.widget<PageCanvas>(find.byType(PageCanvas));
    final id = rectangle(canvas.controller, 2);
    canvas.controller.setShapeText(id, 'Automatic label');
    await tester.pumpAndSettle();

    final scrollable = find.ancestor(
      of: find.text('Arrange'),
      matching: find.byWidgetPredicate((widget) => widget is Scrollable),
    );
    final state = tester.state<ScrollableState>(scrollable);
    final autosize = find.byKey(const ValueKey('autosize-text-switch'));
    for (var i = 0; i < 30 && autosize.evaluate().isEmpty; i++) {
      state.position.jumpTo(
        (state.position.pixels + 260).clamp(0, state.position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
    }
    expect(autosize, findsOneWidget);
    await Scrollable.ensureVisible(tester.element(autosize), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(autosize);
    await tester.pumpAndSettle();
    expect(canvas.controller.selectedAutosizeText, isTrue);
    expect(find.text('Automatic Text Size'), findsOneWidget);
  });
}
