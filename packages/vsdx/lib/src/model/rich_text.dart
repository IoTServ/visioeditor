/// Rich-text model: one [VsdxRichText] per shape.
///
/// Visio splits text style across two sibling sections in the ShapeSheet:
///
///   * `<Section N="Character">` — per-run typography (Font / Color / Size /
///     Style bitmask / Case / Position).
///   * `<Section N="Paragraph">` — per-paragraph layout (HorzAlign,
///     IndFirst, SpLine, BulletStr, …).
///
/// And the raw `<Text>` element interleaves plain-text content with
/// `<cp IX="N"/>` / `<pp IX="N"/>` / `<tp IX="N"/>` markers pointing at
/// those section rows.
///
/// We collapse the markers into a flat list of [VsdxTextRun]s; each run
/// carries its resolved [VsdxCharStyle] / [VsdxParaStyle]. The render layer
/// converts these to a Flutter `TextSpan` tree.
library;

import 'package:meta/meta.dart';

import '../utils/color.dart';

/// One `<fld IX="n">…</fld>` span inside a [VsdxTextRun]'s [text]
/// (offsets are UTF-16 code units, Visio / Dart string indexing).
@immutable
class VsdxFieldSpan {
  const VsdxFieldSpan({
    required this.start,
    required this.length,
    required this.ix,
  });

  final int start;
  final int length;
  final int ix;

  @override
  bool operator ==(Object other) =>
      other is VsdxFieldSpan &&
      other.start == start &&
      other.length == length &&
      other.ix == ix;

  @override
  int get hashCode => Object.hash(start, length, ix);
}

/// One tab stop inside a [VsdxTabSet] (libvisio `PositionN` / `AlignmentN`).
@immutable
class VsdxTabStop {
  const VsdxTabStop({
    required this.positionInches,
    this.alignment = 0,
  });

  final double positionInches;

  /// 0 = left, 1 = center, 2 = right, other = decimal (libvisio).
  final int alignment;

  @override
  bool operator ==(Object other) =>
      other is VsdxTabStop &&
      other.positionInches == positionInches &&
      other.alignment == alignment;

  @override
  int get hashCode => Object.hash(positionInches, alignment);
}

/// One `<Section N="Tabs"><Row IX="n">` — referenced by `<tp IX="n"/>`.
@immutable
class VsdxTabSet {
  const VsdxTabSet({
    required this.ix,
    this.stops = const <VsdxTabStop>[],
  });

  final int ix;
  final List<VsdxTabStop> stops;

  @override
  bool operator ==(Object other) =>
      other is VsdxTabSet && other.ix == ix && _listEq(other.stops, stops);

  @override
  int get hashCode => Object.hash(ix, Object.hashAll(stops));

  static bool _listEq(List<VsdxTabStop> a, List<VsdxTabStop> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Resolve the start of the field following a Visio tab character.
///
/// Tab-stop positions and all arguments are relative to the paragraph's text
/// band. Alignment follows libvisio's mapping: 0 left, 1 centre, 2 right and
/// every other value decimal (the `.` character). When no authored stop lies
/// ahead of [currentPosition], Visio advances to the next default stop.
double visioTabFieldStart({
  required List<VsdxTabSet> tabSets,
  required int tabSetIx,
  required double currentPosition,
  required double followingWidth,
  required double decimalPrefixWidth,
  required double defaultTabStop,
}) {
  VsdxTabSet? set;
  for (final candidate in tabSets) {
    if (candidate.ix == tabSetIx) {
      set = candidate;
      break;
    }
  }
  final stops = [...?set?.stops]
    ..sort((a, b) => a.positionInches.compareTo(b.positionInches));
  VsdxTabStop? stop;
  for (final candidate in stops) {
    if (candidate.positionInches > currentPosition + 1e-9) {
      stop = candidate;
      break;
    }
  }
  final interval = defaultTabStop > 1e-9 ? defaultTabStop : 0.5;
  final position = stop?.positionInches ??
      ((currentPosition / interval).floor() + 1) * interval;
  final adjustment = switch (stop?.alignment ?? 0) {
    1 => followingWidth / 2,
    2 => followingWidth,
    0 => 0.0,
    _ => decimalPrefixWidth,
  };
  return (position - adjustment).clamp(currentPosition, double.infinity);
}

/// One contiguous run of text with the same character + paragraph style.
@immutable
class VsdxTextRun {
  const VsdxTextRun({
    required this.text,
    this.charStyle = VsdxCharStyle.defaults,
    this.paraStyle = VsdxParaStyle.defaults,
    this.fieldSpans = const <VsdxFieldSpan>[],
    this.tabIndices = const <int>[],
  });

  final String text;
  final VsdxCharStyle charStyle;
  final VsdxParaStyle paraStyle;

  /// Field markers embedded in [text] (display cache kept inline for paint).
  final List<VsdxFieldSpan> fieldSpans;

  /// Tabs-row IX for each `\t` in [text], in appearance order (libvisio `<tp>`).
  final List<int> tabIndices;

  VsdxTextRun copyWith({
    String? text,
    VsdxCharStyle? charStyle,
    VsdxParaStyle? paraStyle,
    List<VsdxFieldSpan>? fieldSpans,
    List<int>? tabIndices,
  }) =>
      VsdxTextRun(
        text: text ?? this.text,
        charStyle: charStyle ?? this.charStyle,
        paraStyle: paraStyle ?? this.paraStyle,
        fieldSpans: fieldSpans ?? this.fieldSpans,
        tabIndices: tabIndices ?? this.tabIndices,
      );

  @override
  String toString() =>
      'VsdxTextRun(${text.length} chars, ${charStyle.fontSizeInches}in, '
      '${charStyle.style.name})';
}

/// Visio character style row (`<Section N="Character">`).
enum VsdxTextPosition { normal, superscript, subscript }

/// Visio `Char.Case` — matches libvisio `allcaps` / `initcaps`.
enum VsdxTextCase { normal, allCaps, initialCaps }

/// Whether [rune] belongs to a script for which Visio uses the Character
/// section's `ComplexScriptFont` / `ComplexScriptSize` cells.
///
/// Office classifies Hebrew, Arabic, Indic and the shaping-dependent South
/// and South-East Asian scripts as complex text. Keep this independent of a
/// rendering backend so Canvas and SVG split mixed-script runs identically.
bool isVisioComplexScriptRune(int rune) {
  return (rune >= 0x0590 && rune <= 0x08ff) || // Hebrew, Arabic, Syriac, etc.
      (rune >= 0x0900 && rune <= 0x109f) || // Indic + SE Asian scripts.
      (rune >= 0x1780 && rune <= 0x18af) || // Khmer and Mongolian.
      (rune >= 0x1c00 && rune <= 0x1cff) ||
      (rune >= 0xa800 && rune <= 0xaaff) ||
      (rune >= 0xfb1d && rune <= 0xfdff) || // Hebrew/Arabic presentation.
      (rune >= 0xfe70 && rune <= 0xfeff) ||
      (rune >= 0x11000 && rune <= 0x11fff); // Supplementary Brahmic scripts.
}

/// Whether [rune] uses Visio's Character `AsianFont` face.
///
/// Keep this separate from [isVisioComplexScriptRune]: Office stores East
/// Asian and complex-script font choices in different Character cells. A
/// fallback list is insufficient because many Unicode fonts contain both
/// Latin and CJK glyphs; in that case the explicitly authored `AsianFont`
/// must still win for Han, Kana, Hangul, Bopomofo, Yi and Tangut text.
bool isVisioAsianScriptRune(int rune) {
  return (rune >= 0x1100 && rune <= 0x11ff) || // Hangul Jamo.
      (rune >= 0x2e80 && rune <= 0x33ff) || // CJK/Kana/Bopomofo symbols.
      (rune >= 0x3400 && rune <= 0x4dbf) || // CJK Extension A.
      (rune >= 0x4e00 && rune <= 0x9fff) || // Unified ideographs.
      (rune >= 0xa000 && rune <= 0xa4cf) || // Yi.
      (rune >= 0xac00 && rune <= 0xd7ff) || // Hangul syllables/Jamo.
      (rune >= 0xf900 && rune <= 0xfaff) || // Compatibility ideographs.
      (rune >= 0xfe30 && rune <= 0xfe4f) || // CJK compatibility forms.
      (rune >= 0xff00 && rune <= 0xffef) || // Full/half-width forms.
      (rune >= 0x16fe0 && rune <= 0x16fff) || // Ideographic symbols.
      (rune >= 0x17000 && rune <= 0x18aff) || // Tangut.
      (rune >= 0x1b000 && rune <= 0x1b2ff) || // Kana supplements.
      (rune >= 0x20000 && rune <= 0x323af); // CJK extensions B through H.
}

/// Whether [rune] has a strong right-to-left Unicode direction.
bool isVisioRightToLeftRune(int rune) {
  // Arabic-Indic digits are weak/neutral even though they sit in Arabic
  // blocks. Let surrounding text or LangID choose their paragraph direction.
  if ((rune >= 0x0660 && rune <= 0x0669) ||
      (rune >= 0x06f0 && rune <= 0x06f9) ||
      _isVisioRtlNonStrongRune(rune)) {
    return false;
  }
  return rune == 0x200f || // RIGHT-TO-LEFT MARK.
      (rune >= 0x0590 && rune <= 0x08ff) ||
      (rune >= 0xfb1d && rune <= 0xfdff) ||
      (rune >= 0xfe70 && rune <= 0xfeff) ||
      (rune >= 0x10840 && rune <= 0x1085f) ||
      (rune >= 0x10900 && rune <= 0x10cff) ||
      (rune >= 0x10e60 && rune <= 0x10fff) ||
      (rune >= 0x1e800 && rune <= 0x1e95f) ||
      (rune >= 0x1ee00 && rune <= 0x1eeff);
}

bool _isVisioRtlNonStrongRune(int rune) =>
    rune == 0x060c || // Arabic comma has the neutral CS bidi class.
    (rune >= 0x0591 && rune <= 0x05bd) ||
    rune == 0x05bf ||
    (rune >= 0x05c1 && rune <= 0x05c2) ||
    (rune >= 0x05c4 && rune <= 0x05c5) ||
    rune == 0x05c7 ||
    (rune >= 0x0610 && rune <= 0x061a) ||
    (rune >= 0x064b && rune <= 0x065f) ||
    rune == 0x0670 ||
    (rune >= 0x06d6 && rune <= 0x06dc) ||
    (rune >= 0x06df && rune <= 0x06e4) ||
    (rune >= 0x06e7 && rune <= 0x06e8) ||
    (rune >= 0x06ea && rune <= 0x06ed);

/// Base direction LibreOffice's Unicode layout chooses for Visio text.
///
/// Use the first strong character, falling back to Character `LangID` for
/// digit/punctuation-only runs. This keeps Latin+Arabic mixed paragraphs LTR
/// while pure Arabic/Hebrew paragraphs shape and anchor RTL.
bool isVisioRightToLeftText(String text, {String? langId}) {
  for (final rune in text.runes) {
    if (isVisioRightToLeftRune(rune)) return true;
    if (!_isVisioNeutralBidiRune(rune)) return false;
  }
  final subtags = langId
          ?.trim()
          .replaceAll('_', '-')
          .split('-')
          .where((part) => part.isNotEmpty)
          .map((part) => part.toLowerCase())
          .toList() ??
      const <String>[];
  if (subtags.contains('arab') || subtags.contains('hebr')) return true;
  if (subtags.contains('latn') || subtags.contains('deva')) return false;
  final language = subtags.firstOrNull;
  return const <String>{
    'ar',
    'dv',
    'fa',
    'he',
    'iw',
    'ku',
    'ps',
    'sd',
    'ur',
    'yi',
  }.contains(language);
}

bool _isVisioNeutralBidiRune(int rune) {
  if (rune == 0x200e) return false; // LEFT-TO-RIGHT MARK.
  return _isVisioRtlNonStrongRune(rune) ||
      rune <= 0x40 ||
      (rune >= 0x5b && rune <= 0x60) ||
      (rune >= 0x7b && rune <= 0xbf) ||
      (rune >= 0x0300 && rune <= 0x036f) ||
      (rune >= 0x2000 && rune <= 0x2bff) ||
      (rune >= 0xfe00 && rune <= 0xfe0f) ||
      (rune >= 0x1f000 && rune <= 0x1faff) ||
      (rune >= 0xe0100 && rune <= 0xe01ef);
}

@immutable
class VsdxCharStyle {
  const VsdxCharStyle({
    this.fontFamily,
    // Visio's default character size is 12pt (matches libvisio); a shape whose
    // text carries no Size cell inherits this.
    this.fontSizeInches = 12.0 / 72.0,
    this.style = VsdxFontStyle.regular,
    this.color,
    this.themeColorIndex,
    this.underline = false,
    this.strikethrough = false,
    this.doubleUnderline = false,
    this.doubleStrikethrough = false,
    this.overline = false,
    this.highlight,
    this.transparency = 0.0,
    this.letterSpacingInches = 0.0,
    this.position = VsdxTextPosition.normal,
    this.textCase = VsdxTextCase.normal,
    this.fontScale = 1.0,
    this.asianFont,
    this.complexScriptFont,
    this.langId,
    this.complexScriptSizeInches,
  });

  /// e.g. "Calibri", "Arial". When `null` the renderer picks the platform
  /// default sans-serif.
  final String? fontFamily;

  /// Cap height in inches (Visio default is 12pt = 0.167 in).
  final double fontSizeInches;

  final VsdxFontStyle style;
  final VsdxColor? color;

  /// QuickStyle color index (used when [color] is `null` and a theme
  /// formula was detected by the parser).
  final int? themeColorIndex;

  final bool underline;
  final bool strikethrough;
  final bool doubleUnderline;
  final bool doubleStrikethrough;
  final bool overline;

  /// Character `Highlight` — a marker colour behind the glyphs (`V=0` = none).
  /// libvisio's `readCharIX` skips the cell; canvas and SVG still paint it.
  final VsdxColor? highlight;
  final double transparency;
  final double letterSpacingInches;

  /// `Char.Pos`: 0 = normal, 1 = superscript, 2 = subscript.
  final VsdxTextPosition position;

  /// `Char.Case`: 0 = normal, 1 = all caps, 2 = initial caps.
  final VsdxTextCase textCase;

  /// `Char.FontScale` — width scale (1.0 = 100%), libvisio `scaleWidth`.
  final double fontScale;

  /// FontScale LibreOffice emits as `style:text-scale` (width only).
  ///
  /// Non-positive sheet values fall back to 100%; extreme values are clamped
  /// so layout stays readable — the same range canvas and SVG already used.
  double get clampedFontScale {
    if (fontScale <= 0) return 1.0;
    return fontScale.clamp(0.1, 4.0);
  }

  /// `AsianFont` / `ComplexScriptFont` / `LangID` / `ComplexScriptSize`.
  /// Locale-specific faces and complex-script size are preserved for XML
  /// round-trip and consumed by the Canvas/SVG renderers.
  final String? asianFont;
  final String? complexScriptFont;
  final String? langId;
  final double? complexScriptSizeInches;

  /// Largest Character size that applies to the actual glyphs in [text].
  ///
  /// `ComplexScriptSize` replaces (rather than scales) `Size` for complex
  /// glyphs. Mixed runs need the larger of both sizes for line metrics, while
  /// spaces and ASCII punctuation do not turn an otherwise Arabic/Hebrew run
  /// into a mixed Latin run.
  double effectiveFontSizeInchesForText(String text) {
    final complexSize = complexScriptSizeInches;
    if (complexSize == null || text.isEmpty) return fontSizeInches;
    var hasComplex = false;
    var hasOther = false;
    for (final rune in text.runes) {
      if (isVisioComplexScriptRune(rune)) {
        hasComplex = true;
      } else if (!_isVisioNeutralTextRune(rune)) {
        hasOther = true;
      }
    }
    if (!hasComplex) return fontSizeInches;
    if (!hasOther) return complexSize;
    return complexSize > fontSizeInches ? complexSize : fontSizeInches;
  }

  static const VsdxCharStyle defaults = VsdxCharStyle();

  /// Solid text colour, clearing any theme-slot binding.
  VsdxCharStyle withSolidColor(VsdxColor color) => copyWith(
        color: color,
        clearThemeColorIndex: true,
      );

  /// Bind text colour to a document theme slot.
  VsdxCharStyle withThemeColor(int slot) => VsdxCharStyle(
        fontFamily: fontFamily,
        fontSizeInches: fontSizeInches,
        style: style,
        color: null,
        themeColorIndex: slot,
        underline: underline,
        strikethrough: strikethrough,
        doubleUnderline: doubleUnderline,
        doubleStrikethrough: doubleStrikethrough,
        overline: overline,
        highlight: highlight,
        transparency: transparency,
        letterSpacingInches: letterSpacingInches,
        position: position,
        textCase: textCase,
        fontScale: fontScale,
        asianFont: asianFont,
        complexScriptFont: complexScriptFont,
        langId: langId,
        complexScriptSizeInches: complexScriptSizeInches,
      );

  VsdxCharStyle copyWith({
    String? fontFamily,
    double? fontSizeInches,
    VsdxFontStyle? style,
    VsdxColor? color,
    bool? underline,
    bool? strikethrough,
    bool? doubleUnderline,
    bool? doubleStrikethrough,
    bool? overline,
    VsdxColor? highlight,
    bool clearHighlight = false,
    double? transparency,
    double? letterSpacingInches,
    VsdxTextPosition? position,
    VsdxTextCase? textCase,
    double? fontScale,
    int? themeColorIndex,
    bool clearThemeColorIndex = false,
    String? asianFont,
    String? complexScriptFont,
    String? langId,
    double? complexScriptSizeInches,
    bool clearFontFamily = false,
    bool clearAsianFont = false,
    bool clearComplexScriptFont = false,
    bool clearLangId = false,
    bool clearComplexScriptSize = false,
    bool clearColor = false,
  }) =>
      VsdxCharStyle(
        fontFamily: clearFontFamily ? null : (fontFamily ?? this.fontFamily),
        fontSizeInches: fontSizeInches ?? this.fontSizeInches,
        style: style ?? this.style,
        color: clearColor ? null : (color ?? this.color),
        themeColorIndex: clearThemeColorIndex
            ? null
            : (themeColorIndex ?? this.themeColorIndex),
        underline: underline ?? this.underline,
        strikethrough: strikethrough ?? this.strikethrough,
        doubleUnderline: doubleUnderline ?? this.doubleUnderline,
        doubleStrikethrough: doubleStrikethrough ?? this.doubleStrikethrough,
        overline: overline ?? this.overline,
        highlight: clearHighlight ? null : (highlight ?? this.highlight),
        transparency: transparency ?? this.transparency,
        letterSpacingInches: letterSpacingInches ?? this.letterSpacingInches,
        position: position ?? this.position,
        textCase: textCase ?? this.textCase,
        fontScale: fontScale ?? this.fontScale,
        asianFont: clearAsianFont ? null : (asianFont ?? this.asianFont),
        complexScriptFont: clearComplexScriptFont
            ? null
            : (complexScriptFont ?? this.complexScriptFont),
        langId: clearLangId ? null : (langId ?? this.langId),
        complexScriptSizeInches: clearComplexScriptSize
            ? null
            : (complexScriptSizeInches ?? this.complexScriptSizeInches),
      );
}

bool _isVisioNeutralTextRune(int rune) =>
    rune <= 0x20 ||
    (rune >= 0x21 && rune <= 0x2f) ||
    (rune >= 0x3a && rune <= 0x40) ||
    (rune >= 0x5b && rune <= 0x60) ||
    (rune >= 0x7b && rune <= 0x7e);

/// Effective character baseline used by libvisio while parsing a shape.
///
/// Keep this separate from [VsdxCharStyle.defaults] so editor-created sparse
/// rows can retain absent Font/Color cells for round-trip. When no character
/// style exists, libvisio renders 12 pt Arial in opaque black.
const VsdxCharStyle libvisioCharacterStyleDefault = VsdxCharStyle(
  fontFamily: 'Arial',
  color: VsdxColor.black,
);

/// Style bitmask (Visio `Char.Style`):
///   bit 0 = bold, bit 1 = italic, bit 2 = underline, bit 3 = small-caps.
@immutable
class VsdxFontStyle {
  const VsdxFontStyle({
    this.bold = false,
    this.italic = false,
    this.smallCaps = false,
  });
  final bool bold;
  final bool italic;
  final bool smallCaps;

  VsdxFontStyle copyWith({bool? bold, bool? italic, bool? smallCaps}) =>
      VsdxFontStyle(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        smallCaps: smallCaps ?? this.smallCaps,
      );

  static const VsdxFontStyle regular = VsdxFontStyle();
  static const VsdxFontStyle boldStyle = VsdxFontStyle(bold: true);
  static const VsdxFontStyle italicStyle = VsdxFontStyle(italic: true);
  static const VsdxFontStyle boldItalic =
      VsdxFontStyle(bold: true, italic: true);

  String get name {
    if (bold && italic) return 'BoldItalic';
    if (bold) return 'Bold';
    if (italic) return 'Italic';
    return 'Regular';
  }

  /// Decode Visio's `Style` integer into our model.
  factory VsdxFontStyle.fromBitmask(int v) => VsdxFontStyle(
        bold: (v & 0x01) != 0,
        italic: (v & 0x02) != 0,
        smallCaps: (v & 0x08) != 0,
      );
}

/// LibreOffice applies percentage line spacing to the font's typographic
/// cell rather than its nominal point size. The reference SVG for 12 pt text
/// uses a 423-unit cell and a 568-unit advance at 120%, yielding 1.12.
const double kLibreOfficeFontCellLineHeightFactor = 1.12;

/// Default `BulletStr` libvisio emits when the cell is empty.
///
/// `VSDContentCollector::_bulletFromParaFormat` maps Visio `Bullet` 1–7 onto
/// these UCS-4 code points; LibreOffice Draw paints the same list. Unknown
/// ids fall through to the disc, matching that `default` branch.
String libvisioBulletGlyph(int bullet) {
  if (bullet == 0) return '';
  return switch (bullet) {
    2 => '\u25CB', // ○ WHITE CIRCLE
    3 => '\u25A0', // ■ BLACK SQUARE
    4 => '\u25A1', // □ WHITE SQUARE
    5 => '\u2756', // ❖ BLACK DIAMOND MINUS WHITE X
    6 => '\u27A2', // ➢ THREE-D TOP-LIGHTED RIGHTWARDS ARROWHEAD
    7 => '\u2714', // ✓ HEAVY CHECK MARK
    _ => '\u2022', // • BULLET (1 and unknown)
  };
}

/// Visio paragraph style (`<Section N="Paragraph">`).
@immutable
class VsdxParaStyle {
  const VsdxParaStyle({
    this.horizontalAlign = VsdxHorzAlign.left,
    this.indentFirstInches = 0.0,
    this.indentLeftInches = 0.0,
    this.indentRightInches = 0.0,
    this.spaceBeforeInches = 0.0,
    this.spaceAfterInches = 0.0,
    this.lineSpacing = 1.0,
    this.lineSpacingAbsoluteInches = 0.0,
    this.lineSpacingSolid = false,
    this.bullet = 0,
    this.bulletStr,
    this.bulletFont,
    this.bulletFontSizeInches,
    this.textPosAfterBulletInches = 0.0,
    this.flags = 0,
  });

  final VsdxHorzAlign horizontalAlign;
  final double indentFirstInches;
  final double indentLeftInches;
  final double indentRightInches;
  final double spaceBeforeInches;
  final double spaceAfterInches;

  /// Line height as a multiple of the font size (Visio `SpLine` < 0, e.g.
  /// `-1.2` → `1.2`). `1.0` = single, `1.5` = 1.5×, `2.0` = double. Maps
  /// through [kLibreOfficeFontCellLineHeightFactor] before mapping onto
  /// Flutter's `TextStyle.height`, so it must stay positive.
  final double lineSpacing;

  /// Absolute line height in inches (Visio `SpLine` > 0 — spacing that is
  /// independent of type size). `0.0` when unused; when > 0 it takes
  /// precedence over [lineSpacing] and the renderer converts it into a height
  /// multiple using the run's font size.
  final double lineSpacingAbsoluteInches;

  /// `true` when Visio stored `SpLine=0` ("set solid") — distinct from an
  /// omitted cell (default single spacing via negative `-1`).
  final bool lineSpacingSolid;

  /// Visio `Bullet` (0 = none).
  final int bullet;

  /// `BulletStr` / `BulletFont` / `BulletFontSize` / `TextPosAfterBullet`.
  final String? bulletStr;
  final String? bulletFont;
  final double? bulletFontSizeInches;
  final double textPosAfterBulletInches;

  /// Resolve Visio's overloaded `BulletFontSize` value against body text.
  ///
  /// libvisio emits positive values as absolute point sizes, negative values
  /// as percentages of the paragraph font size, and zero/absent as 100%.
  /// Values are stored in Visio internal units, so an absolute result remains
  /// in inches while `-0.5` resolves to half of [bodyFontSizeInches].
  double effectiveBulletFontSizeInches(double bodyFontSizeInches) {
    final value = bulletFontSizeInches;
    if (value == null || value == 0 || !value.isFinite) {
      return bodyFontSizeInches;
    }
    return value > 0 ? value : -value * bodyFontSizeInches;
  }

  /// Visio `Flags` bitmask.
  final int flags;

  /// Alignment after applying libvisio's Paragraph `Flags` semantics.
  ///
  /// A non-zero flag swaps explicit left/right alignment while leaving center
  /// and justify unchanged. [horizontalAlign] remains the raw ShapeSheet value
  /// so it can still be edited and written back losslessly.
  VsdxHorzAlign get effectiveHorizontalAlign {
    if (flags == 0) return horizontalAlign;
    return switch (horizontalAlign) {
      VsdxHorzAlign.left => VsdxHorzAlign.right,
      VsdxHorzAlign.right => VsdxHorzAlign.left,
      _ => horizontalAlign,
    };
  }

  /// Glyph canvas / SVG / Draw paint when [bullet] is non-zero.
  ///
  /// A non-empty [bulletStr] wins. Otherwise this is
  /// [libvisioBulletGlyph] so empty `BulletStr` cells match LibreOffice.
  String get resolvedBulletGlyph {
    final custom = bulletStr;
    if (custom != null && custom.isNotEmpty) return custom;
    return libvisioBulletGlyph(bullet);
  }

  static const VsdxParaStyle defaults = VsdxParaStyle();

  VsdxParaStyle copyWith({
    VsdxHorzAlign? horizontalAlign,
    double? indentFirstInches,
    double? indentLeftInches,
    double? indentRightInches,
    double? spaceBeforeInches,
    double? spaceAfterInches,
    double? lineSpacing,
    double? lineSpacingAbsoluteInches,
    bool? lineSpacingSolid,
    int? bullet,
    String? bulletStr,
    String? bulletFont,
    double? bulletFontSizeInches,
    double? textPosAfterBulletInches,
    int? flags,
    bool clearBulletStr = false,
    bool clearBulletFont = false,
    bool clearBulletFontSize = false,
  }) =>
      VsdxParaStyle(
        horizontalAlign: horizontalAlign ?? this.horizontalAlign,
        indentFirstInches: indentFirstInches ?? this.indentFirstInches,
        indentLeftInches: indentLeftInches ?? this.indentLeftInches,
        indentRightInches: indentRightInches ?? this.indentRightInches,
        spaceBeforeInches: spaceBeforeInches ?? this.spaceBeforeInches,
        spaceAfterInches: spaceAfterInches ?? this.spaceAfterInches,
        lineSpacing: lineSpacing ?? this.lineSpacing,
        lineSpacingAbsoluteInches:
            lineSpacingAbsoluteInches ?? this.lineSpacingAbsoluteInches,
        lineSpacingSolid: lineSpacingSolid ?? this.lineSpacingSolid,
        bullet: bullet ?? this.bullet,
        bulletStr: clearBulletStr ? null : (bulletStr ?? this.bulletStr),
        bulletFont: clearBulletFont ? null : (bulletFont ?? this.bulletFont),
        bulletFontSizeInches: clearBulletFontSize
            ? null
            : (bulletFontSizeInches ?? this.bulletFontSizeInches),
        textPosAfterBulletInches:
            textPosAfterBulletInches ?? this.textPosAfterBulletInches,
        flags: flags ?? this.flags,
      );
}

/// Visio Paragraph `HorzAlign` values.
///
/// [justify] (`3`) leaves the final line ragged; [full] (`4`) distributes the
/// final line as well. Keep them distinct so VSD/VSDX round-trips do not
/// collapse libvisio's `fo:text-align="full"` into left alignment.
enum VsdxHorzAlign { left, center, right, justify, full }

/// Baseline paragraph style used by libvisio while parsing a shape.
///
/// Keep this separate from [VsdxParaStyle.defaults], which is the editor's
/// creation default. libvisio starts an unstyled shape at centered, 120%
/// line spacing (`VSDParaStyle::spLine = -1.2`).
const VsdxParaStyle libvisioParagraphStyleDefault = VsdxParaStyle(
  horizontalAlign: VsdxHorzAlign.center,
  lineSpacing: 1.2,
);

/// Full rich-text body of a shape.
@immutable
class VsdxRichText {
  const VsdxRichText({
    required this.runs,
    this.textBlock = VsdxTextBlock.defaults,
    this.tabSets = const <VsdxTabSet>[],
  });

  /// Empty rich-text body — used by shapes without a `<Text>` element.
  static const VsdxRichText empty =
      VsdxRichText(runs: <VsdxTextRun>[], textBlock: VsdxTextBlock.defaults);

  final List<VsdxTextRun> runs;
  final VsdxTextBlock textBlock;

  /// `<Section N="Tabs">` rows (libvisio tab sets).
  final List<VsdxTabSet> tabSets;

  VsdxRichText copyWith({
    List<VsdxTextRun>? runs,
    VsdxTextBlock? textBlock,
    List<VsdxTabSet>? tabSets,
  }) =>
      VsdxRichText(
        runs: runs ?? this.runs,
        textBlock: textBlock ?? this.textBlock,
        tabSets: tabSets ?? this.tabSets,
      );

  /// Whole-string view — useful for fallback rendering and search.
  String get plainText {
    if (runs.isEmpty) return '';
    if (runs.length == 1) return runs.first.text;
    final buf = StringBuffer();
    for (final r in runs) {
      buf.write(r.text);
    }
    return buf.toString();
  }

  bool get isEmpty => runs.isEmpty || plainText.isEmpty;
}

/// Text block geometry — placement of the text inside the shape.
@immutable
class VsdxTextBlock {
  const VsdxTextBlock({
    this.pinXInches,
    this.pinYInches,
    this.locPinXInches,
    this.locPinYInches,
    this.widthInches,
    this.heightInches,
    this.angleRad = 0,
    this.verticalAlign = VsdxVertAlign.middle,
    this.marginLeftInches = 0.04,
    this.marginRightInches = 0.04,
    this.marginTopInches = 0.04,
    this.marginBottomInches = 0.04,
    this.hideText = false,
    this.backgroundColor,
    this.backgroundTransparency = 0.0,
    this.textDirection = 0,
    this.defaultTabStopInches = 0.5,
  });

  /// `TxtPinX` / `TxtPinY` — where the text block's local pin sits in
  /// shape-local coords. `null` ⇒ centred on the shape.
  final double? pinXInches;
  final double? pinYInches;

  /// `TxtLocPinX` / `TxtLocPinY` — the pin's position *within* the text block,
  /// measured from the block's lower-left corner. Together with the pin and
  /// size this fixes the block's rectangle (Visio, like libvisio, places the
  /// block so its local pin lands on the [pinXInches]/[pinYInches] point). When
  /// `null` the block is assumed pinned by its centre (`TxtWidth/2`,
  /// `TxtHeight/2`).
  final double? locPinXInches;
  final double? locPinYInches;

  /// `TxtWidth` / `TxtHeight`. `null` ⇒ inherit shape width/height.
  final double? widthInches;
  final double? heightInches;

  /// `TxtAngle` — radians, CCW per Visio.
  final double angleRad;

  final VsdxVertAlign verticalAlign;

  final double marginLeftInches;
  final double marginRightInches;
  final double marginTopInches;
  final double marginBottomInches;

  /// `HideText` — when true, Visio / libvisio suppress drawing the label
  /// (text remains in the model for round-trip).
  final bool hideText;

  /// `TextBkgnd` solid fill behind the text block. `null` ⇒ transparent
  /// (Visio palette indices 0 / 255, or a missing cell).
  final VsdxColor? backgroundColor;

  /// `TextBkgndTrans` — 0 = opaque, 1 = invisible (multiplied with the
  /// colour's own ARGB alpha, same as Fill*/Line*Trans).
  final double backgroundTransparency;

  /// `TextDirection` — 0 = horizontal LTR (libvisio default), 1 = vertical.
  final int textDirection;

  /// `DefaultTabStop` — tab stop distance in inches (libvisio
  /// `style:tab-stop-distance`).
  final double defaultTabStopInches;

  static const VsdxTextBlock defaults = VsdxTextBlock();

  /// Drop [backgroundColor] (transparent TextBkgnd). Prefer this over
  /// [copyWith] with `backgroundColor: null`, which cannot clear the field.
  VsdxTextBlock withoutBackgroundColor() =>
      copyWith(clearBackgroundColor: true);

  VsdxTextBlock copyWith({
    double? pinXInches,
    double? pinYInches,
    double? locPinXInches,
    double? locPinYInches,
    double? widthInches,
    double? heightInches,
    double? angleRad,
    VsdxVertAlign? verticalAlign,
    double? marginLeftInches,
    double? marginRightInches,
    double? marginTopInches,
    double? marginBottomInches,
    bool? hideText,
    VsdxColor? backgroundColor,
    bool clearBackgroundColor = false,
    double? backgroundTransparency,
    int? textDirection,
    double? defaultTabStopInches,
  }) =>
      VsdxTextBlock(
        pinXInches: pinXInches ?? this.pinXInches,
        pinYInches: pinYInches ?? this.pinYInches,
        locPinXInches: locPinXInches ?? this.locPinXInches,
        locPinYInches: locPinYInches ?? this.locPinYInches,
        widthInches: widthInches ?? this.widthInches,
        heightInches: heightInches ?? this.heightInches,
        angleRad: angleRad ?? this.angleRad,
        verticalAlign: verticalAlign ?? this.verticalAlign,
        marginLeftInches: marginLeftInches ?? this.marginLeftInches,
        marginRightInches: marginRightInches ?? this.marginRightInches,
        marginTopInches: marginTopInches ?? this.marginTopInches,
        marginBottomInches: marginBottomInches ?? this.marginBottomInches,
        hideText: hideText ?? this.hideText,
        backgroundColor: clearBackgroundColor
            ? null
            : (backgroundColor ?? this.backgroundColor),
        backgroundTransparency:
            backgroundTransparency ?? this.backgroundTransparency,
        textDirection: textDirection ?? this.textDirection,
        defaultTabStopInches: defaultTabStopInches ?? this.defaultTabStopInches,
      );
}

/// Baseline text-block style used by libvisio while parsing a shape.
///
/// Visio documents normally override these through a text stylesheet, but a
/// sparse VSD/VSDX shape begins with zero padding in libvisio. The editor's
/// creation default intentionally keeps its friendlier 0.04-inch padding.
const VsdxTextBlock libvisioTextBlockStyleDefault = VsdxTextBlock(
  marginLeftInches: 0,
  marginRightInches: 0,
  marginTopInches: 0,
  marginBottomInches: 0,
);

enum VsdxVertAlign { top, middle, bottom }
