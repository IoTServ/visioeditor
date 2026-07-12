import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vsdx/vsdx.dart';

import 'editor/canvas_camera.dart';
import 'editor/edit_data_dialog.dart';
import 'editor/edit_link_dialog.dart';
import 'editor/editor_controller.dart';
import 'editor/editor_workspace.dart';
import 'editor/outline_panel.dart';
import 'editor/page_canvas.dart';
import 'editor/ruler.dart';
import 'editor/stencils.dart';
import 'render/arrow_library.dart';
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
  bool _showFind = false;
  bool _showOutline = false;
  bool _showRulers = true;
  final CanvasCamera _camera = CanvasCamera();

  EditorController? get _c => _workspace.active;

  void _openFind() {
    if (_c == null || !_c!.hasDocument) return;
    setState(() => _showFind = true);
  }

  void _closeFind() {
    setState(() => _showFind = false);
    _c?.clearFind();
  }

  /// Open drawio's "Edit Data" (Cmd+M) for the single selected shape.
  Future<void> _editData() async {
    final c = _c;
    final id = c?.singleSelectedId;
    if (c == null || id == null) return;
    await showEditDataDialog(context, c, id);
  }

  /// Open drawio's "Edit Link" (Cmd+K) for the single selected shape.
  Future<void> _editLink() async {
    final c = _c;
    final id = c?.singleSelectedId;
    if (c == null || id == null) return;
    await showEditLinkDialog(context, c, id);
  }

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
    _camera.dispose();
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
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () {
          if (c != null && c.hasSelection) c.rotateSelection90();
        },
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true, shift: true):
            () {
          if (c != null && c.hasSelection) {
            c.rotateSelection90(clockwise: false);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openFind,
        const SingleActivator(LogicalKeyboardKey.keyM, meta: true): () {
          if (c != null && c.singleSelectedId != null) _editData();
        },
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () {
          if (c != null && c.singleSelectedId != null) _editLink();
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
                onPressed: () => setState(() => _showOutline = !_showOutline),
                icon: const Icon(Icons.map_outlined),
                isSelected: _showOutline,
                tooltip: 'Outline',
              ),
              IconButton(
                onPressed: () => setState(() => _showRulers = !_showRulers),
                icon: const Icon(Icons.straighten),
                isSelected: _showRulers,
                tooltip: 'Rulers',
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
                    case 'find':
                      _openFind();
                    case 'editData':
                      _editData();
                    case 'editLink':
                      _editLink();
                    case 'zoomSel':
                      c.revealSelection();
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
                  const PopupMenuItem<String>(
                    value: 'find',
                    child: Text('Find… (Cmd+F)'),
                  ),
                  PopupMenuItem<String>(
                    value: 'editData',
                    enabled: c.singleSelectedId != null,
                    child: const Text('Edit Data… (Cmd+M)'),
                  ),
                  PopupMenuItem<String>(
                    value: 'editLink',
                    enabled: c.singleSelectedId != null,
                    child: const Text('Edit Link… (Cmd+K)'),
                  ),
                  PopupMenuItem<String>(
                    value: 'zoomSel',
                    enabled: c.hasSelection,
                    child: const Text('Zoom to Selection'),
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
              if (_showFind && c != null && c.hasDocument)
                Positioned(
                  top: 12,
                  right: 12,
                  child: _FindBar(controller: c, onClose: _closeFind),
                ),
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
          child: Stack(
            children: [
              Positioned.fill(
                child: PageCanvas(controller: c, camera: _camera),
              ),
              if (_showRulers)
                Positioned.fill(
                  child: RulerOverlay(controller: c, camera: _camera),
                ),
              if (_showOutline)
                Positioned(
                  right: 16,
                  bottom: 64,
                  child: OutlinePanel(
                    controller: c,
                    camera: _camera,
                    onClose: () => setState(() => _showOutline = false),
                  ),
                ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // drawio always keeps the Format panel docked: a shape inspector when
        // something is selected, otherwise the page/"Diagram" settings.
        if (c.hasSelection)
          _PropertyPanel(controller: c)
        else
          _PageFormatPanel(controller: c),
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
            tool(EditorTool.text, Icons.text_fields, 'Text'),
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
          Wrap(
            children: [
              _iconBtn(Icons.flip_to_front, 'Bring to front',
                  controller.bringSelectionToFront),
              _iconBtn(Icons.flip_to_back, 'Send to back',
                  controller.sendSelectionToBack),
              _iconBtn(Icons.arrow_upward, 'Bring forward',
                  controller.bringSelectionForward),
              _iconBtn(Icons.arrow_downward, 'Send backward',
                  controller.sendSelectionBackward),
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
          _section(context, 'Arrange'),
          Wrap(
            children: [
              _iconBtn(Icons.flip, 'Flip horizontal', controller.flipHorizontal),
              Transform.rotate(
                angle: math.pi / 2,
                child: _iconBtn(
                    Icons.flip, 'Flip vertical', controller.flipVertical),
              ),
              _iconBtn(Icons.rotate_left, 'Rotate 90° left',
                  () => controller.rotateSelection90(clockwise: false)),
              _iconBtn(Icons.rotate_right, 'Rotate 90° right (Cmd+R)',
                  () => controller.rotateSelection90()),
            ],
          ),
          _arrangeFields(controller),
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
          _roundedControl(context, controller),
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
          const SizedBox(height: 8),
          _arrowPickers(controller),
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
            Wrap(
              spacing: 8,
              children: [
                for (final s in ConnectorRouteStyle.values)
                  ChoiceChip(
                    label: Text(switch (s) {
                      ConnectorRouteStyle.straight => 'Straight',
                      ConnectorRouteStyle.orthogonal => 'Orthogonal',
                      ConnectorRouteStyle.curved => 'Curved',
                    }),
                    selected: controller.selectedConnectorRouteStyle == s,
                    onSelected: (_) => controller.setConnectorRouteStyle(s),
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
          if (controller.singleSelectedId != null) ...[
            const SizedBox(height: 16),
            _dataSection(context),
            const SizedBox(height: 16),
            _linkSection(context),
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

  /// Shape Data (drawio "Edit Data"): a compact read-out of the single
  /// selection's custom properties plus a button to open the editor (Cmd+M).
  Widget _dataSection(BuildContext context) {
    final id = controller.singleSelectedId;
    if (id == null) return const SizedBox.shrink();
    final props = controller.selectedProperties;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(context, 'Data'),
        if (props.isEmpty)
          Text(
            'No shape data',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          )
        else
          for (final p in props)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      p.displayLabel,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Text(
                      p.displayValue,
                      style:
                          TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => showEditDataDialog(context, controller, id),
          icon: const Icon(Icons.data_object, size: 18),
          label: const Text('Edit Data…'),
        ),
      ],
    );
  }

  /// Hyperlink (drawio "Edit Link"): show the single selection's current link
  /// (if any) plus a button to open the editor (Cmd+K).
  Widget _linkSection(BuildContext context) {
    final id = controller.singleSelectedId;
    if (id == null) return const SizedBox.shrink();
    final link = controller.selectedLink;
    final target = link?.effectiveTarget;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(context, 'Link'),
        if (target == null || target.isEmpty)
          Text(
            'No link',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          )
        else
          Text(
            (link!.description?.isNotEmpty ?? false)
                ? '${link.description}  →  $target'
                : target,
            style: TextStyle(fontSize: 12, color: scheme.primary),
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => showEditLinkDialog(context, controller, id),
          icon: const Icon(Icons.link, size: 18),
          label: const Text('Edit Link…'),
        ),
      ],
    );
  }

  /// Corner-radius slider for a single rectangular selection (drawio's
  /// "Rounded" + arc size). Hidden for non-rectangular / multi selections.
  Widget _roundedControl(BuildContext context, EditorController controller) {
    final radius = controller.selectedCornerRadius;
    final s = controller.singleSelected;
    if (radius == null || s == null) return const SizedBox.shrink();
    final maxR = math.min(s.width, s.height) / 2;
    if (maxR <= 0) return const SizedBox.shrink();
    final v = radius.clamp(0.0, maxR);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            const SizedBox(
                width: 48,
                child: Text('Corners', style: TextStyle(fontSize: 11))),
            Expanded(
              child: Slider(
                value: v,
                max: maxR,
                onChangeStart: (_) => controller.beginTransaction(),
                onChanged: (x) => controller.setCornerRadius(x, transient: true),
                onChangeEnd: (_) => controller.commitTransaction(),
              ),
            ),
            SizedBox(
              width: 34,
              child: Text(
                '${(v * 100).round() / 100}"',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Numeric position / size / angle fields for a single selection (drawio's
  /// Arrange tab). Hidden when zero or many shapes are selected.
  Widget _arrangeFields(EditorController controller) {
    final g = controller.selectedGeometry;
    if (g == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _NumField(
                  label: 'X',
                  value: g.x,
                  onSubmit: controller.setSelectedX,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumField(
                  label: 'Y',
                  value: g.y,
                  onSubmit: controller.setSelectedY,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _NumField(
                  label: 'W',
                  value: g.w,
                  onSubmit: controller.setSelectedWidth,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumField(
                  label: 'H',
                  value: g.h,
                  onSubmit: controller.setSelectedHeight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _NumField(
                  label: '∠°',
                  value: g.angleDeg,
                  onSubmit: controller.setSelectedAngleDegrees,
                ),
              ),
              const Spacer(),
            ],
          ),
        ],
      ),
    );
  }

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

  /// Curated arrowhead types (Visio `BeginArrow`/`EndArrow` ids → labels),
  /// mirroring drawio's start/end arrow menus.
  static const Map<int, String> _arrowTypes = <int, String>{
    0: 'None',
    4: 'Filled',
    1: 'Open',
    3: 'Thin',
    7: 'Stealth',
    10: 'Diamond',
    11: 'Open diamond',
    14: 'Circle',
  };

  Widget _arrowPickers(EditorController controller) {
    final line = controller.selectedLine;
    final begin = line?.beginArrow ?? 0;
    final end = line?.endArrow ?? 0;
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(
                width: 40,
                child: Text('Start', style: TextStyle(fontSize: 12))),
            Expanded(
              child: _arrowDropdown(
                  begin, controller.setBeginArrow, flip: true),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(
                width: 40,
                child: Text('End', style: TextStyle(fontSize: 12))),
            Expanded(
              child:
                  _arrowDropdown(end, controller.setEndArrow, flip: false),
            ),
          ],
        ),
      ],
    );
  }

  Widget _arrowDropdown(
    int value,
    ValueChanged<int> onChanged, {
    required bool flip,
  }) {
    final ids = <int>{..._arrowTypes.keys, value}.toList()..sort();
    String label(int id) => _arrowTypes[id] ?? 'Arrow #$id';
    return DropdownButton<int>(
      value: value,
      isExpanded: true,
      isDense: true,
      items: [
        for (final id in ids)
          DropdownMenuItem<int>(
            value: id,
            child: Row(
              children: [
                SizedBox(
                  width: 38,
                  height: 14,
                  child: id == 0
                      ? const SizedBox.shrink()
                      : _ArrowPreview(arrowId: id, flip: flip),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label(id),
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

/// A named paper size (portrait width × height, inches).
class _Paper {
  const _Paper(this.name, this.width, this.height);
  final String name;
  final double width;
  final double height;
}

/// Right-hand Format panel shown when nothing is selected — drawio's "Diagram"
/// tab: grid / snap toggles, page background colour, and paper size (preset +
/// orientation + custom width/height). All changes round-trip via the writer.
class _PageFormatPanel extends StatelessWidget {
  const _PageFormatPanel({required this.controller});

  final EditorController controller;

  static const List<int> _backgrounds = <int>[
    0xFFFFFFFF,
    0xFFF5F5F5,
    0xFFFFF9C4,
    0xFFE3F2FD,
    0xFFE8F5E9,
    0xFFFCE4EC,
    0xFF37474F,
    0xFF000000,
  ];

  /// Common paper sizes as portrait (width, height) in inches.
  static const List<_Paper> _papers = <_Paper>[
    _Paper('Letter', 8.5, 11),
    _Paper('Legal', 8.5, 14),
    _Paper('Tabloid', 11, 17),
    _Paper('A3', 11.69, 16.54),
    _Paper('A4', 8.27, 11.69),
    _Paper('A5', 5.83, 8.27),
    _Paper('A6', 4.13, 5.83),
    _Paper('B4', 9.84, 13.9),
    _Paper('B5', 6.93, 9.84),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = controller.pageSize;
    if (size == null) return const SizedBox(width: 232);
    final w = size.width;
    final h = size.height;
    final landscape = controller.pageIsLandscape;
    final matched = _matchPaper(w, h);
    final bg = controller.pageBackgroundColor;

    return SizedBox(
      width: 232,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Diagram', style: theme.textTheme.titleSmall),
          const SizedBox(height: 16),
          Text('View', style: theme.textTheme.labelLarge),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Grid'),
            value: controller.showGrid,
            onChanged: (_) => controller.toggleGrid(),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Snap to grid'),
            value: controller.snapToGrid,
            onChanged: (_) => controller.toggleSnap(),
          ),
          const SizedBox(height: 16),
          Text('Background', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final argb in _backgrounds)
                _SwatchButton(
                  color: Color(argb),
                  selected: bg?.value == argb,
                  onTap: () => controller.setBackgroundColor(VsdxColor(argb)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Paper Size', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          DropdownButton<_Paper>(
            value: matched,
            isExpanded: true,
            isDense: true,
            hint: const Text('Custom'),
            items: [
              for (final p in _papers)
                DropdownMenuItem<_Paper>(
                  value: p,
                  child: Text(
                    '${p.name}   ${_dim(p.width)} × ${_dim(p.height)} in',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (p) {
              if (p == null) return;
              controller.setPageSize(
                landscape ? p.height : p.width,
                landscape ? p.width : p.height,
              );
            },
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment<bool>(value: false, label: Text('Portrait')),
              ButtonSegment<bool>(value: true, label: Text('Landscape')),
            ],
            selected: <bool>{landscape},
            onSelectionChanged: (s) => controller.setPageLandscape(s.first),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NumField(
                  label: 'W',
                  value: w,
                  onSubmit: (v) => controller.setPageSize(v, h),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumField(
                  label: 'H',
                  value: h,
                  onSubmit: (v) => controller.setPageSize(w, v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The preset matching (w, h) in either orientation, or `null` for a custom
  /// size.
  _Paper? _matchPaper(double w, double h) {
    final lo = math.min(w, h);
    final hi = math.max(w, h);
    for (final p in _papers) {
      if ((p.width - lo).abs() < 0.05 && (p.height - hi).abs() < 0.05) {
        return p;
      }
    }
    return null;
  }

  static String _dim(double v) {
    final r = (v * 100).round() / 100;
    return r == r.roundToDouble() ? r.toInt().toString() : '$r';
  }
}

/// Small preview of an arrowhead ([arrowId]) drawn at the end of a stub line.
/// When [flip] is set the head points left (used for the start arrow).
class _ArrowPreview extends StatelessWidget {
  const _ArrowPreview({required this.arrowId, this.flip = false});

  final int arrowId;
  final bool flip;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(38, 14),
      painter: _ArrowPreviewPainter(
        arrowId,
        Theme.of(context).colorScheme.onSurface,
        flip,
      ),
    );
  }
}

class _ArrowPreviewPainter extends CustomPainter {
  _ArrowPreviewPainter(this.id, this.color, this.flip);

  final int id;
  final Color color;
  final bool flip;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(2, y), Offset(size.width - 2, y), line);
    if (id == 0) return;
    final d = arrowDescriptor(id);
    if (d == null) return;
    const s = 9.0;
    final tipX = flip ? 2.0 : size.width - 2;
    canvas
      ..save()
      ..translate(tipX, y)
      ..scale(flip ? -s : s, s);
    final p = Paint()
      ..color = color
      ..style = d.filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1.2 / s;
    canvas
      ..drawPath(d.path, p)
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _ArrowPreviewPainter old) =>
      old.id != id || old.color != color || old.flip != flip;
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

/// A compact numeric text field for the Arrange panel. Reflects an external
/// [value] while idle, and commits the parsed number on Enter or focus loss.
class _NumField extends StatefulWidget {
  const _NumField({
    required this.label,
    required this.value,
    required this.onSubmit,
  });

  final String label;
  final double value;
  final ValueChanged<double> onSubmit;

  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final TextEditingController _c =
      TextEditingController(text: _fmt(widget.value));
  late final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _NumField old) {
    super.didUpdateWidget(old);
    // Refresh from the model unless the user is actively editing this field.
    if (!_focus.hasFocus && widget.value != old.value) {
      _c.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final v = double.tryParse(_c.text.trim());
    if (v != null && v != widget.value) {
      widget.onSubmit(v);
    } else {
      _c.text = _fmt(widget.value);
    }
  }

  static String _fmt(double v) {
    final r = (v * 100).roundToDouble() / 100;
    return r == r.roundToDouble() ? r.toInt().toString() : '$r';
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      focusNode: _focus,
      keyboardType: const TextInputType.numberWithOptions(
          signed: true, decimal: true),
      textAlign: TextAlign.right,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        prefixText: '${widget.label} ',
        prefixStyle: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (_) => _commit(),
    );
  }
}

/// Floating Find bar (drawio Cmd+F). Filters shapes by text/name on the
/// current page, shows a match counter, and cycles matches with the arrows or
/// Enter / Shift+Enter. Escape closes it.
class _FindBar extends StatefulWidget {
  const _FindBar({required this.controller, required this.onClose});

  final EditorController controller;
  final VoidCallback onClose;

  @override
  State<_FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<_FindBar> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _text.text = widget.controller.findQuery;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      color: scheme.surface,
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final count = widget.controller.findMatchCount;
          final ord = widget.controller.findCurrentOrdinal;
          final label = count == 0
              ? (widget.controller.findQuery.trim().isEmpty ? '' : 'No results')
              : '$ord / $count';
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.search, size: 18),
                const SizedBox(width: 6),
                SizedBox(
                  width: 180,
                  child: CallbackShortcuts(
                    bindings: <ShortcutActivator, VoidCallback>{
                      const SingleActivator(LogicalKeyboardKey.escape):
                          widget.onClose,
                    },
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Find shapes…',
                        border: InputBorder.none,
                      ),
                      onChanged: widget.controller.updateFind,
                      onSubmitted: (_) {
                        if (HardwareKeyboard.instance.isShiftPressed) {
                          widget.controller.findPrevious();
                        } else {
                          widget.controller.findNext();
                        }
                      },
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ),
                IconButton(
                  onPressed: count == 0 ? null : widget.controller.findPrevious,
                  icon: const Icon(Icons.keyboard_arrow_up),
                  tooltip: 'Previous (Shift+Enter)',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: count == 0 ? null : widget.controller.findNext,
                  icon: const Icon(Icons.keyboard_arrow_down),
                  tooltip: 'Next (Enter)',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Close (Esc)',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SwatchButton extends StatelessWidget {
  const _SwatchButton({
    required this.color,
    required this.onTap,
    this.selected = false,
  });

  final Color color;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? scheme.primary : Colors.grey.shade500,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}
