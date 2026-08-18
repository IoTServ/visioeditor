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
      // CJK — keep the Visio/Edraw name first; platform CJK fallbacks cover
      // machines without Microsoft YaHei (typical macOS / Linux).
      'Microsoft YaHei': 'Microsoft YaHei',
      '微软雅黑': 'Microsoft YaHei',
      'Microsoft YaHei UI': 'Microsoft YaHei UI',
      'SimSun': 'SimSun',
      '宋体': 'SimSun',
      'SimHei': 'SimHei',
      '黑体': 'SimHei',
      'PingFang SC': 'PingFang SC',
      'PingFang TC': 'PingFang TC',
      'Songti SC': 'Songti SC',
      'Hiragino Sans GB': 'Hiragino Sans GB',
      // Visio-specific symbol fonts (we don't render glyphs, but keeping
      // the family name avoids forcing a wrong substitution).
      'Wingdings': 'Wingdings',
      'Wingdings 2': 'Wingdings 2',
      'Wingdings 3': 'Wingdings 3',
      'Webdings': 'Webdings',
    },
    platformFallbacks: {
      // Apple: SF Pro first for Latin; CJK faces after so YaHei substitutes
      // cleanly when Office fonts aren't installed.
      'mac': <String>[
        'SF Pro Text',
        'SF Pro',
        'Helvetica Neue',
        'Helvetica',
        'Arial',
        'PingFang SC',
        'Hiragino Sans GB',
        'Heiti SC',
        'Songti SC',
        'Arial Unicode MS',
        'Lucida Grande',
      ],
      'ios': <String>[
        'SF Pro Text',
        'SF Pro',
        'Helvetica Neue',
        'PingFang SC',
        'Hiragino Sans GB',
        'Heiti SC',
        'Helvetica',
        'Arial',
      ],
      // Android ships Roboto + Noto CJK.
      'android': <String>[
        'Roboto',
        'Noto Sans CJK SC',
        'Noto Sans SC',
        'Noto Sans',
        'Droid Sans Fallback',
        'Droid Sans',
        'Arial',
        'Helvetica',
      ],
      // Most Linux distros ship DejaVu + Liberation; Noto CJK when present.
      'linux': <String>[
        'Liberation Sans',
        'DejaVu Sans',
        'Noto Sans CJK SC',
        'Noto Sans SC',
        'Noto Sans',
        'WenQuanYi Micro Hei',
        'Arial',
      ],
      // On Windows the original family almost always exists, so we add
      // fonts that exist as lower-bound fallbacks.
      'windows': <String>[
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'Segoe UI',
        'Tahoma',
        'Arial',
      ],
      // Web fallback hits the OS-default sans-serif eventually.
      'web': <String>[
        'Helvetica Neue',
        'Helvetica',
        'PingFang SC',
        'Microsoft YaHei',
        'Noto Sans SC',
        'Arial',
        'sans-serif',
      ],
      'fuchsia': <String>['Roboto', 'Noto Sans CJK SC', 'Noto Sans', 'Arial'],
    },
  );

  static const Set<String> _serifFamilies = <String>{
    'cambria',
    'garamond',
    'georgia',
    'liberation serif',
    'times new roman',
  };

  static const Set<String> _monospaceFamilies = <String>{
    'consolas',
    'courier new',
    'liberation mono',
    'lucida console',
  };

  static const Map<String, List<String>> _serifFallbacks = {
    'mac': <String>['Times', 'Georgia', 'New York', 'serif'],
    'ios': <String>['Times New Roman', 'Georgia', 'New York', 'serif'],
    'android': <String>['Noto Serif', 'Droid Serif', 'serif'],
    'linux': <String>[
      'Liberation Serif',
      'DejaVu Serif',
      'Noto Serif',
      'serif',
    ],
    'windows': <String>['Times New Roman', 'Cambria', 'Georgia', 'serif'],
    'web': <String>['Times New Roman', 'Georgia', 'serif'],
    'fuchsia': <String>['Noto Serif', 'serif'],
  };

  static const Map<String, List<String>> _monospaceFallbacks = {
    'mac': <String>['Menlo', 'Monaco', 'Courier', 'monospace'],
    'ios': <String>['Menlo', 'Courier', 'monospace'],
    'android': <String>['Roboto Mono', 'Noto Sans Mono', 'monospace'],
    'linux': <String>[
      'Liberation Mono',
      'DejaVu Sans Mono',
      'Noto Sans Mono',
      'monospace',
    ],
    'windows': <String>[
      'Consolas',
      'Courier New',
      'Lucida Console',
      'monospace',
    ],
    'web': <String>['Courier New', 'Consolas', 'monospace'],
    'fuchsia': <String>['Roboto Mono', 'Noto Sans Mono', 'monospace'],
  };

  /// Resolve a Visio font name to `(family, fallback chain)`.
  ///
  /// `null` input ⇒ platform default chain (no specific family).
  /// Unknown family ⇒ pass-through with the platform fallback chain
  /// appended, so a custom font still wins where installed but degrades
  /// gracefully elsewhere.
  ///
  /// When [asianFont] / [complexScriptFont] are set (Visio Character cells),
  /// they are tried after the Latin [rawFamily]. The painter also promotes
  /// [complexScriptFont] to the primary face for complex-script substrings.
  ResolvedFont resolve(
    String? rawFamily, {
    String? asianFont,
    String? complexScriptFont,
    String? platformOverride,
  }) {
    final platform = platformOverride ?? _currentPlatform();
    final fallbacks = platformFallbacks[platform] ?? const <String>[];
    final primary = (rawFamily == null || rawFamily.trim().isEmpty)
        ? null
        : (familyMap[rawFamily] ?? rawFamily);
    final asian = (asianFont == null || asianFont.trim().isEmpty)
        ? null
        : (familyMap[asianFont] ?? asianFont);
    final complex =
        (complexScriptFont == null || complexScriptFont.trim().isEmpty)
        ? null
        : (familyMap[complexScriptFont] ?? complexScriptFont);

    // libvisio preserves the authored FontFace family. If that exact face is
    // unavailable, retain its metric/style class: a Times/Cambria label must
    // not silently become sans-serif, and Courier/Consolas must remain
    // fixed-width. Script-specific faces still take priority for their runs.
    final familyKey = (primary ?? '').trim().toLowerCase();
    final semanticFallbacks = _serifFamilies.contains(familyKey)
        ? (_serifFallbacks[platform] ?? const <String>[])
        : _monospaceFamilies.contains(familyKey)
        ? (_monospaceFallbacks[platform] ?? const <String>[])
        : const <String>[];

    final chain = <String>[];
    void add(String? name) {
      if (name == null || name.isEmpty) return;
      if (primary != null && name == primary) return;
      if (chain.contains(name)) return;
      chain.add(name);
    }

    add(asian);
    add(complex);
    for (final f in semanticFallbacks) {
      add(f);
    }
    for (final f in fallbacks) {
      add(f);
    }
    return ResolvedFont(
      family: primary ?? asian,
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
