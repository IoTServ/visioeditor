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
    return value.singleSelectedId!;
  }

  int line(EditorController value, double y) {
    value
      ..setTool(EditorTool.line)
      ..createShapeByDrag(1, y, 4, y);
    return value.singleSelectedId!;
  }

  test('Sketch is undoable, lock-safe, and round-trips through User rows', () {
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

    value
      ..setSketchEffect(true)
      ..beginTransaction()
      ..setSketchJiggle(2.5, transient: true)
      ..setSketchJiggle(3.5, transient: true)
      ..commitTransaction();
    expect(value.selectedHasSketchEffect, isTrue);
    expect(value.selectedSketchJiggle, 3.5);

    value.undo();
    expect(value.selectedSketchJiggle, 2);
    value.redo();
    final reopened = const DocumentParser()
        .parse(value.exportToBytes())
        .pages
        .single
        .findShapeById(id)!;
    expect(reopened.sketchEffect, isTrue);
    expect(reopened.sketchJiggle, closeTo(3.5, 1e-6));
    expect(
      reopened.userCells
          .singleWhere((cell) => cell.name == 'foreignMeta')
          .value,
      'keep',
    );

    value.setSelectionLocked(true);
    value.setSketchEffect(false);
    expect(value.currentPage!.findShapeById(id)!.sketchEffect, isTrue);
    expect(value.canSetSketchEffect, isFalse);
  });

  test(
    'Canvas, SVG, and PDF use stable double-stroke sketch offsets',
    () async {
      final offsets = drawioSketchStrokeOffsets(7, 2, pxPerInch: 100);
      expect(offsets, hasLength(2));
      expect(
        offsets[0],
        equals(drawioSketchStrokeOffsets(7, 2, pxPerInch: 100)[0]),
      );
      expect(offsets[0].x, lessThan(0));
      expect(offsets[1].x, greaterThan(0));

      final plain =
          VsdxShapeFactory.rectangle(
            id: 7,
            pinX: 3,
            pinY: 2,
            width: 3,
            height: 1.5,
          ).copyWith(
            fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF)),
            line: const VsdxLine(
              color: VsdxColor(0xFF111111),
              weightInches: 0.08,
            ),
          );
      final sketch = plain.withSketchEffect(true).withSketchJiggle(2.75);
      final page = VsdxPage(
        id: 0,
        name: 'Sketch',
        widthInches: 7,
        heightInches: 5,
        shapes: <VsdxShape>[sketch],
      );
      final svg = VsdxToSvgSerializer().serializePage(page);
      expect(svg, contains('data-ve-sketch="1"'));
      expect(RegExp('opacity="0.68"').allMatches(svg), hasLength(2));
      expect(
        RegExp('transform="translate\\(').allMatches(svg).length,
        greaterThanOrEqualTo(3),
      );
      final pdfSvg = VsdxToSvgSerializer(pdfCompat: true).serializePage(page);
      expect(pdfSvg, contains('data-ve-sketch="1"'));
      expect(RegExp('opacity="0.68"').allMatches(pdfSvg), hasLength(2));

      Future<List<int>> raster(VsdxShape shape) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        VsdxPainter(
          page: page.copyWith(shapes: <VsdxShape>[shape]),
          pxPerInch: 50,
        ).paint(canvas, const Size(350, 250));
        final image = await recorder.endRecording().toImage(350, 250);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data!.buffer.asUint8List();
      }

      expect(await raster(sketch), isNot(equals(await raster(plain))));
    },
  );

  test('Copy/Paste and independent vertex/edge defaults carry Sketch', () {
    final value = controller();
    final source = rectangle(value, 2);
    value
      ..setSketchEffect(true)
      ..setSketchJiggle(3)
      ..copyStyle();

    final target = rectangle(value, 5);
    value.pasteStyle();
    expect(value.currentPage!.findShapeById(target)!.sketchEffect, isTrue);
    expect(value.currentPage!.findShapeById(target)!.sketchJiggle, 3);

    value
      ..setSelection(<int>[source])
      ..setSelectionAsDefaultStyle();
    final vertex = rectangle(value, 8);
    expect(value.currentPage!.findShapeById(vertex)!.sketchEffect, isTrue);

    final edge = line(value, 3);
    expect(value.currentPage!.findShapeById(edge)!.sketchEffect, isFalse);
    value
      ..setSketchEffect(true)
      ..setSketchJiggle(4)
      ..setSelectionAsDefaultStyle();
    final nextEdge = line(value, 4);
    expect(value.currentPage!.findShapeById(nextEdge)!.sketchEffect, isTrue);
    expect(value.currentPage!.findShapeById(nextEdge)!.sketchJiggle, 4);
  });

  testWidgets('Format exposes draw.io Sketch and Jiggle', (tester) async {
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
    final sketchSwitch = find.byKey(const ValueKey('sketch-effect-switch'));
    for (var i = 0; i < 30 && sketchSwitch.evaluate().isEmpty; i++) {
      state.position.jumpTo(
        (state.position.pixels + 220).clamp(0, state.position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('Sketch'), findsOneWidget);
    expect(sketchSwitch, findsOneWidget);
    await tester.ensureVisible(sketchSwitch);
    await tester.tap(
      find.descendant(of: sketchSwitch, matching: find.byType(Switch)),
    );
    await tester.pumpAndSettle();
    expect(canvas.controller.selectedHasSketchEffect, isTrue);

    final jiggle = find.byKey(const ValueKey('sketch-jiggle-slider'));
    expect(jiggle, findsOneWidget);
    expect(find.text('Jiggle'), findsOneWidget);
    await tester.ensureVisible(jiggle);
    await tester.drag(
      find.descendant(of: jiggle, matching: find.byType(Slider)),
      const Offset(70, 0),
    );
    await tester.pumpAndSettle();
    expect(canvas.controller.selectedSketchJiggle, greaterThan(2));
  });
}
