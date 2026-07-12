import 'package:flutter/widgets.dart';

/// A lightweight, read-mostly snapshot of the [PageCanvas]'s view transform,
/// published by the canvas and consumed by peripheral widgets (the Outline
/// minimap) that need to know which part of the page is currently on screen.
///
/// Mapping: `viewportPx = contentPx * scale + offset`, where content-px is the
/// page in `inches * pxPerInch` (top-left origin, Y-down).
class CanvasCamera extends ChangeNotifier {
  double scale = 1;
  Offset offset = Offset.zero;
  Size viewport = Size.zero;
  Size content = Size.zero;

  /// Update the published transform; notifies only when something changed so
  /// listeners (the Outline) don't repaint on every canvas rebuild.
  void publish({
    required double scale,
    required Offset offset,
    required Size viewport,
    required Size content,
  }) {
    if (this.scale == scale &&
        this.offset == offset &&
        this.viewport == viewport &&
        this.content == content) {
      return;
    }
    this.scale = scale;
    this.offset = offset;
    this.viewport = viewport;
    this.content = content;
    notifyListeners();
  }

  /// The page area currently visible in the canvas, in content-px, or `null`
  /// before the canvas has laid out.
  Rect? get visibleContentRect {
    if (scale <= 0 || viewport.isEmpty) return null;
    return Rect.fromLTWH(
      -offset.dx / scale,
      -offset.dy / scale,
      viewport.width / scale,
      viewport.height / scale,
    );
  }
}
