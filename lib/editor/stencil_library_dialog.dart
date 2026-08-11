import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/editor_l10n.dart';
import 'stencil_library_catalog.dart';
import 'stencils.dart';

typedef StencilThumbnailBuilder =
    Widget Function(BuildContext context, Stencil stencil);

/// Two-pane library browser: checkable category tree and live shape preview.
class StencilLibraryDialog extends StatefulWidget {
  const StencilLibraryDialog({
    required this.initialSelection,
    required this.thumbnailBuilder,
    super.key,
  });

  final Set<String> initialSelection;
  final StencilThumbnailBuilder thumbnailBuilder;

  @override
  State<StencilLibraryDialog> createState() => _StencilLibraryDialogState();
}

class _StencilLibraryDialogState extends State<StencilLibraryDialog> {
  final TextEditingController _queryController = TextEditingController();
  late final Set<String> _selected = Set<String>.from(widget.initialSelection);
  final Set<String> _expanded = <String>{};
  List<StencilLibraryNode> _tree = const <StencilLibraryNode>[];
  StencilLibraryNode? _focused;
  String _query = '';
  String? _localeTag;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    if (_localeTag == localeTag) return;
    _localeTag = localeTag;
    final previousFocus = _focused?.key;
    final el = EditorL10n.of(context);
    _tree = buildStencilLibraryTree(
      kStencilGroups,
      localizeBuiltIn: el.stencilGroup,
    );
    _focused = _findNode(previousFocus) ?? (_tree.isEmpty ? null : _tree.first);
  }

  StencilLibraryNode? _findNode(String? key) {
    if (key == null) return null;
    StencilLibraryNode? visit(StencilLibraryNode node) {
      if (node.key == key) return node;
      for (final child in node.children) {
        final found = visit(child);
        if (found != null) return found;
      }
      return null;
    }

    for (final node in _tree) {
      final found = visit(node);
      if (found != null) return found;
    }
    return null;
  }

  Iterable<StencilLibraryNode> get _allNodes sync* {
    Iterable<StencilLibraryNode> visit(StencilLibraryNode node) sync* {
      yield node;
      for (final child in node.children) {
        yield* visit(child);
      }
    }

    for (final node in _tree) {
      yield* visit(node);
    }
  }

  void _toggleExpanded(StencilLibraryNode node) => setState(() {
    _focused = node;
    if (!_expanded.remove(node.key)) _expanded.add(node.key);
  });

  void _toggleSelected(StencilLibraryNode node) => setState(() {
    final names = node.descendantGroups.map((group) => group.name).toSet();
    if (names.every(_selected.contains)) {
      _selected.removeAll(names);
    } else {
      _selected.addAll(names);
    }
  });

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final rows = _visibleRows(el);
    final focusedGroups =
        _focused?.descendantGroups.toList() ?? const <StencilGroup>[];
    final previewStencils = <Stencil>[
      for (final group in focusedGroups) ...group.stencils,
    ];
    final mediaSize = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(1000.0, math.max(320.0, mediaSize.width - 64));
    final dialogHeight = math.min(
      680.0,
      math.max(300.0, mediaSize.height - 180),
    );
    final treeWidth = math.min(340.0, math.max(220.0, dialogWidth * 0.38));

    return AlertDialog(
      insetPadding: const EdgeInsets.all(24),
      title: Row(
        children: [
          Expanded(child: Text(el.moreShapes)),
          Text(
            '${_selected.length}/${kStencilGroups.length}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            TextField(
              controller: _queryController,
              autofocus: true,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: el.searchShapes,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: treeWidth,
                    child: _buildTreePane(scheme, el, rows),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildPreviewPane(
                      scheme,
                      el,
                      focusedGroups,
                      previewStencils,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }

  List<({StencilLibraryNode node, int depth})> _visibleRows(EditorL10n el) {
    final normalized = _query.trim().toLowerCase();
    final cache = <String, bool>{};
    bool matches(StencilLibraryNode node) {
      if (normalized.isEmpty) return true;
      final cached = cache[node.key];
      if (cached != null) return cached;
      final ownMatch =
          node.label.toLowerCase().contains(normalized) ||
          node.groups.any(
            (group) => group.stencils.any(
              (stencil) => el.stencilMatches(stencil.name, normalized),
            ),
          );
      final value = ownMatch || node.children.any(matches);
      cache[node.key] = value;
      return value;
    }

    final rows = <({StencilLibraryNode node, int depth})>[];
    void add(StencilLibraryNode node, int depth) {
      if (!matches(node)) return;
      rows.add((node: node, depth: depth));
      if (normalized.isNotEmpty || _expanded.contains(node.key)) {
        for (final child in node.children) {
          add(child, depth + 1);
        }
      }
    }

    for (final node in _tree) {
      add(node, 0);
    }
    return rows;
  }

  Widget _buildTreePane(
    ColorScheme scheme,
    EditorL10n el,
    List<({StencilLibraryNode node, int depth})> rows,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    el.categoriesCount(rows.length),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                _headerButton(
                  icon: Icons.unfold_more,
                  tooltip: el.expandAll,
                  onPressed: () => setState(() {
                    _expanded.addAll(
                      _allNodes
                          .where((node) => node.children.isNotEmpty)
                          .map((node) => node.key),
                    );
                  }),
                ),
                _headerButton(
                  icon: Icons.unfold_less,
                  tooltip: el.collapseAll,
                  onPressed: () => setState(_expanded.clear),
                ),
                _headerButton(
                  icon: Icons.select_all,
                  tooltip: el.selectAll,
                  onPressed: rows.isEmpty
                      ? null
                      : () => setState(() {
                          for (final row in rows) {
                            _selected.addAll(
                              row.node.descendantGroups.map(
                                (group) => group.name,
                              ),
                            );
                          }
                        }),
                ),
                _headerButton(
                  icon: Icons.deselect,
                  tooltip: el.none,
                  onPressed: rows.isEmpty
                      ? null
                      : () => setState(() {
                          for (final row in rows) {
                            _selected.removeAll(
                              row.node.descendantGroups.map(
                                (group) => group.name,
                              ),
                            );
                          }
                        }),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              key: const ValueKey('stencil-library-tree'),
              itemCount: rows.length,
              itemBuilder: (context, index) =>
                  _buildTreeRow(scheme, rows[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPane(
    ColorScheme scheme,
    EditorL10n el,
    List<StencilGroup> groups,
    List<Stencil> stencils,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 9),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _focused?.label ?? el.moreShapes,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  '${el.categoriesCount(groups.length)} · ${stencils.length}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: stencils.isEmpty
                ? Center(
                    child: Icon(
                      Icons.category_outlined,
                      size: 48,
                      color: scheme.outline,
                    ),
                  )
                : GridView.builder(
                    key: const ValueKey('stencil-library-preview'),
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 116,
                          mainAxisExtent: 96,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemCount: stencils.length,
                    itemBuilder: (context, index) =>
                        _buildPreviewTile(scheme, stencils[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _headerButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
    );
  }

  Widget _buildTreeRow(
    ColorScheme scheme,
    ({StencilLibraryNode node, int depth}) row,
  ) {
    final node = row.node;
    final names = node.descendantGroups.map((group) => group.name).toSet();
    final selectedCount = names.where(_selected.contains).length;
    final bool? checked = selectedCount == 0
        ? false
        : selectedCount == names.length
        ? true
        : null;
    final focused = _focused?.key == node.key;
    return Material(
      key: ValueKey('stencil-library-node-${node.key}'),
      color: focused ? scheme.secondaryContainer : Colors.transparent,
      child: InkWell(
        onTap: () {
          if (node.children.isEmpty) {
            setState(() => _focused = node);
          } else {
            _toggleExpanded(node);
          }
        },
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: 4 + row.depth * 16,
            end: 6,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: node.children.isEmpty
                    ? const SizedBox()
                    : IconButton(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          _expanded.contains(node.key)
                              ? Icons.expand_more
                              : Icons.chevron_right,
                          size: 18,
                        ),
                        onPressed: () => _toggleExpanded(node),
                      ),
              ),
              Checkbox(
                tristate: true,
                value: checked,
                visualDensity: VisualDensity.compact,
                onChanged: (_) => _toggleSelected(node),
              ),
              Expanded(
                child: Text(
                  node.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${node.shapeCount}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewTile(ColorScheme scheme, Stencil stencil) {
    final label = EditorL10n.of(context).stencil(stencil.name);
    return Tooltip(
      message: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 7, 6, 5),
          child: Column(
            children: [
              Expanded(
                child: SizedBox.expand(
                  child: widget.thumbnailBuilder(context, stencil),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
