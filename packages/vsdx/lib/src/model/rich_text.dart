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

/// One contiguous run of text with the same character + paragraph style.
@immutable
class VsdxTextRun {
  const VsdxTextRun({
    required this.text,
    this.charStyle = VsdxCharStyle.defaults,
    this.paraStyle = VsdxParaStyle.defaults,
  });

  final String text;
  final VsdxCharStyle charStyle;
  final VsdxParaStyle paraStyle;

  VsdxTextRun copyWith({
    String? text,
    VsdxCharStyle? charStyle,
    VsdxParaStyle? paraStyle,
  }) =>
      VsdxTextRun(
        text: text ?? this.text,
        charStyle: charStyle ?? this.charStyle,
        paraStyle: paraStyle ?? this.paraStyle,
      );

  @override
  String toString() =>
      'VsdxTextRun(${text.length} chars, ${charStyle.fontSizeInches}in, '
      '${charStyle.style.name})';
}

/// Visio character style row (`<Section N="Character">`).
enum VsdxTextPosition { normal, superscript, subscript }

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
    this.transparency = 0.0,
    this.letterSpacingInches = 0.0,
    this.position = VsdxTextPosition.normal,
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
  final double transparency;
  final double letterSpacingInches;

  /// `Char.Position`: 0 = normal, 1 = superscript, 2 = subscript.
  final VsdxTextPosition position;

  static const VsdxCharStyle defaults = VsdxCharStyle();

  VsdxCharStyle copyWith({
    String? fontFamily,
    double? fontSizeInches,
    VsdxFontStyle? style,
    VsdxColor? color,
    bool? underline,
    bool? strikethrough,
  }) =>
      VsdxCharStyle(
        fontFamily: fontFamily ?? this.fontFamily,
        fontSizeInches: fontSizeInches ?? this.fontSizeInches,
        style: style ?? this.style,
        color: color ?? this.color,
        themeColorIndex: themeColorIndex,
        underline: underline ?? this.underline,
        strikethrough: strikethrough ?? this.strikethrough,
        transparency: transparency,
        letterSpacingInches: letterSpacingInches,
        position: position,
      );
}

/// Style bitmask (Visio `Char.Style`):
///   bit 0 = bold, bit 1 = italic, bit 2 = underline, bit 4 = small-caps.
/// We expose the common ones as an enum-set.
@immutable
class VsdxFontStyle {
  const VsdxFontStyle({
    this.bold = false,
    this.italic = false,
  });
  final bool bold;
  final bool italic;

  VsdxFontStyle copyWith({bool? bold, bool? italic}) =>
      VsdxFontStyle(bold: bold ?? this.bold, italic: italic ?? this.italic);

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
  factory VsdxFontStyle.fromBitmask(int v) =>
      VsdxFontStyle(bold: (v & 0x01) != 0, italic: (v & 0x02) != 0);
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
  });

  final VsdxHorzAlign horizontalAlign;
  final double indentFirstInches;
  final double indentLeftInches;
  final double indentRightInches;
  final double spaceBeforeInches;
  final double spaceAfterInches;

  /// `1.0` = single, `1.5` = 1.5×, `2.0` = double.
  final double lineSpacing;

  static const VsdxParaStyle defaults = VsdxParaStyle();

  VsdxParaStyle copyWith({VsdxHorzAlign? horizontalAlign}) => VsdxParaStyle(
        horizontalAlign: horizontalAlign ?? this.horizontalAlign,
        indentFirstInches: indentFirstInches,
        indentLeftInches: indentLeftInches,
        indentRightInches: indentRightInches,
        spaceBeforeInches: spaceBeforeInches,
        spaceAfterInches: spaceAfterInches,
        lineSpacing: lineSpacing,
      );
}

enum VsdxHorzAlign { left, center, right, justify }

/// Full rich-text body of a shape.
@immutable
class VsdxRichText {
  const VsdxRichText({
    required this.runs,
    this.textBlock = VsdxTextBlock.defaults,
  });

  /// Empty rich-text body — used by shapes without a `<Text>` element.
  static const VsdxRichText empty =
      VsdxRichText(runs: <VsdxTextRun>[], textBlock: VsdxTextBlock.defaults);

  final List<VsdxTextRun> runs;
  final VsdxTextBlock textBlock;

  VsdxRichText copyWith({List<VsdxTextRun>? runs, VsdxTextBlock? textBlock}) =>
      VsdxRichText(
        runs: runs ?? this.runs,
        textBlock: textBlock ?? this.textBlock,
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

  static const VsdxTextBlock defaults = VsdxTextBlock();

  VsdxTextBlock copyWith({VsdxVertAlign? verticalAlign}) => VsdxTextBlock(
        pinXInches: pinXInches,
        pinYInches: pinYInches,
        locPinXInches: locPinXInches,
        locPinYInches: locPinYInches,
        widthInches: widthInches,
        heightInches: heightInches,
        angleRad: angleRad,
        verticalAlign: verticalAlign ?? this.verticalAlign,
        marginLeftInches: marginLeftInches,
        marginRightInches: marginRightInches,
        marginTopInches: marginTopInches,
        marginBottomInches: marginBottomInches,
      );
}

enum VsdxVertAlign { top, middle, bottom }
