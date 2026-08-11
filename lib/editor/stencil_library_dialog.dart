import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/editor_l10n.dart';
import 'stencil_library_catalog.dart';
import 'stencils.dart';

typedef StencilThumbnailBuilder =
    Widget Function(BuildContext context, Stencil stencil);

class StencilLibraryDialogResult {
  const StencilLibraryDialogResult({
    required this.selectedGroups,
    this.stencil,
  });

  final Set<String> selectedGroups;

  /// Non-null when the user chose a preview tile for immediate insertion.
  final Stencil? stencil;
}

class _StencilSearchEntry {
  const _StencilSearchEntry({
    required this.stencil,
    required this.group,
    required this.category,
    required this.haystack,
    required this.shapeText,
    required this.categoryText,
  });

  final Stencil stencil;
  final StencilGroup group;
  final String category;
  final String haystack;
  final String shapeText;
  final String categoryText;
}

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
  List<_StencilSearchEntry> _searchIndex = const <_StencilSearchEntry>[];
  Map<String, List<_StencilSearchEntry>> _searchByGroup =
      const <String, List<_StencilSearchEntry>>{};
  StencilLibraryNode? _focused;
  _StencilSearchEntry? _selectedPreview;
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
    _searchIndex = <_StencilSearchEntry>[
      for (final group in kStencilGroups)
        for (final stencil in group.stencils)
          _StencilSearchEntry(
            stencil: stencil,
            group: group,
            category: stencilLibraryDisplayName(
              group.name,
              localizeBuiltIn: el.stencilGroup,
            ),
            haystack: <String>[
              stencil.name,
              el.stencil(stencil.name),
              stencilLibraryDisplayName(group.name),
              stencilLibraryDisplayName(
                group.name,
                localizeBuiltIn: el.stencilGroup,
              ),
            ].join(' ').toLowerCase(),
            shapeText: '${stencil.name} ${el.stencil(stencil.name)}'
                .toLowerCase(),
            categoryText: <String>[
              stencilLibraryDisplayName(group.name),
              stencilLibraryDisplayName(
                group.name,
                localizeBuiltIn: el.stencilGroup,
              ),
            ].join(' ').toLowerCase(),
          ),
    ];
    final byGroup = <String, List<_StencilSearchEntry>>{};
    for (final entry in _searchIndex) {
      (byGroup[entry.group.name] ??= <_StencilSearchEntry>[]).add(entry);
    }
    _searchByGroup = byGroup;
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

  List<String> get _queryTokens => _query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList(growable: false);

  bool _matchesTokens(String haystack, List<String> tokens) =>
      tokens.every(haystack.contains);

  List<_StencilSearchEntry> _searchResults(List<String> tokens) {
    final phrase = tokens.join(' ');
    final results = _searchIndex
        .where((entry) => _matchesTokens(entry.haystack, tokens))
        .toList(growable: false);
    int score(_StencilSearchEntry entry) {
      final name = entry.stencil.name.toLowerCase();
      if (name == phrase) return 0;
      if (name.startsWith(phrase)) return 1;
      if (_matchesTokens(entry.shapeText, tokens)) return 2;
      if (_matchesTokens(entry.categoryText, tokens)) return 4;
      return 3;
    }

    results.sort((a, b) {
      final byScore = score(a).compareTo(score(b));
      if (byScore != 0) return byScore;
      return a.stencil.name.toLowerCase().compareTo(
        b.stencil.name.toLowerCase(),
      );
    });
    return results;
  }

  void _selectPreview(_StencilSearchEntry entry) =>
      setState(() => _selectedPreview = entry);

  void _clearQuery() {
    _queryController.clear();
    setState(() {
      _query = '';
      _selectedPreview = null;
    });
  }

  void _chooseStencil(_StencilSearchEntry entry) {
    _selected.add(entry.group.name);
    Navigator.pop(
      context,
      StencilLibraryDialogResult(
        selectedGroups: Set<String>.unmodifiable(_selected),
        stencil: entry.stencil,
      ),
    );
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final rows = _visibleRows();
    final focusedGroups =
        _focused?.descendantGroups.toList() ?? const <StencilGroup>[];
    final queryTokens = _queryTokens;
    final searching = queryTokens.isNotEmpty;
    final previewEntries = searching
        ? _searchResults(queryTokens)
        : <_StencilSearchEntry>[
            for (final group in focusedGroups) ...?_searchByGroup[group.name],
          ];
    final selectedPreview = previewEntries.contains(_selectedPreview)
        ? _selectedPreview
        : previewEntries.isEmpty
        ? null
        : previewEntries.first;
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
            Focus(
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent || previewEntries.isEmpty) {
                  return KeyEventResult.ignored;
                }
                final delta = event.logicalKey == LogicalKeyboardKey.arrowDown
                    ? 1
                    : event.logicalKey == LogicalKeyboardKey.arrowUp
                    ? -1
                    : 0;
                if (delta == 0) return KeyEventResult.ignored;
                final current = selectedPreview == null
                    ? 0
                    : previewEntries.indexOf(selectedPreview);
                final next = (current + delta)
                    .clamp(0, previewEntries.length - 1)
                    .toInt();
                setState(() => _selectedPreview = previewEntries[next]);
                return KeyEventResult.handled;
              },
              child: TextField(
                controller: _queryController,
                autofocus: true,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          key: const ValueKey('stencil-library-clear-search'),
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).deleteButtonTooltip,
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _clearQuery,
                        ),
                  hintText: el.searchShapes,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() {
                  _query = value;
                  _selectedPreview = null;
                }),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) {
                  if (selectedPreview != null) {
                    _chooseStencil(selectedPreview);
                  }
                },
              ),
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
                      previewEntries,
                      selectedPreview: selectedPreview,
                      searching: searching,
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
          onPressed: () => Navigator.pop(
            context,
            StencilLibraryDialogResult(
              selectedGroups: Set<String>.unmodifiable(_selected),
            ),
          ),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }

  List<({StencilLibraryNode node, int depth})> _visibleRows() {
    final tokens = _queryTokens;
    final cache = <String, bool>{};
    bool matches(StencilLibraryNode node) {
      if (tokens.isEmpty) return true;
      final cached = cache[node.key];
      if (cached != null) return cached;
      final ownMatch =
          _matchesTokens(node.label.toLowerCase(), tokens) ||
          node.groups.any(
            (group) => (_searchByGroup[group.name] ?? const []).any(
              (entry) => _matchesTokens(entry.haystack, tokens),
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
      if (tokens.isNotEmpty || _expanded.contains(node.key)) {
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
    List<_StencilSearchEntry> entries, {
    required _StencilSearchEntry? selectedPreview,
    required bool searching,
  }) {
    final groupCount = entries.map((entry) => entry.group.name).toSet().length;
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        searching
                            ? '${el.searchShapes}: ${_query.trim()}'
                            : _focused?.label ?? el.moreShapes,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Text(
                      '${el.categoriesCount(groupCount)} · ${entries.length}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  el.chooseShapeToAddHint,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Icon(
                      searching ? Icons.search_off : Icons.category_outlined,
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
                          mainAxisExtent: 116,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemCount: entries.length,
                    itemBuilder: (context, index) => _buildPreviewTile(
                      scheme,
                      entries[index],
                      index,
                      selected: identical(entries[index], selectedPreview),
                    ),
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selectedPreview == null
                        ? el.chooseShapeToAddHint
                        : '${EditorL10n.of(context).stencil(selectedPreview.stencil.name)}'
                              ' · ${selectedPreview.category}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const ValueKey('stencil-library-add-to-canvas'),
                  onPressed: selectedPreview == null
                      ? null
                      : () => _chooseStencil(selectedPreview),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(el.addShapeToCanvas),
                ),
              ],
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

  Widget _buildPreviewTile(
    ColorScheme scheme,
    _StencilSearchEntry entry,
    int index, {
    required bool selected,
  }) {
    final label = EditorL10n.of(context).stencil(entry.stencil.name);
    return Tooltip(
      message: '$label\n${entry.category}',
      child: Semantics(
        button: true,
        label: label,
        selected: selected,
        child: Material(
          key: ValueKey('stencil-library-preview-tile-$index'),
          color: selected
              ? scheme.secondaryContainer
              : scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            onTap: () => _selectPreview(entry),
            onDoubleTap: () => _chooseStencil(entry),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 5),
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        widget.thumbnailBuilder(context, entry.stencil),
                        Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            key: ValueKey('stencil-library-quick-add-$index'),
                            tooltip: EditorL10n.of(context).addShapeToCanvas,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 26,
                              minHeight: 26,
                            ),
                            icon: Icon(
                              Icons.add_circle,
                              size: 19,
                              color: scheme.primary,
                            ),
                            onPressed: () => _chooseStencil(entry),
                          ),
                        ),
                      ],
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
                  Text(
                    entry.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 8,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
