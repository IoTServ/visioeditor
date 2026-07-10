import 'package:flutter/material.dart';
import 'package:vsdx/vsdx.dart';

/// A palette entry: a named, icon-labelled builder that produces a shape at a
/// given page-inch centre.
class Stencil {
  const Stencil(this.name, this.icon, this.build);

  final String name;
  final IconData icon;
  final VsdxShape Function(int id, double cx, double cy) build;
}

const double _w = 1.5;
const double _h = 1.0;

VsdxShape _poly(int id, double cx, double cy, List<Offset2D> unit) =>
    VsdxShapeFactory.polygon(
      id: id,
      pinX: cx,
      pinY: cy,
      width: _w,
      height: _h,
      unit: unit,
    );

/// Built-in flowchart-style stencils. All use polygon / ellipse geometry so
/// they render and round-trip through the writer without loss.
final List<Stencil> kStencils = <Stencil>[
  Stencil('Process', Icons.crop_square,
      (id, cx, cy) => VsdxShapeFactory.rectangle(
          id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
  Stencil('Start / End', Icons.circle_outlined,
      (id, cx, cy) => VsdxShapeFactory.ellipse(
          id: id, pinX: cx, pinY: cy, width: _w, height: _h)),
  Stencil(
      'Decision',
      Icons.diamond_outlined,
      (id, cx, cy) => _poly(id, cx, cy, const [
            Offset2D(0.5, 1),
            Offset2D(1, 0.5),
            Offset2D(0.5, 0),
            Offset2D(0, 0.5),
          ])),
  Stencil(
      'Data',
      Icons.rectangle_outlined,
      (id, cx, cy) => _poly(id, cx, cy, const [
            Offset2D(0.25, 1),
            Offset2D(1, 1),
            Offset2D(0.75, 0),
            Offset2D(0, 0),
          ])),
  Stencil(
      'Triangle',
      Icons.change_history,
      (id, cx, cy) => _poly(id, cx, cy, const [
            Offset2D(0.5, 1),
            Offset2D(1, 0),
            Offset2D(0, 0),
          ])),
  Stencil(
      'Hexagon',
      Icons.hexagon_outlined,
      (id, cx, cy) => _poly(id, cx, cy, const [
            Offset2D(0.25, 1),
            Offset2D(0.75, 1),
            Offset2D(1, 0.5),
            Offset2D(0.75, 0),
            Offset2D(0.25, 0),
            Offset2D(0, 0.5),
          ])),
  Stencil(
      'Pentagon',
      Icons.pentagon_outlined,
      (id, cx, cy) => _poly(id, cx, cy, const [
            Offset2D(0.5, 1),
            Offset2D(1, 0.62),
            Offset2D(0.81, 0),
            Offset2D(0.19, 0),
            Offset2D(0, 0.62),
          ])),
  Stencil(
      'Arrow',
      Icons.arrow_forward,
      (id, cx, cy) => _poly(id, cx, cy, const [
            Offset2D(0, 0.7),
            Offset2D(0.6, 0.7),
            Offset2D(0.6, 1),
            Offset2D(1, 0.5),
            Offset2D(0.6, 0),
            Offset2D(0.6, 0.3),
            Offset2D(0, 0.3),
          ])),
];
