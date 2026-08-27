/// Procedural Visio arrow heads.
///
/// Visio ships 45 built-in BeginArrow/EndArrow shapes. The id mapping follows
/// libvisio's `VSDContentCollector::_linePropertiesMarkerPath`; unknown ids
/// fall back to the classic filled triangle (id 4, Visio's default).
///
/// Each arrow is described by an [ArrowDescriptor] in its own local space:
///   * X axis points along the line direction (toward the tip).
///   * Y axis is the perpendicular.
///   * The tip is at the origin.
///
/// The painter rotates the descriptor into world space and scales it by
/// the [VsdxLine.beginArrowSizeInches] / `endArrowSizeInches` value.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:meta/meta.dart';

@immutable
class ArrowDescriptor {
  const ArrowDescriptor({
    required this.path,
    this.filled = true,
    this.centered = false,
  });

  /// Path in the arrow's local space (tip at origin, length along -X).
  final Path path;

  /// `true` ⇒ fill with the line colour; `false` ⇒ stroke only.
  final bool filled;

  /// libvisio `draw:marker-*-center`: centre the marker on the line endpoint.
  final bool centered;
}

/// Lookup map for the supported arrow ids.
ArrowDescriptor? arrowDescriptor(int id) {
  final builder = _arrowBuilders[id] ?? _arrowBuilders[_defaultArrow];
  final descriptor = builder?.call();
  if (descriptor == null || !_centeredMarkerIds.contains(id)) {
    return descriptor;
  }
  return ArrowDescriptor(
    path: descriptor.path,
    filled: descriptor.filled,
    centered: true,
  );
}

/// The set of arrow ids we know how to render. Used by tests + tooling.
Iterable<int> supportedArrowIds() => _arrowBuilders.keys;

const int _defaultArrow = 4;

// VSDContentCollector::_lineProperties sets marker-center only for these ids.
const Set<int> _centeredMarkerIds = <int>{9, 10, 11, 20, 21};

final Map<int, ArrowDescriptor Function()> _arrowBuilders = {
  // 0 = no arrow (line only). The painter checks `hasBeginArrow` /
  // `hasEndArrow` before calling us so id 0 wouldn't actually arrive,
  // but we surface it as a no-op for completeness.
  0: _empty,
  1: _openTriangle,
  2: _filledTriangleNarrow,
  3: _openArrow,
  4: _filledTriangle,
  5: _stealth,
  6: _filledArrowSwept,
  // libvisio emits the exact same marker path for ids 7 and 19.
  7: _openChevron,
  8: _filledArrowSwept,
  9: _centeredLine,
  10: _filledCircle,
  11: _square,
  12: _openArrowSwept,
  13: _spear,
  14: _openTriangleWide,
  15: _openTriangleNarrow,
  16: _openTriangle,
  17: _stealthOpen,
  18: _openArrowSwept,
  19: _openChevron,
  20: _openCircle,
  21: _openSquare,
  22: _openDiamond,
  23: _backslash,
  24: _databaseOne,
  25: _crossfoot,
  // libvisio's TODO stub copies 25; Visio 26 is three hash strokes.
  26: _crossfootThree,
  27: _databaseMany,
  28: _databaseManyOne,
  29: _databaseOptionalMany,
  30: _databaseOptionalOne,
  31: () => _openCircleWithBars(1),
  32: () => _openCircleWithBars(2),
  33: () => _openCircleWithBars(3),
  34: _openCircleWithDiamond,
  35: () => _filledCircleWithBars(1),
  36: () => _filledCircleWithBars(2),
  37: () => _filledCircleWithBars(3),
  38: _filledCircleWithDiamond,
  39: _doubleTriangle,
  // libvisio's TODO stub fills 40; Visio 40 is the unfilled double triangle.
  40: _doubleTriangleOpen,
  41: _openCircleTerminator,
  42: _filledCircleTerminator,
  43: _doubleOpenArrow,
  44: _openArrowWithBar,
  45: _doubleOpenArrowWithBar,
};

ArrowDescriptor _empty() => ArrowDescriptor(path: Path(), filled: false);

ArrowDescriptor _filledTriangle() {
  // Length 1, half-width 0.4 — scaled to size at draw time.
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-1, -0.4)
    ..lineTo(-1, 0.4)
    ..close();
  return ArrowDescriptor(path: p, filled: true);
}

ArrowDescriptor _filledTriangleNarrow() {
  // libvisio marker 2 uses the same 20×10 triangle as unfilled 15, so Draw
  // paints it almost as wide as id 4. Keep the narrow filled head.
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-1, -0.25)
    ..lineTo(-1, 0.25)
    ..close();
  return ArrowDescriptor(path: p, filled: true);
}

ArrowDescriptor _openTriangle() {
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-1, -0.4)
    ..lineTo(-1, 0.4)
    ..close();
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _openTriangleNarrow() {
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-1, -0.25)
    ..lineTo(-1, 0.25)
    ..close();
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _openTriangleWide() {
  // libvisio marker 14 is labelled Unfilled Long Triangle but its viewBox
  // (`110 200 200 300`) clips the authored path. Keep the wide overflow
  // silhouette canvas / SVG already stroke (`overflow=visible`).
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-0.85, -0.55)
    ..lineTo(-0.85, 0.55)
    ..close();
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _openArrow() {
  // Two stroke lines forming a "V" — classic open arrow.
  final p = Path()
    ..moveTo(-1, -0.4)
    ..lineTo(0, 0)
    ..lineTo(-1, 0.4);
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _stealth() {
  // Concave-base "stealth" arrow.
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-1, -0.4)
    ..lineTo(-0.7, 0)
    ..lineTo(-1, 0.4)
    ..close();
  return ArrowDescriptor(path: p, filled: true);
}

ArrowDescriptor _stealthOpen() {
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-1, -0.4)
    ..lineTo(-0.7, 0)
    ..lineTo(-1, 0.4)
    ..close();
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _filledCircle() {
  // A "ball" terminator sitting just behind the line end (Visio arrow 10).
  final p = Path()
    ..addOval(Rect.fromCircle(center: const Offset(-0.5, 0), radius: 0.5));
  return ArrowDescriptor(path: p, filled: true);
}

ArrowDescriptor _filledCircleWithBars(int bars) {
  // libvisio TODO-stubs 36–37 copy the one-bar path of 35. Visio adds extra
  // bars behind the circle (same layout the Geometry bake uses).
  final p = Path()
    ..addOval(Rect.fromCircle(center: const Offset(-0.4, 0), radius: 0.4));
  for (var i = 0; i < bars; i++) {
    p.addRect(Rect.fromLTWH(-1.0 - i * 0.25, -0.5, 0.2, 1.0));
  }
  return ArrowDescriptor(path: p, filled: true);
}

ArrowDescriptor _openDiamond() {
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-0.5, -0.35)
    ..lineTo(-1, 0)
    ..lineTo(-0.5, 0.35)
    ..close();
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _filledCircleTerminator() {
  final p = Path()
    ..addOval(Rect.fromCircle(center: const Offset(-0.5, 0), radius: 0.5));
  return ArrowDescriptor(path: p, filled: true);
}

ArrowDescriptor _openCircle() {
  final p = Path()
    ..addOval(Rect.fromCircle(center: const Offset(-0.5, 0), radius: 0.4));
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _openCircleTerminator() {
  final p = Path()
    ..addOval(Rect.fromCircle(center: const Offset(-0.5, 0), radius: 0.5));
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _square() {
  final p = Path()..addRect(const Rect.fromLTWH(-0.85, -0.4, 0.85, 0.8));
  return ArrowDescriptor(path: p, filled: true);
}

ArrowDescriptor _openSquare() {
  final p = Path()..addRect(const Rect.fromLTWH(-0.85, -0.4, 0.85, 0.8));
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _backslash() {
  // libvisio marker 23: oblique stroke plus the full centred stem.
  final p = Path()
    ..moveTo(-1, 0.5)
    ..lineTo(0, -0.5)
    ..moveTo(-0.5, -0.5)
    ..lineTo(-0.5, 0.5);
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _centeredLine() {
  // libvisio marker 9 combines an oblique stroke with a centred stem. Its
  // authored path is about 2.2 times taller than its nominal viewBox
  // (`M1 2 ... 20 20 ... M11 11 v12` in VSDContentCollector), so keep that
  // overflow. A square approximation turns architectural dimension ticks
  // into tiny crosses, especially at the legacy VSD 0.05-inch size floor.
  final p = Path()
    ..moveTo(-1, -1.1)
    ..lineTo(0, 1.1)
    ..moveTo(-0.5, -1.1)
    ..lineTo(-0.5, 1.1);
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _crossfoot() {
  // Two parallel hash strokes — "exactly one" notation.
  final p = Path()
    ..moveTo(-0.3, -0.5)
    ..lineTo(-0.3, 0.5)
    ..moveTo(-0.55, -0.5)
    ..lineTo(-0.55, 0.5);
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _crossfootThree() {
  // libvisio TODO 26 copies the two-bar path of 25.
  final p = Path()
    ..moveTo(-0.2, -0.5)
    ..lineTo(-0.2, 0.5)
    ..moveTo(-0.4, -0.5)
    ..lineTo(-0.4, 0.5)
    ..moveTo(-0.6, -0.5)
    ..lineTo(-0.6, 0.5);
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _openCircleWithBars(int bars) {
  final p = Path()
    ..addOval(Rect.fromCircle(center: const Offset(-0.4, 0), radius: 0.4));
  for (var i = 0; i < bars; i++) {
    final x = -0.95 - i * 0.25;
    p
      ..moveTo(x, -0.5)
      ..lineTo(x, 0.5);
  }
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _openCircleWithDiamond() {
  final p = Path()
    ..addOval(Rect.fromCircle(center: const Offset(-0.35, 0), radius: 0.35))
    ..moveTo(-0.8, 0)
    ..lineTo(-1.15, -0.35)
    ..lineTo(-1.5, 0)
    ..lineTo(-1.15, 0.35)
    ..close();
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _filledCircleWithDiamond() {
  final p = Path()
    ..addOval(Rect.fromCircle(center: const Offset(-0.35, 0), radius: 0.35))
    ..moveTo(-0.8, 0)
    ..lineTo(-1.15, -0.35)
    ..lineTo(-1.5, 0)
    ..lineTo(-1.15, 0.35)
    ..close();
  return ArrowDescriptor(path: p, filled: true);
}

ArrowDescriptor _doubleOpenArrow() {
  final p = Path()
    ..moveTo(-0.5, -0.4)
    ..lineTo(0, 0)
    ..lineTo(-0.5, 0.4)
    ..moveTo(-1.0, -0.4)
    ..lineTo(-0.5, 0)
    ..lineTo(-1.0, 0.4);
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _openArrowWithBar() {
  final p = Path()
    ..moveTo(-1, -0.4)
    ..lineTo(0, 0)
    ..lineTo(-1, 0.4)
    ..moveTo(-1.2, -0.5)
    ..lineTo(-1.2, 0.5);
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _doubleOpenArrowWithBar() {
  final p = Path()
    ..moveTo(-0.5, -0.4)
    ..lineTo(0, 0)
    ..lineTo(-0.5, 0.4)
    ..moveTo(-1.0, -0.4)
    ..lineTo(-0.5, 0)
    ..lineTo(-1.0, 0.4)
    ..moveTo(-1.2, -0.5)
    ..lineTo(-1.2, 0.5);
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _databaseOne() {
  // Crossfoot with a single hash — Chen ER "one and only one".
  final p = Path()
    ..moveTo(-0.3, -0.5)
    ..lineTo(-0.3, 0.5);
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _databaseMany() {
  // Crow's foot — "many". libvisio's ids 27–30 are reverse markers:
  // their notation extends past the authored endpoint, unlike arrowheads
  // whose body sits back on the carrier line.
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(0.85, -0.5)
    ..moveTo(0, 0)
    ..lineTo(0.85, 0)
    ..moveTo(0, 0)
    ..lineTo(0.85, 0.5);
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _databaseManyOne() {
  // Crow's foot plus the "one" bar (libvisio marker 28).
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(0.72, -0.5)
    ..moveTo(0, 0)
    ..lineTo(0.72, 0)
    ..moveTo(0, 0)
    ..lineTo(0.72, 0.5)
    ..moveTo(0.88, -0.5)
    ..lineTo(0.88, 0.5);
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _databaseOptionalOne() {
  // Open circle + single hash.
  final p = Path()
    ..addOval(Rect.fromCircle(center: const Offset(0.6, 0), radius: 0.18))
    ..moveTo(0.3, -0.5)
    ..lineTo(0.3, 0.5);
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _databaseOptionalMany() {
  // Open circle + crow's foot.
  final p = Path()
    ..addOval(Rect.fromCircle(center: const Offset(0.4, 0), radius: 0.18))
    ..moveTo(0.6, -0.05)
    ..lineTo(1.1, -0.5)
    ..moveTo(0.6, 0)
    ..lineTo(1.1, 0)
    ..moveTo(0.6, 0.05)
    ..lineTo(1.1, 0.5);
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _filledArrowSwept() {
  // Slightly back-swept triangle — Visio's "stealth" alt.
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-1.1, -0.45)
    ..lineTo(-0.85, 0)
    ..lineTo(-1.1, 0.45)
    ..close();
  return ArrowDescriptor(path: p, filled: true);
}

ArrowDescriptor _openArrowSwept() {
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-1.1, -0.45)
    ..lineTo(-0.85, 0)
    ..lineTo(-1.1, 0.45)
    ..close();
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _spear() {
  // libvisio marker 13 is a 20-by-30 filled long triangle. Keep the 1.4
  // endpoint reach used by marker sizing and preserve its 1:3 half-width.
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-1.4, -1.4 / 3)
    ..lineTo(-1.4, 1.4 / 3)
    ..close();
  return ArrowDescriptor(path: p, filled: true);
}

ArrowDescriptor _doubleTriangle() {
  // Two stacked triangles.
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-0.6, -0.35)
    ..lineTo(-0.6, 0.35)
    ..close()
    ..moveTo(-0.6, 0)
    ..lineTo(-1.2, -0.35)
    ..lineTo(-1.2, 0.35)
    ..close();
  return ArrowDescriptor(path: p, filled: true);
}

ArrowDescriptor _doubleTriangleOpen() {
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-0.6, -0.35)
    ..lineTo(-0.6, 0.35)
    ..close()
    ..moveTo(-0.6, 0)
    ..lineTo(-1.2, -0.35)
    ..lineTo(-1.2, 0.35)
    ..close();
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _openChevron() {
  final p = Path()
    ..moveTo(-0.55, -0.5)
    ..lineTo(0, 0)
    ..lineTo(-0.55, 0.5);
  return ArrowDescriptor(path: p, filled: false);
}

// Used by tests / tooling: small assertion-friendly summary of the path.
double arrowDebugReach(int id) {
  final desc = arrowDescriptor(id);
  if (desc == null) return 0;
  final b = desc.path.getBounds();
  // The arrow's reach along the line direction is `|min(x)|` (tip at 0,
  // base at negative X).
  return math.max(b.width, b.height);
}

/// Visible body-stroke length hidden underneath a non-centred marker.
///
/// The marker remains anchored at the authored endpoint; trimming prevents
/// open circles and line arrows from showing the body through their interior.
double arrowBodyTrimInches(int id, double sizeInches, double lineWeightInches) {
  final desc = arrowDescriptor(id);
  if (desc == null || desc.centered || id == 0) return 0;
  final reach = math.max(0.0, -desc.path.getBounds().left);
  final size = sizeInches > 0 ? sizeInches : 0.125;
  return math.max(0.0, reach * size - math.max(0.0, lineWeightInches) / 2);
}
