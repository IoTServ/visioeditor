/// Parse `<Section N="Character">` + `<Section N="Paragraph">` + `<Text>`
/// into a [VsdxRichText].
///
/// MS-VSDX §2.2.5 / §2.2.6:
///
///   * Character / Paragraph sections each contain `<Row IX="N">` entries
///     whose `<Cell>` children carry the style values.
///   * `<Text>` interleaves text with `<cp IX="N"/>` (switch character
///     style to row N) and `<pp IX="N"/>` (switch paragraph style) markers.
///     Plain text without any marker uses row `IX=0`.
///
/// We resolve every marker eagerly: if a Char row referenced by `<cp/>`
/// doesn't exist (typical for shapes that inherit from a Master) we fall
/// back to the Char/Para [defaults] supplied by the caller (which the
/// PageParser populates from the Master prototype).
library;

import 'package:xml/xml.dart';

import '../model/rich_text.dart';
import '../model/sheet_sections.dart';
import '../utils/color.dart';
import 'cell_helpers.dart';

/// Lookup for `<fld>` inline fields. The PageParser may supply a fresh
/// instance per shape with the relevant `Field` section rows pre-parsed.
class FieldResolver {
  FieldResolver({
    required this.pageName,
    required this.pageIndex,
    required this.totalPages,
    String? documentTitle,
    String? documentCreator,
    DateTime? now,
  })  : _title = documentTitle ?? '',
        _creator = documentCreator ?? '',
        _now = now ?? DateTime.now();

  final String pageName;
  final int pageIndex;
  final int totalPages;
  final String _title;
  final String _creator;
  final DateTime _now;

  static const FieldResolver placeholder = FieldResolver._placeholder();
  const FieldResolver._placeholder()
      : pageName = 'Page',
        pageIndex = 0,
        totalPages = 1,
        _title = '',
        _creator = '',
        _now = const _ZeroDateTime();

  /// Resolve a single `<fld>` element from the rich-text stream. Returns
  /// the substitution string, or the element's literal innerText when the
  /// field type is unknown.
  String resolve(XmlElement fld) {
    final type = (fld.getAttribute('Type') ??
            fld.getAttribute('UICat') ??
            fld.getAttribute('Cat') ??
            '')
        .toLowerCase();
    final format = fld.getAttribute('Format') ?? '';
    switch (type) {
      case 'pagenumber':
      case 'page':
      case '0':
        return '${pageIndex + 1}';
      case 'pagecount':
      case 'pagesnum':
      case '6':
        return '$totalPages';
      case 'pagename':
        return pageName;
      case 'creator':
      case 'author':
        return _creator;
      case 'title':
        return _title;
      case 'date':
      case 'currentdate':
      case '5':
        return _formatDate(_now, format);
      case 'time':
      case 'currenttime':
        return _formatTime(_now, format);
      default:
        final inner = fld.innerText.trim();
        return inner.isEmpty ? '' : inner;
    }
  }

  static String _formatDate(DateTime t, String fmt) {
    // Minimal Visio date formatting — covers Visio's most common tokens.
    // For full ICU coverage callers can pre-format with `package:intl`.
    final y = t.year.toString().padLeft(4, '0');
    final m = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    if (fmt.isEmpty) return '$y-$m-$d';
    return fmt
        .replaceAll('yyyy', y)
        .replaceAll('yy', y.substring(2))
        .replaceAll('MM', m)
        .replaceAll('dd', d);
  }

  static String _formatTime(DateTime t, String fmt) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return fmt.isEmpty ? '$h:$m' : fmt.replaceAll('HH', h).replaceAll('mm', m);
  }
}

class _ZeroDateTime implements DateTime {
  const _ZeroDateTime();
  @override
  int get year => 1970;
  @override
  int get month => 1;
  @override
  int get day => 1;
  @override
  int get hour => 0;
  @override
  int get minute => 0;
  @override
  int get second => 0;
  @override
  int get millisecond => 0;
  @override
  int get microsecond => 0;
  @override
  int get weekday => DateTime.thursday;
  @override
  int get millisecondsSinceEpoch => 0;
  @override
  int get microsecondsSinceEpoch => 0;
  @override
  String get timeZoneName => 'UTC';
  @override
  Duration get timeZoneOffset => Duration.zero;
  @override
  bool get isUtc => true;
  @override
  bool isAfter(DateTime other) => false;
  @override
  bool isAtSameMomentAs(DateTime other) => other.millisecondsSinceEpoch == 0;
  @override
  bool isBefore(DateTime other) => other.millisecondsSinceEpoch > 0;
  @override
  Duration difference(DateTime other) =>
      Duration(milliseconds: -other.millisecondsSinceEpoch);
  @override
  DateTime add(Duration duration) => DateTime.fromMillisecondsSinceEpoch(
        duration.inMilliseconds,
        isUtc: true,
      );
  @override
  DateTime subtract(Duration duration) =>
      DateTime.fromMillisecondsSinceEpoch(-duration.inMilliseconds, isUtc: true);
  @override
  DateTime toLocal() => DateTime.fromMillisecondsSinceEpoch(0);
  @override
  DateTime toUtc() => DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  @override
  String toIso8601String() => '1970-01-01T00:00:00.000Z';
  @override
  String toString() => toIso8601String();
  @override
  int compareTo(DateTime other) =>
      millisecondsSinceEpoch.compareTo(other.millisecondsSinceEpoch);
}

class RichTextParser {
  const RichTextParser({
    this.fieldResolver = FieldResolver.placeholder,
    this.colorPalette = const <int, VsdxColor>{},
    this.fontNames = const <int, String>{},
  });

  /// Field substitution policy. Defaults to a static placeholder; the
  /// PageParser overrides it per page so `PageNumber` / `PageCount` /
  /// `Title` / `DateField` resolve to real values.
  final FieldResolver fieldResolver;
  final Map<int, VsdxColor> colorPalette;
  final Map<int, String> fontNames;

  /// Parse the shape's text into a [VsdxRichText].
  ///
  /// Masters often define a `<Section N="Character">` without a `<Text>`
  /// element — still surface that style as an empty run so instance shapes
  /// inherit Size/Style the same way libvisio does.
  VsdxRichText parse(
    XmlElement shape, {
    VsdxCharStyle defaultChar = libvisioCharacterStyleDefault,
    VsdxParaStyle defaultPara = libvisioParagraphStyleDefault,
    VsdxTextBlock defaultBlock = libvisioTextBlockStyleDefault,
    List<VsdxTabSet> inheritTabs = const <VsdxTabSet>[],
    List<VsdxFieldRow> fields = const <VsdxFieldRow>[],
    bool preferCachedInh = false,
  }) {
    final textEl = _firstChildLocal(shape, 'Text');
    final block = _readTextBlock(
      shape,
      defaultBlock,
      preferCachedInh: preferCachedInh,
    );
    final charStyles = _readCharSection(
      shape,
      defaultChar,
      preferCachedInh: preferCachedInh,
    );
    final paraStyles = _readParaSection(shape, defaultPara);
    final tabSets = _readTabsSection(shape, inherit: inheritTabs);

    if (textEl == null) {
      if (charStyles.isEmpty) {
        return VsdxRichText(
          runs: const [],
          textBlock: block,
          tabSets: tabSets,
        );
      }
      final style = charStyles[0] ?? charStyles.values.first;
      return VsdxRichText(
        runs: List.unmodifiable(<VsdxTextRun>[
          VsdxTextRun(text: '', charStyle: style, paraStyle: defaultPara),
        ]),
        textBlock: block,
        tabSets: tabSets,
      );
    }

    final runs = _splitRuns(
      textEl,
      charStyles: charStyles,
      paraStyles: paraStyles,
      defaultChar: defaultChar,
      defaultPara: defaultPara,
      fields: fields,
    );
    return VsdxRichText(
      runs: List.unmodifiable(runs),
      textBlock: block,
      tabSets: tabSets,
    );
  }

  /// Spawn a new parser with the field resolver overridden — useful for
  /// per-page substitution without rebuilding the rest of the config.
  RichTextParser withFieldResolver(FieldResolver resolver) =>
      RichTextParser(
        fieldResolver: resolver,
        colorPalette: colorPalette,
        fontNames: fontNames,
      );

  /// Public: parse only the Character section into a map IX→style (used by
  /// the Master parser to lift defaults onto instance shapes).
  Map<int, VsdxCharStyle> readCharStyles(
    XmlElement shape, {
    VsdxCharStyle defaultChar = VsdxCharStyle.defaults,
  }) =>
      _readCharSection(shape, defaultChar);

  /// Parse one Character row. StyleSheetParser uses the same decoder so
  /// stylesheet and shape-local rows agree on every libvisio character cell.
  VsdxCharStyle readCharStyleRow(
    XmlElement row, {
    VsdxCharStyle defaults = VsdxCharStyle.defaults,
  }) =>
      _readCharRow(row, defaults);

  Map<int, VsdxCharStyle> _readCharSection(
    XmlElement shape,
    VsdxCharStyle defaults, {
    bool preferCachedInh = false,
  }) {
    final out = <int, VsdxCharStyle>{};
    for (final section in shape.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Character') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final ix =
            int.tryParse(row.getAttribute('IX') ?? row.getAttribute('N') ?? '');
        if (ix == null) continue;
        out[ix] = _readCharRow(
          row,
          defaults,
          preferCachedInh: preferCachedInh,
        );
      }
    }
    return out;
  }

  Map<int, VsdxParaStyle> _readParaSection(
    XmlElement shape,
    VsdxParaStyle defaults,
  ) {
    final out = <int, VsdxParaStyle>{};
    for (final section in shape.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Paragraph') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final ix =
            int.tryParse(row.getAttribute('IX') ?? row.getAttribute('N') ?? '');
        if (ix == null) continue;
        out[ix] = _readParaRow(row, defaults);
      }
    }
    return out;
  }

  VsdxCharStyle _readCharRow(
    XmlElement row,
    VsdxCharStyle defaults, {
    bool preferCachedInh = false,
  }) {
    // Font / Color stay null when the cell is absent — do NOT materialise the
    // stylesheet default into the model. Editor-created shapes leave both unset
    // (inherit via DefaultTextStyle at paint / in Visio); stuffing Arial /
    // #000000 here made save→reopen drift (`null → Arial` / `null → black`).
    // Size and other metrics still fall back to [defaults] (TextStyle / master).
    final font = _fontString(row, 'Font', inheritFrom: defaults.fontFamily);
    final size = readLengthInches(
          row,
          'Size',
          inheritFrom: defaults.fontSizeInches,
        ) ??
        defaults.fontSizeInches;
    final styleInt = _cellInt(
      row,
      'Style',
      inheritFrom: (defaults.style.bold ? 0x01 : 0) |
          (defaults.style.italic ? 0x02 : 0) |
          (defaults.underline ? 0x04 : 0) |
          (defaults.style.smallCaps ? 0x08 : 0),
    );
    final style = styleInt == null
        ? defaults.style
        : VsdxFontStyle.fromBitmask(styleInt);
    final colorCell = findCell(row, 'Color');
    final colorV = colorCell?.getAttribute('V');
    final colorF = colorCell?.getAttribute('F') ?? '';
    final colorInh = isInhFormula(colorF);
    final cachedColor =
        VsdxColor.tryParse(colorV, palette: colorPalette);
    // libvisio consumes V= for formulas that *compute* from THEMEVAL (for
    // example IF(LUM(...),SHADE(THEMEVAL(...),75),...)). Only a direct
    // THEMEVAL(...) remains a live theme binding in our editable model.
    // Treating every formula containing THEMEVAL as a slot discarded Visio's
    // evaluated dark/red text caches and painted them black.
    final concreteThemeFormula = cachedColor != null &&
        (_isConcreteThemeGuard(colorF) ||
            (_containsThemeEval(colorF) && !_isDirectThemeEval(colorF)));
    final themedToken = colorV?.trim().toUpperCase() == 'THEMED';
    final isTheme = !colorInh &&
        !concreteThemeFormula &&
        ((colorV != null &&
                (colorV.toUpperCase().contains('THEMEVAL') ||
                    colorV.toUpperCase().contains('THEMEGUARD'))) ||
            colorF.toUpperCase().contains('THEMEVAL') ||
            colorF.toUpperCase().contains('THEMEGUARD'));
    // libvisio's VSDX shape reader consumes the evaluated V= cache even when
    // F="Inh". StyleSheet parsing keeps inheritance semantics, while a master
    // instance must retain its cached character colour.
    final color = colorInh
        ? (preferCachedInh && cachedColor != null
            ? cachedColor
            : defaults.color)
        : (isTheme
            ? (themedToken ? defaults.color : null)
            : cachedColor);
    // A theme character colour caches its slot index in V (see the writer);
    // read it back when present, otherwise fall back to the inherited slot.
    int? themeIdx;
    if (colorInh) {
      themeIdx = preferCachedInh && cachedColor != null
          ? null
          : defaults.themeColorIndex;
    } else if (isTheme && themedToken) {
      themeIdx = defaults.themeColorIndex;
    } else if (isTheme) {
      final parsed = int.tryParse((colorV ?? '').trim());
      themeIdx = (parsed != null && parsed >= 0 && parsed < 100)
          ? parsed
          : (defaults.themeColorIndex ?? 0);
    }
    // Underline lives in Style bit 0x04 (libvisio); only inherit when absent.
    final underline =
        styleInt != null ? (styleInt & 0x04) != 0 : defaults.underline;
    final strike =
        _cellBool(row, 'Strikethru',
            inheritFrom: defaults.strikethrough) ??
        defaults.strikethrough;
    final dblUnder =
        _cellBool(row, 'DblUnderline',
            inheritFrom: defaults.doubleUnderline) ??
        defaults.doubleUnderline;
    final dblStrike =
        _cellBool(row, 'DoubleStrikethrough',
            inheritFrom: defaults.doubleStrikethrough) ??
        defaults.doubleStrikethrough;
    final overline =
        _cellBool(row, 'Overline', inheritFrom: defaults.overline) ??
        defaults.overline;
    final transparency = (_cellDouble(row, 'ColorTrans',
                inheritFrom: defaults.transparency) ??
            defaults.transparency)
        .clamp(0.0, 1.0);
    final posInt = _cellInt(row, 'Pos',
        inheritFrom: switch (defaults.position) {
          VsdxTextPosition.superscript => 1,
          VsdxTextPosition.subscript => 2,
          _ => 0,
        });
    final position = switch (posInt) {
      1 => VsdxTextPosition.superscript,
      2 => VsdxTextPosition.subscript,
      null => defaults.position,
      _ => VsdxTextPosition.normal,
    };
    final caseInt = _cellInt(row, 'Case',
        inheritFrom: switch (defaults.textCase) {
          VsdxTextCase.allCaps => 1,
          VsdxTextCase.initialCaps => 2,
          _ => 0,
        });
    final textCase = switch (caseInt) {
      1 => VsdxTextCase.allCaps,
      2 => VsdxTextCase.initialCaps,
      null => defaults.textCase,
      _ => VsdxTextCase.normal,
    };
    final fontScale =
        _cellDouble(row, 'FontScale', inheritFrom: defaults.fontScale) ??
            defaults.fontScale;
    return VsdxCharStyle(
      fontFamily: font,
      fontSizeInches: size,
      style: style,
      color: color,
      themeColorIndex: colorCell == null
          ? null
          : (color != null ? null : (themeIdx ?? defaults.themeColorIndex)),
      underline: underline,
      strikethrough: strike,
      doubleUnderline: dblUnder,
      doubleStrikethrough: dblStrike,
      overline: overline,
      transparency: transparency,
      letterSpacingInches: readLengthInches(
            row,
            'Letterspace',
            inheritFrom: defaults.letterSpacingInches,
          ) ??
          defaults.letterSpacingInches,
      position: position,
      textCase: textCase,
      fontScale: fontScale,
      asianFont:
          _fontString(row, 'AsianFont', inheritFrom: defaults.asianFont),
      complexScriptFont: _fontString(row, 'ComplexScriptFont',
          inheritFrom: defaults.complexScriptFont),
      langId: _cellString(row, 'LangID', inheritFrom: defaults.langId),
      complexScriptSizeInches: readLengthInches(
        row,
        'ComplexScriptSize',
        inheritFrom: defaults.complexScriptSizeInches,
      ),
    );
  }

  bool _isConcreteThemeGuard(String formula) =>
      formula.toUpperCase().contains('THEMEGUARD');

  bool _containsThemeEval(String formula) =>
      formula.toUpperCase().contains('THEMEVAL');

  bool _isDirectThemeEval(String formula) => RegExp(
        r'^\s*THEMEVAL\s*\(',
        caseSensitive: false,
      ).hasMatch(formula);

  VsdxParaStyle _readParaRow(XmlElement row, VsdxParaStyle defaults) {
    final horz = _cellInt(
      row,
      'HorzAlign',
      inheritFrom: switch (defaults.horizontalAlign) {
        VsdxHorzAlign.center => 1,
        VsdxHorzAlign.right => 2,
        VsdxHorzAlign.justify => 3,
        VsdxHorzAlign.full => 4,
        _ => 0,
      },
    );
    final align = horz == null ? defaults.horizontalAlign : _alignFromInt(horz);
    final (lineSpacing, lineSpacingAbs, lineSpacingSolid) =
        _readLineSpacing(row, defaults);
    final rawBulletStr =
        _cellString(row, 'BulletStr', inheritFrom: defaults.bulletStr);
    // Visio 2002 writes U+E000 as its sentinel for an empty BulletStr;
    // libvisio treats it like an absent value so the inherited bullet stays.
    final bulletStr =
        rawBulletStr == '\uE000' || rawBulletStr?.toUpperCase() == 'THEMED'
            ? defaults.bulletStr
            : rawBulletStr;
    final bulletFont = _fontString(
      row,
      'BulletFont',
      inheritFrom: defaults.bulletFont,
      zeroIsAbsent: true,
    );
    return VsdxParaStyle(
      horizontalAlign: align,
      indentFirstInches: readLengthInches(
            row,
            'IndFirst',
            inheritFrom: defaults.indentFirstInches,
          ) ??
          defaults.indentFirstInches,
      indentLeftInches: readLengthInches(
            row,
            'IndLeft',
            inheritFrom: defaults.indentLeftInches,
          ) ??
          defaults.indentLeftInches,
      indentRightInches: readLengthInches(
            row,
            'IndRight',
            inheritFrom: defaults.indentRightInches,
          ) ??
          defaults.indentRightInches,
      spaceBeforeInches: readLengthInches(
            row,
            'SpBefore',
            inheritFrom: defaults.spaceBeforeInches,
          ) ??
          defaults.spaceBeforeInches,
      spaceAfterInches: readLengthInches(
            row,
            'SpAfter',
            inheritFrom: defaults.spaceAfterInches,
          ) ??
          defaults.spaceAfterInches,
      lineSpacing: lineSpacing,
      lineSpacingAbsoluteInches: lineSpacingAbs,
      lineSpacingSolid: lineSpacingSolid,
      bullet: _cellInt(row, 'Bullet', inheritFrom: defaults.bullet) ??
          defaults.bullet,
      bulletStr: (bulletStr == null || bulletStr.isEmpty)
          ? defaults.bulletStr
          : bulletStr,
      bulletFont: (bulletFont == null || bulletFont.isEmpty)
          ? defaults.bulletFont
          : bulletFont,
      bulletFontSizeInches: readLengthInches(
            row,
            'BulletFontSize',
            inheritFrom: defaults.bulletFontSizeInches,
          ) ??
          defaults.bulletFontSizeInches,
      textPosAfterBulletInches: readLengthInches(
            row,
            'TextPosAfterBullet',
            inheritFrom: defaults.textPosAfterBulletInches,
          ) ??
          defaults.textPosAfterBulletInches,
      flags: _cellInt(row, 'Flags', inheritFrom: defaults.flags) ??
          defaults.flags,
    );
  }

  /// Interpret Visio's `SpLine` (Paragraph section) into our two line-spacing
  /// fields. Per the ShapeSheet reference the cell is a percentage where 100%
  /// is a line's height:
  ///   * `< 0` — a percentage of type size (`-1.2` → 120% → 1.2× line height).
  ///   * `= 0` — "set solid": single spacing (100% of type size).
  ///   * `> 0` — absolute spacing in inches, independent of type size.
  /// Feeding the raw (usually negative) value straight into a Flutter
  /// `TextStyle.height` inverts the line advance, so wrapped lines stack
  /// upward instead of downward. Returns `(multiple, absoluteInches, solid)`.
  (double, double, bool) _readLineSpacing(
      XmlElement row, VsdxParaStyle defaults) {
    // Reconstruct master SpLine so F=Inh does not keep a stale V=.
    double? inheritSp;
    if (defaults.lineSpacingSolid) {
      inheritSp = 0;
    } else if (defaults.lineSpacingAbsoluteInches > 1e-12) {
      inheritSp = defaults.lineSpacingAbsoluteInches;
    } else if ((defaults.lineSpacing - 1.0).abs() > 1e-12) {
      inheritSp = -defaults.lineSpacing;
    }
    final sp = _cellDouble(row, 'SpLine', inheritFrom: inheritSp);
    if (sp == null) {
      return (
        defaults.lineSpacing,
        defaults.lineSpacingAbsoluteInches,
        defaults.lineSpacingSolid,
      );
    }
    if (sp < 0) return (-sp, 0.0, false);
    if (sp == 0) return (1.0, 0.0, true);
    return (1.0, sp, false); // V is already in internal units (inches)
  }

  /// Read the shape's text-block transform. Each cell falls back to [inherit]
  /// (the Master prototype's text block) when the instance omits it, so a
  /// shape that inherits its text orientation — most importantly `TxtAngle`
  /// (vertical / rotated labels) — from its Master renders correctly instead of
  /// defaulting to horizontal. Matches Visio / libvisio cell inheritance.
  VsdxTextBlock _readTextBlock(
    XmlElement shape,
    VsdxTextBlock inherit, {
    bool preferCachedInh = false,
  }) {
    double? instanceLength(String name, double? inherited) =>
        readLengthInches(
          shape,
          name,
          inheritFrom: preferCachedInh ? null : inherited,
        ) ??
        inherited;

    final vAlignInt = _cellInt(
      shape,
      'VerticalAlign',
      inheritFrom: switch (inherit.verticalAlign) {
        VsdxVertAlign.top => 0,
        VsdxVertAlign.bottom => 2,
        _ => 1,
      },
    );
    final hideText = _cellBool(
      shape,
      'HideText',
      inheritFrom: inherit.hideText,
    );
    return VsdxTextBlock(
      pinXInches: instanceLength('TxtPinX', inherit.pinXInches),
      pinYInches: instanceLength('TxtPinY', inherit.pinYInches),
      locPinXInches: instanceLength('TxtLocPinX', inherit.locPinXInches),
      locPinYInches: instanceLength('TxtLocPinY', inherit.locPinYInches),
      widthInches: instanceLength('TxtWidth', inherit.widthInches),
      heightInches: instanceLength('TxtHeight', inherit.heightInches),
      // F=Inh + cached V=0 must not flatten Master vertical text (π/2).
      angleRad: readAngleRadians(
            shape,
            'TxtAngle',
            inheritFrom:
                inherit.angleRad.abs() > 1e-12 ? inherit.angleRad : null,
          ) ??
          inherit.angleRad,
      verticalAlign: vAlignInt == null
          ? inherit.verticalAlign
          : switch (vAlignInt) {
              0 => VsdxVertAlign.top,
              2 => VsdxVertAlign.bottom,
              _ => VsdxVertAlign.middle,
            },
      marginLeftInches: readLengthInches(
            shape,
            'LeftMargin',
            inheritFrom: inherit.marginLeftInches,
          ) ??
          inherit.marginLeftInches,
      marginRightInches: readLengthInches(
            shape,
            'RightMargin',
            inheritFrom: inherit.marginRightInches,
          ) ??
          inherit.marginRightInches,
      marginTopInches: readLengthInches(
            shape,
            'TopMargin',
            inheritFrom: inherit.marginTopInches,
          ) ??
          inherit.marginTopInches,
      marginBottomInches: readLengthInches(
            shape,
            'BottomMargin',
            inheritFrom: inherit.marginBottomInches,
          ) ??
          inherit.marginBottomInches,
      hideText: hideText ?? inherit.hideText,
      // Absent TextBkgnd → inherit; explicit V=0/255 → transparent (do not
      // fall back to master — mirrors VSD textBgFilled=false).
      backgroundColor: _resolveTextBkgnd(shape, inherit.backgroundColor),
      backgroundTransparency: (_cellDouble(
                shape,
                'TextBkgndTrans',
                inheritFrom: inherit.backgroundTransparency,
              ) ??
              inherit.backgroundTransparency)
          .clamp(0.0, 1.0),
      textDirection: _cellInt(
            shape,
            'TextDirection',
            inheritFrom: inherit.textDirection,
          ) ??
          inherit.textDirection,
      defaultTabStopInches: readLengthInches(
            shape,
            'DefaultTabStop',
            inheritFrom: inherit.defaultTabStopInches,
          ) ??
          inherit.defaultTabStopInches,
    );
  }

  /// Resolve `TextBkgnd`: missing / `F=Inh` inherits; present transparent
  /// sentinel clears (null); otherwise parse the colour.
  VsdxColor? _resolveTextBkgnd(XmlElement shape, VsdxColor? inherit) {
    final cell = findCell(shape, 'TextBkgnd');
    if (cell == null) return inherit;
    if (isInhFormula(cell.getAttribute('F'))) return inherit;
    return _readTextBkgnd(shape);
  }

  /// `TextBkgnd` — solid colour behind the text. Palette indices `0` / `255`
  /// mean transparent (libvisio); hex colours are kept.
  VsdxColor? _readTextBkgnd(XmlElement shape) {
    final raw = _cellString(shape, 'TextBkgnd');
    if (raw == null || raw.isEmpty) return null;
    final u = raw.trim().toUpperCase();
    if (u == '0' || u == '255' || u == 'THEMED' || u.contains('THEMEVAL')) {
      return null;
    }
    final asInt = int.tryParse(raw);
    if (asInt == 0 || asInt == 255) return null;
    return VsdxColor.tryParse(raw, palette: colorPalette);
  }

  /// Walk the children of `<Text>`, splitting at every `<cp/>` / `<pp/>`
  /// marker. Returns the assembled runs in source order. `<fld IX>` markers
  /// keep their display cache inline and record a [VsdxFieldSpan] so the
  /// writer can emit `<fld>` again (libvisio / Visio round-trip).
  List<VsdxTextRun> _splitRuns(
    XmlElement textEl, {
    required Map<int, VsdxCharStyle> charStyles,
    required Map<int, VsdxParaStyle> paraStyles,
    required VsdxCharStyle defaultChar,
    required VsdxParaStyle defaultPara,
    required List<VsdxFieldRow> fields,
  }) {
    final runs = <VsdxTextRun>[];
    var curChar = charStyles[0] ?? defaultChar;
    var curPara = paraStyles[0] ?? defaultPara;
    final buf = StringBuffer();
    final fieldSpans = <VsdxFieldSpan>[];
    final tabIndices = <int>[];
    var currentTabSetIx = 0;
    final fieldsByIx = <int, VsdxFieldRow>{
      for (final field in fields) field.ix: field,
    };

    void flush() {
      if (buf.isEmpty && fieldSpans.isEmpty) return;
      runs.add(VsdxTextRun(
        text: buf.toString(),
        charStyle: curChar,
        paraStyle: curPara,
        fieldSpans: List.unmodifiable(fieldSpans),
        tabIndices: List.unmodifiable(tabIndices),
      ));
      buf.clear();
      fieldSpans.clear();
      tabIndices.clear();
    }

    for (final node in textEl.children) {
      if (node is XmlText) {
        final text = normalizeVisioText(node.value);
        buf.write(text);
        for (var i = 0; i < text.length; i++) {
          if (text.codeUnitAt(i) == 0x09) tabIndices.add(currentTabSetIx);
        }
      } else if (node is XmlElement) {
        switch (node.name.local) {
          case 'cp':
            flush();
            final ix = int.tryParse(node.getAttribute('IX') ?? '');
            if (ix != null) curChar = charStyles[ix] ?? defaultChar;
          case 'pp':
            flush();
            final ix = int.tryParse(node.getAttribute('IX') ?? '');
            if (ix != null) curPara = paraStyles[ix] ?? defaultPara;
          case 'tp':
            // `tp` selects the Tabs row for subsequent text; the actual tab is
            // a U+0009 character in an XML text node. This mirrors
            // libvisio's VSDXMLParserBase::readText char-count handling.
            currentTabSetIx =
                int.tryParse(node.getAttribute('IX') ?? '') ?? 0;
          case 'fld':
            // Dynamic field — keep display text for paint, record span for
            // XML round-trip (`<fld IX="n">cached</fld>`). DiagramML may
            // keep that cache only in Field.Value and emit an empty marker;
            // libvisio collects field rows before flushing the text object,
            // so use the same IX-based fallback rather than losing the label.
            final ix = int.tryParse(node.getAttribute('IX') ?? '') ?? 0;
            final resolved = fieldResolver.resolve(node);
            final display = normalizeVisioText(
              resolved.isNotEmpty
                  ? resolved
                  : (fieldsByIx[ix]?.displayText ?? ''),
            );
            final start = buf.length;
            buf.write(display);
            for (var i = 0; i < display.length; i++) {
              if (display.codeUnitAt(i) == 0x09) {
                tabIndices.add(currentTabSetIx);
              }
            }
            fieldSpans.add(VsdxFieldSpan(
              start: start,
              length: display.length,
              ix: ix,
            ));
          default:
            // Unknown inline marker — ignore but keep going.
        }
      }
    }
    flush();
    return runs;
  }

  /// `<Section N="Tabs">` — libvisio `PositionN` / `AlignmentN` cells per row.
  ///
  /// When [inherit] is supplied, rows with the same IX merge `F=Inh` cells from
  /// the master tab set (Position / Alignment).
  List<VsdxTabSet> _readTabsSection(
    XmlElement shape, {
    List<VsdxTabSet> inherit = const <VsdxTabSet>[],
  }) {
    final byIx = <int, VsdxTabSet>{
      for (final t in inherit) t.ix: t,
    };
    final out = <VsdxTabSet>[];
    var sawSection = false;
    for (final section in shape.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Tabs') continue;
      sawSection = true;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final ix = int.tryParse(row.getAttribute('IX') ?? '') ?? out.length;
        final proto = byIx[ix];
        final byIndex = <int, VsdxTabStop>{
          if (proto != null)
            // Visio PositionN / AlignmentN are 1-based.
            for (var i = 0; i < proto.stops.length; i++)
              i + 1: proto.stops[i],
        };
        for (final cell in row.childElements) {
          if (cell.name.local != 'Cell') continue;
          final n = cell.getAttribute('N') ?? '';
          if (n.startsWith('Position') && n.length > 8) {
            final idx = int.tryParse(n.substring(8));
            if (idx == null) continue;
            final protoStop = byIndex[idx];
            final pos = readLengthInches(row, n,
                    inheritFrom: protoStop?.positionInches) ??
                (isInhFormula(cell.getAttribute('F'))
                    ? protoStop?.positionInches
                    : null) ??
                double.tryParse(cell.getAttribute('V') ?? '') ??
                protoStop?.positionInches ??
                0;
            final prev = byIndex[idx];
            byIndex[idx] = VsdxTabStop(
              positionInches: pos,
              alignment: prev?.alignment ?? protoStop?.alignment ?? 0,
            );
          } else if (n.startsWith('Alignment') && n.length > 9) {
            final idx = int.tryParse(n.substring(9));
            if (idx == null) continue;
            final protoStop = byIndex[idx];
            final align = isInhFormula(cell.getAttribute('F'))
                ? (protoStop?.alignment ?? 0)
                : (int.tryParse(cell.getAttribute('V') ?? '') ??
                    protoStop?.alignment ??
                    0);
            final prev = byIndex[idx];
            byIndex[idx] = VsdxTabStop(
              positionInches: prev?.positionInches ?? protoStop?.positionInches ?? 0,
              alignment: align,
            );
          }
        }
        final keys = byIndex.keys.toList()..sort();
        // Prefer Visio 1-based stops. When Position0 and Position1 are a
        // legacy dual-write of the *same* stop (matching position + align),
        // drop the 0-based twin. Distinct 0-based multi-stop rows
        // (Position0/1/2 as three stops) must keep index 0.
        if (keys.contains(0) && keys.contains(1)) {
          final a = byIndex[0]!;
          final b = byIndex[1]!;
          final samePos =
              (a.positionInches - b.positionInches).abs() < 1e-9;
          if (samePos && a.alignment == b.alignment) {
            byIndex.remove(0);
            keys
              ..clear()
              ..addAll(byIndex.keys)
              ..sort();
          }
        }
        out.add(VsdxTabSet(
          ix: ix,
          stops: [for (final k in keys) byIndex[k]!],
        ));
      }
    }
    if (!sawSection && inherit.isNotEmpty) {
      return List.unmodifiable(inherit);
    }
    return List.unmodifiable(out);
  }

  String? _cellString(XmlElement parent, String name, {String? inheritFrom}) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    // F=Inh → master string (LangID / Font); absent cell stays null so Font
    // is not materialised from stylesheet defaults into the model.
    if (isInhFormula(cell.getAttribute('F'))) return inheritFrom;
    final v = cell.getAttribute('V');
    if (v == null) return null;
    return v.isEmpty ? null : v;
  }

  String? _fontString(
    XmlElement parent,
    String name, {
    String? inheritFrom,
    bool zeroIsAbsent = false,
  }) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    if (isInhFormula(cell.getAttribute('F'))) return inheritFrom;
    final value = cell.getAttribute('V') ?? '';
    final formula = cell.getAttribute('F') ?? '';
    final combined = '$value $formula'.toUpperCase();
    if (value.toUpperCase() == 'THEMED' ||
        combined.contains('THEMEVAL') ||
        combined.contains('THEMEGUARD')) {
      return inheritFrom;
    }
    if (value.isEmpty) return null;
    final index = int.tryParse(value);
    if (zeroIsAbsent && index == 0) return inheritFrom;
    return index == null ? value : fontNames[index] ?? value;
  }

  int? _cellInt(XmlElement parent, String name, {int? inheritFrom}) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    if (isInhFormula(cell.getAttribute('F'))) {
      if (inheritFrom != null) return inheritFrom;
    }
    final s = cell.getAttribute('V');
    if (s == null || s.isEmpty) return null;
    return int.tryParse(s) ?? double.tryParse(s)?.toInt();
  }

  bool? _cellBool(XmlElement parent, String name, {bool? inheritFrom}) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    if (isInhFormula(cell.getAttribute('F')) && inheritFrom != null) {
      return inheritFrom;
    }
    return parseVisioBool(cell.getAttribute('V'));
  }

  double? _cellDouble(XmlElement parent, String name, {double? inheritFrom}) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    if (isInhFormula(cell.getAttribute('F'))) {
      if (inheritFrom != null) return inheritFrom;
    }
    final s = cell.getAttribute('V');
    if (s == null || s.isEmpty) return null;
    return double.tryParse(s);
  }

  VsdxHorzAlign _alignFromInt(int v) => switch (v) {
        0 => VsdxHorzAlign.left,
        1 => VsdxHorzAlign.center,
        2 => VsdxHorzAlign.right,
        3 => VsdxHorzAlign.justify,
        4 => VsdxHorzAlign.full,
        _ => VsdxHorzAlign.left,
      };

  XmlElement? _firstChildLocal(XmlElement parent, String name) {
    for (final el in parent.childElements) {
      if (el.name.local == name) return el;
    }
    return null;
  }
}
