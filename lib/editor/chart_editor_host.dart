import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vsdx/vsdx.dart';

import '../l10n/editor_l10n.dart';
import 'chart_config_panel.dart';
import 'editor_controller.dart';

/// Routes the selected chart to a shared or specialty editor.
class ChartEditorHost extends StatelessWidget {
  const ChartEditorHost({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final chart = controller.selectedChart;
    if (chart == null) return const SizedBox.shrink();
    final kind = ChartOps.chartKind(chart) ?? 'column';
    if (!ChartOps.isCustomEditorKind(kind)) {
      return ChartConfigPanel(controller: controller);
    }
    final editor = switch (kind) {
      'candlestick' => _CandlestickEditor(controller: controller),
      'heatmap' => _HeatmapEditor(controller: controller),
      'gantt' => _GanttEditor(controller: controller),
      'boxplot' => _BoxplotEditor(controller: controller),
      'slope' => _SlopeEditor(controller: controller),
      'calendarHeat' => _CalendarHeatEditor(controller: controller),
      'rangeBar' => _PairSeriesEditor(
          controller: controller,
          title: 'Range Bar',
          hintGetter: (el) => el.chartSpecialtyRangeBarHint,
          leftGetter: (el) => el.chartLow,
          rightGetter: (el) => el.chartHigh,
          maxItems: 6,
        ),
      'dumbbell' => _PairSeriesEditor(
          controller: controller,
          title: 'Dumbbell Chart',
          hintGetter: (el) => el.chartSpecialtyDumbbellHint,
          leftGetter: (el) => el.chartStartValue,
          rightGetter: (el) => el.chartEndValue,
          maxItems: 6,
        ),
      'quadrant' => _PairSeriesEditor(
          controller: controller,
          title: 'Quadrant Chart',
          hintGetter: (el) => el.chartSpecialtyQuadrantHint,
          leftGetter: (el) => el.chartAxisX,
          rightGetter: (el) => el.chartAxisY,
          maxItems: 6,
        ),
      'timeline' => _PositionEventsEditor(
          controller: controller,
          title: 'Timeline Chart',
          hintGetter: (el) => el.chartSpecialtyTimelineHint,
          defaultLabelPrefix: 'Event',
          maxItems: 10,
        ),
      'nestedDonut' => _NestedDonutEditor(controller: controller),
      'kpiTarget' => _KpiTargetEditor(controller: controller),
      'dataTable' => _DataTableEditor(controller: controller),
      'venn' => _VennEditor(controller: controller),
      'scorecard' => _ScorecardEditor(controller: controller),
      'radialMulti' => _RadialMultiEditor(controller: controller),
      'spanColumn' => _PairSeriesEditor(
          controller: controller,
          title: 'Span Column',
          hintGetter: (el) => el.chartSpecialtySpanHint,
          leftGetter: (el) => el.chartLow,
          rightGetter: (el) => el.chartHigh,
          maxItems: 6,
        ),
      'ranking' => _LabeledValuesEditor(
          controller: controller,
          title: 'Ranking Chart',
          hintGetter: (el) => el.chartSpecialtyRankingHint,
          maxItems: 10,
          asPercent: true,
        ),
      'processSteps' => _ProcessStepsEditor(controller: controller),
      'arcGauge' => _ArcGaugeEditor(controller: controller),
      'bulletGroup' => _PairSeriesEditor(
          controller: controller,
          title: 'Bullet Group',
          hintGetter: (el) => el.chartSpecialtyBulletGroupHint,
          leftGetter: (el) => el.chartActual,
          rightGetter: (el) => el.chartTarget,
          maxItems: 6,
        ),
      'likert' => _LikertEditor(controller: controller),
      'heatStrip' => _HeatStripEditor(controller: controller),
      'dualCompare' => _PairSeriesEditor(
          controller: controller,
          title: 'Dual Compare',
          hintGetter: (el) => el.chartSpecialtyDualCompareHint,
          leftGetter: (el) => el.chartSeriesA,
          rightGetter: (el) => el.chartSeriesB,
          maxItems: 6,
        ),
      'statusBoard' => _StatusBoardEditor(controller: controller),
      'progressList' => _LabeledValuesEditor(
          controller: controller,
          title: 'Progress List',
          hintGetter: (el) => el.chartSpecialtyProgressListHint,
          maxItems: 8,
          asPercent: true,
        ),
      'milestone' => _PositionEventsEditor(
          controller: controller,
          title: 'Milestone Track',
          hintGetter: (el) => el.chartSpecialtyMilestoneHint,
          defaultLabelPrefix: 'M',
          maxItems: 8,
        ),
      'balanceBar' => _PairSeriesEditor(
          controller: controller,
          title: 'Balance Bar',
          hintGetter: (el) => el.chartSpecialtyBalanceBarHint,
          leftGetter: (el) => el.chartSeriesA,
          rightGetter: (el) => el.chartSeriesB,
          maxItems: 6,
        ),
      'meterCluster' => _LabeledValuesEditor(
          controller: controller,
          title: 'Meter Cluster',
          hintGetter: (el) => el.chartSpecialtyMeterClusterHint,
          maxItems: 6,
          asPercent: true,
        ),
      'priorityMatrix' => _PriorityMatrixEditor(controller: controller),
      'cycleFlow' => _LabeledValuesEditor(
          controller: controller,
          title: 'Cycle Flow',
          hintGetter: (el) => el.chartSpecialtyCycleFlowHint,
          maxItems: 8,
          asPercent: false,
        ),
      'checkboxList' => _CheckboxListEditor(controller: controller),
      'gapAnalysis' => _PairSeriesEditor(
          controller: controller,
          title: 'Gap Analysis',
          hintGetter: (el) => el.chartSpecialtyGapAnalysisHint,
          leftGetter: (el) => el.chartActual,
          rightGetter: (el) => el.chartTarget,
          maxItems: 6,
        ),
      'stageFunnel' => _LabeledValuesEditor(
          controller: controller,
          title: 'Stage Funnel',
          hintGetter: (el) => el.chartSpecialtyStageFunnelHint,
          maxItems: 8,
          asPercent: true,
        ),
      'rhythmBars' => _LabeledValuesEditor(
          controller: controller,
          title: 'Rhythm Bars',
          hintGetter: (el) => el.chartSpecialtyRhythmBarsHint,
          maxItems: 8,
          asPercent: true,
        ),
      'voteStack' => _VoteStackEditor(controller: controller),
      'trafficRow' => _TrafficRowEditor(controller: controller),
      'starRating' => _LabeledValuesEditor(
          controller: controller,
          title: 'Star Rating',
          hintGetter: (el) => el.chartSpecialtyStarRatingHint,
          maxItems: 6,
          asPercent: true,
        ),
      'compareCards' => _CompareCardsEditor(controller: controller),
      'pipeline' => _LabeledValuesEditor(
          controller: controller,
          title: 'Pipeline',
          hintGetter: (el) => el.chartSpecialtyPipelineHint,
          maxItems: 8,
          asPercent: true,
        ),
      'winLossStrip' => _WinLossStripEditor(controller: controller),
      'quotaBoard' => _PairSeriesEditor(
          controller: controller,
          title: 'Quota Board',
          hintGetter: (el) => el.chartSpecialtyQuotaBoardHint,
          leftGetter: (el) => el.chartActual,
          rightGetter: (el) => el.chartTarget,
          maxItems: 6,
        ),
      'tickLadder' => _LabeledValuesEditor(
          controller: controller,
          title: 'Tick Ladder',
          hintGetter: (el) => el.chartSpecialtyTickLadderHint,
          maxItems: 6,
          asPercent: true,
        ),
      _ => ChartConfigPanel(controller: controller),
    };
    if (editor is ChartConfigPanel) return editor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        editor,
        const _SpecialtyApplyButton(),
      ],
    );
  }
}

class _SpecialtyHeader extends StatelessWidget {
  const _SpecialtyHeader({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final el = EditorL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(el.panelChart, style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          hint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          el.chartConfigHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Toolbar above specialty item lists: count + paste / equalize.
class _SpecialtyDataToolbar extends StatelessWidget {
  const _SpecialtyDataToolbar({
    required this.count,
    required this.maxItems,
    this.onPaste,
    this.onEqualize,
  });

  final int count;
  final int maxItems;
  final VoidCallback? onPaste;
  final VoidCallback? onEqualize;

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              el.chartItems,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          Text(
            '$count/$maxItems',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          if (onPaste != null)
            IconButton(
              tooltip: el.chartPasteValues,
              onPressed: onPaste,
              icon: const Icon(Icons.content_paste_go_outlined, size: 18),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          if (onEqualize != null)
            IconButton(
              tooltip: el.chartEqualize,
              onPressed: onEqualize,
              icon: const Icon(Icons.horizontal_distribute, size: 18),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
        ],
      ),
    );
  }
}

class _SpecialtyItemFrame extends StatelessWidget {
  const _SpecialtyItemFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
        child: child,
      ),
    );
  }
}

class _SpecialtyAddButton extends StatelessWidget {
  const _SpecialtyAddButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add, size: 18),
        label: Text(label),
      ),
    );
  }
}

class _SpecialtyIndexChrome extends StatelessWidget {
  const _SpecialtyIndexChrome({
    required this.index,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    this.trailing,
  });

  final int index;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          '${index + 1}',
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: el.chartMoveUp,
          onPressed: canMoveUp ? onMoveUp : null,
          icon: const Icon(Icons.keyboard_arrow_up, size: 20),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        IconButton(
          tooltip: el.chartMoveDown,
          onPressed: canMoveDown ? onMoveDown : null,
          icon: const Icon(Icons.keyboard_arrow_down, size: 20),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        ?trailing,
      ],
    );
  }
}

Future<String?> _promptChartPaste(
  BuildContext context, {
  required String initial,
}) async {
  final el = EditorL10n.of(context);
  final draft = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(el.chartPasteValues),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: draft,
          autofocus: true,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: el.chartValuesHint,
            helperText: el.chartPasteHint,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(el.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, draft.text),
          child: Text(el.applyChart),
        ),
      ],
    ),
  );
  draft.dispose();
  return result;
}

class _NumField extends StatelessWidget {
  const _NumField({
    required this.label,
    required this.controller,
    required this.onCommit,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: _CommitTextField(
        controller: controller,
        onCommit: onCommit,
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        style: const TextStyle(fontSize: 12),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
        ],
      ),
    );
  }
}

/// Text field that commits on Enter and when focus leaves (tap outside).
class _CommitTextField extends StatelessWidget {
  const _CommitTextField({
    required this.controller,
    required this.onCommit,
    this.decoration,
    this.style,
    this.keyboardType,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final VoidCallback onCommit;
  final InputDecoration? decoration;
  final TextStyle? style;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: decoration ??
          const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
      style: style,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onEditingComplete: onCommit,
      onSubmitted: (_) => onCommit(),
      onTapOutside: (_) => onCommit(),
    );
  }
}

class _SpecialtyApplyButton extends StatelessWidget {
  const _SpecialtyApplyButton();

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => FocusScope.of(context).unfocus(),
          child: Text(el.applyChart),
        ),
      ),
    );
  }
}

mixin _ChartSync<T extends StatefulWidget> on State<T> {
  EditorController get controller;
  int? _boundId;
  String _boundFp = '';

  String fingerprint(VsdxShape chart);

  void syncFields(VsdxShape chart);

  void onControllerTick() {
    if (!mounted) return;
    final chart = controller.selectedChart;
    final id = controller.selectedChartId;
    if (chart == null || id == null) return;
    final fp = fingerprint(chart);
    if (id == _boundId && fp == _boundFp) return;
    _boundId = id;
    _boundFp = fp;
    syncFields(chart);
    setState(() {});
  }

  void markDirty() => _boundFp = '';
}

// --- Candlestick ------------------------------------------------------------

class _CandlestickEditor extends StatefulWidget {
  const _CandlestickEditor({required this.controller});
  final EditorController controller;
  @override
  State<_CandlestickEditor> createState() => _CandlestickEditorState();
}

class _CandlestickEditorState extends State<_CandlestickEditor>
    with _ChartSync<_CandlestickEditor> {
  final List<List<TextEditingController>> _rows = [];

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final r in _rows) {
      for (final c in r) {
        c.dispose();
      }
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      ChartOps.formatValues(ChartOps.chartValues(chart));

  @override
  void syncFields(VsdxShape chart) {
    final vals = ChartOps.chartValues(chart);
    final n = mathMax(1, vals.length ~/ 4);
    while (_rows.length > n) {
      for (final c in _rows.removeLast()) {
        c.dispose();
      }
    }
    while (_rows.length < n) {
      _rows.add(List.generate(4, (_) => TextEditingController()));
    }
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < 4; j++) {
        final v = i * 4 + j < vals.length ? vals[i * 4 + j] : 0.5;
        final t = ChartOps.formatValues(<double>[v]);
        if (_rows[i][j].text != t) _rows[i][j].text = t;
      }
    }
  }

  void _commit() {
    final out = <double>[];
    for (final r in _rows) {
      for (final c in r) {
        out.add(double.tryParse(c.text.replaceAll(',', '.')) ?? 0.5);
      }
    }
    markDirty();
    controller.setChartSpecialtyData(values: out);
  }

  void _add() {
    if (_rows.length >= 4) return;
    _rows.add(List.generate(
      4,
      (j) => TextEditingController(
        text: ChartOps.formatValues(
            <double>[[0.4, 0.7, 0.3, 0.55][j]]),
      ),
    ));
    _commit();
  }

  void _remove(int i) {
    if (_rows.length <= 1) return;
    for (final c in _rows.removeAt(i)) {
      c.dispose();
    }
    _commit();
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _rows.length) return;
    final row = _rows.removeAt(from);
    _rows.insert(to, row);
    _commit();
  }

  void _ensureFields() {
    final chart = controller.selectedChart;
    if (chart != null && _rows.isEmpty) syncFields(chart);
  }

  @override
  Widget build(BuildContext context) {
    _ensureFields();
    final el = EditorL10n.of(context);
    const maxItems = 4;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Candlestick Chart'),
          hint: el.chartSpecialtyCandlestickHint,
        ),
        _SpecialtyDataToolbar(count: _rows.length, maxItems: maxItems),
        for (var i = 0; i < _rows.length; i++) ...[
          _SpecialtyItemFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SpecialtyIndexChrome(
                  index: i,
                  canMoveUp: i > 0,
                  canMoveDown: i < _rows.length - 1,
                  onMoveUp: () => _move(i, i - 1),
                  onMoveDown: () => _move(i, i + 1),
                  trailing: _rows.length > 1
                      ? IconButton(
                          tooltip: el.chartRemoveItem,
                          onPressed: () => _remove(i),
                          icon: const Icon(Icons.remove_circle_outline,
                              size: 18),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 28, minHeight: 28),
                        )
                      : null,
                ),
                Text('${el.chartCandle} ${i + 1}',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _NumField(
                        label: el.chartOpen,
                        controller: _rows[i][0],
                        onCommit: _commit),
                    const SizedBox(width: 4),
                    _NumField(
                        label: el.chartHigh,
                        controller: _rows[i][1],
                        onCommit: _commit),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _NumField(
                        label: el.chartLow,
                        controller: _rows[i][2],
                        onCommit: _commit),
                    const SizedBox(width: 4),
                    _NumField(
                        label: el.chartClose,
                        controller: _rows[i][3],
                        onCommit: _commit),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        _SpecialtyAddButton(
          label: el.chartAddCandle,
          onPressed: _rows.length < maxItems ? _add : null,
        ),
      ],
    );
  }
}

// --- Heatmap ----------------------------------------------------------------

class _HeatmapEditor extends StatefulWidget {
  const _HeatmapEditor({required this.controller});
  final EditorController controller;
  @override
  State<_HeatmapEditor> createState() => _HeatmapEditorState();
}

class _HeatmapEditorState extends State<_HeatmapEditor>
    with _ChartSync<_HeatmapEditor> {
  int _rows = 3;
  int _cols = 4;
  final List<TextEditingController> _cells = [];

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in _cells) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      '${ChartOps.chartExtras(chart)}|${ChartOps.formatValues(ChartOps.chartValues(chart))}';

  @override
  void syncFields(VsdxShape chart) {
    final g = ChartOps.parseHeatmapGrid(ChartOps.chartExtras(chart));
    _rows = g.$1;
    _cols = g.$2;
    final vals = ChartOps.chartValues(chart);
    final n = _rows * _cols;
    while (_cells.length > n) {
      _cells.removeLast().dispose();
    }
    while (_cells.length < n) {
      _cells.add(TextEditingController());
    }
    for (var i = 0; i < n; i++) {
      final v = i < vals.length ? vals[i] : 0.5;
      final t = ChartOps.formatPercent(v);
      if (_cells[i].text != t) _cells[i].text = t;
    }
  }

  void _commit({int? rows, int? cols}) {
    final r = rows ?? _rows;
    final c = cols ?? _cols;
    final n = r * c;
    final out = <double>[
      for (var i = 0; i < n; i++)
        ChartOps.parseUnitValue(i < _cells.length ? _cells[i].text : '50'),
    ];
    markDirty();
    controller.setChartSpecialtyData(
      values: out,
      extras: ChartOps.formatHeatmapGrid(r, c),
    );
  }

  void _ensureControllers() {
    final chart = controller.selectedChart;
    final n = _rows * _cols;
    if (chart != null &&
        ChartOps.chartKind(chart) == 'heatmap' &&
        (_cells.isEmpty || _cells.length != n)) {
      syncFields(chart);
      return;
    }
    while (_cells.length > n) {
      _cells.removeLast().dispose();
    }
    while (_cells.length < n) {
      _cells.add(TextEditingController(text: '50'));
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureControllers();
    final el = EditorL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Heatmap'),
          hint: el.chartSpecialtyHeatmapHint,
        ),
        _SpecialtyDataToolbar(count: _rows * _cols, maxItems: 36),
        Row(
          children: [
            Text(el.chartRows, style: Theme.of(context).textTheme.labelMedium),
            const Spacer(),
            IconButton(
              onPressed: _rows > 1
                  ? () => _commit(rows: _rows - 1)
                  : null,
              icon: const Icon(Icons.remove, size: 18),
            ),
            Text('$_rows'),
            IconButton(
              onPressed: _rows < 6
                  ? () => _commit(rows: _rows + 1)
                  : null,
              icon: const Icon(Icons.add, size: 18),
            ),
          ],
        ),
        Row(
          children: [
            Text(el.chartCols, style: Theme.of(context).textTheme.labelMedium),
            const Spacer(),
            IconButton(
              onPressed: _cols > 1
                  ? () => _commit(cols: _cols - 1)
                  : null,
              icon: const Icon(Icons.remove, size: 18),
            ),
            Text('$_cols'),
            IconButton(
              onPressed: _cols < 6
                  ? () => _commit(cols: _cols + 1)
                  : null,
              icon: const Icon(Icons.add, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _SpecialtyItemFrame(
          child: Column(
            children: [
              for (var r = 0; r < _rows; r++)
                Padding(
                  padding: EdgeInsets.only(bottom: r < _rows - 1 ? 4 : 0),
                  child: Row(
                    children: [
                      for (var c = 0; c < _cols; c++) ...[
                        if (c > 0) const SizedBox(width: 4),
                        Expanded(
                          child: TextField(
                            controller: _cells[r * _cols + c],
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 6),
                              suffixText: '%',
                            ),
                            style: const TextStyle(fontSize: 11),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onEditingComplete: _commit,
                            onSubmitted: (_) => _commit(),
                            onTapOutside: (_) => _commit(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _SpecialtyAddButton(
          label: el.chartAddItem,
          onPressed: _rows < 6 ? () => _commit(rows: _rows + 1) : null,
        ),
      ],
    );
  }
}

// --- Gantt ------------------------------------------------------------------

class _GanttEditor extends StatefulWidget {
  const _GanttEditor({required this.controller});
  final EditorController controller;
  @override
  State<_GanttEditor> createState() => _GanttEditorState();
}

class _GanttEditorState extends State<_GanttEditor>
    with _ChartSync<_GanttEditor> {
  final List<TextEditingController> _labels = [];
  final List<TextEditingController> _starts = [];
  final List<TextEditingController> _durs = [];

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in [..._labels, ..._starts, ..._durs]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      '${ChartOps.formatValues(ChartOps.chartValues(chart))}|${ChartOps.formatLabels(ChartOps.chartLabels(chart))}';

  @override
  void syncFields(VsdxShape chart) {
    final vals = ChartOps.chartValues(chart);
    final n = mathMax(1, vals.length ~/ 2);
    final labs = ChartOps.chartLabels(chart, n);
    void ensure(List<TextEditingController> list, int count) {
      while (list.length > count) {
        list.removeLast().dispose();
      }
      while (list.length < count) {
        list.add(TextEditingController());
      }
    }

    ensure(_labels, n);
    ensure(_starts, n);
    ensure(_durs, n);
    for (var i = 0; i < n; i++) {
      if (_labels[i].text != labs[i]) _labels[i].text = labs[i];
      final s = ChartOps.formatPercent(vals[i * 2]);
      final d = ChartOps.formatPercent(vals[i * 2 + 1]);
      if (_starts[i].text != s) _starts[i].text = s;
      if (_durs[i].text != d) _durs[i].text = d;
    }
  }

  void _commit() {
    final n = _starts.length;
    final values = <double>[];
    final labels = <String>[];
    for (var i = 0; i < n; i++) {
      values.add(ChartOps.parseUnitValue(_starts[i].text));
      values.add(ChartOps.parseUnitValue(_durs[i].text));
      labels.add(_labels[i].text.trim().isEmpty
          ? 'Task ${i + 1}'
          : _labels[i].text.trim());
    }
    markDirty();
    controller.setChartSpecialtyData(values: values, labels: labels);
  }

  void _add() {
    if (_starts.length >= 8) return;
    _labels.add(TextEditingController(text: 'Task ${_starts.length + 1}'));
    _starts.add(TextEditingController(text: '10'));
    _durs.add(TextEditingController(text: '30'));
    _commit();
  }

  void _remove(int i) {
    if (_starts.length <= 1) return;
    _labels.removeAt(i).dispose();
    _starts.removeAt(i).dispose();
    _durs.removeAt(i).dispose();
    _commit();
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _starts.length) return;
    final lab = _labels.removeAt(from);
    final s = _starts.removeAt(from);
    final d = _durs.removeAt(from);
    _labels.insert(to, lab);
    _starts.insert(to, s);
    _durs.insert(to, d);
    _commit();
  }

  void _ensureFields() {
    final chart = controller.selectedChart;
    if (chart != null && _starts.isEmpty) syncFields(chart);
  }

  @override
  Widget build(BuildContext context) {
    _ensureFields();
    final el = EditorL10n.of(context);
    const maxItems = 8;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Gantt Chart'),
          hint: el.chartSpecialtyGanttHint,
        ),
        _SpecialtyDataToolbar(count: _starts.length, maxItems: maxItems),
        for (var i = 0; i < _starts.length; i++) ...[
          _SpecialtyItemFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SpecialtyIndexChrome(
                  index: i,
                  canMoveUp: i > 0,
                  canMoveDown: i < _starts.length - 1,
                  onMoveUp: () => _move(i, i - 1),
                  onMoveDown: () => _move(i, i + 1),
                  trailing: _starts.length > 1
                      ? IconButton(
                          tooltip: el.chartRemoveItem,
                          onPressed: () => _remove(i),
                          icon: const Icon(Icons.remove_circle_outline,
                              size: 18),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 28, minHeight: 28),
                        )
                      : null,
                ),
                TextField(
                  controller: _labels[i],
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: el.chartTaskName,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onEditingComplete: _commit,
                  onTapOutside: (_) => _commit(),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _NumField(
                        label: el.chartStart,
                        controller: _starts[i],
                        onCommit: _commit),
                    const SizedBox(width: 4),
                    _NumField(
                        label: el.chartDuration,
                        controller: _durs[i],
                        onCommit: _commit),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        _SpecialtyAddButton(
          label: el.chartAddTask,
          onPressed: _starts.length < maxItems ? _add : null,
        ),
      ],
    );
  }
}

// --- Box plot ---------------------------------------------------------------

class _BoxplotEditor extends StatefulWidget {
  const _BoxplotEditor({required this.controller});
  final EditorController controller;
  @override
  State<_BoxplotEditor> createState() => _BoxplotEditorState();
}

class _BoxplotEditorState extends State<_BoxplotEditor>
    with _ChartSync<_BoxplotEditor> {
  final List<TextEditingController> _ctrls = [];

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      ChartOps.formatValues(ChartOps.chartValues(chart));

  @override
  void syncFields(VsdxShape chart) {
    final vals = ChartOps.chartValues(chart);
    while (_ctrls.length > 5) {
      _ctrls.removeLast().dispose();
    }
    while (_ctrls.length < 5) {
      _ctrls.add(TextEditingController());
    }
    for (var i = 0; i < 5; i++) {
      final v = i < vals.length ? vals[i] : [0.15, 0.35, 0.5, 0.65, 0.85][i];
      final t = ChartOps.formatValues(<double>[v]);
      if (_ctrls[i].text != t) _ctrls[i].text = t;
    }
  }

  void _commit() {
    final out = <double>[
      for (final c in _ctrls)
        double.tryParse(c.text.replaceAll(',', '.')) ?? 0.5,
    ];
    markDirty();
    controller.setChartSpecialtyData(values: out);
  }

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    final labels = <String>[
      el.chartMin,
      el.chartQ1,
      el.chartMedian,
      el.chartQ3,
      el.chartMax,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Box Plot'),
          hint: el.chartSpecialtyBoxplotHint,
        ),
        _SpecialtyDataToolbar(count: 5, maxItems: 5),
        for (var i = 0; i < _ctrls.length; i++) ...[
          _SpecialtyItemFrame(
            child: TextField(
              controller: _ctrls[i],
              decoration: InputDecoration(
                isDense: true,
                labelText: labels[i],
                border: const OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 13),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onEditingComplete: _commit,
              onSubmitted: (_) => _commit(),
              onTapOutside: (_) => _commit(),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

// --- Slope ------------------------------------------------------------------

class _SlopeEditor extends StatefulWidget {
  const _SlopeEditor({required this.controller});
  final EditorController controller;
  @override
  State<_SlopeEditor> createState() => _SlopeEditorState();
}

class _SlopeEditorState extends State<_SlopeEditor>
    with _ChartSync<_SlopeEditor> {
  final List<TextEditingController> _labels = [];
  final List<TextEditingController> _before = [];
  final List<TextEditingController> _after = [];

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in [..._labels, ..._before, ..._after]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      '${ChartOps.formatValues(ChartOps.chartValues(chart))}|${ChartOps.formatLabels(ChartOps.chartLabels(chart))}';

  @override
  void syncFields(VsdxShape chart) {
    final vals = ChartOps.chartValues(chart);
    final n = mathMax(1, vals.length ~/ 2);
    final labs = ChartOps.chartLabels(chart, n);
    void ensure(List<TextEditingController> list, int count) {
      while (list.length > count) {
        list.removeLast().dispose();
      }
      while (list.length < count) {
        list.add(TextEditingController());
      }
    }

    ensure(_labels, n);
    ensure(_before, n);
    ensure(_after, n);
    for (var i = 0; i < n; i++) {
      if (_labels[i].text != labs[i]) _labels[i].text = labs[i];
      final a = ChartOps.formatValues(<double>[vals[i * 2]]);
      final b = ChartOps.formatValues(<double>[vals[i * 2 + 1]]);
      if (_before[i].text != a) _before[i].text = a;
      if (_after[i].text != b) _after[i].text = b;
    }
  }

  void _commit() {
    final values = <double>[];
    final labels = <String>[];
    for (var i = 0; i < _before.length; i++) {
      values.add(double.tryParse(_before[i].text.replaceAll(',', '.')) ?? 0.3);
      values.add(double.tryParse(_after[i].text.replaceAll(',', '.')) ?? 0.7);
      labels.add(_labels[i].text.trim().isEmpty
          ? 'Series ${i + 1}'
          : _labels[i].text.trim());
    }
    markDirty();
    controller.setChartSpecialtyData(values: values, labels: labels);
  }

  void _add() {
    if (_before.length >= 6) return;
    _labels.add(TextEditingController(text: 'Series ${_before.length + 1}'));
    _before.add(TextEditingController(text: '0.3'));
    _after.add(TextEditingController(text: '0.7'));
    _commit();
  }

  void _remove(int i) {
    if (_before.length <= 1) return;
    _labels.removeAt(i).dispose();
    _before.removeAt(i).dispose();
    _after.removeAt(i).dispose();
    _commit();
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _before.length) return;
    final lab = _labels.removeAt(from);
    final a = _before.removeAt(from);
    final b = _after.removeAt(from);
    _labels.insert(to, lab);
    _before.insert(to, a);
    _after.insert(to, b);
    _commit();
  }

  void _ensureFields() {
    final chart = controller.selectedChart;
    if (chart != null && _before.isEmpty) syncFields(chart);
  }

  Future<void> _paste() async {
    final chart = controller.selectedChart;
    final initial = chart == null
        ? ''
        : ChartOps.formatValues(ChartOps.chartValues(chart));
    final result = await _promptChartPaste(context, initial: initial);
    if (result == null || !mounted) return;
    final parsed = ChartOps.parseSeriesPaste(result);
    if (parsed.values.isEmpty) return;
    final pairs = (parsed.values.length / 2).ceil().clamp(1, 6);
    final pastedLabs = parsed.labels ?? const <String>[];
    markDirty();
    controller.setChartSpecialtyData(
      values: <double>[
        for (var i = 0; i < pairs; i++) ...[
          i * 2 < parsed.values.length ? parsed.values[i * 2] : 0.3,
          i * 2 + 1 < parsed.values.length ? parsed.values[i * 2 + 1] : 0.7,
        ],
      ],
      labels: <String>[
        for (var i = 0; i < pairs; i++)
          i < pastedLabs.length && pastedLabs[i].trim().isNotEmpty
              ? pastedLabs[i].trim()
              : 'Series ${i + 1}',
      ],
    );
  }

  void _equalize() {
    if (_before.isEmpty) return;
    markDirty();
    controller.setChartSpecialtyData(
      values: <double>[
        for (var i = 0; i < _before.length; i++) ...[0.35, 0.65],
      ],
      labels: <String>[
        for (var i = 0; i < _labels.length; i++)
          _labels[i].text.trim().isEmpty
              ? 'Series ${i + 1}'
              : _labels[i].text.trim(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureFields();
    final el = EditorL10n.of(context);
    const maxItems = 6;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Slope Chart'),
          hint: el.chartSpecialtySlopeHint,
        ),
        _SpecialtyDataToolbar(
          count: _before.length,
          maxItems: maxItems,
          onPaste: _paste,
          onEqualize: _equalize,
        ),
        for (var i = 0; i < _before.length; i++) ...[
          _SpecialtyItemFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SpecialtyIndexChrome(
                  index: i,
                  canMoveUp: i > 0,
                  canMoveDown: i < _before.length - 1,
                  onMoveUp: () => _move(i, i - 1),
                  onMoveDown: () => _move(i, i + 1),
                  trailing: _before.length > 1
                      ? IconButton(
                          tooltip: el.chartRemoveItem,
                          onPressed: () => _remove(i),
                          icon: const Icon(Icons.remove_circle_outline,
                              size: 18),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 28, minHeight: 28),
                        )
                      : null,
                ),
                TextField(
                  controller: _labels[i],
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: el.chartItemLabel,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onEditingComplete: _commit,
                  onTapOutside: (_) => _commit(),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _NumField(
                        label: el.chartBefore,
                        controller: _before[i],
                        onCommit: _commit),
                    const SizedBox(width: 4),
                    _NumField(
                        label: el.chartAfter,
                        controller: _after[i],
                        onCommit: _commit),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        _SpecialtyAddButton(
          label: el.chartAddItem,
          onPressed: _before.length < maxItems ? _add : null,
        ),
      ],
    );
  }
}

// --- Calendar heat ----------------------------------------------------------

class _CalendarHeatEditor extends StatefulWidget {
  const _CalendarHeatEditor({required this.controller});
  final EditorController controller;
  @override
  State<_CalendarHeatEditor> createState() => _CalendarHeatEditorState();
}

class _CalendarHeatEditorState extends State<_CalendarHeatEditor>
    with _ChartSync<_CalendarHeatEditor> {
  int _weeks = 4;
  final List<TextEditingController> _cells = [];

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in _cells) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      '${ChartOps.chartExtras(chart)}|${ChartOps.formatValues(ChartOps.chartValues(chart))}';

  @override
  void syncFields(VsdxShape chart) {
    _weeks = ChartOps.parseCalendarWeeks(ChartOps.chartExtras(chart));
    final vals = ChartOps.chartValues(chart);
    final n = _weeks * 7;
    while (_cells.length > n) {
      _cells.removeLast().dispose();
    }
    while (_cells.length < n) {
      _cells.add(TextEditingController());
    }
    for (var i = 0; i < n; i++) {
      final v = i < vals.length ? vals[i] : 0.5;
      final t = ChartOps.formatPercent(v);
      if (_cells[i].text != t) _cells[i].text = t;
    }
  }

  void _commit({int? weeks}) {
    final w = weeks ?? _weeks;
    final n = w * 7;
    final out = <double>[
      for (var i = 0; i < n; i++)
        ChartOps.parseUnitValue(i < _cells.length ? _cells[i].text : '40'),
    ];
    markDirty();
    controller.setChartSpecialtyData(
      values: out,
      extras: ChartOps.formatCalendarWeeks(w),
    );
  }

  void _ensureControllers() {
    final chart = controller.selectedChart;
    final n = _weeks * 7;
    if (chart != null &&
        ChartOps.chartKind(chart) == 'calendarHeat' &&
        (_cells.isEmpty || _cells.length != n)) {
      syncFields(chart);
      return;
    }
    while (_cells.length > n) {
      _cells.removeLast().dispose();
    }
    while (_cells.length < n) {
      _cells.add(TextEditingController(text: '40'));
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureControllers();
    final el = EditorL10n.of(context);
    final days = el.chartWeekdaysShort.split(',');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Calendar Heatmap'),
          hint: el.chartSpecialtyCalendarHint,
        ),
        _SpecialtyDataToolbar(count: _weeks * 7, maxItems: 42),
        Row(
          children: [
            Text(el.chartWeeks, style: Theme.of(context).textTheme.labelMedium),
            const Spacer(),
            IconButton(
              onPressed: _weeks > 2 ? () => _commit(weeks: _weeks - 1) : null,
              icon: const Icon(Icons.remove, size: 18),
            ),
            Text('$_weeks'),
            IconButton(
              onPressed: _weeks < 6 ? () => _commit(weeks: _weeks + 1) : null,
              icon: const Icon(Icons.add, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (var d = 0; d < 7; d++)
              Expanded(
                child: Text(
                  d < days.length ? days[d].trim() : '·',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        _SpecialtyItemFrame(
          child: Column(
            children: [
              for (var week = 0; week < _weeks; week++)
                Padding(
                  padding: EdgeInsets.only(bottom: week < _weeks - 1 ? 4 : 0),
                  child: Row(
                    children: [
                      for (var day = 0; day < 7; day++) ...[
                        if (day > 0) const SizedBox(width: 2),
                        Expanded(
                          child: TextField(
                            controller: _cells[week * 7 + day],
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 2, vertical: 4),
                            ),
                            style: const TextStyle(fontSize: 10),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onEditingComplete: _commit,
                            onSubmitted: (_) => _commit(),
                            onTapOutside: (_) => _commit(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _SpecialtyAddButton(
          label: el.chartAddItem,
          onPressed: _weeks < 6 ? () => _commit(weeks: _weeks + 1) : null,
        ),
      ],
    );
  }
}

int mathMax(int a, int b) => a > b ? a : b;

/// Shared editor for packed low/high (or x/y) series with labels.
class _PairSeriesEditor extends StatefulWidget {
  const _PairSeriesEditor({
    required this.controller,
    required this.title,
    required this.hintGetter,
    required this.leftGetter,
    required this.rightGetter,
    required this.maxItems,
  });

  final EditorController controller;
  final String title;
  final String Function(EditorL10n el) hintGetter;
  final String Function(EditorL10n el) leftGetter;
  final String Function(EditorL10n el) rightGetter;
  final int maxItems;

  @override
  State<_PairSeriesEditor> createState() => _PairSeriesEditorState();
}

class _PairSeriesEditorState extends State<_PairSeriesEditor>
    with _ChartSync<_PairSeriesEditor> {
  final List<TextEditingController> _labels = [];
  final List<TextEditingController> _left = [];
  final List<TextEditingController> _right = [];

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in [..._labels, ..._left, ..._right]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      '${ChartOps.formatValues(ChartOps.chartValues(chart))}|${ChartOps.formatLabels(ChartOps.chartLabels(chart))}';

  @override
  void syncFields(VsdxShape chart) {
    final vals = ChartOps.chartValues(chart);
    final n = mathMax(1, vals.length ~/ 2);
    final labs = ChartOps.chartLabels(chart, n);
    void ensure(List<TextEditingController> list, int count) {
      while (list.length > count) {
        list.removeLast().dispose();
      }
      while (list.length < count) {
        list.add(TextEditingController());
      }
    }

    ensure(_labels, n);
    ensure(_left, n);
    ensure(_right, n);
    for (var i = 0; i < n; i++) {
      if (_labels[i].text != labs[i]) _labels[i].text = labs[i];
      final a = ChartOps.formatValues(<double>[vals[i * 2]]);
      final b = ChartOps.formatValues(<double>[vals[i * 2 + 1]]);
      if (_left[i].text != a) _left[i].text = a;
      if (_right[i].text != b) _right[i].text = b;
    }
  }

  void _commit() {
    final values = <double>[];
    final labels = <String>[];
    for (var i = 0; i < _left.length; i++) {
      values.add(double.tryParse(_left[i].text.replaceAll(',', '.')) ?? 0.2);
      values.add(double.tryParse(_right[i].text.replaceAll(',', '.')) ?? 0.7);
      labels.add(_labels[i].text.trim().isEmpty
          ? 'Item ${i + 1}'
          : _labels[i].text.trim());
    }
    markDirty();
    controller.setChartSpecialtyData(values: values, labels: labels);
  }

  void _ensureFields() {
    final chart = controller.selectedChart;
    if (chart != null && _left.isEmpty) {
      syncFields(chart);
    }
  }

  void _add() {
    if (_left.length >= widget.maxItems) return;
    final el = EditorL10n.of(context);
    _labels.add(
        TextEditingController(text: el.chartDefaultItem(_left.length + 1)));
    _left.add(TextEditingController(text: '0.2'));
    _right.add(TextEditingController(text: '0.7'));
    _commit();
  }

  void _remove(int i) {
    if (_left.length <= 1) return;
    _labels.removeAt(i).dispose();
    _left.removeAt(i).dispose();
    _right.removeAt(i).dispose();
    _commit();
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _left.length) return;
    final lab = _labels.removeAt(from);
    final a = _left.removeAt(from);
    final b = _right.removeAt(from);
    _labels.insert(to, lab);
    _left.insert(to, a);
    _right.insert(to, b);
    _commit();
  }

  Future<void> _paste() async {
    final chart = controller.selectedChart;
    final initial = chart == null
        ? ''
        : ChartOps.formatValues(ChartOps.chartValues(chart));
    final result = await _promptChartPaste(context, initial: initial);
    if (result == null || !mounted) return;
    final parsed = ChartOps.parseSeriesPaste(result);
    if (parsed.values.isEmpty) return;
    final pairs = (parsed.values.length ~/ 2).clamp(1, widget.maxItems);
    final pastedLabs = parsed.labels ?? const <String>[];
    final values = <double>[
      for (var i = 0; i < pairs; i++) ...[
        i * 2 < parsed.values.length ? parsed.values[i * 2] : 0.2,
        i * 2 + 1 < parsed.values.length ? parsed.values[i * 2 + 1] : 0.7,
      ],
    ];
    final labels = <String>[
      for (var i = 0; i < pairs; i++)
        i < pastedLabs.length && pastedLabs[i].trim().isNotEmpty
            ? pastedLabs[i].trim()
            : 'Item ${i + 1}',
    ];
    markDirty();
    controller.setChartSpecialtyData(values: values, labels: labels);
  }

  void _equalize() {
    if (_left.isEmpty) return;
    markDirty();
    controller.setChartSpecialtyData(
      values: <double>[
        for (var i = 0; i < _left.length; i++) ...[0.5, 0.5],
      ],
      labels: <String>[
        for (var i = 0; i < _labels.length; i++)
          _labels[i].text.trim().isEmpty
              ? 'Item ${i + 1}'
              : _labels[i].text.trim(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureFields();
    final el = EditorL10n.of(context);
    final canAdd = _left.length < widget.maxItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil(widget.title),
          hint: widget.hintGetter(el),
        ),
        _SpecialtyDataToolbar(
          count: _left.length,
          maxItems: widget.maxItems,
          onPaste: _paste,
          onEqualize: _equalize,
        ),
        for (var i = 0; i < _left.length; i++) ...[
          _SpecialtyItemFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _labels[i],
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: el.chartItemLabel,
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                        ),
                        style: const TextStyle(fontSize: 12),
                        onEditingComplete: _commit,
                        onTapOutside: (_) => _commit(),
                      ),
                    ),
                    IconButton(
                      tooltip: el.chartMoveUp,
                      onPressed: i > 0 ? () => _move(i, i - 1) : null,
                      icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                    IconButton(
                      tooltip: el.chartMoveDown,
                      onPressed:
                          i < _left.length - 1 ? () => _move(i, i + 1) : null,
                      icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _NumField(
                        label: widget.leftGetter(el),
                        controller: _left[i],
                        onCommit: _commit),
                    const SizedBox(width: 4),
                    _NumField(
                        label: widget.rightGetter(el),
                        controller: _right[i],
                        onCommit: _commit),
                    if (_left.length > 1)
                      IconButton(
                        tooltip: el.chartRemoveItem,
                        onPressed: () => _remove(i),
                        icon: const Icon(Icons.remove_circle_outline, size: 18),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (canAdd)
          _SpecialtyAddButton(
            label: el.chartAddItem,
            onPressed: _add,
          ),
      ],
    );
  }
}

class _PositionEventsEditor extends StatefulWidget {
  const _PositionEventsEditor({
    required this.controller,
    required this.title,
    required this.hintGetter,
    required this.defaultLabelPrefix,
    required this.maxItems,
  });

  final EditorController controller;
  final String title;
  final String Function(EditorL10n el) hintGetter;
  final String defaultLabelPrefix;
  final int maxItems;

  @override
  State<_PositionEventsEditor> createState() => _PositionEventsEditorState();
}

class _PositionEventsEditorState extends State<_PositionEventsEditor>
    with _ChartSync<_PositionEventsEditor> {
  final List<TextEditingController> _labels = [];
  final List<TextEditingController> _pos = [];

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in [..._labels, ..._pos]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      '${ChartOps.formatValues(ChartOps.chartValues(chart))}|${ChartOps.formatLabels(ChartOps.chartLabels(chart))}';

  @override
  void syncFields(VsdxShape chart) {
    final vals = ChartOps.chartValues(chart);
    final n = mathMax(1, vals.length);
    final labs = ChartOps.chartLabels(chart, n);
    while (_labels.length > n) {
      _labels.removeLast().dispose();
      _pos.removeLast().dispose();
    }
    while (_labels.length < n) {
      _labels.add(TextEditingController());
      _pos.add(TextEditingController());
    }
    for (var i = 0; i < n; i++) {
      if (_labels[i].text != labs[i]) _labels[i].text = labs[i];
      final t = ChartOps.formatPercent(vals[i]);
      if (_pos[i].text != t) _pos[i].text = t;
    }
  }

  String _defaultLabel(int i) => '${widget.defaultLabelPrefix} ${i + 1}';

  void _ensureFields() {
    final chart = controller.selectedChart;
    if (chart != null && _pos.isEmpty) {
      syncFields(chart);
    }
  }

  void _commit() {
    final values = <double>[
      for (final c in _pos) ChartOps.parseUnitValue(c.text),
    ];
    final labels = <String>[
      for (var i = 0; i < _labels.length; i++)
        _labels[i].text.trim().isEmpty
            ? _defaultLabel(i)
            : _labels[i].text.trim(),
    ];
    markDirty();
    controller.setChartSpecialtyData(values: values, labels: labels);
  }

  void _add() {
    if (_pos.length >= widget.maxItems) return;
    _labels.add(TextEditingController(text: _defaultLabel(_pos.length)));
    _pos.add(TextEditingController(text: '50'));
    _commit();
  }

  void _remove(int i) {
    if (_pos.length <= 1) return;
    _labels.removeAt(i).dispose();
    _pos.removeAt(i).dispose();
    _commit();
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _pos.length) return;
    final lab = _labels.removeAt(from);
    final pos = _pos.removeAt(from);
    _labels.insert(to, lab);
    _pos.insert(to, pos);
    _commit();
  }

  Future<void> _paste() async {
    final chart = controller.selectedChart;
    final initial = chart == null
        ? ''
        : ChartOps.formatValues(ChartOps.chartValues(chart));
    final result = await _promptChartPaste(context, initial: initial);
    if (result == null || !mounted) return;
    final parsed = ChartOps.parseSeriesPaste(result);
    if (parsed.values.isEmpty) return;
    final n = parsed.values.length.clamp(1, widget.maxItems);
    final pastedLabs = parsed.labels ?? const <String>[];
    markDirty();
    controller.setChartSpecialtyData(
      values: <double>[
        for (var i = 0; i < n; i++) parsed.values[i].clamp(0.0, 1.0),
      ],
      labels: <String>[
        for (var i = 0; i < n; i++)
          i < pastedLabs.length && pastedLabs[i].trim().isNotEmpty
              ? pastedLabs[i].trim()
              : _defaultLabel(i),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureFields();
    final el = EditorL10n.of(context);
    final canAdd = _pos.length < widget.maxItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil(widget.title),
          hint: widget.hintGetter(el),
        ),
        _SpecialtyDataToolbar(
          count: _pos.length,
          maxItems: widget.maxItems,
          onPaste: _paste,
        ),
        for (var i = 0; i < _pos.length; i++) ...[
          _SpecialtyItemFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _labels[i],
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: el.chartEventName,
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                        ),
                        style: const TextStyle(fontSize: 12),
                        onEditingComplete: _commit,
                        onTapOutside: (_) => _commit(),
                      ),
                    ),
                    IconButton(
                      tooltip: el.chartMoveUp,
                      onPressed: i > 0 ? () => _move(i, i - 1) : null,
                      icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                    IconButton(
                      tooltip: el.chartMoveDown,
                      onPressed:
                          i < _pos.length - 1 ? () => _move(i, i + 1) : null,
                      icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _NumField(
                        label: el.chartPosition,
                        controller: _pos[i],
                        onCommit: _commit),
                    if (_pos.length > 1)
                      IconButton(
                        tooltip: el.chartRemoveItem,
                        onPressed: () => _remove(i),
                        icon: const Icon(Icons.remove_circle_outline, size: 18),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (canAdd)
          _SpecialtyAddButton(
            label: el.chartAddEvent,
            onPressed: _add,
          ),
      ],
    );
  }
}

class _NestedDonutEditor extends StatefulWidget {
  const _NestedDonutEditor({required this.controller});
  final EditorController controller;
  @override
  State<_NestedDonutEditor> createState() => _NestedDonutEditorState();
}

class _NestedDonutEditorState extends State<_NestedDonutEditor>
    with _ChartSync<_NestedDonutEditor> {
  int _inner = 3;
  final List<TextEditingController> _vals = [];

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in _vals) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      '${ChartOps.chartExtras(chart)}|${ChartOps.formatValues(ChartOps.chartValues(chart))}';

  @override
  void syncFields(VsdxShape chart) {
    final vals = ChartOps.chartValues(chart);
    _inner = ChartOps.parseNestedInner(ChartOps.chartExtras(chart), vals.length);
    while (_vals.length > vals.length) {
      _vals.removeLast().dispose();
    }
    while (_vals.length < vals.length) {
      _vals.add(TextEditingController());
    }
    for (var i = 0; i < vals.length; i++) {
      final t = ChartOps.formatValues(<double>[vals[i]]);
      if (_vals[i].text != t) _vals[i].text = t;
    }
  }

  void _commit({int? inner}) {
    final values = <double>[
      for (final c in _vals)
        double.tryParse(c.text.replaceAll(',', '.')) ?? 0.25,
    ];
    final inn = (inner ?? _inner).clamp(1, mathMax(1, values.length - 1));
    markDirty();
    controller.setChartSpecialtyData(
      values: values,
      extras: ChartOps.formatNestedInner(inn),
    );
  }

  void _add() {
    if (_vals.length >= 12) return;
    _vals.add(TextEditingController(text: '0.25'));
    _commit();
  }

  void _remove(int i) {
    if (_vals.length <= 2) return;
    _vals.removeAt(i).dispose();
    _commit();
  }

  Future<void> _paste() async {
    final chart = controller.selectedChart;
    final initial = chart == null
        ? ''
        : ChartOps.formatValues(ChartOps.chartValues(chart));
    final result = await _promptChartPaste(context, initial: initial);
    if (result == null || !mounted) return;
    final parsed = ChartOps.parseSeriesPaste(result);
    if (parsed.values.isEmpty) return;
    final n = parsed.values.length.clamp(2, 12);
    markDirty();
    controller.setChartSpecialtyData(
      values: parsed.values.take(n).toList(),
      extras: ChartOps.formatNestedInner(_inner.clamp(1, n - 1)),
    );
  }

  void _equalize() {
    if (_vals.isEmpty) return;
    markDirty();
    controller.setChartSpecialtyData(
      values: List<double>.filled(_vals.length, 1.0),
      extras: ChartOps.formatNestedInner(_inner),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chart = controller.selectedChart;
    if (chart != null &&
        ChartOps.chartKind(chart) == 'nestedDonut' &&
        _vals.isEmpty) {
      syncFields(chart);
    }
    final el = EditorL10n.of(context);
    const maxItems = 12;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Nested Donut'),
          hint: el.chartSpecialtyNestedDonutHint,
        ),
        Row(
          children: [
            Text(el.chartInnerSlices,
                style: Theme.of(context).textTheme.labelMedium),
            const Spacer(),
            IconButton(
              onPressed: _inner > 1 ? () => _commit(inner: _inner - 1) : null,
              icon: const Icon(Icons.remove, size: 18),
            ),
            Text('$_inner'),
            IconButton(
              onPressed: _inner < _vals.length - 1
                  ? () => _commit(inner: _inner + 1)
                  : null,
              icon: const Icon(Icons.add, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _SpecialtyDataToolbar(
          count: _vals.length,
          maxItems: maxItems,
          onPaste: _paste,
          onEqualize: _equalize,
        ),
        for (var i = 0; i < _vals.length; i++) ...[
          _SpecialtyItemFrame(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _vals[i],
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: i < _inner
                          ? '${el.chartInnerRing} ${i + 1}'
                          : '${el.chartOuterRing} ${i - _inner + 1}',
                      border: const OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 12),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onEditingComplete: _commit,
                    onSubmitted: (_) => _commit(),
                    onTapOutside: (_) => _commit(),
                  ),
                ),
                if (_vals.length > 2)
                  IconButton(
                    tooltip: el.chartRemoveItem,
                    onPressed: () => _remove(i),
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
        _SpecialtyAddButton(
          label: el.chartAddItem,
          onPressed: _vals.length < maxItems ? _add : null,
        ),
      ],
    );
  }
}

class _KpiTargetEditor extends StatefulWidget {
  const _KpiTargetEditor({required this.controller});
  final EditorController controller;
  @override
  State<_KpiTargetEditor> createState() => _KpiTargetEditorState();
}

class _KpiTargetEditorState extends State<_KpiTargetEditor>
    with _ChartSync<_KpiTargetEditor> {
  final _label = TextEditingController();
  final _actual = TextEditingController();
  final _target = TextEditingController();

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    _label.dispose();
    _actual.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      '${ChartOps.formatValues(ChartOps.chartValues(chart))}|${ChartOps.formatLabels(ChartOps.chartLabels(chart))}';

  @override
  void syncFields(VsdxShape chart) {
    final vals = ChartOps.chartValues(chart);
    final labs = ChartOps.chartLabels(chart, 1);
    if (_label.text != labs.first) _label.text = labs.first;
    final a = ChartOps.formatPercent(vals.isNotEmpty ? vals[0] : 0.72);
    final t = ChartOps.formatPercent(vals.length > 1 ? vals[1] : 0.9);
    if (_actual.text != a) _actual.text = a;
    if (_target.text != t) _target.text = t;
  }

  void _commit() {
    markDirty();
    controller.setChartSpecialtyData(
      values: <double>[
        ChartOps.parseUnitValue(_actual.text),
        ChartOps.parseUnitValue(_target.text),
      ],
      labels: <String>[
        _label.text.trim().isEmpty ? 'KPI' : _label.text.trim(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('KPI Target'),
          hint: el.chartSpecialtyKpiHint,
        ),
        _SpecialtyItemFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _label,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: el.chartKpiName,
                  border: const OutlineInputBorder(),
                ),
                onEditingComplete: _commit,
                onTapOutside: (_) => _commit(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _actual,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: el.chartActual,
                  suffixText: '%',
                  border: const OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onEditingComplete: _commit,
                onTapOutside: (_) => _commit(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _target,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: el.chartTarget,
                  suffixText: '%',
                  border: const OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onEditingComplete: _commit,
                onTapOutside: (_) => _commit(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DataTableEditor extends StatefulWidget {
  const _DataTableEditor({required this.controller});
  final EditorController controller;
  @override
  State<_DataTableEditor> createState() => _DataTableEditorState();
}

class _DataTableEditorState extends State<_DataTableEditor>
    with _ChartSync<_DataTableEditor> {
  static const List<int> _swatches = <int>[
    0xFF5B9BD5,
    0xFFED7D31,
    0xFF70AD47,
    0xFFFFC000,
    0xFF9E7CC3,
    0xFFFFFFFF,
    0xFFF0F4F8,
    0xFFE3F2FD,
    0xFF212121,
    0xFF90A4AE,
  ];

  int _rows = 4;
  int _cols = 3;
  bool _header = true;
  bool _borders = true;
  bool _zebra = false;
  int _headerColor = 0xFF5B9BD5;
  int _bodyColor = 0xFFFFFFFF;
  int _zebraColor = 0xFFF0F4F8;
  final List<TextEditingController> _cells = [];

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in _cells) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) {
    final cols = ChartOps.chartColors(chart);
    final colFp = cols.isEmpty
        ? ''
        : cols.map((c) => c.value.toRadixString(16)).join(',');
    return '${ChartOps.chartExtras(chart)}|'
        '${ChartOps.formatLabels(ChartOps.chartLabels(chart))}|$colFp';
  }

  @override
  void syncFields(VsdxShape chart) {
    final extras = ChartOps.chartExtras(chart);
    final g = ChartOps.parseTableGrid(extras);
    _rows = g.$1;
    _cols = g.$2;
    _header = ChartOps.parseTableFlag(extras, 'header');
    _borders = ChartOps.parseTableFlag(extras, 'borders');
    _zebra = ChartOps.parseTableFlag(extras, 'zebra', defaultValue: false);
    final colors = ChartOps.padColors(ChartOps.chartColors(chart), 3);
    _headerColor = colors[0].value;
    _bodyColor = colors[1].value;
    _zebraColor = colors[2].value;
    final labs = ChartOps.chartLabels(chart, _rows * _cols);
    final n = _rows * _cols;
    while (_cells.length > n) {
      _cells.removeLast().dispose();
    }
    while (_cells.length < n) {
      _cells.add(TextEditingController());
    }
    for (var i = 0; i < n; i++) {
      if (_cells[i].text != labs[i]) _cells[i].text = labs[i];
    }
  }

  void _commit({
    int? rows,
    int? cols,
    bool? header,
    bool? borders,
    bool? zebra,
    int? headerColor,
    int? bodyColor,
    int? zebraColor,
  }) {
    final r = rows ?? _rows;
    final c = cols ?? _cols;
    final n = r * c;
    final labels = <String>[
      for (var i = 0; i < n; i++)
        i < _cells.length && _cells[i].text.trim().isNotEmpty
            ? _cells[i].text
            : ( (header ?? _header) && i < c
                ? 'H${i + 1}'
                : 'R${i ~/ c + 1}C${i % c + 1}'),
    ];
    markDirty();
    controller.setChartSpecialtyData(
      values: List<double>.filled(n, 1),
      labels: labels,
      colors: <VsdxColor>[
        VsdxColor(headerColor ?? _headerColor),
        VsdxColor(bodyColor ?? _bodyColor),
        VsdxColor(zebraColor ?? _zebraColor),
      ],
      extras: ChartOps.formatTableExtras(
        rows: r,
        cols: c,
        header: header ?? _header,
        borders: borders ?? _borders,
        zebra: zebra ?? _zebra,
      ),
    );
  }

  Widget _colorRow(String label, int color, ValueChanged<int> onPick) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
        PopupMenuButton<int>(
          tooltip: label,
          onSelected: onPick,
          itemBuilder: (ctx) => [
            for (final s in _swatches)
              PopupMenuItem<int>(
                value: s,
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Color(s),
                        border: Border.all(color: Colors.black26),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '#${s.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Color(color),
              border: Border.all(color: Colors.black26),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    // First frame can run before the post-frame sync creates cell controllers.
    final chart = controller.selectedChart;
    if (chart != null &&
        ChartOps.chartKind(chart) == 'dataTable' &&
        (_cells.isEmpty || _cells.length != _rows * _cols)) {
      syncFields(chart);
    } else {
      final n = _rows * _cols;
      while (_cells.length > n) {
        _cells.removeLast().dispose();
      }
      while (_cells.length < n) {
        _cells.add(TextEditingController());
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Data Table'),
          hint: el.chartSpecialtyTableHint,
        ),
        _SpecialtyDataToolbar(count: _rows * _cols, maxItems: 64),
        Row(
          children: [
            Text(el.chartRows, style: Theme.of(context).textTheme.labelMedium),
            const Spacer(),
            IconButton(
              onPressed: _rows > 1 ? () => _commit(rows: _rows - 1) : null,
              icon: const Icon(Icons.remove, size: 18),
            ),
            Text('$_rows'),
            IconButton(
              onPressed: _rows < 8 ? () => _commit(rows: _rows + 1) : null,
              icon: const Icon(Icons.add, size: 18),
            ),
          ],
        ),
        Row(
          children: [
            Text(el.chartCols, style: Theme.of(context).textTheme.labelMedium),
            const Spacer(),
            IconButton(
              onPressed: _cols > 1 ? () => _commit(cols: _cols - 1) : null,
              icon: const Icon(Icons.remove, size: 18),
            ),
            Text('$_cols'),
            IconButton(
              onPressed: _cols < 8 ? () => _commit(cols: _cols + 1) : null,
              icon: const Icon(Icons.add, size: 18),
            ),
          ],
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(el.chartTableHeader, style: const TextStyle(fontSize: 13)),
          value: _header,
          onChanged: (v) => _commit(header: v),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(el.chartTableBorders, style: const TextStyle(fontSize: 13)),
          value: _borders,
          onChanged: (v) => _commit(borders: v),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(el.chartTableZebra, style: const TextStyle(fontSize: 13)),
          value: _zebra,
          onChanged: (v) => _commit(zebra: v),
        ),
        const SizedBox(height: 4),
        _colorRow(el.chartHeaderFill, _headerColor,
            (c) => _commit(headerColor: c)),
        const SizedBox(height: 6),
        _colorRow(el.chartBodyFill, _bodyColor, (c) => _commit(bodyColor: c)),
        if (_zebra) ...[
          const SizedBox(height: 6),
          _colorRow(el.chartZebraFill, _zebraColor,
              (c) => _commit(zebraColor: c)),
        ],
        const SizedBox(height: 10),
        Text(el.chartCellText, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        _SpecialtyItemFrame(
          child: Column(
            children: [
              for (var r = 0; r < _rows; r++)
                Padding(
                  padding: EdgeInsets.only(bottom: r < _rows - 1 ? 4 : 0),
                  child: Row(
                    children: [
                      for (var c = 0; c < _cols; c++) ...[
                        if (c > 0) const SizedBox(width: 4),
                        Expanded(
                          child: TextField(
                            controller: _cells[r * _cols + c],
                            decoration: InputDecoration(
                              isDense: true,
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 6),
                              hintText: _header && r == 0 ? 'H${c + 1}' : null,
                            ),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: _header && r == 0
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                            onEditingComplete: _commit,
                            onSubmitted: (_) => _commit(),
                            onTapOutside: (_) => _commit(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _SpecialtyAddButton(
          label: el.chartAddItem,
          onPressed: _rows < 8 ? () => _commit(rows: _rows + 1) : null,
        ),
      ],
    );
  }
}


class _VennEditor extends StatefulWidget {
  const _VennEditor({required this.controller});
  final EditorController controller;
  @override
  State<_VennEditor> createState() => _VennEditorState();
}

class _VennEditorState extends State<_VennEditor>
    with _ChartSync<_VennEditor> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  final _both = TextEditingController();
  final _la = TextEditingController();
  final _lb = TextEditingController();
  final _lboth = TextEditingController();

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in <TextEditingController>[_a, _b, _both, _la, _lb, _lboth]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      '${ChartOps.formatValues(ChartOps.chartValues(chart))}|${ChartOps.formatLabels(ChartOps.chartLabels(chart))}';

  @override
  void syncFields(VsdxShape chart) {
    final vals = ChartOps.chartValues(chart);
    final labs = ChartOps.chartLabels(chart, 3);
    void set(TextEditingController c, String t) {
      if (c.text != t) c.text = t;
    }

    set(_la, labs[0]);
    set(_lb, labs[1]);
    set(_lboth, labs[2]);
    set(_a, ChartOps.formatValues(<double>[vals[0]]));
    set(_b, ChartOps.formatValues(<double>[vals[1]]));
    set(_both, ChartOps.formatValues(<double>[vals[2]]));
  }

  void _commit() {
    markDirty();
    controller.setChartSpecialtyData(
      values: <double>[
        double.tryParse(_a.text.replaceAll(',', '.')) ?? 0.4,
        double.tryParse(_b.text.replaceAll(',', '.')) ?? 0.4,
        double.tryParse(_both.text.replaceAll(',', '.')) ?? 0.2,
      ],
      labels: <String>[
        _la.text.trim().isEmpty ? 'A' : _la.text.trim(),
        _lb.text.trim().isEmpty ? 'B' : _lb.text.trim(),
        _lboth.text.trim().isEmpty ? 'A∩B' : _lboth.text.trim(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Venn Diagram'),
          hint: el.chartSpecialtyVennHint,
        ),
        _SpecialtyDataToolbar(count: 3, maxItems: 3),
        _SpecialtyItemFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _la,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: el.chartVennSetA,
                  border: const OutlineInputBorder(),
                ),
                onEditingComplete: _commit,
                onTapOutside: (_) => _commit(),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _a,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: el.chartVennOnlyA,
                  border: const OutlineInputBorder(),
                ),
                onEditingComplete: _commit,
                onTapOutside: (_) => _commit(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _SpecialtyItemFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _lb,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: el.chartVennSetB,
                  border: const OutlineInputBorder(),
                ),
                onEditingComplete: _commit,
                onTapOutside: (_) => _commit(),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _b,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: el.chartVennOnlyB,
                  border: const OutlineInputBorder(),
                ),
                onEditingComplete: _commit,
                onTapOutside: (_) => _commit(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _SpecialtyItemFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _lboth,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: el.chartVennBothLabel,
                  border: const OutlineInputBorder(),
                ),
                onEditingComplete: _commit,
                onTapOutside: (_) => _commit(),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _both,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: el.chartVennBothValue,
                  border: const OutlineInputBorder(),
                ),
                onEditingComplete: _commit,
                onTapOutside: (_) => _commit(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScorecardEditor extends StatefulWidget {
  const _ScorecardEditor({required this.controller});
  final EditorController controller;
  @override
  State<_ScorecardEditor> createState() => _ScorecardEditorState();
}

class _ScorecardEditorState extends State<_ScorecardEditor>
    with _ChartSync<_ScorecardEditor> {
  int _cols = 2;
  final List<TextEditingController> _labels = [];
  final List<TextEditingController> _vals = [];

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in [..._labels, ..._vals]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      '${ChartOps.chartExtras(chart)}|${ChartOps.formatValues(ChartOps.chartValues(chart))}|${ChartOps.formatLabels(ChartOps.chartLabels(chart))}';

  @override
  void syncFields(VsdxShape chart) {
    _cols = ChartOps.parseScorecardCols(ChartOps.chartExtras(chart));
    final vals = ChartOps.chartValues(chart);
    final n = mathMax(1, vals.length);
    final labs = ChartOps.chartLabels(chart, n);
    while (_labels.length > n) {
      _labels.removeLast().dispose();
      _vals.removeLast().dispose();
    }
    while (_labels.length < n) {
      _labels.add(TextEditingController());
      _vals.add(TextEditingController());
    }
    for (var i = 0; i < n; i++) {
      if (_labels[i].text != labs[i]) _labels[i].text = labs[i];
      final t = ChartOps.formatPercent(vals[i]);
      if (_vals[i].text != t) _vals[i].text = t;
    }
  }

  void _commit({int? cols}) {
    final values = <double>[
      for (final c in _vals) ChartOps.parseUnitValue(c.text),
    ];
    final labels = <String>[
      for (var i = 0; i < _labels.length; i++)
        _labels[i].text.trim().isEmpty
            ? 'KPI ${i + 1}'
            : _labels[i].text.trim(),
    ];
    markDirty();
    controller.setChartSpecialtyData(
      values: values,
      labels: labels,
      extras: ChartOps.formatScorecardCols(cols ?? _cols),
    );
  }

  void _add() {
    if (_vals.length >= 8) return;
    _labels.add(TextEditingController(text: 'KPI ${_vals.length + 1}'));
    _vals.add(TextEditingController(text: '50'));
    _commit();
  }

  void _remove(int i) {
    if (_vals.length <= 1) return;
    _labels.removeAt(i).dispose();
    _vals.removeAt(i).dispose();
    _commit();
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _vals.length) return;
    final lab = _labels.removeAt(from);
    final val = _vals.removeAt(from);
    _labels.insert(to, lab);
    _vals.insert(to, val);
    _commit();
  }

  void _ensureFields() {
    final chart = controller.selectedChart;
    if (chart != null && _vals.isEmpty) syncFields(chart);
  }

  Future<void> _paste() async {
    final chart = controller.selectedChart;
    final initial = chart == null
        ? ''
        : ChartOps.formatValues(ChartOps.chartValues(chart));
    final result = await _promptChartPaste(context, initial: initial);
    if (result == null || !mounted) return;
    final parsed = ChartOps.parseSeriesPaste(result);
    if (parsed.values.isEmpty) return;
    final n = parsed.values.length.clamp(1, 8);
    final pastedLabs = parsed.labels ?? const <String>[];
    markDirty();
    controller.setChartSpecialtyData(
      values: <double>[
        for (var i = 0; i < n; i++) parsed.values[i].clamp(0.0, 1.0),
      ],
      labels: <String>[
        for (var i = 0; i < n; i++)
          i < pastedLabs.length && pastedLabs[i].trim().isNotEmpty
              ? pastedLabs[i].trim()
              : 'KPI ${i + 1}',
      ],
      extras: ChartOps.formatScorecardCols(_cols),
    );
  }

  void _equalize() {
    if (_vals.isEmpty) return;
    markDirty();
    controller.setChartSpecialtyData(
      values: List<double>.filled(_vals.length, 0.5),
      labels: <String>[
        for (var i = 0; i < _labels.length; i++)
          _labels[i].text.trim().isEmpty
              ? 'KPI ${i + 1}'
              : _labels[i].text.trim(),
      ],
      extras: ChartOps.formatScorecardCols(_cols),
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureFields();
    final el = EditorL10n.of(context);
    const maxItems = 8;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Scorecard'),
          hint: el.chartSpecialtyScorecardHint,
        ),
        Row(
          children: [
            Text(el.chartCols, style: Theme.of(context).textTheme.labelMedium),
            const Spacer(),
            IconButton(
              onPressed: _cols > 1 ? () => _commit(cols: _cols - 1) : null,
              icon: const Icon(Icons.remove, size: 18),
            ),
            Text('$_cols'),
            IconButton(
              onPressed: _cols < 4 ? () => _commit(cols: _cols + 1) : null,
              icon: const Icon(Icons.add, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _SpecialtyDataToolbar(
          count: _vals.length,
          maxItems: maxItems,
          onPaste: _paste,
          onEqualize: _equalize,
        ),
        for (var i = 0; i < _vals.length; i++) ...[
          _SpecialtyItemFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SpecialtyIndexChrome(
                  index: i,
                  canMoveUp: i > 0,
                  canMoveDown: i < _vals.length - 1,
                  onMoveUp: () => _move(i, i - 1),
                  onMoveDown: () => _move(i, i + 1),
                  trailing: _vals.length > 1
                      ? IconButton(
                          tooltip: el.chartRemoveItem,
                          onPressed: () => _remove(i),
                          icon: const Icon(Icons.remove_circle_outline,
                              size: 18),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 28, minHeight: 28),
                        )
                      : null,
                ),
                TextField(
                  controller: _labels[i],
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: el.chartKpiName,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                  onEditingComplete: _commit,
                  onTapOutside: (_) => _commit(),
                ),
                const SizedBox(height: 6),
                _NumField(
                    label: el.chartActual,
                    controller: _vals[i],
                    onCommit: _commit),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        _SpecialtyAddButton(
          label: el.chartAddItem,
          onPressed: _vals.length < maxItems ? _add : null,
        ),
      ],
    );
  }
}

class _RadialMultiEditor extends StatefulWidget {
  const _RadialMultiEditor({required this.controller});
  final EditorController controller;
  @override
  State<_RadialMultiEditor> createState() => _RadialMultiEditorState();
}

class _RadialMultiEditorState extends State<_RadialMultiEditor>
    with _ChartSync<_RadialMultiEditor> {
  final List<TextEditingController> _vals = [];

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in _vals) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      ChartOps.formatValues(ChartOps.chartValues(chart));

  @override
  void syncFields(VsdxShape chart) {
    final vals = ChartOps.chartValues(chart);
    while (_vals.length > vals.length) {
      _vals.removeLast().dispose();
    }
    while (_vals.length < vals.length) {
      _vals.add(TextEditingController());
    }
    for (var i = 0; i < vals.length; i++) {
      final t = ChartOps.formatPercent(vals[i]);
      if (_vals[i].text != t) _vals[i].text = t;
    }
  }

  void _commit() {
    markDirty();
    controller.setChartSpecialtyData(
      values: <double>[
        for (final c in _vals) ChartOps.parseUnitValue(c.text),
      ],
    );
  }

  void _add() {
    if (_vals.length >= 5) return;
    _vals.add(TextEditingController(text: '50'));
    _commit();
  }

  void _remove(int i) {
    if (_vals.length <= 1) return;
    _vals.removeAt(i).dispose();
    _commit();
  }

  Future<void> _paste() async {
    final chart = controller.selectedChart;
    final initial = chart == null
        ? ''
        : ChartOps.formatValues(ChartOps.chartValues(chart));
    final result = await _promptChartPaste(context, initial: initial);
    if (result == null || !mounted) return;
    final parsed = ChartOps.parseSeriesPaste(result);
    if (parsed.values.isEmpty) return;
    final n = parsed.values.length.clamp(1, 5);
    markDirty();
    controller.setChartSpecialtyData(
      values: <double>[
        for (var i = 0; i < n; i++) parsed.values[i].clamp(0.0, 1.0),
      ],
    );
  }

  void _equalize() {
    if (_vals.isEmpty) return;
    markDirty();
    controller.setChartSpecialtyData(
      values: List<double>.filled(_vals.length, 0.5),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chart = controller.selectedChart;
    if (chart != null && _vals.isEmpty) syncFields(chart);
    final el = EditorL10n.of(context);
    const maxItems = 5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Radial Multi'),
          hint: el.chartSpecialtyRadialMultiHint,
        ),
        _SpecialtyDataToolbar(
          count: _vals.length,
          maxItems: maxItems,
          onPaste: _paste,
          onEqualize: _equalize,
        ),
        for (var i = 0; i < _vals.length; i++) ...[
          _SpecialtyItemFrame(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _vals[i],
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: '${el.chartRing} ${i + 1}',
                      suffixText: '%',
                      border: const OutlineInputBorder(),
                    ),
                    onEditingComplete: _commit,
                    onTapOutside: (_) => _commit(),
                  ),
                ),
                if (_vals.length > 1)
                  IconButton(
                    tooltip: el.chartRemoveItem,
                    onPressed: () => _remove(i),
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
        _SpecialtyAddButton(
          label: el.chartAddRing,
          onPressed: _vals.length < maxItems ? _add : null,
        ),
      ],
    );
  }
}

class _LabeledValuesEditor extends StatefulWidget {
  const _LabeledValuesEditor({
    required this.controller,
    required this.title,
    required this.hintGetter,
    required this.maxItems,
    this.asPercent = false,
  });

  final EditorController controller;
  final String title;
  final String Function(EditorL10n el) hintGetter;
  final int maxItems;
  final bool asPercent;

  @override
  State<_LabeledValuesEditor> createState() => _LabeledValuesEditorState();
}

class _LabeledValuesEditorState extends State<_LabeledValuesEditor>
    with _ChartSync<_LabeledValuesEditor> {
  final List<TextEditingController> _labels = [];
  final List<TextEditingController> _vals = [];

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in [..._labels, ..._vals]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      '${ChartOps.formatValues(ChartOps.chartValues(chart))}|${ChartOps.formatLabels(ChartOps.chartLabels(chart))}';

  @override
  void syncFields(VsdxShape chart) {
    final vals = ChartOps.chartValues(chart);
    final n = mathMax(1, vals.length);
    final labs = ChartOps.chartLabels(chart, n);
    while (_labels.length > n) {
      _labels.removeLast().dispose();
      _vals.removeLast().dispose();
    }
    while (_labels.length < n) {
      _labels.add(TextEditingController());
      _vals.add(TextEditingController());
    }
    for (var i = 0; i < n; i++) {
      if (_labels[i].text != labs[i]) _labels[i].text = labs[i];
      final t = widget.asPercent
          ? ChartOps.formatPercent(vals[i])
          : ChartOps.formatValues(<double>[vals[i]]);
      if (_vals[i].text != t) _vals[i].text = t;
    }
  }

  void _ensureFields() {
    final chart = controller.selectedChart;
    if (chart != null && _vals.isEmpty) {
      syncFields(chart);
    }
  }

  void _commit() {
    final values = <double>[
      for (final c in _vals)
        widget.asPercent
            ? ChartOps.parseUnitValue(c.text)
            : (double.tryParse(c.text.replaceAll(',', '.')) ?? 0.5),
    ];
    final labels = <String>[
      for (var i = 0; i < _labels.length; i++)
        _labels[i].text.trim().isEmpty
            ? 'Item ${i + 1}'
            : _labels[i].text.trim(),
    ];
    markDirty();
    controller.setChartSpecialtyData(values: values, labels: labels);
  }

  void _add() {
    if (_vals.length >= widget.maxItems) return;
    final el = EditorL10n.of(context);
    _labels.add(
        TextEditingController(text: el.chartDefaultItem(_vals.length + 1)));
    _vals.add(TextEditingController(text: widget.asPercent ? '50' : '0.5'));
    _commit();
  }

  void _remove(int i) {
    if (_vals.length <= 1) return;
    _labels.removeAt(i).dispose();
    _vals.removeAt(i).dispose();
    _commit();
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _vals.length) return;
    final lab = _labels.removeAt(from);
    final val = _vals.removeAt(from);
    _labels.insert(to, lab);
    _vals.insert(to, val);
    _commit();
  }

  Future<void> _paste() async {
    final chart = controller.selectedChart;
    final initial = chart == null
        ? ''
        : ChartOps.formatValues(ChartOps.chartValues(chart));
    final result = await _promptChartPaste(context, initial: initial);
    if (result == null || !mounted) return;
    final parsed = ChartOps.parseSeriesPaste(result);
    if (parsed.values.isEmpty) return;
    final n = parsed.values.length.clamp(1, widget.maxItems);
    final pastedLabs = parsed.labels ?? const <String>[];
    markDirty();
    controller.setChartSpecialtyData(
      values: <double>[
        for (var i = 0; i < n; i++)
          widget.asPercent
              ? parsed.values[i].clamp(0.0, 1.0)
              : parsed.values[i],
      ],
      labels: <String>[
        for (var i = 0; i < n; i++)
          i < pastedLabs.length && pastedLabs[i].trim().isNotEmpty
              ? pastedLabs[i].trim()
              : 'Item ${i + 1}',
      ],
    );
  }

  void _equalize() {
    if (_vals.isEmpty) return;
    markDirty();
    controller.setChartSpecialtyData(
      values: List<double>.filled(_vals.length, widget.asPercent ? 0.5 : 1.0),
      labels: <String>[
        for (var i = 0; i < _labels.length; i++)
          _labels[i].text.trim().isEmpty
              ? 'Item ${i + 1}'
              : _labels[i].text.trim(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureFields();
    final el = EditorL10n.of(context);
    final canAdd = _vals.length < widget.maxItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil(widget.title),
          hint: widget.hintGetter(el),
        ),
        _SpecialtyDataToolbar(
          count: _vals.length,
          maxItems: widget.maxItems,
          onPaste: _paste,
          onEqualize: _equalize,
        ),
        for (var i = 0; i < _vals.length; i++) ...[
          _SpecialtyItemFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _labels[i],
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: el.chartItemLabel,
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                        ),
                        style: const TextStyle(fontSize: 13),
                        onEditingComplete: _commit,
                        onTapOutside: (_) => _commit(),
                      ),
                    ),
                    IconButton(
                      tooltip: el.chartMoveUp,
                      onPressed: i > 0 ? () => _move(i, i - 1) : null,
                      icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                    IconButton(
                      tooltip: el.chartMoveDown,
                      onPressed:
                          i < _vals.length - 1 ? () => _move(i, i + 1) : null,
                      icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _vals[i],
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: el.chartValue,
                          suffixText: widget.asPercent ? '%' : null,
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                        ),
                        style: const TextStyle(fontSize: 13),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onEditingComplete: _commit,
                        onSubmitted: (_) => _commit(),
                        onTapOutside: (_) => _commit(),
                      ),
                    ),
                    if (_vals.length > 1)
                      IconButton(
                        tooltip: el.chartRemoveItem,
                        onPressed: () => _remove(i),
                        icon:
                            const Icon(Icons.remove_circle_outline, size: 18),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (canAdd)
          _SpecialtyAddButton(
            label: el.chartAddItem,
            onPressed: _add,
          ),
      ],
    );
  }
}

class _ProcessStepsEditor extends StatefulWidget {
  const _ProcessStepsEditor({required this.controller});
  final EditorController controller;
  @override
  State<_ProcessStepsEditor> createState() => _ProcessStepsEditorState();
}

class _ProcessStepsEditorState extends State<_ProcessStepsEditor>
    with _ChartSync<_ProcessStepsEditor> {
  final List<TextEditingController> _labels = [];
  final List<double> _status = [];

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in _labels) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      '${ChartOps.formatValues(ChartOps.chartValues(chart))}|${ChartOps.formatLabels(ChartOps.chartLabels(chart))}';

  @override
  void syncFields(VsdxShape chart) {
    final vals = ChartOps.chartValues(chart);
    final n = mathMax(1, vals.length);
    final labs = ChartOps.chartLabels(chart, n);
    while (_labels.length > n) {
      _labels.removeLast().dispose();
      _status.removeLast();
    }
    while (_labels.length < n) {
      _labels.add(TextEditingController());
      _status.add(0);
    }
    for (var i = 0; i < n; i++) {
      if (_labels[i].text != labs[i]) _labels[i].text = labs[i];
      _status[i] = vals[i].clamp(0.0, 1.0);
    }
  }

  void _commit() {
    markDirty();
    controller.setChartSpecialtyData(
      values: List<double>.of(_status),
      labels: <String>[
        for (var i = 0; i < _labels.length; i++)
          _labels[i].text.trim().isEmpty
              ? 'Step ${i + 1}'
              : _labels[i].text.trim(),
      ],
    );
  }

  void _add() {
    if (_labels.length >= 8) return;
    _labels.add(TextEditingController(text: 'Step ${_labels.length + 1}'));
    _status.add(0);
    _commit();
  }

  void _remove(int i) {
    if (_labels.length <= 1) return;
    _labels.removeAt(i).dispose();
    _status.removeAt(i);
    _commit();
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _labels.length) return;
    final lab = _labels.removeAt(from);
    final st = _status.removeAt(from);
    _labels.insert(to, lab);
    _status.insert(to, st);
    _commit();
  }

  void _ensureFields() {
    final chart = controller.selectedChart;
    if (chart != null && _labels.isEmpty) syncFields(chart);
  }

  @override
  Widget build(BuildContext context) {
    _ensureFields();
    final el = EditorL10n.of(context);
    const maxItems = 8;
    final statuses = <(double, String)>[
      (1, el.chartStepDone),
      (0.5, el.chartStepCurrent),
      (0, el.chartStepTodo),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Process Steps'),
          hint: el.chartSpecialtyProcessHint,
        ),
        _SpecialtyDataToolbar(count: _labels.length, maxItems: maxItems),
        for (var i = 0; i < _labels.length; i++) ...[
          _SpecialtyItemFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SpecialtyIndexChrome(
                  index: i,
                  canMoveUp: i > 0,
                  canMoveDown: i < _labels.length - 1,
                  onMoveUp: () => _move(i, i - 1),
                  onMoveDown: () => _move(i, i + 1),
                  trailing: _labels.length > 1
                      ? IconButton(
                          tooltip: el.chartRemoveItem,
                          onPressed: () => _remove(i),
                          icon: const Icon(Icons.remove_circle_outline,
                              size: 18),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 28, minHeight: 28),
                        )
                      : null,
                ),
                TextField(
                  controller: _labels[i],
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: el.chartStepName,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                  onEditingComplete: _commit,
                  onTapOutside: (_) => _commit(),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<double>(
                  initialValue: _status[i] >= 0.99
                      ? 1
                      : _status[i] >= 0.4
                          ? 0.5
                          : 0,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: el.chartStepStatus,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final s in statuses)
                      DropdownMenuItem(value: s.$1, child: Text(s.$2)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _status[i] = v);
                    _commit();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        _SpecialtyAddButton(
          label: el.chartAddStep,
          onPressed: _labels.length < maxItems ? _add : null,
        ),
      ],
    );
  }
}


class _ArcGaugeEditor extends StatefulWidget {
  const _ArcGaugeEditor({required this.controller});
  final EditorController controller;
  @override
  State<_ArcGaugeEditor> createState() => _ArcGaugeEditorState();
}

class _ArcGaugeEditorState extends State<_ArcGaugeEditor>
    with _ChartSync<_ArcGaugeEditor> {
  final _actual = TextEditingController();
  final _target = TextEditingController();

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    _actual.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      ChartOps.formatValues(ChartOps.chartValues(chart));

  @override
  void syncFields(VsdxShape chart) {
    final vals = ChartOps.chartValues(chart);
    final a = ChartOps.formatPercent(vals.isNotEmpty ? vals[0] : 0.68);
    final t = ChartOps.formatPercent(vals.length > 1 ? vals[1] : 0.85);
    if (_actual.text != a) _actual.text = a;
    if (_target.text != t) _target.text = t;
  }

  void _commit() {
    markDirty();
    controller.setChartSpecialtyData(
      values: <double>[
        ChartOps.parseUnitValue(_actual.text),
        ChartOps.parseUnitValue(_target.text),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Arc Gauge'),
          hint: el.chartSpecialtyArcGaugeHint,
        ),
        _SpecialtyItemFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _actual,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: el.chartActual,
                  suffixText: '%',
                  border: const OutlineInputBorder(),
                ),
                onEditingComplete: _commit,
                onTapOutside: (_) => _commit(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _target,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: el.chartTarget,
                  suffixText: '%',
                  border: const OutlineInputBorder(),
                ),
                onEditingComplete: _commit,
                onTapOutside: (_) => _commit(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LikertEditor extends StatefulWidget {
  const _LikertEditor({required this.controller});
  final EditorController controller;
  @override
  State<_LikertEditor> createState() => _LikertEditorState();
}

class _LikertEditorState extends State<_LikertEditor>
    with _ChartSync<_LikertEditor> {
  final List<TextEditingController> _labels = List.generate(
    5,
    (_) => TextEditingController(),
  );
  final List<TextEditingController> _vals = List.generate(
    5,
    (_) => TextEditingController(),
  );

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in [..._labels, ..._vals]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      '${ChartOps.formatValues(ChartOps.chartValues(chart))}|${ChartOps.formatLabels(ChartOps.chartLabels(chart))}';

  @override
  void syncFields(VsdxShape chart) {
    final vals = ChartOps.chartValues(chart);
    final labs = ChartOps.chartLabels(chart, 5);
    for (var i = 0; i < 5; i++) {
      if (_labels[i].text != labs[i]) _labels[i].text = labs[i];
      final t = ChartOps.formatValues(
          <double>[i < vals.length ? vals[i] : 0.2]);
      if (_vals[i].text != t) _vals[i].text = t;
    }
  }

  void _commit() {
    markDirty();
    controller.setChartSpecialtyData(
      values: <double>[
        for (final c in _vals)
          double.tryParse(c.text.replaceAll(',', '.')) ?? 0.2,
      ],
      labels: <String>[
        for (var i = 0; i < 5; i++)
          _labels[i].text.trim().isEmpty
              ? const <String>['SD', 'D', 'N', 'A', 'SA'][i]
              : _labels[i].text.trim(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Likert Scale'),
          hint: el.chartSpecialtyLikertHint,
        ),
        _SpecialtyDataToolbar(count: 5, maxItems: 5),
        for (var i = 0; i < 5; i++) ...[
          _SpecialtyItemFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _labels[i],
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: '${el.chartSegment} ${i + 1}',
                    border: const OutlineInputBorder(),
                  ),
                  onEditingComplete: _commit,
                  onTapOutside: (_) => _commit(),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _vals[i],
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: el.chartValue,
                    border: const OutlineInputBorder(),
                  ),
                  onEditingComplete: _commit,
                  onTapOutside: (_) => _commit(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _HeatStripEditor extends StatefulWidget {
  const _HeatStripEditor({required this.controller});
  final EditorController controller;
  @override
  State<_HeatStripEditor> createState() => _HeatStripEditorState();
}

class _HeatStripEditorState extends State<_HeatStripEditor>
    with _ChartSync<_HeatStripEditor> {
  int _cells = 8;
  final List<TextEditingController> _vals = [];

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in _vals) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      '${ChartOps.chartExtras(chart)}|${ChartOps.formatValues(ChartOps.chartValues(chart))}';

  @override
  void syncFields(VsdxShape chart) {
    _cells = ChartOps.parseHeatStripCells(ChartOps.chartExtras(chart));
    final vals = ChartOps.chartValues(chart);
    while (_vals.length > _cells) {
      _vals.removeLast().dispose();
    }
    while (_vals.length < _cells) {
      _vals.add(TextEditingController());
    }
    for (var i = 0; i < _cells; i++) {
      final v = i < vals.length ? vals[i] : 0.5;
      final t = ChartOps.formatPercent(v);
      if (_vals[i].text != t) _vals[i].text = t;
    }
  }

  void _ensureControllers() {
    final chart = controller.selectedChart;
    if (chart != null &&
        ChartOps.chartKind(chart) == 'heatStrip' &&
        (_vals.isEmpty || _vals.length != _cells)) {
      syncFields(chart);
      return;
    }
    while (_vals.length > _cells) {
      _vals.removeLast().dispose();
    }
    while (_vals.length < _cells) {
      _vals.add(TextEditingController(text: '50'));
    }
  }

  void _commit({int? cells}) {
    final n = cells ?? _cells;
    final values = <double>[
      for (var i = 0; i < n; i++)
        ChartOps.parseUnitValue(i < _vals.length ? _vals[i].text : '50'),
    ];
    markDirty();
    controller.setChartSpecialtyData(
      values: values,
      extras: ChartOps.formatHeatStripCells(n),
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureControllers();
    final el = EditorL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Heat Strip'),
          hint: el.chartSpecialtyHeatStripHint,
        ),
        _SpecialtyDataToolbar(count: _cells, maxItems: 16),
        Row(
          children: [
            Text(el.chartCells, style: Theme.of(context).textTheme.labelMedium),
            const Spacer(),
            IconButton(
              onPressed: _cells > 3 ? () => _commit(cells: _cells - 1) : null,
              icon: const Icon(Icons.remove, size: 18),
            ),
            Text('$_cells'),
            IconButton(
              onPressed: _cells < 16 ? () => _commit(cells: _cells + 1) : null,
              icon: const Icon(Icons.add, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _SpecialtyItemFrame(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (var i = 0; i < _vals.length; i++)
                SizedBox(
                  width: 56,
                  child: TextField(
                    controller: _vals[i],
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      suffixText: '%',
                    ),
                    style: const TextStyle(fontSize: 11),
                    onEditingComplete: _commit,
                    onSubmitted: (_) => _commit(),
                    onTapOutside: (_) => _commit(),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _SpecialtyAddButton(
          label: el.chartAddItem,
          onPressed: _cells < 16 ? () => _commit(cells: _cells + 1) : null,
        ),
      ],
    );
  }
}

class _StatusBoardEditor extends StatefulWidget {
  const _StatusBoardEditor({required this.controller});
  final EditorController controller;
  @override
  State<_StatusBoardEditor> createState() => _StatusBoardEditorState();
}

class _StatusBoardEditorState extends State<_StatusBoardEditor>
    with _ChartSync<_StatusBoardEditor> {
  int _cols = 2;
  final List<TextEditingController> _labels = [];
  final List<double> _status = [];

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in _labels) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      '${ChartOps.chartExtras(chart)}|${ChartOps.formatValues(ChartOps.chartValues(chart))}|${ChartOps.formatLabels(ChartOps.chartLabels(chart))}';

  @override
  void syncFields(VsdxShape chart) {
    _cols = ChartOps.parseScorecardCols(ChartOps.chartExtras(chart));
    final vals = ChartOps.chartValues(chart);
    final n = mathMax(1, vals.length);
    final labs = ChartOps.chartLabels(chart, n);
    while (_labels.length > n) {
      _labels.removeLast().dispose();
      _status.removeLast();
    }
    while (_labels.length < n) {
      _labels.add(TextEditingController());
      _status.add(1);
    }
    for (var i = 0; i < n; i++) {
      if (_labels[i].text != labs[i]) _labels[i].text = labs[i];
      _status[i] = vals[i].clamp(0.0, 1.0);
    }
  }

  void _ensureFields() {
    final chart = controller.selectedChart;
    if (chart != null &&
        ChartOps.chartKind(chart) == 'statusBoard' &&
        _labels.isEmpty) {
      syncFields(chart);
    }
  }

  void _commit({int? cols}) {
    markDirty();
    controller.setChartSpecialtyData(
      values: List<double>.of(_status),
      labels: <String>[
        for (var i = 0; i < _labels.length; i++)
          _labels[i].text.trim().isEmpty
              ? 'Item ${i + 1}'
              : _labels[i].text.trim(),
      ],
      extras: ChartOps.formatScorecardCols(cols ?? _cols),
    );
  }

  void _add() {
    if (_labels.length >= 8) return;
    _labels.add(TextEditingController(text: 'Item ${_labels.length + 1}'));
    _status.add(1);
    _commit();
  }

  void _remove(int i) {
    if (_labels.length <= 1) return;
    _labels.removeAt(i).dispose();
    _status.removeAt(i);
    _commit();
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _labels.length) return;
    final lab = _labels.removeAt(from);
    final st = _status.removeAt(from);
    _labels.insert(to, lab);
    _status.insert(to, st);
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    _ensureFields();
    final el = EditorL10n.of(context);
    const maxItems = 8;
    final statuses = <(double, String)>[
      (1, el.chartStatusOk),
      (0.5, el.chartStatusWarn),
      (0, el.chartStatusBad),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Status Board'),
          hint: el.chartSpecialtyStatusBoardHint,
        ),
        Row(
          children: [
            Text(el.chartCols, style: Theme.of(context).textTheme.labelMedium),
            const Spacer(),
            IconButton(
              onPressed: _cols > 1 ? () => _commit(cols: _cols - 1) : null,
              icon: const Icon(Icons.remove, size: 18),
            ),
            Text('$_cols'),
            IconButton(
              onPressed: _cols < 4 ? () => _commit(cols: _cols + 1) : null,
              icon: const Icon(Icons.add, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _SpecialtyDataToolbar(count: _labels.length, maxItems: maxItems),
        for (var i = 0; i < _labels.length; i++) ...[
          _SpecialtyItemFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SpecialtyIndexChrome(
                  index: i,
                  canMoveUp: i > 0,
                  canMoveDown: i < _labels.length - 1,
                  onMoveUp: () => _move(i, i - 1),
                  onMoveDown: () => _move(i, i + 1),
                  trailing: _labels.length > 1
                      ? IconButton(
                          tooltip: el.chartRemoveItem,
                          onPressed: () => _remove(i),
                          icon: const Icon(Icons.remove_circle_outline,
                              size: 18),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 28, minHeight: 28),
                        )
                      : null,
                ),
                TextField(
                  controller: _labels[i],
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: el.chartItemLabel,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                  onEditingComplete: _commit,
                  onTapOutside: (_) => _commit(),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<double>(
                  initialValue: _status[i] >= 0.99
                      ? 1
                      : _status[i] >= 0.4
                          ? 0.5
                          : 0,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: el.chartStepStatus,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final s in statuses)
                      DropdownMenuItem(value: s.$1, child: Text(s.$2)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _status[i] = v);
                    _commit();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        _SpecialtyAddButton(
          label: el.chartAddItem,
          onPressed: _labels.length < maxItems ? _add : null,
        ),
      ],
    );
  }
}


class _PriorityMatrixEditor extends StatefulWidget {
  const _PriorityMatrixEditor({required this.controller});
  final EditorController controller;
  @override
  State<_PriorityMatrixEditor> createState() => _PriorityMatrixEditorState();
}

class _PriorityMatrixEditorState extends State<_PriorityMatrixEditor>
    with _ChartSync<_PriorityMatrixEditor> {
  static const _defaults = <String>[
    'Do first',
    'Schedule',
    'Delegate',
    'Drop',
  ];
  final List<TextEditingController> _labels =
      List.generate(4, (_) => TextEditingController());
  final List<TextEditingController> _vals =
      List.generate(4, (_) => TextEditingController());

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in [..._labels, ..._vals]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      '${ChartOps.formatValues(ChartOps.chartValues(chart))}|${ChartOps.formatLabels(ChartOps.chartLabels(chart))}';

  @override
  void syncFields(VsdxShape chart) {
    final vals = ChartOps.chartValues(chart);
    final labs = ChartOps.chartLabels(chart, 4);
    for (var i = 0; i < 4; i++) {
      if (_labels[i].text != labs[i]) _labels[i].text = labs[i];
      final t = ChartOps.formatPercent(i < vals.length ? vals[i] : 0.5);
      if (_vals[i].text != t) _vals[i].text = t;
    }
  }

  void _commit() {
    markDirty();
    controller.setChartSpecialtyData(
      values: <double>[
        for (final c in _vals) ChartOps.parseUnitValue(c.text),
      ],
      labels: <String>[
        for (var i = 0; i < 4; i++)
          _labels[i].text.trim().isEmpty ? _defaults[i] : _labels[i].text.trim(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Priority Matrix'),
          hint: el.chartSpecialtyPriorityMatrixHint,
        ),
        _SpecialtyDataToolbar(count: 4, maxItems: 4),
        for (var i = 0; i < 4; i++) ...[
          _SpecialtyItemFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _labels[i],
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: '${el.chartQuadrant} ${i + 1}',
                    border: const OutlineInputBorder(),
                  ),
                  onEditingComplete: _commit,
                  onTapOutside: (_) => _commit(),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _vals[i],
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: el.chartValue,
                    suffixText: '%',
                    border: const OutlineInputBorder(),
                  ),
                  onEditingComplete: _commit,
                  onTapOutside: (_) => _commit(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}


class _CheckboxListEditor extends StatefulWidget {
  const _CheckboxListEditor({required this.controller});
  final EditorController controller;
  @override
  State<_CheckboxListEditor> createState() => _CheckboxListEditorState();
}

class _CheckboxListEditorState extends State<_CheckboxListEditor>
    with _ChartSync<_CheckboxListEditor> {
  final List<TextEditingController> _labels = [];
  final List<bool> _done = [];

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in _labels) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      '${ChartOps.formatValues(ChartOps.chartValues(chart))}|${ChartOps.formatLabels(ChartOps.chartLabels(chart))}';

  @override
  void syncFields(VsdxShape chart) {
    final vals = ChartOps.chartValues(chart);
    final n = mathMax(1, vals.length);
    final labs = ChartOps.chartLabels(chart, n);
    while (_labels.length > n) {
      _labels.removeLast().dispose();
      _done.removeLast();
    }
    while (_labels.length < n) {
      _labels.add(TextEditingController());
      _done.add(false);
    }
    for (var i = 0; i < n; i++) {
      if (_labels[i].text != labs[i]) _labels[i].text = labs[i];
      _done[i] = vals[i] >= 0.5;
    }
  }

  void _ensureFields() {
    final chart = controller.selectedChart;
    if (chart != null &&
        ChartOps.chartKind(chart) == 'checkboxList' &&
        _labels.isEmpty) {
      syncFields(chart);
    }
  }

  void _commit() {
    markDirty();
    controller.setChartSpecialtyData(
      values: <double>[for (final d in _done) d ? 1.0 : 0.0],
      labels: <String>[
        for (var i = 0; i < _labels.length; i++)
          _labels[i].text.trim().isEmpty
              ? 'Item ${i + 1}'
              : _labels[i].text.trim(),
      ],
    );
  }

  void _add() {
    if (_labels.length >= 8) return;
    _labels.add(TextEditingController(text: 'Item ${_labels.length + 1}'));
    _done.add(false);
    _commit();
  }

  void _remove(int i) {
    if (_labels.length <= 1) return;
    _labels.removeAt(i).dispose();
    _done.removeAt(i);
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    _ensureFields();
    final el = EditorL10n.of(context);
    const maxItems = 8;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Checklist'),
          hint: el.chartSpecialtyCheckboxListHint,
        ),
        _SpecialtyDataToolbar(count: _labels.length, maxItems: maxItems),
        for (var i = 0; i < _labels.length; i++) ...[
          _SpecialtyItemFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _labels[i],
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: el.chartItemLabel,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                  onEditingComplete: _commit,
                  onTapOutside: (_) => _commit(),
                ),
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(el.chartStepDone),
                        value: _done[i],
                        onChanged: (v) {
                          setState(() => _done[i] = v ?? false);
                          _commit();
                        },
                      ),
                    ),
                    if (_labels.length > 1)
                      IconButton(
                        tooltip: el.chartRemoveItem,
                        onPressed: () => _remove(i),
                        icon: const Icon(Icons.remove_circle_outline, size: 18),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
        _SpecialtyAddButton(
          label: el.chartAddItem,
          onPressed: _labels.length < maxItems ? _add : null,
        ),
      ],
    );
  }
}

class _VoteStackEditor extends StatefulWidget {
  const _VoteStackEditor({required this.controller});
  final EditorController controller;
  @override
  State<_VoteStackEditor> createState() => _VoteStackEditorState();
}

class _VoteStackEditorState extends State<_VoteStackEditor>
    with _ChartSync<_VoteStackEditor> {
  static const _defaults = <String>['Yes', 'No', 'Abstain'];
  final List<TextEditingController> _labels =
      List.generate(3, (_) => TextEditingController());
  final List<TextEditingController> _vals =
      List.generate(3, (_) => TextEditingController());

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in [..._labels, ..._vals]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      '${ChartOps.formatValues(ChartOps.chartValues(chart))}|${ChartOps.formatLabels(ChartOps.chartLabels(chart))}';

  @override
  void syncFields(VsdxShape chart) {
    final vals = ChartOps.chartValues(chart);
    final labs = ChartOps.chartLabels(chart, 3);
    for (var i = 0; i < 3; i++) {
      if (_labels[i].text != labs[i]) _labels[i].text = labs[i];
      final t = ChartOps.formatValues(
          <double>[i < vals.length ? vals[i] : 0.3]);
      if (_vals[i].text != t) _vals[i].text = t;
    }
  }

  void _commit() {
    markDirty();
    controller.setChartSpecialtyData(
      values: <double>[
        for (final c in _vals)
          double.tryParse(c.text.replaceAll(',', '.')) ?? 0.3,
      ],
      labels: <String>[
        for (var i = 0; i < 3; i++)
          _labels[i].text.trim().isEmpty
              ? _defaults[i]
              : _labels[i].text.trim(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Vote Stack'),
          hint: el.chartSpecialtyVoteStackHint,
        ),
        _SpecialtyDataToolbar(count: 3, maxItems: 3),
        for (var i = 0; i < 3; i++) ...[
          _SpecialtyItemFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _labels[i],
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: '${el.chartSegment} ${i + 1}',
                    border: const OutlineInputBorder(),
                  ),
                  onEditingComplete: _commit,
                  onTapOutside: (_) => _commit(),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _vals[i],
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: el.chartValue,
                    border: const OutlineInputBorder(),
                  ),
                  onEditingComplete: _commit,
                  onTapOutside: (_) => _commit(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _TrafficRowEditor extends StatefulWidget {
  const _TrafficRowEditor({required this.controller});
  final EditorController controller;
  @override
  State<_TrafficRowEditor> createState() => _TrafficRowEditorState();
}

class _TrafficRowEditorState extends State<_TrafficRowEditor>
    with _ChartSync<_TrafficRowEditor> {
  final List<TextEditingController> _labels = [];
  final List<double> _status = [];

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in _labels) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      '${ChartOps.formatValues(ChartOps.chartValues(chart))}|${ChartOps.formatLabels(ChartOps.chartLabels(chart))}';

  @override
  void syncFields(VsdxShape chart) {
    final vals = ChartOps.chartValues(chart);
    final n = mathMax(1, vals.length);
    final labs = ChartOps.chartLabels(chart, n);
    while (_labels.length > n) {
      _labels.removeLast().dispose();
      _status.removeLast();
    }
    while (_labels.length < n) {
      _labels.add(TextEditingController());
      _status.add(1);
    }
    for (var i = 0; i < n; i++) {
      if (_labels[i].text != labs[i]) _labels[i].text = labs[i];
      _status[i] = vals[i].clamp(0.0, 1.0);
    }
  }

  void _ensureFields() {
    final chart = controller.selectedChart;
    if (chart != null &&
        ChartOps.chartKind(chart) == 'trafficRow' &&
        _labels.isEmpty) {
      syncFields(chart);
    }
  }

  void _commit() {
    markDirty();
    controller.setChartSpecialtyData(
      values: List<double>.of(_status),
      labels: <String>[
        for (var i = 0; i < _labels.length; i++)
          _labels[i].text.trim().isEmpty
              ? 'Item ${i + 1}'
              : _labels[i].text.trim(),
      ],
    );
  }

  void _add() {
    if (_labels.length >= 8) return;
    _labels.add(TextEditingController(text: 'Item ${_labels.length + 1}'));
    _status.add(1);
    _commit();
  }

  void _remove(int i) {
    if (_labels.length <= 1) return;
    _labels.removeAt(i).dispose();
    _status.removeAt(i);
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    _ensureFields();
    final el = EditorL10n.of(context);
    const maxItems = 8;
    final statuses = <(double, String)>[
      (1, el.chartStatusOk),
      (0.5, el.chartStatusWarn),
      (0, el.chartStatusBad),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Traffic Row'),
          hint: el.chartSpecialtyTrafficRowHint,
        ),
        _SpecialtyDataToolbar(count: _labels.length, maxItems: maxItems),
        for (var i = 0; i < _labels.length; i++) ...[
          _SpecialtyItemFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _labels[i],
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: el.chartItemLabel,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                  onEditingComplete: _commit,
                  onTapOutside: (_) => _commit(),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<double>(
                        initialValue: _status[i] >= 0.99
                            ? 1
                            : _status[i] >= 0.4
                                ? 0.5
                                : 0,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: el.chartStepStatus,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          for (final s in statuses)
                            DropdownMenuItem(value: s.$1, child: Text(s.$2)),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _status[i] = v);
                          _commit();
                        },
                      ),
                    ),
                    if (_labels.length > 1)
                      IconButton(
                        tooltip: el.chartRemoveItem,
                        onPressed: () => _remove(i),
                        icon: const Icon(Icons.remove_circle_outline, size: 18),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        _SpecialtyAddButton(
          label: el.chartAddItem,
          onPressed: _labels.length < maxItems ? _add : null,
        ),
      ],
    );
  }
}


class _CompareCardsEditor extends StatefulWidget {
  const _CompareCardsEditor({required this.controller});
  final EditorController controller;
  @override
  State<_CompareCardsEditor> createState() => _CompareCardsEditorState();
}

class _CompareCardsEditorState extends State<_CompareCardsEditor>
    with _ChartSync<_CompareCardsEditor> {
  final _la = TextEditingController();
  final _lb = TextEditingController();
  final _va = TextEditingController();
  final _vb = TextEditingController();

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    for (final c in [_la, _lb, _va, _vb]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      '${ChartOps.formatValues(ChartOps.chartValues(chart))}|${ChartOps.formatLabels(ChartOps.chartLabels(chart))}';

  @override
  void syncFields(VsdxShape chart) {
    final vals = ChartOps.chartValues(chart);
    final labs = ChartOps.chartLabels(chart, 2);
    if (_la.text != labs[0]) _la.text = labs[0];
    if (_lb.text != labs[1]) _lb.text = labs[1];
    final a = ChartOps.formatPercent(vals.isNotEmpty ? vals[0] : 0.72);
    final b = ChartOps.formatPercent(vals.length > 1 ? vals[1] : 0.58);
    if (_va.text != a) _va.text = a;
    if (_vb.text != b) _vb.text = b;
  }

  void _commit() {
    markDirty();
    controller.setChartSpecialtyData(
      values: <double>[
        ChartOps.parseUnitValue(_va.text),
        ChartOps.parseUnitValue(_vb.text),
      ],
      labels: <String>[
        _la.text.trim().isEmpty ? 'A' : _la.text.trim(),
        _lb.text.trim().isEmpty ? 'B' : _lb.text.trim(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Compare Cards'),
          hint: el.chartSpecialtyCompareCardsHint,
        ),
        _SpecialtyDataToolbar(count: 2, maxItems: 2),
        _SpecialtyItemFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _la,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: el.chartSeriesA,
                  border: const OutlineInputBorder(),
                ),
                onEditingComplete: _commit,
                onTapOutside: (_) => _commit(),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _va,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: el.chartValue,
                  suffixText: '%',
                  border: const OutlineInputBorder(),
                ),
                onEditingComplete: _commit,
                onTapOutside: (_) => _commit(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _SpecialtyItemFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _lb,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: el.chartSeriesB,
                  border: const OutlineInputBorder(),
                ),
                onEditingComplete: _commit,
                onTapOutside: (_) => _commit(),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _vb,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: el.chartValue,
                  suffixText: '%',
                  border: const OutlineInputBorder(),
                ),
                onEditingComplete: _commit,
                onTapOutside: (_) => _commit(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WinLossStripEditor extends StatefulWidget {
  const _WinLossStripEditor({required this.controller});
  final EditorController controller;
  @override
  State<_WinLossStripEditor> createState() => _WinLossStripEditorState();
}

class _WinLossStripEditorState extends State<_WinLossStripEditor>
    with _ChartSync<_WinLossStripEditor> {
  final List<bool> _wins = [];

  @override
  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => onControllerTick());
  }

  @override
  void dispose() {
    controller.removeListener(onControllerTick);
    super.dispose();
  }

  @override
  String fingerprint(VsdxShape chart) =>
      ChartOps.formatValues(ChartOps.chartValues(chart));

  @override
  void syncFields(VsdxShape chart) {
    final vals = ChartOps.chartValues(chart);
    final n = mathMax(1, vals.length);
    while (_wins.length > n) {
      _wins.removeLast();
    }
    while (_wins.length < n) {
      _wins.add(true);
    }
    for (var i = 0; i < n; i++) {
      _wins[i] = vals[i] >= 0.5;
    }
  }

  void _ensureFields() {
    final chart = controller.selectedChart;
    if (chart != null &&
        ChartOps.chartKind(chart) == 'winLossStrip' &&
        _wins.isEmpty) {
      syncFields(chart);
    }
  }

  void _commit() {
    markDirty();
    controller.setChartSpecialtyData(
      values: <double>[for (final w in _wins) w ? 1.0 : 0.0],
      labels: <String>[for (final w in _wins) w ? 'W' : 'L'],
    );
  }

  void _add() {
    if (_wins.length >= 8) return;
    _wins.add(true);
    _commit();
  }

  void _remove(int i) {
    if (_wins.length <= 1) return;
    _wins.removeAt(i);
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    _ensureFields();
    final el = EditorL10n.of(context);
    const maxItems = 8;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Win/Loss Strip'),
          hint: el.chartSpecialtyWinLossStripHint,
        ),
        _SpecialtyDataToolbar(count: _wins.length, maxItems: maxItems),
        for (var i = 0; i < _wins.length; i++) ...[
          _SpecialtyItemFrame(
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<bool>(
                    initialValue: _wins[i],
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: '${el.chartSegment} ${i + 1}',
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(value: true, child: Text(el.chartWin)),
                      DropdownMenuItem(value: false, child: Text(el.chartLoss)),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _wins[i] = v);
                      _commit();
                    },
                  ),
                ),
                if (_wins.length > 1)
                  IconButton(
                    tooltip: el.chartRemoveItem,
                    onPressed: () => _remove(i),
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        _SpecialtyAddButton(
          label: el.chartAddItem,
          onPressed: _wins.length < maxItems ? _add : null,
        ),
      ],
    );
  }
}
