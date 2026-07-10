/// Colour helpers — kept pure-Dart (no `dart:ui`) so the model and parser
/// layers stay Flutter-free.
///
/// In the model we store [VsdxColor] (32-bit ARGB packed in `int`).
/// The renderer converts it to `Color` (`ui.Color`) via `toFlutterValue()`
/// in `lib/render/color_ext.dart`.
library;

import 'package:meta/meta.dart';

/// Immutable 32-bit ARGB colour. Compatible with Flutter's `Color(value)`
/// constructor: top byte = alpha, then R, G, B.
@immutable
class VsdxColor {
  /// Raw ARGB int (0xAARRGGBB).
  const VsdxColor(this.value);

  const VsdxColor.argb(int a, int r, int g, int b)
      : assert(a >= 0 && a <= 0xFF, 'alpha must be 0..255'),
        assert(r >= 0 && r <= 0xFF, 'red must be 0..255'),
        assert(g >= 0 && g <= 0xFF, 'green must be 0..255'),
        assert(b >= 0 && b <= 0xFF, 'blue must be 0..255'),
        value = (a << 24) | (r << 16) | (g << 8) | b;

  final int value;

  int get alpha => (value >> 24) & 0xFF;
  int get red => (value >> 16) & 0xFF;
  int get green => (value >> 8) & 0xFF;
  int get blue => value & 0xFF;

  static const VsdxColor black = VsdxColor(0xFF000000);
  static const VsdxColor white = VsdxColor(0xFFFFFFFF);
  static const VsdxColor transparent = VsdxColor(0x00000000);

  /// Parse a colour token as it appears in Visio XML.
  ///
  /// Supports:
  ///   * `#RRGGBB` / `#RRGGBBAA`
  ///   * `RGB(r,g,b)` (0–255 each)
  ///   * `HSL(h,s,l)` (h 0–360, s/l 0–100 — Visio Office tooltip form)
  ///   * Bare integer 0–23: index into the Visio default colour palette
  ///   * `THEMEVAL(...)` / `THEMEGUARD(...)`: NOT resolved here — returns
  ///     `null`, caller (the theme resolver) must look it up against the
  ///     theme part.
  ///   * `MSO_SYSTEM_COLOR(...)`: returns `null` (delegate to OS palette).
  static VsdxColor? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final s = raw.trim();
    final upper = s.toUpperCase();

    if (s.startsWith('#')) return _fromHex(s);
    if (upper.startsWith('RGB(')) return _fromRgbFn(s);
    if (upper.startsWith('HSL(')) return _fromHslFn(s);
    if (upper.contains('THEMEVAL') || upper.contains('THEMEGUARD')) return null;
    if (upper.contains('MSO_SYSTEM_COLOR')) return null;
    if (upper.contains('USE(')) return null;

    // Bare palette index?
    final paletteIdx = int.tryParse(s);
    if (paletteIdx != null &&
        paletteIdx >= 0 &&
        paletteIdx < _defaultPalette.length) {
      return _defaultPalette[paletteIdx];
    }
    return null;
  }

  /// Compose a new colour with the same RGB but a different alpha (0..1).
  VsdxColor withOpacity(double opacity) {
    final a = (opacity.clamp(0.0, 1.0) * 0xFF).round();
    return VsdxColor((a << 24) | (value & 0x00FFFFFF));
  }

  static VsdxColor? _fromHex(String s) {
    final hex = s.substring(1);
    if (hex.length == 6) {
      final v = int.tryParse(hex, radix: 16);
      return v == null ? null : VsdxColor(0xFF000000 | v);
    }
    if (hex.length == 8) {
      final v = int.tryParse(hex, radix: 16);
      // Visio's #RRGGBBAA — re-pack to AARRGGBB.
      if (v == null) return null;
      final rgb = (v >> 8) & 0xFFFFFF;
      final a = v & 0xFF;
      return VsdxColor((a << 24) | rgb);
    }
    return null;
  }

  static VsdxColor? _fromRgbFn(String s) {
    final open = s.indexOf('(');
    final close = s.lastIndexOf(')');
    if (open < 0 || close <= open) return null;
    final parts = s.substring(open + 1, close).split(',');
    if (parts.length != 3) return null;
    final r = int.tryParse(parts[0].trim());
    final g = int.tryParse(parts[1].trim());
    final b = int.tryParse(parts[2].trim());
    if (r == null || g == null || b == null) return null;
    return VsdxColor.argb(0xFF, r & 0xFF, g & 0xFF, b & 0xFF);
  }

  /// `HSL(h, s, l)` — `h` in degrees [0..360), `s` and `l` as percentages
  /// [0..100]. Returns the equivalent ARGB colour (opaque).
  static VsdxColor? _fromHslFn(String s) {
    final open = s.indexOf('(');
    final close = s.lastIndexOf(')');
    if (open < 0 || close <= open) return null;
    final parts = s.substring(open + 1, close).split(',');
    if (parts.length != 3) return null;
    final h = double.tryParse(parts[0].trim());
    final sPct = double.tryParse(parts[1].trim());
    final lPct = double.tryParse(parts[2].trim());
    if (h == null || sPct == null || lPct == null) return null;
    final hh = ((h % 360) + 360) % 360 / 360.0;
    final sat = (sPct.clamp(0.0, 100.0)) / 100.0;
    final lig = (lPct.clamp(0.0, 100.0)) / 100.0;
    double q;
    if (sat == 0) {
      final v = (lig * 255).round();
      return VsdxColor.argb(0xFF, v, v, v);
    }
    q = lig < 0.5 ? lig * (1 + sat) : lig + sat - lig * sat;
    final p = 2 * lig - q;
    double hueToRgb(double t) {
      var tt = t;
      if (tt < 0) tt += 1;
      if (tt > 1) tt -= 1;
      if (tt < 1 / 6) return p + (q - p) * 6 * tt;
      if (tt < 1 / 2) return q;
      if (tt < 2 / 3) return p + (q - p) * (2 / 3 - tt) * 6;
      return p;
    }

    final r = (hueToRgb(hh + 1 / 3) * 255).round() & 0xFF;
    final g = (hueToRgb(hh) * 255).round() & 0xFF;
    final b = (hueToRgb(hh - 1 / 3) * 255).round() & 0xFF;
    return VsdxColor.argb(0xFF, r, g, b);
  }

  @override
  bool operator ==(Object other) => other is VsdxColor && other.value == value;
  @override
  int get hashCode => value;

  @override
  String toString() =>
      '#${value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}

// Visio's classic 24-colour palette (Colors/ColorEntry IX=0..23) — used when
// a `Cell V="3"` references the palette without `THEMEVAL`. Confirmed against
// MS-VSDX appendix A.
const List<VsdxColor> _defaultPalette = <VsdxColor>[
  VsdxColor(0xFF000000), // 0  Black
  VsdxColor(0xFFFFFFFF), // 1  White
  VsdxColor(0xFFFF0000), // 2  Red
  VsdxColor(0xFF00FF00), // 3  Green
  VsdxColor(0xFF0000FF), // 4  Blue
  VsdxColor(0xFFFFFF00), // 5  Yellow
  VsdxColor(0xFFFF00FF), // 6  Magenta
  VsdxColor(0xFF00FFFF), // 7  Cyan
  VsdxColor(0xFF800000), // 8  DarkRed
  VsdxColor(0xFF008000), // 9  DarkGreen
  VsdxColor(0xFF000080), // 10 DarkBlue
  VsdxColor(0xFF808000), // 11 DarkYellow
  VsdxColor(0xFF800080), // 12 DarkMagenta
  VsdxColor(0xFF008080), // 13 DarkCyan
  VsdxColor(0xFFC0C0C0), // 14 LightGray
  VsdxColor(0xFF808080), // 15 DarkGray
  VsdxColor(0xFFE6E6E6), // 16
  VsdxColor(0xFFCDCDCD), // 17
  VsdxColor(0xFFB3B3B3), // 18
  VsdxColor(0xFF9A9A9A), // 19
  VsdxColor(0xFF808080), // 20
  VsdxColor(0xFF666666), // 21
  VsdxColor(0xFF4D4D4D), // 22
  VsdxColor(0xFF333333), // 23
];
