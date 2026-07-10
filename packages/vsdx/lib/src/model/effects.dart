/// Visual effects attached to a shape: shadow + gradient fill stops.
///
/// Kept in a separate module from [VsdxFill] / [VsdxLine] because:
///   * They're optional ⇒ we want them allocated only when present.
///   * They evolve at a different cadence (gradients ⇒ M6, shadows ⇒ M3-09).
library;

import 'package:meta/meta.dart';

import '../utils/color.dart';

/// Drop-shadow parameters (`Shadow*` cells).
@immutable
class VsdxShadow {
  const VsdxShadow({
    this.color,
    this.themeColorIndex,
    this.offsetXInches = 0.05,
    this.offsetYInches = 0.05,
    this.blurInches = 0.04,
    this.transparency = 0.4,
    this.enabled = true,
  });

  /// Resolved colour. When `null` the renderer falls back to
  /// [themeColorIndex] (a grey/black derivative) and finally a neutral
  /// 60%-black.
  final VsdxColor? color;

  /// Theme slot used when [color] is `null`.
  final int? themeColorIndex;

  final double offsetXInches;
  final double offsetYInches;

  /// Gaussian sigma applied via `MaskFilter.blur`.
  final double blurInches;

  /// 0 = fully opaque, 1 = invisible.
  final double transparency;

  /// `true` when the shape's `ShadowPattern` cell is non-zero.
  final bool enabled;

  static const VsdxShadow disabled =
      VsdxShadow(enabled: false, transparency: 1.0);
}

/// Soft "outer glow" effect (`Glow*` cells).
@immutable
class VsdxGlow {
  const VsdxGlow({
    this.color,
    this.themeColorIndex,
    this.sizeInches = 0.05,
    this.transparency = 0.6,
    this.enabled = true,
  });

  final VsdxColor? color;
  final int? themeColorIndex;
  final double sizeInches;
  final double transparency;
  final bool enabled;

  static const VsdxGlow disabled = VsdxGlow(enabled: false, transparency: 1);
}

/// Mirror reflection below the shape (`Reflection*` cells).
@immutable
class VsdxReflection {
  const VsdxReflection({
    this.sizeInches = 0.3,
    this.distanceInches = 0.0,
    this.transparency = 0.6,
    this.blurInches = 0.02,
    this.enabled = true,
  });

  final double sizeInches;
  final double distanceInches;
  final double transparency;
  final double blurInches;
  final bool enabled;

  static const VsdxReflection disabled =
      VsdxReflection(enabled: false, transparency: 1);
}

/// One stop in a gradient fill (`<Section N="FillGradient">` row).
@immutable
class VsdxGradientStop {
  const VsdxGradientStop({
    required this.position,
    this.color,
    this.themeColorIndex,
    this.transparency = 0.0,
  });

  /// 0..1 along the gradient axis.
  final double position;

  /// Resolved colour. `null` → look up [themeColorIndex] at render time.
  final VsdxColor? color;
  final int? themeColorIndex;

  final double transparency;
}

/// Gradient fill descriptor (linear / radial / rectangular).
@immutable
class VsdxGradient {
  const VsdxGradient({
    required this.stops,
    this.type = VsdxGradientType.linear,
    this.angleRad = 0.0,
  });

  final List<VsdxGradientStop> stops;
  final VsdxGradientType type;

  /// Direction angle (radians, CCW from page +X). Ignored for radial.
  final double angleRad;
}

enum VsdxGradientType { linear, radial, rectangular, path }
