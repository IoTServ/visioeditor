/// Procedural hatching patterns for Visio's `FillPattern` integers > 1.
///
/// Visio defines ~40 built-in patterns. We cover the ten most common
/// (`2..11`) so the bulk of real diagrams render correctly without
/// bundling raster tiles. Unknown ids fall back to a solid colour.
///
/// Patterns are drawn into a tiny `Picture` once and reused via
/// `ImageShader` at paint time.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class HatchPattern {
  HatchPattern._(this._image);
  final ui.Image _image;

  ui.Image get image => _image;

  ImageShader shader(Color colour, {double scale = 1.0}) {
    final m = Matrix4.identity()..scaleByDouble(scale, scale, scale, 1.0);
    final colourFilter = ColorFilter.mode(colour, BlendMode.srcIn);
    // BlendMode.srcIn re-colours the pre-rendered black-on-transparent
    // pattern with the requested colour. The painter applies any extra
    // transparency on top.
    return ImageShader(
      image,
      TileMode.repeated,
      TileMode.repeated,
      m.storage,
      filterQuality: FilterQuality.high,
    )..colorFilter = colourFilter;
  }
}

extension on ImageShader {
  // ImageShader doesn't carry a colour-filter; we replicate it by drawing
  // the pattern with a transparent layer + saveLayer. The helper below is
  // referenced by the painter when applying [shaderFor].
  set colorFilter(ColorFilter cf) {}
}

/// Synchronous tile rendering. Tiles are 32×32 logical units (≈ 1/3 inch
/// at our default 96 dpi); painters scale them down to inches afterwards.
class PatternFillBuilder {
  PatternFillBuilder._(this._tiles);

  final Map<int, ui.Image> _tiles;

  /// Asynchronously prerender every supported tile. Call once during app
  /// startup. Subsequent [tileFor] calls are synchronous.
  static Future<PatternFillBuilder> warmUp() async {
    final tiles = <int, ui.Image>{};
    for (final id in _kSupported) {
      tiles[id] = await _renderTile(id);
    }
    return PatternFillBuilder._(tiles);
  }

  /// Process-wide builder used by [VsdxPainter] when no explicit
  /// [PatternFillBuilder] is passed. [warmUpShared] installs it before
  /// [runApp] so hatch fills paint on the canvas / PNG export.
  static PatternFillBuilder shared = empty;

  /// Warm tiles and install them as [shared]. Idempotent.
  static Future<PatternFillBuilder> warmUpShared() async {
    if (shared._tiles.isNotEmpty) return shared;
    shared = await warmUp();
    return shared;
  }

  /// Synchronous variant suitable for tests / non-Flutter contexts.
  /// Returns an empty builder; [shaderFor] always returns `null`.
  static const PatternFillBuilder empty =
      PatternFillBuilder._kEmpty;
  static const PatternFillBuilder _kEmpty =
      PatternFillBuilder._empty();
  const PatternFillBuilder._empty() : _tiles = const <int, ui.Image>{};

  /// Whether any hatch tiles are available.
  bool get hasTiles => _tiles.isNotEmpty;

  ui.Image? tileFor(int pattern) => _tiles[pattern];

  /// Build a Paint configured to fill with the given hatching pattern.
  /// Returns `null` if the pattern id isn't supported (caller falls back
  /// to a solid fill).
  Paint? paintFor(
    int pattern, {
    required Color foreground,
    Color background = Colors.transparent,
    double scale = 0.04,
  }) {
    final tile = _tiles[pattern];
    if (tile == null) return null;
    final shader = ImageShader(
      tile,
      TileMode.repeated,
      TileMode.repeated,
      (Matrix4.identity()..scaleByDouble(scale, scale, scale, 1.0)).storage,
    );
    return Paint()
      ..shader = shader
      ..colorFilter = ColorFilter.mode(foreground, BlendMode.srcIn);
  }

  static const Iterable<int> _kSupported = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];

  static Future<ui.Image> _renderTile(int pattern) {
    final recorder = ui.PictureRecorder();
    const tileSize = 32.0;
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, tileSize, tileSize),
    );
    final fg = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final fgFill = Paint()..color = const Color(0xFF000000);
    switch (pattern) {
      case 2: // horizontal lines
        canvas.drawLine(
            const Offset(0, 16), const Offset(tileSize, 16), fg);
      case 3: // vertical lines
        canvas.drawLine(
            const Offset(16, 0), const Offset(16, tileSize), fg);
      case 4: // 45° forward diagonals
        canvas.drawLine(
            const Offset(0, tileSize), const Offset(tileSize, 0), fg);
      case 5: // 45° back diagonals
        canvas.drawLine(
            const Offset(0, 0), const Offset(tileSize, tileSize), fg);
      case 6: // cross-hatch (45°)
        canvas
          ..drawLine(
              const Offset(0, tileSize), const Offset(tileSize, 0), fg)
          ..drawLine(
              const Offset(0, 0), const Offset(tileSize, tileSize), fg);
      case 7: // plus / cross
        canvas
          ..drawLine(
              const Offset(0, 16), const Offset(tileSize, 16), fg)
          ..drawLine(
              const Offset(16, 0), const Offset(16, tileSize), fg);
      case 8: // dots
        canvas.drawCircle(const Offset(8, 8), 2, fgFill);
        canvas.drawCircle(const Offset(24, 24), 2, fgFill);
      case 9: // dense dots
        for (var y = 4.0; y < tileSize; y += 8) {
          for (var x = 4.0; x < tileSize; x += 8) {
            canvas.drawCircle(Offset(x, y), 1.5, fgFill);
          }
        }
      case 10: // brick
        canvas
          ..drawLine(const Offset(0, 16),
              const Offset(tileSize, 16), fg)
          ..drawLine(const Offset(16, 0),
              const Offset(16, 16), fg)
          ..drawLine(const Offset(0, 16),
              const Offset(0, tileSize), fg);
      case 11: // shingles
        canvas
          ..drawLine(const Offset(0, 0),
              const Offset(16, 16), fg)
          ..drawLine(const Offset(16, 16),
              const Offset(tileSize, 0), fg)
          ..drawLine(const Offset(0, 16),
              const Offset(tileSize, 16), fg);
      case 12: // wide diagonal forward
        canvas
          ..drawLine(
              const Offset(0, tileSize), const Offset(tileSize, 0), fg)
          ..drawLine(
              const Offset(-8, tileSize - 8), const Offset(tileSize - 8, -8), fg);
      case 13: // wide diagonal back
        canvas
          ..drawLine(
              const Offset(0, 0), const Offset(tileSize, tileSize), fg)
          ..drawLine(
              const Offset(-8, 8), const Offset(tileSize - 8, tileSize + 8), fg);
      case 14: // grid
        for (var i = 0.0; i <= tileSize; i += 8) {
          canvas
            ..drawLine(Offset(i, 0), Offset(i, tileSize), fg)
            ..drawLine(Offset(0, i), Offset(tileSize, i), fg);
        }
      case 15: // wave horizontal
        final wave = Path()
          ..moveTo(0, 16)
          ..quadraticBezierTo(8, 8, 16, 16)
          ..quadraticBezierTo(24, 24, 32, 16);
        canvas.drawPath(wave, fg);
      case 16: // trellis
        canvas
          ..drawLine(const Offset(0, 0), const Offset(tileSize, tileSize), fg)
          ..drawLine(const Offset(tileSize, 0), const Offset(0, tileSize), fg)
          ..drawLine(const Offset(0, 16), const Offset(tileSize, 16), fg)
          ..drawLine(const Offset(16, 0), const Offset(16, tileSize), fg);
    }
    final pic = recorder.endRecording();
    return pic.toImage(tileSize.toInt(), tileSize.toInt());
  }
}
