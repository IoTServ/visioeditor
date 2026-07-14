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
  const StencilGroup(this.name, this.stencils);

  final String name;
  final List<Stencil> stencils;
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

/// Built-in stencils grouped like drawio's shape libraries. Every builder uses
/// polygon / ellipse / rounded-rect / elliptical-arc geometry, so each shape
/// renders and round-trips through the writer without loss.
final List<StencilGroup> kStencilGroups = <StencilGroup>[
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
    Stencil('Ellipse', _ellipse),
    Stencil('Square', (id, cx, cy) => _rect(id, cx, cy, w: 1, h: 1)),
    Stencil('Circle', (id, cx, cy) => _ellipse(id, cx, cy, w: 1, h: 1)),
    Stencil('Diamond', (id, cx, cy) => _poly(id, cx, cy, _diamond)),
    Stencil('Parallelogram', (id, cx, cy) => _poly(id, cx, cy, _parallelogram)),
    Stencil('Triangle', (id, cx, cy) => _poly(id, cx, cy, _triangle, w: 1, h: 1)),
    Stencil('Right Triangle',
        (id, cx, cy) => _poly(id, cx, cy, _rightTriangle, w: 1, h: 1)),
    Stencil('Pentagon', (id, cx, cy) => _poly(id, cx, cy, _pentagon, w: 1, h: 1)),
    Stencil('Hexagon', (id, cx, cy) => _poly(id, cx, cy, _hexagon)),
    Stencil('Octagon', (id, cx, cy) => _poly(id, cx, cy, _octagon, w: 1, h: 1)),
    Stencil('Trapezoid', (id, cx, cy) => _poly(id, cx, cy, _trapezoid)),
    Stencil('Cross', (id, cx, cy) => _poly(id, cx, cy, _cross, w: 1, h: 1)),
    Stencil('Star', (id, cx, cy) => _poly(id, cx, cy, _star, w: 1, h: 1)),
    Stencil(
        'Cylinder',
        (id, cx, cy) => VsdxShapeFactory.cylinder(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.3)),
    Stencil(
        'Cube',
        (id, cx, cy) => VsdxShapeFactory.cube(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Document',
        (id, cx, cy) => VsdxShapeFactory.document(
            id: id, pinX: cx, pinY: cy, width: _w, height: 1.1)),
    Stencil('Card', (id, cx, cy) => _poly(id, cx, cy, _card)),
    Stencil('Callout', (id, cx, cy) => _poly(id, cx, cy, _callout)),
    Stencil('Step', (id, cx, cy) => _poly(id, cx, cy, _step)),
    Stencil(
        'Cloud',
        (id, cx, cy) => VsdxShapeFactory.cloud(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.1)),
    Stencil('Lightning', (id, cx, cy) => _poly(id, cx, cy, _lightning, w: 1, h: 1.3)),
    Stencil(
        'Heart',
        (id, cx, cy) => VsdxShapeFactory.heart(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.1)),
  ]),
  StencilGroup('Flowchart', <Stencil>[
    Stencil('Process', _rect),
    Stencil('Decision', (id, cx, cy) => _poly(id, cx, cy, _diamond)),
    Stencil(
        'Terminator',
        (id, cx, cy) => VsdxShapeFactory.roundedRectangle(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h, radius: _h / 2)),
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
    Stencil('Manual Input', (id, cx, cy) => _poly(id, cx, cy, _manualInput)),
    Stencil(
        'Manual Operation', (id, cx, cy) => _poly(id, cx, cy, _manualOperation)),
    Stencil('Preparation', (id, cx, cy) => _poly(id, cx, cy, _hexagon)),
    Stencil(
        'Delay',
        (id, cx, cy) => VsdxShapeFactory.delay(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil('Off-Page Ref', (id, cx, cy) => _poly(id, cx, cy, _offPage, w: 1, h: 1)),
    Stencil('Card', (id, cx, cy) => _poly(id, cx, cy, _card)),
    Stencil(
        'Display',
        (id, cx, cy) => VsdxShapeFactory.display(
            id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
    Stencil('Merge', (id, cx, cy) => _poly(id, cx, cy, _merge)),
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
  ]),
  StencilGroup('Arrows', <Stencil>[
    Stencil('Arrow Right', (id, cx, cy) => _poly(id, cx, cy, _arrowRight)),
    Stencil('Arrow Left', (id, cx, cy) => _poly(id, cx, cy, _arrowLeft)),
    Stencil('Arrow Up', (id, cx, cy) => _poly(id, cx, cy, _arrowUp, w: 1, h: 1)),
    Stencil('Arrow Down', (id, cx, cy) => _poly(id, cx, cy, _arrowDown, w: 1, h: 1)),
    Stencil('Double Arrow', (id, cx, cy) => _poly(id, cx, cy, _doubleArrow)),
  ]),
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
    Stencil(
        'Package',
        (id, cx, cy) => VsdxShapeFactory.umlPackage(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.1)),
    Stencil(
        'Note',
        (id, cx, cy) => VsdxShapeFactory.note(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Node',
        (id, cx, cy) => VsdxShapeFactory.cube(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.1)),
  ]),
];

/// Flattened view of every stencil (used for search / lookups).
final List<Stencil> kStencils = <Stencil>[
  for (final g in kStencilGroups) ...g.stencils,
];
