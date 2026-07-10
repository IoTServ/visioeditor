/// Procedural Visio arrow heads.
///
/// Visio ships ~40 built-in BeginArrow/EndArrow shapes; we cover ~30
/// common ids procedurally so the renderer doesn't need to bundle SVG
/// assets. Unknown ids fall back to the classic filled triangle (id 4,
/// Visio's default).
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
  const ArrowDescriptor({required this.path, this.filled = true});

  /// Path in the arrow's local space (tip at origin, length along -X).
  final Path path;

  /// `true` ⇒ fill with the line colour; `false` ⇒ stroke only.
  final bool filled;
}

/// Lookup map for the supported arrow ids.
ArrowDescriptor? arrowDescriptor(int id) {
  final builder = _arrowBuilders[id] ?? _arrowBuilders[_defaultArrow];
  return builder?.call();
}

/// The set of arrow ids we know how to render. Used by tests + tooling.
Iterable<int> supportedArrowIds() => _arrowBuilders.keys;

const int _defaultArrow = 4;

final Map<int, ArrowDescriptor Function()> _arrowBuilders = {
  // 0 = no arrow (line only). The painter checks `hasBeginArrow` /
  // `hasEndArrow` before calling us so id 0 wouldn't actually arrive,
  // but we surface it as a no-op for completeness.
  0: _empty,
  1: _openTriangle,
  2: _filledTriangle,
  3: _openArrow,
  4: _filledTriangle,
  5: _filledTriangleNarrow,
  6: _openTriangleNarrow,
  7: _stealth,
  8: _stealthOpen,
  9: _filledArrowFletched,
  10: _diamond,
  11: _openDiamond,
  12: _filledHalfArrow,
  13: _circleDot,
  14: _openCircle,
  15: _square,
  16: _openSquare,
  17: _backslash,
  18: _crossfoot,
  19: _databaseOne,
  20: _databaseMany,
  21: _databaseOptionalOne,
  22: _databaseOptionalMany,
  23: _filledArrowSwept,
  24: _openArrowSwept,
  25: _filledTriangleWide,
  26: _openTriangleWide,
  27: _hatchedTriangle,
  28: _spear,
  29: _doubleTriangle,
  30: _doubleOpenTriangle,
  31: _filledChevron,
  32: _openChevron,
  33: _trident,
  34: _smallCircle,
  35: _filledArrowLong,
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
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-1, -0.25)
    ..lineTo(-1, 0.25)
    ..close();
  return ArrowDescriptor(path: p, filled: true);
}

ArrowDescriptor _filledTriangleWide() {
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-0.85, -0.55)
    ..lineTo(-0.85, 0.55)
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

ArrowDescriptor _filledArrowFletched() {
  // Triangle + tail flick (vertical hash).
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-1, -0.4)
    ..lineTo(-1, 0.4)
    ..close()
    ..moveTo(-1, -0.45)
    ..lineTo(-1.2, -0.55)
    ..lineTo(-1.2, 0.55)
    ..lineTo(-1, 0.45)
    ..close();
  return ArrowDescriptor(path: p, filled: true);
}

ArrowDescriptor _diamond() {
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-0.5, -0.35)
    ..lineTo(-1, 0)
    ..lineTo(-0.5, 0.35)
    ..close();
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

ArrowDescriptor _filledHalfArrow() {
  // Half (asymmetric) triangle — used for flow diagrams.
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-1, -0.5)
    ..lineTo(-1, 0)
    ..close();
  return ArrowDescriptor(path: p, filled: true);
}

ArrowDescriptor _circleDot() {
  final p = Path()
    ..addOval(Rect.fromCircle(center: const Offset(-0.5, 0), radius: 0.4));
  return ArrowDescriptor(path: p, filled: true);
}

ArrowDescriptor _openCircle() {
  final p = Path()
    ..addOval(Rect.fromCircle(center: const Offset(-0.5, 0), radius: 0.4));
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _smallCircle() {
  final p = Path()
    ..addOval(Rect.fromCircle(center: const Offset(-0.25, 0), radius: 0.2));
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _square() {
  final p = Path()
    ..addRect(const Rect.fromLTWH(-0.85, -0.4, 0.85, 0.8));
  return ArrowDescriptor(path: p, filled: true);
}

ArrowDescriptor _openSquare() {
  final p = Path()
    ..addRect(const Rect.fromLTWH(-0.85, -0.4, 0.85, 0.8));
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _backslash() {
  // Single hash stroke crossing the line (used by some database connectors).
  final p = Path()
    ..moveTo(-0.5, -0.5)
    ..lineTo(-0.5, 0.5);
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

ArrowDescriptor _databaseOne() {
  // Crossfoot with a single hash — Chen ER "one and only one".
  final p = Path()
    ..moveTo(-0.3, -0.5)
    ..lineTo(-0.3, 0.5);
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _databaseMany() {
  // Crow's foot — "many".
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-0.85, -0.5)
    ..moveTo(0, 0)
    ..lineTo(-0.85, 0)
    ..moveTo(0, 0)
    ..lineTo(-0.85, 0.5);
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _databaseOptionalOne() {
  // Open circle + single hash.
  final p = Path()
    ..addOval(Rect.fromCircle(center: const Offset(-0.6, 0), radius: 0.18))
    ..moveTo(-0.3, -0.5)
    ..lineTo(-0.3, 0.5);
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _databaseOptionalMany() {
  // Open circle + crow's foot.
  final p = Path()
    ..addOval(Rect.fromCircle(center: const Offset(-0.4, 0), radius: 0.18))
    ..moveTo(-0.6, -0.05)
    ..lineTo(-1.1, -0.5)
    ..moveTo(-0.6, 0)
    ..lineTo(-1.1, 0)
    ..moveTo(-0.6, 0.05)
    ..lineTo(-1.1, 0.5);
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

ArrowDescriptor _hatchedTriangle() {
  // Triangle outline + diagonal hash.
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-1, -0.4)
    ..lineTo(-1, 0.4)
    ..close()
    ..moveTo(-0.3, -0.2)
    ..lineTo(-0.7, 0.2);
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _spear() {
  // Long thin spear-style arrow.
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-1.4, -0.18)
    ..lineTo(-1.4, 0.18)
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

ArrowDescriptor _doubleOpenTriangle() {
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

ArrowDescriptor _filledChevron() {
  // Single chevron (>) — short fat arrow.
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-0.55, -0.5)
    ..lineTo(-0.4, 0)
    ..lineTo(-0.55, 0.5)
    ..close();
  return ArrowDescriptor(path: p, filled: true);
}

ArrowDescriptor _openChevron() {
  final p = Path()
    ..moveTo(-0.55, -0.5)
    ..lineTo(0, 0)
    ..lineTo(-0.55, 0.5);
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _trident() {
  // Three-pronged fork.
  const tip = Offset(0, 0);
  final p = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(-0.7, -0.5)
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(-0.85, 0)
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(-0.7, 0.5);
  return ArrowDescriptor(path: p, filled: false);
}

ArrowDescriptor _filledArrowLong() {
  // Long slim arrow head — useful for flow / process diagrams.
  final p = Path()
    ..moveTo(0, 0)
    ..lineTo(-1.5, -0.3)
    ..lineTo(-1.2, 0)
    ..lineTo(-1.5, 0.3)
    ..close();
  return ArrowDescriptor(path: p, filled: true);
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

