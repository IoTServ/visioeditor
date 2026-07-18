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
VsdxShape withLabel(
  VsdxShape s,
  String text, {
  bool bold = false,
  String? colorHex,
  double pt = 11,
}) {
  if (text.isEmpty) return s;
  final color = parseColorOrNull(colorHex) ?? kInk;
  final style = VsdxCharStyle(
    fontSizeInches: pt / 72.0,
    color: color,
    style: bold ? VsdxFontStyle.boldStyle : VsdxFontStyle.regular,
  );
  return s.copyWith(
    text: text,
    richText: VsdxRichText(runs: <VsdxTextRun>[
      VsdxTextRun(text: text, charStyle: style),
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
  String? label,
  String? lineHex,
  bool arrow = true,
}) {
  final base = VsdxShapeFactory.line(
    id: id,
    ax: a.pinX,
    ay: a.pinY,
    bx: b.pinX,
    by: b.pinY,
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
