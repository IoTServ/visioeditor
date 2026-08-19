/// Shape-level fill description.
///
/// Solid / theme colours, transparencies, `FillPattern` (canvas+SVG render
/// libvisio hatch ids 2–24; VSD/VSDX parsers convert classic gradient ids
/// 25–40 to [gradient]), and optional gradient stops.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../utils/color.dart';
import 'effects.dart';

/// Baseline fill before a parsed Visio shape applies a master or style.
///
/// libvisio starts with `FillPattern=0`. Its inactive internal colour slots
/// must stay unresolved in the editable model so a save does not invent
/// `FillForegnd` / `FillBkgnd` cells that were absent from the source.
const VsdxFill libvisioShapeFillDefault = VsdxFill(pattern: 0);

/// libvisio's rendering classification for classic `FillPattern` 2–24.
enum VsdxHatchStyle { single, double, triple }

@immutable
class VsdxHatchSpec {
  const VsdxHatchSpec({
    required this.style,
    required this.angleDegrees,
    required this.distanceInches,
  });

  final VsdxHatchStyle style;
  final int angleDegrees;
  final double distanceInches;
}

/// Return libvisio's hatch style, angle and spacing for a classic Visio fill.
/// `null` means the pattern is not one of the built-in hatch ids 2–24.
VsdxHatchSpec? libvisioHatchSpec(int pattern) {
  const sparse = 0.1;
  const dense = 0.05;
  return switch (pattern) {
    2 => const VsdxHatchSpec(
        style: VsdxHatchStyle.single,
        angleDegrees: 45,
        distanceInches: sparse,
      ),
    3 => const VsdxHatchSpec(
        style: VsdxHatchStyle.double,
        angleDegrees: 0,
        distanceInches: sparse,
      ),
    4 => const VsdxHatchSpec(
        style: VsdxHatchStyle.double,
        angleDegrees: 45,
        distanceInches: sparse,
      ),
    5 => const VsdxHatchSpec(
        style: VsdxHatchStyle.single,
        angleDegrees: 315,
        distanceInches: sparse,
      ),
    6 => const VsdxHatchSpec(
        style: VsdxHatchStyle.single,
        angleDegrees: 0,
        distanceInches: sparse,
      ),
    7 => const VsdxHatchSpec(
        style: VsdxHatchStyle.single,
        angleDegrees: 90,
        distanceInches: sparse,
      ),
    >= 8 && <= 12 => const VsdxHatchSpec(
        style: VsdxHatchStyle.triple,
        angleDegrees: 0,
        distanceInches: dense,
      ),
    13 || 19 => const VsdxHatchSpec(
        style: VsdxHatchStyle.single,
        angleDegrees: 0,
        distanceInches: dense,
      ),
    14 || 20 => const VsdxHatchSpec(
        style: VsdxHatchStyle.single,
        angleDegrees: 90,
        distanceInches: dense,
      ),
    15 || 21 => const VsdxHatchSpec(
        style: VsdxHatchStyle.single,
        angleDegrees: 315,
        distanceInches: dense,
      ),
    16 || 22 => const VsdxHatchSpec(
        style: VsdxHatchStyle.single,
        angleDegrees: 45,
        distanceInches: dense,
      ),
    17 || 18 || 24 => const VsdxHatchSpec(
        style: VsdxHatchStyle.triple,
        angleDegrees: 0,
        distanceInches: dense,
      ),
    23 => const VsdxHatchSpec(
        style: VsdxHatchStyle.double,
        angleDegrees: 0,
        distanceInches: dense,
      ),
    _ => null,
  };
}

/// Convert classic Visio gradient `FillPattern` ids 25–40 to gradient stops.
/// This is shared by VSD and VSDX parsing so legacy fills render identically.
VsdxFill withLibvisioClassicGradient(VsdxFill fill) {
  final pattern = fill.pattern;
  if (pattern < 25 || pattern > 40 || fill.hasGradient) return fill;

  VsdxGradientStop stop(
    double position, {
    required bool foreground,
  }) =>
      VsdxGradientStop(
        position: position,
        color: foreground ? fill.foreground : fill.background,
        themeColorIndex: foreground
            ? fill.themeForegroundIndex
            : fill.themeBackgroundIndex,
        transparency: (foreground
                ? fill.foregroundTransparency
                : fill.backgroundTransparency)
            .clamp(0.0, 1.0),
      );

  late final VsdxGradient gradient;
  if (pattern == 26 || pattern == 29) {
    gradient = VsdxGradient(
      stops: List.unmodifiable([
        stop(0, foreground: false),
        stop(0.5, foreground: true),
        stop(1, foreground: false),
      ]),
      angleRad: pattern == 26 ? 0 : math.pi / 2,
      dir: 0,
    );
  } else if (pattern >= 25 && pattern <= 34) {
    final drawDegrees = switch (pattern) {
      25 => 270.0,
      27 => 90.0,
      28 => 180.0,
      30 => 0.0,
      31 => 225.0,
      32 => 135.0,
      33 => 315.0,
      34 => 45.0,
      _ => 0.0,
    };
    gradient = VsdxGradient(
      stops: List.unmodifiable([
        stop(0, foreground: false),
        stop(1, foreground: true),
      ]),
      angleRad: math.pi / 2 - drawDegrees * math.pi / 180,
      dir: 0,
    );
  } else {
    final dir = switch (pattern) {
      35 => 10,
      36 => 1,
      37 => 3,
      38 => 5,
      39 => 7,
      _ => 4,
    };
    gradient = VsdxGradient(
      stops: List.unmodifiable([
        stop(0, foreground: true),
        stop(1, foreground: false),
      ]),
      type: pattern == 35
          ? VsdxGradientType.rectangular
          : VsdxGradientType.radial,
      dir: dir,
    );
  }

  // Endpoint transparency now lives on each stop. Leaving FillForegndTrans
  // active would multiply it a second time in SVG/canvas rendering.
  return VsdxFill(
    foreground: fill.foreground,
    background: fill.background,
    pattern: pattern,
    themeForegroundIndex: fill.themeForegroundIndex,
    themeBackgroundIndex: fill.themeBackgroundIndex,
    gradient: gradient,
  );
}

/// Classic `FillPattern` 25–40 that libvisio's VSDX parser will paint as an
/// ODF gradient. `null` when [gradient] cannot be approximated that way.
///
/// LibreOffice reaches Visio only through `VisioDocument::parse`. The VSDX
/// token map has no `FillGradient` / `FillGradientEnabled`, so a modern
/// two-stop fill with `FillPattern=1` becomes a solid. Writing the nearest
/// classic id keeps Draw filling the shape while Visio still honours the
/// `FillGradient` section when `FillGradientEnabled=1`.
int? libvisioClassicPatternFor(VsdxGradient gradient) {
  switch (gradient.type) {
    case VsdxGradientType.rectangular:
      return 35;
    case VsdxGradientType.radial:
    case VsdxGradientType.path:
      return switch (gradient.dir) {
        1 => 36,
        3 => 37,
        5 => 38,
        7 => 39,
        _ => 40,
      };
    case VsdxGradientType.linear:
      break;
  }
  if (gradient.stops.length >= 3) {
    final degrees = _normDegrees(gradient.angleRad * 180 / math.pi);
    return _degreeDelta(degrees, 0) <= _degreeDelta(degrees, 90) ? 26 : 29;
  }
  // Inverse of `angleRad = π/2 − drawDegrees × π/180` in the 25–34 table.
  final drawDegrees = _normDegrees(90 - gradient.angleRad * 180 / math.pi);
  const table = <int, double>{
    25: 270,
    27: 90,
    28: 180,
    30: 0,
    31: 225,
    32: 135,
    33: 315,
    34: 45,
  };
  var best = 27;
  var bestDelta = 360.0;
  for (final entry in table.entries) {
    final delta = _degreeDelta(drawDegrees, entry.value);
    if (delta < bestDelta) {
      bestDelta = delta;
      best = entry.key;
    }
  }
  return best;
}

/// `FillPattern` LibreOffice's libvisio importer will actually collect.
///
/// Ids above 40 fall through `_fillAndShadowProperties` to a solid
/// *background* colour. This package paints those as solid foreground, so a
/// save snaps them to `1` (or the nearest classic gradient id when stops
/// are present).
int fillPatternForLibvisioWrite(VsdxFill fill) {
  final pattern = fill.pattern;
  if (pattern == 0) return 0;
  if (pattern >= 2 && pattern <= 40) return pattern;
  if (fill.hasGradient) {
    return libvisioClassicPatternFor(fill.gradient!) ?? 1;
  }
  return 1;
}

double _normDegrees(double degrees) {
  final wrapped = degrees % 360;
  return wrapped < 0 ? wrapped + 360 : wrapped;
}

double _degreeDelta(double a, double b) {
  var delta = (_normDegrees(a) - _normDegrees(b)).abs();
  if (delta > 180) delta = 360 - delta;
  return delta;
}

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

  /// `0` = no fill. `1` = solid. `2–24` = libvisio hatch (canvas + SVG).
  /// Classic gradient ids 25–40 retain their value and also populate
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

  /// Gradient the renderer should paint: an explicit `FillGradient` section,
  /// or the libvisio mapping of classic `FillPattern` 25–40. Factory shapes
  /// can carry pattern 40 without a stop section; parse-time conversion
  /// would otherwise be the only path that filled them.
  VsdxGradient? get paintGradient {
    if (hasGradient) return gradient;
    if (pattern < 25 || pattern > 40) return null;
    return withLibvisioClassicGradient(this).gradient;
  }

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
        // Clearing a gradient must not leave classic ids 25–40 behind: a save
        // that used them as a libvisio FillGradient fallback would otherwise
        // rematerialise the wash on the next parse.
        pattern: gradient == null
            ? (pattern >= 25 && pattern <= 40 ? 1 : pattern)
            : (pattern == 0 ? 1 : pattern),
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
