import 'package:flutter/material.dart';
import 'package:vsdx/vsdx.dart';

import '../l10n/editor_l10n.dart';
import 'editor_controller.dart';

/// Merge an edited (or cleared) primary hyperlink into [existing] without
/// dropping secondary rows. [editedPrimary] `null` removes only the primary.
@visibleForTesting
List<VsdxHyperlink> mergeEditedPrimaryLink({
  required List<VsdxHyperlink> existing,
  required VsdxHyperlink? editedPrimary,
}) {
  VsdxHyperlink? oldPrimary;
  for (final h in existing) {
    if (h.isDefault) {
      oldPrimary = h;
      break;
    }
  }
  oldPrimary ??= existing.isEmpty ? null : existing.first;
  final secondary = <VsdxHyperlink>[
    for (final h in existing)
      if (oldPrimary == null || h.id != oldPrimary.id)
        h.copyWith(isDefault: false),
  ];
  if (editedPrimary == null) return secondary;
  return <VsdxHyperlink>[
    editedPrimary.copyWith(isDefault: true),
    ...secondary,
  ];
}

/// Dialog result: apply with optional primary (null = remove primary only).
class _LinkEditResult {
  const _LinkEditResult(this.primary);
  final VsdxHyperlink? primary;
}

/// Open drawio's "Edit Link" (Cmd+K) for shape [shapeId]: set or clear the
/// shape's primary hyperlink (Visio `<Section N="Hyperlink">`). A value that
/// starts with `#` is treated as an in-document anchor (e.g. `#Page-2`),
/// everything else as an external address. Applying commits a single undo step
/// via [EditorController.setShapeHyperlinks]. Secondary hyperlink rows are
/// preserved when editing or removing the primary.
Future<void> showEditLinkDialog(
  BuildContext context,
  EditorController controller,
  int shapeId,
) async {
  final shape = controller.currentPage?.findShapeById(shapeId);
  if (shape == null) return;
  final existing = List<VsdxHyperlink>.of(shape.hyperlinks);
  final result = await showDialog<_LinkEditResult>(
    context: context,
    builder: (_) => _EditLinkDialog(
      title: shape.name,
      initial: shape.primaryHyperlink,
    ),
  );
  if (result == null) return; // cancelled
  controller.setShapeHyperlinks(
    shapeId,
    mergeEditedPrimaryLink(
      existing: existing,
      editedPrimary: result.primary,
    ),
  );
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

  VsdxHyperlink? _buildPrimary() {
    final raw = _link.text.trim();
    if (raw.isEmpty) return null;
    final desc = _label.text.trim();
    final isAnchor = raw.startsWith('#');
    final base = widget.initial;
    return VsdxHyperlink(
      id: base?.id ?? 0,
      address: isAnchor ? null : raw,
      subAddress: isAnchor ? raw : null,
      description: desc.isEmpty ? null : desc,
      isDefault: true,
      // Preserve Visio ExtraInfo / Frame / flags when only URL/label change.
      extraInfo: base?.extraInfo,
      frame: base?.frame,
      newWindow: base?.newWindow ?? false,
      invisible: base?.invisible ?? false,
      sortKey: base?.sortKey,
      addressFormula: base?.addressFormula,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final el = EditorL10n.of(context);
    final hasLink = (widget.initial?.effectiveTarget ?? '').isNotEmpty;
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(el.editLink.replaceAll('…', ''))),
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
              onSubmitted: (_) => Navigator.pop(
                context,
                _LinkEditResult(_buildPrimary()),
              ),
              decoration: InputDecoration(
                isDense: true,
                labelText: el.link,
                hintText: el.linkHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _label,
              decoration: InputDecoration(
                isDense: true,
                labelText: el.labelOptional,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (hasLink)
          TextButton.icon(
            onPressed: () =>
                Navigator.pop(context, const _LinkEditResult(null)),
            icon: const Icon(Icons.link_off, size: 18),
            label: Text(el.removeLink),
          )
        else
          const SizedBox.shrink(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(el.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _LinkEditResult(_buildPrimary()),
              ),
              child: Text(el.apply),
            ),
          ],
        ),
      ],
      actionsAlignment: MainAxisAlignment.spaceBetween,
    );
  }
}
