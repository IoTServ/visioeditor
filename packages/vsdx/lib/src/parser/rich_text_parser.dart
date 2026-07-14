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

  /// Parse the shape's text into a [VsdxRichText]. Returns
  /// [VsdxRichText.empty] when the shape has no `<Text>` element.
  VsdxRichText parse(
    XmlElement shape, {
    VsdxCharStyle defaultChar = VsdxCharStyle.defaults,
    VsdxParaStyle defaultPara = VsdxParaStyle.defaults,
  }) {
    final textEl = _firstChildLocal(shape, 'Text');
    final block = _readTextBlock(shape);
    if (textEl == null) {
      return VsdxRichText(runs: const [], textBlock: block);
    }

    final charStyles = _readCharSection(shape, defaultChar);
    final paraStyles = _readParaSection(shape, defaultPara);

    final runs = _splitRuns(
      textEl,
      charStyles: charStyles,
      paraStyles: paraStyles,
      defaultChar: defaultChar,
      defaultPara: defaultPara,
    );
    return VsdxRichText(runs: List.unmodifiable(runs), textBlock: block);
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
    final font = _cellString(row, 'Font') ?? defaults.fontFamily;
    final size = readLengthInches(row, 'Size') ?? defaults.fontSizeInches;
    final styleInt = _cellInt(row, 'Style');
    final style = styleInt == null
        ? defaults.style
        : VsdxFontStyle.fromBitmask(styleInt);
    final colorCell = _cellString(row, 'Color');
    final isTheme = colorCell != null &&
        (colorCell.toUpperCase().contains('THEMEVAL') ||
            colorCell.toUpperCase().contains('THEMEGUARD'));
    final color = isTheme ? null : VsdxColor.tryParse(colorCell);
    final themeIdx = isTheme ? _cellInt(row, 'ColorTrans') : null;
    final underline = (_cellInt(row, 'Style') ?? 0) & 0x04 != 0;
    final strike = (_cellInt(row, 'Strikethru') ?? 0) != 0;
    final transparency = _cellDouble(row, 'ColorTrans') ?? defaults.transparency;
    final posInt = _cellInt(row, 'Position');
    final position = switch (posInt) {
      1 => VsdxTextPosition.superscript,
      2 => VsdxTextPosition.subscript,
      _ => defaults.position,
    };
    return VsdxCharStyle(
      fontFamily: font,
      fontSizeInches: size,
      style: style,
      color: color ?? defaults.color,
      themeColorIndex: themeIdx ?? defaults.themeColorIndex,
      underline: underline || defaults.underline,
      strikethrough: strike || defaults.strikethrough,
      transparency: transparency.clamp(0.0, 1.0),
      letterSpacingInches:
          readLengthInches(row, 'Letterspace') ?? defaults.letterSpacingInches,
      position: position,
    );
  }

  VsdxParaStyle _readParaRow(XmlElement row, VsdxParaStyle defaults) {
    final horz = _cellInt(row, 'HorzAlign');
    final align = horz == null ? defaults.horizontalAlign : _alignFromInt(horz);
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
      lineSpacing: _cellDouble(row, 'SpLine') ?? defaults.lineSpacing,
    );
  }

  VsdxTextBlock _readTextBlock(XmlElement shape) {
    final vAlignInt = _cellInt(shape, 'VerticalAlign');
    return VsdxTextBlock(
      pinXInches: readLengthInches(shape, 'TxtPinX'),
      pinYInches: readLengthInches(shape, 'TxtPinY'),
      locPinXInches: readLengthInches(shape, 'TxtLocPinX'),
      locPinYInches: readLengthInches(shape, 'TxtLocPinY'),
      widthInches: readLengthInches(shape, 'TxtWidth'),
      heightInches: readLengthInches(shape, 'TxtHeight'),
      angleRad: readAngleRadians(shape, 'TxtAngle') ?? 0,
      verticalAlign: switch (vAlignInt) {
        0 => VsdxVertAlign.top,
        2 => VsdxVertAlign.bottom,
        _ => VsdxVertAlign.middle,
      },
      marginLeftInches:
          readLengthInches(shape, 'LeftMargin') ?? 0.04,
      marginRightInches:
          readLengthInches(shape, 'RightMargin') ?? 0.04,
      marginTopInches:
          readLengthInches(shape, 'TopMargin') ?? 0.04,
      marginBottomInches:
          readLengthInches(shape, 'BottomMargin') ?? 0.04,
    );
  }

  /// Walk the children of `<Text>`, splitting at every `<cp/>` / `<pp/>`
  /// marker. Returns the assembled runs in source order.
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

    void flush() {
      if (buf.isEmpty) return;
      runs.add(VsdxTextRun(
        text: buf.toString(),
        charStyle: curChar,
        paraStyle: curPara,
      ));
      buf.clear();
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
            // Tab paragraph marker — emit a tab character within the run.
            buf.write('\t');
          case 'fld':
            // Dynamic field (PageNumber, DateField, …) — resolved via the
            // injected field resolver.
            buf.write(fieldResolver.resolve(node));
          default:
            // Unknown inline marker — ignore but keep going.
        }
      }
    }
    flush();
    _trimTrailingWhitespace(runs);
    return runs;
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
        runs.removeLast();
      } else {
        runs[runs.length - 1] = last.copyWith(text: trimmed);
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
