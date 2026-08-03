/// Page drawing-scale materialisation shared by the parser and writer.
library;

import 'geometry.dart';
import 'page.dart';
import 'shape.dart';

/// Effective VSDX `PageScale / DrawingScale` ratio.
///
/// libvisio treats a zero DrawingScale as an unscaled page.
double visioDrawingScale(VsdxPageSheet sheet) {
  if (sheet.drawingScale == 0) return 1;
  final scale = (sheet.pageScale / sheet.drawingScale).abs();
  return scale.isFinite ? scale : 1;
}

/// Scale the shape properties libvisio materialises into drawing coordinates.
///
/// Text metrics and shadow offsets are physical values and intentionally stay
/// unchanged. Passing the reciprocal scale converts an edited model shape
/// back to the source-cell coordinate space used by VSDX XML.
VsdxShape scaleVisioDrawingShape(VsdxShape shape, double scale) {
  if (scale == 1.0) return shape;
  final block = shape.richText.textBlock;
  return shape.copyWith(
    pinX: shape.pinX * scale,
    pinY: shape.pinY * scale,
    width: shape.width * scale,
    height: shape.height * scale,
    locPinXInches:
        shape.locPinXInches == null ? null : shape.locPinXInches! * scale,
    locPinYInches:
        shape.locPinYInches == null ? null : shape.locPinYInches! * scale,
    beginX: shape.beginX == null ? null : shape.beginX! * scale,
    beginY: shape.beginY == null ? null : shape.beginY! * scale,
    endX: shape.endX == null ? null : shape.endX! * scale,
    endY: shape.endY == null ? null : shape.endY! * scale,
    geometries: <VsdxGeometry>[
      for (final geometry in shape.geometries)
        geometry.copyWith(
          commands: <VsdxPathCommand>[
            for (final command in geometry.commands)
              scalePathCommand(command, scale, scale),
          ],
        ),
    ],
    line: shape.line.copyWith(
      weightInches: shape.line.weightInches * scale,
      roundingInches: shape.line.roundingInches * scale,
      beginArrowSizeInches: shape.line.beginArrowSizeInches * scale,
      endArrowSizeInches: shape.line.endArrowSizeInches * scale,
    ),
    imgOffsetXInches: shape.imgOffsetXInches * scale,
    imgOffsetYInches: shape.imgOffsetYInches * scale,
    imgWidthInches:
        shape.imgWidthInches == null ? null : shape.imgWidthInches! * scale,
    imgHeightInches:
        shape.imgHeightInches == null ? null : shape.imgHeightInches! * scale,
    richText: shape.richText.copyWith(
      textBlock: block.copyWith(
        pinXInches: block.pinXInches == null ? null : block.pinXInches! * scale,
        pinYInches: block.pinYInches == null ? null : block.pinYInches! * scale,
        locPinXInches:
            block.locPinXInches == null ? null : block.locPinXInches! * scale,
        locPinYInches:
            block.locPinYInches == null ? null : block.locPinYInches! * scale,
        widthInches:
            block.widthInches == null ? null : block.widthInches! * scale,
        heightInches:
            block.heightInches == null ? null : block.heightInches! * scale,
      ),
    ),
    children: <VsdxShape>[
      for (final child in shape.children) scaleVisioDrawingShape(child, scale),
    ],
  );
}

/// Convert a materialised page back to the source-cell coordinate space.
VsdxPage visioSourceScalePage(VsdxPage page) {
  final scale = visioDrawingScale(page.pageSheet);
  if (scale == 1.0 || scale == 0.0) return page;
  final inverse = 1 / scale;
  return page.copyWith(
    widthInches: page.widthInches * inverse,
    heightInches: page.heightInches * inverse,
    shapes: <VsdxShape>[
      for (final shape in page.shapes) scaleVisioDrawingShape(shape, inverse),
    ],
  );
}
