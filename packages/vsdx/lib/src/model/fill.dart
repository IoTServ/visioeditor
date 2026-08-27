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

/// Hairline width libvisio / canvas / SVG use for FillPattern 2–24, in inches.
const kVisioHatchHairlineInches = 0.01;

/// Sample a classic hatch at a shape-local point (Y-up inches).
///
/// Tile phase matches canvas [PatternFillBuilder] and SVG `userSpaceOnUse`
/// patterns: axis-aligned strokes sit at `distance/2` in each cell; 45° /
/// 315° strokes run through the cell corners and are half-coverage so
/// LibreOffice's anti-aliased sloped hairlines do not flicker.
({int r, int g, int b, int a}) sampleVisioHatchRgba({
  required VsdxHatchSpec spec,
  required double x,
  required double y,
  required ({int r, int g, int b, int a}) foreground,
  required ({int r, int g, int b, int a}) background,
}) {
  final period = spec.distanceInches;
  final half = kVisioHatchHairlineInches / 2;
  var horiz = false;
  var vert = false;
  var rising = false;
  var falling = false;
  switch (spec.style) {
    case VsdxHatchStyle.triple:
      horiz = true;
      vert = true;
      rising = true;
      falling = true;
    case VsdxHatchStyle.double:
      if (spec.angleDegrees == 45) {
        rising = true;
        falling = true;
      } else {
        horiz = true;
        vert = true;
      }
    case VsdxHatchStyle.single:
      switch (spec.angleDegrees) {
        case 45:
          rising = true;
        case 90:
          vert = true;
        case 315:
          falling = true;
        default:
          horiz = true;
      }
  }
  var color = background;
  if (rising && _nearDiagonalRising(x, y, period)) {
    color = _overHatch(color, foreground, 0.5);
  }
  if (falling && _nearDiagonalFalling(x, y, period)) {
    color = _overHatch(color, foreground, 0.5);
  }
  if (horiz && _nearAxisHatch(y, period, half)) {
    color = foreground;
  }
  if (vert && _nearAxisHatch(x, period, half)) {
    color = foreground;
  }
  return color;
}

bool _nearAxisHatch(double coord, double period, double halfWidth) {
  if (period <= 1e-12) return false;
  final phase = (coord % period + period) % period;
  final delta = (phase - period / 2).abs();
  return delta <= halfWidth;
}

bool _nearDiagonalRising(double x, double y, double distance) {
  final period = distance * math.sqrt2;
  // Canvas scales a 0.01" hairline through a `distance * √2` tile, so the
  // |x−y| corridor is `0.01"` either side of each corner-to-corner stroke.
  return _nearWrapped(x - y, period, kVisioHatchHairlineInches);
}

bool _nearDiagonalFalling(double x, double y, double distance) {
  final period = distance * math.sqrt2;
  return _nearWrapped(x + y, period, kVisioHatchHairlineInches);
}

bool _nearWrapped(double coord, double period, double absTolerance) {
  if (period <= 1e-12) return false;
  final phase = (coord % period + period) % period;
  return phase <= absTolerance || period - phase <= absTolerance;
}

({int r, int g, int b, int a}) _overHatch(
  ({int r, int g, int b, int a}) dst,
  ({int r, int g, int b, int a}) src,
  double srcFactor,
) {
  final sa = (src.a / 255.0) * srcFactor.clamp(0.0, 1.0);
  final da = dst.a / 255.0;
  final outA = sa + da * (1 - sa);
  if (outA <= 1e-9) return (r: 0, g: 0, b: 0, a: 0);
  int ch(int s, int d) =>
      ((s * sa + d * da * (1 - sa)) / outA).round().clamp(0, 255);
  return (
    r: ch(src.r, dst.r),
    g: ch(src.g, dst.g),
    b: ch(src.b, dst.b),
    a: (outA * 255).round().clamp(0, 255),
  );
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
        themeColorIndex:
            foreground ? fill.themeForegroundIndex : fill.themeBackgroundIndex,
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
      35 => 10, // rectangular centre
      36 => 7, // radial top-left (ODF 36 cx/cy 0)
      37 => 6, // radial top-right
      38 => 2, // radial bottom-left
      39 => 1, // radial bottom-right
      _ => 3, // 40 radial centre
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
/// `FillGradient` section when `FillGradientEnabled=1`. Three-stop
/// BG–FG–BG linears become FillPattern 26 / 29 (`draw:style=axial`).
int? _libvisioStopColorKey(VsdxGradientStop stop) {
  if (stop.transparency > 1 - 1e-9) return null;
  final color = stop.color;
  if (color != null) return color.value & 0x00FFFFFF;
  final slot = stop.themeColorIndex;
  if (slot == null) return null;
  return 0x1000000 | (slot & 0xFFFFFF);
}

List<VsdxGradientStop> _libvisioOpaqueStops(List<VsdxGradientStop> stops) =>
    <VsdxGradientStop>[
      for (final stop in stops)
        if (stop.transparency < 1 - 1e-9) stop,
    ];

/// libvisio FillPattern 26 / 29 (`draw:style=axial`): edges share a colour
/// and a different colour sits at the middle. Canvas paints that as a
/// three-stop linear (BG–FG–BG); Draw's start-color is the centre.
bool libvisioGradientIsAxialWash(VsdxGradient? gradient) {
  if (gradient == null || gradient.type != VsdxGradientType.linear) {
    return false;
  }
  final opaque = _libvisioOpaqueStops(gradient.stops);
  if (opaque.length < 3) return false;
  final edge = _libvisioStopColorKey(opaque.first);
  final last = _libvisioStopColorKey(opaque.last);
  if (edge == null || last == null || edge != last) return false;
  return opaque.any((stop) => _libvisioStopColorKey(stop) != edge);
}

VsdxGradientStop? _libvisioAxialEdgeStop(List<VsdxGradientStop> stops) {
  final opaque = _libvisioOpaqueStops(stops);
  return opaque.isEmpty ? null : opaque.first;
}

VsdxGradientStop? _libvisioAxialPeakStop(List<VsdxGradientStop> stops) {
  final opaque = _libvisioOpaqueStops(stops);
  if (opaque.length < 3) return null;
  final edge = _libvisioStopColorKey(opaque.first);
  VsdxGradientStop? best;
  var bestDelta = 1.0;
  for (final stop in opaque) {
    if (_libvisioStopColorKey(stop) == edge) continue;
    final delta = (stop.position - 0.5).abs();
    if (best == null || delta < bestDelta) {
      best = stop;
      bestDelta = delta;
    }
  }
  return best;
}

int? libvisioClassicPatternFor(VsdxGradient gradient) {
  switch (gradient.type) {
    case VsdxGradientType.rectangular:
      return 35;
    case VsdxGradientType.radial:
    case VsdxGradientType.path:
      return switch (gradient.dir) {
        7 || 12 => 36, // top-left
        6 || 11 => 37, // top-right
        2 || 9 => 38, // bottom-left
        1 || 8 => 39, // bottom-right
        _ => 40, // centre (3 / 10) and edge 4/5 (those bake)
      };
    case VsdxGradientType.linear:
      break;
  }
  if (libvisioGradientIsAxialWash(gradient)) {
    final degrees = _normDegrees(gradient.angleRad * 180 / math.pi);
    // Axial is symmetric: 180° is the same wash as 0°, 270° as 90°.
    final horiz = math.min(
      _degreeDelta(degrees, 0),
      _degreeDelta(degrees, 180),
    );
    final vert = math.min(
      _degreeDelta(degrees, 90),
      _degreeDelta(degrees, 270),
    );
    return horiz <= vert ? 26 : 29;
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

/// Whether Draw can paint [gradient]'s linear angle as FillPattern 25–34 / 26 / 29.
///
/// `_fillAndShadowProperties` only emits ODF `draw:style=axial` at
/// `draw:angle` 0 / 90 (FillPattern 29 / 26) and eight linear compass
/// points (25 / 27 / 28 / 30–34). `FillGradientAngle` is not a token, so
/// a 45° three-stop wash or a 15° two-stop ramp would otherwise snap to
/// the nearest of those ids while canvas / SVG keep the authored angle.
bool libvisioGradientAngleFitsClassic(VsdxGradient? gradient) {
  if (gradient == null || gradient.type != VsdxGradientType.linear) {
    return true;
  }
  if (gradient.stops.length < 2) return true;
  const maxDelta = 5.0;
  if (libvisioGradientIsAxialWash(gradient)) {
    final degrees = _normDegrees(gradient.angleRad * 180 / math.pi);
    final horiz = math.min(
      _degreeDelta(degrees, 0),
      _degreeDelta(degrees, 180),
    );
    final vert = math.min(
      _degreeDelta(degrees, 90),
      _degreeDelta(degrees, 270),
    );
    return math.min(horiz, vert) <= maxDelta;
  }
  final drawDegrees = _normDegrees(90 - gradient.angleRad * 180 / math.pi);
  const table = <double>[270, 90, 180, 0, 225, 135, 315, 45];
  var best = 360.0;
  for (final slot in table) {
    final delta = _degreeDelta(drawDegrees, slot);
    if (delta < best) best = delta;
  }
  return best <= maxDelta;
}

/// Whether Draw can paint [gradient]'s stop positions as FillPattern 25–40.
///
/// Classic linear 25–34 and radial / rectangular 35–40 interpolate
/// FillBkgnd→FillForegnd across the whole box. Axial 26 / 29 always
/// peaks at the centre. `FillGradient` stop `Position` is not a token, so
/// inset two-stops (0.25→0.75) or an off-centre axial peak would snap to
/// that layout while canvas / SVG keep the authored positions.
bool libvisioGradientStopsFitClassic(VsdxGradient? gradient) {
  if (gradient == null || gradient.stops.length < 2) return true;
  final opaque = _libvisioOpaqueStops(gradient.stops);
  if (opaque.length < 2) return true;
  const eps = 0.05;
  if (libvisioGradientIsAxialWash(gradient)) {
    if (opaque.first.position > eps) return false;
    if (opaque.last.position < 1 - eps) return false;
    final peak = _libvisioAxialPeakStop(gradient.stops);
    if (peak == null) return false;
    if ((peak.position - 0.5).abs() > eps) return false;
    return opaque.length <= 3;
  }
  if (opaque.first.position > eps) return false;
  if (opaque.last.position < 1 - eps) return false;
  return true;
}

/// `FillPattern` LibreOffice's libvisio importer will actually collect.
///
/// Ids above 40 fall through `_fillAndShadowProperties` to a solid
/// *background* colour. This package paints those as solid foreground, so a
/// save snaps them to `1` (or the nearest classic gradient id when stops
/// are present).
///
/// `FillPattern=0` is libvisio's shape default when the cell is omitted.
/// Visio 2013+ / Edraw still paint `FillGradientEnabled`; that wash must
/// become a classic 25–40 id or Draw stays hollow (and an unfilled
/// LineGradient ribbon would steal the body).
int fillPatternForLibvisioWrite(VsdxFill fill) {
  final pattern = fill.pattern;
  if (pattern == 0 && !fill.hasGradient) return 0;
  if (pattern >= 2 && pattern <= 40) return pattern;
  if (fill.hasGradient) {
    return libvisioClassicPatternFor(fill.gradient!) ?? 1;
  }
  return 1;
}

/// Classic `FillPattern` plus `FillForegnd` / `FillBkgnd` libvisio
/// interpolates for a modern `FillGradient` that may have omitted those
/// cells (Edraw chevrons often ship stops only).
VsdxFill fillForLibvisioWrite(VsdxFill fill) {
  final pattern = fillPatternForLibvisioWrite(fill);
  var foreground = fill.foreground;
  var background = fill.background;
  var foregroundTheme = fill.themeForegroundIndex;
  var backgroundTheme = fill.themeBackgroundIndex;
  if (fill.hasGradient) {
    final stops = fill.gradient!.stops;
    if (pattern == 26 || pattern == 29) {
      final peak = _libvisioAxialPeakStop(stops);
      final edge = _libvisioAxialEdgeStop(stops);
      if (peak != null) {
        foreground = peak.color;
        foregroundTheme = peak.themeColorIndex;
      }
      if (edge != null) {
        background = edge.color;
        backgroundTheme = edge.themeColorIndex;
      }
    } else {
      if (foreground == null && foregroundTheme == null) {
        final stop = _libvisioWriteFillStop(stops, last: false);
        foreground = stop?.color;
        foregroundTheme = stop?.themeColorIndex;
      }
      if (background == null && backgroundTheme == null) {
        final stop = _libvisioWriteFillStop(stops, last: true);
        background = stop?.color;
        backgroundTheme = stop?.themeColorIndex;
      }
    }
  }
  if (pattern == fill.pattern &&
      identical(foreground, fill.foreground) &&
      identical(background, fill.background) &&
      foregroundTheme == fill.themeForegroundIndex &&
      backgroundTheme == fill.themeBackgroundIndex) {
    return fill;
  }
  return fill.copyWith(
    pattern: pattern,
    foreground: foreground,
    background: background,
    themeForegroundIndex: foregroundTheme,
    themeBackgroundIndex: backgroundTheme,
  );
}

VsdxGradientStop? _libvisioWriteFillStop(
  List<VsdxGradientStop> stops, {
  required bool last,
}) {
  if (stops.isEmpty) return null;
  if (last) return stops.last;
  for (final stop in stops) {
    if (stop.transparency < 1 - 1e-9) return stop;
  }
  return stops.first;
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

  /// `FillPattern != 0`, or a modern `FillGradient` whose `FillPattern` cell
  /// was omitted (libvisio defaults that cell to 0).
  bool get hasFill => pattern != 0 || hasGradient;
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
