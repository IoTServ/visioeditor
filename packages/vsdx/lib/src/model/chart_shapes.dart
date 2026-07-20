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
import 'rich_text.dart';
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
  static const String userColors = 'visioeditor.ChartColors';
  static const String userLabels = 'visioeditor.ChartLabels';
  /// Full series stashed when switching to a single-value kind (gauge/progress).
  static const String userValuesBackup = 'visioeditor.ChartValuesBackup';
  static const String userColorsBackup = 'visioeditor.ChartColorsBackup';
  static const String userLabelsBackup = 'visioeditor.ChartLabelsBackup';
  /// Marks legend / category-label chrome under the plot.
  static const String userLegend = 'visioeditor.ChartLegend';
  /// Marks non-series chrome (axes, grid, track, bridges, needle).
  static const String userChrome = 'visioeditor.ChartChrome';

  static const int maxSeriesItems = 12;

  /// Kind picker groups for the editor (group title → kind keys).
  static const List<(String, List<String>)> kindGroups =
      <(String, List<String>)>[
    ('Bars & columns', <String>[
      'column',
      'bar',
      'histogram',
      'cylinder',
      'cone',
      'stackedColumn',
      'stackedBar',
      'clusteredColumn',
      'clusteredBar',
      'lollipop',
      'horizontalLollipop',
      'divergingBar',
      'dotPlot',
    ]),
    ('Pies', <String>['pie', 'donut', 'semiDonut', 'rose']),
    ('Lines & areas', <String>['line', 'stepLine', 'area', 'stepArea', 'radar']),
    ('Process', <String>[
      'funnel',
      'pyramid',
      'waterfall',
      'radialBar',
      'compositionBar',
      'percentColumn',
      'treemap',
      'packedBubble',
    ]),
    ('Meters', <String>[
      'gauge',
      'progress',
      'ringProgress',
      'bullet',
      'thermometer',
      'waffle',
    ]),
    ('Other', <String>['bubble']),
  ];

  /// Chart kinds exposed in the editor type picker (value → stencil English name).
  static const Map<String, String> kindDisplayNames = <String, String>{
    'column': 'Column Chart',
    'bar': 'Bar Chart',
    'histogram': 'Histogram',
    'cylinder': 'Cylinder Chart',
    'cone': 'Cone Chart',
    'stackedColumn': 'Stacked Column',
    'stackedBar': 'Stacked Bar',
    'clusteredColumn': 'Clustered Column',
    'clusteredBar': 'Clustered Bar',
    'lollipop': 'Lollipop Chart',
    'horizontalLollipop': 'Horizontal Lollipop',
    'divergingBar': 'Diverging Bar',
    'dotPlot': 'Dot Plot',
    'pie': 'Pie Chart',
    'donut': 'Donut Chart',
    'semiDonut': 'Semi Donut',
    'rose': 'Rose Chart',
    'line': 'Line Chart',
    'stepLine': 'Step Line',
    'area': 'Area Chart',
    'stepArea': 'Step Area',
    'funnel': 'Funnel',
    'pyramid': 'Pyramid Chart',
    'radar': 'Radar Chart',
    'radialBar': 'Radial Bar',
    'compositionBar': 'Composition Bar',
    'percentColumn': 'Percent Column',
    'treemap': 'Treemap',
    'packedBubble': 'Packed Bubble',
    'gauge': 'Gauge',
    'progress': 'Progress',
    'ringProgress': 'Ring Progress',
    'bullet': 'Bullet Chart',
    'thermometer': 'Thermometer',
    'waffle': 'Waffle Chart',
    'waterfall': 'Waterfall',
    'bubble': 'Bubble Chart',
  };

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

  /// True for axes / grid / track / bridge / needle / legend children.
  static bool isChartChrome(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userChrome && (c.value == '1' || c.value == 'true')) {
        return true;
      }
      if (c.name == userLegend && (c.value == '1' || c.value == 'true')) {
        return true;
      }
    }
    return false;
  }

  static bool isLegend(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userLegend && (c.value == '1' || c.value == 'true')) {
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

  static List<String> chartLabels(VsdxShape s, [int? count]) {
    final n = count ?? chartValues(s).length;
    for (final c in s.userCells) {
      if (c.name == userLabels) return parseLabels(c.value, n);
    }
    return defaultLabels(n);
  }

  static String defaultLabel(int index) => 'Item ${index + 1}';

  static List<String> defaultLabels(int n) => <String>[
        for (var i = 0; i < n; i++) defaultLabel(i),
      ];

  static List<String> parseLabels(String? raw, int count) {
    if (count <= 0) return const <String>[];
    if (raw == null || raw.trim().isEmpty) return defaultLabels(count);
    final parts = raw.split('|');
    return <String>[
      for (var i = 0; i < count; i++)
        (i < parts.length && parts[i].trim().isNotEmpty)
            ? parts[i].trim()
            : defaultLabel(i),
    ];
  }

  static String formatLabels(List<String> labels) =>
      labels.map((l) => l.replaceAll('|', '/').trim()).join('|');

  static List<String> padLabels(List<String> labels, int n) {
    if (n <= 0) return const <String>[];
    return <String>[
      for (var i = 0; i < n; i++)
        (i < labels.length && labels[i].trim().isNotEmpty)
            ? labels[i].trim()
            : defaultLabel(i),
    ];
  }

  /// Parse a unit fraction from `0.68`, `68`, or `68%`.
  static double parseUnitValue(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return 0;
    if (s.endsWith('%')) {
      final v = double.tryParse(s.substring(0, s.length - 1).trim());
      return ((v ?? 0) / 100).clamp(0.0, 1.0);
    }
    final v = double.tryParse(s.replaceAll(',', '.'));
    if (v == null || !v.isFinite) return 0;
    if (v > 1) return (v / 100).clamp(0.0, 1.0);
    return v.clamp(0.0, 1.0);
  }

  static String formatPercent(double unit) =>
      '${(unit.clamp(0.0, 1.0) * 100).round()}';

  static List<double>? _backupValues(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userValuesBackup) {
        final v = parseValues(c.value);
        return v.length > 1 ? v : null;
      }
    }
    return null;
  }

  static List<VsdxColor>? _backupColors(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userColorsBackup) {
        final v = parseColors(c.value);
        return v.isNotEmpty ? v : null;
      }
    }
    return null;
  }

  static List<String>? _backupLabels(VsdxShape s) {
    for (final c in s.userCells) {
      final raw = c.value;
      if (c.name == userLabelsBackup && raw != null && raw.trim().isNotEmpty) {
        return raw.split('|');
      }
    }
    return null;
  }

  static List<double> parseValues(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return List<double>.of(defaultValues);
    }
    final out = <double>[];
    for (final part in raw.split(RegExp(r'[,;\s]+'))) {
      if (part.isEmpty) continue;
      final v = double.tryParse(part);
      if (v != null && v.isFinite) out.add(v);
    }
    return out.isEmpty ? List<double>.of(defaultValues) : out;
  }

  /// Paste helper: `1, 2, 3` or `North: 1; South: 2` → values (+ optional labels).
  static ({List<double> values, List<String>? labels}) parseSeriesPaste(
    String? raw,
  ) {
    if (raw == null || raw.trim().isEmpty) {
      return (values: List<double>.of(defaultValues), labels: null);
    }
    final chunks = raw
        .split(RegExp(r'[\n;]+'))
        .expand((line) => line.split(','))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (chunks.isEmpty) {
      return (values: List<double>.of(defaultValues), labels: null);
    }
    final vals = <double>[];
    final labs = <String>[];
    var labeled = 0;
    for (final chunk in chunks) {
      final colon = chunk.indexOf(':');
      if (colon > 0) {
        final name = chunk.substring(0, colon).trim();
        final num = double.tryParse(
          chunk.substring(colon + 1).trim().replaceAll(',', '.'),
        );
        if (num != null && num.isFinite) {
          labs.add(name.isEmpty ? defaultLabel(vals.length) : name);
          vals.add(num);
          labeled++;
          continue;
        }
      }
      final num = double.tryParse(chunk.replaceAll(',', '.'));
      if (num != null && num.isFinite) {
        vals.add(num);
        labs.add(defaultLabel(vals.length - 1));
      }
    }
    if (vals.isEmpty) {
      return (values: List<double>.of(defaultValues), labels: null);
    }
    if (vals.length > maxSeriesItems) {
      return (
        values: vals.sublist(0, maxSeriesItems),
        labels: labeled > 0 ? labs.sublist(0, maxSeriesItems) : null,
      );
    }
    return (values: vals, labels: labeled > 0 ? labs : null);
  }

  static String formatValues(List<double> values) =>
      values.map((v) => _fmtNum(v)).join(', ');

  static String _fmtNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  static List<VsdxColor> parseColors(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <VsdxColor>[];
    final out = <VsdxColor>[];
    for (final part in raw.split(RegExp(r'[,;\s]+'))) {
      if (part.isEmpty) continue;
      var hex = part.trim();
      if (hex.startsWith('#')) hex = hex.substring(1);
      if (hex.length == 6) hex = 'FF$hex';
      final v = int.tryParse(hex, radix: 16);
      if (v != null) out.add(VsdxColor(v));
    }
    return out;
  }

  static String formatColors(List<VsdxColor> colors) => colors
      .map((c) =>
          '#${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}')
      .join(', ');

  /// Series fills for [chart], from userCells or derived from children.
  static List<VsdxColor> chartColors(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userColors) {
        final parsed = parseColors(c.value);
        if (parsed.isNotEmpty) return parsed;
      }
    }
    final derived = <VsdxColor>[];
    for (final c in s.children) {
      if (isChartChrome(c)) continue;
      final fg = c.fill.foreground;
      if (fg != null) derived.add(fg);
    }
    if (derived.isNotEmpty) return derived;
    return List<VsdxColor>.of(seriesColors);
  }

  static List<VsdxShape> seriesChildren(VsdxShape chart) => <VsdxShape>[
        for (final c in chart.children)
          if (!isChartChrome(c)) c,
      ];

  static bool isSingleValueKind(String kind) =>
      kind == 'gauge' ||
      kind == 'progress' ||
      kind == 'ringProgress' ||
      kind == 'bullet' ||
      kind == 'thermometer' ||
      kind == 'waffle';

  static List<VsdxColor> padColors(List<VsdxColor> colors, int n) {
    if (n <= 0) return const <VsdxColor>[];
    if (colors.isEmpty) {
      return <VsdxColor>[
        for (var i = 0; i < n; i++) seriesColors[i % seriesColors.length],
      ];
    }
    return <VsdxColor>[
      for (var i = 0; i < n; i++) colors[i % colors.length],
    ];
  }

  static List<VsdxUserCell> _meta(
    String kind,
    List<double> values, {
    List<VsdxColor>? colors,
    List<String>? labels,
    List<double>? valuesBackup,
    List<VsdxColor>? colorsBackup,
    List<String>? labelsBackup,
  }) =>
      <VsdxUserCell>[
        const VsdxUserCell(name: userChart, value: '1'),
        VsdxUserCell(name: userKind, value: kind),
        VsdxUserCell(name: userValues, value: formatValues(values)),
        if (colors != null && colors.isNotEmpty)
          VsdxUserCell(name: userColors, value: formatColors(colors)),
        if (labels != null && labels.isNotEmpty)
          VsdxUserCell(name: userLabels, value: formatLabels(labels)),
        if (valuesBackup != null && valuesBackup.length > 1)
          VsdxUserCell(
              name: userValuesBackup, value: formatValues(valuesBackup)),
        if (colorsBackup != null && colorsBackup.isNotEmpty)
          VsdxUserCell(
              name: userColorsBackup, value: formatColors(colorsBackup)),
        if (labelsBackup != null && labelsBackup.isNotEmpty)
          VsdxUserCell(
              name: userLabelsBackup, value: formatLabels(labelsBackup)),
      ];

  static const _metaKeys = <String>{
    userChart,
    userKind,
    userValues,
    userColors,
    userLabels,
    userValuesBackup,
    userColorsBackup,
    userLabelsBackup,
  };

  static const List<VsdxUserCell> _chromeMeta = <VsdxUserCell>[
    VsdxUserCell(name: userChrome, value: '1'),
  ];

  /// Auto id name so the painter does not treat it as a visible label.
  static String _sheetName(int id) => 'Sheet.$id';

  /// Normalise values into (0, 1] for plotting (keeps relative proportions).
  static List<double> _unit(List<double> values) {
    if (values.isEmpty) return List<double>.of(defaultValues);
    final maxV = values.map((v) => v.abs()).reduce(math.max);
    if (maxV <= 0) return List<double>.filled(values.length, 0.1);
    return <double>[
      for (final v in values) (v.abs() / maxV).clamp(0.02, 1.0),
    ];
  }

  /// Apply [colors] to non-chrome children (in order) and persist on the root.
  static VsdxShape withSeriesColors(
    VsdxShape chart,
    List<VsdxColor> colors, {
    List<String>? labels,
    List<double>? valuesBackup,
    List<VsdxColor>? colorsBackup,
    List<String>? labelsBackup,
  }) {
    final kind = chartKind(chart) ?? 'column';
    final vals = chartValues(chart);
    final padded = padColors(colors, math.max(vals.length, 1));
    final labs =
        padLabels(labels ?? chartLabels(chart, vals.length), vals.length);
    // Gauge keeps its traffic-light bands; only persist the meta colours.
    final List<VsdxShape> kids;
    if (kind == 'gauge') {
      kids = chart.children;
    } else if (kind == 'ringProgress' ||
        kind == 'waffle' ||
        kind == 'thermometer') {
      // All value glyphs share the single series colour.
      final color = padded.first;
      kids = <VsdxShape>[
        for (final c in chart.children)
          if (isChartChrome(c)) c else _recolor(c, color),
      ];
    } else {
      final series = seriesChildren(chart);
      final byId = <int, VsdxColor>{};
      if (series.length == vals.length) {
        for (var i = 0; i < series.length; i++) {
          byId[series[i].id] = padded[i];
        }
      } else if (series.length == vals.length + 1 && vals.isNotEmpty) {
        // Line / area / radar: shared stroke/fill first, then per-point marks.
        byId[series.first.id] = padded.first;
        for (var i = 0; i < vals.length; i++) {
          byId[series[i + 1].id] = padded[i];
        }
      } else {
        for (var i = 0; i < series.length; i++) {
          byId[series[i].id] = padded[i % padded.length];
        }
      }
      kids = <VsdxShape>[
        for (final c in chart.children)
          if (byId[c.id] case final color?) _recolor(c, color) else c,
      ];
    }
    final kept = <VsdxUserCell>[
      for (final c in chart.userCells)
        if (!_metaKeys.contains(c.name)) c,
    ];
    return chart.copyWith(
      children: kids,
      userCells: <VsdxUserCell>[
        ...kept,
        ..._meta(
          kind,
          vals,
          colors: padded,
          labels: labs,
          valuesBackup: valuesBackup ?? _backupValues(chart),
          colorsBackup: colorsBackup ?? _backupColors(chart),
          labelsBackup: labelsBackup ?? _backupLabels(chart),
        ),
      ],
    );
  }

  static VsdxShape _recolor(VsdxShape s, VsdxColor color) {
    final fill = s.fill;
    return s.copyWith(
      fill: fill.copyWith(
        foreground: color,
        pattern: fill.pattern == 0 ? 1 : fill.pattern,
      ),
      line: s.line.copyWith(color: VsdxColor(_darken(color.value))),
    );
  }

  static const List<VsdxUserCell> _legendMeta = <VsdxUserCell>[
    VsdxUserCell(name: userChrome, value: '1'),
    VsdxUserCell(name: userLegend, value: '1'),
  ];

  /// Category labels along the bottom of the chart (visible on canvas).
  static VsdxShape withCategoryLabels(
    VsdxShape chart,
    List<String> labels,
    List<VsdxColor> colors, {
    required int Function() allocId,
  }) {
    final kind = chartKind(chart) ?? 'column';
    final baseKids = <VsdxShape>[
      for (final c in chart.children)
        if (!isLegend(c)) c,
    ];
    if (isSingleValueKind(kind) || labels.isEmpty) {
      return chart.copyWith(children: baseKids);
    }
    final w = chart.width.abs();
    final h = chart.height.abs();
    final n = labels.length;
    final legendH = math.min(0.2, h * 0.12).clamp(0.12, 0.22);
    final slotW = w / n;
    final font = (legendH * 0.42).clamp(0.07, 0.11);
    final kids = <VsdxShape>[...baseKids];
    for (var i = 0; i < n; i++) {
      final raw = labels[i].trim().isEmpty ? defaultLabel(i) : labels[i].trim();
      final text = raw.length > 12 ? '${raw.substring(0, 11)}…' : raw;
      final id = allocId();
      kids.add(VsdxShape(
        id: id,
        name: _sheetName(id),
        pinX: slotW * i + slotW / 2,
        pinY: legendH / 2,
        width: math.max(slotW * 0.9, 0.12),
        height: legendH,
        text: text,
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: text,
            charStyle: VsdxCharStyle(
              fontSizeInches: font,
              color: colors[i % colors.length],
            ),
            paraStyle: const VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
            ),
          ),
        ]),
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            noLine: true,
            commands: <VsdxPathCommand>[
              const MoveTo(0, 0),
              LineTo(math.max(slotW * 0.9, 0.12), 0),
              LineTo(math.max(slotW * 0.9, 0.12), legendH),
              LineTo(0, legendH),
              const LineTo(0, 0),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
        userCells: _legendMeta,
      ));
    }
    return chart.copyWith(children: kids);
  }

  // ---------------------------------------------------------------------------
  // Rebuild
  // ---------------------------------------------------------------------------

  /// Rebuild [chart] with optional new [values] / [colors] / [labels] / [kind].
  /// Child ids are reassigned via [allocId] (must return unused page ids).
  static VsdxShape rebuild(
    VsdxShape chart, {
    List<double>? values,
    List<VsdxColor>? colors,
    List<String>? labels,
    String? kind,
    required int Function() allocId,
  }) {
    final prevKind = chartKind(chart) ?? 'column';
    final k = kind ?? prevKind;
    final prevVals = chartValues(chart);
    final prevCols = chartColors(chart);
    final prevLabs = chartLabels(chart, prevVals.length);

    var vals = List<double>.of(values ?? prevVals);
    var cols = List<VsdxColor>.of(colors ?? prevCols);
    var labs = List<String>.of(labels ?? prevLabs);

    List<double>? valuesBackup = _backupValues(chart);
    List<VsdxColor>? colorsBackup = _backupColors(chart);
    List<String>? labelsBackup = _backupLabels(chart);

    // Multi → single: stash full series so switching back can restore.
    if (isSingleValueKind(k) && !isSingleValueKind(prevKind) && prevVals.length > 1) {
      valuesBackup = List<double>.of(prevVals);
      colorsBackup = List<VsdxColor>.of(prevCols);
      labelsBackup = List<String>.of(prevLabs);
      if (values == null) vals = <double>[prevVals.first.clamp(0.0, 1.0)];
    }

    // Single → multi: restore stashed series when caller did not pass values.
    if (!isSingleValueKind(k) &&
        isSingleValueKind(prevKind) &&
        values == null &&
        valuesBackup != null &&
        valuesBackup.length > 1) {
      vals = List<double>.of(valuesBackup);
      if (colors == null && colorsBackup != null) {
        cols = List<VsdxColor>.of(colorsBackup);
      }
      if (labels == null && labelsBackup != null) {
        labs = padLabels(labelsBackup, vals.length);
      }
      valuesBackup = null;
      colorsBackup = null;
      labelsBackup = null;
    }

    if (isSingleValueKind(k) && vals.length > 1) {
      vals = <double>[vals.first.clamp(0.0, 1.0)];
    }
    if (vals.isEmpty) vals = List<double>.of(defaultValues);
    if (vals.length > maxSeriesItems) {
      vals = vals.sublist(0, maxSeriesItems);
    }
    cols = padColors(cols, vals.length);
    labs = padLabels(labs, vals.length);

    final built = buildKind(
      k,
      id: chart.id,
      pinX: chart.pinX,
      pinY: chart.pinY,
      width: chart.width,
      height: chart.height,
      values: vals,
      allocId: allocId,
    );
    final colored = withSeriesColors(
      built,
      cols,
      labels: labs,
      valuesBackup: valuesBackup,
      colorsBackup: colorsBackup,
      labelsBackup: labelsBackup,
    );
    return withCategoryLabels(colored, labs, cols, allocId: allocId);
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
      case 'clusteredBar':
        return clusteredBarChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'lollipop':
        return lollipopChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'horizontalLollipop':
        return horizontalLollipopChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'histogram':
        return histogramChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'cylinder':
        return cylinderChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'cone':
        return coneChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'divergingBar':
        return divergingBarChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'dotPlot':
        return dotPlotChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'compositionBar':
        return compositionBarChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 0.7,
            values: values,
            allocId: allocId);
      case 'percentColumn':
        return percentColumnChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 1.2,
            height: height ?? 2.2,
            values: values,
            allocId: allocId);
      case 'treemap':
        return treemapChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'packedBubble':
        return packedBubbleChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'bullet':
        return bulletChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 0.7,
            values: values,
            allocId: allocId);
      case 'thermometer':
        return thermometerChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 0.7,
            height: height ?? 2.2,
            values: values,
            allocId: allocId);
      case 'waffle':
        return waffleChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.0,
            height: height ?? 2.0,
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
      case 'semiDonut':
        return semiDonutChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.2,
            height: height ?? 1.4,
            values: values,
            allocId: allocId);
      case 'rose':
        return roseChart(
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
      case 'stepLine':
        return stepLineChart(
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
      case 'stepArea':
        return stepAreaChart(
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
      case 'radialBar':
        return radialBarChart(
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
      case 'ringProgress':
        return ringProgressChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.0,
            height: height ?? 2.0,
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
    double startAngle = math.pi / 2,
    double totalSweep = math.pi * 2,
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
    var angle = startAngle;
    final sweepSpan = totalSweep.abs() < 1e-9 ? math.pi * 2 : totalSweep;
    for (var i = 0; i < norm.length; i++) {
      final sweep = (norm[i] / total) * sweepSpan;
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

  static VsdxShape clusteredBarChart({
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
    final gap = plotH * 0.1;
    final clusterH = (plotH - gap * (cats + 1)) / cats;
    final barH = clusterH / (series + 0.2);
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < cats; i++) {
      final clusterBottom = padB + gap + i * (clusterH + gap);
      for (var s = 0; s < series; s++) {
        final idx = i * series + s;
        final u = idx < unit.length ? unit[idx] : 0.4;
        final bw = plotW * u;
        final cy = clusterBottom + barH / 2 + s * barH;
        kids.add(_rectChild(
          id: next(),
          pinX: padL + bw / 2,
          pinY: cy,
          width: bw,
          height: barH * 0.9,
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
      kind: 'clusteredBar',
      values: vals,
    );
  }

  static VsdxShape lollipopChart({
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
    final slot = (plotW - gap * (unit.length + 1)) / unit.length;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < unit.length; i++) {
      final cx = padL + gap + slot / 2 + i * (slot + gap);
      final top = padB + plotH * unit[i];
      final stemH = math.max(top - padB, 0.04);
      kids.add(_rectChild(
        id: next(),
        pinX: cx,
        pinY: padB + stemH / 2,
        width: 0.03,
        height: stemH,
        fill: const VsdxColor(0xFFB0B0B0),
        chrome: true,
      ));
      const r = 0.07;
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: cx,
        pinY: top,
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
      kind: 'lollipop',
      values: vals,
    );
  }

  static VsdxShape semiDonutChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.2,
    double height = 1.4,
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
        inner: 0.55,
        kind: 'semiDonut',
        allocId: allocId,
        startAngle: math.pi,
        totalSweep: math.pi,
      );

  static VsdxShape roseChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.0,
    double height = 2.0,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.55, 0.8, 0.4, 0.7, 0.5, 0.65];
    final unit = _unit(vals);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final cx = w / 2;
    final cy = h / 2;
    final rx = w * 0.42;
    final ry = h * 0.42;
    final sweep = (2 * math.pi) / unit.length;
    var angle = math.pi / 2;
    final kids = <VsdxShape>[];
    for (var i = 0; i < unit.length; i++) {
      final a0 = angle;
      final a1 = angle - sweep;
      final scale = unit[i];
      kids.add(_wedgeChild(
        id: next(),
        cx: cx,
        cy: cy,
        rx: rx * scale,
        ry: ry * scale,
        a0: a0,
        a1: a1,
        inner: 0,
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
      kind: 'rose',
      values: vals,
    );
  }

  static VsdxShape stepLineChart({
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
    final stepPts = <({double x, double y})>[pts.first];
    for (var i = 1; i < pts.length; i++) {
      stepPts.add((x: pts[i].x, y: pts[i - 1].y));
      stepPts.add(pts[i]);
    }
    var minX = stepPts.first.x, maxX = stepPts.first.x;
    var minY = stepPts.first.y, maxY = stepPts.first.y;
    for (final p in stepPts.skip(1)) {
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
            MoveTo(stepPts.first.x - minX, stepPts.first.y - minY),
            for (final p in stepPts.skip(1))
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
      kind: 'stepLine',
      values: vals,
    );
  }

  static VsdxShape radialBarChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.0,
    double height = 2.0,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? defaultValues;
    final unit = _unit(vals);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final cx = w / 2;
    final cy = h / 2;
    final maxR = math.min(w, h) * 0.42;
    final kids = <VsdxShape>[];
    final n = unit.length;
    for (var i = 0; i < n; i++) {
      final outer = maxR * ((i + 1) / n);
      final band = maxR / n * 0.7;
      final innerR = math.max(outer - band, outer * 0.15);
      final inner = innerR / outer;
      final a0 = math.pi / 2;
      final a1 = a0 - unit[i] * math.pi * 1.75;
      kids.add(_wedgeChild(
        id: next(),
        cx: cx,
        cy: cy,
        rx: outer,
        ry: outer,
        a0: a0,
        a1: a1,
        inner: inner,
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
      kind: 'radialBar',
      values: vals,
    );
  }

  static VsdxShape ringProgressChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.0,
    double height = 2.0,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.68];
    final level = vals.first.clamp(0.0, 1.0);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final cx = w / 2;
    final cy = h / 2;
    final r = math.min(w, h) * 0.42;
    const inner = 0.68;
    final kids = <VsdxShape>[];
    // Track as three chrome bands so arcs stay well-formed.
    for (var i = 0; i < 3; i++) {
      final a0 = math.pi / 2 - i * (2 * math.pi / 3);
      final a1 = a0 - (2 * math.pi / 3);
      kids.add(_wedgeChild(
        id: next(),
        cx: cx,
        cy: cy,
        rx: r,
        ry: r,
        a0: a0,
        a1: a1,
        inner: inner,
        fill: const VsdxColor(0xFFE8E8E8),
      ).copyWith(userCells: _chromeMeta));
    }
    final sweep = math.max(level * math.pi * 2, 0.08);
    // Progress may span multiple arcs — split into ≤120° wedges.
    var remaining = sweep;
    var angle = math.pi / 2;
    while (remaining > 1e-6) {
      final step = math.min(remaining, 2 * math.pi / 3);
      kids.add(_wedgeChild(
        id: next(),
        cx: cx,
        cy: cy,
        rx: r,
        ry: r,
        a0: angle,
        a1: angle - step,
        inner: inner,
        fill: seriesColors.first,
      ));
      angle -= step;
      remaining -= step;
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'ringProgress',
      values: vals,
    );
  }

  static VsdxShape histogramChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.2, 0.35, 0.55, 0.8, 0.65, 0.4, 0.25];
    final unit = _unit(vals);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.12;
    final padB = h * 0.12;
    final padT = h * 0.08;
    final plotW = w - padL - w * 0.08;
    final plotH = h - padB - padT;
    final gap = plotW * 0.015;
    final barW = (plotW - gap * (unit.length + 1)) / unit.length;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < unit.length; i++) {
      final bh = plotH * unit[i];
      final cx = padL + gap + barW / 2 + i * (barW + gap);
      kids.add(_rectChild(
        id: next(),
        pinX: cx,
        pinY: padB + bh / 2,
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
      kind: 'histogram',
      values: vals,
    );
  }

  static VsdxShape horizontalLollipopChart({
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
    final slot = (plotH - gap * (unit.length + 1)) / unit.length;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < unit.length; i++) {
      final cy = padB + gap + slot / 2 + i * (slot + gap);
      final tip = padL + plotW * unit[i];
      final stemW = math.max(tip - padL, 0.04);
      kids.add(_rectChild(
        id: next(),
        pinX: padL + stemW / 2,
        pinY: cy,
        width: stemW,
        height: 0.03,
        fill: const VsdxColor(0xFFB0B0B0),
        chrome: true,
      ));
      const r = 0.07;
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: tip,
        pinY: cy,
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
      kind: 'horizontalLollipop',
      values: vals,
    );
  }

  static VsdxShape divergingBarChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[-0.4, 0.55, -0.25, 0.7, 0.35];
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.08;
    final padB = h * 0.12;
    final padR = w * 0.08;
    final plotW = w - padL - padR;
    final plotH = h - padB - h * 0.08;
    final midX = padL + plotW / 2;
    final maxAbs = vals.map((v) => v.abs()).fold(0.0, math.max);
    final scale = maxAbs > 0 ? (plotW / 2) / maxAbs : plotW / 2;
    final gap = plotH * 0.08;
    final barH = (plotH - gap * (vals.length + 1)) / vals.length;
    final kids = <VsdxShape>[
      _axesChild(id: next(), width: w, height: h),
      // Center baseline.
      VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: midX,
        pinY: padB + plotH / 2,
        width: 0.02,
        height: plotH,
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              MoveTo(0.01, 0),
              LineTo(0.01, plotH),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(
          color: VsdxColor(0xFF888888),
          weightInches: 0.01,
        ),
        userCells: _chromeMeta,
      ),
    ];
    for (var i = 0; i < vals.length; i++) {
      final v = vals[i];
      final bw = math.max(v.abs() * scale, 0.04);
      final cy = padB + gap + barH / 2 + i * (barH + gap);
      final cx = v >= 0 ? midX + bw / 2 : midX - bw / 2;
      kids.add(_rectChild(
        id: next(),
        pinX: cx,
        pinY: cy,
        width: bw,
        height: barH * 0.85,
        fill: v >= 0 ? seriesColors[0] : seriesColors[1],
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'divergingBar',
      values: vals,
    );
  }

  static VsdxShape dotPlotChart({
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
    final slot = (plotH - gap * (unit.length + 1)) / unit.length;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < unit.length; i++) {
      final cy = padB + gap + slot / 2 + i * (slot + gap);
      final cx = padL + plotW * unit[i];
      // Guide line (chrome).
      kids.add(_rectChild(
        id: next(),
        pinX: padL + plotW / 2,
        pinY: cy,
        width: plotW,
        height: 0.015,
        fill: const VsdxColor(0xFFD0D0D0),
        chrome: true,
      ));
      const r = 0.08;
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: cx,
        pinY: cy,
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
      kind: 'dotPlot',
      values: vals,
    );
  }

  static VsdxShape compositionBarChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 0.7,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.3, 0.25, 0.2, 0.15, 0.1];
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final sum = vals.fold<double>(0, (a, b) => a + b.abs());
    final total = sum > 0 ? sum : 1.0;
    final barH = h * 0.55;
    final kids = <VsdxShape>[];
    var x0 = 0.0;
    for (var i = 0; i < vals.length; i++) {
      final bw = math.max(w * (vals[i].abs() / total), 0.04);
      kids.add(_rectChild(
        id: next(),
        pinX: x0 + bw / 2,
        pinY: h / 2,
        width: bw,
        height: barH,
        fill: seriesColors[i % seriesColors.length],
      ));
      x0 += bw;
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'compositionBar',
      values: vals,
    );
  }

  static VsdxShape treemapChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.35, 0.25, 0.2, 0.12, 0.08];
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final kids = <VsdxShape>[];
    final absVals = <double>[for (final v in vals) v.abs()];
    final total = absVals.fold<double>(0, (a, b) => a + b);
    final norm = total > 0
        ? absVals
        : List<double>.filled(math.max(vals.length, 1), 1);

    void layout(
      List<int> idxs,
      double x,
      double y,
      double rw,
      double rh,
    ) {
      if (idxs.isEmpty) return;
      if (idxs.length == 1) {
        final i = idxs.first;
        final gap = 0.02;
        kids.add(_rectChild(
          id: next(),
          pinX: x + rw / 2,
          pinY: y + rh / 2,
          width: math.max(rw - gap, 0.04),
          height: math.max(rh - gap, 0.04),
          fill: seriesColors[i % seriesColors.length],
        ));
        return;
      }
      var halfSum = 0.0;
      final target =
          idxs.fold<double>(0, (a, i) => a + norm[i]) / 2;
      var split = 1;
      for (var k = 0; k < idxs.length - 1; k++) {
        halfSum += norm[idxs[k]];
        split = k + 1;
        if (halfSum >= target) break;
      }
      final left = idxs.sublist(0, split);
      final right = idxs.sublist(split);
      final leftSum = left.fold<double>(0, (a, i) => a + norm[i]);
      final allSum = leftSum + right.fold<double>(0, (a, i) => a + norm[i]);
      final frac = allSum > 0 ? leftSum / allSum : 0.5;
      if (rw >= rh) {
        final lw = rw * frac;
        layout(left, x, y, lw, rh);
        layout(right, x + lw, y, rw - lw, rh);
      } else {
        final th = rh * frac;
        layout(left, x, y, rw, th);
        layout(right, x, y + th, rw, rh - th);
      }
    }

    layout(
      <int>[for (var i = 0; i < vals.length; i++) i],
      0.04,
      0.04,
      w - 0.08,
      h - 0.08,
    );
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'treemap',
      values: vals,
    );
  }

  static VsdxShape bulletChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 0.7,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.72];
    final level = vals.first.clamp(0.0, 1.0);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final trackH = h * 0.55;
    final kids = <VsdxShape>[
      // Qualitative bands (chrome).
      _rectChild(
        id: next(),
        pinX: w * 0.3 / 2,
        pinY: h / 2,
        width: w * 0.3,
        height: trackH,
        fill: const VsdxColor(0xFFD9D9D9),
        chrome: true,
      ),
      _rectChild(
        id: next(),
        pinX: w * 0.3 + w * 0.35 / 2,
        pinY: h / 2,
        width: w * 0.35,
        height: trackH,
        fill: const VsdxColor(0xFFBDBDBD),
        chrome: true,
      ),
      _rectChild(
        id: next(),
        pinX: w * 0.65 + w * 0.35 / 2,
        pinY: h / 2,
        width: w * 0.35,
        height: trackH,
        fill: const VsdxColor(0xFF9E9E9E),
        chrome: true,
      ),
      // Value bar.
      _rectChild(
        id: next(),
        pinX: (w * level) / 2,
        pinY: h / 2,
        width: math.max(w * level, 0.04),
        height: trackH * 0.45,
        fill: seriesColors.first,
      ),
      // Target marker (chrome).
      _rectChild(
        id: next(),
        pinX: w * 0.85,
        pinY: h / 2,
        width: 0.035,
        height: trackH * 0.9,
        fill: const VsdxColor(0xFF333333),
        chrome: true,
      ),
    ];
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'bullet',
      values: vals,
    );
  }

  static VsdxShape cylinderChart({
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
    final padT = h * 0.1;
    final plotW = w - padL - w * 0.08;
    final plotH = h - padB - padT;
    final gap = plotW * 0.08;
    final barW = (plotW - gap * (unit.length + 1)) / unit.length;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < unit.length; i++) {
      final bh = plotH * unit[i];
      final cx = padL + gap + barW / 2 + i * (barW + gap);
      final color = seriesColors[i % seriesColors.length];
      final bodyH = math.max(bh - barW * 0.22, 0.04);
      kids.add(_rectChild(
        id: next(),
        pinX: cx,
        pinY: padB + bodyH / 2,
        width: barW * 0.85,
        height: bodyH,
        fill: color,
      ));
      final r = barW * 0.425;
      final topY = padB + bodyH;
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: cx,
        pinY: topY,
        width: r * 2,
        height: r * 0.55,
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
              cx: r,
              cy: r * 0.275,
              aX: r * 2,
              aY: r * 0.275,
              bX: r,
              bY: 0,
            ),
          ]),
        ],
        fill: VsdxFill(foreground: VsdxColor(_darken(color.value))),
        line: _barLine(color),
        userCells: _chromeMeta,
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'cylinder',
      values: vals,
    );
  }

  static VsdxShape coneChart({
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
      final bh = math.max(plotH * unit[i], 0.06);
      final cx = padL + gap + barW / 2 + i * (barW + gap);
      final color = seriesColors[i % seriesColors.length];
      final half = barW * 0.42;
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: cx,
        pinY: padB + bh / 2,
        width: half * 2,
        height: bh,
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(0, 0),
            LineTo(half * 2, 0),
            LineTo(half, bh),
            const LineTo(0, 0),
          ]),
        ],
        fill: VsdxFill(foreground: color),
        line: _barLine(color),
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'cone',
      values: vals,
    );
  }

  static VsdxShape stepAreaChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.3, 0.55, 0.45, 0.8, 0.6];
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
    final stepPts = <({double x, double y})>[pts.first];
    for (var i = 1; i < pts.length; i++) {
      stepPts.add((x: pts[i].x, y: pts[i - 1].y));
      stepPts.add(pts[i]);
    }
    var minX = stepPts.first.x, maxX = stepPts.first.x;
    var minY = padB, maxY = stepPts.first.y;
    for (final p in stepPts) {
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
          MoveTo(stepPts.first.x - minX, padB - minY),
          LineTo(stepPts.first.x - minX, stepPts.first.y - minY),
          for (final p in stepPts.skip(1)) LineTo(p.x - minX, p.y - minY),
          LineTo(stepPts.last.x - minX, padB - minY),
          LineTo(stepPts.first.x - minX, padB - minY),
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
      kind: 'stepArea',
      values: vals,
    );
  }

  static VsdxShape percentColumnChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 1.2,
    double height = 2.2,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.3, 0.25, 0.2, 0.15, 0.1];
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final sum = vals.fold<double>(0, (a, b) => a + b.abs());
    final total = sum > 0 ? sum : 1.0;
    final colW = w * 0.55;
    final kids = <VsdxShape>[];
    var y0 = 0.0;
    for (var i = 0; i < vals.length; i++) {
      final bh = math.max(h * (vals[i].abs() / total), 0.04);
      kids.add(_rectChild(
        id: next(),
        pinX: w / 2,
        pinY: y0 + bh / 2,
        width: colW,
        height: bh,
        fill: seriesColors[i % seriesColors.length],
      ));
      y0 += bh;
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'percentColumn',
      values: vals,
    );
  }

  static VsdxShape packedBubbleChart({
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
    final kids = <VsdxShape>[];
    // Simple row-pack: place circles left-to-right, wrap when needed.
    var x = 0.12;
    var y = h - 0.12;
    var rowH = 0.0;
    for (var i = 0; i < unit.length; i++) {
      final r = 0.08 + 0.16 * unit[i];
      if (x + r * 2 > w - 0.08) {
        x = 0.12;
        y -= rowH + 0.06;
        rowH = 0;
      }
      if (y - r < 0.08) {
        y = r + 0.08;
      }
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: x + r,
        pinY: y - r,
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
          foregroundTransparency: 0.15,
        ),
        line: _barLine(seriesColors[i % seriesColors.length]),
      ));
      x += r * 2 + 0.04;
      rowH = math.max(rowH, r * 2);
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'packedBubble',
      values: vals,
    );
  }

  static VsdxShape thermometerChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 0.7,
    double height = 2.2,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.68];
    final level = vals.first.clamp(0.0, 1.0);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final tubeW = w * 0.28;
    final bulbR = w * 0.32;
    final tubeTop = h * 0.88;
    final tubeBottom = bulbR * 1.6;
    final tubeH = tubeTop - tubeBottom;
    final kids = <VsdxShape>[
      // Tube track.
      _rectChild(
        id: next(),
        pinX: w / 2,
        pinY: tubeBottom + tubeH / 2,
        width: tubeW,
        height: tubeH,
        fill: const VsdxColor(0xFFE8E8E8),
        chrome: true,
      ),
      // Bulb chrome.
      VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: w / 2,
        pinY: bulbR,
        width: bulbR * 2,
        height: bulbR * 2,
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
              cx: bulbR,
              cy: bulbR,
              aX: bulbR * 2,
              aY: bulbR,
              bX: bulbR,
              bY: 0,
            ),
          ]),
        ],
        fill: const VsdxFill(foreground: VsdxColor(0xFFE8E8E8)),
        line: const VsdxLine(color: VsdxColor(0xFFB0B0B0), weightInches: 0.008),
        userCells: _chromeMeta,
      ),
    ];
    final fillH = math.max(tubeH * level, 0.04);
    kids.add(_rectChild(
      id: next(),
      pinX: w / 2,
      pinY: tubeBottom + fillH / 2,
      width: tubeW * 0.7,
      height: fillH,
      fill: seriesColors[1],
    ));
    kids.add(VsdxShape(
      id: next(),
      name: _sheetName(id),
      pinX: w / 2,
      pinY: bulbR,
      width: bulbR * 1.5,
      height: bulbR * 1.5,
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          EllipseCmd(
            cx: bulbR * 0.75,
            cy: bulbR * 0.75,
            aX: bulbR * 1.5,
            aY: bulbR * 0.75,
            bX: bulbR * 0.75,
            bY: 0,
          ),
        ]),
      ],
      fill: VsdxFill(foreground: seriesColors[1]),
      line: _barLine(seriesColors[1]),
    ));
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'thermometer',
      values: vals,
    );
  }

  static VsdxShape waffleChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.0,
    double height = 2.0,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.68];
    final level = vals.first.clamp(0.0, 1.0);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    const cols = 10;
    const rows = 10;
    final filled = (level * cols * rows).round().clamp(0, cols * rows);
    final gap = 0.03;
    final cellW = (w - gap * (cols + 1)) / cols;
    final cellH = (h - gap * (rows + 1)) / rows;
    final kids = <VsdxShape>[];
    var n = 0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final cx = gap + cellW / 2 + c * (cellW + gap);
        final cy = h - (gap + cellH / 2 + r * (cellH + gap));
        final on = n < filled;
        n++;
        kids.add(_rectChild(
          id: next(),
          pinX: cx,
          pinY: cy,
          width: cellW,
          height: cellH,
          fill: on ? seriesColors.first : const VsdxColor(0xFFE8E8E8),
          chrome: !on,
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
      kind: 'waffle',
      values: vals,
    );
  }
}
