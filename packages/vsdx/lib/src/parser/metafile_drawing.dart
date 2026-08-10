/// Platform-neutral display list for WMF / EMF vector replay.
///
/// The Flutter app rasterises these ops onto a [Canvas]; the vsdx package
/// stays free of `dart:ui` so parsers stay unit-testable.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

@immutable
class MetafilePoint {
  const MetafilePoint(this.x, this.y);
  final double x;
  final double y;
}

/// Axis-aligned GDI rectangle in metafile logical coordinates.
@immutable
class MetafileRect {
  const MetafileRect(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get minX => math.min(left, right);
  double get minY => math.min(top, bottom);
  double get maxX => math.max(left, right);
  double get maxY => math.max(top, bottom);
  double get width => maxX - minX;
  double get height => maxY - minY;

  List<MetafilePoint> get corners => <MetafilePoint>[
        MetafilePoint(minX, minY),
        MetafilePoint(maxX, minY),
        MetafilePoint(maxX, maxY),
        MetafilePoint(minX, maxY),
      ];
}

/// GDI clipping operation retained in metafile paint order.
enum MetafileClipCombineMode { intersect, exclude }

/// GDI ROP2 foreground mix modes retained for vector paint operations.
///
/// LibreOffice maps R2_NOT (6) to invert, R2_XORPEN (7) to xor, and
/// R2_NOP (11) to transparent output; the remaining ROP2 values use the
/// normal overpaint path in its metafile renderer.
enum MetafileRasterOperation { overpaint, invert, xor, nop }

/// Save the current GDI device context before later state or clip changes.
@immutable
class MetafileSaveDcOp {
  const MetafileSaveDcOp();
}

/// Restore one or more previously saved GDI device contexts.
@immutable
class MetafileRestoreDcOp {
  const MetafileRestoreDcOp({this.count = 1}) : assert(count > 0);

  final int count;
}

/// Concatenate a GDI logical-to-device transform with the active transform.
@immutable
class MetafileTransformOp {
  const MetafileTransformOp({
    required this.m11,
    required this.m12,
    required this.m21,
    required this.m22,
    required this.dx,
    required this.dy,
  });

  final double m11;
  final double m12;
  final double m21;
  final double m22;
  final double dx;
  final double dy;
}

/// Intersect the active clip region with, or exclude, an axis-aligned rect.
@immutable
class MetafileClipRectOp {
  const MetafileClipRectOp({required this.rect, required this.mode});

  final MetafileRect rect;
  final MetafileClipCombineMode mode;
}

/// A single GDI device pixel retained in metafile paint order.
@immutable
class MetafilePixelOp {
  const MetafilePixelOp({required this.x, required this.y, required this.argb});

  final double x;
  final double y;

  /// 0xAARRGGBB
  final int argb;
}

/// A decoded WMF/EMF DIB retained at its authored position in paint order.
@immutable
class MetafileBitmapOp {
  const MetafileBitmapOp({
    required this.bmpBytes,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.destination,
    this.source,
    this.destinationParallelogram,
    this.rasterOperation = 0x00cc0020,
    this.opacity = 1,
  })  : assert(
          destinationParallelogram == null ||
              destinationParallelogram.length == 3,
        ),
        assert(opacity >= 0 && opacity <= 1);

  /// Complete BMP stream (14-byte file header followed by the source DIB).
  final Uint8List bmpBytes;
  final int pixelWidth;
  final int pixelHeight;

  /// Directed destination rectangle. Reversed edges retain GDI mirroring.
  final MetafileRect destination;

  /// Optional directed source crop in bitmap pixel coordinates.
  final MetafileRect? source;

  /// Optional upper-left, upper-right, and lower-left destination corners.
  ///
  /// EMR_PLGBLT uses these points instead of an axis-aligned destination.
  final List<MetafilePoint>? destinationParallelogram;

  /// Authored ternary raster operation (SRCCOPY by default).
  final int rasterOperation;

  /// Constant source alpha applied after any per-pixel alpha channel.
  final double opacity;
}

/// A colored point in an EMR_GRADIENTFILL mesh.
@immutable
class MetafileGradientVertex {
  const MetafileGradientVertex({required this.point, required this.argb});

  final MetafilePoint point;
  final int argb;
}

/// A horizontal or vertical two-color EMR_GRADIENTFILL rectangle.
@immutable
class MetafileGradientRectOp {
  const MetafileGradientRectOp({
    required this.upperLeft,
    required this.lowerRight,
    required this.horizontal,
  });

  final MetafileGradientVertex upperLeft;
  final MetafileGradientVertex lowerRight;
  final bool horizontal;
}

/// A three-color EMR_GRADIENTFILL triangle.
@immutable
class MetafileGradientTriangleOp {
  const MetafileGradientTriangleOp({
    required this.first,
    required this.second,
    required this.third,
  });

  final MetafileGradientVertex first;
  final MetafileGradientVertex second;
  final MetafileGradientVertex third;
}

/// An additional figure in a compound GDI path.
@immutable
class MetafilePathContour {
  const MetafilePathContour({required this.points, required this.closed});

  final List<MetafilePoint> points;
  final bool closed;
}

@immutable
class MetafilePathOp {
  const MetafilePathOp({
    required this.points,
    required this.closed,
    required this.fill,
    required this.stroke,
    required this.fillArgb,
    required this.strokeArgb,
    required this.strokeWidth,
    this.strokeDashPattern,
    this.isEllipse = false,
    this.cornerRadiusX,
    this.cornerRadiusY,
    this.fillHatch,
    this.fillBackgroundArgb,
    this.additionalContours = const <MetafilePathContour>[],
    this.evenOddFill = false,
    this.rasterOperation = MetafileRasterOperation.overpaint,
  });

  final List<MetafilePoint> points;
  final bool closed;
  final bool fill;
  final bool stroke;

  /// 0xAARRGGBB
  final int fillArgb;
  final int strokeArgb;
  final double strokeWidth;

  /// GDI dash/gap lengths in metafile logical units. `null` means solid.
  final List<double>? strokeDashPattern;

  /// GDI `BS_HATCHED` style (`HS_HORIZONTAL` 0 through `HS_DIAGCROSS` 5).
  /// `null` means an ordinary solid fill.
  final int? fillHatch;

  /// Opaque GDI background colour for a hatched brush. A null value keeps the
  /// spaces between hatch strokes transparent (`BKMODE=TRANSPARENT`).
  final int? fillBackgroundArgb;

  /// When true, [points] are the bounding box corners of an ellipse.
  final bool isEllipse;

  /// Rounded-rectangle corner radii in metafile logical units. Both values
  /// are present only for GDI `ROUNDRECT` records.
  final double? cornerRadiusX;
  final double? cornerRadiusY;

  /// Further figures painted as part of the same compound GDI path.
  final List<MetafilePathContour> additionalContours;

  /// GDI `ALTERNATE` polygon fill mode; false represents `WINDING`.
  final bool evenOddFill;

  /// The ROP2 mode active when this path was painted.
  final MetafileRasterOperation rasterOperation;
}

/// Convert the low `PS_STYLE_MASK` bits of a GDI pen into dash/gap lengths.
///
/// LibreOffice uses one mapped `(penWidth + 1)` unit for dots and gaps, and
/// three units for dashes. Keeping that authored pattern in the neutral
/// display list lets Canvas and SVG replay the same WMF/EMF pen.
List<double>? metafileGdiDashPattern(int penStyle, double rawPenWidth) {
  if (!rawPenWidth.isFinite) return null;
  final unit = rawPenWidth.abs() + 1;
  final values = switch (penStyle & 0x0f) {
    1 => <double>[unit * 3, unit], // PS_DASH
    2 => <double>[unit, unit], // PS_DOT
    3 => <double>[unit * 3, unit, unit, unit], // PS_DASHDOT
    4 => <double>[unit * 3, unit, unit, unit, unit, unit], // PS_DASHDOTDOT
    _ => null,
  };
  return values == null ? null : List<double>.unmodifiable(values);
}

@immutable
class MetafileTextOp {
  const MetafileTextOp({
    required this.text,
    required this.x,
    required this.y,
    required this.fontHeight,
    required this.argb,
    this.face,
    this.align = 0,
    this.backgroundArgb,
    this.opaqueRect,
    this.clipRect,
    this.advancesX,
    this.advancesY,
    this.fontWeight = 400,
    this.italic = false,
    this.underline = false,
    this.strikeThrough = false,
    this.escapementDegrees = 0,
  });

  final String text;
  final double x;
  final double y;

  /// Font cell height in metafile logical units (absolute value).
  final double fontHeight;
  final int argb;
  final String? face;

  /// WMF/EMF text-align flags (TA_* low bits).
  final int align;

  /// GDI text background selected by `SETBKMODE(OPAQUE)` / `SETBKCOLOR`.
  final int? backgroundArgb;

  /// Record-space rectangle filled for `ExtTextOut(ETO_OPAQUE)`. This is
  /// axis-aligned in logical coordinates and is independent of font rotation.
  final MetafileRect? opaqueRect;

  /// Record-space clipping rectangle selected by `ExtTextOut(ETO_CLIPPED)`.
  final MetafileRect? clipRect;

  /// Optional GDI `ExtTextOut` advance for each Unicode scalar value. These
  /// override platform font metrics so metafile labels keep their authored
  /// width and per-glyph positions.
  final List<double>? advancesX;

  /// Optional vertical component used by `ETO_PDY` records.
  final List<double>? advancesY;

  /// GDI LOGFONT styling retained independently of the host font backend.
  final int fontWeight;
  final bool italic;
  final bool underline;
  final bool strikeThrough;

  /// LOGFONT escapement in degrees. Positive values rotate counter-clockwise
  /// in GDI's logical coordinate system.
  final double escapementDegrees;
}

/// GDI current position after replaying [op] with `TA_UPDATECP`.
///
/// The text reference point first receives right/centre alignment, then the
/// authored glyph advances, and finally LOGFONT escapement rotation in GDI's
/// Y-down coordinate system. Both WMF and EMF parsers use this shared rule so
/// a following text or line record starts at the same logical point.
MetafilePoint metafileTextUpdatedCurrentPoint(MetafileTextOp op) {
  final glyphCount = op.text.runes.length;
  final xAdvances = op.advancesX;
  final yAdvances = op.advancesY;
  final hasAdvances = xAdvances != null &&
      xAdvances.length == glyphCount &&
      xAdvances.every((advance) => advance.isFinite) &&
      (yAdvances == null ||
          (yAdvances.length == glyphCount &&
              yAdvances.every((advance) => advance.isFinite)));
  final advanceX = hasAdvances
      ? xAdvances.fold<double>(0, (sum, advance) => sum + advance)
      : op.fontHeight.abs() * 0.55 * glyphCount;
  final advanceY = hasAdvances && yAdvances != null
      ? yAdvances.fold<double>(0, (sum, advance) => sum + advance)
      : 0.0;
  final width = advanceX.abs();
  final alignedX = switch (op.align & 0x06) {
    6 => -width / 2,
    2 => -width,
    _ => 0.0,
  };
  final dx = alignedX + advanceX;
  final angle = op.escapementDegrees * math.pi / 180;
  final cosA = math.cos(angle);
  final sinA = math.sin(angle);
  return MetafilePoint(
    op.x + dx * cosA + advanceY * sinA,
    op.y - dx * sinA + advanceY * cosA,
  );
}

@immutable
class MetafileDrawing {
  const MetafileDrawing({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    required this.ops,
  });

  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  /// Mixed drawing and GDI device-context operations in paint order.
  final List<Object> ops;

  double get width => (maxX - minX).abs().clamp(1.0, 1e9);
  double get height => (maxY - minY).abs().clamp(1.0, 1e9);

  bool get isEmpty => !ops.any(
        (op) =>
            op is MetafilePixelOp ||
            op is MetafileBitmapOp ||
            op is MetafileGradientRectOp ||
            op is MetafileGradientTriangleOp ||
            op is MetafilePathOp ||
            op is MetafileTextOp,
      );
}

/// Densify cubic Bezier control points (start + n×(c1,c2,end)) into a polyline.
List<MetafilePoint> densifyPolyBezier(
  List<MetafilePoint> pts, {
  int steps = 8,
}) {
  if (pts.length < 4) return pts;
  final out = <MetafilePoint>[pts.first];
  for (var i = 1; i + 2 < pts.length; i += 3) {
    final p0 = out.last;
    final p1 = pts[i];
    final p2 = pts[i + 1];
    final p3 = pts[i + 2];
    for (var s = 1; s <= steps; s++) {
      final t = s / steps;
      final u = 1 - t;
      final x = u * u * u * p0.x +
          3 * u * u * t * p1.x +
          3 * u * t * t * p2.x +
          t * t * t * p3.x;
      final y = u * u * u * p0.y +
          3 * u * u * t * p1.y +
          3 * u * t * t * p2.y +
          t * t * t * p3.y;
      out.add(MetafilePoint(x, y));
    }
  }
  return out;
}

/// Project GDI radial endpoints onto [bounds] and approximate the selected
/// ellipse arc with the same direction and point-density rules as
/// LibreOffice's `tools::Polygon` metafile path conversion.
///
/// GDI angles use an Y-up parameter even though logical coordinates are
/// normally Y-down. Equal radial endpoints denote a complete ellipse.
List<MetafilePoint> densifyMetafileEllipticalArc(
  MetafileRect bounds,
  MetafilePoint start,
  MetafilePoint end, {
  bool clockwise = false,
}) {
  final radiusX = bounds.width / 2;
  final radiusY = bounds.height / 2;
  if (!radiusX.isFinite || !radiusY.isFinite || radiusX <= 0 || radiusY <= 0) {
    return const <MetafilePoint>[];
  }
  final centerX = (bounds.minX + bounds.maxX) / 2;
  final centerY = (bounds.minY + bounds.maxY) / 2;

  double parameter(MetafilePoint point) => math.atan2(
        radiusX * (centerY - point.y),
        radiusY * (point.x - centerX),
      );

  var angle = parameter(start);
  final endAngle = parameter(end);
  var sweep = endAngle - angle;
  if (!clockwise) {
    if (sweep <= 0) sweep += 2 * math.pi;
  } else {
    sweep = 2 * math.pi - sweep;
    if (sweep > 2 * math.pi) sweep -= 2 * math.pi;
    sweep = -sweep;
  }

  var fullPointCount = (math.pi *
          (1.5 * (radiusX + radiusY) - math.sqrt((radiusX * radiusY).abs())))
      .clamp(32.0, 256.0)
      .floor();
  if (radiusX > 32 && radiusY > 32 && radiusX + radiusY < 8192) {
    fullPointCount >>= 1;
  }
  final pointCount = math.max(
    ((sweep.abs() / (2 * math.pi)) * fullPointCount).floor(),
    16,
  );
  final step = sweep / (pointCount - 1);
  final points = <MetafilePoint>[];
  for (var i = 0; i < pointCount; i++, angle += step) {
    points.add(MetafilePoint(
      centerX + radiusX * math.cos(angle),
      centerY - radiusY * math.sin(angle),
    ));
  }
  return List<MetafilePoint>.unmodifiable(points);
}

/// Approximate EMF `ANGLEARC` using its authored degree angles.
///
/// LibreOffice reverses the start/end traversal when the device context uses
/// clockwise arc direction, while negative sweeps retain their own direction.
List<MetafilePoint> densifyMetafileAngleArc(
  MetafilePoint center,
  double radius,
  double startDegrees,
  double sweepDegrees, {
  bool clockwise = false,
}) {
  if (!radius.isFinite ||
      radius <= 0 ||
      !startDegrees.isFinite ||
      !sweepDegrees.isFinite ||
      sweepDegrees == 0) {
    return const <MetafilePoint>[];
  }
  var start = startDegrees * math.pi / 180;
  var end = start + sweepDegrees * math.pi / 180;
  if (clockwise) {
    final oldStart = start;
    start = end;
    end = oldStart;
  }
  final pointCount =
      (((end - start).abs() / (math.pi / 128)).floor() + 1).clamp(2, 65536);
  final step = (end - start) / (pointCount - 1);
  return List<MetafilePoint>.unmodifiable(List<MetafilePoint>.generate(
    pointCount,
    (index) {
      final angle = start + step * index;
      return MetafilePoint(
        center.x + radius * math.cos(angle),
        center.y - radius * math.sin(angle),
      );
    },
    growable: false,
  ));
}
