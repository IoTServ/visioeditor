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
}
