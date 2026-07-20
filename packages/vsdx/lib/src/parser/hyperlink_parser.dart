/// Parse `<Section N="Hyperlink">` rows into [VsdxHyperlink]s.
library;

import 'package:xml/xml.dart';

import '../model/hyperlink.dart';
import 'cell_helpers.dart';

class HyperlinkParser {
  const HyperlinkParser();

  /// Returns one [VsdxHyperlink] per `<Row>` in the shape's Hyperlink
  /// section, or an empty list when no such section exists.
  ///
  /// When [inherit] is supplied, rows with the same IX merge `F=Inh` cells
  /// from the master hyperlink (same pattern as Actions / Scratch).
  List<VsdxHyperlink> parse(
    XmlElement shape, {
    List<VsdxHyperlink>? inherit,
  }) {
    final byId = <int, VsdxHyperlink>{
      if (inherit != null)
        for (final h in inherit) h.id: h,
    };
    final out = <VsdxHyperlink>[];
    for (final section in shape.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Hyperlink') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final ix = int.tryParse(row.getAttribute('IX') ?? '') ?? 0;
        final proto = byId[ix];
        out.add(VsdxHyperlink(
          id: ix,
          description: _str(row, 'Description', inheritFrom: proto?.description),
          address: _str(row, 'Address', inheritFrom: proto?.address),
          addressFormula: _formulaOrInherit(row, 'Address', proto?.addressFormula),
          subAddress: _str(row, 'SubAddress', inheritFrom: proto?.subAddress),
          extraInfo: _str(row, 'ExtraInfo', inheritFrom: proto?.extraInfo),
          frame: _str(row, 'Frame', inheritFrom: proto?.frame),
          newWindow: (_int(row, 'NewWindow',
                      inheritFrom:
                          proto == null ? null : (proto.newWindow ? 1 : 0)) ??
                  (proto?.newWindow == true ? 1 : 0)) !=
              0,
          isDefault: (_int(row, 'Default',
                      inheritFrom:
                          proto == null ? null : (proto.isDefault ? 1 : 0)) ??
                  (proto?.isDefault == true ? 1 : 0)) !=
              0,
          invisible: (_int(row, 'Invisible',
                      inheritFrom:
                          proto == null ? null : (proto.invisible ? 1 : 0)) ??
                  (proto?.invisible == true ? 1 : 0)) !=
              0,
          sortKey: _str(row, 'SortKey', inheritFrom: proto?.sortKey),
        ));
      }
    }
    return List.unmodifiable(out);
  }

  String? _str(XmlElement parent, String name, {String? inheritFrom}) {
    final cell = findCell(parent, name);
    if (cell == null) return inheritFrom;
    if (isInhFormula(cell.getAttribute('F'))) return inheritFrom;
    final v = cell.getAttribute('V');
    if (v == null || v.isEmpty) return null;
    return v;
  }

  int? _int(XmlElement parent, String name, {int? inheritFrom}) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    if (isInhFormula(cell.getAttribute('F')) && inheritFrom != null) {
      return inheritFrom;
    }
    final v = cell.getAttribute('V');
    if (v == null || v.isEmpty) return null;
    return int.tryParse(v) ?? double.tryParse(v)?.toInt();
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
    final cell = findCell(parent, name);
    final f = cell?.getAttribute('F');
    if (f == null || f.isEmpty || f == 'No Formula') return null;
    return f;
  }
}
