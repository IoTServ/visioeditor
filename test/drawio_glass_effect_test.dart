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

  int rectangle(EditorController value, double y) {
    value
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, y, 4, y + 1.5);
    return value.singleSelectedId!;
  }

  test('Glass is undoable, lock-safe, and survives VSDX round-trip', () {
    final value = controller();
    final id = rectangle(value, 1);

    expect(value.canSetGlassEffect, isTrue);
    value.setGlassEffect(true);
    expect(value.selectedHasGlassEffect, isTrue);
    value.undo();
    expect(value.selectedHasGlassEffect, isFalse);
    value.redo();

    final shape = value.currentPage!.findShapeById(id)!;
    expect(shape.glassEffect, isTrue);
    expect(
      shape.userCells.any(
        (cell) => cell.name == VsdxShape.userGlassEffect && cell.value == '1',
      ),
      isTrue,
    );
    final reopened = const DocumentParser()
        .parse(value.exportToBytes())
        .pages
        .single
        .findShapeById(id)!;
    expect(reopened.glassEffect, isTrue);

    value.setSelectionLocked(true);
    value.setGlassEffect(false);
    expect(value.currentPage!.findShapeById(id)!.glassEffect, isTrue);
  });

  test('Glass participates in Copy/Paste Style and default vertex style', () {
    final value = controller();
    final source = rectangle(value, 1);
    value
      ..setGlassEffect(true)
      ..copyStyle();

    final target = rectangle(value, 3);
    value.pasteStyle();
    expect(value.currentPage!.findShapeById(target)!.glassEffect, isTrue);

    value
      ..setSelection(<int>[source])
      ..setSelectionAsDefaultStyle();
    final created = rectangle(value, 5);
    expect(value.currentPage!.findShapeById(created)!.glassEffect, isTrue);
  });

  test('Canvas path and SVG use draw.io white wave highlight', () async {
    final path = drawioGlassHighlightPath(
      width: 4,
      height: 2,
      strokeWidth: 0.1,
    );
    final bounds = path.getBounds();
    expect(bounds.left, closeTo(-0.05, 1e-6));
    expect(bounds.right, closeTo(4.05, 1e-6));
    expect(bounds.bottom, greaterThan(2));

    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 3,
      pinY: 2,
      width: 4,
      height: 2,
    )
        .copyWith(
          fill: const VsdxFill(
            foreground: VsdxColor(0xFF1565C0),
          ),
        )
        .withGlassEffect(true);
    final page = VsdxPage(
      id: 0,
      name: 'Glass',
      widthInches: 7,
      heightInches: 5,
      shapes: <VsdxShape>[shape],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg, contains('gradient-p0-1-glass'));
    expect(svg, contains('stop-color="#ffffff"'));
    expect(svg, contains('stop-opacity="0.9"'));
    expect(svg, contains('clip-path="url(#clip-p0-1-glass)"'));

    final pdfSvg = VsdxToSvgSerializer(pdfCompat: true).serializePage(page);
    expect(pdfSvg, contains('gradient-p0-1-glass'));

    Future<List<int>> raster(VsdxShape value) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final rasterPage = page.copyWith(shapes: <VsdxShape>[value]);
      VsdxPainter(
        page: rasterPage,
        pxPerInch: 40,
      ).paint(canvas, const Size(280, 200));
      final image = await recorder.endRecording().toImage(280, 200);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }

    final withoutGlass = await raster(shape.withGlassEffect(false));
    final withGlass = await raster(shape);
    expect(withGlass, isNot(equals(withoutGlass)));
  });

  test('connectors and image frames do not expose Glass', () {
    final line = VsdxShapeFactory.line(id: 1, ax: 1, ay: 1, bx: 4, by: 1);
    final image = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
    ).copyWith(imagePartName: '/visio/media/image1.png');
    expect(line.supportsGlassEffect, isFalse);
    expect(line.withGlassEffect(true).glassEffect, isTrue);
    expect(line.withGlassEffect(true).supportsGlassEffect, isFalse);
    expect(image.hasImage, isTrue);
    expect(image.supportsGlassEffect, isFalse);
  });

  testWidgets('Format exposes and toggles draw.io Glass', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = await AppSettings.load();
    await tester.pumpWidget(VisioEditorApp(settings: settings));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'New drawing'));
    await tester.pumpAndSettle();

    final canvas = tester.widget<PageCanvas>(find.byType(PageCanvas));
    rectangle(canvas.controller, 1);
    await tester.pumpAndSettle();

    final scrollable = find.ancestor(
      of: find.text('Arrange'),
      matching: find.byWidgetPredicate((widget) => widget is Scrollable),
    );
    final state = tester.state<ScrollableState>(scrollable);
    for (var i = 0; i < 30 && find.text('Glass').evaluate().isEmpty; i++) {
      state.position.jumpTo(
        (state.position.pixels + 240).clamp(0, state.position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('Glass'), findsOneWidget);
    await tester.ensureVisible(find.text('Glass'));
    await tester.pumpAndSettle();

    final glassY = tester.getCenter(find.text('Glass')).dy;
    Element? nearest;
    var distance = double.infinity;
    for (final element in find.byType(Switch).evaluate()) {
      final render = element.renderObject;
      if (render is! RenderBox || !render.attached) continue;
      final center = render.localToGlobal(render.size.center(Offset.zero));
      if (center.dy < 0 || center.dy > 800) continue;
      final candidate = (center.dy - glassY).abs();
      if (candidate < distance) {
        distance = candidate;
        nearest = element;
      }
    }
    expect(nearest, isNotNull);
    await tester.tap(find.byElementPredicate((element) => element == nearest));
    await tester.pumpAndSettle();
    expect(canvas.controller.selectedHasGlassEffect, isTrue);
  });
}
