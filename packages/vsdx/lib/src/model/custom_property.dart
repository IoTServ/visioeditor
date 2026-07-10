/// Document-level custom property from `docProps/custom.xml`.
library;

import 'package:meta/meta.dart';

@immutable
class VsdxCustomProperty {
  const VsdxCustomProperty({
    required this.name,
    required this.value,
    this.valueType,
    this.propertyId,
  });

  /// `name` attribute on `<property>`.
  final String name;

  /// Text content of the nested `vt:*` value element.
  final String value;

  /// Local name of the value element (e.g. `lpwstr`, `i4`, `bool`).
  final String? valueType;

  /// `pid` attribute when present.
  final int? propertyId;

  @override
  String toString() =>
      'VsdxCustomProperty(name: $name, value: $value, type: $valueType)';
}
