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
    final lineDefined = <String>{};
    VsdxFill? fill;
    final fillDefined = <String>{};

    for (final section in ss.childElements) {
      if (section.name.local != 'Section') continue;
      switch (section.getAttribute('N')) {
        case 'Character':
          final row = _firstRow(section);
          if (row != null) {
            final sizeCell = findCell(row, 'Size');
            charSizeInherits = isInhFormula(sizeCell?.getAttribute('F'));
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
          // F=Inh → treat as absent so [StyleSheetRegistry.resolveLine] walks
          // the parent LineStyle chain instead of the cached V=.
          final weight = _length(section, 'LineWeight');
          final pat = _cellInt(section, 'LinePattern');
          final colorStr = _cellString(section, 'LineColor');
          final color =
              colorStr == null ? null : VsdxColor.tryParse(colorStr);
          final soft = _length(section, 'SoftEdgesSize');
          final rounding = _length(section, 'Rounding');
          if (weight != null) lineDefined.add('LineWeight');
          if (pat != null) lineDefined.add('LinePattern');
          if (color != null) lineDefined.add('LineColor');
          if (soft != null) lineDefined.add('SoftEdgesSize');
          if (rounding != null) lineDefined.add('Rounding');
          if (lineDefined.isNotEmpty) {
            line = VsdxLine(
              color: color,
              weightInches: weight ?? VsdxLine.defaultLine.weightInches,
              pattern: pat ?? VsdxLine.defaultLine.pattern,
              softEdgesInches: soft ?? VsdxLine.defaultLine.softEdgesInches,
              roundingInches:
                  rounding ?? VsdxLine.defaultLine.roundingInches,
            );
          }
        case 'Fill':
          final pat = _cellInt(section, 'FillPattern');
          final fgStr = _cellString(section, 'FillForegnd');
          final fg = fgStr == null ? null : VsdxColor.tryParse(fgStr);
          final bgStr = _cellString(section, 'FillBkgnd');
          final bg = bgStr == null ? null : VsdxColor.tryParse(bgStr);
          if (pat != null) fillDefined.add('FillPattern');
          if (fg != null) fillDefined.add('FillForegnd');
          if (bg != null) fillDefined.add('FillBkgnd');
          if (fillDefined.isNotEmpty) {
            fill = VsdxFill(
              foreground: fg,
              background: bg,
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
      lineDefinedCells: Set.unmodifiable(lineDefined),
      fill: fill,
      fillDefinedCells: Set.unmodifiable(fillDefined),
    );
  }

  XmlElement? _firstRow(XmlElement section) {
    for (final el in section.childElements) {
      if (el.name.local == 'Row') return el;
    }
    return null;
  }

  /// Length cell; `F=Inh` → null (caller keeps walking the parent chain).
  double? _length(XmlElement parent, String name) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    if (isInhFormula(cell.getAttribute('F'))) return null;
    return readLengthInches(parent, name);
  }

  String? _cellString(XmlElement parent, String name) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    if (isInhFormula(cell.getAttribute('F'))) return null;
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
    if (isInhFormula(cell.getAttribute('F'))) return null;
    final v = cell.getAttribute('V');
    if (v == null) return null;
    return int.tryParse(v) ?? double.tryParse(v)?.toInt();
  }
}
