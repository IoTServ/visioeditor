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

  /// Visio `THEMEVAL("…")` colour-name argument for [slot], or `null` when
  /// the slot should use bare `THEMEVAL()` + `QuickStyle*Color`.
  ///
  /// Used when FillForegnd and FillBkgnd need different theme slots — they
  /// share one `QuickStyleFillColor` cell, so the background cell carries an
  /// explicit name (MS-Visio THEMEVAL function docs).
  static String? themeValName(int slot) => switch (slot) {
        dk1 => 'Dark',
        lt1 => 'Light',
        accent1 => 'AccentColor',
        accent2 => 'AccentColor2',
        accent3 => 'AccentColor3',
        accent4 => 'AccentColor4',
        accent5 => 'AccentColor5',
        accent6 => 'AccentColor6',
        hyperlink => 'Hyperlink',
        followedHyperlink => 'FollowedHyperlink',
        // dk2 / lt2 have no stable THEMEVAL string in classic docs; callers
        // fall back to QuickStyleFillColor when only one theme fill is set.
        _ => null,
      };

  /// Inverse of [themeValName] (case-insensitive). Also accepts Visio's
  /// 1-based scheme integers (`1`=Dark … `8`=Accent6) from THEMEVAL docs.
  static int? fromThemeValArg(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final unquoted = (s.startsWith('"') && s.endsWith('"') && s.length >= 2)
        ? s.substring(1, s.length - 1)
        : s;
    final lower = unquoted.toLowerCase();
    switch (lower) {
      case 'dark':
        return dk1;
      case 'light':
        return lt1;
      case 'accentcolor':
      case 'accentcolor1':
        return accent1;
      case 'accentcolor2':
        return accent2;
      case 'accentcolor3':
        return accent3;
      case 'accentcolor4':
        return accent4;
      case 'accentcolor5':
        return accent5;
      case 'accentcolor6':
        return accent6;
      case 'hyperlink':
        return hyperlink;
      case 'followedhyperlink':
        return followedHyperlink;
    }
    final n = int.tryParse(unquoted);
    if (n == null) return null;
    // THEMEVAL integer args: 1=Dark, 2=Light, 3=Accent1 … 8=Accent6.
    return switch (n) {
      1 => dk1,
      2 => lt1,
      3 => accent1,
      4 => accent2,
      5 => accent3,
      6 => accent4,
      7 => accent5,
      8 => accent6,
      _ => null,
    };
  }
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

  /// Named built-in palettes (draw.io-style theme gallery). Documents without
  /// a theme part start empty; the editor can install one of these so
  /// theme-slot fills / lines / text resolve to real colours.
  static const List<({String name, VsdxTheme theme})> builtins = <({
    String name,
    VsdxTheme theme,
  })>[
    (name: 'Office', theme: office),
    (name: 'Blue', theme: blue),
    (name: 'Green', theme: green),
    (name: 'Orange', theme: orange),
    (name: 'Monochrome', theme: monochrome),
  ];

  /// Default Office-like palette (Visio / PowerPoint accent defaults).
  static const VsdxTheme office = VsdxTheme(colors: <int, VsdxColor>{
    ThemeSlot.dk1: VsdxColor(0xFF000000),
    ThemeSlot.lt1: VsdxColor(0xFFFFFFFF),
    ThemeSlot.dk2: VsdxColor(0xFF44546A),
    ThemeSlot.lt2: VsdxColor(0xFFE7E6E6),
    ThemeSlot.accent1: VsdxColor(0xFF4472C4),
    ThemeSlot.accent2: VsdxColor(0xFFED7D31),
    ThemeSlot.accent3: VsdxColor(0xFFA5A5A5),
    ThemeSlot.accent4: VsdxColor(0xFFFFC000),
    ThemeSlot.accent5: VsdxColor(0xFF5B9BD5),
    ThemeSlot.accent6: VsdxColor(0xFF70AD47),
    ThemeSlot.hyperlink: VsdxColor(0xFF0563C1),
    ThemeSlot.followedHyperlink: VsdxColor(0xFF954F72),
  });

  static const VsdxTheme blue = VsdxTheme(colors: <int, VsdxColor>{
    ThemeSlot.dk1: VsdxColor(0xFF1B1B1B),
    ThemeSlot.lt1: VsdxColor(0xFFFFFFFF),
    ThemeSlot.dk2: VsdxColor(0xFF2F5496),
    ThemeSlot.lt2: VsdxColor(0xFFD6DCE5),
    ThemeSlot.accent1: VsdxColor(0xFF5B9BD5),
    ThemeSlot.accent2: VsdxColor(0xFF9DC3E6),
    ThemeSlot.accent3: VsdxColor(0xFF2F5496),
    ThemeSlot.accent4: VsdxColor(0xFF00B0F0),
    ThemeSlot.accent5: VsdxColor(0xFF0070C0),
    ThemeSlot.accent6: VsdxColor(0xFF002060),
    ThemeSlot.hyperlink: VsdxColor(0xFF0563C1),
    ThemeSlot.followedHyperlink: VsdxColor(0xFF954F72),
  });

  static const VsdxTheme green = VsdxTheme(colors: <int, VsdxColor>{
    ThemeSlot.dk1: VsdxColor(0xFF1B1B1B),
    ThemeSlot.lt1: VsdxColor(0xFFFFFFFF),
    ThemeSlot.dk2: VsdxColor(0xFF385723),
    ThemeSlot.lt2: VsdxColor(0xFFE2EFDA),
    ThemeSlot.accent1: VsdxColor(0xFF70AD47),
    ThemeSlot.accent2: VsdxColor(0xFFA9D08E),
    ThemeSlot.accent3: VsdxColor(0xFF548235),
    ThemeSlot.accent4: VsdxColor(0xFFC6E0B4),
    ThemeSlot.accent5: VsdxColor(0xFF375623),
    ThemeSlot.accent6: VsdxColor(0xFF92D050),
    ThemeSlot.hyperlink: VsdxColor(0xFF0563C1),
    ThemeSlot.followedHyperlink: VsdxColor(0xFF954F72),
  });

  static const VsdxTheme orange = VsdxTheme(colors: <int, VsdxColor>{
    ThemeSlot.dk1: VsdxColor(0xFF1B1B1B),
    ThemeSlot.lt1: VsdxColor(0xFFFFFFFF),
    ThemeSlot.dk2: VsdxColor(0xFF833C0C),
    ThemeSlot.lt2: VsdxColor(0xFFFCE4D6),
    ThemeSlot.accent1: VsdxColor(0xFFED7D31),
    ThemeSlot.accent2: VsdxColor(0xFFF4B183),
    ThemeSlot.accent3: VsdxColor(0xFFC65911),
    ThemeSlot.accent4: VsdxColor(0xFFFFC000),
    ThemeSlot.accent5: VsdxColor(0xFFFF6600),
    ThemeSlot.accent6: VsdxColor(0xFF833C0C),
    ThemeSlot.hyperlink: VsdxColor(0xFF0563C1),
    ThemeSlot.followedHyperlink: VsdxColor(0xFF954F72),
  });

  static const VsdxTheme monochrome = VsdxTheme(colors: <int, VsdxColor>{
    ThemeSlot.dk1: VsdxColor(0xFF000000),
    ThemeSlot.lt1: VsdxColor(0xFFFFFFFF),
    ThemeSlot.dk2: VsdxColor(0xFF595959),
    ThemeSlot.lt2: VsdxColor(0xFFF2F2F2),
    ThemeSlot.accent1: VsdxColor(0xFF404040),
    ThemeSlot.accent2: VsdxColor(0xFF7F7F7F),
    ThemeSlot.accent3: VsdxColor(0xFFA6A6A6),
    ThemeSlot.accent4: VsdxColor(0xFFD9D9D9),
    ThemeSlot.accent5: VsdxColor(0xFF262626),
    ThemeSlot.accent6: VsdxColor(0xFFBFBFBF),
    ThemeSlot.hyperlink: VsdxColor(0xFF0563C1),
    ThemeSlot.followedHyperlink: VsdxColor(0xFF954F72),
  });

  /// Accent slots shown in the Format panel theme strip (draw.io-style).
  static const List<int> accentSlots = <int>[
    ThemeSlot.accent1,
    ThemeSlot.accent2,
    ThemeSlot.accent3,
    ThemeSlot.accent4,
    ThemeSlot.accent5,
    ThemeSlot.accent6,
    ThemeSlot.dk2,
    ThemeSlot.lt2,
  ];
}
