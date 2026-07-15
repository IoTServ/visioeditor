import 'package:vsdx/vsdx.dart';

/// A palette entry: a named builder that produces a shape at a given page-inch
/// centre. The shapes panel renders a **live geometry thumbnail** (built via
/// `lib/render/path_builder.dart`), so no icon is needed — the preview always
/// matches what actually drops on the canvas.
class Stencil {
  const Stencil(this.name, this.build);

  final String name;
  final VsdxShape Function(int id, double cx, double cy) build;
}

/// A named group of stencils — drawio's shape-library sections (General,
/// Flowchart, Arrows …). The panel renders one collapsible header per group.
class StencilGroup {
  const StencilGroup(this.name, this.stencils,
      {this.expandAtWidth = double.infinity});

  final String name;
  final List<Stencil> stencils;

  /// Minimum window width (logical px) at which this library starts expanded.
  /// Lower values = everyday libraries (opened on typical laptops); higher
  /// values = specialised libraries that only open when the window is roomy.
  /// [double.infinity] means never auto-expand (user must open manually).
  ///
  /// Matches drawio / Visio / 万兴图示: basic shapes stay open; UML and other
  /// specialised packs stay collapsed until there is space (or the user opens
  /// them).
  final double expandAtWidth;

  /// True when this group is in the everyday tier (opened from ~laptop width).
  bool get defaultExpanded => expandAtWidth <= 900;
}

const double _w = 1.5;
const double _h = 1.0;

VsdxShape _rect(int id, double cx, double cy, {double w = _w, double h = _h}) =>
    VsdxShapeFactory.rectangle(
        id: id, pinX: cx, pinY: cy, width: w, height: h);

VsdxShape _ellipse(int id, double cx, double cy,
        {double w = _w, double h = _h}) =>
    VsdxShapeFactory.ellipse(id: id, pinX: cx, pinY: cy, width: w, height: h);

VsdxShape _poly(int id, double cx, double cy, List<Offset2D> unit,
        {double w = _w, double h = _h}) =>
    VsdxShapeFactory.polygon(
        id: id, pinX: cx, pinY: cy, width: w, height: h, unit: unit);

// --- Unit polygon vertices (0..1, origin bottom-left, Y-up) ------------------

const List<Offset2D> _diamond = [
  Offset2D(0.5, 1),
  Offset2D(1, 0.5),
  Offset2D(0.5, 0),
  Offset2D(0, 0.5),
];
const List<Offset2D> _parallelogram = [
  Offset2D(0.25, 1),
  Offset2D(1, 1),
  Offset2D(0.75, 0),
  Offset2D(0, 0),
];
const List<Offset2D> _triangle = [
  Offset2D(0.5, 1),
  Offset2D(1, 0),
  Offset2D(0, 0),
];
const List<Offset2D> _rightTriangle = [
  Offset2D(0, 1),
  Offset2D(0, 0),
  Offset2D(1, 0),
];
const List<Offset2D> _pentagon = [
  Offset2D(0.5, 1),
  Offset2D(1, 0.62),
  Offset2D(0.81, 0),
  Offset2D(0.19, 0),
  Offset2D(0, 0.62),
];
const List<Offset2D> _hexagon = [
  Offset2D(0.25, 1),
  Offset2D(0.75, 1),
  Offset2D(1, 0.5),
  Offset2D(0.75, 0),
  Offset2D(0.25, 0),
  Offset2D(0, 0.5),
];
const List<Offset2D> _octagon = [
  Offset2D(0.3, 1),
  Offset2D(0.7, 1),
  Offset2D(1, 0.7),
  Offset2D(1, 0.3),
  Offset2D(0.7, 0),
  Offset2D(0.3, 0),
  Offset2D(0, 0.3),
  Offset2D(0, 0.7),
];
const List<Offset2D> _trapezoid = [
  Offset2D(0.2, 1),
  Offset2D(0.8, 1),
  Offset2D(1, 0),
  Offset2D(0, 0),
];
const List<Offset2D> _cross = [
  Offset2D(0.35, 1),
  Offset2D(0.65, 1),
  Offset2D(0.65, 0.65),
  Offset2D(1, 0.65),
  Offset2D(1, 0.35),
  Offset2D(0.65, 0.35),
  Offset2D(0.65, 0),
  Offset2D(0.35, 0),
  Offset2D(0.35, 0.35),
  Offset2D(0, 0.35),
  Offset2D(0, 0.65),
  Offset2D(0.35, 0.65),
];
const List<Offset2D> _star = [
  Offset2D(0.5, 1.0),
  Offset2D(0.382, 0.662),
  Offset2D(0.024, 0.655),
  Offset2D(0.31, 0.438),
  Offset2D(0.206, 0.095),
  Offset2D(0.5, 0.3),
  Offset2D(0.794, 0.095),
  Offset2D(0.69, 0.438),
  Offset2D(0.976, 0.655),
  Offset2D(0.618, 0.662),
];
const List<Offset2D> _card = [
  Offset2D(0.2, 1),
  Offset2D(1, 1),
  Offset2D(1, 0),
  Offset2D(0, 0),
  Offset2D(0, 0.8),
];
const List<Offset2D> _callout = [
  Offset2D(0, 0.35),
  Offset2D(0, 1),
  Offset2D(1, 1),
  Offset2D(1, 0.35),
  Offset2D(0.45, 0.35),
  Offset2D(0.2, 0),
  Offset2D(0.3, 0.35),
];
const List<Offset2D> _step = [
  Offset2D(0, 1),
  Offset2D(0.7, 1),
  Offset2D(1, 0.5),
  Offset2D(0.7, 0),
  Offset2D(0, 0),
  Offset2D(0.3, 0.5),
];
const List<Offset2D> _manualInput = [
  Offset2D(0, 0),
  Offset2D(0, 0.75),
  Offset2D(1, 1),
  Offset2D(1, 0),
];
const List<Offset2D> _manualOperation = [
  Offset2D(0, 1),
  Offset2D(1, 1),
  Offset2D(0.8, 0),
  Offset2D(0.2, 0),
];
const List<Offset2D> _offPage = [
  Offset2D(0, 1),
  Offset2D(1, 1),
  Offset2D(1, 0.35),
  Offset2D(0.5, 0),
  Offset2D(0, 0.35),
];
const List<Offset2D> _arrowRight = [
  Offset2D(0, 0.7),
  Offset2D(0.6, 0.7),
  Offset2D(0.6, 1),
  Offset2D(1, 0.5),
  Offset2D(0.6, 0),
  Offset2D(0.6, 0.3),
  Offset2D(0, 0.3),
];
const List<Offset2D> _arrowLeft = [
  Offset2D(1, 0.7),
  Offset2D(0.4, 0.7),
  Offset2D(0.4, 1),
  Offset2D(0, 0.5),
  Offset2D(0.4, 0),
  Offset2D(0.4, 0.3),
  Offset2D(1, 0.3),
];
const List<Offset2D> _arrowUp = [
  Offset2D(0.3, 0),
  Offset2D(0.3, 0.6),
  Offset2D(0, 0.6),
  Offset2D(0.5, 1),
  Offset2D(1, 0.6),
  Offset2D(0.7, 0.6),
  Offset2D(0.7, 0),
];
const List<Offset2D> _arrowDown = [
  Offset2D(0.3, 1),
  Offset2D(0.3, 0.4),
  Offset2D(0, 0.4),
  Offset2D(0.5, 0),
  Offset2D(1, 0.4),
  Offset2D(0.7, 0.4),
  Offset2D(0.7, 1),
];
const List<Offset2D> _doubleArrow = [
  Offset2D(0, 0.5),
  Offset2D(0.25, 0.8),
  Offset2D(0.25, 0.65),
  Offset2D(0.75, 0.65),
  Offset2D(0.75, 0.8),
  Offset2D(1, 0.5),
  Offset2D(0.75, 0.2),
  Offset2D(0.75, 0.35),
  Offset2D(0.25, 0.35),
  Offset2D(0.25, 0.2),
];
const List<Offset2D> _merge = [
  Offset2D(0, 1),
  Offset2D(1, 1),
  Offset2D(0.5, 0),
];
const List<Offset2D> _collate = [
  Offset2D(0, 1),
  Offset2D(1, 1),
  Offset2D(0, 0),
  Offset2D(1, 0),
];
const List<Offset2D> _loopLimit = [
  Offset2D(0, 0),
  Offset2D(0, 0.75),
  Offset2D(0.25, 1),
  Offset2D(0.75, 1),
  Offset2D(1, 0.75),
  Offset2D(1, 0),
];
const List<Offset2D> _lightning = [
  Offset2D(0.55, 1.0),
  Offset2D(0.15, 0.45),
  Offset2D(0.42, 0.45),
  Offset2D(0.30, 0.0),
  Offset2D(0.85, 0.55),
  Offset2D(0.50, 0.55),
];
const List<Offset2D> _chevron = [
  Offset2D(0, 1),
  Offset2D(0.7, 1),
  Offset2D(1, 0.5),
  Offset2D(0.7, 0),
  Offset2D(0, 0),
  Offset2D(0.3, 0.5),
];
const List<Offset2D> _notchedArrow = [
  Offset2D(0, 0.7),
  Offset2D(0.55, 0.7),
  Offset2D(0.55, 1),
  Offset2D(1, 0.5),
  Offset2D(0.55, 0),
  Offset2D(0.55, 0.3),
  Offset2D(0, 0.3),
  Offset2D(0.15, 0.5),
];
const List<Offset2D> _signalIn = [
  Offset2D(0, 1),
  Offset2D(0.75, 1),
  Offset2D(1, 0.5),
  Offset2D(0.75, 0),
  Offset2D(0, 0),
];
const List<Offset2D> _quadArrow = [
  Offset2D(0.35, 0.65),
  Offset2D(0.35, 0.85),
  Offset2D(0.2, 0.85),
  Offset2D(0.5, 1),
  Offset2D(0.8, 0.85),
  Offset2D(0.65, 0.85),
  Offset2D(0.65, 0.65),
  Offset2D(0.85, 0.65),
  Offset2D(0.85, 0.8),
  Offset2D(1, 0.5),
  Offset2D(0.85, 0.2),
  Offset2D(0.85, 0.35),
  Offset2D(0.65, 0.35),
  Offset2D(0.65, 0.15),
  Offset2D(0.8, 0.15),
  Offset2D(0.5, 0),
  Offset2D(0.2, 0.15),
  Offset2D(0.35, 0.15),
  Offset2D(0.35, 0.35),
  Offset2D(0.15, 0.35),
  Offset2D(0.15, 0.2),
  Offset2D(0, 0.5),
  Offset2D(0.15, 0.8),
  Offset2D(0.15, 0.65),
];
const List<Offset2D> _triadArrow = [
  Offset2D(0.35, 0.55),
  Offset2D(0.35, 0.8),
  Offset2D(0.2, 0.8),
  Offset2D(0.5, 1),
  Offset2D(0.8, 0.8),
  Offset2D(0.65, 0.8),
  Offset2D(0.65, 0.55),
  Offset2D(0.85, 0.55),
  Offset2D(0.85, 0.7),
  Offset2D(1, 0.35),
  Offset2D(0.85, 0),
  Offset2D(0.85, 0.2),
  Offset2D(0.15, 0.2),
  Offset2D(0.15, 0),
  Offset2D(0, 0.35),
  Offset2D(0.15, 0.7),
  Offset2D(0.15, 0.55),
];
const List<Offset2D> _corner = [
  Offset2D(0, 1),
  Offset2D(0.4, 1),
  Offset2D(0.4, 0.4),
  Offset2D(1, 0.4),
  Offset2D(1, 0),
  Offset2D(0, 0),
];
const List<Offset2D> _tee = [
  Offset2D(0, 1),
  Offset2D(1, 1),
  Offset2D(1, 0.6),
  Offset2D(0.65, 0.6),
  Offset2D(0.65, 0),
  Offset2D(0.35, 0),
  Offset2D(0.35, 0.6),
  Offset2D(0, 0.6),
];
const List<Offset2D> _banner = [
  Offset2D(0, 0.85),
  Offset2D(0.15, 1),
  Offset2D(0.85, 1),
  Offset2D(1, 0.85),
  Offset2D(1, 0.15),
  Offset2D(0.85, 0),
  Offset2D(0.15, 0),
  Offset2D(0, 0.15),
];
const List<Offset2D> _pyramid = [
  Offset2D(0.5, 1),
  Offset2D(1, 0),
  Offset2D(0, 0),
];
const List<Offset2D> _star4 = [
  Offset2D(0.5, 1),
  Offset2D(0.62, 0.62),
  Offset2D(1, 0.5),
  Offset2D(0.62, 0.38),
  Offset2D(0.5, 0),
  Offset2D(0.38, 0.38),
  Offset2D(0, 0.5),
  Offset2D(0.38, 0.62),
];
const List<Offset2D> _star6 = [
  Offset2D(0.5, 1),
  Offset2D(0.62, 0.72),
  Offset2D(0.95, 0.75),
  Offset2D(0.72, 0.5),
  Offset2D(0.95, 0.25),
  Offset2D(0.62, 0.28),
  Offset2D(0.5, 0),
  Offset2D(0.38, 0.28),
  Offset2D(0.05, 0.25),
  Offset2D(0.28, 0.5),
  Offset2D(0.05, 0.75),
  Offset2D(0.38, 0.72),
];
const List<Offset2D> _moon = [
  Offset2D(0.55, 1),
  Offset2D(0.15, 0.85),
  Offset2D(0, 0.5),
  Offset2D(0.15, 0.15),
  Offset2D(0.55, 0),
  Offset2D(0.35, 0.2),
  Offset2D(0.25, 0.5),
  Offset2D(0.35, 0.8),
];
const List<Offset2D> _transfer = [
  Offset2D(0, 0.65),
  Offset2D(0.55, 0.65),
  Offset2D(0.55, 1),
  Offset2D(1, 0.5),
  Offset2D(0.55, 0),
  Offset2D(0.55, 0.35),
  Offset2D(0, 0.35),
];
const List<Offset2D> _doubleArrowV = [
  Offset2D(0.5, 1),
  Offset2D(0.8, 0.75),
  Offset2D(0.65, 0.75),
  Offset2D(0.65, 0.25),
  Offset2D(0.8, 0.25),
  Offset2D(0.5, 0),
  Offset2D(0.2, 0.25),
  Offset2D(0.35, 0.25),
  Offset2D(0.35, 0.75),
  Offset2D(0.2, 0.75),
];
const List<Offset2D> _slenderArrow = [
  Offset2D(0, 0.6),
  Offset2D(0.7, 0.6),
  Offset2D(0.7, 0.85),
  Offset2D(1, 0.5),
  Offset2D(0.7, 0.15),
  Offset2D(0.7, 0.4),
  Offset2D(0, 0.4),
];
const List<Offset2D> _sharpArrow = [
  Offset2D(0, 0.62),
  Offset2D(0.55, 0.62),
  Offset2D(0.45, 1),
  Offset2D(1, 0.5),
  Offset2D(0.45, 0),
  Offset2D(0.55, 0.38),
  Offset2D(0, 0.38),
];
const List<Offset2D> _tailedArrow = [
  Offset2D(0.15, 0.65),
  Offset2D(0.55, 0.65),
  Offset2D(0.55, 1),
  Offset2D(1, 0.5),
  Offset2D(0.55, 0),
  Offset2D(0.55, 0.35),
  Offset2D(0.15, 0.35),
  Offset2D(0, 0.5),
];
const List<Offset2D> _stripedArrow = [
  Offset2D(0.18, 0.7),
  Offset2D(0.55, 0.7),
  Offset2D(0.55, 1),
  Offset2D(1, 0.5),
  Offset2D(0.55, 0),
  Offset2D(0.55, 0.3),
  Offset2D(0.18, 0.3),
  Offset2D(0.18, 0.7),
];
const List<Offset2D> _bendArrow = [
  Offset2D(0, 0.35),
  Offset2D(0.55, 0.35),
  Offset2D(0.55, 0),
  Offset2D(1, 0.25),
  Offset2D(0.55, 0.5),
  Offset2D(0.55, 0.55),
  Offset2D(0.35, 0.55),
  Offset2D(0.35, 1),
  Offset2D(0, 1),
];
const List<Offset2D> _uTurnArrow = [
  Offset2D(0.15, 0),
  Offset2D(0.15, 0.55),
  Offset2D(0.35, 0.55),
  Offset2D(0.35, 0.25),
  Offset2D(0.55, 0.25),
  Offset2D(0.55, 0.7),
  Offset2D(0.75, 0.7),
  Offset2D(0.55, 1),
  Offset2D(0.35, 0.7),
  Offset2D(0.35, 0.85),
  Offset2D(0, 0.85),
  Offset2D(0, 0),
];
const List<Offset2D> _calloutArrow = [
  Offset2D(0, 0.25),
  Offset2D(0.55, 0.25),
  Offset2D(0.55, 0),
  Offset2D(1, 0.5),
  Offset2D(0.55, 1),
  Offset2D(0.55, 0.75),
  Offset2D(0, 0.75),
];
const List<Offset2D> _star8 = [
  Offset2D(0.5, 1),
  Offset2D(0.58, 0.72),
  Offset2D(0.85, 0.85),
  Offset2D(0.72, 0.58),
  Offset2D(1, 0.5),
  Offset2D(0.72, 0.42),
  Offset2D(0.85, 0.15),
  Offset2D(0.58, 0.28),
  Offset2D(0.5, 0),
  Offset2D(0.42, 0.28),
  Offset2D(0.15, 0.15),
  Offset2D(0.28, 0.42),
  Offset2D(0, 0.5),
  Offset2D(0.28, 0.58),
  Offset2D(0.15, 0.85),
  Offset2D(0.42, 0.72),
];
const List<Offset2D> _tick = [
  Offset2D(0.1, 0.55),
  Offset2D(0.35, 0.25),
  Offset2D(0.45, 0.35),
  Offset2D(0.9, 0.9),
  Offset2D(0.78, 1),
  Offset2D(0.35, 0.5),
];
const List<Offset2D> _xMark = [
  Offset2D(0.2, 1),
  Offset2D(0.5, 0.7),
  Offset2D(0.8, 1),
  Offset2D(1, 0.8),
  Offset2D(0.7, 0.5),
  Offset2D(1, 0.2),
  Offset2D(0.8, 0),
  Offset2D(0.5, 0.3),
  Offset2D(0.2, 0),
  Offset2D(0, 0.2),
  Offset2D(0.3, 0.5),
  Offset2D(0, 0.8),
];
const List<Offset2D> _plaque = [
  Offset2D(0.15, 1),
  Offset2D(0.85, 1),
  Offset2D(1, 0.85),
  Offset2D(1, 0.15),
  Offset2D(0.85, 0),
  Offset2D(0.15, 0),
  Offset2D(0, 0.15),
  Offset2D(0, 0.85),
];
const List<Offset2D> _diagStripe = [
  Offset2D(0.35, 1),
  Offset2D(1, 1),
  Offset2D(0.65, 0),
  Offset2D(0, 0),
];
const List<Offset2D> _acuteTriangle = [
  Offset2D(0.5, 1),
  Offset2D(1, 0),
  Offset2D(0, 0),
];
const List<Offset2D> _obtuseTriangle = [
  Offset2D(0.15, 1),
  Offset2D(1, 0),
  Offset2D(0, 0),
];
const List<Offset2D> _ovalCallout = [
  Offset2D(0.15, 0.45),
  Offset2D(0.05, 0.7),
  Offset2D(0.25, 0.85),
  Offset2D(0.5, 0.95),
  Offset2D(0.8, 0.85),
  Offset2D(0.95, 0.6),
  Offset2D(0.9, 0.35),
  Offset2D(0.7, 0.2),
  Offset2D(0.4, 0.2),
  Offset2D(0.28, 0.35),
  Offset2D(0.22, 0),
  Offset2D(0.35, 0.35),
];
const List<Offset2D> _sun = [
  Offset2D(0.5, 1),
  Offset2D(0.58, 0.78),
  Offset2D(0.78, 0.92),
  Offset2D(0.7, 0.7),
  Offset2D(0.95, 0.7),
  Offset2D(0.78, 0.58),
  Offset2D(1, 0.5),
  Offset2D(0.78, 0.42),
  Offset2D(0.95, 0.3),
  Offset2D(0.7, 0.3),
  Offset2D(0.78, 0.08),
  Offset2D(0.58, 0.22),
  Offset2D(0.5, 0),
  Offset2D(0.42, 0.22),
  Offset2D(0.22, 0.08),
  Offset2D(0.3, 0.3),
  Offset2D(0.05, 0.3),
  Offset2D(0.22, 0.42),
  Offset2D(0, 0.5),
  Offset2D(0.22, 0.58),
  Offset2D(0.05, 0.7),
  Offset2D(0.3, 0.7),
  Offset2D(0.22, 0.92),
  Offset2D(0.42, 0.78),
];
const List<Offset2D> _switchShape = [
  Offset2D(0, 0.7),
  Offset2D(0.35, 0.7),
  Offset2D(0.5, 1),
  Offset2D(0.65, 0.7),
  Offset2D(1, 0.7),
  Offset2D(1, 0.3),
  Offset2D(0.65, 0.3),
  Offset2D(0.5, 0),
  Offset2D(0.35, 0.3),
  Offset2D(0, 0.3),
];
const List<Offset2D> _notchedSignalIn = [
  Offset2D(0, 0.7),
  Offset2D(0.55, 0.7),
  Offset2D(0.55, 1),
  Offset2D(1, 0.5),
  Offset2D(0.55, 0),
  Offset2D(0.55, 0.3),
  Offset2D(0, 0.3),
  Offset2D(0.12, 0.5),
];
const List<Offset2D> _slenderTwoWay = [
  Offset2D(0, 0.5),
  Offset2D(0.22, 0.85),
  Offset2D(0.22, 0.65),
  Offset2D(0.78, 0.65),
  Offset2D(0.78, 0.85),
  Offset2D(1, 0.5),
  Offset2D(0.78, 0.15),
  Offset2D(0.78, 0.35),
  Offset2D(0.22, 0.35),
  Offset2D(0.22, 0.15),
];
const List<Offset2D> _stylisedArrow = [
  Offset2D(0, 0.72),
  Offset2D(0.42, 0.72),
  Offset2D(0.48, 1),
  Offset2D(1, 0.5),
  Offset2D(0.48, 0),
  Offset2D(0.42, 0.28),
  Offset2D(0, 0.28),
  Offset2D(0.1, 0.5),
];
const List<Offset2D> _bendDoubleArrow = [
  Offset2D(0, 0.35),
  Offset2D(0.45, 0.35),
  Offset2D(0.45, 0),
  Offset2D(0.75, 0.22),
  Offset2D(0.45, 0.45),
  Offset2D(0.45, 0.55),
  Offset2D(0.75, 0.55),
  Offset2D(0.45, 0.78),
  Offset2D(0.45, 1),
  Offset2D(0, 0.78),
  Offset2D(0.22, 0.55),
  Offset2D(0.22, 0.45),
];
const List<Offset2D> _calloutDoubleArrow = [
  Offset2D(0.35, 0.35),
  Offset2D(0.35, 0),
  Offset2D(0, 0.5),
  Offset2D(0.35, 1),
  Offset2D(0.35, 0.65),
  Offset2D(0.65, 0.65),
  Offset2D(0.65, 1),
  Offset2D(1, 0.5),
  Offset2D(0.65, 0),
  Offset2D(0.65, 0.35),
];
const List<Offset2D> _calloutQuadArrow = [
  Offset2D(0.35, 0.35),
  Offset2D(0.35, 0.15),
  Offset2D(0.2, 0.15),
  Offset2D(0.5, 0),
  Offset2D(0.8, 0.15),
  Offset2D(0.65, 0.15),
  Offset2D(0.65, 0.35),
  Offset2D(0.85, 0.35),
  Offset2D(0.85, 0.2),
  Offset2D(1, 0.5),
  Offset2D(0.85, 0.8),
  Offset2D(0.85, 0.65),
  Offset2D(0.65, 0.65),
  Offset2D(0.65, 0.85),
  Offset2D(0.8, 0.85),
  Offset2D(0.5, 1),
  Offset2D(0.2, 0.85),
  Offset2D(0.35, 0.85),
  Offset2D(0.35, 0.65),
  Offset2D(0.15, 0.65),
  Offset2D(0.15, 0.8),
  Offset2D(0, 0.5),
  Offset2D(0.15, 0.2),
  Offset2D(0.15, 0.35),
];
const List<Offset2D> _tailedNotch = [
  Offset2D(0.18, 0.65),
  Offset2D(0.55, 0.65),
  Offset2D(0.55, 1),
  Offset2D(1, 0.5),
  Offset2D(0.55, 0),
  Offset2D(0.55, 0.35),
  Offset2D(0.18, 0.35),
  Offset2D(0, 0.5),
];
const List<Offset2D> _jumpIn = [
  Offset2D(0.15, 0),
  Offset2D(0.15, 0.45),
  Offset2D(0.55, 0.45),
  Offset2D(0.55, 0.15),
  Offset2D(1, 0.55),
  Offset2D(0.55, 0.95),
  Offset2D(0.55, 0.65),
  Offset2D(0, 0.65),
  Offset2D(0, 0),
];
const List<Offset2D> _orthoTriangle = [
  Offset2D(0, 1),
  Offset2D(0, 0),
  Offset2D(1, 0),
];
const List<Offset2D> _rectCallout = [
  Offset2D(0, 1),
  Offset2D(1, 1),
  Offset2D(1, 0.35),
  Offset2D(0.45, 0.35),
  Offset2D(0.28, 0),
  Offset2D(0.35, 0.35),
  Offset2D(0, 0.35),
];
const List<Offset2D> _frameCorner = [
  Offset2D(0, 1),
  Offset2D(1, 1),
  Offset2D(1, 0.55),
  Offset2D(0.45, 0.55),
  Offset2D(0.45, 0),
  Offset2D(0, 0),
];

/// Built-in stencils aligned with draw.io's default shape libraries
/// (`general` [=general+misc+advanced]; `uml;er;bpmn;flowchart;basic;arrows2`
/// — see drawio Sidebar.js `defaultEntries` / `configuration`). Every builder
/// uses whitelist geometry so shapes render and round-trip through the writer
/// without loss.
///
/// Groups are ordered most-used-first and tagged with [StencilGroup.expandAtWidth]
/// so the panel opens everyday libraries first, then Basic / Containers, then
/// UML / ER / BPMN / Misc / Advanced when the window is roomy.
final List<StencilGroup> kStencilGroups = <StencilGroup>[
  // drawio "General" — everyday primitives + common composites.
  StencilGroup('General', <Stencil>[
    Stencil('Rectangle', _rect),
    Stencil(
        'Rounded Rectangle',
        (id, cx, cy) => VsdxShapeFactory.roundedRectangle(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Text',
        (id, cx, cy) => VsdxShapeFactory.textBox(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 0.5, text: 'Text')),
    Stencil('Square', (id, cx, cy) => _rect(id, cx, cy, w: 1, h: 1)),
    Stencil('Ellipse', _ellipse),
    Stencil('Circle', (id, cx, cy) => _ellipse(id, cx, cy, w: 1, h: 1)),
    Stencil('Triangle', (id, cx, cy) => _poly(id, cx, cy, _triangle, w: 1, h: 1)),
    Stencil('Right Triangle',
        (id, cx, cy) => _poly(id, cx, cy, _rightTriangle, w: 1, h: 1)),
    Stencil('Diamond', (id, cx, cy) => _poly(id, cx, cy, _diamond)),
    Stencil('Parallelogram', (id, cx, cy) => _poly(id, cx, cy, _parallelogram)),
    Stencil('Trapezoid', (id, cx, cy) => _poly(id, cx, cy, _trapezoid)),
    Stencil('Pentagon', (id, cx, cy) => _poly(id, cx, cy, _pentagon, w: 1, h: 1)),
    Stencil('Hexagon', (id, cx, cy) => _poly(id, cx, cy, _hexagon)),
    Stencil('Octagon', (id, cx, cy) => _poly(id, cx, cy, _octagon, w: 1, h: 1)),
    Stencil('Process', _rect),
    Stencil(
        'Cylinder',
        (id, cx, cy) => VsdxShapeFactory.cylinder(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.3)),
    Stencil(
        'Cloud',
        (id, cx, cy) => VsdxShapeFactory.cloud(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.1)),
    Stencil(
        'Document',
        (id, cx, cy) => VsdxShapeFactory.document(
            id: id, pinX: cx, pinY: cy, width: _w, height: 1.1)),
    Stencil(
        'Cube',
        (id, cx, cy) => VsdxShapeFactory.cube(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil('Step', (id, cx, cy) => _poly(id, cx, cy, _step)),
    Stencil('Card', (id, cx, cy) => _poly(id, cx, cy, _card)),
    Stencil('Callout', (id, cx, cy) => _poly(id, cx, cy, _callout)),
    Stencil(
        'Note',
        (id, cx, cy) => VsdxShapeFactory.note(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Actor',
        (id, cx, cy) => VsdxShapeFactory.umlActor(
            id: id, pinX: cx, pinY: cy, width: 0.8, height: 1.4)),
    Stencil(
        'Or',
        (id, cx, cy) => VsdxShapeFactory.orGate(
            id: id, pinX: cx, pinY: cy, width: 1, height: 1)),
    Stencil(
        'And',
        (id, cx, cy) => VsdxShapeFactory.andGate(
            id: id, pinX: cx, pinY: cy, width: 1, height: 1)),
    Stencil(
        'Data Storage',
        (id, cx, cy) => VsdxShapeFactory.storedData(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Double Rectangle',
        (id, cx, cy) => VsdxShapeFactory.doubleRectangle(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Double Ellipse',
        (id, cx, cy) => VsdxShapeFactory.doubleEllipse(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil('Corner', (id, cx, cy) => _poly(id, cx, cy, _corner, w: 1, h: 1)),
    Stencil('Tee', (id, cx, cy) => _poly(id, cx, cy, _tee, w: 1, h: 1)),
    Stencil(
        'Container',
        (id, cx, cy) => VsdxShapeFactory.container(
            id: id, pinX: cx, pinY: cy, width: 2.2, height: 1.6)),
    Stencil(
        'Horizontal Container',
        (id, cx, cy) => VsdxShapeFactory.container(
            id: id, pinX: cx, pinY: cy, width: 2.6, height: 1.2)),
    Stencil(
        'Table',
        (id, cx, cy) => TableOps.assembleTable(
              tableId: id,
              pinX: cx,
              pinY: cy,
              width: 3.0,
              height: 2.0,
              rows: 3,
              cols: 3,
            )),
    Stencil(
        'Table 2×2',
        (id, cx, cy) => TableOps.assembleTable(
              tableId: id,
              pinX: cx,
              pinY: cy,
              width: 2.4,
              height: 1.6,
              rows: 2,
              cols: 2,
            )),
  ], expandAtWidth: 900),
  // drawio "Flowchart".
  StencilGroup('Flowchart', <Stencil>[
    Stencil('Process', _rect),
    Stencil('Decision', (id, cx, cy) => _poly(id, cx, cy, _diamond)),
    Stencil(
        'Terminator',
        (id, cx, cy) => VsdxShapeFactory.roundedRectangle(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h, radius: _h / 2)),
    Stencil(
        'Start',
        (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.9)),
    Stencil('Data', (id, cx, cy) => _poly(id, cx, cy, _parallelogram)),
    Stencil(
        'Predefined Process',
        (id, cx, cy) => VsdxShapeFactory.predefinedProcess(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Internal Storage',
        (id, cx, cy) => VsdxShapeFactory.internalStorage(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Document',
        (id, cx, cy) => VsdxShapeFactory.document(
            id: id, pinX: cx, pinY: cy, width: _w, height: 1.1)),
    Stencil(
        'Multi-Document',
        (id, cx, cy) => VsdxShapeFactory.multiDocument(
            id: id, pinX: cx, pinY: cy, width: _w, height: 1.2)),
    Stencil('Manual Input', (id, cx, cy) => _poly(id, cx, cy, _manualInput)),
    Stencil(
        'Manual Operation', (id, cx, cy) => _poly(id, cx, cy, _manualOperation)),
    Stencil('Preparation', (id, cx, cy) => _poly(id, cx, cy, _hexagon)),
    Stencil(
        'Delay',
        (id, cx, cy) => VsdxShapeFactory.delay(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Display',
        (id, cx, cy) => VsdxShapeFactory.display(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Tape',
        (id, cx, cy) => VsdxShapeFactory.tape(
            id: id, pinX: cx, pinY: cy, width: _w, height: 1.0)),
    Stencil(
        'Database',
        (id, cx, cy) => VsdxShapeFactory.cylinder(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.3)),
    Stencil(
        'Direct Data',
        (id, cx, cy) => VsdxShapeFactory.cylinder(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Stored Data',
        (id, cx, cy) => VsdxShapeFactory.storedData(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Sequential Data',
        (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil('Merge', (id, cx, cy) => _poly(id, cx, cy, _merge)),
    Stencil('Extract', (id, cx, cy) => _poly(id, cx, cy, _triangle, w: 1, h: 1)),
    Stencil('Collate', (id, cx, cy) => _poly(id, cx, cy, _collate, w: 1, h: 1)),
    Stencil(
        'Or',
        (id, cx, cy) => VsdxShapeFactory.orGate(
            id: id, pinX: cx, pinY: cy, width: 1, height: 1)),
    Stencil(
        'Summing Junction',
        (id, cx, cy) => VsdxShapeFactory.summingJunction(
            id: id, pinX: cx, pinY: cy, width: 1, height: 1)),
    Stencil(
        'Sort',
        (id, cx, cy) => VsdxShapeFactory.sort(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil('Loop Limit', (id, cx, cy) => _poly(id, cx, cy, _loopLimit)),
    Stencil('Off-Page Ref', (id, cx, cy) => _poly(id, cx, cy, _offPage, w: 1, h: 1)),
    Stencil(
        'On-Page Ref',
        (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id, pinX: cx, pinY: cy, width: 0.9, height: 0.9)),
    Stencil(
        'Annotation',
        (id, cx, cy) => VsdxShapeFactory.annotation(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.0)),
    Stencil(
        'Parallel Mode',
        (id, cx, cy) => VsdxShapeFactory.parallelMode(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.0)),
    Stencil('Transfer', (id, cx, cy) => _poly(id, cx, cy, _transfer)),
    Stencil('Card', (id, cx, cy) => _poly(id, cx, cy, _card)),
    Stencil('Step', (id, cx, cy) => _poly(id, cx, cy, _step)),
  ], expandAtWidth: 900),
  // drawio "Arrows" (arrows2) — everyday + stylised variants.
  StencilGroup('Arrows', <Stencil>[
    Stencil('Arrow Right', (id, cx, cy) => _poly(id, cx, cy, _arrowRight)),
    Stencil('Arrow Left', (id, cx, cy) => _poly(id, cx, cy, _arrowLeft)),
    Stencil('Arrow Up', (id, cx, cy) => _poly(id, cx, cy, _arrowUp, w: 1, h: 1)),
    Stencil('Arrow Down', (id, cx, cy) => _poly(id, cx, cy, _arrowDown, w: 1, h: 1)),
    Stencil('Double Arrow', (id, cx, cy) => _poly(id, cx, cy, _doubleArrow)),
    Stencil('Double Arrow Vertical',
        (id, cx, cy) => _poly(id, cx, cy, _doubleArrowV, w: 1, h: 1.2)),
    Stencil('Chevron', (id, cx, cy) => _poly(id, cx, cy, _chevron)),
    Stencil('Notched Arrow', (id, cx, cy) => _poly(id, cx, cy, _notchedArrow)),
    Stencil('Signal In', (id, cx, cy) => _poly(id, cx, cy, _signalIn)),
    Stencil('Notched Signal In',
        (id, cx, cy) => _poly(id, cx, cy, _notchedSignalIn)),
    Stencil('Slender Arrow', (id, cx, cy) => _poly(id, cx, cy, _slenderArrow)),
    Stencil('Slender Two Way',
        (id, cx, cy) => _poly(id, cx, cy, _slenderTwoWay)),
    Stencil('Stylised Arrow', (id, cx, cy) => _poly(id, cx, cy, _stylisedArrow)),
    Stencil('Sharp Arrow', (id, cx, cy) => _poly(id, cx, cy, _sharpArrow)),
    Stencil('Tailed Arrow', (id, cx, cy) => _poly(id, cx, cy, _tailedArrow)),
    Stencil('Tailed Arrow Notch',
        (id, cx, cy) => _poly(id, cx, cy, _tailedNotch)),
    Stencil('Striped Arrow', (id, cx, cy) => _poly(id, cx, cy, _stripedArrow)),
    Stencil('Bend Arrow', (id, cx, cy) => _poly(id, cx, cy, _bendArrow, w: 1.2, h: 1.2)),
    Stencil('Bend Double Arrow',
        (id, cx, cy) => _poly(id, cx, cy, _bendDoubleArrow, w: 1.2, h: 1.2)),
    Stencil('U Turn Arrow', (id, cx, cy) => _poly(id, cx, cy, _uTurnArrow, w: 1.1, h: 1.2)),
    Stencil('Jump In Arrow', (id, cx, cy) => _poly(id, cx, cy, _jumpIn, w: 1.2, h: 1.1)),
    Stencil('Callout Arrow', (id, cx, cy) => _poly(id, cx, cy, _calloutArrow)),
    Stencil('Callout Double Arrow',
        (id, cx, cy) => _poly(id, cx, cy, _calloutDoubleArrow)),
    Stencil('Callout Quad Arrow',
        (id, cx, cy) => _poly(id, cx, cy, _calloutQuadArrow, w: 1.2, h: 1.2)),
    Stencil('Quad Arrow', (id, cx, cy) => _poly(id, cx, cy, _quadArrow, w: 1.2, h: 1.2)),
    Stencil('Triad Arrow', (id, cx, cy) => _poly(id, cx, cy, _triadArrow, w: 1.2, h: 1.2)),
  ], expandAtWidth: 900),
  // drawio "Basic".
  StencilGroup('Basic', <Stencil>[
    Stencil('Star', (id, cx, cy) => _poly(id, cx, cy, _star, w: 1, h: 1)),
    Stencil('4 Point Star', (id, cx, cy) => _poly(id, cx, cy, _star4, w: 1, h: 1)),
    Stencil('6 Point Star', (id, cx, cy) => _poly(id, cx, cy, _star6, w: 1, h: 1)),
    Stencil('8 Point Star', (id, cx, cy) => _poly(id, cx, cy, _star8, w: 1, h: 1)),
    Stencil('Cross', (id, cx, cy) => _poly(id, cx, cy, _cross, w: 1, h: 1)),
    Stencil(
        'Heart',
        (id, cx, cy) => VsdxShapeFactory.heart(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.1)),
    Stencil('Lightning', (id, cx, cy) => _poly(id, cx, cy, _lightning, w: 1, h: 1.3)),
    Stencil('Flash', (id, cx, cy) => _poly(id, cx, cy, _lightning, w: 1, h: 1.3)),
    Stencil(
        'Half Circle',
        (id, cx, cy) => VsdxShapeFactory.halfCircle(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.8)),
    Stencil(
        'Wave',
        (id, cx, cy) => VsdxShapeFactory.wave(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 0.7)),
    Stencil('Banner', (id, cx, cy) => _poly(id, cx, cy, _banner)),
    Stencil('Pyramid', (id, cx, cy) => _poly(id, cx, cy, _pyramid, w: 1.2, h: 1.0)),
    Stencil('Moon', (id, cx, cy) => _poly(id, cx, cy, _moon, w: 1, h: 1)),
    Stencil('Sun', (id, cx, cy) => _poly(id, cx, cy, _sun, w: 1.2, h: 1.2)),
    Stencil(
        'Cone',
        (id, cx, cy) => VsdxShapeFactory.cone(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'Drop',
        (id, cx, cy) => VsdxShapeFactory.drop(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.3)),
    Stencil(
        'Pointed Oval',
        (id, cx, cy) => VsdxShapeFactory.pointedOval(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 0.9)),
    Stencil(
        'Pie',
        (id, cx, cy) => VsdxShapeFactory.pie(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Smiley',
        (id, cx, cy) => VsdxShapeFactory.smiley(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Neutral Smiley',
        (id, cx, cy) => VsdxShapeFactory.neutralSmiley(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Sad Smiley',
        (id, cx, cy) => VsdxShapeFactory.sadSmiley(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil('Tick', (id, cx, cy) => _poly(id, cx, cy, _tick, w: 1, h: 1)),
    Stencil('X', (id, cx, cy) => _poly(id, cx, cy, _xMark, w: 1, h: 1)),
    Stencil('Plaque', (id, cx, cy) => _poly(id, cx, cy, _plaque, w: 1.3, h: 1.0)),
    Stencil('Diagonal Stripe',
        (id, cx, cy) => _poly(id, cx, cy, _diagStripe, w: 1.2, h: 0.8)),
    Stencil('Orthogonal Triangle',
        (id, cx, cy) => _poly(id, cx, cy, _orthoTriangle, w: 1, h: 1)),
    Stencil('Acute Triangle',
        (id, cx, cy) => _poly(id, cx, cy, _acuteTriangle, w: 1, h: 1)),
    Stencil('Obtuse Triangle',
        (id, cx, cy) => _poly(id, cx, cy, _obtuseTriangle, w: 1.3, h: 1)),
    Stencil('Oval Callout',
        (id, cx, cy) => _poly(id, cx, cy, _ovalCallout, w: 1.4, h: 1.1)),
    Stencil('Rectangular Callout',
        (id, cx, cy) => _poly(id, cx, cy, _rectCallout, w: 1.4, h: 1.1)),
    Stencil('Loud Callout', (id, cx, cy) => _poly(id, cx, cy, _callout, w: 1.4, h: 1.1)),
    Stencil(
        'Cloud Callout',
        (id, cx, cy) => VsdxShapeFactory.cloud(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.1)),
    Stencil(
        'Cloud Rectangle',
        (id, cx, cy) => VsdxShapeFactory.cloud(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.0)),
    Stencil(
        'Document',
        (id, cx, cy) => VsdxShapeFactory.document(
            id: id, pinX: cx, pinY: cy, width: _w, height: 1.1)),
    Stencil(
        'Donut',
        (id, cx, cy) => VsdxShapeFactory.donut(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Frame',
        (id, cx, cy) => VsdxShapeFactory.frame(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil('Frame Corner',
        (id, cx, cy) => _poly(id, cx, cy, _frameCorner, w: 1.2, h: 1.2)),
    Stencil(
        'No Symbol',
        (id, cx, cy) => VsdxShapeFactory.noSymbol(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Partial Rectangle',
        (id, cx, cy) => VsdxShapeFactory.partialRectangle(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Rectangle with diagonal fill',
        (id, cx, cy) => VsdxShapeFactory.rectWithHatch(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h, style: 'diag')),
    Stencil(
        'Rectangle with reverse diagonal fill',
        (id, cx, cy) => VsdxShapeFactory.rectWithHatch(
            id: id,
            pinX: cx,
            pinY: cy,
            width: _w,
            height: _h,
            style: 'diagRev')),
    Stencil(
        'Rectangle with vertical fill',
        (id, cx, cy) => VsdxShapeFactory.rectWithHatch(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h, style: 'vert')),
    Stencil(
        'Rectangle with horizontal fill',
        (id, cx, cy) => VsdxShapeFactory.rectWithHatch(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h, style: 'hor')),
    Stencil(
        'Rectangle with grid fill',
        (id, cx, cy) => VsdxShapeFactory.rectWithHatch(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h, style: 'grid')),
    Stencil(
        'Rectangle with diagonal grid fill',
        (id, cx, cy) => VsdxShapeFactory.rectWithHatch(
            id: id,
            pinX: cx,
            pinY: cy,
            width: _w,
            height: _h,
            style: 'diagGrid')),
    Stencil(
        'Diagonal Snip Rectangle',
        (id, cx, cy) => VsdxShapeFactory.diagonalSnipRectangle(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Diagonal Rounded Rectangle',
        (id, cx, cy) => VsdxShapeFactory.diagonalRoundedRectangle(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Corner Rounded Rectangle',
        (id, cx, cy) => VsdxShapeFactory.cornerRoundedRectangle(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Rounded Rectangle (three corners)',
        (id, cx, cy) => VsdxShapeFactory.threeCornerRoundedRectangle(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Layered Rectangle',
        (id, cx, cy) => VsdxShapeFactory.layeredRectangle(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Rounded Frame',
        (id, cx, cy) => VsdxShapeFactory.roundedFrame(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Plaque Frame',
        (id, cx, cy) => VsdxShapeFactory.plaqueFrame(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Button',
        (id, cx, cy) => VsdxShapeFactory.button(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.0)),
    Stencil(
        'Button (shaded)',
        (id, cx, cy) => VsdxShapeFactory.button(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.0)),
    Stencil(
        'Arc',
        (id, cx, cy) => VsdxShapeFactory.arc(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.9)),
    Stencil(
        'Partial Concentric Ellipse',
        (id, cx, cy) => VsdxShapeFactory.partialConcentricEllipse(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.0)),
    Stencil(
        'Message',
        (id, cx, cy) => VsdxShapeFactory.message(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.9)),
    Stencil(
        'Tag',
        (id, cx, cy) => VsdxShapeFactory.tag(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.8)),
    Stencil(
        'Bang',
        (id, cx, cy) => VsdxShapeFactory.bang(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Isometric Cube',
        (id, cx, cy) => VsdxShapeFactory.cube(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Cylinder Stack',
        (id, cx, cy) => VsdxShapeFactory.cylinderStack(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.4)),
    Stencil('Pentagon', (id, cx, cy) => _poly(id, cx, cy, _pentagon, w: 1, h: 1)),
    Stencil('Octagon', (id, cx, cy) => _poly(id, cx, cy, _octagon, w: 1, h: 1)),
  ], expandAtWidth: 1100),
  // Containers / 3-D storage.
  StencilGroup('Containers', <Stencil>[
    Stencil(
        'Cylinder',
        (id, cx, cy) => VsdxShapeFactory.cylinder(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.3)),
    Stencil(
        'Cube',
        (id, cx, cy) => VsdxShapeFactory.cube(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Cloud',
        (id, cx, cy) => VsdxShapeFactory.cloud(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.1)),
    Stencil(
        'Document',
        (id, cx, cy) => VsdxShapeFactory.document(
            id: id, pinX: cx, pinY: cy, width: _w, height: 1.1)),
    Stencil('Callout', (id, cx, cy) => _poly(id, cx, cy, _callout)),
    Stencil(
        'Data Storage',
        (id, cx, cy) => VsdxShapeFactory.storedData(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Cylinder Stack',
        (id, cx, cy) => VsdxShapeFactory.cylinderStack(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.4)),
    Stencil(
        'Layered Rectangle',
        (id, cx, cy) => VsdxShapeFactory.layeredRectangle(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Container',
        (id, cx, cy) => VsdxShapeFactory.container(
            id: id, pinX: cx, pinY: cy, width: 2.2, height: 1.6)),
  ], expandAtWidth: 1100),
  // drawio "UML" (classic palette subset).
  StencilGroup('UML', <Stencil>[
    Stencil(
        'Actor',
        (id, cx, cy) => VsdxShapeFactory.umlActor(
            id: id, pinX: cx, pinY: cy, width: 0.8, height: 1.4)),
    Stencil('Use Case', (id, cx, cy) => _ellipse(id, cx, cy, w: 1.7, h: 0.9)),
    Stencil(
        'Class',
        (id, cx, cy) => VsdxShapeFactory.umlClass(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.2)),
    Stencil('Object', (id, cx, cy) => _rect(id, cx, cy, w: 1.5, h: 0.9)),
    Stencil('Block', (id, cx, cy) => _rect(id, cx, cy, w: 1.5, h: 1.0)),
    Stencil(
        'Interface',
        (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id, pinX: cx, pinY: cy, width: 0.9, height: 0.9)),
    Stencil(
        'Provided Interface',
        (id, cx, cy) => VsdxShapeFactory.providedInterface(
            id: id, pinX: cx, pinY: cy, width: 0.55, height: 0.55)),
    Stencil(
        'Required Interface',
        (id, cx, cy) => VsdxShapeFactory.requiredInterface(
            id: id, pinX: cx, pinY: cy, width: 0.55, height: 0.7)),
    Stencil(
        'Package',
        (id, cx, cy) => VsdxShapeFactory.umlPackage(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.1)),
    Stencil(
        'Module',
        (id, cx, cy) => VsdxShapeFactory.umlModule(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.1)),
    Stencil(
        'Component',
        (id, cx, cy) => VsdxShapeFactory.umlComponent(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.1)),
    Stencil(
        'Boundary',
        (id, cx, cy) => VsdxShapeFactory.umlBoundary(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.0)),
    Stencil(
        'Control',
        (id, cx, cy) => VsdxShapeFactory.umlControl(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Entity',
        (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Note',
        (id, cx, cy) => VsdxShapeFactory.note(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Node',
        (id, cx, cy) => VsdxShapeFactory.cube(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.1)),
    Stencil(
        'Lifeline',
        (id, cx, cy) => VsdxShapeFactory.umlLifeline(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 2.2)),
    Stencil(
        'Actor Lifeline',
        (id, cx, cy) => VsdxShapeFactory.umlActorLifeline(
            id: id, pinX: cx, pinY: cy, width: 0.9, height: 2.2)),
    Stencil(
        'Boundary Lifeline',
        (id, cx, cy) => VsdxShapeFactory.umlStereoLifeline(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 1.0,
            height: 2.2,
            kind: 'boundary')),
    Stencil(
        'Entity Lifeline',
        (id, cx, cy) => VsdxShapeFactory.umlStereoLifeline(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 0.9,
            height: 2.2,
            kind: 'entity')),
    Stencil(
        'Control Lifeline',
        (id, cx, cy) => VsdxShapeFactory.umlStereoLifeline(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 0.9,
            height: 2.2,
            kind: 'control')),
    Stencil(
        'Activation Bar',
        (id, cx, cy) => VsdxShapeFactory.umlActivationBar(
            id: id, pinX: cx, pinY: cy, width: 0.28, height: 1.2)),
    Stencil(
        'Destruction',
        (id, cx, cy) => VsdxShapeFactory.umlDestruction(
            id: id, pinX: cx, pinY: cy, width: 0.7, height: 0.7)),
    Stencil(
        'Frame',
        (id, cx, cy) => VsdxShapeFactory.umlFrame(
            id: id, pinX: cx, pinY: cy, width: 2.2, height: 1.6)),
    Stencil(
        'Start',
        (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id, pinX: cx, pinY: cy, width: 0.7, height: 0.7)),
    Stencil(
        'End',
        (id, cx, cy) => VsdxShapeFactory.doubleEllipse(
            id: id, pinX: cx, pinY: cy, width: 0.8, height: 0.8)),
    Stencil(
        'Fork / Join',
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.18)),
  ], expandAtWidth: 1280),
  // drawio "ER" — entity-relationship essentials.
  StencilGroup('ER', <Stencil>[
    Stencil('Entity', _rect),
    Stencil(
        'Entity (Rounded)',
        (id, cx, cy) => VsdxShapeFactory.roundedRectangle(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Weak Entity',
        (id, cx, cy) => VsdxShapeFactory.weakEntity(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil('Attribute', (id, cx, cy) => _ellipse(id, cx, cy, w: 1.4, h: 0.8)),
    Stencil(
        'Key Attribute',
        (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.8)),
    Stencil(
        'Weak Key Attribute',
        (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.8)),
    Stencil(
        'Multivalue Attribute',
        (id, cx, cy) => VsdxShapeFactory.doubleEllipse(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.9)),
    Stencil(
        'Derived Attribute',
        (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.8)),
    Stencil('Relationship', (id, cx, cy) => _poly(id, cx, cy, _diamond)),
    Stencil(
        'Identifying Relationship',
        (id, cx, cy) => VsdxShapeFactory.identifyingRelationship(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.0)),
    Stencil(
        'Associative Entity',
        (id, cx, cy) => VsdxShapeFactory.associativeEntity(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.0)),
    Stencil(
        'Cloud',
        (id, cx, cy) => VsdxShapeFactory.cloud(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.1)),
    Stencil(
        'Note',
        (id, cx, cy) => VsdxShapeFactory.note(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
  ], expandAtWidth: 1280),
  // drawio "BPMN" — classic bpmn.xml essentials + common events/gateways.
  StencilGroup('BPMN', <Stencil>[
    Stencil(
        'Task',
        (id, cx, cy) => VsdxShapeFactory.bpmnTask(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.0)),
    Stencil(
        'User Task',
        (id, cx, cy) => VsdxShapeFactory.bpmnTask(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.0)),
    Stencil(
        'Service Task',
        (id, cx, cy) => VsdxShapeFactory.bpmnTask(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.0)),
    Stencil(
        'Script Task',
        (id, cx, cy) => VsdxShapeFactory.bpmnTask(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.0)),
    Stencil(
        'Manual Task',
        (id, cx, cy) => VsdxShapeFactory.bpmnTask(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.0)),
    Stencil(
        'Business Rule Task',
        (id, cx, cy) => VsdxShapeFactory.bpmnTask(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.0)),
    Stencil(
        'Gateway',
        (id, cx, cy) => VsdxShapeFactory.bpmnGateway(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Exclusive Gateway',
        (id, cx, cy) => VsdxShapeFactory.bpmnGateway(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Parallel Gateway',
        (id, cx, cy) => VsdxShapeFactory.bpmnParallelGateway(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Inclusive Gateway',
        (id, cx, cy) => VsdxShapeFactory.bpmnInclusiveGateway(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Complex Gateway',
        (id, cx, cy) => VsdxShapeFactory.bpmnComplexGateway(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Event-Based Gateway',
        (id, cx, cy) => VsdxShapeFactory.bpmnEventBasedGateway(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Start Event',
        (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id, pinX: cx, pinY: cy, width: 0.9, height: 0.9)),
    Stencil(
        'Message Start',
        (id, cx, cy) => VsdxShapeFactory.bpmnMessageEvent(
            id: id, pinX: cx, pinY: cy, width: 0.95, height: 0.95)),
    Stencil(
        'Timer Start',
        (id, cx, cy) => VsdxShapeFactory.bpmnTimerEvent(
            id: id, pinX: cx, pinY: cy, width: 0.95, height: 0.95)),
    Stencil(
        'Intermediate Event',
        (id, cx, cy) => VsdxShapeFactory.bpmnEvent(
            id: id, pinX: cx, pinY: cy, width: 0.95, height: 0.95)),
    Stencil(
        'Message Intermediate',
        (id, cx, cy) => VsdxShapeFactory.bpmnMessageEvent(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 0.95,
            height: 0.95,
            intermediate: true)),
    Stencil(
        'Timer Intermediate',
        (id, cx, cy) => VsdxShapeFactory.bpmnTimerEvent(
            id: id, pinX: cx, pinY: cy, width: 0.95, height: 0.95)),
    Stencil(
        'Cancel Intermediate',
        (id, cx, cy) => VsdxShapeFactory.bpmnCancelEvent(
            id: id, pinX: cx, pinY: cy, width: 0.95, height: 0.95)),
    Stencil(
        'Link Intermediate',
        (id, cx, cy) => VsdxShapeFactory.bpmnLinkEvent(
            id: id, pinX: cx, pinY: cy, width: 0.95, height: 0.95)),
    Stencil(
        'Compensation Intermediate',
        (id, cx, cy) => VsdxShapeFactory.bpmnCompensation(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 0.95,
            height: 0.95,
            asEvent: true)),
    Stencil(
        'Multiple Intermediate',
        (id, cx, cy) => VsdxShapeFactory.bpmnMultipleEvent(
            id: id, pinX: cx, pinY: cy, width: 0.95, height: 0.95)),
    Stencil(
        'Rule Intermediate',
        (id, cx, cy) => VsdxShapeFactory.bpmnRuleEvent(
            id: id, pinX: cx, pinY: cy, width: 0.95, height: 0.95)),
    Stencil(
        'End Event',
        (id, cx, cy) => VsdxShapeFactory.bpmnEvent(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.0)),
    Stencil(
        'Terminate',
        (id, cx, cy) => VsdxShapeFactory.bpmnTerminateEvent(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.0)),
    Stencil(
        'Compensation',
        (id, cx, cy) => VsdxShapeFactory.bpmnCompensation(
            id: id, pinX: cx, pinY: cy, width: 0.9, height: 0.7)),
    Stencil(
        'Loop Marker',
        (id, cx, cy) => VsdxShapeFactory.bpmnLoopMarker(
            id: id, pinX: cx, pinY: cy, width: 0.7, height: 0.55)),
    Stencil(
        'Multiple Instances',
        (id, cx, cy) => VsdxShapeFactory.bpmnMultiInstance(
            id: id, pinX: cx, pinY: cy, width: 0.7, height: 0.55)),
    Stencil(
        'Ad Hoc',
        (id, cx, cy) => VsdxShapeFactory.bpmnAdHoc(
            id: id, pinX: cx, pinY: cy, width: 0.8, height: 0.45)),
    Stencil(
        'Data Object',
        (id, cx, cy) => VsdxShapeFactory.document(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.2)),
    Stencil(
        'Data Store',
        (id, cx, cy) => VsdxShapeFactory.cylinder(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 0.9)),
    Stencil(
        'Message',
        (id, cx, cy) => VsdxShapeFactory.message(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 0.8)),
    Stencil(
        'Pool',
        (id, cx, cy) => SwimlaneOps.assemblePool(
              poolId: id,
              pinX: cx,
              pinY: cy,
              width: 4.0,
              height: 2.8,
              laneCount: 2,
              horizontal: true,
            )),
    Stencil(
        'Horizontal Lane',
        (id, cx, cy) => SwimlaneOps.lane(
              id: id,
              pinX: cx,
              pinY: cy,
              width: 2.6,
              height: 1.0,
              horizontal: true,
              text: 'Lane',
            )),
    Stencil(
        'Vertical Lane',
        (id, cx, cy) => SwimlaneOps.lane(
              id: id,
              pinX: cx,
              pinY: cy,
              width: 1.2,
              height: 2.2,
              horizontal: false,
              text: 'Lane',
            )),
    Stencil(
        'Vertical Pool',
        (id, cx, cy) => SwimlaneOps.assemblePool(
              poolId: id,
              pinX: cx,
              pinY: cy,
              width: 2.8,
              height: 4.0,
              laneCount: 2,
              horizontal: false,
              name: 'Pool',
            )),
    Stencil(
        'Conversation',
        (id, cx, cy) => VsdxShapeFactory.bpmnConversation(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 0.9)),
    Stencil(
        'Annotation',
        (id, cx, cy) => VsdxShapeFactory.annotation(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.0)),
  ], expandAtWidth: 1280),
  // Misc (bundled with drawio "general" pack via libs: misc).
  StencilGroup('Misc', <Stencil>[
    Stencil(
        'Autosize Title',
        (id, cx, cy) => VsdxShapeFactory.textBox(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 1.6,
            height: 0.5,
            text: 'Title')),
    Stencil(
        'Unordered List',
        (id, cx, cy) => VsdxShapeFactory.textBox(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 1.4,
            height: 1.1,
            text: '• Item 1\n• Item 2\n• Item 3')),
    Stencil(
        'Ordered List',
        (id, cx, cy) => VsdxShapeFactory.textBox(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 1.4,
            height: 1.1,
            text: '1. Item 1\n2. Item 2\n3. Item 3')),
    Stencil(
        'Left Curly Bracket',
        (id, cx, cy) => VsdxShapeFactory.curlyBracket(
            id: id, pinX: cx, pinY: cy, width: 0.45, height: 1.6)),
    Stencil(
        'Right Curly Bracket',
        (id, cx, cy) => VsdxShapeFactory.curlyBracket(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 0.45,
            height: 1.6,
            flipH: true)),
    Stencil(
        'Horizontal Line',
        (id, cx, cy) => VsdxShapeFactory.line(
            id: id, ax: cx - 0.8, ay: cy, bx: cx + 0.8, by: cy)),
    Stencil(
        'Vertical Line',
        (id, cx, cy) => VsdxShapeFactory.line(
            id: id, ax: cx, ay: cy - 0.8, bx: cx, by: cy + 0.8)),
    Stencil(
        'Horizontal Backbone',
        (id, cx, cy) => VsdxShapeFactory.backbone(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 0.22)),
    Stencil(
        'Vertical Backbone',
        (id, cx, cy) => VsdxShapeFactory.backbone(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 0.22,
            height: 1.8,
            vertical: true)),
    Stencil(
        'Horizontal Crossbar',
        (id, cx, cy) => VsdxShapeFactory.crossbar(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 0.35)),
    Stencil(
        'Vertical Crossbar',
        (id, cx, cy) => VsdxShapeFactory.crossbar(
            id: id,
            pinX: cx,
            pinY: cy,
            width: 0.35,
            height: 1.6,
            vertical: true)),
    Stencil(
        'Zigzag',
        (id, cx, cy) => VsdxShapeFactory.zigzag(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 0.7)),
    Stencil(
        'Waypoint',
        (id, cx, cy) => VsdxShapeFactory.waypoint(
            id: id, pinX: cx, pinY: cy, width: 0.25, height: 0.25)),
    Stencil(
        'Arc',
        (id, cx, cy) => VsdxShapeFactory.arc(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.9)),
    Stencil(
        'Partial Rectangle',
        (id, cx, cy) => VsdxShapeFactory.partialRectangle(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Isometric Cube',
        (id, cx, cy) => VsdxShapeFactory.cube(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Isometric Square',
        (id, cx, cy) => VsdxShapeFactory.isometricSquare(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.9)),
    Stencil(
        'Label 1',
        (id, cx, cy) => VsdxShapeFactory.textBox(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 0.7, text: 'Label')),
    Stencil(
        'Label 2',
        (id, cx, cy) => VsdxShapeFactory.textBox(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 0.9, text: 'Label')),
    Stencil(
        'Note',
        (id, cx, cy) => VsdxShapeFactory.note(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.4)),
  ], expandAtWidth: 1280),
  // Misc composites + drawio Advanced (bundled with general pack).
  StencilGroup('Advanced', <Stencil>[
    Stencil(
        'Double Rectangle',
        (id, cx, cy) => VsdxShapeFactory.doubleRectangle(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Double Rounded Rectangle',
        (id, cx, cy) => VsdxShapeFactory.doubleRoundedRectangle(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Double Ellipse',
        (id, cx, cy) => VsdxShapeFactory.doubleEllipse(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Double Square',
        (id, cx, cy) => VsdxShapeFactory.doubleRectangle(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Double Circle',
        (id, cx, cy) => VsdxShapeFactory.doubleEllipse(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Tape Data',
        (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil('Manual Input', (id, cx, cy) => _poly(id, cx, cy, _manualInput)),
    Stencil('Loop Limit', (id, cx, cy) => _poly(id, cx, cy, _loopLimit)),
    Stencil('Off Page Connector',
        (id, cx, cy) => _poly(id, cx, cy, _offPage, w: 1, h: 1)),
    Stencil(
        'Delay',
        (id, cx, cy) => VsdxShapeFactory.delay(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Display',
        (id, cx, cy) => VsdxShapeFactory.display(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil('Arrow Left', (id, cx, cy) => _poly(id, cx, cy, _arrowLeft)),
    Stencil('Arrow Right', (id, cx, cy) => _poly(id, cx, cy, _arrowRight)),
    Stencil('Arrow Up', (id, cx, cy) => _poly(id, cx, cy, _arrowUp, w: 1, h: 1)),
    Stencil('Arrow Down', (id, cx, cy) => _poly(id, cx, cy, _arrowDown, w: 1, h: 1)),
    Stencil('Double Arrow', (id, cx, cy) => _poly(id, cx, cy, _doubleArrow)),
    Stencil('Double Arrow Vertical',
        (id, cx, cy) => _poly(id, cx, cy, _doubleArrowV, w: 1, h: 1.2)),
    Stencil(
        'User',
        (id, cx, cy) => VsdxShapeFactory.umlActor(
            id: id, pinX: cx, pinY: cy, width: 0.8, height: 1.4)),
    Stencil('Cross', (id, cx, cy) => _poly(id, cx, cy, _cross, w: 1, h: 1)),
    Stencil('Corner', (id, cx, cy) => _poly(id, cx, cy, _corner, w: 1, h: 1)),
    Stencil('Tee', (id, cx, cy) => _poly(id, cx, cy, _tee, w: 1, h: 1)),
    Stencil(
        'Data Store',
        (id, cx, cy) => VsdxShapeFactory.cylinder(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 0.9)),
    Stencil(
        'Or',
        (id, cx, cy) => VsdxShapeFactory.orGate(
            id: id, pinX: cx, pinY: cy, width: 1, height: 1)),
    Stencil(
        'Sum',
        (id, cx, cy) => VsdxShapeFactory.summingJunction(
            id: id, pinX: cx, pinY: cy, width: 1, height: 1)),
    Stencil(
        'Ellipse with horizontal divider',
        (id, cx, cy) => VsdxShapeFactory.ellipseDividerH(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.0)),
    Stencil(
        'Ellipse with vertical divider',
        (id, cx, cy) => VsdxShapeFactory.ellipseDividerV(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.4)),
    Stencil(
        'Sort',
        (id, cx, cy) => VsdxShapeFactory.sort(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil('Collate', (id, cx, cy) => _poly(id, cx, cy, _collate, w: 1, h: 1)),
    Stencil('Switch', (id, cx, cy) => _poly(id, cx, cy, _switchShape, w: 1.3, h: 1.0)),
    Stencil(
        'Process Bar',
        (id, cx, cy) => VsdxShapeFactory.processBar(
            id: id, pinX: cx, pinY: cy, width: 2.4, height: 0.7)),
    Stencil(
        'Container',
        (id, cx, cy) => VsdxShapeFactory.container(
            id: id, pinX: cx, pinY: cy, width: 2.2, height: 1.6)),
    Stencil(
        'List Item',
        (id, cx, cy) => VsdxShapeFactory.listItem(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.4)),
    Stencil(
        'Layered Rectangle',
        (id, cx, cy) => VsdxShapeFactory.layeredRectangle(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'Frame',
        (id, cx, cy) => VsdxShapeFactory.frame(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil(
        'No Symbol',
        (id, cx, cy) => VsdxShapeFactory.noSymbol(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Partial Rectangle',
        (id, cx, cy) => VsdxShapeFactory.partialRectangle(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
  ], expandAtWidth: 1280),
];

/// Flattened view of every stencil (used for search / lookups).
final List<Stencil> kStencils = <Stencil>[
  for (final g in kStencilGroups) ...g.stencils,
];
