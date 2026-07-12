import 'package:flutter/material.dart';
import 'package:vsdx/vsdx.dart';

import 'editor_controller.dart';

/// Open drawio's "Edit Link" (Cmd+K) for shape [shapeId]: set or clear the
/// shape's primary hyperlink (Visio `<Section N="Hyperlink">`). A value that
/// starts with `#` is treated as an in-document anchor (e.g. `#Page-2`),
/// everything else as an external address. Applying commits a single undo step
/// via [EditorController.setShapeHyperlinks]; an empty field removes the link.
Future<void> showEditLinkDialog(
  BuildContext context,
  EditorController controller,
  int shapeId,
) async {
  final shape = controller.currentPage?.findShapeById(shapeId);
  if (shape == null) return;
  final result = await showDialog<List<VsdxHyperlink>>(
    context: context,
    builder: (_) => _EditLinkDialog(
      title: shape.name,
      initial: shape.primaryHyperlink,
    ),
  );
  if (result != null) controller.setShapeHyperlinks(shapeId, result);
}

class _EditLinkDialog extends StatefulWidget {
  const _EditLinkDialog({required this.title, this.initial});

  final String title;
  final VsdxHyperlink? initial;

  @override
  State<_EditLinkDialog> createState() => _EditLinkDialogState();
}

class _EditLinkDialogState extends State<_EditLinkDialog> {
  late final TextEditingController _link = TextEditingController(
    text: widget.initial?.address ?? widget.initial?.subAddress ?? '',
  );
  late final TextEditingController _label = TextEditingController(
    text: widget.initial?.description ?? '',
  );

  @override
  void dispose() {
    _link.dispose();
    _label.dispose();
    super.dispose();
  }

  List<VsdxHyperlink> _build() {
    final raw = _link.text.trim();
    if (raw.isEmpty) return const <VsdxHyperlink>[];
    final desc = _label.text.trim();
    final isAnchor = raw.startsWith('#');
    return <VsdxHyperlink>[
      VsdxHyperlink(
        id: widget.initial?.id ?? 0,
        address: isAnchor ? null : raw,
        subAddress: isAnchor ? raw : null,
        description: desc.isEmpty ? null : desc,
        isDefault: true,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasLink = (widget.initial?.effectiveTarget ?? '').isNotEmpty;
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Edit Link')),
          Text(
            widget.title,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _link,
              autofocus: true,
              onSubmitted: (_) => Navigator.pop(context, _build()),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Link',
                hintText: 'https://example.com  or  #Page-2',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Label (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (hasLink)
          TextButton.icon(
            onPressed: () => Navigator.pop(context, const <VsdxHyperlink>[]),
            icon: const Icon(Icons.link_off, size: 18),
            label: const Text('Remove Link'),
          ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _build()),
          child: const Text('Apply'),
        ),
      ],
      actionsAlignment: MainAxisAlignment.start,
    );
  }
}
