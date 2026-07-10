/// Pure-Dart affine transform helpers used by the geometry / render layers.
///
/// We deliberately wrap [Matrix4] (from `vector_math`) instead of relying on
/// Flutter's `Matrix4` typedef — this keeps the math reusable from CLI/server
/// code that has no Flutter dependency.
library;

import 'package:vector_math/vector_math_64.dart';

/// Build an affine transform that places a Visio shape:
///
/// 1. Translate so the shape's pin (anchor) aligns with the origin.
/// 2. Rotate by [angleRad].
/// 3. Translate by `(pinX, pinY)` in page coordinates.
///
/// `pinX`/`pinY` are page-space inches; `localPinX`/`localPinY` are the local
/// anchor (typically `Width/2`, `Height/2` for centred rotation).
Matrix4 shapeTransform({
  required double pinX,
  required double pinY,
  required double localPinX,
  required double localPinY,
  double angleRad = 0,
  bool flipX = false,
  bool flipY = false,
}) {
  final m = Matrix4.identity()
    ..translateByDouble(pinX, pinY, 0.0, 1.0)
    ..rotateZ(angleRad);
  if (flipX || flipY) {
    final sx = flipX ? -1.0 : 1.0;
    final sy = flipY ? -1.0 : 1.0;
    m.scaleByDouble(sx, sy, sx, 1.0);
  }
  m.translateByDouble(-localPinX, -localPinY, 0.0, 1.0);
  return m;
}

/// Build the page → viewport transform.
///
/// Visio page origin is at the **bottom-left** with Y growing up; Flutter's
/// canvas has the origin at the **top-left** with Y growing down. We flip Y
/// and scale by [pxPerInch] so subsequent painter code can think in native
/// page coordinates.
Matrix4 pageToViewportTransform({
  required double pageHeightInches,
  required double pxPerInch,
}) {
  return Matrix4.identity()
    ..translateByDouble(0.0, pageHeightInches * pxPerInch, 0.0, 1.0)
    ..scaleByDouble(pxPerInch, -pxPerInch, pxPerInch, 1.0);
}
