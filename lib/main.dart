import 'dart:convert';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vsdx/vsdx.dart';

import 'editor/editor_controller.dart';
import 'editor/page_canvas.dart';
import 'io/document_io.dart';
import 'io/image_export.dart';
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
  final EditorController _controller = EditorController();
  final RecentFiles _recentFiles = RecentFiles();
  List<String> _recents = const <String>[];
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _recentFiles.load().then((r) {
      if (mounted) setState(() => _recents = r);
    });
  }

  Future<void> _addRecent(String? path) async {
    if (path == null) return;
    final r = await _recentFiles.add(path);
    if (mounted) setState(() => _recents = r);
  }

  Future<void> _openPath(String path) async {
    if (!await _confirmDiscard()) return;
    try {
      final picked = await readDroppedFile(path);
      await _controller.openBytes(
        picked.bytes,
        path: picked.path,
        name: picked.name,
      );
      _reportErrorIfAny();
      if (!_controller.hasDocument) return;
      await _addRecent(path);
    } catch (e) {
      _snack('Could not open $path');
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _open() async {
    if (!await _confirmDiscard()) return;
    final picked = await pickVisioFile();
    if (picked == null) return;
    await _controller.openBytes(
      picked.bytes,
      path: picked.path,
      name: picked.name,
    );
    _reportErrorIfAny();
    if (_controller.hasDocument) await _addRecent(picked.path);
  }

  Future<void> _onDrop(DropDoneDetails details) async {
    setState(() => _dragging = false);
    if (details.files.isEmpty) return;
    final path = details.files.first.path;
    if (!hasVisioExtension(path)) {
      _snack('Unsupported file. Drop a .vsdx / .vsdm / .vstx file.');
      return;
    }
    final picked = await readDroppedFile(path);
    await _controller.openBytes(
      picked.bytes,
      path: picked.path,
      name: picked.name,
    );
    _reportErrorIfAny();
    if (_controller.hasDocument) await _addRecent(picked.path);
  }

  void _reportErrorIfAny() {
    final err = _controller.error;
    if (err != null) _snack('Could not open file: $err');
  }

  Future<bool> _confirmDiscard() async {
    if (!_controller.isDirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text('The current drawing has unsaved changes.'),
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

  Future<void> _newDoc() async {
    if (await _confirmDiscard()) _controller.newDocument();
  }

  Future<void> _close() async {
    if (await _confirmDiscard()) _controller.closeDocument();
  }

  Future<void> _save() async {
    final c = _controller;
    if (!c.hasDocument) return;
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
    final c = _controller;
    if (!c.hasDocument) return;
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
    final doc = _controller.document;
    if (doc == null) return;
    final path = await pickExportLocation(
      ext: 'svg',
      suggestedName: '${baseName(_controller.fileName)}.svg',
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
    final doc = _controller.document;
    final page = _controller.currentPage;
    if (doc == null || page == null) return;
    final path = await pickExportLocation(
      ext: 'png',
      suggestedName: '${baseName(_controller.fileName)}.png',
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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          if (c.hasDocument) _save();
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () {
          if (c.canUndo) c.undo();
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            () {
          if (c.canRedo) c.redo();
        },
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true): () {
          if (c.hasSelection) c.duplicateSelection();
        },
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () {
          if (c.hasSelection) c.copySelection();
        },
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () {
          if (c.hasClipboard) c.paste();
        },
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _newDoc,
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(
          '${c.isDirty ? '• ' : ''}${c.fileName ?? 'Editor for Visio Diagrams'}',
        ),
        actions: [
          if (c.hasDocument) ...[
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
              onPressed: c.toggleGrid,
              icon: Icon(c.showGrid ? Icons.grid_on : Icons.grid_off),
              tooltip: 'Toggle grid',
            ),
            IconButton(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              tooltip: 'Save',
            ),
          ],
          IconButton(
            onPressed: _newDoc,
            icon: const Icon(Icons.note_add_outlined),
            tooltip: 'New drawing',
          ),
          IconButton(
            onPressed: _open,
            icon: const Icon(Icons.folder_open_outlined),
            tooltip: 'Open a Visio drawing',
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
          if (c.hasDocument)
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
                  case 'snap':
                    c.toggleSnap();
                  case 'close':
                    _close();
                }
              },
              itemBuilder: (context) => [
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
                CheckedPopupMenuItem<String>(
                  value: 'snap',
                  checked: c.snapToGrid,
                  child: const Text('Snap to grid'),
                ),
                const PopupMenuItem<String>(
                  value: 'close',
                  child: Text('Close drawing'),
                ),
              ],
            ),
        ],
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
      bottomNavigationBar: c.pageCount > 1 ? _pageTabs(c) : null,
      ),
    );
  }

  Widget _buildBody(EditorController c) {
    if (c.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!c.hasDocument || c.currentPage == null) {
      return _EmptyState(onOpen: _open, onNew: _newDoc);
    }
    return Row(
      children: [
        _ToolStrip(controller: c),
        const VerticalDivider(width: 1),
        Expanded(
          child: PageCanvas(controller: c, onRequestTextEdit: _editText),
        ),
        if (c.hasSelection) ...[
          const VerticalDivider(width: 1),
          _PropertyPanel(controller: c),
        ],
      ],
    );
  }

  Future<void> _editText(int shapeId) async {
    final shape = _controller.currentPage?.findShapeById(shapeId);
    if (shape == null) return;
    final textController = TextEditingController(text: shape.text ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit shape text'),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(hintText: 'Type text…'),
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
    if (result != null) _controller.setShapeText(shapeId, result);
    textController.dispose();
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
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: c.pageCount,
          itemBuilder: (context, i) {
            final page = c.document!.pages[i];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
              child: ChoiceChip(
                label: Text(page.name),
                selected: i == c.currentPageIndex,
                onSelected: (_) => c.selectPage(i),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onOpen, required this.onNew});

  final VoidCallback onOpen;
  final VoidCallback onNew;

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
            'Create a new drawing, or drag & drop / open a .vsdx file.',
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
          const SizedBox(height: 16),
          _section(context, 'Fill'),
          _swatchRow(
            onColor: (v) => controller.setFillColor(VsdxColor(v)),
            onNone: controller.setNoFill,
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
