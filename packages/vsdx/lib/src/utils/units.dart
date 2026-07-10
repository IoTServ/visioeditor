/// Unit conversions used throughout the parser.
///
/// The Visio ShapeSheet uses many units (IN, MM, CM, PT, …). Per
/// `docs/VSDX_FORMAT.md` §6 we normalise everything to **inches** for length
/// and **radians** for angle as soon as a [Cell] enters the model layer.
///
/// All conversions are pure functions — no allocations, no locale.
library;

import 'dart:math' as math;

/// Recognised Visio length unit tokens. The string is the canonical XML token
/// (case-insensitive in the wild).
enum VsdxLengthUnit {
  inch('IN'),
  inchFractional('IN_F'),
  millimeter('MM'),
  centimeter('CM'),
  meter('M'),
  point('PT'),
  pica('PICA'),
  foot('FT'),
  /// "Display feet-inches", e.g. `1' 6"`.
  /// The raw string is kept; numeric value is already pre-resolved in `V`.
  displayFeetInches('DT');

  const VsdxLengthUnit(this.token);
  final String token;

  static VsdxLengthUnit? tryParse(String? token) {
    if (token == null) return null;
    final t = token.toUpperCase();
    for (final u in values) {
      if (u.token == t) return u;
    }
    return null;
  }
}

/// Recognised angle unit tokens.
enum VsdxAngleUnit {
  degrees('DEG'),
  radians('RAD');

  const VsdxAngleUnit(this.token);
  final String token;

  static VsdxAngleUnit? tryParse(String? token) {
    if (token == null) return null;
    final t = token.toUpperCase();
    for (final u in values) {
      if (u.token == t) return u;
    }
    return null;
  }
}

/// Convert [value] expressed in [unit] to **inches**.
///
/// Defaults to the identity transform when [unit] is `null` (assume inch),
/// matching Visio's behaviour for cells that omit the `U=` attribute.
double toInches(double value, [VsdxLengthUnit? unit]) {
  switch (unit) {
    case null:
    case VsdxLengthUnit.inch:
    case VsdxLengthUnit.inchFractional:
    case VsdxLengthUnit.displayFeetInches:
      return value;
    case VsdxLengthUnit.millimeter:
      return value / 25.4;
    case VsdxLengthUnit.centimeter:
      return value / 2.54;
    case VsdxLengthUnit.meter:
      return value * 100.0 / 2.54;
    case VsdxLengthUnit.point:
      return value / 72.0;
    case VsdxLengthUnit.pica:
      return value / 6.0;
    case VsdxLengthUnit.foot:
      return value * 12.0;
  }
}

/// Inverse of [toInches]: express an inch [value] in [unit] for writing back
/// to a `<Cell V=..>` that carries that `U=` unit. `null` ⇒ inches (identity).
double fromInches(double value, [VsdxLengthUnit? unit]) {
  switch (unit) {
    case null:
    case VsdxLengthUnit.inch:
    case VsdxLengthUnit.inchFractional:
    case VsdxLengthUnit.displayFeetInches:
      return value;
    case VsdxLengthUnit.millimeter:
      return value * 25.4;
    case VsdxLengthUnit.centimeter:
      return value * 2.54;
    case VsdxLengthUnit.meter:
      return value * 2.54 / 100.0;
    case VsdxLengthUnit.point:
      return value * 72.0;
    case VsdxLengthUnit.pica:
      return value * 6.0;
    case VsdxLengthUnit.foot:
      return value / 12.0;
  }
}

/// Convert [value] from inches to pixels at [dpi] (default 96 — CSS reference).
double inchesToPx(double inches, {double dpi = 96.0}) => inches * dpi;

/// Convert [value] expressed in [unit] to **radians**.
double toRadians(double value, [VsdxAngleUnit? unit]) {
  switch (unit) {
    case null:
    case VsdxAngleUnit.radians:
      return value;
    case VsdxAngleUnit.degrees:
      return value * math.pi / 180.0;
  }
}

/// Inverse of [toRadians]: express a radian [value] in [unit] for writing back.
double fromRadians(double value, [VsdxAngleUnit? unit]) {
  switch (unit) {
    case null:
    case VsdxAngleUnit.radians:
      return value;
    case VsdxAngleUnit.degrees:
      return value * 180.0 / math.pi;
  }
}
