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
    this.line,
    this.lineDefinedCells = const <String>{},
    this.fill,
    this.fillDefinedCells = const <String>{},
    this.shadow,
    this.shadowDefinedCells = const <String>{},
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
    var underline = false;
    var sawStyle = false;
    // Colour is often THEMEVAL / index — leave null unless we get a hex.
    // (Colour resolution stays with StyleParser + theme.)

    final seen = <int>{};
    while (id != null && seen.add(id)) {
      final sheet = _byId[id];
      if (sheet == null) break;
      final c = sheet.charStyle;
      if (c != null) {
        fontFamily ??= c.fontFamily;
        if (fontSizeInches == null &&
            !sheet.charSizeInherits &&
            c.fontSizeInches > 0) {
          fontSizeInches = c.fontSizeInches;
        }
        if (!sawStyle &&
            (c.style.bold || c.style.italic || c.underline)) {
          style = c.style;
          underline = c.underline;
          sawStyle = true;
        } else if (!sawStyle && c.style == VsdxFontStyle.regular) {
          // Explicit Style=0 on this sheet — still a concrete value.
          style = c.style;
          underline = c.underline;
          sawStyle = true;
        }
      }
      id = sheet.textStyleId;
    }

    if (fontFamily == null && fontSizeInches == null && !sawStyle) {
      return null;
    }
    return VsdxCharStyle(
      fontFamily: fontFamily,
      fontSizeInches: fontSizeInches ?? VsdxCharStyle.defaults.fontSizeInches,
      style: style ?? VsdxFontStyle.regular,
      underline: underline,
    );
  }

  /// Resolve effective [VsdxLine] defaults from a `LineStyle` id (weight /
  /// pattern / colour / SoftEdgesSize / Rounding), walking the parent chain.
  VsdxLine? resolveLine(int? lineStyleId) {
    var id = lineStyleId;
    if (id == null) return null;

    VsdxColor? color;
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
      final defined = sheet.lineDefinedCells.isEmpty
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
        if (color == null &&
            defined.contains('LineColor') &&
            line.color != null) {
          color = line.color;
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
        if (endArrowSizeInches == null &&
            defined.contains('EndArrowSize')) {
          endArrowSizeInches = line.endArrowSizeInches;
        }
        if (softEdgesInches == null &&
            defined.contains('SoftEdgesSize')) {
          softEdgesInches = line.softEdgesInches;
        }
        if (roundingInches == null &&
            defined.contains('Rounding')) {
          roundingInches = line.roundingInches;
        }
        if (compoundType == null && defined.contains('CompoundType')) {
          compoundType = line.compoundType;
        }
      }
      id = sheet.lineStyleId;
    }

    if (color == null &&
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
      softEdgesInches:
          softEdgesInches ?? VsdxLine.defaultLine.softEdgesInches,
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
    VsdxGradient? gradient;
    double? foregroundTransparency;
    double? backgroundTransparency;

    final seen = <int>{};
    while (id != null && seen.add(id)) {
      final sheet = _byId[id];
      if (sheet == null) break;
      final fill = sheet.fill;
      // Empty defined set ⇒ hand-built / legacy sheet: take every field.
      final defined = sheet.fillDefinedCells.isEmpty
          ? const {
              'FillForegnd',
              'FillBkgnd',
              'FillPattern',
              'FillForegndTrans',
              'FillBkgndTrans',
            }
          : sheet.fillDefinedCells;
      if (fill != null) {
        if (foreground == null &&
            defined.contains('FillForegnd') &&
            fill.foreground != null) {
          foreground = fill.foreground;
        }
        if (background == null &&
            defined.contains('FillBkgnd') &&
            fill.background != null) {
          background = fill.background;
        }
        if (pattern == null && defined.contains('FillPattern')) {
          pattern = fill.pattern;
        }
        themeForegroundIndex ??= fill.themeForegroundIndex;
        themeBackgroundIndex ??= fill.themeBackgroundIndex;
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

    if (foreground == null &&
        background == null &&
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
    int? pattern;
    double? offsetX;
    double? offsetY;
    double? transparency;

    final seen = <int>{};
    while (id != null && seen.add(id)) {
      final sheet = _byId[id];
      if (sheet == null) break;
      final shadow = sheet.shadow;
      final defined = sheet.shadowDefinedCells.isEmpty
          ? const {
              'ShdwForegnd',
              'ShdwPattern',
              'ShapeShdwOffsetX',
              'ShapeShdwOffsetY',
              'ShdwForegndTrans',
            }
          : sheet.shadowDefinedCells;
      if (shadow != null) {
        if (color == null &&
            defined.contains('ShdwForegnd') &&
            shadow.color != null) {
          color = shadow.color;
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
        if (transparency == null &&
            defined.contains('ShdwForegndTrans')) {
          transparency = shadow.transparency;
        }
      }
      id = sheet.fillStyleId;
    }

    if (color == null &&
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
      offsetXInches: offsetX ?? pageOffsetXInches ?? 0.125,
      offsetYInches: offsetY ?? pageOffsetYInches ?? -0.125,
      blurInches: 0,
      transparency: transparency ?? 0,
    );
  }
}
