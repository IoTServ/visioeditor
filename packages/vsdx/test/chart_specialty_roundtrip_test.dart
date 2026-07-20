import 'package:test/test.dart';
import 'package:vsdx/agent.dart';
import 'package:vsdx/vsdx.dart';

/// Round-trip specialty charts through rebuild + VSDX write/read.
void main() {
  const writer = VsdxWriter();
  const parser = DocumentParser();

  List<double> _mutatedValues(String kind, List<double> original) {
    switch (kind) {
      case 'candlestick':
        return <double>[
          0.41, 0.72, 0.31, 0.58,
          0.52, 0.81, 0.44, 0.61,
        ];
      case 'gantt':
      case 'slope':
      case 'rangeBar':
      case 'dumbbell':
      case 'quadrant':
      case 'spanColumn':
      case 'bulletGroup':
      case 'dualCompare':
      case 'balanceBar':
      case 'gapAnalysis':
      case 'quotaBoard':
        return <double>[
          for (var i = 0; i < 4; i++) ...[0.12 + i * 0.08, 0.35 + i * 0.05],
        ];
      case 'boxplot':
        return const <double>[0.1, 0.3, 0.5, 0.7, 0.9];
      case 'heatmap':
        return const <double>[0.14, 0.28, 0.42, 0.57, 0.71, 0.85];
      case 'calendarHeat':
        return List<double>.generate(21, (i) => ((i % 5) + 1) * 0.15);
      case 'dataTable':
        return List<double>.filled(6, 1);
      case 'kpiTarget':
      case 'arcGauge':
        return const <double>[0.66, 0.88];
      case 'venn':
        return const <double>[0.42, 0.38, 0.18];
      case 'likert':
        return const <double>[0.1, 0.15, 0.25, 0.3, 0.2];
      case 'voteStack':
        return const <double>[0.45, 0.35, 0.2];
      case 'priorityMatrix':
        return const <double>[0.8, 0.6, 0.4, 0.2];
      case 'compareCards':
        return const <double>[0.7, 0.55];
      case 'nestedDonut':
        return const <double>[0.2, 0.25, 0.15, 0.2, 0.1, 0.1];
      case 'radialMulti':
        return const <double>[0.7, 0.5, 0.35];
      case 'heatStrip':
        return const <double>[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8];
      case 'winLossStrip':
      case 'checkboxList':
        return const <double>[1, 0, 1, 0];
      case 'processSteps':
      case 'trafficRow':
      case 'statusBoard':
        return const <double>[1, 0.5, 0, 1];
      default:
        return <double>[
          for (var i = 0; i < original.length.clamp(1, 6); i++)
            0.15 + i * 0.12,
        ];
    }
  }

  String? _mutatedExtras(String kind) {
    switch (kind) {
      case 'heatmap':
        return ChartOps.formatHeatmapGrid(2, 3);
      case 'calendarHeat':
        return ChartOps.formatCalendarWeeks(3);
      case 'dataTable':
        return ChartOps.formatTableExtras(
          rows: 3,
          cols: 2,
          header: true,
          borders: true,
          zebra: true,
        );
      case 'nestedDonut':
        return ChartOps.formatNestedInner(2);
      case 'heatStrip':
        return ChartOps.formatHeatStripCells(8);
      case 'scorecard':
      case 'statusBoard':
        return ChartOps.formatScorecardCols(2);
      default:
        return null;
    }
  }

  List<String>? _mutatedLabels(String kind, List<double> values, String? extras) {
    final n = ChartOps.logicalSeriesCount(kind, values, extras);
    switch (kind) {
      case 'dataTable':
        return List<String>.generate(n, (i) => 'C$i');
      case 'gantt':
      case 'timeline':
      case 'milestone':
      case 'processSteps':
      case 'ranking':
      case 'progressList':
      case 'checkboxList':
      case 'statusBoard':
      case 'trafficRow':
        return List<String>.generate(n, (i) => 'L$i');
      case 'venn':
        return const <String>['A', 'B', 'A∩B'];
      case 'kpiTarget':
        return const <String>['KPI'];
      case 'likert':
        return const <String>['SD', 'D', 'N', 'A', 'SA'];
      case 'voteStack':
        return const <String>['Yes', 'No', 'Abs'];
      case 'priorityMatrix':
        return const <String>['Q1', 'Q2', 'Q3', 'Q4'];
      case 'compareCards':
        return const <String>['Left', 'Right'];
      case 'slope':
      case 'rangeBar':
      case 'dumbbell':
      case 'quadrant':
      case 'spanColumn':
      case 'bulletGroup':
      case 'dualCompare':
      case 'balanceBar':
      case 'gapAnalysis':
      case 'quotaBoard':
        return List<String>.generate(n, (i) => 'S$i');
      default:
        return List<String>.generate(n, (i) => 'Item$i');
    }
  }

  test('every specialty kind rebuilds with mutated data', () {
    for (final kind in ChartOps.customEditorKinds) {
      final chart = ChartOps.buildKind(kind, id: 21, pinX: 1.5, pinY: 2.5);
      final original = ChartOps.chartValues(chart);
      final values = _mutatedValues(kind, original);
      final extras = _mutatedExtras(kind) ?? ChartOps.chartExtras(chart);
      final labels = _mutatedLabels(kind, values, extras);
      var next = 500;
      final rebuilt = ChartOps.rebuild(
        chart,
        values: values,
        labels: labels,
        extras: extras,
        allocId: () => next++,
      );
      expect(rebuilt.id, 21, reason: kind);
      expect(rebuilt.pinX, 1.5, reason: kind);
      expect(rebuilt.pinY, 2.5, reason: kind);
      expect(ChartOps.chartKind(rebuilt), kind);
      expect(ChartOps.isChart(rebuilt), isTrue, reason: kind);
      expect(rebuilt.children, isNotEmpty, reason: kind);
      final gotVals = ChartOps.chartValues(rebuilt);
      expect(gotVals.length, values.length, reason: kind);
      for (var i = 0; i < values.length; i++) {
        expect(gotVals[i], closeTo(values[i], 1e-6), reason: '$kind[$i]');
      }
      if (extras != null && extras.isNotEmpty) {
        expect(ChartOps.chartExtras(rebuilt), extras, reason: kind);
      }
      if (labels != null) {
        final n = ChartOps.logicalSeriesCount(kind, gotVals, extras);
        final gotLabs = ChartOps.chartLabels(rebuilt, n);
        expect(gotLabs.take(labels.length).toList(), labels,
            reason: '$kind labels');
      }
    }
  });

  test('specialty charts round-trip through vsdx writer', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;

    final expected = <int, ({String kind, List<double> values, String? extras, List<String>? labels})>{};
    var id = 100;
    for (final kind in ChartOps.customEditorKinds) {
      final chart0 = ChartOps.buildKind(
        kind,
        id: id,
        pinX: 1 + (id % 7) * 0.1,
        pinY: 1 + (id % 5) * 0.1,
      );
      final values = _mutatedValues(kind, ChartOps.chartValues(chart0));
      final extras = _mutatedExtras(kind) ?? ChartOps.chartExtras(chart0);
      final labels = _mutatedLabels(kind, values, extras);
      var next = id + 1;
      final chart = ChartOps.rebuild(
        chart0,
        values: values,
        labels: labels,
        extras: extras,
        allocId: () => next++,
      );
      page = page.addShape(chart);
      expected[id] = (
        kind: kind,
        values: values,
        extras: extras,
        labels: labels,
      );
      id += 40;
    }
    doc = doc.replacePage(0, page);
    final out = writer.write(originalBytes: blank, edited: doc);
    final afterDoc = parser.parse(out);
    expect(
      validateDocument(afterDoc).where((i) => i.severity == 'error'),
      isEmpty,
    );
    final after = afterDoc.pages.first;
    for (final entry in expected.entries) {
      final loaded = after.findShapeById(entry.key);
      expect(loaded, isNotNull, reason: entry.value.kind);
      expect(ChartOps.isChart(loaded!), isTrue, reason: entry.value.kind);
      expect(ChartOps.chartKind(loaded), entry.value.kind);
      expect(loaded.children, isNotEmpty, reason: entry.value.kind);
      final gotVals = ChartOps.chartValues(loaded);
      expect(gotVals.length, entry.value.values.length,
          reason: entry.value.kind);
      for (var i = 0; i < entry.value.values.length; i++) {
        expect(
          gotVals[i],
          closeTo(entry.value.values[i], 1e-4),
          reason: '${entry.value.kind}[$i]',
        );
      }
      if (entry.value.extras != null && entry.value.extras!.isNotEmpty) {
        expect(
          ChartOps.chartExtras(loaded),
          entry.value.extras,
          reason: entry.value.kind,
        );
      }
      if (entry.value.labels != null) {
        final n = ChartOps.logicalSeriesCount(
          entry.value.kind,
          gotVals,
          entry.value.extras,
        );
        final gotLabs = ChartOps.chartLabels(loaded, n);
        expect(
          gotLabs.take(entry.value.labels!.length).toList(),
          entry.value.labels,
          reason: '${entry.value.kind} labels',
        );
      }
    }
  });

  test('shared chart kinds also survive write/read after rebuild', () {
    final kinds = <String>[
      'column',
      'bar',
      'pie',
      'donut',
      'line',
      'area',
      'stackedColumn',
      'waterfall',
      'gauge',
      'ringProgress',
    ];
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    var id = 10;
    final expected = <int, String>{};
    for (final kind in kinds) {
      final chart0 = ChartOps.buildKind(kind, id: id, pinX: 2, pinY: 2);
      var next = id + 1;
      final chart = ChartOps.rebuild(
        chart0,
        values: ChartOps.isSingleValueKind(kind)
            ? const <double>[0.73]
            : const <double>[0.2, 0.35, 0.45, 0.55],
        allocId: () => next++,
      );
      page = page.addShape(chart);
      expected[id] = kind;
      id += 30;
    }
    doc = doc.replacePage(0, page);
    final out = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(out).pages.first;
    for (final e in expected.entries) {
      final loaded = after.findShapeById(e.key)!;
      expect(ChartOps.chartKind(loaded), e.value);
      expect(ChartOps.chartValues(loaded), isNotEmpty);
    }
  });
}
