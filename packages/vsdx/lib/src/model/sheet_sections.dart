/// Visio ShapeSheet rows that parametric geometry and text handles depend on.
///
///   * `<Section N="Control">` — interactive handles (`Controls.TextPosition`,
///     …). libvisio / Visio often wire `TxtPinX` via `SETATREF(Controls.…)`.
///   * `<Section N="Scratch">` — intermediate formula cells referenced by
///     Geometry (`F="Scratch.X1"`, `MIN(Height/2,Width/2)`, …).
///   * `<Section N="Field">` — dynamic text fields referenced by
///     `<fld IX="n"/>` in the `<Text>` stream.
library;

import 'package:meta/meta.dart';

/// One named Control row (`Row N="TextPosition"`).
///
/// Visio/MS-VSDX uses cell names `XDyn`/`YDyn`/`XCon`/`YCon`; some Lucidchart
/// exports use the aliases `DynX`/`DynY`/`ConX`/`ConY`. The model stores one
/// set of values; [useVisioDynNames] selects which names the writer emits.
@immutable
class VsdxControlRow {
  const VsdxControlRow({
    required this.name,
    this.x = 0,
    this.y = 0,
    this.conX = 0,
    this.conY = 0,
    this.dynX = 0,
    this.dynY = 0,
    this.xFormula,
    this.yFormula,
    this.dynXFormula,
    this.dynYFormula,
    this.conXFormula,
    this.conYFormula,
    this.canGlue = false,
    this.prompt,
    this.useVisioDynNames = true,
  });

  /// `Row N=` — e.g. `TextPosition`.
  final String name;

  final double x;
  final double y;
  final double conX;
  final double conY;
  final double dynX;
  final double dynY;

  /// Optional `F=` on X/Y/Dyn*/Con* (kept so SETATREF / self-refs survive).
  final String? xFormula;
  final String? yFormula;
  final String? dynXFormula;
  final String? dynYFormula;
  final String? conXFormula;
  final String? conYFormula;

  /// `CanGlue` — whether the handle participates in glue.
  final bool canGlue;

  final String? prompt;

  /// When true, write `XDyn`/`YDyn`/`XCon`/`YCon` (Visio); else Lucidchart
  /// aliases `DynX`/`DynY`/`ConX`/`ConY`.
  final bool useVisioDynNames;

  VsdxControlRow copyWith({
    String? name,
    double? x,
    double? y,
    double? conX,
    double? conY,
    double? dynX,
    double? dynY,
    String? xFormula,
    String? yFormula,
    String? dynXFormula,
    String? dynYFormula,
    String? conXFormula,
    String? conYFormula,
    bool? canGlue,
    String? prompt,
    bool? useVisioDynNames,
    bool clearPrompt = false,
  }) =>
      VsdxControlRow(
        name: name ?? this.name,
        x: x ?? this.x,
        y: y ?? this.y,
        conX: conX ?? this.conX,
        conY: conY ?? this.conY,
        dynX: dynX ?? this.dynX,
        dynY: dynY ?? this.dynY,
        xFormula: xFormula ?? this.xFormula,
        yFormula: yFormula ?? this.yFormula,
        dynXFormula: dynXFormula ?? this.dynXFormula,
        dynYFormula: dynYFormula ?? this.dynYFormula,
        conXFormula: conXFormula ?? this.conXFormula,
        conYFormula: conYFormula ?? this.conYFormula,
        canGlue: canGlue ?? this.canGlue,
        prompt: clearPrompt ? null : (prompt ?? this.prompt),
        useVisioDynNames: useVisioDynNames ?? this.useVisioDynNames,
      );

  @override
  bool operator ==(Object other) =>
      other is VsdxControlRow &&
      other.name == name &&
      other.x == x &&
      other.y == y &&
      other.conX == conX &&
      other.conY == conY &&
      other.dynX == dynX &&
      other.dynY == dynY &&
      other.xFormula == xFormula &&
      other.yFormula == yFormula &&
      other.dynXFormula == dynXFormula &&
      other.dynYFormula == dynYFormula &&
      other.conXFormula == conXFormula &&
      other.conYFormula == conYFormula &&
      other.canGlue == canGlue &&
      other.prompt == prompt &&
      other.useVisioDynNames == useVisioDynNames;

  @override
  int get hashCode => Object.hash(
        name,
        x,
        y,
        conX,
        conY,
        dynX,
        dynY,
        canGlue,
        prompt,
        useVisioDynNames,
      );
}

/// One Scratch row (`Row IX="0"`) with X/Y/A/B/C/D cells.
@immutable
class VsdxScratchRow {
  const VsdxScratchRow({
    required this.ix,
    this.x = 0,
    this.y = 0,
    this.a = 0,
    this.b = 0,
    this.c = 0,
    this.d = 0,
    this.xFormula,
    this.yFormula,
    this.aFormula,
    this.bFormula,
    this.cFormula,
    this.dFormula,
  });

  final int ix;
  final double x;
  final double y;
  final double a;
  final double b;
  final double c;
  final double d;
  final String? xFormula;
  final String? yFormula;
  final String? aFormula;
  final String? bFormula;
  final String? cFormula;
  final String? dFormula;

  VsdxScratchRow copyWith({
    int? ix,
    double? x,
    double? y,
    double? a,
    double? b,
    double? c,
    double? d,
    String? xFormula,
    String? yFormula,
    String? aFormula,
    String? bFormula,
    String? cFormula,
    String? dFormula,
  }) =>
      VsdxScratchRow(
        ix: ix ?? this.ix,
        x: x ?? this.x,
        y: y ?? this.y,
        a: a ?? this.a,
        b: b ?? this.b,
        c: c ?? this.c,
        d: d ?? this.d,
        xFormula: xFormula ?? this.xFormula,
        yFormula: yFormula ?? this.yFormula,
        aFormula: aFormula ?? this.aFormula,
        bFormula: bFormula ?? this.bFormula,
        cFormula: cFormula ?? this.cFormula,
        dFormula: dFormula ?? this.dFormula,
      );

  @override
  bool operator ==(Object other) =>
      other is VsdxScratchRow &&
      other.ix == ix &&
      other.x == x &&
      other.y == y &&
      other.a == a &&
      other.b == b &&
      other.c == c &&
      other.d == d &&
      other.xFormula == xFormula &&
      other.yFormula == yFormula &&
      other.aFormula == aFormula &&
      other.bFormula == bFormula &&
      other.cFormula == cFormula &&
      other.dFormula == dFormula;

  @override
  int get hashCode => Object.hash(
        ix,
        x,
        y,
        a,
        b,
        c,
        d,
        xFormula,
        yFormula,
        aFormula,
        bFormula,
        cFormula,
        dFormula,
      );
}

/// One row of `<Section N="Field">` — dynamic text fields referenced by
/// `<fld IX="n"/>` in the `<Text>` stream (Visio / MS-VSDX).
@immutable
class VsdxFieldRow {
  const VsdxFieldRow({
    required this.ix,
    this.value,
    this.valueFormula,
    this.format,
    this.formatFormula,
    this.type = 0,
    this.uiCat,
    this.uiCod,
    this.uiFmt,
    this.calendar,
    this.objectKind,
  });

  final int ix;
  final String? value;
  final String? valueFormula;
  final String? format;
  final String? formatFormula;
  final int type;
  final int? uiCat;
  final int? uiCod;
  final int? uiFmt;
  final int? calendar;
  final int? objectKind;

  /// Display string shown inside `<fld>` (cached `Value` cell).
  String get displayText => value ?? '';

  @override
  bool operator ==(Object other) =>
      other is VsdxFieldRow &&
      other.ix == ix &&
      other.value == value &&
      other.valueFormula == valueFormula &&
      other.format == format &&
      other.formatFormula == formatFormula &&
      other.type == type &&
      other.uiCat == uiCat &&
      other.uiCod == uiCod &&
      other.uiFmt == uiFmt &&
      other.calendar == calendar &&
      other.objectKind == objectKind;

  @override
  int get hashCode => Object.hash(ix, value, valueFormula, format, type);
}

/// Connector / layout dynamics cells (BegTrigger, GlueType, …).
///
/// Opaque cloning covers group rebuild of existing XML; this model keeps the
/// values for brand-new `_buildShapeElement` emission (libvisio round-trip).
@immutable
class VsdxConnectorProps {
  const VsdxConnectorProps({
    this.begTrigger,
    this.endTrigger,
    this.glueType,
    this.conFixedCode,
    this.dynFeedback,
    this.noLiveDynamics = false,
    this.conLineJumpCode,
    this.conLineRouteExt,
    this.conLineJumpStyle,
    this.conLineJumpDirX,
    this.conLineJumpDirY,
    this.shapeRouteStyle,
    this.shapePlaceFlip,
  });

  /// Cached `V=` for BegTrigger / EndTrigger (formula lives in [VsdxShape.formulas]).
  final String? begTrigger;
  final String? endTrigger;

  final int? glueType;
  final int? conFixedCode;
  final int? dynFeedback;
  final bool noLiveDynamics;
  final int? conLineJumpCode;

  /// `ConLineRouteExt` — extended connector routing style.
  final int? conLineRouteExt;

  /// `ConLineJumpStyle` / `ConLineJumpDirX` / `ConLineJumpDirY`.
  final int? conLineJumpStyle;
  final int? conLineJumpDirX;
  final int? conLineJumpDirY;

  final int? shapeRouteStyle;

  /// `ShapePlaceFlip` — placement flip behaviour for dynamic connectors.
  final int? shapePlaceFlip;

  bool get isEmpty =>
      begTrigger == null &&
      endTrigger == null &&
      glueType == null &&
      conFixedCode == null &&
      dynFeedback == null &&
      !noLiveDynamics &&
      conLineJumpCode == null &&
      conLineRouteExt == null &&
      conLineJumpStyle == null &&
      conLineJumpDirX == null &&
      conLineJumpDirY == null &&
      shapeRouteStyle == null &&
      shapePlaceFlip == null;

  VsdxConnectorProps copyWith({
    String? begTrigger,
    String? endTrigger,
    int? glueType,
    int? conFixedCode,
    int? dynFeedback,
    bool? noLiveDynamics,
    int? conLineJumpCode,
    int? conLineRouteExt,
    int? conLineJumpStyle,
    int? conLineJumpDirX,
    int? conLineJumpDirY,
    int? shapeRouteStyle,
    int? shapePlaceFlip,
  }) =>
      VsdxConnectorProps(
        begTrigger: begTrigger ?? this.begTrigger,
        endTrigger: endTrigger ?? this.endTrigger,
        glueType: glueType ?? this.glueType,
        conFixedCode: conFixedCode ?? this.conFixedCode,
        dynFeedback: dynFeedback ?? this.dynFeedback,
        noLiveDynamics: noLiveDynamics ?? this.noLiveDynamics,
        conLineJumpCode: conLineJumpCode ?? this.conLineJumpCode,
        conLineRouteExt: conLineRouteExt ?? this.conLineRouteExt,
        conLineJumpStyle: conLineJumpStyle ?? this.conLineJumpStyle,
        conLineJumpDirX: conLineJumpDirX ?? this.conLineJumpDirX,
        conLineJumpDirY: conLineJumpDirY ?? this.conLineJumpDirY,
        shapeRouteStyle: shapeRouteStyle ?? this.shapeRouteStyle,
        shapePlaceFlip: shapePlaceFlip ?? this.shapePlaceFlip,
      );

  @override
  bool operator ==(Object other) =>
      other is VsdxConnectorProps &&
      other.begTrigger == begTrigger &&
      other.endTrigger == endTrigger &&
      other.glueType == glueType &&
      other.conFixedCode == conFixedCode &&
      other.dynFeedback == dynFeedback &&
      other.noLiveDynamics == noLiveDynamics &&
      other.conLineJumpCode == conLineJumpCode &&
      other.conLineRouteExt == conLineRouteExt &&
      other.conLineJumpStyle == conLineJumpStyle &&
      other.conLineJumpDirX == conLineJumpDirX &&
      other.conLineJumpDirY == conLineJumpDirY &&
      other.shapeRouteStyle == shapeRouteStyle &&
      other.shapePlaceFlip == shapePlaceFlip;

  @override
  int get hashCode => Object.hash(
        begTrigger,
        endTrigger,
        glueType,
        conFixedCode,
        dynFeedback,
        noLiveDynamics,
        conLineJumpCode,
        conLineRouteExt,
        conLineJumpStyle,
        conLineJumpDirX,
        conLineJumpDirY,
        shapeRouteStyle,
        shapePlaceFlip,
      );
}

/// One row of `<Section N="Actions">` — shape context-menu / right-click
/// actions (MS-VSDX Action Row). Rare in fixtures but required for brand-new
/// rebuild fidelity once modeled.
@immutable
class VsdxActionRow {
  const VsdxActionRow({
    required this.name,
    this.ix = 0,
    this.menu,
    this.action,
    this.actionFormula,
    this.checked = false,
    this.disabled = false,
    this.readOnly = false,
    this.invisible = false,
    this.tag,
    this.buttonFace = 0,
    this.sortKey,
  });

  /// `Row N="..."` identifier.
  final String name;
  final int ix;

  /// `Menu` — display text (may include `&` accelerators).
  final String? menu;

  /// `Action` cached `V=` (formula often carries `RUNADDON` / `OPENFILE`).
  final String? action;
  final String? actionFormula;

  final bool checked;
  final bool disabled;
  final bool readOnly;
  final bool invisible;
  final String? tag;
  final int buttonFace;
  final String? sortKey;

  VsdxActionRow copyWith({
    String? name,
    int? ix,
    String? menu,
    String? action,
    String? actionFormula,
    bool? checked,
    bool? disabled,
    bool? readOnly,
    bool? invisible,
    String? tag,
    int? buttonFace,
    String? sortKey,
  }) =>
      VsdxActionRow(
        name: name ?? this.name,
        ix: ix ?? this.ix,
        menu: menu ?? this.menu,
        action: action ?? this.action,
        actionFormula: actionFormula ?? this.actionFormula,
        checked: checked ?? this.checked,
        disabled: disabled ?? this.disabled,
        readOnly: readOnly ?? this.readOnly,
        invisible: invisible ?? this.invisible,
        tag: tag ?? this.tag,
        buttonFace: buttonFace ?? this.buttonFace,
        sortKey: sortKey ?? this.sortKey,
      );

  @override
  bool operator ==(Object other) =>
      other is VsdxActionRow &&
      other.name == name &&
      other.ix == ix &&
      other.menu == menu &&
      other.action == action &&
      other.actionFormula == actionFormula &&
      other.checked == checked &&
      other.disabled == disabled &&
      other.readOnly == readOnly &&
      other.invisible == invisible &&
      other.tag == tag &&
      other.buttonFace == buttonFace &&
      other.sortKey == sortKey;

  @override
  int get hashCode => Object.hash(
        name,
        ix,
        menu,
        action,
        actionFormula,
        checked,
        disabled,
        readOnly,
        invisible,
        tag,
        buttonFace,
        sortKey,
      );
}
