/// Map Visio's Windows-centric font names to fonts that ship on every
/// Flutter target. Without this table, a `.vsdx` authored with `Calibri`
/// would render in the platform default (often Roboto on Android, SF Pro
/// on Apple, DejaVu on Linux) — which is fine, but inconsistent and
/// impossible to test deterministically.
///
/// The mapping is intentionally conservative — we only redirect well-known
/// Microsoft fonts to a *fallback chain* (`fontFamilyFallback`) so that
/// when the original *is* installed (e.g. on Windows) it still wins, and
/// when it isn't, we end up at a similar-metric font.
library;

import 'dart:io' show Platform;

class VsdxFontFallback {
  const VsdxFontFallback({
    required this.familyMap,
    required this.platformFallbacks,
  });

  /// Visio font name → preferred normalised family (still tried first by
  /// Flutter, but with a fallback chain bolted on).
  final Map<String, String> familyMap;

  /// Platform-keyed fallback chain for any "Microsoft sans-serif"-class
  /// family. Keys are short tokens: `mac`, `linux`, `android`, `ios`,
  /// `windows`, `web`, `fuchsia` (matching `Platform` recognised values).
  final Map<String, List<String>> platformFallbacks;

  /// Default table — covers the ~20 fonts that ship with Microsoft Office
  /// or Windows itself, which is what 95 % of authored `.vsdx` files use.
  static const VsdxFontFallback defaults = VsdxFontFallback(
    familyMap: {
      // Microsoft sans-serifs
      'Calibri': 'Calibri',
      'Calibri Light': 'Calibri Light',
      'Segoe UI': 'Segoe UI',
      'Segoe UI Light': 'Segoe UI Light',
      'Segoe UI Semibold': 'Segoe UI Semibold',
      'Tahoma': 'Tahoma',
      'Verdana': 'Verdana',
      'Trebuchet MS': 'Trebuchet MS',
      'Lucida Sans Unicode': 'Lucida Sans Unicode',
      // Microsoft serifs
      'Times New Roman': 'Times New Roman',
      'Cambria': 'Cambria',
      'Georgia': 'Georgia',
      'Garamond': 'Garamond',
      // Microsoft mono
      'Consolas': 'Consolas',
      'Courier New': 'Courier New',
      'Lucida Console': 'Lucida Console',
      // Cross-platform standards
      'Arial': 'Arial',
      'Arial Black': 'Arial Black',
      'Helvetica': 'Helvetica',
      'Symbol': 'Symbol',
      // Visio-specific symbol fonts (we don't render glyphs, but keeping
      // the family name avoids forcing a wrong substitution).
      'Wingdings': 'Wingdings',
      'Wingdings 2': 'Wingdings 2',
      'Wingdings 3': 'Wingdings 3',
      'Webdings': 'Webdings',
    },
    platformFallbacks: {
      // Apple platforms ship SF Pro + a wide PostScript classics set.
      'mac': <String>[
        'SF Pro Text',
        'SF Pro',
        'Helvetica Neue',
        'Helvetica',
        'Arial',
        'Lucida Grande',
      ],
      'ios': <String>[
        'SF Pro Text',
        'SF Pro',
        'Helvetica Neue',
        'Helvetica',
        'Arial',
      ],
      // Android ships Roboto + Noto.
      'android': <String>[
        'Roboto',
        'Noto Sans',
        'Droid Sans',
        'Arial',
        'Helvetica',
      ],
      // Most Linux distros ship DejaVu + Liberation; both have decent
      // Calibri-ish metrics for sans-serif fallbacks.
      'linux': <String>[
        'Liberation Sans',
        'DejaVu Sans',
        'Noto Sans',
        'Arial',
      ],
      // On Windows the original family almost always exists, so we add
      // fonts that exist as lower-bound fallbacks.
      'windows': <String>['Segoe UI', 'Tahoma', 'Arial'],
      // Web fallback hits the OS-default sans-serif eventually.
      'web': <String>[
        'Helvetica Neue',
        'Helvetica',
        'Arial',
        'sans-serif',
      ],
      'fuchsia': <String>['Roboto', 'Noto Sans', 'Arial'],
    },
  );

  /// Resolve a Visio font name to `(family, fallback chain)`.
  ///
  /// `null` input ⇒ platform default chain (no specific family).
  /// Unknown family ⇒ pass-through with the platform fallback chain
  /// appended, so a custom font still wins where installed but degrades
  /// gracefully elsewhere.
  ResolvedFont resolve(String? rawFamily, {String? platformOverride}) {
    final platform = platformOverride ?? _currentPlatform();
    final fallbacks = platformFallbacks[platform] ?? const <String>[];
    if (rawFamily == null || rawFamily.trim().isEmpty) {
      return ResolvedFont(
        family: null,
        familyFallback: List<String>.unmodifiable(fallbacks),
      );
    }
    final family = familyMap[rawFamily] ?? rawFamily;
    // De-dupe — `family` itself shouldn't appear in the fallback chain.
    final chain = <String>[
      for (final f in fallbacks)
        if (f != family) f,
    ];
    return ResolvedFont(
      family: family,
      familyFallback: List<String>.unmodifiable(chain),
    );
  }

  static String _currentPlatform() {
    // The Web shim raises when accessing `Platform`; viewers running in
    // tests use the canonical Dart names.
    try {
      if (Platform.isMacOS) return 'mac';
      if (Platform.isIOS) return 'ios';
      if (Platform.isAndroid) return 'android';
      if (Platform.isLinux) return 'linux';
      if (Platform.isWindows) return 'windows';
      if (Platform.isFuchsia) return 'fuchsia';
    } on UnsupportedError {
      return 'web';
    }
    return 'linux';
  }
}

class ResolvedFont {
  const ResolvedFont({required this.family, required this.familyFallback});

  /// Primary family — pass to `TextStyle.fontFamily` (may be `null`).
  final String? family;

  /// Pass to `TextStyle.fontFamilyFallback`. Order is from "best" to
  /// "last-resort generic".
  final List<String> familyFallback;
}
