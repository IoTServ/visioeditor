/// Per-page [Picture] cache for interactive viewing.
///
/// Recording the full page into a [Picture] once and replaying it on every
/// frame avoids re-walking the shape tree during pan/zoom — a noticeable win
/// on dense drawings. The cache is invalidated when the underlying page,
/// theme, layer visibility, or embedded-image decode generation changes.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'vsdx_painter.dart';

/// Holds at most one cached [Picture] for a (page, painter-config) pair.
class VsdxPagePictureCache {
  ui.Picture? _picture;
  Object? _pageKey;
  int _imageEpoch = -1;
  double _widthPx = 0;
  double _heightPx = 0;

  /// Paint [painter] onto [canvas], reusing a cached [Picture] when valid.
  void paint(Canvas canvas, Size size, VsdxPainter painter) {
    final page = painter.page;
    final epoch = painter.imageCache?.decodeEpoch ?? 0;
    final key = Object.hash(
      page,
      painter.theme,
      painter.images,
      painter.visibleLayerIdsOverride,
      painter.pxPerInch,
      painter.respectLayerVisibility,
      painter.patternBuilder,
    );
    final needsRebuild = _picture == null ||
        _pageKey != key ||
        _imageEpoch != epoch ||
        _widthPx != size.width ||
        _heightPx != size.height;

    if (needsRebuild) {
      _picture?.dispose();
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), size);
      _picture = recorder.endRecording();
      _pageKey = key;
      _imageEpoch = epoch;
      _widthPx = size.width;
      _heightPx = size.height;
    }
    canvas.drawPicture(_picture!);
  }

  void clear() {
    _picture?.dispose();
    _picture = null;
    _pageKey = null;
    _imageEpoch = -1;
  }

  void dispose() => clear();
}
