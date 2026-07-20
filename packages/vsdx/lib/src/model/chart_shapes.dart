/// Geometric chart shapes (draw.io / 万兴图示 style) for the Charts palette.
///
/// Each chart is a [VsdxShapeKind.group] with coloured child bars/slices so it
/// paints multi-series on canvas and round-trips through [VsdxWriter] as normal
/// Visio geometry (no external chart engine).
library;

import 'dart:math' as math;

import 'fill.dart';
import 'geometry.dart';
import 'line.dart';
import 'page.dart';
import 'shape.dart';
import 'shape_kind.dart';
import '../utils/color.dart';

/// Builders for common chart stencils.
abstract final class ChartOps {
  ChartOps._();

  static const List<VsdxColor> _series = <VsdxColor>[
    VsdxColor(0xFF5B9BD5),
    VsdxColor(0xFFED7D31),
    VsdxColor(0xFF70AD47),
    VsdxColor(0xFFFFC000),
    VsdxColor(0xFF9E7CC3),
    VsdxColor(0xFF5B9EA6),
  ];

  static VsdxLine get _axisLine => const VsdxLine(
        color: VsdxColor(0xFF888888),
        weightInches: 0.01,
      );

  static VsdxLine _barLine(VsdxColor c) => VsdxLine(
        color: VsdxColor(_darken(c.value)),
        weightInches: 0.008,
      );

  static int _darken(int argb) {
    final a = (argb >> 24) & 0xFF;
    final r = (((argb >> 16) & 0xFF) * 0.75).round().clamp(0, 255);
    final g = (((argb >> 8) & 0xFF) * 0.75).round().clamp(0, 255);
    final b = ((argb & 0xFF) * 0.75).round().clamp(0, 255);
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  static VsdxShape _rectChild({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    required VsdxColor fill,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    return VsdxShape(
      id: id,
      name: name ?? 'Series.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          const MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          const LineTo(0, 0),
        ]),
      ],
      fill: VsdxFill(foreground: fill),
      line: _barLine(fill),
    );
  }

  static VsdxShape _axesChild({
    required int id,
    required double width,
    required double height,
  }) {
    final w = width.abs();
    final h = height.abs();
    const pad = 0.08;
    return VsdxShape(
      id: id,
      name: 'Axes.$id',
      pinX: w / 2,
      pinY: h / 2,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(pad * w, pad * h),
            LineTo(pad * w, (1 - pad) * h),
            LineTo((1 - pad) * w, (1 - pad) * h),
          ],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: _axisLine,
    );
  }

  static VsdxShape _group({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    required List<VsdxShape> children,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    return VsdxShape(
      id: id,
      name: name ?? 'Chart.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      shapeKind: VsdxShapeKind.group,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      connectionPoints: VsdxPage.defaultConnectionPoints(w, h),
      children: children,
    );
  }

  /// Vertical column chart (4 sample bars).
  static VsdxShape columnChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.8,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    const values = <double>[0.45, 0.75, 0.55, 0.9];
    final padL = w * 0.12;
    final padB = h * 0.12;
    final padT = h * 0.08;
    final plotW = w - padL - w * 0.08;
    final plotH = h - padB - padT;
    final gap = plotW * 0.08;
    final barW = (plotW - gap * (values.length + 1)) / values.length;
    var next = id + 1;
    final kids = <VsdxShape>[_axesChild(id: next++, width: w, height: h)];
    for (var i = 0; i < values.length; i++) {
      final bh = plotH * values[i];
      final cx = padL + gap + barW / 2 + i * (barW + gap);
      final cy = padB + bh / 2;
      kids.add(_rectChild(
        id: next++,
        pinX: cx,
        pinY: cy,
        width: barW,
        height: bh,
        fill: _series[i % _series.length],
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      name: name ?? 'Column Chart',
    );
  }

  /// Horizontal bar chart.
  static VsdxShape barChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.8,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    const values = <double>[0.55, 0.8, 0.4, 0.7];
    final padL = w * 0.12;
    final padB = h * 0.12;
    final padR = w * 0.08;
    final plotW = w - padL - padR;
    final plotH = h - padB - h * 0.08;
    final gap = plotH * 0.08;
    final barH = (plotH - gap * (values.length + 1)) / values.length;
    var next = id + 1;
    final kids = <VsdxShape>[_axesChild(id: next++, width: w, height: h)];
    for (var i = 0; i < values.length; i++) {
      final bw = plotW * values[i];
      final cy = padB + gap + barH / 2 + i * (barH + gap);
      final cx = padL + bw / 2;
      kids.add(_rectChild(
        id: next++,
        pinX: cx,
        pinY: cy,
        width: bw,
        height: barH,
        fill: _series[i % _series.length],
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      name: name ?? 'Bar Chart',
    );
  }

  /// Stacked column (three series × three categories).
  static VsdxShape stackedColumnChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.8,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    const stacks = <List<double>>[
      [0.25, 0.2, 0.3],
      [0.35, 0.25, 0.15],
      [0.2, 0.35, 0.25],
    ];
    final padL = w * 0.12;
    final padB = h * 0.12;
    final plotW = w - padL - w * 0.08;
    final plotH = h - padB - h * 0.08;
    final gap = plotW * 0.1;
    final barW = (plotW - gap * (stacks.length + 1)) / stacks.length;
    var next = id + 1;
    final kids = <VsdxShape>[_axesChild(id: next++, width: w, height: h)];
    for (var i = 0; i < stacks.length; i++) {
      final cx = padL + gap + barW / 2 + i * (barW + gap);
      var y0 = padB;
      for (var s = 0; s < stacks[i].length; s++) {
        final bh = plotH * stacks[i][s];
        kids.add(_rectChild(
          id: next++,
          pinX: cx,
          pinY: y0 + bh / 2,
          width: barW,
          height: bh,
          fill: _series[s % _series.length],
        ));
        y0 += bh;
      }
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      name: name ?? 'Stacked Column',
    );
  }

  /// Pie chart with four coloured slices.
  static VsdxShape pieChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.0,
    double height = 2.0,
    String? name,
  }) {
    return _radialChart(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      values: const <double>[0.3, 0.25, 0.2, 0.25],
      innerRatio: 0,
      name: name ?? 'Pie Chart',
    );
  }

  /// Donut chart (hollow centre).
  static VsdxShape donutChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.0,
    double height = 2.0,
    String? name,
  }) {
    return _radialChart(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      values: const <double>[0.28, 0.22, 0.3, 0.2],
      innerRatio: 0.45,
      name: name ?? 'Donut Chart',
    );
  }

  static VsdxShape _radialChart({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    required List<double> values,
    required double innerRatio,
    required String name,
  }) {
    final w = width.abs();
    final h = height.abs();
    final cx = w / 2;
    final cy = h / 2;
    final rx = w * 0.42;
    final ry = h * 0.42;
    var next = id + 1;
    final kids = <VsdxShape>[];
    var angle = math.pi / 2; // start at top
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] * 2 * math.pi;
      final a0 = angle;
      final a1 = angle - sweep; // clockwise visually with Y-up → negative
      kids.add(_wedgeChild(
        id: next++,
        chartW: w,
        chartH: h,
        cx: cx,
        cy: cy,
        rx: rx,
        ry: ry,
        a0: a0,
        a1: a1,
        inner: innerRatio,
        fill: _series[i % _series.length],
      ));
      angle = a1;
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      name: name,
    );
  }

  static VsdxShape _wedgeChild({
    required int id,
    required double chartW,
    required double chartH,
    required double cx,
    required double cy,
    required double rx,
    required double ry,
    required double a0,
    required double a1,
    required double inner,
    required VsdxColor fill,
  }) {
    // Full-chart-sized child so arcs stay in chart coordinates.
    final cmds = <VsdxPathCommand>[];
    final x0 = cx + rx * math.cos(a0);
    final y0 = cy + ry * math.sin(a0);
    final x1 = cx + rx * math.cos(a1);
    final y1 = cy + ry * math.sin(a1);
    final mid = (a0 + a1) / 2;
    final ctrlX = cx + rx * 1.05 * math.cos(mid);
    final ctrlY = cy + ry * 1.05 * math.sin(mid);
    if (inner <= 0) {
      cmds.addAll(<VsdxPathCommand>[
        MoveTo(cx, cy),
        LineTo(x0, y0),
        EllipticalArcTo(x: x1, y: y1, controlX: ctrlX, controlY: ctrlY),
        LineTo(cx, cy),
      ]);
    } else {
      final irx = rx * inner;
      final iry = ry * inner;
      final ix0 = cx + irx * math.cos(a0);
      final iy0 = cy + iry * math.sin(a0);
      final ix1 = cx + irx * math.cos(a1);
      final iy1 = cy + iry * math.sin(a1);
      final icx = cx + irx * 1.05 * math.cos(mid);
      final icy = cy + iry * 1.05 * math.sin(mid);
      cmds.addAll(<VsdxPathCommand>[
        MoveTo(ix0, iy0),
        LineTo(x0, y0),
        EllipticalArcTo(x: x1, y: y1, controlX: ctrlX, controlY: ctrlY),
        LineTo(ix1, iy1),
        EllipticalArcTo(x: ix0, y: iy0, controlX: icx, controlY: icy),
      ]);
    }
    return VsdxShape(
      id: id,
      name: 'Slice.$id',
      pinX: chartW / 2,
      pinY: chartH / 2,
      width: chartW,
      height: chartH,
      geometries: <VsdxGeometry>[VsdxGeometry(commands: cmds)],
      fill: VsdxFill(foreground: fill),
      line: _barLine(fill),
    );
  }

  /// Line chart with markers.
  static VsdxShape lineChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.8,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    const values = <double>[0.35, 0.55, 0.45, 0.8, 0.65];
    final padL = w * 0.12;
    final padB = h * 0.12;
    final padT = h * 0.1;
    final padR = w * 0.08;
    final plotW = w - padL - padR;
    final plotH = h - padB - padT;
    var next = id + 1;
    final kids = <VsdxShape>[_axesChild(id: next++, width: w, height: h)];
    final pts = <({double x, double y})>[];
    for (var i = 0; i < values.length; i++) {
      final x = padL + (values.length == 1 ? 0 : plotW * i / (values.length - 1));
      final y = padB + plotH * values[i];
      pts.add((x: x, y: y));
    }
    kids.add(VsdxShape(
      id: next++,
      name: 'Line.$id',
      pinX: w / 2,
      pinY: h / 2,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(pts.first.x, pts.first.y),
            for (final p in pts.skip(1)) LineTo(p.x, p.y),
          ],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: VsdxColor(0xFF5B9BD5),
        weightInches: 0.018,
      ),
    ));
    for (var i = 0; i < pts.length; i++) {
      const r = 0.06;
      kids.add(VsdxShape(
        id: next++,
        name: 'Mark.$i',
        pinX: pts[i].x,
        pinY: pts[i].y,
        width: r * 2,
        height: r * 2,
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
              cx: r,
              cy: r,
              aX: r * 2,
              aY: r,
              bX: r,
              bY: 0,
            ),
          ]),
        ],
        fill: VsdxFill(foreground: _series[i % _series.length]),
        line: _barLine(_series[i % _series.length]),
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      name: name ?? 'Line Chart',
    );
  }

  /// Area chart under a polyline.
  static VsdxShape areaChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.8,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    const values = <double>[0.3, 0.6, 0.5, 0.85, 0.55];
    final padL = w * 0.12;
    final padB = h * 0.12;
    final padT = h * 0.1;
    final padR = w * 0.08;
    final plotW = w - padL - padR;
    final plotH = h - padB - padT;
    var next = id + 1;
    final kids = <VsdxShape>[_axesChild(id: next++, width: w, height: h)];
    final pts = <({double x, double y})>[];
    for (var i = 0; i < values.length; i++) {
      final x = padL + (values.length == 1 ? 0 : plotW * i / (values.length - 1));
      final y = padB + plotH * values[i];
      pts.add((x: x, y: y));
    }
    kids.add(VsdxShape(
      id: next++,
      name: 'Area.$id',
      pinX: w / 2,
      pinY: h / 2,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(pts.first.x, padB),
          LineTo(pts.first.x, pts.first.y),
          for (final p in pts.skip(1)) LineTo(p.x, p.y),
          LineTo(pts.last.x, padB),
          LineTo(pts.first.x, padB),
        ]),
      ],
      fill: const VsdxFill(
        foreground: VsdxColor(0xFF5B9BD5),
        foregroundTransparency: 0.35,
      ),
      line: const VsdxLine(
        color: VsdxColor(0xFF2E75B6),
        weightInches: 0.012,
      ),
    ));
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      name: name ?? 'Area Chart',
    );
  }

  /// Funnel chart (trapezoid bands).
  static VsdxShape funnelChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.0,
    double height = 2.2,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    const widths = <double>[1.0, 0.78, 0.55, 0.35];
    final bandH = h * 0.2;
    final gap = h * 0.04;
    var next = id + 1;
    final kids = <VsdxShape>[];
    var top = h * 0.88;
    for (var i = 0; i < widths.length; i++) {
      final bw = w * widths[i];
      final cy = top - bandH / 2;
      kids.add(_rectChild(
        id: next++,
        pinX: w / 2,
        pinY: cy,
        width: bw,
        height: bandH,
        fill: _series[i % _series.length],
      ));
      top -= bandH + gap;
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      name: name ?? 'Funnel',
    );
  }

  /// Radar / spider chart outline with filled polygon.
  static VsdxShape radarChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.0,
    double height = 2.0,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    const values = <double>[0.7, 0.55, 0.85, 0.45, 0.65];
    final cx = w / 2;
    final cy = h / 2;
    final rx = w * 0.4;
    final ry = h * 0.4;
    var next = id + 1;
    final kids = <VsdxShape>[];
    // Grid rings.
    kids.add(VsdxShape(
      id: next++,
      name: 'RadarGrid.$id',
      pinX: cx,
      pinY: cy,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        for (final t in <double>[0.33, 0.66, 1.0])
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              for (var i = 0; i <= values.length; i++)
                if (i == 0)
                  MoveTo(
                    cx + rx * t * math.cos(math.pi / 2),
                    cy + ry * t * math.sin(math.pi / 2),
                  )
                else
                  LineTo(
                    cx +
                        rx *
                            t *
                            math.cos(math.pi / 2 - i * 2 * math.pi / values.length),
                    cy +
                        ry *
                            t *
                            math.sin(math.pi / 2 - i * 2 * math.pi / values.length),
                  ),
            ],
          ),
        for (var i = 0; i < values.length; i++)
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              MoveTo(cx, cy),
              LineTo(
                cx +
                    rx *
                        math.cos(math.pi / 2 - i * 2 * math.pi / values.length),
                cy +
                    ry *
                        math.sin(math.pi / 2 - i * 2 * math.pi / values.length),
              ),
            ],
          ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: _axisLine,
    ));
    final poly = <VsdxPathCommand>[];
    for (var i = 0; i < values.length; i++) {
      final a = math.pi / 2 - i * 2 * math.pi / values.length;
      final x = cx + rx * values[i] * math.cos(a);
      final y = cy + ry * values[i] * math.sin(a);
      poly.add(i == 0 ? MoveTo(x, y) : LineTo(x, y));
    }
    poly.add(LineTo(
      cx + rx * values.first * math.cos(math.pi / 2),
      cy + ry * values.first * math.sin(math.pi / 2),
    ));
    kids.add(VsdxShape(
      id: next++,
      name: 'RadarFill.$id',
      pinX: cx,
      pinY: cy,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[VsdxGeometry(commands: poly)],
      fill: const VsdxFill(
        foreground: VsdxColor(0xFF5B9BD5),
        foregroundTransparency: 0.4,
      ),
      line: const VsdxLine(
        color: VsdxColor(0xFF2E75B6),
        weightInches: 0.014,
      ),
    ));
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      name: name ?? 'Radar Chart',
    );
  }

  /// Simple gauge / meter (semicircle + needle).
  static VsdxShape gaugeChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.2,
    double height = 1.4,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    final cx = w / 2;
    final cy = h * 0.2;
    final rx = w * 0.42;
    final ry = h * 0.7;
    var next = id + 1;
    final kids = <VsdxShape>[];
    // Three arc bands.
    const bands = <(double, double, VsdxColor)>[
      (math.pi, math.pi * 2 / 3, VsdxColor(0xFF70AD47)),
      (math.pi * 2 / 3, math.pi / 3, VsdxColor(0xFFFFC000)),
      (math.pi / 3, 0, VsdxColor(0xFFED7D31)),
    ];
    for (final b in bands) {
      final a0 = b.$1;
      final a1 = b.$2;
      final mid = (a0 + a1) / 2;
      kids.add(VsdxShape(
        id: next++,
        name: 'Band.$id',
        pinX: w / 2,
        pinY: h / 2,
        width: w,
        height: h,
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(cx, cy),
            LineTo(cx + rx * math.cos(a0), cy + ry * math.sin(a0)),
            EllipticalArcTo(
              x: cx + rx * math.cos(a1),
              y: cy + ry * math.sin(a1),
              controlX: cx + rx * 1.05 * math.cos(mid),
              controlY: cy + ry * 1.05 * math.sin(mid),
            ),
            LineTo(cx, cy),
          ]),
        ],
        fill: VsdxFill(foreground: b.$3),
        line: _barLine(b.$3),
      ));
    }
    // Needle at ~65%.
    const needle = math.pi * 0.35;
    kids.add(VsdxShape(
      id: next++,
      name: 'Needle.$id',
      pinX: w / 2,
      pinY: h / 2,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(cx, cy),
            LineTo(cx + rx * 0.85 * math.cos(needle),
                cy + ry * 0.85 * math.sin(needle)),
          ],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: VsdxColor(0xFF333333),
        weightInches: 0.02,
      ),
    ));
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      name: name ?? 'Gauge',
    );
  }
}
