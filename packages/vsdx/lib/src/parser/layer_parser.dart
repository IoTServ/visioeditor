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
        // Name: keep cached V= when F=Inh so equal-path sync does not rewrite
        // a Visio-cached layer name as the synthetic Layer-$id fallback.
        final name = _cellStringCached(row, 'Name') ?? 'Layer-$id';
        out.add(VsdxLayer(
          id: id,
          name: name,
          visible: (_cellInt(row, 'Visible') ?? 1) != 0,
          print: (_cellInt(row, 'Print') ?? 1) != 0,
          active: (_cellInt(row, 'Active') ?? 0) != 0,
          locked: (_cellInt(row, 'Lock') ?? 0) != 0,
          snap: (_cellInt(row, 'Snap') ?? 1) != 0,
          glue: (_cellInt(row, 'Glue') ?? 1) != 0,
          color: VsdxColor.tryParse(_cellString(row, 'Color')),
          // ColorTrans / Status: keep cached V= even when F=Inh so a non-zero
          // transparency / status is not forced to the Visio default 0.
          colorTrans: _cellDoubleCached(row, 'ColorTrans') ?? 0,
          nameUniv: _cellString(row, 'NameUniv'),
          status: _cellIntCached(row, 'Status') ?? 0,
        ));
      }
    }
    return List.unmodifiable(out);
  }

  /// Parse a shape's `LayerMember` cell into a list of layer ids.
  ///
  /// Returns `null` when the cell is absent (inherit Master / prototype).
  /// Returns an empty list when the cell is present with an empty `V`
  /// (explicitly cleared membership).
  static List<int>? parseLayerMembersOrNull(XmlElement shape) {
    final cell = findCell(shape, 'LayerMember');
    if (cell == null) return null;
    // F=Inh → inherit Master / prototype (same as a missing cell).
    if (isInhFormula(cell.getAttribute('F'))) return null;
    final v = cell.getAttribute('V');
    if (v == null || v.isEmpty) return const <int>[];
    final ids = <int>[];
    for (final t in v.split(';')) {
      final n = int.tryParse(t.trim());
      if (n != null) ids.add(n);
    }
    return List.unmodifiable(ids);
  }

  /// Parse a shape's `LayerMember` cell into a list of layer ids. The cell
  /// value is a semicolon-separated string ("0;3;5") or absent.
  ///
  /// Absent and empty both yield `[]` — prefer [parseLayerMembersOrNull]
  /// when Master inheritance must be distinguished from an explicit clear.
  static List<int> parseLayerMembers(XmlElement shape) =>
      parseLayerMembersOrNull(shape) ?? const <int>[];

  String? _cellString(XmlElement parent, String name) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    // F=Inh → treat as absent (use Visio defaults), same as LayerMember.
    if (isInhFormula(cell.getAttribute('F'))) return null;
    final v = cell.getAttribute('V');
    if (v == null || v.isEmpty) return null;
    return v;
  }

  int? _cellInt(XmlElement parent, String name) {
    final s = _cellString(parent, name);
    if (s == null) return null;
    return int.tryParse(s) ?? double.tryParse(s)?.toInt();
  }

  double? _cellDouble(XmlElement parent, String name) {
    final s = _cellString(parent, name);
    if (s == null) return null;
    return double.tryParse(s);
  }

  /// Read `V=` even when `F=Inh` (cached value Visio still stores).
  String? _cellStringCached(XmlElement parent, String name) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    final v = cell.getAttribute('V');
    if (v == null || v.isEmpty) return null;
    return v;
  }

  int? _cellIntCached(XmlElement parent, String name) {
    final s = _cellStringCached(parent, name);
    if (s == null) return null;
    return int.tryParse(s) ?? double.tryParse(s)?.toInt();
  }

  double? _cellDoubleCached(XmlElement parent, String name) {
    final s = _cellStringCached(parent, name);
    if (s == null) return null;
    return double.tryParse(s);
  }
}
