/// Small helpers for the ubiquitous `<Cell N="..." V="..." U="..." F="..."/>`
/// pattern.
///
/// In M1/M2 we only deal with *literal* values (`V=` numeric or string).
/// Formula evaluation (`F=`) and master inheritance (`F="Inh"`) are wired in
/// during M3.
library;

import 'package:xml/xml.dart';

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

/// Read the literal numeric value of `<Cell N="$name" V="...">` as **inches**.
///
/// Visio always stores a cell's `V` in its *internal units* — inches for any
/// length — and the `U` attribute only records the unit Visio uses to *display*
/// the value (e.g. `V="24" U="FT"` means 24 inches shown as "2 ft", and
/// `V="0.138889" U="PT"` means 0.138889 in shown as "10 pt"). So we take `V`
/// verbatim and must **not** rescale it by `U`. This mirrors libvisio, whose
/// internal unit is likewise inches. (See the Visio XML schema: "The value of a
/// cell element is always expressed in internal units.")
///
/// When `F="Inh"` and [inheritFrom] is supplied, returns [inheritFrom]
/// (formula-level master / page inheritance). When [inheritFrom] is `null`,
/// falls through to the cached `V=` so companions (Rounding, ReflectionDist,
/// …) are not zeroed when the stylesheet/master is unresolved. When there is
/// no literal `V`, falls back to evaluating the `F=` formula, which *does*
/// honour inline units written in the expression itself (`1.5 in`, `25.4 mm`).
double? readLengthInches(
  XmlElement parent,
  String name, {
  double? inheritFrom,
}) {
  final cell = findCell(parent, name);
  if (cell == null) return null;
  final f = cell.getAttribute('F');
  if (f != null && isInhFormula(f) && inheritFrom != null) {
    return inheritFrom;
  }
  final v = cell.getAttribute('V');
  if (v != null) {
    final n = double.tryParse(v);
    if (n != null) return n; // V is already in internal units (inches)
  }
  // No literal — fall back to the F= formula. evaluateFormula handles
  // numeric expressions with inline length units (`1.5 in`, `25.4 mm`).
  // (Still skip pure Inh with no V / no inherit source.)
  if (f == null || isInhFormula(f)) return null;
  return evaluateFormula(f);
}

/// Same shape as [readLengthInches] but for angles → **radians**. Visio stores
/// the `V` of an angle cell in radians (its internal unit); `U="DEG"` is only a
/// display hint, so `V` is taken verbatim and never rescaled by `U`.
double? readAngleRadians(
  XmlElement parent,
  String name, {
  double? inheritFrom,
}) {
  final cell = findCell(parent, name);
  if (cell == null) return null;
  final f = cell.getAttribute('F');
  if (f != null && isInhFormula(f) && inheritFrom != null) {
    return inheritFrom;
  }
  final v = cell.getAttribute('V');
  if (v != null) {
    final n = double.tryParse(v);
    if (n != null) return n; // V is already in internal units (radians)
  }
  if (f == null || isInhFormula(f)) return null;
  return evaluateFormula(f);
}

/// True when [f] is Visio master-inheritance (`Inh` / `Inh(...)`).
bool isInhFormula(String? f) {
  if (f == null) return false;
  final t = f.trim();
  if (t.isEmpty) return false;
  final u = t.toUpperCase();
  return u == 'INH' || u.startsWith('INH(');
}

/// True for the two XML boolean spellings accepted by libvisio.
bool isXmlTrue(String? value) {
  if (value == null) return false;
  final normalized = value.trim().toLowerCase();
  return normalized == '1' || normalized == 'true';
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
