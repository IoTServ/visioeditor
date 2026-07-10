/// Resolved Visio theme colour palette.
///
/// The Visio theme part (`visio/theme/theme1.xml`) is DrawingML-compatible:
/// it stores a 12-slot colour scheme (`<a:clrScheme>`). Shapes reference
/// these slots indirectly through `THEMEVAL()` / `THEMEGUARD()` formulas in
/// `FillForegnd` / `LineColor` / `Char.Color`, paired with a numeric index
/// such as `QuickStyleFillColor`.
///
/// To keep the parser tier free of any UI dependency, [VsdxTheme] holds a
/// pure `Map<int, VsdxColor>`. The renderer (`lib/render/vsdx_painter.dart`)
/// reads the index recorded on each [VsdxFill] / [VsdxLine] and resolves
/// against this map at paint time.
library;

import 'package:meta/meta.dart';

import '../utils/color.dart';

/// Stable numeric ids for theme colour slots. The integer values match the
/// `QuickStyleFillColor` indices used by Visio (MS-VSDX §2.2.4.5).
abstract final class ThemeSlot {
  static const int dk1 = 0;
  static const int lt1 = 1;
  static const int dk2 = 2;
  static const int lt2 = 3;
  static const int accent1 = 4;
  static const int accent2 = 5;
  static const int accent3 = 6;
  static const int accent4 = 7;
  static const int accent5 = 8;
  static const int accent6 = 9;
  static const int hyperlink = 10;
  static const int followedHyperlink = 11;
}

@immutable
class VsdxTheme {
  const VsdxTheme({required this.colors});

  /// Slot → colour. Slot ids match [ThemeSlot]'s constants.
  final Map<int, VsdxColor> colors;

  /// Convenience: an empty theme that always returns `null`. Documents
  /// without a theme part fall back to this; renderer then uses its own
  /// neutral defaults.
  static const VsdxTheme empty = VsdxTheme(colors: <int, VsdxColor>{});

  /// Resolve a slot id to its colour, or `null` if the slot is undefined.
  VsdxColor? resolve(int slotId) => colors[slotId];

  bool get isEmpty => colors.isEmpty;
}
