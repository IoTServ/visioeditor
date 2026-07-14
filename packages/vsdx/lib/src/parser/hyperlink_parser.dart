/// Parse `<Section N="Hyperlink">` rows into [VsdxHyperlink]s.
library;

import 'package:xml/xml.dart';

import '../model/hyperlink.dart';
import 'cell_helpers.dart';

class HyperlinkParser {
  const HyperlinkParser();

  /// Returns one [VsdxHyperlink] per `<Row>` in the shape's Hyperlink
  /// section, or an empty list when no such section exists.
  List<VsdxHyperlink> parse(XmlElement shape) {
    final out = <VsdxHyperlink>[];
    for (final section in shape.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Hyperlink') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final ix = int.tryParse(row.getAttribute('IX') ?? '') ?? 0;
        out.add(VsdxHyperlink(
          id: ix,
          description: _str(row, 'Description'),
          address: _str(row, 'Address'),
          addressFormula: _formula(row, 'Address'),
          subAddress: _str(row, 'SubAddress'),
          extraInfo: _str(row, 'ExtraInfo'),
          frame: _str(row, 'Frame'),
          newWindow: (_int(row, 'NewWindow') ?? 0) != 0,
          isDefault: (_int(row, 'Default') ?? 0) != 0,
          invisible: (_int(row, 'Invisible') ?? 0) != 0,
          sortKey: _str(row, 'SortKey'),
        ));
      }
    }
    return List.unmodifiable(out);
  }

  String? _str(XmlElement parent, String name) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    final v = cell.getAttribute('V');
    if (v == null || v.isEmpty) return null;
    return v;
  }

  int? _int(XmlElement parent, String name) {
    final s = _str(parent, name);
    if (s == null) return null;
    return int.tryParse(s) ?? double.tryParse(s)?.toInt();
  }

  static String? _formula(XmlElement parent, String name) {
    final cell = findCell(parent, name);
    final f = cell?.getAttribute('F');
    if (f == null || f.isEmpty || f == 'No Formula') return null;
    return f;
  }
}
