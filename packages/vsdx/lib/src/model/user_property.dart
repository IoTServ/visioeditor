/// Visio user-defined / custom property entries.
///
/// Real `.vsdx` files store these in two related sections of the shape
/// sheet:
///
///   * `<Section N="User">` — programmer-facing scratch cells (`User.<Name>`),
///     usually carrying intermediate formula results.
///   * `<Section N="Property">` — end-user-facing custom properties (the
///     "Shape Data" pane in Visio). Each row describes one named field
///     with a Label / Value / Type / Format triple.
///
/// We expose them as immutable value-objects so the inspector panel and
/// search index can both consume the same model. Values are kept as the
/// raw `V=` string — callers that need a typed view can read [type] and
/// dispatch on Visio's numeric type code.
library;

import 'package:meta/meta.dart';

/// One row of a `<Section N="Property">` block.
@immutable
class VsdxUserProperty {
  const VsdxUserProperty({
    required this.name,
    this.label,
    this.value,
    this.valueFormula,
    this.prompt,
    this.format,
    this.type = 0,
    this.sortKey,
    this.invisible = false,
    this.verify = false,
    this.ask = false,
    this.dataLinked = false,
    this.langId,
    this.calendar,
  });

  /// `Row N="..."` — the property identifier (e.g. "Cost", "AssetTag").
  /// We sometimes see numeric `IX="N"` only; in that case the parser
  /// synthesises `Row${IX}`.
  final String name;

  /// `Label` cell — the user-facing label (e.g. "Estimated cost").
  /// May be `null`, in which case the inspector falls back to [name].
  final String? label;

  /// `Value` cell — the raw `V=` string. Numeric types remain as
  /// stringified numbers so the original precision is preserved.
  final String? value;

  /// `F=` on the Value cell (parametric Property.* / Scratch.* refs).
  final String? valueFormula;

  /// `Prompt` cell — tooltip text shown by Visio when editing the field.
  final String? prompt;

  /// `Format` cell — printf-ish picture string (e.g. `"# ##0.00"`,
  /// `"yyyy-mm-dd"`).
  final String? format;

  /// Visio property type code:
  ///
  /// | code | meaning           |
  /// |------|-------------------|
  /// | 0    | String (default)  |
  /// | 1    | Fixed-precision   |
  /// | 2    | Number            |
  /// | 5    | Boolean           |
  /// | 7    | Date              |
  /// | 8    | Duration          |
  /// | 4    | Currency          |
  /// | 3    | List              |
  ///
  /// We don't normalise — callers consult the code directly.
  final int type;

  /// `SortKey` — Shape Data pane ordering hint.
  final String? sortKey;

  /// `Invisible` — hide from Shape Data UI when true.
  final bool invisible;

  /// `Verify` — prompt on edit when true.
  final bool verify;

  /// `Ask` — prompt for a value when the shape is dropped (Visio).
  final bool ask;

  /// `DataLinked` — linked to external data when true.
  final bool dataLinked;

  /// `LangID` / `Calendar` — locale for typed values.
  final String? langId;
  final int? calendar;

  /// Best-effort textual rendering for inspector chips / search hits.
  String get displayLabel => label?.trim().isNotEmpty == true ? label! : name;
  String get displayValue => value ?? '';

  /// Functional update. As with [VsdxShape.copyWith], omitted nullable fields
  /// keep their current value (they can't be reset to `null` via `copyWith`).
  VsdxUserProperty copyWith({
    String? name,
    String? label,
    String? value,
    String? valueFormula,
    String? prompt,
    String? format,
    int? type,
    String? sortKey,
    bool? invisible,
    bool? verify,
    bool? ask,
    bool? dataLinked,
    String? langId,
    int? calendar,
  }) {
    return VsdxUserProperty(
      name: name ?? this.name,
      label: label ?? this.label,
      value: value ?? this.value,
      valueFormula: valueFormula ?? this.valueFormula,
      prompt: prompt ?? this.prompt,
      format: format ?? this.format,
      type: type ?? this.type,
      sortKey: sortKey ?? this.sortKey,
      invisible: invisible ?? this.invisible,
      verify: verify ?? this.verify,
      ask: ask ?? this.ask,
      dataLinked: dataLinked ?? this.dataLinked,
      langId: langId ?? this.langId,
      calendar: calendar ?? this.calendar,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VsdxUserProperty &&
      other.name == name &&
      other.label == label &&
      other.value == value &&
      other.valueFormula == valueFormula &&
      other.prompt == prompt &&
      other.format == format &&
      other.type == type &&
      other.sortKey == sortKey &&
      other.invisible == invisible &&
      other.verify == verify &&
      other.ask == ask &&
      other.dataLinked == dataLinked &&
      other.langId == langId &&
      other.calendar == calendar;

  @override
  int get hashCode => Object.hash(
        name,
        label,
        value,
        valueFormula,
        prompt,
        format,
        type,
        sortKey,
        invisible,
        verify,
        ask,
        dataLinked,
        langId,
        calendar,
      );

  @override
  String toString() =>
      'VsdxUserProperty($name${label == null ? '' : '/$label'}'
      '${value == null ? '' : '=$value'}, type=$type)';
}

/// One row of a `<Section N="User">` block (`User.<Name>`).
@immutable
class VsdxUserCell {
  const VsdxUserCell({
    required this.name,
    this.value,
    this.valueFormula,
    this.prompt,
  });

  final String name;
  final String? value;

  /// `F=` on the Value cell (parametric User.* references).
  final String? valueFormula;
  final String? prompt;

  VsdxUserCell copyWith({
    String? name,
    String? value,
    String? valueFormula,
    String? prompt,
  }) =>
      VsdxUserCell(
        name: name ?? this.name,
        value: value ?? this.value,
        valueFormula: valueFormula ?? this.valueFormula,
        prompt: prompt ?? this.prompt,
      );

  @override
  bool operator ==(Object other) =>
      other is VsdxUserCell &&
      other.name == name &&
      other.value == value &&
      other.valueFormula == valueFormula &&
      other.prompt == prompt;

  @override
  int get hashCode => Object.hash(name, value, valueFormula, prompt);

  @override
  String toString() => 'VsdxUserCell($name=$value)';
}
