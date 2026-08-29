import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

import 'stencil_styles.dart';

export 'stencil_styles.dart';

part 'drawio_xml_stencils.dart';
part 'generated/drawio_js_stencil_data.g.dart';
part 'generated/drawio_xml_stencil_data.g.dart';

/// A palette entry: a named builder that produces a shape at a given page-inch
/// centre. The shapes panel renders a **live geometry thumbnail** (built via
/// `lib/render/path_builder.dart`), so no icon is needed — the preview always
/// matches what actually drops on the canvas.
class Stencil {
  Stencil(
    this.name,
    VsdxShape Function(int id, double cx, double cy) build, {
    this.colors,
    this.group,
  }) : _rawBuild = build;

  final String name;

  /// Optional explicit colours; otherwise resolved from [name] / [group].
  final StencilColors? colors;

  /// Owning library name (Flowchart, AWS, …) used for group palette lookup.
  final String? group;

  final VsdxShape Function(int id, double cx, double cy) _rawBuild;

  /// Build a shape at ([cx],[cy]) with the stencil's default fill/line applied.
  VsdxShape build(int id, double cx, double cy) {
    final raw = _rawBuild(id, cx, cy);
    final resolved = resolveStencilColors(
      explicit: colors,
      name: name,
      group: group,
    );
    final styled = applyStencilStyle(raw, colors: resolved);
    return strokeNestedFillsOnShapeForLibvisio(
      styled,
      keepHoles: stencilKeepsLibvisioEvenoddHoles(name),
    );
  }

  Stencil withGroup(String groupName) => Stencil(
        name,
        _rawBuild,
        colors: colors,
        group: groupName,
      );
}

/// A named group of stencils — drawio's shape-library sections (General,
/// Flowchart, Arrows …). The panel renders one collapsible header per group.
class StencilGroup {
  StencilGroup(this.name, List<Stencil> stencils,
      {this.expandAtWidth = double.infinity})
      : stencils = List<Stencil>.unmodifiable(
          stencils.map((s) => s.group == name ? s : s.withGroup(name)),
        );

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
final List<StencilGroup> _builtInStencilGroups = <StencilGroup>[
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
    Stencil(
        'Parallelepiped',
        (id, cx, cy) => VsdxShapeFactory.parallelepiped(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.0)),
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
        'List',
        (id, cx, cy) => VsdxShapeFactory.list(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.4)),
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
    Stencil(
        'Rounded Rectangular Callout',
        (id, cx, cy) => VsdxShapeFactory.roundedRectangularCallout(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.2)),
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
        'Parallelepiped',
        (id, cx, cy) => VsdxShapeFactory.parallelepiped(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.0)),
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
        'Partial Rectangle',
        (id, cx, cy) => VsdxShapeFactory.partialRectangle(
            id: id,
            pinX: cx,
            pinY: cy,
            width: _w,
            height: _h,
            top: true,
            bottom: true,
            left: false,
            right: false)),
    Stencil(
        'Partial Rectangle',
        (id, cx, cy) => VsdxShapeFactory.partialRectangle(
            id: id,
            pinX: cx,
            pinY: cy,
            width: _w,
            height: _h,
            top: false,
            bottom: false,
            left: true,
            right: true)),
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
    Stencil(
        'Vertical List',
        (id, cx, cy) => VsdxShapeFactory.list(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.4)),
    Stencil(
        'Image',
        (id, cx, cy) => VsdxShapeFactory.imagePlaceholder(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.1)),
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
        'List',
        (id, cx, cy) => VsdxShapeFactory.list(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.4)),
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
  // drawio "Network" (mxgraph.networks) — common vendor-neutral devices.
  StencilGroup('Network', <Stencil>[
    Stencil(
        'Server',
        (id, cx, cy) => VsdxShapeFactory.networkServer(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.4)),
    Stencil(
        'Router',
        (id, cx, cy) => VsdxShapeFactory.networkRouter(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.2)),
    Stencil(
        'Firewall',
        (id, cx, cy) => VsdxShapeFactory.networkFirewall(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.2)),
    Stencil(
        'Monitor',
        (id, cx, cy) => VsdxShapeFactory.networkMonitor(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.3)),
    Stencil(
        'Laptop',
        (id, cx, cy) => VsdxShapeFactory.networkLaptop(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.2)),
    Stencil(
        'Mobile',
        (id, cx, cy) => VsdxShapeFactory.networkMobile(
            id: id, pinX: cx, pinY: cy, width: 0.9, height: 1.5)),
    Stencil(
        'Printer',
        (id, cx, cy) => VsdxShapeFactory.networkPrinter(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.3)),
    Stencil(
        'Wireless',
        (id, cx, cy) => VsdxShapeFactory.networkWireless(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.3)),
    Stencil(
        'Cloud',
        (id, cx, cy) => VsdxShapeFactory.cloud(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.1)),
    Stencil(
        'Database',
        (id, cx, cy) => VsdxShapeFactory.cylinder(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.3)),
    Stencil(
        'User',
        (id, cx, cy) => VsdxShapeFactory.umlActor(
            id: id, pinX: cx, pinY: cy, width: 0.8, height: 1.4)),
    Stencil(
        'Switch',
        (id, cx, cy) => VsdxShapeFactory.networkSwitch(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 0.9)),
    Stencil(
        'Hub',
        (id, cx, cy) => VsdxShapeFactory.networkHub(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.3)),
    Stencil(
        'PC',
        (id, cx, cy) => VsdxShapeFactory.networkPc(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.3)),
    Stencil(
        'Tablet',
        (id, cx, cy) => VsdxShapeFactory.networkTablet(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.1)),
    Stencil(
        'Phone',
        (id, cx, cy) => VsdxShapeFactory.networkPhone(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'Modem',
        (id, cx, cy) => VsdxShapeFactory.networkModem(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 0.9)),
    Stencil(
        'Storage',
        (id, cx, cy) => VsdxShapeFactory.networkStorage(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.4)),
    Stencil(
        'Load Balancer',
        (id, cx, cy) => VsdxShapeFactory.networkLoadBalancer(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.2)),
    Stencil(
        'Security Camera',
        (id, cx, cy) => VsdxShapeFactory.networkSecurityCamera(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.1)),
  ], expandAtWidth: 1280),
  // drawio Mockup (mxgraph.mockup.*) — UI wireframe essentials.
  StencilGroup('Mockup', <Stencil>[
    Stencil(
        'Button',
        (id, cx, cy) => VsdxShapeFactory.button(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.55)),
    Stencil(
        'Checkbox',
        (id, cx, cy) => VsdxShapeFactory.mockupCheckbox(
            id: id, pinX: cx, pinY: cy, width: 0.55, height: 0.55)),
    Stencil(
        'Radio Button',
        (id, cx, cy) => VsdxShapeFactory.mockupRadio(
            id: id, pinX: cx, pinY: cy, width: 0.55, height: 0.55)),
    Stencil(
        'Text Field',
        (id, cx, cy) => VsdxShapeFactory.mockupTextField(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 0.5)),
    Stencil(
        'Combo Box',
        (id, cx, cy) => VsdxShapeFactory.mockupComboBox(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 0.5)),
    Stencil(
        'Window',
        (id, cx, cy) => VsdxShapeFactory.mockupWindow(
            id: id, pinX: cx, pinY: cy, width: 2.2, height: 1.6)),
    Stencil(
        'Progress Bar',
        (id, cx, cy) => VsdxShapeFactory.mockupProgressBar(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 0.35)),
    Stencil(
        'Slider',
        (id, cx, cy) => VsdxShapeFactory.mockupSlider(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 0.45)),
    Stencil(
        'Tab Bar',
        (id, cx, cy) => VsdxShapeFactory.mockupTabBar(
            id: id, pinX: cx, pinY: cy, width: 2.0, height: 0.9)),
    Stencil(
        'Menu Bar',
        (id, cx, cy) => VsdxShapeFactory.mockupMenuBar(
            id: id, pinX: cx, pinY: cy, width: 2.0, height: 0.4)),
    Stencil(
        'Toggle',
        (id, cx, cy) => VsdxShapeFactory.mockupToggle(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 0.5)),
    Stencil(
        'Search Box',
        (id, cx, cy) => VsdxShapeFactory.mockupSearchBox(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 0.5)),
    Stencil(
        'Star Rating',
        (id, cx, cy) => VsdxShapeFactory.mockupStarRating(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 0.4)),
    Stencil(
        'Help Icon',
        (id, cx, cy) => VsdxShapeFactory.mockupHelpIcon(
            id: id, pinX: cx, pinY: cy, width: 0.7, height: 0.7)),
    Stencil(
        'Information Icon',
        (id, cx, cy) => VsdxShapeFactory.mockupInfoIcon(
            id: id, pinX: cx, pinY: cy, width: 0.7, height: 0.7)),
    Stencil(
        'Loading Circle',
        (id, cx, cy) => VsdxShapeFactory.mockupLoadingCircle(
            id: id, pinX: cx, pinY: cy, width: 0.8, height: 0.8)),
    Stencil(
        'Horizontal Splitter',
        (id, cx, cy) => VsdxShapeFactory.mockupHorizontalSplitter(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 0.45)),
    Stencil(
        'Dropdown Menu',
        (id, cx, cy) => VsdxShapeFactory.mockupDropdownMenu(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.3)),
  ], expandAtWidth: 1280),
  // drawio Electrical (mxgraph.electrical.*) — common circuit symbols.
  StencilGroup('Electrical', <Stencil>[
    Stencil(
        'Resistor',
        (id, cx, cy) => VsdxShapeFactory.electricalResistor(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 0.55)),
    Stencil(
        'Capacitor',
        (id, cx, cy) => VsdxShapeFactory.electricalCapacitor(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 0.8)),
    Stencil(
        'Inductor',
        (id, cx, cy) => VsdxShapeFactory.electricalInductor(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 0.7)),
    Stencil(
        'Diode',
        (id, cx, cy) => VsdxShapeFactory.electricalDiode(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 0.7)),
    Stencil(
        'LED',
        (id, cx, cy) => VsdxShapeFactory.electricalLed(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 0.8)),
    Stencil(
        'Ground',
        (id, cx, cy) => VsdxShapeFactory.electricalGround(
            id: id, pinX: cx, pinY: cy, width: 0.9, height: 0.8)),
    Stencil(
        'Battery',
        (id, cx, cy) => VsdxShapeFactory.electricalBattery(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.7)),
    Stencil(
        'Transformer',
        (id, cx, cy) => VsdxShapeFactory.electricalTransformer(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'AC Source',
        (id, cx, cy) => VsdxShapeFactory.electricalAcSource(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.0)),
    Stencil(
        'Electrical Switch',
        (id, cx, cy) => VsdxShapeFactory.electricalSwitch(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 0.7)),
    Stencil(
        'Fuse',
        (id, cx, cy) => VsdxShapeFactory.electricalFuse(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 0.55)),
    Stencil(
        'DC Source',
        (id, cx, cy) => VsdxShapeFactory.electricalDcSource(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.0)),
    Stencil(
        'Inverter',
        (id, cx, cy) => VsdxShapeFactory.electricalInverter(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 0.9)),
    Stencil(
        'Potentiometer',
        (id, cx, cy) => VsdxShapeFactory.electricalPotentiometer(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 0.7)),
    Stencil(
        'Circuit Breaker',
        (id, cx, cy) => VsdxShapeFactory.electricalCircuitBreaker(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 0.7)),
    Stencil(
        'Crystal',
        (id, cx, cy) => VsdxShapeFactory.electricalCrystal(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 0.7)),
    Stencil(
        'Lamp',
        (id, cx, cy) => VsdxShapeFactory.electricalLamp(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.0)),
    Stencil(
        'AND Gate',
        (id, cx, cy) => VsdxShapeFactory.electricalAndGate(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.0)),
    Stencil(
        'OR Gate',
        (id, cx, cy) => VsdxShapeFactory.electricalOrGate(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.0)),
    Stencil(
        'NAND Gate',
        (id, cx, cy) => VsdxShapeFactory.electricalNandGate(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.0)),
    Stencil(
        'NOR Gate',
        (id, cx, cy) => VsdxShapeFactory.electricalNorGate(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.0)),
    Stencil(
        'XOR Gate',
        (id, cx, cy) => VsdxShapeFactory.electricalXorGate(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.0)),
    Stencil(
        'XNOR Gate',
        (id, cx, cy) => VsdxShapeFactory.electricalXnorGate(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.0)),
    Stencil(
        'Buffer',
        (id, cx, cy) => VsdxShapeFactory.electricalBuffer(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 0.9)),
  ], expandAtWidth: 1280),
  // drawio Signs (mxGraph.signs.*) — safety / info glyphs.
  StencilGroup('Signs', <Stencil>[
    Stencil(
        'Warning',
        (id, cx, cy) => VsdxShapeFactory.signWarning(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.1)),
    Stencil(
        'No Entry',
        (id, cx, cy) => VsdxShapeFactory.signNoEntry(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Mandatory',
        (id, cx, cy) => VsdxShapeFactory.signMandatory(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Exit',
        (id, cx, cy) => VsdxShapeFactory.signExit(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.0)),
    Stencil(
        'Radiation',
        (id, cx, cy) => VsdxShapeFactory.signRadiation(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'First Aid',
        (id, cx, cy) => VsdxShapeFactory.signFirstAid(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'High Voltage',
        (id, cx, cy) => VsdxShapeFactory.signHighVoltage(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.1)),
    Stencil(
        'Fragile',
        (id, cx, cy) => VsdxShapeFactory.signFragile(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.2)),
    Stencil(
        'No Smoking',
        (id, cx, cy) => VsdxShapeFactory.signNoSmoking(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Biohazard',
        (id, cx, cy) => VsdxShapeFactory.signBiohazard(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Pedestrian Crossing',
        (id, cx, cy) => VsdxShapeFactory.signPedestrianCrossing(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.3)),
    Stencil(
        'Keep Dry',
        (id, cx, cy) => VsdxShapeFactory.signKeepDry(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Slip Hazard',
        (id, cx, cy) => VsdxShapeFactory.signSlipHazard(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.1)),
    Stencil(
        'Fire Extinguisher',
        (id, cx, cy) => VsdxShapeFactory.signFireExtinguisher(
            id: id, pinX: cx, pinY: cy, width: 0.9, height: 1.3)),
  ], expandAtWidth: 1280),
  // drawio Floorplan — top-down furniture / openings starter set.
  StencilGroup('Floorplan', <Stencil>[
    Stencil(
        'Wall',
        (id, cx, cy) => VsdxShapeFactory.floorplanWall(
            id: id, pinX: cx, pinY: cy, width: 2.0, height: 0.25)),
    Stencil(
        'Door',
        (id, cx, cy) => VsdxShapeFactory.floorplanDoor(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.2)),
    Stencil(
        'Window Opening',
        (id, cx, cy) => VsdxShapeFactory.floorplanWindowOpening(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 0.55)),
    Stencil(
        'Dining Table',
        (id, cx, cy) => VsdxShapeFactory.floorplanTable(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.0)),
    Stencil(
        'Chair',
        (id, cx, cy) => VsdxShapeFactory.floorplanChair(
            id: id, pinX: cx, pinY: cy, width: 0.8, height: 0.9)),
    Stencil(
        'Desk',
        (id, cx, cy) => VsdxShapeFactory.floorplanDesk(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 1.1)),
    Stencil(
        'Bed',
        (id, cx, cy) => VsdxShapeFactory.floorplanBed(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.8)),
    Stencil(
        'Sofa',
        (id, cx, cy) => VsdxShapeFactory.floorplanSofa(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 0.9)),
    Stencil(
        'Sink',
        (id, cx, cy) => VsdxShapeFactory.floorplanSink(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 0.8)),
    Stencil(
        'Toilet',
        (id, cx, cy) => VsdxShapeFactory.floorplanToilet(
            id: id, pinX: cx, pinY: cy, width: 0.8, height: 1.2)),
    Stencil(
        'Stairs',
        (id, cx, cy) => VsdxShapeFactory.floorplanStairs(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.6)),
    Stencil(
        'Elevator',
        (id, cx, cy) => VsdxShapeFactory.floorplanElevator(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Plant',
        (id, cx, cy) => VsdxShapeFactory.floorplanPlant(
            id: id, pinX: cx, pinY: cy, width: 0.9, height: 0.9)),
    Stencil(
        'Refrigerator',
        (id, cx, cy) => VsdxShapeFactory.floorplanRefrigerator(
            id: id, pinX: cx, pinY: cy, width: 0.9, height: 1.2)),
    Stencil(
        'Double Door',
        (id, cx, cy) => VsdxShapeFactory.floorplanDoubleDoor(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 1.2)),
    Stencil(
        'Sliding Door',
        (id, cx, cy) => VsdxShapeFactory.floorplanSlidingDoor(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 0.7)),
    Stencil(
        'Bathtub',
        (id, cx, cy) => VsdxShapeFactory.floorplanBathtub(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 0.9)),
    Stencil(
        'Shower',
        (id, cx, cy) => VsdxShapeFactory.floorplanShower(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Closet',
        (id, cx, cy) => VsdxShapeFactory.floorplanCloset(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.7)),
    Stencil(
        'Bookshelf',
        (id, cx, cy) => VsdxShapeFactory.floorplanBookshelf(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 0.45)),
    Stencil(
        'Fireplace',
        (id, cx, cy) => VsdxShapeFactory.floorplanFireplace(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.9)),
    Stencil(
        'Kitchen Island',
        (id, cx, cy) => VsdxShapeFactory.floorplanKitchenIsland(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 1.0)),
    Stencil(
        'Parking Space',
        (id, cx, cy) => VsdxShapeFactory.floorplanParkingSpace(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 2.2)),
    Stencil(
        'TV Stand',
        (id, cx, cy) => VsdxShapeFactory.floorplanTvStand(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 0.7)),
    Stencil(
        'File Cabinet',
        (id, cx, cy) => VsdxShapeFactory.floorplanFileCabinet(
            id: id, pinX: cx, pinY: cy, width: 0.7, height: 1.1)),
    Stencil(
        'Column',
        (id, cx, cy) => VsdxShapeFactory.floorplanColumn(
            id: id, pinX: cx, pinY: cy, width: 0.55, height: 0.55)),
    Stencil(
        'Escalator',
        (id, cx, cy) => VsdxShapeFactory.floorplanEscalator(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.8)),
    Stencil(
        'Copier',
        (id, cx, cy) => VsdxShapeFactory.floorplanCopier(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 0.9)),
  ], expandAtWidth: 1280),
  // drawio EIP (mxgraph.eip.*) — Enterprise Integration Patterns starter set.
  StencilGroup('EIP', <Stencil>[
    Stencil(
        'Message Channel',
        (id, cx, cy) => VsdxShapeFactory.eipMessageChannel(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 0.45)),
    Stencil(
        'Dead Letter Channel',
        (id, cx, cy) => VsdxShapeFactory.eipDeadLetterChannel(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 0.45)),
    Stencil(
        'Message',
        (id, cx, cy) => VsdxShapeFactory.message(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 0.8)),
    Stencil(
        'Aggregator',
        (id, cx, cy) => VsdxShapeFactory.eipAggregator(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Splitter',
        (id, cx, cy) => VsdxShapeFactory.eipSplitter(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Content Based Router',
        (id, cx, cy) => VsdxShapeFactory.eipContentBasedRouter(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Message Filter',
        (id, cx, cy) => VsdxShapeFactory.eipMessageFilter(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Message Translator',
        (id, cx, cy) => VsdxShapeFactory.eipMessageTranslator(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Content Enricher',
        (id, cx, cy) => VsdxShapeFactory.eipContentEnricher(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Messaging Gateway',
        (id, cx, cy) => VsdxShapeFactory.eipMessagingGateway(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Channel Adapter',
        (id, cx, cy) => VsdxShapeFactory.eipChannelAdapter(
            id: id, pinX: cx, pinY: cy, width: 0.7, height: 1.2)),
    Stencil(
        'Wire Tap',
        (id, cx, cy) => VsdxShapeFactory.eipWireTap(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Recipient List',
        (id, cx, cy) => VsdxShapeFactory.eipRecipientList(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Competing Consumers',
        (id, cx, cy) => VsdxShapeFactory.eipCompetingConsumers(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Event Driven Consumer',
        (id, cx, cy) => VsdxShapeFactory.eipEventDrivenConsumer(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Messaging Bridge',
        (id, cx, cy) => VsdxShapeFactory.eipMessagingBridge(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Process Manager',
        (id, cx, cy) => VsdxShapeFactory.eipProcessManager(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Claim Check',
        (id, cx, cy) => VsdxShapeFactory.eipClaimCheck(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Resequencer',
        (id, cx, cy) => VsdxShapeFactory.eipResequencer(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Composed Message Processor',
        (id, cx, cy) => VsdxShapeFactory.eipComposedMessageProcessor(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Content Filter',
        (id, cx, cy) => VsdxShapeFactory.eipContentFilter(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Control Bus',
        (id, cx, cy) => VsdxShapeFactory.eipControlBus(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 0.7)),
    Stencil(
        'Detour',
        (id, cx, cy) => VsdxShapeFactory.eipDetour(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Durable Subscriber',
        (id, cx, cy) => VsdxShapeFactory.eipDurableSubscriber(
            id: id, pinX: cx, pinY: cy, width: 0.7, height: 0.85)),
    Stencil(
        'Dynamic Router',
        (id, cx, cy) => VsdxShapeFactory.eipDynamicRouter(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Envelope Wrapper',
        (id, cx, cy) => VsdxShapeFactory.eipEnvelopeWrapper(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Message Dispatcher',
        (id, cx, cy) => VsdxShapeFactory.eipMessageDispatcher(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Message Store',
        (id, cx, cy) => VsdxShapeFactory.eipMessageStore(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Normalizer',
        (id, cx, cy) => VsdxShapeFactory.eipNormalizer(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Polling Consumer',
        (id, cx, cy) => VsdxShapeFactory.eipPollingConsumer(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Routing Slip',
        (id, cx, cy) => VsdxShapeFactory.eipRoutingSlip(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Selective Consumer',
        (id, cx, cy) => VsdxShapeFactory.eipSelectiveConsumer(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Service Activator',
        (id, cx, cy) => VsdxShapeFactory.eipServiceActivator(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Smart Proxy',
        (id, cx, cy) => VsdxShapeFactory.eipSmartProxy(
            id: id, pinX: cx, pinY: cy, width: 0.9, height: 1.2)),
    Stencil(
        'Transactional Client',
        (id, cx, cy) => VsdxShapeFactory.eipTransactionalClient(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Channel Purger',
        (id, cx, cy) => VsdxShapeFactory.eipChannelPurger(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Test Message',
        (id, cx, cy) => VsdxShapeFactory.eipTestMessage(
            id: id, pinX: cx, pinY: cy, width: 1.7, height: 1.0)),
    Stencil(
        'Datatype Channel',
        (id, cx, cy) => VsdxShapeFactory.eipDatatypeChannel(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 0.45)),
    Stencil(
        'Invalid Message Channel',
        (id, cx, cy) => VsdxShapeFactory.eipInvalidMessageChannel(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 0.45)),
  ], expandAtWidth: 1280),
  // drawio AWS (mxgraph.aws4.*) — geometric architecture starters.
  StencilGroup('AWS', <Stencil>[
    Stencil(
        'EC2',
        (id, cx, cy) => VsdxShapeFactory.awsEc2(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.1)),
    Stencil(
        'S3',
        (id, cx, cy) => VsdxShapeFactory.awsS3(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.2)),
    Stencil(
        'Lambda',
        (id, cx, cy) => VsdxShapeFactory.awsLambda(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'VPC',
        (id, cx, cy) => VsdxShapeFactory.awsVpc(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.1)),
    Stencil(
        'RDS',
        (id, cx, cy) => VsdxShapeFactory.awsRds(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'DynamoDB',
        (id, cx, cy) => VsdxShapeFactory.awsDynamoDb(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.2)),
    Stencil(
        'SQS',
        (id, cx, cy) => VsdxShapeFactory.awsSqs(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 0.9)),
    Stencil(
        'SNS',
        (id, cx, cy) => VsdxShapeFactory.awsSns(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.1)),
    Stencil(
        'CloudFront',
        (id, cx, cy) => VsdxShapeFactory.awsCloudFront(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'API Gateway',
        (id, cx, cy) => VsdxShapeFactory.awsApiGateway(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.1)),
    Stencil(
        'IAM',
        (id, cx, cy) => VsdxShapeFactory.awsIam(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.2)),
    Stencil(
        'ELB',
        (id, cx, cy) => VsdxShapeFactory.awsElb(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.2)),
    Stencil(
        'ECS',
        (id, cx, cy) => VsdxShapeFactory.awsEcs(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
    Stencil(
        'EKS',
        (id, cx, cy) => VsdxShapeFactory.awsEks(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Step Functions',
        (id, cx, cy) => VsdxShapeFactory.awsStepFunctions(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.3)),
    Stencil(
        'CloudWatch',
        (id, cx, cy) => VsdxShapeFactory.awsCloudWatch(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.1)),
    Stencil(
        'Kinesis',
        (id, cx, cy) => VsdxShapeFactory.awsKinesis(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.0)),
    Stencil(
        'ElastiCache',
        (id, cx, cy) => VsdxShapeFactory.awsElastiCache(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Redshift',
        (id, cx, cy) => VsdxShapeFactory.awsRedshift(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'EventBridge',
        (id, cx, cy) => VsdxShapeFactory.awsEventBridge(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
    Stencil(
        'Cognito',
        (id, cx, cy) => VsdxShapeFactory.awsCognito(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Route 53',
        (id, cx, cy) => VsdxShapeFactory.awsRoute53(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'EFS',
        (id, cx, cy) => VsdxShapeFactory.awsEfs(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
    Stencil(
        'Aurora',
        (id, cx, cy) => VsdxShapeFactory.awsAurora(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
    Stencil(
        'Fargate',
        (id, cx, cy) => VsdxShapeFactory.awsFargate(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.0)),
    Stencil(
        'ECR',
        (id, cx, cy) => VsdxShapeFactory.awsEcr(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Glue',
        (id, cx, cy) => VsdxShapeFactory.awsGlue(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'Athena',
        (id, cx, cy) => VsdxShapeFactory.awsAthena(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'EMR',
        (id, cx, cy) => VsdxShapeFactory.awsEmr(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'SageMaker',
        (id, cx, cy) => VsdxShapeFactory.awsSageMaker(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
    Stencil(
        'CloudTrail',
        (id, cx, cy) => VsdxShapeFactory.awsCloudTrail(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.1)),
    Stencil(
        'Secrets Manager',
        (id, cx, cy) => VsdxShapeFactory.awsSecretsManager(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.2)),
    Stencil(
        'CodePipeline',
        (id, cx, cy) => VsdxShapeFactory.awsCodePipeline(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.0)),
    Stencil(
        'CodeBuild',
        (id, cx, cy) => VsdxShapeFactory.awsCodeBuild(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'WAF',
        (id, cx, cy) => VsdxShapeFactory.awsWaf(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.2)),
    Stencil(
        'Transit Gateway',
        (id, cx, cy) => VsdxShapeFactory.awsTransitGateway(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Direct Connect',
        (id, cx, cy) => VsdxShapeFactory.awsDirectConnect(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.2)),
    Stencil(
        'OpenSearch',
        (id, cx, cy) => VsdxShapeFactory.awsOpenSearch(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
  ], expandAtWidth: 1280),
  // drawio Azure (azure / azure2) — geometric architecture starters.
  StencilGroup('Azure', <Stencil>[
    Stencil(
        'Virtual Machine',
        (id, cx, cy) => VsdxShapeFactory.azureVirtualMachine(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
    Stencil(
        'App Service',
        (id, cx, cy) => VsdxShapeFactory.azureAppService(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Azure Functions',
        (id, cx, cy) => VsdxShapeFactory.azureFunctions(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Blob Storage',
        (id, cx, cy) => VsdxShapeFactory.azureBlobStorage(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'SQL Database',
        (id, cx, cy) => VsdxShapeFactory.azureSqlDatabase(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Cosmos DB',
        (id, cx, cy) => VsdxShapeFactory.azureCosmosDb(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'AKS',
        (id, cx, cy) => VsdxShapeFactory.azureAks(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Virtual Network',
        (id, cx, cy) => VsdxShapeFactory.azureVirtualNetwork(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.1)),
    Stencil(
        'Application Gateway',
        (id, cx, cy) => VsdxShapeFactory.azureApplicationGateway(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Azure AD',
        (id, cx, cy) => VsdxShapeFactory.azureActiveDirectory(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Key Vault',
        (id, cx, cy) => VsdxShapeFactory.azureKeyVault(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.2)),
    Stencil(
        'Service Bus',
        (id, cx, cy) => VsdxShapeFactory.azureServiceBus(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.1)),
    Stencil(
        'Event Hubs',
        (id, cx, cy) => VsdxShapeFactory.azureEventHubs(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
    Stencil(
        'Azure Monitor',
        (id, cx, cy) => VsdxShapeFactory.azureMonitor(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.1)),
    Stencil(
        'Container Instances',
        (id, cx, cy) => VsdxShapeFactory.azureContainerInstances(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'Container Registry',
        (id, cx, cy) => VsdxShapeFactory.azureContainerRegistry(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Redis Cache',
        (id, cx, cy) => VsdxShapeFactory.azureRedisCache(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Front Door',
        (id, cx, cy) => VsdxShapeFactory.azureFrontDoor(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'API Management',
        (id, cx, cy) => VsdxShapeFactory.azureApiManagement(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Logic Apps',
        (id, cx, cy) => VsdxShapeFactory.azureLogicApps(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
    Stencil(
        'Data Factory',
        (id, cx, cy) => VsdxShapeFactory.azureDataFactory(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'Synapse Analytics',
        (id, cx, cy) => VsdxShapeFactory.azureSynapseAnalytics(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'IoT Hub',
        (id, cx, cy) => VsdxShapeFactory.azureIotHub(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Event Grid',
        (id, cx, cy) => VsdxShapeFactory.azureEventGrid(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
    Stencil(
        'Azure Firewall',
        (id, cx, cy) => VsdxShapeFactory.azureFirewall(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'Bastion',
        (id, cx, cy) => VsdxShapeFactory.azureBastion(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.2)),
    Stencil(
        'Azure DNS',
        (id, cx, cy) => VsdxShapeFactory.azureDns(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Azure DevOps',
        (id, cx, cy) => VsdxShapeFactory.azureDevOps(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
  ], expandAtWidth: 1280),
  // drawio GCP (gcp2) — geometric architecture starters.
  StencilGroup('GCP', <Stencil>[
    Stencil(
        'Compute Engine',
        (id, cx, cy) => VsdxShapeFactory.gcpComputeEngine(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
    Stencil(
        'App Engine',
        (id, cx, cy) => VsdxShapeFactory.gcpAppEngine(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Cloud Functions',
        (id, cx, cy) => VsdxShapeFactory.gcpCloudFunctions(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Cloud Storage',
        (id, cx, cy) => VsdxShapeFactory.gcpCloudStorage(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'Cloud SQL',
        (id, cx, cy) => VsdxShapeFactory.gcpCloudSql(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'BigQuery',
        (id, cx, cy) => VsdxShapeFactory.gcpBigQuery(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'GKE',
        (id, cx, cy) => VsdxShapeFactory.gcpGke(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'VPC Network',
        (id, cx, cy) => VsdxShapeFactory.gcpVpcNetwork(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.1)),
    Stencil(
        'Cloud Load Balancing',
        (id, cx, cy) => VsdxShapeFactory.gcpCloudLoadBalancing(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Cloud IAM',
        (id, cx, cy) => VsdxShapeFactory.gcpCloudIam(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.2)),
    Stencil(
        'Pub/Sub',
        (id, cx, cy) => VsdxShapeFactory.gcpPubSub(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Cloud Spanner',
        (id, cx, cy) => VsdxShapeFactory.gcpCloudSpanner(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
    Stencil(
        'Cloud Run',
        (id, cx, cy) => VsdxShapeFactory.gcpCloudRun(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.1)),
    Stencil(
        'Cloud Monitoring',
        (id, cx, cy) => VsdxShapeFactory.gcpCloudMonitoring(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.1)),
    Stencil(
        'Bigtable',
        (id, cx, cy) => VsdxShapeFactory.gcpBigtable(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Dataflow',
        (id, cx, cy) => VsdxShapeFactory.gcpDataflow(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.0)),
    Stencil(
        'Dataproc',
        (id, cx, cy) => VsdxShapeFactory.gcpDataproc(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Cloud Composer',
        (id, cx, cy) => VsdxShapeFactory.gcpCloudComposer(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
    Stencil(
        'Cloud Armor',
        (id, cx, cy) => VsdxShapeFactory.gcpCloudArmor(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.2)),
    Stencil(
        'Cloud CDN',
        (id, cx, cy) => VsdxShapeFactory.gcpCloudCdn(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Memorystore',
        (id, cx, cy) => VsdxShapeFactory.gcpMemorystore(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Cloud Build',
        (id, cx, cy) => VsdxShapeFactory.gcpCloudBuild(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Artifact Registry',
        (id, cx, cy) => VsdxShapeFactory.gcpArtifactRegistry(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Cloud Scheduler',
        (id, cx, cy) => VsdxShapeFactory.gcpCloudScheduler(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'Cloud Tasks',
        (id, cx, cy) => VsdxShapeFactory.gcpCloudTasks(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Firestore',
        (id, cx, cy) => VsdxShapeFactory.gcpFirestore(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.3)),
    Stencil(
        'Secret Manager',
        (id, cx, cy) => VsdxShapeFactory.gcpSecretManager(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.2)),
    Stencil(
        'Vertex AI',
        (id, cx, cy) => VsdxShapeFactory.gcpVertexAi(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
  ], expandAtWidth: 1280),
  // drawio Cisco — geometric network gear starters (not brand-mark replicas).
  StencilGroup('Cisco', <Stencil>[
    Stencil(
        'Cisco Router',
        (id, cx, cy) => VsdxShapeFactory.ciscoRouter(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.0)),
    Stencil(
        'Cisco Switch',
        (id, cx, cy) => VsdxShapeFactory.ciscoSwitch(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 0.9)),
    Stencil(
        'ASA Firewall',
        (id, cx, cy) => VsdxShapeFactory.ciscoAsaFirewall(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.1)),
    Stencil(
        'Access Point',
        (id, cx, cy) => VsdxShapeFactory.ciscoAccessPoint(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.1)),
    Stencil(
        'Nexus Switch',
        (id, cx, cy) => VsdxShapeFactory.ciscoNexusSwitch(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.3)),
    Stencil(
        'Catalyst Switch',
        (id, cx, cy) => VsdxShapeFactory.ciscoCatalystSwitch(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'IP Phone',
        (id, cx, cy) => VsdxShapeFactory.ciscoIpPhone(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.1)),
    Stencil(
        'Call Manager',
        (id, cx, cy) => VsdxShapeFactory.ciscoCallManager(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 1.3)),
    Stencil(
        'Layer 3 Switch',
        (id, cx, cy) => VsdxShapeFactory.ciscoLayer3Switch(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.0)),
    Stencil(
        'WAN Router',
        (id, cx, cy) => VsdxShapeFactory.ciscoWanRouter(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.2)),
    Stencil(
        'Voice Gateway',
        (id, cx, cy) => VsdxShapeFactory.ciscoVoiceGateway(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.1)),
    Stencil(
        'UCS',
        (id, cx, cy) => VsdxShapeFactory.ciscoUcs(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
    Stencil(
        'Fabric Interconnect',
        (id, cx, cy) => VsdxShapeFactory.ciscoFabricInterconnect(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.1)),
    Stencil(
        'Content Engine',
        (id, cx, cy) => VsdxShapeFactory.ciscoContentEngine(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.1)),
    Stencil(
        'Wireless Controller',
        (id, cx, cy) => VsdxShapeFactory.ciscoWirelessController(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.0)),
    Stencil(
        'PIX Firewall',
        (id, cx, cy) => VsdxShapeFactory.ciscoPixFirewall(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.1)),
    Stencil(
        'ATM Switch',
        (id, cx, cy) => VsdxShapeFactory.ciscoAtmSwitch(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Workgroup Switch',
        (id, cx, cy) => VsdxShapeFactory.ciscoWorkgroupSwitch(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.9)),
    Stencil(
        'Content Switch',
        (id, cx, cy) => VsdxShapeFactory.ciscoContentSwitch(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'VPN Concentrator',
        (id, cx, cy) => VsdxShapeFactory.ciscoVpnConcentrator(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.1)),
    Stencil(
        'Wireless Bridge',
        (id, cx, cy) => VsdxShapeFactory.ciscoWirelessBridge(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.1)),
    Stencil(
        'Meraki AP',
        (id, cx, cy) => VsdxShapeFactory.ciscoMerakiAp(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.1)),
    Stencil(
        'Cisco ISE',
        (id, cx, cy) => VsdxShapeFactory.ciscoIse(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.2)),
    Stencil(
        'DNA Center',
        (id, cx, cy) => VsdxShapeFactory.ciscoDnaCenter(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Telepresence',
        (id, cx, cy) => VsdxShapeFactory.ciscoTelepresence(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.2)),
    Stencil(
        'Expressway',
        (id, cx, cy) => VsdxShapeFactory.ciscoExpressway(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
    Stencil(
        'Core Switch',
        (id, cx, cy) => VsdxShapeFactory.ciscoCoreSwitch(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.3)),
    Stencil(
        'Branch Router',
        (id, cx, cy) => VsdxShapeFactory.ciscoBranchRouter(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.0)),
  ], expandAtWidth: 1280),
  // drawio Alibaba Cloud — geometric architecture starters.
  StencilGroup('Alibaba', <Stencil>[
    Stencil(
        'Alibaba ECS',
        (id, cx, cy) => VsdxShapeFactory.alibabaEcs(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
    Stencil(
        'OSS',
        (id, cx, cy) => VsdxShapeFactory.alibabaOss(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'SLB',
        (id, cx, cy) => VsdxShapeFactory.alibabaSlb(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'ACK',
        (id, cx, cy) => VsdxShapeFactory.alibabaAck(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Function Compute',
        (id, cx, cy) => VsdxShapeFactory.alibabaFunctionCompute(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'PolarDB',
        (id, cx, cy) => VsdxShapeFactory.alibabaPolarDb(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'TableStore',
        (id, cx, cy) => VsdxShapeFactory.alibabaTableStore(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'MaxCompute',
        (id, cx, cy) => VsdxShapeFactory.alibabaMaxCompute(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'RocketMQ',
        (id, cx, cy) => VsdxShapeFactory.alibabaRocketMq(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'RAM',
        (id, cx, cy) => VsdxShapeFactory.alibabaRam(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.2)),
    Stencil(
        'CEN',
        (id, cx, cy) => VsdxShapeFactory.alibabaCen(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'SLS',
        (id, cx, cy) => VsdxShapeFactory.alibabaSls(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.1)),
    Stencil(
        'NAS',
        (id, cx, cy) => VsdxShapeFactory.alibabaNas(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'AnalyticDB',
        (id, cx, cy) => VsdxShapeFactory.alibabaAnalyticDb(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'CDN',
        (id, cx, cy) => VsdxShapeFactory.alibabaCdn(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Aliyun WAF',
        (id, cx, cy) => VsdxShapeFactory.alibabaWaf(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.2)),
    Stencil(
        'DataWorks',
        (id, cx, cy) => VsdxShapeFactory.alibabaDataWorks(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Hologres',
        (id, cx, cy) => VsdxShapeFactory.alibabaHologres(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Flink',
        (id, cx, cy) => VsdxShapeFactory.alibabaFlink(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.0)),
    Stencil(
        'MSE',
        (id, cx, cy) => VsdxShapeFactory.alibabaMse(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'ASM',
        (id, cx, cy) => VsdxShapeFactory.alibabaAsm(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'ACR',
        (id, cx, cy) => VsdxShapeFactory.alibabaAcr(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'EIP',
        (id, cx, cy) => VsdxShapeFactory.alibabaEip(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'NAT Gateway',
        (id, cx, cy) => VsdxShapeFactory.alibabaNatGateway(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
    Stencil(
        'KMS',
        (id, cx, cy) => VsdxShapeFactory.alibabaKms(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.2)),
    Stencil(
        'ARMS',
        (id, cx, cy) => VsdxShapeFactory.alibabaArms(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.1)),
    Stencil(
        'Lindorm',
        (id, cx, cy) => VsdxShapeFactory.alibabaLindorm(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'DTS',
        (id, cx, cy) => VsdxShapeFactory.alibabaDts(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
  ], expandAtWidth: 1280),
  // drawio IBM Cloud — geometric architecture starters.
  StencilGroup('IBM', <Stencil>[
    Stencil(
        'IBM VPC',
        (id, cx, cy) => VsdxShapeFactory.ibmVpc(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.1)),
    Stencil(
        'Cloud Object Storage',
        (id, cx, cy) => VsdxShapeFactory.ibmCloudObjectStorage(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'IKS',
        (id, cx, cy) => VsdxShapeFactory.ibmIks(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'ROKS',
        (id, cx, cy) => VsdxShapeFactory.ibmRoks(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Db2',
        (id, cx, cy) => VsdxShapeFactory.ibmDb2(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Cloudant',
        (id, cx, cy) => VsdxShapeFactory.ibmCloudant(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.3)),
    Stencil(
        'Event Streams',
        (id, cx, cy) => VsdxShapeFactory.ibmEventStreams(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.0)),
    Stencil(
        'IBM MQ',
        (id, cx, cy) => VsdxShapeFactory.ibmMq(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'watsonx',
        (id, cx, cy) => VsdxShapeFactory.ibmWatsonx(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
    Stencil(
        'Code Engine',
        (id, cx, cy) => VsdxShapeFactory.ibmCodeEngine(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.0)),
    Stencil(
        'API Connect',
        (id, cx, cy) => VsdxShapeFactory.ibmApiConnect(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'App ID',
        (id, cx, cy) => VsdxShapeFactory.ibmAppId(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.2)),
    Stencil(
        'Key Protect',
        (id, cx, cy) => VsdxShapeFactory.ibmKeyProtect(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.2)),
    Stencil(
        'Direct Link',
        (id, cx, cy) => VsdxShapeFactory.ibmDirectLink(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.2)),
    Stencil(
        'Activity Tracker',
        (id, cx, cy) => VsdxShapeFactory.ibmActivityTracker(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.1)),
    Stencil(
        'Log Analysis',
        (id, cx, cy) => VsdxShapeFactory.ibmLogAnalysis(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Schematics',
        (id, cx, cy) => VsdxShapeFactory.ibmSchematics(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'Satellite',
        (id, cx, cy) => VsdxShapeFactory.ibmSatellite(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Power VS',
        (id, cx, cy) => VsdxShapeFactory.ibmPowerVs(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
    Stencil(
        'Bare Metal',
        (id, cx, cy) => VsdxShapeFactory.ibmBareMetal(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.3)),
    Stencil(
        'Block Storage',
        (id, cx, cy) => VsdxShapeFactory.ibmBlockStorage(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'File Storage',
        (id, cx, cy) => VsdxShapeFactory.ibmFileStorage(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'CIS',
        (id, cx, cy) => VsdxShapeFactory.ibmCis(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Internet Services',
        (id, cx, cy) => VsdxShapeFactory.ibmInternetServices(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.1)),
    Stencil(
        'Aspera',
        (id, cx, cy) => VsdxShapeFactory.ibmAspera(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.0)),
    Stencil(
        'Certificate Manager',
        (id, cx, cy) => VsdxShapeFactory.ibmCertificateManager(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.3)),
    Stencil(
        'Toolchain',
        (id, cx, cy) => VsdxShapeFactory.ibmToolchain(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.1)),
    Stencil(
        'Security Advisor',
        (id, cx, cy) => VsdxShapeFactory.ibmSecurityAdvisor(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.2)),
  ], expandAtWidth: 1280),
  // drawio Oracle Cloud (OCI) — geometric architecture starters.
  StencilGroup('Oracle', <Stencil>[
    Stencil(
        'Compute Instance',
        (id, cx, cy) => VsdxShapeFactory.oracleComputeInstance(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.2)),
    Stencil(
        'Autonomous Database',
        (id, cx, cy) => VsdxShapeFactory.oracleAutonomousDatabase(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'Object Storage',
        (id, cx, cy) => VsdxShapeFactory.oracleObjectStorage(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'Block Volume',
        (id, cx, cy) => VsdxShapeFactory.oracleBlockVolume(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'OKE',
        (id, cx, cy) => VsdxShapeFactory.oracleOke(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Oracle Functions',
        (id, cx, cy) => VsdxShapeFactory.oracleFunctions(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.1)),
    Stencil(
        'VCN',
        (id, cx, cy) => VsdxShapeFactory.oracleVcn(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.1)),
    Stencil(
        'Oracle Load Balancer',
        (id, cx, cy) => VsdxShapeFactory.oracleLoadBalancer(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Streaming',
        (id, cx, cy) => VsdxShapeFactory.oracleStreaming(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.0)),
    Stencil(
        'Oracle Vault',
        (id, cx, cy) => VsdxShapeFactory.oracleVault(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.2)),
    Stencil(
        'Exadata',
        (id, cx, cy) => VsdxShapeFactory.oracleExadata(
            id: id, pinX: cx, pinY: cy, width: 1.3, height: 1.3)),
    Stencil(
        'MySQL HeatWave',
        (id, cx, cy) => VsdxShapeFactory.oracleMysqlHeatwave(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.2)),
    Stencil(
        'GoldenGate',
        (id, cx, cy) => VsdxShapeFactory.oracleGoldenGate(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.0)),
    Stencil(
        'Analytics Cloud',
        (id, cx, cy) => VsdxShapeFactory.oracleAnalyticsCloud(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.1)),
    Stencil(
        'OCI API Gateway',
        (id, cx, cy) => VsdxShapeFactory.oracleApiGateway(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Service Connector',
        (id, cx, cy) => VsdxShapeFactory.oracleServiceConnector(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.0)),
    Stencil(
        'OCI Notifications',
        (id, cx, cy) => VsdxShapeFactory.oracleNotifications(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.2)),
    Stencil(
        'OCI Events',
        (id, cx, cy) => VsdxShapeFactory.oracleEvents(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Data Science',
        (id, cx, cy) => VsdxShapeFactory.oracleDataScience(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'OCI Data Flow',
        (id, cx, cy) => VsdxShapeFactory.oracleDataFlow(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.1)),
    Stencil(
        'Data Catalog',
        (id, cx, cy) => VsdxShapeFactory.oracleDataCatalog(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'FastConnect',
        (id, cx, cy) => VsdxShapeFactory.oracleFastConnect(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.2)),
    Stencil(
        'OCI File Storage',
        (id, cx, cy) => VsdxShapeFactory.oracleFileStorage(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'OCI Bastion',
        (id, cx, cy) => VsdxShapeFactory.oracleBastion(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'Network Load Balancer',
        (id, cx, cy) => VsdxShapeFactory.oracleNetworkLoadBalancer(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.2)),
    Stencil(
        'Cloud Guard',
        (id, cx, cy) => VsdxShapeFactory.oracleCloudGuard(
            id: id, pinX: cx, pinY: cy, width: 1.1, height: 1.2)),
    Stencil(
        'Resource Manager',
        (id, cx, cy) => VsdxShapeFactory.oracleResourceManager(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.3)),
    Stencil(
        'DevOps',
        (id, cx, cy) => VsdxShapeFactory.oracleDevOps(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.1)),
  ], expandAtWidth: 1280),
];

/// Libraries visible before the user opens the “More shapes” chooser.
final Set<String> kDefaultStencilGroupNames = Set<String>.unmodifiable(
  _builtInStencilGroups.map((group) => group.name),
);

/// Complete palette: hand-tuned everyday libraries followed by every draw.io
/// XML stencil pack. Extended packs start collapsed and are enabled from the
/// “More shapes” chooser, so the sidebar remains responsive with 8k+ entries.
final List<StencilGroup> kStencilGroups = <StencilGroup>[
  ..._builtInStencilGroups,
  ...kDrawioXmlStencilGroups,
  ...kDrawioJsStencilGroups,
];

/// Flattened view of every stencil (used for search / lookups).
final List<Stencil> kStencils = <Stencil>[
  for (final g in kStencilGroups) ...g.stencils,
];
