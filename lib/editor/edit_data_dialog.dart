import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vsdx/vsdx.dart';

import '../l10n/editor_l10n.dart';
import 'editor_controller.dart';

/// Open drawio's "Edit Data" (Cmd+M) for shape [shapeId]: edit its Shape Data
/// (Visio `<Section N="Property">`) as name / value rows. Applying commits a
/// single undo step via [EditorController.setShapeProperties]; the original
/// label / prompt / format / type of each unchanged-name row are preserved.
Future<void> showEditDataDialog(
  BuildContext context,
  EditorController controller,
  int shapeId,
) async {
  final shape = controller.currentPage?.findShapeById(shapeId);
  if (shape == null) return;
  final result = await showDialog<List<VsdxUserProperty>>(
    context: context,
    builder: (_) => _EditDataDialog(
      title: shape.name,
      initial: shape.userProperties,
    ),
  );
  if (result != null) controller.setShapeProperties(shapeId, result);
}

class _EditDataDialog extends StatefulWidget {
  const _EditDataDialog({required this.title, required this.initial});

  final String title;
  final List<VsdxUserProperty> initial;

  @override
  State<_EditDataDialog> createState() => _EditDataDialogState();
}

/// One editable name/value row backed by the original property (so we keep any
/// label / prompt / format / type Visio stored on it).
class _Field {
  _Field(VsdxUserProperty? source)
      : source = source,
        name = TextEditingController(text: source?.name ?? ''),
        value = TextEditingController(text: source?.value ?? '');

  final VsdxUserProperty? source;
  final TextEditingController name;
  final TextEditingController value;

  void dispose() {
    name.dispose();
    value.dispose();
  }

  VsdxUserProperty? toProperty() {
    final n = name.text.trim();
    if (n.isEmpty) return null;
    final v = value.text;
    final src = source;
    if (src != null) return src.copyWith(name: n, value: v);
    return VsdxUserProperty(name: n, value: v);
  }
}

class _EditDataDialogState extends State<_EditDataDialog> {
  late final List<_Field> _fields = <_Field>[
    for (final p in widget.initial) _Field(p),
  ];

  @override
  void dispose() {
    for (final f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  void _add() => setState(() => _fields.add(_Field(null)));

  void _removeAt(int i) => setState(() => _fields.removeAt(i).dispose());

  void _apply() {
    final props = <VsdxUserProperty>[];
    for (final f in _fields) {
      final p = f.toProperty();
      if (p != null) props.add(p);
    }
    Navigator.pop(context, props);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final el = EditorL10n.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(el.editData.replaceAll('…', ''))),
          Flexible(
            child: Text(
              widget.title,
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
        child: _fields.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(el.noShapeDataHint),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: _fields.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final f = _fields[i];
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        flex: 2,
                        child: TextField(
                          controller: f.name,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: el.name,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: f.value,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: el.value,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _removeAt(i),
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        tooltip: el.remove,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  );
                },
              ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add, size: 18),
          label: Text(el.addProperty),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(el.cancel),
            ),
            FilledButton(onPressed: _apply, child: Text(el.apply)),
          ],
        ),
      ],
      actionsAlignment: MainAxisAlignment.spaceBetween,
    );
  }
}
