/// Charts palette — draw.io / 万兴图示 style chart stencils.
library;

import 'package:vsdx/vsdx.dart';

import 'stencils.dart';

/// Chart libraries shown in the dedicated Charts sidebar.
final List<StencilGroup> kChartStencilGroups = <StencilGroup>[
  StencilGroup('Charts', <Stencil>[
    Stencil(
      'Column Chart',
      (id, cx, cy) => ChartOps.columnChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Bar Chart',
      (id, cx, cy) => ChartOps.barChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Stacked Column',
      (id, cx, cy) => ChartOps.stackedColumnChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Stacked Bar',
      (id, cx, cy) => ChartOps.stackedBarChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Clustered Column',
      (id, cx, cy) =>
          ChartOps.clusteredColumnChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Clustered Bar',
      (id, cx, cy) => ChartOps.clusteredBarChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Lollipop Chart',
      (id, cx, cy) => ChartOps.lollipopChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Horizontal Lollipop',
      (id, cx, cy) =>
          ChartOps.horizontalLollipopChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Diamond Lollipop',
      (id, cx, cy) =>
          ChartOps.diamondLollipopChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Histogram',
      (id, cx, cy) => ChartOps.histogramChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Cylinder Chart',
      (id, cx, cy) => ChartOps.cylinderChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Horizontal Cylinder',
      (id, cx, cy) =>
          ChartOps.horizontalCylinderChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Cone Chart',
      (id, cx, cy) => ChartOps.coneChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Variable Column',
      (id, cx, cy) => ChartOps.variableColumnChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Pill Bar',
      (id, cx, cy) => ChartOps.pillBarChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Arrow Bar',
      (id, cx, cy) => ChartOps.arrowBarChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Spark Column',
      (id, cx, cy) => ChartOps.sparkColumnChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Spark Win/Loss',
      (id, cx, cy) => ChartOps.sparkWinLossChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Triangle Bar',
      (id, cx, cy) => ChartOps.triangleBarChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Mirror Column',
      (id, cx, cy) => ChartOps.mirrorColumnChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Tornado Chart',
      (id, cx, cy) => ChartOps.tornadoChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Pareto Chart',
      (id, cx, cy) => ChartOps.paretoChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Diverging Bar',
      (id, cx, cy) => ChartOps.divergingBarChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Dot Plot',
      (id, cx, cy) => ChartOps.dotPlotChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Composition Bar',
      (id, cx, cy) =>
          ChartOps.compositionBarChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Percent Column',
      (id, cx, cy) => ChartOps.percentColumnChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Treemap',
      (id, cx, cy) => ChartOps.treemapChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Packed Bubble',
      (id, cx, cy) => ChartOps.packedBubbleChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Pie Chart',
      (id, cx, cy) => ChartOps.pieChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Donut Chart',
      (id, cx, cy) => ChartOps.donutChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Semi Donut',
      (id, cx, cy) => ChartOps.semiDonutChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Rose Chart',
      (id, cx, cy) => ChartOps.roseChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Nightingale Chart',
      (id, cx, cy) => ChartOps.nightingaleChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Line Chart',
      (id, cx, cy) => ChartOps.lineChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Step Line',
      (id, cx, cy) => ChartOps.stepLineChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Area Chart',
      (id, cx, cy) => ChartOps.areaChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Step Area',
      (id, cx, cy) => ChartOps.stepAreaChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Spark Line',
      (id, cx, cy) => ChartOps.sparkLineChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Spark Area',
      (id, cx, cy) => ChartOps.sparkAreaChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Funnel',
      (id, cx, cy) => ChartOps.funnelChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Pyramid Chart',
      (id, cx, cy) => ChartOps.pyramidChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Chevron Process',
      (id, cx, cy) => ChartOps.chevronChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Radar Chart',
      (id, cx, cy) => ChartOps.radarChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Polar Line',
      (id, cx, cy) => ChartOps.polarLineChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Radial Bar',
      (id, cx, cy) => ChartOps.radialBarChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Radial Column',
      (id, cx, cy) => ChartOps.radialColumnChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Gauge',
      (id, cx, cy) => ChartOps.gaugeChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Progress',
      (id, cx, cy) => ChartOps.progressChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Ring Progress',
      (id, cx, cy) => ChartOps.ringProgressChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Semi Progress',
      (id, cx, cy) => ChartOps.semiProgressChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Step Progress',
      (id, cx, cy) => ChartOps.stepProgressChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Bullet Chart',
      (id, cx, cy) => ChartOps.bulletChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Thermometer',
      (id, cx, cy) => ChartOps.thermometerChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Waffle Chart',
      (id, cx, cy) => ChartOps.waffleChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Battery Chart',
      (id, cx, cy) => ChartOps.batteryChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Traffic Light',
      (id, cx, cy) => ChartOps.trafficLightChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Waterfall',
      (id, cx, cy) => ChartOps.waterfallChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Bubble Chart',
      (id, cx, cy) => ChartOps.bubbleChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Candlestick Chart',
      (id, cx, cy) => ChartOps.candlestickChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Heatmap',
      (id, cx, cy) => ChartOps.heatmapChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Gantt Chart',
      (id, cx, cy) => ChartOps.ganttChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Box Plot',
      (id, cx, cy) => ChartOps.boxplotChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Slope Chart',
      (id, cx, cy) => ChartOps.slopeChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Calendar Heatmap',
      (id, cx, cy) => ChartOps.calendarHeatChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Range Bar',
      (id, cx, cy) => ChartOps.rangeBarChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Dumbbell Chart',
      (id, cx, cy) => ChartOps.dumbbellChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Quadrant Chart',
      (id, cx, cy) => ChartOps.quadrantChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Timeline Chart',
      (id, cx, cy) => ChartOps.timelineChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Nested Donut',
      (id, cx, cy) => ChartOps.nestedDonutChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'KPI Target',
      (id, cx, cy) => ChartOps.kpiTargetChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Data Table',
      (id, cx, cy) => ChartOps.dataTableChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Venn Diagram',
      (id, cx, cy) => ChartOps.vennChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Scorecard',
      (id, cx, cy) => ChartOps.scorecardChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Radial Multi',
      (id, cx, cy) => ChartOps.radialMultiChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Span Column',
      (id, cx, cy) => ChartOps.spanColumnChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Ranking Chart',
      (id, cx, cy) => ChartOps.rankingChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Process Steps',
      (id, cx, cy) => ChartOps.processStepsChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Arc Gauge',
      (id, cx, cy) => ChartOps.arcGaugeChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Bullet Group',
      (id, cx, cy) => ChartOps.bulletGroupChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Likert Scale',
      (id, cx, cy) => ChartOps.likertChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Heat Strip',
      (id, cx, cy) => ChartOps.heatStripChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Dual Compare',
      (id, cx, cy) => ChartOps.dualCompareChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Status Board',
      (id, cx, cy) => ChartOps.statusBoardChart(id: id, pinX: cx, pinY: cy),
    ),
  ], expandAtWidth: 900),
];

/// Flat list of every chart stencil.
final List<Stencil> kChartStencils = <Stencil>[
  for (final g in kChartStencilGroups) ...g.stencils,
];
