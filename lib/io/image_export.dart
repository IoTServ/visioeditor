import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:vsdx/vsdx.dart';

import '../render/image_cache.dart';
import '../render/pattern_fill.dart';
import '../render/vsdx_painter.dart';

/// Rasterise a single [page] to PNG bytes at [pxPerInch] using the same
/// [VsdxPainter] the on-screen canvas uses. Pass [underlayPage] to composite
/// a Visio BackPage; [visibleLayerIdsOverride] defaults to printable layers
/// when the page has layers (export honouring Visio `Print`).
///
/// Embedded pictures in [images] are decoded before paint so the one-shot
/// export path does not fall back to placeholders.
Future<Uint8List?> renderPageToPng(
  VsdxPage page, {
  VsdxTheme theme = VsdxTheme.empty,
  ImageRegistry images = ImageRegistry.empty,
  VsdxPage? underlayPage,
  Set<int>? visibleLayerIdsOverride,
  double pxPerInch = 150.0,
  bool drawLineJumps = true,
  double lineJumpRadiusInches = 0.07,
}) async {
  final w = (page.widthInches <= 0 ? 8.5 : page.widthInches) * pxPerInch;
  final h = (page.heightInches <= 0 ? 11.0 : page.heightInches) * pxPerInch;
  final cache = VsdxImageCache();
  try {
    await cache.warmUp(images);
    await PatternFillBuilder.warmUpShared();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
    final layerIds = visibleLayerIdsOverride ??
        (page.layers.isEmpty ? null : page.printableLayerIds);
    final underlayLayerIds = underlayPage == null || underlayPage.layers.isEmpty
        ? null
        : underlayPage.printableLayerIds;
    VsdxPainter(
      page: page,
      underlayPage: underlayPage,
      theme: theme,
      images: images,
      imageCache: cache,
      patternBuilder: PatternFillBuilder.shared,
      pxPerInch: pxPerInch,
      backgroundColor: const Color(0xFFFFFFFF),
      respectLayerVisibility: layerIds != null || underlayLayerIds != null,
      visibleLayerIdsOverride: layerIds,
      underlayVisibleLayerIdsOverride: underlayLayerIds,
      drawLineJumps: drawLineJumps,
      lineJumpRadiusInches: lineJumpRadiusInches,
      // Match SVG export: no fold chevrons / kind-hint dashed frames.
      drawEditorChrome: false,
    ).paint(canvas, Size(w, h));
    final picture = recorder.endRecording();
    final image = await picture.toImage(w.ceil(), h.ceil());
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  } finally {
    cache.dispose();
  }
}
