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
    value.setShapeText(id, 'Padded label');
    return id;
  }

  test('CSS shorthand parsing matches draw.io labelPadding', () {
    expect(VsdxLabelPadding.tryParse('4'), const VsdxLabelPadding.all(4));
    expect(
      VsdxLabelPadding.tryParse('4 8'),
      const VsdxLabelPadding(top: 4, right: 8, bottom: 4, left: 8),
    );
    expect(
      VsdxLabelPadding.tryParse('1 2 3'),
      const VsdxLabelPadding(top: 1, right: 2, bottom: 3, left: 2),
    );
    expect(VsdxLabelPadding.tryParse(<num>[1, 2, 3, 4])!.cssValue, '1 2 3 4');
    expect(VsdxLabelPadding.tryParse('bad'), isNull);
  });

  test('label padding is undoable, copied, exported and VSDX round-tripped', () {
    final value = controller();
    final source = rectangle(value, 2);
    value
      ..setTextBackgroundColor(const VsdxColor(0xFFFFCC33))
      ..beginTransaction()
      ..setLabelPadding(top: 4, right: 8, transient: true)
      ..setLabelPadding(bottom: 12, left: 16, transient: true)
      ..commitTransaction();

    const expected = VsdxLabelPadding(top: 4, right: 8, bottom: 12, left: 16);
    var shape = value.currentPage!.findShapeById(source)!;
    expect(shape.labelPadding, expected);
    expect(
      shape.userCells
          .singleWhere((c) => c.name == VsdxShape.userLabelPadding)
          .value,
      '4 8 12 16',
    );
    value.undo();
    expect(
      value.currentPage!.findShapeById(source)!.labelPadding.isZero,
      isTrue,
    );
    value.redo();

    final svg = VsdxToSvgSerializer().serializePage(value.currentPage!);
    final plate = RegExp(
      r'<rect x="[^"]+" y="[^"]+" width="([^"]+)" height="([^"]+)" fill="#ffcc33"',
    ).firstMatch(svg);
    expect(plate, isNotNull);
    expect(double.parse(plate!.group(1)!), lessThan(2));
    expect(double.parse(plate.group(2)!), lessThan(1));

    final reopened = const DocumentParser()
        .parse(value.exportToBytes())
        .pages
        .single
        .findShapeById(source)!;
    expect(reopened.labelPadding, expected);

    value.copyStyle();
    final target = rectangle(value, 5);
    value.pasteStyle();
    expect(value.currentPage!.findShapeById(target)!.labelPadding, expected);

    value.resetLabelPadding();
    shape = value.currentPage!.findShapeById(target)!;
    expect(shape.labelPadding.isZero, isTrue);
    expect(
      shape.userCells.where((c) => c.name == VsdxShape.userLabelPadding),
      isEmpty,
    );
  });

  testWidgets('Format shows per-side Label Padding only with a plate', (
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
    expect(
      find.byKey(const ValueKey('label-padding-top-slider')),
      findsNothing,
    );

    canvas.controller.setLabelBorderColor(const VsdxColor(0xFF1565C0));
    await tester.pumpAndSettle();
    final scrollable = find.ancestor(
      of: find.text('Arrange'),
      matching: find.byWidgetPredicate((widget) => widget is Scrollable),
    );
    final state = tester.state<ScrollableState>(scrollable);
    for (
      var i = 0;
      i < 30 &&
          find
              .byKey(const ValueKey('label-padding-top-slider'))
              .evaluate()
              .isEmpty;
      i++
    ) {
      state.position.jumpTo(
        (state.position.pixels + 260).clamp(0, state.position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('Label Padding'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('label-padding-top-slider')),
      findsOneWidget,
    );
    expect(find.text('Reset Label Padding'), findsOneWidget);
  });
}
