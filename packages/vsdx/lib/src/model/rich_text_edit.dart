/// In-place rich-text surgery: apply styles to a UTF-16 range, replace plain
/// text while preserving per-character styles, and coalesce adjacent runs.
///
/// Used by the editor so draw.io-style selection formatting and text edits do
/// not flatten a multi-run label into a single styled run.
library;

import 'rich_text.dart';

/// Apply [update] to every character in [[start], [end]) (UTF-16 offsets into
/// [rich.plainText]). Splits runs at the range boundaries and merges adjacent
/// runs that end up with identical styles. Out-of-range indices are clamped;
/// an empty range is a no-op.
///
/// Field (`<fld>`) and tab (`<tp>`) markers are remapped onto the resulting
/// runs so a style-only edit does not strip Visio dynamic text on save.
VsdxRichText applyCharStyleToRange(
  VsdxRichText rich, {
  required int start,
  required int end,
  required VsdxCharStyle Function(VsdxCharStyle) update,
}) {
  final plain = rich.plainText;
  if (plain.isEmpty || rich.runs.isEmpty) return rich;
  var a = start < end ? start : end;
  var b = start < end ? end : start;
  a = a.clamp(0, plain.length);
  b = b.clamp(0, plain.length);
  if (a >= b) return rich;

  final styles = <VsdxCharStyle>[];
  final paras = <VsdxParaStyle>[];
  _expandStyles(rich, styles, paras);
  for (var i = a; i < b; i++) {
    styles[i] = update(styles[i]);
  }
  return rich.copyWith(
    runs: _coalesce(
      plain,
      styles,
      paras,
      fields: _absoluteFields(rich),
      tabs: _absoluteTabs(rich),
    ),
  );
}

/// Apply [update] to paragraph styles of every character in [[start], [end]).
VsdxRichText applyParaStyleToRange(
  VsdxRichText rich, {
  required int start,
  required int end,
  required VsdxParaStyle Function(VsdxParaStyle) update,
}) {
  final plain = rich.plainText;
  if (plain.isEmpty || rich.runs.isEmpty) return rich;
  var a = start < end ? start : end;
  var b = start < end ? end : start;
  a = a.clamp(0, plain.length);
  b = b.clamp(0, plain.length);
  if (a >= b) return rich;

  final styles = <VsdxCharStyle>[];
  final paras = <VsdxParaStyle>[];
  _expandStyles(rich, styles, paras);
  for (var i = a; i < b; i++) {
    paras[i] = update(paras[i]);
  }
  return rich.copyWith(
    runs: _coalesce(
      plain,
      styles,
      paras,
      fields: _absoluteFields(rich),
      tabs: _absoluteTabs(rich),
    ),
  );
}

/// Replace the plain-text content of [rich] with [newText], preserving
/// per-character styles on the longest common prefix and suffix. Characters
/// inserted in the middle inherit the style at the caret (end of the prefix).
///
/// Field / tab markers wholly inside the preserved prefix or suffix are kept
/// (suffix markers are remapped); markers that overlapped the edited middle
/// are dropped.
VsdxRichText replacePlainText(VsdxRichText rich, String newText) {
  final old = rich.plainText;
  if (old == newText) return rich;
  if (rich.runs.isEmpty) {
    return rich.copyWith(
      runs: <VsdxTextRun>[VsdxTextRun(text: newText)],
    );
  }
  if (newText.isEmpty) {
    // Keep one empty run so subsequent typing still has a style to inherit.
    final first = rich.runs.first;
    return rich.copyWith(
      runs: <VsdxTextRun>[
        VsdxTextRun(
          text: '',
          charStyle: first.charStyle,
          paraStyle: first.paraStyle,
        ),
      ],
    );
  }
  // Empty → non-empty: inherit the seeded run's style (Bold-before-type).
  if (old.isEmpty) {
    final first = rich.runs.first;
    return rich.copyWith(
      runs: <VsdxTextRun>[
        VsdxTextRun(
          text: newText,
          charStyle: first.charStyle,
          paraStyle: first.paraStyle,
        ),
      ],
    );
  }

  final styles = <VsdxCharStyle>[];
  final paras = <VsdxParaStyle>[];
  _expandStyles(rich, styles, paras);

  var prefix = 0;
  final maxPrefix = old.length < newText.length ? old.length : newText.length;
  while (prefix < maxPrefix &&
      old.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  final maxSuffix = (old.length - prefix) < (newText.length - prefix)
      ? (old.length - prefix)
      : (newText.length - prefix);
  while (suffix < maxSuffix &&
      old.codeUnitAt(old.length - 1 - suffix) ==
          newText.codeUnitAt(newText.length - 1 - suffix)) {
    suffix++;
  }

  final insertChar = prefix > 0 ? styles[prefix - 1] : styles.first;
  final insertPara = prefix > 0 ? paras[prefix - 1] : paras.first;

  final newStyles = <VsdxCharStyle>[];
  final newParas = <VsdxParaStyle>[];
  for (var i = 0; i < prefix; i++) {
    newStyles.add(styles[i]);
    newParas.add(paras[i]);
  }
  final mid = newText.length - prefix - suffix;
  for (var i = 0; i < mid; i++) {
    newStyles.add(insertChar);
    newParas.add(insertPara);
  }
  for (var i = 0; i < suffix; i++) {
    final oi = old.length - suffix + i;
    newStyles.add(styles[oi]);
    newParas.add(paras[oi]);
  }

  final oldSuffixStart = old.length - suffix;
  final newSuffixStart = newText.length - suffix;
  final mappedFields = <(int, int, int)>[];
  for (final f in _absoluteFields(rich)) {
    final end = f.$1 + f.$2;
    if (end <= prefix) {
      mappedFields.add(f);
    } else if (f.$1 >= oldSuffixStart) {
      mappedFields.add((
        newSuffixStart + (f.$1 - oldSuffixStart),
        f.$2,
        f.$3,
      ));
    }
  }
  final mappedTabs = <(int, int)>[];
  for (final t in _absoluteTabs(rich)) {
    if (t.$1 < prefix) {
      mappedTabs.add(t);
    } else if (t.$1 >= oldSuffixStart) {
      mappedTabs.add((newSuffixStart + (t.$1 - oldSuffixStart), t.$2));
    }
  }

  return rich.copyWith(
    runs: _coalesce(
      newText,
      newStyles,
      newParas,
      fields: mappedFields,
      tabs: mappedTabs,
    ),
  );
}

/// Character style at UTF-16 offset [index] (clamped), or `null` when empty.
VsdxCharStyle? charStyleAt(VsdxRichText rich, int index) {
  if (rich.runs.isEmpty) return null;
  final plain = rich.plainText;
  if (plain.isEmpty) return rich.runs.first.charStyle;
  final i = index.clamp(0, plain.length - 1);
  var offset = 0;
  for (final r in rich.runs) {
    if (i < offset + r.text.length) return r.charStyle;
    offset += r.text.length;
  }
  return rich.runs.last.charStyle;
}

void _expandStyles(
  VsdxRichText rich,
  List<VsdxCharStyle> styles,
  List<VsdxParaStyle> paras,
) {
  for (final r in rich.runs) {
    for (var i = 0; i < r.text.length; i++) {
      styles.add(r.charStyle);
      paras.add(r.paraStyle);
    }
  }
}

/// Absolute (start, length, ix) field spans across [rich.plainText].
List<(int, int, int)> _absoluteFields(VsdxRichText rich) {
  final out = <(int, int, int)>[];
  var offset = 0;
  for (final r in rich.runs) {
    for (final f in r.fieldSpans) {
      out.add((offset + f.start, f.length, f.ix));
    }
    offset += r.text.length;
  }
  return out;
}

/// Absolute (position, tab-row IX) for each `\t` in [rich.plainText].
List<(int, int)> _absoluteTabs(VsdxRichText rich) {
  final out = <(int, int)>[];
  var offset = 0;
  for (final r in rich.runs) {
    var ti = 0;
    for (var i = 0; i < r.text.length; i++) {
      if (r.text.codeUnitAt(i) != 0x09) continue;
      final ix = ti < r.tabIndices.length ? r.tabIndices[ti] : 0;
      out.add((offset + i, ix));
      ti++;
    }
    offset += r.text.length;
  }
  return out;
}

List<VsdxFieldSpan> _clipFields(
  List<(int, int, int)> fields,
  int runStart,
  int runEnd,
) {
  final out = <VsdxFieldSpan>[];
  for (final f in fields) {
    final fs = f.$1;
    final fe = f.$1 + f.$2;
    if (fe <= runStart || fs >= runEnd) continue;
    final clipStart = fs < runStart ? runStart : fs;
    final clipEnd = fe > runEnd ? runEnd : fe;
    final len = clipEnd - clipStart;
    if (len <= 0) continue;
    out.add(VsdxFieldSpan(
      start: clipStart - runStart,
      length: len,
      ix: f.$3,
    ));
  }
  return out;
}

List<int> _clipTabs(
  List<(int, int)> tabs,
  String plain,
  int runStart,
  int runEnd,
) {
  final out = <int>[];
  for (final t in tabs) {
    if (t.$1 < runStart || t.$1 >= runEnd) continue;
    if (plain.codeUnitAt(t.$1) != 0x09) continue;
    out.add(t.$2);
  }
  return out;
}

List<VsdxTextRun> _coalesce(
  String plain,
  List<VsdxCharStyle> styles,
  List<VsdxParaStyle> paras, {
  List<(int, int, int)> fields = const <(int, int, int)>[],
  List<(int, int)> tabs = const <(int, int)>[],
}) {
  assert(plain.length == styles.length);
  assert(plain.length == paras.length);
  if (plain.isEmpty) {
    return <VsdxTextRun>[
      VsdxTextRun(
        text: '',
        charStyle: styles.isNotEmpty ? styles.first : VsdxCharStyle.defaults,
        paraStyle: paras.isNotEmpty ? paras.first : VsdxParaStyle.defaults,
      ),
    ];
  }
  final out = <VsdxTextRun>[];
  var start = 0;
  for (var i = 1; i <= plain.length; i++) {
    final boundary = i == plain.length ||
        !_sameStyle(styles[i], styles[start], paras[i], paras[start]);
    if (boundary) {
      out.add(VsdxTextRun(
        text: plain.substring(start, i),
        charStyle: styles[start],
        paraStyle: paras[start],
        fieldSpans: _clipFields(fields, start, i),
        tabIndices: _clipTabs(tabs, plain, start, i),
      ));
      start = i;
    }
  }
  return out;
}

bool _sameStyle(
  VsdxCharStyle a,
  VsdxCharStyle b,
  VsdxParaStyle pa,
  VsdxParaStyle pb,
) =>
    _sameChar(a, b) && _samePara(pa, pb);

bool _sameChar(VsdxCharStyle a, VsdxCharStyle b) =>
    a.fontFamily == b.fontFamily &&
    a.fontSizeInches == b.fontSizeInches &&
    a.style.bold == b.style.bold &&
    a.style.italic == b.style.italic &&
    a.style.smallCaps == b.style.smallCaps &&
    a.color == b.color &&
    a.themeColorIndex == b.themeColorIndex &&
    a.underline == b.underline &&
    a.strikethrough == b.strikethrough &&
    a.doubleUnderline == b.doubleUnderline &&
    a.doubleStrikethrough == b.doubleStrikethrough &&
    a.overline == b.overline &&
    a.highlight?.value == b.highlight?.value &&
    a.transparency == b.transparency &&
    a.letterSpacingInches == b.letterSpacingInches &&
    a.position == b.position &&
    a.textCase == b.textCase &&
    a.fontScale == b.fontScale &&
    a.asianFont == b.asianFont &&
    a.complexScriptFont == b.complexScriptFont &&
    a.langId == b.langId &&
    a.complexScriptSizeInches == b.complexScriptSizeInches;

bool _samePara(VsdxParaStyle a, VsdxParaStyle b) =>
    a.horizontalAlign == b.horizontalAlign &&
    a.indentFirstInches == b.indentFirstInches &&
    a.indentLeftInches == b.indentLeftInches &&
    a.indentRightInches == b.indentRightInches &&
    a.spaceBeforeInches == b.spaceBeforeInches &&
    a.spaceAfterInches == b.spaceAfterInches &&
    a.lineSpacing == b.lineSpacing &&
    a.lineSpacingAbsoluteInches == b.lineSpacingAbsoluteInches &&
    a.lineSpacingSolid == b.lineSpacingSolid &&
    a.bullet == b.bullet &&
    a.bulletStr == b.bulletStr &&
    a.bulletFont == b.bulletFont &&
    a.bulletFontSizeInches == b.bulletFontSizeInches &&
    a.textPosAfterBulletInches == b.textPosAfterBulletInches &&
    a.flags == b.flags;
