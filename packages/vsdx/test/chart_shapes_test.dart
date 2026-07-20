import 'package:test/test.dart';
import 'package:vsdx/agent.dart';
import 'package:vsdx/stencils.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('chart stencils build groups with series children and meta', () {
    expect(kChartStencils, hasLength(16));
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
      void check(VsdxShape node) {
        expect(autoName.hasMatch(node.name), isTrue,
            reason: '${s.name} id=${node.id} name=${node.name}');
        expect(node.text, isNull, reason: '${s.name} id=${node.id}');
        for (final c in node.children) {
          check(c);
        }
      }

      check(shape);
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

  test('parseUnitValue accepts percent and fractions', () {
    expect(ChartOps.parseUnitValue('68%'), closeTo(0.68, 1e-9));
    expect(ChartOps.parseUnitValue('68'), closeTo(0.68, 1e-9));
    expect(ChartOps.parseUnitValue('0.45'), closeTo(0.45, 1e-9));
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
