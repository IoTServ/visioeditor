/// Parse `<StyleSheet>` entries from `visio/document.xml` into a
/// [StyleSheetRegistry].
///
/// Visio shapes reference styles via `TextStyle` / `LineStyle` / `FillStyle`
/// attributes (or inherit them from a Master). libvisio walks the same chain
/// when a shape omits its own Character `Size` cell — without this, we fall
/// back to the hard-coded 12pt default and diverge from the oracle.
library;

import 'package:xml/xml.dart';

import '../model/fill.dart';
import '../model/line.dart';
import '../model/rich_text.dart';
import '../model/stylesheet.dart';
import '../utils/color.dart';
import 'cell_helpers.dart';

class StyleSheetParser {
  const StyleSheetParser();

  StyleSheetRegistry parse(
    XmlDocument documentXml, {
    int? defaultTextStyleId,
  }) {
    // Prefer the attribute on <DocumentSettings> when the caller didn't pass
    // one (DocumentSettingsParser historically ignored it).
    final settingsDefault = defaultTextStyleId ??
        _documentSettingsTextStyle(documentXml.rootElement);

    final byId = <int, VsdxStyleSheet>{};
    for (final el in documentXml.rootElement.childElements) {
      if (el.name.local != 'StyleSheets') continue;
      for (final ss in el.childElements) {
        if (ss.name.local != 'StyleSheet') continue;
        final sheet = _readSheet(ss);
        if (sheet != null) byId[sheet.id] = sheet;
      }
    }
    // Some writers put StyleSheet elements directly under VisioDocument.
    if (byId.isEmpty) {
      for (final ss in documentXml.rootElement.childElements) {
        if (ss.name.local != 'StyleSheet') continue;
        final sheet = _readSheet(ss);
        if (sheet != null) byId[sheet.id] = sheet;
      }
    }
    return StyleSheetRegistry(Map.unmodifiable(byId),
        defaultTextStyleId: settingsDefault);
  }

  int? _documentSettingsTextStyle(XmlElement root) {
    for (final el in root.childElements) {
      if (el.name.local != 'DocumentSettings') continue;
      final a = el.getAttribute('DefaultTextStyle');
      if (a != null) return int.tryParse(a);
    }
    return null;
  }

  VsdxStyleSheet? _readSheet(XmlElement ss) {
    final id = int.tryParse(ss.getAttribute('ID') ?? '');
    if (id == null) return null;
    final name = ss.getAttribute('NameU') ??
        ss.getAttribute('Name') ??
        'Style.$id';
    final textStyleId = int.tryParse(ss.getAttribute('TextStyle') ?? '');
    final lineStyleId = int.tryParse(ss.getAttribute('LineStyle') ?? '');
    final fillStyleId = int.tryParse(ss.getAttribute('FillStyle') ?? '');

    VsdxCharStyle? charStyle;
    var charSizeInherits = false;
    VsdxLine? line;
    VsdxFill? fill;

    for (final section in ss.childElements) {
      if (section.name.local != 'Section') continue;
      switch (section.getAttribute('N')) {
        case 'Character':
          final row = _firstRow(section);
          if (row != null) {
            final sizeCell = findCell(row, 'Size');
            charSizeInherits = _isInh(sizeCell?.getAttribute('F'));
            charStyle = VsdxCharStyle(
              fontFamily: _cellString(row, 'Font'),
              fontSizeInches:
                  readLengthInches(row, 'Size') ?? (12.0 / 72.0),
              style: VsdxFontStyle.fromBitmask(_rawCellInt(row, 'Style') ?? 0),
              color: VsdxColor.tryParse(_cellString(row, 'Color') ?? ''),
              underline: ((_rawCellInt(row, 'Style') ?? 0) & 0x04) != 0,
            );
          }
        case 'Line':
          // Line cells may sit directly under the section (no Row) in styles.
          final weight = readLengthInches(section, 'LineWeight');
          final pat = _cellInt(section, 'LinePattern');
          final color = VsdxColor.tryParse(_cellString(section, 'LineColor') ?? '');
          final soft = readLengthInches(section, 'SoftEdgesSize');
          if (weight != null || pat != null || color != null || soft != null) {
            line = VsdxLine(
              color: color,
              weightInches: weight ?? VsdxLine.defaultLine.weightInches,
              pattern: pat ?? VsdxLine.defaultLine.pattern,
              softEdgesInches: soft ?? VsdxLine.defaultLine.softEdgesInches,
            );
          }
        case 'Fill':
          final pat = _cellInt(section, 'FillPattern');
          final fg =
              VsdxColor.tryParse(_cellString(section, 'FillForegnd') ?? '');
          if (pat != null || fg != null) {
            fill = VsdxFill(
              foreground: fg,
              pattern: pat ?? VsdxFill.defaultFill.pattern,
            );
          }
      }
    }

    return VsdxStyleSheet(
      id: id,
      name: name,
      textStyleId: textStyleId,
      lineStyleId: lineStyleId,
      fillStyleId: fillStyleId,
      charStyle: charStyle,
      charSizeInherits: charSizeInherits,
      line: line,
      fill: fill,
    );
  }

  XmlElement? _firstRow(XmlElement section) {
    for (final el in section.childElements) {
      if (el.name.local == 'Row') return el;
    }
    return null;
  }

  bool _isInh(String? f) {
    if (f == null) return false;
    final u = f.trim().toUpperCase();
    return u == 'INH' || u.startsWith('INH(');
  }

  String? _cellString(XmlElement parent, String name) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    final v = cell.getAttribute('V');
    if (v == null || v.isEmpty) return null;
    // Skip theme formulas — not a concrete font name / colour.
    final u = v.toUpperCase();
    if (u == 'THEMED' || u.contains('THEMEVAL') || u.contains('THEMEGUARD')) {
      return null;
    }
    return v;
  }

  int? _cellInt(XmlElement parent, String name) {
    final s = _cellString(parent, name);
    if (s == null) return null;
    return int.tryParse(s) ?? double.tryParse(s)?.toInt();
  }

  /// Like [_cellInt] but reads the raw `V` even when it is `Themed` / a
  /// formula — numeric Style bitmasks still parse; non-numeric → null.
  int? _rawCellInt(XmlElement parent, String name) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    final v = cell.getAttribute('V');
    if (v == null) return null;
    return int.tryParse(v) ?? double.tryParse(v)?.toInt();
  }
}
