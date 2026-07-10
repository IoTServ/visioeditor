import 'dart:async';
import 'dart:convert';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vsdx/vsdx.dart';

import 'editor/editor_controller.dart';
import 'editor/editor_workspace.dart';
import 'editor/page_canvas.dart';
import 'editor/stencils.dart';
import 'io/document_io.dart';
import 'io/image_export.dart';
import 'io/pdf_export.dart';
import 'io/recent_files.dart';

void main() {
  runApp(const VisioEditorApp());
}

class VisioEditorApp extends StatelessWidget {
  const VisioEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1F6FEB);
    return MaterialApp(
      title: 'Editor for Visio Diagrams',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: seed,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: seed,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const EditorHomePage(),
    );
  }
}

class EditorHomePage extends StatefulWidget {
  const EditorHomePage({super.key});

  @override
  State<EditorHomePage> createState() => _EditorHomePageState();
}

class _EditorHomePageState extends State<EditorHomePage> {
  static const List<String> _examples = <String>[
    'test1.vsdx',
    'test3_house.vsdx',
    'test4_connectors.vsdx',
    'test10_nested_shapes.vsdx',
    'test11_rotate.vsdx',
    'test12_colors.vsdx',
  ];

  /// Channel over which macOS hands us documents opened from Finder
  /// (double-click / "Open With") or the `open` command.
  static const MethodChannel _fileChannel = MethodChannel('visioeditor/files');

  final EditorWorkspace _workspace = EditorWorkspace();
  final RecentFiles _recentFiles = RecentFiles();
  List<String> _recents = const <String>[];
  bool _dragging = false;
  bool _showStencils = false;

  EditorController? get _c => _workspace.active;

  @override
  void initState() {
    super.initState();
    _workspace.addListener(_onChanged);
    _recentFiles.load().then((r) {
      if (mounted) setState(() => _recents = r);
    });
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      _fileChannel.setMethodCallHandler(_onNativeMethod);
      // Tell the native side we're listening so it can flush any file that was
      // opened before the Dart isolate was ready (cold launch from Finder).
      unawaited(_fileChannel.invokeMethod<void>('ready').catchError((Object _) {}));
    }
  }

  /// Handle calls pushed from the native side (currently only `openFiles`).
  Future<dynamic> _onNativeMethod(MethodCall call) async {
    if (call.method == 'openFiles') {
      final args = call.arguments;
      if (args is List) {
        for (final p in args) {
          if (p is String && hasVisioExtension(p)) await _openPath(p);
        }
      }
    }
    return null;
  }

  @override
  void dispose() {
    _workspace.removeListener(_onChanged);
    _workspace.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _addRecent(String? path) async {
    if (path == null) return;
    final r = await _recentFiles.add(path);
    if (mounted) setState(() => _recents = r);
  }

  /// Open bytes in a NEW tab; drops the tab and reports if parsing failed.
  Future<void> _openBytes(
    Uint8List bytes, {
    String? path,
    String? name,
  }) async {
    final c = await _workspace.openBytes(bytes, path: path, name: name);
    if (c.error != null) {
      _snack('Could not open file: ${c.error}');
      final i = _workspace.indexOf(c);
      if (i >= 0) _workspace.closeAt(i);
      return;
    }
    if (path != null) await _addRecent(path);
  }

  Future<void> _open() async {
    final picked = await pickVisioFile();
    if (picked == null) return;
    await _openBytes(picked.bytes, path: picked.path, name: picked.name);
  }

  Future<void> _openPath(String path) async {
    try {
      final picked = await readDroppedFile(path);
      await _openBytes(picked.bytes, path: picked.path, name: picked.name);
    } catch (e) {
      _snack('Could not open $path');
    }
  }

  Future<void> _openExample(String assetName) async {
    try {
      final data = await rootBundle.load('assets/examples/$assetName');
      await _openBytes(data.buffer.asUint8List(), name: assetName);
    } catch (e) {
      _snack('Could not open example $assetName');
    }
  }

  Future<void> _onDrop(DropDoneDetails details) async {
    setState(() => _dragging = false);
    for (final f in details.files) {
      if (!hasVisioExtension(f.path)) continue;
      final picked = await readDroppedFile(f.path);
      await _openBytes(picked.bytes, path: picked.path, name: picked.name);
    }
  }

  Future<bool> _confirmDiscard(EditorController c) async {
    if (!c.isDirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: Text('“${c.fileName ?? 'Untitled'}” has unsaved changes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _newDoc() => _workspace.newDocument();

  Future<void> _closeTab(int index) async {
    if (index < 0 || index >= _workspace.docs.length) return;
    if (await _confirmDiscard(_workspace.docs[index])) {
      _workspace.closeAt(index);
    }
  }

  Future<void> _save() async {
    final c = _c;
    if (c == null || !c.hasDocument) return;
    var path = c.filePath;
    path ??= await pickSaveLocation(suggestedName: c.fileName ?? 'drawing.vsdx');
    if (path == null) return;
    try {
      final bytes = c.exportToBytes();
      await writeBytesToFile(path, bytes);
      c.markSaved(bytes, path: path);
      await _addRecent(path);
      _snack('Saved to $path');
    } catch (e) {
      _snack('Save failed: $e');
    }
  }

  Future<void> _saveAs() async {
    final c = _c;
    if (c == null || !c.hasDocument) return;
    final path =
        await pickSaveLocation(suggestedName: c.fileName ?? 'drawing.vsdx');
    if (path == null) return;
    try {
      final bytes = c.exportToBytes();
      await writeBytesToFile(path, bytes);
      c.markSaved(bytes, path: path);
      await _addRecent(path);
      _snack('Saved to $path');
    } catch (e) {
      _snack('Save failed: $e');
    }
  }

  Future<void> _exportSvg() async {
    final c = _c;
    final doc = c?.document;
    if (c == null || doc == null) return;
    final path = await pickExportLocation(
      ext: 'svg',
      suggestedName: '${baseName(c.fileName)}.svg',
    );
    if (path == null) return;
    try {
      final svg = VsdxToSvgSerializer().serializeDocument(doc);
      await writeBytesToFile(path, Uint8List.fromList(utf8.encode(svg)));
      _snack('Exported SVG to $path');
    } catch (e) {
      _snack('SVG export failed: $e');
    }
  }

  Future<void> _exportPng() async {
    final c = _c;
    final doc = c?.document;
    final page = c?.currentPage;
    if (c == null || doc == null || page == null) return;
    final path = await pickExportLocation(
      ext: 'png',
      suggestedName: '${baseName(c.fileName)}.png',
    );
    if (path == null) return;
    try {
      final bytes =
          await renderPageToPng(page, theme: doc.theme, images: doc.images);
      if (bytes == null) {
        _snack('PNG export failed');
        return;
      }
      await writeBytesToFile(path, bytes);
      _snack('Exported PNG to $path');
    } catch (e) {
      _snack('PNG export failed: $e');
    }
  }

  Future<void> _renamePage(int index) async {
    final c = _c;
    final doc = c?.document;
    if (c == null || doc == null || index < 0 || index >= doc.pages.length) {
      return;
    }
    final textController =
        TextEditingController(text: doc.pages[index].name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename page'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Page name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, textController.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result != null) c.renamePageAt(index, result);
    textController.dispose();
  }

  Future<void> _showLayers() async {
    final c = _c;
    if (c == null || !c.hasLayers) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Layers'),
        content: SizedBox(
          width: 320,
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) {
              final layers = c.currentPage?.layers ?? const [];
              if (layers.isEmpty) {
                return const Text('No layers on this page.');
              }
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final l in layers)
                      SwitchListTile(
                        dense: true,
                        title: Text(l.name),
                        value: l.visible,
                        onChanged: (_) => c.toggleLayerVisibility(l.id),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportPdf() async {
    final c = _c;
    final doc = c?.document;
    if (c == null || doc == null) return;
    final path = await pickExportLocation(
      ext: 'pdf',
      suggestedName: '${baseName(c.fileName)}.pdf',
    );
    if (path == null) return;
    try {
      final bytes = await exportDocumentToPdf(doc);
      await writeBytesToFile(path, bytes);
      _snack('Exported PDF to $path');
    } catch (e) {
      _snack('PDF export failed: $e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _newDoc,
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true): _open,
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () {
          if (_workspace.hasDocs) _closeTab(_workspace.activeIndex);
        },
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          if (c != null && c.hasDocument) _save();
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () {
          if (c != null && c.canUndo) c.undo();
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            () {
          if (c != null && c.canRedo) c.redo();
        },
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true): () {
          if (c != null && c.hasSelection) c.duplicateSelection();
        },
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () {
          if (c != null && c.hasSelection) c.copySelection();
        },
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () {
          if (c != null && c.hasClipboard) c.paste();
        },
        const SingleActivator(LogicalKeyboardKey.keyX, meta: true): () {
          if (c != null && c.hasSelection) c.cut();
        },
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): () {
          if (c != null && c.hasDocument) c.selectAll();
        },
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true, shift: true):
            () {
          if (c != null && c.hasSelection) c.bringSelectionToFront();
        },
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true, shift: true):
            () {
          if (c != null && c.hasSelection) c.sendSelectionToBack();
        },
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true, alt: true):
            () {
          if (c != null && c.hasSelection) c.copyStyle();
        },
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true, alt: true):
            () {
          if (c != null && c.hasStyleClipboard) c.pasteStyle();
        },
        const SingleActivator(LogicalKeyboardKey.keyG, meta: true): () {
          if (c != null && c.canGroup) c.groupSelection();
        },
        const SingleActivator(LogicalKeyboardKey.keyU, meta: true, shift: true):
            () {
          if (c != null && c.canUngroup) c.ungroupSelection();
        },
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Editor for Visio Diagrams'),
          actions: [
            if (c != null) ...[
              IconButton(
                onPressed: c.canUndo ? c.undo : null,
                icon: const Icon(Icons.undo),
                tooltip: 'Undo',
              ),
              IconButton(
                onPressed: c.canRedo ? c.redo : null,
                icon: const Icon(Icons.redo),
                tooltip: 'Redo',
              ),
              IconButton(
                onPressed: () => setState(() => _showStencils = !_showStencils),
                icon: const Icon(Icons.category_outlined),
                isSelected: _showStencils,
                tooltip: 'Shapes palette',
              ),
              IconButton(
                onPressed: c.toggleGrid,
                icon: Icon(c.showGrid ? Icons.grid_on : Icons.grid_off),
                tooltip: 'Toggle grid',
              ),
              if (c.hasLayers)
                IconButton(
                  onPressed: _showLayers,
                  icon: const Icon(Icons.layers_outlined),
                  tooltip: 'Layers',
                ),
              IconButton(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                tooltip: 'Save (Cmd+S)',
              ),
            ],
            IconButton(
              onPressed: _newDoc,
              icon: const Icon(Icons.note_add_outlined),
              tooltip: 'New drawing (Cmd+N)',
            ),
            IconButton(
              onPressed: _open,
              icon: const Icon(Icons.folder_open_outlined),
              tooltip: 'Open a Visio drawing (Cmd+O)',
            ),
            if (_recents.isNotEmpty)
              PopupMenuButton<String>(
                icon: const Icon(Icons.history),
                tooltip: 'Recent files',
                onSelected: _openPath,
                itemBuilder: (context) => [
                  for (final p in _recents)
                    PopupMenuItem<String>(
                      value: p,
                      child: Text(
                        p.split(RegExp(r'[/\\]')).last,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            if (c != null)
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (value) {
                  switch (value) {
                    case 'saveAs':
                      _saveAs();
                    case 'exportSvg':
                      _exportSvg();
                    case 'exportPng':
                      _exportPng();
                    case 'exportPdf':
                      _exportPdf();
                    case 'selectAll':
                      c.selectAll();
                    case 'copyStyle':
                      c.copyStyle();
                    case 'pasteStyle':
                      c.pasteStyle();
                    case 'snap':
                      c.toggleSnap();
                    case 'close':
                      _closeTab(_workspace.activeIndex);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem<String>(
                    value: 'selectAll',
                    child: Text('Select All (Cmd+A)'),
                  ),
                  PopupMenuItem<String>(
                    value: 'copyStyle',
                    enabled: c.hasSelection,
                    child: const Text('Copy Style (Cmd+Alt+C)'),
                  ),
                  PopupMenuItem<String>(
                    value: 'pasteStyle',
                    enabled: c.hasStyleClipboard && c.hasSelection,
                    child: const Text('Paste Style (Cmd+Alt+V)'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    value: 'saveAs',
                    child: Text('Save As…'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'exportSvg',
                    child: Text('Export as SVG…'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'exportPng',
                    child: Text('Export as PNG…'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'exportPdf',
                    child: Text('Export as PDF…'),
                  ),
                  CheckedPopupMenuItem<String>(
                    value: 'snap',
                    checked: c.snapToGrid,
                    child: const Text('Snap to grid'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'close',
                    child: Text('Close tab (Cmd+W)'),
                  ),
                ],
              ),
          ],
          bottom: _workspace.hasDocs ? _tabBar() : null,
        ),
        body: DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: _onDrop,
          child: Stack(
            children: [
              Positioned.fill(child: _buildBody(c)),
              if (_dragging) Positioned.fill(child: _dropOverlay(context)),
            ],
          ),
        ),
        bottomNavigationBar: (c != null && c.hasDocument)
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [_pageTabs(c), _statusBar(c)],
              )
            : null,
      ),
    );
  }

  Widget _statusBar(EditorController c) {
    final scheme = Theme.of(context).colorScheme;
    final page = c.currentPage;
    final selCount = c.selection.length;
    final style = TextStyle(fontSize: 11, color: scheme.onSurfaceVariant);
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SizedBox(
        height: 24,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (page != null) ...[
                Icon(Icons.crop_free, size: 13, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('${_trimNum(page.widthInches)} × '
                    '${_trimNum(page.heightInches)} in', style: style),
                const SizedBox(width: 16),
                Text('Page ${c.currentPageIndex + 1} of ${c.pageCount}',
                    style: style),
              ],
              const Spacer(),
              if (c.isDirty) ...[
                Text('Unsaved', style: style),
                const SizedBox(width: 12),
              ],
              Text(selCount == 0 ? 'No selection' : '$selCount selected',
                  style: style),
            ],
          ),
        ),
      ),
    );
  }

  /// Format an inch value without trailing zeros (e.g. 8.5, 11, 8.27).
  static String _trimNum(double v) {
    final r = (v * 100).round() / 100;
    return r == r.roundToDouble() ? r.toInt().toString() : '$r';
  }

  PreferredSizeWidget _tabBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(40),
      child: Container(
        height: 40,
        alignment: Alignment.centerLeft,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: _workspace.docs.length,
          itemBuilder: (context, i) {
            final doc = _workspace.docs[i];
            return _DocTab(
              label: doc.fileName ?? 'Untitled',
              dirty: doc.isDirty,
              active: i == _workspace.activeIndex,
              onTap: () => _workspace.setActive(i),
              onClose: () => _closeTab(i),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(EditorController? c) {
    if (c == null) {
      return _EmptyState(
        onOpen: _open,
        onNew: _newDoc,
        examples: _examples,
        onOpenExample: _openExample,
      );
    }
    if (c.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!c.hasDocument || c.currentPage == null) {
      return _EmptyState(
        onOpen: _open,
        onNew: _newDoc,
        examples: _examples,
        onOpenExample: _openExample,
      );
    }
    return Row(
      children: [
        _ToolStrip(controller: c),
        const VerticalDivider(width: 1),
        if (_showStencils) ...[
          _StencilPanel(controller: c),
          const VerticalDivider(width: 1),
        ],
        Expanded(
          child: PageCanvas(controller: c),
        ),
        if (c.hasSelection) ...[
          const VerticalDivider(width: 1),
          _PropertyPanel(controller: c),
        ],
      ],
    );
  }

  Widget _dropOverlay(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: ColoredBox(
        color: scheme.primary.withValues(alpha: 0.10),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.primary, width: 2),
            ),
            child: const Text('Drop to open', style: TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );
  }

  Widget _pageTabs(EditorController c) {
    return Material(
      elevation: 8,
      child: SizedBox(
        height: 46,
        child: Row(
          children: [
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: c.pageCount,
                itemBuilder: (context, i) {
                  final page = c.document!.pages[i];
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
                    child: GestureDetector(
                      onDoubleTap: () => _renamePage(i),
                      child: ChoiceChip(
                        label: Text(page.name),
                        selected: i == c.currentPageIndex,
                        onSelected: (_) => c.selectPage(i),
                        tooltip: 'Double-click to rename',
                      ),
                    ),
                  );
                },
              ),
            ),
            IconButton(
              onPressed: c.addPage,
              icon: const Icon(Icons.add),
              tooltip: 'Add page',
            ),
            IconButton(
              onPressed: c.duplicateCurrentPage,
              icon: const Icon(Icons.copy_all_outlined),
              tooltip: 'Duplicate page',
            ),
            IconButton(
              onPressed: c.pageCount > 1 ? c.deleteCurrentPage : null,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete page',
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

/// A single open-file tab in the top tab bar.
class _DocTab extends StatelessWidget {
  const _DocTab({
    required this.label,
    required this.dirty,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final String label;
  final bool dirty;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Material(
        color: active ? scheme.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dirty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.circle, size: 8, color: scheme.primary),
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Close tab',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onOpen,
    required this.onNew,
    required this.examples,
    required this.onOpenExample,
  });

  final VoidCallback onOpen;
  final VoidCallback onNew;
  final List<String> examples;
  final void Function(String assetName) onOpenExample;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_tree_outlined, size: 72, color: scheme.primary),
          const SizedBox(height: 20),
          const Text(
            'Editor for Visio Diagrams',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a new drawing, or drag & drop / open .vsdx files '
            '(each opens in its own tab).',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: onNew,
                icon: const Icon(Icons.note_add_outlined),
                label: const Text('New drawing'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Open Visio drawing'),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text('Or try a sample:',
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in examples)
                  ActionChip(
                    avatar: const Icon(Icons.description_outlined, size: 18),
                    label: Text(e.replaceAll('.vsdx', '')),
                    onPressed: () => onOpenExample(e),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Left-hand vertical tool palette.
class _ToolStrip extends StatelessWidget {
  const _ToolStrip({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget tool(EditorTool t, IconData icon, String tip) {
      final active = controller.tool == t;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        child: Material(
          color: active ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: IconButton(
            onPressed: () => controller.setTool(t),
            icon: Icon(icon),
            tooltip: tip,
            color: active ? cs.onPrimaryContainer : null,
          ),
        ),
      );
    }

    return ColoredBox(
      color: cs.surface,
      child: SizedBox(
        width: 56,
        child: Column(
          children: [
            const SizedBox(height: 8),
            tool(EditorTool.select, Icons.near_me_outlined, 'Select / move'),
            tool(EditorTool.rectangle, Icons.crop_square, 'Rectangle'),
            tool(EditorTool.ellipse, Icons.circle_outlined, 'Ellipse'),
            tool(EditorTool.line, Icons.horizontal_rule, 'Line'),
            tool(EditorTool.connector, Icons.timeline, 'Connector (glue)'),
          ],
        ),
      ),
    );
  }
}

/// Left-hand shapes palette; clicking a stencil drops it on the current page.
class _StencilPanel extends StatelessWidget {
  const _StencilPanel({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 168,
      child: ColoredBox(
        color: scheme.surface,
        child: ListView(
          padding: const EdgeInsets.all(8),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
              child: Text('Shapes',
                  style: Theme.of(context).textTheme.labelLarge),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in kStencils)
                  Tooltip(
                    message: s.name,
                    child: InkWell(
                      onTap: () => controller.addShapeFromBuilder(s.build),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 64,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(s.icon, size: 24),
                            const SizedBox(height: 4),
                            Text(
                              s.name,
                              style: const TextStyle(fontSize: 9),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Right-hand inspector for the current selection (fill / line / delete).
class _PropertyPanel extends StatelessWidget {
  const _PropertyPanel({required this.controller});

  final EditorController controller;

  static const List<int> _swatches = <int>[
    0xFFFFFFFF,
    0xFF000000,
    0xFFE53935,
    0xFF43A047,
    0xFF1E88E5,
    0xFFFDD835,
    0xFFFB8C00,
    0xFF8E24AA,
  ];

  @override
  Widget build(BuildContext context) {
    final count = controller.selection.length;
    return SizedBox(
      width: 232,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '$count shape${count == 1 ? '' : 's'} selected',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _iconBtn(Icons.flip_to_front, 'Bring to front',
                  controller.bringSelectionToFront),
              _iconBtn(Icons.flip_to_back, 'Send to back',
                  controller.sendSelectionToBack),
              IconButton(
                onPressed:
                    controller.canGroup ? controller.groupSelection : null,
                icon: const Icon(Icons.group_work_outlined),
                tooltip: 'Group (Cmd+G)',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed:
                    controller.canUngroup ? controller.ungroupSelection : null,
                icon: const Icon(Icons.call_split),
                tooltip: 'Ungroup (Cmd+Shift+U)',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (count >= 2) ...[
            _section(context, 'Align'),
            Wrap(
              children: [
                _iconBtn(Icons.align_horizontal_left, 'Align left',
                    controller.alignLeft),
                _iconBtn(Icons.align_horizontal_center, 'Center horizontally',
                    controller.alignCenterH),
                _iconBtn(Icons.align_horizontal_right, 'Align right',
                    controller.alignRight),
                _iconBtn(Icons.align_vertical_top, 'Align top',
                    controller.alignTop),
                _iconBtn(Icons.align_vertical_center, 'Center vertically',
                    controller.alignMiddle),
                _iconBtn(Icons.align_vertical_bottom, 'Align bottom',
                    controller.alignBottom),
                if (count >= 3) ...[
                  _iconBtn(Icons.horizontal_distribute, 'Distribute horizontally',
                      controller.distributeHorizontally),
                  _iconBtn(Icons.vertical_distribute, 'Distribute vertically',
                      controller.distributeVertically),
                ],
              ],
            ),
            const SizedBox(height: 16),
          ],
          _section(context, 'Fill'),
          _swatchRow(
            onColor: (v) => controller.setFillColor(VsdxColor(v)),
            onNone: controller.setNoFill,
          ),
          _OpacitySlider(
            label: 'Opacity',
            opacity: 1 - (controller.selectedFill?.foregroundTransparency ?? 0),
            onStart: controller.beginTransaction,
            onChanged: (v) => controller.setFillOpacity(v, transient: true),
            onEnd: controller.commitTransaction,
          ),
          const SizedBox(height: 16),
          _section(context, 'Line'),
          _swatchRow(
            onColor: (v) => controller.setLineColor(VsdxColor(v)),
            onNone: controller.setNoLine,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (final pt in <double>[0.5, 1, 2, 3])
                ActionChip(
                  label: Text('${pt == pt.roundToDouble() ? pt.toInt() : pt}pt'),
                  onPressed: () => controller.setLineWeight(pt / 72.0),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _dashDropdown(controller),
          _arrowToggles(controller),
          _OpacitySlider(
            label: 'Opacity',
            opacity: 1 - (controller.selectedLine?.transparency ?? 0),
            onStart: controller.beginTransaction,
            onChanged: (v) => controller.setLineOpacity(v, transient: true),
            onEnd: controller.commitTransaction,
          ),
          if (controller.hasConnectorSelected) ...[
            const SizedBox(height: 16),
            _section(context, 'Connector'),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Straight'),
                  selected: controller.selectedConnectorStraight,
                  onSelected: (_) =>
                      controller.setConnectorStyle(straight: true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Orthogonal'),
                  selected: !controller.selectedConnectorStraight,
                  onSelected: (_) =>
                      controller.setConnectorStyle(straight: false),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Shadow'),
              const Spacer(),
              Switch(
                value: controller.selectedHasShadow,
                onChanged: controller.setShadow,
              ),
            ],
          ),
          if (controller.selectedCharStyle != null) ...[
            const SizedBox(height: 16),
            _section(context, 'Text'),
            _textControls(context),
          ],
          const Divider(height: 32),
          FilledButton.tonalIcon(
            onPressed: controller.deleteSelection,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label, style: Theme.of(context).textTheme.labelLarge),
      );

  Widget _iconBtn(IconData icon, String tip, VoidCallback onTap) => IconButton(
        onPressed: onTap,
        icon: Icon(icon),
        tooltip: tip,
        visualDensity: VisualDensity.compact,
      );

  Widget _textControls(BuildContext context) {
    final cs = controller.selectedCharStyle;
    if (cs == null) return const SizedBox.shrink();
    final curPt = (cs.fontSizeInches * 72).round();
    final sizes = <int>{8, 9, 10, 11, 12, 14, 16, 18, 24, 28, 36, 48, curPt}
        .toList()
      ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            DropdownButton<int>(
              value: curPt,
              isDense: true,
              items: [
                for (final p in sizes)
                  DropdownMenuItem<int>(value: p, child: Text('$p pt')),
              ],
              onChanged: (p) {
                if (p != null) controller.setTextSizeInches(p / 72.0);
              },
            ),
            const Spacer(),
            IconButton(
              onPressed: () => controller.setBold(!cs.style.bold),
              isSelected: cs.style.bold,
              icon: const Icon(Icons.format_bold),
              tooltip: 'Bold',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: () => controller.setItalic(!cs.style.italic),
              isSelected: cs.style.italic,
              icon: const Icon(Icons.format_italic),
              tooltip: 'Italic',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: () => controller.setUnderline(!cs.underline),
              isSelected: cs.underline,
              icon: const Icon(Icons.format_underlined),
              tooltip: 'Underline',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _fontDropdown(cs),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final argb in _swatches)
              _SwatchButton(
                color: Color(argb),
                onTap: () => controller.setTextColor(VsdxColor(argb)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _iconBtn(Icons.format_align_left, 'Align left',
                () => controller.setTextAlign(VsdxHorzAlign.left)),
            _iconBtn(Icons.format_align_center, 'Align center',
                () => controller.setTextAlign(VsdxHorzAlign.center)),
            _iconBtn(Icons.format_align_right, 'Align right',
                () => controller.setTextAlign(VsdxHorzAlign.right)),
            _iconBtn(Icons.format_align_justify, 'Justify',
                () => controller.setTextAlign(VsdxHorzAlign.justify)),
          ],
        ),
        Row(
          children: [
            _vAlignBtn(Icons.vertical_align_top, 'Align top', VsdxVertAlign.top),
            _vAlignBtn(Icons.vertical_align_center, 'Align middle',
                VsdxVertAlign.middle),
            _vAlignBtn(Icons.vertical_align_bottom, 'Align bottom',
                VsdxVertAlign.bottom),
          ],
        ),
      ],
    );
  }

  static const List<String> _fonts = <String>[
    'Arial',
    'Calibri',
    'Times New Roman',
    'Courier New',
    'Georgia',
    'Verdana',
    'Comic Sans MS',
  ];

  Widget _fontDropdown(VsdxCharStyle cs) {
    final current = cs.fontFamily;
    final items = <String>{..._fonts, ?current}.toList();
    return Row(
      children: [
        const Icon(Icons.font_download_outlined, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<String>(
            value: current != null && items.contains(current) ? current : null,
            isExpanded: true,
            isDense: true,
            hint: const Text('Default'),
            items: [
              for (final f in items)
                DropdownMenuItem<String>(
                  value: f,
                  child: Text(f, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (f) {
              if (f != null) controller.setFontFamily(f);
            },
          ),
        ),
      ],
    );
  }

  IconButton _vAlignBtn(IconData icon, String tip, VsdxVertAlign v) =>
      IconButton(
        onPressed: () => controller.setTextVerticalAlign(v),
        isSelected: controller.selectedVerticalAlign == v,
        icon: Icon(icon),
        tooltip: tip,
        visualDensity: VisualDensity.compact,
      );

  Widget _swatchRow({
    required void Function(int argb) onColor,
    required VoidCallback onNone,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final argb in _swatches)
          _SwatchButton(color: Color(argb), onTap: () => onColor(argb)),
        InkWell(
          onTap: onNone,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey),
            ),
            child: const Icon(Icons.block, size: 18),
          ),
        ),
      ],
    );
  }

  static const Map<int, String> _dashPresets = <int, String>{
    1: 'Solid',
    2: 'Dashed',
    3: 'Dotted',
    4: 'Dash-dot',
  };

  Widget _dashDropdown(EditorController controller) {
    final pattern = controller.selectedLine?.pattern ?? 1;
    final value = _dashPresets.containsKey(pattern) ? pattern : 1;
    return Row(
      children: [
        const Icon(Icons.line_style, size: 18),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: value,
          isDense: true,
          items: [
            for (final e in _dashPresets.entries)
              DropdownMenuItem<int>(value: e.key, child: Text(e.value)),
          ],
          onChanged: (p) {
            if (p != null) controller.setLinePattern(p);
          },
        ),
      ],
    );
  }

  Widget _arrowToggles(EditorController controller) {
    final line = controller.selectedLine;
    final hasBegin = (line?.beginArrow ?? 0) != 0;
    final hasEnd = (line?.endArrow ?? 0) != 0;
    return Row(
      children: [
        const Text('Arrows', style: TextStyle(fontSize: 12)),
        const Spacer(),
        IconButton(
          onPressed: () => controller.setLineArrows(begin: hasBegin ? 0 : 1),
          isSelected: hasBegin,
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Start arrow',
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          onPressed: () => controller.setLineArrows(end: hasEnd ? 0 : 1),
          isSelected: hasEnd,
          icon: const Icon(Icons.arrow_forward),
          tooltip: 'End arrow',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

/// Compact opacity slider (0–100%) with transactional live preview so the drag
/// records a single undo step.
class _OpacitySlider extends StatelessWidget {
  const _OpacitySlider({
    required this.label,
    required this.opacity,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
  });

  final String label;
  final double opacity;
  final VoidCallback onStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final v = opacity.clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(label, style: const TextStyle(fontSize: 11)),
        ),
        Expanded(
          child: Slider(
            value: v,
            onChangeStart: (_) => onStart(),
            onChanged: onChanged,
            onChangeEnd: (_) => onEnd(),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '${(v * 100).round()}%',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _SwatchButton extends StatelessWidget {
  const _SwatchButton({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade500),
        ),
      ),
    );
  }
}
