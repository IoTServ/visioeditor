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
  /// Kind-specific params (e.g. heatmap `3x4`, calendar `weeks=4`).
  static const String userExtras = 'visioeditor.ChartExtras';

  static const int maxSeriesItems = 12;

  /// Kinds that use a dedicated right-panel editor (not the shared series UI).
  static const Set<String> customEditorKinds = <String>{
    'candlestick',
    'heatmap',
    'gantt',
    'boxplot',
    'slope',
    'calendarHeat',
    'rangeBar',
    'dumbbell',
    'quadrant',
    'timeline',
    'nestedDonut',
    'kpiTarget',
    'dataTable',
    'venn',
    'scorecard',
    'radialMulti',
    'spanColumn',
    'ranking',
    'processSteps',
    'arcGauge',
    'bulletGroup',
    'likert',
    'heatStrip',
    'dualCompare',
    'statusBoard',
    'progressList',
    'milestone',
    'balanceBar',
    'meterCluster',
    'priorityMatrix',
    'cycleFlow',
    'checkboxList',
    'gapAnalysis',
    'stageFunnel',
    'rhythmBars',
    'voteStack',
    'trafficRow',
    'starRating',
    'compareCards',
    'pipeline',
    'winLossStrip',
    'quotaBoard',
    'tickLadder',
  };

  static bool isCustomEditorKind(String kind) =>
      customEditorKinds.contains(kind);

  /// Max packed values for custom kinds (shared series cap stays [maxSeriesItems]).
  static int maxValuesForKind(String kind) {
    switch (kind) {
      case 'heatmap':
      case 'calendarHeat':
        return 36;
      case 'candlestick':
        return 16; // 4 candles × OHLC
      case 'gantt':
        return 16; // 8 tasks × start/duration
      case 'boxplot':
        return 15; // 3 boxes × 5 stats
      case 'slope':
      case 'rangeBar':
      case 'dumbbell':
      case 'quadrant':
        return 12; // 6 pairs
      case 'timeline':
        return 10;
      case 'nestedDonut':
        return 12;
      case 'kpiTarget':
        return 2;
      case 'dataTable':
        return 48; // up to 8×6 cells
      case 'venn':
        return 3;
      case 'scorecard':
        return 8;
      case 'radialMulti':
        return 5;
      case 'spanColumn':
        return 12;
      case 'ranking':
        return 10;
      case 'processSteps':
        return 8;
      case 'arcGauge':
        return 2;
      case 'bulletGroup':
        return 12;
      case 'likert':
        return 5;
      case 'heatStrip':
        return 16;
      case 'dualCompare':
        return 12;
      case 'statusBoard':
        return 8;
      case 'progressList':
      case 'milestone':
      case 'meterCluster':
      case 'cycleFlow':
      case 'checkboxList':
      case 'stageFunnel':
      case 'rhythmBars':
      case 'trafficRow':
      case 'starRating':
      case 'pipeline':
      case 'winLossStrip':
      case 'tickLadder':
        return 8;
      case 'balanceBar':
      case 'gapAnalysis':
      case 'quotaBoard':
        return 12;
      case 'priorityMatrix':
        return 4;
      case 'voteStack':
        return 3;
      case 'compareCards':
        return 2;
      default:
        return maxSeriesItems;
    }
  }

  /// Logical series count for labels/colours on custom kinds.
  static int logicalSeriesCount(
    String kind,
    List<double> values, [
    String? extras,
  ]) {
    switch (kind) {
      case 'candlestick':
        return math.max(1, values.length ~/ 4);
      case 'gantt':
      case 'slope':
      case 'rangeBar':
      case 'dumbbell':
      case 'quadrant':
        return math.max(1, values.length ~/ 2);
      case 'boxplot':
        return math.max(1, values.length ~/ 5);
      case 'heatmap':
        final g = parseHeatmapGrid(extras);
        return g.$1 * g.$2;
      case 'calendarHeat':
        return calendarCellCount(extras);
      case 'timeline':
        return math.max(1, values.length);
      case 'nestedDonut':
        return math.max(1, values.length);
      case 'kpiTarget':
        return 1;
      case 'dataTable':
        final g = parseTableGrid(extras);
        return g.$1 * g.$2;
      case 'venn':
        return 3;
      case 'scorecard':
      case 'radialMulti':
      case 'ranking':
      case 'processSteps':
      case 'likert':
      case 'heatStrip':
      case 'statusBoard':
      case 'progressList':
      case 'milestone':
      case 'meterCluster':
      case 'cycleFlow':
      case 'priorityMatrix':
      case 'checkboxList':
      case 'stageFunnel':
      case 'rhythmBars':
      case 'trafficRow':
      case 'voteStack':
      case 'starRating':
      case 'compareCards':
      case 'pipeline':
      case 'winLossStrip':
      case 'tickLadder':
        return math.max(1, values.length);
      case 'spanColumn':
      case 'bulletGroup':
      case 'dualCompare':
      case 'balanceBar':
      case 'gapAnalysis':
      case 'quotaBoard':
        return math.max(1, values.length ~/ 2);
      case 'arcGauge':
        return 1;
      default:
        return values.length;
    }
  }

  static (int rows, int cols) parseHeatmapGrid(String? extras) {
    final m = RegExp(r'(\d+)\s*[x×]\s*(\d+)').firstMatch(extras ?? '');
    if (m != null) {
      final rows = int.parse(m.group(1)!).clamp(1, 6);
      final cols = int.parse(m.group(2)!).clamp(1, 6);
      return (rows, cols);
    }
    return (3, 4);
  }

  static String formatHeatmapGrid(int rows, int cols) =>
      '${rows.clamp(1, 6)}x${cols.clamp(1, 6)}';

  static int parseCalendarWeeks(String? extras) {
    final m = RegExp(r'weeks\s*=\s*(\d+)').firstMatch(extras ?? '');
    if (m != null) return int.parse(m.group(1)!).clamp(2, 6);
    return 4;
  }

  static String formatCalendarWeeks(int weeks) => 'weeks=${weeks.clamp(2, 6)}';

  static int calendarCellCount(String? extras) =>
      parseCalendarWeeks(extras) * 7;

  static int parseNestedInner(String? extras, int total) {
    final m = RegExp(r'inner\s*=\s*(\d+)').firstMatch(extras ?? '');
    if (m != null) {
      return int.parse(m.group(1)!).clamp(1, math.max(1, total - 1));
    }
    return math.max(1, total ~/ 2);
  }

  static String formatNestedInner(int inner) => 'inner=${inner.clamp(1, 8)}';

  static (int rows, int cols) parseTableGrid(String? extras) {
    final m = RegExp(r'(\d+)\s*[x×]\s*(\d+)').firstMatch(extras ?? '');
    if (m != null) {
      return (
        int.parse(m.group(1)!).clamp(1, 8),
        int.parse(m.group(2)!).clamp(1, 8),
      );
    }
    return (4, 3);
  }

  static bool parseTableFlag(String? extras, String key, {bool defaultValue = true}) {
    final m = RegExp(
      '${RegExp.escape(key)}\\s*=\\s*(1|0|true|false)',
      caseSensitive: false,
    ).firstMatch(extras ?? '');
    if (m == null) return defaultValue;
    final v = m.group(1)!.toLowerCase();
    return v == '1' || v == 'true';
  }

  static String formatTableExtras({
    required int rows,
    required int cols,
    bool header = true,
    bool borders = true,
    bool zebra = false,
  }) =>
      '${rows.clamp(1, 8)}x${cols.clamp(1, 8)};'
      'header=${header ? 1 : 0};'
      'borders=${borders ? 1 : 0};'
      'zebra=${zebra ? 1 : 0}';

  static int parseScorecardCols(String? extras) {
    final m = RegExp(r'cols\s*=\s*(\d+)').firstMatch(extras ?? '');
    if (m != null) return int.parse(m.group(1)!).clamp(1, 4);
    return 2;
  }

  static String formatScorecardCols(int cols) => 'cols=${cols.clamp(1, 4)}';

  static int parseHeatStripCells(String? extras) {
    final m = RegExp(r'cells\s*=\s*(\d+)').firstMatch(extras ?? '');
    if (m != null) return int.parse(m.group(1)!).clamp(3, 16);
    return 8;
  }

  static String formatHeatStripCells(int cells) =>
      'cells=${cells.clamp(3, 16)}';

  /// Kind picker groups for the editor (group title → kind keys).
  static const List<(String, List<String>)> kindGroups =
      <(String, List<String>)>[
    ('Bars & columns', <String>[
      'column',
      'bar',
      'histogram',
      'cylinder',
      'horizontalCylinder',
      'cone',
      'variableColumn',
      'pillBar',
      'arrowBar',
      'sparkColumn',
      'sparkWinLoss',
      'triangleBar',
      'mirrorColumn',
      'tornado',
      'pareto',
      'stackedColumn',
      'stackedBar',
      'clusteredColumn',
      'clusteredBar',
      'lollipop',
      'horizontalLollipop',
      'diamondLollipop',
      'divergingBar',
      'dotPlot',
    ]),
    ('Pies', <String>['pie', 'donut', 'semiDonut', 'rose', 'nightingale']),
    ('Lines & areas', <String>[
      'line',
      'stepLine',
      'area',
      'stepArea',
      'sparkLine',
      'sparkArea',
      'radar',
      'polarLine',
    ]),
    ('Process', <String>[
      'funnel',
      'pyramid',
      'chevron',
      'waterfall',
      'radialBar',
      'radialColumn',
      'compositionBar',
      'percentColumn',
      'treemap',
      'packedBubble',
    ]),
    ('Meters', <String>[
      'gauge',
      'progress',
      'ringProgress',
      'semiProgress',
      'stepProgress',
      'bullet',
      'thermometer',
      'waffle',
      'battery',
      'trafficLight',
    ]),
    ('Other', <String>['bubble']),
    // Specialty kinds have dedicated editors; listed for display names / insert.
    ('Specialty', <String>[
      'candlestick',
      'heatmap',
      'gantt',
      'boxplot',
      'slope',
      'calendarHeat',
      'rangeBar',
      'dumbbell',
      'quadrant',
      'timeline',
      'nestedDonut',
      'kpiTarget',
      'dataTable',
      'venn',
      'scorecard',
      'radialMulti',
      'spanColumn',
      'ranking',
      'processSteps',
      'arcGauge',
      'bulletGroup',
      'likert',
      'heatStrip',
      'dualCompare',
      'statusBoard',
      'progressList',
      'milestone',
      'balanceBar',
      'meterCluster',
      'priorityMatrix',
      'cycleFlow',
      'checkboxList',
      'gapAnalysis',
      'stageFunnel',
      'rhythmBars',
      'voteStack',
      'trafficRow',
      'starRating',
      'compareCards',
      'pipeline',
      'winLossStrip',
      'quotaBoard',
      'tickLadder',
    ]),
  ];

  /// Kind groups shown in the shared series editor (excludes specialty).
  static List<(String, List<String>)> get sharedKindGroups => <(String, List<String>)>[
        for (final g in kindGroups)
          if (g.$1 != 'Specialty') g,
      ];

  /// Chart kinds exposed in the editor type picker (value → stencil English name).
  static const Map<String, String> kindDisplayNames = <String, String>{
    'column': 'Column Chart',
    'bar': 'Bar Chart',
    'histogram': 'Histogram',
    'cylinder': 'Cylinder Chart',
    'horizontalCylinder': 'Horizontal Cylinder',
    'cone': 'Cone Chart',
    'variableColumn': 'Variable Column',
    'pillBar': 'Pill Bar',
    'arrowBar': 'Arrow Bar',
    'sparkColumn': 'Spark Column',
    'sparkWinLoss': 'Spark Win/Loss',
    'triangleBar': 'Triangle Bar',
    'mirrorColumn': 'Mirror Column',
    'tornado': 'Tornado Chart',
    'pareto': 'Pareto Chart',
    'stackedColumn': 'Stacked Column',
    'stackedBar': 'Stacked Bar',
    'clusteredColumn': 'Clustered Column',
    'clusteredBar': 'Clustered Bar',
    'lollipop': 'Lollipop Chart',
    'horizontalLollipop': 'Horizontal Lollipop',
    'diamondLollipop': 'Diamond Lollipop',
    'divergingBar': 'Diverging Bar',
    'dotPlot': 'Dot Plot',
    'pie': 'Pie Chart',
    'donut': 'Donut Chart',
    'semiDonut': 'Semi Donut',
    'rose': 'Rose Chart',
    'nightingale': 'Nightingale Chart',
    'line': 'Line Chart',
    'stepLine': 'Step Line',
    'area': 'Area Chart',
    'stepArea': 'Step Area',
    'sparkLine': 'Spark Line',
    'sparkArea': 'Spark Area',
    'funnel': 'Funnel',
    'pyramid': 'Pyramid Chart',
    'chevron': 'Chevron Process',
    'radar': 'Radar Chart',
    'polarLine': 'Polar Line',
    'radialBar': 'Radial Bar',
    'radialColumn': 'Radial Column',
    'compositionBar': 'Composition Bar',
    'percentColumn': 'Percent Column',
    'treemap': 'Treemap',
    'packedBubble': 'Packed Bubble',
    'gauge': 'Gauge',
    'progress': 'Progress',
    'ringProgress': 'Ring Progress',
    'semiProgress': 'Semi Progress',
    'stepProgress': 'Step Progress',
    'bullet': 'Bullet Chart',
    'thermometer': 'Thermometer',
    'waffle': 'Waffle Chart',
    'battery': 'Battery Chart',
    'trafficLight': 'Traffic Light',
    'waterfall': 'Waterfall',
    'bubble': 'Bubble Chart',
    'candlestick': 'Candlestick Chart',
    'heatmap': 'Heatmap',
    'gantt': 'Gantt Chart',
    'boxplot': 'Box Plot',
    'slope': 'Slope Chart',
    'calendarHeat': 'Calendar Heatmap',
    'rangeBar': 'Range Bar',
    'dumbbell': 'Dumbbell Chart',
    'quadrant': 'Quadrant Chart',
    'timeline': 'Timeline Chart',
    'nestedDonut': 'Nested Donut',
    'kpiTarget': 'KPI Target',
    'dataTable': 'Data Table',
    'venn': 'Venn Diagram',
    'scorecard': 'Scorecard',
    'radialMulti': 'Radial Multi',
    'spanColumn': 'Span Column',
    'ranking': 'Ranking Chart',
    'processSteps': 'Process Steps',
    'arcGauge': 'Arc Gauge',
    'bulletGroup': 'Bullet Group',
    'likert': 'Likert Scale',
    'heatStrip': 'Heat Strip',
    'dualCompare': 'Dual Compare',
    'statusBoard': 'Status Board',
    'progressList': 'Progress List',
    'milestone': 'Milestone Track',
    'balanceBar': 'Balance Bar',
    'meterCluster': 'Meter Cluster',
    'priorityMatrix': 'Priority Matrix',
    'cycleFlow': 'Cycle Flow',
    'checkboxList': 'Checklist',
    'gapAnalysis': 'Gap Analysis',
    'stageFunnel': 'Stage Funnel',
    'rhythmBars': 'Rhythm Bars',
    'voteStack': 'Vote Stack',
    'trafficRow': 'Traffic Row',
    'starRating': 'Star Rating',
    'compareCards': 'Compare Cards',
    'pipeline': 'Pipeline',
    'winLossStrip': 'Win/Loss Strip',
    'quotaBoard': 'Quota Board',
    'tickLadder': 'Tick Ladder',
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

  static String? chartExtras(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userExtras) {
        final v = (c.value ?? '').trim();
        if (v.isNotEmpty) return v;
      }
    }
    return null;
  }

  static VsdxShape withExtras(VsdxShape chart, String? extras) {
    final kept = <VsdxUserCell>[
      for (final c in chart.userCells)
        if (c.name != userExtras) c,
    ];
    if (extras != null && extras.trim().isNotEmpty) {
      kept.add(VsdxUserCell(name: userExtras, value: extras.trim()));
    }
    return chart.copyWith(userCells: kept);
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

  /// Persist chart numbers with enough precision for rebuild/side-panel fidelity.
  static String _fmtNum(double v) {
    if (v.isNaN || v.isInfinite) return '0';
    if (v == v.roundToDouble()) return v.toInt().toString();
    var s = v.toStringAsFixed(6);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    }
    return s;
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
      kind == 'semiProgress' ||
      kind == 'stepProgress' ||
      kind == 'bullet' ||
      kind == 'thermometer' ||
      kind == 'waffle' ||
      kind == 'battery' ||
      kind == 'trafficLight';

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
    String? extras,
  }) =>
      <VsdxUserCell>[
        const VsdxUserCell(name: userChart, value: '1'),
        VsdxUserCell(name: userKind, value: kind),
        VsdxUserCell(name: userValues, value: formatValues(values)),
        if (colors != null && colors.isNotEmpty)
          VsdxUserCell(name: userColors, value: formatColors(colors)),
        if (labels != null && labels.isNotEmpty)
          VsdxUserCell(name: userLabels, value: formatLabels(labels)),
        if (extras != null && extras.trim().isNotEmpty)
          VsdxUserCell(name: userExtras, value: extras.trim()),
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
    userExtras,
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
    } else if (kind == 'heatmap' ||
        kind == 'calendarHeat' ||
        kind == 'dataTable' ||
        kind == 'heatStrip') {
      // Table / heat colours are applied at build time.
      kids = chart.children;
    } else if (kind == 'ringProgress' ||
        kind == 'waffle' ||
        kind == 'thermometer' ||
        kind == 'semiProgress' ||
        kind == 'stepProgress') {
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
          extras: chartExtras(chart),
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
    if (isSingleValueKind(kind) ||
        labels.isEmpty ||
        kind == 'dataTable' ||
        kind == 'heatmap' ||
        kind == 'calendarHeat' ||
        kind == 'scorecard' ||
        kind == 'processSteps' ||
        kind == 'venn' ||
        kind == 'statusBoard' ||
        kind == 'likert' ||
        kind == 'heatStrip' ||
        kind == 'progressList' ||
        kind == 'milestone' ||
        kind == 'meterCluster' ||
        kind == 'priorityMatrix' ||
        kind == 'cycleFlow' ||
        kind == 'checkboxList' ||
        kind == 'stageFunnel' ||
        kind == 'voteStack' ||
        kind == 'trafficRow' ||
        kind == 'starRating' ||
        kind == 'compareCards' ||
        kind == 'pipeline' ||
        kind == 'winLossStrip' ||
        kind == 'quotaBoard' ||
        kind == 'tickLadder') {
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
    String? extras,
    required int Function() allocId,
  }) {
    final prevKind = chartKind(chart) ?? 'column';
    final k = kind ?? prevKind;
    final prevVals = chartValues(chart);
    final prevCols = chartColors(chart);
    final extrasOut = extras ?? chartExtras(chart);
    final prevLabs = chartLabels(
      chart,
      isCustomEditorKind(prevKind)
          ? logicalSeriesCount(prevKind, prevVals, chartExtras(chart))
          : prevVals.length,
    );

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
    if (vals.isEmpty) {
      vals = isCustomEditorKind(k)
          ? List<double>.of(_defaultValuesForKind(k, extrasOut))
          : List<double>.of(defaultValues);
    }
    final maxV = maxValuesForKind(k);
    if (vals.length > maxV) {
      vals = vals.sublist(0, maxV);
    }
    if (k == 'dataTable') {
      final g = parseTableGrid(extrasOut);
      final need = g.$1 * g.$2;
      if (vals.length < need) {
        vals = <double>[
          ...vals,
          for (var i = vals.length; i < need; i++) 1.0,
        ];
      } else if (vals.length > need) {
        vals = vals.sublist(0, need);
      }
      // Style colours: header / body / zebra (not one-per-cell).
      if (cols.length > 3) cols = cols.sublist(0, 3);
      cols = padColors(
        cols.isEmpty
            ? const <VsdxColor>[
                VsdxColor(0xFF5B9BD5),
                VsdxColor(0xFFFFFFFF),
                VsdxColor(0xFFF0F4F8),
              ]
            : cols,
        3,
      );
      labs = padLabels(labs, need);
    } else {
      final labelCount = isCustomEditorKind(k)
          ? logicalSeriesCount(k, vals, extrasOut)
          : vals.length;
      cols = padColors(cols, labelCount);
      labs = padLabels(labs, labelCount);
    }

    final built = buildKind(
      k,
      id: chart.id,
      pinX: chart.pinX,
      pinY: chart.pinY,
      width: chart.width,
      height: chart.height,
      values: vals,
      labels: labs,
      colors: cols,
      extras: extrasOut,
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
    final withEx = extrasOut == null ? colored : withExtras(colored, extrasOut);
    return withCategoryLabels(withEx, labs, cols, allocId: allocId);
  }

  static List<double> _defaultValuesForKind(String kind, String? extras) {
    switch (kind) {
      case 'candlestick':
        return const <double>[
          0.4, 0.7, 0.3, 0.55,
          0.55, 0.8, 0.45, 0.65,
          0.5, 0.75, 0.35, 0.4,
        ];
      case 'heatmap':
        final g = parseHeatmapGrid(extras);
        return <double>[
          for (var i = 0; i < g.$1 * g.$2; i++) 0.2 + (i % 5) * 0.15,
        ];
      case 'gantt':
        return const <double>[0.05, 0.35, 0.25, 0.3, 0.45, 0.4, 0.7, 0.25];
      case 'boxplot':
        return const <double>[0.15, 0.35, 0.5, 0.65, 0.85];
      case 'slope':
        return const <double>[0.3, 0.7, 0.6, 0.4, 0.45, 0.8];
      case 'calendarHeat':
        final n = calendarCellCount(extras);
        return <double>[
          for (var i = 0; i < n; i++) ((i * 37) % 100) / 100.0,
        ];
      case 'rangeBar':
        return const <double>[0.1, 0.55, 0.25, 0.7, 0.15, 0.45, 0.4, 0.85];
      case 'dumbbell':
        return const <double>[0.2, 0.75, 0.35, 0.55, 0.15, 0.9];
      case 'quadrant':
        return const <double>[0.25, 0.7, 0.7, 0.75, 0.3, 0.3, 0.8, 0.35];
      case 'timeline':
        return const <double>[0.1, 0.35, 0.55, 0.8];
      case 'nestedDonut':
        return const <double>[0.3, 0.25, 0.2, 0.25, 0.4, 0.35, 0.25];
      case 'kpiTarget':
        return const <double>[0.72, 0.9];
      case 'dataTable':
        final g = parseTableGrid(extras);
        return List<double>.filled(g.$1 * g.$2, 1);
      case 'venn':
        return const <double>[0.45, 0.4, 0.2];
      case 'scorecard':
        return const <double>[0.82, 0.64, 0.91, 0.55];
      case 'radialMulti':
        return const <double>[0.85, 0.65, 0.45];
      case 'spanColumn':
        return const <double>[0.15, 0.55, 0.3, 0.75, 0.2, 0.5, 0.4, 0.9];
      case 'ranking':
        return const <double>[0.9, 0.75, 0.6, 0.45, 0.3];
      case 'processSteps':
        return const <double>[1, 1, 0.5, 0, 0];
      case 'arcGauge':
        return const <double>[0.68, 0.85];
      case 'bulletGroup':
        return const <double>[0.7, 0.9, 0.55, 0.8, 0.4, 0.7];
      case 'likert':
        return const <double>[0.1, 0.15, 0.25, 0.3, 0.2];
      case 'heatStrip':
        final n = parseHeatStripCells(extras);
        return <double>[
          for (var i = 0; i < n; i++) ((i * 37) % 100) / 100.0,
        ];
      case 'dualCompare':
        return const <double>[0.6, 0.45, 0.75, 0.55, 0.4, 0.7];
      case 'statusBoard':
        return const <double>[1, 0.5, 0, 1];
      case 'progressList':
        return const <double>[0.85, 0.6, 0.4, 0.25];
      case 'milestone':
        return const <double>[0.1, 0.35, 0.65, 0.9];
      case 'balanceBar':
        return const <double>[0.55, 0.45, 0.7, 0.35, 0.4, 0.6];
      case 'meterCluster':
        return const <double>[0.8, 0.55, 0.35];
      case 'priorityMatrix':
        return const <double>[0.8, 0.55, 0.4, 0.25];
      case 'cycleFlow':
        return const <double>[1, 1, 1, 1];
      case 'checkboxList':
        return const <double>[1, 1, 0, 0];
      case 'gapAnalysis':
        return const <double>[0.55, 0.85, 0.4, 0.7, 0.65, 0.9];
      case 'stageFunnel':
        return const <double>[1.0, 0.75, 0.5, 0.3];
      case 'rhythmBars':
        return const <double>[0.4, 0.7, 0.55, 0.9, 0.35, 0.65];
      case 'voteStack':
        return const <double>[0.45, 0.35, 0.2];
      case 'trafficRow':
        return const <double>[1, 0.5, 0, 1];
      case 'starRating':
        return const <double>[0.9, 0.7, 0.5];
      case 'compareCards':
        return const <double>[0.72, 0.58];
      case 'pipeline':
        return const <double>[1.0, 0.7, 0.45, 0.25];
      case 'winLossStrip':
        return const <double>[1, 1, 0, 1, 0, 1];
      case 'quotaBoard':
        return const <double>[0.65, 1.0, 0.8, 1.0, 0.45, 1.0];
      case 'tickLadder':
        return const <double>[0.8, 0.5, 0.3];
      default:
        return List<double>.of(defaultValues);
    }
  }

  static VsdxShape buildKind(
    String kind, {
    required int id,
    required double pinX,
    required double pinY,
    double? width,
    double? height,
    List<double>? values,
    List<String>? labels,
    List<VsdxColor>? colors,
    String? extras,
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
      case 'diamondLollipop':
        return diamondLollipopChart(
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
      case 'horizontalCylinder':
        return horizontalCylinderChart(
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
      case 'variableColumn':
        return variableColumnChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'pillBar':
        return pillBarChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'arrowBar':
        return arrowBarChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'sparkColumn':
        return sparkColumnChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.0,
            height: height ?? 0.9,
            values: values,
            allocId: allocId);
      case 'sparkWinLoss':
        return sparkWinLossChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.0,
            height: height ?? 0.7,
            values: values,
            allocId: allocId);
      case 'triangleBar':
        return triangleBarChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'mirrorColumn':
        return mirrorColumnChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'tornado':
        return tornadoChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'pareto':
        return paretoChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
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
      case 'battery':
        return batteryChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.2,
            height: height ?? 0.9,
            values: values,
            allocId: allocId);
      case 'trafficLight':
        return trafficLightChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 0.8,
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
      case 'nightingale':
        return nightingaleChart(
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
      case 'sparkLine':
        return sparkLineChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.0,
            height: height ?? 0.7,
            values: values,
            allocId: allocId);
      case 'sparkArea':
        return sparkAreaChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.0,
            height: height ?? 0.7,
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
      case 'chevron':
        return chevronChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.8,
            height: height ?? 0.9,
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
      case 'polarLine':
        return polarLineChart(
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
      case 'radialColumn':
        return radialColumnChart(
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
      case 'semiProgress':
        return semiProgressChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.2,
            height: height ?? 1.3,
            values: values,
            allocId: allocId);
      case 'stepProgress':
        return stepProgressChart(
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
      case 'candlestick':
        return candlestickChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'heatmap':
        return heatmapChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            extras: extras,
            allocId: allocId);
      case 'gantt':
        return ganttChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.8,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'boxplot':
        return boxplotChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'slope':
        return slopeChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'calendarHeat':
        return calendarHeatChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 1.6,
            values: values,
            extras: extras,
            allocId: allocId);
      case 'rangeBar':
        return rangeBarChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'dumbbell':
        return dumbbellChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'quadrant':
        return quadrantChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.2,
            height: height ?? 2.0,
            values: values,
            allocId: allocId);
      case 'timeline':
        return timelineChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.8,
            height: height ?? 1.2,
            values: values,
            allocId: allocId);
      case 'nestedDonut':
        return nestedDonutChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.0,
            height: height ?? 2.0,
            values: values,
            extras: extras,
            allocId: allocId);
      case 'kpiTarget':
        return kpiTargetChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.2,
            height: height ?? 1.2,
            values: values,
            allocId: allocId);
      case 'dataTable':
        return dataTableChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 3.2,
            height: height ?? 2.0,
            values: values,
            labels: labels,
            colors: colors,
            extras: extras,
            allocId: allocId);
      case 'venn':
        return vennChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.8,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'scorecard':
        return scorecardChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 3.0,
            height: height ?? 1.2,
            values: values,
            labels: labels,
            extras: extras,
            allocId: allocId);
      case 'radialMulti':
        return radialMultiChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.0,
            height: height ?? 2.0,
            values: values,
            allocId: allocId);
      case 'spanColumn':
        return spanColumnChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 1.8,
            values: values,
            allocId: allocId);
      case 'ranking':
        return rankingChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 1.8,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'processSteps':
        return processStepsChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 3.2,
            height: height ?? 1.0,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'arcGauge':
        return arcGaugeChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.2,
            height: height ?? 1.4,
            values: values,
            allocId: allocId);
      case 'bulletGroup':
        return bulletGroupChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 1.8,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'likert':
        return likertChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.8,
            height: height ?? 0.9,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'heatStrip':
        return heatStripChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.8,
            height: height ?? 0.7,
            values: values,
            extras: extras,
            allocId: allocId);
      case 'dualCompare':
        return dualCompareChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 1.8,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'statusBoard':
        return statusBoardChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.8,
            height: height ?? 1.4,
            values: values,
            labels: labels,
            extras: extras,
            allocId: allocId);
      case 'progressList':
        return progressListChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 1.8,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'milestone':
        return milestoneChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.8,
            height: height ?? 1.3,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'balanceBar':
        return balanceBarChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 1.8,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'meterCluster':
        return meterClusterChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.8,
            height: height ?? 1.2,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'priorityMatrix':
        return priorityMatrixChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 2.0,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'cycleFlow':
        return cycleFlowChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.2,
            height: height ?? 2.2,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'checkboxList':
        return checkboxListChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.4,
            height: height ?? 1.6,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'gapAnalysis':
        return gapAnalysisChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 1.8,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'stageFunnel':
        return stageFunnelChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.8,
            height: height ?? 1.6,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'rhythmBars':
        return rhythmBarsChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 1.4,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'voteStack':
        return voteStackChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 0.9,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'trafficRow':
        return trafficRowChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.8,
            height: height ?? 0.9,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'starRating':
        return starRatingChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 1.5,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'compareCards':
        return compareCardsChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.8,
            height: height ?? 1.4,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'pipeline':
        return pipelineChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 3.2,
            height: height ?? 1.1,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'winLossStrip':
        return winLossStripChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.8,
            height: height ?? 0.8,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'quotaBoard':
        return quotaBoardChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 1.8,
            values: values,
            labels: labels,
            allocId: allocId);
      case 'tickLadder':
        return tickLadderChart(
            id: id,
            pinX: pinX,
            pinY: pinY,
            width: width ?? 2.6,
            height: height ?? 1.5,
            values: values,
            labels: labels,
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
    String? extras,
    List<String>? labels,
    List<VsdxColor>? colors,
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
      userCells: _meta(
        kind,
        values,
        extras: extras,
        labels: labels,
        colors: colors,
      ),
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

  static VsdxShape sparkColumnChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.0,
    double height = 0.9,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.3, 0.55, 0.4, 0.8, 0.65, 0.5, 0.7];
    final unit = _unit(vals);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final gap = w * 0.04;
    final barW = (w - gap * (unit.length + 1)) / unit.length;
    final kids = <VsdxShape>[];
    for (var i = 0; i < unit.length; i++) {
      final bh = math.max(h * unit[i], 0.04);
      kids.add(_rectChild(
        id: next(),
        pinX: gap + barW / 2 + i * (barW + gap),
        pinY: bh / 2,
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
      kind: 'sparkColumn',
      values: vals,
    );
  }

  static VsdxShape triangleBarChart({
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
      final bw = math.max(plotW * unit[i], 0.06);
      final cy = padB + gap + barH / 2 + i * (barH + gap);
      final color = seriesColors[i % seriesColors.length];
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: padL + bw / 2,
        pinY: cy,
        width: bw,
        height: barH * 0.85,
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(0, 0),
            LineTo(0, barH * 0.85),
            LineTo(bw, barH * 0.425),
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
      kind: 'triangleBar',
      values: vals,
    );
  }

  static VsdxShape mirrorColumnChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.4, -0.55, 0.7, -0.3, 0.5];
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.12;
    final padB = h * 0.08;
    final padT = h * 0.08;
    final plotW = w - padL - w * 0.08;
    final plotH = h - padB - padT;
    final midY = padB + plotH / 2;
    final maxAbs = vals.map((v) => v.abs()).fold(0.0, math.max);
    final scale = maxAbs > 0 ? (plotH / 2) / maxAbs : plotH / 2;
    final gap = plotW * 0.08;
    final barW = (plotW - gap * (vals.length + 1)) / vals.length;
    final kids = <VsdxShape>[
      _axesChild(id: next(), width: w, height: h),
      _rectChild(
        id: next(),
        pinX: padL + plotW / 2,
        pinY: midY,
        width: plotW,
        height: 0.02,
        fill: const VsdxColor(0xFF888888),
        chrome: true,
      ),
    ];
    for (var i = 0; i < vals.length; i++) {
      final v = vals[i];
      final bh = math.max(v.abs() * scale, 0.04);
      final cx = padL + gap + barW / 2 + i * (barW + gap);
      final cy = v >= 0 ? midY + bh / 2 : midY - bh / 2;
      kids.add(_rectChild(
        id: next(),
        pinX: cx,
        pinY: cy,
        width: barW * 0.85,
        height: bh,
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
      kind: 'mirrorColumn',
      values: vals,
    );
  }

  static VsdxShape paretoChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.9, 0.65, 0.45, 0.3, 0.2];
    final unit = _unit(vals);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.12;
    final padB = h * 0.12;
    final padT = h * 0.08;
    final plotW = w - padL - w * 0.08;
    final plotH = h - padB - padT;
    final gap = plotW * 0.06;
    final barW = (plotW - gap * (unit.length + 1)) / unit.length;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    final sum = unit.fold<double>(0, (a, b) => a + b);
    var running = 0.0;
    final cumPts = <({double x, double y})>[];
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
      running += unit[i];
      final cy = padB + plotH * (sum > 0 ? running / sum : 0);
      cumPts.add((x: cx, y: cy));
    }
    if (cumPts.length >= 2) {
      var minX = cumPts.first.x, maxX = cumPts.first.x;
      var minY = cumPts.first.y, maxY = cumPts.first.y;
      for (final p in cumPts.skip(1)) {
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
              MoveTo(cumPts.first.x - minX, cumPts.first.y - minY),
              for (final p in cumPts.skip(1))
                LineTo(p.x - minX, p.y - minY),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(
          color: VsdxColor(0xFFE53935),
          weightInches: 0.016,
        ),
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
      kind: 'pareto',
      values: vals,
    );
  }

  static VsdxShape radialColumnChart({
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
    final inner = maxR * 0.18;
    final kids = <VsdxShape>[];
    final n = unit.length;
    final sweep = (2 * math.pi) / n;
    var angle = math.pi / 2;
    for (var i = 0; i < n; i++) {
      final half = sweep * 0.35;
      final a0 = angle + half;
      final a1 = angle - half;
      final outer = inner + (maxR - inner) * unit[i];
      kids.add(_wedgeChild(
        id: next(),
        cx: cx,
        cy: cy,
        rx: outer,
        ry: outer,
        a0: a0,
        a1: a1,
        inner: inner / outer,
        fill: seriesColors[i % seriesColors.length],
      ));
      angle -= sweep;
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'radialColumn',
      values: vals,
    );
  }

  static VsdxShape batteryChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.2,
    double height = 0.9,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.72];
    final level = vals.first.clamp(0.0, 1.0);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final bodyW = w * 0.88;
    final bodyH = h * 0.55;
    final tipW = w * 0.06;
    final kids = <VsdxShape>[
      _rectChild(
        id: next(),
        pinX: bodyW / 2,
        pinY: h / 2,
        width: bodyW,
        height: bodyH,
        fill: const VsdxColor(0xFFE8E8E8),
        chrome: true,
      ),
      _rectChild(
        id: next(),
        pinX: bodyW + tipW / 2,
        pinY: h / 2,
        width: tipW,
        height: bodyH * 0.45,
        fill: const VsdxColor(0xFFBDBDBD),
        chrome: true,
      ),
      _rectChild(
        id: next(),
        pinX: (bodyW * 0.9 * level) / 2 + bodyW * 0.05,
        pinY: h / 2,
        width: math.max(bodyW * 0.9 * level, 0.04),
        height: bodyH * 0.7,
        fill: level > 0.3 ? seriesColors[2] : seriesColors[1],
      ),
    ];
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'battery',
      values: vals,
    );
  }

  static VsdxShape trafficLightChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 0.8,
    double height = 2.0,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.72];
    final level = vals.first.clamp(0.0, 1.0);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final active = level < 0.34 ? 0 : (level < 0.67 ? 1 : 2);
    const colors = <VsdxColor>[
      VsdxColor(0xFFE53935),
      VsdxColor(0xFFFFC000),
      VsdxColor(0xFF43A047),
    ];
    final kids = <VsdxShape>[
      _rectChild(
        id: next(),
        pinX: w / 2,
        pinY: h / 2,
        width: w * 0.7,
        height: h * 0.92,
        fill: const VsdxColor(0xFF424242),
        chrome: true,
      ),
    ];
    for (var i = 0; i < 3; i++) {
      final r = w * 0.22;
      final cy = h * (0.78 - i * 0.28);
      final on = i == active;
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: w / 2,
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
        fill: VsdxFill(
          foreground: on ? colors[i] : const VsdxColor(0xFF616161),
        ),
        line: const VsdxLine(pattern: 0),
        userCells: on ? const <VsdxUserCell>[] : _chromeMeta,
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'trafficLight',
      values: vals,
    );
  }

  static VsdxShape horizontalCylinderChart({
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
    final padR = w * 0.1;
    final plotW = w - padL - padR;
    final plotH = h - padB - h * 0.08;
    final gap = plotH * 0.08;
    final barH = (plotH - gap * (unit.length + 1)) / unit.length;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < unit.length; i++) {
      final bw = math.max(plotW * unit[i], 0.08);
      final cy = padB + gap + barH / 2 + i * (barH + gap);
      final color = seriesColors[i % seriesColors.length];
      final bodyW = math.max(bw - barH * 0.35, 0.04);
      kids.add(_rectChild(
        id: next(),
        pinX: padL + bodyW / 2,
        pinY: cy,
        width: bodyW,
        height: barH * 0.7,
        fill: color,
      ));
      final r = barH * 0.35;
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: padL + bodyW,
        pinY: cy,
        width: r * 0.55,
        height: r * 2,
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
              cx: r * 0.275,
              cy: r,
              aX: r * 0.55,
              aY: r,
              bX: r * 0.275,
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
      kind: 'horizontalCylinder',
      values: vals,
    );
  }

  static VsdxShape sparkWinLossChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.0,
    double height = 0.7,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.4, -0.2, 0.6, -0.5, 0.3, 0.7, -0.1];
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final midY = h / 2;
    final gap = w * 0.04;
    final barW = (w - gap * (vals.length + 1)) / vals.length;
    final kids = <VsdxShape>[
      _rectChild(
        id: next(),
        pinX: w / 2,
        pinY: midY,
        width: w,
        height: 0.015,
        fill: const VsdxColor(0xFFBDBDBD),
        chrome: true,
      ),
    ];
    for (var i = 0; i < vals.length; i++) {
      final v = vals[i];
      final bh = h * 0.38;
      final cx = gap + barW / 2 + i * (barW + gap);
      final cy = v >= 0 ? midY + bh / 2 : midY - bh / 2;
      kids.add(_rectChild(
        id: next(),
        pinX: cx,
        pinY: cy,
        width: barW * 0.85,
        height: bh,
        fill: v >= 0 ? seriesColors[2] : seriesColors[1],
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'sparkWinLoss',
      values: vals,
    );
  }

  static VsdxShape tornadoChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    // Keep userCells order stable; sort a paint copy by absolute value.
    final stored = List<double>.of(
      values ?? const <double>[-0.7, 0.55, -0.4, 0.85, 0.3],
    );
    final painted = List<double>.of(stored)
      ..sort((a, b) => b.abs().compareTo(a.abs()));
    final chart = divergingBarChart(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      values: painted,
      allocId: allocId,
    );
    return chart.copyWith(
      userCells: _meta('tornado', stored),
    );
  }

  static VsdxShape sparkLineChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.0,
    double height = 0.7,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.35, 0.55, 0.4, 0.75, 0.6];
    final unit = _unit(vals);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final pad = 0.06;
    final plotW = w - pad * 2;
    final plotH = h - pad * 2;
    final pts = <({double x, double y})>[];
    for (var i = 0; i < unit.length; i++) {
      final x = pad + (unit.length == 1 ? 0 : plotW * i / (unit.length - 1));
      final y = pad + plotH * unit[i];
      pts.add((x: x, y: y));
    }
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
    final kids = <VsdxShape>[
      VsdxShape(
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
              for (final p in pts.skip(1)) LineTo(p.x - minX, p.y - minY),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(
          color: VsdxColor(0xFF5B9BD5),
          weightInches: 0.016,
        ),
      ),
    ];
    for (var i = 0; i < pts.length; i++) {
      const r = 0.045;
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
      kind: 'sparkLine',
      values: vals,
    );
  }

  static VsdxShape sparkAreaChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.0,
    double height = 0.7,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.3, 0.55, 0.45, 0.8, 0.5];
    final unit = _unit(vals);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final pad = 0.06;
    final plotW = w - pad * 2;
    final plotH = h - pad * 2;
    final pts = <({double x, double y})>[];
    for (var i = 0; i < unit.length; i++) {
      final x = pad + (unit.length == 1 ? 0 : plotW * i / (unit.length - 1));
      final y = pad + plotH * unit[i];
      pts.add((x: x, y: y));
    }
    var minX = pts.first.x, maxX = pts.first.x;
    var maxY = pts.first.y;
    for (final p in pts) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    final minY = pad;
    final aw = math.max(maxX - minX, 0.04);
    final ah = math.max(maxY - minY, 0.04);
    final kids = <VsdxShape>[
      VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: minX + aw / 2,
        pinY: minY + ah / 2,
        width: aw,
        height: ah,
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(pts.first.x - minX, pad - minY),
            LineTo(pts.first.x - minX, pts.first.y - minY),
            for (final p in pts.skip(1)) LineTo(p.x - minX, p.y - minY),
            LineTo(pts.last.x - minX, pad - minY),
            LineTo(pts.first.x - minX, pad - minY),
          ]),
        ],
        fill: const VsdxFill(
          foreground: VsdxColor(0xFF5B9BD5),
          foregroundTransparency: 0.35,
        ),
        line: const VsdxLine(
          color: VsdxColor(0xFF2E75B6),
          weightInches: 0.01,
        ),
      ),
    ];
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'sparkArea',
      values: vals,
    );
  }

  static VsdxShape semiProgressChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.2,
    double height = 1.3,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.68];
    final level = vals.first.clamp(0.0, 1.0);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final cx = w / 2;
    final cy = h * 0.2;
    final r = math.min(w, h) * 0.45;
    const inner = 0.62;
    final kids = <VsdxShape>[
      _wedgeChild(
        id: next(),
        cx: cx,
        cy: cy,
        rx: r,
        ry: r,
        a0: math.pi,
        a1: 0,
        inner: inner,
        fill: const VsdxColor(0xFFE8E8E8),
      ).copyWith(userCells: _chromeMeta),
    ];
    final sweep = math.max(level * math.pi, 0.08);
    kids.add(_wedgeChild(
      id: next(),
      cx: cx,
      cy: cy,
      rx: r,
      ry: r,
      a0: math.pi,
      a1: math.pi - sweep,
      inner: inner,
      fill: seriesColors.first,
    ));
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'semiProgress',
      values: vals,
    );
  }

  static VsdxShape stepProgressChart({
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
    const steps = 5;
    final filled = (level * steps).round().clamp(0, steps);
    final gap = w * 0.03;
    final cellW = (w - gap * (steps + 1)) / steps;
    final kids = <VsdxShape>[];
    for (var i = 0; i < steps; i++) {
      final on = i < filled;
      kids.add(_rectChild(
        id: next(),
        pinX: gap + cellW / 2 + i * (cellW + gap),
        pinY: h / 2,
        width: cellW,
        height: h * 0.55,
        fill: on ? seriesColors.first : const VsdxColor(0xFFE8E8E8),
        chrome: !on,
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'stepProgress',
      values: vals,
    );
  }

  static VsdxShape nightingaleChart({
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
        inner: 0.35,
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
      kind: 'nightingale',
      values: vals,
    );
  }

  static VsdxShape variableColumnChart({
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
    final gap = plotW * 0.06;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    var x0 = padL + gap;
    final sum = unit.fold<double>(0, (a, b) => a + b);
    for (var i = 0; i < unit.length; i++) {
      final bw = math.max(plotW * (sum > 0 ? unit[i] / sum : 1 / unit.length) * 0.9, 0.06);
      final bh = plotH * unit[i];
      kids.add(_rectChild(
        id: next(),
        pinX: x0 + bw / 2,
        pinY: padB + bh / 2,
        width: bw,
        height: bh,
        fill: seriesColors[i % seriesColors.length],
      ));
      x0 += bw + gap * 0.5;
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'variableColumn',
      values: vals,
    );
  }

  static VsdxShape pillBarChart({
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
    final gap = plotH * 0.1;
    final barH = (plotH - gap * (unit.length + 1)) / unit.length;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < unit.length; i++) {
      final bw = math.max(plotW * unit[i], barH);
      final cy = padB + gap + barH / 2 + i * (barH + gap);
      final color = seriesColors[i % seriesColors.length];
      final r = barH * 0.42;
      // Capsule ≈ rect + two half-circles (full ellipses as end caps).
      kids.add(_rectChild(
        id: next(),
        pinX: padL + bw / 2,
        pinY: cy,
        width: math.max(bw - r, 0.04),
        height: barH * 0.75,
        fill: color,
      ));
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: padL + bw - r * 0.15,
        pinY: cy,
        width: r * 1.1,
        height: r * 1.6,
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
              cx: r * 0.55,
              cy: r * 0.8,
              aX: r * 1.1,
              aY: r * 0.8,
              bX: r * 0.55,
              bY: 0,
            ),
          ]),
        ],
        fill: VsdxFill(foreground: color),
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
      kind: 'pillBar',
      values: vals,
    );
  }

  static VsdxShape arrowBarChart({
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
      final bw = math.max(plotW * unit[i], 0.12);
      final cy = padB + gap + barH / 2 + i * (barH + gap);
      final color = seriesColors[i % seriesColors.length];
      final tip = math.min(bw * 0.28, barH);
      final body = math.max(bw - tip, 0.04);
      final bh = barH * 0.75;
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: padL + bw / 2,
        pinY: cy,
        width: bw,
        height: bh,
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(0, bh * 0.2),
            LineTo(body, bh * 0.2),
            LineTo(body, 0),
            LineTo(bw, bh / 2),
            LineTo(body, bh),
            LineTo(body, bh * 0.8),
            LineTo(0, bh * 0.8),
            LineTo(0, bh * 0.2),
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
      kind: 'arrowBar',
      values: vals,
    );
  }

  static VsdxShape diamondLollipopChart({
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
      const s = 0.1;
      final color = seriesColors[i % seriesColors.length];
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: cx,
        pinY: top,
        width: s * 2,
        height: s * 2,
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(s, 0),
            LineTo(s * 2, s),
            LineTo(s, s * 2),
            LineTo(0, s),
            LineTo(s, 0),
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
      kind: 'diamondLollipop',
      values: vals,
    );
  }

  static VsdxShape chevronChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.8,
    double height = 0.9,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? defaultValues;
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final gap = w * 0.02;
    final tip = math.min(w * 0.06, h * 0.45);
    final stepW = (w - gap * (vals.length + 1)) / vals.length;
    final kids = <VsdxShape>[];
    for (var i = 0; i < vals.length; i++) {
      final color = seriesColors[i % seriesColors.length];
      final x0 = gap + i * (stepW + gap);
      final bh = h * 0.7;
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: x0 + stepW / 2,
        pinY: h / 2,
        width: stepW,
        height: bh,
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(0, 0),
            LineTo(stepW - tip, 0),
            LineTo(stepW, bh / 2),
            LineTo(stepW - tip, bh),
            LineTo(0, bh),
            LineTo(tip, bh / 2),
            LineTo(0, 0),
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
      kind: 'chevron',
      values: vals,
    );
  }

  static VsdxShape polarLineChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.0,
    double height = 2.0,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? const <double>[0.55, 0.75, 0.45, 0.85, 0.6];
    final unit = _unit(vals);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final cx = w / 2;
    final cy = h / 2;
    final maxR = math.min(w, h) * 0.38;
    final kids = <VsdxShape>[];
    // Grid rings (chrome).
    for (final f in <double>[0.33, 0.66, 1.0]) {
      final r = maxR * f;
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: cx,
        pinY: cy,
        width: r * 2,
        height: r * 2,
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              EllipseCmd(
                cx: r,
                cy: r,
                aX: r * 2,
                aY: r,
                bX: r,
                bY: 0,
              ),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(
          color: VsdxColor(0xFFD0D0D0),
          weightInches: 0.006,
        ),
        userCells: _chromeMeta,
      ));
    }
    final pts = <({double x, double y})>[];
    final n = unit.length;
    for (var i = 0; i < n; i++) {
      final a = math.pi / 2 - i * (2 * math.pi / n);
      final r = maxR * unit[i];
      pts.add((x: cx + r * math.cos(a), y: cy + r * math.sin(a)));
    }
    pts.add(pts.first);
    var minX = pts.first.x, maxX = pts.first.x;
    var minY = pts.first.y, maxY = pts.first.y;
    for (final p in pts) {
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
            for (final p in pts.skip(1)) LineTo(p.x - minX, p.y - minY),
          ],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: VsdxColor(0xFF5B9BD5),
        weightInches: 0.016,
      ),
    ));
    for (var i = 0; i < n; i++) {
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
      kind: 'polarLine',
      values: vals,
    );
  }

  static VsdxColor _heatColor(double t, {int base = 0xFF1565C0}) {
    final u = t.clamp(0.0, 1.0);
    final a = (base >> 24) & 0xFF;
    final r0 = (base >> 16) & 0xFF;
    final g0 = (base >> 8) & 0xFF;
    final b0 = base & 0xFF;
    // Blend toward white for low intensity.
    final r = (r0 + ((255 - r0) * (1 - u))).round().clamp(0, 255);
    final g = (g0 + ((255 - g0) * (1 - u))).round().clamp(0, 255);
    final b = (b0 + ((255 - b0) * (1 - u))).round().clamp(0, 255);
    return VsdxColor((a << 24) | (r << 16) | (g << 8) | b);
  }

  /// OHLC candlesticks. Values packed as open,high,low,close per candle.
  static VsdxShape candlestickChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? _defaultValuesForKind('candlestick', null);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.12;
    final padB = h * 0.12;
    final padR = w * 0.08;
    final padT = h * 0.08;
    final plotW = w - padL - padR;
    final plotH = h - padB - padT;
    final n = math.max(1, vals.length ~/ 4);
    final gap = plotW * 0.08;
    final slot = (plotW - gap * (n + 1)) / n;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < n; i++) {
      final o = vals[i * 4].clamp(0.0, 1.0);
      final hi = vals[i * 4 + 1].clamp(0.0, 1.0);
      final lo = vals[i * 4 + 2].clamp(0.0, 1.0);
      final c = vals[i * 4 + 3].clamp(0.0, 1.0);
      final cx = padL + gap + slot / 2 + i * (slot + gap);
      final up = c >= o;
      final color = up
          ? const VsdxColor(0xFF43A047)
          : const VsdxColor(0xFFE53935);
      final wickTop = padB + plotH * math.max(hi, math.max(o, c));
      final wickBot = padB + plotH * math.min(lo, math.min(o, c));
      final bodyTop = padB + plotH * math.max(o, c);
      final bodyBot = padB + plotH * math.min(o, c);
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: cx,
        pinY: (wickTop + wickBot) / 2,
        width: 0.02,
        height: math.max(wickTop - wickBot, 0.02),
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              MoveTo(0.01, 0),
              LineTo(0.01, math.max(wickTop - wickBot, 0.02)),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: VsdxLine(color: color, weightInches: 0.012),
        userCells: _chromeMeta,
      ));
      kids.add(_rectChild(
        id: next(),
        pinX: cx,
        pinY: (bodyTop + bodyBot) / 2,
        width: slot * 0.55,
        height: math.max(bodyTop - bodyBot, 0.04),
        fill: color,
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'candlestick',
      values: vals,
    );
  }

  /// Grid heatmap. [extras] = `rows x cols` (default `3x4`).
  static VsdxShape heatmapChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.8,
    List<double>? values,
    String? extras,
    int Function()? allocId,
  }) {
    final grid = parseHeatmapGrid(extras);
    final rows = grid.$1;
    final cols = grid.$2;
    final ex = formatHeatmapGrid(rows, cols);
    var vals = values ?? _defaultValuesForKind('heatmap', ex);
    final need = rows * cols;
    if (vals.length < need) {
      vals = <double>[
        ...vals,
        for (var i = vals.length; i < need; i++) 0.2 + (i % 5) * 0.15,
      ];
    } else if (vals.length > need) {
      vals = vals.sublist(0, need);
    }
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final pad = math.min(w, h) * 0.08;
    final gap = math.min(w, h) * 0.02;
    final cellW = (w - pad * 2 - gap * (cols - 1)) / cols;
    final cellH = (h - pad * 2 - gap * (rows - 1)) / rows;
    final kids = <VsdxShape>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final i = r * cols + c;
        final t = vals[i].clamp(0.0, 1.0);
        kids.add(_rectChild(
          id: next(),
          pinX: pad + cellW / 2 + c * (cellW + gap),
          pinY: h - pad - cellH / 2 - r * (cellH + gap),
          width: cellW,
          height: cellH,
          fill: _heatColor(t),
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
      kind: 'heatmap',
      values: vals,
      extras: ex,
    );
  }

  /// Gantt bars. Values packed as start,duration (0–1) per task.
  static VsdxShape ganttChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.8,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? _defaultValuesForKind('gantt', null);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.12;
    final padB = h * 0.12;
    final padR = w * 0.06;
    final padT = h * 0.08;
    final plotW = w - padL - padR;
    final plotH = h - padB - padT;
    final n = math.max(1, vals.length ~/ 2);
    final gap = plotH * 0.08;
    final barH = (plotH - gap * (n + 1)) / n;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < n; i++) {
      final start = vals[i * 2].clamp(0.0, 0.95);
      final dur = vals[i * 2 + 1].clamp(0.05, 1.0 - start);
      final color = seriesColors[i % seriesColors.length];
      final cy = padB + gap + barH / 2 + i * (barH + gap);
      kids.add(_rectChild(
        id: next(),
        pinX: padL + plotW * (start + dur / 2),
        pinY: cy,
        width: math.max(plotW * dur, 0.06),
        height: barH * 0.7,
        fill: color,
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'gantt',
      values: vals,
    );
  }

  /// Box plot. Values packed as min,q1,median,q3,max per box.
  static VsdxShape boxplotChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? _defaultValuesForKind('boxplot', null);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.12;
    final padB = h * 0.12;
    final padR = w * 0.08;
    final padT = h * 0.08;
    final plotW = w - padL - padR;
    final plotH = h - padB - padT;
    final n = math.max(1, vals.length ~/ 5);
    final gap = plotW * 0.1;
    final slot = (plotW - gap * (n + 1)) / n;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < n; i++) {
      final sorted = <double>[
        vals[i * 5],
        vals[i * 5 + 1],
        vals[i * 5 + 2],
        vals[i * 5 + 3],
        vals[i * 5 + 4],
      ]..sort();
      final mn = sorted[0].clamp(0.0, 1.0);
      final q1 = sorted[1].clamp(0.0, 1.0);
      final med = sorted[2].clamp(0.0, 1.0);
      final q3 = sorted[3].clamp(0.0, 1.0);
      final mx = sorted[4].clamp(0.0, 1.0);
      final color = seriesColors[i % seriesColors.length];
      final cx = padL + gap + slot / 2 + i * (slot + gap);
      double y(double t) => padB + plotH * t;
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: cx,
        pinY: (y(mn) + y(mx)) / 2,
        width: 0.02,
        height: math.max(y(mx) - y(mn), 0.02),
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              MoveTo(0.01, 0),
              LineTo(0.01, math.max(y(mx) - y(mn), 0.02)),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: VsdxLine(color: color, weightInches: 0.01),
        userCells: _chromeMeta,
      ));
      kids.add(_rectChild(
        id: next(),
        pinX: cx,
        pinY: (y(q1) + y(q3)) / 2,
        width: slot * 0.55,
        height: math.max(y(q3) - y(q1), 0.04),
        fill: color,
      ));
      kids.add(_rectChild(
        id: next(),
        pinX: cx,
        pinY: y(med),
        width: slot * 0.55,
        height: 0.025,
        fill: const VsdxColor(0xFF212121),
        chrome: true,
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'boxplot',
      values: vals,
    );
  }

  /// Slope chart. Values packed as before,after per series.
  static VsdxShape slopeChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? _defaultValuesForKind('slope', null);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.18;
    final padB = h * 0.12;
    final padR = w * 0.18;
    final padT = h * 0.1;
    final plotH = h - padB - padT;
    final x0 = padL;
    final x1 = w - padR;
    final n = math.max(1, vals.length ~/ 2);
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < n; i++) {
      final a = vals[i * 2].clamp(0.0, 1.0);
      final b = vals[i * 2 + 1].clamp(0.0, 1.0);
      final color = seriesColors[i % seriesColors.length];
      final y0 = padB + plotH * a;
      final y1 = padB + plotH * b;
      final minY = math.min(y0, y1);
      final maxY = math.max(y0, y1);
      final lh = math.max(maxY - minY, 0.04);
      final lw = math.max(x1 - x0, 0.04);
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: (x0 + x1) / 2,
        pinY: (y0 + y1) / 2,
        width: lw,
        height: lh,
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              MoveTo(0, y0 - minY),
              LineTo(lw, y1 - minY),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: VsdxLine(color: color, weightInches: 0.016),
        userCells: _chromeMeta,
      ));
      for (final p in <(double, double)>[(x0, y0), (x1, y1)]) {
        const r = 0.055;
        kids.add(VsdxShape(
          id: next(),
          name: _sheetName(id),
          pinX: p.$1,
          pinY: p.$2,
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
          fill: VsdxFill(foreground: color),
          line: _barLine(color),
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
      kind: 'slope',
      values: vals,
    );
  }

  /// Calendar heatmap (weeks × 7 days). [extras] = `weeks=N`.
  static VsdxShape calendarHeatChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 1.6,
    List<double>? values,
    String? extras,
    int Function()? allocId,
  }) {
    final weeks = parseCalendarWeeks(extras);
    final ex = formatCalendarWeeks(weeks);
    final need = weeks * 7;
    var vals = values ?? _defaultValuesForKind('calendarHeat', ex);
    if (vals.length < need) {
      vals = <double>[
        ...vals,
        for (var i = vals.length; i < need; i++) ((i * 37) % 100) / 100.0,
      ];
    } else if (vals.length > need) {
      vals = vals.sublist(0, need);
    }
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final pad = math.min(w, h) * 0.08;
    final gap = math.min(w, h) * 0.015;
    final cellW = (w - pad * 2 - gap * 6) / 7;
    final cellH = (h - pad * 2 - gap * (weeks - 1)) / weeks;
    final kids = <VsdxShape>[];
    for (var week = 0; week < weeks; week++) {
      for (var day = 0; day < 7; day++) {
        final i = week * 7 + day;
        final t = vals[i].clamp(0.0, 1.0);
        kids.add(_rectChild(
          id: next(),
          pinX: pad + cellW / 2 + day * (cellW + gap),
          pinY: h - pad - cellH / 2 - week * (cellH + gap),
          width: cellW,
          height: cellH,
          fill: _heatColor(t, base: 0xFF2E7D32),
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
      kind: 'calendarHeat',
      values: vals,
      extras: ex,
    );
  }

  /// Range bars: values packed as low,high per category.
  static VsdxShape rangeBarChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? _defaultValuesForKind('rangeBar', null);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.12;
    final padB = h * 0.12;
    final padR = w * 0.08;
    final padT = h * 0.08;
    final plotW = w - padL - padR;
    final plotH = h - padB - padT;
    final n = math.max(1, vals.length ~/ 2);
    final gap = plotH * 0.08;
    final barH = (plotH - gap * (n + 1)) / n;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < n; i++) {
      final lo = math.min(vals[i * 2], vals[i * 2 + 1]).clamp(0.0, 1.0);
      final hi = math.max(vals[i * 2], vals[i * 2 + 1]).clamp(0.0, 1.0);
      final color = seriesColors[i % seriesColors.length];
      final cy = padB + gap + barH / 2 + i * (barH + gap);
      kids.add(_rectChild(
        id: next(),
        pinX: padL + plotW * ((lo + hi) / 2),
        pinY: cy,
        width: math.max(plotW * (hi - lo), 0.06),
        height: barH * 0.65,
        fill: color,
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'rangeBar',
      values: vals,
    );
  }

  /// Dumbbell: start/end dots connected by a stem (horizontal).
  static VsdxShape dumbbellChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? _defaultValuesForKind('dumbbell', null);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.12;
    final padB = h * 0.12;
    final padR = w * 0.08;
    final padT = h * 0.08;
    final plotW = w - padL - padR;
    final plotH = h - padB - padT;
    final n = math.max(1, vals.length ~/ 2);
    final gap = plotH * 0.1;
    final rowH = (plotH - gap * (n + 1)) / n;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < n; i++) {
      final a = vals[i * 2].clamp(0.0, 1.0);
      final b = vals[i * 2 + 1].clamp(0.0, 1.0);
      final color = seriesColors[i % seriesColors.length];
      final cy = padB + gap + rowH / 2 + i * (rowH + gap);
      final x0 = padL + plotW * a;
      final x1 = padL + plotW * b;
      final minX = math.min(x0, x1);
      final maxX = math.max(x0, x1);
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: (minX + maxX) / 2,
        pinY: cy,
        width: math.max(maxX - minX, 0.04),
        height: 0.02,
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              MoveTo(0, 0.01),
              LineTo(math.max(maxX - minX, 0.04), 0.01),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: VsdxLine(color: color, weightInches: 0.014),
        userCells: _chromeMeta,
      ));
      for (final x in <double>[x0, x1]) {
        const r = 0.055;
        kids.add(VsdxShape(
          id: next(),
          name: _sheetName(id),
          pinX: x,
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
          fill: VsdxFill(foreground: color),
          line: _barLine(color),
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
      kind: 'dumbbell',
      values: vals,
    );
  }

  /// Quadrant scatter: values packed as x,y per point.
  static VsdxShape quadrantChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.2,
    double height = 2.0,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? _defaultValuesForKind('quadrant', null);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final pad = math.min(w, h) * 0.1;
    final plotW = w - pad * 2;
    final plotH = h - pad * 2;
    final kids = <VsdxShape>[
      _axesChild(id: next(), width: w, height: h),
      // Crosshair (chrome).
      VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: w / 2,
        pinY: h / 2,
        width: w,
        height: h,
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              MoveTo(pad + plotW / 2, pad),
              LineTo(pad + plotW / 2, pad + plotH),
              MoveTo(pad, pad + plotH / 2),
              LineTo(pad + plotW, pad + plotH / 2),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(
          color: VsdxColor(0xFFBDBDBD),
          weightInches: 0.008,
        ),
        userCells: _chromeMeta,
      ),
    ];
    final n = math.max(1, vals.length ~/ 2);
    for (var i = 0; i < n; i++) {
      final x = vals[i * 2].clamp(0.0, 1.0);
      final y = vals[i * 2 + 1].clamp(0.0, 1.0);
      final color = seriesColors[i % seriesColors.length];
      const r = 0.07;
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: pad + plotW * x,
        pinY: pad + plotH * y,
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
      kind: 'quadrant',
      values: vals,
    );
  }

  /// Timeline milestones along a baseline (0–1 positions).
  static VsdxShape timelineChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.8,
    double height = 1.2,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? _defaultValuesForKind('timeline', null);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.08;
    final padR = w * 0.08;
    final plotW = w - padL - padR;
    final baseY = h * 0.45;
    final kids = <VsdxShape>[
      VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: w / 2,
        pinY: baseY,
        width: plotW,
        height: 0.02,
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              const MoveTo(0, 0.01),
              LineTo(plotW, 0.01),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(
          color: VsdxColor(0xFF888888),
          weightInches: 0.014,
        ),
        userCells: _chromeMeta,
      ),
    ];
    for (var i = 0; i < vals.length; i++) {
      final t = vals[i].clamp(0.0, 1.0);
      final color = seriesColors[i % seriesColors.length];
      final x = padL + plotW * t;
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: x,
        pinY: baseY,
        width: 0.02,
        height: h * 0.28,
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              MoveTo(0.01, 0),
              LineTo(0.01, h * 0.28),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: VsdxLine(color: color, weightInches: 0.01),
        userCells: _chromeMeta,
      ));
      const r = 0.06;
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: x,
        pinY: baseY + h * 0.28,
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
      kind: 'timeline',
      values: vals,
    );
  }

  /// Nested donut: inner ring then outer ring. [extras] = `inner=N`.
  static VsdxShape nestedDonutChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.0,
    double height = 2.0,
    List<double>? values,
    String? extras,
    int Function()? allocId,
  }) {
    final vals = values ?? _defaultValuesForKind('nestedDonut', null);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final cx = w / 2;
    final cy = h / 2;
    final rx = math.min(w, h) * 0.42;
    final ry = rx;
    final innerCount = parseNestedInner(extras, vals.length);
    final ex = formatNestedInner(innerCount);
    final kids = <VsdxShape>[];

    void addRing(List<double> ringVals, double outer, double hole, int colorOff) {
      final sum = ringVals.fold<double>(0, (a, b) => a + b.abs());
      if (sum <= 0) return;
      var a0 = math.pi / 2;
      for (var i = 0; i < ringVals.length; i++) {
        final sweep = (ringVals[i].abs() / sum) * 2 * math.pi;
        final a1 = a0 - sweep;
        final color = seriesColors[(colorOff + i) % seriesColors.length];
        kids.add(_wedgeChild(
          id: next(),
          cx: cx,
          cy: cy,
          rx: outer * rx,
          ry: outer * ry,
          a0: a0,
          a1: a1,
          inner: hole / outer,
          fill: color,
        ));
        a0 = a1;
      }
    }

    final innerVals = vals.take(innerCount).toList();
    final outerVals = vals.skip(innerCount).toList();
    if (outerVals.isEmpty) {
      addRing(vals, 1.0, 0.55, 0);
    } else {
      addRing(outerVals, 1.0, 0.62, innerCount);
      addRing(innerVals, 0.55, 0.28, 0);
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'nestedDonut',
      values: vals,
      extras: ex,
    );
  }

  /// KPI actual vs target bar with track.
  static VsdxShape kpiTargetChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.2,
    double height = 1.2,
    List<double>? values,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('kpiTarget', null);
    final actual = (raw.isNotEmpty ? raw[0] : 0.72).clamp(0.0, 1.0);
    final targetStored = (raw.length > 1 ? raw[1] : 0.9).clamp(0.0, 1.0);
    final target = math.max(targetStored, 0.05);
    final vals = <double>[actual, targetStored];
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.1;
    final padR = w * 0.1;
    final trackY = h * 0.42;
    final trackH = h * 0.22;
    final plotW = w - padL - padR;
    final kids = <VsdxShape>[
      _rectChild(
        id: next(),
        pinX: padL + plotW / 2,
        pinY: trackY,
        width: plotW,
        height: trackH,
        fill: const VsdxColor(0xFFE0E0E0),
        chrome: true,
      ),
      _rectChild(
        id: next(),
        pinX: padL + plotW * actual / 2,
        pinY: trackY,
        width: math.max(plotW * actual, 0.04),
        height: trackH * 0.85,
        fill: seriesColors.first,
      ),
      // Target marker.
      VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: padL + plotW * target,
        pinY: trackY,
        width: 0.03,
        height: trackH * 1.6,
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              MoveTo(0.015, 0),
              LineTo(0.015, trackH * 1.6),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(
          color: VsdxColor(0xFFE53935),
          weightInches: 0.016,
        ),
        userCells: _chromeMeta,
      ),
    ];
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'kpiTarget',
      values: vals,
    );
  }

  /// Editable data table with configurable rows/cols and cell styles.
  ///
  /// [extras] = `RxC;header=1;borders=1;zebra=0`.
  /// [colors]: `[0]` header fill, `[1]` body fill, `[2]` zebra fill.
  /// [labels]: row-major cell text.
  static VsdxShape dataTableChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 3.2,
    double height = 2.0,
    List<double>? values,
    List<String>? labels,
    List<VsdxColor>? colors,
    String? extras,
    int Function()? allocId,
  }) {
    final grid = parseTableGrid(extras);
    final rows = grid.$1;
    final cols = grid.$2;
    final headerOn = parseTableFlag(extras, 'header', defaultValue: true);
    final bordersOn = parseTableFlag(extras, 'borders', defaultValue: true);
    final zebraOn = parseTableFlag(extras, 'zebra', defaultValue: false);
    final ex = formatTableExtras(
      rows: rows,
      cols: cols,
      header: headerOn,
      borders: bordersOn,
      zebra: zebraOn,
    );
    final need = rows * cols;
    var vals = values ?? List<double>.filled(need, 1);
    if (vals.length < need) {
      vals = <double>[...vals, for (var i = vals.length; i < need; i++) 1.0];
    } else if (vals.length > need) {
      vals = vals.sublist(0, need);
    }
    final labs = padLabels(
      labels ??
          <String>[
            for (var r = 0; r < rows; r++)
              for (var c = 0; c < cols; c++)
                headerOn && r == 0 ? 'H${c + 1}' : 'R${r + 1}C${c + 1}',
          ],
      need,
    );
    final headerFill = (colors != null && colors.isNotEmpty)
        ? colors[0]
        : const VsdxColor(0xFF5B9BD5);
    final bodyFill = (colors != null && colors.length > 1)
        ? colors[1]
        : const VsdxColor(0xFFFFFFFF);
    final zebraFill = (colors != null && colors.length > 2)
        ? colors[2]
        : const VsdxColor(0xFFF0F4F8);
    final styleColors = <VsdxColor>[headerFill, bodyFill, zebraFill];

    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final pad = math.min(w, h) * 0.04;
    final gap = bordersOn ? 0.0 : math.min(w, h) * 0.008;
    final cellW = (w - pad * 2 - gap * (cols - 1)) / cols;
    final cellH = (h - pad * 2 - gap * (rows - 1)) / rows;
    final font = (cellH * 0.28).clamp(0.06, 0.12);
    final borderLine = bordersOn
        ? const VsdxLine(color: VsdxColor(0xFF90A4AE), weightInches: 0.008)
        : const VsdxLine(pattern: 0);
    final kids = <VsdxShape>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final i = r * cols + c;
        final isHeader = headerOn && r == 0;
        final fill = isHeader
            ? headerFill
            : (zebraOn && r.isOdd ? zebraFill : bodyFill);
        final textColor = isHeader
            ? const VsdxColor(0xFFFFFFFF)
            : const VsdxColor(0xFF212121);
        final text = labs[i];
        kids.add(VsdxShape(
          id: next(),
          name: _sheetName(id),
          pinX: pad + cellW / 2 + c * (cellW + gap),
          pinY: h - pad - cellH / 2 - r * (cellH + gap),
          width: cellW,
          height: cellH,
          text: text,
          richText: VsdxRichText(runs: <VsdxTextRun>[
            VsdxTextRun(
              text: text,
              charStyle: VsdxCharStyle(
                fontSizeInches: font,
                color: textColor,
                style: isHeader
                    ? VsdxFontStyle.boldStyle
                    : VsdxFontStyle.regular,
              ),
              paraStyle: const VsdxParaStyle(
                horizontalAlign: VsdxHorzAlign.center,
              ),
            ),
          ]),
          geometries: <VsdxGeometry>[
            VsdxGeometry(commands: <VsdxPathCommand>[
              const MoveTo(0, 0),
              LineTo(cellW, 0),
              LineTo(cellW, cellH),
              LineTo(0, cellH),
              const LineTo(0, 0),
            ]),
          ],
          fill: VsdxFill(foreground: fill),
          line: bordersOn ? borderLine : _barLine(fill),
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
      kind: 'dataTable',
      values: vals,
      labels: labs,
      colors: styleColors,
      extras: ex,
    );
  }

  /// Two-circle Venn: values = onlyA, onlyB, both.
  static VsdxShape vennChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.8,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('venn', null);
    final stored = <double>[
      for (var i = 0; i < 3; i++)
        (i < raw.length ? raw[i] : 0.3).clamp(0.0, 1.0),
    ];
    final labs = padLabels(
      labels ?? const <String>['A', 'B', 'A∩B'],
      3,
    );
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final r = math.min(w, h) * 0.36;
    final cy = h / 2;
    final cxA = w * 0.38;
    final cxB = w * 0.62;
    final kids = <VsdxShape>[];
    void addCircle(double cx, VsdxColor fill) {
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
        fill: VsdxFill(foreground: fill, foregroundTransparency: 0.35),
        line: _barLine(fill),
      ));
    }

    addCircle(cxA, seriesColors[0]);
    addCircle(cxB, seriesColors[1]);
    // Value labels as small text shapes.
    final spots = <(double, double, String)>[
      (cxA - r * 0.35, cy, '${labs[0]}\n${formatValues(<double>[stored[0]])}'),
      (cxB + r * 0.35, cy, '${labs[1]}\n${formatValues(<double>[stored[1]])}'),
      ((cxA + cxB) / 2, cy, '${labs[2]}\n${formatValues(<double>[stored[2]])}'),
    ];
    for (var i = 0; i < spots.length; i++) {
      final s = spots[i];
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: s.$1,
        pinY: s.$2,
        width: 0.45,
        height: 0.35,
        text: s.$3,
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: s.$3,
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.08,
              color: VsdxColor(0xFF212121),
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
              const LineTo(0.45, 0),
              const LineTo(0.45, 0.35),
              const LineTo(0, 0.35),
              const LineTo(0, 0),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
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
      kind: 'venn',
      values: stored,
      labels: labs,
    );
  }

  /// Scorecard KPI tiles. [extras] = `cols=N`.
  static VsdxShape scorecardChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 3.0,
    double height = 1.2,
    List<double>? values,
    List<String>? labels,
    String? extras,
    int Function()? allocId,
  }) {
    final vals = values ?? _defaultValuesForKind('scorecard', null);
    final n = math.max(1, vals.length);
    final cols = parseScorecardCols(extras).clamp(1, n);
    final ex = formatScorecardCols(cols);
    final labs = padLabels(labels ?? defaultLabels(n), n);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final rows = (n + cols - 1) ~/ cols;
    final pad = math.min(w, h) * 0.06;
    final gap = math.min(w, h) * 0.04;
    final cellW = (w - pad * 2 - gap * (cols - 1)) / cols;
    final cellH = (h - pad * 2 - gap * (rows - 1)) / rows;
    final kids = <VsdxShape>[];
    for (var i = 0; i < n; i++) {
      final r = i ~/ cols;
      final c = i % cols;
      final color = seriesColors[i % seriesColors.length];
      final pct = formatPercent(vals[i].clamp(0.0, 1.0));
      final text = '${labs[i]}\n$pct%';
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: pad + cellW / 2 + c * (cellW + gap),
        pinY: h - pad - cellH / 2 - r * (cellH + gap),
        width: cellW,
        height: cellH,
        text: text,
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: text,
            charStyle: VsdxCharStyle(
              fontSizeInches: (cellH * 0.18).clamp(0.07, 0.12),
              color: const VsdxColor(0xFF212121),
              style: VsdxFontStyle.boldStyle,
            ),
            paraStyle: const VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
            ),
          ),
        ]),
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            const MoveTo(0, 0),
            LineTo(cellW, 0),
            LineTo(cellW, cellH),
            LineTo(0, cellH),
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
      kind: 'scorecard',
      values: List<double>.of(vals),
      labels: labs,
      extras: ex,
    );
  }

  /// Concentric progress rings (outer → inner).
  static VsdxShape radialMultiChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.0,
    double height = 2.0,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? _defaultValuesForKind('radialMulti', null);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final cx = w / 2;
    final cy = h / 2;
    final maxR = math.min(w, h) * 0.42;
    final n = math.max(1, vals.length);
    final kids = <VsdxShape>[];
    for (var i = 0; i < n; i++) {
      final outer = 1.0 - i * (0.55 / n);
      final hole = outer - 0.12;
      final level = vals[i].clamp(0.0, 1.0);
      final color = seriesColors[i % seriesColors.length];
      // Track (chrome) — almost full ring.
      kids.add(_wedgeChild(
        id: next(),
        cx: cx,
        cy: cy,
        rx: maxR * outer,
        ry: maxR * outer,
        a0: math.pi / 2,
        a1: math.pi / 2 - math.pi * 2 * 0.999,
        inner: hole / outer,
        fill: const VsdxColor(0xFFE0E0E0),
      ).copyWith(userCells: _chromeMeta));
      // Value arc.
      if (level > 0.01) {
        kids.add(_wedgeChild(
          id: next(),
          cx: cx,
          cy: cy,
          rx: maxR * outer,
          ry: maxR * outer,
          a0: math.pi / 2,
          a1: math.pi / 2 - level * math.pi * 2,
          inner: hole / outer,
          fill: color,
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
      kind: 'radialMulti',
      values: List<double>.of(vals),
    );
  }

  /// Floating / span columns: values packed as low,high.
  static VsdxShape spanColumnChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 1.8,
    List<double>? values,
    int Function()? allocId,
  }) {
    final vals = values ?? _defaultValuesForKind('spanColumn', null);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.12;
    final padB = h * 0.12;
    final padR = w * 0.08;
    final padT = h * 0.08;
    final plotW = w - padL - padR;
    final plotH = h - padB - padT;
    final n = math.max(1, vals.length ~/ 2);
    final gap = plotW * 0.08;
    final slot = (plotW - gap * (n + 1)) / n;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < n; i++) {
      final lo = math.min(vals[i * 2], vals[i * 2 + 1]).clamp(0.0, 1.0);
      final hi = math.max(vals[i * 2], vals[i * 2 + 1]).clamp(0.0, 1.0);
      final color = seriesColors[i % seriesColors.length];
      final cx = padL + gap + slot / 2 + i * (slot + gap);
      kids.add(_rectChild(
        id: next(),
        pinX: cx,
        pinY: padB + plotH * ((lo + hi) / 2),
        width: slot * 0.55,
        height: math.max(plotH * (hi - lo), 0.04),
        fill: color,
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'spanColumn',
      values: vals,
    );
  }

  /// Ranking bars with rank badges.
  static VsdxShape rankingChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 1.8,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    // Keep userCells order stable for the side-panel editor; sort only for paint.
    final source = values ?? _defaultValuesForKind('ranking', null);
    final stored = <double>[
      for (final v in source.isEmpty ? const <double>[0] : source)
        v.clamp(0.0, 1.0),
    ];
    final storedLabs = padLabels(labels ?? defaultLabels(stored.length), stored.length);
    final order = <int>[for (var i = 0; i < stored.length; i++) i]
      ..sort((a, b) => stored[b].compareTo(stored[a]));
    final vals = <double>[for (final i in order) stored[i]];
    final labs = <String>[for (final i in order) storedLabs[i]];
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.18;
    final padB = h * 0.1;
    final padR = w * 0.08;
    final padT = h * 0.08;
    final plotW = w - padL - padR;
    final plotH = h - padB - padT;
    final n = vals.length;
    final gap = plotH * 0.08;
    final barH = (plotH - gap * (n + 1)) / n;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < n; i++) {
      final color = seriesColors[i % seriesColors.length];
      final cy = h - padT - gap - barH / 2 - i * (barH + gap);
      kids.add(_rectChild(
        id: next(),
        pinX: padL + plotW * vals[i] / 2,
        pinY: cy,
        width: math.max(plotW * vals[i], 0.06),
        height: barH * 0.7,
        fill: color,
      ));
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: padL + plotW / 2,
        pinY: cy,
        width: plotW * 0.92,
        height: barH * 0.8,
        text: labs[i],
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: labs[i],
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.07,
              color: VsdxColor(0xFFFFFFFF),
              style: VsdxFontStyle.boldStyle,
            ),
            paraStyle: const VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.left,
            ),
          ),
        ]),
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            noLine: true,
            commands: <VsdxPathCommand>[
              const MoveTo(0, 0),
              LineTo(plotW * 0.92, 0),
              LineTo(plotW * 0.92, barH * 0.8),
              LineTo(0, barH * 0.8),
              const LineTo(0, 0),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
        userCells: _chromeMeta,
      ));
      final badge = '${i + 1}';
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: padL * 0.45,
        pinY: cy,
        width: 0.22,
        height: 0.22,
        text: badge,
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: badge,
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.09,
              color: VsdxColor(0xFFFFFFFF),
              style: VsdxFontStyle.boldStyle,
            ),
            paraStyle: const VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
            ),
          ),
        ]),
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            EllipseCmd(
              cx: 0.11,
              cy: 0.11,
              aX: 0.22,
              aY: 0.11,
              bX: 0.11,
              bY: 0,
            ),
          ]),
        ],
        fill: VsdxFill(foreground: color),
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
      kind: 'ranking',
      values: stored,
      labels: storedLabs,
    );
  }

  /// Process steps: values 1=done, 0.5=current, 0=todo.
  static VsdxShape processStepsChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 3.2,
    double height = 1.0,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final vals = values ?? _defaultValuesForKind('processSteps', null);
    final n = math.max(1, vals.length);
    final labs = padLabels(labels ?? defaultLabels(n), n);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final pad = w * 0.04;
    final gap = w * 0.02;
    final stepW = (w - pad * 2 - gap * (n - 1)) / n;
    final stepH = h * 0.55;
    final cy = h * 0.55;
    final tip = stepW * 0.18;
    final kids = <VsdxShape>[];
    for (var i = 0; i < n; i++) {
      final status = vals[i].clamp(0.0, 1.0);
      final color = status >= 0.99
          ? const VsdxColor(0xFF43A047)
          : status >= 0.4
              ? const VsdxColor(0xFF1E88E5)
              : const VsdxColor(0xFFBDBDBD);
      final x0 = pad + i * (stepW + gap);
      final body = math.max(stepW - tip, 0.08);
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: x0 + stepW / 2,
        pinY: cy,
        width: stepW,
        height: stepH,
        text: labs[i],
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: labs[i],
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.08,
              color: VsdxColor(0xFFFFFFFF),
              style: VsdxFontStyle.boldStyle,
            ),
            paraStyle: const VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
            ),
          ),
        ]),
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(0, 0),
            LineTo(body, 0),
            LineTo(stepW, stepH / 2),
            LineTo(body, stepH),
            LineTo(0, stepH),
            LineTo(tip * 0.6, stepH / 2),
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
      kind: 'processSteps',
      values: List<double>.of(vals),
      labels: labs,
    );
  }

  /// Arc gauge with value + target marker. Values: [value, target].
  static VsdxShape arcGaugeChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.2,
    double height = 1.4,
    List<double>? values,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('arcGauge', null);
    final level = (raw.isNotEmpty ? raw[0] : 0.68).clamp(0.0, 1.0);
    final targetStored = (raw.length > 1 ? raw[1] : 0.85).clamp(0.0, 1.0);
    final target = math.max(targetStored, 0.05);
    final vals = <double>[level, targetStored];
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final cx = w / 2;
    final cy = h * 0.72;
    final r = math.min(w, h) * 0.55;
    const inner = 0.62;
    final kids = <VsdxShape>[
      _wedgeChild(
        id: next(),
        cx: cx,
        cy: cy,
        rx: r,
        ry: r,
        a0: math.pi,
        a1: 0,
        inner: inner,
        fill: const VsdxColor(0xFFE0E0E0),
      ).copyWith(userCells: _chromeMeta),
      if (level > 0.01)
        _wedgeChild(
          id: next(),
          cx: cx,
          cy: cy,
          rx: r,
          ry: r,
          a0: math.pi,
          a1: math.pi * (1 - level),
          inner: inner,
          fill: seriesColors.first,
        ),
    ];
    // Target tick.
    final ta = math.pi * (1 - target);
    final t0x = cx + r * inner * 0.9 * math.cos(ta);
    final t0y = cy + r * inner * 0.9 * math.sin(ta);
    final t1x = cx + r * 1.05 * math.cos(ta);
    final t1y = cy + r * 1.05 * math.sin(ta);
    final minX = math.min(t0x, t1x) - 0.02;
    final maxX = math.max(t0x, t1x) + 0.02;
    final minY = math.min(t0y, t1y) - 0.02;
    final maxY = math.max(t0y, t1y) + 0.02;
    kids.add(VsdxShape(
      id: next(),
      name: _sheetName(id),
      pinX: (minX + maxX) / 2,
      pinY: (minY + maxY) / 2,
      width: math.max(maxX - minX, 0.04),
      height: math.max(maxY - minY, 0.04),
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(t0x - minX, t0y - minY),
            LineTo(t1x - minX, t1y - minY),
          ],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: VsdxColor(0xFFE53935),
        weightInches: 0.016,
      ),
      userCells: _chromeMeta,
    ));
    final label = '${formatPercent(level)}%';
    kids.add(VsdxShape(
      id: next(),
      name: _sheetName(id),
      pinX: cx,
      pinY: cy - r * 0.15,
      width: 0.7,
      height: 0.28,
      text: label,
      richText: VsdxRichText(runs: <VsdxTextRun>[
        VsdxTextRun(
          text: label,
          charStyle: const VsdxCharStyle(
            fontSizeInches: 0.12,
            color: VsdxColor(0xFF212121),
            style: VsdxFontStyle.boldStyle,
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
            const LineTo(0.7, 0),
            const LineTo(0.7, 0.28),
            const LineTo(0, 0.28),
            const LineTo(0, 0),
          ],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      userCells: _chromeMeta,
    ));
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'arcGauge',
      values: vals,
    );
  }

  /// Multiple bullet meters. Values packed as actual,target.
  static VsdxShape bulletGroupChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 1.8,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final vals = values ?? _defaultValuesForKind('bulletGroup', null);
    final n = math.max(1, vals.length ~/ 2);
    final labs = padLabels(labels ?? defaultLabels(n), n);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.08;
    final padR = w * 0.06;
    final padT = h * 0.08;
    final padB = h * 0.08;
    final plotW = w - padL - padR;
    final plotH = h - padT - padB;
    final gap = plotH * 0.1;
    final rowH = (plotH - gap * (n + 1)) / n;
    final kids = <VsdxShape>[];
    for (var i = 0; i < n; i++) {
      final actual = vals[i * 2].clamp(0.0, 1.0);
      final target = vals[i * 2 + 1].clamp(0.05, 1.0);
      final color = seriesColors[i % seriesColors.length];
      final cy = h - padT - gap - rowH / 2 - i * (rowH + gap);
      kids.add(_rectChild(
        id: next(),
        pinX: padL + plotW / 2,
        pinY: cy,
        width: plotW,
        height: rowH * 0.55,
        fill: const VsdxColor(0xFFE0E0E0),
        chrome: true,
      ));
      kids.add(_rectChild(
        id: next(),
        pinX: padL + plotW * actual / 2,
        pinY: cy,
        width: math.max(plotW * actual, 0.04),
        height: rowH * 0.35,
        fill: color,
      ));
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: padL + plotW * target,
        pinY: cy,
        width: 0.025,
        height: rowH * 0.75,
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              MoveTo(0.012, 0),
              LineTo(0.012, rowH * 0.75),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(
          color: VsdxColor(0xFFE53935),
          weightInches: 0.012,
        ),
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
      kind: 'bulletGroup',
      values: vals,
      labels: labs,
    );
  }

  /// Likert stacked bar (5 sentiment segments).
  static VsdxShape likertChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.8,
    double height = 0.9,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('likert', null);
    final stored = <double>[
      for (var i = 0; i < 5; i++)
        (i < raw.length ? raw[i] : 0.2).clamp(0.0, 1.0),
    ];
    final vals = <double>[for (final v in stored) math.max(v, 0.02)];
    final labs = padLabels(
      labels ??
          const <String>['SD', 'D', 'N', 'A', 'SA'],
      5,
    );
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final pad = w * 0.06;
    final barH = h * 0.45;
    final cy = h * 0.55;
    final sum = vals.fold<double>(0, (a, b) => a + b);
    final plotW = w - pad * 2;
    var x = pad;
    const palette = <VsdxColor>[
      VsdxColor(0xFFE53935),
      VsdxColor(0xFFFB8C00),
      VsdxColor(0xFFFFC000),
      VsdxColor(0xFF7CB342),
      VsdxColor(0xFF43A047),
    ];
    final kids = <VsdxShape>[];
    for (var i = 0; i < 5; i++) {
      final segW = plotW * (vals[i] / sum);
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: x + segW / 2,
        pinY: cy,
        width: math.max(segW, 0.04),
        height: barH,
        text: labs[i],
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: labs[i],
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.07,
              color: VsdxColor(0xFFFFFFFF),
              style: VsdxFontStyle.boldStyle,
            ),
            paraStyle: const VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
            ),
          ),
        ]),
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            const MoveTo(0, 0),
            LineTo(math.max(segW, 0.04), 0),
            LineTo(math.max(segW, 0.04), barH),
            LineTo(0, barH),
            const LineTo(0, 0),
          ]),
        ],
        fill: VsdxFill(foreground: palette[i]),
        line: _barLine(palette[i]),
      ));
      x += segW;
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'likert',
      values: stored,
      labels: labs,
    );
  }

  /// Single-row heat strip. [extras] = `cells=N`.
  static VsdxShape heatStripChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.8,
    double height = 0.7,
    List<double>? values,
    String? extras,
    int Function()? allocId,
  }) {
    final cells = parseHeatStripCells(extras);
    final ex = formatHeatStripCells(cells);
    var vals = values ?? _defaultValuesForKind('heatStrip', ex);
    if (vals.length < cells) {
      vals = <double>[
        ...vals,
        for (var i = vals.length; i < cells; i++) ((i * 37) % 100) / 100.0,
      ];
    } else if (vals.length > cells) {
      vals = vals.sublist(0, cells);
    }
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final pad = math.min(w, h) * 0.1;
    final gap = w * 0.01;
    final cellW = (w - pad * 2 - gap * (cells - 1)) / cells;
    final cellH = h - pad * 2;
    final kids = <VsdxShape>[];
    for (var i = 0; i < cells; i++) {
      final t = vals[i].clamp(0.0, 1.0);
      kids.add(_rectChild(
        id: next(),
        pinX: pad + cellW / 2 + i * (cellW + gap),
        pinY: h / 2,
        width: cellW,
        height: cellH,
        fill: _heatColor(t, base: 0xFF6A1B9A),
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'heatStrip',
      values: vals,
      extras: ex,
    );
  }

  /// Side-by-side A/B compare columns. Values packed as a,b.
  static VsdxShape dualCompareChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 1.8,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final vals = values ?? _defaultValuesForKind('dualCompare', null);
    final n = math.max(1, vals.length ~/ 2);
    final labs = padLabels(labels ?? defaultLabels(n), n);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.12;
    final padB = h * 0.12;
    final padR = w * 0.08;
    final padT = h * 0.08;
    final plotW = w - padL - padR;
    final plotH = h - padB - padT;
    final gap = plotW * 0.08;
    final slot = (plotW - gap * (n + 1)) / n;
    final kids = <VsdxShape>[_axesChild(id: next(), width: w, height: h)];
    for (var i = 0; i < n; i++) {
      final a = vals[i * 2].clamp(0.0, 1.0);
      final b = vals[i * 2 + 1].clamp(0.0, 1.0);
      final cx = padL + gap + slot / 2 + i * (slot + gap);
      final barW = slot * 0.35;
      kids.add(_rectChild(
        id: next(),
        pinX: cx - barW * 0.55,
        pinY: padB + plotH * a / 2,
        width: barW,
        height: math.max(plotH * a, 0.04),
        fill: seriesColors[0],
      ));
      kids.add(_rectChild(
        id: next(),
        pinX: cx + barW * 0.55,
        pinY: padB + plotH * b / 2,
        width: barW,
        height: math.max(plotH * b, 0.04),
        fill: seriesColors[1],
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'dualCompare',
      values: vals,
      labels: labs,
    );
  }

  /// Status board cards. Values: 1=ok, 0.5=warn, 0=bad.
  static VsdxShape statusBoardChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.8,
    double height = 1.4,
    List<double>? values,
    List<String>? labels,
    String? extras,
    int Function()? allocId,
  }) {
    final vals = values ?? _defaultValuesForKind('statusBoard', null);
    final n = math.max(1, vals.length);
    final cols = parseScorecardCols(extras).clamp(1, n);
    final ex = formatScorecardCols(cols);
    final labs = padLabels(labels ?? defaultLabels(n), n);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final rows = (n + cols - 1) ~/ cols;
    final pad = math.min(w, h) * 0.06;
    final gap = math.min(w, h) * 0.04;
    final cellW = (w - pad * 2 - gap * (cols - 1)) / cols;
    final cellH = (h - pad * 2 - gap * (rows - 1)) / rows;
    final kids = <VsdxShape>[];
    for (var i = 0; i < n; i++) {
      final r = i ~/ cols;
      final c = i % cols;
      final s = vals[i].clamp(0.0, 1.0);
      final color = s >= 0.99
          ? const VsdxColor(0xFF43A047)
          : s >= 0.4
              ? const VsdxColor(0xFFFFC000)
              : const VsdxColor(0xFFE53935);
      final status = s >= 0.99 ? 'OK' : s >= 0.4 ? 'WARN' : 'BAD';
      final text = '${labs[i]}\n$status';
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: pad + cellW / 2 + c * (cellW + gap),
        pinY: h - pad - cellH / 2 - r * (cellH + gap),
        width: cellW,
        height: cellH,
        text: text,
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: text,
            charStyle: VsdxCharStyle(
              fontSizeInches: (cellH * 0.16).clamp(0.07, 0.11),
              color: const VsdxColor(0xFFFFFFFF),
              style: VsdxFontStyle.boldStyle,
            ),
            paraStyle: const VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
            ),
          ),
        ]),
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            const MoveTo(0, 0),
            LineTo(cellW, 0),
            LineTo(cellW, cellH),
            LineTo(0, cellH),
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
      kind: 'statusBoard',
      values: List<double>.of(vals),
      labels: labs,
      extras: ex,
    );
  }

  /// Progress list: labeled horizontal bars. Values in 0–1.
  static VsdxShape progressListChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 1.8,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('progressList', null);
    final stored = <double>[for (final v in raw) v.clamp(0.0, 1.0)];
    final vals = <double>[for (final v in stored) math.max(v, 0.02)];
    final n = math.max(1, vals.length);
    final labs = padLabels(labels ?? defaultLabels(n), n);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.28;
    final padR = w * 0.06;
    final padT = h * 0.08;
    final padB = h * 0.08;
    final plotW = w - padL - padR;
    final plotH = h - padT - padB;
    final gap = plotH * 0.1;
    final barH = (plotH - gap * (n - 1)) / n;
    final kids = <VsdxShape>[];
    for (var i = 0; i < n; i++) {
      final color = seriesColors[i % seriesColors.length];
      final cy = h - padT - barH / 2 - i * (barH + gap);
      kids.add(_rectChild(
        id: next(),
        pinX: padL + plotW / 2,
        pinY: cy,
        width: plotW,
        height: barH * 0.55,
        fill: const VsdxColor(0xFFE0E0E0),
        chrome: true,
      ));
      kids.add(_rectChild(
        id: next(),
        pinX: padL + plotW * vals[i] / 2,
        pinY: cy,
        width: math.max(plotW * vals[i], 0.05),
        height: barH * 0.55,
        fill: color,
      ));
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: padL * 0.5,
        pinY: cy,
        width: padL * 0.9,
        height: barH * 0.8,
        text: labs[i],
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: labs[i],
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.07,
              color: VsdxColor(0xFF424242),
            ),
            paraStyle: const VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.right,
            ),
          ),
        ]),
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            noLine: true,
            commands: <VsdxPathCommand>[
              const MoveTo(0, 0),
              LineTo(padL * 0.9, 0),
              LineTo(padL * 0.9, barH * 0.8),
              LineTo(0, barH * 0.8),
              const LineTo(0, 0),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
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
      kind: 'progressList',
      values: stored,
      labels: labs,
    );
  }

  /// Milestone track: markers on a line at positions 0–1.
  static VsdxShape milestoneChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.8,
    double height = 1.3,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('milestone', null);
    final vals = <double>[for (final v in raw) v.clamp(0.0, 1.0)];
    final n = math.max(1, vals.length);
    final labs = padLabels(labels ?? defaultLabels(n), n);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.08;
    final padR = w * 0.08;
    final plotW = w - padL - padR;
    final baseY = h * 0.4;
    final kids = <VsdxShape>[
      VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: w / 2,
        pinY: baseY,
        width: plotW,
        height: 0.025,
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              const MoveTo(0, 0.012),
              LineTo(plotW, 0.012),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(
          color: VsdxColor(0xFF888888),
          weightInches: 0.014,
        ),
        userCells: _chromeMeta,
      ),
    ];
    for (var i = 0; i < n; i++) {
      final color = seriesColors[i % seriesColors.length];
      final x = padL + plotW * vals[i];
      const r = 0.07;
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: x,
        pinY: baseY,
        width: r * 2,
        height: r * 2,
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            MoveTo(r, 0),
            LineTo(r * 2, r),
            LineTo(r, r * 2),
            LineTo(0, r),
            LineTo(r, 0),
          ]),
        ],
        fill: VsdxFill(foreground: color),
        line: _barLine(color),
      ));
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: x,
        pinY: baseY + h * 0.28,
        width: math.min(0.55, plotW / n * 1.2),
        height: 0.28,
        text: labs[i],
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: labs[i],
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.07,
              color: VsdxColor(0xFF424242),
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
              LineTo(0.5, 0),
              LineTo(0.5, 0.28),
              LineTo(0, 0.28),
              const LineTo(0, 0),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
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
      kind: 'milestone',
      values: vals,
      labels: labs,
    );
  }

  /// Balance bar: left/right opposing bars from center. Values packed L,R,…
  static VsdxShape balanceBarChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 1.8,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('balanceBar', null);
    final pairs = math.max(1, raw.length ~/ 2);
    final stored = <double>[
      for (var i = 0; i < pairs; i++) ...[
        (i * 2 < raw.length ? raw[i * 2] : 0.5).clamp(0.0, 1.0),
        (i * 2 + 1 < raw.length ? raw[i * 2 + 1] : 0.5).clamp(0.0, 1.0),
      ],
    ];
    final vals = <double>[for (final v in stored) math.max(v, 0.02)];
    final labs = padLabels(labels ?? defaultLabels(pairs), pairs);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.06;
    final padR = w * 0.06;
    final padT = h * 0.1;
    final padB = h * 0.1;
    final mid = w / 2;
    final half = (w - padL - padR) / 2 * 0.92;
    final plotH = h - padT - padB;
    final gap = plotH * 0.1;
    final barH = (plotH - gap * (pairs - 1)) / pairs;
    final kids = <VsdxShape>[
      VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: mid,
        pinY: h / 2,
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
          color: VsdxColor(0xFFBDBDBD),
          weightInches: 0.01,
        ),
        userCells: _chromeMeta,
      ),
    ];
    for (var i = 0; i < pairs; i++) {
      final left = vals[i * 2];
      final right = vals[i * 2 + 1];
      final cy = h - padT - barH / 2 - i * (barH + gap);
      final lh = barH * 0.55;
      kids.add(_rectChild(
        id: next(),
        pinX: mid - half * left / 2,
        pinY: cy,
        width: math.max(half * left, 0.05),
        height: lh,
        fill: seriesColors[0],
      ));
      kids.add(_rectChild(
        id: next(),
        pinX: mid + half * right / 2,
        pinY: cy,
        width: math.max(half * right, 0.05),
        height: lh,
        fill: seriesColors[1],
      ));
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: mid,
        pinY: cy + barH * 0.42,
        width: w * 0.35,
        height: 0.18,
        text: labs[i],
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: labs[i],
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.065,
              color: VsdxColor(0xFF616161),
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
              LineTo(0.35, 0),
              LineTo(0.35, 0.18),
              LineTo(0, 0.18),
              const LineTo(0, 0),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
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
      kind: 'balanceBar',
      values: stored,
      labels: labs,
    );
  }

  /// Meter cluster: side-by-side mini progress meters.
  static VsdxShape meterClusterChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.8,
    double height = 1.2,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('meterCluster', null);
    final stored = <double>[for (final v in raw) v.clamp(0.0, 1.0)];
    final vals = <double>[for (final v in stored) math.max(v, 0.02)];
    final n = math.max(1, vals.length);
    final labs = padLabels(labels ?? defaultLabels(n), n);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final pad = w * 0.05;
    final gap = w * 0.04;
    final cellW = (w - pad * 2 - gap * (n - 1)) / n;
    final kids = <VsdxShape>[];
    for (var i = 0; i < n; i++) {
      final color = seriesColors[i % seriesColors.length];
      final cx = pad + cellW / 2 + i * (cellW + gap);
      final trackH = h * 0.18;
      final trackY = h * 0.38;
      kids.add(_rectChild(
        id: next(),
        pinX: cx,
        pinY: trackY,
        width: cellW * 0.85,
        height: trackH,
        fill: const VsdxColor(0xFFE0E0E0),
        chrome: true,
      ));
      kids.add(_rectChild(
        id: next(),
        pinX: cx - cellW * 0.85 * (1 - vals[i]) / 2,
        pinY: trackY,
        width: math.max(cellW * 0.85 * vals[i], 0.04),
        height: trackH,
        fill: color,
      ));
      final pct = '${formatPercent(vals[i])}%';
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: cx,
        pinY: h * 0.62,
        width: cellW * 0.9,
        height: 0.22,
        text: pct,
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: pct,
            charStyle: VsdxCharStyle(
              fontSizeInches: 0.09,
              color: color,
              style: VsdxFontStyle.boldStyle,
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
              LineTo(0.4, 0),
              LineTo(0.4, 0.22),
              LineTo(0, 0.22),
              const LineTo(0, 0),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
        userCells: _chromeMeta,
      ));
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: cx,
        pinY: h * 0.82,
        width: cellW * 0.9,
        height: 0.2,
        text: labs[i],
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: labs[i],
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.065,
              color: VsdxColor(0xFF616161),
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
              LineTo(0.4, 0),
              LineTo(0.4, 0.2),
              LineTo(0, 0.2),
              const LineTo(0, 0),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
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
      kind: 'meterCluster',
      values: stored,
      labels: labs,
    );
  }

  /// Priority matrix: fixed 2×2 cells with intensity + labels.
  static VsdxShape priorityMatrixChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 2.0,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('priorityMatrix', null);
    final vals = <double>[
      for (var i = 0; i < 4; i++)
        (i < raw.length ? raw[i] : 0.5).clamp(0.0, 1.0),
    ];
    final defaultLabs = const <String>[
      'Do first',
      'Schedule',
      'Delegate',
      'Drop',
    ];
    final labs = padLabels(labels ?? defaultLabs, 4);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final pad = math.min(w, h) * 0.06;
    final gap = math.min(w, h) * 0.04;
    final cellW = (w - pad * 2 - gap) / 2;
    final cellH = (h - pad * 2 - gap) / 2;
    const palette = <VsdxColor>[
      VsdxColor(0xFFE53935),
      VsdxColor(0xFFFFC000),
      VsdxColor(0xFF1E88E5),
      VsdxColor(0xFF9E9E9E),
    ];
    final kids = <VsdxShape>[];
    for (var i = 0; i < 4; i++) {
      final r = i ~/ 2;
      final c = i % 2;
      final base = palette[i];
      final t = vals[i];
      final fill = VsdxColor(
        (0xFF << 24) |
            ((((base.value >> 16) & 0xFF) * (0.35 + 0.65 * t)).round() << 16) |
            ((((base.value >> 8) & 0xFF) * (0.35 + 0.65 * t)).round() << 8) |
            (((base.value & 0xFF) * (0.35 + 0.65 * t)).round()),
      );
      final text = '${labs[i]}\n${formatPercent(t)}%';
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: pad + cellW / 2 + c * (cellW + gap),
        pinY: h - pad - cellH / 2 - r * (cellH + gap),
        width: cellW,
        height: cellH,
        text: text,
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: text,
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.08,
              color: VsdxColor(0xFFFFFFFF),
              style: VsdxFontStyle.boldStyle,
            ),
            paraStyle: const VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
            ),
          ),
        ]),
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            const MoveTo(0, 0),
            LineTo(cellW, 0),
            LineTo(cellW, cellH),
            LineTo(0, cellH),
            const LineTo(0, 0),
          ]),
        ],
        fill: VsdxFill(foreground: fill),
        line: _barLine(fill),
      ));
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'priorityMatrix',
      values: vals,
      labels: labs,
    );
  }

  /// Cycle flow: equal wedges around a ring with step labels.
  static VsdxShape cycleFlowChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.2,
    double height = 2.2,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('cycleFlow', null);
    final n = math.max(3, math.min(8, raw.isEmpty ? 4 : raw.length));
    // Persist user weights as-is (0–1); only drawing uses a non-zero floor.
    final stored = <double>[
      for (var i = 0; i < n; i++)
        (i < raw.length ? raw[i] : 1.0).clamp(0.0, 1.0),
    ];
    final vals = <double>[
      for (final v in stored) math.max(v, 0.05),
    ];
    final labs = padLabels(labels ?? defaultLabels(n), n);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final cx = w / 2;
    final cy = h / 2;
    final r = math.min(w, h) * 0.42;
    const inner = 0.55;
    final sum = vals.fold<double>(0, (a, b) => a + b);
    var a0 = -math.pi / 2;
    final kids = <VsdxShape>[];
    for (var i = 0; i < n; i++) {
      final sweep = (vals[i] / sum) * math.pi * 2;
      final a1 = a0 + sweep;
      final color = seriesColors[i % seriesColors.length];
      kids.add(_wedgeChild(
        id: next(),
        cx: cx,
        cy: cy,
        rx: r,
        ry: r,
        a0: a0,
        a1: a1,
        inner: inner,
        fill: color,
      ));
      final mid = a0 + sweep / 2;
      final lx = cx + r * 0.78 * math.cos(mid);
      final ly = cy + r * 0.78 * math.sin(mid);
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: lx,
        pinY: ly,
        width: 0.55,
        height: 0.22,
        text: labs[i],
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: labs[i],
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.07,
              color: VsdxColor(0xFFFFFFFF),
              style: VsdxFontStyle.boldStyle,
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
              LineTo(0.55, 0),
              LineTo(0.55, 0.22),
              LineTo(0, 0.22),
              const LineTo(0, 0),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
        userCells: _chromeMeta,
      ));
      a0 = a1;
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'cycleFlow',
      values: stored,
      labels: labs,
    );
  }


  /// Checklist: done (1) / todo (0) rows with labels.
  static VsdxShape checkboxListChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.4,
    double height = 1.6,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('checkboxList', null);
    final vals = <double>[for (final v in raw) v >= 0.5 ? 1.0 : 0.0];
    final n = math.max(1, vals.length);
    final labs = padLabels(labels ?? defaultLabels(n), n);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final pad = h * 0.08;
    final gap = h * 0.06;
    final rowH = (h - pad * 2 - gap * (n - 1)) / n;
    final kids = <VsdxShape>[];
    for (var i = 0; i < n; i++) {
      final done = vals[i] >= 0.5;
      final cy = h - pad - rowH / 2 - i * (rowH + gap);
      final box = math.min(rowH * 0.7, w * 0.12);
      final color = done
          ? const VsdxColor(0xFF43A047)
          : const VsdxColor(0xFFBDBDBD);
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: w * 0.1,
        pinY: cy,
        width: box,
        height: box,
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            const MoveTo(0, 0),
            LineTo(box, 0),
            LineTo(box, box),
            LineTo(0, box),
            const LineTo(0, 0),
          ]),
        ],
        fill: VsdxFill(foreground: color),
        line: _barLine(color),
      ));
      if (done) {
        kids.add(VsdxShape(
          id: next(),
          name: _sheetName(id),
          pinX: w * 0.1,
          pinY: cy,
          width: box,
          height: box,
          geometries: <VsdxGeometry>[
            VsdxGeometry(
              noFill: true,
              commands: <VsdxPathCommand>[
                MoveTo(box * 0.2, box * 0.5),
                LineTo(box * 0.42, box * 0.72),
                LineTo(box * 0.8, box * 0.28),
              ],
            ),
          ],
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(
            color: VsdxColor(0xFFFFFFFF),
            weightInches: 0.014,
          ),
          userCells: _chromeMeta,
        ));
      }
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: w * 0.55,
        pinY: cy,
        width: w * 0.7,
        height: rowH * 0.8,
        text: labs[i],
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: labs[i],
            charStyle: VsdxCharStyle(
              fontSizeInches: 0.08,
              color: const VsdxColor(0xFF212121),
              style: done ? VsdxFontStyle.regular : VsdxFontStyle.regular,
            ),
            paraStyle: const VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.left,
            ),
          ),
        ]),
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            noLine: true,
            commands: <VsdxPathCommand>[
              const MoveTo(0, 0),
              LineTo(0.7, 0),
              LineTo(0.7, 0.2),
              LineTo(0, 0.2),
              const LineTo(0, 0),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
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
      kind: 'checkboxList',
      values: vals,
      labels: labs,
    );
  }

  /// Gap analysis: actual vs target bars. Values packed actual,target,…
  static VsdxShape gapAnalysisChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 1.8,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('gapAnalysis', null);
    final pairs = math.max(1, raw.length ~/ 2);
    final stored = <double>[
      for (var i = 0; i < pairs; i++) ...[
        (i * 2 < raw.length ? raw[i * 2] : 0.5).clamp(0.0, 1.0),
        (i * 2 + 1 < raw.length ? raw[i * 2 + 1] : 0.8).clamp(0.0, 1.0),
      ],
    ];
    final vals = <double>[for (final v in stored) math.max(v, 0.02)];
    final labs = padLabels(labels ?? defaultLabels(pairs), pairs);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.28;
    final padR = w * 0.06;
    final padT = h * 0.08;
    final padB = h * 0.08;
    final plotW = w - padL - padR;
    final plotH = h - padT - padB;
    final gap = plotH * 0.12;
    final rowH = (plotH - gap * (pairs - 1)) / pairs;
    final kids = <VsdxShape>[];
    for (var i = 0; i < pairs; i++) {
      final actual = vals[i * 2];
      final target = vals[i * 2 + 1];
      final cy = h - padT - rowH / 2 - i * (rowH + gap);
      final barH = rowH * 0.35;
      kids.add(_rectChild(
        id: next(),
        pinX: padL + plotW * target / 2,
        pinY: cy + barH * 0.55,
        width: math.max(plotW * target, 0.05),
        height: barH,
        fill: const VsdxColor(0xFFBDBDBD),
        chrome: true,
      ));
      kids.add(_rectChild(
        id: next(),
        pinX: padL + plotW * actual / 2,
        pinY: cy - barH * 0.55,
        width: math.max(plotW * actual, 0.05),
        height: barH,
        fill: seriesColors[i % seriesColors.length],
      ));
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: padL * 0.5,
        pinY: cy,
        width: padL * 0.9,
        height: rowH * 0.7,
        text: labs[i],
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: labs[i],
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.07,
              color: VsdxColor(0xFF424242),
            ),
            paraStyle: const VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.right,
            ),
          ),
        ]),
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            noLine: true,
            commands: <VsdxPathCommand>[
              const MoveTo(0, 0),
              LineTo(0.4, 0),
              LineTo(0.4, 0.2),
              LineTo(0, 0.2),
              const LineTo(0, 0),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
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
      kind: 'gapAnalysis',
      values: stored,
      labels: labs,
    );
  }

  /// Stage funnel: decreasing width stages top→bottom.
  static VsdxShape stageFunnelChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.8,
    double height = 1.6,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('stageFunnel', null);
    final stored = <double>[for (final v in raw) v.clamp(0.0, 1.0)];
    final vals = <double>[for (final v in stored) math.max(v, 0.08)];
    final n = math.max(1, vals.length);
    final labs = padLabels(labels ?? defaultLabels(n), n);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padT = h * 0.06;
    final padB = h * 0.06;
    final gap = h * 0.03;
    final stageH = (h - padT - padB - gap * (n - 1)) / n;
    final kids = <VsdxShape>[];
    for (var i = 0; i < n; i++) {
      final color = seriesColors[i % seriesColors.length];
      final sw = w * vals[i];
      final cy = h - padT - stageH / 2 - i * (stageH + gap);
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: w / 2,
        pinY: cy,
        width: math.max(sw, 0.2),
        height: stageH,
        text: labs[i],
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: labs[i],
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.08,
              color: VsdxColor(0xFFFFFFFF),
              style: VsdxFontStyle.boldStyle,
            ),
            paraStyle: const VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
            ),
          ),
        ]),
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            const MoveTo(0, 0),
            LineTo(math.max(sw, 0.2), 0),
            LineTo(math.max(sw, 0.2), stageH),
            LineTo(0, stageH),
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
      kind: 'stageFunnel',
      values: stored,
      labels: labs,
    );
  }

  /// Rhythm bars: equalizer-style vertical columns.
  static VsdxShape rhythmBarsChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 1.4,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('rhythmBars', null);
    final stored = <double>[for (final v in raw) v.clamp(0.0, 1.0)];
    final vals = <double>[for (final v in stored) math.max(v, 0.05)];
    final n = math.max(1, vals.length);
    final labs = padLabels(labels ?? defaultLabels(n), n);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.06;
    final padR = w * 0.06;
    final padB = h * 0.22;
    final padT = h * 0.08;
    final plotW = w - padL - padR;
    final plotH = h - padT - padB;
    final gap = plotW * 0.06;
    final barW = (plotW - gap * (n - 1)) / n;
    final kids = <VsdxShape>[];
    for (var i = 0; i < n; i++) {
      final color = seriesColors[i % seriesColors.length];
      final bh = plotH * vals[i];
      final cx = padL + barW / 2 + i * (barW + gap);
      kids.add(_rectChild(
        id: next(),
        pinX: cx,
        pinY: padB + bh / 2,
        width: barW * 0.85,
        height: math.max(bh, 0.05),
        fill: color,
      ));
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: cx,
        pinY: padB * 0.45,
        width: barW,
        height: padB * 0.7,
        text: labs[i],
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: labs[i],
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.06,
              color: VsdxColor(0xFF616161),
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
              LineTo(0.2, 0),
              LineTo(0.2, 0.15),
              LineTo(0, 0.15),
              const LineTo(0, 0),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
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
      kind: 'rhythmBars',
      values: stored,
      labels: labs,
    );
  }

  /// Vote stack: three segments (Yes / No / Abstain).
  static VsdxShape voteStackChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 0.9,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('voteStack', null);
    final stored = <double>[
      for (var i = 0; i < 3; i++)
        (i < raw.length ? raw[i] : 0.33).clamp(0.0, 1.0),
    ];
    final vals = <double>[for (final v in stored) math.max(v, 0.02)];
    final labs = padLabels(
      labels ?? const <String>['Yes', 'No', 'Abstain'],
      3,
    );
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final pad = w * 0.06;
    final barH = h * 0.45;
    final cy = h * 0.55;
    final sum = vals.fold<double>(0, (a, b) => a + b);
    final plotW = w - pad * 2;
    var x = pad;
    const palette = <VsdxColor>[
      VsdxColor(0xFF43A047),
      VsdxColor(0xFFE53935),
      VsdxColor(0xFF9E9E9E),
    ];
    final kids = <VsdxShape>[];
    for (var i = 0; i < 3; i++) {
      final segW = plotW * (vals[i] / sum);
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: x + segW / 2,
        pinY: cy,
        width: math.max(segW, 0.04),
        height: barH,
        text: labs[i],
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: labs[i],
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.07,
              color: VsdxColor(0xFFFFFFFF),
              style: VsdxFontStyle.boldStyle,
            ),
            paraStyle: const VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
            ),
          ),
        ]),
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            const MoveTo(0, 0),
            LineTo(math.max(segW, 0.04), 0),
            LineTo(math.max(segW, 0.04), barH),
            LineTo(0, barH),
            const LineTo(0, 0),
          ]),
        ],
        fill: VsdxFill(foreground: palette[i]),
        line: _barLine(palette[i]),
      ));
      x += segW;
    }
    return _group(
      id: id,
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      children: kids,
      kind: 'voteStack',
      values: stored,
      labels: labs,
    );
  }

  /// Traffic row: lights with OK/WARN/BAD status + labels.
  static VsdxShape trafficRowChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.8,
    double height = 0.9,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('trafficRow', null);
    final vals = <double>[for (final v in raw) v.clamp(0.0, 1.0)];
    final n = math.max(1, vals.length);
    final labs = padLabels(labels ?? defaultLabels(n), n);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final pad = w * 0.06;
    final gap = w * 0.04;
    final cellW = (w - pad * 2 - gap * (n - 1)) / n;
    final kids = <VsdxShape>[];
    for (var i = 0; i < n; i++) {
      final s = vals[i];
      final color = s >= 0.99
          ? const VsdxColor(0xFF43A047)
          : s >= 0.4
              ? const VsdxColor(0xFFFFC000)
              : const VsdxColor(0xFFE53935);
      final cx = pad + cellW / 2 + i * (cellW + gap);
      final r = math.min(cellW, h) * 0.22;
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: cx,
        pinY: h * 0.42,
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
        fill: VsdxFill(foreground: color),
        line: _barLine(color),
      ));
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: cx,
        pinY: h * 0.78,
        width: cellW * 0.9,
        height: 0.22,
        text: labs[i],
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: labs[i],
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.065,
              color: VsdxColor(0xFF424242),
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
              LineTo(0.4, 0),
              LineTo(0.4, 0.22),
              LineTo(0, 0.22),
              const LineTo(0, 0),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
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
      kind: 'trafficRow',
      values: vals,
      labels: labs,
    );
  }


  /// Star rating rows: value 0–1 fills up to 5 stars.
  static VsdxShape starRatingChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 1.5,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('starRating', null);
    final vals = <double>[for (final v in raw) v.clamp(0.0, 1.0)];
    final n = math.max(1, vals.length);
    final labs = padLabels(labels ?? defaultLabels(n), n);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final pad = h * 0.08;
    final gap = h * 0.06;
    final rowH = (h - pad * 2 - gap * (n - 1)) / n;
    final kids = <VsdxShape>[];
    for (var i = 0; i < n; i++) {
      final cy = h - pad - rowH / 2 - i * (rowH + gap);
      final filled = (vals[i] * 5).clamp(0.0, 5.0);
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: w * 0.18,
        pinY: cy,
        width: w * 0.32,
        height: rowH * 0.7,
        text: labs[i],
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: labs[i],
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.07,
              color: VsdxColor(0xFF424242),
            ),
            paraStyle: const VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.right,
            ),
          ),
        ]),
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            noLine: true,
            commands: <VsdxPathCommand>[
              const MoveTo(0, 0),
              LineTo(0.4, 0),
              LineTo(0.4, 0.2),
              LineTo(0, 0.2),
              const LineTo(0, 0),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
        userCells: _chromeMeta,
      ));
      final starSize = math.min(rowH * 0.55, w * 0.08);
      final startX = w * 0.4;
      for (var s = 0; s < 5; s++) {
        final on = filled >= s + 1
            ? true
            : filled > s
                ? true
                : false;
        final color = on
            ? const VsdxColor(0xFFFFC000)
            : const VsdxColor(0xFFE0E0E0);
        final cx = startX + starSize / 2 + s * (starSize * 1.25);
        kids.add(_rectChild(
          id: next(),
          pinX: cx,
          pinY: cy,
          width: starSize,
          height: starSize,
          fill: color,
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
      kind: 'starRating',
      values: vals,
      labels: labs,
    );
  }

  /// Compare cards: two side-by-side KPI cards.
  static VsdxShape compareCardsChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.8,
    double height = 1.4,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('compareCards', null);
    final vals = <double>[
      (raw.isNotEmpty ? raw[0] : 0.72).clamp(0.0, 1.0),
      (raw.length > 1 ? raw[1] : 0.58).clamp(0.0, 1.0),
    ];
    final labs = padLabels(labels ?? const <String>['A', 'B'], 2);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final pad = w * 0.05;
    final gap = w * 0.06;
    final cardW = (w - pad * 2 - gap) / 2;
    final kids = <VsdxShape>[];
    for (var i = 0; i < 2; i++) {
      final color = seriesColors[i % seriesColors.length];
      final cx = pad + cardW / 2 + i * (cardW + gap);
      final text = '${labs[i]}\n${formatPercent(vals[i])}%';
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: cx,
        pinY: h / 2,
        width: cardW,
        height: h * 0.85,
        text: text,
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: text,
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.11,
              color: VsdxColor(0xFFFFFFFF),
              style: VsdxFontStyle.boldStyle,
            ),
            paraStyle: const VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
            ),
          ),
        ]),
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            const MoveTo(0, 0),
            LineTo(cardW, 0),
            LineTo(cardW, h * 0.85),
            LineTo(0, h * 0.85),
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
      kind: 'compareCards',
      values: vals,
      labels: labs,
    );
  }

  /// Pipeline: connected horizontal stages.
  static VsdxShape pipelineChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 3.2,
    double height = 1.1,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('pipeline', null);
    // Persist configured weights; geometry uses a visible minimum height.
    final stored = <double>[for (final v in raw) v.clamp(0.0, 1.0)];
    final vals = <double>[for (final v in stored) math.max(v, 0.15)];
    final n = math.max(1, vals.length);
    final labs = padLabels(labels ?? defaultLabels(n), n);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final pad = w * 0.04;
    final gap = w * 0.015;
    final stageW = (w - pad * 2 - gap * (n - 1)) / n;
    final stageH = h * 0.5;
    final cy = h * 0.55;
    final tip = stageW * 0.18;
    final kids = <VsdxShape>[];
    for (var i = 0; i < n; i++) {
      final color = seriesColors[i % seriesColors.length];
      final x0 = pad + i * (stageW + gap);
      final body = math.max(stageW - tip, 0.1);
      final stageHeight = stageH * vals[i].clamp(0.5, 1.0);
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: x0 + stageW / 2,
        pinY: cy,
        width: stageW,
        height: stageHeight,
        text: labs[i],
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: labs[i],
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.07,
              color: VsdxColor(0xFFFFFFFF),
              style: VsdxFontStyle.boldStyle,
            ),
            paraStyle: const VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
            ),
          ),
        ]),
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            const MoveTo(0, 0),
            LineTo(body, 0),
            LineTo(stageW, stageHeight / 2),
            LineTo(body, stageHeight),
            LineTo(0, stageHeight),
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
      kind: 'pipeline',
      values: stored,
      labels: labs,
    );
  }

  /// Win/loss strip: green W / red L cells.
  static VsdxShape winLossStripChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.8,
    double height = 0.8,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('winLossStrip', null);
    final vals = <double>[for (final v in raw) v >= 0.5 ? 1.0 : 0.0];
    final n = math.max(1, vals.length);
    final labs = padLabels(
      labels ??
          <String>[for (var i = 0; i < n; i++) (vals[i] >= 0.5 ? 'W' : 'L')],
      n,
    );
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final pad = w * 0.05;
    final gap = w * 0.02;
    final cellW = (w - pad * 2 - gap * (n - 1)) / n;
    final cellH = h * 0.55;
    final kids = <VsdxShape>[];
    for (var i = 0; i < n; i++) {
      final win = vals[i] >= 0.5;
      final color =
          win ? const VsdxColor(0xFF43A047) : const VsdxColor(0xFFE53935);
      final text = labs[i].trim().isEmpty ? (win ? 'W' : 'L') : labs[i];
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: pad + cellW / 2 + i * (cellW + gap),
        pinY: h * 0.5,
        width: cellW,
        height: cellH,
        text: text,
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: text,
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.1,
              color: VsdxColor(0xFFFFFFFF),
              style: VsdxFontStyle.boldStyle,
            ),
            paraStyle: const VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
            ),
          ),
        ]),
        geometries: <VsdxGeometry>[
          VsdxGeometry(commands: <VsdxPathCommand>[
            const MoveTo(0, 0),
            LineTo(cellW, 0),
            LineTo(cellW, cellH),
            LineTo(0, cellH),
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
      kind: 'winLossStrip',
      values: vals,
      labels: labs,
    );
  }

  /// Quota board: actual/target progress rows.
  static VsdxShape quotaBoardChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 1.8,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('quotaBoard', null);
    final pairs = math.max(1, raw.length ~/ 2);
    final stored = <double>[
      for (var i = 0; i < pairs; i++) ...[
        (i * 2 < raw.length ? raw[i * 2] : 0.6).clamp(0.0, 1.0),
        (i * 2 + 1 < raw.length ? raw[i * 2 + 1] : 1.0).clamp(0.0, 1.0),
      ],
    ];
    final vals = <double>[
      for (var i = 0; i < pairs; i++) ...[
        math.max(stored[i * 2], 0.02),
        math.max(stored[i * 2 + 1], 0.05),
      ],
    ];
    final labs = padLabels(labels ?? defaultLabels(pairs), pairs);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    final padL = w * 0.28;
    final padR = w * 0.06;
    final padT = h * 0.08;
    final padB = h * 0.08;
    final plotW = w - padL - padR;
    final plotH = h - padT - padB;
    final gap = plotH * 0.12;
    final rowH = (plotH - gap * (pairs - 1)) / pairs;
    final kids = <VsdxShape>[];
    for (var i = 0; i < pairs; i++) {
      final actual = vals[i * 2];
      final target = vals[i * 2 + 1];
      final ratio = (actual / target).clamp(0.0, 1.2);
      final cy = h - padT - rowH / 2 - i * (rowH + gap);
      final barH = rowH * 0.45;
      kids.add(_rectChild(
        id: next(),
        pinX: padL + plotW / 2,
        pinY: cy,
        width: plotW,
        height: barH,
        fill: const VsdxColor(0xFFE0E0E0),
        chrome: true,
      ));
      final fillW = plotW * ratio.clamp(0.0, 1.0);
      kids.add(_rectChild(
        id: next(),
        pinX: padL + fillW / 2,
        pinY: cy,
        width: math.max(fillW, 0.04),
        height: barH,
        fill: ratio >= 1
            ? const VsdxColor(0xFF43A047)
            : seriesColors[i % seriesColors.length],
      ));
      // Target tick at full quota.
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: padL + plotW,
        pinY: cy,
        width: 0.02,
        height: barH * 1.4,
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              MoveTo(0.01, 0),
              LineTo(0.01, barH * 1.4),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(
          color: VsdxColor(0xFFE53935),
          weightInches: 0.012,
        ),
        userCells: _chromeMeta,
      ));
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: padL * 0.5,
        pinY: cy,
        width: padL * 0.9,
        height: rowH * 0.7,
        text: labs[i],
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: labs[i],
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.07,
              color: VsdxColor(0xFF424242),
            ),
            paraStyle: const VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.right,
            ),
          ),
        ]),
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            noLine: true,
            commands: <VsdxPathCommand>[
              const MoveTo(0, 0),
              LineTo(0.4, 0),
              LineTo(0.4, 0.2),
              LineTo(0, 0.2),
              const LineTo(0, 0),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
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
      kind: 'quotaBoard',
      values: stored,
      labels: labs,
    );
  }

  /// Tick ladder: rows of discrete tick marks filled by value.
  static VsdxShape tickLadderChart({
    required int id,
    required double pinX,
    required double pinY,
    double width = 2.6,
    double height = 1.5,
    List<double>? values,
    List<String>? labels,
    int Function()? allocId,
  }) {
    final raw = values ?? _defaultValuesForKind('tickLadder', null);
    final vals = <double>[for (final v in raw) v.clamp(0.0, 1.0)];
    final n = math.max(1, vals.length);
    final labs = padLabels(labels ?? defaultLabels(n), n);
    final w = width.abs();
    final h = height.abs();
    final next = _seq(id + 1, allocId);
    const ticks = 10;
    final pad = h * 0.08;
    final gap = h * 0.08;
    final rowH = (h - pad * 2 - gap * (n - 1)) / n;
    final kids = <VsdxShape>[];
    for (var i = 0; i < n; i++) {
      final cy = h - pad - rowH / 2 - i * (rowH + gap);
      final filled = (vals[i] * ticks).round().clamp(0, ticks);
      kids.add(VsdxShape(
        id: next(),
        name: _sheetName(id),
        pinX: w * 0.16,
        pinY: cy,
        width: w * 0.28,
        height: rowH * 0.7,
        text: labs[i],
        richText: VsdxRichText(runs: <VsdxTextRun>[
          VsdxTextRun(
            text: labs[i],
            charStyle: const VsdxCharStyle(
              fontSizeInches: 0.07,
              color: VsdxColor(0xFF424242),
            ),
            paraStyle: const VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.right,
            ),
          ),
        ]),
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            noLine: true,
            commands: <VsdxPathCommand>[
              const MoveTo(0, 0),
              LineTo(0.35, 0),
              LineTo(0.35, 0.2),
              LineTo(0, 0.2),
              const LineTo(0, 0),
            ],
          ),
        ],
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
        userCells: _chromeMeta,
      ));
      final startX = w * 0.36;
      final tickW = w * 0.04;
      final tickGap = w * 0.018;
      final tickH = rowH * 0.5;
      for (var t = 0; t < ticks; t++) {
        final on = t < filled;
        kids.add(_rectChild(
          id: next(),
          pinX: startX + tickW / 2 + t * (tickW + tickGap),
          pinY: cy,
          width: tickW,
          height: tickH,
          fill: on
              ? seriesColors[i % seriesColors.length]
              : const VsdxColor(0xFFE0E0E0),
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
      kind: 'tickLadder',
      values: vals,
      labels: labs,
    );
  }

}
