import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:vsdx/vsdx.dart';

import '../render/vsdx_painter.dart';

/// Rasterise a single [page] to PNG bytes at [pxPerInch] using the same
/// [VsdxPainter] the on-screen canvas uses.
Future<Uint8List?> renderPageToPng(
  VsdxPage page, {
  VsdxTheme theme = VsdxTheme.empty,
  ImageRegistry images = ImageRegistry.empty,
  double pxPerInch = 150.0,
}) async {
  final w = (page.widthInches <= 0 ? 8.5 : page.widthInches) * pxPerInch;
  final h = (page.heightInches <= 0 ? 11.0 : page.heightInches) * pxPerInch;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
  VsdxPainter(
    page: page,
    theme: theme,
    images: images,
    pxPerInch: pxPerInch,
    backgroundColor: const Color(0xFFFFFFFF),
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
}
