import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vsdx/vsdx.dart';

import '../l10n/editor_l10n.dart';
import 'editor_controller.dart';

/// Right-panel chart editor: type, add/remove items, per-item value + colour.
class ChartConfigPanel extends StatefulWidget {
  const ChartConfigPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  State<ChartConfigPanel> createState() => _ChartConfigPanelState();
}

class _ChartConfigPanelState extends State<ChartConfigPanel> {
  final List<TextEditingController> _valueCtrls = <TextEditingController>[];
  int? _boundChartId;
  String _boundFingerprint = '';

  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _syncFromController();
    controller.addListener(_onController);
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
    for (final c in _valueCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    _syncFromController();
  }

  String _fingerprint(VsdxShape chart) {
    final kind = ChartOps.chartKind(chart) ?? '';
    final vals = ChartOps.formatValues(ChartOps.chartValues(chart));
    final cols = ChartOps.formatColors(ChartOps.chartColors(chart));
    return '$kind|$vals|$cols';
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
    while (_valueCtrls.length > values.length) {
      _valueCtrls.removeLast().dispose();
    }
    while (_valueCtrls.length < values.length) {
      _valueCtrls.add(TextEditingController());
    }
    for (var i = 0; i < values.length; i++) {
      final text = ChartOps.formatValues(<double>[values[i]]);
      if (_valueCtrls[i].text != text) {
        _valueCtrls[i].text = text;
      }
    }
    setState(() {});
  }

  void _commitValue(int index) {
    if (index < 0 || index >= _valueCtrls.length) return;
    final raw = _valueCtrls[index].text.trim();
    final v = double.tryParse(raw.replaceAll(',', '.'));
    if (v == null || !v.isFinite) {
      _syncFromController();
      return;
    }
    controller.updateChartItem(index, value: v);
  }

  @override
  Widget build(BuildContext context) {
    final chart = controller.selectedChart;
    if (chart == null) return const SizedBox.shrink();
    final el = EditorL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final kind = ChartOps.chartKind(chart) ?? 'column';
    final values = ChartOps.chartValues(chart);
    final colors = ChartOps.padColors(ChartOps.chartColors(chart), values.length);
    final single = ChartOps.isSingleValueKind(kind);
    final canAdd =
        !single && values.length < ChartOps.maxSeriesItems;
    final canRemove = !single && values.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(el.panelChart, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Text(el.chartType, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        InputDecorator(
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: ChartOps.kindDisplayNames.containsKey(kind)
                  ? kind
                  : 'column',
              isExpanded: true,
              isDense: true,
              style: TextStyle(fontSize: 13, color: scheme.onSurface),
              items: [
                for (final e in ChartOps.kindDisplayNames.entries)
                  DropdownMenuItem(
                    value: e.key,
                    child: Text(
                      el.stencil(e.value),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) controller.setChartKind(v);
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                el.chartItems,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            if (canAdd)
              IconButton(
                tooltip: el.chartAddItem,
                onPressed: controller.addChartItem,
                icon: const Icon(Icons.add_circle_outline, size: 20),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < values.length; i++) ...[
          _ChartItemRow(
            index: i,
            valueController: _valueCtrls[i],
            color: colors[i].value,
            canRemove: canRemove,
            onCommitValue: () => _commitValue(i),
            onColor: (c) =>
                controller.updateChartItem(i, color: VsdxColor(c)),
            onRemove: () => controller.removeChartItem(i),
            valueHint: el.chartValue,
            removeTooltip: el.chartRemoveItem,
          ),
          const SizedBox(height: 6),
        ],
        if (single) ...[
          const SizedBox(height: 4),
          Text(el.chartLevel, style: Theme.of(context).textTheme.labelMedium),
          Slider(
            value: values.first.clamp(0.0, 1.0),
            min: 0,
            max: 1,
            divisions: 100,
            label: '${(values.first.clamp(0.0, 1.0) * 100).round()}%',
            onChangeStart: (_) => controller.beginTransaction(),
            onChanged: (v) {
              controller.updateChartItem(0, value: v, transient: true);
            },
            onChangeEnd: (_) => controller.commitTransaction(),
          ),
        ],
        if (canAdd)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: controller.addChartItem,
              icon: const Icon(Icons.add, size: 18),
              label: Text(el.chartAddItem),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          el.chartConfigHint,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ChartItemRow extends StatelessWidget {
  const _ChartItemRow({
    required this.index,
    required this.valueController,
    required this.color,
    required this.canRemove,
    required this.onCommitValue,
    required this.onColor,
    required this.onRemove,
    required this.valueHint,
    required this.removeTooltip,
  });

  final int index;
  final TextEditingController valueController;
  final int color;
  final bool canRemove;
  final VoidCallback onCommitValue;
  final ValueChanged<int> onColor;
  final VoidCallback onRemove;
  final String valueHint;
  final String removeTooltip;

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
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
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
        const SizedBox(width: 6),
        Text(
          '${index + 1}',
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: valueController,
            decoration: InputDecoration(
              isDense: true,
              hintText: valueHint,
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
      ],
    );
  }
}
