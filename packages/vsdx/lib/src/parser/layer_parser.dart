/// Parse the `<Section N="Layer">` block on a PageSheet into [VsdxLayer]s.
///
/// MS-VSDX §"Layer Section":
///   * Each `<Row IX="N">` defines one layer.
///   * Cells: Name, Visible, Print, Active, Lock, Color, Snap, Glue,
///     NameUniv (we keep the user-facing `Name`).
library;

import 'package:xml/xml.dart';

import '../model/layer.dart';
import '../utils/color.dart';
import 'cell_helpers.dart';

class LayerParser {
  const LayerParser();

  /// Returns one [VsdxLayer] per `<Row>` of the `Layer` section. Returns an
  /// empty list when no Layer section is present.
  List<VsdxLayer> parseLayers(XmlElement pageSheet) {
    final out = <VsdxLayer>[];
    for (final section in pageSheet.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'Layer') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final idStr = row.getAttribute('IX') ?? row.getAttribute('N');
        final id = idStr == null ? null : int.tryParse(idStr);
        if (id == null) continue;
        final name = _cellString(row, 'Name') ?? 'Layer-$id';
        out.add(VsdxLayer(
          id: id,
          name: name,
          visible: (_cellInt(row, 'Visible') ?? 1) != 0,
          print: (_cellInt(row, 'Print') ?? 1) != 0,
          active: (_cellInt(row, 'Active') ?? 0) != 0,
          locked: (_cellInt(row, 'Lock') ?? 0) != 0,
          color: VsdxColor.tryParse(_cellString(row, 'Color')),
        ));
      }
    }
    return List.unmodifiable(out);
  }

  /// Parse a shape's `LayerMember` cell into a list of layer ids. The cell
  /// value is a semicolon-separated string ("0;3;5") or absent.
  static List<int> parseLayerMembers(XmlElement shape) {
    final cell = findCell(shape, 'LayerMember');
    if (cell == null) return const <int>[];
    final v = cell.getAttribute('V');
    if (v == null || v.isEmpty) return const <int>[];
    final ids = <int>[];
    for (final t in v.split(';')) {
      final n = int.tryParse(t.trim());
      if (n != null) ids.add(n);
    }
    return List.unmodifiable(ids);
  }

  String? _cellString(XmlElement parent, String name) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    final v = cell.getAttribute('V');
    if (v == null || v.isEmpty) return null;
    return v;
  }

  int? _cellInt(XmlElement parent, String name) {
    final s = _cellString(parent, name);
    if (s == null) return null;
    return int.tryParse(s) ?? double.tryParse(s)?.toInt();
  }
}
