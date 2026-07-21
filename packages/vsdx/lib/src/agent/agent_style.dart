/// Shared style helpers for the Agent build / edit-ops pipelines: colour
/// parsing, default node/edge styling, text labelling, and connector assembly.
/// Mirrors the proven pattern in `tool/gen_example_templates.dart`.
library;

import 'package:vsdx/vsdx.dart';

/// Default dark ink for labels.
const VsdxColor kInk = VsdxColor(0xFF1F2937);

/// draw.io-like defaults so an unstyled diagram still looks intentional.
const VsdxColor kDefaultNodeFill = VsdxColor(0xFFDAE8FC);
const VsdxColor kDefaultNodeLine = VsdxColor(0xFF6C8EBF);
const VsdxColor kDefaultEdgeLine = VsdxColor(0xFF333333);

/// Parse `#RGB` / `#RRGGBB` / `#AARRGGBB` (with or without `#`) to a
/// [VsdxColor], or `null` when [hex] is `null`/blank/malformed.
VsdxColor? parseColorOrNull(String? hex) {
  if (hex == null) return null;
  var h = hex.trim();
  if (h.isEmpty) return null;
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 3) {
    // #RGB -> #RRGGBB
    h = h.split('').map((c) => '$c$c').join();
  }
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : VsdxColor(v);
}

/// Node fill from an optional hex, falling back to the default node fill.
VsdxFill fillFromHex(String? hex) {
  final c = parseColorOrNull(hex);
  if (hex != null && hex.trim().toLowerCase() == 'none') {
    return const VsdxFill(pattern: 0);
  }
  return VsdxFill(foreground: c ?? kDefaultNodeFill);
}

/// Node stroke from an optional hex, falling back to the default node line.
VsdxLine lineFromHex(String? hex, {double weightInches = 0.012, int endArrow = 0}) {
  if (hex != null && hex.trim().toLowerCase() == 'none') {
    return VsdxLine(color: kDefaultNodeLine, weightInches: weightInches, pattern: 0);
  }
  final c = parseColorOrNull(hex) ?? kDefaultNodeLine;
  return VsdxLine(color: c, weightInches: weightInches, endArrow: endArrow);
}

/// Keep Geometry NoFill/NoLine aligned with [s.fill]/[s.line] patterns so
/// `fill:none` / `line:none` export with Edraw-visible hollow flags.
VsdxShape syncNoneGeometryFlags(VsdxShape s) {
  var geos = s.geometries;
  geos = syncGeometryNoFill(geos, hollow: s.fill.pattern == 0);
  geos = syncGeometryNoLine(geos, hollow: s.line.pattern == 0);
  if (identical(geos, s.geometries)) return s;
  return s.copyWith(geometries: geos);
}

/// Attach a single-run label to [s] (plain text cache + styled rich run).
///
/// When [bold] / [colorHex] / [pt] are omitted, an existing first-run style is
/// preserved so `set_text` does not wipe bold / colour / size.
VsdxShape withLabel(
  VsdxShape s,
  String text, {
  bool? bold,
  bool? italic,
  bool? underline,
  bool? strikethrough,
  bool? doubleUnderline,
  bool? doubleStrikethrough,
  bool? overline,
  bool? smallCaps,
  String? colorHex,
  double? pt,
  String? fontFamily,
  double? letterSpacingInches,
  double? textTransparency,
  VsdxTextCase? textCase,
  VsdxTextPosition? textPosition,
  double? fontScale,
  String? langId,
  String? asianFont,
  String? complexScriptFont,
  double? complexScriptSizeInches,
}) {
  if (text.isEmpty) {
    // Clear label (set_text "" must round-trip as empty, not no-op).
    return s.copyWith(
      text: '',
      richText: VsdxRichText.empty,
      fields: const <VsdxFieldRow>[],
    );
  }
  final textChanged = text != (s.text ?? '');
  final prev =
      s.richText.runs.isNotEmpty ? s.richText.runs.first.charStyle : null;
  final clearColor =
      colorHex != null && colorHex.trim().toLowerCase() == 'none';
  final parsed = clearColor ? null : parseColorOrNull(colorHex);
  final fontSize = pt != null
      ? pt / 72.0
      : (prev?.fontSizeInches ?? 11 / 72.0);
  final prevStyle = prev?.style ?? VsdxFontStyle.regular;
  final fontStyle = prevStyle.copyWith(
    bold: bold ?? prevStyle.bold,
    italic: italic ?? prevStyle.italic,
    smallCaps: smallCaps ?? prevStyle.smallCaps,
  );
  // Preserve theme-bound text (color=null + themeColorIndex) unless the op
  // supplies an explicit colour — injecting kInk would paint solid ink and
  // writer would drop THEMEVAL on save. textColor:"none" clears solid/theme.
  late final VsdxCharStyle style;
  if (prev != null) {
    var next = prev.copyWith(
      fontSizeInches: fontSize,
      style: fontStyle,
      underline: underline ?? prev.underline,
      strikethrough: strikethrough ?? prev.strikethrough,
      doubleUnderline: doubleUnderline ?? prev.doubleUnderline,
      doubleStrikethrough:
          doubleStrikethrough ?? prev.doubleStrikethrough,
      overline: overline ?? prev.overline,
      fontFamily: fontFamily ?? prev.fontFamily,
      letterSpacingInches:
          letterSpacingInches ?? prev.letterSpacingInches,
      transparency: textTransparency ?? prev.transparency,
      textCase: textCase ?? prev.textCase,
      position: textPosition ?? prev.position,
      fontScale: fontScale ?? prev.fontScale,
      langId: langId ?? prev.langId,
      asianFont: asianFont ?? prev.asianFont,
      complexScriptFont: complexScriptFont ?? prev.complexScriptFont,
      complexScriptSizeInches:
          complexScriptSizeInches ?? prev.complexScriptSizeInches,
    );
    if (clearColor) {
      next = next.copyWith(clearColor: true, clearThemeColorIndex: true);
    } else if (parsed != null) {
      next = next.withSolidColor(parsed);
    }
    style = next;
  } else if (parsed != null) {
    style = VsdxCharStyle(
      fontSizeInches: fontSize,
      style: fontStyle,
      underline: underline ?? false,
      strikethrough: strikethrough ?? false,
      doubleUnderline: doubleUnderline ?? false,
      doubleStrikethrough: doubleStrikethrough ?? false,
      overline: overline ?? false,
      fontFamily: fontFamily,
      letterSpacingInches: letterSpacingInches ?? 0.0,
      transparency: textTransparency ?? 0.0,
      textCase: textCase ?? VsdxTextCase.normal,
      position: textPosition ?? VsdxTextPosition.normal,
      fontScale: fontScale ?? 1.0,
      langId: langId,
      asianFont: asianFont,
      complexScriptFont: complexScriptFont,
      complexScriptSizeInches: complexScriptSizeInches,
    ).withSolidColor(parsed);
  } else if (clearColor) {
    style = VsdxCharStyle(
      fontSizeInches: fontSize,
      style: fontStyle,
      underline: underline ?? false,
      strikethrough: strikethrough ?? false,
      doubleUnderline: doubleUnderline ?? false,
      doubleStrikethrough: doubleStrikethrough ?? false,
      overline: overline ?? false,
      fontFamily: fontFamily,
      letterSpacingInches: letterSpacingInches ?? 0.0,
      transparency: textTransparency ?? 0.0,
      textCase: textCase ?? VsdxTextCase.normal,
      position: textPosition ?? VsdxTextPosition.normal,
      fontScale: fontScale ?? 1.0,
      langId: langId,
      asianFont: asianFont,
      complexScriptFont: complexScriptFont,
      complexScriptSizeInches: complexScriptSizeInches,
    );
  } else {
    style = VsdxCharStyle(
      fontSizeInches: fontSize,
      color: kInk,
      style: fontStyle,
      underline: underline ?? false,
      strikethrough: strikethrough ?? false,
      doubleUnderline: doubleUnderline ?? false,
      doubleStrikethrough: doubleStrikethrough ?? false,
      overline: overline ?? false,
      fontFamily: fontFamily,
      letterSpacingInches: letterSpacingInches ?? 0.0,
      transparency: textTransparency ?? 0.0,
      textCase: textCase ?? VsdxTextCase.normal,
      position: textPosition ?? VsdxTextPosition.normal,
      fontScale: fontScale ?? 1.0,
      langId: langId,
      asianFont: asianFont,
      complexScriptFont: complexScriptFont,
      complexScriptSizeInches: complexScriptSizeInches,
    );
  }
  final prevRun =
      s.richText.runs.isNotEmpty ? s.richText.runs.first : null;
  return s.copyWith(
    text: text,
    // Plain label rewrite drops field spans — also drop Field rows so the
    // writer cannot leave an orphan `<Section N="Field">` without `<fld>`.
    // Style-only edits (same text) keep Field / fieldSpans intact.
    fields: textChanged ? const <VsdxFieldRow>[] : null,
    richText: s.richText.copyWith(
      runs: <VsdxTextRun>[
        VsdxTextRun(
          text: text,
          charStyle: style,
          paraStyle: prevRun?.paraStyle ?? VsdxParaStyle.defaults,
          fieldSpans: textChanged
              ? const <VsdxFieldSpan>[]
              : (prevRun?.fieldSpans ?? const []),
          tabIndices: textChanged
              ? const <int>[]
              : (prevRun?.tabIndices ?? const []),
        ),
      ],
    ),
  );
}

/// Apply character style without wiping Character when the label is empty.
///
/// Masters often have Character runs with no `<Text>` / empty [VsdxShape.text].
/// [withLabel] would clear richText on `""`; this keeps / injects style runs.
VsdxShape applyCharStyle(
  VsdxShape s, {
  bool? bold,
  bool? italic,
  bool? underline,
  bool? strikethrough,
  bool? doubleUnderline,
  bool? doubleStrikethrough,
  bool? overline,
  bool? smallCaps,
  String? colorHex,
  double? pt,
  String? fontFamily,
  double? letterSpacingInches,
  double? textTransparency,
  VsdxTextCase? textCase,
  VsdxTextPosition? textPosition,
  double? fontScale,
  String? langId,
  String? asianFont,
  String? complexScriptFont,
  double? complexScriptSizeInches,
}) {
  final fromText = s.text;
  final plain = (fromText != null && fromText.isNotEmpty)
      ? fromText
      : (s.richText.plainText.isNotEmpty ? s.richText.plainText : null);
  if (plain != null) {
    return withLabel(
      s,
      plain,
      bold: bold,
      italic: italic,
      underline: underline,
      strikethrough: strikethrough,
      doubleUnderline: doubleUnderline,
      doubleStrikethrough: doubleStrikethrough,
      overline: overline,
      smallCaps: smallCaps,
      colorHex: colorHex,
      pt: pt,
      fontFamily: fontFamily,
      letterSpacingInches: letterSpacingInches,
      textTransparency: textTransparency,
      textCase: textCase,
      textPosition: textPosition,
      fontScale: fontScale,
      langId: langId,
      asianFont: asianFont,
      complexScriptFont: complexScriptFont,
      complexScriptSizeInches: complexScriptSizeInches,
    );
  }
  VsdxCharStyle merge(VsdxCharStyle prev) {
    final clearColor =
        colorHex != null && colorHex.trim().toLowerCase() == 'none';
    final parsed = clearColor ? null : parseColorOrNull(colorHex);
    final fontSize =
        pt != null ? pt / 72.0 : prev.fontSizeInches;
    final fontStyle = prev.style.copyWith(
      bold: bold ?? prev.style.bold,
      italic: italic ?? prev.style.italic,
      smallCaps: smallCaps ?? prev.style.smallCaps,
    );
    var next = prev.copyWith(
      fontSizeInches: fontSize,
      style: fontStyle,
      underline: underline ?? prev.underline,
      strikethrough: strikethrough ?? prev.strikethrough,
      doubleUnderline: doubleUnderline ?? prev.doubleUnderline,
      doubleStrikethrough:
          doubleStrikethrough ?? prev.doubleStrikethrough,
      overline: overline ?? prev.overline,
      fontFamily: fontFamily ?? prev.fontFamily,
      letterSpacingInches:
          letterSpacingInches ?? prev.letterSpacingInches,
      transparency: textTransparency ?? prev.transparency,
      textCase: textCase ?? prev.textCase,
      position: textPosition ?? prev.position,
      fontScale: fontScale ?? prev.fontScale,
      langId: langId ?? prev.langId,
      asianFont: asianFont ?? prev.asianFont,
      complexScriptFont: complexScriptFont ?? prev.complexScriptFont,
      complexScriptSizeInches:
          complexScriptSizeInches ?? prev.complexScriptSizeInches,
    );
    if (clearColor) {
      next = next.copyWith(clearColor: true, clearThemeColorIndex: true);
    } else if (parsed != null) {
      next = next.withSolidColor(parsed);
    }
    return next;
  }

  final runs = s.richText.runs;
  if (runs.isNotEmpty) {
    return s.copyWith(
      richText: s.richText.copyWith(
        runs: [
          for (final r in runs) r.copyWith(charStyle: merge(r.charStyle)),
        ],
      ),
    );
  }
  return s.copyWith(
    richText: VsdxRichText(runs: [
      VsdxTextRun(
        text: '',
        charStyle: merge(VsdxCharStyle.defaults),
      ),
    ]),
  );
}

/// Build a glued connector shape from [a] to [b] plus its page-level
/// `<Connect>` rows. Endpoints start on the pins; `rerouteConnectors()` snaps
/// them to the shape outlines. Matches the editor's `createConnector`.
({VsdxShape connector, List<VsdxConnect> connects}) buildConnector({
  required int id,
  required VsdxShape a,
  required VsdxShape b,
  VsdxPage? page,
  String? label,
  String? lineHex,
  bool arrow = true,
}) {
  // Prefer page pins when [page] is provided so nested group members glue
  // correctly (stored pinX is parent-local). DiagramSpec builds off-page.
  final ap = page != null && page.findShapeById(a.id) != null
      ? page.shapePinPage(a.id)
      : Offset2D(a.pinX, a.pinY);
  final bp = page != null && page.findShapeById(b.id) != null
      ? page.shapePinPage(b.id)
      : Offset2D(b.pinX, b.pinY);
  final hideLine = lineHex != null && lineHex.trim().toLowerCase() == 'none';
  final base = VsdxShapeFactory.line(
    id: id,
    ax: ap.x,
    ay: ap.y,
    bx: bp.x,
    by: bp.y,
    // Honour line:"none" like add_shape / set_style (pattern=0).
    line: VsdxLine(
      color: parseColorOrNull(lineHex) ?? kDefaultEdgeLine,
      weightInches: 0.012,
      pattern: hideLine ? 0 : 1,
      endArrow: arrow ? 4 : 0,
    ),
  ).copyWith(
    formulas: <String, String>{
      'BegTrigger': '_XFTRIGGER(Sheet.${a.id}!EventXFMod)',
      'EndTrigger': '_XFTRIGGER(Sheet.${b.id}!EventXFMod)',
      'PinX': '(BeginX+EndX)*0.5',
      'PinY': '(BeginY+EndY)*0.5',
      'Width': 'EndX-BeginX',
      'Height': 'EndY-BeginY',
      'LocPinX': '(EndX-BeginX)/2',
      'LocPinY': '(EndY-BeginY)/2',
    },
    connectorProps: const VsdxConnectorProps(
      glueType: 2,
      conFixedCode: 3,
      dynFeedback: 2,
      noLiveDynamics: true,
      conLineRouteExt: 1,
      shapeRouteStyle: 16,
      begTrigger: '2',
      endTrigger: '2',
    ),
  );
  final connector = syncNoneGeometryFlags(
    (label != null && label.isNotEmpty) ? withLabel(base, label, pt: 10) : base,
  );
  final connects = <VsdxConnect>[
    VsdxConnect(
      fromSheetId: id,
      fromCell: 'BeginX',
      fromPart: 9,
      toSheetId: a.id,
      toCell: 'PinX',
      toPart: 3,
    ),
    VsdxConnect(
      fromSheetId: id,
      fromCell: 'EndX',
      fromPart: 12,
      toSheetId: b.id,
      toCell: 'PinX',
      toPart: 3,
    ),
  ];
  return (connector: connector, connects: connects);
}
