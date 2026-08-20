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

  test(
    'Shape Opacity is undoable, lock-safe, and round-trips in User rows',
    () {
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
        ..beginTransaction()
        ..setShapeOpacity(0.75, transient: true)
        ..setShapeOpacity(0.4, transient: true)
        ..commitTransaction();
      expect(value.canSetShapeOpacity, isTrue);
      expect(value.selectedShapeOpacity, closeTo(0.4, 1e-9));
      var shape = value.currentPage!.findShapeById(id)!;
      expect(
        shape.userCells
            .singleWhere((cell) => cell.name == VsdxShape.userShapeOpacity)
            .value,
        '0.4',
      );
      expect(
        shape.userCells.singleWhere((cell) => cell.name == 'foreignMeta').value,
        'keep',
      );

      value.undo();
      expect(value.selectedShapeOpacity, 1);
      value.redo();
      final reopened = const DocumentParser()
          .parse(value.exportToBytes())
          .pages
          .single
          .findShapeById(id)!;
      expect(reopened.shapeOpacity, 1,
          reason: 'User.veOpacity is not a token; save bakes FillForegndTrans');
      expect(reopened.fill.foregroundTransparency, closeTo(0.6, 1e-6));
      expect(
        reopened.userCells
            .singleWhere((cell) => cell.name == 'foreignMeta')
            .value,
        'keep',
      );

      value.setSelectionLocked(true);
      value.setShapeOpacity(0.8);
      shape = value.currentPage!.findShapeById(id)!;
      expect(shape.shapeOpacity, closeTo(0.4, 1e-9));
      expect(value.canSetShapeOpacity, isFalse);
    },
  );

  test(
    'Canvas and SVG composite the complete shape with one opacity',
    () async {
      final opaque = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 1,
      ).copyWith(fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000)));
      final faded = opaque.withShapeOpacity(0.5);
      final page = VsdxPage(
        id: 0,
        name: 'Opacity',
        widthInches: 7,
        heightInches: 5,
        shapes: <VsdxShape>[faded],
      );

      final svg = VsdxToSvgSerializer().serializePage(page);
      expect(svg, contains('translate(2 2) translate(-1 -0.5)" opacity="0.5"'));
      final pdfSvg = VsdxToSvgSerializer(pdfCompat: true).serializePage(page);
      expect(pdfSvg, contains('opacity="0.5"'));

      Future<List<int>> raster(VsdxShape shape) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        VsdxPainter(
          page: page.copyWith(shapes: <VsdxShape>[shape]),
          pxPerInch: 40,
        ).paint(canvas, const Size(280, 200));
        final image = await recorder.endRecording().toImage(280, 200);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data!.buffer.asUint8List();
      }

      final solidPixels = await raster(opaque);
      final fadedPixels = await raster(faded);
      final offset = (120 * 280 + 80) * 4;
      expect(solidPixels[offset], 255);
      expect(solidPixels[offset + 1], lessThan(10));
      expect(fadedPixels[offset], 255);
      expect(fadedPixels[offset + 1], inInclusiveRange(120, 135));
      expect(fadedPixels[offset + 2], inInclusiveRange(120, 135));
    },
  );

  test('Copy/Paste and independent defaults carry Shape Opacity', () {
    final value = controller();
    final source = rectangle(value, 2);
    value
      ..setShapeOpacity(0.4)
      ..copyStyle();

    final target = rectangle(value, 5);
    value.pasteStyle();
    expect(
      value.currentPage!.findShapeById(target)!.shapeOpacity,
      closeTo(0.4, 1e-9),
    );

    value
      ..setSelection(<int>[source])
      ..setSelectionAsDefaultStyle();
    final vertex = rectangle(value, 8);
    expect(
      value.currentPage!.findShapeById(vertex)!.shapeOpacity,
      closeTo(0.4, 1e-9),
    );

    final edge = line(value, 3);
    expect(value.currentPage!.findShapeById(edge)!.shapeOpacity, 1);
    value
      ..setShapeOpacity(0.25)
      ..setSelectionAsDefaultStyle();
    final nextEdge = line(value, 4);
    expect(
      value.currentPage!.findShapeById(nextEdge)!.shapeOpacity,
      closeTo(0.25, 1e-9),
    );
  });

  testWidgets('Format exposes and edits draw.io Shape Opacity', (tester) async {
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
      i < 10 &&
          find.byKey(const ValueKey('shape-opacity-slider')).evaluate().isEmpty;
      i++
    ) {
      state.position.jumpTo(
        (state.position.pixels + 160).clamp(0, state.position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
    }
    final opacity = find.byKey(const ValueKey('shape-opacity-slider'));
    expect(opacity, findsOneWidget);
    expect(find.text('Shape Opacity'), findsOneWidget);
    final slider = find.descendant(of: opacity, matching: find.byType(Slider));
    await tester.drag(slider, const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(canvas.controller.selectedShapeOpacity, lessThan(1));
  });
}
