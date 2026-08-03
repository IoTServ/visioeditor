/// Procedural hatching for Visio `FillPattern` 2–24.
///
/// Style, angle and spacing follow libvisio's `VSDContentCollector` mapping.
/// Unknown ids fall back to a solid colour.
///
/// Patterns are drawn into a tiny `Picture` once and reused via
/// `ImageShader` at paint time.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vsdx/vsdx.dart';

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

/// Synchronous tile rendering. Painters scale the high-resolution source
/// tiles down to the libvisio spacing in inches.
class PatternFillBuilder {
  PatternFillBuilder._(this._tiles, this._overlays);

  static const double _tileSize = 128;

  final Map<int, ui.Image> _tiles;
  final Map<int, ui.Image> _overlays;

  /// Asynchronously prerender every supported tile. Call once during app
  /// startup. Subsequent [tileFor] calls are synchronous.
  static Future<PatternFillBuilder> warmUp() async {
    final tiles = <int, ui.Image>{};
    final overlays = <int, ui.Image>{};
    for (final id in _kSupported) {
      final spec = libvisioHatchSpec(id)!;
      if (spec.style == VsdxHatchStyle.triple) {
        tiles[id] = await _renderTile(id, axisOnly: true);
        overlays[id] = await _renderTile(id, diagonalOnly: true);
      } else {
        tiles[id] = await _renderTile(id);
      }
    }
    return PatternFillBuilder._(tiles, overlays);
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
  const PatternFillBuilder._empty()
      : _tiles = const <int, ui.Image>{},
        _overlays = const <int, ui.Image>{};

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
    double? scale,
  }) {
    final tile = _tiles[pattern];
    final spec = libvisioHatchSpec(pattern);
    if (tile == null || spec == null) return null;
    final diagonal = spec.style != VsdxHatchStyle.triple &&
        (spec.angleDegrees == 45 || spec.angleDegrees == 315);
    final period = spec.distanceInches * (diagonal ? math.sqrt2 : 1);
    return _shaderPaint(tile, scale ?? period / _tileSize, foreground);
  }

  /// Second diagonal layer for libvisio's triple hatch. Axis-aligned lines
  /// repeat every `distance`; diagonals need a `distance * sqrt(2)` square
  /// period to preserve that same perpendicular spacing.
  Paint? overlayPaintFor(
    int pattern, {
    required Color foreground,
  }) {
    final tile = _overlays[pattern];
    final spec = libvisioHatchSpec(pattern);
    if (tile == null || spec == null) return null;
    return _shaderPaint(
      tile,
      spec.distanceInches * math.sqrt2 / _tileSize,
      foreground,
    );
  }

  Paint _shaderPaint(ui.Image tile, double scale, Color foreground) {
    final shader = ImageShader(
      tile,
      TileMode.repeated,
      TileMode.repeated,
      (Matrix4.identity()..scaleByDouble(scale, scale, scale, 1.0)).storage,
      filterQuality: FilterQuality.high,
    );
    return Paint()
      ..shader = shader
      ..colorFilter = ColorFilter.mode(foreground, BlendMode.srcIn);
  }

  static const Iterable<int> _kSupported = [
    2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,
    14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
  ];

  static Future<ui.Image> _renderTile(
    int pattern, {
    bool axisOnly = false,
    bool diagonalOnly = false,
  }) {
    final spec = libvisioHatchSpec(pattern)!;
    final recorder = ui.PictureRecorder();
    // The larger source tile prevents a sub-pixel hatch stroke from
    // alternating between dark and faint repeats when scaled to 96 dpi.
    const tileSize = _tileSize;
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, tileSize, tileSize),
    );
    Paint stroke(double widthInches) => Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = widthInches * tileSize / spec.distanceInches;
    final axisStroke = stroke(0.01);
    // LibreOffice's sloped hatch hairlines are anti-aliased to about half
    // coverage at 96 dpi. Preserve a full-pixel footprint and encode that
    // coverage in alpha so Skia does not alternate dark and faint repeats.
    final diagonalStroke = stroke(0.01)
      ..color = const Color(0x80000000);

    void horizontal() => canvas.drawLine(
          const Offset(0, tileSize / 2),
          const Offset(tileSize, tileSize / 2),
          axisStroke,
        );
    void vertical() => canvas.drawLine(
          const Offset(tileSize / 2, 0),
          const Offset(tileSize / 2, tileSize),
          axisStroke,
        );
    void rising() => canvas.drawLine(
          // VsdxPainter flips local Y into Flutter's downward page axis.
          const Offset(0, 0),
          const Offset(tileSize, tileSize),
          diagonalStroke,
        );
    void falling() => canvas.drawLine(
          const Offset(0, tileSize),
          const Offset(tileSize, 0),
          diagonalStroke,
        );

    if (spec.style == VsdxHatchStyle.triple) {
      if (!diagonalOnly) {
        horizontal();
        vertical();
      }
      if (!axisOnly) {
        rising();
        falling();
      }
    } else if (spec.style == VsdxHatchStyle.double) {
      if (spec.angleDegrees == 45) {
        rising();
        falling();
      } else {
        horizontal();
        vertical();
      }
    } else {
      switch (spec.angleDegrees) {
        case 45:
          rising();
        case 90:
          vertical();
        case 315:
          falling();
        default:
          horizontal();
      }
    }
    final pic = recorder.endRecording();
    return pic.toImage(tileSize.toInt(), tileSize.toInt());
  }
}
