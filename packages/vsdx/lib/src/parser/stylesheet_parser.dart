/// Parse `<StyleSheet>` entries from `visio/document.xml` into a
/// [StyleSheetRegistry].
///
/// Visio shapes reference styles via `TextStyle` / `LineStyle` / `FillStyle`
/// attributes (or inherit them from a Master). libvisio walks the same chain
/// when a shape omits its own Character `Size` cell — without this, we fall
/// back to the hard-coded 12pt default and diverge from the oracle.
library;

import 'package:logging/logging.dart';
import 'package:xml/xml.dart';

import '../model/fill.dart';
import '../model/effects.dart';
import '../model/line.dart';
import '../model/rich_text.dart';
import '../model/stylesheet.dart';
import '../model/theme.dart';
import '../utils/color.dart';
import 'cell_helpers.dart';
import 'rich_text_parser.dart';

final _log = Logger('vsdx.parser.stylesheet');

class StyleSheetParser {
  const StyleSheetParser({
    this.colorPalette = const <int, VsdxColor>{},
    this.fontNames = const <int, String>{},
  });

  final Map<int, VsdxColor> colorPalette;
  final Map<int, String> fontNames;

  StyleSheetRegistry parse(
    XmlDocument documentXml, {
    int? defaultTextStyleId,
  }) {
    // Prefer the attribute on <DocumentSettings> when the caller didn't pass
    // one (DocumentSettingsParser historically ignored it).
    final settingsDefault = defaultTextStyleId ??
        _documentSettingsTextStyle(documentXml.rootElement);

    final byId = <int, VsdxStyleSheet>{};
    for (final el in documentXml.rootElement.childElements) {
      if (el.name.local != 'StyleSheets') continue;
      for (final ss in el.childElements) {
        if (ss.name.local != 'StyleSheet') continue;
        _readSheetSafely(ss, byId);
      }
    }
    // Some writers put StyleSheet elements directly under VisioDocument.
    if (byId.isEmpty) {
      for (final ss in documentXml.rootElement.childElements) {
        if (ss.name.local != 'StyleSheet') continue;
        _readSheetSafely(ss, byId);
      }
    }
    return StyleSheetRegistry(Map.unmodifiable(byId),
        defaultTextStyleId: settingsDefault);
  }

  void _readSheetSafely(
    XmlElement element,
    Map<int, VsdxStyleSheet> output,
  ) {
    try {
      final sheet = _readSheet(element);
      if (sheet != null) output[sheet.id] = sheet;
    } catch (error, stackTrace) {
      _log.warning(
        'Skipping malformed stylesheet ${element.getAttribute('ID') ?? '?'}',
        error,
        stackTrace,
      );
    }
  }

  int? _documentSettingsTextStyle(XmlElement root) {
    for (final el in root.childElements) {
      if (el.name.local != 'DocumentSettings') continue;
      final a = el.getAttribute('DefaultTextStyle');
      if (a != null) return int.tryParse(a);
    }
    return null;
  }

  VsdxStyleSheet? _readSheet(XmlElement ss) {
    final id = int.tryParse(ss.getAttribute('ID') ?? '');
    if (id == null) return null;
    final name =
        ss.getAttribute('NameU') ?? ss.getAttribute('Name') ?? 'Style.$id';
    final textStyleId = int.tryParse(ss.getAttribute('TextStyle') ?? '');
    final lineStyleId = int.tryParse(ss.getAttribute('LineStyle') ?? '');
    final fillStyleId = int.tryParse(ss.getAttribute('FillStyle') ?? '');

    VsdxCharStyle? charStyle;
    var charSizeInherits = false;
    final charDefined = <String>{};
    VsdxParaStyle? paraStyle;
    var paraDefined = <String>{};
    VsdxTextBlock? textBlock;
    var textBlockDefined = <String>{};
    VsdxLine? line;
    final lineDefined = <String>{};
    VsdxFill? fill;
    final fillDefined = <String>{};
    VsdxShadow? shadow;
    final shadowDefined = <String>{};

    for (final section in ss.childElements) {
      if (section.name.local != 'Section') continue;
      switch (section.getAttribute('N')) {
        case 'Character':
          final row = _firstRow(section);
          if (row != null) {
            final sizeCell = findCell(row, 'Size');
            charSizeInherits = isInhFormula(sizeCell?.getAttribute('F'));
            for (final name in const <String>{
              'Font',
              'Size',
              'Style',
              'Color',
              'Strikethru',
              'DblUnderline',
              'DoubleStrikethrough',
              'Overline',
              'ColorTrans',
              'Letterspace',
              'Pos',
              'Case',
              'FontScale',
              'AsianFont',
              'ComplexScriptFont',
              'LangID',
              'ComplexScriptSize',
            }) {
              final cell = _concreteCell(row, name);
              if (cell != null && (name == 'Color' || !_isThemeCell(cell))) {
                charDefined.add(name);
              }
            }
            if (charDefined.isNotEmpty) {
              charStyle = RichTextParser(
                colorPalette: colorPalette,
                fontNames: fontNames,
              ).readCharStyleRow(row);
            }
          }
        case 'Paragraph':
          final parsed = _readParagraphStyle(section);
          paraStyle = parsed.style;
          paraDefined = parsed.defined;
        case 'Line':
          // Line cells may sit directly under the section (no Row) in styles.
          // F=Inh → treat as absent so [StyleSheetRegistry.resolveLine] walks
          // the parent LineStyle chain instead of the cached V=.
          final weight = _length(section, 'LineWeight');
          final pat = _cellInt(section, 'LinePattern');
          final colorRes = _resolveColor(
            section,
            'LineColor',
            'QuickStyleLineColor',
            quickStyle100Fallback: VsdxColor.black,
          );
          final color = colorRes.color;
          final soft = _length(section, 'SoftEdgesSize');
          final rounding = _length(section, 'Rounding');
          if (weight != null) lineDefined.add('LineWeight');
          if (pat != null) lineDefined.add('LinePattern');
          if (colorRes.defined) lineDefined.add('LineColor');
          if (soft != null) lineDefined.add('SoftEdgesSize');
          if (rounding != null) lineDefined.add('Rounding');
          if (lineDefined.isNotEmpty) {
            line = VsdxLine(
              color: color,
              themeColorIndex: colorRes.themeIndex,
              weightInches: weight ?? VsdxLine.defaultLine.weightInches,
              pattern: pat ?? VsdxLine.defaultLine.pattern,
              softEdgesInches: soft ?? VsdxLine.defaultLine.softEdgesInches,
              roundingInches: rounding ?? VsdxLine.defaultLine.roundingInches,
            );
          }
        case 'Fill':
          final pat = _cellInt(section, 'FillPattern');
          final fgRes = _resolveColor(
            section,
            'FillForegnd',
            'QuickStyleFillColor',
            quickStyle100Fallback: VsdxColor.white,
          );
          final bgRes = _resolveColor(
            section,
            'FillBkgnd',
            'QuickStyleFillColor',
            quickStyle100Fallback: VsdxColor.white,
          );
          final fg = fgRes.color;
          final bg = bgRes.color;
          if (pat != null) fillDefined.add('FillPattern');
          if (fgRes.defined) fillDefined.add('FillForegnd');
          if (bgRes.defined) fillDefined.add('FillBkgnd');
          if (fillDefined.isNotEmpty) {
            fill = VsdxFill(
              foreground: fg,
              background: bg,
              themeForegroundIndex: fgRes.themeIndex,
              themeBackgroundIndex: bgRes.themeIndex,
              pattern: pat ?? VsdxFill.defaultFill.pattern,
            );
          }
      }
    }

    // The normative VSDX layout places Line/Fill/TextBlock cells directly
    // under <StyleSheet>, not inside a Section. libvisio's
    // readStyleProperties() consumes both those direct cells and Character /
    // Paragraph sections in one pass. Preserve the section form above for
    // third-party writers, then overlay any concrete direct cells here.
    final weight = _length(ss, 'LineWeight');
    final linePattern = _cellInt(ss, 'LinePattern');
    final lineColorRes = _resolveColor(
      ss,
      'LineColor',
      'QuickStyleLineColor',
      quickStyle100Fallback: VsdxColor.black,
    );
    final lineColor = lineColorRes.color;
    final lineCapValue = _cellInt(ss, 'LineCap');
    final lineTransparency = _number(ss, 'LineColorTrans');
    final beginArrow = _cellInt(ss, 'BeginArrow');
    final endArrow = _cellInt(ss, 'EndArrow');
    final beginArrowSize = _cellInt(ss, 'BeginArrowSize');
    final endArrowSize = _cellInt(ss, 'EndArrowSize');
    final directRounding = _length(ss, 'Rounding');
    final directSoftEdges = _length(ss, 'SoftEdgesSize');
    final compoundType = _cellInt(ss, 'CompoundType');
    if (weight != null) lineDefined.add('LineWeight');
    if (linePattern != null) lineDefined.add('LinePattern');
    if (lineColorRes.defined) lineDefined.add('LineColor');
    if (lineCapValue != null) lineDefined.add('LineCap');
    if (lineTransparency != null) lineDefined.add('LineColorTrans');
    if (beginArrow != null) lineDefined.add('BeginArrow');
    if (endArrow != null) lineDefined.add('EndArrow');
    if (beginArrowSize != null) lineDefined.add('BeginArrowSize');
    if (endArrowSize != null) lineDefined.add('EndArrowSize');
    if (directRounding != null) lineDefined.add('Rounding');
    if (directSoftEdges != null) lineDefined.add('SoftEdgesSize');
    if (compoundType != null) lineDefined.add('CompoundType');
    if (lineDefined.isNotEmpty) {
      line = VsdxLine(
        color: lineColorRes.defined ? lineColor : line?.color,
        themeColorIndex: lineColorRes.defined
            ? lineColorRes.themeIndex
            : line?.themeColorIndex,
        weightInches:
            weight ?? line?.weightInches ?? VsdxLine.defaultLine.weightInches,
        pattern: linePattern ?? line?.pattern ?? VsdxLine.defaultLine.pattern,
        cap: lineCapValue == null
            ? (line?.cap ?? VsdxLine.defaultLine.cap)
            : _lineCap(lineCapValue),
        transparency: (lineTransparency ??
                line?.transparency ??
                VsdxLine.defaultLine.transparency)
            .clamp(0.0, 1.0),
        beginArrow:
            beginArrow ?? line?.beginArrow ?? VsdxLine.defaultLine.beginArrow,
        endArrow: endArrow ?? line?.endArrow ?? VsdxLine.defaultLine.endArrow,
        beginArrowSizeInches: beginArrowSize == null
            ? (line?.beginArrowSizeInches ??
                VsdxLine.defaultLine.beginArrowSizeInches)
            : _arrowSize(beginArrowSize),
        endArrowSizeInches: endArrowSize == null
            ? (line?.endArrowSizeInches ??
                VsdxLine.defaultLine.endArrowSizeInches)
            : _arrowSize(endArrowSize),
        roundingInches: directRounding ??
            line?.roundingInches ??
            VsdxLine.defaultLine.roundingInches,
        softEdgesInches: directSoftEdges ??
            line?.softEdgesInches ??
            VsdxLine.defaultLine.softEdgesInches,
        compoundType: compoundType ??
            line?.compoundType ??
            VsdxLine.defaultLine.compoundType,
      );
    }

    final fillPattern = _cellInt(ss, 'FillPattern');
    final fgRes = _resolveColor(
      ss,
      'FillForegnd',
      'QuickStyleFillColor',
      quickStyle100Fallback: VsdxColor.white,
    );
    final fg = fgRes.color;
    final bgRes = _resolveColor(
      ss,
      'FillBkgnd',
      'QuickStyleFillColor',
      quickStyle100Fallback: VsdxColor.white,
    );
    final bg = bgRes.color;
    final fgTransparency = _number(ss, 'FillForegndTrans');
    final bgTransparency = _number(ss, 'FillBkgndTrans');
    if (fillPattern != null) fillDefined.add('FillPattern');
    if (fgRes.defined) fillDefined.add('FillForegnd');
    if (bgRes.defined) fillDefined.add('FillBkgnd');
    if (fgTransparency != null) fillDefined.add('FillForegndTrans');
    if (bgTransparency != null) fillDefined.add('FillBkgndTrans');
    if (fillDefined.isNotEmpty) {
      fill = VsdxFill(
        foreground: fgRes.defined ? fg : fill?.foreground,
        background: bgRes.defined ? bg : fill?.background,
        themeForegroundIndex:
            fgRes.defined ? fgRes.themeIndex : fill?.themeForegroundIndex,
        themeBackgroundIndex:
            bgRes.defined ? bgRes.themeIndex : fill?.themeBackgroundIndex,
        pattern: fillPattern ?? fill?.pattern ?? VsdxFill.defaultFill.pattern,
        foregroundTransparency: (fgTransparency ??
                fill?.foregroundTransparency ??
                VsdxFill.defaultFill.foregroundTransparency)
            .clamp(0.0, 1.0),
        backgroundTransparency: (bgTransparency ??
                fill?.backgroundTransparency ??
                VsdxFill.defaultFill.backgroundTransparency)
            .clamp(0.0, 1.0),
      );
    }

    final shadowPattern = _cellInt(ss, 'ShdwPattern');
    final shadowColorRes = _resolveColor(
      ss,
      'ShdwForegnd',
      'QuickStyleShadowColor',
      quickStyle100Fallback: VsdxColor.black,
    );
    final shadowColor = shadowColorRes.color;
    final shadowOffsetX = _length(ss, 'ShapeShdwOffsetX');
    final shadowOffsetY = _length(ss, 'ShapeShdwOffsetY');
    final shadowTransparency = _number(ss, 'ShdwForegndTrans');
    if (shadowPattern != null) shadowDefined.add('ShdwPattern');
    if (shadowColorRes.defined) shadowDefined.add('ShdwForegnd');
    if (shadowOffsetX != null) shadowDefined.add('ShapeShdwOffsetX');
    if (shadowOffsetY != null) shadowDefined.add('ShapeShdwOffsetY');
    if (shadowTransparency != null) {
      shadowDefined.add('ShdwForegndTrans');
    }
    if (shadowDefined.isNotEmpty) {
      final effectivePattern = shadowPattern ?? 0;
      shadow = VsdxShadow(
        enabled: effectivePattern != 0,
        pattern: effectivePattern == 0 ? 1 : effectivePattern,
        color: shadowColor,
        themeColorIndex: shadowColorRes.themeIndex,
        offsetXInches: shadowOffsetX ?? 0.125,
        offsetYInches: shadowOffsetY ?? -0.125,
        blurInches: 0,
        transparency: (shadowTransparency ?? 0).clamp(0.0, 1.0),
      );
    }

    final parsedTextBlock = _readTextBlockStyle(ss);
    textBlock = parsedTextBlock.style;
    textBlockDefined = parsedTextBlock.defined;

    return VsdxStyleSheet(
      id: id,
      name: name,
      textStyleId: textStyleId,
      lineStyleId: lineStyleId,
      fillStyleId: fillStyleId,
      charStyle: charStyle,
      charSizeInherits: charSizeInherits,
      charDefinedCells: Set.unmodifiable(charDefined),
      paraStyle: paraStyle,
      paraDefinedCells: Set.unmodifiable(paraDefined),
      textBlock: textBlock,
      textBlockDefinedCells: Set.unmodifiable(textBlockDefined),
      line: line,
      lineDefinedCells: Set.unmodifiable(lineDefined),
      fill: fill,
      fillDefinedCells: Set.unmodifiable(fillDefined),
      shadow: shadow,
      shadowDefinedCells: Set.unmodifiable(shadowDefined),
      quickStyleLineMatrix: _cellInt(ss, 'QuickStyleLineMatrix'),
      quickStyleFillMatrix: _cellInt(ss, 'QuickStyleFillMatrix'),
    );
  }

  XmlElement? _firstRow(XmlElement section) {
    for (final el in section.childElements) {
      if (el.name.local == 'Row') return el;
    }
    return null;
  }

  ({VsdxParaStyle? style, Set<String> defined}) _readParagraphStyle(
    XmlElement section,
  ) {
    final row = _firstRow(section);
    if (row == null) return (style: null, defined: <String>{});
    final defined = <String>{};

    double? length(String name) {
      final value = _length(row, name);
      if (value != null) defined.add(name);
      return value;
    }

    int? integer(String name) {
      final value = _cellInt(row, name);
      if (value != null) defined.add(name);
      return value;
    }

    String? bulletString() {
      final cell = _concreteCell(row, 'BulletStr');
      final value = cell?.getAttribute('V');
      if (value == null ||
          value.isEmpty ||
          value == '\uE000' ||
          value.toUpperCase() == 'THEMED') {
        return null;
      }
      defined.add('BulletStr');
      return value;
    }

    String? readBulletFont() {
      final cell = _concreteCell(row, 'BulletFont');
      final value = cell?.getAttribute('V');
      if (value == null || value.isEmpty || value.toUpperCase() == 'THEMED') {
        return null;
      }
      final index = int.tryParse(value);
      // libvisio treats numeric zero as no BulletFont override.
      if (index == 0) return null;
      defined.add('BulletFont');
      return index == null ? value : fontNames[index] ?? value;
    }

    final horz = integer('HorzAlign');
    final indFirst = length('IndFirst');
    final indLeft = length('IndLeft');
    final indRight = length('IndRight');
    final spBefore = length('SpBefore');
    final spAfter = length('SpAfter');
    final spLine = _number(row, 'SpLine');
    if (spLine != null) defined.add('SpLine');
    final bullet = integer('Bullet');
    final bulletStr = bulletString();
    final bulletFont = readBulletFont();
    final bulletFontSize = length('BulletFontSize');
    final textPosAfterBullet = length('TextPosAfterBullet');
    final flags = integer('Flags');
    if (defined.isEmpty) return (style: null, defined: defined);

    final lineSpacing = spLine == null || spLine >= 0 ? 1.0 : -spLine;
    final lineSpacingAbsolute = spLine != null && spLine > 0 ? spLine : 0.0;
    return (
      style: VsdxParaStyle(
        horizontalAlign: switch (horz) {
          1 => VsdxHorzAlign.center,
          2 => VsdxHorzAlign.right,
          3 => VsdxHorzAlign.justify,
          4 => VsdxHorzAlign.full,
          _ => VsdxHorzAlign.left,
        },
        indentFirstInches: indFirst ?? 0,
        indentLeftInches: indLeft ?? 0,
        indentRightInches: indRight ?? 0,
        spaceBeforeInches: spBefore ?? 0,
        spaceAfterInches: spAfter ?? 0,
        lineSpacing: lineSpacing,
        lineSpacingAbsoluteInches: lineSpacingAbsolute,
        lineSpacingSolid: spLine == 0,
        bullet: bullet ?? 0,
        bulletStr: bulletStr,
        bulletFont: bulletFont,
        bulletFontSizeInches: bulletFontSize,
        textPosAfterBulletInches: textPosAfterBullet ?? 0,
        flags: flags ?? 0,
      ),
      defined: defined,
    );
  }

  ({VsdxTextBlock? style, Set<String> defined}) _readTextBlockStyle(
    XmlElement sheet,
  ) {
    final defined = <String>{};

    double? length(String name) {
      final value = _length(sheet, name);
      if (value != null) defined.add(name);
      return value;
    }

    int? integer(String name) {
      final value = _cellInt(sheet, name);
      if (value != null) defined.add(name);
      return value;
    }

    final left = length('LeftMargin');
    final right = length('RightMargin');
    final top = length('TopMargin');
    final bottom = length('BottomMargin');
    final verticalAlign = integer('VerticalAlign');
    final backgroundCell = _concreteCell(sheet, 'TextBkgnd');
    if (backgroundCell != null) defined.add('TextBkgnd');
    final background = _textBackground(backgroundCell?.getAttribute('V'));
    final backgroundTransparency = _number(sheet, 'TextBkgndTrans');
    if (backgroundTransparency != null) defined.add('TextBkgndTrans');
    final textDirection = integer('TextDirection');
    final defaultTabStop = length('DefaultTabStop');
    if (defined.isEmpty) return (style: null, defined: defined);

    return (
      style: VsdxTextBlock(
        verticalAlign: switch (verticalAlign) {
          0 => VsdxVertAlign.top,
          2 => VsdxVertAlign.bottom,
          _ => VsdxVertAlign.middle,
        },
        marginLeftInches: left ?? VsdxTextBlock.defaults.marginLeftInches,
        marginRightInches: right ?? VsdxTextBlock.defaults.marginRightInches,
        marginTopInches: top ?? VsdxTextBlock.defaults.marginTopInches,
        marginBottomInches: bottom ?? VsdxTextBlock.defaults.marginBottomInches,
        backgroundColor: background,
        backgroundTransparency: (backgroundTransparency ?? 0).clamp(0.0, 1.0),
        textDirection: textDirection ?? 0,
        defaultTabStopInches:
            defaultTabStop ?? VsdxTextBlock.defaults.defaultTabStopInches,
      ),
      defined: defined,
    );
  }

  XmlElement? _concreteCell(XmlElement parent, String name) {
    final cell = findCell(parent, name);
    if (cell == null || isInhFormula(cell.getAttribute('F'))) return null;
    return cell;
  }

  bool _isThemeCell(XmlElement cell) {
    final value = cell.getAttribute('V') ?? '';
    final formula = cell.getAttribute('F') ?? '';
    final combined = '$value $formula'.toUpperCase();
    return value.toUpperCase() == 'THEMED' ||
        combined.contains('THEMEVAL') ||
        combined.contains('THEMEGUARD');
  }

  _StyleColorResolution _resolveColor(
    XmlElement parent,
    String colorCell,
    String quickStyleCell, {
    VsdxColor? quickStyle100Fallback,
  }) {
    final cell = _concreteCell(parent, colorCell);
    if (cell == null) return const _StyleColorResolution.absent();
    final value = cell.getAttribute('V') ?? '';
    final formula = cell.getAttribute('F') ?? '';
    final cached = VsdxColor.tryParse(value, palette: colorPalette);
    if (_isConcreteThemeGuard(formula) && cached != null) {
      return _StyleColorResolution(color: cached);
    }
    if (_isThemeFormula(value) || _isThemeFormula(formula)) {
      final named = _themeValArgSlot(formula.isNotEmpty ? formula : value);
      if (named != null) return _StyleColorResolution(themeIndex: named);
      final quick = _concreteCell(parent, quickStyleCell);
      final index = quick == null
          ? null
          : int.tryParse(quick.getAttribute('V') ?? '') ??
              double.tryParse(quick.getAttribute('V') ?? '')?.toInt();
      // libvisio starts QuickStyle colours at 100 and resolves 100..106 /
      // 200..206 through vt:variationClrSchemeLst. A missing selector has the
      // same default value 100; it must remain theme-bound rather than being
      // prematurely flattened to black/white.
      final themeIndex = index ?? 100;
      return _StyleColorResolution(
        color: themeIndex == 100 ? quickStyle100Fallback : null,
        themeIndex: themeIndex,
      );
    }
    return _StyleColorResolution(color: cached);
  }

  bool _isThemeFormula(String value) {
    final upper = value.toUpperCase();
    return upper == 'THEMED' ||
        upper.contains('THEMEVAL') ||
        upper.contains('THEMEGUARD');
  }

  bool _isConcreteThemeGuard(String formula) =>
      formula.toUpperCase().contains('THEMEGUARD');

  int? _themeValArgSlot(String formula) {
    final match = RegExp(
      r'THEMEVAL\s*\(\s*([^),]+)\s*[,)]',
      caseSensitive: false,
    ).firstMatch(formula);
    if (match == null) return null;
    return ThemeSlot.fromThemeValArg(match.group(1)!);
  }

  VsdxColor? _textBackground(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final value = raw.trim();
    if (value == '0' || value == '255') return null;
    return VsdxColor.tryParse(value, palette: colorPalette);
  }

  /// Length cell; `F=Inh` → null (caller keeps walking the parent chain).
  double? _length(XmlElement parent, String name) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    if (isInhFormula(cell.getAttribute('F'))) return null;
    return readLengthInches(parent, name);
  }

  String? _cellString(XmlElement parent, String name) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    if (isInhFormula(cell.getAttribute('F'))) return null;
    final v = cell.getAttribute('V');
    if (v == null || v.isEmpty) return null;
    // Skip theme formulas — not a concrete font name / colour.
    final u = v.toUpperCase();
    if (u == 'THEMED' || u.contains('THEMEVAL') || u.contains('THEMEGUARD')) {
      return null;
    }
    return v;
  }

  int? _cellInt(XmlElement parent, String name) {
    final s = _cellString(parent, name);
    if (s == null) return null;
    return int.tryParse(s) ?? double.tryParse(s)?.toInt();
  }

  double? _number(XmlElement parent, String name) {
    final s = _cellString(parent, name);
    return s == null ? null : double.tryParse(s);
  }

  LineCap _lineCap(int value) => switch (value) {
        1 => LineCap.extended,
        2 => LineCap.square,
        _ => LineCap.round,
      };

  double _arrowSize(int bucket) => switch (bucket) {
        0 => 0.0625,
        1 => 0.0875,
        2 => 0.125,
        3 => 0.175,
        4 => 0.225,
        5 => 0.30,
        6 => 0.375,
        _ => 0.125,
      };
}

class _StyleColorResolution {
  const _StyleColorResolution({this.color, this.themeIndex}) : defined = true;
  const _StyleColorResolution.absent()
      : color = null,
        themeIndex = null,
        defined = false;

  final VsdxColor? color;
  final int? themeIndex;
  final bool defined;
}
