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
/// when the page has layers (export honouring Visio `Print`). [colorByLayer]
/// mirrors the editor's session-level Color-by-Layer view.
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
  bool colorByLayer = false,
}) async {
  // LibreOffice/libvisio fall back to ISO A4 for malformed pages without a
  // PageWidth/PageHeight. Normal documents always carry positive dimensions.
  final safeDpi = pxPerInch.isFinite && pxPerInch > 0 ? pxPerInch : 150.0;
  final pageWidth = page.widthInches.isFinite && page.widthInches > 0
      ? page.widthInches
      : 8.2677165354;
  final pageHeight = page.heightInches.isFinite && page.heightInches > 0
      ? page.heightInches
      : 11.6929133858;
  final w = pageWidth * safeDpi;
  final h = pageHeight * safeDpi;
  final cache = VsdxImageCache();
  try {
    await cache.warmUp(images);
    // Hatching is an enhancement. If the graphics backend cannot allocate a
    // tile in release mode, continue with the painter's solid-fill fallback.
    try {
      await PatternFillBuilder.warmUpShared();
    } catch (_) {
      // Best-effort export; PatternFillBuilder.shared remains usable/empty.
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
    final layerIds =
        visibleLayerIdsOverride ??
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
      pxPerInch: safeDpi,
      backgroundColor: const Color(0xFFFFFFFF),
      respectLayerVisibility: layerIds != null || underlayLayerIds != null,
      visibleLayerIdsOverride: layerIds,
      underlayVisibleLayerIdsOverride: underlayLayerIds,
      drawLineJumps: drawLineJumps,
      lineJumpRadiusInches: lineJumpRadiusInches,
      colorByLayer: colorByLayer,
      // Match SVG export: no fold chevrons / kind-hint dashed frames.
      drawEditorChrome: false,
      drawPageBorder: false,
      drawPlaceholders: false,
      drawNameFallback: false,
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
