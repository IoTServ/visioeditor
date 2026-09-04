import 'dart:ui' as ui;

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

  int line(EditorController value, double y) {
    value
      ..setTool(EditorTool.line)
      ..createShapeByDrag(1, y, 5, y);
    return value.singleSelectedId!;
  }

  test('Flow Animation is undoable, lock-safe, and round-trips settings', () {
    final value = controller();
    final id = line(value, 2);

    expect(value.canSetFlowAnimation, isTrue);
    value
      ..setFlowAnimation(true)
      ..setFlowAnimationDurationMs(900)
      ..setFlowAnimationTiming(VsdxFlowAnimationTiming.easeInOut)
      ..setFlowAnimationDirection(VsdxFlowAnimationDirection.alternateReverse);
    expect(value.selectedHasFlowAnimation, isTrue);
    value.undo();
    expect(
      value.selectedFlowAnimationDirection,
      VsdxFlowAnimationDirection.normal,
    );
    value.redo();

    final shape = value.currentPage!.findShapeById(id)!;
    expect(shape.flowAnimationDurationMs, 900);
    expect(shape.flowAnimationTiming, VsdxFlowAnimationTiming.easeInOut);
    expect(
      shape.flowAnimationDirection,
      VsdxFlowAnimationDirection.alternateReverse,
    );
    final reopened = const DocumentParser()
        .parse(value.exportToBytes())
        .pages
        .single
        .findShapeById(id)!;
    expect(reopened.flowAnimation, isTrue);
    expect(reopened.flowAnimationDurationMs, 900);
    expect(reopened.flowAnimationTiming, VsdxFlowAnimationTiming.easeInOut);
    expect(
      reopened.flowAnimationDirection,
      VsdxFlowAnimationDirection.alternateReverse,
    );

    value.setSelectionLocked(true);
    value.setFlowAnimation(false);
    expect(value.currentPage!.findShapeById(id)!.flowAnimation, isTrue);
  });

  test('Flow Animation participates in Copy/Paste Style and edge defaults', () {
    final value = controller();
    final source = line(value, 4);
    value
      ..setFlowAnimation(true)
      ..setFlowAnimationDurationMs(750)
      ..setFlowAnimationDirection(VsdxFlowAnimationDirection.reverse)
      ..copyStyle();

    final target = line(value, 3);
    value.pasteStyle();
    var pasted = value.currentPage!.findShapeById(target)!;
    expect(pasted.flowAnimation, isTrue);
    expect(pasted.flowAnimationDurationMs, 750);
    expect(pasted.flowAnimationDirection, VsdxFlowAnimationDirection.reverse);

    value
      ..setSelection(<int>[source])
      ..setSelectionAsDefaultStyle();
    final created = line(value, 2);
    pasted = value.currentPage!.findShapeById(created)!;
    expect(pasted.flowAnimation, isTrue);
    expect(pasted.flowAnimationDurationMs, 750);
  });

  test('Canvas phase and SVG export match draw.io flow semantics', () async {
    expect(
      drawioFlowAnimationProgress(elapsedSeconds: 0.25, durationMs: 500),
      closeTo(0.5, 1e-9),
    );
    expect(
      drawioFlowAnimationProgress(
        elapsedSeconds: 0,
        durationMs: 500,
        direction: VsdxFlowAnimationDirection.reverse,
      ),
      closeTo(1, 1e-9),
    );

    final shape = VsdxShapeFactory.line(id: 1, ax: 1, ay: 2, bx: 5, by: 2)
        .copyWith(
          line: const VsdxLine(
            color: VsdxColor(0xFF1565C0),
            weightInches: 0.08,
          ),
        )
        .withFlowAnimation(true)
        .withFlowAnimationTiming(VsdxFlowAnimationTiming.easeInOut)
        .withFlowAnimationDirection(
          VsdxFlowAnimationDirection.alternateReverse,
        );
    final page = VsdxPage(
      id: 0,
      name: 'Flow',
      widthInches: 7,
      heightInches: 5,
      shapes: <VsdxShape>[shape],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg, contains('@keyframes flow-p0-1-0'));
    expect(svg, contains('stroke-dasharray="0.083 0.083"'));
    expect(svg, contains('flow-p0-1-0 500ms ease-in-out infinite'));
    expect(svg, contains('alternate-reverse'));
    final pdfSvg = VsdxToSvgSerializer(pdfCompat: true).serializePage(page);
    expect(pdfSvg, contains('stroke-dasharray="0.083 0.083"'));
    expect(pdfSvg, isNot(contains('@keyframes')));

    Future<List<int>> raster(double clockValue) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      VsdxPainter(
        page: page,
        pxPerInch: 96,
        flowAnimation: AlwaysStoppedAnimation<double>(clockValue),
      ).paint(canvas, const Size(672, 480));
      final image = await recorder.endRecording().toImage(672, 480);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }

    final first = await raster(0);
    final halfway = await raster(0.25 / 3600);
    expect(halfway, isNot(equals(first)));
  });

  test('vertices and freehand ink do not expose Flow Animation', () {
    final rectangle = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
    );
    final ink = VsdxShapeFactory.line(
      id: 2,
      ax: 1,
      ay: 1,
      bx: 3,
      by: 2,
    ).copyWith(objType: 1);
    final hiddenEdge = VsdxShapeFactory.line(
      id: 3,
      ax: 1,
      ay: 3,
      bx: 3,
      by: 3,
    ).copyWith(line: const VsdxLine(pattern: 0));
    expect(rectangle.supportsFlowAnimation, isFalse);
    expect(ink.isInk, isTrue);
    expect(ink.supportsFlowAnimation, isFalse);
    expect(hiddenEdge.line.hasLine, isFalse);
    expect(hiddenEdge.supportsFlowAnimation, isTrue);
  });

  testWidgets('Format exposes and toggles draw.io Flow Animation', (
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
    line(canvas.controller, 2);
    await tester.pumpAndSettle();
    final scrollable = find.ancestor(
      of: find.text('Arrange'),
      matching: find.byWidgetPredicate((widget) => widget is Scrollable),
    );
    final state = tester.state<ScrollableState>(scrollable);
    for (
      var i = 0;
      i < 30 && find.text('Flow Animation').evaluate().isEmpty;
      i++
    ) {
      state.position.jumpTo(
        (state.position.pixels + 240).clamp(0, state.position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('Flow Animation'), findsOneWidget);
    await tester.ensureVisible(find.text('Flow Animation'));
    await tester.tap(find.text('Flow Animation'));
    await tester.pumpAndSettle();

    final sectionY = tester.getCenter(find.text('Flow Animation')).dy;
    Element? nearest;
    var distance = double.infinity;
    for (final element in find.byType(Switch).evaluate()) {
      final render = element.renderObject;
      if (render is! RenderBox || !render.attached) continue;
      final center = render.localToGlobal(render.size.center(Offset.zero));
      final candidate = (center.dy - sectionY).abs();
      if (center.dy >= 0 && center.dy <= 800 && candidate < distance) {
        distance = candidate;
        nearest = element;
      }
    }
    expect(nearest, isNotNull);
    await tester.tap(find.byElementPredicate((element) => element == nearest));
    await tester.pump(const Duration(milliseconds: 100));
    expect(canvas.controller.selectedHasFlowAnimation, isTrue);
    expect(find.text('Flow Duration'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
