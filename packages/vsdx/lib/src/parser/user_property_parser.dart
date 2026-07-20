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
import 'cell_helpers.dart';

class UserPropertyParser {
  const UserPropertyParser();

  /// Returns every `<Row>` of `<Section N="Property">` parsed into a
  /// [VsdxUserProperty]. Empty list when no Property section exists.
  ///
  /// When [inherit] is supplied, same-named rows merge `F=Inh` cells from
  /// the master property.
  List<VsdxUserProperty> parseProperties(
    XmlElement shape, {
    List<VsdxUserProperty>? inherit,
  }) {
    final byName = <String, VsdxUserProperty>{
      if (inherit != null)
        for (final p in inherit) p.name: p,
    };
    final out = <VsdxUserProperty>[];
    for (final section in shape.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Property') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final name = row.getAttribute('N') ??
            'Row${row.getAttribute('IX') ?? ''}';
        final proto = byName[name];
        out.add(VsdxUserProperty(
          name: name,
          label: _cellString(row, 'Label', inheritFrom: proto?.label),
          value: _cellString(row, 'Value', inheritFrom: proto?.value),
          valueFormula: _formulaOrInherit(row, 'Value', proto?.valueFormula),
          prompt: _cellString(row, 'Prompt', inheritFrom: proto?.prompt),
          format: _cellString(row, 'Format', inheritFrom: proto?.format),
          type: _cellInt(row, 'Type', inheritFrom: proto?.type) ??
              proto?.type ??
              0,
          sortKey: _cellString(row, 'SortKey', inheritFrom: proto?.sortKey),
          invisible: (_cellInt(row, 'Invisible',
                      inheritFrom:
                          proto == null ? null : (proto.invisible ? 1 : 0)) ??
                  (proto?.invisible == true ? 1 : 0)) !=
              0,
          verify: (_cellInt(row, 'Verify',
                      inheritFrom:
                          proto == null ? null : (proto.verify ? 1 : 0)) ??
                  (proto?.verify == true ? 1 : 0)) !=
              0,
          ask: (_cellInt(row, 'Ask',
                      inheritFrom: proto == null ? null : (proto.ask ? 1 : 0)) ??
                  (proto?.ask == true ? 1 : 0)) !=
              0,
          dataLinked: (_cellInt(row, 'DataLinked',
                      inheritFrom:
                          proto == null ? null : (proto.dataLinked ? 1 : 0)) ??
                  (proto?.dataLinked == true ? 1 : 0)) !=
              0,
          langId: _cellString(row, 'LangID', inheritFrom: proto?.langId),
          calendar: _cellInt(row, 'Calendar', inheritFrom: proto?.calendar) ??
              proto?.calendar,
        ));
      }
    }
    return List.unmodifiable(out);
  }

  /// Returns every `<Row>` of `<Section N="User">` parsed into a
  /// [VsdxUserCell]. Empty list when no User section exists.
  List<VsdxUserCell> parseUserCells(
    XmlElement shape, {
    List<VsdxUserCell>? inherit,
  }) {
    final byName = <String, VsdxUserCell>{
      if (inherit != null)
        for (final c in inherit) c.name: c,
    };
    final out = <VsdxUserCell>[];
    for (final section in shape.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'User') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final name = row.getAttribute('N') ??
            'Row${row.getAttribute('IX') ?? ''}';
        final proto = byName[name];
        out.add(VsdxUserCell(
          name: name,
          value: _cellString(row, 'Value', inheritFrom: proto?.value),
          valueFormula: _formulaOrInherit(row, 'Value', proto?.valueFormula),
          prompt: _cellString(row, 'Prompt', inheritFrom: proto?.prompt),
        ));
      }
    }
    return List.unmodifiable(out);
  }

  String? _cellString(XmlElement row, String name, {String? inheritFrom}) {
    for (final el in row.childElements) {
      if (el.name.local != 'Cell') continue;
      if (el.getAttribute('N') != name) continue;
      if (isInhFormula(el.getAttribute('F'))) return inheritFrom;
      final v = el.getAttribute('V');
      if (v == null || v.isEmpty) return null;
      return v;
    }
    return inheritFrom;
  }

  int? _cellInt(XmlElement row, String name, {int? inheritFrom}) {
    for (final el in row.childElements) {
      if (el.name.local != 'Cell') continue;
      if (el.getAttribute('N') != name) continue;
      if (isInhFormula(el.getAttribute('F')) && inheritFrom != null) {
        return inheritFrom;
      }
      final v = el.getAttribute('V');
      if (v == null || v.isEmpty) return null;
      return int.tryParse(v) ?? double.tryParse(v)?.toInt();
    }
    return null;
  }

  static String? _formulaOrInherit(
    XmlElement parent,
    String name,
    String? inherit,
  ) {
    final f = _formula(parent, name);
    if (f == null) return inherit;
    if (isInhFormula(f)) return inherit;
    return f;
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
