import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/editor/page_canvas.dart';
import 'package:visioeditor/main.dart';
import 'package:visioeditor/render/vsdx_painter.dart';
import 'package:visioeditor/settings/app_settings.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EditorController controller() {
    final value = EditorController()..newDocument();
    addTearDown(value.dispose);
    return value;
  }

  int line(EditorController value, double ax, double ay, double bx, double by) {
    value
      ..setTool(EditorTool.line)
      ..createShapeByDrag(ax, ay, bx, by);
    return value.singleSelectedId!;
  }

  test('Line Cap is undoable, lock-safe, and survives VSDX round-trip', () {
    final value = controller();
    final id = line(value, 1, 3, 5, 3);

    value.setLineCap(LineCap.square);
    expect(value.currentPage!.findShapeById(id)!.line.cap, LineCap.square);
    value.undo();
    expect(value.currentPage!.findShapeById(id)!.line.cap, LineCap.round);
    value.redo();

    final reopened = const DocumentParser()
        .parse(value.exportToBytes())
        .pages
        .single
        .findShapeById(id)!;
    expect(reopened.line.cap, LineCap.square);

    value.setSelectionLocked(true);
    value.setLineCap(LineCap.extended);
    expect(value.currentPage!.findShapeById(id)!.line.cap, LineCap.square);
  });

  test(
    'Line Join and Miter Limit are undoable and survive VSDX round-trip',
    () {
      final value = controller();
      final id = line(value, 1, 3, 5, 3);

      value.setLineJoin(VsdxLineJoin.miterClip);
      expect(value.selectedLineJoin, VsdxLineJoin.miterClip);
      value.undo();
      expect(value.selectedLineJoin, VsdxLineJoin.miter);
      value.redo();
      value.setLineMiterLimit(9);

      var shape = value.currentPage!.findShapeById(id)!;
      expect(shape.line.join, VsdxLineJoin.miterClip);
      expect(shape.line.miterLimit, 9);
      expect(
        shape.userCells.any(
          (cell) =>
              cell.name == VsdxShape.userLineJoin && cell.value == 'miter-clip',
        ),
        isTrue,
      );

      final reopened = const DocumentParser()
          .parse(value.exportToBytes())
          .pages
          .single
          .findShapeById(id)!;
      expect(reopened.line.join, VsdxLineJoin.miterClip);
      expect(reopened.line.miterLimit, closeTo(9, 1e-9));

      value.setSelectionLocked(true);
      value
        ..setLineJoin(VsdxLineJoin.round)
        ..setLineMiterLimit(2);
      shape = value.currentPage!.findShapeById(id)!;
      expect(shape.line.join, VsdxLineJoin.miterClip);
      expect(shape.line.miterLimit, 9);
    },
  );

  test('SVG preserves five joins and Canvas uses documented fallbacks', () {
    final base = VsdxShapeFactory.line(id: 1, ax: 1, ay: 1, bx: 4, by: 3)
        .reshapeAsPolyline(const <Offset2D>[
          Offset2D(1, 1),
          Offset2D(2, 3),
          Offset2D(4, 3),
        ])
        .copyWith(line: const VsdxLine(weightInches: 0.2));

    for (final join in VsdxLineJoin.values) {
      final shape = base.withDrawioLineJoin(join).withDrawioMiterLimit(7);
      final page = VsdxPage(
        id: 0,
        name: 'Join',
        widthInches: 6,
        heightInches: 5,
        shapes: <VsdxShape>[shape],
      );
      final svg = VsdxToSvgSerializer().serializePage(page);
      expect(svg, contains('stroke-linejoin="${join.svgName}"'));
      if (join == VsdxLineJoin.miter || join == VsdxLineJoin.miterClip) {
        expect(svg, contains('stroke-miterlimit="7"'));
      } else {
        expect(svg, isNot(contains('stroke-miterlimit=')));
      }
    }

    expect(
      canvasStrokeJoin(const VsdxLine(join: VsdxLineJoin.miterClip)),
      StrokeJoin.miter,
    );
    expect(
      canvasStrokeJoin(const VsdxLine(join: VsdxLineJoin.arcs)),
      StrokeJoin.round,
    );
    expect(
      canvasStrokeJoin(const VsdxLine(join: VsdxLineJoin.bevel)),
      StrokeJoin.bevel,
    );
  });

  test('custom Dash Pattern and Fixed Dash round-trip and scale correctly', () {
    final value = controller();
    final id = line(value, 1, 3, 5, 3);

    value.setCustomDashPattern(const <double>[8, 4, 2, 4]);
    expect(value.selectedCustomDashPattern, <double>[8, 4, 2, 4]);
    expect(value.selectedLine?.pattern, 2);
    value.setFixedDash(true);
    expect(value.selectedFixedDash, isTrue);
    value.undo();
    expect(value.selectedFixedDash, isFalse);
    value.redo();

    final shape = value.currentPage!.findShapeById(id)!;
    expect(
      shape.userCells.any(
        (cell) =>
            cell.name == VsdxShape.userDashPattern && cell.value == '8 4 2 4',
      ),
      isTrue,
    );
    expect(
      shape.userCells.any(
        (cell) => cell.name == VsdxShape.userFixedDash && cell.value == '1',
      ),
      isTrue,
    );

    final reopened = const DocumentParser()
        .parse(value.exportToBytes())
        .pages
        .single
        .findShapeById(id)!;
    expect(reopened.line.customDashPattern, <double>[8, 4, 2, 4]);
    expect(reopened.line.fixedDash, isTrue);

    const scalable = VsdxLine(
      weightInches: 0.02,
      pattern: 2,
      customDashPattern: <double>[4, 2],
    );
    expect(effectiveDashPatternForLine(scalable), <double>[0.08, 0.04]);
    expect(
      effectiveDashPatternForLine(
        const VsdxLine(
          weightInches: 0.08,
          pattern: 2,
          customDashPattern: <double>[4, 2],
          fixedDash: true,
        ),
      ),
      <double>[4 / 96, 2 / 96],
    );

    value.setSelectionLocked(true);
    value.setCustomDashPattern(const <double>[1, 1]);
    expect(value.selectedCustomDashPattern, <double>[8, 4, 2, 4]);
  });

  test('SVG exports the effective custom dash array', () {
    final shape = VsdxShapeFactory.line(id: 1, ax: 1, ay: 1, bx: 4, by: 3)
        .copyWith(
          line: const VsdxLine(
            weightInches: 0.02,
            pattern: 2,
            customDashPattern: <double>[4, 2],
          ),
        );
    final page = VsdxPage(
      id: 0,
      name: 'Dash',
      widthInches: 6,
      heightInches: 5,
      shapes: <VsdxShape>[shape],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg, contains('stroke-dasharray="0.08 0.04"'));
  });

  test('five jump styles and per-edge size round-trip through VSDX', () {
    final value = controller();
    final id = line(value, 1, 3, 5, 3);

    for (final style in ConnectorLineJumpStyle.values) {
      value.setConnectorLineJumpStyle(style);
      expect(value.selectedConnectorLineJumpStyle, style);
    }
    value
      ..beginTransaction()
      ..setConnectorLineJumpSize(0.1, transient: true)
      ..setConnectorLineJumpSize(0.14, transient: true)
      ..commitTransaction();

    var shape = value.currentPage!.findShapeById(id)!;
    expect(value.selectedConnectorLineJumpStyle, ConnectorLineJumpStyle.line);
    expect(value.selectedConnectorLineJumpSize, closeTo(0.14, 1e-9));
    expect(shape.connectorProps?.conLineJumpCode, 2);
    expect(shape.connectorProps?.conLineJumpStyle, 3);
    expect(shape.drawioLineJumpStyle, 'line');
    expect(shape.drawioLineJumpSizeInches, closeTo(0.14, 1e-9));

    value.undo();
    shape = value.currentPage!.findShapeById(id)!;
    expect(shape.drawioLineJumpStyle, 'line');
    expect(shape.drawioLineJumpSizeInches, isNull);
    value.redo();

    final reopened = const DocumentParser()
        .parse(value.exportToBytes())
        .pages
        .single
        .findShapeById(id)!;
    expect(reopened.connectorProps?.conLineJumpCode, 2);
    expect(reopened.connectorProps?.conLineJumpStyle, 3);
    expect(reopened.drawioLineJumpStyle, 'line');
    expect(reopened.drawioLineJumpSizeInches, closeTo(0.14, 1e-6));

    value.setConnectorLineJumpStyle(ConnectorLineJumpStyle.none);
    shape = value.currentPage!.findShapeById(id)!;
    expect(shape.connectorProps?.conLineJumpCode, 1);
    expect(value.selectedConnectorLineJumpStyle, ConnectorLineJumpStyle.none);
  });

  test('Copy/Paste Style and default edge style include jumps and cap', () {
    final value = controller();
    final source = line(value, 1, 5, 4, 5);
    value
      ..setLineCap(LineCap.extended)
      ..setLineJoin(VsdxLineJoin.round)
      ..setLineMiterLimit(12)
      ..setCustomDashPattern(const <double>[7, 3, 1, 3])
      ..setFixedDash(true)
      ..setConnectorLineJumpStyle(ConnectorLineJumpStyle.gap)
      ..setConnectorLineJumpSize(0.12)
      ..copyStyle();

    final target = line(value, 1, 3, 4, 3);
    value.updateCurrentPage(
      (page) => page.updateShapeById(
        target,
        (shape) => shape.copyWith(
          connectorProps: (shape.connectorProps ?? const VsdxConnectorProps())
              .copyWith(begTrigger: 'keep'),
        ),
      ),
    );
    value.pasteStyle();
    var pasted = value.currentPage!.findShapeById(target)!;
    expect(pasted.line.cap, LineCap.extended);
    expect(pasted.line.join, VsdxLineJoin.round);
    expect(pasted.line.miterLimit, 12);
    expect(pasted.line.customDashPattern, <double>[7, 3, 1, 3]);
    expect(pasted.line.fixedDash, isTrue);
    expect(pasted.drawioLineJumpStyle, 'gap');
    expect(pasted.drawioLineJumpSizeInches, closeTo(0.12, 1e-9));
    expect(pasted.connectorProps?.begTrigger, 'keep');

    value
      ..setSelection([source])
      ..setSelectionAsDefaultStyle();
    final created = line(value, 1, 1, 4, 1);
    pasted = value.currentPage!.findShapeById(created)!;
    expect(pasted.line.cap, LineCap.extended);
    expect(pasted.line.join, VsdxLineJoin.round);
    expect(pasted.line.miterLimit, 12);
    expect(pasted.line.customDashPattern, <double>[7, 3, 1, 3]);
    expect(pasted.line.fixedDash, isTrue);
    expect(pasted.drawioLineJumpStyle, 'gap');
    expect(pasted.drawioLineJumpSizeInches, closeTo(0.12, 1e-9));
  });

  test('locked connector rejects jump style and size edits', () {
    final value = controller();
    final id = line(value, 1, 3, 5, 3);
    value.setSelectionLocked(true);

    value
      ..setConnectorLineJumpStyle(ConnectorLineJumpStyle.sharp)
      ..setConnectorLineJumpSize(0.2);
    final shape = value.currentPage!.findShapeById(id)!;
    expect(shape.drawioLineJumpStyle, isNull);
    expect(shape.drawioLineJumpSizeInches, isNull);
  });

  testWidgets('Format exposes draw.io Line Cap and Line Jumps controls', (
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
    line(canvas.controller, 1, 3, 5, 3);
    await tester.pumpAndSettle();

    final scrollable = find.ancestor(
      of: find.text('Arrange'),
      matching: find.byWidgetPredicate((widget) => widget is Scrollable),
    );
    final state = tester.state<ScrollableState>(scrollable);
    Future<void> scrollTo(String label) async {
      state.position.jumpTo(0);
      await tester.pumpAndSettle();
      for (var i = 0; i < 30 && find.text(label).evaluate().isEmpty; i++) {
        state.position.jumpTo(
          (state.position.pixels + 240).clamp(
            0,
            state.position.maxScrollExtent,
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text(label), findsOneWidget);
    }

    await scrollTo('Line Cap');
    await tester.ensureVisible(find.text('Square'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Square'));
    await tester.pumpAndSettle();
    expect(canvas.controller.selectedLine?.cap, LineCap.square);

    await scrollTo('Dash Pattern…');
    await tester.ensureVisible(find.text('Dash Pattern…'));
    await tester.tap(find.text('Dash Pattern…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '8 4 2 4');
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();
    expect(canvas.controller.selectedCustomDashPattern, <double>[8, 4, 2, 4]);
    expect(find.text('Fixed Dash'), findsOneWidget);

    await scrollTo('Line Join');
    await tester.ensureVisible(find.text('Bevel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bevel'));
    await tester.pumpAndSettle();
    expect(canvas.controller.selectedLineJoin, VsdxLineJoin.bevel);
    expect(find.text('Miter Limit'), findsNothing);

    await tester.ensureVisible(find.text('Miter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Miter'));
    await tester.pumpAndSettle();
    expect(canvas.controller.selectedLineJoin, VsdxLineJoin.miter);
    expect(find.text('Miter Limit'), findsOneWidget);

    await scrollTo('Line Jumps');
    final jumpDropdown = find.byWidgetPredicate(
      (widget) => widget is DropdownButton<ConnectorLineJumpStyle>,
    );
    expect(jumpDropdown, findsOneWidget);
    await tester.tap(jumpDropdown);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(DropdownMenuItem<ConnectorLineJumpStyle>, 'Line'),
    );
    await tester.pumpAndSettle();
    expect(
      canvas.controller.selectedConnectorLineJumpStyle,
      ConnectorLineJumpStyle.line,
    );
    expect(find.text('Jump Size'), findsOneWidget);
  });
}
