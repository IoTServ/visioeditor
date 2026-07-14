/// Parse `<Section N="Property">` and `<Section N="User">` blocks into
/// the [VsdxUserProperty] / [VsdxUserCell] models.
///
/// Both sections share a `<Row N="..." IX="...">` child structure but
/// differ in which cells they carry:
///
/// ```xml
/// <Section N="Property">
///   <Row N="Cost" IX="1">
///     <Cell N="Label" V="Estimated cost"/>
///     <Cell N="Value" V="42.5" U="STR"/>
///     <Cell N="Format" V="# ##0.00"/>
///     <Cell N="Type" V="2"/>
///   </Row>
/// </Section>
/// ```
library;

import 'package:xml/xml.dart';

import '../model/user_property.dart';

class UserPropertyParser {
  const UserPropertyParser();

  /// Returns every `<Row>` of `<Section N="Property">` parsed into a
  /// [VsdxUserProperty]. Empty list when no Property section exists.
  List<VsdxUserProperty> parseProperties(XmlElement shape) {
    final out = <VsdxUserProperty>[];
    for (final section in shape.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Property') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final name = row.getAttribute('N') ??
            'Row${row.getAttribute('IX') ?? ''}';
        out.add(VsdxUserProperty(
          name: name,
          label: _cellString(row, 'Label'),
          value: _cellString(row, 'Value'),
          valueFormula: _formula(row, 'Value'),
          prompt: _cellString(row, 'Prompt'),
          format: _cellString(row, 'Format'),
          type: _cellInt(row, 'Type') ?? 0,
          sortKey: _cellString(row, 'SortKey'),
          invisible: (_cellInt(row, 'Invisible') ?? 0) != 0,
          verify: (_cellInt(row, 'Verify') ?? 0) != 0,
          ask: (_cellInt(row, 'Ask') ?? 0) != 0,
          dataLinked: (_cellInt(row, 'DataLinked') ?? 0) != 0,
          langId: _cellString(row, 'LangID'),
          calendar: _cellInt(row, 'Calendar'),
        ));
      }
    }
    return List.unmodifiable(out);
  }

  /// Returns every `<Row>` of `<Section N="User">` parsed into a
  /// [VsdxUserCell]. Empty list when no User section exists.
  List<VsdxUserCell> parseUserCells(XmlElement shape) {
    final out = <VsdxUserCell>[];
    for (final section in shape.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'User') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final name = row.getAttribute('N') ??
            'Row${row.getAttribute('IX') ?? ''}';
        out.add(VsdxUserCell(
          name: name,
          value: _cellString(row, 'Value'),
          valueFormula: _formula(row, 'Value'),
          prompt: _cellString(row, 'Prompt'),
        ));
      }
    }
    return List.unmodifiable(out);
  }

  String? _cellString(XmlElement row, String name) {
    for (final el in row.childElements) {
      if (el.name.local != 'Cell') continue;
      if (el.getAttribute('N') != name) continue;
      final v = el.getAttribute('V');
      if (v == null || v.isEmpty) return null;
      return v;
    }
    return null;
  }

  int? _cellInt(XmlElement row, String name) {
    final s = _cellString(row, name);
    if (s == null) return null;
    return int.tryParse(s) ?? double.tryParse(s)?.toInt();
  }

  static String? _formula(XmlElement parent, String name) {
    for (final el in parent.childElements) {
      if (el.name.local != 'Cell') continue;
      if (el.getAttribute('N') != name) continue;
      final f = el.getAttribute('F');
      if (f == null || f.isEmpty || f == 'No Formula') return null;
      return f;
    }
    return null;
  }
}
