import 'package:test/test.dart';
import 'package:vsdx/agent.dart';
import 'package:vsdx/stencils.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('chart stencils build groups with series children and meta', () {
    expect(kChartStencils, hasLength(101));
    for (final s in kChartStencils) {
      final shape = s.build(1, 4, 5);
      expect(shape.shapeKind, VsdxShapeKind.group, reason: s.name);
      expect(shape.children, isNotEmpty, reason: s.name);
      expect(shape.connectionPoints, isNotEmpty, reason: s.name);
      expect(ChartOps.isChart(shape), isTrue, reason: s.name);
      expect(ChartOps.chartKind(shape), isNotNull, reason: s.name);
      expect(ChartOps.chartValues(shape), isNotEmpty, reason: s.name);
    }
  });

  test('axes form bottom-left L in Y-up local space', () {
    final chart = ChartOps.columnChart(id: 1, pinX: 2, pinY: 2);
    final axes = chart.children.firstWhere(ChartOps.isChartChrome);
    final cmds = axes.geometries.first.commands;
    expect(cmds, hasLength(3));
    final m = cmds[0] as MoveTo;
    final a = cmds[1] as LineTo;
    final b = cmds[2] as LineTo;
    // Top of Y axis → origin → right along X axis (└).
    expect(m.y, greaterThan(a.y));
    expect(a.x, closeTo(m.x, 1e-9));
    expect(b.y, closeTo(a.y, 1e-9));
    expect(b.x, greaterThan(a.x));
  });

  test('chart shapes use Sheet.N names so painter skips name labels', () {
    final autoName = RegExp(r'^Sheet\.\d+$');
    for (final s in kChartStencils) {
      final shape = s.build(7, 4, 5);
      final kind = ChartOps.chartKind(shape);
      final allowCellText = kind == 'dataTable' ||
          kind == 'scorecard' ||
          kind == 'processSteps' ||
          kind == 'venn' ||
          kind == 'ranking' ||
          kind == 'statusBoard' ||
          kind == 'likert' ||
          kind == 'arcGauge' ||
          kind == 'progressList' ||
          kind == 'milestone' ||
          kind == 'balanceBar' ||
          kind == 'meterCluster' ||
          kind == 'priorityMatrix' ||
          kind == 'cycleFlow' ||
          kind == 'checkboxList' ||
          kind == 'gapAnalysis' ||
          kind == 'stageFunnel' ||
          kind == 'rhythmBars' ||
          kind == 'voteStack' ||
          kind == 'trafficRow' ||
          kind == 'starRating' ||
          kind == 'compareCards' ||
          kind == 'pipeline' ||
          kind == 'winLossStrip' ||
          kind == 'quotaBoard' ||
          kind == 'tickLadder';
      void check(VsdxShape node, {required bool isRoot}) {
        expect(autoName.hasMatch(node.name), isTrue,
            reason: '${s.name} id=${node.id} name=${node.name}');
        if (isRoot || !allowCellText) {
          expect(node.text, isNull, reason: '${s.name} id=${node.id}');
        }
        for (final c in node.children) {
          check(c, isRoot: false);
        }
      }

      check(shape, isRoot: true);
    }
  });

  test('pie slices use tight AABB (not full chart frame)', () {
    final pie = ChartOps.pieChart(id: 5, pinX: 3, pinY: 3, width: 2, height: 2);
    for (final slice in pie.children) {
      expect(slice.width, lessThan(pie.width * 0.95), reason: slice.name);
      expect(slice.height, lessThan(pie.height * 0.95), reason: slice.name);
    }
  });

  test('rebuild preserves root id and updates ChartValues', () {
    final chart = ChartOps.columnChart(
      id: 10,
      pinX: 1,
      pinY: 2,
      values: const <double>[1, 2, 3],
    );
    var next = 100;
    final rebuilt = ChartOps.rebuild(
      chart,
      values: const <double>[0.2, 0.4, 0.6, 0.8],
      allocId: () => next++,
    );
    expect(rebuilt.id, 10);
    expect(rebuilt.pinX, 1);
    expect(rebuilt.pinY, 2);
    expect(ChartOps.chartKind(rebuilt), 'column');
    expect(ChartOps.chartValues(rebuilt), <double>[0.2, 0.4, 0.6, 0.8]);
    expect(rebuilt.children.length, greaterThan(chart.children.length - 1));
    for (final c in rebuilt.children) {
      expect(c.id, greaterThanOrEqualTo(100));
    }
  });

  test('rebuild preserves custom series colours in userCells', () {
    final chart = ChartOps.columnChart(
      id: 10,
      pinX: 1,
      pinY: 2,
      values: const <double>[1, 2, 3],
    );
    var next = 100;
    final colored = ChartOps.rebuild(
      chart,
      values: const <double>[1, 2, 3],
      colors: const <VsdxColor>[
        VsdxColor(0xFFE53935),
        VsdxColor(0xFF43A047),
        VsdxColor(0xFF1E88E5),
      ],
      labels: const <String>['A', 'B', 'C'],
      allocId: () => next++,
    );
    expect(ChartOps.formatColors(ChartOps.chartColors(colored)),
        '#E53935, #43A047, #1E88E5');
    expect(ChartOps.chartLabels(colored), <String>['A', 'B', 'C']);
    final series = ChartOps.seriesChildren(colored);
    expect(series, hasLength(3));
    expect(series[0].fill.foreground?.value, 0xFFE53935);
    expect(series[1].fill.foreground?.value, 0xFF43A047);
  });

  test('switching to gauge stashes values and restores on switch back', () {
    final chart = ChartOps.columnChart(
      id: 3,
      pinX: 1,
      pinY: 1,
      values: const <double>[0.2, 0.4, 0.6, 0.8],
    );
    var next = 50;
    final gauge = ChartOps.rebuild(
      chart,
      kind: 'gauge',
      allocId: () => next++,
    );
    expect(ChartOps.chartKind(gauge), 'gauge');
    expect(ChartOps.chartValues(gauge), hasLength(1));
    next = 80;
    final back = ChartOps.rebuild(
      gauge,
      kind: 'column',
      allocId: () => next++,
    );
    expect(ChartOps.chartKind(back), 'column');
    expect(ChartOps.chartValues(back), <double>[0.2, 0.4, 0.6, 0.8]);
  });

  test('new multi-value kinds rebuild and keep item colours', () {
    for (final kind in <String>[
      'lollipop',
      'semiDonut',
      'rose',
      'stepLine',
      'radialBar',
      'clusteredBar',
      'histogram',
      'horizontalLollipop',
      'divergingBar',
      'dotPlot',
      'compositionBar',
      'treemap',
      'cylinder',
      'cone',
      'stepArea',
      'percentColumn',
      'packedBubble',
      'sparkColumn',
      'triangleBar',
      'mirrorColumn',
      'pareto',
      'radialColumn',
      'horizontalCylinder',
      'sparkWinLoss',
      'tornado',
      'sparkLine',
      'sparkArea',
      'nightingale',
      'variableColumn',
      'pillBar',
      'arrowBar',
      'diamondLollipop',
      'chevron',
      'polarLine',
    ]) {
      final chart = ChartOps.buildKind(
        kind,
        id: 11,
        pinX: 1,
        pinY: 1,
        values: const <double>[0.3, 0.5, 0.7],
      );
      expect(ChartOps.chartKind(chart), kind);
      var next = 200;
      final rebuilt = ChartOps.rebuild(
        chart,
        values: const <double>[0.2, 0.4, 0.6, 0.8],
        colors: const <VsdxColor>[
          VsdxColor(0xFFE53935),
          VsdxColor(0xFF43A047),
          VsdxColor(0xFF1E88E5),
          VsdxColor(0xFFFFC000),
        ],
        labels: const <String>['A', 'B', 'C', 'D'],
        allocId: () => next++,
      );
      expect(ChartOps.chartValues(rebuilt), hasLength(4), reason: kind);
      expect(ChartOps.chartLabels(rebuilt), <String>['A', 'B', 'C', 'D'],
          reason: kind);
    }
  });

  test('ringProgress is a single-value kind with backup restore', () {
    final chart = ChartOps.columnChart(
      id: 9,
      pinX: 1,
      pinY: 1,
      values: const <double>[0.2, 0.4, 0.6],
    );
    var next = 30;
    final ring = ChartOps.rebuild(
      chart,
      kind: 'ringProgress',
      allocId: () => next++,
    );
    expect(ChartOps.isSingleValueKind('ringProgress'), isTrue);
    expect(ChartOps.chartValues(ring), hasLength(1));
    next = 60;
    final back = ChartOps.rebuild(
      ring,
      kind: 'lollipop',
      allocId: () => next++,
    );
    expect(ChartOps.chartKind(back), 'lollipop');
    expect(ChartOps.chartValues(back), <double>[0.2, 0.4, 0.6]);
  });

  test('bullet is a single-value kind', () {
    final chart = ChartOps.bulletChart(id: 2, pinX: 1, pinY: 1);
    expect(ChartOps.isSingleValueKind('bullet'), isTrue);
    expect(ChartOps.chartValues(chart), hasLength(1));
    expect(ChartOps.seriesChildren(chart), hasLength(1));
  });

  test('thermometer and waffle are single-value meters', () {
    expect(ChartOps.isSingleValueKind('thermometer'), isTrue);
    expect(ChartOps.isSingleValueKind('waffle'), isTrue);
    final t = ChartOps.thermometerChart(id: 3, pinX: 1, pinY: 1);
    final w = ChartOps.waffleChart(id: 4, pinX: 2, pinY: 1);
    expect(ChartOps.chartValues(t), hasLength(1));
    expect(ChartOps.chartValues(w), hasLength(1));
    expect(ChartOps.seriesChildren(w), isNotEmpty);
  });

  test('battery and trafficLight are single-value meters', () {
    expect(ChartOps.isSingleValueKind('battery'), isTrue);
    expect(ChartOps.isSingleValueKind('trafficLight'), isTrue);
    final b = ChartOps.batteryChart(id: 5, pinX: 1, pinY: 1);
    final t = ChartOps.trafficLightChart(id: 6, pinX: 2, pinY: 1);
    expect(ChartOps.chartValues(b), hasLength(1));
    expect(ChartOps.seriesChildren(b), hasLength(1));
    expect(ChartOps.seriesChildren(t), hasLength(1));
  });

  test('semiProgress and stepProgress are single-value meters', () {
    expect(ChartOps.isSingleValueKind('semiProgress'), isTrue);
    expect(ChartOps.isSingleValueKind('stepProgress'), isTrue);
    final s = ChartOps.semiProgressChart(id: 7, pinX: 1, pinY: 1);
    final p = ChartOps.stepProgressChart(id: 8, pinX: 2, pinY: 1);
    expect(ChartOps.chartValues(s), hasLength(1));
    expect(ChartOps.chartValues(p), hasLength(1));
  });

  test('parseSeriesPaste supports labeled pairs', () {
    final parsed = ChartOps.parseSeriesPaste('North: 10, South: 20; East: 5');
    expect(parsed.values, <double>[10, 20, 5]);
    expect(parsed.labels, <String>['North', 'South', 'East']);
  });

  test('parseUnitValue accepts percent and fractions', () {
    expect(ChartOps.parseUnitValue('68%'), closeTo(0.68, 1e-9));
    expect(ChartOps.parseUnitValue('68'), closeTo(0.68, 1e-9));
    expect(ChartOps.parseUnitValue('0.45'), closeTo(0.45, 1e-9));
  });

  test('rebuild attaches category legend labels on canvas', () {
    final chart = ChartOps.columnChart(
      id: 4,
      pinX: 1,
      pinY: 1,
      values: const <double>[1, 2, 3],
    );
    var next = 40;
    final labeled = ChartOps.rebuild(
      chart,
      values: const <double>[1, 2, 3],
      labels: const <String>['Alpha', 'Beta', 'Gamma'],
      allocId: () => next++,
    );
    final legends = labeled.children.where(ChartOps.isLegend).toList();
    expect(legends, hasLength(3));
    expect(legends.map((s) => s.text).toList(), <String>['Alpha', 'Beta', 'Gamma']);
  });

  test('parseValues accepts negatives for waterfall', () {
    expect(ChartOps.parseValues('0.4, -0.2, 0.3'), <double>[0.4, -0.2, 0.3]);
  });

  test('parseValues accepts commas semicolons and whitespace', () {
    expect(ChartOps.parseValues('1, 2;3  4.5'), <double>[1, 2, 3, 4.5]);
    expect(ChartOps.parseValues(''), ChartOps.defaultValues);
  });


  test('new chart kinds round-trip through vsdx writer', () {
    const writer = VsdxWriter();
    const parser = DocumentParser();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    final builders = <VsdxShape Function(int id)>[
      (id) => ChartOps.stackedBarChart(id: id, pinX: 1, pinY: 1),
      (id) => ChartOps.clusteredColumnChart(id: id, pinX: 3, pinY: 1),
      (id) => ChartOps.pyramidChart(id: id, pinX: 5, pinY: 1),
      (id) => ChartOps.progressChart(id: id, pinX: 1, pinY: 3),
      (id) => ChartOps.waterfallChart(id: id, pinX: 3, pinY: 3),
      (id) => ChartOps.bubbleChart(id: id, pinX: 5, pinY: 3),
      (id) => ChartOps.gaugeChart(id: id, pinX: 2, pinY: 5),
      (id) => ChartOps.lollipopChart(id: id, pinX: 4, pinY: 5),
      (id) => ChartOps.semiDonutChart(id: id, pinX: 6, pinY: 5),
      (id) => ChartOps.roseChart(id: id, pinX: 1, pinY: 7),
      (id) => ChartOps.stepLineChart(id: id, pinX: 3, pinY: 7),
      (id) => ChartOps.radialBarChart(id: id, pinX: 5, pinY: 7),
      (id) => ChartOps.ringProgressChart(id: id, pinX: 7, pinY: 7),
      (id) => ChartOps.clusteredBarChart(id: id, pinX: 2, pinY: 9),
    ];
    var id = 20;
    for (final b in builders) {
      page = page.addShape(b(id));
      id += 20;
    }
    doc = doc.replacePage(0, page);
    final out = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(out).pages.first;
    for (var i = 20; i < id; i += 20) {
      final loaded = after.findShapeById(i);
      expect(loaded, isNotNull, reason: 'id=$i');
      expect(ChartOps.isChart(loaded!), isTrue, reason: 'id=$i');
      expect(loaded.children, isNotEmpty, reason: 'id=$i');
      expect(ChartOps.chartValues(loaded), isNotEmpty, reason: 'id=$i');
    }
    expect(validateDocument(parser.parse(out)).where((i) => i.severity == 'error'),
        isEmpty);
  });

  test('column chart round-trips through vsdx writer', () {
    const writer = VsdxWriter();
    const parser = DocumentParser();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final chart = ChartOps.columnChart(id: 10, pinX: 3, pinY: 4);
    doc = doc.replacePage(0, doc.pages.first.addShape(chart));
    final out = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(out);
    final loaded = after.pages.first.findShapeById(10);
    expect(loaded, isNotNull);
    expect(loaded!.shapeKind, VsdxShapeKind.group);
    expect(loaded.children.length, chart.children.length);
    expect(ChartOps.isChart(loaded), isTrue);
    expect(ChartOps.chartKind(loaded), 'column');
    expect(loaded.connectionPoints, isNotEmpty);
    expect(validateDocument(after).where((i) => i.severity == 'error'), isEmpty);
  });

  test('specialty charts use custom editor kinds and rebuild', () {
    for (final kind in ChartOps.customEditorKinds) {
      expect(ChartOps.isCustomEditorKind(kind), isTrue);
      final chart = ChartOps.buildKind(kind, id: 21, pinX: 1, pinY: 1);
      expect(ChartOps.chartKind(chart), kind);
      expect(ChartOps.chartValues(chart), isNotEmpty);
      var next = 300;
      final rebuilt = ChartOps.rebuild(
        chart,
        values: List<double>.of(ChartOps.chartValues(chart)),
        allocId: () => next++,
      );
      expect(ChartOps.chartKind(rebuilt), kind);
      expect(rebuilt.children, isNotEmpty);
    }
    final heat = ChartOps.heatmapChart(id: 2, pinX: 1, pinY: 1);
    expect(ChartOps.chartExtras(heat), '3x4');
    var next = 400;
    final resized = ChartOps.rebuild(
      heat,
      extras: '2x3',
      allocId: () => next++,
    );
    expect(ChartOps.chartExtras(resized), '2x3');
    expect(ChartOps.chartValues(resized), hasLength(6));
  });

  test('data table respects grid extras and cell labels', () {
    final table = ChartOps.dataTableChart(
      id: 5,
      pinX: 1,
      pinY: 1,
      extras: '3x2;header=1;borders=1;zebra=1',
      labels: const <String>['A', 'B', '1', '2', '3', '4'],
    );
    expect(ChartOps.chartKind(table), 'dataTable');
    expect(ChartOps.isCustomEditorKind('dataTable'), isTrue);
    expect(ChartOps.chartExtras(table), contains('3x2'));
    expect(ChartOps.chartLabels(table, 6), hasLength(6));
    expect(ChartOps.seriesChildren(table), hasLength(6));
    var next = 500;
    final rebuilt = ChartOps.rebuild(
      table,
      extras: '2x2;header=0;borders=0;zebra=0',
      labels: const <String>['w', 'x', 'y', 'z'],
      colors: const <VsdxColor>[
        VsdxColor(0xFFE53935),
        VsdxColor(0xFFFFFFFF),
        VsdxColor(0xFFEEEEEE),
      ],
      allocId: () => next++,
    );
    expect(ChartOps.parseTableGrid(ChartOps.chartExtras(rebuilt)).$1, 2);
    expect(ChartOps.parseTableFlag(ChartOps.chartExtras(rebuilt), 'header'),
        isFalse);
    expect(ChartOps.seriesChildren(rebuilt), hasLength(4));
  });

  test('pie and line charts round-trip', () {
    const writer = VsdxWriter();
    const parser = DocumentParser();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    page = page.addShape(ChartOps.pieChart(id: 20, pinX: 2, pinY: 2));
    page = page.addShape(ChartOps.lineChart(id: 40, pinX: 5, pinY: 2));
    doc = doc.replacePage(0, page);
    final out = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(out).pages.first;
    expect(after.findShapeById(20)!.children, isNotEmpty);
    expect(ChartOps.isChart(after.findShapeById(20)!), isTrue);
    expect(after.findShapeById(40)!.children, isNotEmpty);
  });
}
