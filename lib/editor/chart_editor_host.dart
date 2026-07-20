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
    return switch (kind) {
      'candlestick' => _CandlestickEditor(controller: controller),
      'heatmap' => _HeatmapEditor(controller: controller),
      'gantt' => _GanttEditor(controller: controller),
      'boxplot' => _BoxplotEditor(controller: controller),
      'slope' => _SlopeEditor(controller: controller),
      'calendarHeat' => _CalendarHeatEditor(controller: controller),
      _ => ChartConfigPanel(controller: controller),
    };
  }
}

class _SpecialtyHeader extends StatelessWidget {
  const _SpecialtyHeader({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(EditorL10n.of(context).panelChart,
            style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          hint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
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
      child: TextField(
        controller: controller,
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
        onEditingComplete: onCommit,
        onSubmitted: (_) => onCommit(),
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

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Candlestick Chart'),
          hint: el.chartSpecialtyCandlestickHint,
        ),
        for (var i = 0; i < _rows.length; i++) ...[
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
              IconButton(
                tooltip: el.delete,
                onPressed: _rows.length > 1 ? () => _remove(i) : null,
                icon: const Icon(Icons.remove_circle_outline, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        TextButton.icon(
          onPressed: _rows.length < 4 ? _add : null,
          icon: const Icon(Icons.add, size: 16),
          label: Text(el.chartAddCandle),
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

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Heatmap'),
          hint: el.chartSpecialtyHeatmapHint,
        ),
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
        for (var r = 0; r < _rows; r++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
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
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        suffixText: '%',
                      ),
                      style: const TextStyle(fontSize: 11),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onEditingComplete: _commit,
                      onSubmitted: (_) => _commit(),
                    ),
                  ),
                ],
              ],
            ),
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

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Gantt Chart'),
          hint: el.chartSpecialtyGanttHint,
        ),
        for (var i = 0; i < _starts.length; i++) ...[
          TextField(
            controller: _labels[i],
            decoration: InputDecoration(
              isDense: true,
              labelText: el.chartTaskName,
              border: const OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 12),
            onEditingComplete: _commit,
          ),
          const SizedBox(height: 4),
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
              IconButton(
                onPressed: _starts.length > 1 ? () => _remove(i) : null,
                icon: const Icon(Icons.remove_circle_outline, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        TextButton.icon(
          onPressed: _starts.length < 8 ? _add : null,
          icon: const Icon(Icons.add, size: 16),
          label: Text(el.chartAddTask),
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
        for (var i = 0; i < _ctrls.length; i++) ...[
          TextField(
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

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Slope Chart'),
          hint: el.chartSpecialtySlopeHint,
        ),
        for (var i = 0; i < _before.length; i++) ...[
          TextField(
            controller: _labels[i],
            decoration: InputDecoration(
              isDense: true,
              labelText: el.chartItemLabel,
              border: const OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 12),
            onEditingComplete: _commit,
          ),
          const SizedBox(height: 4),
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
              IconButton(
                onPressed: _before.length > 1 ? () => _remove(i) : null,
                icon: const Icon(Icons.remove_circle_outline, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        TextButton.icon(
          onPressed: _before.length < 6 ? _add : null,
          icon: const Icon(Icons.add, size: 16),
          label: Text(el.chartAddItem),
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

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    final days = el.chartWeekdaysShort.split(',');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpecialtyHeader(
          title: el.stencil('Calendar Heatmap'),
          hint: el.chartSpecialtyCalendarHint,
        ),
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
        for (var week = 0; week < _weeks; week++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
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
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                      ),
                      style: const TextStyle(fontSize: 10),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onEditingComplete: _commit,
                      onSubmitted: (_) => _commit(),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

int mathMax(int a, int b) => a > b ? a : b;
