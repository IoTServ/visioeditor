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

  int rectangle(EditorController value, double x) {
    value.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 2,
        height: 1,
      ),
      x,
      5,
    );
    final id = value.singleSelectedId!;
    value.setShapeText(id, 'Advanced label');
    return id;
  }

  test('Text Opacity is one undo step and round-trips through ColorTrans', () {
    final value = controller();
    final id = rectangle(value, 2);

    value.setTextColor(VsdxColor.black);
    value
      ..beginTransaction()
      ..setTextOpacity(0.7, transient: true)
      ..setTextOpacity(0.35, transient: true)
      ..commitTransaction();

    expect(value.selectedTextOpacity, closeTo(0.35, 1e-9));
    expect(
      value.currentPage!
          .findShapeById(id)!
          .richText
          .runs
          .first
          .charStyle
          .transparency,
      closeTo(0.65, 1e-9),
    );
    value.undo();
    expect(value.selectedTextOpacity, closeTo(1, 1e-9));
    value.redo();

    final reopened = const DocumentParser()
        .parse(value.exportToBytes())
        .pages
        .single
        .findShapeById(id)!;
    expect(
      reopened.richText.runs.first.charStyle.transparency,
      closeTo(0.65, 1e-6),
    );
    final svg = VsdxToSvgSerializer().serializePage(value.currentPage!);
    expect(svg, contains('fill-opacity="0.35"'));
  });

  test('Label Border preserves User rows and Canvas/SVG export semantics', () {
    final value = controller();
    final id = rectangle(value, 2);
    value.updateCurrentPage(
      (page) => page.updateShapeById(
        id,
        (shape) => shape.copyWith(
          userCells: const <VsdxUserCell>[
            VsdxUserCell(name: 'foreignMeta', value: 'keep'),
          ],
        ),
      ),
    );
    value.setLabelBorderColor(const VsdxColor(0xFF1565C0));

    final changed = value.currentPage!.findShapeById(id)!;
    expect(changed.labelBorderColor, const VsdxColor(0xFF1565C0));
    expect(
      changed.userCells.singleWhere((cell) => cell.name == 'foreignMeta').value,
      'keep',
    );
    expect(
      changed.userCells
          .singleWhere((cell) => cell.name == VsdxShape.userLabelBorderColor)
          .value,
      '#1565C0',
    );

    final svg = VsdxToSvgSerializer().serializePage(value.currentPage!);
    expect(svg, contains('stroke="#1565c0"'));
    expect(svg, contains('stroke-width="0.01"'));

    final reopened = const DocumentParser()
        .parse(value.exportToBytes())
        .pages
        .single
        .findShapeById(id)!;
    expect(reopened.labelBorderColor, const VsdxColor(0xFF1565C0));
    expect(
      reopened.userCells
          .singleWhere((cell) => cell.name == 'foreignMeta')
          .value,
      'keep',
    );

    value.clearLabelBorderColor();
    expect(value.currentPage!.findShapeById(id)!.labelBorderColor, isNull);
  });

  test('Copy/Paste Style and default style carry advanced label styling', () {
    final value = controller();
    final source = rectangle(value, 2);
    value
      ..setTextOpacity(0.4)
      ..setLabelBorderColor(const VsdxColor(0xFFE53935))
      ..copyStyle();

    final target = rectangle(value, 5);
    value.pasteStyle();
    var targetShape = value.currentPage!.findShapeById(target)!;
    expect(targetShape.labelBorderColor, const VsdxColor(0xFFE53935));
    expect(
      targetShape.richText.runs.first.charStyle.transparency,
      closeTo(0.6, 1e-9),
    );

    value
      ..setSelection(<int>[source])
      ..setSelectionAsDefaultStyle();
    final created = rectangle(value, 8);
    targetShape = value.currentPage!.findShapeById(created)!;
    expect(targetShape.labelBorderColor, const VsdxColor(0xFFE53935));
    expect(
      targetShape.richText.runs.first.charStyle.transparency,
      closeTo(0.6, 1e-9),
    );
  });

  testWidgets('Format exposes draw.io Text Opacity and Label Border', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = await AppSettings.load();
    await tester.pumpWidget(VisioEditorApp(settings: settings));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'New drawing'));
    await tester.pumpAndSettle();

    final canvas = tester.widget<PageCanvas>(find.byType(PageCanvas));
    rectangle(canvas.controller, 2);
    await tester.pumpAndSettle();

    final scrollable = find.ancestor(
      of: find.text('Arrange'),
      matching: find.byWidgetPredicate((widget) => widget is Scrollable),
    );
    final state = tester.state<ScrollableState>(scrollable);
    for (
      var i = 0;
      i < 30 &&
          find.byKey(const ValueKey('text-opacity-slider')).evaluate().isEmpty;
      i++
    ) {
      state.position.jumpTo(
        (state.position.pixels + 260).clamp(0, state.position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
    }
    final opacity = find.byKey(const ValueKey('text-opacity-slider'));
    expect(opacity, findsOneWidget);
    await tester.ensureVisible(opacity);
    await tester.pumpAndSettle();
    expect(find.text('Text Opacity'), findsOneWidget);
    expect(find.text('Label Border'), findsOneWidget);

    final slider = find.descendant(of: opacity, matching: find.byType(Slider));
    await tester.drag(slider, const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(canvas.controller.selectedTextOpacity, lessThan(1));
  });
}
