/// Shape-level fill description.
///
/// M3 scope: solid foreground / background colours + transparencies + an
/// integer `FillPattern` selector. Gradient stops and pattern definitions
/// arrive in M6 (advanced graphics).
library;

import 'package:meta/meta.dart';

import '../utils/color.dart';
import 'effects.dart';

@immutable
class VsdxFill {
  const VsdxFill({
    this.foreground,
    this.background,
    this.foregroundTransparency = 0.0,
    this.backgroundTransparency = 0.0,
    this.pattern = 1,
    this.themeForegroundIndex,
    this.themeBackgroundIndex,
    this.gradient,
  });

  /// Primary fill colour. `null` means the colour is unresolved (e.g. a
  /// `THEMEVAL()` formula that the renderer must look up against the
  /// document's [VsdxTheme] using [themeForegroundIndex]).
  final VsdxColor? foreground;
  final VsdxColor? background;

  /// 0 = fully opaque, 1 = fully transparent (Visio convention).
  final double foregroundTransparency;
  final double backgroundTransparency;

  /// `0` = no fill. `1` = solid. `> 1` = pattern (rendered as solid until
  /// M6).
  final int pattern;

  /// Theme slot to use when [foreground] is `null`. See `lib/model/theme.dart`
  /// `ThemeSlot` for the canonical id constants.
  final int? themeForegroundIndex;
  final int? themeBackgroundIndex;

  /// Optional gradient overlay. When present the renderer prefers it over
  /// the solid [foreground] colour. `null` means "no gradient".
  final VsdxGradient? gradient;

  bool get hasFill => pattern != 0;
  bool get hasGradient => gradient != null && gradient!.stops.isNotEmpty;

  /// Default sentinel for shapes without an explicit Fill section.
  static const VsdxFill defaultFill = VsdxFill();

  /// Solid foreground colour, clearing any theme-slot binding and any gradient
  /// so the painted colour is exactly [color] (draw.io palette swatch behaviour).
  VsdxFill withSolidForeground(VsdxColor color) => VsdxFill(
        foreground: color,
        background: background,
        foregroundTransparency: foregroundTransparency,
        backgroundTransparency: backgroundTransparency,
        pattern: pattern == 0 ? 1 : pattern,
        themeForegroundIndex: null,
        themeBackgroundIndex: themeBackgroundIndex,
      );

  /// Bind fill to a document theme slot ([ThemeSlot]), clearing the explicit
  /// foreground and any gradient so the renderer resolves via `THEMEVAL` /
  /// [VsdxTheme].
  VsdxFill withThemeForeground(int slot) => VsdxFill(
        foreground: null,
        background: background,
        foregroundTransparency: foregroundTransparency,
        backgroundTransparency: backgroundTransparency,
        pattern: pattern == 0 ? 1 : pattern,
        themeForegroundIndex: slot,
        themeBackgroundIndex: themeBackgroundIndex,
      );

  /// Install (or clear, when [gradient] is `null`) a fill gradient. Enables
  /// solid fill when a gradient is set on a no-fill shape.
  VsdxFill withGradient(VsdxGradient? gradient) => VsdxFill(
        foreground: foreground,
        background: background,
        foregroundTransparency: foregroundTransparency,
        backgroundTransparency: backgroundTransparency,
        pattern: gradient != null && pattern == 0 ? 1 : pattern,
        themeForegroundIndex: themeForegroundIndex,
        themeBackgroundIndex: themeBackgroundIndex,
        gradient: gradient,
      );

  /// Sentinel for [copyWith] so callers can clear [gradient] to `null`.
  static const Object keepGradient = Object();

  VsdxFill copyWith({
    VsdxColor? foreground,
    VsdxColor? background,
    double? foregroundTransparency,
    double? backgroundTransparency,
    int? pattern,
    int? themeForegroundIndex,
    int? themeBackgroundIndex,
    Object? gradient = keepGradient,
  }) {
    return VsdxFill(
      foreground: foreground ?? this.foreground,
      background: background ?? this.background,
      foregroundTransparency:
          foregroundTransparency ?? this.foregroundTransparency,
      backgroundTransparency:
          backgroundTransparency ?? this.backgroundTransparency,
      pattern: pattern ?? this.pattern,
      themeForegroundIndex: themeForegroundIndex ?? this.themeForegroundIndex,
      themeBackgroundIndex: themeBackgroundIndex ?? this.themeBackgroundIndex,
      gradient: identical(gradient, keepGradient)
          ? this.gradient
          : gradient as VsdxGradient?,
    );
  }
}
