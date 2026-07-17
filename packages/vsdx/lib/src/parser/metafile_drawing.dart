/// Platform-neutral display list for WMF / EMF vector replay.
///
/// The Flutter app rasterises these ops onto a [Canvas]; the vsdx package
/// stays free of `dart:ui` so parsers stay unit-testable.
library;

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
  });

  final List<MetafilePoint> points;
  final bool closed;
  final bool fill;
  final bool stroke;

  /// 0xAARRGGBB
  final int fillArgb;
  final int strokeArgb;
  final double strokeWidth;

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
