/// Shared Visio gradient helpers (SVG export + Flutter canvas).
library;

/// Visio `FillGradientDir` / `LineGradientDir` 1–7 → radial origin within
/// an axis-aligned box. `4` / `null` / unknown → centre.
({double x, double y}) radialGradientOrigin({
  int? dir,
  required double minX,
  required double minY,
  required double width,
  required double height,
}) {
  final left = minX;
  final right = minX + width;
  final top = minY;
  final bottom = minY + height;
  final cx = left + width / 2;
  final cy = top + height / 2;
  return switch (dir) {
    1 => (x: left, y: top),
    2 => (x: cx, y: top),
    3 => (x: right, y: top),
    5 => (x: left, y: bottom),
    6 => (x: cx, y: bottom),
    7 => (x: right, y: bottom),
    _ => (x: cx, y: cy), // 4 / null / legacy
  };
}
