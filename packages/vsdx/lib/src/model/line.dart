/// Shape-level line (stroke) description.
library;

import 'package:meta/meta.dart';

import '../utils/color.dart';
import 'effects.dart';

@immutable
class VsdxLine {
  const VsdxLine({
    this.color,
    this.weightInches = 0.01,
    this.pattern = 1,
    this.cap = LineCap.round,
    this.transparency = 0.0,
    this.themeColorIndex,
    this.beginArrow = 0,
    this.endArrow = 0,
    // Visio stores arrow size as one of 7 discrete buckets. Default to
    // bucket 2 (0.125") — matches Visio/万兴图示 StyleSheet defaults and keeps
    // the size stable across a save→reopen round-trip.
    this.beginArrowSizeInches = 0.125,
    this.endArrowSizeInches = 0.125,
    this.roundingInches = 0.0,
    this.customDashPattern,
    this.fixedDash = false,
    this.join,
    this.miterLimit = 4.0,
    this.softEdgesInches = 0.0,
    this.compoundType = 0,
    this.gradient,
  });

  /// `null` ⇒ unresolved colour. Look up [themeColorIndex] against the
  /// document theme; if that's also `null` fall back to black.
  final VsdxColor? color;

  /// Stroke width in inches. Visio's default is ≈ 0.01 in (~0.72 pt).
  final double weightInches;

  /// `0` = no line. `1` = solid. `2..` = dashed/dotted variants — the
  /// renderer maps the integer onto a weight-scaled dash pattern (see
  /// `dash_pattern.dart`).
  final int pattern;

  final LineCap cap;

  /// 0 = fully opaque, 1 = fully transparent.
  final double transparency;

  /// Theme slot id paired with `THEMEVAL()` colour formulas.
  final int? themeColorIndex;

  /// `BeginArrow` / `EndArrow` integer id. `0` = no arrow.
  /// IDs map to entries in `lib/render/arrow_library.dart`.
  final int beginArrow;
  final int endArrow;

  /// `BeginArrowSize` / `EndArrowSize` — Visio stores these as one of
  /// 7 named buckets (`0..6`). The parser pre-converts to a length in
  /// inches so the renderer just reads it.
  final double beginArrowSizeInches;
  final double endArrowSizeInches;

  /// `Rounding` — corner radius applied when stroking polylines (libvisio
  /// `computeRounding`). `0` ⇒ sharp corners.
  final double roundingInches;

  /// draw.io `dashPattern` values. Each positive number is a dash/gap length
  /// relative to the stroke width, unless [fixedDash] requests fixed display
  /// units. `null` keeps Visio [pattern] rendering.
  final List<double>? customDashPattern;

  /// draw.io `fixDash=1`: custom dash lengths stay constant as line weight
  /// changes instead of scaling with the stroke width.
  final bool fixedDash;

  /// draw.io/SVG stroke join override. `null` follows Visio/libvisio's
  /// LineCap-derived fallback: round caps use round joins, while square and
  /// extended caps use miter joins.
  final VsdxLineJoin? join;

  /// SVG/Canvas miter ratio. draw.io defaults to 4 and exposes values >= 1.
  final double miterLimit;

  VsdxLineJoin get effectiveJoin =>
      join ?? (cap == LineCap.round ? VsdxLineJoin.round : VsdxLineJoin.miter);

  /// `SoftEdgesSize` — soft-edge blur radius in inches (`0` ⇒ none).
  final double softEdgesInches;

  /// `CompoundType` — 0 = single, 1+ = double/thick-thin/… (MS-VSDX).
  final int compoundType;

  /// Optional line gradient (`LineGradientEnabled` + `<Section N="LineGradient">`).
  final VsdxGradient? gradient;

  bool get hasLine => pattern != 0;
  bool get hasBeginArrow => beginArrow != 0;
  bool get hasEndArrow => endArrow != 0;
  bool get hasGradient => gradient != null && gradient!.stops.isNotEmpty;

  static const VsdxLine defaultLine = VsdxLine();

  /// Solid stroke colour, clearing any theme-slot binding and any line gradient.
  VsdxLine withSolidColor(VsdxColor color) => VsdxLine(
        color: color,
        weightInches: weightInches,
        pattern: pattern == 0 ? 1 : pattern,
        cap: cap,
        transparency: transparency,
        themeColorIndex: null,
        beginArrow: beginArrow,
        endArrow: endArrow,
        beginArrowSizeInches: beginArrowSizeInches,
        endArrowSizeInches: endArrowSizeInches,
        roundingInches: roundingInches,
        customDashPattern: customDashPattern,
        fixedDash: fixedDash,
        join: join,
        miterLimit: miterLimit,
        softEdgesInches: softEdgesInches,
        compoundType: compoundType,
      );

  /// Bind stroke to a document theme slot, clearing the explicit colour and
  /// any line gradient.
  VsdxLine withThemeColor(int slot) => VsdxLine(
        color: null,
        weightInches: weightInches,
        pattern: pattern == 0 ? 1 : pattern,
        cap: cap,
        transparency: transparency,
        themeColorIndex: slot,
        beginArrow: beginArrow,
        endArrow: endArrow,
        beginArrowSizeInches: beginArrowSizeInches,
        endArrowSizeInches: endArrowSizeInches,
        roundingInches: roundingInches,
        customDashPattern: customDashPattern,
        fixedDash: fixedDash,
        join: join,
        miterLimit: miterLimit,
        softEdgesInches: softEdgesInches,
        compoundType: compoundType,
      );

  /// Install (or clear, when [gradient] is `null`) a stroke gradient.
  VsdxLine withGradient(VsdxGradient? gradient) => VsdxLine(
        color: color,
        weightInches: weightInches,
        pattern: gradient != null && pattern == 0 ? 1 : pattern,
        cap: cap,
        transparency: transparency,
        themeColorIndex: themeColorIndex,
        beginArrow: beginArrow,
        endArrow: endArrow,
        beginArrowSizeInches: beginArrowSizeInches,
        endArrowSizeInches: endArrowSizeInches,
        roundingInches: roundingInches,
        customDashPattern: customDashPattern,
        fixedDash: fixedDash,
        join: join,
        miterLimit: miterLimit,
        softEdgesInches: softEdgesInches,
        compoundType: compoundType,
        gradient: gradient,
      );

  /// Sentinel for [copyWith] so callers can clear [gradient] to `null`.
  static const Object keepGradient = Object();

  /// Sentinel for [copyWith] so callers can clear [customDashPattern].
  static const Object keepDashPattern = Object();

  VsdxLine copyWith({
    VsdxColor? color,
    double? weightInches,
    int? pattern,
    LineCap? cap,
    double? transparency,
    int? themeColorIndex,
    bool clearThemeColorIndex = false,
    int? beginArrow,
    int? endArrow,
    double? beginArrowSizeInches,
    double? endArrowSizeInches,
    double? roundingInches,
    Object? customDashPattern = keepDashPattern,
    bool? fixedDash,
    VsdxLineJoin? join,
    double? miterLimit,
    double? softEdgesInches,
    int? compoundType,
    Object? gradient = keepGradient,
  }) {
    return VsdxLine(
      color: color ?? this.color,
      weightInches: weightInches ?? this.weightInches,
      pattern: pattern ?? this.pattern,
      cap: cap ?? this.cap,
      transparency: transparency ?? this.transparency,
      themeColorIndex: clearThemeColorIndex
          ? null
          : (themeColorIndex ?? this.themeColorIndex),
      beginArrow: beginArrow ?? this.beginArrow,
      endArrow: endArrow ?? this.endArrow,
      beginArrowSizeInches: beginArrowSizeInches ?? this.beginArrowSizeInches,
      endArrowSizeInches: endArrowSizeInches ?? this.endArrowSizeInches,
      roundingInches: roundingInches ?? this.roundingInches,
      customDashPattern: identical(customDashPattern, keepDashPattern)
          ? this.customDashPattern
          : customDashPattern as List<double>?,
      fixedDash: fixedDash ?? this.fixedDash,
      join: join ?? this.join,
      miterLimit: miterLimit ?? this.miterLimit,
      softEdgesInches: softEdgesInches ?? this.softEdgesInches,
      compoundType: compoundType ?? this.compoundType,
      gradient: identical(gradient, keepGradient)
          ? this.gradient
          : gradient as VsdxGradient?,
    );
  }
}

enum LineCap { round, square, extended }

/// draw.io's five SVG 2 line-join values.
enum VsdxLineJoin {
  miter,
  arcs,
  bevel,
  miterClip,
  round;

  String get svgName => switch (this) {
        VsdxLineJoin.miter => 'miter',
        VsdxLineJoin.arcs => 'arcs',
        VsdxLineJoin.bevel => 'bevel',
        VsdxLineJoin.miterClip => 'miter-clip',
        VsdxLineJoin.round => 'round',
      };

  static VsdxLineJoin? parse(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'miter' => VsdxLineJoin.miter,
        'arcs' => VsdxLineJoin.arcs,
        'bevel' => VsdxLineJoin.bevel,
        'miter-clip' || 'miterclip' => VsdxLineJoin.miterClip,
        'round' => VsdxLineJoin.round,
        _ => null,
      };
}
