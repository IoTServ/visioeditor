import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vsdx/vsdx.dart';

import '../l10n/editor_l10n.dart';
import 'editor_controller.dart';

/// Right-panel chart editor: type, add/remove/reorder items, labels, values, colours.
class ChartConfigPanel extends StatefulWidget {
  const ChartConfigPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  State<ChartConfigPanel> createState() => _ChartConfigPanelState();
}

class _ChartConfigPanelState extends State<ChartConfigPanel> {
  final List<TextEditingController> _valueCtrls = <TextEditingController>[];
  final List<TextEditingController> _labelCtrls = <TextEditingController>[];
  final List<FocusNode> _valueFocus = <FocusNode>[];
  final List<FocusNode> _labelFocus = <FocusNode>[];
  final TextEditingController _percentCtrl = TextEditingController();
  final FocusNode _percentFocus = FocusNode();
  int? _boundChartId;
  String _boundFingerprint = '';
  int? _editingValueIndex;
  int? _editingLabelIndex;
  bool _editingPercent = false;

  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _percentFocus.addListener(_onPercentFocus);
    controller.addListener(_onController);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncFromController();
    });
  }

  @override
  void didUpdateWidget(covariant ChartConfigPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
      _syncFromController();
    }
  }

  @override
  void dispose() {
    controller.removeListener(_onController);
    _percentFocus.removeListener(_onPercentFocus);
    _percentFocus.dispose();
    _percentCtrl.dispose();
    _disposeFieldLists();
    super.dispose();
  }

  void _disposeFieldLists() {
    for (final c in _valueCtrls) {
      c.dispose();
    }
    for (final c in _labelCtrls) {
      c.dispose();
    }
    for (final f in _valueFocus) {
      f.removeListener(_onValueFocusChanged);
      f.dispose();
    }
    for (final f in _labelFocus) {
      f.removeListener(_onLabelFocusChanged);
      f.dispose();
    }
    _valueCtrls.clear();
    _labelCtrls.clear();
    _valueFocus.clear();
    _labelFocus.clear();
  }

  void _onController() {
    if (!mounted) return;
    _syncFromController();
  }

  void _onPercentFocus() {
    if (_percentFocus.hasFocus) {
      _editingPercent = true;
    } else if (_editingPercent) {
      _editingPercent = false;
      _commitPercent();
    }
  }

  void _onValueFocusChanged() {
    for (var i = 0; i < _valueFocus.length; i++) {
      if (_valueFocus[i].hasFocus) {
        _editingValueIndex = i;
        return;
      }
    }
    final idx = _editingValueIndex;
    _editingValueIndex = null;
    if (idx != null) _commitValue(idx);
  }

  void _onLabelFocusChanged() {
    for (var i = 0; i < _labelFocus.length; i++) {
      if (_labelFocus[i].hasFocus) {
        _editingLabelIndex = i;
        return;
      }
    }
    final idx = _editingLabelIndex;
    _editingLabelIndex = null;
    if (idx != null) _commitLabel(idx);
  }

  String _fingerprint(VsdxShape chart) {
    final kind = ChartOps.chartKind(chart) ?? '';
    final vals = ChartOps.formatValues(ChartOps.chartValues(chart));
    final cols = ChartOps.formatColors(ChartOps.chartColors(chart));
    final labs = ChartOps.formatLabels(ChartOps.chartLabels(chart));
    return '$kind|$vals|$cols|$labs';
  }

  void _ensureFieldCount(int n) {
    while (_valueCtrls.length > n) {
      _valueCtrls.removeLast().dispose();
      _labelCtrls.removeLast().dispose();
      _valueFocus.removeLast()
        ..removeListener(_onValueFocusChanged)
        ..dispose();
      _labelFocus.removeLast()
        ..removeListener(_onLabelFocusChanged)
        ..dispose();
    }
    while (_valueCtrls.length < n) {
      _valueCtrls.add(TextEditingController());
      _labelCtrls.add(TextEditingController());
      final vf = FocusNode()..addListener(_onValueFocusChanged);
      final lf = FocusNode()..addListener(_onLabelFocusChanged);
      _valueFocus.add(vf);
      _labelFocus.add(lf);
    }
  }

  String _displayLabel(EditorL10n el, String stored, int index) {
    final m = RegExp(r'^Item (\d+)$').firstMatch(stored.trim());
    if (m != null) {
      return el.chartDefaultItem(int.parse(m.group(1)!));
    }
    if (stored.trim().isEmpty) return el.chartDefaultItem(index + 1);
    return stored;
  }

  void _syncFromController() {
    final chart = controller.selectedChart;
    final id = controller.selectedChartId;
    if (chart == null || id == null) return;
    final fp = _fingerprint(chart);
    if (id == _boundChartId && fp == _boundFingerprint) return;
    _boundChartId = id;
    _boundFingerprint = fp;
    final values = ChartOps.chartValues(chart);
    final labels = ChartOps.chartLabels(chart, values.length);
    final kind = ChartOps.chartKind(chart) ?? 'column';
    final el = EditorL10n.of(context);
    _ensureFieldCount(values.length);
    for (var i = 0; i < values.length; i++) {
      if (_editingValueIndex == i) continue;
      final text = ChartOps.isSingleValueKind(kind)
          ? ChartOps.formatPercent(values[i])
          : ChartOps.formatValues(<double>[values[i]]);
      if (_valueCtrls[i].text != text) _valueCtrls[i].text = text;
      if (_editingLabelIndex != i) {
        final shown = _displayLabel(el, labels[i], i);
        if (_labelCtrls[i].text != shown) _labelCtrls[i].text = shown;
      }
    }
    if (!_editingPercent &&
        ChartOps.isSingleValueKind(kind) &&
        values.isNotEmpty) {
      final p = ChartOps.formatPercent(values.first);
      if (_percentCtrl.text != p) _percentCtrl.text = p;
    }
    setState(() {});
  }

  void _flushEdits() {
    final vIdx = _editingValueIndex;
    final lIdx = _editingLabelIndex;
    if (vIdx != null) _commitValue(vIdx);
    if (lIdx != null) _commitLabel(lIdx);
    if (_editingPercent) _commitPercent();
  }

  void _commitValue(int index) {
    if (index < 0 || index >= _valueCtrls.length) return;
    final chart = controller.selectedChart;
    if (chart == null) return;
    final kind = ChartOps.chartKind(chart) ?? 'column';
    final raw = _valueCtrls[index].text.trim();
    final double? v;
    if (ChartOps.isSingleValueKind(kind)) {
      v = ChartOps.parseUnitValue(raw);
    } else {
      v = double.tryParse(raw.replaceAll(',', '.'));
    }
    if (v == null || !v.isFinite) {
      _boundFingerprint = '';
      _syncFromController();
      return;
    }
    controller.updateChartItem(index, value: v);
  }

  void _commitLabel(int index) {
    if (index < 0 || index >= _labelCtrls.length) return;
    controller.updateChartItem(index, label: _labelCtrls[index].text);
  }

  void _commitPercent() {
    final chart = controller.selectedChart;
    if (chart == null) return;
    final v = ChartOps.parseUnitValue(_percentCtrl.text);
    controller.updateChartItem(0, value: v);
  }

  void _addItem() {
    _flushEdits();
    final el = EditorL10n.of(context);
    final n = (controller.selectedChart != null)
        ? ChartOps.chartValues(controller.selectedChart!).length + 1
        : 1;
    controller.addChartItem(label: el.chartDefaultItem(n));
  }

  void _removeItem(int i) {
    _flushEdits();
    controller.removeChartItem(i);
  }

  void _moveItem(int from, int to) {
    _flushEdits();
    controller.reorderChartItem(from, to);
  }

  void _setKind(String kind) {
    _flushEdits();
    controller.setChartKind(kind);
  }

  Future<void> _pasteValues() async {
    _flushEdits();
    final el = EditorL10n.of(context);
    final chart = controller.selectedChart;
    final initial = chart == null
        ? ''
        : ChartOps.formatValues(ChartOps.chartValues(chart));
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
    if (result == null) return;
    controller.pasteChartSeries(result);
  }

  @override
  Widget build(BuildContext context) {
    final chart = controller.selectedChart;
    if (chart == null) return const SizedBox.shrink();
    final el = EditorL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final kind = ChartOps.chartKind(chart) ?? 'column';
    final values = ChartOps.chartValues(chart);
    final labels = ChartOps.chartLabels(chart, values.length);
    final colors =
        ChartOps.padColors(ChartOps.chartColors(chart), values.length);
    // First frame can run before the post-frame sync; keep controllers in lockstep.
    if (_valueCtrls.length != values.length) {
      _ensureFieldCount(values.length);
      for (var i = 0; i < values.length; i++) {
        final text = ChartOps.isSingleValueKind(kind)
            ? ChartOps.formatPercent(values[i])
            : ChartOps.formatValues(<double>[values[i]]);
        if (_valueCtrls[i].text != text) _valueCtrls[i].text = text;
        final shown = _displayLabel(el, labels[i], i);
        if (_labelCtrls[i].text != shown) _labelCtrls[i].text = shown;
      }
      if (ChartOps.isSingleValueKind(kind) && values.isNotEmpty) {
        final p = ChartOps.formatPercent(values.first);
        if (_percentCtrl.text != p) _percentCtrl.text = p;
      }
    }
    final single = ChartOps.isSingleValueKind(kind);
    final canAdd = !single && values.length < ChartOps.maxSeriesItems;
    final canRemove = !single && values.length > 1;
    final kindTitle = el.stencil(
      ChartOps.kindDisplayNames[kind] ?? 'Column Chart',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(el.panelChart, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Text(el.chartType, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        PopupMenuButton<String>(
          tooltip: el.chartType,
          onSelected: _setKind,
          itemBuilder: (ctx) => [
            for (final group in ChartOps.sharedKindGroups) ...[
              PopupMenuItem<String>(
                enabled: false,
                height: 28,
                child: Text(
                  el.chartKindGroup(group.$1),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ),
              for (final k in group.$2)
                CheckedPopupMenuItem<String>(
                  value: k,
                  checked: k == kind,
                  child: Text(
                    el.stencil(ChartOps.kindDisplayNames[k] ?? k),
                  ),
                ),
            ],
          ],
          child: InputDecorator(
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              suffixIcon: Icon(Icons.arrow_drop_down, size: 20),
            ),
            child: Text(kindTitle, style: const TextStyle(fontSize: 13)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          el.chartConfigHint,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        if (single) ...[
          Text(el.chartLevel, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          TextField(
            controller: _percentCtrl,
            focusNode: _percentFocus,
            decoration: InputDecoration(
              isDense: true,
              suffixText: '%',
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            style: const TextStyle(fontSize: 13),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,%]')),
            ],
            onEditingComplete: _commitPercent,
            onSubmitted: (_) => _commitPercent(),
          ),
          Slider(
            value: values.first.clamp(0.0, 1.0),
            min: 0,
            max: 1,
            divisions: 100,
            label: '${(values.first.clamp(0.0, 1.0) * 100).round()}%',
            onChangeStart: (_) {
              _flushEdits();
              controller.beginTransaction();
            },
            onChanged: (v) {
              _percentCtrl.text = ChartOps.formatPercent(v);
              controller.updateChartItem(0, value: v, transient: true);
            },
            onChangeEnd: (_) => controller.commitTransaction(),
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  el.chartItems,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              Text(
                '${values.length}/${ChartOps.maxSeriesItems}',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              IconButton(
                tooltip: el.chartPasteValues,
                onPressed: _pasteValues,
                icon: const Icon(Icons.content_paste_go_outlined, size: 18),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              IconButton(
                tooltip: el.chartEqualize,
                onPressed: () {
                  _flushEdits();
                  controller.equalizeChartValues();
                },
                icon: const Icon(Icons.horizontal_distribute, size: 18),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < values.length; i++) ...[
            _ChartItemCard(
              index: i,
              labelController: _labelCtrls[i],
              labelFocus: _labelFocus[i],
              valueController: _valueCtrls[i],
              valueFocus: _valueFocus[i],
              color: colors[i].value,
              labelHint: el.chartItemLabel,
              valueHint: el.chartValue,
              canRemove: canRemove,
              canMoveUp: i > 0,
              canMoveDown: i < values.length - 1,
              onCommitLabel: () => _commitLabel(i),
              onCommitValue: () => _commitValue(i),
              onColor: (c) {
                _flushEdits();
                controller.updateChartItem(i, color: VsdxColor(c));
              },
              onRemove: () => _removeItem(i),
              onMoveUp: () => _moveItem(i, i - 1),
              onMoveDown: () => _moveItem(i, i + 1),
              removeTooltip: el.chartRemoveItem,
              moveUpTooltip: el.chartMoveUp,
              moveDownTooltip: el.chartMoveDown,
            ),
            const SizedBox(height: 8),
          ],
          if (canAdd)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add, size: 18),
                label: Text(el.chartAddItem),
              ),
            ),
        ],
      ],
    );
  }
}

class _ChartItemCard extends StatelessWidget {
  const _ChartItemCard({
    required this.index,
    required this.labelController,
    required this.labelFocus,
    required this.valueController,
    required this.valueFocus,
    required this.color,
    required this.labelHint,
    required this.valueHint,
    required this.canRemove,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onCommitLabel,
    required this.onCommitValue,
    required this.onColor,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.removeTooltip,
    required this.moveUpTooltip,
    required this.moveDownTooltip,
  });

  final int index;
  final TextEditingController labelController;
  final FocusNode labelFocus;
  final TextEditingController valueController;
  final FocusNode valueFocus;
  final int color;
  final String labelHint;
  final String valueHint;
  final bool canRemove;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onCommitLabel;
  final VoidCallback onCommitValue;
  final ValueChanged<int> onColor;
  final VoidCallback onRemove;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final String removeTooltip;
  final String moveUpTooltip;
  final String moveDownTooltip;

  static const _palette = <int>[
    0xFF5B9BD5,
    0xFFED7D31,
    0xFF70AD47,
    0xFFFFC000,
    0xFF9E7CC3,
    0xFF5B9EA6,
    0xFFE53935,
    0xFF8E24AA,
    0xFF00897B,
    0xFF6D4C41,
    0xFF1E88E5,
    0xFFFB8C00,
  ];

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                PopupMenuButton<int>(
                  tooltip: EditorL10n.of(context).chartSeries,
                  padding: EdgeInsets.zero,
                  onSelected: onColor,
                  itemBuilder: (ctx) => [
                    for (final c in _palette)
                      PopupMenuItem(
                        value: c,
                        child: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Color(c),
                                border: Border.all(color: Colors.black26),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '#${c.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                            ),
                          ],
                        ),
                      ),
                  ],
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Color(color),
                      border: Border.all(color: Colors.black26),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: labelController,
                    focusNode: labelFocus,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: labelHint,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                    onEditingComplete: onCommitLabel,
                    onSubmitted: (_) => onCommitLabel(),
                  ),
                ),
                IconButton(
                  tooltip: moveUpTooltip,
                  onPressed: canMoveUp ? onMoveUp : null,
                  icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                IconButton(
                  tooltip: moveDownTooltip,
                  onPressed: canMoveDown ? onMoveDown : null,
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
                Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: valueController,
                    focusNode: valueFocus,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: valueHint,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
                    ],
                    onEditingComplete: onCommitValue,
                    onSubmitted: (_) => onCommitValue(),
                  ),
                ),
                if (canRemove)
                  IconButton(
                    tooltip: removeTooltip,
                    onPressed: onRemove,
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
    );
  }
}
