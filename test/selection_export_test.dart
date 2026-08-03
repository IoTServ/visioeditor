import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/io/image_export.dart';
import 'package:visioeditor/io/selection_export.dart';
import 'package:visioeditor/render/shape_bounds.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'selection export crops, translates, filters, and preserves paint order',
    () {
      final ignored = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 1,
        pinY: 1,
        width: 1,
        height: 1,
      ).copyWith(text: 'ignored');
      final back = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 4,
        pinY: 2,
        width: 2,
        height: 1,
      ).copyWith(text: 'selected-back');
      final front = VsdxShapeFactory.rectangle(
        id: 3,
        pinX: 8,
        pinY: 2,
        width: 1,
        height: 1,
      ).copyWith(text: 'selected-front');
      final page = VsdxPage(
        id: 7,
        name: 'Canvas',
        widthInches: 12,
        heightInches: 8,
        shapes: <VsdxShape>[ignored, back, front],
      );

      final cropped = buildSelectionExportPage(page, <int>[
        3,
        2,
      ], marginInches: 0.1)!;

      expect(cropped.shapes.map((shape) => shape.id), <int>[2, 3]);
      expect(cropped.widthInches, closeTo(5.775, 1e-9));
      expect(cropped.heightInches, closeTo(1.3, 1e-9));
      final visualBounds = buildShapeBounds(cropped);
      expect(visualBounds[2]!.left, closeTo(0.1, 1e-9));
      expect(visualBounds[3]!.right, closeTo(cropped.widthInches - 0.1, 1e-9));

      final svg = VsdxToSvgSerializer().serializePage(cropped);
      final renderedText = RegExp(r'<tspan\b[^>]*>(.*?)</tspan>')
          .allMatches(svg)
          .map((match) => match.group(1))
          .join();
      // The narrow front shape may wrap at different glyph boundaries as
      // metrics improve; concatenated SVG text must retain content and order.
      expect(renderedText, contains('selected-backselected-front'));
      expect(svg, isNot(contains('ignored')));
    },
  );

  test(
    'selection roots avoid duplicate descendants and crop their overflow',
    () {
      final child = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 3,
        pinY: 1,
        width: 1,
        height: 0.5,
      );
      final group = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 5,
        pinY: 4,
        width: 2,
        height: 2,
      ).copyWith(shapeKind: VsdxShapeKind.group, children: <VsdxShape>[child]);
      final page = VsdxPage(
        id: 0,
        name: 'Group',
        widthInches: 10,
        heightInches: 8,
        shapes: <VsdxShape>[group],
      );

      final cropped = buildSelectionExportPage(page, <int>[
        2,
        1,
      ], marginInches: 0.2)!;

      expect(cropped.shapes, hasLength(1));
      expect(cropped.shapes.single.id, 1);
      expect(cropped.shapes.single.children.single.id, 2);
      final childBounds = buildShapeBounds(cropped)[2]!;
      expect(
        childBounds.right,
        lessThanOrEqualTo(cropped.widthInches - 0.2 + 1e-9),
      );
      expect(
        childBounds.top,
        lessThanOrEqualTo(cropped.heightInches - 0.2 + 1e-9),
      );
    },
  );

  test('selection crop includes an external label text block', () {
    const labelHeight = 0.22;
    final icon =
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 0.75,
          height: 0.75,
        ).copyWith(
          text: 'Caption',
          richText: VsdxRichText(
            runs: const <VsdxTextRun>[VsdxTextRun(text: 'Caption')],
            textBlock: VsdxTextBlock(
              pinXInches: 0.375,
              pinYInches: 0,
              locPinXInches: 0.375,
              locPinYInches: labelHeight,
              widthInches: 0.75,
              heightInches: labelHeight,
            ),
          ),
        );
    final page = VsdxPage(
      id: 0,
      name: 'Caption',
      widthInches: 5,
      heightInches: 5,
      shapes: <VsdxShape>[icon],
    );

    final cropped = buildSelectionExportPage(page, <int>[
      1,
    ], marginInches: 0.1)!;
    final visible = buildShapeBounds(cropped)[1]!;
    expect(visible.top, closeTo(0.1, 1e-9));
    expect(
      visible.bottom,
      lessThanOrEqualTo(cropped.heightInches - 0.1 + 1e-9),
    );
  });

  test('selection crop includes loose labels and large visual effects', () {
    final connector = VsdxShapeFactory.line(
      id: 1,
      ax: 2,
      ay: 2,
      bx: 2.2,
      by: 2,
    ).copyWith(text: 'A connector label much wider than its edge');
    final effected =
        VsdxShapeFactory.rectangle(
          id: 2,
          pinX: 5,
          pinY: 3,
          width: 1,
          height: 1,
        ).copyWith(
          shadow: const VsdxShadow(
            offsetXInches: 0.25,
            offsetYInches: -0.25,
            blurInches: 0.2,
            transparency: 0,
          ),
          glow: const VsdxGlow(sizeInches: 0.2, transparency: 0),
          reflection: const VsdxReflection(
            sizeInches: 1,
            distanceInches: 0.3,
            blurInches: 0.1,
            transparency: 0,
          ),
        );
    final page = VsdxPage(
      id: 0,
      name: 'Effects',
      widthInches: 9,
      heightInches: 6,
      shapes: <VsdxShape>[connector, effected],
    );

    final labelCrop = buildSelectionExportPage(page, <int>[
      1,
    ], marginInches: 0.1)!;
    expect(labelCrop.widthInches, greaterThan(4));

    final effectCrop = buildSelectionExportPage(page, <int>[
      2,
    ], marginInches: 0.1)!;
    final visible = buildShapeBounds(effectCrop)[2]!;
    expect(visible.left, closeTo(0.1, 1e-9));
    expect(visible.top, closeTo(0.1, 1e-9));
    expect(visible.right, closeTo(effectCrop.widthInches - 0.1, 1e-9));
    expect(visible.bottom, closeTo(effectCrop.heightInches - 0.1, 1e-9));
  });

  test('selection export retains only internal glue rows', () {
    final a = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 1,
      pinY: 1,
      width: 1,
      height: 1,
    );
    final b = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 4,
      pinY: 1,
      width: 1,
      height: 1,
    );
    final edge = VsdxShapeFactory.line(id: 3, ax: 1, ay: 1, bx: 4, by: 1);
    const connects = <VsdxConnect>[
      VsdxConnect(
        fromSheetId: 3,
        fromCell: 'BeginX',
        toSheetId: 1,
        toCell: 'PinX',
      ),
      VsdxConnect(
        fromSheetId: 3,
        fromCell: 'EndX',
        toSheetId: 2,
        toCell: 'PinX',
      ),
    ];
    final page = VsdxPage(
      id: 0,
      name: 'Glue',
      widthInches: 6,
      heightInches: 3,
      shapes: <VsdxShape>[a, b, edge],
      connects: connects,
    );

    expect(
      buildSelectionExportPage(page, <int>[1, 2, 3])!.connects,
      hasLength(2),
    );
    expect(buildSelectionExportPage(page, <int>[1, 3])!.connects, hasLength(1));
    expect(buildSelectionExportPage(page, <int>[3])!.connects, isEmpty);
    expect(buildSelectionExportPage(page, const <int>[]), isNull);
  });

  test('cropped selection page rasterises at its own PNG dimensions', () async {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4,
      pinY: 3,
      width: 1,
      height: 1,
    );
    final page = VsdxPage(
      id: 0,
      name: 'Raster',
      widthInches: 10,
      heightInches: 8,
      shapes: <VsdxShape>[shape],
    );
    final cropped = buildSelectionExportPage(page, <int>[
      1,
    ], marginInches: 0.1)!;

    final png = await renderPageToPng(cropped, pxPerInch: 100);
    expect(png, isNotNull);
    final codec = await ui.instantiateImageCodec(png!);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, (cropped.widthInches * 100).ceil());
    expect(frame.image.height, (cropped.heightInches * 100).ceil());
    frame.image.dispose();
    codec.dispose();
  });
}
