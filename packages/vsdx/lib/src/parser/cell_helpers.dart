/// Small helpers for the ubiquitous `<Cell N="..." V="..." U="..." F="..."/>`
/// pattern.
///
/// In M1/M2 we only deal with *literal* values (`V=` numeric or string).
/// Formula evaluation (`F=`) and master inheritance (`F="Inh"`) are wired in
/// during M3.
library;

import 'package:xml/xml.dart';

import '../utils/units.dart';
import 'formula.dart';

/// First direct `<Cell N="$name">` child, ignoring deeper sub-shapes.
XmlElement? findCell(XmlElement parent, String name) {
  for (final el in parent.childElements) {
    if (el.name.local == 'Cell' && el.getAttribute('N') == name) {
      return el;
    }
  }
  return null;
}

/// Read the literal numeric value of `<Cell N="$name" V="...">` and convert
/// it to **inches** if a length unit is provided.
///
/// Falls back to [fallback] when the cell is missing, the value is
/// non-numeric, or the formula (`F=`) makes the literal unreliable
/// (we deliberately *do* still trust `V=` because Visio always pre-computes
/// it — formulas are needed only for live re-evaluation).
///
/// When `F="Inh"` and [inheritFrom] is supplied, returns [inheritFrom]
/// directly (M2-09 formula-level master inheritance).
double? readLengthInches(
  XmlElement parent,
  String name, {
  double? inheritFrom,
}) {
  final cell = findCell(parent, name);
  if (cell == null) return null;
  final f = cell.getAttribute('F');
  if (f != null && _isInhFormula(f)) {
    return inheritFrom;
  }
  final v = cell.getAttribute('V');
  if (v != null) {
    final n = double.tryParse(v);
    if (n != null) {
      final u = VsdxLengthUnit.tryParse(cell.getAttribute('U'));
      return toInches(n, u);
    }
  }
  // No literal — fall back to the F= formula. evaluateFormula handles
  // numeric expressions with inline length units (`1.5 in`, `25.4 mm`).
  if (f == null) return null;
  return evaluateFormula(f);
}

/// Same shape as [readLengthInches] but for angles → **radians**.
double? readAngleRadians(
  XmlElement parent,
  String name, {
  double? inheritFrom,
}) {
  final cell = findCell(parent, name);
  if (cell == null) return null;
  final f = cell.getAttribute('F');
  if (f != null && _isInhFormula(f)) {
    return inheritFrom;
  }
  final v = cell.getAttribute('V');
  if (v != null) {
    final n = double.tryParse(v);
    if (n != null) {
      final u = VsdxAngleUnit.tryParse(cell.getAttribute('U'));
      return toRadians(n, u);
    }
  }
  if (f == null) return null;
  return evaluateFormula(f);
}

bool _isInhFormula(String f) {
  final t = f.trim();
  if (t.isEmpty) return false;
  final u = t.toUpperCase();
  return u == 'INH' || u.startsWith('INH(');
}

/// Direct text content of `<Text>` (concatenates all descendant text nodes).
String? readShapeText(XmlElement shape) {
  for (final child in shape.childElements) {
    if (child.name.local == 'Text') {
      final t = child.innerText.trim();
      return t.isEmpty ? null : t;
    }
  }
  return null;
}
