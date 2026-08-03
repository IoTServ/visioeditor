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
  const LayerParser({
    this.colorPalette = const <int, VsdxColor>{},
  });

  final Map<int, VsdxColor> colorPalette;

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
        // libvisio reads Layer row cells directly from V= without inspecting
        // F=. Keep every cached value when F=Inh so parsing and equal-path
        // synthesis preserve the same layer behavior.
        final name = _cellStringCached(row, 'Name') ?? 'Layer-$id';
        out.add(VsdxLayer(
          id: id,
          name: name,
          visible: _cellBoolCached(row, 'Visible') ?? true,
          print: _cellBoolCached(row, 'Print') ?? true,
          active: _cellBoolCached(row, 'Active') ?? false,
          locked: _cellBoolCached(row, 'Lock') ?? false,
          snap: _cellBoolCached(row, 'Snap') ?? true,
          glue: _cellBoolCached(row, 'Glue') ?? true,
          color: VsdxColor.tryParse(
            _cellStringCached(row, 'Color'),
            palette: colorPalette,
          ),
          colorTrans: _cellDoubleCached(row, 'ColorTrans') ?? 0,
          nameUniv: _cellStringCached(row, 'NameUniv'),
          status: _cellIntCached(row, 'Status') ?? 0,
        ));
      }
    }
    return List.unmodifiable(out);
  }

  /// Parse a shape's `LayerMember` cell into a list of layer ids.
  ///
  /// Returns `null` when the cell is absent (no page-local membership).
  /// Returns an empty list when the cell is present with an empty `V`
  /// (explicitly cleared membership).
  static List<int>? parseLayerMembersOrNull(XmlElement shape) {
    final cell = findCell(shape, 'LayerMember');
    if (cell == null) return null;
    // libvisio reads the cached V= for LayerMember even when F="Inh".
    // Unlike ordinary ShapeSheet cells, membership is never copied from the
    // Master prototype when the cell is absent.
    final v = cell.getAttribute('V');
    if (v == null || v.isEmpty) return const <int>[];
    final ids = <int>[];
    for (final t in v.split(';')) {
      final n = int.tryParse(t.trim());
      // libvisio parses the complete value as `int % ';'`: one malformed or
      // empty item invalidates the entire membership instead of preserving a
      // misleading subset.
      if (n == null) return const <int>[];
      ids.add(n);
    }
    return List.unmodifiable(ids);
  }

  /// Parse a shape's `LayerMember` cell into a list of layer ids. The cell
  /// value is a semicolon-separated string ("0;3;5") or absent.
  ///
  /// Absent and empty both yield `[]` — prefer [parseLayerMembersOrNull]
  /// when source-cell absence must be distinguished from an explicit clear.
  static List<int> parseLayerMembers(XmlElement shape) =>
      parseLayerMembersOrNull(shape) ?? const <int>[];

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

  bool? _cellBoolCached(XmlElement parent, String name) =>
      parseVisioBool(_cellStringCached(parent, name));

  double? _cellDoubleCached(XmlElement parent, String name) {
    final s = _cellStringCached(parent, name);
    if (s == null) return null;
    return double.tryParse(s);
  }
}
