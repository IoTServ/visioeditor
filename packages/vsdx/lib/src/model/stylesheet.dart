/// Visio StyleSheets from `visio/document.xml` — the inheritance source for
/// shapes that omit their own Character / Fill / Line cells (libvisio resolves
/// `TextStyle` / `LineStyle` / `FillStyle` the same way).
library;

import 'package:meta/meta.dart';

import '../utils/color.dart';
import 'effects.dart';
import 'fill.dart';
import 'line.dart';
import 'rich_text.dart';

@immutable
class VsdxStyleSheet {
  const VsdxStyleSheet({
    required this.id,
    required this.name,
    this.textStyleId,
    this.lineStyleId,
    this.fillStyleId,
    this.charStyle,
    this.charSizeInherits = false,
    this.charDefinedCells = const <String>{},
    this.paraStyle,
    this.paraDefinedCells = const <String>{},
    this.textBlock,
    this.textBlockDefinedCells = const <String>{},
    this.line,
    this.lineDefinedCells = const <String>{},
    this.fill,
    this.fillDefinedCells = const <String>{},
    this.shadow,
    this.shadowDefinedCells = const <String>{},
    this.quickStyleLineMatrix,
    this.quickStyleFillMatrix,
  });

  final int id;
  final String name;

  /// Parent stylesheet for text (`TextStyle` attribute) — walk this chain to
  /// resolve Character cells the shape itself doesn't define.
  final int? textStyleId;
  final int? lineStyleId;
  final int? fillStyleId;

  /// Character style materialised from this sheet's `<Section N="Character">`
  /// (may be partial — null fields mean "not set here").
  final VsdxCharStyle? charStyle;

  /// `true` when the Size cell carried `F="Inh"` — callers should keep walking
  /// the [textStyleId] chain rather than treating [charStyle]'s size as final.
  final bool charSizeInherits;

  /// Concrete Character cells contributed by row IX=0 on this stylesheet.
  final Set<String> charDefinedCells;

  final VsdxParaStyle? paraStyle;

  /// Concrete Paragraph cells contributed by row IX=0 on this stylesheet.
  final Set<String> paraDefinedCells;

  final VsdxTextBlock? textBlock;

  /// Concrete TextBlock cells placed directly under the stylesheet.
  final Set<String> textBlockDefinedCells;

  final VsdxLine? line;

  /// Cell names that were concrete on this sheet (not absent / not `F=Inh`).
  /// [StyleSheetRegistry.resolveLine] only takes values for these names so a
  /// parent sheet's LineWeight is not blocked by a child that only set SoftEdges.
  final Set<String> lineDefinedCells;

  final VsdxFill? fill;

  /// Same idea as [lineDefinedCells] for Fill cells.
  final Set<String> fillDefinedCells;

  final VsdxShadow? shadow;

  /// Concrete shadow cells contributed by this stylesheet. Shadow properties
  /// share the FillStyle inheritance chain in Visio/libvisio.
  final Set<String> shadowDefinedCells;

  /// Theme format-scheme selectors carried by the stylesheet. libvisio
  /// retains these alongside the optional line/fill styles and walks the same
  /// parent chains as the corresponding style properties.
  final int? quickStyleLineMatrix;
  final int? quickStyleFillMatrix;
}

/// Registry of every `<StyleSheet>` in the document, with chain resolution
/// matching Visio / libvisio (`TextStyle` → parent → … → No Style).
@immutable
class StyleSheetRegistry {
  const StyleSheetRegistry(this._byId, {this.defaultTextStyleId});

  static const StyleSheetRegistry empty =
      StyleSheetRegistry(<int, VsdxStyleSheet>{});

  final Map<int, VsdxStyleSheet> _byId;

  /// `DocumentSettings/@DefaultTextStyle` — fallback when a shape has no
  /// `TextStyle` attribute (and no master to inherit from).
  final int? defaultTextStyleId;

  bool get isEmpty => _byId.isEmpty;

  VsdxStyleSheet? operator [](int id) => _byId[id];

  /// Resolve the effective character style for a shape's `TextStyle` id
  /// (falling back to [defaultTextStyleId]). Walks the parent chain; a Size
  /// with `F="Inh"` is skipped so the parent's concrete size wins — matching
  /// how libvisio ends up at Connector=8pt / Normal→Theme→NoStyle=12pt.
  VsdxCharStyle? resolveCharStyle(int? textStyleId) {
    var id = textStyleId ?? defaultTextStyleId;
    if (id == null) return null;

    String? fontFamily;
    double? fontSizeInches;
    VsdxFontStyle? style;
    VsdxColor? color;
    int? themeColorIndex;
    bool? underline;
    bool? strikethrough;
    bool? doubleUnderline;
    bool? doubleStrikethrough;
    bool? overline;
    double? transparency;
    double? letterSpacingInches;
    VsdxTextPosition? position;
    VsdxTextCase? textCase;
    double? fontScale;
    String? asianFont;
    String? complexScriptFont;
    String? langId;
    double? complexScriptSizeInches;
    final resolved = <String>{};

    final seen = <int>{};
    while (id != null && seen.add(id)) {
      final sheet = _byId[id];
      if (sheet == null) break;
      final c = sheet.charStyle;
      if (c != null) {
        final defined = sheet.charDefinedCells.isEmpty
            ? const <String>{'Font', 'Size', 'Style', 'Color'}
            : sheet.charDefinedCells;
        if (resolved.addIfAbsent('Font', defined)) fontFamily = c.fontFamily;
        if (!sheet.charSizeInherits && resolved.addIfAbsent('Size', defined)) {
          fontSizeInches = c.fontSizeInches;
        }
        if (resolved.addIfAbsent('Style', defined)) {
          style = c.style;
          underline = c.underline;
        }
        if (resolved.addIfAbsent('Color', defined)) {
          color = c.color;
          themeColorIndex = c.themeColorIndex;
        }
        if (resolved.addIfAbsent('Strikethru', defined)) {
          strikethrough = c.strikethrough;
        }
        if (resolved.addIfAbsent('DblUnderline', defined)) {
          doubleUnderline = c.doubleUnderline;
        }
        if (resolved.addIfAbsent('DoubleStrikethrough', defined)) {
          doubleStrikethrough = c.doubleStrikethrough;
        }
        if (resolved.addIfAbsent('Overline', defined)) overline = c.overline;
        if (resolved.addIfAbsent('ColorTrans', defined)) {
          transparency = c.transparency;
        }
        if (resolved.addIfAbsent('Letterspace', defined)) {
          letterSpacingInches = c.letterSpacingInches;
        }
        if (resolved.addIfAbsent('Pos', defined)) position = c.position;
        if (resolved.addIfAbsent('Case', defined)) textCase = c.textCase;
        if (resolved.addIfAbsent('FontScale', defined)) fontScale = c.fontScale;
        if (resolved.addIfAbsent('AsianFont', defined)) asianFont = c.asianFont;
        if (resolved.addIfAbsent('ComplexScriptFont', defined)) {
          complexScriptFont = c.complexScriptFont;
        }
        if (resolved.addIfAbsent('LangID', defined)) langId = c.langId;
        if (resolved.addIfAbsent('ComplexScriptSize', defined)) {
          complexScriptSizeInches = c.complexScriptSizeInches;
        }
      }
      id = sheet.textStyleId;
    }

    if (resolved.isEmpty) return null;
    return VsdxCharStyle(
      fontFamily: fontFamily,
      fontSizeInches: fontSizeInches ?? VsdxCharStyle.defaults.fontSizeInches,
      style: style ?? VsdxFontStyle.regular,
      color: color,
      themeColorIndex: themeColorIndex,
      underline: underline ?? false,
      strikethrough: strikethrough ?? false,
      doubleUnderline: doubleUnderline ?? false,
      doubleStrikethrough: doubleStrikethrough ?? false,
      overline: overline ?? false,
      transparency: transparency ?? 0,
      letterSpacingInches: letterSpacingInches ?? 0,
      position: position ?? VsdxTextPosition.normal,
      textCase: textCase ?? VsdxTextCase.normal,
      fontScale: fontScale ?? 1,
      asianFont: asianFont,
      complexScriptFont: complexScriptFont,
      langId: langId,
      complexScriptSizeInches: complexScriptSizeInches,
    );
  }

  /// Resolve Paragraph row IX=0 through the TextStyle chain. Each cell walks
  /// independently so a child can override alignment while inheriting line
  /// spacing, indentation, and bullets from its parent (libvisio behaviour).
  VsdxParaStyle? resolveParaStyle(
    int? textStyleId, {
    VsdxParaStyle defaults = VsdxParaStyle.defaults,
  }) {
    var id = textStyleId ?? defaultTextStyleId;
    if (id == null) return null;

    VsdxHorzAlign? horizontalAlign;
    double? indentFirstInches;
    double? indentLeftInches;
    double? indentRightInches;
    double? spaceBeforeInches;
    double? spaceAfterInches;
    double? lineSpacing;
    double? lineSpacingAbsoluteInches;
    bool? lineSpacingSolid;
    int? bullet;
    String? bulletStr;
    String? bulletFont;
    double? bulletFontSizeInches;
    double? textPosAfterBulletInches;
    int? flags;
    final resolved = <String>{};

    final seen = <int>{};
    while (id != null && seen.add(id)) {
      final sheet = _byId[id];
      if (sheet == null) break;
      final para = sheet.paraStyle;
      final defined = sheet.paraDefinedCells;
      if (para != null) {
        if (resolved.addIfAbsent('HorzAlign', defined)) {
          horizontalAlign = para.horizontalAlign;
        }
        if (resolved.addIfAbsent('IndFirst', defined)) {
          indentFirstInches = para.indentFirstInches;
        }
        if (resolved.addIfAbsent('IndLeft', defined)) {
          indentLeftInches = para.indentLeftInches;
        }
        if (resolved.addIfAbsent('IndRight', defined)) {
          indentRightInches = para.indentRightInches;
        }
        if (resolved.addIfAbsent('SpBefore', defined)) {
          spaceBeforeInches = para.spaceBeforeInches;
        }
        if (resolved.addIfAbsent('SpAfter', defined)) {
          spaceAfterInches = para.spaceAfterInches;
        }
        if (resolved.addIfAbsent('SpLine', defined)) {
          lineSpacing = para.lineSpacing;
          lineSpacingAbsoluteInches = para.lineSpacingAbsoluteInches;
          lineSpacingSolid = para.lineSpacingSolid;
        }
        if (resolved.addIfAbsent('Bullet', defined)) bullet = para.bullet;
        if (resolved.addIfAbsent('BulletStr', defined)) {
          bulletStr = para.bulletStr;
        }
        if (resolved.addIfAbsent('BulletFont', defined)) {
          bulletFont = para.bulletFont;
        }
        if (resolved.addIfAbsent('BulletFontSize', defined)) {
          bulletFontSizeInches = para.bulletFontSizeInches;
        }
        if (resolved.addIfAbsent('TextPosAfterBullet', defined)) {
          textPosAfterBulletInches = para.textPosAfterBulletInches;
        }
        if (resolved.addIfAbsent('Flags', defined)) flags = para.flags;
      }
      id = sheet.textStyleId;
    }

    if (resolved.isEmpty) return null;
    return VsdxParaStyle(
      horizontalAlign: horizontalAlign ?? defaults.horizontalAlign,
      indentFirstInches: indentFirstInches ?? defaults.indentFirstInches,
      indentLeftInches: indentLeftInches ?? defaults.indentLeftInches,
      indentRightInches: indentRightInches ?? defaults.indentRightInches,
      spaceBeforeInches: spaceBeforeInches ?? defaults.spaceBeforeInches,
      spaceAfterInches: spaceAfterInches ?? defaults.spaceAfterInches,
      lineSpacing: lineSpacing ?? defaults.lineSpacing,
      lineSpacingAbsoluteInches:
          lineSpacingAbsoluteInches ?? defaults.lineSpacingAbsoluteInches,
      lineSpacingSolid: lineSpacingSolid ?? defaults.lineSpacingSolid,
      bullet: bullet ?? defaults.bullet,
      bulletStr:
          resolved.contains('BulletStr') ? bulletStr : defaults.bulletStr,
      bulletFont:
          resolved.contains('BulletFont') ? bulletFont : defaults.bulletFont,
      bulletFontSizeInches: resolved.contains('BulletFontSize')
          ? bulletFontSizeInches
          : defaults.bulletFontSizeInches,
      textPosAfterBulletInches:
          textPosAfterBulletInches ?? defaults.textPosAfterBulletInches,
      flags: flags ?? defaults.flags,
    );
  }

  /// Resolve direct TextBlock style cells through the TextStyle chain while
  /// preserving shape/master text transforms supplied in [defaults].
  VsdxTextBlock? resolveTextBlock(
    int? textStyleId, {
    VsdxTextBlock defaults = VsdxTextBlock.defaults,
  }) {
    var id = textStyleId ?? defaultTextStyleId;
    if (id == null) return null;

    double? left;
    double? right;
    double? top;
    double? bottom;
    VsdxVertAlign? verticalAlign;
    VsdxColor? backgroundColor;
    double? backgroundTransparency;
    int? textDirection;
    double? defaultTabStop;
    final resolved = <String>{};

    final seen = <int>{};
    while (id != null && seen.add(id)) {
      final sheet = _byId[id];
      if (sheet == null) break;
      final block = sheet.textBlock;
      final defined = sheet.textBlockDefinedCells;
      if (block != null) {
        if (resolved.addIfAbsent('LeftMargin', defined)) {
          left = block.marginLeftInches;
        }
        if (resolved.addIfAbsent('RightMargin', defined)) {
          right = block.marginRightInches;
        }
        if (resolved.addIfAbsent('TopMargin', defined)) {
          top = block.marginTopInches;
        }
        if (resolved.addIfAbsent('BottomMargin', defined)) {
          bottom = block.marginBottomInches;
        }
        if (resolved.addIfAbsent('VerticalAlign', defined)) {
          verticalAlign = block.verticalAlign;
        }
        if (resolved.addIfAbsent('TextBkgnd', defined)) {
          backgroundColor = block.backgroundColor;
        }
        if (resolved.addIfAbsent('TextBkgndTrans', defined)) {
          backgroundTransparency = block.backgroundTransparency;
        }
        if (resolved.addIfAbsent('TextDirection', defined)) {
          textDirection = block.textDirection;
        }
        if (resolved.addIfAbsent('DefaultTabStop', defined)) {
          defaultTabStop = block.defaultTabStopInches;
        }
      }
      id = sheet.textStyleId;
    }

    if (resolved.isEmpty) return null;
    return VsdxTextBlock(
      pinXInches: defaults.pinXInches,
      pinYInches: defaults.pinYInches,
      locPinXInches: defaults.locPinXInches,
      locPinYInches: defaults.locPinYInches,
      widthInches: defaults.widthInches,
      heightInches: defaults.heightInches,
      angleRad: defaults.angleRad,
      verticalAlign: verticalAlign ?? defaults.verticalAlign,
      marginLeftInches: left ?? defaults.marginLeftInches,
      marginRightInches: right ?? defaults.marginRightInches,
      marginTopInches: top ?? defaults.marginTopInches,
      marginBottomInches: bottom ?? defaults.marginBottomInches,
      hideText: defaults.hideText,
      backgroundColor: resolved.contains('TextBkgnd')
          ? backgroundColor
          : defaults.backgroundColor,
      backgroundTransparency:
          backgroundTransparency ?? defaults.backgroundTransparency,
      textDirection: textDirection ?? defaults.textDirection,
      defaultTabStopInches: defaultTabStop ?? defaults.defaultTabStopInches,
    );
  }

  /// Resolve effective [VsdxLine] defaults from a `LineStyle` id (weight /
  /// pattern / colour / SoftEdgesSize / Rounding), walking the parent chain.
  VsdxLine? resolveLine(int? lineStyleId) {
    var id = lineStyleId;
    if (id == null) return null;

    VsdxColor? color;
    int? themeColorIndex;
    var colorResolved = false;
    double? weightInches;
    int? pattern;
    LineCap? cap;
    double? transparency;
    int? beginArrow;
    int? endArrow;
    double? beginArrowSizeInches;
    double? endArrowSizeInches;
    double? softEdgesInches;
    double? roundingInches;
    int? compoundType;

    final seen = <int>{};
    while (id != null && seen.add(id)) {
      final sheet = _byId[id];
      if (sheet == null) break;
      final line = sheet.line;
      // Empty defined set ⇒ hand-built / legacy sheet: take every field.
      final legacy = sheet.lineDefinedCells.isEmpty;
      final defined = legacy
          ? const {
              'LineColor',
              'LineWeight',
              'LinePattern',
              'LineCap',
              'LineColorTrans',
              'BeginArrow',
              'EndArrow',
              'BeginArrowSize',
              'EndArrowSize',
              'SoftEdgesSize',
              'Rounding',
              'CompoundType',
            }
          : sheet.lineDefinedCells;
      if (line != null) {
        if (!colorResolved &&
            defined.contains('LineColor') &&
            (!legacy || line.color != null || line.themeColorIndex != null)) {
          color = line.color;
          themeColorIndex = line.themeColorIndex;
          colorResolved = true;
        }
        if (weightInches == null && defined.contains('LineWeight')) {
          weightInches = line.weightInches;
        }
        if (pattern == null && defined.contains('LinePattern')) {
          pattern = line.pattern;
        }
        if (cap == null && defined.contains('LineCap')) cap = line.cap;
        if (transparency == null && defined.contains('LineColorTrans')) {
          transparency = line.transparency;
        }
        if (beginArrow == null && defined.contains('BeginArrow')) {
          beginArrow = line.beginArrow;
        }
        if (endArrow == null && defined.contains('EndArrow')) {
          endArrow = line.endArrow;
        }
        if (beginArrowSizeInches == null &&
            defined.contains('BeginArrowSize')) {
          beginArrowSizeInches = line.beginArrowSizeInches;
        }
        if (endArrowSizeInches == null && defined.contains('EndArrowSize')) {
          endArrowSizeInches = line.endArrowSizeInches;
        }
        if (softEdgesInches == null && defined.contains('SoftEdgesSize')) {
          softEdgesInches = line.softEdgesInches;
        }
        if (roundingInches == null && defined.contains('Rounding')) {
          roundingInches = line.roundingInches;
        }
        if (compoundType == null && defined.contains('CompoundType')) {
          compoundType = line.compoundType;
        }
      }
      id = sheet.lineStyleId;
    }

    if (!colorResolved &&
        weightInches == null &&
        pattern == null &&
        cap == null &&
        transparency == null &&
        beginArrow == null &&
        endArrow == null &&
        beginArrowSizeInches == null &&
        endArrowSizeInches == null &&
        softEdgesInches == null &&
        roundingInches == null &&
        compoundType == null) {
      return null;
    }
    return VsdxLine(
      color: color,
      themeColorIndex: themeColorIndex,
      weightInches: weightInches ?? VsdxLine.defaultLine.weightInches,
      pattern: pattern ?? VsdxLine.defaultLine.pattern,
      cap: cap ?? VsdxLine.defaultLine.cap,
      transparency: transparency ?? VsdxLine.defaultLine.transparency,
      beginArrow: beginArrow ?? VsdxLine.defaultLine.beginArrow,
      endArrow: endArrow ?? VsdxLine.defaultLine.endArrow,
      beginArrowSizeInches:
          beginArrowSizeInches ?? VsdxLine.defaultLine.beginArrowSizeInches,
      endArrowSizeInches:
          endArrowSizeInches ?? VsdxLine.defaultLine.endArrowSizeInches,
      softEdgesInches: softEdgesInches ?? VsdxLine.defaultLine.softEdgesInches,
      roundingInches: roundingInches ?? VsdxLine.defaultLine.roundingInches,
      compoundType: compoundType ?? VsdxLine.defaultLine.compoundType,
    );
  }

  /// Resolve effective [VsdxFill] defaults from a `FillStyle` id, walking the
  /// parent chain like Visio / [resolveLine].
  VsdxFill? resolveFill(int? fillStyleId) {
    var id = fillStyleId;
    if (id == null) return null;

    VsdxColor? foreground;
    VsdxColor? background;
    int? pattern;
    int? themeForegroundIndex;
    int? themeBackgroundIndex;
    var foregroundResolved = false;
    var backgroundResolved = false;
    VsdxGradient? gradient;
    double? foregroundTransparency;
    double? backgroundTransparency;

    final seen = <int>{};
    while (id != null && seen.add(id)) {
      final sheet = _byId[id];
      if (sheet == null) break;
      final fill = sheet.fill;
      // Empty defined set ⇒ hand-built / legacy sheet: take every field.
      final legacy = sheet.fillDefinedCells.isEmpty;
      final defined = legacy
          ? const {
              'FillForegnd',
              'FillBkgnd',
              'FillPattern',
              'FillForegndTrans',
              'FillBkgndTrans',
            }
          : sheet.fillDefinedCells;
      if (fill != null) {
        if (!foregroundResolved &&
            defined.contains('FillForegnd') &&
            (!legacy ||
                fill.foreground != null ||
                fill.themeForegroundIndex != null)) {
          foreground = fill.foreground;
          themeForegroundIndex = fill.themeForegroundIndex;
          foregroundResolved = true;
        }
        if (!backgroundResolved &&
            defined.contains('FillBkgnd') &&
            (!legacy ||
                fill.background != null ||
                fill.themeBackgroundIndex != null)) {
          background = fill.background;
          themeBackgroundIndex = fill.themeBackgroundIndex;
          backgroundResolved = true;
        }
        if (pattern == null && defined.contains('FillPattern')) {
          pattern = fill.pattern;
        }
        gradient ??= fill.gradient;
        if (foregroundTransparency == null &&
            defined.contains('FillForegndTrans')) {
          foregroundTransparency = fill.foregroundTransparency;
        }
        if (backgroundTransparency == null &&
            defined.contains('FillBkgndTrans')) {
          backgroundTransparency = fill.backgroundTransparency;
        }
      }
      id = sheet.fillStyleId;
    }

    if (!foregroundResolved &&
        !backgroundResolved &&
        pattern == null &&
        themeForegroundIndex == null &&
        themeBackgroundIndex == null &&
        gradient == null &&
        foregroundTransparency == null &&
        backgroundTransparency == null) {
      return null;
    }
    return VsdxFill(
      foreground: foreground,
      background: background,
      pattern: pattern ?? VsdxFill.defaultFill.pattern,
      foregroundTransparency:
          foregroundTransparency ?? VsdxFill.defaultFill.foregroundTransparency,
      backgroundTransparency:
          backgroundTransparency ?? VsdxFill.defaultFill.backgroundTransparency,
      themeForegroundIndex: themeForegroundIndex,
      themeBackgroundIndex: themeBackgroundIndex,
      gradient: gradient,
    );
  }

  /// Resolve shadow cells through the FillStyle chain, matching libvisio's
  /// treatment of shadow as part of FillAndShadow.
  VsdxShadow? resolveShadow(
    int? fillStyleId, {
    double? pageOffsetXInches,
    double? pageOffsetYInches,
  }) {
    var id = fillStyleId;
    if (id == null) return null;

    VsdxColor? color;
    int? themeColorIndex;
    var colorResolved = false;
    int? pattern;
    double? offsetX;
    double? offsetY;
    double? transparency;

    final seen = <int>{};
    while (id != null && seen.add(id)) {
      final sheet = _byId[id];
      if (sheet == null) break;
      final shadow = sheet.shadow;
      final legacy = sheet.shadowDefinedCells.isEmpty;
      final defined = legacy
          ? const {
              'ShdwForegnd',
              'ShdwPattern',
              'ShapeShdwOffsetX',
              'ShapeShdwOffsetY',
              'ShdwForegndTrans',
            }
          : sheet.shadowDefinedCells;
      if (shadow != null) {
        if (!colorResolved &&
            defined.contains('ShdwForegnd') &&
            (!legacy ||
                shadow.color != null ||
                shadow.themeColorIndex != null)) {
          color = shadow.color;
          themeColorIndex = shadow.themeColorIndex;
          colorResolved = true;
        }
        if (pattern == null && defined.contains('ShdwPattern')) {
          pattern = shadow.enabled ? shadow.pattern : 0;
        }
        if (offsetX == null && defined.contains('ShapeShdwOffsetX')) {
          offsetX = shadow.offsetXInches;
        }
        if (offsetY == null && defined.contains('ShapeShdwOffsetY')) {
          offsetY = shadow.offsetYInches;
        }
        if (transparency == null && defined.contains('ShdwForegndTrans')) {
          transparency = shadow.transparency;
        }
      }
      id = sheet.fillStyleId;
    }

    if (!colorResolved &&
        pattern == null &&
        offsetX == null &&
        offsetY == null &&
        transparency == null) {
      return null;
    }
    final effectivePattern = pattern ?? 0;
    return VsdxShadow(
      enabled: effectivePattern != 0,
      pattern: effectivePattern == 0 ? 1 : effectivePattern,
      color: color,
      themeColorIndex: themeColorIndex,
      offsetXInches: offsetX ?? pageOffsetXInches ?? 0.125,
      offsetYInches: offsetY ?? pageOffsetYInches ?? -0.125,
      blurInches: 0,
      transparency: transparency ?? 0,
    );
  }

  /// Resolve the QuickStyle line matrix through the LineStyle chain.
  int? resolveQuickStyleLineMatrix(int? lineStyleId) {
    var id = lineStyleId;
    final seen = <int>{};
    while (id != null && seen.add(id)) {
      final sheet = _byId[id];
      if (sheet == null) break;
      if (sheet.quickStyleLineMatrix != null) {
        return sheet.quickStyleLineMatrix;
      }
      id = sheet.lineStyleId;
    }
    return null;
  }

  /// Resolve the QuickStyle fill matrix through the FillStyle chain.
  int? resolveQuickStyleFillMatrix(int? fillStyleId) {
    var id = fillStyleId;
    final seen = <int>{};
    while (id != null && seen.add(id)) {
      final sheet = _byId[id];
      if (sheet == null) break;
      if (sheet.quickStyleFillMatrix != null) {
        return sheet.quickStyleFillMatrix;
      }
      id = sheet.fillStyleId;
    }
    return null;
  }
}

extension on Set<String> {
  bool addIfAbsent(String cell, Set<String> defined) {
    if (contains(cell) || !defined.contains(cell)) return false;
    add(cell);
    return true;
  }
}
