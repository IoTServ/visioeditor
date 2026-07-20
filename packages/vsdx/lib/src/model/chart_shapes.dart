/// Geometric chart shapes (draw.io / 万兴图示 style) for the Charts palette.
///
/// Each chart is a [VsdxShapeKind.group] tagged with [userChart] / [userKind] /
/// [userValues] so the editor can rebuild series after the user edits data.
library;

import 'dart:math' as math;

import 'fill.dart';
import 'geometry.dart';
import 'line.dart';
import 'page.dart';
import 'shape.dart';
import 'shape_kind.dart';
import 'user_property.dart';
import '../utils/color.dart';

/// Builders and rebuild helpers for chart stencils.
abstract final class ChartOps {
  ChartOps._();

  static const String userChart = 'visioeditor.Chart';
  static const String userKind = 'visioeditor.ChartKind';
  static const String userValues = 'visioeditor.ChartValues';
  /// Marks non-series chrome (axes, grid, track, bridges, needle).
  static const String userChrome = 'visioeditor.ChartChrome';

  static const List<VsdxColor> seriesColors = <VsdxColor>[
    VsdxColor(0xFF5B9BD5),
    VsdxColor(0xFFED7D31),
    VsdxColor(0xFF70AD47),
    VsdxColor(0xFFFFC000),
    VsdxColor(0xFF9E7CC3),
    VsdxColor(0xFF5B9EA6),
  ];

  static const List<double> defaultValues = <double>[0.45, 0.75, 0.55, 0.9];

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

  // ---------------------------------------------------------------------------
  // Identity / data
  // ---------------------------------------------------------------------------

  static bool isChart(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userChart && (c.value == '1' || c.value == 'true')) {
        return true;
      }
    }
    return false;
  }

  /// True for axes / grid / track / bridge / needle children (not series).
  static bool isChartChrome(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userChrome && (c.value == '1' || c.value == 'true')) {
        return true;
      }
    }
    return false;
  }

  static String? chartKind(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userKind) return c.value;
    }
    return null;
  }

  static List<double> chartValues(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userValues) return parseValues(c.value);
    }
    return List<double>.of(defaultValues);
  }

  static List<double> parseValues(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return List<double>.of(defaultValues);
    }
    final out = <double>[];
    for (final part in raw.split(RegExp(r'[,;\s]+'))) {
      if (part.isEmpty) continue;
      final v = double.tryParse(part);
      if (v != null && v.isFinite && v >= 0) out.add(v);
    }
    return out.isEmpty ? List<double>.of(defaultValues) : out;
  }

  static String formatValues(List<double> values) =>
      values.map((v) => v.toStringAsFixed(2)).join(', ');

  static List<VsdxUserCell> _meta(String kind, List<double> values) =>
      <VsdxUserCell>[
        const VsdxUserCell(name: userChart, value: '1'),
        VsdxUserCell(name: userKind, value: kind),
        VsdxUserCell(name: userValues, value: formatValues(values)),
      ];

  static const List<VsdxUserCell> _chromeMeta = <VsdxUserCell>[
    VsdxUserCell(name: userChrome, value: '1'),
  ];

  /// Auto id name so the painter does not treat it as a visible label.
  static String _sheetName(int id) => 'Sheet.$id';

  /// Normalise values into (0, 1] for plotting (keeps relative proportions).
  static List<double> _unit(List<double> values) {
    if (values.isEmpty) return List<double>.of(defaultValues);
    final maxV = values.reduce(math.max);
    if (maxV <= 0) return List<double>.filled(values.length, 0.1);
    return <double>[for (final v in values) (v / maxV).clamp(0.02, 1.0)];
  }

  // ---------------------------------------------------------------------------
  // Rebuild
  // ---------------------------------------------------------------------------

  /// Rebuild [chart] with optional new [values], keeping frame and root id.
  /// Child ids are reassigned via [allocId] (must return unused page ids).
  static VsdxShape rebuild(
    VsdxShape chart, {
    List<double>? values,
    required int Function() allocId,
  }) {
    final kind = chartKind(chart) ?? 'column';
    final vals = values ?? chartValues(chart);
    return buildKind(
      kind,
      id: chart.id,
      pinX: chart.pinX,
      pinY: chart.pinY,
      width: chart.width,
      height: chart.height,
      values: vals,
      allocId: allocId,
    );
  }

  static VsdxShape buildKind(
    String kind, {
    required int id,
    required double pinX,
    required double pinY,
    double? width,
    double? height,
    List<double>? values,
    int Function()? allocId,
  }) {
    switch (kind) {
      case 'bar':
        return barChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'stackedColumn':
        return stackedColumnChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'stackedBar':
        return stackedBarChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'clusteredColumn':
        return clusteredColumnChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'pie':
        return pieChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.0,
            height: height ?? 2.0,
            values: values,
            allocId: allocId);
      case 'donut':
        return donutChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.0,
            height: height ?? 2.0,
            values: values,
            allocId: allocId);
      case 'line':
        return lineChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'area':
        return areaChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'funnel':
        return funnelChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.0,
            height: height ?? 2.2,
            values: values,
            allocId: allocId);
      case 'pyramid':
        return pyramidChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.0,
            height: height ?? 2.2,
            values: values,
            allocId: allocId);
      case 'radar':
        return radarChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.0,
            height: height ?? 2.0,
            values: values,
            allocId: allocId);
      case 'gauge':
        return gaugeChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.2,
            height: height ?? 1.4,
            values: values,
            allocId: allocId);
      case 'progress':
        return progressChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 0.55,
            values: values,
            allocId: allocId);
      case 'waterfall':
        return waterfallChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'bubble':
        return bubbleChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'column':
      default:
        return columnChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
    }
  }

  // ---------------------------------------------------------------------------
  // Shared geometry helpers
  // ---------------------------------------------------------------------------

  static int Function() _seq(int start, int Function()? alloc) {
    if (alloc != null) return alloc;
    var n = start;
    return () => n++;
  }

  static VsdxShape _rectChild({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    required VsdxColor fill,
    bool chrome = false,
  }) {
    final w = math.max(width.abs(), 0.02);
    final h = math.max(height.abs(), 0.02);
    return VsdxShape(
      id: id,
      name: _sheetName(id),
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
      userCells: chrome ? _chromeMeta : const <VsdxUserCell>[],
    );
  }

  /// Axes in Y-up: origin at bottom-left → └ shape.
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
      name: _sheetName(id),
      pinX: w / 2,
      pinY: h / 2,
      width: w,
      height: h,
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(pad * w, (1 - pad) * h),
            LineTo(pad * w, pad * h),
            LineTo((1 - pad) * w, pad * h),
          ],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: _axisLine,
      userCells: _chromeMeta,
    );
  }

  static VsdxShape _group({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    required List<VsdxShape> children,
    required String kind,
    required List<double> values,
  }) {
    final w = width.abs();
    final h = height.abs();
    return VsdxShape(
      id: id,
      // Always Sheet.N — readable stencil titles must not become on-canvas labels.
      name: _sheetName(id),
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      shapeKind: VsdxShapeKind.group,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      connectionPoints: VsdxPage.defaultConnectionPoints(w, h),
      userCells: _meta(kind, values),
      children: children,
    );
  }

  /// Build a wedge (or donut sector) with a tight AABB for hit-testing.
  static VsdxShape _wedgeChild({
    required int id,
    required double cx,
    required double cy,
    required double rx,
    required double ry,
    required double a0,
    required double a1,
    required double inner,
    required VsdxColor fill,
  }) {
    final mid = (a0 + a1) / 2;
    final pts = <({double x, double y})>[];
    void addPolar(double rxi, double ryi, double a) {
      pts.add((x: cx + rxi * math.cos(a), y: cy + ryi * math.sin(a)));
    }

    if (inner <= 0) {
      pts.add((x: cx, y: cy));
      addPolar(rx, ry, a0);
      addPolar(rx, ry, mid);
      addPolar(rx, ry, a1);
    } else {
      addPolar(rx * inner, ry * inner, a0);
      addPolar(rx, ry, a0);
      addPolar(rx, ry, mid);
      addPolar(rx, ry, a1);
      addPolar(rx * inner, ry * inner, a1);
      addPolar(rx * inner, ry * inner, mid);
    }
    var minX = pts.first.x, maxX = pts.first.x;
    var minY = pts.first.y, maxY = pts.first.y;
    for (final p in pts.skip(1)) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    final bw = math.max(maxX - minX, 0.04);
    final bh = math.max(maxY - minY, 0.04);
    double lx(double x) => x - minX;
    double ly(double y) => y - minY;

    final x0 = cx + rx * math.cos(a0);
    final y0 = cy + ry * math.sin(a0);
    final x1 = cx + rx * math.cos(a1);
    final y1 = cy + ry * math.sin(a1);
    // Control point must lie ON the ellipse (MS-VSDX / sampleEllipticalArc).
    final ctrlX = cx + rx * math.cos(mid);
    final ctrlY = cy + ry * math.sin(mid);

    final List<VsdxPathCommand> cmds;
    if (inner <= 0) {
      cmds = <VsdxPathCommand>[
        MoveTo(lx(cx), ly(cy)),
        LineTo(lx(x0), ly(y0)),
        EllipticalArcTo(
            x: lx(x1), y: ly(y1), controlX: lx(ctrlX), controlY: ly(ctrlY)),
        LineTo(lx(cx), ly(cy)),
      ];
    } else {
      final irx = rx * inner;
      final iry = ry * inner;
      final ix0 = cx + irx * math.cos(a0);
      final iy0 = cy + iry * math.sin(a0);
      final ix1 = cx + irx * math.cos(a1);
      final iy1 = cy + iry * math.sin(a1);
      final icx = cx + irx * math.cos(mid);
      final icy = cy + iry * math.sin(mid);
      cmds = <VsdxPathCommand>[
        MoveTo(lx(ix0), ly(iy0)),
        LineTo(lx(x0), ly(y0)),
        EllipticalArcTo(
            x: lx(x1), y: ly(y1), controlX: lx(ctrlX), controlY: ly(ctrlY)),
        LineTo(lx(ix1), ly(iy1)),
        EllipticalArcTo(
            x: lx(ix0), y: ly(iy0), controlX: lx(icx), controlY: ly(icy)),
      ];
    }
    return VsdxShape(
      id: id,
      name: _sheetName(id),
      pinX: minX + bw / 2,
      pinY: minY + bh / 2,
      width: bw,
      height: bh,
      geometries: <VsdxGeometry>[VsdxGeometry(commands: cmds)],
      fill: VsdxFill(foreground: fill),
      line: _barLine(fill),
    );
  }

  // ---------------------------------------------------------------------------
  // Chart builders
  // ---------------------------------------------------------------------------

  static VsdxShape columnChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? defaultValues;
    final unit = _unit(vals);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.12;
    final padB = h * 0.12;
    final padT = h * 0.08;
    final plotW = w - padL - w * 0.08;
    final plotH = h - padB - padT;
    final gap = plotW * 0.08;
    final barW = (plotW - gap * (unit.length + 1)) / unit.length;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < unit.length; i++) {
      final bh = plotH * unit[i];
      final cx = padL + gap + barW / 2 + i * (barW + gap);
      final cy = padB + bh / 2;
      kids.add(_rectChild(
        id: next(),
        pinX: cx,
        pinY: cy,
        width: barW,
        height: bh,
        fill: seriesColors[i % seriesColors.length],
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'column',
      values: vals,
    );
  }

  static VsdxShape barChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? defaultValues;
    final unit = _unit(vals);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.12;
    final padB = h * 0.12;
    final padR = w * 0.08;
    final plotW = w - padL - padR;
    final plotH = h - padB - h * 0.08;
    final gap = plotH * 0.08;
    final barH = (plotH - gap * (unit.length + 1)) / unit.length;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < unit.length; i++) {
      final bw = plotW * unit[i];
      final cy = padB + gap + barH / 2 + i * (barH + gap);
      final cx = padL + bw / 2;
      kids.add(_rectChild(
        id: next(),
        pinX: cx,
        pinY: cy,
        width: bw,
        height: barH,
        fill: seriesColors[i % seriesColors.length],
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'bar',
      values: vals,
    );
  }

  static VsdxShape stackedColumnChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    // values interpreted as flat series repeating every 3 for 3 categories.
    final vals = values ?? const <double>[0.25, 0.2, 0.3, 0.35, 0.25, 0.15, 0.2, 0.35, 0.25];
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final cats = 3;
    final series = 3;
    final padL = w * 0.12;
    final padB = h * 0.12;
    final plotW = w - padL - w * 0.08;
    final plotH = h - padB - h * 0.08;
    final gap = plotW * 0.1;
    final barW = (plotW - gap * (cats + 1)) / cats;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < cats; i++) {
      final cx = padL + gap + barW / 2 + i * (barW + gap);
      var y0 = padB;
      var colSum = 0.0;
      for (var s = 0; s < series; s++) {
        final idx = i * series + s;
        colSum += idx < vals.length ? vals[idx] : 0.15;
      }
      final scale = colSum > 0 ? plotH / colSum : plotH;
      for (var s = 0; s < series; s++) {
        final idx = i * series + s;
        final raw = idx < vals.length ? vals[idx] : 0.15;
        final bh = math.max(raw * scale, 0.02);
        kids.add(_rectChild(
          id: next(),
          pinX: cx,
          pinY: y0 + bh / 2,
          width: barW,
          height: bh,
          fill: seriesColors[s % seriesColors.length],
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
      kind: 'stackedColumn',
      values: vals,
    );
  }

  static VsdxShape stackedBarChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.25, 0.2, 0.3, 0.35, 0.25, 0.15, 0.2, 0.35, 0.25];
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    const cats = 3;
    const series = 3;
    final padL = w * 0.12;
    final padB = h * 0.12;
    final plotW = w - padL - w * 0.08;
    final plotH = h - padB - h * 0.08;
    final gap = plotH * 0.1;
    final barH = (plotH - gap * (cats + 1)) / cats;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < cats; i++) {
      final cy = padB + gap + barH / 2 + i * (barH + gap);
      var x0 = padL;
      var rowSum = 0.0;
      for (var s = 0; s < series; s++) {
        final idx = i * series + s;
        rowSum += idx < vals.length ? vals[idx] : 0.15;
      }
      final scale = rowSum > 0 ? plotW / rowSum : plotW;
      for (var s = 0; s < series; s++) {
        final idx = i * series + s;
        final raw = idx < vals.length ? vals[idx] : 0.15;
        final bw = math.max(raw * scale, 0.02);
        kids.add(_rectChild(
          id: next(),
          pinX: x0 + bw / 2,
          pinY: cy,
          width: bw,
          height: barH,
          fill: seriesColors[s % seriesColors.length],
        ));
        x0 += bw;
      }
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'stackedBar',
      values: vals,
    );
  }

  static VsdxShape clusteredColumnChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.5, 0.7, 0.4, 0.65, 0.55, 0.8];
    final unit = _unit(vals);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    const cats = 3;
    const series = 2;
    final padL = w * 0.12;
    final padB = h * 0.12;
    final plotW = w - padL - w * 0.08;
    final plotH = h - padB - h * 0.08;
    final gap = plotW * 0.1;
    final clusterW = (plotW - gap * (cats + 1)) / cats;
    final barW = clusterW / (series + 0.2);
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < cats; i++) {
      final clusterLeft = padL + gap + i * (clusterW + gap);
      for (var s = 0; s < series; s++) {
        final idx = i * series + s;
        final u = idx < unit.length ? unit[idx] : 0.4;
        final bh = plotH * u;
        final cx = clusterLeft + barW / 2 + s * barW;
        kids.add(_rectChild(
          id: next(),
          pinX: cx,
          pinY: padB + bh / 2,
          width: barW * 0.9,
          height: bh,
          fill: seriesColors[s % seriesColors.length],
        ));
      }
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'clusteredColumn',
      values: vals,
    );
  }

  static VsdxShape _radial({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    required List<double> values,
    required double inner,
    required String kind,
    int Function()? allocId,
  }) {
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final cx = w / 2;
    final cy = h / 2;
    final rx = w * 0.42;
    final ry = h * 0.42;
    final sum = values.fold<double>(0, (a, b) => a + b);
    final norm = sum > 0
        ? values
        : List<double>.filled(math.max(values.length, 1), 1);
    final total = norm.fold<double>(0, (a, b) => a + b);
    final kids = <VsdxShape>[];
    var angle = math.pi / 2;
    for (var i = 0; i < norm.length; i++) {
      final sweep = (norm[i] / total) * 2 * math.pi;
      final a0 = angle;
      final a1 = angle - sweep;
      kids.add(_wedgeChild(
        id: next(),
        cx: cx,
        cy: cy,
        rx: rx,
        ry: ry,
        a0: a0,
        a1: a1,
        inner: inner,
        fill: seriesColors[i % seriesColors.length],
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
      kind: kind,
      values: values,
    );
  }

  static VsdxShape pieChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.0,
    double height = 2.0,
    List<double>? values,
    int Function()? allocId,
  }) =>
      _radial(
        id: id,
        pinX: pinX,
        pinY: pinY,
        width: width,
        height: height,
        values: values ?? const <double>[0.3, 0.25, 0.2, 0.25],
        inner: 0,
        kind: 'pie',
        allocId: allocId,
      );

  static VsdxShape donutChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.0,
    double height = 2.0,
    List<double>? values,
    int Function()? allocId,
  }) =>
      _radial(
        id: id,
        pinX: pinX,
        pinY: pinY,
        width: width,
        height: height,
        values: values ?? const <double>[0.28, 0.22, 0.3, 0.2],
        inner: 0.45,
        kind: 'donut',
        allocId: allocId,
      );

  static VsdxShape lineChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.35, 0.55, 0.45, 0.8, 0.65];
    final unit = _unit(vals);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.12;
    final padB = h * 0.12;
    final padT = h * 0.1;
    final padR = w * 0.08;
    final plotW = w - padL - padR;
    final plotH = h - padB - padT;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    final pts = <({double x, double y})>[];
    for (var i = 0; i < unit.length; i++) {
      final x = padL +
          (unit.length == 1 ? 0 : plotW * i / (unit.length - 1));
      final y = padB + plotH * unit[i];
      pts.add((x: x, y: y));
    }
    // Line as a thin polyline child with AABB of the polyline.
    var minX = pts.first.x, maxX = pts.first.x;
    var minY = pts.first.y, maxY = pts.first.y;
    for (final p in pts.skip(1)) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    final lw = math.max(maxX - minX, 0.04);
    final lh = math.max(maxY - minY, 0.04);
    kids.add(VsdxShape(
      id: next(),
      name: _sheetName(id),
      pinX: minX + lw / 2,
      pinY: minY + lh / 2,
      width: lw,
      height: lh,
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(pts.first.x - minX, pts.first.y - minY),
            for (final p in pts.skip(1))
              LineTo(p.x - minX, p.y - minY),
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
        id: next(),
        name: _sheetName(id),
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
        fill: VsdxFill(foreground: seriesColors[i % seriesColors.length]),
        line: _barLine(seriesColors[i % seriesColors.length]),
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'line',
      values: vals,
    );
  }

  static VsdxShape areaChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.3, 0.6, 0.5, 0.85, 0.55];
    final unit = _unit(vals);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.12;
    final padB = h * 0.12;
    final padT = h * 0.1;
    final padR = w * 0.08;
    final plotW = w - padL - padR;
    final plotH = h - padB - padT;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    final pts = <({double x, double y})>[];
    for (var i = 0; i < unit.length; i++) {
      final x = padL +
          (unit.length == 1 ? 0 : plotW * i / (unit.length - 1));
      final y = padB + plotH * unit[i];
      pts.add((x: x, y: y));
    }
    var minX = pts.first.x, maxX = pts.first.x;
    var minY = padB, maxY = pts.first.y;
    for (final p in pts) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    final aw = math.max(maxX - minX, 0.04);
    final ah = math.max(maxY - minY, 0.04);
    kids.add(VsdxShape(
      id: next(),
      name: _sheetName(id),
      pinX: minX + aw / 2,
      pinY: minY + ah / 2,
      width: aw,
      height: ah,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(pts.first.x - minX, padB - minY),
          LineTo(pts.first.x - minX, pts.first.y - minY),
          for (final p in pts.skip(1)) LineTo(p.x - minX, p.y - minY),
          LineTo(pts.last.x - minX, padB - minY),
          LineTo(pts.first.x - minX, padB - minY),
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
      kind: 'area',
      values: vals,
    );
  }

  static VsdxShape funnelChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.0,
    double height = 2.2,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[1.0, 0.78, 0.55, 0.35];
    final unit = _unit(vals);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final bandH = h * 0.18;
    final gap = h * 0.04;
    final kids = <VsdxShape>[];
    var top = h * 0.88;
    for (var i = 0; i < unit.length; i++) {
      final bw = w * (0.35 + 0.65 * unit[i]);
      final cy = top - bandH / 2;
      kids.add(_rectChild(
        id: next(),
        pinX: w / 2,
        pinY: cy,
        width: bw,
        height: bandH,
        fill: seriesColors[i % seriesColors.length],
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
      kind: 'funnel',
      values: vals,
    );
  }

  static VsdxShape pyramidChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.0,
    double height = 2.2,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.35, 0.55, 0.78, 1.0];
    final unit = _unit(vals);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final bandH = h * 0.18;
    final gap = h * 0.04;
    final kids = <VsdxShape>[];
    var bottom = h * 0.12;
    for (var i = 0; i < unit.length; i++) {
      final bw = w * (0.35 + 0.65 * unit[i]);
      final cy = bottom + bandH / 2;
      kids.add(_rectChild(
        id: next(),
        pinX: w / 2,
        pinY: cy,
        width: bw,
        height: bandH,
        fill: seriesColors[i % seriesColors.length],
      ));
      bottom += bandH + gap;
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'pyramid',
      values: vals,
    );
  }

  static VsdxShape radarChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.0,
    double height = 2.0,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.7, 0.55, 0.85, 0.45, 0.65];
    final unit = _unit(vals);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final cx = w / 2;
    final cy = h / 2;
    final rx = w * 0.4;
    final ry = h * 0.4;
    final kids = <VsdxShape>[];
    final gridCmds = <VsdxGeometry>[];
    for (final t in <double>[0.33, 0.66, 1.0]) {
      final ring = <VsdxPathCommand>[];
      for (var i = 0; i <= unit.length; i++) {
        final a = math.pi / 2 - (i % unit.length) * 2 * math.pi / unit.length;
        final x = cx + rx * t * math.cos(a);
        final y = cy + ry * t * math.sin(a);
        ring.add(i == 0 ? MoveTo(x, y) : LineTo(x, y));
      }
      gridCmds.add(VsdxGeometry(noFill: true, commands: ring));
    }
    for (var i = 0; i < unit.length; i++) {
      final a = math.pi / 2 - i * 2 * math.pi / unit.length;
      gridCmds.add(VsdxGeometry(
        noFill: true,
        commands: <VsdxPathCommand>[
          MoveTo(cx, cy),
          LineTo(cx + rx * math.cos(a), cy + ry * math.sin(a)),
        ],
      ));
    }
    kids.add(VsdxShape(
      id: next(),
      name: _sheetName(id),
      pinX: cx,
      pinY: cy,
      width: w,
      height: h,
      geometries: gridCmds,
      fill: const VsdxFill(pattern: 0),
      line: _axisLine,
      userCells: _chromeMeta,
    ));
    final polyPts = <({double x, double y})>[];
    for (var i = 0; i < unit.length; i++) {
      final a = math.pi / 2 - i * 2 * math.pi / unit.length;
      polyPts.add((
        x: cx + rx * unit[i] * math.cos(a),
        y: cy + ry * unit[i] * math.sin(a),
      ));
    }
    var minX = polyPts.first.x, maxX = polyPts.first.x;
    var minY = polyPts.first.y, maxY = polyPts.first.y;
    for (final p in polyPts.skip(1)) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    final pw = math.max(maxX - minX, 0.04);
    final ph = math.max(maxY - minY, 0.04);
    kids.add(VsdxShape(
      id: next(),
      name: _sheetName(id),
      pinX: minX + pw / 2,
      pinY: minY + ph / 2,
      width: pw,
      height: ph,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(polyPts.first.x - minX, polyPts.first.y - minY),
          for (final p in polyPts.skip(1))
            LineTo(p.x - minX, p.y - minY),
          LineTo(polyPts.first.x - minX, polyPts.first.y - minY),
        ]),
      ],
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
      kind: 'radar',
      values: vals,
    );
  }

  static VsdxShape gaugeChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.2,
    double height = 1.4,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.65];
    final level = vals.first.clamp(0.0, 1.0);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final cx = w / 2;
    final cy = h * 0.22;
    final r = math.min(w, h) * 0.42;
    final kids = <VsdxShape>[];
    // Three annular bands (circular) from π → 0.
    const bands = <(double, double, VsdxColor)>[
      (math.pi, math.pi * 2 / 3, VsdxColor(0xFF70AD47)),
      (math.pi * 2 / 3, math.pi / 3, VsdxColor(0xFFFFC000)),
      (math.pi / 3, 0.0, VsdxColor(0xFFED7D31)),
    ];
    const inner = 0.62;
    for (final b in bands) {
      kids.add(_wedgeChild(
        id: next(),
        cx: cx,
        cy: cy,
        rx: r,
        ry: r,
        a0: b.$1,
        a1: b.$2,
        inner: inner,
        fill: b.$3,
      ));
    }
    final needle = math.pi * (1 - level);
    final nx = cx + r * 0.82 * math.cos(needle);
    final ny = cy + r * 0.82 * math.sin(needle);
    final nMinX = math.min(cx, nx) - 0.02;
    final nMaxX = math.max(cx, nx) + 0.02;
    final nMinY = math.min(cy, ny) - 0.02;
    final nMaxY = math.max(cy, ny) + 0.02;
    kids.add(VsdxShape(
      id: next(),
      name: _sheetName(id),
      pinX: (nMinX + nMaxX) / 2,
      pinY: (nMinY + nMaxY) / 2,
      width: math.max(nMaxX - nMinX, 0.04),
      height: math.max(nMaxY - nMinY, 0.04),
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(cx - nMinX, cy - nMinY),
            LineTo(nx - nMinX, ny - nMinY),
          ],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: VsdxColor(0xFF333333),
        weightInches: 0.02,
      ),
      userCells: _chromeMeta,
    ));
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'gauge',
      values: vals,
    );
  }

  static VsdxShape progressChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 0.55,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.68];
    final level = vals.first.clamp(0.0, 1.0);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final kids = <VsdxShape>[
      _rectChild(
        id: next(),
        pinX: w / 2,
        pinY: h / 2,
        width: w,
        height: h * 0.55,
        fill: const VsdxColor(0xFFE8E8E8),
        chrome: true,
      ),
      _rectChild(
        id: next(),
        pinX: (w * level) / 2,
        pinY: h / 2,
        width: math.max(w * level, 0.04),
        height: h * 0.55,
        fill: seriesColors.first,
      ),
    ];
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'progress',
      values: vals,
    );
  }

  static VsdxShape waterfallChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.4, 0.25, -0.15, 0.3, -0.1];
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.1;
    final padB = h * 0.12;
    final plotW = w - padL - w * 0.08;
    final plotH = h - padB - h * 0.08;
    final gap = plotW * 0.06;
    final barW = (plotW - gap * (vals.length + 1)) / vals.length;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    var running = 0.0;
    final scale =
        plotH / (vals.map((v) => v.abs()).fold(0.0, (a, b) => a + b) + 0.01);
    for (var i = 0; i < vals.length; i++) {
      final step = vals[i];
      final bh = math.max(step.abs() * scale, 0.04);
      final cy = step >= 0
          ? padB + running * scale + bh / 2
          : padB + (running + step) * scale + bh / 2;
      final cx = padL + gap + barW / 2 + i * (barW + gap);
      kids.add(_rectChild(
        id: next(),
        pinX: cx,
        pinY: cy,
        width: barW,
        height: bh,
        fill: step >= 0 ? seriesColors[0] : seriesColors[1],
      ));
      if (i < vals.length - 1) {
        final connectorY = step >= 0 ? cy + bh / 2 : cy - bh / 2;
        final nextX = padL + gap + barW / 2 + (i + 1) * (barW + gap);
        kids.add(VsdxShape(
          id: next(),
          name: _sheetName(id),
          pinX: (cx + nextX) / 2,
          pinY: connectorY,
          width: math.max((nextX - cx).abs(), 0.04),
          height: 0.04,
          geometries: <VsdxGeometry>[
            VsdxGeometry(
              noFill: true,
              commands: <VsdxPathCommand>[
                MoveTo(0, 0.02),
                LineTo(math.max((nextX - cx).abs(), 0.04), 0.02),
              ],
            ),
          ],
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(
            color: VsdxColor(0xFF888888),
            weightInches: 0.008,
            pattern: 2,
          ),
          userCells: _chromeMeta,
        ));
      }
      running += step;
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'waterfall',
      values: vals,
    );
  }

  static VsdxShape bubbleChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    // Triples: x, y, size (0..1-ish), repeated.
    final vals = values ??
        const <double>[0.2, 0.4, 0.35, 0.55, 0.7, 0.55, 0.75, 0.35, 0.25, 0.4, 0.55, 0.7];
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.12;
    final padB = h * 0.12;
    final plotW = w - padL - w * 0.1;
    final plotH = h - padB - h * 0.1;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    final n = vals.length ~/ 3;
    for (var i = 0; i < n; i++) {
      final x = vals[i * 3].clamp(0.0, 1.0);
      final y = vals[i * 3 + 1].clamp(0.0, 1.0);
      final s = vals[i * 3 + 2].clamp(0.15, 1.0);
      final r = 0.08 + 0.18 * s;
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: padL + plotW * x,
        pinY: padB + plotH * y,
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
        fill: VsdxFill(
          foreground: seriesColors[i % seriesColors.length],
          foregroundTransparency: 0.25,
        ),
        line: _barLine(seriesColors[i % seriesColors.length]),
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'bubble',
      values: vals,
    );
  }
}
