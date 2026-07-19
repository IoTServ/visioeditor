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

/// Attach a single-run label to [s] (plain text cache + styled rich run).
///
/// When [bold] / [colorHex] / [pt] are omitted, an existing first-run style is
/// preserved so `set_text` does not wipe bold / colour / size.
VsdxShape withLabel(
  VsdxShape s,
  String text, {
  bool? bold,
  String? colorHex,
  double? pt,
}) {
  if (text.isEmpty) {
    // Clear label (set_text "" must round-trip as empty, not no-op).
    return s.copyWith(text: '', richText: VsdxRichText.empty);
  }
  final prev =
      s.richText.runs.isNotEmpty ? s.richText.runs.first.charStyle : null;
  final color = parseColorOrNull(colorHex) ?? prev?.color ?? kInk;
  final fontSize = pt != null
      ? pt / 72.0
      : (prev?.fontSizeInches ?? 11 / 72.0);
  final fontStyle = bold == true
      ? VsdxFontStyle.boldStyle
      : bold == false
          ? VsdxFontStyle.regular
          : (prev?.style ?? VsdxFontStyle.regular);
  final style = (prev ??
          VsdxCharStyle(
            fontSizeInches: fontSize,
            color: color,
            style: fontStyle,
          ))
      .copyWith(
        fontSizeInches: fontSize,
        color: color,
        style: fontStyle,
      );
  return s.copyWith(
    text: text,
    richText: VsdxRichText(runs: <VsdxTextRun>[
      VsdxTextRun(
        text: text,
        charStyle: style,
        paraStyle: s.richText.runs.isNotEmpty
            ? s.richText.runs.first.paraStyle
            : VsdxParaStyle.defaults,
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
  final base = VsdxShapeFactory.line(
    id: id,
    ax: ap.x,
    ay: ap.y,
    bx: bp.x,
    by: bp.y,
    line: VsdxLine(
      color: parseColorOrNull(lineHex) ?? kDefaultEdgeLine,
      weightInches: 0.012,
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
  final connector =
      (label != null && label.isNotEmpty) ? withLabel(base, label, pt: 10) : base;
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
