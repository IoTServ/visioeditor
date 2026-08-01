import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/chart_config_panel.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  EditorController chartController(VsdxShape Function(int, double, double) build) {
    final controller = EditorController()..newDocument();
    controller.addShapeFromBuilderAt(build, 3, 3);
    return controller;
  }

  test('chart item edits preserve palette order and skip no-op rebuilds', () {
    final controller = chartController(
      (id, x, y) => ChartOps.columnChart(id: id, pinX: x, pinY: y),
    );
    addTearDown(controller.dispose);

    controller.addChartItem(label: 'Extra');
    var chart = controller.selectedChart!;
    expect(ChartOps.chartValues(chart), hasLength(5));
    expect(ChartOps.chartLabels(chart).last, 'Extra');
    expect(ChartOps.chartColors(chart), hasLength(5));
    expect(ChartOps.chartColors(chart).last, ChartOps.seriesColors[4]);

    final afterAdd = controller.document;
    final first = ChartOps.chartValues(chart).first;
    controller.updateChartItem(0, value: first);
    expect(identical(controller.document, afterAdd), isTrue);

    controller.undo();
    chart = controller.selectedChart!;
    expect(ChartOps.chartValues(chart), hasLength(4));
  });

  test('removing a chart item preserves repeated authored colours', () {
    const authored = VsdxColor(0xFF123456);
    final controller = chartController((id, x, y) {
      final chart = ChartOps.columnChart(id: id, pinX: x, pinY: y);
      return chart.copyWith(
        userCells: <VsdxUserCell>[
          for (final cell in chart.userCells)
            if (cell.name != ChartOps.userColors) cell,
          const VsdxUserCell(name: ChartOps.userColors, value: '#123456'),
        ],
      );
    });
    addTearDown(controller.dispose);

    controller.removeChartItem(0);
    final chart = controller.selectedChart!;

    expect(ChartOps.chartValues(chart), hasLength(3));
    expect(ChartOps.chartColors(chart), <VsdxColor>[authored, authored, authored]);
  });

  test('chart edits survive VSDX reopen and SVG display output', () {
    const custom = VsdxColor(0xFF7B1FA2);
    final controller = chartController(
      (id, x, y) => ChartOps.columnChart(id: id, pinX: x, pinY: y),
    );
    addTearDown(controller.dispose);
    final id = controller.selectedChartId!;

    controller.updateChartItem(
      0,
      value: 0.33,
      color: custom,
      label: 'North',
    );
    controller.reorderChartItem(0, 2);
    controller.setChartKind('pie');
    final edited = controller.selectedChart!;
    final values = ChartOps.chartValues(edited);
    final colors = ChartOps.chartColors(edited);
    final labels = ChartOps.chartLabels(edited, values.length);

    final reopened = const DocumentParser().parse(controller.exportToBytes());
    final restored = reopened.pages.single.findShapeById(id)!;
    expect(ChartOps.chartKind(restored), 'pie');
    expect(ChartOps.chartValues(restored), values);
    expect(ChartOps.chartColors(restored), colors);
    expect(ChartOps.chartLabels(restored, values.length), labels);

    final svg = VsdxToSvgSerializer().serializePage(
      reopened.pages.single,
      theme: reopened.theme,
      images: reopened.images,
    );
    expect(svg.toUpperCase(), contains('#7B1FA2'));
    expect(svg, contains('North'));
  });

  testWidgets('invalid single-value chart input restores the prior value', (
    tester,
  ) async {
    final controller = chartController(
      (id, x, y) => ChartOps.gaugeChart(id: id, pinX: x, pinY: y),
    );
    addTearDown(controller.dispose);
    final before = controller.document;
    final value = ChartOps.chartValues(controller.selectedChart!).single;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChartConfigPanel(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '%');
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(ChartOps.chartValues(controller.selectedChart!).single, value);
    expect(identical(controller.document, before), isTrue);
    expect(find.text(ChartOps.formatPercent(value)), findsOneWidget);
  });
}
