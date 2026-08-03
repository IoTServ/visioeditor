import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/render/shape_bounds.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('buildShapeBounds includes elbow bend outside Begin→End box', () {
    final conn = VsdxShapeFactory.line(id: 1, ax: 1, ay: 2, bx: 5, by: 2)
        .copyWith(waypoints: const [Offset2D(3, 2), Offset2D(3, 5)])
        .reshapeAsPolyline(const [
      Offset2D(1, 2),
      Offset2D(3, 2),
      Offset2D(3, 5),
      Offset2D(5, 2),
    ]);
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 10,
      heightInches: 10,
      shapes: <VsdxShape>[conn],
    );
    final box = buildShapeBounds(page)[1]!;
    // Page Y-up values are stored directly in Rect (minY→top, maxY→bottom).
    expect(box.bottom, greaterThanOrEqualTo(5 - 0.25));
    expect(box.height, greaterThan(2.5));
  });

  test('buildShapeBounds includes caption text block below the shape', () {
    const labelH = 0.22;
    final icon = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 2,
      pinY: 2,
      width: 0.75,
      height: 0.75,
    ).copyWith(
      text: 'Cloud',
      richText: VsdxRichText(
        runs: const <VsdxTextRun>[VsdxTextRun(text: 'Cloud')],
        textBlock: VsdxTextBlock(
          pinXInches: 0.375,
          pinYInches: 0,
          locPinXInches: 0.375,
          locPinYInches: labelH,
          widthInches: 0.75,
          heightInches: labelH,
        ),
      ),
    );
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 10,
      heightInches: 10,
      shapes: <VsdxShape>[icon],
    );
    final box = buildShapeBounds(page)[2]!;
    // Caption sits under the local box (y=0 bottom); page pin is centre.
    expect(box.top, lessThan(2 - 0.75 / 2));
  });

  test('buildShapeBounds includes a loose connector label plate', () {
    final connector = VsdxShapeFactory.line(
      id: 3,
      ax: 2,
      ay: 2,
      bx: 2.2,
      by: 2,
    ).copyWith(text: 'A connector label much wider than its edge');
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 5,
      shapes: <VsdxShape>[connector],
    );

    final box = buildShapeBounds(page)[3]!;

    expect(box.width, greaterThan(3.8));
    expect(box.center.dx, closeTo(2.1, 1e-9));
  });

  test('buildShapeBounds keeps an off-page InfiniteLine that crosses page', () {
    const shape = VsdxShape(
      id: 6,
      name: 'Infinite',
      pinX: 20,
      pinY: 3,
      width: 0.01,
      height: 0.01,
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            InfiniteLineCmd(x: 0, y: 0.005, a: 0.01, b: 0.005),
          ],
        ),
      ],
    );
    const page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 10,
      heightInches: 6,
      shapes: <VsdxShape>[shape],
    );

    final box = buildShapeBounds(page)[6]!;

    expect(box.left, lessThanOrEqualTo(0));
    expect(box.right, greaterThanOrEqualTo(10));
  });

  test('buildShapeBounds includes label padding and visual effects', () {
    final padded =
        VsdxShapeFactory.rectangle(
              id: 4,
              pinX: 2,
              pinY: 2,
              width: 0.5,
              height: 0.5,
            )
            .copyWith(
              text: 'Padded',
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[VsdxTextRun(text: 'Padded')],
                textBlock: VsdxTextBlock(backgroundColor: VsdxColor.white),
              ),
            )
            .withLabelPadding(const VsdxLabelPadding(left: 20));
    final effected =
        VsdxShapeFactory.rectangle(
          id: 5,
          pinX: 4,
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
      name: 'P',
      widthInches: 8,
      heightInches: 6,
      shapes: <VsdxShape>[padded, effected],
    );
    final bounds = buildShapeBounds(page);

    expect(bounds[4]!.left, closeTo(2 - 0.25 - 20 / 96, 1e-9));
    expect(bounds[5]!.left, closeTo(2.7, 1e-9));
    expect(bounds[5]!.right, closeTo(5.35, 1e-9));
    expect(bounds[5]!.top, closeTo(0.9, 1e-9));
    expect(bounds[5]!.bottom, closeTo(4.3, 1e-9));
  });
}
