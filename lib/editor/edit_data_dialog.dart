import 'package:flutter/material.dart';
import 'package:vsdx/vsdx.dart';

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
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Edit Data')),
          Text(
            widget.title,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: _fields.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No shape data. Add a property to get started.'),
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
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: f.name,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: f.value,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Value',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _removeAt(i),
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        tooltip: 'Remove',
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
          label: const Text('Add Property'),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(onPressed: _apply, child: const Text('Apply')),
          ],
        ),
      ],
      actionsAlignment: MainAxisAlignment.spaceBetween,
    );
  }
}
