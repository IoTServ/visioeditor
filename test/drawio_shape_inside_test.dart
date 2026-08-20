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

  int ellipse(EditorController value, double x) {
    value.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.ellipse(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 3,
        height: 2,
      ),
      x,
      5,
    );
    return value.singleSelectedId!;
  }

  VsdxShape diamond(int id) => VsdxShapeFactory.polygon(
    id: id,
    pinX: 2,
    pinY: 2,
    width: 3,
    height: 2,
    unit: const <Offset2D>[
      Offset2D(0.5, 1),
      Offset2D(1, 0.5),
      Offset2D(0.5, 0),
      Offset2D(0, 0.5),
    ],
  );

  test('ellipse and convex polygon expose narrowing text-flow bands', () {
    final oval = VsdxShapeFactory.ellipse(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 3,
      height: 2,
    );
    final rhombus = diamond(2);
    final rectangle = VsdxShapeFactory.rectangle(
      id: 3,
      pinX: 2,
      pinY: 2,
      width: 3,
      height: 2,
    );

    expect(oval.supportsShapeInside, isTrue);
    expect(rhombus.supportsShapeInside, isTrue);
    expect(rectangle.supportsShapeInside, isFalse);
    final ovalTop = oval.shapeInsideBand(0.05, 0.15)!;
    final ovalMiddle = oval.shapeInsideBand(0.45, 0.55)!;
    expect(ovalTop.left, greaterThan(ovalMiddle.left));
    expect(ovalTop.right, lessThan(ovalMiddle.right));
    final diamondTop = rhombus.shapeInsideBand(0.05, 0.15)!;
    expect(diamondTop.right - diamondTop.left, lessThan(1));
    expect(rhombus.shapeInsideBand(0, 0.1), isNotNull);
    final overflow = rhombus.shapeInsideBand(-0.2, -0.1)!;
    expect(overflow.left, 0);
    expect(overflow.right, 1);

    final slanted = VsdxShapeFactory.polygon(
      id: 4,
      pinX: 2,
      pinY: 2,
      width: 3,
      height: 2,
      unit: const <Offset2D>[
        Offset2D(0.2, 1),
        Offset2D(1, 1),
        Offset2D(0.8, 0),
        Offset2D(0, 0),
      ],
    );
    final normalBand = slanted.shapeInsideBand(0.1, 0.2)!;
    final flippedBand = slanted
        .copyWith(flipX: true)
        .shapeInsideBand(0.1, 0.2)!;
    expect(flippedBand.left, closeTo(1 - normalBand.right, 1e-9));
    expect(flippedBand.right, closeTo(1 - normalBand.left, 1e-9));
  });

  test('controller forces Word Wrap and preserves User rows on round-trip', () {
    final value = controller();
    final id = ellipse(value, 2);
    value
      ..setShapeText(id, 'Text flows along the ellipse outline')
      ..updateCurrentPage(
        (page) => page.updateShapeById(
          id,
          (shape) => shape.copyWith(
            userCells: <VsdxUserCell>[
              ...shape.userCells,
              const VsdxUserCell(name: 'foreignMeta', value: 'keep'),
            ],
          ),
        ),
      )
      ..setWordWrap(false)
      ..setShapeInside(true);

    var shape = value.currentPage!.findShapeById(id)!;
    expect(value.canSetShapeInside, isTrue);
    expect(shape.shapeInside, isTrue);
    expect(shape.wordWrap, isTrue);
    value
      ..beginTransaction()
      ..setShapeInsidePadding(5, transient: true)
      ..setShapeInsidePadding(7, transient: true)
      ..commitTransaction();
    shape = value.currentPage!.findShapeById(id)!;
    expect(shape.shapeInsidePaddingPx, 7);
    value.undo();
    expect(value.currentPage!.findShapeById(id)!.shapeInsidePaddingPx, 2);
    value.redo();

    final exported = value.exportToBytes();
    final reopenedDoc = const DocumentParser().parse(exported);
    final reopened = reopenedDoc.pages.single.findShapeById(id)!;
    expect(reopened.shapeInside, isFalse);
    expect(reopened.richText.textBlock.hideText, isTrue);
    expect(
      reopened.userCells
          .singleWhere((cell) => cell.name == 'foreignMeta')
          .value,
      'keep',
    );
    expect(
      reopenedDoc.pages.single.shapes.where(isLibvisioShapeInsidePlate),
      isNotEmpty,
    );
  });

  test('Copy/Paste, Text Style and default Vertex style carry text flow', () {
    final value = controller();
    final source = ellipse(value, 2);
    value
      ..setShapeText(source, 'Source')
      ..setShapeInside(true)
      ..setShapeInsidePadding(6)
      ..copyStyle();

    final target = ellipse(value, 5);
    value
      ..setShapeText(target, 'Target')
      ..pasteStyle();
    var targetShape = value.currentPage!.findShapeById(target)!;
    expect(targetShape.shapeInside, isTrue);
    expect(targetShape.shapeInsidePaddingPx, 6);

    value
      ..setSelection(<int>[source])
      ..copyTextStyle()
      ..setSelection(<int>[target])
      ..setShapeInside(false)
      ..pasteTextStyle();
    targetShape = value.currentPage!.findShapeById(target)!;
    expect(targetShape.shapeInside, isTrue);

    value
      ..setSelection(<int>[source])
      ..setSelectionAsDefaultStyle();
    final inherited = ellipse(value, 8);
    expect(value.currentPage!.findShapeById(inherited)!.shapeInside, isTrue);
  });

  test('unsupported and locked shapes reject Fit Text to Shape', () {
    final value = controller();
    value.addShapeFromBuilderAt(
      (id, x, y) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: x,
        pinY: y,
        width: 3,
        height: 2,
      ),
      2,
      5,
    );
    expect(value.canSetShapeInside, isFalse);
    value.setShapeInside(true);
    expect(value.singleSelected!.shapeInside, isFalse);

    final id = ellipse(value, 5);
    value.updateCurrentPage(
      (page) =>
          page.updateShapeById(id, (shape) => shape.copyWith(locked: true)),
    );
    expect(value.canSetShapeInside, isFalse);
    value.setShapeInside(true);
    expect(value.currentPage!.findShapeById(id)!.shapeInside, isFalse);
  });

  test('Automatic Text Size accounts for the narrower outline', () {
    final value = controller();
    final id = ellipse(value, 2);
    value
      ..setShapeText(
        id,
        'Automatic text size follows the narrower ellipse outline bands',
      )
      ..setAutosizeText(true);
    double points() =>
        value.currentPage!
            .findShapeById(id)!
            .richText
            .runs
            .first
            .charStyle
            .fontSizeInches *
        72;
    final rectangularSize = points();
    value.setShapeInside(true);
    final flowedSize = points();
    expect(flowedSize, lessThanOrEqualTo(rectangularSize));
    value.setShapeInsidePadding(12);
    expect(points(), lessThanOrEqualTo(flowedSize));
  });

  test('Canvas and SVG/PDF lay out lines on different outline bands', () async {
    final base = diamond(1).copyWith(
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      text: 'one two three four five six seven eight nine ten eleven twelve',
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(
            text:
                'one two three four five six seven eight nine ten eleven twelve',
            charStyle: VsdxCharStyle(fontSizeInches: 12 / 72),
          ),
        ],
      ),
    );
    final flowed = base.withShapeInside(true).withShapeInsidePadding(2);
    final page = VsdxPage(
      id: 0,
      name: 'Flow',
      widthInches: 6,
      heightInches: 5,
      shapes: <VsdxShape>[flowed],
    );

    List<double> lineXs(String svg) => RegExp(
      r'<tspan x="([0-9.]+)"',
    ).allMatches(svg).map((match) => double.parse(match.group(1)!)).toList();
    final svg = VsdxToSvgSerializer().serializePage(page);
    final xs = lineXs(svg);
    expect(xs.length, greaterThan(1));
    expect(xs.toSet().length, greaterThan(1));
    final pdfSvg = VsdxToSvgSerializer(pdfCompat: true).serializePage(page);
    expect(lineXs(pdfSvg).toSet().length, greaterThan(1));

    Future<List<int>> raster(VsdxShape shape) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      VsdxPainter(
        page: page.copyWith(shapes: <VsdxShape>[shape]),
        pxPerInch: 50,
      ).paint(canvas, const Size(300, 250));
      final image = await recorder.endRecording().toImage(300, 250);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }

    expect(await raster(flowed), isNot(equals(await raster(base))));
  });

  testWidgets('Format Text exposes Fit Text to Shape and outline padding', (
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
    final id = ellipse(canvas.controller, 2);
    canvas.controller.setShapeText(id, 'Flow inside the ellipse');
    await tester.pumpAndSettle();

    final scrollable = find.ancestor(
      of: find.text('Arrange'),
      matching: find.byWidgetPredicate((widget) => widget is Scrollable),
    );
    final state = tester.state<ScrollableState>(scrollable);
    final toggle = find.byKey(const ValueKey('shape-inside-switch'));
    for (var i = 0; i < 30 && toggle.evaluate().isEmpty; i++) {
      state.position.jumpTo(
        (state.position.pixels + 260).clamp(0, state.position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
    }
    expect(toggle, findsOneWidget);
    await Scrollable.ensureVisible(tester.element(toggle), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(canvas.controller.selectedShapeInside, isTrue);
    expect(find.text('Fit Text to Shape'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('shape-inside-padding-slider')),
      findsOneWidget,
    );
  });
}
