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

  int rectangle(EditorController value, double x, double y) {
    value.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 2,
        height: 1,
      ),
      x,
      y,
    );
    final id = value.singleSelectedId!;
    value.setShapeText(id, 'Label');
    return id;
  }

  test(
    'label background and text padding undo and survive VSDX round-trip',
    () {
      final value = controller();
      final id = rectangle(value, 2, 5);

      value
        ..setTextBackgroundColor(const VsdxColor(0xFFFFCC33))
        ..setTextBackgroundOpacity(0.65)
        ..beginTransaction()
        ..setTextMargins(left: 0.1, right: 0.15, transient: true)
        ..setTextMargins(top: 0.2, bottom: 0.25, transient: true)
        ..commitTransaction();

      var block = value.currentPage!.findShapeById(id)!.richText.textBlock;
      expect(block.backgroundColor, const VsdxColor(0xFFFFCC33));
      expect(block.backgroundTransparency, closeTo(0.35, 1e-9));
      expect(block.marginLeftInches, closeTo(0.1, 1e-9));
      expect(block.marginRightInches, closeTo(0.15, 1e-9));
      expect(block.marginTopInches, closeTo(0.2, 1e-9));
      expect(block.marginBottomInches, closeTo(0.25, 1e-9));

      value.undo();
      block = value.currentPage!.findShapeById(id)!.richText.textBlock;
      expect(block.marginLeftInches, VsdxTextBlock.defaults.marginLeftInches);
      expect(
        block.marginBottomInches,
        VsdxTextBlock.defaults.marginBottomInches,
      );
      expect(block.backgroundColor, const VsdxColor(0xFFFFCC33));
      value.redo();

      final reopened = const DocumentParser()
          .parse(value.exportToBytes())
          .pages
          .single
          .findShapeById(id)!
          .richText
          .textBlock;
      expect(reopened.backgroundColor, const VsdxColor(0xFFFFCC33));
      expect(reopened.backgroundTransparency, closeTo(0.35, 1e-6));
      expect(reopened.marginLeftInches, closeTo(0.1, 1e-6));
      expect(reopened.marginRightInches, closeTo(0.15, 1e-6));
      expect(reopened.marginTopInches, closeTo(0.2, 1e-6));
      expect(reopened.marginBottomInches, closeTo(0.25, 1e-6));
    },
  );

  test('copy style transfers text-block appearance but preserves geometry', () {
    final value = controller();
    final source = rectangle(value, 2, 5);
    value
      ..setTextBackgroundColor(const VsdxColor(0xFF44CCAA))
      ..setTextBackgroundOpacity(0.4)
      ..setTextMargins(left: 0.11, right: 0.12, top: 0.13, bottom: 0.14)
      ..copyStyle();

    final target = rectangle(value, 5, 5);
    value.updateCurrentPage(
      (page) => page.updateShapeById(
        target,
        (shape) => shape.copyWith(
          richText: shape.richText.copyWith(
            textBlock: shape.richText.textBlock.copyWith(
              pinXInches: 0.7,
              pinYInches: 0.8,
              widthInches: 1.2,
              heightInches: 0.6,
              angleRad: 0.3,
            ),
          ),
        ),
      ),
    );
    value.pasteStyle();

    final block = value.currentPage!.findShapeById(target)!.richText.textBlock;
    expect(block.backgroundColor, const VsdxColor(0xFF44CCAA));
    expect(block.backgroundTransparency, closeTo(0.6, 1e-9));
    expect(block.marginLeftInches, closeTo(0.11, 1e-9));
    expect(block.marginBottomInches, closeTo(0.14, 1e-9));
    expect(block.pinXInches, closeTo(0.7, 1e-9));
    expect(block.pinYInches, closeTo(0.8, 1e-9));
    expect(block.widthInches, closeTo(1.2, 1e-9));
    expect(block.heightInches, closeTo(0.6, 1e-9));
    expect(block.angleRad, closeTo(0.3, 1e-9));
    expect(source, isNot(target));
  });

  test('default style carries background and padding to new labels', () {
    final value = controller();
    final source = rectangle(value, 2, 5);
    value
      ..setTextBackgroundColor(const VsdxColor(0xFF3366FF))
      ..setTextMargins(left: 0.08, right: 0.09, top: 0.1, bottom: 0.11)
      ..setSelectionAsDefaultStyle();

    final created = rectangle(value, 5, 5);
    final block = value.currentPage!.findShapeById(created)!.richText.textBlock;
    expect(block.backgroundColor, const VsdxColor(0xFF3366FF));
    expect(block.marginLeftInches, closeTo(0.08, 1e-9));
    expect(block.marginRightInches, closeTo(0.09, 1e-9));
    expect(block.marginTopInches, closeTo(0.1, 1e-9));
    expect(block.marginBottomInches, closeTo(0.11, 1e-9));
    expect(source, isNot(created));
  });

  test('clearing background round-trips and locked labels reject edits', () {
    final value = controller();
    final id = rectangle(value, 2, 5);
    value
      ..setTextBackgroundColor(const VsdxColor(0xFFFF0000))
      ..clearTextBackgroundColor();
    expect(
      const DocumentParser()
          .parse(value.exportToBytes())
          .pages
          .single
          .findShapeById(id)!
          .richText
          .textBlock
          .backgroundColor,
      isNull,
    );

    value.setSelectionLocked(true);
    final before = value.currentPage!.findShapeById(id)!.richText.textBlock;
    value
      ..setTextBackgroundColor(const VsdxColor(0xFF00FF00))
      ..setTextMargins(left: 0.3)
      ..resetTextMargins();
    final after = value.currentPage!.findShapeById(id)!.richText.textBlock;
    expect(after.backgroundColor, before.backgroundColor);
    expect(after.marginLeftInches, before.marginLeftInches);
  });

  testWidgets('Format exposes label background and text padding controls', (
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
    rectangle(canvas.controller, 2, 5);
    canvas.controller
      ..setTextBackgroundColor(const VsdxColor(0xFFFFCC33))
      ..setTextMargins(left: 0.2, right: 0.2, top: 0.2, bottom: 0.2);
    await tester.pumpAndSettle();

    final scrollable = find.ancestor(
      of: find.text('Arrange'),
      matching: find.byWidgetPredicate((widget) => widget is Scrollable),
    );
    final state = tester.state<ScrollableState>(scrollable);
    Future<void> scrollTo(String label) async {
      for (var i = 0; i < 30 && find.text(label).evaluate().isEmpty; i++) {
        state.position.jumpTo(
          (state.position.pixels + 260).clamp(
            0,
            state.position.maxScrollExtent,
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text(label), findsOneWidget);
    }

    await scrollTo('Label Background');
    expect(find.text('Opacity'), findsWidgets);
    await scrollTo('Text Padding');
    await scrollTo('Reset Text Padding');
    await tester.ensureVisible(find.text('Reset Text Padding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset Text Padding'));
    await tester.pumpAndSettle();
    final block = canvas.controller.selectedTextBlock!;
    expect(block.marginLeftInches, VsdxTextBlock.defaults.marginLeftInches);
    expect(block.marginRightInches, VsdxTextBlock.defaults.marginRightInches);
    expect(block.marginTopInches, VsdxTextBlock.defaults.marginTopInches);
    expect(block.marginBottomInches, VsdxTextBlock.defaults.marginBottomInches);
  });
}
