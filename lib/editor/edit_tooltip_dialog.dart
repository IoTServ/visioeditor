import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/editor_l10n.dart';
import 'editor_controller.dart';

class _TooltipEditResult {
  const _TooltipEditResult(this.value);

  final String value;
}

/// Opens draw.io's "Edit Tooltip" dialog for [shapeId].
///
/// Applying empty text clears the tooltip. The controller commits the change
/// as one undoable edit and persists it through `User.veTooltip`.
Future<void> showEditTooltipDialog(
  BuildContext context,
  EditorController controller,
  int shapeId,
) async {
  final shape = controller.currentPage?.findShapeById(shapeId);
  if (shape == null) return;
  final result = await showDialog<_TooltipEditResult>(
    context: context,
    builder: (_) => _EditTooltipDialog(
      shapeName: shape.name,
      initialValue: shape.tooltip ?? '',
    ),
  );
  if (result == null) return;
  controller.setShapeTooltip(shapeId, result.value);
}

class _EditTooltipDialog extends StatefulWidget {
  const _EditTooltipDialog({
    required this.shapeName,
    required this.initialValue,
  });

  final String shapeName;
  final String initialValue;

  @override
  State<_EditTooltipDialog> createState() => _EditTooltipDialogState();
}

class _EditTooltipDialogState extends State<_EditTooltipDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _apply() {
    Navigator.pop(context, _TooltipEditResult(_text.text));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final el = EditorL10n.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(el.editTooltip.replaceAll('…', ''))),
          Flexible(
            child: Text(
              widget.shapeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(420, MediaQuery.sizeOf(context).width - 48),
        ),
        child: TextField(
          key: const ValueKey('edit-tooltip-field'),
          controller: _text,
          autofocus: true,
          minLines: 4,
          maxLines: 8,
          decoration: InputDecoration(
            alignLabelWithHint: true,
            labelText: el.tooltipText,
            hintText: el.tooltipHint,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(el.cancel),
        ),
        FilledButton(
          key: const ValueKey('apply-tooltip'),
          onPressed: _apply,
          child: Text(el.apply),
        ),
      ],
    );
  }
}
