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
    this.prompt,
    this.format,
    this.type = 0,
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

  /// Best-effort textual rendering for inspector chips / search hits.
  String get displayLabel => label?.trim().isNotEmpty == true ? label! : name;
  String get displayValue => value ?? '';

  /// Functional update. As with [VsdxShape.copyWith], omitted nullable fields
  /// keep their current value (they can't be reset to `null` via `copyWith`).
  VsdxUserProperty copyWith({
    String? name,
    String? label,
    String? value,
    String? prompt,
    String? format,
    int? type,
  }) {
    return VsdxUserProperty(
      name: name ?? this.name,
      label: label ?? this.label,
      value: value ?? this.value,
      prompt: prompt ?? this.prompt,
      format: format ?? this.format,
      type: type ?? this.type,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VsdxUserProperty &&
      other.name == name &&
      other.label == label &&
      other.value == value &&
      other.prompt == prompt &&
      other.format == format &&
      other.type == type;

  @override
  int get hashCode => Object.hash(name, label, value, prompt, format, type);

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
    this.prompt,
  });

  final String name;
  final String? value;
  final String? prompt;

  @override
  String toString() => 'VsdxUserCell($name=$value)';
}
