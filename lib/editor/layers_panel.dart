import 'package:flutter/material.dart';
import 'package:vsdx/vsdx.dart';

import 'editor_controller.dart';

/// draw.io-style floating Layers panel (visibility / lock / print / assign).
class LayersPanel extends StatelessWidget {
  const LayersPanel({
    required this.controller,
    this.onClose,
    this.width = 300,
    super.key,
  });

  final EditorController controller;
  final VoidCallback? onClose;
  final double width;

  Future<void> _rename(BuildContext context, VsdxLayer layer) async {
    final textController = TextEditingController(text: layer.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename layer'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, textController.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    textController.dispose();
    if (result != null) controller.renameLayer(layer.id, result);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      color: scheme.surface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final layers = controller.currentPage?.layers ?? const <VsdxLayer>[];
          return SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                  child: Row(
                    children: [
                      Text('Layers', style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      if (onClose != null)
                        IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: onClose,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
                if (layers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Text(
                      'No layers yet. Add one to organise shapes '
                      '(visibility / lock / print).',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final l in layers)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          l.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Rename',
                                        icon: const Icon(Icons.edit_outlined,
                                            size: 18),
                                        onPressed: () => _rename(context, l),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      IconButton(
                                        tooltip: 'Delete layer',
                                        icon: const Icon(Icons.delete_outline,
                                            size: 18),
                                        onPressed: () =>
                                            controller.deleteLayer(l.id),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 0,
                                    children: [
                                      FilterChip(
                                        label: const Text('Visible'),
                                        selected: l.visible,
                                        onSelected: (_) => controller
                                            .toggleLayerVisibility(l.id),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      FilterChip(
                                        label: const Text('Locked'),
                                        selected: l.locked,
                                        onSelected: (_) => controller
                                            .toggleLayerLocked(l.id),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      FilterChip(
                                        label: const Text('Print'),
                                        selected: l.print,
                                        onSelected: (_) =>
                                            controller.toggleLayerPrint(l.id),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      if (controller.hasSelection)
                                        ActionChip(
                                          label: const Text('Assign sel.'),
                                          onPressed: () => controller
                                              .assignSelectionToLayer(l.id),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                  child: OutlinedButton.icon(
                    onPressed: () => controller.addLayer(
                      assignSelection: controller.hasSelection,
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(
                      controller.hasSelection
                          ? 'Add layer (with selection)'
                          : 'Add layer',
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
