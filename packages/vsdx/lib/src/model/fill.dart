/// Shape-level fill description.
///
/// Solid / theme colours, transparencies, `FillPattern` (canvas+SVG render
/// hatch ids 2–16; the VSD parser converts classic gradient ids 25–40 to
/// [gradient]), and optional gradient stops.
library;

import 'package:meta/meta.dart';

import '../utils/color.dart';
import 'effects.dart';

/// Baseline fill before a parsed Visio shape applies a master or style.
///
/// libvisio starts with `FillPattern=0`. Its inactive internal colour slots
/// must stay unresolved in the editable model so a save does not invent
/// `FillForegnd` / `FillBkgnd` cells that were absent from the source.
const VsdxFill libvisioShapeFillDefault = VsdxFill(pattern: 0);

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

  /// `0` = no fill. `1` = solid. `2–16` = hatch (canvas + SVG). Binary VSD
  /// gradient ids 25–40 retain their original value and also populate
  /// [gradient]. Other ids fall back to solid foreground.
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
  ///
  /// For solid / no-fill patterns the hatch-only `FillBkgnd` theme slot is also
  /// cleared so a later hatch switch cannot revive a stale AccentColor.
  VsdxFill withSolidForeground(VsdxColor color) => VsdxFill(
        foreground: color,
        background: background,
        foregroundTransparency: foregroundTransparency,
        backgroundTransparency: backgroundTransparency,
        pattern: pattern == 0 ? 1 : pattern,
        themeForegroundIndex: null,
        themeBackgroundIndex: pattern > 1 ? themeBackgroundIndex : null,
      );

  /// Solid hatch background colour (`FillBkgnd`), clearing any theme binding.
  VsdxFill withSolidBackground(VsdxColor color) => VsdxFill(
        foreground: foreground,
        background: color,
        foregroundTransparency: foregroundTransparency,
        backgroundTransparency: backgroundTransparency,
        pattern: pattern <= 1 ? 2 : pattern,
        themeForegroundIndex: themeForegroundIndex,
        themeBackgroundIndex: null,
        gradient: null,
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

  /// Bind hatch background to a document theme slot (`FillBkgnd` THEMEVAL).
  VsdxFill withThemeBackground(int slot) => VsdxFill(
        foreground: foreground,
        background: null,
        foregroundTransparency: foregroundTransparency,
        backgroundTransparency: backgroundTransparency,
        pattern: pattern <= 1 ? 2 : pattern,
        themeForegroundIndex: themeForegroundIndex,
        themeBackgroundIndex: slot,
        gradient: null,
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
    bool clearThemeForegroundIndex = false,
    bool clearThemeBackgroundIndex = false,
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
      themeForegroundIndex: clearThemeForegroundIndex
          ? null
          : (themeForegroundIndex ?? this.themeForegroundIndex),
      themeBackgroundIndex: clearThemeBackgroundIndex
          ? null
          : (themeBackgroundIndex ?? this.themeBackgroundIndex),
      gradient: identical(gradient, keepGradient)
          ? this.gradient
          : gradient as VsdxGradient?,
    );
  }
}
