/// Charts palette — draw.io / 万兴图示 style chart stencils.
library;

import 'package:vsdx/vsdx.dart';

import 'stencils.dart';

/// Chart libraries shown in the dedicated Charts sidebar (not mixed into
/// [kStencilGroups] "More shapes").
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
      'Pie Chart',
      (id, cx, cy) => ChartOps.pieChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Donut Chart',
      (id, cx, cy) => ChartOps.donutChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Line Chart',
      (id, cx, cy) => ChartOps.lineChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Area Chart',
      (id, cx, cy) => ChartOps.areaChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Funnel',
      (id, cx, cy) => ChartOps.funnelChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Radar Chart',
      (id, cx, cy) => ChartOps.radarChart(id: id, pinX: cx, pinY: cy),
    ),
    Stencil(
      'Gauge',
      (id, cx, cy) => ChartOps.gaugeChart(id: id, pinX: cx, pinY: cy),
    ),
  ], expandAtWidth: 900),
];

/// Flat list of every chart stencil.
final List<Stencil> kChartStencils = <Stencil>[
  for (final g in kChartStencilGroups) ...g.stencils,
];
