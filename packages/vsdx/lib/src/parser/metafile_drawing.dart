/// Platform-neutral display list for WMF / EMF vector replay.
///
/// The Flutter app rasterises these ops onto a [Canvas]; the vsdx package
/// stays free of `dart:ui` so parsers stay unit-testable.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

@immutable
class MetafilePoint {
  const MetafilePoint(this.x, this.y);
  final double x;
  final double y;
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
    this.isEllipse = false,
    this.fillHatch,
    this.fillBackgroundArgb,
  });

  final List<MetafilePoint> points;
  final bool closed;
  final bool fill;
  final bool stroke;

  /// 0xAARRGGBB
  final int fillArgb;
  final int strokeArgb;
  final double strokeWidth;

  /// GDI `BS_HATCHED` style (`HS_HORIZONTAL` 0 through `HS_DIAGCROSS` 5).
  /// `null` means an ordinary solid fill.
  final int? fillHatch;

  /// Opaque GDI background colour for a hatched brush. A null value keeps the
  /// spaces between hatch strokes transparent (`BKMODE=TRANSPARENT`).
  final int? fillBackgroundArgb;

  /// When true, [points] are the bounding box corners of an ellipse.
  final bool isEllipse;
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

  /// Mixed [MetafilePathOp] / [MetafileTextOp] in paint order.
  final List<Object> ops;

  double get width => (maxX - minX).abs().clamp(1.0, 1e9);
  double get height => (maxY - minY).abs().clamp(1.0, 1e9);

  bool get isEmpty => ops.isEmpty;
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
