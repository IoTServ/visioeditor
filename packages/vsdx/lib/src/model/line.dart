/// Shape-level line (stroke) description.
library;

import 'package:meta/meta.dart';

import '../utils/color.dart';

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
    this.beginArrowSizeInches = 0.05,
    this.endArrowSizeInches = 0.05,
  });

  /// `null` ⇒ unresolved colour. Look up [themeColorIndex] against the
  /// document theme; if that's also `null` fall back to black.
  final VsdxColor? color;

  /// Stroke width in inches. Visio's default is ≈ 0.01 in (~0.72 pt).
  final double weightInches;

  /// `0` = no line. `1` = solid. `2..` = dashed/dotted variants — the
  /// renderer maps the integer onto a dash pattern (see
  /// `lib/render/dash_path.dart`).
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
  /// 7 named buckets (`1..7`). The parser pre-converts to a length in
  /// inches so the renderer just reads it.
  final double beginArrowSizeInches;
  final double endArrowSizeInches;

  bool get hasLine => pattern != 0;
  bool get hasBeginArrow => beginArrow != 0;
  bool get hasEndArrow => endArrow != 0;

  static const VsdxLine defaultLine = VsdxLine();

  VsdxLine copyWith({
    VsdxColor? color,
    double? weightInches,
    int? pattern,
    LineCap? cap,
    double? transparency,
    int? themeColorIndex,
    int? beginArrow,
    int? endArrow,
    double? beginArrowSizeInches,
    double? endArrowSizeInches,
  }) {
    return VsdxLine(
      color: color ?? this.color,
      weightInches: weightInches ?? this.weightInches,
      pattern: pattern ?? this.pattern,
      cap: cap ?? this.cap,
      transparency: transparency ?? this.transparency,
      themeColorIndex: themeColorIndex ?? this.themeColorIndex,
      beginArrow: beginArrow ?? this.beginArrow,
      endArrow: endArrow ?? this.endArrow,
      beginArrowSizeInches: beginArrowSizeInches ?? this.beginArrowSizeInches,
      endArrowSizeInches: endArrowSizeInches ?? this.endArrowSizeInches,
    );
  }
}

enum LineCap { round, square, extended }
