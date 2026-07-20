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
  const RichTextParser({this.fieldResolver = FieldResolver.placeholder});

  /// Field substitution policy. Defaults to a static placeholder; the
  /// PageParser overrides it per page so `PageNumber` / `PageCount` /
  /// `Title` / `DateField` resolve to real values.
  final FieldResolver fieldResolver;

  /// Parse the shape's text into a [VsdxRichText].
  ///
  /// Masters often define a `<Section N="Character">` without a `<Text>`
  /// element — still surface that style as an empty run so instance shapes
  /// inherit Size/Style the same way libvisio does.
  VsdxRichText parse(
    XmlElement shape, {
    VsdxCharStyle defaultChar = VsdxCharStyle.defaults,
    VsdxParaStyle defaultPara = VsdxParaStyle.defaults,
    VsdxTextBlock defaultBlock = VsdxTextBlock.defaults,
  }) {
    final textEl = _firstChildLocal(shape, 'Text');
    final block = _readTextBlock(shape, defaultBlock);
    final charStyles = _readCharSection(shape, defaultChar);
    final paraStyles = _readParaSection(shape, defaultPara);
    final tabSets = _readTabsSection(shape);

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
      RichTextParser(fieldResolver: resolver);

  /// Public: parse only the Character section into a map IX→style (used by
  /// the Master parser to lift defaults onto instance shapes).
  Map<int, VsdxCharStyle> readCharStyles(
    XmlElement shape, {
    VsdxCharStyle defaultChar = VsdxCharStyle.defaults,
  }) =>
      _readCharSection(shape, defaultChar);

  Map<int, VsdxCharStyle> _readCharSection(
    XmlElement shape,
    VsdxCharStyle defaults,
  ) {
    final out = <int, VsdxCharStyle>{};
    for (final section in shape.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Character') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final ix =
            int.tryParse(row.getAttribute('IX') ?? row.getAttribute('N') ?? '');
        if (ix == null) continue;
        out[ix] = _readCharRow(row, defaults);
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

  VsdxCharStyle _readCharRow(XmlElement row, VsdxCharStyle defaults) {
    // Font / Color stay null when the cell is absent — do NOT materialise the
    // stylesheet default into the model. Editor-created shapes leave both unset
    // (inherit via DefaultTextStyle at paint / in Visio); stuffing Arial /
    // #000000 here made save→reopen drift (`null → Arial` / `null → black`).
    // Size and other metrics still fall back to [defaults] (TextStyle / master).
    final font = _cellString(row, 'Font');
    final size = readLengthInches(row, 'Size') ?? defaults.fontSizeInches;
    final styleInt = _cellInt(row, 'Style');
    final style = styleInt == null
        ? defaults.style
        : VsdxFontStyle.fromBitmask(styleInt);
    final colorCell = findCell(row, 'Color');
    final colorV = colorCell?.getAttribute('V');
    final colorF = colorCell?.getAttribute('F') ?? '';
    final isTheme = (colorV != null &&
            (colorV.toUpperCase().contains('THEMEVAL') ||
                colorV.toUpperCase().contains('THEMEGUARD'))) ||
        colorF.toUpperCase().contains('THEMEVAL') ||
        colorF.toUpperCase().contains('THEMEGUARD');
    final color = isTheme ? null : VsdxColor.tryParse(colorV);
    // A theme character colour caches its slot index in V (see the writer);
    // read it back when present, otherwise fall back to the inherited slot.
    int? themeIdx;
    if (isTheme) {
      final parsed = int.tryParse((colorV ?? '').trim());
      themeIdx = (parsed != null && parsed >= 0 && parsed < 100)
          ? parsed
          : (defaults.themeColorIndex ?? 0);
    }
    // Underline lives in Style bit 0x04 (libvisio); only inherit when absent.
    final underline =
        styleInt != null ? (styleInt & 0x04) != 0 : defaults.underline;
    final strikeCell = _cellInt(row, 'Strikethru');
    final strike =
        strikeCell != null ? strikeCell != 0 : defaults.strikethrough;
    final dblUnderCell = _cellInt(row, 'DblUnderline');
    final dblUnder = dblUnderCell != null
        ? dblUnderCell != 0
        : defaults.doubleUnderline;
    final dblStrikeCell = _cellInt(row, 'DoubleStrikethrough');
    final dblStrike = dblStrikeCell != null
        ? dblStrikeCell != 0
        : defaults.doubleStrikethrough;
    final overCell = _cellInt(row, 'Overline');
    final overline = overCell != null ? overCell != 0 : defaults.overline;
    final transparency = _cellDouble(row, 'ColorTrans') ?? defaults.transparency;
    final posInt = _cellInt(row, 'Pos');
    final position = switch (posInt) {
      1 => VsdxTextPosition.superscript,
      2 => VsdxTextPosition.subscript,
      null => defaults.position,
      _ => VsdxTextPosition.normal,
    };
    final caseInt = _cellInt(row, 'Case');
    final textCase = switch (caseInt) {
      1 => VsdxTextCase.allCaps,
      2 => VsdxTextCase.initialCaps,
      null => defaults.textCase,
      _ => VsdxTextCase.normal,
    };
    final fontScale = _cellDouble(row, 'FontScale') ?? defaults.fontScale;
    return VsdxCharStyle(
      fontFamily: font,
      fontSizeInches: size,
      style: style,
      color: color,
      themeColorIndex: themeIdx ?? defaults.themeColorIndex,
      underline: underline,
      strikethrough: strike,
      doubleUnderline: dblUnder,
      doubleStrikethrough: dblStrike,
      overline: overline,
      transparency: transparency.clamp(0.0, 1.0),
      letterSpacingInches:
          readLengthInches(row, 'Letterspace') ?? defaults.letterSpacingInches,
      position: position,
      textCase: textCase,
      fontScale: fontScale,
      asianFont: _cellString(row, 'AsianFont') ?? defaults.asianFont,
      complexScriptFont:
          _cellString(row, 'ComplexScriptFont') ?? defaults.complexScriptFont,
      langId: _cellString(row, 'LangID') ?? defaults.langId,
      complexScriptSizeInches: readLengthInches(row, 'ComplexScriptSize') ??
          defaults.complexScriptSizeInches,
    );
  }

  VsdxParaStyle _readParaRow(XmlElement row, VsdxParaStyle defaults) {
    final horz = _cellInt(row, 'HorzAlign');
    final align = horz == null ? defaults.horizontalAlign : _alignFromInt(horz);
    final (lineSpacing, lineSpacingAbs, lineSpacingSolid) =
        _readLineSpacing(row, defaults);
    final bulletStr = _cellString(row, 'BulletStr');
    final bulletFont = _cellString(row, 'BulletFont');
    return VsdxParaStyle(
      horizontalAlign: align,
      indentFirstInches:
          readLengthInches(row, 'IndFirst') ?? defaults.indentFirstInches,
      indentLeftInches:
          readLengthInches(row, 'IndLeft') ?? defaults.indentLeftInches,
      indentRightInches:
          readLengthInches(row, 'IndRight') ?? defaults.indentRightInches,
      spaceBeforeInches:
          readLengthInches(row, 'SpBefore') ?? defaults.spaceBeforeInches,
      spaceAfterInches:
          readLengthInches(row, 'SpAfter') ?? defaults.spaceAfterInches,
      lineSpacing: lineSpacing,
      lineSpacingAbsoluteInches: lineSpacingAbs,
      lineSpacingSolid: lineSpacingSolid,
      bullet: _cellInt(row, 'Bullet') ?? defaults.bullet,
      bulletStr: (bulletStr == null || bulletStr.isEmpty)
          ? defaults.bulletStr
          : bulletStr,
      bulletFont: (bulletFont == null || bulletFont.isEmpty)
          ? defaults.bulletFont
          : bulletFont,
      bulletFontSizeInches: readLengthInches(row, 'BulletFontSize') ??
          defaults.bulletFontSizeInches,
      textPosAfterBulletInches:
          readLengthInches(row, 'TextPosAfterBullet') ??
              defaults.textPosAfterBulletInches,
      flags: _cellInt(row, 'Flags') ?? defaults.flags,
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
    final sp = _cellDouble(row, 'SpLine');
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
  VsdxTextBlock _readTextBlock(XmlElement shape, VsdxTextBlock inherit) {
    final vAlignInt = _cellInt(shape, 'VerticalAlign');
    final hideInt = _cellInt(shape, 'HideText');
    return VsdxTextBlock(
      pinXInches: readLengthInches(
            shape,
            'TxtPinX',
            inheritFrom: inherit.pinXInches,
          ) ??
          inherit.pinXInches,
      pinYInches: readLengthInches(
            shape,
            'TxtPinY',
            inheritFrom: inherit.pinYInches,
          ) ??
          inherit.pinYInches,
      locPinXInches: readLengthInches(
            shape,
            'TxtLocPinX',
            inheritFrom: inherit.locPinXInches,
          ) ??
          inherit.locPinXInches,
      locPinYInches: readLengthInches(
            shape,
            'TxtLocPinY',
            inheritFrom: inherit.locPinYInches,
          ) ??
          inherit.locPinYInches,
      widthInches: readLengthInches(
            shape,
            'TxtWidth',
            inheritFrom: inherit.widthInches,
          ) ??
          inherit.widthInches,
      heightInches: readLengthInches(
            shape,
            'TxtHeight',
            inheritFrom: inherit.heightInches,
          ) ??
          inherit.heightInches,
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
      hideText: hideInt == null ? inherit.hideText : hideInt != 0,
      // Absent TextBkgnd → inherit; explicit V=0/255 → transparent (do not
      // fall back to master — mirrors VSD textBgFilled=false).
      backgroundColor: _resolveTextBkgnd(shape, inherit.backgroundColor),
      backgroundTransparency:
          (_cellDouble(shape, 'TextBkgndTrans') ?? inherit.backgroundTransparency)
              .clamp(0.0, 1.0),
      textDirection: _cellInt(shape, 'TextDirection') ?? inherit.textDirection,
      defaultTabStopInches: readLengthInches(shape, 'DefaultTabStop') ??
          inherit.defaultTabStopInches,
    );
  }

  /// Resolve `TextBkgnd`: missing cell inherits; present transparent sentinel
  /// clears (null); otherwise parse the colour.
  VsdxColor? _resolveTextBkgnd(XmlElement shape, VsdxColor? inherit) {
    if (findCell(shape, 'TextBkgnd') == null) return inherit;
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
    return VsdxColor.tryParse(raw);
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
  }) {
    final runs = <VsdxTextRun>[];
    var curChar = charStyles[0] ?? defaultChar;
    var curPara = paraStyles[0] ?? defaultPara;
    final buf = StringBuffer();
    final fieldSpans = <VsdxFieldSpan>[];
    final tabIndices = <int>[];

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
        buf.write(node.value);
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
            // Tab marker — emit `\t` and record Tabs-row IX (libvisio).
            buf.write('\t');
            tabIndices.add(int.tryParse(node.getAttribute('IX') ?? '') ?? 0);
          case 'fld':
            // Dynamic field — keep display text for paint, record span for
            // XML round-trip (`<fld IX="n">cached</fld>`).
            final ix = int.tryParse(node.getAttribute('IX') ?? '') ?? 0;
            final display = fieldResolver.resolve(node);
            final start = buf.length;
            buf.write(display);
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
    _trimTrailingWhitespace(runs);
    return runs;
  }

  /// `<Section N="Tabs">` — libvisio `PositionN` / `AlignmentN` cells per row.
  List<VsdxTabSet> _readTabsSection(XmlElement shape) {
    final out = <VsdxTabSet>[];
    for (final section in shape.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Tabs') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final ix = int.tryParse(row.getAttribute('IX') ?? '') ?? out.length;
        final byIndex = <int, VsdxTabStop>{};
        for (final cell in row.childElements) {
          if (cell.name.local != 'Cell') continue;
          final n = cell.getAttribute('N') ?? '';
          if (n.startsWith('Position') && n.length > 8) {
            final idx = int.tryParse(n.substring(8));
            if (idx == null) continue;
            final pos = readLengthInches(row, n) ??
                double.tryParse(cell.getAttribute('V') ?? '') ??
                0;
            final prev = byIndex[idx];
            byIndex[idx] = VsdxTabStop(
              positionInches: pos,
              alignment: prev?.alignment ?? 0,
            );
          } else if (n.startsWith('Alignment') && n.length > 9) {
            final idx = int.tryParse(n.substring(9));
            if (idx == null) continue;
            final align = int.tryParse(cell.getAttribute('V') ?? '') ?? 0;
            final prev = byIndex[idx];
            byIndex[idx] = VsdxTabStop(
              positionInches: prev?.positionInches ?? 0,
              alignment: align,
            );
          }
        }
        final keys = byIndex.keys.toList()..sort();
        out.add(VsdxTabSet(
          ix: ix,
          stops: [for (final k in keys) byIndex[k]!],
        ));
      }
    }
    return List.unmodifiable(out);
  }

  /// Visio commonly terminates a label with a trailing newline plus an empty
  /// tab-stop marker (`…市场部需求\n<tp/>`), which would otherwise render as a
  /// blank extra line and push the visible text off-centre. Strip trailing
  /// whitespace from the run stream so a single-line label stays centred —
  /// matching how Visio and libvisio lay the text out.
  static void _trimTrailingWhitespace(List<VsdxTextRun> runs) {
    while (runs.isNotEmpty) {
      final last = runs.last;
      final trimmed = last.text.replaceFirst(RegExp(r'\s+$'), '');
      if (trimmed == last.text) break;
      if (trimmed.isEmpty) {
        // Keep a run that exists only to host zero-length field markers.
        final kept = [
          for (final s in last.fieldSpans)
            if (s.length == 0) s,
        ];
        if (kept.isEmpty) {
          runs.removeLast();
        } else {
          runs[runs.length - 1] = last.copyWith(
            text: '',
            fieldSpans: kept,
          );
          break;
        }
      } else {
        final newSpans = <VsdxFieldSpan>[
          for (final s in last.fieldSpans)
            if (s.start < trimmed.length)
              VsdxFieldSpan(
                start: s.start,
                length: s.length > trimmed.length - s.start
                    ? trimmed.length - s.start
                    : s.length,
                ix: s.ix,
              )
            else if (s.length == 0 && s.start == trimmed.length)
              s,
        ];
        // Drop tab indices that belonged to trimmed trailing tabs.
        final keptTabs = '\t'.allMatches(trimmed).length;
        final newTabs = last.tabIndices.length <= keptTabs
            ? last.tabIndices
            : last.tabIndices.sublist(0, keptTabs);
        runs[runs.length - 1] = last.copyWith(
          text: trimmed,
          fieldSpans: newSpans,
          tabIndices: newTabs,
        );
        break;
      }
    }
  }

  String? _cellString(XmlElement parent, String name) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    final v = cell.getAttribute('V');
    if (v == null) return null;
    return v.isEmpty ? null : v;
  }

  int? _cellInt(XmlElement parent, String name) {
    final s = _cellString(parent, name);
    if (s == null) return null;
    return int.tryParse(s) ?? double.tryParse(s)?.toInt();
  }

  double? _cellDouble(XmlElement parent, String name) {
    final s = _cellString(parent, name);
    if (s == null) return null;
    return double.tryParse(s);
  }

  VsdxHorzAlign _alignFromInt(int v) => switch (v) {
        0 => VsdxHorzAlign.left,
        1 => VsdxHorzAlign.center,
        2 => VsdxHorzAlign.right,
        3 => VsdxHorzAlign.justify,
        _ => VsdxHorzAlign.left,
      };

  XmlElement? _firstChildLocal(XmlElement parent, String name) {
    for (final el in parent.childElements) {
      if (el.name.local == name) return el;
    }
    return null;
  }
}
